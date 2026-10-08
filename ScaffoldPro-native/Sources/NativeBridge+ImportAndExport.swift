import Cocoa
import WebKit
import UniformTypeIdentifiers
import CoreGraphics
import CoreText
import PDFKit
import Vision
import Security
import Network
import CryptoKit

extension NativeBridge {
    // ---- Importing a quotation from a file ----

    /// Reads the chosen file on this Mac (its text, or the words off a
    /// scan) and makes out what it can; the file waits in a temporary
    /// folder, under the draft's token, until the quotation is made.
    func handleImportQuotationRead(id: String, payload: [String: Any]) {
        let name = ((payload["name"] as? String) ?? "").replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        guard !name.isEmpty, let base64 = payload["base64"] as? String, let data = Data(base64Encoded: base64) else {
            respond(id: id, encodable: QuotationImportDraft(ok: false, error: "The file couldn’t be read."))
            return
        }
        let token = UUID().uuidString
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ScaffoldPro-import-\(token)", isDirectory: true)
        let url = folder.appendingPathComponent(name)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try data.write(to: url)
        } catch {
            respond(id: id, encodable: QuotationImportDraft(ok: false, error: "The file couldn’t be saved for reading (\(error.localizedDescription))."))
            return
        }
        let priceItems = db.priceListItemsStore.readAll().filter { !$0.isArchived }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (text, ocr) = QuotationImportReader.text(of: url)
            let parsed = QuotationImportReader.parse(text, priceItems: priceItems)
            DispatchQueue.main.async {
                guard let self = self else { return }
                var draft = parsed
                self.pendingQuotationImports[token] = (url, text)
                draft.token = token
                draft.fileName = name
                draft.source = ocr ? "ocr" : "text"
                draft.textPreview = String(text.prefix(3000))
                draft.aiReady = QuotationAI.shared.ready
                draft.unsure = draft.items.count < 2 || (ocr && draft.items.count < 4)
                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !QuotationAI.shared.ready {
                    draft.error = "No text could be read from this file. Set up the AI in Settings › AI Import to read it, or add the items by hand."
                }
                self.respond(id: id, encodable: draft)
            }
        }
    }

    /// The same file read by the AI instead.
    func handleImportQuotationAI(id: String, payload: [String: Any]) {
        let token = (payload["token"] as? String) ?? ""
        guard let pending = pendingQuotationImports[token] else {
            respond(id: id, encodable: QuotationImportDraft(ok: false, error: "Choose the file again."))
            return
        }
        let priceItems = db.priceListItemsStore.readAll().filter { !$0.isArchived }
        QuotationAI.shared.read(fileURL: pending.url, text: pending.text) { [weak self] json, error in
            guard let self = self else { return }
            guard let json = json else {
                self.respond(id: id, encodable: QuotationImportDraft(ok: false, error: error ?? "The AI couldn’t read it."))
                return
            }
            var draft = QuotationImportReader.draft(fromAI: json, priceItems: priceItems)
            draft.token = token
            draft.fileName = pending.url.lastPathComponent
            draft.source = "ai"
            draft.textPreview = String(pending.text.prefix(3000))
            draft.aiReady = true
            self.respond(id: id, encodable: draft)
        }
    }

    /// Makes the quotation from the checked items, and keeps the file with
    /// the project's documents, filed with the new quotation.
    func handleImportQuotationCreate(id: String, payload: [String: Any]) {
        let token = (payload["token"] as? String) ?? ""
        guard let project = db.getProjectByNumber((payload["projectNumber"] as? String) ?? "") else {
            respond(id: id, encodable: LeadSaveResult(ok: false, error: "Project not found."))
            return
        }
        var lines: [ImportedQuotationLine] = []
        if let raw = payload["items"], let data = try? JSONSerialization.data(withJSONObject: raw) {
            lines = (try? JSONDecoder().decode([ImportedQuotationLine].self, from: data)) ?? []
        }
        let q = db.createImportedQuotation(projectId: project.id, projectNumber: project.projectNumber,
                                           pricingMode: (payload["pricingMode"] as? String) ?? "Rental",
                                           subject: payload["subject"] as? String, clientRef: payload["clientRef"] as? String,
                                           currency: payload["currency"] as? String, lines: lines)
        var note: String? = nil
        if let pending = pendingQuotationImports[token] {
            do {
                let doc = try addDocumentFile(pending.url, project: project, category: "Correspondence")
                let old = nonBlank(payload["oldNumber"] as? String)
                _ = db.updateDocumentDescription(id: doc.id, description: "The original of \(q.quotationNumber), imported\(old.map { " (was \($0))" } ?? "")")
                _ = db.setDocumentLink(id: doc.id, kind: "Quotation", linkedId: q.id)
                db.setQuotationImportedFile(quotationId: q.id, documentId: doc.id)
            } catch {
                note = "The quotation was made, but the original file couldn’t be kept (\(error.localizedDescription))."
            }
            try? FileManager.default.removeItem(at: pending.url.deletingLastPathComponent())
            pendingQuotationImports[token] = nil
        }
        db.logActivity(projectId: project.id, "Quotation imported from a file", reference: q.quotationNumber)
        respond(id: id, encodable: LeadSaveResult(ok: true, error: note, id: q.id))
    }

    func handleAddQuotationLineItem(id: String, payload: [String: Any]) {
        let quotationId = (payload["quotationId"] as? String) ?? ""
        let sourceKey = payload["sourceKey"] as? String
        let priceListItemId = payload["priceListItemId"] as? String
        let itemCode = (payload["itemCode"] as? String) ?? ""
        let description = (payload["description"] as? String) ?? ""
        let unit = (payload["unit"] as? String) ?? "pc"
        let quantity = (payload["quantity"] as? Double) ?? 1
        let appliedUnitPrice = (payload["appliedUnitPrice"] as? Double) ?? 0
        let section = payload["section"] as? String

        guard !description.isEmpty else {
            respond(id: id, encodable: QuotationActionResult(ok: false, error: "Description is required."))
            return
        }
        guard quantity > 0 else {
            respond(id: id, encodable: QuotationActionResult(ok: false, error: "Quantity must be greater than zero."))
            return
        }

        if let error = db.addQuotationLineItem(
            quotationId: quotationId, sourceKey: sourceKey, priceListItemId: priceListItemId,
            itemCode: itemCode, description: description, unit: unit, quantity: quantity,
            appliedUnitPrice: appliedUnitPrice, section: section
        ) {
            respond(id: id, encodable: QuotationActionResult(ok: false, error: error))
        } else {
            respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
        }
    }

    func handleUpdateQuotationHeader(id: String, payload: [String: Any]) {
        let qid = (payload["id"] as? String) ?? ""
        let validUntil = payload["validUntil"] as? String
        let paymentTerms = payload["paymentTerms"] as? String
        let notes = payload["notes"] as? String
        let discountType = (payload["discountType"] as? String) ?? "None"
        let discountValue = (payload["discountValue"] as? Double) ?? 0
        let taxRatePercent = (payload["taxRatePercent"] as? Double) ?? 0
        let pricingMode = (payload["pricingMode"] as? String) ?? "Rental"
        let markupPercent = payload["markupPercent"] as? Double

        if let day = payload["quotationDate"] as? String, !day.isEmpty,
           let error = db.updateQuotationDate(id: qid, day: day) {
            respond(id: id, encodable: QuotationActionResult(ok: false, error: error))
            return
        }
        if let error = db.updateQuotationHeader(
            id: qid, validUntil: validUntil, paymentTerms: paymentTerms, notes: notes,
            discountType: discountType, discountValue: discountValue, taxRatePercent: taxRatePercent,
            pricingMode: pricingMode, markupPercent: markupPercent
        ) {
            respond(id: id, encodable: QuotationActionResult(ok: false, error: error))
        } else {
            respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
        }
    }

    func handleCreateInvoice(id: String, payload: [String: Any]) {
        let projectId = (payload["projectId"] as? String) ?? ""
        let projectNumber = (payload["projectNumber"] as? String) ?? ""
        guard !projectId.isEmpty, !projectNumber.isEmpty else {
            respondError(id: id, message: "Missing project.")
            return
        }
        // From delivery notes (what was delivered), or a whole quotation.
        let noteIds = (payload["deliveryNoteIds"] as? [String]) ?? []
        let result = noteIds.isEmpty
            ? db.createInvoice(projectId: projectId, projectNumber: projectNumber,
                               sourceQuotationId: (payload["quotationId"] as? String) ?? "",
                               rentalMonths: payload["rentalMonths"] as? Int,
                               includeDelivery: (payload["includeDelivery"] as? Bool) ?? true,
                               includeOtherCharges: (payload["includeOtherCharges"] as? Bool) ?? true)
            : db.createInvoice(projectId: projectId, projectNumber: projectNumber, deliveryNoteIds: noteIds,
                               rentalMonths: payload["rentalMonths"] as? Int,
                               includeDelivery: (payload["includeDelivery"] as? Bool) ?? true,
                               includeOtherCharges: (payload["includeOtherCharges"] as? Bool) ?? true)
        switch result {
        case .success(let invoice): respond(id: id, encodable: invoice)
        case .failure(let e): respondError(id: id, message: e.message)
        }
    }

    func handleAddInvoiceLineItem(id: String, payload: [String: Any]) {
        let invoiceId = (payload["invoiceId"] as? String) ?? ""
        let sourceKey = payload["sourceKey"] as? String
        let priceListItemId = payload["priceListItemId"] as? String
        let itemCode = (payload["itemCode"] as? String) ?? ""
        let description = (payload["description"] as? String) ?? ""
        let unit = (payload["unit"] as? String) ?? "pc"
        let quantity = (payload["quantity"] as? Double) ?? 1
        let appliedUnitPrice = (payload["appliedUnitPrice"] as? Double) ?? 0
        let section = payload["section"] as? String

        guard !description.isEmpty else {
            respond(id: id, encodable: InvoiceActionResult(ok: false, error: "Description is required."))
            return
        }
        guard quantity > 0 else {
            respond(id: id, encodable: InvoiceActionResult(ok: false, error: "Quantity must be greater than zero."))
            return
        }

        if let error = db.addInvoiceLineItem(
            invoiceId: invoiceId, sourceKey: sourceKey, priceListItemId: priceListItemId,
            itemCode: itemCode, description: description, unit: unit, quantity: quantity,
            appliedUnitPrice: appliedUnitPrice, section: section
        ) {
            respond(id: id, encodable: InvoiceActionResult(ok: false, error: error))
        } else {
            respond(id: id, encodable: InvoiceActionResult(ok: true, error: nil))
        }
    }

    func handleUpdateInvoiceHeader(id: String, payload: [String: Any]) {
        let invId = (payload["id"] as? String) ?? ""
        let dueDate = payload["dueDate"] as? String
        let paymentTerms = payload["paymentTerms"] as? String
        let notes = payload["notes"] as? String
        let discountType = (payload["discountType"] as? String) ?? "None"
        let discountValue = (payload["discountValue"] as? Double) ?? 0
        let taxRatePercent = (payload["taxRatePercent"] as? Double) ?? 0

        if let day = payload["invoiceDate"] as? String, !day.isEmpty,
           let error = db.updateInvoiceDate(id: invId, day: day) {
            respond(id: id, encodable: InvoiceActionResult(ok: false, error: error))
            return
        }
        if let error = db.updateInvoiceHeader(
            id: invId, dueDate: dueDate, paymentTerms: paymentTerms, notes: notes,
            discountType: discountType, discountValue: discountValue, taxRatePercent: taxRatePercent
        ) {
            respond(id: id, encodable: InvoiceActionResult(ok: false, error: error))
        } else {
            respond(id: id, encodable: InvoiceActionResult(ok: true, error: nil))
        }
    }

    func handleCreateDeliveryNote(id: String, payload: [String: Any]) {
        let projectId = (payload["projectId"] as? String) ?? ""
        let projectNumber = (payload["projectNumber"] as? String) ?? ""
        let sourceQuotationId = payload["quotationId"] as? String
        let sourceInvoiceId = payload["invoiceId"] as? String
        guard !projectId.isEmpty, !projectNumber.isEmpty else {
            respondError(id: id, message: "Missing project.")
            return
        }
        let note = db.createDeliveryNote(projectId: projectId, projectNumber: projectNumber, sourceQuotationId: sourceQuotationId, sourceInvoiceId: sourceInvoiceId)
        respond(id: id, encodable: note)
    }

    func handleAddDeliveryNoteLineItem(id: String, payload: [String: Any]) {
        let deliveryNoteId = (payload["deliveryNoteId"] as? String) ?? ""
        let sourceKey = payload["sourceKey"] as? String
        let priceListItemId = payload["priceListItemId"] as? String
        let itemCode = (payload["itemCode"] as? String) ?? ""
        let description = (payload["description"] as? String) ?? ""
        let unit = (payload["unit"] as? String) ?? "pc"
        let quantity = (payload["quantity"] as? Double) ?? 1
        let section = payload["section"] as? String

        guard !description.isEmpty else {
            respond(id: id, encodable: DeliveryNoteActionResult(ok: false, error: "Description is required."))
            return
        }
        guard quantity > 0 else {
            respond(id: id, encodable: DeliveryNoteActionResult(ok: false, error: "Quantity must be greater than zero."))
            return
        }

        if let error = db.addDeliveryNoteLineItem(
            deliveryNoteId: deliveryNoteId, sourceKey: sourceKey, priceListItemId: priceListItemId,
            itemCode: itemCode, description: description, unit: unit, quantity: quantity, section: section
        ) {
            respond(id: id, encodable: DeliveryNoteActionResult(ok: false, error: error))
        } else {
            respond(id: id, encodable: DeliveryNoteActionResult(ok: true, error: nil))
        }
    }

    func handleUpdateDeliveryNoteHeader(id: String, payload: [String: Any]) {
        let dnId = (payload["id"] as? String) ?? ""
        let deliveryAddress = payload["deliveryAddress"] as? String
        let deliveredBy = payload["deliveredBy"] as? String
        let receivedBy = payload["receivedBy"] as? String
        let notes = payload["notes"] as? String

        if let day = payload["deliveryDate"] as? String, !day.isEmpty,
           let error = db.updateDeliveryNoteDate(id: dnId, day: day) {
            respond(id: id, encodable: DeliveryNoteActionResult(ok: false, error: error))
            return
        }
        // Only changed when the page sends it.
        let contactPerson: String?? = payload.keys.contains("contactPerson") ? .some(nonBlank(payload["contactPerson"] as? String)) : .none
        if let error = db.updateDeliveryNoteHeader(id: dnId, deliveryAddress: deliveryAddress, deliveredBy: deliveredBy, receivedBy: receivedBy, notes: notes,
                                                   contactPerson: contactPerson) {
            respond(id: id, encodable: DeliveryNoteActionResult(ok: false, error: error))
        } else {
            respond(id: id, encodable: DeliveryNoteActionResult(ok: true, error: nil))
        }
    }

    // MARK: PDF export (Phase 13)

    /// Shared by every document type. Export: renders the PDF, saves it
    /// into the project's own folder under a meaningful filename
    /// (sections 31-32) and opens it. Print: renders the same PDF and
    /// opens the standard macOS print dialog (section 54) — nothing saved.
    /// Saves a table a page made (Accounts, Stock, Employees, delivery
    /// schedule, inspection register, reference list) as an Excel workbook
    /// into Administration/Accounts (or the folder the page names), and opens
    /// it. The page sends the table as CSV text; it's written as .xlsx, with
    /// plain numbers as numbers.
    func handleSaveAccountsCSV(id: String, payload: [String: Any]) {
        let given = ((payload["fileName"] as? String) ?? "").replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let lower = given.lowercased()
        guard lower.hasSuffix(".csv") || lower.hasSuffix(".xlsx"), !given.hasPrefix("."), let csv = payload["csv"] as? String else {
            respond(id: id, encodable: SimpleResult(ok: false, error: "The file couldn't be saved."))
            return
        }
        let base = (given as NSString).deletingPathExtension
        let name = base + ".xlsx"
        // Accounts' own folder, unless the page names another: a project's
        // subfolder (a quotation's delivery schedule) or an Administration one.
        var folder = storage.administrationCategoryFolder("Accounts")
        if let project = nonBlank(payload["projectNumber"] as? String) {
            folder = fileFolder(projectNumber: project, subfolder: nonBlank(payload["subfolder"] as? String) ?? "Other", name: name)
        } else if let admin = nonBlank(payload["adminFolder"] as? String), !admin.contains("/"), !admin.hasPrefix(".") {
            folder = storage.administrationCategoryFolder(admin)
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(name)
            try SpreadsheetWriter.writeXLSX(sheetName: base, rows: SpreadsheetReader.parseCSV(csv), to: destination, numbers: true)
            self.openForUser(destination)
            respond(id: id, encodable: SimpleResult(ok: true, error: nil))
        } catch {
            respond(id: id, encodable: SimpleResult(ok: false, error: "The Excel file couldn't be saved: \(error.localizedDescription)"))
        }
    }

    /// Saves a Word copy built by the page (js/docx-export.js) into the
    /// project's folder next to its PDF, and opens it.

    /// "preview": true on an export → the PDF is shown before it's saved.
    func previewMode(_ payload: [String: Any]) -> PDFMode {
        (payload["preview"] as? Bool) == true ? .preview : .export
    }

    /// A PDF's pages as JPEGs about 1,400 pixels wide (the first 80; a
    /// drawing larger than the paper is scaled to the same width).
    static func previewPages(_ data: Data, maxPages: Int = 80) -> (pages: [PreviewPage], count: Int) {
        guard let document = PDFDocument(data: data) else { return ([], 0) }
        var pages: [PreviewPage] = []
        for index in 0..<min(document.pageCount, maxPages) {
            guard let page = document.page(at: index) else { continue }
            let box = page.bounds(for: .mediaBox)
            let turned = page.rotation % 180 != 0
            let width = turned ? box.height : box.width
            let height = turned ? box.width : box.height
            guard width > 0, height > 0 else { continue }
            let scale = min(1400 / width, 2400 / height)
            let image = page.thumbnail(of: NSSize(width: width * scale, height: height * scale), for: .mediaBox)
            guard let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) else { continue }
            pages.append(PreviewPage(image: jpeg.base64EncodedString(), width: Double(width), height: Double(height)))
        }
        return (pages, document.pageCount)
    }

    /// Any finished PDF shown in the app first (js/doc-preview.js): kept
    /// aside until Save ("files:savePreview") puts it where `pending` says.
    func showPreview(id: String, data: Data, _ pending: PendingPreview) {
        let token = UUID().uuidString
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScaffoldPro-preview-\(token).pdf")
        do { try data.write(to: url, options: .atomic) } catch {
            respond(id: id, encodable: PreviewResult(ok: false, error: "The preview couldn't be prepared: \(error.localizedDescription)"))
            return
        }
        for (old, p) in pendingPreviews where p.docTypeTag == pending.docTypeTag && p.documentNumber == pending.documentNumber {
            try? FileManager.default.removeItem(at: p.url)
            pendingPreviews.removeValue(forKey: old)
        }
        var kept = pending
        kept.url = url
        pendingPreviews[token] = kept
        let filename = pending.fileName
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let drawn = NativeBridge.previewPages(data)
            DispatchQueue.main.async {
                self?.respond(id: id, encodable: PreviewResult(ok: true, error: nil, token: token, fileName: filename,
                                                                pages: drawn.pages, pageCount: drawn.count))
            }
        }
    }

    /// "Save" in the preview: the PDF shown goes into the project folder.
    func handleSavePreview(id: String, token: String) {
        guard let p = pendingPreviews.removeValue(forKey: token), let data = try? Data(contentsOf: p.url) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "That preview is no longer there — please export it again.", path: nil))
            return
        }
        try? FileManager.default.removeItem(at: p.url)
        if let folder = p.folder {
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let base = (p.fileName as NSString).deletingPathExtension
                var url = folder.appendingPathComponent(p.fileName)
                var n = 2
                while FileManager.default.fileExists(atPath: url.path) {
                    url = folder.appendingPathComponent("\(base) (\(n)).pdf")
                    n += 1
                }
                try data.write(to: url, options: .atomic)
                db.recordGeneratedPDF(docTypeTag: p.docTypeTag, documentNumber: p.documentNumber, path: url.path)
                respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: url.path))
            } catch {
                respond(id: id, encodable: PDFExportResult(ok: false, error: "The PDF couldn't be saved: \(error.localizedDescription)", path: nil))
            }
            return
        }
        do {
            let destination = try storage.writeGeneratedFile(data: data, projectNumber: p.projectNumber, subfolder: p.subfolder, meaningfulFilename: p.fileName,
                                                             folder: fileFolder(projectNumber: p.projectNumber, subfolder: p.subfolder, name: p.fileName,
                                                                                docTypeTag: p.docTypeTag, documentNumber: p.documentNumber))
            db.recordGeneratedPDF(docTypeTag: p.docTypeTag, documentNumber: p.documentNumber, path: destination.path)
            if let project = db.getProjectByNumber(p.projectNumber) {
                db.logActivity(projectId: project.id, "PDF exported", reference: destination.lastPathComponent)
            }
            respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: destination.path))
        } catch {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "The PDF couldn't be saved to the project folder. Please check there's free disk space and try again.", path: nil))
        }
    }

    /// After saving from the preview: open the file, or show it in Finder
    /// (only files in ScaffoldPro's own folders).
    func handleOpenSaved(id: String, path: String, reveal: Bool) {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard !path.isEmpty, url.path.hasPrefix(storage.appRoot.standardizedFileURL.path + "/"), fileIsPresent(url.path) else {
            respond(id: id, encodable: QuotationActionResult(ok: false, error: "That file isn't there any more."))
            return
        }
        if reveal { NSWorkspace.shared.activateFileViewerSelecting([url]) } else { openForUser(url) }
        respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
    }

    func handleSaveWord(id: String, payload: [String: Any]) {
        let projectNumber = (payload["projectNumber"] as? String) ?? ""
        let subfolder = (payload["subfolder"] as? String) ?? ""
        let fileName = ((payload["fileName"] as? String) ?? "").replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        // A worker's employment agreement: into their Contracts folder.
        if let worker = nonBlank(payload["workerId"] as? String).flatMap({ db.getWorker(id: $0) }) {
            guard fileName.hasSuffix(".docx"), !fileName.hasPrefix("."), let data = Data(base64Encoded: (payload["data"] as? String) ?? ""), !data.isEmpty else {
                respond(id: id, encodable: PDFExportResult(ok: false, error: "The Word document couldn't be saved.", path: nil))
                return
            }
            do {
                let folder = storage.workerFolder(worker.workerNumber).appendingPathComponent("Contracts", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = storage.uniqueDestination(folder.appendingPathComponent(fileName))
                try data.write(to: destination, options: .atomic)
                if (payload["open"] as? Bool) != false { self.openForUser(destination) }
                respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: destination.path))
            } catch {
                respond(id: id, encodable: PDFExportResult(ok: false, error: "The Word document couldn't be saved in the worker’s folder.", path: nil))
            }
            return
        }
        guard !projectNumber.isEmpty, db.getProjectByNumber(projectNumber) != nil,
              ["BOQ", "Quotations", "Invoices", "Delivery Notes"].contains(subfolder),
              fileName.hasSuffix(".docx"), !fileName.hasPrefix("."),
              let data = Data(base64Encoded: (payload["data"] as? String) ?? ""), !data.isEmpty else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "The Word document couldn't be saved.", path: nil))
            return
        }
        do {
            let destination = try storage.writeGeneratedFile(data: data, projectNumber: projectNumber, subfolder: subfolder, meaningfulFilename: fileName,
                                                             folder: fileFolder(projectNumber: projectNumber, subfolder: subfolder, name: fileName))
            if (payload["open"] as? Bool) != false { self.openForUser(destination) }
            if let project = db.getProjectByNumber(projectNumber) {
                db.logActivity(projectId: project.id, "Word document exported", reference: destination.lastPathComponent)
            }
            respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: destination.path))
        } catch {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "The Word document couldn't be saved to the project folder. Please check there's free disk space and try again.", path: nil))
        }
    }

    func deliverRenderedPDF(id: String, mode: PDFMode, company: CompanySettings, projectNumber: String, subfolder: String, documentNumber: String, docTypeTag: String, letter: LetterDocument,
                                    attachments: [URL] = []) {
        let paper = company.paperSize ?? "A4"
        guard let generator = PDFGenerator(paperSize: paper) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Could not prepare the document.", path: nil))
            return
        }
        let safeNumber = documentNumber.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")

        if mode == .word {
            // The page reads this, builds the .docx (js/docx-export.js) and
            // hands it back to "files:saveWord".
            var layout = generator.wordLayout(letter)
            guard let png = PDFGenerator.letterheadPNG(paperSize: paper) else {
                respond(id: id, encodable: PDFExportResult(ok: false, error: "Could not prepare the letterhead for the Word document.", path: nil))
                return
            }
            layout.letterheadPNG = png.base64EncodedString()
            layout.projectNumber = projectNumber
            layout.subfolder = subfolder
            layout.fileName = "\(db.documentFileBase(docTypeTag: docTypeTag, number: documentNumber) ?? "\(projectNumber)_\(docTypeTag)_\(safeNumber)").docx"
            if let fonts = Bundle.main.resourceURL?.appendingPathComponent("resources/fonts", isDirectory: true) {
                for (style, file) in [("regular", "EBGaramond-Regular"), ("bold", "EBGaramond-Bold"), ("italic", "EBGaramond-Italic"), ("boldItalic", "EBGaramond-BoldItalic")] {
                    if let data = try? Data(contentsOf: fonts.appendingPathComponent("\(file).ttf")) {
                        layout.fonts.append(WordFont(style: style, data: data.base64EncodedString()))
                    }
                }
            }
            respond(id: id, encodable: layout)
            return
        }
        let data = generator.generate(letter)
        deliverPDF(id: id, mode: mode, data: data,
                   paperSize: paper == "Letter" ? NSSize(width: 612, height: 792) : NSSize(width: 595.28, height: 841.89),
                   projectNumber: projectNumber, subfolder: subfolder, documentNumber: documentNumber, docTypeTag: docTypeTag,
                   attachments: attachments)
    }

    /// Prints a finished PDF (standard print dialog), or saves it into the
    /// project's folder and opens it. `attachments` (drawings) are added
    /// after the document's own pages.
    func deliverPDF(id: String, mode: PDFMode, data original: Data, paperSize: NSSize, projectNumber: String, subfolder: String, documentNumber: String, docTypeTag: String,
                            attachments: [URL] = []) {
        let safeNumber = documentNumber.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        // A draft (or cancelled) document: a big diagonal word across each
        // of its own pages — not across drawings attached after them.
        let status = db.documentStatus(docTypeTag: docTypeTag, number: documentNumber)
        let mark = status == "Draft" ? "DRAFT" : status == "Cancelled" ? "CANCELLED" : nil
        let own = mark.map { PDFWatermark.stamp(original, text: $0) } ?? original
        let data = PDFAttachments.append(attachments, to: own, paperSize: paperSize)
        // The preview: kept aside, its pages drawn for the page to show.
        if mode == .preview {
            showPreview(id: id, data: data, PendingPreview(url: URL(fileURLWithPath: "/"), projectNumber: projectNumber, subfolder: subfolder,
                                                           documentNumber: documentNumber, docTypeTag: docTypeTag,
                                                           fileName: "\(db.documentFileBase(docTypeTag: docTypeTag, number: documentNumber) ?? "\(projectNumber)_\(docTypeTag)_\(safeNumber)").pdf"))
            return
        }
        // From a browser, "Print" makes the PDF; the browser prints it.
        if mode == .print && !servingWeb {
            guard let document = PDFDocument(data: data), let window = window else {
                respond(id: id, encodable: PDFExportResult(ok: false, error: "Could not prepare the document for printing.", path: nil))
                return
            }
            let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
            info.paperSize = paperSize
            info.orientation = paperSize.width > paperSize.height ? .landscape : .portrait
            info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
            info.jobDisposition = .spool
            // Drawings may be larger than the paper (e.g. A1) or landscape:
            // those pages are fitted and turned; the document's own aren't.
            if let op = document.printOperation(for: info, scalingMode: attachments.isEmpty ? .pageScaleNone : .pageScaleDownToFit,
                                                autoRotate: !attachments.isEmpty) {
                op.jobTitle = "\(docTypeTag) \(documentNumber)"
                op.showsPrintPanel = true
                op.showsProgressPanel = true
                op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
            }
            if let project = db.getProjectByNumber(projectNumber) {
                db.logActivity(projectId: project.id, "Printed", reference: documentNumber)
            }
            respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: nil))
            return
        }

        let filename = "\(db.documentFileBase(docTypeTag: docTypeTag, number: documentNumber) ?? "\(projectNumber)_\(docTypeTag)_\(safeNumber)").pdf"
        do {
            let destination = try storage.writeGeneratedFile(data: data, projectNumber: projectNumber, subfolder: subfolder, meaningfulFilename: filename,
                                                             folder: fileFolder(projectNumber: projectNumber, subfolder: subfolder, name: filename,
                                                                                docTypeTag: docTypeTag, documentNumber: documentNumber))
            db.recordGeneratedPDF(docTypeTag: docTypeTag, documentNumber: documentNumber, path: destination.path)
            self.openForUser(destination)
            if let project = db.getProjectByNumber(projectNumber) {
                db.logActivity(projectId: project.id, "PDF exported", reference: destination.lastPathComponent)
            }
            respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: destination.path))
        } catch {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "The PDF couldn't be saved to the project folder. Please check there's free disk space and try again.", path: nil))
        }
    }

    /// "Locate File": shows a document's file in Finder — the PDF last
    /// exported, else the newest PDF or Word copy with its number in its
    /// project folder, else just that folder.
    /// A document's file: the PDF last exported, else the newest PDF or
    /// Word copy with its number in its project folder (nil if none yet),
    /// with that folder and the document's number. nil if not found.
    func documentFile(kind: String, documentId: String) -> (file: URL?, folder: URL, number: String)? {
        var number = "", projectId = "", pdfPath: String?, subfolder = ""
        switch kind {
        case "BOQ":
            guard let d = db.getBOQ(id: documentId) else { return nil }
            (number, projectId, pdfPath, subfolder) = (d.boqNumber, d.projectId, d.pdfPath, "BOQ")
        case "Quotation":
            guard let d = db.getQuotation(id: documentId) else { return nil }
            (number, projectId, pdfPath, subfolder) = (d.quotationNumber, d.projectId, d.pdfPath, "Quotations")
        case "Invoice":
            guard let d = db.getInvoice(id: documentId) else { return nil }
            (number, projectId, pdfPath, subfolder) = (d.invoiceNumber, d.projectId, d.pdfPath, "Invoices")
        case "DeliveryNote":
            guard let d = db.getDeliveryNote(id: documentId) else { return nil }
            (number, projectId, pdfPath, subfolder) = (d.deliveryNoteNumber, d.projectId, d.pdfPath, "Delivery Notes")
        default: return nil
        }
        guard !number.isEmpty, let project = db.getProject(id: projectId) else { return nil }
        let folder = fileFolder(projectNumber: project.projectNumber, subfolder: subfolder, name: number, docTypeTag: kind, documentNumber: number)
        if let path = pdfPath, fileIsPresent(path) { return (URL(fileURLWithPath: path), folder, number) }
        let fm = FileManager.default
        let safeNumber = number.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let files = ((try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
            .filter { $0.lastPathComponent.contains(safeNumber) && !$0.lastPathComponent.contains(" - Signed") && !isCombinedExport($0.lastPathComponent) && ["pdf", "docx"].contains($0.pathExtension.lowercased()) }
        let newest = files.max { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let dbb = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da < dbb
        }
        return (newest, folder, number)
    }

    /// One PDF made from several documents ("…_Quotations_Qt1+Qt2.pdf").
    func isCombinedExport(_ name: String) -> Bool {
        ["_Quotations_", "_BOQs_", "_Invoices_", "_Delivery Notes_"].contains { name.contains($0) }
    }

    /// "Locate File": shows a document's file in Finder — or, if it hasn't
    /// been exported yet, the folder it will be saved in.
    func handleLocateDocument(id: String, kind: String, documentId: String) {
        struct LocateResult: Encodable { var ok: Bool; var error: String?; var note: String? }
        guard let found = documentFile(kind: kind, documentId: documentId) else {
            respond(id: id, encodable: LocateResult(ok: false, error: "Document not found.", note: nil))
            return
        }
        if let file = found.file {
            self.revealOne(file)
            respond(id: id, encodable: LocateResult(ok: true, error: nil, note: nil))
            return
        }
        try? FileManager.default.createDirectory(at: found.folder, withIntermediateDirectories: true)
        self.revealOne(found.folder)
        respond(id: id, encodable: LocateResult(ok: true, error: nil,
                                               note: "\(found.number) hasn't been exported as a PDF or Word file yet, so Finder shows the folder it will be saved in."))
    }

    /// "Locate Files" for several documents: one Finder window with all
    /// their files selected. Says which haven't been exported yet.
    func handleLocateDocuments(id: String, kind: String, ids: [String]) {
        struct LocateResult: Encodable { var ok: Bool; var error: String?; var note: String? }
        let found = ids.compactMap { documentFile(kind: kind, documentId: $0) }
        let files = found.compactMap { $0.file }
        let missing = found.filter { $0.file == nil }.map { $0.number }
        if files.isEmpty {
            guard let folder = found.first?.folder else {
                respond(id: id, encodable: LocateResult(ok: false, error: "Nothing to show.", note: nil))
                return
            }
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            self.revealOne(folder)
        } else {
            self.revealForUser(files)
        }
        let note = missing.isEmpty ? nil
            : "\(missing.joined(separator: ", ")) \(missing.count == 1 ? "hasn't" : "haven't") been exported as a PDF or Word file yet\(files.isEmpty ? ", so Finder shows the folder they'll be saved in" : "")."
        respond(id: id, encodable: LocateResult(ok: true, error: nil, note: note))
    }
}

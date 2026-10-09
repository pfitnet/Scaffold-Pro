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
    // MARK: Documents in the letterhead layout (from Qt26193)

    /// "HK$" for Hong Kong dollars (as on the original), otherwise the code.
    func currencySymbol(_ company: CompanySettings) -> String {
        currencyDisplay(company.currency)
    }

    /// "22 Sep 2026", as on the original.
    func letterDate(_ iso: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX") // "Sep", not en_GB's "Sept"
        formatter.dateFormat = "d MMM yyyy"
        if let date = isoFormatter.date(from: iso) ?? isoFromDay(iso).flatMap({ isoFormatter.date(from: $0) }) {
            return formatter.string(from: date)
        }
        return iso
    }

    /// The client block at the top left: company name, then the billing
    /// information (or address), then "Attn:" if there's a contact.
    func clientBlock(projectNumber: String, fallbackName: String?) -> (name: String, lines: [String]) {
        guard let project = db.getProjectByNumber(projectNumber), let c = db.getClient(id: project.clientId) else {
            return (fallbackName ?? "", [])
        }
        var lines: [String] = []
        if let billing = nonBlank(c.billingInfo) {
            lines = billing.components(separatedBy: "\n").compactMap { nonBlank($0) }
        } else {
            for line in [c.address, c.addressLine2, c.addressLine3] {
                if let v = nonBlank(line) { lines.append(v) }
            }
            let cityLine = [c.city, c.postalCode].compactMap { nonBlank($0) }.joined(separator: " ")
            if !cityLine.isEmpty { lines.append(cityLine) }
            if let v = nonBlank(c.country) { lines.append(v) }
        }
        if let v = nonBlank(c.contactPerson) { lines.append("Attn: \(v)") }
        return (c.companyName, lines)
    }

    /// A client's name and address lines for the letterhead.
    func clientBlock(_ c: Client) -> (name: String, lines: [String]) {
        var lines: [String] = []
        if let billing = nonBlank(c.billingInfo) {
            lines = billing.components(separatedBy: "\n").compactMap { nonBlank($0) }
        } else {
            for line in [c.address, c.addressLine2, c.addressLine3] {
                if let v = nonBlank(line) { lines.append(v) }
            }
            let cityLine = [c.city, c.postalCode].compactMap { nonBlank($0) }.joined(separator: " ")
            if !cityLine.isEmpty { lines.append(cityLine) }
            if let v = nonBlank(c.country) { lines.append(v) }
        }
        if let v = nonBlank(c.contactPerson) { lines.append("Attn: \(v)") }
        return (c.companyName, lines)
    }

    /// Marketing › Client Report as a PDF on the letterhead.
    func handleClientReportPDF(id: String, payload: [String: Any]) {
        let clientId = nonBlank(payload["clientId"] as? String)
        let from = (payload["from"] as? String) ?? "0000-00-00", to = (payload["to"] as? String) ?? "9999-99-99"
        let report = db.clientQuoteReport(clientId: clientId, from: from, to: to)
        let company = db.getCompanySettings()
        let client = clientId.flatMap { db.getClient(id: $0) }
        let block = client.map { clientBlock($0) } ?? (name: report.clientName, lines: [])
        func day(_ ymd: String) -> String { letterDate(isoFromDay(ymd) ?? ymd) }
        let period = "\(day(from)) – \(day(to))"
        var rows: [LetterTableRow] = report.rows.enumerated().map { i, r in
            let what = [r.projectNumber.map { "\($0) \(r.projectName ?? "")" }, r.subject].compactMap { $0 }.joined(separator: "\n")
            return .item(["\(i + 1)", r.number + (r.won ? "\n(Accepted)" : ""), day(r.date), what, formatMoney(r.value)])
        }
        if rows.isEmpty { rows.append(.partial(["", "—"], tail: "No quotations were issued in this period.")) }
        rows.append(.summary(label: "Total of \(report.rows.count) quotation\(report.rows.count == 1 ? "" : "s"):", value: formatMoney(report.total), emphasized: true))
        if report.wonCount > 0 {
            rows.append(.summary(label: "Of which accepted (\(report.wonCount)):", value: formatMoney(report.wonValue), emphasized: false))
        }
        let columns = [
            LetterColumn(title: "No.", width: 29.25, kind: .center),
            LetterColumn(title: "Quotation No.", width: 100.0, kind: .left),
            LetterColumn(title: "Date", width: 76.0, kind: .center),
            LetterColumn(title: "Project / Subject", width: 192.75, kind: .left),
            LetterColumn(title: "Amount", width: 109.0, kind: .money),
        ]
        let letter = LetterDocument(
            number: "Quotation Report", status: "Issued", title: "QUOTATIONS ISSUED",
            clientName: block.name, clientLines: block.lines,
            refRows: [("Period", period), ("Date", letterDate(nowISO()))],
            deliveryMethod: nil, salutation: nil, subject: nil,
            intro: "Quotations issued to \(report.clientName) from \(day(from)) to \(day(to)).",
            currencySymbol: currencySymbol(company), columns: columns, rows: rows,
            sections: [], signatures: [], closingLine: nil
        )
        guard let generator = PDFGenerator(paperSize: company.paperSize ?? "A4") else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Could not prepare the report.", path: nil))
            return
        }
        let data = generator.generate(letter)
        let folder = storage.administrationCategoryFolder("Marketing Reports")
        let safe = report.clientName.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let name = "Quotations Issued - \(safe) - \(from) to \(to).pdf"
        showPreview(id: id, data: data, PendingPreview(url: URL(fileURLWithPath: "/"), projectNumber: "", subfolder: "", documentNumber: name,
                                                       docTypeTag: "Marketing Report", fileName: name, folder: folder))
    }

    /// "Unit Rates" for a client: chosen items from the material lists
    /// (either or both), laid out like a quotation, with each item's unit
    /// weight and monthly rental (with the markup chosen) and no list
    /// names. Saved in the company folder's "Unit Rates" folder and opened.
    func handleExportUnitRates(id: String, payload: [String: Any]) {
        let ids = (payload["itemIds"] as? [String]) ?? []
        let markup = payload["markupPercent"] as? Double
        let byId = Dictionary(db.inBaseCurrency(db.allPriceListItems()).map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let items = ids.compactMap { byId[$0] }
        guard !items.isEmpty else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Choose the items to include first.", path: nil))
            return
        }
        let company = db.getCompanySettings()
        let client = (payload["clientId"] as? String).flatMap { db.getClient(id: $0) }
        let block = client.map { clientBlock($0) } ?? (name: nonBlank(payload["clientName"] as? String) ?? "", lines: [])
        let roundUp = db.markupRoundsUp
        let price: (Double?) -> String = { p in p.map { formatMoney(markedUpPrice($0, markupPercent: markup, roundUp: roundUp)) } ?? "" }
        let rows: [LetterTableRow] = items.enumerated().map { index, item in
            // "kg" goes in the weight cells (the .weight column), not the heading.
            let weight = item.weightKg.map { String(format: "%.2f", $0) } ?? ""
            return .item(["\(index + 1)", item.itemName, weight, price(item.unitRentalPrice), price(item.unitSalePrice)])
        }
        let columns = [
            LetterColumn(title: "No.", width: 29.25, kind: .center),
            LetterColumn(title: "Item Description", width: 251.75, kind: .left),
            LetterColumn(title: "Unit\nWeight", width: 70.0, kind: .weight),
            LetterColumn(title: "Unit\nMonthly Rental", width: 78.0, kind: .money),
            LetterColumn(title: "Unit\nSale Price", width: 78.0, kind: .money),
        ]
        let today = nowISO()
        let letter = LetterDocument(
            number: "Unit Rates", status: "Issued", title: "UNIT RATES",
            clientName: block.name, clientLines: block.lines,
            refRows: [("Date", letterDate(today))],
            deliveryMethod: nil, salutation: block.name.isEmpty ? nil : "Dear Sir / Madam,",
            subject: nonBlank(payload["subject"] as? String).map { "Re: \($0)" },
            intro: "We are pleased to provide our unit rates for the following items.",
            currencySymbol: currencySymbol(company), columns: columns, rows: rows,
            sections: remarks(nonBlank(payload["notes"] as? String)),
            signatures: [companySignature(company)], closingLine: nil
        )
        guard let generator = PDFGenerator(paperSize: company.paperSize ?? "A4") else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Could not prepare the document.", path: nil))
            return
        }
        let data = generator.generate(letter)
        let folder = storage.appRoot.appendingPathComponent("Unit Rates", isDirectory: true)
        let who = block.name.isEmpty ? "" : " - \(block.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-"))"
        let base = "Unit Rates\(who) - \(String(today.prefix(10)))"
        if previewMode(payload) == .preview {
            showPreview(id: id, data: data, PendingPreview(url: URL(fileURLWithPath: "/"), projectNumber: "", subfolder: "", documentNumber: base,
                                                           docTypeTag: "Unit Rates", fileName: "\(base).pdf", folder: folder))
            return
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var url = folder.appendingPathComponent("\(base).pdf")
            var n = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = folder.appendingPathComponent("\(base) (\(n)).pdf")
                n += 1
            }
            try data.write(to: url, options: .atomic)
            self.openForUser(url)
            respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: url.path))
        } catch {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "The PDF couldn't be saved: \(error.localizedDescription)", path: nil))
        }
    }

    /// The site's own reference, or its name.
    func siteReference(projectNumber: String) -> String {
        guard let project = db.getProjectByNumber(projectNumber), let site = db.getSite(id: project.siteId) else { return "" }
        return nonBlank(site.siteReference) ?? site.name
    }

    /// "For and on Behalf of" the company, with the signatory from Settings.
    /// `nameUnderHeading`: the company's name right under the heading
    /// (quotations), not under the signing line.
    func companySignature(_ company: CompanySettings, nameUnderHeading: Bool = false) -> LetterSignature {
        var lines = nameUnderHeading ? [] : [LetterSignatureLine(text: company.companyName)]
        if let name = nonBlank(company.signatoryName) { lines.append(LetterSignatureLine(text: name)) }
        if let title = nonBlank(company.signatoryTitle) { lines.append(LetterSignatureLine(text: title)) }
        return LetterSignature(heading: "For and on Behalf of", subheading: nameUnderHeading ? company.companyName : nil, lines: lines)
    }

    func remarks(_ notes: String?) -> [LetterSection] {
        guard let notes = nonBlank(notes) else { return [] }
        return [LetterSection(heading: "Remarks", paragraphs: [.text(notes, link: nil)])]
    }

    /// The numbered terms from Settings: a line starting "(" begins a term
    /// ("(i) Payment : …"); other lines continue the one above.
    /// Materials numbered 1, 2, 3…; lines in the "Delivery" section go
    /// under a "Delivery Charges" heading, numbered D1, D2… (as on Qt26193).
    /// A line's own discount is printed under its description ("Less 10%
    /// discount") and its Total Price is net of it.
    func pricedRows(_ lines: [(description: String, unit: String, quantity: Double, price: Double, isDelivery: Bool, discountType: String?, discountValue: Double?)],
                            currency: String, rateSuffix: (String) -> String) -> (materials: [LetterTableRow], delivery: [LetterTableRow]) {
        var materials: [LetterTableRow] = []
        var delivery: [LetterTableRow] = []
        for line in lines {
            let net = netLineAmount(quantity: line.quantity, unitPrice: line.price, discountType: line.discountType, discountValue: line.discountValue)
            let total = formatMoney(doubleOf(net))
            let note = lineDiscountNote(discountType: line.discountType, discountValue: line.discountValue, currencySymbol: currency)
            let description = note.map { "\(line.description)\n\($0)" } ?? line.description
            if line.isDelivery {
                delivery.append(.item(["D\(delivery.count + 1)", description, "\(formatMoney(line.price)) /\(line.unit)", formatQuantity(line.quantity), total]))
            } else {
                materials.append(.item([String(materials.count + 1), description, "\(formatMoney(line.price))\(rateSuffix(line.unit))", formatQuantity(line.quantity), total]))
            }
        }
        return (materials, delivery)
    }

    /// One of a quotation's extra sections as table rows: its title, its
    /// rows (numbered A1, A2… or R1, R2…) and its note.
    func blockRows(_ block: QuotationBlock, _ detail: QuotationDetail, currency: String) -> [LetterTableRow] {
        var rows: [LetterTableRow] = []
        // A section charged per day / week / month says so in its title.
        let per = block.kind == "Priced" ? block.chargePeriod.map { " (per \($0.lowercased()))" } ?? "" : ""
        if let title = nonBlank(block.title) { rows.append(.section(title + per)) } else if !per.isEmpty { rows.append(.section("Charged\(per)")) }
        // The buy-back offer: one row, BO1, worded from its figures.
        if block.kind == "BuyBack" {
            if let offer = detail.buyBack {
                rows.append(.wide(number: "\(block.prefix)1", text: offer.sentences(currency: currency).joined(separator: "\n")))
            }
            if let note = nonBlank(block.note) { rows.append(.note(note)) }
            return rows
        }
        let lines = detail.lineItems.filter { $0.blockId == block.id }.sorted { $0.sortOrder < $1.sortOrder }
        for (i, line) in lines.enumerated() {
            let number = "\(block.prefix)\(i + 1)"
            let unit = line.unit.trimmingCharacters(in: .whitespaces)
            if block.kind == "Rates" {
                rows.append(.partial([number, line.itemDescription, "\(formatMoney(line.appliedUnitPrice))\(unit.isEmpty ? "" : " / \(unit)")"],
                                     tail: "(Rate Only)"))
            } else if let label = priceNoteLabel(line.priceNote) {
                // Not charged: the words across the price columns.
                rows.append(.partial([number, line.itemDescription], tail: label))
            } else {
                let note = lineDiscountNote(discountType: line.discountType, discountValue: line.discountValue, currencySymbol: currency)
                let description = note.map { "\(line.itemDescription)\n\($0)" } ?? line.itemDescription
                let total = detail.lineTotals[line.id] ?? line.appliedUnitPrice * line.quantity.rounded()
                rows.append(.item([number, description, "\(formatMoney(line.appliedUnitPrice))\(unit.isEmpty ? "" : " /\(unit)")",
                                   formatQuantity(line.quantity), formatMoney(total)]))
            }
        }
        if let note = nonBlank(block.note) { rows.append(.note(note)) }
        return rows
    }


    /// Landscape: the BOQ as the company's BQ sheet ("PROFICIENCY
    /// QUOTATION"), with prices. Portrait: on the letterhead, with weights
    /// and no prices (`exportBOQOnLetterhead`).
    func handleExportBOQPDF(id: String, boqId: String, mode: PDFMode = .export) {
        guard let detail = db.getBOQDetail(id: boqId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "BOQ not found.", path: nil))
            return
        }
        if detail.orientation == "Portrait" {
            exportBOQOnLetterhead(id: id, detail: detail, mode: mode)
            return
        }
        var layout = boqSheetLayout(detail)
        let safeNumber = detail.boqNumber.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")

        if mode == .word {
            layout.number = detail.boqNumber
            layout.projectNumber = detail.projectNumber
            layout.subfolder = "BOQ"
            layout.fileName = "\(db.documentFileBase(docTypeTag: "BOQ", number: detail.boqNumber) ?? "\(detail.projectNumber)_BOQ_\(safeNumber)").docx"
            respond(id: id, encodable: layout)
            return
        }
        guard let data = BQSheetRenderer.pdf(layout) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Could not prepare the document.", path: nil))
            return
        }
        deliverPDF(id: id, mode: mode, data: data, paperSize: NSSize(width: layout.pageWidth, height: layout.pageHeight),
                   projectNumber: detail.projectNumber, subfolder: "BOQ", documentNumber: detail.boqNumber, docTypeTag: "BOQ",
                   attachments: boqAttachments(detail.id))
    }

    /// Everything added after a BOQ's own pages: its delivery schedule, then its drawings.
    func boqAttachments(_ id: String) -> [URL] {
        [deliveryScheduleFile(kind: "BOQ", id: id)].compactMap { $0 } + db.appendedDrawingFiles(kind: "BOQ", id: id)
    }

    /// The landscape BQ sheet ("PROFICIENCY QUOTATION") for a BOQ.
    func boqSheetLayout(_ detail: BOQDetail) -> SheetLayout {
        let company = db.getCompanySettings()
        let project = db.getProjectByNumber(detail.projectNumber)
        let client = project.flatMap { db.getClient(id: $0.clientId) }
        let site = project.flatMap { db.getSite(id: $0.siteId) }
        // Job site: its reference and name, e.g. "1635 Kwu Tung Station".
        var jobSite = site.map { $0.name } ?? ""
        if let ref = nonBlank(site?.siteReference), !jobSite.contains(ref) { jobSite = jobSite.isEmpty ? ref : "\(ref) \(jobSite)" }
        let clientName = nonBlank(client?.clientReference) ?? client?.companyName ?? ""
        // "26210 - Project Name - Rental - CRBC"
        let projectCode = [detail.projectNumber, detail.projectName, detail.pricingMode, clientName]
            .compactMap { nonBlank($0) }.joined(separator: " - ")
        // Printed at their discounted rates; the discount itself isn't shown.
        // Item names in English or in Chinese, as chosen.
        let inChinese = db.printsInChinese(detail.language)
        let zh = inChinese
            ? db.chineseNames(for: detail.lineItems, id: { $0.id }, itemId: { $0.priceListItemId }, description: { $0.itemDescription }) : [:]
        let lines = detail.lineItems.map { line -> BOQLineItem in
            var copy = line
            copy.appliedUnitPrice = detail.effectiveRates[line.id] ?? line.appliedUnitPrice
            copy.itemDescription = documentItemName(line.itemDescription, zh[line.id], inChinese: inChinese)
            return copy
        }
        return BQSheet.layout(
            landscape: true, pricingMode: detail.pricingMode, currencyCode: company.currency,
            info: (projectCode: projectCode, client: clientName, jobSite: jobSite, structure: detail.structure ?? ""),
            lines: lines, grandTotal: detail.grandTotal, totalWeightKg: detail.totalWeightKg,
            ratesSection: detail.ratesSection, charges: detail.charges ?? [], notes: detail.notes,
            terms: detail.terms, chinese: inChinese)
    }

    /// A BOQ's own pages as a PDF (landscape sheet or portrait letterhead,
    /// as the BOQ is set), without its drawings: for the quotation that
    /// follows it.
    func boqPDFData(_ detail: BOQDetail) -> Data? {
        if detail.orientation == "Portrait" {
            return PDFGenerator(paperSize: db.getCompanySettings().paperSize ?? "A4")?.generate(boqLetter(detail))
        }
        return BQSheetRenderer.pdf(boqSheetLayout(detail))
    }

    /// The BOQ a quotation follows, written to a temporary PDF so it can be
    /// added after the quotation's pages like a drawing.
    func followedBOQFile(_ quotation: QuotationDetail) -> URL? {
        guard let boqId = db.getQuotation(id: quotation.id)?.sourceBOQId, let boq = db.getBOQDetail(id: boqId),
              !boq.lineItems.isEmpty, let data = boqPDFData(boq) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScaffoldPro-\(boq.id).pdf")
        return (try? data.write(to: url)) != nil ? url : nil
    }

    /// A BOQ's or quotation's delivery schedule as landscape pages
    /// (BQSheet.deliverySchedule), written to a temporary PDF so it's added
    /// right after the document's own pages; nil when no day has anything
    /// on it. A quotation without one of its own has its BOQ's.
    func deliveryScheduleFile(kind: String, id: String, withInternalNotes: Bool = false) -> URL? {
        let used: (DeliveryScheduleData) -> [QuotationDeliveryDay] = { schedule in
            schedule.days.contains { $0.quantities.values.contains { $0 > 0 } }
                ? schedule.days.filter { $0.date != nil || $0.quantities.values.contains { $0 > 0 } || nonBlank($0.note) != nil
                    || (withInternalNotes && nonBlank($0.internalNote) != nil) } : []
        }
        // The BOQ's items, with its schedule.
        func ofBOQ(_ boq: BOQDetail, document: String) -> [SheetLayout] {
            let schedule = db.deliverySchedule(quotationId: boq.id)
            let days = used(schedule)
            guard !days.isEmpty else { return [] }
            let inChinese = db.printsInChinese(boq.language)
            let zh = inChinese ? db.chineseNames(for: boq.lineItems, id: { $0.id }, itemId: { $0.priceListItemId }, description: { $0.itemDescription }) : [:]
            let lines = boq.lineItems.map { l in
                BQSheet.ScheduleLine(id: l.id, name: documentItemName(l.itemDescription, zh[l.id], inChinese: inChinese), unit: l.unit,
                                     quantity: l.quantity, weightKg: l.weightKg ?? schedule.weights[l.id])
            }
            return BQSheet.deliverySchedule(info: scheduleInfo(projectNumber: boq.projectNumber, projectName: boq.projectName,
                                                               pricingMode: boq.pricingMode, document: document),
                                            lines: lines, days: days, chinese: inChinese, withInternalNotes: withInternalNotes)
        }
        var sheets: [SheetLayout] = []
        if kind == "BOQ" {
            guard let boq = db.getBOQDetail(id: id) else { return nil }
            sheets = ofBOQ(boq, document: "BOQ \(boq.boqNumber)")
        } else {
            guard let q = db.getQuotationDetail(id: id) else { return nil }
            let schedule = db.deliverySchedule(quotationId: q.id)
            let days = used(schedule)
            if !days.isEmpty {
                let inChinese = db.printsInChinese(q.language)
                let materials = q.lineItems.filter { $0.blockId == nil && $0.section != "Delivery" }
                let zh = inChinese ? db.chineseNames(for: materials, id: { $0.id }, itemId: { $0.priceListItemId }, description: { $0.itemDescription }) : [:]
                let weights = db.quotationLineWeights(materials)
                let lines = materials.map { l in
                    BQSheet.ScheduleLine(id: l.id, name: documentItemName(l.itemDescription, zh[l.id], inChinese: inChinese), unit: l.unit,
                                         quantity: l.quantity, weightKg: weights[l.id] ?? schedule.weights[l.id])
                }
                sheets = BQSheet.deliverySchedule(info: scheduleInfo(projectNumber: q.projectNumber, projectName: q.projectName,
                                                                     pricingMode: q.pricingMode, document: "Quotation \(q.quotationNumber)"),
                                                  lines: lines, days: days, chinese: inChinese, withInternalNotes: withInternalNotes)
            } else if let boqId = db.getQuotation(id: q.id)?.sourceBOQId, let boq = db.getBOQDetail(id: boqId) {
                sheets = ofBOQ(boq, document: "Quotation \(q.quotationNumber)")
            }
        }
        let document = PDFDocument()
        for sheet in sheets {
            guard let data = BQSheetRenderer.pdf(sheet), let pages = PDFDocument(data: data) else { continue }
            for i in 0..<pages.pageCount {
                if let page = pages.page(at: i)?.copy() as? PDFPage { document.insert(page, at: document.pageCount) }
            }
        }
        guard document.pageCount > 0, let data = document.dataRepresentation() else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScaffoldPro-schedule-\(id)\(withInternalNotes ? "-internal" : "").pdf")
        return (try? data.write(to: url)) != nil ? url : nil
    }

    /// The delivery schedule on its own (its Export › External or Internal ›
    /// PDF): the landscape sheet, saved in the document's folder as
    /// "…_Delivery Schedule_Qt26212-007.pdf" (Internal: with the internal
    /// notes, "…_Delivery Schedule (Internal)_…") and opened.
    func handleExportSchedulePDF(id: String, kind: String, documentId: String, withInternalNotes: Bool, mode: PDFMode = .export) {
        let isBOQ = kind == "BOQ"
        let doc: (number: String, projectNumber: String)? = isBOQ
            ? db.getBOQDetail(id: documentId).map { ($0.boqNumber, $0.projectNumber) }
            : db.getQuotationDetail(id: documentId).map { ($0.quotationNumber, $0.projectNumber) }
        guard let doc = doc else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: isBOQ ? "BOQ not found." : "Quotation not found.", path: nil))
            return
        }
        guard let file = deliveryScheduleFile(kind: isBOQ ? "BOQ" : "Quotation", id: documentId, withInternalNotes: withInternalNotes), let data = try? Data(contentsOf: file) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Put some items on a day of the schedule first.", path: nil))
            return
        }
        let size = PDFDocument(data: data)?.page(at: 0)?.bounds(for: .mediaBox).size ?? NSSize(width: 842.88, height: 595.92)
        deliverPDF(id: id, mode: mode, data: data, paperSize: size, projectNumber: doc.projectNumber,
                   subfolder: isBOQ ? "BOQ" : "Quotations", documentNumber: doc.number, docTypeTag: withInternalNotes ? "Delivery Schedule (Internal)" : "Delivery Schedule")
    }

    /// The project code, client and job site at the top of a sheet, as on the BQ sheet.
    func scheduleInfo(projectNumber: String, projectName: String, pricingMode: String, document: String)
        -> (projectCode: String, client: String, jobSite: String, document: String) {
        let project = db.getProjectByNumber(projectNumber)
        let client = project.flatMap { db.getClient(id: $0.clientId) }
        let site = project.flatMap { db.getSite(id: $0.siteId) }
        var jobSite = site.map { $0.name } ?? ""
        if let ref = nonBlank(site?.siteReference), !jobSite.contains(ref) { jobSite = jobSite.isEmpty ? ref : "\(ref) \(jobSite)" }
        let clientName = nonBlank(client?.clientReference) ?? client?.companyName ?? ""
        let projectCode = [projectNumber, projectName, pricingMode, clientName].compactMap { nonBlank($0) }.joined(separator: " - ")
        return (projectCode, clientName, jobSite, document)
    }

    /// The portrait BOQ: the letterhead layout (from Qt26193) with each
    /// item's unit, quantity and weights, and the total weight.
    func exportBOQOnLetterhead(id: String, detail: BOQDetail, mode: PDFMode) {
        deliverRenderedPDF(id: id, mode: mode, company: db.getCompanySettings(), projectNumber: detail.projectNumber, subfolder: "BOQ",
                           documentNumber: detail.boqNumber, docTypeTag: "BOQ", letter: boqLetter(detail),
                           attachments: boqAttachments(detail.id))
    }

    func boqLetter(_ detail: BOQDetail) -> LetterDocument {
        let company = db.getCompanySettings()
        let client = clientBlock(projectNumber: detail.projectNumber, fallbackName: nil)
        let inChinese = db.printsInChinese(detail.language)
        let columns = [
            LetterColumn(title: inChinese ? "編號" : "No", width: 29.25, kind: .center),
            LetterColumn(title: inChinese ? "物料名稱" : "Item Description", width: 219.75, kind: .left),
            LetterColumn(title: inChinese ? "單位" : "Unit", width: 50.0, kind: .center),
            LetterColumn(title: inChinese ? "數量" : "Qty", width: 50.0, kind: .center),
            LetterColumn(title: inChinese ? "單位重量 (kg)" : "Unit Wt (kg)", width: 75.0, kind: .right),
            LetterColumn(title: inChinese ? "總重量 (kg)" : "Total Wt (kg)", width: 83.0, kind: .right),
        ]
        let zh = inChinese
            ? db.chineseNames(for: detail.lineItems, id: { $0.id }, itemId: { $0.priceListItemId }, description: { $0.itemDescription }) : [:]
        var rows: [LetterTableRow] = detail.lineItems.enumerated().map { index, item in
            .item([String(index + 1), lineDescription(documentItemName(item.itemDescription, zh[item.id], inChinese: inChinese), notes: item.notes), item.unit, formatQuantity(item.quantity),
                   item.weightKg.map { formatMoney($0) } ?? "—",
                   item.weightKg.map { formatMoney($0 * item.quantity.rounded()) } ?? "—"])
        }
        rows.append(.summary(label: inChinese ? "總重量:" : "Total Weight:", value: "\(formatMoney(detail.totalWeightKg)) kg", emphasized: true))

        return LetterDocument(
            number: detail.boqNumber, status: detail.status, title: "BILL OF QUANTITIES",
            clientName: client.name, clientLines: client.lines,
            refRows: [("BOQ No.", detail.boqNumber), ("Project No.", detail.projectNumber),
                      ("Site Ref.", siteReference(projectNumber: detail.projectNumber)), ("Date", letterDate(detail.createdAt))],
            deliveryMethod: nil, salutation: nil,
            subject: "Re: \(detail.projectNumber) \(detail.projectName) - \(detail.pricingMode)",
            intro: detail.structure.flatMap { nonBlank($0) }.map { "Structure: \($0)" },
            currencySymbol: currencySymbol(company), columns: columns, rows: rows,
            sections: remarks(detail.notes), signatures: [], closingLine: nil
        )
    }

    func handleExportQuotationPDF(id: String, quotationId: String, mode: PDFMode = .export, withSubsidiaries: Bool = false, subsidiaryIds: [String]? = nil) {
        guard let detail = db.getQuotationDetail(id: quotationId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Quotation not found.", path: nil))
            return
        }
        // Landscape: the BQ sheet, as a BOQ's, with the terms and signatures.
        if detail.orientation == "Landscape" {
            var layout = quotationSheetLayout(detail)
            if mode == .word {
                let safe = detail.quotationNumber.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
                layout.number = detail.quotationNumber
                layout.projectNumber = detail.projectNumber
                layout.subfolder = "Quotations"
                layout.fileName = "\(db.documentFileBase(docTypeTag: "Quotation", number: detail.quotationNumber) ?? "\(detail.projectNumber)_Quotation_\(safe)").docx"
                respond(id: id, encodable: layout)
                return
            }
            guard let data = BQSheetRenderer.pdf(layout) else {
                respond(id: id, encodable: PDFExportResult(ok: false, error: "Could not prepare the document.", path: nil))
                return
            }
            deliverPDF(id: id, mode: mode, data: data, paperSize: NSSize(width: layout.pageWidth, height: layout.pageHeight),
                       projectNumber: detail.projectNumber, subfolder: "Quotations", documentNumber: detail.quotationNumber, docTypeTag: "Quotation",
                       attachments: quotationAttachments(detail, withSubsidiaries: withSubsidiaries, only: subsidiaryIds))
            return
        }
        let company = db.getCompanySettings()
        let letter = quotationLetter(detail, company: company)
        deliverRenderedPDF(id: id, mode: mode, company: company, projectNumber: detail.projectNumber, subfolder: "Quotations",
                           documentNumber: detail.quotationNumber, docTypeTag: "Quotation", letter: letter,
                           attachments: mode == .word ? [] : quotationAttachments(detail, withSubsidiaries: withSubsidiaries, only: subsidiaryIds))
    }

    /// A quotation's own pages as a PDF, as it's set to print (portrait
    /// letterhead or the landscape BQ sheet), signed if pictures are given.
    /// `signer`: who signed and chopped it; their full name and title (Team
    /// page) are printed under the signature instead of Settings' signatory.
    func quotationPDFData(_ detail: QuotationDetail, signature: CGImage? = nil, chop: CGImage? = nil, signer: String? = nil) -> Data? {
        let company = db.getCompanySettings()
        if detail.orientation == "Landscape" {
            return BQSheetRenderer.pdf(quotationSheetLayout(detail, signer: signer), signature: signature, chop: chop)
        }
        var letter = quotationLetter(detail, company: company)
        if signature != nil, let i = letter.signatures.firstIndex(where: { $0.heading == "For and on Behalf of" }) {
            letter.signatures[i].signatureImage = signature
            letter.signatures[i].chopImage = chop
            if let signer = nonBlank(signer) {
                let title = nonBlank(db.membership(signer)?.title) ?? nonBlank(company.signatoryTitle)
                letter.signatures[i].lines = [LetterSignatureLine(text: db.fullName(signer))] + [title].compactMap { $0 }.map { LetterSignatureLine(text: $0) }
            }
        }
        return PDFGenerator(paperSize: company.paperSize ?? "A4")?.generate(letter)
    }

    /// The landscape quotation: the BQ sheet ("PROFICIENCY QUOTATION") as for
    /// a BOQ — the quotation number and date, each material with its weight
    /// and price, the subtotal, then what's added to it (minimum charges,
    /// delivery D1, D2…, priced sections, discount, tax) and the Total
    /// Amount; rates after it; notes; the terms and conditions; and the
    /// signature block ("For and On Behalf of" / "Accepted By"). All on one
    /// page, shrunk to fit if need be.
    func quotationSheetLayout(_ detail: QuotationDetail, signer: String? = nil) -> SheetLayout {
        let company = db.getCompanySettings()
        let project = db.getProjectByNumber(detail.projectNumber)
        let client = project.flatMap { db.getClient(id: $0.clientId) }
        let site = project.flatMap { db.getSite(id: $0.siteId) }
        var jobSite = site.map { $0.name } ?? ""
        if let ref = nonBlank(site?.siteReference), !jobSite.contains(ref) { jobSite = jobSite.isEmpty ? ref : "\(ref) \(jobSite)" }
        let clientName = nonBlank(client?.clientReference) ?? client?.companyName ?? ""
        let projectCode = [detail.projectNumber, detail.projectName, detail.pricingMode, clientName].compactMap { nonBlank($0) }.joined(separator: " - ")
        let structure = detail.sourceBOQId.flatMap { db.getBOQ(id: $0)?.structure }.flatMap { nonBlank($0) } ?? nonBlank(detail.subject) ?? ""
        let inChinese = db.printsInChinese(detail.language)
        let zh = inChinese
            ? db.chineseNames(for: detail.lineItems, id: { $0.id }, itemId: { $0.priceListItemId }, description: { $0.itemDescription }) : [:]
        let materials = detail.lineItems.filter { $0.blockId == nil && $0.section != "Delivery" }
        let weights = db.quotationLineWeights(materials)
        // Each at the rate charged (markup and any discount in it).
        let lines = materials.map { l -> BOQLineItem in
            let qty = l.quantity.rounded()
            let total = detail.lineTotals[l.id] ?? (detail.effectiveUnitPrices[l.id] ?? l.appliedUnitPrice) * qty
            let rate = qty > 0 && (l.discountType ?? "None") != "None" ? doubleOf(roundToCents(decimalOf(total) / decimalOf(qty)))
                : (detail.effectiveUnitPrices[l.id] ?? l.appliedUnitPrice)
            return BOQLineItem(id: l.id, boqId: detail.id, sourceKey: l.sourceKey, priceListItemId: l.priceListItemId, itemCode: l.itemCode,
                               itemDescription: documentItemName(l.itemDescription, zh[l.id], inChinese: inChinese), unit: l.unit,
                               quantity: qty, priceListUnitPrice: nil, appliedUnitPrice: rate, weightKg: weights[l.id],
                               section: l.section, sortOrder: l.sortOrder, notes: nil)
        }
        let totalWeight = lines.reduce(0.0) { $0 + ($1.weightKg ?? 0) * $1.quantity }
        // What's added after the materials' subtotal.
        var charges: [BOQCharge] = []
        if detail.pricingMode == "Rental" {
            if detail.minimumMonthlyApplied && detail.monthlyRental > detail.materialsSubtotal {
                charges.append(BOQCharge(code: "M", name: "Minimum Monthly Rental Charge (\(formatMoney(detail.monthlyRental)) a month)",
                                         amount: doubleOf(decimalOf(detail.monthlyRental) - decimalOf(detail.materialsSubtotal))))
            }
            if detail.minimumHireEnabled && detail.hireMonths > 1 && detail.materialsCharge > detail.monthlyRental {
                let months = detail.hireMonths == 2 ? "the 2nd month" : "months 2 – \(detail.hireMonths)"
                charges.append(BOQCharge(code: "M", name: "Minimum Hire of \(detail.hireMonths) Months — rental for \(months)",
                                         amount: doubleOf(decimalOf(detail.materialsCharge) - decimalOf(detail.monthlyRental))))
            }
        }
        for (i, l) in detail.lineItems.filter({ $0.blockId == nil && $0.section == "Delivery" }).enumerated() {
            // "Delivery of materials" over "@$3,300.00 / Truck / Trip" (the
            // weight band, "(2 – 6 tons)", isn't printed).
            var first = l.itemDescription.components(separatedBy: "\n").first ?? l.itemDescription
            first = first.replacingOccurrences(of: #"\s*\([^)]*(kg|ton)[^)]*\)"#, with: "", options: [.regularExpression, .caseInsensitive])
            let unit = l.unit.trimmingCharacters(in: .whitespaces).split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces).capitalized }
                .filter { !$0.isEmpty }.joined(separator: " / ")
            charges.append(BOQCharge(code: "D\(i + 1)", name: "\(first)\n@$\(formatMoney(l.appliedUnitPrice))\(unit.isEmpty ? "" : " / \(unit)")",
                                     amount: detail.lineTotals[l.id] ?? l.appliedUnitPrice * l.quantity.rounded()))
        }
        for block in detail.blocks where block.kind == "Priced" {
            let per = block.chargePeriod.map { " (per \($0.lowercased()))" } ?? ""
            for (i, l) in detail.lineItems.filter({ $0.blockId == block.id }).sorted(by: { $0.sortOrder < $1.sortOrder }).enumerated() {
                let title = nonBlank(block.title).map { "\($0)\(per): " } ?? ""
                charges.append(BOQCharge(code: "\(block.prefix)\(i + 1)", name: "\(title)\(l.itemDescription.replacingOccurrences(of: "\n", with: " "))",
                                         amount: detail.lineTotals[l.id] ?? l.appliedUnitPrice * l.quantity.rounded(),
                                         amountText: priceNoteLabel(l.priceNote)))
            }
        }
        if detail.discountAmount > 0 {
            let percent = detail.discountType == "Percent" ? " \(formatMoney(detail.discountValue).replacingOccurrences(of: ".00", with: ""))%" : ""
            charges.append(BOQCharge(code: "–", name: "Less\(percent) Discount", amount: -detail.discountAmount))
        }
        if detail.taxAmount > 0 {
            let label = (company.pricesIncludeTax ?? false) ? "Tax / VAT included" : "Tax / VAT (\(formatMoney(detail.taxRatePercent))%)"
            charges.append(BOQCharge(code: "–", name: label, amount: detail.taxAmount))
        }
        // Rates after the total: the first rates section.
        let ratesBlock = detail.blocks.first { $0.kind == "Rates" }
        let rates = ratesBlock.map { b in
            BOQRatesSection(title: b.title, rates: detail.lineItems.filter { $0.blockId == b.id }.sorted { $0.sortOrder < $1.sortOrder }
                .map { ManpowerRate(name: $0.itemDescription, rate: $0.appliedUnitPrice, unit: $0.unit) }, note: b.note)
        }
        let notes = ([nonBlank(detail.notes)] + detail.blocks.filter { $0.kind == "Note" }.map { nonBlank($0.note) }).compactMap { $0 }.joined(separator: "\n")
        // The terms as on the portrait quotation: the web address, the key terms, the acceptance.
        var terms: [String] = []
        if let url = nonBlank(company.termsURL) {
            terms.append("The terms and conditions set out in \(url) are hereby expressively incorporated into this quotation with other relevant key terms set forth below.")
        }
        terms.append(nonBlank(detail.keyTerms) ?? detail.standardKeyTerms)
        terms.append(company.quotationAcceptance ?? defaultQuotationAcceptance)
        return BQSheet.layout(
            landscape: true, pricingMode: detail.pricingMode, currencyCode: company.currency,
            info: (projectCode: projectCode, client: clientName, jobSite: jobSite, structure: structure),
            lines: lines, grandTotal: detail.materialsSubtotal, totalWeightKg: totalWeight,
            ratesSection: rates, charges: charges, notes: nonBlank(notes),
            terms: terms.joined(separator: "\n\n"), chinese: inChinese,
            signature: (company: company.companyName,
                        name: nonBlank(signer).map { db.fullName($0) } ?? company.signatoryName ?? "",
                        title: nonBlank(signer).flatMap { nonBlank(db.membership($0)?.title) } ?? company.signatoryTitle ?? "",
                        client: client?.companyName ?? detail.clientName ?? ""),
            extraInfo: [("Quotation No. :", detail.quotationNumber, "Date               :", letterDate(detail.quotationDate))],
            onePage: true)
    }

    /// Everything added after a quotation's own pages: its delivery
    /// schedule, the BOQ it follows (not after a landscape quotation, which
    /// is the BQ sheet itself), then its image and PDF drawings.
    func quotationAttachments(_ detail: QuotationDetail, withSubsidiaries: Bool = false, only: [String]? = nil) -> [URL] {
        let boq = detail.orientation == "Landscape" || detail.jobType == "Crane" ? nil : followedBOQFile(detail)
        return (withSubsidiaries ? subsidiaryFiles(detail, only: only) : [])
            + [deliveryScheduleFile(kind: "Quotation", id: detail.id), boq].compactMap { $0 }
            + db.appendedDrawingFiles(kind: "Quotation", id: detail.id)
    }

    /// The quotations split off this one (not cancelled ones), as each
    /// prints, written to temporary PDFs so they follow this quotation's own
    /// pages — when asked for at Export / Print.
    /// `only`: just these of them (chosen at Export / Print).
    func subsidiaryFiles(_ detail: QuotationDetail, only: [String]? = nil) -> [URL] {
        return detail.subsidiaries.filter { $0.status != "Cancelled" && (only.map { Set($0) }?.contains($0.id) ?? true) }.compactMap { ref -> URL? in
            guard let sub = db.getQuotationDetail(id: ref.id), var data = quotationPDFData(sub) else { return nil }
            if sub.status == "Draft" { data = PDFWatermark.stamp(data, text: "DRAFT") }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScaffoldPro-\(sub.id).pdf")
            return (try? data.write(to: url)) != nil ? url : nil
        }
    }

    /// A quotation laid out on the letterhead (as Qt26193).
    func quotationLetter(_ detail: QuotationDetail, company: CompanySettings) -> LetterDocument {
        // A quotation in another currency (a crane job's, say) prints in it.
        var company = company
        if let code = nonBlank(detail.currency) { company.currency = code }
        let isRental = detail.pricingMode == "Rental"
        let client = clientBlock(projectNumber: detail.projectNumber, fallbackName: detail.clientName)

        // Item names in English or in Chinese, as chosen for the quotation.
        let inChinese = db.printsInChinese(detail.language)
        let zh = inChinese
            ? db.chineseNames(for: detail.lineItems, id: { $0.id }, itemId: { $0.priceListItemId }, description: { $0.itemDescription }) : [:]
        // Unit prices as charged: with the quotation's markup, if any.
        let priced = pricedRows(detail.lineItems.filter { $0.blockId == nil }.map { (description: documentItemName($0.itemDescription, zh[$0.id], inChinese: inChinese),
                                                         unit: $0.unit, quantity: $0.quantity,
                                                         price: detail.effectiveUnitPrices[$0.id] ?? $0.appliedUnitPrice, isDelivery: $0.section == "Delivery",
                                                         discountType: $0.discountType, discountValue: $0.discountValue) },
                                currency: currencySymbol(company), rateSuffix: { _ in isRental ? " /Month" : "" })
        var rows = priced.materials
        // No items (only priced sections, say): no subtotal of them.
        if isRental && !priced.materials.isEmpty {
            rows.append(.summary(label: "Subtotal of Monthly Rental Charge:", value: formatMoney(detail.materialsSubtotal), emphasized: false))
            if detail.minimumMonthlyApplied {
                rows.append(.summary(label: "Minimum Monthly Rental Charge:", value: formatMoney(detail.monthlyRental), emphasized: false))
            }
            // Only when it changes the amount: ticked, and more than one month.
            if detail.minimumHireEnabled && detail.hireMonths > 1 {
                rows.append(.summary(label: "Minimum Hire of \(detail.hireMonths) Month\(detail.hireMonths == 1 ? "" : "s"):", value: formatMoney(detail.materialsCharge), emphasized: false))
            }
        } else if !priced.materials.isEmpty {
            rows.append(.summary(label: "Subtotal:", value: formatMoney(detail.materialsSubtotal), emphasized: false))
        }
        if !priced.delivery.isEmpty {
            rows.append(.section("Delivery Charges"))
            rows += priced.delivery
        }
        // Priced sections (design fees, erection prices…) count towards the
        // total; rates-only sections and notes follow the Total Amount.
        let currency = currencySymbol(company)
        for block in detail.blocks where block.kind == "Priced" {
            rows += blockRows(block, detail, currency: currency)
        }
        if detail.discountAmount > 0 {
            let percent = detail.discountType == "Percent" ? " \(formatMoney(detail.discountValue).replacingOccurrences(of: ".00", with: ""))%" : ""
            rows.append(.summary(label: "Less\(percent) Discount:", value: "-\(formatMoney(detail.discountAmount))", emphasized: false))
        }
        if detail.taxAmount > 0 {
            let label = (company.pricesIncludeTax ?? false) ? "Tax / VAT included:" : "Tax / VAT (\(formatMoney(detail.taxRatePercent))%):"
            rows.append(.summary(label: label, value: formatMoney(detail.taxAmount), emphasized: false))
        }
        rows.append(.summary(label: "Total Amount:", value: formatMoney(detail.total), emphasized: true))
        for block in detail.blocks where block.kind != "Priced" {
            rows += blockRows(block, detail, currency: currency)
        }

        var terms: [LetterParagraph] = []
        if let url = nonBlank(company.termsURL) {
            terms.append(.text("The terms and conditions set out in \(url) are hereby expressively incorporated into this quotation with other relevant key terms set forth below.", link: url))
        }
        // This quotation's own key terms, or the standard ones from Settings.
        terms += formattedParagraphs(nonBlank(detail.keyTerms) ?? detail.standardKeyTerms)
        terms.append(.text(company.quotationAcceptance ?? defaultQuotationAcceptance, link: nil))

        return LetterDocument(
            number: detail.quotationNumber, status: detail.status, title: "QUOTATION",
            clientName: client.name, clientLines: client.lines,
            refRows: [("Our Ref. No.", detail.quotationNumber), ("Your Ref. No.", detail.clientRef ?? ""),
                      ("Site Ref.", nonBlank(detail.siteRef) ?? detail.siteName ?? ""), ("Date", letterDate(detail.quotationDate))],
            deliveryMethod: nonBlank(detail.deliveryMethod), salutation: "Dear Sir / Madam,",
            subject: "Re: \(nonBlank(detail.subject) ?? "\(detail.projectName) - \(detail.pricingMode)")",
            intro: "We thank you for your inquiry related to the item above, the following is our quotation on the job.",
            currencySymbol: currencySymbol(company), columns: pricedColumns, rows: rows,
            sections: remarks(detail.notes) + [LetterSection(heading: "Terms and Conditions", paragraphs: terms, keepTogether: true,
                                                                      alwaysNewPage: company.termsNewPage == "Always")],
            // The company's name right under "For and on Behalf of" (who
            // signs under the line); the client's side is "Accepted By".
            signatures: [
                companySignature(company, nameUnderHeading: true),
                LetterSignature(heading: "Accepted By", subheading: client.name, lines: [
                    LetterSignatureLine(text: "Position", colon: true),
                    LetterSignatureLine(text: "Date", colon: true),
                ]),
            ],
            closingLine: "-[Remainder of this page is intentionally left blank]-"
        )
    }

    /// Several quotations or BOQs of a project in one PDF, in the order
    /// given — each with its drawings (for a quotation, the BOQ it follows
    /// first) after it, if asked. Saved in the project's folder and opened.
    func handleCombineDocuments(id: String, kind: String, ids: [String], includeDrawings: Bool, mode: PDFMode = .export) {
        let company = db.getCompanySettings()
        let paper = company.paperSize ?? "A4"
        let paperSize = paper == "Letter" ? NSSize(width: 612, height: 792) : NSSize(width: 595.28, height: 841.89)
        // Each document: its number, project, and its pages (with drawings).
        var parts: [(number: String, projectNumber: String, data: Data)] = []
        for docId in ids {
            if kind == "BOQ" {
                guard let detail = db.getBOQDetail(id: docId), var data = boqPDFData(detail) else { continue }
                // (Its delivery schedule either way: it's part of the BOQ.)
                let extra = includeDrawings ? boqAttachments(detail.id) : [deliveryScheduleFile(kind: "BOQ", id: detail.id)].compactMap { $0 }
                data = PDFAttachments.append(extra, to: data, paperSize: paperSize)
                parts.append((detail.boqNumber, detail.projectNumber, data))
            } else if kind == "Invoice" {
                guard let detail = db.getInvoiceDetail(id: docId), let generator = PDFGenerator(paperSize: paper) else { continue }
                let data = PDFAttachments.append(db.signedDeliveryNoteFiles(invoiceId: detail.id), to: generator.generate(invoiceLetter(detail, company: company)), paperSize: paperSize)
                parts.append((detail.invoiceNumber, detail.projectNumber, data))
            } else if kind == "DeliveryNote" {
                guard let detail = db.getDeliveryNoteDetail(id: docId), let note = db.getDeliveryNote(id: docId),
                      let generator = PDFGenerator(paperSize: paper) else { continue }
                parts.append((detail.deliveryNoteNumber, detail.projectNumber, generator.generate(deliveryNoteLetter(detail, note: note, company: company))))
            } else {
                guard let detail = db.getQuotationDetail(id: docId), var data = quotationPDFData(detail) else { continue }
                let extra = includeDrawings ? quotationAttachments(detail) : [deliveryScheduleFile(kind: "Quotation", id: detail.id)].compactMap { $0 }
                data = PDFAttachments.append(extra, to: data, paperSize: paperSize)
                parts.append((detail.quotationNumber, detail.projectNumber, data))
            }
        }
        let (label, subfolder): (String, String) = {
            switch kind {
            case "BOQ": return ("BOQs", "BOQ")
            case "Invoice": return ("Invoices", "Invoices")
            case "DeliveryNote": return ("Delivery Notes", "Delivery Notes")
            default: return ("Quotations", "Quotations")
            }
        }()
        guard let first = parts.first else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Nothing to export.", path: nil))
            return
        }
        let combined = PDFDocument()
        for part in parts {
            guard let doc = PDFDocument(data: part.data) else { continue }
            for i in 0..<doc.pageCount {
                if let page = doc.page(at: i)?.copy() as? PDFPage { combined.insert(page, at: combined.pageCount) }
            }
        }
        guard combined.pageCount > 0, let data = combined.dataRepresentation() else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "The PDF couldn't be made.", path: nil))
            return
        }
        let numbers = parts.map { $0.number.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }
        let name = numbers.count <= 4 ? numbers.joined(separator: "+") : "\(numbers.count) \(label.lowercased()) \(letterDate(nowISO()).replacingOccurrences(of: "/", with: "-"))"
        let filename = "\(first.projectNumber)_\(label)_\(name)\(includeDrawings ? "_with drawings" : "").pdf"
        if mode == .preview {
            showPreview(id: id, data: data, PendingPreview(url: URL(fileURLWithPath: "/"), projectNumber: first.projectNumber, subfolder: subfolder,
                                                           documentNumber: name, docTypeTag: "Combined", fileName: filename))
            return
        }
        do {
            let destination = try storage.writeGeneratedFile(data: data, projectNumber: first.projectNumber, subfolder: "Other", meaningfulFilename: filename)
            self.openForUser(destination)
            if let project = db.getProjectByNumber(first.projectNumber) {
                db.logActivity(projectId: project.id, "\(label) exported as one PDF", reference: destination.lastPathComponent)
            }
            respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: destination.path))
        } catch {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "The PDF couldn't be saved to the project folder. Please check there's free disk space and try again.", path: nil))
        }
    }

    func handleExportInvoicePDF(id: String, invoiceId: String, mode: PDFMode = .export) {
        guard let detail = db.getInvoiceDetail(id: invoiceId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Invoice not found.", path: nil))
            return
        }
        let company = db.getCompanySettings()
        // The signed delivery notes it bills follow its own pages.
        deliverRenderedPDF(id: id, mode: mode, company: company, projectNumber: detail.projectNumber, subfolder: "Invoices",
                           documentNumber: detail.invoiceNumber, docTypeTag: "Invoice", letter: invoiceLetter(detail, company: company),
                           attachments: mode == .word ? [] : db.signedDeliveryNoteFiles(invoiceId: detail.id))
    }

    /// An invoice laid out on the letterhead.
    func invoiceLetter(_ detail: InvoiceDetail, company: CompanySettings) -> LetterDocument {
        let client = clientBlock(projectNumber: detail.projectNumber, fallbackName: detail.clientName)
        let isRental = detail.pricingMode == "Rental"
        let quotation = detail.sourceQuotationId.flatMap { db.getQuotation(id: $0) }
        // Billed in its quotation's currency (a crane job may be in US$).
        var company = company
        if let code = nonBlank(quotation?.currency) { company.currency = code }

        func rowsFor(_ lines: [InvoiceLineItem]) -> (materials: [LetterTableRow], delivery: [LetterTableRow]) {
            pricedRows(lines.map { (description: $0.itemDescription, unit: $0.unit, quantity: $0.quantity,
                                    price: $0.appliedUnitPrice, isDelivery: $0.section == "Delivery",
                                    discountType: $0.discountType, discountValue: $0.discountValue) },
                       currency: currencySymbol(company),
                       rateSuffix: { unit in isRental ? " /Month" : (unit.isEmpty || unit == "pc" ? "" : " /\(unit)") })
        }
        let ownLines = detail.lineItems.filter { $0.chargeGroup == nil }
        let priced = rowsFor(ownLines.filter { $0.materialGroup == nil })
        var rows = priced.materials
        // Deliveries for other quotations on the same invoice: a section each,
        // the invoice's own quotation first under its number.
        var materialGroups: [String] = []
        for line in ownLines { if let g = line.materialGroup, !materialGroups.contains(g) { materialGroups.append(g) } }
        if !materialGroups.isEmpty {
            if !rows.isEmpty, let q = quotation {
                rows.insert(.section(q.quotationNumber + (nonBlank(q.subject).map { " — \($0)" } ?? "")), at: 0)
            }
            for group in materialGroups {
                rows.append(.section(group))
                rows += rowsFor(ownLines.filter { $0.materialGroup == group && $0.section != "Delivery" }).materials
            }
        }
        if isRental && !priced.materials.isEmpty {
            // As on the quotation: the monthly charge, then the months charged.
            let period = nonBlank(detail.rentalPeriod).map { " (\($0))" } ?? ""
            if detail.rentalMonths > 1 {
                rows.append(.summary(label: "Monthly Rental Charge:", value: formatMoney(detail.materialsSubtotal), emphasized: false))
                rows.append(.summary(label: "Rental for \(detail.rentalMonths) Months\(period):", value: formatMoney(detail.materialsCharge), emphasized: false))
            } else {
                rows.append(.summary(label: "Monthly Rental Charge\(period):", value: formatMoney(detail.materialsCharge), emphasized: false))
            }
        }
        if !priced.delivery.isEmpty {
            rows.append(.section("Delivery Charges"))
            rows += priced.delivery
        }
        // One-off charges from the quotation's priced sections, under their titles.
        let charges = detail.lineItems.filter { $0.chargeGroup != nil }
        var groups: [String] = []
        for line in charges { if let g = line.chargeGroup, !groups.contains(g) { groups.append(g) } }
        for group in groups {
            rows.append(.section(group))
            for (n, line) in charges.filter({ $0.chargeGroup == group }).enumerated() {
                let note = lineDiscountNote(discountType: line.discountType, discountValue: line.discountValue, currencySymbol: currencySymbol(company))
                let description = note.map { "\(line.itemDescription)\n\($0)" } ?? line.itemDescription
                let unit = line.unit.trimmingCharacters(in: .whitespaces)
                let total = netLineAmount(quantity: line.quantity, unitPrice: line.appliedUnitPrice, discountType: line.discountType, discountValue: line.discountValue)
                rows.append(.item(["\(line.chargePrefix ?? "")\(n + 1)", description, "\(formatMoney(line.appliedUnitPrice))\(unit.isEmpty ? "" : " /\(unit)")",
                                   formatQuantity(line.quantity), formatMoney(doubleOf(total))]))
            }
        }
        // A subtotal only when something is taken off or added on.
        if detail.discountAmount > 0 || detail.taxAmount > 0 {
            rows.append(.summary(label: "Subtotal:", value: formatMoney(detail.subtotal), emphasized: false))
        }
        if detail.discountAmount > 0 {
            rows.append(.summary(label: "Less Discount:", value: "-\(formatMoney(detail.discountAmount))", emphasized: false))
        }
        if detail.taxAmount > 0 {
            let label = (company.pricesIncludeTax ?? false) ? "Tax / VAT included:" : "Tax / VAT (\(formatMoney(detail.taxRatePercent))%):"
            rows.append(.summary(label: label, value: formatMoney(detail.taxAmount), emphasized: false))
        }
        // The total in words: "SAY HONG KONG DOLLARS … ONLY".
        rows.append(.summary(label: amountInWords(detail.total, currency: company.currency), value: formatMoney(detail.total), emphasized: true))
        if detail.amountPaid > 0 {
            rows.append(.summary(label: "Less Amount Paid:", value: "-\(formatMoney(detail.amountPaid))", emphasized: false))
            rows.append(.summary(label: "Balance Due:", value: formatMoney(detail.balanceDue), emphasized: true))
        }

        var payment: [LetterParagraph] = []
        // The standard terms (with the bank details), as formatted in Settings.
        if let terms = nonBlank(detail.paymentTerms) { payment += formattedParagraphs(terms) }
        if let bank = nonBlank(company.bankDetails) { payment.append(.text(bank, link: nil)) }
        var sections = remarks(detail.notes)
        if !payment.isEmpty { sections.append(LetterSection(heading: "Payment Information", paragraphs: payment)) }

        var refRows: [(label: String, value: String)] = [("Invoice No.", detail.invoiceNumber)]
        if let number = detail.sourceQuotationNumber { refRows.append(("Quotation No.", number)) }
        if let yourRef = nonBlank(quotation?.clientRef) { refRows.append(("Your Ref. No.", yourRef)) }
        refRows += [("Site Ref.", nonBlank(quotation?.siteRef) ?? siteReference(projectNumber: detail.projectNumber)), ("Date", letterDate(detail.invoiceDate))]
        if let due = nonBlank(detail.dueDate) { refRows.append(("Due Date", letterDate(due))) }

        return LetterDocument(
            number: detail.invoiceNumber, status: detail.status, title: "INVOICE",
            clientName: client.name, clientLines: client.lines, refRows: refRows,
            deliveryMethod: nil, salutation: nil,
            subject: "Re: \(nonBlank(quotation?.subject) ?? "\(detail.projectNumber) \(detail.projectName)")", intro: nil,
            currencySymbol: currencySymbol(company), columns: pricedColumns, rows: rows,
            sections: sections, signatures: [companySignature(company)], closingLine: nil
        )
    }

    /// The delivery note as the company's own (e.g. DN26038a): Our Ref. No.,
    /// Site Ref. and Date, "BY HAND ONLY", "Delivery Note", then Delivery
    /// Address / Site Reference / Project / Contact Person, the materials
    /// with their weights and the total weight, and lines for the person
    /// receiving them to fill in.
}

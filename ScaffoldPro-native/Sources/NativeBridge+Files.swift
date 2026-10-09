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
    // ---- Letters ----

    /// A new letter, addressed to the client given (or the project's client).
    func handleCreateLetter(id: String, payload: [String: Any]) {
        let projectId = nonBlank(payload["projectId"] as? String)
        let project = projectId.flatMap { db.getProject(id: $0) }
        let clientId = nonBlank(payload["clientId"] as? String) ?? project?.clientId
        var name: String? = nil, address: String? = nil, attention: String? = nil
        if let client = clientId.flatMap({ db.getClient(id: $0) }) {
            let block = clientBlock(client)
            name = block.name
            address = block.lines.joined(separator: "\n")
            attention = client.contactPerson
        }
        switch db.createLetter(projectId: project?.id, clientId: clientId, recipientName: name, recipientAddress: address, attention: attention) {
        case .success(let letter): respond(id: id, encodable: LetterActionResult(ok: true, error: nil, id: letter.id))
        case .failure(let e): respond(id: id, encodable: LetterActionResult(ok: false, error: e.message, id: nil))
        }
    }

    func htmlEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The letter's opening as the editor shows it (the PDF draws it
    /// natively, as on the quotations): recipient on the left with "Attn:"
    /// bold and underlined; Our Ref. No., Your Ref. No. and Date on the
    /// right; then the "Re:" line, bold and underlined.
    func letterOpeningHTML(_ letter: Letter) -> String {
        let o = letterOpening(letter)
        var left = ""
        if let name = nonBlank(o.recipientName) { left += "<b>\(htmlEscaped(name))</b><br>" }
        for line in o.addressLines { left += "\(htmlEscaped(line))<br>" }
        if let attn = nonBlank(o.attention) { left += "<br><b><u>Attn: \(htmlEscaped(attn))</u></b>" }
        let refs = o.refRows.map { "<tr><td class=\"ref-label\">\(htmlEscaped($0.label))</td><td class=\"ref-colon\">:</td><td class=\"ref-value\">\(htmlEscaped($0.value))</td></tr>" }.joined()
        var html = "<div class=\"opening-grid\"><div class=\"opening-to\">\(left)</div><table class=\"opening-refs\">\(refs)</table></div>"
        if let subject = nonBlank(o.subject) { html += "<p class=\"opening-re\"><b><u>Re: \(htmlEscaped(subject))</u></b></p>" }
        return html
    }

    func letterOpening(_ letter: Letter) -> LetterOpening {
        var refs: [(label: String, value: String)] = [("Our Ref. No.", letter.letterNumber)]
        if let yours = nonBlank(letter.yourRef) { refs.append(("Your Ref. No.", yours)) }
        refs.append(("Date", letterDate(letter.letterDate)))
        return LetterOpening(recipientName: letter.recipientName,
                             addressLines: (letter.recipientAddress ?? "").components(separatedBy: "\n").compactMap { nonBlank($0) },
                             attention: letter.attention, refRows: refs, subject: letter.subject)
    }

    /// Stand-in for EB Garamond while the HTML is read: AppKit's HTML reader
    /// runs where the app's own fonts aren't installed, so EB Garamond would
    /// come out as Georgia or Times. Baskerville is on every Mac and isn't
    /// offered in the editor; it's swapped back for EB Garamond afterwards.
    static let letterFontStandIn = "Baskerville"

    /// The letter's body as formatted text for the PDF, in the fonts and
    /// sizes chosen in the editor.
    func letterAttributedText(_ letter: Letter) -> NSAttributedString? {
        let standIn = NativeBridge.letterFontStandIn
        let css = """
        body, p, td, th, li, h1, h2, h3, div, span { font-family: '\(standIn)'; }
        body { font-size: 11pt; }
        p { margin: 0 0 3pt 0; }
        h1 { font-size: 18pt; margin: 8pt 0 4pt 0; } h2 { font-size: 15pt; margin: 6pt 0 3pt 0; } h3 { font-size: 13pt; margin: 4pt 0 2pt 0; }
        ul, ol { margin: 0 0 3pt 0; }
        table.grid { border-collapse: collapse; }
        table.grid td, table.grid th { border: 0.75pt solid #000; padding: 3pt 5pt; vertical-align: top; }
        """
        // Text the editor set in EB Garamond (or left in the default) uses the stand-in.
        var body = letter.bodyHTML
        for form in ["'EB Garamond'", "&quot;EB Garamond&quot;", "\"EB Garamond\"", "EB Garamond"] {
            body = body.replacingOccurrences(of: form, with: "'\(standIn)'")
        }
        guard let text = importHTML("<html><head><meta charset=\"utf-8\"><style>\(css)</style></head><body>\(body)</body></html>") else { return nil }
        // How the reader scales sizes (it may take px as pt, or not): a
        // 100-unit sample tells, so 11pt in the editor is 11pt on paper.
        let sample = importHTML("<html><body><span style=\"font-family:'\(standIn)';font-size:100pt\">M</span></body></html>")
        let sampleSize = (sample?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize ?? 100
        let scale = sampleSize > 1 ? 100 / sampleSize : 1
        let out = NSMutableAttributedString(attributedString: text)
        out.enumerateAttribute(.font, in: NSRange(location: 0, length: out.length)) { value, range, _ in
            guard let font = value as? NSFont else { return }
            let size = (font.pointSize * scale * 2).rounded() / 2
            var replacement = NSFont(descriptor: font.fontDescriptor, size: size) ?? font
            let family = font.familyName ?? ""
            // The stand-in, and the reader's own fallbacks, become EB Garamond.
            if family == standIn || family == "Times" || family == "Times New Roman" && !body.contains("Times New Roman") {
                let traits = font.fontDescriptor.symbolicTraits
                let name: String
                switch (traits.contains(.bold), traits.contains(.italic)) {
                case (true, true): name = "EBGaramond-BoldItalic"
                case (true, false): name = "EBGaramond-Bold"
                case (false, true): name = "EBGaramond-Italic"
                case (false, false): name = "EBGaramond-Regular"
                }
                replacement = NSFont(name: name, size: size) ?? replacement
            }
            out.addAttribute(.font, value: replacement, range: range)
        }
        // The annexures, listed under the letter: "ANNEXURE P.01 : …".
        if let annexes = letter.attachments, !annexes.isEmpty {
            let size: CGFloat = 12
            let regular = NSFont(name: "EBGaramond-Regular", size: size) ?? NSFont.systemFont(ofSize: size)
            let bold = NSFont(name: "EBGaramond-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size)
            let labels = annexes.indices.map { annexureLabel(letter, $0) }
            let labelWidth = labels.map { ($0 as NSString).size(withAttributes: [.font: bold]).width }.max() ?? 0
            let colonX = labelWidth + 6
            let heading = NSMutableParagraphStyle()
            heading.paragraphSpacingBefore = 14
            heading.paragraphSpacing = 6
            out.append(NSAttributedString(string: "\nAttachments:\n", attributes: [.font: bold, .paragraphStyle: heading]))
            for (i, annex) in annexes.enumerated() {
                let style = NSMutableParagraphStyle()
                style.tabStops = [NSTextTab(textAlignment: .left, location: colonX), NSTextTab(textAlignment: .left, location: colonX + 12)]
                style.headIndent = colonX + 12
                style.paragraphSpacing = 2
                let line = NSMutableAttributedString(string: "\(labels[i])\t:\t", attributes: [.font: bold, .paragraphStyle: style])
                line.append(NSAttributedString(string: (nonBlank(annex.description) ?? "") + (i == annexes.count - 1 ? "" : "\n"),
                                               attributes: [.font: regular, .paragraphStyle: style]))
                out.append(line)
            }
        }
        return out
    }

    /// AppKit's HTML reader, with points passed as px (it reads CSS px as
    /// points); the size check above corrects it if that ever changes.
    func importHTML(_ raw: String) -> NSAttributedString? {
        let html = (try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)pt\b"#))
            .map { $0.stringByReplacingMatches(in: raw, range: NSRange(raw.startIndex..., in: raw), withTemplate: "$1px") } ?? raw
        guard let data = html.data(using: .utf8) else { return nil }
        return try? NSAttributedString(data: data, options: [.documentType: NSAttributedString.DocumentType.html,
                                                             .characterEncoding: String.Encoding.utf8.rawValue], documentAttributes: nil)
    }

    /// Saves the letter as a PDF (in its project's Letters folder, or
    /// Administration › Letters) and opens it, or prints it.
    /// Choose PDFs or pictures to attach to a letter: copied next to the
    /// letter (the project's Letters folder, or Administration › Letters).
    func handleAddLetterAttachment(id: String, letterId: String, attachmentId: String?) {
        guard let window = window, let letter = db.getLetter(id: letterId) else { respondNull(id: id); return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.pdf, .image]
        panel.message = "Choose the PDFs or pictures for this annexure. Copies are kept with the letter; the originals stay where they are."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, !panel.urls.isEmpty else { self.respondNull(id: id); return }
            let safe = letter.letterNumber.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let project = letter.projectId.flatMap { self.db.getProject(id: $0) }
            let folder = (project.map { self.storage.projectSubfolder($0.projectNumber, "Letters") }
                ?? self.storage.administrationCategoryFolder("Letters")).appendingPathComponent("\(safe) Attachments", isDirectory: true)
            var copied: [String] = []
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                for url in panel.urls {
                    let destination = self.storage.uniqueDestination(folder.appendingPathComponent(url.lastPathComponent))
                    try FileManager.default.copyItem(at: url, to: destination)
                    copied.append(destination.path)
                }
            } catch {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "The files couldn’t be copied: \(error.localizedDescription)"))
                return
            }
            switch self.db.addLetterAttachmentFiles(letterId: letterId, attachmentId: attachmentId, paths: copied) {
            case .success(let list):
                struct AttachResult: Encodable { var ok: Bool; var attachments: [LetterAttachment] }
                self.respond(id: id, encodable: AttachResult(ok: true, attachments: list))
            case .failure(let e):
                self.respond(id: id, encodable: SimpleResult(ok: false, error: e.message))
            }
        }
    }

    /// The letter's pages, then each annexure: its cover page, then its files.
    func letterPDFWithAnnexures(_ letter: Letter, body: Data, paper: String) -> Data {
        guard let annexes = letter.attachments, !annexes.isEmpty else { return body }
        let size = paper == "Letter" ? NSSize(width: 612, height: 792) : NSSize(width: 595.28, height: 841.89)
        // The cover's opening: as the letter's, without our reference or the "Re:" line.
        var opening = letterOpening(letter)
        opening.refRows.removeAll { $0.label == "Our Ref. No." }
        opening.subject = nil
        var parts = [body]
        var pages = PDFDocument(data: body)?.pageCount ?? 1
        for (i, annex) in annexes.enumerated() {
            guard let generator = PDFGenerator(paperSize: paper) else { continue }
            let cover = generator.annexureCover(opening: opening, title: annexureLabel(letter, i), pageNumber: pages + 1)
            let files = annex.files.map { URL(fileURLWithPath: $0) }.filter { FileManager.default.fileExists(atPath: $0.path) }
            let part = PDFAttachments.append(files, to: cover, paperSize: size)
            pages += PDFDocument(data: part)?.pageCount ?? 1
            parts.append(part)
        }
        let joined = PDFDocument()
        for part in parts {
            guard let doc = PDFDocument(data: part) else { continue }
            for p in 0..<doc.pageCount {
                if let page = doc.page(at: p)?.copy() as? PDFPage { joined.insert(page, at: joined.pageCount) }
            }
        }
        return joined.dataRepresentation() ?? body
    }

    func handleExportLetter(id: String, letterId: String, mode: PDFMode) {
        guard let letter = db.getLetter(id: letterId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Letter not found.", path: nil))
            return
        }
        let paper = db.getCompanySettings().paperSize ?? "A4"
        guard let generator = PDFGenerator(paperSize: paper), let text = letterAttributedText(letter) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Could not prepare the letter.", path: nil))
            return
        }
        let data = letterPDFWithAnnexures(letter, body: generator.generateRichText(text, opening: letterOpening(letter)), paper: paper)
        let size = paper == "Letter" ? NSSize(width: 612, height: 792) : NSSize(width: 595.28, height: 841.89)
        let project = letter.projectId.flatMap { db.getProject(id: $0) }
        if project != nil || mode == .print {
            deliverPDF(id: id, mode: mode, data: data, paperSize: size, projectNumber: project?.projectNumber ?? "",
                       subfolder: "Letters", documentNumber: letter.letterNumber, docTypeTag: "Letter")
            return
        }
        let safe = letter.letterNumber.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let folder = storage.administrationCategoryFolder("Letters")
        if mode == .preview {
            let mark = letter.status == "Draft" ? "DRAFT" : letter.status == "Cancelled" ? "CANCELLED" : nil
            showPreview(id: id, data: mark.map { PDFWatermark.stamp(data, text: $0) } ?? data,
                        PendingPreview(url: URL(fileURLWithPath: "/"), projectNumber: "", subfolder: "", documentNumber: letter.letterNumber,
                                       docTypeTag: "Letter", fileName: "\(db.documentFileBase(docTypeTag: "Letter", number: letter.letterNumber) ?? "Letter_\(safe)").pdf", folder: folder))
            return
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent("\(db.documentFileBase(docTypeTag: "Letter", number: letter.letterNumber) ?? "Letter_\(safe)").pdf")
            try data.write(to: destination, options: .atomic)
            db.recordGeneratedPDF(docTypeTag: "Letter", documentNumber: letter.letterNumber, path: destination.path)
            self.openForUser(destination)
            respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: destination.path))
        } catch {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "The PDF couldn't be saved: \(error.localizedDescription)", path: nil))
        }
    }

    /// A letter as a Word document (js/docx-export.js): the letterhead, the
    /// opening as on the PDF, and the body as typed (its HTML, read on the
    /// page). Saved into the project's Letters folder.
    func handleExportLetterWord(id: String, letterId: String) {
        guard let letter = db.getLetter(id: letterId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Letter not found.", path: nil))
            return
        }
        guard let project = letter.projectId.flatMap({ db.getProject(id: $0) }) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Attach the letter to a project before saving it as a Word document.", path: nil))
            return
        }
        let paper = db.getCompanySettings().paperSize ?? "A4"
        guard let generator = PDFGenerator(paperSize: paper), let png = PDFGenerator.letterheadPNG(paperSize: paper) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Could not prepare the letterhead for the Word document.", path: nil))
            return
        }
        let opening = letterOpening(letter)
        var clientLines = opening.addressLines
        if let attention = nonBlank(opening.attention) { clientLines.append("Attn: \(attention)") }
        var layout = WordLayout(paperSize: paper, pageWidth: Double(generator.pageWidth), pageHeight: Double(generator.pageHeight),
                                textLeft: Double(generator.textLeft), textRight: Double(generator.textRight), contentBottom: Double(generator.contentBottom),
                                number: letter.letterNumber, status: letter.status, title: "", clientName: nonBlank(opening.recipientName) ?? "",
                                clientLines: clientLines, refRows: opening.refRows.map { WordRefRow(label: $0.label, value: $0.value, wraps: false) },
                                refColon: 478.5, subject: nonBlank(opening.subject).map { "Re: \($0)" },
                                currencySymbol: "", columns: [], rows: [], sections: [], signatures: [])
        layout.letterheadPNG = png.base64EncodedString()
        layout.bodyHTML = letter.bodyHTML
        layout.projectNumber = project.projectNumber
        layout.subfolder = "Letters"
        let safe = letter.letterNumber.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        layout.fileName = "\(db.documentFileBase(docTypeTag: "Letter", number: letter.letterNumber) ?? "Letter_\(safe)").docx"
        if let fonts = Bundle.main.resourceURL?.appendingPathComponent("resources/fonts", isDirectory: true) {
            for (style, file) in [("regular", "EBGaramond-Regular"), ("bold", "EBGaramond-Bold"), ("italic", "EBGaramond-Italic"), ("boldItalic", "EBGaramond-BoldItalic")] {
                if let data = try? Data(contentsOf: fonts.appendingPathComponent("\(file).ttf")) {
                    layout.fonts.append(WordFont(style: style, data: data.base64EncodedString()))
                }
            }
        }
        respond(id: id, encodable: layout)
    }

    /// A letter as a Word document (js/docx-export.js): the letterhead, the
    /// opening as on the PDF, and the body as typed (its HTML, read on the
    /// page). Saved into the project's Letters folder.
    func handleExportLetterWord(id: String, letterId: String) {
        guard let letter = db.getLetter(id: letterId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Letter not found.", path: nil))
            return
        }
        guard let project = letter.projectId.flatMap({ db.getProject(id: $0) }) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Attach the letter to a project before saving it as a Word document.", path: nil))
            return
        }
        let paper = db.getCompanySettings().paperSize ?? "A4"
        guard let generator = PDFGenerator(paperSize: paper), let png = PDFGenerator.letterheadPNG(paperSize: paper) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Could not prepare the letterhead for the Word document.", path: nil))
            return
        }
        let opening = letterOpening(letter)
        var clientLines = opening.addressLines
        if let attention = nonBlank(opening.attention) { clientLines.append("Attn: \(attention)") }
        var layout = WordLayout(paperSize: paper, pageWidth: Double(generator.pageWidth), pageHeight: Double(generator.pageHeight),
                                textLeft: Double(generator.textLeft), textRight: Double(generator.textRight), contentBottom: Double(generator.contentBottom),
                                number: letter.letterNumber, status: letter.status, title: "", clientName: nonBlank(opening.recipientName) ?? "",
                                clientLines: clientLines, refRows: opening.refRows.map { WordRefRow(label: $0.label, value: $0.value, wraps: false) },
                                refColon: 478.5, subject: nonBlank(opening.subject).map { "Re: \($0)" },
                                currencySymbol: "", columns: [], rows: [], sections: [], signatures: [])
        layout.letterheadPNG = png.base64EncodedString()
        layout.bodyHTML = letter.bodyHTML
        layout.projectNumber = project.projectNumber
        layout.subfolder = "Letters"
        let safe = letter.letterNumber.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        layout.fileName = "\(db.documentFileBase(docTypeTag: "Letter", number: letter.letterNumber) ?? "Letter_\(safe)").docx"
        if let fonts = Bundle.main.resourceURL?.appendingPathComponent("resources/fonts", isDirectory: true) {
            for (style, file) in [("regular", "EBGaramond-Regular"), ("bold", "EBGaramond-Bold"), ("italic", "EBGaramond-Italic"), ("boldItalic", "EBGaramond-BoldItalic")] {
                if let data = try? Data(contentsOf: fonts.appendingPathComponent("\(file).ttf")) {
                    layout.fonts.append(WordFont(style: style, data: data.base64EncodedString()))
                }
            }
        }
        respond(id: id, encodable: layout)
    }

    func handleExportDeliveryNotePDF(id: String, deliveryNoteId: String, mode: PDFMode = .export) {
        guard let detail = db.getDeliveryNoteDetail(id: deliveryNoteId), let note = db.getDeliveryNote(id: deliveryNoteId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Delivery note not found.", path: nil))
            return
        }
        let company = db.getCompanySettings()
        deliverRenderedPDF(id: id, mode: mode, company: company, projectNumber: detail.projectNumber, subfolder: "Delivery Notes",
                           documentNumber: detail.deliveryNoteNumber, docTypeTag: "DeliveryNote",
                           letter: onOnePage(deliveryNoteLetter(detail, note: note, company: company), paper: company.paperSize ?? "A4"))
    }

    /// A delivery note that just spills onto a second page — its items there
    /// would fill no more than a quarter of it — is drawn with its rows a
    /// little closer together so that it all fits on one page. One with more
    /// than that keeps its second page.
    func onOnePage(_ letter: LetterDocument, paper: String) -> LetterDocument {
        func pages(_ doc: LetterDocument) -> Int {
            guard let generator = PDFGenerator(paperSize: paper) else { return 1 }
            return PDFDocument(data: generator.generate(doc))?.pageCount ?? 1
        }
        guard pages(letter) > 1 else { return letter }
        let items = Double(letter.rows.count)
        let quarterPage = (paper == "Letter" ? 792.0 : 841.89) / 4
        for height in [20.0, 19.0, 18.0, 17.2, 16.5] {
            // Squeezing more than a quarter page's worth: it stays on two pages.
            guard items * (21.1 - height) <= quarterPage else { break }
            var tighter = letter
            tighter.tableRowHeight = height
            if pages(tighter) == 1 { return tighter }
        }
        return letter
    }

    /// A delivery note laid out on the letterhead (as DN26038a).
    func deliveryNoteLetter(_ detail: DeliveryNoteDetail, note: DeliveryNote, company: CompanySettings) -> LetterDocument {
        let client = clientBlock(projectNumber: detail.projectNumber, fallbackName: detail.clientName)
        let project = db.getProjectByNumber(detail.projectNumber)
        let site = project.flatMap { db.getSite(id: $0.siteId) }
        let siteRef = nonBlank(site?.siteReference)
        // "MTR 1635 Kwu Tung Station": the site's reference and name.
        var siteLine = site.map { $0.name } ?? ""
        if let ref = siteRef, !siteLine.contains(ref) { siteLine = siteLine.isEmpty ? ref : "\(ref) \(siteLine)" }
        let pricingMode = note.sourceQuotationId.flatMap { db.getQuotation(id: $0)?.pricingMode }
            ?? note.sourceInvoiceId.flatMap { db.getInvoice(id: $0)?.pricingMode }
        let projectLine = [pricingMode, detail.projectName].compactMap { nonBlank($0) }.joined(separator: " - ")
        var info: [LetterInfoRow] = []
        if let address = nonBlank(detail.deliveryAddress) { info.append(LetterInfoRow(label: "Delivery Address", value: address)) }
        if !siteLine.isEmpty { info.append(LetterInfoRow(label: "Site Reference", value: siteLine)) }
        if !projectLine.isEmpty { info.append(LetterInfoRow(label: "Project", value: projectLine)) }
        if let contact = nonBlank(detail.contactPerson) { info.append(LetterInfoRow(label: "Contact Person", value: contact, boldValue: true)) }

        // Item names (and the table's headings) in English or in Chinese,
        // for workers who read Chinese.
        let inChinese = db.printsInChinese(note.language)
        let columns = [
            LetterColumn(title: inChinese ? "編號" : "No", width: 29.25, kind: .center),
            LetterColumn(title: inChinese ? "物料名稱" : "Item Description", width: 290.75, kind: .left),
            LetterColumn(title: inChinese ? "單位重量" : "Unit Weight", width: 75.0, kind: .weight),
            LetterColumn(title: inChinese ? "數量" : "Qty", width: 39.0, kind: .center),
            LetterColumn(title: inChinese ? "總重量" : "Total Weight", width: 76.0, kind: .weight),
        ]
        let priceItems = db.allPriceListItems()
        let zh = inChinese
            ? db.chineseNames(for: detail.lineItems, id: { $0.id }, itemId: { $0.priceListItemId }, description: { $0.itemDescription }) : [:]
        var totalKg = Decimal(0)
        var rows: [LetterTableRow] = detail.lineItems.enumerated().map { index, item in
            let qty = item.quantity.rounded()
            let kg = db.deliveryNoteWeight(item, in: priceItems)
            if let kg = kg { totalKg += decimalOf(kg) * decimalOf(qty) }
            return .item([String(index + 1), lineDescription(documentItemName(item.itemDescription, zh[item.id], inChinese: inChinese), notes: item.notes),
                          kg.map { String(format: "%.1f", $0) } ?? "", formatQuantity(qty),
                          kg.map { String(format: "%.1f", $0 * qty) } ?? ""])
        }
        if !rows.isEmpty {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
            let total = formatter.string(from: NSDecimalNumber(decimal: totalKg)) ?? String(format: "%.1f", doubleOf(totalKg))
            rows.append(.summary(label: inChinese ? "總重量:" : "Total Weight:", value: total, emphasized: false))
        }

        var letter = LetterDocument(
            number: detail.deliveryNoteNumber, status: detail.status, title: "Delivery Note",
            clientName: client.name, clientLines: client.lines,
            refRows: [("Our Ref. No.", detail.deliveryNoteNumber), ("Site Ref.", siteRef ?? "N/a"), ("Date", letterDate(detail.deliveryDate))],
            deliveryMethod: "BY HAND ONLY", salutation: nil, subject: nil, intro: nil,
            currencySymbol: currencySymbol(company), columns: columns, rows: rows,
            sections: remarks(detail.notes), signatures: [], closingLine: nil
        )
        letter.infoRows = info
        letter.compactTable = true
        letter.receiptRows = [("Received By", "Date"), ("Full Name", "Contact No.")]
        return letter
    }

    /// Edit Project Details › Project Code: renames the project's folder
    /// (Documents/ScaffoldPro/Projects/<code>), re-points every file kept in
    /// it, and renumbers its draft documents.
    func handleChangeProjectNumber(id: String, projectId: String, newNumber raw: String) {
        let newNumber = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        func fail(_ message: String) { respond(id: id, encodable: SimpleResult(ok: false, error: message)) }
        guard let project = db.getProject(id: projectId) else { return fail("Project not found.") }
        guard !newNumber.isEmpty else { return fail("Enter a project code.") }
        guard newNumber.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\\")) == nil, !newNumber.hasPrefix(".") else {
            return fail("A project code can't contain / : or \\ or start with a dot.")
        }
        let old = project.projectNumber
        guard newNumber != old else { return respond(id: id, encodable: SimpleResult(ok: true, error: nil)) }
        guard !db.allProjectNumbers().contains(where: { $0.caseInsensitiveCompare(newNumber) == .orderedSame }) else {
            return fail("Another project already has the code \(newNumber).")
        }
        let fm = FileManager.default
        let oldFolder = storage.projectFolder(old)
        let newFolder = storage.projectFolder(newNumber)
        if fm.fileExists(atPath: oldFolder.path) {
            if fm.fileExists(atPath: newFolder.path) {
                // An empty leftover folder can go; anything else is kept.
                let contents = ((try? fm.contentsOfDirectory(atPath: newFolder.path)) ?? []).filter { $0 != ".DS_Store" }
                guard contents.isEmpty else {
                    return fail("There's already a folder called \(newNumber) in ScaffoldPro/Projects. Rename or move it in Finder first.")
                }
                try? fm.removeItem(at: newFolder)
            }
            do {
                try fm.moveItem(at: oldFolder, to: newFolder)
            } catch {
                return fail("The project folder couldn't be renamed (\(error.localizedDescription)). Close any of its files that are open and try again.")
            }
            db.rebaseFilePaths(from: oldFolder.path, to: newFolder.path)
        }
        db.setProjectNumber(id: project.id, to: newNumber)
        // "<new number> <name>", and its folders "<new number> BOQ"…
        organiseProjectFolders([newNumber])
        respond(id: id, encodable: SimpleResult(ok: true, error: nil))
    }

    func projectListEntries() -> [ProjectListEntry] {
        // All clients/sites, including archived ones, so older projects
        // still show who they belong to.
        let clients = db.allClients()
        let sites = db.allSites()
        let names = db.authorsByRecord("projects.json")
        let stats = db.projectStats()
        return db.listProjectsRaw().map { p in
            var entry = ProjectListEntry(
                id: p.id, projectNumber: p.projectNumber, name: p.name,
                clientId: p.clientId, siteId: p.siteId, status: p.status, createdAt: p.createdAt,
                clientName: clients.first { $0.id == p.clientId }?.companyName,
                siteName: sites.first { $0.id == p.siteId }?.name
            )
            entry.jobType = normalJobType(p.jobType)
            entry.createdBy = names[p.id]?.createdBy
            entry.lastEditedBy = names[p.id]?.lastEditedBy
            if let st = stats[p.id] {
                entry.boqCount = st.boqs
                entry.quotationCount = st.quotations
                entry.invoiceCount = st.invoices
                entry.deliveryNoteCount = st.deliveryNotes
                entry.lastActivityAt = st.lastActivityAt.isEmpty ? nil : st.lastActivityAt
            }
            return entry
        }
    }

    func handleCreateProject(id: String, payload: [String: Any]) {
        let name = (payload["name"] as? String) ?? ""
        let clientId = (payload["clientId"] as? String) ?? ""
        let siteId = (payload["siteId"] as? String) ?? ""
        let overrideNumber = (payload["overrideNumber"] as? Bool) ?? false
        let manualNumber = (payload["manualNumber"] as? String) ?? ""

        guard !name.isEmpty, !clientId.isEmpty, !siteId.isEmpty else {
            respond(id: id, encodable: ProjectCreateResult(ok: false, error: "Project name, client, and site are all required.", project: nil, folder: nil))
            return
        }

        let existing = db.allProjectNumbers()
        let numberToUse = overrideNumber ? manualNumber : nextProjectNumber(existingNumbers: existing)

        let check = validateProjectNumber(numberToUse, existingNumbers: existing)
        guard check.valid else {
            respond(id: id, encodable: ProjectCreateResult(ok: false, error: check.reason, project: nil, folder: nil))
            return
        }

        var project = db.createProject(projectNumber: numberToUse, name: name, clientId: clientId, siteId: siteId)
        // Optional details entered at creation (section 13).
        var optional = payload
        optional.removeValue(forKey: "name")
        optional.removeValue(forKey: "clientId")
        optional.removeValue(forKey: "siteId")
        _ = db.updateProject(id: project.id, payload: optional, logChange: false)
        project = db.getProjectByNumber(numberToUse) ?? project
        let folder = storage.createProjectFolders(numberToUse)
        respond(id: id, encodable: ProjectCreateResult(ok: true, error: nil, project: project, folder: folder.path))
    }

    func handleGetProject(id: String, payload: [String: Any]) {
        let number = (payload["projectNumber"] as? String) ?? ""
        guard let project = db.getProjectByNumber(number) else {
            respondNull(id: id)
            return
        }
        organiseProjectFolders([project.projectNumber])
        let detail = ProjectDetail(
            id: project.id, projectNumber: project.projectNumber, name: project.name, status: project.status,
            projectDescription: project.projectDescription, startDate: project.startDate,
            expectedCompletionDate: project.expectedCompletionDate, projectManager: project.projectManager,
            internalNotes: project.internalNotes, createdAt: project.createdAt,
            client: db.getClient(id: project.clientId), site: db.getSite(id: project.siteId),
            jobType: normalJobType(project.jobType)
        )
        respond(id: id, encodable: detail)
    }

    /// Adds each file chosen in an upload panel. Replies with everything
    /// added; if some couldn't be copied, the rest are still added and the
    /// reply is an error naming the ones that failed.
    func addEachFile<T: Encodable>(id: String, urls: [URL], add: (URL) throws -> T) {
        var added: [T] = []
        var failed: [String] = []
        for url in urls {
            do {
                added.append(try add(url))
            } catch {
                failed.append("\(url.lastPathComponent): \(error.localizedDescription)")
            }
        }
        if failed.isEmpty {
            respond(id: id, encodable: added)
        } else {
            respondError(id: id, message: "\(added.count) of \(urls.count) file\(urls.count == 1 ? "" : "s") added. These couldn't be copied:\n\(failed.joined(separator: "\n"))")
        }
    }

    func handleUploadDrawing(id: String, projectNumber: String, linkedKind: String?, linkedId: String?) {
        guard let window = window else {
            respondNull(id: id)
            return
        }
        guard let project = db.getProjectByNumber(projectNumber) else {
            respondError(id: id, message: "Project not found.")
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = drawingContentTypes
        panel.message = "Choose one or more drawings: PDF, DWG, DXF or images. The originals stay where they are; copies go in the Drawings folder of the BOQ or quotation they're linked to (else the project's)."

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, !panel.urls.isEmpty else {
                self.respondNull(id: id)
                return
            }
            self.addEachFile(id: id, urls: panel.urls) { sourceURL -> UploadDrawingResult in
                try self.addDrawingFile(sourceURL, project: project, linkedKind: linkedKind, linkedId: linkedId)
            }
        }
    }

    /// Copies a drawing into the project's Drawings folder and records it.
    func addDrawingFile(_ sourceURL: URL, project: Project, linkedKind: String?, linkedId: String?) throws -> UploadDrawingResult {
        let originalName = sourceURL.lastPathComponent
        // Uploaded to a BOQ or quotation: into its series' Drawings folder.
        let destination = try storage.copyFileIntoProject(
            source: sourceURL, projectNumber: project.projectNumber,
            subfolder: "Drawings", meaningfulFilename: "\(project.projectNumber)_Drawing_\(originalName)",
            folder: linkedFileFolder(projectNumber: project.projectNumber, kind: linkedKind, linkedId: linkedId, sub: "Drawings")
        )
        db.recordDrawing(projectId: project.id, originalName: originalName, storedURL: destination, linkedKind: linkedKind, linkedId: linkedId)
        return UploadDrawingResult(originalName: originalName, destination: destination.path)
    }

    /// Copies a document into the project's Documents folder and records it.
    func addDocumentFile(_ sourceURL: URL, project: Project, category: String) throws -> ProjectDocument {
        let originalName = sourceURL.lastPathComponent
        let destination = try storage.copyFileIntoProject(
            source: sourceURL, projectNumber: project.projectNumber, subfolder: "Documents",
            meaningfulFilename: "\(project.projectNumber)_\(category.replacingOccurrences(of: " ", with: ""))_\(originalName)"
        )
        return db.recordDocument(projectId: project.id, originalName: originalName, category: category, storedURL: destination)
    }

    /// Files dropped onto a Drawings or Documents section. A web page can't
    /// see where a dropped file is, so each comes as base64; it's written
    /// to a temporary folder under its own name, then added like a chosen
    /// file. Drawings must be PDF, DWG, DXF or an image.
    func handleDroppedProjectFiles(id: String, payload: [String: Any]) {
        guard let project = db.getProjectByNumber((payload["projectNumber"] as? String) ?? "") else {
            respond(id: id, encodable: DroppedFilesResult(ok: false, added: 0, error: "Project not found."))
            return
        }
        let isDrawing = (payload["target"] as? String) != "document"
        let category = (payload["category"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Miscellaneous"
        let linkedKind = (payload["linkedKind"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let linkedId = (payload["linkedId"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("ScaffoldPro-drop-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        var added = 0
        var failed: [String] = []
        for (index, file) in ((payload["files"] as? [[String: Any]]) ?? []).enumerated() {
            let name = ((file["name"] as? String) ?? "").replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            guard !name.isEmpty, let base64 = file["base64"] as? String, let data = Data(base64Encoded: base64) else {
                failed.append("\(name.isEmpty ? "A file" : name): couldn't be read")
                continue
            }
            if isDrawing {
                let type = UTType(filenameExtension: (name as NSString).pathExtension.lowercased())
                guard let type = type, drawingContentTypes.contains(where: { type.conforms(to: $0) }) else {
                    failed.append("\(name): not a drawing (PDF, DWG, DXF or an image)")
                    continue
                }
            }
            do {
                // A folder each, so two dropped files with the same name don't clash.
                let folder = temp.appendingPathComponent("\(index)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appendingPathComponent(name)
                try data.write(to: url)
                if isDrawing {
                    _ = try addDrawingFile(url, project: project, linkedKind: linkedKind, linkedId: linkedId)
                } else {
                    _ = try addDocumentFile(url, project: project, category: category)
                }
                added += 1
            } catch {
                failed.append("\(name): \(error.localizedDescription)")
            }
        }
        respond(id: id, encodable: DroppedFilesResult(
            ok: failed.isEmpty, added: added,
            error: failed.isEmpty ? nil : "\(added) file\(added == 1 ? "" : "s") added. These couldn't be:\n\(failed.joined(separator: "\n"))"))
    }

    func handleUploadDocument(id: String, projectNumber: String, category: String) {
        guard let window = window else {
            respondNull(id: id)
            return
        }
        guard let project = db.getProjectByNumber(projectNumber) else {
            respondError(id: id, message: "Project not found.")
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose one or more documents."
        // Deliberately no allowedContentTypes restriction here — section
        // 34's general documents (contracts, correspondence, etc.) can
        // be any file type, unlike drawings.

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, !panel.urls.isEmpty else {
                self.respondNull(id: id)
                return
            }
            self.addEachFile(id: id, urls: panel.urls) { sourceURL -> ProjectDocument in
                try self.addDocumentFile(sourceURL, project: project, category: category)
            }
        }
    }

    /// Shared by drawings:relink / documents:relink / workerDocuments:relink
    /// / adminDocuments:relink — the person picks wherever the file
    /// actually is now, and we just re-point the record at it (section
    /// 38). Nothing is copied or moved.
    enum RelinkTarget {
        case drawing, document, workerDocument, adminDocument
    }

    func handleRelinkFile(id: String, recordId: String, target: RelinkTarget) {
        guard let window = window else {
            respondNull(id: id)
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let newURL = panel.url else {
                self.respondNull(id: id)
                return
            }
            let error: String?
            switch target {
            case .drawing: error = self.db.relinkDrawing(id: recordId, newPath: newURL.path)
            case .document: error = self.db.relinkDocument(id: recordId, newPath: newURL.path)
            case .workerDocument: error = self.db.relinkWorkerDocument(id: recordId, newPath: newURL.path)
            case .adminDocument: error = self.db.relinkAdminDocument(id: recordId, newPath: newURL.path)
            }
            self.respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        }
    }

    /// Worker documents land in Administration/Workers/<W001>/<Contracts|
    /// Certificates|Other>/ — section 35's layout.
    func handleUploadWorkerDocument(id: String, workerId: String, category: String, expiryDate: String?) {
        guard let window = window else {
            respondNull(id: id)
            return
        }
        guard let worker = db.getWorker(id: workerId) else {
            respondError(id: id, message: "Worker not found.")
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose one or more documents for \(worker.name)."

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, !panel.urls.isEmpty else {
                self.respondNull(id: id)
                return
            }
            let subfolder: String
            switch category {
            case "Employment Contract": subfolder = "Contracts"
            case "Certification", "Training Certificate": subfolder = "Certificates"
            default: subfolder = "Other"
            }
            self.addEachFile(id: id, urls: panel.urls) { sourceURL -> WorkerDocument in
                let originalName = sourceURL.lastPathComponent
                let destination = try self.storage.copyFile(
                    source: sourceURL,
                    into: self.storage.workerFolder(worker.workerNumber).appendingPathComponent(subfolder, isDirectory: true),
                    meaningfulFilename: "\(worker.workerNumber)_\(category.replacingOccurrences(of: " ", with: ""))_\(originalName)"
                )
                return self.db.recordWorkerDocument(workerId: worker.id, originalName: originalName, category: category, expiryDate: expiryDate, storedURL: destination)
            }
        }
    }

    /// General admin documents land in Administration/<folder>/ — the
    /// category picks the folder (section 35/43).
    func handleUploadAdminDocument(id: String, category: String, expiryDate: String?) {
        guard let window = window else {
            respondNull(id: id)
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose one or more documents."

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, !panel.urls.isEmpty else {
                self.respondNull(id: id)
                return
            }
            let folderName: String
            switch category {
            case "Contracts": folderName = "Contracts"
            case "Insurance": folderName = "Insurance"
            case "Licenses", "Certificates": folderName = "Licenses"
            case "Company Documents": folderName = "Company"
            default: folderName = "Other"
            }
            self.addEachFile(id: id, urls: panel.urls) { sourceURL -> AdminDocument in
                let originalName = sourceURL.lastPathComponent
                let destination = try self.storage.copyFile(
                    source: sourceURL,
                    into: self.storage.administrationCategoryFolder(folderName),
                    meaningfulFilename: originalName
                )
                return self.db.recordAdminDocument(originalName: originalName, category: category, expiryDate: expiryDate, storedURL: destination)
            }
        }
    }

    // MARK: Settings helpers

    /// Section 5/57: Follow System (default), or force Light / Dark. The
    /// web view's prefers-color-scheme follows the app's appearance, so
    /// the pages switch instantly.
    /// The Light / Dark of whoever is using ScaffoldPro (Settings › You ›
    /// Theme): kept with their colour, so it's theirs on any Mac. Before
    /// they choose: what this Mac had, else System — never someone else's.
    func ownAppearance() -> String {
        if let look = db.userAppearance(name: TeamSync.memberName) { return look }
        if TeamSync.actingAs == nil, let mine = UserDefaults.standard.string(forKey: "ScaffoldPro.appearance") { return mine }
        return "System"
    }

    func applyAppearance(_ value: String?) {
        switch value {
        case "Light": NSApp.appearance = NSAppearance(named: .aqua)
        case "Dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    func handleChooseLogo(id: String) {
        guard let window = window else { respondNull(id: id); return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .tiff]
        panel.message = "Choose your company logo (PNG with a transparent background works best)."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let source = panel.url else { self.respondNull(id: id); return }
            guard NSImage(contentsOf: source) != nil else {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "That file couldn't be read as an image."))
                return
            }
            let folder = self.storage.administrationCategoryFolder("Company")
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let dest = folder.appendingPathComponent("Company_Logo.\(source.pathExtension.lowercased())")
                if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
                try FileManager.default.copyItem(at: source, to: dest)
                self.db.setLogoPath(dest.path)
                self.respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            } catch {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "The logo couldn't be copied into the Company folder."))
            }
        }
    }

    // MARK: Price-list import / export (sections 8, 49)

    func handlePriceImportPreview(id: String, sourceKey: String) {
        guard let window = window else { respondNull(id: id); return }
        guard let list = db.listPriceLists().first(where: { $0.sourceKey == sourceKey }) else {
            respond(id: id, encodable: PriceImportPreview(ok: false, error: "Price list not found.", token: nil, fileName: nil, sheetName: nil, mapping: [], rowsFound: 0, toAdd: 0, toUpdate: 0, samples: []))
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")].compactMap { $0 }
        panel.message = "Choose an Excel workbook (.xlsx) to update “\(list.displayName)”."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let url = panel.url else { self.respondNull(id: id); return }
            func fail(_ message: String) {
                self.respond(id: id, encodable: PriceImportPreview(ok: false, error: message, token: nil, fileName: url.lastPathComponent, sheetName: nil, mapping: [], rowsFound: 0, toAdd: 0, toUpdate: 0, samples: []))
            }
            do {
                let sheets = url.pathExtension.lowercased() == "csv" ? try SpreadsheetReader.readCSV(url) : try SpreadsheetReader.readXLSX(url)
                // With several sheets, prefer one named after this list
                // (e.g. "SCAFOM"); otherwise the first one that makes sense.
                let named = sheets.filter { $0.name.lowercased().contains(sourceKey.lowercased()) }
                let otherLists = self.db.listPriceLists().map { $0.sourceKey.lowercased() }.filter { $0 != sourceKey.lowercased() }
                let unclaimed = sheets.filter { sh in !otherLists.contains { sh.name.lowercased().contains($0) } }
                let ordered = named + unclaimed + sheets
                let firstMatch = ordered.lazy.compactMap({ sh -> (SpreadsheetSheet, (rows: [ParsedPriceRow], mapping: [String]))? in
                    guard let parsed = PriceSheetInterpreter.interpret(sh) else { return nil }
                    return (sh, parsed)
                }).first
                guard let match = firstMatch else {
                    fail("No price table was recognised. The file needs a row of column titles such as “Item” or “Description”, plus “Sale Price”, “Rental Price” or “Weight”.")
                    return
                }
                let sheet = match.0
                let parsed = match.1
                guard !parsed.rows.isEmpty else { fail("The column titles were found, but there were no item rows beneath them."); return }
                let counts = self.db.applyPriceImport(sourceKey: sourceKey, rows: parsed.rows, apply: false)
                let token = UUID().uuidString
                self.pendingPriceImport = (token, sourceKey, parsed.rows)
                let samples = parsed.rows.prefix(5).map { r -> String in
                    var parts = [r.name]
                    if let v = r.salePrice { parts.append("sale \(formatMoney(v))") }
                    if let v = r.rentalPrice { parts.append("rental \(formatMoney(v))") }
                    if let v = r.weightKg { parts.append("\(formatMoney(v)) kg") }
                    return parts.joined(separator: " · ")
                }
                self.respond(id: id, encodable: PriceImportPreview(
                    ok: true, error: nil, token: token, fileName: url.lastPathComponent, sheetName: sheet.name,
                    mapping: parsed.mapping, rowsFound: parsed.rows.count, toAdd: counts.added, toUpdate: counts.updated, samples: samples))
            } catch let e as BackupError {
                fail(e.message)
            } catch {
                fail("This file couldn't be read.")
            }
        }
    }

    func handlePriceImportApply(id: String, token: String) {
        guard let pending = pendingPriceImport, pending.token == token else {
            respond(id: id, encodable: PriceImportResult(ok: false, error: "This import has expired — please choose the file again.", added: 0, updated: 0))
            return
        }
        pendingPriceImport = nil
        let counts = db.applyPriceImport(sourceKey: pending.sourceKey, rows: pending.rows, apply: true)
        respond(id: id, encodable: PriceImportResult(ok: true, error: nil, added: counts.added, updated: counts.updated))
    }

    // MARK: Chat pictures

    /// A picture or GIF from this Mac, sent in a chat message.
    func handleChatAttach(id: String, conversation: String) {
        guard let window = window else { respondNull(id: id); return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.gif, .png, .jpeg, .heic]
        panel.message = "Choose a picture or GIF to send."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let url = panel.url else { self.respondNull(id: id); return }
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            guard size <= 12_000_000 else {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "That picture is too big to send (12 MB at most)."))
                return
            }
            var ext = url.pathExtension.lowercased()
            var data = try? Data(contentsOf: url)
            // HEIC photos are sent as JPEG, so every Mac can show them.
            if ext == "heic", let d = data, let rep = NSBitmapImageRep(data: d), let jpg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.82]) {
                data = jpg
                ext = "jpg"
            }
            guard let body = data else {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "That picture couldn’t be read."))
                return
            }
            let name = "\(makeId("chatfile")).\(ext == "jpeg" ? "jpg" : ext)"
            do {
                try FileManager.default.createDirectory(at: self.db.chatFilesFolder, withIntermediateDirectories: true)
                try body.write(to: self.db.chatFilesFolder.appendingPathComponent(name), options: .atomic)
            } catch {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "The picture couldn’t be saved."))
                return
            }
            switch self.db.sendChat(conversation: conversation, text: nil, gifURL: nil, file: name, fileName: url.lastPathComponent, replyTo: nil) {
            case .success(let m): self.respond(id: id, encodable: m)
            case .failure(let e): self.respond(id: id, encodable: SimpleResult(ok: false, error: e.message))
            }
        }
    }

    // MARK: Signing and chopping quotations (Team › Signatures)

    /// The director signs: the quotation's PDF is made with their signature
    /// over the company's signing line and the chop beside it, saved in the
    /// project's Quotations folder, and whoever asked is told.
    func handleSignQuotation(id: String, requestId: String) {
        func fail(_ message: String) { respond(id: id, encodable: PDFExportResult(ok: false, error: message, path: nil)) }
        guard let request = db.getSignRequest(id: requestId), request.status == "Pending" else { fail("That request isn’t waiting any more."); return }
        let me = TeamSync.memberName
        guard request.signer.lowercased() == me.lowercased() else { fail("Only \(request.signer) can sign this."); return }
        guard let detail = db.getQuotationDetail(id: request.documentId) else { fail("Quotation not found."); return }
        func picture(_ which: String) -> CGImage? {
            guard let image = NSImage(contentsOf: db.signatureImageURL(me, which)) else { return nil }
            return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
        }
        guard let signature = picture("signature") else {
            fail("Add your signature first: Team › People › your name › Signature.")
            return
        }
        let company = db.getCompanySettings()
        let paper = company.paperSize ?? "A4"
        guard let pages = quotationPDFData(detail, signature: signature, chop: picture("chop")) else { fail("Could not prepare the document."); return }
        let size = paper == "Letter" ? NSSize(width: 612, height: 792) : NSSize(width: 595.28, height: 841.89)
        let data = PDFAttachments.append(quotationAttachments(detail), to: pages, paperSize: size)
        let safe = detail.quotationNumber.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        do {
            let destination = try storage.writeGeneratedFile(data: data, projectNumber: detail.projectNumber, subfolder: "Quotations",
                                                             meaningfulFilename: "\(db.documentFileBase(docTypeTag: "Quotation", number: detail.quotationNumber) ?? "\(detail.projectNumber)_Quotation_\(safe)") - Signed & Chopped.pdf",
                                                             folder: fileFolder(projectNumber: detail.projectNumber, subfolder: "Quotations", name: safe,
                                                                                docTypeTag: "Quotation", documentNumber: detail.quotationNumber))
            if let error = db.finishSignRequest(id: requestId, signed: true, filePath: destination.path, reply: nil) { fail(error); return }
            respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: destination.path))
        } catch {
            fail("The signed PDF couldn’t be saved in the project folder. Check there’s free disk space and try again.")
        }
    }

    /// This Mac's user's signature or chop: a picture (PNG with a clear
    /// background is best), kept in the shared folder's signatures folder.
    func handleChooseSignatureImage(id: String, which: String) {
        guard let window = window else { respondNull(id: id); return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff]
        panel.message = which == "chop" ? "Choose a picture of the company chop (a PNG with a clear background looks best)."
            : "Choose a picture of your signature (a PNG with a clear background looks best)."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let url = panel.url else { self.respondNull(id: id); return }
            guard let image = NSImage(contentsOf: url), let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff), let png = rep.representation(using: .png, properties: [:]) else {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "That picture couldn’t be read."))
                return
            }
            do {
                try FileManager.default.createDirectory(at: self.db.signaturesFolder, withIntermediateDirectories: true)
                try png.write(to: self.db.signatureImageURL(TeamSync.memberName, which), options: .atomic)
                self.respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            } catch {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "The picture couldn’t be saved."))
            }
        }
    }

    // MARK: Clients & sites to and from Excel

    func handlePartyExport(id: String, kind: String, includeArchived: Bool) {
        guard let window = window else { respondNull(id: id); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")].compactMap { $0 }
        let listName = kind == "sites" ? "Sites" : "Clients"
        panel.nameFieldStringValue = "ScaffoldPro " + listName + ".xlsx"
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let url = panel.url else { self.respondNull(id: id); return }
            do {
                try SpreadsheetWriter.writeXLSX(sheetName: kind == "sites" ? "Sites" : "Clients",
                                                rows: self.db.partySheetRows(kind: kind, includeArchived: includeArchived), to: url)
                self.revealOne(url)
                self.respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            } catch let e as BackupError {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: e.message))
            } catch {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "The Excel file couldn't be saved there."))
            }
        }
    }

    func handlePartyImportPreview(id: String, kind: String) {
        guard let window = window else { respondNull(id: id); return }
        let what = kind == "sites" ? "sites" : "clients"
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")].compactMap { $0 }
        panel.message = "Choose an Excel workbook (.xlsx) of \(what) to add or update."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let url = panel.url else { self.respondNull(id: id); return }
            func fail(_ message: String) {
                self.respond(id: id, encodable: PartyImportPreview(ok: false, error: message, token: nil, fileName: url.lastPathComponent, sheetName: nil, columns: [], rowsFound: 0, toAdd: 0, toUpdate: 0, samples: []))
            }
            do {
                let sheets = url.pathExtension.lowercased() == "csv" ? try SpreadsheetReader.readCSV(url) : try SpreadsheetReader.readXLSX(url)
                // A sheet named after the list first (e.g. "Clients"), else the first one that makes sense.
                let singular = String(what.dropLast())
                let ordered = sheets.filter { $0.name.lowercased().contains(singular) } + sheets
                var picked: (sheet: SpreadsheetSheet, header: Int, map: [Int: PartyColumn])? = nil
                for sh in ordered {
                    if let f = PartySheet.interpret(sh, kind: kind) { picked = (sheet: sh, header: f.header, map: f.map); break }
                }
                guard let match = picked else {
                    fail("No list of \(what) was recognised. The file needs a row of column titles with “\(PartySheet.columns(kind)[0].title)” — the easiest start is Export to Excel, then edit that file.")
                    return
                }
                let sheet = match.sheet
                let columnMap = match.map
                let nameKey = PartySheet.columns(kind)[0].key
                var rows: [[String: String]] = []
                for row in sheet.rows.dropFirst(match.header + 1) {
                    var values: [String: String] = [:]
                    for (c, col) in columnMap where c < row.count { values[col.key] = row[c].trimmingCharacters(in: .whitespacesAndNewlines) }
                    guard !(values[nameKey] ?? "").isEmpty else { continue }
                    rows.append(values)
                }
                guard !rows.isEmpty else { fail("The column titles were found, but there were no \(what) beneath them."); return }
                let matched = self.db.matchPartyRows(kind: kind, rows: rows)
                let token = UUID().uuidString
                self.pendingPartyImport = (token, kind, matched)
                let titles: [String] = columnMap.keys.sorted().compactMap { columnMap[$0]?.title }
                var samples: [String] = []
                for m in matched.prefix(5) {
                    var parts: [String] = [m.row[nameKey] ?? ""]
                    for k in ["contactPerson", "phone"] { if let v = m.row[k], !v.isEmpty { parts.append(v) } }
                    samples.append(parts.joined(separator: " · ") + (m.matchId == nil ? "  (new)" : "  (update)"))
                }
                self.respond(id: id, encodable: PartyImportPreview(ok: true, error: nil, token: token, fileName: url.lastPathComponent, sheetName: sheet.name,
                    columns: titles, rowsFound: rows.count, toAdd: matched.filter { $0.matchId == nil }.count,
                    toUpdate: matched.filter { $0.matchId != nil }.count, samples: samples))
            } catch let e as BackupError {
                fail(e.message)
            } catch {
                fail("This file couldn't be read.")
            }
        }
    }

    func handlePartyImportApply(id: String, token: String) {
        guard let pending = pendingPartyImport, pending.token == token else {
            respond(id: id, encodable: PartyImportResult(ok: false, error: "This import has expired — please choose the file again.", added: 0, updated: 0, skipped: []))
            return
        }
        pendingPartyImport = nil
        respond(id: id, encodable: db.applyPartyImport(kind: pending.kind, rows: pending.rows))
    }

    /// Section 49: export a price list to Excel (.xlsx). Unlike documents,
    /// the export keeps the item code — it's what lets an edited copy be
    /// imported back and matched to the right items.
    func handlePriceExportCSV(id: String, sourceKey: String) {
        guard let window = window, let list = db.listPriceLists().first(where: { $0.sourceKey == sourceKey }) else { respondNull(id: id); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx")].compactMap { $0 }
        panel.nameFieldStringValue = "\(list.displayName.replacingOccurrences(of: "/", with: "-")).xlsx"
        panel.directoryURL = storage.appRoot
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let url = panel.url else { self.respondNull(id: id); return }
            func num(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "" }
            var rows = [["Item Code", "Category", "Item", "Unit", "Weight (kg)", "Sale Price (\(list.currency))", "Rental Price (\(list.currency))"]]
            for item in self.db.allPriceListItems(sourceKey: sourceKey) {
                rows.append([item.itemCode, item.category ?? "", item.itemName, item.unit,
                             num(item.weightKg), num(item.unitSalePrice), num(item.unitRentalPrice)])
            }
            do {
                try SpreadsheetWriter.writeXLSX(sheetName: list.displayName, rows: rows, to: url, numbers: true)
                self.revealOne(url)
                self.respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            } catch {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "The Excel file couldn't be saved there."))
            }
        }
    }

    // MARK: Backup & Restore (Phase 14)

    /// Copying a few gigabytes of drawings must not freeze the window
    /// (section 55), so the work runs on a background queue and only the
    /// reply to the page hops back to the main thread.
    /// Picks the folder for the automatic iCloud backup (starting in
    /// iCloud Drive), then backs up into it straight away.
    func handleChooseCloudFolder(id: String) {
        guard let window = window else { respondNull(id: id); return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = FileManager.default.fileExists(atPath: CloudBackupManager.defaultFolder.path)
            ? CloudBackupManager.defaultFolder : CloudBackupManager.iCloudDrive
        panel.prompt = "Use This Folder"
        panel.message = "Choose the folder to keep the automatic backup in, e.g. iCloud Drive › Proficiency › William's Work."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let url = panel.url else {
                self.respond(id: id, encodable: self.cloudBackup.status())
                return
            }
            self.cloudBackup.setFolder(url)
            self.cloudBackup.backUpNow { status in self.respond(id: id, encodable: status) }
        }
    }

    // MARK: Scheduled backups — every day at 12:00 a.m. and 12:00 p.m.
    //
    // Checked every minute (and soon after opening): if the latest 12:00
    // that has passed has no scheduled backup yet — e.g. the Mac was asleep
    // or ScaffoldPro was closed then — one is made now. Afterwards the
    // scheduled backups older than 3 days are deleted. On APFS the copies
    // are clones, so unchanged files take no extra disk space.

    static let lastScheduledKey = "backup.scheduled.lastSlot"
    static let lastScheduledAtKey = "backup.scheduled.lastAt"
    static let lastScheduledErrorKey = "backup.scheduled.lastError"

    func startScheduledBackups() {
        scheduleTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.runScheduledBackupIfDue() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.runScheduledBackupIfDue() }
    }

    /// The latest 12:00 a.m. or 12:00 p.m. that has passed.
    static func latestBackupSlot(_ now: Date = Date()) -> Date {
        let cal = Calendar.current
        let midnight = cal.startOfDay(for: now)
        let noon = cal.date(bySettingHour: 12, minute: 0, second: 0, of: now) ?? midnight.addingTimeInterval(12 * 3600)
        return now >= noon ? noon : midnight
    }

    func runScheduledBackupIfDue() {
        let slot = NativeBridge.latestBackupSlot()
        let done = UserDefaults.standard.double(forKey: NativeBridge.lastScheduledKey)
        guard done < slot.timeIntervalSince1970, !backupInProgress else { return }
        if let last = lastAttempt, Date().timeIntervalSince(last) < 15 * 60 { return }
        lastAttempt = Date()
        backupInProgress = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            var failure: String? = nil
            do { _ = try self.backups.createBackup(kind: "Scheduled") } catch {
                failure = (error as? BackupError)?.message ?? error.localizedDescription
            }
            if failure == nil { self.backups.deleteOldScheduledBackups(olderThanDays: 3) }
            DispatchQueue.main.async {
                self.backupInProgress = false
                let defaults = UserDefaults.standard
                if let failure = failure {
                    defaults.set(failure, forKey: NativeBridge.lastScheduledErrorKey)
                    NSLog("ScaffoldPro: automatic backup failed: %@", failure)
                } else {
                    defaults.set(slot.timeIntervalSince1970, forKey: NativeBridge.lastScheduledKey)
                    defaults.set(Date().timeIntervalSince1970, forKey: NativeBridge.lastScheduledAtKey)
                    let skipped = self.backups.lastSkipped
                    if skipped.isEmpty { defaults.removeObject(forKey: NativeBridge.lastScheduledErrorKey) }
                    else { defaults.set("\(skipped.count) item\(skipped.count == 1 ? "" : "s") weren't copied, e.g. \(skipped[0]).", forKey: NativeBridge.lastScheduledErrorKey) }
                    self.db.logActivity(projectId: nil, "Automatic backup made")
                }
            }
        }
    }

    /// Settings › Backup & Restore: the automatic backups and the local copy.
    func autoBackupStatus() -> AutoBackupStatus {
        let defaults = UserDefaults.standard
        let at = defaults.object(forKey: NativeBridge.lastScheduledAtKey) as? Double
        let iso = ISO8601DateFormatter()
        var status = AutoBackupStatus(lastAt: at.map { iso.string(from: Date(timeIntervalSince1970: $0)) },
                                      lastError: defaults.string(forKey: NativeBridge.lastScheduledErrorKey),
                                      running: backupInProgress)
        status.local = localCopy.status()
        return status
    }

    func handleCreateBackup(id: String) {
        guard !backupInProgress else {
            respond(id: id, encodable: BackupResult(ok: false, error: "A backup or restore is already running.", backup: nil, safetyBackup: nil))
            return
        }
        backupInProgress = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result: BackupResult
            do {
                let summary = try self.backups.createBackup(kind: "Manual")
                result = BackupResult(ok: true, error: nil, backup: summary, safetyBackup: nil)
            } catch let e as BackupError {
                result = BackupResult(ok: false, error: e.message, backup: nil, safetyBackup: nil)
            } catch {
                result = BackupResult(ok: false, error: "The backup could not be completed.", backup: nil, safetyBackup: nil)
            }
            DispatchQueue.main.async {
                self.backupInProgress = false
                self.respond(id: id, encodable: result)
            }
        }
    }

    func handleRestore(id: String, from folder: URL) {
        guard TeamSync.current == nil else {
            respond(id: id, encodable: BackupResult(ok: false, error: "This Mac is using a shared folder, so restoring would replace everyone's data. Turn off sharing on this Mac first (Settings › Share with Other Macs), restore, then set up sharing again.", backup: nil, safetyBackup: nil))
            return
        }
        guard !backupInProgress else {
            respond(id: id, encodable: BackupResult(ok: false, error: "A backup or restore is already running.", backup: nil, safetyBackup: nil))
            return
        }
        backupInProgress = true
        cloudBackup.paused = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let result: BackupResult
            do {
                let safety = try self.backups.restore(from: folder)
                let restored = self.backups.readManifest(folder).map {
                    BackupSummary(name: folder.lastPathComponent, path: folder.path, createdAt: $0.createdAt, kind: $0.kind,
                                  projectCount: $0.projectCount, fileCount: $0.fileCount, totalBytes: $0.totalBytes)
                }
                result = BackupResult(ok: true, error: nil, backup: restored, safetyBackup: safety)
            } catch let e as BackupError {
                result = BackupResult(ok: false, error: e.message, backup: nil, safetyBackup: nil)
            } catch {
                result = BackupResult(ok: false, error: "The restore could not be completed.", backup: nil, safetyBackup: nil)
            }
            DispatchQueue.main.async {
                self.backupInProgress = false
                self.cloudBackup.paused = false
                self.cloudBackup.schedule(after: 5)
                self.respond(id: id, encodable: result)
            }
        }
    }

    /// "Restore from Folder…" — for a backup kept elsewhere (USB drive,
    /// another Mac). The page asks for confirmation before calling this.
    func handleChooseAndRestore(id: String) {
        guard let window = window else {
            respondNull(id: id)
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Restore"
        panel.message = "Choose a ScaffoldPro backup folder (named like \"ScaffoldPro-Backup_…\")."
        panel.directoryURL = storage.backupsRoot

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let folder = panel.url else {
                self.respondNull(id: id)
                return
            }
            self.handleRestore(id: id, from: folder)
        }
    }

    /// Section 14 "Replace": copy in the new version (original source
    /// untouched), move the previous copy to Other/Superseded/ so nothing
    /// is lost, then update the record.
    func handleReplaceFile(id: String, recordId: String, isDrawing: Bool) {
        guard let window = window else { respondNull(id: id); return }
        let oldPath: String
        let projectId: String
        if isDrawing, let d = db.getDrawing(id: recordId) { oldPath = d.filePath; projectId = d.projectId }
        else if !isDrawing, let d = db.getDocument(id: recordId) { oldPath = d.filePath; projectId = d.projectId }
        else { respond(id: id, encodable: FileActionResult(ok: false, error: "File record not found.")); return }
        guard let project = db.listProjectsRaw().first(where: { $0.id == projectId }) else {
            respond(id: id, encodable: FileActionResult(ok: false, error: "Project not found.")); return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if isDrawing { panel.allowedContentTypes = drawingContentTypes }
        panel.message = "Choose the new version. The previous copy will be kept in the project's Other/Superseded folder."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let source = panel.url else { self.respondNull(id: id); return }
            let fm = FileManager.default
            do {
                if fm.fileExists(atPath: oldPath) {
                    let superseded = self.storage.projectSubfolder(project.projectNumber, "Other")
                        .appendingPathComponent("Superseded", isDirectory: true)
                    _ = try self.storage.copyFile(source: URL(fileURLWithPath: oldPath), into: superseded,
                                                  meaningfulFilename: URL(fileURLWithPath: oldPath).lastPathComponent)
                    try fm.removeItem(atPath: oldPath)
                }
                let subfolder = isDrawing ? "Drawings" : "Documents"
                let name = "\(project.projectNumber)_\(isDrawing ? "Drawing" : "Document")_\(source.lastPathComponent)"
                let link = isDrawing ? self.db.getDrawing(id: recordId).map { ($0.linkedKind, $0.linkedId) } : self.db.getDocument(id: recordId).map { ($0.linkedKind, $0.linkedId) }
                let dest = try self.storage.copyFileIntoProject(source: source, projectNumber: project.projectNumber, subfolder: subfolder, meaningfulFilename: name,
                                                               folder: self.linkedFileFolder(projectNumber: project.projectNumber, kind: link?.0 ?? nil, linkedId: link?.1 ?? nil, sub: subfolder))
                let error = isDrawing
                    ? self.db.replaceDrawingFile(id: recordId, originalName: source.lastPathComponent, storedURL: dest)
                    : self.db.replaceDocumentFile(id: recordId, originalName: source.lastPathComponent, storedURL: dest)
                self.respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
            } catch {
                self.respond(id: id, encodable: FileActionResult(ok: false, error: "The new version couldn't be copied into the project folder."))
            }
        }
    }

    /// Opens a file — downloading it first if iCloud Drive moved it off
    /// this Mac (a shared folder keeps files in iCloud).
    func handleOpenFile(id: String, path: String) {
        whenDownloaded(path) { [weak self] here in
            guard let self = self else { return }
            guard here else {
                self.respond(id: id, encodable: FileActionResult(ok: false, error: fileIsPresent(path)
                    ? "This file is still downloading from iCloud. Try again in a moment."
                    : "This file could not be found. It may have been moved or deleted."))
                return
            }
            self.openForUser(URL(fileURLWithPath: path))
            self.respond(id: id, encodable: FileActionResult(ok: true, error: nil))
        }
    }

    func handleRevealFile(id: String, path: String) {
        guard fileIsPresent(path) else {
            respond(id: id, encodable: FileActionResult(ok: false, error: "This file could not be found. It may have been moved or deleted."))
            return
        }
        self.revealOne(URL(fileURLWithPath: path))
        respond(id: id, encodable: FileActionResult(ok: true, error: nil))
    }

    // MARK: Team sharing


    func teamStatus() -> TeamStatus {
        if let sync = TeamSync.current { return sync.status() }
        let folder = TeamSync.configuredFolder
        return TeamStatus(enabled: false, folder: folder?.path, folderDisplay: folder.map { TeamSync.display($0) },
                          folderMissing: folder != nil && teamFolderMissing, memberName: TeamSync.memberName, members: [],
                          lastChangeAt: nil, lastChangeBy: nil, iCloudDrive: CloudBackupManager.iCloudDrive.path)
    }

    /// Tells the page that other Macs changed something (it refreshes).
    func sharedDataChanged(stores: [String], names: [String]) {
        struct Change: Encodable { var stores: [String]; var names: [String] }
        guard let data = try? JSONEncoder().encode(Change(stores: stores, names: names)),
              let json = String(data: data, encoding: .utf8) else { return }
        webView?.evaluateJavaScript("window.__sharedDataChanged && window.__sharedDataChanged(\(json))", completionHandler: nil)
    }

    /// Makes a shared folder from this Mac's data. The chosen folder is
    /// used as it is if it's empty; otherwise a "ScaffoldPro Team" folder
    /// is made inside it (e.g. inside a Proficiency folder already shared).
    func handleStartTeam(id: String) {
        guard let window = window else { respondNull(id: id); return }
        guard TeamSync.current == nil else {
            respond(id: id, encodable: SimpleResult(ok: false, error: "This Mac is already using a shared folder."))
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Share Here"
        panel.message = "Choose a folder in iCloud Drive that you share (or will share) with the others — for example your shared Proficiency folder. A “ScaffoldPro Team” folder is made inside it."
        panel.directoryURL = CloudBackupManager.iCloudDrive
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let chosen = panel.url else { self.respondNull(id: id); return }
            let fm = FileManager.default
            if TeamSync.isWorkspace(chosen) || TeamSync.isWorkspace(chosen.appendingPathComponent("ScaffoldPro Team")) {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "That folder already has ScaffoldPro's shared data in it. Use “Join a Shared Folder…” instead — setting it up again would mix two sets of data."))
                return
            }
            let contents = ((try? fm.contentsOfDirectory(atPath: chosen.path)) ?? []).filter { !$0.hasPrefix(".") }
            let folder = contents.isEmpty ? chosen : chosen.appendingPathComponent("ScaffoldPro Team", isDirectory: true)
            let mine = self.storage.appRoot.standardizedFileURL.path
            if (folder.standardizedFileURL.path + "/").hasPrefix(mine + "/") || (mine + "/").hasPrefix(folder.standardizedFileURL.path + "/") {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "Choose a folder outside Documents › ScaffoldPro — ideally one in iCloud Drive that you share with the others."))
                return
            }
            do { try fm.createDirectory(at: folder, withIntermediateDirectories: true) } catch {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "The folder couldn't be made: \(error.localizedDescription)"))
                return
            }
            TeamSync.createWorkspace(in: folder, dataDir: self.db.dataDir, storage: self.storage) { error in
                if error == nil { TeamSync.setConfiguredFolder(folder) }
                self.respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
            }
        }
    }

    /// Uses a shared folder someone else set up. This Mac's own data is
    /// left as it is (and comes back if sharing is turned off).
    func handleJoinTeam(id: String) {
        guard let window = window else { respondNull(id: id); return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Join"
        panel.message = "Choose the shared “ScaffoldPro Team” folder (in iCloud Drive, once you've accepted the invitation to the shared folder)."
        panel.directoryURL = CloudBackupManager.iCloudDrive
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let chosen = panel.url else { self.respondNull(id: id); return }
            let inside = chosen.appendingPathComponent("ScaffoldPro Team", isDirectory: true)
            guard let folder = TeamSync.isWorkspace(chosen) ? chosen : TeamSync.isWorkspace(inside) ? inside : nil else {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "That isn't a ScaffoldPro shared folder. Choose the “ScaffoldPro Team” folder that was set up with “Share My Data…” on the other Mac. If it was only just shared, wait for iCloud to finish downloading it."))
                return
            }
            TeamSync.setConfiguredFolder(folder)
            self.respond(id: id, encodable: SimpleResult(ok: true, error: nil))
        }
    }

    // MARK: Signed copies of quotations

    /// PDF, or a photo / scan of the signed page.
    static let signedCopyTypes: [UTType] = [.pdf, .jpeg, .png, .heic, .tiff]

    /// Saves the client's signed copy as "<Qt number> - Signed.<ext>" in
    /// the project's Quotations folder and records it on the quotation.
    /// `write` puts the file at the URL it's given.
    func storeSignedQuotation(quotationId: String, fileName: String, write: (URL) throws -> Void) -> SimpleResult {
        storeSignedCopy(kind: "quotation", documentId: quotationId, fileName: fileName, write: write)
    }

    /// The signed copy of a quotation (from the client) or a delivery note
    /// (signed on site): "<number> - Signed.<ext>" in its quotation series'
    /// Quotations or Delivery Notes folder, recorded on the document.
    func storeSignedCopy(kind: String, documentId: String, fileName: String, write: (URL) throws -> Void) -> SimpleResult {
        let found: (number: String, projectId: String, folder: String, noun: String)?
        if kind == "deliveryNote" {
            found = db.getDeliveryNote(id: documentId).map { (number: $0.deliveryNoteNumber, projectId: $0.projectId, folder: "Delivery Notes", noun: "delivery note") }
        } else {
            found = db.getQuotation(id: documentId).map { (number: $0.quotationNumber, projectId: $0.projectId, folder: "Quotations", noun: "quotation") }
        }
        guard let doc = found, let project = db.getProject(id: doc.projectId) else {
            return SimpleResult(ok: false, error: kind == "deliveryNote" ? "Delivery note not found." : "Quotation not found.")
        }
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        guard let type = UTType(filenameExtension: ext), NativeBridge.signedCopyTypes.contains(where: { type.conforms(to: $0) }) else {
            return SimpleResult(ok: false, error: "Use a PDF, or a photo or scan (JPEG, PNG, HEIC or TIFF), of the signed \(doc.noun).")
        }
        let folder = fileFolder(projectNumber: project.projectNumber, subfolder: doc.folder, name: doc.number,
                                docTypeTag: kind == "deliveryNote" ? "DeliveryNote" : "Quotation", documentNumber: doc.number)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safe = doc.number.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let base = db.documentFileBase(docTypeTag: kind == "deliveryNote" ? "DeliveryNote" : "Quotation", number: doc.number) ?? safe
            let destination = storage.uniqueDestination(folder.appendingPathComponent("\(base) - Signed.\(ext)"))
            try write(destination)
            let error = kind == "deliveryNote" ? db.setDeliveryNoteSignedCopy(id: documentId, path: destination.path)
                                               : db.setQuotationSignedCopy(id: documentId, path: destination.path)
            if let error = error { return SimpleResult(ok: false, error: error) }
            return SimpleResult(ok: true, error: nil)
        } catch {
            return SimpleResult(ok: false, error: "The signed copy couldn't be saved in the project folder: \(error.localizedDescription)")
        }
    }

    func handleUploadSignedDeliveryNote(id: String, noteId: String) {
        guard let window = window else { respondNull(id: id); return }
        guard let n = db.getDeliveryNote(id: noteId) else { respondError(id: id, message: "Delivery note not found."); return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = NativeBridge.signedCopyTypes
        panel.message = "Choose the signed copy of \(n.deliveryNoteNumber) (a PDF, or a photo or scan). A copy is kept in the project's Delivery Notes folder and added after the invoice that bills it."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let source = panel.url else { self.respondNull(id: id); return }
            self.respond(id: id, encodable: self.storeSignedCopy(kind: "deliveryNote", documentId: noteId, fileName: source.lastPathComponent) {
                try FileManager.default.copyItem(at: source, to: $0)
            })
        }
    }

    /// "open" | "reveal" | "remove" for a delivery note's signed copy.
    func handleDeliveryNoteSignedAction(id: String, noteId: String, action: String) {
        guard let n = db.getDeliveryNote(id: noteId) else { respondError(id: id, message: "Delivery note not found."); return }
        switch action {
        case "remove":
            let error = db.setDeliveryNoteSignedCopy(id: noteId, path: nil)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "open", "reveal":
            guard let path = n.signedCopyPath else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "No signed copy has been added to \(n.deliveryNoteNumber) yet."))
                return
            }
            if action == "open" { handleOpenFile(id: id, path: path) } else { handleRevealFile(id: id, path: path) }
        default:
            respondError(id: id, message: "Unknown action.")
        }
    }

    func handleUploadSignedQuotation(id: String, quotationId: String) {
        guard let window = window else { respondNull(id: id); return }
        guard let q = db.getQuotation(id: quotationId) else { respondError(id: id, message: "Quotation not found."); return }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = NativeBridge.signedCopyTypes
        panel.message = "Choose the signed copy of \(q.quotationNumber) (a PDF, or a photo or scan). A copy is kept in the project's Quotations folder."
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let source = panel.url else { self.respondNull(id: id); return }
            self.respond(id: id, encodable: self.storeSignedQuotation(quotationId: quotationId, fileName: source.lastPathComponent) {
                try FileManager.default.copyItem(at: source, to: $0)
            })
        }
    }

    /// A file dropped onto the page (sent as base64).
    func handleSaveSignedQuotationData(id: String, payload: [String: Any]) {
        let quotationId = (payload["id"] as? String) ?? ""
        let fileName = (payload["fileName"] as? String) ?? ""
        guard let base64 = payload["base64"] as? String, let data = Data(base64Encoded: base64), !data.isEmpty else {
            respond(id: id, encodable: SimpleResult(ok: false, error: "That file couldn't be read."))
            return
        }
        respond(id: id, encodable: storeSignedQuotation(quotationId: quotationId, fileName: fileName) {
            try data.write(to: $0, options: .atomic)
        })
    }

    /// "open" | "reveal" | "remove" (forgets it; the file stays in the folder).
    func handleSignedCopyAction(id: String, quotationId: String, action: String) {
        guard let q = db.getQuotation(id: quotationId) else { respondError(id: id, message: "Quotation not found."); return }
        switch action {
        case "remove":
            let error = db.setQuotationSignedCopy(id: quotationId, path: nil)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "open", "reveal":
            guard let path = q.signedCopyPath else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "No signed copy has been added to \(q.quotationNumber) yet."))
                return
            }
            if action == "open" { handleOpenFile(id: id, path: path) } else { handleRevealFile(id: id, path: path) }
        default:
            respondError(id: id, message: "Unknown action.")
        }
    }

    // MARK: response helpers

    func respond<T: Encodable>(id: String, encodable: T) {
        guard let data = try? JSONEncoder().encode(encodable), let json = String(data: data, encoding: .utf8) else {
            respondError(id: id, message: "Failed to encode response")
            return
        }
        callback(id: id, ok: true, resultJson: json, error: nil)
    }

    func respondNull(id: String) {
        callback(id: id, ok: true, resultJson: "null", error: nil)
    }

    func respondError(id: String, message: String) {
        callback(id: id, ok: false, resultJson: nil, error: message)
    }

    func callback(id: String, ok: Bool, resultJson: String?, error: String?) {
        if id.hasPrefix("web-") {
            DispatchQueue.main.async { [weak self] in
                self?.webReplies.removeValue(forKey: id)?(ok, resultJson, error)
            }
            return
        }
        guard let webView = webView else { return }
        let idJS = jsStringLiteral(id)
        let okJS = ok ? "true" : "false"
        let resultJS = resultJson == nil ? "null" : jsStringLiteral(resultJson!)
        let errorJS = error == nil ? "null" : jsStringLiteral(error!)
        let script = "window.__nativeCallback(\(idJS), \(okJS), \(resultJS), \(errorJS));"
        DispatchQueue.main.async {
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }

    func jsStringLiteral(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s), let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json
    }
}

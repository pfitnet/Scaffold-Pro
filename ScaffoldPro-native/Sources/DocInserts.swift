import Cocoa

// =====================================================================
// MARK: - Paragraphs added in a document's preview
//
// In the preview of a quotation, invoice or delivery note (js/doc-preview.js
// › Edit) a paragraph can be added above or below any of its lines: the
// opening, an item row, a terms paragraph, after the table, or at the end.
// They're kept with the document (doc_inserts.json, by its id) and drawn in
// every PDF and Word copy of it: `withInserts` puts them into the letter
// before it's laid out, so both get them.
//
// Where: each line's key is made from its own text ("row:2.0m standard with
// spigot"), so a paragraph stays with its line when lines are added, moved
// or removed around it. If its line has gone, it's printed at the end
// (before the signatures): never lost. The quotation's landscape BQ sheet
// is drawn by BQSheetRenderer and doesn't take them.
// =====================================================================

/// One added paragraph: above (`after` false) or below its line (`anchor`).
struct DocInsert: Codable {
    var id: String
    var anchor: String
    var after: Bool
    var text: String
}

/// A document's added paragraphs (`id`: the quotation's, invoice's or delivery note's id).
struct DocInserts: Codable {
    var id: String
    var inserts: [DocInsert]
}

/// A line of a document that a paragraph can go above or below.
struct DocAnchor: Encodable {
    var key: String
    var label: String
    var text: String
}

struct DocEditsPage: Encodable {
    var ok: Bool
    var error: String?
    var anchors: [DocAnchor]
    var inserts: [DocInsert]
}

extension AppDatabase {
    func docInserts(_ documentId: String) -> [DocInsert] {
        docInsertsStore.readAll().first { $0.id == documentId }?.inserts ?? []
    }

    func setDocInserts(_ documentId: String, _ inserts: [DocInsert]) {
        var all = docInsertsStore.readAll().filter { $0.id != documentId }
        if !inserts.isEmpty { all.append(DocInserts(id: documentId, inserts: inserts)) }
        docInsertsStore.writeAll(all)
    }
}

extension NativeBridge {
    /// A line's text as its key: lower case, single spaces, no style marks, the first 60 characters.
    func anchorFingerprint(_ text: String) -> String {
        let plain = String(String.UnicodeScalarView(text.unicodeScalars.filter { !(0xE000...0xF8FF).contains($0.value) }))
        return String(plain.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ").prefix(60))
    }

    /// A table row's name and text (nil: totals and repeated column titles).
    func anchorRowText(_ row: LetterTableRow) -> (label: String, text: String)? {
        switch row {
        case .item(let values): return ("Item \(values.first ?? "")", values.count > 1 ? values[1] : values.joined(separator: " "))
        case .section(let heading): return ("Heading", heading)
        case .partial(let values, _): return ("Item \(values.first ?? "")", values.count > 1 ? values[1] : values.joined(separator: " "))
        case .wide(let number, let text): return (number.isEmpty ? "Line" : "Item \(number)", text)
        case .lump(let number, let heading, _, _): return ("Item \(number)", heading)
        case .note(let text): return ("Note", text)
        case .summary, .columnTitles: return nil
        }
    }

    func anchorParagraphText(_ paragraph: LetterParagraph) -> String {
        switch paragraph {
        case .text(let text, _): return text
        case .term(let label, let lines): return ([label ?? ""] + lines).joined(separator: " ")
        case .hanging(let marker, let lines, _, _, _): return ([marker] + lines).joined(separator: " ")
        }
    }

    /// Keys made in reading order; the same text twice gets "#2", "#3"…
    final class AnchorKeys {
        var seen: [String: Int] = [:]
        func key(_ kind: String, _ fingerprint: String) -> String {
            let base = "\(kind):\(fingerprint)"
            let n = (seen[base] ?? 0) + 1
            seen[base] = n
            return n == 1 ? base : "\(base)#\(n)"
        }
    }

    /// The lines a paragraph can be added at, in reading order.
    func letterAnchors(_ doc: LetterDocument) -> [DocAnchor] {
        let keys = AnchorKeys()
        var out: [DocAnchor] = []
        if let intro = nonBlank(doc.intro) { out.append(DocAnchor(key: "intro", label: "Opening", text: intro)) }
        for row in doc.rows {
            guard let r = anchorRowText(row), let text = nonBlank(r.text) else { continue }
            out.append(DocAnchor(key: keys.key("row", anchorFingerprint(text)), label: r.label, text: text))
        }
        if !doc.rows.isEmpty { out.append(DocAnchor(key: "table-end", label: "After the table", text: "")) }
        for section in doc.sections {
            for paragraph in section.paragraphs {
                guard let text = nonBlank(anchorParagraphText(paragraph)) else { continue }
                out.append(DocAnchor(key: keys.key("para", anchorFingerprint(text)), label: nonBlank(section.heading) ?? "Paragraph", text: text))
            }
        }
        out.append(DocAnchor(key: "end", label: "End, before the signatures", text: ""))
        return out
    }

    /// The letter with the document's added paragraphs in place.
    func withInserts(_ base: LetterDocument, documentId: String) -> LetterDocument {
        let inserts = db.docInserts(documentId).filter { nonBlank($0.text) != nil }
        guard !inserts.isEmpty else { return base }
        var doc = base
        var placed = Set<String>()
        func texts(_ anchor: String, after: Bool) -> [String] {
            let found = inserts.filter { $0.anchor == anchor && $0.after == after }
            for f in found { placed.insert(f.id) }
            return found.map { $0.text }
        }
        if let intro = nonBlank(doc.intro) {
            doc.intro = (texts("intro", after: false) + [intro] + texts("intro", after: true)).joined(separator: "\n")
        }
        let keys = AnchorKeys()
        var rows: [LetterTableRow] = []
        for row in doc.rows {
            guard let r = anchorRowText(row), let text = nonBlank(r.text) else { rows.append(row); continue }
            let key = keys.key("row", anchorFingerprint(text))
            rows += texts(key, after: false).map { LetterTableRow.wide(number: "", text: $0) }
            rows.append(row)
            rows += texts(key, after: true).map { LetterTableRow.wide(number: "", text: $0) }
        }
        doc.rows = rows
        var sections: [LetterSection] = []
        for var section in doc.sections {
            var paragraphs: [LetterParagraph] = []
            for paragraph in section.paragraphs {
                guard let text = nonBlank(anchorParagraphText(paragraph)) else { paragraphs.append(paragraph); continue }
                let key = keys.key("para", anchorFingerprint(text))
                paragraphs += texts(key, after: false).map { LetterParagraph.text($0, link: nil) }
                paragraphs.append(paragraph)
                paragraphs += texts(key, after: true).map { LetterParagraph.text($0, link: nil) }
            }
            section.paragraphs = paragraphs
            sections.append(section)
        }
        let afterTable = texts("table-end", after: false) + texts("table-end", after: true)
        if !afterTable.isEmpty { sections.insert(LetterSection(heading: nil, paragraphs: afterTable.map { LetterParagraph.text($0, link: nil) }), at: 0) }
        // At the end — and any whose line has gone, so nothing is lost.
        var rest = texts("end", after: false) + texts("end", after: true)
        rest += inserts.filter { !placed.contains($0.id) }.map { $0.text }
        if !rest.isEmpty { sections.append(LetterSection(heading: nil, paragraphs: rest.map { LetterParagraph.text($0, link: nil) })) }
        doc.sections = sections
        return doc
    }

    /// The document's letter as drawn without its added paragraphs (nil: not one of these, or the landscape BQ sheet).
    func baseLetter(forDocument documentId: String) -> LetterDocument? {
        let company = db.getCompanySettings()
        if let q = db.getQuotationDetail(id: documentId) { return q.orientation == "Landscape" ? nil : quotationLetterBase(q, company: company) }
        if let invoice = db.getInvoiceDetail(id: documentId) { return invoiceLetterBase(invoice, company: company) }
        if let detail = db.getDeliveryNoteDetail(id: documentId), let note = db.getDeliveryNote(id: documentId) {
            return deliveryNoteLetterBase(detail, note: note, company: company)
        }
        return nil
    }

    func handleDocEditsGet(id: String, payload: [String: Any]) {
        let documentId = (payload["id"] as? String) ?? ""
        guard let letter = baseLetter(forDocument: documentId) else {
            respond(id: id, encodable: DocEditsPage(ok: false, error: "Paragraphs can be added in the preview of a quotation on the letterhead, an invoice or a delivery note.", anchors: [], inserts: []))
            return
        }
        respond(id: id, encodable: DocEditsPage(ok: true, error: nil, anchors: letterAnchors(letter), inserts: db.docInserts(documentId)))
    }

    func handleDocEditsSave(id: String, payload: [String: Any]) {
        let documentId = (payload["id"] as? String) ?? ""
        guard baseLetter(forDocument: documentId) != nil else {
            respond(id: id, encodable: SimpleResult(ok: false, error: "That document isn't there any more."))
            return
        }
        let inserts: [DocInsert] = ((payload["inserts"] as? [[String: Any]]) ?? []).prefix(200).compactMap { raw in
            guard let anchor = nonBlank(raw["anchor"] as? String) else { return nil }
            let text = String(((raw["text"] as? String) ?? "").prefix(4000))
            return DocInsert(id: nonBlank(raw["id"] as? String) ?? UUID().uuidString, anchor: anchor, after: (raw["after"] as? Bool) ?? true, text: text)
        }
        db.setDocInserts(documentId, inserts)
        respond(id: id, encodable: SimpleResult(ok: true, error: nil))
    }
}

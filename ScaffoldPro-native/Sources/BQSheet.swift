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

// =====================================================================
// MARK: - BQ sheet ("PROFICIENCY QUOTATION")
//
// The bill of quantities as the company's own Google Sheets BQ (e.g.
// "CRBC 1635 - 80m Concrete Wall"): an orange title banner, two light
// yellow rows for project code / client / job site / structure, a blue
// heading row, 18pt item rows and a "Total Amount :" row. Every position,
// size and colour is measured from that sheet (A4 landscape, 842.88 ×
// 595.92pt, table 85.875–754.875pt across, from 53.625pt down).
//
//   No. | Item Name | Weight | Quantity | Unit … Rate | Total … Rate | Total Weight
//
// This is the landscape BOQ. A portrait BOQ is printed on the letterhead
// instead (no prices). BQSheet.layout can also lay out a portrait sheet
// without prices, which isn't used at present.
//
// One layout (`SheetLayout`) is drawn by `BQSheetRenderer` for the PDF and
// by js/docx-export.js for the Word copy, so the two look the same.
// =====================================================================

struct SheetCell: Encodable {
    var x0: Double
    var x1: Double
    var text: String
    /// "title" (Arial Bold) or "body" (Calibri)
    var font: String
    var size: Double
    /// "left", "center", "right" or "money" ("$" at the left, the amount at the right)
    var align: String
    /// Baseline height above the row's bottom line.
    var baselineUp: Double
    /// Part of the text drawn as a link (blue, underlined), e.g. "pfitnet.com/TC".
    var link: String? = nil
    /// A rule along the cell's bottom (the line to sign on).
    var lineBelow = false
    /// A line of the terms set in from the box's edge: its text starts at
    /// `textX` (not just inside the rule), with `marker` ("Payment", "(i)",
    /// "•") at `markerX` on its first line, and `colon` a colon just before
    /// the text, as on the portrait quotation.
    var textX: Double? = nil
    var marker: String? = nil
    var markerX: Double? = nil
    var colon = false
}

struct SheetRow: Encodable {
    /// "banner", "info", "header", "item" or "total"
    var kind: String
    var height: Double
    /// Hex fill, e.g. "ED7D31"; nil = white.
    var fill: String?
    var cells: [SheetCell]
    /// Repeated at the top of every page (banner, info rows, heading row).
    var repeats: Bool
    /// No rule between this row and the next, which stay on the same page
    /// (the lines of the Notes box).
    var joinNext = false
    /// Below the table, with no rules (the signature block).
    var borderless = false
}

struct SheetLayout: Encodable {
    var ok = true
    var kind = "sheet"
    var landscape: Bool
    var pageWidth: Double
    var pageHeight: Double
    /// Outer rule positions (line centres).
    var left: Double
    var right: Double
    var top: Double
    /// Rows stop above this; the rest go on the next page.
    var bottomLimit: Double
    var rows: [SheetRow]
    /// Below 1 when the sheet is shrunk to fit one page (rules and
    /// padding shrink with it).
    var scale = 1.0
    // Filled in for a Word copy:
    var number = ""
    var title = "PROFICIENCY QUOTATION"
    var projectNumber = ""
    var subfolder = ""
    var fileName = ""
}

enum BQSheet {
    static let orange = "ED7D31"
    static let cream = "FDF9DF"
    static let blue = "B4C6E7"

    /// Builds the sheet. `info` is (project code, client, job site, structure).
    static func layout(landscape: Bool, pricingMode: String, currencyCode: String,
                       info: (projectCode: String, client: String, jobSite: String, structure: String),
                       lines: [BOQLineItem], grandTotal: Double, totalWeightKg: Double,
                       ratesSection: BOQRatesSection? = nil, charges: [BOQCharge] = [], notes: String? = nil,
                       terms: String? = nil, chinese: Bool = false,
                       signature: (company: String, name: String, title: String, client: String)? = nil,
                       extraInfo: [(String, String, String, String)] = [], onePage: Bool = false) -> SheetLayout {
        let pageWidth: Double = landscape ? 842.88 : 595.92
        let pageHeight: Double = landscape ? 595.92 : 842.88
        let left = 85.875
        let top = 53.625
        // Column widths as on the sheet; in portrait (no prices) Item Name
        // takes the room so the table keeps the same side margins.
        let widths: [Double] = landscape
            ? [68.25, 174.75, 43.5, 51.75, 130.5, 128.25, 72.0]
            : [68.25, 186.54, 43.5, 51.75, 72.0]
        var edges = [left]
        for w in widths { edges.append(edges.last! + w) }
        let right = edges.last!
        // Info rows: label | value | label | value.
        let infoEdges: [Double] = landscape
            ? [left, 154.125, 424.125, 492.375, right]
            : [left, 154.125, 263.625, 331.875, right]

        func cell(_ x0: Double, _ x1: Double, _ text: String, _ size: Double, _ align: String, _ up: Double, font: String = "body") -> SheetCell {
            SheetCell(x0: x0, x1: x1, text: text, font: font, size: size, align: align, baselineUp: up)
        }
        var rows: [SheetRow] = []
        rows.append(SheetRow(kind: "banner", height: 27.75, fill: orange,
                             cells: [cell(left, right, "PROFICIENCY QUOTATION", 19.99, "center", 6.375, font: "title")], repeats: true))
        let infoRows = extraInfo + [("Project Code  :", info.projectCode, "Job Site          :", info.jobSite),
                                    ("Client             :", info.client, "Structure        :", info.structure)]
        for r in infoRows {
            rows.append(SheetRow(kind: "info", height: 15.75, fill: cream, cells: [
                cell(infoEdges[0], infoEdges[1], r.0, 10, "left", 4.125), cell(infoEdges[1], infoEdges[2], r.1, 10, "left", 4.125),
                cell(infoEdges[2], infoEdges[3], r.2, 10, "left", 4.125), cell(infoEdges[3], infoEdges[4], r.3, 10, "left", 4.125),
            ], repeats: true))
        }
        let rateWord = pricingMode == "Sale" ? "Sale Price" : "Rental Rate"
        // The item table's headings in Chinese when the item names are.
        let zhRate = pricingMode == "Sale" ? "售價" : "租價"
        let titles = chinese
            ? (landscape
                ? ["編號", "物料名稱", "重量", "數量", "單位\(zhRate) (\(currencyCode))", "總\(zhRate) (\(currencyCode))", "總重量"]
                : ["編號", "物料名稱", "重量", "數量", "總重量"])
            : (landscape
                ? ["No.", "Item Name", "Weight", "Quantity", "Unit \(rateWord) (\(currencyCode))", "Total \(rateWord) (\(currencyCode))", "Total Weight"]
                : ["No.", "Item Name", "Weight", "Quantity", "Total Weight"])
        rows.append(SheetRow(kind: "header", height: 19.5, fill: blue,
                             cells: titles.enumerated().map { cell(edges[$0.offset], edges[$0.offset + 1], $0.element, 13, "center", 4.875) },
                             repeats: true))
        let kg: (Double) -> String = { String(format: "%.1f kg", $0) }
        for (i, line) in lines.enumerated() {
            let qty = line.quantity.rounded()
            let name = plainMarkup(line.itemDescription).replacingOccurrences(of: "\n", with: " ")
            let weight = line.weightKg.map(kg) ?? ""
            let totalWeight = line.weightKg.map { kg($0 * qty) } ?? ""
            var texts: [(String, String)] = [(String(i + 1), "center"), (name, "left"), (weight, "right"), (formatQuantity(qty), "center")]
            if landscape {
                texts.append((formatMoney(line.appliedUnitPrice), "money"))
                texts.append((formatMoney(doubleOf(lineAmount(quantity: line.quantity, unitPrice: line.appliedUnitPrice))), "money"))
            }
            texts.append((totalWeight, "right"))
            // A description over several lines (or with bullets, numbering,
            // hanging indents): its first line in the item's row, the rest
            // in rows joined under it, 14.25pt apart.
            let pad = 2.625
            let nameLines: [CellTextLine] = {
                let description = plainMarkup(line.itemDescription)
                guard description.contains("\n") || description.contains("\t") else { return [] }
                let font = bodyFont(12)
                let room = edges[2] - edges[1] - 2 * pad
                if isFormattedDescription(description) {
                    return formattedCellLines(description, width: room, measure: { Double(($0 as NSString).size(withAttributes: [.font: font]).width) },
                                              wrap: { wrap($0, width: $1, size: 12) })
                }
                return wrap(description, width: room, size: 12).map { CellTextLine(marker: nil, markerX: 0, text: $0, textX: 0, colon: false) }
            }()
            func nameCell(_ l: CellTextLine, up: Double) -> SheetCell {
                var c = cell(edges[1], edges[2], l.text, 12, "left", up)
                if l.textX > 0 || l.marker != nil {
                    c.textX = edges[1] + pad + l.textX
                    c.marker = l.marker
                    c.markerX = edges[1] + pad + l.markerX
                    c.colon = l.colon
                }
                return c
            }
            var first = texts.enumerated().map { cell(edges[$0.offset], edges[$0.offset + 1], $0.element.0, 12, $0.element.1, 4.875) }
            if let l = nameLines.first { first[1] = nameCell(l, up: 4.875) }
            rows.append(SheetRow(kind: "item", height: 18, fill: nil, cells: first, repeats: false, joinNext: nameLines.count > 1))
            for (k, l) in nameLines.enumerated().dropFirst() {
                let last = k == nameLines.count - 1
                var more = texts.indices.map { cell(edges[$0], edges[$0 + 1], "", 12, "left", 4.875) }
                more[1] = nameCell(l, up: last ? 8.625 : 4.875)
                rows.append(SheetRow(kind: "item", height: last ? 18 : 14.25, fill: nil, cells: more, repeats: false, joinNext: !last))
            }
        }
        // "Total Amount :" across the columns before the totals.
        let n = widths.count
        var totals: [SheetCell] = []
        // With rates or charges listed after it, the total is a subtotal.
        let rates = landscape ? (ratesSection?.rates.filter { !$0.name.isEmpty } ?? []) : []
        let hasRates = landscape && ratesSection != nil && (!rates.isEmpty || nonBlank(ratesSection?.title) != nil)
        let shownCharges = landscape ? charges.filter { nonBlank($0.name) != nil || $0.amount != 0 } : []
        if landscape {
            let label = !shownCharges.isEmpty ? "Subtotal Amount :" : hasRates ? "Subtotal :" : "Total Amount :"
            totals.append(cell(edges[0], edges[n - 2], label, 28.99, "center", 8.625))
            totals.append(cell(edges[n - 2], edges[n - 1], formatMoney(grandTotal), 12, "money", 15.375))
        } else {
            totals.append(cell(edges[0], edges[n - 1], chinese ? "總重量 :" : "Total Weight :", 28.99, "center", 8.625))
        }
        totals.append(cell(edges[n - 1], edges[n], kg(totalWeightKg), 12, "right", 15.375))
        // No items but charges after them: no "Subtotal Amount : 0.00".
        if !(lines.isEmpty && !shownCharges.isEmpty) {
            rows.append(SheetRow(kind: "total", height: 38.25, fill: nil, cells: totals, repeats: false))
        }

        // Amounts added after the subtotal (as on the company's sheet for
        // Mr. Law's container access platform): D1 Delivery, D2 Design
        // Fees…, "N/a" for their weight, then "Total Amount".
        if !shownCharges.isEmpty {
            var total = decimalOf(grandTotal)
            for (i, charge) in shownCharges.enumerated() {
                total += decimalOf(charge.amount)
                // A name on two lines (a delivery: what, then the rate) makes the row
                // a line taller; the code sits by its first line, the amount by its last.
                let extra = Double(charge.name.components(separatedBy: "\n").count - 1) * 14.25
                rows.append(SheetRow(kind: "charge", height: 18.75 + extra, fill: nil, cells: [
                    cell(edges[0], edges[1], nonBlank(charge.code) ?? "D\(i + 1)", 12, "left", 5.625 + extra),
                    cell(edges[1], edges[n - 2], charge.name, 12, "left", 5.625),
                    charge.amountText.map { cell(edges[n - 2], edges[n - 1], $0, 12, "center", 5.625) }
                        ?? cell(edges[n - 2], edges[n - 1], formatMoney(charge.amount), 12, "money", 5.625),
                    cell(edges[n - 1], edges[n], "N/a", 12, "center", 5.625),
                ], repeats: false))
            }
            rows.append(SheetRow(kind: "grandTotal", height: 45.75, fill: nil, cells: [
                cell(edges[0], edges[n - 2], "Total Amount", 28.99, "center", 12.375),
                cell(edges[n - 2], edges[n - 1], formatMoney(doubleOf(roundToCents(total))), 12, "money", 19.125),
                cell(edges[n - 1], edges[n], "", 12, "right", 19.125),
            ], repeats: false))
        }

        // Rates after the total (e.g. Erection & Dismantle Manpower Rates):
        // a blue title row, then R1, R2… with "(Rate Only)", then the note.
        if hasRates, let section = ratesSection {
            if let title = nonBlank(section.title) {
                rows.append(SheetRow(kind: "ratesTitle", height: 19.5, fill: blue,
                                     cells: [cell(left, right, title, 13, "center", 4.875)], repeats: false))
            }
            for (i, rate) in rates.enumerated() {
                let unit = rate.unit.trimmingCharacters(in: .whitespaces)
                let texts: [(String, String)] = [
                    ("R\(i + 1)", "center"), (rate.name, "left"), ("", "right"), ("", "center"),
                    (formatMoney(rate.rate) + (unit.isEmpty ? "" : " / \(unit)"), "money"), ("(Rate Only)", "center"), ("", "right"),
                ]
                rows.append(SheetRow(kind: "rate", height: 18, fill: nil,
                                     cells: texts.enumerated().map { cell(edges[$0.offset], edges[$0.offset + 1], $0.element.0, 12, $0.element.1, 4.875) },
                                     repeats: false))
            }
            if let note = nonBlank(section.note) {
                rows.append(SheetRow(kind: "note", height: 15.75, fill: nil,
                                     cells: [cell(left, right, note, 10, "left", 4.125)], repeats: false))
            }
        }

        // The BOQ's notes in one box at the end: "Notes:" and then each
        // line, 14.25pt apart with 9pt above and below; any web address
        // in blue, underlined. Its terms in a box like it after.
        func textBox(_ text: String, heading: String, kind: String) {
            var lines = wrap(text, width: right - left - 2 * 2.625, size: 12)
            if !(lines.first ?? "").lowercased().hasPrefix(heading.lowercased().prefix(4)) { lines.insert("\(heading):", at: 0) }
            for (i, line) in lines.enumerated() {
                let first = i == 0, last = i == lines.count - 1
                var c = cell(left, right, line, 12, "left", last ? 12.375 : 3.375)
                c.link = webAddress(in: line)
                rows.append(SheetRow(kind: kind, height: 14.25 + (first ? 9 : 0) + (last ? 9 : 0), fill: nil,
                                     cells: [c], repeats: false, joinNext: !last))
            }
        }
        if landscape, let text = nonBlank(notes) { textBox(text, heading: "Notes", kind: "notes") }
        if landscape, let text = nonBlank(terms) {
            for row in termsBox(text, left: left, right: right) { rows.append(row) }
        }

        // The signature block under the table, as on the company's own sheet
        // (Mr. Law's): "For and On Behalf of" over a line, then the company,
        // who signs and their title; "Accepted By" over a line, then the
        // client and "Date :". No rules but the two lines to sign on.
        if landscape, let sign = signature {
            let leftEnd = edges[2], rightStart = infoEdges[2], rightEnd = edges[n - 1]
            let texts: [(String, String, Double, Double, Bool)] = [
                ("For and On Behalf of", "Accepted By", 36, 4.125, false),
                ("", "", 48, 0, true),
                (sign.company, sign.client, 20.25, 4.125, false),
                (sign.name, "Date :", 15.75, 4.125, false),
                (sign.title, "", 15.75, 4.125, false),
            ]
            for (i, r) in texts.enumerated() {
                var a = cell(left, leftEnd, r.0, 10, "left", r.3)
                var b = cell(rightStart, rightEnd, r.1, 10, "left", r.3)
                a.lineBelow = r.4
                b.lineBelow = r.4
                rows.append(SheetRow(kind: "signature", height: r.2, fill: nil, cells: [
                    a, cell(leftEnd, rightStart, "", 10, "left", 0), b, cell(rightEnd, right, "", 10, "left", 0),
                ], repeats: false, joinNext: i < texts.count - 1, borderless: true))
            }
        }

        return fitToPage(SheetLayout(landscape: landscape, pageWidth: pageWidth, pageHeight: pageHeight,
                                     left: left, right: right, top: top, bottomLimit: pageHeight - 53.25, rows: rows),
                         smallest: onePage ? 0 : 0.7, portraitBelow: onePage ? 0.6 : nil)
    }

    /// An item on a delivery schedule sheet: its name (in the document's
    /// language), unit, quantity on the document and unit weight.
    struct ScheduleLine {
        var id: String
        var name: String
        var unit: String
        var quantity: Double
        var weightKg: Double?
    }

    /// A delivery schedule as landscape sheets in the BQ sheet's style, for
    /// after a quotation's or BOQ's own pages: the orange "DELIVERY
    /// SCHEDULE" banner, the project code, client, job site and document,
    /// then a blue heading row —
    ///
    ///   No. | Item Name | Unit | Qty | Day 1 (its date) | Day 2 … | Left
    ///
    /// — a row for each item with how many go to site each day, then the
    /// pieces (and weight) each day. Seven days to a sheet; more carry on,
    /// on the next one ("Left" on the last). The days' notes in a box under
    /// the table. Long lists run on over pages under the repeated heading.
    /// The schedule on one page if it can be: every day side by side, on
    /// A4 landscape or A4 portrait — whichever needs less shrinking — or,
    /// if neither holds it at a readable size, on A3 (landscape or
    /// portrait). Only a schedule too big even for A3 goes over several A4
    /// landscape sheets, a run of days on each.
    static func deliverySchedule(info: (projectCode: String, client: String, jobSite: String, document: String),
                                 lines: [ScheduleLine], days: [QuotationDeliveryDay], chinese: Bool, withInternalNotes: Bool = false) -> [SheetLayout] {
        guard !lines.isEmpty, !days.isEmpty else { return [] }
        func onOne(_ width: Double, _ height: Double) -> SheetLayout? {
            guard let raw = scheduleSheets(info: info, lines: lines, days: days, chinese: chinese, withInternalNotes: withInternalNotes,
                                           pageWidth: width, pageHeight: height, everyDay: true).first else { return nil }
            let tall = raw.rows.reduce(0) { $0 + $1.height }
            let k = min(1, (width - 72) / (raw.right - raw.left), (raw.bottomLimit - raw.top - 3) / max(1, tall))
            guard k >= 0.55 else { return nil }
            return k < 1 ? scaled(raw, by: k, from: (raw.left + raw.right) / 2, to: width / 2) : raw
        }
        // The first that's largest wins (landscape before portrait on a tie).
        func best(_ options: [SheetLayout?]) -> SheetLayout? {
            var pick: SheetLayout?
            for case let o? in options where pick == nil || o.scale > pick!.scale + 0.001 { pick = o }
            return pick
        }
        let a4 = best([onOne(842.88, 595.92), onOne(595.92, 842.88)])
        if let a4 = a4, a4.scale >= 0.8 { return [a4] }
        if let roomiest = best([a4, onOne(1190.55, 841.89), onOne(841.89, 1190.55)]) { return [roomiest] }
        return scheduleSheets(info: info, lines: lines, days: days, chinese: chinese, withInternalNotes: withInternalNotes,
                              pageWidth: 842.88, pageHeight: 595.92, everyDay: false)
    }

    /// The schedule laid out for a page `pageWidth` × `pageHeight`: all the
    /// days on one sheet (`everyDay`, as wide as that needs — the caller
    /// shrinks it to fit), or as many as fit on each.
    static func scheduleSheets(info: (projectCode: String, client: String, jobSite: String, document: String),
                               lines: [ScheduleLine], days: [QuotationDeliveryDay], chinese: Bool, withInternalNotes: Bool,
                               pageWidth: Double, pageHeight: Double, everyDay: Bool) -> [SheetLayout] {
        let top = 53.625
        let room = pageWidth - 2 * 36
        let noW = 34.5, unitW = 42.0, qtyW = 51.75, dayW = 56.0, leftW = 51.75
        let perSheet = everyDay ? days.count : max(1, Int((room - noW - unitW - qtyW - 170 - leftW) / dayW))
        let day: (String?) -> String = { iso in
            let p = DateFormatter()
            p.locale = Locale(identifier: "en_US_POSIX")
            p.dateFormat = "yyyy-MM-dd"
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX") // "Sep", not en_GB's "Sept"
            f.dateFormat = "d MMM yyyy"
            return iso.flatMap { p.date(from: String($0.prefix(10))) }.map { f.string(from: $0) } ?? ""
        }
        let weight: (Double) -> String = { $0 >= 1000 ? String(format: "%.2f t", $0 / 1000) : String(format: "%.1f kg", $0) }
        let hasWeights = lines.contains { ($0.weightKg ?? 0) > 0 }
        func cell(_ x0: Double, _ x1: Double, _ text: String, _ size: Double, _ align: String, _ up: Double, font: String = "body") -> SheetCell {
            SheetCell(x0: x0, x1: x1, text: text, font: font, size: size, align: align, baselineUp: up)
        }
        let quantity: (Double) -> String = { $0 == 0 ? "" : formatQuantity($0) }

        var sheets: [SheetLayout] = []
        for start in stride(from: 0, to: days.count, by: perSheet) {
            let chunk = Array(days[start..<min(days.count, start + perSheet)])
            let last = start + perSheet >= days.count
            let nameW = max(170, min(330, room - noW - unitW - qtyW - Double(chunk.count) * dayW - (last ? leftW : 0)))
            let width = noW + nameW + unitW + qtyW + Double(chunk.count) * dayW + (last ? leftW : 0)
            let left = (pageWidth - width) / 2, right = left + width
            var edges = [left, left + noW, left + noW + nameW, left + noW + nameW + unitW, left + noW + nameW + unitW + qtyW]
            for _ in chunk { edges.append(edges.last! + dayW) }
            if last { edges.append(right) }
            let n = edges.count - 1

            var rows: [SheetRow] = []
            // On more than one sheet: which days this one has.
            // An Internal copy says so.
            let marks = (withInternalNotes ? ["INTERNAL"] : []) + (days.count > perSheet ? ["DAY \(chunk.first!.day) – \(chunk.last!.day)"] : [])
            let banner = "DELIVERY SCHEDULE" + (marks.isEmpty ? "" : " (\(marks.joined(separator: ", ")))")
            rows.append(SheetRow(kind: "banner", height: 27.75, fill: orange,
                                 cells: [cell(left, right, banner, 19.99, "center", 6.375, font: "title")], repeats: true))
            let mid = left + width * 0.56
            let infoEdges = [left, left + 68.25, mid, mid + 68.25, right]
            for r in [("Project Code  :", info.projectCode, "Job Site          :", info.jobSite),
                      ("Client             :", info.client, "Document      :", info.document)] {
                rows.append(SheetRow(kind: "info", height: 15.75, fill: cream, cells: [
                    cell(infoEdges[0], infoEdges[1], r.0, 10, "left", 4.125), cell(infoEdges[1], infoEdges[2], r.1, 10, "left", 4.125),
                    cell(infoEdges[2], infoEdges[3], r.2, 10, "left", 4.125), cell(infoEdges[3], infoEdges[4], r.3, 10, "left", 4.125),
                ], repeats: true))
            }
            // Headings: each day with its date under it.
            var heads = (chinese ? ["編號", "物料名稱", "單位", "數量"] : ["No.", "Item Name", "Unit", "Qty"])
                .enumerated().map { cell(edges[$0.offset], edges[$0.offset + 1], $0.element, 12, "center", 12) }
            for (i, d) in chunk.enumerated() {
                let title = chinese ? "第 \(d.day) 天" : "Day \(d.day)"
                let date = day(d.date)
                heads.append(date.isEmpty ? cell(edges[4 + i], edges[5 + i], title, 12, "center", 12)
                                          : cell(edges[4 + i], edges[5 + i], "\(title)\n\(date)", 10.5, "center", 6))
            }
            if last { heads.append(cell(edges[n - 1], edges[n], chinese ? "尚餘" : "Left", 12, "center", 12)) }
            rows.append(SheetRow(kind: "header", height: 33, fill: blue, cells: heads, repeats: true))

            // The items.
            var pieces = Array(repeating: 0.0, count: chunk.count), kgs = Array(repeating: 0.0, count: chunk.count)
            var totalQty = 0.0, totalKg = 0.0, leftQty = 0.0, leftKg = 0.0
            for (i, line) in lines.enumerated() {
                let qty = line.quantity.rounded()
                let unitKg = line.weightKg ?? 0
                totalQty += qty
                totalKg += qty * unitKg
                var cells = [cell(edges[0], edges[1], String(i + 1), 11, "center", 4.875),
                             cell(edges[1], edges[2], plainMarkup(line.name).replacingOccurrences(of: "\n", with: " "), 11, "left", 4.875),
                             cell(edges[2], edges[3], line.unit, 11, "center", 4.875),
                             cell(edges[3], edges[4], formatQuantity(qty), 11, "center", 4.875)]
                for (j, d) in chunk.enumerated() {
                    let q = (d.quantities[line.id] ?? 0).rounded()
                    pieces[j] += q
                    kgs[j] += q * unitKg
                    cells.append(cell(edges[4 + j], edges[5 + j], quantity(q), 11, "center", 4.875))
                }
                if last {
                    let scheduled = days.reduce(0.0) { $0 + ($1.quantities[line.id] ?? 0).rounded() }
                    leftQty += qty - scheduled
                    leftKg += (qty - scheduled) * unitKg
                    cells.append(cell(edges[n - 1], edges[n], quantity(qty - scheduled), 11, "center", 4.875))
                }
                rows.append(SheetRow(kind: "item", height: 18, fill: nil, cells: cells, repeats: false))
            }
            // Pieces (and weight) each day.
            var totals: [(String, String, [String], String)] = [(chinese ? "總件數 :" : "Total Pieces :", formatQuantity(totalQty),
                                                                  pieces.map(quantity), quantity(leftQty))]
            if hasWeights {
                totals.append((chinese ? "總重量 :" : "Total Weight :", weight(totalKg), kgs.map { $0 == 0 ? "" : weight($0) },
                               leftKg == 0 ? "" : weight(leftKg)))
            }
            for t in totals {
                var cells = [cell(edges[0], edges[3], t.0, 12, "right", 6.375), cell(edges[3], edges[4], t.1, 11, "center", 6.375)]
                for (j, text) in t.2.enumerated() { cells.append(cell(edges[4 + j], edges[5 + j], text, 11, "center", 6.375)) }
                if last { cells.append(cell(edges[n - 1], edges[n], t.3, 11, "center", 6.375)) }
                rows.append(SheetRow(kind: "total", height: 21, fill: nil, cells: cells, repeats: false))
            }
            // The days' notes, in a box under the table (an Internal copy:
            // their internal notes too, after them).
            let noted: (KeyPath<QuotationDeliveryDay, String?>) -> [String] = { field in
                chunk.compactMap { d -> String? in
                    guard let note = nonBlank(d[keyPath: field]) else { return nil }
                    let date = day(d.date)
                    return "\(chinese ? "第 \(d.day) 天" : "Day \(d.day)")\(date.isEmpty ? "" : " (\(date))"): \(note)"
                }
            }
            let notes = noted(\.note), internalNotes = withInternalNotes ? noted(\.internalNote) : []
            if !notes.isEmpty || !internalNotes.isEmpty {
                var texts: [String] = []
                let width = right - left - 2 * 2.625
                if !notes.isEmpty { texts.append("Notes:"); for note in notes { texts += wrap(note, width: width, size: 11) } }
                if !internalNotes.isEmpty { texts.append("Internal notes:"); for note in internalNotes { texts += wrap(note, width: width, size: 11) } }
                for (i, text) in texts.enumerated() {
                    let first = i == 0, end = i == texts.count - 1
                    rows.append(SheetRow(kind: "notes", height: 14.25 + (first ? 9 : 0) + (end ? 9 : 0), fill: nil,
                                         cells: [cell(left, right, text, 11, "left", end ? 12.375 : 3.375)], repeats: false, joinNext: !end))
                }
            }
            let sheet = SheetLayout(landscape: pageWidth > pageHeight, pageWidth: pageWidth, pageHeight: pageHeight, left: left, right: right,
                                    top: top, bottomLimit: pageHeight - 53.25, rows: rows)
            sheets.append(everyDay ? sheet : fitToPage(sheet, smallest: 0.8))
        }
        return sheets
    }

    /// The Terms & Conditions box, laid out as on the portrait quotation
    /// (formattedParagraphs): plain paragraphs at the box's edge with a
    /// little space around them; "Payment : …", "(i) …" and "• …" items
    /// with the marker at the edge (or under the item above, when indented)
    /// and the text, and every line under it, set in to one column.
    static func termsBox(_ text: String, left: Double, right: Double) -> [SheetRow] {
        let pad = 2.625
        let width = right - left - 2 * pad
        let font = bodyFont(12)
        let measure: (String) -> Double = { Double(($0 as NSString).size(withAttributes: [.font: font]).width) }
        // (marker, its x, text, the text's x, colon, space above) for each line, x from the text's left edge.
        var lines: [(marker: String?, markerX: Double, text: String, textX: Double, colon: Bool, gap: Double)] = []
        func appendHanging(marker: String, texts: [String], left l: Double, indent: Double?, colon: Bool, gap: Double) {
            // Where the text starts, as hangingTextX on the letter: past a long label, and always 120pt wide.
            let markerWidth = marker.isEmpty ? 0 : measure(marker)
            var textX = indent ?? (l + max(18, markerWidth + 6))
            if !marker.isEmpty { textX = max(textX, l + markerWidth + (colon ? 7.5 : 5)) }
            textX = min(textX, width - 120)
            let pieces = texts.flatMap { wrap($0, width: width - textX, size: 12) }
            for (i, piece) in (pieces.isEmpty ? [""] : pieces).enumerated() {
                lines.append((i == 0 && !marker.isEmpty ? marker : nil, l, piece, textX, i == 0 && colon, i == 0 ? gap : 0))
            }
        }
        // The heading: the text's own first line ("Terms & Conditions:"), or that added.
        var body = text.replacingOccurrences(of: "\r\n", with: "\n").trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: "\n")
        var heading = "Terms & Conditions:"
        if let first = body.first?.trimmingCharacters(in: .whitespaces), first.lowercased().hasPrefix("term"),
           first.hasSuffix(":") || ["terms & conditions", "terms and conditions"].contains(first.lowercased()) {
            heading = first
            body.removeFirst()
        }
        lines.append((nil, 0, heading, 0, false, 0))
        var previous: Bool? = nil // whether the paragraph before was plain text (nil: none yet)
        for paragraph in formattedParagraphs(body.joined(separator: "\n")) {
            var isText = false
            if case .text = paragraph { isText = true }
            // Space between paragraphs as on the portrait letter: none under the
            // heading, nor between one item and the next.
            let gap = previous == nil || (!isText && previous == false) ? 0.0 : 6.0
            switch paragraph {
            case .text(let string, _):
                for (i, line) in wrap(string, width: width, size: 12).enumerated() {
                    lines.append((nil, 0, line, 0, false, i == 0 ? gap : 0))
                }
            case .hanging(let marker, let texts, let l, let indent, let colon):
                appendHanging(marker: marker, texts: texts, left: Double(l), indent: indent.map { Double($0) }, colon: colon, gap: gap)
            case .term(let label, let texts):
                appendHanging(marker: label ?? "", texts: texts, left: 0, indent: Double(labelTextIndent), colon: true, gap: gap)
            }
            previous = isText
        }
        // Each line 14.25pt, with 9pt above and below the box, as the Notes box.
        return lines.enumerated().map { i, line in
            let first = i == 0, last = i == lines.count - 1
            var c = SheetCell(x0: left, x1: right, text: line.text, font: "body", size: 12, align: "left", baselineUp: last ? 12.375 : 3.375)
            c.link = webAddress(in: line.text)
            if line.textX > 0 || line.marker != nil {
                c.textX = left + pad + line.textX
                c.marker = line.marker
                c.markerX = left + pad + line.markerX
                c.colon = line.colon
            }
            return SheetRow(kind: "terms", height: 14.25 + line.gap + (first ? 9 : 0) + (last ? 9 : 0), fill: nil,
                            cells: [c], repeats: false, joinNext: !last)
        }
    }

    /// As Google Sheets' "Fit to page": a sheet a little too long for one
    /// page is shrunk onto it (to no less than `smallest`, 70% for a BOQ),
    /// from the same top margin and about the same centre line, e.g. Mr.
    /// Law's sheet at 76.75%. Longer sheets run on over pages at full size.
    /// A landscape quotation always goes on one page, its terms and
    /// signatures with it (`smallest` 0) — and when that would shrink it
    /// below `portraitBelow` (60%), the same landscape design goes on a
    /// portrait page instead, where its long table has more room and is
    /// shrunk less (only when it does come out bigger there).
    static func fitToPage(_ sheet: SheetLayout, smallest: Double = 0.7, portraitBelow: Double? = nil) -> SheetLayout {
        let height = sheet.rows.reduce(0) { $0 + $1.height }
        let room = sheet.bottomLimit - sheet.top
        guard height > room, room / height >= smallest else { return sheet }
        // 3pt to spare, so Word's rounding never tips the last rows over.
        let k = (room - 3) / height
        let centre = (sheet.left + sheet.right) / 2
        if let below = portraitBelow, sheet.landscape, k < below {
            // A4 portrait: the same top and bottom margins, 36pt at the sides.
            var tall = sheet
            tall.landscape = false
            tall.pageWidth = sheet.pageHeight
            tall.pageHeight = sheet.pageWidth
            tall.bottomLimit = tall.pageHeight - (sheet.pageHeight - sheet.bottomLimit)
            let byWidth = (tall.pageWidth - 72) / (sheet.right - sheet.left)
            let byHeight = (tall.bottomLimit - tall.top - 3) / height
            let kTall = min(1, byWidth, byHeight)
            if kTall > k { return scaled(tall, by: kTall, from: centre, to: tall.pageWidth / 2) }
        }
        return scaled(sheet, by: k, from: centre, to: centre)
    }

    /// The sheet `k` times its size from its top margin, its centre line
    /// moved from `from` to `to`; rules and padding shrink with it.
    static func scaled(_ sheet: SheetLayout, by k: Double, from: Double, to: Double) -> SheetLayout {
        let x: (Double) -> Double = { to + ($0 - from) * k }
        var out = sheet
        out.scale = k
        out.left = x(sheet.left)
        out.right = x(sheet.right)
        out.rows = sheet.rows.map { row in
            var r = row
            r.height = row.height * k
            r.cells = row.cells.map { c in
                var cell = c
                cell.x0 = x(c.x0)
                cell.x1 = x(c.x1)
                cell.size = c.size * k
                cell.baselineUp = c.baselineUp * k
                cell.textX = c.textX.map(x)
                cell.markerX = c.markerX.map(x)
                return cell
            }
            return r
        }
        return out
    }

    /// Calibri, or Carlito (same letter widths), as the renderer uses.
    static func bodyFont(_ size: Double) -> NSFont {
        for name in ["Calibri", "Carlito-Regular", "Carlito", "Helvetica"] {
            if let f = NSFont(name: name, size: CGFloat(size)) { return f }
        }
        return NSFont.systemFont(ofSize: CGFloat(size))
    }

    /// Splits text into lines no wider than `width`, keeping its own line breaks.
    static func wrap(_ text: String, width: Double, size: Double) -> [String] {
        let font = bodyFont(size)
        let measure: (String) -> Double = { Double(($0 as NSString).size(withAttributes: [.font: font]).width) }
        var lines: [String] = []
        for paragraph in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            var current = ""
            for word in paragraph.split(separator: " ", omittingEmptySubsequences: false).map(String.init) {
                let candidate = current.isEmpty ? word : "\(current) \(word)"
                if measure(candidate) <= width || current.isEmpty {
                    current = candidate
                } else {
                    lines.append(current)
                    current = word
                }
            }
            lines.append(current)
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        return lines
    }

    /// The first web address in a line (e.g. "pfitnet.com/TC"), if any.
    static func webAddress(in line: String) -> String? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
              let match = detector.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
              let range = Range(match.range, in: line) else { return nil }
        let found = String(line[range])
        return found.contains("@") ? nil : found
    }
}

/// Draws a `SheetLayout` as a PDF: fills first, then 0.75pt black rules,
/// then text — as Google Sheets does. Rows that don't fit go on the next
/// page, under the repeated banner, info and heading rows.
final class BQSheetRenderer {
    let layout: SheetLayout
    let data = NSMutableData()
    var context: CGContext!
    var rule: Double { 0.75 * layout.scale }

    /// A director's signature and the company chop, drawn over the
    /// "For and On Behalf of" line (a quotation signed in Team › Signatures).
    var signatureImage: CGImage?
    var chopImage: CGImage?

    init(_ layout: SheetLayout) { self.layout = layout }

    static func pdf(_ layout: SheetLayout, signature: CGImage? = nil, chop: CGImage? = nil) -> Data? {
        let renderer = BQSheetRenderer(layout)
        renderer.signatureImage = signature
        renderer.chopImage = chop
        var box = CGRect(x: 0, y: 0, width: layout.pageWidth, height: layout.pageHeight)
        guard let consumer = CGDataConsumer(data: renderer.data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        renderer.context = ctx
        renderer.draw()
        ctx.closePDF()
        return renderer.data as Data
    }

    /// Calibri if it's installed, otherwise Carlito (bundled; same letter
    /// widths as Calibri, SIL Open Font Licence).
    func font(_ cell: SheetCell) -> NSFont {
        let names = cell.font == "title" ? ["Arial-BoldMT", "Arial Bold", "Helvetica-Bold"] : ["Calibri", "Carlito-Regular", "Carlito", "Helvetica"]
        for name in names { if let f = NSFont(name: name, size: CGFloat(cell.size)) { return f } }
        return NSFont.systemFont(ofSize: CGFloat(cell.size))
    }

    func pages() -> [[SheetRow]] {
        let repeating = layout.rows.filter { $0.repeats }
        let body = layout.rows.filter { !$0.repeats }
        let headHeight = repeating.reduce(0) { $0 + $1.height }
        var pages: [[SheetRow]] = []
        var current = repeating
        var y = layout.top + headHeight
        var keepingTogether = false
        for (i, row) in body.enumerated() {
            // Rows joined to the next (the Notes box) move to a new page
            // together, unless they'd fill more than a page.
            var needed = row.height
            if i > 0 && body[i - 1].joinNext {
                if keepingTogether { needed = 0 }
            } else if row.joinNext {
                var j = i
                while body[j].joinNext && j + 1 < body.count { j += 1; needed += body[j].height }
                keepingTogether = needed <= layout.bottomLimit - layout.top - headHeight
                if !keepingTogether { needed = row.height }
            }
            if y + needed > layout.bottomLimit && current.count > repeating.count {
                pages.append(current)
                current = repeating
                y = layout.top + headHeight
            }
            current.append(row)
            y += row.height
        }
        pages.append(current)
        return pages
    }

    func draw() {
        let h = layout.pageHeight
        let half = rule / 2
        for rows in pages() {
            context.beginPDFPage(nil)
            // Fills
            var y = layout.top
            for row in rows {
                if let hex = row.fill {
                    context.setFillColor(color(hex))
                    context.fill(CGRect(x: layout.left - half, y: h - (y + row.height + half), width: layout.right - layout.left + rule, height: row.height + rule))
                }
                y += row.height
            }
            // Rules: along every row edge, and down each cell edge. Rows
            // below the table (the signature block) have only their lines
            // to sign on.
            context.setFillColor(NSColor.black.cgColor)
            y = layout.top
            hLine(y)
            var tableBottom = y
            for (index, row) in rows.enumerated() {
                if row.borderless {
                    for cell in row.cells where cell.lineBelow {
                        context.fill(CGRect(x: cell.x0 - half, y: h - (y + row.height + half), width: cell.x1 - cell.x0 + rule, height: rule))
                    }
                    y += row.height
                    continue
                }
                for cell in row.cells where cell.x0 > layout.left + 0.01 {
                    context.fill(CGRect(x: cell.x0 - half, y: h - (y + row.height + half), width: rule, height: row.height + rule))
                }
                y += row.height
                tableBottom = y
                if !row.joinNext || index == rows.count - 1 { hLine(y) }
            }
            context.fill(CGRect(x: layout.left - half, y: h - (tableBottom + half), width: rule, height: tableBottom - layout.top + rule))
            context.fill(CGRect(x: layout.right - half, y: h - (tableBottom + half), width: rule, height: tableBottom - layout.top + rule))
            // Text
            y = layout.top
            for row in rows {
                for cell in row.cells { drawText(cell, rowBottom: y + row.height) }
                if row.kind == "signature", let line = row.cells.first(where: { $0.lineBelow }) {
                    drawSigning(over: line, rowTop: y, rowBottom: y + row.height)
                }
                y += row.height
            }
            context.endPDFPage()
        }
    }

    /// The signature sits on the company's signing line; the chop overlaps
    /// its right end, a little above and below the line.
    func drawSigning(over cell: SheetCell, rowTop: Double, rowBottom: Double) {
        let h = layout.pageHeight
        let room = rowBottom - rowTop
        var signatureWidth = (cell.x1 - cell.x0) * 0.4
        if let sig = signatureImage {
            let maxW = (cell.x1 - cell.x0) * 0.62, maxH = room * 0.92
            let k = min(maxW / Double(sig.width), maxH / Double(sig.height))
            let w = Double(sig.width) * k, ht = Double(sig.height) * k
            context.draw(sig, in: CGRect(x: cell.x0 + 6, y: h - rowBottom + 1, width: w, height: ht))
            signatureWidth = w
        }
        // The chop goes over the signature (its middle a little past the
        // signature's middle), not out at the end of the line.
        if let chop = chopImage {
            // Its middle stays where the full-size chop's was (a quarter of
            // it below the line); it is drawn at chopScale of that size.
            let full = room * 1.45
            let fullHeight = Double(chop.height) * full / Double(max(chop.width, chop.height))
            let middleY = h - rowBottom - fullHeight * 0.25 + fullHeight / 2
            let side = full * Double(chopScale)
            let k = side / Double(max(chop.width, chop.height))
            let w = Double(chop.width) * k, ht = Double(chop.height) * k
            let x = min(cell.x0 + 6 + signatureWidth * 0.6 - w / 2, cell.x1 - w - 4)
            context.draw(chop, in: CGRect(x: max(cell.x0 + 6, x), y: middleY - ht / 2, width: w, height: ht))
        }
    }

    func hLine(_ y: Double) {
        context.fill(CGRect(x: layout.left - rule / 2, y: layout.pageHeight - (y + rule / 2), width: layout.right - layout.left + rule, height: rule))
    }

    func color(_ hex: String) -> CGColor {
        let v = Int(hex, radix: 16) ?? 0
        return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    func line(_ text: String, _ font: NSFont, link: String? = nil) -> CTLine {
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let string = NSMutableAttributedString(string: text, attributes: [.font: font, colorKey: NSColor.black.cgColor])
        if let link = link {
            let range = (text as NSString).range(of: link)
            if range.location != NSNotFound { string.addAttribute(colorKey, value: color(BQSheetRenderer.linkBlue), range: range) }
        }
        return CTLineCreateWithAttributedString(string)
    }

    /// Links as Google Sheets shows them: blue, with a 0.75pt underline 1.125pt below the baseline.
    static let linkBlue = "1155CC"

    func width(_ l: CTLine) -> Double { Double(CTLineGetTypographicBounds(l, nil, nil, nil)) }

    func put(_ l: CTLine, x: Double, baseline: Double) {
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: layout.pageHeight - baseline)
        CTLineDraw(l, context)
        context.restoreGState()
    }

    /// Text is 2.625pt in from the cell's rules; right-aligned figures
    /// keep a space's width before the rule, as the sheet's number formats do.
    func drawText(_ cell: SheetCell, rowBottom: Double) {
        // Text on more than one line: each 14.25pt above the next, the last where the cell's baseline is.
        let pieces = cell.text.components(separatedBy: "\n")
        if pieces.count > 1 {
            for (i, piece) in pieces.enumerated() {
                var one = cell
                one.text = piece
                one.baselineUp = cell.baselineUp + Double(pieces.count - 1 - i) * 14.25 * layout.scale
                if i > 0 { one.marker = nil; one.colon = false }
                drawText(one, rowBottom: rowBottom)
            }
            return
        }
        let pad = 2.625 * layout.scale
        let baseline = rowBottom - cell.baselineUp
        // A term's marker ("(i) Payment") and the colon before its text.
        if let marker = cell.marker, !marker.isEmpty { put(line(marker, font(cell)), x: cell.markerX ?? cell.x0 + pad, baseline: baseline) }
        if cell.colon, let textX = cell.textX { put(line(":", font(cell)), x: textX - 3.75 * layout.scale, baseline: baseline) }
        guard !cell.text.isEmpty else { return }
        var f = font(cell)
        let start = cell.textX ?? cell.x0 + pad
        let space = width(line(" ", f))
        let room = cell.x1 - pad - start - (cell.align == "right" || cell.align == "money" ? space : 0)
        var l = line(cell.text, f, link: cell.link)
        // Too long for its cell: a slightly smaller size, never wrapped.
        if width(l) > room, room > 0 {
            f = NSFont(descriptor: f.fontDescriptor, size: max(f.pointSize * CGFloat(room / width(l)), f.pointSize * 0.6)) ?? f
            l = line(cell.text, f, link: cell.link)
        }
        var x: Double
        switch cell.align {
        case "center": x = (cell.x0 + cell.x1) / 2 - width(l) / 2
        case "right", "money": x = cell.x1 - pad - space - width(l)
        default: x = start
        }
        if cell.align == "money" { put(line("$", f), x: cell.x0 + pad, baseline: baseline) }
        put(l, x: x, baseline: baseline)
        if let link = cell.link, let range = cell.text.range(of: link) {
            let start = x + width(line(String(cell.text[..<range.lowerBound]), f))
            context.setFillColor(color(BQSheetRenderer.linkBlue))
            context.fill(CGRect(x: start, y: layout.pageHeight - (baseline + 1.125 * layout.scale) - rule / 2, width: width(line(link, f)), height: rule))
            context.setFillColor(NSColor.black.cgColor)
        }
    }
}

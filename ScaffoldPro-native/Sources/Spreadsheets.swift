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
// MARK: - Price-list import (sections 8, 49)
//
// Reads .xlsx (via macOS's built-in /usr/bin/unzip + XMLParser — no extra
// libraries) or .csv, finds the header row by recognising column titles,
// and matches rows to existing items by item code (or by name when the
// file has no code column). Nothing is written until the person has seen
// a preview and confirmed.
// =====================================================================

/// Collects the attributes of every element with one of the given local
/// names (namespace prefix ignored).
final class XMLAttributeCollector: NSObject, XMLParserDelegate {
    let wanted: Set<String>
    var found: [[String: String]] = []
    init(_ names: Set<String>) { wanted = names }
    static func collect(_ data: Data, _ names: Set<String>) -> [[String: String]] {
        let c = XMLAttributeCollector(names)
        let p = XMLParser(data: data)
        p.delegate = c
        p.parse()
        return c.found
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if wanted.contains(local) { found.append(attributeDict) }
    }
}

/// xl/sharedStrings.xml → array of strings (rich-text runs joined,
/// phonetic hints ignored).
final class SharedStringsParser: NSObject, XMLParserDelegate {
    var strings: [String] = []
    var current = ""
    var inSI = false, inT = false, inPhonetic = false
    static func parse(_ data: Data) -> [String] {
        let d = SharedStringsParser()
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.strings
    }
    func local(_ n: String) -> String { n.split(separator: ":").last.map(String.init) ?? n }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        switch local(elementName) {
        case "si": inSI = true; current = ""
        case "t": inT = true
        case "rPh": inPhonetic = true
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inSI && inT && !inPhonetic { current += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch local(elementName) {
        case "si": inSI = false; strings.append(current)
        case "t": inT = false
        case "rPh": inPhonetic = false
        default: break
        }
    }
}

/// One worksheet → rows of cell text, in column order.
final class WorksheetParser: NSObject, XMLParserDelegate {
    let shared: [String]
    var rows: [Int: [Int: String]] = [:]
    var cellRef = "", cellType = "", value = "", inline = ""
    var inV = false, inInlineT = false, inCell = false
    var nextRow = 1
    init(shared: [String]) { self.shared = shared }

    static func parse(_ data: Data, shared: [String]) -> [[String]] {
        let d = WorksheetParser(shared: shared)
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        guard let maxRow = d.rows.keys.max() else { return [] }
        return (1...maxRow).map { r in
            let cells = d.rows[r] ?? [:]
            guard let maxCol = cells.keys.max() else { return [] }
            return (0...maxCol).map { cells[$0] ?? "" }
        }
    }
    func local(_ n: String) -> String { n.split(separator: ":").last.map(String.init) ?? n }
    static func columnIndex(_ ref: String) -> Int {
        var n = 0
        for ch in ref.uppercased() {
            guard let a = ch.asciiValue, a >= 65, a <= 90 else { break }
            n = n * 26 + Int(a - 64)
        }
        return max(0, n - 1)
    }
    static func rowNumber(_ ref: String) -> Int? { Int(ref.filter { $0.isNumber }) }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes a: [String: String] = [:]) {
        switch local(elementName) {
        case "row":
            if let r = a["r"].flatMap(Int.init) { nextRow = r }
        case "c":
            inCell = true
            cellRef = a["r"] ?? ""
            cellType = a["t"] ?? ""
            value = ""
            inline = ""
        case "v": inV = true
        case "t": if inCell { inInlineT = true }
        default: break
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inV { value += string }
        if inInlineT { inline += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        switch local(elementName) {
        case "v": inV = false
        case "t": inInlineT = false
        case "c":
            inCell = false
            let text: String
            switch cellType {
            case "s": text = Int(value).flatMap { $0 < shared.count ? shared[$0] : nil } ?? ""
            case "inlineStr": text = inline
            case "b": text = value == "1" ? "TRUE" : "FALSE"
            default: text = value
            }
            let row = WorksheetParser.rowNumber(cellRef) ?? nextRow
            let col = WorksheetParser.columnIndex(cellRef)
            rows[row, default: [:]][col] = text.trimmingCharacters(in: .whitespacesAndNewlines)
        case "row": nextRow += 1
        default: break
        }
    }
}

struct SpreadsheetSheet {
    var name: String
    var rows: [[String]]
}

enum SpreadsheetReader {
    static func unzipEntry(_ file: URL, _ entry: String) -> Data? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        p.arguments = ["-p", file.path, entry]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do { try p.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus == 0 && !data.isEmpty) ? data : nil
    }

    static func readXLSX(_ file: URL) throws -> [SpreadsheetSheet] {
        guard let workbook = unzipEntry(file, "xl/workbook.xml") else {
            throw BackupError(message: "This file couldn't be opened as an Excel workbook (.xlsx). If it's an older .xls or a .csv file, open it in Excel or Numbers and save it as an Excel workbook (.xlsx) first.")
        }
        let shared = unzipEntry(file, "xl/sharedStrings.xml").map(SharedStringsParser.parse) ?? []
        let rels = unzipEntry(file, "xl/_rels/workbook.xml.rels").map { XMLAttributeCollector.collect($0, ["Relationship"]) } ?? []
        var sheets: [SpreadsheetSheet] = []
        for (index, attrs) in XMLAttributeCollector.collect(workbook, ["sheet"]).enumerated() {
            let name = attrs["name"] ?? "Sheet \(index + 1)"
            let rid = attrs["r:id"] ?? attrs["id"] ?? ""
            var path = "xl/worksheets/sheet\(index + 1).xml"
            if let target = rels.first(where: { $0["Id"] == rid })?["Target"] {
                path = target.hasPrefix("/") ? String(target.dropFirst()) : (target.hasPrefix("xl/") ? target : "xl/" + target)
            }
            if let data = unzipEntry(file, path) {
                sheets.append(SpreadsheetSheet(name: name, rows: WorksheetParser.parse(data, shared: shared)))
            }
        }
        guard !sheets.isEmpty else { throw BackupError(message: "No worksheets were found in this workbook.") }
        return sheets
    }

    static func readCSV(_ file: URL) throws -> [SpreadsheetSheet] {
        let raw: String
        if let utf8 = try? String(contentsOf: file, encoding: .utf8) {
            raw = utf8
        } else if let latin = try? String(contentsOf: file, encoding: .isoLatin1) {
            raw = latin
        } else {
            throw BackupError(message: "This CSV file couldn't be read.")
        }
        return [SpreadsheetSheet(name: file.deletingPathExtension().lastPathComponent, rows: parseCSV(raw))]
    }

    /// CSV text as rows of cells (commas, or semicolons when the first line
    /// has more of them; quoted cells may hold commas, quotes and line breaks).
    static func parseCSV(_ raw: String) -> [[String]] {
        // "\r\n" is one Character in Swift: made "\n" first, so it ends a row.
        let text = (raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw)
            .replacingOccurrences(of: "\r\n", with: "\n")
        let firstLine = text.split(separator: "\n", maxSplits: 1).first.map(String.init) ?? ""
        let delimiter: Character = (firstLine.filter { $0 == ";" }.count > firstLine.filter { $0 == "," }.count) ? ";" : ","
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var chars = Array(text)
        chars.append("\n")
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if inQuotes {
                if ch == "\"" {
                    if i + 1 < chars.count && chars[i + 1] == "\"" { field.append("\""); i += 1 } else { inQuotes = false }
                } else { field.append(ch) }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == delimiter {
                row.append(field.trimmingCharacters(in: .whitespaces)); field = ""
            } else if ch == "\n" || ch == "\r" {
                if ch == "\r" && i + 1 < chars.count && chars[i + 1] == "\n" { i += 1 }
                row.append(field.trimmingCharacters(in: .whitespaces)); field = ""
                if !(row.count == 1 && row[0].isEmpty) { rows.append(row) }
                row = []
            } else {
                field.append(ch)
            }
            i += 1
        }
        return rows
    }
}

struct ParsedPriceRow {
    var code: String?
    var name: String
    var category: String?
    var unit: String?
    var weightKg: Double?
    var salePrice: Double?
    var rentalPrice: Double?
}

// MARK: - Clients & sites to and from Excel
//
// Export writes a real .xlsx (the parts zipped with macOS's /usr/bin/zip);
// import reads .xlsx or .csv, finds the row of column titles, and matches
// each row to an existing record by its reference, else its name. Nothing
// is written until the person has seen what will be added and updated.

enum SpreadsheetWriter {
    static func xml(_ s: String) -> String {
        var out = ""
        for ch in s.unicodeScalars {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default:
                // Control characters aren't allowed in the XML (tab and line breaks are).
                if ch.value < 0x20 && ch != "\t" && ch != "\n" && ch != "\r" { continue }
                out.unicodeScalars.append(ch)
            }
        }
        return out
    }

    static func columnName(_ index: Int) -> String {
        var n = index + 1
        var name = ""
        while n > 0 {
            let r = (n - 1) % 26
            name = String(Character(Unicode.Scalar(UInt8(65 + r)))) + name
            n = (n - 1) / 26
        }
        return name
    }

    /// A cell that reads as a plain number (1234, -5, 4391.80), written as
    /// one so Excel can add it up. Not one with a leading zero (00001, a
    /// phone number) or a very long one (an account number): those stay text.
    static func plainNumber(_ s: String) -> String? {
        guard s.count <= 15, s.range(of: "^-?(0|[1-9][0-9]*)(\\.[0-9]+)?$", options: .regularExpression) != nil else { return nil }
        return s
    }

    /// A sheet name Excel accepts: up to 31 characters, none of : \ / ? * [ ].
    static func sheetName(_ s: String) -> String {
        let cleaned = String(s.map { ":\\/?*[]".contains($0) ? "-" : $0 }).trimmingCharacters(in: .whitespaces)
        return cleaned.isEmpty ? "Sheet1" : String(cleaned.prefix(31))
    }

    /// Columns kept as text even with `numbers` (by their title): codes,
    /// numbers that are names (Project No. 26212, item code 3.10), phones,
    /// accounts and references.
    static func textOnlyColumn(_ title: String) -> Bool {
        title.range(of: "code|\\bno\\b|no\\.|number|phone|tel\\b|mobile|fax|account|ref", options: [.regularExpression, .caseInsensitive]) != nil
    }

    /// One worksheet: the first row is the column titles (bold, kept at the
    /// top while scrolling); cells are text, so phone numbers keep their zeros
    /// — unless `numbers`, when plain numbers are written as numbers (keeping
    /// their 1 or 2 decimals), except in code / number / phone columns.
    static func writeXLSX(sheetName: String, rows: [[String]], to url: URL, numbers: Bool = false) throws {
        let textColumns = Set((rows.first ?? []).enumerated().filter { textOnlyColumn($0.element) }.map { $0.offset })
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("xlsx-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: dir) }
        let colCount = rows.map { $0.count }.max() ?? 0
        var widths: [Int] = Array(repeating: 10, count: colCount)
        for row in rows {
            for (i, v) in row.enumerated() {
                let longest = v.components(separatedBy: "\n").map { $0.count }.max() ?? 0
                widths[i] = min(60, max(widths[i], longest + 2))
            }
        }
        var sheet = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><cols>
        """
        for (i, w) in widths.enumerated() { sheet += "<col min=\"\(i + 1)\" max=\"\(i + 1)\" width=\"\(w)\" customWidth=\"1\"/>" }
        sheet += "</cols><sheetData>"
        for (r, row) in rows.enumerated() {
            sheet += "<row r=\"\(r + 1)\">"
            let style = r == 0 ? " s=\"1\"" : ""
            for (c, value) in row.enumerated() where !value.isEmpty {
                let ref = columnName(c) + String(r + 1)
                if numbers && r > 0 && !textColumns.contains(c), let n = plainNumber(value) {
                    // 2 decimals → style 2 (#,##0.00), 1 → style 3 (#,##0.0), whole → General.
                    let decimals = n.split(separator: ".").dropFirst().first?.count ?? 0
                    let numberStyle = decimals >= 2 ? " s=\"2\"" : (decimals == 1 ? " s=\"3\"" : "")
                    sheet += "<c r=\"" + ref + "\"" + numberStyle + "><v>" + n + "</v></c>"
                } else {
                    sheet += "<c r=\"" + ref + "\" t=\"inlineStr\"" + style + "><is><t xml:space=\"preserve\">" + xml(value) + "</t></is></c>"
                }
            }
            sheet += "</row>"
        }
        sheet += "</sheetData></worksheet>"
        let files: [String: String] = [
            "[Content_Types].xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>
            """,
            "_rels/.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>
            """,
            "xl/workbook.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="\(xml(Self.sheetName(sheetName)))" sheetId="1" r:id="rId1"/></sheets></workbook>
            """,
            "xl/_rels/workbook.xml.rels": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>
            """,
            "xl/styles.xml": """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><numFmts count="1"><numFmt numFmtId="164" formatCode="#,##0.0"/></numFmts><fonts count="2"><font><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="11"/><name val="Calibri"/></font></fonts><fills count="2"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="4"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/><xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>
            """,
            "xl/worksheets/sheet1.xml": sheet,
        ]
        for (path, content) in files {
            let file = dir.appendingPathComponent(path)
            try fm.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: file)
        }
        let zipped = dir.appendingPathComponent("out.xlsx")
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        p.currentDirectoryURL = dir
        p.arguments = ["-q", "-X", "-r", zipped.path, "[Content_Types].xml", "_rels", "xl"]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { throw BackupError(message: "The Excel file couldn't be made.") }
        if fm.fileExists(atPath: url.path) { try fm.removeItem(at: url) }
        try fm.copyItem(at: zipped, to: url)
    }
}

/// The columns of the Clients and Sites spreadsheets: title, the record's
/// field, and other titles recognised on import.
struct PartyColumn {
    var title: String
    var key: String
    var aliases: [String]
}

enum PartySheet {
    static let clients: [PartyColumn] = [
        PartyColumn(title: "Company Name", key: "companyName", aliases: ["company", "client", "clientname", "name", "companyname"]),
        PartyColumn(title: "Client Reference", key: "clientReference", aliases: ["reference", "ref", "clientref", "code", "clientcode"]),
        PartyColumn(title: "Contact Person", key: "contactPerson", aliases: ["contact", "attn", "attention"]),
        PartyColumn(title: "Phone", key: "phone", aliases: ["tel", "telephone", "mobile", "phoneno", "contactno"]),
        PartyColumn(title: "Email", key: "email", aliases: ["emailaddress", "mail"]),
        PartyColumn(title: "Address Line 1", key: "address", aliases: ["address", "address1", "addressline1"]),
        PartyColumn(title: "Address Line 2", key: "addressLine2", aliases: ["address2"]),
        PartyColumn(title: "Address Line 3", key: "addressLine3", aliases: ["address3"]),
        PartyColumn(title: "City", key: "city", aliases: ["district", "town"]),
        PartyColumn(title: "Postal Code", key: "postalCode", aliases: ["postcode", "zip", "zipcode"]),
        PartyColumn(title: "Country", key: "country", aliases: []),
        PartyColumn(title: "Default Markup (%)", key: "defaultMarkupPercent", aliases: ["markup", "defaultmarkup", "markuppercent"]),
        PartyColumn(title: "Billing Information", key: "billingInfo", aliases: ["billing", "billinginfo", "billingaddress"]),
        PartyColumn(title: "Notes", key: "notes", aliases: ["note", "remarks", "remark"]),
        PartyColumn(title: "Archived", key: "isArchived", aliases: []),
    ]
    static let sites: [PartyColumn] = [
        PartyColumn(title: "Site Name", key: "name", aliases: ["site", "name", "sitename"]),
        PartyColumn(title: "Site Reference", key: "siteReference", aliases: ["reference", "ref", "siteref", "code", "sitecode"]),
        PartyColumn(title: "Address", key: "address", aliases: ["siteaddress", "address1", "addressline1", "location"]),
        PartyColumn(title: "Contact Person", key: "contactPerson", aliases: ["contact", "sitecontact"]),
        PartyColumn(title: "Phone", key: "phone", aliases: ["tel", "telephone", "mobile", "phoneno", "contactno"]),
        PartyColumn(title: "Email", key: "email", aliases: ["emailaddress", "mail"]),
        PartyColumn(title: "City", key: "city", aliases: ["district", "town"]),
        PartyColumn(title: "Postal Code", key: "postalCode", aliases: ["postcode", "zip", "zipcode"]),
        PartyColumn(title: "Country", key: "country", aliases: []),
        PartyColumn(title: "Notes", key: "notes", aliases: ["note", "remarks", "remark"]),
        PartyColumn(title: "Archived", key: "isArchived", aliases: []),
    ]

    static func columns(_ kind: String) -> [PartyColumn] { kind == "sites" ? sites : clients }

    static func normalise(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for u in s.lowercased().unicodeScalars where CharacterSet.alphanumerics.contains(u) { out.append(u) }
        return String(out)
    }

    /// Finds the title row (in the first 15 rows) and which column is which.
    /// nil when there's no column for the name.
    static func interpret(_ sheet: SpreadsheetSheet, kind: String) -> (header: Int, map: [Int: PartyColumn])? {
        let cols = columns(kind)
        for (r, row) in sheet.rows.prefix(15).enumerated() {
            var map: [Int: PartyColumn] = [:]
            var used = Set<String>()
            for (c, cell) in row.enumerated() {
                let n = normalise(cell)
                guard !n.isEmpty else { continue }
                // Exact titles first, then the other names for a column.
                if let col = cols.first(where: { normalise($0.title) == n && !used.contains($0.key) })
                    ?? cols.first(where: { $0.aliases.contains(n) && !used.contains($0.key) }) {
                    map[c] = col
                    used.insert(col.key)
                }
            }
            if used.contains(cols[0].key) { return (r, map) }
        }
        return nil
    }
}

struct PartyImportPreview: Codable {
    var ok: Bool
    var error: String?
    var token: String?
    var fileName: String?
    var sheetName: String?
    var columns: [String]
    var rowsFound: Int
    var toAdd: Int
    var toUpdate: Int
    var samples: [String]
}

struct PartyImportResult: Codable {
    var ok: Bool
    var error: String?
    var added: Int
    var updated: Int
    var skipped: [String]
}

extension AppDatabase {
    func partyValue(_ v: String?) -> String { v ?? "" }

    /// The spreadsheet rows (titles first) for Export to Excel.
    func partySheetRows(kind: String, includeArchived: Bool) -> [[String]] {
        let cols = PartySheet.columns(kind)
        var rows = [cols.map { $0.title }]
        if kind == "sites" {
            for s in listSites(includeArchived: includeArchived) {
                let values: [String: String] = ["name": s.name, "siteReference": partyValue(s.siteReference), "address": partyValue(s.address),
                    "contactPerson": partyValue(s.contactPerson), "phone": partyValue(s.phone), "email": partyValue(s.email), "city": partyValue(s.city),
                    "postalCode": partyValue(s.postalCode), "country": partyValue(s.country), "notes": partyValue(s.notes), "isArchived": s.isArchived ? "Yes" : ""]
                rows.append(cols.map { values[$0.key] ?? "" })
            }
        } else {
            for c in listClients(includeArchived: includeArchived) {
                var markupText = ""
                if let m = c.defaultMarkupPercent { markupText = m == m.rounded() ? String(Int(m)) : String(m) }
                let values: [String: String] = ["companyName": c.companyName, "clientReference": partyValue(c.clientReference), "contactPerson": partyValue(c.contactPerson),
                    "phone": partyValue(c.phone), "email": partyValue(c.email), "address": partyValue(c.address), "addressLine2": partyValue(c.addressLine2),
                    "addressLine3": partyValue(c.addressLine3), "city": partyValue(c.city), "postalCode": partyValue(c.postalCode), "country": partyValue(c.country),
                    "defaultMarkupPercent": markupText,
                    "billingInfo": partyValue(c.billingInfo), "notes": partyValue(c.notes), "isArchived": c.isArchived ? "Yes" : ""]
                rows.append(cols.map { values[$0.key] ?? "" })
            }
        }
        return rows
    }

    /// The record's fields as the form would send them.
    func partyPayload(kind: String, id: String) -> [String: Any]? {
        if kind == "sites" {
            guard let s = getSite(id: id) else { return nil }
            return ["name": s.name, "siteReference": partyValue(s.siteReference), "address": partyValue(s.address), "contactPerson": partyValue(s.contactPerson),
                    "phone": partyValue(s.phone), "email": partyValue(s.email), "city": partyValue(s.city), "postalCode": partyValue(s.postalCode),
                    "country": partyValue(s.country), "notes": partyValue(s.notes)]
        }
        guard let c = getClient(id: id) else { return nil }
        return ["companyName": c.companyName, "clientReference": partyValue(c.clientReference), "contactPerson": partyValue(c.contactPerson),
                "phone": partyValue(c.phone), "email": partyValue(c.email), "address": partyValue(c.address), "addressLine2": partyValue(c.addressLine2),
                "addressLine3": partyValue(c.addressLine3), "city": partyValue(c.city), "postalCode": partyValue(c.postalCode), "country": partyValue(c.country),
                "defaultMarkupPercent": c.defaultMarkupPercent.map { String($0) } ?? "", "billingInfo": partyValue(c.billingInfo), "notes": partyValue(c.notes),
                "vatNumber": partyValue(c.vatNumber)]
    }

    /// Each imported row with the record it updates (nil: a new one).
    /// Matched by reference when both have one, else by name.
    func matchPartyRows(kind: String, rows: [[String: String]]) -> [(row: [String: String], matchId: String?)] {
        let nameKey = PartySheet.columns(kind)[0].key
        let refKey = kind == "sites" ? "siteReference" : "clientReference"
        var existing: [(id: String, name: String, ref: String)] = []
        if kind == "sites" {
            for s in allSites() { existing.append((id: s.id, name: s.name, ref: s.siteReference ?? "")) }
        } else {
            for c in allClients() { existing.append((id: c.id, name: c.companyName, ref: c.clientReference ?? "")) }
        }
        func norm(_ s: String) -> String { s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        var out: [(row: [String: String], matchId: String?)] = []
        for row in rows {
            let ref = norm(row[refKey] ?? "")
            let name = norm(row[nameKey] ?? "")
            var hitId: String? = nil
            if !ref.isEmpty, let byRef = existing.first(where: { norm($0.ref) == ref }) { hitId = byRef.id }
            if hitId == nil, let byName = existing.first(where: { norm($0.name) == name }) { hitId = byName.id }
            out.append((row: row, matchId: hitId))
        }
        return out
    }

    /// Adds and updates the records. Blank cells leave what's there.
    func applyPartyImport(kind: String, rows: [(row: [String: String], matchId: String?)]) -> PartyImportResult {
        var added = 0, updated = 0
        var skipped: [String] = []
        for (row, matchId) in rows {
            // A blank Archived cell leaves it as it is.
            var archived: Bool? = nil
            if let cell = row["isArchived"], !cell.isEmpty { archived = ["yes", "y", "true", "1", "archived"].contains(cell.lowercased()) }
            var fields = row.filter { $0.key != "isArchived" && !$0.value.isEmpty }
            let label = fields[PartySheet.columns(kind)[0].key] ?? "?"
            if let id = matchId, var payload = partyPayload(kind: kind, id: id) {
                for (k, v) in fields { payload[k] = v }
                let error = kind == "sites" ? updateSite(id: id, payload: payload) : updateClient(id: id, payload: payload)
                if let e = error { skipped.append("\(label): \(e)"); continue }
                if let a = archived {
                    if kind == "sites" { _ = setSiteArchived(id: id, archived: a) } else { _ = setClientArchived(id: id, archived: a) }
                }
                updated += 1
            } else {
                if kind != "sites", let m = fields["defaultMarkupPercent"], Double(m.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) == nil {
                    fields["defaultMarkupPercent"] = nil
                }
                let payload: [String: Any] = fields
                if kind == "sites" {
                    let newId = createSite(payload).id
                    if archived == true { _ = setSiteArchived(id: newId, archived: true) }
                } else {
                    let newId = createClient(payload).id
                    if archived == true { _ = setClientArchived(id: newId, archived: true) }
                }
                added += 1
            }
        }
        return PartyImportResult(ok: true, error: nil, added: added, updated: updated, skipped: skipped)
    }
}

struct PriceImportPreview: Codable {
    var ok: Bool
    var error: String?
    var token: String?
    var fileName: String?
    var sheetName: String?
    /// e.g. "Item name ← “Description”" — documents the mapping used.
    var mapping: [String]
    var rowsFound: Int
    var toAdd: Int
    var toUpdate: Int
    var samples: [String]
}

struct PriceImportResult: Codable {
    var ok: Bool
    var error: String?
    var added: Int
    var updated: Int
}

enum PriceSheetInterpreter {
    static func classify(_ raw: String) -> String? {
        let h = raw.lowercased().replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
        if h.isEmpty { return nil }
        if h.contains("rent") || h.contains("hire") { return "rental" }
        if h.contains("sale") || h.contains("sell") || h.hasPrefix("price") || h.contains("unit price") || h == "hk$" { return "sale" }
        if h.contains("weight") || h == "kg" || h.contains("(kg)") || h == "wt" || h == "wt." { return "weight" }
        if h.contains("product no") || h.contains("product code") || h.contains("part no") || h.contains("sku") { return "altcode" }
        if h.contains("code") || ["no", "no.", "item no", "item no.", "ref", "ref.", "#", "item #"].contains(h) { return "code" }
        if h.contains("category") || h == "group" || h == "type" || h == "section" { return "category" }
        if ["unit", "units", "uom", "u/m"].contains(h) { return "unit" }
        if h.contains("description") || h.contains("item") || h.contains("name") || h.contains("material") || h.contains("product") { return "name" }
        return nil
    }

    static func number(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: "HK$", with: "").replacingOccurrences(of: "HKD", with: "")
            .replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "kg", with: "").trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, cleaned != "-", cleaned != "—" else { return nil }
        return Double(cleaned)
    }

    /// Picks the header row, maps columns, and turns the rest into rows.
    static func interpret(_ sheet: SpreadsheetSheet) -> (rows: [ParsedPriceRow], mapping: [String])? {
        var bestRow = -1
        var bestMap: [String: Int] = [:]
        var bestScore = 0
        for (r, row) in sheet.rows.prefix(25).enumerated() {
            var map: [String: [Int]] = [:]
            for (c, cell) in row.enumerated() { if let k = classify(cell) { map[k, default: []].append(c) } }
            guard map["name"] != nil, map["sale"] != nil || map["rental"] != nil || map["weight"] != nil else { continue }
            let score = map.keys.count
            if score > bestScore {
                bestScore = score
                bestRow = r
                var single: [String: Int] = [:]
                for (k, cols) in map { single[k] = cols[0] }
                // Two "name"-like columns (e.g. "Item" + "Description"): the
                // one with shorter values is really the code column.
                if let names = map["name"], names.count >= 2, single["code"] == nil {
                    func avgLen(_ col: Int) -> Double {
                        let vals = sheet.rows.dropFirst(r + 1).prefix(40).compactMap { col < $0.count ? $0[col] : nil }.filter { !$0.isEmpty }
                        return vals.isEmpty ? 0 : Double(vals.reduce(0) { $0 + $1.count }) / Double(vals.count)
                    }
                    let sorted = names.prefix(2).sorted { avgLen($0) > avgLen($1) }
                    single["name"] = sorted[0]
                    single["code"] = sorted[1]
                }
                // An untitled column full of values like 1.1, 1.2 … 12.3 is
                // the item-code column (the company workbook's column A).
                if single["code"] == nil {
                    let used = Set(single.values)
                    let dataRows = sheet.rows.dropFirst(r + 1).prefix(80)
                    let width = dataRows.map { $0.count }.max() ?? 0
                    for col in 0..<width where !used.contains(col) {
                        let vals = dataRows.compactMap { col < $0.count ? $0[col] : nil }.filter { !$0.isEmpty }
                        let codeLike = vals.filter { $0.range(of: #"^\d+(\.\d+)+$"#, options: .regularExpression) != nil }
                        if vals.count >= 3, Double(codeLike.count) >= Double(vals.count) * 0.6 { single["code"] = col; break }
                    }
                }
                if single["code"] == nil, let alt = single["altcode"] { single["code"] = alt }
                bestMap = single
            }
        }
        guard bestRow >= 0, let nameCol = bestMap["name"] else { return nil }
        let header = sheet.rows[bestRow]
        let labels: [(String, String)] = [("code", "Item code"), ("name", "Item name"), ("category", "Category"), ("unit", "Unit"),
                                          ("weight", "Weight (kg)"), ("sale", "Sale price"), ("rental", "Rental price")]
        var mapping: [String] = []
        for (key, label) in labels {
            if let c = bestMap[key], c < header.count { mapping.append("\(label) ← “\(header[c])”") }
        }
        if bestMap["category"] == nil { mapping.append("Category ← heading rows between groups of items") }

        func cell(_ row: [String], _ key: String) -> String {
            guard let c = bestMap[key], c < row.count else { return "" }
            return row[c]
        }
        var result: [ParsedPriceRow] = []
        var currentCategory: String? = nil
        for row in sheet.rows.dropFirst(bestRow + 1) {
            let name = nameCol < row.count ? row[nameCol] : ""
            let code = cell(row, "code")
            let sale = number(cell(row, "sale"))
            let rental = number(cell(row, "rental"))
            let weight = number(cell(row, "weight"))
            let unit = cell(row, "unit")
            // A row carrying a single piece of text and no numbers — e.g. a
            // merged "Base Items" row — is a category heading for the rows
            // beneath it (tick-box TRUE/FALSE cells are ignored).
            let texts = Set(row.filter { !$0.isEmpty && $0 != "TRUE" && $0 != "FALSE" })
            if bestMap["category"] == nil, sale == nil, rental == nil, weight == nil, unit.isEmpty,
               texts.count == 1, (code.isEmpty || !code.contains(".")) {
                currentCategory = texts.first
                continue
            }
            if name.isEmpty && code.isEmpty { continue }
            guard !name.isEmpty else { continue }
            let category = bestMap["category"] != nil ? (cell(row, "category").isEmpty ? currentCategory : cell(row, "category")) : currentCategory
            if bestMap["category"] != nil, !cell(row, "category").isEmpty { currentCategory = cell(row, "category") }
            result.append(ParsedPriceRow(code: code.isEmpty ? nil : code, name: name, category: category,
                                         unit: unit.isEmpty ? nil : unit, weightKg: weight, salePrice: sale, rentalPrice: rental))
        }
        return (result, mapping)
    }
}

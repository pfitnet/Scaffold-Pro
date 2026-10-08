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
// MARK: - Automatic iCloud backup
//
// Keeps an up-to-date copy of everything in a shared iCloud Drive folder —
// by default iCloud Drive/Proficiency/William's Work — so the work is off
// this Mac and shared with Proficiency:
//
//   William's Work/        (the copy goes straight in here)
//   ├── Database/          the *.json stores, always current
//   ├── Projects/          project folders (drawings, PDFs, Word copies)
//   ├── Administration/    worker and company documents
//   ├── Configuration/     manifest.json + README — the same layout as a
//   │                      backup, so "Restore from Folder…" can restore it
//   └── Database History/  the database as it was each day (last 30 days)
//
// Only files that changed are copied. It runs about a minute after
// anything is saved, every 15 minutes, and when the app opens. Nothing is
// ever deleted from the iCloud copy, so a mistake in the app can't wipe it.
// Its settings are kept per Mac (UserDefaults), not in the database.
// =====================================================================

struct CloudBackupStatus: Codable {
    var enabled: Bool
    /// The "William's Work" folder, which the copy goes straight into.
    var folder: String
    /// e.g. "iCloud Drive › Proficiency › William's Work"
    var folderDisplay: String
    var usingDefault: Bool
    var lastBackupAt: String?
    var lastFilesCopied: Int?
    var lastError: String?
    var running: Bool
}

/// Settings › Google Sheets: a Google Sheet kept as an overview of who did
/// what, and when — its Activity and Projects tabs — through the Apps
/// Script in resources/google-sheets/ScaffoldPro.gs. About every minute
/// (and soon after anything is saved) this Mac sends the last few days'
/// history and every project, and takes back what was changed in the
/// sheet: a project's status, manager or notes, and lines typed into
/// Activity. It's set up on one Mac (kept in that Mac's settings), so the
/// sheet is kept up to date from one place.
struct GoogleSheetsStatus: Codable {
    var linked: Bool
    var url: String?
    var sheetName: String?
    var sheetURL: String?
    var lastSyncAt: String?
    var lastError: String?
    /// Changes from the sheet taken in at the last sync that had any.
    var lastTakenIn: Int?
    var lastTakenInAt: String?
    /// The layout the sheet's script reports (from its code on GitHub);
    /// nil while the sheet runs a script pasted before it updated itself.
    var sheetLayout: String?
    var running: Bool
}

final class GoogleSheetsSync {
    let db: AppDatabase
    let defaults = UserDefaults.standard
    enum Key {
        static let url = "googleSheets.url"
        static let secret = "googleSheets.secret"
        static let name = "googleSheets.name"
        static let sheetURL = "googleSheets.sheetURL"
        static let lastSync = "googleSheets.lastSync"
        static let lastError = "googleSheets.lastError"
        static let takenIn = "googleSheets.takenIn"
        static let takenInAt = "googleSheets.takenInAt"
        static let layout = "googleSheets.layout"
        /// The first sync sends months of history; later ones a few days.
        static let primed = "googleSheets.primed"
    }
    var timer: Timer?
    var pending: DispatchWorkItem?
    var running = false
    /// After the sheet's changes are taken in (the page shows them).
    var onChangesTakenIn: (() -> Void)?

    init(db: AppDatabase) { self.db = db }

    var isLinked: Bool { defaults.string(forKey: Key.url) != nil && defaults.string(forKey: Key.secret) != nil }

    func status() -> GoogleSheetsStatus {
        let iso: (String) -> String? = { key in
            (self.defaults.object(forKey: key) as? Double).map { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0)) }
        }
        return GoogleSheetsStatus(linked: isLinked, url: defaults.string(forKey: Key.url), sheetName: defaults.string(forKey: Key.name),
                                  sheetURL: defaults.string(forKey: Key.sheetURL), lastSyncAt: iso(Key.lastSync),
                                  lastError: defaults.string(forKey: Key.lastError), lastTakenIn: defaults.object(forKey: Key.takenIn) as? Int,
                                  lastTakenInAt: iso(Key.takenInAt), sheetLayout: defaults.string(forKey: Key.layout), running: running)
    }

    /// Starts syncing (main thread): every minute, and 20 seconds after a save.
    func start() {
        NotificationCenter.default.addObserver(forName: CloudBackupManager.dataSaved, object: nil, queue: .main) { [weak self] _ in
            self?.schedule(after: 20)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.syncNow() }
        schedule(after: 15)
    }

    func schedule(after seconds: TimeInterval) {
        guard isLinked else { return }
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.syncNow() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    /// Checks the Web app URL and secret with the sheet, then keeps them.
    func link(url rawURL: String, secret rawSecret: String, completion: @escaping (SimpleResult) -> Void) {
        let text = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = rawSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text), url.scheme == "https", url.host == "script.google.com" else {
            completion(SimpleResult(ok: false, error: "Paste the Web app URL from the sheet’s Deploy › New deployment — it starts with https://script.google.com/."))
            return
        }
        guard !secret.isEmpty else { completion(SimpleResult(ok: false, error: "Paste the connection secret too (in the sheet: ScaffoldPro › Connection secret).")); return }
        post(to: url, body: ["secret": secret, "action": "ping"]) { [weak self] json, error in
            guard let self = self else { return }
            guard let json = json else { completion(SimpleResult(ok: false, error: error)); return }
            self.defaults.set(text, forKey: Key.url)
            self.defaults.set(secret, forKey: Key.secret)
            self.defaults.set(json["name"] as? String, forKey: Key.name)
            self.defaults.set(json["url"] as? String, forKey: Key.sheetURL)
            self.defaults.removeObject(forKey: Key.primed)
            self.defaults.removeObject(forKey: Key.lastError)
            completion(SimpleResult(ok: true, error: nil))
            self.syncNow(refreshScript: true)
        }
    }

    func unlink() {
        pending?.cancel()
        for key in [Key.url, Key.secret, Key.name, Key.sheetURL, Key.lastSync, Key.lastError, Key.takenIn, Key.takenInAt, Key.primed, Key.layout] {
            defaults.removeObject(forKey: key)
        }
    }

    /// Sends this Mac's history and projects, and takes in the sheet's changes (main thread).
    /// refreshScript: the sheet fetches its newest code from GitHub first
    /// (Sync Now, and connecting), instead of only every 10 minutes.
    func syncNow(refreshScript: Bool = false, completion: ((GoogleSheetsStatus) -> Void)? = nil) {
        guard !running, let secret = defaults.string(forKey: Key.secret),
              let url = defaults.string(forKey: Key.url).flatMap({ URL(string: $0) }) else { completion?(status()); return }
        running = true
        let payload = db.sheetsPayload(days: defaults.bool(forKey: Key.primed) ? 3 : 120)
        post(to: url, body: ["secret": secret, "action": "sync", "activity": payload.activity, "projects": payload.projects,
                             "people": db.sheetsPeopleColours(), "refresh": refreshScript]) { [weak self] json, error in
            guard let self = self else { return }
            self.running = false
            if let json = json {
                let taken = self.db.applySheetChanges((json["changes"] as? [[String: Any]]) ?? [], activity: (json["activity"] as? [[String: Any]]) ?? [])
                let now = Date().timeIntervalSince1970
                self.defaults.set(now, forKey: Key.lastSync)
                self.defaults.set(true, forKey: Key.primed)
                self.defaults.removeObject(forKey: Key.lastError)
                if let name = json["name"] as? String { self.defaults.set(name, forKey: Key.name) }
                if let link = json["url"] as? String { self.defaults.set(link, forKey: Key.sheetURL) }
                self.defaults.set(json["layout"] as? String, forKey: Key.layout)
                if taken > 0 {
                    self.defaults.set(taken, forKey: Key.takenIn)
                    self.defaults.set(now, forKey: Key.takenInAt)
                    self.onChangesTakenIn?()
                }
            } else {
                self.defaults.set(error, forKey: Key.lastError)
            }
            completion?(self.status())
        }
    }

    /// POSTs JSON to the Web app (Google answers through a redirect, which
    /// is followed) → its reply when it says ok, or why not (main thread).
    func post(to url: URL, body: [String: Any], completion: @escaping ([String: Any]?, String?) -> Void) {
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        URLSession.shared.dataTask(with: request) { data, response, error in
            let outcome: ([String: Any]?, String?)
            if let error = error {
                outcome = (nil, "Google Sheets couldn’t be reached (\(error.localizedDescription)).")
            } else if let data = data, let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                outcome = obj["ok"] as? Bool == true ? (obj, nil) : (nil, (obj["error"] as? String) ?? "Google Sheets didn’t accept it.")
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                outcome = (nil, code == 404
                    ? "That Web app wasn’t found — copy the URL again from Deploy › Manage deployments."
                    : "Google Sheets didn’t answer as expected. Check the deployment is a Web app with “Who has access” set to Anyone.")
            }
            DispatchQueue.main.async { completion(outcome.0, outcome.1) }
        }.resume()
    }

    /// The Apps Script to paste into the sheet (bundled with the app).
    static func script() -> String? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("resources/google-sheets/ScaffoldPro.gs") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

// ---- Importing a quotation from a file (an old quotation, a scan) ----

/// A line read off an imported quotation. kind: "Material" (an item; a
/// code in the material list links it), "Delivery" (a delivery or
/// transport charge) or "Other" (another charge, in a section named
/// `section`, e.g. "Design Fees").
struct ImportedQuotationLine: Codable {
    var kind: String? = "Material"
    var section: String? = nil
    var itemCode: String? = nil
    var description: String
    var unit: String
    var quantity: Double
    var unitPrice: Double
    /// Found in the material list by its code.
    var matched: Bool? = nil
}

/// What was read from an imported file, for the person to check before a
/// quotation is made from it.
struct QuotationImportDraft: Codable {
    var ok: Bool
    var error: String? = nil
    /// Names the file kept for this import (`quotations:importCreate`).
    var token: String = ""
    var fileName: String = ""
    /// How it was read: "text" (the file's own text), "ocr" (read off a
    /// scan on this Mac) or "ai".
    var source: String = "text"
    var subject: String? = nil
    var clientRef: String? = nil
    /// The number on the file (e.g. an old Qt26101-002), for reference.
    var oldNumber: String? = nil
    var pricingMode: String = "Rental"
    var currency: String? = nil
    var items: [ImportedQuotationLine] = []
    /// The start of the text read, so the person can see what was read.
    var textPreview: String = ""
    /// An AI is set up (Settings › AI Import).
    var aiReady: Bool = false
    /// Few or no items could be made out: worth asking the AI.
    var unsure: Bool = false
}

enum QuotationImportReader {
    static let imageTypes = ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "bmp", "webp"]

    /// The file's text, and whether it had to be read off images (a scan).
    static func text(of url: URL) -> (text: String, ocr: Bool) {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf", let pdf = PDFDocument(url: url) {
            let own = pdf.string ?? ""
            let pages = max(1, pdf.pageCount)
            // Plenty of text: a PDF made by a program. Little: a scan.
            if own.trimmingCharacters(in: .whitespacesAndNewlines).count >= 60 * pages { return (own, false) }
            var read: [String] = []
            for i in 0..<min(pdf.pageCount, 15) {
                guard let page = pdf.page(at: i), let image = render(page) else { continue }
                read.append(ocr(image))
            }
            let joined = read.joined(separator: "\n")
            return joined.count > own.count ? (joined, true) : (own, false)
        }
        if imageTypes.contains(ext) {
            guard let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return ("", true) }
            return (ocr(cg), true)
        }
        if ["csv", "tsv", "txt"].contains(ext) {
            return ((try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url, encoding: .isoLatin1)) ?? "", false)
        }
        // Word, RTF, web pages: what macOS can open as text.
        if let attributed = try? NSAttributedString(url: url, options: [:], documentAttributes: nil) { return (attributed.string, false) }
        return ("", false)
    }

    /// A PDF page as a picture, about 200 dpi, on white.
    static func render(_ page: PDFPage) -> CGImage? {
        let box = page.bounds(for: .mediaBox)
        guard box.width > 0, box.height > 0 else { return nil }
        let scale = min(2.8, 2200 / max(box.width, box.height))
        let w = Int(box.width * scale), h = Int(box.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: ctx)
        return ctx.makeImage()
    }

    /// The words in a picture (Apple's text recognition, on this Mac), put
    /// back into lines, the columns of a line two spaces apart.
    static func ocr(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        let wanted = ["en-US", "zh-Hant", "zh-Hans"]
        if let supported = try? request.supportedRecognitionLanguages() {
            let langs = wanted.filter { supported.contains($0) }
            if !langs.isEmpty { request.recognitionLanguages = langs }
        }
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try? handler.perform([request])
        let observations = (request.results ?? []).compactMap { obs -> (box: CGRect, text: String)? in
            guard let top = obs.topCandidates(1).first else { return nil }
            return (obs.boundingBox, top.string)
        }
        // Top to bottom; pieces whose middles are level make one line.
        var rows: [[(box: CGRect, text: String)]] = []
        for o in observations.sorted(by: { $0.box.midY > $1.box.midY }) {
            if let last = rows.last, let first = last.first, abs(first.box.midY - o.box.midY) < max(first.box.height, o.box.height) * 0.5 {
                rows[rows.count - 1].append(o)
            } else {
                rows.append([o])
            }
        }
        return rows.map { $0.sorted { $0.box.minX < $1.box.minX }.map { $0.text }.joined(separator: "  ") }.joined(separator: "\n")
    }

    static let units: Set<String> = ["pc", "pcs", "pce", "no", "no.", "nos", "nos.", "set", "sets", "m", "m2", "m²", "m3", "m³", "lm", "lot", "lots",
                                     "kg", "ton", "tons", "tonne", "item", "items", "ea", "each", "day", "days", "week", "weeks", "month", "months",
                                     "mth", "mths", "trip", "trips", "ls", "l.s.", "l/s", "sum", "unit", "units", "nr", "length", "lengths", "load", "loads",
                                     "支", "件", "套", "個", "个", "米", "次", "車", "车", "條", "条", "塊", "块"]

    /// A number as printed: "1,250", "HK$12.50", "$3.00", "@12.5".
    static func number(_ token: String) -> Double? {
        var t = token
        for p in ["HK$", "US$", "S$", "MOP$", "RMB", "$", "@", "¥", "£", "€"] where t.uppercased().hasPrefix(p) { t = String(t.dropFirst(p.count)) }
        t = t.replacingOccurrences(of: ",", with: "")
        guard !t.isEmpty, t.range(of: #"^[0-9]+(\.[0-9]+)?$"#, options: .regularExpression) != nil else { return nil }
        return Double(t)
    }

    /// Reads the items from the text: a line ending in a quantity, a unit
    /// price and an amount that agree (quantity × price ≈ amount), with a
    /// unit word before or between them. Also the "Re:" line, "Your Ref.",
    /// the old number and whether it's for rental or sale.
    static func parse(_ text: String, priceItems: [PriceListItem]) -> QuotationImportDraft {
        var draft = QuotationImportDraft(ok: true)
        let codes = Set(priceItems.map { $0.itemCode.uppercased() })
        var rentalWords = 0, saleWords = 0
        var section: String? = nil
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let lower = line.lowercased()
            rentalWords += ["rental", "hire", "per month", "/month", "monthly"].filter { lower.contains($0) }.count
            saleWords += ["sale", "purchase", "sell"].filter { lower.contains($0) }.count
            if draft.subject == nil, let r = line.range(of: #"^(re|subject)\s*[:：]\s*"#, options: [.regularExpression, .caseInsensitive]) {
                draft.subject = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                continue
            }
            if draft.clientRef == nil, let r = line.range(of: #"your\s*ref(erence)?(\.|\s)*(no\.?)?\s*[:：]\s*"#, options: [.regularExpression, .caseInsensitive]) {
                let rest = String(line[r.upperBound...]).components(separatedBy: "  ").first ?? ""
                if !rest.trimmingCharacters(in: .whitespaces).isEmpty { draft.clientRef = rest.trimmingCharacters(in: .whitespaces) }
            }
            if draft.oldNumber == nil, let r = line.range(of: #"\bQ[Tt][-\s]?\d{4,6}(-\d{1,3})?\b"#, options: .regularExpression) {
                draft.oldNumber = String(line[r])
            }
            if draft.currency == nil {
                if line.contains("US$") || line.contains("USD") { draft.currency = "USD" } else if line.contains("HK$") || line.contains("HKD") { draft.currency = "HKD" }
            }
            var tokens = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            // Numbers at the end: amount, price and quantity (a unit may sit
            // between the quantity and the price, or before the quantity).
            var nums: [Double] = []
            var unit: String? = nil
            while let last = tokens.last, nums.count < 3 {
                if let n = number(last) { nums.insert(n, at: 0); tokens.removeLast(); continue }
                if unit == nil, units.contains(last.lowercased()), !nums.isEmpty, nums.count < 3 { unit = last; tokens.removeLast(); continue }
                break
            }
            if unit == nil, let last = tokens.last, units.contains(last.lowercased()) { unit = last; tokens.removeLast() }
            var item: (q: Double, p: Double)? = nil
            if nums.count == 3, abs(nums[0] * nums[1] - nums[2]) <= max(0.015 * nums[2], 0.6), nums[0] > 0 { item = (nums[0], nums[1]) }
            else if nums.count >= 2, unit != nil, nums[nums.count - 2] > 0 { item = (nums[nums.count - 2], nums[nums.count - 1]) }
            guard let found = item else {
                // A short line with no numbers, in capitals or ending in a
                // colon, between items: a section heading.
                if nums.isEmpty, line.count < 60, line.rangeOfCharacter(from: .letters) != nil,
                   line == line.uppercased() || line.hasSuffix(":") { section = line.trimmingCharacters(in: CharacterSet(charactersIn: ": ")) }
                continue
            }
            // A row label first ("A1", "1.", "(3)"), then perhaps a code.
            if let first = tokens.first, first.range(of: #"^\(?[A-Za-z]?\d{1,3}[.)]?$"#, options: .regularExpression) != nil, tokens.count > 1 { tokens.removeFirst() }
            var code: String? = nil
            if let first = tokens.first, codes.contains(first.uppercased()) || first.range(of: #"^[A-Z]{0,3}\d{4,}[A-Z0-9-]*$"#, options: .regularExpression) != nil, tokens.count > 1 {
                code = first
                tokens.removeFirst()
            }
            let description = tokens.joined(separator: " ").trimmingCharacters(in: CharacterSet(charactersIn: " -–:|"))
            let dl = description.lowercased()
            guard description.rangeOfCharacter(from: .letters) != nil,
                  !["total", "subtotal", "sub-total", "discount", "deposit", "balance", "amount due"].contains(where: { dl.hasPrefix($0) || dl == $0 }) else { continue }
            var kind = "Material"
            if ["delivery", "transport", "collection", "lorry", "truck", "運輸", "运输", "送貨"].contains(where: { dl.contains($0) }) { kind = "Delivery" }
            else if let s = section?.lowercased(), code == nil,
                    ["fee", "labour", "labor", "manpower", "erect", "dismantl", "design", "engineer", "inspection", "insurance", "other", "人工", "設計", "设计", "搭", "拆"].contains(where: { s.contains($0) }) { kind = "Other" }
            draft.items.append(ImportedQuotationLine(kind: kind, section: kind == "Other" ? section : nil, itemCode: code, description: description,
                                                     unit: unit ?? "pc", quantity: found.q, unitPrice: found.p,
                                                     matched: code.map { codes.contains($0.uppercased()) } ?? false))
        }
        draft.pricingMode = saleWords > rentalWords ? "Sale" : "Rental"
        return draft
    }

    /// Turns the AI's JSON answer into a draft.
    static func draft(fromAI json: [String: Any], priceItems: [PriceListItem]) -> QuotationImportDraft {
        var draft = QuotationImportDraft(ok: true)
        let codes = Set(priceItems.map { $0.itemCode.uppercased() })
        let str: (Any?) -> String? = { v in (v as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0.trimmingCharacters(in: .whitespacesAndNewlines) } }
        let num: (Any?) -> Double? = { v in
            if let d = v as? Double { return d }
            if let i = v as? Int { return Double(i) }
            if let s = v as? String { return number(s.trimmingCharacters(in: .whitespaces)) }
            return nil
        }
        draft.subject = str(json["subject"])
        draft.clientRef = str(json["clientRef"])
        draft.oldNumber = str(json["quotationNumber"])
        draft.pricingMode = str(json["pricingMode"])?.lowercased() == "sale" ? "Sale" : "Rental"
        draft.currency = str(json["currency"])?.uppercased()
        for case let row as [String: Any] in (json["items"] as? [Any]) ?? [] {
            guard let description = str(row["description"]) else { continue }
            let kind = ["Material", "Delivery", "Other"].first { $0.lowercased() == (str(row["kind"]) ?? "").lowercased() } ?? "Material"
            let code = str(row["itemCode"])
            draft.items.append(ImportedQuotationLine(kind: kind, section: kind == "Other" ? str(row["section"]) : nil, itemCode: code,
                                                     description: description, unit: str(row["unit"]) ?? "pc",
                                                     quantity: max(1, num(row["quantity"]) ?? 1), unitPrice: max(0, num(row["unitPrice"]) ?? 0),
                                                     matched: code.map { codes.contains($0.uppercased()) } ?? false))
        }
        return draft
    }
}

/// Reading a quotation the app can't make out on its own (a scan, an odd
/// layout) with a free cloud AI: Google's Gemini (free tier, reads PDFs and
/// pictures itself) or OpenRouter's free models (sent the text read on this
/// Mac). The key is kept in this Mac's Keychain; nothing is sent until a
/// key is set and the person imports a file.
final class QuotationAI {
    static let shared = QuotationAI()
    let defaults = UserDefaults.standard
    enum Key {
        static let provider = "ai.provider"
        static let model = "ai.model"
    }
    static let providers = ["gemini": "Google Gemini (free tier)", "openrouter": "OpenRouter (free models)"]
    static let defaultModels = ["gemini": "gemini-2.5-flash", "openrouter": "openrouter/free"]

    /// The team's settings, where the connection is kept (set at launch).
    weak var db: AppDatabase?
    var company: CompanySettings? { db?.getCompanySettings() }

    var provider: String { nonBlank(company?.aiProvider) ?? "gemini" }
    var model: String { nonBlank(company?.aiModel) ?? QuotationAI.defaultModels[provider] ?? "" }
    var ready: Bool { sharedKey != nil }
    var sharedKey: String? { nonBlank(company?.aiKey) }

    struct Status: Codable {
        var provider: String
        var model: String
        var defaultModel: String
        var hasKey: Bool
    }
    func status() -> Status {
        adoptThisMacsKey()
        return Status(provider: provider, model: nonBlank(company?.aiModel) ?? "", defaultModel: QuotationAI.defaultModels[provider] ?? "", hasKey: ready)
    }

    /// Saves the connection for the whole team while none is set;
    /// `removeKey` removes it (for everyone).
    func configure(provider: String, model: String?, key: String?, removeKey: Bool) {
        guard let db = db else { return }
        adoptThisMacsKey()
        if removeKey {
            db.setAIConnection(provider: company?.aiProvider, model: company?.aiModel, key: nil)
            return
        }
        // A key in use: no new key, provider or model until it's removed.
        if ready { return }
        let p = QuotationAI.providers[provider] == nil ? "gemini" : provider
        db.setAIConnection(provider: p, model: nonBlank(model), key: nonBlank(key))
    }

    /// Before the connection was the team's, each Mac kept its own key in
    /// its Keychain: the first one found becomes the team's, and leaves
    /// the Keychain.
    func adoptThisMacsKey() {
        guard let db = db, sharedKey == nil else { return }
        let localProvider = defaults.string(forKey: Key.provider) ?? "gemini"
        for p in [localProvider] + QuotationAI.providers.keys.filter({ $0 != localProvider }) {
            guard let k = keychainKey(for: p) else { continue }
            db.setAIConnection(provider: p, model: p == localProvider ? nonBlank(defaults.string(forKey: Key.model)) : nil, key: k)
            break
        }
        for p in QuotationAI.providers.keys { _ = SecItemDelete(query(p) as CFDictionary) }
        defaults.removeObject(forKey: Key.provider)
        defaults.removeObject(forKey: Key.model)
    }

    // ---- The old per-Mac Keychain keys (read once, then removed) ----
    func query(_ provider: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "ScaffoldPro AI", kSecAttrAccount as String: provider]
    }
    func keychainKey(for provider: String) -> String? {
        var q = query(provider)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return nonBlank(String(data: data, encoding: .utf8))
    }

    static let prompt = """
    You read construction (scaffolding) quotations and return their contents as JSON for a program. \
    Read the attached quotation (it may be a scan, a photo or an old template) and answer with ONLY a JSON object, no other text:
    {"subject": the "Re:" line or title, or null,
     "clientRef": the client's "Your Ref." or null,
     "quotationNumber": the quotation's own number or null,
     "pricingMode": "Rental" if items are hired per month, else "Sale",
     "currency": ISO code such as "HKD" or "USD",
     "items": [{"kind": "Material" for a material or item, "Delivery" for a delivery/transport/collection charge, "Other" for anything else charged (labour, design fees, erection…),
                "section": the heading it is under (for "Other"), or null,
                "itemCode": the item's code if printed, or null,
                "description": the item's description as printed (English, and Chinese if printed),
                "unit": e.g. "pc", "set", "m", "trip",
                "quantity": number,
                "unitPrice": number (the price for one unit, per month for rental; no currency signs or commas)}]}
    Rules: one entry per priced row, in order. Leave out totals, subtotals, discounts, deposits and terms. \
    Do not invent rows or prices; if a quantity is not printed use 1. Numbers must be plain JSON numbers.
    """

    /// Reads the file (or its text) → the JSON answer, or why not (main thread).
    func read(fileURL: URL, text: String, completion: @escaping ([String: Any]?, String?) -> Void) {
        adoptThisMacsKey()
        guard let key = sharedKey else { completion(nil, "No AI is set up. Add a free key in Settings › AI Import."); return }
        let ext = fileURL.pathExtension.lowercased()
        let mime: String? = ext == "pdf" ? "application/pdf" : ext == "png" ? "image/png" : ["jpg", "jpeg"].contains(ext) ? "image/jpeg"
            : ext == "webp" ? "image/webp" : ["heic"].contains(ext) ? "image/heic" : nil
        let fileData = mime != nil ? (try? Data(contentsOf: fileURL)).flatMap { $0.count <= 15_000_000 ? $0 : nil } : nil
        let clipped = String(text.prefix(60_000))
        var request: URLRequest
        if provider == "openrouter" {
            request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!, timeoutInterval: 150)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("ScaffoldPro", forHTTPHeaderField: "X-Title")
            let read = clipped.isEmpty ? "(no text could be read — see the picture)" : clipped
            var content: [[String: Any]] = [["type": "text", "text": "The quotation's text, as read:\n\n" + read]]
            if let data = fileData, let mime = mime, mime.hasPrefix("image/") {
                let image: [String: Any] = ["url": "data:\(mime);base64,\(data.base64EncodedString())"]
                content.append(["type": "image_url", "image_url": image])
            }
            let messages: [[String: Any]] = [["role": "system", "content": QuotationAI.prompt], ["role": "user", "content": content]]
            let body: [String: Any] = ["model": model, "temperature": 0, "messages": messages]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else {
            let name = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "gemini-2.5-flash"
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(name):generateContent")!, timeoutInterval: 150)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            var parts: [[String: Any]] = [["text": QuotationAI.prompt]]
            if let data = fileData, let mime = mime {
                let inline: [String: Any] = ["mime_type": mime, "data": data.base64EncodedString()]
                parts.append(["inline_data": inline])
            } else {
                parts.append(["text": "The quotation's text:\n\n" + clipped])
            }
            let contents: [[String: Any]] = [["role": "user", "parts": parts]]
            let config: [String: Any] = ["temperature": 0, "responseMimeType": "application/json"]
            let body: [String: Any] = ["contents": contents, "generationConfig": config]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let isGemini = provider != "openrouter"
        URLSession.shared.dataTask(with: request) { data, response, error in
            var result: ([String: Any]?, String?) = (nil, nil)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let obj = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            if let error = error {
                result = (nil, "The AI couldn’t be reached (\(error.localizedDescription)).")
            } else if code == 401 || code == 403 || (code == 400 && "\(obj ?? [:])".contains("API_KEY")) {
                result = (nil, "The AI didn’t accept the key. Check it in Settings › AI Import.")
            } else if code == 429 {
                result = (nil, "The free allowance is used up for the moment. Try again in a minute.")
            } else if code >= 400 || obj == nil {
                let message = ((obj?["error"] as? [String: Any])?["message"] as? String) ?? "it answered with an error (\(code))"
                result = (nil, "The AI couldn’t read it: \(message).")
            } else {
                var answer = ""
                if isGemini {
                    let parts = (((obj?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
                    answer = parts.compactMap { $0["text"] as? String }.joined()
                } else {
                    answer = ((((obj?["choices"] as? [[String: Any]])?.first)?["message"] as? [String: Any])?["content"] as? String) ?? ""
                }
                // Just the JSON, even if it came in a code fence.
                if let start = answer.firstIndex(of: "{"), let end = answer.lastIndex(of: "}"), start < end,
                   let json = (try? JSONSerialization.jsonObject(with: Data(answer[start...end].utf8))) as? [String: Any] {
                    result = (json, nil)
                } else {
                    result = (nil, "The AI’s answer couldn’t be understood. Try again, or add the items by hand.")
                }
            }
            DispatchQueue.main.async { completion(result.0, result.1) }
        }.resume()
    }
}

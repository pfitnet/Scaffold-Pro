import Cocoa
import WebKit
import UniformTypeIdentifiers
import CoreGraphics
import CoreText
import PDFKit

// =====================================================================
// MARK: - Models
//
// Ported from the (tested) Electron version's src/db.js. Field names
// match the JSON shape the renderer's page scripts (dashboard.js,
// clients.js, sites.js, projects.js, project-detail.js, price-lists.js)
// already expect, so those files are unchanged from the Electron build.
// =====================================================================

struct Client: Codable {
    var id: String
    var companyName: String
    var contactPerson: String?
    var address: String?
    var phone: String?
    var email: String?
    var notes: String?
    var isArchived: Bool
    var createdAt: String
    // Section 10's fuller client record — optional so older data loads.
    var clientReference: String?
    var city: String?
    var postalCode: String?
    var country: String?
    var vatNumber: String?
    var billingInfo: String?
    /// `address` is line 1; these are the address's further lines.
    var addressLine2: String? = nil
    var addressLine3: String? = nil
    /// The markup % new BOQs and quotations for this client start with
    /// (a BOQ's mark-up then carries on to its quotation). nil = none.
    var defaultMarkupPercent: Double? = nil
}

struct Site: Codable {
    var id: String
    var name: String
    var address: String?
    var contactPerson: String?
    var phone: String?
    var notes: String?
    var isArchived: Bool
    var createdAt: String
    // Section 9's fuller site record — optional so older data loads.
    var siteReference: String?
    var city: String?
    var postalCode: String?
    var country: String?
    var email: String?
}

/// One formal document in a list — used by client/site pages, the
/// Dashboard and global search.
struct DocRow: Codable {
    var id: String
    /// "BOQ", "Quotation", "Invoice" or "Delivery Note"
    var kind: String
    var number: String
    var status: String
    var projectNumber: String
    var projectName: String
    var clientName: String?
    var date: String
    var updatedAt: String
    var amount: Double?
    var balance: Double?
    var dueDate: String?
    var isOverdue: Bool
    var url: String
    /// Quotations: monthly / one-time split (see ChargeSplit).
    var charges: ChargeSplit? = nil
}

struct PartyDetail: Codable {
    var projects: [ProjectListEntry]
    var documents: [DocRow]
}

struct DashboardSummary: Codable {
    var activeProjects: Int
    var totalProjects: Int
    var clientCount: Int
    var priceListItemCount: Int
    var currency: String
    var outstandingQuotations: [DocRow]
    var unpaidInvoices: [DocRow]
    var unpaidTotal: Double
    var overdueCount: Int
    var overdueTotal: Double
    var recentDeliveryNotes: [DocRow]
    var recentDocuments: [DocRow]
    var recentActivity: [ActivityRow]
    /// Issued quotations with no signed copy from the client yet (newest
    /// first; "Invoiced" ones — already going ahead — first of all).
    var awaitingSignedCopy: [DocRow] = []
    var awaitingSignedCopyCount = 0
}

struct SearchResult: Codable {
    var kind: String
    var title: String
    var subtitle: String
    var url: String
}

struct SimpleResult: Codable {
    var ok: Bool
    var error: String?
}

struct Project: Codable {
    var id: String
    var projectNumber: String
    var name: String
    var clientId: String
    var siteId: String
    var projectDescription: String?
    var startDate: String?
    var expectedCompletionDate: String?
    var projectManager: String?
    var internalNotes: String?
    var status: String
    var createdAt: String
}

struct PriceList: Codable {
    var id: String
    var sourceKey: String
    var displayName: String
    var currency: String
    var createdAt: String
}

struct PriceListItem: Codable {
    var id: String
    var sourceKey: String
    var itemCode: String
    var category: String?
    var itemName: String
    var unit: String
    var weightKg: Double?
    var unitSalePrice: Double?
    var unitRentalPrice: Double?
    var applicableTypes: [String]
    var notes: String?
    var isArchived: Bool
    /// Its place in its category, as dragged in the Material List. nil =
    /// never moved (then it follows the moved ones, by item code).
    var sortOrder: Int? = nil
    /// Pinned: shown first, in a "Pinned" box, when picking items for a
    /// document. Kept with the material list, so every Mac sees it.
    var isPinned: Bool? = nil
    /// The name in Chinese, for workers who read Chinese (shown with the
    /// English name on delivery notes and BOQs). "" = deliberately none.
    var chineseName: String? = nil
}

/// The Chinese name for a material, from the words used on the official SP
/// Material List (e.g. "2.07m Ledger" → "2.07m橫杆", "0.90m x 1.0m Face
/// Brace" → "0.90m x 1.0m斜杆"). nil when it isn't a material it knows.
func chineseMaterialName(_ english: String) -> String? {
    let name = english.trimmingCharacters(in: .whitespacesAndNewlines)
        .split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    guard !name.isEmpty else { return nil }
    let exact: [String: String] = [
        "600mm base jack": "600mm 短底座",
        "60mm u jack": "頂積",
        "600mm u jack": "600mm 頂積",
        "base jack (with wheels)": "底座(帶轆)",
        "angle turning steel deck": "轉角板",
        "turning steel deck": "轉彎板",
        "twin ledger end coupler": "雙尖扣/雙接手扣",
        "tube connector with semi coupler": "駁芯手扣",
        "0.36m triangular rack": "360三角架",
        "732 bracket": "732 三角架",
        "lattice gridder coupler": "桁條扣",
        "lattice girder coupler": "桁條扣",
        "spigot clamp": "駁芯夾",
        "spigot": "駁芯",
        "round spigot": "圓形駁心",
        "ra coupler": "直角手扣",
        "right angle coupler": "直角手扣 (死扣)",
        "swivel coupler": "活動手扣 (生扣)",
        "swivel bolt coupler": "活動手扣",
        "ledger end to ra tube coupler": "橫杆頭直角手扣",
        "ledger end to swivel tube coupler": "橫杆頭活動手扣",
        "sole board": "木墊板",
        "wood sole board": "木墊板",
        "l bolt": "L 曲",
    ]
    if let hit = exact[name.lowercased()] { return hit }
    let size = #"(\d+(?:\.\d+)?\s?(?:mm|m)?)"#
    let rules: [(String, String)] = [
        ("^\(size) standard with double[- ]bolted spigot$", "$1企柱(雙螺栓駁芯)"),
        ("^\(size) standard with spigot$", "$1企柱(帶駁芯)"),
        ("^\(size) standard without spigot$", "$1企柱(無駁芯)"),
        ("^\(size) standard$", "$1企柱"),
        ("^\(size) rei?nforced ledger$", "$1加固橫杆"),
        ("^\(size) double ledger$", "$1雙橫杆"),
        ("^\(size) ledger$", "$1橫杆"),
        ("^\(size) ?x ?\(size) face brace$", "$1 x $2斜杆"),
        ("^\(size) ?x ?0\\.32m steel deck$", "$1踏板"),
        ("^\(size) ?x ?0\\.16m steel deck$", "$1窄踏板 (160)"),
        ("^\(size) ?x ?0\\.19m steel deck$", "$1窄踏板 (190)"),
        ("^\(size) steel deck$", "$1踏板"),
        ("^\(size) triangular steel deck$", "$1三角板"),
        ("^\(size) wood toe board$", "$1木踢腳板"),
        ("^\(size) (?:steel )?toe board$", "$1踢腳板"),
        ("^\(size) ?x ?\(size) alu(?:minium)? ?\\+ ?wood flip board \\(with ladder\\)$", "$1 x $2 鋁木揭蓋板(連梯)"),
        ("^\(size) flip board$", "$1揭蓋板"),
        ("^\(size) alumin\\w* stai?r?case$", "$1鋁樓梯"),
        ("^\(size) ?x ?\(size) assistant stai?r?case$", "$1 x $2輔助梯"),
        ("^\(size) iron diagonal stai?r?case$", "$1鐵斜梯"),
        ("^\(size) diagonal stai?r?case$", "$1 斜梯"),
        ("^\(size) cat ladder$", "$1掛梯"),
        ("^\(size) outer guard rail$", "$1外扶手"),
        ("^\(size) inner guard rail \\(extended\\)$", "$1內扶手(加長)"),
        ("^\(size) inner guard rail$", "$1內扶手"),
        ("^\(size) (?:bracket|triangular rack)$", "$1三角架"),
        ("^\(size) anchor tube$", "$1扣牆通"),
        ("^\(size) lattice (?:gri?dd?er|girder) w/ middle spigot$", "$1桁條(帶中駁芯)"),
        ("^\(size) lattice (?:gri?dd?er|girder)$", "$1桁條"),
        ("^\(size) base jack$", "$1 底座"),
        ("^\(size) u jack$", "$1 頂積"),
        ("^\(size) base collar$", "$1腳套"),
        ("^\(size) tube$", "$1喉通"),
    ]
    let range = NSRange(name.startIndex..., in: name)
    for (pattern, template) in rules {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              regex.firstMatch(in: name, range: range) != nil else { continue }
        return regex.stringByReplacingMatches(in: name, range: range, withTemplate: template)
    }
    return nil
}

/// "2.07m Ledger" with its Chinese name → "2.07m Ledger  橫杆": the size
/// isn't said twice when the Chinese name starts with it.
func withChineseName(_ description: String, _ chinese: String?) -> String {
    guard let zh = chinese?.trimmingCharacters(in: .whitespacesAndNewlines), !zh.isEmpty,
          !description.contains(zh) else { return description }
    // The part before the first Chinese character, e.g. "0.90m x 1.0m".
    let lead = String(zh.prefix { $0.isASCII }).trimmingCharacters(in: .whitespaces)
    var shown = zh
    if lead.contains(where: { $0.isNumber }), description.lowercased().hasPrefix(lead.lowercased()), lead.count < zh.count {
        shown = String(zh.dropFirst(zh.prefix { $0.isASCII }.count)).trimmingCharacters(in: .whitespaces)
    }
    return "\(description)  \(shown)"
}

struct PriceListItemActionResult: Codable {
    var ok: Bool
    var error: String?
}

/// Shape of the bundled resources/*.json (pre-parsed from the client's
/// real Excel workbook — see the JSON files themselves for the data).
struct SeedPriceItem: Codable {
    var itemCode: String
    var category: String?
    var name: String
    var weightKg: Double?
    var unitSalePriceHKD: Double?
    var unitRentalPriceHKD: Double?
    var spProductNo: String?
    var applicableTypes: [String]
    var source: String
}

struct ProjectListEntry: Codable {
    var id: String
    var projectNumber: String
    var name: String
    var clientId: String
    var siteId: String
    var status: String
    var createdAt: String
    var clientName: String?
    var siteName: String?
}

struct ProjectDetail: Codable {
    var id: String
    var projectNumber: String
    var name: String
    var status: String
    var projectDescription: String?
    var startDate: String?
    var expectedCompletionDate: String?
    var projectManager: String?
    var internalNotes: String?
    var createdAt: String
    var client: Client?
    var site: Site?
}

struct ProjectCreateResult: Codable {
    var ok: Bool
    var error: String?
    var project: Project?
    var folder: String?
}

struct UploadDrawingResult: Codable {
    var originalName: String
    var destination: String
}

/// A document made by combining several (its id, to open it).
struct CombinedDocumentResult: Codable {
    var ok: Bool
    var error: String?
    var id: String?
}

struct DroppedFilesResult: Codable {
    var ok: Bool
    var added: Int
    var error: String?
}

// ---- Drawings & Documents (Phase 11) ----

/// Metadata section 14 asks the app to keep alongside every uploaded
/// drawing — the file itself lives in the project's Drawings/ folder
/// (copied there, never moved from its original location).
struct ProjectDrawing: Codable {
    var id: String
    var projectId: String
    var originalName: String
    var storedFilename: String
    var filePath: String
    var fileType: String
    var fileSizeBytes: Int
    var description: String?
    var isArchived: Bool
    var uploadedAt: String
    /// The BOQ or quotation this drawing belongs to: "BOQ" or "Quotation",
    /// and that document's id. nil = not linked (e.g. uploaded with the
    /// project, before any BOQ existed).
    var linkedKind: String? = nil
    var linkedId: String? = nil
}

struct ProjectDrawingSummary: Codable {
    var id: String
    var originalName: String
    var storedFilename: String
    var fileType: String
    var fileSizeBytes: Int
    var description: String?
    var uploadedAt: String
    /// Section 38: if this comes back false, the UI shows "File
    /// unavailable" plus Locate/Remove-Reference instead of Open/Reveal.
    var fileExists: Bool
    var linkedKind: String?
    var linkedId: String?
    /// e.g. "26017-BOQ-001" or "Qt26193".
    var linkedNumber: String?
    /// In a quotation's list: the BOQ it comes from (drawings of the BOQ
    /// the quotation follows are the quotation's too).
    var fromBOQNumber: String? = nil
    /// Image or PDF: added after the document's own pages in its PDF.
    var appended: Bool = false
    /// Set on the row for the BOQ itself, which a quotation that follows
    /// it carries as its first drawing (built fresh as a PDF).
    var boqId: String? = nil
}

/// Drawing files: PDF and images, plus AutoCAD DWG / DXF.
let drawingContentTypes: [UTType] = {
    var types: [UTType] = [.pdf, .png, .jpeg, .tiff]
    types += ["dwg", "dxf"].compactMap { UTType(filenameExtension: $0) }
    return types
}()

/// Same idea as ProjectDrawing but for general project paperwork
/// (section 34): contracts, specs, correspondence, certificates, etc.
struct ProjectDocument: Codable {
    var id: String
    var projectId: String
    var originalName: String
    var storedFilename: String
    var filePath: String
    var category: String
    var fileType: String
    var fileSizeBytes: Int
    var description: String?
    var isArchived: Bool
    var uploadedAt: String
}

struct ProjectDocumentSummary: Codable {
    var id: String
    var originalName: String
    var storedFilename: String
    var category: String
    var fileType: String
    var fileSizeBytes: Int
    var description: String?
    var uploadedAt: String
    var fileExists: Bool
}

let documentCategories = ["Contracts", "Specifications", "Correspondence", "Certificates", "Client Documents", "Site Information", "Miscellaneous"]

struct FileActionResult: Codable {
    var ok: Bool
    var error: String?
}

// ---- Workers & worker documents (Phase 12 — sections 41-42) ----

struct Worker: Codable {
    var id: String
    /// "W001", "W002", ... — also the name of this worker's folder
    /// under Administration/Workers/ (section 35).
    var workerNumber: String
    var name: String
    var position: String?
    var phone: String?
    var email: String?
    var startDate: String?
    var endDate: String?
    var notes: String?
    var isArchived: Bool
    var createdAt: String
}

struct WorkerError: Error {
    let message: String
}

struct WorkerActionResult: Codable {
    var ok: Bool
    var error: String?
    var worker: Worker?
}

/// One row in the "expiring soon" reminder list (sections 42-43),
/// shown on the Admin page and the Dashboard.
struct ExpiringDocument: Codable {
    var id: String
    /// "Worker" or "Company"
    var kind: String
    var ownerName: String
    var originalName: String
    var category: String
    var expiryDate: String
    /// Negative means already expired.
    var daysLeft: Int
}

let workerDocumentCategories = ["Employment Contract", "Certification", "Training Certificate", "Identification", "Other"]

struct WorkerDocument: Codable {
    var id: String
    var workerId: String
    var originalName: String
    var storedFilename: String
    var filePath: String
    var category: String
    var fileType: String
    var fileSizeBytes: Int
    var description: String?
    /// Section 42: "where documents have expiry dates, provide useful
    /// reminders" — the list view flags anything expired or expiring
    /// within 30 days.
    var expiryDate: String?
    var isArchived: Bool
    var uploadedAt: String
}

struct WorkerDocumentSummary: Codable {
    var id: String
    var originalName: String
    var storedFilename: String
    var category: String
    var fileType: String
    var fileSizeBytes: Int
    var description: String?
    var expiryDate: String?
    var uploadedAt: String
    var fileExists: Bool
}

// ---- General administrative documents (Phase 12 — section 43) ----

let adminDocumentCategories = ["Contracts", "Insurance", "Licenses", "Certificates", "Company Documents", "Other"]

struct AdminDocument: Codable {
    var id: String
    var originalName: String
    var storedFilename: String
    var filePath: String
    var category: String
    var fileType: String
    var fileSizeBytes: Int
    var description: String?
    var expiryDate: String?
    var isArchived: Bool
    var uploadedAt: String
}

struct AdminDocumentSummary: Codable {
    var id: String
    var originalName: String
    var storedFilename: String
    var category: String
    var fileType: String
    var fileSizeBytes: Int
    var description: String?
    var expiryDate: String?
    var uploadedAt: String
    var fileExists: Bool
}

// ---- File-path records (used by Restore to re-point files) ----

/// Every record that remembers where a file lives on disk. Restore uses
/// this to re-point all of them at once if the backup came from a
/// different Mac or user account (different home folder path).
protocol HasFilePath {
    var filePath: String { get set }
}
extension ProjectDrawing: HasFilePath {}
extension ProjectDocument: HasFilePath {}
extension WorkerDocument: HasFilePath {}
extension AdminDocument: HasFilePath {}

// ---- Backup & Restore (Phase 14 — section 39) ----

/// Written to Configuration/manifest.json inside every backup; its
/// presence is how Restore recognises a genuine ScaffoldPro backup.
struct BackupManifest: Codable {
    var app: String
    var formatVersion: Int
    var createdAt: String
    /// "Manual", "Scheduled" (made by itself at 12:00 a.m. / p.m.) or
    /// "Before Restore"
    var kind: String
    /// ~/Documents/ScaffoldPro at the time of backup — used to re-point
    /// file paths if restored somewhere else.
    var sourceAppRoot: String
    var projectCount: Int
    var fileCount: Int
    var totalBytes: Int64
}

struct BackupSummary: Codable {
    var name: String
    var path: String
    var createdAt: String
    var kind: String
    var projectCount: Int
    var fileCount: Int
    var totalBytes: Int64
}

struct BackupResult: Codable {
    var ok: Bool
    var error: String?
    var backup: BackupSummary?
    /// For a restore: the automatic safety backup taken just before.
    var safetyBackup: BackupSummary?
}

struct DataLocations: Codable {
    var documentsFolder: String
    var backupsFolder: String
    var databaseFolder: String
}

struct BackupError: Error {
    let message: String
}

// ---- Activity history (Phase 15 — section 45) ----

struct ActivityEntry: Codable {
    var id: String
    /// nil for company-wide events (e.g. a backup).
    var projectId: String?
    var action: String
    var reference: String?
    var createdAt: String
    /// Who did it, when several people share the data (TeamSync).
    var by: String? = nil
}

/// What the History list and Dashboard show — the entry plus its
/// project's number/name for display.
struct ActivityRow: Codable {
    var id: String
    var projectNumber: String?
    var projectName: String?
    var action: String
    var reference: String?
    var createdAt: String
    var by: String? = nil
}

// ---- Backward-compatible decoding ----

/// Quotations saved before the Sale/Rental option existed have no
/// pricingMode; they load as "Rental" instead of failing to load.
extension Quotation {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        projectId = try c.decode(String.self, forKey: .projectId)
        sourceBOQId = try c.decodeIfPresent(String.self, forKey: .sourceBOQId)
        quotationNumber = try c.decode(String.self, forKey: .quotationNumber)
        status = try c.decode(String.self, forKey: .status)
        quotationDate = try c.decode(String.self, forKey: .quotationDate)
        pricingMode = try c.decodeIfPresent(String.self, forKey: .pricingMode) ?? "Rental"
        validUntil = try c.decodeIfPresent(String.self, forKey: .validUntil)
        paymentTerms = try c.decodeIfPresent(String.self, forKey: .paymentTerms)
        discountType = try c.decodeIfPresent(String.self, forKey: .discountType) ?? "None"
        discountValue = try c.decodeIfPresent(Double.self, forKey: .discountValue) ?? 0
        taxRatePercent = try c.decodeIfPresent(Double.self, forKey: .taxRatePercent) ?? 0
        notes = try c.decodeIfPresent(String.self, forKey: .notes)
        createdAt = try c.decode(String.self, forKey: .createdAt)
        updatedAt = try c.decode(String.self, forKey: .updatedAt)
        subject = try c.decodeIfPresent(String.self, forKey: .subject)
        clientRef = try c.decodeIfPresent(String.self, forKey: .clientRef)
        siteRef = try c.decodeIfPresent(String.self, forKey: .siteRef)
        deliveryMethod = try c.decodeIfPresent(String.self, forKey: .deliveryMethod)
        minimumHireMonths = try c.decodeIfPresent(Int.self, forKey: .minimumHireMonths)
        minimumHireEnabled = try c.decodeIfPresent(Bool.self, forKey: .minimumHireEnabled)
        minimumMonthlyChargeEnabled = try c.decodeIfPresent(Bool.self, forKey: .minimumMonthlyChargeEnabled)
        markupPercent = try c.decodeIfPresent(Double.self, forKey: .markupPercent)
        keyTerms = try c.decodeIfPresent(String.self, forKey: .keyTerms)
        pdfPath = try c.decodeIfPresent(String.self, forKey: .pdfPath)
        signedCopyPath = try c.decodeIfPresent(String.self, forKey: .signedCopyPath)
        signedCopyAt = try c.decodeIfPresent(String.self, forKey: .signedCopyAt)
        signedCopyNotNeeded = try c.decodeIfPresent(Bool.self, forKey: .signedCopyNotNeeded)
    }
}

// ---- Exact money maths (section 50) ----
//
// Every money total is calculated with Decimal and rounded to whole
// cents — never by adding up binary floating-point numbers — so totals
// are always exactly right to the cent. Values are only converted back
// to Double at the very end, for sending to the screen/PDF.

func decimalOf(_ value: Double) -> Decimal {
    Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX")) ?? Decimal(value)
}

func roundToCents(_ value: Decimal) -> Decimal {
    var input = value
    var result = Decimal()
    NSDecimalRound(&result, &input, 2, .plain)
    return result
}

func doubleOf(_ value: Decimal) -> Double {
    NSDecimalNumber(decimal: value).doubleValue
}

/// quantity × unit price, rounded to the cent.
func lineAmount(quantity: Double, unitPrice: Double) -> Decimal {
    roundToCents(decimalOf(quantity.rounded()) * decimalOf(unitPrice))
}

/// The discount on one line: a percentage of the line total, or an
/// amount off it — never more than the line total itself.
func lineDiscount(quantity: Double, unitPrice: Double, discountType: String?, discountValue: Double?) -> Decimal {
    let gross = lineAmount(quantity: quantity, unitPrice: unitPrice)
    let value = decimalOf(max(0, discountValue ?? 0))
    let discount: Decimal
    switch discountType {
    case "Percent": discount = roundToCents(gross * min(value, 100) / 100)
    case "Amount": discount = roundToCents(value)
    default: discount = 0
    }
    return min(discount, max(gross, 0))
}

/// quantity × unit price, less the line's own discount, to the cent.
func netLineAmount(quantity: Double, unitPrice: Double, discountType: String?, discountValue: Double?) -> Decimal {
    lineAmount(quantity: quantity, unitPrice: unitPrice) - lineDiscount(quantity: quantity, unitPrice: unitPrice, discountType: discountType, discountValue: discountValue)
}

/// "Less 10% discount" / "Less HK$ 20.00 discount" — printed under the
/// item's description on quotations and invoices.
func lineDiscountNote(discountType: String?, discountValue: Double?, currencySymbol: String) -> String? {
    guard let value = discountValue, value > 0 else { return nil }
    switch discountType {
    case "Percent": return "Less \(formatMoney(value).replacingOccurrences(of: ".00", with: ""))% discount"
    case "Amount": return "Less \(currencySymbol) \(formatMoney(value)) discount"
    default: return nil
    }
}

/// A unit price with a markup (or, below 0, a mark-down) applied, rounded
/// off to the nearest 0.1 (5.50 +30% → 7.20) or, with `roundUp`, up to the
/// next 0.1 (4.20 +15% = 4.83 → 4.90). Unchanged when there's no markup.
func markedUpPrice(_ price: Double, markupPercent: Double?, roundUp: Bool = false) -> Double {
    guard let markup = markupPercent, markup != 0, markup > -100 else { return price }
    var value = roundToCents(decimalOf(price) * (1 + decimalOf(markup) / 100))
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 1, roundUp ? .up : .plain)
    return doubleOf(rounded)
}

struct MoneyTotals {
    var subtotal: Double
    var discountAmount: Double
    var taxAmount: Double
    var total: Double
}

/// Shared by quotations and invoices. When prices include tax (a
/// Settings option), the tax is the portion already inside the total;
/// otherwise it's added on top.
func moneyTotals(subtotal: Decimal, discountType: String, discountValue: Double, taxRatePercent: Double, pricesIncludeTax: Bool) -> MoneyTotals {
    var discount: Decimal
    switch discountType {
    case "Percent": discount = roundToCents(subtotal * decimalOf(discountValue) / 100)
    case "Fixed": discount = roundToCents(decimalOf(discountValue))
    default: discount = 0
    }
    if discount > subtotal { discount = subtotal }
    if discount < 0 { discount = 0 }
    let afterDiscount = subtotal - discount
    let rate = decimalOf(max(0, taxRatePercent))
    let tax: Decimal
    let total: Decimal
    if pricesIncludeTax {
        tax = rate == 0 ? 0 : roundToCents(afterDiscount * rate / (100 + rate))
        total = afterDiscount
    } else {
        tax = roundToCents(afterDiscount * rate / 100)
        total = afterDiscount + tax
    }
    return MoneyTotals(subtotal: doubleOf(subtotal), discountAmount: doubleOf(discount), taxAmount: doubleOf(tax), total: doubleOf(total))
}

// ---- Bill of Quantities (Phase 7) ----

struct BillOfQuantities: Codable {
    var id: String
    var projectId: String
    var boqNumber: String
    /// "Rental" or "Sale" — which price-list column new line items default
    /// to when added from the item picker (section 18-20 of the brief).
    var pricingMode: String
    /// "Draft" or "Issued" — issued BOQs reject line-item mutations
    /// (section 25: don't silently modify issued documents).
    var status: String
    var notes: String?
    var createdAt: String
    var updatedAt: String
    /// BOQ settings, as in the company's own BQ sheet: mark-up (+) or
    /// mark-down (−) on price-list prices, and what the structure is.
    var markupPercent: Double?
    var structure: String?
    /// The last PDF exported for this document (sections 31-32).
    var pdfPath: String?
    /// The BQ sheet's page: "Landscape" (with prices, the default) or
    /// "Portrait" (no prices).
    var orientation: String? = nil
    /// Rates listed after the total on the BQ sheet (e.g. manpower rates);
    /// the "Total Amount :" row then reads "Subtotal :".
    var ratesSection: BOQRatesSection? = nil
    /// Amounts added after the subtotal on the BQ sheet (e.g. D1 Delivery,
    /// D2 Design Fees): not priced by unit, but added to the total.
    var charges: [BOQCharge]? = nil
    /// true: lines keep their list prices and the mark-up is applied to the
    /// rates shown and printed (rounded to 0.1, like a quotation's). nil:
    /// an older BOQ whose stored prices already include its mark-up.
    var markupOnRates: Bool? = nil
    /// The landscape BQ sheet's Terms box (after the Notes), and a
    /// signature box at the end (company and client).
    var terms: String? = nil
    var signatureSection: Bool? = nil
}

struct BOQCharge: Codable {
    /// "D1", "D2"… when blank.
    var code: String?
    var name: String
    var amount: Double
}

struct BOQRatesSection: Codable {
    var title: String
    var rates: [ManpowerRate]
    var note: String?
}

struct BOQLineItem: Codable {
    var id: String
    var boqId: String
    var sourceKey: String?
    var priceListItemId: String?
    var itemCode: String
    var itemDescription: String
    var unit: String
    var quantity: Double
    /// The price-list price at the moment this line was added — kept as
    /// a permanent reference even if appliedUnitPrice is later
    /// overridden (section 20: never silently overwrite the original).
    /// Still computed and carried through to any Quotation/Invoice made
    /// from this BOQ, even though the BOQ's own screen and PDF now show
    /// weight instead of price.
    var priceListUnitPrice: Double?
    var appliedUnitPrice: Double
    /// Per-unit weight from the price list, for the BOQ's weight display.
    var weightKg: Double?
    var section: String?
    var sortOrder: Int
    var notes: String?
    /// A discount on this item's unit rate: nil/"None", "Percent" (0-100)
    /// or "Amount" (off each unit). Only the discounted rate is printed.
    var discountType: String? = nil
    var discountValue: Double? = nil
}

/// Lightweight row for the project's BOQ list — avoids shipping every
/// line item just to show a summary.
struct BOQSummary: Codable {
    var id: String
    var boqNumber: String
    var status: String
    var pricingMode: String
    var itemCount: Int
    var grandTotal: Double
    var totalWeightKg: Double
    var createdAt: String
    /// What the scaffold is for, e.g. "Access platform for louvres".
    var structure: String? = nil
}

struct BOQDetail: Codable {
    /// The client's default markup (a hint in the editor), and its name.
    var clientMarkupPercent: Double? = nil
    var clientName: String? = nil
    var id: String
    var boqNumber: String
    var status: String
    var pricingMode: String
    var notes: String?
    var createdAt: String
    var updatedAt: String
    var projectNumber: String
    var projectName: String
    var lineItems: [BOQLineItem]
    var grandTotal: Double
    var totalWeightKg: Double
    var markupPercent: Double
    var structure: String?
    /// "Landscape" (with prices) or "Portrait" (no prices).
    var orientation: String
    /// Line id → unit rate after its discount.
    var effectiveRates: [String: Double]
    var ratesSection: BOQRatesSection?
    /// nil = no "+ Section"; grandTotal is the items' total (the
    /// subtotal when there are charges) and totalAmount adds the charges.
    var charges: [BOQCharge]?
    var chargesTotal: Double
    var totalAmount: Double
    /// The mark-up is applied to the rates (not built into the prices).
    var markupOnRates = false
    /// Marked-up rates round up to the next 0.1 (else off to the nearest).
    var markupRoundUp = false
    /// Each line's Chinese name, by line id.
    var chineseNames: [String: String]? = nil
    /// The landscape BQ sheet's Terms box, and whether it ends with a
    /// signature box; the standard terms from Settings.
    var terms: String? = nil
    var signatureSection = false
    var standardTerms: String? = nil
}

struct BOQActionResult: Codable {
    var ok: Bool
    var error: String?
}

// ---- Quotations (Phase 8) ----

struct Quotation: Codable {
    var id: String
    var projectId: String
    var sourceBOQId: String?
    var quotationNumber: String
    /// "Draft", "Issued", or "Cancelled" (section 25's document lifecycle).
    var status: String
    var quotationDate: String
    /// "Rental" or "Sale" — which price-list column the item picker
    /// defaults new line items to. Inherited from the source BOQ when
    /// created from one; chosen at creation otherwise, same idea as
    /// BOQ.pricingMode.
    var pricingMode: String
    var validUntil: String?
    var paymentTerms: String?
    /// "None", "Percent", or "Fixed".
    var discountType: String
    var discountValue: Double
    var taxRatePercent: Double
    var notes: String?
    var createdAt: String
    var updatedAt: String
    // The company's standard quotation (Qt26193):
    /// "Re:" line, e.g. "1601 Scaffolding Materials - Rental - GL-28 G/F …"
    var subject: String?
    /// "Your Ref. No." — the client's own reference.
    var clientRef: String?
    /// "Site Ref.", e.g. "MTR 1601".
    var siteRef: String?
    /// e.g. "BY EMAIL ONLY".
    var deliveryMethod: String?
    /// Rental: "Minimum Hire of N Months".
    var minimumHireMonths: Int?
    /// Whether this quotation has a minimum hire period at all. nil =
    /// saved before this option existed, when every rental quotation had one.
    var minimumHireEnabled: Bool?
    /// Rental: the monthly rental charge is at least Settings' minimum
    /// (HK$1,000 unless changed) when ticked.
    var minimumMonthlyChargeEnabled: Bool? = nil
    /// Markup on every item's unit price (e.g. 30 = +30%), each marked-up
    /// price rounded to the nearest 0.1. Delivery charges aren't marked up.
    var markupPercent: Double?
    /// The last PDF exported for this document (sections 31-32).
    var pdfPath: String?
    /// This quotation's own key terms (payment, delivery, modification…),
    /// with paragraph formatting. nil/blank = the key terms from Settings.
    var keyTerms: String?
    /// The copy the client signed and sent back, kept in the project's
    /// Quotations folder, and when it was added.
    var signedCopyPath: String? = nil
    var signedCopyAt: String? = nil
    /// "No signed copy needed" — takes it off the Dashboard's reminder.
    var signedCopyNotNeeded: Bool? = nil
}

struct QuotationLineItem: Codable {
    var id: String
    var quotationId: String
    var sourceKey: String?
    var priceListItemId: String?
    var itemCode: String
    var itemDescription: String
    var unit: String
    var quantity: Double
    var appliedUnitPrice: Double
    var section: String?
    var sortOrder: Int
    /// The material-list price when the line was priced (section 20), so a
    /// hand-typed price can be shown as an override and kept when the
    /// quotation is switched between Sale and Rental.
    var priceListUnitPrice: Double? = nil
    /// Per-line discount: nil/"None", "Percent" (0-100) or "Amount"
    /// (taken off the line total).
    var discountType: String? = nil
    var discountValue: Double? = nil
    /// Set for a row of one of the quotation's extra sections
    /// (`QuotationBlock`) rather than a material or delivery charge.
    var blockId: String? = nil
}

/// An extra section of a quotation's table, after the materials and
/// delivery charges, as on the company's own quotations:
/// - "Priced": a title row and priced rows added to the total, e.g.
///   "Design Fees" — A1 Design and Drawing HK$ 3,000.00, or erection &
///   dismantle prices;
/// - "Rates": a title row and rate-only rows after the Total Amount, e.g.
///   "Erection & Dismantle Manpower Rates" — R1 Scaffolder CP
///   HK$ 2,300.00 / md "(Rate Only)";
/// - "Note": just a note, after the Total Amount.
/// Any of them can end with a note across the whole table, in small italics.
struct QuotationBlock: Codable {
    var id: String
    var quotationId: String
    var kind: String
    /// The merged title row ("" = none).
    var title: String
    /// Row numbers: "A" → A1, A2…
    var prefix: String
    var note: String?
    var sortOrder: Int
    /// Priced sections: charged once (nil), or "Day" / "Week" / "Month" —
    /// shown as "per week" etc. and counted as a recurring charge.
    var chargePeriod: String? = nil
}

/// A quotation's charges split for the Dashboard and project totals:
/// the monthly charge (rental, and sections charged per month), the
/// one-time charge (delivery and sections charged once; everything on a
/// Sale quotation), and sections charged per day or week.
struct ChargeSplit: Codable {
    var monthly: Double
    var oneTime: Double
    /// "Day" / "Week" → amount.
    var recurring: [String: Double]
}

struct QuotationSummary: Codable {
    var id: String
    var quotationNumber: String
    var status: String
    var itemCount: Int
    var total: Double
    var createdAt: String
    /// The client's signed copy has been added.
    var signed = false
    /// The BOQ it refers to (if any), and that BOQ's structure.
    var boqNumber: String? = nil
    var structure: String? = nil
    /// Its "Re:" subject line.
    var subject: String? = nil
    var pricingMode: String? = nil
    var charges: ChargeSplit? = nil
}

struct QuotationDetail: Codable {
    var id: String
    var projectId: String
    /// The BOQ this quotation currently references (set when created
    /// from a BOQ, or when items are imported from one later).
    var sourceBOQId: String?
    var sourceBOQNumber: String?
    var quotationNumber: String
    var status: String
    var quotationDate: String
    var pricingMode: String
    var validUntil: String?
    var paymentTerms: String?
    var discountType: String
    var discountValue: Double
    var taxRatePercent: Double
    var notes: String?
    var createdAt: String
    var updatedAt: String
    var projectNumber: String
    var projectName: String
    var clientName: String?
    var siteName: String?
    var lineItems: [QuotationLineItem]
    var subtotal: Double
    var discountAmount: Double
    var taxAmount: Double
    var total: Double
    var subject: String?
    var clientRef: String?
    var siteRef: String?
    var deliveryMethod: String?
    /// 1 for Sale quotations.
    var hireMonths: Int
    /// Materials only (per month, for rental).
    var materialsSubtotal: Double
    /// materialsSubtotal × hireMonths.
    var materialsCharge: Double
    var deliveryTotal: Double
    var standardDeliveryCharge: Double?
    /// Whether "Minimum Hire of N Months" applies to this quotation.
    var minimumHireEnabled: Bool
    /// The months used when it does.
    var minimumHireMonths: Int
    var markupPercent: Double?
    /// Marked-up prices round up to the next 0.1 (else off to the nearest).
    var markupRoundUp = false
    /// Line id → unit price charged (after the markup).
    var effectiveUnitPrices: [String: Double]
    /// Line id → line total (after the markup and the line's discount).
    var lineTotals: [String: Double]
    /// Extra sections (priced, rates, notes), in order. Their rows are in
    /// `lineItems` with `blockId` set.
    var blocks: [QuotationBlock]
    /// The priced sections' rows, added to the total.
    var otherChargesTotal: Double
    /// Minimum monthly rental charge: ticked, the minimum, and whether it
    /// raised this quotation's monthly rental (then `monthlyRental` is it).
    var minimumMonthlyChargeEnabled: Bool = false
    var minimumMonthlyCharge: Double = 1000
    var minimumMonthlyApplied: Bool = false
    var monthlyRental: Double = 0
    var charges: ChargeSplit? = nil
    /// This quotation's own key terms; nil = the standard ones below.
    var keyTerms: String?
    /// The key terms from Settings, printed when `keyTerms` is blank.
    var standardKeyTerms: String
    /// The signed copy the client returned: its file name, when it was
    /// added, and whether the file is still there.
    var signedCopyName: String? = nil
    var signedCopyAt: String? = nil
    var signedCopyExists = false
    var signedCopyNotNeeded = false
    /// The client's default markup (a hint in the editor).
    var clientMarkupPercent: Double? = nil
}

struct QuotationActionResult: Codable {
    var ok: Bool
    var error: String?
}

// ---- Invoices (Phase 9) ----

struct Invoice: Codable {
    var id: String
    var projectId: String
    var sourceQuotationId: String?
    var invoiceNumber: String
    /// "Draft", "Issued", "PartiallyPaid", "Paid", "Overdue", or
    /// "Cancelled" (section 22's invoice statuses).
    var status: String
    var invoiceDate: String
    var dueDate: String?
    var paymentTerms: String?
    var discountType: String
    var discountValue: Double
    var taxRatePercent: Double
    /// Cumulative amount recorded against this invoice.
    var amountPaid: Double
    var notes: String?
    var createdAt: String
    var updatedAt: String
    /// The last PDF exported for this document (sections 31-32).
    var pdfPath: String?
    /// "Rental" or "Sale", from the quotation it's based on. nil = made
    /// before invoices followed their quotation's pricing (plain lines).
    var pricingMode: String? = nil
    /// Rental: how many months of rent this invoice charges (one month,
    /// or the quotation's full hire period).
    var rentalMonths: Int? = nil
    /// Rental: the period charged, e.g. "1 Oct – 31 Oct 2026" (optional).
    var rentalPeriod: String? = nil
}

struct InvoiceLineItem: Codable {
    var id: String
    var invoiceId: String
    var sourceKey: String?
    var priceListItemId: String?
    var itemCode: String
    var itemDescription: String
    var unit: String
    var quantity: Double
    var appliedUnitPrice: Double
    var section: String?
    var sortOrder: Int
    /// Per-line discount: nil/"None", "Percent" (0-100) or "Amount"
    /// (taken off the line total).
    var discountType: String? = nil
    var discountValue: Double? = nil
    /// A one-off charge copied from one of the quotation's priced
    /// sections: its title (e.g. "Design Fees") and row prefix ("A").
    var chargeGroup: String? = nil
    var chargePrefix: String? = nil
}

struct InvoiceSummary: Codable {
    var id: String
    var invoiceNumber: String
    var status: String
    var itemCount: Int
    var total: Double
    var amountPaid: Double
    var dueDate: String?
    var createdAt: String
}

struct InvoiceDetail: Codable {
    var id: String
    var invoiceNumber: String
    var status: String
    var invoiceDate: String
    var dueDate: String?
    var paymentTerms: String?
    var discountType: String
    var discountValue: Double
    var taxRatePercent: Double
    var amountPaid: Double
    var notes: String?
    var createdAt: String
    var updatedAt: String
    var projectNumber: String
    var projectName: String
    var clientName: String?
    var siteName: String?
    var lineItems: [InvoiceLineItem]
    var subtotal: Double
    var discountAmount: Double
    var taxAmount: Double
    var total: Double
    var balanceDue: Double
    var sourceQuotationId: String?
    var sourceQuotationNumber: String?
    var pricingMode: String?
    /// 1 unless a rental invoice charges several months.
    var rentalMonths: Int
    var rentalPeriod: String?
    /// Materials only, per month for rental.
    var materialsSubtotal: Double
    /// materialsSubtotal × rentalMonths.
    var materialsCharge: Double
    var deliveryTotal: Double
    /// One-off charges from the quotation's priced sections.
    var otherChargesTotal: Double
}

struct InvoiceActionResult: Codable {
    var ok: Bool
    var error: String?
}

// ---- Delivery Notes (Phase 10) ----

struct DeliveryNote: Codable {
    var id: String
    var projectId: String
    var sourceQuotationId: String?
    var sourceInvoiceId: String?
    var deliveryNoteNumber: String
    /// "Draft", "Issued", or "Cancelled" — same lifecycle discipline as
    /// every other formal document (section 25).
    var status: String
    var deliveryDate: String
    var deliveryAddress: String?
    var deliveredBy: String?
    var receivedBy: String?
    var notes: String?
    var createdAt: String
    var updatedAt: String
    /// The last PDF exported for this document (sections 31-32).
    var pdfPath: String?
    /// Who to contact on site ("Contact Person" on the note); the site's
    /// contact person when the note is made.
    var contactPerson: String? = nil
}

/// No pricing fields on purpose — section 23 lists delivery notes as
/// items/quantity/unit/description, never prices.
struct DeliveryNoteLineItem: Codable {
    var id: String
    var deliveryNoteId: String
    var sourceKey: String?
    var priceListItemId: String?
    var itemCode: String
    var itemDescription: String
    var unit: String
    var quantity: Double
    var section: String?
    var sortOrder: Int
    var notes: String?
}

struct DeliveryNoteSummary: Codable {
    var id: String
    var deliveryNoteNumber: String
    var status: String
    var itemCount: Int
    var deliveryDate: String
    var createdAt: String
}

struct DeliveryNoteDetail: Codable {
    var id: String
    var deliveryNoteNumber: String
    var status: String
    var deliveryDate: String
    var deliveryAddress: String?
    var deliveredBy: String?
    var receivedBy: String?
    var notes: String?
    var createdAt: String
    var updatedAt: String
    var projectNumber: String
    var projectName: String
    var clientName: String?
    var siteName: String?
    var lineItems: [DeliveryNoteLineItem]
    var contactPerson: String? = nil
    var projectId: String? = nil
    /// The quotation its items were first taken from (if any).
    var sourceQuotationId: String? = nil
    /// Each line's Chinese name, by line id.
    var chineseNames: [String: String]? = nil
}

struct DeliveryNoteActionResult: Codable {
    var ok: Bool
    var error: String?
}

// ---- Company settings (feeds every PDF header — section 28) ----

struct CompanySettings: Codable {
    var id: String
    var companyName: String
    var addressLine1: String?
    var addressLine2: String?
    var phone: String?
    var email: String?
    var website: String?
    var registrationNumber: String?
    var vatNumber: String?
    var bankDetails: String?
    var defaultPaymentTerms: String?
    var defaultNotes: String?
    var currency: String
    var defaultTaxRatePercent: Double
    // Added later — all optional so settings saved by earlier versions
    // still load.
    /// When true, line prices already include tax (section 50).
    var pricesIncludeTax: Bool?
    /// "A4" (default) or "Letter" (sections 27, 54).
    var paperSize: String?
    /// "System" (default), "Light" or "Dark" (sections 5, 57).
    var appearance: String?
    /// Copied into Administration/Company/ — shown on every PDF (section 28).
    var logoPath: String?
    /// Document number formats (section 24). Tokens: {PROJECT} {YYYY}
    /// {YY} {SEQ}. nil = the built-in default.
    var numberFormatBOQ: String?
    var numberFormatQuotation: String?
    var numberFormatInvoice: String?
    var numberFormatDeliveryNote: String?
    /// Default days until an invoice is due.
    var defaultInvoiceDueDays: Int?
    // ---- Standard quotation (from Qt26193) ----
    var signatoryName: String?
    var signatoryTitle: String?
    /// e.g. "www.pfitnet.com/TC"
    var termsURL: String?
    /// The numbered terms: payment, delivery, modification…
    var quotationTerms: String?
    /// "Order shall be confirmed … valid for 7 business days …"
    var quotationAcceptance: String?
    /// Per truck per trip; pre-fills the "+ Delivery Charge" line.
    var standardDeliveryCharge: Double?
    /// Rental quotations: "Minimum Hire of N Months".
    var defaultMinimumHireMonths: Int?
    /// Foreign price lists → base currency, e.g. ["EUR": 8.93].
    var exchangeRates: [String: Double]?
    /// Continue an existing sequence, e.g. ["QT": 194] after Qt26193.
    var numberStarts: [String: Int]?
    /// Where a quotation's Terms and Conditions start: "WhenLong" (nil —
    /// right after the rest if they fit on that page, else on a new page;
    /// the signatures move on by themselves if they don't fit) or "Always"
    /// (always on a page of their own, as on Qt26193).
    var termsNewPage: String?
    /// The standard manpower rates filled into a quotation's rates section
    /// by "Standard Rates". nil = `defaultManpowerRates`.
    var manpowerRates: [ManpowerRate]?
    /// Marked-up unit prices (quotation and BOQ markup %) are rounded up to
    /// the next 0.1 (true) or off to the nearest 0.1 (nil / false).
    var markupRoundUp: Bool? = nil
    /// Materials every new BOQ starts with (Settings → BOQ Defaults).
    var defaultBOQItems: [DefaultBOQItem]? = nil
    /// The minimum monthly rental charge a quotation can apply (nil = 1,000).
    var minimumMonthlyRental: Double? = nil
    /// Materials' Chinese names shown on delivery notes and BOQs (nil = yes).
    var chineseNamesOnDocuments: Bool? = nil
    /// Standard terms for the landscape BOQ's Terms box (Settings → BOQ Defaults).
    var boqTerms: String? = nil
}

/// A price-list item and quantity put into every new BOQ.
struct DefaultBOQItem: Codable {
    var priceListItemId: String
    var quantity: Double
}

/// A worker type and its day rate, e.g. "Scaffolder CP", 2,300 per "md".
struct ManpowerRate: Codable {
    var name: String
    var rate: Double
    var unit: String
}

/// As on the company's quotations (e.g. Qt26179).
let defaultManpowerRates = [
    ManpowerRate(name: "Scaffolder CP", rate: 2300, unit: "md"),
    ManpowerRate(name: "Scaffolder", rate: 2100, unit: "md"),
    ManpowerRate(name: "Rigger", rate: 2000, unit: "md"),
    ManpowerRate(name: "General Helper", rate: 1800, unit: "md"),
]

let defaultQuotationTerms = """
(i) Payment : First two month's rental is to be paid upon order confirmation.
Following rental charges are to be paid monthly on the first day of the month.
Delivery charges are to be paid within 7 days against each truck's delivery.
(ii) Delivery : Minimum of 5 days upon order confirmation.
(iii) Modification : Extra works & modifications of works will be subject to an extra charge.
"""

let defaultQuotationAcceptance = "Order shall be confirmed and regarded as properly accepted upon signature by all parties AND such signed copy is returned to Proficiency (HK) Limited via instant electronic communication means. This quotation shall be valid for 7 business days against the issue date."


/// Built-in number formats — exactly what the app has always produced.
let defaultNumberFormats: [String: String] = [
    "BOQ": "{PROJECT}-BOQ-{SEQ}",
    // The company's own convention: Qt26193 (quotations), H26XXX (invoices).
    "QT": "Qt{YY}{SEQ}",
    "INV": "H{YY}{SEQ}",
    "DN": "{PROJECT}-DN-{SEQ}",
]

/// Makes the next number for a template, looking at every existing
/// number of that document type so a duplicate can never be produced
/// (section 24). The sequence restarts naturally whenever the text
/// around {SEQ} changes — e.g. per project for {PROJECT}, per year for
/// {YYYY}.
func nextDocumentNumber(template rawTemplate: String, projectNumber: String, existing: [String], date: Date = Date(), startAt: Int = 1) -> String {
    var template = rawTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
    if !template.contains("{SEQ}") { template += "-{SEQ}" }
    let year = Calendar.current.component(.year, from: date)
    let filled = template
        .replacingOccurrences(of: "{PROJECT}", with: projectNumber)
        .replacingOccurrences(of: "{YYYY}", with: String(year))
        .replacingOccurrences(of: "{YY}", with: String(format: "%02d", year % 100))
    guard let seqRange = filled.range(of: "{SEQ}") else { return filled }
    let before = String(filled[..<seqRange.lowerBound])
    let after = String(filled[seqRange.upperBound...])
    let used = Set(existing)
    let sequences: [Int] = existing.compactMap { number in
        guard number.hasPrefix(before), number.hasSuffix(after), number.count > before.count + after.count else { return nil }
        return Int(number.dropFirst(before.count).dropLast(after.count))
    }
    var next = max((sequences.max() ?? 0) + 1, startAt)
    var candidate = before + String(format: "%03d", next) + after
    while used.contains(candidate) {
        next += 1
        candidate = before + String(format: "%03d", next) + after
    }
    return candidate
}

// ---- PDF documents (layout of the company's quotation Qt26193) ----

enum PDFMode {
    case export
    case print
    /// A Word (.docx) copy laid out like the PDF (built by js/docx-export.js).
    case word
}

// ---- Word (.docx) export: the document as the PDF lays it out ----

struct WordColumn: Encodable { var title: String; var width: Double; var kind: String }

/// "Delivery Address : …": the value wrapped as on the PDF.
struct WordInfoRow: Encodable { var label: String; var lines: [String]; var bold: Bool }

struct WordRow: Encodable {
    /// "item", "section", "summary", "partial" or "note"
    var type: String
    /// Row height on the PDF, in points.
    var height: Double
    /// item/partial: each cell's lines, wrapped as on the PDF.
    var cells: [[String]]? = nil
    /// section title, note, or the partial row's merged text.
    var text: String? = nil
    var label: String? = nil
    var value: String? = nil
    var emphasized: Bool? = nil
}

struct WordParagraph: Encodable {
    /// "text" (justified) or "hanging"
    var type: String
    var text: String? = nil
    var link: String? = nil
    var marker: String? = nil
    var lines: [String]? = nil
    /// Points in from the margin: the marker, and where the text starts.
    var left: Double? = nil
    var textX: Double? = nil
    var colon: Bool? = nil
}

struct WordSection: Encodable {
    var heading: String?
    var paragraphs: [WordParagraph]
    var pageBreakBefore: Bool
}

struct WordRefRow: Encodable { var label: String; var value: String; var wraps: Bool }
struct WordSignatureLine: Encodable { var text: String; var colon: Bool; var value: String? }
struct WordSignature: Encodable { var heading: String; var lines: [WordSignatureLine] }
struct WordFont: Encodable { var style: String; var data: String }

struct WordLayout: Encodable {
    var ok = true
    var paperSize: String
    var pageWidth: Double
    var pageHeight: Double
    var textLeft: Double
    var textRight: Double
    var contentBottom: Double
    var number: String
    var status: String
    var title: String
    var clientName: String
    var clientLines: [String]
    var refRows: [WordRefRow]
    var deliveryMethod: String?
    var salutation: String?
    var subject: String?
    var intro: String?
    var currencySymbol: String
    var columns: [WordColumn]
    var rows: [WordRow]
    var sections: [WordSection]
    var signatures: [WordSignature]
    var closingLine: String?
    var infoRows: [WordInfoRow] = []
    /// Heading row height (23pt on a compact table, else 24.1pt).
    var headerHeight = 24.1
    var receiptRows: [[String]] = []
    /// The receipt lines start a new page (with "Ref.: <number>").
    var receiptNewPage = false
    // Filled in by the bridge:
    var projectNumber = ""
    var subfolder = ""
    var fileName = ""
    /// The letterhead and footer, page-sized, as a base64 PNG.
    var letterheadPNG = ""
    var fonts: [WordFont] = []
}

/// How a table column's cells are drawn, as on the company's quotation.
enum LetterColumnKind {
    /// "No", "Qty"
    case center
    /// Descriptions
    case left
    /// Weights and other plain figures
    case right
    /// "HK$" at the left of the cell, the amount at the right
    case money
    /// A weight with "kg" at the right of the cell, the figure before it
    /// (the delivery note's "3.8   kg")
    case weight
}

struct LetterColumn {
    let title: String
    /// Points. The columns of a table add up to 507 (the original's width).
    let width: CGFloat
    let kind: LetterColumnKind
}

enum LetterTableRow {
    /// One value per column; a value wraps, and "\n" starts a new line.
    case item([String])
    /// A full-width, centred bold heading, e.g. "Delivery Charges".
    case section(String)
    /// A label across every column but the last, and a bold value in the
    /// last column. `emphasized` is the larger "Total Amount:" style.
    case summary(label: String, value: String, emphasized: Bool)
    /// Values for the first columns, then `tail` centred across the rest,
    /// e.g. a rates-only row: No, description, rate, "(Rate Only)".
    case partial([String], tail: String)
    /// A note across the whole table in small grey italics, e.g. "* Please
    /// note that labour rates are subject to a price increase…".
    case note(String)
}

enum LetterParagraph {
    /// Justified body text. `link` (if it appears in the text) is shown as
    /// a blue, underlined web address.
    case text(String, link: String?)
    /// A numbered term: "(i) Payment : First two month's rental…", with
    /// any further lines indented under the first.
    case term(label: String?, lines: [String])
    /// A hanging-indent paragraph: `marker` ("(i) Payment", "•", "1.") at
    /// `left` points in from the margin, and the text wrapped at `indent`
    /// points in (nil: just past the marker). `colon` puts a colon just
    /// before the text, as in "(i) Payment : First two month's rental…".
    case hanging(marker: String, lines: [String], left: CGFloat, indent: CGFloat?, colon: Bool)
}

// ---- Paragraph formatting in payment terms and key terms ----
//
// Typed in a plain text box, one paragraph per line:
//   "(i) Payment : text" or "Deposit: text"  label, colon, and the text in a
//                                           hanging indent at a fixed column
//   "- text" or "• text"                    bullet, hanging indent
//   "1. text", "(a) text", "b) text", "(iv) text"   numbered, hanging indent
//   "marker<Tab>text"                       any marker, hanging indent
// Lines after one of these (up to a blank line) continue its text, lined up
// under it; an indented bullet, number or label goes under it, lined up with
// its text. Anything else is an ordinary paragraph; a blank line starts a
// new one. js/paragraph-format.js follows the same rules for the preview.

/// Where the text of a labelled line starts: 89.25pt in, so the colon is
/// at 128.25pt and the text at 132pt, as on Qt26193.
let labelTextIndent: CGFloat = 89.25

enum HangingStyle { case label, bullet, marker }

private let numberMarkerPattern = #"^(\(?[0-9]{1,3}[.)]|\([0-9]{1,3}\)|\(?[a-zA-Z][.)]|\([a-zA-Z]\)|\(?[ivxIVX]{1,5}[.)]|\([ivxIVX]{1,5}\))\s+"#

/// "Deposit: 50%…" → ("Deposit", "50%…"). A label is short (up to five
/// words) and the colon is followed by a space or nothing, so "10:30" and
/// web addresses aren't labels.
private func labelSplit(_ line: String) -> (marker: String, text: String, style: HangingStyle)? {
    guard let colon = line.firstIndex(of: ":") else { return nil }
    let label = line[..<colon].trimmingCharacters(in: .whitespaces)
    let after = line[line.index(after: colon)...]
    guard !label.isEmpty, label.count <= 40, label.split(separator: " ").count <= 5,
          after.isEmpty || after.first == " " || after.first == "\t",
          !label.lowercased().contains("http"), !label.lowercased().contains("www.") else { return nil }
    return (label, after.trimmingCharacters(in: .whitespaces), .label)
}

/// The marker and text of a formatted line, or nil for ordinary text.
func hangingItem(_ raw: String) -> (marker: String, text: String, style: HangingStyle)? {
    let line = raw.trimmingCharacters(in: .whitespaces)
    if let tab = line.firstIndex(of: "\t") {
        let marker = line[..<tab].trimmingCharacters(in: .whitespaces)
        let rest = line[line.index(after: tab)...].trimmingCharacters(in: .whitespaces)
        if !marker.isEmpty {
            if marker.hasSuffix(":") {
                return (String(marker.dropLast()).trimmingCharacters(in: .whitespaces), rest, .label)
            }
            return (marker, rest, .marker)
        }
    }
    for bullet in ["- ", "• ", "* ", "· "] where line.hasPrefix(bullet) {
        return ("•", String(line.dropFirst(bullet.count)).trimmingCharacters(in: .whitespaces), .bullet)
    }
    if let label = labelSplit(line) { return label }
    if let range = line.range(of: numberMarkerPattern, options: .regularExpression) {
        return (line[range].trimmingCharacters(in: .whitespaces), String(line[range.upperBound...]), .marker)
    }
    return nil
}

/// Formatted text as letter paragraphs, `left` points in from the margin
/// (0 for the Terms and Conditions; more when nested under a label).
/// Where a hanging item's text starts, from its marker's position.
func hangingTextOffset(_ style: HangingStyle) -> CGFloat {
    switch style {
    case .label: return labelTextIndent
    case .bullet: return 12
    case .marker: return 24
    }
}

func formattedParagraphs(_ text: String, left: CGFloat = 0) -> [LetterParagraph] {
    var result: [LetterParagraph] = []
    var current: (marker: String, lines: [String], style: HangingStyle, left: CGFloat)? = nil
    var plain: [String] = []
    /// The text column of the last item at `left`: indented items go there.
    var parentText: CGFloat? = nil
    func flush() {
        if let c = current {
            result.append(.hanging(marker: c.marker, lines: c.lines, left: c.left, indent: c.left + hangingTextOffset(c.style), colon: c.style == .label))
            current = nil
        }
        if !plain.isEmpty {
            result.append(left == 0 ? .text(plain.joined(separator: "\n"), link: nil)
                                    : .hanging(marker: "", lines: plain, left: left, indent: left, colon: false))
            plain = []
        }
    }
    for raw in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { flush(); continue }
        if let item = hangingItem(raw) {
            flush()
            let indented = raw.first == " " || raw.first == "\t"
            let itemLeft = indented ? (parentText ?? left) : left
            if !indented || parentText == nil { parentText = left + hangingTextOffset(item.style) }
            current = (item.marker, item.text.isEmpty ? [] : [item.text], item.style, itemLeft)
        } else if current != nil {
            current?.lines.append(trimmed)
        } else {
            plain.append(trimmed)
            parentText = nil
        }
    }
    flush()
    return result
}

/// Key terms text with `paymentTerms` as the text of its "Payment" term
/// (replacing that term and the lines under it), or added as one: the
/// payment terms' opening lines beside the label, the rest indented under it.
func keyTermsText(_ standard: String, withPaymentTerms paymentTerms: String) -> String {
    let lines = standard.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
    let isPaymentLabel: (String) -> Bool = { line in
        guard let item = hangingItem(line), item.style == .label else { return false }
        return item.marker.lowercased().contains("payment")
    }
    let start = lines.firstIndex(where: isPaymentLabel)
    let label = start.flatMap { hangingItem(lines[$0])?.marker } ?? "Payment"
    var block: [String] = []
    var opening = true
    for raw in paymentTerms.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
        let line = raw.trimmingCharacters(in: .whitespaces)
        guard !line.isEmpty else { continue }
        if opening && hangingItem(line) == nil {
            block.append(block.isEmpty ? "\(label) : \(line)" : line)
        } else {
            if block.isEmpty { block.append("\(label) :") }
            opening = false
            block.append("    \(line)")
        }
    }
    guard let first = start else { return (lines + block).joined(separator: "\n") }
    var end = first + 1
    while end < lines.count {
        let line = lines[end]
        if line.trimmingCharacters(in: .whitespaces).isEmpty { break }
        let indented = line.first == " " || line.first == "\t"
        if hangingItem(line) != nil && !indented { break }
        end += 1
    }
    return (Array(lines[..<first]) + block + Array(lines[end...])).joined(separator: "\n")
}

/// A quotation's or invoice's own payment terms under a "Payment" label:
/// their opening text beside the label, and any bullets, numbered or
/// labelled lines after it indented under that text.
func paymentTermParagraphs(_ paymentTerms: String, label: String) -> [LetterParagraph] {
    var nested = formattedParagraphs(paymentTerms, left: labelTextIndent)
    var opening: [String] = []
    if case .hanging(let marker, let lines, _, _, false)? = nested.first, marker.isEmpty {
        opening = lines
        nested.removeFirst()
    }
    return [.hanging(marker: label, lines: opening, left: 0, indent: labelTextIndent, colon: true)] + nested
}

struct LetterSection {
    /// Bold and underlined, e.g. "Terms and Conditions".
    var heading: String?
    var paragraphs: [LetterParagraph]
    /// Kept on one page (the quotation's Terms and Conditions): it follows
    /// on in the space left, and starts a new page only if it won't fit.
    var keepTogether: Bool = false
    /// Always starts at the top of a new page.
    var alwaysNewPage: Bool = false
}

struct LetterSignatureLine {
    var text: String
    /// "Position :" / "Date :" style.
    var colon: Bool = false
    /// Printed after the colon, e.g. a name already known.
    var value: String? = nil
}

struct LetterSignature {
    /// "For and on Behalf of"
    var heading: String
    /// Under the signing rule: party name, then name / position / date lines.
    var lines: [LetterSignatureLine]
}

/// A complete document in the letterhead layout.
struct LetterDocument {
    var number: String
    var status: String
    /// "QUOTATION", "INVOICE", …
    var title: String
    var clientName: String
    var clientLines: [String]
    /// The block at the top right: "Our Ref. No. : Qt26193", …
    var refRows: [(label: String, value: String)]
    /// e.g. "BY EMAIL ONLY"
    var deliveryMethod: String?
    var salutation: String?
    /// Bold and underlined "Re: …" line.
    var subject: String?
    var intro: String?
    /// "HK$" for HKD, otherwise the currency code.
    var currencySymbol: String
    var columns: [LetterColumn]
    var rows: [LetterTableRow]
    var sections: [LetterSection]
    /// Left, then right.
    var signatures: [LetterSignature]
    var closingLine: String?
    /// Labelled lines under the title, e.g. the delivery note's "Delivery
    /// Address : …", "Contact Person : …" (bold value).
    var infoRows: [LetterInfoRow] = []
    /// Shorter rows (23pt heading, 21.1pt items), as on the delivery note.
    var compactTable = false
    /// Lines to write on after everything else, two to a row, e.g.
    /// ("Received By", "Date"), ("Full Name", "Contact No."). If they go
    /// on a page of their own it starts "Ref.: <number>".
    var receiptRows: [(String, String)] = []
}

struct LetterInfoRow {
    var label: String
    var value: String
    var boldValue = false
}

struct PDFExportResult: Codable {
    var ok: Bool
    var error: String?
    var path: String?
}

// =====================================================================
// MARK: - Small helpers
// =====================================================================

/// `current` in the order of `ids` (unknown ids ignored), then any of
/// `current` that `ids` left out, in their existing order.
func reordered(_ current: [String], by ids: [String]) -> [String] {
    let known = Set(current)
    var seen = Set<String>()
    let front = ids.filter { known.contains($0) && seen.insert($0).inserted }
    return front + current.filter { !seen.contains($0) }
}

func makeId(_ prefix: String) -> String {
    let millis = Int(Date().timeIntervalSince1970 * 1000)
    let randomPart = Int.random(in: 0..<1_000_000_000)
    return "\(prefix)_\(String(millis, radix: 36))_\(String(randomPart, radix: 36))"
}

private let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func nowISO() -> String {
    isoFormatter.string(from: Date())
}

/// "1,234.56" rather than "1234.56" — every PDF money figure goes
/// through this, per the person's explicit formatting preference.
func formatMoney(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = true
    formatter.groupingSeparator = ","
    formatter.decimalSeparator = "."
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
}

/// Quantities are always whole numbers in this app — "1,250" not
/// "1250.00" or "1250.0".
func formatQuantity(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.usesGroupingSeparator = true
    formatter.groupingSeparator = ","
    formatter.maximumFractionDigits = 0
    return formatter.string(from: NSNumber(value: value.rounded())) ?? String(format: "%.0f", value)
}

/// nil for a missing or whitespace-only value — records saved by earlier
/// versions can hold "" where nothing was entered.
func nonBlank(_ value: String?) -> String? {
    guard let v = value?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
    return v
}

/// A name typed for Rename, made safe as a file name: no folder
/// separators, and without the extension if the person typed it too
/// (so "Plan.pdf" doesn't become "Plan.pdf.pdf").
func safeFileBaseName(_ raw: String, extension ext: String) -> String {
    var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "/", with: "-")
        .replacingOccurrences(of: ":", with: "-")
    if !ext.isEmpty, name.lowercased().hasSuffix("." + ext.lowercased()) {
        name = String(name.dropLast(ext.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    while name.hasPrefix(".") { name.removeFirst() }
    return name
}

/// A BOQ line's description with its note (if any) appended.
func lineDescription(_ description: String, notes: String?) -> String {
    guard let notes = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty else { return description }
    return "\(description) — \(notes)"
}

/// "2026-09-28" (from a date field) → the stored ISO timestamp, fixed at
/// midday UTC so it shows as the same calendar day in any time zone.
/// nil if the text isn't a real date.
func isoFromDay(_ day: String) -> String? {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyy-MM-dd"
    guard let date = f.date(from: String(day.prefix(10))) else { return nil }
    return isoFormatter.string(from: date.addingTimeInterval(12 * 3600))
}

func formatDateForDisplay(_ iso: String) -> String {
    guard let date = isoFormatter.date(from: iso) else { return iso }
    let displayFormatter = DateFormatter()
    displayFormatter.dateStyle = .medium
    displayFormatter.timeStyle = .none
    return displayFormatter.string(from: date)
}

// =====================================================================
// MARK: - JSON-file collection store (mirrors db.js's JsonCollection)
// =====================================================================

/// Whether a file is there — also when iCloud Drive has moved it off this
/// Mac to save space (older macOS leaves ".name.icloud" in its place until
/// it's downloaded again).
func fileIsPresent(_ path: String) -> Bool {
    let fm = FileManager.default
    if fm.fileExists(atPath: path) { return true }
    let url = URL(fileURLWithPath: path)
    return fm.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud").path)
}

/// Asks iCloud Drive to bring back a file it moved off this Mac, and calls
/// `done` (main thread) once it's here, or with false after `timeout`.
func whenDownloaded(_ path: String, timeout: TimeInterval = 60, done: @escaping (Bool) -> Void) {
    let fm = FileManager.default
    if fm.fileExists(atPath: path) { done(true); return }
    guard fileIsPresent(path) else { done(false); return }
    try? fm.startDownloadingUbiquitousItem(at: URL(fileURLWithPath: path))
    let started = Date()
    func check() {
        if fm.fileExists(atPath: path) { done(true); return }
        if Date().timeIntervalSince(started) > timeout { done(false); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: check)
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: check)
}

final class JSONStore<T: Codable> {
    private let fileURL: URL

    init(fileURL: URL) {
        self.fileURL = fileURL
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            try? Data("[]".utf8).write(to: fileURL)
        }
    }

    func readAll() -> [T] {
        guard let data = try? Data(contentsOf: fileURL), !data.isEmpty else { return [] }
        do {
            return try JSONDecoder().decode([T].self, from: data)
        } catch {
            // Never let an unreadable file be silently overwritten by the
            // next save: keep a copy of it alongside, then carry on.
            // (Section 48: never lose saved information.)
            preserveUnreadableFile(error)
            return []
        }
    }

    private func preserveUnreadableFile(_ error: Error) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        let copy = fileURL.deletingPathExtension()
            .appendingPathExtension("unreadable-\(f.string(from: Date())).json")
        if !FileManager.default.fileExists(atPath: copy.path) {
            try? FileManager.default.copyItem(at: fileURL, to: copy)
        }
        NSLog("ScaffoldPro: could not read %@ (%@). A copy was kept at %@", fileURL.lastPathComponent, String(describing: error), copy.lastPathComponent)
    }

    func writeAll(_ items: [T]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Sharing a folder with other Macs: what changed goes into this
        // Mac's log there too (TeamSync).
        // The material list also goes to iCloud Drive when this Mac isn't
        // sharing a folder (TeamSync.material).
        let folder = fileURL.deletingLastPathComponent().standardizedFileURL
        let team = [TeamSync.current, TeamSync.material].compactMap { $0 }.first {
            $0.localData.standardizedFileURL == folder && $0.handles(fileURL.lastPathComponent)
        }
        let previous: Data? = team == nil ? nil : (try? Data(contentsOf: fileURL))
        // Atomic: written to a temporary file and swapped in, so a crash
        // or power cut mid-save can never leave a half-written database
        // file behind (section 48).
        try? data.write(to: fileURL, options: .atomic)
        team?.recordLocalWrite(store: fileURL.lastPathComponent, old: previous, new: data)
        // Lets the automatic iCloud backup know there's something new.
        NotificationCenter.default.post(name: CloudBackupManager.dataSaved, object: nil)
    }

    func insert(_ item: T) {
        var items = readAll()
        items.append(item)
        writeAll(items)
    }

    func insertMany(_ newItems: [T]) {
        var items = readAll()
        items.append(contentsOf: newItems)
        writeAll(items)
    }

    var isEmpty: Bool { readAll().isEmpty }
}

// =====================================================================
// MARK: - Project numbering (mirrors src/projectNumbering.js)
// =====================================================================

func currentYearSuffix(_ date: Date = Date()) -> String {
    let year = Calendar.current.component(.year, from: date)
    return String(format: "%02d", year % 100)
}

func nextProjectNumber(existingNumbers: [String], date: Date = Date()) -> String {
    let yearSuffix = currentYearSuffix(date)
    let sequences: [Int] = existingNumbers.compactMap { number in
        guard number.count == 5, number.hasPrefix(yearSuffix) else { return nil }
        return Int(number.suffix(3))
    }
    // Skip any sequence already taken (e.g. by a manual override) and never
    // go past 999, which would make a 6-digit number.
    var next = (sequences.max() ?? 0) + 1
    while existingNumbers.contains("\(yearSuffix)\(String(format: "%03d", next))") { next += 1 }
    return "\(yearSuffix)\(String(format: "%03d", min(next, 999)))"
}

struct NumberValidation {
    let valid: Bool
    let reason: String?
}

func validateProjectNumber(_ number: String, existingNumbers: [String], date: Date = Date()) -> NumberValidation {
    guard number.count == 5 else {
        return NumberValidation(valid: false, reason: "Project number must be exactly 5 digits (YYNNN).")
    }
    guard number.allSatisfy({ $0.isASCII && $0.isNumber }) else {
        return NumberValidation(valid: false, reason: "Project number must contain only digits.")
    }
    // YY is the calendar year the project belongs to. A past year is
    // allowed (entering an older project), a future year is not.
    guard let yy = Int(number.prefix(2)), let currentYY = Int(currentYearSuffix(date)), yy <= currentYY else {
        return NumberValidation(valid: false, reason: "The first two digits must be the project's year (\(currentYearSuffix(date)) for this year) — not a future year.")
    }
    guard number.suffix(3) != "000" else {
        return NumberValidation(valid: false, reason: "The last three digits are the project's sequence and start at 001.")
    }
    guard !existingNumbers.contains(number) else {
        return NumberValidation(valid: false, reason: "Project number \(number) is already in use.")
    }
    return NumberValidation(valid: true, reason: nil)
}

// =====================================================================
// MARK: - File storage (mirrors src/fileStorage.js)
// =====================================================================

let projectSubfolders = ["Drawings", "BOQ", "Quotations", "Invoices", "Delivery Notes", "Documents", "Other"]

final class FileStorage {
    let documentsRoot: URL
    let companyFolderName: String
    /// Backups live with the database (Application Support/ScaffoldPro/
    /// Backups, beside data/), not among the business files in Documents.
    let backupsRoot: URL

    init(documentsRoot: URL, companyFolderName: String, backupsRoot: URL) {
        self.documentsRoot = documentsRoot
        self.companyFolderName = companyFolderName
        self.backupsRoot = backupsRoot
    }

    var appRoot: URL { documentsRoot.appendingPathComponent(companyFolderName, isDirectory: true) }
    var projectsRoot: URL { appRoot.appendingPathComponent("Projects", isDirectory: true) }
    var administrationRoot: URL { appRoot.appendingPathComponent("Administration", isDirectory: true) }
    /// Where backups were kept before they moved in with the database.
    var legacyBackupsRoot: URL { appRoot.appendingPathComponent("Backups", isDirectory: true) }

    /// Moves backups made by earlier versions (in Documents/ScaffoldPro/
    /// Backups) into the database's Backups folder, then removes the old
    /// folder if nothing else is left in it.
    func moveLegacyBackups() {
        let fm = FileManager.default
        guard legacyBackupsRoot.standardizedFileURL != backupsRoot.standardizedFileURL,
              let names = try? fm.contentsOfDirectory(atPath: legacyBackupsRoot.path) else { return }
        try? fm.createDirectory(at: backupsRoot, withIntermediateDirectories: true)
        for name in names where name.hasPrefix("ScaffoldPro-Backup_") {
            let source = legacyBackupsRoot.appendingPathComponent(name, isDirectory: true)
            var destination = backupsRoot.appendingPathComponent(name, isDirectory: true)
            var n = 2
            while fm.fileExists(atPath: destination.path) {
                destination = backupsRoot.appendingPathComponent("\(name)-\(n)", isDirectory: true)
                n += 1
            }
            try? fm.moveItem(at: source, to: destination)
        }
        for name in (try? fm.contentsOfDirectory(atPath: legacyBackupsRoot.path)) ?? [] where name == ".DS_Store" || name.hasPrefix(".inprogress-") {
            try? fm.removeItem(at: legacyBackupsRoot.appendingPathComponent(name))
        }
        if ((try? fm.contentsOfDirectory(atPath: legacyBackupsRoot.path)) ?? ["?"]).isEmpty {
            try? fm.removeItem(at: legacyBackupsRoot)
        }
    }

    func ensureRootFoldersExist() {
        let folders = [
            appRoot, projectsRoot, administrationRoot,
            administrationRoot.appendingPathComponent("Company"),
            administrationRoot.appendingPathComponent("Workers"),
            administrationRoot.appendingPathComponent("Contracts"),
            administrationRoot.appendingPathComponent("Insurance"),
            administrationRoot.appendingPathComponent("Licenses"),
            administrationRoot.appendingPathComponent("Other"),
            backupsRoot,
        ]
        for folder in folders {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
    }

    func projectFolder(_ projectNumber: String) -> URL {
        projectsRoot.appendingPathComponent(projectNumber, isDirectory: true)
    }

    @discardableResult
    func createProjectFolders(_ projectNumber: String) -> URL {
        let folder = projectFolder(projectNumber)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for sub in projectSubfolders {
            try? FileManager.default.createDirectory(at: folder.appendingPathComponent(sub, isDirectory: true), withIntermediateDirectories: true)
        }
        return folder
    }

    func copyFileIntoProject(source: URL, projectNumber: String, subfolder: String, meaningfulFilename: String) throws -> URL {
        let destFolder = projectFolder(projectNumber).appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let destination = uniqueDestination(destFolder.appendingPathComponent(meaningfulFilename))
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// A worker's own folder under Administration/Workers/<workerNumber>/
    /// (section 35's example layout — "Worker-001", "Worker-002" —
    /// except we use the shorter "W001" reference number this app
    /// generates).
    func workerFolder(_ workerNumber: String) -> URL {
        administrationRoot.appendingPathComponent("Workers", isDirectory: true).appendingPathComponent(workerNumber, isDirectory: true)
    }

    /// One of Administration's top-level category folders (Contracts,
    /// Insurance, Licenses, Company, Other, ...) for section 43's general
    /// administrative documents.
    func administrationCategoryFolder(_ category: String) -> URL {
        administrationRoot.appendingPathComponent(category, isDirectory: true)
    }

    /// General-purpose version of copyFileIntoProject for files that
    /// don't belong to a project — worker documents and administrative
    /// documents both use this.
    func copyFile(source: URL, into destFolder: URL, meaningfulFilename: String) throws -> URL {
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let destination = uniqueDestination(destFolder.appendingPathComponent(meaningfulFilename))
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// Writes generated data (a rendered PDF, typically) into a project
    /// subfolder under a meaningful filename (sections 31-32) rather than
    /// copying an existing source file.
    /// A document's PDF always has the same name (its number), so a new
    /// export replaces the previous one rather than piling up copies.
    func writeGeneratedFile(data: Data, projectNumber: String, subfolder: String, meaningfulFilename: String) throws -> URL {
        let destFolder = projectFolder(projectNumber).appendingPathComponent(subfolder, isDirectory: true)
        try FileManager.default.createDirectory(at: destFolder, withIntermediateDirectories: true)
        let destination = destFolder.appendingPathComponent(meaningfulFilename)
        try data.write(to: destination, options: .atomic)
        return destination
    }

    func uniqueDestination(_ url: URL) -> URL {
        guard FileManager.default.fileExists(atPath: url.path) else { return url }
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        let dir = url.deletingLastPathComponent()
        var counter = 2
        var candidate: URL
        repeat {
            let name = ext.isEmpty ? "\(base) (\(counter))" : "\(base) (\(counter)).\(ext)"
            candidate = dir.appendingPathComponent(name)
            counter += 1
        } while FileManager.default.fileExists(atPath: candidate.path)
        return candidate
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}

// =====================================================================
// MARK: - Database facade (mirrors the rest of db.js)
// =====================================================================

final class AppDatabase {
    /// Folder holding every *.json store — what Backup copies and Restore
    /// replaces.
    let dataDir: URL

    let clientsStore: JSONStore<Client>
    let sitesStore: JSONStore<Site>
    let projectsStore: JSONStore<Project>
    let priceListsStore: JSONStore<PriceList>
    let priceListItemsStore: JSONStore<PriceListItem>
    let boqsStore: JSONStore<BillOfQuantities>
    let boqLineItemsStore: JSONStore<BOQLineItem>
    let quotationsStore: JSONStore<Quotation>
    let quotationLineItemsStore: JSONStore<QuotationLineItem>
    let quotationBlocksStore: JSONStore<QuotationBlock>
    let invoicesStore: JSONStore<Invoice>
    let invoiceLineItemsStore: JSONStore<InvoiceLineItem>
    let deliveryNotesStore: JSONStore<DeliveryNote>
    let deliveryNoteLineItemsStore: JSONStore<DeliveryNoteLineItem>
    let settingsStore: JSONStore<CompanySettings>
    let drawingsStore: JSONStore<ProjectDrawing>
    let documentsStore: JSONStore<ProjectDocument>
    let workersStore: JSONStore<Worker>
    let workerDocumentsStore: JSONStore<WorkerDocument>
    let adminDocumentsStore: JSONStore<AdminDocument>
    let activityStore: JSONStore<ActivityEntry>
    let stockMovementsStore: JSONStore<StockMovement>
    let invoicePaymentsStore: JSONStore<InvoicePayment>
    let expensesStore: JSONStore<Expense>
    let liabilitiesStore: JSONStore<Liability>
    let liabilityPaymentsStore: JSONStore<LiabilityPayment>
    let employeesStore: JSONStore<Employee>

    init(dataDir: URL) {
        self.dataDir = dataDir
        clientsStore = JSONStore(fileURL: dataDir.appendingPathComponent("clients.json"))
        sitesStore = JSONStore(fileURL: dataDir.appendingPathComponent("sites.json"))
        projectsStore = JSONStore(fileURL: dataDir.appendingPathComponent("projects.json"))
        priceListsStore = JSONStore(fileURL: dataDir.appendingPathComponent("price_lists.json"))
        priceListItemsStore = JSONStore(fileURL: dataDir.appendingPathComponent("price_list_items.json"))
        boqsStore = JSONStore(fileURL: dataDir.appendingPathComponent("boqs.json"))
        boqLineItemsStore = JSONStore(fileURL: dataDir.appendingPathComponent("boq_line_items.json"))
        quotationsStore = JSONStore(fileURL: dataDir.appendingPathComponent("quotations.json"))
        quotationLineItemsStore = JSONStore(fileURL: dataDir.appendingPathComponent("quotation_line_items.json"))
        quotationBlocksStore = JSONStore(fileURL: dataDir.appendingPathComponent("quotation_blocks.json"))
        invoicesStore = JSONStore(fileURL: dataDir.appendingPathComponent("invoices.json"))
        invoiceLineItemsStore = JSONStore(fileURL: dataDir.appendingPathComponent("invoice_line_items.json"))
        deliveryNotesStore = JSONStore(fileURL: dataDir.appendingPathComponent("delivery_notes.json"))
        deliveryNoteLineItemsStore = JSONStore(fileURL: dataDir.appendingPathComponent("delivery_note_line_items.json"))
        settingsStore = JSONStore(fileURL: dataDir.appendingPathComponent("settings.json"))
        drawingsStore = JSONStore(fileURL: dataDir.appendingPathComponent("drawings.json"))
        documentsStore = JSONStore(fileURL: dataDir.appendingPathComponent("documents.json"))
        workersStore = JSONStore(fileURL: dataDir.appendingPathComponent("workers.json"))
        workerDocumentsStore = JSONStore(fileURL: dataDir.appendingPathComponent("worker_documents.json"))
        adminDocumentsStore = JSONStore(fileURL: dataDir.appendingPathComponent("admin_documents.json"))
        activityStore = JSONStore(fileURL: dataDir.appendingPathComponent("activity.json"))
        stockMovementsStore = JSONStore(fileURL: dataDir.appendingPathComponent("stock_movements.json"))
        invoicePaymentsStore = JSONStore(fileURL: dataDir.appendingPathComponent("invoice_payments.json"))
        expensesStore = JSONStore(fileURL: dataDir.appendingPathComponent("expenses.json"))
        liabilitiesStore = JSONStore(fileURL: dataDir.appendingPathComponent("liabilities.json"))
        liabilityPaymentsStore = JSONStore(fileURL: dataDir.appendingPathComponent("liability_payments.json"))
        employeesStore = JSONStore(fileURL: dataDir.appendingPathComponent("employees.json"))
    }

    // ---- Document rows (client/site pages, Dashboard, search) ----

    private func todayYMD() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Every BOQ, quotation, invoice and delivery note — optionally only
    /// for a set of projects — as display rows with totals worked out.
    func documentRows(projectIds: Set<String>? = nil) -> [DocRow] {
        let projects = Dictionary(projectsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let clients = Dictionary(clientsStore.readAll().map { ($0.id, $0.companyName) }, uniquingKeysWith: { a, _ in a })
        let today = todayYMD()
        // Each line-item file is read once and grouped, rather than re-read
        // for every document — search runs this on every keystroke.
        let quotationLines = Dictionary(grouping: quotationLineItemsStore.readAll(), by: { $0.quotationId })
        let invoiceLines = Dictionary(grouping: invoiceLineItemsStore.readAll(), by: { $0.invoiceId })
        var rows: [DocRow] = []
        func include(_ pid: String) -> Project? {
            guard projectIds == nil || projectIds!.contains(pid) else { return nil }
            return projects[pid]
        }
        for b in boqsStore.readAll() {
            guard let p = include(b.projectId) else { continue }
            rows.append(DocRow(id: b.id, kind: "BOQ", number: b.boqNumber, status: b.status, projectNumber: p.projectNumber,
                               projectName: p.name, clientName: clients[p.clientId], date: b.createdAt, updatedAt: b.updatedAt,
                               amount: nil, balance: nil, dueDate: nil, isOverdue: false, url: "boq-editor.html?id=\(b.id)"))
        }
        for q in quotationsStore.readAll() {
            guard let p = include(q.projectId) else { continue }
            let t = quotationMoney(q, lineItems: quotationLines[q.id] ?? [])
            rows.append(DocRow(id: q.id, kind: "Quotation", number: q.quotationNumber, status: q.status, projectNumber: p.projectNumber,
                               projectName: p.name, clientName: clients[p.clientId], date: q.quotationDate, updatedAt: q.updatedAt,
                               amount: t.total, balance: nil, dueDate: q.validUntil, isOverdue: false, url: "quotation-editor.html?id=\(q.id)",
                               charges: t.charges))
        }
        for inv in invoicesStore.readAll() {
            guard let p = include(inv.projectId) else { continue }
            let t = invoiceTotals(inv, lineItems: invoiceLines[inv.id] ?? [])
            let overdue = isInvoiceOverdue(inv, balanceDue: t.balanceDue, today: today)
            rows.append(DocRow(id: inv.id, kind: "Invoice", number: inv.invoiceNumber, status: overdue ? "Overdue" : inv.status,
                               projectNumber: p.projectNumber, projectName: p.name, clientName: clients[p.clientId],
                               date: inv.invoiceDate, updatedAt: inv.updatedAt, amount: t.total, balance: t.balanceDue,
                               dueDate: inv.dueDate, isOverdue: overdue, url: "invoice-editor.html?id=\(inv.id)"))
        }
        for dn in deliveryNotesStore.readAll() {
            guard let p = include(dn.projectId) else { continue }
            rows.append(DocRow(id: dn.id, kind: "Delivery Note", number: dn.deliveryNoteNumber, status: dn.status, projectNumber: p.projectNumber,
                               projectName: p.name, clientName: clients[p.clientId], date: dn.deliveryDate, updatedAt: dn.updatedAt,
                               amount: nil, balance: nil, dueDate: nil, isOverdue: false, url: "delivery-note-editor.html?id=\(dn.id)"))
        }
        return rows
    }

    /// Projects and documents for a client (section 10) or site (section 9).
    func partyDetail(clientId: String?, siteId: String?) -> PartyDetail {
        let clients = clientsStore.readAll()
        let sites = sitesStore.readAll()
        let projects = projectsStore.readAll()
            .filter { (clientId == nil || $0.clientId == clientId) && (siteId == nil || $0.siteId == siteId) }
            .sorted { $0.projectNumber > $1.projectNumber }
        let entries = projects.map { p in
            ProjectListEntry(id: p.id, projectNumber: p.projectNumber, name: p.name, clientId: p.clientId, siteId: p.siteId,
                             status: p.status, createdAt: p.createdAt,
                             clientName: clients.first { $0.id == p.clientId }?.companyName,
                             siteName: sites.first { $0.id == p.siteId }?.name)
        }
        let docs = documentRows(projectIds: Set(projects.map { $0.id })).sorted { $0.updatedAt > $1.updatedAt }
        return PartyDetail(projects: entries, documents: docs)
    }

    func dashboardSummary() -> DashboardSummary {
        let projects = projectsStore.readAll()
        let rows = documentRows()
        let settings = getCompanySettings()
        let invoicedQuotationIds = Set(invoicesStore.readAll().compactMap { $0.sourceQuotationId })
        let outstanding = rows.filter { $0.kind == "Quotation" && $0.status == "Issued" && !invoicedQuotationIds.contains($0.id) }
            .sorted { $0.date > $1.date }
        let unpaid = rows.filter { $0.kind == "Invoice" && ($0.balance ?? 0) > 0 && !["Draft", "Paid", "Cancelled"].contains($0.status) }
            .sorted { ($0.isOverdue ? 0 : 1, $0.dueDate ?? "") < ($1.isOverdue ? 0 : 1, $1.dueDate ?? "") }
        let unpaidTotal = unpaid.reduce(Decimal(0)) { $0 + decimalOf($1.balance ?? 0) }
        let overdue = unpaid.filter { $0.isOverdue }
        let overdueTotal = overdue.reduce(Decimal(0)) { $0 + decimalOf($1.balance ?? 0) }
        var summary = DashboardSummary(
            activeProjects: projects.filter { $0.status == "Active" }.count,
            totalProjects: projects.count,
            clientCount: clientsStore.readAll().filter { !$0.isArchived }.count,
            priceListItemCount: priceListItemsStore.readAll().filter { !$0.isArchived }.count,
            currency: settings.currency,
            outstandingQuotations: Array(outstanding.prefix(8)),
            unpaidInvoices: Array(unpaid.prefix(8)),
            unpaidTotal: doubleOf(unpaidTotal),
            overdueCount: overdue.count,
            overdueTotal: doubleOf(overdueTotal),
            recentDeliveryNotes: Array(rows.filter { $0.kind == "Delivery Note" }.sorted { $0.date > $1.date }.prefix(5)),
            recentDocuments: Array(rows.sorted { $0.updatedAt > $1.updatedAt }.prefix(8)),
            recentActivity: listActivity(projectId: nil, limit: 10)
        )
        let quotations = Dictionary(quotationsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let unsigned = rows.filter { r in
            guard r.kind == "Quotation", r.status == "Issued", let q = quotations[r.id] else { return false }
            return q.signedCopyNotNeeded != true && !(q.signedCopyPath.map { fileIsPresent($0) } ?? false)
        }.map { r -> DocRow in
            var row = r
            if invoicedQuotationIds.contains(r.id) { row.status = "Invoiced" }
            return row
        }.sorted { ($0.status == "Invoiced" ? 0 : 1, $1.date) < ($1.status == "Invoiced" ? 0 : 1, $0.date) }
        summary.awaitingSignedCopy = Array(unsigned.prefix(8))
        summary.awaitingSignedCopyCount = unsigned.count
        return summary
    }

    // ---- Signed copies of quotations ----

    /// Records the signed copy the client returned (already copied into the
    /// project folder). Takes it off the Dashboard's reminder.
    func setQuotationSignedCopy(id: String, path: String?) -> String? {
        var qs = quotationsStore.readAll()
        guard let i = qs.firstIndex(where: { $0.id == id }) else { return "Quotation not found." }
        qs[i].signedCopyPath = path
        qs[i].signedCopyAt = path == nil ? nil : nowISO()
        if path != nil { qs[i].signedCopyNotNeeded = nil }
        qs[i].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
        logActivity(projectId: qs[i].projectId, path == nil ? "Signed copy removed from quotation" : "Signed quotation received",
                    reference: qs[i].quotationNumber)
        return nil
    }

    func setQuotationSignedCopyNotNeeded(id: String, notNeeded: Bool) -> String? {
        var qs = quotationsStore.readAll()
        guard let i = qs.firstIndex(where: { $0.id == id }) else { return "Quotation not found." }
        qs[i].signedCopyNotNeeded = notNeeded ? true : nil
        quotationsStore.writeAll(qs)
        return nil
    }

    /// Global search (section 44) across everything, best matches first.
    func search(_ rawQuery: String, limit: Int = 40) -> [SearchResult] {
        let q = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        func matches(_ fields: String?...) -> Bool { fields.contains { ($0 ?? "").lowercased().contains(q) } }
        let clients = clientsStore.readAll()
        let sites = sitesStore.readAll()
        let projects = projectsStore.readAll()
        func projectOf(_ id: String) -> Project? { projects.first { $0.id == id } }
        var results: [SearchResult] = []

        for p in projects.sorted(by: { $0.projectNumber > $1.projectNumber }) {
            let client = clients.first { $0.id == p.clientId }?.companyName
            let site = sites.first { $0.id == p.siteId }?.name
            if matches(p.projectNumber, p.name, client, site, p.projectManager, p.projectDescription) {
                results.append(SearchResult(kind: "Project", title: "\(p.projectNumber) — \(p.name)", subtitle: [client, site, p.status].compactMap { $0 }.joined(separator: " · "), url: "project-detail.html?number=\(p.projectNumber)"))
            }
        }
        for c in clients where !c.isArchived && matches(c.companyName, c.contactPerson, c.email, c.phone, c.clientReference, c.city) {
            results.append(SearchResult(kind: "Client", title: c.companyName, subtitle: [c.contactPerson, c.phone].compactMap { $0 }.joined(separator: " · "), url: "clients.html?id=\(c.id)"))
        }
        for st in sites where !st.isArchived && matches(st.name, st.address, st.city, st.siteReference, st.contactPerson) {
            results.append(SearchResult(kind: "Site", title: st.name, subtitle: [st.address, st.city].compactMap { $0 }.joined(separator: ", "), url: "sites.html?id=\(st.id)"))
        }
        for d in documentRows() where matches(d.number, d.projectNumber, d.projectName, d.clientName) {
            results.append(SearchResult(kind: d.kind, title: d.number, subtitle: "\(d.projectNumber) — \(d.projectName) · \(d.status)", url: d.url))
        }
        for w in workersStore.readAll() where matches(w.name, w.workerNumber, w.position, w.phone) {
            results.append(SearchResult(kind: "Worker", title: "\(w.workerNumber) \(w.name)", subtitle: w.position ?? "", url: "admin.html?worker=\(w.id)"))
        }
        for d in drawingsStore.readAll() where !d.isArchived && matches(d.originalName, d.description) {
            if let p = projectOf(d.projectId) {
                results.append(SearchResult(kind: "Drawing", title: d.originalName, subtitle: "\(p.projectNumber) — \(p.name)", url: "project-detail.html?number=\(p.projectNumber)#drawings"))
            }
        }
        for d in documentsStore.readAll() where !d.isArchived && matches(d.originalName, d.description, d.category) {
            if let p = projectOf(d.projectId) {
                results.append(SearchResult(kind: "Document", title: d.originalName, subtitle: "\(p.projectNumber) — \(d.category)", url: "project-detail.html?number=\(p.projectNumber)#documents"))
            }
        }
        for d in adminDocumentsStore.readAll() where !d.isArchived && matches(d.originalName, d.description, d.category) {
            results.append(SearchResult(kind: "Company Document", title: d.originalName, subtitle: d.category, url: "admin.html"))
        }
        let lists = Dictionary(priceListsStore.readAll().map { ($0.sourceKey, $0.displayName) }, uniquingKeysWith: { a, _ in a })
        var priceHits = 0
        for item in priceListItemsStore.readAll() where !item.isArchived && matches(item.itemName, item.category) {
            guard priceHits < 12 else { break }
            priceHits += 1
            let encoded = item.itemName.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            results.append(SearchResult(kind: "Material", title: item.itemName, subtitle: [lists[item.sourceKey], item.category].compactMap { $0 }.joined(separator: " · "), url: "price-lists.html?source=\(item.sourceKey)&q=\(encoded)"))
        }
        return Array(results.prefix(limit))
    }

    // ---- Activity history (section 45) ----

    func logActivity(projectId: String?, _ action: String, reference: String? = nil) {
        activityStore.insert(ActivityEntry(id: makeId("act"), projectId: projectId, action: action, reference: reference, createdAt: nowISO(),
                                           by: TeamSync.current == nil ? nil : TeamSync.memberName))
    }

    func listActivity(projectId: String?, limit: Int) -> [ActivityRow] {
        let projects = projectsStore.readAll()
        return activityStore.readAll()
            .filter { projectId == nil || $0.projectId == projectId }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { e in
                let p = projects.first { $0.id == e.projectId }
                return ActivityRow(id: e.id, projectNumber: p?.projectNumber, projectName: p?.name, action: e.action, reference: e.reference, createdAt: e.createdAt, by: e.by)
            }
    }

    private func text(_ payload: [String: Any], _ key: String) -> String? {
        guard let v = (payload[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }

    // ---- Clients ----
    func listClients(includeArchived: Bool = false) -> [Client] {
        clientsStore.readAll().filter { includeArchived || !$0.isArchived }
            .sorted { $0.companyName.localizedCaseInsensitiveCompare($1.companyName) == .orderedAscending }
    }
    func allClients() -> [Client] { clientsStore.readAll() }

    func updateClient(id: String, payload: [String: Any]) -> String? {
        var items = clientsStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Client not found." }
        guard let name = text(payload, "companyName") else { return "Company name is required." }
        items[i].companyName = name
        items[i].contactPerson = text(payload, "contactPerson")
        items[i].address = text(payload, "address")
        items[i].phone = text(payload, "phone")
        items[i].email = text(payload, "email")
        items[i].notes = text(payload, "notes")
        items[i].clientReference = text(payload, "clientReference")
        items[i].city = text(payload, "city")
        items[i].postalCode = text(payload, "postalCode")
        items[i].country = text(payload, "country")
        items[i].vatNumber = text(payload, "vatNumber")
        items[i].billingInfo = text(payload, "billingInfo")
        items[i].addressLine2 = text(payload, "addressLine2")
        items[i].addressLine3 = text(payload, "addressLine3")
        switch markupField(payload["defaultMarkupPercent"]) {
        case .failure(let e): return e.message
        case .success(let m): items[i].defaultMarkupPercent = m
        }
        clientsStore.writeAll(items)
        return nil
    }

    /// A default markup typed in the client form: blank or 0 = none.
    private func markupField(_ raw: Any?) -> Result<Double?, WorkerError> {
        let value: Double?
        if let n = raw as? Double { value = n }
        else if let t = nonBlank(raw as? String) {
            guard let n = Double(t.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)) else {
                return .failure(WorkerError(message: "Enter the default markup as a number, e.g. 15 for 15%."))
            }
            value = n
        } else { value = nil }
        guard let m = value, m != 0 else { return .success(nil) }
        guard m > 0, m <= 1000 else { return .failure(WorkerError(message: "Enter a default markup between 0% and 1000%.")) }
        return .success(m)
    }

    /// The default markup of a project's client, if it has one.
    func clientDefaultMarkup(projectId: String) -> Double? {
        guard let project = projectsStore.readAll().first(where: { $0.id == projectId }) else { return nil }
        return getClient(id: project.clientId)?.defaultMarkupPercent
    }

    func setClientArchived(id: String, archived: Bool) -> String? {
        var items = clientsStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Client not found." }
        items[i].isArchived = archived
        clientsStore.writeAll(items)
        return nil
    }
    func getClient(id: String) -> Client? {
        clientsStore.readAll().first { $0.id == id }
    }
    func createClient(_ payload: [String: Any]) -> Client {
        var client = Client(
            id: makeId("client"),
            // Blank form fields are stored as nil, not "" — otherwise PDFs
            // print empty "Attn:" / address lines for new clients.
            companyName: text(payload, "companyName") ?? "",
            contactPerson: text(payload, "contactPerson"),
            address: text(payload, "address"),
            phone: text(payload, "phone"),
            email: text(payload, "email"),
            notes: text(payload, "notes"),
            isArchived: false,
            createdAt: nowISO(),
            clientReference: text(payload, "clientReference"), city: text(payload, "city"),
            postalCode: text(payload, "postalCode"), country: text(payload, "country"),
            vatNumber: text(payload, "vatNumber"), billingInfo: text(payload, "billingInfo")
        )
        client.addressLine2 = text(payload, "addressLine2")
        client.addressLine3 = text(payload, "addressLine3")
        if case .success(let m) = markupField(payload["defaultMarkupPercent"]) { client.defaultMarkupPercent = m }
        clientsStore.insert(client)
        return client
    }

    // ---- Sites ----
    func listSites(includeArchived: Bool = false) -> [Site] {
        sitesStore.readAll().filter { includeArchived || !$0.isArchived }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    func allSites() -> [Site] { sitesStore.readAll() }

    func updateSite(id: String, payload: [String: Any]) -> String? {
        var items = sitesStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Site not found." }
        guard let name = text(payload, "name") else { return "Site name is required." }
        items[i].name = name
        items[i].address = text(payload, "address")
        items[i].contactPerson = text(payload, "contactPerson")
        items[i].phone = text(payload, "phone")
        items[i].notes = text(payload, "notes")
        items[i].siteReference = text(payload, "siteReference")
        items[i].city = text(payload, "city")
        items[i].postalCode = text(payload, "postalCode")
        items[i].country = text(payload, "country")
        items[i].email = text(payload, "email")
        sitesStore.writeAll(items)
        return nil
    }

    func setSiteArchived(id: String, archived: Bool) -> String? {
        var items = sitesStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Site not found." }
        items[i].isArchived = archived
        sitesStore.writeAll(items)
        return nil
    }
    func getSite(id: String) -> Site? {
        sitesStore.readAll().first { $0.id == id }
    }
    func createSite(_ payload: [String: Any]) -> Site {
        let site = Site(
            id: makeId("site"),
            name: text(payload, "name") ?? "",
            address: text(payload, "address"),
            contactPerson: text(payload, "contactPerson"),
            phone: text(payload, "phone"),
            notes: text(payload, "notes"),
            isArchived: false,
            createdAt: nowISO(),
            siteReference: text(payload, "siteReference"), city: text(payload, "city"),
            postalCode: text(payload, "postalCode"), country: text(payload, "country"),
            email: text(payload, "email")
        )
        sitesStore.insert(site)
        return site
    }

    // ---- Projects ----
    func allProjectNumbers() -> [String] {
        projectsStore.readAll().map { $0.projectNumber }
    }
    func listProjectsRaw() -> [Project] {
        projectsStore.readAll().sorted { $0.projectNumber > $1.projectNumber }
    }
    func getProject(id: String) -> Project? {
        projectsStore.readAll().first { $0.id == id }
    }

    func getProjectByNumber(_ number: String) -> Project? {
        projectsStore.readAll().first { $0.projectNumber == number }
    }
    func createProject(projectNumber: String, name: String, clientId: String, siteId: String) -> Project {
        let project = Project(
            id: makeId("project"), projectNumber: projectNumber, name: name,
            clientId: clientId, siteId: siteId, projectDescription: nil,
            startDate: nil, expectedCompletionDate: nil, projectManager: nil,
            internalNotes: nil, status: "Planning", createdAt: nowISO()
        )
        projectsStore.insert(project)
        logActivity(projectId: project.id, "Project created", reference: "\(projectNumber) — \(name)")
        return project
    }
    /// Section 17: editing a project's details after creation. The
    /// project number never changes (section 12 — permanent identifier).
    func updateProject(id: String, payload: [String: Any], logChange: Bool = true) -> String? {
        var items = projectsStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Project not found." }
        if payload.keys.contains("name") {
            guard let name = text(payload, "name") else { return "Project name is required." }
            items[i].name = name
        }
        if let clientId = text(payload, "clientId") {
            guard clientsStore.readAll().contains(where: { $0.id == clientId }) else { return "Choose a valid client." }
            items[i].clientId = clientId
        }
        if let siteId = text(payload, "siteId") {
            guard sitesStore.readAll().contains(where: { $0.id == siteId }) else { return "Choose a valid site." }
            items[i].siteId = siteId
        }
        if payload.keys.contains("projectDescription") { items[i].projectDescription = text(payload, "projectDescription") }
        if payload.keys.contains("startDate") { items[i].startDate = text(payload, "startDate") }
        if payload.keys.contains("expectedCompletionDate") { items[i].expectedCompletionDate = text(payload, "expectedCompletionDate") }
        if payload.keys.contains("projectManager") { items[i].projectManager = text(payload, "projectManager") }
        if payload.keys.contains("internalNotes") { items[i].internalNotes = text(payload, "internalNotes") }
        projectsStore.writeAll(items)
        if logChange { logActivity(projectId: id, "Project details edited") }
        return nil
    }

    /// A new project code (number). Draft documents numbered with the old
    /// code are renumbered with the new one; issued documents keep the
    /// numbers they were sent with. (The project's folder is renamed and
    /// file paths re-pointed by the caller.)
    func setProjectNumber(id: String, to newNumber: String) {
        var items = projectsStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        let old = items[i].projectNumber
        items[i].projectNumber = newNumber
        projectsStore.writeAll(items)
        // The old code where it stands on its own among the digits
        // ("BQ26210-001", "26210-BOQ-001"), not inside another number.
        let pattern = "(?<![0-9])" + NSRegularExpression.escapedPattern(for: old) + "(?![0-9])"
        let regex = try? NSRegularExpression(pattern: pattern)
        let renumber: (String) -> String = { number in
            guard let regex = regex else { return number }
            return regex.stringByReplacingMatches(in: number, range: NSRange(number.startIndex..., in: number),
                                                  withTemplate: NSRegularExpression.escapedTemplate(for: newNumber))
        }
        var boqs = boqsStore.readAll()
        for j in boqs.indices where boqs[j].projectId == id && boqs[j].status == "Draft" { boqs[j].boqNumber = renumber(boqs[j].boqNumber) }
        boqsStore.writeAll(boqs)
        var qs = quotationsStore.readAll()
        for j in qs.indices where qs[j].projectId == id && qs[j].status == "Draft" { qs[j].quotationNumber = renumber(qs[j].quotationNumber) }
        quotationsStore.writeAll(qs)
        var invs = invoicesStore.readAll()
        for j in invs.indices where invs[j].projectId == id && invs[j].status == "Draft" { invs[j].invoiceNumber = renumber(invs[j].invoiceNumber) }
        invoicesStore.writeAll(invs)
        var dns = deliveryNotesStore.readAll()
        for j in dns.indices where dns[j].projectId == id && dns[j].status == "Draft" { dns[j].deliveryNoteNumber = renumber(dns[j].deliveryNoteNumber) }
        deliveryNotesStore.writeAll(dns)
        logActivity(projectId: id, "Project code changed to \(newNumber)", reference: "was \(old)")
    }

    func updateProjectStatus(id: String, status: String) {
        var items = projectsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let previous = items[index].status
        items[index].status = status
        projectsStore.writeAll(items)
        if previous != status { logActivity(projectId: id, "Status changed to \(status)", reference: "was \(previous)") }
    }

    // ---- Price lists ----
    var priceListsAreSeeded: Bool { !priceListsStore.isEmpty }

    /// Items with no Chinese name yet get one from `chineseMaterialName`
    /// (the words on the official SP Material List). Names typed in, or
    /// cleared on purpose, are left alone.
    func fillChineseNamesIfNeeded() {
        var items = priceListItemsStore.readAll()
        var changed = false
        for i in items.indices where items[i].chineseName == nil {
            if let zh = chineseMaterialName(items[i].itemName) { items[i].chineseName = zh; changed = true }
        }
        if changed { priceListItemsStore.writeAll(items) }
    }

    /// Whether documents show materials' Chinese names (Settings; default yes).
    var chineseNamesOnDocuments: Bool { getCompanySettings().chineseNamesOnDocuments ?? true }

    /// Each line's Chinese name (by line id), from its material-list item or,
    /// for a line typed in, from its description.
    func chineseNames<Line>(for lines: [Line], id: (Line) -> String, itemId: (Line) -> String?, description: (Line) -> String) -> [String: String] {
        let byId = Dictionary(priceListItemsStore.readAll().map { ($0.id, $0.chineseName) }, uniquingKeysWith: { a, _ in a })
        var out: [String: String] = [:]
        for line in lines {
            let fromItem = itemId(line).flatMap { byId[$0] ?? nil }
            // "" on the item: no Chinese name, on purpose.
            if let zh = fromItem { if !zh.isEmpty { out[id(line)] = zh }; continue }
            if let zh = chineseMaterialName(description(line)) { out[id(line)] = zh }
        }
        return out
    }

    /// Gives the price lists, and the items on them, ids made from what
    /// they are (a list: its source; an item: its source, code and name), so
    /// they're the same on every Mac, and changes every reference to them in
    /// the other stores. Done before this Mac's material list first goes to
    /// iCloud Drive: the same list made on different Macs then lines up,
    /// item by item, instead of appearing twice.
    func canonicalizePriceListIds() {
        func stableHash(_ text: String) -> String {
            var h: UInt64 = 0xcbf29ce484222325
            for b in text.utf8 { h ^= UInt64(b); h = h &* 0x100000001b3 }
            return String(h, radix: 36)
        }
        func norm(_ text: String) -> String {
            text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        }
        var map: [String: String] = [:]
        var lists = priceListsStore.readAll()
        var taken = Set<String>()
        for i in lists.indices {
            let wanted = "pricelist_" + stableHash(norm(lists[i].sourceKey))
            guard !taken.contains(wanted) else { taken.insert(lists[i].id); continue }
            taken.insert(wanted)
            if lists[i].id != wanted { map[lists[i].id] = wanted; lists[i].id = wanted }
        }
        var items = priceListItemsStore.readAll()
        taken = []
        for i in items.indices {
            let key = [items[i].sourceKey, items[i].itemCode, items[i].itemName].map(norm).joined(separator: "|")
            let wanted = "item_" + stableHash(key)
            guard !taken.contains(wanted) else { taken.insert(items[i].id); continue }
            taken.insert(wanted)
            if items[i].id != wanted { map[items[i].id] = wanted; items[i].id = wanted }
        }
        guard !map.isEmpty else { return }
        priceListsStore.writeAll(lists)
        priceListItemsStore.writeAll(items)
        // Every other store: a value that is exactly an old id becomes the new one.
        func replaced(_ value: Any) -> Any {
            switch value {
            case let text as String: return map[text] ?? text
            case let dict as [String: Any]: return dict.mapValues(replaced)
            case let array as [Any]: return array.map(replaced)
            default: return value
            }
        }
        let files = ((try? FileManager.default.contentsOfDirectory(at: dataDir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && !TeamSync.materialStores.contains($0.lastPathComponent) && !$0.lastPathComponent.contains(".unreadable-") }
        for url in files {
            guard let data = try? Data(contentsOf: url), let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            let changed = replaced(json)
            let before = try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys, .withoutEscapingSlashes])
            guard let out = try? JSONSerialization.data(withJSONObject: changed, options: [.sortedKeys, .withoutEscapingSlashes]),
                  out != before else { continue }
            try? out.write(to: url, options: .atomic)
        }
    }

    func seedPriceList(sourceKey: String, displayName: String, currency: String, items: [SeedPriceItem]) {
        let priceList = PriceList(id: makeId("pricelist"), sourceKey: sourceKey, displayName: displayName, currency: currency, createdAt: nowISO())
        priceListsStore.insert(priceList)

        let mapped: [PriceListItem] = items.map { seed in
            PriceListItem(
                id: makeId("item"), sourceKey: sourceKey, itemCode: seed.itemCode,
                category: seed.category, itemName: seed.name, unit: "pc",
                weightKg: seed.weightKg, unitSalePrice: seed.unitSalePriceHKD,
                unitRentalPrice: seed.unitRentalPriceHKD, applicableTypes: seed.applicableTypes,
                notes: seed.spProductNo.map { "SP Product No.: \($0)" }, isArchived: false
            )
        }
        priceListItemsStore.insertMany(mapped)
    }

    func listPriceLists() -> [PriceList] {
        priceListsStore.readAll()
    }

    func searchPriceListItems(sourceKey: String, query: String, category: String?) -> [PriceListItem] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return priceListItemsStore.readAll()
            .filter { $0.sourceKey == sourceKey && !$0.isArchived }
            .filter { category == nil || category == "" || $0.category == category }
            .filter { q.isEmpty || $0.itemName.lowercased().contains(q) || $0.itemCode.lowercased().contains(q)
                || ($0.chineseName?.contains(q) ?? false) }
            .sorted { a, b in
                // The order they were dragged into; the rest by item code.
                let oa = a.sortOrder ?? Int.max, ob = b.sortOrder ?? Int.max
                if oa != ob { return oa < ob }
                return a.itemCode.localizedStandardCompare(b.itemCode) == .orderedAscending
            }
    }

    /// The items of one category in their new order (dragged in the
    /// Material List).
    func reorderPriceListItems(ids: [String]) -> String? {
        var items = priceListItemsStore.readAll()
        let place = Dictionary(ids.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
        var changed = false
        for i in items.indices {
            if let p = place[items[i].id], items[i].sortOrder != p {
                items[i].sortOrder = p
                changed = true
            }
        }
        if changed { priceListItemsStore.writeAll(items) }
        return nil
    }

    private func uniqueItemCode(sourceKey: String, preferred: String?) -> String {
        let used = Set(priceListItemsStore.readAll().filter { $0.sourceKey == sourceKey }.map { $0.itemCode.lowercased() })
        if let p = preferred?.trimmingCharacters(in: .whitespacesAndNewlines), !p.isEmpty, !used.contains(p.lowercased()) { return p }
        let base = preferred?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? preferred! + "-" : "C-"
        var n = 1
        while used.contains("\(base)\(String(format: "%03d", n))".lowercased()) { n += 1 }
        return "\(base)\(String(format: "%03d", n))"
    }

    /// Section 8: "Add item".
    func createPriceListItem(sourceKey: String, payload: [String: Any]) -> Result<PriceListItem, WorkerError> {
        guard priceListsStore.readAll().contains(where: { $0.sourceKey == sourceKey }) else { return .failure(WorkerError(message: "Price list not found.")) }
        guard let name = text(payload, "itemName") else { return .failure(WorkerError(message: "Item name is required.")) }
        let item = PriceListItem(
            id: makeId("pli"), sourceKey: sourceKey,
            itemCode: uniqueItemCode(sourceKey: sourceKey, preferred: text(payload, "itemCode")),
            category: text(payload, "category"), itemName: name, unit: text(payload, "unit") ?? "pc",
            weightKg: payload["weightKg"] as? Double, unitSalePrice: payload["unitSalePrice"] as? Double,
            unitRentalPrice: payload["unitRentalPrice"] as? Double, applicableTypes: [], notes: nil, isArchived: false,
            // Typed in, or else worked out from the English name.
            chineseName: text(payload, "chineseName") ?? chineseMaterialName(name)
        )
        priceListItemsStore.insert(item)
        return .success(item)
    }

    /// Section 8: "Delete/archive item". Archived, never erased — BOQs,
    /// quotations and invoices keep their own copies of the details.
    func archivePriceListItem(id: String) -> String? {
        var items = priceListItemsStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Item not found." }
        items[i].isArchived = true
        priceListItemsStore.writeAll(items)
        return nil
    }

    /// Section 8: "Duplicate item".
    func duplicatePriceListItem(id: String) -> Result<PriceListItem, WorkerError> {
        guard let original = priceListItemsStore.readAll().first(where: { $0.id == id }) else { return .failure(WorkerError(message: "Item not found.")) }
        var copy = original
        copy.id = makeId("pli")
        copy.itemCode = uniqueItemCode(sourceKey: original.sourceKey, preferred: original.itemCode)
        copy.itemName = original.itemName + " (copy)"
        copy.isArchived = false
        var items = priceListItemsStore.readAll()
        // Right after the original, if the list has been put in order.
        if let order = original.sortOrder {
            for i in items.indices where items[i].sourceKey == original.sourceKey && items[i].category == original.category {
                if let o = items[i].sortOrder, o > order { items[i].sortOrder = o + 1 }
            }
            copy.sortOrder = order + 1
        }
        items.append(copy)
        priceListItemsStore.writeAll(items)
        return .success(copy)
    }

    /// Works out what an import would do (or does it, when apply is true):
    /// rows match existing items by code, else by name; matched items get
    /// their details and prices updated, the rest are added.
    func applyPriceImport(sourceKey: String, rows: [ParsedPriceRow], apply: Bool) -> (added: Int, updated: Int) {
        var items = priceListItemsStore.readAll()
        var added = 0, updated = 0
        var byCode: [String: Int] = [:]
        var byName: [String: Int] = [:]
        for (i, item) in items.enumerated() where item.sourceKey == sourceKey {
            byCode[item.itemCode.lowercased()] = byCode[item.itemCode.lowercased()] ?? i
            byName[item.itemName.lowercased()] = byName[item.itemName.lowercased()] ?? i
        }
        var usedCodes = Set(byCode.keys)
        for row in rows {
            let match = row.code.flatMap { byCode[$0.lowercased()] } ?? byName[row.name.lowercased()]
            if let i = match {
                updated += 1
                guard apply else { continue }
                items[i].itemName = row.name
                if let v = row.category { items[i].category = v }
                if let v = row.unit { items[i].unit = v }
                if let v = row.weightKg { items[i].weightKg = v }
                if let v = row.salePrice { items[i].unitSalePrice = v }
                if let v = row.rentalPrice { items[i].unitRentalPrice = v }
                items[i].isArchived = false
            } else {
                added += 1
                var code = row.code ?? ""
                if code.isEmpty || usedCodes.contains(code.lowercased()) {
                    var n = usedCodes.count + 1
                    repeat { code = "IMP-\(String(format: "%04d", n))"; n += 1 } while usedCodes.contains(code.lowercased())
                }
                usedCodes.insert(code.lowercased())
                guard apply else { continue }
                let item = PriceListItem(
                    id: makeId("pli"), sourceKey: sourceKey, itemCode: code, category: row.category, itemName: row.name,
                    unit: row.unit ?? "pc", weightKg: row.weightKg, unitSalePrice: row.salePrice, unitRentalPrice: row.rentalPrice,
                    applicableTypes: [], notes: nil, isArchived: false
                )
                items.append(item)
                byCode[code.lowercased()] = items.count - 1
                if row.code == nil { byName[row.name.lowercased()] = items.count - 1 }
            }
        }
        if apply { priceListItemsStore.writeAll(items) }
        return (added, updated)
    }

    func allPriceListItems(sourceKey: String) -> [PriceListItem] {
        priceListItemsStore.readAll().filter { $0.sourceKey == sourceKey && !$0.isArchived }
            .sorted { $0.itemCode.localizedStandardCompare($1.itemCode) == .orderedAscending }
    }

    /// Multiplier from each price list's currency to the base currency
    /// (e.g. SCAFOM in EUR × 8.93 → HKD). 1 for lists already in base.
    func conversionRates() -> [String: Double] {
        let settings = getCompanySettings()
        var map: [String: Double] = [:]
        for list in priceListsStore.readAll() {
            map[list.sourceKey] = list.currency == settings.currency ? 1 : (settings.exchangeRates?[list.currency] ?? 1)
        }
        return map
    }

    /// A price-list item's Sale or Rental price in the base currency,
    /// rounded to the cent (falls back to the other price if one is blank).
    func basePrice(_ item: PriceListItem, mode: String, rates: [String: Double]) -> Double? {
        let primary = mode == "Sale" ? item.unitSalePrice : item.unitRentalPrice
        let fallback = mode == "Sale" ? item.unitRentalPrice : item.unitSalePrice
        guard let raw = primary ?? fallback else { return nil }
        let rate = rates[item.sourceKey] ?? 1
        return doubleOf(roundToCents(decimalOf(raw) * decimalOf(rate)))
    }

    /// The same list of items with prices converted to the base currency —
    /// what the BOQ / quotation / invoice pickers use.
    func inBaseCurrency(_ items: [PriceListItem]) -> [PriceListItem] {
        let rates = conversionRates()
        return items.map { item in
            let rate = rates[item.sourceKey] ?? 1
            guard rate != 1 else { return item }
            var c = item
            c.unitSalePrice = item.unitSalePrice.map { doubleOf(roundToCents(decimalOf($0) * decimalOf(rate))) }
            c.unitRentalPrice = item.unitRentalPrice.map { doubleOf(roundToCents(decimalOf($0) * decimalOf(rate))) }
            return c
        }
    }

    /// One-off correction: the SCAFOM list was first loaded labelled HKD,
    /// but its prices are in euros (the company workbook's "Unit Sale Price
    /// (EUR)"). Relabel it so prices convert correctly.
    func fixScafomCurrencyIfNeeded() {
        var lists = priceListsStore.readAll()
        guard let i = lists.firstIndex(where: { $0.sourceKey == "SCAFOM" }), lists[i].currency != "EUR" else { return }
        lists[i].currency = "EUR"
        priceListsStore.writeAll(lists)
        var settings = getCompanySettings()
        if settings.exchangeRates?["EUR"] == nil {
            settings.exchangeRates = (settings.exchangeRates ?? [:]).merging(["EUR": 8.93]) { a, _ in a }
            settingsStore.writeAll([settings])
        }
    }

    /// One-time update: the standard delivery charge is HK$3,800 per truck
    /// per trip (confirmed by the owner). Installs that saved the earlier
    /// default of 1,200 (or none) are moved to 3,800 once; anything set by
    /// hand afterwards is left alone.
    func applyDeliveryChargeUpdateIfNeeded() {
        let key = "ScaffoldPro.deliveryCharge3800Applied"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        var settings = getCompanySettings()
        if settings.standardDeliveryCharge == nil || settings.standardDeliveryCharge == 1200 {
            settings.standardDeliveryCharge = 3800
            settingsStore.writeAll([settings])
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Once: quotations whose own payment terms were typed in (not just the
    /// Settings default) get key terms of their own — the standard key
    /// terms with those payment terms as the Payment term — so they print
    /// as before now that each quotation has key terms instead.
    func movePaymentTermsIntoKeyTermsIfNeeded() {
        let key = "ScaffoldPro.paymentTermsMovedToKeyTerms"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let settings = getCompanySettings()
        let standard = settings.quotationTerms ?? defaultQuotationTerms
        var qs = quotationsStore.readAll()
        var changed = false
        for i in qs.indices where nonBlank(qs[i].keyTerms) == nil {
            guard let pt = nonBlank(qs[i].paymentTerms), pt != nonBlank(settings.defaultPaymentTerms) else { continue }
            qs[i].keyTerms = keyTermsText(standard, withPaymentTerms: pt)
            changed = true
        }
        if changed { quotationsStore.writeAll(qs) }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Section 8's "Edit item" — item code is intentionally left alone
    /// here (it's the identifier everything else keys off), everything
    /// else is editable.
    func updatePriceListItem(id: String, itemName: String, category: String?, unit: String, unitSalePrice: Double?, unitRentalPrice: Double?, weightKg: Double? = nil, updateWeight: Bool = false,
                             chineseName: String? = nil) -> String? {
        var items = priceListItemsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Item not found." }
        let trimmedName = itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return "Item name is required." }
        let trimmedUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedUnit.isEmpty else { return "Unit is required." }
        items[index].itemName = trimmedName
        let trimmedCategory = category?.trimmingCharacters(in: .whitespacesAndNewlines)
        items[index].category = (trimmedCategory?.isEmpty ?? true) ? nil : trimmedCategory
        items[index].unit = trimmedUnit
        items[index].unitSalePrice = unitSalePrice
        items[index].unitRentalPrice = unitRentalPrice
        if updateWeight { items[index].weightKg = weightKg }
        // "" = no Chinese name (kept that way, not filled in again).
        if let zh = chineseName { items[index].chineseName = zh.trimmingCharacters(in: .whitespacesAndNewlines) }
        priceListItemsStore.writeAll(items)
        return nil
    }

    /// Pins an item to the top of the document pickers (or unpins it).
    func setPriceListItemPinned(id: String, pinned: Bool) -> String? {
        var items = priceListItemsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Item not found." }
        items[index].isPinned = pinned ? true : nil
        priceListItemsStore.writeAll(items)
        return nil
    }

    // ---- Bills of Quantities (Phase 7) ----

    private func lineItems(for boqId: String) -> [BOQLineItem] {
        boqLineItemsStore.readAll()
            .filter { $0.boqId == boqId }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    private func grandTotal(for boqId: String) -> Double {
        boqMoneyTotal(lineItems(for: boqId))
    }

    private func boqMoneyTotal(_ items: [BOQLineItem]) -> Double {
        let boqs = Dictionary(boqsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let up = markupRoundsUp
        return doubleOf(items.reduce(Decimal(0)) { $0 + lineAmount(quantity: $1.quantity, unitPrice: boqEffectiveRate($1, boq: boqs[$1.boqId], roundUp: up)) })
    }

    /// Marked-up prices round up (Settings › Standard Quotation) or off.
    var markupRoundsUp: Bool { getCompanySettings().markupRoundUp == true }

    /// A BOQ line's rate before its discount: its price with the BOQ's
    /// mark-up, rounded to 0.1 as on a quotation.
    func boqMarkedUpRate(_ line: BOQLineItem, boq: BillOfQuantities?, roundUp: Bool? = nil) -> Double {
        guard let boq = boq, boq.markupOnRates == true else { return line.appliedUnitPrice }
        return markedUpPrice(line.appliedUnitPrice, markupPercent: boq.markupPercent, roundUp: roundUp ?? markupRoundsUp)
    }

    /// A BOQ line's unit rate as charged: with the BOQ's mark-up, then its
    /// discount (to the cent).
    func boqEffectiveRate(_ line: BOQLineItem, boq: BillOfQuantities? = nil, roundUp: Bool? = nil) -> Double {
        let owner = boq ?? getBOQ(id: line.boqId)
        let marked = boqMarkedUpRate(line, boq: owner, roundUp: roundUp)
        let rate = decimalOf(marked)
        let value = decimalOf(max(0, line.discountValue ?? 0))
        let discounted: Decimal
        switch line.discountType {
        case "Percent": discounted = rate - rate * min(value, 100) / 100
        case "Amount": discounted = rate - value
        default: return marked
        }
        return doubleOf(roundToCents(max(0, discounted)))
    }

    /// Discount on a BOQ line's unit rate (Draft only).
    func updateBOQLineDiscount(id: String, type: String?, value: Double?) -> String? {
        var items = boqLineItemsStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        guard let boq = getBOQ(id: items[i].boqId) else { return "BOQ not found." }
        guard boq.status == "Draft" else { return "This BOQ is issued and can no longer be edited." }
        let kind = type ?? "None"
        guard ["None", "Percent", "Amount"].contains(kind) else { return "Invalid discount type." }
        if kind == "None" {
            items[i].discountType = nil
            items[i].discountValue = nil
        } else {
            let v = value ?? 0
            guard v > 0 else { return "Enter a discount greater than zero." }
            if kind == "Percent", v > 100 { return "A percentage discount can't be more than 100%." }
            if kind == "Amount", v > boqMarkedUpRate(items[i], boq: boq) { return "The discount can't be more than the unit rate." }
            items[i].discountType = kind
            items[i].discountValue = doubleOf(roundToCents(decimalOf(v)))
        }
        boqLineItemsStore.writeAll(items)
        touchBOQ(boq.id)
        return nil
    }

    /// The rates listed after the BQ sheet's total (nil removes them).
    func setBOQRatesSection(id: String, section: BOQRatesSection?) -> String? {
        var boqs = boqsStore.readAll()
        guard let i = boqs.firstIndex(where: { $0.id == id }) else { return "BOQ not found." }
        guard boqs[i].status == "Draft" else { return "This BOQ is issued and can no longer be edited." }
        boqs[i].ratesSection = section
        boqs[i].updatedAt = nowISO()
        boqsStore.writeAll(boqs)
        return nil
    }

    /// The amounts added after the subtotal (nil removes the section).
    func setBOQCharges(id: String, charges: [BOQCharge]?) -> String? {
        var boqs = boqsStore.readAll()
        guard let i = boqs.firstIndex(where: { $0.id == id }) else { return "BOQ not found." }
        guard boqs[i].status == "Draft" else { return "This BOQ is issued and can no longer be edited." }
        boqs[i].charges = charges
        boqs[i].updatedAt = nowISO()
        boqsStore.writeAll(boqs)
        return nil
    }

    /// The sum of a BOQ's charges, to the cent.
    func boqChargesTotal(_ charges: [BOQCharge]?) -> Double {
        doubleOf(roundToCents((charges ?? []).reduce(Decimal(0)) { $0 + decimalOf($1.amount) }))
    }

    private func totalWeight(for items: [BOQLineItem]) -> Double {
        let kg = items.reduce(Decimal(0)) { $0 + decimalOf($1.quantity.rounded()) * decimalOf($1.weightKg ?? 0) }
        return doubleOf(roundToCents(kg))
    }

    func listBOQSummaries(projectId: String) -> [BOQSummary] {
        boqsStore.readAll()
            .filter { $0.projectId == projectId }
            .sorted { $0.boqNumber > $1.boqNumber }
            .map { boq in
                let items = lineItems(for: boq.id)
                // The total amount, with any charges after the subtotal.
                let total = doubleOf(decimalOf(boqMoneyTotal(items)) + decimalOf(boqChargesTotal(boq.charges)))
                var summary = BOQSummary(
                    id: boq.id, boqNumber: boq.boqNumber, status: boq.status,
                    pricingMode: boq.pricingMode, itemCount: items.count,
                    grandTotal: total, totalWeightKg: totalWeight(for: items), createdAt: boq.createdAt
                )
                summary.structure = nonBlank(boq.structure)
                return summary
            }
    }

    /// BOQ numbers are scoped per project: "<projectNumber>-BOQ-001", next
    /// free sequence for that project — independent of every other
    /// project's numbering (section 24: separate numbering sequences per
    /// document type; here also per project, which is the natural scope
    /// for a BOQ).
    func nextBOQNumber(projectNumber: String, projectId: String) -> String {
        nextDocumentNumber(template: numberFormat("BOQ"), projectNumber: projectNumber, existing: boqsStore.readAll().map { $0.boqNumber }, startAt: getCompanySettings().numberStarts?["BOQ"] ?? 1)
    }

    func createBOQ(projectId: String, projectNumber: String, pricingMode: String, withDefaultItems: Bool = true) -> BillOfQuantities {
        var boq = BillOfQuantities(
            id: makeId("boq"),
            projectId: projectId,
            boqNumber: nextBOQNumber(projectNumber: projectNumber, projectId: projectId),
            pricingMode: pricingMode == "Sale" ? "Sale" : "Rental",
            status: "Draft",
            notes: nil,
            createdAt: nowISO(),
            updatedAt: nowISO(),
            markupOnRates: true
        )
        // Starts with the client's default markup.
        boq.markupPercent = clientDefaultMarkup(projectId: projectId)
        boqsStore.insert(boq)
        if withDefaultItems { addDefaultBOQItems(to: boq) }
        logActivity(projectId: projectId, "BOQ created (\(boq.pricingMode))", reference: boq.boqNumber)
        return boq
    }

    /// Several BOQs of a project added together into one new Draft BOQ:
    /// each item once, with its quantities summed (in the order the items
    /// first appear). Takes the first BOQ's Sale / Rental mode, markup and
    /// prices; notes say which BOQs it was made from.
    func combineBOQs(ids: [String]) -> (id: String?, error: String?) {
        let all = boqsStore.readAll()
        let boqs = ids.compactMap { id in all.first { $0.id == id } }
        guard boqs.count >= 2 else { return (nil, "Choose at least two BOQs to combine.") }
        guard Set(boqs.map { $0.projectId }).count == 1,
              let project = projectsStore.readAll().first(where: { $0.id == boqs[0].projectId }) else { return (nil, "The BOQs must be from the same project.") }
        let first = boqs[0]
        var combined = createBOQ(projectId: project.id, projectNumber: project.projectNumber, pricingMode: first.pricingMode, withDefaultItems: false)
        var order: [String] = []
        var lines: [String: BOQLineItem] = [:]
        for boq in boqs {
            for line in lineItems(for: boq.id) {
                let key = line.priceListItemId ?? "\(line.itemCode)|\(line.itemDescription)|\(line.unit)"
                if var existing = lines[key] {
                    existing.quantity += line.quantity
                    lines[key] = existing
                } else {
                    var copy = line
                    copy.id = makeId("boqitem")
                    copy.boqId = combined.id
                    lines[key] = copy
                    order.append(key)
                }
            }
        }
        boqLineItemsStore.insertMany(order.enumerated().compactMap { index, key in
            guard var line = lines[key] else { return nil }
            line.sortOrder = index
            return line
        })
        var boqsNow = boqsStore.readAll()
        if let i = boqsNow.firstIndex(where: { $0.id == combined.id }) {
            let structures = boqs.compactMap { nonBlank($0.structure) }
            boqsNow[i].markupPercent = first.markupPercent
            boqsNow[i].markupOnRates = first.markupOnRates
            boqsNow[i].orientation = first.orientation
            boqsNow[i].structure = structures.isEmpty ? nil : Array(NSOrderedSet(array: structures)).compactMap { $0 as? String }.joined(separator: " + ")
            boqsNow[i].notes = "Combined from \(boqs.map { $0.boqNumber }.joined(separator: ", "))."
            boqsStore.writeAll(boqsNow)
            combined = boqsNow[i]
        }
        logActivity(projectId: project.id, "BOQ combined from \(boqs.map { $0.boqNumber }.joined(separator: ", "))", reference: combined.boqNumber)
        return (combined.id, nil)
    }

    /// The materials from Settings → BOQ Defaults, priced for the BOQ's
    /// Sale / Rental mode as if picked from the list. Items since deleted
    /// from the material list are skipped.
    private func addDefaultBOQItems(to boq: BillOfQuantities) {
        let defaults = getCompanySettings().defaultBOQItems ?? []
        guard !defaults.isEmpty else { return }
        let items = Dictionary(priceListItemsStore.readAll().filter { !$0.isArchived }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let rates = conversionRates()
        for d in defaults {
            guard let item = items[d.priceListItemId] else { continue }
            let price = basePrice(item, mode: boq.pricingMode, rates: rates) ?? 0
            _ = addBOQLineItem(boqId: boq.id, sourceKey: item.sourceKey, priceListItemId: item.id, itemCode: item.itemCode,
                               description: item.itemName, unit: item.unit, quantity: d.quantity,
                               priceListUnitPrice: price, appliedUnitPrice: price, weightKg: item.weightKg, section: item.category)
        }
    }

    func getBOQ(id: String) -> BillOfQuantities? {
        boqsStore.readAll().first { $0.id == id }
    }

    func getBOQDetail(id: String) -> BOQDetail? {
        guard let boq = boqsStore.readAll().first(where: { $0.id == id }) else { return nil }
        guard let project = projectsStore.readAll().first(where: { $0.id == boq.projectId }) else { return nil }
        let items = lineItems(for: boq.id)
        let total = boqMoneyTotal(items)
        let roundUp = markupRoundsUp
        var detail = BOQDetail(
            id: boq.id, boqNumber: boq.boqNumber, status: boq.status, pricingMode: boq.pricingMode,
            notes: boq.notes, createdAt: boq.createdAt, updatedAt: boq.updatedAt,
            projectNumber: project.projectNumber, projectName: project.name,
            lineItems: items, grandTotal: total, totalWeightKg: totalWeight(for: items),
            markupPercent: boq.markupPercent ?? 0, structure: boq.structure,
            orientation: boq.orientation == "Portrait" ? "Portrait" : "Landscape",
            effectiveRates: Dictionary(items.map { ($0.id, boqEffectiveRate($0, boq: boq, roundUp: roundUp)) }, uniquingKeysWith: { a, _ in a }),
            ratesSection: boq.ratesSection,
            charges: boq.charges, chargesTotal: boqChargesTotal(boq.charges),
            totalAmount: doubleOf(decimalOf(total) + decimalOf(boqChargesTotal(boq.charges))),
            markupOnRates: boq.markupOnRates == true, markupRoundUp: roundUp
        )
        let client = getClient(id: project.clientId)
        detail.clientMarkupPercent = client?.defaultMarkupPercent
        detail.clientName = client?.companyName
        detail.chineseNames = chineseNames(for: items, id: { $0.id }, itemId: { $0.priceListItemId }, description: { $0.itemDescription })
        detail.terms = boq.terms
        detail.signatureSection = boq.signatureSection == true
        detail.standardTerms = getCompanySettings().boqTerms
        return detail
    }

    /// How the BQ sheet is printed; allowed on issued BOQs too, as it
    /// changes only the page, not the content.
    func setBOQOrientation(id: String, orientation: String) -> String? {
        guard ["Landscape", "Portrait"].contains(orientation) else { return "Choose Landscape or Portrait." }
        var boqs = boqsStore.readAll()
        guard let i = boqs.firstIndex(where: { $0.id == id }) else { return "BOQ not found." }
        boqs[i].orientation = orientation
        boqsStore.writeAll(boqs)
        return nil
    }

    private func touchBOQ(_ id: String) {
        var boqs = boqsStore.readAll()
        guard let index = boqs.firstIndex(where: { $0.id == id }) else { return }
        boqs[index].updatedAt = nowISO()
        boqsStore.writeAll(boqs)
    }

    /// Returns nil (success) or an error message. Issued BOQs reject
    /// mutations — section 25 of the brief.
    func addBOQLineItem(boqId: String, sourceKey: String?, priceListItemId: String?, itemCode: String, description: String, unit: String, quantity: Double, priceListUnitPrice: Double?, appliedUnitPrice: Double, weightKg: Double?, section: String?) -> String? {
        guard let boq = getBOQ(id: boqId) else { return "BOQ not found." }
        guard boq.status == "Draft" else { return "This BOQ is issued and can no longer be edited." }

        let nextSortOrder = (lineItems(for: boqId).map { $0.sortOrder }.max() ?? -1) + 1
        let line = BOQLineItem(
            id: makeId("boqitem"), boqId: boqId, sourceKey: sourceKey, priceListItemId: priceListItemId,
            itemCode: itemCode, itemDescription: description, unit: unit, quantity: quantity.rounded(),
            priceListUnitPrice: priceListUnitPrice, appliedUnitPrice: appliedUnitPrice, weightKg: weightKg,
            section: section, sortOrder: nextSortOrder, notes: nil
        )
        boqLineItemsStore.insert(line)
        touchBOQ(boqId)
        return nil
    }

    func updateBOQLineItem(id: String, quantity: Double?, appliedUnitPrice: Double?) -> String? {
        var items = boqLineItemsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        guard let boq = getBOQ(id: items[index].boqId) else { return "BOQ not found." }
        guard boq.status == "Draft" else { return "This BOQ is issued and can no longer be edited." }

        // Quantities are always whole numbers in this app (section note:
        // integer-only quantities), regardless of what a client sends.
        if let quantity = quantity { items[index].quantity = quantity.rounded() }
        if let appliedUnitPrice = appliedUnitPrice { items[index].appliedUnitPrice = appliedUnitPrice }
        boqLineItemsStore.writeAll(items)
        touchBOQ(boq.id)
        return nil
    }

    /// Price-list price for this BOQ's mode, in HKD, with its mark-up.
    func boqPrice(for item: PriceListItem, mode: String, markupPercent: Double, rates: [String: Double]) -> Double? {
        guard let base = basePrice(item, mode: mode, rates: rates) else { return nil }
        return doubleOf(roundToCents(decimalOf(base) * (1 + decimalOf(markupPercent) / 100)))
    }

    /// BOQ settings: Sale/Rental, mark-up and structure. Changing the mode
    /// or mark-up re-prices every price-list line; lines whose price was
    /// typed in by hand (applied ≠ price-list price) keep that price.
    func updateBOQDetails(id: String, pricingMode: String?, markupPercent: Double?, structure: String?, updateStructure: Bool) -> String? {
        var boqs = boqsStore.readAll()
        guard let i = boqs.firstIndex(where: { $0.id == id }) else { return "BOQ not found." }
        guard boqs[i].status == "Draft" else { return "This BOQ is issued. Set it back to Draft to change its details." }
        if boqs[i].markupOnRates != true {
            moveBOQMarkupOntoRates(id)
            boqs = boqsStore.readAll()
        }
        let oldMode = boqs[i].pricingMode
        let oldMarkup = boqs[i].markupPercent ?? 0
        let newMode = (pricingMode == "Sale" || pricingMode == "Rental") ? pricingMode! : oldMode
        let newMarkup = markupPercent ?? oldMarkup
        guard newMarkup > -100 else { return "A mark-down can't be 100% or more." }
        boqs[i].pricingMode = newMode
        boqs[i].markupPercent = newMarkup
        let oldStructure = boqs[i].structure
        if updateStructure {
            let t = structure?.trimmingCharacters(in: .whitespacesAndNewlines)
            boqs[i].structure = (t?.isEmpty ?? true) ? nil : t
        }
        boqs[i].updatedAt = nowISO()
        boqsStore.writeAll(boqs)
        // Quotations following this BOQ carry its structure in their subject line.
        if boqs[i].structure != oldStructure { refreshQuotationSubjects(boqId: id, previousStructure: oldStructure) }

        // The mark-up is applied to the rates as they're shown and printed;
        // only a Sale ↔ Rental change re-prices the lines.
        if newMarkup != oldMarkup {
            logActivity(projectId: boqs[i].projectId, "BOQ mark-up \(formatMoney(newMarkup))%", reference: boqs[i].boqNumber)
        }
        if newMode != oldMode {
            let rates = conversionRates()
            let priceItems = Dictionary(priceListItemsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var lines = boqLineItemsStore.readAll()
            var repriced = 0, kept = 0
            for li in lines.indices where lines[li].boqId == id {
                guard let plId = lines[li].priceListItemId, let pl = priceItems[plId] else { continue }
                let wasManual = lines[li].priceListUnitPrice.map { abs($0 - lines[li].appliedUnitPrice) > 0.004 } ?? false
                guard let newPrice = boqPrice(for: pl, mode: newMode, markupPercent: 0, rates: rates) else { continue }
                lines[li].priceListUnitPrice = newPrice
                if wasManual { kept += 1 } else { lines[li].appliedUnitPrice = newPrice; repriced += 1 }
            }
            boqLineItemsStore.writeAll(lines)
            logActivity(projectId: boqs[i].projectId, "BOQ changed to \(newMode) — \(repriced) line(s) re-priced\(kept > 0 ? ", \(kept) hand-typed price(s) kept" : "")", reference: boqs[i].boqNumber)
        }
        return nil
    }

    func priceListItem(id: String) -> PriceListItem? {
        priceListItemsStore.readAll().first { $0.id == id }
    }

    /// Section 19: reorder lines. direction -1 = up, +1 = down.
    func moveBOQLineItem(id: String, direction: Int) -> String? {
        var all = boqLineItemsStore.readAll()
        guard let target = all.first(where: { $0.id == id }) else { return "Line item not found." }
        guard let boq = getBOQ(id: target.boqId), boq.status == "Draft" else { return "This BOQ is issued and can no longer be edited." }
        var lines = all.filter { $0.boqId == target.boqId }.sorted { $0.sortOrder < $1.sortOrder }
        guard let from = lines.firstIndex(where: { $0.id == id }) else { return nil }
        let to = from + (direction < 0 ? -1 : 1)
        guard to >= 0, to < lines.count else { return nil }
        lines.swapAt(from, to)
        for (order, line) in lines.enumerated() {
            if let i = all.firstIndex(where: { $0.id == line.id }) { all[i].sortOrder = order }
        }
        boqLineItemsStore.writeAll(all)
        touchBOQ(boq.id)
        return nil
    }

    /// Puts a BOQ's lines in the order given (dragged in the editor); any
    /// line not listed keeps its place after them.
    func reorderBOQLineItems(boqId: String, ids: [String]) -> String? {
        guard let boq = getBOQ(id: boqId) else { return "BOQ not found." }
        guard boq.status == "Draft" else { return "This BOQ is issued and can no longer be edited." }
        var all = boqLineItemsStore.readAll()
        let lines = all.filter { $0.boqId == boqId }.sorted { $0.sortOrder < $1.sortOrder }
        for (order, lineId) in reordered(lines.map { $0.id }, by: ids).enumerated() {
            if let i = all.firstIndex(where: { $0.id == lineId }) { all[i].sortOrder = order }
        }
        boqLineItemsStore.writeAll(all)
        touchBOQ(boq.id)
        return nil
    }

    /// Section 19: duplicate a line, placed straight after the original.
    func duplicateBOQLineItem(id: String) -> String? {
        var all = boqLineItemsStore.readAll()
        guard let original = all.first(where: { $0.id == id }) else { return "Line item not found." }
        guard let boq = getBOQ(id: original.boqId), boq.status == "Draft" else { return "This BOQ is issued and can no longer be edited." }
        for i in all.indices where all[i].boqId == original.boqId && all[i].sortOrder > original.sortOrder {
            all[i].sortOrder += 1
        }
        var copy = original
        copy.id = makeId("boqitem")
        copy.sortOrder = original.sortOrder + 1
        all.append(copy)
        boqLineItemsStore.writeAll(all)
        touchBOQ(boq.id)
        return nil
    }

    /// Section 19: a note on an individual line (shown on the PDF too).
    func updateBOQLineNotes(id: String, notes: String?) -> String? {
        var all = boqLineItemsStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        guard let boq = getBOQ(id: all[i].boqId), boq.status == "Draft" else { return "This BOQ is issued and can no longer be edited." }
        let trimmed = notes?.trimmingCharacters(in: .whitespacesAndNewlines)
        all[i].notes = (trimmed?.isEmpty ?? true) ? nil : trimmed
        boqLineItemsStore.writeAll(all)
        touchBOQ(boq.id)
        return nil
    }

    func removeBOQLineItem(id: String) -> String? {
        var items = boqLineItemsStore.readAll()
        guard let target = items.first(where: { $0.id == id }) else { return "Line item not found." }
        guard let boq = getBOQ(id: target.boqId) else { return "BOQ not found." }
        guard boq.status == "Draft" else { return "This BOQ is issued and can no longer be edited." }

        items.removeAll { $0.id == id }
        boqLineItemsStore.writeAll(items)
        touchBOQ(boq.id)
        return nil
    }

    func updateBOQStatus(id: String, status: String) -> String? {
        var boqs = boqsStore.readAll()
        guard let index = boqs.firstIndex(where: { $0.id == id }) else { return "BOQ not found." }
        guard ["Draft", "Issued"].contains(status) else { return "Invalid status." }
        if status == "Issued" && boqs[index].status == "Draft" && lineItems(for: id).isEmpty { return "Add at least one item before issuing this BOQ." }
        let changed = boqs[index].status != status
        boqs[index].status = status
        boqs[index].updatedAt = nowISO()
        boqsStore.writeAll(boqs)
        if changed { logActivity(projectId: boqs[index].projectId, "BOQ \(status == "Issued" ? "issued" : "returned to draft")", reference: boqs[index].boqNumber) }
        if status == "Draft" { moveBOQMarkupOntoRates(id) }
        return nil
    }

    /// Every draft BOQ from before the mark-up moved onto the rates (issued
    /// ones are left as printed until they're set back to Draft).
    func moveBOQMarkupsOntoRates() {
        for boq in boqsStore.readAll() where boq.status == "Draft" && boq.markupOnRates != true { moveBOQMarkupOntoRates(boq.id) }
    }

    /// An older BOQ stored its prices with the mark-up in them. Its lines
    /// go back to list prices (a price typed by hand loses the mark-up) and
    /// the mark-up is applied to the rates instead, rounded to 0.1.
    func moveBOQMarkupOntoRates(_ id: String) {
        var boqs = boqsStore.readAll()
        guard let i = boqs.firstIndex(where: { $0.id == id }), boqs[i].markupOnRates != true, boqs[i].status == "Draft" else { return }
        let markup = boqs[i].markupPercent ?? 0
        if markup != 0, markup > -100 {
            let factor = 1 + decimalOf(markup) / 100
            let rates = conversionRates()
            let priceItems = Dictionary(priceListItemsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var lines = boqLineItemsStore.readAll()
            for li in lines.indices where lines[li].boqId == id {
                let handTyped = lines[li].priceListUnitPrice.map { abs($0 - lines[li].appliedUnitPrice) > 0.004 } ?? true
                let listPrice = lines[li].priceListItemId.flatMap { priceItems[$0] }.flatMap { basePrice($0, mode: boqs[i].pricingMode, rates: rates) }
                    ?? lines[li].priceListUnitPrice.map { doubleOf(roundToCents(decimalOf($0) / factor)) }
                lines[li].priceListUnitPrice = listPrice
                lines[li].appliedUnitPrice = !handTyped && listPrice != nil ? listPrice!
                    : doubleOf(roundToCents(decimalOf(lines[li].appliedUnitPrice) / factor))
            }
            boqLineItemsStore.writeAll(lines)
        }
        boqs[i].markupOnRates = true
        boqsStore.writeAll(boqs)
    }

    /// The landscape sheet's Terms box and signature box; like the notes,
    /// changeable on an issued BOQ too.
    func updateBOQSheetExtras(id: String, payload: [String: Any]) -> String? {
        var boqs = boqsStore.readAll()
        guard let i = boqs.firstIndex(where: { $0.id == id }) else { return "BOQ not found." }
        if payload.keys.contains("terms") { boqs[i].terms = nonBlank(payload["terms"] as? String) }
        if let on = payload["signatureSection"] as? Bool { boqs[i].signatureSection = on ? true : nil }
        boqs[i].updatedAt = nowISO()
        boqsStore.writeAll(boqs)
        return nil
    }

    func updateBOQNotes(id: String, notes: String?) {
        var boqs = boqsStore.readAll()
        guard let index = boqs.firstIndex(where: { $0.id == id }) else { return }
        boqs[index].notes = notes
        boqs[index].updatedAt = nowISO()
        boqsStore.writeAll(boqs)
    }

    /// Draft BOQs only — issued ones are never deleted, per section 25
    /// ("prefer cancellation/archive over deletion" for formal documents).
    /// Deletes a BOQ and its lines. An issued one only when `includingIssued`
    /// (the page asks twice). Its exported PDF stays in the project folder.
    func deleteBOQ(id: String, includingIssued: Bool = false) -> String? {
        guard let boq = getBOQ(id: id) else { return "BOQ not found." }
        guard boq.status == "Draft" || includingIssued else { return "Only draft BOQs can be deleted." }
        var boqs = boqsStore.readAll()
        boqs.removeAll { $0.id == id }
        boqsStore.writeAll(boqs)
        unlinkDrawings(kind: "BOQ", id: id)
        logActivity(projectId: boq.projectId, "\(boq.status == "Draft" ? "Draft" : boq.status) BOQ deleted", reference: boq.boqNumber)
        var items = boqLineItemsStore.readAll()
        items.removeAll { $0.boqId == id }
        boqLineItemsStore.writeAll(items)
        return nil
    }

    // ---- Quotations (Phase 8) ----

    private func quotationLineItems(for quotationId: String) -> [QuotationLineItem] {
        byItemCode(quotationLineItemsStore.readAll().filter { $0.quotationId == quotationId }, code: { $0.itemCode }, order: { $0.sortOrder })
    }

    /// Document lines in item-code order ("1.2" before "1.10"); lines
    /// without a code (custom items, delivery charges) keep the order they
    /// were added in, after the coded ones.
    func byItemCode<T>(_ lines: [T], code: (T) -> String, order: (T) -> Int) -> [T] {
        lines.sorted { a, b in
            let ca = code(a).trimmingCharacters(in: .whitespaces), cb = code(b).trimmingCharacters(in: .whitespaces)
            if ca.isEmpty != cb.isEmpty { return !ca.isEmpty }
            if !ca.isEmpty {
                let comparison = ca.localizedStandardCompare(cb)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return order(a) < order(b)
        }
    }

    /// Rental quotations charge a minimum hire period only when it's
    /// switched on for that quotation. Quotations saved before the option
    /// existed (nil) keep the minimum hire they always had.
    func hireMonths(_ q: Quotation) -> Int {
        guard q.pricingMode == "Rental", q.minimumHireEnabled ?? true else { return 1 }
        return max(1, q.minimumHireMonths ?? getCompanySettings().defaultMinimumHireMonths ?? 2)
    }

    /// The standard quotation's arithmetic: materials subtotal (per month
    /// for rental) × minimum hire months, plus delivery charges; then any
    /// discount and tax as usual. Delivery lines are those in the
    /// "Delivery" section.
    struct QuotationMoney {
        var materialsSubtotal: Double
        /// The monthly rental charged: the materials subtotal, or the
        /// minimum monthly charge when that's ticked and higher.
        var monthlyRental: Double
        var minimumApplied: Bool
        var charges: ChargeSplit
        var materialsCharge: Double
        var deliveryTotal: Double
        var otherTotal: Double
        var subtotal: Double
        var discountAmount: Double
        var taxAmount: Double
        var total: Double
    }

    /// The unit price a quotation line is charged at: its price with the
    /// quotation's markup (materials only, rounded to 0.1).
    func effectiveUnitPrice(_ line: QuotationLineItem, _ q: Quotation) -> Double {
        isMaterialLine(line) ? markedUpPrice(line.appliedUnitPrice, markupPercent: q.markupPercent, roundUp: markupRoundsUp) : line.appliedUnitPrice
    }

    /// A material (or custom item) — not a delivery charge, and not a row
    /// of an extra section.
    func isMaterialLine(_ line: QuotationLineItem) -> Bool {
        line.section != "Delivery" && line.blockId == nil
    }

    func isDeliveryLine(_ line: QuotationLineItem) -> Bool {
        line.section == "Delivery" && line.blockId == nil
    }

    func quotationLineTotal(_ line: QuotationLineItem, _ q: Quotation) -> Decimal {
        netLineAmount(quantity: line.quantity, unitPrice: effectiveUnitPrice(line, q), discountType: line.discountType, discountValue: line.discountValue)
    }

    func quotationMoney(_ q: Quotation, lineItems: [QuotationLineItem]) -> QuotationMoney {
        let months = hireMonths(q)
        let isRental = q.pricingMode == "Rental"
        func net(_ line: QuotationLineItem) -> Decimal { quotationLineTotal(line, q) }
        let materials = lineItems.filter { isMaterialLine($0) }.reduce(Decimal(0)) { $0 + net($1) }
        // A minimum monthly rental charge (when ticked) lifts a small order to it.
        let minimum = decimalOf(minimumMonthlyRental)
        let minimumApplied = isRental && q.minimumMonthlyChargeEnabled == true && materials > 0 && materials < minimum
        let rental = minimumApplied ? minimum : materials
        let delivery = lineItems.filter { isDeliveryLine($0) }.reduce(Decimal(0)) { $0 + net($1) }
        // Priced sections count once; rates-only rows aren't charged.
        let pricedBlocks = quotationBlocks(for: q.id).filter { $0.kind == "Priced" }
        var once = Decimal(0)
        var perPeriod: [String: Decimal] = [:]
        for block in pricedBlocks {
            let amount = lineItems.filter { $0.blockId == block.id }.reduce(Decimal(0)) { $0 + net($1) }
            if let period = block.chargePeriod, ["Day", "Week", "Month"].contains(period) {
                perPeriod[period, default: 0] += amount
            } else {
                once += amount
            }
        }
        let other = once + perPeriod.values.reduce(Decimal(0), +)
        let charge = rental * Decimal(months)
        let t = moneyTotals(subtotal: charge + delivery + other, discountType: q.discountType, discountValue: q.discountValue,
                            taxRatePercent: q.taxRatePercent, pricesIncludeTax: getCompanySettings().pricesIncludeTax ?? false)
        // The split, with any discount taken off each part in proportion.
        let subtotal = decimalOf(t.subtotal)
        let factor: Decimal = subtotal > 0 && t.discountAmount > 0 ? (subtotal - decimalOf(t.discountAmount)) / subtotal : 1
        func part(_ d: Decimal) -> Double { doubleOf(roundToCents(d * factor)) }
        let split: ChargeSplit
        if isRental {
            split = ChargeSplit(monthly: part(rental + (perPeriod["Month"] ?? 0)), oneTime: part(delivery + once),
                                recurring: perPeriod.filter { $0.key != "Month" && $0.value != 0 }.mapValues { part($0) })
        } else {
            // Sale: nothing monthly; it's all one-time.
            split = ChargeSplit(monthly: 0, oneTime: part(materials + delivery + other), recurring: [:])
        }
        return QuotationMoney(materialsSubtotal: doubleOf(materials), monthlyRental: doubleOf(rental), minimumApplied: minimumApplied,
                              charges: split, materialsCharge: doubleOf(charge), deliveryTotal: doubleOf(delivery),
                              otherTotal: doubleOf(other),
                              subtotal: t.subtotal, discountAmount: t.discountAmount, taxAmount: t.taxAmount, total: t.total)
    }

    /// Settings' minimum monthly rental charge (HK$1,000 unless changed).
    var minimumMonthlyRental: Double { getCompanySettings().minimumMonthlyRental ?? 1000 }

    func listQuotationSummaries(projectId: String) -> [QuotationSummary] {
        quotationsStore.readAll()
            .filter { $0.projectId == projectId }
            .sorted { $0.quotationNumber > $1.quotationNumber }
            .map { q in
                let items = quotationLineItems(for: q.id)
                let totals = quotationMoney(q, lineItems: items)
                var summary = QuotationSummary(id: q.id, quotationNumber: q.quotationNumber, status: q.status, itemCount: items.count, total: totals.total, createdAt: q.createdAt)
                summary.signed = q.signedCopyPath.map { fileIsPresent($0) } ?? false
                let boq = q.sourceBOQId.flatMap { getBOQ(id: $0) }
                summary.boqNumber = boq?.boqNumber
                summary.structure = nonBlank(boq?.structure)
                summary.subject = nonBlank(q.subject)
                summary.pricingMode = q.pricingMode
                summary.charges = totals.charges
                return summary
            }
    }

    /// Quotation numbers are scoped per project, same convention as BOQ
    /// numbers: "<projectNumber>-QT-001". Independent of every other
    /// project's numbering.
    func nextQuotationNumber(projectNumber: String, projectId: String) -> String {
        nextDocumentNumber(template: numberFormat("QT"), projectNumber: projectNumber, existing: quotationsStore.readAll().map { $0.quotationNumber }, startAt: getCompanySettings().numberStarts?["QT"] ?? 1)
    }

    /// Creates a quotation, optionally seeding its line items from an
    /// existing BOQ (section 21: "create quotations from a project, a
    /// BOQ, or manually entered items"). Copies, not references — later
    /// edits to the BOQ never change an already-created quotation.
    /// The quotation's "Re:" subject line until someone types their own:
    /// "<project> - <Rental|Sale>", then the structure of the BOQ it
    /// follows, e.g. "GL-28 Works - Rental - Access platform for louvres".
    func autoQuotationSubject(projectName: String, pricingMode: String, structure: String?) -> String {
        ([projectName, pricingMode] + [nonBlank(structure)].compactMap { $0 }).joined(separator: " - ")
    }

    /// Whether a subject line is still the one made for it (with or without
    /// the structure), so it can be kept in step; typed-in ones are left.
    private func isAutoQuotationSubject(_ subject: String?, projectName: String, pricingMode: String, structures: [String?]) -> Bool {
        guard let subject = nonBlank(subject) else { return true }
        return (([nil] as [String?]) + structures).contains { autoQuotationSubject(projectName: projectName, pricingMode: pricingMode, structure: $0) == subject }
    }

    /// Draft quotations following BOQ `boqId` whose subject line is still
    /// automatic get the BOQ's structure (e.g. after it's changed).
    func refreshQuotationSubjects(boqId: String, previousStructure: String? = nil) {
        guard let boq = getBOQ(id: boqId),
              let project = projectsStore.readAll().first(where: { $0.id == boq.projectId }) else { return }
        var qs = quotationsStore.readAll()
        var changed = false
        for i in qs.indices where qs[i].sourceBOQId == boqId && qs[i].status == "Draft" {
            guard isAutoQuotationSubject(qs[i].subject, projectName: project.name, pricingMode: qs[i].pricingMode,
                                         structures: [previousStructure, boq.structure]) else { continue }
            let subject = autoQuotationSubject(projectName: project.name, pricingMode: qs[i].pricingMode, structure: boq.structure)
            guard qs[i].subject != subject else { continue }
            qs[i].subject = subject
            qs[i].updatedAt = nowISO()
            changed = true
        }
        if changed { quotationsStore.writeAll(qs) }
    }

    /// Once per launch: draft quotations made before their subject line
    /// carried the BOQ's structure.
    func addStructuresToQuotationSubjects() {
        let boqIds = Set(quotationsStore.readAll().filter { $0.status == "Draft" }.compactMap { $0.sourceBOQId })
        for id in boqIds { refreshQuotationSubjects(boqId: id) }
    }

    func createQuotation(projectId: String, projectNumber: String, sourceBOQId: String?, pricingMode: String) -> Quotation {
        // A quotation built from a BOQ inherits that BOQ's pricing mode
        // (the line items it copies already reflect that mode's prices),
        // rather than letting the two disagree.
        let resolvedPricingMode = sourceBOQId.flatMap { getBOQ(id: $0)?.pricingMode } ?? pricingMode
        let settings = getCompanySettings()
        var quotation = Quotation(
            id: makeId("quotation"), projectId: projectId, sourceBOQId: sourceBOQId,
            quotationNumber: nextQuotationNumber(projectNumber: projectNumber, projectId: projectId),
            status: "Draft", quotationDate: nowISO(), pricingMode: resolvedPricingMode, validUntil: nil,
            paymentTerms: settings.defaultPaymentTerms,
            // No sales tax in Hong Kong: new quotations carry none.
            discountType: "None", discountValue: 0, taxRatePercent: 0,
            notes: settings.defaultNotes,
            createdAt: nowISO(), updatedAt: nowISO()
        )
        if let project = projectsStore.readAll().first(where: { $0.id == projectId }) {
            let site = sitesStore.readAll().first { $0.id == project.siteId }
            quotation.siteRef = site?.siteReference ?? site?.name
            quotation.subject = autoQuotationSubject(projectName: project.name, pricingMode: resolvedPricingMode,
                                                     structure: sourceBOQId.flatMap { getBOQ(id: $0)?.structure })
        }
        quotation.deliveryMethod = "BY EMAIL ONLY"
        // Starts with the client's default markup — unless it follows a BOQ,
        // whose own mark-up carries on to it instead.
        if sourceBOQId == nil { quotation.markupPercent = clientDefaultMarkup(projectId: projectId) }
        // Minimum hire is an option per quotation, off until switched on;
        // the months default from Settings.
        quotation.minimumHireMonths = settings.defaultMinimumHireMonths ?? 2
        quotation.minimumHireEnabled = false
        quotationsStore.insert(quotation)
        logActivity(projectId: projectId, sourceBOQId == nil ? "Quotation created (\(resolvedPricingMode))" : "Quotation created from BOQ", reference: quotation.quotationNumber)

        if let boqId = sourceBOQId, let boq = getBOQ(id: boqId) {
            let sourceItems = boqLineItemsStore.readAll()
                .filter { $0.boqId == boqId }
                .sorted { $0.sortOrder < $1.sortOrder }
            let copied: [QuotationLineItem] = sourceItems.enumerated().map { index, item in
                let priced = quotationPricing(of: item, boq: boq)
                var line = QuotationLineItem(
                    id: makeId("qitem"), quotationId: quotation.id, sourceKey: item.sourceKey,
                    priceListItemId: item.priceListItemId, itemCode: item.itemCode,
                    itemDescription: item.itemDescription, unit: item.unit, quantity: item.quantity.rounded(),
                    appliedUnitPrice: priced.price, section: item.section, sortOrder: index,
                    priceListUnitPrice: priced.listPrice
                )
                line.discountType = priced.discountType
                line.discountValue = priced.discountValue
                return line
            }
            quotationLineItemsStore.insertMany(copied)
            // The BOQ's mark-up becomes the quotation's markup %.
            if let markup = carriedMarkup(boq) {
                var qs = quotationsStore.readAll()
                if let qi = qs.firstIndex(where: { $0.id == quotation.id }) {
                    qs[qi].markupPercent = markup
                    quotationsStore.writeAll(qs)
                    quotation.markupPercent = markup
                }
            }
        }
        return quotation
    }

    /// The markup % a BOQ passes on to a quotation: its mark-up, if the
    /// BOQ keeps list prices (a mark-down is priced into the lines instead).
    func carriedMarkup(_ boq: BillOfQuantities) -> Double? {
        guard boq.markupOnRates == true, let m = boq.markupPercent, m > 0 else { return nil }
        return m
    }

    /// A BOQ line as a quotation line. With the BOQ's mark-up carried to the
    /// quotation, it keeps its list price, and its discount on the unit rate
    /// becomes the same discount on the quotation line (a per-unit amount ×
    /// quantity), so it's charged the same. Otherwise the rate as charged.
    func quotationPricing(of item: BOQLineItem, boq: BillOfQuantities) -> (price: Double, listPrice: Double?, discountType: String?, discountValue: Double?) {
        guard carriedMarkup(boq) != nil else {
            // No mark-up, a mark-down, or an older BOQ: the rate as charged.
            let rate = boqEffectiveRate(item, boq: boq)
            let list = boq.markupOnRates == true ? item.priceListUnitPrice.map { markedUpPrice($0, markupPercent: boq.markupPercent, roundUp: markupRoundsUp) } : item.priceListUnitPrice
            return (rate, list, nil, nil)
        }
        let value = max(0, item.discountValue ?? 0)
        switch item.discountType {
        case "Percent" where value > 0: return (item.appliedUnitPrice, item.priceListUnitPrice, "Percent", min(value, 100))
        case "Amount" where value > 0:
            return (item.appliedUnitPrice, item.priceListUnitPrice, "Amount", doubleOf(roundToCents(decimalOf(value) * decimalOf(item.quantity.rounded()))))
        default: return (item.appliedUnitPrice, item.priceListUnitPrice, nil, nil)
        }
    }

    func getQuotation(id: String) -> Quotation? {
        quotationsStore.readAll().first { $0.id == id }
    }

    /// "Reference a BOQ for quicker work": copies every line of a BOQ
    /// from the same project into an existing Draft quotation. Prices
    /// are looked up fresh from the price list for the *quotation's*
    /// Sale/Rental mode (so a Rental BOQ can feed a Sale quotation);
    /// if the price-list item no longer exists, the BOQ's own price is
    /// used. `replaceExisting` clears the quotation's current lines
    /// first; otherwise the BOQ's lines are appended.
    func importBOQIntoQuotation(quotationId: String, boqId: String, replaceExisting: Bool) -> String? {
        var qs = quotationsStore.readAll()
        guard let qIndex = qs.firstIndex(where: { $0.id == quotationId }) else { return "Quotation not found." }
        guard qs[qIndex].status == "Draft" else { return "This quotation is issued and can no longer be edited." }
        guard let boq = getBOQ(id: boqId) else { return "BOQ not found." }
        guard boq.projectId == qs[qIndex].projectId else { return "That BOQ belongs to a different project." }

        let boqItems = lineItems(for: boqId)
        guard !boqItems.isEmpty else { return "That BOQ has no items to import." }

        var allQuotationItems = quotationLineItemsStore.readAll()
        if replaceExisting {
            // The extra sections (design fees, rates, notes) stay.
            allQuotationItems.removeAll { $0.quotationId == quotationId && $0.blockId == nil }
        }
        let startOrder = (allQuotationItems.filter { $0.quotationId == quotationId }.map { $0.sortOrder }.max() ?? -1) + 1

        let priceItems = priceListItemsStore.readAll()
        let pricingMode = qs[qIndex].pricingMode
        let rates = conversionRates()
        let carried = carriedMarkup(boq)
        let imported: [QuotationLineItem] = boqItems.enumerated().map { index, item in
            // Same mode: keep the BOQ's own price (any hand-typed price and
            // discount). Different mode: re-price at the list price in HKD.
            let priced = quotationPricing(of: item, boq: boq)
            var price = priced.price
            var listPrice = priced.listPrice
            if boq.pricingMode != pricingMode, let plId = item.priceListItemId, let pl = priceItems.first(where: { $0.id == plId }),
               let p = boqPrice(for: pl, mode: pricingMode, markupPercent: carried == nil && boq.markupOnRates != true ? (boq.markupPercent ?? 0) : 0, rates: rates) {
                price = carried == nil && boq.markupOnRates == true ? markedUpPrice(p, markupPercent: boq.markupPercent, roundUp: markupRoundsUp) : p
                listPrice = price
            }
            var line = QuotationLineItem(
                id: makeId("qitem"), quotationId: quotationId, sourceKey: item.sourceKey,
                priceListItemId: item.priceListItemId, itemCode: item.itemCode,
                itemDescription: item.itemDescription, unit: item.unit, quantity: item.quantity.rounded(),
                appliedUnitPrice: price, section: item.section, sortOrder: startOrder + index,
                priceListUnitPrice: listPrice
            )
            line.discountType = priced.discountType
            line.discountValue = priced.discountValue
            return line
        }
        // The BOQ's mark-up becomes the quotation's markup % (replacing the
        // lines, or when the quotation has no markup of its own yet).
        if let markup = carried, replaceExisting || (qs[qIndex].markupPercent ?? 0) <= 0 {
            qs[qIndex].markupPercent = markup
        }
        allQuotationItems.append(contentsOf: imported)
        quotationLineItemsStore.writeAll(allQuotationItems)

        let previousStructure = qs[qIndex].sourceBOQId.flatMap { getBOQ(id: $0)?.structure }
        qs[qIndex].sourceBOQId = boqId
        qs[qIndex].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
        logActivity(projectId: qs[qIndex].projectId, "Items imported from \(boq.boqNumber)", reference: qs[qIndex].quotationNumber)
        // Now following this BOQ: its structure goes in the subject line.
        refreshQuotationSubjects(boqId: boqId, previousStructure: previousStructure)
        return nil
    }

    func getQuotationDetail(id: String) -> QuotationDetail? {
        guard let q = quotationsStore.readAll().first(where: { $0.id == id }) else { return nil }
        guard let project = projectsStore.readAll().first(where: { $0.id == q.projectId }) else { return nil }
        let items = quotationLineItems(for: q.id)
        let totals = quotationMoney(q, lineItems: items)
        let client = clientsStore.readAll().first { $0.id == project.clientId }
        let site = sitesStore.readAll().first { $0.id == project.siteId }
        let sourceBOQNumber = q.sourceBOQId.flatMap { getBOQ(id: $0)?.boqNumber }
        var detail = QuotationDetail(
            id: q.id, projectId: q.projectId, sourceBOQId: q.sourceBOQId, sourceBOQNumber: sourceBOQNumber,
            quotationNumber: q.quotationNumber, status: q.status, quotationDate: q.quotationDate,
            pricingMode: q.pricingMode, validUntil: q.validUntil, paymentTerms: q.paymentTerms, discountType: q.discountType,
            discountValue: q.discountValue, taxRatePercent: q.taxRatePercent, notes: q.notes,
            createdAt: q.createdAt, updatedAt: q.updatedAt, projectNumber: project.projectNumber,
            projectName: project.name, clientName: client?.companyName, siteName: site?.name,
            lineItems: items, subtotal: totals.subtotal, discountAmount: totals.discountAmount,
            taxAmount: totals.taxAmount, total: totals.total,
            subject: q.subject, clientRef: q.clientRef, siteRef: q.siteRef, deliveryMethod: q.deliveryMethod,
            hireMonths: hireMonths(q), materialsSubtotal: totals.materialsSubtotal, materialsCharge: totals.materialsCharge,
            deliveryTotal: totals.deliveryTotal, standardDeliveryCharge: getCompanySettings().standardDeliveryCharge,
            minimumHireEnabled: q.pricingMode == "Rental" && (q.minimumHireEnabled ?? true),
            minimumHireMonths: max(1, q.minimumHireMonths ?? getCompanySettings().defaultMinimumHireMonths ?? 2),
            markupPercent: q.markupPercent, markupRoundUp: markupRoundsUp,
            effectiveUnitPrices: Dictionary(items.map { ($0.id, effectiveUnitPrice($0, q)) }, uniquingKeysWith: { a, _ in a }),
            lineTotals: Dictionary(items.map { ($0.id, doubleOf(quotationLineTotal($0, q))) }, uniquingKeysWith: { a, _ in a }),
            blocks: quotationBlocks(for: q.id), otherChargesTotal: totals.otherTotal,
            keyTerms: q.keyTerms, standardKeyTerms: getCompanySettings().quotationTerms ?? defaultQuotationTerms
        )
        detail.signedCopyName = q.signedCopyPath.map { URL(fileURLWithPath: $0).lastPathComponent }
        detail.signedCopyAt = q.signedCopyAt
        detail.signedCopyExists = q.signedCopyPath.map { fileIsPresent($0) } ?? false
        detail.signedCopyNotNeeded = q.signedCopyNotNeeded ?? false
        detail.clientMarkupPercent = client?.defaultMarkupPercent
        detail.minimumMonthlyChargeEnabled = q.pricingMode == "Rental" && q.minimumMonthlyChargeEnabled == true
        detail.minimumMonthlyCharge = minimumMonthlyRental
        detail.minimumMonthlyApplied = totals.minimumApplied
        detail.monthlyRental = totals.monthlyRental
        detail.charges = totals.charges
        return detail
    }

    // ---- Extra sections: priced rows, rates-only rows, notes ----

    func quotationBlocks(for quotationId: String) -> [QuotationBlock] {
        quotationBlocksStore.readAll().filter { $0.quotationId == quotationId }.sorted { $0.sortOrder < $1.sortOrder }
    }

    private func draftQuotation(_ id: String) -> Result<Quotation, WorkerError> {
        guard let q = getQuotation(id: id) else { return .failure(WorkerError(message: "Quotation not found.")) }
        guard q.status == "Draft" else { return .failure(WorkerError(message: "This quotation is issued and can no longer be edited.")) }
        return .success(q)
    }

    /// A new section at the end. Priced sections are numbered A, B, C…
    /// (D is taken by delivery charges); rates sections R, S, T…; a rates
    /// section starts with the usual note about labour rates.
    func addQuotationBlock(quotationId: String, kind: String) -> Result<QuotationBlock, WorkerError> {
        guard ["Priced", "Rates", "Note"].contains(kind) else { return .failure(WorkerError(message: "Unknown kind of section.")) }
        if case .failure(let e) = draftQuotation(quotationId) { return .failure(e) }
        let existing = quotationBlocks(for: quotationId)
        let used = Set(existing.map { $0.prefix.uppercased() })
        let letters: [String]
        switch kind {
        case "Priced": letters = "ABCEFGHJKLMNPQ".map { String($0) }
        case "Rates": letters = "RSTUVWXYZ".map { String($0) }
        default: letters = [""]
        }
        let prefix = letters.first { !used.contains($0) } ?? letters.first ?? ""
        let block = QuotationBlock(
            id: makeId("qblock"), quotationId: quotationId, kind: kind,
            title: kind == "Priced" ? "Design Fees" : kind == "Rates" ? "Erection & Dismantle Manpower Rates" : "",
            prefix: prefix,
            note: kind == "Rates" ? "* Please note that labour rates are subject to a price increase for over-time works and works on sundays / public holidays" : nil,
            sortOrder: (existing.map { $0.sortOrder }.max() ?? -1) + 1
        )
        quotationBlocksStore.insert(block)
        touchQuotation(quotationId)
        return .success(block)
    }

    /// Title, row prefix and note. Only fields actually sent are changed.
    func updateQuotationBlock(id: String, payload: [String: Any]) -> String? {
        var blocks = quotationBlocksStore.readAll()
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return "Section not found." }
        if case .failure(let e) = draftQuotation(blocks[i].quotationId) { return e.message }
        if payload.keys.contains("title") {
            blocks[i].title = ((payload["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if payload.keys.contains("prefix") {
            let prefix = ((payload["prefix"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard prefix.count <= 4 else { return "Keep the row prefix short, e.g. \"A\" or \"R\"." }
            blocks[i].prefix = prefix
        }
        if payload.keys.contains("note") { blocks[i].note = text(payload, "note") }
        if payload.keys.contains("chargePeriod") {
            let period = payload["chargePeriod"] as? String
            blocks[i].chargePeriod = ["Day", "Week", "Month"].contains(period ?? "") ? period : nil
        }
        quotationBlocksStore.writeAll(blocks)
        touchQuotation(blocks[i].quotationId)
        return nil
    }

    /// Moves a section up or down among the quotation's sections.
    func moveQuotationBlock(id: String, up: Bool) -> String? {
        var blocks = quotationBlocksStore.readAll()
        guard let target = blocks.first(where: { $0.id == id }) else { return "Section not found." }
        if case .failure(let e) = draftQuotation(target.quotationId) { return e.message }
        let ordered = quotationBlocks(for: target.quotationId)
        guard let position = ordered.firstIndex(where: { $0.id == id }) else { return nil }
        let other = up ? position - 1 : position + 1
        guard ordered.indices.contains(other) else { return nil }
        var order = ordered.map { $0.id }
        order.swapAt(position, other)
        for (n, blockId) in order.enumerated() {
            if let i = blocks.firstIndex(where: { $0.id == blockId }) { blocks[i].sortOrder = n }
        }
        quotationBlocksStore.writeAll(blocks)
        touchQuotation(target.quotationId)
        return nil
    }

    /// Puts a quotation's sections in the order given (dragged in the editor).
    func reorderQuotationBlocks(quotationId: String, ids: [String]) -> String? {
        if case .failure(let e) = draftQuotation(quotationId) { return e.message }
        var blocks = quotationBlocksStore.readAll()
        let current = quotationBlocks(for: quotationId).map { $0.id }
        for (n, blockId) in reordered(current, by: ids).enumerated() {
            if let i = blocks.firstIndex(where: { $0.id == blockId }) { blocks[i].sortOrder = n }
        }
        quotationBlocksStore.writeAll(blocks)
        touchQuotation(quotationId)
        return nil
    }

    /// Removes a section and its rows.
    func removeQuotationBlock(id: String) -> String? {
        var blocks = quotationBlocksStore.readAll()
        guard let target = blocks.first(where: { $0.id == id }) else { return "Section not found." }
        if case .failure(let e) = draftQuotation(target.quotationId) { return e.message }
        blocks.removeAll { $0.id == id }
        quotationBlocksStore.writeAll(blocks)
        var items = quotationLineItemsStore.readAll()
        items.removeAll { $0.blockId == id }
        quotationLineItemsStore.writeAll(items)
        touchQuotation(target.quotationId)
        return nil
    }

    /// "Standard Rates": the standard manpower rates (Settings) as rows of a
    /// rates section — `blockId`'s, or a new "Erection & Dismantle Manpower
    /// Rates" section. Workers already in the section aren't added twice.
    func addStandardManpowerRates(quotationId: String, blockId: String?) -> String? {
        var target: QuotationBlock
        if let blockId = blockId, !blockId.isEmpty {
            guard let block = quotationBlocksStore.readAll().first(where: { $0.id == blockId && $0.quotationId == quotationId }) else { return "Section not found." }
            guard block.kind == "Rates" else { return "Standard rates go in a rates section." }
            target = block
        } else {
            switch addQuotationBlock(quotationId: quotationId, kind: "Rates") {
            case .success(let block): target = block
            case .failure(let e): return e.message
            }
        }
        let existing = Set(quotationLineItemsStore.readAll().filter { $0.blockId == target.id }
            .map { $0.itemDescription.lowercased().trimmingCharacters(in: .whitespaces) })
        for rate in getCompanySettings().manpowerRates ?? defaultManpowerRates
            where !existing.contains(rate.name.lowercased().trimmingCharacters(in: .whitespaces)) {
            if let error = addQuotationBlockLine(blockId: target.id, description: rate.name, unit: rate.unit, quantity: 1, price: rate.rate) {
                return error
            }
        }
        return nil
    }

    /// A row of a priced or rates section: description, unit, quantity
    /// (always 1 for a rate) and unit price / rate.
    func addQuotationBlockLine(blockId: String, description: String, unit: String, quantity: Double, price: Double) -> String? {
        guard let block = quotationBlocksStore.readAll().first(where: { $0.id == blockId }) else { return "Section not found." }
        guard block.kind != "Note" else { return "A note has no rows." }
        if case .failure(let e) = draftQuotation(block.quotationId) { return e.message }
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return "Enter a description." }
        guard price >= 0 else { return "Enter a price of zero or more." }
        let nextSortOrder = (quotationLineItemsStore.readAll().filter { $0.quotationId == block.quotationId }.map { $0.sortOrder }.max() ?? -1) + 1
        var line = QuotationLineItem(
            id: makeId("qitem"), quotationId: block.quotationId, sourceKey: nil, priceListItemId: nil,
            itemCode: "", itemDescription: description, unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
            quantity: block.kind == "Rates" ? 1 : max(1, quantity.rounded()),
            appliedUnitPrice: doubleOf(roundToCents(decimalOf(price))), section: nil, sortOrder: nextSortOrder
        )
        line.blockId = block.id
        quotationLineItemsStore.insert(line)
        touchQuotation(block.quotationId)
        return nil
    }

    /// The standard-quotation fields (subject, refs, delivery method,
    /// minimum hire). Only fields actually sent are changed.
    func updateQuotationLetterFields(id: String, payload: [String: Any]) -> String? {
        var qs = quotationsStore.readAll()
        guard let i = qs.firstIndex(where: { $0.id == id }) else { return "Quotation not found." }
        guard qs[i].status == "Draft" else { return "This quotation is issued and can no longer be edited." }
        if payload.keys.contains("subject") { qs[i].subject = text(payload, "subject") }
        if payload.keys.contains("clientRef") { qs[i].clientRef = text(payload, "clientRef") }
        if payload.keys.contains("siteRef") { qs[i].siteRef = text(payload, "siteRef") }
        if payload.keys.contains("deliveryMethod") { qs[i].deliveryMethod = text(payload, "deliveryMethod") }
        if payload.keys.contains("keyTerms") { qs[i].keyTerms = text(payload, "keyTerms") }
        if let m = payload["minimumHireMonths"] as? Int { qs[i].minimumHireMonths = max(1, m) }
        if let enabled = payload["minimumHireEnabled"] as? Bool { qs[i].minimumHireEnabled = enabled }
        if let enabled = payload["minimumMonthlyChargeEnabled"] as? Bool { qs[i].minimumMonthlyChargeEnabled = enabled ? true : nil }
        qs[i].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
        return nil
    }

    private func touchQuotation(_ id: String) {
        var qs = quotationsStore.readAll()
        guard let index = qs.firstIndex(where: { $0.id == id }) else { return }
        qs[index].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
    }

    func addQuotationLineItem(quotationId: String, sourceKey: String?, priceListItemId: String?, itemCode: String, description: String, unit: String, quantity: Double, appliedUnitPrice: Double, section: String?) -> String? {
        guard let q = getQuotation(id: quotationId) else { return "Quotation not found." }
        guard q.status == "Draft" else { return "This quotation is issued and can no longer be edited." }

        // Items from the material list are priced here, for this
        // quotation's Sale/Rental mode, in the base currency.
        var price = appliedUnitPrice
        var listPrice: Double? = nil
        if let plId = priceListItemId, let pl = priceListItem(id: plId),
           let p = basePrice(pl, mode: q.pricingMode, rates: conversionRates()) {
            price = p
            listPrice = p
        }
        let nextSortOrder = (quotationLineItems(for: quotationId).map { $0.sortOrder }.max() ?? -1) + 1
        let line = QuotationLineItem(
            id: makeId("qitem"), quotationId: quotationId, sourceKey: sourceKey, priceListItemId: priceListItemId,
            itemCode: itemCode, itemDescription: description, unit: unit, quantity: quantity.rounded(),
            appliedUnitPrice: price, section: section, sortOrder: nextSortOrder, priceListUnitPrice: listPrice
        )
        quotationLineItemsStore.insert(line)
        touchQuotation(quotationId)
        return nil
    }

    func updateQuotationLineItem(id: String, quantity: Double?, appliedUnitPrice: Double?, description: String? = nil, unit: String? = nil) -> String? {
        var items = quotationLineItemsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        guard let q = getQuotation(id: items[index].quotationId) else { return "Quotation not found." }
        guard q.status == "Draft" else { return "This quotation is issued and can no longer be edited." }

        if let quantity = quantity { items[index].quantity = quantity.rounded() }
        if let appliedUnitPrice = appliedUnitPrice { items[index].appliedUnitPrice = appliedUnitPrice }
        if let description = description {
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "Enter a description." }
            items[index].itemDescription = trimmed
        }
        if let unit = unit { items[index].unit = unit.trimmingCharacters(in: .whitespacesAndNewlines) }
        quotationLineItemsStore.writeAll(items)
        touchQuotation(q.id)
        return nil
    }

    func removeQuotationLineItem(id: String) -> String? {
        var items = quotationLineItemsStore.readAll()
        guard let target = items.first(where: { $0.id == id }) else { return "Line item not found." }
        guard let q = getQuotation(id: target.quotationId) else { return "Quotation not found." }
        guard q.status == "Draft" else { return "This quotation is issued and can no longer be edited." }

        items.removeAll { $0.id == id }
        quotationLineItemsStore.writeAll(items)
        touchQuotation(q.id)
        return nil
    }

    /// `markupPercent` (+30 = +30% on every item, rounded to 0.1) and the
    /// discount ("Percent" 15 = 15% off, "Fixed" 1000 = 1,000 off) come
    /// from the editor's single "Markup / Discount" box; only one is set.
    func updateQuotationHeader(id: String, validUntil: String?, paymentTerms: String?, notes: String?, discountType: String, discountValue: Double, taxRatePercent: Double, pricingMode: String, markupPercent: Double?) -> String? {
        var qs = quotationsStore.readAll()
        guard let index = qs.firstIndex(where: { $0.id == id }) else { return "Quotation not found." }
        guard qs[index].status == "Draft" else { return "This quotation is issued and can no longer be edited." }
        guard ["Sale", "Rental"].contains(pricingMode) else { return "Invalid pricing mode." }
        guard ["None", "Percent", "Fixed"].contains(discountType) else { return "Invalid discount." }
        guard discountValue >= 0, taxRatePercent >= 0 else { return "Enter amounts of zero or more." }
        if discountType == "Percent" && discountValue > 100 { return "A discount can't be more than 100%." }
        if let m = markupPercent, m < 0 || m > 1000 { return "Enter a markup between 0% and 1000%." }
        qs[index].markupPercent = (markupPercent ?? 0) > 0 ? markupPercent : nil

        qs[index].validUntil = validUntil
        qs[index].paymentTerms = paymentTerms
        qs[index].notes = notes
        qs[index].discountType = discountType
        qs[index].discountValue = discountValue
        qs[index].taxRatePercent = taxRatePercent
        let oldMode = qs[index].pricingMode
        qs[index].pricingMode = pricingMode
        if oldMode != pricingMode, let project = projectsStore.readAll().first(where: { $0.id == qs[index].projectId }) {
            // The subject line still reads "<project> - Rental[ - structure]": keep it in step.
            let structure = qs[index].sourceBOQId.flatMap { getBOQ(id: $0)?.structure }
            if isAutoQuotationSubject(qs[index].subject, projectName: project.name, pricingMode: oldMode, structures: [structure]) {
                qs[index].subject = autoQuotationSubject(projectName: project.name, pricingMode: pricingMode, structure: structure)
            }
        }
        qs[index].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
        if oldMode != pricingMode { repriceQuotationLines(qs[index], from: oldMode) }
        return nil
    }

    /// After a Sale ↔ Rental switch: every line from the material list is
    /// re-priced at its price for the new mode (with the mark-up of the
    /// BOQ it came from, if any). Prices typed in by hand are kept.
    private func repriceQuotationLines(_ q: Quotation, from oldMode: String) {
        let rates = conversionRates()
        // An older BOQ's mark-up was built into its prices; now it's the
        // quotation's own markup %, applied when the prices are charged.
        let markup = q.sourceBOQId.flatMap { getBOQ(id: $0) }.flatMap { $0.markupOnRates == true ? 0 : $0.markupPercent } ?? 0
        let priceItems = Dictionary(priceListItemsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var lines = quotationLineItemsStore.readAll()
        var repriced = 0, kept = 0
        for i in lines.indices where lines[i].quotationId == q.id {
            guard let plId = lines[i].priceListItemId, let pl = priceItems[plId],
                  let newPrice = boqPrice(for: pl, mode: q.pricingMode, markupPercent: markup, rates: rates) else { continue }
            let handTyped = lines[i].priceListUnitPrice.map { abs($0 - lines[i].appliedUnitPrice) > 0.004 } ?? false
            lines[i].priceListUnitPrice = newPrice
            if handTyped { kept += 1 } else { lines[i].appliedUnitPrice = newPrice; repriced += 1 }
        }
        quotationLineItemsStore.writeAll(lines)
        logActivity(projectId: q.projectId, "Quotation changed from \(oldMode) to \(q.pricingMode) — \(repriced) line(s) re-priced\(kept > 0 ? ", \(kept) hand-typed price(s) kept" : "")", reference: q.quotationNumber)
    }

    /// A discount on one line (quotation or invoice): "None", "Percent"
    /// (0-100) or "Amount" off the line total.
    private func checkedDiscount(_ type: String?, _ value: Double?) -> Result<(String?, Double?), WorkerError> {
        let kind = type ?? "None"
        guard ["None", "Percent", "Amount"].contains(kind) else { return .failure(WorkerError(message: "Invalid discount type.")) }
        if kind == "None" { return .success((nil, nil)) }
        let v = value ?? 0
        guard v > 0 else { return .failure(WorkerError(message: "Enter a discount greater than zero.")) }
        if kind == "Percent", v > 100 { return .failure(WorkerError(message: "A percentage discount can't be more than 100%.")) }
        return .success((kind, doubleOf(roundToCents(decimalOf(v)))))
    }

    func updateQuotationLineDiscount(id: String, type: String?, value: Double?) -> String? {
        var items = quotationLineItemsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        guard let q = getQuotation(id: items[index].quotationId) else { return "Quotation not found." }
        guard q.status == "Draft" else { return "This quotation is issued and can no longer be edited." }
        switch checkedDiscount(type, value) {
        case .failure(let e): return e.message
        case .success(let d):
            items[index].discountType = d.0
            items[index].discountValue = d.1
        }
        quotationLineItemsStore.writeAll(items)
        touchQuotation(q.id)
        return nil
    }

    func updateInvoiceLineDiscount(id: String, type: String?, value: Double?) -> String? {
        var items = invoiceLineItemsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        guard let inv = getInvoice(id: items[index].invoiceId) else { return "Invoice not found." }
        guard inv.status == "Draft" else { return "This invoice is issued and can no longer be edited." }
        switch checkedDiscount(type, value) {
        case .failure(let e): return e.message
        case .success(let d):
            items[index].discountType = d.0
            items[index].discountValue = d.1
        }
        invoiceLineItemsStore.writeAll(items)
        touchInvoice(inv.id)
        return nil
    }

    /// The quotation's own date (editable while Draft).
    func updateQuotationDate(id: String, day: String) -> String? {
        var qs = quotationsStore.readAll()
        guard let i = qs.firstIndex(where: { $0.id == id }) else { return "Quotation not found." }
        guard qs[i].status == "Draft" else { return "This quotation is issued and can no longer be edited." }
        guard let iso = isoFromDay(day) else { return "Enter a valid date." }
        qs[i].quotationDate = iso
        qs[i].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
        return nil
    }

    func updateQuotationStatus(id: String, status: String) -> String? {
        var qs = quotationsStore.readAll()
        guard let index = qs.firstIndex(where: { $0.id == id }) else { return "Quotation not found." }
        guard ["Draft", "Issued", "Cancelled"].contains(status) else { return "Invalid status." }
        let previous = qs[index].status
        // Section 25: a cancelled quotation is kept for the record and stays
        // cancelled; one can only be issued once it has something on it.
        if previous == "Cancelled" && status != "Cancelled" { return "This quotation is cancelled and can't be reopened. Create a new quotation instead." }
        if status == "Issued" && previous == "Draft" && quotationLineItems(for: id).isEmpty { return "Add at least one item before issuing this quotation." }
        let changed = previous != status
        qs[index].status = status
        qs[index].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
        if changed { logActivity(projectId: qs[index].projectId, "Quotation \(status == "Draft" ? "returned to draft" : status.lowercased())", reference: qs[index].quotationNumber) }
        return nil
    }

    /// Draft only — an issued quotation is cancelled, never deleted
    /// (section 25 again).
    func deleteQuotation(id: String, includingIssued: Bool = false) -> String? {
        guard let q = getQuotation(id: id) else { return "Quotation not found." }
        guard q.status == "Draft" || includingIssued else { return "Only draft quotations can be deleted." }
        var qs = quotationsStore.readAll()
        qs.removeAll { $0.id == id }
        quotationsStore.writeAll(qs)
        unlinkDrawings(kind: "Quotation", id: id)
        logActivity(projectId: q.projectId, "\(q.status == "Draft" ? "Draft" : q.status) quotation deleted", reference: q.quotationNumber)
        var items = quotationLineItemsStore.readAll()
        items.removeAll { $0.quotationId == id }
        quotationLineItemsStore.writeAll(items)
        var blocks = quotationBlocksStore.readAll()
        blocks.removeAll { $0.quotationId == id }
        quotationBlocksStore.writeAll(blocks)
        return nil
    }

    // ---- Invoices (Phase 9) ----

    /// Issued (or part-paid) with money still owed and past its due date.
    /// Shown as "Overdue" everywhere without having to be set by hand.
    func isInvoiceOverdue(_ inv: Invoice, balanceDue: Double, today: String) -> Bool {
        let open = !["Draft", "Paid", "Cancelled"].contains(inv.status) && balanceDue > 0
        return open && (inv.dueDate.map { !$0.isEmpty && String($0.prefix(10)) < today } ?? false)
    }

    private func invoiceLineItems(for invoiceId: String) -> [InvoiceLineItem] {
        byItemCode(invoiceLineItemsStore.readAll().filter { $0.invoiceId == invoiceId }, code: { $0.itemCode }, order: { $0.sortOrder })
    }

    /// Months of rent a rental invoice charges; 1 for anything else.
    func invoiceMonths(_ inv: Invoice) -> Int {
        inv.pricingMode == "Rental" ? max(1, inv.rentalMonths ?? 1) : 1
    }

    /// Each line net of its own discount. For rental, the materials are a
    /// monthly charge × the months charged; delivery lines are charged
    /// once. Then the invoice-wide discount and tax.
    private func invoiceTotals(_ inv: Invoice, lineItems: [InvoiceLineItem]) -> (subtotal: Double, discountAmount: Double, taxAmount: Double, total: Double, balanceDue: Double, materials: Double, materialsCharge: Double, delivery: Double, other: Double) {
        func net(_ line: InvoiceLineItem) -> Decimal {
            netLineAmount(quantity: line.quantity, unitPrice: line.appliedUnitPrice, discountType: line.discountType, discountValue: line.discountValue)
        }
        let materials = lineItems.filter { $0.section != "Delivery" && $0.chargeGroup == nil }.reduce(Decimal(0)) { $0 + net($1) }
        let delivery = lineItems.filter { $0.section == "Delivery" && $0.chargeGroup == nil }.reduce(Decimal(0)) { $0 + net($1) }
        // Design fees, erection prices…: charged once, like delivery.
        let other = lineItems.filter { $0.chargeGroup != nil }.reduce(Decimal(0)) { $0 + net($1) }
        let charge = materials * Decimal(invoiceMonths(inv))
        let t = moneyTotals(subtotal: charge + delivery + other, discountType: inv.discountType, discountValue: inv.discountValue, taxRatePercent: inv.taxRatePercent,
                            pricesIncludeTax: getCompanySettings().pricesIncludeTax ?? false)
        let balance = decimalOf(t.total) - roundToCents(decimalOf(inv.amountPaid))
        return (t.subtotal, t.discountAmount, t.taxAmount, t.total, doubleOf(balance > 0 ? balance : 0),
                doubleOf(materials), doubleOf(charge), doubleOf(delivery), doubleOf(other))
    }

    func listInvoiceSummaries(projectId: String) -> [InvoiceSummary] {
        let today = todayYMD()
        return invoicesStore.readAll()
            .filter { $0.projectId == projectId }
            .sorted { $0.invoiceNumber > $1.invoiceNumber }
            .map { inv in
                let items = invoiceLineItems(for: inv.id)
                let totals = invoiceTotals(inv, lineItems: items)
                let status = isInvoiceOverdue(inv, balanceDue: totals.balanceDue, today: today) ? "Overdue" : inv.status
                return InvoiceSummary(id: inv.id, invoiceNumber: inv.invoiceNumber, status: status, itemCount: items.count, total: totals.total, amountPaid: inv.amountPaid, dueDate: inv.dueDate, createdAt: inv.createdAt)
            }
    }

    /// Same per-project convention as BOQs and Quotations:
    /// "<projectNumber>-INV-001".
    func nextInvoiceNumber(projectNumber: String, projectId: String) -> String {
        nextDocumentNumber(template: numberFormat("INV"), projectNumber: projectNumber, existing: invoicesStore.readAll().map { $0.invoiceNumber }, startAt: getCompanySettings().numberStarts?["INV"] ?? 1)
    }

    /// Every invoice is based on one of the project's quotations: its
    /// items, prices, line discounts, discount/tax terms and Sale/Rental
    /// pricing are copied (copies, not references). For a rental
    /// quotation the invoice charges `rentalMonths` of rent — one month,
    /// or the quotation's full hire period; delivery charges are included
    /// when `includeDelivery` is set, and the priced sections' charges
    /// (design fees, erection…) when `includeOtherCharges` is. Rates-only
    /// rows and notes aren't copied.
    func createInvoice(projectId: String, projectNumber: String, sourceQuotationId: String, rentalMonths: Int?, includeDelivery: Bool, includeOtherCharges: Bool = true) -> Result<Invoice, WorkerError> {
        guard let quotation = getQuotation(id: sourceQuotationId), quotation.projectId == projectId else {
            return .failure(WorkerError(message: "Choose one of this project's quotations to base the invoice on."))
        }
        guard quotation.status != "Cancelled" else {
            return .failure(WorkerError(message: "That quotation is cancelled. Choose another quotation."))
        }
        let settings = getCompanySettings()
        let dueFormatter = DateFormatter()
        dueFormatter.locale = Locale(identifier: "en_US_POSIX")
        dueFormatter.dateFormat = "yyyy-MM-dd"
        let dueDate = Calendar.current.date(byAdding: .day, value: settings.defaultInvoiceDueDays ?? 30, to: Date()).map { dueFormatter.string(from: $0) }
        let isRental = quotation.pricingMode == "Rental"

        var invoice = Invoice(
            id: makeId("invoice"), projectId: projectId, sourceQuotationId: quotation.id,
            invoiceNumber: nextInvoiceNumber(projectNumber: projectNumber, projectId: projectId),
            status: "Draft", invoiceDate: nowISO(), dueDate: dueDate, paymentTerms: quotation.paymentTerms ?? settings.defaultPaymentTerms,
            discountType: quotation.discountType, discountValue: quotation.discountValue, taxRatePercent: quotation.taxRatePercent,
            amountPaid: 0, notes: settings.defaultNotes, createdAt: nowISO(), updatedAt: nowISO()
        )
        invoice.pricingMode = quotation.pricingMode
        invoice.rentalMonths = isRental ? max(1, rentalMonths ?? 1) : nil
        invoicesStore.insert(invoice)
        let charge = isRental ? " — \(invoice.rentalMonths ?? 1) month\((invoice.rentalMonths ?? 1) == 1 ? "" : "s") rental" : ""
        logActivity(projectId: projectId, "Invoice created from \(quotation.quotationNumber)\(charge)", reference: invoice.invoiceNumber)

        // Prices as charged on the quotation (with its markup).
        let allItems = quotationLineItems(for: quotation.id)
        var sourceItems = allItems.filter { isMaterialLine($0) || (includeDelivery && isDeliveryLine($0)) }
            .map { (line: $0, block: QuotationBlock?.none) }
        if includeOtherCharges {
            for block in quotationBlocks(for: quotation.id) where block.kind == "Priced" {
                sourceItems += allItems.filter { $0.blockId == block.id }.sorted { $0.sortOrder < $1.sortOrder }.map { (line: $0, block: Optional(block)) }
            }
        }
        let copied: [InvoiceLineItem] = sourceItems.enumerated().map { index, source in
            let item = source.line
            var copy = InvoiceLineItem(
                id: makeId("iitem"), invoiceId: invoice.id, sourceKey: item.sourceKey,
                priceListItemId: item.priceListItemId, itemCode: item.itemCode,
                itemDescription: item.itemDescription, unit: item.unit, quantity: item.quantity.rounded(),
                appliedUnitPrice: effectiveUnitPrice(item, quotation), section: item.section, sortOrder: index,
                discountType: item.discountType, discountValue: item.discountValue
            )
            if let block = source.block {
                copy.chargeGroup = nonBlank(block.title) ?? "Other Charges"
                copy.chargePrefix = block.prefix
            }
            return copy
        }
        // The quotation's minimum monthly rental charge carries over as a
        // line after the materials (charged for each month, like them).
        var lines = copied
        let money = quotationMoney(quotation, lineItems: allItems)
        if money.minimumApplied {
            let adjustment = doubleOf(roundToCents(decimalOf(money.monthlyRental) - decimalOf(money.materialsSubtotal)))
            let position = sourceItems.filter { isMaterialLine($0.line) }.count
            lines.insert(InvoiceLineItem(
                id: makeId("iitem"), invoiceId: invoice.id, sourceKey: nil, priceListItemId: nil, itemCode: "",
                itemDescription: "Minimum monthly rental charge adjustment (minimum \(formatMoney(money.monthlyRental)) per month)",
                unit: "lot", quantity: 1, appliedUnitPrice: adjustment, section: nil, sortOrder: position
            ), at: position)
            for i in lines.indices { lines[i].sortOrder = i }
        }
        invoiceLineItemsStore.insertMany(lines)
        return .success(invoice)
    }

    /// Rental invoices: months charged and the period text (Draft only).
    func updateInvoiceRental(id: String, months: Int?, period: String?, updatePeriod: Bool) -> String? {
        var invs = invoicesStore.readAll()
        guard let i = invs.firstIndex(where: { $0.id == id }) else { return "Invoice not found." }
        guard invs[i].status == "Draft" else { return "This invoice is issued and can no longer be edited." }
        guard invs[i].pricingMode == "Rental" else { return nil }
        if let months = months {
            guard months >= 1 else { return "Charge at least one month." }
            invs[i].rentalMonths = months
        }
        if updatePeriod { invs[i].rentalPeriod = nonBlank(period) }
        invs[i].updatedAt = nowISO()
        invoicesStore.writeAll(invs)
        return nil
    }

    func getInvoice(id: String) -> Invoice? {
        invoicesStore.readAll().first { $0.id == id }
    }

    func getInvoiceDetail(id: String) -> InvoiceDetail? {
        guard let inv = invoicesStore.readAll().first(where: { $0.id == id }) else { return nil }
        guard let project = projectsStore.readAll().first(where: { $0.id == inv.projectId }) else { return nil }
        let items = invoiceLineItems(for: inv.id)
        let totals = invoiceTotals(inv, lineItems: items)
        let client = clientsStore.readAll().first { $0.id == project.clientId }
        let site = sitesStore.readAll().first { $0.id == project.siteId }
        return InvoiceDetail(
            id: inv.id, invoiceNumber: inv.invoiceNumber, status: inv.status, invoiceDate: inv.invoiceDate,
            dueDate: inv.dueDate, paymentTerms: inv.paymentTerms, discountType: inv.discountType,
            discountValue: inv.discountValue, taxRatePercent: inv.taxRatePercent, amountPaid: inv.amountPaid,
            notes: inv.notes, createdAt: inv.createdAt, updatedAt: inv.updatedAt,
            projectNumber: project.projectNumber, projectName: project.name,
            clientName: client?.companyName, siteName: site?.name,
            lineItems: items, subtotal: totals.subtotal, discountAmount: totals.discountAmount,
            taxAmount: totals.taxAmount, total: totals.total, balanceDue: totals.balanceDue,
            sourceQuotationId: inv.sourceQuotationId,
            sourceQuotationNumber: inv.sourceQuotationId.flatMap { getQuotation(id: $0)?.quotationNumber },
            pricingMode: inv.pricingMode, rentalMonths: invoiceMonths(inv), rentalPeriod: inv.rentalPeriod,
            materialsSubtotal: totals.materials, materialsCharge: totals.materialsCharge, deliveryTotal: totals.delivery,
            otherChargesTotal: totals.other
        )
    }

    private func touchInvoice(_ id: String) {
        var invs = invoicesStore.readAll()
        guard let index = invs.firstIndex(where: { $0.id == id }) else { return }
        invs[index].updatedAt = nowISO()
        invoicesStore.writeAll(invs)
    }

    func addInvoiceLineItem(invoiceId: String, sourceKey: String?, priceListItemId: String?, itemCode: String, description: String, unit: String, quantity: Double, appliedUnitPrice: Double, section: String?) -> String? {
        guard let inv = getInvoice(id: invoiceId) else { return "Invoice not found." }
        guard inv.status == "Draft" else { return "This invoice is issued and can no longer be edited." }

        let nextSortOrder = (invoiceLineItems(for: invoiceId).map { $0.sortOrder }.max() ?? -1) + 1
        let line = InvoiceLineItem(
            id: makeId("iitem"), invoiceId: invoiceId, sourceKey: sourceKey, priceListItemId: priceListItemId,
            itemCode: itemCode, itemDescription: description, unit: unit, quantity: quantity.rounded(),
            appliedUnitPrice: appliedUnitPrice, section: section, sortOrder: nextSortOrder
        )
        invoiceLineItemsStore.insert(line)
        touchInvoice(invoiceId)
        return nil
    }

    func updateInvoiceLineItem(id: String, quantity: Double?, appliedUnitPrice: Double?) -> String? {
        var items = invoiceLineItemsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        guard let inv = getInvoice(id: items[index].invoiceId) else { return "Invoice not found." }
        guard inv.status == "Draft" else { return "This invoice is issued and can no longer be edited." }

        if let quantity = quantity { items[index].quantity = quantity.rounded() }
        if let appliedUnitPrice = appliedUnitPrice { items[index].appliedUnitPrice = appliedUnitPrice }
        invoiceLineItemsStore.writeAll(items)
        touchInvoice(inv.id)
        return nil
    }

    func removeInvoiceLineItem(id: String) -> String? {
        var items = invoiceLineItemsStore.readAll()
        guard let target = items.first(where: { $0.id == id }) else { return "Line item not found." }
        guard let inv = getInvoice(id: target.invoiceId) else { return "Invoice not found." }
        guard inv.status == "Draft" else { return "This invoice is issued and can no longer be edited." }

        items.removeAll { $0.id == id }
        invoiceLineItemsStore.writeAll(items)
        touchInvoice(inv.id)
        return nil
    }

    func updateInvoiceHeader(id: String, dueDate: String?, paymentTerms: String?, notes: String?, discountType: String, discountValue: Double, taxRatePercent: Double) -> String? {
        var invs = invoicesStore.readAll()
        guard let index = invs.firstIndex(where: { $0.id == id }) else { return "Invoice not found." }
        guard invs[index].status == "Draft" else { return "This invoice is issued and can no longer be edited." }

        invs[index].dueDate = dueDate
        invs[index].paymentTerms = paymentTerms
        invs[index].notes = notes
        invs[index].discountType = discountType
        invs[index].discountValue = discountValue
        invs[index].taxRatePercent = taxRatePercent
        invs[index].updatedAt = nowISO()
        invoicesStore.writeAll(invs)
        return nil
    }

    /// The invoice date (editable while Draft).
    func updateInvoiceDate(id: String, day: String) -> String? {
        var invs = invoicesStore.readAll()
        guard let i = invs.firstIndex(where: { $0.id == id }) else { return "Invoice not found." }
        guard invs[i].status == "Draft" else { return "This invoice is issued and can no longer be edited." }
        guard let iso = isoFromDay(day) else { return "Enter a valid date." }
        invs[i].invoiceDate = iso
        invs[i].updatedAt = nowISO()
        invoicesStore.writeAll(invs)
        return nil
    }

    /// Explicit status changes an admin makes by hand (e.g. Draft →
    /// Issued, or → Cancelled). Payment-driven transitions (→
    /// PartiallyPaid/Paid) happen automatically in recordPayment below.
    func updateInvoiceStatus(id: String, status: String) -> String? {
        var invs = invoicesStore.readAll()
        guard let index = invs.firstIndex(where: { $0.id == id }) else { return "Invoice not found." }
        guard ["Draft", "Issued", "PartiallyPaid", "Paid", "Overdue", "Cancelled"].contains(status) else { return "Invalid status." }
        let previous = invs[index].status
        // Section 25: an issued invoice is a financial record — it's never
        // put back to Draft (which would unlock its figures). Mistakes are
        // corrected by cancelling it and issuing a new one.
        if previous == "Cancelled" && status != "Cancelled" { return "This invoice is cancelled and can't be reopened. Create a new invoice instead." }
        if previous != "Draft" && status == "Draft" { return "An issued invoice can't be returned to Draft. Cancel it and create a new invoice instead." }
        if previous == "Draft" && status != "Draft" && status != "Issued" && status != "Cancelled" { return "Issue this invoice first." }
        if status == "Issued" && previous == "Draft" {
            if invoiceLineItems(for: id).isEmpty { return "Add at least one item before issuing this invoice." }
            if (invs[index].dueDate ?? "").isEmpty { return "Set a due date before issuing this invoice." }
        }
        let changed = previous != status
        invs[index].status = status
        invs[index].updatedAt = nowISO()
        invoicesStore.writeAll(invs)
        if changed {
            let label = status == "PartiallyPaid" ? "marked partially paid" : status == "Draft" ? "returned to draft" : "marked \(status.lowercased())"
            logActivity(projectId: invs[index].projectId, "Invoice \(status == "Issued" ? "issued" : label)", reference: invs[index].invoiceNumber)
        }
        return nil
    }

    /// Adds `amount` to the invoice's cumulative amountPaid and updates
    /// status accordingly — Paid once the balance reaches zero,
    /// PartiallyPaid otherwise. Rejected on a cancelled invoice.
    func recordInvoicePayment(id: String, amount: Double, date: String? = nil, method: String? = nil, reference: String? = nil) -> String? {
        guard amount > 0 else { return "Payment amount must be greater than zero." }
        var invs = invoicesStore.readAll()
        guard let index = invs.firstIndex(where: { $0.id == id }) else { return "Invoice not found." }
        guard invs[index].status != "Cancelled" else { return "Cannot record a payment on a cancelled invoice." }
        guard invs[index].status != "Draft" else { return "Issue this invoice before recording a payment." }

        let items = invoiceLineItems(for: id)
        let before = invoiceTotals(invs[index], lineItems: items)
        guard roundToCents(decimalOf(amount)) <= decimalOf(before.balanceDue) else {
            return "That's more than the balance due (\(formatMoney(before.balanceDue)))."
        }
        invs[index].amountPaid = doubleOf(roundToCents(decimalOf(invs[index].amountPaid) + decimalOf(amount)))

        let totals = invoiceTotals(invs[index], lineItems: items)
        invs[index].status = totals.balanceDue <= 0 ? "Paid" : "PartiallyPaid"
        invs[index].updatedAt = nowISO()
        invoicesStore.writeAll(invs)
        // Kept for the accounts: when, how much, how.
        invoicePaymentsStore.insert(InvoicePayment(
            id: makeId("payment"), invoiceId: id, date: validDay(date) ?? todayYMD(),
            amount: doubleOf(roundToCents(decimalOf(amount))), method: nonBlank(method), reference: nonBlank(reference), createdAt: nowISO()))
        logActivity(projectId: invs[index].projectId, "Payment recorded: \(getCompanySettings().currency) \(formatMoney(amount))\(totals.balanceDue <= 0 ? " — paid in full" : "")", reference: invs[index].invoiceNumber)
        return nil
    }

    /// Draft only — an issued invoice is cancelled, never deleted
    /// (section 22: "issued financial documents should not be casually
    /// deleted; prefer cancellation/archive mechanisms").
    func deleteInvoice(id: String, includingIssued: Bool = false) -> String? {
        guard let inv = getInvoice(id: id) else { return "Invoice not found." }
        guard inv.status == "Draft" || includingIssued else { return "Only draft invoices can be deleted — cancel it instead." }
        var invs = invoicesStore.readAll()
        invs.removeAll { $0.id == id }
        invoicesStore.writeAll(invs)
        // Its payments go from Accounts too.
        var payments = invoicePaymentsStore.readAll()
        payments.removeAll { $0.invoiceId == id }
        invoicePaymentsStore.writeAll(payments)
        logActivity(projectId: inv.projectId, "\(inv.status == "Draft" ? "Draft" : inv.status) invoice deleted", reference: inv.invoiceNumber)
        var items = invoiceLineItemsStore.readAll()
        items.removeAll { $0.invoiceId == id }
        invoiceLineItemsStore.writeAll(items)
        return nil
    }

    // ---- Delivery Notes (Phase 10) ----

    private func deliveryNoteLineItems(for deliveryNoteId: String) -> [DeliveryNoteLineItem] {
        byItemCode(deliveryNoteLineItemsStore.readAll().filter { $0.deliveryNoteId == deliveryNoteId }, code: { $0.itemCode }, order: { $0.sortOrder })
    }

    func listDeliveryNoteSummaries(projectId: String) -> [DeliveryNoteSummary] {
        deliveryNotesStore.readAll()
            .filter { $0.projectId == projectId }
            .sorted { $0.deliveryNoteNumber > $1.deliveryNoteNumber }
            .map { dn in
                let items = deliveryNoteLineItems(for: dn.id)
                return DeliveryNoteSummary(id: dn.id, deliveryNoteNumber: dn.deliveryNoteNumber, status: dn.status, itemCount: items.count, deliveryDate: dn.deliveryDate, createdAt: dn.createdAt)
            }
    }

    /// Same per-project convention as BOQs/Quotations/Invoices:
    /// "<projectNumber>-DN-001" (section 24).
    func nextDeliveryNoteNumber(projectNumber: String, projectId: String) -> String {
        nextDocumentNumber(template: numberFormat("DN"), projectNumber: projectNumber, existing: deliveryNotesStore.readAll().map { $0.deliveryNoteNumber }, startAt: getCompanySettings().numberStarts?["DN"] ?? 1)
    }

    /// Creates a delivery note, optionally seeding its line items from an
    /// existing Invoice or Quotation (section 23: what's delivered
    /// usually mirrors what was quoted/invoiced). An invoice source wins
    /// over a quotation source when both are somehow supplied. Copies,
    /// not references.
    func createDeliveryNote(projectId: String, projectNumber: String, sourceQuotationId: String?, sourceInvoiceId: String?) -> DeliveryNote {
        // Deliveries go to the project's site unless changed on the note.
        let siteAddress: String? = projectsStore.readAll().first(where: { $0.id == projectId }).flatMap { project in
            sitesStore.readAll().first(where: { $0.id == project.siteId })
        }.flatMap { site -> String? in
            let parts = [site.address, site.city, site.postalCode].compactMap { nonBlank($0) }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
        let siteContact = projectsStore.readAll().first(where: { $0.id == projectId })
            .flatMap { project in sitesStore.readAll().first(where: { $0.id == project.siteId }) }
            .flatMap { nonBlank($0.contactPerson) }
        let note = DeliveryNote(
            id: makeId("dn"), projectId: projectId, sourceQuotationId: sourceQuotationId, sourceInvoiceId: sourceInvoiceId,
            deliveryNoteNumber: nextDeliveryNoteNumber(projectNumber: projectNumber, projectId: projectId),
            status: "Draft", deliveryDate: nowISO(), deliveryAddress: siteAddress, deliveredBy: nil, receivedBy: nil,
            notes: nil, createdAt: nowISO(), updatedAt: nowISO(), contactPerson: siteContact
        )
        deliveryNotesStore.insert(note)
        logActivity(projectId: projectId, "Delivery note created", reference: note.deliveryNoteNumber)

        var seeds: [(sourceKey: String?, priceListItemId: String?, itemCode: String, itemDescription: String, unit: String, quantity: Double, section: String?, sortOrder: Int)] = []
        if let invoiceId = sourceInvoiceId {
            // Materials only: not delivery charges or other one-off charges.
            seeds = invoiceLineItemsStore.readAll()
                .filter { $0.invoiceId == invoiceId && $0.section != "Delivery" && $0.chargeGroup == nil }
                .sorted { $0.sortOrder < $1.sortOrder }
                .enumerated().map { index, item in (item.sourceKey, item.priceListItemId, item.itemCode, item.itemDescription, item.unit, item.quantity, item.section, index) }
        } else if let quotationId = sourceQuotationId {
            seeds = quotationLineItemsStore.readAll()
                .filter { $0.quotationId == quotationId && isMaterialLine($0) }
                .sorted { $0.sortOrder < $1.sortOrder }
                .enumerated().map { index, item in (item.sourceKey, item.priceListItemId, item.itemCode, item.itemDescription, item.unit, item.quantity, item.section, index) }
        }
        if !seeds.isEmpty {
            let copied: [DeliveryNoteLineItem] = seeds.map { item in
                DeliveryNoteLineItem(
                    id: makeId("dnitem"), deliveryNoteId: note.id, sourceKey: item.sourceKey,
                    priceListItemId: item.priceListItemId, itemCode: item.itemCode,
                    itemDescription: item.itemDescription, unit: item.unit, quantity: item.quantity.rounded(),
                    section: item.section, sortOrder: item.sortOrder, notes: nil
                )
            }
            deliveryNoteLineItemsStore.insertMany(copied)
        }
        return note
    }

    /// Several delivery notes of a project added together into one new Draft
    /// note: each item once, its quantities summed.
    func combineDeliveryNotes(ids: [String]) -> (id: String?, error: String?) {
        let all = deliveryNotesStore.readAll()
        let notesList = ids.compactMap { id in all.first { $0.id == id } }
        guard notesList.count >= 2 else { return (nil, "Choose at least two delivery notes to combine.") }
        guard Set(notesList.map { $0.projectId }).count == 1,
              let project = projectsStore.readAll().first(where: { $0.id == notesList[0].projectId }) else { return (nil, "The delivery notes must be from the same project.") }
        let combined = createDeliveryNote(projectId: project.id, projectNumber: project.projectNumber, sourceQuotationId: nil, sourceInvoiceId: nil)
        var order: [String] = []
        var lines: [String: DeliveryNoteLineItem] = [:]
        for note in notesList {
            for line in deliveryNoteLineItems(for: note.id) {
                let key = line.priceListItemId ?? "\(line.itemCode)|\(line.itemDescription)|\(line.unit)"
                if var existing = lines[key] {
                    existing.quantity += line.quantity
                    lines[key] = existing
                } else {
                    var copy = line
                    copy.id = makeId("dnitem")
                    copy.deliveryNoteId = combined.id
                    lines[key] = copy
                    order.append(key)
                }
            }
        }
        deliveryNoteLineItemsStore.insertMany(order.enumerated().compactMap { index, key in
            guard var line = lines[key] else { return nil }
            line.sortOrder = index
            return line
        })
        var notesNow = deliveryNotesStore.readAll()
        if let i = notesNow.firstIndex(where: { $0.id == combined.id }) {
            notesNow[i].notes = "Combined from \(notesList.map { $0.deliveryNoteNumber }.joined(separator: ", "))."
            deliveryNotesStore.writeAll(notesNow)
        }
        return (combined.id, nil)
    }

    /// A quotation's materials copied into a Draft delivery note: items
    /// already on the note get the quotation's quantity added (or, with
    /// `replaceExisting`, the note's items are cleared first).
    func importQuotationIntoDeliveryNote(deliveryNoteId: String, quotationId: String, replaceExisting: Bool) -> (added: Int, error: String?) {
        guard let dn = getDeliveryNote(id: deliveryNoteId) else { return (0, "Delivery note not found.") }
        guard dn.status == "Draft" else { return (0, "This delivery note is issued and can no longer be edited.") }
        guard let quotation = quotationsStore.readAll().first(where: { $0.id == quotationId }) else { return (0, "Quotation not found.") }
        guard quotation.projectId == dn.projectId else { return (0, "The quotation must be from the same project.") }
        let source = quotationLineItemsStore.readAll()
            .filter { $0.quotationId == quotationId && isMaterialLine($0) }
            .sorted { $0.sortOrder < $1.sortOrder }
        guard !source.isEmpty else { return (0, "\(quotation.quotationNumber) has no materials to import.") }

        var items = deliveryNoteLineItemsStore.readAll()
        if replaceExisting { items.removeAll { $0.deliveryNoteId == deliveryNoteId } }
        let key: (String?, String, String, String) -> String = { id, code, description, unit in id ?? "\(code)|\(description)|\(unit)" }
        var nextSort = (items.filter { $0.deliveryNoteId == deliveryNoteId }.map { $0.sortOrder }.max() ?? -1) + 1
        var added = 0
        for line in source {
            let k = key(line.priceListItemId, line.itemCode, line.itemDescription, line.unit)
            if let i = items.firstIndex(where: { $0.deliveryNoteId == deliveryNoteId && key($0.priceListItemId, $0.itemCode, $0.itemDescription, $0.unit) == k }) {
                items[i].quantity += line.quantity.rounded()
            } else {
                items.append(DeliveryNoteLineItem(
                    id: makeId("dnitem"), deliveryNoteId: deliveryNoteId, sourceKey: line.sourceKey,
                    priceListItemId: line.priceListItemId, itemCode: line.itemCode,
                    itemDescription: line.itemDescription, unit: line.unit, quantity: line.quantity.rounded(),
                    section: line.section, sortOrder: nextSort, notes: nil
                ))
                nextSort += 1
            }
            added += 1
        }
        deliveryNoteLineItemsStore.writeAll(items)

        var notesArr = deliveryNotesStore.readAll()
        if let i = notesArr.firstIndex(where: { $0.id == deliveryNoteId }) {
            if notesArr[i].sourceQuotationId == nil { notesArr[i].sourceQuotationId = quotationId }
            notesArr[i].updatedAt = nowISO()
            deliveryNotesStore.writeAll(notesArr)
        }
        logActivity(projectId: dn.projectId, "Materials imported from \(quotation.quotationNumber)", reference: dn.deliveryNoteNumber)
        return (added, nil)
    }

    func getDeliveryNote(id: String) -> DeliveryNote? {
        deliveryNotesStore.readAll().first { $0.id == id }
    }

    func getDeliveryNoteDetail(id: String) -> DeliveryNoteDetail? {
        guard let dn = deliveryNotesStore.readAll().first(where: { $0.id == id }) else { return nil }
        guard let project = projectsStore.readAll().first(where: { $0.id == dn.projectId }) else { return nil }
        let items = deliveryNoteLineItems(for: dn.id)
        let client = clientsStore.readAll().first { $0.id == project.clientId }
        let site = sitesStore.readAll().first { $0.id == project.siteId }
        return DeliveryNoteDetail(
            id: dn.id, deliveryNoteNumber: dn.deliveryNoteNumber, status: dn.status, deliveryDate: dn.deliveryDate,
            deliveryAddress: dn.deliveryAddress, deliveredBy: dn.deliveredBy, receivedBy: dn.receivedBy,
            notes: dn.notes, createdAt: dn.createdAt, updatedAt: dn.updatedAt,
            projectNumber: project.projectNumber, projectName: project.name,
            clientName: client?.companyName, siteName: site?.name, lineItems: items,
            contactPerson: dn.contactPerson, projectId: dn.projectId, sourceQuotationId: dn.sourceQuotationId,
            chineseNames: chineseNames(for: items, id: { $0.id }, itemId: { $0.priceListItemId }, description: { $0.itemDescription })
        )
    }

    private func touchDeliveryNote(_ id: String) {
        var notesArr = deliveryNotesStore.readAll()
        guard let index = notesArr.firstIndex(where: { $0.id == id }) else { return }
        notesArr[index].updatedAt = nowISO()
        deliveryNotesStore.writeAll(notesArr)
    }

    func addDeliveryNoteLineItem(deliveryNoteId: String, sourceKey: String?, priceListItemId: String?, itemCode: String, description: String, unit: String, quantity: Double, section: String?) -> String? {
        guard let dn = getDeliveryNote(id: deliveryNoteId) else { return "Delivery note not found." }
        guard dn.status == "Draft" else { return "This delivery note is issued and can no longer be edited." }

        let nextSortOrder = (deliveryNoteLineItems(for: deliveryNoteId).map { $0.sortOrder }.max() ?? -1) + 1
        let line = DeliveryNoteLineItem(
            id: makeId("dnitem"), deliveryNoteId: deliveryNoteId, sourceKey: sourceKey, priceListItemId: priceListItemId,
            itemCode: itemCode, itemDescription: description, unit: unit, quantity: quantity.rounded(),
            section: section, sortOrder: nextSortOrder, notes: nil
        )
        deliveryNoteLineItemsStore.insert(line)
        touchDeliveryNote(deliveryNoteId)
        return nil
    }

    func updateDeliveryNoteLineItem(id: String, quantity: Double?) -> String? {
        var items = deliveryNoteLineItemsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        guard let dn = getDeliveryNote(id: items[index].deliveryNoteId) else { return "Delivery note not found." }
        guard dn.status == "Draft" else { return "This delivery note is issued and can no longer be edited." }

        if let quantity = quantity { items[index].quantity = quantity.rounded() }
        deliveryNoteLineItemsStore.writeAll(items)
        touchDeliveryNote(dn.id)
        return nil
    }

    func removeDeliveryNoteLineItem(id: String) -> String? {
        var items = deliveryNoteLineItemsStore.readAll()
        guard let target = items.first(where: { $0.id == id }) else { return "Line item not found." }
        guard let dn = getDeliveryNote(id: target.deliveryNoteId) else { return "Delivery note not found." }
        guard dn.status == "Draft" else { return "This delivery note is issued and can no longer be edited." }

        items.removeAll { $0.id == id }
        deliveryNoteLineItemsStore.writeAll(items)
        touchDeliveryNote(dn.id)
        return nil
    }

    func updateDeliveryNoteHeader(id: String, deliveryAddress: String?, deliveredBy: String?, receivedBy: String?, notes: String?,
                                  contactPerson: String?? = nil) -> String? {
        var notesArr = deliveryNotesStore.readAll()
        guard let index = notesArr.firstIndex(where: { $0.id == id }) else { return "Delivery note not found." }
        guard notesArr[index].status == "Draft" else { return "This delivery note is issued and can no longer be edited." }

        if let contact = contactPerson { notesArr[index].contactPerson = contact }
        notesArr[index].deliveryAddress = deliveryAddress
        notesArr[index].deliveredBy = deliveredBy
        notesArr[index].receivedBy = receivedBy
        notesArr[index].notes = notes
        notesArr[index].updatedAt = nowISO()
        deliveryNotesStore.writeAll(notesArr)
        return nil
    }

    /// The delivery date (editable while Draft).
    func updateDeliveryNoteDate(id: String, day: String) -> String? {
        var notesArr = deliveryNotesStore.readAll()
        guard let i = notesArr.firstIndex(where: { $0.id == id }) else { return "Delivery note not found." }
        guard notesArr[i].status == "Draft" else { return "This delivery note is issued and can no longer be edited." }
        guard let iso = isoFromDay(day) else { return "Enter a valid date." }
        notesArr[i].deliveryDate = iso
        notesArr[i].updatedAt = nowISO()
        deliveryNotesStore.writeAll(notesArr)
        return nil
    }

    func updateDeliveryNoteStatus(id: String, status: String) -> String? {
        var notesArr = deliveryNotesStore.readAll()
        guard let index = notesArr.firstIndex(where: { $0.id == id }) else { return "Delivery note not found." }
        guard ["Draft", "Issued", "Cancelled"].contains(status) else { return "Invalid status." }
        let previous = notesArr[index].status
        if previous == "Cancelled" && status != "Cancelled" { return "This delivery note is cancelled and can't be reopened. Create a new delivery note instead." }
        if status == "Issued" && previous == "Draft" && deliveryNoteLineItems(for: id).isEmpty { return "Add at least one item before issuing this delivery note." }
        let changed = previous != status
        notesArr[index].status = status
        notesArr[index].updatedAt = nowISO()
        deliveryNotesStore.writeAll(notesArr)
        // Stock: an issued delivery note books its items out of the yard;
        // cancelling or reopening it puts them back.
        if status == "Issued" && previous != "Issued" { recordDeliveryStock(notesArr[index]) }
        if previous == "Issued" && status != "Issued" { removeDeliveryStock(deliveryNoteId: id) }
        if changed { logActivity(projectId: notesArr[index].projectId, "Delivery note \(status == "Draft" ? "returned to draft" : status.lowercased())", reference: notesArr[index].deliveryNoteNumber) }
        return nil
    }

    /// Draft only — same "don't casually delete a formal document" rule
    /// as BOQs/Quotations/Invoices (section 25).
    func deleteDeliveryNote(id: String, includingIssued: Bool = false) -> String? {
        guard let dn = getDeliveryNote(id: id) else { return "Delivery note not found." }
        guard dn.status == "Draft" || includingIssued else { return "Only draft delivery notes can be deleted." }
        var notesArr = deliveryNotesStore.readAll()
        notesArr.removeAll { $0.id == id }
        deliveryNotesStore.writeAll(notesArr)
        // Its items go back into the stock list.
        removeDeliveryStock(deliveryNoteId: id)
        logActivity(projectId: dn.projectId, "\(dn.status == "Draft" ? "Draft" : dn.status) delivery note deleted", reference: dn.deliveryNoteNumber)
        var items = deliveryNoteLineItemsStore.readAll()
        items.removeAll { $0.deliveryNoteId == id }
        deliveryNoteLineItemsStore.writeAll(items)
        return nil
    }

    /// Remembers where a document's exported PDF was saved (section 32).
    func recordGeneratedPDF(docTypeTag: String, documentNumber: String, path: String) {
        switch docTypeTag {
        case "BOQ":
            var all = boqsStore.readAll()
            guard let i = all.firstIndex(where: { $0.boqNumber == documentNumber }) else { return }
            all[i].pdfPath = path
            boqsStore.writeAll(all)
        case "Quotation":
            var all = quotationsStore.readAll()
            guard let i = all.firstIndex(where: { $0.quotationNumber == documentNumber }) else { return }
            all[i].pdfPath = path
            quotationsStore.writeAll(all)
        case "Invoice":
            var all = invoicesStore.readAll()
            guard let i = all.firstIndex(where: { $0.invoiceNumber == documentNumber }) else { return }
            all[i].pdfPath = path
            invoicesStore.writeAll(all)
        case "DeliveryNote":
            var all = deliveryNotesStore.readAll()
            guard let i = all.firstIndex(where: { $0.deliveryNoteNumber == documentNumber }) else { return }
            all[i].pdfPath = path
            deliveryNotesStore.writeAll(all)
        default:
            break
        }
    }

    // ---- Company settings (section 28) ----

    /// Always a single record with a fixed id — created with sensible
    /// defaults the first time it's requested.
    func getCompanySettings() -> CompanySettings {
        if let existing = settingsStore.readAll().first { return existing }
        let defaults = CompanySettings(
            id: "company", companyName: "Proficiency (HK) Limited",
            addressLine1: nil, addressLine2: nil, phone: nil, email: nil, website: nil,
            registrationNumber: nil, vatNumber: nil, bankDetails: nil,
            defaultPaymentTerms: nil, defaultNotes: nil, currency: "HKD", defaultTaxRatePercent: 0,
            pricesIncludeTax: false, paperSize: "A4", appearance: "System", logoPath: nil,
            numberFormatBOQ: nil, numberFormatQuotation: nil, numberFormatInvoice: nil, numberFormatDeliveryNote: nil,
            defaultInvoiceDueDays: 30,
            signatoryName: "Richard Kwan", signatoryTitle: "Director", termsURL: "www.pfitnet.com/TC",
            quotationTerms: defaultQuotationTerms, quotationAcceptance: defaultQuotationAcceptance,
            standardDeliveryCharge: 3800, defaultMinimumHireMonths: 2, exchangeRates: ["EUR": 8.93], numberStarts: nil
        )
        settingsStore.writeAll([defaults])
        return defaults
    }

    func updateCompanySettings(_ payload: [String: Any]) -> CompanySettings {
        var settings = getCompanySettings()
        if let v = payload["companyName"] as? String, !v.isEmpty { settings.companyName = v }
        // Only fields actually sent are changed — so saving one option
        // (e.g. Appearance) never blanks the company details.
        func optionalText(_ key: String) -> String?? {
            guard payload.keys.contains(key) else { return .none }
            let v = (payload[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .some((v?.isEmpty ?? true) ? nil : v)
        }
        if let v = optionalText("addressLine1") { settings.addressLine1 = v }
        if let v = optionalText("addressLine2") { settings.addressLine2 = v }
        if let v = optionalText("phone") { settings.phone = v }
        if let v = optionalText("email") { settings.email = v }
        if let v = optionalText("website") { settings.website = v }
        if let v = optionalText("registrationNumber") { settings.registrationNumber = v }
        if let v = optionalText("vatNumber") { settings.vatNumber = v }
        if let v = optionalText("bankDetails") { settings.bankDetails = v }
        if let v = optionalText("defaultPaymentTerms") { settings.defaultPaymentTerms = v }
        if let v = optionalText("defaultNotes") { settings.defaultNotes = v }
        if let v = payload["currency"] as? String, !v.isEmpty { settings.currency = v }
        if let v = payload["defaultTaxRatePercent"] as? Double { settings.defaultTaxRatePercent = v }
        // Newer options: only changed when the page actually sends them.
        if let v = payload["pricesIncludeTax"] as? Bool { settings.pricesIncludeTax = v }
        if let v = payload["paperSize"] as? String, ["A4", "Letter"].contains(v) { settings.paperSize = v }
        if let v = payload["appearance"] as? String, ["System", "Light", "Dark"].contains(v) { settings.appearance = v }
        if let v = payload["defaultInvoiceDueDays"] as? Int { settings.defaultInvoiceDueDays = max(0, v) }
        func format(_ key: String) -> String?? {
            guard payload.keys.contains(key) else { return .none }
            let raw = ((payload[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .some(raw.isEmpty ? nil : raw)
        }
        if let v = format("numberFormatBOQ") { settings.numberFormatBOQ = v }
        if let v = format("numberFormatQuotation") { settings.numberFormatQuotation = v }
        if let v = format("numberFormatInvoice") { settings.numberFormatInvoice = v }
        if let v = format("numberFormatDeliveryNote") { settings.numberFormatDeliveryNote = v }
        if let v = optionalText("signatoryName") { settings.signatoryName = v }
        if let v = optionalText("signatoryTitle") { settings.signatoryTitle = v }
        if let v = optionalText("termsURL") { settings.termsURL = v }
        if payload.keys.contains("quotationTerms") { settings.quotationTerms = (payload["quotationTerms"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } }
        if let v = optionalText("quotationAcceptance") { settings.quotationAcceptance = v }
        if payload.keys.contains("standardDeliveryCharge") { settings.standardDeliveryCharge = payload["standardDeliveryCharge"] as? Double }
        if let v = payload["defaultMinimumHireMonths"] as? Int { settings.defaultMinimumHireMonths = max(1, v) }
        if let v = payload["termsNewPage"] as? String, ["WhenLong", "Always"].contains(v) { settings.termsNewPage = v == "Always" ? v : nil }
        if let v = payload["markupRounding"] as? String, ["Nearest", "Up"].contains(v) { settings.markupRoundUp = v == "Up" ? true : nil }
        if let list = payload["manpowerRates"] as? [[String: Any]] {
            settings.manpowerRates = list.compactMap { item in
                guard let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
                let unit = ((item["unit"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return ManpowerRate(name: name, rate: max(0, (item["rate"] as? Double) ?? 0), unit: unit.isEmpty ? "md" : unit)
            }
        }
        if let v = payload["minimumMonthlyRental"] as? Double { settings.minimumMonthlyRental = max(0, v) }
        if let v = payload["chineseNamesOnDocuments"] as? Bool { settings.chineseNamesOnDocuments = v }
        if payload.keys.contains("boqTerms") { settings.boqTerms = nonBlank(payload["boqTerms"] as? String) }
        if let list = payload["defaultBOQItems"] as? [[String: Any]] {
            var seen = Set<String>()
            let items: [DefaultBOQItem] = list.compactMap { item in
                guard let itemId = item["priceListItemId"] as? String, !itemId.isEmpty, seen.insert(itemId).inserted else { return nil }
                let quantity = ((item["quantity"] as? Double) ?? 1).rounded()
                return DefaultBOQItem(priceListItemId: itemId, quantity: max(1, quantity))
            }
            settings.defaultBOQItems = items.isEmpty ? nil : items
        }
        if let rates = payload["exchangeRates"] as? [String: Any] {
            var clean: [String: Double] = settings.exchangeRates ?? [:]
            for (k, v) in rates { if let d = v as? Double, d > 0 { clean[k.uppercased()] = d } }
            settings.exchangeRates = clean
        }
        if let starts = payload["numberStarts"] as? [String: Any] {
            var clean: [String: Int] = [:]
            for (k, v) in starts { if let n = v as? Int, n > 0 { clean[k] = n } }
            settings.numberStarts = clean.isEmpty ? nil : clean
        }
        settingsStore.writeAll([settings])
        return settings
    }

    func setLogoPath(_ path: String?) {
        var settings = getCompanySettings()
        settings.logoPath = path
        settingsStore.writeAll([settings])
    }

    func numberFormat(_ type: String) -> String {
        let s = getCompanySettings()
        let custom: String?
        switch type {
        case "BOQ": custom = s.numberFormatBOQ
        case "QT": custom = s.numberFormatQuotation
        case "INV": custom = s.numberFormatInvoice
        default: custom = s.numberFormatDeliveryNote
        }
        return custom ?? defaultNumberFormats[type] ?? "{PROJECT}-\(type)-{SEQ}"
    }

    // ---- Drawings (Phase 11 — section 14) ----

    func listDrawings(projectId: String) -> [ProjectDrawingSummary] {
        drawingSummaries(drawingsStore.readAll().filter { $0.projectId == projectId && !$0.isArchived })
    }

    /// Drawings that belonged to a deleted BOQ or quotation stay with the project.
    func unlinkDrawings(kind: String, id: String) {
        var items = drawingsStore.readAll()
        var changed = false
        for i in items.indices where items[i].linkedKind == kind && items[i].linkedId == id {
            items[i].linkedKind = nil
            items[i].linkedId = nil
            changed = true
        }
        if changed { drawingsStore.writeAll(items) }
    }

    /// The drawings of one BOQ or quotation, in the order they're added to
    /// its PDF: for a quotation that follows a BOQ, the BOQ's drawings first,
    /// then its own; each oldest first.
    func listDrawings(linkedKind: String, linkedId: String) -> [ProjectDrawingSummary] {
        let boq = linkedKind == "Quotation" ? getQuotation(id: linkedId)?.sourceBOQId.flatMap { getBOQ(id: $0) } : nil
        // The BOQ itself comes first, as a PDF of its own pages.
        var boqRow: [ProjectDrawingSummary] = []
        if let boq = boq, !lineItems(for: boq.id).isEmpty {
            boqRow = [ProjectDrawingSummary(
                id: "boq:\(boq.id)", originalName: "\(boq.boqNumber) (the BOQ)", storedFilename: "\(boq.boqNumber) — Bill of Quantities",
                fileType: "PDF", fileSizeBytes: 0, description: "Its latest version, made fresh each time the quotation is exported or printed.",
                uploadedAt: boq.updatedAt, fileExists: true, linkedKind: "BOQ", linkedId: boq.id, linkedNumber: boq.boqNumber,
                fromBOQNumber: boq.boqNumber, appended: true, boqId: boq.id)]
        }
        return boqRow + documentDrawings(kind: linkedKind, id: linkedId).map { d in
            var summary = drawingSummaries([d])[0]
            if let boq = boq, d.linkedKind == "BOQ", d.linkedId == boq.id { summary.fromBOQNumber = boq.boqNumber }
            summary.appended = PDFAttachments.canAppend(URL(fileURLWithPath: d.filePath)) && summary.fileExists
            return summary
        }
    }

    /// See `listDrawings(linkedKind:linkedId:)`.
    func documentDrawings(kind: String, id: String) -> [ProjectDrawing] {
        let all = drawingsStore.readAll().filter { !$0.isArchived }
        let own = all.filter { $0.linkedKind == kind && $0.linkedId == id }.sorted { $0.uploadedAt < $1.uploadedAt }
        guard kind == "Quotation", let boqId = getQuotation(id: id)?.sourceBOQId else { return own }
        let inherited = all.filter { $0.linkedKind == "BOQ" && $0.linkedId == boqId }.sorted { $0.uploadedAt < $1.uploadedAt }
        return inherited + own
    }

    /// The drawing files added after a BOQ's or quotation's own pages.
    func appendedDrawingFiles(kind: String, id: String) -> [URL] {
        documentDrawings(kind: kind, id: id).map { URL(fileURLWithPath: $0.filePath) }
            .filter { PDFAttachments.canAppend($0) && FileManager.default.fileExists(atPath: $0.path) }
    }

    private func drawingSummaries(_ drawings: [ProjectDrawing]) -> [ProjectDrawingSummary] {
        let boqNumbers = Dictionary(boqsStore.readAll().map { ($0.id, $0.boqNumber) }, uniquingKeysWith: { a, _ in a })
        let quotationNumbers = Dictionary(quotationsStore.readAll().map { ($0.id, $0.quotationNumber) }, uniquingKeysWith: { a, _ in a })
        return drawings
            .sorted { $0.uploadedAt > $1.uploadedAt }
            .map { d in
                let number = d.linkedId.flatMap { d.linkedKind == "BOQ" ? boqNumbers[$0] : d.linkedKind == "Quotation" ? quotationNumbers[$0] : nil }
                return ProjectDrawingSummary(
                    id: d.id, originalName: d.originalName, storedFilename: d.storedFilename,
                    fileType: d.fileType, fileSizeBytes: d.fileSizeBytes, description: d.description,
                    uploadedAt: d.uploadedAt, fileExists: FileManager.default.fileExists(atPath: d.filePath),
                    linkedKind: number == nil ? nil : d.linkedKind, linkedId: number == nil ? nil : d.linkedId, linkedNumber: number
                )
            }
    }

    /// Links a drawing to one of its project's BOQs or quotations, or
    /// unlinks it (kind nil).
    func setDrawingLink(id: String, kind: String?, linkedId: String?) -> String? {
        var items = drawingsStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Drawing not found." }
        if let error = checkDrawingLink(projectId: items[i].projectId, kind: kind, linkedId: linkedId) { return error }
        let linked = (kind == "BOQ" || kind == "Quotation") && nonBlank(linkedId) != nil
        items[i].linkedKind = linked ? kind : nil
        items[i].linkedId = linked ? linkedId : nil
        drawingsStore.writeAll(items)
        return nil
    }

    /// nil when the link is empty or points at this project's own BOQ or
    /// quotation.
    func checkDrawingLink(projectId: String, kind: String?, linkedId: String?) -> String? {
        guard let kind = nonBlank(kind), let linkedId = nonBlank(linkedId) else { return nil }
        switch kind {
        case "BOQ": return getBOQ(id: linkedId)?.projectId == projectId ? nil : "That BOQ isn't part of this project."
        case "Quotation": return getQuotation(id: linkedId)?.projectId == projectId ? nil : "That quotation isn't part of this project."
        default: return "A drawing can be linked to a BOQ or a quotation."
        }
    }

    @discardableResult
    func recordDrawing(projectId: String, originalName: String, storedURL: URL, linkedKind: String? = nil, linkedId: String? = nil) -> ProjectDrawing {
        let attrs = try? FileManager.default.attributesOfItem(atPath: storedURL.path)
        let size = (attrs?[.size] as? Int) ?? 0
        let linked = checkDrawingLink(projectId: projectId, kind: linkedKind, linkedId: linkedId) == nil && nonBlank(linkedKind) != nil && nonBlank(linkedId) != nil
        let drawing = ProjectDrawing(
            id: makeId("drawing"), projectId: projectId, originalName: originalName,
            storedFilename: storedURL.lastPathComponent, filePath: storedURL.path,
            fileType: storedURL.pathExtension.uppercased(), fileSizeBytes: size,
            description: nil, isArchived: false, uploadedAt: nowISO(),
            linkedKind: linked ? linkedKind : nil, linkedId: linked ? linkedId : nil
        )
        drawingsStore.insert(drawing)
        logActivity(projectId: projectId, "Drawing uploaded", reference: originalName)
        return drawing
    }

    func getDrawing(id: String) -> ProjectDrawing? {
        drawingsStore.readAll().first { $0.id == id }
    }

    func updateDrawingDescription(id: String, description: String?) -> String? {
        var items = drawingsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Drawing not found." }
        items[index].description = description
        drawingsStore.writeAll(items)
        return nil
    }

    /// Renames the file on disk (not just a label), so Finder and the
    /// app never disagree about what a drawing is called.
    func renameDrawing(id: String, newDisplayName: String) -> String? {
        var items = drawingsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Drawing not found." }
        let oldURL = URL(fileURLWithPath: items[index].filePath)
        guard FileManager.default.fileExists(atPath: oldURL.path) else {
            return "The original file could not be found, so it can't be renamed. Try Locate File first."
        }
        let ext = oldURL.pathExtension
        let sanitized = safeFileBaseName(newDisplayName, extension: ext)
        guard !sanitized.isEmpty else { return "Enter a name." }
        let newFilename = ext.isEmpty ? sanitized : "\(sanitized).\(ext)"
        guard newFilename != oldURL.lastPathComponent else { return nil }
        guard !FileManager.default.fileExists(atPath: oldURL.deletingLastPathComponent().appendingPathComponent(newFilename).path) else {
            return "A file called \"\(newFilename)\" already exists in that folder."
        }
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newFilename)
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            return "Could not rename the file: \(error.localizedDescription)"
        }
        items[index].storedFilename = newFilename
        items[index].filePath = newURL.path
        drawingsStore.writeAll(items)
        return nil
    }

    /// Soft delete (section 33: "Archive/delete where appropriate") —
    /// the file on disk is untouched.
    func archiveDrawing(id: String) -> String? {
        var items = drawingsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Drawing not found." }
        items[index].isArchived = true
        drawingsStore.writeAll(items)
        return nil
    }

    /// Section 38's "Remove Reference" — only removes ScaffoldPro's own
    /// record. Never touches the filesystem.
    func removeDrawingReference(id: String) -> String? {
        var items = drawingsStore.readAll()
        guard items.contains(where: { $0.id == id }) else { return "Drawing not found." }
        items.removeAll { $0.id == id }
        drawingsStore.writeAll(items)
        return nil
    }

    /// Section 38's "Locate File" / "Re-link" — points the record at
    /// wherever the person says the file actually is now, without
    /// moving or copying anything.
    func relinkDrawing(id: String, newPath: String) -> String? {
        var items = drawingsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Drawing not found." }
        guard FileManager.default.fileExists(atPath: newPath) else { return "That file could not be found." }
        let url = URL(fileURLWithPath: newPath)
        let attrs = try? FileManager.default.attributesOfItem(atPath: newPath)
        items[index].filePath = newPath
        items[index].storedFilename = url.lastPathComponent
        items[index].fileSizeBytes = (attrs?[.size] as? Int) ?? items[index].fileSizeBytes
        drawingsStore.writeAll(items)
        return nil
    }

    /// Section 14 "Replace": points the record at a newly copied file.
    /// The caller has already moved the previous copy to Superseded/.
    func replaceDrawingFile(id: String, originalName: String, storedURL: URL) -> String? {
        var items = drawingsStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Drawing not found." }
        let attrs = try? FileManager.default.attributesOfItem(atPath: storedURL.path)
        let previous = items[i].originalName
        items[i].originalName = originalName
        items[i].storedFilename = storedURL.lastPathComponent
        items[i].filePath = storedURL.path
        items[i].fileType = storedURL.pathExtension.uppercased()
        items[i].fileSizeBytes = (attrs?[.size] as? Int) ?? 0
        items[i].uploadedAt = nowISO()
        drawingsStore.writeAll(items)
        logActivity(projectId: items[i].projectId, "Drawing replaced with a new version", reference: "\(previous) → \(originalName)")
        return nil
    }

    func replaceDocumentFile(id: String, originalName: String, storedURL: URL) -> String? {
        var items = documentsStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        let attrs = try? FileManager.default.attributesOfItem(atPath: storedURL.path)
        let previous = items[i].originalName
        items[i].originalName = originalName
        items[i].storedFilename = storedURL.lastPathComponent
        items[i].filePath = storedURL.path
        items[i].fileType = storedURL.pathExtension.uppercased()
        items[i].fileSizeBytes = (attrs?[.size] as? Int) ?? 0
        items[i].uploadedAt = nowISO()
        documentsStore.writeAll(items)
        logActivity(projectId: items[i].projectId, "Document replaced with a new version", reference: "\(previous) → \(originalName)")
        return nil
    }

    // ---- General project documents (Phase 11 — section 34) ----

    func listDocuments(projectId: String) -> [ProjectDocumentSummary] {
        documentsStore.readAll()
            .filter { $0.projectId == projectId && !$0.isArchived }
            .sorted { $0.uploadedAt > $1.uploadedAt }
            .map { d in
                ProjectDocumentSummary(
                    id: d.id, originalName: d.originalName, storedFilename: d.storedFilename,
                    category: d.category, fileType: d.fileType, fileSizeBytes: d.fileSizeBytes,
                    description: d.description, uploadedAt: d.uploadedAt,
                    fileExists: FileManager.default.fileExists(atPath: d.filePath)
                )
            }
    }

    @discardableResult
    func recordDocument(projectId: String, originalName: String, category: String, storedURL: URL) -> ProjectDocument {
        let attrs = try? FileManager.default.attributesOfItem(atPath: storedURL.path)
        let size = (attrs?[.size] as? Int) ?? 0
        let document = ProjectDocument(
            id: makeId("document"), projectId: projectId, originalName: originalName,
            storedFilename: storedURL.lastPathComponent, filePath: storedURL.path,
            category: category, fileType: storedURL.pathExtension.uppercased(), fileSizeBytes: size,
            description: nil, isArchived: false, uploadedAt: nowISO()
        )
        documentsStore.insert(document)
        logActivity(projectId: projectId, "Document uploaded (\(category))", reference: originalName)
        return document
    }

    func getDocument(id: String) -> ProjectDocument? {
        documentsStore.readAll().first { $0.id == id }
    }

    func updateDocumentDescription(id: String, description: String?) -> String? {
        var items = documentsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        items[index].description = description
        documentsStore.writeAll(items)
        return nil
    }

    func renameDocument(id: String, newDisplayName: String) -> String? {
        var items = documentsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        let oldURL = URL(fileURLWithPath: items[index].filePath)
        guard FileManager.default.fileExists(atPath: oldURL.path) else {
            return "The original file could not be found, so it can't be renamed. Try Locate File first."
        }
        let ext = oldURL.pathExtension
        let sanitized = safeFileBaseName(newDisplayName, extension: ext)
        guard !sanitized.isEmpty else { return "Enter a name." }
        let newFilename = ext.isEmpty ? sanitized : "\(sanitized).\(ext)"
        guard newFilename != oldURL.lastPathComponent else { return nil }
        guard !FileManager.default.fileExists(atPath: oldURL.deletingLastPathComponent().appendingPathComponent(newFilename).path) else {
            return "A file called \"\(newFilename)\" already exists in that folder."
        }
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newFilename)
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            return "Could not rename the file: \(error.localizedDescription)"
        }
        items[index].storedFilename = newFilename
        items[index].filePath = newURL.path
        documentsStore.writeAll(items)
        return nil
    }

    func archiveDocument(id: String) -> String? {
        var items = documentsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        items[index].isArchived = true
        documentsStore.writeAll(items)
        return nil
    }

    func removeDocumentReference(id: String) -> String? {
        var items = documentsStore.readAll()
        guard items.contains(where: { $0.id == id }) else { return "Document not found." }
        items.removeAll { $0.id == id }
        documentsStore.writeAll(items)
        return nil
    }

    func relinkDocument(id: String, newPath: String) -> String? {
        var items = documentsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        guard FileManager.default.fileExists(atPath: newPath) else { return "That file could not be found." }
        let url = URL(fileURLWithPath: newPath)
        let attrs = try? FileManager.default.attributesOfItem(atPath: newPath)
        items[index].filePath = newPath
        items[index].storedFilename = url.lastPathComponent
        items[index].fileSizeBytes = (attrs?[.size] as? Int) ?? items[index].fileSizeBytes
        documentsStore.writeAll(items)
        return nil
    }

    // ---- Workers (Phase 12 — section 41) ----

    func listWorkers(includeArchived: Bool) -> [Worker] {
        workersStore.readAll()
            .filter { includeArchived || !$0.isArchived }
            .sorted { $0.workerNumber < $1.workerNumber }
    }

    func getWorker(id: String) -> Worker? {
        workersStore.readAll().first { $0.id == id }
    }

    /// "W001", "W002", ... — never reused, even after archiving.
    func nextWorkerNumber() -> String {
        let sequences = workersStore.readAll().compactMap { Int($0.workerNumber.dropFirst()) }
        return "W" + String(format: "%03d", (sequences.max() ?? 0) + 1)
    }

    func createWorker(_ payload: [String: Any]) -> Result<Worker, WorkerError> {
        let name = ((payload["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(WorkerError(message: "Name is required.")) }
        let worker = Worker(
            id: makeId("worker"), workerNumber: nextWorkerNumber(), name: name,
            position: nonEmpty(payload["position"]), phone: nonEmpty(payload["phone"]),
            email: nonEmpty(payload["email"]), startDate: nonEmpty(payload["startDate"]),
            endDate: nonEmpty(payload["endDate"]), notes: nonEmpty(payload["notes"]),
            isArchived: false, createdAt: nowISO()
        )
        workersStore.insert(worker)
        return .success(worker)
    }

    func updateWorker(id: String, payload: [String: Any]) -> String? {
        var workers = workersStore.readAll()
        guard let index = workers.firstIndex(where: { $0.id == id }) else { return "Worker not found." }
        let name = ((payload["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Name is required." }
        workers[index].name = name
        workers[index].position = nonEmpty(payload["position"])
        workers[index].phone = nonEmpty(payload["phone"])
        workers[index].email = nonEmpty(payload["email"])
        workers[index].startDate = nonEmpty(payload["startDate"])
        workers[index].endDate = nonEmpty(payload["endDate"])
        workers[index].notes = nonEmpty(payload["notes"])
        workersStore.writeAll(workers)
        return nil
    }

    func setWorkerArchived(id: String, archived: Bool) -> String? {
        var workers = workersStore.readAll()
        guard let index = workers.firstIndex(where: { $0.id == id }) else { return "Worker not found." }
        workers[index].isArchived = archived
        workersStore.writeAll(workers)
        return nil
    }

    private func nonEmpty(_ value: Any?) -> String? {
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    // ---- Worker documents (Phase 12 — section 42) ----

    func listWorkerDocuments(workerId: String) -> [WorkerDocumentSummary] {
        workerDocumentsStore.readAll()
            .filter { $0.workerId == workerId && !$0.isArchived }
            .sorted { $0.uploadedAt > $1.uploadedAt }
            .map { d in
                WorkerDocumentSummary(
                    id: d.id, originalName: d.originalName, storedFilename: d.storedFilename,
                    category: d.category, fileType: d.fileType, fileSizeBytes: d.fileSizeBytes,
                    description: d.description, expiryDate: d.expiryDate, uploadedAt: d.uploadedAt,
                    fileExists: FileManager.default.fileExists(atPath: d.filePath)
                )
            }
    }

    @discardableResult
    func recordWorkerDocument(workerId: String, originalName: String, category: String, expiryDate: String?, storedURL: URL) -> WorkerDocument {
        let attrs = try? FileManager.default.attributesOfItem(atPath: storedURL.path)
        let doc = WorkerDocument(
            id: makeId("wdoc"), workerId: workerId, originalName: originalName,
            storedFilename: storedURL.lastPathComponent, filePath: storedURL.path,
            category: category, fileType: storedURL.pathExtension.uppercased(),
            fileSizeBytes: (attrs?[.size] as? Int) ?? 0, description: nil,
            expiryDate: expiryDate, isArchived: false, uploadedAt: nowISO()
        )
        workerDocumentsStore.insert(doc)
        return doc
    }

    func getWorkerDocument(id: String) -> WorkerDocument? {
        workerDocumentsStore.readAll().first { $0.id == id }
    }

    func updateWorkerDocument(id: String, description: String?, expiryDate: String?) -> String? {
        var docs = workerDocumentsStore.readAll()
        guard let index = docs.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        docs[index].description = description
        docs[index].expiryDate = expiryDate
        workerDocumentsStore.writeAll(docs)
        return nil
    }

    func archiveWorkerDocument(id: String) -> String? {
        var docs = workerDocumentsStore.readAll()
        guard let index = docs.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        docs[index].isArchived = true
        workerDocumentsStore.writeAll(docs)
        return nil
    }

    func removeWorkerDocumentReference(id: String) -> String? {
        var docs = workerDocumentsStore.readAll()
        guard docs.contains(where: { $0.id == id }) else { return "Document not found." }
        docs.removeAll { $0.id == id }
        workerDocumentsStore.writeAll(docs)
        return nil
    }

    func relinkWorkerDocument(id: String, newPath: String) -> String? {
        var docs = workerDocumentsStore.readAll()
        guard let index = docs.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        guard FileManager.default.fileExists(atPath: newPath) else { return "That file could not be found." }
        let attrs = try? FileManager.default.attributesOfItem(atPath: newPath)
        docs[index].filePath = newPath
        docs[index].storedFilename = URL(fileURLWithPath: newPath).lastPathComponent
        docs[index].fileSizeBytes = (attrs?[.size] as? Int) ?? docs[index].fileSizeBytes
        workerDocumentsStore.writeAll(docs)
        return nil
    }

    // ---- Administrative documents (Phase 12 — section 43) ----

    func listAdminDocuments() -> [AdminDocumentSummary] {
        adminDocumentsStore.readAll()
            .filter { !$0.isArchived }
            .sorted { $0.uploadedAt > $1.uploadedAt }
            .map { d in
                AdminDocumentSummary(
                    id: d.id, originalName: d.originalName, storedFilename: d.storedFilename,
                    category: d.category, fileType: d.fileType, fileSizeBytes: d.fileSizeBytes,
                    description: d.description, expiryDate: d.expiryDate, uploadedAt: d.uploadedAt,
                    fileExists: FileManager.default.fileExists(atPath: d.filePath)
                )
            }
    }

    @discardableResult
    func recordAdminDocument(originalName: String, category: String, expiryDate: String?, storedURL: URL) -> AdminDocument {
        let attrs = try? FileManager.default.attributesOfItem(atPath: storedURL.path)
        let doc = AdminDocument(
            id: makeId("adoc"), originalName: originalName,
            storedFilename: storedURL.lastPathComponent, filePath: storedURL.path,
            category: category, fileType: storedURL.pathExtension.uppercased(),
            fileSizeBytes: (attrs?[.size] as? Int) ?? 0, description: nil,
            expiryDate: expiryDate, isArchived: false, uploadedAt: nowISO()
        )
        adminDocumentsStore.insert(doc)
        return doc
    }

    func getAdminDocument(id: String) -> AdminDocument? {
        adminDocumentsStore.readAll().first { $0.id == id }
    }

    func updateAdminDocument(id: String, description: String?, expiryDate: String?) -> String? {
        var docs = adminDocumentsStore.readAll()
        guard let index = docs.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        docs[index].description = description
        docs[index].expiryDate = expiryDate
        adminDocumentsStore.writeAll(docs)
        return nil
    }

    func archiveAdminDocument(id: String) -> String? {
        var docs = adminDocumentsStore.readAll()
        guard let index = docs.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        docs[index].isArchived = true
        adminDocumentsStore.writeAll(docs)
        return nil
    }

    func removeAdminDocumentReference(id: String) -> String? {
        var docs = adminDocumentsStore.readAll()
        guard docs.contains(where: { $0.id == id }) else { return "Document not found." }
        docs.removeAll { $0.id == id }
        adminDocumentsStore.writeAll(docs)
        return nil
    }

    func relinkAdminDocument(id: String, newPath: String) -> String? {
        var docs = adminDocumentsStore.readAll()
        guard let index = docs.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        guard FileManager.default.fileExists(atPath: newPath) else { return "That file could not be found." }
        let attrs = try? FileManager.default.attributesOfItem(atPath: newPath)
        docs[index].filePath = newPath
        docs[index].storedFilename = URL(fileURLWithPath: newPath).lastPathComponent
        docs[index].fileSizeBytes = (attrs?[.size] as? Int) ?? docs[index].fileSizeBytes
        adminDocumentsStore.writeAll(docs)
        return nil
    }

    /// After a restore: any stored file path that starts with the backup's
    /// original ~/Documents/ScaffoldPro location is re-pointed at this
    /// Mac's location. A no-op when restoring on the same Mac/account.
    func rebaseFilePaths(from oldRoot: String, to newRoot: String) {
        guard oldRoot != newRoot, !oldRoot.isEmpty else { return }
        func rebase<T: Codable & HasFilePath>(_ store: JSONStore<T>) {
            var items = store.readAll()
            var changed = false
            for i in items.indices where items[i].filePath.hasPrefix(oldRoot + "/") {
                items[i].filePath = newRoot + String(items[i].filePath.dropFirst(oldRoot.count))
                changed = true
            }
            if changed { store.writeAll(items) }
        }
        rebase(drawingsStore)
        rebase(documentsStore)
        rebase(workerDocumentsStore)
        rebase(adminDocumentsStore)
        func rebasePDF(_ path: String?) -> String? {
            guard let p = path, p.hasPrefix(oldRoot + "/") else { return path }
            return newRoot + String(p.dropFirst(oldRoot.count))
        }
        var boqs = boqsStore.readAll()
        for i in boqs.indices { boqs[i].pdfPath = rebasePDF(boqs[i].pdfPath) }
        boqsStore.writeAll(boqs)
        var quotations = quotationsStore.readAll()
        for i in quotations.indices { quotations[i].pdfPath = rebasePDF(quotations[i].pdfPath) }
        quotationsStore.writeAll(quotations)
        var invoices = invoicesStore.readAll()
        for i in invoices.indices { invoices[i].pdfPath = rebasePDF(invoices[i].pdfPath) }
        invoicesStore.writeAll(invoices)
        var notes = deliveryNotesStore.readAll()
        for i in notes.indices { notes[i].pdfPath = rebasePDF(notes[i].pdfPath) }
        deliveryNotesStore.writeAll(notes)
        var settings = getCompanySettings()
        if let logo = settings.logoPath, logo.hasPrefix(oldRoot + "/") {
            settings.logoPath = newRoot + String(logo.dropFirst(oldRoot.count))
            settingsStore.writeAll([settings])
        }
    }

    /// Section 42/43: "where documents have expiry dates, provide useful
    /// reminders." Anything expired or expiring within 30 days, across
    /// worker documents and admin documents, soonest first.
    func expiringDocuments(withinDays days: Int) -> [ExpiringDocument] {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        let today = Calendar.current.startOfDay(for: Date())
        guard let cutoff = Calendar.current.date(byAdding: .day, value: days, to: today) else { return [] }

        func daysLeft(_ expiry: String?) -> Int? {
            guard let expiry = expiry, let date = dayFormatter.date(from: String(expiry.prefix(10))) else { return nil }
            guard date <= cutoff else { return nil }
            return Calendar.current.dateComponents([.day], from: today, to: date).day
        }

        let workers = workersStore.readAll()
        var result: [ExpiringDocument] = []
        for d in workerDocumentsStore.readAll() where !d.isArchived {
            guard let left = daysLeft(d.expiryDate), let worker = workers.first(where: { $0.id == d.workerId }), !worker.isArchived else { continue }
            result.append(ExpiringDocument(id: d.id, kind: "Worker", ownerName: "\(worker.workerNumber) \(worker.name)", originalName: d.originalName, category: d.category, expiryDate: d.expiryDate ?? "", daysLeft: left))
        }
        for d in adminDocumentsStore.readAll() where !d.isArchived {
            guard let left = daysLeft(d.expiryDate) else { continue }
            result.append(ExpiringDocument(id: d.id, kind: "Company", ownerName: "Company", originalName: d.originalName, category: d.category, expiryDate: d.expiryDate ?? "", daysLeft: left))
        }
        return result.sorted { $0.daysLeft < $1.daysLeft }
    }
}

// =====================================================================
// MARK: - PDF generation (Phase 13)
//
// Every document uses the layout of the company's own quotation Qt26193:
// the Proficiency (HK) letterhead and footer on every page, EB Garamond
// body text, black-ruled tables with "HK$" at the left of money cells,
// and the original's colours. All positions, sizes and colours were
// measured from the original (A4, points from the top-left corner);
// drawing converts them to the PDF's bottom-left origin. On Letter
// paper the body and footer are centred on the wider page.
//
// Letterhead and footer are drawn to match the original exactly: each
// piece of the letterhead is scaled so its drawn outline fills the same
// box it fills on the original, whichever font variant the Mac has.
// =====================================================================

/// The letterhead's colours, measured from the original document.
enum LetterheadColor {
    static let orange = NSColor(srgbRed: 241 / 255, green: 158 / 255, blue: 56 / 255, alpha: 1)
    static let grey = NSColor(srgbRed: 153 / 255, green: 153 / 255, blue: 153 / 255, alpha: 1)
    static let darkGrey = NSColor(srgbRed: 102 / 255, green: 102 / 255, blue: 102 / 255, alpha: 1)
    static let link = NSColor(srgbRed: 40 / 255, green: 84 / 255, blue: 197 / 255, alpha: 1)
}

/// Drawings added after a document's own pages: every page of a PDF as
/// it is, and each image on a page of its own (the document's paper size,
/// turned landscape for a wide image), fitted inside a 24pt margin.
enum PDFAttachments {
    static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]

    static func canAppend(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "pdf" || imageTypes.contains(ext)
    }

    static func append(_ files: [URL], to data: Data, paperSize: NSSize) -> Data {
        guard !files.isEmpty, let document = PDFDocument(data: data) else { return data }
        for url in files {
            if url.pathExtension.lowercased() == "pdf" {
                guard let drawing = PDFDocument(url: url), !drawing.isLocked else { continue }
                for i in 0..<drawing.pageCount {
                    if let page = drawing.page(at: i)?.copy() as? PDFPage { document.insert(page, at: document.pageCount) }
                }
            } else if let page = imagePage(url, paperSize: paperSize) {
                document.insert(page, at: document.pageCount)
            }
        }
        return document.dataRepresentation() ?? data
    }

    private static func imagePage(_ url: URL, paperSize: NSSize) -> PDFPage? {
        guard let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let wide = cg.width > cg.height
        let short = min(paperSize.width, paperSize.height), long = max(paperSize.width, paperSize.height)
        var box = CGRect(x: 0, y: 0, width: wide ? long : short, height: wide ? short : long)
        let margin: CGFloat = 24
        let scale = min((box.width - 2 * margin) / CGFloat(cg.width), (box.height - 2 * margin) / CGFloat(cg.height))
        let size = CGSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        context.beginPDFPage(nil)
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2, width: size.width, height: size.height))
        context.endPDFPage()
        context.closePDF()
        return PDFDocument(data: data as Data)?.page(at: 0)
    }
}

final class PDFGenerator {
    private let paperSize: String
    private let pageWidth: CGFloat
    private let pageHeight: CGFloat
    private let mutableData: NSMutableData
    private let context: CGContext
    private var pageNumber = 0
    /// Distance from the page top of the last thing drawn: the last
    /// baseline after text, or the bottom rule after a table.
    private var cursor: CGFloat = 0

    // Measured on A4; on Letter the body and footer are centred.
    private var dx: CGFloat { (pageWidth - 595.28) / 2 }
    private var footerDY: CGFloat { pageHeight - 841.89 }
    private var textLeft: CGFloat { 42.75 + dx }
    private var textRight: CGFloat { 552.0 + dx }
    private var textWidth: CGFloat { textRight - textLeft }
    /// Nothing goes below this; the footer rule starts at 792.75.
    private var contentBottom: CGFloat { 781.5 + footerDY }
    /// First baseline, or table top, on a continuation page.
    private let continuationBaseline: CGFloat = 95.25
    private let continuationTableTop: CGFloat = 88.0
    /// Body text line spacing (11pt EB Garamond, as on the original).
    private let bodyPitch: CGFloat = 16.5
    /// Table rules are 0.75pt black; a one-line row is 24.1pt tall and
    /// each further line of text adds 14.9pt, with lines 14.25pt apart.
    private let rule: CGFloat = 0.75
    private var rowHeight: CGFloat = 24.1
    private let cellPitch: CGFloat = 14.25
    /// Heading row height, and where one line of text sits below a
    /// row's middle (compact tables: 23pt, 21.1pt rows, 4.1pt).
    private var headerHeight: CGFloat = 24.1
    private var baselineBelowMiddle: CGFloat = 5.2

    private func configure(for doc: LetterDocument) {
        rowHeight = doc.compactTable ? 21.1 : 24.1
        headerHeight = doc.compactTable ? 23.0 : 24.1
        baselineBelowMiddle = doc.compactTable ? 4.1 : 5.2
    }

    /// "A4" (595.28 × 841.89 pt) or "Letter" (612 × 792 pt) — sections 27, 54.
    init?(paperSize: String = "A4") {
        self.paperSize = paperSize
        if paperSize == "Letter" {
            pageWidth = 612
            pageHeight = 792
        } else {
            pageWidth = 595.28
            pageHeight = 841.89
        }
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        mutableData = data
        context = ctx
    }

    /// Draws into a bitmap instead of a PDF: for the letterhead picture of
    /// Word documents.
    private init?(bitmapPaperSize paperSize: String, scale: CGFloat) {
        self.paperSize = paperSize
        if paperSize == "Letter" {
            pageWidth = 612
            pageHeight = 792
        } else {
            pageWidth = 595.28
            pageHeight = 841.89
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int((pageWidth * scale).rounded()), height: Int((pageHeight * scale).rounded()),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        mutableData = NSMutableData()
        context = ctx
    }

    /// The letterhead and footer (without the page number, which Word adds
    /// as a field) as a transparent, page-sized PNG at 300 dpi.
    static func letterheadPNG(paperSize: String) -> Data? {
        guard let generator = PDFGenerator(bitmapPaperSize: paperSize, scale: 300.0 / 72.0) else { return nil }
        generator.showPageNumber = false
        generator.drawLetterhead()
        generator.drawFooter()
        guard let image = generator.context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Off for the Word letterhead picture.
    private var showPageNumber = true

    // MARK: fonts

    private func firstFont(_ names: [String], _ size: CGFloat) -> NSFont {
        for name in names {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return NSFont.systemFont(ofSize: size)
    }

    /// EB Garamond — bundled with the app (resources/fonts) and
    /// registered at launch. Georgia if it's somehow unavailable.
    private func body(_ size: CGFloat = 11, bold: Bool = false, italic: Bool = false) -> NSFont {
        switch (bold, italic) {
        case (true, true): return firstFont(["EBGaramond-BoldItalic", "Georgia-BoldItalic"], size)
        case (true, false): return firstFont(["EBGaramond-Bold", "Georgia-Bold"], size)
        case (false, true): return firstFont(["EBGaramond-Italic", "Georgia-Italic"], size)
        case (false, false): return firstFont(["EBGaramond-Regular", "Georgia"], size)
        }
    }

    /// Times New Roman — the footer, signature block and closing line.
    private func times(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        switch (bold, italic) {
        case (true, true): return firstFont(["TimesNewRomanPS-BoldItalicMT", "Times-BoldItalic"], size)
        case (true, false): return firstFont(["TimesNewRomanPS-BoldMT", "Times-Bold"], size)
        case (false, true): return firstFont(["TimesNewRomanPS-ItalicMT", "Times-Italic"], size)
        case (false, false): return firstFont(["TimesNewRomanPSMT", "Times-Roman"], size)
        }
    }

    private let letterheadLatin = ["Verdana-Bold", "Tahoma-Bold", "Helvetica-Bold"]
    /// "ScaffoldPro Letterhead TC" is Noto Sans TC cut down to the logo's
    /// characters, bundled in resources/fonts (SIL Open Font License).
    private let letterheadChinese = ["ScaffoldProLetterheadTC-Regular", "NotoSansTC-Regular", "NotoSansHK-Regular", "PingFangHK-Regular"]
    private let footerChinese = ["STSongti-TC-Regular", "STSong", "PingFangHK-Regular"]

    // MARK: low-level drawing (top-down coordinates)

    private func fill(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: NSColor) {
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: x, y: pageHeight - top - height, width: width, height: height))
    }

    private func makeLine(_ string: String, _ font: NSFont, _ color: NSColor) -> CTLine {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    private func lineWidth(_ line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    private func draw(_ line: CTLine, x: CGFloat, baseline: CGFloat) {
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: pageHeight - baseline)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// One line of text on a baseline; returns its width.
    @discardableResult
    private func text(_ string: String, x: CGFloat, baseline: CGFloat, font: NSFont, color: NSColor = .black,
                      align: NSTextAlignment = .left, underline: Bool = false) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        let line = makeLine(string, font, color)
        let width = lineWidth(line)
        let startX: CGFloat
        switch align {
        case .right: startX = x - width
        case .center: startX = x - width / 2
        default: startX = x
        }
        draw(line, x: startX, baseline: baseline)
        if underline { underlineRun(x: startX, width: width, baseline: baseline, font: font, color: color) }
        return width
    }

    /// EB Garamond's own underline position and thickness.
    private func underlineRun(x: CGFloat, width: CGFloat, baseline: CGFloat, font: NSFont, color: NSColor) {
        fill(x, baseline + font.pointSize * 0.1, width, max(0.6, font.pointSize * 0.05), color)
    }

    private func inkBounds(_ line: CTLine) -> CGRect {
        CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    }

    /// Places text so its drawn outline starts exactly at `inkLeft`, or
    /// ends exactly at `inkRight`.
    private func textAtInk(_ string: String, inkLeft: CGFloat? = nil, inkRight: CGFloat? = nil, baseline: CGFloat, font: NSFont, color: NSColor) {
        let line = makeLine(string, font, color)
        let ink = inkBounds(line)
        let x: CGFloat
        if let left = inkLeft { x = left - ink.minX } else { x = (inkRight ?? 0) - ink.maxX }
        draw(line, x: x, baseline: baseline)
    }

    /// Scales text so its drawn outline exactly fills a box measured from
    /// the original letterhead.
    private func fitted(_ string: String, fonts: [String], color: NSColor, left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
        let line = makeLine(string, firstFont(fonts, 100), color)
        let ink = inkBounds(line)
        guard ink.width > 0, ink.height > 0 else { return }
        let sx = (right - left) / ink.width
        let sy = (bottom - top) / ink.height
        context.saveGState()
        context.translateBy(x: left - ink.minX * sx, y: (pageHeight - bottom) - ink.minY * sy)
        context.scaleBy(x: sx, y: sy)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Breaks text into lines no wider than `width`; "\n" always breaks.
    private func wrap(_ string: String, _ font: NSFont, _ width: CGFloat) -> [String] {
        var result: [String] = []
        for paragraph in string.components(separatedBy: "\n") {
            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let attributed = NSAttributedString(string: trimmed, attributes: [.font: font])
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            let ns = trimmed as NSString
            var start = 0
            while start < ns.length {
                let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(max(width, 10))))
                result.append(ns.substring(with: NSRange(location: start, length: min(count, ns.length - start))).trimmingCharacters(in: .whitespaces))
                start += count
            }
        }
        return result
    }

    // MARK: letterhead and footer (identical on every page and document)

    private func drawLetterhead() {
        let orange = LetterheadColor.orange, grey = LetterheadColor.grey, darkGrey = LetterheadColor.darkGrey
        fitted("P", fonts: letterheadLatin, color: orange, left: 42.75, top: 28.5, right: 57.75, bottom: 46.5)
        fitted("ROFICIENCY", fonts: letterheadLatin, color: grey, left: 60.0, top: 31.5, right: 200.25, bottom: 47.25)
        fill(6.0, 51.0, 209.25, 2.25, orange)
        // Noto Sans (Traditional Chinese) at 15pt, its natural shape — not
        // stretched to fit — starting where the original's does.
        textAtInk("建機 (香港) 有限公司", inkLeft: 41.25, baseline: 72.25, font: firstFont(letterheadChinese, 15), color: darkGrey)
        fitted("(HK)", fonts: letterheadLatin, color: orange, left: 190.5, top: 58.5, right: 240.75, bottom: 77.25)
        fitted("LIMITED", fonts: letterheadLatin, color: grey, left: 251.25, top: 61.5, right: 331.5, bottom: 74.25)
        fill(189.0, 78.0, pageWidth - 6.53 - 189.0, 2.25, orange)
    }

    private func drawFooter() {
        let grey = LetterheadColor.grey
        let x = dx, y = footerDY
        fill(42.75 + x, 792.75 + y, 510.0, 2.25, LetterheadColor.orange)

        let chinese: [(String, CGFloat, CGFloat)] = [
            ("香港", 210.75, 228.75), ("北角", 231.75, 248.25), ("蜆殼街 9-23", 252.0, 297.0),
            ("號", 300.0, 308.25), ("秀明中心", 311.25, 346.5), ("17樓 B室", 349.5, 384.0),
        ]
        for (segment, left, right) in chinese {
            fitted(segment, fonts: footerChinese, color: grey, left: left + x, top: 798.75 + y, right: right + x, bottom: 807.75 + y)
        }

        let font = times(9)
        let words = "Unit B, 17/F, Seabright Plaza, 9-23 Shell Street, Causeway Bay, Hong Kong".components(separatedBy: " ")
        let wordLefts: [CGFloat] = [160.5, 178.5, 189.75, 209.25, 246.0, 270.0, 288.75, 309.75, 335.25, 374.25, 393.0, 414.75]
        for (word, left) in zip(words, wordLefts) {
            textAtInk(word, inkLeft: left + x, baseline: 816.75 + y, font: font, color: grey)
        }
        let contacts: [(String, CGFloat)] = [("Tel: +852 2690 0133", 153.0), ("Email: rk123@pfitnet.com", 249.75), ("Fax: +852 2663 0371", 368.25)]
        for (segment, left) in contacts {
            textAtInk(segment, inkLeft: left + x, baseline: 827.25 + y, font: font, color: grey)
        }
        if showPageNumber {
            textAtInk("Page \(pageNumber)", inkRight: 552.0 + x, baseline: 827.25 + y, font: times(9, italic: true), color: grey)
        }
    }

    private func beginPage() {
        context.beginPDFPage(nil)
        pageNumber += 1
        drawLetterhead()
    }

    private func endPage() {
        drawFooter()
        context.endPDFPage()
    }

    private func newPage() {
        endPage()
        beginPage()
    }

    // MARK: opening (client, references, title, "Re:")

    /// Extra space above and below the title ("QUOTATION", "BILL OF
    /// QUANTITIES", …), on top of the original's spacing.
    static let titlePadding: CGFloat = 6.0
    private var titlePadding: CGFloat { PDFGenerator.titlePadding }

    /// The client's name (bold) and address, as printed: each address line
    /// kept to 260pt, a long one broken after its commas where it can be
    /// ("38th Floor, Dorset House, Taikoo Place," / "979 King's Road, …").
    private func clientBlockLines(_ doc: LetterDocument) -> [(text: String, bold: Bool)] {
        var lines = wrap(doc.clientName, body(12, bold: true), 300).map { (text: $0, bold: true) }
        for line in doc.clientLines {
            lines += wrapAddress(line, body(12), 260).map { (text: $0, bold: false) }
        }
        return lines
    }

    private func wrapAddress(_ line: String, _ font: NSFont, _ width: CGFloat) -> [String] {
        let fits: (String) -> Bool = { self.lineWidth(self.makeLine($0, font, .black)) <= width }
        let parts = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // A line typed with a comma at the end keeps it ("38th Floor, Dorset House,").
        let endsWithComma = line.trimmingCharacters(in: .whitespaces).hasSuffix(",")
        var out: [String] = []
        var current = ""
        for (i, part) in parts.enumerated() {
            let piece = i < parts.count - 1 || endsWithComma ? part + "," : part
            let candidate = current.isEmpty ? piece : current + " " + piece
            if current.isEmpty || fits(candidate) {
                current = candidate
            } else {
                out.append(current)
                current = piece
            }
        }
        if !current.isEmpty { out.append(current) }
        return out.flatMap { fits($0) ? [$0] : wrap($0, font, width) }
    }

    private func drawOpening(_ doc: LetterDocument) {
        let blockLeft = 47.75 + dx
        let firstBaseline: CGFloat = 104.25
        let pitch: CGFloat = 15.75

        let left = clientBlockLines(doc)
        for (i, item) in left.enumerated() {
            text(item.text, x: blockLeft, baseline: firstBaseline + CGFloat(i) * pitch, font: body(12, bold: item.bold))
        }

        // Reference block: label, colon, value right-aligned; a value too
        // long for the space runs on under itself, left-aligned.
        let refFont = body(11)
        var refLine = 0
        for row in doc.refRows {
            let baseline = firstBaseline + CGFloat(refLine) * pitch
            text(row.label, x: 401.25 + dx, baseline: baseline, font: refFont)
            text(":", x: 478.5 + dx, baseline: baseline, font: refFont)
            let valueLines = wrap(row.value, refFont, 66)
            if valueLines.count <= 1 {
                text(row.value, x: 550.5 + dx, baseline: baseline, font: refFont, align: .right)
                refLine += 1
            } else {
                for (j, line) in valueLines.enumerated() {
                    text(line, x: 484.5 + dx, baseline: firstBaseline + CGFloat(refLine + j) * pitch, font: refFont)
                }
                refLine += valueLines.count
            }
        }

        // "BY EMAIL ONLY" goes under the references (beside the client's
        // last line if the address is longer), the title under both.
        let clientLast = firstBaseline + CGFloat(max(left.count, 1) - 1) * pitch
        let refLast = firstBaseline + CGFloat(max(refLine, 1) - 1) * pitch
        var baseline: CGFloat
        if let method = doc.deliveryMethod, !method.isEmpty {
            let methodBaseline = refLast + 19.5
            text(method, x: 550.5 + dx, baseline: methodBaseline, font: body(13, bold: true), align: .right, underline: true)
            baseline = max(methodBaseline + 21.0, clientLast + 24.0) + titlePadding
        } else {
            baseline = max(clientLast, refLast) + 40.5 + titlePadding
        }

        text(doc.title, x: pageWidth / 2, baseline: baseline, font: body(15, bold: true), align: .center, underline: true)
        if doc.status != "Issued" {
            text(doc.status.uppercased(), x: textRight, baseline: baseline, font: body(11, bold: true), color: LetterheadColor.grey, align: .right)
        }
        var last = baseline
        var next = baseline + 18.0 + titlePadding
        if let salutation = doc.salutation, !salutation.isEmpty {
            text(salutation, x: textLeft, baseline: next, font: body(11))
            last = next
            next += bodyPitch
        }
        if let subject = doc.subject, !subject.isEmpty {
            for line in wrap(subject, body(11, bold: true), textWidth) {
                text(line, x: textLeft, baseline: next, font: body(11, bold: true), underline: true)
                last = next
                next += bodyPitch
            }
        }
        if let intro = doc.intro, !intro.isEmpty {
            for line in wrap(intro, body(11), textWidth) {
                text(line, x: textLeft, baseline: next, font: body(11))
                last = next
                next += bodyPitch
            }
        }
        // The table starts 15pt below the last line (243 → 258 on the original).
        cursor = last + 15.0
        guard !doc.infoRows.isEmpty else { return }
        // Labelled lines (the delivery note): bold labels, ": value" at
        // 100.5pt, 17.35pt apart, the first 24pt (plus the title padding)
        // under the title; the table 17.6pt under the last.
        next = last == baseline ? baseline + 24.0 + titlePadding : last + 17.35
        for row in doc.infoRows {
            let lines = infoValueLines(row)
            text(row.label, x: textLeft + 1.5, baseline: next, font: body(11, bold: true))
            text(":", x: infoColonX, baseline: next, font: body(11))
            for (j, line) in lines.enumerated() {
                text(line, x: infoValueX, baseline: next + CGFloat(j) * bodyPitch, font: body(11, bold: row.boldValue))
            }
            last = next + CGFloat(max(lines.count, 1) - 1) * bodyPitch
            next = last + 17.35
        }
        cursor = last + 17.6
    }

    private var infoColonX: CGFloat { textLeft + 100.5 }
    private var infoValueX: CGFloat { infoColonX + lineWidth(makeLine(": ", body(11), .black)) }
    private func infoValueLines(_ row: LetterInfoRow) -> [String] {
        wrap(row.value, body(11, bold: row.boldValue), textRight - infoValueX)
    }

    // MARK: table

    private func columnEdges(_ columns: [LetterColumn]) -> [CGFloat] {
        var edges: [CGFloat] = [42.0 + dx]
        for column in columns { edges.append((edges.last ?? 0) + column.width) }
        return edges
    }

    private func hRule(_ edges: [CGFloat], _ y: CGFloat) {
        guard let first = edges.first, let last = edges.last else { return }
        fill(first, y, last - first + rule, rule, .black)
    }

    private func vRule(_ x: CGFloat, _ top: CGFloat, _ height: CGFloat) {
        fill(x, top, rule, height + rule, .black)
    }

    /// Text is centred vertically in its cell, as on the original.
    private func cellBaseline(top: CGFloat, height: CGFloat, lines: Int, line: Int) -> CGFloat {
        top + height / 2 + baselineBelowMiddle - CGFloat(lines - 1) * cellPitch / 2 + CGFloat(line) * cellPitch
    }

    private func cellLines(_ value: String, column: LetterColumn, font: NSFont, currencyWidth: CGFloat) -> [String] {
        let available = column.width - 10.5 - (column.kind == .money ? currencyWidth + 4 : 0)
            - (column.kind == .weight ? weightSuffixRoom(font) : 0)
        return wrap(value, font, available)
    }

    private func height(of row: LetterTableRow, in doc: LetterDocument) -> CGFloat {
        switch row {
        case .item(let cells):
            let font = body(11)
            let currencyWidth = lineWidth(makeLine(doc.currencySymbol, font, .black))
            var lines = 1
            for (i, cell) in cells.enumerated() where i < doc.columns.count {
                lines = max(lines, cellLines(cell, column: doc.columns[i], font: font, currencyWidth: currencyWidth).count)
            }
            return rowHeight + CGFloat(lines - 1) * 14.9
        case .section:
            return 37.5
        case .summary(_, _, let emphasized):
            return emphasized ? 37.5 : 29.25
        case .partial(let cells, _):
            return height(of: .item(cells), in: doc)
        case .note(let note):
            let lines = wrap(note, noteFont, noteWidth(doc)).count
            return 29.25 + CGFloat(max(1, lines) - 1) * notePitch
        }
    }

    // Table notes: 9.5pt italic, grey, 13pt apart.
    private var noteFont: NSFont { body(9.5, italic: true) }
    private let notePitch: CGFloat = 13.0
    private func noteWidth(_ doc: LetterDocument) -> CGFloat {
        doc.columns.reduce(0) { $0 + $1.width } - 12.0
    }

    private func drawCell(_ lines: [String], column: LetterColumn, left: CGFloat, right: CGFloat, top: CGFloat, height: CGFloat, font: NSFont, currency: String) {
        let count = max(1, lines.count)
        for (j, line) in lines.enumerated() {
            let baseline = cellBaseline(top: top, height: height, lines: count, line: j)
            switch column.kind {
            case .center: text(line, x: (left + right + rule) / 2, baseline: baseline, font: font, align: .center)
            case .left: text(line, x: left + 5.0, baseline: baseline, font: font)
            case .right, .money: text(line, x: right - 3.4, baseline: baseline, font: font, align: .right)
            case .weight:
                guard !line.isEmpty else { continue }
                text(line, x: right - 3.4 - weightSuffixRoom(font), baseline: baseline, font: font, align: .right)
                if j == 0 { text("kg", x: right - 3.4, baseline: baseline, font: font, align: .right) }
            }
        }
        if column.kind == .money, let first = lines.first, !first.isEmpty {
            text(currency, x: left + 5.25, baseline: cellBaseline(top: top, height: height, lines: 1, line: 0), font: font)
        }
    }

    /// "kg" and the space before it, at the right of a weight cell.
    private func weightSuffixRoom(_ font: NSFont) -> CGFloat {
        lineWidth(makeLine("kg", font, .black)) + 8.4
    }

    private func drawHeaderRow(_ columns: [LetterColumn], _ edges: [CGFloat]) {
        let top = cursor
        hRule(edges, top)
        hRule(edges, top + headerHeight)
        for x in edges { vRule(x, top, headerHeight) }
        let font = body(11, bold: true)
        for (i, column) in columns.enumerated() {
            text(column.title, x: (edges[i] + edges[i + 1] + rule) / 2,
                 baseline: cellBaseline(top: top, height: headerHeight, lines: 1, line: 0), font: font, align: .center)
        }
        cursor += headerHeight
    }

    /// Draws the table, repeating the column titles at the top of every
    /// page it runs onto (section 27).
    private func drawTable(_ doc: LetterDocument) {
        guard !doc.columns.isEmpty else { return }
        let edges = columnEdges(doc.columns)
        let last = edges.count - 1
        drawHeaderRow(doc.columns, edges)
        if doc.rows.isEmpty {
            text("No items.", x: textLeft, baseline: cursor + 17.25, font: body(11, italic: true))
            cursor += rowHeight
            return
        }
        for row in doc.rows {
            let h = height(of: row, in: doc)
            if cursor + h > contentBottom {
                newPage()
                cursor = continuationTableTop
                drawHeaderRow(doc.columns, edges)
            }
            let top = cursor
            hRule(edges, top)
            hRule(edges, top + h)
            switch row {
            case .item(let cells):
                for x in edges { vRule(x, top, h) }
                let font = body(11)
                let currencyWidth = lineWidth(makeLine(doc.currencySymbol, font, .black))
                for (i, cell) in cells.enumerated() where i < doc.columns.count {
                    let lines = cellLines(cell, column: doc.columns[i], font: font, currencyWidth: currencyWidth)
                    drawCell(lines, column: doc.columns[i], left: edges[i], right: edges[i + 1], top: top, height: h, font: font, currency: doc.currencySymbol)
                }
            case .section(let title):
                vRule(edges[0], top, h)
                vRule(edges[last], top, h)
                text(title, x: (edges[0] + edges[last] + rule) / 2, baseline: cellBaseline(top: top, height: h, lines: 1, line: 0),
                     font: body(12, bold: true), align: .center)
            case .summary(let label, let value, let emphasized):
                vRule(edges[0], top, h)
                vRule(edges[last - 1], top, h)
                vRule(edges[last], top, h)
                let font = body(emphasized ? 12 : 11, bold: true)
                text(label, x: edges[last - 1] - 4.25, baseline: cellBaseline(top: top, height: h, lines: 1, line: 0), font: font, align: .right)
                drawCell([value], column: doc.columns[last - 1], left: edges[last - 1], right: edges[last], top: top, height: h, font: font, currency: doc.currencySymbol)
            case .partial(let cells, let tail):
                let count = min(cells.count, doc.columns.count - 1)
                for x in edges[0...count] { vRule(x, top, h) }
                vRule(edges[last], top, h)
                let font = body(11)
                let currencyWidth = lineWidth(makeLine(doc.currencySymbol, font, .black))
                for (i, cell) in cells.prefix(count).enumerated() {
                    let lines = cellLines(cell, column: doc.columns[i], font: font, currencyWidth: currencyWidth)
                    drawCell(lines, column: doc.columns[i], left: edges[i], right: edges[i + 1], top: top, height: h, font: font, currency: doc.currencySymbol)
                }
                text(tail, x: (edges[count] + edges[last] + rule) / 2, baseline: cellBaseline(top: top, height: h, lines: 1, line: 0),
                     font: font, align: .center)
            case .note(let note):
                vRule(edges[0], top, h)
                vRule(edges[last], top, h)
                let lines = wrap(note, noteFont, noteWidth(doc))
                let first = top + h / 2 + 3.4 - CGFloat(max(1, lines.count) - 1) * notePitch / 2
                for (j, line) in lines.enumerated() {
                    text(line, x: edges[0] + 6.0, baseline: first + CGFloat(j) * notePitch, font: noteFont, color: LetterheadColor.darkGrey)
                }
            }
            cursor += h
        }
    }

    // MARK: text after the table

    /// Justified paragraph (the last line and lines ending in "\n" are
    /// left-aligned). Returns the last baseline used.
    private func drawParagraph(_ string: String, link: String?, firstBaseline: CGFloat) -> CGFloat {
        let font = body(11)
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let attributed = NSMutableAttributedString(string: string, attributes: [.font: font, colorKey: NSColor.black.cgColor])
        let ns = string as NSString
        var linkRange = NSRange(location: NSNotFound, length: 0)
        if let link = link, !link.isEmpty {
            linkRange = ns.range(of: link)
            if linkRange.location != NSNotFound {
                attributed.addAttribute(colorKey, value: LetterheadColor.link.cgColor, range: linkRange)
            }
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let breaks = CharacterSet.whitespacesAndNewlines
        var start = 0
        var baseline = firstBaseline
        var firstLine = true
        while start < ns.length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(textWidth))
            guard count > 0 else { break }
            // Leave out trailing spaces / the line break itself.
            var visible = count
            var hardBreak = false
            while visible > 0, let scalar = UnicodeScalar(ns.character(at: start + visible - 1)), breaks.contains(scalar) {
                if scalar == "\n" { hardBreak = true }
                visible -= 1
            }
            if !firstLine { baseline += bodyPitch }
            if baseline > contentBottom {
                newPage()
                baseline = continuationBaseline
            }
            firstLine = false
            if visible > 0 {
                var line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: visible))
                let isLast = start + count >= ns.length
                if !isLast, !hardBreak, let justified = CTLineCreateJustifiedLine(line, 1.0, Double(textWidth)) {
                    line = justified
                }
                draw(line, x: textLeft, baseline: baseline)
                if linkRange.location != NSNotFound {
                    let from = max(linkRange.location, start)
                    let to = min(NSMaxRange(linkRange), start + visible)
                    if from < to {
                        let x0 = CTLineGetOffsetForStringIndex(line, from, nil)
                        let x1 = CTLineGetOffsetForStringIndex(line, to, nil)
                        underlineRun(x: textLeft + x0, width: x1 - x0, baseline: baseline, font: font, color: LetterheadColor.link)
                    }
                }
            }
            start += count
        }
        return baseline
    }

    /// "(i) Payment : First two month's rental…" — label at the margin,
    /// colon at 128.25pt, text (and any further lines) at 132pt.
    private func drawTerm(label: String?, lines: [String], firstBaseline: CGFloat) -> CGFloat {
        let font = body(11)
        let textX = 132.0 + dx
        var baseline = firstBaseline
        var firstLine = true
        for raw in lines {
            for piece in wrap(raw, font, textRight - textX) {
                if !firstLine { baseline += bodyPitch }
                if baseline > contentBottom {
                    newPage()
                    baseline = continuationBaseline
                }
                if firstLine {
                    if let label = label { text(label, x: textLeft, baseline: baseline, font: font) }
                    text(":", x: 128.25 + dx, baseline: baseline, font: font)
                }
                text(piece, x: textX, baseline: baseline, font: font)
                firstLine = false
            }
        }
        return baseline
    }

    /// Where a hanging paragraph's text starts, in points from the margin.
    private func hangingTextX(marker: String, left: CGFloat, indent: CGFloat?, colon: Bool) -> CGFloat {
        let markerWidth = marker.isEmpty ? 0 : lineWidth(makeLine(marker, body(11), .black))
        var textX = indent ?? (left + max(18, markerWidth + 6))
        if !marker.isEmpty { textX = max(textX, left + markerWidth + (colon ? 7.5 : 5)) }
        return min(textX, textRight - 120 - textLeft)
    }

    /// A hanging-indent paragraph (see `LetterParagraph.hanging`). A long
    /// label pushes the text column right; the text always keeps at least
    /// 120pt. Returns the last baseline used.
    private func drawHanging(marker: String, lines: [String], left: CGFloat, indent: CGFloat?, colon: Bool, firstBaseline: CGFloat) -> CGFloat {
        let font = body(11)
        let markerX = textLeft + left
        let textX = textLeft + hangingTextX(marker: marker, left: left, indent: indent, colon: colon)
        var baseline = firstBaseline
        if !marker.isEmpty { text(marker, x: markerX, baseline: baseline, font: font) }
        if colon { text(":", x: textX - 3.75, baseline: baseline, font: font) }
        var first = true
        for piece in lines.flatMap({ wrap($0, font, textRight - textX) }) {
            if !first {
                baseline += bodyPitch
                if baseline > contentBottom {
                    newPage()
                    baseline = continuationBaseline
                }
            }
            text(piece, x: textX, baseline: baseline, font: font)
            first = false
        }
        return baseline
    }

    /// Set by `generate` after a trial layout: the sections (by index) that
    /// are kept together but ran over a page there, so start a new page.
    private var sectionsOnNewPage: Set<Int> = []
    /// Recorded while laying out: kept-together sections that ran over a page.
    private(set) var sectionsThatSplit: Set<Int> = []

    /// Which kept-together sections have to start a new page: laid out on
    /// trial (again, if moving one moves another) until none runs over.
    private func keptTogetherBreaks(_ doc: LetterDocument) -> Set<Int> {
        guard doc.sections.contains(where: { $0.keepTogether }) else { return [] }
        var breaks: Set<Int> = []
        for _ in 0..<3 {
            guard let trial = PDFGenerator(paperSize: paperSize) else { break }
            trial.sectionsOnNewPage = breaks
            _ = trial.layOut(doc)
            let more = trial.sectionsThatSplit.subtracting(breaks)
            if more.isEmpty { break }
            breaks.formUnion(more)
        }
        return breaks
    }

    private func drawSections(_ sections: [LetterSection]) {
        var afterTable = true
        for (sectionIndex, section) in sections.enumerated() {
            var baseline = cursor + (afterTable ? 27.0 : 33.0)
            afterTable = false
            if section.alwaysNewPage || sectionsOnNewPage.contains(sectionIndex) {
                newPage()
                baseline = continuationBaseline
            }
            if let heading = section.heading, !heading.isEmpty {
                // Keep the heading with its first line.
                if baseline + 26.25 > contentBottom {
                    newPage()
                    baseline = continuationBaseline
                }
                text(heading, x: textLeft, baseline: baseline, font: body(11, bold: true), underline: true)
                cursor = baseline
                baseline += 26.25
            } else if baseline > contentBottom {
                newPage()
                baseline = continuationBaseline
            }
            let startPage = pageNumber
            defer { if section.keepTogether && pageNumber != startPage { sectionsThatSplit.insert(sectionIndex) } }
            var previousWasTerm = false
            for (index, paragraph) in section.paragraphs.enumerated() {
                switch paragraph {
                case .text(let string, let link):
                    if index > 0 { baseline = cursor + (previousWasTerm ? 33.0 : 26.25) }
                    if baseline > contentBottom {
                        newPage()
                        baseline = continuationBaseline
                    }
                    cursor = drawParagraph(string, link: link, firstBaseline: baseline)
                    previousWasTerm = false
                case .hanging(let marker, let lines, let left, let indent, let colon):
                    if index > 0 { baseline = cursor + (previousWasTerm ? bodyPitch : 26.25) }
                    if baseline > contentBottom {
                        newPage()
                        baseline = continuationBaseline
                    }
                    cursor = drawHanging(marker: marker, lines: lines, left: left, indent: indent, colon: colon, firstBaseline: baseline)
                    previousWasTerm = true
                case .term(let label, let lines):
                    if index > 0 { baseline = cursor + (previousWasTerm ? bodyPitch : 26.25) }
                    if baseline > contentBottom {
                        newPage()
                        baseline = continuationBaseline
                    }
                    cursor = drawTerm(label: label, lines: lines, firstBaseline: baseline)
                    previousWasTerm = true
                }
            }
        }
    }

    // MARK: signatures and closing line

    /// "For and on Behalf of", a signing rule 75.75pt below, then the
    /// party and name/position/date lines — kept together on one page.
    private func drawSignatures(_ signatures: [LetterSignature], afterTable: Bool) {
        guard !signatures.isEmpty else { return }
        var baseline = cursor + (afterTable ? 30.0 : 32.25)
        let maxLines = signatures.map { $0.lines.count }.max() ?? 0
        let blockHeight = 75.75 + 39.0 + CGFloat(max(0, maxLines - 3)) * 14.0 + 6
        if baseline + blockHeight > contentBottom {
            newPage()
            baseline = continuationBaseline
        }
        let font = times(10.5, bold: true, italic: true)
        let columns: [(textX: CGFloat, ruleX: CGFloat, ruleWidth: CGFloat, colonX: CGFloat)] = [
            (48.75 + dx, 43.5 + dx, 225.75, 120.75 + dx),
            (331.5 + dx, 326.25 + dx, 225.0, 403.5 + dx),
        ]
        let offsets: [CGFloat] = [11.25, 24.75, 39.0]
        var lowest = baseline
        for (i, signature) in signatures.prefix(2).enumerated() {
            let column = columns[i]
            text(signature.heading, x: column.textX, baseline: baseline, font: font)
            let ruleY = baseline + 75.75
            fill(column.ruleX, ruleY, column.ruleWidth, 0.75, .black)
            for (j, line) in signature.lines.enumerated() {
                let lineBaseline = ruleY + (j < offsets.count ? offsets[j] : 39.0 + CGFloat(j - 2) * 14.0)
                text(line.text, x: column.textX, baseline: lineBaseline, font: font)
                if line.colon {
                    text(":", x: column.colonX, baseline: lineBaseline, font: font)
                    if let value = line.value, !value.isEmpty {
                        text(value, x: column.colonX + 8, baseline: lineBaseline, font: font)
                    }
                }
                lowest = max(lowest, lineBaseline)
            }
        }
        cursor = lowest
    }

    /// Set while laying out: the receipt lines went onto a page of their own.
    private(set) var receiptOnNewPage = false

    /// "Received By : ____  Date : ____" — bold labels, the colon at
    /// 81.65pt, a line to write on 6.3pt under the baseline, rows 34.5pt
    /// apart. Moved to a new page if they don't fit, under "Ref.: <number>".
    private func drawReceipt(_ doc: LetterDocument) {
        guard !doc.receiptRows.isEmpty else { return }
        let pitch: CGFloat = 34.5
        var baseline = cursor + 33.0
        if baseline + CGFloat(doc.receiptRows.count - 1) * pitch + 8 > contentBottom {
            newPage()
            receiptOnNewPage = true
            text("Ref.: \(doc.number)", x: textLeft, baseline: continuationBaseline, font: body(11))
            baseline = continuationBaseline + 32.9
        }
        let font = body(11, bold: true)
        for (i, row) in doc.receiptRows.enumerated() {
            let b = baseline + CGFloat(i) * pitch
            for (label, x, ruleEnd) in [(row.0, CGFloat(0), CGFloat(255.5)), (row.1, CGFloat(255.0), textRight + 1 - textLeft)] {
                text(label, x: textLeft + x + 9.65, baseline: b, font: font)
                text(":", x: textLeft + x + 81.65, baseline: b, font: font)
                fill(textLeft + x + 87.5, b + 6.3, ruleEnd - (x + 87.5), rule, .black)
            }
            cursor = b + 6.3
        }
    }

    private func drawClosingLine(_ line: String) {
        let baseline = cursor + 69.0
        // "Remainder of this page is intentionally left blank": not worth a
        // page of its own when the page is already full.
        guard baseline <= contentBottom else { return }
        text(line, x: pageWidth / 2, baseline: baseline, font: times(10.5, italic: true), align: .center)
        cursor = baseline
    }

    // MARK: entry point

    func generate(_ doc: LetterDocument) -> Data {
        // Trial layouts (discarded) find which kept-together sections won't
        // fit where they fall; those start a new page.
        sectionsOnNewPage = keptTogetherBreaks(doc)
        return layOut(doc)
    }

    /// The document for a Word copy (js/docx-export.js): table cells wrapped
    /// as here, row heights, where hanging text starts, and which sections
    /// start a new page — so Word lays it out like the PDF.
    func wordLayout(_ doc: LetterDocument) -> WordLayout {
        configure(for: doc)
        var receiptNewPage = false
        if !doc.receiptRows.isEmpty, let trial = PDFGenerator(paperSize: paperSize) {
            _ = trial.layOut(doc)
            receiptNewPage = trial.receiptOnNewPage
        }
        let breaks = keptTogetherBreaks(doc)
        let font = body(11)
        let currencyWidth = lineWidth(makeLine(doc.currencySymbol, font, .black))
        func lines(_ cells: [String]) -> [[String]] {
            cells.enumerated().filter { $0.offset < doc.columns.count }.map {
                cellLines($0.element, column: doc.columns[$0.offset], font: font, currencyWidth: currencyWidth)
            }
        }
        let rows: [WordRow] = doc.rows.map { row in
            let h = Double(height(of: row, in: doc))
            switch row {
            case .item(let cells): return WordRow(type: "item", height: h, cells: lines(cells))
            case .section(let title): return WordRow(type: "section", height: h, text: title)
            case .summary(let label, let value, let emphasized):
                return WordRow(type: "summary", height: h, label: label, value: value, emphasized: emphasized)
            case .partial(let cells, let tail): return WordRow(type: "partial", height: h, cells: lines(cells), text: tail)
            case .note(let note): return WordRow(type: "note", height: h, text: note)
            }
        }
        let sections: [WordSection] = doc.sections.enumerated().map { sectionIndex, section in
            let paragraphs: [WordParagraph] = section.paragraphs.map { p in
                switch p {
                case .text(let string, let link):
                    return WordParagraph(type: "text", text: string, link: link)
                case .term(let label, let lines):
                    return WordParagraph(type: "hanging", marker: label ?? "", lines: lines, left: 0, textX: Double(labelTextIndent), colon: true)
                case .hanging(let marker, let lines, let left, let indent, let colon):
                    return WordParagraph(type: "hanging", marker: marker, lines: lines, left: Double(left),
                                         textX: Double(hangingTextX(marker: marker, left: left, indent: indent, colon: colon)), colon: colon)
                }
            }
            return WordSection(heading: section.heading, paragraphs: paragraphs,
                               pageBreakBefore: section.alwaysNewPage || breaks.contains(sectionIndex))
        }
        return WordLayout(
            paperSize: paperSize, pageWidth: Double(pageWidth), pageHeight: Double(pageHeight),
            textLeft: Double(textLeft), textRight: Double(textRight), contentBottom: Double(contentBottom),
            number: doc.number, status: doc.status, title: doc.title,
            clientName: clientBlockLines(doc).filter { $0.bold }.map { $0.text }.joined(separator: "\n"),
            clientLines: clientBlockLines(doc).filter { !$0.bold }.map { $0.text },
            refRows: doc.refRows.map { WordRefRow(label: $0.label, value: $0.value, wraps: wrap($0.value, font, 66).count > 1) },
            deliveryMethod: nonBlank(doc.deliveryMethod), salutation: nonBlank(doc.salutation), subject: nonBlank(doc.subject),
            intro: nonBlank(doc.intro), currencySymbol: doc.currencySymbol,
            columns: doc.columns.map { WordColumn(title: $0.title, width: Double($0.width), kind: "\($0.kind)") },
            rows: rows, sections: sections,
            signatures: doc.signatures.map { WordSignature(heading: $0.heading, lines: $0.lines.map { WordSignatureLine(text: $0.text, colon: $0.colon, value: $0.value) }) },
            closingLine: nonBlank(doc.closingLine),
            infoRows: doc.infoRows.map { WordInfoRow(label: $0.label, lines: infoValueLines($0), bold: $0.boldValue) },
            headerHeight: Double(headerHeight),
            receiptRows: doc.receiptRows.map { [$0.0, $0.1] },
            receiptNewPage: receiptNewPage
        )
    }

    private func layOut(_ doc: LetterDocument) -> Data {
        configure(for: doc)
        receiptOnNewPage = false
        sectionsThatSplit = []
        pageNumber = 0
        beginPage()
        drawOpening(doc)
        drawTable(doc)
        drawSections(doc.sections)
        drawSignatures(doc.signatures, afterTable: doc.sections.isEmpty)
        drawReceipt(doc)
        if let closing = doc.closingLine { drawClosingLine(closing) }
        endPage()
        context.closePDF()
        return mutableData as Data
    }
}

// =====================================================================
// MARK: - Stock list
//
// Every change to the stock is a movement: + into the yard, − out of it.
//   Opening / Purchase   received into the yard (+)
//   Delivery             out to a project on hire (−), from an issued delivery note
//   Sale                 out to a project for good (−), from a delivery note of a sale
//   Return               back from a project (+)
//   WriteOff             lost, scrapped or damaged (−)
//   Adjustment           a stock count's difference (±)
// In the yard = the sum of all movements. On hire, per project = delivered
// − returned. Owned = in the yard + on hire.
// =====================================================================

struct StockMovement: Codable {
    var id: String
    /// yyyy-MM-dd
    var date: String
    var kind: String
    /// The price-list item's id, or "code:…" / "name:…" for other items.
    var itemKey: String
    var priceListItemId: String?
    var itemCode: String
    var itemDescription: String
    var unit: String
    var quantity: Double
    var projectId: String?
    var deliveryNoteId: String?
    var reference: String?
    var notes: String?
    var createdAt: String
}

struct ProjectRef: Codable {
    var id: String
    var projectNumber: String
    var name: String
    /// Where its materials are (Stock › By Site), and the company it's for.
    var siteId: String? = nil
    var siteName: String? = nil
    var siteAddress: String? = nil
    var clientName: String? = nil
}

struct StockProjectQuantity: Codable {
    var projectId: String
    var projectNumber: String
    var projectName: String
    var quantity: Double
}

struct StockItemRow: Codable {
    var key: String
    var priceListItemId: String?
    var sourceKey: String?
    var category: String?
    var itemCode: String
    var itemName: String
    var unit: String
    var weightKg: Double?
    var inYard: Double
    var onHire: Double
    var owned: Double
    var onHireByProject: [StockProjectQuantity]
}

struct StockMovementView: Codable {
    var movement: StockMovement
    var projectNumber: String?
    /// Delivery / Sale movements come from delivery notes and can't be deleted here.
    var automatic: Bool
}

struct StockData: Codable {
    var items: [StockItemRow]
    var movements: [StockMovementView]
    var projects: [ProjectRef]
}

// =====================================================================
// MARK: - Accounts
//
// Receivables from invoices (with dated payments), expenses entered by
// hand, and the figures the Accounts page adds up from them.
// =====================================================================

struct InvoicePayment: Codable {
    var id: String
    var invoiceId: String
    /// yyyy-MM-dd
    var date: String
    var amount: Double
    var method: String?
    var reference: String?
    var createdAt: String
}

struct Expense: Codable {
    var id: String
    /// yyyy-MM-dd
    var date: String
    var category: String
    var supplier: String?
    var description: String
    var amount: Double
    var projectId: String?
    var reference: String?
    var createdAt: String
}

let expenseCategories = ["Materials purchase", "Transport", "Labour / subcontract", "Salaries & MPF", "Equipment & repairs",
                         "Rent & storage", "Office & admin", "Insurance & licences", "Other"]

/// Money the company owes: a loan, a supplier's bill, hire purchase, a
/// credit card, tax… Paid off by the payments recorded against it.
struct Liability: Codable {
    var id: String
    var name: String
    /// One of `liabilityKinds`.
    var kind: String
    /// Who it's owed to.
    var creditor: String?
    var amount: Double
    /// yyyy-MM-dd: when it was taken on.
    var startDate: String
    /// yyyy-MM-dd: when it must be paid off (or the next payment is due).
    var dueDate: String?
    var monthlyPayment: Double?
    var interestRatePercent: Double?
    var reference: String?
    var notes: String?
    var createdAt: String
    var updatedAt: String
}

struct LiabilityPayment: Codable {
    var id: String
    var liabilityId: String
    /// yyyy-MM-dd
    var date: String
    var amount: Double
    var note: String?
    var createdAt: String
}

let liabilityKinds = ["Loan", "Supplier bill", "Hire purchase / lease", "Credit card", "Tax", "MPF / wages payable", "Deposit held", "Other"]

/// A liability with what's been paid and what's left.
struct AccountsLiability: Codable {
    var liability: Liability
    var payments: [LiabilityPayment]
    var paid: Double
    var balance: Double
    /// Past its due date with money still owing.
    var isOverdue: Bool
}

/// Someone on the payroll, full-time or part-time: their pay and MPF.
struct Employee: Codable {
    var id: String
    /// "E001", "E002", ... never reused.
    var employeeNumber: String
    var name: String
    var chineseName: String?
    var position: String?
    var phone: String?
    /// The worker record (Admin › Workers) for the same person, if any.
    var workerId: String?
    /// "Full-time" or "Part-time".
    var employmentType: String
    /// "Monthly", "Daily" or "Hourly".
    var payBasis: String
    /// The monthly salary, or the daily / hourly rate.
    var payRate: Double
    /// Days (daily) or hours (hourly) usually worked in a month, for
    /// working out a month's pay.
    var usualUnitsPerMonth: Double?
    /// Fixed monthly allowances (travel, meals, phone…).
    var monthlyAllowance: Double?
    /// The employer's MPF contribution is paid (5%, up to HK$1,500 a month).
    var mpfEnabled: Bool
    var annualLeaveDays: Double?
    var bankAccount: String?
    /// yyyy-MM-dd
    var startDate: String?
    var endDate: String?
    var notes: String?
    /// Left the company: kept for the records, off the payroll.
    var isArchived: Bool
    var createdAt: String
    var updatedAt: String
}

struct EmployeeActionResult: Codable {
    var ok: Bool
    var error: String?
    var id: String?
}

struct PayrollResult: Codable {
    var ok: Bool
    var error: String?
    var recorded: Int
    /// Employees whose pay for that month was already in Expenses.
    var skipped: [String]
}

struct AccountsInvoice: Codable {
    var id: String
    var invoiceNumber: String
    var projectId: String
    var projectNumber: String
    var projectName: String
    var clientName: String?
    var status: String
    /// yyyy-MM-dd
    var invoiceDate: String
    var dueDate: String?
    var total: Double
    var amountPaid: Double
    var balanceDue: Double
}

struct AccountsPayment: Codable {
    var id: String
    var invoiceId: String
    var invoiceNumber: String
    var projectId: String
    var date: String
    var amount: Double
    var method: String?
    var reference: String?
    /// Paid before payments were dated (no date on record).
    var undated: Bool
}

struct AccountsData: Codable {
    var currency: String
    var invoices: [AccountsInvoice]
    var payments: [AccountsPayment]
    var expenses: [Expense]
    var projects: [ProjectRef]
    var categories: [String]
    var liabilities: [AccountsLiability] = []
    var liabilityKinds: [String] = []
}

/// "2026-09-28" from a date field or an ISO timestamp; nil if it isn't one.
func validDay(_ value: String?) -> String? {
    guard let v = value?.trimmingCharacters(in: .whitespaces), v.count >= 10 else { return nil }
    let day = String(v.prefix(10))
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f.date(from: day) == nil ? nil : day
}

extension AppDatabase {
    // ---- Stock ----

    static func stockKey(priceListItemId: String?, itemCode: String, description: String) -> String {
        if let id = priceListItemId, !id.isEmpty { return id }
        let code = itemCode.trimmingCharacters(in: .whitespaces).lowercased()
        return code.isEmpty ? "name:" + description.trimmingCharacters(in: .whitespaces).lowercased() : "code:" + code
    }

    func projectRefs() -> [ProjectRef] {
        let siteById = Dictionary(sitesStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let clientById = Dictionary(clientsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        return projectsStore.readAll().map { p -> ProjectRef in
            var ref = ProjectRef(id: p.id, projectNumber: p.projectNumber, name: p.name)
            if let site = siteById[p.siteId] {
                ref.siteId = site.id
                ref.siteName = site.name
                ref.siteAddress = [site.address, site.city].compactMap { nonBlank($0) }.joined(separator: ", ")
            }
            ref.clientName = clientById[p.clientId]?.companyName
            return ref
        }
            .sorted { $0.projectNumber > $1.projectNumber }
    }

    func stockData() -> StockData {
        let movements = stockMovementsStore.readAll()
        let projects = projectRefs()
        let projectById = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var rows: [String: StockItemRow] = [:]
        var order: [String] = []
        for item in priceListItemsStore.readAll() where !item.isArchived {
            rows[item.id] = StockItemRow(key: item.id, priceListItemId: item.id, sourceKey: item.sourceKey, category: item.category,
                                         itemCode: item.itemCode, itemName: item.itemName, unit: item.unit, weightKg: item.weightKg,
                                         inYard: 0, onHire: 0, owned: 0, onHireByProject: [])
            order.append(item.id)
        }
        var hire: [String: [String: Double]] = [:]
        for m in movements {
            if rows[m.itemKey] == nil {
                rows[m.itemKey] = StockItemRow(key: m.itemKey, priceListItemId: m.priceListItemId, sourceKey: nil, category: nil,
                                               itemCode: m.itemCode, itemName: m.itemDescription, unit: m.unit, weightKg: nil,
                                               inYard: 0, onHire: 0, owned: 0, onHireByProject: [])
                order.append(m.itemKey)
            }
            rows[m.itemKey]!.inYard += m.quantity
            if (m.kind == "Delivery" || m.kind == "Return"), let p = m.projectId {
                hire[m.itemKey, default: [:]][p, default: 0] -= m.quantity
            }
        }
        for (key, byProject) in hire {
            let list = byProject.filter { abs($0.value) > 0.0001 }.map { entry -> StockProjectQuantity in
                let p = projectById[entry.key]
                return StockProjectQuantity(projectId: entry.key, projectNumber: p?.projectNumber ?? "?", projectName: p?.name ?? "", quantity: entry.value)
            }.sorted { $0.projectNumber < $1.projectNumber }
            rows[key]!.onHireByProject = list
            rows[key]!.onHire = list.reduce(0) { $0 + $1.quantity }
        }
        for key in order { rows[key]!.owned = rows[key]!.inYard + rows[key]!.onHire }
        let views = movements.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }.map {
            StockMovementView(movement: $0, projectNumber: $0.projectId.flatMap { projectById[$0]?.projectNumber },
                              automatic: $0.deliveryNoteId != nil)
        }
        return StockData(items: order.compactMap { rows[$0] }, movements: views, projects: projects)
    }

    /// A movement entered on the Stock page: "Purchase" (received),
    /// "Return" (from a project), "WriteOff", or "Count" (the counted
    /// quantity in the yard, recorded as an adjustment).
    func addStockMovement(_ payload: [String: Any]) -> String? {
        let kind = (payload["kind"] as? String) ?? ""
        guard ["Opening", "Purchase", "Return", "WriteOff", "Count"].contains(kind) else { return "Choose what kind of stock change this is." }
        let plId = nonBlank(payload["priceListItemId"] as? String)
        var code = ((payload["itemCode"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        var name = ((payload["itemDescription"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        var unit = ((payload["unit"] as? String) ?? "pc").trimmingCharacters(in: .whitespaces)
        if let plId = plId, let pl = priceListItem(id: plId) {
            code = pl.itemCode; name = pl.itemName; unit = pl.unit
        }
        guard !name.isEmpty else { return "Choose the item." }
        let key = AppDatabase.stockKey(priceListItemId: plId, itemCode: code, description: name)
        let value = ((payload["quantity"] as? Double) ?? 0).rounded()
        var quantity: Double
        switch kind {
        case "Count":
            guard value >= 0 else { return "Enter the quantity counted in the yard." }
            let inYard = stockMovementsStore.readAll().filter { $0.itemKey == key }.reduce(0) { $0 + $1.quantity }
            quantity = value - inYard
            guard abs(quantity) > 0.0001 else { return "The count matches the stock already — nothing to change." }
        case "WriteOff":
            guard value > 0 else { return "Enter a quantity greater than zero." }
            quantity = -value
        default:
            guard value > 0 else { return "Enter a quantity greater than zero." }
            quantity = value
        }
        let projectId = nonBlank(payload["projectId"] as? String)
        if kind == "Return" {
            guard let p = projectId, projectsStore.readAll().contains(where: { $0.id == p }) else { return "Choose the project the items came back from." }
        }
        stockMovementsStore.insert(StockMovement(
            id: makeId("stock"), date: validDay(payload["date"] as? String) ?? todayYMD(), kind: kind == "Count" ? "Adjustment" : kind,
            itemKey: key, priceListItemId: plId, itemCode: code, itemDescription: name, unit: unit.isEmpty ? "pc" : unit,
            quantity: quantity, projectId: kind == "Return" ? projectId : nil, deliveryNoteId: nil,
            reference: nonBlank(payload["reference"] as? String), notes: nonBlank(payload["notes"] as? String), createdAt: nowISO()))
        return nil
    }

    func deleteStockMovement(id: String) -> String? {
        var all = stockMovementsStore.readAll()
        guard let m = all.first(where: { $0.id == id }) else { return "Stock entry not found." }
        guard m.deliveryNoteId == nil else { return "This comes from a delivery note. Cancel or reopen the delivery note instead." }
        all.removeAll { $0.id == id }
        stockMovementsStore.writeAll(all)
        return nil
    }

    /// Whether a delivery note is for a sale (its quotation or invoice is).
    func deliveryNoteIsSale(_ note: DeliveryNote) -> Bool {
        note.sourceQuotationId.flatMap { getQuotation(id: $0)?.pricingMode } == "Sale"
            || note.sourceInvoiceId.flatMap { getInvoice(id: $0)?.pricingMode } == "Sale"
    }

    /// A delivery-note line's weight per unit, from the material list: by
    /// the item it was picked from, else the same code in the same list,
    /// else the same name.
    func deliveryNoteWeight(_ line: DeliveryNoteLineItem, in items: [PriceListItem]) -> Double? {
        if let id = line.priceListItemId, let item = items.first(where: { $0.id == id }), let kg = item.weightKg { return kg }
        let code = line.itemCode.trimmingCharacters(in: .whitespaces)
        if !code.isEmpty, let item = items.first(where: { $0.itemCode == code && (line.sourceKey == nil || $0.sourceKey == line.sourceKey) && $0.weightKg != nil }) {
            return item.weightKg
        }
        let name = line.itemDescription.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return items.first(where: { $0.itemName.trimmingCharacters(in: .whitespaces).lowercased() == name && $0.weightKg != nil })?.weightKg
    }

    func allPriceListItems() -> [PriceListItem] { priceListItemsStore.readAll() }

    /// Books an issued delivery note's items out of the yard: on hire to
    /// its project, or sold if it's for a sale.
    func recordDeliveryStock(_ note: DeliveryNote) {
        removeDeliveryStock(deliveryNoteId: note.id)
        let sale = deliveryNoteIsSale(note)
        let lines = deliveryNoteLineItemsStore.readAll().filter { $0.deliveryNoteId == note.id && $0.quantity > 0 }
        let movements = lines.map { line in
            StockMovement(id: makeId("stock"), date: validDay(note.deliveryDate) ?? todayYMD(), kind: sale ? "Sale" : "Delivery",
                          itemKey: AppDatabase.stockKey(priceListItemId: line.priceListItemId, itemCode: line.itemCode, description: line.itemDescription),
                          priceListItemId: line.priceListItemId, itemCode: line.itemCode, itemDescription: line.itemDescription, unit: line.unit,
                          quantity: -line.quantity.rounded(), projectId: note.projectId, deliveryNoteId: note.id,
                          reference: note.deliveryNoteNumber, notes: nil, createdAt: nowISO())
        }
        stockMovementsStore.insertMany(movements)
    }

    func removeDeliveryStock(deliveryNoteId: String) {
        var all = stockMovementsStore.readAll()
        let before = all.count
        all.removeAll { $0.deliveryNoteId == deliveryNoteId }
        if all.count != before { stockMovementsStore.writeAll(all) }
    }

    // ---- Accounts ----

    func accountsData() -> AccountsData {
        let today = todayYMD()
        let projects = projectRefs()
        let projectById = Dictionary(projectsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let clients = Dictionary(clientsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let allPayments = invoicePaymentsStore.readAll()
        var invoices: [AccountsInvoice] = []
        var payments: [AccountsPayment] = []
        for inv in invoicesStore.readAll() where inv.status != "Draft" && inv.status != "Cancelled" {
            let totals = invoiceTotals(inv, lineItems: invoiceLineItems(for: inv.id))
            let project = projectById[inv.projectId]
            let status = isInvoiceOverdue(inv, balanceDue: totals.balanceDue, today: today) ? "Overdue" : inv.status
            invoices.append(AccountsInvoice(
                id: inv.id, invoiceNumber: inv.invoiceNumber, projectId: inv.projectId,
                projectNumber: project?.projectNumber ?? "", projectName: project?.name ?? "",
                clientName: project.flatMap { clients[$0.clientId]?.companyName },
                status: status, invoiceDate: validDay(inv.invoiceDate) ?? String(inv.invoiceDate.prefix(10)), dueDate: validDay(inv.dueDate),
                total: totals.total, amountPaid: inv.amountPaid, balanceDue: totals.balanceDue))
            let dated = allPayments.filter { $0.invoiceId == inv.id }
            for p in dated {
                payments.append(AccountsPayment(id: p.id, invoiceId: inv.id, invoiceNumber: inv.invoiceNumber, projectId: inv.projectId,
                                                date: p.date, amount: p.amount, method: p.method, reference: p.reference, undated: false))
            }
            // Paid before payments were dated: one undated entry for the rest.
            let earlier = decimalOf(inv.amountPaid) - dated.reduce(Decimal(0)) { $0 + decimalOf($1.amount) }
            if earlier > 0.004 {
                payments.append(AccountsPayment(id: "earlier-\(inv.id)", invoiceId: inv.id, invoiceNumber: inv.invoiceNumber, projectId: inv.projectId,
                                                date: validDay(inv.updatedAt) ?? today, amount: doubleOf(roundToCents(earlier)),
                                                method: nil, reference: "Recorded before payments were dated", undated: true))
            }
        }
        return AccountsData(currency: getCompanySettings().currency,
                            invoices: invoices.sorted { $0.invoiceDate > $1.invoiceDate },
                            payments: payments.sorted { $0.date > $1.date },
                            expenses: expensesStore.readAll().sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) },
                            projects: projects, categories: expenseCategories,
                            liabilities: accountsLiabilities(today: today), liabilityKinds: liabilityKinds)
    }

    /// Adds an expense, or changes one when `id` is given.
    func saveExpense(_ payload: [String: Any]) -> String? {
        guard let date = validDay(payload["date"] as? String) else { return "Enter the date." }
        let description = ((payload["description"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return "Enter what the expense was for." }
        let amount = (payload["amount"] as? Double) ?? 0
        guard amount > 0 else { return "Enter an amount greater than zero." }
        let category = nonBlank(payload["category"] as? String) ?? "Other"
        let projectId = nonBlank(payload["projectId"] as? String)
        var all = expensesStore.readAll()
        if let id = nonBlank(payload["id"] as? String) {
            guard let i = all.firstIndex(where: { $0.id == id }) else { return "Expense not found." }
            all[i].date = date; all[i].category = category; all[i].supplier = nonBlank(payload["supplier"] as? String)
            all[i].description = description; all[i].amount = doubleOf(roundToCents(decimalOf(amount)))
            all[i].projectId = projectId; all[i].reference = nonBlank(payload["reference"] as? String)
            expensesStore.writeAll(all)
        } else {
            expensesStore.insert(Expense(id: makeId("expense"), date: date, category: category, supplier: nonBlank(payload["supplier"] as? String),
                                         description: description, amount: doubleOf(roundToCents(decimalOf(amount))), projectId: projectId,
                                         reference: nonBlank(payload["reference"] as? String), createdAt: nowISO()))
        }
        return nil
    }

    func deleteExpense(id: String) -> String? {
        var all = expensesStore.readAll()
        guard all.contains(where: { $0.id == id }) else { return "Expense not found." }
        all.removeAll { $0.id == id }
        expensesStore.writeAll(all)
        return nil
    }

    // ---- Liabilities ----

    func accountsLiabilities(today: String) -> [AccountsLiability] {
        let payments = Dictionary(grouping: liabilityPaymentsStore.readAll(), by: { $0.liabilityId })
        return liabilitiesStore.readAll().map { l in
            let list = (payments[l.id] ?? []).sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }
            let paid = roundToCents(list.reduce(Decimal(0)) { $0 + decimalOf($1.amount) })
            let balance = roundToCents(decimalOf(l.amount) - paid)
            let overdue = balance > 0.004 && (validDay(l.dueDate).map { $0 < today } ?? false)
            return AccountsLiability(liability: l, payments: list, paid: doubleOf(paid), balance: doubleOf(balance), isOverdue: overdue)
        }.sorted { a, b in
            // Still owing first, then by due date (none last), then newest.
            let owingA = a.balance > 0.004, owingB = b.balance > 0.004
            if owingA != owingB { return owingA }
            let dueA = validDay(a.liability.dueDate) ?? "9999", dueB = validDay(b.liability.dueDate) ?? "9999"
            if dueA != dueB { return dueA < dueB }
            return a.liability.startDate > b.liability.startDate
        }
    }

    /// Adds a liability, or changes one when `id` is given.
    func saveLiability(_ payload: [String: Any]) -> String? {
        let name = ((payload["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Enter what the liability is (e.g. “Bank loan – truck”)." }
        let amount = (payload["amount"] as? Double) ?? 0
        guard amount > 0 else { return "Enter the amount owed, greater than zero." }
        guard let start = validDay(payload["startDate"] as? String) else { return "Enter the date it was taken on." }
        let dueText = nonBlank(payload["dueDate"] as? String)
        let due = validDay(dueText)
        if dueText != nil && due == nil { return "Enter a valid due date, or leave it empty." }
        let kind = nonBlank(payload["kind"] as? String).flatMap { liabilityKinds.contains($0) ? $0 : nil } ?? "Other"
        let positive: (String) -> Double? = { key in (payload[key] as? Double).flatMap { $0 > 0 ? doubleOf(roundToCents(decimalOf($0))) : nil } }
        let rate = (payload["interestRatePercent"] as? Double).flatMap { $0 > 0 ? $0 : nil }
        var all = liabilitiesStore.readAll()
        if let id = nonBlank(payload["id"] as? String) {
            guard let i = all.firstIndex(where: { $0.id == id }) else { return "Liability not found." }
            all[i].name = name; all[i].kind = kind; all[i].creditor = nonBlank(payload["creditor"] as? String)
            all[i].amount = doubleOf(roundToCents(decimalOf(amount))); all[i].startDate = start; all[i].dueDate = due
            all[i].monthlyPayment = positive("monthlyPayment"); all[i].interestRatePercent = rate
            all[i].reference = nonBlank(payload["reference"] as? String); all[i].notes = nonBlank(payload["notes"] as? String)
            all[i].updatedAt = nowISO()
            liabilitiesStore.writeAll(all)
        } else {
            liabilitiesStore.insert(Liability(
                id: makeId("liability"), name: name, kind: kind, creditor: nonBlank(payload["creditor"] as? String),
                amount: doubleOf(roundToCents(decimalOf(amount))), startDate: start, dueDate: due,
                monthlyPayment: positive("monthlyPayment"), interestRatePercent: rate,
                reference: nonBlank(payload["reference"] as? String), notes: nonBlank(payload["notes"] as? String),
                createdAt: nowISO(), updatedAt: nowISO()))
        }
        return nil
    }

    /// Deletes a liability and the payments recorded against it.
    func deleteLiability(id: String) -> String? {
        var all = liabilitiesStore.readAll()
        guard all.contains(where: { $0.id == id }) else { return "Liability not found." }
        all.removeAll { $0.id == id }
        liabilitiesStore.writeAll(all)
        var payments = liabilityPaymentsStore.readAll()
        let before = payments.count
        payments.removeAll { $0.liabilityId == id }
        if payments.count != before { liabilityPaymentsStore.writeAll(payments) }
        return nil
    }

    func addLiabilityPayment(_ payload: [String: Any]) -> String? {
        let liabilityId = (payload["liabilityId"] as? String) ?? ""
        guard liabilitiesStore.readAll().contains(where: { $0.id == liabilityId }) else { return "Liability not found." }
        guard let date = validDay(payload["date"] as? String) else { return "Enter the payment date." }
        let amount = (payload["amount"] as? Double) ?? 0
        guard amount > 0 else { return "Enter an amount greater than zero." }
        liabilityPaymentsStore.insert(LiabilityPayment(
            id: makeId("lpay"), liabilityId: liabilityId, date: date, amount: doubleOf(roundToCents(decimalOf(amount))),
            note: nonBlank(payload["note"] as? String), createdAt: nowISO()))
        return nil
    }

    func deleteLiabilityPayment(id: String) -> String? {
        var all = liabilityPaymentsStore.readAll()
        guard all.contains(where: { $0.id == id }) else { return "Payment not found." }
        all.removeAll { $0.id == id }
        liabilityPaymentsStore.writeAll(all)
        return nil
    }

    // ---- Employees & payroll ----

    func listEmployees() -> [Employee] {
        employeesStore.readAll().sorted { $0.employeeNumber < $1.employeeNumber }
    }

    /// Adds an employee, or changes one when `id` is given.
    func saveEmployee(_ payload: [String: Any]) -> (id: String?, error: String?) {
        let name = ((payload["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return (nil, "Enter the employee’s name.") }
        let type = (payload["employmentType"] as? String) == "Part-time" ? "Part-time" : "Full-time"
        let basis = ["Monthly", "Daily", "Hourly"].contains((payload["payBasis"] as? String) ?? "") ? (payload["payBasis"] as! String) : "Monthly"
        let rate = (payload["payRate"] as? Double) ?? 0
        guard rate >= 0 else { return (nil, "The pay can’t be negative.") }
        let positive: (String) -> Double? = { key in (payload[key] as? Double).flatMap { $0 > 0 ? $0 : nil } }
        for key in ["startDate", "endDate"] {
            if nonBlank(payload[key] as? String) != nil && validDay(payload[key] as? String) == nil { return (nil, "Enter valid dates, or leave them empty.") }
        }
        let workerId = nonBlank(payload["workerId"] as? String).flatMap { id in workersStore.readAll().contains { $0.id == id } ? id : nil }
        func fill(_ e: inout Employee) {
            e.name = name
            e.chineseName = nonBlank(payload["chineseName"] as? String)
            e.position = nonBlank(payload["position"] as? String)
            e.phone = nonBlank(payload["phone"] as? String)
            e.workerId = workerId
            e.employmentType = type
            e.payBasis = basis
            e.payRate = doubleOf(roundToCents(decimalOf(rate)))
            e.usualUnitsPerMonth = basis == "Monthly" ? nil : positive("usualUnitsPerMonth")
            e.monthlyAllowance = positive("monthlyAllowance").map { doubleOf(roundToCents(decimalOf($0))) }
            e.mpfEnabled = (payload["mpfEnabled"] as? Bool) ?? true
            e.annualLeaveDays = positive("annualLeaveDays")
            e.bankAccount = nonBlank(payload["bankAccount"] as? String)
            e.startDate = validDay(payload["startDate"] as? String)
            e.endDate = validDay(payload["endDate"] as? String)
            e.notes = nonBlank(payload["notes"] as? String)
            if let archived = payload["isArchived"] as? Bool { e.isArchived = archived }
            e.updatedAt = nowISO()
        }
        var all = employeesStore.readAll()
        if let id = nonBlank(payload["id"] as? String) {
            guard let i = all.firstIndex(where: { $0.id == id }) else { return (nil, "Employee not found.") }
            fill(&all[i])
            employeesStore.writeAll(all)
            return (id, nil)
        }
        let next = (all.compactMap { Int($0.employeeNumber.dropFirst()) }.max() ?? 0) + 1
        var e = Employee(id: makeId("employee"), employeeNumber: "E" + String(format: "%03d", next), name: name,
                         chineseName: nil, position: nil, phone: nil, workerId: nil, employmentType: type, payBasis: basis,
                         payRate: 0, usualUnitsPerMonth: nil, monthlyAllowance: nil, mpfEnabled: true, annualLeaveDays: nil,
                         bankAccount: nil, startDate: nil, endDate: nil, notes: nil, isArchived: false,
                         createdAt: nowISO(), updatedAt: nowISO())
        fill(&e)
        employeesStore.insert(e)
        return (e.id, nil)
    }

    func deleteEmployee(id: String) -> String? {
        var all = employeesStore.readAll()
        guard all.contains(where: { $0.id == id }) else { return "Employee not found." }
        all.removeAll { $0.id == id }
        employeesStore.writeAll(all)
        return nil
    }

    /// A month's pay put into Expenses ("Salaries & MPF"): one expense per
    /// employee, for their pay plus the employer's MPF. An employee whose
    /// pay for that month is already there is skipped.
    func recordPayroll(_ payload: [String: Any]) -> PayrollResult {
        guard let month = payload["month"] as? String, month.count == 7, validDay(month + "-01") != nil else {
            return PayrollResult(ok: false, error: "Choose the month.", recorded: 0, skipped: [])
        }
        let lines = (payload["lines"] as? [[String: Any]]) ?? []
        guard !lines.isEmpty else { return PayrollResult(ok: false, error: "Tick at least one employee.", recorded: 0, skipped: []) }
        let employees = Dictionary(employeesStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let date = validDay(payload["date"] as? String) ?? todayYMD()
        let existing = Set(expensesStore.readAll().compactMap { $0.reference })
        let monthName: String = {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_GB")
            f.dateFormat = "MMMM yyyy"
            let p = DateFormatter()
            p.locale = Locale(identifier: "en_US_POSIX")
            p.dateFormat = "yyyy-MM-dd"
            return p.date(from: month + "-01").map { f.string(from: $0) } ?? month
        }()
        var new: [Expense] = []
        var skipped: [String] = []
        for line in lines {
            guard let e = employees[(line["employeeId"] as? String) ?? ""] else { continue }
            let reference = "PAY \(month) \(e.employeeNumber)"
            if existing.contains(reference) { skipped.append(e.name); continue }
            let pay = roundToCents(decimalOf((line["pay"] as? Double) ?? 0))
            let mpf = roundToCents(decimalOf((line["mpf"] as? Double) ?? 0))
            guard pay + mpf > 0 else { continue }
            var description = "Salary \(monthName) — \(e.name) (\(e.employeeNumber), \(e.employmentType.lowercased()))"
            if mpf > 0 { description += ": pay \(formatMoney(doubleOf(pay))) + employer MPF \(formatMoney(doubleOf(mpf)))" }
            new.append(Expense(id: makeId("expense"), date: date, category: "Salaries & MPF", supplier: e.name,
                               description: description, amount: doubleOf(pay + mpf), projectId: nil,
                               reference: reference, createdAt: nowISO()))
        }
        if !new.isEmpty { expensesStore.insertMany(new) }
        return PayrollResult(ok: true, error: nil, recorded: new.count, skipped: skipped)
    }
}

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
                       terms: String? = nil,
                       signature: (company: String, name: String, title: String, client: String)? = nil) -> SheetLayout {
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
        let infoRows = [("Project Code  :", info.projectCode, "Job Site          :", info.jobSite),
                        ("Client             :", info.client, "Structure        :", info.structure)]
        for r in infoRows {
            rows.append(SheetRow(kind: "info", height: 15.75, fill: cream, cells: [
                cell(infoEdges[0], infoEdges[1], r.0, 10, "left", 4.125), cell(infoEdges[1], infoEdges[2], r.1, 10, "left", 4.125),
                cell(infoEdges[2], infoEdges[3], r.2, 10, "left", 4.125), cell(infoEdges[3], infoEdges[4], r.3, 10, "left", 4.125),
            ], repeats: true))
        }
        let rateWord = pricingMode == "Sale" ? "Sale Price" : "Rental Rate"
        let titles = landscape
            ? ["No.", "Item Name", "Weight", "Quantity", "Unit \(rateWord) (\(currencyCode))", "Total \(rateWord) (\(currencyCode))", "Total Weight"]
            : ["No.", "Item Name", "Weight", "Quantity", "Total Weight"]
        rows.append(SheetRow(kind: "header", height: 19.5, fill: blue,
                             cells: titles.enumerated().map { cell(edges[$0.offset], edges[$0.offset + 1], $0.element, 13, "center", 4.875) },
                             repeats: true))
        let kg: (Double) -> String = { String(format: "%.1f kg", $0) }
        for (i, line) in lines.enumerated() {
            let qty = line.quantity.rounded()
            let name = line.itemDescription.replacingOccurrences(of: "\n", with: " ")
            let weight = line.weightKg.map(kg) ?? ""
            let totalWeight = line.weightKg.map { kg($0 * qty) } ?? ""
            var texts: [(String, String)] = [(String(i + 1), "center"), (name, "left"), (weight, "right"), (formatQuantity(qty), "center")]
            if landscape {
                texts.append((formatMoney(line.appliedUnitPrice), "money"))
                texts.append((formatMoney(doubleOf(lineAmount(quantity: line.quantity, unitPrice: line.appliedUnitPrice))), "money"))
            }
            texts.append((totalWeight, "right"))
            rows.append(SheetRow(kind: "item", height: 18, fill: nil,
                                 cells: texts.enumerated().map { cell(edges[$0.offset], edges[$0.offset + 1], $0.element.0, 12, $0.element.1, 4.875) },
                                 repeats: false))
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
            totals.append(cell(edges[0], edges[n - 1], "Total Weight :", 28.99, "center", 8.625))
        }
        totals.append(cell(edges[n - 1], edges[n], kg(totalWeightKg), 12, "right", 15.375))
        rows.append(SheetRow(kind: "total", height: 38.25, fill: nil, cells: totals, repeats: false))

        // Amounts added after the subtotal (as on the company's sheet for
        // Mr. Law's container access platform): D1 Delivery, D2 Design
        // Fees…, "N/a" for their weight, then "Total Amount".
        if !shownCharges.isEmpty {
            var total = decimalOf(grandTotal)
            for (i, charge) in shownCharges.enumerated() {
                total += decimalOf(charge.amount)
                rows.append(SheetRow(kind: "charge", height: 18.75, fill: nil, cells: [
                    cell(edges[0], edges[1], nonBlank(charge.code) ?? "D\(i + 1)", 12, "left", 5.625),
                    cell(edges[1], edges[n - 2], charge.name, 12, "left", 5.625),
                    cell(edges[n - 2], edges[n - 1], formatMoney(charge.amount), 12, "money", 5.625),
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
        if landscape, let text = nonBlank(terms) { textBox(text, heading: "Terms & Conditions", kind: "terms") }

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
                                     left: left, right: right, top: top, bottomLimit: pageHeight - 53.25, rows: rows))
    }

    /// As Google Sheets' "Fit to page": a sheet a little too long for one
    /// page is shrunk onto it (to no less than 70%), from the same top
    /// margin and about the same centre line, e.g. Mr. Law's sheet at
    /// 76.75%. Longer sheets run on over pages at full size.
    static func fitToPage(_ sheet: SheetLayout) -> SheetLayout {
        let height = sheet.rows.reduce(0) { $0 + $1.height }
        let room = sheet.bottomLimit - sheet.top
        guard height > room, room / height >= 0.7 else { return sheet }
        // 3pt to spare, so Word's rounding never tips the last rows over.
        let k = (room - 3) / height
        let centre = (sheet.left + sheet.right) / 2
        let x: (Double) -> Double = { centre + ($0 - centre) * k }
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
    private let layout: SheetLayout
    private let data = NSMutableData()
    private var context: CGContext!
    private var rule: Double { 0.75 * layout.scale }

    private init(_ layout: SheetLayout) { self.layout = layout }

    static func pdf(_ layout: SheetLayout) -> Data? {
        let renderer = BQSheetRenderer(layout)
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
    private func font(_ cell: SheetCell) -> NSFont {
        let names = cell.font == "title" ? ["Arial-BoldMT", "Arial Bold", "Helvetica-Bold"] : ["Calibri", "Carlito-Regular", "Carlito", "Helvetica"]
        for name in names { if let f = NSFont(name: name, size: CGFloat(cell.size)) { return f } }
        return NSFont.systemFont(ofSize: CGFloat(cell.size))
    }

    private func pages() -> [[SheetRow]] {
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

    private func draw() {
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
                y += row.height
            }
            context.endPDFPage()
        }
    }

    private func hLine(_ y: Double) {
        context.fill(CGRect(x: layout.left - rule / 2, y: layout.pageHeight - (y + rule / 2), width: layout.right - layout.left + rule, height: rule))
    }

    private func color(_ hex: String) -> CGColor {
        let v = Int(hex, radix: 16) ?? 0
        return CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: 1)
    }

    private func line(_ text: String, _ font: NSFont, link: String? = nil) -> CTLine {
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

    private func width(_ l: CTLine) -> Double { Double(CTLineGetTypographicBounds(l, nil, nil, nil)) }

    private func put(_ l: CTLine, x: Double, baseline: Double) {
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: layout.pageHeight - baseline)
        CTLineDraw(l, context)
        context.restoreGState()
    }

    /// Text is 2.625pt in from the cell's rules; right-aligned figures
    /// keep a space's width before the rule, as the sheet's number formats do.
    private func drawText(_ cell: SheetCell, rowBottom: Double) {
        guard !cell.text.isEmpty else { return }
        var f = font(cell)
        let pad = 2.625 * layout.scale
        let space = width(line(" ", f))
        let room = cell.x1 - cell.x0 - 2 * pad - (cell.align == "right" || cell.align == "money" ? space : 0)
        var l = line(cell.text, f, link: cell.link)
        // Too long for its cell: a slightly smaller size, never wrapped.
        if width(l) > room, room > 0 {
            f = NSFont(descriptor: f.fontDescriptor, size: max(f.pointSize * CGFloat(room / width(l)), f.pointSize * 0.6)) ?? f
            l = line(cell.text, f, link: cell.link)
        }
        let baseline = rowBottom - cell.baselineUp
        var x: Double
        switch cell.align {
        case "center": x = (cell.x0 + cell.x1) / 2 - width(l) / 2
        case "right", "money": x = cell.x1 - pad - space - width(l)
        default: x = cell.x0 + pad
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
    private let wanted: Set<String>
    private(set) var found: [[String: String]] = []
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
    private(set) var strings: [String] = []
    private var current = ""
    private var inSI = false, inT = false, inPhonetic = false
    static func parse(_ data: Data) -> [String] {
        let d = SharedStringsParser()
        let p = XMLParser(data: data)
        p.delegate = d
        p.parse()
        return d.strings
    }
    private func local(_ n: String) -> String { n.split(separator: ":").last.map(String.init) ?? n }
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
    private let shared: [String]
    private var rows: [Int: [Int: String]] = [:]
    private var cellRef = "", cellType = "", value = "", inline = ""
    private var inV = false, inInlineT = false, inCell = false
    private var nextRow = 1
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
    private func local(_ n: String) -> String { n.split(separator: ":").last.map(String.init) ?? n }
    private static func columnIndex(_ ref: String) -> Int {
        var n = 0
        for ch in ref.uppercased() {
            guard let a = ch.asciiValue, a >= 65, a <= 90 else { break }
            n = n * 26 + Int(a - 64)
        }
        return max(0, n - 1)
    }
    private static func rowNumber(_ ref: String) -> Int? { Int(ref.filter { $0.isNumber }) }

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
    private static func unzipEntry(_ file: URL, _ entry: String) -> Data? {
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
            throw BackupError(message: "This file couldn't be opened as an Excel workbook (.xlsx). If it's an older .xls file, open it in Excel or Numbers and save it as .xlsx or .csv first.")
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
        let text = raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
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
        return [SpreadsheetSheet(name: file.deletingPathExtension().lastPathComponent, rows: rows)]
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

// =====================================================================
// MARK: - Backup & Restore (Phase 14 — section 39)
//
// A backup is a plain, self-contained folder kept with the database, in
// ~/Library/Application Support/ScaffoldPro/Backups/ (beside data/) — no
// zip, no proprietary format, so it can be copied to a USB drive or
// opened in Finder:
//
//   ScaffoldPro-Backup_2026-09-27_143012/
//   ├── Database/        every *.json store (clients, projects, BOQs, …)
//   ├── Projects/        every project folder with drawings and PDFs
//   ├── Administration/  worker and company documents
//   └── Configuration/   manifest.json + a short README
//
// Everything is copied into a hidden ".inprogress-…" folder first and
// only renamed to its real name once complete, so an interrupted backup
// never looks like a valid one. Restore always takes a "Before Restore"
// safety backup of the current state before replacing anything.
// =====================================================================

final class BackupManager {
    private let db: AppDatabase
    private let storage: FileStorage
    private let fm = FileManager.default

    init(db: AppDatabase, storage: FileStorage) {
        self.db = db
        self.storage = storage
    }

    private func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f.string(from: Date())
    }

    /// Counts files and total bytes under a folder (for the manifest and
    /// the list shown in Settings).
    private func folderStats(_ url: URL) -> (files: Int, bytes: Int64) {
        guard let enumerator = fm.enumerator(at: url, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey]) else { return (0, 0) }
        var files = 0
        var bytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true else { continue }
            files += 1
            bytes += Int64(values.fileSize ?? 0)
        }
        return (files, bytes)
    }

    func readManifest(_ backupFolder: URL) -> BackupManifest? {
        let url = backupFolder.appendingPathComponent("Configuration/manifest.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(BackupManifest.self, from: data)
    }

    private func summary(_ folder: URL, _ m: BackupManifest) -> BackupSummary {
        BackupSummary(
            name: folder.lastPathComponent, path: folder.path, createdAt: m.createdAt, kind: m.kind,
            projectCount: m.projectCount, fileCount: m.fileCount, totalBytes: m.totalBytes
        )
    }

    func createBackup(kind: String) throws -> BackupSummary {
        try fm.createDirectory(at: storage.backupsRoot, withIntermediateDirectories: true)
        let suffix = kind == "Before Restore" ? "_BeforeRestore" : kind == "Scheduled" ? "_Auto" : ""
        var finalFolder = storage.backupsRoot.appendingPathComponent("ScaffoldPro-Backup_\(timestamp())\(suffix)", isDirectory: true)
        var n = 2
        while fm.fileExists(atPath: finalFolder.path) {
            finalFolder = storage.backupsRoot.appendingPathComponent("ScaffoldPro-Backup_\(timestamp())\(suffix)-\(n)", isDirectory: true)
            n += 1
        }

        let working = storage.backupsRoot.appendingPathComponent(".inprogress-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: working, withIntermediateDirectories: true)

        do {
            try fm.copyItem(at: db.dataDir, to: working.appendingPathComponent("Database", isDirectory: true))

            var projectCount = 0
            if fm.fileExists(atPath: storage.projectsRoot.path) {
                try fm.copyItem(at: storage.projectsRoot, to: working.appendingPathComponent("Projects", isDirectory: true))
                projectCount = ((try? fm.contentsOfDirectory(atPath: storage.projectsRoot.path)) ?? [])
                    .filter { !$0.hasPrefix(".") }.count
            }
            if fm.fileExists(atPath: storage.administrationRoot.path) {
                try fm.copyItem(at: storage.administrationRoot, to: working.appendingPathComponent("Administration", isDirectory: true))
            }

            let stats = folderStats(working)
            let manifest = BackupManifest(
                app: "ScaffoldPro", formatVersion: 1, createdAt: nowISO(), kind: kind,
                sourceAppRoot: storage.appRoot.path, projectCount: projectCount,
                fileCount: stats.files, totalBytes: stats.bytes
            )
            let config = working.appendingPathComponent("Configuration", isDirectory: true)
            try fm.createDirectory(at: config, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: config.appendingPathComponent("manifest.json"), options: .atomic)
            let readme = """
            ScaffoldPro backup — \(formatDateForDisplay(manifest.createdAt))

            This folder is a complete, self-contained copy of your ScaffoldPro data:
              Database/        clients, sites, projects, price lists, BOQs, quotations,
                               invoices, delivery notes, workers, settings
              Projects/        every project folder, with drawings and generated PDFs
              Administration/  worker and company documents

            To restore it: open ScaffoldPro → Settings → Backup & Restore →
            "Restore from Folder…" and choose this folder.
            Please don't rename or rearrange the folders inside it.
            """
            try Data(readme.utf8).write(to: config.appendingPathComponent("README.txt"), options: .atomic)

            try fm.moveItem(at: working, to: finalFolder)
            return summary(finalFolder, manifest)
        } catch {
            try? fm.removeItem(at: working)
            throw BackupError(message: "The backup could not be completed: \(error.localizedDescription)")
        }
    }

    /// Deletes the scheduled backups older than `days` days. Manual and
    /// before-restore backups are kept. Returns how many were deleted.
    @discardableResult
    func deleteOldScheduledBackups(olderThanDays days: Int = 7) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        var deleted = 0
        for b in listBackups() where b.kind == "Scheduled" {
            guard let made = isoFormatter.date(from: b.createdAt) ?? ISO8601DateFormatter().date(from: b.createdAt), made < cutoff else { continue }
            if (try? fm.removeItem(at: URL(fileURLWithPath: b.path, isDirectory: true))) != nil { deleted += 1 }
        }
        return deleted
    }

    func listBackups() -> [BackupSummary] {
        guard let names = try? fm.contentsOfDirectory(atPath: storage.backupsRoot.path) else { return [] }
        return names
            .filter { !$0.hasPrefix(".") }
            .compactMap { name -> BackupSummary? in
                let folder = storage.backupsRoot.appendingPathComponent(name, isDirectory: true)
                guard let m = readManifest(folder) else { return nil }
                return summary(folder, m)
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    /// Replaces the current database, Projects and Administration with the
    /// backup's copies. Returns the safety backup taken first.
    func restore(from backupFolder: URL) throws -> BackupSummary {
        guard let manifest = readManifest(backupFolder), manifest.app == "ScaffoldPro" else {
            throw BackupError(message: "This folder isn't a ScaffoldPro backup. Choose a folder named like \"ScaffoldPro-Backup_…\".")
        }
        guard manifest.formatVersion <= 1 else {
            throw BackupError(message: "This backup was made by a newer version of ScaffoldPro and can't be restored here.")
        }
        let dbSource = backupFolder.appendingPathComponent("Database", isDirectory: true)
        guard fm.fileExists(atPath: dbSource.path) else {
            throw BackupError(message: "This backup is incomplete — its Database folder is missing.")
        }
        // A backup in iCloud Drive may have files that are only in iCloud
        // (shown as ".name.icloud" here); restoring then would miss them.
        if let walker = fm.enumerator(at: backupFolder, includingPropertiesForKeys: nil),
           walker.contains(where: { (($0 as? URL)?.lastPathComponent ?? "").hasSuffix(".icloud") }) {
            throw BackupError(message: "Some files in this backup are still only in iCloud. In Finder, Control-click the backup folder, choose “Download Now”, wait until it has finished, then restore again.")
        }
        let resolved = backupFolder.resolvingSymlinksInPath().path
        for live in [storage.projectsRoot, storage.administrationRoot] {
            if resolved.hasPrefix(live.resolvingSymlinksInPath().path + "/") {
                throw BackupError(message: "Please move the backup folder out of the Projects or Administration folder before restoring it.")
            }
        }

        // 1. Safety net: snapshot the current state first.
        let safety = try createBackup(kind: "Before Restore")

        do {
            // 2. Database: copy into a staging folder, then swap it in.
            let parent = db.dataDir.deletingLastPathComponent()
            let staging = parent.appendingPathComponent("data-restoring", isDirectory: true)
            let old = parent.appendingPathComponent("data-replaced", isDirectory: true)
            try? fm.removeItem(at: staging)
            try? fm.removeItem(at: old)
            try fm.copyItem(at: dbSource, to: staging)
            if fm.fileExists(atPath: db.dataDir.path) { try fm.moveItem(at: db.dataDir, to: old) }
            do {
                try fm.moveItem(at: staging, to: db.dataDir)
            } catch {
                // Put the original database straight back rather than
                // leave the app with none.
                if fm.fileExists(atPath: old.path) { try? fm.moveItem(at: old, to: db.dataDir) }
                throw error
            }
            try? fm.removeItem(at: old)

            // 3. Files: same staging-then-swap for Projects and Administration.
            for name in ["Projects", "Administration"] {
                let source = backupFolder.appendingPathComponent(name, isDirectory: true)
                guard fm.fileExists(atPath: source.path) else { continue }
                let destination = storage.appRoot.appendingPathComponent(name, isDirectory: true)
                let stagingFiles = storage.appRoot.appendingPathComponent(".restoring-\(name)", isDirectory: true)
                try? fm.removeItem(at: stagingFiles)
                try fm.copyItem(at: source, to: stagingFiles)
                if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
                try fm.moveItem(at: stagingFiles, to: destination)
            }
        } catch {
            throw BackupError(message: "The restore stopped part-way: \(error.localizedDescription). Your previous data is safe in the backup \"\(safety.name)\" — restore that to go back.")
        }

        storage.ensureRootFoldersExist()
        db.rebaseFilePaths(from: manifest.sourceAppRoot, to: storage.appRoot.path)
        return safety
    }
}

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

final class CloudBackupManager {
    /// Posted by every database save.
    static let dataSaved = Notification.Name("ScaffoldPro.dataSaved")
    /// Where copies went before they went straight into the folder.
    static let backupFolderName = "ScaffoldPro Backup"
    static let historyDays = 30

    private let db: AppDatabase
    private let storage: FileStorage
    private let queue = DispatchQueue(label: "ScaffoldPro.cloudBackup", qos: .utility)
    private let defaults = UserDefaults.standard
    private var timer: Timer?
    private var pending: DispatchWorkItem?
    /// Set while a restore swaps the data in (main thread).
    var paused = false
    /// A backup is being copied (main thread).
    private(set) var running = false

    private enum Key {
        static let enabled = "cloudBackup.enabled"
        static let folder = "cloudBackup.folder"
        static let lastBackup = "cloudBackup.lastBackupAt"
        static let lastCopied = "cloudBackup.lastFilesCopied"
        static let lastError = "cloudBackup.lastError"
    }

    init(db: AppDatabase, storage: FileStorage) {
        self.db = db
        self.storage = storage
    }

    /// ~/Library/Mobile Documents/com~apple~CloudDocs — "iCloud Drive" in Finder.
    static var iCloudDrive: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    static var defaultFolder: URL {
        iCloudDrive.appendingPathComponent("Proficiency", isDirectory: true).appendingPathComponent("William's Work", isDirectory: true)
    }

    var enabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var usingDefault: Bool { defaults.string(forKey: Key.folder) == nil }

    var folder: URL {
        defaults.string(forKey: Key.folder).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? CloudBackupManager.defaultFolder
    }

    func setFolder(_ url: URL?) {
        if let url = url { defaults.set(url.path, forKey: Key.folder) } else { defaults.removeObject(forKey: Key.folder) }
    }

    func status() -> CloudBackupStatus {
        let drive = CloudBackupManager.iCloudDrive.path
        let path = folder.path
        let display = path.hasPrefix(drive + "/")
            ? (["iCloud Drive"] + path.dropFirst(drive.count + 1).split(separator: "/").map(String.init)).joined(separator: " › ")
            : path
        let last = defaults.object(forKey: Key.lastBackup) as? Double
        return CloudBackupStatus(
            enabled: enabled, folder: path, folderDisplay: display, usingDefault: usingDefault,
            lastBackupAt: last.map { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0)) },
            lastFilesCopied: defaults.object(forKey: Key.lastCopied) as? Int,
            lastError: defaults.string(forKey: Key.lastError), running: running)
    }

    /// Starts the automatic schedule (main thread).
    func start() {
        NotificationCenter.default.addObserver(forName: CloudBackupManager.dataSaved, object: nil, queue: .main) { [weak self] _ in
            self?.schedule(after: 60)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.backUpNow() }
        schedule(after: 20)
    }

    /// Backs up after a quiet spell, so a burst of saves makes one backup.
    func schedule(after seconds: TimeInterval) {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.backUpNow() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    /// Copies what changed (main thread; the copying runs in the background).
    func backUpNow(completion: ((CloudBackupStatus) -> Void)? = nil) {
        guard enabled, !paused, !running else { completion?(status()); return }
        running = true
        let target = folder
        let startedAt = Date()
        let since = (defaults.object(forKey: Key.lastBackup) as? Double).map { Date(timeIntervalSince1970: $0) }
        queue.async { [weak self] in
            guard let self = self else { return }
            let result: Result<Int, BackupError>
            do {
                result = .success(try self.copyChanges(into: target, since: since))
            } catch let e as BackupError {
                result = .failure(e)
            } catch {
                result = .failure(BackupError(message: error.localizedDescription))
            }
            DispatchQueue.main.async {
                self.running = false
                switch result {
                case .success(let copied):
                    self.defaults.set(startedAt.timeIntervalSince1970, forKey: Key.lastBackup)
                    self.defaults.set(copied, forKey: Key.lastCopied)
                    self.defaults.removeObject(forKey: Key.lastError)
                case .failure(let e):
                    self.defaults.set(e.message, forKey: Key.lastError)
                }
                completion?(self.status())
            }
        }
    }

    // MARK: copying (background queue)

    private func copyChanges(into target: URL, since: Date?) throws -> Int {
        let fm = FileManager.default
        if !fm.fileExists(atPath: target.path) {
            let parent = target.deletingLastPathComponent()
            guard fm.fileExists(atPath: parent.path) else {
                throw BackupError(message: "The “\(parent.lastPathComponent)” folder wasn't found in iCloud Drive. Check that iCloud Drive is on and the shared “\(parent.lastPathComponent)” folder has been accepted (it shows in Finder under iCloud Drive), or choose the folder here.")
            }
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
        }
        // The copy goes straight into the chosen folder (William's Work).
        let root = target
        // Backups made before this went into a "ScaffoldPro Backup" folder
        // inside it: move those up once, so nothing is copied twice.
        let older = target.appendingPathComponent(CloudBackupManager.backupFolderName, isDirectory: true)
        if fm.fileExists(atPath: older.path) {
            for name in (try? fm.contentsOfDirectory(atPath: older.path)) ?? [] where !name.hasPrefix(".") {
                let destination = root.appendingPathComponent(name)
                if !fm.fileExists(atPath: destination.path) {
                    try? fm.moveItem(at: older.appendingPathComponent(name), to: destination)
                }
            }
            if ((try? fm.contentsOfDirectory(atPath: older.path)) ?? ["?"]).filter({ !$0.hasPrefix(".") }).isEmpty {
                try? fm.removeItem(at: older)
            }
        }

        var totals = (copied: 0, files: 0, bytes: Int64(0), failed: [String]())
        func mirror(_ source: URL, _ name: String) {
            guard fm.fileExists(atPath: source.path) else { return }
            let r = mirrorFolder(source, to: root.appendingPathComponent(name, isDirectory: true), since: since)
            totals.copied += r.copied
            totals.files += r.files
            totals.bytes += r.bytes
            totals.failed += r.failed
        }
        mirror(db.dataDir, "Database")
        mirror(storage.projectsRoot, "Projects")
        mirror(storage.administrationRoot, "Administration")

        // The manifest makes the copy restorable with "Restore from Folder…".
        let projectCount = ((try? fm.contentsOfDirectory(atPath: storage.projectsRoot.path)) ?? []).filter { !$0.hasPrefix(".") }.count
        let manifest = BackupManifest(app: "ScaffoldPro", formatVersion: 1, createdAt: nowISO(), kind: "iCloud",
                                      sourceAppRoot: storage.appRoot.path, projectCount: projectCount,
                                      fileCount: totals.files, totalBytes: totals.bytes)
        let config = root.appendingPathComponent("Configuration", isDirectory: true)
        try fm.createDirectory(at: config, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: config.appendingPathComponent("manifest.json"), options: .atomic)
        let readme = """
        ScaffoldPro — automatic iCloud backup, kept up to date by the app.

          Database/          clients, projects, price lists, BOQs, quotations,
                             invoices, delivery notes, workers, settings
          Projects/          every project folder, with drawings, PDFs and Word copies
          Administration/    worker and company documents
          Database History/  the database as it was each day (last \(CloudBackupManager.historyDays) days)

        To restore it: ScaffoldPro → Settings → Backup & Restore →
        "Restore from Folder…" and choose this folder ("\(root.lastPathComponent)").
        Files deleted in the app are kept here; nothing is removed from this copy.
        """
        try Data(readme.utf8).write(to: config.appendingPathComponent("README.txt"), options: .atomic)

        // A dated copy of the database once a day; the oldest are removed.
        let history = root.appendingPathComponent("Database History", isDirectory: true)
        try fm.createDirectory(at: history, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let today = history.appendingPathComponent(f.string(from: Date()), isDirectory: true)
        if !fm.fileExists(atPath: today.path) { try? fm.copyItem(at: db.dataDir, to: today) }
        let days = ((try? fm.contentsOfDirectory(atPath: history.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        for old in days.dropLast(CloudBackupManager.historyDays) {
            try? fm.removeItem(at: history.appendingPathComponent(old, isDirectory: true))
        }

        if !totals.failed.isEmpty {
            throw BackupError(message: "\(totals.failed.count) file\(totals.failed.count == 1 ? "" : "s") couldn't be copied to iCloud, e.g. \(totals.failed[0]). The rest are backed up; it will try again.")
        }
        return totals.copied
    }

    /// Copies every file in `source` that's new or changed since `since`
    /// (or differs in size) into `destination`, keeping the folder layout.
    /// Nothing in `destination` is deleted. Files iCloud has moved off this
    /// Mac to save space (".name.icloud") count as there.
    private func mirrorFolder(_ source: URL, to destination: URL, since: Date?) -> (copied: Int, files: Int, bytes: Int64, failed: [String]) {
        let fm = FileManager.default
        var result = (copied: 0, files: 0, bytes: Int64(0), failed: [String]())
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = fm.enumerator(at: source, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return result }
        let base = source.standardizedFileURL.pathComponents.count
        for case let url as URL in walker {
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let relative = url.standardizedFileURL.pathComponents.dropFirst(base)
            guard !relative.isEmpty else { continue }
            result.files += 1
            result.bytes += Int64(values.fileSize ?? 0)
            let out = relative.reduce(destination) { $0.appendingPathComponent($1) }
            let changed = since.map { (values.contentModificationDate ?? .distantFuture) > $0 } ?? true
            let needsCopy: Bool
            if fm.fileExists(atPath: out.path) {
                let size = (try? out.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                needsCopy = changed || size != values.fileSize
            } else if fm.fileExists(atPath: out.deletingLastPathComponent().appendingPathComponent(".\(out.lastPathComponent).icloud").path) {
                needsCopy = changed
            } else {
                needsCopy = true
            }
            guard needsCopy else { continue }
            do {
                try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                let temp = out.deletingLastPathComponent().appendingPathComponent(".\(out.lastPathComponent).scaffoldpro-copy")
                try? fm.removeItem(at: temp)
                try fm.copyItem(at: url, to: temp)
                if fm.fileExists(atPath: out.path) {
                    _ = try fm.replaceItemAt(out, withItemAt: temp)
                } else {
                    try fm.moveItem(at: temp, to: out)
                }
                result.copied += 1
            } catch {
                result.failed.append("\(relative.joined(separator: "/")) (\(error.localizedDescription))")
            }
        }
        return result
    }
}

// =====================================================================
// MARK: - Team sharing (several Macs, one shared folder — no server)
//
// Everyone works on the same data through a folder they all have, e.g. a
// shared iCloud Drive folder. It holds the project files and the database
// as one change log per Mac:
//
//   <shared folder>/
//     ScaffoldPro Team.json              marks the folder as a shared workspace
//     Database/<Mac id>/<store>.json     that Mac's changes — only it writes them
//     Members/<Mac id>.json              who uses it, last seen when
//     Projects/  Administration/         the files, as in Documents/ScaffoldPro
//
// Each Mac only ever writes its own files, so iCloud never has two
// versions of one file to choose between. Every record (a client, a
// quotation, each line of it…) carries the time it last changed; the
// newest change to a record wins, and a deleted record leaves a "deleted"
// marker so it stays deleted everywhere.
//
// This Mac works from a merged copy of the database (Application Support/
// ScaffoldPro/team-data — ordinary store files, so the rest of the app is
// unchanged). A save writes that copy as usual and TeamSync adds what
// changed to this Mac's log. Every two seconds it looks at the other Macs'
// logs; when one has changed it merges it in and the page refreshes.
// File paths inside the shared folder are kept relative to it, since the
// folder sits at a different place on each Mac.
// =====================================================================

struct TeamMember: Codable {
    var id: String
    var name: String
    var computer: String
    var lastSeen: String
    var isThisMac: Bool? = nil
    /// The date of the ScaffoldPro version it runs (install.sh's version.txt).
    var version: String? = nil
    /// Runs an older version than this Mac.
    var outdated: Bool? = nil
}

struct TeamStatus: Codable {
    var enabled: Bool
    var folder: String?
    var folderDisplay: String?
    /// Sharing is on but the folder can't be found (this launch uses this
    /// Mac's own data).
    var folderMissing: Bool
    var memberName: String
    var members: [TeamMember]
    var lastChangeAt: String?
    var lastChangeBy: String?
    var iCloudDrive: String
    /// Another Mac in the folder runs a newer version: this one should be
    /// updated (an older version can drop details the newer one saves).
    var thisMacOutdated = false
}

final class TeamSync {
    /// Set while this Mac works in a shared folder.
    static private(set) var current: TeamSync?
    /// Set while this Mac (not in a shared folder) keeps its material list
    /// in step with the other Macs through iCloud Drive.
    static private(set) var material: TeamSync?

    /// The stores that make up the material list.
    static let materialStores: Set<String> = ["price_lists.json", "price_list_items.json"]

    /// Where the material list is kept in step when this Mac isn't in a
    /// shared folder: "ScaffoldPro Material List" in the company's shared
    /// Proficiency folder (so everyone's Macs see it), or at the top of
    /// iCloud Drive if that folder isn't on this Mac. nil without iCloud Drive.
    static var materialFolder: URL? {
        let fm = FileManager.default
        let drive = CloudBackupManager.iCloudDrive
        guard fm.fileExists(atPath: drive.path) else { return nil }
        let company = drive.appendingPathComponent("Proficiency", isDirectory: true)
        let base = fm.fileExists(atPath: company.path) ? company : drive
        return base.appendingPathComponent("ScaffoldPro Material List", isDirectory: true)
    }

    static let markerName = "ScaffoldPro Team.json"
    static let pathToken = "$SCAFFOLDPRO_TEAM$"
    private static let folderKey = "team.folder"
    private static let deviceKey = "team.deviceId"
    private static let nameKey = "team.memberName"

    // MARK: settings (UserDefaults — per Mac)

    static var configuredFolder: URL? {
        UserDefaults.standard.string(forKey: folderKey).map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func setConfiguredFolder(_ url: URL?) {
        if let url = url { UserDefaults.standard.set(url.path, forKey: folderKey) } else { UserDefaults.standard.removeObject(forKey: folderKey) }
    }

    static var deviceId: String {
        if let id = UserDefaults.standard.string(forKey: deviceKey) { return id }
        let id = "mac-" + UUID().uuidString.lowercased().prefix(13).replacingOccurrences(of: "-", with: "")
        UserDefaults.standard.set(id, forKey: deviceKey)
        return id
    }

    static var memberName: String {
        get {
            let saved = UserDefaults.standard.string(forKey: nameKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? NSFullUserName() : saved
        }
        set { UserDefaults.standard.set(newValue, forKey: nameKey) }
    }

    static var computerName: String { Host.current().localizedName ?? "Mac" }

    /// When this version of ScaffoldPro was made (from install.sh), or nil.
    static var appVersion: String? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("version.txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private static func versionDate(_ v: String?) -> Date? {
        v.flatMap { ISO8601DateFormatter().date(from: $0) }
    }

    static func isWorkspace(_ folder: URL) -> Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: folder.appendingPathComponent(markerName).path)
            || fm.fileExists(atPath: folder.appendingPathComponent(".\(markerName).icloud").path)
    }

    /// "iCloud Drive › Proficiency › ScaffoldPro Team" for a folder in iCloud Drive.
    static func display(_ folder: URL) -> String {
        let drive = CloudBackupManager.iCloudDrive.path
        let path = folder.path
        return path.hasPrefix(drive + "/")
            ? (["iCloud Drive"] + path.dropFirst(drive.count + 1).split(separator: "/").map(String.init)).joined(separator: " › ")
            : path
    }

    // MARK: state (main thread)

    let root: URL
    let localData: URL
    let device: String
    private var databaseRoot: URL { root.appendingPathComponent("Database", isDirectory: true) }
    private var ownFolder: URL { databaseRoot.appendingPathComponent(device, isDirectory: true) }
    private var membersFolder: URL { root.appendingPathComponent("Members", isDirectory: true) }

    /// A record as last changed: when (t), its place in the list (c), and
    /// its value — nil once deleted.
    private struct Entry {
        var t: Double
        var c: Double
        var v: [String: Any]?
    }

    /// This Mac's log, store by store ("clients.json" → id → entry).
    private var own: [String: [String: Entry]] = [:]
    /// The other Macs' logs as last read, by file path.
    private var others: [String: (signature: String, device: String, store: String, entries: [String: Entry])] = [:]
    /// Each record's place in its list, from the last merge.
    private var order: [String: [String: Double]] = [:]
    private var lastStamp: Double = 0
    private var timer: Timer?
    private var scanning = false
    private(set) var lastChangeAt: Date?
    private(set) var lastChangeBy: String?
    /// Called (main thread) after other Macs' changes are merged in: the
    /// stores that changed and who changed them.
    var onRemoteChange: (([String], [String]) -> Void)?
    private let queue = DispatchQueue(label: "ScaffoldPro.teamSync", qos: .userInitiated)

    /// Only these stores (the material list), or nil for all of them.
    let only: Set<String>?

    init(root: URL, localData: URL, only: Set<String>? = nil) {
        self.root = root
        self.localData = localData
        self.device = TeamSync.deviceId
        self.only = only
    }

    func handles(_ store: String) -> Bool {
        only?.contains(store) ?? true
    }

    /// This Mac already has a log here (maybe still in iCloud only).
    var hasOwnLog: Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: ownFolder.path)) ?? []
        return names.contains { name in
            let plain = name.hasPrefix(".") && name.hasSuffix(".icloud") ? String(name.dropFirst().dropLast(".icloud".count)) : name
            return plain.hasSuffix(".json") && handles(plain)
        }
    }

    // MARK: starting

    /// Reads every log, rebuilds the local copy from them, and starts
    /// recording this Mac's saves. Call before the database is opened.
    /// False if this Mac's own log couldn't be read (still only in iCloud):
    /// adding to it then would lose what's in it.
    func start(downloadTimeout: TimeInterval = 30) -> Bool {
        let fm = FileManager.default
        try? fm.createDirectory(at: ownFolder, withIntermediateDirectories: true)
        try? fm.createDirectory(at: localData, withIntermediateDirectories: true)
        guard downloadEverything(in: ownFolder, timeout: downloadTimeout) else { return false }
        for url in logFiles(in: ownFolder) {
            guard let log = parseLog(url) else { return false }
            own[url.lastPathComponent] = log
        }
        lastStamp = own.values.flatMap { $0.values.map { $0.t } }.max() ?? 0
        let scan = scanOthers(known: [:])
        apply(scan)
        // The local copy is exactly the merge of the logs: stores with no
        // record in any log are emptied.
        var stores = Set(logFiles(in: localData).map { $0.lastPathComponent })
        stores.formUnion(own.keys)
        stores.formUnion(others.values.map { $0.store })
        for store in stores { materialize(store) }
        if only == nil { TeamSync.current = self } else { TeamSync.material = self }
        touchMember()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.checkForChanges() }
        Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in self?.touchMember() }
        return true
    }

    /// Brings back any file in `folder` that iCloud Drive has moved off
    /// this Mac (".name.icloud"), waiting up to `timeout` seconds.
    private func downloadEverything(in folder: URL, timeout: TimeInterval) -> Bool {
        let fm = FileManager.default
        let waiting = ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasPrefix(".") && $0.hasSuffix(".icloud") }
            .map { folder.appendingPathComponent(String($0.dropFirst().dropLast(".icloud".count))) }
        for url in waiting { try? fm.startDownloadingUbiquitousItem(at: url) }
        let started = Date()
        while waiting.contains(where: { !fm.fileExists(atPath: $0.path) }) {
            if Date().timeIntervalSince(started) > timeout { return false }
            Thread.sleep(forTimeInterval: 0.25)
        }
        return true
    }

    // MARK: this Mac's saves

    /// Called by JSONStore after it saves a store in the local copy.
    func recordLocalWrite(store: String, old: Data?, new: Data) {
        guard old != new else { return }
        let before = TeamSync.recordsById(old)
        let after = TeamSync.recordsById(new)
        var log = own[store] ?? [:]
        var places = order[store] ?? [:]
        var changed = false
        let now = nextStamp()
        for (index, (id, record)) in after.list.enumerated() {
            guard before.canonical[id] != after.canonical[id] else { continue }
            // New records go after the rest, in the order they were saved.
            let place = places[id] ?? now + Double(index) * 1e-6
            log[id] = Entry(t: now, c: place, v: portable(record))
            places[id] = place
            changed = true
        }
        for id in before.canonical.keys where after.canonical[id] == nil {
            log[id] = Entry(t: now, c: places[id] ?? 0, v: nil)
            places[id] = nil
            changed = true
        }
        guard changed else { return }
        own[store] = log
        order[store] = places
        writeOwnLog(store)
    }

    /// Puts every record of this Mac's own (unshared) data into the shared
    /// folder's log, in its present order — used once, when sharing starts.
    /// Paths into `fromRoot` become paths into the shared folder.
    /// `stamp`: when the records count as changed (default now). The
    /// material list is put in as of when it was last saved on this Mac, so
    /// a newer change made on another Mac isn't overwritten by it.
    func seed(from dataDir: URL, fromRoot: URL, stamp: Double? = nil) {
        let fm = FileManager.default
        try? fm.createDirectory(at: ownFolder, withIntermediateDirectories: true)
        let now = stamp ?? nextStamp()
        for url in logFiles(in: dataDir) {
            let parsed = TeamSync.recordsById(try? Data(contentsOf: url))
            var log: [String: Entry] = [:]
            for (index, (id, record)) in parsed.list.enumerated() {
                log[id] = Entry(t: now, c: Double(index), v: portable(record, extraRoots: [fromRoot]))
            }
            own[url.lastPathComponent] = log
            writeOwnLog(url.lastPathComponent)
        }
    }

    /// Later than every change seen so far — also the other Macs', so a
    /// change made after seeing theirs wins even if their clock is ahead.
    private func nextStamp() -> Double {
        lastStamp = max(Date().timeIntervalSince1970, lastStamp + 0.001)
        return lastStamp
    }

    private func writeOwnLog(_ store: String) {
        var records: [String: Any] = [:]
        for (id, e) in own[store] ?? [:] {
            let value: Any = e.v.map { $0 as Any } ?? NSNull()
            records[id] = ["t": e.t, "c": e.c, "v": value] as [String: Any]
        }
        let file: [String: Any] = ["format": 1, "device": device, "records": records]
        guard let data = try? JSONSerialization.data(withJSONObject: file, options: [.sortedKeys, .withoutEscapingSlashes]) else { return }
        try? FileManager.default.createDirectory(at: ownFolder, withIntermediateDirectories: true)
        try? data.write(to: ownFolder.appendingPathComponent(store), options: .atomic)
    }

    // MARK: the other Macs' changes

    private struct Scan {
        var changed: [String: (signature: String, device: String, store: String, entries: [String: Entry])] = [:]
        var gone: [String] = []
    }

    private func checkForChanges() {
        guard !scanning else { return }
        scanning = true
        let known = others.mapValues { $0.signature }
        queue.async { [weak self] in
            guard let self = self else { return }
            let scan = self.scanOthers(known: known)
            DispatchQueue.main.async {
                self.scanning = false
                guard !scan.changed.isEmpty || !scan.gone.isEmpty else { return }
                let stores = self.apply(scan)
                for store in stores { self.materialize(store) }
                let names = Set(scan.changed.values.map { $0.device }).map { self.memberName(of: $0) }.sorted()
                self.lastChangeAt = Date()
                self.lastChangeBy = names.joined(separator: ", ")
                self.onRemoteChange?(stores.sorted(), names)
            }
        }
    }

    /// Other Macs' logs that are new or changed since `known` (background
    /// or main thread; touches no state).
    private func scanOthers(known: [String: String]) -> Scan {
        let fm = FileManager.default
        var scan = Scan()
        var seen = Set<String>()
        let devices = ((try? fm.contentsOfDirectory(at: databaseRoot, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { $0.lastPathComponent != device && !$0.lastPathComponent.hasPrefix(".") }
        for folder in devices {
            // Logs iCloud has moved off this Mac: ask for them back.
            for name in (try? fm.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix(".") && name.hasSuffix(".json.icloud") {
                try? fm.startDownloadingUbiquitousItem(at: folder.appendingPathComponent(name))
            }
            for url in logFiles(in: folder) {
                let path = url.path
                seen.insert(path)
                let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
                let signature = "\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)/\(values?.fileSize ?? -1)"
                guard known[path] != signature else { continue }
                // Unreadable (e.g. still arriving): try again next time.
                guard let entries = parseLog(url) else { continue }
                scan.changed[path] = (signature, folder.lastPathComponent, url.lastPathComponent, entries)
            }
        }
        scan.gone = known.keys.filter { !seen.contains($0) }
        return scan
    }

    /// Takes in a scan; returns the stores it affects.
    @discardableResult
    private func apply(_ scan: Scan) -> Set<String> {
        var stores = Set<String>()
        for (path, log) in scan.changed {
            others[path] = log
            stores.insert(log.store)
            lastStamp = max(lastStamp, log.entries.values.map { $0.t }.max() ?? 0)
        }
        for path in scan.gone {
            if let log = others.removeValue(forKey: path) { stores.insert(log.store) }
        }
        return stores
    }

    /// Rewrites the local copy of a store from every Mac's log: each
    /// record's newest change wins; deleted records are left out.
    private func materialize(_ store: String) {
        var best: [String: (entry: Entry, device: String)] = [:]
        func consider(_ id: String, _ e: Entry, _ from: String) {
            if let b = best[id], b.entry.t > e.t || (b.entry.t == e.t && b.device >= from) { return }
            best[id] = (e, from)
        }
        for log in others.values where log.store == store {
            for (id, e) in log.entries { consider(id, e, log.device) }
        }
        for (id, e) in own[store] ?? [:] { consider(id, e, device) }
        order[store] = best.mapValues { $0.entry.c }
        let live = best.compactMap { id, b -> (String, Double, [String: Any])? in
            guard let v = b.entry.v else { return nil }
            return (id, b.entry.c, v)
        }.sorted { ($0.1, $0.0) < ($1.1, $1.0) }
        let records = live.map { local($0.2) }
        guard let data = try? JSONSerialization.data(withJSONObject: records, options: [.withoutEscapingSlashes]) else { return }
        let url = localData.appendingPathComponent(store)
        if (try? Data(contentsOf: url)) == data { return }
        try? data.write(to: url, options: .atomic)
    }

    // MARK: members

    private func touchMember() {
        let fm = FileManager.default
        try? fm.createDirectory(at: membersFolder, withIntermediateDirectories: true)
        let me = TeamMember(id: device, name: TeamSync.memberName, computer: TeamSync.computerName, lastSeen: nowISO(), version: TeamSync.appVersion)
        if let data = try? JSONEncoder().encode(me) {
            try? data.write(to: membersFolder.appendingPathComponent("\(device).json"), options: .atomic)
        }
    }

    func setMemberName(_ name: String) {
        TeamSync.memberName = name
        touchMember()
    }

    func members() -> [TeamMember] {
        let fm = FileManager.default
        var list = ((try? fm.contentsOfDirectory(at: membersFolder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .compactMap { (try? Data(contentsOf: $0)).flatMap { try? JSONDecoder().decode(TeamMember.self, from: $0) } }
        let mine = TeamSync.versionDate(TeamSync.appVersion)
        for i in list.indices {
            list[i].isThisMac = list[i].id == device
            if let mine = mine, let theirs = TeamSync.versionDate(list[i].version), list[i].id != device {
                list[i].outdated = theirs < mine
            }
        }
        return list.sorted { ($0.isThisMac == true ? 0 : 1, $0.name) < ($1.isThisMac == true ? 0 : 1, $1.name) }
    }

    private func memberName(of id: String) -> String {
        let url = membersFolder.appendingPathComponent("\(id).json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(TeamMember.self, from: $0) }?.name ?? "another Mac"
    }

    // MARK: JSON helpers

    private func logFiles(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") && !$0.lastPathComponent.contains(".unreadable-")
                && handles($0.lastPathComponent) }
    }

    private func parseLog(_ url: URL) -> [String: Entry]? {
        guard let data = try? Data(contentsOf: url),
              let file = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let records = file["records"] as? [String: Any] else { return nil }
        var entries: [String: Entry] = [:]
        for (id, raw) in records {
            guard let e = raw as? [String: Any], let t = (e["t"] as? NSNumber)?.doubleValue else { continue }
            entries[id] = Entry(t: t, c: (e["c"] as? NSNumber)?.doubleValue ?? 0, v: e["v"] as? [String: Any])
        }
        return entries
    }

    /// A store file's records by id, in file order, with a canonical form
    /// of each for spotting changes.
    private static func recordsById(_ data: Data?) -> (list: [(String, [String: Any])], canonical: [String: Data]) {
        guard let data = data, let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return ([], [:]) }
        var list: [(String, [String: Any])] = []
        var canonical: [String: Data] = [:]
        for case let record as [String: Any] in array {
            guard let id = record["id"] as? String, canonical[id] == nil else { continue }
            list.append((id, record))
            canonical[id] = (try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])) ?? Data()
        }
        return (list, canonical)
    }

    /// Paths into the shared folder (or `extraRoots`) → relative to it.
    private func portable(_ record: [String: Any], extraRoots: [URL] = []) -> [String: Any] {
        let prefixes = ([root] + extraRoots).map { $0.standardizedFileURL.path + "/" }
        return TeamSync.mapStrings(record) { s in
            for p in prefixes where s.hasPrefix(p) { return TeamSync.pathToken + "/" + s.dropFirst(p.count) }
            return s
        } as? [String: Any] ?? record
    }

    /// Relative paths → this Mac's path to the shared folder.
    private func local(_ record: [String: Any]) -> [String: Any] {
        let prefix = TeamSync.pathToken + "/"
        let base = root.standardizedFileURL.path + "/"
        return TeamSync.mapStrings(record) { s in
            s.hasPrefix(prefix) ? base + s.dropFirst(prefix.count) : s
        } as? [String: Any] ?? record
    }

    private static func mapStrings(_ value: Any, _ f: (String) -> String) -> Any {
        switch value {
        case let s as String: return f(s)
        case let d as [String: Any]: return d.mapValues { mapStrings($0, f) }
        case let a as [Any]: return a.map { mapStrings($0, f) }
        default: return value
        }
    }

    // MARK: status

    func status() -> TeamStatus {
        let list = members()
        // Only Macs used in the last two weeks count.
        let recent = Date().addingTimeInterval(-14 * 86400)
        let mine = TeamSync.versionDate(TeamSync.appVersion)
        let newerElsewhere = list.contains { m in
            guard m.isThisMac != true, let seen = ISO8601DateFormatter().date(from: m.lastSeen), seen > recent,
                  let theirs = TeamSync.versionDate(m.version) else { return false }
            return mine.map { theirs > $0 } ?? false
        }
        var s = TeamStatus(enabled: true, folder: root.path, folderDisplay: TeamSync.display(root), folderMissing: false,
                           memberName: TeamSync.memberName, members: list,
                           lastChangeAt: lastChangeAt.map { ISO8601DateFormatter().string(from: $0) }, lastChangeBy: lastChangeBy,
                           iCloudDrive: CloudBackupManager.iCloudDrive.path)
        s.thisMacOutdated = newerElsewhere
        return s
    }

    // MARK: setting up a shared folder (main thread; the copying runs in the background)

    /// Makes `folder` a shared workspace from this Mac's own data: copies
    /// the project and company files in, and the whole database as this
    /// Mac's first log. Calls `done` (main thread) with an error message,
    /// or nil when it's ready.
    static func createWorkspace(in folder: URL, dataDir: URL, storage: FileStorage, done: @escaping (String?) -> Void) {
        let fm = FileManager.default
        DispatchQueue.global(qos: .userInitiated).async {
            var failed: [String] = []
            for name in ["Projects", "Administration"] {
                let source = storage.appRoot.appendingPathComponent(name, isDirectory: true)
                guard fm.fileExists(atPath: source.path) else { continue }
                failed += TeamSync.copyMerging(source, into: folder.appendingPathComponent(name, isDirectory: true))
            }
            DispatchQueue.main.async {
                guard failed.isEmpty else {
                    done("\(failed.count) file\(failed.count == 1 ? "" : "s") couldn't be copied into the shared folder, e.g. \(failed[0]). Nothing has changed — try again.")
                    return
                }
                let sync = TeamSync(root: folder, localData: dataDir)
                sync.seed(from: dataDir, fromRoot: storage.appRoot)
                sync.touchMember()
                let marker: [String: Any] = ["app": "ScaffoldPro", "format": 1, "createdAt": nowISO(),
                                             "createdBy": TeamSync.memberName, "note": "A ScaffoldPro shared folder. Don't move or rename the files in here by hand."]
                do {
                    let data = try JSONSerialization.data(withJSONObject: marker, options: [.prettyPrinted, .sortedKeys])
                    try data.write(to: folder.appendingPathComponent(TeamSync.markerName), options: .atomic)
                } catch {
                    done("The shared folder couldn't be set up: \(error.localizedDescription)")
                    return
                }
                done(nil)
            }
        }
    }

    /// Copies a folder's files into another, leaving files already there.
    private static func copyMerging(_ source: URL, into destination: URL) -> [String] {
        let fm = FileManager.default
        var failed: [String] = []
        guard let walker = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { return failed }
        let base = source.standardizedFileURL.pathComponents.count
        try? fm.createDirectory(at: destination, withIntermediateDirectories: true)
        for case let url as URL in walker {
            let relative = url.standardizedFileURL.pathComponents.dropFirst(base)
            let out = relative.reduce(destination) { $0.appendingPathComponent($1) }
            if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                try? fm.createDirectory(at: out, withIntermediateDirectories: true)
            } else if !fm.fileExists(atPath: out.path) {
                do { try fm.copyItem(at: url, to: out) } catch { failed.append(relative.joined(separator: "/")) }
            }
        }
        return failed
    }
}

// =====================================================================
// MARK: - Native bridge (replaces main.js's ipcMain handlers)
// =====================================================================

final class NativeBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    weak var window: NSWindow?
    let db: AppDatabase
    let storage: FileStorage
    let backups: BackupManager
    let cloudBackup: CloudBackupManager
    /// Only one backup or restore may run at a time.
    private var backupInProgress = false
    /// A parsed-but-not-yet-applied price import, keyed by the preview's
    /// token, so the person can review it before anything changes.
    private var pendingPriceImport: (token: String, sourceKey: String, rows: [ParsedPriceRow])?

    init(db: AppDatabase, storage: FileStorage) {
        self.db = db
        self.storage = storage
        self.backups = BackupManager(db: db, storage: storage)
        self.cloudBackup = CloudBackupManager(db: db, storage: storage)
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let action = body["action"] as? String else { return }
        let payload = (body["payload"] as? [String: Any]) ?? [:]

        switch action {
        case "clients:list":
            respond(id: id, encodable: db.listClients(includeArchived: (payload["includeArchived"] as? Bool) ?? false))
        case "clients:create":
            respond(id: id, encodable: db.createClient(payload))
        case "clients:update":
            let error = db.updateClient(id: (payload["id"] as? String) ?? "", payload: payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "clients:setArchived":
            let error = db.setClientArchived(id: (payload["id"] as? String) ?? "", archived: (payload["archived"] as? Bool) ?? true)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "clients:detail":
            respond(id: id, encodable: db.partyDetail(clientId: (payload["id"] as? String) ?? "", siteId: nil))
        case "sites:list":
            respond(id: id, encodable: db.listSites(includeArchived: (payload["includeArchived"] as? Bool) ?? false))
        case "sites:create":
            respond(id: id, encodable: db.createSite(payload))
        case "sites:update":
            let error = db.updateSite(id: (payload["id"] as? String) ?? "", payload: payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "sites:setArchived":
            let error = db.setSiteArchived(id: (payload["id"] as? String) ?? "", archived: (payload["archived"] as? Bool) ?? true)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "sites:detail":
            respond(id: id, encodable: db.partyDetail(clientId: nil, siteId: (payload["id"] as? String) ?? ""))

        case "dashboard:summary":
            respond(id: id, encodable: db.dashboardSummary())
        case "search:query":
            respond(id: id, encodable: db.search((payload["query"] as? String) ?? ""))
        case "activity:listForProject":
            respond(id: id, encodable: db.listActivity(projectId: (payload["projectId"] as? String) ?? "", limit: (payload["limit"] as? Int) ?? 200))
        case "priceLists:list":
            respond(id: id, encodable: db.listPriceLists())
        case "priceListItems:search":
            let sourceKey = (payload["sourceKey"] as? String) ?? ""
            let query = (payload["query"] as? String) ?? ""
            let category = payload["category"] as? String
            let found = db.searchPriceListItems(sourceKey: sourceKey, query: query, category: category)
            // Document pickers ask for prices in HKD; the Material List page
            // shows each list in its own currency.
            respond(id: id, encodable: (payload["inBaseCurrency"] as? Bool) == true ? db.inBaseCurrency(found) : found)
        case "priceListItems:update":
            handleUpdatePriceListItem(id: id, payload: payload)
        case "priceListItems:create":
            switch db.createPriceListItem(sourceKey: (payload["sourceKey"] as? String) ?? "", payload: payload) {
            case .success: respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            case .failure(let e): respond(id: id, encodable: SimpleResult(ok: false, error: e.message))
            }
        case "priceListItems:archive":
            let error = db.archivePriceListItem(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "priceLists:syncStatus":
            // How the material list is kept the same on every Mac.
            struct MaterialSyncStatus: Encodable { var mode: String; var folder: String?; var otherMacs: Int }
            if let team = TeamSync.current {
                respond(id: id, encodable: MaterialSyncStatus(mode: "team", folder: TeamSync.display(team.root), otherMacs: max(0, team.members().count - 1)))
            } else if let material = TeamSync.material {
                respond(id: id, encodable: MaterialSyncStatus(mode: "icloud", folder: TeamSync.display(material.root), otherMacs: max(0, material.members().count - 1)))
            } else {
                respond(id: id, encodable: MaterialSyncStatus(mode: "off", folder: nil, otherMacs: 0))
            }
        case "priceLists:unitRatesPDF":
            handleExportUnitRates(id: id, payload: payload)
        case "priceListItems:setPinned":
            let error = db.setPriceListItemPinned(id: (payload["id"] as? String) ?? "", pinned: (payload["pinned"] as? Bool) ?? false)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "priceListItems:reorder":
            let error = db.reorderPriceListItems(ids: (payload["ids"] as? [String]) ?? [])
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "priceListItems:duplicate":
            switch db.duplicatePriceListItem(id: (payload["id"] as? String) ?? "") {
            case .success: respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            case .failure(let e): respond(id: id, encodable: SimpleResult(ok: false, error: e.message))
            }
        case "priceLists:importPreview":
            handlePriceImportPreview(id: id, sourceKey: (payload["sourceKey"] as? String) ?? "")
        case "priceLists:importApply":
            handlePriceImportApply(id: id, token: (payload["token"] as? String) ?? "")
        case "priceLists:exportCSV":
            handlePriceExportCSV(id: id, sourceKey: (payload["sourceKey"] as? String) ?? "")
        case "projects:list":
            respond(id: id, encodable: projectListEntries())
        case "projects:proposeNumber":
            respond(id: id, encodable: nextProjectNumber(existingNumbers: db.allProjectNumbers()))
        case "projects:create":
            handleCreateProject(id: id, payload: payload)
        case "projects:get":
            handleGetProject(id: id, payload: payload)
        case "projects:changeNumber":
            handleChangeProjectNumber(id: id, projectId: (payload["id"] as? String) ?? "", newNumber: (payload["projectNumber"] as? String) ?? "")
        case "projects:update":
            let error = db.updateProject(id: (payload["id"] as? String) ?? "", payload: payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "projects:updateStatus":
            if let pid = payload["id"] as? String, let status = payload["status"] as? String {
                db.updateProjectStatus(id: pid, status: status)
            }
            respondNull(id: id)
        case "projects:revealFolder":
            let number = (payload["projectNumber"] as? String) ?? ""
            let folder = storage.projectFolder(number)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            storage.revealInFinder(folder)
            respondNull(id: id)
        case "files:dropIntoProject":
            handleDroppedProjectFiles(id: id, payload: payload)
        case "projects:uploadDrawing":
            let number = (payload["projectNumber"] as? String) ?? ""
            handleUploadDrawing(id: id, projectNumber: number, linkedKind: payload["linkedKind"] as? String, linkedId: payload["linkedId"] as? String)
        case "drawings:setLink":
            let error = db.setDrawingLink(id: (payload["id"] as? String) ?? "", kind: payload["linkedKind"] as? String, linkedId: payload["linkedId"] as? String)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "drawings:listForDocument":
            respond(id: id, encodable: db.listDrawings(linkedKind: (payload["linkedKind"] as? String) ?? "", linkedId: (payload["linkedId"] as? String) ?? ""))

        case "boq:listForProject":
            let projectId = (payload["projectId"] as? String) ?? ""
            respond(id: id, encodable: db.listBOQSummaries(projectId: projectId))
        case "boq:combine":
            let r = db.combineBOQs(ids: (payload["ids"] as? [String]) ?? [])
            respond(id: id, encodable: CombinedDocumentResult(ok: r.error == nil, error: r.error, id: r.id))
        case "deliveryNotes:combine":
            let r = db.combineDeliveryNotes(ids: (payload["ids"] as? [String]) ?? [])
            respond(id: id, encodable: CombinedDocumentResult(ok: r.error == nil, error: r.error, id: r.id))
        case "deliveryNotes:importQuotation":
            let r = db.importQuotationIntoDeliveryNote(
                deliveryNoteId: (payload["id"] as? String) ?? "",
                quotationId: (payload["quotationId"] as? String) ?? "",
                replaceExisting: (payload["replaceExisting"] as? Bool) ?? false
            )
            respond(id: id, encodable: DroppedFilesResult(ok: r.error == nil, added: r.added, error: r.error))
        case "boq:create":
            handleCreateBOQ(id: id, payload: payload)
        case "boq:get":
            let boqId = (payload["id"] as? String) ?? ""
            if let detail = db.getBOQDetail(id: boqId) {
                respond(id: id, encodable: detail)
            } else {
                respondNull(id: id)
            }
        case "boq:addLineItem":
            handleAddBOQLineItem(id: id, payload: payload)
        case "boq:updateLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            let quantity = payload["quantity"] as? Double
            let appliedUnitPrice = payload["appliedUnitPrice"] as? Double
            if let error = db.updateBOQLineItem(id: lineId, quantity: quantity, appliedUnitPrice: appliedUnitPrice) {
                respond(id: id, encodable: BOQActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: BOQActionResult(ok: true, error: nil))
            }
        case "boq:removeLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            if let error = db.removeBOQLineItem(id: lineId) {
                respond(id: id, encodable: BOQActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: BOQActionResult(ok: true, error: nil))
            }
        case "boq:updateStatus":
            let boqId = (payload["id"] as? String) ?? ""
            let status = (payload["status"] as? String) ?? ""
            if let error = db.updateBOQStatus(id: boqId, status: status) {
                respond(id: id, encodable: BOQActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: BOQActionResult(ok: true, error: nil))
            }
        case "boq:updateSheetExtras":
            let error = db.updateBOQSheetExtras(id: (payload["id"] as? String) ?? "", payload: payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "boq:updateNotes":
            let boqId = (payload["id"] as? String) ?? ""
            let notes = payload["notes"] as? String
            db.updateBOQNotes(id: boqId, notes: notes)
            respondNull(id: id)
        case "boq:delete":
            let boqId = (payload["id"] as? String) ?? ""
            if let error = db.deleteBOQ(id: boqId, includingIssued: (payload["force"] as? Bool) ?? false) {
                respond(id: id, encodable: BOQActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: BOQActionResult(ok: true, error: nil))
            }

        case "quotations:listForProject":
            let projectId = (payload["projectId"] as? String) ?? ""
            respond(id: id, encodable: db.listQuotationSummaries(projectId: projectId))
        case "quotations:create":
            handleCreateQuotation(id: id, payload: payload)
        case "quotations:get":
            let qid = (payload["id"] as? String) ?? ""
            if let detail = db.getQuotationDetail(id: qid) {
                respond(id: id, encodable: detail)
            } else {
                respondNull(id: id)
            }
        case "quotations:addLineItem":
            handleAddQuotationLineItem(id: id, payload: payload)
        case "quotations:updateLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            let quantity = payload["quantity"] as? Double
            let appliedUnitPrice = payload["appliedUnitPrice"] as? Double
            if let error = db.updateQuotationLineItem(id: lineId, quantity: quantity, appliedUnitPrice: appliedUnitPrice,
                                                      description: payload["itemDescription"] as? String, unit: payload["unit"] as? String) {
                respond(id: id, encodable: QuotationActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
            }
        case "quotations:removeLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            if let error = db.removeQuotationLineItem(id: lineId) {
                respond(id: id, encodable: QuotationActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
            }
        case "quotations:addBlock":
            switch db.addQuotationBlock(quotationId: (payload["quotationId"] as? String) ?? "", kind: (payload["kind"] as? String) ?? "") {
            case .success: respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
            case .failure(let e): respond(id: id, encodable: QuotationActionResult(ok: false, error: e.message))
            }
        case "quotations:updateBlock":
            let error = db.updateQuotationBlock(id: (payload["id"] as? String) ?? "", payload: payload)
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:moveBlock":
            let error = db.moveQuotationBlock(id: (payload["id"] as? String) ?? "", up: (payload["up"] as? Bool) ?? true)
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:reorderBlocks":
            let error = db.reorderQuotationBlocks(quotationId: (payload["quotationId"] as? String) ?? "", ids: (payload["ids"] as? [String]) ?? [])
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:removeBlock":
            let error = db.removeQuotationBlock(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:addStandardRates":
            let error = db.addStandardManpowerRates(quotationId: (payload["quotationId"] as? String) ?? "", blockId: payload["blockId"] as? String)
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:addBlockLine":
            let error = db.addQuotationBlockLine(
                blockId: (payload["blockId"] as? String) ?? "", description: (payload["description"] as? String) ?? "",
                unit: (payload["unit"] as? String) ?? "", quantity: (payload["quantity"] as? Double) ?? 1,
                price: (payload["price"] as? Double) ?? 0)
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:updateLineDiscount":
            let error = db.updateQuotationLineDiscount(id: (payload["id"] as? String) ?? "", type: payload["discountType"] as? String,
                                                       value: payload["discountValue"] as? Double)
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:updateHeader":
            handleUpdateQuotationHeader(id: id, payload: payload)
        case "quotations:updateLetterFields":
            let error = db.updateQuotationLetterFields(id: (payload["id"] as? String) ?? "", payload: payload)
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:importFromBOQ":
            let qid = (payload["quotationId"] as? String) ?? ""
            let boqId = (payload["boqId"] as? String) ?? ""
            let replaceExisting = (payload["replaceExisting"] as? Bool) ?? false
            if let error = db.importBOQIntoQuotation(quotationId: qid, boqId: boqId, replaceExisting: replaceExisting) {
                respond(id: id, encodable: QuotationActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
            }
        case "quotations:updateStatus":
            let qid = (payload["id"] as? String) ?? ""
            let status = (payload["status"] as? String) ?? ""
            if let error = db.updateQuotationStatus(id: qid, status: status) {
                respond(id: id, encodable: QuotationActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
            }
        case "quotations:delete":
            let qid = (payload["id"] as? String) ?? ""
            if let error = db.deleteQuotation(id: qid, includingIssued: (payload["force"] as? Bool) ?? false) {
                respond(id: id, encodable: QuotationActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
            }

        case "invoices:listForProject":
            let projectId = (payload["projectId"] as? String) ?? ""
            respond(id: id, encodable: db.listInvoiceSummaries(projectId: projectId))
        case "invoices:create":
            handleCreateInvoice(id: id, payload: payload)
        case "invoices:get":
            let invId = (payload["id"] as? String) ?? ""
            if let detail = db.getInvoiceDetail(id: invId) {
                respond(id: id, encodable: detail)
            } else {
                respondNull(id: id)
            }
        case "invoices:addLineItem":
            handleAddInvoiceLineItem(id: id, payload: payload)
        case "invoices:updateLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            let quantity = payload["quantity"] as? Double
            let appliedUnitPrice = payload["appliedUnitPrice"] as? Double
            if let error = db.updateInvoiceLineItem(id: lineId, quantity: quantity, appliedUnitPrice: appliedUnitPrice) {
                respond(id: id, encodable: InvoiceActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: InvoiceActionResult(ok: true, error: nil))
            }
        case "invoices:removeLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            if let error = db.removeInvoiceLineItem(id: lineId) {
                respond(id: id, encodable: InvoiceActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: InvoiceActionResult(ok: true, error: nil))
            }
        case "invoices:updateLineDiscount":
            let error = db.updateInvoiceLineDiscount(id: (payload["id"] as? String) ?? "", type: payload["discountType"] as? String,
                                                     value: payload["discountValue"] as? Double)
            respond(id: id, encodable: InvoiceActionResult(ok: error == nil, error: error))
        case "invoices:updateRental":
            let error = db.updateInvoiceRental(id: (payload["id"] as? String) ?? "", months: payload["rentalMonths"] as? Int,
                                               period: payload["rentalPeriod"] as? String, updatePeriod: payload.keys.contains("rentalPeriod"))
            respond(id: id, encodable: InvoiceActionResult(ok: error == nil, error: error))
        case "invoices:updateHeader":
            handleUpdateInvoiceHeader(id: id, payload: payload)
        case "invoices:updateStatus":
            let invId = (payload["id"] as? String) ?? ""
            let status = (payload["status"] as? String) ?? ""
            if let error = db.updateInvoiceStatus(id: invId, status: status) {
                respond(id: id, encodable: InvoiceActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: InvoiceActionResult(ok: true, error: nil))
            }
        case "invoices:recordPayment":
            let invId = (payload["id"] as? String) ?? ""
            let amount = (payload["amount"] as? Double) ?? 0
            if let error = db.recordInvoicePayment(id: invId, amount: amount, date: payload["date"] as? String,
                                                   method: payload["method"] as? String, reference: payload["reference"] as? String) {
                respond(id: id, encodable: InvoiceActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: InvoiceActionResult(ok: true, error: nil))
            }
        case "invoices:delete":
            let invId = (payload["id"] as? String) ?? ""
            if let error = db.deleteInvoice(id: invId, includingIssued: (payload["force"] as? Bool) ?? false) {
                respond(id: id, encodable: InvoiceActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: InvoiceActionResult(ok: true, error: nil))
            }
        case "invoices:exportPDF":
            let invId = (payload["id"] as? String) ?? ""
            handleExportInvoicePDF(id: id, invoiceId: invId)

        case "deliveryNotes:listForProject":
            let projectId = (payload["projectId"] as? String) ?? ""
            respond(id: id, encodable: db.listDeliveryNoteSummaries(projectId: projectId))
        case "deliveryNotes:create":
            handleCreateDeliveryNote(id: id, payload: payload)
        case "deliveryNotes:get":
            let dnId = (payload["id"] as? String) ?? ""
            if let detail = db.getDeliveryNoteDetail(id: dnId) {
                respond(id: id, encodable: detail)
            } else {
                respondNull(id: id)
            }
        case "deliveryNotes:addLineItem":
            handleAddDeliveryNoteLineItem(id: id, payload: payload)
        case "deliveryNotes:updateLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            let quantity = payload["quantity"] as? Double
            if let error = db.updateDeliveryNoteLineItem(id: lineId, quantity: quantity) {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: true, error: nil))
            }
        case "deliveryNotes:removeLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            if let error = db.removeDeliveryNoteLineItem(id: lineId) {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: true, error: nil))
            }
        case "deliveryNotes:updateHeader":
            handleUpdateDeliveryNoteHeader(id: id, payload: payload)
        case "deliveryNotes:updateStatus":
            let dnId = (payload["id"] as? String) ?? ""
            let status = (payload["status"] as? String) ?? ""
            if let error = db.updateDeliveryNoteStatus(id: dnId, status: status) {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: true, error: nil))
            }
        case "deliveryNotes:delete":
            let dnId = (payload["id"] as? String) ?? ""
            if let error = db.deleteDeliveryNote(id: dnId, includingIssued: (payload["force"] as? Bool) ?? false) {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: true, error: nil))
            }
        case "deliveryNotes:exportPDF":
            let dnId = (payload["id"] as? String) ?? ""
            handleExportDeliveryNotePDF(id: id, deliveryNoteId: dnId)

        case "stock:data":
            respond(id: id, encodable: db.stockData())
        case "stock:addMovement":
            let error = db.addStockMovement(payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "stock:deleteMovement":
            let error = db.deleteStockMovement(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "accounts:data":
            respond(id: id, encodable: db.accountsData())
        case "accounts:saveExpense":
            let error = db.saveExpense(payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "accounts:deleteExpense":
            let error = db.deleteExpense(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "accounts:saveCSV":
            handleSaveAccountsCSV(id: id, payload: payload)
        case "accounts:saveLiability":
            let error = db.saveLiability(payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "accounts:deleteLiability":
            let error = db.deleteLiability(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "accounts:addLiabilityPayment":
            let error = db.addLiabilityPayment(payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "accounts:deleteLiabilityPayment":
            let error = db.deleteLiabilityPayment(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "employees:list":
            respond(id: id, encodable: db.listEmployees())
        case "employees:save":
            let r = db.saveEmployee(payload)
            respond(id: id, encodable: EmployeeActionResult(ok: r.error == nil, error: r.error, id: r.id))
        case "employees:delete":
            let error = db.deleteEmployee(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "employees:recordPayroll":
            respond(id: id, encodable: db.recordPayroll(payload))
        case "boq:updateLineDiscount":
            let error = db.updateBOQLineDiscount(id: (payload["id"] as? String) ?? "", type: payload["discountType"] as? String,
                                                 value: payload["discountValue"] as? Double)
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:setRatesSection":
            var section: BOQRatesSection? = nil
            if let s = payload["section"] as? [String: Any] {
                let rates = ((s["rates"] as? [[String: Any]]) ?? []).map { r in
                    ManpowerRate(name: ((r["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                 rate: max(0, (r["rate"] as? Double) ?? 0),
                                 unit: ((r["unit"] as? String) ?? "md").trimmingCharacters(in: .whitespacesAndNewlines))
                }
                section = BOQRatesSection(title: ((s["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                          rates: rates, note: nonBlank(s["note"] as? String))
            }
            let error = db.setBOQRatesSection(id: (payload["id"] as? String) ?? "", section: section)
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:setCharges":
            var charges: [BOQCharge]? = nil
            if let list = payload["charges"] as? [[String: Any]] {
                charges = list.map { c in
                    BOQCharge(code: nonBlank(c["code"] as? String),
                              name: ((c["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                              amount: doubleOf(roundToCents(decimalOf((c["amount"] as? Double) ?? 0))))
                }
            }
            let error = db.setBOQCharges(id: (payload["id"] as? String) ?? "", charges: charges)
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:standardRates":
            respond(id: id, encodable: db.getCompanySettings().manpowerRates ?? defaultManpowerRates)
        case "boq:setOrientation":
            let error = db.setBOQOrientation(id: (payload["id"] as? String) ?? "", orientation: (payload["orientation"] as? String) ?? "")
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:updateDetails":
            let error = db.updateBOQDetails(id: (payload["id"] as? String) ?? "", pricingMode: payload["pricingMode"] as? String,
                                            markupPercent: payload["markupPercent"] as? Double,
                                            structure: payload["structure"] as? String, updateStructure: payload.keys.contains("structure"))
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:moveLineItem":
            let error = db.moveBOQLineItem(id: (payload["id"] as? String) ?? "", direction: (payload["direction"] as? Int) ?? 1)
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:reorderLineItems":
            let error = db.reorderBOQLineItems(boqId: (payload["boqId"] as? String) ?? "", ids: (payload["ids"] as? [String]) ?? [])
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:duplicateLineItem":
            let error = db.duplicateBOQLineItem(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:updateLineNotes":
            let error = db.updateBOQLineNotes(id: (payload["id"] as? String) ?? "", notes: payload["notes"] as? String)
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:exportPDF":
            let boqId = (payload["id"] as? String) ?? ""
            handleExportBOQPDF(id: id, boqId: boqId)
        case "quotations:exportPDF":
            let qid = (payload["id"] as? String) ?? ""
            handleExportQuotationPDF(id: id, quotationId: qid)
        case "boq:exportWord":
            handleExportBOQPDF(id: id, boqId: (payload["id"] as? String) ?? "", mode: .word)
        case "quotations:exportWord":
            handleExportQuotationPDF(id: id, quotationId: (payload["id"] as? String) ?? "", mode: .word)
        case "invoices:exportWord":
            handleExportInvoicePDF(id: id, invoiceId: (payload["id"] as? String) ?? "", mode: .word)
        case "deliveryNotes:exportWord":
            handleExportDeliveryNotePDF(id: id, deliveryNoteId: (payload["id"] as? String) ?? "", mode: .word)
        case "files:saveWord":
            handleSaveWord(id: id, payload: payload)
        case "files:locateDocument":
            handleLocateDocument(id: id, kind: (payload["kind"] as? String) ?? "", documentId: (payload["id"] as? String) ?? "")
        case "boq:print":
            handleExportBOQPDF(id: id, boqId: (payload["id"] as? String) ?? "", mode: .print)
        case "quotations:print":
            handleExportQuotationPDF(id: id, quotationId: (payload["id"] as? String) ?? "", mode: .print)
        case "quotations:combinePDF":
            handleCombineDocuments(id: id, kind: "Quotation", ids: (payload["ids"] as? [String]) ?? [], includeDrawings: (payload["includeDrawings"] as? Bool) ?? false)
        case "documents:combinePDF":
            handleCombineDocuments(id: id, kind: (payload["kind"] as? String) ?? "Quotation", ids: (payload["ids"] as? [String]) ?? [], includeDrawings: (payload["includeDrawings"] as? Bool) ?? false)
        case "files:locateDocuments":
            handleLocateDocuments(id: id, kind: (payload["kind"] as? String) ?? "", ids: (payload["ids"] as? [String]) ?? [])
        case "team:status":
            respond(id: id, encodable: teamStatus())
        case "team:start":
            handleStartTeam(id: id)
        case "team:join":
            handleJoinTeam(id: id)
        case "team:leave":
            TeamSync.setConfiguredFolder(nil)
            respond(id: id, encodable: SimpleResult(ok: true, error: nil))
        case "team:setName":
            let name = ((payload["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let sync = TeamSync.current { sync.setMemberName(name) } else { TeamSync.memberName = name }
            respond(id: id, encodable: teamStatus())
        case "team:reveal":
            if let folder = TeamSync.current?.root ?? TeamSync.configuredFolder, FileManager.default.fileExists(atPath: folder.path) {
                NSWorkspace.shared.activateFileViewerSelecting([folder])
                respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            } else {
                respond(id: id, encodable: SimpleResult(ok: false, error: "The shared folder can't be found."))
            }
        case "app:relaunch":
            respondNull(id: id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { relaunchApp() }
        case "quotations:uploadSigned":
            handleUploadSignedQuotation(id: id, quotationId: (payload["id"] as? String) ?? "")
        case "quotations:saveSignedFile":
            handleSaveSignedQuotationData(id: id, payload: payload)
        case "quotations:signedCopy":
            handleSignedCopyAction(id: id, quotationId: (payload["id"] as? String) ?? "", action: (payload["action"] as? String) ?? "")
        case "quotations:setSignedNotNeeded":
            let error = db.setQuotationSignedCopyNotNeeded(id: (payload["id"] as? String) ?? "", notNeeded: (payload["notNeeded"] as? Bool) ?? true)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "invoices:print":
            handleExportInvoicePDF(id: id, invoiceId: (payload["id"] as? String) ?? "", mode: .print)
        case "deliveryNotes:print":
            handleExportDeliveryNotePDF(id: id, deliveryNoteId: (payload["id"] as? String) ?? "", mode: .print)

        case "settings:get":
            respond(id: id, encodable: db.getCompanySettings())
        case "settings:update":
            let updated = db.updateCompanySettings(payload)
            applyAppearance(updated.appearance)
            respond(id: id, encodable: updated)
        case "settings:chooseLogo":
            handleChooseLogo(id: id)
        case "settings:removeLogo":
            db.setLogoPath(nil)
            respond(id: id, encodable: SimpleResult(ok: true, error: nil))
        case "settings:logoPreview":
            // The page can't read ~/Documents directly, so the logo comes
            // across as a data: URL.
            if let path = db.getCompanySettings().logoPath, let data = FileManager.default.contents(atPath: path) {
                let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
                let mime = ext == "png" ? "image/png" : ext == "tiff" || ext == "tif" ? "image/tiff" : "image/jpeg"
                respond(id: id, encodable: ["dataURL": "data:\(mime);base64,\(data.base64EncodedString())"])
            } else {
                respondNull(id: id)
            }
        case "settings:numberPreview":
            let template = (payload["template"] as? String) ?? ""
            respond(id: id, encodable: ["example": nextDocumentNumber(template: template.isEmpty ? (defaultNumberFormats[(payload["type"] as? String) ?? "QT"] ?? "{PROJECT}-{SEQ}") : template, projectNumber: nextProjectNumber(existingNumbers: db.allProjectNumbers()), existing: [])])

        case "drawings:listForProject":
            let projectId = (payload["projectId"] as? String) ?? ""
            respond(id: id, encodable: db.listDrawings(projectId: projectId))
        case "drawings:updateDescription":
            let drawingId = (payload["id"] as? String) ?? ""
            let description = payload["description"] as? String
            let error = db.updateDrawingDescription(id: drawingId, description: description)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "drawings:rename":
            let drawingId = (payload["id"] as? String) ?? ""
            let newName = (payload["newName"] as? String) ?? ""
            let error = db.renameDrawing(id: drawingId, newDisplayName: newName)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "drawings:archive":
            let drawingId = (payload["id"] as? String) ?? ""
            let error = db.archiveDrawing(id: drawingId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "drawings:removeReference":
            let drawingId = (payload["id"] as? String) ?? ""
            let error = db.removeDrawingReference(id: drawingId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "drawings:relink":
            let drawingId = (payload["id"] as? String) ?? ""
            handleRelinkFile(id: id, recordId: drawingId, target: .drawing)
        case "drawings:replace":
            handleReplaceFile(id: id, recordId: (payload["id"] as? String) ?? "", isDrawing: true)
        case "documents:replace":
            handleReplaceFile(id: id, recordId: (payload["id"] as? String) ?? "", isDrawing: false)
        case "drawings:open":
            let drawingId = (payload["id"] as? String) ?? ""
            if let drawing = db.getDrawing(id: drawingId) {
                handleOpenFile(id: id, path: drawing.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Drawing not found."))
            }
        case "drawings:reveal":
            let drawingId = (payload["id"] as? String) ?? ""
            if let drawing = db.getDrawing(id: drawingId) {
                handleRevealFile(id: id, path: drawing.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Drawing not found."))
            }

        case "workers:list":
            let includeArchived = (payload["includeArchived"] as? Bool) ?? false
            respond(id: id, encodable: db.listWorkers(includeArchived: includeArchived))
        case "workers:create":
            switch db.createWorker(payload) {
            case .success(let worker):
                try? FileManager.default.createDirectory(at: storage.workerFolder(worker.workerNumber), withIntermediateDirectories: true)
                respond(id: id, encodable: WorkerActionResult(ok: true, error: nil, worker: worker))
            case .failure(let err):
                respond(id: id, encodable: WorkerActionResult(ok: false, error: err.message, worker: nil))
            }
        case "workers:update":
            let workerId = (payload["id"] as? String) ?? ""
            let error = db.updateWorker(id: workerId, payload: payload)
            respond(id: id, encodable: WorkerActionResult(ok: error == nil, error: error, worker: nil))
        case "workers:setArchived":
            let workerId = (payload["id"] as? String) ?? ""
            let archived = (payload["archived"] as? Bool) ?? true
            let error = db.setWorkerArchived(id: workerId, archived: archived)
            respond(id: id, encodable: WorkerActionResult(ok: error == nil, error: error, worker: nil))
        case "workers:revealFolder":
            let workerId = (payload["id"] as? String) ?? ""
            if let worker = db.getWorker(id: workerId) {
                let folder = storage.workerFolder(worker.workerNumber)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                storage.revealInFinder(folder)
            }
            respondNull(id: id)

        case "workerDocuments:list":
            let workerId = (payload["workerId"] as? String) ?? ""
            respond(id: id, encodable: db.listWorkerDocuments(workerId: workerId))
        case "workerDocuments:upload":
            let workerId = (payload["workerId"] as? String) ?? ""
            let category = (payload["category"] as? String) ?? "Other"
            let expiryDate = payload["expiryDate"] as? String
            handleUploadWorkerDocument(id: id, workerId: workerId, category: category, expiryDate: (expiryDate?.isEmpty ?? true) ? nil : expiryDate)
        case "workerDocuments:update":
            let docId = (payload["id"] as? String) ?? ""
            let description = payload["description"] as? String
            let expiryDate = payload["expiryDate"] as? String
            let error = db.updateWorkerDocument(id: docId, description: description, expiryDate: (expiryDate?.isEmpty ?? true) ? nil : expiryDate)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "workerDocuments:archive":
            let docId = (payload["id"] as? String) ?? ""
            let error = db.archiveWorkerDocument(id: docId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "workerDocuments:removeReference":
            let docId = (payload["id"] as? String) ?? ""
            let error = db.removeWorkerDocumentReference(id: docId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "workerDocuments:relink":
            let docId = (payload["id"] as? String) ?? ""
            handleRelinkFile(id: id, recordId: docId, target: .workerDocument)
        case "workerDocuments:open":
            let docId = (payload["id"] as? String) ?? ""
            if let doc = db.getWorkerDocument(id: docId) {
                handleOpenFile(id: id, path: doc.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Document not found."))
            }
        case "workerDocuments:reveal":
            let docId = (payload["id"] as? String) ?? ""
            if let doc = db.getWorkerDocument(id: docId) {
                handleRevealFile(id: id, path: doc.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Document not found."))
            }

        case "adminDocuments:list":
            respond(id: id, encodable: db.listAdminDocuments())
        case "adminDocuments:upload":
            let category = (payload["category"] as? String) ?? "Other"
            let expiryDate = payload["expiryDate"] as? String
            handleUploadAdminDocument(id: id, category: category, expiryDate: (expiryDate?.isEmpty ?? true) ? nil : expiryDate)
        case "adminDocuments:update":
            let docId = (payload["id"] as? String) ?? ""
            let description = payload["description"] as? String
            let expiryDate = payload["expiryDate"] as? String
            let error = db.updateAdminDocument(id: docId, description: description, expiryDate: (expiryDate?.isEmpty ?? true) ? nil : expiryDate)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "adminDocuments:archive":
            let docId = (payload["id"] as? String) ?? ""
            let error = db.archiveAdminDocument(id: docId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "adminDocuments:removeReference":
            let docId = (payload["id"] as? String) ?? ""
            let error = db.removeAdminDocumentReference(id: docId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "adminDocuments:relink":
            let docId = (payload["id"] as? String) ?? ""
            handleRelinkFile(id: id, recordId: docId, target: .adminDocument)
        case "adminDocuments:open":
            let docId = (payload["id"] as? String) ?? ""
            if let doc = db.getAdminDocument(id: docId) {
                handleOpenFile(id: id, path: doc.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Document not found."))
            }
        case "adminDocuments:reveal":
            let docId = (payload["id"] as? String) ?? ""
            if let doc = db.getAdminDocument(id: docId) {
                handleRevealFile(id: id, path: doc.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Document not found."))
            }
        case "adminDocuments:expiring":
            let days = (payload["days"] as? Int) ?? 30
            respond(id: id, encodable: db.expiringDocuments(withinDays: days))

        case "backup:list":
            respond(id: id, encodable: backups.listBackups())
        case "backup:locations":
            respond(id: id, encodable: DataLocations(
                documentsFolder: storage.appRoot.path,
                backupsFolder: storage.backupsRoot.path,
                databaseFolder: db.dataDir.path
            ))
        case "cloudBackup:status":
            respond(id: id, encodable: cloudBackup.status())
        case "cloudBackup:setEnabled":
            cloudBackup.enabled = (payload["enabled"] as? Bool) ?? true
            if cloudBackup.enabled { cloudBackup.schedule(after: 1) }
            respond(id: id, encodable: cloudBackup.status())
        case "cloudBackup:backUpNow":
            cloudBackup.backUpNow { [weak self] status in self?.respond(id: id, encodable: status) }
        case "cloudBackup:useDefaultFolder":
            cloudBackup.setFolder(nil)
            cloudBackup.schedule(after: 1)
            respond(id: id, encodable: cloudBackup.status())
        case "cloudBackup:chooseFolder":
            handleChooseCloudFolder(id: id)
        case "cloudBackup:reveal":
            let fm = FileManager.default
            let target = [cloudBackup.folder, CloudBackupManager.iCloudDrive].first { fm.fileExists(atPath: $0.path) }
            if let target = target { storage.revealInFinder(target) }
            respond(id: id, encodable: SimpleResult(ok: target != nil, error: target == nil ? "iCloud Drive wasn't found on this Mac." : nil))
        case "backup:create":
            handleCreateBackup(id: id)
        case "backup:restore":
            let path = (payload["path"] as? String) ?? ""
            handleRestore(id: id, from: URL(fileURLWithPath: path, isDirectory: true))
        case "backup:chooseAndRestore":
            handleChooseAndRestore(id: id)
        case "backup:reveal":
            let path = (payload["path"] as? String) ?? ""
            let url = path.isEmpty ? storage.backupsRoot : URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: storage.backupsRoot, withIntermediateDirectories: true)
            storage.revealInFinder(url)
            respondNull(id: id)
        case "backup:revealDataFolder":
            try? FileManager.default.createDirectory(at: storage.appRoot, withIntermediateDirectories: true)
            storage.revealInFinder(storage.appRoot)
            respondNull(id: id)

        case "documents:listForProject":
            let projectId = (payload["projectId"] as? String) ?? ""
            respond(id: id, encodable: db.listDocuments(projectId: projectId))
        case "documents:upload":
            let number = (payload["projectNumber"] as? String) ?? ""
            let category = (payload["category"] as? String) ?? "Miscellaneous"
            handleUploadDocument(id: id, projectNumber: number, category: category)
        case "documents:updateDescription":
            let documentId = (payload["id"] as? String) ?? ""
            let description = payload["description"] as? String
            let error = db.updateDocumentDescription(id: documentId, description: description)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "documents:rename":
            let documentId = (payload["id"] as? String) ?? ""
            let newName = (payload["newName"] as? String) ?? ""
            let error = db.renameDocument(id: documentId, newDisplayName: newName)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "documents:archive":
            let documentId = (payload["id"] as? String) ?? ""
            let error = db.archiveDocument(id: documentId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "documents:removeReference":
            let documentId = (payload["id"] as? String) ?? ""
            let error = db.removeDocumentReference(id: documentId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "documents:relink":
            let documentId = (payload["id"] as? String) ?? ""
            handleRelinkFile(id: id, recordId: documentId, target: .document)
        case "documents:open":
            let documentId = (payload["id"] as? String) ?? ""
            if let document = db.getDocument(id: documentId) {
                handleOpenFile(id: id, path: document.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Document not found."))
            }
        case "documents:reveal":
            let documentId = (payload["id"] as? String) ?? ""
            if let document = db.getDocument(id: documentId) {
                handleRevealFile(id: id, path: document.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Document not found."))
            }

        default:
            respondError(id: id, message: "Unknown action: \(action)")
        }
    }

    private func handleCreateBOQ(id: String, payload: [String: Any]) {
        let projectId = (payload["projectId"] as? String) ?? ""
        let projectNumber = (payload["projectNumber"] as? String) ?? ""
        let pricingMode = (payload["pricingMode"] as? String) ?? "Rental"
        guard !projectId.isEmpty, !projectNumber.isEmpty else {
            respondError(id: id, message: "Missing project.")
            return
        }
        let boq = db.createBOQ(projectId: projectId, projectNumber: projectNumber, pricingMode: pricingMode)
        respond(id: id, encodable: boq)
    }

    private func handleAddBOQLineItem(id: String, payload: [String: Any]) {
        let boqId = (payload["boqId"] as? String) ?? ""
        let sourceKey = payload["sourceKey"] as? String
        let priceListItemId = payload["priceListItemId"] as? String
        let itemCode = (payload["itemCode"] as? String) ?? ""
        let description = (payload["description"] as? String) ?? ""
        let unit = (payload["unit"] as? String) ?? "pc"
        let quantity = (payload["quantity"] as? Double) ?? 1
        let priceListUnitPrice = payload["priceListUnitPrice"] as? Double
        let appliedUnitPrice = (payload["appliedUnitPrice"] as? Double) ?? (priceListUnitPrice ?? 0)
        var weightKg = payload["weightKg"] as? Double
        let section = payload["section"] as? String
        var priceListUnitPriceFinal = priceListUnitPrice
        var appliedUnitPriceFinal = appliedUnitPrice
        // Items picked from the Material List are priced here, consistently:
        // this BOQ's Sale/Rental mode, its mark-up, converted to HKD.
        if let plId = priceListItemId, let pl = db.priceListItem(id: plId), let boq = db.getBOQ(id: boqId),
           let price = db.boqPrice(for: pl, mode: boq.pricingMode, markupPercent: boq.markupOnRates == true ? 0 : (boq.markupPercent ?? 0), rates: db.conversionRates()) {
            priceListUnitPriceFinal = price
            appliedUnitPriceFinal = price
            if weightKg == nil { weightKg = pl.weightKg }
        }

        guard !description.isEmpty else {
            respond(id: id, encodable: BOQActionResult(ok: false, error: "Description is required."))
            return
        }
        guard quantity > 0 else {
            respond(id: id, encodable: BOQActionResult(ok: false, error: "Quantity must be greater than zero."))
            return
        }

        if let error = db.addBOQLineItem(
            boqId: boqId, sourceKey: sourceKey, priceListItemId: priceListItemId,
            itemCode: itemCode, description: description, unit: unit, quantity: quantity,
            priceListUnitPrice: priceListUnitPriceFinal, appliedUnitPrice: appliedUnitPriceFinal, weightKg: weightKg, section: section
        ) {
            respond(id: id, encodable: BOQActionResult(ok: false, error: error))
        } else {
            respond(id: id, encodable: BOQActionResult(ok: true, error: nil))
        }
    }

    private func handleUpdatePriceListItem(id: String, payload: [String: Any]) {
        let itemId = (payload["id"] as? String) ?? ""
        let itemName = (payload["itemName"] as? String) ?? ""
        let category = payload["category"] as? String
        let unit = (payload["unit"] as? String) ?? ""
        let unitSalePrice = payload["unitSalePrice"] as? Double
        let unitRentalPrice = payload["unitRentalPrice"] as? Double

        if let error = db.updatePriceListItem(id: itemId, itemName: itemName, category: category, unit: unit, unitSalePrice: unitSalePrice, unitRentalPrice: unitRentalPrice,
                                              weightKg: payload["weightKg"] as? Double, updateWeight: payload.keys.contains("weightKg"),
                                              chineseName: payload["chineseName"] as? String) {
            respond(id: id, encodable: PriceListItemActionResult(ok: false, error: error))
        } else {
            respond(id: id, encodable: PriceListItemActionResult(ok: true, error: nil))
        }
    }

    private func handleCreateQuotation(id: String, payload: [String: Any]) {
        let projectId = (payload["projectId"] as? String) ?? ""
        let projectNumber = (payload["projectNumber"] as? String) ?? ""
        let sourceBOQId = payload["boqId"] as? String
        let pricingMode = (payload["pricingMode"] as? String) ?? "Rental"
        guard !projectId.isEmpty, !projectNumber.isEmpty else {
            respondError(id: id, message: "Missing project.")
            return
        }
        let quotation = db.createQuotation(projectId: projectId, projectNumber: projectNumber, sourceBOQId: sourceBOQId, pricingMode: pricingMode)
        respond(id: id, encodable: quotation)
    }

    private func handleAddQuotationLineItem(id: String, payload: [String: Any]) {
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

    private func handleUpdateQuotationHeader(id: String, payload: [String: Any]) {
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

    private func handleCreateInvoice(id: String, payload: [String: Any]) {
        let projectId = (payload["projectId"] as? String) ?? ""
        let projectNumber = (payload["projectNumber"] as? String) ?? ""
        guard !projectId.isEmpty, !projectNumber.isEmpty else {
            respondError(id: id, message: "Missing project.")
            return
        }
        switch db.createInvoice(projectId: projectId, projectNumber: projectNumber,
                                sourceQuotationId: (payload["quotationId"] as? String) ?? "",
                                rentalMonths: payload["rentalMonths"] as? Int,
                                includeDelivery: (payload["includeDelivery"] as? Bool) ?? true,
                                includeOtherCharges: (payload["includeOtherCharges"] as? Bool) ?? true) {
        case .success(let invoice): respond(id: id, encodable: invoice)
        case .failure(let e): respondError(id: id, message: e.message)
        }
    }

    private func handleAddInvoiceLineItem(id: String, payload: [String: Any]) {
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

    private func handleUpdateInvoiceHeader(id: String, payload: [String: Any]) {
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

    private func handleCreateDeliveryNote(id: String, payload: [String: Any]) {
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

    private func handleAddDeliveryNoteLineItem(id: String, payload: [String: Any]) {
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

    private func handleUpdateDeliveryNoteHeader(id: String, payload: [String: Any]) {
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
    /// Saves a CSV the Accounts or Stock page made into Administration/
    /// Accounts, and opens it (Numbers or Excel).
    private func handleSaveAccountsCSV(id: String, payload: [String: Any]) {
        let name = ((payload["fileName"] as? String) ?? "").replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        guard name.hasSuffix(".csv"), !name.hasPrefix("."), let csv = payload["csv"] as? String else {
            respond(id: id, encodable: SimpleResult(ok: false, error: "The file couldn't be saved."))
            return
        }
        let folder = storage.administrationCategoryFolder("Accounts")
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = folder.appendingPathComponent(name)
            // With a byte-order mark, so Excel reads the text as UTF-8.
            try Data(("\u{FEFF}" + csv).utf8).write(to: destination, options: .atomic)
            NSWorkspace.shared.open(destination)
            respond(id: id, encodable: SimpleResult(ok: true, error: nil))
        } catch {
            respond(id: id, encodable: SimpleResult(ok: false, error: "The file couldn't be saved: \(error.localizedDescription)"))
        }
    }

    /// Saves a Word copy built by the page (js/docx-export.js) into the
    /// project's folder next to its PDF, and opens it.
    private func handleSaveWord(id: String, payload: [String: Any]) {
        let projectNumber = (payload["projectNumber"] as? String) ?? ""
        let subfolder = (payload["subfolder"] as? String) ?? ""
        let fileName = ((payload["fileName"] as? String) ?? "").replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        guard !projectNumber.isEmpty, db.getProjectByNumber(projectNumber) != nil,
              ["BOQ", "Quotations", "Invoices", "Delivery Notes"].contains(subfolder),
              fileName.hasSuffix(".docx"), !fileName.hasPrefix("."),
              let data = Data(base64Encoded: (payload["data"] as? String) ?? ""), !data.isEmpty else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "The Word document couldn't be saved.", path: nil))
            return
        }
        do {
            let destination = try storage.writeGeneratedFile(data: data, projectNumber: projectNumber, subfolder: subfolder, meaningfulFilename: fileName)
            NSWorkspace.shared.open(destination)
            if let project = db.getProjectByNumber(projectNumber) {
                db.logActivity(projectId: project.id, "Word document exported", reference: destination.lastPathComponent)
            }
            respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: destination.path))
        } catch {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "The Word document couldn't be saved to the project folder. Please check there's free disk space and try again.", path: nil))
        }
    }

    private func deliverRenderedPDF(id: String, mode: PDFMode, company: CompanySettings, projectNumber: String, subfolder: String, documentNumber: String, docTypeTag: String, letter: LetterDocument,
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
            layout.fileName = "\(projectNumber)_\(docTypeTag)_\(safeNumber).docx"
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
    private func deliverPDF(id: String, mode: PDFMode, data original: Data, paperSize: NSSize, projectNumber: String, subfolder: String, documentNumber: String, docTypeTag: String,
                            attachments: [URL] = []) {
        let safeNumber = documentNumber.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        let data = PDFAttachments.append(attachments, to: original, paperSize: paperSize)
        if mode == .print {
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

        let filename = "\(projectNumber)_\(docTypeTag)_\(safeNumber).pdf"
        do {
            let destination = try storage.writeGeneratedFile(data: data, projectNumber: projectNumber, subfolder: subfolder, meaningfulFilename: filename)
            db.recordGeneratedPDF(docTypeTag: docTypeTag, documentNumber: documentNumber, path: destination.path)
            NSWorkspace.shared.open(destination)
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
    private func documentFile(kind: String, documentId: String) -> (file: URL?, folder: URL, number: String)? {
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
        let folder = storage.projectFolder(project.projectNumber).appendingPathComponent(subfolder, isDirectory: true)
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
    private func isCombinedExport(_ name: String) -> Bool {
        ["_Quotations_", "_BOQs_", "_Invoices_", "_Delivery Notes_"].contains { name.contains($0) }
    }

    /// "Locate File": shows a document's file in Finder — or, if it hasn't
    /// been exported yet, the folder it will be saved in.
    private func handleLocateDocument(id: String, kind: String, documentId: String) {
        struct LocateResult: Encodable { var ok: Bool; var error: String?; var note: String? }
        guard let found = documentFile(kind: kind, documentId: documentId) else {
            respond(id: id, encodable: LocateResult(ok: false, error: "Document not found.", note: nil))
            return
        }
        if let file = found.file {
            storage.revealInFinder(file)
            respond(id: id, encodable: LocateResult(ok: true, error: nil, note: nil))
            return
        }
        try? FileManager.default.createDirectory(at: found.folder, withIntermediateDirectories: true)
        storage.revealInFinder(found.folder)
        respond(id: id, encodable: LocateResult(ok: true, error: nil,
                                               note: "\(found.number) hasn't been exported as a PDF or Word file yet, so Finder shows the folder it will be saved in."))
    }

    /// "Locate Files" for several documents: one Finder window with all
    /// their files selected. Says which haven't been exported yet.
    private func handleLocateDocuments(id: String, kind: String, ids: [String]) {
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
            storage.revealInFinder(folder)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        }
        let note = missing.isEmpty ? nil
            : "\(missing.joined(separator: ", ")) \(missing.count == 1 ? "hasn't" : "haven't") been exported as a PDF or Word file yet\(files.isEmpty ? ", so Finder shows the folder they'll be saved in" : "")."
        respond(id: id, encodable: LocateResult(ok: true, error: nil, note: note))
    }

    // MARK: Documents in the letterhead layout (from Qt26193)

    /// "HK$" for Hong Kong dollars (as on the original), otherwise the code.
    private func currencySymbol(_ company: CompanySettings) -> String {
        company.currency == "HKD" ? "HK$" : company.currency
    }

    /// "22 Sep 2026", as on the original.
    private func letterDate(_ iso: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "d MMM yyyy"
        if let date = isoFormatter.date(from: iso) ?? isoFromDay(iso).flatMap({ isoFormatter.date(from: $0) }) {
            return formatter.string(from: date)
        }
        return iso
    }

    /// The client block at the top left: company name, then the billing
    /// information (or address), then "Attn:" if there's a contact.
    private func clientBlock(projectNumber: String, fallbackName: String?) -> (name: String, lines: [String]) {
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
    private func clientBlock(_ c: Client) -> (name: String, lines: [String]) {
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

    /// "Unit Rates" for a client: chosen items from the material lists
    /// (either or both), laid out like a quotation, with each item's unit
    /// weight and monthly rental (with the markup chosen) and no list
    /// names. Saved in the company folder's "Unit Rates" folder and opened.
    private func handleExportUnitRates(id: String, payload: [String: Any]) {
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
        let rows: [LetterTableRow] = items.enumerated().map { index, item in
            let weight = item.weightKg.map { String(format: "%.2f", $0) } ?? "—"
            let rental = item.unitRentalPrice.map { formatMoney(markedUpPrice($0, markupPercent: markup, roundUp: roundUp)) } ?? "—"
            return .item(["\(index + 1)", item.itemName, weight, rental, item.unit])
        }
        let columns = [
            LetterColumn(title: "No.", width: 29.25, kind: .center),
            LetterColumn(title: "Item Description", width: 219.75, kind: .left),
            LetterColumn(title: "Unit Weight (kg)", width: 86.0, kind: .right),
            LetterColumn(title: "Unit Monthly Rental", width: 117.0, kind: .money),
            LetterColumn(title: "Unit", width: 55.0, kind: .center),
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
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            var url = folder.appendingPathComponent("\(base).pdf")
            var n = 2
            while FileManager.default.fileExists(atPath: url.path) {
                url = folder.appendingPathComponent("\(base) (\(n)).pdf")
                n += 1
            }
            try data.write(to: url, options: .atomic)
            NSWorkspace.shared.open(url)
            respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: url.path))
        } catch {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "The PDF couldn't be saved: \(error.localizedDescription)", path: nil))
        }
    }

    /// The site's own reference, or its name.
    private func siteReference(projectNumber: String) -> String {
        guard let project = db.getProjectByNumber(projectNumber), let site = db.getSite(id: project.siteId) else { return "" }
        return nonBlank(site.siteReference) ?? site.name
    }

    /// "For and on Behalf of" the company, with the signatory from Settings.
    private func companySignature(_ company: CompanySettings) -> LetterSignature {
        var lines = [LetterSignatureLine(text: company.companyName)]
        if let name = nonBlank(company.signatoryName) { lines.append(LetterSignatureLine(text: name)) }
        if let title = nonBlank(company.signatoryTitle) { lines.append(LetterSignatureLine(text: title)) }
        return LetterSignature(heading: "For and on Behalf of", lines: lines)
    }

    private func remarks(_ notes: String?) -> [LetterSection] {
        guard let notes = nonBlank(notes) else { return [] }
        return [LetterSection(heading: "Remarks", paragraphs: [.text(notes, link: nil)])]
    }

    /// The numbered terms from Settings: a line starting "(" begins a term
    /// ("(i) Payment : …"); other lines continue the one above.
    /// Materials numbered 1, 2, 3…; lines in the "Delivery" section go
    /// under a "Delivery Charges" heading, numbered D1, D2… (as on Qt26193).
    /// A line's own discount is printed under its description ("Less 10%
    /// discount") and its Total Price is net of it.
    private func pricedRows(_ lines: [(description: String, unit: String, quantity: Double, price: Double, isDelivery: Bool, discountType: String?, discountValue: Double?)],
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
    private func blockRows(_ block: QuotationBlock, _ detail: QuotationDetail, currency: String) -> [LetterTableRow] {
        var rows: [LetterTableRow] = []
        // A section charged per day / week / month says so in its title.
        let per = block.kind == "Priced" ? block.chargePeriod.map { " (per \($0.lowercased()))" } ?? "" : ""
        if let title = nonBlank(block.title) { rows.append(.section(title + per)) } else if !per.isEmpty { rows.append(.section("Charged\(per)")) }
        let lines = detail.lineItems.filter { $0.blockId == block.id }.sorted { $0.sortOrder < $1.sortOrder }
        for (i, line) in lines.enumerated() {
            let number = "\(block.prefix)\(i + 1)"
            let unit = line.unit.trimmingCharacters(in: .whitespaces)
            if block.kind == "Rates" {
                rows.append(.partial([number, line.itemDescription, "\(formatMoney(line.appliedUnitPrice))\(unit.isEmpty ? "" : " / \(unit)")"],
                                     tail: "(Rate Only)"))
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

    private let pricedColumns = [
        LetterColumn(title: "No", width: 29.25, kind: .center),
        LetterColumn(title: "Item Description", width: 219.75, kind: .left),
        LetterColumn(title: "Unit Rate", width: 110.25, kind: .money),
        LetterColumn(title: "Qty", width: 39.0, kind: .center),
        LetterColumn(title: "Total Price", width: 108.75, kind: .money),
    ]

    /// Landscape: the BOQ as the company's BQ sheet ("PROFICIENCY
    /// QUOTATION"), with prices. Portrait: on the letterhead, with weights
    /// and no prices (`exportBOQOnLetterhead`).
    private func handleExportBOQPDF(id: String, boqId: String, mode: PDFMode = .export) {
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
            layout.fileName = "\(detail.projectNumber)_BOQ_\(safeNumber).docx"
            respond(id: id, encodable: layout)
            return
        }
        guard let data = BQSheetRenderer.pdf(layout) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Could not prepare the document.", path: nil))
            return
        }
        deliverPDF(id: id, mode: mode, data: data, paperSize: NSSize(width: layout.pageWidth, height: layout.pageHeight),
                   projectNumber: detail.projectNumber, subfolder: "BOQ", documentNumber: detail.boqNumber, docTypeTag: "BOQ",
                   attachments: db.appendedDrawingFiles(kind: "BOQ", id: detail.id))
    }

    /// The landscape BQ sheet ("PROFICIENCY QUOTATION") for a BOQ.
    private func boqSheetLayout(_ detail: BOQDetail) -> SheetLayout {
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
        // Materials' Chinese names follow the English ones.
        let zh = db.chineseNamesOnDocuments
            ? db.chineseNames(for: detail.lineItems, id: { $0.id }, itemId: { $0.priceListItemId }, description: { $0.itemDescription }) : [:]
        let lines = detail.lineItems.map { line -> BOQLineItem in
            var copy = line
            copy.appliedUnitPrice = detail.effectiveRates[line.id] ?? line.appliedUnitPrice
            copy.itemDescription = withChineseName(line.itemDescription, zh[line.id])
            return copy
        }
        return BQSheet.layout(
            landscape: true, pricingMode: detail.pricingMode, currencyCode: company.currency,
            info: (projectCode: projectCode, client: clientName, jobSite: jobSite, structure: detail.structure ?? ""),
            lines: lines, grandTotal: detail.grandTotal, totalWeightKg: detail.totalWeightKg,
            ratesSection: detail.ratesSection, charges: detail.charges ?? [], notes: detail.notes,
            terms: detail.terms,
            signature: detail.signatureSection
                ? (company: company.companyName, name: company.signatoryName ?? "", title: company.signatoryTitle ?? "",
                   client: client?.companyName ?? "") : nil)
    }

    /// A BOQ's own pages as a PDF (landscape sheet or portrait letterhead,
    /// as the BOQ is set), without its drawings: for the quotation that
    /// follows it.
    private func boqPDFData(_ detail: BOQDetail) -> Data? {
        if detail.orientation == "Portrait" {
            return PDFGenerator(paperSize: db.getCompanySettings().paperSize ?? "A4")?.generate(boqLetter(detail))
        }
        return BQSheetRenderer.pdf(boqSheetLayout(detail))
    }

    /// The BOQ a quotation follows, written to a temporary PDF so it can be
    /// added after the quotation's pages like a drawing.
    private func followedBOQFile(_ quotation: QuotationDetail) -> URL? {
        guard let boqId = db.getQuotation(id: quotation.id)?.sourceBOQId, let boq = db.getBOQDetail(id: boqId),
              !boq.lineItems.isEmpty, let data = boqPDFData(boq) else { return nil }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ScaffoldPro-\(boq.id).pdf")
        return (try? data.write(to: url)) != nil ? url : nil
    }

    /// The portrait BOQ: the letterhead layout (from Qt26193) with each
    /// item's unit, quantity and weights, and the total weight.
    private func exportBOQOnLetterhead(id: String, detail: BOQDetail, mode: PDFMode) {
        deliverRenderedPDF(id: id, mode: mode, company: db.getCompanySettings(), projectNumber: detail.projectNumber, subfolder: "BOQ",
                           documentNumber: detail.boqNumber, docTypeTag: "BOQ", letter: boqLetter(detail),
                           attachments: db.appendedDrawingFiles(kind: "BOQ", id: detail.id))
    }

    private func boqLetter(_ detail: BOQDetail) -> LetterDocument {
        let company = db.getCompanySettings()
        let client = clientBlock(projectNumber: detail.projectNumber, fallbackName: nil)
        let columns = [
            LetterColumn(title: "No", width: 29.25, kind: .center),
            LetterColumn(title: "Item Description", width: 219.75, kind: .left),
            LetterColumn(title: "Unit", width: 50.0, kind: .center),
            LetterColumn(title: "Qty", width: 50.0, kind: .center),
            LetterColumn(title: "Unit Wt (kg)", width: 75.0, kind: .right),
            LetterColumn(title: "Total Wt (kg)", width: 83.0, kind: .right),
        ]
        let zh = db.chineseNamesOnDocuments
            ? db.chineseNames(for: detail.lineItems, id: { $0.id }, itemId: { $0.priceListItemId }, description: { $0.itemDescription }) : [:]
        var rows: [LetterTableRow] = detail.lineItems.enumerated().map { index, item in
            .item([String(index + 1), lineDescription(withChineseName(item.itemDescription, zh[item.id]), notes: item.notes), item.unit, formatQuantity(item.quantity),
                   item.weightKg.map { formatMoney($0) } ?? "—",
                   item.weightKg.map { formatMoney($0 * item.quantity.rounded()) } ?? "—"])
        }
        rows.append(.summary(label: "Total Weight:", value: "\(formatMoney(detail.totalWeightKg)) kg", emphasized: true))

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

    private func handleExportQuotationPDF(id: String, quotationId: String, mode: PDFMode = .export) {
        guard let detail = db.getQuotationDetail(id: quotationId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Quotation not found.", path: nil))
            return
        }
        let company = db.getCompanySettings()
        let letter = quotationLetter(detail, company: company)
        deliverRenderedPDF(id: id, mode: mode, company: company, projectNumber: detail.projectNumber, subfolder: "Quotations",
                           documentNumber: detail.quotationNumber, docTypeTag: "Quotation", letter: letter,
                           attachments: mode == .word ? [] : quotationAttachments(detail))
    }

    /// Everything added after a quotation's own pages: the BOQ it follows,
    /// then its image and PDF drawings.
    private func quotationAttachments(_ detail: QuotationDetail) -> [URL] {
        [followedBOQFile(detail)].compactMap { $0 } + db.appendedDrawingFiles(kind: "Quotation", id: detail.id)
    }

    /// A quotation laid out on the letterhead (as Qt26193).
    private func quotationLetter(_ detail: QuotationDetail, company: CompanySettings) -> LetterDocument {
        let isRental = detail.pricingMode == "Rental"
        let client = clientBlock(projectNumber: detail.projectNumber, fallbackName: detail.clientName)

        // Unit prices as charged: with the quotation's markup, if any.
        let priced = pricedRows(detail.lineItems.filter { $0.blockId == nil }.map { (description: $0.itemDescription, unit: $0.unit, quantity: $0.quantity,
                                                         price: detail.effectiveUnitPrices[$0.id] ?? $0.appliedUnitPrice, isDelivery: $0.section == "Delivery",
                                                         discountType: $0.discountType, discountValue: $0.discountValue) },
                                currency: currencySymbol(company), rateSuffix: { _ in isRental ? " /Month" : "" })
        var rows = priced.materials
        if isRental {
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
            signatures: [
                companySignature(company),
                LetterSignature(heading: "For and on Behalf of", lines: [
                    LetterSignatureLine(text: client.name),
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
    private func handleCombineDocuments(id: String, kind: String, ids: [String], includeDrawings: Bool) {
        let company = db.getCompanySettings()
        let paper = company.paperSize ?? "A4"
        let paperSize = paper == "Letter" ? NSSize(width: 612, height: 792) : NSSize(width: 595.28, height: 841.89)
        // Each document: its number, project, and its pages (with drawings).
        var parts: [(number: String, projectNumber: String, data: Data)] = []
        for docId in ids {
            if kind == "BOQ" {
                guard let detail = db.getBOQDetail(id: docId), var data = boqPDFData(detail) else { continue }
                if includeDrawings { data = PDFAttachments.append(db.appendedDrawingFiles(kind: "BOQ", id: detail.id), to: data, paperSize: paperSize) }
                parts.append((detail.boqNumber, detail.projectNumber, data))
            } else if kind == "Invoice" {
                guard let detail = db.getInvoiceDetail(id: docId), let generator = PDFGenerator(paperSize: paper) else { continue }
                parts.append((detail.invoiceNumber, detail.projectNumber, generator.generate(invoiceLetter(detail, company: company))))
            } else if kind == "DeliveryNote" {
                guard let detail = db.getDeliveryNoteDetail(id: docId), let note = db.getDeliveryNote(id: docId),
                      let generator = PDFGenerator(paperSize: paper) else { continue }
                parts.append((detail.deliveryNoteNumber, detail.projectNumber, generator.generate(deliveryNoteLetter(detail, note: note, company: company))))
            } else {
                guard let detail = db.getQuotationDetail(id: docId), let generator = PDFGenerator(paperSize: paper) else { continue }
                var data = generator.generate(quotationLetter(detail, company: company))
                if includeDrawings { data = PDFAttachments.append(quotationAttachments(detail), to: data, paperSize: paperSize) }
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
        do {
            let destination = try storage.writeGeneratedFile(data: data, projectNumber: first.projectNumber, subfolder: subfolder, meaningfulFilename: filename)
            NSWorkspace.shared.open(destination)
            if let project = db.getProjectByNumber(first.projectNumber) {
                db.logActivity(projectId: project.id, "\(label) exported as one PDF", reference: destination.lastPathComponent)
            }
            respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: destination.path))
        } catch {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "The PDF couldn't be saved to the project folder. Please check there's free disk space and try again.", path: nil))
        }
    }

    private func handleExportInvoicePDF(id: String, invoiceId: String, mode: PDFMode = .export) {
        guard let detail = db.getInvoiceDetail(id: invoiceId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Invoice not found.", path: nil))
            return
        }
        let company = db.getCompanySettings()
        deliverRenderedPDF(id: id, mode: mode, company: company, projectNumber: detail.projectNumber, subfolder: "Invoices",
                           documentNumber: detail.invoiceNumber, docTypeTag: "Invoice", letter: invoiceLetter(detail, company: company))
    }

    /// An invoice laid out on the letterhead.
    private func invoiceLetter(_ detail: InvoiceDetail, company: CompanySettings) -> LetterDocument {
        let client = clientBlock(projectNumber: detail.projectNumber, fallbackName: detail.clientName)
        let isRental = detail.pricingMode == "Rental"
        let quotation = detail.sourceQuotationId.flatMap { db.getQuotation(id: $0) }

        let priced = pricedRows(detail.lineItems.filter { $0.chargeGroup == nil }.map { (description: $0.itemDescription, unit: $0.unit, quantity: $0.quantity,
                                                         price: $0.appliedUnitPrice, isDelivery: $0.section == "Delivery",
                                                         discountType: $0.discountType, discountValue: $0.discountValue) },
                                currency: currencySymbol(company),
                                rateSuffix: { unit in isRental ? " /Month" : (unit.isEmpty || unit == "pc" ? "" : " /\(unit)") })
        var rows = priced.materials
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
        rows.append(.summary(label: "Total Amount:", value: formatMoney(detail.total), emphasized: true))
        if detail.amountPaid > 0 {
            rows.append(.summary(label: "Less Amount Paid:", value: "-\(formatMoney(detail.amountPaid))", emphasized: false))
            rows.append(.summary(label: "Balance Due:", value: formatMoney(detail.balanceDue), emphasized: true))
        }

        var payment: [LetterParagraph] = []
        if let terms = nonBlank(detail.paymentTerms) { payment += paymentTermParagraphs(terms, label: "Payment Terms") }
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
    private func handleExportDeliveryNotePDF(id: String, deliveryNoteId: String, mode: PDFMode = .export) {
        guard let detail = db.getDeliveryNoteDetail(id: deliveryNoteId), let note = db.getDeliveryNote(id: deliveryNoteId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Delivery note not found.", path: nil))
            return
        }
        let company = db.getCompanySettings()
        deliverRenderedPDF(id: id, mode: mode, company: company, projectNumber: detail.projectNumber, subfolder: "Delivery Notes",
                           documentNumber: detail.deliveryNoteNumber, docTypeTag: "DeliveryNote",
                           letter: deliveryNoteLetter(detail, note: note, company: company))
    }

    /// A delivery note laid out on the letterhead (as DN26038a).
    private func deliveryNoteLetter(_ detail: DeliveryNoteDetail, note: DeliveryNote, company: CompanySettings) -> LetterDocument {
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

        let columns = [
            LetterColumn(title: "No", width: 29.25, kind: .center),
            LetterColumn(title: "Item Description", width: 290.75, kind: .left),
            LetterColumn(title: "Unit Weight", width: 75.0, kind: .weight),
            LetterColumn(title: "Qty", width: 39.0, kind: .center),
            LetterColumn(title: "Total Weight", width: 76.0, kind: .weight),
        ]
        let priceItems = db.allPriceListItems()
        // Chinese names too, for the workers who read Chinese.
        let zh = db.chineseNamesOnDocuments
            ? db.chineseNames(for: detail.lineItems, id: { $0.id }, itemId: { $0.priceListItemId }, description: { $0.itemDescription }) : [:]
        var totalKg = Decimal(0)
        var rows: [LetterTableRow] = detail.lineItems.enumerated().map { index, item in
            let qty = item.quantity.rounded()
            let kg = db.deliveryNoteWeight(item, in: priceItems)
            if let kg = kg { totalKg += decimalOf(kg) * decimalOf(qty) }
            return .item([String(index + 1), lineDescription(withChineseName(item.itemDescription, zh[item.id]), notes: item.notes),
                          kg.map { String(format: "%.1f", $0) } ?? "", formatQuantity(qty),
                          kg.map { String(format: "%.1f", $0 * qty) } ?? ""])
        }
        if !rows.isEmpty {
            let formatter = NumberFormatter()
            formatter.numberStyle = .decimal
            formatter.minimumFractionDigits = 1
            formatter.maximumFractionDigits = 1
            let total = formatter.string(from: NSDecimalNumber(decimal: totalKg)) ?? String(format: "%.1f", doubleOf(totalKg))
            rows.append(.summary(label: "Total Weight:", value: total, emphasized: false))
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
    private func handleChangeProjectNumber(id: String, projectId: String, newNumber raw: String) {
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
        respond(id: id, encodable: SimpleResult(ok: true, error: nil))
    }

    private func projectListEntries() -> [ProjectListEntry] {
        // All clients/sites, including archived ones, so older projects
        // still show who they belong to.
        let clients = db.allClients()
        let sites = db.allSites()
        return db.listProjectsRaw().map { p in
            ProjectListEntry(
                id: p.id, projectNumber: p.projectNumber, name: p.name,
                clientId: p.clientId, siteId: p.siteId, status: p.status, createdAt: p.createdAt,
                clientName: clients.first { $0.id == p.clientId }?.companyName,
                siteName: sites.first { $0.id == p.siteId }?.name
            )
        }
    }

    private func handleCreateProject(id: String, payload: [String: Any]) {
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

    private func handleGetProject(id: String, payload: [String: Any]) {
        let number = (payload["projectNumber"] as? String) ?? ""
        guard let project = db.getProjectByNumber(number) else {
            respondNull(id: id)
            return
        }
        let detail = ProjectDetail(
            id: project.id, projectNumber: project.projectNumber, name: project.name, status: project.status,
            projectDescription: project.projectDescription, startDate: project.startDate,
            expectedCompletionDate: project.expectedCompletionDate, projectManager: project.projectManager,
            internalNotes: project.internalNotes, createdAt: project.createdAt,
            client: db.getClient(id: project.clientId), site: db.getSite(id: project.siteId)
        )
        respond(id: id, encodable: detail)
    }

    /// Adds each file chosen in an upload panel. Replies with everything
    /// added; if some couldn't be copied, the rest are still added and the
    /// reply is an error naming the ones that failed.
    private func addEachFile<T: Encodable>(id: String, urls: [URL], add: (URL) throws -> T) {
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

    private func handleUploadDrawing(id: String, projectNumber: String, linkedKind: String?, linkedId: String?) {
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
        panel.message = "Choose one or more drawings: PDF, DWG, DXF or images. The originals stay where they are; copies go in the project's Drawings folder."

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
    private func addDrawingFile(_ sourceURL: URL, project: Project, linkedKind: String?, linkedId: String?) throws -> UploadDrawingResult {
        let originalName = sourceURL.lastPathComponent
        let destination = try storage.copyFileIntoProject(
            source: sourceURL, projectNumber: project.projectNumber,
            subfolder: "Drawings", meaningfulFilename: "\(project.projectNumber)_Drawing_\(originalName)"
        )
        db.recordDrawing(projectId: project.id, originalName: originalName, storedURL: destination, linkedKind: linkedKind, linkedId: linkedId)
        return UploadDrawingResult(originalName: originalName, destination: destination.path)
    }

    /// Copies a document into the project's Documents folder and records it.
    private func addDocumentFile(_ sourceURL: URL, project: Project, category: String) throws -> ProjectDocument {
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
    private func handleDroppedProjectFiles(id: String, payload: [String: Any]) {
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

    private func handleUploadDocument(id: String, projectNumber: String, category: String) {
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
    private enum RelinkTarget {
        case drawing, document, workerDocument, adminDocument
    }

    private func handleRelinkFile(id: String, recordId: String, target: RelinkTarget) {
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
    private func handleUploadWorkerDocument(id: String, workerId: String, category: String, expiryDate: String?) {
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
    private func handleUploadAdminDocument(id: String, category: String, expiryDate: String?) {
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
    func applyAppearance(_ value: String?) {
        switch value {
        case "Light": NSApp.appearance = NSAppearance(named: .aqua)
        case "Dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }

    private func handleChooseLogo(id: String) {
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

    private func handlePriceImportPreview(id: String, sourceKey: String) {
        guard let window = window else { respondNull(id: id); return }
        guard let list = db.listPriceLists().first(where: { $0.sourceKey == sourceKey }) else {
            respond(id: id, encodable: PriceImportPreview(ok: false, error: "Price list not found.", token: nil, fileName: nil, sheetName: nil, mapping: [], rowsFound: 0, toAdd: 0, toUpdate: 0, samples: []))
            return
        }
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [UTType(filenameExtension: "xlsx"), .commaSeparatedText].compactMap { $0 }
        panel.message = "Choose an Excel (.xlsx) or CSV file to update “\(list.displayName)”."
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

    private func handlePriceImportApply(id: String, token: String) {
        guard let pending = pendingPriceImport, pending.token == token else {
            respond(id: id, encodable: PriceImportResult(ok: false, error: "This import has expired — please choose the file again.", added: 0, updated: 0))
            return
        }
        pendingPriceImport = nil
        let counts = db.applyPriceImport(sourceKey: pending.sourceKey, rows: pending.rows, apply: true)
        respond(id: id, encodable: PriceImportResult(ok: true, error: nil, added: counts.added, updated: counts.updated))
    }

    /// Section 49: export a price list to CSV (opens in Excel/Numbers).
    /// Unlike documents, the export keeps the item code — it's what lets
    /// an edited copy be imported back and matched to the right items.
    private func handlePriceExportCSV(id: String, sourceKey: String) {
        guard let window = window, let list = db.listPriceLists().first(where: { $0.sourceKey == sourceKey }) else { respondNull(id: id); return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "\(list.displayName.replacingOccurrences(of: "/", with: "-")).csv"
        panel.directoryURL = storage.appRoot
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let url = panel.url else { self.respondNull(id: id); return }
            func csv(_ value: String) -> String {
                value.contains(",") || value.contains("\"") || value.contains("\n") ? "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : value
            }
            func num(_ v: Double?) -> String { v.map { String(format: "%.2f", $0) } ?? "" }
            var lines = ["Item Code,Category,Item,Unit,Weight (kg),Sale Price (\(list.currency)),Rental Price (\(list.currency))"]
            for item in self.db.allPriceListItems(sourceKey: sourceKey) {
                lines.append([csv(item.itemCode), csv(item.category ?? ""), csv(item.itemName), csv(item.unit),
                              num(item.weightKg), num(item.unitSalePrice), num(item.unitRentalPrice)].joined(separator: ","))
            }
            do {
                // UTF-8 with a byte-order mark so Excel shows symbols correctly.
                try Data(("\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n").utf8).write(to: url, options: .atomic)
                self.storage.revealInFinder(url)
                self.respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            } catch {
                self.respond(id: id, encodable: SimpleResult(ok: false, error: "The file couldn't be saved there."))
            }
        }
    }

    // MARK: Backup & Restore (Phase 14)

    /// Copying a few gigabytes of drawings must not freeze the window
    /// (section 55), so the work runs on a background queue and only the
    /// reply to the page hops back to the main thread.
    /// Picks the folder for the automatic iCloud backup (starting in
    /// iCloud Drive), then backs up into it straight away.
    private func handleChooseCloudFolder(id: String) {
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
    // scheduled backups older than a week are deleted. On APFS the copies
    // are clones, so unchanged files take no extra disk space.

    private var scheduleTimer: Timer?
    private var attemptedSlot: Date?
    private static let lastScheduledKey = "backup.scheduled.lastSlot"

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

    private func runScheduledBackupIfDue() {
        let slot = NativeBridge.latestBackupSlot()
        let done = UserDefaults.standard.double(forKey: NativeBridge.lastScheduledKey)
        guard done < slot.timeIntervalSince1970, attemptedSlot != slot, !backupInProgress else { return }
        attemptedSlot = slot
        backupInProgress = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let made = (try? self.backups.createBackup(kind: "Scheduled")) != nil
            if made { self.backups.deleteOldScheduledBackups(olderThanDays: 7) }
            DispatchQueue.main.async {
                self.backupInProgress = false
                if made {
                    UserDefaults.standard.set(slot.timeIntervalSince1970, forKey: NativeBridge.lastScheduledKey)
                    self.db.logActivity(projectId: nil, "Automatic backup made")
                }
            }
        }
    }

    private func handleCreateBackup(id: String) {
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

    private func handleRestore(id: String, from folder: URL) {
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
    private func handleChooseAndRestore(id: String) {
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
    private func handleReplaceFile(id: String, recordId: String, isDrawing: Bool) {
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
                    let superseded = self.storage.projectFolder(project.projectNumber)
                        .appendingPathComponent("Other", isDirectory: true)
                        .appendingPathComponent("Superseded", isDirectory: true)
                    _ = try self.storage.copyFile(source: URL(fileURLWithPath: oldPath), into: superseded,
                                                  meaningfulFilename: URL(fileURLWithPath: oldPath).lastPathComponent)
                    try fm.removeItem(atPath: oldPath)
                }
                let subfolder = isDrawing ? "Drawings" : "Documents"
                let name = "\(project.projectNumber)_\(isDrawing ? "Drawing" : "Document")_\(source.lastPathComponent)"
                let dest = try self.storage.copyFileIntoProject(source: source, projectNumber: project.projectNumber, subfolder: subfolder, meaningfulFilename: name)
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
    private func handleOpenFile(id: String, path: String) {
        whenDownloaded(path) { [weak self] here in
            guard let self = self else { return }
            guard here else {
                self.respond(id: id, encodable: FileActionResult(ok: false, error: fileIsPresent(path)
                    ? "This file is still downloading from iCloud. Try again in a moment."
                    : "This file could not be found. It may have been moved or deleted."))
                return
            }
            NSWorkspace.shared.open(URL(fileURLWithPath: path))
            self.respond(id: id, encodable: FileActionResult(ok: true, error: nil))
        }
    }

    private func handleRevealFile(id: String, path: String) {
        guard fileIsPresent(path) else {
            respond(id: id, encodable: FileActionResult(ok: false, error: "This file could not be found. It may have been moved or deleted."))
            return
        }
        storage.revealInFinder(URL(fileURLWithPath: path))
        respond(id: id, encodable: FileActionResult(ok: true, error: nil))
    }

    // MARK: Team sharing

    /// Set at launch when sharing is on but its folder couldn't be used.
    var teamFolderMissing = false

    private func teamStatus() -> TeamStatus {
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
    private func handleStartTeam(id: String) {
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
    private func handleJoinTeam(id: String) {
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
    private static let signedCopyTypes: [UTType] = [.pdf, .jpeg, .png, .heic, .tiff]

    /// Saves the client's signed copy as "<Qt number> - Signed.<ext>" in
    /// the project's Quotations folder and records it on the quotation.
    /// `write` puts the file at the URL it's given.
    private func storeSignedQuotation(quotationId: String, fileName: String, write: (URL) throws -> Void) -> SimpleResult {
        guard let q = db.getQuotation(id: quotationId), let project = db.getProject(id: q.projectId) else {
            return SimpleResult(ok: false, error: "Quotation not found.")
        }
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        guard let type = UTType(filenameExtension: ext), NativeBridge.signedCopyTypes.contains(where: { type.conforms(to: $0) }) else {
            return SimpleResult(ok: false, error: "Use a PDF, or a photo or scan (JPEG, PNG, HEIC or TIFF), of the signed quotation.")
        }
        let folder = storage.projectFolder(project.projectNumber).appendingPathComponent("Quotations", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let safe = q.quotationNumber.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            let destination = storage.uniqueDestination(folder.appendingPathComponent("\(safe) - Signed.\(ext)"))
            try write(destination)
            if let error = db.setQuotationSignedCopy(id: q.id, path: destination.path) { return SimpleResult(ok: false, error: error) }
            return SimpleResult(ok: true, error: nil)
        } catch {
            return SimpleResult(ok: false, error: "The signed copy couldn't be saved in the project folder: \(error.localizedDescription)")
        }
    }

    private func handleUploadSignedQuotation(id: String, quotationId: String) {
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
    private func handleSaveSignedQuotationData(id: String, payload: [String: Any]) {
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
    private func handleSignedCopyAction(id: String, quotationId: String, action: String) {
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

    private func respond<T: Encodable>(id: String, encodable: T) {
        guard let data = try? JSONEncoder().encode(encodable), let json = String(data: data, encoding: .utf8) else {
            respondError(id: id, message: "Failed to encode response")
            return
        }
        callback(id: id, ok: true, resultJson: json, error: nil)
    }

    private func respondNull(id: String) {
        callback(id: id, ok: true, resultJson: "null", error: nil)
    }

    private func respondError(id: String, message: String) {
        callback(id: id, ok: false, resultJson: nil, error: message)
    }

    private func callback(id: String, ok: Bool, resultJson: String?, error: String?) {
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

    private func jsStringLiteral(_ s: String) -> String {
        guard let data = try? JSONEncoder().encode(s), let json = String(data: data, encoding: .utf8) else {
            return "\"\""
        }
        return json
    }
}

// =====================================================================
// MARK: - App delegate
// =====================================================================

/// Behaves like a standard Mac title bar over the top edge of the page:
/// drag to move the window; double-click follows the person's System
/// Settings choice (zoom, minimise, or nothing).
final class TitlebarDragView: NSView {
    override var mouseDownCanMoveWindow: Bool { true }

    override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        if event.clickCount == 2 {
            switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
            case "Minimize": window.performMiniaturize(nil)
            case "None": break
            default: window.performZoom(nil)
            }
            return
        }
        window.performDrag(with: event)
    }

    // Transparent: let the page show through.
    override func draw(_ dirtyRect: NSRect) {}
}

// =====================================================================
// MARK: - Checking GitHub for a newer version
//
// install.sh records the commit it built (commit.txt) and its source
// folder (source.txt). When the app opens it fetches from GitHub in that
// folder (without asking for a password), then compares: GitHub's latest
// as last fetched — here, or by GitHub Desktop — and the folder's own
// latest, with what's installed. If Terminal can't sign in to GitHub, a
// public repository is also checked through GitHub's web API.
// =====================================================================

struct UpdateInfo {
    /// How many changes are newer than this copy (nil = newer, count unknown).
    var changes: Int?
    /// The newest change's description.
    var latest: String?
    /// Install ScaffoldPro.command in the source folder.
    var installer: URL?
}

enum UpdateChecker {
    static func resource(_ name: String) -> String? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent(name),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return nonBlank(text)
    }

    /// Whether this copy was built from a git folder (so updates can be checked).
    static var canCheck: Bool { resource("commit.txt") != nil && resource("source.txt") != nil }

    /// Runs git in `dir`, never waiting on a password prompt; nil if it
    /// failed or took longer than `timeout`.
    static func git(_ args: [String], in dir: String, timeout: TimeInterval = 20) -> String? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", dir] + args
        var env = ProcessInfo.processInfo.environment
        env["GIT_TERMINAL_PROMPT"] = "0"
        p.environment = env
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        do { try p.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(timeout)
        while p.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.1) }
        if p.isRunning { p.terminate(); return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        guard p.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The latest commit on GitHub, through the web API (public
    /// repositories only), for when git can't sign in.
    private static func latestOnGitHub(repoDir: String, branch: String) -> String? {
        guard let remote = git(["remote", "get-url", "origin"], in: repoDir),
              let match = remote.range(of: #"github\.com[:/]([^/]+)/([^/]+?)(\.git)?/?$"#, options: .regularExpression) else { return nil }
        let parts = remote[match].dropFirst("github.com/".count).split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        guard let url = URL(string: "https://api.github.com/repos/\(parts[0])/\(repo)/commits/\(branch)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github.sha", forHTTPHeaderField: "Accept")
        let done = DispatchSemaphore(value: 0)
        var sha: String?
        URLSession.shared.dataTask(with: request) { data, response, _ in
            if (response as? HTTPURLResponse)?.statusCode == 200, let data = data {
                sha = nonBlank(String(data: data, encoding: .utf8))
            }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 20)
        return sha
    }

    /// Checks for a newer version (background thread). nil = up to date,
    /// or it couldn't tell.
    static func check() -> UpdateInfo? {
        guard let installed = resource("commit.txt"), let source = resource("source.txt"),
              FileManager.default.fileExists(atPath: source),
              let top = git(["rev-parse", "--show-toplevel"], in: source), !top.isEmpty else { return nil }
        let installer = URL(fileURLWithPath: top).appendingPathComponent("Install ScaffoldPro.command")
        let fetched = git(["-c", "credential.interactive=never", "fetch", "--quiet", "origin"], in: top, timeout: 30) != nil
        var newest = 0
        var newestRef: String?
        for ref in ["@{u}", "origin/main", "HEAD"] {
            guard let n = git(["rev-list", "--count", "\(installed)..\(ref)"], in: top).flatMap({ Int($0) }), n > newest else { continue }
            newest = n
            newestRef = ref
        }
        if newest > 0 {
            return UpdateInfo(changes: newest, latest: newestRef.flatMap { git(["log", "-1", "--format=%s", $0], in: top) },
                              installer: FileManager.default.fileExists(atPath: installer.path) ? installer : nil)
        }
        // Couldn't reach GitHub with git: ask its web API instead.
        if !fetched {
            let branch = git(["rev-parse", "--abbrev-ref", "@{u}"], in: top).map { String($0.split(separator: "/").last ?? "main") } ?? "main"
            if let sha = latestOnGitHub(repoDir: top, branch: branch), sha != installed,
               git(["merge-base", "--is-ancestor", sha, installed], in: top) == nil {
                return UpdateInfo(changes: nil, latest: nil, installer: FileManager.default.fileExists(atPath: installer.path) ? installer : nil)
            }
        }
        return nil
    }
}

// =====================================================================
// MARK: - Updating inside the app (a loading screen instead of Terminal)
//
// "Update Now" gets the new version and builds it in the background while
// a loading screen shows how far it has got. Terminal isn't used:
//  1. git pull in the source folder (never asking for a password). If
//     that can't sign in to GitHub, GitHub Desktop is opened and the
//     screen waits until its Pull origin has brought the new version.
//  2. install.sh, with its messages going to a log file
//     (~/Library/Logs/ScaffoldPro Update.log) that the screen follows.
//     Near the end install.sh closes this copy, puts the new one in
//     Applications and opens it. (A log file, unlike a pipe back to this
//     app, lets install.sh carry on once this copy has closed.)
// =====================================================================

/// Where an update shows its progress (see Updater).
protocol UpdateScreen: AnyObject {
    func present()
    func setTitle(_ title: String)
    /// progress 0–100, or nil for "working on it".
    func show(_ status: String, _ detail: String, progress: Double?)
    func hideProgress()
    /// Buttons, the first the default; `tapped` gets the one pressed.
    func setButtons(_ titles: [String], _ tapped: @escaping (Int) -> Void)
    func dismiss()
}

/// The update's progress in a sheet on the main window ("Check for Updates…").
final class SheetUpdateScreen: NSObject, UpdateScreen {
    private weak var host: NSWindow?
    private var sheet: NSWindow?
    private let titleLabel = NSTextField(labelWithString: "Updating ScaffoldPro")
    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let bar = NSProgressIndicator()
    private let buttonRow = NSStackView()
    private var tapped: ((Int) -> Void)?

    init(host: NSWindow) {
        self.host = host
        super.init()
    }

    func present() {
        guard let host = host, sheet == nil else { return }
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 210), styleMask: [.titled], backing: .buffered, defer: false)
        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 64).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 64).isActive = true
        titleLabel.font = .boldSystemFont(ofSize: 15)
        statusLabel.font = .systemFont(ofSize: 13)
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.preferredMaxLayoutWidth = 340
        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 100
        bar.widthAnchor.constraint(equalToConstant: 340).isActive = true
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.isHidden = true
        let text = NSStackView(views: [titleLabel, statusLabel, bar, detailLabel, buttonRow])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 8
        let row = NSStackView(views: [icon, text])
        row.orientation = .horizontal
        row.alignment = .top
        row.spacing = 16
        row.edgeInsets = NSEdgeInsets(top: 22, left: 22, bottom: 22, right: 22)
        row.translatesAutoresizingMaskIntoConstraints = false
        let content = NSView()
        content.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: content.leadingAnchor), row.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            row.topAnchor.constraint(equalTo: content.topAnchor), row.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        window.contentView = content
        sheet = window
        host.beginSheet(window, completionHandler: nil)
    }

    func setTitle(_ title: String) { titleLabel.stringValue = title }

    func show(_ status: String, _ detail: String, progress: Double?) {
        statusLabel.stringValue = status
        detailLabel.stringValue = detail
        bar.isHidden = false
        if let p = progress {
            bar.isIndeterminate = false
            bar.stopAnimation(nil)
            bar.doubleValue = p
        } else {
            bar.isIndeterminate = true
            bar.startAnimation(nil)
        }
    }

    func hideProgress() { bar.isHidden = true }

    func setButtons(_ titles: [String], _ tapped: @escaping (Int) -> Void) {
        self.tapped = tapped
        for v in buttonRow.arrangedSubviews { buttonRow.removeArrangedSubview(v); v.removeFromSuperview() }
        for (i, title) in titles.enumerated() {
            let b = NSButton(title: title, target: self, action: #selector(buttonClicked(_:)))
            b.bezelStyle = .rounded
            b.tag = i
            if i == 0 { b.keyEquivalent = "\r" }
            buttonRow.addArrangedSubview(b)
        }
        buttonRow.isHidden = titles.isEmpty
    }

    @objc private func buttonClicked(_ sender: NSButton) { tapped?(sender.tag) }

    func dismiss() {
        if let sheet = sheet, let host = host { host.endSheet(sheet) }
        sheet = nil
    }
}

// =====================================================================
// MARK: - The launch screen
//
// Shown as ScaffoldPro opens, while it checks GitHub for a newer version
// (launch.html: the scaffold logo builds itself, then "Checking for
// updates…"). A newer version is offered there, and if it's taken the
// update's progress is shown there too, so the app never opens only to
// ask a few seconds later. Otherwise the main window opens and the
// screen fades away.
// =====================================================================

/// Passes the page's messages on without WKUserContentController keeping
/// the launch screen alive.
private final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Borderless, yet able to take clicks and the keyboard (Return / Escape).
private final class LaunchWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class LaunchScreen: NSObject, UpdateScreen, WKScriptMessageHandler, WKNavigationDelegate {
    private let window: LaunchWindow
    private let webView: WKWebView
    private var loaded = false
    private var pending: [String] = []
    private var tapped: ((Int) -> Void)?
    private var closing = false
    /// When the screen appeared (the logo's animation takes about 1.8 s).
    private(set) var shownAt = Date()

    /// nil when this copy has no launch.html (then the app just opens).
    static func make() -> LaunchScreen? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let page = resources.appendingPathComponent("launch.html")
        guard FileManager.default.fileExists(atPath: page.path) else { return nil }
        return LaunchScreen(page: page, resources: resources)
    }

    private init(page: URL, resources: URL) {
        let size = NSSize(width: 560, height: 380)
        let win = LaunchWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isReleasedWhenClosed = false
        win.title = "ScaffoldPro"
        let config = WKWebViewConfiguration()
        let web = WKWebView(frame: NSRect(origin: .zero, size: size), configuration: config)
        web.autoresizingMask = [.width, .height]
        // Transparent, so the rounded card's corners show the desktop.
        web.setValue(false, forKey: "drawsBackground")
        win.contentView = web
        window = win
        webView = web
        super.init()
        config.userContentController.add(WeakScriptHandler(self), name: "launch")
        webView.navigationDelegate = self
        webView.loadFileURL(page, allowingReadAccessTo: resources)
    }

    /// Appears once the page has loaded (or after half a second anyway).
    func open() {
        window.center()
        window.alphaValue = 0
        shownAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.reveal() }
    }

    private func reveal() {
        guard !closing, window.alphaValue == 0 else { return }
        shownAt = Date()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            window.animator().alphaValue = 1
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded = true
        for script in pending { webView.evaluateJavaScript(script, completionHandler: nil) }
        pending = []
        window.invalidateShadow()
        reveal()
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "launch", let body = message.body as? [String: Any], let index = body["button"] as? Int else { return }
        tapped?(index)
    }

    private func run(_ script: String) {
        if loaded { webView.evaluateJavaScript(script, completionHandler: nil) } else { pending.append(script) }
    }

    /// A string as a JavaScript literal.
    private func js(_ text: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [text]), let array = String(data: data, encoding: .utf8) else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }

    /// The line under the logo, e.g. "Checking for updates" (with moving dots while `busy`).
    func status(_ text: String, busy: Bool = true) {
        run("launch.status(\(js(text)), \(busy))")
    }

    // UpdateScreen
    func present() {}
    func setTitle(_ title: String) { run("launch.setTitle(\(js(title)))") }
    func show(_ status: String, _ detail: String, progress: Double?) {
        run("launch.show(\(js(status)), \(js(detail)), \(progress.map { String(format: "%.1f", $0) } ?? "null"))")
    }
    func hideProgress() { run("launch.hideProgress()") }
    func setButtons(_ titles: [String], _ tapped: @escaping (Int) -> Void) {
        self.tapped = tapped
        run("launch.setButtons([\(titles.map { js($0) }.joined(separator: ","))])")
    }
    func dismiss() { close() }

    /// Fades away (the main window taking over), then goes.
    func close(then done: (() -> Void)? = nil) {
        guard !closing else { done?(); return }
        closing = true
        tapped = nil
        webView.evaluateJavaScript("window.launch && launch.leave()", completionHandler: nil)
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.4
            window.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            guard let self = self else { return }
            self.window.orderOut(nil)
            self.webView.configuration.userContentController.removeScriptMessageHandler(forName: "launch")
            done?()
        })
    }
}

final class Updater: NSObject {
    /// Where the progress is shown: a sheet on the main window, or the
    /// launch screen when the update was offered as the app opened.
    private let screen: UpdateScreen
    private let installed: String
    private let sourceDir: String
    private let repoDir: String
    private let logURL: URL
    private var timer: Timer?
    private var compileStarted: Date?
    private var waitingForDesktop = false
    private var finished = false
    /// Called when the screen closes without updating (cancelled, failed, nothing new).
    var onClose: (() -> Void)?

    convenience init?(host: NSWindow) {
        self.init(screen: SheetUpdateScreen(host: host))
    }

    init?(screen: UpdateScreen) {
        guard let commit = UpdateChecker.resource("commit.txt"), let source = UpdateChecker.resource("source.txt"),
              FileManager.default.fileExists(atPath: source + "/install.sh"),
              let top = UpdateChecker.git(["rev-parse", "--show-toplevel"], in: source), !top.isEmpty else { return nil }
        self.screen = screen
        installed = commit
        sourceDir = source
        repoDir = top
        let logs = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        logURL = logs.appendingPathComponent("ScaffoldPro Update.log")
        super.init()
    }

    // MARK: the screen

    private func show(_ status: String, _ detail: String, progress: Double?) {
        screen.show(status, detail, progress: progress)
    }

    /// Buttons under the progress, the first the default; each runs its selector.
    private func setButtons(_ items: [(String, Selector)]) {
        screen.setButtons(items.map { $0.0 }) { [weak self] index in
            guard let self = self, index < items.count else { return }
            self.perform(items[index].1, with: nil)
        }
    }

    private func closeScreen() {
        timer?.invalidate()
        timer = nil
        screen.dismiss()
        onClose?()
    }

    @objc private func closeClicked(_ sender: Any?) { closeScreen() }
    @objc private func showLogClicked(_ sender: Any?) { NSWorkspace.shared.open(logURL) }
    @objc private func openDesktopClicked(_ sender: Any?) { openGitHubDesktop() }
    @objc private func cancelClicked(_ sender: Any?) { waitingForDesktop = false; closeScreen() }

    private func fail(_ message: String) {
        finished = true
        timer?.invalidate()
        screen.setTitle("The update didn't finish")
        show(message, "ScaffoldPro is still the version you had; nothing has changed.", progress: 0)
        screen.hideProgress()
        setButtons([("Close", #selector(closeClicked(_:))), ("Show Log", #selector(showLogClicked(_:)))])
    }

    // MARK: 1. getting the new version

    func start() {
        screen.present()
        screen.setTitle("Updating ScaffoldPro")
        show("Getting the latest version…", "", progress: nil)
        DispatchQueue.global(qos: .userInitiated).async {
            let pulled = UpdateChecker.git(["-c", "credential.interactive=never", "pull", "--ff-only", "--quiet"], in: self.repoDir, timeout: 90) != nil
            let state = self.localState()
            DispatchQueue.main.async {
                if state.hasNew {
                    self.build()
                } else if pulled && state.head == self.installed {
                    self.finished = true
                    self.screen.setTitle("ScaffoldPro is up to date")
                    self.show("There's nothing new to install.", "", progress: 100)
                    self.setButtons([("Close", #selector(self.closeClicked(_:)))])
                } else if self.gitHubDesktopURL != nil {
                    self.waitForGitHubDesktop()
                } else {
                    self.fail("The new version couldn't be downloaded from GitHub (it may need you to sign in). Open the Scaffold-Pro folder in GitHub Desktop, press Pull origin, then try again.")
                }
            }
        }
    }

    /// The source folder's version, and whether it's newer than this copy
    /// with nothing left to pull (as far as the last fetch knows).
    private func localState() -> (head: String, hasNew: Bool) {
        let head = UpdateChecker.git(["rev-parse", "HEAD"], in: repoDir) ?? installed
        let behind = UpdateChecker.git(["rev-list", "--count", "HEAD..@{u}"], in: repoDir).flatMap { Int($0) } ?? 0
        return (head, head != installed && behind == 0)
    }

    private var gitHubDesktopURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.github.GitHubClient") }

    private func openGitHubDesktop() {
        guard let app = gitHubDesktopURL else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: repoDir)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    /// Git can't sign in to GitHub by itself: GitHub Desktop brings the new
    /// version, and the screen carries on by itself once it's here.
    private func waitForGitHubDesktop() {
        waitingForDesktop = true
        openGitHubDesktop()
        show("Waiting for GitHub Desktop…", "In GitHub Desktop, press “Fetch origin”, then “Pull origin”. The update carries on by itself once the new version is here.", progress: nil)
        setButtons([("Open GitHub Desktop", #selector(openDesktopClicked(_:))), ("Cancel", #selector(cancelClicked(_:)))])
        checkForDesktopPull()
    }

    private func checkForDesktopPull() {
        guard waitingForDesktop else { return }
        DispatchQueue.global(qos: .utility).async {
            let state = self.localState()
            DispatchQueue.main.async {
                guard self.waitingForDesktop else { return }
                if state.hasNew {
                    self.waitingForDesktop = false
                    self.build()
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.checkForDesktopPull() }
                }
            }
        }
    }

    // MARK: 2. building and installing

    private var buildTask: Process?
    private var buildStarted: Date?
    private var slowShown = false

    private func build() {
        setButtons([])
        show("Building the new version…", "This takes about a minute. ScaffoldPro closes and opens again by itself when it's done.", progress: 3)
        NSApp.activate(ignoringOtherApps: true)
        try? Data().write(to: logURL)
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = ["-c", "exec /bin/bash ./install.sh > \"$0\" 2>&1 < /dev/null", logURL.path]
        task.currentDirectoryURL = URL(fileURLWithPath: sourceDir)
        // Only build: this app installs it (see installAndReopen).
        var env = ProcessInfo.processInfo.environment
        env["SCAFFOLDPRO_BUILD_ONLY"] = "1"
        task.environment = env
        task.terminationHandler = { process in
            DispatchQueue.main.async {
                self.buildTask = nil
                if process.terminationStatus == 0 {
                    self.installAndReopen()
                } else {
                    let lines = ((try? String(contentsOf: self.logURL, encoding: .utf8)) ?? "")
                        .split(separator: "\n").map(String.init).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                    let reason = lines.last { $0.contains("error:") || $0.hasPrefix("❌") } ?? lines.last ?? "The build stopped."
                    self.fail("It couldn't be built: \(reason.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        do { try task.run() } catch {
            fail("The installer couldn't be started: \(error.localizedDescription)")
            return
        }
        buildTask = task
        buildStarted = Date()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in self?.followLog() }
    }

    @objc private func stopClicked(_ sender: Any?) { buildTask?.terminate() }

    // MARK: 3. putting the new copy in place

    /// Where a failed install leaves its reason, for the next launch to show.
    static var failureNoteURL: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/ScaffoldPro Update failed.txt")
    }

    /// Waits for this copy to close, then swaps the new build in (the old
    /// copy is only removed once the new one is in place, and is put back
    /// if that fails) and opens ScaffoldPro. Runs on its own after this
    /// app has quit.
    private static let installScript = """
    #!/bin/sh
    PID="$1"; BUILD="$2"; DEST="$3"; FAILED="$4"
    n=0
    while kill -0 "$PID" 2>/dev/null; do
        n=$((n + 1))
        [ "$n" -eq 75 ] && kill -9 "$PID" 2>/dev/null
        sleep 0.2
    done
    echo "📦 Installing to $DEST..."
    rm -f "$FAILED"
    NEW="$DEST.updating"
    OLD="$DEST.previous"
    rm -rf "$NEW" "$OLD"
    if cp -R "$BUILD" "$NEW" && mv "$DEST" "$OLD"; then
        if mv "$NEW" "$DEST"; then
            rm -rf "$OLD"
            xattr -cr "$DEST" 2>/dev/null
            /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST" 2>/dev/null
            echo "✅ Installed."
        else
            mv "$OLD" "$DEST"
            echo "❌ The new copy couldn't be moved into place."
            echo "The new version couldn't be moved into place." > "$FAILED"
        fi
    else
        rm -rf "$NEW"
        echo "❌ The copy in $DEST couldn't be replaced."
        echo "The copy of ScaffoldPro in $(dirname "$DEST") couldn't be replaced. If macOS asked about letting ScaffoldPro modify apps, allow it in System Settings › Privacy & Security › App Management, then update again." > "$FAILED"
    fi
    open "$DEST" || open "$BUILD"
    """

    private func installAndReopen() {
        finished = true
        timer?.invalidate()
        setButtons([])
        show("Installing…", "ScaffoldPro closes and opens again in a moment.", progress: 97)
        let build = URL(fileURLWithPath: sourceDir).appendingPathComponent("build/ScaffoldPro.app").path
        let script = FileManager.default.temporaryDirectory.appendingPathComponent("scaffoldpro-install-update.sh")
        do {
            try Updater.installScript.write(to: script, atomically: true, encoding: .utf8)
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/bin/sh")
            // Started in the background (nohup, &) so it carries on once this app has quit.
            helper.arguments = ["-c", "nohup /bin/sh \"$0\" \"$1\" \"$2\" \"$3\" \"$4\" >> \"$5\" 2>&1 < /dev/null &",
                                script.path, String(ProcessInfo.processInfo.processIdentifier), build, Bundle.main.bundlePath,
                                Updater.failureNoteURL.path, logURL.path]
            try helper.run()
        } catch {
            fail("The new version is built, but couldn't be installed: \(error.localizedDescription). Double-click Install ScaffoldPro to finish.")
            return
        }
        // Close this copy so the helper can replace it. If quitting is held
        // up for any reason, leave anyway after a few seconds.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            self.screen.dismiss()
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { exit(0) }
            NSApp.terminate(nil)
        }
    }

    /// Says (once) why the last update couldn't be installed, if it couldn't.
    static func reportPreviousFailure(in window: NSWindow?) {
        guard let text = try? String(contentsOf: failureNoteURL, encoding: .utf8) else { return }
        try? FileManager.default.removeItem(at: failureNoteURL)
        let alert = NSAlert()
        alert.messageText = "The last update couldn't be installed"
        alert.informativeText = text.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\nThis is still the version you had. You can try again from ScaffoldPro › Check for Updates…, or double-click Install ScaffoldPro."
        if let window = window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    /// Moves the screen on as install.sh reports each step.
    private func followLog() {
        guard !finished else { return }
        // Never stuck without a way out: after 8 minutes, offer to stop.
        if !slowShown, let started = buildStarted, Date().timeIntervalSince(started) > 480 {
            slowShown = true
            setButtons([("Show Log", #selector(showLogClicked(_:))), ("Stop", #selector(stopClicked(_:)))])
        }
        let log = (try? String(contentsOf: logURL, encoding: .utf8)) ?? ""
        func has(_ s: String) -> Bool { log.contains(s) }
        if has("✅ Built.") {
            show("Installing…", "ScaffoldPro closes and opens again in a moment.", progress: 96)
        } else if has("Ad-hoc signing") || has("Removing quarantine") || has("Validating Info.plist") || has("Adding app icon") {
            show("Finishing…", "Almost done.", progress: 90)
        } else if has("Assembling bundle") {
            show("Putting it together…", "Almost done.", progress: 84)
        } else if has("Compiling ScaffoldPro") {
            if compileStarted == nil { compileStarted = Date() }
            // Compiling is most of the wait (about a minute): creep towards 80%.
            let seconds = Date().timeIntervalSince(compileStarted ?? Date())
            show("Building the new version…", "This takes about a minute. ScaffoldPro closes and opens again by itself when it's done.",
                 progress: 8 + 72 * (1 - exp(-seconds / 45)))
        }
    }
}

/// Quits and opens ScaffoldPro again (after switching to or from a shared folder).
func relaunchApp() {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", "while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done; open \"$0\"", Bundle.main.bundlePath]
    try? task.run()
    NSApp.terminate(nil)
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var bridge: NativeBridge!
    var db: AppDatabase!
    var storage: FileStorage!
    /// Sharing is on, but this launch uses this Mac's own data.
    var teamFolderMissing = false

    /// The launch screen, while it's up.
    private var launchScreen: LaunchScreen?
    private var launched = false
    /// Set once the launch screen has decided (update offered, or opened).
    private var launchDecided = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerBundledFonts()
        // Quit works while the launch screen is up; the full menu comes with the main window.
        let launchMenu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit ScaffoldPro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(launchMenu, "ScaffoldPro", appMenu)
        NSApp.mainMenu = launchMenu

        guard let screen = LaunchScreen.make() else {
            finishLaunching()
            checkForUpdates(manual: false)
            return
        }
        launchScreen = screen
        screen.open()
        guard UpdateChecker.canCheck else {
            screen.status("Opening")
            afterLaunchAnimation { self.finishLaunching() }
            return
        }
        // Is there a newer version on GitHub? Asked here, before the app
        // opens, so it never pops up a few seconds after.
        screen.status("Checking for updates")
        checkingForUpdates = true
        // Never held up for long: after 10 seconds the app opens anyway,
        // and an answer that comes later is offered as before.
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in
            guard let self = self, !self.launchDecided else { return }
            self.launchDecided = true
            self.finishLaunching()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let info = UpdateChecker.check()
            DispatchQueue.main.async {
                self.checkingForUpdates = false
                if self.launchDecided {
                    if let info = info { self.offerUpdate(info) }
                    return
                }
                self.afterLaunchAnimation {
                    guard !self.launchDecided else { return }
                    self.launchDecided = true
                    if let info = info, info.installer != nil {
                        self.offerUpdateOnLaunchScreen(info, screen: screen)
                    } else {
                        screen.status("Up to date", busy: false)
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            self.finishLaunching()
                            if let info = info { self.offerUpdate(info) }
                        }
                    }
                }
            }
        }
    }

    /// Lets the logo finish building itself (about 1.9 s) before moving on.
    private func afterLaunchAnimation(_ then: @escaping () -> Void) {
        let shown = launchScreen?.shownAt ?? Date()
        let wait = max(0, 1.9 - Date().timeIntervalSince(shown))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: then)
    }

    /// "A new version is available" on the launch screen; Update Now shows
    /// the update's progress right there.
    private func offerUpdateOnLaunchScreen(_ info: UpdateInfo, screen: LaunchScreen) {
        var text = info.changes.map { "\($0) change\($0 == 1 ? "" : "s") since this copy was installed." } ?? "GitHub has a newer version than this copy."
        if let latest = nonBlank(info.latest) { text += " Latest: “\(latest)”." }
        screen.setTitle("A new version is available")
        screen.show(text, "Update now: it's downloaded and built here (about a minute), then ScaffoldPro opens again by itself.", progress: nil)
        screen.hideProgress()
        screen.setButtons(["Update Now", "Later"]) { [weak self] index in
            guard let self = self else { return }
            guard index == 0 else { self.finishLaunching(); return }
            guard let u = Updater(screen: screen) else {
                // This copy can't update itself: Install ScaffoldPro does it.
                if let installer = info.installer { NSWorkspace.shared.open(installer) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
                return
            }
            self.updater = u
            // Cancelled, failed or nothing new: the app opens as usual.
            u.onClose = { [weak self] in
                self?.updater = nil
                self?.finishLaunching()
            }
            u.start()
        }
    }

    /// Opens the main window (the launch screen fading away over it).
    private func finishLaunching() {
        guard !launched else { return }
        launched = true
        setupDataLayer()
        setupWindow()
        bridge.teamFolderMissing = teamFolderMissing
        // Other Macs' changes: the page refreshes to show them.
        TeamSync.current?.onRemoteChange = { [weak self] stores, names in
            self?.bridge.sharedDataChanged(stores: stores, names: names)
        }
        TeamSync.material?.onRemoteChange = { [weak self] stores, names in
            self?.bridge.sharedDataChanged(stores: stores, names: names)
        }
        // Keep the shared iCloud copy up to date from now on.
        bridge.cloudBackup.start()
        // A local backup every day at 12:00 a.m. and 12:00 p.m. (kept a week).
        bridge.startScheduledBackups()
        // If the last update couldn't be put in place, say why.
        Updater.reportPreviousFailure(in: window)
        launchScreen?.close()
        launchScreen = nil
    }

    // MARK: Updates

    private var checkingForUpdates = false

    @objc func checkForUpdatesFromMenu(_ sender: Any?) { checkForUpdates(manual: true) }

    /// Checks GitHub in the background; offers to update if there's a newer
    /// version. `manual` also says when it's up to date or couldn't check.
    func checkForUpdates(manual: Bool) {
        guard !checkingForUpdates else { return }
        guard UpdateChecker.canCheck else {
            if manual { showUpdateAlert("Updates can't be checked for this copy", "It wasn't installed from a GitHub copy of ScaffoldPro (a folder downloaded as a zip has no link to GitHub). Download the latest version and run install.sh.") }
            return
        }
        checkingForUpdates = true
        DispatchQueue.global(qos: .utility).async {
            let info = UpdateChecker.check()
            DispatchQueue.main.async {
                self.checkingForUpdates = false
                if let info = info { self.offerUpdate(info) }
                else if manual { self.showUpdateAlert("ScaffoldPro is up to date", "This is the latest version on GitHub (as far as can be checked from this Mac).") }
            }
        }
    }

    private var updater: Updater?

    /// Runs the update behind a loading screen; if this copy can't (no
    /// source folder), Install ScaffoldPro runs in Terminal instead.
    private func startUpdate(fallbackInstaller: URL) {
        guard updater == nil else { return }
        guard let window = window, let u = Updater(host: window) else {
            NSWorkspace.shared.open(fallbackInstaller)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
            return
        }
        updater = u
        u.onClose = { [weak self] in self?.updater = nil }
        u.start()
    }

    private func showUpdateAlert(_ title: String, _ text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        if let window = window { alert.beginSheetModal(for: window) } else { alert.runModal() }
    }

    private func offerUpdate(_ info: UpdateInfo) {
        let alert = NSAlert()
        alert.messageText = "A new version of ScaffoldPro is available"
        var text = info.changes.map { "\($0) change\($0 == 1 ? "" : "s") since this copy was installed." } ?? "GitHub has a newer version than this copy."
        if let latest = nonBlank(info.latest) { text += "\nLatest: “\(latest)”." }
        text += info.installer == nil
            ? "\n\nTo update, run install.sh in the ScaffoldPro-native folder."
            : "\n\nUpdate now? ScaffoldPro closes, Install ScaffoldPro gets the new version and builds it (about a minute), then opens it again."
        alert.informativeText = text
        alert.addButton(withTitle: info.installer == nil ? "OK" : "Update Now")
        if info.installer != nil { alert.addButton(withTitle: "Later") }
        let handle: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .alertFirstButtonReturn, let installer = info.installer else { return }
            // Updated here, behind a loading screen (Terminal isn't shown).
            // The alert has to be gone before the loading screen appears.
            DispatchQueue.main.async { self.startUpdate(fallbackInstaller: installer) }
        }
        if let window = window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// EB Garamond — the documents' body font (as on the company's
    /// quotation) — ships inside the app, in resources/fonts, under the
    /// SIL Open Font License. Registered for this app only.
    private func registerBundledFonts() {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("resources/fonts", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for url in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    private func setupDataLayer() {
        let fm = FileManager.default
        let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appFolder = appSupport.appendingPathComponent("ScaffoldPro", isDirectory: true)
        var dataDir = appFolder.appendingPathComponent("data", isDirectory: true)
        var documentsRoot = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        var companyFolderName = "ScaffoldPro"

        // Sharing a folder with other Macs: the database is the merge of
        // everyone's logs there, and the files live in that folder.
        if let team = TeamSync.configuredFolder {
            let mirror = appFolder.appendingPathComponent("team-data", isDirectory: true)
            let sync = TeamSync(root: team, localData: mirror)
            if TeamSync.isWorkspace(team) && sync.start() {
                dataDir = mirror
                documentsRoot = team.deletingLastPathComponent()
                companyFolderName = team.lastPathComponent
            } else {
                teamFolderMissing = true
                let alert = NSAlert()
                alert.alertStyle = .warning
                alert.messageText = TeamSync.isWorkspace(team) ? "The shared folder is still downloading" : "The shared folder can't be found"
                alert.informativeText = "ScaffoldPro is set to use the shared folder “\(TeamSync.display(team))”, but "
                    + (TeamSync.isWorkspace(team)
                       ? "its files are still coming down from iCloud. Wait a minute and open ScaffoldPro again."
                       : "it isn't there. Check that iCloud Drive is on and the shared folder has been accepted (it shows in Finder under iCloud Drive).")
                    + "\n\nYou can also work on this Mac's own data for now — changes made then aren't shared."
                alert.addButton(withTitle: "Quit")
                alert.addButton(withTitle: "Use This Mac's Own Data")
                alert.addButton(withTitle: "Stop Sharing")
                switch alert.runModal() {
                case .alertFirstButtonReturn: exit(0)
                case .alertThirdButtonReturn: TeamSync.setConfiguredFolder(nil); teamFolderMissing = false
                default: break
                }
            }
        }
        try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true)

        db = AppDatabase(dataDir: dataDir)

        let backupsRoot = appFolder.appendingPathComponent("Backups", isDirectory: true)
        storage = FileStorage(documentsRoot: documentsRoot, companyFolderName: companyFolderName, backupsRoot: backupsRoot)
        storage.ensureRootFoldersExist()
        storage.moveLegacyBackups()

        // A shared folder already has its price lists (seeding one again
        // before the others' logs arrive would make a second copy).
        if TeamSync.current == nil {
            let brandNew = !db.priceListsAreSeeded
            seedPriceListsIfNeeded()
            startMaterialSync(dataDir: dataDir, brandNew: brandNew)
        }
        db.fixScafomCurrencyIfNeeded()
        db.applyDeliveryChargeUpdateIfNeeded()
        db.movePaymentTermsIntoKeyTermsIfNeeded()
        db.moveBOQMarkupsOntoRates()
        db.addStructuresToQuotationSubjects()
        db.fillChineseNamesIfNeeded()
    }

    /// Not in a shared folder: the material list is still kept the same on
    /// every Mac, through iCloud Drive (TeamSync.materialFolder).
    /// `brandNew`: the list was only just made from the app's own copy.
    private func startMaterialSync(dataDir: URL, brandNew: Bool) {
        guard let folder = TeamSync.materialFolder else { return }
        let sync = TeamSync(root: folder, localData: dataDir, only: TeamSync.materialStores)
        if !sync.hasOwnLog {
            // First time on this Mac: its list goes in as of when it was
            // last changed here, so a newer change made on another Mac wins
            // (and a list only just made here never replaces anyone's).
            let saved = (try? dataDir.appendingPathComponent("price_list_items.json").resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate?.timeIntervalSince1970
            db.canonicalizePriceListIds()
            let stamp = brandNew ? 1 : min(saved ?? 1, Date().timeIntervalSince1970)
            sync.seed(from: dataDir, fromRoot: storage.appRoot, stamp: stamp)
        }
        if !sync.start(downloadTimeout: 5) {
            NSLog("ScaffoldPro: the material list in iCloud Drive isn't on this Mac yet; it's kept in step from the next launch.")
        }
    }

    private func seedPriceListsIfNeeded() {
        guard !db.priceListsAreSeeded, let resourceURL = Bundle.main.resourceURL else { return }

        func loadSeed(_ filename: String) -> [SeedPriceItem] {
            let url = resourceURL.appendingPathComponent("resources/\(filename)")
            guard let data = try? Data(contentsOf: url) else { return [] }
            return (try? JSONDecoder().decode([SeedPriceItem].self, from: data)) ?? []
        }

        let spItems = loadSeed("sp_pricelist.json")
        let scafomItems = loadSeed("scafom_pricelist.json")

        if !spItems.isEmpty {
            db.seedPriceList(sourceKey: "SP", displayName: "SP Material & Price List 2026", currency: "HKD", items: spItems)
        }
        if !scafomItems.isEmpty {
            db.seedPriceList(sourceKey: "SCAFOM", displayName: "SCAFOM Material & Price List", currency: "EUR", items: scafomItems)
        }
    }

    private func setupWindow() {
        let contentRect = NSRect(x: 0, y: 0, width: 1280, height: 800)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.center()
        window.title = "ScaffoldPro"
        window.minSize = NSSize(width: 1000, height: 660)
        // Unified, modern Mac title bar: the sidebar runs up behind the
        // window buttons, like Finder, Mail and Notes.
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.toolbarStyle = .unified
        // Reopen at the same size and position as last time.
        window.setFrameAutosaveName("ScaffoldProMainWindow")

        let contentController = WKUserContentController()
        bridge = NativeBridge(db: db, storage: storage)
        contentController.add(bridge, name: "native")

        // Inject the JS bridge (window.api) at document-start so it exists
        // before dashboard.js / clients.js / etc. run — see js/bridge.js.
        if let bridgeScriptURL = Bundle.main.resourceURL?.appendingPathComponent("js/bridge.js"),
           let bridgeSource = try? String(contentsOf: bridgeScriptURL, encoding: .utf8) {
            let userScript = WKUserScript(source: bridgeSource, injectionTime: .atDocumentStart, forMainFrameOnly: true)
            contentController.addUserScript(userScript)
        }

        let config = WKWebViewConfiguration()
        config.userContentController = contentController

        webView = WKWebView(frame: contentRect, configuration: config)
        webView.autoresizingMask = [.width, .height]
        // No white flash between pages in Dark Mode.
        webView.underPageBackgroundColor = .windowBackgroundColor
        // Without a UI delegate, WKWebView silently ignores every alert(),
        // confirm() and prompt() — confirm() just returns false. That made
        // Delete, Archive, Rename, Restore etc. quietly do nothing.
        webView.uiDelegate = self
        bridge.webView = webView
        bridge.window = window

        // The page runs up behind the title bar (unified look), so a web
        // view would swallow title-bar drags. A thin native strip on top
        // restores normal title-bar behaviour: drag to move, double-click
        // to zoom. The window buttons sit above it and stay clickable.
        let container = NSView(frame: contentRect)
        container.autoresizingMask = [.width, .height]
        webView.frame = container.bounds
        container.addSubview(webView)
        let stripHeight: CGFloat = 38
        let dragStrip = TitlebarDragView(frame: NSRect(x: 0, y: container.bounds.height - stripHeight,
                                                       width: container.bounds.width, height: stripHeight))
        dragStrip.autoresizingMask = [.width, .minYMargin]
        container.addSubview(dragStrip, positioned: .above, relativeTo: webView)
        window.contentView = container

        if let resourceURL = Bundle.main.resourceURL {
            let indexURL = resourceURL.appendingPathComponent("index.html")
            webView.loadFileURL(indexURL, allowingReadAccessTo: resourceURL)
        }

        bridge.applyAppearance(db.getCompanySettings().appearance)
        setupMenuBar()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Native dialogs for the pages' alert / confirm / prompt

    /// The pages write messages as "Headline\n\nMore detail" — shown as a
    /// bold title plus explanatory text, like standard Mac alerts.
    private func makeAlert(_ message: String) -> NSAlert {
        let alert = NSAlert()
        let parts = message.components(separatedBy: "\n\n")
        alert.messageText = parts.first ?? message
        if parts.count > 1 { alert.informativeText = parts.dropFirst().joined(separator: "\n\n") }
        return alert
    }

    private func isDestructive(_ message: String) -> Bool {
        let lower = message.lowercased()
        return ["delete", "archive", "remove", "restor", "replace all"].contains { lower.hasPrefix($0) || lower.contains(" \($0)") }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = makeAlert(message)
        alert.addButton(withTitle: "OK")
        alert.beginSheetModal(for: window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = makeAlert(message)
        let ok = alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        if isDestructive(message) {
            alert.alertStyle = .warning
            ok.hasDestructiveAction = true
        }
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = makeAlert(prompt)
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        alert.beginSheetModal(for: window) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }

    // MARK: Menu bar & keyboard shortcuts (sections 4, 51, 60)
    //
    // Without an Edit menu, ⌘C / ⌘V / ⌘X / ⌘A / ⌘Z don't work in text
    // fields at all in a WKWebView app — so this is essential, not polish.

    private func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [.command], page: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = modifiers
        if let page = page { i.representedObject = page }
        return i
    }

    private func setupMenuBar() {
        let main = NSMenu()

        // App menu
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About ScaffoldPro", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let updates = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdatesFromMenu(_:)), keyEquivalent: "")
        updates.target = self
        appMenu.addItem(updates)
        appMenu.addItem(.separator())
        let settings = item("Settings…", #selector(goToPage(_:)), ",", page: "settings.html")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide ScaffoldPro", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit ScaffoldPro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        addSubmenu(main, "ScaffoldPro", appMenu)

        // File
        let file = NSMenu(title: "File")
        let newItems: [(String, String, NSEvent.ModifierFlags, String)] = [
            ("New Project…", "n", [.command], "projects.html?new=1"),
            ("New Client…", "n", [.command, .shift], "clients.html?new=1"),
            ("New Site…", "n", [.command, .option], "sites.html?new=1"),
        ]
        for (title, key, mods, page) in newItems {
            let i = item(title, #selector(goToPage(_:)), key, mods, page: page)
            i.target = self
            file.addItem(i)
        }
        file.addItem(.separator())
        let find = item("Find…", #selector(openSearch(_:)), "k")
        find.target = self
        file.addItem(find)
        file.addItem(.separator())
        let export = item("Export PDF", #selector(exportPDF(_:)), "e")
        export.target = self
        file.addItem(export)
        let print = item("Print…", #selector(printDocument(_:)), "p")
        print.target = self
        file.addItem(print)
        file.addItem(.separator())
        let backup = item("Back Up Now…", #selector(goToPage(_:)), "b", [.command, .shift], page: "settings.html#backup")
        backup.target = self
        file.addItem(backup)
        file.addItem(.separator())
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        addSubmenu(main, "File", file)

        // Edit — standard actions, handled by the web view.
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(main, "Edit", edit)

        // Go — ⌘1…⌘9 for the sidebar sections, ⌘[ / ⌘] for back/forward.
        let go = NSMenu(title: "Go")
        let sections: [(String, String)] = [("Dashboard", "index.html"), ("Material List", "price-lists.html"), ("Sites", "sites.html"),
                                            ("Clients", "clients.html"), ("Projects", "projects.html"), ("Stock", "stock.html"),
                                            ("Accounts", "accounts.html"), ("Admin", "admin.html"),
                                            ("Settings", "settings.html")]
        for (index, entry) in sections.enumerated() {
            let i = item(entry.0, #selector(goToPage(_:)), "\(index + 1)", page: entry.1)
            i.target = self
            go.addItem(i)
        }
        go.addItem(.separator())
        let back = item("Back", #selector(goBack(_:)), "[")
        back.target = self
        go.addItem(back)
        let forward = item("Forward", #selector(goForward(_:)), "]")
        forward.target = self
        go.addItem(forward)
        addSubmenu(main, "Go", go)

        // View
        let view = NSMenu(title: "View")
        let fullScreen = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        view.addItem(fullScreen)
        addSubmenu(main, "View", view)

        // Window
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        addSubmenu(main, "Window", windowMenu)
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = main
    }

    private func addSubmenu(_ main: NSMenu, _ title: String, _ submenu: NSMenu) {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        main.addItem(holder)
    }

    private func runJS(_ script: String) {
        window.makeKeyAndOrderFront(nil)
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    @objc func goToPage(_ sender: NSMenuItem) {
        guard let page = sender.representedObject as? String else { return }
        runJS("location.href = '\(page)';")
    }

    @objc func openSearch(_ sender: Any?) {
        runJS("window.openGlobalSearch && window.openGlobalSearch();")
    }

    @objc func exportPDF(_ sender: Any?) {
        runJS("(function(){ var b = document.getElementById('export-pdf-btn'); if (b && !b.disabled) b.click(); })();")
    }

    @objc func printDocument(_ sender: Any?) {
        runJS("(function(){ var b = document.getElementById('print-btn'); if (b && !b.disabled) b.click(); })();")
    }

    @objc func goBack(_ sender: Any?) {
        if webView.canGoBack { webView.goBack() }
    }

    @objc func goForward(_ sender: Any?) {
        if webView.canGoForward { webView.goForward() }
    }
}

// =====================================================================
// MARK: - Bootstrap
// =====================================================================

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()

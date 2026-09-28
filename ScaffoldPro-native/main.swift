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
    /// "Manual" or "Before Restore"
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
        markupPercent = try c.decodeIfPresent(Double.self, forKey: .markupPercent)
        keyTerms = try c.decodeIfPresent(String.self, forKey: .keyTerms)
        pdfPath = try c.decodeIfPresent(String.self, forKey: .pdfPath)
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

/// A unit price with a quotation's markup applied, rounded to the nearest
/// 0.1 (5.50 +30% → 7.20). Unchanged when there's no markup.
func markedUpPrice(_ price: Double, markupPercent: Double?) -> Double {
    guard let markup = markupPercent, markup > 0 else { return price }
    var value = decimalOf(price) * (1 + decimalOf(markup) / 100)
    var rounded = Decimal()
    NSDecimalRound(&rounded, &value, 1, .plain)
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
}

struct BOQDetail: Codable {
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
    /// Markup on every item's unit price (e.g. 30 = +30%), each marked-up
    /// price rounded to the nearest 0.1. Delivery charges aren't marked up.
    var markupPercent: Double?
    /// The last PDF exported for this document (sections 31-32).
    var pdfPath: String?
    /// This quotation's own key terms (payment, delivery, modification…),
    /// with paragraph formatting. nil/blank = the key terms from Settings.
    var keyTerms: String?
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
}

struct QuotationSummary: Codable {
    var id: String
    var quotationNumber: String
    var status: String
    var itemCount: Int
    var total: Double
    var createdAt: String
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
    /// Line id → unit price charged (after the markup).
    var effectiveUnitPrices: [String: Double]
    /// Line id → line total (after the markup and the line's discount).
    var lineTotals: [String: Double]
    /// Extra sections (priced, rates, notes), in order. Their rows are in
    /// `lineItems` with `blockId` set.
    var blocks: [QuotationBlock]
    /// The priced sections' rows, added to the total.
    var otherChargesTotal: Double
    /// This quotation's own key terms; nil = the standard ones below.
    var keyTerms: String?
    /// The key terms from Settings, printed when `keyTerms` is blank.
    var standardKeyTerms: String
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
    /// on a new page unless the whole quotation fits on one page) or
    /// "Always" (always on a page of their own, as on Qt26193).
    var termsNewPage: String?
}

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
    /// Starts at the top of a new page unless the whole document fits on
    /// one page (the quotation's Terms and Conditions).
    var newPageUnlessSinglePage: Bool = false
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
}

struct PDFExportResult: Codable {
    var ok: Bool
    var error: String?
    var path: String?
}

// =====================================================================
// MARK: - Small helpers
// =====================================================================

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
        // Atomic: written to a temporary file and swapped in, so a crash
        // or power cut mid-save can never leave a half-written database
        // file behind (section 48).
        try? data.write(to: fileURL, options: .atomic)
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

    private func uniqueDestination(_ url: URL) -> URL {
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
                               amount: t.total, balance: nil, dueDate: q.validUntil, isOverdue: false, url: "quotation-editor.html?id=\(q.id)"))
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
        return DashboardSummary(
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
        activityStore.insert(ActivityEntry(id: makeId("act"), projectId: projectId, action: action, reference: reference, createdAt: nowISO()))
    }

    func listActivity(projectId: String?, limit: Int) -> [ActivityRow] {
        let projects = projectsStore.readAll()
        return activityStore.readAll()
            .filter { projectId == nil || $0.projectId == projectId }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { e in
                let p = projects.first { $0.id == e.projectId }
                return ActivityRow(id: e.id, projectNumber: p?.projectNumber, projectName: p?.name, action: e.action, reference: e.reference, createdAt: e.createdAt)
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
        clientsStore.writeAll(items)
        return nil
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
        let client = Client(
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
            .filter { q.isEmpty || $0.itemName.lowercased().contains(q) || $0.itemCode.lowercased().contains(q) }
            .sorted { $0.itemCode.localizedStandardCompare($1.itemCode) == .orderedAscending }
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
            unitRentalPrice: payload["unitRentalPrice"] as? Double, applicableTypes: [], notes: nil, isArchived: false
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
        priceListItemsStore.insert(copy)
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
    func updatePriceListItem(id: String, itemName: String, category: String?, unit: String, unitSalePrice: Double?, unitRentalPrice: Double?, weightKg: Double? = nil, updateWeight: Bool = false) -> String? {
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
        doubleOf(items.reduce(Decimal(0)) { $0 + lineAmount(quantity: $1.quantity, unitPrice: $1.appliedUnitPrice) })
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
                let total = boqMoneyTotal(items)
                return BOQSummary(
                    id: boq.id, boqNumber: boq.boqNumber, status: boq.status,
                    pricingMode: boq.pricingMode, itemCount: items.count,
                    grandTotal: total, totalWeightKg: totalWeight(for: items), createdAt: boq.createdAt
                )
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

    func createBOQ(projectId: String, projectNumber: String, pricingMode: String) -> BillOfQuantities {
        let boq = BillOfQuantities(
            id: makeId("boq"),
            projectId: projectId,
            boqNumber: nextBOQNumber(projectNumber: projectNumber, projectId: projectId),
            pricingMode: pricingMode == "Sale" ? "Sale" : "Rental",
            status: "Draft",
            notes: nil,
            createdAt: nowISO(),
            updatedAt: nowISO()
        )
        boqsStore.insert(boq)
        logActivity(projectId: projectId, "BOQ created (\(boq.pricingMode))", reference: boq.boqNumber)
        return boq
    }

    func getBOQ(id: String) -> BillOfQuantities? {
        boqsStore.readAll().first { $0.id == id }
    }

    func getBOQDetail(id: String) -> BOQDetail? {
        guard let boq = boqsStore.readAll().first(where: { $0.id == id }) else { return nil }
        guard let project = projectsStore.readAll().first(where: { $0.id == boq.projectId }) else { return nil }
        let items = lineItems(for: boq.id)
        let total = boqMoneyTotal(items)
        return BOQDetail(
            id: boq.id, boqNumber: boq.boqNumber, status: boq.status, pricingMode: boq.pricingMode,
            notes: boq.notes, createdAt: boq.createdAt, updatedAt: boq.updatedAt,
            projectNumber: project.projectNumber, projectName: project.name,
            lineItems: items, grandTotal: total, totalWeightKg: totalWeight(for: items),
            markupPercent: boq.markupPercent ?? 0, structure: boq.structure
        )
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
        let oldMode = boqs[i].pricingMode
        let oldMarkup = boqs[i].markupPercent ?? 0
        let newMode = (pricingMode == "Sale" || pricingMode == "Rental") ? pricingMode! : oldMode
        let newMarkup = markupPercent ?? oldMarkup
        guard newMarkup > -100 else { return "A mark-down can't be 100% or more." }
        boqs[i].pricingMode = newMode
        boqs[i].markupPercent = newMarkup
        if updateStructure {
            let t = structure?.trimmingCharacters(in: .whitespacesAndNewlines)
            boqs[i].structure = (t?.isEmpty ?? true) ? nil : t
        }
        boqs[i].updatedAt = nowISO()
        boqsStore.writeAll(boqs)

        if newMode != oldMode || newMarkup != oldMarkup {
            let rates = conversionRates()
            let priceItems = Dictionary(priceListItemsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            var lines = boqLineItemsStore.readAll()
            var repriced = 0, kept = 0
            for li in lines.indices where lines[li].boqId == id {
                guard let plId = lines[li].priceListItemId, let pl = priceItems[plId] else { continue }
                let wasManual = lines[li].priceListUnitPrice.map { abs($0 - lines[li].appliedUnitPrice) > 0.004 } ?? false
                guard let newPrice = boqPrice(for: pl, mode: newMode, markupPercent: newMarkup, rates: rates) else { continue }
                lines[li].priceListUnitPrice = newPrice
                if wasManual { kept += 1 } else { lines[li].appliedUnitPrice = newPrice; repriced += 1 }
            }
            boqLineItemsStore.writeAll(lines)
            var what: [String] = []
            if newMode != oldMode { what.append("changed to \(newMode)") }
            if newMarkup != oldMarkup { what.append("mark-up \(formatMoney(newMarkup))%") }
            logActivity(projectId: boqs[i].projectId, "BOQ \(what.joined(separator: ", ")) — \(repriced) line(s) re-priced\(kept > 0 ? ", \(kept) hand-typed price(s) kept" : "")", reference: boqs[i].boqNumber)
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
    func deleteBOQ(id: String) -> String? {
        guard let boq = getBOQ(id: id) else { return "BOQ not found." }
        guard boq.status == "Draft" else { return "Only draft BOQs can be deleted." }
        var boqs = boqsStore.readAll()
        boqs.removeAll { $0.id == id }
        boqsStore.writeAll(boqs)
        logActivity(projectId: boq.projectId, "Draft BOQ deleted", reference: boq.boqNumber)
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
        isMaterialLine(line) ? markedUpPrice(line.appliedUnitPrice, markupPercent: q.markupPercent) : line.appliedUnitPrice
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
        func net(_ line: QuotationLineItem) -> Decimal { quotationLineTotal(line, q) }
        let materials = lineItems.filter { isMaterialLine($0) }.reduce(Decimal(0)) { $0 + net($1) }
        let delivery = lineItems.filter { isDeliveryLine($0) }.reduce(Decimal(0)) { $0 + net($1) }
        // Priced sections count once; rates-only rows aren't charged.
        let priced = Set(quotationBlocks(for: q.id).filter { $0.kind == "Priced" }.map { $0.id })
        let other = lineItems.filter { $0.blockId.map { priced.contains($0) } ?? false }.reduce(Decimal(0)) { $0 + net($1) }
        let charge = materials * Decimal(months)
        let t = moneyTotals(subtotal: charge + delivery + other, discountType: q.discountType, discountValue: q.discountValue,
                            taxRatePercent: q.taxRatePercent, pricesIncludeTax: getCompanySettings().pricesIncludeTax ?? false)
        return QuotationMoney(materialsSubtotal: doubleOf(materials), materialsCharge: doubleOf(charge), deliveryTotal: doubleOf(delivery),
                              otherTotal: doubleOf(other),
                              subtotal: t.subtotal, discountAmount: t.discountAmount, taxAmount: t.taxAmount, total: t.total)
    }

    func listQuotationSummaries(projectId: String) -> [QuotationSummary] {
        quotationsStore.readAll()
            .filter { $0.projectId == projectId }
            .sorted { $0.quotationNumber > $1.quotationNumber }
            .map { q in
                let items = quotationLineItems(for: q.id)
                let totals = quotationMoney(q, lineItems: items)
                return QuotationSummary(id: q.id, quotationNumber: q.quotationNumber, status: q.status, itemCount: items.count, total: totals.total, createdAt: q.createdAt)
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
            discountType: "None", discountValue: 0, taxRatePercent: settings.defaultTaxRatePercent,
            notes: settings.defaultNotes,
            createdAt: nowISO(), updatedAt: nowISO()
        )
        if let project = projectsStore.readAll().first(where: { $0.id == projectId }) {
            let site = sitesStore.readAll().first { $0.id == project.siteId }
            quotation.siteRef = site?.siteReference ?? site?.name
            quotation.subject = "\(project.name) - \(resolvedPricingMode)"
        }
        quotation.deliveryMethod = "BY EMAIL ONLY"
        // Minimum hire is an option per quotation, off until switched on;
        // the months default from Settings.
        quotation.minimumHireMonths = settings.defaultMinimumHireMonths ?? 2
        quotation.minimumHireEnabled = false
        quotationsStore.insert(quotation)
        logActivity(projectId: projectId, sourceBOQId == nil ? "Quotation created (\(resolvedPricingMode))" : "Quotation created from BOQ", reference: quotation.quotationNumber)

        if let boqId = sourceBOQId {
            let sourceItems = boqLineItemsStore.readAll()
                .filter { $0.boqId == boqId }
                .sorted { $0.sortOrder < $1.sortOrder }
            let copied: [QuotationLineItem] = sourceItems.enumerated().map { index, item in
                QuotationLineItem(
                    id: makeId("qitem"), quotationId: quotation.id, sourceKey: item.sourceKey,
                    priceListItemId: item.priceListItemId, itemCode: item.itemCode,
                    itemDescription: item.itemDescription, unit: item.unit, quantity: item.quantity.rounded(),
                    appliedUnitPrice: item.appliedUnitPrice, section: item.section, sortOrder: index,
                    priceListUnitPrice: item.priceListUnitPrice
                )
            }
            quotationLineItemsStore.insertMany(copied)
        }
        return quotation
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
        let imported: [QuotationLineItem] = boqItems.enumerated().map { index, item in
            // Same mode: keep the BOQ's own price (its mark-up and any
            // hand-typed price). Different mode: re-price in HKD with the
            // BOQ's mark-up.
            var price = item.appliedUnitPrice
            var listPrice = item.priceListUnitPrice
            if boq.pricingMode != pricingMode, let plId = item.priceListItemId, let pl = priceItems.first(where: { $0.id == plId }),
               let p = boqPrice(for: pl, mode: pricingMode, markupPercent: boq.markupPercent ?? 0, rates: rates) {
                price = p
                listPrice = p
            }
            return QuotationLineItem(
                id: makeId("qitem"), quotationId: quotationId, sourceKey: item.sourceKey,
                priceListItemId: item.priceListItemId, itemCode: item.itemCode,
                itemDescription: item.itemDescription, unit: item.unit, quantity: item.quantity.rounded(),
                appliedUnitPrice: price, section: item.section, sortOrder: startOrder + index,
                priceListUnitPrice: listPrice
            )
        }
        allQuotationItems.append(contentsOf: imported)
        quotationLineItemsStore.writeAll(allQuotationItems)

        qs[qIndex].sourceBOQId = boqId
        qs[qIndex].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
        logActivity(projectId: qs[qIndex].projectId, "Items imported from \(boq.boqNumber)", reference: qs[qIndex].quotationNumber)
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
        return QuotationDetail(
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
            markupPercent: q.markupPercent,
            effectiveUnitPrices: Dictionary(items.map { ($0.id, effectiveUnitPrice($0, q)) }, uniquingKeysWith: { a, _ in a }),
            lineTotals: Dictionary(items.map { ($0.id, doubleOf(quotationLineTotal($0, q))) }, uniquingKeysWith: { a, _ in a }),
            blocks: quotationBlocks(for: q.id), otherChargesTotal: totals.otherTotal,
            keyTerms: q.keyTerms, standardKeyTerms: getCompanySettings().quotationTerms ?? defaultQuotationTerms
        )
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
        if oldMode != pricingMode, let project = projectsStore.readAll().first(where: { $0.id == qs[index].projectId }),
           qs[index].subject == "\(project.name) - \(oldMode)" {
            // The subject line still reads "<project> - Rental": keep it in step.
            qs[index].subject = "\(project.name) - \(pricingMode)"
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
        let markup = q.sourceBOQId.flatMap { getBOQ(id: $0)?.markupPercent } ?? 0
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
    func deleteQuotation(id: String) -> String? {
        guard let q = getQuotation(id: id) else { return "Quotation not found." }
        guard q.status == "Draft" else { return "Only draft quotations can be deleted." }
        var qs = quotationsStore.readAll()
        qs.removeAll { $0.id == id }
        quotationsStore.writeAll(qs)
        logActivity(projectId: q.projectId, "Draft quotation deleted", reference: q.quotationNumber)
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
        invoiceLineItemsStore.insertMany(copied)
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
    func recordInvoicePayment(id: String, amount: Double) -> String? {
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
        logActivity(projectId: invs[index].projectId, "Payment recorded: \(getCompanySettings().currency) \(formatMoney(amount))\(totals.balanceDue <= 0 ? " — paid in full" : "")", reference: invs[index].invoiceNumber)
        return nil
    }

    /// Draft only — an issued invoice is cancelled, never deleted
    /// (section 22: "issued financial documents should not be casually
    /// deleted; prefer cancellation/archive mechanisms").
    func deleteInvoice(id: String) -> String? {
        guard let inv = getInvoice(id: id) else { return "Invoice not found." }
        guard inv.status == "Draft" else { return "Only draft invoices can be deleted — cancel it instead." }
        var invs = invoicesStore.readAll()
        invs.removeAll { $0.id == id }
        invoicesStore.writeAll(invs)
        logActivity(projectId: inv.projectId, "Draft invoice deleted", reference: inv.invoiceNumber)
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
        let note = DeliveryNote(
            id: makeId("dn"), projectId: projectId, sourceQuotationId: sourceQuotationId, sourceInvoiceId: sourceInvoiceId,
            deliveryNoteNumber: nextDeliveryNoteNumber(projectNumber: projectNumber, projectId: projectId),
            status: "Draft", deliveryDate: nowISO(), deliveryAddress: siteAddress, deliveredBy: nil, receivedBy: nil,
            notes: nil, createdAt: nowISO(), updatedAt: nowISO()
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
            clientName: client?.companyName, siteName: site?.name, lineItems: items
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

    func updateDeliveryNoteHeader(id: String, deliveryAddress: String?, deliveredBy: String?, receivedBy: String?, notes: String?) -> String? {
        var notesArr = deliveryNotesStore.readAll()
        guard let index = notesArr.firstIndex(where: { $0.id == id }) else { return "Delivery note not found." }
        guard notesArr[index].status == "Draft" else { return "This delivery note is issued and can no longer be edited." }

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
        if changed { logActivity(projectId: notesArr[index].projectId, "Delivery note \(status == "Draft" ? "returned to draft" : status.lowercased())", reference: notesArr[index].deliveryNoteNumber) }
        return nil
    }

    /// Draft only — same "don't casually delete a formal document" rule
    /// as BOQs/Quotations/Invoices (section 25).
    func deleteDeliveryNote(id: String) -> String? {
        guard let dn = getDeliveryNote(id: id) else { return "Delivery note not found." }
        guard dn.status == "Draft" else { return "Only draft delivery notes can be deleted." }
        var notesArr = deliveryNotesStore.readAll()
        notesArr.removeAll { $0.id == id }
        deliveryNotesStore.writeAll(notesArr)
        logActivity(projectId: dn.projectId, "Draft delivery note deleted", reference: dn.deliveryNoteNumber)
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

    /// The drawings linked to one BOQ or quotation.
    func listDrawings(linkedKind: String, linkedId: String) -> [ProjectDrawingSummary] {
        drawingSummaries(drawingsStore.readAll().filter { !$0.isArchived && $0.linkedKind == linkedKind && $0.linkedId == linkedId })
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
    private let rowHeight: CGFloat = 24.1
    private let cellPitch: CGFloat = 14.25

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
        textAtInk("Page \(pageNumber)", inkRight: 552.0 + x, baseline: 827.25 + y, font: times(9, italic: true), color: grey)
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

    private func drawOpening(_ doc: LetterDocument) {
        let blockLeft = 47.75 + dx
        let firstBaseline: CGFloat = 104.25
        let pitch: CGFloat = 15.75

        var left: [(String, NSFont)] = wrap(doc.clientName, body(12, bold: true), 345).map { ($0, body(12, bold: true)) }
        for line in doc.clientLines {
            left += wrap(line, body(12), 345).map { ($0, body(12)) }
        }
        for (i, item) in left.enumerated() {
            text(item.0, x: blockLeft, baseline: firstBaseline + CGFloat(i) * pitch, font: item.1)
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

        var baseline = firstBaseline + CGFloat(max(left.count, refLine, 1) - 1) * pitch
        if let method = doc.deliveryMethod, !method.isEmpty {
            baseline += 19.5
            text(method, x: 550.5 + dx, baseline: baseline, font: body(13, bold: true), align: .right, underline: true)
            baseline += 21.0
        } else {
            baseline += 40.5
        }

        text(doc.title, x: pageWidth / 2, baseline: baseline, font: body(15, bold: true), align: .center, underline: true)
        if doc.status != "Issued" {
            text(doc.status.uppercased(), x: textRight, baseline: baseline, font: body(11, bold: true), color: LetterheadColor.grey, align: .right)
        }
        var last = baseline
        var next = baseline + 18.0
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
        top + height / 2 + 5.2 - CGFloat(lines - 1) * cellPitch / 2 + CGFloat(line) * cellPitch
    }

    private func cellLines(_ value: String, column: LetterColumn, font: NSFont, currencyWidth: CGFloat) -> [String] {
        let available = column.width - 10.5 - (column.kind == .money ? currencyWidth + 4 : 0)
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
            }
        }
        if column.kind == .money, let first = lines.first, !first.isEmpty {
            text(currency, x: left + 5.25, baseline: cellBaseline(top: top, height: height, lines: 1, line: 0), font: font)
        }
    }

    private func drawHeaderRow(_ columns: [LetterColumn], _ edges: [CGFloat]) {
        let top = cursor
        hRule(edges, top)
        hRule(edges, top + rowHeight)
        for x in edges { vRule(x, top, rowHeight) }
        let font = body(11, bold: true)
        for (i, column) in columns.enumerated() {
            text(column.title, x: (edges[i] + edges[i + 1] + rule) / 2,
                 baseline: cellBaseline(top: top, height: rowHeight, lines: 1, line: 0), font: font, align: .center)
        }
        cursor += rowHeight
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

    /// A hanging-indent paragraph (see `LetterParagraph.hanging`). A long
    /// label pushes the text column right; the text always keeps at least
    /// 120pt. Returns the last baseline used.
    private func drawHanging(marker: String, lines: [String], left: CGFloat, indent: CGFloat?, colon: Bool, firstBaseline: CGFloat) -> CGFloat {
        let font = body(11)
        let markerX = textLeft + left
        let markerWidth = marker.isEmpty ? 0 : lineWidth(makeLine(marker, font, .black))
        var textX = textLeft + (indent ?? (left + max(18, markerWidth + 6)))
        if !marker.isEmpty { textX = max(textX, markerX + markerWidth + (colon ? 7.5 : 5)) }
        textX = min(textX, textRight - 120)
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

    /// Set by `generate` after a trial layout: the document needs more
    /// than one page.
    private var documentIsLong = false

    private func drawSections(_ sections: [LetterSection]) {
        var afterTable = true
        for section in sections {
            var baseline = cursor + (afterTable ? 27.0 : 33.0)
            afterTable = false
            if section.alwaysNewPage || (section.newPageUnlessSinglePage && documentIsLong) {
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

    private func drawClosingLine(_ line: String) {
        var baseline = cursor + 69.0
        if baseline > contentBottom {
            newPage()
            baseline = continuationBaseline
        }
        text(line, x: pageWidth / 2, baseline: baseline, font: times(10.5, italic: true), align: .center)
        cursor = baseline
    }

    // MARK: entry point

    func generate(_ doc: LetterDocument) -> Data {
        // Trial layout (discarded) to find out whether everything fits on
        // one page; if not, sections marked for it start on a new page.
        if doc.sections.contains(where: { $0.newPageUnlessSinglePage }), let trial = PDFGenerator(paperSize: paperSize) {
            _ = trial.layOut(doc)
            documentIsLong = trial.pageNumber > 1
        }
        return layOut(doc)
    }

    private func layOut(_ doc: LetterDocument) -> Data {
        pageNumber = 0
        beginPage()
        drawOpening(doc)
        drawTable(doc)
        drawSections(doc.sections)
        drawSignatures(doc.signatures, afterTable: doc.sections.isEmpty)
        if let closing = doc.closingLine { drawClosingLine(closing) }
        endPage()
        context.closePDF()
        return mutableData as Data
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
        let suffix = kind == "Before Restore" ? "_BeforeRestore" : ""
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
// MARK: - Native bridge (replaces main.js's ipcMain handlers)
// =====================================================================

final class NativeBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    weak var window: NSWindow?
    let db: AppDatabase
    let storage: FileStorage
    let backups: BackupManager
    /// Only one backup or restore may run at a time.
    private var backupInProgress = false
    /// A parsed-but-not-yet-applied price import, keyed by the preview's
    /// token, so the person can review it before anything changes.
    private var pendingPriceImport: (token: String, sourceKey: String, rows: [ParsedPriceRow])?

    init(db: AppDatabase, storage: FileStorage) {
        self.db = db
        self.storage = storage
        self.backups = BackupManager(db: db, storage: storage)
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
        case "boq:updateNotes":
            let boqId = (payload["id"] as? String) ?? ""
            let notes = payload["notes"] as? String
            db.updateBOQNotes(id: boqId, notes: notes)
            respondNull(id: id)
        case "boq:delete":
            let boqId = (payload["id"] as? String) ?? ""
            if let error = db.deleteBOQ(id: boqId) {
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
        case "quotations:removeBlock":
            let error = db.removeQuotationBlock(id: (payload["id"] as? String) ?? "")
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
            if let error = db.deleteQuotation(id: qid) {
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
            if let error = db.recordInvoicePayment(id: invId, amount: amount) {
                respond(id: id, encodable: InvoiceActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: InvoiceActionResult(ok: true, error: nil))
            }
        case "invoices:delete":
            let invId = (payload["id"] as? String) ?? ""
            if let error = db.deleteInvoice(id: invId) {
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
            if let error = db.deleteDeliveryNote(id: dnId) {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: true, error: nil))
            }
        case "deliveryNotes:exportPDF":
            let dnId = (payload["id"] as? String) ?? ""
            handleExportDeliveryNotePDF(id: id, deliveryNoteId: dnId)

        case "boq:updateDetails":
            let error = db.updateBOQDetails(id: (payload["id"] as? String) ?? "", pricingMode: payload["pricingMode"] as? String,
                                            markupPercent: payload["markupPercent"] as? Double,
                                            structure: payload["structure"] as? String, updateStructure: payload.keys.contains("structure"))
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:moveLineItem":
            let error = db.moveBOQLineItem(id: (payload["id"] as? String) ?? "", direction: (payload["direction"] as? Int) ?? 1)
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
        case "boq:print":
            handleExportBOQPDF(id: id, boqId: (payload["id"] as? String) ?? "", mode: .print)
        case "quotations:print":
            handleExportQuotationPDF(id: id, quotationId: (payload["id"] as? String) ?? "", mode: .print)
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
           let price = db.boqPrice(for: pl, mode: boq.pricingMode, markupPercent: boq.markupPercent ?? 0, rates: db.conversionRates()) {
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
                                              weightKg: payload["weightKg"] as? Double, updateWeight: payload.keys.contains("weightKg")) {
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
        if let error = db.updateDeliveryNoteHeader(id: dnId, deliveryAddress: deliveryAddress, deliveredBy: deliveredBy, receivedBy: receivedBy, notes: notes) {
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
    private func deliverRenderedPDF(id: String, mode: PDFMode, company: CompanySettings, projectNumber: String, subfolder: String, documentNumber: String, docTypeTag: String, render: (PDFGenerator) -> Data) {
        let paper = company.paperSize ?? "A4"
        guard let generator = PDFGenerator(paperSize: paper) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Could not prepare the document.", path: nil))
            return
        }
        let data = render(generator)

        if mode == .print {
            guard let document = PDFDocument(data: data), let window = window else {
                respond(id: id, encodable: PDFExportResult(ok: false, error: "Could not prepare the document for printing.", path: nil))
                return
            }
            let info = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo.shared
            info.paperSize = paper == "Letter" ? NSSize(width: 612, height: 792) : NSSize(width: 595.28, height: 841.89)
            info.topMargin = 0; info.bottomMargin = 0; info.leftMargin = 0; info.rightMargin = 0
            info.jobDisposition = .spool
            if let op = document.printOperation(for: info, scalingMode: .pageScaleNone, autoRotate: false) {
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

        let safeNumber = documentNumber.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
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
            if let v = nonBlank(c.address) { lines.append(v) }
            let cityLine = [c.city, c.postalCode].compactMap { nonBlank($0) }.joined(separator: " ")
            if !cityLine.isEmpty { lines.append(cityLine) }
            if let v = nonBlank(c.country) { lines.append(v) }
        }
        if let v = nonBlank(c.contactPerson) { lines.append("Attn: \(v)") }
        return (c.companyName, lines)
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
        if let title = nonBlank(block.title) { rows.append(.section(title)) }
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

    private func handleExportBOQPDF(id: String, boqId: String, mode: PDFMode = .export) {
        guard let detail = db.getBOQDetail(id: boqId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "BOQ not found.", path: nil))
            return
        }
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
        var rows: [LetterTableRow] = detail.lineItems.enumerated().map { index, item in
            .item([String(index + 1), lineDescription(item.itemDescription, notes: item.notes), item.unit, formatQuantity(item.quantity),
                   item.weightKg.map { formatMoney($0) } ?? "—",
                   item.weightKg.map { formatMoney($0 * item.quantity.rounded()) } ?? "—"])
        }
        rows.append(.summary(label: "Total Weight:", value: "\(formatMoney(detail.totalWeightKg)) kg", emphasized: true))

        let letter = LetterDocument(
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
        deliverRenderedPDF(id: id, mode: mode, company: company, projectNumber: detail.projectNumber, subfolder: "BOQ",
                           documentNumber: detail.boqNumber, docTypeTag: "BOQ") { $0.generate(letter) }
    }

    private func handleExportQuotationPDF(id: String, quotationId: String, mode: PDFMode = .export) {
        guard let detail = db.getQuotationDetail(id: quotationId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Quotation not found.", path: nil))
            return
        }
        let company = db.getCompanySettings()
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

        let letter = LetterDocument(
            number: detail.quotationNumber, status: detail.status, title: "QUOTATION",
            clientName: client.name, clientLines: client.lines,
            refRows: [("Our Ref. No.", detail.quotationNumber), ("Your Ref. No.", detail.clientRef ?? ""),
                      ("Site Ref.", nonBlank(detail.siteRef) ?? detail.siteName ?? ""), ("Date", letterDate(detail.quotationDate))],
            deliveryMethod: nonBlank(detail.deliveryMethod), salutation: "Dear Sir / Madam,",
            subject: "Re: \(nonBlank(detail.subject) ?? "\(detail.projectName) - \(detail.pricingMode)")",
            intro: "We thank you for your inquiry related to the item above, the following is our quotation on the job.",
            currencySymbol: currencySymbol(company), columns: pricedColumns, rows: rows,
            sections: remarks(detail.notes) + [LetterSection(heading: "Terms and Conditions", paragraphs: terms, newPageUnlessSinglePage: true,
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
        deliverRenderedPDF(id: id, mode: mode, company: company, projectNumber: detail.projectNumber, subfolder: "Quotations",
                           documentNumber: detail.quotationNumber, docTypeTag: "Quotation") { $0.generate(letter) }
    }

    private func handleExportInvoicePDF(id: String, invoiceId: String, mode: PDFMode = .export) {
        guard let detail = db.getInvoiceDetail(id: invoiceId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Invoice not found.", path: nil))
            return
        }
        let company = db.getCompanySettings()
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

        let letter = LetterDocument(
            number: detail.invoiceNumber, status: detail.status, title: "INVOICE",
            clientName: client.name, clientLines: client.lines, refRows: refRows,
            deliveryMethod: nil, salutation: nil,
            subject: "Re: \(nonBlank(quotation?.subject) ?? "\(detail.projectNumber) \(detail.projectName)")", intro: nil,
            currencySymbol: currencySymbol(company), columns: pricedColumns, rows: rows,
            sections: sections, signatures: [companySignature(company)], closingLine: nil
        )
        deliverRenderedPDF(id: id, mode: mode, company: company, projectNumber: detail.projectNumber, subfolder: "Invoices",
                           documentNumber: detail.invoiceNumber, docTypeTag: "Invoice") { $0.generate(letter) }
    }

    private func handleExportDeliveryNotePDF(id: String, deliveryNoteId: String, mode: PDFMode = .export) {
        guard let detail = db.getDeliveryNoteDetail(id: deliveryNoteId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Delivery note not found.", path: nil))
            return
        }
        let company = db.getCompanySettings()
        let client = clientBlock(projectNumber: detail.projectNumber, fallbackName: detail.clientName)
        let columns = [
            LetterColumn(title: "No", width: 29.25, kind: .center),
            LetterColumn(title: "Item Description", width: 327.75, kind: .left),
            LetterColumn(title: "Unit", width: 75.0, kind: .center),
            LetterColumn(title: "Qty", width: 75.0, kind: .center),
        ]
        let rows: [LetterTableRow] = detail.lineItems.enumerated().map { index, item in
            .item([String(index + 1), lineDescription(item.itemDescription, notes: item.notes), item.unit, formatQuantity(item.quantity)])
        }

        let letter = LetterDocument(
            number: detail.deliveryNoteNumber, status: detail.status, title: "DELIVERY NOTE",
            clientName: client.name, clientLines: client.lines,
            refRows: [("D/N No.", detail.deliveryNoteNumber), ("Project No.", detail.projectNumber),
                      ("Site Ref.", siteReference(projectNumber: detail.projectNumber)), ("Date", letterDate(detail.deliveryDate))],
            deliveryMethod: nil, salutation: nil, subject: "Re: \(detail.projectNumber) \(detail.projectName)",
            intro: nonBlank(detail.deliveryAddress).map { "Delivery address: \($0)" },
            currencySymbol: currencySymbol(company), columns: columns, rows: rows,
            sections: remarks(detail.notes),
            signatures: [
                LetterSignature(heading: "Delivered by", lines: [
                    LetterSignatureLine(text: company.companyName),
                    LetterSignatureLine(text: "Name", colon: true, value: nonBlank(detail.deliveredBy)),
                    LetterSignatureLine(text: "Date", colon: true),
                ]),
                LetterSignature(heading: "Received in good condition by", lines: [
                    LetterSignatureLine(text: client.name),
                    LetterSignatureLine(text: "Name", colon: true, value: nonBlank(detail.receivedBy)),
                    LetterSignatureLine(text: "Date", colon: true),
                ]),
            ],
            closingLine: nil
        )
        deliverRenderedPDF(id: id, mode: mode, company: company, projectNumber: detail.projectNumber, subfolder: "Delivery Notes",
                           documentNumber: detail.deliveryNoteNumber, docTypeTag: "DeliveryNote") { $0.generate(letter) }
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
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = drawingContentTypes
        panel.message = "Choose a drawing: PDF, DWG, DXF or an image. The original stays where it is; a copy goes in the project's Drawings folder."

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let sourceURL = panel.url else {
                self.respondNull(id: id)
                return
            }
            let originalName = sourceURL.lastPathComponent
            let meaningfulName = "\(projectNumber)_Drawing_\(originalName)"
            do {
                let destination = try self.storage.copyFileIntoProject(
                    source: sourceURL, projectNumber: projectNumber,
                    subfolder: "Drawings", meaningfulFilename: meaningfulName
                )
                self.db.recordDrawing(projectId: project.id, originalName: originalName, storedURL: destination, linkedKind: linkedKind, linkedId: linkedId)
                self.respond(id: id, encodable: UploadDrawingResult(originalName: originalName, destination: destination.path))
            } catch {
                self.respondError(id: id, message: "Could not copy file: \(error.localizedDescription)")
            }
        }
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
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        // Deliberately no allowedContentTypes restriction here — section
        // 34's general documents (contracts, correspondence, etc.) can
        // be any file type, unlike drawings.

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let sourceURL = panel.url else {
                self.respondNull(id: id)
                return
            }
            let originalName = sourceURL.lastPathComponent
            let meaningfulName = "\(projectNumber)_\(category.replacingOccurrences(of: " ", with: ""))_\(originalName)"
            do {
                let destination = try self.storage.copyFileIntoProject(
                    source: sourceURL, projectNumber: projectNumber,
                    subfolder: "Documents", meaningfulFilename: meaningfulName
                )
                let document = self.db.recordDocument(projectId: project.id, originalName: originalName, category: category, storedURL: destination)
                self.respond(id: id, encodable: document)
            } catch {
                self.respondError(id: id, message: "Could not copy file: \(error.localizedDescription)")
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
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let sourceURL = panel.url else {
                self.respondNull(id: id)
                return
            }
            let subfolder: String
            switch category {
            case "Employment Contract": subfolder = "Contracts"
            case "Certification", "Training Certificate": subfolder = "Certificates"
            default: subfolder = "Other"
            }
            let originalName = sourceURL.lastPathComponent
            let meaningfulName = "\(worker.workerNumber)_\(category.replacingOccurrences(of: " ", with: ""))_\(originalName)"
            do {
                let destination = try self.storage.copyFile(
                    source: sourceURL,
                    into: self.storage.workerFolder(worker.workerNumber).appendingPathComponent(subfolder, isDirectory: true),
                    meaningfulFilename: meaningfulName
                )
                let doc = self.db.recordWorkerDocument(workerId: worker.id, originalName: originalName, category: category, expiryDate: expiryDate, storedURL: destination)
                self.respond(id: id, encodable: doc)
            } catch {
                self.respondError(id: id, message: "Could not copy file: \(error.localizedDescription)")
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
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            guard response == .OK, let sourceURL = panel.url else {
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
            let originalName = sourceURL.lastPathComponent
            do {
                let destination = try self.storage.copyFile(
                    source: sourceURL,
                    into: self.storage.administrationCategoryFolder(folderName),
                    meaningfulFilename: originalName
                )
                let doc = self.db.recordAdminDocument(originalName: originalName, category: category, expiryDate: expiryDate, storedURL: destination)
                self.respond(id: id, encodable: doc)
            } catch {
                self.respondError(id: id, message: "Could not copy file: \(error.localizedDescription)")
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
        guard !backupInProgress else {
            respond(id: id, encodable: BackupResult(ok: false, error: "A backup or restore is already running.", backup: nil, safetyBackup: nil))
            return
        }
        backupInProgress = true
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

    private func handleOpenFile(id: String, path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            respond(id: id, encodable: FileActionResult(ok: false, error: "This file could not be found. It may have been moved or deleted."))
            return
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
        respond(id: id, encodable: FileActionResult(ok: true, error: nil))
    }

    private func handleRevealFile(id: String, path: String) {
        guard FileManager.default.fileExists(atPath: path) else {
            respond(id: id, encodable: FileActionResult(ok: false, error: "This file could not be found. It may have been moved or deleted."))
            return
        }
        storage.revealInFinder(URL(fileURLWithPath: path))
        respond(id: id, encodable: FileActionResult(ok: true, error: nil))
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

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var bridge: NativeBridge!
    var db: AppDatabase!
    var storage: FileStorage!

    func applicationDidFinishLaunching(_ notification: Notification) {
        registerBundledFonts()
        setupDataLayer()
        setupWindow()
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
        let dataDir = appSupport.appendingPathComponent("ScaffoldPro", isDirectory: true).appendingPathComponent("data", isDirectory: true)
        try? fm.createDirectory(at: dataDir, withIntermediateDirectories: true)

        db = AppDatabase(dataDir: dataDir)

        let documentsRoot = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let backupsRoot = dataDir.deletingLastPathComponent().appendingPathComponent("Backups", isDirectory: true)
        storage = FileStorage(documentsRoot: documentsRoot, companyFolderName: "ScaffoldPro", backupsRoot: backupsRoot)
        storage.ensureRootFoldersExist()
        storage.moveLegacyBackups()

        seedPriceListsIfNeeded()
        db.fixScafomCurrencyIfNeeded()
        db.applyDeliveryChargeUpdateIfNeeded()
        db.movePaymentTermsIntoKeyTermsIfNeeded()
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

        // Go — ⌘1…⌘7 for the sidebar sections, ⌘[ / ⌘] for back/forward.
        let go = NSMenu(title: "Go")
        let sections: [(String, String)] = [("Dashboard", "index.html"), ("Material List", "price-lists.html"), ("Sites", "sites.html"),
                                            ("Clients", "clients.html"), ("Projects", "projects.html"), ("Admin", "admin.html"),
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

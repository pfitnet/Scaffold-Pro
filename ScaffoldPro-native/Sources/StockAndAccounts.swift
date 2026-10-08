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
// MARK: - Stock list
//
// Every change to the stock is a movement: + into the yard, − out of it.
//   Opening / Purchase   received into the yard (+)
//   Delivery             out to a project's site on hire (−), from a delivery
//                        note once it's issued and its signed copy is in
//   Sale                 out to a project for good (−), the same way, for a sale
//   Return               back from a project (+), maybe against one delivery note
//   RentIn / RentReturn  rented from another company into the yard (+), and
//                        sent back to it (−); not ours, so not owned
//   WriteOff             lost, scrapped or damaged (−)
//   Adjustment           a stock count's difference (±)
// In the yard = the sum of all movements. On hire, per project = delivered
// − returned. Rented, per company = rented in − sent back. Owned = in the
// yard + on hire − rented (rented pieces are in the yard or on site, but
// aren't ours).
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
    /// Lines recorded together on the Stock page (one receipt, one return,
    /// one stock count) share an id, so they're shown and removed together.
    var batchId: String? = nil
    /// A return answering one signed delivery note (Stock › Returns).
    var returnOfDeliveryNoteId: String? = nil
    /// RentIn / RentReturn: the company they're rented from.
    var company: String? = nil
}

/// What a batch from the Stock page came to.
struct StockBatchResult: Codable {
    var ok: Bool
    var error: String?
    /// Lines saved, and lines left out (a count that matched; an unknown item).
    var saved: Int
    var skipped: [String]
    var batchId: String?
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

struct StockCompanyQuantity: Codable {
    var company: String
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
    /// Rented from other companies (in the yard or on site, not owned), and
    /// from whom.
    var rented: Double = 0
    var rentedByCompany: [StockCompanyQuantity] = []
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
    /// Signed delivery notes with items still on site (Stock › Returns).
    var returns: [DeliveryReturnRow] = []
    /// Companies to suggest for renting from: those already rented from,
    /// suppliers (Expenses) and clients.
    var companies: [String] = []
}

/// One item of a signed delivery note: sent, back, still on site.
struct DeliveryReturnLine: Codable {
    var itemKey: String
    var priceListItemId: String?
    var itemCode: String
    var itemName: String
    var unit: String
    var delivered: Double
    var returned: Double
    var outstanding: Double
}

/// A signed delivery note with items still on site, and when to ask
/// whether they're back.
struct DeliveryReturnRow: Codable {
    var deliveryNoteId: String
    var deliveryNoteNumber: String
    var projectId: String
    var projectNumber: String
    var projectName: String
    var siteName: String?
    var clientName: String?
    var deliveryDate: String
    var signedAt: String?
    /// yyyy-MM-dd; due = on or before today.
    var checkDate: String
    var due: Bool
    var delivered: Double
    var returned: Double
    var outstanding: Double
    var lines: [DeliveryReturnLine]
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
        var rent: [String: [String: Double]] = [:]
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
            if (m.kind == "RentIn" || m.kind == "RentReturn"), let c = nonBlank(m.company) {
                rent[m.itemKey, default: [:]][c, default: 0] += m.quantity
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
        for (key, byCompany) in rent {
            let list = byCompany.filter { abs($0.value) > 0.0001 }.map { StockCompanyQuantity(company: $0.key, quantity: $0.value) }
                .sorted { $0.company.localizedCaseInsensitiveCompare($1.company) == .orderedAscending }
            rows[key]!.rentedByCompany = list
            rows[key]!.rented = list.reduce(0) { $0 + $1.quantity }
        }
        for key in order { rows[key]!.owned = rows[key]!.inYard + rows[key]!.onHire - rows[key]!.rented }
        let views = movements.sorted { ($0.date, $0.createdAt) > ($1.date, $1.createdAt) }.map {
            StockMovementView(movement: $0, projectNumber: $0.projectId.flatMap { projectById[$0]?.projectNumber },
                              automatic: $0.deliveryNoteId != nil)
        }
        var companies = Set(clientsStore.readAll().compactMap { nonBlank($0.companyName) })
        for m in movements { if let c = nonBlank(m.company) { companies.insert(c) } }
        for e in expensesStore.readAll() { if let c = nonBlank(e.supplier) { companies.insert(c) } }
        return StockData(items: order.compactMap { rows[$0] }, movements: views, projects: projects,
                         returns: deliveryReturns(movements: movements),
                         companies: companies.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending })
    }

    /// When to ask whether a signed delivery note's items are back: the day
    /// chosen, else the project's finish date, else 30 days after the signed
    /// copy came in.
    func returnCheckDay(_ note: DeliveryNote, project: Project?) -> String {
        if let d = validDay(note.returnCheckDate) { return d }
        let from = validDay(note.signedCopyAt) ?? validDay(note.deliveryDate) ?? todayYMD()
        if let finish = validDay(project?.expectedCompletionDate), finish > from { return finish }
        return addDays(from, 30) ?? from
    }

    /// Signed delivery notes with items still on site: what's still to come
    /// back, and when to ask. A return recorded against a note settles that
    /// note; other returns from the project settle its notes oldest first.
    func deliveryReturns(movements: [StockMovement]? = nil) -> [DeliveryReturnRow] {
        let all = movements ?? stockMovementsStore.readAll()
        let today = todayYMD()
        let notes = Dictionary(deliveryNotesStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let projects = Dictionary(projectsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let sites = Dictionary(sitesStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let clients = Dictionary(clientsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        // What each note booked out (on hire, not sold), item by item.
        var sent: [String: [String: Double]] = [:]
        var named: [String: StockMovement] = [:]
        for m in all where m.kind == "Delivery" {
            guard let nid = m.deliveryNoteId else { continue }
            sent[nid, default: [:]][m.itemKey, default: 0] -= m.quantity
            if named[m.itemKey] == nil { named[m.itemKey] = m }
        }
        var back: [String: [String: Double]] = [:]
        var pool: [String: [String: Double]] = [:]
        for m in all where m.kind == "Return" {
            guard let pid = m.projectId else { continue }
            var left = m.quantity
            if let nid = m.returnOfDeliveryNoteId, let out = sent[nid]?[m.itemKey] {
                let take = min(left, max(0, out - (back[nid]?[m.itemKey] ?? 0)))
                back[nid, default: [:]][m.itemKey, default: 0] += take
                left -= take
            }
            if left > 0.0001 { pool[pid, default: [:]][m.itemKey, default: 0] += left }
        }
        let ordered = sent.keys.compactMap { notes[$0] }
            .sorted { ($0.deliveryDate, $0.deliveryNoteNumber) < ($1.deliveryDate, $1.deliveryNoteNumber) }
        for note in ordered {
            for (key, out) in sent[note.id] ?? [:] {
                let free = pool[note.projectId]?[key] ?? 0
                guard free > 0.0001 else { continue }
                let take = min(free, max(0, out - (back[note.id]?[key] ?? 0)))
                back[note.id, default: [:]][key, default: 0] += take
                pool[note.projectId]?[key] = free - take
            }
        }
        var rows: [DeliveryReturnRow] = []
        for note in ordered {
            let lines = (sent[note.id] ?? [:]).compactMap { entry -> DeliveryReturnLine? in
                guard let m = named[entry.key], entry.value > 0.0001 else { return nil }
                let b = back[note.id]?[entry.key] ?? 0
                return DeliveryReturnLine(itemKey: entry.key, priceListItemId: m.priceListItemId, itemCode: m.itemCode, itemName: m.itemDescription,
                                          unit: m.unit, delivered: entry.value, returned: b, outstanding: max(0, entry.value - b))
            }.sorted { $0.itemCode.localizedStandardCompare($1.itemCode) == .orderedAscending }
            let outstanding = lines.reduce(0) { $0 + $1.outstanding }
            guard outstanding > 0.0001 else { continue }
            let p = projects[note.projectId]
            let check = returnCheckDay(note, project: p)
            rows.append(DeliveryReturnRow(
                deliveryNoteId: note.id, deliveryNoteNumber: note.deliveryNoteNumber, projectId: note.projectId,
                projectNumber: p?.projectNumber ?? "", projectName: p?.name ?? "",
                siteName: p.flatMap { sites[$0.siteId]?.name }, clientName: p.flatMap { clients[$0.clientId]?.companyName },
                deliveryDate: validDay(note.deliveryDate) ?? String(note.deliveryDate.prefix(10)), signedAt: validDay(note.signedCopyAt),
                checkDate: check, due: check <= today,
                delivered: lines.reduce(0) { $0 + $1.delivered }, returned: lines.reduce(0) { $0 + $1.returned },
                outstanding: outstanding, lines: lines))
        }
        return rows.sorted { ($0.checkDate, $0.deliveryNoteNumber) < ($1.checkDate, $1.deliveryNoteNumber) }
    }

    /// "Not yet": the day to ask again whether a delivery note's items are back.
    func setReturnCheckDate(deliveryNoteId: String, day: String?) -> String? {
        var notes = deliveryNotesStore.readAll()
        guard let i = notes.firstIndex(where: { $0.id == deliveryNoteId }) else { return "Delivery note not found." }
        guard let d = validDay(day) else { return "Enter a valid date." }
        notes[i].returnCheckDate = d
        deliveryNotesStore.writeAll(notes)
        return nil
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

    /// Many lines at once from the Stock page: one kind ("Purchase",
    /// "Return", "RentIn", "RentReturn", "WriteOff", "Count", "Opening"), one
    /// date, reference, notes, (for a return) project and maybe the signed
    /// delivery note it answers, (for renting) the company rented from, and its lines
    /// [{ priceListItemId, itemCode, itemDescription, unit, quantity }].
    /// Saved together, as one batch (one step to undo); a count records only
    /// the differences.
    func addStockMovements(_ payload: [String: Any]) -> StockBatchResult {
        let kind = (payload["kind"] as? String) ?? ""
        guard ["Opening", "Purchase", "Return", "RentIn", "RentReturn", "WriteOff", "Count"].contains(kind) else {
            return StockBatchResult(ok: false, error: "Choose what kind of stock change this is.", saved: 0, skipped: [], batchId: nil)
        }
        let lines = (payload["lines"] as? [[String: Any]]) ?? []
        guard !lines.isEmpty else { return StockBatchResult(ok: false, error: "Add at least one item.", saved: 0, skipped: [], batchId: nil) }
        var projectId = nonBlank(payload["projectId"] as? String)
        // A return answering a signed delivery note: from its project.
        let noteId = kind == "Return" ? nonBlank(payload["deliveryNoteId"] as? String) : nil
        let note: DeliveryNote? = noteId.flatMap { id in deliveryNotesStore.readAll().first(where: { $0.id == id }) }
        if let note = note { projectId = note.projectId }
        if kind == "Return" {
            guard let p = projectId, projectsStore.readAll().contains(where: { $0.id == p }) else {
                return StockBatchResult(ok: false, error: "Choose the project the items came back from.", saved: 0, skipped: [], batchId: nil)
            }
        }
        let renting = kind == "RentIn" || kind == "RentReturn"
        let company = renting ? nonBlank(payload["company"] as? String) : nil
        if renting && company == nil {
            return StockBatchResult(ok: false, error: "Enter the company they're rented from.", saved: 0, skipped: [], batchId: nil)
        }
        let date = validDay(payload["date"] as? String) ?? todayYMD()
        let reference = nonBlank(payload["reference"] as? String)
        let notes = nonBlank(payload["notes"] as? String)
        let existing = stockMovementsStore.readAll()
        var inYard: [String: Double] = [:]
        for m in existing { inYard[m.itemKey, default: 0] += m.quantity }
        let batchId = makeId("batch")
        var made: [StockMovement] = []
        var skipped: [String] = []
        var seen = Set<String>()
        for line in lines {
            let plId = nonBlank(line["priceListItemId"] as? String)
            var code = ((line["itemCode"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            var name = ((line["itemDescription"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            var unit = ((line["unit"] as? String) ?? "pc").trimmingCharacters(in: .whitespaces)
            if let plId = plId, let pl = priceListItem(id: plId) { code = pl.itemCode; name = pl.itemName; unit = pl.unit }
            guard !name.isEmpty else { skipped.append("A line without an item"); continue }
            let key = AppDatabase.stockKey(priceListItemId: plId, itemCode: code, description: name)
            // The same item twice in one batch: added together (a count keeps the last).
            let value = ((line["quantity"] as? Double) ?? Double((line["quantity"] as? Int) ?? -1)).rounded()
            var quantity: Double
            switch kind {
            case "Count":
                guard value >= 0 else { skipped.append("\(name): no count"); continue }
                if seen.contains(key) { made.removeAll { $0.itemKey == key } }
                quantity = value - (inYard[key] ?? 0)
                guard abs(quantity) > 0.0001 else { skipped.append("\(name): count matches"); seen.insert(key); continue }
            case "WriteOff", "RentReturn":
                guard value > 0 else { skipped.append("\(name): no quantity"); continue }
                quantity = -value
            default:
                guard value > 0 else { skipped.append("\(name): no quantity"); continue }
                quantity = value
            }
            seen.insert(key)
            made.append(StockMovement(
                id: makeId("stock"), date: date, kind: kind == "Count" ? "Adjustment" : kind,
                itemKey: key, priceListItemId: plId, itemCode: code, itemDescription: name, unit: unit.isEmpty ? "pc" : unit,
                quantity: quantity, projectId: kind == "Return" ? projectId : nil, deliveryNoteId: nil,
                reference: reference, notes: notes, createdAt: nowISO(), batchId: batchId,
                returnOfDeliveryNoteId: note?.id, company: company))
        }
        guard !made.isEmpty else {
            return StockBatchResult(ok: false, error: kind == "Count" ? "Every count matches the stock already — nothing to change." : "Enter a quantity for at least one item.",
                                    saved: 0, skipped: skipped, batchId: nil)
        }
        stockMovementsStore.writeAll(existing + made)
        // Part of a delivery note back: ask about the rest in two weeks.
        if let note = note, let next = addDays(todayYMD(), 14) { _ = setReturnCheckDate(deliveryNoteId: note.id, day: next) }
        let label = ["Opening": "Opening stock", "Purchase": "Stock received", "Return": "Stock returned", "RentIn": "Stock rented in",
                     "RentReturn": "Rented stock sent back", "WriteOff": "Stock written off", "Count": "Stock count"][kind] ?? "Stock"
        let who = company.map { " (\($0))" } ?? ""
        logActivity(projectId: kind == "Return" ? projectId : nil, "\(label) — \(made.count) item\(made.count == 1 ? "" : "s")\(who)",
                    reference: reference ?? note?.deliveryNoteNumber)
        return StockBatchResult(ok: true, error: nil, saved: made.count, skipped: skipped, batchId: batchId)
    }

    /// A batch's lines removed together (not ones from delivery notes).
    func deleteStockBatch(batchId: String) -> String? {
        var all = stockMovementsStore.readAll()
        let before = all.count
        all.removeAll { $0.batchId == batchId && $0.deliveryNoteId == nil }
        guard all.count != before else { return "Stock entry not found." }
        stockMovementsStore.writeAll(all)
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

    /// A delivery note's items are out of the yard once it's issued and its
    /// signed copy is in (on hire to its project's site, or sold); not
    /// before, and not once it's cancelled or back to draft.
    func syncDeliveryStock(_ note: DeliveryNote) {
        let booked = stockMovementsStore.readAll().contains { $0.deliveryNoteId == note.id }
        let due = note.status == "Issued" && note.signedCopyPath != nil
        if due && !booked { recordDeliveryStock(note) } else if !due && booked { removeDeliveryStock(deliveryNoteId: note.id) }
    }

    /// Once: delivery notes issued but not signed no longer hold stock out
    /// (they used to from the moment they were issued).
    func bookStockOnSignedDeliveryNotesOnce() {
        let key = "ScaffoldPro.stockFromSignedDeliveryNotes"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let signed = Set(deliveryNotesStore.readAll().filter { $0.status == "Issued" && $0.signedCopyPath != nil }.map { $0.id })
        var all = stockMovementsStore.readAll()
        let before = all.count
        all.removeAll { m in m.deliveryNoteId.map { !signed.contains($0) } ?? false }
        if all.count != before { stockMovementsStore.writeAll(all) }
        UserDefaults.standard.set(true, forKey: key)
    }

    /// Books a delivery note's items out of the yard: on hire to its
    /// project, or sold if it's for a sale.
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

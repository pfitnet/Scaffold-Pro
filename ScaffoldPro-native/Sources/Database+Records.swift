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

extension AppDatabase {
    // ---- Document rows (client/site pages, Dashboard, search) ----

    func todayYMD() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    /// Every BOQ, quotation, invoice and delivery note — optionally only
    /// for a set of projects — as display rows with totals worked out.
    func documentRows(projectIds: Set<String>? = nil, withAuthors: Bool = true) -> [DocRow] {
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
        // Who made each one and who last worked on it (not needed for search).
        guard withAuthors else { return rows }
        let files = ["BOQ": "boqs.json", "Quotation": "quotations.json", "Invoice": "invoices.json", "Delivery Note": "delivery_notes.json"]
        var indexes: [String: [String: DocAuthors]] = [:]
        let history = activityAuthors()
        for i in rows.indices {
            guard let file = files[rows[i].kind] else { continue }
            if indexes[file] == nil { indexes[file] = authorsIndex(file, history: history) }
            let a = indexes[file]?[rows[i].id] ?? authors(nil, number: rows[i].number, history: history)
            rows[i].createdBy = a.createdBy
            rows[i].lastEditedBy = a.lastEditedBy
            rows[i].lastEditedAt = a.lastEditedAt
            rows[i].mine = a.mine
        }
        return rows
    }

    // ---- Who made / last worked on what ----

    /// This Mac's user: by the Mac (when recorded), else by name. Records
    /// from before names were kept count as everyone's.
    func isMine(device: String?, name: String?) -> Bool {
        if let d = device { return d == TeamSync.deviceId }
        if let n = nonBlank(name) { return n == TeamSync.memberName }
        return true
    }

    /// From the History (older documents, saved before names were kept):
    /// document number → who first and who last did something with it.
    func activityAuthors() -> [String: (first: String?, last: String?, lastDevice: String?, lastAt: String)] {
        var out: [String: (first: String?, last: String?, lastDevice: String?, lastAt: String)] = [:]
        for e in activityStore.readAll().sorted(by: { $0.createdAt < $1.createdAt }) {
            guard let ref = nonBlank(e.reference), nonBlank(e.by) != nil else { continue }
            let first = out[ref]?.first ?? e.by
            out[ref] = (first, e.by, e.device, e.createdAt)
        }
        return out
    }

    /// The names kept in a store's records (by record id).
    func authorsIndex(_ file: String, history: [String: (first: String?, last: String?, lastDevice: String?, lastAt: String)]) -> [String: DocAuthors] {
        guard let data = try? Data(contentsOf: dataDir.appendingPathComponent(file)),
              let list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return [:] }
        let numberKey = ["boqs.json": "boqNumber", "quotations.json": "quotationNumber", "invoices.json": "invoiceNumber",
                         "delivery_notes.json": "deliveryNoteNumber", "letters.json": "letterNumber", "projects.json": "projectNumber"][file] ?? "number"
        var out: [String: DocAuthors] = [:]
        for r in list {
            guard let id = r["id"] as? String else { continue }
            out[id] = authors(r, number: r[numberKey] as? String, history: history)
        }
        return out
    }

    func authors(_ record: [String: Any]?, number: String?, history: [String: (first: String?, last: String?, lastDevice: String?, lastAt: String)]) -> DocAuthors {
        let fromHistory = number.flatMap { history[$0] }
        let created = nonBlank(record?["createdBy"] as? String) ?? fromHistory?.first
        if let last = nonBlank(record?["lastEditedBy"] as? String) {
            return DocAuthors(createdBy: created, lastEditedBy: last, lastEditedAt: record?["lastEditedAt"] as? String,
                              mine: isMine(device: record?["lastEditedByDevice"] as? String, name: last))
        }
        if let h = fromHistory {
            return DocAuthors(createdBy: created, lastEditedBy: h.last, lastEditedAt: h.lastAt, mine: isMine(device: h.lastDevice, name: h.last))
        }
        return DocAuthors(createdBy: created, lastEditedBy: nil, lastEditedAt: nil, mine: true)
    }

    /// Every record's names in one store (e.g. "quotations.json"), by id —
    /// for the lists.
    func authorsByRecord(_ file: String) -> [String: DocAuthors] {
        authorsIndex(file, history: activityAuthors())
    }

    /// The documents linked to one: the BOQ a quotation came from, the
    /// quotation, the delivery notes made from it and the invoices billing
    /// it (from those delivery notes or the quotation itself).
    func documentChain(kind: String, id: String) -> [ChainLink] {
        let quotations = quotationsStore.readAll()
        let notes = deliveryNotesStore.readAll()
        let invoices = invoicesStore.readAll()
        var root: Quotation? = nil
        var boq: BillOfQuantities? = nil
        switch kind {
        case "quotation": root = quotations.first { $0.id == id }
        case "deliveryNote": root = notes.first { $0.id == id }?.sourceQuotationId.flatMap { qid in quotations.first { $0.id == qid } }
        case "invoice": root = invoices.first { $0.id == id }?.sourceQuotationId.flatMap { qid in quotations.first { $0.id == qid } }
        case "boq": boq = getBOQ(id: id)
        default: break
        }
        // A subsidiary follows the quotation it was split off (and its BOQ).
        let rootParent = root.flatMap { parentQuotation(of: $0, in: quotations) }
        if boq == nil { boq = (root?.sourceBOQId ?? rootParent?.sourceBOQId).flatMap { getBOQ(id: $0) } }
        var links: [ChainLink] = []
        if let b = boq {
            links.append(ChainLink(kind: "BOQ", id: b.id, number: b.boqNumber, status: b.status, url: "boq-editor.html?id=\(b.id)", current: kind == "boq" && b.id == id))
        }
        let chainQuotations = root.map { [$0] } ?? (kind == "boq" ? quotations.filter { $0.sourceBOQId == id }.sorted { $0.quotationNumber < $1.quotationNumber } : [])
        let link = { (q: Quotation, role: String) in
            ChainLink(kind: role, id: q.id, number: q.quotationNumber, status: q.status, url: "quotation-editor.html?id=\(q.id)", current: kind == "quotation" && q.id == id)
        }
        for q in chainQuotations {
            // Quotation › Subsidiaries: the quotation, then those split off it.
            if let parent = parentQuotation(of: q, in: quotations), q.id == root?.id {
                links.append(link(parent, "Quotation"))
                links.append(link(q, "Subsidiary"))
            } else {
                links.append(link(q, "Quotation"))
                for sub in quotations.filter({ parentQuotation(of: $0, in: quotations)?.id == q.id }).sorted(by: { $0.quotationNumber < $1.quotationNumber }) {
                    links.append(link(sub, "Subsidiary"))
                }
            }
        }
        let qids = Set(chainQuotations.map { $0.id })
        var dnList = notes.filter { $0.sourceQuotationId.map { qids.contains($0) } ?? false }
        // A delivery note made without a quotation: itself and its invoices.
        if kind == "deliveryNote", root == nil, let dn = notes.first(where: { $0.id == id }) { dnList = [dn] }
        let dnIds = Set(dnList.map { $0.id })
        for dn in dnList.sorted(by: { $0.deliveryNoteNumber < $1.deliveryNoteNumber }) {
            links.append(ChainLink(kind: "DeliveryNote", id: dn.id, number: dn.deliveryNoteNumber, status: dn.status, url: "delivery-note-editor.html?id=\(dn.id)", current: kind == "deliveryNote" && dn.id == id))
        }
        let invList = invoices.filter { inv in
            (inv.sourceQuotationId.map { qids.contains($0) } ?? false) || (inv.sourceDeliveryNoteIds ?? []).contains { dnIds.contains($0) } || (kind == "invoice" && inv.id == id)
        }
        for inv in invList.sorted(by: { $0.invoiceNumber < $1.invoiceNumber }) {
            links.append(ChainLink(kind: "Invoice", id: inv.id, number: inv.invoiceNumber, status: inv.status, url: "invoice-editor.html?id=\(inv.id)", current: kind == "invoice" && inv.id == id))
        }
        return links.count > 1 ? links : []
    }

    /// One document's (or project's) names, for its page.
    func documentAuthors(kind: String, id rawId: String, number: String? = nil) -> DocAuthors {
        // A project can be asked for by its code.
        let id = kind == "project" && rawId.isEmpty ? (number.flatMap { getProjectByNumber($0)?.id } ?? "") : rawId
        let file = ["boq": "boqs.json", "quotation": "quotations.json", "invoice": "invoices.json", "deliveryNote": "delivery_notes.json",
                    "letter": "letters.json", "project": "projects.json"][kind] ?? ""
        let history = activityAuthors()
        return authorsIndex(file, history: history)[id] ?? DocAuthors(createdBy: nil, lastEditedBy: nil, lastEditedAt: nil, mine: true)
    }

    /// The projects this Mac's user has worked on, most recent first: made
    /// or last changed by them, or with a document or History entry of theirs.
    func myRecentProjects(rows: [DocRow], limit: Int) -> [MyProject] {
        let projects = projectsStore.readAll()
        let clients = Dictionary(clientsStore.readAll().map { ($0.id, $0.companyName) }, uniquingKeysWith: { a, _ in a })
        let history = activityAuthors()
        let projectAuthors = authorsIndex("projects.json", history: history)
        var touched: [String: String] = [:]   // project number → latest time
        func touch(_ number: String?, _ at: String?) {
            guard let n = number, let at = at else { return }
            if (touched[n] ?? "") < at { touched[n] = at }
        }
        for p in projects {
            if let a = projectAuthors[p.id], a.mine, a.lastEditedBy != nil { touch(p.projectNumber, a.lastEditedAt) }
        }
        for r in rows where r.mine && r.lastEditedBy != nil { touch(r.projectNumber, r.lastEditedAt ?? r.updatedAt) }
        let byId = Dictionary(projects.map { ($0.id, $0.projectNumber) }, uniquingKeysWith: { a, _ in a })
        for e in activityStore.readAll() where e.by != nil && isMine(device: e.device, name: e.by) {
            touch(e.projectId.flatMap { byId[$0] }, e.createdAt)
        }
        return projects.compactMap { p -> MyProject? in
            guard let at = touched[p.projectNumber] else { return nil }
            return MyProject(id: p.id, projectNumber: p.projectNumber, name: p.name, clientName: clients[p.clientId], status: p.status, lastWorkedAt: at,
                             createdBy: projectAuthors[p.id]?.createdBy)
        }
        .sorted { ($0.status == "Active" ? 0 : 1, $1.lastWorkedAt) < ($1.status == "Active" ? 0 : 1, $0.lastWorkedAt) }
        .prefix(limit).map { $0 }
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
            outstandingQuotations: Array(outstanding.prefix(30)),
            unpaidInvoices: Array(unpaid.prefix(30)),
            unpaidTotal: doubleOf(unpaidTotal),
            overdueCount: overdue.count,
            overdueTotal: doubleOf(overdueTotal),
            // Mine: the ones this Mac's user last worked on (the others are
            // in the team's activity).
            recentDeliveryNotes: Array(rows.filter { $0.kind == "Delivery Note" && $0.mine }
                .sorted { ($0.lastEditedAt ?? $0.updatedAt) > ($1.lastEditedAt ?? $1.updatedAt) }.prefix(30)),
            recentDocuments: Array(rows.filter { $0.mine }.sorted { ($0.lastEditedAt ?? $0.updatedAt) > ($1.lastEditedAt ?? $1.updatedAt) }.prefix(30)),
            recentActivity: Array(listActivity(projectId: nil, limit: 200).filter { $0.mine }.prefix(30))
        )
        summary.teamActivity = Array(listActivity(projectId: nil, limit: 200).filter { !$0.mine }.prefix(30))
        summary.myProjects = myRecentProjects(rows: rows, limit: 30)
        summary.userName = TeamSync.memberName
        summary.inspectionsDue = inspectionsDue(withinDays: 3)
        summary.myTasks = Array(listTasks().filter { $0.mine && !$0.task.done }.prefix(30))
        let quotations = Dictionary(quotationsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let unsigned = rows.filter { r in
            guard r.kind == "Quotation", r.status == "Issued", r.mine, let q = quotations[r.id] else { return false }
            return q.signedCopyNotNeeded != true && q.clientAgreedAt == nil && !(q.signedCopyPath.map { fileIsPresent($0) } ?? false)
        }.map { r -> DocRow in
            var row = r
            if invoicedQuotationIds.contains(r.id) { row.status = "Invoiced" }
            return row
        }.sorted { ($0.status == "Invoiced" ? 0 : 1, $1.date) < ($1.status == "Invoiced" ? 0 : 1, $0.date) }
        summary.awaitingSignedCopy = Array(unsigned.prefix(30))
        summary.awaitingSignedCopyCount = unsigned.count
        return summary
    }

    // ---- Scaffold inspections ----

    static let inspectionResults = ["Safe", "Safe with remarks", "Unsafe"]

    func dayFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }

    /// yyyy-MM-dd plus `days`.
    func addDays(_ day: String, _ days: Int) -> String? {
        let f = dayFormatter()
        guard let d = f.date(from: String(day.prefix(10))), let next = Calendar(identifier: .gregorian).date(byAdding: .day, value: days, to: d) else { return nil }
        return f.string(from: next)
    }

    /// Days from today to a yyyy-MM-dd (negative = past).
    func daysFromToday(_ day: String) -> Int {
        let f = dayFormatter()
        guard let d = f.date(from: String(day.prefix(10))), let t = f.date(from: todayYMD()) else { return 0 }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: t, to: d).day ?? 0
    }

    func listInspections(projectId: String) -> [ScaffoldInspection] {
        inspectionsStore.readAll().filter { $0.projectId == projectId }
            .sorted { ($0.inspectedOn, $0.createdAt) > ($1.inspectedOn, $1.createdAt) }
    }

    /// Records an inspection (no id) or changes one. The next one is due
    /// 14 days on unless another date is given; none once dismantled.
    func saveInspection(_ payload: [String: Any]) -> LeadSaveResult {
        guard let projectId = text(payload, "projectId"), let project = getProject(id: projectId) else { return LeadSaveResult(ok: false, error: "Project not found.") }
        guard let structure = text(payload, "structure") else { return LeadSaveResult(ok: false, error: "Say what was inspected (e.g. the truss-out at 5/F).") }
        guard let day = validDay(text(payload, "inspectedOn")) else { return LeadSaveResult(ok: false, error: "Enter the date of the inspection.") }
        guard let inspector = text(payload, "inspector") else { return LeadSaveResult(ok: false, error: "Enter the competent person who inspected it.") }
        let result = text(payload, "result") ?? "Safe"
        guard AppDatabase.inspectionResults.contains(result) else { return LeadSaveResult(ok: false, error: "Choose the result.") }
        let dismantled = (payload["dismantled"] as? Bool) == true
        let nextText = text(payload, "nextDue")
        if nextText != nil && validDay(nextText) == nil { return LeadSaveResult(ok: false, error: "Enter a valid date for the next inspection.") }
        let next = dismantled ? nil : (validDay(nextText) ?? addDays(day, 14))
        var all = inspectionsStore.readAll()
        if let id = text(payload, "id"), let i = all.firstIndex(where: { $0.id == id }) {
            all[i].structure = structure
            all[i].location = text(payload, "location")
            all[i].inspectedOn = day
            all[i].inspector = inspector
            all[i].result = result
            all[i].remarks = text(payload, "remarks")
            all[i].actionTaken = text(payload, "actionTaken")
            all[i].nextDue = next
            all[i].dismantled = dismantled ? true : nil
            all[i].updatedAt = nowISO()
            inspectionsStore.writeAll(all)
            return LeadSaveResult(ok: true, error: nil, id: id)
        }
        let record = ScaffoldInspection(id: makeId("inspection"), projectId: project.id, structure: structure, location: text(payload, "location"),
                                        inspectedOn: day, inspector: inspector, result: result, remarks: text(payload, "remarks"),
                                        actionTaken: text(payload, "actionTaken"), nextDue: next, dismantled: dismantled ? true : nil,
                                        createdBy: TeamSync.memberName, createdAt: nowISO(), updatedAt: nowISO())
        inspectionsStore.insert(record)
        logActivity(projectId: project.id, dismantled ? "Scaffold dismantled — \(structure)" : "Scaffold inspected (\(result)) — \(structure)", reference: day)
        return LeadSaveResult(ok: true, error: nil, id: record.id)
    }

    func deleteInspection(id: String) -> String? {
        var all = inspectionsStore.readAll()
        guard all.contains(where: { $0.id == id }) else { return "Inspection not found." }
        all.removeAll { $0.id == id }
        inspectionsStore.writeAll(all)
        return nil
    }

    /// Each structure's next inspection (from its latest record) on active
    /// projects — all of them, or only those due within `withinDays`.
    func inspectionsDue(withinDays: Int? = nil) -> [InspectionDue] {
        let projects = Dictionary(projectsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var latest: [String: ScaffoldInspection] = [:]
        for r in inspectionsStore.readAll() {
            let key = "\(r.projectId)|\(r.structure.lowercased())"
            if let cur = latest[key], (cur.inspectedOn, cur.createdAt) >= (r.inspectedOn, r.createdAt) { continue }
            latest[key] = r
        }
        return latest.values.compactMap { r -> InspectionDue? in
            guard r.dismantled != true, let due = r.nextDue, let p = projects[r.projectId], p.status == "Active" else { return nil }
            let left = daysFromToday(due)
            if let w = withinDays, left > w { return nil }
            return InspectionDue(projectId: p.id, projectNumber: p.projectNumber, projectName: p.name, structure: r.structure,
                                 lastInspected: r.inspectedOn, lastResult: r.result, nextDue: due, daysLeft: left,
                                 url: "project-detail.html?number=\(p.projectNumber)&tab=inspections")
        }.sorted { ($0.daysLeft, $0.projectNumber) < ($1.daysLeft, $1.projectNumber) }
    }

    // ---- Tasks ----

    /// "9:5" / "09:05" → "09:05"; nil if it isn't a time.
    func validTime(_ value: String?) -> String? {
        guard let v = nonBlank(value) else { return nil }
        let parts = v.split(separator: ":").map { Int($0) }
        guard parts.count == 2, let h = parts[0], let m = parts[1], (0..<24).contains(h), (0..<60).contains(m) else { return nil }
        return String(format: "%02d:%02d", h, m)
    }

    /// An end time only if it's after the start.
    func laterTime(_ end: String?, than start: String?) -> String? {
        guard let e = end, let s = start, e > s else { return nil }
        return e
    }

    func isForMe(_ t: TeamTask) -> Bool {
        if let a = nonBlank(t.assignee) { return a.lowercased() == TeamSync.memberName.lowercased() }
        if let team = nonBlank(t.team) {
            return teamOf(TeamSync.memberName)?.lowercased() == team.lowercased() || (t.createdBy ?? "").lowercased() == TeamSync.memberName.lowercased()
        }
        return (t.createdBy ?? "").lowercased() == TeamSync.memberName.lowercased()
    }

    /// Tasks (to-dos). Scheduled events (with an end time) live on the
    /// Calendar, so they're left out unless `includeEvents`.
    func listTasks(projectId: String? = nil, includeEvents: Bool = false) -> [TaskRow] {
        let projects = Dictionary(projectsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let today = todayYMD()
        return tasksStore.readAll().filter { (projectId == nil || $0.projectId == projectId) && (includeEvents || $0.endTime == nil) }
            .map { t in
                let p = t.projectId.flatMap { projects[$0] }
                return TaskRow(task: t, projectNumber: p?.projectNumber, projectName: p?.name, mine: isForMe(t),
                               overdue: !t.done && (t.dueDate.map { $0 < today } ?? false))
            }
            .sorted { a, b in
                if a.task.done != b.task.done { return !a.task.done }
                if a.task.done { return (a.task.doneAt ?? "") > (b.task.doneAt ?? "") }
                let ha = a.task.priority == "High", hb = b.task.priority == "High"
                if ha != hb { return ha }
                return (a.task.dueDate ?? "9999", a.task.createdAt) < (b.task.dueDate ?? "9999", b.task.createdAt)
            }
    }

    func saveTask(_ payload: [String: Any]) -> LeadSaveResult {
        guard let title = text(payload, "title") else { return LeadSaveResult(ok: false, error: "Say what needs doing.") }
        let due = text(payload, "dueDate")
        if due != nil && validDay(due) == nil { return LeadSaveResult(ok: false, error: "Enter a valid due date.") }
        let projectId = text(payload, "projectId")
        if let pid = projectId, getProject(id: pid) == nil { return LeadSaveResult(ok: false, error: "Project not found.") }
        let priority = text(payload, "priority") == "High" ? "High" : nil
        var all = tasksStore.readAll()
        if let id = text(payload, "id"), let i = all.firstIndex(where: { $0.id == id }) {
            all[i].title = title
            all[i].notes = text(payload, "notes")
            all[i].projectId = projectId
            all[i].assignee = text(payload, "assignee")
            all[i].dueDate = validDay(due)
            all[i].dueTime = validDay(due) == nil ? nil : validTime(text(payload, "dueTime"))
            all[i].endTime = all[i].dueTime == nil ? nil : laterTime(validTime(text(payload, "endTime")), than: all[i].dueTime)
            all[i].team = all[i].assignee == nil ? text(payload, "team") : nil
            all[i].priority = priority
            all[i].updatedAt = nowISO()
            tasksStore.writeAll(all)
            return LeadSaveResult(ok: true, error: nil, id: id)
        }
        let t = TeamTask(id: makeId("task"), title: title, notes: text(payload, "notes"), projectId: projectId, assignee: text(payload, "assignee"),
                         dueDate: validDay(due), priority: priority, done: false, doneAt: nil, doneBy: nil,
                         createdBy: TeamSync.memberName, createdAt: nowISO(), updatedAt: nowISO())
        var task = t
        task.dueTime = validDay(due) == nil ? nil : validTime(text(payload, "dueTime"))
        task.endTime = task.dueTime == nil ? nil : laterTime(validTime(text(payload, "endTime")), than: task.dueTime)
        task.team = task.assignee == nil ? text(payload, "team") : nil
        tasksStore.insert(task)
        return LeadSaveResult(ok: true, error: nil, id: t.id)
    }

    func setTaskDone(id: String, done: Bool) -> String? {
        var all = tasksStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return "Task not found." }
        all[i].done = done
        all[i].doneAt = done ? nowISO() : nil
        all[i].doneBy = done ? TeamSync.memberName : nil
        all[i].updatedAt = nowISO()
        tasksStore.writeAll(all)
        if done, let pid = all[i].projectId { logActivity(projectId: pid, "Task done — \(all[i].title)") }
        return nil
    }

    func deleteTask(id: String) -> String? {
        var all = tasksStore.readAll()
        guard all.contains(where: { $0.id == id }) else { return "Task not found." }
        all.removeAll { $0.id == id }
        tasksStore.writeAll(all)
        return nil
    }

    /// The people tasks can be given to: everyone with a colour, in the
    /// shared folder, or already given a task.
    func teamNames() -> [String] {
        var names = Set<String>([TeamSync.memberName])
        for p in userProfilesStore.readAll() { names.insert(p.name) }
        for m in TeamSync.current?.members() ?? [] { names.insert(m.name) }
        for t in tasksStore.readAll() { if let a = nonBlank(t.assignee) { names.insert(a) } }
        return names.filter { !$0.isEmpty }.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // ---- Calendar ----

    /// Everything dated between `from` and `to` (yyyy-MM-dd, inclusive).
    func calendarEvents(from: String, to: String) -> [CalendarEvent] {
        let inRange: (String?) -> String? = { d in
            guard let d = d.map({ String($0.prefix(10)) }), d.count == 10, d >= from, d <= to else { return nil }
            return d
        }
        let today = todayYMD()
        let projects = Dictionary(projectsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let quotations = Dictionary(quotationsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let boqs = Dictionary(boqsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var events: [CalendarEvent] = []
        // Delivery schedule days (quotations' and BOQs'), each for the whole day.
        for d in quotationDeliveriesStore.readAll() {
            guard let day = inRange(d.date) else { continue }
            let q = quotations[d.quotationId], b = boqs[d.quotationId]
            let number = q?.quotationNumber ?? b?.boqNumber ?? ""
            let pid = q?.projectId ?? b?.projectId
            let pcs = Int(d.quantities.values.reduce(0, +))
            events.append(CalendarEvent(date: day, kind: "Delivery", title: "Day \(d.day) — \(number)",
                                        detail: [pid.flatMap { projects[$0] }.map { "\($0.projectNumber) \($0.name)" }, "\(pcs) pcs", nonBlank(d.note)].compactMap { $0 }.joined(separator: " · "),
                                        url: q != nil ? "quotation-editor.html?id=\(d.quotationId)" : "boq-editor.html?id=\(d.quotationId)", done: d.sent == true, time: nil))
        }
        for dn in deliveryNotesStore.readAll() where dn.status != "Cancelled" {
            guard let day = inRange(dn.deliveryDate) else { continue }
            let p = projects[dn.projectId]
            events.append(CalendarEvent(date: day, kind: "Delivery", title: "\(dn.deliveryNoteNumber) delivered",
                                        detail: p.map { "\($0.projectNumber) \($0.name)" }, url: "delivery-note-editor.html?id=\(dn.id)", done: dn.status != "Draft"))
        }
        // Signed delivery notes: the day to ask whether their items are back
        // (shown on today once it has passed).
        for r in deliveryReturns() {
            guard let day = inRange(r.checkDate < today ? today : r.checkDate) else { continue }
            events.append(CalendarEvent(date: day, kind: "Delivery", title: "\(r.deliveryNoteNumber) back from site?",
                                        detail: ["\(r.projectNumber) \(r.projectName)", "\(Int(r.outstanding)) pcs out", r.checkDate < today ? "asked since \(r.checkDate)" : nil].compactMap { $0 }.joined(separator: " · "),
                                        url: "stock.html?tab=returns&dn=\(r.deliveryNoteId)", overdue: r.checkDate < today))
        }
        // Inspections done, and due.
        for r in inspectionsStore.readAll() {
            guard let day = inRange(r.inspectedOn), let p = projects[r.projectId] else { continue }
            events.append(CalendarEvent(date: day, kind: "Inspection", title: "Inspected — \(r.structure)", detail: "\(p.projectNumber) · \(r.result) · \(r.inspector)",
                                        url: "project-detail.html?number=\(p.projectNumber)&tab=inspections", done: true))
        }
        for due in inspectionsDue() {
            // Overdue ones show on today.
            let shownOn = due.daysLeft < 0 ? today : due.nextDue
            guard let day = inRange(shownOn) else { continue }
            events.append(CalendarEvent(date: day, kind: "Inspection", title: "Inspection due — \(due.structure)",
                                        detail: "\(due.projectNumber) \(due.projectName)\(due.daysLeft < 0 ? " · overdue since \(due.nextDue)" : "")",
                                        url: due.url, overdue: due.daysLeft < 0))
        }
        for row in listTasks(includeEvents: true) {
            guard let day = inRange(row.task.dueDate) else { continue }
            // A scheduled event (with an end time) is a block on the week,
            // never "overdue"; a task is a to-do.
            let isEvent = row.task.endTime != nil
            var event = CalendarEvent(date: day, kind: isEvent ? "Event" : "Task", title: row.task.title,
                                      detail: [row.projectNumber.map { "\($0) \(row.projectName ?? "")" }, row.task.team.map { "\($0) team" }].compactMap { $0 }.joined(separator: " · "),
                                      url: isEvent ? "calendar.html?day=\(day)&event=\(row.task.id)" : "tasks.html?task=\(row.task.id)", done: isEvent ? false : row.task.done, person: row.task.assignee,
                                      overdue: isEvent ? false : row.overdue, time: row.task.dueTime)
            event.endTime = row.task.endTime
            event.id = row.task.id
            if event.detail?.isEmpty ?? false { event.detail = nil }
            events.append(event)
        }
        for r in documentRows(withAuthors: false) {
            if r.kind == "Quotation", r.status == "Issued", let day = inRange(r.dueDate) {
                events.append(CalendarEvent(date: day, kind: "Quotation", title: "\(r.number) valid until", detail: [r.clientName, r.projectNumber].compactMap { $0 }.joined(separator: " · "), url: r.url))
            }
            if r.kind == "Invoice", (r.balance ?? 0) > 0, !["Draft", "Paid", "Cancelled"].contains(r.status), let day = inRange(r.dueDate) {
                events.append(CalendarEvent(date: day, kind: "Invoice", title: "\(r.number) payment due", detail: [r.clientName, "\(formatMoney(r.balance ?? 0)) owed"].compactMap { $0 }.joined(separator: " · "),
                                            url: r.url, overdue: r.isOverdue))
            }
        }
        for l in leadsStore.readAll() where !["Won", "Lost"].contains(l.status) {
            guard let day = inRange(l.nextFollowUp) else { continue }
            events.append(CalendarEvent(date: day, kind: "Lead", title: "Follow up — \(l.company)", detail: [l.contactPerson, l.status].compactMap { nonBlank($0) }.joined(separator: " · "),
                                        url: "marketing.html?tab=leads&lead=\(l.id)", person: l.owner))
        }
        let workers = Dictionary(workersStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for d in workerDocumentsStore.readAll() where !d.isArchived {
            guard let day = inRange(d.expiryDate), let w = workers[d.workerId], !w.isArchived else { continue }
            events.append(CalendarEvent(date: day, kind: "Expiry", title: "\(d.category) expires — \(w.name)", detail: d.originalName, url: "admin.html?worker=\(w.id)"))
        }
        for d in adminDocumentsStore.readAll() where !d.isArchived {
            guard let day = inRange(d.expiryDate) else { continue }
            events.append(CalendarEvent(date: day, kind: "Expiry", title: "\(d.category) expires", detail: d.originalName, url: "admin.html"))
        }
        for p in projects.values {
            if let day = inRange(p.startDate) { events.append(CalendarEvent(date: day, kind: "Project", title: "\(p.projectNumber) starts", detail: p.name, url: "project-detail.html?number=\(p.projectNumber)")) }
            if let day = inRange(p.expectedCompletionDate) { events.append(CalendarEvent(date: day, kind: "Project", title: "\(p.projectNumber) due to finish", detail: p.name, url: "project-detail.html?number=\(p.projectNumber)")) }
        }
        return events.sorted { ($0.date, $0.kind, $0.title) < ($1.date, $1.kind, $1.title) }
    }

    // ---- Marketing ----

    static let leadStatuses = ["New", "Contacted", "Quoted", "Won", "Lost"]
    static let leadSources = ["Referral", "Website", "Tender", "Cold Call", "Repeat Client", "Site Visit", "Other"]

    func listLeads() -> [Lead] {
        let order = Dictionary(uniqueKeysWithValues: AppDatabase.leadStatuses.enumerated().map { ($1, $0) })
        return leadsStore.readAll().sorted { (order[$0.status] ?? 9, $1.updatedAt) < (order[$1.status] ?? 9, $0.updatedAt) }
    }

    /// Adds a lead (no id) or changes one.
    func saveLead(_ payload: [String: Any]) -> LeadSaveResult {
        guard let company = text(payload, "company") else { return LeadSaveResult(ok: false, error: "Enter the company's name.") }
        let status = text(payload, "status") ?? "New"
        guard AppDatabase.leadStatuses.contains(status) else { return LeadSaveResult(ok: false, error: "Choose a status.") }
        let followUp = text(payload, "nextFollowUp")
        if followUp != nil && validDay(followUp) == nil { return LeadSaveResult(ok: false, error: "Enter a valid follow-up date.") }
        let value = (payload["estimatedValue"] as? Double).map { max(0, $0) }
        var all = leadsStore.readAll()
        if let id = text(payload, "id"), let i = all.firstIndex(where: { $0.id == id }) {
            all[i].company = company
            all[i].contactPerson = text(payload, "contactPerson")
            all[i].phone = text(payload, "phone")
            all[i].email = text(payload, "email")
            all[i].source = text(payload, "source") ?? "Other"
            all[i].status = status
            all[i].estimatedValue = value
            all[i].nextFollowUp = validDay(followUp)
            all[i].notes = text(payload, "notes")
            all[i].owner = text(payload, "owner")
            all[i].updatedAt = nowISO()
            leadsStore.writeAll(all)
            return LeadSaveResult(ok: true, error: nil, id: id)
        }
        let lead = Lead(id: makeId("lead"), company: company, contactPerson: text(payload, "contactPerson"), phone: text(payload, "phone"),
                        email: text(payload, "email"), source: text(payload, "source") ?? "Other", status: status, estimatedValue: value,
                        nextFollowUp: validDay(followUp), notes: text(payload, "notes"), owner: text(payload, "owner") ?? TeamSync.memberName,
                        clientId: nil, createdAt: nowISO(), updatedAt: nowISO())
        leadsStore.insert(lead)
        logActivity(projectId: nil, "Lead added", reference: company)
        return LeadSaveResult(ok: true, error: nil, id: lead.id)
    }

    func deleteLead(id: String) -> String? {
        var all = leadsStore.readAll()
        guard all.contains(where: { $0.id == id }) else { return "Lead not found." }
        all.removeAll { $0.id == id }
        leadsStore.writeAll(all)
        return nil
    }

    /// Makes a client from a lead (its name, contact, phone, e-mail).
    func convertLead(id: String) -> LeadSaveResult {
        var all = leadsStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return LeadSaveResult(ok: false, error: "Lead not found.") }
        if let existing = all[i].clientId, clientsStore.readAll().contains(where: { $0.id == existing }) {
            return LeadSaveResult(ok: true, error: nil, id: existing)
        }
        let l = all[i]
        var payload: [String: Any] = ["companyName": l.company]
        payload["contactPerson"] = l.contactPerson
        payload["phone"] = l.phone
        payload["email"] = l.email
        payload["notes"] = [l.notes, "From a lead (\(l.source))."].compactMap { nonBlank($0) }.joined(separator: "\n")
        let client = createClient(payload)
        all[i].clientId = client.id
        if all[i].status != "Won" { all[i].status = "Won" }
        all[i].updatedAt = nowISO()
        leadsStore.writeAll(all)
        logActivity(projectId: nil, "Lead became a client", reference: l.company)
        return LeadSaveResult(ok: true, error: nil, id: client.id)
    }

    /// The quotations sent to a client (or everyone) between two days
    /// (yyyy-MM-dd, both included): not drafts, cancelled ones or combined counts.
    func clientQuoteReport(clientId: String?, from: String, to: String) -> ClientQuoteReport {
        let projects = Dictionary(projectsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let boqById = Dictionary(boqsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let qLines = Dictionary(grouping: quotationLineItemsStore.readAll(), by: { $0.quotationId })
        var rows: [ClientQuoteRow] = []
        var total = Decimal(0), wonValue = Decimal(0), wonCount = 0
        for q in quotationsStore.readAll() where q.status != "Draft" && q.status != "Cancelled" {
            if q.sourceBOQId.flatMap({ boqById[$0] }).map({ combinedSources($0) != nil }) ?? false { continue }
            guard let project = projects[q.projectId] else { continue }
            if let cid = clientId, project.clientId != cid { continue }
            let day = String(q.quotationDate.prefix(10))
            guard day >= from, day <= to else { continue }
            let value = quotationMoney(q, lineItems: qLines[q.id] ?? []).total
            // Accepted only when the client signed it, or agreed (recorded by hand).
            let won = q.clientAgreedAt != nil || (q.signedCopyPath.map { fileIsPresent($0) } ?? false)
            rows.append(ClientQuoteRow(id: q.id, number: q.quotationNumber, date: day, status: q.status, projectNumber: project.projectNumber,
                                       projectName: project.name, subject: nonBlank(q.subject), pricingMode: q.pricingMode, value: value, won: won))
            total += decimalOf(value)
            if won { wonCount += 1; wonValue += decimalOf(value) }
        }
        rows.sort { ($0.date, $0.number) < ($1.date, $1.number) }
        let name = clientId.flatMap { cid in clientsStore.readAll().first { $0.id == cid }?.companyName } ?? "All clients"
        return ClientQuoteReport(clientId: clientId, clientName: name, from: from, to: to, currency: getCompanySettings().currency,
                                 rows: rows, total: doubleOf(total), wonCount: wonCount, wonValue: doubleOf(wonValue))
    }

    // ---- Promotions ----

    func listPromotions() -> [Promotion] {
        promotionsStore.readAll().sorted { ($0.status == "Done" ? 1 : 0, $1.updatedAt) < ($1.status == "Done" ? 1 : 0, $0.updatedAt) }
    }

    func savePromotion(_ payload: [String: Any]) -> Result<Promotion, WorkerError> {
        guard let data = try? JSONSerialization.data(withJSONObject: payload), var promo = try? JSONDecoder().decode(Promotion.self, from: data) else {
            return .failure(WorkerError(message: "The campaign couldn’t be read."))
        }
        promo.name = promo.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !promo.name.isEmpty else { return .failure(WorkerError(message: "Give the campaign a name.")) }
        var all = promotionsStore.readAll()
        promo.updatedAt = nowISO()
        if let i = all.firstIndex(where: { $0.id == promo.id }) {
            all[i] = promo
        } else {
            if promo.id.isEmpty { promo.id = makeId("promo") }
            promo.createdAt = nowISO()
            all.append(promo)
        }
        promotionsStore.writeAll(all)
        return .success(promo)
    }

    func deletePromotion(id: String) -> String? {
        var all = promotionsStore.readAll()
        all.removeAll { $0.id == id }
        promotionsStore.writeAll(all)
        return nil
    }

    /// A promotional letter for each chosen target that hasn't one yet:
    /// numbered PL26-001… (no project), addressed to them, the campaign's
    /// letter with {Company} and {Contact} filled in.
    func writePromotionLetters(promotionId: String, targetIds: [String]) -> Result<Promotion, WorkerError> {
        var all = promotionsStore.readAll()
        guard let pi = all.firstIndex(where: { $0.id == promotionId }) else { return .failure(WorkerError(message: "Campaign not found.")) }
        let esc: (String) -> String = { $0.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        let template = nonBlank(all[pi].bodyHTML) ?? "<p>Dear Sirs,</p><p><br></p>"
        var made = 0
        for ti in all[pi].targets.indices where targetIds.contains(all[pi].targets[ti].id) && all[pi].targets[ti].letterId == nil {
            let t = all[pi].targets[ti]
            let body = template.replacingOccurrences(of: "{Company}", with: esc(t.name))
                .replacingOccurrences(of: "{Contact}", with: esc(nonBlank(t.contact) ?? "Sir / Madam"))
            let number = nextDocumentNumber(template: "PL{YY}-{SEQ}", projectNumber: "", existing: lettersStore.readAll().map { $0.letterNumber })
            let letter = Letter(id: makeId("letter"), letterNumber: number, projectId: nil, clientId: t.kind == "Client" ? t.refId : nil,
                                status: "Draft", letterDate: nowISO(), recipientName: t.name, recipientAddress: nonBlank(t.address),
                                attention: nonBlank(t.contact), yourRef: nil, subject: nonBlank(all[pi].subject), bodyHTML: body,
                                pdfPath: nil, createdAt: nowISO(), updatedAt: nowISO())
            lettersStore.insert(letter)
            all[pi].targets[ti].letterId = letter.id
            all[pi].targets[ti].lastAt = nowISO()
            made += 1
        }
        guard made > 0 else { return .failure(WorkerError(message: "Everyone chosen already has a letter.")) }
        all[pi].updatedAt = nowISO()
        promotionsStore.writeAll(all)
        logActivity(projectId: nil, "\(made) promotional letter\(made == 1 ? "" : "s") written", reference: all[pi].name)
        return .success(all[pi])
    }

    func marketingSummary() -> MarketingSummary {
        let today = todayYMD()
        func localDay(_ iso: String) -> String { String(iso.prefix(10)) }
        let projects = projectsStore.readAll()
        let projectById = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let clients = clientsStore.readAll()
        let clientName = Dictionary(clients.map { ($0.id, $0.companyName) }, uniquingKeysWith: { a, _ in a })
        let sites = Dictionary(sitesStore.readAll().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let boqs = boqsStore.readAll()
        let boqById = Dictionary(boqs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let invoices = invoicesStore.readAll().filter { $0.status != "Cancelled" }
        let qLines = Dictionary(grouping: quotationLineItemsStore.readAll(), by: { $0.quotationId })
        let iLines = Dictionary(grouping: invoiceLineItemsStore.readAll(), by: { $0.invoiceId })
        // Quotations sent (not drafts, not cancelled, not for a combined count).
        let sent = quotationsStore.readAll().filter { q in
            q.status != "Draft" && q.status != "Cancelled" && !(q.sourceBOQId.flatMap { boqById[$0] }.map { combinedSources($0) != nil } ?? false)
        }
        // Won only when the client signed it or agreed (recorded by hand);
        // being issued, or even invoiced, isn't enough.
        func isWon(_ q: Quotation) -> Bool { q.clientAgreedAt != nil || (q.signedCopyPath.map { fileIsPresent($0) } ?? false) }
        func value(_ q: Quotation) -> Double { quotationMoney(q, lineItems: qLines[q.id] ?? []).total }
        let calendar = Calendar(identifier: .gregorian)
        let monthFormat = DateFormatter()
        monthFormat.locale = Locale(identifier: "en_US_POSIX")
        monthFormat.dateFormat = "yyyy-MM"
        let thisMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: Date())) ?? Date()
        let monthKeys = (0..<12).reversed().compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }.map { monthFormat.string(from: $0) }
        var months = Dictionary(uniqueKeysWithValues: monthKeys.map { ($0, MarketingMonth(month: $0, quotedCount: 0, quotedValue: 0, wonCount: 0)) })
        var quotedValue = Decimal(0), quotedCount = 0, wonCount = 0
        var quotes: [MarketingQuote] = []
        for q in sent {
            let key = String(localDay(q.quotationDate).prefix(7))
            guard months[key] != nil else { continue }
            let v = value(q)
            let project = projectById[q.projectId]
            quotes.append(MarketingQuote(id: q.id, number: q.quotationNumber, date: localDay(q.quotationDate), month: key,
                                         clientId: project?.clientId, clientName: project.flatMap { clientName[$0.clientId] },
                                         projectNumber: project?.projectNumber, projectName: project?.name,
                                         subject: nonBlank(q.subject), value: v, won: isWon(q)))
            months[key]!.quotedCount += 1
            months[key]!.quotedValue = doubleOf(decimalOf(months[key]!.quotedValue) + decimalOf(v))
            quotedCount += 1
            quotedValue += decimalOf(v)
            if isWon(q) { months[key]!.wonCount += 1; wonCount += 1 }
        }
        let yearAgo = monthKeys.first ?? today
        // Clients: invoiced, quotations, won, and when they last had work.
        var byClient: [String: MarketingClient] = [:]
        func entry(_ clientId: String) -> MarketingClient {
            byClient[clientId] ?? MarketingClient(id: clientId, name: clientName[clientId] ?? "Unknown client", invoiced: 0, quotations: 0, won: 0, lastActivity: nil)
        }
        func touch(_ c: inout MarketingClient, _ day: String) { if (c.lastActivity ?? "") < day { c.lastActivity = day } }
        for q in sent {
            guard let cid = projectById[q.projectId]?.clientId else { continue }
            var c = entry(cid)
            c.quotations += 1
            if isWon(q) { c.won += 1 }
            touch(&c, localDay(q.quotationDate))
            byClient[cid] = c
        }
        for inv in invoices where inv.status != "Draft" {
            guard let cid = projectById[inv.projectId]?.clientId else { continue }
            var c = entry(cid)
            c.invoiced = doubleOf(decimalOf(c.invoiced) + decimalOf(invoiceTotals(inv, lineItems: iLines[inv.id] ?? []).total))
            touch(&c, localDay(inv.invoiceDate))
            byClient[cid] = c
        }
        for p in projects {
            var c = entry(p.clientId)
            touch(&c, localDay(p.createdAt))
            byClient[p.clientId] = c
        }
        let topClients = byClient.values.filter { $0.invoiced > 0 || $0.quotations > 0 }
            .sorted { ($0.invoiced, Double($0.quotations)) > ($1.invoiced, Double($1.quotations)) }.prefix(10).map { $0 }
        // Follow-ups.
        func daysSince(_ day: String) -> Int {
            guard let d = isoFromDay(day).flatMap({ isoFormatter.date(from: $0) }) else { return 0 }
            return max(0, Int(Date().timeIntervalSince(d) / 86400))
        }
        let authorNames = authorsByRecord("quotations.json")
        var followUps: [MarketingFollowUp] = []
        for q in sent where q.status == "Issued" && !isWon(q) && q.signedCopyNotNeeded != true {
            let days = daysSince(localDay(q.quotationDate))
            guard days >= 7 else { continue }
            let p = projectById[q.projectId]
            followUps.append(MarketingFollowUp(kind: "Quotation", title: "Chase \(q.quotationNumber)",
                detail: [p.flatMap { clientName[$0.clientId] }, nonBlank(q.subject)].compactMap { $0 }.joined(separator: " · "),
                days: days, url: "quotation-editor.html?id=\(q.id)", owner: authorNames[q.id]?.lastEditedBy ?? authorNames[q.id]?.createdBy))
        }
        for c in byClient.values where !(clients.first(where: { $0.id == c.id })?.isArchived ?? true) {
            guard let last = c.lastActivity else { continue }
            let days = daysSince(last)
            guard days >= 90 else { continue }
            followUps.append(MarketingFollowUp(kind: "Client", title: "Get back in touch with \(c.name)",
                detail: "No new quotation, invoice or project since \(last)", days: days, url: "clients.html?id=\(c.id)", owner: nil))
        }
        let leads = leadsStore.readAll()
        for l in leads where !["Won", "Lost"].contains(l.status) {
            guard let due = l.nextFollowUp, due <= today else { continue }
            followUps.append(MarketingFollowUp(kind: "Lead", title: "Follow up with \(l.company)",
                detail: [l.contactPerson, l.status, due == today ? "due today" : "due \(due)"].compactMap { nonBlank($0) }.joined(separator: " · "),
                days: daysSince(due), url: "marketing.html?tab=leads&lead=\(l.id)", owner: l.owner))
        }
        followUps.sort { ($0.kind == "Lead" ? 0 : $0.kind == "Quotation" ? 1 : 2, -$0.days) < ($1.kind == "Lead" ? 0 : $1.kind == "Quotation" ? 1 : 2, -$1.days) }
        // References: every project, newest first.
        let sentByProject = Dictionary(grouping: sent, by: { $0.projectId })
        let invoicesByProject = Dictionary(grouping: invoices.filter { $0.status != "Draft" }, by: { $0.projectId })
        let references = projects.sorted { $0.projectNumber > $1.projectNumber }.map { p -> ProjectReference in
            let structures = boqs.filter { $0.projectId == p.id && combinedSources($0) == nil }.compactMap { nonBlank($0.structure) }
            let quoted = (sentByProject[p.id] ?? []).reduce(Decimal(0)) { $0 + decimalOf(value($1)) }
            let invoiced = (invoicesByProject[p.id] ?? []).reduce(Decimal(0)) { $0 + decimalOf(invoiceTotals($1, lineItems: iLines[$1.id] ?? []).total) }
            return ProjectReference(projectNumber: p.projectNumber, name: p.name, clientName: clientName[p.clientId], siteName: sites[p.siteId],
                                    status: p.status, startDate: nonBlank(p.startDate) ?? String(localDay(p.createdAt)),
                                    structures: Array(NSOrderedSet(array: structures)).compactMap { $0 as? String },
                                    quotedValue: doubleOf(quoted), invoicedValue: doubleOf(invoiced))
        }
        let open = leads.filter { !["Won", "Lost"].contains($0.status) }
        var sources: [String: Int] = [:]
        for l in leads { sources[l.source, default: 0] += 1 }
        return MarketingSummary(
            currency: getCompanySettings().currency, months: monthKeys.compactMap { months[$0] },
            quotedCount: quotedCount, quotedValue: doubleOf(quotedValue), wonCount: wonCount,
            winRate: quotedCount > 0 ? Double(wonCount) / Double(quotedCount) : 0,
            averageQuote: quotedCount > 0 ? doubleOf(roundToCents(quotedValue / Decimal(quotedCount))) : 0,
            newClients: clients.filter { !$0.isArchived && String(localDay($0.createdAt).prefix(7)) >= yearAgo }.count,
            openLeads: open.count, pipelineValue: doubleOf(open.reduce(Decimal(0)) { $0 + decimalOf($1.estimatedValue ?? 0) }),
            leadSources: sources, topClients: topClients, quotes: quotes.sorted { ($0.date, $0.number) > ($1.date, $1.number) },
            followUps: Array(followUps.prefix(60)), references: references)
    }

    // ---- The user: their colour and their own work ----

    func userProfiles() -> [UserProfile] {
        userProfilesStore.readAll().sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// A person's colour ("#RRGGBB"); blank goes back to the automatic one.
    func setUserColor(name rawName: String, color rawColor: String?) -> String? {
        guard let name = nonBlank(rawName) else { return "Enter your name first." }
        let key = name.lowercased()
        var all = userProfilesStore.readAll()
        guard let color = nonBlank(rawColor) else {
            // Back to the automatic colour (their theme, if chosen, stays).
            if let i = all.firstIndex(where: { $0.id == key }), all[i].appearance != nil {
                all[i].color = ""
                all[i].updatedAt = nowISO()
            } else {
                all.removeAll { $0.id == key }
            }
            userProfilesStore.writeAll(all)
            return nil
        }
        guard color.range(of: "^#[0-9A-Fa-f]{6}$", options: .regularExpression) != nil else { return "Choose a colour." }
        if let i = all.firstIndex(where: { $0.id == key }) {
            all[i].name = name
            all[i].color = color.uppercased()
            all[i].updatedAt = nowISO()
        } else {
            all.append(UserProfile(id: key, name: name, color: color.uppercased(), updatedAt: nowISO()))
        }
        userProfilesStore.writeAll(all)
        return nil
    }

    /// A person's own Light / Dark, or nil if they haven't chosen.
    func userAppearance(name: String) -> String? {
        userProfilesStore.readAll().first { $0.id == name.lowercased() }?.appearance
    }

    /// Keeps a person's Light / Dark with their colour (shared by every Mac).
    func setUserAppearance(name rawName: String, appearance: String) {
        guard let name = nonBlank(rawName), ["System", "Light", "Dark"].contains(appearance) else { return }
        let key = name.lowercased()
        var all = userProfilesStore.readAll()
        if let i = all.firstIndex(where: { $0.id == key }) {
            all[i].appearance = appearance
            all[i].updatedAt = nowISO()
        } else {
            all.append(UserProfile(id: key, name: name, color: "", updatedAt: nowISO(), appearance: appearance))
        }
        userProfilesStore.writeAll(all)
    }

    /// A new name for this Mac's user; their colour and theme go with them.
    func renameUser(to rawName: String) -> String? {
        guard let name = nonBlank(rawName) else { return "Enter your name." }
        let old = TeamSync.memberName
        if let sync = TeamSync.current { sync.setMemberName(name) } else { TeamSync.memberName = name }
        let profiles = userProfilesStore.readAll()
        if old.lowercased() != name.lowercased(), let was = profiles.first(where: { $0.id == old.lowercased() }),
           !profiles.contains(where: { $0.id == name.lowercased() }) {
            if nonBlank(was.color) != nil { _ = setUserColor(name: name, color: was.color) }
            if let look = was.appearance { setUserAppearance(name: name, appearance: look) }
        }
        return nil
    }

    func userPage() -> UserPage {
        let rows = documentRows()
        let me = TeamSync.memberName
        let mine = rows.filter { $0.mine && $0.lastEditedBy != nil }
            .sorted { ($0.lastEditedAt ?? $0.updatedAt) > ($1.lastEditedAt ?? $1.updatedAt) }
        let history = activityAuthors()
        var created = rows.filter { $0.createdBy == me }.count
        var lastWorked = mine.count
        for file in ["projects.json", "letters.json"] {
            for a in authorsIndex(file, history: history).values {
                if a.createdBy == me { created += 1 }
                if a.mine && a.lastEditedBy != nil { lastWorked += 1 }
            }
        }
        let sync = TeamSync.current
        return UserPage(name: me, computer: TeamSync.computerName,
                        color: userProfilesStore.readAll().first { $0.id == me.lowercased() }.flatMap { nonBlank($0.color) },
                        sharing: sync != nil, members: sync?.members() ?? [],
                        myProjects: myRecentProjects(rows: rows, limit: 12),
                        myDocuments: Array(mine.prefix(15)),
                        myActivity: Array(listActivity(projectId: nil, limit: 400).filter { $0.mine && $0.by != nil }.prefix(20)),
                        createdCount: created, lastWorkedCount: lastWorked,
                        team: teamOf(me), teams: allTeams())
    }

    // ---- Teams and announcements ----

    func teamOf(_ name: String) -> String? {
        nonBlank(teamMembershipsStore.readAll().first { $0.id == name.lowercased() }?.team)
    }

    func allTeams() -> [String] {
        var seen: [String: String] = [:]
        for m in teamMembershipsStore.readAll() {
            guard let team = nonBlank(m.team), seen[team.lowercased()] == nil else { continue }
            seen[team.lowercased()] = team
        }
        return seen.values.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// This Mac's user's team; blank takes them out of any team.
    func setMyTeam(_ raw: String?) -> String? {
        let me = TeamSync.memberName
        guard nonBlank(me) != nil else { return "Enter your name first." }
        return setPerson(name: me, team: .some(raw), title: nil, canSign: nil, canSignAgreements: nil, idNumber: nil)
    }

    /// A person's team, title and whether they sign (each only when given).
    func setPerson(name rawName: String, team: String??, title: String??, canSign: Bool?, canSignAgreements: Bool?, idNumber: String??) -> String? {
        guard let name = nonBlank(rawName) else { return "Choose a person." }
        var all = teamMembershipsStore.readAll()
        var row = all.first { $0.id == name.lowercased() } ?? TeamMembership(id: name.lowercased(), name: name, team: nil, updatedAt: nowISO())
        if let team = team {
            // The same spelling as others in that team.
            row.team = nonBlank(team).map { t in allTeams().first { $0.lowercased() == t.lowercased() } ?? t }
        }
        if let title = title { row.title = nonBlank(title) }
        if let canSign = canSign { row.canSign = canSign ? true : nil }
        if let canSignAgreements = canSignAgreements { row.canSignAgreements = canSignAgreements ? true : nil }
        if let idNumber = idNumber { row.idNumber = nonBlank(idNumber)?.uppercased() }
        row.updatedAt = nowISO()
        all.removeAll { $0.id == row.id }
        if row.team != nil || row.title != nil || row.canSign == true || row.canSignAgreements == true || row.idNumber != nil { all.append(row) }
        teamMembershipsStore.writeAll(all)
        return nil
    }

    func membership(_ name: String) -> TeamMembership? {
        teamMembershipsStore.readAll().first { $0.id == name.lowercased() }
    }

    // ---- The Team page: people and their devices ----

    /// Where people's signature and chop images are kept (in the shared folder).
    var signaturesFolder: URL { dataDir.appendingPathComponent("signatures", isDirectory: true) }
    func signatureImageURL(_ name: String, _ which: String) -> URL {
        let safe = name.lowercased().replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return signaturesFolder.appendingPathComponent("\(safe)-\(which == "chop" ? "chop" : "signature").png")
    }

    func teamPage() -> TeamPage {
        let me = TeamSync.memberName
        let sync = TeamSync.current
        var devices: [String: [TeamMember]] = [:]
        if let sync = sync {
            for d in sync.members() {
                // A browser not used for two weeks drops off the list.
                if d.id.hasPrefix("web-"), (parseISODate(d.lastSeen).map { Date().timeIntervalSince($0) > 14 * 86400 } ?? true) { continue }
                devices[d.name.lowercased(), default: []].append(d)
            }
        } else if nonBlank(me) != nil {
            devices[me.lowercased()] = [TeamMember(id: "this", name: me, computer: TeamSync.computerName, lastSeen: nowISO(), isThisMac: true)]
        }
        // People using ScaffoldPro Web through this Mac.
        for w in WebServer.shared.recentPeople() where !(devices[w.name.lowercased()] ?? []).contains(where: { $0.id == "web-" + String(w.token.prefix(8)) }) {
            devices[w.name.lowercased(), default: []].append(TeamMember(id: "web-" + String(w.token.prefix(8)), name: w.name, computer: "\(w.agent) (web)", lastSeen: w.lastSeen))
        }
        var names: [String: String] = [:]
        for key in devices.keys { names[key] = devices[key]?.first?.name }
        for m in teamMembershipsStore.readAll() { names[m.id] = names[m.id] ?? m.name }
        for p in userProfilesStore.readAll() { names[p.id] = names[p.id] ?? p.name }
        let employees = employeesStore.readAll().filter { !$0.isArchived }
        for e in employees { names[e.name.lowercased()] = names[e.name.lowercased()] ?? e.name }
        if nonBlank(me) != nil { names[me.lowercased()] = names[me.lowercased()] ?? me }
        let fm = FileManager.default
        var people: [TeamPerson] = []
        for (key, name) in names {
            let m = membership(name)
            let e = employees.first { $0.name.lowercased() == key }
            people.append(TeamPerson(name: name, team: nonBlank(m?.team), title: m?.title, canSign: m?.canSign == true,
                                     canSignAgreements: m?.canSignAgreements == true, idNumber: m?.idNumber,
                                     isMe: key == me.lowercased(), devices: devices[key] ?? [],
                                     employeeNumber: e?.employeeNumber, position: e?.position, phone: e?.phone,
                                     hasSignature: fm.fileExists(atPath: signatureImageURL(name, "signature").path),
                                     hasChop: fm.fileExists(atPath: signatureImageURL(name, "chop").path)))
        }
        people.sort { a, b in
            if a.isMe != b.isMe { return a.isMe }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
        return TeamPage(me: me, people: people, teams: allTeams(), sharing: sync != nil)
    }

    // ---- Asking a director to sign a quotation ----

    func signers() -> [String] {
        teamMembershipsStore.readAll().filter { $0.canSign == true }.map { $0.name }.sorted()
    }

    func signRequestsPage() -> SignRequestsPage {
        let me = TeamSync.memberName.lowercased()
        let all = signRequestsStore.readAll().sorted { $0.createdAt > $1.createdAt }
        return SignRequestsPage(me: TeamSync.memberName, canSign: membership(TeamSync.memberName)?.canSign == true,
                                incoming: all.filter { $0.status == "Pending" && $0.signer.lowercased() == me },
                                outgoing: all.filter { $0.requestedBy.lowercased() == me },
                                recent: Array(all.prefix(60)), signers: signers())
    }

    func requestSignature(quotationId: String, signer rawSigner: String, note: String?) -> String? {
        let me = TeamSync.memberName
        guard nonBlank(me) != nil else { return "Enter your name on the User page first." }
        guard let q = getQuotation(id: quotationId), let project = getProject(id: q.projectId) else { return "Quotation not found." }
        guard q.status != "Cancelled" else { return "That quotation is cancelled." }
        guard let signer = signers().first(where: { $0.lowercased() == rawSigner.lowercased() }) else {
            return "Choose who signs. Directors are marked on the Team page."
        }
        if signRequestsStore.readAll().contains(where: { $0.documentId == q.id && $0.status == "Pending" }) {
            return "\(q.quotationNumber) is already waiting for a signature."
        }
        let requestId = makeId("sign")
        signRequestsStore.insert(SignRequest(id: requestId, kind: "Quotation", documentId: q.id, number: q.quotationNumber,
                                             projectNumber: project.projectNumber, projectName: project.name, requestedBy: me, signer: signer,
                                             note: nonBlank(note), status: "Pending", createdAt: nowISO()))
        // A notice for the signer on every page, until they close it or answer.
        var notice = Announcement(id: makeId("announcement"),
                                  message: "\(me) asked you to sign and chop \(q.quotationNumber) — \(project.projectNumber) \(project.name)\(nonBlank(note).map { ": “\($0)”" } ?? ".")",
                                  audience: "@" + signer.lowercased(), author: me, createdAt: nowISO(), showUntil: nil, important: true, dismissedBy: [])
        notice.signRequestId = requestId
        notice.link = "team.html?tab=signatures&review=\(requestId)"
        announcementsStore.insert(notice)
        logActivity(projectId: project.id, "Sent to \(signer) to sign", reference: q.quotationNumber)
        return nil
    }

    func getSignRequest(id: String) -> SignRequest? { signRequestsStore.readAll().first { $0.id == id } }

    /// Takes back a director's signature and chop: the quotation is no
    /// longer marked signed, its request says Withdrawn, and the signed
    /// PDF goes to the Trash (so it can still be put back from there).
    func withdrawDirectorSignature(quotationId: String) -> String? {
        var qs = quotationsStore.readAll()
        guard let qi = qs.firstIndex(where: { $0.id == quotationId }) else { return "Quotation not found." }
        let q = qs[qi]
        guard let signer = q.directorSignedBy else { return "\(q.quotationNumber) isn’t signed." }
        let path = q.directorSignedPath
        qs[qi].directorSignedPath = nil
        qs[qi].directorSignedAt = nil
        qs[qi].directorSignedBy = nil
        quotationsStore.writeAll(qs)
        var all = signRequestsStore.readAll()
        if let i = all.lastIndex(where: { $0.documentId == quotationId && $0.status == "Signed" }) {
            all[i].status = "Withdrawn"
            all[i].decidedAt = nowISO()
            signRequestsStore.writeAll(all)
        }
        if let p = path, fileIsPresent(p) { try? FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil) }
        logActivity(projectId: q.projectId, "\(signer)’s signature and chop withdrawn by \(TeamSync.memberName)", reference: q.quotationNumber)
        return nil
    }

    /// Records the outcome, and tells whoever asked (an announcement just for them).
    func finishSignRequest(id: String, signed: Bool, filePath: String?, reply: String?) -> String? {
        var all = signRequestsStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return "That request has been withdrawn." }
        all[i].status = signed ? "Signed" : "Declined"
        all[i].decidedAt = nowISO()
        all[i].filePath = filePath
        all[i].reply = nonBlank(reply)
        signRequestsStore.writeAll(all)
        let r = all[i]
        removeSignNotices(requestId: id)
        if signed, var q = getQuotation(id: r.documentId) {
            q.directorSignedPath = filePath
            q.directorSignedAt = nowISO()
            q.directorSignedBy = r.signer
            var qs = quotationsStore.readAll()
            if let qi = qs.firstIndex(where: { $0.id == q.id }) { qs[qi] = q; quotationsStore.writeAll(qs) }
        }
        let message = signed
            ? "\(r.number) has been signed and chopped by \(r.signer). The signed copy is saved in project \(r.projectNumber)’s Quotations folder."
            : "\(r.signer) didn’t sign \(r.number)\(r.reply.map { ": \($0)" } ?? ".")"
        announcementsStore.insert(Announcement(id: makeId("announcement"), message: message, audience: "@" + r.requestedBy.lowercased(),
                                               author: r.signer, createdAt: nowISO(), showUntil: nil, important: !signed, dismissedBy: []))
        if let project = getProjectByNumber(r.projectNumber) {
            logActivity(projectId: project.id, signed ? "Signed and chopped by \(r.signer)" : "Not signed by \(r.signer)", reference: r.number)
        }
        return nil
    }

    // ---- Chat ----

    static func dmId(_ a: String, _ b: String) -> String {
        "dm:" + [a.lowercased(), b.lowercased()].sorted().joined(separator: "|")
    }

    /// Whether this person may read a conversation.
    func chatAllowed(_ conversation: String, for name: String) -> Bool {
        let key = name.lowercased()
        if conversation == "everyone" { return true }
        if conversation.hasPrefix("team:") { return teamOf(name)?.lowercased() == String(conversation.dropFirst(5)) }
        if conversation.hasPrefix("dm:") { return conversation.dropFirst(3).split(separator: "|").map { String($0) }.contains(key) }
        return false
    }

    func chatPage() -> ChatPage {
        let me = TeamSync.memberName
        let key = me.lowercased()
        let myTeam = teamOf(me)
        let people = teamPage().people.map { $0.name }.filter { $0.lowercased() != key }
        let messages = chatStore.readAll().filter { $0.deleted != true }
        var byConversation: [String: [ChatMessage]] = [:]
        for m in messages { byConversation[m.conversation, default: []].append(m) }
        func summary(_ id: String, _ title: String, _ kind: String, with: String?) -> ChatConversation {
            let list = byConversation[id] ?? []
            let last = list.max { $0.createdAt < $1.createdAt }
            let text = last.map { m -> String in
                if !m.text.isEmpty { return m.text }
                return m.gifURL != nil ? "GIF" : (m.file != nil ? "Picture" : "")
            }
            return ChatConversation(id: id, title: title, kind: kind, with: with, lastText: text, lastAuthor: last?.author, lastAt: last?.createdAt, count: list.count)
        }
        var list = [summary("everyone", "Everyone", "everyone", with: nil)]
        if let team = myTeam { list.append(summary("team:" + team.lowercased(), "\(team) team", "team", with: nil)) }
        // A direct message with each person (ones with messages first).
        var dms = people.map { summary(AppDatabase.dmId(me, $0), $0, "dm", with: $0) }
        // People who've written to me but aren't on the Team list.
        for (id, msgs) in byConversation where id.hasPrefix("dm:") && chatAllowed(id, for: me) && !dms.contains(where: { $0.id == id }) {
            let names: [String] = id.dropFirst(3).split(separator: "|").map { String($0) }
            var other = "Someone"
            if let m = msgs.first(where: { $0.author.lowercased() != key }) { other = m.author }
            else if let n = names.first(where: { $0 != key }) { other = n }
            dms.append(summary(id, other, "dm", with: other))
        }
        dms.sort { a, b in
            if (a.lastAt != nil) != (b.lastAt != nil) { return a.lastAt != nil }
            if let x = a.lastAt, let y = b.lastAt, x != y { return x > y }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
        return ChatPage(me: me, myTeam: myTeam, people: people, conversations: list + dms, gifKey: getCompanySettings().giphyKey)
    }

    /// The conversation's messages (the last `limit`), oldest first.
    func chatMessages(conversation: String, limit: Int = 300) -> [ChatMessage] {
        guard chatAllowed(conversation, for: TeamSync.memberName) else { return [] }
        let list = chatStore.readAll().filter { $0.conversation == conversation }.sorted { $0.createdAt < $1.createdAt }
        return Array(list.suffix(limit))
    }

    func sendChat(conversation: String, text raw: String?, gifURL: String?, file: String?, fileName: String?, replyTo: String?) -> Result<ChatMessage, WorkerError> {
        let me = TeamSync.memberName
        guard nonBlank(me) != nil else { return .failure(WorkerError(message: "Enter your name on the User page first.")) }
        guard chatAllowed(conversation, for: me) else { return .failure(WorkerError(message: "You’re not in that conversation.")) }
        let text = (raw ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || gifURL != nil || file != nil else { return .failure(WorkerError(message: "Write a message.")) }
        guard text.count <= 4000 else { return .failure(WorkerError(message: "That message is too long.")) }
        if let g = gifURL, !(g.hasPrefix("https://") && g.count < 600) { return .failure(WorkerError(message: "That GIF can’t be sent.")) }
        let m = ChatMessage(id: makeId("msg"), conversation: conversation, author: me, text: text, createdAt: nowISO(),
                            gifURL: gifURL, file: file, fileName: fileName, replyTo: nonBlank(replyTo))
        chatStore.insert(m)
        return .success(m)
    }

    func editChat(id: String, text: String?, delete: Bool) -> String? {
        var all = chatStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return "That message isn’t there any more." }
        guard all[i].author.lowercased() == TeamSync.memberName.lowercased() else { return "You can only change your own messages." }
        if delete {
            all[i].deleted = true
            all[i].text = ""
            all[i].gifURL = nil
            all[i].file = nil
        } else {
            guard let t = nonBlank(text) else { return "Write a message." }
            all[i].text = t
            all[i].editedAt = nowISO()
        }
        chatStore.writeAll(all)
        return nil
    }

    /// Adds my reaction, or takes it away if it's already there.
    func reactChat(id: String, emoji: String) -> String? {
        let key = TeamSync.memberName.lowercased()
        guard !emoji.isEmpty, emoji.count <= 4 else { return "Choose an emoji." }
        var all = chatStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return "That message isn’t there any more." }
        var reactions = all[i].reactions ?? [:]
        var who = reactions[emoji] ?? []
        if who.contains(key) { who.removeAll { $0 == key } } else { who.append(key) }
        reactions[emoji] = who.isEmpty ? nil : who
        all[i].reactions = reactions.isEmpty ? nil : reactions
        chatStore.writeAll(all)
        return nil
    }

    /// Where pictures sent in chat are kept: the shared folder (so the other
    /// Macs see them), else this Mac's data folder.
    var chatFilesFolder: URL {
        (TeamSync.current?.root ?? dataDir).appendingPathComponent("Chat Files", isDirectory: true)
    }

    /// Withdraws a request that hasn't been signed yet (whoever asked).
    func withdrawSignRequest(id: String) -> String? {
        var all = signRequestsStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return nil }
        guard all[i].status == "Pending" else { return "It has already been \(all[i].status.lowercased())." }
        all.remove(at: i)
        signRequestsStore.writeAll(all)
        removeSignNotices(requestId: id)
        return nil
    }

    func removeSignNotices(requestId: String) {
        let all = announcementsStore.readAll()
        let left = all.filter { $0.signRequestId != requestId }
        if left.count != all.count { announcementsStore.writeAll(left) }
    }

    func announcementRunning(_ a: Announcement) -> Bool {
        guard let until = nonBlank(a.showUntil) else { return true }
        return until >= todayYMD()
    }

    func announcementsPage() -> AnnouncementsPage {
        let me = TeamSync.memberName
        let key = me.lowercased()
        let myTeam = teamOf(me)
        // Important ones first, then the newest.
        let running = announcementsStore.readAll().filter { announcementRunning($0) }.sorted { a, b in
            if a.important != b.important { return a.important }
            return a.createdAt > b.createdAt
        }
        let team = myTeam?.lowercased() ?? ""
        let forMe = running.filter { a in
            if a.audience == "Everyone" || a.audience.lowercased() == "@" + key { return true }
            // Ones I posted to a team; not a personal note I sent someone.
            if a.author.lowercased() == key { return !a.audience.hasPrefix("@") }
            return !team.isEmpty && a.audience.lowercased() == team
        }
        let visible = forMe.filter { !$0.dismissedBy.contains(key) }.map { AnnouncementRow(announcement: $0, mine: $0.author.lowercased() == key) }
        let mine = running.filter { $0.author.lowercased() == key && !$0.audience.hasPrefix("@") }.map { AnnouncementRow(announcement: $0, mine: true) }
        return AnnouncementsPage(me: me, myTeam: myTeam, teams: allTeams(), visible: visible, mine: mine)
    }

    func postAnnouncement(_ payload: [String: Any]) -> String? {
        let me = TeamSync.memberName
        guard nonBlank(me) != nil else { return "Enter your name on the User page first." }
        guard let message = nonBlank(payload["message"] as? String) else { return "Write the announcement." }
        let wanted = nonBlank(payload["audience"] as? String) ?? "Everyone"
        var audience = "Everyone"
        if wanted != "Everyone" {
            guard let team = teamOf(me) else { return "Set your team on the User page to announce to your team." }
            audience = team
        }
        var until = nonBlank(payload["showUntil"] as? String)
        if let u = until, u.range(of: "^\\d{4}-\\d{2}-\\d{2}$", options: .regularExpression) == nil { until = nil }
        let a = Announcement(id: makeId("announcement"), message: message, audience: audience, author: me, createdAt: nowISO(),
                             showUntil: until, important: (payload["important"] as? Bool) ?? false, dismissedBy: [])
        announcementsStore.insert(a)
        return nil
    }

    /// Closes it on this person's Dashboard (on every Mac they use).
    func dismissAnnouncement(id: String) -> String? {
        let key = TeamSync.memberName.lowercased()
        var all = announcementsStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return "That announcement has been taken down." }
        if !all[i].dismissedBy.contains(key) { all[i].dismissedBy.append(key) }
        announcementsStore.writeAll(all)
        return nil
    }

    /// Takes it down for everyone (only whoever posted it).
    func deleteAnnouncement(id: String) -> String? {
        var all = announcementsStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return nil }
        guard all[i].author.lowercased() == TeamSync.memberName.lowercased() else { return "Only \(all[i].author) can take this announcement down." }
        all.remove(at: i)
        announcementsStore.writeAll(all)
        return nil
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

    /// The delivery note signed on site (already copied into the project
    /// folder), or nil to forget it (the file stays in the folder).
    func setDeliveryNoteSignedCopy(id: String, path: String?) -> String? {
        var notes = deliveryNotesStore.readAll()
        guard let i = notes.firstIndex(where: { $0.id == id }) else { return "Delivery note not found." }
        notes[i].signedCopyPath = path
        notes[i].signedCopyAt = path == nil ? nil : nowISO()
        notes[i].updatedAt = nowISO()
        deliveryNotesStore.writeAll(notes)
        logActivity(projectId: notes[i].projectId, path == nil ? "Signed copy removed from delivery note" : "Signed delivery note received",
                    reference: notes[i].deliveryNoteNumber)
        // Signed: its items are now out of the yard, at the site.
        syncDeliveryStock(notes[i])
        return nil
    }

    /// The signed copies of the delivery notes an invoice bills, in their
    /// order, that are still in the folder.
    func signedDeliveryNoteFiles(invoiceId: String) -> [URL] {
        guard let inv = getInvoice(id: invoiceId) else { return [] }
        let notes = deliveryNotesStore.readAll()
        return (inv.sourceDeliveryNoteIds ?? []).compactMap { nid in notes.first { $0.id == nid } }
            .sorted { $0.deliveryNoteNumber.localizedStandardCompare($1.deliveryNoteNumber) == .orderedAscending }
            .compactMap { $0.signedCopyPath }.filter { fileIsPresent($0) }.map { URL(fileURLWithPath: $0) }
    }

    /// The client agreed without a signed copy (by email, phone…): counts
    /// as won, and comes off the Dashboard's list. false takes it back.
    func setQuotationClientAgreed(id: String, agreed: Bool) -> String? {
        var qs = quotationsStore.readAll()
        guard let i = qs.firstIndex(where: { $0.id == id }) else { return "Quotation not found." }
        qs[i].clientAgreedAt = agreed ? nowISO() : nil
        quotationsStore.writeAll(qs)
        logActivity(projectId: qs[i].projectId, agreed ? "Client agreed to the quotation" : "Client's agreement taken back", reference: qs[i].quotationNumber)
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
        for d in documentRows(withAuthors: false) where matches(d.number, d.projectNumber, d.projectName, d.clientName) {
            results.append(SearchResult(kind: d.kind, title: d.number, subtitle: "\(d.projectNumber) — \(d.projectName) · \(d.status)", url: d.url))
        }
        for l in lettersStore.readAll() where matches(l.letterNumber, l.subject, l.recipientName) {
            results.append(SearchResult(kind: "Letter", title: l.letterNumber, subtitle: [l.subject, l.recipientName, l.status].compactMap { nonBlank($0) }.joined(separator: " · "),
                                        url: "letter-editor.html?id=\(l.id)"))
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
                                           by: TeamSync.memberName, device: TeamSync.deviceId))
    }

    func listActivity(projectId: String?, limit: Int) -> [ActivityRow] {
        let projects = projectsStore.readAll()
        return activityStore.readAll()
            .filter { projectId == nil || $0.projectId == projectId }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .map { e in
                let p = projects.first { $0.id == e.projectId }
                return ActivityRow(id: e.id, projectNumber: p?.projectNumber, projectName: p?.name, action: e.action, reference: e.reference, createdAt: e.createdAt, by: e.by,
                                   mine: isMine(device: e.device, name: e.by))
            }
    }

    // ---- Google Sheets (Settings › Google Sheets; GoogleSheetsSync) ----

    /// What the sheet is sent: the history of the last `days` days (the
    /// sheet skips what it already has) and every project as a row.
    func sheetsPayload(days: Int) -> (activity: [[String: Any]], projects: [[String: Any]]) {
        let projects = projectsStore.readAll()
        let byId = Dictionary(projects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let clients = Dictionary(clientsStore.readAll().map { ($0.id, $0.companyName) }, uniquingKeysWith: { a, _ in a })
        let sites = Dictionary(sitesStore.readAll().map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let cutoff = ISO8601DateFormatter().string(from: Date().addingTimeInterval(-Double(days) * 86400))
        let all = activityStore.readAll()
        var last: [String: ActivityEntry] = [:]
        for e in all {
            guard let pid = e.projectId else { continue }
            if (last[pid]?.createdAt ?? "") < e.createdAt { last[pid] = e }
        }
        // Housekeeping (backups, undo / redo) isn't work: left out of the sheet.
        func isNoise(_ e: ActivityEntry) -> Bool {
            let a = e.action.lowercased()
            return a.contains("backup made") || a.hasPrefix("undone:") || a.hasPrefix("redone:") || a.hasPrefix("restored from")
        }
        let recent = all.filter { $0.createdAt >= cutoff && !isNoise($0) }.sorted { $0.createdAt > $1.createdAt }.prefix(3000)
        let activity: [[String: Any]] = recent.map { e in
            let p = e.projectId.flatMap { byId[$0] }
            return ["id": e.id, "when": e.createdAt, "who": e.by ?? "", "project": p?.projectNumber ?? "", "projectName": p?.name ?? "",
                    "what": e.action, "reference": e.reference ?? "", "from": e.device == "google-sheets" ? "Google Sheets" : "ScaffoldPro"]
        }
        let subs = sheetsSubProjects(projects)
        let letters = Dictionary(grouping: lettersStore.readAll().filter { $0.projectId != nil && $0.status != "Cancelled" }, by: { $0.projectId ?? "" })
        let rows: [[String: Any]] = projects.map { p in
            ["id": p.id, "number": p.projectNumber, "name": p.name, "client": clients[p.clientId] ?? "", "site": sites[p.siteId] ?? "",
             "status": p.status, "projectManager": p.projectManager ?? "", "internalNotes": p.internalNotes ?? "",
             "lastActivity": last[p.id]?.createdAt ?? "", "lastBy": last[p.id]?.by ?? "",
             "letters": (letters[p.id] ?? []).sorted { $0.letterNumber.localizedStandardCompare($1.letterNumber) == .orderedAscending }
                .map { "\($0.letterNumber) · \($0.status)" },
             "subs": subs[p.id] ?? []]
        }
        return (activity, rows)
    }

    /// Everyone's name colour for the sheet ("#RRGGBB"): the one chosen on
    /// their User page, else the one the app works out from the name
    /// (the same as js/sidebar.js personColor).
    func sheetsPeopleColours() -> [String: String] {
        let palette = ["#5B7DB1", "#B07A5E", "#5E8C6A", "#8E72A8", "#A8677C", "#4F8A8F", "#9A8458", "#6D6BA6", "#4E8472", "#A66A6A", "#6B7078", "#4F6F96"]
        var chosen: [String: String] = [:]
        for p in userProfilesStore.readAll() where nonBlank(p.color) != nil { chosen[p.name.lowercased()] = p.color }
        var names = Set(teamNames())
        for e in activityStore.readAll().suffix(2000) { if let by = nonBlank(e.by) { names.insert(by) } }
        var out: [String: String] = [:]
        for name in names {
            let key = name.trimmingCharacters(in: .whitespaces).lowercased()
            guard !key.isEmpty else { continue }
            if let c = chosen[key], c.hasPrefix("#"), c.count == 7 { out[name] = c; continue }
            var h: UInt32 = 0
            for u in key.unicodeScalars { h = h &* 31 &+ u.value }
            out[name] = palette[Int(h % UInt32(palette.count))]
        }
        return out
    }

    /// A project's sub-projects for the sheet: its documents grouped by the
    /// number after the project code (BQ26212-001, Qt26212-001-s1,
    /// DN26212-001-2 and H26212-001 are all 26212-001), each with how far
    /// it has got.
    func sheetsSubProjects(_ projects: [Project]) -> [String: [[String: Any]]] {
        let numbers = Dictionary(projects.map { ($0.id, $0.projectNumber) }, uniquingKeysWith: { a, _ in a })
        func key(_ docNumber: String, _ projectId: String) -> String {
            guard let code = numbers[projectId], let r = docNumber.range(of: code) else { return "" }
            let rest = String(docNumber[r.upperBound...])
            guard let m = rest.range(of: #"^-(?:[A-Za-z]+-)?(\d+)"#, options: .regularExpression) else { return "" }
            return String(rest[m].filter { $0.isNumber })
        }
        struct Group { var boqs: [String] = []; var quotations: [String] = []; var notes: [String] = []; var invoices: [String] = []
            var title: String? = nil; var updated = ""; var updatedBy: String? = nil; var statuses: [String] = []
            var anyIssuedQuote = false; var accepted = false; var delivered = false; var invoiced = false; var invoiceStates: [String] = [] }
        var groups: [String: [String: Group]] = [:]
        func touch(_ g: inout Group, _ at: String, _ by: String?) { if at > g.updated { g.updated = at; g.updatedBy = by } }
        let boqAuthors = authorsByRecord("boqs.json"), qAuthors = authorsByRecord("quotations.json")
        let dnAuthors = authorsByRecord("delivery_notes.json"), invAuthors = authorsByRecord("invoices.json")
        let tag: (String) -> String = { $0 == "PartiallyPaid" ? "Part paid" : $0 }
        for b in boqsStore.readAll() {
            let k = key(b.boqNumber, b.projectId)
            var g = groups[b.projectId, default: [:]][k, default: Group()]
            g.boqs.append("\(b.boqNumber) · \(b.status)")
            if g.title == nil { g.title = nonBlank(b.structure) }
            g.statuses.append(b.status)
            touch(&g, b.updatedAt, boqAuthors[b.id]?.lastEditedBy)
            groups[b.projectId, default: [:]][k] = g
        }
        // Main quotations first, so the subject is the main one's.
        for q in quotationsStore.readAll().sorted(by: { $0.quotationNumber.count < $1.quotationNumber.count }) {
            let k = key(q.quotationNumber, q.projectId)
            var g = groups[q.projectId, default: [:]][k, default: Group()]
            let signed = q.signedCopyPath.map { fileIsPresent($0) } ?? false
            g.quotations.append("\(q.quotationNumber) · \(q.status)\(signed ? " · client signed" : q.directorSignedBy != nil ? " · chopped" : "")")
            if let subject = nonBlank(q.subject), !q.quotationNumber.contains("-s") { g.title = subject }
            g.statuses.append(q.status)
            if q.status == "Issued" { g.anyIssuedQuote = true }
            if signed { g.accepted = true }
            touch(&g, q.updatedAt, qAuthors[q.id]?.lastEditedBy)
            groups[q.projectId, default: [:]][k] = g
        }
        for n in deliveryNotesStore.readAll() {
            let k = key(n.deliveryNoteNumber, n.projectId)
            var g = groups[n.projectId, default: [:]][k, default: Group()]
            let signed = n.signedCopyPath.map { fileIsPresent($0) } ?? false
            g.notes.append("\(n.deliveryNoteNumber) · \(n.status)\(signed ? " · signed" : "")")
            g.statuses.append(n.status)
            if n.status == "Issued" { g.delivered = true }
            touch(&g, n.updatedAt, dnAuthors[n.id]?.lastEditedBy)
            groups[n.projectId, default: [:]][k] = g
        }
        for i in invoicesStore.readAll() {
            let k = key(i.invoiceNumber, i.projectId)
            var g = groups[i.projectId, default: [:]][k, default: Group()]
            g.invoices.append("\(i.invoiceNumber) · \(tag(i.status))")
            g.statuses.append(i.status)
            if i.status != "Cancelled" { g.invoiceStates.append(i.status) }
            if i.status != "Draft" && i.status != "Cancelled" { g.invoiced = true }
            touch(&g, i.updatedAt, invAuthors[i.id]?.lastEditedBy)
            groups[i.projectId, default: [:]][k] = g
        }
        let sortNumbers: ([String]) -> [String] = { $0.sorted { $0.localizedStandardCompare($1) == .orderedAscending } }
        var out: [String: [[String: Any]]] = [:]
        for (pid, byKey) in groups {
            let code = numbers[pid] ?? ""
            out[pid] = byKey.keys.sorted { a, b in a.isEmpty ? false : b.isEmpty ? true : a.localizedStandardCompare(b) == .orderedAscending }.map { k -> [String: Any] in
                let g = byKey[k]!
                let stage: String
                if !g.invoiceStates.isEmpty && g.invoiceStates.allSatisfy({ $0 == "Paid" }) { stage = "Paid" }
                else if g.invoiced { stage = "Invoiced" }
                else if g.delivered { stage = "Delivered" }
                else if g.accepted { stage = "Accepted" }
                else if g.anyIssuedQuote { stage = "Quoted" }
                else if !g.statuses.isEmpty && g.statuses.allSatisfy({ $0 == "Cancelled" }) { stage = "Cancelled" }
                else { stage = "Draft" }
                return ["key": k.isEmpty ? "other" : k, "ref": k.isEmpty ? "\(code) (other)" : "\(code)-\(k)", "title": g.title ?? "", "stage": stage,
                        "boqs": sortNumbers(g.boqs), "quotations": sortNumbers(g.quotations), "deliveryNotes": sortNumbers(g.notes),
                        "invoices": sortNumbers(g.invoices), "updated": g.updated, "updatedBy": g.updatedBy ?? ""]
            }
        }
        return out
    }

    /// What was changed in the sheet: a project's status, manager or notes,
    /// and lines typed into its Activity tab. Noted in the history as done
    /// in Google Sheets. → how many were taken in.
    func applySheetChanges(_ changes: [[String: Any]], activity: [[String: Any]]) -> Int {
        var projects = projectsStore.readAll()
        var notes: [(String, String)] = []
        for c in changes {
            guard let pid = c["projectId"] as? String, let field = c["field"] as? String,
                  let i = projects.firstIndex(where: { $0.id == pid }) else { continue }
            let value = ((c["value"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            switch field {
            case "status":
                guard !value.isEmpty, value != projects[i].status else { continue }
                notes.append((pid, "Status changed to \(value)"))
                projects[i].status = value
            case "projectManager":
                guard value != (projects[i].projectManager ?? "") else { continue }
                projects[i].projectManager = nonBlank(value)
                notes.append((pid, value.isEmpty ? "Project manager cleared" : "Project manager set to \(value)"))
            case "internalNotes":
                guard value != (projects[i].internalNotes ?? "") else { continue }
                projects[i].internalNotes = nonBlank(value)
                notes.append((pid, "Notes edited"))
            default:
                continue
            }
        }
        if !notes.isEmpty { projectsStore.writeAll(projects) }
        for (pid, what) in notes {
            activityStore.insert(ActivityEntry(id: makeId("act"), projectId: pid, action: what, reference: "in Google Sheets", createdAt: nowISO(),
                                               by: "Google Sheets", device: "google-sheets"))
        }
        var typed = 0
        let known = Set(activityStore.readAll().map { $0.id })
        for a in activity {
            guard let id = a["id"] as? String, !known.contains(id), let what = nonBlank(a["what"] as? String) else { continue }
            let number = nonBlank(a["project"] as? String)
            let pid = number.flatMap { n in projects.first { $0.projectNumber == n }?.id }
            activityStore.insert(ActivityEntry(id: id, projectId: pid, action: what, reference: nonBlank(a["reference"] as? String),
                                               createdAt: nonBlank(a["when"] as? String) ?? nowISO(),
                                               by: nonBlank(a["who"] as? String) ?? "Google Sheets", device: "google-sheets"))
            typed += 1
        }
        return notes.count + typed
    }

    func text(_ payload: [String: Any], _ key: String) -> String? {
        guard let v = (payload[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty else { return nil }
        return v
    }
}

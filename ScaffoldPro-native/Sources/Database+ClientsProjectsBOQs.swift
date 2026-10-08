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
    func markupField(_ raw: Any?) -> Result<Double?, WorkerError> {
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
    /// For the Projects list: each project's documents counted (not the
    /// cancelled ones) and when any of them last changed.
    struct ProjectStats {
        var boqs = 0, quotations = 0, invoices = 0, deliveryNotes = 0
        var lastActivityAt = ""
    }
    func projectStats() -> [String: ProjectStats] {
        var out: [String: ProjectStats] = [:]
        func note(_ projectId: String, _ updatedAt: String, _ add: (inout ProjectStats) -> Void) {
            var st = out[projectId] ?? ProjectStats()
            add(&st)
            if updatedAt > st.lastActivityAt { st.lastActivityAt = updatedAt }
            out[projectId] = st
        }
        for b in boqsStore.readAll() { note(b.projectId, b.updatedAt) { $0.boqs += 1 } }
        for q in quotationsStore.readAll() where q.status != "Cancelled" { note(q.projectId, q.updatedAt) { $0.quotations += 1 } }
        for i in invoicesStore.readAll() where i.status != "Cancelled" { note(i.projectId, i.updatedAt) { $0.invoices += 1 } }
        for d in deliveryNotesStore.readAll() where d.status != "Cancelled" { note(d.projectId, d.updatedAt) { $0.deliveryNotes += 1 } }
        return out
    }
    func getProject(id: String) -> Project? {
        projectsStore.readAll().first { $0.id == id }
    }

    /// The Projects page's Overview: each project's documents by kind, and
    /// what each was made from (`linked`: still kept in step with it).
    struct OverviewLink: Codable { var id: String; var linked: Bool }
    struct OverviewDoc: Codable { var id: String; var number: String; var status: String; var from: [OverviewLink] }
    struct ProjectOverview: Codable {
        var projectId: String
        var boqs: [OverviewDoc] = []
        var quotations: [OverviewDoc] = []
        var deliveryNotes: [OverviewDoc] = []
        var invoices: [OverviewDoc] = []
    }

    func projectsOverview() -> [ProjectOverview] {
        var out: [String: ProjectOverview] = [:]
        func get(_ id: String) -> ProjectOverview { out[id] ?? ProjectOverview(projectId: id) }
        for b in boqsStore.readAll() {
            var o = get(b.projectId)
            o.boqs.append(OverviewDoc(id: b.id, number: b.boqNumber, status: b.status, from: []))
            out[b.projectId] = o
        }
        let quotations = quotationsStore.readAll()
        for q in quotations {
            var o = get(q.projectId)
            var from: [OverviewLink] = []
            if let bid = q.sourceBOQId { from.append(OverviewLink(id: bid, linked: q.boqLinked == true)) }
            if let parent = parentQuotation(of: q, in: quotations) { from.append(OverviewLink(id: parent.id, linked: true)) }
            o.quotations.append(OverviewDoc(id: q.id, number: q.quotationNumber, status: q.status, from: from))
            out[q.projectId] = o
        }
        for d in deliveryNotesStore.readAll() {
            var o = get(d.projectId)
            o.deliveryNotes.append(OverviewDoc(id: d.id, number: d.deliveryNoteNumber, status: d.status,
                                               from: d.sourceQuotationId.map { [OverviewLink(id: $0, linked: true)] } ?? []))
            out[d.projectId] = o
        }
        for i in invoicesStore.readAll() {
            var o = get(i.projectId)
            var from = (i.sourceDeliveryNoteIds ?? []).map { OverviewLink(id: $0, linked: true) }
            if from.isEmpty, let qid = i.sourceQuotationId { from.append(OverviewLink(id: qid, linked: true)) }
            o.invoices.append(OverviewDoc(id: i.id, number: i.invoiceNumber, status: i.status, from: from))
            out[i.projectId] = o
        }
        let byNumber: (OverviewDoc, OverviewDoc) -> Bool = { $0.number.localizedStandardCompare($1.number) == .orderedAscending }
        return out.values.map { o in
            var o = o
            o.boqs.sort(by: byNumber); o.quotations.sort(by: byNumber); o.deliveryNotes.sort(by: byNumber); o.invoices.sort(by: byNumber)
            return o
        }
    }

    /// The quotation series a document is filed under: "26001-002" for
    /// BQ26001-002, Qt26001-002 (and its -s1…), and the delivery notes and
    /// invoices made from Qt26001-002. nil if its number doesn't follow
    /// the project's.
    func documentSeries(docTypeTag: String, number: String) -> String? {
        func series(_ num: String, projectId: String) -> String? {
            guard let p = getProject(id: projectId) else { return nil }
            // Its project's number, else the number it was given before the
            // project's was changed.
            let pattern = NSRegularExpression.escapedPattern(for: p.projectNumber) + "-[0-9]+"
            return (num.range(of: pattern, options: .regularExpression) ?? num.range(of: "[0-9]+-[0-9]+", options: .regularExpression))
                .map { String(num[$0]) }
        }
        let quotes = quotationsStore.readAll()
        func viaQuotation(_ id: String?) -> String? {
            quotes.first(where: { $0.id == id }).flatMap { series($0.quotationNumber, projectId: $0.projectId) }
        }
        if docTypeTag == "Invoice" || docTypeTag == "DeliveryNote" || docTypeTag == "Delivery Note" {
            if let i = invoicesStore.readAll().first(where: { $0.invoiceNumber == number }) {
                return viaQuotation(i.sourceQuotationId) ?? series(i.invoiceNumber, projectId: i.projectId)
            }
            if let d = deliveryNotesStore.readAll().first(where: { $0.deliveryNoteNumber == number }) {
                return viaQuotation(d.sourceQuotationId) ?? series(d.deliveryNoteNumber, projectId: d.projectId)
            }
        }
        if let q = quotes.first(where: { $0.quotationNumber == number }) { return series(q.quotationNumber, projectId: q.projectId) }
        if let b = boqsStore.readAll().first(where: { $0.boqNumber == number }) { return series(b.boqNumber, projectId: b.projectId) }
        if let i = invoicesStore.readAll().first(where: { $0.invoiceNumber == number }) {
            return viaQuotation(i.sourceQuotationId) ?? series(i.invoiceNumber, projectId: i.projectId)
        }
        if let d = deliveryNotesStore.readAll().first(where: { $0.deliveryNoteNumber == number }) {
            return viaQuotation(d.sourceQuotationId) ?? series(d.deliveryNoteNumber, projectId: d.projectId)
        }
        return nil
    }

    /// What a quotation series' folder is called after its number: the
    /// structure of its BOQ (or of its quotation's BOQ), else its
    /// quotation's subject. nil if it has neither.
    func seriesTitle(projectNumber: String, series: String) -> String? {
        guard let project = getProjectByNumber(projectNumber) else { return nil }
        let boqs = boqsStore.readAll().filter { $0.projectId == project.id }
        let pattern = NSRegularExpression.escapedPattern(for: series) + "(?![0-9])"
        let inSeries = { (n: String) in n.range(of: pattern, options: .regularExpression) != nil }
        if let s = boqs.filter({ inSeries($0.boqNumber) }).compactMap({ nonBlank($0.structure) }).first { return s }
        // The main quotation first (Qt26219-001 before its -s1…).
        let quotes = quotationsStore.readAll().filter { $0.projectId == project.id && inSeries($0.quotationNumber) }
            .sorted { $0.quotationNumber.count < $1.quotationNumber.count }
        for q in quotes {
            if let s = q.sourceBOQId.flatMap({ id in boqs.first { $0.id == id } }).flatMap({ nonBlank($0.structure) }) { return s }
        }
        return quotes.compactMap { nonBlank($0.subject) }.first
    }

    /// Every project's quotation series ("26219-001"…) by its number, as
    /// documentSeries finds them (each store read once).
    func seriesByProject() -> [String: Set<String>] {
        let numberOf = Dictionary(projectsStore.readAll().map { ($0.id, $0.projectNumber) }, uniquingKeysWith: { a, _ in a })
        func series(_ num: String, _ projectId: String) -> String? {
            guard let projectNumber = numberOf[projectId] else { return nil }
            let pattern = NSRegularExpression.escapedPattern(for: projectNumber) + "-[0-9]+"
            return (num.range(of: pattern, options: .regularExpression) ?? num.range(of: "[0-9]+-[0-9]+", options: .regularExpression))
                .map { String(num[$0]) }
        }
        let quotes = quotationsStore.readAll()
        var quoteSeries: [String: String] = [:]
        for q in quotes { if let s = series(q.quotationNumber, q.projectId) { quoteSeries[q.id] = s } }
        var out: [String: Set<String>] = [:]
        func add(_ projectId: String, _ found: String?) {
            if let found = found, let projectNumber = numberOf[projectId] { out[projectNumber, default: []].insert(found) }
        }
        for b in boqsStore.readAll() { add(b.projectId, series(b.boqNumber, b.projectId)) }
        for q in quotes { add(q.projectId, quoteSeries[q.id]) }
        for d in deliveryNotesStore.readAll() { add(d.projectId, d.sourceQuotationId.flatMap { quoteSeries[$0] } ?? series(d.deliveryNoteNumber, d.projectId)) }
        for i in invoicesStore.readAll() { add(i.projectId, i.sourceQuotationId.flatMap { quoteSeries[$0] } ?? series(i.invoiceNumber, i.projectId)) }
        return out
    }

    /// A project's BOQs, quotations, delivery notes and invoices as
    /// (kind, number), longest numbers first (so Qt26001-002-s1 is found
    /// before Qt26001-002 in a file's name).
    func projectDocumentNumbers(projectId: String) -> [(tag: String, number: String)] {
        var out: [(tag: String, number: String)] = []
        out += boqsStore.readAll().filter { $0.projectId == projectId }.map { ("BOQ", $0.boqNumber) }
        out += quotationsStore.readAll().filter { $0.projectId == projectId }.map { ("Quotation", $0.quotationNumber) }
        out += deliveryNotesStore.readAll().filter { $0.projectId == projectId }.map { ("DeliveryNote", $0.deliveryNoteNumber) }
        out += invoicesStore.readAll().filter { $0.projectId == projectId }.map { ("Invoice", $0.invoiceNumber) }
        return out.filter { !$0.number.isEmpty }.sorted { $0.number.count > $1.number.count }
    }

    /// A document's status from its kind and number (for the PDF's watermark).
    /// How a document's files are named: its number, the project's name
    /// and, when there is one, the structure — "Qt26001-001 NOL Ancilliary
    /// Works - GL/09 Platform". Other files from it (a delivery schedule)
    /// say what they are in brackets. nil if the number isn't found.
    func documentFileBase(docTypeTag: String, number: String) -> String? {
        let boqs = boqsStore.readAll()
        let quotes = quotationsStore.readAll()
        // A quotation's structure is its BOQ's.
        func structure(ofQuotation id: String?) -> String? {
            guard let q = quotes.first(where: { $0.id == id }) else { return nil }
            return q.sourceBOQId.flatMap { bid in boqs.first { $0.id == bid }?.structure }
        }
        var projectId: String?
        var structureName: String?
        if let b = boqs.first(where: { $0.boqNumber == number }) {
            projectId = b.projectId; structureName = b.structure
        } else if let q = quotes.first(where: { $0.quotationNumber == number }) {
            projectId = q.projectId; structureName = structure(ofQuotation: q.id)
        } else if let i = invoicesStore.readAll().first(where: { $0.invoiceNumber == number }) {
            projectId = i.projectId; structureName = structure(ofQuotation: i.sourceQuotationId)
        } else if let d = deliveryNotesStore.readAll().first(where: { $0.deliveryNoteNumber == number }) {
            projectId = d.projectId; structureName = structure(ofQuotation: d.sourceQuotationId)
        } else if let l = lettersStore.readAll().first(where: { $0.letterNumber == number }) {
            projectId = l.projectId
        } else {
            return nil
        }
        var base = number
        if let name = projectId.flatMap({ getProject(id: $0)?.name }).flatMap({ nonBlank($0) }) { base += " \(name)" }
        if let s = nonBlank(structureName) { base += " - \(s)" }
        if !["BOQ", "Quotation", "Invoice", "DeliveryNote", "Letter"].contains(docTypeTag) { base += " (\(docTypeTag))" }
        return safeFileName(base)
    }

    func documentStatus(docTypeTag: String, number: String) -> String? {
        switch docTypeTag {
        case "BOQ": return boqsStore.readAll().first { $0.boqNumber == number }?.status
        case "Quotation": return quotationsStore.readAll().first { $0.quotationNumber == number }?.status
        case "Invoice": return invoicesStore.readAll().first { $0.invoiceNumber == number }?.status
        case "DeliveryNote": return deliveryNotesStore.readAll().first { $0.deliveryNoteNumber == number }?.status
        case "Letter": return lettersStore.readAll().first { $0.letterNumber == number }?.status
        default: return nil
        }
    }

    /// What a project holds — asked before it's deleted.
    struct ProjectContents: Codable {
        var ok = true
        var error: String? = nil
        var projectNumber = ""
        var name = ""
        var boqs = 0, quotations = 0, deliveryNotes = 0, invoices = 0, letters = 0
        var drawings = 0, documents = 0, inspections = 0, payments = 0
        var total: Int { boqs + quotations + deliveryNotes + invoices + letters + drawings + documents + inspections }
        var isEmpty = true
    }

    func projectContents(id: String) -> ProjectContents {
        guard let p = getProject(id: id) else { var c = ProjectContents(); c.ok = false; c.error = "Project not found."; return c }
        var c = ProjectContents()
        c.projectNumber = p.projectNumber
        c.name = p.name
        c.boqs = boqsStore.readAll().filter { $0.projectId == id }.count
        let quotationIds = Set(quotationsStore.readAll().filter { $0.projectId == id }.map { $0.id })
        c.quotations = quotationIds.count
        c.deliveryNotes = deliveryNotesStore.readAll().filter { $0.projectId == id }.count
        let invoiceIds = Set(invoicesStore.readAll().filter { $0.projectId == id }.map { $0.id })
        c.invoices = invoiceIds.count
        c.payments = invoicePaymentsStore.readAll().filter { invoiceIds.contains($0.invoiceId) }.count
        c.letters = lettersStore.readAll().filter { $0.projectId == id }.count
        c.drawings = drawingsStore.readAll().filter { $0.projectId == id }.count
        c.documents = documentsStore.readAll().filter { $0.projectId == id }.count
        c.inspections = inspectionsStore.readAll().filter { $0.projectId == id }.count
        c.isEmpty = c.total == 0
        return c
    }

    /// Deletes a project and everything in it (documents, drawings and
    /// documents' records, inspections). A project holding anything must be
    /// confirmed by typing its name (or number). Tasks, expenses and stock
    /// movements are kept, without the project. The folder is moved to the
    /// Trash by the caller.
    func deleteProject(id: String, confirm: String?) -> String? {
        guard let p = getProject(id: id) else { return "Project not found." }
        let contents = projectContents(id: id)
        if !contents.isEmpty {
            let typed = (confirm ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard typed == p.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() || typed == p.projectNumber.lowercased() else {
                return "Type the project’s name exactly to delete it."
            }
        }
        for b in boqsStore.readAll() where b.projectId == id { _ = deleteBOQ(id: b.id, includingIssued: true) }
        let quotationIds = quotationsStore.readAll().filter { $0.projectId == id }.map { $0.id }
        for q in quotationIds { _ = deleteQuotation(id: q, includingIssued: true) }
        for d in deliveryNotesStore.readAll() where d.projectId == id { _ = deleteDeliveryNote(id: d.id, includingIssued: true) }
        for i in invoicesStore.readAll() where i.projectId == id { _ = deleteInvoice(id: i.id, includingIssued: true) }
        for l in lettersStore.readAll() where l.projectId == id { _ = deleteLetter(id: l.id, force: true) }
        let drawings = drawingsStore.readAll()
        if drawings.contains(where: { $0.projectId == id }) { drawingsStore.writeAll(drawings.filter { $0.projectId != id }) }
        let documents = documentsStore.readAll()
        if documents.contains(where: { $0.projectId == id }) { documentsStore.writeAll(documents.filter { $0.projectId != id }) }
        let inspections = inspectionsStore.readAll()
        if inspections.contains(where: { $0.projectId == id }) { inspectionsStore.writeAll(inspections.filter { $0.projectId != id }) }
        let requests = signRequestsStore.readAll()
        if requests.contains(where: { quotationIds.contains($0.documentId) && $0.status == "Pending" }) {
            for r in requests where quotationIds.contains(r.documentId) && r.status == "Pending" { _ = withdrawSignRequest(id: r.id) }
        }
        var tasks = tasksStore.readAll()
        if tasks.contains(where: { $0.projectId == id }) {
            for i in tasks.indices where tasks[i].projectId == id { tasks[i].projectId = nil }
            tasksStore.writeAll(tasks)
        }
        var expenses = expensesStore.readAll()
        if expenses.contains(where: { $0.projectId == id }) {
            for i in expenses.indices where expenses[i].projectId == id { expenses[i].projectId = nil }
            expensesStore.writeAll(expenses)
        }
        let activity = activityStore.readAll()
        if activity.contains(where: { $0.projectId == id }) { activityStore.writeAll(activity.filter { $0.projectId != id }) }
        var projects = projectsStore.readAll()
        projects.removeAll { $0.id == id }
        projectsStore.writeAll(projects)
        logActivity(projectId: nil, "Project deleted", reference: "\(p.projectNumber) — \(p.name)")
        return nil
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
    /// Who a project or document was made by, set by hand (e.g. for one
    /// made before names were recorded). Kept in the record itself, so
    /// every Mac shows it; `file` is its store, e.g. "projects.json".
    func setCreator(file: String, id: String, name: String) -> String? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "Choose who made it." }
        let url = dataDir.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url), var list = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]],
              let i = list.firstIndex(where: { ($0["id"] as? String) == id }) else { return "Not found." }
        let before = list[i]["createdBy"] as? String
        guard before != clean else { return nil }
        list[i]["createdBy"] = clean
        // Not this Mac's: "mine" then goes by the name.
        list[i].removeValue(forKey: "createdByDevice")
        guard let out = try? JSONSerialization.data(withJSONObject: list, options: [.withoutEscapingSlashes]) else { return "It couldn’t be saved." }
        StoreFile.write(out, to: url)
        logActivity(projectId: file == "projects.json" ? id : nil, "Made by set to \(clean)", reference: before.map { "was \($0)" })
        return nil
    }

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
        var newJob: String? = nil
        if payload.keys.contains("jobType") {
            let job = normalJobType(payload["jobType"])
            if job != normalJobType(items[i].jobType) { newJob = job }
            items[i].jobType = job
        }
        projectsStore.writeAll(items)
        if logChange { logActivity(projectId: id, "Project details edited", reference: newJob.map { "now a \($0.lowercased()) job" }) }
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
        var letters = lettersStore.readAll()
        for j in letters.indices where letters[j].projectId == id && letters[j].status == "Draft" { letters[j].letterNumber = renumber(letters[j].letterNumber) }
        lettersStore.writeAll(letters)
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

    /// A document's item names in Chinese: its own choice, or else Settings'.
    func printsInChinese(_ own: String?) -> Bool {
        (own ?? getCompanySettings().documentLanguage) == "Chinese"
    }

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
            // Items from the official SP list already have the same id everywhere.
            if items[i].id.hasPrefix("item_sp_") { taken.insert(items[i].id); continue }
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
                id: seed.spProductNo.map(spProductItemId) ?? makeId("item"), sourceKey: sourceKey, itemCode: seed.itemCode,
                category: seed.category, itemName: seed.name, unit: "pc",
                weightKg: seed.weightKg, unitSalePrice: seed.unitSalePriceHKD,
                unitRentalPrice: seed.unitRentalPriceHKD, applicableTypes: seed.applicableTypes,
                notes: seed.spProductNo.map { "SP Product No.: \($0)" }, isArchived: false,
                chineseName: seed.chineseName
            )
        }
        priceListItemsStore.insertMany(mapped)
    }

    /// Items from the official SP Material List that the SP list doesn't
    /// have yet (lists made before they were added to the app): added once,
    /// at the end of their categories. An item already there — by its id,
    /// or by name, even if archived — is left alone.
    func addMissingSPProducts(_ seeds: [SeedPriceItem]) {
        guard priceListsStore.readAll().contains(where: { $0.sourceKey == "SP" }) else { return }
        let all = priceListItemsStore.readAll()
        let sp = all.filter { $0.sourceKey == "SP" }
        let norm: (String) -> String = { $0.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ") }
        let ids = Set(all.map { $0.id })
        let names = Set(sp.map { norm($0.itemName) })
        var added: [PriceListItem] = []
        for seed in seeds {
            guard let product = seed.spProductNo else { continue }
            let id = spProductItemId(product)
            guard !ids.contains(id), !names.contains(norm(seed.name)) else { continue }
            let codes = Set((sp + added).map { $0.itemCode.lowercased() })
            var code = seed.itemCode
            if codes.contains(code.lowercased()) { code = product }
            added.append(PriceListItem(
                id: id, sourceKey: "SP", itemCode: code, category: seed.category, itemName: seed.name, unit: "pc",
                weightKg: seed.weightKg, unitSalePrice: seed.unitSalePriceHKD, unitRentalPrice: seed.unitRentalPriceHKD,
                applicableTypes: seed.applicableTypes, notes: "SP Product No.: \(product)", isArchived: false,
                chineseName: seed.chineseName
            ))
        }
        guard !added.isEmpty else { return }
        priceListItemsStore.insertMany(added)
        logActivity(projectId: nil, "\(added.count) items added to the SP Material List", reference: "from the official SP list")
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

    func uniqueItemCode(sourceKey: String, preferred: String?) -> String {
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

    /// A price-list item's Sale or Rental price in the base currency —
    /// converted ones rounded to the nearest 0.1 (falls back to the other
    /// price if one is blank).
    func basePrice(_ item: PriceListItem, mode: String, rates: [String: Double]) -> Double? {
        let primary = mode == "Sale" ? item.unitSalePrice : item.unitRentalPrice
        let fallback = mode == "Sale" ? item.unitRentalPrice : item.unitSalePrice
        guard let raw = primary ?? fallback else { return nil }
        let rate = rates[item.sourceKey] ?? 1
        return convertedPrice(raw, rate: rate)
    }

    /// The same list of items with prices converted to the base currency —
    /// what the BOQ / quotation / invoice pickers use.
    func inBaseCurrency(_ items: [PriceListItem]) -> [PriceListItem] {
        let rates = conversionRates()
        return items.map { item in
            let rate = rates[item.sourceKey] ?? 1
            guard rate != 1 else { return item }
            var c = item
            c.unitSalePrice = item.unitSalePrice.map { convertedPrice($0, rate: rate) }
            c.unitRentalPrice = item.unitRentalPrice.map { convertedPrice($0, rate: rate) }
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

    /// Settings › Invoices has one "Standard Terms" box now: the bank
    /// details are part of it. Bank details kept on their own are added
    /// under the standard terms, and under any invoice's own terms that
    /// don't already have them, so every invoice prints as before.
    func mergeBankDetailsIntoTermsIfNeeded() {
        var settings = getCompanySettings()
        guard let bank = nonBlank(settings.bankDetails) else { return }
        let firstLine = bank.split(separator: "\n").first.map { $0.trimmingCharacters(in: .whitespaces) } ?? bank
        func withBank(_ terms: String?) -> String {
            guard let t = nonBlank(terms) else { return bank }
            return t.contains(firstLine) ? t : t + "\n\n" + bank
        }
        var invs = invoicesStore.readAll()
        var changed = false
        for i in invs.indices where invs[i].paymentTerms != nil {
            let merged = withBank(invs[i].paymentTerms)
            if merged != invs[i].paymentTerms { invs[i].paymentTerms = merged; changed = true }
        }
        if changed { invoicesStore.writeAll(invs) }
        settings.defaultPaymentTerms = withBank(settings.defaultPaymentTerms)
        settings.bankDetails = nil
        saveCompanySettingsDirect(settings)
    }

    /// Once: draft invoices still carrying the payment terms copied from
    /// their quotation (never edited) follow Settings › Invoices instead.
    func linkDraftInvoiceTermsToSettingsIfNeeded() {
        let key = "ScaffoldPro.invoiceTermsFollowSettings"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        let quotations = Dictionary(quotationsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let standard = nonBlank(getCompanySettings().defaultPaymentTerms)
        var invs = invoicesStore.readAll()
        var changed = false
        for i in invs.indices where invs[i].status == "Draft" {
            guard let terms = invs[i].paymentTerms else { continue }
            let copied = invs[i].sourceQuotationId.flatMap { quotations[$0] }.map { $0.paymentTerms == terms } ?? false
            if copied || nonBlank(terms) == standard {
                invs[i].paymentTerms = nil
                changed = true
            }
        }
        if changed { invoicesStore.writeAll(invs) }
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
        if pinned {
            // A newly pinned item goes at the end of the Pinned box.
            if items[index].isPinned != true {
                let last = items.filter { $0.isPinned == true && $0.sourceKey == items[index].sourceKey }.compactMap { $0.pinOrder }.max() ?? -1
                items[index].pinOrder = last + 1
            }
            items[index].isPinned = true
        } else {
            items[index].isPinned = nil
            items[index].pinOrder = nil
        }
        priceListItemsStore.writeAll(items)
        return nil
    }

    /// The pinned items dragged into a new order in the Pinned box. `ids`
    /// may be only some of them (the ones a search shows): they take the
    /// places those ones had, in the new order, and the others stay put.
    func reorderPinnedItems(ids: [String]) -> String? {
        var items = priceListItemsStore.readAll()
        guard let firstId = ids.first, let first = items.first(where: { $0.id == firstId }) else { return nil }
        let pinned = items.indices
            .filter { items[$0].isPinned == true && items[$0].sourceKey == first.sourceKey }
            .sorted { a, b in
                let oa = items[a].pinOrder ?? Int.max, ob = items[b].pinOrder ?? Int.max
                if oa != ob { return oa < ob }
                return items[a].itemCode.localizedStandardCompare(items[b].itemCode) == .orderedAscending
            }
        let wanted = Set(ids)
        var queue = ids.compactMap { id in pinned.first { items[$0].id == id } }
        var order: [Int] = []
        for i in pinned {
            if wanted.contains(items[i].id), !queue.isEmpty { order.append(queue.removeFirst()) } else { order.append(i) }
        }
        for (place, i) in order.enumerated() { items[i].pinOrder = place }
        priceListItemsStore.writeAll(items)
        return nil
    }

    // ---- Bills of Quantities (Phase 7) ----

    /// A BOQ's lines in its order: as in the material list (the
    /// default), by item code, by description, or as arranged.
    func lineItems(for boqId: String) -> [BOQLineItem] {
        sortedLines(boqLineItemsStore.readAll().filter { $0.boqId == boqId }, mode: getBOQ(id: boqId)?.lineSort, itemId: { $0.priceListItemId },
                    code: { $0.itemCode }, description: { $0.itemDescription }, order: { $0.sortOrder })
    }

    func sortedLines<T>(_ lines: [T], mode: String?, itemId: (T) -> String?, code: (T) -> String, description: (T) -> String, order: (T) -> Int) -> [T] {
        switch mode {
        case "manual": return lines.sorted { order($0) < order($1) }
        case "description":
            return lines.sorted { a, b in
                let c = description(a).localizedStandardCompare(description(b))
                return c == .orderedSame ? order(a) < order(b) : c == .orderedAscending
            }
        case "code": return byItemCode(lines, code: code, order: order)
        default: return byMaterialList(lines, itemId: itemId, code: code, description: description, order: order)
        }
    }

    /// The material list's order. By type first — the list's categories in
    /// its own order (Base Items, Standards, Ledgers, Face Braces, Steel
    /// Decks, Toe Boards…: the group number at the front of their item
    /// codes, the same in both lists) — then, within a type, the list's own
    /// order (as dragged in the Material List). A type with items from both
    /// lists (SP and SCAFOM) goes by length instead, shortest first: a 0.73m
    /// ledger (SP), a 1.40m (SCAFOM), a 2.57m (SP). Items not on a material
    /// list (delivery, custom items) come last, in the order added.
    func byMaterialList<T>(_ lines: [T], itemId: (T) -> String?, code: (T) -> String, description: (T) -> String, order: (T) -> Int) -> [T] {
        let all = priceListItemsStore.readAll()
        let items = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let group: (String) -> Int = { Int($0.split(separator: ".").first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "") ?? Int.max }
        // A type: the item's category, as both lists name it, else what its name says.
        let typeOf: (PriceListItem) -> String = { item in
            let category = materialCategory(item.category ?? "")
            return category.isEmpty ? "name: " + materialKind(item.itemName) : category
        }
        // Each type's place: the group its items have in the lists (Ledgers 4, Face Braces 6…).
        var rank: [String: Int] = [:]
        for item in all { rank[typeOf(item)] = min(rank[typeOf(item)] ?? Int.max, group(item.itemCode)) }
        let keys = lines.map { line -> (listed: Bool, rank: Int, type: String, source: String, place: Int, code: String, lengths: [Double]) in
            guard let id = itemId(line), let item = items[id] else {
                return (false, Int.max, "", "", Int.max, code(line), materialLengths(description(line)))
            }
            let type = typeOf(item)
            return (true, rank[type] ?? Int.max, type, item.sourceKey, item.sortOrder ?? Int.max, item.itemCode, materialLengths(item.itemName))
        }
        var sources: [String: Set<String>] = [:]
        for k in keys where k.listed { sources[k.type, default: []].insert(k.source) }
        // The shorter one first (by the first size, then the next); nil = the same sizes.
        let shorter: ([Double], [Double]) -> Bool? = { a, b in
            for (x, y) in zip(a, b) where x != y { return x < y }
            return a.count == b.count ? nil : a.count < b.count
        }
        let sorted = lines.indices.sorted { ia, ib in
            let a = keys[ia], b = keys[ib]
            if a.listed != b.listed { return a.listed }
            if a.listed {
                if a.rank != b.rank { return a.rank < b.rank }
                if a.type != b.type { return a.type < b.type }
                if (sources[a.type]?.count ?? 0) > 1, let first = shorter(a.lengths, b.lengths) { return first }
                if a.source != b.source { return a.source > b.source } // "SP" before "SCAFOM"
                if a.place != b.place { return a.place < b.place }
                let c = a.code.localizedStandardCompare(b.code)
                if c != .orderedSame { return c == .orderedAscending }
            }
            return order(lines[ia]) < order(lines[ib])
        }
        return sorted.map { lines[$0] }
    }

    /// How a BOQ's items are listed. Switching to "As arranged" keeps the
    /// order shown; linked quotations follow.
    func setBOQLineSort(id: String, mode: String) -> String? {
        guard ["list", "code", "description", "manual"].contains(mode) else { return "Choose how to sort." }
        let shown = lineItems(for: id)
        var boqs = boqsStore.readAll()
        guard let i = boqs.firstIndex(where: { $0.id == id }) else { return "BOQ not found." }
        guard boqs[i].status == "Draft" else { return "This BOQ is issued and can no longer be edited." }
        boqs[i].lineSort = mode == "list" ? nil : mode
        boqs[i].updatedAt = nowISO()
        boqsStore.writeAll(boqs)
        if mode == "manual" { freezeBOQOrder(id: id, ids: shown.map { $0.id }) }
        syncLinkedQuotations(boqId: id)
        return nil
    }

    /// Stores an order as the BOQ's own (sortOrder 0, 1, 2…).
    func freezeBOQOrder(id: String, ids: [String]) {
        var all = boqLineItemsStore.readAll()
        let position = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        var changed = false
        for i in all.indices where all[i].boqId == id {
            if let p = position[all[i].id], all[i].sortOrder != p { all[i].sortOrder = p; changed = true }
        }
        if changed { boqLineItemsStore.writeAll(all) }
    }

    func setBOQManual(_ id: String) {
        var boqs = boqsStore.readAll()
        guard let i = boqs.firstIndex(where: { $0.id == id }), boqs[i].lineSort != "manual" else { return }
        boqs[i].lineSort = "manual"
        boqsStore.writeAll(boqs)
    }

    func grandTotal(for boqId: String) -> Double {
        boqMoneyTotal(lineItems(for: boqId))
    }

    func boqMoneyTotal(_ items: [BOQLineItem]) -> Double {
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
        // Linked quotations change with it.
        syncLinkedQuotations(boqId: boq.id)
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

    func totalWeight(for items: [BOQLineItem]) -> Double {
        let kg = items.reduce(Decimal(0)) { $0 + decimalOf($1.quantity.rounded()) * decimalOf($1.weightKg ?? 0) }
        return doubleOf(roundToCents(kg))
    }

    /// A combined count's source BOQ numbers (nil if it isn't one). BOQs
    /// combined before this was recorded are known by their notes.
    func combinedSources(_ boq: BillOfQuantities) -> [String]? {
        if let list = boq.combinedFrom, !list.isEmpty { return list }
        guard let notes = boq.notes, notes.hasPrefix("Combined from ") else { return nil }
        let list = notes.dropFirst("Combined from ".count).split(separator: "\n").first.map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: ". ")).components(separatedBy: ", ").filter { !$0.isEmpty } ?? []
        return list.isEmpty ? nil : list
    }

    func listBOQSummaries(projectId: String) -> [BOQSummary] {
        let names = authorsByRecord("boqs.json")
        return boqsStore.readAll()
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
                summary.combinedFrom = combinedSources(boq)
                summary.combined = summary.combinedFrom != nil
                summary.createdBy = names[boq.id]?.createdBy
                summary.lastEditedBy = names[boq.id]?.lastEditedBy
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
            boqsNow[i].combinedFrom = boqs.map { $0.boqNumber }
            boqsStore.writeAll(boqsNow)
            combined = boqsNow[i]
        }
        logActivity(projectId: project.id, "BOQ combined from \(boqs.map { $0.boqNumber }.joined(separator: ", "))", reference: combined.boqNumber)
        return (combined.id, nil)
    }

    /// The materials from Settings → BOQ Defaults, priced for the BOQ's
    /// Sale / Rental mode as if picked from the list. Items since deleted
    /// from the material list are skipped.
    func addDefaultBOQItems(to boq: BillOfQuantities) {
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
        detail.deliveryRates = getCompanySettings().deliveryRates ?? defaultDeliveryRates
        detail.chineseNames = chineseNames(for: items, id: { $0.id }, itemId: { $0.priceListItemId }, description: { $0.itemDescription })
        detail.terms = boq.terms.map { isLegacyBOQTerms($0) ? standardBOQTerms() : $0 }
        detail.signatureSection = boq.signatureSection == true
        detail.standardTerms = standardBOQTerms()
        detail.language = boq.language
        detail.defaultLanguage = getCompanySettings().documentLanguage ?? "English"
        detail.lineSort = boq.lineSort ?? "list"
        detail.linkedQuotations = quotationsStore.readAll().filter { $0.sourceBOQId == boq.id && $0.boqLinked == true }
            .sorted { $0.quotationNumber < $1.quotationNumber }
            .map { LinkedDocument(id: $0.id, number: $0.quotationNumber, status: $0.status) }
        return detail
    }

    /// How the BQ sheet is printed; allowed on issued BOQs too, as it
    /// changes only the page, not the content.
    /// Portrait (the letterhead) or Landscape (the BQ sheet) for a quotation.
    func setQuotationOrientation(id: String, orientation: String) -> String? {
        guard ["Landscape", "Portrait"].contains(orientation) else { return "Choose Landscape or Portrait." }
        var qs = quotationsStore.readAll()
        guard let i = qs.firstIndex(where: { $0.id == id }) else { return "Quotation not found." }
        qs[i].orientation = orientation == "Landscape" ? "Landscape" : nil
        quotationsStore.writeAll(qs)
        return nil
    }

    func setBOQOrientation(id: String, orientation: String) -> String? {
        guard ["Landscape", "Portrait"].contains(orientation) else { return "Choose Landscape or Portrait." }
        var boqs = boqsStore.readAll()
        guard let i = boqs.firstIndex(where: { $0.id == id }) else { return "BOQ not found." }
        boqs[i].orientation = orientation
        boqsStore.writeAll(boqs)
        return nil
    }

    func touchBOQ(_ id: String) {
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
        // Linked quotations change with it.
        syncLinkedQuotations(boqId: boqId)
        return nil
    }

    func updateBOQLineItem(id: String, quantity: Double?, appliedUnitPrice: Double?, quantityFormula: String? = nil) -> String? {
        var items = boqLineItemsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        guard let boq = getBOQ(id: items[index].boqId) else { return "BOQ not found." }
        guard boq.status == "Draft" else { return "This BOQ is issued and can no longer be edited." }

        // Quantities are always whole numbers in this app (section note:
        // integer-only quantities), regardless of what a client sends.
        if let quantity = quantity {
            items[index].quantity = quantity.rounded()
            items[index].quantityFormula = lineFormula(quantityFormula)
        }
        if let appliedUnitPrice = appliedUnitPrice { items[index].appliedUnitPrice = appliedUnitPrice }
        boqLineItemsStore.writeAll(items)
        touchBOQ(boq.id)
        // Linked quotations change with it.
        syncLinkedQuotations(boqId: boq.id)
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
        // Linked quotations take the new Sale / Rental, mark-up and prices.
        if newMode != oldMode || newMarkup != oldMarkup { syncLinkedQuotations(boqId: id) }
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
        var lines = lineItems(for: target.boqId)
        setBOQManual(target.boqId)
        guard let from = lines.firstIndex(where: { $0.id == id }) else { return nil }
        let to = from + (direction < 0 ? -1 : 1)
        guard to >= 0, to < lines.count else { return nil }
        lines.swapAt(from, to)
        for (order, line) in lines.enumerated() {
            if let i = all.firstIndex(where: { $0.id == line.id }) { all[i].sortOrder = order }
        }
        boqLineItemsStore.writeAll(all)
        touchBOQ(boq.id)
        // Linked quotations change with it.
        syncLinkedQuotations(boqId: boq.id)
        return nil
    }

    /// Puts a BOQ's lines in the order given (dragged in the editor); any
    /// line not listed keeps its place after them.
    func reorderBOQLineItems(boqId: String, ids: [String]) -> String? {
        guard let boq = getBOQ(id: boqId) else { return "BOQ not found." }
        guard boq.status == "Draft" else { return "This BOQ is issued and can no longer be edited." }
        // Dragged: listed as arranged from now on.
        let shownIds = lineItems(for: boqId).map { $0.id }
        setBOQManual(boqId)
        var all = boqLineItemsStore.readAll()
        for (order, lineId) in reordered(shownIds, by: ids).enumerated() {
            if let i = all.firstIndex(where: { $0.id == lineId }) { all[i].sortOrder = order }
        }
        boqLineItemsStore.writeAll(all)
        touchBOQ(boq.id)
        // Linked quotations change with it.
        syncLinkedQuotations(boqId: boq.id)
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
        // Linked quotations change with it.
        syncLinkedQuotations(boqId: boq.id)
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
        // Linked quotations change with it.
        syncLinkedQuotations(boqId: boq.id)
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
        // Back to Draft: its linked Draft quotations' changes since it was
        // issued are made to it (and so to one another).
        if changed, status == "Draft" {
            for q in quotationsStore.readAll() where q.sourceBOQId == id && q.boqLinked == true && q.status == "Draft" { pushQuotationToBOQ(q.id) }
        }
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

    /// The language of a document's item names ("English", "Chinese", or
    /// nil for Settings' choice): only how it's printed, so issued ones too.
    func setDocumentLanguage(kind: String, id: String, language: String?) -> String? {
        let value = ["English", "Chinese"].contains(language ?? "") ? language : nil
        if kind == "quotation" {
            var all = quotationsStore.readAll()
            guard let i = all.firstIndex(where: { $0.id == id }) else { return "Quotation not found." }
            all[i].language = value
            quotationsStore.writeAll(all)
        } else if kind == "boq" {
            var all = boqsStore.readAll()
            guard let i = all.firstIndex(where: { $0.id == id }) else { return "BOQ not found." }
            all[i].language = value
            boqsStore.writeAll(all)
        } else {
            var all = deliveryNotesStore.readAll()
            guard let i = all.firstIndex(where: { $0.id == id }) else { return "Delivery note not found." }
            all[i].language = value
            deliveryNotesStore.writeAll(all)
        }
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
        var days = quotationDeliveriesStore.readAll()
        if days.contains(where: { $0.quotationId == id }) {
            days.removeAll { $0.quotationId == id }
            quotationDeliveriesStore.writeAll(days)
        }
        // Quotations linked to it keep their items, no longer linked.
        var qs = quotationsStore.readAll()
        if qs.contains(where: { $0.sourceBOQId == id && $0.boqLinked == true }) {
            for i in qs.indices where qs[i].sourceBOQId == id { qs[i].boqLinked = nil }
            quotationsStore.writeAll(qs)
        }
        return nil
    }
}

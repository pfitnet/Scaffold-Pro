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
    /// Who made it and who last worked on it; `mine` when that was this
    /// Mac's user.
    var createdBy: String? = nil
    var lastEditedBy: String? = nil
    var lastEditedAt: String? = nil
    var mine = true
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
    /// The Dashboard is personal: the projects this Mac's user worked on,
    /// and the team's activity apart from theirs.
    var myProjects: [MyProject] = []
    var teamActivity: [ActivityRow] = []
    var userName = ""
    /// Scaffold inspections due within 3 days or overdue; my open tasks.
    var inspectionsDue: [InspectionDue] = []
    var myTasks: [TaskRow] = []
}

/// A scaffold inspection by a competent person (Construction Sites
/// (Safety) Regulations: before first use, then at least every 14 days,
/// recorded on Form 5). One structure of a project per record.
struct ScaffoldInspection: Codable {
    var id: String
    var projectId: String
    /// What was inspected, e.g. "Truss-out at 5/F".
    var structure: String
    var location: String?
    /// yyyy-MM-dd
    var inspectedOn: String
    /// The competent person.
    var inspector: String
    /// "Safe", "Safe with remarks" or "Unsafe".
    var result: String
    var remarks: String?
    var actionTaken: String?
    /// yyyy-MM-dd — 14 days on unless changed; nil once dismantled.
    var nextDue: String?
    /// Taken down: no further inspections are due for it.
    var dismantled: Bool?
    var createdBy: String?
    var createdAt: String
    var updatedAt: String
}

/// A structure's next inspection (the latest record for it).
struct InspectionDue: Codable {
    var projectId: String
    var projectNumber: String
    var projectName: String
    var structure: String
    var lastInspected: String
    var lastResult: String
    var nextDue: String
    /// Negative: overdue.
    var daysLeft: Int
    var url: String
}

/// A to-do for someone in the team, optionally for a project.
struct TeamTask: Codable {
    var id: String
    var title: String
    var notes: String?
    var projectId: String?
    /// Who it's for (a user's name); nil = anyone.
    var assignee: String?
    /// yyyy-MM-dd
    var dueDate: String?
    /// HH:mm, if it's at a time (shown in the Calendar's week).
    var dueTime: String? = nil
    /// HH:mm: when it ends. With a start time, it's a scheduled event
    /// (a meeting, a site visit) — a block on the Calendar, not a to-do.
    var endTime: String? = nil
    /// For a whole team (e.g. "Site") instead of one person.
    var team: String? = nil
    /// "High" or nil (normal).
    var priority: String?
    var done: Bool
    var doneAt: String?
    var doneBy: String?
    var createdBy: String?
    var createdAt: String
    var updatedAt: String
}

/// Who a task or event can be for, beyond the people: this Mac's user and
/// the teams.
struct TaskForOptions: Codable {
    var me: String
    var teams: [String]
}

struct TaskRow: Codable {
    var task: TeamTask
    var projectNumber: String?
    var projectName: String?
    /// For this Mac's user (or for anyone and made by them).
    var mine: Bool
    var overdue: Bool
}

/// One thing on the Calendar.
struct CalendarEvent: Codable {
    /// yyyy-MM-dd
    var date: String
    /// Delivery, Inspection, Task, Quotation, Invoice, Lead, Expiry, Project
    var kind: String
    var title: String
    var detail: String?
    var url: String?
    var done: Bool = false
    var person: String? = nil
    var overdue: Bool = false
    /// HH:mm — at a time of day (else all day).
    var time: String? = nil
    /// HH:mm — when it ends (a scheduled event); and its id, to change it.
    var endTime: String? = nil
    var id: String? = nil
}

/// A possible customer being worked on (Marketing › Leads) — not a
/// client yet. "Convert to Client" makes it one.
struct Lead: Codable {
    var id: String
    var company: String
    var contactPerson: String?
    var phone: String?
    var email: String?
    /// How they came: Referral, Website, Tender, Cold Call, Repeat Client, Site Visit, Other.
    var source: String
    /// New, Contacted, Quoted, Won or Lost.
    var status: String
    var estimatedValue: Double?
    /// yyyy-MM-dd — shown in Follow-ups from that day.
    var nextFollowUp: String?
    var notes: String?
    /// Who's looking after it (a user's name).
    var owner: String?
    /// The client made from it.
    var clientId: String?
    var createdAt: String
    var updatedAt: String
}

struct MarketingMonth: Codable {
    /// yyyy-MM
    var month: String
    var quotedCount: Int
    var quotedValue: Double
    var wonCount: Int
}

/// One quotation sent in the last 12 months, for Marketing's interactive
/// overview (filtering by month and client, and the list under the chart).
struct MarketingQuote: Codable {
    var id: String
    var number: String
    /// yyyy-MM-dd and yyyy-MM.
    var date: String
    var month: String
    var clientId: String?
    var clientName: String?
    var projectNumber: String?
    var projectName: String?
    var subject: String?
    var value: Double
    /// Signed by the client, or marked "Client agreed".
    var won: Bool
}

struct MarketingClient: Codable {
    var id: String
    var name: String
    var invoiced: Double
    var quotations: Int
    var won: Int
    var lastActivity: String?
}

/// Something to chase: a quotation with no reply, a client gone quiet, a lead due.
struct MarketingFollowUp: Codable {
    var kind: String
    var title: String
    var detail: String
    var days: Int
    var url: String
    var owner: String?
}

/// A project for a reference list (tenders, the company profile).
struct ProjectReference: Codable {
    var projectNumber: String
    var name: String
    var clientName: String?
    var siteName: String?
    var status: String
    var startDate: String?
    var structures: [String]
    var quotedValue: Double
    var invoicedValue: Double
}

struct MarketingSummary: Codable {
    var currency: String
    /// The last 12 months, oldest first.
    var months: [MarketingMonth]
    var quotedCount: Int
    var quotedValue: Double
    var wonCount: Int
    /// Won ÷ quoted over the 12 months (0–1).
    var winRate: Double
    var averageQuote: Double
    var newClients: Int
    var openLeads: Int
    var pipelineValue: Double
    var leadSources: [String: Int]
    var topClients: [MarketingClient]
    /// Every quotation behind `months`, newest first.
    var quotes: [MarketingQuote] = []
    var followUps: [MarketingFollowUp]
    var references: [ProjectReference]
}

/// Marketing › Client Report: the quotations a client was sent in a period.
struct ClientQuoteRow: Codable {
    var id: String
    var number: String
    var date: String
    var status: String
    var projectNumber: String?
    var projectName: String?
    var subject: String?
    var pricingMode: String?
    var value: Double
    var won: Bool
}

struct ClientQuoteReport: Codable {
    var clientId: String?
    var clientName: String
    var from: String
    var to: String
    var currency: String
    var rows: [ClientQuoteRow]
    var total: Double
    var wonCount: Int
    var wonValue: Double
}

/// Marketing › Promotions: a campaign to win new work — who it's aimed at,
/// the letter sent them, and how each answered.
struct Promotion: Codable {
    var id: String
    var name: String
    /// "Letter", "Email", "Visit", "Call" or "Event".
    var channel: String
    /// "Planning", "Running" or "Done".
    var status: String
    var goal: String?
    /// The promotional letter: its "Re:" line and its body ({Company},
    /// {Contact} are filled in for each one it's written for).
    var subject: String?
    var bodyHTML: String?
    var targets: [PromoTarget]
    var createdAt: String
    var updatedAt: String
}

struct PromoTarget: Codable {
    var id: String
    /// "Lead", "Client" or "Other".
    var kind: String
    var refId: String?
    var name: String
    var contact: String?
    var address: String?
    /// "To Contact", "Sent", "Replied", "Meeting", "Won" or "Not Interested".
    var status: String
    var letterId: String?
    var lastAt: String?
    var note: String?
}

struct LeadSaveResult: Codable {
    var ok: Bool
    var error: String?
    var id: String?
}

/// A person's colour, so their name looks the same wherever it's shown and
/// on every Mac (kept with the shared data). By name, lowercased.
struct UserProfile: Codable {
    var id: String
    var name: String
    /// "#RRGGBB"; "" = the automatic colour.
    var color: String
    var updatedAt: String
    /// Their own Light / Dark ("System", "Light" or "Dark"), on any Mac
    /// and in ScaffoldPro Web; nil = not chosen.
    var appearance: String? = nil
}

/// The team a person is in (e.g. "Office", "Site"), set on their User
/// page — who "my team" is when posting an announcement.
struct TeamMembership: Codable {
    /// The person's name, lower-cased.
    var id: String
    var name: String
    var team: String?
    var updatedAt: String
    /// e.g. "Director" — printed under their name when they sign.
    var title: String? = nil
    /// Signs and chops quotations (a director).
    var canSign: Bool? = nil
    /// Signs and chops workers' employment agreements.
    var canSignAgreements: Bool? = nil
    /// HK ID card number — printed under their name on the agreements they sign.
    var idNumber: String? = nil
    /// Their full name (e.g. "William Chan"), printed with their signature
    /// and chop; nil = their ScaffoldPro name.
    var fullName: String? = nil
}

/// A person on the Team page: who they are, and the Macs (and other
/// devices) they use ScaffoldPro on.
struct TeamPerson: Codable {
    var name: String
    var team: String?
    var title: String?
    var canSign: Bool
    var canSignAgreements: Bool = false
    var idNumber: String? = nil
    var isMe: Bool
    var devices: [TeamMember]
    /// From Admin › Employees, when there's a record with the same name.
    var employeeNumber: String?
    var position: String?
    var phone: String?
    var hasSignature: Bool
    var hasChop: Bool
    var fullName: String? = nil
}

struct TeamPage: Codable {
    var me: String
    var people: [TeamPerson]
    var teams: [String]
    var sharing: Bool
}

/// A chat message. `conversation` is "everyone", "team:<team>" (lower
/// case) or "dm:<name>|<name>" (the two names lower-cased, in order).
struct ChatMessage: Codable {
    var id: String
    var conversation: String
    var author: String
    var text: String
    var createdAt: String
    var editedAt: String? = nil
    var deleted: Bool? = nil
    /// A GIF from GIPHY (its address), or a picture sent from a Mac (its
    /// file name in the shared folder's "Chat Files").
    var gifURL: String? = nil
    var file: String? = nil
    var fileName: String? = nil
    /// The message it answers.
    var replyTo: String? = nil
    /// Emoji → who reacted with it (lower-cased names).
    var reactions: [String: [String]]? = nil
}

struct ChatConversation: Codable {
    var id: String
    var title: String
    /// "everyone", "team" or "dm"
    var kind: String
    /// For a direct message: the other person.
    var with: String?
    var lastText: String?
    var lastAuthor: String?
    var lastAt: String?
    var count: Int
}

struct ChatPage: Codable {
    var me: String
    var myTeam: String?
    var people: [String]
    var conversations: [ChatConversation]
    var gifKey: String?
}

/// A request for a director to sign (and chop) a quotation.
struct SignRequest: Codable {
    var id: String
    var kind: String
    var documentId: String
    var number: String
    var projectNumber: String
    var projectName: String?
    var requestedBy: String
    var signer: String
    var note: String?
    /// "Pending", "Signed" or "Declined"
    var status: String
    var createdAt: String
    var decidedAt: String? = nil
    var reply: String? = nil
    /// The signed and chopped PDF, in the project's Quotations folder.
    var filePath: String? = nil
}

struct SignRequestsPage: Codable {
    var me: String
    var canSign: Bool
    /// Waiting for me to sign.
    var incoming: [SignRequest]
    /// Ones I asked for (newest first).
    var outgoing: [SignRequest]
    /// Everyone's, newest first (the last 60).
    var recent: [SignRequest]
    var signers: [String]
}

/// A message for the team: shown in a bar at the top of the Dashboard of
/// everyone it's for (everyone, or one team) until it runs out or they
/// close it.
struct Announcement: Codable {
    var id: String
    var message: String
    /// "Everyone", or a team's name.
    var audience: String
    var author: String
    var createdAt: String
    /// Last day it's shown (yyyy-MM-dd); nil = until it's taken down.
    var showUntil: String?
    var important: Bool
    /// Who has closed it (lower-cased names).
    var dismissedBy: [String]
    /// A request to sign and chop it stands for: it goes when the request is
    /// answered or withdrawn. Its page (Review) opens from the notice.
    var signRequestId: String? = nil
    var link: String? = nil
}

struct AnnouncementRow: Codable {
    var announcement: Announcement
    var mine: Bool
}

struct AnnouncementsPage: Codable {
    var me: String
    var myTeam: String?
    /// Every team someone is in.
    var teams: [String]
    /// Shown to me now (not closed, not run out).
    var visible: [AnnouncementRow]
    /// The ones I posted that are still running.
    var mine: [AnnouncementRow]
}

/// The User page: this Mac's user, their colour, and their own work.
struct UserPage: Codable {
    var name: String
    var computer: String
    var color: String?
    /// Working in a shared folder, and who else is in it.
    var sharing: Bool
    var members: [TeamMember]
    var myProjects: [MyProject]
    var myDocuments: [DocRow]
    var myActivity: [ActivityRow]
    /// Documents (and projects) they made, and ones they were the last to work on.
    var createdCount: Int
    var lastWorkedCount: Int
    var team: String? = nil
    var teams: [String] = []
}

struct MyProject: Codable {
    var id: String
    var projectNumber: String
    var name: String
    var clientName: String?
    var status: String
    var lastWorkedAt: String
    var createdBy: String? = nil
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
    /// "Scaffolding" or "Crane" — asked when the project is made. nil
    /// (projects made before) counts as scaffolding.
    var jobType: String? = nil
}

/// A project's kind of job as kept: "Crane", else "Scaffolding".
func normalJobType(_ value: Any?) -> String {
    ((value as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "crane" ? "Crane" : "Scaffolding"
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
    /// Its place in the "Pinned" box, as dragged there (nil = not moved:
    /// after the moved ones, by item code).
    var pinOrder: Int? = nil
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

/// The sizes in a material's name, in metres, in the order written:
/// "1.40m x 2.0m Face Brace" → [1.4, 2.0], "600mm Base Jack" → [0.6].
func materialLengths(_ name: String) -> [Double] {
    guard let pattern = try? NSRegularExpression(pattern: #"(\d+(?:\.\d+)?)\s?(mm|m)(?![a-z])"#, options: [.caseInsensitive]) else { return [] }
    let ns = name as NSString
    return pattern.matches(in: name, range: NSRange(location: 0, length: ns.length)).compactMap { m in
        guard let value = Double(ns.substring(with: m.range(at: 1))) else { return nil }
        return ns.substring(with: m.range(at: 2)).lowercased() == "mm" ? value / 1000 : value
    }
}

/// A material list category as both lists name it: SP's "Toe Boards" and
/// SCAFOM's "Steel Toe Boards" → "toe boards"; "Lattice Girders" and
/// "Lattice Gridders & Required Accessories" → "lattice girders".
func materialCategory(_ category: String) -> String {
    var c = category.lowercased().replacingOccurrences(of: "gridder", with: "girder")
    if let and = c.range(of: " & ") { c = String(c[..<and.lowerBound]) }
    c = c.replacingOccurrences(of: "steel ", with: "")
    return c.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// What a material is, without its sizes: "1.40m x 2.0m Face Brace" →
/// "face brace" (for items with no category).
func materialKind(_ name: String) -> String {
    name.replacingOccurrences(of: #"\d+(?:\.\d+)?\s?(mm|m)?(?![a-z])"#, with: " ", options: [.regularExpression, .caseInsensitive])
        .replacingOccurrences(of: #"(^|\s)x(\s|$)"#, with: " ", options: [.regularExpression, .caseInsensitive])
        .lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
}

/// An item's name on a document in the language chosen for it: its Chinese
/// name when Chinese is chosen and it has one, otherwise the English one.
func documentItemName(_ description: String, _ chinese: String?, inChinese: Bool) -> String {
    guard inChinese, let zh = chinese?.trimmingCharacters(in: .whitespacesAndNewlines), !zh.isEmpty else { return description }
    return zh
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
    /// As on the official SP Material List (items added from it).
    var chineseName: String? = nil
}

/// The id of an item from the official SP Material List ("GH36.414" →
/// "item_sp_gh36_414"): the same on every Mac, so the same item added on
/// two Macs at once is one item when they're merged.
func spProductItemId(_ productNo: String) -> String {
    "item_sp_" + productNo.lowercased().map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
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
    /// Who made it, and who last worked on it (their names).
    var createdBy: String? = nil
    var lastEditedBy: String? = nil
    /// Its documents (not cancelled ones) and when one last changed, for
    /// the Projects list's cards.
    var boqCount = 0
    var quotationCount = 0
    var invoiceCount = 0
    var deliveryNoteCount = 0
    var lastActivityAt: String? = nil
    /// "Scaffolding" or "Crane".
    var jobType = "Scaffolding"
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
    /// "Scaffolding" or "Crane".
    var jobType = "Scaffolding"
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
    /// The BOQ or quotation it's filed with ("BOQ" / "Quotation" and its
    /// id), like a drawing's; nil = the project in general.
    var linkedKind: String? = nil
    var linkedId: String? = nil
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
    var linkedKind: String? = nil
    var linkedId: String? = nil
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
    /// For the employment agreement (Batch 213).
    var chineseName: String? = nil
    /// "先生" or "女士".
    var honorific: String? = nil
    /// HK ID card number, e.g. "A123456(7)".
    var idNumber: String? = nil
    /// HK$ a day.
    var dailyWage: Double? = nil
}

struct WorkerError: Error {
    let message: String
}

struct WorkerActionResult: Codable {
    var ok: Bool
    var error: String?
    var worker: Worker?
}

// ---- A worker's employment agreement (Batch 213) ----

/// A worker's site-work employment agreement (簡易僱傭合約), made when the
/// worker is added: these terms and the worker's details fill the
/// company's template. Someone marked on the Team page as signing worker
/// agreements signs and chops it for the employer; the worker signs the
/// printed copy, and that copy is uploaded.
struct WorkerAgreement: Codable {
    var id: String
    var workerId: String
    /// yyyy-MM-dd
    var agreementDate: String
    var startDate: String
    var position: String
    /// HK$ a day (the basic wage).
    var dailyWage: Double
    /// "08:00" to "18:00".
    var hoursFrom: String
    var hoursTo: String
    /// Wages for a month are paid on this day of the next.
    var payDay: Int
    /// Days' notice (or wages instead) to end it.
    var noticeDays: Int
    /// Who signs for the employer (one of the agreement signers).
    var signatory: String? = nil
    var employerSignedBy: String? = nil
    var employerSignedAt: String? = nil
    /// The PDF with the employer's signature and chop.
    var employerSignedPath: String? = nil
    /// The copy signed by both (a PDF, or a photo or scan), uploaded.
    var signedCopyPath: String? = nil
    var signedCopyAt: String? = nil
    var createdAt: String
    var updatedAt: String
}

/// A worker on the Workers page's list.
struct WorkerRosterEntry: Codable {
    var worker: Worker
    var agreementNumber: String
    /// 0 no agreement, 1 made, 2 signed & chopped for the employer, 3 signed by the worker too.
    var stage: Int
    var signedBy: String?
    var documents: Int
    /// Documents expired or expiring within 30 days.
    var expiring: Int
}

/// The Workers page's agreement card for a worker.
struct WorkerAgreementPage: Codable {
    var agreement: WorkerAgreement?
    /// "W001-EA"
    var number: String
    /// Everyone who can sign worker agreements (Team page).
    var signers: [String]
    var me: String
    var canSign: Bool
    var hasSignature: Bool
    var employerSignedExists: Bool
    var signedCopyExists: Bool
    /// Details the agreement still needs, e.g. "the worker's ID card number".
    var missing: [String]
    /// Each signer's full name, as printed (ScaffoldPro name → full name).
    var fullNames: [String: String] = [:]
}

/// The agreement's words, laid out the same way on the PDF and in Word.
struct AgreementTerm: Encodable {
    var number: String
    var label: String
    /// After the label's colon; empty when the term's lines follow under it.
    var value: String
    var lines: [String] = []
}

struct AgreementSection: Encodable {
    var letter: String
    var title: String
    var terms: [AgreementTerm]
}

struct AgreementParty: Encodable {
    var heading: String
    /// Under the signing line: name, ID card number, role, date.
    var lines: [String]
}

struct AgreementContent: Encodable {
    var coverTitle = "Site-work Employment Agreement"
    var coverSubtitle = "簡易僱傭合約"
    var intro: String
    var sections: [AgreementSection]
    var closing: [String]
    var employer: AgreementParty
    var employee: AgreementParty
}

/// For js/docx-export.js: the agreement and the page it goes on.
struct AgreementWordLayout: Encodable {
    var ok = true
    var kind = "agreement"
    var paperSize: String
    var pageWidth: Double
    var pageHeight: Double
    var textLeft: Double
    var textRight: Double
    var contentBottom: Double
    var number: String
    var title = "Employment Agreement"
    var status = "Issued"
    var content: AgreementContent
    var workerId: String
    var projectNumber = ""
    var subfolder = "Contracts"
    var fileName: String
    var letterheadPNG = ""
    var fonts: [WordFont] = []
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
    /// Files that couldn't be copied (e.g. still only in iCloud then).
    var skipped: [String]? = nil
}

struct BackupSummary: Codable {
    var name: String
    var path: String
    var createdAt: String
    var kind: String
    var projectCount: Int
    var fileCount: Int
    var totalBytes: Int64
    /// How many files it couldn't copy (nil = none).
    var skippedCount: Int? = nil
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
    /// Who did it (this Mac's user), and on which Mac.
    var by: String? = nil
    var device: String? = nil
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
    /// Done by this Mac's user (or not known).
    var mine = true
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
        language = try c.decodeIfPresent(String.self, forKey: .language)
        boqLinked = try c.decodeIfPresent(Bool.self, forKey: .boqLinked)
        lineSort = try c.decodeIfPresent(String.self, forKey: .lineSort)
        // Every field added later must be read here too, or it's lost on the next load.
        directorSignedPath = try c.decodeIfPresent(String.self, forKey: .directorSignedPath)
        directorSignedAt = try c.decodeIfPresent(String.self, forKey: .directorSignedAt)
        directorSignedBy = try c.decodeIfPresent(String.self, forKey: .directorSignedBy)
        orientation = try c.decodeIfPresent(String.self, forKey: .orientation)
        parentQuotationId = try c.decodeIfPresent(String.self, forKey: .parentQuotationId)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
        clientAgreedAt = try c.decodeIfPresent(String.self, forKey: .clientAgreedAt)
        importedFromDocumentId = try c.decodeIfPresent(String.self, forKey: .importedFromDocumentId)
        buyBackEnabled = try c.decodeIfPresent(Bool.self, forKey: .buyBackEnabled)
        buyBackPercent = try c.decodeIfPresent(Double.self, forKey: .buyBackPercent)
        buyBackAfterMonths = try c.decodeIfPresent(Int.self, forKey: .buyBackAfterMonths)
        buyBackReductionPercent = try c.decodeIfPresent(Double.self, forKey: .buyBackReductionPercent)
        buyBackEndMonths = try c.decodeIfPresent(Int.self, forKey: .buyBackEndMonths)
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

/// A price from another currency (EUR × 8.93 → HKD): rounded to the
/// nearest 0.1. A price already in the base currency (rate 1) is kept as is.
func convertedPrice(_ value: Double, rate: Double) -> Double {
    guard rate != 1 else { return value }
    var input = decimalOf(value) * decimalOf(rate)
    var result = Decimal()
    NSDecimalRound(&result, &input, 1, .plain)
    return doubleOf(result)
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
    /// Item names on the PDF: "English" or "Chinese"; nil = Settings' choice.
    var language: String? = nil
    /// The BOQs it was combined from (a combined count), by number.
    var combinedFrom: [String]? = nil
    /// How its items are listed (and printed): nil/"code" by item code,
    /// "description" A–Z, "manual" as arranged (dragged).
    var lineSort: String? = nil
}

struct BOQCharge: Codable {
    /// "D1", "D2"… when blank.
    var code: String?
    var name: String
    var amount: Double
    /// Printed instead of the amount, e.g. "Free of Charge".
    var amountText: String? = nil
}

struct BOQRatesSection: Codable {
    var title: String
    var rates: [ManpowerRate]
    var note: String?
}

/// A sum typed into a quantity or price box (js/calc-input.js), kept when
/// it is one — "14+28", "2 x 7" — and nil for a plain number or nothing.
func lineFormula(_ text: String?) -> String? {
    guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty, t.count <= 200 else { return nil }
    let digitsAndOps = t.replacingOccurrences(of: ",", with: "")
    return digitsAndOps.range(of: "[0-9.)]\\s*[-+*/×xX÷−–]\\s*[-(0-9.]", options: .regularExpression) != nil ? t : nil
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
    /// The sum typed for the quantity (e.g. "14+28"), shown again when the
    /// box is clicked; nil when a plain number was typed.
    var quantityFormula: String? = nil
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
    /// A combined count (made from other BOQs): listed apart, not added
    /// to the project's total weight. `combinedFrom` = their numbers.
    var combined = false
    var combinedFrom: [String]? = nil
    /// Who made it, and who last worked on it (their names).
    var createdBy: String? = nil
    var lastEditedBy: String? = nil
}

struct BOQDetail: Codable {
    /// Delivery charges by weight (Settings), for "+ Add Section › Delivery Charges".
    var deliveryRates: [DeliveryRate]? = nil
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
    /// Item names on the PDF: the BOQ's own choice (nil = Settings'), and Settings'.
    var language: String? = nil
    var defaultLanguage = "English"
    /// The quotations kept in step with this BOQ.
    var linkedQuotations: [LinkedDocument] = []
    var lineSort = "code"
}

/// One document in a chain: BOQ › Quotation › Delivery Notes › Invoices.
struct ChainLink: Codable {
    /// "BOQ", "Quotation", "DeliveryNote", "Invoice"
    var kind: String
    var id: String
    var number: String
    var status: String
    var url: String
    /// The document open.
    var current: Bool
}

/// A document linked to the one open (number and status, for a link).
struct LinkedDocument: Codable {
    var id: String
    var number: String
    var status: String
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
    /// Item names on the PDF: "English" or "Chinese"; nil = Settings' choice.
    var language: String? = nil
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
    /// Signed and chopped by a director (Team › Signatures): the PDF, when, who.
    var directorSignedPath: String? = nil
    var directorSignedAt: String? = nil
    var directorSignedBy: String? = nil
    /// Kept in step with its BOQ (`sourceBOQId`) both ways until the link
    /// is removed. nil/false: the BOQ is only where its items came from.
    var boqLinked: Bool? = nil
    /// How its items are listed: nil/"code", "description" or "manual"
    /// (a linked quotation follows its BOQ's).
    var lineSort: String? = nil
    /// How it's printed: nil = portrait on the letterhead (as Qt26193);
    /// "Landscape" = the BQ sheet, with its terms and signature block.
    var orientation: String? = nil
    /// Split off another quotation (`splitQuotation`): listed under it as
    /// its subsidiary. Not linked — each is changed on its own.
    var parentQuotationId: String? = nil
    /// The currency it's priced in (crane jobs can be quoted in another):
    /// an ISO code such as "USD"; nil = Settings' currency.
    var currency: String? = nil
    /// The client has agreed to it (said so by email, phone…), recorded
    /// by hand when no signed copy comes back. Counts as won.
    var clientAgreedAt: String? = nil
    /// Imported from a file (an old quotation, a scan): that file, kept
    /// with the project's documents.
    var importedFromDocumentId: String? = nil
    /// A crane job's buy-back offer (nil = Settings' standard offer): on or
    /// off, the % of the price after so many months, the % taken off for
    /// each month beyond, and the month after which none is offered.
    var buyBackEnabled: Bool? = nil
    var buyBackPercent: Double? = nil
    var buyBackAfterMonths: Int? = nil
    var buyBackReductionPercent: Double? = nil
    var buyBackEndMonths: Int? = nil
}

/// A crane quotation's buy-back offer, as printed: we buy the equipment
/// back at `percent` of its price after `afterMonths` months, less
/// `reductionPercent` (of the price) for each month beyond that, and make
/// no offer after `endMonths` months.
struct BuyBackTerms: Codable {
    var enabled: Bool
    var percent: Double
    var afterMonths: Int
    var reductionPercent: Double
    var endMonths: Int
    /// One unit's price (the dearest item, as charged), on a sale; nil
    /// leaves the amounts out.
    var unitPrice: Double? = nil
    /// The wording (Settings › Quotations › Crane jobs), with the figures
    /// as {PERCENT}, {UNIT_PRICE}, {MONTHS}, {LESS}, {NEXT_MONTHS},
    /// {NEXT_PERCENT}, {NEXT_UNIT_PRICE} (the first month beyond),
    /// {END_MONTHS}, {END_PERCENT} and {END_UNIT_PRICE}; a line a paragraph.
    var wording: String = BuyBackTerms.defaultWording

    static let defaultWording = """
    We offer to buy back the equipment at {PERCENT} of its price (i.e. {UNIT_PRICE} per unit) after {MONTHS} months.
    For each month beyond {MONTHS} months, the buy-back price is reduced by {LESS} of the price (i.e. {NEXT_UNIT_PRICE} at {NEXT_MONTHS} months and so on).
    No buy-back is offered after {END_MONTHS} months.
    """

    /// The % offered when it's returned after `months` months; nil = none.
    func share(atMonths months: Int) -> Double? {
        guard months <= endMonths else { return nil }
        return max(0, percent - reductionPercent * Double(max(0, months - afterMonths)))
    }

    /// The offer in words, a line a paragraph. Without a unit price, the
    /// brackets holding one are left out; without a monthly reduction, the
    /// lines about it are.
    func sentences(currency: String) -> [String] {
        let pc: (Double) -> String = { v in
            (v.rounded() == v ? String(Int(v)) : String(format: "%.1f", v)) + "%"
        }
        let price = unitPrice.flatMap { $0 > 0 ? $0 : nil }
        let money: (Double) -> String = { p in price.map { "\(currency) \(formatMoney($0 * p / 100))" } ?? "" }
        let end = max(endMonths, afterMonths)
        let last = share(atMonths: end) ?? 0
        let next = afterMonths + 1
        let nextShare = share(atMonths: next) ?? 0
        let reduces = reductionPercent > 0 && endMonths > afterMonths
        var lines: [String] = []
        for raw in wording.components(separatedBy: .newlines) {
            var line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }
            if !reduces && ["{LESS}", "{NEXT_", "{END_PERCENT}", "{END_UNIT_PRICE}"].contains(where: { line.contains($0) }) { continue }
            if price == nil {
                line = line.replacingOccurrences(of: #"\s*\([^()]*\{(END_|NEXT_)?UNIT_PRICE\}[^()]*\)"#, with: "", options: .regularExpression)
                for token in ["{UNIT_PRICE}", "{NEXT_UNIT_PRICE}", "{END_UNIT_PRICE}"] { line = line.replacingOccurrences(of: token, with: "") }
            }
            let values = ["{PERCENT}": pc(percent), "{UNIT_PRICE}": money(percent), "{MONTHS}": String(afterMonths), "{LESS}": pc(reductionPercent),
                          "{NEXT_MONTHS}": String(next), "{NEXT_PERCENT}": pc(nextShare), "{NEXT_UNIT_PRICE}": money(nextShare),
                          "{END_MONTHS}": String(end), "{END_PERCENT}": pc(last), "{END_UNIT_PRICE}": money(last)]
            for (token, value) in values { line = line.replacingOccurrences(of: token, with: value) }
            lines.append(line)
        }
        return lines
    }
}

/// An amount written out as on a cheque, in capitals: "SAY HONG KONG
/// DOLLARS ONE HUNDRED AND FIFTEEN THOUSAND NINE HUNDRED AND SIXTY AND
/// CENTS TWENTY-FOUR ONLY".
func amountInWords(_ amount: Double, currency: String) -> String {
    let ones = ["", "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX", "SEVEN", "EIGHT", "NINE", "TEN", "ELEVEN", "TWELVE",
                "THIRTEEN", "FOURTEEN", "FIFTEEN", "SIXTEEN", "SEVENTEEN", "EIGHTEEN", "NINETEEN"]
    let tens = ["", "", "TWENTY", "THIRTY", "FORTY", "FIFTY", "SIXTY", "SEVENTY", "EIGHTY", "NINETY"]
    func underHundred(_ n: Int) -> String {
        if n < 20 { return ones[n] }
        return tens[n / 10] + (n % 10 > 0 ? "-" + ones[n % 10] : "")
    }
    func underThousand(_ n: Int) -> String {
        let h = n / 100, r = n % 100
        var parts: [String] = []
        if h > 0 { parts.append(ones[h] + " HUNDRED") }
        if r > 0 { parts.append((h > 0 ? "AND " : "") + underHundred(r)) }
        return parts.joined(separator: " ")
    }
    func words(_ value: Int) -> String {
        if value == 0 { return "ZERO" }
        let scales: [(Int, String)] = [(1_000_000_000, "BILLION"), (1_000_000, "MILLION"), (1_000, "THOUSAND"), (1, "")]
        var n = value
        var parts: [String] = []
        for (size, name) in scales where n >= size {
            let chunk = n / size
            n %= size
            // "ONE THOUSAND AND FIVE": AND before a last part under a hundred.
            let text = size == 1 && !parts.isEmpty && chunk < 100 ? "AND " + underHundred(chunk) : underThousand(chunk)
            parts.append(name.isEmpty ? text : text + " " + name)
        }
        return parts.joined(separator: " ")
    }
    let cents = Int((abs(amount) * 100).rounded())
    let whole = cents / 100, part = cents % 100
    let names = ["HKD": "HONG KONG DOLLARS", "USD": "US DOLLARS", "CNY": "RENMINBI", "RMB": "RENMINBI", "MOP": "MACAU PATACAS",
                 "EUR": "EUROS", "GBP": "POUNDS STERLING", "SGD": "SINGAPORE DOLLARS", "JPY": "JAPANESE YEN", "AUD": "AUSTRALIAN DOLLARS"]
    let name = names[currency.uppercased()] ?? currency.uppercased()
    var text = "SAY \(name) \(words(whole))"
    if part > 0 { text += " AND CENTS \(underHundred(part))" }
    return text + " ONLY"
}

// ---- Bold, italic and underline in descriptions ----
// Typed as **bold**, *italic* and __underline__ (the custom item box's
// B / I / U). For laying out and drawing they become private marks that
// switch the style on and off: \u{E010} bold, \u{E011} italic, \u{E012}
// underline. Styles stay within a line.

let inlineBoldMark: Character = "\u{E010}"
let inlineItalicMark: Character = "\u{E011}"
let inlineUnderlineMark: Character = "\u{E012}"

func hasInlineMarks(_ s: String) -> Bool {
    s.unicodeScalars.contains { $0.value >= 0xE010 && $0.value <= 0xE012 }
}

/// The typed markers as style marks.
func applyInlineMarkup(_ s: String) -> String {
    guard s.contains("*") || s.contains("__") else { return s }
    var out = s
    out = out.replacingOccurrences(of: #"\*\*(?=\S)(.+?)(?<=\S)\*\*"#, with: "\u{E010}$1\u{E010}", options: .regularExpression)
    out = out.replacingOccurrences(of: #"__(?=\S)(.+?)(?<=\S)__"#, with: "\u{E012}$1\u{E012}", options: .regularExpression)
    out = out.replacingOccurrences(of: #"(?m)(^|[^*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![*\w])"#, with: "$1\u{E011}$2\u{E011}", options: .regularExpression)
    return out
}

/// The text without any styling (where it can't be shown, e.g. the BQ sheet).
func plainMarkup(_ s: String) -> String {
    String(applyInlineMarkup(s).unicodeScalars.filter { !($0.value >= 0xE010 && $0.value <= 0xE012) })
}

/// Text with style marks as runs of plain text and their styles.
func inlineRuns(_ s: String) -> [(text: String, bold: Bool, italic: Bool, underline: Bool)] {
    var runs: [(text: String, bold: Bool, italic: Bool, underline: Bool)] = []
    var bold = false, italic = false, underline = false
    var current = ""
    for ch in s {
        if ch == inlineBoldMark || ch == inlineItalicMark || ch == inlineUnderlineMark {
            if !current.isEmpty { runs.append((current, bold, italic, underline)); current = "" }
            if ch == inlineBoldMark { bold.toggle() } else if ch == inlineItalicMark { italic.toggle() } else { underline.toggle() }
        } else {
            current.append(ch)
        }
    }
    if !current.isEmpty { runs.append((current, bold, italic, underline)) }
    return runs
}

/// A name a file can have on a Mac, Windows and in the cloud: a slash
/// (as in "GL/09") becomes "∕", which looks the same; \ : * ? " < > |
/// become "-"; at most 200 characters.
func safeFileName(_ name: String) -> String {
    var out = name.replacingOccurrences(of: "/", with: "∕")
    for c in ["\\", ":", "*", "?", "\"", "<", ">", "|"] { out = out.replacingOccurrences(of: c, with: "-") }
    out = out.components(separatedBy: .controlCharacters).joined().trimmingCharacters(in: .whitespacesAndNewlines)
    while out.hasSuffix(".") { out.removeLast() }
    return String(out.prefix(200))
}

/// How a currency is written on documents: HK$, US$, RMB, or its code.
func currencyDisplay(_ code: String) -> String {
    switch code.uppercased() {
    case "HKD": return "HK$"
    case "USD": return "US$"
    case "CNY", "RMB": return "RMB"
    case "MOP": return "MOP$"
    case "SGD": return "S$"
    case "EUR": return "EUR"
    case "GBP": return "GBP"
    default: return code.uppercased()
    }
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
    /// The sum typed for the quantity (e.g. "14+28"), shown again when the
    /// box is clicked; nil when a plain number was typed.
    var quantityFormula: String? = nil
    /// The sum typed for the unit price (e.g. "12.5*2"), as for the quantity.
    var priceFormula: String? = nil
    /// Per-line discount: nil/"None", "Percent" (0-100) or "Amount"
    /// (taken off the line total).
    var discountType: String? = nil
    var discountValue: Double? = nil
    /// Set for a row of one of the quotation's extra sections
    /// (`QuotationBlock`) rather than a material or delivery charge.
    var blockId: String? = nil
    /// The line of the BOQ it came from (and, while the two are linked,
    /// is kept the same as).
    var boqLineId: String? = nil
    /// Taken out of the link on its own ("Unlink from BOQ"): it keeps its
    /// own quantity and price, and the BOQ's line keeps its, until relinked.
    var boqDetached: Bool? = nil
    /// A priced section's row that isn't charged: the words typed in its
    /// unit price ("(Included)", "(Free of Charge)"…; older rows "FOC" or
    /// "Included"). Its price is 0 and the words print instead of figures.
    var priceNote: String? = nil
}

/// How a priced row that isn't charged is printed: the words typed.
func priceNoteLabel(_ note: String?) -> String? {
    switch note {
    case "FOC": return "Free of Charge"
    case "Included": return "Included in Unit Price"
    default: return nonBlank(note)
    }
}

/// A letter on the letterhead, written in the letter editor. The app prints
/// its opening (recipient, references, date and "Re:" line) from the fields;
/// the rest is the body as typed, with its formatting (`bodyHTML`).
struct Letter: Codable {
    var id: String
    /// Built from Settings' letter number format (default L{PROJECT}-{SEQ},
    /// e.g. L26001-001 for project 26001).
    var letterNumber: String
    var projectId: String?
    var clientId: String?
    /// "Draft", "Issued" or "Cancelled".
    var status: String
    /// ISO timestamp (the day shown on the letter).
    var letterDate: String
    var recipientName: String?
    /// One line per line of the address.
    var recipientAddress: String?
    var attention: String?
    var yourRef: String?
    var subject: String?
    var bodyHTML: String
    var pdfPath: String?
    var createdAt: String
    var updatedAt: String
    /// Annexures sent with it, in order: each gets a cover page (the
    /// letterhead, the recipient, "ANNEXURE P.01") followed by its files,
    /// after the letter's own pages, and a line in the letter's
    /// "Attachments:" list.
    var attachments: [LetterAttachment]? = nil
    /// How annexures are numbered: this then 01, 02… (default "ANNEXURE P.").
    var annexurePrefix: String? = nil
}

struct LetterAttachment: Codable {
    var id: String
    /// "a detailed list of items for 1 unit of Kroll K1400"
    var description: String
    /// PDFs and pictures, in order (copies kept with the letter).
    var files: [String]
}

/// "ANNEXURE P.01", "ANNEXURE P.02"… for a letter's attachments.
func annexureLabel(_ letter: Letter, _ index: Int) -> String {
    // As typed, a space at its end kept ("ANNEX " → "ANNEX 01").
    let prefix = letter.annexurePrefix.flatMap { nonBlank($0) == nil ? nil : $0 } ?? "ANNEXURE P."
    return prefix + String(format: "%02d", index + 1)
}

struct LetterSummary: Codable {
    var id: String
    var letterNumber: String
    var status: String
    var letterDate: String
    var subject: String?
    var recipientName: String?
    var projectId: String?
    var projectNumber: String?
    var projectName: String?
    var updatedAt: String
    /// Who made it, and who last worked on it (their names).
    var createdBy: String? = nil
    var lastEditedBy: String? = nil
}

struct LetterDetail: Codable {
    var letter: Letter
    var projectNumber: String?
    var projectName: String?
    /// The PDF's opening as it will print (for the editor's page).
    var openingHTML: String
}

/// Who made each project and document, and who last worked on it — kept
/// in the records themselves (added as they're saved; see JSONStore), so
/// every Mac sharing the data sees the same names.
enum Authorship {
    static let stores: Set<String> = ["projects.json", "boqs.json", "quotations.json", "invoices.json", "delivery_notes.json", "letters.json"]
    static let keys = ["createdBy", "createdByDevice", "lastEditedBy", "lastEditedByDevice", "lastEditedAt"]

    /// The records being saved, with the names carried over from the file
    /// (the app's own record types don't keep them) and this Mac's user as
    /// the last to work on each record that changed (and the maker of any
    /// new one).
    static func stamp(_ new: Data, previous: Data?) -> Data {
        guard let list = (try? JSONSerialization.jsonObject(with: new)) as? [[String: Any]] else { return new }
        var before: [String: [String: Any]] = [:]
        if let old = previous.flatMap({ (try? JSONSerialization.jsonObject(with: $0)) as? [[String: Any]] }) {
            for r in old { if let id = r["id"] as? String { before[id] = r } }
        }
        func canonical(_ r: [String: Any]) -> Data? {
            var c = r
            for k in keys { c.removeValue(forKey: k) }
            return try? JSONSerialization.data(withJSONObject: c, options: [.sortedKeys])
        }
        let me = TeamSync.memberName, device = TeamSync.deviceId, now = nowISO()
        let out: [[String: Any]] = list.map { record in
            var r = record
            guard let id = r["id"] as? String else { return r }
            if let old = before[id] {
                for k in keys where r[k] == nil { if let v = old[k] { r[k] = v } }
                guard canonical(record) != canonical(old) else { return r }
            } else {
                r["createdBy"] = me
                r["createdByDevice"] = device
            }
            r["lastEditedBy"] = me
            r["lastEditedByDevice"] = device
            r["lastEditedAt"] = now
            return r
        }
        return (try? JSONSerialization.data(withJSONObject: out, options: [.withoutEscapingSlashes])) ?? new
    }
}

/// Who made a document and who last worked on it; `mine` when that was
/// this Mac's user (or it isn't known).
struct DocAuthors: Codable {
    var createdBy: String?
    var lastEditedBy: String?
    var lastEditedAt: String?
    var mine: Bool
}

/// A letter's opening for the PDF (drawn as on the quotations).
struct LetterOpening {
    var recipientName: String?
    var addressLines: [String]
    var attention: String?
    var refRows: [(label: String, value: String)]
    var subject: String?
}

struct LetterActionResult: Codable {
    var ok: Bool
    var error: String?
    var id: String?
}

/// One day of a quotation's delivery schedule: how many of each of the
/// quotation's materials go to site that day (by quotation line id). Just a
/// plan / record for now — not connected to the stock list.
struct QuotationDeliveryDay: Codable {
    var id: String
    /// The quotation's id — or the BOQ's, for a BOQ's delivery schedule
    /// (keyed by BOQ line id then). Ids never clash between the two.
    var quotationId: String
    /// Day 1, Day 2… (renumbered when a day is removed).
    var day: Int
    /// yyyy-MM-dd, if a date is set.
    var date: String?
    /// HH:mm, if a time is set.
    var time: String? = nil
    /// Delivered (true) or still planned.
    var sent: Bool?
    /// The note printed for the client (the schedule's "Notes").
    var note: String?
    /// A note for the team only: on an Internal export, never on the
    /// copy printed with the quotation or BOQ.
    var internalNote: String? = nil
    var quantities: [String: Double]
    var createdAt: String
    var updatedAt: String
}

struct CopyScheduleResult: Codable {
    var ok: Bool
    var error: String?
    /// Items on the BOQ's schedule with no line on the quotation.
    var skipped: Int
}

struct DeliveryScheduleData: Codable {
    var days: [QuotationDeliveryDay]
    /// Each material line's unit weight (kg) from the material list, by line id.
    var weights: [String: Double]
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
    var boqId: String? = nil
    var boqNumber: String? = nil
    /// Kept in step with that BOQ.
    var boqLinked = false
    var structure: String? = nil
    /// Its "Re:" subject line.
    var subject: String? = nil
    var pricingMode: String? = nil
    var charges: ChargeSplit? = nil
    /// Made from a combined BOQ: listed apart, not added to the project total.
    var fromCombined = false
    /// Who made it, and who last worked on it (their names).
    var createdBy: String? = nil
    var lastEditedBy: String? = nil
    /// Split off this quotation (listed under it as its subsidiary).
    var parentId: String? = nil
    var parentNumber: String? = nil
}

/// A quotation named on another: its parent, or one split off it.
struct QuotationRef: Codable {
    var id: String
    var number: String
    var status: String
}

struct QuotationSplitResult: Codable {
    var ok: Bool
    var error: String?
    /// The new quotation.
    var id: String? = nil
    var number: String? = nil
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
    /// Delivery charges by weight (Settings), lightest band first.
    var deliveryRates: [DeliveryRate] = defaultDeliveryRates
    /// The materials' weight (kg), from the material list; nil when none
    /// of them has a weight. `linesWithoutWeight` counts those that don't.
    var materialsWeightKg: Double? = nil
    var linesWithoutWeight: Int = 0
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
    /// Its own currency (nil = Settings'), and when the client agreed by hand.
    var currency: String? = nil
    var clientAgreedAt: String? = nil
    /// Imported from a file: that file, kept with the project's documents.
    var importedDocumentId: String? = nil
    var importedFileName: String? = nil
    /// A crane job's buy-back offer (nil for other jobs).
    var buyBack: BuyBackTerms? = nil
    /// Signed and chopped by a director, and a request still waiting.
    var directorSignedBy: String? = nil
    var directorSignedAt: String? = nil
    var directorSignedExists = false
    var directorSignedPath: String? = nil
    var signPendingWith: String? = nil
    var signRequestId: String? = nil
    /// The client's default markup (a hint in the editor).
    var clientMarkupPercent: Double? = nil
    /// Item names on the PDF: the quotation's own choice (nil = Settings'), and Settings'.
    var language: String? = nil
    var defaultLanguage = "English"
    /// "Portrait" (the letterhead) or "Landscape" (the BQ sheet).
    var orientation = "Portrait"
    /// The project's kind of job: a crane job's quotation is always the
    /// letter (portrait) with items written out, not the BQ sheet.
    var jobType = "Scaffolding"
    /// Kept in step with the BOQ above, both ways; and that BOQ's status
    /// (an issued one isn't changed).
    var boqLinked = false
    var sourceBOQStatus: String? = nil
    var lineSort = "code"
    /// The quotation it was split off, and the ones split off it.
    var parent: QuotationRef? = nil
    var subsidiaries: [QuotationRef] = []
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
    /// The delivery notes it bills (what was delivered, at the quotation's
    /// prices). nil = billed from the quotation itself.
    var sourceDeliveryNoteIds: [String]? = nil
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
    /// The sum typed for the quantity (e.g. "14+28"), shown again when the
    /// box is clicked; nil when a plain number was typed.
    var quantityFormula: String? = nil
    /// The sum typed for the unit price (e.g. "12.5*2"), as for the quantity.
    var priceFormula: String? = nil
    /// A one-off charge copied from one of the quotation's priced
    /// sections: its title (e.g. "Design Fees") and row prefix ("A").
    var chargeGroup: String? = nil
    var chargePrefix: String? = nil
    /// Materials delivered for another of the project's quotations, on the
    /// same invoice: that quotation (its number and subject), printed as a
    /// section of its own. nil = the invoice's own quotation.
    var materialGroup: String? = nil
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
    /// Who made it, and who last worked on it (their names).
    var createdBy: String? = nil
    var lastEditedBy: String? = nil
    /// What it bills: the quotation, and the delivery notes (if from them).
    var quotationNumber: String? = nil
    var deliveryNoteNumbers: [String] = []
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
    /// True while a draft's payment terms follow Settings › Invoices
    /// (it hasn't been given terms of its own); the Settings text.
    var paymentTermsFromSettings: Bool? = nil
    var defaultPaymentTerms: String? = nil
    /// Its quotation's own currency (a crane job in US$); nil = Settings'.
    var currency: String? = nil
    /// The delivery notes it bills, and whether each has a signed copy
    /// (attached after the invoice's own pages).
    var deliveryNotes: [InvoiceNoteRef] = []
}

struct InvoiceNoteRef: Codable {
    var id: String
    var number: String
    var status: String
    var signedCopyName: String?
    var signedCopyExists: Bool
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
    /// Item names on the PDF: "English" or "Chinese"; nil = Settings' choice.
    var language: String? = nil
    /// The copy signed on site ("<DN no.> - Signed.pdf" in the project's
    /// Delivery Notes folder). It's added after the invoice that bills it.
    var signedCopyPath: String? = nil
    var signedCopyAt: String? = nil
    /// When to ask whether its items are back from site (Stock › Returns),
    /// set by "Not yet" or a part return. nil = the project's finish date,
    /// else 30 days after the signed copy came in.
    var returnCheckDate: String? = nil
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
    /// The sum typed for the quantity (e.g. "14+28"), shown again when the
    /// box is clicked; nil when a plain number was typed.
    var quantityFormula: String? = nil
}

struct DeliveryNoteSummary: Codable {
    var id: String
    var deliveryNoteNumber: String
    var status: String
    var itemCount: Int
    var deliveryDate: String
    var createdAt: String
    /// Who made it, and who last worked on it (their names).
    var createdBy: String? = nil
    var lastEditedBy: String? = nil
    /// The quotation it delivers (its prices), and the invoices billing it.
    var sourceQuotationId: String? = nil
    var quotationNumber: String? = nil
    var invoiceNumbers: [String] = []
    /// The copy signed on site is in the project folder.
    var signed = false
    var totalQuantity: Double = 0
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
    /// Item names on the PDF: the note's own choice (nil = Settings'), and Settings'.
    var language: String? = nil
    var defaultLanguage = "English"
    /// The signed copy: its file name, when it was added, whether it's
    /// still in the folder, and the invoices it's attached to.
    var signedCopyName: String? = nil
    var signedCopyAt: String? = nil
    var signedCopyExists = false
    var invoiceNumbers: [String] = []
    /// Its items are booked out of the stock (issued and signed), how many
    /// are still on site, and when we'll ask whether they're back.
    var stockBooked = false
    var isSale = false
    var stockOutstanding: Double? = nil
    var returnCheckDate: String? = nil
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
    var numberFormatLetter: String? = nil
    /// Default days until an invoice is due.
    var defaultInvoiceDueDays: Int?
    // ---- Standard quotation (from Qt26193) ----
    var signatoryName: String?
    var signatoryTitle: String?
    /// e.g. "www.pfitnet.com/TC"
    var termsURL: String?
    /// The numbered terms: payment, delivery, modification… (for rental
    /// quotations, and for sale ones when they have none of their own).
    var quotationTerms: String?
    /// The standard key terms of a sale quotation; nil = the ones above.
    var quotationTermsSale: String? = nil
    /// "Order shall be confirmed … valid for 7 business days …"
    var quotationAcceptance: String?
    /// Per truck per trip; what "+ Delivery Charge" used before the
    /// charges went by weight (see `deliveryRates`).
    var standardDeliveryCharge: Double?
    /// Rental quotations: "Minimum Hire of N Months".
    var defaultMinimumHireMonths: Int?
    /// Crane quotations' standard buy-back offer: the % of the price after
    /// so many months, less a % a month beyond, none after so many months.
    var buyBackPercent: Double? = nil
    var buyBackAfterMonths: Int? = nil
    var buyBackReductionPercent: Double? = nil
    var buyBackEndMonths: Int? = nil
    /// The buy-back offer's wording, with its figures as {PERCENT}, {UNIT_PRICE}…;
    /// nil = the standard wording (`BuyBackTerms.defaultWording`).
    var buyBackWording: String? = nil
    /// The AI that reads imported quotations (Settings › AI Import), the
    /// same for the whole team: "gemini" or "openrouter", its model (nil =
    /// the provider's default) and key. The key never goes to the pages.
    var aiProvider: String? = nil
    var aiModel: String? = nil
    var aiKey: String? = nil
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
    /// The manpower rate providers (Costs › Manpower). nil = the defaults.
    var manpowerProviders: [String]? = nil
    /// Marked-up unit prices (quotation and BOQ markup %) are rounded up to
    /// the next 0.1 (true) or off to the nearest 0.1 (nil / false).
    var markupRoundUp: Bool? = nil
    /// Materials every new BOQ starts with (Settings → BOQ Defaults).
    var defaultBOQItems: [DefaultBOQItem]? = nil
    /// The minimum monthly rental charge a quotation can apply (nil = 1,000).
    var minimumMonthlyRental: Double? = nil
    /// The language item names are printed in on delivery notes and BOQs
    /// unless a document says otherwise: "English" (nil) or "Chinese".
    var documentLanguage: String? = nil
    /// Standard terms for the landscape BOQ's Terms box (Settings → BOQ Defaults).
    var boqTerms: String? = nil
    /// Documents made from another share its number: the invoice and
    /// delivery notes for Qt26001-004 are H26001-004 and DN26001-004, the
    /// quotation from BQ26001-004 is Qt26001-004 (nil = on; false = off).
    var linkedNumbers: Bool? = nil
    /// A GIPHY API key, for searching GIFs in Chat (nil = no GIF search).
    var giphyKey: String? = nil
    /// Delivery charges by weight, lightest band first (nil = `defaultDeliveryRates`).
    var deliveryRates: [DeliveryRate]? = nil
}

/// A price-list item and quantity put into every new BOQ.
struct DefaultBOQItem: Codable {
    var priceListItemId: String
    var quantity: Double
}

/// A worker type and its day rate, e.g. "Scaffolder CP", 2,300 per "md".
struct ManpowerRate: Codable {
    var name: String
    /// What we charge (filled into quotations).
    var rate: Double
    var unit: String
    /// What each rate provider charges us for it, by provider name.
    var costs: [String: Double]? = nil
}

/// Who supplies our workers (Costs › Manpower), unless changed there.
let defaultManpowerProviders = ["Summit Engineering & Resources Limited", "Lingma Const. & Eng. Co. Ltd."]

struct ManpowerPage: Codable {
    var rates: [ManpowerRate]
    var providers: [String]
}

/// A delivery charge band: per truck per trip for a load up to `upToKg`.
struct DeliveryRate: Codable {
    var upToKg: Double
    var price: Double
}

/// The company's delivery charges by the weight on the truck (per truck
/// per trip): under 500 kg $1,200; 500 kg – 1 ton $1,800; 1 – 2 tons
/// $2,200; 2 – 6 tons $3,300; 6 – 8 tons $3,800. Heavier loads go on
/// more than one truck.
let defaultDeliveryRates = [
    DeliveryRate(upToKg: 500, price: 1200),
    DeliveryRate(upToKg: 1000, price: 1800),
    DeliveryRate(upToKg: 2000, price: 2200),
    DeliveryRate(upToKg: 6000, price: 3300),
    DeliveryRate(upToKg: 8000, price: 3800),
]

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

/// What the landscape BOQ's standard terms used to be. A BOQ (or Settings)
/// still holding exactly these gets the quotations' terms instead — the BOQ
/// and the quotation now share one set of standard terms.
let legacyBOQTerms = """
1. Quantities are estimated from the drawings provided; the quantities actually delivered are charged.
2. Rental is charged monthly from the date of delivery until the materials are returned.
3. Lost or damaged materials are charged at the sale price.
4. Delivery and collection are charged separately unless stated.
"""

let defaultQuotationAcceptance = "Order shall be confirmed and regarded as properly accepted upon signature by all parties AND such signed copy is returned to Proficiency (HK) Limited via instant electronic communication means. This quotation shall be valid for 7 business days against the issue date."


/// Built-in number formats — exactly what the app has always produced.
let defaultNumberFormats: [String: String] = [
    "BOQ": "{PROJECT}-BOQ-{SEQ}",
    // The company's own convention: Qt26193 (quotations), H26XXX (invoices).
    "QT": "Qt{YY}{SEQ}",
    "INV": "H{YY}{SEQ}",
    "DN": "{PROJECT}-DN-{SEQ}",
    // Letters follow their project: L26001-001, L26001-002… for project 26001.
    "LT": "L{PROJECT}-{SEQ}",
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

/// The {SEQ} part of a number made from `template` — "004" from
/// Qt26001-004 with "Qt{PROJECT}-{SEQ}", "004-2" from Qt26001-004-2,
/// "004-s1" from the subsidiary Qt26001-004-s1 —
/// or nil when the number doesn't follow the template.
func sequencePart(of number: String, template rawTemplate: String, projectNumber: String) -> String? {
    var template = rawTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
    if !template.contains("{SEQ}") { template += "-{SEQ}" }
    let tokens: [(token: String, pattern: String)] = [
        ("{PROJECT}", NSRegularExpression.escapedPattern(for: projectNumber)), ("{YYYY}", "\\d{4}"), ("{YY}", "\\d{2}"), ("{SEQ}", "(\\d+(?:-s?\\d+)*)"),
    ]
    var pattern = "^"
    var rest = Substring(template)
    while let first = rest.first {
        if let t = tokens.first(where: { rest.hasPrefix($0.token) as Bool }) {
            pattern += t.pattern
            rest = rest.dropFirst(t.token.count)
        } else {
            pattern += NSRegularExpression.escapedPattern(for: String(first))
            rest = rest.dropFirst()
        }
    }
    pattern += "$"
    guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
          let m = re.firstMatch(in: number, range: NSRange(number.startIndex..., in: number)),
          m.numberOfRanges > 1, let r = Range(m.range(at: 1), in: number) else { return nil }
    return String(number[r])
}

/// A number with a given sequence: `template` with {SEQ} = `sequence`, and
/// "-2", "-3"… after it when that number is already used.
func linkedDocumentNumber(template rawTemplate: String, projectNumber: String, existing: [String], sequence: String, date: Date = Date()) -> String {
    var template = rawTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
    if !template.contains("{SEQ}") { template += "-{SEQ}" }
    let year = Calendar.current.component(.year, from: date)
    let base = template
        .replacingOccurrences(of: "{PROJECT}", with: projectNumber)
        .replacingOccurrences(of: "{YYYY}", with: String(year))
        .replacingOccurrences(of: "{YY}", with: String(format: "%02d", year % 100))
        .replacingOccurrences(of: "{SEQ}", with: sequence)
    let used = Set(existing.map { $0.lowercased() })
    if !used.contains(base.lowercased()) { return base }
    var n = 2
    while used.contains("\(base)-\(n)".lowercased()) { n += 1 }
    return "\(base)-\(n)"
}

// ---- PDF documents (layout of the company's quotation Qt26193) ----

enum PDFMode {
    case export
    case print
    /// A Word (.docx) copy laid out like the PDF (built by js/docx-export.js).
    case word
    /// The finished PDF shown in the app (js/doc-preview.js) before it's
    /// saved: kept aside until "files:savePreview".
    case preview
}

/// A PDF made for the preview, waiting to be saved into the project folder.
struct PendingPreview {
    var url: URL
    var projectNumber: String
    var subfolder: String
    var documentNumber: String
    var docTypeTag: String
    var fileName: String
    /// Saved here (a new name if one's taken) instead of the project folder.
    var folder: URL? = nil
}

struct PreviewPage: Codable {
    /// JPEG, base64.
    var image: String
    /// In points (as it prints).
    var width: Double
    var height: Double
}

struct PreviewResult: Codable {
    var ok: Bool
    var error: String?
    var token: String?
    var fileName: String?
    var pages: [PreviewPage] = []
    /// All its pages (only the first ones are drawn when there are very many).
    var pageCount: Int = 0
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
struct WordSignature: Encodable { var heading: String; var subheading: String? = nil; var lines: [WordSignatureLine] }
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
    /// Where the references' colons go (478.5pt unless a long number moved them).
    var refColon: Double
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
    /// A letter's body as its editor HTML; the page turns it into paragraphs.
    var bodyHTML: String? = nil
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
    /// A row number in the first column, then text across all the others,
    /// left-aligned and wrapped, e.g. a buy-back offer's BO1.
    case wide(number: String, text: String)
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

let numberMarkerPattern = #"^(\(?[0-9]{1,3}[.)]|\([0-9]{1,3}\)|\(?[a-zA-Z][.)]|\([a-zA-Z]\)|\(?[ivxIVX]{1,5}[.)]|\([ivxIVX]{1,5}\))\s+"#

/// "Deposit: 50%…" → ("Deposit", "50%…"). A label is short (up to five
/// words) and the colon is followed by a space or nothing, so "10:30" and
/// web addresses aren't labels.
func labelSplit(_ line: String) -> (marker: String, text: String, style: HangingStyle)? {
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
            // "Model<Tab>: ZT14JC": Tab used to line the colons up.
            if rest.hasPrefix(":") {
                return (marker, String(rest.dropFirst()).trimmingCharacters(in: .whitespaces), .label)
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

/// `labelHeads` (a line item's description): a label with nothing after
/// its colon ("Standard Warranty :") is a line on its own, and the lines
/// under it start at the edge and use the full width instead of hanging
/// under the label's text column.
func formattedParagraphs(_ text: String, left: CGFloat = 0, labelHeads: Bool = false) -> [LetterParagraph] {
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
            if labelHeads && item.style == .label && item.text.isEmpty && !indented {
                plain.append(trimmed)
                parentText = nil
                continue
            }
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

/// One line of a description laid out in a table cell: `text` at
/// `textX` points from the cell's text edge, and on an item's first line
/// its `marker` ("•", "1.", "Transport") at `markerX`, with a colon just
/// before the text when `colon`.
struct CellTextLine {
    var marker: String?
    var markerX: Double
    var text: String
    var textX: Double
    var colon: Bool
}

/// Whether a line item's description is laid out like the terms (bullets,
/// numbering, "Label : text" hanging indents): it runs over more than one
/// line (or has a Tab) and at least one line is such an item. One-line
/// descriptions print as typed.
func isFormattedDescription(_ text: String) -> Bool {
    guard text.contains("\n") || text.contains("\t") else { return false }
    return text.components(separatedBy: "\n").contains { hangingItem($0) != nil }
}

/// A formatted description (isFormattedDescription) in a cell `width`
/// points wide, by the terms' rules (formattedParagraphs): plain lines at
/// the edge; an item's marker at its place and its text, and every line
/// under it, set in to one column (never so far that less than 60% of the
/// cell is left for the text).
func formattedCellLines(_ text: String, width: Double, measure: (String) -> Double, wrap: (String, Double) -> [String]) -> [CellTextLine] {
    // Labels ("Model", "Manufacturer"…) at the same place share one colon
    // column, just past the longest of them, as in a typed spec list.
    var labelText: [Double: Double] = [:]
    for paragraph in formattedParagraphs(text, labelHeads: true) {
        if case .hanging(let marker, _, let l, _, true) = paragraph, !marker.isEmpty {
            let left = min(Double(l), width * 0.4)
            labelText[left] = max(labelText[left] ?? 0, left + measure(marker) + 7.5)
        }
    }
    var lines: [CellTextLine] = []
    // A blank line in the text leaves a blank line in the cell.
    let blocks = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
        .split(omittingEmptySubsequences: false) { $0.trimmingCharacters(in: .whitespaces).isEmpty }
        .map { $0.joined(separator: "\n") }.filter { !$0.isEmpty }
    for (b, block) in blocks.enumerated() {
        if b > 0 { lines.append(CellTextLine(marker: nil, markerX: 0, text: "", textX: 0, colon: false)) }
        for paragraph in formattedParagraphs(block, labelHeads: true) {
            switch paragraph {
            case .text(let string, _):
                for line in string.components(separatedBy: "\n").flatMap({ wrap($0, width) }) {
                    lines.append(CellTextLine(marker: nil, markerX: 0, text: line, textX: 0, colon: false))
                }
            case .hanging(let marker, let texts, let l, let indent, let colon):
                let left = min(Double(l), width * 0.4)
                let markerWidth = marker.isEmpty ? 0 : measure(marker)
                var textX: Double
                if colon, !marker.isEmpty {
                    textX = labelText[left] ?? (left + markerWidth + 7.5)
                } else if marker.isEmpty {
                    textX = indent.map { min(Double($0), width * 0.4) } ?? left
                } else {
                    textX = left + max(12, markerWidth + 5)
                }
                textX = min(textX, width * 0.55)
                let pieces = texts.flatMap { wrap($0, width - textX) }
                for (i, piece) in (pieces.isEmpty ? [""] : pieces).enumerated() {
                    lines.append(CellTextLine(marker: i == 0 && !marker.isEmpty ? marker : nil, markerX: left, text: piece, textX: textX, colon: i == 0 && colon))
                }
            case .term(let label, let texts):
                for (i, piece) in texts.flatMap({ wrap($0, width * 0.6) }).enumerated() {
                    lines.append(CellTextLine(marker: i == 0 ? label : nil, markerX: 0, text: piece, textX: width * 0.4, colon: i == 0 && label != nil))
                }
            }
        }
    }
    return lines
}

/// A laid-out line in a portrait table cell, carried as text: a private
/// prefix gives the marker's and the text's places (drawCell reads it).
func encodeCellLine(_ l: CellTextLine) -> String {
    "\u{E000}\(l.markerX)\u{E001}\(l.textX)\u{E001}\(l.colon ? 1 : 0)\u{E001}\(l.marker ?? "")\u{E002}\(l.text)"
}

func decodeCellLine(_ s: String) -> CellTextLine? {
    guard s.hasPrefix("\u{E000}"), let split = s.firstIndex(of: "\u{E002}") else { return nil }
    let head = s[s.index(after: s.startIndex)..<split].components(separatedBy: "\u{E001}")
    guard head.count == 4 else { return nil }
    return CellTextLine(marker: head[3].isEmpty ? nil : head[3], markerX: Double(head[0]) ?? 0,
                        text: String(s[s.index(after: split)...]), textX: Double(head[1]) ?? 0, colon: head[2] == "1")
}

/// The same line as plain text for Word: set in with spaces, the marker
/// before the text.
func plainCellLine(_ s: String) -> String {
    guard let l = decodeCellLine(s) else { return s }
    let pad = { (x: Double) in String(repeating: " ", count: max(0, Int((x / 2.8).rounded()))) }
    if let marker = l.marker { return pad(l.markerX) + marker + (l.colon ? " : " : "  ") + l.text }
    return pad(l.textX) + l.text
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
    /// "For and on Behalf of" / "Accepted By"
    var heading: String
    /// Printed right under the heading, e.g. the company's or client's name.
    var subheading: String? = nil
    /// Under the signing rule: party name, then name / position / date lines.
    var lines: [LetterSignatureLine]
    /// A director's signature (above the rule) and the company chop over it.
    var signatureImage: CGImage? = nil
    var chopImage: CGImage? = nil
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
    /// Item rows this tall instead (a delivery note squeezed onto one page).
    var tableRowHeight: Double? = nil
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

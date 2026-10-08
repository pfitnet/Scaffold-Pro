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

let isoFormatter: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

func nowISO() -> String {
    isoFormatter.string(from: Date())
}

let plainISOFormatter = ISO8601DateFormatter()

/// A time as saved by nowISO() (with fractions of a second) or without them.
func parseISODate(_ text: String) -> Date? {
    isoFormatter.date(from: text) ?? plainISOFormatter.date(from: text)
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
    // "24 Sep 2026", whatever the Mac's region is set to.
    let displayFormatter = DateFormatter()
    displayFormatter.locale = Locale(identifier: "en_US_POSIX") // "Sep", not en_GB's "Sept"
    displayFormatter.dateFormat = "d MMM yyyy"
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
    let fileURL: URL

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

    func preserveUnreadableFile(_ error: Error) {
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
        StoreFile.write(data, to: fileURL)
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

/// Saving a store's file: what every JSONStore save goes through, and
/// Undo / Redo too (UndoJournal), which put back records as they were.
enum StoreFile {
    static func write(_ newData: Data, to fileURL: URL) {
        var data = newData
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Sharing a folder with other Macs: what changed goes into this
        // Mac's log there too (TeamSync).
        // The material list also goes to iCloud Drive when this Mac isn't
        // sharing a folder (TeamSync.material).
        let folder = fileURL.deletingLastPathComponent().standardizedFileURL
        let team = [TeamSync.current, TeamSync.material].compactMap { $0 }.first {
            $0.localData.standardizedFileURL == folder && $0.handles(fileURL.lastPathComponent)
        }
        let stamped = Authorship.stores.contains(fileURL.lastPathComponent)
        let journal = UndoJournal.shared.wants(fileURL)
        let previous: Data? = team == nil && !stamped && !journal ? nil : (try? Data(contentsOf: fileURL))
        // Projects and documents: who made each one, and who last worked on it.
        if stamped { data = Authorship.stamp(data, previous: previous) }
        // Atomic: written to a temporary file and swapped in, so a crash
        // or power cut mid-save can never leave a half-written database
        // file behind (section 48).
        try? data.write(to: fileURL, options: .atomic)
        team?.recordLocalWrite(store: fileURL.lastPathComponent, old: previous, new: data)
        // What this action changed, so it can be undone.
        if journal { UndoJournal.shared.record(fileURL, old: previous, new: data) }
        // Lets the automatic iCloud backup know there's something new.
        NotificationCenter.default.post(name: CloudBackupManager.dataSaved, object: nil)
    }
}

// =====================================================================
// MARK: - Undo / Redo (⌘Z or Ctrl+Z; ⇧⌘Z, ⌘Y or Ctrl+Y)
//
// Each action the pages ask for (adding a line, changing a quantity,
// deleting a BOQ…) is one step. While it runs, every record it changes is
// noted as it was before and after. Undo puts those records back as they
// were before (re-adding any it deleted, taking off any it added); Redo
// puts them back as they were after. Only those records change, so a
// teammate's work on other records (TeamSync) is left alone. The steps
// last while the app is open (the latest 60). Not undone: the project
// history, chat, announcements, signing requests and team membership —
// and files on disk (an uploaded drawing's copy stays in the folder).
// =====================================================================

struct UndoResult: Encodable {
    var ok: Bool
    var error: String?
    var label: String?
    var canUndo: Bool
    var canRedo: Bool
}

final class UndoJournal {
    static let shared = UndoJournal()
    init() {}

    /// Stores that aren't part of the work people undo.
    static let untracked: Set<String> = ["activity.json", "chat_messages.json", "announcements.json", "sign_requests.json",
                                         "user_profiles.json", "user_teams.json"]

    /// One store's records changed by a step: as they were before and after
    /// (absent = the record wasn't there), and where each stood in the file.
    struct Change {
        var url: URL
        var ids: [String] = []
        var before: [String: Data] = [:]
        var after: [String: Data] = [:]
        var beforeAt: [String: Int] = [:]
        var afterAt: [String: Int] = [:]
    }

    struct Step {
        var action: String
        var label: String
        var stores: [String] = []
        var changes: [String: Change] = [:]
    }

    var undoSteps: [Step] = []
    var redoSteps: [Step] = []
    var current: Step?
    let limit = 60

    /// Actions that change nothing of the person's work, or not undoably:
    /// reading, exporting and printing, files, backups, chat, the team.
    static func journaled(_ action: String) -> Bool {
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return false }
        let area = parts[0], verb = parts[1]
        let skipAreas: Set<String> = ["history", "chat", "team", "users", "web", "app", "backup", "cloudBackup", "announcements",
                                      "signatures", "search", "calendar", "dashboard"]
        if skipAreas.contains(area) { return false }
        let readPrefixes = ["get", "list", "export", "print", "reveal", "open", "locate"]
        let reads: Set<String> = ["page", "detail", "summary", "data", "search", "status", "due", "expiring", "profiles", "people", "events",
                                  "leads", "image", "letterhead", "combinePDF", "unitRatesPDF", "saveCSV", "saveWord", "proposeNumber",
                                  "signedCopy", "deliverySchedule", "standardRates", "syncStatus", "authors", "chain", "typing",
                                  "importPreview", "logoPreview", "numberPreview", "chooseAndRestore"]
        return !reads.contains(verb) && !readPrefixes.contains { verb.hasPrefix($0) }
    }

    /// "boq:addLineItem" → "Add line item (BOQ)".
    static func label(_ action: String) -> String {
        let parts = action.split(separator: ":", maxSplits: 1).map(String.init)
        let areas = ["boq": "BOQ", "quotations": "quotation", "invoices": "invoice", "deliveryNotes": "delivery note", "letters": "letter",
                     "projects": "project", "clients": "client", "sites": "site", "priceListItems": "material list", "priceLists": "material list",
                     "drawings": "drawing", "documents": "document", "stock": "stock", "accounts": "accounts", "employees": "employee",
                     "tasks": "task", "inspections": "inspection", "marketing": "lead", "settings": "settings", "workers": "worker",
                     "workerDocuments": "worker document", "adminDocuments": "admin document", "lines": "quantities"]
        guard parts.count == 2 else { return action }
        var words = ""
        for ch in parts[1] {
            if ch.isUppercase { words += " " + ch.lowercased() } else { words.append(ch) }
        }
        words = words.replacingOccurrences(of: " boq", with: " BOQ")
        let verb = words.prefix(1).uppercased() + words.dropFirst()
        return areas[parts[0]].map { "\(verb) (\($0))" } ?? verb
    }

    /// Whether a save to this file is being noted (an action is running).
    func wants(_ url: URL) -> Bool { current != nil && !UndoJournal.untracked.contains(url.lastPathComponent) }

    func begin(_ action: String) {
        current = UndoJournal.journaled(action) ? Step(action: action, label: UndoJournal.label(action)) : nil
    }

    func record(_ url: URL, old: Data?, new: Data) {
        guard var step = current else { return }
        let before = UndoJournal.records(old), after = UndoJournal.records(new)
        let key = url.path
        var change = step.changes[key] ?? Change(url: url)
        for id in Set(before.data.keys).union(after.data.keys) where before.data[id] != after.data[id] {
            if !change.ids.contains(id) {
                // The first time this step touches the record: as it was before the step.
                change.ids.append(id)
                change.before[id] = before.data[id]
                change.beforeAt[id] = before.at[id]
            }
            change.after[id] = after.data[id]
            change.afterAt[id] = after.at[id]
        }
        if !change.ids.isEmpty && step.changes[key] == nil { step.stores.append(key) }
        if !change.ids.isEmpty { step.changes[key] = change }
        current = step
    }

    func end() {
        guard let step = current else { return }
        current = nil
        // Kept only when something really changed (and stayed changed).
        let changed = step.changes.values.contains { c in c.ids.contains { c.before[$0] != c.after[$0] } }
        guard changed else { return }
        undoSteps.append(step)
        if undoSteps.count > limit { undoSteps.removeFirst(undoSteps.count - limit) }
        redoSteps.removeAll()
    }

    var canUndo: Bool { !undoSteps.isEmpty }
    var canRedo: Bool { !redoSteps.isEmpty }

    /// Undoes the latest step; its label, or nil when there's nothing to undo.
    func undo() -> String? {
        guard let step = undoSteps.popLast() else { return nil }
        apply(step, back: true)
        redoSteps.append(step)
        return step.label
    }

    func redo() -> String? {
        guard let step = redoSteps.popLast() else { return nil }
        apply(step, back: false)
        undoSteps.append(step)
        return step.label
    }

    /// Puts the step's records back as they were before it (`back`) or after it.
    func apply(_ step: Step, back: Bool) {
        for key in (back ? step.stores.reversed() : step.stores) {
            guard let change = step.changes[key] else { continue }
            let current = (try? Data(contentsOf: change.url)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [Any] } ?? []
            var rows = current
            let target = back ? change.before : change.after
            let places = back ? change.beforeAt : change.afterAt
            // Off first, then back in their old places (lowest first, so the places hold).
            let touched = Set(change.ids)
            rows.removeAll { (($0 as? [String: Any])?["id"] as? String).map { touched.contains($0) } ?? false }
            let restore = change.ids.filter { target[$0] != nil }.sorted { (places[$0] ?? .max) < (places[$1] ?? .max) }
            for id in restore {
                guard let data = target[id], let record = try? JSONSerialization.jsonObject(with: data) else { continue }
                rows.insert(record, at: min(places[id] ?? rows.count, rows.count))
            }
            guard let data = try? JSONSerialization.data(withJSONObject: rows) else { continue }
            StoreFile.write(data, to: change.url)
        }
    }

    /// A store file's records by id: each as JSON (keys sorted, so the same
    /// record always reads the same) and its place in the file.
    static func records(_ data: Data?) -> (data: [String: Data], at: [String: Int]) {
        guard let data = data, let array = try? JSONSerialization.jsonObject(with: data) as? [Any] else { return ([:], [:]) }
        var out: [String: Data] = [:], at: [String: Int] = [:]
        for (i, item) in array.enumerated() {
            guard let record = item as? [String: Any], let id = record["id"] as? String, out[id] == nil else { continue }
            out[id] = (try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys])) ?? Data()
            at[id] = i
        }
        return (out, at)
    }
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

    /// A project's name from its number (set by the app), for its folder's name.
    var projectName: ((String) -> String?)?

    /// "26219 NOL Ancilliary Works": a project's folder — its number, then its name.
    func projectFolderName(_ projectNumber: String) -> String {
        guard let name = projectName?(projectNumber).flatMap({ nonBlank($0) }) else { return projectNumber }
        return safeFileName("\(projectNumber) \(name)")
    }

    /// The folders already there for a project's number ("26219", "26219 …").
    func existingProjectFolders(_ projectNumber: String) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: projectsRoot.path)) ?? [])
            .filter { $0 == projectNumber || $0.hasPrefix(projectNumber + " ") }.sorted()
            .map { projectsRoot.appendingPathComponent($0, isDirectory: true) }
    }

    /// A project's folder: named as above, or the one already there for its
    /// number until it's renamed (organiseProjectFolder).
    func projectFolder(_ projectNumber: String) -> URL {
        let wanted = projectsRoot.appendingPathComponent(projectFolderName(projectNumber), isDirectory: true)
        if FileManager.default.fileExists(atPath: wanted.path) { return wanted }
        return existingProjectFolders(projectNumber).first ?? wanted
    }

    /// "26219 BOQ", "26219 Quotations"…: a folder inside a project's folder
    /// (the old plain name until it's renamed).
    func projectSubfolder(_ projectNumber: String, _ sub: String) -> URL {
        let folder = projectFolder(projectNumber)
        let wanted = folder.appendingPathComponent("\(projectNumber) \(sub)", isDirectory: true)
        let plain = folder.appendingPathComponent(sub, isDirectory: true)
        let fm = FileManager.default
        if !fm.fileExists(atPath: wanted.path) && fm.fileExists(atPath: plain.path) { return plain }
        return wanted
    }

    /// A quotation series' title (its structure, else its quotation's
    /// subject), from the project's number and the series (set by the app).
    var seriesName: ((String, String) -> String?)?

    /// "26219-001 GL∕09 Platform": a quotation series' folder — its number,
    /// then its structure or subject.
    func seriesFolderName(_ projectNumber: String, _ series: String) -> String {
        guard let title = seriesName?(projectNumber, series).flatMap({ nonBlank($0) }) else { return series }
        return safeFileName("\(series) \(String(title.prefix(80)))")
    }

    /// The folders already there for a series ("26219-001", "26219-001 …").
    func existingSeriesFolders(_ projectNumber: String, _ series: String) -> [URL] {
        let folder = projectFolder(projectNumber)
        return ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0 == series || $0.hasPrefix(series + " ") }.sorted()
            .map { folder.appendingPathComponent($0, isDirectory: true) }
    }

    /// A series' folder: named as above, or the one already there for it
    /// until it's renamed (NativeBridge.organiseSeriesFolders).
    func seriesRoot(_ projectNumber: String, _ series: String) -> URL {
        let wanted = projectFolder(projectNumber).appendingPathComponent(seriesFolderName(projectNumber, series), isDirectory: true)
        if FileManager.default.fileExists(atPath: wanted.path) { return wanted }
        return existingSeriesFolders(projectNumber, series).first ?? wanted
    }

    /// "26219-001 …/26219-001 Quotations": a quotation series' folder for one
    /// kind of file (BOQ, Quotations, Delivery Schedules, Delivery Notes,
    /// Invoices, Drawings, Documents), inside the project's folder.
    func seriesFolder(_ projectNumber: String, _ series: String, _ sub: String) -> URL {
        seriesRoot(projectNumber, series).appendingPathComponent("\(series) \(sub)", isDirectory: true)
    }

    /// Moves everything in `from` into `into` (folders of the same name
    /// merged), then removes `from` if that left it empty. Returns the moves.
    func mergeFolder(_ from: URL, into: URL) -> [(String, String)] {
        let fm = FileManager.default
        var moves: [(String, String)] = []
        try? fm.createDirectory(at: into, withIntermediateDirectories: true)
        for item in (try? fm.contentsOfDirectory(atPath: from.path)) ?? [] where item != ".DS_Store" {
            let source = from.appendingPathComponent(item)
            let target = into.appendingPathComponent(item)
            var isDir: ObjCBool = false
            var targetIsDir: ObjCBool = false
            if fm.fileExists(atPath: source.path, isDirectory: &isDir), isDir.boolValue,
               fm.fileExists(atPath: target.path, isDirectory: &targetIsDir), targetIsDir.boolValue {
                moves += mergeFolder(source, into: target)
                continue
            }
            let to = uniqueDestination(target)
            if (try? fm.moveItem(at: source, to: to)) != nil { moves.append((source.path, to.path)) }
        }
        if ((try? fm.contentsOfDirectory(atPath: from.path)) ?? []).allSatisfy({ $0 == ".DS_Store" }) { try? fm.removeItem(at: from) }
        return moves
    }

    /// True when a folder holds nothing (or only Finder's .DS_Store).
    func isEmptyFolder(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return false }
        return ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).allSatisfy { $0 == ".DS_Store" }
    }

    /// Renames a project's folder to "<number> <name>" and the folders in it
    /// to "<number> BOQ", "<number> Quotations"… (also after its name or
    /// number changes). Returns the moves (old path → new), and the old
    /// names' paths, so the file paths kept in the database can follow.
    func organiseProjectFolder(_ projectNumber: String) -> [(String, String)] {
        let fm = FileManager.default
        var moves: [(String, String)] = []
        let target = projectsRoot.appendingPathComponent(projectFolderName(projectNumber), isDirectory: true)
        let others = existingProjectFolders(projectNumber).filter { $0.lastPathComponent != target.lastPathComponent }
        if !fm.fileExists(atPath: target.path), let current = others.first, (try? fm.moveItem(at: current, to: target)) != nil {
            moves.append((current.path, target.path))
        }
        // Paths saved under its earlier names (another Mac may have renamed it).
        for old in [projectsRoot.appendingPathComponent(projectNumber, isDirectory: true)] + others where old.lastPathComponent != target.lastPathComponent {
            moves.append((old.path, target.path))
        }
        guard fm.fileExists(atPath: target.path) else { return moves }
        let names = (try? fm.contentsOfDirectory(atPath: target.path)) ?? []
        for sub in projectSubfolders + ["Letters"] {
            let wantedName = "\(projectNumber) \(sub)"
            let wanted = target.appendingPathComponent(wantedName, isDirectory: true)
            // The plain name, or another number's (after the number changed).
            let words = sub.split(separator: " ").count
            // (Not a quotation series' folder, "26219-001 Other".)
            let legacy = names.filter { $0 != wantedName && ($0 == sub || ($0.hasSuffix(" \(sub)") && $0.split(separator: " ").count == words + 1))
                && $0.range(of: #"^\S+-[0-9]+ "#, options: .regularExpression) == nil }
            for name in legacy {
                let old = target.appendingPathComponent(name, isDirectory: true)
                if !fm.fileExists(atPath: wanted.path) {
                    if (try? fm.moveItem(at: old, to: wanted)) != nil { moves.append((old.path, wanted.path)) }
                } else {
                    // Both there: what's in the old one moves in.
                    for item in (try? fm.contentsOfDirectory(atPath: old.path)) ?? [] where item != ".DS_Store" {
                        let from = old.appendingPathComponent(item)
                        let to = uniqueDestination(wanted.appendingPathComponent(item))
                        if (try? fm.moveItem(at: from, to: to)) != nil { moves.append((from.path, to.path)) }
                    }
                    if ((try? fm.contentsOfDirectory(atPath: old.path)) ?? []).allSatisfy({ $0 == ".DS_Store" }) { try? fm.removeItem(at: old) }
                }
            }
            moves.append((target.appendingPathComponent(sub, isDirectory: true).path, wanted.path))
        }
        return moves
    }

    @discardableResult
    func createProjectFolders(_ projectNumber: String) -> URL {
        let folder = projectFolder(projectNumber)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // Its Drawings, Documents and Other folders are made when something
        // is first put in them; each quotation series' folders as soon as
        // the series exists (NativeBridge.makeSeriesFolders).
        return folder
    }

    func copyFileIntoProject(source: URL, projectNumber: String, subfolder: String, meaningfulFilename: String, folder: URL? = nil) throws -> URL {
        let destFolder = folder ?? projectSubfolder(projectNumber, subfolder)
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
    func writeGeneratedFile(data: Data, projectNumber: String, subfolder: String, meaningfulFilename: String, folder: URL? = nil) throws -> URL {
        let destFolder = folder ?? projectSubfolder(projectNumber, subfolder)
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

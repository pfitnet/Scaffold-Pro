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
// MARK: - Local copy (while the files are in a shared folder)
//
// Sharing with other Macs moves the project files into the shared iCloud
// folder, so Documents › ScaffoldPro (where they used to be) would stop
// changing. Instead it's kept up to date as a local copy of everything —
// Database, Projects, Administration, Configuration (so "Restore from
// Folder…" can restore it) — the same way as the iCloud copy: only what
// changed is copied, nothing is deleted from it, about a minute after a
// save, every 15 minutes and when ScaffoldPro opens. Files that are still
// only in iCloud are asked for and copied on a later run.
// =====================================================================

struct LocalCopyStatus: Codable {
    /// Only while working from a shared folder.
    var active: Bool
    var folder: String
    var lastAt: String?
    var lastCopied: Int?
    /// Files still only in iCloud, to be copied once they're down.
    var waiting: Int?
    var lastError: String?
    var running: Bool
}

struct AutoBackupStatus: Codable {
    /// The last automatic (12:00) backup, and its problem if any.
    var lastAt: String?
    var lastError: String?
    var running: Bool
    var local: LocalCopyStatus? = nil
}

final class LocalCopyManager {
    let db: AppDatabase
    let storage: FileStorage
    let queue = DispatchQueue(label: "ScaffoldPro.localCopy", qos: .utility)
    let defaults = UserDefaults.standard
    var timer: Timer?
    var pending: DispatchWorkItem?
    var running = false
    enum Key {
        static let lastAt = "localCopy.lastAt"
        static let lastCopied = "localCopy.lastCopied"
        static let waiting = "localCopy.waiting"
        static let lastError = "localCopy.lastError"
    }

    /// Documents › ScaffoldPro.
    let target: URL

    init(db: AppDatabase, storage: FileStorage) {
        self.db = db
        self.storage = storage
        target = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScaffoldPro", isDirectory: true)
    }

    /// Working from a shared folder (not from Documents › ScaffoldPro itself).
    var active: Bool { storage.appRoot.standardizedFileURL.path != target.standardizedFileURL.path }

    func status() -> LocalCopyStatus {
        let iso = ISO8601DateFormatter()
        return LocalCopyStatus(active: active, folder: target.path,
                               lastAt: (defaults.object(forKey: Key.lastAt) as? Double).map { iso.string(from: Date(timeIntervalSince1970: $0)) },
                               lastCopied: defaults.object(forKey: Key.lastCopied) as? Int,
                               waiting: defaults.object(forKey: Key.waiting) as? Int,
                               lastError: defaults.string(forKey: Key.lastError), running: running)
    }

    func start() {
        guard active else { return }
        NotificationCenter.default.addObserver(forName: CloudBackupManager.dataSaved, object: nil, queue: .main) { [weak self] _ in
            self?.schedule(after: 60)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.copyNow() }
        schedule(after: 30)
    }

    func schedule(after seconds: TimeInterval) {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.copyNow() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    /// Copies what changed (main thread; the copying runs in the background).
    func copyNow(completion: ((LocalCopyStatus) -> Void)? = nil) {
        guard active, !running else { completion?(status()); return }
        running = true
        let startedAt = Date()
        let since = (defaults.object(forKey: Key.lastAt) as? Double).map { Date(timeIntervalSince1970: $0) }
        let target = self.target
        let sources = [(db.dataDir, "Database"), (storage.projectsRoot, "Projects"), (storage.administrationRoot, "Administration")]
        let appRoot = storage.appRoot.path
        queue.async { [weak self] in
            let fm = FileManager.default
            var copied = 0, files = 0, waiting = 0
            var bytes: Int64 = 0
            var failed: [String] = []
            var error: String? = nil
            do {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                for (source, name) in sources where fm.fileExists(atPath: source.path) {
                    // The database is small: always compared in full.
                    let r = CloudBackupManager.mirrorFolder(source, to: target.appendingPathComponent(name, isDirectory: true),
                                                            since: name == "Database" ? nil : since)
                    copied += r.copied; files += r.files; bytes += r.bytes; waiting += r.waiting; failed += r.failed
                }
                let projects = target.appendingPathComponent("Projects", isDirectory: true)
                let projectCount = ((try? fm.contentsOfDirectory(atPath: projects.path)) ?? []).filter { !$0.hasPrefix(".") }.count
                let manifest = BackupManifest(app: "ScaffoldPro", formatVersion: 1, createdAt: nowISO(), kind: "Local copy",
                                              sourceAppRoot: appRoot, projectCount: projectCount, fileCount: files, totalBytes: bytes)
                let config = target.appendingPathComponent("Configuration", isDirectory: true)
                try fm.createDirectory(at: config, withIntermediateDirectories: true)
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                try encoder.encode(manifest).write(to: config.appendingPathComponent("manifest.json"), options: .atomic)
                if !failed.isEmpty {
                    error = "\(failed.count) file\(failed.count == 1 ? "" : "s") couldn't be copied, e.g. \(failed[0]). It will try again."
                }
            } catch let e {
                error = e.localizedDescription
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.running = false
                if error == nil || !failed.isEmpty {
                    self.defaults.set(startedAt.timeIntervalSince1970, forKey: Key.lastAt)
                    self.defaults.set(copied, forKey: Key.lastCopied)
                    self.defaults.set(waiting, forKey: Key.waiting)
                }
                if let error = error { self.defaults.set(error, forKey: Key.lastError) } else { self.defaults.removeObject(forKey: Key.lastError) }
                completion?(self.status())
            }
        }
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
    /// Where it listens for the others' changes on the office network
    /// (TeamLink): its port and addresses.
    var linkPort: Int? = nil
    var linkAddresses: [String]? = nil
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
    static var current: TeamSync?
    /// Set while this Mac (not in a shared folder) keeps its material list
    /// in step with the other Macs through iCloud Drive.
    static var material: TeamSync?

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
    static let folderKey = "team.folder"
    static let deviceKey = "team.deviceId"
    static let nameKey = "team.memberName"

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

    /// Someone using ScaffoldPro Web from a browser: while their request is
    /// handled, they are "me" (who made what, their tasks, their chat).
    static var actingAs: String?

    static var memberName: String {
        get {
            if let acting = actingAs { return acting }
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

    static func versionDate(_ v: String?) -> Date? {
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
    var databaseRoot: URL { root.appendingPathComponent("Database", isDirectory: true) }
    var ownFolder: URL { databaseRoot.appendingPathComponent(device, isDirectory: true) }
    var membersFolder: URL { root.appendingPathComponent("Members", isDirectory: true) }

    /// A record as last changed: when (t), its place in the list (c), and
    /// its value — nil once deleted.
    struct Entry {
        var t: Double
        var c: Double
        var v: [String: Any]?
    }

    /// This Mac's log, store by store ("clients.json" → id → entry).
    var own: [String: [String: Entry]] = [:]
    /// The other Macs' logs as last read, by file path.
    var others: [String: (signature: String, device: String, store: String, entries: [String: Entry])] = [:]
    /// Each record's place in its list, from the last merge.
    var order: [String: [String: Double]] = [:]
    var lastStamp: Double = 0
    var timer: Timer?
    var scanning = false
    var lastChangeAt: Date?
    var lastChangeBy: String?
    /// Called (main thread) after other Macs' changes are merged in: the
    /// stores that changed and who changed them.
    var onRemoteChange: (([String], [String]) -> Void)?
    let queue = DispatchQueue(label: "ScaffoldPro.teamSync", qos: .userInitiated)

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

    // MARK: who's typing in Chat (a small file per Mac, not the log)

    var typingFolder: URL { root.appendingPathComponent("Typing", isDirectory: true) }

    func setTyping(_ conversation: String?) {
        let file = typingFolder.appendingPathComponent("\(device).json")
        guard let conversation = conversation else { try? FileManager.default.removeItem(at: file); return }
        let body: [String: Any] = ["name": TeamSync.memberName, "conversation": conversation, "at": Date().timeIntervalSince1970]
        try? FileManager.default.createDirectory(at: typingFolder, withIntermediateDirectories: true)
        if let data = try? JSONSerialization.data(withJSONObject: body) { try? data.write(to: file, options: .atomic) }
    }

    /// Who else is typing in a conversation (in the last 6 seconds).
    func typing(in conversation: String) -> [String] {
        let fm = FileManager.default
        let now = Date().timeIntervalSince1970
        var names: [String] = []
        for url in (try? fm.contentsOfDirectory(at: typingFolder, includingPropertiesForKeys: nil)) ?? [] where url.pathExtension == "json" {
            guard url.deletingPathExtension().lastPathComponent != device,
                  let data = try? Data(contentsOf: url),
                  let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  body["conversation"] as? String == conversation,
                  let at = body["at"] as? Double, now - at < 6,
                  let name = body["name"] as? String,
                  name.lowercased() != TeamSync.memberName.lowercased() else { continue }
            if !names.contains(name) { names.append(name) }
        }
        return names
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
        // Changes also go straight to the other Macs on the same network.
        if only == nil { TeamLink.shared.start(root: root) }
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.checkForChanges() }
        Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in self?.touchMember() }
        return true
    }

    /// Brings back any file in `folder` that iCloud Drive has moved off
    /// this Mac (".name.icloud"), waiting up to `timeout` seconds.
    func downloadEverything(in folder: URL, timeout: TimeInterval) -> Bool {
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
        var sent: [String: Any] = [:]
        let now = nextStamp()
        for (index, (id, record)) in after.list.enumerated() {
            guard before.canonical[id] != after.canonical[id] else { continue }
            // New records go after the rest, in the order they were saved.
            let place = places[id] ?? now + Double(index) * 1e-6
            let value = portable(record)
            log[id] = Entry(t: now, c: place, v: value)
            places[id] = place
            sent[id] = ["t": now, "c": place, "v": value] as [String: Any]
            changed = true
        }
        for id in before.canonical.keys where after.canonical[id] == nil {
            log[id] = Entry(t: now, c: places[id] ?? 0, v: nil)
            sent[id] = ["t": now, "c": places[id] ?? 0, "v": NSNull()] as [String: Any]
            places[id] = nil
            changed = true
        }
        guard changed else { return }
        own[store] = log
        order[store] = places
        writeOwnLog(store)
        if only == nil { TeamLink.shared.send(device: device, store: store, records: sent) }
    }

    // MARK: the fast lane (TeamLink)

    /// Changes other Macs sent straight over the network, ahead of iCloud
    /// Drive bringing their logs: "device|store" → id → entry.
    var pushed: [String: [String: Entry]] = [:]

    /// Another Mac's change, sent over the network (main thread).
    func receivePushed(device from: String, store: String, records: [String: Any]) {
        guard from != device, handles(store), !store.contains("/") else { return }
        let key = "\(from)|\(store)"
        var overlay = pushed[key] ?? [:]
        let inFile = others.values.first { $0.device == from && $0.store == store }?.entries ?? [:]
        var changed = false
        for (id, raw) in records {
            guard let e = raw as? [String: Any], let t = (e["t"] as? NSNumber)?.doubleValue else { continue }
            if let have = overlay[id], have.t >= t { continue }
            if let have = inFile[id], have.t >= t { continue }
            overlay[id] = Entry(t: t, c: (e["c"] as? NSNumber)?.doubleValue ?? 0, v: e["v"] as? [String: Any])
            changed = true
        }
        guard changed else { return }
        pushed[key] = overlay
        lastStamp = max(lastStamp, overlay.values.map { $0.t }.max() ?? 0)
        materialize(store)
        let name = memberName(of: from)
        lastChangeAt = Date()
        lastChangeBy = name
        onRemoteChange?([store], [name])
    }

    /// Says where this Mac listens (once TeamLink is ready, or moved).
    func announceLink() { touchMember() }

    /// Someone using ScaffoldPro Web through this Mac: listed among the
    /// devices on every Mac's Team page, as themselves.
    func touchWebMember(name: String, token: String, agent: String) {
        let fm = FileManager.default
        try? fm.createDirectory(at: membersFolder, withIntermediateDirectories: true)
        let id = "web-" + String(token.prefix(8))
        let member = TeamMember(id: id, name: name, computer: "\(agent) via \(TeamSync.computerName) (web)", lastSeen: nowISO(), version: nil)
        if let data = try? JSONEncoder().encode(member) {
            try? data.write(to: membersFolder.appendingPathComponent("\(id).json"), options: .atomic)
        }
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
    func nextStamp() -> Double {
        lastStamp = max(Date().timeIntervalSince1970, lastStamp + 0.001)
        return lastStamp
    }

    func writeOwnLog(_ store: String) {
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

    struct Scan {
        var changed: [String: (signature: String, device: String, store: String, entries: [String: Entry])] = [:]
        var gone: [String] = []
    }

    func checkForChanges() {
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
    func scanOthers(known: [String: String]) -> Scan {
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
    func apply(_ scan: Scan) -> Set<String> {
        var stores = Set<String>()
        for (path, log) in scan.changed {
            others[path] = log
            stores.insert(log.store)
            // What came over the network first is in the file now.
            let key = "\(log.device)|\(log.store)"
            if let overlay = pushed[key] {
                let left = overlay.filter { id, e in (log.entries[id]?.t ?? -1) < e.t }
                pushed[key] = left.isEmpty ? nil : left
            }
            lastStamp = max(lastStamp, log.entries.values.map { $0.t }.max() ?? 0)
        }
        for path in scan.gone {
            if let log = others.removeValue(forKey: path) { stores.insert(log.store) }
        }
        return stores
    }

    /// Rewrites the local copy of a store from every Mac's log: each
    /// record's newest change wins; deleted records are left out.
    func materialize(_ store: String) {
        var best: [String: (entry: Entry, device: String)] = [:]
        func consider(_ id: String, _ e: Entry, _ from: String) {
            if let b = best[id], b.entry.t > e.t || (b.entry.t == e.t && b.device >= from) { return }
            best[id] = (e, from)
        }
        for log in others.values where log.store == store {
            for (id, e) in log.entries { consider(id, e, log.device) }
        }
        for (key, entries) in pushed where key.hasSuffix("|" + store) {
            let from = String(key.dropLast(store.count + 1))
            for (id, e) in entries { consider(id, e, from) }
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

    func touchMember() {
        let fm = FileManager.default
        try? fm.createDirectory(at: membersFolder, withIntermediateDirectories: true)
        var me = TeamMember(id: device, name: TeamSync.memberName, computer: TeamSync.computerName, lastSeen: nowISO(), version: TeamSync.appVersion)
        if only == nil, let port = TeamLink.shared.port {
            me.linkPort = port
            me.linkAddresses = TeamLink.shared.addresses
        }
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

    func memberName(of id: String) -> String {
        let url = membersFolder.appendingPathComponent("\(id).json")
        return (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(TeamMember.self, from: $0) }?.name ?? "another Mac"
    }

    // MARK: JSON helpers

    func logFiles(in folder: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" && !$0.lastPathComponent.hasPrefix(".") && !$0.lastPathComponent.contains(".unreadable-")
                && handles($0.lastPathComponent) }
    }

    func parseLog(_ url: URL) -> [String: Entry]? {
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
    static func recordsById(_ data: Data?) -> (list: [(String, [String: Any])], canonical: [String: Data]) {
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
    func portable(_ record: [String: Any], extraRoots: [URL] = []) -> [String: Any] {
        let prefixes = ([root] + extraRoots).map { $0.standardizedFileURL.path + "/" }
        return TeamSync.mapStrings(record) { s in
            for p in prefixes where s.hasPrefix(p) { return TeamSync.pathToken + "/" + s.dropFirst(p.count) }
            return s
        } as? [String: Any] ?? record
    }

    /// Relative paths → this Mac's path to the shared folder.
    func local(_ record: [String: Any]) -> [String: Any] {
        let prefix = TeamSync.pathToken + "/"
        let base = root.standardizedFileURL.path + "/"
        return TeamSync.mapStrings(record) { s in
            s.hasPrefix(prefix) ? base + s.dropFirst(prefix.count) : s
        } as? [String: Any] ?? record
    }

    static func mapStrings(_ value: Any, _ f: (String) -> String) -> Any {
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
            guard m.isThisMac != true, let seen = parseISODate(m.lastSeen), seen > recent,
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
    static func copyMerging(_ source: URL, into destination: URL) -> [String] {
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

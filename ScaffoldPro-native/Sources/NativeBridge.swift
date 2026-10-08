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
// MARK: - Native bridge (replaces main.js's ipcMain handlers)
// =====================================================================

final class NativeBridge: NSObject, WKScriptMessageHandler {
    weak var webView: WKWebView?
    weak var window: NSWindow?
    let db: AppDatabase
    let storage: FileStorage
    let backups: BackupManager
    let cloudBackup: CloudBackupManager
    /// While the files are in a shared folder: Documents › ScaffoldPro kept as a local copy.
    let localCopy: LocalCopyManager
    /// Settings › Google Sheets: the overview sheet kept in step.
    let sheets: GoogleSheetsSync
    /// Only one backup or restore may run at a time.
    var backupInProgress = false
    /// A parsed-but-not-yet-applied price import, keyed by the preview's
    /// token, so the person can review it before anything changes.
    var pendingPriceImport: (token: String, sourceKey: String, rows: [ParsedPriceRow])?
    var pendingPartyImport: (token: String, kind: String, rows: [(row: [String: String], matchId: String?)])?
    /// Quotation files being imported, by token: the file (in a temporary
    /// folder) and the text read from it.
    var pendingQuotationImports: [String: (url: URL, text: String)] = [:]

    init(db: AppDatabase, storage: FileStorage) {
        self.db = db
        self.storage = storage
        self.backups = BackupManager(db: db, storage: storage)
        self.cloudBackup = CloudBackupManager(db: db, storage: storage)
        self.localCopy = LocalCopyManager(db: db, storage: storage)
        self.sheets = GoogleSheetsSync(db: db)
        QuotationAI.shared.db = db
        storage.projectName = { [weak db] number in db?.getProjectByNumber(number)?.name }
        storage.seriesName = { [weak db] number, series in db?.seriesTitle(projectNumber: number, series: series) }
    }

    /// Project folders named "<number> <name>", with "<number> BOQ",
    /// "<number> Quotations"… inside (renaming older ones), and the stored
    /// file paths moved with them. All projects when `numbers` is nil.
    func organiseProjectFolders(_ numbers: [String]? = nil) {
        guard FileManager.default.fileExists(atPath: storage.projectsRoot.path) else { return }
        var moves: [(String, String)] = []
        for number in numbers ?? db.allProjectNumbers() where !number.isEmpty {
            moves += storage.organiseProjectFolder(number)
            moves += organiseSeriesFolders(number)
            moves += fileDocumentsBySeries(number)
        }
        db.rebaseFilePaths(moves: moves)
        moves = []
        for number in numbers ?? db.allProjectNumbers() where !number.isEmpty { moves += fileLinkedFiles(number) }
        db.rebaseFilePaths(moves: moves)
        makeSeriesFolders(numbers)
        for number in numbers ?? db.allProjectNumbers() where !number.isEmpty { removeEmptyProjectFolders(number) }
    }

    /// A picture of the page, laid over it while it reloads (so there's no
    /// blank flash), until the reloaded page says it has drawn.
    var heldFrame: NSView?
    /// Assistant runs the person interrupted (assistant:cancel): they stop
    /// at the next step, and their answer is dropped.
    var assistantCancelled = Set<String>()

    func holdFrame(_ done: @escaping () -> Void) {
        guard let webView = webView, let container = webView.superview else { done(); return }
        // The picture already on screen (no waiting for another draw), and
        // never more than a moment's wait for it: the page change mustn't lag.
        var finished = false
        let finish = { if !finished { finished = true; done() } }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: finish)
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = false
        webView.takeSnapshot(with: config) { [weak self] image, _ in
            guard let self = self, let image = image, !finished else { finish(); return }
            self.heldFrame?.removeFromSuperview()
            let view = NSImageView(frame: webView.frame)
            view.image = image
            view.imageScaling = .scaleAxesIndependently
            view.autoresizingMask = [.width, .height]
            container.addSubview(view, positioned: .above, relativeTo: webView)
            self.heldFrame = view
            // Never left up for long, whatever happens to the page.
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self, weak view] in
                if let view = view, self?.heldFrame === view { self?.releaseFrame() }
            }
            finish()
        }
    }

    /// Whether a picture of the page is being held over it.
    var holdingFrame: Bool { heldFrame != nil }

    func releaseFrame() {
        guard let view = heldFrame else { return }
        heldFrame = nil
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.12
            view.animator().alphaValue = 0
        }, completionHandler: { view.removeFromSuperview() })
    }

    /// The project folders kept for each kind of document. Inside a
    /// quotation series' folder they're "26001-002 BOQ", "26001-002
    /// Quotations"…, plus "26001-002 Delivery Schedules".
    static let documentKindFolders = ["BOQ", "Quotations", "Invoices", "Delivery Notes"]
    /// What's in each quotation series' folder, made even while empty.
    static let seriesKindFolders = ["BOQ", "Quotations", "Delivery Schedules", "Delivery Notes", "Invoices", "Drawings", "Documents"]
    /// The folders' tidy-up, waiting for a pause in typing (see handle).
    var organiseSoon: DispatchWorkItem?
    /// Actions after which a project may have a new quotation series.
    static let seriesCreatingActions: Set<String> = ["boq:create", "assistant:run", "quotations:create", "quotations:duplicate", "quotations:importCreate",
                                                             "quotations:importFromBOQ", "deliveryNotes:create", "deliveryNotes:importQuotation", "invoices:create"]

    /// A project's quotation series ("26219-001", "26219-002"…), from its
    /// BOQs, quotations, delivery notes and invoices.
    func projectSeries(_ projectNumber: String) -> [String] {
        (db.seriesByProject()[projectNumber] ?? []).sorted()
    }

    /// Each series' folder with its BOQ, Quotations, Delivery Schedules,
    /// Delivery Notes and Invoices folders inside, for one project or all.
    func makeSeriesFolders(_ numbers: [String]? = nil) {
        guard FileManager.default.fileExists(atPath: storage.projectsRoot.path) else { return }
        let all = db.seriesByProject()
        for number in numbers ?? db.allProjectNumbers() where !number.isEmpty {
            for series in (all[number] ?? []).sorted() {
                let root = storage.seriesRoot(number, series)
                for kind in NativeBridge.seriesKindFolders {
                    let folder = root.appendingPathComponent("\(series) \(kind)", isDirectory: true)
                    if !FileManager.default.fileExists(atPath: folder.path) {
                        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    }
                }
            }
        }
    }

    /// Where a project's file goes: the folder of its quotation series and
    /// kind ("26001-002/26001-002 Quotations"; delivery schedules in
    /// "26001-002 Delivery Schedules"), found from the document's number
    /// (given, or in the file's name). Files of several documents go in
    /// "<number> Other"; anything else in the project's own subfolder.
    func fileFolder(projectNumber: String, subfolder: String, name: String, docTypeTag: String? = nil, documentNumber: String? = nil) -> URL {
        if docTypeTag == "Combined" || isCombinedExport(name) { return storage.projectSubfolder(projectNumber, "Other") }
        guard NativeBridge.documentKindFolders.contains(subfolder) else { return storage.projectSubfolder(projectNumber, subfolder) }
        let schedule = (docTypeTag ?? "").hasPrefix("Delivery Schedule") || name.lowercased().contains("delivery schedule")
        var series: String?
        if let tag = docTypeTag, let number = nonBlank(documentNumber) { series = db.documentSeries(docTypeTag: tag, number: number) }
        if series == nil, let project = db.getProjectByNumber(projectNumber) {
            let safe = { (n: String) in n.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-") }
            if let match = db.projectDocumentNumbers(projectId: project.id).first(where: { name.contains(safe($0.number)) }) {
                series = db.documentSeries(docTypeTag: match.tag, number: match.number)
            }
        }
        // A project with one series: anything of its kind goes there.
        if series == nil {
            let all = projectSeries(projectNumber)
            if all.count == 1 { series = all.first }
        }
        guard let found = series else { return storage.projectSubfolder(projectNumber, subfolder) }
        return storage.seriesFolder(projectNumber, found, schedule ? "Delivery Schedules" : subfolder)
    }

    /// Renames each quotation series' folder to "<series> <structure or
    /// subject>" (merging any other folder of the same series into it).
    func organiseSeriesFolders(_ projectNumber: String) -> [(String, String)] {
        let fm = FileManager.default
        let projectFolder = storage.projectFolder(projectNumber)
        guard fm.fileExists(atPath: projectFolder.path) else { return [] }
        var moves: [(String, String)] = []
        for series in projectSeries(projectNumber) {
            let target = projectFolder.appendingPathComponent(storage.seriesFolderName(projectNumber, series), isDirectory: true)
            for old in storage.existingSeriesFolders(projectNumber, series) where old.lastPathComponent != target.lastPathComponent {
                if !fm.fileExists(atPath: target.path) {
                    if (try? fm.moveItem(at: old, to: target)) != nil { moves.append((old.path, target.path)) }
                } else {
                    moves += storage.mergeFolder(old, into: target)
                    moves.append((old.path, target.path))
                }
            }
        }
        return moves
    }

    /// The folder a drawing or document goes in: its BOQ's or quotation's
    /// series' Drawings / Documents folder when it's linked to one, else
    /// the project's own.
    func linkedFileFolder(projectNumber: String, kind: String?, linkedId: String?, sub: String) -> URL {
        if let kind = kind, let lid = linkedId,
           let number = kind == "BOQ" ? db.getBOQ(id: lid)?.boqNumber : kind == "Quotation" ? db.getQuotation(id: lid)?.quotationNumber : nil,
           let series = db.documentSeries(docTypeTag: kind, number: number) {
            return storage.seriesFolder(projectNumber, series, sub)
        }
        return storage.projectSubfolder(projectNumber, sub)
    }

    /// A drawing's or document's file moved to where its link says (see
    /// linkedFileFolder), if it's somewhere in its project's folder.
    func refileLinkedFile(path: String, projectNumber: String, kind: String?, linkedId: String?, sub: String) -> (String, String)? {
        let fm = FileManager.default
        let file = URL(fileURLWithPath: path).standardizedFileURL
        let projectPath = storage.projectFolder(projectNumber).standardizedFileURL.path
        guard file.path.hasPrefix(projectPath + "/"), fm.fileExists(atPath: file.path) else { return nil }
        let target = linkedFileFolder(projectNumber: projectNumber, kind: kind, linkedId: linkedId, sub: sub).standardizedFileURL
        guard file.deletingLastPathComponent().path != target.path else { return nil }
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        let to = storage.uniqueDestination(target.appendingPathComponent(file.lastPathComponent))
        guard (try? fm.moveItem(at: file, to: to)) != nil else { return nil }
        return (path, to.path)
    }

    /// Every linked drawing and document of a project moved into its
    /// series' folder (and unlinked ones back to the project's).
    func fileLinkedFiles(_ projectNumber: String) -> [(String, String)] {
        guard let project = db.getProjectByNumber(projectNumber) else { return [] }
        var moves: [(String, String)] = []
        for d in db.drawingsForProject(project.id) {
            if let m = refileLinkedFile(path: d.filePath, projectNumber: projectNumber, kind: d.linkedKind, linkedId: d.linkedId, sub: "Drawings") { moves.append(m) }
        }
        for d in db.documentsForProject(project.id) {
            if let m = refileLinkedFile(path: d.filePath, projectNumber: projectNumber, kind: d.linkedKind, linkedId: d.linkedId, sub: "Documents") { moves.append(m) }
        }
        return moves
    }

    /// The project's own folders (Drawings, Documents, Other, Letters…)
    /// aren't kept while they're empty.
    func removeEmptyProjectFolders(_ projectNumber: String) {
        for sub in projectSubfolders + ["Letters"] {
            let folder = storage.projectSubfolder(projectNumber, sub)
            if storage.isEmptyFolder(folder) { try? FileManager.default.removeItem(at: folder) }
        }
    }

    /// Moves the files in a project's "<number> BOQ", "<number> Quotations"…
    /// into their quotation series' folders (fileFolder), and removes those
    /// folders once empty. Returns the moves, for the stored paths.
    func fileDocumentsBySeries(_ projectNumber: String) -> [(String, String)] {
        let fm = FileManager.default
        var moves: [(String, String)] = []
        for sub in NativeBridge.documentKindFolders {
            let folder = storage.projectSubfolder(projectNumber, sub)
            guard let items = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
            for item in items where item != ".DS_Store" {
                // A file not downloaded from iCloud: ".<name>.icloud".
                let placeholder = item.hasPrefix(".") && item.hasSuffix(".icloud")
                guard !item.hasPrefix(".") || placeholder else { continue }
                let name = placeholder ? String(item.dropFirst().dropLast(".icloud".count)) : item
                let target = fileFolder(projectNumber: projectNumber, subfolder: sub, name: name)
                guard target.standardizedFileURL.path != folder.standardizedFileURL.path else { continue }
                let from = folder.appendingPathComponent(item)
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
                let to = storage.uniqueDestination(target.appendingPathComponent(item))
                if (try? fm.moveItem(at: from, to: to)) != nil { moves.append((from.path, to.path)) }
            }
            if ((try? fm.contentsOfDirectory(atPath: folder.path)) ?? []).allSatisfy({ $0 == ".DS_Store" }) { try? fm.removeItem(at: folder) }
        }
        return moves
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let id = body["id"] as? String,
              let action = body["action"] as? String else { return }
        let payload = (body["payload"] as? [String: Any]) ?? [:]
        // What the action changes is noted, so ⌘Z can undo it (UndoJournal).
        // (Requests from browsers, ScaffoldPro Web, aren't: the undo steps
        // are this Mac's own.)
        UndoJournal.shared.begin(action)
        handle(id: id, action: action, payload: payload)
        UndoJournal.shared.end()
    }

    // ---- Kept here: extensions (the other NativeBridge files) can't hold stored properties ----

    /// Replies that go back to a browser over HTTP, by request id.
    var webReplies: [String: (Bool, String?, String?) -> Void] = [:]
    /// Set while a browser's request is being handled: files are made for
    /// downloading instead of opened, and nothing is printed on this Mac.
    var servingWeb = false
    /// A file the browser should open (download) when the reply arrives.
    var webOpenURL: URL?

    /// PDFs made for the preview, by token (until saved or dismissed).
    var pendingPreviews: [String: PendingPreview] = [:]

    let pricedColumns = [
        LetterColumn(title: "No", width: 29.25, kind: .center),
        LetterColumn(title: "Item Description", width: 219.75, kind: .left),
        LetterColumn(title: "Unit Rate", width: 110.25, kind: .money),
        LetterColumn(title: "Qty", width: 39.0, kind: .center),
        LetterColumn(title: "Total Price", width: 108.75, kind: .money),
    ]

    var scheduleTimer: Timer?
    /// When it last tried: after a failure it tries again 15 minutes on,
    /// not only at the next 12:00.
    var lastAttempt: Date?

    /// Set at launch when sharing is on but its folder couldn't be used.
    var teamFolderMissing = false
}

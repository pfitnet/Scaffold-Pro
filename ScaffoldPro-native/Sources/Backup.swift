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
    let db: AppDatabase
    let storage: FileStorage
    let fm = FileManager.default
    /// What the last backup couldn't copy (shown in Settings).
    var lastSkipped: [String] = []

    init(db: AppDatabase, storage: FileStorage) {
        self.db = db
        self.storage = storage
    }

    func timestamp() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd_HHmmss"
        return f.string(from: Date())
    }

    /// Counts files and total bytes under a folder (for the manifest and
    /// the list shown in Settings).
    func folderStats(_ url: URL) -> (files: Int, bytes: Int64) {
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

    func summary(_ folder: URL, _ m: BackupManifest) -> BackupSummary {
        BackupSummary(
            name: folder.lastPathComponent, path: folder.path, createdAt: m.createdAt, kind: m.kind,
            projectCount: m.projectCount, fileCount: m.fileCount, totalBytes: m.totalBytes,
            skippedCount: m.skipped.map { $0.count }
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

            // The files one by one (the project folders may be in a shared
            // iCloud folder): one that can't be copied — e.g. still only in
            // iCloud — is noted and skipped instead of stopping the backup.
            var projectCount = 0
            var skipped: [String] = []
            for (folder, name) in [(storage.projectsRoot, "Projects"), (storage.administrationRoot, "Administration")] where fm.fileExists(atPath: folder.path) {
                let r = CloudBackupManager.mirrorFolder(folder, to: working.appendingPathComponent(name, isDirectory: true), since: nil)
                skipped += r.failed
                if r.waiting > 0 { skipped.append("\(r.waiting) file\(r.waiting == 1 ? "" : "s") in \(name) still only in iCloud (being downloaded)") }
            }
            projectCount = ((try? fm.contentsOfDirectory(atPath: storage.projectsRoot.path)) ?? []).filter { !$0.hasPrefix(".") }.count
            lastSkipped = skipped

            let stats = folderStats(working)
            var manifest = BackupManifest(
                app: "ScaffoldPro", formatVersion: 1, createdAt: nowISO(), kind: kind,
                sourceAppRoot: storage.appRoot.path, projectCount: projectCount,
                fileCount: stats.files, totalBytes: stats.bytes
            )
            manifest.skipped = skipped.isEmpty ? nil : skipped
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

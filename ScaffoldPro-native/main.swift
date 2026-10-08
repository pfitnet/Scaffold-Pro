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

/// A GitHub access token (read-only, for this repository) so updates can be
/// checked and downloaded from a private repository without signing in to
/// git. Kept in a file only this Mac's user can read (not the Keychain,
/// which would ask again after every update, as the app is rebuilt).
enum GitHubToken {
    static var file: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ScaffoldPro", isDirectory: true).appendingPathComponent("github-token")
    }
    static func get() -> String? { (try? String(contentsOf: file, encoding: .utf8)).flatMap { nonBlank($0) } }
    static func set(_ token: String?) {
        guard let t = nonBlank(token) else { try? FileManager.default.removeItem(at: file); return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? Data(t.utf8).write(to: file, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }
}

enum UpdateChecker {
    /// The last check couldn't reach GitHub at all (so "up to date" isn't known).
    static var lastCheckUnknown = false

    /// git options that sign in to GitHub with the saved token, if any.
    static var authArgs: [String] {
        guard let token = GitHubToken.get() else { return ["-c", "credential.interactive=never"] }
        let basic = Data("x-access-token:\(token)".utf8).base64EncodedString()
        return ["-c", "credential.interactive=never", "-c", "http.https://github.com/.extraheader=Authorization: Basic \(basic)"]
    }

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
    static func latestOnGitHub(repoDir: String, branch: String) -> String? {
        guard let remote = git(["remote", "get-url", "origin"], in: repoDir),
              let match = remote.range(of: #"github\.com[:/]([^/]+)/([^/]+?)(\.git)?/?$"#, options: .regularExpression) else { return nil }
        let parts = remote[match].dropFirst("github.com/".count).split(separator: "/").map(String.init)
        guard parts.count >= 2 else { return nil }
        let repo = parts[1].hasSuffix(".git") ? String(parts[1].dropLast(4)) : parts[1]
        guard let url = URL(string: "https://api.github.com/repos/\(parts[0])/\(repo)/commits/\(branch)") else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github.sha", forHTTPHeaderField: "Accept")
        // A private repository needs the token.
        if let token = GitHubToken.get() { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
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
        lastCheckUnknown = false
        let fetched = git(authArgs + ["fetch", "--quiet", "origin"], in: top, timeout: 30) != nil
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
            guard let sha = latestOnGitHub(repoDir: top, branch: branch) else {
                // Neither git nor GitHub's web API could be reached (a
                // private repository needs a token: Settings › Updates).
                lastCheckUnknown = true
                return nil
            }
            if sha != installed, git(["merge-base", "--is-ancestor", sha, installed], in: top) == nil {
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
    weak var host: NSWindow?
    var sheet: NSWindow?
    let titleLabel = NSTextField(labelWithString: "Updating ScaffoldPro")
    let statusLabel = NSTextField(labelWithString: "")
    let detailLabel = NSTextField(wrappingLabelWithString: "")
    let bar = NSProgressIndicator()
    let buttonRow = NSStackView()
    var tapped: ((Int) -> Void)?

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

    @objc func buttonClicked(_ sender: NSButton) { tapped?(sender.tag) }

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
final class WeakScriptHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Borderless, yet able to take clicks and the keyboard (Return / Escape).
final class LaunchWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class LaunchScreen: NSObject, UpdateScreen, WKScriptMessageHandler, WKNavigationDelegate {
    let window: LaunchWindow
    let webView: WKWebView
    var loaded = false
    var pending: [String] = []
    var tapped: ((Int) -> Void)?
    var closing = false
    /// When the screen appeared (the logo's animation takes about 1.8 s).
    var shownAt = Date()

    /// nil when this copy has no launch.html (then the app just opens).
    static func make() -> LaunchScreen? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let page = resources.appendingPathComponent("launch.html")
        guard FileManager.default.fileExists(atPath: page.path) else { return nil }
        return LaunchScreen(page: page, resources: resources)
    }

    init(page: URL, resources: URL) {
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

    func reveal() {
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

    func run(_ script: String) {
        if loaded { webView.evaluateJavaScript(script, completionHandler: nil) } else { pending.append(script) }
    }

    /// A string as a JavaScript literal.
    func js(_ text: String) -> String {
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
    let screen: UpdateScreen
    let installed: String
    let sourceDir: String
    let repoDir: String
    let logURL: URL
    var timer: Timer?
    var compileStarted: Date?
    var waitingForDesktop = false
    var finished = false
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

    func show(_ status: String, _ detail: String, progress: Double?) {
        screen.show(status, detail, progress: progress)
    }

    /// Buttons under the progress, the first the default; each runs its selector.
    func setButtons(_ items: [(String, Selector)]) {
        screen.setButtons(items.map { $0.0 }) { [weak self] index in
            guard let self = self, index < items.count else { return }
            self.perform(items[index].1, with: nil)
        }
    }

    func closeScreen() {
        timer?.invalidate()
        timer = nil
        screen.dismiss()
        onClose?()
    }

    @objc func closeClicked(_ sender: Any?) { closeScreen() }
    @objc func showLogClicked(_ sender: Any?) { NSWorkspace.shared.open(logURL) }
    @objc func openDesktopClicked(_ sender: Any?) { openGitHubDesktop() }
    @objc func cancelClicked(_ sender: Any?) { waitingForDesktop = false; closeScreen() }

    func fail(_ message: String) {
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
            let pulled = UpdateChecker.git(UpdateChecker.authArgs + ["pull", "--ff-only", "--quiet"], in: self.repoDir, timeout: 90) != nil
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
    func localState() -> (head: String, hasNew: Bool) {
        let head = UpdateChecker.git(["rev-parse", "HEAD"], in: repoDir) ?? installed
        let behind = UpdateChecker.git(["rev-list", "--count", "HEAD..@{u}"], in: repoDir).flatMap { Int($0) } ?? 0
        return (head, head != installed && behind == 0)
    }

    var gitHubDesktopURL: URL? { NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.github.GitHubClient") }

    func openGitHubDesktop() {
        guard let app = gitHubDesktopURL else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: repoDir)], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }

    /// Git can't sign in to GitHub by itself: GitHub Desktop brings the new
    /// version, and the screen carries on by itself once it's here.
    func waitForGitHubDesktop() {
        waitingForDesktop = true
        openGitHubDesktop()
        show("Waiting for GitHub Desktop…", "In GitHub Desktop, press “Fetch origin”, then “Pull origin”. The update carries on by itself once the new version is here.", progress: nil)
        setButtons([("Open GitHub Desktop", #selector(openDesktopClicked(_:))), ("Cancel", #selector(cancelClicked(_:)))])
        checkForDesktopPull()
    }

    func checkForDesktopPull() {
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

    var buildTask: Process?
    var buildStarted: Date?
    var slowShown = false

    func build() {
        setButtons([])
        show("Building the new version…", "A minute or two when the app's code changed; seconds when only its pages did. ScaffoldPro closes and opens again by itself when it's done.", progress: 3)
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

    @objc func stopClicked(_ sender: Any?) { buildTask?.terminate() }

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
    static let installScript = """
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
    if ditto --norsrc --noextattr --noacl "$BUILD" "$NEW" && mv "$DEST" "$OLD"; then
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

    func installAndReopen() {
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
    func followLog() {
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
        } else if has("so that build is used") {
            // Only the pages changed: nothing to compile (install.sh's build cache).
            show("Using the last build…", "Only the pages changed, so there's nothing to compile.", progress: 80)
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

final class AppDelegate: NSObject, NSApplicationDelegate, WKUIDelegate, NSWindowDelegate {
    var window: NSWindow!
    var webView: WKWebView!
    var bridge: NativeBridge!
    var db: AppDatabase!
    var storage: FileStorage!
    /// Sharing is on, but this launch uses this Mac's own data.
    var teamFolderMissing = false

    /// The launch screen, while it's up.
    var launchScreen: LaunchScreen?
    var launched = false
    /// Set once the launch screen has decided (update offered, or opened).
    var launchDecided = false

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
                    if let info = info { self.offerOrUpdate(info) }
                    return
                }
                self.afterLaunchAnimation {
                    guard !self.launchDecided else { return }
                    self.launchDecided = true
                    if let info = info, info.installer != nil {
                        self.offerUpdateOnLaunchScreen(info, screen: screen)
                    } else {
                        screen.status(UpdateChecker.lastCheckUnknown ? "Couldn't check for updates" : "Up to date", busy: false)
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
    func afterLaunchAnimation(_ then: @escaping () -> Void) {
        let shown = launchScreen?.shownAt ?? Date()
        let wait = max(0, 1.9 - Date().timeIntervalSince(shown))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: then)
    }

    /// "A new version is available" on the launch screen; Update Now shows
    /// the update's progress right there.
    func offerUpdateOnLaunchScreen(_ info: UpdateInfo, screen: LaunchScreen) {
        var text = info.changes.map { "\($0) change\($0 == 1 ? "" : "s") since this copy was installed." } ?? "GitHub has a newer version than this copy."
        if let latest = nonBlank(info.latest) { text += " Latest: “\(latest)”." }
        screen.setTitle("A new version is available")
        screen.show(text, "Update now: it's downloaded and built here (about a minute), then ScaffoldPro opens again by itself.", progress: nil)
        screen.hideProgress()
        let begin: (Int) -> Void = { [weak self] index in
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
        // Asks first; Update Now does the rest by itself.
        screen.setButtons(["Update Now", "Later"], begin)
    }

    /// Settings › Updates: check for new versions while ScaffoldPro is open
    /// (and offer them, to update with one click).
    static let autoUpdateKey = "updates.automatic"
    static var autoUpdate: Bool {
        get { UserDefaults.standard.object(forKey: autoUpdateKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: autoUpdateKey) }
    }

    var updateTimer: Timer?
    var updatePostponedUntil = Date.distantPast

    /// While ScaffoldPro is open: every 30 minutes, is there a newer
    /// version? If so it asks; "Update Now" saves what's open, makes a
    /// backup, updates and reopens by itself. "Later" asks again in an hour.
    func startUpdateWatch() {
        updateTimer?.invalidate()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 30 * 60, repeats: true) { [weak self] _ in self?.backgroundUpdateCheck() }
    }

    func backgroundUpdateCheck() {
        guard AppDelegate.autoUpdate, UpdateChecker.canCheck, !checkingForUpdates, updater == nil, Date() >= updatePostponedUntil else { return }
        checkingForUpdates = true
        DispatchQueue.global(qos: .utility).async {
            let info = UpdateChecker.check()
            DispatchQueue.main.async {
                self.checkingForUpdates = false
                guard let info = info, let installer = info.installer else { return }
                self.updateAutomatically(info, installer: installer)
            }
        }
    }

    func updateAutomatically(_ info: UpdateInfo, installer: URL) {
        guard updater == nil else { return }
        let latest = nonBlank(info.latest).map { "Latest: “\($0)”." } ?? ""
        let js = "return window.appUpdatePrompt ? await window.appUpdatePrompt(latest) : 'now';"
        let proceed: () -> Void = { [weak self] in
            guard let self = self else { return }
            // A backup first (in the background), then the update.
            DispatchQueue.global(qos: .userInitiated).async {
                _ = try? self.bridge.backups.createBackup(kind: "Before Update")
                DispatchQueue.main.async {
                    self.bridge.db.logActivity(projectId: nil, "Backup made before updating ScaffoldPro")
                    self.startUpdate(fallbackInstaller: installer)
                }
            }
        }
        guard let webView = webView else { proceed(); return }
        webView.callAsyncJavaScript(js, arguments: ["latest": latest], in: nil, in: .page) { [weak self] result in
            if case .success(let value) = result, (value as? String) == "later" {
                self?.updatePostponedUntil = Date().addingTimeInterval(3600)
                return
            }
            proceed()
        }
    }

    /// Opens the main window (the launch screen fading away over it).
    func finishLaunching() {
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
        // Sharing a folder: Documents › ScaffoldPro kept up to date as a local copy.
        bridge.localCopy.start()
        // Settings › Google Sheets: the overview sheet kept in step, both ways.
        bridge.sheets.onChangesTakenIn = { [weak self] in
            self?.bridge.sharedDataChanged(stores: ["projects.json", "activity.json"], names: ["Google Sheets"])
        }
        bridge.sheets.start()
        // A local backup every day at 12:00 a.m. and 12:00 p.m. (kept 3 days).
        bridge.startScheduledBackups()
        // Project folders as "<number> <name>" with "<number> BOQ"… inside
        // (renames older ones once; stored file paths follow).
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in self?.bridge.organiseProjectFolders() }
        // If the last update couldn't be put in place, say why.
        Updater.reportPreviousFailure(in: window)
        // Keep checking for updates while it's open.
        startUpdateWatch()
        launchScreen?.close()
        launchScreen = nil
    }

    // MARK: Updates

    var checkingForUpdates = false

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
                if let info = info { if manual { self.offerUpdate(info) } else { self.offerOrUpdate(info) } }
                else if manual && UpdateChecker.lastCheckUnknown {
                    self.showUpdateAlert("Updates couldn't be checked", "GitHub couldn't be reached from ScaffoldPro. If the Scaffold-Pro repository is private, add a GitHub access token in Settings › Updates (or open the Scaffold-Pro folder in GitHub Desktop and press Fetch origin), then check again.")
                }
                else if manual { self.showUpdateAlert("ScaffoldPro is up to date", "This is the latest version on GitHub (as far as can be checked from this Mac).") }
            }
        }
    }

    var updater: Updater?

    /// Runs the update behind a loading screen; if this copy can't (no
    /// source folder), Install ScaffoldPro runs in Terminal instead.
    func startUpdate(fallbackInstaller: URL) {
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

    /// Asks in the page's own dialog (js/dialogs.js) — the app's look, not
    /// the Mac's alert box. `buttons` run left to right; the last is the
    /// main one, the first (when there are two or more) is Escape's.
    /// Answers the button's index, or nil if the page couldn't show it
    /// (then `fallback` shows the Mac's alert instead).
    func askInPage(_ message: String, buttons: [String], fallback: @escaping () -> Void, answer: @escaping (Int) -> Void) {
        guard let webView = webView else { fallback(); return }
        let js = """
        if (!window.appDialog) throw new Error('no dialogs');
        return await window.appDialog({ message: message, buttons: labels.map((label, i) =>
          ({ label: label, value: i, primary: i === labels.length - 1, cancel: labels.length > 1 ? i === 0 : true })) });
        """
        webView.callAsyncJavaScript(js, arguments: ["message": message, "labels": buttons], in: nil, in: .page) { result in
            switch result {
            case .success(let value): answer((value as? NSNumber)?.intValue ?? 0)
            case .failure: fallback()
            }
        }
    }

    func showUpdateAlert(_ title: String, _ text: String) {
        askInPage("\(title)\n\n\(text)", buttons: ["OK"], fallback: { [weak self] in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = text
            if let window = self?.window { alert.beginSheetModal(for: window) } else { alert.runModal() }
        }, answer: { _ in })
    }

    /// Updating automatically: goes ahead (after saving and a warning);
    /// otherwise asks.
    func offerOrUpdate(_ info: UpdateInfo) {
        if AppDelegate.autoUpdate, let installer = info.installer { updateAutomatically(info, installer: installer) } else { offerUpdate(info) }
    }

    func offerUpdate(_ info: UpdateInfo) {
        let title = "A new version of ScaffoldPro is available"
        var text = info.changes.map { "\($0) change\($0 == 1 ? "" : "s") since this copy was installed." } ?? "GitHub has a newer version than this copy."
        if let latest = nonBlank(info.latest) { text += "\nLatest: “\(latest)”." }
        text += info.installer == nil
            ? "\n\nTo update, run install.sh in the ScaffoldPro-native folder."
            : "\n\nUpdate now? ScaffoldPro closes, Install ScaffoldPro gets the new version and builds it (about a minute), then opens it again."
        let update: () -> Void = {
            guard let installer = info.installer else { return }
            // Updated here, behind a loading screen (Terminal isn't shown).
            // The dialog has to be gone before the loading screen appears.
            DispatchQueue.main.async { self.startUpdate(fallbackInstaller: installer) }
        }
        let buttons = info.installer == nil ? ["OK"] : ["Later", "Update Now"]
        askInPage("\(title)\n\n\(text)", buttons: buttons, fallback: { [weak self] in
            let alert = NSAlert()
            alert.messageText = title
            alert.informativeText = text
            alert.addButton(withTitle: info.installer == nil ? "OK" : "Update Now")
            if info.installer != nil { alert.addButton(withTitle: "Later") }
            let handle: (NSApplication.ModalResponse) -> Void = { response in
                if response == .alertFirstButtonReturn { update() }
            }
            if let window = self?.window { alert.beginSheetModal(for: window, completionHandler: handle) } else { handle(alert.runModal()) }
        }, answer: { index in
            if info.installer != nil && index == 1 { update() }
        })
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// Quitting (⌘Q, the menu, or closing the window) first saves what's
    /// being typed: the box in use is left, as if clicked away from, so its
    /// change is saved. Nothing else (no backup) happens on the way out.
    var savedBeforeQuit = false
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !savedBeforeQuit, webView != nil else { return .terminateNow }
        saveOpenWork { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    /// Asks the page to save what's being typed, then `done` — once, and
    /// within 1.5 seconds even if the page doesn't answer.
    var afterSave: (() -> Void)?
    func saveOpenWork(then done: @escaping () -> Void) {
        savedBeforeQuit = true
        afterSave = done
        let script = "try { var a = document.activeElement; if (a && a.blur) { a.dispatchEvent(new Event('change', { bubbles: true })); a.blur(); } window.dispatchEvent(new Event('beforeunload')); } catch (e) {} true"
        webView?.evaluateJavaScript(script) { [weak self] _, _ in
            // A moment for the save it started to reach the app.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self?.finishSave() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.finishSave() }
    }
    func finishSave() {
        let done = afterSave
        afterSave = nil
        done?()
    }

    /// The red button (or ⌘W) on the main window quits ScaffoldPro. The
    /// window stays until what's being typed is saved — the page is still
    /// awake then — and the app quits straight after.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window else { return true }
        if savedBeforeQuit { NSApp.terminate(nil); return false }
        saveOpenWork { NSApp.terminate(nil) }
        return false
    }

    /// EB Garamond — the documents' body font (as on the company's
    /// quotation) — ships inside the app, in resources/fonts, under the
    /// SIL Open Font License. Registered for this app only.
    func registerBundledFonts() {
        guard let folder = Bundle.main.resourceURL?.appendingPathComponent("resources/fonts", isDirectory: true),
              let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else { return }
        for url in files where ["ttf", "otf"].contains(url.pathExtension.lowercased()) {
            _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    func setupDataLayer() {
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
        db.linkDraftInvoiceTermsToSettingsIfNeeded()
        db.bookStockOnSignedDeliveryNotesOnce()
        db.mergeBankDetailsIntoTermsIfNeeded()
        db.moveBOQMarkupsOntoRates()
        db.addStructuresToQuotationSubjects()
        db.addMissingSPProducts(loadSeed("sp_pricelist.json"))
        db.fillChineseNamesIfNeeded()
    }

    /// Not in a shared folder: the material list is still kept the same on
    /// every Mac, through iCloud Drive (TeamSync.materialFolder).
    /// `brandNew`: the list was only just made from the app's own copy.
    func startMaterialSync(dataDir: URL, brandNew: Bool) {
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

    /// A material list bundled with the app (resources/*.json).
    func loadSeed(_ filename: String) -> [SeedPriceItem] {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("resources/\(filename)"),
              let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([SeedPriceItem].self, from: data)) ?? []
    }

    func seedPriceListsIfNeeded() {
        guard !db.priceListsAreSeeded else { return }

        let spItems = loadSeed("sp_pricelist.json")
        let scafomItems = loadSeed("scafom_pricelist.json")

        if !spItems.isEmpty {
            db.seedPriceList(sourceKey: "SP", displayName: "SP Material & Price List 2026", currency: "HKD", items: spItems)
        }
        if !scafomItems.isEmpty {
            db.seedPriceList(sourceKey: "SCAFOM", displayName: "SCAFOM Material & Price List", currency: "EUR", items: scafomItems)
        }
    }

    func setupWindow() {
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
        // Closing the window quits ScaffoldPro (windowShouldClose, below).
        window.delegate = self

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
        // Moving between pages without a blank (black) flash: see
        // NativeBridge's WKNavigationDelegate.
        webView.navigationDelegate = bridge
        // ScaffoldPro Web: the same pages, for the team's browsers.
        WebServer.shared.bridge = bridge
        WebServer.shared.db = db
        WebServer.shared.applySettings()

        // The page runs up behind the title bar (unified look), so a web
        // view would swallow title-bar drags. A thin native strip on top
        // restores normal title-bar behaviour: drag to move, double-click
        // to zoom. The window buttons sit above it and stay clickable.
        // Behind the page, the page's own background colour: between two
        // pages the window shows that, not an empty (black) web view.
        let container = PageBackdropView(frame: contentRect)
        container.autoresizingMask = [.width, .height]
        webView.setValue(false, forKey: "drawsBackground")
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

        bridge.applyAppearance(bridge.ownAppearance())
        setupMenuBar()

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // MARK: Native dialogs for the pages' alert / confirm / prompt

    /// The pages write messages as "Headline\n\nMore detail" — shown as a
    /// bold title plus explanatory text, like standard Mac alerts.
    func makeAlert(_ message: String) -> NSAlert {
        let alert = NSAlert()
        let parts = message.components(separatedBy: "\n\n")
        alert.messageText = parts.first ?? message
        if parts.count > 1 { alert.informativeText = parts.dropFirst().joined(separator: "\n\n") }
        return alert
    }

    func isDestructive(_ message: String) -> Bool {
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

    func item(_ title: String, _ action: Selector?, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = [.command], page: String? = nil) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = modifiers
        if let page = page { i.representedObject = page }
        return i
    }

    func setupMenuBar() {
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

        // Edit — Undo / Redo go to the page (js/undo.js): typing in a field
        // is undone there; otherwise the last action (UndoJournal). The
        // page takes ⌘Z, ⇧⌘Z, ⌘Y and Ctrl+Z / Ctrl+Y itself first.
        let edit = NSMenu(title: "Edit")
        let undo = NSMenuItem(title: "Undo", action: #selector(appUndo(_:)), keyEquivalent: "z")
        undo.target = self
        edit.addItem(undo)
        let redo = NSMenuItem(title: "Redo", action: #selector(appRedo(_:)), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        redo.target = self
        edit.addItem(redo)
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        addSubmenu(main, "Edit", edit)

        // Go — ⌘1…⌘7 for the sidebar sections (letters are in each project; sites are with clients) (Settings is ⌘,), ⌘[ / ⌘] for back/forward.
        let go = NSMenu(title: "Go")
        let sections: [(String, String)] = [("Dashboard", "index.html"), ("Costs", "price-lists.html"),
                                            ("Clients & Sites", "clients.html"), ("Projects", "projects.html"),
                                            ("Stock", "stock.html"), ("Accounting", "accounts.html"), ("Admin", "admin.html")]
        for (index, entry) in sections.enumerated() {
            let i = item(entry.0, #selector(goToPage(_:)), "\(index + 1)", page: entry.1)
            i.target = self
            go.addItem(i)
        }
        for (title, page) in [("Calendar", "calendar.html"), ("Tasks", "tasks.html"), ("Assistant", "assistant.html"), ("Chat", "chat.html"), ("Team", "team.html"), ("Marketing", "marketing.html")] {
            let extra = item(title, #selector(goToPage(_:)), "", page: page)
            extra.target = self
            go.addItem(extra)
        }
        // The user's own page, pinned at the foot of the sidebar.
        let user = item("You (Settings)", #selector(goToPage(_:)), "0", page: "settings.html#you")
        user.target = self
        go.addItem(user)
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

        // Help — the User Manual (manual.html), ⇧⌘?.
        let help = NSMenu(title: "Help")
        let manual = item("ScaffoldPro User Manual", #selector(goToPage(_:)), "?", page: "manual.html")
        manual.target = self
        help.addItem(manual)
        addSubmenu(main, "Help", help)
        NSApp.helpMenu = help

        NSApp.mainMenu = main
    }

    func addSubmenu(_ main: NSMenu, _ title: String, _ submenu: NSMenu) {
        let holder = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        holder.submenu = submenu
        main.addItem(holder)
    }

    func runJS(_ script: String) {
        window.makeKeyAndOrderFront(nil)
        webView.evaluateJavaScript(script, completionHandler: nil)
    }

    @objc func goToPage(_ sender: NSMenuItem) {
        guard let page = sender.representedObject as? String else { return }
        // (Through the page, so unsaved settings are asked about first.)
        runJS("window.appNavigate ? window.appNavigate('\(page)') : (location.href = '\(page)');")
    }

    @objc func appUndo(_ sender: Any?) {
        runJS("window.appUndo && window.appUndo('undo');")
    }

    @objc func appRedo(_ sender: Any?) {
        runJS("window.appUndo && window.appUndo('redo');")
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
        guard webView.canGoBack else { return }
        runJS("window.appNavigate ? window.appNavigate(function(){ history.back(); }) : history.back();")
    }

    @objc func goForward(_ sender: Any?) {
        guard webView.canGoForward else { return }
        runJS("window.appNavigate ? window.appNavigate(function(){ history.forward(); }) : history.forward();")
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

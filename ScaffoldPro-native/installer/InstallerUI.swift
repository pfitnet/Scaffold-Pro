// Install ScaffoldPro's window. Runs installer/install-steps.sh and shows
// what it reports ("@@" lines): the six steps, a progress bar, GitHub's
// one-time sign-in code with Copy / Open GitHub buttons, and the full
// output under "Show Details". Built by the Install ScaffoldPro app's
// launcher with swiftc the first time (and when this file changes).
//
//   InstallerUI <ScaffoldPro-native folder> [<Install ScaffoldPro.app>]

import Cocoa

final class InstallerController: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let appDir: String
    private let launcherApp: String
    private var window: NSWindow!

    private let titleLabel = NSTextField(labelWithString: "Install ScaffoldPro")
    private let subtitleLabel = NSTextField(labelWithString: "Gets the latest version from GitHub, builds it and puts it in Applications.")
    private let statusLabel = NSTextField(labelWithString: "Starting…")
    private let bar = NSProgressIndicator()
    private let stepNames = ["Homebrew", "GitHub tool (gh)", "Sign in to GitHub", "Get the latest version", "Build ScaffoldPro", "Install and open"]
    private var stepLabels: [NSTextField] = []
    private var stepStates: [String] = Array(repeating: "wait", count: 6)

    private let codeBox = NSBox()
    private let codeLabel = NSTextField(labelWithString: "")
    private var code = ""

    private let logScroll = NSScrollView()
    private let logView = NSTextView()
    private let detailsButton = NSButton(title: "Show Details", target: nil, action: nil)
    private let closeButton = NSButton(title: "Cancel", target: nil, action: nil)
    private let againButton = NSButton(title: "Try Again", target: nil, action: nil)

    private var process: Process?
    private var buffer = Data()
    private var target: Double = 0
    private var creepTo: Double?
    private var ticker: Timer?
    private var finished = false

    init(appDir: String, launcherApp: String) {
        self.appDir = appDir
        self.launcherApp = launcherApp
        super.init()
    }

    // MARK: window

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let icon = NSImage(contentsOfFile: appDir + "/icon/AppIcon.icns") { NSApp.applicationIconImage = icon }
        buildMenu()
        buildWindow()
        NSApp.activate(ignoringOtherApps: true)
        start()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func buildMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit Install ScaffoldPro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func label(_ text: String, size: CGFloat, bold: Bool = false, color: NSColor = .labelColor) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        l.textColor = color
        return l
    }

    private func buildWindow() {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "Install ScaffoldPro"
        window.delegate = self

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.widthAnchor.constraint(equalToConstant: 56).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 56).isActive = true
        titleLabel.font = .boldSystemFont(ofSize: 17)
        subtitleLabel.font = .systemFont(ofSize: 12)
        subtitleLabel.textColor = .secondaryLabelColor
        let heading = NSStackView(views: [titleLabel, subtitleLabel])
        heading.orientation = .vertical
        heading.alignment = .leading
        heading.spacing = 2
        let top = NSStackView(views: [icon, heading])
        top.orientation = .horizontal
        top.alignment = .centerY
        top.spacing = 14

        let steps = NSStackView()
        steps.orientation = .vertical
        steps.alignment = .leading
        steps.spacing = 5
        for name in stepNames {
            let l = label("○  \(name)", size: 13, color: .secondaryLabelColor)
            stepLabels.append(l)
            steps.addArrangedSubview(l)
        }

        bar.style = .bar
        bar.isIndeterminate = false
        bar.minValue = 0
        bar.maxValue = 100
        bar.doubleValue = 0
        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail

        // GitHub's one-time code, while signing in.
        codeLabel.font = .monospacedSystemFont(ofSize: 22, weight: .semibold)
        codeLabel.isSelectable = true
        let codeHint = label("Enter this code on the GitHub page in your browser:", size: 12, color: .secondaryLabelColor)
        let copyButton = NSButton(title: "Copy Code", target: self, action: #selector(copyCode))
        let openButton = NSButton(title: "Open GitHub", target: self, action: #selector(openGitHub))
        let codeRow = NSStackView(views: [codeLabel, copyButton, openButton])
        codeRow.orientation = .horizontal
        codeRow.spacing = 10
        let codeStack = NSStackView(views: [codeHint, codeRow])
        codeStack.orientation = .vertical
        codeStack.alignment = .leading
        codeStack.spacing = 6
        codeBox.boxType = .custom
        codeBox.cornerRadius = 8
        codeBox.borderColor = .separatorColor
        codeBox.fillColor = .controlBackgroundColor
        codeBox.contentViewMargins = NSSize(width: 12, height: 10)
        codeBox.contentView = codeStack
        codeBox.isHidden = true

        logView.frame = NSRect(x: 0, y: 0, width: 490, height: 170)
        logView.minSize = NSSize(width: 0, height: 170)
        logView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        logView.isHorizontallyResizable = false
        logView.isEditable = false
        logView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        logView.textColor = .secondaryLabelColor
        logView.isVerticallyResizable = true
        logView.autoresizingMask = [.width]
        logView.textContainer?.widthTracksTextView = true
        logScroll.documentView = logView
        logScroll.hasVerticalScroller = true
        logScroll.borderType = .bezelBorder
        logScroll.heightAnchor.constraint(equalToConstant: 170).isActive = true
        logScroll.isHidden = true

        detailsButton.target = self
        detailsButton.action = #selector(toggleDetails)
        detailsButton.bezelStyle = .rounded
        againButton.target = self
        againButton.action = #selector(tryAgain)
        againButton.bezelStyle = .rounded
        againButton.isHidden = true
        closeButton.target = self
        closeButton.action = #selector(closeClicked)
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\r"
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [detailsButton, spacer, againButton, closeButton])
        buttons.orientation = .horizontal
        buttons.spacing = 8

        let content = NSStackView(views: [top, steps, bar, statusLabel, codeBox, logScroll, buttons])
        content.orientation = .vertical
        content.alignment = .leading
        content.spacing = 14
        content.edgeInsets = NSEdgeInsets(top: 20, left: 22, bottom: 18, right: 22)
        for v in [bar, statusLabel, codeBox, logScroll, buttons] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        content.translatesAutoresizingMaskIntoConstraints = false
        let root = NSView()
        root.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            content.topAnchor.constraint(equalTo: root.topAnchor),
            content.widthAnchor.constraint(equalToConstant: 540),
            bar.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -44),
            statusLabel.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -44),
            codeBox.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -44),
            logScroll.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -44),
            buttons.widthAnchor.constraint(equalTo: content.widthAnchor, constant: -44),
        ])
        // The bottom follows the content, but gives way while the window is
        // being resized to fit (fitWindow).
        let bottom = content.bottomAnchor.constraint(equalTo: root.bottomAnchor)
        bottom.priority = .defaultHigh
        bottom.isActive = true
        window.contentView = root
        fitWindow()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    /// Sizes the window to its content (which grows when the details or
    /// the sign-in code show), keeping its top edge where it is.
    private func fitWindow() {
        guard let root = window.contentView else { return }
        root.layoutSubtreeIfNeeded()
        let size = NSSize(width: 540, height: max(200, root.fittingSize.height))
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin.x = window.frame.minX
        frame.origin.y = window.frame.maxY - frame.height
        window.setFrame(frame, display: true, animate: window.isVisible)
    }

    // MARK: running the steps

    private func start() {
        finished = false
        target = 0
        creepTo = nil
        bar.doubleValue = 0
        stepStates = Array(repeating: "wait", count: 6)
        for i in 0..<6 { setStep(i + 1, "wait", stepNames[i]) }
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.stringValue = "Starting…"
        againButton.isHidden = true
        closeButton.title = "Cancel"
        codeBox.isHidden = true
        buffer = Data()

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = [appDir + "/installer/install-steps.sh", appDir, launcherApp]
        p.currentDirectoryURL = URL(fileURLWithPath: appDir)
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            // Empty = the end of the output: stop listening (the rest is
            // read when the script exits).
            if data.isEmpty { handle.readabilityHandler = nil; return }
            DispatchQueue.main.async { self?.received(data) }
        }
        p.terminationHandler = { [weak self] proc in
            DispatchQueue.main.async {
                pipe.fileHandleForReading.readabilityHandler = nil
                let rest = pipe.fileHandleForReading.readDataToEndOfFile()
                self?.received(rest)
                self?.received("\n".data(using: .utf8)!)
                self?.ended(status: proc.terminationStatus)
            }
        }
        do {
            try p.run()
            process = p
        } catch {
            fail("The installer couldn't start: \(error.localizedDescription)")
            return
        }
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// Moves the bar smoothly towards where it should be; while compiling
    /// (about a minute) it keeps creeping forward on its own.
    private func tick() {
        if let limit = creepTo, target < limit { target = min(limit, target + 0.06) }
        let now = bar.doubleValue
        if now < target { bar.doubleValue = min(target, now + max(0.4, (target - now) * 0.15)) }
    }

    private func received(_ data: Data) {
        guard !data.isEmpty else { return }
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer.subdata(in: buffer.startIndex..<newline)
            buffer.removeSubrange(buffer.startIndex...newline)
            handle(String(decoding: lineData, as: UTF8.self))
        }
    }

    private func handle(_ line: String) {
        guard line.hasPrefix("@@") else {
            appendLog(line)
            return
        }
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).map(String.init)
        let kind = parts[0]
        let rest = parts.count > 1 ? parts[1] : ""
        switch kind {
        case "@@STEP":
            let bits = rest.split(separator: " ", maxSplits: 2).map(String.init)
            if bits.count >= 2, let n = Int(bits[0]) { setStep(n, bits[1], bits.count > 2 ? bits[2] : stepNames[max(0, min(5, n - 1))]) }
        case "@@PROGRESS":
            if let v = Double(rest) { target = max(target, v); creepTo = nil }
        case "@@CREEP":
            if let v = Double(rest) { creepTo = v }
        case "@@STATUS":
            statusLabel.stringValue = rest
        case "@@CODE":
            code = rest
            codeLabel.stringValue = rest
            codeBox.isHidden = false
            fitWindow()
            _ = NSApp.requestUserAttention(.informationalRequest)
        case "@@CODEDONE":
            codeBox.isHidden = true
            fitWindow()
        case "@@FINISHED":
            let bits = rest.split(separator: " ", maxSplits: 1).map(String.init)
            if bits.first == "ok" {
                succeed(bits.count > 1 ? bits[1] : "Done.")
            } else {
                fail(bits.count > 1 ? bits[1] : "The install didn't finish.")
            }
        default:
            appendLog(line)
        }
    }

    private func setStep(_ n: Int, _ state: String, _ text: String) {
        guard n >= 1, n <= stepLabels.count else { return }
        stepStates[n - 1] = state
        let l = stepLabels[n - 1]
        switch state {
        case "run":
            l.stringValue = "▸  \(text)…"
            l.textColor = .labelColor
            l.font = .boldSystemFont(ofSize: 13)
        case "done":
            l.stringValue = "✓  \(text)"
            l.textColor = .systemGreen
            l.font = .systemFont(ofSize: 13)
        case "skip":
            l.stringValue = "–  \(text)"
            l.textColor = .secondaryLabelColor
            l.font = .systemFont(ofSize: 13)
        case "fail":
            l.stringValue = "✕  \(text)"
            l.textColor = .systemOrange
            l.font = .systemFont(ofSize: 13)
        default:
            l.stringValue = "○  \(text)"
            l.textColor = .secondaryLabelColor
            l.font = .systemFont(ofSize: 13)
        }
    }

    private func appendLog(_ line: String) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.secondaryLabelColor]
        logView.textStorage?.append(NSAttributedString(string: line + "\n", attributes: attrs))
        logView.scrollToEndOfDocument(nil)
    }

    private func succeed(_ message: String) {
        finished = true
        ticker?.invalidate()
        target = 100
        bar.doubleValue = 100
        for i in 0..<stepStates.count where stepStates[i] == "run" { setStep(i + 1, "done", stepNames[i]) }
        codeBox.isHidden = true
        titleLabel.stringValue = "ScaffoldPro is installed"
        statusLabel.textColor = .labelColor
        statusLabel.stringValue = message
        closeButton.title = "Done"
        fitWindow()
    }

    private func fail(_ message: String) {
        finished = true
        ticker?.invalidate()
        for i in 0..<stepStates.count where stepStates[i] == "run" { setStep(i + 1, "fail", stepNames[i]) }
        codeBox.isHidden = true
        titleLabel.stringValue = "The install didn't finish"
        statusLabel.textColor = .systemRed
        statusLabel.stringValue = message
        closeButton.title = "Close"
        againButton.isHidden = false
        if logScroll.isHidden { toggleDetails() }
    }

    /// The script ended: if it didn't say how, it stopped unexpectedly.
    private func ended(status: Int32) {
        process = nil
        guard !finished else { return }
        if status == 0 { succeed("Done.") } else { fail("The installer stopped unexpectedly. Show Details has what happened.") }
    }

    // MARK: buttons

    @objc private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
    }

    @objc private func openGitHub() {
        if let url = URL(string: "https://github.com/login/device") { NSWorkspace.shared.open(url) }
    }

    @objc private func toggleDetails() {
        logScroll.isHidden.toggle()
        detailsButton.title = logScroll.isHidden ? "Show Details" : "Hide Details"
        fitWindow()
    }

    @objc private func tryAgain() {
        titleLabel.stringValue = "Install ScaffoldPro"
        start()
    }

    @objc private func closeClicked() {
        if let p = process, p.isRunning {
            let alert = NSAlert()
            alert.messageText = "Stop installing?"
            alert.informativeText = "ScaffoldPro stays as it was. You can open Install ScaffoldPro again at any time."
            alert.addButton(withTitle: "Stop")
            alert.addButton(withTitle: "Keep Going")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            p.terminate()
        }
        NSApp.terminate(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeClicked()
        return false
    }
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("Usage: InstallerUI <ScaffoldPro-native folder> [<Install ScaffoldPro.app>]\n".data(using: .utf8)!)
    exit(2)
}
let app = NSApplication.shared
app.setActivationPolicy(.regular)
let controller = InstallerController(appDir: arguments[1], launcherApp: arguments.count > 2 ? arguments[2] : "")
app.delegate = controller
app.run()

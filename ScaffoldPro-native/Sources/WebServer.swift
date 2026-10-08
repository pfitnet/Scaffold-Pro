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
// MARK: - ScaffoldPro Web
//
// For the people who don't use a Mac: one Mac in the office keeps
// ScaffoldPro open with Web Access on (Settings › Web Access), and serves
// the very same pages to web browsers on the network — Windows PCs,
// iPads, phones. Each person signs in with their name and the office
// password; what they do goes through this Mac exactly as if they'd done
// it here (as them), so it lands in the shared iCloud folder with
// everything else. It's always the same version as this Mac, because
// it's this Mac's own copy of the pages.
// =====================================================================

struct WebSession: Codable {
    var token: String
    var name: String
    var agent: String
    var createdAt: String
    var lastSeen: String
}

struct WebStatus: Codable {
    var enabled: Bool
    var running: Bool
    var port: Int
    var hasPassword: Bool
    var urls: [String]
    var sessions: [WebSession]
    var error: String?
}

/// The fast lane between Macs sharing a folder on the same network: each
/// change is also sent straight to the others, so it shows on their screens
/// in a second instead of waiting for iCloud Drive (which can take from
/// seconds to minutes). iCloud Drive stays the record; this only gets there
/// first, and a Mac on another network simply waits for iCloud as before.
/// Messages are signed with a key made from the shared folder's marker file,
/// so only Macs in the same shared folder are listened to.
/// A big word ("DRAFT") laid diagonally across every page of a PDF, corner
/// to corner, light enough to read the page through.
enum PDFWatermark {
    static func stamp(_ data: Data, text: String) -> Data {
        guard let provider = CGDataProvider(data: data as CFData), let source = CGPDFDocument(provider), source.numberOfPages > 0,
              let first = source.page(at: 1) else { return data }
        let out = NSMutableData()
        var firstBox = first.getBoxRect(.mediaBox)
        guard let consumer = CGDataConsumer(data: out as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &firstBox, nil) else { return data }
        for index in 1...source.numberOfPages {
            guard let page = source.page(at: index) else { continue }
            var box = page.getBoxRect(.mediaBox)
            let boxData = Data(bytes: &box, count: MemoryLayout<CGRect>.size)
            context.beginPDFPage([kCGPDFContextMediaBox as String: boxData] as CFDictionary)
            context.drawPDFPage(page)
            draw(text, in: box, on: context)
            context.endPDFPage()
        }
        context.closePDF()
        return out.length > 0 ? out as Data : data
    }

    static func draw(_ text: String, in box: CGRect, on context: CGContext) {
        let diagonal = (box.width * box.width + box.height * box.height).squareRoot()
        // Sized to run about three quarters of the way along the diagonal.
        let probe = CTFontCreateWithName("Helvetica-Bold" as CFString, 100, nil)
        let probeLine = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [kCTFontAttributeName as NSAttributedString.Key: probe]))
        let probeWidth = max(1, CTLineGetBoundsWithOptions(probeLine, .useGlyphPathBounds).width)
        let size = min(220, 100 * diagonal * 0.72 / probeWidth)
        let font = CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil)
        let colour = CGColor(red: 0.55, green: 0.55, blue: 0.58, alpha: 0.16)
        let attributes: [NSAttributedString.Key: Any] = [kCTFontAttributeName as NSAttributedString.Key: font,
                                                         kCTForegroundColorAttributeName as NSAttributedString.Key: colour,
                                                         kCTKernAttributeName as NSAttributedString.Key: size * 0.08]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let bounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        context.saveGState()
        context.translateBy(x: box.midX, y: box.midY)
        context.rotate(by: atan2(box.height, box.width))
        context.textPosition = CGPoint(x: -bounds.width / 2 - bounds.minX, y: -bounds.height / 2 - bounds.minY)
        CTLineDraw(line, context)
        context.restoreGState()
    }
}

final class TeamLink {
    static let shared = TeamLink()
    var listener: NWListener?
    var port: Int?
    var addresses: [String] = []
    var key: SymmetricKey?
    var peers: [(host: String, port: Int)] = []
    var peersAt = Date.distantPast
    var addressTimer: Timer?
    let sendQueue = DispatchQueue(label: "ScaffoldPro.teamLink")

    func start(root: URL) {
        guard listener == nil else { return }
        guard let marker = try? Data(contentsOf: root.appendingPathComponent(TeamSync.markerName)), !marker.isEmpty else { return }
        key = SymmetricKey(data: Data(SHA256.hash(data: Data("ScaffoldPro link|".utf8) + marker)))
        do {
            let l = try NWListener(using: .tcp)
            l.newConnectionHandler = { [weak self] connection in self?.receive(connection) }
            l.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.port = l.port.map { Int($0.rawValue) }
                    self.findAddresses()
                case .failed(_):
                    self.listener = nil
                    self.port = nil
                default:
                    break
                }
            }
            l.start(queue: .main)
            listener = l
            // A new address (another Wi-Fi, a new lease) is picked up.
            addressTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in self?.findAddresses() }
        } catch {
            listener = nil
        }
    }

    func findAddresses() {
        DispatchQueue.global(qos: .utility).async {
            let found = Host.current().addresses.filter { $0.contains(".") && !$0.hasPrefix("127.") && !$0.hasPrefix("169.254.") }
            DispatchQueue.main.async {
                guard found != self.addresses else { return }
                self.addresses = found
                TeamSync.current?.announceLink()
            }
        }
    }

    /// The other Macs that are open and can be reached this way.
    func currentPeers() -> [(host: String, port: Int)] {
        if Date().timeIntervalSince(peersAt) > 20, let sync = TeamSync.current {
            peers = sync.members()
                .filter { m in
                    m.isThisMac != true && (m.linkPort ?? 0) > 0
                        && (parseISODate(m.lastSeen).map { Date().timeIntervalSince($0) < 20 * 60 } ?? false)
                }
                .flatMap { m in (m.linkAddresses ?? []).map { (host: $0, port: m.linkPort ?? 0) } }
            peersAt = Date()
        }
        return peers
    }

    func sign(_ body: Data, _ key: SymmetricKey) -> String {
        HMAC<SHA256>.authenticationCode(for: body, using: key).map { String(format: "%02x", $0) }.joined()
    }

    /// Sends this Mac's change to a store to the others.
    func send(device: String, store: String, records: [String: Any]) {
        guard let key = key, listener != nil, !records.isEmpty else { return }
        let targets = currentPeers()
        guard !targets.isEmpty else { return }
        let message: [String: Any] = ["device": device, "store": store, "records": records]
        guard let body = try? JSONSerialization.data(withJSONObject: message) else { return }
        let envelope: [String: Any] = ["body": body.base64EncodedString(), "mac": sign(body, key)]
        guard let packet = try? JSONSerialization.data(withJSONObject: envelope) else { return }
        for target in targets {
            guard let port = NWEndpoint.Port(rawValue: UInt16(clamping: target.port)) else { continue }
            let connection = NWConnection(host: NWEndpoint.Host(target.host), port: port, using: .tcp)
            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.send(content: packet, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in connection.cancel() })
                case .failed(_), .waiting(_):
                    connection.cancel()
                default:
                    break
                }
            }
            connection.start(queue: sendQueue)
            sendQueue.asyncAfter(deadline: .now() + 6) { connection.cancel() }
        }
    }

    func receive(_ connection: NWConnection) {
        connection.start(queue: .main)
        read(connection, Data())
    }

    func read(_ connection: NWConnection, _ sofar: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            var buffer = sofar
            if let data = data { buffer.append(data) }
            if buffer.count > 32 << 20 { connection.cancel(); return }
            if isComplete || error != nil {
                connection.cancel()
                self?.handle(buffer)
                return
            }
            self?.read(connection, buffer)
        }
    }

    func handle(_ data: Data) {
        guard let key = key,
              let envelope = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let encoded = envelope["body"] as? String, let body = Data(base64Encoded: encoded),
              let mac = envelope["mac"] as? String, mac == sign(body, key),
              let message = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any],
              let device = message["device"] as? String, let store = message["store"] as? String,
              let records = message["records"] as? [String: Any] else { return }
        TeamSync.current?.receivePushed(device: device, store: store, records: records)
    }
}

final class WebServer {
    static let shared = WebServer()
    weak var bridge: NativeBridge?
    weak var db: AppDatabase?

    var listener: NWListener?
    var lastError: String?
    var sleepActivity: NSObjectProtocol?

    static let enabledKey = "web.enabled"
    static let portKey = "web.port"
    static let passwordKey = "web.passwordHash"
    static let sessionsKey = "web.sessions"

    var enabled: Bool {
        get { UserDefaults.standard.bool(forKey: WebServer.enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: WebServer.enabledKey) }
    }
    var port: Int {
        get { let p = UserDefaults.standard.integer(forKey: WebServer.portKey); return (1024...65535).contains(p) ? p : 8642 }
        set { UserDefaults.standard.set(newValue, forKey: WebServer.portKey) }
    }
    var hasPassword: Bool { UserDefaults.standard.string(forKey: WebServer.passwordKey) != nil }

    static func hash(_ password: String) -> String {
        let digest = SHA256.hash(data: Data(("ScaffoldPro Web|" + password).utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
    func setPassword(_ password: String) {
        UserDefaults.standard.set(WebServer.hash(password), forKey: WebServer.passwordKey)
        // A new password signs everyone out.
        sessions = [:]
    }
    func passwordMatches(_ password: String) -> Bool {
        guard let saved = UserDefaults.standard.string(forKey: WebServer.passwordKey) else { return false }
        return saved == WebServer.hash(password)
    }

    // MARK: sessions (kept, so a restart doesn't sign everyone out)

    var sessions: [String: WebSession] {
        get {
            guard let data = UserDefaults.standard.data(forKey: WebServer.sessionsKey),
                  let list = try? JSONDecoder().decode([WebSession].self, from: data) else { return [:] }
            return Dictionary(list.map { ($0.token, $0) }, uniquingKeysWith: { a, _ in a })
        }
        set {
            if let data = try? JSONEncoder().encode(Array(newValue.values)) { UserDefaults.standard.set(data, forKey: WebServer.sessionsKey) }
        }
    }

    func session(for request: HTTPRequest) -> WebSession? {
        guard let token = request.cookie("sp_session"), var s = sessions[token] else { return nil }
        // Signed out after 30 days without use.
        if let seen = parseISODate(s.lastSeen), Date().timeIntervalSince(seen) > 30 * 86400 { endSession(token); return nil }
        if let seen = parseISODate(s.lastSeen), Date().timeIntervalSince(seen) < 60 { return s }
        s.lastSeen = nowISO()
        var all = sessions
        all[token] = s
        sessions = all
        TeamSync.current?.touchWebMember(name: s.name, token: token, agent: s.agent)
        return s
    }

    /// Signs out the session(s) whose token starts like this (the status
    /// only shows the start of each); "" signs everyone out.
    func endSessions(startingWith prefix: String) {
        var all = sessions
        for token in all.keys where prefix.isEmpty || token.hasPrefix(prefix) { all.removeValue(forKey: token) }
        sessions = all
    }

    func endSession(_ token: String) {
        var all = sessions
        all.removeValue(forKey: token)
        sessions = all
    }

    // MARK: starting and stopping

    func applySettings() {
        stop()
        guard enabled else { return }
        guard hasPassword else { lastError = "Set a password first."; return }
        start()
    }

    func start() {
        lastError = nil
        guard let nwPort = NWEndpoint.Port(rawValue: UInt16(port)) else { lastError = "That port can’t be used."; return }
        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let l = try NWListener(using: parameters, on: nwPort)
            l.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                self?.read(connection, Data())
            }
            l.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.lastError = "Web Access stopped: \(error.localizedDescription)"
                    self?.listener = nil
                }
            }
            l.start(queue: .main)
            listener = l
            // The Mac mustn't fall asleep while it's serving the others.
            sleepActivity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "Serving ScaffoldPro Web")
        } catch {
            lastError = "Web Access couldn’t start on port \(port): \(error.localizedDescription)"
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        if let a = sleepActivity { ProcessInfo.processInfo.endActivity(a); sleepActivity = nil }
    }

    /// The addresses to type in a browser on the same network.
    func addresses() -> [String] {
        var urls: [String] = []
        let host = ProcessInfo.processInfo.hostName
        if !host.isEmpty { urls.append("http://\(host.hasSuffix(".local") ? host : host + ".local"):\(port)") }
        for a in Host.current().addresses where a.contains(".") && !a.hasPrefix("127.") && !a.hasPrefix("169.254.") {
            urls.append("http://\(a):\(port)")
        }
        return urls
    }

    func status() -> WebStatus {
        WebStatus(enabled: enabled, running: listener != nil, port: port, hasPassword: hasPassword, urls: addresses(),
                  sessions: sessions.values.sorted { $0.lastSeen > $1.lastSeen }.map { (one: WebSession) -> WebSession in var s = one; s.token = String(one.token.prefix(8)); return s },
                  error: lastError)
    }

    /// Everyone using it from a browser lately (for the Team page).
    func recentPeople() -> [WebSession] {
        return sessions.values.filter { parseISODate($0.lastSeen).map { Date().timeIntervalSince($0) < 14 * 86400 } ?? false }
    }

    // MARK: HTTP

    func read(_ connection: NWConnection, _ buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, isComplete, error in
            guard let self = self else { connection.cancel(); return }
            var buf = buffer
            if let d = data { buf.append(d) }
            if let request = HTTPRequest.parse(buf) {
                self.route(request, connection)
                return
            }
            if buf.count > 40_000_000 || isComplete || error != nil { connection.cancel(); return }
            self.read(connection, buf)
        }
    }

    func send(_ connection: NWConnection, status: String = "200 OK", type: String, body: Data, headers: [String: String] = [:]) {
        var head = "HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(body.count)\r\nConnection: close\r\nX-Content-Type-Options: nosniff\r\n"
        if headers["Cache-Control"] == nil { head += "Cache-Control: no-store\r\n" }
        for (k, v) in headers { head += "\(k): \(v)\r\n" }
        head += "\r\n"
        var data = Data(head.utf8)
        data.append(body)
        connection.send(content: data, completion: .contentProcessed { _ in connection.cancel() })
    }

    func sendJSON(_ connection: NWConnection, _ json: String, status: String = "200 OK", headers: [String: String] = [:]) {
        send(connection, status: status, type: "application/json; charset=utf-8", body: Data(json.utf8), headers: headers)
    }

    func redirect(_ connection: NWConnection, to location: String) {
        send(connection, status: "302 Found", type: "text/plain", body: Data(), headers: ["Location": location])
    }

    static func jsonString(_ s: String?) -> String {
        guard let s = s, let data = try? JSONEncoder().encode(s), let out = String(data: data, encoding: .utf8) else { return "null" }
        return out
    }

    func route(_ request: HTTPRequest, _ connection: NWConnection) {
        let path = request.path
        switch (request.method, path) {
        case ("GET", "/login"):
            send(connection, type: "text/html; charset=utf-8", body: Data(loginPage().utf8))
        case ("POST", "/api/login"):
            let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any] ?? [:]
            let name = ((body["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, name.count <= 60 else { sendJSON(connection, #"{"ok":false,"error":"Enter your name."}"#); return }
            guard passwordMatches((body["password"] as? String) ?? "") else {
                // A little slower each wrong guess.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    self.sendJSON(connection, #"{"ok":false,"error":"That password isn’t right."}"#, status: "401 Unauthorized")
                }
                return
            }
            let token = UUID().uuidString + UUID().uuidString
            var all = sessions
            all[token] = WebSession(token: token, name: name, agent: WebServer.describe(agent: request.headers["user-agent"] ?? ""), createdAt: nowISO(), lastSeen: nowISO())
            sessions = all
            sendJSON(connection, #"{"ok":true}"#, headers: ["Set-Cookie": "sp_session=\(token); Path=/; HttpOnly; SameSite=Lax; Max-Age=2592000"])
        case ("POST", "/api/logout"):
            if let token = request.cookie("sp_session") { endSession(token) }
            sendJSON(connection, #"{"ok":true}"#, headers: ["Set-Cookie": "sp_session=; Path=/; Max-Age=0"])
        case ("GET", "/__web/shim.js"):
            send(connection, type: "text/javascript; charset=utf-8", body: Data(WebServer.shim.utf8))
        default:
            // Everything else needs signing in (the login page's stylesheet aside).
            let open = path == "/css/styles.css" || path.hasPrefix("/resources/fonts/") || path.hasPrefix("/icon/")
            guard let session = session(for: request) else {
                if path.hasPrefix("/api/") { sendJSON(connection, #"{"ok":false,"error":"signed-out"}"#, status: "401 Unauthorized"); return }
                if !open { redirect(connection, to: "/login"); return }
                serveStatic(path, connection)
                return
            }
            if request.method == "POST" && path == "/api/call" {
                call(request, session, connection)
            } else if request.method == "GET" && path == "/api/download" {
                download(request.query["path"] ?? "", connection)
            } else if request.method == "GET" && path == "/api/me" {
                sendJSON(connection, "{\"name\":\(WebServer.jsonString(session.name))}")
            } else if request.method == "GET" {
                serveStatic(path == "/" ? "/index.html" : path, connection)
            } else {
                send(connection, status: "405 Method Not Allowed", type: "text/plain", body: Data())
            }
        }
    }

    /// A page's request, handled as the signed-in person.
    func call(_ request: HTTPRequest, _ session: WebSession, _ connection: NWConnection) {
        guard let bridge = bridge,
              let body = (try? JSONSerialization.jsonObject(with: request.body)) as? [String: Any],
              let action = body["action"] as? String else {
            sendJSON(connection, #"{"ok":false,"error":"Bad request."}"#, status: "400 Bad Request")
            return
        }
        if NativeBridge.macOnly(action) {
            sendJSON(connection, "{\"ok\":false,\"error\":\(WebServer.jsonString("That needs the Mac app — choosing files and folders, backups and setup aren’t in the web version yet."))}")
            return
        }
        let payload = (body["payload"] as? [String: Any]) ?? [:]
        let id = "web-" + UUID().uuidString
        var openURL: URL?
        var answered = false
        bridge.webReplies[id] = { ok, result, error in
            answered = true
            let open = openURL.map { "/api/download?path=" + ($0.path.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&=+"))) ?? "") }
            self.sendJSON(connection, "{\"ok\":\(ok ? "true" : "false"),\"result\":\(result ?? "null"),\"error\":\(WebServer.jsonString(error)),\"open\":\(WebServer.jsonString(open))}")
        }
        bridge.webOpenURL = nil
        bridge.handleWeb(id: id, action: action, payload: payload, person: session.name)
        openURL = bridge.webOpenURL
        bridge.webOpenURL = nil
        // Long jobs (a big PDF) get two minutes.
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak bridge] in
            guard !answered, bridge?.webReplies.removeValue(forKey: id) != nil else { return }
            self.sendJSON(connection, #"{"ok":false,"error":"That took too long."}"#, status: "504 Gateway Timeout")
        }
    }

    /// A file made for (or opened by) someone in a browser: only from the
    /// project folders or the shared data, never anywhere else on this Mac.
    func download(_ rawPath: String, _ connection: NWConnection) {
        let url = URL(fileURLWithPath: rawPath).standardizedFileURL.resolvingSymlinksInPath()
        let allowed = [bridge?.storage.appRoot, db?.dataDir, TeamSync.current?.root].compactMap { $0?.standardizedFileURL.resolvingSymlinksInPath().path }
        guard allowed.contains(where: { url.path.hasPrefix($0 + "/") }), let data = try? Data(contentsOf: url) else {
            send(connection, status: "404 Not Found", type: "text/plain; charset=utf-8", body: Data("Not found.".utf8))
            return
        }
        let name = url.lastPathComponent.replacingOccurrences(of: "\"", with: "")
        let encoded = name.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "file"
        send(connection, type: WebServer.contentType(url.pathExtension), body: data,
             headers: ["Content-Disposition": "inline; filename*=UTF-8''\(encoded)"])
    }

    func serveStatic(_ rawPath: String, _ connection: NWConnection) {
        guard let root = Bundle.main.resourceURL?.standardizedFileURL else { send(connection, status: "500 Internal Server Error", type: "text/plain", body: Data()); return }
        let url = root.appendingPathComponent(String(rawPath.drop(while: { $0 == "/" }))).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/"), var data = try? Data(contentsOf: url) else {
            send(connection, status: "404 Not Found", type: "text/plain; charset=utf-8", body: Data("Not found.".utf8))
            return
        }
        let ext = url.pathExtension.lowercased()
        if ext == "html", var html = String(data: data, encoding: .utf8) {
            // The bridge the Mac window injects, here as script tags.
            // First, the loading screen (js/web-loading.js), shown while the
            // page and its data come over the network.
            let inject = #"<script src="/js/web-loading.js"></script><script>document.documentElement.classList.add('web')</script><script src="/__web/shim.js"></script><script src="/js/bridge.js"></script>"#
            if let r = html.range(of: "<head>") { html.insert(contentsOf: inject, at: r.upperBound) } else { html = inject + html }
            data = Data(html.utf8)
        }
        send(connection, type: WebServer.contentType(ext), body: data, headers: ["Cache-Control": ext == "html" ? "no-store" : "no-cache"])
    }

    static func contentType(_ ext: String) -> String {
        switch ext.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "js": return "text/javascript; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "svg": return "image/svg+xml"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "ttf": return "font/ttf"
        case "otf": return "font/otf"
        case "woff2": return "font/woff2"
        case "pdf": return "application/pdf"
        case "docx": return "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
        case "xlsx": return "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
        case "csv": return "text/csv; charset=utf-8"
        case "dwg": return "application/acad"
        case "txt": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }

    static func describe(agent: String) -> String {
        let os = agent.contains("Windows") ? "Windows" : agent.contains("iPhone") ? "iPhone" : agent.contains("iPad") ? "iPad"
            : agent.contains("Android") ? "Android" : agent.contains("Mac OS X") ? "Mac" : agent.contains("Linux") ? "Linux" : "Browser"
        let browser = agent.contains("Edg/") ? "Edge" : agent.contains("Chrome/") ? "Chrome" : agent.contains("Firefox/") ? "Firefox" : agent.contains("Safari/") ? "Safari" : ""
        return browser.isEmpty ? os : "\(browser) on \(os)"
    }

    func loginPage() -> String {
        let names = (db?.teamPage().people.map { $0.name } ?? []).map { "<option value=\"\(htmlEscape($0))\"></option>" }.joined()
        return """
        <!DOCTYPE html><html><head><meta charset="UTF-8"><meta name="viewport" content="width=device-width, initial-scale=1">
        <title>Sign in — ScaffoldPro</title><link rel="stylesheet" href="/css/styles.css">
        <style>
          body { display: flex; align-items: center; justify-content: center; min-height: 100vh; background: var(--bg); }
          .login { width: 360px; max-width: calc(100vw - 32px); background: var(--panel); border: 1px solid var(--border); border-radius: 16px; padding: 28px 26px 24px; box-shadow: var(--shadow-sheet); }
          .login h1 { font-size: 20px; margin: 10px 0 4px; } .login p { color: var(--text-secondary); margin: 0 0 18px; font-size: 13px; }
          .login .field { display: flex; flex-direction: column; gap: 6px; margin-bottom: 14px; } .login input { width: 100%; height: 36px; }
          .login button { width: 100%; height: 38px; font-size: 14px; } .mark { width: 44px; height: 44px; border-radius: 11px; background: #1B3556; display: flex; align-items: center; justify-content: center; color: #F4B400; font-weight: 800; font-size: 20px; }
          .err { color: var(--danger); font-size: 13px; min-height: 18px; margin-bottom: 8px; }
        </style></head><body>
        <form class="login" id="f"><div class="mark">S</div><h1>ScaffoldPro</h1><p>Sign in to work with the team. Everything you do is saved to the shared folder, just like on the Macs.</p>
          <div class="field"><label for="n">Your name</label><input id="n" list="people" autocomplete="username" required placeholder="As on the Team page"><datalist id="people">\(names)</datalist></div>
          <div class="field"><label for="p">Office password</label><input id="p" type="password" autocomplete="current-password" required></div>
          <div class="err" id="e"></div><button class="primary" type="submit">Sign In</button></form>
        <script>
          const n = document.getElementById('n'); try { n.value = localStorage.getItem('web.name') || ''; } catch (e) {}
          document.getElementById('f').addEventListener('submit', async (ev) => {
            ev.preventDefault();
            const r = await fetch('/api/login', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ name: n.value, password: document.getElementById('p').value }) });
            const b = await r.json().catch(() => ({}));
            if (b.ok) { try { localStorage.setItem('web.name', n.value); } catch (e) {} location.href = '/index.html'; }
            else document.getElementById('e').textContent = b.error || 'Couldn’t sign in.';
          });
        </script></body></html>
        """
    }

    func htmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// In a browser, the pages talk to this Mac over HTTP instead of
    /// window.webkit: the same messages, the same replies.
    static let shim = """
    (function () {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.native) return;
      window.__scaffoldProWeb = true;
      async function post(m) {
        let ok = false, result = null, error = null, open = null;
        try {
          const r = await fetch('/api/call', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ action: m.action, payload: m.payload || {} }) });
          if (r.status === 401) { location.href = '/login'; return; }
          const b = await r.json();
          ok = !!b.ok; result = b.result === undefined ? null : b.result; error = b.error || null; open = b.open || null;
        } catch (e) {
          error = 'The office Mac can’t be reached. Check it’s on, with ScaffoldPro open.';
        }
        if (open) {
          // A slow file may be past the browser's pop-up allowance: then a note to click.
          const w = window.open(open, '_blank');
          if (!w) {
            const n = document.createElement('a');
            n.href = open; n.target = '_blank'; n.className = 'web-file-ready';
            n.textContent = 'Your file is ready — click to open it';
            n.addEventListener('click', () => setTimeout(() => n.remove(), 100));
            document.body.appendChild(n);
            setTimeout(() => n.remove(), 20000);
          }
        }
        if (ok) window.__nativeCallback(m.id, true, JSON.stringify(result), null);
        else window.__nativeCallback(m.id, false, null, error || 'Something went wrong.');
      }
      window.webkit = { messageHandlers: { native: { postMessage: (m) => { post(m); } } } };
      window.scaffoldProSignOut = async () => { await fetch('/api/logout', { method: 'POST' }); location.href = '/login'; };
    })();
    """
}

/// One HTTP request, once it has all arrived.
struct HTTPRequest {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data

    func cookie(_ name: String) -> String? {
        guard let raw = headers["cookie"] else { return nil }
        for part in raw.split(separator: ";") {
            let kv = part.trimmingCharacters(in: .whitespaces).split(separator: "=", maxSplits: 1).map { String($0) }
            if kv.count == 2 && kv[0] == name { return kv[1] }
        }
        return nil
    }

    static func parse(_ data: Data) -> HTTPRequest? {
        let separator = Data("\r\n\r\n".utf8)
        guard let end = data.range(of: separator), let head = String(data: data[..<end.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        guard !lines.isEmpty else { return nil }
        let first = lines.removeFirst().components(separatedBy: " ")
        guard first.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = end.upperBound
        guard data.count - bodyStart >= length else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + length))
        let target = first[1]
        let pieces = target.split(separator: "?", maxSplits: 1).map { String($0) }
        let path = (pieces.first ?? "/").removingPercentEncoding ?? "/"
        var query: [String: String] = [:]
        if pieces.count > 1 {
            for pair in pieces[1].split(separator: "&") {
                let kv = pair.split(separator: "=", maxSplits: 1).map { String($0) }
                let k = kv[0].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? kv[0]
                let v = kv.count > 1 ? (kv[1].replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? kv[1]) : ""
                query[k] = v
            }
        }
        return HTTPRequest(method: first[0].uppercased(), path: path, query: query, headers: headers, body: body)
    }
}

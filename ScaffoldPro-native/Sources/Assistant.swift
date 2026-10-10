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
// MARK: - Moving between pages without a flash
// =====================================================================

/// The window's content view: filled with the pages' background colour
/// (css/styles.css --content), light or dark with the appearance.
final class PageBackdropView: NSView {
    static let color = NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0x10 / 255, green: 0x11 / 255, blue: 0x15 / 255, alpha: 1)
            : NSColor(srgbRed: 0xf4 / 255, green: 0xf5 / 255, blue: 0xf8 / 255, alpha: 1)
    }
    override func draw(_ dirtyRect: NSRect) {
        PageBackdropView.color.setFill()
        dirtyRect.fill()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }
}

/// Moving between pages (and window.softReload): a picture of the page being
/// left stays over the window until the next page is fully built — its data
/// in and drawn — and then gives way to it in one step. The page says when
/// (ui:releaseFrame, js/bridge.js); failing that, a moment after it has
/// loaded. So the half-built page (sidebar and lists still filling in) is
/// never seen. Behind it all, the pages' own background colour
/// (PageBackdropView), never a dark empty web view.
extension NativeBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        let toThisWindow = navigationAction.targetFrame?.isMainFrame ?? false
        let from = webView.url, to = navigationAction.request.url
        // Only a jump within the same page (#section): nothing to cover.
        let samePage = from != nil && to != nil && from!.path == to!.path && from!.query == to!.query
            && to!.fragment != nil && navigationAction.navigationType != .reload
        guard toThisWindow, !samePage, !holdingFrame, from?.isFileURL == true, to?.isFileURL == true else {
            decisionHandler(.allow)
            return
        }
        // The picture already on screen: taken at once (holdFrame never
        // waits more than 0.12 s for it), then the page change goes ahead.
        holdFrame { decisionHandler(.allow) }
    }

    /// A new page swaps the web view's mouse tracking under the title bar:
    /// the window's close / minimise / full-screen buttons then lose track of
    /// the pointer until it leaves and comes back. Re-armed after each page.
    func refreshTitlebarButtons() {
        guard let window = window else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window.standardWindowButton($0) }
        for b in buttons {
            b.superview?.updateTrackingAreas()
            b.updateTrackingAreas()
        }
        window.invalidateCursorRects(for: window.contentView ?? NSView())
        // Tell them where the pointer is now, as if it had just moved.
        let point = window.mouseLocationOutsideOfEventStream
        if let moved = NSEvent.mouseEvent(with: .mouseMoved, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0) {
            window.sendEvent(moved)
        }
        buttons.first?.superview?.needsDisplay = true
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        DispatchQueue.main.async { [weak self] in self?.refreshTitlebarButtons() }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        refreshTitlebarButtons()
        // Normally the page has said it's built by now; a slow one is shown anyway.
        // Only the picture held for this page: not one held since for the next.
        let held = heldFrame
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self, weak held] in
            if let held = held, self?.heldFrame === held { self?.releaseFrame() }
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { releaseFrame() }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { releaseFrame() }
}

// =====================================================================
// MARK: - The assistant (assistant.html): a chat with the team's AI that
// can look things up and propose work (a quotation, items, a task)
// =====================================================================

extension QuotationAI {
    /// A file shown to the AI as it is (a PDF or a picture).
    struct ChatFile { var mime: String; var data: Data }
    /// One message of a conversation: "user" or "assistant".
    struct ChatTurn { var role: String; var text: String; var files: [ChatFile] = [] }

    /// Sends a conversation; the AI's answer (its text), or why not (main thread).
    /// `json`: Gemini is told to answer with JSON (the assistant); false for
    /// plain text (a summary).
    func chat(system: String, turns: [ChatTurn], json: Bool = true, completion: @escaping (String?, String?) -> Void) {
        adoptThisMacsKey()
        guard let key = sharedKey else { completion(nil, "No AI is set up yet. Add a key in Settings › AI Import."); return }
        var request: URLRequest
        if provider == "openrouter" {
            request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!, timeoutInterval: 75)
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            request.setValue("ScaffoldPro", forHTTPHeaderField: "X-Title")
            var messages: [[String: Any]] = [["role": "system", "content": system]]
            for t in turns {
                var content: [[String: Any]] = [["type": "text", "text": t.text]]
                for f in t.files where f.mime.hasPrefix("image/") {
                    let image: [String: Any] = ["url": "data:\(f.mime);base64,\(f.data.base64EncodedString())"]
                    content.append(["type": "image_url", "image_url": image])
                }
                messages.append(["role": t.role == "assistant" ? "assistant" : "user", "content": t.role == "assistant" ? t.text as Any : content as Any])
            }
            let body: [String: Any] = ["model": model, "temperature": 0.2, "messages": messages]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        } else {
            let name = model.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "gemini-2.5-flash"
            request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(name):generateContent")!, timeoutInterval: 75)
            request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
            let contents: [[String: Any]] = turns.map { t -> [String: Any] in
                var parts: [[String: Any]] = [["text": t.text.isEmpty ? " " : t.text]]
                for f in t.files {
                    let inline: [String: Any] = ["mime_type": f.mime, "data": f.data.base64EncodedString()]
                    parts.append(["inline_data": inline])
                }
                return ["role": t.role == "assistant" ? "model" : "user", "parts": parts]
            }
            let systemPart: [String: Any] = ["parts": [["text": system]]]
            let config: [String: Any] = json ? ["temperature": 0.2, "responseMimeType": "application/json"] : ["temperature": 0.2]
            let body: [String: Any] = ["systemInstruction": systemPart, "contents": contents, "generationConfig": config]
            request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        }
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let isGemini = provider != "openrouter"
        URLSession.shared.dataTask(with: request) { data, response, error in
            var result: (String?, String?) = (nil, nil)
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let obj = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            if let error = error {
                result = (nil, "The AI couldn’t be reached (\(error.localizedDescription)).")
            } else if code == 401 || code == 403 || (code == 400 && "\(obj ?? [:])".contains("API_KEY")) {
                result = (nil, "The AI didn’t accept the key. Check it in Settings › AI.")
            } else if code == 429 {
                result = (nil, "The free allowance is used up for the moment. Try again in a minute.")
            } else if code >= 400 || obj == nil {
                let message = ((obj?["error"] as? [String: Any])?["message"] as? String) ?? "it answered with an error (\(code))"
                result = (nil, "The AI couldn’t answer: \(message).")
            } else if isGemini {
                let parts = (((obj?["candidates"] as? [[String: Any]])?.first?["content"] as? [String: Any])?["parts"] as? [[String: Any]]) ?? []
                result = (parts.compactMap { $0["text"] as? String }.joined(), nil)
            } else {
                result = (((((obj?["choices"] as? [[String: Any]])?.first)?["message"] as? [String: Any])?["content"] as? String) ?? "", nil)
            }
            DispatchQueue.main.async { completion(result.0, result.1) }
        }.resume()
    }
}

/// The JSON object in a piece of text (even inside a code fence).
func jsonObject(in text: String?) -> [String: Any]? {
    guard let text = text, let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
    return (try? JSONSerialization.jsonObject(with: Data(text[start...end].utf8))) as? [String: Any]
}

/// Any JSON value as text (for the AI, and for the page).
func jsonText(_ value: Any) -> String {
    guard JSONSerialization.isValidJSONObject(value) || value is [Any],
          let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]) else { return "null" }
    return String(data: data, encoding: .utf8) ?? "null"
}

extension NativeBridge {
    /// What the AI is told about itself, the app and how to answer.
    func assistantSystem() -> String {
        let company = db.getCompanySettings()
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.dateFormat = "EEEE d MMMM yyyy"
        let iso = DateFormatter()
        iso.locale = Locale(identifier: "en_US_POSIX")
        iso.dateFormat = "yyyy-MM-dd"
        return """
        You are the assistant inside ScaffoldPro, the office app of Proficiency (HK) Limited, a Hong Kong scaffolding (and crane) \
        company that rents and sells scaffolding materials and quotes for jobs. You help the team do work in the app. \
        Today is \(f.string(from: Date())) (\(iso.string(from: Date()))). You are talking to \(nonBlank(TeamSync.memberName) ?? "a member of the team"). \
        Money is in \(company.currency) unless said otherwise.

        How the app works: projects have numbers such as 26219 and a name. Each project has BOQs (BQ26219-001), quotations \
        (Qt26219-001; subsidiaries Qt26219-001-s1), delivery notes and invoices. A quotation is "Rental" (prices per month) or "Sale". \
        Its lines are materials (from the material/price list, by item code), delivery charges, and other charges (labour, design, \
        erection…) in sections with a heading.

        ALWAYS answer with ONLY one JSON object, no other text — never tool-call syntax or function calls:
        {"reply": "what you say to the person (plain text; short; use - for lists)",
         "lookups": [ ... things to look up first ... ],
         "proposals": [ ... actions for the person to confirm ... ],
         "questions": [ ... choices for the person to make, shown as buttons ... ]}

        Questions (when you need the person to decide something before you can go on):
        {"id": "pricing", "text": "Rental or sale prices?", "options": ["Rental", "Sale"]}
        {"id": "standard", "text": "No “2m standard” in the material list", "options": ["Search for 2.0m standard", "Add it without a price", "Leave it out"]}
        Keep each question's text to a few words and give 2–5 short options (the person can also type their own). Ask everything \
        you need at once, put nothing else in "reply" than one short line, and make no proposals until they've answered.

        Lookups (the app runs them and sends you the results; then answer again). Use them before proposing:
        {"type": "findProjects", "query": "number, name or client words, or empty for the latest"}
        {"type": "findItems", "query": "words of an item, e.g. 2.0m standard", "limit": 12}  → the material list with item codes, units and Sale / Rental prices in \(company.currency)
        {"type": "getQuotation", "number": "Qt26219-001"}  → its lines (with ids), totals and letter details
        {"type": "listQuotations", "projectNumber": "26219"}
        {"type": "getProject", "number": "26219"}  → client, site, BOQs, quotations, delivery notes, invoices, open tasks
        {"type": "findClients", "query": "company, contact or site words"}  → clients and sites
        {"type": "listTasks", "projectNumber": "26219 or null", "includeDone": false, "events": false}
        {"type": "listInvoices", "projectNumber": "26219 or null", "unpaidOnly": true}  → totals, paid and balance due
        {"type": "stock", "query": "item words"}  → how many are in the yard, on hire, and on which projects

        Proposals (shown as cards; nothing happens until the person confirms):
        {"type": "createQuotation", "projectNumber": "26219", "pricingMode": "Rental" or "Sale", "subject": "short subject or null",
         "clientRef": null, "currency": null or e.g. "EUR" if the prices are not in \(company.currency),
         "items": [{"kind": "Material" | "Delivery" | "Other", "section": heading for "Other" or null, "itemCode": "code from findItems or null",
                    "description": "as it should read", "unit": "pc", "quantity": 10, "unitPrice": number or null}]}
        {"type": "addQuotationItems", "quotationNumber": "Qt26219-001", "items": [ same as above ]}
        {"type": "createTask", "title": "...", "dueDate": "yyyy-mm-dd or null", "dueTime": "HH:mm or null", "notes": null,
         "projectNumber": "26219 or null", "assignee": "a person's name or null"}
        {"type": "editQuotationItems", "quotationNumber": "Qt26219-001",
         "changes": [{"lineId": "id from getQuotation", "quantity": number or null, "unitPrice": number or null, "description": "new text or null", "remove": false}]}
        {"type": "updateQuotationDetails", "quotationNumber": "Qt26219-001", "subject": "...", "clientRef": "...", "siteRef": "...", "keyTerms": "..."}  (only the fields to change)
        {"type": "duplicateQuotation", "quotationNumber": "Qt26219-001", "toProjectNumber": "26220 or null for the same project"}
        {"type": "createProject", "name": "project name", "clientName": "client company", "siteName": "site name", "jobType": "Scaffolding" or "Crane"}
        {"type": "createBOQ", "projectNumber": "26220", "structure": "e.g. 10x20x5m working platform", "pricingMode": "Rental" or "Sale",
         "items": [ same as a quotation's items ]}
        {"type": "createClient", "companyName": "...", "contactPerson": null, "phone": null, "email": null, "address": "line 1", "addressLine2": null, "addressLine3": null}
        {"type": "completeTask", "taskId": "id from listTasks"}
        An event on the calendar is a createTask with "dueTime" and "endTime" ("HH:mm").
        {"type": "open", "page": "project" | "quotation", "number": "26219 or Qt26219-001"}

        Rules:
        - You can't make or change anything yourself: never say you have ("Created…", "Done"). Propose it, and say what the card will do.
        - "Continue", "yes", "go ahead", "do it": propose (as a card) the action you and the person were discussing — with every detail \
        already settled. Never answer with an empty reply.
        - Never invent prices. Take prices from the person, from an attached file, or from findItems (Sale or Rental to match the \
        quotation); if none, set "unitPrice": null and say so. Put the item code from findItems in "itemCode" when an item matches.
        - Never guess a project: look it up with findProjects; if it's unclear which, ask with "questions" (the likely projects as options).
        - Quantities are whole numbers. Keep descriptions as written on the file or by the person.
        - Read attached files carefully: every priced row, in order; leave out totals, discounts and terms.
        - To change a quotation's lines, getQuotation first and use the lines' ids. Only draft quotations can be changed.
        - For a new project, findClients first: use the client's and site's names exactly as found; a name not found makes a new one.
        - Use lookups only when you need them, at most a few at once. When you propose, say briefly in "reply" what you prepared.
        - You can propose several things at once (e.g. a new project and its quotation: create the project first; the quotation \
        card can name the project once it's made — or ask the person to confirm the project, then propose the quotation).
        - If you're asked something you can answer directly, just answer in "reply" with empty "lookups" and "proposals".
        """
    }

    // ---- assistant:send ----

    func handleAssistantSend(id: String, payload: [String: Any]) {
        guard QuotationAI.shared.ready else {
            let out: [String: Any] = ["ok": false, "error": "No AI is set up yet. Add a key in Settings › AI Import."]
            callback(id: id, ok: true, resultJson: jsonText(out), error: nil)
            return
        }
        var turns: [QuotationAI.ChatTurn] = []
        // The page keeps the conversation within the AI's context window
        // (older messages summarised); this is only a backstop.
        for m in ((payload["messages"] as? [[String: Any]]) ?? []).suffix(80) {
            var text = (m["text"] as? String) ?? ""
            // Files sent earlier: their text, as read then.
            for f in (m["files"] as? [[String: Any]]) ?? [] {
                if let t = nonBlank(f["text"] as? String) { text += "\n\n[Attached file “\((f["name"] as? String) ?? "file")”, as read:]\n\(t)" }
            }
            turns.append(QuotationAI.ChatTurn(role: (m["role"] as? String) == "assistant" ? "assistant" : "user", text: text))
        }
        guard !turns.isEmpty else {
            let out: [String: Any] = ["ok": false, "error": "Say what you'd like done."]
            callback(id: id, ok: true, resultJson: jsonText(out), error: nil)
            return
        }
        let attachments = (payload["attachments"] as? [[String: Any]]) ?? []
        let run = AssistantRun(id: nonBlank(payload["runId"] as? String), live: !id.hasPrefix("web-"))
        // The floating chat: what the person is looking at, with the newest message
        // — its text, and a picture of the screen taken now.
        let context = payload["context"] as? [String: Any]
        let screen = context.map { assistantScreen($0) } ?? ""
        let wantsPicture = context != nil && webView != nil
        let history = turns
        // The newest message's files: read (OCR if need be) off the main thread.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("ScaffoldPro-assistant-\(UUID().uuidString)", isDirectory: true)
            try? FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: temp) }
            var files: [QuotationAI.ChatFile] = []
            var read: [[String: Any]] = []
            var extra = ""
            for (i, a) in attachments.prefix(5).enumerated() {
                let name = safeFileName((a["name"] as? String) ?? "file \(i + 1)")
                DispatchQueue.main.async { self?.assistantStep(run, "Reading “\(name)”") }
                guard let data = Data(base64Encoded: (a["base64"] as? String) ?? ""), !data.isEmpty, data.count <= 20_000_000 else { continue }
                let url = temp.appendingPathComponent("\(i)-\(name)")
                try? data.write(to: url)
                let ext = url.pathExtension.lowercased()
                var text = ""
                if ["xlsx", "xlsm"].contains(ext), let sheets = try? SpreadsheetReader.readXLSX(url) {
                    text = sheets.map { s in "Sheet \(s.name):\n" + s.rows.map { $0.joined(separator: "\t") }.joined(separator: "\n") }.joined(separator: "\n\n")
                } else {
                    text = QuotationImportReader.text(of: url).text
                }
                text = String(text.prefix(40_000))
                let mime = ext == "pdf" ? "application/pdf" : ext == "png" ? "image/png" : ["jpg", "jpeg"].contains(ext) ? "image/jpeg"
                    : ext == "webp" ? "image/webp" : ext == "heic" ? "image/heic" : nil
                if let mime = mime, data.count <= 15_000_000 { files.append(QuotationAI.ChatFile(mime: mime, data: data)) }
                read.append(["name": name, "text": text])
                extra += "\n\n[Attached file “\(name)”, as read:]\n" + (text.isEmpty ? "(no text could be read — see the file itself)" : text)
            }
            DispatchQueue.main.async {
                guard let self = self else { return }
                let go = { (picture: QuotationAI.ChatFile?) in
                    var all = history
                    if var last = all.popLast() {
                        last.text += extra + screen + (picture == nil ? "" : "\n[A picture of their screen is attached.]")
                        last.files = files + (picture.map { [$0] } ?? [])
                        all.append(last)
                    }
                    self.runAssistant(turns: all, round: 0, run: run) { reply in
                        if self.assistantStopped(run) { return }
                        var out = reply
                        out["files"] = read
                        self.callback(id: id, ok: true, resultJson: jsonText(out), error: nil)
                    }
                }
                if self.assistantStopped(run) { return }
                if wantsPicture {
                    self.assistantStep(run, "Looking at your screen")
                    self.screenPicture(go)
                } else { go(nil) }
            }
        }
    }

    /// The older part of a conversation condensed (the page's context
    /// window): what was asked, decided, made and still to do — numbers kept.
    func handleAssistantSummarise(id: String, payload: [String: Any]) {
        let previous = nonBlank(payload["summary"] as? String)
        var transcript = previous.map { "Summary so far:\n\($0)\n\nThen:\n" } ?? ""
        for m in (payload["messages"] as? [[String: Any]]) ?? [] {
            let who = (m["role"] as? String) == "assistant" ? "Assistant" : "Person"
            var text = (m["text"] as? String) ?? ""
            for f in (m["files"] as? [[String: Any]]) ?? [] {
                if let t = nonBlank(f["text"] as? String) { text += "\n[File “\((f["name"] as? String) ?? "file")”:]\n\(String(t.prefix(6000)))" }
            }
            transcript += "\(who): \(text)\n\n"
        }
        let system = "You condense a conversation between a person at Proficiency (HK) Limited and the ScaffoldPro assistant, so it can go on "
            + "without the full text. Write plain text (no JSON), under 350 words, as short notes: what they asked for; project, quotation, "
            + "BOQ and item numbers; items with quantities and prices; choices made (Rental/Sale, which items); what was made or changed "
            + "(and its number); what is still waiting or was proposed but not confirmed. Keep every number exactly. Leave out chit-chat."
        QuotationAI.shared.chat(system: system, turns: [QuotationAI.ChatTurn(role: "user", text: String(transcript.prefix(120_000)))], json: false) { [weak self] text, error in
            let summary = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let out: [String: Any] = error != nil || summary.isEmpty
                ? ["ok": false, "error": error ?? "The AI couldn't summarise it."]
                : ["ok": true, "summary": summary]
            self?.callback(id: id, ok: true, resultJson: jsonText(out), error: nil)
        }
    }

    /// The lookups the AI can ask for (everything else it names is a proposal).
    static let assistantLookupTypes: Set<String> = ["findProjects", "findItems", "getQuotation", "listQuotations", "getProject",
                                                           "findClients", "listTasks", "listInvoices", "stock"]

    /// Asks the AI; runs its lookups and asks again — a few rounds at most,
    /// and never past `deadline` (it says what it has instead).
    func runAssistant(turns: [QuotationAI.ChatTurn], round: Int, deadline: Date = Date().addingTimeInterval(150),
                              run: AssistantRun = AssistantRun(id: nil, live: false), done: @escaping ([String: Any]) -> Void) {
        if assistantStopped(run) { return }
        assistantStep(run, round == 0 ? "Asking the AI (\(QuotationAI.shared.model))" : "Asking the AI again, with what it found")
        QuotationAI.shared.chat(system: assistantSystem(), turns: turns) { [weak self] text, error in
            guard let self = self, !self.assistantStopped(run) else { return }
            if let error = error { done(["ok": false, "error": error]); return }
            guard let json = self.assistantAnswer(text) else {
                let raw = (text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                // Plain words: its answer. Something like JSON or code that
                // couldn't be read: never shown — asked for once more.
                let looksLikeCode = raw.contains("{\"") || raw.contains("\"reply\"") || raw.contains("<|") || raw.hasPrefix("{") || raw.hasPrefix("[")
                if !looksLikeCode { done(["ok": true, "reply": raw, "proposals": [Any]()]); return }
                if round < 4, Date() < deadline {
                    self.assistantStep(run, "Its answer came back garbled — asking again")
                    var next = turns
                    next.append(QuotationAI.ChatTurn(role: "assistant", text: raw))
                    next.append(QuotationAI.ChatTurn(role: "user", text: "That answer couldn't be read: it wasn't valid JSON. Answer again with ONLY the one JSON object {\"reply\", \"lookups\", \"proposals\", \"questions\"} — proposals go inside \"proposals\", lists are real JSON lists (not in quotes)."))
                    self.runAssistant(turns: next, round: round + 1, deadline: deadline, run: run, done: done)
                    return
                }
                done(["ok": true, "reply": self.replyOnly(raw) ?? "Its answer came back garbled. Please try again — or choose another model in Settings › AI Import.", "proposals": [Any]()])
                return
            }
            let reply = ((json["reply"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let lookups = (json["lookups"] as? [[String: Any]]) ?? []
            let proposals = (json["proposals"] as? [[String: Any]]) ?? []
            let asked = !((json["questions"] as? [Any]) ?? []).isEmpty
            // Nothing at all (or just "Done"): asked once more for a real answer.
            let empty = lookups.isEmpty && proposals.isEmpty && !asked
                && (reply.isEmpty || reply.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".! ")) == "done")
            if empty {
                guard round < 4, Date() < deadline else {
                    done(["ok": false, "error": "The AI came back with nothing. Say exactly what you'd like (e.g. “make the BOQ for 26220 with those items”) and try again."])
                    return
                }
                self.assistantStep(run, "It answered with nothing — asking again")
                var next = turns
                next.append(QuotationAI.ChatTurn(role: "assistant", text: jsonText(json)))
                next.append(QuotationAI.ChatTurn(role: "user", text: "That answer was empty. Answer my last message now: put the action we discussed in \"proposals\" (it shows as a card for me to confirm), or ask in \"questions\" if you must. Never just say \"Done\" — nothing has been made."))
                self.runAssistant(turns: next, round: round + 1, deadline: deadline, run: run, done: done)
                return
            }
            if !lookups.isEmpty && proposals.isEmpty {
                guard round < 4, Date() < deadline else {
                    done(["ok": false, "error": "The AI took too long working it out. Try again, perhaps asking for one thing at a time — or choose a quicker model in Settings › AI Import."])
                    return
                }
                let results: [[String: Any]] = lookups.prefix(8).map { l in
                    let result = self.assistantLookup(l)
                    self.assistantStep(run, self.lookupSummary(l, result))
                    return ["lookup": l, "result": result]
                }
                var next = turns
                next.append(QuotationAI.ChatTurn(role: "assistant", text: jsonText(json)))
                next.append(QuotationAI.ChatTurn(role: "user", text: "The app's results for your lookups:\n\(jsonText(results))\n\nNow answer with the JSON object (proposals if you're ready; more lookups only if you must)."))
                self.runAssistant(turns: next, round: round + 1, deadline: deadline, run: run, done: done)
                return
            }
            if !proposals.isEmpty { self.assistantStep(run, "Preparing \(min(6, proposals.count)) card\(proposals.count == 1 ? "" : "s") to confirm") }
            // Its questions, as buttons: a few words each, a few options each.
            let questions: [[String: Any]] = ((json["questions"] as? [[String: Any]]) ?? []).prefix(4).enumerated().compactMap { pair -> [String: Any]? in
                let (i, q) = pair
                guard let text = nonBlank(q["text"] as? String) else { return nil }
                let options = ((q["options"] as? [Any]) ?? []).compactMap { nonBlank(($0 as? String) ?? ($0 as? NSNumber)?.stringValue) }.prefix(6)
                return ["id": nonBlank(q["id"] as? String) ?? "q\(i + 1)", "text": text, "options": Array(options)]
            }
            done(["ok": true, "reply": reply, "proposals": proposals.prefix(6).map { self.assistantCheck($0) }, "questions": questions])
        }
    }

    /// One run of the assistant: its id (from the page) and whether its
    /// page is in this window (steps are shown there as they happen).
    struct AssistantRun { var id: String?; var live: Bool }

    /// Interrupted by the person: stop here.
    func assistantStopped(_ run: AssistantRun) -> Bool {
        guard let id = run.id else { return false }
        return assistantCancelled.contains(id)
    }

    /// A step, shown on the page as it happens ("Searched the material list…").
    func assistantStep(_ run: AssistantRun, _ text: String) {
        guard run.live, let id = run.id, let webView = webView, !assistantCancelled.contains(id) else { return }
        let step: [String: Any] = ["runId": id, "text": text]
        webView.evaluateJavaScript("window.__assistantStep && window.__assistantStep(\(jsonText(step)))", completionHandler: nil)
    }

    /// What a lookup did, in a few words.
    func lookupSummary(_ l: [String: Any], _ result: Any) -> String {
        let type = (l["type"] as? String) ?? ""
        let q = nonBlank(l["query"] as? String) ?? nonBlank(l["number"] as? String) ?? nonBlank(l["projectNumber"] as? String) ?? ""
        let quoted = q.isEmpty ? "" : " “\(q)”"
        if let e = (result as? [String: Any])?["error"] as? String { return "Looked for\(quoted) — \(e)" }
        let n = (result as? [Any])?.count ?? 0
        let count = { (one: String, many: String) in "\(n) \(n == 1 ? one : many)" }
        switch type {
        case "findProjects": return "Searched projects for\(quoted) — \(count("found", "found"))"
        case "findItems": return "Searched the material list for\(quoted) — \(count("item", "items"))"
        case "getQuotation": return "Read quotation\(quoted)"
        case "listQuotations": return "Listed the quotations of project\(quoted) — \(n)"
        case "getProject": return "Read project\(quoted)"
        case "findClients":
            let r = result as? [String: Any]
            return "Searched clients and sites for\(quoted) — \((r?["clients"] as? [Any])?.count ?? 0) clients, \((r?["sites"] as? [Any])?.count ?? 0) sites"
        case "listTasks": return "Listed tasks\(quoted.isEmpty ? "" : " of\(quoted)") — \(n)"
        case "listInvoices": return "Listed invoices\(quoted.isEmpty ? "" : " of\(quoted)") — \(n)"
        case "stock": return "Checked stock for\(quoted) — \(count("item", "items"))"
        default: return "Looked up \(type)"
        }
    }

    /// The AI's answer as {reply, lookups, proposals}: its JSON object — or,
    /// from a model that writes tool calls instead
    /// (<|tool_call_start|>[createProject(name='x', …)]<|tool_call_end|>),
    /// those calls, read into the same shape. nil: plain text.
    func assistantAnswer(_ text: String?) -> [String: Any]? {
        guard let text = text else { return nil }
        if let json = jsonObject(in: text) ?? jsonObject(in: repairedJSON(text)), let answer = normalisedAnswer(json) { return answer }
        // name(key='value', key2=12, key3=[{…}]) — as many as there are.
        guard let call = try? NSRegularExpression(pattern: #"([A-Za-z]+)\(((?:[^()'"]|'[^']*'|"[^"]*"|\([^()]*\))*)\)"#) else { return nil }
        var lookups: [[String: Any]] = [], proposals: [[String: Any]] = []
        let ns = text as NSString
        var used: [NSRange] = []
        for m in call.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            let known = NativeBridge.assistantLookupTypes.contains(name)
                || ["createQuotation", "addQuotationItems", "createTask", "open", "editQuotationItems", "updateQuotationDetails",
                    "duplicateQuotation", "createProject", "createClient", "completeTask", "createBOQ"].contains(name)
            guard known else { continue }
            var item: [String: Any] = ["type": name]
            for (k, v) in toolArguments(ns.substring(with: m.range(at: 2))) { item[k] = v }
            if NativeBridge.assistantLookupTypes.contains(name) { lookups.append(item) } else { proposals.append(item) }
            used.append(m.range)
        }
        guard !lookups.isEmpty || !proposals.isEmpty else { return nil }
        var reply = text
        for r in used.reversed() { reply = (reply as NSString).replacingCharacters(in: r, with: "") }
        reply = reply.replacingOccurrences(of: #"<\|[^|>]*\|>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "[]", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return ["reply": reply, "lookups": lookups, "proposals": proposals]
    }

    /// Every kind of proposal the app knows.
    static let assistantProposalTypes: Set<String> = ["createQuotation", "addQuotationItems", "createTask", "open", "editQuotationItems",
                                                             "updateQuotationDetails", "duplicateQuotation", "createProject", "createClient",
                                                             "completeTask", "createBOQ"]

    /// The usual ways a model's JSON comes out broken, mended: a list or
    /// object wrapped in quotes ("items": "[…]"), and trailing commas.
    func repairedJSON(_ text: String) -> String {
        var t = text
        for (pattern, template) in [(#":\s*"(\[|\{)"#, ": $1"), (#"(\]|\})"\s*([,}\]])"#, "$1$2"), (#",\s*([\]}])"#, "$1")] {
            t = t.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
        return t
    }

    /// {reply, lookups, proposals, questions} from whatever object the model
    /// gave: as asked, or one proposal (or lookup) on its own at the top.
    func normalisedAnswer(_ json: [String: Any]) -> [String: Any]? {
        var out = json
        if let type = json["type"] as? String {
            var item = json
            for k in ["reply", "lookups", "proposals", "questions"] { item.removeValue(forKey: k) }
            if NativeBridge.assistantProposalTypes.contains(type) {
                out["proposals"] = [item] + ((json["proposals"] as? [[String: Any]]) ?? [])
            } else if NativeBridge.assistantLookupTypes.contains(type) {
                out["lookups"] = [item] + ((json["lookups"] as? [[String: Any]]) ?? [])
            }
        }
        // A list sent as text ("items": "[…]") read as the list.
        if var proposals = out["proposals"] as? [[String: Any]] {
            for i in proposals.indices {
                for key in ["items", "changes"] {
                    if let raw = proposals[i][key] as? String, let data = repairedJSON(raw).data(using: .utf8),
                       let list = try? JSONSerialization.jsonObject(with: data) as? [Any] { proposals[i][key] = list }
                }
            }
            out["proposals"] = proposals
        }
        guard out["reply"] != nil || out["lookups"] != nil || out["proposals"] != nil || out["questions"] != nil else { return nil }
        return out
    }

    /// Just the "reply" of an answer that couldn't be read, if it has one.
    func replyOnly(_ text: String) -> String? {
        guard let r = text.range(of: #""reply"\s*:\s*"((?:[^"\\]|\\.)*)""#, options: .regularExpression) else { return nil }
        let quoted = String(text[r]).replacingOccurrences(of: #"^"reply"\s*:\s*"#, with: "", options: .regularExpression)
        return (try? JSONSerialization.jsonObject(with: Data(quoted.utf8), options: [.fragmentsAllowed])) as? String
    }

    /// key='text', key="text", key=12.5, key=true, key=null, key=[…json…].
    func toolArguments(_ raw: String) -> [String: Any] {
        var out: [String: Any] = [:]
        let chars = Array(raw)
        var i = 0
        func skipSpace() { while i < chars.count, chars[i] == " " || chars[i] == "," || chars[i] == "\n" { i += 1 } }
        while i < chars.count {
            skipSpace()
            var key = ""
            while i < chars.count, chars[i] != "=" { key.append(chars[i]); i += 1 }
            i += 1
            key = key.trimmingCharacters(in: .whitespaces)
            guard i <= chars.count, !key.isEmpty else { break }
            skipSpace()
            guard i < chars.count else { break }
            var value = ""
            if chars[i] == "'" || chars[i] == "\"" {
                let q = chars[i]; i += 1
                while i < chars.count, chars[i] != q { value.append(chars[i]); i += 1 }
                i += 1
                out[key] = value
            } else if chars[i] == "[" || chars[i] == "{" {
                var depth = 0
                repeat {
                    if chars[i] == "[" || chars[i] == "{" { depth += 1 }
                    if chars[i] == "]" || chars[i] == "}" { depth -= 1 }
                    value.append(chars[i]); i += 1
                } while i < chars.count && depth > 0
                let json = value.replacingOccurrences(of: "'", with: "\"").replacingOccurrences(of: "None", with: "null")
                    .replacingOccurrences(of: "True", with: "true").replacingOccurrences(of: "False", with: "false")
                out[key] = (try? JSONSerialization.jsonObject(with: Data(json.utf8), options: [.fragmentsAllowed])) ?? value
            } else {
                while i < chars.count, chars[i] != "," { value.append(chars[i]); i += 1 }
                let v = value.trimmingCharacters(in: .whitespaces)
                if let d = Double(v) { out[key] = d } else if ["true", "True"].contains(v) { out[key] = true }
                else if ["false", "False"].contains(v) { out[key] = false } else if ["null", "None"].contains(v) { out[key] = NSNull() } else { out[key] = v }
            }
        }
        return out
    }

    /// A picture of the window's page, as a JPEG at most 1,600 pixels wide
    /// (nil if it can't be taken).
    func screenPicture(_ done: @escaping (QuotationAI.ChatFile?) -> Void) {
        guard let webView = webView else { done(nil); return }
        let config = WKSnapshotConfiguration()
        config.afterScreenUpdates = false
        if webView.bounds.width > 1600 { config.snapshotWidth = NSNumber(value: 1600) }
        webView.takeSnapshot(with: config) { image, _ in
            guard let image = image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                  let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.72]) else { done(nil); return }
            done(QuotationAI.ChatFile(mime: "image/jpeg", data: jpeg))
        }
    }

    /// What's on the person's screen, for the AI: the page, the document
    /// open on it, what they've selected and the page's text.
    func assistantScreen(_ c: [String: Any]) -> String {
        let page = (c["page"] as? String) ?? ""
        let id = (c["id"] as? String) ?? ""
        let number = (c["number"] as? String) ?? ""
        var what = "the \(page.isEmpty ? "app's" : page) page"
        switch page {
        case "quotation-editor":
            if let q = db.getQuotation(id: id) { what = "quotation \(q.quotationNumber) (\(q.status), \(q.pricingMode)) of project \(db.getProject(id: q.projectId)?.projectNumber ?? "?")" }
        case "boq-editor":
            if let b = db.getBOQ(id: id) { what = "BOQ \(b.boqNumber) (\(b.status)) of project \(db.getProject(id: b.projectId)?.projectNumber ?? "?")" }
        case "invoice-editor":
            if let i = db.getInvoice(id: id) { what = "invoice \(i.invoiceNumber) (\(i.status)) of project \(db.getProject(id: i.projectId)?.projectNumber ?? "?")" }
        case "delivery-note-editor":
            if let d = db.getDeliveryNote(id: id) { what = "delivery note \(d.deliveryNoteNumber) (\(d.status)) of project \(db.getProject(id: d.projectId)?.projectNumber ?? "?")" }
        case "project-detail":
            if let p = db.getProjectByNumber(number) { what = "project \(p.projectNumber) \(p.name)" }
        default:
            if let t = nonBlank(c["title"] as? String) { what = "the \(t) page" }
        }
        var out = "\n\n[On screen: the person is looking at \(what). “This”, “here” and “it” mean that unless they say otherwise. Look it up (getQuotation, getProject…) before changing it.]"
        if let sel = nonBlank(c["selection"] as? String) { out += "\n[They have selected this text:]\n\(String(sel.prefix(2000)))" }
        if let text = nonBlank(c["screen"] as? String) { out += "\n[What the page shows, as text:]\n\(String(text.prefix(8000)))" }
        return out
    }

    // ---- lookups ----

    func assistantLookup(_ l: [String: Any]) -> Any {
        let type = (l["type"] as? String) ?? ""
        let query = ((l["query"] as? String) ?? "").lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let words = query.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        switch type {
        case "findProjects":
            let clients = Dictionary(db.listClients(includeArchived: true).map { ($0.id, $0.companyName) }, uniquingKeysWith: { a, _ in a })
            let projects = db.listProjectsRaw().sorted { $0.createdAt > $1.createdAt }
            let found = projects.filter { p in
                let hay = "\(p.projectNumber) \(p.name) \(clients[p.clientId] ?? "")".lowercased()
                return words.allSatisfy { hay.contains($0) }
            }
            return found.prefix(25).map { p -> [String: Any] in
                ["projectNumber": p.projectNumber, "name": p.name, "client": clients[p.clientId] ?? "", "status": p.status, "jobType": normalJobType(p.jobType)]
            }
        case "findItems":
            let limit = max(1, min(30, (l["limit"] as? Int) ?? 12))
            let items = db.inBaseCurrency(db.allPriceListItems().filter { !$0.isArchived })
            let scored = items.compactMap { i -> (PriceListItem, Int)? in
                let hay = "\(i.itemCode) \(i.itemName) \(i.category ?? "")".lowercased()
                let hits = words.filter { hay.contains($0) }.count
                return words.isEmpty || hits == words.count ? (i, hits) : nil
            }
            return scored.prefix(limit).map { pair -> [String: Any] in
                let i = pair.0
                var row: [String: Any] = ["itemCode": i.itemCode, "description": i.itemName, "unit": i.unit]
                if let c = i.category { row["category"] = c }
                if let s = i.unitSalePrice { row["salePrice"] = s }
                if let r = i.unitRentalPrice { row["rentalPrice"] = r }
                return row
            }
        case "getQuotation":
            let number = ((l["number"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            guard let q = db.quotationsStore.readAll().first(where: { $0.quotationNumber.caseInsensitiveCompare(number) == .orderedSame }) else {
                return ["error": "No quotation \(number)."]
            }
            let lines = db.quotationLineItemsStore.readAll().filter { $0.quotationId == q.id }.sorted { $0.sortOrder < $1.sortOrder }.map { li -> [String: Any] in
                ["lineId": li.id, "itemCode": li.itemCode, "description": li.itemDescription, "unit": li.unit, "quantity": li.quantity, "unitPrice": li.appliedUnitPrice,
                 "kind": li.blockId != nil ? "Other" : li.section == "Delivery" ? "Delivery" : "Material"]
            }
            let detail = db.getQuotationDetail(id: q.id)
            let out: [String: Any] = ["number": q.quotationNumber, "status": q.status, "pricingMode": q.pricingMode, "subject": q.subject ?? "",
                                      "clientRef": q.clientRef ?? "", "siteRef": q.siteRef ?? "", "keyTerms": q.keyTerms ?? "",
                                      "subtotal": detail?.subtotal ?? 0, "total": detail?.total ?? 0,
                                      "project": db.getProject(id: q.projectId)?.projectNumber ?? "", "lines": lines]
            return out
        case "listQuotations":
            let number = ((l["projectNumber"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            guard let p = db.getProjectByNumber(number) else { return ["error": "No project \(number)."] }
            return db.quotationsStore.readAll().filter { $0.projectId == p.id }.map { q -> [String: Any] in
                ["number": q.quotationNumber, "status": q.status, "pricingMode": q.pricingMode, "subject": q.subject ?? "",
                 "total": db.getQuotationDetail(id: q.id)?.total ?? 0]
            }
        case "getProject":
            let number = ((l["number"] as? String) ?? (l["projectNumber"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            guard let p = db.getProjectByNumber(number) else { return ["error": "No project \(number)."] }
            let client = db.getClient(id: p.clientId), site = db.getSite(id: p.siteId)
            let boqs = db.boqsStore.readAll().filter { $0.projectId == p.id }.map { b -> [String: Any] in
                ["number": b.boqNumber, "status": b.status, "structure": b.structure ?? "", "pricingMode": b.pricingMode]
            }
            let quotes = db.quotationsStore.readAll().filter { $0.projectId == p.id }.map { q -> [String: Any] in
                ["number": q.quotationNumber, "status": q.status, "subject": q.subject ?? "", "pricingMode": q.pricingMode,
                 "total": db.getQuotationDetail(id: q.id)?.total ?? 0]
            }
            let notes = db.deliveryNotesStore.readAll().filter { $0.projectId == p.id }.map { d -> [String: Any] in
                ["number": d.deliveryNoteNumber, "status": d.status]
            }
            let invoices = db.invoicesStore.readAll().filter { $0.projectId == p.id }.map { i -> [String: Any] in
                let detail = db.getInvoiceDetail(id: i.id)
                return ["number": i.invoiceNumber, "status": i.status, "date": i.invoiceDate, "total": detail?.total ?? 0, "balanceDue": detail?.balanceDue ?? 0]
            }
            let tasks = db.listTasks(projectId: p.id, includeEvents: true).filter { !$0.task.done }.map { t -> [String: Any] in
                ["id": t.task.id, "title": t.task.title, "dueDate": t.task.dueDate ?? "", "assignee": t.task.assignee ?? t.task.team ?? "anyone"]
            }
            let out: [String: Any] = ["projectNumber": p.projectNumber, "name": p.name, "status": p.status, "jobType": normalJobType(p.jobType),
                                      "client": client?.companyName ?? "", "clientContact": client?.contactPerson ?? "", "site": site?.name ?? "",
                                      "siteAddress": site?.address ?? "", "description": p.projectDescription ?? "",
                                      "boqs": boqs, "quotations": quotes, "deliveryNotes": notes, "invoices": invoices, "openTasks": tasks]
            return out
        case "findClients":
            let clients = db.listClients(includeArchived: false).filter { c in
                let hay = "\(c.companyName) \(c.contactPerson ?? "") \(c.clientReference ?? "")".lowercased()
                return words.allSatisfy { hay.contains($0) }
            }.prefix(15).map { c -> [String: Any] in
                ["companyName": c.companyName, "contactPerson": c.contactPerson ?? "", "phone": c.phone ?? "", "email": c.email ?? "",
                 "address": [c.address, c.addressLine2, c.addressLine3].compactMap { nonBlank($0) }.joined(separator: ", ")]
            }
            let sites = db.listSites(includeArchived: false).filter { st in
                let hay = "\(st.name) \(st.address ?? "")".lowercased()
                return words.allSatisfy { hay.contains($0) }
            }.prefix(15).map { st -> [String: Any] in ["name": st.name, "address": st.address ?? ""] }
            let out: [String: Any] = ["clients": Array(clients), "sites": Array(sites)]
            return out
        case "listTasks":
            let projectId = nonBlank(l["projectNumber"] as? String).flatMap { db.getProjectByNumber($0)?.id }
            let includeDone = (l["includeDone"] as? Bool) == true
            let events = (l["events"] as? Bool) == true
            return db.listTasks(projectId: projectId, includeEvents: true)
                .filter { (includeDone || !$0.task.done) && (events ? $0.task.endTime != nil : true) }
                .prefix(40).map { t -> [String: Any] in
                    ["id": t.task.id, "title": t.task.title, "done": t.task.done, "dueDate": t.task.dueDate ?? "", "time": t.task.dueTime ?? "",
                     "endTime": t.task.endTime ?? "", "for": t.task.assignee ?? t.task.team ?? "anyone", "project": t.projectNumber ?? "",
                     "overdue": t.overdue, "priority": t.task.priority ?? ""]
                }
        case "listInvoices":
            let projectId = nonBlank(l["projectNumber"] as? String).flatMap { db.getProjectByNumber($0)?.id }
            let unpaid = (l["unpaidOnly"] as? Bool) == true
            let projects = Dictionary(db.listProjectsRaw().map { ($0.id, $0.projectNumber) }, uniquingKeysWith: { a, _ in a })
            return db.invoicesStore.readAll().filter { projectId == nil || $0.projectId == projectId }
                .compactMap { i -> [String: Any]? in
                    let d = db.getInvoiceDetail(id: i.id)
                    let balance = d?.balanceDue ?? 0
                    if unpaid && (balance <= 0.005 || i.status == "Cancelled" || i.status == "Draft") { return nil }
                    return ["number": i.invoiceNumber, "project": projects[i.projectId] ?? "", "status": i.status, "date": i.invoiceDate,
                            "dueDate": i.dueDate ?? "", "total": d?.total ?? 0, "paid": i.amountPaid, "balanceDue": balance]
                }
                .sorted { (($0["date"] as? String) ?? "") > (($1["date"] as? String) ?? "") }
                .prefix(40).map { $0 }
        case "stock":
            let rows = db.stockData().items.filter { r in
                let hay = "\(r.itemCode) \(r.itemName)".lowercased()
                return !words.isEmpty && words.allSatisfy { hay.contains($0) }
            }
            return rows.prefix(15).map { r -> [String: Any] in
                ["itemCode": r.itemCode, "description": r.itemName, "unit": r.unit, "inYard": r.inYard, "onHire": r.onHire, "owned": r.owned,
                 "onHireByProject": r.onHireByProject.prefix(8).map { ["project": "\($0.projectNumber) \($0.projectName)", "quantity": $0.quantity] as [String: Any] }]
            }
        default:
            return ["error": "Unknown lookup \(type)."]
        }
    }

    // ---- proposals: checked and filled in before they're shown ----

    /// The material list's items by code, prices in the base currency.
    func priceItemsByCode() -> [String: PriceListItem] {
        Dictionary(db.inBaseCurrency(db.allPriceListItems().filter { !$0.isArchived }).map { ($0.itemCode.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })
    }

    /// The lines of a proposal made whole: found items get their code,
    /// unit and (when none was given) price from the material list.
    func assistantItems(_ raw: Any?, mode: String, problems: inout [String]) -> [[String: Any]] {
        let byCode = priceItemsByCode()
        var out: [[String: Any]] = []
        for r in (raw as? [[String: Any]]) ?? [] {
            var item: [String: Any] = [:]
            let kind = ["Material", "Delivery", "Other"].contains((r["kind"] as? String) ?? "") ? (r["kind"] as! String) : "Material"
            var description = ((r["description"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var unit = nonBlank(r["unit"] as? String) ?? ""
            var price = (r["unitPrice"] as? NSNumber)?.doubleValue
            let quantity = max(1, ((r["quantity"] as? NSNumber)?.doubleValue ?? 1).rounded())
            var code = nonBlank(r["itemCode"] as? String)
            if kind == "Material", let c = code, let pl = byCode[c.uppercased()] {
                code = pl.itemCode
                if description.isEmpty { description = pl.itemName }
                if unit.isEmpty { unit = pl.unit }
                let list = mode == "Sale" ? (pl.unitSalePrice ?? pl.unitRentalPrice) : (pl.unitRentalPrice ?? pl.unitSalePrice)
                if price == nil || price == 0, let list = list { price = list; item["priceFromList"] = true }
                item["matched"] = true
            }
            guard !description.isEmpty else { continue }
            if price == nil { problems.append("No price for “\(description.split(separator: "\n").first.map(String.init) ?? description)” — it's added at 0.") }
            item["kind"] = kind
            if let s = nonBlank(r["section"] as? String), kind == "Other" { item["section"] = s }
            if let c = code { item["itemCode"] = c }
            item["description"] = description
            item["unit"] = unit.isEmpty ? "pc" : unit
            item["quantity"] = quantity
            item["unitPrice"] = doubleOf(roundToCents(decimalOf(max(0, price ?? 0))))
            out.append(item)
        }
        return out
    }

    func assistantCheck(_ p: [String: Any]) -> [String: Any] {
        var out = p
        var problems: [String] = []
        let type = (p["type"] as? String) ?? ""
        switch type {
        case "createQuotation":
            let number = ((p["projectNumber"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            let mode = (p["pricingMode"] as? String) == "Sale" ? "Sale" : "Rental"
            out["pricingMode"] = mode
            if let project = db.getProjectByNumber(number) { out["projectName"] = project.name } else { problems.append("There's no project \(number.isEmpty ? "chosen" : number).") }
            out["items"] = assistantItems(p["items"], mode: mode, problems: &problems)
            if ((out["items"] as? [Any]) ?? []).isEmpty { problems.append("There are no items.") }
        case "addQuotationItems":
            let number = ((p["quotationNumber"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            let q = db.quotationsStore.readAll().first { $0.quotationNumber.caseInsensitiveCompare(number) == .orderedSame }
            if let q = q {
                out["quotationNumber"] = q.quotationNumber
                if q.status != "Draft" { problems.append("\(q.quotationNumber) is \(q.status.lowercased()); only a draft can be changed.") }
            } else { problems.append("There's no quotation \(number).") }
            out["items"] = assistantItems(p["items"], mode: q?.pricingMode ?? "Rental", problems: &problems)
            if ((out["items"] as? [Any]) ?? []).isEmpty { problems.append("There are no items.") }
        case "createTask":
            if nonBlank(p["title"] as? String) == nil { problems.append("The task has no title.") }
            if let n = nonBlank(p["projectNumber"] as? String), db.getProjectByNumber(n) == nil { problems.append("There's no project \(n).") }
            if let due = nonBlank(p["dueDate"] as? String), validDay(due) == nil { problems.append("“\(due)” isn't a date.") }
        case "open":
            if assistantHref(p) == nil { problems.append("That page couldn't be found.") }
            out["href"] = assistantHref(p) ?? ""
        case "editQuotationItems":
            let number = ((p["quotationNumber"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            guard let q = quotation(number) else { problems.append("There's no quotation \(number)."); break }
            out["quotationNumber"] = q.quotationNumber
            if q.status != "Draft" { problems.append("\(q.quotationNumber) is \(q.status.lowercased()); only a draft can be changed.") }
            let lines = db.quotationLineItemsStore.readAll().filter { $0.quotationId == q.id }
            var changes: [[String: Any]] = []
            for c in (p["changes"] as? [[String: Any]]) ?? [] {
                // By its id, else by its code or the words of its description.
                let key = ((c["lineId"] as? String) ?? (c["match"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
                var found = lines.filter { $0.id == key }
                if found.isEmpty, !key.isEmpty {
                    found = lines.filter { $0.itemCode.caseInsensitiveCompare(key) == .orderedSame }
                    if found.isEmpty {
                        let ws = key.lowercased().split(separator: " ").map(String.init)
                        found = lines.filter { l in ws.allSatisfy { l.itemDescription.lowercased().contains($0) } }
                    }
                }
                guard found.count == 1, let line = found.first else {
                    problems.append(found.isEmpty ? "No line matches “\(key)”." : "“\(key)” matches \(found.count) lines; say which.")
                    continue
                }
                var change: [String: Any] = ["lineId": line.id, "description": line.itemDescription, "unit": line.unit,
                                             "oldQuantity": line.quantity, "oldUnitPrice": line.appliedUnitPrice]
                if (c["remove"] as? Bool) == true { change["remove"] = true }
                if let v = (c["quantity"] as? NSNumber)?.doubleValue { change["quantity"] = max(0, v.rounded()) }
                if let v = (c["unitPrice"] as? NSNumber)?.doubleValue { change["unitPrice"] = doubleOf(roundToCents(decimalOf(max(0, v)))) }
                if let d = nonBlank(c["description"] as? String) { change["newDescription"] = d }
                changes.append(change)
            }
            out["changes"] = changes
            if changes.isEmpty { problems.append("There's nothing to change.") }
        case "updateQuotationDetails":
            let number = ((p["quotationNumber"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            guard let q = quotation(number) else { problems.append("There's no quotation \(number)."); break }
            out["quotationNumber"] = q.quotationNumber
            if q.status != "Draft" { problems.append("\(q.quotationNumber) is \(q.status.lowercased()); only a draft can be changed.") }
            let before: [String: String] = ["subject": q.subject ?? "", "clientRef": q.clientRef ?? "", "siteRef": q.siteRef ?? "", "keyTerms": q.keyTerms ?? ""]
            var fields: [[String: Any]] = []
            for (key, label) in [("subject", "Subject"), ("clientRef", "Your ref."), ("siteRef", "Site ref."), ("keyTerms", "Key terms")] where p[key] is String {
                fields.append(["key": key, "label": label, "old": before[key] ?? "", "new": (p[key] as? String) ?? ""])
            }
            out["fields"] = fields
            if fields.isEmpty { problems.append("There's nothing to change.") }
        case "duplicateQuotation":
            let number = ((p["quotationNumber"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            guard let q = quotation(number) else { problems.append("There's no quotation \(number)."); break }
            out["quotationNumber"] = q.quotationNumber
            if let to = nonBlank(p["toProjectNumber"] as? String) {
                if let project = db.getProjectByNumber(to) { out["toProjectName"] = project.name } else { problems.append("There's no project \(to).") }
            }
        case "createProject":
            let name = ((p["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { problems.append("The project has no name.") }
            out["jobType"] = normalJobType(p["jobType"])
            out["projectNumber"] = nonBlank(p["projectNumber"] as? String) ?? nextProjectNumber(existingNumbers: db.allProjectNumbers())
            let clientName = ((p["clientName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let siteName = ((p["siteName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if clientName.isEmpty { problems.append("Say which client it's for.") }
            if siteName.isEmpty { problems.append("Say which site it's at.") }
            if let c = db.listClients(includeArchived: false).first(where: { $0.companyName.caseInsensitiveCompare(clientName) == .orderedSame }) {
                out["clientName"] = c.companyName
            } else if !clientName.isEmpty { out["clientNew"] = true }
            if let st = db.listSites(includeArchived: false).first(where: { $0.name.caseInsensitiveCompare(siteName) == .orderedSame }) {
                out["siteName"] = st.name
            } else if !siteName.isEmpty { out["siteNew"] = true }
        case "createBOQ":
            let number = ((p["projectNumber"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            let mode = (p["pricingMode"] as? String) == "Sale" ? "Sale" : "Rental"
            out["pricingMode"] = mode
            if let project = db.getProjectByNumber(number) { out["projectName"] = project.name } else { problems.append("There's no project \(number.isEmpty ? "chosen" : number).") }
            out["items"] = assistantItems(p["items"], mode: mode, problems: &problems)
            if ((out["items"] as? [Any]) ?? []).isEmpty { problems.append("There are no items.") }
        case "createClient":
            let name = ((p["companyName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if name.isEmpty { problems.append("The client has no name.") }
            if db.listClients(includeArchived: true).contains(where: { $0.companyName.caseInsensitiveCompare(name) == .orderedSame }) {
                problems.append("There's already a client called \(name).")
            }
        case "completeTask":
            let key = ((p["taskId"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            let open = db.tasksStore.readAll().filter { !$0.done }
            var found = open.filter { $0.id == key }
            if found.isEmpty, let title = nonBlank(p["title"] as? String) { found = open.filter { $0.title.lowercased().contains(title.lowercased()) } }
            if found.count == 1, let t = found.first { out["taskId"] = t.id; out["title"] = t.title } else {
                problems.append(found.isEmpty ? "No open task matches." : "More than one task matches; say which.")
            }
        default:
            problems.append("The app can't do “\(type)” yet.")
        }
        out["problems"] = problems
        return out
    }

    func quotation(_ number: String) -> Quotation? {
        db.quotationsStore.readAll().first { $0.quotationNumber.caseInsensitiveCompare(number) == .orderedSame }
    }

    func assistantHref(_ p: [String: Any]) -> String? {
        let number = ((p["number"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
        let enc = { (s: String) in s.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? s }
        if (p["page"] as? String) == "project", db.getProjectByNumber(number) != nil { return "project-detail.html?number=\(enc(number))" }
        if let q = db.quotationsStore.readAll().first(where: { $0.quotationNumber.caseInsensitiveCompare(number) == .orderedSame }) {
            return "quotation-editor.html?id=\(enc(q.id))"
        }
        return nil
    }

    // ---- assistant:run — a proposal the person confirmed ----

    func handleAssistantRun(id: String, payload: [String: Any]) {
        let p = (payload["proposal"] as? [String: Any]) ?? [:]
        func reply(_ ok: Bool, _ message: String, href: String? = nil) {
            var out: [String: Any] = ["ok": ok, (ok ? "message" : "error"): message]
            if let h = href { out["href"] = h }
            callback(id: id, ok: true, resultJson: jsonText(out), error: nil)
        }
        let lines: () -> [ImportedQuotationLine] = {
            ((p["items"] as? [[String: Any]]) ?? []).map { i in
                ImportedQuotationLine(kind: i["kind"] as? String, section: i["section"] as? String, itemCode: i["itemCode"] as? String,
                                      description: (i["description"] as? String) ?? "", unit: (i["unit"] as? String) ?? "pc",
                                      quantity: (i["quantity"] as? NSNumber)?.doubleValue ?? 1, unitPrice: (i["unitPrice"] as? NSNumber)?.doubleValue ?? 0)
            }
        }
        switch (p["type"] as? String) ?? "" {
        case "createQuotation":
            guard let project = db.getProjectByNumber(((p["projectNumber"] as? String) ?? "").trimmingCharacters(in: .whitespaces)) else { reply(false, "Project not found."); return }
            let q = db.createImportedQuotation(projectId: project.id, projectNumber: project.projectNumber,
                                               pricingMode: (p["pricingMode"] as? String) == "Sale" ? "Sale" : "Rental",
                                               subject: p["subject"] as? String, clientRef: p["clientRef"] as? String,
                                               currency: p["currency"] as? String, lines: lines())
            db.logActivity(projectId: project.id, "Quotation made by the assistant", reference: q.quotationNumber)
            reply(true, "\(q.quotationNumber) made, with \(lines().count) line\(lines().count == 1 ? "" : "s").", href: "quotation-editor.html?id=\(q.id)")
        case "addQuotationItems":
            let number = ((p["quotationNumber"] as? String) ?? "").trimmingCharacters(in: .whitespaces)
            guard let q = db.quotationsStore.readAll().first(where: { $0.quotationNumber.caseInsensitiveCompare(number) == .orderedSame }) else { reply(false, "Quotation not found."); return }
            guard q.status == "Draft" else { reply(false, "\(q.quotationNumber) is \(q.status.lowercased()); only a draft can be changed."); return }
            db.appendImportedLines(to: q, lines: lines())
            reply(true, "\(lines().count) line\(lines().count == 1 ? "" : "s") added to \(q.quotationNumber).", href: "quotation-editor.html?id=\(q.id)")
        case "createTask":
            var task: [String: Any] = ["title": p["title"] ?? "", "notes": p["notes"] ?? NSNull(), "dueDate": p["dueDate"] ?? NSNull(),
                                       "dueTime": p["dueTime"] ?? NSNull(), "endTime": p["endTime"] ?? NSNull(), "assignee": p["assignee"] ?? NSNull(),
                                       "team": p["team"] ?? NSNull()]
            if let n = nonBlank(p["projectNumber"] as? String), let project = db.getProjectByNumber(n) { task["projectId"] = project.id }
            let r = db.saveTask(task)
            if r.ok { reply(true, nonBlank(p["endTime"] as? String) != nil ? "Event added to the calendar." : "Task added.", href: nonBlank(p["endTime"] as? String) != nil ? "calendar.html" : "tasks.html") } else { reply(false, r.error ?? "The task couldn't be added.") }
        case "editQuotationItems":
            guard let q = quotation(((p["quotationNumber"] as? String) ?? "").trimmingCharacters(in: .whitespaces)) else { reply(false, "Quotation not found."); return }
            guard q.status == "Draft" else { reply(false, "\(q.quotationNumber) is \(q.status.lowercased()); only a draft can be changed."); return }
            var done = 0
            var failed: [String] = []
            for c in (p["changes"] as? [[String: Any]]) ?? [] {
                guard let lineId = c["lineId"] as? String else { continue }
                let error: String?
                if (c["remove"] as? Bool) == true {
                    error = db.removeQuotationLineItem(id: lineId)
                } else {
                    error = db.updateQuotationLineItem(id: lineId, quantity: (c["quantity"] as? NSNumber)?.doubleValue,
                                                       appliedUnitPrice: (c["unitPrice"] as? NSNumber)?.doubleValue,
                                                       description: c["newDescription"] as? String)
                }
                if let e = error { failed.append(e) } else { done += 1 }
            }
            if done == 0 { reply(false, failed.first ?? "Nothing was changed."); return }
            reply(true, "\(done) line\(done == 1 ? "" : "s") of \(q.quotationNumber) changed\(failed.isEmpty ? "" : " (\(failed.count) couldn't be)").",
                  href: "quotation-editor.html?id=\(q.id)")
        case "updateQuotationDetails":
            guard let q = quotation(((p["quotationNumber"] as? String) ?? "").trimmingCharacters(in: .whitespaces)) else { reply(false, "Quotation not found."); return }
            var fields: [String: Any] = [:]
            for f in (p["fields"] as? [[String: Any]]) ?? [] { if let k = f["key"] as? String { fields[k] = (f["new"] as? String) ?? "" } }
            if let error = db.updateQuotationLetterFields(id: q.id, payload: fields) { reply(false, error); return }
            reply(true, "\(q.quotationNumber) updated.", href: "quotation-editor.html?id=\(q.id)")
        case "duplicateQuotation":
            guard let q = quotation(((p["quotationNumber"] as? String) ?? "").trimmingCharacters(in: .whitespaces)) else { reply(false, "Quotation not found."); return }
            let to = nonBlank(p["toProjectNumber"] as? String).flatMap { db.getProjectByNumber($0)?.id }
            switch db.duplicateQuotation(id: q.id, toProjectId: to) {
            case .success(let copy): reply(true, "\(copy.quotationNumber) made, a copy of \(q.quotationNumber).", href: "quotation-editor.html?id=\(copy.id)")
            case .failure(let e): reply(false, e.message)
            }
        case "createProject":
            let name = ((p["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let clientName = ((p["clientName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let siteName = ((p["siteName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, !clientName.isEmpty, !siteName.isEmpty else { reply(false, "A project needs a name, a client and a site."); return }
            let existing = db.allProjectNumbers()
            let number = nonBlank(p["projectNumber"] as? String) ?? nextProjectNumber(existingNumbers: existing)
            let check = validateProjectNumber(number, existingNumbers: existing)
            guard check.valid else { reply(false, check.reason ?? "That project number can't be used."); return }
            let client = db.listClients(includeArchived: false).first { $0.companyName.caseInsensitiveCompare(clientName) == .orderedSame }
                ?? db.createClient(["companyName": clientName])
            let site = db.listSites(includeArchived: false).first { $0.name.caseInsensitiveCompare(siteName) == .orderedSame }
                ?? db.createSite(["name": siteName])
            let project = db.createProject(projectNumber: number, name: name, clientId: client.id, siteId: site.id)
            _ = db.updateProject(id: project.id, payload: ["jobType": normalJobType(p["jobType"])], logChange: false)
            storage.createProjectFolders(number)
            reply(true, "Project \(number) \(name) made.", href: "project-detail.html?number=\(number.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? number)")
        case "createBOQ":
            guard let project = db.getProjectByNumber(((p["projectNumber"] as? String) ?? "").trimmingCharacters(in: .whitespaces)) else { reply(false, "Project not found."); return }
            let mode = (p["pricingMode"] as? String) == "Sale" ? "Sale" : "Rental"
            let boq = db.createBOQ(projectId: project.id, projectNumber: project.projectNumber, pricingMode: mode, withDefaultItems: false)
            if let structure = nonBlank(p["structure"] as? String) {
                _ = db.updateBOQDetails(id: boq.id, pricingMode: nil, markupPercent: nil, structure: structure, updateStructure: true)
            }
            // Each item priced as the BOQ prices it: from the material list
            // (with its markup) when found there, else as given.
            let byCode = Dictionary(db.allPriceListItems().filter { !$0.isArchived }.map { ($0.itemCode.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })
            let rates = db.conversionRates()
            let current = db.getBOQ(id: boq.id) ?? boq
            var added = 0
            for i in (p["items"] as? [[String: Any]]) ?? [] {
                let description = ((i["description"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let quantity = (i["quantity"] as? NSNumber)?.doubleValue ?? 1
                let given = (i["unitPrice"] as? NSNumber)?.doubleValue
                if let code = nonBlank(i["itemCode"] as? String), let pl = byCode[code.uppercased()] {
                    let list = db.basePrice(pl, mode: mode, rates: rates)
                    let priced = db.boqPrice(for: pl, mode: mode, markupPercent: current.markupOnRates == true ? 0 : (current.markupPercent ?? 0), rates: rates)
                    let fromList = (i["priceFromList"] as? Bool) == true
                    _ = db.addBOQLineItem(boqId: boq.id, sourceKey: pl.sourceKey, priceListItemId: pl.id, itemCode: pl.itemCode,
                                          description: description.isEmpty ? pl.itemName : description, unit: pl.unit, quantity: quantity,
                                          priceListUnitPrice: list, appliedUnitPrice: fromList || given == nil ? (priced ?? list ?? 0) : (given ?? 0),
                                          weightKg: pl.weightKg, section: pl.category)
                } else {
                    guard !description.isEmpty else { continue }
                    _ = db.addBOQLineItem(boqId: boq.id, sourceKey: nil, priceListItemId: nil, itemCode: (i["itemCode"] as? String) ?? "",
                                          description: description, unit: (i["unit"] as? String) ?? "pc", quantity: quantity,
                                          priceListUnitPrice: nil, appliedUnitPrice: given ?? 0, weightKg: nil,
                                          section: (i["kind"] as? String) == "Delivery" ? "Delivery" : nil)
                }
                added += 1
            }
            reply(true, "\(boq.boqNumber) made, with \(added) line\(added == 1 ? "" : "s").", href: "boq-editor.html?id=\(boq.id)")
        case "createClient":
            let name = ((p["companyName"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { reply(false, "The client has no name."); return }
            var fields: [String: Any] = [:]
            for k in ["companyName", "contactPerson", "phone", "email", "address", "addressLine2", "addressLine3", "notes"] { if let v = p[k] as? String { fields[k] = v } }
            let c = db.createClient(fields)
            reply(true, "Client \(c.companyName) added.", href: "clients.html")
        case "completeTask":
            guard let taskId = p["taskId"] as? String else { reply(false, "Task not found."); return }
            if let error = db.setTaskDone(id: taskId, done: true) { reply(false, error) } else { reply(true, "Marked done.", href: "tasks.html") }
        default:
            reply(false, "That can't be done from here.")
        }
    }
}

final class CloudBackupManager {
    /// Posted by every database save.
    static let dataSaved = Notification.Name("ScaffoldPro.dataSaved")
    /// Where copies went before they went straight into the folder.
    static let backupFolderName = "ScaffoldPro Backup"
    static let historyDays = 30

    let db: AppDatabase
    let storage: FileStorage
    let queue = DispatchQueue(label: "ScaffoldPro.cloudBackup", qos: .utility)
    let defaults = UserDefaults.standard
    var timer: Timer?
    var pending: DispatchWorkItem?
    /// Set while a restore swaps the data in (main thread).
    var paused = false
    /// A backup is being copied (main thread).
    var running = false

    enum Key {
        static let enabled = "cloudBackup.enabled"
        static let folder = "cloudBackup.folder"
        static let lastBackup = "cloudBackup.lastBackupAt"
        static let lastCopied = "cloudBackup.lastFilesCopied"
        static let lastError = "cloudBackup.lastError"
    }

    init(db: AppDatabase, storage: FileStorage) {
        self.db = db
        self.storage = storage
    }

    /// ~/Library/Mobile Documents/com~apple~CloudDocs — "iCloud Drive" in Finder.
    static var iCloudDrive: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    static var defaultFolder: URL {
        iCloudDrive.appendingPathComponent("Proficiency", isDirectory: true).appendingPathComponent("William's Work", isDirectory: true)
    }

    var enabled: Bool {
        get { defaults.object(forKey: Key.enabled) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    var usingDefault: Bool { defaults.string(forKey: Key.folder) == nil }

    var folder: URL {
        defaults.string(forKey: Key.folder).map { URL(fileURLWithPath: $0, isDirectory: true) } ?? CloudBackupManager.defaultFolder
    }

    func setFolder(_ url: URL?) {
        if let url = url { defaults.set(url.path, forKey: Key.folder) } else { defaults.removeObject(forKey: Key.folder) }
    }

    func status() -> CloudBackupStatus {
        let drive = CloudBackupManager.iCloudDrive.path
        let path = folder.path
        let display = path.hasPrefix(drive + "/")
            ? (["iCloud Drive"] + path.dropFirst(drive.count + 1).split(separator: "/").map(String.init)).joined(separator: " › ")
            : path
        let last = defaults.object(forKey: Key.lastBackup) as? Double
        return CloudBackupStatus(
            enabled: enabled, folder: path, folderDisplay: display, usingDefault: usingDefault,
            lastBackupAt: last.map { ISO8601DateFormatter().string(from: Date(timeIntervalSince1970: $0)) },
            lastFilesCopied: defaults.object(forKey: Key.lastCopied) as? Int,
            lastError: defaults.string(forKey: Key.lastError), running: running)
    }

    /// Starts the automatic schedule (main thread).
    func start() {
        NotificationCenter.default.addObserver(forName: CloudBackupManager.dataSaved, object: nil, queue: .main) { [weak self] _ in
            self?.schedule(after: 60)
        }
        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in self?.backUpNow() }
        schedule(after: 20)
    }

    /// Backs up after a quiet spell, so a burst of saves makes one backup.
    func schedule(after seconds: TimeInterval) {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.backUpNow() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: item)
    }

    /// Copies what changed (main thread; the copying runs in the background).
    func backUpNow(completion: ((CloudBackupStatus) -> Void)? = nil) {
        guard enabled, !paused, !running else { completion?(status()); return }
        running = true
        let target = folder
        let startedAt = Date()
        let since = (defaults.object(forKey: Key.lastBackup) as? Double).map { Date(timeIntervalSince1970: $0) }
        queue.async { [weak self] in
            guard let self = self else { return }
            let result: Result<Int, BackupError>
            do {
                result = .success(try self.copyChanges(into: target, since: since))
            } catch let e as BackupError {
                result = .failure(e)
            } catch {
                result = .failure(BackupError(message: error.localizedDescription))
            }
            DispatchQueue.main.async {
                self.running = false
                switch result {
                case .success(let copied):
                    self.defaults.set(startedAt.timeIntervalSince1970, forKey: Key.lastBackup)
                    self.defaults.set(copied, forKey: Key.lastCopied)
                    self.defaults.removeObject(forKey: Key.lastError)
                case .failure(let e):
                    self.defaults.set(e.message, forKey: Key.lastError)
                }
                completion?(self.status())
            }
        }
    }

    // MARK: copying (background queue)

    func copyChanges(into target: URL, since: Date?) throws -> Int {
        let fm = FileManager.default
        if !fm.fileExists(atPath: target.path) {
            let parent = target.deletingLastPathComponent()
            guard fm.fileExists(atPath: parent.path) else {
                throw BackupError(message: "The “\(parent.lastPathComponent)” folder wasn't found in iCloud Drive. Check that iCloud Drive is on and the shared “\(parent.lastPathComponent)” folder has been accepted (it shows in Finder under iCloud Drive), or choose the folder here.")
            }
            try fm.createDirectory(at: target, withIntermediateDirectories: true)
        }
        // The copy goes straight into the chosen folder (William's Work).
        let root = target
        // Backups made before this went into a "ScaffoldPro Backup" folder
        // inside it: move those up once, so nothing is copied twice.
        let older = target.appendingPathComponent(CloudBackupManager.backupFolderName, isDirectory: true)
        if fm.fileExists(atPath: older.path) {
            for name in (try? fm.contentsOfDirectory(atPath: older.path)) ?? [] where !name.hasPrefix(".") {
                let destination = root.appendingPathComponent(name)
                if !fm.fileExists(atPath: destination.path) {
                    try? fm.moveItem(at: older.appendingPathComponent(name), to: destination)
                }
            }
            if ((try? fm.contentsOfDirectory(atPath: older.path)) ?? ["?"]).filter({ !$0.hasPrefix(".") }).isEmpty {
                try? fm.removeItem(at: older)
            }
        }

        var totals = (copied: 0, files: 0, bytes: Int64(0), failed: [String]())
        func mirror(_ source: URL, _ name: String) {
            guard fm.fileExists(atPath: source.path) else { return }
            let r = CloudBackupManager.mirrorFolder(source, to: root.appendingPathComponent(name, isDirectory: true), since: since)
            totals.copied += r.copied
            totals.files += r.files
            totals.bytes += r.bytes
            totals.failed += r.failed
        }
        mirror(db.dataDir, "Database")
        mirror(storage.projectsRoot, "Projects")
        mirror(storage.administrationRoot, "Administration")

        // The manifest makes the copy restorable with "Restore from Folder…".
        let projectCount = ((try? fm.contentsOfDirectory(atPath: storage.projectsRoot.path)) ?? []).filter { !$0.hasPrefix(".") }.count
        let manifest = BackupManifest(app: "ScaffoldPro", formatVersion: 1, createdAt: nowISO(), kind: "iCloud",
                                      sourceAppRoot: storage.appRoot.path, projectCount: projectCount,
                                      fileCount: totals.files, totalBytes: totals.bytes)
        let config = root.appendingPathComponent("Configuration", isDirectory: true)
        try fm.createDirectory(at: config, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: config.appendingPathComponent("manifest.json"), options: .atomic)
        let readme = """
        ScaffoldPro — automatic iCloud backup, kept up to date by the app.

          Database/          clients, projects, price lists, BOQs, quotations,
                             invoices, delivery notes, workers, settings
          Projects/          every project folder, with drawings, PDFs and Word copies
          Administration/    worker and company documents
          Database History/  the database as it was each day (last \(CloudBackupManager.historyDays) days)

        To restore it: ScaffoldPro → Settings → Backup & Restore →
        "Restore from Folder…" and choose this folder ("\(root.lastPathComponent)").
        Files deleted in the app are kept here; nothing is removed from this copy.
        """
        try Data(readme.utf8).write(to: config.appendingPathComponent("README.txt"), options: .atomic)

        // A dated copy of the database once a day; the oldest are removed.
        let history = root.appendingPathComponent("Database History", isDirectory: true)
        try fm.createDirectory(at: history, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let today = history.appendingPathComponent(f.string(from: Date()), isDirectory: true)
        if !fm.fileExists(atPath: today.path) { try? fm.copyItem(at: db.dataDir, to: today) }
        let days = ((try? fm.contentsOfDirectory(atPath: history.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted()
        for old in days.dropLast(CloudBackupManager.historyDays) {
            try? fm.removeItem(at: history.appendingPathComponent(old, isDirectory: true))
        }

        if !totals.failed.isEmpty {
            throw BackupError(message: "\(totals.failed.count) file\(totals.failed.count == 1 ? "" : "s") couldn't be copied to iCloud, e.g. \(totals.failed[0]). The rest are backed up; it will try again.")
        }
        return totals.copied
    }

    /// Copies every file in `source` that's new or changed since `since`
    /// (or differs in size) into `destination`, keeping the folder layout.
    /// Nothing in `destination` is deleted. Files iCloud has moved off this
    /// Mac to save space (".name.icloud") count as there.
    /// A file iCloud keeps only in the cloud (".name.icloud") isn't copied
    /// yet: iCloud is asked to bring it down, and it's counted in `waiting`
    /// so the next run copies it.
    static func mirrorFolder(_ source: URL, to destination: URL, since: Date?) -> (copied: Int, files: Int, bytes: Int64, failed: [String], waiting: Int) {
        let fm = FileManager.default
        var result = (copied: 0, files: 0, bytes: Int64(0), failed: [String](), waiting: 0)
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        guard let walker = fm.enumerator(at: source, includingPropertiesForKeys: keys, options: []) else { return result }
        let base = source.standardizedFileURL.pathComponents.count
        for case let url as URL in walker {
            let name = url.lastPathComponent
            if name.hasPrefix(".") {
                if name.hasSuffix(".icloud"), name.count > ".x.icloud".count - 1 {
                    let real = url.deletingLastPathComponent().appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
                    let out = url.standardizedFileURL.pathComponents.dropFirst(base).dropLast()
                        .reduce(destination) { $0.appendingPathComponent($1) }.appendingPathComponent(real.lastPathComponent)
                    if !fm.fileExists(atPath: out.path) {
                        try? fm.startDownloadingUbiquitousItem(at: real)
                        result.waiting += 1
                    }
                } else if (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                    walker.skipDescendants()
                }
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let relative = url.standardizedFileURL.pathComponents.dropFirst(base)
            guard !relative.isEmpty else { continue }
            result.files += 1
            result.bytes += Int64(values.fileSize ?? 0)
            let out = relative.reduce(destination) { $0.appendingPathComponent($1) }
            let changed = since.map { (values.contentModificationDate ?? .distantFuture) > $0 } ?? true
            let needsCopy: Bool
            if fm.fileExists(atPath: out.path) {
                let size = (try? out.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
                needsCopy = changed || size != values.fileSize
            } else if fm.fileExists(atPath: out.deletingLastPathComponent().appendingPathComponent(".\(out.lastPathComponent).icloud").path) {
                needsCopy = changed
            } else {
                needsCopy = true
            }
            guard needsCopy else { continue }
            do {
                try fm.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
                let temp = out.deletingLastPathComponent().appendingPathComponent(".\(out.lastPathComponent).scaffoldpro-copy")
                try? fm.removeItem(at: temp)
                try fm.copyItem(at: url, to: temp)
                if fm.fileExists(atPath: out.path) {
                    _ = try fm.replaceItemAt(out, withItemAt: temp)
                } else {
                    try fm.moveItem(at: temp, to: out)
                }
                result.copied += 1
            } catch {
                result.failed.append("\(relative.joined(separator: "/")) (\(error.localizedDescription))")
            }
        }
        return result
    }
}

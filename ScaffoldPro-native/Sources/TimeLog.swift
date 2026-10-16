import Foundation

// Time log (Schedule › Time, js/time-log.js): a chain. Nobody presses start
// or stop: each entry says what was just finished, and its time runs from
// the entry before it (the same person, the same day) to now. The first
// entry of a day only marks the start. The lengths are worked out in the
// page, so changing or removing one entry moves its neighbour with it.

struct TimeEntry: Codable {
    var id: String
    var text: String
    /// When it was finished: local yyyy-MM-ddTHH:mm:ss.
    var at: String
    /// The task it was for, if any (TeamTask.id).
    var taskId: String?
    var person: String
    var createdAt: String
    var updatedAt: String
}

extension AppDatabase {
    /// A moment as local yyyy-MM-ddTHH:mm:ss.
    func localStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: date)
    }

    /// A local yyyy-MM-ddTHH:mm[:ss] as yyyy-MM-ddTHH:mm:ss, or nil.
    func validStamp(_ value: String?) -> String? {
        guard let v = nonBlank(value), validDay(v) != nil, v.count >= 16 else { return nil }
        let rest = v.dropFirst(11)
        guard v.dropFirst(10).first == "T", let time = validTime(String(rest.prefix(5))) else { return nil }
        let secs = rest.count >= 8 ? Int(rest.dropFirst(6).prefix(2)) ?? 0 : 0
        guard (0..<60).contains(secs) else { return nil }
        return "\(v.prefix(10))T\(time):\(String(format: "%02d", secs))"
    }

    func isMine(_ e: TimeEntry) -> Bool { e.person.lowercased() == TeamSync.memberName.lowercased() }

    /// This person's entries from `from` to `to` (yyyy-MM-dd, inclusive; nil = all), oldest first.
    func listTimeEntries(from: String?, to: String?) -> [TimeEntry] {
        let lo = validDay(from) ?? "0000-00-00", hi = validDay(to) ?? "9999-99-99"
        return timeEntriesStore.readAll()
            .filter { e in isMine(e) && String(e.at.prefix(10)) >= lo && String(e.at.prefix(10)) <= hi }
            .sorted { $0.at < $1.at }
    }

    func addTimeEntry(_ payload: [String: Any]) -> LeadSaveResult {
        guard let words = text(payload, "text") else { return LeadSaveResult(ok: false, error: "Say what you just finished.") }
        let at = validStamp(text(payload, "at")) ?? localStamp(Date())
        let e = TimeEntry(id: makeId("time"), text: words, at: at, taskId: text(payload, "taskId"),
                          person: TeamSync.memberName, createdAt: nowISO(), updatedAt: nowISO())
        timeEntriesStore.insert(e)
        return LeadSaveResult(ok: true, error: nil, id: e.id)
    }

    /// Changes an entry's words, time or task (only the keys sent; taskId "" unlinks).
    func saveTimeEntry(_ payload: [String: Any]) -> String? {
        var all = timeEntriesStore.readAll()
        guard let id = text(payload, "id"), let i = all.firstIndex(where: { $0.id == id && isMine($0) }) else { return "Entry not found." }
        if payload["text"] != nil {
            guard let words = text(payload, "text") else { return "Say what you finished." }
            all[i].text = words
        }
        if payload["at"] != nil {
            guard let at = validStamp(text(payload, "at")) else { return "Enter a valid time." }
            all[i].at = at
        }
        if payload["taskId"] != nil { all[i].taskId = text(payload, "taskId") }
        all[i].updatedAt = nowISO()
        timeEntriesStore.writeAll(all)
        return nil
    }

    func deleteTimeEntry(id: String) -> String? {
        var all = timeEntriesStore.readAll()
        guard all.contains(where: { $0.id == id && isMine($0) }) else { return "Entry not found." }
        all.removeAll { $0.id == id }
        timeEntriesStore.writeAll(all)
        return nil
    }
}

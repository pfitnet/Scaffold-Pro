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
// MARK: - Worker employment agreements (Batch 213)
//
// Made when a worker is added (Admin › Workers), from the company's
// "Simple Employment Agreement" template: a cover page, the terms, and a
// page to sign. Export PDF / Word / Print as the quotations; someone the
// Team page marks as signing worker agreements signs and chops it for the
// employer; the copy signed by both is uploaded into the worker's
// Contracts folder.
// =====================================================================

/// 1300 → "壹仟叁佰元正"; 1350.5 → "壹仟叁佰伍拾元伍角" (as on cheques).
func chineseCapitalAmount(_ value: Double) -> String {
    let digits = ["零", "壹", "貳", "叁", "肆", "伍", "陸", "柒", "捌", "玖"]
    let cents = Int((max(0, value) * 100).rounded())
    let whole = cents / 100, jiao = (cents % 100) / 10, fen = cents % 10
    // 0–9999, with 零 for gaps inside it ("壹仟零伍拾").
    func group(_ n: Int) -> String {
        let units = ["仟", "佰", "拾", ""]
        let ds = [n / 1000, n / 100 % 10, n / 10 % 10, n % 10]
        var s = "", gap = false
        for (i, d) in ds.enumerated() {
            if d == 0 { if !s.isEmpty { gap = true }; continue }
            if gap { s += "零"; gap = false }
            s += digits[d] + units[i]
        }
        return s
    }
    var out = ""
    var gap = false
    for (n, unit) in [(whole / 100_000_000, "億"), (whole / 10_000 % 10_000, "萬"), (whole % 10_000, "")] {
        if n == 0 { if !out.isEmpty { gap = true }; continue }
        if !out.isEmpty && (gap || n < 1000) { out += "零" }
        out += group(n) + unit
        gap = false
    }
    if out.isEmpty { out = "零" }
    out += "元"
    if jiao == 0 && fen == 0 { return out + "正" }
    out += jiao > 0 ? digits[jiao] + "角" : "零"
    if fen > 0 { out += digits[fen] + "分" }
    return out
}

/// 1–99 in everyday Chinese numerals: 八, 十二, 三十.
func chineseSmallNumber(_ n: Int) -> String {
    let d = ["零", "一", "二", "三", "四", "五", "六", "七", "八", "九"]
    if n < 10 { return d[max(0, n)] }
    if n < 20 { return "十" + (n % 10 == 0 ? "" : d[n % 10]) }
    return d[n / 10] + "十" + (n % 10 == 0 ? "" : d[n % 10])
}

/// "08:00" → "早上八時正 (8:00 a.m.)"; "18:30" → "晚上六時三十分 (6:30 p.m.)".
func chineseClockTime(_ hhmm: String) -> String {
    let parts = hhmm.split(separator: ":").compactMap { Int($0) }
    let h = parts.first.map { min(23, max(0, $0)) } ?? 8
    let m = parts.count > 1 ? min(59, max(0, parts[1])) : 0
    let period = h < 6 ? "凌晨" : h < 12 ? "早上" : h < 13 ? "中午" : h < 18 ? "下午" : "晚上"
    let twelve = h % 12 == 0 ? 12 : h % 12
    let minutes = m == 0 ? "時正" : "時\(m < 10 ? "零" : "")\(chineseSmallNumber(m))分"
    return "\(period)\(chineseSmallNumber(twelve))\(minutes) (\(twelve):\(String(format: "%02d", m)) \(h < 12 ? "a.m." : "p.m."))"
}

/// "2026-10-08" → "2026年10月8日".
func chineseDate(_ ymd: String) -> String {
    let p = ymd.prefix(10).split(separator: "-").compactMap { Int($0) }
    guard p.count == 3 else { return ymd }
    return "\(p[0])年\(p[1])月\(p[2])日"
}

let agreementDayFormatter: DateFormatter = {
    let f = DateFormatter()
    f.calendar = Calendar(identifier: .gregorian)
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd"
    return f
}()

extension AppDatabase {
    /// Everyone the Team page marks as signing worker agreements.
    func agreementSigners() -> [String] {
        teamMembershipsStore.readAll().filter { $0.canSignAgreements == true }.map { $0.name }.sorted()
    }

    func workerAgreement(workerId: String) -> WorkerAgreement? {
        workerAgreementsStore.readAll().filter { $0.workerId == workerId }.max { $0.createdAt < $1.createdAt }.map { repairedDates($0) }
    }

    /// Agreements made by Batch 213 could have no dates (its date formatter
    /// was never set up): the day it was made, and the worker's start date
    /// (or that day), are filled in and kept.
    func repairedDates(_ agreement: WorkerAgreement) -> WorkerAgreement {
        let isDay = { (s: String) in s.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil }
        guard !isDay(agreement.agreementDate) || !isDay(agreement.startDate) else { return agreement }
        var a = agreement
        let made = String(a.createdAt.prefix(10))
        let day = isDay(made) ? made : agreementDayFormatter.string(from: Date())
        if !isDay(a.agreementDate) { a.agreementDate = day }
        if !isDay(a.startDate) {
            let start = getWorker(id: a.workerId).flatMap { nonBlank($0.startDate) }.map { String($0.prefix(10)) }
            a.startDate = start.flatMap { isDay($0) ? $0 : nil } ?? a.agreementDate
        }
        var all = workerAgreementsStore.readAll()
        if let i = all.firstIndex(where: { $0.id == a.id }) { all[i] = a; workerAgreementsStore.writeAll(all) }
        return a
    }

    /// The Workers page's list: each worker with where their agreement is
    /// (0 none, 1 made, 2 signed & chopped for the employer, 3 signed by
    /// the worker too), their documents, and how many expire within 30 days.
    func workerRoster(includeArchived: Bool) -> [WorkerRosterEntry] {
        let agreements = workerAgreementsStore.readAll()
        let docs = workerDocumentsStore.readAll().filter { !$0.isArchived }
        let today = Calendar.current.startOfDay(for: Date())
        let soon = Calendar.current.date(byAdding: .day, value: 30, to: today) ?? today
        return listWorkers(includeArchived: includeArchived).map { w in
            let a = agreements.filter { $0.workerId == w.id }.max { $0.createdAt < $1.createdAt }
            let stage = a == nil ? 0 : a?.signedCopyPath != nil ? 3 : a?.employerSignedBy != nil ? 2 : 1
            let mine = docs.filter { $0.workerId == w.id }
            let expiring = mine.filter { d in
                guard let e = d.expiryDate, let date = agreementDayFormatter.date(from: String(e.prefix(10))) else { return false }
                return date <= soon
            }.count
            return WorkerRosterEntry(worker: w, agreementNumber: workerAgreementNumber(w), stage: stage,
                                     signedBy: a?.employerSignedBy, documents: mine.count, expiring: expiring)
        }
    }

    func getWorkerAgreement(id: String) -> WorkerAgreement? {
        workerAgreementsStore.readAll().first { $0.id == id }.map { repairedDates($0) }
    }

    func workerAgreementNumber(_ worker: Worker) -> String { "\(worker.workerNumber)-EA" }

    /// The agreement for a new worker: dated today, starting on their start
    /// date (or today), as a scaffolder at their daily wage (or HK$1,300),
    /// 8 a.m. to 6 p.m., paid on the 7th, 7 days' notice.
    @discardableResult
    func createWorkerAgreement(for worker: Worker) -> WorkerAgreement {
        if let existing = workerAgreement(workerId: worker.id) { return existing }
        let today = agreementDayFormatter.string(from: Date())
        let agreement = WorkerAgreement(
            id: makeId("agreement"), workerId: worker.id, agreementDate: today,
            startDate: nonBlank(worker.startDate).map { String($0.prefix(10)) } ?? today,
            position: nonBlank(worker.position) ?? "Scaffolder",
            dailyWage: worker.dailyWage.flatMap { $0 > 0 ? $0 : nil } ?? 1300,
            hoursFrom: "08:00", hoursTo: "18:00", payDay: 7, noticeDays: 7,
            signatory: agreementSigners().first, createdAt: nowISO(), updatedAt: nowISO())
        workerAgreementsStore.insert(agreement)
        return agreement
    }

    /// Its terms. Changing them after the employer signed takes the
    /// signature off (the signed PDF stays in the folder) — it has to be
    /// signed again.
    func updateWorkerAgreement(id: String, payload: [String: Any]) -> String? {
        var all = workerAgreementsStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return "Agreement not found." }
        var a = all[i]
        func terms(_ a: WorkerAgreement) -> String { "\(a.agreementDate)|\(a.startDate)|\(a.position)|\(a.dailyWage)|\(a.hoursFrom)|\(a.hoursTo)|\(a.payDay)|\(a.noticeDays)" }
        let before = terms(a)
        func day(_ key: String) -> String? {
            guard let v = nonBlank(payload[key] as? String) else { return nil }
            return v.range(of: #"^\d{4}-\d{2}-\d{2}"#, options: .regularExpression) != nil ? String(v.prefix(10)) : nil
        }
        func time(_ key: String) -> String? {
            guard let v = nonBlank(payload[key] as? String) else { return nil }
            return v.range(of: #"^\d{1,2}:\d{2}$"#, options: .regularExpression) != nil ? v : nil
        }
        func number(_ key: String) -> Double? {
            if let d = payload[key] as? Double { return d }
            if let n = payload[key] as? Int { return Double(n) }
            return (payload[key] as? String).flatMap { Double($0.replacingOccurrences(of: ",", with: "")) }
        }
        if payload.keys.contains("agreementDate") { guard let v = day("agreementDate") else { return "Choose the agreement's date." }; a.agreementDate = v }
        if payload.keys.contains("startDate") { guard let v = day("startDate") else { return "Choose the date the job starts." }; a.startDate = v }
        if payload.keys.contains("position") { a.position = nonBlank(payload["position"] as? String) ?? "Scaffolder" }
        if payload.keys.contains("dailyWage") {
            guard let v = number("dailyWage"), v > 0 else { return "Enter the daily wage." }
            a.dailyWage = (v * 100).rounded() / 100
        }
        if payload.keys.contains("hoursFrom") { guard let v = time("hoursFrom") else { return "Enter when work starts, e.g. 08:00." }; a.hoursFrom = v }
        if payload.keys.contains("hoursTo") { guard let v = time("hoursTo") else { return "Enter when work ends, e.g. 18:00." }; a.hoursTo = v }
        if payload.keys.contains("payDay") {
            guard let v = number("payDay"), v >= 1, v <= 28 else { return "Wages are paid on a day from the 1st to the 28th." }
            a.payDay = Int(v)
        }
        if payload.keys.contains("noticeDays") {
            guard let v = number("noticeDays"), v >= 0, v <= 365 else { return "Enter the days of notice." }
            a.noticeDays = Int(v)
        }
        if payload.keys.contains("signatory") {
            let v = nonBlank(payload["signatory"] as? String)
            a.signatory = v.flatMap { s in agreementSigners().first { $0.lowercased() == s.lowercased() } }
        }
        if before != terms(a) && a.employerSignedBy != nil {
            a.employerSignedBy = nil
            a.employerSignedAt = nil
            a.employerSignedPath = nil
        }
        a.updatedAt = nowISO()
        all[i] = a
        workerAgreementsStore.writeAll(all)
        return nil
    }

    func setWorkerAgreementEmployerSigned(id: String, by signer: String?, path: String?) {
        var all = workerAgreementsStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].employerSignedBy = signer
        all[i].employerSignedAt = signer == nil ? nil : nowISO()
        all[i].employerSignedPath = path
        if let signer = signer { all[i].signatory = signer }
        all[i].updatedAt = nowISO()
        workerAgreementsStore.writeAll(all)
    }

    func setWorkerAgreementSignedCopy(id: String, path: String?) {
        var all = workerAgreementsStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return }
        all[i].signedCopyPath = path
        all[i].signedCopyAt = path == nil ? nil : nowISO()
        all[i].updatedAt = nowISO()
        workerAgreementsStore.writeAll(all)
    }

    func workerAgreementPage(workerId: String) -> WorkerAgreementPage? {
        guard let worker = getWorker(id: workerId) else { return nil }
        let a = workerAgreement(workerId: workerId)
        let me = TeamSync.memberName
        var missing: [String] = []
        if nonBlank(worker.idNumber) == nil { missing.append("the worker’s ID card number") }
        if let a = a, let who = nonBlank(a.signatory), nonBlank(membership(who)?.idNumber) == nil {
            missing.append("\(who)’s ID card number (Team page)")
        }
        return WorkerAgreementPage(
            agreement: a, number: workerAgreementNumber(worker), signers: agreementSigners(), me: me,
            canSign: membership(me)?.canSignAgreements == true,
            hasSignature: FileManager.default.fileExists(atPath: signatureImageURL(me, "signature").path),
            employerSignedExists: a?.employerSignedPath.map { fileIsPresent($0) } ?? false,
            signedCopyExists: a?.signedCopyPath.map { fileIsPresent($0) } ?? false,
            missing: missing)
    }

    /// The agreement's words: the worker's and the terms' details in the
    /// company's template. `signer`: who signs for the employer.
    func agreementContent(_ a: WorkerAgreement, worker: Worker, signer: String?) -> AgreementContent {
        let name = [nonBlank(worker.chineseName), nonBlank(worker.name)].compactMap { $0 }
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }.joined(separator: " ")
        let honorific = nonBlank(worker.honorific) ?? "先生"
        let figures = NumberFormatter()
        figures.locale = Locale(identifier: "en_US_POSIX")
        figures.numberStyle = .decimal
        figures.usesGroupingSeparator = true
        figures.groupingSeparator = ","
        figures.minimumFractionDigits = 2
        figures.maximumFractionDigits = 2
        let wageShown = figures.string(from: NSNumber(value: a.dailyWage)) ?? String(format: "%.2f", a.dailyWage)
        let employer = "建機（香港）設備有限公司"
        let sections = [
            AgreementSection(letter: "A", title: "工作崗位內容", terms: [
                AgreementTerm(number: "1", label: "受僱日期", value: "由 \(chineseDate(a.startDate)) 起生效（至其中一方終止合約）"),
                AgreementTerm(number: "2", label: "試用期", value: "不設試用期"),
                AgreementTerm(number: "3", label: "受僱職位", value: a.position),
                AgreementTerm(number: "4", label: "工作地點", value: "任何地方（由僱主指派）"),
                AgreementTerm(number: "5", label: "工作時間", value: "每天 \(chineseClockTime(a.hoursFrom)) 至 \(chineseClockTime(a.hoursTo))"),
            ]),
            AgreementSection(letter: "B", title: "薪酬內容", terms: [
                AgreementTerm(number: "6", label: "工資", value: "每天 港元 \(chineseCapitalAmount(a.dailyWage)) (HK$\(wageShown))（下稱「基本薪金」）"),
                AgreementTerm(number: "7", label: "超時工作工資", value: "以基本薪金1.5倍計算"),
                AgreementTerm(number: "8", label: "工資支付日期", value: "每月壹次；工資於每月第\(a.payDay)日支付（工資期由上一個月首日起至上一個月尾日（包括首尾兩天））"),
                AgreementTerm(number: "9", label: "年終酬金", value: "不設年終酬金"),
            ]),
            AgreementSection(letter: "C", title: "其他內容", terms: [
                AgreementTerm(number: "10", label: "合約終止", value: "欲終止合約方須於終止前 \(a.noticeDays) 天前通知對方，或支付對方相等於 \(a.noticeDays) 天工資"),
                AgreementTerm(number: "11", label: "強制性公積金", value: "僱員於符合《強制性公積金計劃條例》之要求後，僱主將為其安排參加強積金計劃，並以臨時僱員方式為其作出僱主供款及僱員供款。"),
                AgreementTerm(number: "12", label: "銀行自動轉賬", value: "僱員的所有工資、年終酬金（如有）及強制性公積金供款均由僱主安排在僱主指定銀行直接自動轉賬。"),
                AgreementTerm(number: "13", label: "假期福利", value: "按《僱傭條例》、《僱員福利條例》，僱員如符合有關規定，可享有法定假日、有薪年假、疾病津貼、產假和休息日等福利，及其他權益或保障。"),
                AgreementTerm(number: "14", label: "颱風或暴雨警告下工作安排", value: "", lines: [
                    "當黑色暴雨警告／八號或以上風球生效時，僱員無需上班。",
                    "當黑色暴雨警告／八號或以上風球於下班前不少於8小時前取消，僱員需要上班。",
                ]),
            ]),
        ]
        let signerName = nonBlank(signer) ?? ""
        let signerId = nonBlank(signer).flatMap { membership($0)?.idNumber }.flatMap { nonBlank($0) } ?? ""
        return AgreementContent(
            intro: "本簡易僱傭合約由 \(employer)（下稱「僱主」）與 \(name) \(honorific)（下簡稱「僱員」）於 \(chineseDate(a.agreementDate))（下稱「合約日期」）訂立，雙方同意遵守下列僱傭條款：",
            sections: sections,
            closing: [
                "雙方確認及同意共同執行合約內所有條款，包括工資率及工資計算方法，並聲明此僱傭合約為雙方協約的事實之全部，並無任何其他口頭或書面協議。",
                "處理「僱傭條例」及「僱員補償條例」有關之保障及福利結算以本僱傭合約內之條款作唯一依據。僱員每日需向所屬之打理人報到以核證當日之出勤。",
            ],
            employer: AgreementParty(heading: "僱主或其代表簽署", lines: [signerName, "身份證號碼：\(signerId)", "Authorised Signature", chineseDate(a.agreementDate)]),
            employee: AgreementParty(heading: "僱員簽署", lines: [name, "身份證號碼：\(nonBlank(worker.idNumber) ?? "")", chineseDate(a.agreementDate)]))
    }
}

extension PDFGenerator {
    /// Times New Roman, with Songti TC for the Chinese (as the template).
    func agreementFont(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        let latin = times(size, bold: bold, italic: italic)
        let chinese = (bold ? ["STSongti-TC-Bold", "STSongti-TC-Regular"] : ["STSongti-TC-Regular", "STSong"]) + ["PingFangHK-Regular"]
        let descriptor = latin.fontDescriptor.addingAttributes([.cascadeList: chinese.map { NSFontDescriptor(name: $0, size: size) }])
        return NSFont(descriptor: descriptor, size: size) ?? latin
    }

    /// The agreement on the letterhead: a cover page, the terms, then a
    /// page to sign — the employer's signature and chop when given.
    func employmentAgreement(_ c: AgreementContent, signature: CGImage? = nil, chop: CGImage? = nil) -> Data {
        pageNumber = 0
        // The cover: the title between two rules, in the middle of the page.
        beginPage()
        let ruleWidth: CGFloat = 232, ruleLeft = (pageWidth - ruleWidth) / 2
        let middle = pageHeight * 0.47
        fill(ruleLeft, middle - 56, ruleWidth, 0.9, .black)
        text(c.coverTitle, x: pageWidth / 2, baseline: middle - 14, font: times(20, bold: true), align: .center)
        text(c.coverSubtitle, x: pageWidth / 2, baseline: middle + 26, font: agreementFont(20), align: .center)
        fill(ruleLeft, middle + 52, ruleWidth, 0.9, .black)
        endPage()

        // The terms.
        beginPage()
        let font = agreementFont(11)
        let pitch: CGFloat = 16.5
        var y: CGFloat = 108
        func room(_ height: CGFloat) {
            if y + height > contentBottom { newPage(); y = continuationBaseline + 6 }
        }
        func paragraph(_ s: String, after: CGFloat) {
            for line in wrap(s, font, textWidth) { room(0); text(line, x: textLeft, baseline: y, font: font); y += pitch }
            y += after
        }
        paragraph(c.intro, after: 9)
        let labelX = textLeft + 34, colonX = labelX + 70, valueX = colonX + 12
        for section in c.sections {
            room(pitch * 3)
            text("\(section.letter).", x: textLeft, baseline: y, font: font)
            text(section.title, x: labelX, baseline: y, font: font)
            y += pitch + 6
            for term in section.terms {
                let values = term.value.isEmpty ? [] : wrap(term.value, font, textRight - valueX)
                let below = term.lines.flatMap { wrap($0, font, textRight - labelX) }
                room(CGFloat(max(1, values.count) + below.count - 1) * pitch)
                text("\(term.number).", x: textLeft, baseline: y, font: font)
                if values.isEmpty {
                    text("\(term.label)：", x: labelX, baseline: y, font: font)
                } else {
                    text(term.label, x: labelX, baseline: y, font: font)
                    text("：", x: colonX, baseline: y, font: font)
                    for (i, line) in values.enumerated() { text(line, x: valueX, baseline: y + CGFloat(i) * pitch, font: font) }
                }
                y += CGFloat(max(1, values.count)) * pitch
                for line in below { text(line, x: labelX, baseline: y, font: font); y += pitch }
                y += 6
            }
            y += 2
        }
        y += 4
        for p in c.closing { paragraph(p, after: 8) }
        endPage()

        // Signing: the employer on the left, the employee on the right.
        beginPage()
        drawAgreementParty(c.employer, x: textLeft, width: 205, signature: signature, chop: chop)
        drawAgreementParty(c.employee, x: 348 + dx, width: textRight - 348 - dx, signature: nil, chop: nil)
        endPage()
        context.closePDF()
        return mutableData as Data
    }

    func drawAgreementParty(_ p: AgreementParty, x: CGFloat, width: CGFloat, signature: CGImage?, chop: CGImage?) {
        let top: CGFloat = 122
        text(p.heading, x: x, baseline: top, font: agreementFont(11))
        let ruleY = top + 72
        if let signature = signature { image(signature, x: x + 4, top: top + 12, width: 165, height: ruleY - top - 14) }
        // The chop over the signature, well inside the line.
        if let chop = chop { image(chop, x: x + 62, top: top + 4, width: 86, height: 86, centred: true) }
        fill(x, ruleY, width, 0.75, .black)
        let font = agreementFont(10.5, bold: true, italic: true)
        var baseline = ruleY + 12
        for line in p.lines where !line.isEmpty {
            text(line, x: x, baseline: baseline, font: font)
            baseline += 14
        }
    }
}

extension NativeBridge {
    func handleWorkerAgreement(id: String, action: String, payload: [String: Any]) {
        if action == "get" {
            let workerId = (payload["workerId"] as? String) ?? ""
            if let page = db.workerAgreementPage(workerId: workerId) { respond(id: id, encodable: page) } else { respondNull(id: id) }
            return
        }
        if action == "create" {
            guard let worker = db.getWorker(id: (payload["workerId"] as? String) ?? "") else {
                respond(id: id, encodable: SimpleResult(ok: false, error: "Worker not found.")); return
            }
            db.createWorkerAgreement(for: worker)
            respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            return
        }
        guard let a = db.getWorkerAgreement(id: (payload["id"] as? String) ?? ""), let worker = db.getWorker(id: a.workerId) else {
            respond(id: id, encodable: PDFExportResult(ok: false, error: "Agreement not found.", path: nil))
            return
        }
        let number = db.workerAgreementNumber(worker)
        let folder = storage.workerFolder(worker.workerNumber).appendingPathComponent("Contracts", isDirectory: true)
        let paper = db.getCompanySettings().paperSize ?? "A4"
        let size = paper == "Letter" ? NSSize(width: 612, height: 792) : NSSize(width: 595.28, height: 841.89)
        let baseName = "\(number) Employment Agreement - \(worker.name)".replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        func fail(_ message: String) { respond(id: id, encodable: PDFExportResult(ok: false, error: message, path: nil)) }

        switch action {
        case "update":
            let error = db.updateWorkerAgreement(id: a.id, payload: payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "exportPDF", "print":
            guard let generator = PDFGenerator(paperSize: paper) else { fail("Could not prepare the agreement."); return }
            let data = generator.employmentAgreement(db.agreementContent(a, worker: worker, signer: a.employerSignedBy ?? a.signatory))
            if action == "print" {
                deliverPDF(id: id, mode: .print, data: data, paperSize: size, projectNumber: "", subfolder: "", documentNumber: number, docTypeTag: "WorkerAgreement")
            } else if (payload["preview"] as? Bool) == true {
                showPreview(id: id, data: data, PendingPreview(url: URL(fileURLWithPath: "/"), projectNumber: "", subfolder: "", documentNumber: number,
                                                               docTypeTag: "WorkerAgreement", fileName: "\(baseName).pdf", folder: folder))
            } else {
                do {
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    let destination = storage.uniqueDestination(folder.appendingPathComponent("\(baseName).pdf"))
                    try data.write(to: destination, options: .atomic)
                    openForUser(destination)
                    respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: destination.path))
                } catch {
                    fail("The PDF couldn't be saved: \(error.localizedDescription)")
                }
            }
        case "exportWord":
            guard let png = PDFGenerator.letterheadPNG(paperSize: paper) else {
                fail("Could not prepare the letterhead for the Word document."); return
            }
            let a4 = paper != "Letter"
            let width = a4 ? 595.28 : 612.0, height = a4 ? 841.89 : 792.0
            let dx = (width - 595.28) / 2
            var layout = AgreementWordLayout(paperSize: paper, pageWidth: width, pageHeight: height, textLeft: 42.75 + dx, textRight: 552.0 + dx,
                                             contentBottom: 781.5 + (height - 841.89), number: number,
                                             content: db.agreementContent(a, worker: worker, signer: a.employerSignedBy ?? a.signatory),
                                             workerId: worker.id, fileName: "\(baseName).docx")
            layout.letterheadPNG = png.base64EncodedString()
            respond(id: id, encodable: layout)
        case "sign":
            let me = TeamSync.memberName
            guard nonBlank(me) != nil else { fail("Enter your name on the User page first."); return }
            guard db.membership(me)?.canSignAgreements == true else {
                let who = db.agreementSigners()
                fail(who.isEmpty ? "No one signs worker agreements yet. Tick “Signs and chops worker agreements” for them on the Team page."
                                 : "Only \(who.joined(separator: ", ")) can sign worker agreements (Team page).")
                return
            }
            func picture(_ which: String) -> CGImage? {
                NSImage(contentsOf: db.signatureImageURL(me, which))?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            }
            guard let signature = picture("signature") else { fail("Add your signature first: Team › People › your name › Signature."); return }
            let signer = db.membership(me)?.name ?? me
            guard let generator = PDFGenerator(paperSize: paper) else { fail("Could not prepare the agreement."); return }
            let data = generator.employmentAgreement(db.agreementContent(a, worker: worker, signer: signer), signature: signature, chop: picture("chop"))
            do {
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let destination = storage.uniqueDestination(folder.appendingPathComponent("\(baseName) - Signed & Chopped.pdf"))
                try data.write(to: destination, options: .atomic)
                db.setWorkerAgreementEmployerSigned(id: a.id, by: signer, path: destination.path)
                respond(id: id, encodable: PDFExportResult(ok: true, error: nil, path: destination.path))
            } catch {
                fail("The signed agreement couldn’t be saved in the worker’s folder. Check there’s free disk space and try again.")
            }
        case "unsign":
            if let p = a.employerSignedPath, fileIsPresent(p) { try? FileManager.default.trashItem(at: URL(fileURLWithPath: p), resultingItemURL: nil) }
            db.setWorkerAgreementEmployerSigned(id: a.id, by: nil, path: nil)
            respond(id: id, encodable: SimpleResult(ok: true, error: nil))
        case "uploadSigned":
            guard let window = window else { respondNull(id: id); return }
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.allowedContentTypes = [.pdf, .jpeg, .png, .heic, .tiff]
            panel.message = "Choose the agreement signed by \(worker.name) (a PDF, or a photo or scan). A copy is kept in the worker’s Contracts folder."
            panel.beginSheetModal(for: window) { [weak self] response in
                guard let self = self else { return }
                guard response == .OK, let source = panel.url else { self.respondNull(id: id); return }
                self.respond(id: id, encodable: self.storeSignedAgreement(a, folder: folder, baseName: baseName, fileName: source.lastPathComponent) {
                    try FileManager.default.copyItem(at: source, to: $0)
                })
            }
        case "saveSignedFile":
            guard let data = (payload["base64"] as? String).flatMap({ Data(base64Encoded: $0) }), !data.isEmpty else {
                respond(id: id, encodable: SimpleResult(ok: false, error: "That file couldn't be read.")); return
            }
            respond(id: id, encodable: storeSignedAgreement(a, folder: folder, baseName: baseName, fileName: (payload["fileName"] as? String) ?? "") {
                try data.write(to: $0, options: .atomic)
            })
        case "file":
            // which: "employer" (signed & chopped here) or "signed" (by both, uploaded); action: open, reveal, remove.
            let signedCopy = (payload["which"] as? String) == "signed"
            let path = signedCopy ? a.signedCopyPath : a.employerSignedPath
            switch (payload["action"] as? String) ?? "" {
            case "remove":
                if signedCopy { db.setWorkerAgreementSignedCopy(id: a.id, path: nil) }
                respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            case "reveal":
                guard let p = path, fileIsPresent(p) else { respond(id: id, encodable: SimpleResult(ok: false, error: "That file isn’t there any more.")); return }
                revealOne(URL(fileURLWithPath: p))
                respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            default:
                guard let p = path, fileIsPresent(p) else { respond(id: id, encodable: SimpleResult(ok: false, error: "That file isn’t there any more.")); return }
                openForUser(URL(fileURLWithPath: p))
                respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            }
        default:
            respondError(id: id, message: "Unknown action.")
        }
    }

    /// The copy signed by both: "<number> Employment Agreement - <name> - Signed.<ext>" in the worker's Contracts folder.
    func storeSignedAgreement(_ a: WorkerAgreement, folder: URL, baseName: String, fileName: String, write: (URL) throws -> Void) -> SimpleResult {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        guard let type = UTType(filenameExtension: ext), [UTType.pdf, .jpeg, .png, .heic, .tiff].contains(where: { type.conforms(to: $0) }) else {
            return SimpleResult(ok: false, error: "Use a PDF, or a photo or scan (JPEG, PNG, HEIC or TIFF), of the signed agreement.")
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let destination = storage.uniqueDestination(folder.appendingPathComponent("\(baseName) - Signed.\(ext)"))
            try write(destination)
            db.setWorkerAgreementSignedCopy(id: a.id, path: destination.path)
            return SimpleResult(ok: true, error: nil)
        } catch {
            return SimpleResult(ok: false, error: "The signed copy couldn't be saved in the worker’s folder: \(error.localizedDescription)")
        }
    }
}

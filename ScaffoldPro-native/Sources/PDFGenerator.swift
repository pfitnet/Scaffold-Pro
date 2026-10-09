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
// MARK: - PDF generation (Phase 13)
//
// Every document uses the layout of the company's own quotation Qt26193:
// the Proficiency (HK) letterhead and footer on every page, EB Garamond
// body text, black-ruled tables with "HK$" at the left of money cells,
// and the original's colours. All positions, sizes and colours were
// measured from the original (A4, points from the top-left corner);
// drawing converts them to the PDF's bottom-left origin. On Letter
// paper the body and footer are centred on the wider page.
//
// Letterhead and footer are drawn to match the original exactly: each
// piece of the letterhead is scaled so its drawn outline fills the same
// box it fills on the original, whichever font variant the Mac has.
// =====================================================================

/// The letterhead's colours, measured from the original document.
enum LetterheadColor {
    static let orange = NSColor(srgbRed: 241 / 255, green: 158 / 255, blue: 56 / 255, alpha: 1)
    static let grey = NSColor(srgbRed: 153 / 255, green: 153 / 255, blue: 153 / 255, alpha: 1)
    static let darkGrey = NSColor(srgbRed: 102 / 255, green: 102 / 255, blue: 102 / 255, alpha: 1)
    static let link = NSColor(srgbRed: 40 / 255, green: 84 / 255, blue: 197 / 255, alpha: 1)
}

/// Drawings added after a document's own pages: every page of a PDF as
/// it is, and each image on a page of its own (the document's paper size,
/// turned landscape for a wide image), fitted inside a 24pt margin.
enum PDFAttachments {
    static let imageTypes: Set<String> = ["png", "jpg", "jpeg", "heic", "heif", "tif", "tiff", "gif", "bmp", "webp"]

    static func canAppend(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        return ext == "pdf" || imageTypes.contains(ext)
    }

    static func append(_ files: [URL], to data: Data, paperSize: NSSize) -> Data {
        guard !files.isEmpty, let document = PDFDocument(data: data) else { return data }
        for url in files {
            if url.pathExtension.lowercased() == "pdf" {
                guard let drawing = PDFDocument(url: url), !drawing.isLocked else { continue }
                for i in 0..<drawing.pageCount {
                    if let page = drawing.page(at: i)?.copy() as? PDFPage { document.insert(page, at: document.pageCount) }
                }
            } else if let page = imagePage(url, paperSize: paperSize) {
                document.insert(page, at: document.pageCount)
            }
        }
        return document.dataRepresentation() ?? data
    }

    static func imagePage(_ url: URL, paperSize: NSSize) -> PDFPage? {
        guard let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let wide = cg.width > cg.height
        let short = min(paperSize.width, paperSize.height), long = max(paperSize.width, paperSize.height)
        var box = CGRect(x: 0, y: 0, width: wide ? long : short, height: wide ? short : long)
        let margin: CGFloat = 24
        let scale = min((box.width - 2 * margin) / CGFloat(cg.width), (box.height - 2 * margin) / CGFloat(cg.height))
        let size = CGSize(width: CGFloat(cg.width) * scale, height: CGFloat(cg.height) * scale)
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        context.beginPDFPage(nil)
        context.interpolationQuality = .high
        context.draw(cg, in: CGRect(x: (box.width - size.width) / 2, y: (box.height - size.height) / 2, width: size.width, height: size.height))
        context.endPDFPage()
        context.closePDF()
        return PDFDocument(data: data as Data)?.page(at: 0)
    }
}

/// The company chop's size on signed documents, against the size it was
/// first drawn at (the PDFs and the BQ sheet). It shrinks about its middle.
let chopScale: CGFloat = 0.4

final class PDFGenerator {
    let paperSize: String
    let pageWidth: CGFloat
    let pageHeight: CGFloat
    let mutableData: NSMutableData
    let context: CGContext
    var pageNumber = 0
    /// Distance from the page top of the last thing drawn: the last
    /// baseline after text, or the bottom rule after a table.
    var cursor: CGFloat = 0

    // Measured on A4; on Letter the body and footer are centred.
    var dx: CGFloat { (pageWidth - 595.28) / 2 }
    var footerDY: CGFloat { pageHeight - 841.89 }
    var textLeft: CGFloat { 42.75 + dx }
    var textRight: CGFloat { 552.0 + dx }
    var textWidth: CGFloat { textRight - textLeft }
    /// Nothing goes below this; the footer rule starts at 792.75.
    var contentBottom: CGFloat { 781.5 + footerDY }
    /// First baseline, or table top, on a continuation page.
    let continuationBaseline: CGFloat = 95.25
    let continuationTableTop: CGFloat = 88.0
    /// Body text line spacing (11pt EB Garamond, as on the original).
    let bodyPitch: CGFloat = 16.5
    /// Table rules are 0.75pt black; a one-line row is 24.1pt tall and
    /// each further line of text adds 14.9pt, with lines 14.25pt apart.
    let rule: CGFloat = 0.75
    var rowHeight: CGFloat = 24.1
    let cellPitch: CGFloat = 14.25
    /// Heading row height, and where one line of text sits below a
    /// row's middle (compact tables: 23pt, 21.1pt rows, 4.1pt).
    var headerHeight: CGFloat = 24.1
    var baselineBelowMiddle: CGFloat = 5.2

    func configure(for doc: LetterDocument) {
        rowHeight = doc.tableRowHeight.map { CGFloat($0) } ?? (doc.compactTable ? 21.1 : 24.1)
        // A column title can run to two lines ("Unit\nMonthly Rental").
        let headingLines = doc.columns.map { $0.title.components(separatedBy: "\n").count }.max() ?? 1
        headerHeight = (doc.compactTable ? 23.0 : 24.1) + CGFloat(max(0, headingLines - 1)) * 13.0
        baselineBelowMiddle = doc.tableRowHeight.map { max(3.2, CGFloat($0) / 2 - 6.2) } ?? (doc.compactTable ? 4.1 : 5.2)
    }

    /// "A4" (595.28 × 841.89 pt) or "Letter" (612 × 792 pt) — sections 27, 54.
    init?(paperSize: String = "A4") {
        self.paperSize = paperSize
        if paperSize == "Letter" {
            pageWidth = 612
            pageHeight = 792
        } else {
            pageWidth = 595.28
            pageHeight = 841.89
        }
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let ctx = CGContext(consumer: consumer, mediaBox: &box, nil) else { return nil }
        mutableData = data
        context = ctx
    }

    /// Draws into a bitmap instead of a PDF: for the letterhead picture of
    /// Word documents.
    init?(bitmapPaperSize paperSize: String, scale: CGFloat) {
        self.paperSize = paperSize
        if paperSize == "Letter" {
            pageWidth = 612
            pageHeight = 792
        } else {
            pageWidth = 595.28
            pageHeight = 841.89
        }
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(data: nil, width: Int((pageWidth * scale).rounded()), height: Int((pageHeight * scale).rounded()),
                                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.scaleBy(x: scale, y: scale)
        mutableData = NSMutableData()
        context = ctx
    }

    /// The letterhead and footer (without the page number, which Word adds
    /// as a field) as a transparent, page-sized PNG at 300 dpi.
    static func letterheadPNG(paperSize: String, dpi: CGFloat = 300) -> Data? {
        guard let generator = PDFGenerator(bitmapPaperSize: paperSize, scale: dpi / 72.0) else { return nil }
        generator.showPageNumber = false
        generator.drawLetterhead()
        generator.drawFooter()
        guard let image = generator.context.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Off for the Word letterhead picture.
    var showPageNumber = true

    // MARK: fonts

    func firstFont(_ names: [String], _ size: CGFloat) -> NSFont {
        for name in names {
            if let font = NSFont(name: name, size: size) { return font }
        }
        return NSFont.systemFont(ofSize: size)
    }

    /// EB Garamond — bundled with the app (resources/fonts) and
    /// registered at launch. Georgia if it's somehow unavailable.
    func body(_ size: CGFloat = 11, bold: Bool = false, italic: Bool = false) -> NSFont {
        switch (bold, italic) {
        case (true, true): return firstFont(["EBGaramond-BoldItalic", "Georgia-BoldItalic"], size)
        case (true, false): return firstFont(["EBGaramond-Bold", "Georgia-Bold"], size)
        case (false, true): return firstFont(["EBGaramond-Italic", "Georgia-Italic"], size)
        case (false, false): return firstFont(["EBGaramond-Regular", "Georgia"], size)
        }
    }

    /// Times New Roman — the footer, signature block and closing line.
    func times(_ size: CGFloat, bold: Bool = false, italic: Bool = false) -> NSFont {
        switch (bold, italic) {
        case (true, true): return firstFont(["TimesNewRomanPS-BoldItalicMT", "Times-BoldItalic"], size)
        case (true, false): return firstFont(["TimesNewRomanPS-BoldMT", "Times-Bold"], size)
        case (false, true): return firstFont(["TimesNewRomanPS-ItalicMT", "Times-Italic"], size)
        case (false, false): return firstFont(["TimesNewRomanPSMT", "Times-Roman"], size)
        }
    }

    let letterheadLatin = ["Verdana-Bold", "Tahoma-Bold", "Helvetica-Bold"]
    /// "ScaffoldPro Letterhead TC" is Noto Sans TC cut down to the logo's
    /// characters, bundled in resources/fonts (SIL Open Font License).
    let letterheadChinese = ["ScaffoldProLetterheadTC-Regular", "NotoSansTC-Regular", "NotoSansHK-Regular", "PingFangHK-Regular"]
    let footerChinese = ["STSongti-TC-Regular", "STSong", "PingFangHK-Regular"]

    // MARK: low-level drawing (top-down coordinates)

    func fill(_ x: CGFloat, _ top: CGFloat, _ width: CGFloat, _ height: CGFloat, _ color: NSColor) {
        context.setFillColor(color.cgColor)
        context.fill(CGRect(x: x, y: pageHeight - top - height, width: width, height: height))
    }

    /// An image fitted (keeping its shape) into a box; at the box's left and
    /// bottom, or in its centre.
    func image(_ cg: CGImage, x: CGFloat, top: CGFloat, width: CGFloat, height: CGFloat, centred: Bool = false) {
        let iw = CGFloat(cg.width), ih = CGFloat(cg.height)
        guard iw > 0, ih > 0, width > 0, height > 0 else { return }
        let scale = min(width / iw, height / ih)
        let w = iw * scale, h = ih * scale
        let left = centred ? x + (width - w) / 2 : x
        let imageTop = centred ? top + (height - h) / 2 : top + height - h
        context.draw(cg, in: CGRect(x: left, y: pageHeight - imageTop - h, width: w, height: h))
    }

    func makeLine(_ string: String, _ font: NSFont, _ color: NSColor) -> CTLine {
        if hasInlineMarks(string) { return CTLineCreateWithAttributedString(styledText(string, font, color)) }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor,
        ]
        return CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    }

    /// Text with style marks (bold, italic, underline) in `font`'s family
    /// and size; the marks themselves take no room.
    func styledText(_ string: String, _ font: NSFont, _ color: NSColor) -> NSAttributedString {
        let traits = NSFontManager.shared.traits(of: font)
        let baseBold = traits.contains(.boldFontMask), baseItalic = traits.contains(.italicFontMask)
        let out = NSMutableAttributedString()
        for run in inlineRuns(string) {
            let f = (run.bold || run.italic) ? body(font.pointSize, bold: baseBold || run.bold, italic: baseItalic || run.italic) : font
            out.append(NSAttributedString(string: run.text, attributes: [
                .font: f, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color.cgColor]))
        }
        return out
    }

    func lineWidth(_ line: CTLine) -> CGFloat {
        CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    func draw(_ line: CTLine, x: CGFloat, baseline: CGFloat) {
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: x, y: pageHeight - baseline)
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// One line of text on a baseline; returns its width.
    @discardableResult
    func text(_ string: String, x: CGFloat, baseline: CGFloat, font: NSFont, color: NSColor = .black,
                      align: NSTextAlignment = .left, underline: Bool = false) -> CGFloat {
        guard !string.isEmpty else { return 0 }
        let line = makeLine(string, font, color)
        let width = lineWidth(line)
        let startX: CGFloat
        switch align {
        case .right: startX = x - width
        case .center: startX = x - width / 2
        default: startX = x
        }
        draw(line, x: startX, baseline: baseline)
        if underline { underlineRun(x: startX, width: width, baseline: baseline, font: font, color: color) }
        // Underlined runs (__text__ in a description).
        if hasInlineMarks(string) {
            var index = 0
            for run in inlineRuns(string) {
                let length = (run.text as NSString).length
                if run.underline {
                    let from = CTLineGetOffsetForStringIndex(line, index, nil), to = CTLineGetOffsetForStringIndex(line, index + length, nil)
                    underlineRun(x: startX + from, width: to - from, baseline: baseline, font: font, color: color)
                }
                index += length
            }
        }
        return width
    }

    /// EB Garamond's own underline position and thickness.
    func underlineRun(x: CGFloat, width: CGFloat, baseline: CGFloat, font: NSFont, color: NSColor) {
        fill(x, baseline + font.pointSize * 0.1, width, max(0.6, font.pointSize * 0.05), color)
    }

    func inkBounds(_ line: CTLine) -> CGRect {
        CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    }

    /// Places text so its drawn outline starts exactly at `inkLeft`, or
    /// ends exactly at `inkRight`.
    func textAtInk(_ string: String, inkLeft: CGFloat? = nil, inkRight: CGFloat? = nil, baseline: CGFloat, font: NSFont, color: NSColor) {
        let line = makeLine(string, font, color)
        let ink = inkBounds(line)
        let x: CGFloat
        if let left = inkLeft { x = left - ink.minX } else { x = (inkRight ?? 0) - ink.maxX }
        draw(line, x: x, baseline: baseline)
    }

    /// Scales text so its drawn outline exactly fills a box measured from
    /// the original letterhead.
    func fitted(_ string: String, fonts: [String], color: NSColor, left: CGFloat, top: CGFloat, right: CGFloat, bottom: CGFloat) {
        let line = makeLine(string, firstFont(fonts, 100), color)
        let ink = inkBounds(line)
        guard ink.width > 0, ink.height > 0 else { return }
        let sx = (right - left) / ink.width
        let sy = (bottom - top) / ink.height
        context.saveGState()
        context.translateBy(x: left - ink.minX * sx, y: (pageHeight - bottom) - ink.minY * sy)
        context.scaleBy(x: sx, y: sy)
        context.textMatrix = .identity
        context.textPosition = .zero
        CTLineDraw(line, context)
        context.restoreGState()
    }

    /// Where the references' colons go (before `dx`): at 478.5pt as on the
    /// template, the value right-aligned to 550.5pt after it. A value that
    /// can't be broken (a number such as Qt26210-004-s1) and is wider than
    /// that space moves the colons left — no further than just after the
    /// longest label — so it stays on one line.
    func refColon(_ rows: [(label: String, value: String)], _ font: NSFont) -> CGFloat {
        let measure = { (s: String) -> CGFloat in NSAttributedString(string: s, attributes: [.font: font]).size().width }
        let widest = rows.filter { !$0.value.contains(" ") && !$0.value.contains("\n") }.map { measure($0.value) }.max() ?? 0
        guard widest > 66 else { return 478.5 }
        let labels = rows.map { measure($0.label) }.max() ?? 0
        return max(401.25 + labels + 6, 550.5 - 6 - widest)
    }

    /// Breaks text into lines no wider than `width`; "\n" always breaks.
    func wrap(_ string: String, _ font: NSFont, _ width: CGFloat) -> [String] {
        if hasInlineMarks(string) { return wrapStyled(string, font, width) }
        var result: [String] = []
        for paragraph in string.components(separatedBy: "\n") {
            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let attributed = NSAttributedString(string: trimmed, attributes: [.font: font])
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            let ns = trimmed as NSString
            var start = 0
            while start < ns.length {
                let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(max(width, 10))))
                result.append(ns.substring(with: NSRange(location: start, length: min(count, ns.length - start))).trimmingCharacters(in: .whitespaces))
                start += count
            }
        }
        return result
    }

    /// `wrap` for text with style marks: measured as drawn (bold is wider),
    /// each line starting with the styles still on from the line before.
    func wrapStyled(_ string: String, _ font: NSFont, _ width: CGFloat) -> [String] {
        let marks: [unichar] = [0xE010, 0xE011, 0xE012]
        var result: [String] = []
        for paragraph in string.components(separatedBy: "\n") {
            let ns = paragraph as NSString
            // The visible text, and each of its characters' styles.
            let plain = NSMutableString()
            var styles: [[Bool]] = []
            var on = [false, false, false]
            var i = 0
            while i < ns.length {
                if let m = marks.firstIndex(of: ns.character(at: i)) { on[m].toggle(); i += 1; continue }
                let r = ns.rangeOfComposedCharacterSequence(at: i)
                plain.append(ns.substring(with: r))
                for _ in 0..<r.length { styles.append(on) }
                i += r.length
            }
            guard plain.length > 0, !(plain as String).trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            let attributed = NSMutableAttributedString(string: plain as String, attributes: [.font: font])
            for i in 0..<styles.count where styles[i][0] || styles[i][1] {
                attributed.addAttribute(.font, value: body(font.pointSize, bold: styles[i][0], italic: styles[i][1]), range: NSRange(location: i, length: 1))
            }
            let typesetter = CTTypesetterCreateWithAttributedString(attributed)
            var start = 0
            while start < plain.length {
                let count = max(1, CTTypesetterSuggestLineBreak(typesetter, start, Double(max(width, 10))))
                var a = start, b = min(start + count, plain.length)
                while a < b && plain.character(at: a) == 32 { a += 1 }
                while b > a && plain.character(at: b - 1) == 32 { b -= 1 }
                if a < b {
                    var line = ""
                    var state = [false, false, false]
                    let markChars: [Character] = [inlineBoldMark, inlineItalicMark, inlineUnderlineMark]
                    var k = a
                    while k < b {
                        for m in 0..<3 where styles[k][m] != state[m] {
                            line.append(markChars[m])
                            state[m] = styles[k][m]
                        }
                        let r = plain.rangeOfComposedCharacterSequence(at: k)
                        line += plain.substring(with: r)
                        k += r.length
                    }
                    result.append(line)
                }
                start += count
            }
        }
        return result
    }

    // MARK: letterhead and footer (identical on every page and document)

    func drawLetterhead() {
        let orange = LetterheadColor.orange, grey = LetterheadColor.grey, darkGrey = LetterheadColor.darkGrey
        fitted("P", fonts: letterheadLatin, color: orange, left: 42.75, top: 28.5, right: 57.75, bottom: 46.5)
        fitted("ROFICIENCY", fonts: letterheadLatin, color: grey, left: 60.0, top: 31.5, right: 200.25, bottom: 47.25)
        fill(6.0, 51.0, 209.25, 2.25, orange)
        // Noto Sans (Traditional Chinese), its natural shape — not stretched
        // to fit — starting where the original's does. The full name is
        // longer than the original's, so it's smaller (11.5pt, not 15pt): it
        // ends where the original did, clear of "(HK)".
        textAtInk("建機（香港）設備有限公司", inkLeft: 41.25, baseline: 72.25, font: firstFont(letterheadChinese, 11.5), color: darkGrey)
        fitted("(HK)", fonts: letterheadLatin, color: orange, left: 190.5, top: 58.5, right: 240.75, bottom: 77.25)
        fitted("LIMITED", fonts: letterheadLatin, color: grey, left: 251.25, top: 61.5, right: 331.5, bottom: 74.25)
        fill(189.0, 78.0, pageWidth - 6.53 - 189.0, 2.25, orange)
    }

    func drawFooter() {
        let grey = LetterheadColor.grey
        let x = dx, y = footerDY
        fill(42.75 + x, 792.75 + y, 510.0, 2.25, LetterheadColor.orange)

        let chinese: [(String, CGFloat, CGFloat)] = [
            ("香港", 210.75, 228.75), ("北角", 231.75, 248.25), ("蜆殼街 9-23", 252.0, 297.0),
            ("號", 300.0, 308.25), ("秀明中心", 311.25, 346.5), ("17樓 B室", 349.5, 384.0),
        ]
        for (segment, left, right) in chinese {
            fitted(segment, fonts: footerChinese, color: grey, left: left + x, top: 798.75 + y, right: right + x, bottom: 807.75 + y)
        }

        let font = times(9)
        let words = "Unit B, 17/F, Seabright Plaza, 9-23 Shell Street, Causeway Bay, Hong Kong".components(separatedBy: " ")
        let wordLefts: [CGFloat] = [160.5, 178.5, 189.75, 209.25, 246.0, 270.0, 288.75, 309.75, 335.25, 374.25, 393.0, 414.75]
        for (word, left) in zip(words, wordLefts) {
            textAtInk(word, inkLeft: left + x, baseline: 816.75 + y, font: font, color: grey)
        }
        let contacts: [(String, CGFloat)] = [("Tel: +852 2690 0133", 153.0), ("Email: rk123@pfitnet.com", 249.75), ("Fax: +852 2663 0371", 368.25)]
        for (segment, left) in contacts {
            textAtInk(segment, inkLeft: left + x, baseline: 827.25 + y, font: font, color: grey)
        }
        if showPageNumber {
            textAtInk("Page \(pageNumber)", inkRight: 552.0 + x, baseline: 827.25 + y, font: times(9, italic: true), color: grey)
        }
    }

    func beginPage() {
        context.beginPDFPage(nil)
        pageNumber += 1
        drawLetterhead()
    }

    func endPage() {
        drawFooter()
        context.endPDFPage()
    }

    func newPage() {
        endPage()
        beginPage()
    }

    // MARK: opening (client, references, title, "Re:")

    /// Extra space above and below the title ("QUOTATION", "BILL OF
    /// QUANTITIES", …), on top of the original's spacing.
    static let titlePadding: CGFloat = 6.0
    var titlePadding: CGFloat { PDFGenerator.titlePadding }

    /// The client's name (bold) and address, as printed: each address line
    /// kept to 260pt, a long one broken after its commas where it can be
    /// ("38th Floor, Dorset House, Taikoo Place," / "979 King's Road, …").
    func clientBlockLines(_ doc: LetterDocument) -> [(text: String, bold: Bool)] {
        var lines = wrap(doc.clientName, body(12, bold: true), 300).map { (text: $0, bold: true) }
        for line in doc.clientLines {
            lines += wrapAddress(line, body(12), 260).map { (text: $0, bold: false) }
        }
        return lines
    }

    func wrapAddress(_ line: String, _ font: NSFont, _ width: CGFloat) -> [String] {
        let fits: (String) -> Bool = { self.lineWidth(self.makeLine($0, font, .black)) <= width }
        let parts = line.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        // A line typed with a comma at the end keeps it ("38th Floor, Dorset House,").
        let endsWithComma = line.trimmingCharacters(in: .whitespaces).hasSuffix(",")
        var out: [String] = []
        var current = ""
        for (i, part) in parts.enumerated() {
            let piece = i < parts.count - 1 || endsWithComma ? part + "," : part
            let candidate = current.isEmpty ? piece : current + " " + piece
            if current.isEmpty || fits(candidate) {
                current = candidate
            } else {
                out.append(current)
                current = piece
            }
        }
        if !current.isEmpty { out.append(current) }
        return out.flatMap { fits($0) ? [$0] : wrap($0, font, width) }
    }

    func drawOpening(_ doc: LetterDocument) {
        let blockLeft = 47.75 + dx
        let firstBaseline: CGFloat = 104.25
        let pitch: CGFloat = 15.75

        let left = clientBlockLines(doc)
        for (i, item) in left.enumerated() {
            text(item.text, x: blockLeft, baseline: firstBaseline + CGFloat(i) * pitch, font: body(12, bold: item.bold))
        }

        // Reference block: label, colon, value right-aligned; a value too
        // long for the space runs on under itself, left-aligned.
        let refFont = body(11)
        let colon = refColon(doc.refRows, refFont)
        var refLine = 0
        for row in doc.refRows {
            let baseline = firstBaseline + CGFloat(refLine) * pitch
            text(row.label, x: 401.25 + dx, baseline: baseline, font: refFont)
            text(":", x: colon + dx, baseline: baseline, font: refFont)
            let valueLines = wrap(row.value, refFont, 550.5 - colon - 6)
            if valueLines.count <= 1 {
                text(row.value, x: 550.5 + dx, baseline: baseline, font: refFont, align: .right)
                refLine += 1
            } else {
                for (j, line) in valueLines.enumerated() {
                    text(line, x: colon + 6 + dx, baseline: firstBaseline + CGFloat(refLine + j) * pitch, font: refFont)
                }
                refLine += valueLines.count
            }
        }

        // "BY EMAIL ONLY" goes under the references (beside the client's
        // last line if the address is longer), the title under both.
        let clientLast = firstBaseline + CGFloat(max(left.count, 1) - 1) * pitch
        let refLast = firstBaseline + CGFloat(max(refLine, 1) - 1) * pitch
        var baseline: CGFloat
        if let method = doc.deliveryMethod, !method.isEmpty {
            let methodBaseline = refLast + 19.5
            text(method, x: 550.5 + dx, baseline: methodBaseline, font: body(13, bold: true), align: .right, underline: true)
            baseline = max(methodBaseline + 21.0, clientLast + 24.0) + titlePadding
        } else {
            baseline = max(clientLast, refLast) + 40.5 + titlePadding
        }

        text(doc.title, x: pageWidth / 2, baseline: baseline, font: body(15, bold: true), align: .center, underline: true)
        // A draft or cancelled one says so across each whole page (PDFWatermark).
        var last = baseline
        var next = baseline + 18.0 + titlePadding
        if let salutation = doc.salutation, !salutation.isEmpty {
            text(salutation, x: textLeft, baseline: next, font: body(11))
            last = next
            next += bodyPitch
        }
        if let subject = doc.subject, !subject.isEmpty {
            for line in wrap(subject, body(11, bold: true), textWidth) {
                text(line, x: textLeft, baseline: next, font: body(11, bold: true), underline: true)
                last = next
                next += bodyPitch
            }
        }
        if let intro = doc.intro, !intro.isEmpty {
            for line in wrap(intro, body(11), textWidth) {
                text(line, x: textLeft, baseline: next, font: body(11))
                last = next
                next += bodyPitch
            }
        }
        // The table starts 15pt below the last line (243 → 258 on the original).
        cursor = last + 15.0
        guard !doc.infoRows.isEmpty else { return }
        // Labelled lines (the delivery note): bold labels, ": value" at
        // 100.5pt, 17.35pt apart, the first 24pt (plus the title padding)
        // under the title; the table 17.6pt under the last.
        next = last == baseline ? baseline + 24.0 + titlePadding : last + 17.35
        for row in doc.infoRows {
            let lines = infoValueLines(row)
            text(row.label, x: textLeft + 1.5, baseline: next, font: body(11, bold: true))
            text(":", x: infoColonX, baseline: next, font: body(11))
            for (j, line) in lines.enumerated() {
                text(line, x: infoValueX, baseline: next + CGFloat(j) * bodyPitch, font: body(11, bold: row.boldValue))
            }
            last = next + CGFloat(max(lines.count, 1) - 1) * bodyPitch
            next = last + 17.35
        }
        cursor = last + 17.6
    }

    var infoColonX: CGFloat { textLeft + 100.5 }
    var infoValueX: CGFloat { infoColonX + lineWidth(makeLine(": ", body(11), .black)) }
    func infoValueLines(_ row: LetterInfoRow) -> [String] {
        wrap(row.value, body(11, bold: row.boldValue), textRight - infoValueX)
    }

    // MARK: table

    func columnEdges(_ columns: [LetterColumn]) -> [CGFloat] {
        var edges: [CGFloat] = [42.0 + dx]
        for column in columns { edges.append((edges.last ?? 0) + column.width) }
        return edges
    }

    func hRule(_ edges: [CGFloat], _ y: CGFloat) {
        guard let first = edges.first, let last = edges.last else { return }
        fill(first, y, last - first + rule, rule, .black)
    }

    func vRule(_ x: CGFloat, _ top: CGFloat, _ height: CGFloat) {
        fill(x, top, rule, height + rule, .black)
    }

    /// Text is centred vertically in its cell, as on the original.
    func cellBaseline(top: CGFloat, height: CGFloat, lines: Int, line: Int) -> CGFloat {
        top + height / 2 + baselineBelowMiddle - CGFloat(lines - 1) * cellPitch / 2 + CGFloat(line) * cellPitch
    }

    func cellLines(_ rawValue: String, column: LetterColumn, font: NSFont, currencyWidth: CGFloat) -> [String] {
        // **bold**, *italic*, __underline__ in a description.
        let value = column.kind == .left ? applyInlineMarkup(rawValue) : rawValue
        let available = column.width - 10.5 - (column.kind == .money ? currencyWidth + 4 : 0)
            - (column.kind == .weight ? weightSuffixRoom(font) : 0)
        // A description written with bullets, numbering or hanging indents.
        if column.kind == .left && isFormattedDescription(value) {
            let measure = { (s: String) -> Double in Double(self.lineWidth(self.makeLine(s, font, .black))) }
            return formattedCellLines(value, width: Double(available), measure: measure, wrap: { self.wrap($0, font, CGFloat($1)) }).map(encodeCellLine)
        }
        return wrap(value, font, available)
    }

    /// A summary row's label, wrapped to the columns before the last.
    func summaryLabelLines(_ label: String, emphasized: Bool, doc: LetterDocument) -> [String] {
        let width = doc.columns.dropLast().reduce(CGFloat(0)) { $0 + $1.width } - 12
        let lines = wrap(label, body(emphasized ? 12 : 11, bold: true), max(60, width))
        return lines.isEmpty ? [label] : lines
    }

    func height(of row: LetterTableRow, in doc: LetterDocument) -> CGFloat {
        switch row {
        case .item(let cells):
            let font = body(11)
            let currencyWidth = lineWidth(makeLine(doc.currencySymbol, font, .black))
            var lines = 1
            for (i, cell) in cells.enumerated() where i < doc.columns.count {
                lines = max(lines, cellLines(cell, column: doc.columns[i], font: font, currencyWidth: currencyWidth).count)
            }
            return rowHeight + CGFloat(lines - 1) * 14.9
        case .section:
            return 37.5
        case .summary(let label, _, let emphasized):
            // A long label (an invoice's total in words) runs over lines.
            let lines = summaryLabelLines(label, emphasized: emphasized, doc: doc).count
            return (emphasized ? 37.5 : 29.25) + CGFloat(max(1, lines) - 1) * cellPitch
        case .partial(let cells, _):
            return height(of: .item(cells), in: doc)
        case .wide(_, let text):
            return rowHeight + CGFloat(max(1, wideLines(text, doc: doc).count) - 1) * 14.9
        case .note(let note):
            let lines = wrap(note, noteFont, noteWidth(doc)).count
            return 29.25 + CGFloat(max(1, lines) - 1) * notePitch
        }
    }

    /// A wide row's text, wrapped across every column but the first.
    func wideLines(_ text: String, doc: LetterDocument) -> [String] {
        let width = doc.columns.dropFirst().reduce(CGFloat(0)) { $0 + $1.width } - 10
        return wrap(text, body(11), max(60, width))
    }

    // Table notes: 9.5pt italic, grey, 13pt apart.
    var noteFont: NSFont { body(9.5, italic: true) }
    let notePitch: CGFloat = 13.0
    func noteWidth(_ doc: LetterDocument) -> CGFloat {
        doc.columns.reduce(0) { $0 + $1.width } - 12.0
    }

    func drawCell(_ lines: [String], column: LetterColumn, left: CGFloat, right: CGFloat, top: CGFloat, height: CGFloat, font: NSFont, currency: String) {
        let count = max(1, lines.count)
        for (j, line) in lines.enumerated() {
            let baseline = cellBaseline(top: top, height: height, lines: count, line: j)
            switch column.kind {
            case .center: text(line, x: (left + right + rule) / 2, baseline: baseline, font: font, align: .center)
            case .left:
                if let l = decodeCellLine(line) {
                    if let marker = l.marker { text(marker, x: left + 5.0 + CGFloat(l.markerX), baseline: baseline, font: font) }
                    if l.colon { text(":", x: left + 5.0 + CGFloat(l.textX) - 3.75, baseline: baseline, font: font) }
                    text(l.text, x: left + 5.0 + CGFloat(l.textX), baseline: baseline, font: font)
                } else {
                    text(line, x: left + 5.0, baseline: baseline, font: font)
                }
            case .right, .money: text(line, x: right - 3.4, baseline: baseline, font: font, align: .right)
            case .weight:
                guard !line.isEmpty else { continue }
                text(line, x: right - 3.4 - weightSuffixRoom(font), baseline: baseline, font: font, align: .right)
                if j == 0 { text("kg", x: right - 3.4, baseline: baseline, font: font, align: .right) }
            }
        }
        if column.kind == .money, let first = lines.first, !first.isEmpty {
            text(currency, x: left + 5.25, baseline: cellBaseline(top: top, height: height, lines: 1, line: 0), font: font)
        }
    }

    /// "kg" and the space before it, at the right of a weight cell.
    func weightSuffixRoom(_ font: NSFont) -> CGFloat {
        lineWidth(makeLine("kg", font, .black)) + 8.4
    }

    func drawHeaderRow(_ columns: [LetterColumn], _ edges: [CGFloat]) {
        let top = cursor
        hRule(edges, top)
        hRule(edges, top + headerHeight)
        for x in edges { vRule(x, top, headerHeight) }
        let font = body(11, bold: true)
        for (i, column) in columns.enumerated() {
            let lines = column.title.components(separatedBy: "\n")
            for (j, line) in lines.enumerated() {
                text(line, x: (edges[i] + edges[i + 1] + rule) / 2,
                     baseline: cellBaseline(top: top, height: headerHeight, lines: lines.count, line: j), font: font, align: .center)
            }
        }
        cursor += headerHeight
    }

    /// Draws the table, repeating the column titles at the top of every
    /// page it runs onto (section 27).
    func drawTable(_ doc: LetterDocument) {
        guard !doc.columns.isEmpty else { return }
        let edges = columnEdges(doc.columns)
        let last = edges.count - 1
        drawHeaderRow(doc.columns, edges)
        if doc.rows.isEmpty {
            text("No items.", x: textLeft, baseline: cursor + 17.25, font: body(11, italic: true))
            cursor += rowHeight
            return
        }
        for row in doc.rows {
            let h = height(of: row, in: doc)
            if cursor + h > contentBottom {
                newPage()
                cursor = continuationTableTop
                drawHeaderRow(doc.columns, edges)
            }
            let top = cursor
            hRule(edges, top)
            hRule(edges, top + h)
            switch row {
            case .item(let cells):
                for x in edges { vRule(x, top, h) }
                let font = body(11)
                let currencyWidth = lineWidth(makeLine(doc.currencySymbol, font, .black))
                for (i, cell) in cells.enumerated() where i < doc.columns.count {
                    let lines = cellLines(cell, column: doc.columns[i], font: font, currencyWidth: currencyWidth)
                    drawCell(lines, column: doc.columns[i], left: edges[i], right: edges[i + 1], top: top, height: h, font: font, currency: doc.currencySymbol)
                }
            case .section(let title):
                vRule(edges[0], top, h)
                vRule(edges[last], top, h)
                text(title, x: (edges[0] + edges[last] + rule) / 2, baseline: cellBaseline(top: top, height: h, lines: 1, line: 0),
                     font: body(12, bold: true), align: .center)
            case .summary(let label, let value, let emphasized):
                vRule(edges[0], top, h)
                vRule(edges[last - 1], top, h)
                vRule(edges[last], top, h)
                let font = body(emphasized ? 12 : 11, bold: true)
                let labelLines = summaryLabelLines(label, emphasized: emphasized, doc: doc)
                for (i, line) in labelLines.enumerated() {
                    text(line, x: edges[last - 1] - 4.25, baseline: cellBaseline(top: top, height: h, lines: labelLines.count, line: i), font: font, align: .right)
                }
                drawCell([value], column: doc.columns[last - 1], left: edges[last - 1], right: edges[last], top: top, height: h, font: font, currency: doc.currencySymbol)
            case .partial(let cells, let tail):
                let count = min(cells.count, doc.columns.count - 1)
                for x in edges[0...count] { vRule(x, top, h) }
                vRule(edges[last], top, h)
                let font = body(11)
                let currencyWidth = lineWidth(makeLine(doc.currencySymbol, font, .black))
                for (i, cell) in cells.prefix(count).enumerated() {
                    let lines = cellLines(cell, column: doc.columns[i], font: font, currencyWidth: currencyWidth)
                    drawCell(lines, column: doc.columns[i], left: edges[i], right: edges[i + 1], top: top, height: h, font: font, currency: doc.currencySymbol)
                }
                text(tail, x: (edges[count] + edges[last] + rule) / 2, baseline: cellBaseline(top: top, height: h, lines: 1, line: 0),
                     font: font, align: .center)
            case .wide(let number, let wideText):
                vRule(edges[0], top, h)
                if last > 1 { vRule(edges[1], top, h) }
                vRule(edges[last], top, h)
                // The number on one line ("BO1"), a little smaller if it must.
                var numberFont = body(11)
                if lineWidth(makeLine(number, numberFont, .black)) > (edges[1] - edges[0]) - 3 { numberFont = body(9) }
                text(number, x: (edges[0] + edges[1] + rule) / 2, baseline: cellBaseline(top: top, height: h, lines: 1, line: 0), font: numberFont, align: .center)
                let lines = wideLines(wideText, doc: doc)
                for (j, line) in lines.enumerated() {
                    text(line, x: edges[1] + 5.0, baseline: cellBaseline(top: top, height: h, lines: lines.count, line: j), font: body(11))
                }
            case .note(let note):
                vRule(edges[0], top, h)
                vRule(edges[last], top, h)
                let lines = wrap(note, noteFont, noteWidth(doc))
                let first = top + h / 2 + 3.4 - CGFloat(max(1, lines.count) - 1) * notePitch / 2
                for (j, line) in lines.enumerated() {
                    text(line, x: edges[0] + 6.0, baseline: first + CGFloat(j) * notePitch, font: noteFont, color: LetterheadColor.darkGrey)
                }
            }
            cursor += h
        }
    }

    // MARK: text after the table

    /// Justified paragraph (the last line and lines ending in "\n" are
    /// left-aligned). Returns the last baseline used.
    func drawParagraph(_ string: String, link: String?, firstBaseline: CGFloat) -> CGFloat {
        let font = body(11)
        let colorKey = NSAttributedString.Key(kCTForegroundColorAttributeName as String)
        let attributed = NSMutableAttributedString(string: string, attributes: [.font: font, colorKey: NSColor.black.cgColor])
        let ns = string as NSString
        var linkRange = NSRange(location: NSNotFound, length: 0)
        if let link = link, !link.isEmpty {
            linkRange = ns.range(of: link)
            if linkRange.location != NSNotFound {
                attributed.addAttribute(colorKey, value: LetterheadColor.link.cgColor, range: linkRange)
            }
        }
        let typesetter = CTTypesetterCreateWithAttributedString(attributed)
        let breaks = CharacterSet.whitespacesAndNewlines
        var start = 0
        var baseline = firstBaseline
        var firstLine = true
        while start < ns.length {
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(textWidth))
            guard count > 0 else { break }
            // Leave out trailing spaces / the line break itself.
            var visible = count
            var hardBreak = false
            while visible > 0, let scalar = UnicodeScalar(ns.character(at: start + visible - 1)), breaks.contains(scalar) {
                if scalar == "\n" { hardBreak = true }
                visible -= 1
            }
            if !firstLine { baseline += bodyPitch }
            if baseline > contentBottom {
                newPage()
                baseline = continuationBaseline
            }
            firstLine = false
            if visible > 0 {
                var line = CTTypesetterCreateLine(typesetter, CFRange(location: start, length: visible))
                let isLast = start + count >= ns.length
                if !isLast, !hardBreak, let justified = CTLineCreateJustifiedLine(line, 1.0, Double(textWidth)) {
                    line = justified
                }
                draw(line, x: textLeft, baseline: baseline)
                if linkRange.location != NSNotFound {
                    let from = max(linkRange.location, start)
                    let to = min(NSMaxRange(linkRange), start + visible)
                    if from < to {
                        let x0 = CTLineGetOffsetForStringIndex(line, from, nil)
                        let x1 = CTLineGetOffsetForStringIndex(line, to, nil)
                        underlineRun(x: textLeft + x0, width: x1 - x0, baseline: baseline, font: font, color: LetterheadColor.link)
                    }
                }
            }
            start += count
        }
        return baseline
    }

    /// "(i) Payment : First two month's rental…" — label at the margin,
    /// colon at 128.25pt, text (and any further lines) at 132pt.
    func drawTerm(label: String?, lines: [String], firstBaseline: CGFloat) -> CGFloat {
        let font = body(11)
        let textX = 132.0 + dx
        var baseline = firstBaseline
        var firstLine = true
        for raw in lines {
            for piece in wrap(raw, font, textRight - textX) {
                if !firstLine { baseline += bodyPitch }
                if baseline > contentBottom {
                    newPage()
                    baseline = continuationBaseline
                }
                if firstLine {
                    if let label = label { text(label, x: textLeft, baseline: baseline, font: font) }
                    text(":", x: 128.25 + dx, baseline: baseline, font: font)
                }
                text(piece, x: textX, baseline: baseline, font: font)
                firstLine = false
            }
        }
        return baseline
    }

    /// Where a hanging paragraph's text starts, in points from the margin.
    func hangingTextX(marker: String, left: CGFloat, indent: CGFloat?, colon: Bool) -> CGFloat {
        let markerWidth = marker.isEmpty ? 0 : lineWidth(makeLine(marker, body(11), .black))
        var textX = indent ?? (left + max(18, markerWidth + 6))
        if !marker.isEmpty { textX = max(textX, left + markerWidth + (colon ? 7.5 : 5)) }
        return min(textX, textRight - 120 - textLeft)
    }

    /// A hanging-indent paragraph (see `LetterParagraph.hanging`). A long
    /// label pushes the text column right; the text always keeps at least
    /// 120pt. Returns the last baseline used.
    func drawHanging(marker: String, lines: [String], left: CGFloat, indent: CGFloat?, colon: Bool, firstBaseline: CGFloat) -> CGFloat {
        let font = body(11)
        let markerX = textLeft + left
        let textX = textLeft + hangingTextX(marker: marker, left: left, indent: indent, colon: colon)
        var baseline = firstBaseline
        if !marker.isEmpty { text(marker, x: markerX, baseline: baseline, font: font) }
        if colon { text(":", x: textX - 3.75, baseline: baseline, font: font) }
        var first = true
        for piece in lines.flatMap({ wrap($0, font, textRight - textX) }) {
            if !first {
                baseline += bodyPitch
                if baseline > contentBottom {
                    newPage()
                    baseline = continuationBaseline
                }
            }
            text(piece, x: textX, baseline: baseline, font: font)
            first = false
        }
        return baseline
    }

    /// Set by `generate` after a trial layout: the sections (by index) that
    /// are kept together but ran over a page there, so start a new page.
    var sectionsOnNewPage: Set<Int> = []
    /// Recorded while laying out: kept-together sections that ran over a page.
    var sectionsThatSplit: Set<Int> = []

    /// Which kept-together sections have to start a new page: laid out on
    /// trial (again, if moving one moves another) until none runs over.
    func keptTogetherBreaks(_ doc: LetterDocument) -> Set<Int> {
        guard doc.sections.contains(where: { $0.keepTogether }) else { return [] }
        var breaks: Set<Int> = []
        for _ in 0..<3 {
            guard let trial = PDFGenerator(paperSize: paperSize) else { break }
            trial.sectionsOnNewPage = breaks
            _ = trial.layOut(doc)
            let more = trial.sectionsThatSplit.subtracting(breaks)
            if more.isEmpty { break }
            breaks.formUnion(more)
        }
        return breaks
    }

    func drawSections(_ sections: [LetterSection]) {
        var afterTable = true
        for (sectionIndex, section) in sections.enumerated() {
            var baseline = cursor + (afterTable ? 27.0 : 33.0)
            afterTable = false
            if section.alwaysNewPage || sectionsOnNewPage.contains(sectionIndex) {
                newPage()
                baseline = continuationBaseline
            }
            if let heading = section.heading, !heading.isEmpty {
                // Keep the heading with its first line.
                if baseline + 26.25 > contentBottom {
                    newPage()
                    baseline = continuationBaseline
                }
                text(heading, x: textLeft, baseline: baseline, font: body(11, bold: true), underline: true)
                cursor = baseline
                baseline += 26.25
            } else if baseline > contentBottom {
                newPage()
                baseline = continuationBaseline
            }
            let startPage = pageNumber
            defer { if section.keepTogether && pageNumber != startPage { sectionsThatSplit.insert(sectionIndex) } }
            var previousWasTerm = false
            for (index, paragraph) in section.paragraphs.enumerated() {
                switch paragraph {
                case .text(let string, let link):
                    if index > 0 { baseline = cursor + (previousWasTerm ? 33.0 : 26.25) }
                    if baseline > contentBottom {
                        newPage()
                        baseline = continuationBaseline
                    }
                    cursor = drawParagraph(string, link: link, firstBaseline: baseline)
                    previousWasTerm = false
                case .hanging(let marker, let lines, let left, let indent, let colon):
                    if index > 0 { baseline = cursor + (previousWasTerm ? bodyPitch : 26.25) }
                    if baseline > contentBottom {
                        newPage()
                        baseline = continuationBaseline
                    }
                    cursor = drawHanging(marker: marker, lines: lines, left: left, indent: indent, colon: colon, firstBaseline: baseline)
                    previousWasTerm = true
                case .term(let label, let lines):
                    if index > 0 { baseline = cursor + (previousWasTerm ? bodyPitch : 26.25) }
                    if baseline > contentBottom {
                        newPage()
                        baseline = continuationBaseline
                    }
                    cursor = drawTerm(label: label, lines: lines, firstBaseline: baseline)
                    previousWasTerm = true
                }
            }
        }
    }

    // MARK: signatures and closing line

    /// "For and on Behalf of", a signing rule 75.75pt below, then the
    /// party and name/position/date lines — kept together on one page.
    func drawSignatures(_ signatures: [LetterSignature], afterTable: Bool) {
        guard !signatures.isEmpty else { return }
        var baseline = cursor + (afterTable ? 30.0 : 32.25)
        let maxLines = signatures.map { $0.lines.count }.max() ?? 0
        let blockHeight = 75.75 + 39.0 + CGFloat(max(0, maxLines - 3)) * 14.0 + 6
        if baseline + blockHeight > contentBottom {
            newPage()
            baseline = continuationBaseline
        }
        let font = times(10.5, bold: true, italic: true)
        let columns: [(textX: CGFloat, ruleX: CGFloat, ruleWidth: CGFloat, colonX: CGFloat)] = [
            (48.75 + dx, 43.5 + dx, 225.75, 120.75 + dx),
            (331.5 + dx, 326.25 + dx, 225.0, 403.5 + dx),
        ]
        let offsets: [CGFloat] = [11.25, 24.75, 39.0]
        var lowest = baseline
        for (i, signature) in signatures.prefix(2).enumerated() {
            let column = columns[i]
            text(signature.heading, x: column.textX, baseline: baseline, font: font)
            if let sub = signature.subheading {
                text(sub, x: column.textX, baseline: baseline + 14.0, font: font)
            }
            let ruleY = baseline + 75.75
            if let sig = signature.signatureImage {
                image(sig, x: column.textX, top: baseline + (signature.subheading == nil ? 12 : 22), width: 165, height: ruleY - baseline - (signature.subheading == nil ? 13 : 23))
            }
            // The chop goes over the signature, well inside the line.
            if let chop = signature.chopImage {
                let side = 84 * chopScale, inset = (84 - side) / 2
                image(chop, x: column.textX + 62 + inset, top: baseline + 6 + inset, width: side, height: side, centred: true)
            }
            fill(column.ruleX, ruleY, column.ruleWidth, 0.75, .black)
            for (j, line) in signature.lines.enumerated() {
                let lineBaseline = ruleY + (j < offsets.count ? offsets[j] : 39.0 + CGFloat(j - 2) * 14.0)
                text(line.text, x: column.textX, baseline: lineBaseline, font: font)
                if line.colon {
                    text(":", x: column.colonX, baseline: lineBaseline, font: font)
                    if let value = line.value, !value.isEmpty {
                        text(value, x: column.colonX + 8, baseline: lineBaseline, font: font)
                    }
                }
                lowest = max(lowest, lineBaseline)
            }
        }
        cursor = lowest
    }

    /// Set while laying out: the receipt lines went onto a page of their own.
    var receiptOnNewPage = false

    /// "Received By : ____  Date : ____" — bold labels, the colon at
    /// 81.65pt, a line to write on 6.3pt under the baseline, rows 34.5pt
    /// apart. Moved to a new page if they don't fit, under "Ref.: <number>".
    func drawReceipt(_ doc: LetterDocument) {
        guard !doc.receiptRows.isEmpty else { return }
        let pitch: CGFloat = 34.5
        var baseline = cursor + 33.0
        if baseline + CGFloat(doc.receiptRows.count - 1) * pitch + 8 > contentBottom {
            newPage()
            receiptOnNewPage = true
            text("Ref.: \(doc.number)", x: textLeft, baseline: continuationBaseline, font: body(11))
            baseline = continuationBaseline + 32.9
        }
        let font = body(11, bold: true)
        for (i, row) in doc.receiptRows.enumerated() {
            let b = baseline + CGFloat(i) * pitch
            for (label, x, ruleEnd) in [(row.0, CGFloat(0), CGFloat(255.5)), (row.1, CGFloat(255.0), textRight + 1 - textLeft)] {
                text(label, x: textLeft + x + 9.65, baseline: b, font: font)
                text(":", x: textLeft + x + 81.65, baseline: b, font: font)
                fill(textLeft + x + 87.5, b + 6.3, ruleEnd - (x + 87.5), rule, .black)
            }
            cursor = b + 6.3
        }
    }

    func drawClosingLine(_ line: String) {
        let baseline = cursor + 69.0
        // "Remainder of this page is intentionally left blank": not worth a
        // page of its own when the page is already full.
        guard baseline <= contentBottom else { return }
        text(line, x: pageWidth / 2, baseline: baseline, font: times(10.5, italic: true), align: .center)
        cursor = baseline
    }

    // MARK: entry point

    func generate(_ doc: LetterDocument) -> Data {
        // Trial layouts (discarded) find which kept-together sections won't
        // fit where they fall; those start a new page.
        sectionsOnNewPage = keptTogetherBreaks(doc)
        return layOut(doc)
    }

    /// The document for a Word copy (js/docx-export.js): table cells wrapped
    /// as here, row heights, where hanging text starts, and which sections
    /// start a new page — so Word lays it out like the PDF.
    func wordLayout(_ doc: LetterDocument) -> WordLayout {
        configure(for: doc)
        var receiptNewPage = false
        if !doc.receiptRows.isEmpty, let trial = PDFGenerator(paperSize: paperSize) {
            _ = trial.layOut(doc)
            receiptNewPage = trial.receiptOnNewPage
        }
        let breaks = keptTogetherBreaks(doc)
        let font = body(11)
        let currencyWidth = lineWidth(makeLine(doc.currencySymbol, font, .black))
        func lines(_ cells: [String]) -> [[String]] {
            cells.enumerated().filter { $0.offset < doc.columns.count }.map {
                cellLines($0.element, column: doc.columns[$0.offset], font: font, currencyWidth: currencyWidth).map(plainCellLine)
            }
        }
        let rows: [WordRow] = doc.rows.map { row in
            let h = Double(height(of: row, in: doc))
            switch row {
            case .item(let cells): return WordRow(type: "item", height: h, cells: lines(cells))
            case .section(let title): return WordRow(type: "section", height: h, text: title)
            case .summary(let label, let value, let emphasized):
                return WordRow(type: "summary", height: h, label: label, value: value, emphasized: emphasized)
            case .partial(let cells, let tail): return WordRow(type: "partial", height: h, cells: lines(cells), text: tail)
            case .wide(let number, let wideText): return WordRow(type: "wide", height: h, cells: [[number]], text: wideLines(wideText, doc: doc).joined(separator: "\n"))
            case .note(let note): return WordRow(type: "note", height: h, text: note)
            }
        }
        let sections: [WordSection] = doc.sections.enumerated().map { sectionIndex, section in
            let paragraphs: [WordParagraph] = section.paragraphs.map { p in
                switch p {
                case .text(let string, let link):
                    return WordParagraph(type: "text", text: string, link: link)
                case .term(let label, let lines):
                    return WordParagraph(type: "hanging", marker: label ?? "", lines: lines, left: 0, textX: Double(labelTextIndent), colon: true)
                case .hanging(let marker, let lines, let left, let indent, let colon):
                    return WordParagraph(type: "hanging", marker: marker, lines: lines, left: Double(left),
                                         textX: Double(hangingTextX(marker: marker, left: left, indent: indent, colon: colon)), colon: colon)
                }
            }
            return WordSection(heading: section.heading, paragraphs: paragraphs,
                               pageBreakBefore: section.alwaysNewPage || breaks.contains(sectionIndex))
        }
        return WordLayout(
            paperSize: paperSize, pageWidth: Double(pageWidth), pageHeight: Double(pageHeight),
            textLeft: Double(textLeft), textRight: Double(textRight), contentBottom: Double(contentBottom),
            number: doc.number, status: doc.status, title: doc.title,
            clientName: clientBlockLines(doc).filter { $0.bold }.map { $0.text }.joined(separator: "\n"),
            clientLines: clientBlockLines(doc).filter { !$0.bold }.map { $0.text },
            refRows: doc.refRows.map { WordRefRow(label: $0.label, value: $0.value, wraps: wrap($0.value, font, 550.5 - refColon(doc.refRows, font) - 6).count > 1) },
            refColon: Double(refColon(doc.refRows, font)),
            deliveryMethod: nonBlank(doc.deliveryMethod), salutation: nonBlank(doc.salutation), subject: nonBlank(doc.subject),
            intro: nonBlank(doc.intro), currencySymbol: doc.currencySymbol,
            columns: doc.columns.map { WordColumn(title: $0.title, width: Double($0.width), kind: "\($0.kind)") },
            rows: rows, sections: sections,
            signatures: doc.signatures.map { WordSignature(heading: $0.heading, subheading: $0.subheading, lines: $0.lines.map { WordSignatureLine(text: $0.text, colon: $0.colon, value: $0.value) }) },
            closingLine: nonBlank(doc.closingLine),
            infoRows: doc.infoRows.map { WordInfoRow(label: $0.label, lines: infoValueLines($0), bold: $0.boldValue) },
            headerHeight: Double(headerHeight),
            receiptRows: doc.receiptRows.map { [$0.0, $0.1] },
            receiptNewPage: receiptNewPage
        )
    }

    /// A letter from the letter editor: formatted text (with any tables)
    /// laid out over as many pages as it needs, each on the letterhead with
    /// the footer and page number.
    func generateRichText(_ text: NSAttributedString, opening: LetterOpening? = nil) -> Data {
        let storage = NSTextStorage(attributedString: text)
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        // Below the letterhead's lower rule; above the footer's. On the
        // first page the body starts under the letter's opening.
        let top: CGFloat = 100
        let firstTop: CGFloat = opening.map { letterOpeningHeight($0) } ?? top
        var containers: [NSTextContainer] = []
        repeat {
            let pageTop = containers.isEmpty ? firstTop : top
            let container = NSTextContainer(size: NSSize(width: textWidth, height: max(40, contentBottom - pageTop)))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            containers.append(container)
            let range = layout.glyphRange(for: container)
            if NSMaxRange(range) >= layout.numberOfGlyphs || (range.length == 0 && containers.count > 1) { break }
        } while containers.count < 500
        pageNumber = 0
        for container in containers {
            let range = layout.glyphRange(for: container)
            if range.length == 0 && pageNumber > 0 { break }
            beginPage()
            if pageNumber == 1, let opening = opening { drawLetterOpening(opening) }
            let pageTop = pageNumber == 1 ? firstTop : top
            NSGraphicsContext.saveGraphicsState()
            context.saveGState()
            // AppKit text drawing: origin at the page's top left, y down.
            context.translateBy(x: 0, y: pageHeight)
            context.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            let origin = NSPoint(x: textLeft, y: pageTop)
            layout.drawBackground(forGlyphRange: range, at: origin)
            layout.drawGlyphs(forGlyphRange: range, at: origin)
            context.restoreGState()
            NSGraphicsContext.restoreGraphicsState()
            endPage()
        }
        context.closePDF()
        return mutableData as Data
    }

    /// A letter's opening, laid out as on the quotations: the recipient on
    /// the left (bold name, address, then "Attn:" bold and underlined), the
    /// references on the right (label, colon, value to the right margin),
    /// then the "Re:" line, bold and underlined. Returns where the body
    /// starts (with `draw` false, only measures).
    @discardableResult
    func layOutLetterOpening(_ o: LetterOpening, draw: Bool) -> CGFloat {
        // Lined up with the "Re:" line and the body (the letter's left margin).
        let blockLeft = textLeft
        let firstBaseline: CGFloat = 104.25
        let pitch: CGFloat = 15.75
        var left: [(text: String, bold: Bool, underline: Bool)] = []
        if let name = nonBlank(o.recipientName) { left += wrap(name, body(12, bold: true), 300).map { ($0, true, false) } }
        for line in o.addressLines { left += wrapAddress(line, body(12), 260).map { ($0, false, false) } }
        if let attn = nonBlank(o.attention) {
            if !left.isEmpty { left.append(("", false, false)) }
            left += wrap("Attn: \(attn)", body(12, bold: true), 300).map { ($0, true, true) }
        }
        if draw {
            for (i, item) in left.enumerated() where !item.text.isEmpty {
                text(item.text, x: blockLeft, baseline: firstBaseline + CGFloat(i) * pitch, font: body(12, bold: item.bold), underline: item.underline)
            }
        }
        let refFont = body(11)
        let colon = refColon(o.refRows, refFont)
        var refLine = 0
        for row in o.refRows {
            let baseline = firstBaseline + CGFloat(refLine) * pitch
            let valueLines = wrap(row.value, refFont, 550.5 - colon - 6)
            if draw {
                text(row.label, x: 401.25 + dx, baseline: baseline, font: refFont)
                text(":", x: colon + dx, baseline: baseline, font: refFont)
                if valueLines.count <= 1 {
                    text(row.value, x: 550.5 + dx, baseline: baseline, font: refFont, align: .right)
                } else {
                    for (j, line) in valueLines.enumerated() {
                        text(line, x: colon + 6 + dx, baseline: firstBaseline + CGFloat(refLine + j) * pitch, font: refFont)
                    }
                }
            }
            refLine += max(1, valueLines.count)
        }
        let clientLast = firstBaseline + CGFloat(max(left.count, 1) - 1) * pitch
        let refLast = firstBaseline + CGFloat(max(refLine, 1) - 1) * pitch
        var next = max(clientLast, refLast) + 30.0
        if let subject = nonBlank(o.subject) {
            for line in wrap("Re: \(subject)", body(11, bold: true), textWidth) {
                if draw { text(line, x: textLeft, baseline: next, font: body(11, bold: true), underline: true) }
                next += bodyPitch
            }
            next += 8
        }
        // The body's first line sits about a line below.
        return next - 8
    }

    /// An annexure's cover page: the letterhead, the letter's opening, and
    /// the annexure's name large between two rules in the middle of the page.
    /// `pageNumber`: its place in the whole letter (for the footer).
    func annexureCover(opening: LetterOpening, title: String, pageNumber number: Int) -> Data {
        pageNumber = max(0, number - 1)
        beginPage()
        drawLetterOpening(opening)
        let ruleLeft = pageWidth * 0.2, ruleWidth = pageWidth * 0.6
        let middle = pageHeight * 0.49
        fill(ruleLeft, middle - 45, ruleWidth, 1.1, .black)
        fill(ruleLeft, middle + 44, ruleWidth, 1.1, .black)
        text(title, x: pageWidth / 2, baseline: middle + 12, font: body(34, bold: true), align: .center)
        endPage()
        context.closePDF()
        return mutableData as Data
    }

    func letterOpeningHeight(_ o: LetterOpening) -> CGFloat { layOutLetterOpening(o, draw: false) }
    func drawLetterOpening(_ o: LetterOpening) { layOutLetterOpening(o, draw: true) }

    func layOut(_ doc: LetterDocument) -> Data {
        configure(for: doc)
        receiptOnNewPage = false
        sectionsThatSplit = []
        pageNumber = 0
        beginPage()
        drawOpening(doc)
        drawTable(doc)
        drawSections(doc.sections)
        drawSignatures(doc.signatures, afterTable: doc.sections.isEmpty)
        drawReceipt(doc)
        if let closing = doc.closingLine { drawClosingLine(closing) }
        endPage()
        context.closePDF()
        return mutableData as Data
    }
}

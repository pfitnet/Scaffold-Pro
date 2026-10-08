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

extension AppDatabase {
    // ---- Letters ----

    func listLetters(projectId: String?) -> [LetterSummary] {
        let projects = Dictionary(projectsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let names = authorsByRecord("letters.json")
        return lettersStore.readAll()
            .filter { projectId == nil || $0.projectId == projectId }
            .sorted { ($0.letterDate, $0.createdAt) > ($1.letterDate, $1.createdAt) }
            .map { l in
                let p = l.projectId.flatMap { projects[$0] }
                var summary = LetterSummary(id: l.id, letterNumber: l.letterNumber, status: l.status, letterDate: l.letterDate, subject: l.subject,
                                            recipientName: l.recipientName, projectId: l.projectId, projectNumber: p?.projectNumber,
                                            projectName: p?.name, updatedAt: l.updatedAt)
                summary.createdBy = names[l.id]?.createdBy
                summary.lastEditedBy = names[l.id]?.lastEditedBy
                return summary
            }
    }

    func getLetter(id: String) -> Letter? { lettersStore.readAll().first { $0.id == id } }

    func nextLetterNumber(projectNumber: String) -> String {
        nextDocumentNumber(template: numberFormat("LT"), projectNumber: projectNumber,
                           existing: lettersStore.readAll().map { $0.letterNumber },
                           startAt: getCompanySettings().numberStarts?["LT"] ?? 1)
    }

    /// A new Draft letter, numbered, with the body started as a letter
    /// ("Dear Sirs," … "Yours faithfully," and who signs, from Settings).
    /// Every letter belongs to a project and is numbered from its code.
    func createLetter(projectId: String?, clientId: String?, recipientName: String?, recipientAddress: String?, attention: String?) -> Result<Letter, WorkerError> {
        guard let project = projectId.flatMap({ getProject(id: $0) }) else { return .failure(WorkerError(message: "Choose the project the letter is for.")) }
        let settings = getCompanySettings()
        let esc: (String) -> String = { $0.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;") }
        var body = "<p>Dear Sirs,</p><p><br></p><p>Should you have any questions, please do not hesitate to contact us.</p><p><br></p><p>Yours faithfully,</p>"
        body += "<p>For and on behalf of<br><b>\(esc(settings.companyName))</b></p><p><br></p><p><br></p>"
        let signer = [settings.signatoryName, settings.signatoryTitle].compactMap { nonBlank($0) }.map(esc)
        if !signer.isEmpty { body += "<p>\(signer.joined(separator: "<br>"))</p>" }
        let letter = Letter(id: makeId("letter"), letterNumber: nextLetterNumber(projectNumber: project.projectNumber),
                            projectId: project.id, clientId: clientId ?? project.clientId, status: "Draft", letterDate: nowISO(),
                            recipientName: nonBlank(recipientName), recipientAddress: nonBlank(recipientAddress), attention: nonBlank(attention),
                            yourRef: nil, subject: nil, bodyHTML: body, pdfPath: nil, createdAt: nowISO(), updatedAt: nowISO())
        lettersStore.insert(letter)
        logActivity(projectId: project.id, "Letter created", reference: letter.letterNumber)
        return .success(letter)
    }

    /// Changes a Draft letter's fields (those given) and/or its body.
    func updateLetter(id: String, payload: [String: Any]) -> String? {
        var all = lettersStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return "Letter not found." }
        guard all[i].status == "Draft" else { return "This letter is issued and can no longer be edited. Set it back to Draft first." }
        if let day = payload["letterDate"] as? String {
            guard let iso = isoFromDay(day) else { return "Enter a valid date." }
            all[i].letterDate = iso
        }
        for key in ["recipientName", "recipientAddress", "attention", "yourRef", "subject"] where payload.keys.contains(key) {
            let v = nonBlank(payload[key] as? String)
            switch key {
            case "recipientName": all[i].recipientName = v
            case "recipientAddress": all[i].recipientAddress = v
            case "attention": all[i].attention = v
            case "yourRef": all[i].yourRef = v
            default: all[i].subject = v
            }
        }
        if payload.keys.contains("clientId") { all[i].clientId = nonBlank(payload["clientId"] as? String) }
        if let html = payload["bodyHTML"] as? String { all[i].bodyHTML = html }
        if payload.keys.contains("annexurePrefix") {
            let raw = (payload["annexurePrefix"] as? String) ?? ""
            all[i].annexurePrefix = nonBlank(raw) == nil ? nil : String(raw.drop { $0 == " " })
        }
        if let list = payload["attachments"] as? [[String: Any]] {
            all[i].attachments = list.map { a in
                LetterAttachment(id: nonBlank(a["id"] as? String) ?? makeId("annex"), description: ((a["description"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                 files: ((a["files"] as? [String]) ?? []).filter { !$0.isEmpty })
            }
        }
        all[i].updatedAt = nowISO()
        lettersStore.writeAll(all)
        return nil
    }

    /// Files added to one of a letter's attachments (a new one if
    /// `attachmentId` is nil). Returns the attachments.
    func addLetterAttachmentFiles(letterId: String, attachmentId: String?, paths: [String]) -> Result<[LetterAttachment], WorkerError> {
        var all = lettersStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == letterId }) else { return .failure(WorkerError(message: "Letter not found.")) }
        guard all[i].status == "Draft" else { return .failure(WorkerError(message: "This letter is issued and can no longer be edited. Set it back to Draft first.")) }
        var list = all[i].attachments ?? []
        if let aid = attachmentId, let k = list.firstIndex(where: { $0.id == aid }) {
            list[k].files += paths
        } else {
            let base = paths.first.map { URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent } ?? ""
            list.append(LetterAttachment(id: makeId("annex"), description: base, files: paths))
        }
        all[i].attachments = list
        all[i].updatedAt = nowISO()
        lettersStore.writeAll(all)
        return .success(list)
    }

    func updateLetterStatus(id: String, status: String) -> String? {
        var all = lettersStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return "Letter not found." }
        guard ["Draft", "Issued", "Cancelled"].contains(status) else { return "Invalid status." }
        if all[i].status == "Cancelled" && status != "Cancelled" { return "This letter is cancelled and can't be reopened." }
        let changed = all[i].status != status
        all[i].status = status
        all[i].updatedAt = nowISO()
        lettersStore.writeAll(all)
        if changed { logActivity(projectId: all[i].projectId, "Letter \(status.lowercased())", reference: all[i].letterNumber) }
        return nil
    }

    /// A Draft letter; an issued one only with `force` (the page asks twice).
    func deleteLetter(id: String, force: Bool) -> String? {
        var all = lettersStore.readAll()
        guard let letter = all.first(where: { $0.id == id }) else { return "Letter not found." }
        guard letter.status == "Draft" || force else { return "Only draft letters can be deleted." }
        all.removeAll { $0.id == id }
        lettersStore.writeAll(all)
        logActivity(projectId: letter.projectId, "Letter deleted", reference: letter.letterNumber)
        return nil
    }

    /// Removes a day; the days after it move up (Day 3 becomes Day 2…).
    func deleteDeliveryDay(id: String) -> String? {
        var all = quotationDeliveriesStore.readAll()
        guard let gone = all.first(where: { $0.id == id }) else { return "Delivery day not found." }
        all.removeAll { $0.id == id }
        let rest = all.indices.filter { all[$0].quotationId == gone.quotationId }.sorted { all[$0].day < all[$1].day }
        for (n, index) in rest.enumerated() where all[index].day != n + 1 { all[index].day = n + 1 }
        quotationDeliveriesStore.writeAll(all)
        return nil
    }

    // ---- Invoices (Phase 9) ----

    /// Issued (or part-paid) with money still owed and past its due date.
    /// Shown as "Overdue" everywhere without having to be set by hand.
    func isInvoiceOverdue(_ inv: Invoice, balanceDue: Double, today: String) -> Bool {
        let open = !["Draft", "Paid", "Cancelled"].contains(inv.status) && balanceDue > 0
        return open && (inv.dueDate.map { !$0.isEmpty && String($0.prefix(10)) < today } ?? false)
    }

    func invoiceLineItems(for invoiceId: String) -> [InvoiceLineItem] {
        byMaterialList(invoiceLineItemsStore.readAll().filter { $0.invoiceId == invoiceId }, itemId: { $0.priceListItemId },
                       code: { $0.itemCode }, description: { $0.itemDescription }, order: { $0.sortOrder })
    }

    /// Months of rent a rental invoice charges; 1 for anything else.
    func invoiceMonths(_ inv: Invoice) -> Int {
        inv.pricingMode == "Rental" ? max(1, inv.rentalMonths ?? 1) : 1
    }

    /// Each line net of its own discount. For rental, the materials are a
    /// monthly charge × the months charged; delivery lines are charged
    /// once. Then the invoice-wide discount and tax.
    func invoiceTotals(_ inv: Invoice, lineItems: [InvoiceLineItem]) -> (subtotal: Double, discountAmount: Double, taxAmount: Double, total: Double, balanceDue: Double, materials: Double, materialsCharge: Double, delivery: Double, other: Double) {
        func net(_ line: InvoiceLineItem) -> Decimal {
            netLineAmount(quantity: line.quantity, unitPrice: line.appliedUnitPrice, discountType: line.discountType, discountValue: line.discountValue)
        }
        let materials = lineItems.filter { $0.section != "Delivery" && $0.chargeGroup == nil }.reduce(Decimal(0)) { $0 + net($1) }
        let delivery = lineItems.filter { $0.section == "Delivery" && $0.chargeGroup == nil }.reduce(Decimal(0)) { $0 + net($1) }
        // Design fees, erection prices…: charged once, like delivery.
        let other = lineItems.filter { $0.chargeGroup != nil }.reduce(Decimal(0)) { $0 + net($1) }
        let charge = materials * Decimal(invoiceMonths(inv))
        let t = moneyTotals(subtotal: charge + delivery + other, discountType: inv.discountType, discountValue: inv.discountValue, taxRatePercent: inv.taxRatePercent,
                            pricesIncludeTax: getCompanySettings().pricesIncludeTax ?? false)
        let balance = decimalOf(t.total) - roundToCents(decimalOf(inv.amountPaid))
        return (t.subtotal, t.discountAmount, t.taxAmount, t.total, doubleOf(balance > 0 ? balance : 0),
                doubleOf(materials), doubleOf(charge), doubleOf(delivery), doubleOf(other))
    }

    func listInvoiceSummaries(projectId: String) -> [InvoiceSummary] {
        let today = todayYMD()
        let names = authorsByRecord("invoices.json")
        return invoicesStore.readAll()
            .filter { $0.projectId == projectId }
            .sorted { $0.invoiceNumber > $1.invoiceNumber }
            .map { inv in
                let items = invoiceLineItems(for: inv.id)
                let totals = invoiceTotals(inv, lineItems: items)
                let status = isInvoiceOverdue(inv, balanceDue: totals.balanceDue, today: today) ? "Overdue" : inv.status
                var summary = InvoiceSummary(id: inv.id, invoiceNumber: inv.invoiceNumber, status: status, itemCount: items.count, total: totals.total, amountPaid: inv.amountPaid, dueDate: inv.dueDate, createdAt: inv.createdAt)
                summary.quotationNumber = inv.sourceQuotationId.flatMap { getQuotation(id: $0)?.quotationNumber }
                let notes = deliveryNotesStore.readAll()
                summary.deliveryNoteNumbers = (inv.sourceDeliveryNoteIds ?? []).compactMap { id in notes.first { $0.id == id }?.deliveryNoteNumber }
                summary.createdBy = names[inv.id]?.createdBy
                summary.lastEditedBy = names[inv.id]?.lastEditedBy
                return summary
            }
    }

    /// Same per-project convention as BOQs and Quotations:
    /// "<projectNumber>-INV-001".
    func nextInvoiceNumber(projectNumber: String, projectId: String) -> String {
        nextDocumentNumber(template: numberFormat("INV"), projectNumber: projectNumber, existing: invoicesStore.readAll().map { $0.invoiceNumber }, startAt: getCompanySettings().numberStarts?["INV"] ?? 1)
    }

    /// Every invoice is based on one of the project's quotations: its
    /// items, prices, line discounts, discount/tax terms and Sale/Rental
    /// pricing are copied (copies, not references). For a rental
    /// quotation the invoice charges `rentalMonths` of rent — one month,
    /// or the quotation's full hire period; delivery charges are included
    /// when `includeDelivery` is set, and the priced sections' charges
    /// (design fees, erection…) when `includeOtherCharges` is. Rates-only
    /// rows and notes aren't copied.
    /// From delivery notes: what was delivered (their quantities, added
    /// up), at the prices of the quotation they were made from. They must
    /// all come from the same quotation.
    func createInvoice(projectId: String, projectNumber: String, deliveryNoteIds: [String], rentalMonths: Int?, includeDelivery: Bool, includeOtherCharges: Bool = true) -> Result<Invoice, WorkerError> {
        let all = deliveryNotesStore.readAll()
        let notes = deliveryNoteIds.compactMap { id in all.first { $0.id == id } }
        guard !notes.isEmpty, notes.allSatisfy({ $0.projectId == projectId }) else {
            return .failure(WorkerError(message: "Choose this project's delivery notes to invoice."))
        }
        if let cancelled = notes.first(where: { $0.status == "Cancelled" }) {
            return .failure(WorkerError(message: "\(cancelled.deliveryNoteNumber) is cancelled."))
        }
        let sources = Set(notes.map { $0.sourceQuotationId ?? "" })
        guard !sources.contains("") else {
            return .failure(WorkerError(message: "A delivery note that isn't based on a quotation has no prices. Make it from a quotation (or import one into it) first."))
        }
        // Notes from several quotations: one invoice, each quotation's
        // deliveries a section of their own (the first quotation's first).
        let quotations = sources.compactMap { getQuotation(id: $0) }
            .sorted { $0.quotationNumber.localizedStandardCompare($1.quotationNumber) == .orderedAscending }
        guard let primary = quotations.first, quotations.count == sources.count else {
            return .failure(WorkerError(message: "A quotation those delivery notes were made from can't be found."))
        }
        if Set(quotations.map { $0.pricingMode }).count > 1 {
            return .failure(WorkerError(message: "Those delivery notes are for a rental quotation and a sale quotation. Invoice the rental and the sale separately."))
        }
        if Set(quotations.map { nonBlank($0.currency)?.uppercased() ?? "" }).count > 1 {
            return .failure(WorkerError(message: "Those delivery notes are for quotations in different currencies. Invoice each currency separately."))
        }
        let result = createInvoice(projectId: projectId, projectNumber: projectNumber, sourceQuotationId: primary.id, rentalMonths: rentalMonths,
                                   includeDelivery: includeDelivery, includeOtherCharges: includeOtherCharges,
                                   deliveryNotes: notes.filter { $0.sourceQuotationId == primary.id })
        guard case .success(var invoice) = result, quotations.count > 1 else { return result }
        var lines: [InvoiceLineItem] = []
        var order = invoiceLineItems(for: invoice.id).count
        for q in quotations.dropFirst() {
            let group = q.quotationNumber + (nonBlank(q.subject).map { " — \($0)" } ?? "")
            let qLines = quotationLineItems(for: q.id)
            let delivered = deliveredLines(notes.filter { $0.sourceQuotationId == q.id }, quotation: q, quotationLines: qLines)
            var picked = delivered.map { (line: $0, block: QuotationBlock?.none) }
            if includeDelivery { picked += qLines.filter { isDeliveryLine($0) }.map { (line: $0, block: QuotationBlock?.none) } }
            if includeOtherCharges {
                for block in quotationBlocks(for: q.id) where block.kind == "Priced" {
                    picked += qLines.filter { $0.blockId == block.id }.sorted { $0.sortOrder < $1.sortOrder }.map { (line: $0, block: Optional(block)) }
                }
            }
            for source in picked {
                let item = source.line
                var copy = InvoiceLineItem(
                    id: makeId("iitem"), invoiceId: invoice.id, sourceKey: item.sourceKey,
                    priceListItemId: item.priceListItemId, itemCode: item.itemCode,
                    itemDescription: item.itemDescription, unit: item.unit, quantity: item.quantity.rounded(),
                    appliedUnitPrice: effectiveUnitPrice(item, q), section: item.section, sortOrder: order,
                    discountType: item.discountType, discountValue: item.discountValue)
                if let block = source.block {
                    copy.chargeGroup = "\(nonBlank(block.title) ?? "Other Charges") (\(q.quotationNumber))"
                    copy.chargePrefix = block.prefix
                } else if !isDeliveryLine(item) {
                    copy.materialGroup = group
                }
                order += 1
                lines.append(copy)
            }
        }
        invoiceLineItemsStore.insertMany(lines)
        var allInvoices = invoicesStore.readAll()
        if let i = allInvoices.firstIndex(where: { $0.id == invoice.id }) {
            allInvoices[i].sourceDeliveryNoteIds = notes.map { $0.id }
            invoicesStore.writeAll(allInvoices)
            invoice = allInvoices[i]
        }
        logActivity(projectId: projectId, "Invoice also bills \(quotations.dropFirst().map { $0.quotationNumber }.joined(separator: ", "))", reference: invoice.invoiceNumber)
        return .success(invoice)
    }

    func createInvoice(projectId: String, projectNumber: String, sourceQuotationId: String, rentalMonths: Int?, includeDelivery: Bool, includeOtherCharges: Bool = true, deliveryNotes: [DeliveryNote] = []) -> Result<Invoice, WorkerError> {
        guard let quotation = getQuotation(id: sourceQuotationId), quotation.projectId == projectId else {
            return .failure(WorkerError(message: "Choose one of this project's quotations to base the invoice on."))
        }
        guard quotation.status != "Cancelled" else {
            return .failure(WorkerError(message: "That quotation is cancelled. Choose another quotation."))
        }
        let settings = getCompanySettings()
        let dueFormatter = DateFormatter()
        dueFormatter.locale = Locale(identifier: "en_US_POSIX")
        dueFormatter.dateFormat = "yyyy-MM-dd"
        let dueDate = Calendar.current.date(byAdding: .day, value: settings.defaultInvoiceDueDays ?? 30, to: Date()).map { dueFormatter.string(from: $0) }
        let isRental = quotation.pricingMode == "Rental"
        // The quotation's number: H26001-004 for Qt26001-004.
        let usedInvoiceNumbers: [String] = invoicesStore.readAll().map { $0.invoiceNumber }
        let invoiceNumber = linkedNumber(type: "INV", sourceType: "QT", sourceNumber: quotation.quotationNumber,
                                         projectNumber: projectNumber, existing: usedInvoiceNumbers)
            ?? nextInvoiceNumber(projectNumber: projectNumber, projectId: projectId)

        var invoice = Invoice(
            id: makeId("invoice"), projectId: projectId, sourceQuotationId: quotation.id,
            invoiceNumber: invoiceNumber,
            status: "Draft", invoiceDate: nowISO(), dueDate: dueDate, paymentTerms: nil,  // follows Settings until edited
            discountType: quotation.discountType, discountValue: quotation.discountValue, taxRatePercent: quotation.taxRatePercent,
            amountPaid: 0, notes: settings.defaultNotes, createdAt: nowISO(), updatedAt: nowISO()
        )
        invoice.pricingMode = quotation.pricingMode
        invoice.rentalMonths = isRental ? max(1, rentalMonths ?? 1) : nil
        invoice.sourceDeliveryNoteIds = deliveryNotes.isEmpty ? nil : deliveryNotes.map { $0.id }
        invoicesStore.insert(invoice)
        let charge = isRental ? " — \(invoice.rentalMonths ?? 1) month\((invoice.rentalMonths ?? 1) == 1 ? "" : "s") rental" : ""
        let from = deliveryNotes.isEmpty ? quotation.quotationNumber : "\(deliveryNotes.map { $0.deliveryNoteNumber }.joined(separator: ", ")) (\(quotation.quotationNumber))"
        logActivity(projectId: projectId, "Invoice created from \(from)\(charge)", reference: invoice.invoiceNumber)

        // Prices as charged on the quotation (with its markup).
        let allItems = quotationLineItems(for: quotation.id)
        // The materials: the quotation's, or what the delivery notes delivered.
        let materials = deliveryNotes.isEmpty ? allItems.filter { isMaterialLine($0) } : deliveredLines(deliveryNotes, quotation: quotation, quotationLines: allItems)
        var sourceItems = (materials + allItems.filter { includeDelivery && isDeliveryLine($0) })
            .map { (line: $0, block: QuotationBlock?.none) }
        if includeOtherCharges {
            for block in quotationBlocks(for: quotation.id) where block.kind == "Priced" {
                sourceItems += allItems.filter { $0.blockId == block.id }.sorted { $0.sortOrder < $1.sortOrder }.map { (line: $0, block: Optional(block)) }
            }
        }
        let copied: [InvoiceLineItem] = sourceItems.enumerated().map { index, source in
            let item = source.line
            var copy = InvoiceLineItem(
                id: makeId("iitem"), invoiceId: invoice.id, sourceKey: item.sourceKey,
                priceListItemId: item.priceListItemId, itemCode: item.itemCode,
                itemDescription: item.itemDescription, unit: item.unit, quantity: item.quantity.rounded(),
                appliedUnitPrice: effectiveUnitPrice(item, quotation), section: item.section, sortOrder: index,
                discountType: item.discountType, discountValue: item.discountValue
            )
            if let block = source.block {
                copy.chargeGroup = nonBlank(block.title) ?? "Other Charges"
                copy.chargePrefix = block.prefix
            }
            return copy
        }
        // The quotation's minimum monthly rental charge carries over as a
        // line after the materials (charged for each month, like them).
        var lines = copied
        let money = quotationMoney(quotation, lineItems: deliveryNotes.isEmpty ? allItems : materials + allItems.filter { !isMaterialLine($0) })
        if money.minimumApplied {
            let adjustment = doubleOf(roundToCents(decimalOf(money.monthlyRental) - decimalOf(money.materialsSubtotal)))
            let position = sourceItems.filter { isMaterialLine($0.line) }.count
            lines.insert(InvoiceLineItem(
                id: makeId("iitem"), invoiceId: invoice.id, sourceKey: nil, priceListItemId: nil, itemCode: "",
                itemDescription: "Minimum monthly rental charge adjustment (minimum \(formatMoney(money.monthlyRental)) per month)",
                unit: "lot", quantity: 1, appliedUnitPrice: adjustment, section: nil, sortOrder: position
            ), at: position)
            for i in lines.indices { lines[i].sortOrder = i }
        }
        invoiceLineItemsStore.insertMany(lines)
        return .success(invoice)
    }

    /// What delivery notes delivered, item by item (quantities added up),
    /// as quotation lines priced as on the quotation: an item quoted keeps
    /// its price and discount (an amount off is shared in proportion); one
    /// that wasn't quoted takes its material-list price.
    func deliveredLines(_ notes: [DeliveryNote], quotation: Quotation, quotationLines: [QuotationLineItem]) -> [QuotationLineItem] {
        var order: [String] = []
        var quantity: [String: Double] = [:]
        var sample: [String: DeliveryNoteLineItem] = [:]
        for note in notes {
            for l in deliveryNoteLineItems(for: note.id) where l.quantity > 0 {
                let key = l.priceListItemId ?? "\(l.itemCode)|\(l.itemDescription)|\(l.unit)"
                if sample[key] == nil { sample[key] = l; order.append(key) }
                quantity[key, default: 0] += l.quantity
            }
        }
        let quoted = quotationLines.filter { isMaterialLine($0) }
        let rates = conversionRates()
        return order.enumerated().compactMap { index, key -> QuotationLineItem? in
            guard let d = sample[key] else { return nil }
            let q = (quantity[key] ?? 0).rounded()
            let match = quoted.first { m in
                d.priceListItemId != nil ? m.priceListItemId == d.priceListItemId : m.itemCode == d.itemCode && m.itemDescription == d.itemDescription
            }
            if var line = match {
                if line.discountType == "Amount", let v = line.discountValue, line.quantity > 0 {
                    line.discountValue = doubleOf(roundToCents(decimalOf(v) * decimalOf(q) / decimalOf(line.quantity)))
                }
                line.quantity = q
                line.sortOrder = index
                return line
            }
            let price = d.priceListItemId.flatMap { priceListItem(id: $0) }.flatMap { basePrice($0, mode: quotation.pricingMode, rates: rates) } ?? 0
            return QuotationLineItem(id: "delivered-\(index)", quotationId: quotation.id, sourceKey: d.sourceKey, priceListItemId: d.priceListItemId,
                                     itemCode: d.itemCode, itemDescription: d.itemDescription, unit: d.unit, quantity: q,
                                     appliedUnitPrice: price, section: d.section, sortOrder: index, priceListUnitPrice: price)
        }
    }

    /// Rental invoices: months charged and the period text (Draft only).
    func updateInvoiceRental(id: String, months: Int?, period: String?, updatePeriod: Bool) -> String? {
        var invs = invoicesStore.readAll()
        guard let i = invs.firstIndex(where: { $0.id == id }) else { return "Invoice not found." }
        guard invs[i].status == "Draft" else { return "This invoice is issued and can no longer be edited." }
        guard invs[i].pricingMode == "Rental" else { return nil }
        if let months = months {
            guard months >= 1 else { return "Charge at least one month." }
            invs[i].rentalMonths = months
        }
        if updatePeriod { invs[i].rentalPeriod = nonBlank(period) }
        invs[i].updatedAt = nowISO()
        invoicesStore.writeAll(invs)
        return nil
    }

    func getInvoice(id: String) -> Invoice? {
        invoicesStore.readAll().first { $0.id == id }
    }

    func getInvoiceDetail(id: String) -> InvoiceDetail? {
        guard let inv = invoicesStore.readAll().first(where: { $0.id == id }) else { return nil }
        guard let project = projectsStore.readAll().first(where: { $0.id == inv.projectId }) else { return nil }
        let items = invoiceLineItems(for: inv.id)
        let totals = invoiceTotals(inv, lineItems: items)
        let client = clientsStore.readAll().first { $0.id == project.clientId }
        let site = sitesStore.readAll().first { $0.id == project.siteId }
        let settingsTerms = getCompanySettings().defaultPaymentTerms
        var detail = InvoiceDetail(
            id: inv.id, invoiceNumber: inv.invoiceNumber, status: inv.status, invoiceDate: inv.invoiceDate,
            dueDate: inv.dueDate, paymentTerms: inv.paymentTerms ?? settingsTerms, discountType: inv.discountType,
            discountValue: inv.discountValue, taxRatePercent: inv.taxRatePercent, amountPaid: inv.amountPaid,
            notes: inv.notes, createdAt: inv.createdAt, updatedAt: inv.updatedAt,
            projectNumber: project.projectNumber, projectName: project.name,
            clientName: client?.companyName, siteName: site?.name,
            lineItems: items, subtotal: totals.subtotal, discountAmount: totals.discountAmount,
            taxAmount: totals.taxAmount, total: totals.total, balanceDue: totals.balanceDue,
            sourceQuotationId: inv.sourceQuotationId,
            sourceQuotationNumber: inv.sourceQuotationId.flatMap { getQuotation(id: $0)?.quotationNumber },
            pricingMode: inv.pricingMode, rentalMonths: invoiceMonths(inv), rentalPeriod: inv.rentalPeriod,
            materialsSubtotal: totals.materials, materialsCharge: totals.materialsCharge, deliveryTotal: totals.delivery,
            otherChargesTotal: totals.other
        )
        detail.paymentTermsFromSettings = inv.paymentTerms == nil && inv.status == "Draft"
        detail.defaultPaymentTerms = settingsTerms
        detail.currency = inv.sourceQuotationId.flatMap { getQuotation(id: $0)?.currency }
        let notes = deliveryNotesStore.readAll()
        detail.deliveryNotes = (inv.sourceDeliveryNoteIds ?? []).compactMap { nid in notes.first { $0.id == nid } }.map { n in
            InvoiceNoteRef(id: n.id, number: n.deliveryNoteNumber, status: n.status,
                           signedCopyName: n.signedCopyPath.map { URL(fileURLWithPath: $0).lastPathComponent },
                           signedCopyExists: n.signedCopyPath.map { fileIsPresent($0) } ?? false)
        }
        return detail
    }

    func touchInvoice(_ id: String) {
        var invs = invoicesStore.readAll()
        guard let index = invs.firstIndex(where: { $0.id == id }) else { return }
        invs[index].updatedAt = nowISO()
        invoicesStore.writeAll(invs)
    }

    func addInvoiceLineItem(invoiceId: String, sourceKey: String?, priceListItemId: String?, itemCode: String, description: String, unit: String, quantity: Double, appliedUnitPrice: Double, section: String?) -> String? {
        guard let inv = getInvoice(id: invoiceId) else { return "Invoice not found." }
        guard inv.status == "Draft" else { return "This invoice is issued and can no longer be edited." }

        let nextSortOrder = (invoiceLineItems(for: invoiceId).map { $0.sortOrder }.max() ?? -1) + 1
        let line = InvoiceLineItem(
            id: makeId("iitem"), invoiceId: invoiceId, sourceKey: sourceKey, priceListItemId: priceListItemId,
            itemCode: itemCode, itemDescription: description, unit: unit, quantity: quantity.rounded(),
            appliedUnitPrice: appliedUnitPrice, section: section, sortOrder: nextSortOrder
        )
        invoiceLineItemsStore.insert(line)
        touchInvoice(invoiceId)
        return nil
    }

    func updateInvoiceLineItem(id: String, quantity: Double?, appliedUnitPrice: Double?, quantityFormula: String? = nil, priceFormula: String? = nil) -> String? {
        var items = invoiceLineItemsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        guard let inv = getInvoice(id: items[index].invoiceId) else { return "Invoice not found." }
        guard inv.status == "Draft" else { return "This invoice is issued and can no longer be edited." }

        if let quantity = quantity {
            items[index].quantity = quantity.rounded()
            items[index].quantityFormula = lineFormula(quantityFormula)
        }
        if let appliedUnitPrice = appliedUnitPrice {
            items[index].appliedUnitPrice = appliedUnitPrice
            items[index].priceFormula = lineFormula(priceFormula)
        }
        invoiceLineItemsStore.writeAll(items)
        touchInvoice(inv.id)
        return nil
    }

    func removeInvoiceLineItem(id: String) -> String? {
        var items = invoiceLineItemsStore.readAll()
        guard let target = items.first(where: { $0.id == id }) else { return "Line item not found." }
        guard let inv = getInvoice(id: target.invoiceId) else { return "Invoice not found." }
        guard inv.status == "Draft" else { return "This invoice is issued and can no longer be edited." }

        items.removeAll { $0.id == id }
        invoiceLineItemsStore.writeAll(items)
        touchInvoice(inv.id)
        return nil
    }

    func updateInvoiceHeader(id: String, dueDate: String?, paymentTerms: String?, notes: String?, discountType: String, discountValue: Double, taxRatePercent: Double) -> String? {
        var invs = invoicesStore.readAll()
        guard let index = invs.firstIndex(where: { $0.id == id }) else { return "Invoice not found." }
        guard invs[index].status == "Draft" else { return "This invoice is issued and can no longer be edited." }

        invs[index].dueDate = dueDate
        // The Settings text (as shown while following it) keeps following
        // Settings; anything else — a blank box too — is this invoice's own.
        let typed = (paymentTerms ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let standard = (getCompanySettings().defaultPaymentTerms ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        invs[index].paymentTerms = typed == standard ? nil : (paymentTerms ?? "")
        invs[index].notes = notes
        invs[index].discountType = discountType
        invs[index].discountValue = discountValue
        invs[index].taxRatePercent = taxRatePercent
        invs[index].updatedAt = nowISO()
        invoicesStore.writeAll(invs)
        return nil
    }

    /// The invoice date (editable while Draft).
    func updateInvoiceDate(id: String, day: String) -> String? {
        var invs = invoicesStore.readAll()
        guard let i = invs.firstIndex(where: { $0.id == id }) else { return "Invoice not found." }
        guard invs[i].status == "Draft" else { return "This invoice is issued and can no longer be edited." }
        guard let iso = isoFromDay(day) else { return "Enter a valid date." }
        invs[i].invoiceDate = iso
        invs[i].updatedAt = nowISO()
        invoicesStore.writeAll(invs)
        return nil
    }

    /// Explicit status changes an admin makes by hand (e.g. Draft →
    /// Issued, or → Cancelled). Payment-driven transitions (→
    /// PartiallyPaid/Paid) happen automatically in recordPayment below.
    func updateInvoiceStatus(id: String, status: String) -> String? {
        var invs = invoicesStore.readAll()
        guard let index = invs.firstIndex(where: { $0.id == id }) else { return "Invoice not found." }
        guard ["Draft", "Issued", "PartiallyPaid", "Paid", "Overdue", "Cancelled"].contains(status) else { return "Invalid status." }
        let previous = invs[index].status
        // Section 25: an issued invoice is a financial record — it's never
        // put back to Draft (which would unlock its figures). Mistakes are
        // corrected by cancelling it and issuing a new one.
        if previous == "Cancelled" && status != "Cancelled" { return "This invoice is cancelled and can't be reopened. Create a new invoice instead." }
        if previous != "Draft" && status == "Draft" { return "An issued invoice can't be returned to Draft. Cancel it and create a new invoice instead." }
        if previous == "Draft" && status != "Draft" && status != "Issued" && status != "Cancelled" { return "Issue this invoice first." }
        if status == "Issued" && previous == "Draft" {
            if invoiceLineItems(for: id).isEmpty { return "Add at least one item before issuing this invoice." }
            if (invs[index].dueDate ?? "").isEmpty { return "Set a due date before issuing this invoice." }
        }
        let changed = previous != status
        invs[index].status = status
        // Once issued, its payment terms stay as printed, whatever Settings
        // says later.
        if previous == "Draft" && status != "Draft" && invs[index].paymentTerms == nil {
            invs[index].paymentTerms = getCompanySettings().defaultPaymentTerms ?? ""
        }
        invs[index].updatedAt = nowISO()
        invoicesStore.writeAll(invs)
        if changed {
            let label = status == "PartiallyPaid" ? "marked partially paid" : status == "Draft" ? "returned to draft" : "marked \(status.lowercased())"
            logActivity(projectId: invs[index].projectId, "Invoice \(status == "Issued" ? "issued" : label)", reference: invs[index].invoiceNumber)
        }
        return nil
    }

    /// Adds `amount` to the invoice's cumulative amountPaid and updates
    /// status accordingly — Paid once the balance reaches zero,
    /// PartiallyPaid otherwise. Rejected on a cancelled invoice.
    func recordInvoicePayment(id: String, amount: Double, date: String? = nil, method: String? = nil, reference: String? = nil) -> String? {
        guard amount > 0 else { return "Payment amount must be greater than zero." }
        var invs = invoicesStore.readAll()
        guard let index = invs.firstIndex(where: { $0.id == id }) else { return "Invoice not found." }
        guard invs[index].status != "Cancelled" else { return "Cannot record a payment on a cancelled invoice." }
        guard invs[index].status != "Draft" else { return "Issue this invoice before recording a payment." }

        let items = invoiceLineItems(for: id)
        let before = invoiceTotals(invs[index], lineItems: items)
        guard roundToCents(decimalOf(amount)) <= decimalOf(before.balanceDue) else {
            return "That's more than the balance due (\(formatMoney(before.balanceDue)))."
        }
        invs[index].amountPaid = doubleOf(roundToCents(decimalOf(invs[index].amountPaid) + decimalOf(amount)))

        let totals = invoiceTotals(invs[index], lineItems: items)
        invs[index].status = totals.balanceDue <= 0 ? "Paid" : "PartiallyPaid"
        invs[index].updatedAt = nowISO()
        invoicesStore.writeAll(invs)
        // Kept for the accounts: when, how much, how.
        invoicePaymentsStore.insert(InvoicePayment(
            id: makeId("payment"), invoiceId: id, date: validDay(date) ?? todayYMD(),
            amount: doubleOf(roundToCents(decimalOf(amount))), method: nonBlank(method), reference: nonBlank(reference), createdAt: nowISO()))
        logActivity(projectId: invs[index].projectId, "Payment recorded: \(getCompanySettings().currency) \(formatMoney(amount))\(totals.balanceDue <= 0 ? " — paid in full" : "")", reference: invs[index].invoiceNumber)
        return nil
    }

    /// Draft only — an issued invoice is cancelled, never deleted
    /// (section 22: "issued financial documents should not be casually
    /// deleted; prefer cancellation/archive mechanisms").
    func deleteInvoice(id: String, includingIssued: Bool = false) -> String? {
        guard let inv = getInvoice(id: id) else { return "Invoice not found." }
        guard inv.status == "Draft" || includingIssued else { return "Only draft invoices can be deleted — cancel it instead." }
        var invs = invoicesStore.readAll()
        invs.removeAll { $0.id == id }
        invoicesStore.writeAll(invs)
        // Its payments go from Accounts too.
        var payments = invoicePaymentsStore.readAll()
        payments.removeAll { $0.invoiceId == id }
        invoicePaymentsStore.writeAll(payments)
        logActivity(projectId: inv.projectId, "\(inv.status == "Draft" ? "Draft" : inv.status) invoice deleted", reference: inv.invoiceNumber)
        var items = invoiceLineItemsStore.readAll()
        items.removeAll { $0.invoiceId == id }
        invoiceLineItemsStore.writeAll(items)
        return nil
    }

    // ---- Delivery Notes (Phase 10) ----

    func deliveryNoteLineItems(for deliveryNoteId: String) -> [DeliveryNoteLineItem] {
        byMaterialList(deliveryNoteLineItemsStore.readAll().filter { $0.deliveryNoteId == deliveryNoteId }, itemId: { $0.priceListItemId },
                       code: { $0.itemCode }, description: { $0.itemDescription }, order: { $0.sortOrder })
    }

    func listDeliveryNoteSummaries(projectId: String) -> [DeliveryNoteSummary] {
        let names = authorsByRecord("delivery_notes.json")
        let quotationNumbers = Dictionary(quotationsStore.readAll().map { ($0.id, $0.quotationNumber) }, uniquingKeysWith: { a, _ in a })
        let invoices = invoicesStore.readAll().filter { $0.projectId == projectId && $0.status != "Cancelled" }
        return deliveryNotesStore.readAll()
            .filter { $0.projectId == projectId }
            .sorted { $0.deliveryNoteNumber > $1.deliveryNoteNumber }
            .map { dn in
                let items = deliveryNoteLineItems(for: dn.id)
                var summary = DeliveryNoteSummary(id: dn.id, deliveryNoteNumber: dn.deliveryNoteNumber, status: dn.status, itemCount: items.count, deliveryDate: dn.deliveryDate, createdAt: dn.createdAt)
                summary.sourceQuotationId = dn.sourceQuotationId
                summary.quotationNumber = dn.sourceQuotationId.flatMap { quotationNumbers[$0] }
                summary.invoiceNumbers = invoices.filter { ($0.sourceDeliveryNoteIds ?? []).contains(dn.id) }.map { $0.invoiceNumber }.sorted()
                summary.signed = dn.signedCopyPath.map { fileIsPresent($0) } ?? false
                summary.totalQuantity = items.reduce(0) { $0 + $1.quantity }
                summary.createdBy = names[dn.id]?.createdBy
                summary.lastEditedBy = names[dn.id]?.lastEditedBy
                return summary
            }
    }

    /// Same per-project convention as BOQs/Quotations/Invoices:
    /// "<projectNumber>-DN-001" (section 24).
    func nextDeliveryNoteNumber(projectNumber: String, projectId: String) -> String {
        nextDocumentNumber(template: numberFormat("DN"), projectNumber: projectNumber, existing: deliveryNotesStore.readAll().map { $0.deliveryNoteNumber }, startAt: getCompanySettings().numberStarts?["DN"] ?? 1)
    }

    /// Creates a delivery note, optionally seeding its line items from an
    /// existing Invoice or Quotation (section 23: what's delivered
    /// usually mirrors what was quoted/invoiced). An invoice source wins
    /// over a quotation source when both are somehow supplied. Copies,
    /// not references.
    func createDeliveryNote(projectId: String, projectNumber: String, sourceQuotationId: String?, sourceInvoiceId: String?) -> DeliveryNote {
        // Deliveries go to the project's site unless changed on the note.
        let siteAddress: String? = projectsStore.readAll().first(where: { $0.id == projectId }).flatMap { project in
            sitesStore.readAll().first(where: { $0.id == project.siteId })
        }.flatMap { site -> String? in
            let parts = [site.address, site.city, site.postalCode].compactMap { nonBlank($0) }
            return parts.isEmpty ? nil : parts.joined(separator: ", ")
        }
        let siteContact = projectsStore.readAll().first(where: { $0.id == projectId })
            .flatMap { project in sitesStore.readAll().first(where: { $0.id == project.siteId }) }
            .flatMap { nonBlank($0.contactPerson) }
        // From a quotation (or an invoice): its number, DN26001-004 for Qt26001-004.
        let existingNumbers: [String] = deliveryNotesStore.readAll().map { $0.deliveryNoteNumber }
        var linked: String? = nil
        if let invId = sourceInvoiceId, let inv = getInvoice(id: invId) {
            linked = linkedNumber(type: "DN", sourceType: "INV", sourceNumber: inv.invoiceNumber, projectNumber: projectNumber, existing: existingNumbers)
        }
        if linked == nil, let qId = sourceQuotationId, let q = getQuotation(id: qId) {
            linked = linkedNumber(type: "DN", sourceType: "QT", sourceNumber: q.quotationNumber, projectNumber: projectNumber, existing: existingNumbers)
        }
        let note = DeliveryNote(
            id: makeId("dn"), projectId: projectId, sourceQuotationId: sourceQuotationId, sourceInvoiceId: sourceInvoiceId,
            deliveryNoteNumber: linked ?? nextDeliveryNoteNumber(projectNumber: projectNumber, projectId: projectId),
            status: "Draft", deliveryDate: nowISO(), deliveryAddress: siteAddress, deliveredBy: nil, receivedBy: nil,
            notes: nil, createdAt: nowISO(), updatedAt: nowISO(), contactPerson: siteContact
        )
        deliveryNotesStore.insert(note)
        logActivity(projectId: projectId, "Delivery note created", reference: note.deliveryNoteNumber)

        var seeds: [(sourceKey: String?, priceListItemId: String?, itemCode: String, itemDescription: String, unit: String, quantity: Double, section: String?, sortOrder: Int)] = []
        if let invoiceId = sourceInvoiceId {
            // Materials only: not delivery charges or other one-off charges.
            seeds = invoiceLineItemsStore.readAll()
                .filter { $0.invoiceId == invoiceId && $0.section != "Delivery" && $0.chargeGroup == nil }
                .sorted { $0.sortOrder < $1.sortOrder }
                .enumerated().map { index, item in (item.sourceKey, item.priceListItemId, item.itemCode, item.itemDescription, item.unit, item.quantity, item.section, index) }
        } else if let quotationId = sourceQuotationId {
            seeds = quotationLineItemsStore.readAll()
                .filter { $0.quotationId == quotationId && isMaterialLine($0) }
                .sorted { $0.sortOrder < $1.sortOrder }
                .enumerated().map { index, item in (item.sourceKey, item.priceListItemId, item.itemCode, item.itemDescription, item.unit, item.quantity, item.section, index) }
        }
        if !seeds.isEmpty {
            let copied: [DeliveryNoteLineItem] = seeds.map { item in
                DeliveryNoteLineItem(
                    id: makeId("dnitem"), deliveryNoteId: note.id, sourceKey: item.sourceKey,
                    priceListItemId: item.priceListItemId, itemCode: item.itemCode,
                    itemDescription: item.itemDescription, unit: item.unit, quantity: item.quantity.rounded(),
                    section: item.section, sortOrder: item.sortOrder, notes: nil
                )
            }
            deliveryNoteLineItemsStore.insertMany(copied)
        }
        return note
    }

    /// Several delivery notes of a project added together into one new Draft
    /// note: each item once, its quantities summed.
    func combineDeliveryNotes(ids: [String]) -> (id: String?, error: String?) {
        let all = deliveryNotesStore.readAll()
        let notesList = ids.compactMap { id in all.first { $0.id == id } }
        guard notesList.count >= 2 else { return (nil, "Choose at least two delivery notes to combine.") }
        guard Set(notesList.map { $0.projectId }).count == 1,
              let project = projectsStore.readAll().first(where: { $0.id == notesList[0].projectId }) else { return (nil, "The delivery notes must be from the same project.") }
        let combined = createDeliveryNote(projectId: project.id, projectNumber: project.projectNumber, sourceQuotationId: nil, sourceInvoiceId: nil)
        var order: [String] = []
        var lines: [String: DeliveryNoteLineItem] = [:]
        for note in notesList {
            for line in deliveryNoteLineItems(for: note.id) {
                let key = line.priceListItemId ?? "\(line.itemCode)|\(line.itemDescription)|\(line.unit)"
                if var existing = lines[key] {
                    existing.quantity += line.quantity
                    lines[key] = existing
                } else {
                    var copy = line
                    copy.id = makeId("dnitem")
                    copy.deliveryNoteId = combined.id
                    lines[key] = copy
                    order.append(key)
                }
            }
        }
        deliveryNoteLineItemsStore.insertMany(order.enumerated().compactMap { index, key in
            guard var line = lines[key] else { return nil }
            line.sortOrder = index
            return line
        })
        var notesNow = deliveryNotesStore.readAll()
        if let i = notesNow.firstIndex(where: { $0.id == combined.id }) {
            notesNow[i].notes = "Combined from \(notesList.map { $0.deliveryNoteNumber }.joined(separator: ", "))."
            deliveryNotesStore.writeAll(notesNow)
        }
        return (combined.id, nil)
    }

    /// A quotation's materials copied into a Draft delivery note: items
    /// already on the note get the quotation's quantity added (or, with
    /// `replaceExisting`, the note's items are cleared first).
    func importQuotationIntoDeliveryNote(deliveryNoteId: String, quotationId: String, replaceExisting: Bool) -> (added: Int, error: String?) {
        guard let dn = getDeliveryNote(id: deliveryNoteId) else { return (0, "Delivery note not found.") }
        guard dn.status == "Draft" else { return (0, "This delivery note is issued and can no longer be edited.") }
        guard let quotation = quotationsStore.readAll().first(where: { $0.id == quotationId }) else { return (0, "Quotation not found.") }
        guard quotation.projectId == dn.projectId else { return (0, "The quotation must be from the same project.") }
        let source = quotationLineItemsStore.readAll()
            .filter { $0.quotationId == quotationId && isMaterialLine($0) }
            .sorted { $0.sortOrder < $1.sortOrder }
        guard !source.isEmpty else { return (0, "\(quotation.quotationNumber) has no materials to import.") }

        var items = deliveryNoteLineItemsStore.readAll()
        if replaceExisting { items.removeAll { $0.deliveryNoteId == deliveryNoteId } }
        let key: (String?, String, String, String) -> String = { id, code, description, unit in id ?? "\(code)|\(description)|\(unit)" }
        var nextSort = (items.filter { $0.deliveryNoteId == deliveryNoteId }.map { $0.sortOrder }.max() ?? -1) + 1
        var added = 0
        for line in source {
            let k = key(line.priceListItemId, line.itemCode, line.itemDescription, line.unit)
            if let i = items.firstIndex(where: { $0.deliveryNoteId == deliveryNoteId && key($0.priceListItemId, $0.itemCode, $0.itemDescription, $0.unit) == k }) {
                items[i].quantity += line.quantity.rounded()
            } else {
                items.append(DeliveryNoteLineItem(
                    id: makeId("dnitem"), deliveryNoteId: deliveryNoteId, sourceKey: line.sourceKey,
                    priceListItemId: line.priceListItemId, itemCode: line.itemCode,
                    itemDescription: line.itemDescription, unit: line.unit, quantity: line.quantity.rounded(),
                    section: line.section, sortOrder: nextSort, notes: nil
                ))
                nextSort += 1
            }
            added += 1
        }
        deliveryNoteLineItemsStore.writeAll(items)

        var notesArr = deliveryNotesStore.readAll()
        if let i = notesArr.firstIndex(where: { $0.id == deliveryNoteId }) {
            if notesArr[i].sourceQuotationId == nil { notesArr[i].sourceQuotationId = quotationId }
            notesArr[i].updatedAt = nowISO()
            deliveryNotesStore.writeAll(notesArr)
        }
        logActivity(projectId: dn.projectId, "Materials imported from \(quotation.quotationNumber)", reference: dn.deliveryNoteNumber)
        return (added, nil)
    }

    func getDeliveryNote(id: String) -> DeliveryNote? {
        deliveryNotesStore.readAll().first { $0.id == id }
    }

    func getDeliveryNoteDetail(id: String) -> DeliveryNoteDetail? {
        guard let dn = deliveryNotesStore.readAll().first(where: { $0.id == id }) else { return nil }
        guard let project = projectsStore.readAll().first(where: { $0.id == dn.projectId }) else { return nil }
        let items = deliveryNoteLineItems(for: dn.id)
        let client = clientsStore.readAll().first { $0.id == project.clientId }
        let site = sitesStore.readAll().first { $0.id == project.siteId }
        var detail = DeliveryNoteDetail(
            id: dn.id, deliveryNoteNumber: dn.deliveryNoteNumber, status: dn.status, deliveryDate: dn.deliveryDate,
            deliveryAddress: dn.deliveryAddress, deliveredBy: dn.deliveredBy, receivedBy: dn.receivedBy,
            notes: dn.notes, createdAt: dn.createdAt, updatedAt: dn.updatedAt,
            projectNumber: project.projectNumber, projectName: project.name,
            clientName: client?.companyName, siteName: site?.name, lineItems: items,
            contactPerson: dn.contactPerson, projectId: dn.projectId, sourceQuotationId: dn.sourceQuotationId,
            chineseNames: chineseNames(for: items, id: { $0.id }, itemId: { $0.priceListItemId }, description: { $0.itemDescription }),
            language: dn.language, defaultLanguage: getCompanySettings().documentLanguage ?? "English",
            signedCopyName: dn.signedCopyPath.map { URL(fileURLWithPath: $0).lastPathComponent }, signedCopyAt: dn.signedCopyAt,
            signedCopyExists: dn.signedCopyPath.map { fileIsPresent($0) } ?? false,
            invoiceNumbers: invoicesStore.readAll().filter { $0.status != "Cancelled" && ($0.sourceDeliveryNoteIds ?? []).contains(dn.id) }.map { $0.invoiceNumber }.sorted()
        )
        detail.stockBooked = stockMovementsStore.readAll().contains { $0.deliveryNoteId == dn.id }
        detail.isSale = deliveryNoteIsSale(dn)
        if detail.stockBooked && !detail.isSale {
            let row = deliveryReturns().first { $0.deliveryNoteId == dn.id }
            detail.stockOutstanding = row?.outstanding ?? 0
            detail.returnCheckDate = row?.checkDate
        }
        return detail
    }

    func touchDeliveryNote(_ id: String) {
        var notesArr = deliveryNotesStore.readAll()
        guard let index = notesArr.firstIndex(where: { $0.id == id }) else { return }
        notesArr[index].updatedAt = nowISO()
        deliveryNotesStore.writeAll(notesArr)
    }

    func addDeliveryNoteLineItem(deliveryNoteId: String, sourceKey: String?, priceListItemId: String?, itemCode: String, description: String, unit: String, quantity: Double, section: String?) -> String? {
        guard let dn = getDeliveryNote(id: deliveryNoteId) else { return "Delivery note not found." }
        guard dn.status == "Draft" else { return "This delivery note is issued and can no longer be edited." }

        let nextSortOrder = (deliveryNoteLineItems(for: deliveryNoteId).map { $0.sortOrder }.max() ?? -1) + 1
        let line = DeliveryNoteLineItem(
            id: makeId("dnitem"), deliveryNoteId: deliveryNoteId, sourceKey: sourceKey, priceListItemId: priceListItemId,
            itemCode: itemCode, itemDescription: description, unit: unit, quantity: quantity.rounded(),
            section: section, sortOrder: nextSortOrder, notes: nil
        )
        deliveryNoteLineItemsStore.insert(line)
        touchDeliveryNote(deliveryNoteId)
        return nil
    }

    /// A custom item (not from a material list) changed after it was added:
    /// its description (formatting kept) and unit, on a draft BOQ,
    /// quotation, delivery note or invoice.
    func editCustomLine(kind: String, id: String, description: String, unit: String?) -> String? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "Enter a description." }
        let newUnit = unit.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
        switch kind {
        case "quotation":
            return updateQuotationLineItem(id: id, quantity: nil, appliedUnitPrice: nil, description: text, unit: newUnit)
        case "boq":
            var items = boqLineItemsStore.readAll()
            guard let i = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
            guard let boq = getBOQ(id: items[i].boqId), boq.status == "Draft" else { return "This BOQ is issued and can no longer be edited." }
            items[i].itemDescription = text
            if let u = newUnit { items[i].unit = u }
            boqLineItemsStore.writeAll(items)
            touchBOQ(boq.id)
            syncLinkedQuotations(boqId: boq.id)
            return nil
        case "invoice":
            var items = invoiceLineItemsStore.readAll()
            guard let i = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
            guard let inv = getInvoice(id: items[i].invoiceId), inv.status == "Draft" else { return "This invoice is issued and can no longer be edited." }
            items[i].itemDescription = text
            if let u = newUnit { items[i].unit = u }
            invoiceLineItemsStore.writeAll(items)
            touchInvoice(inv.id)
            return nil
        case "deliveryNote":
            var items = deliveryNoteLineItemsStore.readAll()
            guard let i = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
            guard let dn = getDeliveryNote(id: items[i].deliveryNoteId), dn.status == "Draft" else { return "This delivery note is issued and can no longer be edited." }
            items[i].itemDescription = text
            if let u = newUnit { items[i].unit = u }
            deliveryNoteLineItemsStore.writeAll(items)
            touchDeliveryNote(dn.id)
            return nil
        default:
            return "Unknown document."
        }
    }

    func updateDeliveryNoteLineItem(id: String, quantity: Double?, quantityFormula: String? = nil) -> String? {
        var items = deliveryNoteLineItemsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        guard let dn = getDeliveryNote(id: items[index].deliveryNoteId) else { return "Delivery note not found." }
        guard dn.status == "Draft" else { return "This delivery note is issued and can no longer be edited." }

        if let quantity = quantity {
            items[index].quantity = quantity.rounded()
            items[index].quantityFormula = lineFormula(quantityFormula)
        }
        deliveryNoteLineItemsStore.writeAll(items)
        touchDeliveryNote(dn.id)
        return nil
    }

    /// Sets many of a document's quantities at once — "Multiply…" (and its
    /// Undo), or anything else that changes quantities in bulk. `kind` is
    /// "boq", "quotation", "invoice" or "deliveryNote"; `quantities` is line
    /// id → new quantity (whole numbers, as everywhere). Only a Draft
    /// changes; lines of other documents are left alone. A BOQ's linked
    /// quotations follow it, and a linked quotation's BOQ follows it.
    func setLineQuantities(kind: String, documentId: String, quantities: [String: Double]) -> String? {
        let wanted = quantities.mapValues { max(0, $0.rounded()) }
        if wanted.isEmpty { return nil }
        switch kind {
        case "boq":
            guard let boq = getBOQ(id: documentId) else { return "BOQ not found." }
            guard boq.status == "Draft" else { return "This BOQ is issued and can no longer be edited." }
            var items = boqLineItemsStore.readAll()
            for i in items.indices where items[i].boqId == documentId {
                if let n = wanted[items[i].id] { items[i].quantity = n; items[i].quantityFormula = nil }
            }
            boqLineItemsStore.writeAll(items)
            touchBOQ(documentId)
            syncLinkedQuotations(boqId: documentId)
        case "quotation":
            guard let q = getQuotation(id: documentId) else { return "Quotation not found." }
            guard q.status == "Draft" else { return "This quotation is issued and can no longer be edited." }
            var items = quotationLineItemsStore.readAll()
            for i in items.indices where items[i].quotationId == documentId {
                if let n = wanted[items[i].id] { items[i].quantity = n; items[i].quantityFormula = nil }
            }
            quotationLineItemsStore.writeAll(items)
            touchQuotation(documentId)
            pushQuotationToBOQ(documentId)
        case "invoice":
            guard let inv = getInvoice(id: documentId) else { return "Invoice not found." }
            guard inv.status == "Draft" else { return "This invoice is issued and can no longer be edited." }
            var items = invoiceLineItemsStore.readAll()
            for i in items.indices where items[i].invoiceId == documentId {
                if let n = wanted[items[i].id] { items[i].quantity = n; items[i].quantityFormula = nil }
            }
            invoiceLineItemsStore.writeAll(items)
            touchInvoice(documentId)
        case "deliveryNote":
            guard let dn = getDeliveryNote(id: documentId) else { return "Delivery note not found." }
            guard dn.status == "Draft" else { return "This delivery note is issued and can no longer be edited." }
            var items = deliveryNoteLineItemsStore.readAll()
            for i in items.indices where items[i].deliveryNoteId == documentId {
                if let n = wanted[items[i].id] { items[i].quantity = n; items[i].quantityFormula = nil }
            }
            deliveryNoteLineItemsStore.writeAll(items)
            touchDeliveryNote(documentId)
        default:
            return "This document can't be multiplied."
        }
        return nil
    }

    func removeDeliveryNoteLineItem(id: String) -> String? {
        var items = deliveryNoteLineItemsStore.readAll()
        guard let target = items.first(where: { $0.id == id }) else { return "Line item not found." }
        guard let dn = getDeliveryNote(id: target.deliveryNoteId) else { return "Delivery note not found." }
        guard dn.status == "Draft" else { return "This delivery note is issued and can no longer be edited." }

        items.removeAll { $0.id == id }
        deliveryNoteLineItemsStore.writeAll(items)
        touchDeliveryNote(dn.id)
        return nil
    }

    func updateDeliveryNoteHeader(id: String, deliveryAddress: String?, deliveredBy: String?, receivedBy: String?, notes: String?,
                                  contactPerson: String?? = nil) -> String? {
        var notesArr = deliveryNotesStore.readAll()
        guard let index = notesArr.firstIndex(where: { $0.id == id }) else { return "Delivery note not found." }
        guard notesArr[index].status == "Draft" else { return "This delivery note is issued and can no longer be edited." }

        if let contact = contactPerson { notesArr[index].contactPerson = contact }
        notesArr[index].deliveryAddress = deliveryAddress
        notesArr[index].deliveredBy = deliveredBy
        notesArr[index].receivedBy = receivedBy
        notesArr[index].notes = notes
        notesArr[index].updatedAt = nowISO()
        deliveryNotesStore.writeAll(notesArr)
        return nil
    }

    /// The delivery date (editable while Draft).
    func updateDeliveryNoteDate(id: String, day: String) -> String? {
        var notesArr = deliveryNotesStore.readAll()
        guard let i = notesArr.firstIndex(where: { $0.id == id }) else { return "Delivery note not found." }
        guard notesArr[i].status == "Draft" else { return "This delivery note is issued and can no longer be edited." }
        guard let iso = isoFromDay(day) else { return "Enter a valid date." }
        notesArr[i].deliveryDate = iso
        notesArr[i].updatedAt = nowISO()
        deliveryNotesStore.writeAll(notesArr)
        return nil
    }

    func updateDeliveryNoteStatus(id: String, status: String) -> String? {
        var notesArr = deliveryNotesStore.readAll()
        guard let index = notesArr.firstIndex(where: { $0.id == id }) else { return "Delivery note not found." }
        guard ["Draft", "Issued", "Cancelled"].contains(status) else { return "Invalid status." }
        let previous = notesArr[index].status
        if previous == "Cancelled" && status != "Cancelled" { return "This delivery note is cancelled and can't be reopened. Create a new delivery note instead." }
        if status == "Issued" && previous == "Draft" && deliveryNoteLineItems(for: id).isEmpty { return "Add at least one item before issuing this delivery note." }
        let changed = previous != status
        notesArr[index].status = status
        notesArr[index].updatedAt = nowISO()
        deliveryNotesStore.writeAll(notesArr)
        // Stock: an issued, signed delivery note books its items out of the
        // yard; cancelling or reopening it puts them back.
        syncDeliveryStock(notesArr[index])
        if changed { logActivity(projectId: notesArr[index].projectId, "Delivery note \(status == "Draft" ? "returned to draft" : status.lowercased())", reference: notesArr[index].deliveryNoteNumber) }
        return nil
    }

    /// Draft only — same "don't casually delete a formal document" rule
    /// as BOQs/Quotations/Invoices (section 25).
    func deleteDeliveryNote(id: String, includingIssued: Bool = false) -> String? {
        guard let dn = getDeliveryNote(id: id) else { return "Delivery note not found." }
        guard dn.status == "Draft" || includingIssued else { return "Only draft delivery notes can be deleted." }
        var notesArr = deliveryNotesStore.readAll()
        notesArr.removeAll { $0.id == id }
        deliveryNotesStore.writeAll(notesArr)
        // Its items go back into the stock list.
        removeDeliveryStock(deliveryNoteId: id)
        logActivity(projectId: dn.projectId, "\(dn.status == "Draft" ? "Draft" : dn.status) delivery note deleted", reference: dn.deliveryNoteNumber)
        var items = deliveryNoteLineItemsStore.readAll()
        items.removeAll { $0.deliveryNoteId == id }
        deliveryNoteLineItemsStore.writeAll(items)
        return nil
    }

    /// Remembers where a document's exported PDF was saved (section 32).
    func recordGeneratedPDF(docTypeTag: String, documentNumber: String, path: String) {
        switch docTypeTag {
        case "BOQ":
            var all = boqsStore.readAll()
            guard let i = all.firstIndex(where: { $0.boqNumber == documentNumber }) else { return }
            all[i].pdfPath = path
            boqsStore.writeAll(all)
        case "Quotation":
            var all = quotationsStore.readAll()
            guard let i = all.firstIndex(where: { $0.quotationNumber == documentNumber }) else { return }
            all[i].pdfPath = path
            quotationsStore.writeAll(all)
        case "Letter":
            var all = lettersStore.readAll()
            guard let i = all.firstIndex(where: { $0.letterNumber == documentNumber }) else { return }
            all[i].pdfPath = path
            lettersStore.writeAll(all)
        case "Invoice":
            var all = invoicesStore.readAll()
            guard let i = all.firstIndex(where: { $0.invoiceNumber == documentNumber }) else { return }
            all[i].pdfPath = path
            invoicesStore.writeAll(all)
        case "DeliveryNote":
            var all = deliveryNotesStore.readAll()
            guard let i = all.firstIndex(where: { $0.deliveryNoteNumber == documentNumber }) else { return }
            all[i].pdfPath = path
            deliveryNotesStore.writeAll(all)
        default:
            break
        }
    }

    // ---- Company settings (section 28) ----

    /// Always a single record with a fixed id — created with sensible
    /// defaults the first time it's requested.
    func getCompanySettings() -> CompanySettings {
        if let existing = settingsStore.readAll().first { return existing }
        let defaults = CompanySettings(
            id: "company", companyName: "Proficiency (HK) Limited",
            addressLine1: nil, addressLine2: nil, phone: nil, email: nil, website: nil,
            registrationNumber: nil, vatNumber: nil, bankDetails: nil,
            defaultPaymentTerms: nil, defaultNotes: nil, currency: "HKD", defaultTaxRatePercent: 0,
            pricesIncludeTax: false, paperSize: "A4", appearance: "System", logoPath: nil,
            numberFormatBOQ: nil, numberFormatQuotation: nil, numberFormatInvoice: nil, numberFormatDeliveryNote: nil,
            defaultInvoiceDueDays: 30,
            signatoryName: "Richard Kwan", signatoryTitle: "Director", termsURL: "www.pfitnet.com/TC",
            quotationTerms: defaultQuotationTerms, quotationAcceptance: defaultQuotationAcceptance,
            standardDeliveryCharge: 3800, defaultMinimumHireMonths: 2, exchangeRates: ["EUR": 8.93], numberStarts: nil
        )
        settingsStore.writeAll([defaults])
        return defaults
    }

    /// Costs › Manpower: the workers, what we charge and what each provider
    /// charges us.
    func manpowerPage() -> ManpowerPage {
        let s = getCompanySettings()
        return ManpowerPage(rates: s.manpowerRates ?? defaultManpowerRates, providers: s.manpowerProviders ?? defaultManpowerProviders)
    }

    func saveManpower(_ payload: [String: Any]) -> String? {
        var settings = getCompanySettings()
        var providers: [String] = []
        for raw in (payload["providers"] as? [String]) ?? [] {
            let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty && !providers.contains(where: { $0.lowercased() == name.lowercased() }) { providers.append(name) }
        }
        let number: (Any?) -> Double? = { v in (v as? NSNumber)?.doubleValue ?? (v as? String).flatMap { Double($0) } }
        let rates: [ManpowerRate] = ((payload["rates"] as? [[String: Any]]) ?? []).compactMap { item in
            guard let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
            let unit = ((item["unit"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            var costs: [String: Double] = [:]
            for (provider, value) in (item["costs"] as? [String: Any]) ?? [:] where providers.contains(provider) {
                if let v = number(value), v >= 0 { costs[provider] = v }
            }
            return ManpowerRate(name: name, rate: max(0, number(item["rate"]) ?? 0), unit: unit.isEmpty ? "md" : unit, costs: costs.isEmpty ? nil : costs)
        }
        settings.manpowerRates = rates
        settings.manpowerProviders = providers
        settingsStore.writeAll([settings])
        return nil
    }

    /// The team's AI connection (Settings › AI Import); nil key removes it.
    func setAIConnection(provider: String?, model: String?, key: String?) {
        var settings = getCompanySettings()
        settings.aiProvider = provider
        settings.aiModel = model
        settings.aiKey = key
        settingsStore.writeAll([settings])
    }

    func updateCompanySettings(_ payload: [String: Any]) -> CompanySettings {
        var settings = getCompanySettings()
        if let v = payload["companyName"] as? String, !v.isEmpty { settings.companyName = v }
        // Only fields actually sent are changed — so saving one option
        // (e.g. Appearance) never blanks the company details.
        func optionalText(_ key: String) -> String?? {
            guard payload.keys.contains(key) else { return .none }
            let v = (payload[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            return .some((v?.isEmpty ?? true) ? nil : v)
        }
        if let v = optionalText("addressLine1") { settings.addressLine1 = v }
        if let v = optionalText("addressLine2") { settings.addressLine2 = v }
        if let v = optionalText("phone") { settings.phone = v }
        if let v = optionalText("email") { settings.email = v }
        if let v = optionalText("website") { settings.website = v }
        if let v = optionalText("registrationNumber") { settings.registrationNumber = v }
        if let v = optionalText("vatNumber") { settings.vatNumber = v }
        if let v = optionalText("bankDetails") { settings.bankDetails = v }
        if let v = optionalText("defaultPaymentTerms") { settings.defaultPaymentTerms = v }
        if let v = optionalText("defaultNotes") { settings.defaultNotes = v }
        if let v = payload["currency"] as? String, !v.isEmpty { settings.currency = v }
        if let v = payload["defaultTaxRatePercent"] as? Double { settings.defaultTaxRatePercent = v }
        // Newer options: only changed when the page actually sends them.
        if let v = payload["pricesIncludeTax"] as? Bool { settings.pricesIncludeTax = v }
        if let v = payload["paperSize"] as? String, ["A4", "Letter"].contains(v) { settings.paperSize = v }
        if let v = payload["appearance"] as? String, ["System", "Light", "Dark"].contains(v) { settings.appearance = v }
        if let v = payload["defaultInvoiceDueDays"] as? Int { settings.defaultInvoiceDueDays = max(0, v) }
        func format(_ key: String) -> String?? {
            guard payload.keys.contains(key) else { return .none }
            let raw = ((payload[key] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            return .some(raw.isEmpty ? nil : raw)
        }
        if let v = format("numberFormatBOQ") { settings.numberFormatBOQ = v }
        if let v = format("numberFormatQuotation") { settings.numberFormatQuotation = v }
        if let v = format("numberFormatInvoice") { settings.numberFormatInvoice = v }
        if let v = format("numberFormatDeliveryNote") { settings.numberFormatDeliveryNote = v }
        if let v = format("numberFormatLetter") { settings.numberFormatLetter = v }
        if let v = payload["linkedNumbers"] as? Bool { settings.linkedNumbers = v ? nil : false }
        if let v = optionalText("signatoryName") { settings.signatoryName = v }
        if let v = optionalText("signatoryTitle") { settings.signatoryTitle = v }
        if let v = optionalText("termsURL") { settings.termsURL = v }
        if payload.keys.contains("quotationTermsSale") { settings.quotationTermsSale = (payload["quotationTermsSale"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } }
        if payload.keys.contains("quotationTerms") { settings.quotationTerms = (payload["quotationTerms"] as? String).flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } }
        if let v = optionalText("quotationAcceptance") { settings.quotationAcceptance = v }
        if payload.keys.contains("standardDeliveryCharge") { settings.standardDeliveryCharge = payload["standardDeliveryCharge"] as? Double }
        if let list = payload["deliveryRates"] as? [[String: Any]] {
            func number(_ v: Any?) -> Double? { (v as? Double) ?? (v as? Int).map(Double.init) }
            let rates = list.compactMap { r -> DeliveryRate? in
                guard let kg = number(r["upToKg"]), kg > 0, let price = number(r["price"]), price >= 0 else { return nil }
                return DeliveryRate(upToKg: kg, price: price)
            }.sorted { $0.upToKg < $1.upToKg }
            settings.deliveryRates = rates.isEmpty ? nil : rates
        }
        if let v = payload["defaultMinimumHireMonths"] as? Int { settings.defaultMinimumHireMonths = max(1, v) }
        if let v = (payload["buyBackPercent"] as? NSNumber)?.doubleValue { settings.buyBackPercent = min(100, max(0, v)) }
        if let v = (payload["buyBackAfterMonths"] as? NSNumber)?.intValue { settings.buyBackAfterMonths = max(0, v) }
        if let v = (payload["buyBackReductionPercent"] as? NSNumber)?.doubleValue { settings.buyBackReductionPercent = min(100, max(0, v)) }
        if let v = (payload["buyBackEndMonths"] as? NSNumber)?.intValue { settings.buyBackEndMonths = max(0, v) }
        if payload.keys.contains("buyBackWording") {
            let v = (payload["buyBackWording"] as? String).flatMap { nonBlank($0) }
            settings.buyBackWording = v == BuyBackTerms.defaultWording ? nil : v
        }
        if let v = payload["termsNewPage"] as? String, ["WhenLong", "Always"].contains(v) { settings.termsNewPage = v == "Always" ? v : nil }
        if let v = payload["markupRounding"] as? String, ["Nearest", "Up"].contains(v) { settings.markupRoundUp = v == "Up" ? true : nil }
        if let list = payload["manpowerRates"] as? [[String: Any]] {
            let before = settings.manpowerRates ?? []
            settings.manpowerRates = list.compactMap { item in
                guard let name = (item["name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
                let unit = ((item["unit"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                return ManpowerRate(name: name, rate: max(0, (item["rate"] as? Double) ?? 0), unit: unit.isEmpty ? "md" : unit,
                                    costs: before.first { $0.name.lowercased() == name.lowercased() }?.costs)
            }
        }
        if let v = payload["minimumMonthlyRental"] as? Double { settings.minimumMonthlyRental = max(0, v) }
        if let v = payload["documentLanguage"] as? String { settings.documentLanguage = v == "Chinese" ? "Chinese" : nil }
        if payload.keys.contains("boqTerms") { settings.boqTerms = nonBlank(payload["boqTerms"] as? String) }
        if let list = payload["defaultBOQItems"] as? [[String: Any]] {
            var seen = Set<String>()
            let items: [DefaultBOQItem] = list.compactMap { item in
                guard let itemId = item["priceListItemId"] as? String, !itemId.isEmpty, seen.insert(itemId).inserted else { return nil }
                let quantity = ((item["quantity"] as? Double) ?? 1).rounded()
                return DefaultBOQItem(priceListItemId: itemId, quantity: max(1, quantity))
            }
            settings.defaultBOQItems = items.isEmpty ? nil : items
        }
        if let rates = payload["exchangeRates"] as? [String: Any] {
            var clean: [String: Double] = settings.exchangeRates ?? [:]
            for (k, v) in rates { if let d = v as? Double, d > 0 { clean[k.uppercased()] = d } }
            settings.exchangeRates = clean
        }
        if let starts = payload["numberStarts"] as? [String: Any] {
            var clean: [String: Int] = [:]
            for (k, v) in starts { if let n = v as? Int, n > 0 { clean[k] = n } }
            settings.numberStarts = clean.isEmpty ? nil : clean
        }
        settingsStore.writeAll([settings])
        return settings
    }

    /// Saves settings changed in code (not from the Settings page).
    func saveCompanySettingsDirect(_ settings: CompanySettings) {
        settingsStore.writeAll([settings])
    }

    func setLogoPath(_ path: String?) {
        var settings = getCompanySettings()
        settings.logoPath = path
        settingsStore.writeAll([settings])
    }

    /// The number for a document made from another (its source): the same
    /// sequence — the invoice for Qt26001-004 is H26001-004, a second one
    /// H26001-004-2. nil (the next number is used) when switched off in
    /// Settings, when the source's number doesn't follow its format, or
    /// when one format runs per project and the other doesn't (a per-
    /// project 004 isn't the company's 4th quotation of the year).
    func linkedNumber(type: String, sourceType: String, sourceNumber: String, projectNumber: String, existing: [String]) -> String? {
        guard getCompanySettings().linkedNumbers != false else { return nil }
        let target = numberFormat(type), source = numberFormat(sourceType)
        guard target.contains("{PROJECT}") == source.contains("{PROJECT}"),
              let seq = sequencePart(of: sourceNumber, template: source, projectNumber: projectNumber) else { return nil }
        return linkedDocumentNumber(template: target, projectNumber: projectNumber, existing: existing, sequence: seq)
    }

    func numberFormat(_ type: String) -> String {
        let s = getCompanySettings()
        let custom: String?
        switch type {
        case "BOQ": custom = s.numberFormatBOQ
        case "QT": custom = s.numberFormatQuotation
        case "INV": custom = s.numberFormatInvoice
        case "LT": custom = s.numberFormatLetter
        default: custom = s.numberFormatDeliveryNote
        }
        return custom ?? defaultNumberFormats[type] ?? "{PROJECT}-\(type)-{SEQ}"
    }

    // ---- Drawings (Phase 11 — section 14) ----

    func listDrawings(projectId: String) -> [ProjectDrawingSummary] {
        drawingSummaries(drawingsStore.readAll().filter { $0.projectId == projectId && !$0.isArchived })
    }

    /// Drawings that belonged to a deleted BOQ or quotation stay with the project.
    func unlinkDrawings(kind: String, id: String) {
        var items = drawingsStore.readAll()
        var changed = false
        for i in items.indices where items[i].linkedKind == kind && items[i].linkedId == id {
            items[i].linkedKind = nil
            items[i].linkedId = nil
            changed = true
        }
        if changed { drawingsStore.writeAll(items) }
    }

    /// The drawings of one BOQ or quotation, in the order they're added to
    /// its PDF: for a quotation that follows a BOQ, the BOQ's drawings first,
    /// then its own; each oldest first.
    func listDrawings(linkedKind: String, linkedId: String) -> [ProjectDrawingSummary] {
        let boq = linkedKind == "Quotation" ? getQuotation(id: linkedId)?.sourceBOQId.flatMap { getBOQ(id: $0) } : nil
        // The BOQ itself comes first, as a PDF of its own pages.
        var boqRow: [ProjectDrawingSummary] = []
        if let boq = boq, !lineItems(for: boq.id).isEmpty {
            boqRow = [ProjectDrawingSummary(
                id: "boq:\(boq.id)", originalName: "\(boq.boqNumber) (the BOQ)", storedFilename: "\(boq.boqNumber) — Bill of Quantities",
                fileType: "PDF", fileSizeBytes: 0, description: "Its latest version, made fresh each time the quotation is exported or printed.",
                uploadedAt: boq.updatedAt, fileExists: true, linkedKind: "BOQ", linkedId: boq.id, linkedNumber: boq.boqNumber,
                fromBOQNumber: boq.boqNumber, appended: true, boqId: boq.id)]
        }
        return boqRow + documentDrawings(kind: linkedKind, id: linkedId).map { d in
            var summary = drawingSummaries([d])[0]
            // One added to the linked BOQ or quotation: "From BQ26212-001".
            if !(d.linkedKind == linkedKind && d.linkedId == linkedId) { summary.fromBOQNumber = summary.linkedNumber }
            summary.appended = PDFAttachments.canAppend(URL(fileURLWithPath: d.filePath)) && summary.fileExists
            return summary
        }
    }

    /// See `listDrawings(linkedKind:linkedId:)`.
    /// A BOQ and the quotations linked to it share their drawings: a
    /// drawing added to any of them is listed (and printed) with each. A
    /// quotation only made from a BOQ (not linked) has the BOQ's drawings.
    func documentDrawings(kind: String, id: String) -> [ProjectDrawing] {
        let all = drawingsStore.readAll().filter { !$0.isArchived }
        let byDate: (ProjectDrawing, ProjectDrawing) -> Bool = { $0.uploadedAt < $1.uploadedAt }
        let own = all.filter { $0.linkedKind == kind && $0.linkedId == id }.sorted(by: byDate)
        let linkedQuotations: (String) -> [String] = { boqId in
            self.quotationsStore.readAll().filter { $0.sourceBOQId == boqId && $0.boqLinked == true }.map { $0.id }
        }
        let ofQuotations: ([String]) -> [ProjectDrawing] = { ids in
            all.filter { $0.linkedKind == "Quotation" && ids.contains($0.linkedId ?? "") }.sorted(by: byDate)
        }
        if kind == "BOQ" {
            // Its own, then those added to its linked quotations.
            return own + ofQuotations(linkedQuotations(id))
        }
        guard kind == "Quotation", let q = getQuotation(id: id), let boqId = q.sourceBOQId else { return own }
        let inherited = all.filter { $0.linkedKind == "BOQ" && $0.linkedId == boqId }.sorted(by: byDate)
        // Linked: the other linked quotations' drawings too.
        let siblings = q.boqLinked == true ? ofQuotations(linkedQuotations(boqId).filter { $0 != id }) : []
        return inherited + own + siblings
    }

    /// The drawing files added after a BOQ's or quotation's own pages.
    func appendedDrawingFiles(kind: String, id: String) -> [URL] {
        documentDrawings(kind: kind, id: id).map { URL(fileURLWithPath: $0.filePath) }
            .filter { PDFAttachments.canAppend($0) && FileManager.default.fileExists(atPath: $0.path) }
    }

    func drawingSummaries(_ drawings: [ProjectDrawing]) -> [ProjectDrawingSummary] {
        let boqNumbers = Dictionary(boqsStore.readAll().map { ($0.id, $0.boqNumber) }, uniquingKeysWith: { a, _ in a })
        let quotationNumbers = Dictionary(quotationsStore.readAll().map { ($0.id, $0.quotationNumber) }, uniquingKeysWith: { a, _ in a })
        return drawings
            .sorted { $0.uploadedAt > $1.uploadedAt }
            .map { d in
                let number = d.linkedId.flatMap { d.linkedKind == "BOQ" ? boqNumbers[$0] : d.linkedKind == "Quotation" ? quotationNumbers[$0] : nil }
                return ProjectDrawingSummary(
                    id: d.id, originalName: d.originalName, storedFilename: d.storedFilename,
                    fileType: d.fileType, fileSizeBytes: d.fileSizeBytes, description: d.description,
                    uploadedAt: d.uploadedAt, fileExists: FileManager.default.fileExists(atPath: d.filePath),
                    linkedKind: number == nil ? nil : d.linkedKind, linkedId: number == nil ? nil : d.linkedId, linkedNumber: number
                )
            }
    }

    /// Links a drawing to one of its project's BOQs or quotations, or
    /// unlinks it (kind nil).
    func setDrawingLink(id: String, kind: String?, linkedId: String?) -> String? {
        var items = drawingsStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Drawing not found." }
        if let error = checkDrawingLink(projectId: items[i].projectId, kind: kind, linkedId: linkedId) { return error }
        let linked = (kind == "BOQ" || kind == "Quotation") && nonBlank(linkedId) != nil
        items[i].linkedKind = linked ? kind : nil
        items[i].linkedId = linked ? linkedId : nil
        drawingsStore.writeAll(items)
        return nil
    }

    /// nil when the link is empty or points at this project's own BOQ or
    /// quotation.
    func checkDrawingLink(projectId: String, kind: String?, linkedId: String?) -> String? {
        guard let kind = nonBlank(kind), let linkedId = nonBlank(linkedId) else { return nil }
        switch kind {
        case "BOQ": return getBOQ(id: linkedId)?.projectId == projectId ? nil : "That BOQ isn't part of this project."
        case "Quotation": return getQuotation(id: linkedId)?.projectId == projectId ? nil : "That quotation isn't part of this project."
        default: return "A drawing can be linked to a BOQ or a quotation."
        }
    }

    @discardableResult
    func recordDrawing(projectId: String, originalName: String, storedURL: URL, linkedKind: String? = nil, linkedId: String? = nil) -> ProjectDrawing {
        let attrs = try? FileManager.default.attributesOfItem(atPath: storedURL.path)
        let size = (attrs?[.size] as? Int) ?? 0
        let linked = checkDrawingLink(projectId: projectId, kind: linkedKind, linkedId: linkedId) == nil && nonBlank(linkedKind) != nil && nonBlank(linkedId) != nil
        let drawing = ProjectDrawing(
            id: makeId("drawing"), projectId: projectId, originalName: originalName,
            storedFilename: storedURL.lastPathComponent, filePath: storedURL.path,
            fileType: storedURL.pathExtension.uppercased(), fileSizeBytes: size,
            description: nil, isArchived: false, uploadedAt: nowISO(),
            linkedKind: linked ? linkedKind : nil, linkedId: linked ? linkedId : nil
        )
        drawingsStore.insert(drawing)
        logActivity(projectId: projectId, "Drawing uploaded", reference: originalName)
        return drawing
    }

    func getDrawing(id: String) -> ProjectDrawing? {
        drawingsStore.readAll().first { $0.id == id }
    }

    func drawingsForProject(_ projectId: String) -> [ProjectDrawing] {
        drawingsStore.readAll().filter { $0.projectId == projectId }
    }

    func documentsForProject(_ projectId: String) -> [ProjectDocument] {
        documentsStore.readAll().filter { $0.projectId == projectId }
    }

    func updateDrawingDescription(id: String, description: String?) -> String? {
        var items = drawingsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Drawing not found." }
        items[index].description = description
        drawingsStore.writeAll(items)
        return nil
    }

    /// Renames the file on disk (not just a label), so Finder and the
    /// app never disagree about what a drawing is called.
    func renameDrawing(id: String, newDisplayName: String) -> String? {
        var items = drawingsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Drawing not found." }
        let oldURL = URL(fileURLWithPath: items[index].filePath)
        guard FileManager.default.fileExists(atPath: oldURL.path) else {
            return "The original file could not be found, so it can't be renamed. Try Locate File first."
        }
        let ext = oldURL.pathExtension
        let sanitized = safeFileBaseName(newDisplayName, extension: ext)
        guard !sanitized.isEmpty else { return "Enter a name." }
        let newFilename = ext.isEmpty ? sanitized : "\(sanitized).\(ext)"
        guard newFilename != oldURL.lastPathComponent else { return nil }
        guard !FileManager.default.fileExists(atPath: oldURL.deletingLastPathComponent().appendingPathComponent(newFilename).path) else {
            return "A file called \"\(newFilename)\" already exists in that folder."
        }
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newFilename)
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            return "Could not rename the file: \(error.localizedDescription)"
        }
        items[index].storedFilename = newFilename
        items[index].filePath = newURL.path
        drawingsStore.writeAll(items)
        return nil
    }

    /// Soft delete (section 33: "Archive/delete where appropriate") —
    /// the file on disk is untouched.
    func archiveDrawing(id: String) -> String? {
        var items = drawingsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Drawing not found." }
        items[index].isArchived = true
        drawingsStore.writeAll(items)
        return nil
    }

    /// Section 38's "Remove Reference" — only removes ScaffoldPro's own
    /// record. Never touches the filesystem.
    func removeDrawingReference(id: String) -> String? {
        var items = drawingsStore.readAll()
        guard items.contains(where: { $0.id == id }) else { return "Drawing not found." }
        items.removeAll { $0.id == id }
        drawingsStore.writeAll(items)
        return nil
    }

    /// Section 38's "Locate File" / "Re-link" — points the record at
    /// wherever the person says the file actually is now, without
    /// moving or copying anything.
    func relinkDrawing(id: String, newPath: String) -> String? {
        var items = drawingsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Drawing not found." }
        guard FileManager.default.fileExists(atPath: newPath) else { return "That file could not be found." }
        let url = URL(fileURLWithPath: newPath)
        let attrs = try? FileManager.default.attributesOfItem(atPath: newPath)
        items[index].filePath = newPath
        items[index].storedFilename = url.lastPathComponent
        items[index].fileSizeBytes = (attrs?[.size] as? Int) ?? items[index].fileSizeBytes
        drawingsStore.writeAll(items)
        return nil
    }

    /// Section 14 "Replace": points the record at a newly copied file.
    /// The caller has already moved the previous copy to Superseded/.
    func replaceDrawingFile(id: String, originalName: String, storedURL: URL) -> String? {
        var items = drawingsStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Drawing not found." }
        let attrs = try? FileManager.default.attributesOfItem(atPath: storedURL.path)
        let previous = items[i].originalName
        items[i].originalName = originalName
        items[i].storedFilename = storedURL.lastPathComponent
        items[i].filePath = storedURL.path
        items[i].fileType = storedURL.pathExtension.uppercased()
        items[i].fileSizeBytes = (attrs?[.size] as? Int) ?? 0
        items[i].uploadedAt = nowISO()
        drawingsStore.writeAll(items)
        logActivity(projectId: items[i].projectId, "Drawing replaced with a new version", reference: "\(previous) → \(originalName)")
        return nil
    }

    func replaceDocumentFile(id: String, originalName: String, storedURL: URL) -> String? {
        var items = documentsStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        let attrs = try? FileManager.default.attributesOfItem(atPath: storedURL.path)
        let previous = items[i].originalName
        items[i].originalName = originalName
        items[i].storedFilename = storedURL.lastPathComponent
        items[i].filePath = storedURL.path
        items[i].fileType = storedURL.pathExtension.uppercased()
        items[i].fileSizeBytes = (attrs?[.size] as? Int) ?? 0
        items[i].uploadedAt = nowISO()
        documentsStore.writeAll(items)
        logActivity(projectId: items[i].projectId, "Document replaced with a new version", reference: "\(previous) → \(originalName)")
        return nil
    }

    // ---- General project documents (Phase 11 — section 34) ----

    func listDocuments(projectId: String) -> [ProjectDocumentSummary] {
        documentsStore.readAll()
            .filter { $0.projectId == projectId && !$0.isArchived }
            .sorted { $0.uploadedAt > $1.uploadedAt }
            .map { d in
                var summary = ProjectDocumentSummary(
                    id: d.id, originalName: d.originalName, storedFilename: d.storedFilename,
                    category: d.category, fileType: d.fileType, fileSizeBytes: d.fileSizeBytes,
                    description: d.description, uploadedAt: d.uploadedAt,
                    fileExists: FileManager.default.fileExists(atPath: d.filePath)
                )
                // Only while that BOQ / quotation is still there.
                if let kind = d.linkedKind, let lid = d.linkedId,
                   kind == "BOQ" ? getBOQ(id: lid) != nil : getQuotation(id: lid) != nil {
                    summary.linkedKind = kind
                    summary.linkedId = lid
                }
                return summary
            }
    }

    /// Files a document with one of its project's BOQs or quotations, or
    /// with the project in general (kind nil).
    func setDocumentLink(id: String, kind: String?, linkedId: String?) -> String? {
        var items = documentsStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        if let error = checkDrawingLink(projectId: items[i].projectId, kind: kind, linkedId: linkedId) {
            return error.replacingOccurrences(of: "A drawing", with: "A document")
        }
        let linked = (kind == "BOQ" || kind == "Quotation") && nonBlank(linkedId) != nil
        items[i].linkedKind = linked ? kind : nil
        items[i].linkedId = linked ? linkedId : nil
        documentsStore.writeAll(items)
        return nil
    }

    @discardableResult
    func recordDocument(projectId: String, originalName: String, category: String, storedURL: URL) -> ProjectDocument {
        let attrs = try? FileManager.default.attributesOfItem(atPath: storedURL.path)
        let size = (attrs?[.size] as? Int) ?? 0
        let document = ProjectDocument(
            id: makeId("document"), projectId: projectId, originalName: originalName,
            storedFilename: storedURL.lastPathComponent, filePath: storedURL.path,
            category: category, fileType: storedURL.pathExtension.uppercased(), fileSizeBytes: size,
            description: nil, isArchived: false, uploadedAt: nowISO()
        )
        documentsStore.insert(document)
        logActivity(projectId: projectId, "Document uploaded (\(category))", reference: originalName)
        return document
    }

    func getDocument(id: String) -> ProjectDocument? {
        documentsStore.readAll().first { $0.id == id }
    }

    func updateDocumentDescription(id: String, description: String?) -> String? {
        var items = documentsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        items[index].description = description
        documentsStore.writeAll(items)
        return nil
    }

    func renameDocument(id: String, newDisplayName: String) -> String? {
        var items = documentsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        let oldURL = URL(fileURLWithPath: items[index].filePath)
        guard FileManager.default.fileExists(atPath: oldURL.path) else {
            return "The original file could not be found, so it can't be renamed. Try Locate File first."
        }
        let ext = oldURL.pathExtension
        let sanitized = safeFileBaseName(newDisplayName, extension: ext)
        guard !sanitized.isEmpty else { return "Enter a name." }
        let newFilename = ext.isEmpty ? sanitized : "\(sanitized).\(ext)"
        guard newFilename != oldURL.lastPathComponent else { return nil }
        guard !FileManager.default.fileExists(atPath: oldURL.deletingLastPathComponent().appendingPathComponent(newFilename).path) else {
            return "A file called \"\(newFilename)\" already exists in that folder."
        }
        let newURL = oldURL.deletingLastPathComponent().appendingPathComponent(newFilename)
        do {
            try FileManager.default.moveItem(at: oldURL, to: newURL)
        } catch {
            return "Could not rename the file: \(error.localizedDescription)"
        }
        items[index].storedFilename = newFilename
        items[index].filePath = newURL.path
        documentsStore.writeAll(items)
        return nil
    }

    func archiveDocument(id: String) -> String? {
        var items = documentsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        items[index].isArchived = true
        documentsStore.writeAll(items)
        return nil
    }

    func removeDocumentReference(id: String) -> String? {
        var items = documentsStore.readAll()
        guard items.contains(where: { $0.id == id }) else { return "Document not found." }
        items.removeAll { $0.id == id }
        documentsStore.writeAll(items)
        return nil
    }

    func relinkDocument(id: String, newPath: String) -> String? {
        var items = documentsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        guard FileManager.default.fileExists(atPath: newPath) else { return "That file could not be found." }
        let url = URL(fileURLWithPath: newPath)
        let attrs = try? FileManager.default.attributesOfItem(atPath: newPath)
        items[index].filePath = newPath
        items[index].storedFilename = url.lastPathComponent
        items[index].fileSizeBytes = (attrs?[.size] as? Int) ?? items[index].fileSizeBytes
        documentsStore.writeAll(items)
        return nil
    }

    // ---- Workers (Phase 12 — section 41) ----

    func listWorkers(includeArchived: Bool) -> [Worker] {
        workersStore.readAll()
            .filter { includeArchived || !$0.isArchived }
            .sorted { $0.workerNumber < $1.workerNumber }
    }

    func getWorker(id: String) -> Worker? {
        workersStore.readAll().first { $0.id == id }
    }

    /// "W001", "W002", ... — never reused, even after archiving.
    func nextWorkerNumber() -> String {
        let sequences = workersStore.readAll().compactMap { Int($0.workerNumber.dropFirst()) }
        return "W" + String(format: "%03d", (sequences.max() ?? 0) + 1)
    }

    func createWorker(_ payload: [String: Any]) -> Result<Worker, WorkerError> {
        let name = ((payload["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return .failure(WorkerError(message: "Name is required.")) }
        let worker = Worker(
            id: makeId("worker"), workerNumber: nextWorkerNumber(), name: name,
            position: nonEmpty(payload["position"]), phone: nonEmpty(payload["phone"]),
            email: nonEmpty(payload["email"]), startDate: nonEmpty(payload["startDate"]),
            endDate: nonEmpty(payload["endDate"]), notes: nonEmpty(payload["notes"]),
            isArchived: false, createdAt: nowISO(),
            chineseName: nonEmpty(payload["chineseName"]), honorific: nonEmpty(payload["honorific"]),
            idNumber: nonEmpty(payload["idNumber"])?.uppercased(), dailyWage: wageOf(payload["dailyWage"])
        )
        workersStore.insert(worker)
        return .success(worker)
    }

    func updateWorker(id: String, payload: [String: Any]) -> String? {
        var workers = workersStore.readAll()
        guard let index = workers.firstIndex(where: { $0.id == id }) else { return "Worker not found." }
        let name = ((payload["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return "Name is required." }
        workers[index].name = name
        workers[index].position = nonEmpty(payload["position"])
        workers[index].phone = nonEmpty(payload["phone"])
        workers[index].email = nonEmpty(payload["email"])
        workers[index].startDate = nonEmpty(payload["startDate"])
        workers[index].endDate = nonEmpty(payload["endDate"])
        workers[index].notes = nonEmpty(payload["notes"])
        if payload.keys.contains("chineseName") { workers[index].chineseName = nonEmpty(payload["chineseName"]) }
        if payload.keys.contains("honorific") { workers[index].honorific = nonEmpty(payload["honorific"]) }
        if payload.keys.contains("idNumber") { workers[index].idNumber = nonEmpty(payload["idNumber"])?.uppercased() }
        if payload.keys.contains("dailyWage") { workers[index].dailyWage = wageOf(payload["dailyWage"]) }
        workersStore.writeAll(workers)
        return nil
    }

    func setWorkerArchived(id: String, archived: Bool) -> String? {
        var workers = workersStore.readAll()
        guard let index = workers.firstIndex(where: { $0.id == id }) else { return "Worker not found." }
        workers[index].isArchived = archived
        workersStore.writeAll(workers)
        return nil
    }

    func nonEmpty(_ value: Any?) -> String? {
        guard let s = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    func wageOf(_ value: Any?) -> Double? {
        let v = (value as? Double) ?? (value as? Int).map(Double.init) ?? (value as? String).flatMap { Double($0.replacingOccurrences(of: ",", with: "")) }
        return v.flatMap { $0 > 0 ? ($0 * 100).rounded() / 100 : nil }
    }

    // ---- Worker documents (Phase 12 — section 42) ----

    func listWorkerDocuments(workerId: String) -> [WorkerDocumentSummary] {
        workerDocumentsStore.readAll()
            .filter { $0.workerId == workerId && !$0.isArchived }
            .sorted { $0.uploadedAt > $1.uploadedAt }
            .map { d in
                WorkerDocumentSummary(
                    id: d.id, originalName: d.originalName, storedFilename: d.storedFilename,
                    category: d.category, fileType: d.fileType, fileSizeBytes: d.fileSizeBytes,
                    description: d.description, expiryDate: d.expiryDate, uploadedAt: d.uploadedAt,
                    fileExists: FileManager.default.fileExists(atPath: d.filePath)
                )
            }
    }

    @discardableResult
    func recordWorkerDocument(workerId: String, originalName: String, category: String, expiryDate: String?, storedURL: URL) -> WorkerDocument {
        let attrs = try? FileManager.default.attributesOfItem(atPath: storedURL.path)
        let doc = WorkerDocument(
            id: makeId("wdoc"), workerId: workerId, originalName: originalName,
            storedFilename: storedURL.lastPathComponent, filePath: storedURL.path,
            category: category, fileType: storedURL.pathExtension.uppercased(),
            fileSizeBytes: (attrs?[.size] as? Int) ?? 0, description: nil,
            expiryDate: expiryDate, isArchived: false, uploadedAt: nowISO()
        )
        workerDocumentsStore.insert(doc)
        return doc
    }

    func getWorkerDocument(id: String) -> WorkerDocument? {
        workerDocumentsStore.readAll().first { $0.id == id }
    }

    func updateWorkerDocument(id: String, description: String?, expiryDate: String?) -> String? {
        var docs = workerDocumentsStore.readAll()
        guard let index = docs.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        docs[index].description = description
        docs[index].expiryDate = expiryDate
        workerDocumentsStore.writeAll(docs)
        return nil
    }

    func archiveWorkerDocument(id: String) -> String? {
        var docs = workerDocumentsStore.readAll()
        guard let index = docs.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        docs[index].isArchived = true
        workerDocumentsStore.writeAll(docs)
        return nil
    }

    func removeWorkerDocumentReference(id: String) -> String? {
        var docs = workerDocumentsStore.readAll()
        guard docs.contains(where: { $0.id == id }) else { return "Document not found." }
        docs.removeAll { $0.id == id }
        workerDocumentsStore.writeAll(docs)
        return nil
    }

    func relinkWorkerDocument(id: String, newPath: String) -> String? {
        var docs = workerDocumentsStore.readAll()
        guard let index = docs.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        guard FileManager.default.fileExists(atPath: newPath) else { return "That file could not be found." }
        let attrs = try? FileManager.default.attributesOfItem(atPath: newPath)
        docs[index].filePath = newPath
        docs[index].storedFilename = URL(fileURLWithPath: newPath).lastPathComponent
        docs[index].fileSizeBytes = (attrs?[.size] as? Int) ?? docs[index].fileSizeBytes
        workerDocumentsStore.writeAll(docs)
        return nil
    }

    // ---- Administrative documents (Phase 12 — section 43) ----

    func listAdminDocuments() -> [AdminDocumentSummary] {
        adminDocumentsStore.readAll()
            .filter { !$0.isArchived }
            .sorted { $0.uploadedAt > $1.uploadedAt }
            .map { d in
                AdminDocumentSummary(
                    id: d.id, originalName: d.originalName, storedFilename: d.storedFilename,
                    category: d.category, fileType: d.fileType, fileSizeBytes: d.fileSizeBytes,
                    description: d.description, expiryDate: d.expiryDate, uploadedAt: d.uploadedAt,
                    fileExists: FileManager.default.fileExists(atPath: d.filePath)
                )
            }
    }

    @discardableResult
    func recordAdminDocument(originalName: String, category: String, expiryDate: String?, storedURL: URL) -> AdminDocument {
        let attrs = try? FileManager.default.attributesOfItem(atPath: storedURL.path)
        let doc = AdminDocument(
            id: makeId("adoc"), originalName: originalName,
            storedFilename: storedURL.lastPathComponent, filePath: storedURL.path,
            category: category, fileType: storedURL.pathExtension.uppercased(),
            fileSizeBytes: (attrs?[.size] as? Int) ?? 0, description: nil,
            expiryDate: expiryDate, isArchived: false, uploadedAt: nowISO()
        )
        adminDocumentsStore.insert(doc)
        return doc
    }

    func getAdminDocument(id: String) -> AdminDocument? {
        adminDocumentsStore.readAll().first { $0.id == id }
    }

    func updateAdminDocument(id: String, description: String?, expiryDate: String?) -> String? {
        var docs = adminDocumentsStore.readAll()
        guard let index = docs.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        docs[index].description = description
        docs[index].expiryDate = expiryDate
        adminDocumentsStore.writeAll(docs)
        return nil
    }

    func archiveAdminDocument(id: String) -> String? {
        var docs = adminDocumentsStore.readAll()
        guard let index = docs.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        docs[index].isArchived = true
        adminDocumentsStore.writeAll(docs)
        return nil
    }

    func removeAdminDocumentReference(id: String) -> String? {
        var docs = adminDocumentsStore.readAll()
        guard docs.contains(where: { $0.id == id }) else { return "Document not found." }
        docs.removeAll { $0.id == id }
        adminDocumentsStore.writeAll(docs)
        return nil
    }

    func relinkAdminDocument(id: String, newPath: String) -> String? {
        var docs = adminDocumentsStore.readAll()
        guard let index = docs.firstIndex(where: { $0.id == id }) else { return "Document not found." }
        guard FileManager.default.fileExists(atPath: newPath) else { return "That file could not be found." }
        let attrs = try? FileManager.default.attributesOfItem(atPath: newPath)
        docs[index].filePath = newPath
        docs[index].storedFilename = URL(fileURLWithPath: newPath).lastPathComponent
        docs[index].fileSizeBytes = (attrs?[.size] as? Int) ?? docs[index].fileSizeBytes
        adminDocumentsStore.writeAll(docs)
        return nil
    }

    /// After a restore: any stored file path that starts with the backup's
    /// original ~/Documents/ScaffoldPro location is re-pointed at this
    /// Mac's location. A no-op when restoring on the same Mac/account.
    func rebaseFilePaths(from oldRoot: String, to newRoot: String) {
        guard oldRoot != newRoot, !oldRoot.isEmpty else { return }
        rebaseFilePaths(moves: [(oldRoot, newRoot)])
    }

    /// Every stored file path under a moved folder or file (old path → new),
    /// applied in order, re-pointed at where it is now: drawings, documents,
    /// exported PDFs, signed copies, letters, signing requests, the logo.
    func rebaseFilePaths(moves: [(String, String)]) {
        let moves = moves.filter { !$0.0.isEmpty && $0.0 != $0.1 }
        guard !moves.isEmpty else { return }
        func moved(_ path: String) -> String {
            var p = path
            for (old, new) in moves {
                if p == old { p = new } else if p.hasPrefix(old + "/") { p = new + String(p.dropFirst(old.count)) }
            }
            return p
        }
        func movedOptional(_ path: String?) -> String? { path.map(moved) }
        func rebase<T: Codable & HasFilePath>(_ store: JSONStore<T>) {
            var items = store.readAll()
            var changed = false
            for i in items.indices {
                let p = moved(items[i].filePath)
                if p != items[i].filePath { items[i].filePath = p; changed = true }
            }
            if changed { store.writeAll(items) }
        }
        rebase(drawingsStore)
        rebase(documentsStore)
        rebase(workerDocumentsStore)
        rebase(adminDocumentsStore)
        func update<T>(_ store: JSONStore<T>, _ change: (inout T) -> Bool) {
            var items = store.readAll()
            var changed = false
            for i in items.indices where change(&items[i]) { changed = true }
            if changed { store.writeAll(items) }
        }
        update(boqsStore) { b in let p = movedOptional(b.pdfPath); defer { b.pdfPath = p }; return p != b.pdfPath }
        update(quotationsStore) { q in
            let pdf = movedOptional(q.pdfPath), signed = movedOptional(q.signedCopyPath), director = movedOptional(q.directorSignedPath)
            let changed = pdf != q.pdfPath || signed != q.signedCopyPath || director != q.directorSignedPath
            q.pdfPath = pdf; q.signedCopyPath = signed; q.directorSignedPath = director
            return changed
        }
        update(invoicesStore) { v in let p = movedOptional(v.pdfPath); defer { v.pdfPath = p }; return p != v.pdfPath }
        update(deliveryNotesStore) { d in
            let pdf = movedOptional(d.pdfPath), signed = movedOptional(d.signedCopyPath)
            let changed = pdf != d.pdfPath || signed != d.signedCopyPath
            d.pdfPath = pdf; d.signedCopyPath = signed
            return changed
        }
        update(lettersStore) { l in let p = movedOptional(l.pdfPath); defer { l.pdfPath = p }; return p != l.pdfPath }
        update(signRequestsStore) { r in let p = movedOptional(r.filePath); defer { r.filePath = p }; return p != r.filePath }
        var settings = getCompanySettings()
        if let logo = settings.logoPath, moved(logo) != logo {
            settings.logoPath = moved(logo)
            settingsStore.writeAll([settings])
        }
    }

    /// Section 42/43: "where documents have expiry dates, provide useful
    /// reminders." Anything expired or expiring within 30 days, across
    /// worker documents and admin documents, soonest first.
    func expiringDocuments(withinDays days: Int) -> [ExpiringDocument] {
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        let today = Calendar.current.startOfDay(for: Date())
        guard let cutoff = Calendar.current.date(byAdding: .day, value: days, to: today) else { return [] }

        func daysLeft(_ expiry: String?) -> Int? {
            guard let expiry = expiry, let date = dayFormatter.date(from: String(expiry.prefix(10))) else { return nil }
            guard date <= cutoff else { return nil }
            return Calendar.current.dateComponents([.day], from: today, to: date).day
        }

        let workers = workersStore.readAll()
        var result: [ExpiringDocument] = []
        for d in workerDocumentsStore.readAll() where !d.isArchived {
            guard let left = daysLeft(d.expiryDate), let worker = workers.first(where: { $0.id == d.workerId }), !worker.isArchived else { continue }
            result.append(ExpiringDocument(id: d.id, kind: "Worker", ownerName: "\(worker.workerNumber) \(worker.name)", originalName: d.originalName, category: d.category, expiryDate: d.expiryDate ?? "", daysLeft: left))
        }
        for d in adminDocumentsStore.readAll() where !d.isArchived {
            guard let left = daysLeft(d.expiryDate) else { continue }
            result.append(ExpiringDocument(id: d.id, kind: "Company", ownerName: "Company", originalName: d.originalName, category: d.category, expiryDate: d.expiryDate ?? "", daysLeft: left))
        }
        return result.sorted { $0.daysLeft < $1.daysLeft }
    }
}

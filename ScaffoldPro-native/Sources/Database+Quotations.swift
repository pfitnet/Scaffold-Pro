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
    // ---- Quotations (Phase 8) ----

    func quotationLineItems(for quotationId: String) -> [QuotationLineItem] {
        sortedLines(quotationLineItemsStore.readAll().filter { $0.quotationId == quotationId }, mode: getQuotation(id: quotationId)?.lineSort,
                    itemId: { $0.priceListItemId }, code: { $0.itemCode }, description: { $0.itemDescription }, order: { $0.sortOrder })
    }

    /// How a quotation's items are listed. Linked to a BOQ (a Draft), the
    /// BOQ's is set too — the two keep one order.
    func setQuotationLineSort(id: String, mode: String) -> String? {
        guard ["list", "code", "description", "manual"].contains(mode) else { return "Choose how to sort." }
        guard let q = getQuotation(id: id) else { return "Quotation not found." }
        guard q.status == "Draft" else { return "This quotation is issued and can no longer be edited." }
        if q.boqLinked == true, let boqId = q.sourceBOQId, getBOQ(id: boqId)?.status == "Draft" {
            if mode == "manual" { _ = reorderQuotationLines(quotationId: id, ids: quotationLineItems(for: id).map { $0.id }) }
            return setBOQLineSort(id: boqId, mode: mode)
        }
        let shown = quotationLineItems(for: id)
        var qs = quotationsStore.readAll()
        guard let i = qs.firstIndex(where: { $0.id == id }) else { return "Quotation not found." }
        qs[i].lineSort = mode == "list" ? nil : mode
        qs[i].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
        if mode == "manual" { freezeQuotationOrder(id: id, ids: shown.map { $0.id }) }
        return nil
    }

    func freezeQuotationOrder(id: String, ids: [String]) {
        var all = quotationLineItemsStore.readAll()
        let position = Dictionary(ids.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
        for i in all.indices where all[i].quotationId == id {
            if let p = position[all[i].id] { all[i].sortOrder = p }
        }
        quotationLineItemsStore.writeAll(all)
    }

    /// Lines dragged into a new order: listed as arranged from now on. A
    /// linked quotation's BOQ takes the same order (and its other quotations).
    func reorderQuotationLines(quotationId: String, ids: [String]) -> String? {
        guard let q = getQuotation(id: quotationId) else { return "Quotation not found." }
        guard q.status == "Draft" else { return "This quotation is issued and can no longer be edited." }
        let shown = quotationLineItems(for: quotationId).filter { $0.blockId == nil }.map { $0.id }
        let order = reordered(shown, by: ids)
        freezeQuotationOrder(id: quotationId, ids: order)
        var qs = quotationsStore.readAll()
        if let i = qs.firstIndex(where: { $0.id == quotationId }) {
            qs[i].lineSort = "manual"
            qs[i].updatedAt = nowISO()
            quotationsStore.writeAll(qs)
        }
        if q.boqLinked == true, let boqId = q.sourceBOQId, getBOQ(id: boqId)?.status == "Draft" {
            let lines = quotationLineItemsStore.readAll().filter { $0.quotationId == quotationId }
            let boqOrder = order.compactMap { id in lines.first { $0.id == id }?.boqLineId }
            let rest = lineItems(for: boqId).map { $0.id }.filter { !boqOrder.contains($0) }
            setBOQManual(boqId)
            freezeBOQOrder(id: boqId, ids: boqOrder + rest)
            touchBOQ(boqId)
            syncLinkedQuotations(boqId: boqId, except: quotationId)
        }
        return nil
    }

    /// Document lines in item-code order ("1.2" before "1.10"); lines
    /// without a code (custom items, delivery charges) keep the order they
    /// were added in, after the coded ones.
    func byItemCode<T>(_ lines: [T], code: (T) -> String, order: (T) -> Int) -> [T] {
        lines.sorted { a, b in
            let ca = code(a).trimmingCharacters(in: .whitespaces), cb = code(b).trimmingCharacters(in: .whitespaces)
            if ca.isEmpty != cb.isEmpty { return !ca.isEmpty }
            if !ca.isEmpty {
                let comparison = ca.localizedStandardCompare(cb)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            return order(a) < order(b)
        }
    }

    /// Rental quotations charge a minimum hire period only when it's
    /// switched on for that quotation. Quotations saved before the option
    /// existed (nil) keep the minimum hire they always had.
    func hireMonths(_ q: Quotation) -> Int {
        guard q.pricingMode == "Rental", q.minimumHireEnabled ?? true else { return 1 }
        return max(1, q.minimumHireMonths ?? getCompanySettings().defaultMinimumHireMonths ?? 2)
    }

    /// The standard quotation's arithmetic: materials subtotal (per month
    /// for rental) × minimum hire months, plus delivery charges; then any
    /// discount and tax as usual. Delivery lines are those in the
    /// "Delivery" section.
    struct QuotationMoney {
        var materialsSubtotal: Double
        /// The monthly rental charged: the materials subtotal, or the
        /// minimum monthly charge when that's ticked and higher.
        var monthlyRental: Double
        var minimumApplied: Bool
        var charges: ChargeSplit
        var materialsCharge: Double
        var deliveryTotal: Double
        var otherTotal: Double
        var subtotal: Double
        var discountAmount: Double
        var taxAmount: Double
        var total: Double
    }

    /// The unit price a quotation line is charged at: its price with the
    /// quotation's markup (materials only, rounded to 0.1).
    func effectiveUnitPrice(_ line: QuotationLineItem, _ q: Quotation) -> Double {
        isMaterialLine(line) ? markedUpPrice(line.appliedUnitPrice, markupPercent: q.markupPercent, roundUp: markupRoundsUp) : line.appliedUnitPrice
    }

    /// A material (or custom item) — not a delivery charge, and not a row
    /// of an extra section.
    func isMaterialLine(_ line: QuotationLineItem) -> Bool {
        line.section != "Delivery" && line.blockId == nil
    }

    func isDeliveryLine(_ line: QuotationLineItem) -> Bool {
        line.section == "Delivery" && line.blockId == nil
    }

    func quotationLineTotal(_ line: QuotationLineItem, _ q: Quotation) -> Decimal {
        netLineAmount(quantity: line.quantity, unitPrice: effectiveUnitPrice(line, q), discountType: line.discountType, discountValue: line.discountValue)
    }

    func quotationMoney(_ q: Quotation, lineItems: [QuotationLineItem]) -> QuotationMoney {
        let months = hireMonths(q)
        let isRental = q.pricingMode == "Rental"
        func net(_ line: QuotationLineItem) -> Decimal { quotationLineTotal(line, q) }
        let materials = lineItems.filter { isMaterialLine($0) }.reduce(Decimal(0)) { $0 + net($1) }
        // A minimum monthly rental charge (when ticked) lifts a small order to it.
        let minimum = decimalOf(minimumMonthlyRental)
        let minimumApplied = isRental && q.minimumMonthlyChargeEnabled == true && materials > 0 && materials < minimum
        let rental = minimumApplied ? minimum : materials
        let delivery = lineItems.filter { isDeliveryLine($0) }.reduce(Decimal(0)) { $0 + net($1) }
        // Priced sections count once; rates-only rows aren't charged.
        let pricedBlocks = quotationBlocks(for: q.id).filter { $0.kind == "Priced" }
        var once = Decimal(0)
        var perPeriod: [String: Decimal] = [:]
        for block in pricedBlocks {
            let amount = lineItems.filter { $0.blockId == block.id }.reduce(Decimal(0)) { $0 + net($1) }
            if let period = block.chargePeriod, ["Day", "Week", "Month"].contains(period) {
                perPeriod[period, default: 0] += amount
            } else {
                once += amount
            }
        }
        let other = once + perPeriod.values.reduce(Decimal(0), +)
        let charge = rental * Decimal(months)
        let t = moneyTotals(subtotal: charge + delivery + other, discountType: q.discountType, discountValue: q.discountValue,
                            taxRatePercent: q.taxRatePercent, pricesIncludeTax: getCompanySettings().pricesIncludeTax ?? false)
        // The split, with any discount taken off each part in proportion.
        let subtotal = decimalOf(t.subtotal)
        let factor: Decimal = subtotal > 0 && t.discountAmount > 0 ? (subtotal - decimalOf(t.discountAmount)) / subtotal : 1
        func part(_ d: Decimal) -> Double { doubleOf(roundToCents(d * factor)) }
        let split: ChargeSplit
        if isRental {
            split = ChargeSplit(monthly: part(rental + (perPeriod["Month"] ?? 0)), oneTime: part(delivery + once),
                                recurring: perPeriod.filter { $0.key != "Month" && $0.value != 0 }.mapValues { part($0) })
        } else {
            // Sale: nothing monthly; it's all one-time.
            split = ChargeSplit(monthly: 0, oneTime: part(materials + delivery + other), recurring: [:])
        }
        return QuotationMoney(materialsSubtotal: doubleOf(materials), monthlyRental: doubleOf(rental), minimumApplied: minimumApplied,
                              charges: split, materialsCharge: doubleOf(charge), deliveryTotal: doubleOf(delivery),
                              otherTotal: doubleOf(other),
                              subtotal: t.subtotal, discountAmount: t.discountAmount, taxAmount: t.taxAmount, total: t.total)
    }

    /// Settings' minimum monthly rental charge (HK$1,000 unless changed).
    var minimumMonthlyRental: Double { getCompanySettings().minimumMonthlyRental ?? 1000 }

    func listQuotationSummaries(projectId: String) -> [QuotationSummary] {
        let names = authorsByRecord("quotations.json")
        let all = quotationsStore.readAll()
        return all
            .filter { $0.projectId == projectId }
            .sorted { $0.quotationNumber > $1.quotationNumber }
            .map { q in
                let items = quotationLineItems(for: q.id)
                let totals = quotationMoney(q, lineItems: items)
                var summary = QuotationSummary(id: q.id, quotationNumber: q.quotationNumber, status: q.status, itemCount: items.count, total: totals.total, createdAt: q.createdAt)
                summary.signed = q.signedCopyPath.map { fileIsPresent($0) } ?? false
                let boq = q.sourceBOQId.flatMap { getBOQ(id: $0) }
                summary.boqNumber = boq?.boqNumber
                summary.boqId = boq?.id
                summary.boqLinked = boq != nil && q.boqLinked == true
                summary.fromCombined = boq.map { combinedSources($0) != nil } ?? false
                summary.structure = nonBlank(boq?.structure)
                summary.subject = nonBlank(q.subject)
                summary.pricingMode = q.pricingMode
                summary.charges = totals.charges
                summary.createdBy = names[q.id]?.createdBy
                summary.lastEditedBy = names[q.id]?.lastEditedBy
                if let parent = parentQuotation(of: q, in: all) {
                    summary.parentId = parent.id
                    summary.parentNumber = parent.quotationNumber
                }
                return summary
            }
    }

    /// Quotation numbers are scoped per project, same convention as BOQ
    /// numbers: "<projectNumber>-QT-001". Independent of every other
    /// project's numbering.
    func nextQuotationNumber(projectNumber: String, projectId: String) -> String {
        nextDocumentNumber(template: numberFormat("QT"), projectNumber: projectNumber, existing: quotationsStore.readAll().map { $0.quotationNumber }, startAt: getCompanySettings().numberStarts?["QT"] ?? 1)
    }

    /// Creates a quotation, optionally from an existing BOQ (section 21:
    /// "create quotations from a project, a BOQ, or manually entered
    /// items"). One made from a BOQ is linked to it: changes to either are
    /// made to the other, until the link is removed.
    /// The quotation's "Re:" subject line until someone types their own:
    /// "<project> - <Rental|Sale>", then the structure of the BOQ it
    /// follows, e.g. "GL-28 Works - Rental - Access platform for louvres".
    func autoQuotationSubject(projectName: String, pricingMode: String, structure: String?) -> String {
        ([projectName, pricingMode] + [nonBlank(structure)].compactMap { $0 }).joined(separator: " - ")
    }

    /// Whether a subject line is still the one made for it (with or without
    /// the structure), so it can be kept in step; typed-in ones are left.
    func isAutoQuotationSubject(_ subject: String?, projectName: String, pricingMode: String, structures: [String?]) -> Bool {
        guard let subject = nonBlank(subject) else { return true }
        return (([nil] as [String?]) + structures).contains { autoQuotationSubject(projectName: projectName, pricingMode: pricingMode, structure: $0) == subject }
    }

    /// Draft quotations following BOQ `boqId` whose subject line is still
    /// automatic get the BOQ's structure (e.g. after it's changed).
    func refreshQuotationSubjects(boqId: String, previousStructure: String? = nil) {
        guard let boq = getBOQ(id: boqId),
              let project = projectsStore.readAll().first(where: { $0.id == boq.projectId }) else { return }
        var qs = quotationsStore.readAll()
        var changed = false
        for i in qs.indices where qs[i].sourceBOQId == boqId && qs[i].status == "Draft" {
            guard isAutoQuotationSubject(qs[i].subject, projectName: project.name, pricingMode: qs[i].pricingMode,
                                         structures: [previousStructure, boq.structure]) else { continue }
            let subject = autoQuotationSubject(projectName: project.name, pricingMode: qs[i].pricingMode, structure: boq.structure)
            guard qs[i].subject != subject else { continue }
            qs[i].subject = subject
            qs[i].updatedAt = nowISO()
            changed = true
        }
        if changed { quotationsStore.writeAll(qs) }
    }

    /// Once per launch: draft quotations made before their subject line
    /// carried the BOQ's structure.
    func addStructuresToQuotationSubjects() {
        let boqIds = Set(quotationsStore.readAll().filter { $0.status == "Draft" }.compactMap { $0.sourceBOQId })
        for id in boqIds { refreshQuotationSubjects(boqId: id) }
    }

    /// A quotation's buy-back offer (+ Add Section › Buy-back Offer): its
    /// own figures, else Settings' (60% after 6 months, 2% less a month
    /// beyond, none after 24 months, unless changed there). On while it
    /// has a Buy-back Offer section.
    func buyBackTerms(for q: Quotation, unitPrice: Double?) -> BuyBackTerms {
        let s = getCompanySettings()
        let after = q.buyBackAfterMonths ?? s.buyBackAfterMonths ?? 6
        let offered = quotationBlocks(for: q.id).contains { $0.kind == "BuyBack" }
        return BuyBackTerms(enabled: offered,
                            percent: q.buyBackPercent ?? s.buyBackPercent ?? 60,
                            afterMonths: after,
                            reductionPercent: q.buyBackReductionPercent ?? s.buyBackReductionPercent ?? 2,
                            endMonths: max(after, q.buyBackEndMonths ?? s.buyBackEndMonths ?? 24),
                            unitPrice: unitPrice,
                            wording: nonBlank(s.buyBackWording) ?? BuyBackTerms.defaultWording)
    }

    /// A copy of a quotation as a new draft — in its own project or another
    /// — with its items, sections and delivery schedule. Not linked to a BOQ,
    /// not signed or agreed; numbered as the next in the project.
    func duplicateQuotation(id: String, toProjectId: String?) -> Result<Quotation, WorkerError> {
        guard let source = getQuotation(id: id) else { return .failure(WorkerError(message: "Quotation not found.")) }
        let projectId = nonBlank(toProjectId) ?? source.projectId
        guard let project = getProject(id: projectId) else { return .failure(WorkerError(message: "Project not found.")) }
        var copy = source
        copy.id = makeId("quotation")
        copy.projectId = project.id
        copy.quotationNumber = nextQuotationNumber(projectNumber: project.projectNumber, projectId: project.id)
        copy.status = "Draft"
        copy.quotationDate = nowISO()
        copy.createdAt = nowISO()
        copy.updatedAt = nowISO()
        copy.validUntil = nil
        copy.sourceBOQId = nil
        copy.boqLinked = nil
        copy.parentQuotationId = nil
        copy.pdfPath = nil
        copy.signedCopyPath = nil
        copy.signedCopyAt = nil
        copy.signedCopyNotNeeded = nil
        copy.directorSignedPath = nil
        copy.directorSignedAt = nil
        copy.directorSignedBy = nil
        copy.clientAgreedAt = nil
        copy.importedFromDocumentId = nil
        if project.id != source.projectId {
            let site = sitesStore.readAll().first { $0.id == project.siteId }
            copy.siteRef = site?.siteReference ?? site?.name ?? copy.siteRef
        }
        quotationsStore.insert(copy)
        var blockIds: [String: String] = [:]
        for b in quotationBlocks(for: source.id) {
            var nb = b
            nb.id = makeId("qblock")
            nb.quotationId = copy.id
            blockIds[b.id] = nb.id
            quotationBlocksStore.insert(nb)
        }
        var lineIds: [String: String] = [:]
        var lines: [QuotationLineItem] = []
        for l in quotationLineItems(for: source.id) {
            var nl = l
            nl.id = makeId("qitem")
            nl.quotationId = copy.id
            nl.blockId = l.blockId.flatMap { blockIds[$0] }
            nl.boqLineId = nil
            nl.boqDetached = nil
            lineIds[l.id] = nl.id
            lines.append(nl)
        }
        quotationLineItemsStore.writeAll(quotationLineItemsStore.readAll() + lines)
        // The delivery schedule, as planned (each day's quantities moved to
        // the copies' lines).
        let days = quotationDeliveriesStore.readAll().filter { $0.quotationId == source.id }.map { d -> QuotationDeliveryDay in
            var nd = d
            nd.id = makeId("qday")
            nd.quotationId = copy.id
            nd.sent = nil
            nd.quantities = Dictionary(d.quantities.compactMap { k, v in lineIds[k].map { ($0, v) } }, uniquingKeysWith: { a, _ in a })
            nd.createdAt = nowISO()
            nd.updatedAt = nowISO()
            return nd
        }
        if !days.isEmpty { quotationDeliveriesStore.writeAll(quotationDeliveriesStore.readAll() + days) }
        logActivity(projectId: project.id, "Quotation duplicated from \(source.quotationNumber)", reference: copy.quotationNumber)
        return .success(copy)
    }

    /// A new draft quotation from an imported file's items (read from the
    /// file, or by the AI, and checked by the person). Materials whose code
    /// is in the material list are linked to it but keep the price on the
    /// file; delivery charges go under Delivery; anything else into a
    /// priced section named as on the file.
    func createImportedQuotation(projectId: String, projectNumber: String, pricingMode: String, subject: String?, clientRef: String?,
                                 currency: String?, lines: [ImportedQuotationLine]) -> Quotation {
        var q = createQuotation(projectId: projectId, projectNumber: projectNumber, sourceBOQId: nil, pricingMode: pricingMode == "Sale" ? "Sale" : "Rental")
        var all = quotationsStore.readAll()
        if let i = all.firstIndex(where: { $0.id == q.id }) {
            if let s = nonBlank(subject) { all[i].subject = s }
            if let r = nonBlank(clientRef) { all[i].clientRef = r }
            if let c = nonBlank(currency)?.uppercased(), c != getCompanySettings().currency.uppercased() { all[i].currency = c }
            // The prices are the file's: no extra markup on top.
            all[i].markupPercent = nil
            quotationsStore.writeAll(all)
            q = all[i]
        }
        appendImportedLines(to: q, lines: lines)
        return getQuotation(id: q.id) ?? q
    }

    /// Imported (or the assistant's) lines added after a quotation's own:
    /// materials found by their code in the material list, delivery charges,
    /// and other charges in priced sections by their heading.
    func appendImportedLines(to q: Quotation, lines: [ImportedQuotationLine]) {
        let priceItems = priceListItemsStore.readAll().filter { !$0.isArchived }
        let byCode = Dictionary(priceItems.map { ($0.itemCode.uppercased(), $0) }, uniquingKeysWith: { a, _ in a })
        var blocks: [String: String] = [:]
        for b in quotationBlocks(for: q.id) where b.kind == "Priced" { if let t = nonBlank(b.title), blocks[t] == nil { blocks[t] = b.id } }
        var order = (quotationLineItemsStore.readAll().filter { $0.quotationId == q.id && $0.blockId == nil }.map { $0.sortOrder }.max() ?? -1) + 1
        var newLines: [QuotationLineItem] = []
        for l in lines {
            let description = l.description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !description.isEmpty else { continue }
            let kind = l.kind ?? "Material"
            let price = doubleOf(roundToCents(decimalOf(max(0, l.unitPrice))))
            var line = QuotationLineItem(id: makeId("qitem"), quotationId: q.id, sourceKey: nil, priceListItemId: nil,
                                         itemCode: l.itemCode ?? "", itemDescription: description, unit: nonBlank(l.unit) ?? "pc",
                                         quantity: max(1, l.quantity.rounded()), appliedUnitPrice: price, section: nil, sortOrder: order)
            order += 1
            if kind == "Delivery" {
                line.section = "Delivery"
            } else if kind == "Other" {
                let title = nonBlank(l.section) ?? "Other Charges"
                if blocks[title] == nil, case .success(let block) = addQuotationBlock(quotationId: q.id, kind: "Priced") {
                    var bs = quotationBlocksStore.readAll()
                    if let bi = bs.firstIndex(where: { $0.id == block.id }) { bs[bi].title = title; quotationBlocksStore.writeAll(bs) }
                    blocks[title] = block.id
                }
                line.blockId = blocks[title]
            } else if let code = nonBlank(l.itemCode)?.uppercased(), let pl = byCode[code] {
                line.priceListItemId = pl.id
                line.sourceKey = pl.sourceKey
                line.itemCode = pl.itemCode
                line.section = pl.category
                line.priceListUnitPrice = basePrice(pl, mode: q.pricingMode, rates: conversionRates())
            }
            newLines.append(line)
        }
        quotationLineItemsStore.writeAll(quotationLineItemsStore.readAll() + newLines)
        touchQuotation(q.id)
    }

    func setQuotationImportedFile(quotationId: String, documentId: String) {
        var all = quotationsStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == quotationId }) else { return }
        all[i].importedFromDocumentId = documentId
        quotationsStore.writeAll(all)
    }

    func createQuotation(projectId: String, projectNumber: String, sourceBOQId: String?, pricingMode: String) -> Quotation {
        // A quotation built from a BOQ inherits that BOQ's pricing mode
        // (the line items it copies already reflect that mode's prices),
        // rather than letting the two disagree.
        let resolvedPricingMode = sourceBOQId.flatMap { getBOQ(id: $0)?.pricingMode } ?? pricingMode
        let settings = getCompanySettings()
        // Made from a BOQ: the BOQ's number (BQ26001-004 → Qt26001-004).
        var quotationNumber = nextQuotationNumber(projectNumber: projectNumber, projectId: projectId)
        if let boqId = sourceBOQId, let boq = getBOQ(id: boqId) {
            let used: [String] = quotationsStore.readAll().map { $0.quotationNumber }
            if let linked = linkedNumber(type: "QT", sourceType: "BOQ", sourceNumber: boq.boqNumber, projectNumber: projectNumber, existing: used) {
                quotationNumber = linked
            }
        }
        var quotation = Quotation(
            id: makeId("quotation"), projectId: projectId, sourceBOQId: sourceBOQId,
            quotationNumber: quotationNumber,
            status: "Draft", quotationDate: nowISO(), pricingMode: resolvedPricingMode, validUntil: nil,
            paymentTerms: settings.defaultPaymentTerms,
            // No sales tax in Hong Kong: new quotations carry none.
            discountType: "None", discountValue: 0, taxRatePercent: 0,
            notes: settings.defaultNotes,
            createdAt: nowISO(), updatedAt: nowISO()
        )
        if let project = projectsStore.readAll().first(where: { $0.id == projectId }) {
            let site = sitesStore.readAll().first { $0.id == project.siteId }
            quotation.siteRef = site?.siteReference ?? site?.name
            quotation.subject = autoQuotationSubject(projectName: project.name, pricingMode: resolvedPricingMode,
                                                     structure: sourceBOQId.flatMap { getBOQ(id: $0)?.structure })
        }
        quotation.deliveryMethod = "BY EMAIL ONLY"
        // Starts with the client's default markup — unless it follows a BOQ,
        // whose own mark-up carries on to it instead.
        if sourceBOQId == nil { quotation.markupPercent = clientDefaultMarkup(projectId: projectId) }
        // Minimum hire is an option per quotation, off until switched on;
        // the months default from Settings.
        quotation.minimumHireMonths = settings.defaultMinimumHireMonths ?? 2
        quotation.minimumHireEnabled = false
        quotationsStore.insert(quotation)
        logActivity(projectId: projectId, sourceBOQId == nil ? "Quotation created (\(resolvedPricingMode))" : "Quotation created from BOQ", reference: quotation.quotationNumber)

        if let boqId = sourceBOQId, let boq = getBOQ(id: boqId) {
            // Linked to the BOQ: its items (with its mark-up as the markup %),
            // kept in step both ways until the link is removed.
            var qs = quotationsStore.readAll()
            if let qi = qs.firstIndex(where: { $0.id == quotation.id }) {
                qs[qi].boqLinked = true
                quotationsStore.writeAll(qs)
            }
            mirrorBOQ(boq, into: quotation.id)
            // And the BOQ's delivery schedule, if it has one.
            if quotationDeliveriesStore.readAll().contains(where: { $0.quotationId == boqId }) {
                _ = copyDeliverySchedule(fromBOQ: boqId, toQuotation: quotation.id)
            }
            quotation = getQuotation(id: quotation.id) ?? quotation
        }
        return quotation
    }

    /// The markup % a BOQ passes on to a quotation: its mark-up, if the
    /// BOQ keeps list prices (a mark-down is priced into the lines instead).
    func carriedMarkup(_ boq: BillOfQuantities) -> Double? {
        guard boq.markupOnRates == true, let m = boq.markupPercent, m > 0 else { return nil }
        return m
    }

    /// A BOQ line as a quotation line. With the BOQ's mark-up carried to the
    /// quotation, it keeps its list price, and its discount on the unit rate
    /// becomes the same discount on the quotation line (a per-unit amount ×
    /// quantity), so it's charged the same. Otherwise the rate as charged.
    func quotationPricing(of item: BOQLineItem, boq: BillOfQuantities) -> (price: Double, listPrice: Double?, discountType: String?, discountValue: Double?) {
        guard carriedMarkup(boq) != nil else {
            // No mark-up, a mark-down, or an older BOQ: the rate as charged.
            let rate = boqEffectiveRate(item, boq: boq)
            let list = boq.markupOnRates == true ? item.priceListUnitPrice.map { markedUpPrice($0, markupPercent: boq.markupPercent, roundUp: markupRoundsUp) } : item.priceListUnitPrice
            return (rate, list, nil, nil)
        }
        let value = max(0, item.discountValue ?? 0)
        switch item.discountType {
        case "Percent" where value > 0: return (item.appliedUnitPrice, item.priceListUnitPrice, "Percent", min(value, 100))
        case "Amount" where value > 0:
            return (item.appliedUnitPrice, item.priceListUnitPrice, "Amount", doubleOf(roundToCents(decimalOf(value) * decimalOf(item.quantity.rounded()))))
        default: return (item.appliedUnitPrice, item.priceListUnitPrice, nil, nil)
        }
    }

    // ---- A BOQ and a quotation linked together ----
    //
    // A quotation made from a BOQ (or linked to one) is kept in step with it
    // both ways until the link is removed: its materials are the BOQ's items
    // (each quotation line knows the BOQ line it is), with the same names,
    // quantities, prices and discounts, and the BOQ's Sale / Rental and
    // mark-up are the quotation's. Only Draft documents are changed — an
    // issued one stays as it was issued. The quotation's delivery charges,
    // extra sections and overall discount are its own.

    /// A BOQ's prices can pass to a linked quotation as they are (list
    /// prices, the mark-up as the markup %, the discounts) — unless the BOQ
    /// has a mark-down, which is priced into the quotation's rates.
    func linkedPricesPassStraight(_ boq: BillOfQuantities) -> Bool {
        boq.markupOnRates == true && (boq.markupPercent ?? 0) >= 0
    }

    /// A BOQ line as its linked quotation line prices it.
    func linkedPricing(of item: BOQLineItem, boq: BillOfQuantities) -> (price: Double, listPrice: Double?, discountType: String?, discountValue: Double?) {
        guard linkedPricesPassStraight(boq) else { return quotationPricing(of: item, boq: boq) }
        let value = max(0, item.discountValue ?? 0)
        switch item.discountType {
        case "Percent" where value > 0: return (item.appliedUnitPrice, item.priceListUnitPrice, "Percent", min(value, 100))
        case "Amount" where value > 0:
            return (item.appliedUnitPrice, item.priceListUnitPrice, "Amount", doubleOf(roundToCents(decimalOf(value) * decimalOf(item.quantity.rounded()))))
        default: return (item.appliedUnitPrice, item.priceListUnitPrice, nil, nil)
        }
    }

    /// A quotation line's price and discount put back on its BOQ line (the
    /// reverse of `linkedPricing`): a discount off the line total becomes
    /// that much off each unit; with a mark-down, the rate charged becomes
    /// the price before it.
    func applyQuotationPrice(_ ql: QuotationLineItem, to b: inout BOQLineItem, boq: BillOfQuantities) {
        if linkedPricesPassStraight(boq) {
            b.appliedUnitPrice = ql.appliedUnitPrice
        } else {
            let factor = 1 + decimalOf(boq.markupPercent ?? 0) / 100
            b.appliedUnitPrice = factor > 0 ? doubleOf(roundToCents(decimalOf(ql.appliedUnitPrice) / factor)) : ql.appliedUnitPrice
        }
        if let list = ql.priceListUnitPrice, linkedPricesPassStraight(boq) { b.priceListUnitPrice = list }
        let value = max(0, ql.discountValue ?? 0)
        switch ql.discountType {
        case "Percent" where value > 0:
            b.discountType = "Percent"
            b.discountValue = min(value, 100)
        case "Amount" where value > 0 && ql.quantity.rounded() > 0:
            b.discountType = "Amount"
            b.discountValue = doubleOf(roundToCents(decimalOf(value) / decimalOf(ql.quantity.rounded())))
        default:
            b.discountType = nil
            b.discountValue = nil
        }
    }

    func samePricing(_ ql: QuotationLineItem, _ e: (price: Double, listPrice: Double?, discountType: String?, discountValue: Double?)) -> Bool {
        abs(ql.appliedUnitPrice - e.price) < 0.005 && (ql.discountType ?? "None") == (e.discountType ?? "None")
            && abs((ql.discountValue ?? 0) - (e.discountValue ?? 0)) < 0.005
    }

    /// The linked Draft quotations of a BOQ made the same as it (all but
    /// `except`, the one a change came from).
    func syncLinkedQuotations(boqId: String, except: String? = nil) {
        guard let boq = getBOQ(id: boqId) else { return }
        for q in quotationsStore.readAll() where q.sourceBOQId == boqId && q.boqLinked == true && q.status == "Draft" && q.id != except {
            mirrorBOQ(boq, into: q.id)
        }
    }

    /// Makes a quotation's materials the BOQ's: each BOQ line's quotation
    /// line updated (or added), in the BOQ's order; lines whose BOQ line
    /// was deleted go too. Its Sale / Rental and markup % follow the BOQ.
    func mirrorBOQ(_ boq: BillOfQuantities, into quotationId: String) {
        var qs = quotationsStore.readAll()
        guard let qi = qs.firstIndex(where: { $0.id == quotationId }) else { return }
        let fullBOQ = lineItems(for: boq.id)
        let boqLineIds = Set(fullBOQ.map { $0.id })
        var all = quotationLineItemsStore.readAll()
        let before = all.filter { $0.quotationId == quotationId }
        var paired: [String: QuotationLineItem] = [:]
        for l in before where l.blockId == nil { if let b = l.boqLineId, paired[b] == nil { paired[b] = l } }
        // A subsidiary sharing its main quotation's BOQ holds only its own
        // items of it; the main one holds all but its subsidiaries'.
        var boqLines = fullBOQ
        if parentQuotation(of: qs[qi], in: qs) != nil {
            boqLines = fullBOQ.filter { paired[$0.id] != nil }
        } else {
            let subs = Set(qs.filter { $0.id != quotationId && $0.sourceBOQId == boq.id && parentQuotation(of: $0, in: qs)?.id == quotationId }.map { $0.id })
            if !subs.isEmpty {
                let held = Set(all.filter { subs.contains($0.quotationId) && $0.blockId == nil }.compactMap { $0.boqLineId })
                boqLines = fullBOQ.filter { !held.contains($0.id) }
            }
        }
        var materials: [QuotationLineItem] = []
        for (index, item) in boqLines.enumerated() {
            // Unlinked on its own: it stays as it is.
            if var own = paired[item.id], own.boqDetached == true {
                own.sortOrder = index
                materials.append(own)
                continue
            }
            let priced = linkedPricing(of: item, boq: boq)
            var line = paired[item.id] ?? QuotationLineItem(id: makeId("qitem"), quotationId: quotationId, sourceKey: nil, priceListItemId: nil,
                                                            itemCode: "", itemDescription: "", unit: "", quantity: 0, appliedUnitPrice: 0,
                                                            section: nil, sortOrder: 0)
            line.sourceKey = item.sourceKey
            line.priceListItemId = item.priceListItemId
            line.itemCode = item.itemCode
            line.itemDescription = item.itemDescription
            line.unit = item.unit
            line.quantity = item.quantity.rounded()
            line.quantityFormula = item.quantityFormula
            line.appliedUnitPrice = priced.price
            line.priceListUnitPrice = priced.listPrice
            line.discountType = priced.discountType
            line.discountValue = priced.discountValue
            line.section = item.section
            line.sortOrder = index
            line.boqLineId = item.id
            materials.append(line)
        }
        // Everything else (delivery charges, the extra sections' rows, and
        // any item only on the quotation) stays, after the BOQ's items.
        let pairedIds = Set(materials.map { $0.id })
        let others = before
            .filter { !pairedIds.contains($0.id) && !($0.blockId == nil && $0.boqDetached != true && $0.boqLineId.map { !boqLineIds.contains($0) } ?? false) }
            .sorted { $0.sortOrder < $1.sortOrder }
            .enumerated().map { i, l -> QuotationLineItem in
                var c = l
                c.sortOrder = boqLines.count + i
                return c
            }
        let after = materials + others
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let key: ([QuotationLineItem]) -> Data? = { try? encoder.encode($0.sorted { $0.id < $1.id }) }
        var changed = false
        if key(before) != key(after) {
            all.removeAll { $0.quotationId == quotationId }
            all.append(contentsOf: after)
            quotationLineItemsStore.writeAll(all)
            changed = true
        }
        let markup = linkedPricesPassStraight(boq) ? carriedMarkup(boq) : nil
        // Listed in the BOQ's order (its sort, or as arranged on it).
        if qs[qi].lineSort != boq.lineSort {
            qs[qi].lineSort = boq.lineSort
            changed = true
        }
        if qs[qi].pricingMode != boq.pricingMode {
            if let project = projectsStore.readAll().first(where: { $0.id == qs[qi].projectId }),
               isAutoQuotationSubject(qs[qi].subject, projectName: project.name, pricingMode: qs[qi].pricingMode, structures: [boq.structure]) {
                qs[qi].subject = autoQuotationSubject(projectName: project.name, pricingMode: boq.pricingMode, structure: boq.structure)
            }
            qs[qi].pricingMode = boq.pricingMode
            changed = true
        }
        if qs[qi].markupPercent != markup {
            qs[qi].markupPercent = markup
            changed = true
        }
        if changed {
            qs[qi].updatedAt = nowISO()
            quotationsStore.writeAll(qs)
        }
    }

    /// A linked quotation's materials changed: the same changes to its BOQ
    /// (while that's a Draft), then to the BOQ's other linked quotations.
    /// Lines only on the quotation are added to the BOQ.
    func pushQuotationToBOQ(_ quotationId: String) {
        guard let q = getQuotation(id: quotationId), q.boqLinked == true, q.status == "Draft",
              let boqId = q.sourceBOQId, let boq = getBOQ(id: boqId), boq.status == "Draft" else { return }
        var qAll = quotationLineItemsStore.readAll()
        let qIndexes = qAll.indices.filter { qAll[$0].quotationId == quotationId && qAll[$0].blockId == nil && qAll[$0].boqDetached != true
            && (qAll[$0].boqLineId != nil || isMaterialLine(qAll[$0])) }
            .sorted { qAll[$0].sortOrder < qAll[$1].sortOrder }
        var bAll = boqLineItemsStore.readAll()
        let bBefore = bAll.filter { $0.boqId == boqId }
        var nextOrder = (bBefore.map { $0.sortOrder }.max() ?? -1) + 1
        var weights: [String: Double]? = nil
        var added = false
        for qx in qIndexes {
            let ql = qAll[qx]
            if let bid = ql.boqLineId, let bi = bAll.firstIndex(where: { $0.id == bid && $0.boqId == boqId }) {
                var b = bAll[bi]
                b.sourceKey = ql.sourceKey
                b.priceListItemId = ql.priceListItemId
                b.itemCode = ql.itemCode
                b.itemDescription = ql.itemDescription
                b.unit = ql.unit
                b.quantity = ql.quantity.rounded()
                b.quantityFormula = ql.quantityFormula
                b.section = ql.section
                if !samePricing(ql, linkedPricing(of: b, boq: boq)) { applyQuotationPrice(ql, to: &b, boq: boq) }
                bAll[bi] = b
            } else {
                if weights == nil {
                    weights = Dictionary(priceListItemsStore.readAll().compactMap { i in i.weightKg.map { (i.id, $0) } }, uniquingKeysWith: { a, _ in a })
                }
                var b = BOQLineItem(id: makeId("boqitem"), boqId: boqId, sourceKey: ql.sourceKey, priceListItemId: ql.priceListItemId,
                                    itemCode: ql.itemCode, itemDescription: ql.itemDescription, unit: ql.unit, quantity: ql.quantity.rounded(),
                                    priceListUnitPrice: ql.priceListUnitPrice, appliedUnitPrice: ql.appliedUnitPrice,
                                    weightKg: ql.priceListItemId.flatMap { weights?[$0] }, section: ql.section, sortOrder: nextOrder, notes: nil)
                nextOrder += 1
                b.quantityFormula = ql.quantityFormula
                // An item picked from the material list comes in at its list
                // price (the BOQ's mark-up / mark-down then applies to it).
                let atListPrice = ql.priceListUnitPrice.map { abs($0 - ql.appliedUnitPrice) < 0.005 } ?? false
                if !atListPrice { applyQuotationPrice(ql, to: &b, boq: boq) }
                bAll.append(b)
                qAll[qx].boqLineId = b.id
                added = true
            }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let bAfter = bAll.filter { $0.boqId == boqId }
        if (try? encoder.encode(bBefore)) != (try? encoder.encode(bAfter)) {
            boqLineItemsStore.writeAll(bAll)
            touchBOQ(boqId)
        }
        if added { quotationLineItemsStore.writeAll(qAll) }
        // New items are priced as the BOQ prices them (its mark-down…).
        if added, let fresh = getBOQ(id: boqId) { mirrorBOQ(fresh, into: quotationId) }
        syncLinkedQuotations(boqId: boqId, except: quotationId)
    }

    /// Links a Draft quotation to a BOQ of its project: its materials are
    /// made the BOQ's (lines matched to the BOQ's items by the item they
    /// are; the others removed), then kept in step both ways.
    func linkQuotationToBOQ(quotationId: String, boqId: String) -> String? {
        var qs = quotationsStore.readAll()
        guard let qi = qs.firstIndex(where: { $0.id == quotationId }) else { return "Quotation not found." }
        guard qs[qi].status == "Draft" else { return "This quotation is issued and can no longer be edited." }
        guard let boq = getBOQ(id: boqId) else { return "BOQ not found." }
        guard boq.projectId == qs[qi].projectId else { return "That BOQ belongs to a different project." }
        if qs[qi].boqLinked == true, let linked = qs[qi].sourceBOQId, linked != boqId, getBOQ(id: linked) != nil {
            return "This quotation is already linked to \(getBOQ(id: linked)?.boqNumber ?? "a BOQ"). Remove that link first."
        }
        let boqLines = lineItems(for: boqId)
        var all = quotationLineItemsStore.readAll()
        var used = Set<String>()
        var drop = Set<String>()
        let boqIds = Set(boqLines.map { $0.id })
        let candidates = all.indices.filter { all[$0].quotationId == quotationId && all[$0].blockId == nil && (all[$0].boqLineId != nil || isMaterialLine(all[$0])) }
        // Lines already from this BOQ first; then the rest matched by item.
        var unmatched: [Int] = []
        for i in candidates {
            if let b = all[i].boqLineId, boqIds.contains(b), !used.contains(b) { used.insert(b) } else { unmatched.append(i) }
        }
        for i in unmatched {
            let l = all[i]
            let match = boqLines.first { b in
                !used.contains(b.id) && (l.priceListItemId != nil ? b.priceListItemId == l.priceListItemId
                    : b.priceListItemId == nil && b.itemCode == l.itemCode && b.itemDescription == l.itemDescription && b.unit == l.unit)
            }
            if let m = match {
                all[i].boqLineId = m.id
                used.insert(m.id)
            } else {
                drop.insert(all[i].id)
            }
        }
        all.removeAll { drop.contains($0.id) }
        quotationLineItemsStore.writeAll(all)
        let previousStructure = qs[qi].sourceBOQId.flatMap { getBOQ(id: $0)?.structure }
        qs[qi].sourceBOQId = boqId
        qs[qi].boqLinked = true
        qs[qi].updatedAt = nowISO()
        let renumbered = takeLinkedNumber(&qs, qi, from: boq)
        quotationsStore.writeAll(qs)
        if let old = renumbered { logActivity(projectId: qs[qi].projectId, "Quotation renumbered to match \(boq.boqNumber)", reference: "was \(old)") }
        mirrorBOQ(boq, into: quotationId)
        refreshQuotationSubjects(boqId: boqId, previousStructure: previousStructure)
        logActivity(projectId: qs[qi].projectId, "Quotation linked to \(boq.boqNumber)", reference: qs[qi].quotationNumber)
        return nil
    }

    /// A draft quotation linked to a BOQ takes the BOQ's number
    /// (BQ26212-007 → Qt26212-007), as one made from the BOQ does; with
    /// "-2" etc. when another quotation already has it. Returns the old
    /// number when it changed. (Not with Settings' linked numbers off, nor
    /// for an issued quotation, whose number has gone out.)
    @discardableResult
    func takeLinkedNumber(_ qs: inout [Quotation], _ qi: Int, from boq: BillOfQuantities) -> String? {
        guard qs[qi].status == "Draft",
              let projectNumber = projectsStore.readAll().first(where: { $0.id == qs[qi].projectId })?.projectNumber else { return nil }
        let used = qs.filter { $0.id != qs[qi].id }.map { $0.quotationNumber }
        guard let number = linkedNumber(type: "QT", sourceType: "BOQ", sourceNumber: boq.boqNumber, projectNumber: projectNumber, existing: used),
              number != qs[qi].quotationNumber else { return nil }
        let old = qs[qi].quotationNumber
        qs[qi].quotationNumber = number
        return old
    }

    /// The link removed: both stay as they are, and change on their own.
    func unlinkQuotationFromBOQ(quotationId: String) -> String? {
        var qs = quotationsStore.readAll()
        guard let qi = qs.firstIndex(where: { $0.id == quotationId }) else { return "Quotation not found." }
        guard qs[qi].boqLinked == true else { return nil }
        qs[qi].boqLinked = nil
        qs[qi].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
        let boqNumber = qs[qi].sourceBOQId.flatMap { getBOQ(id: $0)?.boqNumber } ?? "its BOQ"
        logActivity(projectId: qs[qi].projectId, "Quotation's link to \(boqNumber) removed", reference: qs[qi].quotationNumber)
        return nil
    }

    /// The BOQ's delivery schedule copied onto a quotation (replacing the
    /// quotation's own): each BOQ item's quantities go on the quotation
    /// line for it. Returns how many items had no line on the quotation.
    func copyDeliverySchedule(fromBOQ boqId: String, toQuotation quotationId: String) -> (skipped: Int, error: String?) {
        guard getQuotation(id: quotationId) != nil else { return (0, "Quotation not found.") }
        guard getBOQ(id: boqId) != nil else { return (0, "BOQ not found.") }
        var all = quotationDeliveriesStore.readAll()
        let boqDays = all.filter { $0.quotationId == boqId }.sorted { $0.day < $1.day }
        guard !boqDays.isEmpty else { return (0, "The BOQ has no delivery schedule yet.") }
        let boqLines = lineItems(for: boqId)
        let qLines = quotationLineItems(for: quotationId).filter { $0.blockId == nil && ($0.boqLineId != nil || isMaterialLine($0)) }
        var map: [String: String] = [:]
        var taken = Set<String>()
        for b in boqLines {
            let match = qLines.first { $0.boqLineId == b.id && !taken.contains($0.id) }
                ?? qLines.first { l in !taken.contains(l.id) && l.boqLineId == nil && (b.priceListItemId != nil ? l.priceListItemId == b.priceListItemId
                    : l.priceListItemId == nil && l.itemCode == b.itemCode && l.itemDescription == b.itemDescription) }
            if let m = match { map[b.id] = m.id; taken.insert(m.id) }
        }
        let scheduled = Set(boqDays.flatMap { $0.quantities.filter { $0.value > 0 }.map { $0.key } })
        let skipped = scheduled.filter { map[$0] == nil }.count
        all.removeAll { $0.quotationId == quotationId }
        for d in boqDays {
            var quantities: [String: Double] = [:]
            for (lineId, qty) in d.quantities { if let to = map[lineId] { quantities[to, default: 0] += qty } }
            all.append(QuotationDeliveryDay(id: makeId("qdday"), quotationId: quotationId, day: d.day, date: d.date, sent: d.sent, note: d.note,
                                            internalNote: d.internalNote, quantities: quantities, createdAt: nowISO(), updatedAt: nowISO()))
        }
        quotationDeliveriesStore.writeAll(all)
        return (skipped, nil)
    }

    func getQuotation(id: String) -> Quotation? {
        quotationsStore.readAll().first { $0.id == id }
    }

    /// "Reference a BOQ for quicker work": copies every line of a BOQ
    /// from the same project into an existing Draft quotation. Prices
    /// are looked up fresh from the price list for the *quotation's*
    /// Sale/Rental mode (so a Rental BOQ can feed a Sale quotation);
    /// if the price-list item no longer exists, the BOQ's own price is
    /// used. `replaceExisting` clears the quotation's current lines
    /// first; otherwise the BOQ's lines are appended.
    func importBOQIntoQuotation(quotationId: String, boqId: String, replaceExisting: Bool) -> String? {
        var qs = quotationsStore.readAll()
        guard let qIndex = qs.firstIndex(where: { $0.id == quotationId }) else { return "Quotation not found." }
        guard qs[qIndex].status == "Draft" else { return "This quotation is issued and can no longer be edited." }
        guard let boq = getBOQ(id: boqId) else { return "BOQ not found." }
        guard boq.projectId == qs[qIndex].projectId else { return "That BOQ belongs to a different project." }
        // A quotation linked to its BOQ follows that BOQ only.
        if qs[qIndex].boqLinked == true, let linked = qs[qIndex].sourceBOQId, getBOQ(id: linked) != nil {
            return "This quotation is linked to \(getBOQ(id: linked)?.boqNumber ?? "its BOQ"). Remove the link before importing items from a BOQ."
        }

        let boqItems = lineItems(for: boqId)
        guard !boqItems.isEmpty else { return "That BOQ has no items to import." }

        var allQuotationItems = quotationLineItemsStore.readAll()
        if replaceExisting {
            // The extra sections (design fees, rates, notes) stay.
            allQuotationItems.removeAll { $0.quotationId == quotationId && $0.blockId == nil }
        }
        let startOrder = (allQuotationItems.filter { $0.quotationId == quotationId }.map { $0.sortOrder }.max() ?? -1) + 1

        let priceItems = priceListItemsStore.readAll()
        let pricingMode = qs[qIndex].pricingMode
        let rates = conversionRates()
        let carried = carriedMarkup(boq)
        let imported: [QuotationLineItem] = boqItems.enumerated().map { index, item in
            // Same mode: keep the BOQ's own price (any hand-typed price and
            // discount). Different mode: re-price at the list price in HKD.
            let priced = quotationPricing(of: item, boq: boq)
            var price = priced.price
            var listPrice = priced.listPrice
            if boq.pricingMode != pricingMode, let plId = item.priceListItemId, let pl = priceItems.first(where: { $0.id == plId }),
               let p = boqPrice(for: pl, mode: pricingMode, markupPercent: carried == nil && boq.markupOnRates != true ? (boq.markupPercent ?? 0) : 0, rates: rates) {
                price = carried == nil && boq.markupOnRates == true ? markedUpPrice(p, markupPercent: boq.markupPercent, roundUp: markupRoundsUp) : p
                listPrice = price
            }
            var line = QuotationLineItem(
                id: makeId("qitem"), quotationId: quotationId, sourceKey: item.sourceKey,
                priceListItemId: item.priceListItemId, itemCode: item.itemCode,
                itemDescription: item.itemDescription, unit: item.unit, quantity: item.quantity.rounded(),
                appliedUnitPrice: price, section: item.section, sortOrder: startOrder + index,
                priceListUnitPrice: listPrice
            )
            line.discountType = priced.discountType
            line.discountValue = priced.discountValue
            line.boqLineId = item.id
            return line
        }
        // The BOQ's mark-up becomes the quotation's markup % (replacing the
        // lines, or when the quotation has no markup of its own yet).
        if let markup = carried, replaceExisting || (qs[qIndex].markupPercent ?? 0) <= 0 {
            qs[qIndex].markupPercent = markup
        }
        allQuotationItems.append(contentsOf: imported)
        quotationLineItemsStore.writeAll(allQuotationItems)

        let previousStructure = qs[qIndex].sourceBOQId.flatMap { getBOQ(id: $0)?.structure }
        qs[qIndex].sourceBOQId = boqId
        // Replacing the items links the two (kept in step from now on);
        // adding them below the quotation's own doesn't.
        qs[qIndex].boqLinked = replaceExisting ? true : nil
        qs[qIndex].updatedAt = nowISO()
        let renumbered = replaceExisting ? takeLinkedNumber(&qs, qIndex, from: boq) : nil
        quotationsStore.writeAll(qs)
        if let old = renumbered { logActivity(projectId: qs[qIndex].projectId, "Quotation renumbered to match \(boq.boqNumber)", reference: "was \(old)") }
        logActivity(projectId: qs[qIndex].projectId, "Items imported from \(boq.boqNumber)", reference: qs[qIndex].quotationNumber)
        if replaceExisting { mirrorBOQ(boq, into: quotationId) }
        // Now following this BOQ: its structure goes in the subject line.
        refreshQuotationSubjects(boqId: boqId, previousStructure: previousStructure)
        return nil
    }

    /// The weight of a quotation's materials (quantity × the material
    /// list's unit weight — by the item it was picked from, else the same
    /// code, else the same name), and how many have no weight.
    func quotationWeight(_ lines: [QuotationLineItem]) -> (kg: Double?, missing: Int) {
        let weights = quotationLineWeights(lines)
        var kg = Decimal(0)
        var found = 0
        var missing = 0
        for line in lines where isMaterialLine(line) {
            if let w = weights[line.id] {
                kg += decimalOf(line.quantity.rounded()) * decimalOf(w)
                found += 1
            } else {
                missing += 1
            }
        }
        return (found > 0 ? doubleOf(kg) : nil, missing)
    }

    /// The landscape BOQ's standard terms ("Use Standard Terms"): its own
    /// from Settings › BOQ Defaults if set, else the same standard terms as
    /// quotations (Settings › Quotations, else the built-in ones).
    func standardBOQTerms() -> String {
        let settings = getCompanySettings()
        if let own = settings.boqTerms, !isLegacyBOQTerms(own) { return own }
        return settings.quotationTerms ?? defaultQuotationTerms
    }

    /// A quotation's standard key terms: a sale's own if set in Settings,
    /// else the rental ones (or the built-in ones).
    func standardKeyTerms(pricingMode: String) -> String {
        let settings = getCompanySettings()
        if pricingMode == "Sale", let sale = nonBlank(settings.quotationTermsSale) { return sale }
        return settings.quotationTerms ?? defaultQuotationTerms
    }

    func isLegacyBOQTerms(_ text: String) -> Bool {
        let squash = { (t: String) in t.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ") }
        return squash(text) == squash(legacyBOQTerms)
    }

    /// Each material line's weight per unit, from the material list.
    func quotationLineWeights(_ lines: [QuotationLineItem]) -> [String: Double] {
        let items = priceListItemsStore.readAll()
        var out: [String: Double] = [:]
        for line in lines where isMaterialLine(line) {
            let note = DeliveryNoteLineItem(id: line.id, deliveryNoteId: "", sourceKey: line.sourceKey, priceListItemId: line.priceListItemId,
                                            itemCode: line.itemCode, itemDescription: line.itemDescription, unit: line.unit,
                                            quantity: line.quantity, section: line.section, sortOrder: line.sortOrder, notes: nil)
            if let w = deliveryNoteWeight(note, in: items) { out[line.id] = w }
        }
        return out
    }

    func getQuotationDetail(id: String) -> QuotationDetail? {
        guard let q = quotationsStore.readAll().first(where: { $0.id == id }) else { return nil }
        guard let project = projectsStore.readAll().first(where: { $0.id == q.projectId }) else { return nil }
        let items = quotationLineItems(for: q.id)
        let totals = quotationMoney(q, lineItems: items)
        let weight = quotationWeight(items)
        let client = clientsStore.readAll().first { $0.id == project.clientId }
        let site = sitesStore.readAll().first { $0.id == project.siteId }
        let sourceBOQNumber = q.sourceBOQId.flatMap { getBOQ(id: $0)?.boqNumber }
        var detail = QuotationDetail(
            id: q.id, projectId: q.projectId, sourceBOQId: q.sourceBOQId, sourceBOQNumber: sourceBOQNumber,
            quotationNumber: q.quotationNumber, status: q.status, quotationDate: q.quotationDate,
            pricingMode: q.pricingMode, validUntil: q.validUntil, paymentTerms: q.paymentTerms, discountType: q.discountType,
            discountValue: q.discountValue, taxRatePercent: q.taxRatePercent, notes: q.notes,
            createdAt: q.createdAt, updatedAt: q.updatedAt, projectNumber: project.projectNumber,
            projectName: project.name, clientName: client?.companyName, siteName: site?.name,
            lineItems: items, subtotal: totals.subtotal, discountAmount: totals.discountAmount,
            taxAmount: totals.taxAmount, total: totals.total,
            subject: q.subject, clientRef: q.clientRef, siteRef: q.siteRef, deliveryMethod: q.deliveryMethod,
            hireMonths: hireMonths(q), materialsSubtotal: totals.materialsSubtotal, materialsCharge: totals.materialsCharge,
            deliveryTotal: totals.deliveryTotal, standardDeliveryCharge: getCompanySettings().standardDeliveryCharge,
            deliveryRates: getCompanySettings().deliveryRates ?? defaultDeliveryRates,
            materialsWeightKg: weight.kg, linesWithoutWeight: weight.missing,
            minimumHireEnabled: q.pricingMode == "Rental" && (q.minimumHireEnabled ?? true),
            minimumHireMonths: max(1, q.minimumHireMonths ?? getCompanySettings().defaultMinimumHireMonths ?? 2),
            markupPercent: q.markupPercent, markupRoundUp: markupRoundsUp,
            effectiveUnitPrices: Dictionary(items.map { ($0.id, effectiveUnitPrice($0, q)) }, uniquingKeysWith: { a, _ in a }),
            lineTotals: Dictionary(items.map { ($0.id, doubleOf(quotationLineTotal($0, q))) }, uniquingKeysWith: { a, _ in a }),
            blocks: quotationBlocks(for: q.id), otherChargesTotal: totals.otherTotal,
            keyTerms: q.keyTerms, standardKeyTerms: standardKeyTerms(pricingMode: q.pricingMode)
        )
        detail.signedCopyName = q.signedCopyPath.map { URL(fileURLWithPath: $0).lastPathComponent }
        detail.signedCopyAt = q.signedCopyAt
        detail.signedCopyExists = q.signedCopyPath.map { fileIsPresent($0) } ?? false
        detail.signedCopyNotNeeded = q.signedCopyNotNeeded ?? false
        detail.currency = q.currency
        detail.clientAgreedAt = q.clientAgreedAt
        if let docId = q.importedFromDocumentId, let doc = getDocument(id: docId) {
            detail.importedDocumentId = doc.id
            detail.importedFileName = doc.originalName
        }
        detail.directorSignedBy = q.directorSignedBy
        detail.directorSignedAt = q.directorSignedAt
        detail.directorSignedExists = q.directorSignedPath.map { fileIsPresent($0) } ?? false
        detail.directorSignedPath = q.directorSignedPath
        if let pending = signRequestsStore.readAll().first(where: { $0.documentId == q.id && $0.status == "Pending" }) {
            detail.signPendingWith = pending.signer
            detail.signRequestId = pending.id
        }
        detail.clientMarkupPercent = client?.defaultMarkupPercent
        detail.minimumMonthlyChargeEnabled = q.pricingMode == "Rental" && q.minimumMonthlyChargeEnabled == true
        detail.minimumMonthlyCharge = minimumMonthlyRental
        detail.minimumMonthlyApplied = totals.minimumApplied
        detail.monthlyRental = totals.monthlyRental
        detail.charges = totals.charges
        detail.language = q.language
        detail.jobType = normalJobType(project.jobType)
        // "Per unit": one of the dearest item (the equipment), as charged.
        let unitPrices = detail.lineItems.filter { $0.blockId == nil && $0.section != "Delivery" }
            .map { detail.effectiveUnitPrices[$0.id] ?? $0.appliedUnitPrice }
        detail.buyBack = buyBackTerms(for: q, unitPrice: q.pricingMode == "Sale" ? unitPrices.max() : nil)
        detail.orientation = q.orientation == "Landscape" && detail.jobType != "Crane" ? "Landscape" : "Portrait"
        detail.defaultLanguage = getCompanySettings().documentLanguage ?? "English"
        let sourceBOQ = q.sourceBOQId.flatMap { getBOQ(id: $0) }
        detail.boqLinked = q.boqLinked == true && sourceBOQ != nil
        detail.lineSort = q.lineSort ?? "list"
        detail.sourceBOQStatus = sourceBOQ?.status
        let all = quotationsStore.readAll()
        detail.parent = parentQuotation(of: q, in: all)
            .map { QuotationRef(id: $0.id, number: $0.quotationNumber, status: $0.status) }
        detail.subsidiaries = all.filter { parentQuotation(of: $0, in: all)?.id == q.id }.sorted { $0.quotationNumber < $1.quotationNumber }
            .map { QuotationRef(id: $0.id, number: $0.quotationNumber, status: $0.status) }
        return detail
    }

    // ---- Extra sections: priced rows, rates-only rows, notes ----

    func quotationBlocks(for quotationId: String) -> [QuotationBlock] {
        quotationBlocksStore.readAll().filter { $0.quotationId == quotationId }.sorted { $0.sortOrder < $1.sortOrder }
    }

    func draftQuotation(_ id: String) -> Result<Quotation, WorkerError> {
        guard let q = getQuotation(id: id) else { return .failure(WorkerError(message: "Quotation not found.")) }
        guard q.status == "Draft" else { return .failure(WorkerError(message: "This quotation is issued and can no longer be edited.")) }
        return .success(q)
    }

    /// A new section at the end. Priced sections are numbered A, B, C…
    /// (D is taken by delivery charges); rates sections R, S, T…; a rates
    /// section starts with the usual note about labour rates.
    func addQuotationBlock(quotationId: String, kind: String) -> Result<QuotationBlock, WorkerError> {
        guard ["Priced", "Rates", "Note", "BuyBack"].contains(kind) else { return .failure(WorkerError(message: "Unknown kind of section.")) }
        if case .failure(let e) = draftQuotation(quotationId) { return .failure(e) }
        let existing = quotationBlocks(for: quotationId)
        // The buy-back offer: one row, BO1, worded from the quotation's
        // figures (Settings' until changed), under "Buy Back Offer".
        if kind == "BuyBack" {
            guard !existing.contains(where: { $0.kind == "BuyBack" }) else { return .failure(WorkerError(message: "This quotation already has a buy-back offer.")) }
            let block = QuotationBlock(id: makeId("qblock"), quotationId: quotationId, kind: kind, title: "Buy Back Offer", prefix: "BO",
                                       note: nil, sortOrder: (existing.map { $0.sortOrder }.max() ?? -1) + 1)
            quotationBlocksStore.insert(block)
            touchQuotation(quotationId)
            return .success(block)
        }
        let used = Set(existing.map { $0.prefix.uppercased() })
        let letters: [String]
        switch kind {
        case "Priced": letters = "ABCEFGHJKLMNPQ".map { String($0) }
        case "Rates": letters = "RSTUVWXYZ".map { String($0) }
        default: letters = [""]
        }
        let prefix = letters.first { !used.contains($0) } ?? letters.first ?? ""
        let block = QuotationBlock(
            id: makeId("qblock"), quotationId: quotationId, kind: kind,
            title: kind == "Priced" ? "Design Fees" : kind == "Rates" ? "Erection & Dismantle Manpower Rates" : "",
            prefix: prefix,
            note: kind == "Rates" ? "* Please note that labour rates are subject to a price increase for over-time works and works on sundays / public holidays" : nil,
            sortOrder: (existing.map { $0.sortOrder }.max() ?? -1) + 1
        )
        quotationBlocksStore.insert(block)
        touchQuotation(quotationId)
        return .success(block)
    }

    /// Title, row prefix and note. Only fields actually sent are changed.
    func updateQuotationBlock(id: String, payload: [String: Any]) -> String? {
        var blocks = quotationBlocksStore.readAll()
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return "Section not found." }
        if case .failure(let e) = draftQuotation(blocks[i].quotationId) { return e.message }
        if payload.keys.contains("title") {
            blocks[i].title = ((payload["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if payload.keys.contains("prefix") {
            let prefix = ((payload["prefix"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard prefix.count <= 4 else { return "Keep the row prefix short, e.g. \"A\" or \"R\"." }
            blocks[i].prefix = prefix
        }
        if payload.keys.contains("note") { blocks[i].note = text(payload, "note") }
        if payload.keys.contains("chargePeriod") {
            let period = payload["chargePeriod"] as? String
            blocks[i].chargePeriod = ["Day", "Week", "Month"].contains(period ?? "") ? period : nil
        }
        quotationBlocksStore.writeAll(blocks)
        touchQuotation(blocks[i].quotationId)
        return nil
    }

    /// Moves a section up or down among the quotation's sections.
    func moveQuotationBlock(id: String, up: Bool) -> String? {
        var blocks = quotationBlocksStore.readAll()
        guard let target = blocks.first(where: { $0.id == id }) else { return "Section not found." }
        if case .failure(let e) = draftQuotation(target.quotationId) { return e.message }
        let ordered = quotationBlocks(for: target.quotationId)
        guard let position = ordered.firstIndex(where: { $0.id == id }) else { return nil }
        let other = up ? position - 1 : position + 1
        guard ordered.indices.contains(other) else { return nil }
        var order = ordered.map { $0.id }
        order.swapAt(position, other)
        for (n, blockId) in order.enumerated() {
            if let i = blocks.firstIndex(where: { $0.id == blockId }) { blocks[i].sortOrder = n }
        }
        quotationBlocksStore.writeAll(blocks)
        touchQuotation(target.quotationId)
        return nil
    }

    /// Puts a quotation's sections in the order given (dragged in the editor).
    func reorderQuotationBlocks(quotationId: String, ids: [String]) -> String? {
        if case .failure(let e) = draftQuotation(quotationId) { return e.message }
        var blocks = quotationBlocksStore.readAll()
        let current = quotationBlocks(for: quotationId).map { $0.id }
        for (n, blockId) in reordered(current, by: ids).enumerated() {
            if let i = blocks.firstIndex(where: { $0.id == blockId }) { blocks[i].sortOrder = n }
        }
        quotationBlocksStore.writeAll(blocks)
        touchQuotation(quotationId)
        return nil
    }

    /// Removes a section and its rows.
    func removeQuotationBlock(id: String) -> String? {
        var blocks = quotationBlocksStore.readAll()
        guard let target = blocks.first(where: { $0.id == id }) else { return "Section not found." }
        if case .failure(let e) = draftQuotation(target.quotationId) { return e.message }
        blocks.removeAll { $0.id == id }
        quotationBlocksStore.writeAll(blocks)
        var items = quotationLineItemsStore.readAll()
        items.removeAll { $0.blockId == id }
        quotationLineItemsStore.writeAll(items)
        touchQuotation(target.quotationId)
        return nil
    }

    /// "Standard Rates": the standard manpower rates (Settings) as rows of a
    /// rates section — `blockId`'s, or a new "Erection & Dismantle Manpower
    /// Rates" section. Workers already in the section aren't added twice.
    func addStandardManpowerRates(quotationId: String, blockId: String?) -> String? {
        var target: QuotationBlock
        if let blockId = blockId, !blockId.isEmpty {
            guard let block = quotationBlocksStore.readAll().first(where: { $0.id == blockId && $0.quotationId == quotationId }) else { return "Section not found." }
            guard block.kind == "Rates" else { return "Standard rates go in a rates section." }
            target = block
        } else {
            switch addQuotationBlock(quotationId: quotationId, kind: "Rates") {
            case .success(let block): target = block
            case .failure(let e): return e.message
            }
        }
        let existing = Set(quotationLineItemsStore.readAll().filter { $0.blockId == target.id }
            .map { $0.itemDescription.lowercased().trimmingCharacters(in: .whitespaces) })
        for rate in getCompanySettings().manpowerRates ?? defaultManpowerRates
            where !existing.contains(rate.name.lowercased().trimmingCharacters(in: .whitespaces)) {
            if let error = addQuotationBlockLine(blockId: target.id, description: rate.name, unit: rate.unit, quantity: 1, price: rate.rate) {
                return error
            }
        }
        return nil
    }

    /// A row of a priced or rates section: description, unit, quantity
    /// (always 1 for a rate) and unit price / rate.
    /// A priced section's row as charged (nil) or not, with the words typed
    /// in its unit price ("(Included)", "(Free of Charge)"); not charged =
    /// a price of 0. Only rows of priced sections.
    func setQuotationLinePriceNote(id: String, note rawNote: String?) -> String? {
        var items = quotationLineItemsStore.readAll()
        guard let i = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        if case .failure(let e) = draftQuotation(items[i].quotationId) { return e.message }
        let note = nonBlank(rawNote).map { String($0.prefix(60)) }
        if note != nil {
            let block = items[i].blockId.flatMap { bid in quotationBlocksStore.readAll().first { $0.id == bid } }
            guard block?.kind == "Priced" else { return "Words in place of a price are for priced sections only." }
        }
        items[i].priceNote = note
        if note != nil {
            items[i].appliedUnitPrice = 0
            items[i].priceFormula = nil
        }
        quotationLineItemsStore.writeAll(items)
        touchQuotation(items[i].quotationId)
        return nil
    }

    func addQuotationBlockLine(blockId: String, description: String, unit: String, quantity: Double, price: Double, priceNote: String? = nil) -> String? {
        guard let block = quotationBlocksStore.readAll().first(where: { $0.id == blockId }) else { return "Section not found." }
        guard block.kind != "Note", block.kind != "BuyBack" else { return block.kind == "Note" ? "A note has no rows." : "The buy-back offer's row is written from its figures." }
        if case .failure(let e) = draftQuotation(block.quotationId) { return e.message }
        let description = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else { return "Enter a description." }
        guard price >= 0 else { return "Enter a price of zero or more." }
        let nextSortOrder = (quotationLineItemsStore.readAll().filter { $0.quotationId == block.quotationId }.map { $0.sortOrder }.max() ?? -1) + 1
        var line = QuotationLineItem(
            id: makeId("qitem"), quotationId: block.quotationId, sourceKey: nil, priceListItemId: nil,
            itemCode: "", itemDescription: description, unit: unit.trimmingCharacters(in: .whitespacesAndNewlines),
            quantity: block.kind == "Rates" ? 1 : max(1, quantity.rounded()),
            appliedUnitPrice: doubleOf(roundToCents(decimalOf(price))), section: nil, sortOrder: nextSortOrder
        )
        line.blockId = block.id
        if block.kind == "Priced", let note = nonBlank(priceNote) {
            line.priceNote = String(note.prefix(60))
            line.appliedUnitPrice = 0
        }
        quotationLineItemsStore.insert(line)
        touchQuotation(block.quotationId)
        return nil
    }

    /// The standard-quotation fields (subject, refs, delivery method,
    /// minimum hire). Only fields actually sent are changed.
    func updateQuotationLetterFields(id: String, payload: [String: Any]) -> String? {
        var qs = quotationsStore.readAll()
        guard let i = qs.firstIndex(where: { $0.id == id }) else { return "Quotation not found." }
        guard qs[i].status == "Draft" else { return "This quotation is issued and can no longer be edited." }
        if payload.keys.contains("subject") { qs[i].subject = text(payload, "subject") }
        if payload.keys.contains("clientRef") { qs[i].clientRef = text(payload, "clientRef") }
        if payload.keys.contains("siteRef") { qs[i].siteRef = text(payload, "siteRef") }
        if payload.keys.contains("deliveryMethod") { qs[i].deliveryMethod = text(payload, "deliveryMethod") }
        if payload.keys.contains("keyTerms") { qs[i].keyTerms = text(payload, "keyTerms") }
        if payload.keys.contains("currency") { qs[i].currency = text(payload, "currency").map { $0.uppercased() } }
        if let m = payload["minimumHireMonths"] as? Int { qs[i].minimumHireMonths = max(1, m) }
        if let enabled = payload["minimumHireEnabled"] as? Bool { qs[i].minimumHireEnabled = enabled }
        if let enabled = payload["minimumMonthlyChargeEnabled"] as? Bool { qs[i].minimumMonthlyChargeEnabled = enabled ? true : nil }
        // The buy-back offer (crane jobs): a number, or null for Settings'.
        if let enabled = payload["buyBackEnabled"] as? Bool { qs[i].buyBackEnabled = enabled }
        let number: (String) -> NSNumber? = { payload[$0] as? NSNumber }
        if payload.keys.contains("buyBackPercent") { qs[i].buyBackPercent = number("buyBackPercent").map { min(100, max(0, $0.doubleValue)) } }
        if payload.keys.contains("buyBackAfterMonths") { qs[i].buyBackAfterMonths = number("buyBackAfterMonths").map { max(0, $0.intValue) } }
        if payload.keys.contains("buyBackReductionPercent") { qs[i].buyBackReductionPercent = number("buyBackReductionPercent").map { min(100, max(0, $0.doubleValue)) } }
        if payload.keys.contains("buyBackEndMonths") { qs[i].buyBackEndMonths = number("buyBackEndMonths").map { max(0, $0.intValue) } }
        qs[i].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
        return nil
    }

    func touchQuotation(_ id: String) {
        var qs = quotationsStore.readAll()
        guard let index = qs.firstIndex(where: { $0.id == id }) else { return }
        qs[index].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
    }

    func addQuotationLineItem(quotationId: String, sourceKey: String?, priceListItemId: String?, itemCode: String, description: String, unit: String, quantity: Double, appliedUnitPrice: Double, section: String?) -> String? {
        guard let q = getQuotation(id: quotationId) else { return "Quotation not found." }
        guard q.status == "Draft" else { return "This quotation is issued and can no longer be edited." }

        // Items from the material list are priced here, for this
        // quotation's Sale/Rental mode, in the base currency.
        var price = appliedUnitPrice
        var listPrice: Double? = nil
        if let plId = priceListItemId, let pl = priceListItem(id: plId),
           let p = basePrice(pl, mode: q.pricingMode, rates: conversionRates()) {
            price = p
            listPrice = p
        }
        let nextSortOrder = (quotationLineItems(for: quotationId).map { $0.sortOrder }.max() ?? -1) + 1
        let line = QuotationLineItem(
            id: makeId("qitem"), quotationId: quotationId, sourceKey: sourceKey, priceListItemId: priceListItemId,
            itemCode: itemCode, itemDescription: description, unit: unit, quantity: quantity.rounded(),
            appliedUnitPrice: price, section: section, sortOrder: nextSortOrder, priceListUnitPrice: listPrice
        )
        quotationLineItemsStore.insert(line)
        touchQuotation(quotationId)
        // A material on a quotation linked to a BOQ goes on the BOQ too.
        if isMaterialLine(line) { pushQuotationToBOQ(quotationId) }
        return nil
    }

    func updateQuotationLineItem(id: String, quantity: Double?, appliedUnitPrice: Double?, description: String? = nil, unit: String? = nil,
                                 quantityFormula: String? = nil, priceFormula: String? = nil) -> String? {
        var items = quotationLineItemsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        guard let q = getQuotation(id: items[index].quotationId) else { return "Quotation not found." }
        guard q.status == "Draft" else { return "This quotation is issued and can no longer be edited." }

        if let quantity = quantity {
            items[index].quantity = quantity.rounded()
            items[index].quantityFormula = lineFormula(quantityFormula)
        }
        if let appliedUnitPrice = appliedUnitPrice {
            items[index].appliedUnitPrice = appliedUnitPrice
            items[index].priceFormula = lineFormula(priceFormula)
        }
        if let description = description {
            let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return "Enter a description." }
            items[index].itemDescription = trimmed
        }
        if let unit = unit { items[index].unit = unit.trimmingCharacters(in: .whitespacesAndNewlines) }
        quotationLineItemsStore.writeAll(items)
        touchQuotation(q.id)
        pushQuotationToBOQ(q.id)
        return nil
    }

    func removeQuotationLineItem(id: String) -> String? {
        var items = quotationLineItemsStore.readAll()
        guard let target = items.first(where: { $0.id == id }) else { return "Line item not found." }
        guard let q = getQuotation(id: target.quotationId) else { return "Quotation not found." }
        guard q.status == "Draft" else { return "This quotation is issued and can no longer be edited." }

        items.removeAll { $0.id == id }
        quotationLineItemsStore.writeAll(items)
        touchQuotation(q.id)
        // Linked to a BOQ (a Draft): the item comes off it, and off the
        // BOQ's other linked quotations.
        if q.boqLinked == true, target.boqDetached != true, let boqLine = target.boqLineId, let boqId = q.sourceBOQId, getBOQ(id: boqId)?.status == "Draft" {
            var lines = boqLineItemsStore.readAll()
            if lines.contains(where: { $0.id == boqLine && $0.boqId == boqId }) {
                lines.removeAll { $0.id == boqLine && $0.boqId == boqId }
                boqLineItemsStore.writeAll(lines)
                touchBOQ(boqId)
                syncLinkedQuotations(boqId: boqId, except: q.id)
            }
        }
        return nil
    }

    /// `markupPercent` (+30 = +30% on every item, rounded to 0.1) and the
    /// discount ("Percent" 15 = 15% off, "Fixed" 1000 = 1,000 off) come
    /// from the editor's single "Markup / Discount" box; only one is set.
    func updateQuotationHeader(id: String, validUntil: String?, paymentTerms: String?, notes: String?, discountType: String, discountValue: Double, taxRatePercent: Double, pricingMode: String, markupPercent: Double?) -> String? {
        var qs = quotationsStore.readAll()
        guard let index = qs.firstIndex(where: { $0.id == id }) else { return "Quotation not found." }
        guard qs[index].status == "Draft" else { return "This quotation is issued and can no longer be edited." }
        guard ["Sale", "Rental"].contains(pricingMode) else { return "Invalid pricing mode." }
        guard ["None", "Percent", "Fixed"].contains(discountType) else { return "Invalid discount." }
        guard discountValue >= 0, taxRatePercent >= 0 else { return "Enter amounts of zero or more." }
        if discountType == "Percent" && discountValue > 100 { return "A discount can't be more than 100%." }
        if let m = markupPercent, m < 0 || m > 1000 { return "Enter a markup between 0% and 1000%." }
        let oldMarkup = qs[index].markupPercent
        qs[index].markupPercent = (markupPercent ?? 0) > 0 ? markupPercent : nil

        qs[index].validUntil = validUntil
        qs[index].paymentTerms = paymentTerms
        qs[index].notes = notes
        qs[index].discountType = discountType
        qs[index].discountValue = discountValue
        qs[index].taxRatePercent = taxRatePercent
        let oldMode = qs[index].pricingMode
        qs[index].pricingMode = pricingMode
        if oldMode != pricingMode, let project = projectsStore.readAll().first(where: { $0.id == qs[index].projectId }) {
            // The subject line still reads "<project> - Rental[ - structure]": keep it in step.
            let structure = qs[index].sourceBOQId.flatMap { getBOQ(id: $0)?.structure }
            if isAutoQuotationSubject(qs[index].subject, projectName: project.name, pricingMode: oldMode, structures: [structure]) {
                qs[index].subject = autoQuotationSubject(projectName: project.name, pricingMode: pricingMode, structure: structure)
            }
        }
        qs[index].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
        // Linked to a Draft BOQ: a new Sale / Rental or markup is the BOQ's
        // too (it re-prices, then this quotation and the others follow it).
        let markupChanged = (oldMarkup ?? 0) != (qs[index].markupPercent ?? 0)
        if qs[index].boqLinked == true, let boqId = qs[index].sourceBOQId, let boq = getBOQ(id: boqId), boq.status == "Draft",
           oldMode != pricingMode || markupChanged {
            let error = updateBOQDetails(id: boqId, pricingMode: pricingMode,
                                         markupPercent: markupChanged ? (qs[index].markupPercent ?? 0) : nil,
                                         structure: nil, updateStructure: false)
            if error == nil {
                if let fresh = getBOQ(id: boqId) { mirrorBOQ(fresh, into: id) }
                return nil
            }
        }
        if oldMode != pricingMode { repriceQuotationLines(qs[index], from: oldMode) }
        return nil
    }

    /// After a Sale ↔ Rental switch: every line from the material list is
    /// re-priced at its price for the new mode (with the mark-up of the
    /// BOQ it came from, if any). Prices typed in by hand are kept.
    func repriceQuotationLines(_ q: Quotation, from oldMode: String) {
        let rates = conversionRates()
        // An older BOQ's mark-up was built into its prices; now it's the
        // quotation's own markup %, applied when the prices are charged.
        let markup = q.sourceBOQId.flatMap { getBOQ(id: $0) }.flatMap { $0.markupOnRates == true ? 0 : $0.markupPercent } ?? 0
        let priceItems = Dictionary(priceListItemsStore.readAll().map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var lines = quotationLineItemsStore.readAll()
        var repriced = 0, kept = 0
        for i in lines.indices where lines[i].quotationId == q.id {
            guard let plId = lines[i].priceListItemId, let pl = priceItems[plId],
                  let newPrice = boqPrice(for: pl, mode: q.pricingMode, markupPercent: markup, rates: rates) else { continue }
            let handTyped = lines[i].priceListUnitPrice.map { abs($0 - lines[i].appliedUnitPrice) > 0.004 } ?? false
            lines[i].priceListUnitPrice = newPrice
            if handTyped { kept += 1 } else { lines[i].appliedUnitPrice = newPrice; repriced += 1 }
        }
        quotationLineItemsStore.writeAll(lines)
        logActivity(projectId: q.projectId, "Quotation changed from \(oldMode) to \(q.pricingMode) — \(repriced) line(s) re-priced\(kept > 0 ? ", \(kept) hand-typed price(s) kept" : "")", reference: q.quotationNumber)
    }

    /// A discount on one line (quotation or invoice): "None", "Percent"
    /// (0-100) or "Amount" off the line total.
    func checkedDiscount(_ type: String?, _ value: Double?) -> Result<(String?, Double?), WorkerError> {
        let kind = type ?? "None"
        guard ["None", "Percent", "Amount"].contains(kind) else { return .failure(WorkerError(message: "Invalid discount type.")) }
        if kind == "None" { return .success((nil, nil)) }
        let v = value ?? 0
        guard v > 0 else { return .failure(WorkerError(message: "Enter a discount greater than zero.")) }
        if kind == "Percent", v > 100 { return .failure(WorkerError(message: "A percentage discount can't be more than 100%.")) }
        return .success((kind, doubleOf(roundToCents(decimalOf(v)))))
    }

    func updateQuotationLineDiscount(id: String, type: String?, value: Double?) -> String? {
        var items = quotationLineItemsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        guard let q = getQuotation(id: items[index].quotationId) else { return "Quotation not found." }
        guard q.status == "Draft" else { return "This quotation is issued and can no longer be edited." }
        switch checkedDiscount(type, value) {
        case .failure(let e): return e.message
        case .success(let d):
            items[index].discountType = d.0
            items[index].discountValue = d.1
        }
        quotationLineItemsStore.writeAll(items)
        touchQuotation(q.id)
        pushQuotationToBOQ(q.id)
        return nil
    }

    func updateInvoiceLineDiscount(id: String, type: String?, value: Double?) -> String? {
        var items = invoiceLineItemsStore.readAll()
        guard let index = items.firstIndex(where: { $0.id == id }) else { return "Line item not found." }
        guard let inv = getInvoice(id: items[index].invoiceId) else { return "Invoice not found." }
        guard inv.status == "Draft" else { return "This invoice is issued and can no longer be edited." }
        switch checkedDiscount(type, value) {
        case .failure(let e): return e.message
        case .success(let d):
            items[index].discountType = d.0
            items[index].discountValue = d.1
        }
        invoiceLineItemsStore.writeAll(items)
        touchInvoice(inv.id)
        return nil
    }

    /// The quotation's own date (editable while Draft).
    func updateQuotationDate(id: String, day: String) -> String? {
        var qs = quotationsStore.readAll()
        guard let i = qs.firstIndex(where: { $0.id == id }) else { return "Quotation not found." }
        guard qs[i].status == "Draft" else { return "This quotation is issued and can no longer be edited." }
        guard let iso = isoFromDay(day) else { return "Enter a valid date." }
        qs[i].quotationDate = iso
        qs[i].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
        return nil
    }

    func updateQuotationStatus(id: String, status: String) -> String? {
        var qs = quotationsStore.readAll()
        guard let index = qs.firstIndex(where: { $0.id == id }) else { return "Quotation not found." }
        guard ["Draft", "Issued", "Cancelled"].contains(status) else { return "Invalid status." }
        let previous = qs[index].status
        // Section 25: a cancelled quotation is kept for the record and stays
        // cancelled; one can only be issued once it has something on it.
        if previous == "Cancelled" && status != "Cancelled" { return "This quotation is cancelled and can't be reopened. Create a new quotation instead." }
        if status == "Issued" && previous == "Draft" && quotationLineItems(for: id).isEmpty { return "Add at least one item before issuing this quotation." }
        let changed = previous != status
        qs[index].status = status
        qs[index].updatedAt = nowISO()
        quotationsStore.writeAll(qs)
        if changed { logActivity(projectId: qs[index].projectId, "Quotation \(status == "Draft" ? "returned to draft" : status.lowercased())", reference: qs[index].quotationNumber) }
        // Back to Draft while linked: it catches up with its BOQ's changes.
        if changed, status == "Draft", qs[index].boqLinked == true, let boq = qs[index].sourceBOQId.flatMap({ getBOQ(id: $0) }) {
            mirrorBOQ(boq, into: id)
        }
        // A main quotation's subsidiaries follow its status (a subsidiary's
        // own change never moves the main one).
        if changed {
            let all = quotationsStore.readAll()
            for sub in all where sub.id != id && sub.status != status && sub.status != "Cancelled" && parentQuotation(of: sub, in: all)?.id == id {
                _ = updateQuotationStatus(id: sub.id, status: status)
            }
        }
        return nil
    }

    /// One line of a linked quotation taken out of the link (it keeps its
    /// own quantity and price), or put back: `prevail` "quotation" makes the
    /// BOQ's line the quotation's, "boq" the quotation's line the BOQ's.
    func setQuotationLineLink(lineId: String, linked: Bool, prevail: String?) -> String? {
        var lines = quotationLineItemsStore.readAll()
        guard let li = lines.firstIndex(where: { $0.id == lineId }) else { return "Line item not found." }
        guard let q = getQuotation(id: lines[li].quotationId) else { return "Quotation not found." }
        guard q.status == "Draft" else { return "This quotation is issued and can no longer be edited." }
        guard q.boqLinked == true, let boqId = q.sourceBOQId, let boq = getBOQ(id: boqId) else { return "This quotation isn’t linked to a BOQ." }
        guard lines[li].boqLineId != nil || linked else { return "This item isn’t on the BOQ." }
        if !linked {
            lines[li].boqDetached = true
            quotationLineItemsStore.writeAll(lines)
            touchQuotation(q.id)
            logActivity(projectId: q.projectId, "\(lines[li].itemDescription) unlinked from \(boq.boqNumber)", reference: q.quotationNumber)
            return nil
        }
        lines[li].boqDetached = nil
        quotationLineItemsStore.writeAll(lines)
        if prevail == "quotation" {
            guard boq.status == "Draft" else { return "\(boq.boqNumber) is issued, so it keeps its own figures. Relink with the BOQ’s instead." }
            pushQuotationToBOQ(q.id)
        } else {
            mirrorBOQ(boq, into: q.id)
        }
        touchQuotation(q.id)
        logActivity(projectId: q.projectId, "\(lines[li].itemDescription) linked to \(boq.boqNumber) again (\(prevail == "quotation" ? "the quotation’s" : "the BOQ’s") figures kept)", reference: q.quotationNumber)
        return nil
    }

    /// A day-by-day delivery schedule's quantities for `lineIds` moved from
    /// one quotation to another, day for day (a day made there if needed).
    func moveDeliveryQuantities(lineIds: Set<String>, from source: String, to target: String, renamed: [String: String] = [:]) {
        guard !lineIds.isEmpty else { return }
        var days = quotationDeliveriesStore.readAll()
        var changed = false
        for i in days.indices where days[i].quotationId == source {
            let found = days[i].quantities.filter { lineIds.contains($0.key) }
            guard !found.isEmpty else { continue }
            for k in found.keys { days[i].quantities.removeValue(forKey: k) }
            // Onto another line there (merged back): under its id.
            var moving: [String: Double] = [:]
            for (k, v) in found { moving[renamed[k] ?? k, default: 0] += v }
            days[i].updatedAt = nowISO()
            if let t = days.firstIndex(where: { $0.quotationId == target && $0.day == days[i].day }) {
                for (k, v) in moving { days[t].quantities[k] = (days[t].quantities[k] ?? 0) + v }
                days[t].updatedAt = nowISO()
            } else {
                var copy = days[i]
                copy.id = makeId("qdday")
                copy.quotationId = target
                copy.quantities = moving
                copy.createdAt = nowISO()
                copy.updatedAt = nowISO()
                days.append(copy)
            }
            changed = true
        }
        if changed { quotationDeliveriesStore.writeAll(days) }
    }

    /// Part of a line's deliveries, by day (day id → how many), from one
    /// document's schedule to the same day of another's, under `newLineId`.
    func moveDeliveryAmounts(lineId: String, newLineId: String, amounts: [String: Double], from source: String, to target: String) {
        let wanted = amounts.filter { $0.value > 0 }
        guard !wanted.isEmpty else { return }
        var days = quotationDeliveriesStore.readAll()
        var changed = false
        for (dayId, amount) in wanted {
            guard let i = days.firstIndex(where: { $0.id == dayId && $0.quotationId == source }),
                  let had = days[i].quantities[lineId], had > 0 else { continue }
            let take = min(amount, had)
            let left = had - take
            if left > 0.0001 { days[i].quantities[lineId] = left } else { days[i].quantities.removeValue(forKey: lineId) }
            days[i].updatedAt = nowISO()
            if let t = days.firstIndex(where: { $0.quotationId == target && $0.day == days[i].day }) {
                days[t].quantities[newLineId, default: 0] += take
                days[t].updatedAt = nowISO()
            } else {
                var copy = days[i]
                copy.id = makeId("qdday")
                copy.quotationId = target
                copy.quantities = [newLineId: take]
                copy.createdAt = nowISO()
                copy.updatedAt = nowISO()
                days.append(copy)
            }
            changed = true
        }
        if changed { quotationDeliveriesStore.writeAll(days) }
    }

    /// The same item on two quotations (to merge them back into one line):
    /// same description, code, unit, price, section and discount.
    func sameItem(_ a: QuotationLineItem, _ b: QuotationLineItem) -> Bool {
        a.blockId == nil && b.blockId == nil && a.section == b.section && a.itemCode == b.itemCode
            && a.itemDescription == b.itemDescription && a.unit == b.unit && a.priceListItemId == b.priceListItemId
            && abs(a.appliedUnitPrice - b.appliedUnitPrice) < 0.005 && a.priceNote == b.priceNote
            && (a.discountType ?? "None") == (b.discountType ?? "None")
            && ((a.discountType ?? "None") != "Percent" || (a.discountValue ?? 0) == (b.discountValue ?? 0))
            && (a.boqLineId == nil || b.boqLineId == nil || a.boqLineId == b.boqLineId)
    }

    /// Draft only — an issued quotation is cancelled, never deleted
    /// (section 25 again).
    func deleteQuotation(id: String, includingIssued: Bool = false) -> String? {
        guard let q = getQuotation(id: id) else { return "Quotation not found." }
        guard q.status == "Draft" || includingIssued else { return "Only draft quotations can be deleted." }
        var qs = quotationsStore.readAll()
        qs.removeAll { $0.id == id }
        quotationsStore.writeAll(qs)
        unlinkDrawings(kind: "Quotation", id: id)
        logActivity(projectId: q.projectId, "\(q.status == "Draft" ? "Draft" : q.status) quotation deleted", reference: q.quotationNumber)
        var items = quotationLineItemsStore.readAll()
        items.removeAll { $0.quotationId == id }
        quotationLineItemsStore.writeAll(items)
        var blocks = quotationBlocksStore.readAll()
        blocks.removeAll { $0.quotationId == id }
        quotationBlocksStore.writeAll(blocks)
        var days = quotationDeliveriesStore.readAll()
        if days.contains(where: { $0.quotationId == id }) {
            days.removeAll { $0.quotationId == id }
            quotationDeliveriesStore.writeAll(days)
        }
        return nil
    }

    /// Splits a draft quotation: the chosen lines (materials, delivery
    /// charges) and sections (priced, rates, notes — with their rows) move
    /// to a new draft quotation of the same project, e.g. the manpower
    /// part to a quotation of its own. The new one takes the next number
    /// and the letter's details (subject, refs, pricing, markup, terms…);
    /// it isn't linked to this one — each is changed on its own — but is
    /// listed under it as its subsidiary. The delivery schedule and the
    /// drawings stay here.
    /// The quotation `q` was split off: by its link — or, should the link be
    /// missing (e.g. the record was saved by an older copy of the app, on
    /// another Mac sharing the data, which drops fields it doesn't know),
    /// by its number: Qt26210-004-s1 → Qt26210-004 in the same project.
    func parentQuotation(of q: Quotation, in all: [Quotation]) -> Quotation? {
        if let pid = q.parentQuotationId, let parent = all.first(where: { $0.id == pid }) { return parent }
        guard let r = q.quotationNumber.range(of: #"-s\d+$"#, options: .regularExpression) else { return nil }
        let base = String(q.quotationNumber[..<r.lowerBound])
        return all.first { $0.id != q.id && $0.projectId == q.projectId && $0.quotationNumber == base }
    }

    /// A subsidiary's number: its parent's with "-s1", "-s2"… (Qt26212-007-s1).
    func subsidiaryNumber(of parentNumber: String) -> String {
        let used = Set(quotationsStore.readAll().map { $0.quotationNumber.lowercased() })
        var n = 1
        while used.contains("\(parentNumber)-s\(n)".lowercased()) { n += 1 }
        return "\(parentNumber)-s\(n)"
    }

    /// "Revert" on a subsidiary: every line and section goes back onto the
    /// quotation it was split off (sections renamed A → B… where the letter
    /// is taken there), and the subsidiary is deleted. Both must be drafts.
    /// Quotations split off the subsidiary move up to its parent.
    func revertQuotationSplit(id: String) -> QuotationSplitResult {
        guard let q = getQuotation(id: id) else { return QuotationSplitResult(ok: false, error: "Quotation not found.") }
        guard let parent = parentQuotation(of: q, in: quotationsStore.readAll()) else {
            return QuotationSplitResult(ok: false, error: "The quotation this was split off is no longer there.")
        }
        guard q.status == "Draft" else {
            return QuotationSplitResult(ok: false, error: "\(q.quotationNumber) is \(q.status.lowercased()). Only a draft subsidiary can be reverted; set it back to Draft first.")
        }
        guard parent.status == "Draft" else {
            return QuotationSplitResult(ok: false, error: "\(parent.quotationNumber) is \(parent.status.lowercased()), so nothing can be added to it. Set it back to Draft first.")
        }
        // Its sections after the parent's, each with a letter not taken there.
        let parentBlocks = quotationBlocks(for: parent.id)
        var usedPrefixes = Set(parentBlocks.map { $0.prefix.uppercased() })
        var blocks = quotationBlocksStore.readAll()
        var order = (parentBlocks.map { $0.sortOrder }.max() ?? -1) + 1
        for block in quotationBlocks(for: q.id) {
            guard let i = blocks.firstIndex(where: { $0.id == block.id }) else { continue }
            blocks[i].quotationId = parent.id
            blocks[i].sortOrder = order
            order += 1
            if !block.prefix.isEmpty && usedPrefixes.contains(block.prefix.uppercased()) {
                let letters = (block.kind == "Rates" ? "RSTUVWXYZ" : "ABCEFGHJKLMNPQ").map { String($0) }
                if let free = letters.first(where: { !usedPrefixes.contains($0) }) { blocks[i].prefix = free }
            }
            usedPrefixes.insert(blocks[i].prefix.uppercased())
        }
        quotationBlocksStore.writeAll(blocks)
        // Its lines after the parent's — or, the same item as one there,
        // added to that line's quantity (and its deliveries to that line's).
        var lines = quotationLineItemsStore.readAll()
        var next = (lines.filter { $0.quotationId == parent.id && $0.blockId == nil }.map { $0.sortOrder }.max() ?? -1) + 1
        let moved = lines.filter { $0.quotationId == q.id }.count
        let boqQuantity = Dictionary(boqLineItemsStore.readAll().map { ($0.id, $0.quantity) }, uniquingKeysWith: { a, _ in a })
        var mergedInto: [String: String] = [:]
        for i in lines.indices where lines[i].quotationId == q.id && lines[i].blockId == nil {
            guard let t = lines.indices.first(where: { lines[$0].quotationId == parent.id && sameItem(lines[$0], lines[i]) }) else { continue }
            lines[t].quantity += lines[i].quantity
            lines[t].quantityFormula = nil
            if lines[t].discountType == "Amount" { lines[t].discountValue = (lines[t].discountValue ?? 0) + (lines[i].discountValue ?? 0) }
            if lines[t].boqLineId == nil { lines[t].boqLineId = lines[i].boqLineId }
            // Whole again: it follows its BOQ line again when they agree.
            if lines[t].boqDetached == true, let b = lines[t].boqLineId, let bq = boqQuantity[b], abs(bq.rounded() - lines[t].quantity) < 0.0001 {
                lines[t].boqDetached = nil
            }
            mergedInto[lines[i].id] = lines[t].id
        }
        moveDeliveryQuantities(lineIds: Set(lines.filter { $0.quotationId == q.id }.map { $0.id }), from: q.id, to: parent.id, renamed: mergedInto)
        lines.removeAll { mergedInto[$0.id] != nil }
        for i in lines.indices where lines[i].quotationId == q.id {
            lines[i].quotationId = parent.id
            if lines[i].blockId == nil {
                lines[i].sortOrder = next
                next += 1
            }
        }
        quotationLineItemsStore.writeAll(lines)
        var qs = quotationsStore.readAll()
        let children = Set(qs.filter { parentQuotation(of: $0, in: qs)?.id == q.id }.map { $0.id })
        for i in qs.indices where children.contains(qs[i].id) { qs[i].parentQuotationId = parent.id }
        quotationsStore.writeAll(qs)
        touchQuotation(parent.id)
        _ = deleteQuotation(id: q.id)
        logActivity(projectId: parent.projectId, "Subsidiary \(q.quotationNumber) reverted — its \(moved) line(s) are back on it", reference: parent.quotationNumber)
        return QuotationSplitResult(ok: true, error: nil, id: parent.id, number: parent.quotationNumber)
    }

    /// Part of a line moved by a split: how many, and how many of them come
    /// off each day of the delivery schedule (day id → how many).
    struct PartialSplit {
        var quantity: Double
        var days: [String: Double]
    }

    func splitQuotation(id: String, lineIds: [String], blockIds: [String], partial: [String: PartialSplit] = [:]) -> QuotationSplitResult {
        guard let q = getQuotation(id: id) else { return QuotationSplitResult(ok: false, error: "Quotation not found.") }
        guard q.status == "Draft" else {
            return QuotationSplitResult(ok: false, error: "Only a draft quotation can be split. Set it back to Draft first.")
        }
        guard projectsStore.readAll().contains(where: { $0.id == q.projectId }) else {
            return QuotationSplitResult(ok: false, error: "Project not found.")
        }
        let items = quotationLineItems(for: id)
        let blocks = quotationBlocks(for: id)
        let movingBlocks = blocks.filter { blockIds.contains($0.id) }
        let movingBlockIds = Set(movingBlocks.map { $0.id })
        // Rows of a section go with it; other lines only when chosen.
        let moving = items.filter { l in l.blockId.map { movingBlockIds.contains($0) } ?? lineIds.contains(l.id) }
        // Lines split by quantity: some stay here, the rest go.
        let parts = partial.compactMapValues { p -> PartialSplit? in p.quantity > 0 ? p : nil }
            .filter { k, p in !lineIds.contains(k) && items.contains { $0.id == k && $0.blockId == nil && p.quantity < $0.quantity } }
        guard !moving.isEmpty || !movingBlocks.isEmpty || !parts.isEmpty else {
            return QuotationSplitResult(ok: false, error: "Tick what to move to the new quotation.")
        }
        guard !parts.isEmpty || moving.count < items.count || movingBlocks.count < blocks.count else {
            return QuotationSplitResult(ok: false, error: "That's everything on this quotation — leave at least one line or section on it.")
        }
        // Linked to a BOQ: the subsidiary is linked to it too, holding the
        // items it takes (the BOQ keeps the main's and the subsidiaries').
        var split = Quotation(
            id: makeId("quotation"), projectId: q.projectId, sourceBOQId: q.sourceBOQId,
            quotationNumber: subsidiaryNumber(of: q.quotationNumber),
            status: "Draft", quotationDate: nowISO(), pricingMode: q.pricingMode, validUntil: q.validUntil,
            paymentTerms: q.paymentTerms, discountType: "None", discountValue: 0, taxRatePercent: q.taxRatePercent,
            notes: q.notes, createdAt: nowISO(), updatedAt: nowISO())
        // Moving one titled section: its title ends the subject line
        // ("… - Rental - Provision of Manpower").
        let title = movingBlocks.count == 1 && moving.allSatisfy({ $0.blockId != nil }) ? nonBlank(movingBlocks[0].title) : nil
        split.subject = nonBlank([nonBlank(q.subject), title].compactMap { $0 }.joined(separator: " - "))
        split.clientRef = q.clientRef
        split.siteRef = q.siteRef
        split.deliveryMethod = q.deliveryMethod
        split.minimumHireMonths = q.minimumHireMonths
        split.minimumHireEnabled = q.minimumHireEnabled
        split.minimumMonthlyChargeEnabled = q.minimumMonthlyChargeEnabled
        split.language = q.language
        split.markupPercent = q.markupPercent
        split.keyTerms = q.keyTerms
        split.lineSort = q.lineSort == "manual" ? "manual" : nil
        split.orientation = q.orientation
        split.parentQuotationId = q.id
        split.boqLinked = q.boqLinked
        quotationsStore.insert(split)

        let movingIds = Set(moving.map { $0.id })
        var lines = quotationLineItemsStore.readAll()
        for i in lines.indices where movingIds.contains(lines[i].id) {
            lines[i].quotationId = split.id
            if q.sourceBOQId == nil { lines[i].boqLineId = nil }
        }
        // Part of a line: a copy with that many goes; this one keeps the
        // rest. Linked to a BOQ, both keep their own quantities from now on
        // (as "Unlink from BOQ") until merged back.
        var partMoves: [(from: String, to: String, days: [String: Double])] = []
        for (lineId, part) in parts {
            guard let i = lines.firstIndex(where: { $0.id == lineId }) else { continue }
            let whole = lines[i].quantity
            var copy = lines[i]
            copy.id = makeId("qitem")
            copy.quotationId = split.id
            copy.quantity = part.quantity
            copy.quantityFormula = nil
            lines[i].quantity = whole - part.quantity
            lines[i].quantityFormula = nil
            if lines[i].discountType == "Amount", let amount = lines[i].discountValue, whole > 0 {
                copy.discountValue = amount * part.quantity / whole
                lines[i].discountValue = amount - (copy.discountValue ?? 0)
            }
            if q.sourceBOQId == nil { copy.boqLineId = nil }
            if q.boqLinked == true && lines[i].boqLineId != nil {
                lines[i].boqDetached = true
                copy.boqDetached = true
            }
            lines.append(copy)
            partMoves.append((lineId, copy.id, part.days))
        }
        quotationLineItemsStore.writeAll(lines)
        // Their deliveries go with them, day for day.
        moveDeliveryQuantities(lineIds: movingIds, from: q.id, to: split.id)
        for m in partMoves {
            moveDeliveryAmounts(lineId: m.from, newLineId: m.to, amounts: m.days, from: q.id, to: split.id)
        }
        var allBlocks = quotationBlocksStore.readAll()
        for (n, block) in movingBlocks.enumerated() {
            if let i = allBlocks.firstIndex(where: { $0.id == block.id }) {
                allBlocks[i].quotationId = split.id
                allBlocks[i].sortOrder = n
            }
        }
        quotationBlocksStore.writeAll(allBlocks)
        touchQuotation(q.id)
        logActivity(projectId: q.projectId, "Quotation split — \(split.quotationNumber) made from part of it", reference: q.quotationNumber)
        logActivity(projectId: q.projectId, "Quotation split off \(q.quotationNumber)", reference: split.quotationNumber)
        return QuotationSplitResult(ok: true, error: nil, id: split.id, number: split.quotationNumber)
    }

    // ---- Quotation delivery schedule ----

    /// A quotation's — or a BOQ's — delivery schedule (`quotationId` is
    /// the document's id), with each line's unit weight.
    func deliverySchedule(quotationId: String) -> DeliveryScheduleData {
        let days = quotationDeliveriesStore.readAll().filter { $0.quotationId == quotationId }.sorted { ($0.day, $0.createdAt) < ($1.day, $1.createdAt) }
        let itemWeights = Dictionary(priceListItemsStore.readAll().compactMap { i in i.weightKg.map { (i.id, $0) } }, uniquingKeysWith: { a, _ in a })
        var weights: [String: Double] = [:]
        for line in quotationLineItemsStore.readAll() where line.quotationId == quotationId {
            if let w = line.priceListItemId.flatMap({ itemWeights[$0] }) { weights[line.id] = w }
        }
        for line in boqLineItemsStore.readAll() where line.boqId == quotationId {
            if let w = line.weightKg ?? line.priceListItemId.flatMap({ itemWeights[$0] }) { weights[line.id] = w }
        }
        return DeliveryScheduleData(days: days, weights: weights)
    }

    /// Adds the next day (Day n+1) to a quotation's (or BOQ's) delivery
    /// schedule, dated the day after the latest date put in for a day
    /// before it. Only Day 1 (or when no day has a date yet) starts blank.
    func addDeliveryDay(quotationId: String) -> String? {
        guard getQuotation(id: quotationId) != nil || getBOQ(id: quotationId) != nil else { return "Document not found." }
        let days = quotationDeliveriesStore.readAll().filter { $0.quotationId == quotationId }
        let last = days.max { ($0.day, $0.createdAt) < ($1.day, $1.createdAt) }
        let date: String? = days.compactMap { validDay($0.date) }.max().flatMap { day in
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyy-MM-dd"
            return f.date(from: day).flatMap { Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: $0) }.map { f.string(from: $0) }
        }
        quotationDeliveriesStore.insert(QuotationDeliveryDay(id: makeId("qdday"), quotationId: quotationId, day: (last?.day ?? 0) + 1, date: date, sent: nil,
                                                             note: nil, quantities: [:], createdAt: nowISO(), updatedAt: nowISO()))
        return nil
    }

    /// Changes a day: its date, whether it was sent, its note, and any
    /// quantities given ({ lineId: quantity }; 0 or less takes the item off that day).
    func updateDeliveryDay(id: String, payload: [String: Any]) -> String? {
        var all = quotationDeliveriesStore.readAll()
        guard let i = all.firstIndex(where: { $0.id == id }) else { return "Delivery day not found." }
        if payload.keys.contains("date") {
            let text = nonBlank(payload["date"] as? String)
            if text != nil && validDay(text) == nil { return "Enter a valid date." }
            all[i].date = validDay(text)
        }
        if payload.keys.contains("time") { all[i].time = validTime(payload["time"] as? String) }
        if let sent = payload["sent"] as? Bool { all[i].sent = sent ? true : nil }
        if payload.keys.contains("note") { all[i].note = nonBlank(payload["note"] as? String) }
        if payload.keys.contains("internalNote") { all[i].internalNote = nonBlank(payload["internalNote"] as? String) }
        if let quantities = payload["quantities"] as? [String: Any] {
            for (lineId, raw) in quantities {
                let q = ((raw as? Double) ?? 0).rounded()
                if q > 0 { all[i].quantities[lineId] = q } else { all[i].quantities.removeValue(forKey: lineId) }
            }
        }
        all[i].updatedAt = nowISO()
        quotationDeliveriesStore.writeAll(all)
        return nil
    }
}

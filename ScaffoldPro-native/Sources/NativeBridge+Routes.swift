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

extension NativeBridge {
    // MARK: ScaffoldPro Web (pages in a browser, through WebServer)


    /// Actions that need this Mac's own windows (choosing files or folders,
    /// joining a shared folder, backups, updates): not from a browser.
    static func macOnly(_ action: String) -> Bool {
        let exact: Set<String> = ["priceLists:importPreview", "parties:exportXLSX", "parties:importPreview", "priceLists:exportCSV",
                                  "projects:uploadDrawing", "signatures:chooseImage", "chat:attach", "quotations:uploadSigned", "deliveryNotes:uploadSigned",
                                  "settings:chooseLogo", "drawings:relink", "drawings:replace", "documents:replace", "documents:upload",
                                  "documents:relink", "workerDocuments:upload", "workerDocuments:relink", "adminDocuments:upload",
                                  "adminDocuments:relink", "users:setName", "team:start", "team:join", "team:leave", "team:setName", "team:reveal",
                                  "projects:revealFolder", "letters:addAttachmentFiles", "workerAgreements:uploadSigned"]
        if exact.contains(action) { return true }
        return ["backup:", "cloudBackup:", "app:", "web:", "sheets:"].contains { action.hasPrefix($0) }
    }

    /// Handles a browser's request as `person`.
    func handleWeb(id: String, action: String, payload: [String: Any], person: String) {
        servingWeb = true
        TeamSync.actingAs = person
        defer { servingWeb = false; TeamSync.actingAs = nil }
        handle(id: id, action: action, payload: payload)
    }

    /// Opens a file for whoever asked: on this Mac, or as a download in their browser.
    func openForUser(_ url: URL) {
        if servingWeb { webOpenURL = url } else { NSWorkspace.shared.open(url) }
    }

    /// Shows files in Finder; in a browser, a single file is downloaded instead.
    func revealForUser(_ urls: [URL]) {
        if servingWeb {
            if let file = urls.first(where: { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true }) { webOpenURL = file }
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    func revealOne(_ url: URL) { revealForUser([url]) }

    /// Answers a page's request — from this Mac's window, or a browser.
    func handle(id: String, action: String, payload: [String: Any]) {
        // A reload without a flash (window.softReload in js/bridge.js).
        if action == "ui:holdFrame" || action == "ui:releaseFrame" {
            if servingWeb { respond(id: id, encodable: SimpleResult(ok: true, error: nil)); return }
            if action == "ui:releaseFrame" {
                releaseFrame()
                respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            } else {
                holdFrame { [weak self] in self?.respond(id: id, encodable: SimpleResult(ok: true, error: nil)) }
            }
            return
        }
        // A new BOQ or quotation (its series' folders), or a new structure
        // or subject (its series' folder's name): the folders follow.
        if NativeBridge.seriesCreatingActions.contains(action) || action == "boq:updateDetails" || action == "quotations:updateLetterFields" {
            organiseSoon?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.organiseProjectFolders() }
            organiseSoon = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
        }
        switch action {
        case "history:undo", "history:redo":
            // Undo / Redo: the latest step's records put back (UndoJournal).
            guard !servingWeb else {
                respond(id: id, encodable: UndoResult(ok: false, error: "Undo works in the ScaffoldPro app on the Mac.", label: nil, canUndo: false, canRedo: false))
                return
            }
            let journal = UndoJournal.shared
            let label = action == "history:undo" ? journal.undo() : journal.redo()
            if let label = label {
                db.logActivity(projectId: nil, action == "history:undo" ? "Undone: \(label)" : "Redone: \(label)")
            }
            respond(id: id, encodable: UndoResult(ok: label != nil, error: label == nil ? (action == "history:undo" ? "Nothing to undo." : "Nothing to redo.") : nil,
                                                  label: label, canUndo: journal.canUndo, canRedo: journal.canRedo))
        case "clients:list":
            respond(id: id, encodable: db.listClients(includeArchived: (payload["includeArchived"] as? Bool) ?? false))
        case "clients:create":
            respond(id: id, encodable: db.createClient(payload))
        case "clients:update":
            let error = db.updateClient(id: (payload["id"] as? String) ?? "", payload: payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "clients:setArchived":
            let error = db.setClientArchived(id: (payload["id"] as? String) ?? "", archived: (payload["archived"] as? Bool) ?? true)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "clients:detail":
            respond(id: id, encodable: db.partyDetail(clientId: (payload["id"] as? String) ?? "", siteId: nil))
        case "sites:list":
            respond(id: id, encodable: db.listSites(includeArchived: (payload["includeArchived"] as? Bool) ?? false))
        case "sites:create":
            respond(id: id, encodable: db.createSite(payload))
        case "sites:update":
            let error = db.updateSite(id: (payload["id"] as? String) ?? "", payload: payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "sites:setArchived":
            let error = db.setSiteArchived(id: (payload["id"] as? String) ?? "", archived: (payload["archived"] as? Bool) ?? true)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "sites:detail":
            respond(id: id, encodable: db.partyDetail(clientId: nil, siteId: (payload["id"] as? String) ?? ""))

        case "dashboard:summary":
            respond(id: id, encodable: db.dashboardSummary())
        case "search:query":
            respond(id: id, encodable: db.search((payload["query"] as? String) ?? ""))
        case "activity:listForProject":
            respond(id: id, encodable: db.listActivity(projectId: (payload["projectId"] as? String) ?? "", limit: (payload["limit"] as? Int) ?? 200))
        case "priceLists:list":
            respond(id: id, encodable: db.listPriceLists())
        case "priceListItems:search":
            let sourceKey = (payload["sourceKey"] as? String) ?? ""
            let query = (payload["query"] as? String) ?? ""
            let category = payload["category"] as? String
            let found = db.searchPriceListItems(sourceKey: sourceKey, query: query, category: category)
            // Document pickers ask for prices in HKD; the Material List page
            // shows each list in its own currency.
            respond(id: id, encodable: (payload["inBaseCurrency"] as? Bool) == true ? db.inBaseCurrency(found) : found)
        case "priceListItems:update":
            handleUpdatePriceListItem(id: id, payload: payload)
        case "priceListItems:create":
            switch db.createPriceListItem(sourceKey: (payload["sourceKey"] as? String) ?? "", payload: payload) {
            case .success: respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            case .failure(let e): respond(id: id, encodable: SimpleResult(ok: false, error: e.message))
            }
        case "priceListItems:archive":
            let error = db.archivePriceListItem(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "priceLists:syncStatus":
            // How the material list is kept the same on every Mac.
            struct MaterialSyncStatus: Encodable { var mode: String; var folder: String?; var otherMacs: Int }
            if let team = TeamSync.current {
                respond(id: id, encodable: MaterialSyncStatus(mode: "team", folder: TeamSync.display(team.root), otherMacs: max(0, team.members().count - 1)))
            } else if let material = TeamSync.material {
                respond(id: id, encodable: MaterialSyncStatus(mode: "icloud", folder: TeamSync.display(material.root), otherMacs: max(0, material.members().count - 1)))
            } else {
                respond(id: id, encodable: MaterialSyncStatus(mode: "off", folder: nil, otherMacs: 0))
            }
        case "priceLists:unitRatesPDF":
            handleExportUnitRates(id: id, payload: payload)
        case "priceListItems:setPinned":
            let error = db.setPriceListItemPinned(id: (payload["id"] as? String) ?? "", pinned: (payload["pinned"] as? Bool) ?? false)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "priceListItems:reorderPinned":
            let error = db.reorderPinnedItems(ids: (payload["ids"] as? [String]) ?? [])
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "priceListItems:reorder":
            let error = db.reorderPriceListItems(ids: (payload["ids"] as? [String]) ?? [])
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "priceListItems:duplicate":
            switch db.duplicatePriceListItem(id: (payload["id"] as? String) ?? "") {
            case .success: respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            case .failure(let e): respond(id: id, encodable: SimpleResult(ok: false, error: e.message))
            }
        case "priceLists:importPreview":
            handlePriceImportPreview(id: id, sourceKey: (payload["sourceKey"] as? String) ?? "")
        case "priceLists:importApply":
            handlePriceImportApply(id: id, token: (payload["token"] as? String) ?? "")
        case "parties:exportXLSX":
            handlePartyExport(id: id, kind: (payload["kind"] as? String) ?? "clients", includeArchived: (payload["includeArchived"] as? Bool) ?? false)
        case "parties:importPreview":
            handlePartyImportPreview(id: id, kind: (payload["kind"] as? String) ?? "clients")
        case "parties:importApply":
            handlePartyImportApply(id: id, token: (payload["token"] as? String) ?? "")
        case "priceLists:exportCSV":
            handlePriceExportCSV(id: id, sourceKey: (payload["sourceKey"] as? String) ?? "")
        case "projects:list":
            respond(id: id, encodable: projectListEntries())
        case "projects:proposeNumber":
            respond(id: id, encodable: nextProjectNumber(existingNumbers: db.allProjectNumbers()))
        case "projects:create":
            handleCreateProject(id: id, payload: payload)
        case "projects:get":
            handleGetProject(id: id, payload: payload)
        case "projects:changeNumber":
            handleChangeProjectNumber(id: id, projectId: (payload["id"] as? String) ?? "", newNumber: (payload["projectNumber"] as? String) ?? "")
        case "projects:update":
            var error = db.updateProject(id: (payload["id"] as? String) ?? "", payload: payload)
            if error == nil, let maker = nonBlank(payload["createdBy"] as? String) {
                error = db.setCreator(file: "projects.json", id: (payload["id"] as? String) ?? "", name: maker)
            }
            // A new name: its folder follows ("26219 New name").
            if error == nil, payload["name"] != nil, let project = db.getProject(id: (payload["id"] as? String) ?? "") {
                organiseProjectFolders([project.projectNumber])
            }
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "quotations:setLineLink":
            let error = db.setQuotationLineLink(lineId: (payload["id"] as? String) ?? "", linked: (payload["linked"] as? Bool) ?? true, prevail: payload["prevail"] as? String)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "projects:overview":
            respond(id: id, encodable: db.projectsOverview())
        case "projects:contents":
            respond(id: id, encodable: db.projectContents(id: (payload["id"] as? String) ?? ""))
        case "projects:delete":
            let pid = (payload["id"] as? String) ?? ""
            let number = db.getProject(id: pid)?.projectNumber
            let error = db.deleteProject(id: pid, confirm: payload["confirm"] as? String)
            var trashed = false
            if error == nil, let number = number, !number.isEmpty {
                let folder = storage.projectFolder(number)
                if FileManager.default.fileExists(atPath: folder.path) {
                    trashed = (try? FileManager.default.trashItem(at: folder, resultingItemURL: nil)) != nil
                }
            }
            struct DeleteProjectResult: Encodable { var ok: Bool; var error: String?; var folderTrashed: Bool }
            respond(id: id, encodable: DeleteProjectResult(ok: error == nil, error: error, folderTrashed: trashed))
        case "projects:updateStatus":
            if let pid = payload["id"] as? String, let status = payload["status"] as? String {
                db.updateProjectStatus(id: pid, status: status)
            }
            respondNull(id: id)
        case "projects:revealFolder":
            let number = (payload["projectNumber"] as? String) ?? ""
            let folder = storage.projectFolder(number)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            self.revealOne(folder)
            respondNull(id: id)
        case "files:dropIntoProject":
            handleDroppedProjectFiles(id: id, payload: payload)
        case "projects:uploadDrawing":
            let number = (payload["projectNumber"] as? String) ?? ""
            handleUploadDrawing(id: id, projectNumber: number, linkedKind: payload["linkedKind"] as? String, linkedId: payload["linkedId"] as? String)
        case "documents:setLink":
            let docId = (payload["id"] as? String) ?? ""
            let error = db.setDocumentLink(id: docId, kind: payload["linkedKind"] as? String, linkedId: payload["linkedId"] as? String)
            // Its file follows: into the series' Documents folder, or back.
            if error == nil, let d = db.getDocument(id: docId), let project = db.getProject(id: d.projectId),
               let m = refileLinkedFile(path: d.filePath, projectNumber: project.projectNumber, kind: d.linkedKind, linkedId: d.linkedId, sub: "Documents") {
                db.rebaseFilePaths(moves: [m])
                removeEmptyProjectFolders(project.projectNumber)
            }
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "drawings:setLink":
            let drawingId = (payload["id"] as? String) ?? ""
            let error = db.setDrawingLink(id: drawingId, kind: payload["linkedKind"] as? String, linkedId: payload["linkedId"] as? String)
            if error == nil, let d = db.getDrawing(id: drawingId), let project = db.getProject(id: d.projectId),
               let m = refileLinkedFile(path: d.filePath, projectNumber: project.projectNumber, kind: d.linkedKind, linkedId: d.linkedId, sub: "Drawings") {
                db.rebaseFilePaths(moves: [m])
                removeEmptyProjectFolders(project.projectNumber)
            }
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "drawings:listForDocument":
            respond(id: id, encodable: db.listDrawings(linkedKind: (payload["linkedKind"] as? String) ?? "", linkedId: (payload["linkedId"] as? String) ?? ""))

        case "boq:listForProject":
            let projectId = (payload["projectId"] as? String) ?? ""
            respond(id: id, encodable: db.listBOQSummaries(projectId: projectId))
        case "boq:combine":
            let r = db.combineBOQs(ids: (payload["ids"] as? [String]) ?? [])
            respond(id: id, encodable: CombinedDocumentResult(ok: r.error == nil, error: r.error, id: r.id))
        case "deliveryNotes:combine":
            let r = db.combineDeliveryNotes(ids: (payload["ids"] as? [String]) ?? [])
            respond(id: id, encodable: CombinedDocumentResult(ok: r.error == nil, error: r.error, id: r.id))
        case "deliveryNotes:importQuotation":
            let r = db.importQuotationIntoDeliveryNote(
                deliveryNoteId: (payload["id"] as? String) ?? "",
                quotationId: (payload["quotationId"] as? String) ?? "",
                replaceExisting: (payload["replaceExisting"] as? Bool) ?? false
            )
            respond(id: id, encodable: DroppedFilesResult(ok: r.error == nil, added: r.added, error: r.error))
        case "boq:create":
            handleCreateBOQ(id: id, payload: payload)
        case "boq:get":
            let boqId = (payload["id"] as? String) ?? ""
            if let detail = db.getBOQDetail(id: boqId) {
                respond(id: id, encodable: detail)
            } else {
                respondNull(id: id)
            }
        case "boq:addLineItem":
            handleAddBOQLineItem(id: id, payload: payload)
        case "boq:updateLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            let quantity = payload["quantity"] as? Double
            let appliedUnitPrice = payload["appliedUnitPrice"] as? Double
            if let error = db.updateBOQLineItem(id: lineId, quantity: quantity, appliedUnitPrice: appliedUnitPrice,
                                                quantityFormula: payload["quantityFormula"] as? String) {
                respond(id: id, encodable: BOQActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: BOQActionResult(ok: true, error: nil))
            }
        case "boq:removeLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            if let error = db.removeBOQLineItem(id: lineId) {
                respond(id: id, encodable: BOQActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: BOQActionResult(ok: true, error: nil))
            }
        case "boq:updateStatus":
            let boqId = (payload["id"] as? String) ?? ""
            let status = (payload["status"] as? String) ?? ""
            if let error = db.updateBOQStatus(id: boqId, status: status) {
                respond(id: id, encodable: BOQActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: BOQActionResult(ok: true, error: nil))
            }
        case "documents:authors":
            respond(id: id, encodable: db.documentAuthors(kind: (payload["kind"] as? String) ?? "", id: (payload["id"] as? String) ?? "",
                                                          number: payload["number"] as? String))
        case "letters:list":
            respond(id: id, encodable: db.listLetters(projectId: nonBlank(payload["projectId"] as? String)))
        case "letters:create":
            handleCreateLetter(id: id, payload: payload)
        case "letters:get":
            if let letter = db.getLetter(id: (payload["id"] as? String) ?? "") {
                let project = letter.projectId.flatMap { db.getProject(id: $0) }
                respond(id: id, encodable: LetterDetail(letter: letter, projectNumber: project?.projectNumber, projectName: project?.name,
                                                        openingHTML: letterOpeningHTML(letter)))
            } else {
                respondNull(id: id)
            }
        case "letters:update":
            let error = db.updateLetter(id: (payload["id"] as? String) ?? "", payload: payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "letters:updateStatus":
            let error = db.updateLetterStatus(id: (payload["id"] as? String) ?? "", status: (payload["status"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "letters:delete":
            let error = db.deleteLetter(id: (payload["id"] as? String) ?? "", force: (payload["force"] as? Bool) ?? false)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "letters:exportPDF":
            handleExportLetter(id: id, letterId: (payload["id"] as? String) ?? "", mode: previewMode(payload))
        case "letters:print":
            handleExportLetter(id: id, letterId: (payload["id"] as? String) ?? "", mode: .print)
        case "letters:addAttachmentFiles":
            handleAddLetterAttachment(id: id, letterId: (payload["id"] as? String) ?? "", attachmentId: nonBlank(payload["attachmentId"] as? String))
        case "letters:openAttachmentFile":
            let path = (payload["path"] as? String) ?? ""
            if fileIsPresent(path) { self.openForUser(URL(fileURLWithPath: path)); respond(id: id, encodable: SimpleResult(ok: true, error: nil)) }
            else { respond(id: id, encodable: SimpleResult(ok: false, error: "That file isn’t there any more.")) }
        case "letters:letterhead":
            // The letterhead and footer as a page-sized picture, for the editor's page.
            struct LetterheadPicture: Encodable { var png: String?; var paperSize: String }
            let paper = db.getCompanySettings().paperSize ?? "A4"
            respond(id: id, encodable: LetterheadPicture(png: PDFGenerator.letterheadPNG(paperSize: paper, dpi: 144)?.base64EncodedString(), paperSize: paper))
        case "quotations:deliverySchedule":
            respond(id: id, encodable: db.deliverySchedule(quotationId: (payload["id"] as? String) ?? ""))
        case "quotations:deliverySchedulePDF":
            handleExportSchedulePDF(id: id, kind: (payload["kind"] as? String) ?? "Quotation", documentId: (payload["id"] as? String) ?? "",
                                    withInternalNotes: (payload["internal"] as? Bool) ?? false, mode: previewMode(payload))
        case "quotations:addDeliveryDay":
            let error = db.addDeliveryDay(quotationId: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "quotations:updateDeliveryDay":
            let error = db.updateDeliveryDay(id: (payload["id"] as? String) ?? "", payload: payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "quotations:deleteDeliveryDay":
            let error = db.deleteDeliveryDay(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "boq:setLanguage", "deliveryNotes:setLanguage", "quotations:setLanguage":
            let kind = action.hasPrefix("boq") ? "boq" : action.hasPrefix("quotations") ? "quotation" : "dn"
            let error = db.setDocumentLanguage(kind: kind, id: (payload["id"] as? String) ?? "",
                                               language: payload["language"] as? String)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "boq:updateSheetExtras":
            let error = db.updateBOQSheetExtras(id: (payload["id"] as? String) ?? "", payload: payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "boq:updateNotes":
            let boqId = (payload["id"] as? String) ?? ""
            let notes = payload["notes"] as? String
            db.updateBOQNotes(id: boqId, notes: notes)
            respondNull(id: id)
        case "boq:delete":
            let boqId = (payload["id"] as? String) ?? ""
            if let error = db.deleteBOQ(id: boqId, includingIssued: (payload["force"] as? Bool) ?? false) {
                respond(id: id, encodable: BOQActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: BOQActionResult(ok: true, error: nil))
            }

        case "quotations:listForProject":
            let projectId = (payload["projectId"] as? String) ?? ""
            respond(id: id, encodable: db.listQuotationSummaries(projectId: projectId))
        case "quotations:create":
            handleCreateQuotation(id: id, payload: payload)
        case "quotations:duplicate":
            switch db.duplicateQuotation(id: (payload["id"] as? String) ?? "", toProjectId: payload["projectId"] as? String) {
            case .success(let q): respond(id: id, encodable: LeadSaveResult(ok: true, error: nil, id: q.id))
            case .failure(let e): respond(id: id, encodable: LeadSaveResult(ok: false, error: e.message))
            }
        case "quotations:importRead":
            handleImportQuotationRead(id: id, payload: payload)
        case "quotations:importAI":
            handleImportQuotationAI(id: id, payload: payload)
        case "quotations:importCreate":
            handleImportQuotationCreate(id: id, payload: payload)
        case "ai:openKeyPage":
            // Where to get a free key, in the browser.
            let page = (payload["provider"] as? String) == "openrouter" ? "https://openrouter.ai/settings/keys" : "https://aistudio.google.com/apikey"
            if let url = URL(string: page) { NSWorkspace.shared.open(url) }
            respond(id: id, encodable: SimpleResult(ok: true, error: nil))
        case "assistant:send":
            handleAssistantSend(id: id, payload: payload)
        case "assistant:run":
            handleAssistantRun(id: id, payload: payload)
        case "assistant:summarise":
            handleAssistantSummarise(id: id, payload: payload)
        case "assistant:cancel":
            if let run = nonBlank(payload["runId"] as? String) { assistantCancelled.insert(run) }
            respond(id: id, encodable: SimpleResult(ok: true, error: nil))
        case "ai:status":
            respond(id: id, encodable: QuotationAI.shared.status())
        case "ai:configure":
            QuotationAI.shared.configure(provider: (payload["provider"] as? String) ?? "gemini", model: payload["model"] as? String,
                                         key: payload["key"] as? String, removeKey: (payload["removeKey"] as? Bool) ?? false)
            respond(id: id, encodable: QuotationAI.shared.status())
        case "quotations:get":
            let qid = (payload["id"] as? String) ?? ""
            if let detail = db.getQuotationDetail(id: qid) {
                respond(id: id, encodable: detail)
            } else {
                respondNull(id: id)
            }
        case "quotations:addLineItem":
            handleAddQuotationLineItem(id: id, payload: payload)
        case "quotations:updateLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            if payload.keys.contains("priceNote") {
                if let error = db.setQuotationLinePriceNote(id: lineId, note: payload["priceNote"] as? String) {
                    respond(id: id, encodable: QuotationActionResult(ok: false, error: error))
                    return
                }
                // Words only: nothing else to change.
                if payload["appliedUnitPrice"] == nil && payload["quantity"] == nil {
                    respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
                    return
                }
            }
            let quantity = payload["quantity"] as? Double
            let appliedUnitPrice = payload["appliedUnitPrice"] as? Double
            if let error = db.updateQuotationLineItem(id: lineId, quantity: quantity, appliedUnitPrice: appliedUnitPrice,
                                                      description: payload["itemDescription"] as? String, unit: payload["unit"] as? String,
                                                      quantityFormula: payload["quantityFormula"] as? String, priceFormula: payload["priceFormula"] as? String) {
                respond(id: id, encodable: QuotationActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
            }
        case "quotations:removeLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            if let error = db.removeQuotationLineItem(id: lineId) {
                respond(id: id, encodable: QuotationActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
            }
        case "quotations:addBlock":
            switch db.addQuotationBlock(quotationId: (payload["quotationId"] as? String) ?? "", kind: (payload["kind"] as? String) ?? "") {
            case .success: respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
            case .failure(let e): respond(id: id, encodable: QuotationActionResult(ok: false, error: e.message))
            }
        case "quotations:updateBlock":
            let error = db.updateQuotationBlock(id: (payload["id"] as? String) ?? "", payload: payload)
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:moveBlock":
            let error = db.moveQuotationBlock(id: (payload["id"] as? String) ?? "", up: (payload["up"] as? Bool) ?? true)
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:reorderBlocks":
            let error = db.reorderQuotationBlocks(quotationId: (payload["quotationId"] as? String) ?? "", ids: (payload["ids"] as? [String]) ?? [])
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:split":
            var partial: [String: AppDatabase.PartialSplit] = [:]
            for (lineId, value) in (payload["partial"] as? [String: Any]) ?? [:] {
                guard let part = value as? [String: Any], let quantity = (part["quantity"] as? NSNumber)?.doubleValue else { continue }
                let days = ((part["days"] as? [String: Any]) ?? [:]).compactMapValues { ($0 as? NSNumber)?.doubleValue }
                partial[lineId] = AppDatabase.PartialSplit(quantity: quantity, days: days)
            }
            respond(id: id, encodable: db.splitQuotation(id: (payload["id"] as? String) ?? "",
                                                         lineIds: (payload["lineIds"] as? [String]) ?? [],
                                                         blockIds: (payload["blockIds"] as? [String]) ?? [], partial: partial))
        case "quotations:revertSplit":
            respond(id: id, encodable: db.revertQuotationSplit(id: (payload["id"] as? String) ?? ""))
        case "quotations:removeBlock":
            let error = db.removeQuotationBlock(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:addStandardRates":
            let error = db.addStandardManpowerRates(quotationId: (payload["quotationId"] as? String) ?? "", blockId: payload["blockId"] as? String)
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:addBlockLine":
            let error = db.addQuotationBlockLine(
                blockId: (payload["blockId"] as? String) ?? "", description: (payload["description"] as? String) ?? "",
                unit: (payload["unit"] as? String) ?? "", quantity: (payload["quantity"] as? Double) ?? 1,
                price: (payload["price"] as? Double) ?? 0, priceNote: payload["priceNote"] as? String)
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:updateLineDiscount":
            let error = db.updateQuotationLineDiscount(id: (payload["id"] as? String) ?? "", type: payload["discountType"] as? String,
                                                       value: payload["discountValue"] as? Double)
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:updateHeader":
            handleUpdateQuotationHeader(id: id, payload: payload)
        case "quotations:updateLetterFields":
            let error = db.updateQuotationLetterFields(id: (payload["id"] as? String) ?? "", payload: payload)
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:linkBOQ":
            let error = db.linkQuotationToBOQ(quotationId: (payload["quotationId"] as? String) ?? "", boqId: (payload["boqId"] as? String) ?? "")
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:unlinkBOQ":
            let error = db.unlinkQuotationFromBOQ(quotationId: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:copyScheduleFromBOQ":
            let r = db.copyDeliverySchedule(fromBOQ: (payload["boqId"] as? String) ?? "", toQuotation: (payload["quotationId"] as? String) ?? "")
            respond(id: id, encodable: CopyScheduleResult(ok: r.error == nil, error: r.error, skipped: r.skipped))
        case "quotations:importFromBOQ":
            let qid = (payload["quotationId"] as? String) ?? ""
            let boqId = (payload["boqId"] as? String) ?? ""
            let replaceExisting = (payload["replaceExisting"] as? Bool) ?? false
            if let error = db.importBOQIntoQuotation(quotationId: qid, boqId: boqId, replaceExisting: replaceExisting) {
                respond(id: id, encodable: QuotationActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
            }
        case "quotations:updateStatus":
            let qid = (payload["id"] as? String) ?? ""
            let status = (payload["status"] as? String) ?? ""
            if let error = db.updateQuotationStatus(id: qid, status: status) {
                respond(id: id, encodable: QuotationActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
            }
        case "quotations:delete":
            let qid = (payload["id"] as? String) ?? ""
            if let error = db.deleteQuotation(id: qid, includingIssued: (payload["force"] as? Bool) ?? false) {
                respond(id: id, encodable: QuotationActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
            }

        case "invoices:listForProject":
            let projectId = (payload["projectId"] as? String) ?? ""
            respond(id: id, encodable: db.listInvoiceSummaries(projectId: projectId))
        case "invoices:create":
            handleCreateInvoice(id: id, payload: payload)
        case "invoices:get":
            let invId = (payload["id"] as? String) ?? ""
            if let detail = db.getInvoiceDetail(id: invId) {
                respond(id: id, encodable: detail)
            } else {
                respondNull(id: id)
            }
        case "invoices:addLineItem":
            handleAddInvoiceLineItem(id: id, payload: payload)
        case "invoices:updateLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            let quantity = payload["quantity"] as? Double
            let appliedUnitPrice = payload["appliedUnitPrice"] as? Double
            if let error = db.updateInvoiceLineItem(id: lineId, quantity: quantity, appliedUnitPrice: appliedUnitPrice,
                                                    quantityFormula: payload["quantityFormula"] as? String, priceFormula: payload["priceFormula"] as? String) {
                respond(id: id, encodable: InvoiceActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: InvoiceActionResult(ok: true, error: nil))
            }
        case "invoices:removeLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            if let error = db.removeInvoiceLineItem(id: lineId) {
                respond(id: id, encodable: InvoiceActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: InvoiceActionResult(ok: true, error: nil))
            }
        case "invoices:updateLineDiscount":
            let error = db.updateInvoiceLineDiscount(id: (payload["id"] as? String) ?? "", type: payload["discountType"] as? String,
                                                     value: payload["discountValue"] as? Double)
            respond(id: id, encodable: InvoiceActionResult(ok: error == nil, error: error))
        case "invoices:updateRental":
            let error = db.updateInvoiceRental(id: (payload["id"] as? String) ?? "", months: payload["rentalMonths"] as? Int,
                                               period: payload["rentalPeriod"] as? String, updatePeriod: payload.keys.contains("rentalPeriod"))
            respond(id: id, encodable: InvoiceActionResult(ok: error == nil, error: error))
        case "invoices:updateHeader":
            handleUpdateInvoiceHeader(id: id, payload: payload)
        case "invoices:updateStatus":
            let invId = (payload["id"] as? String) ?? ""
            let status = (payload["status"] as? String) ?? ""
            if let error = db.updateInvoiceStatus(id: invId, status: status) {
                respond(id: id, encodable: InvoiceActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: InvoiceActionResult(ok: true, error: nil))
            }
        case "invoices:recordPayment":
            let invId = (payload["id"] as? String) ?? ""
            let amount = (payload["amount"] as? Double) ?? 0
            if let error = db.recordInvoicePayment(id: invId, amount: amount, date: payload["date"] as? String,
                                                   method: payload["method"] as? String, reference: payload["reference"] as? String) {
                respond(id: id, encodable: InvoiceActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: InvoiceActionResult(ok: true, error: nil))
            }
        case "invoices:delete":
            let invId = (payload["id"] as? String) ?? ""
            if let error = db.deleteInvoice(id: invId, includingIssued: (payload["force"] as? Bool) ?? false) {
                respond(id: id, encodable: InvoiceActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: InvoiceActionResult(ok: true, error: nil))
            }
        case "invoices:exportPDF":
            let invId = (payload["id"] as? String) ?? ""
            handleExportInvoicePDF(id: id, invoiceId: invId, mode: previewMode(payload))

        case "deliveryNotes:listForProject":
            let projectId = (payload["projectId"] as? String) ?? ""
            respond(id: id, encodable: db.listDeliveryNoteSummaries(projectId: projectId))
        case "deliveryNotes:create":
            handleCreateDeliveryNote(id: id, payload: payload)
        case "deliveryNotes:get":
            let dnId = (payload["id"] as? String) ?? ""
            if let detail = db.getDeliveryNoteDetail(id: dnId) {
                respond(id: id, encodable: detail)
            } else {
                respondNull(id: id)
            }
        case "deliveryNotes:addLineItem":
            handleAddDeliveryNoteLineItem(id: id, payload: payload)
        case "deliveryNotes:updateLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            let quantity = payload["quantity"] as? Double
            if let error = db.updateDeliveryNoteLineItem(id: lineId, quantity: quantity, quantityFormula: payload["quantityFormula"] as? String) {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: true, error: nil))
            }
        case "lines:editCustom":
            let error = db.editCustomLine(kind: (payload["kind"] as? String) ?? "", id: (payload["id"] as? String) ?? "",
                                          description: (payload["description"] as? String) ?? "", unit: payload["unit"] as? String)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "lines:setQuantities":
            var quantities: [String: Double] = [:]
            for (lineId, value) in (payload["quantities"] as? [String: Any]) ?? [:] {
                if let n = value as? Double { quantities[lineId] = n } else if let n = value as? Int { quantities[lineId] = Double(n) }
            }
            let error = db.setLineQuantities(kind: (payload["kind"] as? String) ?? "", documentId: (payload["documentId"] as? String) ?? "", quantities: quantities)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "deliveryNotes:removeLineItem":
            let lineId = (payload["id"] as? String) ?? ""
            if let error = db.removeDeliveryNoteLineItem(id: lineId) {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: true, error: nil))
            }
        case "deliveryNotes:updateHeader":
            handleUpdateDeliveryNoteHeader(id: id, payload: payload)
        case "deliveryNotes:updateStatus":
            let dnId = (payload["id"] as? String) ?? ""
            let status = (payload["status"] as? String) ?? ""
            if let error = db.updateDeliveryNoteStatus(id: dnId, status: status) {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: true, error: nil))
            }
        case "deliveryNotes:delete":
            let dnId = (payload["id"] as? String) ?? ""
            if let error = db.deleteDeliveryNote(id: dnId, includingIssued: (payload["force"] as? Bool) ?? false) {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: false, error: error))
            } else {
                respond(id: id, encodable: DeliveryNoteActionResult(ok: true, error: nil))
            }
        case "deliveryNotes:exportPDF":
            let dnId = (payload["id"] as? String) ?? ""
            handleExportDeliveryNotePDF(id: id, deliveryNoteId: dnId, mode: previewMode(payload))

        case "stock:data":
            respond(id: id, encodable: db.stockData())
        case "stock:addMovement":
            let error = db.addStockMovement(payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "stock:addMovements":
            respond(id: id, encodable: db.addStockMovements(payload))
        case "stock:returnCheck":
            let error = db.setReturnCheckDate(deliveryNoteId: (payload["deliveryNoteId"] as? String) ?? "", day: payload["date"] as? String)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "stock:deleteBatch":
            let error = db.deleteStockBatch(batchId: (payload["batchId"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "stock:deleteMovement":
            let error = db.deleteStockMovement(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "accounts:data":
            respond(id: id, encodable: db.accountsData())
        case "accounts:saveExpense":
            let error = db.saveExpense(payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "accounts:deleteExpense":
            let error = db.deleteExpense(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "accounts:saveCSV":
            handleSaveAccountsCSV(id: id, payload: payload)
        case "accounts:saveLiability":
            let error = db.saveLiability(payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "accounts:deleteLiability":
            let error = db.deleteLiability(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "accounts:addLiabilityPayment":
            let error = db.addLiabilityPayment(payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "accounts:deleteLiabilityPayment":
            let error = db.deleteLiabilityPayment(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "employees:list":
            respond(id: id, encodable: db.listEmployees())
        case "employees:save":
            let r = db.saveEmployee(payload)
            respond(id: id, encodable: EmployeeActionResult(ok: r.error == nil, error: r.error, id: r.id))
        case "employees:delete":
            let error = db.deleteEmployee(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "employees:recordPayroll":
            respond(id: id, encodable: db.recordPayroll(payload))
        case "boq:updateLineDiscount":
            let error = db.updateBOQLineDiscount(id: (payload["id"] as? String) ?? "", type: payload["discountType"] as? String,
                                                 value: payload["discountValue"] as? Double)
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:setRatesSection":
            var section: BOQRatesSection? = nil
            if let s = payload["section"] as? [String: Any] {
                let rates = ((s["rates"] as? [[String: Any]]) ?? []).map { r in
                    ManpowerRate(name: ((r["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                 rate: max(0, (r["rate"] as? Double) ?? 0),
                                 unit: ((r["unit"] as? String) ?? "md").trimmingCharacters(in: .whitespacesAndNewlines))
                }
                section = BOQRatesSection(title: ((s["title"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                                          rates: rates, note: nonBlank(s["note"] as? String))
            }
            let error = db.setBOQRatesSection(id: (payload["id"] as? String) ?? "", section: section)
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:setCharges":
            var charges: [BOQCharge]? = nil
            if let list = payload["charges"] as? [[String: Any]] {
                charges = list.map { c in
                    BOQCharge(code: nonBlank(c["code"] as? String),
                              name: ((c["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines),
                              amount: doubleOf(roundToCents(decimalOf((c["amount"] as? Double) ?? 0))))
                }
            }
            let error = db.setBOQCharges(id: (payload["id"] as? String) ?? "", charges: charges)
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "costs:manpower":
            respond(id: id, encodable: db.manpowerPage())
        case "costs:saveManpower":
            let error = db.saveManpower(payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "boq:standardRates":
            respond(id: id, encodable: db.getCompanySettings().manpowerRates ?? defaultManpowerRates)
        case "quotations:setOrientation":
            let error = db.setQuotationOrientation(id: (payload["id"] as? String) ?? "", orientation: (payload["orientation"] as? String) ?? "")
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "boq:setOrientation":
            let error = db.setBOQOrientation(id: (payload["id"] as? String) ?? "", orientation: (payload["orientation"] as? String) ?? "")
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:updateDetails":
            let error = db.updateBOQDetails(id: (payload["id"] as? String) ?? "", pricingMode: payload["pricingMode"] as? String,
                                            markupPercent: payload["markupPercent"] as? Double,
                                            structure: payload["structure"] as? String, updateStructure: payload.keys.contains("structure"))
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:moveLineItem":
            let error = db.moveBOQLineItem(id: (payload["id"] as? String) ?? "", direction: (payload["direction"] as? Int) ?? 1)
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:setLineSort":
            let error = db.setBOQLineSort(id: (payload["id"] as? String) ?? "", mode: (payload["mode"] as? String) ?? "code")
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "quotations:setLineSort":
            let error = db.setQuotationLineSort(id: (payload["id"] as? String) ?? "", mode: (payload["mode"] as? String) ?? "code")
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "quotations:reorderLineItems":
            let error = db.reorderQuotationLines(quotationId: (payload["quotationId"] as? String) ?? "", ids: (payload["ids"] as? [String]) ?? [])
            respond(id: id, encodable: QuotationActionResult(ok: error == nil, error: error))
        case "boq:reorderLineItems":
            let error = db.reorderBOQLineItems(boqId: (payload["boqId"] as? String) ?? "", ids: (payload["ids"] as? [String]) ?? [])
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:duplicateLineItem":
            let error = db.duplicateBOQLineItem(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:updateLineNotes":
            let error = db.updateBOQLineNotes(id: (payload["id"] as? String) ?? "", notes: payload["notes"] as? String)
            respond(id: id, encodable: BOQActionResult(ok: error == nil, error: error))
        case "boq:exportPDF":
            let boqId = (payload["id"] as? String) ?? ""
            handleExportBOQPDF(id: id, boqId: boqId, mode: previewMode(payload))
        case "quotations:exportPDF":
            let qid = (payload["id"] as? String) ?? ""
            handleExportQuotationPDF(id: id, quotationId: qid, mode: previewMode(payload),
                                     withSubsidiaries: (payload["withSubsidiaries"] as? Bool) ?? false, subsidiaryIds: payload["subsidiaryIds"] as? [String])
        case "boq:exportWord":
            handleExportBOQPDF(id: id, boqId: (payload["id"] as? String) ?? "", mode: .word)
        case "quotations:exportWord":
            handleExportQuotationPDF(id: id, quotationId: (payload["id"] as? String) ?? "", mode: .word)
        case "invoices:exportWord":
            handleExportInvoicePDF(id: id, invoiceId: (payload["id"] as? String) ?? "", mode: .word)
        case "deliveryNotes:exportWord":
            handleExportDeliveryNotePDF(id: id, deliveryNoteId: (payload["id"] as? String) ?? "", mode: .word)
        case "files:savePreview":
            handleSavePreview(id: id, token: (payload["token"] as? String) ?? "")
        case "files:discardPreview":
            if let p = pendingPreviews.removeValue(forKey: (payload["token"] as? String) ?? "") { try? FileManager.default.removeItem(at: p.url) }
            respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
        case "files:openSaved":
            handleOpenSaved(id: id, path: (payload["path"] as? String) ?? "", reveal: (payload["reveal"] as? Bool) ?? false)
        case "files:saveWord":
            handleSaveWord(id: id, payload: payload)
        case "files:locateDocument":
            handleLocateDocument(id: id, kind: (payload["kind"] as? String) ?? "", documentId: (payload["id"] as? String) ?? "")
        case "boq:print":
            handleExportBOQPDF(id: id, boqId: (payload["id"] as? String) ?? "", mode: .print)
        case "quotations:print":
            handleExportQuotationPDF(id: id, quotationId: (payload["id"] as? String) ?? "", mode: .print,
                                     withSubsidiaries: (payload["withSubsidiaries"] as? Bool) ?? false, subsidiaryIds: payload["subsidiaryIds"] as? [String])
        case "quotations:combinePDF":
            handleCombineDocuments(id: id, kind: "Quotation", ids: (payload["ids"] as? [String]) ?? [], includeDrawings: (payload["includeDrawings"] as? Bool) ?? false, mode: previewMode(payload))
        case "documents:combinePDF":
            handleCombineDocuments(id: id, kind: (payload["kind"] as? String) ?? "Quotation", ids: (payload["ids"] as? [String]) ?? [], includeDrawings: (payload["includeDrawings"] as? Bool) ?? false, mode: previewMode(payload))
        case "files:locateDocuments":
            handleLocateDocuments(id: id, kind: (payload["kind"] as? String) ?? "", ids: (payload["ids"] as? [String]) ?? [])
        case "team:status":
            respond(id: id, encodable: teamStatus())
        case "team:start":
            handleStartTeam(id: id)
        case "team:join":
            handleJoinTeam(id: id)
        case "team:leave":
            TeamSync.setConfiguredFolder(nil)
            respond(id: id, encodable: SimpleResult(ok: true, error: nil))
        case "team:setName":
            let name = ((payload["name"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let sync = TeamSync.current { sync.setMemberName(name) } else { TeamSync.memberName = name }
            respond(id: id, encodable: teamStatus())
        case "inspections:list":
            respond(id: id, encodable: db.listInspections(projectId: (payload["projectId"] as? String) ?? ""))
        case "inspections:save":
            respond(id: id, encodable: db.saveInspection(payload))
        case "inspections:delete":
            let error = db.deleteInspection(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "inspections:due":
            respond(id: id, encodable: db.inspectionsDue(withinDays: payload["withinDays"] as? Int))
        case "tasks:list":
            respond(id: id, encodable: db.listTasks(projectId: payload["projectId"] as? String))
        case "tasks:save":
            respond(id: id, encodable: db.saveTask(payload))
        case "tasks:setDone":
            let error = db.setTaskDone(id: (payload["id"] as? String) ?? "", done: (payload["done"] as? Bool) ?? true)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "tasks:delete":
            let error = db.deleteTask(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "tasks:people":
            respond(id: id, encodable: db.teamNames())
        case "tasks:teams":
            respond(id: id, encodable: TaskForOptions(me: TeamSync.memberName, teams: db.allTeams()))
        case "tasks:get":
            let task = db.tasksStore.readAll().first { $0.id == ((payload["id"] as? String) ?? "") }
            respond(id: id, encodable: task.map { [$0] } ?? [])
        case "calendar:events":
            respond(id: id, encodable: db.calendarEvents(from: (payload["from"] as? String) ?? "", to: (payload["to"] as? String) ?? ""))
        case "marketing:summary":
            respond(id: id, encodable: db.marketingSummary())
        case "marketing:clientReport":
            respond(id: id, encodable: db.clientQuoteReport(clientId: nonBlank(payload["clientId"] as? String),
                                                            from: (payload["from"] as? String) ?? "0000-00-00", to: (payload["to"] as? String) ?? "9999-99-99"))
        case "marketing:clientReportPDF":
            handleClientReportPDF(id: id, payload: payload)
        case "promotions:list":
            respond(id: id, encodable: db.listPromotions())
        case "promotions:save":
            switch db.savePromotion((payload["promotion"] as? [String: Any]) ?? [:]) {
            case .success(let promo):
                struct PromoResult: Encodable { var ok: Bool; var promotion: Promotion }
                respond(id: id, encodable: PromoResult(ok: true, promotion: promo))
            case .failure(let e): respond(id: id, encodable: SimpleResult(ok: false, error: e.message))
            }
        case "promotions:delete":
            let error = db.deletePromotion(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "promotions:writeLetters":
            switch db.writePromotionLetters(promotionId: (payload["id"] as? String) ?? "", targetIds: (payload["targetIds"] as? [String]) ?? []) {
            case .success(let promo):
                struct PromoResult: Encodable { var ok: Bool; var promotion: Promotion }
                respond(id: id, encodable: PromoResult(ok: true, promotion: promo))
            case .failure(let e): respond(id: id, encodable: SimpleResult(ok: false, error: e.message))
            }
        case "marketing:leads":
            respond(id: id, encodable: db.listLeads())
        case "marketing:saveLead":
            respond(id: id, encodable: db.saveLead(payload))
        case "marketing:deleteLead":
            let error = db.deleteLead(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "marketing:convertLead":
            respond(id: id, encodable: db.convertLead(id: (payload["id"] as? String) ?? ""))
        case "documents:chain":
            respond(id: id, encodable: db.documentChain(kind: (payload["kind"] as? String) ?? "", id: (payload["id"] as? String) ?? ""))
        case "users:profiles":
            respond(id: id, encodable: db.userProfiles())
        case "users:page":
            respond(id: id, encodable: db.userPage())
        case "users:setColor":
            let error = db.setUserColor(name: TeamSync.memberName, color: payload["color"] as? String)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "users:setTeam":
            let error = db.setMyTeam(payload["team"] as? String)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "web:status":
            respond(id: id, encodable: WebServer.shared.status())
        case "web:configure":
            let server = WebServer.shared
            if let password = payload["password"] as? String {
                guard password.count >= 6 else { respond(id: id, encodable: SimpleResult(ok: false, error: "Use at least 6 characters for the password.")); return }
                server.setPassword(password)
            }
            if let port = payload["port"] as? Int {
                guard (1024...65535).contains(port) else { respond(id: id, encodable: SimpleResult(ok: false, error: "Choose a port from 1024 to 65535.")); return }
                server.port = port
            }
            if let enabled = payload["enabled"] as? Bool { server.enabled = enabled }
            server.applySettings()
            respond(id: id, encodable: server.status())
        case "web:endSession":
            WebServer.shared.endSessions(startingWith: (payload["token"] as? String) ?? "")
            respond(id: id, encodable: WebServer.shared.status())
        case "team:page":
            respond(id: id, encodable: db.teamPage())
        case "team:setPerson":
            let team: String?? = payload.keys.contains("team") ? .some(payload["team"] as? String) : nil
            let title: String?? = payload.keys.contains("title") ? .some(payload["title"] as? String) : nil
            let idNumber: String?? = payload.keys.contains("idNumber") ? .some(payload["idNumber"] as? String) : nil
            let error = db.setPerson(name: (payload["name"] as? String) ?? "", team: team, title: title, canSign: payload["canSign"] as? Bool,
                                     canSignAgreements: payload["canSignAgreements"] as? Bool, idNumber: idNumber)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "signatures:page":
            respond(id: id, encodable: db.signRequestsPage())
        case "signatures:request":
            let error = db.requestSignature(quotationId: (payload["quotationId"] as? String) ?? "", signer: (payload["signer"] as? String) ?? "", note: payload["note"] as? String)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "signatures:withdraw":
            let error = db.withdrawSignRequest(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "signatures:decline":
            let rid = (payload["id"] as? String) ?? ""
            if let r = db.getSignRequest(id: rid), r.signer.lowercased() != TeamSync.memberName.lowercased() {
                respond(id: id, encodable: SimpleResult(ok: false, error: "Only \(r.signer) can answer this."))
            } else {
                let error = db.finishSignRequest(id: rid, signed: false, filePath: nil, reply: payload["reply"] as? String)
                respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
            }
        case "signatures:sign":
            handleSignQuotation(id: id, requestId: (payload["id"] as? String) ?? "")
        case "signatures:previewSigned":
            // The signed copy as it was saved, for the preview (nothing to save).
            let path = (payload["path"] as? String) ?? ""
            guard fileIsPresent(path), let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
                respond(id: id, encodable: PreviewResult(ok: false, error: "The signed PDF isn’t there any more."))
                break
            }
            let name = URL(fileURLWithPath: path).lastPathComponent
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let drawn = NativeBridge.previewPages(data)
                DispatchQueue.main.async {
                    self?.respond(id: id, encodable: PreviewResult(ok: true, error: nil, token: nil, fileName: name, pages: drawn.pages, pageCount: drawn.count))
                }
            }
        case "signatures:unsign":
            let error = db.withdrawDirectorSignature(quotationId: (payload["quotationId"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "signatures:openFile":
            let path = (payload["path"] as? String) ?? ""
            if fileIsPresent(path) {
                self.openForUser(URL(fileURLWithPath: path))
                respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            } else {
                respond(id: id, encodable: SimpleResult(ok: false, error: "The signed PDF isn’t there any more."))
            }
        case "signatures:chooseImage":
            handleChooseSignatureImage(id: id, which: (payload["which"] as? String) ?? "signature")
        case "signatures:removeImage":
            try? FileManager.default.removeItem(at: db.signatureImageURL(TeamSync.memberName, (payload["which"] as? String) ?? "signature"))
            respond(id: id, encodable: SimpleResult(ok: true, error: nil))
        case "signatures:image":
            struct ImageResult: Encodable { var dataURL: String? }
            let url = db.signatureImageURL(TeamSync.memberName, (payload["which"] as? String) ?? "signature")
            respond(id: id, encodable: ImageResult(dataURL: (try? Data(contentsOf: url)).map { "data:image/png;base64," + $0.base64EncodedString() }))
        case "chat:page":
            respond(id: id, encodable: db.chatPage())
        case "chat:messages":
            struct ChatMessagesResult: Encodable { var messages: [ChatMessage]; var typing: [String] }
            let conversation = (payload["conversation"] as? String) ?? ""
            respond(id: id, encodable: ChatMessagesResult(messages: db.chatMessages(conversation: conversation),
                                                           typing: TeamSync.current?.typing(in: conversation) ?? []))
        case "chat:send":
            TeamSync.current?.setTyping(nil)
            switch db.sendChat(conversation: (payload["conversation"] as? String) ?? "", text: payload["text"] as? String,
                               gifURL: payload["gifURL"] as? String, file: nil, fileName: nil, replyTo: payload["replyTo"] as? String) {
            case .success(let m): respond(id: id, encodable: m)
            case .failure(let e): respond(id: id, encodable: SimpleResult(ok: false, error: e.message))
            }
        case "chat:edit":
            let error = db.editChat(id: (payload["id"] as? String) ?? "", text: payload["text"] as? String, delete: (payload["delete"] as? Bool) ?? false)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "chat:react":
            let error = db.reactChat(id: (payload["id"] as? String) ?? "", emoji: (payload["emoji"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "chat:typing":
            let conversation = payload["conversation"] as? String
            if let c = conversation, db.chatAllowed(c, for: TeamSync.memberName) { TeamSync.current?.setTyping(c) } else { TeamSync.current?.setTyping(nil) }
            respond(id: id, encodable: SimpleResult(ok: true, error: nil))
        case "chat:attach":
            handleChatAttach(id: id, conversation: (payload["conversation"] as? String) ?? "")
        case "chat:file":
            struct ChatFile: Encodable { var dataURL: String? }
            let name = ((payload["file"] as? String) ?? "").replacingOccurrences(of: "/", with: "")
            let url = db.chatFilesFolder.appendingPathComponent(name)
            let type = url.pathExtension.lowercased() == "gif" ? "image/gif" : url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
            respond(id: id, encodable: ChatFile(dataURL: name.isEmpty ? nil : (try? Data(contentsOf: url)).map { "data:\(type);base64," + $0.base64EncodedString() }))
        case "chat:setGifKey":
            var settings = db.getCompanySettings()
            settings.giphyKey = nonBlank(payload["key"] as? String)
            db.saveCompanySettingsDirect(settings)
            respond(id: id, encodable: SimpleResult(ok: true, error: nil))
        case "announcements:page":
            respond(id: id, encodable: db.announcementsPage())
        case "announcements:post":
            let error = db.postAnnouncement(payload)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "announcements:dismiss":
            let error = db.dismissAnnouncement(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "announcements:delete":
            let error = db.deleteAnnouncement(id: (payload["id"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "users:setName":
            let error = db.renameUser(to: (payload["name"] as? String) ?? "")
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "team:reveal":
            if let folder = TeamSync.current?.root ?? TeamSync.configuredFolder, FileManager.default.fileExists(atPath: folder.path) {
                self.revealForUser([folder])
                respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            } else {
                respond(id: id, encodable: SimpleResult(ok: false, error: "The shared folder can't be found."))
            }
        case "app:updates":
            // Settings › Updates: { automatic? } changes the setting; "check" checks now.
            if let auto = payload["automatic"] as? Bool { AppDelegate.autoUpdate = auto }
            if payload.keys.contains("token") { GitHubToken.set(payload["token"] as? String) }
            if (payload["check"] as? Bool) == true { (NSApp.delegate as? AppDelegate)?.checkForUpdates(manual: true) }
            respond(id: id, encodable: ["automatic": AppDelegate.autoUpdate, "hasToken": GitHubToken.get() != nil])
        case "app:relaunch":
            respondNull(id: id)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { relaunchApp() }
        case "quotations:uploadSigned":
            handleUploadSignedQuotation(id: id, quotationId: (payload["id"] as? String) ?? "")
        case "quotations:saveSignedFile":
            handleSaveSignedQuotationData(id: id, payload: payload)
        case "quotations:signedCopy":
            handleSignedCopyAction(id: id, quotationId: (payload["id"] as? String) ?? "", action: (payload["action"] as? String) ?? "")
        case "deliveryNotes:uploadSigned":
            handleUploadSignedDeliveryNote(id: id, noteId: (payload["id"] as? String) ?? "")
        case "deliveryNotes:saveSignedFile":
            let fileName = (payload["fileName"] as? String) ?? ""
            if let base64 = payload["base64"] as? String, let data = Data(base64Encoded: base64), !data.isEmpty {
                respond(id: id, encodable: storeSignedCopy(kind: "deliveryNote", documentId: (payload["id"] as? String) ?? "", fileName: fileName) {
                    try data.write(to: $0, options: .atomic)
                })
            } else {
                respond(id: id, encodable: SimpleResult(ok: false, error: "That file couldn't be read."))
            }
        case "deliveryNotes:signedCopy":
            handleDeliveryNoteSignedAction(id: id, noteId: (payload["id"] as? String) ?? "", action: (payload["action"] as? String) ?? "")
        case "quotations:setClientAgreed":
            let error = db.setQuotationClientAgreed(id: (payload["id"] as? String) ?? "", agreed: (payload["agreed"] as? Bool) ?? true)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "quotations:setSignedNotNeeded":
            let error = db.setQuotationSignedCopyNotNeeded(id: (payload["id"] as? String) ?? "", notNeeded: (payload["notNeeded"] as? Bool) ?? true)
            respond(id: id, encodable: SimpleResult(ok: error == nil, error: error))
        case "invoices:print":
            handleExportInvoicePDF(id: id, invoiceId: (payload["id"] as? String) ?? "", mode: .print)
        case "deliveryNotes:print":
            handleExportDeliveryNotePDF(id: id, deliveryNoteId: (payload["id"] as? String) ?? "", mode: .print)

        case "settings:get":
            // Light / Dark is each person's own, not the company's.
            var current = db.getCompanySettings()
            current.appearance = ownAppearance()
            current.buyBackWording = current.buyBackWording ?? BuyBackTerms.defaultWording
            current.aiKey = nil
            respond(id: id, encodable: current)
        case "settings:update":
            // Appearance is the person's own; everything else is the company's.
            var changes = payload
            if let look = changes.removeValue(forKey: "appearance") as? String, ["System", "Light", "Dark"].contains(look) {
                db.setUserAppearance(name: TeamSync.memberName, appearance: look)
                // Someone in ScaffoldPro Web doesn't change this Mac's look.
                if TeamSync.actingAs == nil { applyAppearance(look) }
            }
            var updated = db.updateCompanySettings(changes)
            updated.appearance = ownAppearance()
            updated.buyBackWording = updated.buyBackWording ?? BuyBackTerms.defaultWording
            updated.aiKey = nil
            respond(id: id, encodable: updated)
        case "settings:chooseLogo":
            handleChooseLogo(id: id)
        case "settings:removeLogo":
            db.setLogoPath(nil)
            respond(id: id, encodable: SimpleResult(ok: true, error: nil))
        case "settings:logoPreview":
            // The page can't read ~/Documents directly, so the logo comes
            // across as a data: URL.
            if let path = db.getCompanySettings().logoPath, let data = FileManager.default.contents(atPath: path) {
                let ext = URL(fileURLWithPath: path).pathExtension.lowercased()
                let mime = ext == "png" ? "image/png" : ext == "tiff" || ext == "tif" ? "image/tiff" : "image/jpeg"
                respond(id: id, encodable: ["dataURL": "data:\(mime);base64,\(data.base64EncodedString())"])
            } else {
                respondNull(id: id)
            }
        case "settings:numberPreview":
            let template = (payload["template"] as? String) ?? ""
            respond(id: id, encodable: ["example": nextDocumentNumber(template: template.isEmpty ? (defaultNumberFormats[(payload["type"] as? String) ?? "QT"] ?? "{PROJECT}-{SEQ}") : template, projectNumber: nextProjectNumber(existingNumbers: db.allProjectNumbers()), existing: [])])

        case "drawings:listForProject":
            let projectId = (payload["projectId"] as? String) ?? ""
            respond(id: id, encodable: db.listDrawings(projectId: projectId))
        case "drawings:updateDescription":
            let drawingId = (payload["id"] as? String) ?? ""
            let description = payload["description"] as? String
            let error = db.updateDrawingDescription(id: drawingId, description: description)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "drawings:rename":
            let drawingId = (payload["id"] as? String) ?? ""
            let newName = (payload["newName"] as? String) ?? ""
            let error = db.renameDrawing(id: drawingId, newDisplayName: newName)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "drawings:archive":
            let drawingId = (payload["id"] as? String) ?? ""
            let error = db.archiveDrawing(id: drawingId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "drawings:removeReference":
            let drawingId = (payload["id"] as? String) ?? ""
            let error = db.removeDrawingReference(id: drawingId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "drawings:relink":
            let drawingId = (payload["id"] as? String) ?? ""
            handleRelinkFile(id: id, recordId: drawingId, target: .drawing)
        case "drawings:replace":
            handleReplaceFile(id: id, recordId: (payload["id"] as? String) ?? "", isDrawing: true)
        case "documents:replace":
            handleReplaceFile(id: id, recordId: (payload["id"] as? String) ?? "", isDrawing: false)
        case "drawings:open":
            let drawingId = (payload["id"] as? String) ?? ""
            if let drawing = db.getDrawing(id: drawingId) {
                handleOpenFile(id: id, path: drawing.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Drawing not found."))
            }
        case "drawings:reveal":
            let drawingId = (payload["id"] as? String) ?? ""
            if let drawing = db.getDrawing(id: drawingId) {
                handleRevealFile(id: id, path: drawing.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Drawing not found."))
            }

        case let route where route.hasPrefix("workerAgreements:"):
            handleWorkerAgreement(id: id, action: String(route.dropFirst("workerAgreements:".count)), payload: payload)
        case "workers:roster":
            respond(id: id, encodable: db.workerRoster(includeArchived: (payload["includeArchived"] as? Bool) ?? false))
        case "workers:list":
            let includeArchived = (payload["includeArchived"] as? Bool) ?? false
            respond(id: id, encodable: db.listWorkers(includeArchived: includeArchived))
        case "workers:create":
            switch db.createWorker(payload) {
            case .success(let worker):
                try? FileManager.default.createDirectory(at: storage.workerFolder(worker.workerNumber), withIntermediateDirectories: true)
                // Their employment agreement, ready to print and sign.
                db.createWorkerAgreement(for: worker)
                respond(id: id, encodable: WorkerActionResult(ok: true, error: nil, worker: worker))
            case .failure(let err):
                respond(id: id, encodable: WorkerActionResult(ok: false, error: err.message, worker: nil))
            }
        case "workers:update":
            let workerId = (payload["id"] as? String) ?? ""
            let error = db.updateWorker(id: workerId, payload: payload)
            respond(id: id, encodable: WorkerActionResult(ok: error == nil, error: error, worker: nil))
        case "workers:setArchived":
            let workerId = (payload["id"] as? String) ?? ""
            let archived = (payload["archived"] as? Bool) ?? true
            let error = db.setWorkerArchived(id: workerId, archived: archived)
            respond(id: id, encodable: WorkerActionResult(ok: error == nil, error: error, worker: nil))
        case "workers:revealFolder":
            let workerId = (payload["id"] as? String) ?? ""
            if let worker = db.getWorker(id: workerId) {
                let folder = storage.workerFolder(worker.workerNumber)
                try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                self.revealOne(folder)
            }
            respondNull(id: id)

        case "workerDocuments:list":
            let workerId = (payload["workerId"] as? String) ?? ""
            respond(id: id, encodable: db.listWorkerDocuments(workerId: workerId))
        case "workerDocuments:upload":
            let workerId = (payload["workerId"] as? String) ?? ""
            let category = (payload["category"] as? String) ?? "Other"
            let expiryDate = payload["expiryDate"] as? String
            handleUploadWorkerDocument(id: id, workerId: workerId, category: category, expiryDate: (expiryDate?.isEmpty ?? true) ? nil : expiryDate)
        case "workerDocuments:update":
            let docId = (payload["id"] as? String) ?? ""
            let description = payload["description"] as? String
            let expiryDate = payload["expiryDate"] as? String
            let error = db.updateWorkerDocument(id: docId, description: description, expiryDate: (expiryDate?.isEmpty ?? true) ? nil : expiryDate)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "workerDocuments:archive":
            let docId = (payload["id"] as? String) ?? ""
            let error = db.archiveWorkerDocument(id: docId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "workerDocuments:removeReference":
            let docId = (payload["id"] as? String) ?? ""
            let error = db.removeWorkerDocumentReference(id: docId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "workerDocuments:relink":
            let docId = (payload["id"] as? String) ?? ""
            handleRelinkFile(id: id, recordId: docId, target: .workerDocument)
        case "workerDocuments:open":
            let docId = (payload["id"] as? String) ?? ""
            if let doc = db.getWorkerDocument(id: docId) {
                handleOpenFile(id: id, path: doc.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Document not found."))
            }
        case "workerDocuments:reveal":
            let docId = (payload["id"] as? String) ?? ""
            if let doc = db.getWorkerDocument(id: docId) {
                handleRevealFile(id: id, path: doc.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Document not found."))
            }

        case "adminDocuments:list":
            respond(id: id, encodable: db.listAdminDocuments())
        case "adminDocuments:upload":
            let category = (payload["category"] as? String) ?? "Other"
            let expiryDate = payload["expiryDate"] as? String
            handleUploadAdminDocument(id: id, category: category, expiryDate: (expiryDate?.isEmpty ?? true) ? nil : expiryDate)
        case "adminDocuments:update":
            let docId = (payload["id"] as? String) ?? ""
            let description = payload["description"] as? String
            let expiryDate = payload["expiryDate"] as? String
            let error = db.updateAdminDocument(id: docId, description: description, expiryDate: (expiryDate?.isEmpty ?? true) ? nil : expiryDate)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "adminDocuments:archive":
            let docId = (payload["id"] as? String) ?? ""
            let error = db.archiveAdminDocument(id: docId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "adminDocuments:removeReference":
            let docId = (payload["id"] as? String) ?? ""
            let error = db.removeAdminDocumentReference(id: docId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "adminDocuments:relink":
            let docId = (payload["id"] as? String) ?? ""
            handleRelinkFile(id: id, recordId: docId, target: .adminDocument)
        case "adminDocuments:open":
            let docId = (payload["id"] as? String) ?? ""
            if let doc = db.getAdminDocument(id: docId) {
                handleOpenFile(id: id, path: doc.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Document not found."))
            }
        case "adminDocuments:reveal":
            let docId = (payload["id"] as? String) ?? ""
            if let doc = db.getAdminDocument(id: docId) {
                handleRevealFile(id: id, path: doc.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Document not found."))
            }
        case "adminDocuments:expiring":
            let days = (payload["days"] as? Int) ?? 30
            respond(id: id, encodable: db.expiringDocuments(withinDays: days))

        case "backup:autoStatus":
            respond(id: id, encodable: autoBackupStatus())
        case "backup:localCopyNow":
            localCopy.copyNow { [weak self] _ in
                guard let self = self else { return }
                self.respond(id: id, encodable: self.autoBackupStatus())
            }
        case "backup:revealLocalCopy":
            NSWorkspace.shared.activateFileViewerSelecting([localCopy.target])
            respond(id: id, encodable: QuotationActionResult(ok: true, error: nil))
        case "backup:list":
            respond(id: id, encodable: backups.listBackups())
        case "backup:locations":
            respond(id: id, encodable: DataLocations(
                documentsFolder: storage.appRoot.path,
                backupsFolder: storage.backupsRoot.path,
                databaseFolder: db.dataDir.path
            ))
        case "sheets:status":
            respond(id: id, encodable: sheets.status())
        case "sheets:link":
            sheets.link(url: (payload["url"] as? String) ?? "", secret: (payload["secret"] as? String) ?? "") { [weak self] result in
                self?.respond(id: id, encodable: result)
            }
        case "sheets:unlink":
            sheets.unlink()
            respond(id: id, encodable: sheets.status())
        case "sheets:syncNow":
            sheets.syncNow(refreshScript: true) { [weak self] status in self?.respond(id: id, encodable: status) }
        case "sheets:copyScript":
            if var script = GoogleSheetsSync.script() {
                // The connected sheet's link filled in, for a script made at script.google.com.
                if let link = sheets.status().sheetURL, link.hasPrefix("https://docs.google.com/"),
                   let r = script.range(of: #"const SHEET_URL = '[^'\n]*';"#, options: .regularExpression) {
                    script.replaceSubrange(r, with: "const SHEET_URL = '\(link.replacingOccurrences(of: "'", with: ""))';")
                }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(script, forType: .string)
                respond(id: id, encodable: SimpleResult(ok: true, error: nil))
            } else {
                respond(id: id, encodable: SimpleResult(ok: false, error: "The script wasn’t found in ScaffoldPro’s files."))
            }
        case "sheets:openSheet":
            if let link = sheets.status().sheetURL, let url = URL(string: link) { NSWorkspace.shared.open(url) }
            respond(id: id, encodable: SimpleResult(ok: true, error: nil))
        case "cloudBackup:status":
            respond(id: id, encodable: cloudBackup.status())
        case "cloudBackup:setEnabled":
            cloudBackup.enabled = (payload["enabled"] as? Bool) ?? true
            if cloudBackup.enabled { cloudBackup.schedule(after: 1) }
            respond(id: id, encodable: cloudBackup.status())
        case "cloudBackup:backUpNow":
            cloudBackup.backUpNow { [weak self] status in self?.respond(id: id, encodable: status) }
        case "cloudBackup:useDefaultFolder":
            cloudBackup.setFolder(nil)
            cloudBackup.schedule(after: 1)
            respond(id: id, encodable: cloudBackup.status())
        case "cloudBackup:chooseFolder":
            handleChooseCloudFolder(id: id)
        case "cloudBackup:reveal":
            let fm = FileManager.default
            let target = [cloudBackup.folder, CloudBackupManager.iCloudDrive].first { fm.fileExists(atPath: $0.path) }
            if let target = target { self.revealOne(target) }
            respond(id: id, encodable: SimpleResult(ok: target != nil, error: target == nil ? "iCloud Drive wasn't found on this Mac." : nil))
        case "backup:create":
            handleCreateBackup(id: id)
        case "backup:restore":
            let path = (payload["path"] as? String) ?? ""
            handleRestore(id: id, from: URL(fileURLWithPath: path, isDirectory: true))
        case "backup:chooseAndRestore":
            handleChooseAndRestore(id: id)
        case "backup:reveal":
            let path = (payload["path"] as? String) ?? ""
            let url = path.isEmpty ? storage.backupsRoot : URL(fileURLWithPath: path, isDirectory: true)
            try? FileManager.default.createDirectory(at: storage.backupsRoot, withIntermediateDirectories: true)
            self.revealOne(url)
            respondNull(id: id)
        case "backup:revealDataFolder":
            try? FileManager.default.createDirectory(at: storage.appRoot, withIntermediateDirectories: true)
            self.revealOne(storage.appRoot)
            respondNull(id: id)

        case "documents:listForProject":
            let projectId = (payload["projectId"] as? String) ?? ""
            respond(id: id, encodable: db.listDocuments(projectId: projectId))
        case "documents:upload":
            let number = (payload["projectNumber"] as? String) ?? ""
            let category = (payload["category"] as? String) ?? "Miscellaneous"
            handleUploadDocument(id: id, projectNumber: number, category: category)
        case "documents:updateDescription":
            let documentId = (payload["id"] as? String) ?? ""
            let description = payload["description"] as? String
            let error = db.updateDocumentDescription(id: documentId, description: description)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "documents:rename":
            let documentId = (payload["id"] as? String) ?? ""
            let newName = (payload["newName"] as? String) ?? ""
            let error = db.renameDocument(id: documentId, newDisplayName: newName)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "documents:archive":
            let documentId = (payload["id"] as? String) ?? ""
            let error = db.archiveDocument(id: documentId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "documents:removeReference":
            let documentId = (payload["id"] as? String) ?? ""
            let error = db.removeDocumentReference(id: documentId)
            respond(id: id, encodable: FileActionResult(ok: error == nil, error: error))
        case "documents:relink":
            let documentId = (payload["id"] as? String) ?? ""
            handleRelinkFile(id: id, recordId: documentId, target: .document)
        case "documents:open":
            let documentId = (payload["id"] as? String) ?? ""
            if let document = db.getDocument(id: documentId) {
                handleOpenFile(id: id, path: document.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Document not found."))
            }
        case "documents:reveal":
            let documentId = (payload["id"] as? String) ?? ""
            if let document = db.getDocument(id: documentId) {
                handleRevealFile(id: id, path: document.filePath)
            } else {
                respond(id: id, encodable: FileActionResult(ok: false, error: "Document not found."))
            }

        default:
            respondError(id: id, message: "Unknown action: \(action)")
        }
    }

    func handleCreateBOQ(id: String, payload: [String: Any]) {
        let projectId = (payload["projectId"] as? String) ?? ""
        let projectNumber = (payload["projectNumber"] as? String) ?? ""
        let pricingMode = (payload["pricingMode"] as? String) ?? "Rental"
        guard !projectId.isEmpty, !projectNumber.isEmpty else {
            respondError(id: id, message: "Missing project.")
            return
        }
        let boq = db.createBOQ(projectId: projectId, projectNumber: projectNumber, pricingMode: pricingMode)
        respond(id: id, encodable: boq)
    }

    func handleAddBOQLineItem(id: String, payload: [String: Any]) {
        let boqId = (payload["boqId"] as? String) ?? ""
        let sourceKey = payload["sourceKey"] as? String
        let priceListItemId = payload["priceListItemId"] as? String
        let itemCode = (payload["itemCode"] as? String) ?? ""
        let description = (payload["description"] as? String) ?? ""
        let unit = (payload["unit"] as? String) ?? "pc"
        let quantity = (payload["quantity"] as? Double) ?? 1
        let priceListUnitPrice = payload["priceListUnitPrice"] as? Double
        let appliedUnitPrice = (payload["appliedUnitPrice"] as? Double) ?? (priceListUnitPrice ?? 0)
        var weightKg = payload["weightKg"] as? Double
        let section = payload["section"] as? String
        var priceListUnitPriceFinal = priceListUnitPrice
        var appliedUnitPriceFinal = appliedUnitPrice
        // Items picked from the Material List are priced here, consistently:
        // this BOQ's Sale/Rental mode, its mark-up, converted to HKD.
        if let plId = priceListItemId, let pl = db.priceListItem(id: plId), let boq = db.getBOQ(id: boqId),
           let price = db.boqPrice(for: pl, mode: boq.pricingMode, markupPercent: boq.markupOnRates == true ? 0 : (boq.markupPercent ?? 0), rates: db.conversionRates()) {
            priceListUnitPriceFinal = price
            appliedUnitPriceFinal = price
            if weightKg == nil { weightKg = pl.weightKg }
        }

        guard !description.isEmpty else {
            respond(id: id, encodable: BOQActionResult(ok: false, error: "Description is required."))
            return
        }
        guard quantity > 0 else {
            respond(id: id, encodable: BOQActionResult(ok: false, error: "Quantity must be greater than zero."))
            return
        }

        if let error = db.addBOQLineItem(
            boqId: boqId, sourceKey: sourceKey, priceListItemId: priceListItemId,
            itemCode: itemCode, description: description, unit: unit, quantity: quantity,
            priceListUnitPrice: priceListUnitPriceFinal, appliedUnitPrice: appliedUnitPriceFinal, weightKg: weightKg, section: section
        ) {
            respond(id: id, encodable: BOQActionResult(ok: false, error: error))
        } else {
            respond(id: id, encodable: BOQActionResult(ok: true, error: nil))
        }
    }

    func handleUpdatePriceListItem(id: String, payload: [String: Any]) {
        let itemId = (payload["id"] as? String) ?? ""
        let itemName = (payload["itemName"] as? String) ?? ""
        let category = payload["category"] as? String
        let unit = (payload["unit"] as? String) ?? ""
        let unitSalePrice = payload["unitSalePrice"] as? Double
        let unitRentalPrice = payload["unitRentalPrice"] as? Double

        if let error = db.updatePriceListItem(id: itemId, itemName: itemName, category: category, unit: unit, unitSalePrice: unitSalePrice, unitRentalPrice: unitRentalPrice,
                                              weightKg: payload["weightKg"] as? Double, updateWeight: payload.keys.contains("weightKg"),
                                              chineseName: payload["chineseName"] as? String) {
            respond(id: id, encodable: PriceListItemActionResult(ok: false, error: error))
        } else {
            respond(id: id, encodable: PriceListItemActionResult(ok: true, error: nil))
        }
    }

    func handleCreateQuotation(id: String, payload: [String: Any]) {
        let projectId = (payload["projectId"] as? String) ?? ""
        let projectNumber = (payload["projectNumber"] as? String) ?? ""
        let sourceBOQId = payload["boqId"] as? String
        let pricingMode = (payload["pricingMode"] as? String) ?? "Rental"
        guard !projectId.isEmpty, !projectNumber.isEmpty else {
            respondError(id: id, message: "Missing project.")
            return
        }
        let quotation = db.createQuotation(projectId: projectId, projectNumber: projectNumber, sourceBOQId: sourceBOQId, pricingMode: pricingMode)
        respond(id: id, encodable: quotation)
    }
}

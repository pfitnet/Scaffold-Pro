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
// MARK: - Database facade (mirrors the rest of db.js)
// =====================================================================

final class AppDatabase {
    /// Folder holding every *.json store — what Backup copies and Restore
    /// replaces.
    let dataDir: URL

    let clientsStore: JSONStore<Client>
    let sitesStore: JSONStore<Site>
    let projectsStore: JSONStore<Project>
    let priceListsStore: JSONStore<PriceList>
    let priceListItemsStore: JSONStore<PriceListItem>
    let boqsStore: JSONStore<BillOfQuantities>
    let boqLineItemsStore: JSONStore<BOQLineItem>
    let quotationsStore: JSONStore<Quotation>
    let quotationLineItemsStore: JSONStore<QuotationLineItem>
    let quotationBlocksStore: JSONStore<QuotationBlock>
    let invoicesStore: JSONStore<Invoice>
    let invoiceLineItemsStore: JSONStore<InvoiceLineItem>
    let deliveryNotesStore: JSONStore<DeliveryNote>
    let deliveryNoteLineItemsStore: JSONStore<DeliveryNoteLineItem>
    let settingsStore: JSONStore<CompanySettings>
    let drawingsStore: JSONStore<ProjectDrawing>
    let documentsStore: JSONStore<ProjectDocument>
    let workersStore: JSONStore<Worker>
    let workerDocumentsStore: JSONStore<WorkerDocument>
    let workerAgreementsStore: JSONStore<WorkerAgreement>
    let adminDocumentsStore: JSONStore<AdminDocument>
    let activityStore: JSONStore<ActivityEntry>
    let stockMovementsStore: JSONStore<StockMovement>
    let invoicePaymentsStore: JSONStore<InvoicePayment>
    let expensesStore: JSONStore<Expense>
    let liabilitiesStore: JSONStore<Liability>
    let quotationDeliveriesStore: JSONStore<QuotationDeliveryDay>
    let lettersStore: JSONStore<Letter>
    let userProfilesStore: JSONStore<UserProfile>
    let leadsStore: JSONStore<Lead>
    let inspectionsStore: JSONStore<ScaffoldInspection>
    let tasksStore: JSONStore<TeamTask>
    let liabilityPaymentsStore: JSONStore<LiabilityPayment>
    let employeesStore: JSONStore<Employee>
    let teamMembershipsStore: JSONStore<TeamMembership>
    let announcementsStore: JSONStore<Announcement>
    let signRequestsStore: JSONStore<SignRequest>
    let chatStore: JSONStore<ChatMessage>
    let promotionsStore: JSONStore<Promotion>

    init(dataDir: URL) {
        self.dataDir = dataDir
        clientsStore = JSONStore(fileURL: dataDir.appendingPathComponent("clients.json"))
        sitesStore = JSONStore(fileURL: dataDir.appendingPathComponent("sites.json"))
        projectsStore = JSONStore(fileURL: dataDir.appendingPathComponent("projects.json"))
        priceListsStore = JSONStore(fileURL: dataDir.appendingPathComponent("price_lists.json"))
        priceListItemsStore = JSONStore(fileURL: dataDir.appendingPathComponent("price_list_items.json"))
        boqsStore = JSONStore(fileURL: dataDir.appendingPathComponent("boqs.json"))
        boqLineItemsStore = JSONStore(fileURL: dataDir.appendingPathComponent("boq_line_items.json"))
        quotationsStore = JSONStore(fileURL: dataDir.appendingPathComponent("quotations.json"))
        quotationLineItemsStore = JSONStore(fileURL: dataDir.appendingPathComponent("quotation_line_items.json"))
        quotationBlocksStore = JSONStore(fileURL: dataDir.appendingPathComponent("quotation_blocks.json"))
        invoicesStore = JSONStore(fileURL: dataDir.appendingPathComponent("invoices.json"))
        invoiceLineItemsStore = JSONStore(fileURL: dataDir.appendingPathComponent("invoice_line_items.json"))
        deliveryNotesStore = JSONStore(fileURL: dataDir.appendingPathComponent("delivery_notes.json"))
        deliveryNoteLineItemsStore = JSONStore(fileURL: dataDir.appendingPathComponent("delivery_note_line_items.json"))
        settingsStore = JSONStore(fileURL: dataDir.appendingPathComponent("settings.json"))
        drawingsStore = JSONStore(fileURL: dataDir.appendingPathComponent("drawings.json"))
        documentsStore = JSONStore(fileURL: dataDir.appendingPathComponent("documents.json"))
        workersStore = JSONStore(fileURL: dataDir.appendingPathComponent("workers.json"))
        workerDocumentsStore = JSONStore(fileURL: dataDir.appendingPathComponent("worker_documents.json"))
        workerAgreementsStore = JSONStore(fileURL: dataDir.appendingPathComponent("worker_agreements.json"))
        adminDocumentsStore = JSONStore(fileURL: dataDir.appendingPathComponent("admin_documents.json"))
        activityStore = JSONStore(fileURL: dataDir.appendingPathComponent("activity.json"))
        stockMovementsStore = JSONStore(fileURL: dataDir.appendingPathComponent("stock_movements.json"))
        invoicePaymentsStore = JSONStore(fileURL: dataDir.appendingPathComponent("invoice_payments.json"))
        expensesStore = JSONStore(fileURL: dataDir.appendingPathComponent("expenses.json"))
        liabilitiesStore = JSONStore(fileURL: dataDir.appendingPathComponent("liabilities.json"))
        quotationDeliveriesStore = JSONStore(fileURL: dataDir.appendingPathComponent("quotation_deliveries.json"))
        lettersStore = JSONStore(fileURL: dataDir.appendingPathComponent("letters.json"))
        userProfilesStore = JSONStore(fileURL: dataDir.appendingPathComponent("user_profiles.json"))
        leadsStore = JSONStore(fileURL: dataDir.appendingPathComponent("leads.json"))
        inspectionsStore = JSONStore(fileURL: dataDir.appendingPathComponent("scaffold_inspections.json"))
        tasksStore = JSONStore(fileURL: dataDir.appendingPathComponent("tasks.json"))
        liabilityPaymentsStore = JSONStore(fileURL: dataDir.appendingPathComponent("liability_payments.json"))
        employeesStore = JSONStore(fileURL: dataDir.appendingPathComponent("employees.json"))
        teamMembershipsStore = JSONStore(fileURL: dataDir.appendingPathComponent("user_teams.json"))
        announcementsStore = JSONStore(fileURL: dataDir.appendingPathComponent("announcements.json"))
        signRequestsStore = JSONStore(fileURL: dataDir.appendingPathComponent("sign_requests.json"))
        chatStore = JSONStore(fileURL: dataDir.appendingPathComponent("chat_messages.json"))
        promotionsStore = JSONStore(fileURL: dataDir.appendingPathComponent("promotions.json"))
    }
}

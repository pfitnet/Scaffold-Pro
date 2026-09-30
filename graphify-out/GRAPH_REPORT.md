# Graph Report - Scaffold-Pro  (2026-09-30)

## Corpus Check
- 65 files · ~159,524 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 15 file(s) not represented in the graph (top: .ttf 6, (none) 3, .plist 2)

## Summary
- 1437 nodes · 5343 edges · 67 communities (56 shown, 11 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 170 edges (avg confidence: 0.83)
- Token cost: 422,822 input · 0 output

## Community Hubs (Navigation)
- PDF Drawing Primitives
- Database Queries & Archiving
- App Delegate & Menus
- Team Sync & XLSX Parsing
- Swift Models & Architecture
- Database Creation & Clients
- Native Bridge Handlers
- Project Detail Page
- Installer Window
- PDF Preview Renderer
- Activity, Stock & Delivery
- Word Export
- Quotation Editor
- Settings Page
- File Storage & Seeding
- Pricing & Markup Math
- Letter Formatting
- Accounts Page
- Stock Page
- Reference Docs & Audit
- BOQ/Quotation Line Items
- Admin Page
- Preview Document Builders
- Local Backups
- Invoice Editor
- App Icon Generator
- Sheet Layout & PDF Pages
- Editor Pages & Shared Scripts
- BOQ Editor
- Draft Quotations & Price Items
- Price Lists Page
- Projects & Dates
- Sidebar
- Preview Sheet Layout
- Delivery Note Editor
- Paragraph Formatting
- iCloud Backup
- Sample Quotation Page 2
- JSON Store
- Sample Quotation Page 1
- PDF Export Handlers
- Price Import & Relinking
- Bridge & Install Script
- Dashboard
- Signed Copy Upload
- Accounts Data
- Invoice & Delivery Line Items
- Price Sheet Interpreter
- Party Page Helper
- Line Discount
- Admin & Worker Documents
- Drawings & Quotation Lines
- Logo SVG
- Installer Steps Script
- Projects Page
- Locate & Open Files
- List Pages
- Icon Preview Sheet
- Worksheet Parser
- Preview Signatures & Footer
- App Icon 1024
- Document Selection
- SVG Icons
- graphify Instructions
- Password Prompt
- Repo README

## God Nodes (most connected - your core abstractions)
1. `AppDatabase` - 261 edges
2. `NativeBridge` - 99 edges
3. `PDFGenerator` - 74 edges
4. `nowISO()` - 50 edges
5. `TeamSync` - 46 edges
6. `Gen` - 43 edges
7. `nonBlank()` - 34 edges
8. `AppDelegate` - 34 edges
9. `Updater` - 33 edges
10. `InstallerController` - 32 edges

## Surprising Connections (you probably didn't know these)
- `Share with Other Macs (iCloud change logs)` --shares_data_with--> `JSONStore`  [INFERRED]
  ScaffoldPro-native/README.md → ScaffoldPro-native/main.swift
- `Letterhead layout (from sample quotation Qt26193)` --shares_data_with--> `PDFGenerator`  [INFERRED]
  ScaffoldPro-native/AUDIT.md → ScaffoldPro-native/main.swift
- `PDFGenerator` --shares_data_with--> `Quotation (standard Qt26193 style)`  [INFERRED]
  ScaffoldPro-native/main.swift → ScaffoldPro-native/README.md
- `BQ sheet landscape (with prices) / portrait (no prices)` --references--> `BQ-CRBC-1635 PROFICIENCY QUOTATION sheet (A4 landscape)`  [EXTRACTED]
  ScaffoldPro-native/README.md → docs/reference/BQ-CRBC-1635.pdf
- `JSON file storage instead of SQLite` --rationale_for--> `JSONStore`  [EXTRACTED]
  ScaffoldPro-native/AUDIT.md → ScaffoldPro-native/main.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Documents sharing the Qt26193 letterhead PDF layout** — scaffoldpro_native_readme_quotation, scaffoldpro_native_readme_invoice, scaffoldpro_native_readme_delivery_note, scaffoldpro_native_readme_boq, scaffoldpro_native_main_pdfgenerator [EXTRACTED 1.00]
- **Python PDF layout preview and verification toolchain** — tools_pdf_preview_docs, tools_pdf_preview_compare, tools_pdf_preview_render, tools_pdf_preview_word, tools_pdf_preview_sheet [EXTRACTED 1.00]
- **Data safety: local backup, iCloud backup, team sharing** — scaffoldpro_native_readme_backup_restore, scaffoldpro_native_readme_icloud_backup, scaffoldpro_native_readme_team_sharing [INFERRED 0.85]
- **Project document editors (BOQ, quotation, invoice, delivery note)** — scaffoldpro_native_boq_editor, scaffoldpro_native_quotation_editor, scaffoldpro_native_invoice_editor, scaffoldpro_native_delivery_note_editor [EXTRACTED 1.00]
- **Party pages built on initPartyPage (clients, sites)** — scaffoldpro_native_clients, scaffoldpro_native_sites, scaffoldpro_native_party_page_initpartypage [EXTRACTED 1.00]
- **Project to documents workflow (project detail launches BOQ, quotation, invoice, delivery note)** — scaffoldpro_native_project_detail, scaffoldpro_native_boq_editor, scaffoldpro_native_quotation_editor, scaffoldpro_native_invoice_editor, scaffoldpro_native_delivery_note_editor [INFERRED 0.85]
- **App Icon Visual Composition** — scaffoldpro_native_icon_appicon_1024_scaffold_frame_motif, scaffoldpro_native_icon_appicon_1024_diagonal_brace, scaffoldpro_native_icon_appicon_1024_navy_rounded_square [EXTRACTED 1.00]
- **Scaffold bay structure depicted in the logo** — scaffoldpro_native_icon_scaffoldpro_logo_standards, scaffoldpro_native_icon_scaffoldpro_logo_ledgers, scaffoldpro_native_icon_scaffoldpro_logo_rosettes, scaffoldpro_native_icon_scaffoldpro_logo_safety_yellow_brace [EXTRACTED 1.00]
- **ScaffoldPro App Icon Composition** — scaffoldpro_native_icon_preview_scaffold_frame_motif, scaffoldpro_native_icon_preview_yellow_diagonal_brace, scaffoldpro_native_icon_preview_navy_gradient_background [EXTRACTED 1.00]
- **Total Amount composition (rental items, minimum hire, delivery)** — docs_reference_qt26193_page1_item_table, docs_reference_qt26193_page1_subtotal_min_hire, docs_reference_qt26193_page1_delivery_charges, docs_reference_qt26193_page1_total_amount [EXTRACTED 1.00]
- **Quotation page layout (letterhead, addressee, subject, table, footer)** — docs_reference_qt26193_page1_letterhead, docs_reference_qt26193_page1_client_address_block, docs_reference_qt26193_page1_reference_block, docs_reference_qt26193_page1_subject_line, docs_reference_qt26193_page1_item_table, docs_reference_qt26193_page1_footer [EXTRACTED 1.00]
- **Quotation payment, delivery and modification terms** — docs_reference_qt26193_page2_payment_term, docs_reference_qt26193_page2_delivery_term, docs_reference_qt26193_page2_modification_term, docs_reference_qt26193_page2_order_acceptance_clause [EXTRACTED 1.00]
- **Quotation acceptance via signatures** — docs_reference_qt26193_page2_order_acceptance_clause, docs_reference_qt26193_page2_proficiency_signatory, docs_reference_qt26193_page2_client_signatory, docs_reference_qt26193_page2_signature_block [EXTRACTED 1.00]

## Communities (67 total, 11 thin omitted)

### Community 0 - "PDF Drawing Primitives"
Cohesion: 0.07
Nodes (28): BQSheet, BQSheetRenderer, .rule, hangingItem(), HangingStyle, bullet, label, marker (+20 more)

### Community 1 - "Database Queries & Archiving"
Cohesion: 0.09
Nodes (4): isoFromDay(), safeFileBaseName(), Worker, WorkerActionResult

### Community 2 - "App Delegate & Menus"
Cohesion: 0.05
Nodes (15): AppDelegate, LetterColumnKind, center, left, money, right, weight, TitlebarDragView (+7 more)

### Community 3 - "Team Sync & XLSX Parsing"
Cohesion: 0.08
Nodes (15): Entry, Scan, SharedStringsParser, TeamMember, TeamStatus, TeamSync, .appVersion, .computerName (+7 more)

### Community 4 - "Swift Models & Architecture"
Cohesion: 0.09
Nodes (37): CoreGraphics, CoreText, PDFKit, ActivityRow, AdminDocumentSummary, BOQRatesSection, BOQSummary, CloudBackupStatus (+29 more)

### Community 5 - "Database Creation & Clients"
Cohesion: 0.11
Nodes (11): AppDatabase, .markupRoundsUp, .priceListsAreSeeded, Client, nextDocumentNumber(), PriceList, ProjectDetail, Quotation (+3 more)

### Community 6 - "Native Bridge Handlers"
Cohesion: 0.13
Nodes (6): DeliveryNoteActionResult, FileActionResult, InvoiceActionResult, NativeBridge, QuotationActionResult, SimpleResult

### Community 7 - "Project Detail Page"
Cohesion: 0.12
Nodes (39): createNewBOQ(), createNewDeliveryNote(), createNewInvoice(), createNewQuotation(), currentBOQs, currentDeliveryNotes, currentInvoices, currentQuotations (+31 more)

### Community 9 - "PDF Preview Renderer"
Cohesion: 0.08
Nodes (5): body(), Gen, width(), layout(), text_x()

### Community 10 - "Activity, Stock & Delivery"
Cohesion: 0.12
Nodes (6): ActivityEntry, InvoicePayment, nonBlank(), nowISO(), reordered(), validDay()

### Community 11 - "Word Export"
Cohesion: 0.18
Nodes (33): border(), buildLetterDocx(), buildSheetDocx(), cellParagraph(), closing(), crc32(), documentXML(), exportWord() (+25 more)

### Community 12 - "Quotation Editor"
Cohesion: 0.15
Nodes (31): addDeliveryCharge(), addFromPicker(), allowStatusChange(), BLOCK_KINDS, blockCall(), esc(), formatAdjustment(), getQuotationIdFromURL() (+23 more)

### Community 13 - "Settings Page"
Cohesion: 0.14
Nodes (32): afterRestore(), createBackup(), DEFAULT_MANPOWER_RATES, escAttr(), formatBytes(), formatWhen(), init(), loadLocations() (+24 more)

### Community 14 - "File Storage & Seeding"
Cohesion: 0.12
Nodes (5): FileStorage, .administrationRoot, .appRoot, .legacyBackupsRoot, .projectsRoot

### Community 15 - "Pricing & Markup Math"
Cohesion: 0.23
Nodes (13): BillOfQuantities, BOQCharge, BOQDetail, BOQLineItem, decimalOf(), doubleOf(), lineAmount(), lineDiscount() (+5 more)

### Community 16 - "Letter Formatting"
Cohesion: 0.17
Nodes (15): CompanySettings, DeliveryNote, formatMoney(), formatQuantity(), formattedParagraphs(), LetterParagraph, hanging, term (+7 more)

### Community 17 - "Accounts Page"
Cohesion: 0.21
Nodes (24): cents(), closeExpense(), csvLine(), deleteExpense(), esc(), exportCSV(), figures(), init() (+16 more)

### Community 18 - "Stock Page"
Cohesion: 0.23
Nodes (23): closeModal(), csvLine(), detailRow(), esc(), exportCSV(), filteredItems(), filteredMovements(), findItem() (+15 more)

### Community 19 - "Reference Docs & Audit"
Cohesion: 0.12
Nodes (23): BQ-CRBC-1635 PROFICIENCY QUOTATION sheet (A4 landscape), Qt26193 sample quotation screenshots, Reference documents README, ScaffoldPro audit against the master prompt, Bugs found and fixed in audit pass, Document lifecycle rules (Draft/Issued/Cancelled), Letterhead layout (from sample quotation Qt26193), Master development prompt (67 sections) (+15 more)

### Community 21 - "Admin Page"
Cohesion: 0.19
Nodes (21): admin.html (Admin page: workers, company docs), Worker and company document expiry reminders, ADMIN_DOC_CATEGORIES, adminDocs, applyAdminDocSearch(), closeWorkerModal(), daysUntil(), escapeAttr() (+13 more)

### Community 22 - "Preview Document Builders"
Cohesion: 0.21
Nodes (20): boq(), companySig(), dn(), dn_short(), formatted(), hangingItem(), invoice(), keyTermsText() (+12 more)

### Community 23 - "Local Backups"
Cohesion: 0.20
Nodes (6): BackupError, BackupManager, BackupManifest, BackupResult, BackupSummary, formatDateForDisplay()

### Community 24 - "Invoice Editor"
Cohesion: 0.22
Nodes (19): addFromPicker(), allowStatusChange(), defaultPrice(), esc(), getInvoiceIdFromURL(), init(), loadDetail(), localDay() (+11 more)

### Community 25 - "App Icon Generator"
Cohesion: 0.13
Nodes (6): render(), squircle_mask(), thick_line(), Export Word (.docx) matching PDF layout, PDF layout preview tool README, letterhead_png()

### Community 26 - "Sheet Layout & PDF Pages"
Cohesion: 0.21
Nodes (13): PriceListItemActionResult, SheetLayout, SheetRow, WordColumn, WordFont, WordInfoRow, WordLayout, WordParagraph (+5 more)

### Community 27 - "Editor Pages & Shared Scripts"
Cohesion: 0.22
Nodes (13): boq-editor.html (Bill of Quantities editor), delivery-note-editor.html (Delivery Note editor), Document export actions (PDF, Word, Print, Locate File, Delete), invoice-editor.html (Invoice editor), esc(), refresh(), Price list sources (SP Material and Price List 2026, SCAFOM), price-lists.html (Material List page) (+5 more)

### Community 28 - "BOQ Editor"
Cohesion: 0.24
Nodes (18): addFromPicker(), escAttr(), getBOQIdFromURL(), init(), loadDetail(), money(), populateCategories(), priceForMode() (+10 more)

### Community 29 - "Draft Quotations & Price Items"
Cohesion: 0.24
Nodes (3): makeId(), QuotationBlock, WorkerError

### Community 30 - "Price Lists Page"
Cohesion: 0.25
Nodes (16): allItemsForCurrentList, applyFilters(), applyImport(), groupByCategory(), handleCell(), init(), money(), openAddItem() (+8 more)

### Community 31 - "Projects & Dates"
Cohesion: 0.18
Nodes (6): currentYearSuffix(), nextProjectNumber(), NumberValidation, Project, ProjectCreateResult, validateProjectNumber()

### Community 32 - "Sidebar"
Cohesion: 0.22
Nodes (14): asNumber(), build(), cellValue(), close(), enhance(), highlight(), icon(), ICONS (+6 more)

### Community 33 - "Preview Sheet Layout"
Cohesion: 0.24
Nodes (10): fit(), font(), kg(), law_check(), layout(), money(), qty(), render() (+2 more)

### Community 34 - "Delivery Note Editor"
Cohesion: 0.30
Nodes (14): addFromPicker(), allowStatusChange(), getIdFromURL(), init(), loadDetail(), localDay(), lockStatusOptions(), populateCategories() (+6 more)

### Community 35 - "Paragraph Formatting"
Cohesion: 0.31
Nodes (13): bullets(), changed(), esc(), hangingIndent(), hangingItem(), indent(), labelSplit(), numbering() (+5 more)

### Community 36 - "iCloud Backup"
Cohesion: 0.18
Nodes (6): CloudBackupManager, .defaultFolder, .enabled, .folder, .iCloudDrive, .usingDefault

### Community 37 - "Sample Quotation Page 2"
Cohesion: 0.19
Nodes (13): Quotation Qt26193 Page 2 (Terms and Signature Page), Remainder of Page Intentionally Blank Notice, Lingma Construction & Engineering Co. Ltd. (client, unsigned: Position, Date blank), Delivery Term, Company Address and Contact Footer, Proficiency (HK) Limited Letterhead, Modification Term, Order Acceptance and Validity Clause (+5 more)

### Community 38 - "JSON Store"
Cohesion: 0.17
Nodes (8): JSONStore, .isEmpty, Backup and Restore (atomic, local automatic), Automatic iCloud backup to William's Work, Quotation Key Terms with hanging-indent formatting, Settings (company info, numbering, standard quotation), Share with Other Macs (iCloud change logs), Workers and administrative documents

### Community 39 - "Sample Quotation Page 1"
Cohesion: 0.20
Nodes (11): Client Address Block (Lingma Construction & Engineering Co. Ltd.), Delivery Charges Section (D1, HK$1,200/truck/trip x 2 = HK$2,400), Footer (company address, tel, email, fax, page number), Item Table (No, Description, Unit Rate per Month, Qty, Total Price; 13 rental items), Letterhead (Proficiency (HK) Limited, bilingual, orange rule), Quotation Qt26193 Page 1 (scaffolding rental quotation), Reference Block (Our Ref Qt26193, Site Ref MTR 1601, Date 22 Sep 2026, By Email Only), Salutation and Intro Paragraph (Dear Sir / Madam, thank you for your inquiry) (+3 more)

### Community 40 - "PDF Export Handlers"
Cohesion: 0.35
Nodes (5): PDFExportResult, PDFMode, export, print, word

### Community 41 - "Price Import & Relinking"
Cohesion: 0.21
Nodes (8): PriceImportPreview, RelinkTarget, adminDocument, document, drawing, workerDocument, SpreadsheetReader, SpreadsheetSheet

### Community 42 - "Bridge & Install Script"
Cohesion: 0.22
Nodes (6): install.sh script, refresh(), toast(), ScaffoldPro native shell README (Swift + WebKit), In-app update check and Update Now, Install ScaffoldPro.app / .command installer

### Community 43 - "Dashboard"
Cohesion: 0.38
Nodes (10): day(), esc(), loadDashboard(), money(), pickProjectThen(), projectsCache, renderSignedCopies(), statCard() (+2 more)

### Community 44 - "Signed Copy Upload"
Cohesion: 0.31
Nodes (8): base64Of(), dropTarget(), fromFile(), remove(), report(), setNotNeeded(), upload(), Signed quotation copy upload workflow

### Community 45 - "Accounts Data"
Cohesion: 0.29
Nodes (6): AccountsData, AccountsInvoice, AccountsPayment, DocRow, Expense, Invoice

### Community 46 - "Invoice & Delivery Line Items"
Cohesion: 0.24
Nodes (3): DeliveryNoteDetail, DeliveryNoteLineItem, InvoiceLineItem

### Community 47 - "Price Sheet Interpreter"
Cohesion: 0.22
Nodes (8): LetterTableRow, item, note, partial, section, summary, ParsedPriceRow, PriceSheetInterpreter

### Community 48 - "Party Page Helper"
Cohesion: 0.36
Nodes (10): escapeHTML(), initPartyPage(), closeSheet(), openSheet(), refresh(), render(), renderRelated(), save() (+2 more)

### Community 49 - "Line Discount"
Cohesion: 0.50
Nodes (8): build(), cents(), close(), money(), rateAfter(), save(), updateFields(), updatePreview()

### Community 50 - "Admin & Worker Documents"
Cohesion: 0.22
Nodes (4): AdminDocument, HasFilePath, ProjectDocument, WorkerDocument

### Community 53 - "Logo SVG"
Cohesion: 0.39
Nodes (7): ScaffoldPro App Icon Logo (SVG), Ledgers (horizontal bars), Navy gradient rounded-square icon body (macOS icon grid 824x824), Modular ringlock-style scaffold bay motif, Rosette connectors (3x3 grid of nodes), Safety-yellow diagonal brace, Standards (vertical posts) and base plates

### Community 54 - "Installer Steps Script"
Cohesion: 0.43
Nodes (7): finished(), PATH, progress(), install-steps.sh script, status(), step(), use_brew()

### Community 55 - "Projects Page"
Cohesion: 0.36
Nodes (6): allProjects, applySearch(), closeModal(), refresh(), renderProjects(), saveProject()

### Community 57 - "List Pages"
Cohesion: 0.57
Nodes (6): accounts.html (Accounts page), clients.html (Clients page), index.html (Dashboard), initPartyPage config pattern (clients and sites), projects.html (Projects list), sites.html (Sites page)

### Community 58 - "Icon Preview Sheet"
Cohesion: 0.33
Nodes (5): ScaffoldPro App Icon (rounded-square navy tile with scaffold grid), ScaffoldPro App Icon Preview Sheet, Navy Gradient Background Tile, Scaffold Frame Motif (vertical standards, horizontal ledgers, round node connectors), Yellow Diagonal Brace Accent

### Community 61 - "App Icon 1024"
Cohesion: 0.67
Nodes (4): ScaffoldPro App Icon (1024px), Yellow Diagonal Brace Accent, Navy Gradient Rounded-Square Background, Scaffold Frame Motif (3x3 grid of standards, ledgers and node rosettes)

### Community 63 - "SVG Icons"
Cohesion: 1.00
Nodes (3): iconize(), scan(), start()

## Knowledge Gaps
- **107 isolated node(s):** `install.sh script`, `askpass.sh script`, `PATH`, `PILL`, `STATUS_TEXT` (+102 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 189 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PDFGenerator` connect `PDF Drawing Primitives` to `Database Queries & Archiving`, `Team Sync & XLSX Parsing`, `Swift Models & Architecture`, `JSON Store`, `PDF Export Handlers`, `File Storage & Seeding`, `Reference Docs & Audit`, `App Icon Generator`, `Preview Signatures & Footer`?**
  _High betweenness centrality (0.421) - this node is a cross-community bridge._
- **Why does `Export Word (.docx) matching PDF layout` connect `App Icon Generator` to `PDF Drawing Primitives`, `Word Export`?**
  _High betweenness centrality (0.309) - this node is a cross-community bridge._
- **Why does `invoice-editor.html (Invoice editor)` connect `Editor Pages & Shared Scripts` to `Paragraph Formatting`, `Word Export`, `Line Discount`, `Invoice Editor`, `List Pages`?**
  _High betweenness centrality (0.119) - this node is a cross-community bridge._
- **What connects `install.sh script`, `askpass.sh script`, `PATH` to the rest of the system?**
  _107 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `PDF Drawing Primitives` be split into smaller, more focused modules?**
  _Cohesion score 0.06514851485148515 - nodes in this community are weakly interconnected._
- **Should `Database Queries & Archiving` be split into smaller, more focused modules?**
  _Cohesion score 0.08580246913580247 - nodes in this community are weakly interconnected._
- **Should `App Delegate & Menus` be split into smaller, more focused modules?**
  _Cohesion score 0.05194805194805195 - nodes in this community are weakly interconnected._
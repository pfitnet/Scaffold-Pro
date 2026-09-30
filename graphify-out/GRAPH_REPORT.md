# Graph Report - Scaffold-Pro  (2026-09-30)

## Corpus Check
- 48 files · ~165,676 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 15 file(s) not represented in the graph (top: .ttf 6, (none) 3, .plist 2)

## Summary
- 1507 nodes · 5567 edges · 75 communities (55 shown, 20 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 171 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `7485c7b8`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- PDFGenerator
- String
- AppDelegate
- TeamSync
- Bool
- AppDatabase
- NativeBridge
- project-detail.js
- InstallerController
- Gen
- nowISO
- docx-export.js
- quotation-editor.js
- settings.js
- URL
- Double
- .append
- accounts.js
- stock.js
- Quotation (standard Qt26193 style)
- admin.js
- docs.py
- BackupManager
- invoice-editor.js
- word.py
- Encodable
- quotation-editor.html (Quotation editor)
- boq-editor.js
- .touchQuotation
- price-lists.js
- .deliverRenderedPDF
- sidebar.js
- sheet.py
- delivery-note-editor.js
- paragraph-format.js
- CloudBackupManager
- Terms and Conditions
- JSONStore
- Quotation Qt26193 Page 1 (scaffolding rental quotation)
- Updater
- LetterTableRow
- bridge.js
- dashboard.js
- signed-copy.js
- .accountsData
- LaunchScreen
- initPartyPage
- line-discount.js
- .getDeliveryNote
- .getProjectByNumber
- ScaffoldPro App Icon Logo (SVG)
- install-steps.sh
- projects.js
- index.html (Dashboard)
- SheetUpdateScreen
- ScaffoldPro App Icon (rounded-square navy tile with scaffold grid)
- render.py
- ScaffoldPro App Icon (1024px)
- doc-select.js
- icons.js
- CLAUDE.md (project instructions)
- askpass.sh
- Scaffold-Pro README (title only)
- RelinkTarget
- ProjectRef
- .finishLaunching
- main.swift
- .git
- keep-focus.js

## God Nodes (most connected - your core abstractions)
1. `AppDatabase` - 262 edges
2. `NativeBridge` - 102 edges
3. `PDFGenerator` - 74 edges
4. `nowISO()` - 50 edges
5. `TeamSync` - 46 edges
6. `Gen` - 43 edges
7. `AppDelegate` - 38 edges
8. `nonBlank()` - 35 edges
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
- **App Icon Visual Composition** — scaffoldpro_native_icon_appicon_1024_scaffold_frame_motif, scaffoldpro_native_icon_appicon_1024_diagonal_brace, scaffoldpro_native_icon_appicon_1024_navy_rounded_square [EXTRACTED 1.00]
- **Documents sharing the Qt26193 letterhead PDF layout** — scaffoldpro_native_readme_quotation, scaffoldpro_native_readme_invoice, scaffoldpro_native_readme_delivery_note, scaffoldpro_native_readme_boq, scaffoldpro_native_main_pdfgenerator [EXTRACTED 1.00]
- **Python PDF layout preview and verification toolchain** — tools_pdf_preview_docs, tools_pdf_preview_compare, tools_pdf_preview_render, tools_pdf_preview_word, tools_pdf_preview_sheet [EXTRACTED 1.00]
- **Quotation acceptance via signatures** — docs_reference_qt26193_page2_order_acceptance_clause, docs_reference_qt26193_page2_proficiency_signatory, docs_reference_qt26193_page2_client_signatory, docs_reference_qt26193_page2_signature_block [EXTRACTED 1.00]
- **Quotation payment, delivery and modification terms** — docs_reference_qt26193_page2_payment_term, docs_reference_qt26193_page2_delivery_term, docs_reference_qt26193_page2_modification_term, docs_reference_qt26193_page2_order_acceptance_clause [EXTRACTED 1.00]
- **Quotation page layout (letterhead, addressee, subject, table, footer)** — docs_reference_qt26193_page1_letterhead, docs_reference_qt26193_page1_client_address_block, docs_reference_qt26193_page1_reference_block, docs_reference_qt26193_page1_subject_line, docs_reference_qt26193_page1_item_table, docs_reference_qt26193_page1_footer [EXTRACTED 1.00]
- **Total Amount composition (rental items, minimum hire, delivery)** — docs_reference_qt26193_page1_item_table, docs_reference_qt26193_page1_subtotal_min_hire, docs_reference_qt26193_page1_delivery_charges, docs_reference_qt26193_page1_total_amount [EXTRACTED 1.00]
- **ScaffoldPro App Icon Composition** — scaffoldpro_native_icon_preview_scaffold_frame_motif, scaffoldpro_native_icon_preview_yellow_diagonal_brace, scaffoldpro_native_icon_preview_navy_gradient_background [EXTRACTED 1.00]
- **Project document editors (BOQ, quotation, invoice, delivery note)** — scaffoldpro_native_boq_editor, scaffoldpro_native_quotation_editor, scaffoldpro_native_invoice_editor, scaffoldpro_native_delivery_note_editor [EXTRACTED 1.00]
- **Scaffold bay structure depicted in the logo** — scaffoldpro_native_icon_scaffoldpro_logo_standards, scaffoldpro_native_icon_scaffoldpro_logo_ledgers, scaffoldpro_native_icon_scaffoldpro_logo_rosettes, scaffoldpro_native_icon_scaffoldpro_logo_safety_yellow_brace [EXTRACTED 1.00]
- **Party pages built on initPartyPage (clients, sites)** — scaffoldpro_native_clients, scaffoldpro_native_sites, scaffoldpro_native_party_page_initpartypage [EXTRACTED 1.00]
- **Data safety: local backup, iCloud backup, team sharing** — scaffoldpro_native_readme_backup_restore, scaffoldpro_native_readme_icloud_backup, scaffoldpro_native_readme_team_sharing [INFERRED 0.85]
- **Project to documents workflow (project detail launches BOQ, quotation, invoice, delivery note)** — scaffoldpro_native_project_detail, scaffoldpro_native_boq_editor, scaffoldpro_native_quotation_editor, scaffoldpro_native_invoice_editor, scaffoldpro_native_delivery_note_editor [INFERRED 0.85]

## Communities (75 total, 20 thin omitted)

### Community 0 - "PDFGenerator"
Cohesion: 0.07
Nodes (19): BQSheet, BQSheetRenderer, .rule, Key, LetterColumn, LetterDocument, LetterInfoRow, PDFGenerator (+11 more)

### Community 3 - "TeamSync"
Cohesion: 0.06
Nodes (15): Entry, Scan, SharedStringsParser, TeamSync, .appVersion, .computerName, .configuredFolder, .databaseRoot (+7 more)

### Community 4 - "Bool"
Cohesion: 0.11
Nodes (36): AdminDocument, AdminDocumentSummary, BOQActionResult, BOQSummary, DataLocations, DefaultBOQItem, DeliveryNoteActionResult, DeliveryNoteSummary (+28 more)

### Community 5 - "AppDatabase"
Cohesion: 0.11
Nodes (9): AppDatabase, .markupRoundsUp, .priceListsAreSeeded, fileIsPresent(), nextDocumentNumber(), PriceList, Quotation, QuotationLineItem (+1 more)

### Community 7 - "project-detail.js"
Cohesion: 0.12
Nodes (39): createNewBOQ(), createNewDeliveryNote(), createNewInvoice(), createNewQuotation(), currentBOQs, currentDeliveryNotes, currentInvoices, currentQuotations (+31 more)

### Community 9 - "Gen"
Cohesion: 0.08
Nodes (5): body(), Gen, width(), layout(), text_x()

### Community 10 - "nowISO"
Cohesion: 0.16
Nodes (4): ActivityEntry, makeId(), nowISO(), validDay()

### Community 11 - "docx-export.js"
Cohesion: 0.18
Nodes (33): border(), buildLetterDocx(), buildSheetDocx(), cellParagraph(), closing(), crc32(), documentXML(), exportWord() (+25 more)

### Community 12 - "quotation-editor.js"
Cohesion: 0.15
Nodes (31): addDeliveryCharge(), addFromPicker(), allowStatusChange(), BLOCK_KINDS, blockCall(), esc(), formatAdjustment(), getQuotationIdFromURL() (+23 more)

### Community 13 - "settings.js"
Cohesion: 0.11
Nodes (41): afterRestore(), allMaterials(), createBackup(), DEFAULT_MANPOWER_RATES, defaultBOQItems, escAttr(), formatBytes(), formatWhen() (+33 more)

### Community 14 - "URL"
Cohesion: 0.12
Nodes (6): FileStorage, .administrationRoot, .appRoot, .legacyBackupsRoot, .projectsRoot, SimpleResult

### Community 15 - "Double"
Cohesion: 0.18
Nodes (15): BillOfQuantities, BOQCharge, BOQDetail, BOQLineItem, BOQRatesSection, decimalOf(), doubleOf(), lineAmount() (+7 more)

### Community 16 - ".append"
Cohesion: 0.21
Nodes (16): CompanySettings, DeliveryNote, formatMoney(), formatQuantity(), formattedParagraphs(), LetterParagraph, hanging, term (+8 more)

### Community 17 - "accounts.js"
Cohesion: 0.21
Nodes (24): cents(), closeExpense(), csvLine(), deleteExpense(), esc(), exportCSV(), figures(), init() (+16 more)

### Community 18 - "stock.js"
Cohesion: 0.23
Nodes (23): closeModal(), csvLine(), detailRow(), esc(), exportCSV(), filteredItems(), filteredMovements(), findItem() (+15 more)

### Community 19 - "Quotation (standard Qt26193 style)"
Cohesion: 0.12
Nodes (23): BQ-CRBC-1635 PROFICIENCY QUOTATION sheet (A4 landscape), Qt26193 sample quotation screenshots, Reference documents README, ScaffoldPro audit against the master prompt, Bugs found and fixed in audit pass, Document lifecycle rules (Draft/Issued/Cancelled), Letterhead layout (from sample quotation Qt26193), Master development prompt (67 sections) (+15 more)

### Community 21 - "admin.js"
Cohesion: 0.19
Nodes (21): admin.html (Admin page: workers, company docs), Worker and company document expiry reminders, ADMIN_DOC_CATEGORIES, adminDocs, applyAdminDocSearch(), closeWorkerModal(), daysUntil(), escapeAttr() (+13 more)

### Community 22 - "docs.py"
Cohesion: 0.21
Nodes (20): boq(), companySig(), dn(), dn_short(), formatted(), hangingItem(), invoice(), keyTermsText() (+12 more)

### Community 23 - "BackupManager"
Cohesion: 0.29
Nodes (5): BackupManager, BackupManifest, BackupResult, BackupSummary, formatDateForDisplay()

### Community 24 - "invoice-editor.js"
Cohesion: 0.22
Nodes (19): addFromPicker(), allowStatusChange(), defaultPrice(), esc(), getInvoiceIdFromURL(), init(), loadDetail(), localDay() (+11 more)

### Community 25 - "word.py"
Cohesion: 0.13
Nodes (6): render(), squircle_mask(), thick_line(), Export Word (.docx) matching PDF layout, PDF layout preview tool README, letterhead_png()

### Community 26 - "Encodable"
Cohesion: 0.28
Nodes (12): SheetCell, SheetRow, WordColumn, WordFont, WordInfoRow, WordLayout, WordParagraph, WordRefRow (+4 more)

### Community 27 - "quotation-editor.html (Quotation editor)"
Cohesion: 0.22
Nodes (13): boq-editor.html (Bill of Quantities editor), delivery-note-editor.html (Delivery Note editor), Document export actions (PDF, Word, Print, Locate File, Delete), invoice-editor.html (Invoice editor), esc(), refresh(), Price list sources (SP Material and Price List 2026, SCAFOM), price-lists.html (Material List page) (+5 more)

### Community 28 - "boq-editor.js"
Cohesion: 0.24
Nodes (18): addFromPicker(), escAttr(), getBOQIdFromURL(), init(), loadDetail(), money(), populateCategories(), priceForMode() (+10 more)

### Community 29 - ".touchQuotation"
Cohesion: 0.21
Nodes (3): QuotationBlock, reordered(), WorkerError

### Community 30 - "price-lists.js"
Cohesion: 0.25
Nodes (16): allItemsForCurrentList, applyFilters(), applyImport(), groupByCategory(), handleCell(), init(), money(), openAddItem() (+8 more)

### Community 31 - ".deliverRenderedPDF"
Cohesion: 0.15
Nodes (6): PDFAttachments, PDFExportResult, PDFMode, export, print, word

### Community 32 - "sidebar.js"
Cohesion: 0.22
Nodes (14): asNumber(), build(), cellValue(), close(), enhance(), highlight(), icon(), ICONS (+6 more)

### Community 33 - "sheet.py"
Cohesion: 0.24
Nodes (10): fit(), font(), kg(), law_check(), layout(), money(), qty(), render() (+2 more)

### Community 34 - "delivery-note-editor.js"
Cohesion: 0.30
Nodes (14): addFromPicker(), allowStatusChange(), getIdFromURL(), init(), loadDetail(), localDay(), lockStatusOptions(), populateCategories() (+6 more)

### Community 35 - "paragraph-format.js"
Cohesion: 0.31
Nodes (13): bullets(), changed(), esc(), hangingIndent(), hangingItem(), indent(), labelSplit(), numbering() (+5 more)

### Community 36 - "CloudBackupManager"
Cohesion: 0.12
Nodes (13): BackupError, CloudBackupManager, .defaultFolder, .enabled, .folder, .iCloudDrive, .usingDefault, CloudBackupStatus (+5 more)

### Community 37 - "Terms and Conditions"
Cohesion: 0.19
Nodes (13): Quotation Qt26193 Page 2 (Terms and Signature Page), Remainder of Page Intentionally Blank Notice, Lingma Construction & Engineering Co. Ltd. (client, unsigned: Position, Date blank), Delivery Term, Company Address and Contact Footer, Proficiency (HK) Limited Letterhead, Modification Term, Order Acceptance and Validity Clause (+5 more)

### Community 38 - "JSONStore"
Cohesion: 0.17
Nodes (8): JSONStore, .isEmpty, Backup and Restore (atomic, local automatic), Automatic iCloud backup to William's Work, Quotation Key Terms with hanging-indent formatting, Settings (company info, numbering, standard quotation), Share with Other Macs (iCloud change logs), Workers and administrative documents

### Community 39 - "Quotation Qt26193 Page 1 (scaffolding rental quotation)"
Cohesion: 0.20
Nodes (11): Client Address Block (Lingma Construction & Engineering Co. Ltd.), Delivery Charges Section (D1, HK$1,200/truck/trip x 2 = HK$2,400), Footer (company address, tel, email, fax, page number), Item Table (No, Description, Unit Rate per Month, Qty, Total Price; 13 rental items), Letterhead (Proficiency (HK) Limited, bilingual, orange rule), Quotation Qt26193 Page 1 (scaffolding rental quotation), Reference Block (Our Ref Qt26193, Site Ref MTR 1601, Date 22 Sep 2026, By Email Only), Salutation and Intro Paragraph (Dear Sir / Madam, thank you for your inquiry) (+3 more)

### Community 40 - "Updater"
Cohesion: 0.24
Nodes (3): Updater, .failureNoteURL, .gitHubDesktopURL

### Community 41 - "LetterTableRow"
Cohesion: 0.15
Nodes (10): LetterTableRow, item, note, partial, section, summary, ParsedPriceRow, PriceSheetInterpreter (+2 more)

### Community 42 - "bridge.js"
Cohesion: 0.22
Nodes (6): install.sh script, refresh(), toast(), ScaffoldPro native shell README (Swift + WebKit), In-app update check and Update Now, Install ScaffoldPro.app / .command installer

### Community 43 - "dashboard.js"
Cohesion: 0.35
Nodes (11): day(), esc(), loadDashboard(), money(), pickProjectThen(), projectsCache, renderAwaitingQuotations(), statCard() (+3 more)

### Community 44 - "signed-copy.js"
Cohesion: 0.31
Nodes (8): base64Of(), dropTarget(), fromFile(), remove(), report(), setNotNeeded(), upload(), Signed quotation copy upload workflow

### Community 48 - "initPartyPage"
Cohesion: 0.36
Nodes (10): escapeHTML(), initPartyPage(), closeSheet(), openSheet(), refresh(), render(), renderRelated(), save() (+2 more)

### Community 49 - "line-discount.js"
Cohesion: 0.50
Nodes (8): build(), cents(), close(), money(), rateAfter(), save(), updateFields(), updatePreview()

### Community 53 - "ScaffoldPro App Icon Logo (SVG)"
Cohesion: 0.39
Nodes (7): ScaffoldPro App Icon Logo (SVG), Ledgers (horizontal bars), Navy gradient rounded-square icon body (macOS icon grid 824x824), Modular ringlock-style scaffold bay motif, Rosette connectors (3x3 grid of nodes), Safety-yellow diagonal brace, Standards (vertical posts) and base plates

### Community 54 - "install-steps.sh"
Cohesion: 0.43
Nodes (7): finished(), PATH, progress(), install-steps.sh script, status(), step(), use_brew()

### Community 55 - "projects.js"
Cohesion: 0.36
Nodes (6): allProjects, applySearch(), closeModal(), refresh(), renderProjects(), saveProject()

### Community 56 - "index.html (Dashboard)"
Cohesion: 0.57
Nodes (6): accounts.html (Accounts page), clients.html (Clients page), index.html (Dashboard), initPartyPage config pattern (clients and sites), projects.html (Projects list), sites.html (Sites page)

### Community 57 - "SheetUpdateScreen"
Cohesion: 0.11
Nodes (5): LaunchWindow, .canBecomeKey, .canBecomeMain, SheetUpdateScreen, UpdateScreen

### Community 58 - "ScaffoldPro App Icon (rounded-square navy tile with scaffold grid)"
Cohesion: 0.33
Nodes (5): ScaffoldPro App Icon (rounded-square navy tile with scaffold grid), ScaffoldPro App Icon Preview Sheet, Navy Gradient Background Tile, Scaffold Frame Motif (vertical standards, horizontal ledgers, round node connectors), Yellow Diagonal Brace Accent

### Community 61 - "ScaffoldPro App Icon (1024px)"
Cohesion: 0.67
Nodes (4): ScaffoldPro App Icon (1024px), Yellow Diagonal Brace Accent, Navy Gradient Rounded-Square Background, Scaffold Frame Motif (3x3 grid of standards, ledgers and node rosettes)

### Community 63 - "icons.js"
Cohesion: 1.00
Nodes (3): iconize(), scan(), start()

### Community 67 - "RelinkTarget"
Cohesion: 0.40
Nodes (5): RelinkTarget, adminDocument, document, drawing, workerDocument

### Community 68 - "ProjectRef"
Cohesion: 0.43
Nodes (6): ProjectRef, StockData, StockItemRow, StockMovement, StockMovementView, StockProjectQuantity

### Community 70 - ".finishLaunching"
Cohesion: 0.12
Nodes (8): LetterColumnKind, center, left, money, right, weight, TitlebarDragView, .mouseDownCanMoveWindow

### Community 71 - "main.swift"
Cohesion: 0.10
Nodes (27): CoreGraphics, CoreText, PDFKit, AccountsData, AccountsInvoice, AccountsPayment, ActivityRow, Client (+19 more)

### Community 73 - "keep-focus.js"
Cohesion: 0.80
Nodes (4): alike(), remember(), restore(), signature()

## Knowledge Gaps
- **111 isolated node(s):** `install.sh script`, `askpass.sh script`, `PATH`, `PILL`, `STATUS_TEXT` (+106 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 203 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **20 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PDFGenerator` connect `PDFGenerator` to `String`, `TeamSync`, `Bool`, `JSONStore`, `main.swift`, `.append`, `Quotation (standard Qt26193 style)`, `word.py`, `render.py`, `.deliverRenderedPDF`?**
  _High betweenness centrality (0.403) - this node is a cross-community bridge._
- **Why does `Export Word (.docx) matching PDF layout` connect `word.py` to `PDFGenerator`, `docx-export.js`?**
  _High betweenness centrality (0.309) - this node is a cross-community bridge._
- **Why does `quotation-editor.html (Quotation editor)` connect `quotation-editor.html (Quotation editor)` to `paragraph-format.js`, `docx-export.js`, `quotation-editor.js`, `signed-copy.js`, `line-discount.js`, `index.html (Dashboard)`?**
  _High betweenness centrality (0.114) - this node is a cross-community bridge._
- **What connects `install.sh script`, `askpass.sh script`, `PATH` to the rest of the system?**
  _111 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `PDFGenerator` be split into smaller, more focused modules?**
  _Cohesion score 0.07429526994744386 - nodes in this community are weakly interconnected._
- **Should `String` be split into smaller, more focused modules?**
  _Cohesion score 0.08032128514056225 - nodes in this community are weakly interconnected._
- **Should `AppDelegate` be split into smaller, more focused modules?**
  _Cohesion score 0.12962962962962962 - nodes in this community are weakly interconnected._
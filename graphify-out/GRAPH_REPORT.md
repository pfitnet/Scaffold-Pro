# Graph Report - Scaffold-Pro  (2026-09-30)

## Corpus Check
- 48 files · ~172,012 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 15 file(s) not represented in the graph (top: .ttf 6, (none) 3, .plist 2)

## Summary
- 1537 nodes · 5716 edges · 75 communities (58 shown, 17 thin omitted)
- Extraction: 97% EXTRACTED · 3% INFERRED · 0% AMBIGUOUS · INFERRED: 182 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `9017607a`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- PDFGenerator
- .userContentController
- AppDelegate
- TeamSync
- Codable
- bridge.js
- project-detail.js
- InstallerController
- Gen
- nowISO
- docx-export.js
- quotation-editor.js
- settings.js
- AppDatabase
- Double
- NativeBridge
- accounts.js
- stock.js
- Quotation (standard Qt26193 style)
- String
- admin.js
- docs.py
- BackupManager
- invoice-editor.js
- word.py
- main.swift
- quotation-editor.html (Quotation editor)
- boq-editor.js
- .touchQuotation
- price-lists.js
- LetterTableRow
- sidebar.js
- sheet.py
- delivery-note-editor.js
- paragraph-format.js
- CloudBackupManager
- Terms and Conditions
- .deliveryNoteLetter
- Quotation Qt26193 Page 1 (scaffolding rental quotation)
- Updater
- URL
- WorksheetParser
- dashboard.js
- signed-copy.js
- .append
- .handleCombineDocuments
- LaunchScreen
- initPartyPage
- line-discount.js
- .getCompanySettings
- ScaffoldPro App Icon Logo (SVG)
- install-steps.sh
- projects.js
- NSObject
- SheetUpdateScreen
- ScaffoldPro App Icon (rounded-square navy tile with scaffold grid)
- ProjectRef
- index.html (Dashboard)
- ScaffoldPro App Icon (1024px)
- doc-select.js
- icons.js
- CLAUDE.md (project instructions)
- askpass.sh
- Scaffold-Pro README (title only)
- nextDocumentNumber
- .handleUpdateDeliveryNoteHeader
- linked-drawings.js
- .finishLaunching
- .git
- keep-focus.js
- file-drop.js
- item-picker.js

## God Nodes (most connected - your core abstractions)
1. `AppDatabase` - 268 edges
2. `NativeBridge` - 103 edges
3. `PDFGenerator` - 75 edges
4. `nowISO()` - 52 edges
5. `TeamSync` - 46 edges
6. `Gen` - 43 edges
7. `nonBlank()` - 38 edges
8. `AppDelegate` - 38 edges
9. `makeId()` - 34 edges
10. `Updater` - 33 edges

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

## Communities (75 total, 17 thin omitted)

### Community 0 - "PDFGenerator"
Cohesion: 0.06
Nodes (26): BQSheet, BQSheetRenderer, .rule, hangingItem(), HangingStyle, bullet, label, marker (+18 more)

### Community 3 - "TeamSync"
Cohesion: 0.11
Nodes (11): Entry, Scan, TeamSync, .appVersion, .computerName, .configuredFolder, .databaseRoot, .deviceId (+3 more)

### Community 4 - "Codable"
Cohesion: 0.11
Nodes (28): AccountsData, AccountsInvoice, AccountsPayment, ActivityRow, AdminDocument, AdminDocumentSummary, CloudBackupStatus, DashboardSummary (+20 more)

### Community 5 - "bridge.js"
Cohesion: 0.22
Nodes (6): install.sh script, refresh(), toast(), ScaffoldPro native shell README (Swift + WebKit), In-app update check and Update Now, Install ScaffoldPro.app / .command installer

### Community 7 - "project-detail.js"
Cohesion: 0.12
Nodes (40): createNewBOQ(), createNewDeliveryNote(), createNewInvoice(), createNewQuotation(), currentBOQs, currentDeliveryNotes, currentInvoices, currentQuotations (+32 more)

### Community 9 - "Gen"
Cohesion: 0.08
Nodes (7): body(), font(), Gen, times(), width(), layout(), text_x()

### Community 10 - "nowISO"
Cohesion: 0.15
Nodes (5): makeId(), nonBlank(), nowISO(), StockMovement, validDay()

### Community 11 - "docx-export.js"
Cohesion: 0.18
Nodes (33): border(), buildLetterDocx(), buildSheetDocx(), cellParagraph(), closing(), crc32(), documentXML(), exportWord() (+25 more)

### Community 12 - "quotation-editor.js"
Cohesion: 0.16
Nodes (31): addDeliveryCharge(), addFromPicker(), allowStatusChange(), BLOCK_KINDS, blockCall(), esc(), formatAdjustment(), getQuotationIdFromURL() (+23 more)

### Community 13 - "settings.js"
Cohesion: 0.11
Nodes (41): afterRestore(), allMaterials(), createBackup(), DEFAULT_MANPOWER_RATES, defaultBOQItems, escAttr(), formatBytes(), formatWhen() (+33 more)

### Community 14 - "AppDatabase"
Cohesion: 0.12
Nodes (7): ActivityEntry, AppDatabase, .priceListsAreSeeded, PriceList, ProjectDrawing, ProjectListEntry, Worker

### Community 15 - "Double"
Cohesion: 0.20
Nodes (17): BillOfQuantities, BOQCharge, BOQDetail, BOQLineItem, BOQRatesSection, BOQSummary, decimalOf(), doubleOf() (+9 more)

### Community 16 - "NativeBridge"
Cohesion: 0.10
Nodes (9): FileActionResult, NativeBridge, RelinkTarget, adminDocument, document, drawing, workerDocument, SimpleResult (+1 more)

### Community 17 - "accounts.js"
Cohesion: 0.21
Nodes (24): cents(), closeExpense(), csvLine(), deleteExpense(), esc(), exportCSV(), figures(), init() (+16 more)

### Community 18 - "stock.js"
Cohesion: 0.22
Nodes (25): closeModal(), csvLine(), detailRow(), esc(), exportCSV(), filteredItems(), filteredMovements(), findItem() (+17 more)

### Community 19 - "Quotation (standard Qt26193 style)"
Cohesion: 0.11
Nodes (25): BQ-CRBC-1635 PROFICIENCY QUOTATION sheet (A4 landscape), Qt26193 sample quotation screenshots, Reference documents README, ScaffoldPro audit against the master prompt, Bugs found and fixed in audit pass, Document lifecycle rules (Draft/Issued/Cancelled), Letterhead layout (from sample quotation Qt26193), Master development prompt (67 sections) (+17 more)

### Community 21 - "admin.js"
Cohesion: 0.19
Nodes (21): admin.html (Admin page: workers, company docs), Worker and company document expiry reminders, ADMIN_DOC_CATEGORIES, adminDocs, applyAdminDocSearch(), closeWorkerModal(), daysUntil(), escapeAttr() (+13 more)

### Community 22 - "docs.py"
Cohesion: 0.21
Nodes (20): boq(), companySig(), dn(), dn_short(), formatted(), hangingItem(), invoice(), keyTermsText() (+12 more)

### Community 23 - "BackupManager"
Cohesion: 0.16
Nodes (8): BackupManager, BackupManifest, BackupResult, BackupSummary, currentYearSuffix(), formatDateForDisplay(), nextProjectNumber(), validateProjectNumber()

### Community 24 - "invoice-editor.js"
Cohesion: 0.22
Nodes (19): addFromPicker(), allowStatusChange(), defaultPrice(), esc(), getInvoiceIdFromURL(), init(), loadDetail(), localDay() (+11 more)

### Community 25 - "word.py"
Cohesion: 0.13
Nodes (6): render(), squircle_mask(), thick_line(), Export Word (.docx) matching PDF layout, PDF layout preview tool README, letterhead_png()

### Community 26 - "main.swift"
Cohesion: 0.10
Nodes (37): CoreGraphics, CoreText, PDFKit, BOQActionResult, CombinedDocumentResult, DeliveryNoteActionResult, fileIsPresent(), formattedParagraphs() (+29 more)

### Community 27 - "quotation-editor.html (Quotation editor)"
Cohesion: 0.26
Nodes (11): boq-editor.html (Bill of Quantities editor), delivery-note-editor.html (Delivery Note editor), Document export actions (PDF, Word, Print, Locate File, Delete), invoice-editor.html (Invoice editor), Price list sources (SP Material and Price List 2026, SCAFOM), price-lists.html (Material List page), project-detail.html (Project detail with tabs), quotation-editor.html (Quotation editor) (+3 more)

### Community 28 - "boq-editor.js"
Cohesion: 0.24
Nodes (18): addFromPicker(), escAttr(), getBOQIdFromURL(), init(), loadDetail(), money(), populateCategories(), priceForMode() (+10 more)

### Community 30 - "price-lists.js"
Cohesion: 0.17
Nodes (25): allItemsForCurrentList, applyFilters(), applyImport(), groupByCategory(), handleCell(), init(), lastShownItems, makeUnitRates() (+17 more)

### Community 31 - "LetterTableRow"
Cohesion: 0.33
Nodes (6): LetterTableRow, item, note, partial, section, summary

### Community 32 - "sidebar.js"
Cohesion: 0.20
Nodes (14): asNumber(), build(), cellValue(), close(), enhance(), highlight(), icon(), ICONS (+6 more)

### Community 33 - "sheet.py"
Cohesion: 0.24
Nodes (10): fit(), font(), kg(), law_check(), layout(), money(), qty(), render() (+2 more)

### Community 34 - "delivery-note-editor.js"
Cohesion: 0.24
Nodes (17): addFromPicker(), allowStatusChange(), getIdFromURL(), importFromQuotation(), init(), loadDetail(), loadQuotationChoices(), localDay() (+9 more)

### Community 35 - "paragraph-format.js"
Cohesion: 0.31
Nodes (13): bullets(), changed(), esc(), hangingIndent(), hangingItem(), indent(), labelSplit(), numbering() (+5 more)

### Community 36 - "CloudBackupManager"
Cohesion: 0.13
Nodes (7): BackupError, CloudBackupManager, .defaultFolder, .enabled, .folder, .iCloudDrive, .usingDefault

### Community 37 - "Terms and Conditions"
Cohesion: 0.19
Nodes (13): Quotation Qt26193 Page 2 (Terms and Signature Page), Remainder of Page Intentionally Blank Notice, Lingma Construction & Engineering Co. Ltd. (client, unsigned: Position, Date blank), Delivery Term, Company Address and Contact Footer, Proficiency (HK) Limited Letterhead, Modification Term, Order Acceptance and Validity Clause (+5 more)

### Community 38 - ".deliveryNoteLetter"
Cohesion: 0.16
Nodes (16): Client, CompanySettings, DefaultBOQItem, DeliveryNote, formatMoney(), formatQuantity(), LetterSignature, LetterSignatureLine (+8 more)

### Community 39 - "Quotation Qt26193 Page 1 (scaffolding rental quotation)"
Cohesion: 0.20
Nodes (11): Client Address Block (Lingma Construction & Engineering Co. Ltd.), Delivery Charges Section (D1, HK$1,200/truck/trip x 2 = HK$2,400), Footer (company address, tel, email, fax, page number), Item Table (No, Description, Unit Rate per Month, Qty, Total Price; 13 rental items), Letterhead (Proficiency (HK) Limited, bilingual, orange rule), Quotation Qt26193 Page 1 (scaffolding rental quotation), Reference Block (Our Ref Qt26193, Site Ref MTR 1601, Date 22 Sep 2026, By Email Only), Salutation and Intro Paragraph (Dear Sir / Madam, thank you for your inquiry) (+3 more)

### Community 40 - "Updater"
Cohesion: 0.24
Nodes (3): Updater, .failureNoteURL, .gitHubDesktopURL

### Community 41 - "URL"
Cohesion: 0.11
Nodes (11): FileStorage, .administrationRoot, .appRoot, .legacyBackupsRoot, .projectsRoot, JSONStore, .isEmpty, Backup and Restore (atomic, local automatic) (+3 more)

### Community 42 - "WorksheetParser"
Cohesion: 0.17
Nodes (3): SharedStringsParser, WorksheetParser, XMLAttributeCollector

### Community 43 - "dashboard.js"
Cohesion: 0.33
Nodes (12): chargeCell(), day(), esc(), loadDashboard(), money(), pickProjectThen(), projectsCache, renderAwaitingQuotations() (+4 more)

### Community 44 - "signed-copy.js"
Cohesion: 0.31
Nodes (8): base64Of(), dropTarget(), fromFile(), remove(), report(), setNotNeeded(), upload(), Signed quotation copy upload workflow

### Community 45 - ".append"
Cohesion: 0.20
Nodes (5): ParsedPriceRow, PDFAttachments, PriceSheetInterpreter, SpreadsheetReader, SpreadsheetSheet

### Community 46 - ".handleCombineDocuments"
Cohesion: 0.29
Nodes (5): PDFExportResult, PDFMode, export, print, word

### Community 48 - "initPartyPage"
Cohesion: 0.36
Nodes (10): escapeHTML(), initPartyPage(), closeSheet(), openSheet(), refresh(), render(), renderRelated(), save() (+2 more)

### Community 49 - "line-discount.js"
Cohesion: 0.50
Nodes (8): build(), cents(), close(), money(), rateAfter(), save(), updateFields(), updatePreview()

### Community 51 - ".getCompanySettings"
Cohesion: 0.18
Nodes (9): .markupRoundsUp, .minimumMonthlyRental, ChargeSplit, DocRow, PartyDetail, Quotation, QuotationDetail, QuotationLineItem (+1 more)

### Community 53 - "ScaffoldPro App Icon Logo (SVG)"
Cohesion: 0.39
Nodes (7): ScaffoldPro App Icon Logo (SVG), Ledgers (horizontal bars), Navy gradient rounded-square icon body (macOS icon grid 824x824), Modular ringlock-style scaffold bay motif, Rosette connectors (3x3 grid of nodes), Safety-yellow diagonal brace, Standards (vertical posts) and base plates

### Community 54 - "install-steps.sh"
Cohesion: 0.43
Nodes (7): finished(), PATH, progress(), install-steps.sh script, status(), step(), use_brew()

### Community 55 - "projects.js"
Cohesion: 0.36
Nodes (6): allProjects, applySearch(), closeModal(), refresh(), renderProjects(), saveProject()

### Community 57 - "SheetUpdateScreen"
Cohesion: 0.10
Nodes (5): LaunchWindow, .canBecomeKey, .canBecomeMain, SheetUpdateScreen, UpdateScreen

### Community 58 - "ScaffoldPro App Icon (rounded-square navy tile with scaffold grid)"
Cohesion: 0.33
Nodes (5): ScaffoldPro App Icon (rounded-square navy tile with scaffold grid), ScaffoldPro App Icon Preview Sheet, Navy Gradient Background Tile, Scaffold Frame Motif (vertical standards, horizontal ledgers, round node connectors), Yellow Diagonal Brace Accent

### Community 59 - "ProjectRef"
Cohesion: 0.39
Nodes (6): ProjectRef, SearchResult, StockData, StockItemRow, StockMovementView, StockProjectQuantity

### Community 60 - "index.html (Dashboard)"
Cohesion: 0.57
Nodes (6): accounts.html (Accounts page), clients.html (Clients page), index.html (Dashboard), initPartyPage config pattern (clients and sites), projects.html (Projects list), sites.html (Sites page)

### Community 61 - "ScaffoldPro App Icon (1024px)"
Cohesion: 0.67
Nodes (4): ScaffoldPro App Icon (1024px), Yellow Diagonal Brace Accent, Navy Gradient Rounded-Square Background, Scaffold Frame Motif (3x3 grid of standards, ledgers and node rosettes)

### Community 63 - "icons.js"
Cohesion: 1.00
Nodes (3): iconize(), scan(), start()

### Community 70 - ".finishLaunching"
Cohesion: 0.12
Nodes (8): LetterColumnKind, center, left, money, right, weight, TitlebarDragView, .mouseDownCanMoveWindow

### Community 72 - ".git"
Cohesion: 0.52
Nodes (3): UpdateChecker, .canCheck, UpdateInfo

### Community 73 - "keep-focus.js"
Cohesion: 0.80
Nodes (4): alike(), remember(), restore(), signature()

### Community 74 - "file-drop.js"
Cohesion: 0.60
Nodes (3): scroller(), step(), stop()

### Community 75 - "item-picker.js"
Cohesion: 0.83
Nodes (3): esc(), groupBox(), render()

## Knowledge Gaps
- **115 isolated node(s):** `install.sh script`, `askpass.sh script`, `PATH`, `PILL`, `STATUS_TEXT` (+110 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 205 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **17 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PDFGenerator` connect `PDFGenerator` to `Codable`, `.deliveryNoteLetter`, `Gen`, `WorksheetParser`, `.handleCombineDocuments`, `Quotation (standard Qt26193 style)`, `String`, `word.py`, `main.swift`?**
  _High betweenness centrality (0.403) - this node is a cross-community bridge._
- **Why does `Export Word (.docx) matching PDF layout` connect `word.py` to `PDFGenerator`, `docx-export.js`?**
  _High betweenness centrality (0.309) - this node is a cross-community bridge._
- **Why does `quotation-editor.html (Quotation editor)` connect `quotation-editor.html (Quotation editor)` to `paragraph-format.js`, `linked-drawings.js`, `docx-export.js`, `quotation-editor.js`, `signed-copy.js`, `line-discount.js`, `index.html (Dashboard)`?**
  _High betweenness centrality (0.123) - this node is a cross-community bridge._
- **What connects `install.sh script`, `askpass.sh script`, `PATH` to the rest of the system?**
  _115 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `PDFGenerator` be split into smaller, more focused modules?**
  _Cohesion score 0.06475247524752475 - nodes in this community are weakly interconnected._
- **Should `.userContentController` be split into smaller, more focused modules?**
  _Cohesion score 0.07886904761904762 - nodes in this community are weakly interconnected._
- **Should `AppDelegate` be split into smaller, more focused modules?**
  _Cohesion score 0.11088709677419355 - nodes in this community are weakly interconnected._
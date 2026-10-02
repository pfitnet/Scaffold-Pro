# Graph Report - Scaffold-Pro  (2026-10-02)

## Corpus Check
- 75 files · ~271,474 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 33 file(s) not represented in the graph (top: .whl 16, .ttf 6, (none) 3)

## Summary
- 2207 nodes · 8459 edges · 102 communities (87 shown, 15 thin omitted)
- Extraction: 96% EXTRACTED · 4% INFERRED · 0% AMBIGUOUS · INFERRED: 339 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `c6b51be4`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- PDFGenerator
- AppDatabase
- AppDelegate
- TeamSync
- CloudBackupManager
- marketing.js
- delivery-schedule.js
- project-detail.js
- InstallerController
- Gen
- nowISO
- docx-export.js
- quotation-editor.js
- settings.js
- rich-editor.js
- team.js
- .append
- accounts.js
- stock.js
- Quotation (standard Qt26193 style)
- NSObject
- admin.js
- docs.py
- Data
- invoice-editor.js
- word.py
- employees.js
- quotation-editor.html (Quotation editor)
- boq-editor.js
- .marketingSummary
- price-lists.js
- String
- sidebar.js
- sheet.py
- delivery-note-editor.js
- paragraph-format.js
- URL
- Terms and Conditions
- NativeBridge
- Quotation Qt26193 Page 1 (scaffolding rental quotation)
- Updater
- ProjectRef
- main.swift
- dashboard.js
- signed-copy.js
- letter-editor.js
- letters.js
- LaunchScreen
- initPartyPage
- line-discount.js
- .deliverPDF
- user.js
- ScaffoldPro App Icon Logo (SVG)
- install-steps.sh
- projects.js
- nonBlank
- SheetUpdateScreen
- ScaffoldPro App Icon (rounded-square navy tile with scaffold grid)
- .finishLaunching
- connections.js
- ScaffoldPro App Icon (1024px)
- doc-select.js
- icons.js
- CLAUDE.md (project instructions)
- askpass.sh
- Scaffold-Pro README (title only)
- doc-language.js
- chat.js
- controls.js
- Double
- calendar.js
- UpdateChecker
- keep-focus.js
- file-drop.js
- item-picker.js
- dialogs.js
- bridge.js
- PriceListItem
- project-work.js
- tasks.js
- doc-authors.js
- announcements.js
- hover-menu.js
- widgets.js
- multiply.js
- WebServer
- delivery-rates.js
- .layout
- .interpret
- .write
- marketing-overview.js
- JSONStore
- RelinkTarget
- .updateLetter
- undo.js
- nextDocumentNumber
- LetterParagraph

## God Nodes (most connected - your core abstractions)
1. `AppDatabase` - 403 edges
2. `NativeBridge` - 129 edges
3. `nowISO()` - 85 edges
4. `PDFGenerator` - 82 edges
5. `nonBlank()` - 79 edges
6. `TeamSync` - 61 edges
7. `makeId()` - 51 edges
8. `AppDelegate` - 50 edges
9. `Gen` - 43 edges
10. `doubleOf()` - 42 edges

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

## Communities (102 total, 15 thin omitted)

### Community 0 - "PDFGenerator"
Cohesion: 0.06
Nodes (34): BQSheetRenderer, .rule, hangingItem(), HangingStyle, bullet, label, marker, hangingTextOffset() (+26 more)

### Community 1 - "AppDatabase"
Cohesion: 0.05
Nodes (8): AppDatabase, .chatFilesFolder, .priceListsAreSeeded, .signaturesFolder, Lead, PriceList, safeFileBaseName(), UserProfile

### Community 2 - "AppDelegate"
Cohesion: 0.11
Nodes (3): AppDelegate, .autoUpdate, UpdateInfo

### Community 3 - "TeamSync"
Cohesion: 0.10
Nodes (15): Entry, GitHubToken, .file, Scan, TeamSync, .appVersion, .computerName, .configuredFolder (+7 more)

### Community 4 - "CloudBackupManager"
Cohesion: 0.09
Nodes (16): BackupError, BackupManager, BackupManifest, BackupSummary, CloudBackupManager, .defaultFolder, .enabled, .folder (+8 more)

### Community 5 - "marketing.js"
Cohesion: 0.21
Nodes (21): closeLead(), esc(), exportReferences(), init(), leads, load(), money(), openLead() (+13 more)

### Community 6 - "delivery-schedule.js"
Cohesion: 0.40
Nodes (12): copyFromBOQ(), dayWeight(), exportCSV(), load(), materials(), refresh(), render(), scheduled() (+4 more)

### Community 7 - "project-detail.js"
Cohesion: 0.11
Nodes (48): choosePricing(), chosenNotes(), createNewBOQ(), createNewDeliveryNote(), createNewInvoice(), createNewLetter(), createNewQuotation(), currentBOQs (+40 more)

### Community 9 - "Gen"
Cohesion: 0.08
Nodes (7): body(), font(), Gen, times(), width(), layout(), text_x()

### Community 10 - "nowISO"
Cohesion: 0.10
Nodes (6): LeadSaveResult, makeId(), nowISO(), SeedPriceItem, spProductItemId(), validDay()

### Community 11 - "docx-export.js"
Cohesion: 0.18
Nodes (33): border(), buildLetterDocx(), buildSheetDocx(), cellParagraph(), closing(), crc32(), documentXML(), exportWord() (+25 more)

### Community 12 - "quotation-editor.js"
Cohesion: 0.13
Nodes (37): addDeliveryCharge(), addFromPicker(), allowStatusChange(), BLOCK_KINDS, blockCall(), esc(), formatAdjustment(), getQuotationIdFromURL() (+29 more)

### Community 13 - "settings.js"
Cohesion: 0.11
Nodes (43): afterRestore(), allMaterials(), createBackup(), DEFAULT_MANPOWER_RATES, defaultBOQItems, escAttr(), formatBytes(), formatWhen() (+35 more)

### Community 14 - "rich-editor.js"
Cohesion: 0.26
Nodes (15): applySize(), applySpacing(), cellStyle(), changed(), currentCell(), currentSize(), exec(), focus() (+7 more)

### Community 15 - "team.js"
Cohesion: 0.19
Nodes (19): collapsed, deviceRow(), esc(), extraTeams, groups(), initials(), load(), openPerson() (+11 more)

### Community 16 - ".append"
Cohesion: 0.11
Nodes (22): .markupRoundsUp, .minimumMonthlyRental, BOQCharge, BOQDetail, BOQRatesSection, Client, CompanySettings, DeliveryNote (+14 more)

### Community 17 - "accounts.js"
Cohesion: 0.17
Nodes (33): addLiabilityPayment(), cents(), closeExpense(), closeLiability(), csvLine(), deleteExpense(), deleteLiability(), esc() (+25 more)

### Community 18 - "stock.js"
Cohesion: 0.22
Nodes (25): closeModal(), csvLine(), detailRow(), esc(), exportCSV(), filteredItems(), filteredMovements(), findItem() (+17 more)

### Community 19 - "Quotation (standard Qt26193 style)"
Cohesion: 0.17
Nodes (17): BQ-CRBC-1635 PROFICIENCY QUOTATION sheet (A4 landscape), Qt26193 sample quotation screenshots, Reference documents README, Document lifecycle rules (Draft/Issued/Cancelled), Letterhead layout (from sample quotation Qt26193), Accounts (receivables, payments, expenses), Bill of Quantities (BOQ), BQ sheet landscape (with prices) / portrait (no prices) (+9 more)

### Community 21 - "admin.js"
Cohesion: 0.19
Nodes (21): admin.html (Admin page: workers, company docs), Worker and company document expiry reminders, ADMIN_DOC_CATEGORIES, adminDocs, applyAdminDocSearch(), closeWorkerModal(), daysUntil(), escapeAttr() (+13 more)

### Community 22 - "docs.py"
Cohesion: 0.19
Nodes (20): boq(), companySig(), dn(), dn_short(), invoice(), keyTermsText(), isPay(), money() (+12 more)

### Community 23 - "Data"
Cohesion: 0.09
Nodes (8): Change, SharedStringsParser, Step, UndoJournal, .canRedo, .canUndo, WorksheetParser, XMLAttributeCollector

### Community 24 - "invoice-editor.js"
Cohesion: 0.21
Nodes (20): addFromPicker(), allowStatusChange(), defaultPrice(), esc(), getInvoiceIdFromURL(), init(), loadDetail(), localDay() (+12 more)

### Community 25 - "word.py"
Cohesion: 0.13
Nodes (6): render(), squircle_mask(), thick_line(), Export Word (.docx) matching PDF layout, PDF layout preview tool README, letterhead_png()

### Community 26 - "employees.js"
Cohesion: 0.20
Nodes (28): basePay(), closeEmployee(), closePayroll(), deleteEmployee(), esc(), exportCSV(), fillFromWorker(), formValues() (+20 more)

### Community 27 - "quotation-editor.html (Quotation editor)"
Cohesion: 0.22
Nodes (13): boq-editor.html (Bill of Quantities editor), delivery-note-editor.html (Delivery Note editor), Document export actions (PDF, Word, Print, Locate File, Delete), invoice-editor.html (Invoice editor), esc(), refresh(), Price list sources (SP Material and Price List 2026, SCAFOM), price-lists.html (Material List page) (+5 more)

### Community 28 - "boq-editor.js"
Cohesion: 0.20
Nodes (22): addFromPicker(), escAttr(), getBOQIdFromURL(), init(), loadDetail(), makeQuotation(), money(), multiply (+14 more)

### Community 29 - ".marketingSummary"
Cohesion: 0.23
Nodes (10): AccountsData, AccountsInvoice, AccountsPayment, Expense, Invoice, MarketingFollowUp, MarketingMonth, MarketingQuote (+2 more)

### Community 30 - "price-lists.js"
Cohesion: 0.16
Nodes (27): allItemsForCurrentList, applyFilters(), applyImport(), esc(), groupByCategory(), handleCell(), init(), lastShownItems (+19 more)

### Community 32 - "sidebar.js"
Cohesion: 0.19
Nodes (15): asNumber(), build(), cellValue(), close(), enhance(), highlight(), icon(), ICONS (+7 more)

### Community 33 - "sheet.py"
Cohesion: 0.22
Nodes (13): fit(), font(), kg(), law_check(), layout(), text_box(), money(), qty() (+5 more)

### Community 34 - "delivery-note-editor.js"
Cohesion: 0.22
Nodes (19): addFromPicker(), allowStatusChange(), getIdFromURL(), importFromQuotation(), init(), loadDetail(), loadQuotationChoices(), localDay() (+11 more)

### Community 35 - "paragraph-format.js"
Cohesion: 0.31
Nodes (13): bullets(), changed(), esc(), hangingIndent(), hangingItem(), indent(), labelSplit(), numbering() (+5 more)

### Community 36 - "URL"
Cohesion: 0.11
Nodes (6): FileStorage, .administrationRoot, .appRoot, .legacyBackupsRoot, .projectsRoot, PDFAttachments

### Community 37 - "Terms and Conditions"
Cohesion: 0.19
Nodes (13): Quotation Qt26193 Page 2 (Terms and Signature Page), Remainder of Page Intentionally Blank Notice, Lingma Construction & Engineering Co. Ltd. (client, unsigned: Position, Date blank), Delivery Term, Company Address and Contact Footer, Proficiency (HK) Limited Letterhead, Modification Term, Order Acceptance and Validity Clause (+5 more)

### Community 38 - "NativeBridge"
Cohesion: 0.10
Nodes (5): FileActionResult, fileIsPresent(), NativeBridge, SimpleResult, whenDownloaded()

### Community 39 - "Quotation Qt26193 Page 1 (scaffolding rental quotation)"
Cohesion: 0.20
Nodes (11): Client Address Block (Lingma Construction & Engineering Co. Ltd.), Delivery Charges Section (D1, HK$1,200/truck/trip x 2 = HK$2,400), Footer (company address, tel, email, fax, page number), Item Table (No, Description, Unit Rate per Month, Qty, Total Price; 13 rental items), Letterhead (Proficiency (HK) Limited, bilingual, orange rule), Quotation Qt26193 Page 1 (scaffolding rental quotation), Reference Block (Our Ref Qt26193, Site Ref MTR 1601, Date 22 Sep 2026, By Email Only), Salutation and Intro Paragraph (Dear Sir / Madam, thank you for your inquiry) (+3 more)

### Community 40 - "Updater"
Cohesion: 0.24
Nodes (3): Updater, .failureNoteURL, .gitHubDesktopURL

### Community 41 - "ProjectRef"
Cohesion: 0.22
Nodes (10): PartyColumn, PartyDetail, ProjectListEntry, ProjectRef, SearchResult, StockData, StockItemRow, StockMovement (+2 more)

### Community 42 - "main.swift"
Cohesion: 0.06
Nodes (84): CoreGraphics, CoreText, CryptoKit, Network, PDFKit, AccountsLiability, ActivityEntry, ActivityRow (+76 more)

### Community 43 - "dashboard.js"
Cohesion: 0.21
Nodes (23): chargeCell(), day(), DOC_KINDS, esc(), limitList(), loadDashboard(), madeBy(), money() (+15 more)

### Community 44 - "signed-copy.js"
Cohesion: 0.31
Nodes (8): base64Of(), dropTarget(), fromFile(), remove(), report(), setNotNeeded(), upload(), Signed quotation copy upload workflow

### Community 45 - "letter-editor.js"
Cohesion: 0.37
Nodes (12): esc(), flush(), init(), loadDetail(), localDay(), queueBodySave(), render(), saveBody() (+4 more)

### Community 46 - "letters.js"
Cohesion: 0.30
Nodes (11): clients, create(), dayText(), esc(), init(), letters, load(), openNew() (+3 more)

### Community 48 - "initPartyPage"
Cohesion: 0.20
Nodes (17): accounts.html (Accounts page), clients.html (Clients page), index.html (Dashboard), escapeHTML(), initPartyPage(), closeSheet(), importExcel(), openSheet() (+9 more)

### Community 49 - "line-discount.js"
Cohesion: 0.50
Nodes (8): build(), cents(), close(), money(), rateAfter(), save(), updateFields(), updatePreview()

### Community 50 - ".deliverPDF"
Cohesion: 0.19
Nodes (5): PDFExportResult, PDFMode, export, print, word

### Community 51 - "user.js"
Cohesion: 0.42
Nodes (10): COLOURS, esc(), initials(), load(), renderHead(), renderLists(), renderStats(), setColour() (+2 more)

### Community 53 - "ScaffoldPro App Icon Logo (SVG)"
Cohesion: 0.39
Nodes (7): ScaffoldPro App Icon Logo (SVG), Ledgers (horizontal bars), Navy gradient rounded-square icon body (macOS icon grid 824x824), Modular ringlock-style scaffold bay motif, Rosette connectors (3x3 grid of nodes), Safety-yellow diagonal brace, Standards (vertical posts) and base plates

### Community 54 - "install-steps.sh"
Cohesion: 0.43
Nodes (7): finished(), PATH, progress(), install-steps.sh script, status(), step(), use_brew()

### Community 55 - "projects.js"
Cohesion: 0.36
Nodes (6): allProjects, applySearch(), closeModal(), refresh(), renderProjects(), saveProject()

### Community 56 - "nonBlank"
Cohesion: 0.10
Nodes (3): DocAuthors, Letter, nonBlank()

### Community 57 - "SheetUpdateScreen"
Cohesion: 0.11
Nodes (5): LaunchWindow, .canBecomeKey, .canBecomeMain, SheetUpdateScreen, UpdateScreen

### Community 58 - "ScaffoldPro App Icon (rounded-square navy tile with scaffold grid)"
Cohesion: 0.33
Nodes (5): ScaffoldPro App Icon (rounded-square navy tile with scaffold grid), ScaffoldPro App Icon Preview Sheet, Navy Gradient Background Tile, Scaffold Frame Motif (vertical standards, horizontal ledgers, round node connectors), Yellow Diagonal Brace Accent

### Community 59 - ".finishLaunching"
Cohesion: 0.12
Nodes (8): LetterColumnKind, center, left, money, right, weight, TitlebarDragView, .mouseDownCanMoveWindow

### Community 60 - "connections.js"
Cohesion: 0.36
Nodes (8): applyFocus(), buildLinks(), draw(), drawLines(), openLink(), startConnect(), startProject(), wireCards()

### Community 61 - "ScaffoldPro App Icon (1024px)"
Cohesion: 0.67
Nodes (4): ScaffoldPro App Icon (1024px), Yellow Diagonal Brace Accent, Navy Gradient Rounded-Square Background, Scaffold Frame Motif (3x3 grid of standards, ledgers and node rosettes)

### Community 63 - "icons.js"
Cohesion: 1.00
Nodes (3): iconize(), scan(), start()

### Community 67 - "doc-language.js"
Cohesion: 0.83
Nodes (3): init(), select(), show()

### Community 68 - "chat.js"
Cohesion: 0.15
Nodes (29): ago(), bodyHTML(), closePops(), convAvatar(), dayLabel(), fileURL(), grow(), insertAtCursor() (+21 more)

### Community 69 - "controls.js"
Cohesion: 0.32
Nodes (11): buildStepper(), closeCalendar(), enhanceSelect(), hideStepper(), openCalendar(), outsideCalendar(), placeStepper(), scan() (+3 more)

### Community 70 - "Double"
Cohesion: 0.14
Nodes (17): BillOfQuantities, BOQLineItem, ChargeSplit, decimalOf(), DeliveryNoteLineItem, DeliveryRate, doubleOf(), InvoicePayment (+9 more)

### Community 71 - "calendar.js"
Cohesion: 0.22
Nodes (18): agenda, chip(), COLOR, esc(), events, go(), gridStart(), hidden (+10 more)

### Community 72 - "UpdateChecker"
Cohesion: 0.46
Nodes (3): UpdateChecker, .authArgs, .canCheck

### Community 73 - "keep-focus.js"
Cohesion: 0.80
Nodes (4): alike(), remember(), restore(), signature()

### Community 74 - "file-drop.js"
Cohesion: 0.60
Nodes (3): scroller(), step(), stop()

### Community 75 - "item-picker.js"
Cohesion: 0.67
Nodes (5): edges(), esc(), groupBox(), render(), watchEdges()

### Community 76 - "dialogs.js"
Cohesion: 0.53
Nodes (4): build(), ensureStyles(), show(), split()

### Community 77 - "bridge.js"
Cohesion: 0.12
Nodes (14): ScaffoldPro audit against the master prompt, Bugs found and fixed in audit pass, Master development prompt (67 sections), Not built yet (suggested order), YYNNN project numbering with override validation, pick_sdk(), SDKROOT, install.sh script (+6 more)

### Community 78 - "PriceListItem"
Cohesion: 0.17
Nodes (4): chineseMaterialName(), PriceListItem, QuotationBlock, WorkerError

### Community 79 - "project-work.js"
Cohesion: 0.37
Nodes (12): addDays(), dueList(), exportRegister(), load(), loadInspections(), loadTasks(), newTask(), openInspection() (+4 more)

### Community 80 - "tasks.js"
Cohesion: 0.36
Nodes (8): esc(), filtered(), load(), people, projects, render(), rows, setView()

### Community 81 - "doc-authors.js"
Cohesion: 0.60
Nodes (3): chainText(), esc(), show()

### Community 82 - "announcements.js"
Cohesion: 0.57
Nodes (6): compose(), draw(), refresh(), render(), sheet(), when()

### Community 83 - "hover-menu.js"
Cohesion: 0.43
Nodes (4): attach(), forSelect(), pickInSelect(), selectItems()

### Community 86 - "widgets.js"
Cohesion: 0.30
Nodes (13): apply(), bar(), columns(), drawTray(), guides(), handle(), pack(), refresh() (+5 more)

### Community 88 - "multiply.js"
Cohesion: 0.47
Nodes (7): apply(), build(), close(), open(), preview(), scaled(), undoToast()

### Community 90 - "WebServer"
Cohesion: 0.13
Nodes (7): HTTPRequest, WebServer, .enabled, .hasPassword, .port, .sessions, WebSession

### Community 91 - "delivery-rates.js"
Cohesion: 0.67
Nodes (5): build(), label(), open(), plan(), weight()

### Community 92 - ".layout"
Cohesion: 0.18
Nodes (14): BQSheet, SheetLayout, SheetRow, UndoResult, WordColumn, WordFont, WordInfoRow, WordLayout (+6 more)

### Community 93 - ".interpret"
Cohesion: 0.25
Nodes (5): ParsedPriceRow, PriceSheetInterpreter, sequencePart(), SpreadsheetReader, SpreadsheetSheet

### Community 94 - ".write"
Cohesion: 0.24
Nodes (3): Authorship, SpreadsheetWriter, StoreFile

### Community 95 - "marketing-overview.js"
Cohesion: 0.28
Nodes (15): countTo(), niceStep(), pickMonth(), refresh(), render(), renderChart(), renderChips(), renderClients() (+7 more)

### Community 96 - "JSONStore"
Cohesion: 0.18
Nodes (8): JSONStore, .isEmpty, Backup and Restore (atomic, local automatic), Automatic iCloud backup to William's Work, Quotation Key Terms with hanging-indent formatting, Settings (company info, numbering, standard quotation), Share with Other Macs (iCloud change logs), Workers and administrative documents

### Community 97 - "RelinkTarget"
Cohesion: 0.40
Nodes (5): RelinkTarget, adminDocument, document, drawing, workerDocument

### Community 99 - "undo.js"
Cohesion: 0.83
Nodes (3): afterReload(), appUndo(), toast()

### Community 101 - "LetterParagraph"
Cohesion: 0.40
Nodes (6): formattedParagraphs(), LetterParagraph, hanging, term, text, paymentTermParagraphs()

## Knowledge Gaps
- **142 isolated node(s):** `SDKROOT`, `askpass.sh script`, `PATH`, `PILL`, `STATUS_TEXT` (+137 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 256 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **15 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PDFGenerator` connect `PDFGenerator` to `JSONStore`, `Gen`, `main.swift`, `.append`, `.deliverPDF`, `Quotation (standard Qt26193 style)`, `Data`, `word.py`, `String`?**
  _High betweenness centrality (0.301) - this node is a cross-community bridge._
- **Why does `Export Word (.docx) matching PDF layout` connect `word.py` to `PDFGenerator`, `docx-export.js`?**
  _High betweenness centrality (0.245) - this node is a cross-community bridge._
- **Why does `quotation-editor.html (Quotation editor)` connect `quotation-editor.html (Quotation editor)` to `paragraph-format.js`, `docx-export.js`, `quotation-editor.js`, `signed-copy.js`, `initPartyPage`, `line-discount.js`?**
  _High betweenness centrality (0.099) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `AppDatabase` (e.g. with `.restore()` and `.handle()`) actually correct?**
  _`AppDatabase` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `SDKROOT`, `askpass.sh script`, `PATH` to the rest of the system?**
  _142 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `PDFGenerator` be split into smaller, more focused modules?**
  _Cohesion score 0.05720606826801517 - nodes in this community are weakly interconnected._
- **Should `AppDatabase` be split into smaller, more focused modules?**
  _Cohesion score 0.05311836020497438 - nodes in this community are weakly interconnected._
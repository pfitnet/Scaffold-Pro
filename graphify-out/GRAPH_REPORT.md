# Graph Report - Scaffold-Pro  (2026-10-03)

## Corpus Check
- 81 files · ~313,824 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 35 file(s) not represented in the graph (top: .whl 16, .ttf 6, (none) 4)

## Summary
- 2666 nodes · 9986 edges · 112 communities (92 shown, 20 thin omitted)
- Extraction: 95% EXTRACTED · 5% INFERRED · 0% AMBIGUOUS · INFERRED: 451 edges (avg confidence: 0.83)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `240c237d`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- PDFGenerator
- AppDatabase
- AppDelegate
- TeamSync
- .getCompanySettings
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
- main.swift
- invoice-editor.js
- make_icon.py
- employees.js
- quotation-editor.html (Quotation editor)
- boq-editor.js
- qe
- price-lists.js
- docx-preview.min.js
- sidebar.js
- sheet.py
- delivery-note-editor.js
- paragraph-format.js
- Double
- Terms and Conditions
- NativeBridge
- Quotation Qt26193 Page 1 (scaffolding rental quotation)
- Updater
- FileStorage
- Bool
- dashboard.js
- signed-copy.js
- letter-editor.js
- letters.js
- LaunchScreen
- initPartyPage
- line-discount.js
- .getBOQ
- user.js
- ScaffoldPro App Icon Logo (SVG)
- install-steps.sh
- projects.js
- JSONStore
- Void
- ScaffoldPro App Icon (rounded-square navy tile with scaffold grid)
- UpdateChecker
- connections.js
- ScaffoldPro App Icon (1024px)
- doc-select.js
- icons.js
- CLAUDE.md (project instructions)
- askpass.sh
- Scaffold-Pro README (title only)
- UndoJournal
- chat.js
- Data
- .getQuotationDetail
- calendar.js
- .attr
- keep-focus.js
- file-drop.js
- item-picker.js
- dialogs.js
- bridge.js
- .splitQuotation
- project-work.js
- tasks.js
- doc-authors.js
- announcements.js
- hover-menu.js
- widgets.js
- .elements
- multiply.js
- URL
- WebServer
- delivery-rates.js
- .accountsData
- CompanySettings
- .finishLaunching
- marketing-overview.js
- .parseDefaultProperties
- RelinkTarget
- evaluate
- undo.js
- String
- ProjectRef
- jszip.min.js
- c
- .layout
- .writeXLSX
- index.html (Dashboard)
- doc-preview.js

## God Nodes (most connected - your core abstractions)
1. `AppDatabase` - 413 edges
2. `NativeBridge` - 141 edges
3. `Quotation` - 89 edges
4. `nowISO()` - 87 edges
5. `nonBlank()` - 83 edges
6. `PDFGenerator` - 83 edges
7. `qe` - 81 edges
8. `TeamSync` - 61 edges
9. `oe` - 53 edges
10. `makeId()` - 52 edges

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

## Communities (112 total, 20 thin omitted)

### Community 0 - "PDFGenerator"
Cohesion: 0.07
Nodes (26): BQSheetRenderer, .rule, Key, LetterColumn, LetterDocument, LetterInfoRow, LetterOpening, LetterSignature (+18 more)

### Community 1 - "AppDatabase"
Cohesion: 0.05
Nodes (11): AppDatabase, .chatFilesFolder, .priceListsAreSeeded, .signaturesFolder, isoFromDay(), note, PriceList, ProjectStats (+3 more)

### Community 2 - "AppDelegate"
Cohesion: 0.12
Nodes (3): AppDelegate, .autoUpdate, UpdateInfo

### Community 3 - "TeamSync"
Cohesion: 0.09
Nodes (15): Entry, GitHubToken, .file, Scan, TeamSync, .appVersion, .computerName, .configuredFolder (+7 more)

### Community 4 - ".getCompanySettings"
Cohesion: 0.25
Nodes (3): .markupRoundsUp, .minimumMonthlyRental, nextDocumentNumber()

### Community 5 - "marketing.js"
Cohesion: 0.21
Nodes (21): closeLead(), esc(), exportReferences(), init(), leads, load(), money(), openLead() (+13 more)

### Community 6 - "delivery-schedule.js"
Cohesion: 0.40
Nodes (12): copyFromBOQ(), dayWeight(), exportCSV(), load(), materials(), refresh(), render(), scheduled() (+4 more)

### Community 7 - "project-detail.js"
Cohesion: 0.09
Nodes (61): activityTimeline(), choosePricing(), chosenNotes(), createNewBOQ(), createNewDeliveryNote(), createNewInvoice(), createNewLetter(), createNewQuotation() (+53 more)

### Community 9 - "Gen"
Cohesion: 0.07
Nodes (9): body(), font(), Gen, refColon(), times(), width(), layout(), letterhead_png() (+1 more)

### Community 10 - "nowISO"
Cohesion: 0.11
Nodes (8): DeliveryNote, LeadSaveResult, makeId(), nonBlank(), nowISO(), SeedPriceItem, validDay(), WorkerError

### Community 11 - "docx-export.js"
Cohesion: 0.17
Nodes (37): border(), buildCombinedDocx(), buildLetterDocx(), buildSheetDocx(), cellParagraph(), closing(), crc32(), documentXML() (+29 more)

### Community 12 - "quotation-editor.js"
Cohesion: 0.12
Nodes (43): addDeliveryCharge(), addFromPicker(), allowStatusChange(), askSubsidiaries(), BLOCK_KINDS, blockCall(), esc(), formatAdjustment() (+35 more)

### Community 13 - "settings.js"
Cohesion: 0.10
Nodes (46): afterRestore(), allMaterials(), createBackup(), DEFAULT_MANPOWER_RATES, defaultBOQItems, escAttr(), formatBytes(), formatWhen() (+38 more)

### Community 14 - "rich-editor.js"
Cohesion: 0.26
Nodes (15): applySize(), applySpacing(), cellStyle(), changed(), currentCell(), currentSize(), exec(), focus() (+7 more)

### Community 15 - "team.js"
Cohesion: 0.19
Nodes (19): collapsed, deviceRow(), esc(), extraTeams, groups(), initials(), load(), openPerson() (+11 more)

### Community 16 - ".append"
Cohesion: 0.13
Nodes (14): documentItemName(), formatMoney(), formatQuantity(), formattedParagraphs(), LetterParagraph, hanging, term, text (+6 more)

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

### Community 23 - "main.swift"
Cohesion: 0.06
Nodes (43): CoreGraphics, CoreText, CryptoKit, Network, PDFKit, Client, DataLocations, DeliveryNoteDetail (+35 more)

### Community 24 - "invoice-editor.js"
Cohesion: 0.21
Nodes (20): addFromPicker(), allowStatusChange(), defaultPrice(), esc(), getInvoiceIdFromURL(), init(), loadDetail(), localDay() (+12 more)

### Community 25 - "make_icon.py"
Cohesion: 0.47
Nodes (3): render(), squircle_mask(), thick_line()

### Community 26 - "employees.js"
Cohesion: 0.20
Nodes (28): basePay(), closeEmployee(), closePayroll(), deleteEmployee(), esc(), exportCSV(), fillFromWorker(), formValues() (+20 more)

### Community 27 - "quotation-editor.html (Quotation editor)"
Cohesion: 0.22
Nodes (13): boq-editor.html (Bill of Quantities editor), delivery-note-editor.html (Delivery Note editor), Document export actions (PDF, Word, Print, Locate File, Delete), invoice-editor.html (Invoice editor), esc(), refresh(), Price list sources (SP Material and Price List 2026, SCAFOM), price-lists.html (Material List page) (+5 more)

### Community 28 - "boq-editor.js"
Cohesion: 0.20
Nodes (23): addFromPicker(), escAttr(), getBOQIdFromURL(), init(), loadDetail(), makeQuotation(), money(), multiply (+15 more)

### Community 30 - "price-lists.js"
Cohesion: 0.15
Nodes (28): allItemsForCurrentList, applyFilters(), applyImport(), esc(), groupByCategory(), handleCell(), init(), lastShownItems (+20 more)

### Community 31 - "docx-preview.min.js"
Cohesion: 0.05
Nodes (30): be, ce, D(), E(), ee(), F(), fe, G (+22 more)

### Community 32 - "sidebar.js"
Cohesion: 0.19
Nodes (15): asNumber(), build(), cellValue(), close(), enhance(), highlight(), icon(), ICONS (+7 more)

### Community 33 - "sheet.py"
Cohesion: 0.10
Nodes (19): Export Word (.docx) matching PDF layout, PDF layout preview tool README, fit(), font(), kg(), law_check(), layout(), text_box() (+11 more)

### Community 34 - "delivery-note-editor.js"
Cohesion: 0.22
Nodes (19): addFromPicker(), allowStatusChange(), getIdFromURL(), importFromQuotation(), init(), loadDetail(), loadQuotationChoices(), localDay() (+11 more)

### Community 35 - "paragraph-format.js"
Cohesion: 0.31
Nodes (13): bullets(), changed(), esc(), hangingIndent(), hangingItem(), indent(), labelSplit(), numbering() (+5 more)

### Community 36 - "Double"
Cohesion: 0.19
Nodes (19): AccountsLiability, BillOfQuantities, BOQCharge, BOQDetail, BOQLineItem, BOQRatesSection, BOQSummary, decimalOf() (+11 more)

### Community 37 - "Terms and Conditions"
Cohesion: 0.19
Nodes (13): Quotation Qt26193 Page 2 (Terms and Signature Page), Remainder of Page Intentionally Blank Notice, Lingma Construction & Engineering Co. Ltd. (client, unsigned: Position, Date blank), Delivery Term, Company Address and Contact Footer, Proficiency (HK) Limited Letterhead, Modification Term, Order Acceptance and Validity Clause (+5 more)

### Community 38 - "NativeBridge"
Cohesion: 0.09
Nodes (4): FileActionResult, fileIsPresent(), NativeBridge, SimpleResult

### Community 39 - "Quotation Qt26193 Page 1 (scaffolding rental quotation)"
Cohesion: 0.20
Nodes (11): Client Address Block (Lingma Construction & Engineering Co. Ltd.), Delivery Charges Section (D1, HK$1,200/truck/trip x 2 = HK$2,400), Footer (company address, tel, email, fax, page number), Item Table (No, Description, Unit Rate per Month, Qty, Total Price; 13 rental items), Letterhead (Proficiency (HK) Limited, bilingual, orange rule), Quotation Qt26193 Page 1 (scaffolding rental quotation), Reference Block (Our Ref Qt26193, Site Ref MTR 1601, Date 22 Sep 2026, By Email Only), Salutation and Intro Paragraph (Dear Sir / Madam, thank you for your inquiry) (+3 more)

### Community 40 - "Updater"
Cohesion: 0.24
Nodes (3): Updater, .failureNoteURL, .gitHubDesktopURL

### Community 41 - "FileStorage"
Cohesion: 0.06
Nodes (24): BackupError, BackupManager, BackupManifest, BackupSummary, CloudBackupManager, .defaultFolder, .enabled, .folder (+16 more)

### Community 42 - "Bool"
Cohesion: 0.06
Nodes (65): AdminDocument, AdminDocumentSummary, Announcement, AnnouncementRow, AnnouncementsPage, AutoBackupStatus, BackupResult, BOQActionResult (+57 more)

### Community 43 - "dashboard.js"
Cohesion: 0.16
Nodes (29): chargeCell(), countUp(), day(), DOC_KINDS, esc(), growIn(), limitList(), loadDashboard() (+21 more)

### Community 44 - "signed-copy.js"
Cohesion: 0.36
Nodes (7): base64Of(), dropTarget(), fromFile(), remove(), report(), setNotNeeded(), upload()

### Community 45 - "letter-editor.js"
Cohesion: 0.37
Nodes (12): esc(), flush(), init(), loadDetail(), localDay(), queueBodySave(), render(), saveBody() (+4 more)

### Community 46 - "letters.js"
Cohesion: 0.30
Nodes (11): clients, create(), dayText(), esc(), init(), letters, load(), openNew() (+3 more)

### Community 48 - "initPartyPage"
Cohesion: 0.29
Nodes (11): escapeHTML(), initPartyPage(), closeSheet(), importExcel(), openSheet(), refresh(), render(), renderRelated() (+3 more)

### Community 49 - "line-discount.js"
Cohesion: 0.50
Nodes (8): build(), cents(), close(), money(), rateAfter(), save(), updateFields(), updatePreview()

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
Cohesion: 0.17
Nodes (23): ago(), allProjects, applySearch(), card(), closeModal(), COLOUR, contextMenu(), docChips() (+15 more)

### Community 56 - "JSONStore"
Cohesion: 0.18
Nodes (8): JSONStore, .isEmpty, Backup and Restore (atomic, local automatic), Automatic iCloud backup to William's Work, Quotation Key Terms with hanging-indent formatting, Settings (company info, numbering, standard quotation), Share with Other Macs (iCloud change logs), Workers and administrative documents

### Community 57 - "Void"
Cohesion: 0.10
Nodes (5): LaunchWindow, .canBecomeKey, .canBecomeMain, SheetUpdateScreen, UpdateScreen

### Community 58 - "ScaffoldPro App Icon (rounded-square navy tile with scaffold grid)"
Cohesion: 0.33
Nodes (5): ScaffoldPro App Icon (rounded-square navy tile with scaffold grid), ScaffoldPro App Icon Preview Sheet, Navy Gradient Background Tile, Scaffold Frame Motif (vertical standards, horizontal ledgers, round node connectors), Yellow Diagonal Brace Accent

### Community 59 - "UpdateChecker"
Cohesion: 0.46
Nodes (3): UpdateChecker, .authArgs, .canCheck

### Community 60 - "connections.js"
Cohesion: 0.36
Nodes (8): applyFocus(), buildLinks(), draw(), drawLines(), openLink(), startConnect(), startProject(), wireCards()

### Community 61 - "ScaffoldPro App Icon (1024px)"
Cohesion: 0.67
Nodes (4): ScaffoldPro App Icon (1024px), Yellow Diagonal Brace Accent, Navy Gradient Rounded-Square Background, Scaffold Frame Motif (3x3 grid of standards, ledgers and node rosettes)

### Community 63 - "icons.js"
Cohesion: 1.00
Nodes (3): iconize(), scan(), start()

### Community 67 - "UndoJournal"
Cohesion: 0.22
Nodes (5): Change, Step, UndoJournal, .canRedo, .canUndo

### Community 68 - "chat.js"
Cohesion: 0.15
Nodes (29): ago(), bodyHTML(), closePops(), convAvatar(), dayLabel(), fileURL(), grow(), insertAtCursor() (+21 more)

### Community 69 - "Data"
Cohesion: 0.09
Nodes (7): Authorship, PriceSheetInterpreter, SharedStringsParser, SpreadsheetReader, SpreadsheetSheet, WorksheetParser, XMLAttributeCollector

### Community 71 - "calendar.js"
Cohesion: 0.22
Nodes (18): agenda, chip(), COLOR, esc(), events, go(), gridStart(), hidden (+10 more)

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

### Community 79 - "project-work.js"
Cohesion: 0.35
Nodes (13): addDays(), dueList(), exportRegister(), load(), loadInspections(), loadTasks(), newTask(), openInspection() (+5 more)

### Community 80 - "tasks.js"
Cohesion: 0.08
Nodes (54): buildStepper(), closeCalendar(), commitDate(), enhanceSelect(), hideStepper(), openCalendar(), outsideCalendar(), parseDate() (+46 more)

### Community 81 - "doc-authors.js"
Cohesion: 0.36
Nodes (9): ago(), buildHero(), copyText(), esc(), flowHTML(), metaHTML(), setStatus(), setupHero() (+1 more)

### Community 82 - "announcements.js"
Cohesion: 0.57
Nodes (6): compose(), draw(), refresh(), render(), sheet(), when()

### Community 83 - "hover-menu.js"
Cohesion: 0.27
Nodes (10): init(), select(), show(), attach(), exportMenu(), forSelect(), groupMenu(), linesMenu() (+2 more)

### Community 86 - "widgets.js"
Cohesion: 0.26
Nodes (15): apply(), bar(), columns(), drawTray(), guides(), handle(), load(), pack() (+7 more)

### Community 87 - ".elements"
Cohesion: 0.13
Nodes (7): ae, de(), le(), ne(), se(), v, xe()

### Community 88 - "multiply.js"
Cohesion: 0.47
Nodes (7): apply(), build(), close(), open(), preview(), scaled(), undoToast()

### Community 89 - "URL"
Cohesion: 0.13
Nodes (8): PDFAttachments, PDFExportResult, PDFMode, export, preview, print, word, PendingPreview

### Community 90 - "WebServer"
Cohesion: 0.13
Nodes (7): HTTPRequest, WebServer, .enabled, .hasPassword, .port, .sessions, WebSession

### Community 91 - "delivery-rates.js"
Cohesion: 0.67
Nodes (5): build(), label(), open(), plan(), weight()

### Community 92 - ".accountsData"
Cohesion: 0.29
Nodes (7): AccountsData, AccountsInvoice, AccountsPayment, Expense, Invoice, InvoiceDetail, InvoiceLineItem

### Community 93 - "CompanySettings"
Cohesion: 0.25
Nodes (8): ChargeSplit, CompanySettings, DefaultBOQItem, DeliveryRate, QuotationDetail, QuotationMoney, QuotationRef, QuotationSummary

### Community 94 - ".finishLaunching"
Cohesion: 0.12
Nodes (8): LetterColumnKind, center, left, money, right, weight, TitlebarDragView, .mouseDownCanMoveWindow

### Community 95 - "marketing-overview.js"
Cohesion: 0.28
Nodes (15): countTo(), niceStep(), pickMonth(), refresh(), render(), renderChart(), renderChips(), renderClients() (+7 more)

### Community 96 - ".parseDefaultProperties"
Cohesion: 0.14
Nodes (3): a(), je, ze

### Community 97 - "RelinkTarget"
Cohesion: 0.40
Nodes (5): RelinkTarget, adminDocument, document, drawing, workerDocument

### Community 98 - "evaluate"
Cohesion: 0.39
Nodes (6): evaluate(), factor(), number(), product(), sum(), showBubble()

### Community 99 - "undo.js"
Cohesion: 0.57
Nodes (6): afterReload(), appUndo(), placeOf(), showChanges(), snapshot(), toast()

### Community 100 - "String"
Cohesion: 0.07
Nodes (7): ActivityEntry, chineseMaterialName(), DeliveryNoteLineItem, DocAuthors, Letter, LetterDetail, spProductItemId()

### Community 101 - "ProjectRef"
Cohesion: 0.16
Nodes (15): ActivityRow, DashboardSummary, DocRow, MyProject, PartyColumn, PartyDetail, ProjectListEntry, ProjectRef (+7 more)

### Community 102 - "jszip.min.js"
Cohesion: 0.24
Nodes (22): A(), c(), d(), i(), n(), f(), G(), h() (+14 more)

### Community 103 - "c"
Cohesion: 0.15
Nodes (6): c(), n(), o(), s(), ve, we()

### Community 104 - ".layout"
Cohesion: 0.27
Nodes (6): BQSheet, DeliveryScheduleData, QuotationDeliveryDay, ScheduleLine, SheetLayout, SheetRow

### Community 108 - "index.html (Dashboard)"
Cohesion: 0.46
Nodes (7): accounts.html (Accounts page), clients.html (Clients page), index.html (Dashboard), initPartyPage config pattern (clients and sites), projects.html (Projects list), Signed quotation copy upload workflow, sites.html (Sites page)

### Community 109 - "doc-preview.js"
Cohesion: 0.46
Nodes (7): letterheadBands(), loadVendor(), pdf(), run(), shareFonts(), sheet(), word()

## Knowledge Gaps
- **152 isolated node(s):** `SDKROOT`, `askpass.sh script`, `PATH`, `PILL`, `STATUS_TEXT` (+147 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 310 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **20 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `PDFGenerator` connect `PDFGenerator` to `sheet.py`, `String`, `Data`, `Gen`, `Bool`, `.append`, `Quotation (standard Qt26193 style)`, `main.swift`, `JSONStore`, `URL`?**
  _High betweenness centrality (0.257) - this node is a cross-community bridge._
- **Why does `Export Word (.docx) matching PDF layout` connect `sheet.py` to `PDFGenerator`, `docx-export.js`?**
  _High betweenness centrality (0.217) - this node is a cross-community bridge._
- **Why does `invoice-editor.html (Invoice editor)` connect `quotation-editor.html (Quotation editor)` to `paragraph-format.js`, `docx-export.js`, `index.html (Dashboard)`, `line-discount.js`, `invoice-editor.js`?**
  _High betweenness centrality (0.087) - this node is a cross-community bridge._
- **Are the 2 inferred relationships involving `AppDatabase` (e.g. with `.restore()` and `.handle()`) actually correct?**
  _`AppDatabase` has 2 INFERRED edges - model-reasoned connections that need verification._
- **What connects `SDKROOT`, `askpass.sh script`, `PATH` to the rest of the system?**
  _152 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `PDFGenerator` be split into smaller, more focused modules?**
  _Cohesion score 0.06572068707991038 - nodes in this community are weakly interconnected._
- **Should `AppDatabase` be split into smaller, more focused modules?**
  _Cohesion score 0.05107913669064748 - nodes in this community are weakly interconnected._
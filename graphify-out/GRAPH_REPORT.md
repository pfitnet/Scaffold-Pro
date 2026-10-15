# Graph Report - Scaffold-Pro  (2026-10-15)

## Corpus Check
- 137 files · ~619,243 words
- Verdict: corpus is large enough that graph structure adds value.
- Unclassified: 52 file(s) not represented in the graph (top: .css 17, .whl 16, .ttf 6)

## Summary
- 3837 nodes · 12492 edges · 147 communities (115 shown, 32 thin omitted)
- Extraction: 84% EXTRACTED · 16% INFERRED · 0% AMBIGUOUS · INFERRED: 1989 edges (avg confidence: 0.86)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `e75c449b`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- PDFGenerator
- AppDatabase
- GoogleSheetsSync
- TeamSync
- String
- marketing.js
- delivery-schedule.js
- project-detail.js
- InstallerController
- Gen
- Models.swift
- docx-export.js
- quotation-editor.js
- settings.js
- rich-editor.js
- team.js
- .handle
- accounts.js
- main.swift
- Quotation (standard Qt26193 style)
- data.js
- String
- docs.py
- nonBlank
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
- String
- Terms and Conditions
- SheetUpdateScreen
- Quotation Qt26193 Page 1 (scaffolding rental quotation)
- Updater
- String
- String
- dashboard.js
- String
- letter-editor.js
- letters.js
- .invoiceLetterBase
- Encodable
- line-discount.js
- workers.js
- ScaffoldPro App Icon Logo (SVG)
- install-steps.sh
- projects.js
- NativeBridge
- UpdateChecker
- ScaffoldPro App Icon (rounded-square navy tile with scaffold grid)
- oe
- connections.js
- ScaffoldPro App Icon (1024px)
- .loadRelationshipPart
- LetterTableRow
- CLAUDE.md (project instructions)
- askpass.sh
- Scaffold-Pro README (title only)
- chat.js
- manpower-costs.js
- draw
- calendar.js
- initPartyPage
- keep-focus.js
- file-drop.js
- item-picker.js
- dialogs.js
- String
- 5. Recent work (Batches 147–216, newest last)
- project-work.js
- tasks.js
- TeamLink
- announcements.js
- hover-menu.js
- widgets.js
- stock.js
- multiply.js
- String
- WebServer
- delivery-rates.js
- terms-table.js
- shoot.js
- doc-authors.js
- marketing-overview.js
- .attr
- notify.js
- evaluate
- undo.js
- BackupManager
- settings-ui.js
- jszip.min.js
- formattedParagraphs
- ScaffoldPro-core.js
- manual.js
- open
- Backup and Restore (atomic, local automatic)
- .assistantCheck
- doc-preview.js
- mount
- quotation-import.js
- Assistant.swift
- Double
- doc-language.js
- 1. What ScaffoldPro is
- marketing-report.js
- doc-select.js
- settings-ai.js
- QuotationAI
- AppDelegate
- CloudBackupManager
- c
- install.sh
- ScaffoldPro: one design, every page (redesign plan)
- String
- Bool
- LetterColumnKind
- RelinkTarget
- ge
- .applicationDidFinishLaunching
- CompanySettings
- at
- DocRow
- buildQuotation
- init
- quotation-columns.js
- item
- changelog.js
- MKT_QUOTES

## God Nodes (most connected - your core abstractions)
1. `AppDatabase` - 529 edges
2. `NativeBridge` - 234 edges
3. `nonBlank()` - 147 edges
4. `nowISO()` - 106 edges
5. `PDFGenerator` - 100 edges
6. `5. Recent work (Batches 147–216, newest last)` - 86 edges
7. `qe` - 81 edges
8. `TeamSync` - 71 edges
9. `makeId()` - 63 edges
10. `AppDelegate` - 56 edges

## Surprising Connections (you probably didn't know these)
- `3.1 Merges` --references--> `TeamTask`  [INFERRED]
  docs/redesign/PLAN.md → ScaffoldPro-native/Sources/Models.swift
- `3.2 Sidebar (rebuilt in `js/sidebar.js`)` --references--> `orderedNavItems()`  [INFERRED]
  docs/redesign/PLAN.md → ScaffoldPro-native/js/sidebar.js
- `5. Rollout: batches, in order` --references--> `PageBackdropView`  [INFERRED]
  docs/redesign/PLAN.md → ScaffoldPro-native/Sources/Assistant.swift
- `5. Recent work (Batches 147–216, newest last)` --references--> `PageBackdropView`  [INFERRED]
  HANDOFF.md → ScaffoldPro-native/Sources/Assistant.swift
- `1. What ScaffoldPro is` --references--> `BQSheetRenderer`  [INFERRED]
  HANDOFF.md → ScaffoldPro-native/Sources/BQSheet.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **App Icon Visual Composition** — scaffoldpro_native_icon_appicon_1024_scaffold_frame_motif, scaffoldpro_native_icon_appicon_1024_diagonal_brace, scaffoldpro_native_icon_appicon_1024_navy_rounded_square [EXTRACTED 1.00]
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

## Communities (147 total, 32 thin omitted)

### Community 0 - "PDFGenerator"
Cohesion: 0.07
Nodes (20): .total, hasInlineMarks(), LetterColumn, LetterDocument, LetterInfoRow, LetterOpening, LetterheadColor, PDFAttachments (+12 more)

### Community 1 - "AppDatabase"
Cohesion: 0.04
Nodes (14): AppDatabase, .markupRoundsUp, .priceListsAreSeeded, ProjectStats, .minimumMonthlyRental, .chatFilesFolder, .signaturesFolder, DeliveryNote (+6 more)

### Community 2 - "GoogleSheetsSync"
Cohesion: 0.13
Nodes (6): GoogleSheetsStatus, GoogleSheetsSync, .isLinked, ImportedQuotationLine, QuotationImportDraft, QuotationImportReader

### Community 3 - "TeamSync"
Cohesion: 0.07
Nodes (20): AutoBackupStatus, Entry, Key, LocalCopyManager, .active, LocalCopyStatus, Scan, TeamMember (+12 more)

### Community 5 - "marketing.js"
Cohesion: 0.20
Nodes (22): closeLead(), esc(), exportReferences(), init(), leads, load(), money(), openLead() (+14 more)

### Community 6 - "delivery-schedule.js"
Cohesion: 0.40
Nodes (12): copyFromBOQ(), dayWeight(), exportCSV(), load(), materials(), refresh(), render(), scheduled() (+4 more)

### Community 7 - "project-detail.js"
Cohesion: 0.06
Nodes (80): 4.3 Project page (`project-detail.html`), admin.html (Admin page: workers, company docs), Worker and company document expiry reminders, ADMIN_DOC_CATEGORIES, adminDocs, adminFact(), applyAdminDocSearch(), daysUntil() (+72 more)

### Community 9 - "Gen"
Cohesion: 0.08
Nodes (10): Export Word (.docx) matching PDF layout, body(), font(), Gen, refColon(), times(), width(), layout() (+2 more)

### Community 10 - "Models.swift"
Cohesion: 0.09
Nodes (57): ActivityEntry, AdminDocument, AdminDocumentSummary, AnnouncementRow, AnnouncementsPage, BackupResult, BOQActionResult, CalendarEvent (+49 more)

### Community 11 - "docx-export.js"
Cohesion: 0.16
Nodes (44): agreementParts(), border(), buildCombinedDocx(), buildDocx(), buildLetterDocx(), buildSheetDocx(), cellParagraph(), closing() (+36 more)

### Community 12 - "quotation-editor.js"
Cohesion: 0.08
Nodes (63): addDeliveryCharge(), addFromPicker(), allowStatusChange(), askSubsidiaries(), BLOCK_KINDS, blockCall(), BUYBACK_FIELDS, BUYBACK_KEYS (+55 more)

### Community 13 - "settings.js"
Cohesion: 0.10
Nodes (45): afterRestore(), allMaterials(), createBackup(), DEFAULT_MANPOWER_RATES, defaultBOQItems, escAttr(), formatBytes(), formatWhen() (+37 more)

### Community 14 - "rich-editor.js"
Cohesion: 0.26
Nodes (15): applySize(), applySpacing(), cellStyle(), changed(), currentCell(), currentSize(), exec(), focus() (+7 more)

### Community 15 - "team.js"
Cohesion: 0.13
Nodes (29): CHEVRON, collapsed, declineIt(), deviceRow(), esc(), extraTeams, factLine(), FOLDER (+21 more)

### Community 17 - "accounts.js"
Cohesion: 0.17
Nodes (33): addLiabilityPayment(), cents(), closeExpense(), closeLiability(), csvLine(), deleteExpense(), deleteLiability(), esc() (+25 more)

### Community 18 - "main.swift"
Cohesion: 0.11
Nodes (11): 2.2 Type, callNative(), refresh(), releaseWhenBuilt(), toast(), LaunchWindow, .canBecomeKey, .canBecomeMain (+3 more)

### Community 19 - "Quotation (standard Qt26193 style)"
Cohesion: 0.11
Nodes (24): BQ-CRBC-1635 PROFICIENCY QUOTATION sheet (A4 landscape), Qt26193 sample quotation screenshots, Reference documents README, ScaffoldPro audit against the master prompt, Bugs found and fixed in audit pass, Document lifecycle rules (Draft/Issued/Cancelled), Letterhead layout (from sample quotation Qt26193), Master development prompt (67 sections) (+16 more)

### Community 20 - "data.js"
Cohesion: 0.03
Nodes (65): ACCOUNTS, ACTIVITY, ALL_ITEMS, ANNOUNCE, ANNOUNCEMENTS_PAGE, BOQ, BOQ_SUMMARY, BOQ_ZONE_A (+57 more)

### Community 21 - "String"
Cohesion: 0.08
Nodes (29): annexureLabel(), Authorship, CellTextLine, ChatConversation, ChatPage, chineseMaterialName(), currencyDisplay(), decodeCellLine() (+21 more)

### Community 22 - "docs.py"
Cohesion: 0.20
Nodes (20): boq(), companySig(), dn(), dn_short(), invoice(), keyTermsText(), isPay(), money() (+12 more)

### Community 23 - "nonBlank"
Cohesion: 0.08
Nodes (9): convertedPrice(), decimalOf(), doubleOf(), roundToCents(), WorkerError, validDay(), makeId(), nonBlank() (+1 more)

### Community 24 - "invoice-editor.js"
Cohesion: 0.20
Nodes (21): addFromPicker(), allowStatusChange(), defaultPrice(), esc(), getInvoiceIdFromURL(), init(), loadDetail(), localDay() (+13 more)

### Community 25 - "make_icon.py"
Cohesion: 0.24
Nodes (5): render(), squircle_mask(), thick_line(), box(), PDF layout preview tool README

### Community 26 - "employees.js"
Cohesion: 0.20
Nodes (28): basePay(), closeEmployee(), closePayroll(), deleteEmployee(), esc(), exportCSV(), fillFromWorker(), formValues() (+20 more)

### Community 27 - "quotation-editor.html (Quotation editor)"
Cohesion: 0.13
Nodes (20): accounts.html (Accounts page), boq-editor.html (Bill of Quantities editor), clients.html (Clients page), delivery-note-editor.html (Delivery Note editor), Document export actions (PDF, Word, Print, Locate File, Delete), index.html (Dashboard), invoice-editor.html (Invoice editor), esc() (+12 more)

### Community 28 - "boq-editor.js"
Cohesion: 0.20
Nodes (23): addFromPicker(), escAttr(), getBOQIdFromURL(), init(), loadDetail(), makeQuotation(), money(), multiply (+15 more)

### Community 30 - "price-lists.js"
Cohesion: 0.15
Nodes (28): allItemsForCurrentList, applyFilters(), applyImport(), esc(), groupByCategory(), handleCell(), init(), lastShownItems (+20 more)

### Community 31 - "docx-preview.min.js"
Cohesion: 0.05
Nodes (31): a(), ae, be, ce, D(), E(), ee(), F() (+23 more)

### Community 32 - "sidebar.js"
Cohesion: 0.16
Nodes (20): asNumber(), build(), cellValue(), close(), enhance(), highlight(), move(), NAV_ITEMS (+12 more)

### Community 33 - "sheet.py"
Cohesion: 0.16
Nodes (17): fit(), font(), kg(), law_check(), layout(), text_box(), money(), qty() (+9 more)

### Community 34 - "delivery-note-editor.js"
Cohesion: 0.22
Nodes (19): addFromPicker(), allowStatusChange(), getIdFromURL(), importFromQuotation(), init(), loadDetail(), loadQuotationChoices(), localDay() (+11 more)

### Community 35 - "paragraph-format.js"
Cohesion: 0.24
Nodes (15): bullets(), changed(), esc(), fittedHTML(), hangingIndent(), hangingItem(), indent(), inline() (+7 more)

### Community 36 - "String"
Cohesion: 0.11
Nodes (7): PDFExportResult, PDFMode, export, preview, print, word, PendingPreview

### Community 37 - "Terms and Conditions"
Cohesion: 0.19
Nodes (13): Quotation Qt26193 Page 2 (Terms and Signature Page), Remainder of Page Intentionally Blank Notice, Lingma Construction & Engineering Co. Ltd. (client, unsigned: Position, Date blank), Delivery Term, Company Address and Contact Footer, Proficiency (HK) Limited Letterhead, Modification Term, Order Acceptance and Validity Clause (+5 more)

### Community 39 - "Quotation Qt26193 Page 1 (scaffolding rental quotation)"
Cohesion: 0.20
Nodes (11): Client Address Block (Lingma Construction & Engineering Co. Ltd.), Delivery Charges Section (D1, HK$1,200/truck/trip x 2 = HK$2,400), Footer (company address, tel, email, fax, page number), Item Table (No, Description, Unit Rate per Month, Qty, Total Price; 13 rental items), Letterhead (Proficiency (HK) Limited, bilingual, orange rule), Quotation Qt26193 Page 1 (scaffolding rental quotation), Reference Block (Our Ref Qt26193, Site Ref MTR 1601, Date 22 Sep 2026, By Email Only), Salutation and Intro Paragraph (Dear Sir / Madam, thank you for your inquiry) (+3 more)

### Community 40 - "Updater"
Cohesion: 0.22
Nodes (3): Updater, .failureNoteURL, .gitHubDesktopURL

### Community 41 - "String"
Cohesion: 0.09
Nodes (14): ParsedPriceRow, PartyColumn, PartyImportPreview, PartyImportResult, PartySheet, PriceImportPreview, PriceImportResult, PriceSheetInterpreter (+6 more)

### Community 42 - "String"
Cohesion: 0.07
Nodes (22): safeFileName(), Change, currentYearSuffix(), FileStorage, .administrationRoot, .appRoot, .legacyBackupsRoot, .projectsRoot (+14 more)

### Community 43 - "dashboard.js"
Cohesion: 0.08
Nodes (50): 2.1 Colour tokens, 2.3 Shape, depth, spacing, 2.4 Icons: one family, 2.5 Components: rebuilt once in styles.css, used everywhere, 2.6 Motion system (animate skill), 2.7 One shared UI kit: `js/ui-kit.js` (new; the only new JS file), 2. The design system ("Steel & Signal"), ICON() (+42 more)

### Community 44 - "String"
Cohesion: 0.07
Nodes (45): Cocoa, CoreGraphics, CoreText, CryptoKit, Network, PDFKit, BQSheet, BQSheetRenderer (+37 more)

### Community 45 - "letter-editor.js"
Cohesion: 0.37
Nodes (12): esc(), flush(), init(), loadDetail(), localDay(), queueBodySave(), render(), saveBody() (+4 more)

### Community 46 - "letters.js"
Cohesion: 0.30
Nodes (11): clients, create(), dayText(), esc(), init(), letters, load(), openNew() (+3 more)

### Community 47 - ".invoiceLetterBase"
Cohesion: 0.12
Nodes (6): documentItemName(), InvoiceDetail, lineDiscountNote(), formatMoney(), formatQuantity(), lineDescription()

### Community 48 - "Encodable"
Cohesion: 0.24
Nodes (15): AgreementContent, AgreementParty, AgreementSection, AgreementTerm, AgreementWordLayout, WordColumn, WordFont, WordInfoRow (+7 more)

### Community 49 - "line-discount.js"
Cohesion: 0.50
Nodes (8): build(), cents(), close(), money(), rateAfter(), save(), updateFields(), updatePreview()

### Community 50 - "workers.js"
Cohesion: 0.13
Nodes (45): act(), addDroppedDocuments(), agreementHTML(), capitalAmount(), checkId(), clock(), closeSheet(), counts() (+37 more)

### Community 53 - "ScaffoldPro App Icon Logo (SVG)"
Cohesion: 0.39
Nodes (7): ScaffoldPro App Icon Logo (SVG), Ledgers (horizontal bars), Navy gradient rounded-square icon body (macOS icon grid 824x824), Modular ringlock-style scaffold bay motif, Rosette connectors (3x3 grid of nodes), Safety-yellow diagonal brace, Standards (vertical posts) and base plates

### Community 54 - "install-steps.sh"
Cohesion: 0.43
Nodes (7): finished(), PATH, progress(), install-steps.sh script, status(), step(), use_brew()

### Community 55 - "projects.js"
Cohesion: 0.11
Nodes (43): ago(), allProjects, applySearch(), bracket(), card(), closed, closeModal(), COLOUR (+35 more)

### Community 56 - "NativeBridge"
Cohesion: 0.06
Nodes (3): .scaffoldingBuyBackWording, NativeBridge, .holdingFrame

### Community 57 - "UpdateChecker"
Cohesion: 0.26
Nodes (5): GitHubToken, .file, UpdateChecker, .authArgs, .canCheck

### Community 58 - "ScaffoldPro App Icon (rounded-square navy tile with scaffold grid)"
Cohesion: 0.33
Nodes (5): ScaffoldPro App Icon (rounded-square navy tile with scaffold grid), ScaffoldPro App Icon Preview Sheet, Navy Gradient Background Tile, Scaffold Frame Motif (vertical standards, horizontal ledgers, round node connectors), Yellow Diagonal Brace Accent

### Community 60 - "connections.js"
Cohesion: 0.42
Nodes (8): applyFocus(), buildLinks(), draw(), drawLines(), openLink(), startConnect(), startProject(), wireCards()

### Community 61 - "ScaffoldPro App Icon (1024px)"
Cohesion: 0.67
Nodes (4): ScaffoldPro App Icon (1024px), Yellow Diagonal Brace Accent, Navy Gradient Rounded-Square Background, Scaffold Frame Motif (3x3 grid of standards, ledgers and node rosettes)

### Community 62 - ".loadRelationshipPart"
Cohesion: 0.22
Nodes (5): n(), s(), ve, we(), xe()

### Community 63 - "LetterTableRow"
Cohesion: 0.14
Nodes (13): AnchorKeys, DocAnchor, DocEditsPage, DocInsert, DocInserts, applyInlineMarkup(), LetterTableRow, columnTitles (+5 more)

### Community 68 - "chat.js"
Cohesion: 0.12
Nodes (34): ago(), bodyHTML(), closePops(), convAvatar(), dayLabel(), fileURL(), grow(), insertAtCursor() (+26 more)

### Community 69 - "manpower-costs.js"
Cohesion: 0.54
Nodes (7): cheapest(), margin(), readBack(), render(), save(), show(), wire()

### Community 70 - "draw"
Cohesion: 0.70
Nodes (4): addFiles(), draw(), render(), save()

### Community 71 - "calendar.js"
Cohesion: 0.12
Nodes (53): addDays(), addTask(), agenda, allDayChip(), byDayOf(), chip(), clearGhost(), colorOf() (+45 more)

### Community 72 - "initPartyPage"
Cohesion: 0.29
Nodes (11): escapeHTML(), initPartyPage(), closeSheet(), importExcel(), openSheet(), refresh(), render(), renderRelated() (+3 more)

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

### Community 78 - "5. Recent work (Batches 147–216, newest last)"
Cohesion: 0.24
Nodes (6): 5. Recent work (Batches 147–216, newest last), AssistantRun, ChatFile, ChatTurn, jsonObject(), jsonText()

### Community 79 - "project-work.js"
Cohesion: 0.24
Nodes (13): addDays(), dueList(), exportRegister(), load(), loadInspections(), loadTasks(), newTask(), openInspection() (+5 more)

### Community 80 - "tasks.js"
Cohesion: 0.08
Nodes (41): buildStepper(), closeCalendar(), commitDate(), enhanceSelect(), hideStepper(), openCalendar(), outsideCalendar(), parseDate() (+33 more)

### Community 82 - "announcements.js"
Cohesion: 0.57
Nodes (6): compose(), draw(), refresh(), render(), sheet(), when()

### Community 83 - "hover-menu.js"
Cohesion: 0.42
Nodes (7): attach(), exportMenu(), forSelect(), groupMenu(), linesMenu(), pickInSelect(), selectItems()

### Community 86 - "widgets.js"
Cohesion: 0.24
Nodes (17): close(), apply(), bar(), columns(), drawTray(), guides(), handle(), load() (+9 more)

### Community 87 - "stock.js"
Cohesion: 0.10
Nodes (73): addLine(), answerReturn(), bar(), batches(), catOf(), closeRec(), companyHoldings(), countTo() (+65 more)

### Community 88 - "multiply.js"
Cohesion: 0.47
Nodes (7): apply(), build(), close(), open(), preview(), scaled(), undoToast()

### Community 89 - "String"
Cohesion: 0.06
Nodes (5): OverviewDoc, OverviewLink, ProjectContents, ProjectOverview, BOQLineItem

### Community 90 - "WebServer"
Cohesion: 0.14
Nodes (9): HTTPRequest, PDFWatermark, WebServer, .enabled, .hasPassword, .port, .sessions, WebSession (+1 more)

### Community 91 - "delivery-rates.js"
Cohesion: 0.67
Nodes (5): build(), label(), open(), plan(), weight()

### Community 92 - "terms-table.js"
Cohesion: 0.36
Nodes (5): grow(), labelOf(), parse(), render(), set()

### Community 93 - "shoot.js"
Cohesion: 0.09
Nodes (18): { chromium }, { execSync }, fs, path, { reply }, ROOT, scrollTo(), SHOTS (+10 more)

### Community 94 - "doc-authors.js"
Cohesion: 0.23
Nodes (15): 1. Hard constraints (carry into every batch), 4.4 Document workspace (Quotation, BOQ, Delivery Note, Invoice, Letter), ago(), buildHero(), copyText(), docCrumbs(), esc(), flowHTML() (+7 more)

### Community 95 - "marketing-overview.js"
Cohesion: 0.28
Nodes (15): countTo(), niceStep(), pickMonth(), refresh(), render(), renderChart(), renderChips(), renderClients() (+7 more)

### Community 96 - ".attr"
Cohesion: 0.11
Nodes (5): je, l(), T(), v, ze

### Community 97 - "notify.js"
Cohesion: 0.70
Nodes (4): card(), ensureBox(), look(), start()

### Community 98 - "evaluate"
Cohesion: 0.39
Nodes (6): evaluate(), factor(), number(), product(), sum(), showBubble()

### Community 99 - "undo.js"
Cohesion: 0.57
Nodes (6): afterReload(), appUndo(), placeOf(), showChanges(), snapshot(), toast()

### Community 100 - "BackupManager"
Cohesion: 0.22
Nodes (4): BackupManager, BackupError, BackupManifest, BackupSummary

### Community 101 - "settings-ui.js"
Cohesion: 0.19
Nodes (8): cancelRow(), closeRow(), commit(), openRow(), refresh(), saveRow(), search(), select()

### Community 102 - "jszip.min.js"
Cohesion: 0.24
Nodes (22): A(), c(), d(), i(), n(), f(), G(), h() (+14 more)

### Community 103 - "formattedParagraphs"
Cohesion: 0.19
Nodes (13): formattedParagraphs(), hangingItem(), HangingStyle, bullet, label, marker, hangingTextOffset(), labelSplit() (+5 more)

### Community 104 - "ScaffoldPro-core.js"
Cohesion: 0.09
Nodes (50): create(), drawCards(), drawDetail(), drawFunnel(), drawTargets(), flush(), liveCard(), open() (+42 more)

### Community 106 - "open"
Cohesion: 0.47
Nodes (8): open(), drawDays(), drawLine(), drawMode(), picked(), setMoving(), toggle(), update()

### Community 107 - "Backup and Restore (atomic, local automatic)"
Cohesion: 0.33
Nodes (6): Backup and Restore (atomic, local automatic), Automatic iCloud backup to William's Work, Quotation Key Terms with hanging-indent formatting, Settings (company info, numbering, standard quotation), Share with Other Macs (iCloud change logs), Workers and administrative documents

### Community 109 - "doc-preview.js"
Cohesion: 0.29
Nodes (13): blocksOf(), editStyles(), letterheadBands(), loadVendor(), paginate(), pdf(), renderDocx(), run() (+5 more)

### Community 110 - "mount"
Cohesion: 0.08
Nodes (65): autoTitle(), card(), copyText(), fileIcon(), groupOf(), initFloat(), close(), grab() (+57 more)

### Community 112 - "quotation-import.js"
Cohesion: 0.47
Nodes (3): askAI(), review(), rowHTML()

### Community 113 - "Assistant.swift"
Cohesion: 0.18
Nodes (6): 2. The standing workflow (do this every time, without asking), 3. How the user likes things, 4. Checking work without a Mac (no Swift compiler here), 7. Starting the new chat, ScaffoldPro — handoff for a new chat, PageBackdropView

### Community 114 - "Double"
Cohesion: 0.10
Nodes (31): amountInWords(), BOQSummary, BuyBackTerms, ChargeSplit, ClientQuoteReport, ClientQuoteRow, DeliveryNoteDetail, DeliveryNoteLineItem (+23 more)

### Community 115 - "doc-language.js"
Cohesion: 0.83
Nodes (3): init(), select(), show()

### Community 116 - "1. What ScaffoldPro is"
Cohesion: 0.14
Nodes (20): 4.1 Home (`index.html`, formerly Dashboard), 4.2 Projects (`projects.html`), 4.5 Schedule (`calendar.html`, replacing Tasks and Calendar), 4.6 Team (`team.html`, replacing Chat and Team) and the Assistant, 4.7 Operations, 4.8 Company, 4.9 Settings, Manual, launch and web screens, 4. Page-by-page specs (+12 more)

### Community 117 - "marketing-report.js"
Cohesion: 0.60
Nodes (3): draw(), load(), start()

### Community 121 - "settings-ai.js"
Cohesion: 0.83
Nodes (3): draw(), load(), save()

### Community 122 - "QuotationAI"
Cohesion: 0.21
Nodes (8): Key, QuotationAI, .company, .model, .provider, .ready, .sharedKey, Status

### Community 123 - "AppDelegate"
Cohesion: 0.13
Nodes (3): 6. Open items and things waiting on the user, AppDelegate, .autoUpdate

### Community 124 - "CloudBackupManager"
Cohesion: 0.12
Nodes (9): CloudBackupManager, .defaultFolder, .enabled, .folder, .iCloudDrive, .usingDefault, Key, CloudBackupStatus (+1 more)

### Community 127 - "install.sh"
Cohesion: 0.24
Nodes (14): base_flags(), compile(), fingerprint(), has_identity(), make_identity(), output_file_map(), pick_sdk(), SDKROOT (+6 more)

### Community 128 - "ScaffoldPro: one design, every page (redesign plan)"
Cohesion: 0.12
Nodes (16): 3.1 Merges, 3.2 Sidebar (rebuilt in `js/sidebar.js`), 3.3 Page anatomy (every page), 3.4 Small screens (Mac window, iPad, phone), 3. Information architecture and navigation, 6.1 The screenshot harness (built in R0, kept in the repo), 6.3 Final consistency audit (R12): all must come back empty, or be explained in the README, 6.4 What can't be checked here (+8 more)

### Community 130 - "String"
Cohesion: 0.07
Nodes (7): PartialSplit, QuotationMoney, BillOfQuantities, markedUpPrice(), Quotation, QuotationLineItem, reordered()

### Community 132 - "LetterColumnKind"
Cohesion: 0.33
Nodes (6): LetterColumnKind, center, left, money, right, weight

### Community 133 - "RelinkTarget"
Cohesion: 0.40
Nodes (5): RelinkTarget, adminDocument, document, drawing, workerDocument

### Community 137 - "CompanySettings"
Cohesion: 0.29
Nodes (9): BOQCharge, BOQDetail, BOQRatesSection, CompanySettings, DefaultBOQItem, DeliveryRate, LinkedDocument, ManpowerPage (+1 more)

### Community 139 - "at"
Cohesion: 0.20
Nodes (14): ACC_PAYMENTS, addDays(), at(), BACKUPS, CLIENTS, EXPENSES, LIAB, MY_PROJECTS (+6 more)

### Community 140 - "DocRow"
Cohesion: 0.32
Nodes (8): ActivityRow, DashboardSummary, DocRow, InspectionDue, MyProject, PartyDetail, ProjectListEntry, UserPage

### Community 141 - "buildQuotation"
Cohesion: 0.18
Nodes (12): ACC_INVOICES, ALL_DOC_ROWS, authors(), BOQS_RAW, buildQuotation(), docRow(), LETTERS, markedUp() (+4 more)

### Community 142 - "init"
Cohesion: 0.31
Nodes (8): build(), evaluate(), get(), init(), open(), place(), placeSaved(), percent()

### Community 143 - "quotation-columns.js"
Cohesion: 0.36
Nodes (11): answer(), build(), close(), customInOrder(), draw(), drawNames(), drawTotal(), open() (+3 more)

### Community 144 - "item"
Cohesion: 0.25
Nodes (8): boqLine(), item(), matLine(), mv(), priceItem(), SCAFOM_ITEMS, SP_ITEMS, STOCK_ROWS

## Knowledge Gaps
- **93 isolated node(s):** `.iCloudDrive`, `.defaultFolder`, `.enabled`, `.usingDefault`, `.folder` (+88 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 533 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **32 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `5. Recent work (Batches 147–216, newest last)` connect `5. Recent work (Batches 147–216, newest last)` to `PDFGenerator`, `AppDatabase`, `GoogleSheetsSync`, `String`, `Models.swift`, `docx-export.js`, `quotation-editor.js`, `at`, `.handle`, `String`, `nonBlank`, `String`, `String`, `String`, `String`, `Encodable`, `workers.js`, `NativeBridge`, `LetterTableRow`, `String`, `WebServer`, `.assistantCheck`, `doc-preview.js`, `mount`, `Assistant.swift`, `Double`, `QuotationAI`, `AppDelegate`?**
  _High betweenness centrality (0.266) - this node is a cross-community bridge._
- **Are the 9 inferred relationships involving `AppDatabase` (e.g. with `1. What ScaffoldPro is` and `5. Recent work (Batches 147–216, newest last)`) actually correct?**
  _`AppDatabase` has 9 INFERRED edges - model-reasoned connections that need verification._
- **What connects `.iCloudDrive`, `.defaultFolder`, `.enabled` to the rest of the system?**
  _93 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `PDFGenerator` be split into smaller, more focused modules?**
  _Cohesion score 0.0712143928035982 - nodes in this community are weakly interconnected._
- **Why does `AppDatabase` connect `AppDatabase` to `GoogleSheetsSync`, `TeamSync`, `String`, `String`, `CompanySettings`, `Models.swift`, `.handle`, `String`, `nonBlank`, `String`, `String`, `String`, `Encodable`, `NativeBridge`, `LetterTableRow`, `5. Recent work (Batches 147–216, newest last)`, `String`, `WebServer`, `BackupManager`, `.assistantCheck`, `Double`, `1. What ScaffoldPro is`, `QuotationAI`, `AppDelegate`, `CloudBackupManager`?**
  _High betweenness centrality (0.193) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `NativeBridge` (e.g. with `1. What ScaffoldPro is` and `5. Recent work (Batches 147–216, newest last)`) actually correct?**
  _`NativeBridge` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Should `AppDatabase` be split into smaller, more focused modules?**
  _Cohesion score 0.038188934729715435 - nodes in this community are weakly interconnected._
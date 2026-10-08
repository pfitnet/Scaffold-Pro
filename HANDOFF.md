# ScaffoldPro — handoff for a new chat

Read this whole file before starting. It is what the previous chat knew. The
detailed history of every change is in `ScaffoldPro-native/README.md`: one
"## Batch N" section per change, newest at the bottom, up to Batch 195.

---

## 1. What ScaffoldPro is

A native **macOS app** for **Proficiency (HK) Limited**, a Hong Kong
scaffolding company that also takes on crane / boom-lift jobs. It runs the
business:

- projects, BOQs (bills of quantities), quotations, delivery notes, invoices and letters, with PDF and Word output on the company letterhead;
- stock, costs (material lists and manpower rates), clients and sites;
- accounting, marketing, admin and staff;
- tasks, a calendar, team chat and signatures;
- a Google Sheets overview and a user manual.

**How it's built:**
- One Swift file, `ScaffoldPro-native/main.swift` (~22,000 lines). It holds the
  data stores (JSON files), the PDF and Word rendering, and a WKWebView app shell.
- HTML, CSS and JS pages run inside that WKWebView. The JS talks to Swift
  through `window.webkit.messageHandlers.native`.
  - `js/bridge.js` defines `window.api.*`, which calls `callNative('area:action', payload)`.
  - In main.swift, `NativeBridge` has a big `switch` on these route names (e.g. `case "stock:addMovements":`).
- Data is JSON stores in Application Support. Several Macs share data through
  an iCloud Drive "ScaffoldPro Team" folder: each Mac writes its own change
  log (`TeamSync`). `ScaffoldPro Web` lets browsers use the app through one Mac.
- Build and install: `install.sh` (run by `Install ScaffoldPro.command` on a
  Mac) compiles main.swift with swiftc and copies `css/`, `js/`, the html and
  `resources/` into the .app. The app checks GitHub for updates.
- The user is **William** (others: Jeremie, Irene, Harry, Tom). Repo:
  **pfitnet/Scaffold-Pro** (public). Default branch `main`.

**Key places:**

| What | Where |
|---|---|
| Routes (JS → Swift) | `main.swift`, `NativeBridge` `switch` (search `case "stock:`) |
| JS API | `js/bridge.js` (`window.api`) |
| Stores and models | `main.swift`, `AppDatabase` (e.g. `projectsStore`, `stockMovementsStore`) |
| Portrait letter PDFs (quotation, invoice, DN, portrait BOQ) | `PDFGenerator`, `LetterDocument`, `cellLines`, `drawCell` |
| Landscape BQ sheet (BOQ / landscape quotation) | `enum BQSheet`, `layout(...)`, `termsBox`, `BQSheetRenderer` |
| Terms formatting rules | `formattedParagraphs` / `hangingItem` (Swift) = `js/paragraph-format.js` (preview) |
| Terms editor (table) | `js/terms-table.js` (keeps the same text format) |
| Custom item box (formatting toolbar) | `js/custom-item.js` + `paragraph-format.js` (`strip` option) |
| Settings page | `settings.html` (generated layout), `css/settings.css`, `js/settings-ui.js` (rows, pencils, autosave), `js/settings.js` (load/save logic, unchanged ids) |
| Stock page | `stock.html`, `css/stock.css`, `js/stock.js`; Swift `stockData`, `addStockMovements`, `deleteStockBatch`, `syncDeliveryStock` (signed DN → stock), `deliveryReturns` (Returns tab) |
| Google Sheets | `resources/google-sheets/ScaffoldPro.gs` (loader, pasted once) + `ScaffoldPro-core.js` (fetched from GitHub main by the sheet); Swift `GoogleSheetsSync`, `sheetsPayload` |
| User manual | content in `js/manual-content.js` (short blocks per chapter), drawn by `js/manual.js`, styled by `css/manual.css`; marker positions `js/manual-shots.js`; pictures `resources/manual/*.jpg` |
| Calendar and the task / event box | `js/calendar.js` (drag to schedule), `js/task-editor.js`; Swift `calendarEvents`, `saveTask` (`endTime`, `team`) |
| Quotation import / duplicate | `js/quotation-import.js`, `js/settings-ai.js`; Swift `QuotationImportReader`, `QuotationAI`, `createImportedQuotation`, `duplicateQuotation` |
| Knowledge graph | `graphify-out/` (see `CLAUDE.md`: `graphify query "…"`, run `graphify update .` after code changes) |

---

## 2. The standing workflow (do this every time, without asking)

The user said: *"no need to ask me next time, auto merge it once the task is done."*

1. Start each task from the latest main:
   `git fetch origin main && git checkout -B claude/macos-construction-app-zmobce origin/main`
   (the branch name the session uses; any `claude/…` branch is fine in a new session).
2. Make the change, and check it (section 4).
3. Add a **README entry** at the bottom of `ScaffoldPro-native/README.md`:
   `## Batch N — Short title`, then bullets in plain words. The next number is **196**.
4. Run `graphify update .` from the repo root.
5. Commit, ending the message with:
   ```
   Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>
   Claude-Session: <this session's URL>
   ```
6. Push, create a PR (owner `pfitnet`, repo `Scaffold-Pro`, base `main`).
   The body ends with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`,
   a blank line, then the session URL.
7. **Merge it straight away** (merge method "merge"). Then reply to the user:
   what changed, the PR link, and anything they must do.

Keep the reply short and plain. Say clearly what was tested and what wasn't
(the Swift is never compiled here; see section 4).

---

## 3. How the user likes things

- **Dates:** typed as dd/mm/yyyy, shown as `7 Oct 2026` (d Mon yyyy). The app has `window.appDay`.
- **Look:** subtle, calm colours; clean and roomy, never cramped. They dislike
  anything that looks "odd" or busy, and will say so bluntly; take it as a
  design brief, not hostility.
- **Interaction:** hover menus and hover labels (tooltips), arrow-key
  navigation everywhere, Return / Esc behaving naturally, undo (⌘Z / ⌘Y)
  without a flash or full reload (`window.appRefresh`), and small
  micro-animations that respect Reduce Motion.
- **Settings-style editing:** show values as text with a small pencil SVG
  to edit; switches, dropdowns and segmented buttons act immediately with no
  pencil; autosave with a small "Saved".
- **Speed:** bulk entry over one-at-a-time (e.g. Stock › Record Stock: typing,
  paste from Excel, quick fill).
- **Wording in the app and README:** plain British English, short sentences,
  no jargon ("Saved", "Not set", "Return…").
- **Colours used across the app:**
  - documents: BOQ `#3f938b`, Quotation `#5374b8`, Delivery Note `#b0843f`, Invoice `#5d9150`, Letter `#8a6cb0`;
  - project status: Planning `#8b6cf0`, Quotation `#c98a14`, Active `#2a8a4a`, On Hold `#e0793a`, Completed `#3a66f0`, Archived `#9196a3`;
  - each person's colour comes from `personColor` (sidebar.js), which Swift mirrors in `sheetsPeopleColours`.
- **Job types:** a project is "Scaffolding" or "Crane" (`Project.jobType`).
  Crane jobs differ:
  - no BOQ tab;
  - the quotation is always the portrait letter (never the BQ sheet);
  - items are written out as formatted custom items, e.g. "Provision of
    Tracked Telescopic Boom Lift", a blank line, then "Model : ZT14JC" and
    "Manufacturer : ZOOMLION" with the colons lined up.

---

## 4. Checking work without a Mac (no Swift compiler here)

The container is Linux, so **swiftc isn't available.** What the previous chat used:

1. **Swift syntax:** a tree-sitter parse of main.swift.
   ```bash
   python3 -m venv /tmp/v && /tmp/v/bin/pip install tree-sitter-language-pack
   ```
   Then a short script: `get_parser('swift')`, parse the file, and report
   any `ERROR` / `is_missing` nodes. It should say 0 issues.
   Also watch for these (they parse fine but don't compile):
   - **closures need explicit `self.`** in NativeBridge (stored or escaping
     closures). Use a nested `func` instead.
   - `any`, `internal` and `defer` used as names.
   - **heterogeneous dictionary literals** in multi-statement closures need
     `-> [String: Any]`.
   - a top-level `let` in a JS file isn't on `window` (in settings-ui.js,
     `defaultBOQItems` is used bare).
2. **The pages in a real browser:** Playwright with the preinstalled
   Chromium (`/opt/pw-browsers/chromium-1194/chrome-linux/chrome`; the
   global playwright is at `$(npm root -g)/playwright`).
   - Load `file://…/ScaffoldPro-native/<page>.html`.
   - Inject a mock of the native bridge before the page loads:
     ```js
     const R = { 'stock:data': {...}, 'settings:get': {...} };   // route → reply
     await page.addInitScript(`const R=${JSON.stringify(R)};window.webkit={messageHandlers:{native:{postMessage(m){(window.__calls=window.__calls||[]).push(m);let r=R[m.action];if(r===undefined)r=/:list|search|people/.test(m.action)?[]:{ok:true};setTimeout(()=>window.__nativeCallback(m.id,true,JSON.stringify(r),null),5);}}}};`);
     await page.addInitScript(fs.readFileSync('js/bridge.js','utf8'));
     ```
   - Then drive the UI and assert on `window.__calls` (what would be sent to
     Swift). Check light and dark (`colorScheme`), read screenshots, and
     catch `pageerror`.
   - Note: `js/controls.js` replaces `<select>` with custom menus, so set
     `.value` and dispatch `change` in tests.
3. **The Google Sheets scripts:** run `ScaffoldPro.gs` and
   `ScaffoldPro-core.js` in Node `vm` with stand-ins for SpreadsheetApp,
   PropertiesService, UrlFetchApp and so on, then assert on the cells.
4. **Manual screenshots** were made with a Playwright script that loads each
   page with mock data and records where the marked controls are into
   `js/manual-shots.js` (mark numbers are 1-based in
   `js/manual-content.js`'s `points`). If a page's layout changes, retake
   its shot and check its points (and `view` crop) in `js/manual-content.js`.

The test scripts lived in the old chat's scratchpad and are gone. Recreate
them as needed from the patterns above.

**Never claim the PDFs were seen.** Swift PDF layout changes are verified
only by reading the code. Ask the user to check one PDF after updating.

---

## 5. Recent work (Batches 147–195, newest last)

- **147–148:** letter attachments with annexure cover pages; Marketing (client quotation report, Promotions).
- **149–161: Google Sheets overview**, kept in step both ways.
  - Tabs: Projects (one line per project and sub-project, document numbers as
    coloured progress cells, Next Step), Activity and Overview.
  - The sheet's code updates itself from GitHub (loader + core, Batch 161).
    Sync Now forces a fetch.
  - The company sheet's link is filled into `SHEET_URL`.
- **151:**
  - quit on close; editable "Created by"; your own projects first;
  - Standard Terms (bank details merged in);
  - subsidiaries shown properly; chop position;
  - Unit Rates columns; signed-PDF viewer.
- **152:** the User Manual (Help menu, sidebar).
- **153:** signed delivery notes, uploaded and attached after their invoice.
- **162–164:**
  - Shift-Return for multi-line custom items; the Scaffolding / Crane slider.
  - Terms-style formatting in custom items (Google Docs-style SVG toolbar).
    Formatted descriptions print with hanging indents and aligned colons in
    both PDF renderers and in Word.
  - Projects list: Company column, fixed widths, rounded edge.
  - Crane quotation layout; terms everywhere as a table (label | wording, add term / add paragraph).
- **165:** Settings rebuilt: section list, search, text plus pencil rows, autosave. Tasks centred.
- **166:** Stock rebuilt:
  - Record Stock for many items at once (typing, Excel paste, quick fill), saved as one batch;
  - Stocktake mode in the list;
  - categories; On Hire by site; History grouped by day and batch;
  - animated totals.
- **167:** stock leaves the yard when a delivery note's **signed copy** is
  uploaded (not when it's issued); Stock › **Returns** asks on a set day
  whether the items are back (All Returned / Part Returned… / Not Yet);
  materials **rented** (Rented tab);
  calendar week view no longer cuts titles or day names; Settings shows
  delivery charges as a rate table and terms as a preview.
- **168:** "Rented" = materials **we rent from other companies** (Rent In /
  Send Back, kinds `RentIn` / `RentReturn`). They're in the yard or on site
  but not owned: Owned = in the yard + on hire − rented in.
- **169:** the User Manual redesigned: presentation-style brevity, chapter
  colours, big cropped screenshots with spotlight pins, flows, steps,
  cards and keycaps instead of paragraphs. Edit the words in
  `js/manual-content.js`; keep them short.
- **170:**
  - quotations: **Duplicate…**; **Import…** from a file (read on the Mac with
    PDFKit / Vision OCR, else a free cloud AI — Gemini free tier or
    OpenRouter `openrouter/free`, key in the Keychain, Settings › AI Import);
    the original kept as a project document linked to the quotation;
    currency for crane jobs; Client Agreed (Marketing counts agreed or signed only);
  - invoices: total in words ("SAY … ONLY"); delivery notes from several
    quotations in sections;
  - Settings merged with You and regrouped (You / Company / This Mac & data);
    rental and sale terms; backups kept 3 days; quitting saves open typing;
  - Calendar events (`TeamTask.endTime`), drag to schedule, Sunday first,
    tasks for a team (`TeamTask.team`), new task/event box;
  - sidebar order editable; editable custom items; manual fixes.
- **171:** fixes from a review of 170: Settings saves again (appearance is
  split off per Mac in `settings:update`); a compile error in
  `createImportedQuotation`; invoices use their quotation's currency.
- **172:** crane quotations offer a **buy-back** (`BuyBackTerms`: % after N
  months, less % a month beyond, none after M months; Settings defaults
  `buyBack*`, per-quotation `buyBack*` fields), printed by `buyBackSection`.
  Fixed `extension Quotation { init(from:) }` not reading fields added since
  (currency, clientAgreedAt, importedFromDocumentId, parentQuotationId):
  **every new Quotation field must be added to that decoder.**
- **173:** build fix from the user's first compile of 170–171 (Swift 6.4,
  arm64): `all` redeclared in `createInvoice(deliveryNoteIds:)`; two unused
  values in Marketing.
- **174:** Batches 170–173 now compile on the user's Mac (Swift 6.3, macOS 26 SDK).
  `install.sh` signs a `ditto` clean copy in a temp folder (iCloud-synced
  Documents re-adds Finder info, so codesign refused); the updater copies with `ditto` too.
- **175:** no Settings tab; a gear beside the User row (`.sidebar-gear`, js/sidebar.js).
  `install.sh` signs with a local self-signed identity "ScaffoldPro Local Signing"
  (made once with /usr/bin/openssl, imported to the login keychain) so macOS
  (TCC) keeps permissions across updates; falls back to ad hoc.
- **176:** AI Import locked while a key is saved (only Remove Key; `QuotationAI.configure` ignores changes then).
- **177:** quit on close fixed: `AppDelegate.windowShouldClose` saves open typing (`saveOpenWork`, 1.5 s cap) then terminates; replaces the willClose observer.
- **178:** theme per person (`UserProfile.appearance`, `NativeBridge.ownAppearance()`); buy-back is a `QuotationBlock` kind "BuyBack" (prefix BO, one row from the figures, after the total); `BuyBackTerms.enabled` = has that block.
- **179:** buy-back wording is a template in Settings (`buyBackWording`, tokens {PERCENT} {UNIT_PRICE} {MONTHS} {LESS} {END_MONTHS} {END_PERCENT} {END_UNIT_PRICE}); amounts per unit (dearest item); `BuyBackTerms.sentences` = js `buyBackSentences`.
- **180:** buy-back tokens {NEXT_MONTHS} {NEXT_PERCENT} {NEXT_UNIT_PRICE} (first month beyond); in the standard wording.
- **181:** `LetterTableRow.wide(number:text:)` (number, then text across the other columns; Word type "wide") for BO1; narrow drawings panel laid out as blocks.
- **182:** file names `db.documentFileBase` (number + project name + " - structure", `safeFileName`, "/" → "∕") for PDF, Word, signed copies, letters.
- **183:** AI connection is the team's: `CompanySettings.aiProvider/aiModel/aiKey` (`setAIConnection`); `QuotationAI.db`; old Keychain key adopted once; `aiKey` stripped from settings:get/update.
- **184:** `--page-max` / `--page-gutter` on #content centre the page on wide screens; `.sidebar-user-row` is one split button (name | gear), kept out of the nav ink.
- **185:** `QuotationLineItem.priceNote` ("FOC" / "Included", price 0) for priced-section rows; `setQuotationLinePriceNote`; printed via `priceNoteLabel` (letter `.partial`, BQ sheet `BOQCharge.amountText`).
- **186:** `formattedParagraphs(labelHeads:)` / js `parse(text, heads)`: in item descriptions a bare "Label :" line is plain and following lines run full width.
- **187:** inline styles in descriptions: `**b**` `*i*` `__u__` → marks U+E010–E012 (`applyInlineMarkup`, `inlineRuns`; PDF `styledText`/`wrapStyled`; docx `run()`; js `inlineMarkupHTML`); BQ sheet uses `plainMarkup`. Priced-section unit price takes words (`priceNote` free text) instead of the 185 dropdown.
- **188:** New Project's quick New Client / New Site use `QUICK_FIELDS` in js/projects.js — the same fields as js/connections.js's sheets (keep the two in step).
- **189:** project folders "<number> <name>" with "<number> BOQ"… inside: `FileStorage.projectFolder` / `projectSubfolder` / `organiseProjectFolder` (run at launch and after a name or code change via `NativeBridge.organiseProjectFolders`); `rebaseFilePaths(moves:)` re-points every stored path (now incl. signed copies, letters, sign requests). Always build paths with `projectSubfolder`, never `projectFolder(...).appendingPathComponent("BOQ")`.
- **190:** documents filed by quotation series: `<project>/26219-002/26219-002 Quotations` (and BOQ, Delivery Notes, Invoices, Delivery Schedules). `NativeBridge.fileFolder(projectNumber:subfolder:name:docTypeTag:documentNumber:)` picks the folder (series from `AppDatabase.documentSeries`; invoices/DNs via `sourceQuotationId`; else a number found in the file name via `projectDocumentNumbers`); combined exports go to `<n> Other`; no series → project-level `<n> <Kind>`. `fileDocumentsBySeries` moves old files at launch (inside `organiseProjectFolders`, so paths are rebased). New save sites must pass a `folder:` from `fileFolder` to `writeGeneratedFile`.
- **191:** build fix: `String.replacingOccurrences(options:)` takes `NSString.CompareOptions`, which has no `.anchorsMatchLines`; use an inline `(?m)` in the pattern instead.
- **192:** every quotation series folder gets all its kind folders (BOQ, Quotations, Delivery Schedules, Delivery Notes, Invoices) even when empty: `NativeBridge.makeSeriesFolders` (launch, opening a project, after `seriesCreatingActions`), with `AppDatabase.seriesByProject()` reading each store once. `fileFolder` falls back to the only series when a project has one; the launch sort also moves iCloud placeholders (`.name.icloud`).
- **193:** Word preview (js/doc-preview.js): `table-layout: fixed !important` (docx-preview sets `auto` inline, which ignored column widths); `paginate()` splits each section into pages (paragraphs move whole, tables split between rows with the heading row repeated, a bold short paragraph moves with what follows).
- **194:** the sidebar's User and gear are one link (`.sidebar-user` with `.user-gear` inside) to settings.html#you, active on any Settings page.
- **195:** task/event sheet: When is one field (day | start – end); labels align with the first line; a new event is for "Me" unless someone is chosen (`forChosen`).

---

## 6. Open items and things waiting on the user

- **Google Sheets:** the user still has to paste the new **loader**
  (`resources/google-sheets/ScaffoldPro.gs`) into their Apps Script once, run
  `setup`, then use Deploy › Manage deployments › ✏️ › New version. After
  that, layout changes arrive by themselves. Settings › Google Sheets shows
  a note with **Copy Script** while the sheet runs an old script.
  - Sheet: https://docs.google.com/spreadsheets/d/10_6_7WG4p3pV7J1DIuqfQoqcGxNII6ZUUC9E_WZaKZ8/edit
  - If the Google Drive connector is available, the sheet can be read to check.
- **Not yet seen on a Mac (built but unverified):**
  - formatted custom-item descriptions in the PDFs (portrait letter and landscape BQ sheet);
  - crane quotations;
  - the Stock batch save (`stock:addMovements`) against real data;
  - Batch 167: stock booked on signed-copy upload, the one-time clean-up of
    unsigned notes, Returns, and Rent In / Send Back (Batch 168) against real data.
  - Batch 170 (never compiled here): `import Vision` and the OCR of scans;
    the Keychain key; real calls to Gemini / OpenRouter; the invoice's
    "SAY … ONLY" row and its sections in the PDF; save-on-quit
    (`applicationShouldTerminate`).
- **Ideas offered but not asked for:** job type on the Google Sheet; a
  crane-only filter on Projects; a free local AI agent (needs the Mac's chip
  and RAM); AutoCAD / DXF (needs templates).
- **Housekeeping to ask about** (don't do it without asking): several Python
  `.whl` files are committed in `ScaffoldPro-native/` (e.g.
  `cryptography-…whl`, `lxml-…whl`). They look accidental, so ask before
  removing them.

---

## 7. Starting the new chat

Paste something like this as the first message:

> Read HANDOFF.md in the repo root first, then the last few "Batch"
> entries in ScaffoldPro-native/README.md. Follow the workflow in section 2
> (auto-merge, no need to ask). Then: <your request>.

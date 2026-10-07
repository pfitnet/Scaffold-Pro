# ScaffoldPro — handoff for a new chat

Read this whole file before starting. It is what the previous chat knew. The
detailed history of every change is in `ScaffoldPro-native/README.md`: one
"## Batch N" section per change, newest at the bottom, up to Batch 167.

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
| User manual | `manual.html`, `css/manual.css`, `js/manual.js`, `js/manual-shots.js`, `resources/manual/*.jpg` |
| Knowledge graph | `graphify-out/` (see `CLAUDE.md`: `graphify query "…"`, run `graphify update .` after code changes) |

---

## 2. The standing workflow (do this every time, without asking)

The user said: *"no need to ask me next time, auto merge it once the task is done."*

1. Start each task from the latest main:
   `git fetch origin main && git checkout -B claude/macos-construction-app-zmobce origin/main`
   (the branch name the session uses; any `claude/…` branch is fine in a new session).
2. Make the change, and check it (section 4).
3. Add a **README entry** at the bottom of `ScaffoldPro-native/README.md`:
   `## Batch N — Short title`, then bullets in plain words. The next number is **168**.
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
   `js/manual-shots.js`. If a page's layout changes, retake its shot and fix
   its legend in `manual.html`.

The test scripts lived in the old chat's scratchpad and are gone. Recreate
them as needed from the patterns above.

**Never claim the PDFs were seen.** Swift PDF layout changes are verified
only by reading the code. Ask the user to check one PDF after updating.

---

## 5. Recent work (Batches 147–167, newest last)

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
  materials **rented** by other companies (Rent Out / Rent Back, Rented tab);
  calendar week view no longer cuts titles or day names; Settings shows
  delivery charges as a rate table and terms as a preview.

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
    unsigned notes, Returns and Rent Out / Rent Back against real data.
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

# ScaffoldPro — native shell (Swift + WebKit, your install.sh method)

## Honest status: this one is untested

The Electron version was actually run and driven through its real UI code
in this environment. **This version has not been compiled at all** — this
container has no Swift compiler and no Cocoa/WebKit (they're macOS-only
frameworks), so there was no way to even syntax-check `main.swift` here.
What I *could* check, I did:

- `install.sh` — valid bash (`bash -n`)
- `Info.plist` — valid plist, correct executable/bundle-id keys
- `resources/*.json` — valid JSON (same real price-list data as before)
- `main.swift` — braces/parens/brackets balance (127/127, 329/329, 70/70) —
  a weak signal, not a compile check

Expect at least a few real compiler errors on first build. That's normal
for ~750 lines of Swift written without a compiler in the loop — it's
exactly what your own workflow (build with `install.sh`, fix, rerun) is
for.

**Update — Delivery Notes, PDF export, and Settings pass:** `main.swift`
is now ~2,820 lines (581/581, 1383/1383, 358/358 braces/parens/brackets
— still balanced, still not a compile guarantee). The riskiest new code
in this pass is the PDF generator (`PDFGenerator`, section "Phase 13"
below) — it's the first code in this project using Core Graphics/PDF
APIs directly (`CGContext`, `CGDataConsumer`, `NSGraphicsContext`) rather
than the JSON-store/WKWebView patterns every earlier phase reused. Those
APIs are well-established (this is the standard way to generate a PDF
programmatically on macOS without a print panel), and I checked every
type/method name against what I know of their real signatures, but this
is exactly the kind of code most likely to need a compiler-error round
or two — expect it, and Claude Code fixing it against real `swiftc`
output should be fast.

## What changed from your install.sh

- App/executable name: `TaskTime` → `ScaffoldPro` (in the script, and to
  match `Info.plist`'s `CFBundleExecutable`)
- The copy step now also copies `css/`, `js/`, `resources/`, and the
  other `*.html` pages into `Contents/Resources/`, not just `index.html`.
  Your original template was for a single-page app; this one is multiple
  HTML pages plus shared assets and the bundled real price-list JSON, all
  of which `main.swift` loads at runtime via `Bundle.main.resourceURL`.
  Everything else — the compile command, ad-hoc signing, quarantine
  removal, `/Applications` install, LaunchServices refresh — is
  unchanged.

## How the pieces fit together

- `main.swift` — one file (as `install.sh` compiles only `main.swift`):
  an `NSWindow` containing a `WKWebView`, a JSON-file data layer (ported
  from the Electron build's `src/db.js`), the same project-numbering and
  filesystem logic as before, and a `WKScriptMessageHandler` that acts as
  the bridge to JavaScript.
- `js/bridge.js` — injected into the page via `WKUserScript` at
  document-start, so `window.api.*` exists before any page script runs.
  It replaces Electron's `preload.js`, with the **same method names and
  shapes**, so `dashboard.js`, `clients.js`, `sites.js`, `projects.js`,
  `project-detail.js`, and `price-lists.js` are copied over **unchanged**
  from the Electron build.
- `index.html`, `price-lists.html`, `clients.html`, `sites.html`,
  `projects.html`, `project-detail.html`, `boq-editor.html`,
  `quotation-editor.html`, `invoice-editor.html`,
  `delivery-note-editor.html`, `admin.html`, `settings.html` — same
  multi-page structure as before (Dashboard is now `index.html`
  specifically, since that's the file `install.sh` and `main.swift` both
  expect as the entry point). `settings.html` is a real form now, not a
  placeholder; `admin.html` still is.

## Installing Xcode Command Line Tools (all you need — not full Xcode)

Open Terminal and run:
```bash
xcode-select --install
```
A dialog will prompt you to install — accept it. This is a few hundred
MB, not the ~7-15 GB full Xcode install, and it's all `install.sh` needs
(`swiftc`, `codesign`, `plutil`, `xattr` all come from it).

Confirm it worked:
```bash
swiftc --version
```

## Building and installing

```bash
cd ScaffoldPro-native
chmod +x install.sh   # if it isn't already executable
./install.sh
```

This compiles `main.swift`, assembles `ScaffoldPro.app`, ad-hoc signs it,
and installs + launches it from `/Applications`. Re-run `./install.sh`
any time you (or Claude Code) change the source — it rebuilds and
reinstalls in place.

The **first** time the app creates a project, macOS will show a system
permission prompt for access to your Documents folder — this is normal
(any non-sandboxed app needs it on modern macOS) and only happens once.

## What's real and working (logic ported from the tested Electron build)

Everything from before — real YYNNN project numbering, real
`~/Documents/ScaffoldPro/Projects/<number>/...` folder creation on save,
both price lists imported with your actual Excel data (105 SP items, 112
SCAFOM items), client/site/project creation, drawing upload via a native
`NSOpenPanel`, and "Show Project Folder in Finder" via `NSWorkspace` —
**plus Phase 7, the BOQ editor**, added in this pass:

- A project can have multiple Bills of Quantities, each numbered
  `<projectNumber>-BOQ-001`, `-002`, ... (scoped per project, independent
  of every other project's sequence)
- Each BOQ has a **pricing mode** (Rental or Sale) chosen at creation,
  which decides which price-list column the item picker defaults to
- The item picker searches both real price lists (same search/category
  filter as the Price Lists page) and adds a line item with one click —
  item code, description, and unit populate automatically (section 18)
- Quantity and unit price are editable inline; overriding a price away
  from the list price **keeps the original list price visible** as a
  reference rather than silently discarding it (section 20)
- Line totals and the grand total are computed from quantity × applied
  price, live
- **Draft → Issued** status: switching a BOQ to Issued locks every line
  item (no add/edit/remove) and blocks deletion — issued documents don't
  get silently modified (section 25)

### What I could verify without a compiler this time

Since this container still can't run Swift/Cocoa/WebKit, I leaned harder
on the checks that don't need a compiler:
- Every action name called from `js/bridge.js` has exactly one matching
  `case` in `main.swift`'s dispatcher, and vice versa — 39 actions now,
  cross-checked programmatically, not by eye
- Every JS property access on a bridge response (`item.itemDescription`,
  `d.grandTotal`, `d.discountAmount`, `q.total`, etc.) matches an actual
  field name on the corresponding Swift `Codable` struct — also
  cross-checked, not eyeballed
- Every `document.getElementById(...)` call in every page's JS resolves
  to a real `id=""` in that page's HTML — checked across all 9 pages
- All JS files pass `node --check` (syntax only — no `window.api`/DOM at
  parse time, so this catches typos, not logic bugs)
- `main.swift`'s braces/parens/brackets still balance (288/288, 652/652,
  161/161) after Phase 8's additions
- Every action name called from `js/bridge.js` has exactly one matching
  `case` in `main.swift`'s dispatcher, and vice versa — 41 actions now
- Every JS property access on a bridge response matches an actual field
  name on the corresponding Swift `Codable` struct (`InvoiceDetail`,
  `InvoiceSummary`, etc. included this round)
- Every `document.getElementById(...)` call resolves to a real `id=""`
  in its HTML — checked across all 9 pages that have their own script
  (`admin.html` and `settings.html` are still static placeholders)
- All JS files pass `node --check`
- `main.swift`'s braces/parens/brackets still balance (382/382, 838/838,
  224/224) after Phase 9's additions
- `install.sh`'s HTML copy list matches the actual `*.html` files present

**This pass (Delivery Notes, PDF export, Settings):**
- Every action name called from `js/bridge.js` has exactly one matching
  `case` in `main.swift`'s dispatcher, and vice versa — 56 actions now,
  cross-checked programmatically again
- Every `window.api.<namespace>.<method>(...)` call across every JS file
  resolves to a method that actually exists on that namespace in
  `bridge.js` — a check I hadn't automated in earlier passes, added this
  round to catch a typo'd namespace or method name before it becomes a
  silent runtime `undefined is not a function`
- Every JS property access on a bridge response matches an actual field
  name on the corresponding Swift `Codable` struct — including the new
  `DeliveryNoteDetail`/`DeliveryNoteSummary`/`CompanySettings`, and
  re-verified `BOQDetail`/`QuotationDetail`/`InvoiceDetail` against the
  exact field lists the new PDF-export handlers read from
  (`appliedUnitPrice`, `grandTotal`, `balanceDue`, etc.)
- Every `document.getElementById(...)` call resolves to a real `id=""`
  in its HTML — now covering `delivery-note-editor.html` and the rebuilt
  `settings.html` too
- All JS files (including the two new ones) pass `node --check`
- `main.swift`'s braces/parens/brackets still balance (581/581,
  1383/1383, 358/358) after this pass's additions
- No duplicate `case` labels within the same `switch`, and no function
  defined twice under the same name — checked programmatically, not
  just by re-reading

**This pass (Drawings & Documents):**
- Cross-checked bridge actions vs. dispatcher cases again — 73 actions
  now, still a perfect match both directions
- Re-verified every `window.api.drawings.*` / `window.api.documents.*`
  call against `bridge.js`, and every field `project-detail.js` reads
  off a drawing/document (`fileExists`, `fileType`, `fileSizeBytes`,
  `category`, etc.) against `ProjectDrawingSummary`/`ProjectDocumentSummary`'s
  actual fields
- `main.swift`'s braces/parens/brackets still balance (668/668,
  1601/1601, 407/407) after this pass's additions
- All JS files pass `node --check`; no duplicate case labels or
  duplicate function names

**This pass (Price List edit, category grouping, Quotation pricing mode):**
- Bridge actions vs. dispatcher cases cross-checked again — 74 actions,
  still a perfect match both directions
- `priceListItems:update` and the `pricingMode` additions to
  `quotations:create`/`quotations:updateHeader` all traced end-to-end:
  `bridge.js` → dispatcher `case` → handler → `AppDatabase` method →
  back through `QuotationDetail`'s actual fields
- `main.swift`'s braces/parens/brackets still balance (679/679,
  1626/1626, 423/423)
- All JS files, including the rewritten `price-lists.js`, pass
  `node --check`; every `getElementById` call resolves to a real
  element in its page

That's real verification of the *interface* between Swift and JS — it
rules out an entire class of "wrong field name," "action not handled,"
and "missing DOM id" bugs before you even open Xcode's Command Line
Tools. It does **not** verify the Swift compiles, or that the UI behaves
correctly — only building it on your Mac can do that.

## Phase 8 — Quotations

- A quotation can be generated **from a BOQ** (copies its line items —
  editing the BOQ afterward never changes an already-created quotation)
  or started blank; `project-detail.html` offers the choice against the
  project's most recent BOQ when one exists
- Quotation numbers follow the same per-project convention as BOQs:
  `<projectNumber>-QT-001`, `-002`, ...
- Header fields: valid-until date, payment terms, discount (none /
  percent / fixed amount), and a tax/VAT rate — all feeding a live
  Subtotal → Discount → Tax → Total breakdown (section 21/50)
- Same item picker as the BOQ editor, same inline quantity/price editing
- **Draft → Issued → Cancelled** lifecycle: anything other than Draft
  locks every field and every line item, and only a Draft quotation can
  be deleted (section 25 again)

One deliberate simplification versus the BOQ editor: quotation line
items don't keep a separate "original list price" reference the way BOQ
line items do (section 20 only asked for that on the BOQ). If you want
that same override-tracking on quotations later, it's a small, contained
addition — add `priceListUnitPrice: Double?` to `QuotationLineItem` and
thread it through the same way `BOQLineItem` already does.

## Phase 9 — Invoices, added in this pass

- An invoice can be generated **from a Quotation** (copies line items
  plus the quotation's discount/tax/payment terms) or started blank,
  offered the same way as Quotation-from-BOQ was
- Same per-project numbering convention: `<projectNumber>-INV-001`
- Statuses now cover the full set from section 22: **Draft → Issued →
  PartiallyPaid → Paid**, plus **Overdue** and **Cancelled**. Draft is
  the only editable state for line items and header fields — same
  lock-on-issue rule as BOQs and Quotations
- **Payment recording**: once an invoice is Issued (or Overdue), a
  "Record payment" control lets you log an amount against it. Status
  updates automatically — PartiallyPaid while a balance remains, Paid
  once the balance reaches zero. Recording a payment is rejected on a
  Cancelled invoice, and rejected before the invoice is issued (there's
  nothing to pay against yet)
- Only Draft invoices can be deleted — an issued invoice with a mistake
  in it gets **Cancelled**, never deleted, per section 22's explicit
  instruction not to casually delete issued financial documents
- The totals box now shows Subtotal → Discount → Tax → Total → Paid →
  **Balance Due**, so what's still owed is always visible at a glance

Delivery Notes, Admin, and Settings are still placeholders — Delivery
Notes (Phase 10) is next.

## Phase 10 — Delivery Notes

- A delivery note can be created **from an Invoice** (preferred, since
  it's what's actually being billed) or **from a Quotation**, or started
  blank — `project-detail.html` offers the choice against the project's
  most recent Invoice first, then its most recent Quotation, same
  pattern as Invoice-from-Quotation
- Numbering follows the same per-project convention: `<projectNumber>-DN-001`
- **Deliberately no pricing anywhere** — section 23 lists a delivery
  note's fields as item/description/unit/quantity plus Delivered By /
  Received By, never a price. `DeliveryNoteLineItem` has no unit-price
  field at all, unlike every other line-item type in this app
- Header fields: delivery address, Delivered By, Received By, notes —
  all editable while Draft
- **Draft → Issued → Cancelled** lifecycle, same lock-on-issue and
  delete-only-if-Draft rules as every other formal document here

## Phase 13 (partial) — real PDF export for every document type

Until this pass, **no document type could export a PDF at all** —
despite section 61's explicit "do not fake functionality: if there is
Export PDF, it must generate a real PDF," none of the BOQ, Quotation, or
Invoice editors had an Export PDF button, let alone working code behind
one. This was the single biggest gap against the master prompt, bigger
than Delivery Notes being unbuilt, so it took priority this round.

What's there now:
- A new `PDFGenerator` class draws directly into a Core Graphics PDF
  context — no screenshotting the UI, no NSView/print-panel dance
  (section 27's explicit instruction). It lays out a company header,
  document title/number/status, a Bill To / Site block, a line-item
  table, a totals box, notes, payment information (invoices only), and
  signature lines, then closes the PDF
- **Every** BOQ, Quotation, Invoice, and Delivery Note editor has a
  working "Export PDF" button. Exporting saves the PDF into the
  project's own folder under a meaningful filename — e.g.
  `26017_Invoice_26017-INV-002.pdf` in `Projects/26017/Invoices/`
  (sections 31–32) — and opens it in Preview (or whatever the default
  PDF viewer is) so you see the result immediately
- **Pagination**: if a table has more rows than fit on one page, it
  starts a new page and repeats the column header (section 27's "repeat
  table headers on multiple pages"). The totals/notes/signature block is
  measured and pushed to a fresh page as a unit if it wouldn't
  otherwise fit, rather than splitting awkwardly across a page break
- Every PDF pulls its company name, address, phone, email, website,
  registration number, VAT number, and (for invoices) bank details from
  the new Settings page — see below

**What's unverified**: the pagination math (row height × count vs. page
height) is arithmetic I worked out by hand, not something I could render
and eyeball. For a normal-length BOQ/quotation/invoice/delivery note (a
handful to a few dozen lines) it should look right; a very long one is
the first place to check if a page break looks off. This is a five-minute
fix once you can actually see a rendered PDF — nothing about the
approach is fundamentally shaky, just untested against real rendered
output.

## Settings — Company Information

No longer a placeholder. Company name, address, phone, email, website,
registration number, VAT number, bank details, currency, default
tax/VAT rate, and default payment terms are all editable and persisted
— and, as of this pass, actually used: every generated PDF's header and
(for invoices) payment-information block pulls from exactly these
fields. Document-numbering overrides, backup/restore, and data-location
controls are still on the Admin roadmap, not here.

## What's still not built

- **Document-numbering overrides** (section 24's "allow an administrator
  to configure numbering formats") — numbering is automatic and correct,
  just not yet configurable from the screen
- **Global Search (⌘K), Activity History**: not started
- **Dark mode**: added earlier as a CSS-variable override under
  `prefers-color-scheme: dark` — covers the sidebar, tables, buttons,
  inputs, and status pills. A couple of hardcoded light colors in
  `boq-editor.html`'s own `<style>` block (the "Materials/Labour/..."
  section-header row) weren't touched, so those rows will look slightly
  off in dark mode — a small, contained fix later
- **Printing**: PDFs are printable (any PDF is, via Preview → Print),
  but there's no in-app "Print" menu item wired to `NSPrintOperation`
  yet, separate from Export PDF
- **Replacing a drawing/document's file in place** (keeping the same
  record, swapping the underlying file) isn't built — only Rename and
  Locate File/Re-link are. If the actual content changed, upload it as a
  new item and archive the old one for now

## Phase 11 — Drawings & Documents (this pass)

The one loose end called out at the end of the last pass: uploading a
drawing worked, but nothing about it was remembered — no record, no
list, just a file quietly sitting in Finder. Fixed properly this round,
and general project documents (section 34) built alongside it since
they're the same problem twice:

- **Drawings and Documents are both tracked in the database now** — file
  size, file type, upload date, and an editable description, per drawing
  or document, matching section 14's and section 34's metadata lists
- The project page's "Drawings & Documents" placeholder is a real
  section now: two lists, each row showing name/type/size/date plus an
  editable description field, and Open / Reveal in Finder / Rename /
  Archive buttons
- **Documents also get a category** at upload time — Contracts,
  Specifications, Correspondence, Certificates, Client Documents, Site
  Information, or Miscellaneous (section 34's list) — chosen from a
  dropdown next to the Upload Document button. Unlike drawings, document
  uploads accept any file type, not just PDF/PNG/JPEG/TIFF
- **Rename actually renames the file on disk**, not just a label in the
  database, so Finder and the app never disagree about a file's name
- **Section 38's missing-file handling is real**, not just described:
  every list checks whether the file still exists on disk before
  showing it. A moved or deleted file shows a red "File unavailable"
  badge and swaps its buttons for **Locate File…** (pick where it
  actually is now — nothing gets moved or copied, the record just points
  at the new location) and **Remove Reference** (deletes ScaffoldPro's
  record only; never touches anything on disk)
- Archiving is a soft delete — the database record is hidden from the
  list, the file is left exactly where it is

This pass's new code follows the same patterns as everything already in
the file (JSONStore-backed models, the same dispatcher/handler shape),
so it carries less first-build risk than last pass's `PDFGenerator` —
the one new pattern here is `FileManager.moveItem` for renaming, which
is a very standard, well-worn API.

## Recommended next step

Point Claude Code at this folder on your Mac. It can actually run
`./install.sh`, read the real `swiftc` errors, fix them, and iterate —
which is the one thing I couldn't do for you in this environment.
`PDFGenerator` is still the most likely spot for a real compiler
round-trip; everything since then reuses patterns already proven
elsewhere in the file. Once it builds clean: try Export PDF on a
Quotation or Invoice first, then upload a drawing and a document, then
try editing a price-list item and switching a quotation between Sale
and Rental pricing. After that, Admin (Workers + document numbering) is
the natural next phase.

## Price Lists — edit function, and a cleaner layout (this pass)

- **Items are editable now.** Every row has an Edit button that turns
  Item Name, Category, Unit, Sale Price, and Rental Price into input
  fields with Save/Cancel — nothing was editable before this pass.
  Item code is deliberately left alone (it's the identifier everything
  else, including old BOQ/quotation/invoice line items, keys off)
- **Code and Unit are no longer separate columns** in the table — per
  your request. Unit is still there and still editable, just inside the
  Edit form rather than as its own always-visible column
- **Items are grouped by category** ("bracket") instead of one flat
  list with a repeated Category column on every row — each category now
  gets its own heading with just its items underneath, sorted
  alphabetically. Editing an item's category moves it into the right
  group the next time the list refreshes

## Quotations — Sale or Rental pricing (this pass)

BOQs already had this (a BOQ is created as either Sale or Rental
pricing, and the item picker shows whichever price applies); Quotations
didn't. Now they do, the same way:
- Starting a quotation from scratch asks Sale or Rental up front
- Starting one from an existing BOQ **inherits that BOQ's pricing
  mode** automatically, since the line items being copied already
  reflect it — no separate prompt in that case
- A Pricing dropdown sits in the quotation editor itself (next to Valid
  Until / Payment Terms), changeable any time while the quotation is
  still a Draft — switching it updates the prices shown in the item
  picker for anything you add *from then on*, but never rewrites prices
  already on the quotation, since those may have been manually adjusted
- The quotation's PDF now shows which pricing basis was used, same as
  the BOQ PDF already did


## Phase 12 — Workers & Administrative Documents (this pass)

The Admin page is no longer a placeholder:
- **Workers** (section 41): add a worker (name, position, phone, email,
  start/end date, notes), each gets a permanent number (W001, W002, …)
  and their own folder at `Documents/ScaffoldPro/Administration/Workers/W001/`.
  Details are edited in place; workers are archived, never deleted
- **Worker documents** (section 42): upload employment contracts,
  certifications, training certificates, ID, etc. — copied (never moved)
  into the worker's `Contracts/`, `Certificates/` or `Other/` subfolder,
  each with an optional **expiry date**
- **Company documents** (section 43): insurance, licences, contracts and
  other company paperwork, filed by category into `Administration/Insurance/`,
  `Administration/Licenses/`, etc., searchable, with optional expiry dates
- **Expiry reminders**: anything expired or expiring within 30 days is
  listed under "Needs Attention" at the top of Admin, and also on the
  Dashboard (section 7's "administrative documents requiring attention")
- Same Open / Reveal / Archive / Locate File… / Remove Reference
  behaviour as project drawings and documents

## Requested changes (this pass)

- **Quotation can reference a BOQ**: a "Reference BOQ" bar at the top of
  every quotation lists the project's BOQs; pick one and press **Import
  Items**. If the quotation already has items you're asked whether to
  replace them or add below. Prices are taken from the price list for the
  *quotation's* Sale/Rental setting (so a Rental BOQ can feed a Sale
  quotation), falling back to the BOQ's own price if the item was since
  removed from the price list. The quotation remembers which BOQ it
  references and shows it
- **BOQ shows weight, not price**: the BOQ screen, its item picker, the
  project's BOQ list, and the BOQ PDF now show unit weight, line weight,
  and total weight (kg) instead of prices. Prices are still recorded
  quietly behind the scenes so quotations made from a BOQ come pre-priced.
  *Note:* BOQ lines added before this update have no stored weight and
  show "—"; re-adding the item fills it in
- **Quantities are whole numbers** everywhere — BOQ, quotation, invoice,
  delivery note — both on screen (1-step boxes) and enforced when saving
  (the database rounds anything else), and printed without decimals on
  PDFs
- **Money shows as 1,234.56** on every screen and every PDF (thousands
  separator, two decimals)

**Verification this pass:** 97 bridge actions, all matching dispatcher
cases; every `window.api` call resolves; every `db.` call in Swift
resolves to a real method (new automated check); braces/parens/brackets
balance (811/811, 1970/1970, 516/516); all JS passes `node --check`.
Still not compiled — `./install.sh` on your Mac (or Claude Code) is the
real test.


## Phase 14 — Backup & Restore (this pass)

Settings now has a **Backup & Restore** section (section 39) and a
**Data Location** section (section 57):

- **Create Backup** copies *everything* into one dated folder in
  `Documents/ScaffoldPro/Backups/` (moved in batch 23 to
  `~/Library/Application Support/ScaffoldPro/Backups/`, with the database), laid out exactly as section 39 asks:
  `Database/`, `Projects/`, `Administration/`, `Configuration/` (a
  manifest plus a plain-English README.txt). It's an ordinary folder —
  you can copy it to a USB drive or another Mac
- A backup is built in a hidden `.inprogress-…` folder and only renamed
  when complete, so a backup interrupted by a crash or power cut never
  looks like a real one
- **Restore** (from the list, or **Restore from Folder…** for a backup
  kept elsewhere) always makes an automatic **"before restore" safety
  backup first** — so any restore can be undone by restoring that one.
  The database and files are copied into staging folders and swapped in;
  if the database swap fails, the original is put straight back
- If a backup came from a **different Mac or user account**, every
  stored file location is re-pointed to this Mac automatically, so
  drawings and documents still open
- Copying runs in the background — the window doesn't freeze on large
  drawing folders — and only one backup/restore can run at a time
- The **Dashboard** shows a gentle reminder if there's no backup yet or
  the last one is 7+ days old
- **Data Location** shows exactly where business files, backups and the
  database live, with a Show in Finder button

**Data-safety improvement:** every database save is now *atomic* (written
to a temporary file then swapped in), so a crash mid-save can't leave a
half-written, corrupted file (section 48).

**Verification:** 104 bridge actions, all matched both ways; every
`window.api`, `db.`, `storage.` and `backups.` call resolves; braces
balance (887/887, 2148/2148, 532/532); all JS passes `node --check`.
Additionally, the backup → edit → restore → undo → restore-from-another-Mac
sequence was rehearsed with a small Python replica of the same steps on a
throwaway folder — all 8 checks passed. That validates the *order of
operations*, not the Swift itself, which still needs `./install.sh`.

**Remaining from the master prompt:** Global Search (⌘K), project
Activity History, configurable document-numbering formats, and a native
Print menu item.

## Batch 15 — completing the master prompt (part 1)

**Done in this batch**
- **No item codes on any document** — every PDF and editor numbers rows 1, 2, 3…; pickers don't show codes (search still matches them)
- **Exact money maths** (section 50): all totals use `Decimal`, rounded to the cent (`computeMoneyTotals`)
- **Data safety**: a data file that can't be read is copied aside (`*.unreadable-<time>.json`) instead of being overwritten; quotations saved before the Sale/Rental option load as Rental
- **Clients & Sites** (sections 9–10): edit, archive/restore, reference/city/postcode/country/VAT/billing fields, related projects and documents; full client billing block on PDFs
- **Projects** (sections 13–17): tabbed project page (Overview, BOQ, Quotations, Invoices, Delivery Notes, Drawings & Documents, History); edit details; optional details + drawing upload at creation
- **History** (section 45): creations, status changes, payments, uploads, deletions, exports and prints are logged per project
- **Price lists** (sections 8, 49): add, duplicate, delete (archive); Excel (.xlsx via macOS `unzip`) or CSV import with a preview showing the column mapping and add/update counts; CSV export. Import heuristics were tested on generated workbooks built from the real price data in two layouts — 105/105 and 112/112 items read back exactly
- **Document numbering formats** (section 24): templates with `{PROJECT} {YYYY} {YY} {SEQ}`, never producing duplicates (7 test cases pass). Defaults reproduce the existing numbers exactly
- **Defaults** from Settings (tax rate, payment terms, notes, invoice due days) applied to new quotations/invoices; optional tax-inclusive pricing
- **Print** (section 54) via the standard macOS print dialog, A4 or Letter; **company logo** on PDFs
- **Menu bar & shortcuts**: Edit menu (⌘C/⌘V/⌘X/⌘A/⌘Z — previously missing), ⌘N/⇧⌘N/⌥⌘N new project/client/site, ⌘K find, ⌘E export, ⌘P print, ⌘1–⌘7 sections, ⌘[ / ⌘] back/forward
- **Window**: unified title bar, remembers size/position, no white flash in Dark Mode
- `install.sh` now also links PDFKit and UniformTypeIdentifiers

**Completed in part 2 of this batch**
- **Settings**: logo (choose/remove, preview), paper size, invoice due days, "prices include tax", document number formats with a live example, and Light / Dark / Follow System (applies instantly). Fixed a bug where saving one option would have blanked the company details
- **⌘K search** (section 44): search box in the sidebar and ⌘K anywhere — projects, clients, sites, BOQs, quotations, invoices, delivery notes, workers, drawings, documents, company documents and price-list items; arrow keys + Enter
- **Dashboard** (section 7): unpaid and overdue totals, unpaid invoices, quotations awaiting reply, active/recent projects, recently changed documents, recent delivery notes, recent activity, expiring documents, backup reminder, and quick actions (New Quotation/Invoice/Delivery Note ask which project)
- **BOQ** (section 19): move lines up/down, duplicate a line, a note per line (printed on the PDF)
- **Custom items** (section 21) in BOQ, quotation, invoice and delivery-note editors — for things not on a price list
- **Replace** a drawing or document with a new version (section 14); the previous copy is kept in `Other/Superseded/`
- **Sortable tables** (click a column title) everywhere except document line items, whose order is the document's order
- **Right-click menus** on the Projects list and on drawings/documents
- **Design pass**: new stylesheet — sidebar with icons and selection highlight, Mac-style buttons and fields with focus rings, hairline tables, sheets, search panel, context menus; separately designed Dark Mode; respects Reduce Motion

**Still needs the owner's input**: sample quotation / invoice / BOQ / delivery note (to match the PDF layouts to the company's own style) and the logo file (now just a matter of choosing it in Settings).

**Not done (by choice, noted for later)**: storage stays as JSON files rather than SQLite — it's working, backed up, written atomically and protected against unreadable files; moving to SQLite would be a large change with no visible benefit at this size. Table column *resizing* is not implemented (sorting is).

**Verification**: 133 bridge actions all match both ways; every `window.api`, `db.`, `storage.`, `backups.` call resolves; braces balance (1356/1356, 3422/3422, 843/843); all JS (including inline page scripts) passes `node --check`; every page's element IDs and script files exist; every visual CSS class is defined. Still not compiled — run `./install.sh`.

## Batch 16 — fixes and the company's standard quotation

**Fixed**
- **Dialogs didn't work anywhere** (the cause of "Delete does nothing" in the price list): the web view had no `WKUIDelegate`, so every `alert()`, `confirm()` and `prompt()` was silently ignored and `confirm()` always returned false — breaking Delete, Archive, Rename, Remove Reference, Restore and the "create from BOQ/quotation?" questions. `AppDelegate` now shows native Mac sheets (destructive buttons for delete/archive/remove/restore)
- **SCAFOM prices were labelled HKD but are in EUR** (the company workbook: "Unit Sale Price (EUR)"). The list is relabelled EUR — including on existing installs, once at launch — and its prices are converted to HKD wherever they go onto a document, at a rate set in Settings (default 8.93, which reproduces the workbook's "Wanted Price" exactly: €0.45 → HK$4.02, €0.59 → HK$5.27)

**Changed**
- "Price Lists" is now **Material List**, showing Weight, Rental / Month and Sale for every item; weight is editable
- **BOQ settings** (as in the workbook's "BQ Settings"): Sale ↔ Rental, mark-up/down %, and Structure. Changing mode or mark-up re-prices every material-list line (hand-typed prices are kept); weights never change. Quotations made from / referencing a BOQ use its prices when the mode matches
- **Standard quotation** modelled on Qt26193 (Google Drive):
  - letterhead; client block with "BY EMAIL ONLY"; Our Ref. / Your Ref. / Site Ref. / Date; "QUOTATION"; "Dear Sir / Madam"; bold **Re:** subject; the standard opening sentence
  - items table No / Item Description / Unit Rate ("HK$ 5.50 /Month") / Qty / Total Price
  - rental: "Subtotal of Monthly Rental Charge" and "Minimum Hire of N Months"; a **Delivery Charges** section numbered D1, D2… ("+ Delivery Charge" adds the standard line); "Total Amount"
  - Terms and Conditions with the web address, the numbered key terms, the acceptance/validity paragraph, both signature blocks (Richard Kwan, Director / client Position & Date), and "-[Remainder of this page is intentionally left blank]-"
  - all texts, the signatory, delivery charge (standard HK$3,800 per truck per trip) and minimum hire are editable in Settings → Standard Quotation
- **Numbering** now defaults to the company convention: quotations **Qt26XXX**, invoices **H26XXX** (existing documents keep their numbers). "Next number at least" boxes in Settings continue an existing sequence — e.g. enter 194 after Qt26193
- **Excel import** understands the real workbook layout: untitled item-code column, merged category rows, tick-box and "Wanted Price" columns, EUR sheets; matches by code, then by name (never duplicating). Tested on a replica of the workbook: 105/105 SP and 112/112 SCAFOM items exact

**Verification**: 135 actions matched both ways; all `window.api` / `db.` / `storage.` calls resolve; every stored property is supplied where QuotationDetail, BOQDetail and QuotationLetter are built; code brackets balance (checked with string literals excluded); all JS passes `node --check`.

## Batch 17 — window dragging and the app icon

- **Window can be dragged again.** Since the unified title bar lets the page run up behind the title bar, the web view was catching title-bar clicks. A thin native `TitlebarDragView` now sits over the top 38 pt: drag to move the window, double-click to zoom (or minimise / nothing, following the macOS "double-click a window's title bar" setting). The window buttons stay clickable; no page content sits in that strip
- **App icon** in `icon/`: a two-bay system scaffold with rosette connectors at every joint and a single safety-yellow brace. Colours: navy #1B3556→#10223A, galvanised steel #E4E8EC / #B4BDC7, safety yellow #F4B400. The 16 and 32 px sizes are hand-simplified (no rosettes, heavier lines) so they stay crisp
  - `icon/AppIcon.iconset/` — all macOS sizes; `install.sh` builds `AppIcon.icns` from these with `iconutil` (prebuilt `icon/AppIcon.icns` as fallback); `Info.plist` now names the icon
  - `icon/ScaffoldPro-logo.svg` — vector master for print/web; `icon/AppIcon-1024.png`; `icon/make_icon.py` regenerates everything
  - the small mark also appears at the top of the sidebar

## Batch 18
- Standard delivery charge set to **HK$3,800 per truck per trip** (owner-confirmed). Existing installs still on the earlier 1,200 default are moved to 3,800 once at launch; a value set by hand afterwards is never overwritten
- `icon/preview.png` added — the icon at every size on light and dark backgrounds

## Batch 19 — audit against the master prompt
A full read-through against all 67 sections of the master prompt; results,
remaining gaps and open questions are in **AUDIT.md**. Fixed in this pass:
blank "Attn:"/address lines on PDFs for new clients and sites; project-number
override validation (year / sequence 000); issued invoices can no longer go back
to Draft and cancelled documents stay cancelled; empty documents can't be issued;
overpayments rejected; line order after deleting a line; faster Dashboard/⌘K
search; Overdue shown consistently; Rename (no more `Plan.pdf.pdf`, shows the new
name); ⌘K → worker opens that worker; quotation totals use the Settings currency;
editable quotation / invoice / delivery dates; wrapped rows, measured footers and
page numbers on invoice / delivery-note / BOQ PDFs; exported PDF path stored on
each document and re-export replaces the old PDF; delivery address pre-filled from
the site. Still not compiled — run `./install.sh` on a Mac.

## Batch 20 — every document on the company letterhead
All PDFs (quotation, invoice, delivery note, BOQ) now use the layout of the
standard quotation Qt26193: the Proficiency (HK) letterhead and address footer
drawn to the sample's exact positions, sizes and colours on every page;
EB Garamond body text (bundled in `resources/fonts`, SIL Open Font Licence,
registered when the app starts); black-ruled tables with "HK$" in money
cells; Times New Roman signature blocks. The Settings logo chooser was
replaced by a note, since the letterhead is fixed. Details are in AUDIT.md,
under "Letterhead layout".

## Batch 21 — quotation pricing, item discounts, minimum hire, logo text
- **Sale ↔ Rental re-prices existing items.** Changing a quotation's pricing
  re-prices every material-list item already on it (after a confirmation).
  Prices typed in by hand are kept. Each line remembers its list price, and a
  hand-typed price shows "List 25.00" under it. A subject still reading
  "<project> - Rental" follows the switch.
- **Discount per item** (quotations and invoices): a Discount button on each
  line sets no discount (the default), a percentage, or an amount off the line
  total. The PDF prints "Less 10% discount" under the item, and its Total Price
  is net. Invoices made from a quotation keep the line discounts.
- **Items in item-code order** ("1.2" before "1.10") on quotations, invoices
  and delivery notes, on screen and on the PDF. Custom items and delivery
  charges follow, in the order they were added.
- **Minimum hire is optional per quotation**: a "Minimum Hire: Apply" tick
  box. It's off on new quotations; the months default from Settings. Existing
  rental quotations keep the minimum hire they had.
- **Logo text**: "建機 (香港) 有限公司" is Noto Sans TC at 15pt, drawn at its
  natural shape. A subset of the font with just those characters (7 KB, SIL
  Open Font Licence) is bundled in `resources/fonts`.
- **Terms and Conditions start on a new page** whenever the whole quotation
  doesn't fit on one page (worked out with a trial layout first).

## Batch 22 — invoices from quotations; drawings as DWG, linked to a BOQ or quotation
- **Every invoice is based on one of the project's quotations.** "+ New Invoice"
  opens a sheet to choose the quotation. Its items, prices, line discounts,
  discount/tax terms and Sale/Rental pricing are copied. For a rental quotation,
  choose **one month's rent** or the **full hire period** (the quotation's
  minimum hire months, adjustable), and whether to include delivery charges.
  The invoice editor shows the quotation it's based on, plus "Months charged"
  and an optional "Rental period" while Draft. The PDF shows "/Month" rates,
  "Monthly Rental Charge" and "Rental for N Months", and the quotation number,
  your ref., site ref. and subject line.
- **Drawings can be DWG or DXF** as well as PDF, PNG, JPEG or TIFF.
- **Drawings can be linked to a BOQ or a quotation**: choose "For …" when
  uploading, or change it any time in the project's Drawings list. Each BOQ and
  quotation editor has a Drawings panel listing its drawings (Open / Reveal)
  with an Upload Drawing button that links automatically.

## Batch 23 — quotation markup/discount, backups with the database, T&C page option
- **One "Markup / Discount" box on each quotation** replaces the discount type
  and value fields:
  - `+30%` (or `30%`) marks every item's unit price up 30%, each marked-up
    price rounded to the nearest 0.1. The price you typed stays as it was; the
    editor shows "Quoted …" under it, and the PDF, line totals and totals use
    the marked-up price. Delivery charges aren't marked up.
  - `-15%` takes 15% off: a "Less 15% Discount" row above the total.
  - `-1000` takes 1,000 off: a "Less Discount" row.
  - Blank or `0` means neither. An amount without a minus sign (`1000`) is
    refused, as it's unclear whether it's meant as a markup.
  - Invoices made from a marked-up quotation copy the marked-up prices.
- **Backups are kept with the database**, in
  `~/Library/Application Support/ScaffoldPro/Backups/` (beside `data/`), not in
  Documents. Backups made by earlier versions are moved there when the app
  starts, and the old `Documents/ScaffoldPro/Backups` folder is removed if
  nothing else is in it. "Show Backups Folder" and Data Location show the new
  place.
- **Terms and Conditions page option** (Settings → Standard Quotation): "New
  page when the quotation runs over one page" (the default, as before) or
  "Always on a new page".

## Batch 24 — quotation sections: titles, priced rows, rates-only rows, notes
- **Minimum hire row** shows only when "Minimum Hire: Apply" is ticked and the
  hire is more than 1 month (on the PDF and in the editor's totals).
- **Extra sections on quotations**, as on the company's own quotations. Add them
  below the line items:
  - **+ Priced Section**: a merged title row (e.g. "Design Fees" or "Erection &
    Dismantle") and priced rows numbered A1, A2… (prefix editable). They are
    added to the Total Amount and aren't marked up.
  - **+ Rates Section**: a merged title row (default "Erection & Dismantle
    Manpower Rates") and rows R1, R2… showing "HK$ 2,300.00 / md" with
    "(Rate Only)" across Qty and Total Price. They appear after the Total Amount
    and aren't charged. The section starts with the usual note about overtime
    and Sunday / public holiday rates.
  - **+ Note**: a note across the table, in small grey italics, after the total.
    Every priced or rates section can also end with its own note.
  - Titles, row prefixes, notes and each row's description, unit, quantity and
    price can be edited in place. Sections can be moved up or down and removed.
    Importing a BOQ with "replace" keeps them.
- **Invoices** made from the quotation copy the priced sections' rows under
  their titles, charged once (not per month). The New Invoice sheet has an
  "Include Design Fees…" tick box. Rates and notes aren't copied.
- **Delivery notes** made from a quotation or invoice now list the materials
  only, without delivery charges or other charges.

## Batch 25 — paragraph formatting (hanging indents) in payment terms
- **Payment Terms** on quotations and invoices, and **Default Payment Terms** and
  **Key terms** in Settings, are now multi-line boxes. Each has a small toolbar
  (Hanging Indent, • Bullets, 1. Numbering, (i) Numbering) and an "As printed"
  preview underneath. One paragraph per line:
  - `Deposit : 50% upon order confirmation` (or `Deposit: …`): label, colon,
    and the text in a hanging indent at the same column as "(i) Payment :".
  - `- text` or `• text`: bullet with a hanging indent.
  - `1. text`, `(a) text`, `b) text`, `(iv) text`: numbered, hanging indent.
  - A label or number, then **Tab**, then the text: hanging indent.
  - Lines that follow one of these line up under its text. A blank line ends
    it; any other line is an ordinary paragraph.
- **Quotation PDF:** the quotation's own payment terms replace the text of the
  standard "Payment" key term, under its label. Bullets and labelled lines line
  up under the text. Leave the box blank to print the standard term. (Before
  this, a quotation's payment terms were only printed when the Settings key
  terms were blank.)
- **Invoice PDF:** "Payment Terms :" with the same formatting under Payment
  Information.
- The standard key terms print exactly as before.

## Batch 26 — every quotation has its own editable Key Terms
- The quotation editor's **Payment Terms** box is now **Key Terms**: all of the
  quotation's key terms (Payment, Delivery, Modification…), fully editable with
  the paragraph formatting from batch 25. **Start from Standard Terms** copies
  the Settings key terms in, ready to edit.
- **Blank = standard terms.** A quotation without key terms of its own prints
  the standard key terms from Settings (Settings → Standard Quotation →
  "Standard key terms"). The preview under the box shows them.
- **Indented lines go under the item above:** an indented bullet, number or
  label lines up with the text of the item above it (e.g. bullets under
  "(i) Payment :"). The toolbar has **Indent →** and **← Outdent**.
- Quotations whose payment terms were typed in (different from the Settings
  default) are given key terms of their own once, when the app starts: the
  standard key terms, with those payment terms as the Payment term. They print
  as before.
- Invoices keep their own **Payment Terms**. Settings' "Default Payment Terms"
  now says it's for invoices.

## Batch 27 — Export Word (.docx), laid out like the PDF
- Every BOQ, quotation, invoice and delivery note editor has an **Export Word**
  button next to Export PDF. It saves `<project>_<type>_<number>.docx` next to
  the PDF in the project folder and opens it.
- The Word copy follows the PDF layout:
  - the letterhead and footer on every page, exactly as on the PDF (a
    page-sized picture behind the text, drawn by the same code as the PDF),
    with the page number as a live field;
  - EB Garamond **embedded** in the file, so it looks the same on a Mac or PC
    without the font installed;
  - the client and reference block, title, "Re:" line, the items table (same
    column widths, row heights, line breaks, merged title, "(Rate Only)" and
    note rows, repeated heading row), Terms and Conditions with hanging
    indents, the Terms page break, signatures and closing line.
  Everything except the letterhead is ordinary, editable Word text and
  tables.
- How it works: the app lays the document out as for the PDF
  (`PDFGenerator.wordLayout`) and the page builds the .docx from that
  (`js/docx-export.js`), then hands it back to be saved.
- Checked without a Mac using `tools/pdf-preview/word.py`. It builds the sample
  documents as .docx and renders them with LibreOffice for side-by-side
  comparison with the PDF preview.

## Batch 28 — choose several files at once when uploading
- **Upload Drawings…** (project Drawings tab, and the Drawings panel in BOQ and
  quotation editors), **Upload Documents…** (project Documents), and the worker
  and admin document **Upload…** buttons all let you choose several files in
  one go (⌘-click or Shift-click in the file window). Each file is copied in
  with the same category, link and expiry date chosen on the page.
- If some files can't be copied, the others are still added, and a message
  names the ones that failed.
- Replacing or re-linking a file, choosing a price-list file and restoring a
  backup still take one item, as they only make sense for one.

## Batch 29 — more space around the document title
- On every document (quotation, BOQ, invoice, delivery note) there is 6pt more
  space above and below the title ("QUOTATION", "BILL OF QUANTITIES", …), in
  the PDF and the Word copy alike (`PDFGenerator.titlePadding`,
  `TITLE_PADDING` in `js/docx-export.js`). 6pt keeps a full Qt26193-sized
  quotation on one page; 8pt pushed its last row onto page 2.

## Batch 30 — automatic backup to the shared iCloud folder
- ScaffoldPro keeps an up-to-date copy of everything in the shared iCloud Drive
  folder **Proficiency › William's Work**, in a folder called
  **ScaffoldPro Backup**:
  - `Database/`, `Projects/`, `Administration/`: the same layout as a normal
    backup, plus `Configuration/manifest.json`, so **Restore from Folder…**
    can restore it directly.
  - `Database History/<date>/`: the database as it was each day, for the last
    30 days.
- **When it runs:** about a minute after anything is saved (a burst of changes
  makes one backup), every 15 minutes, and when the app opens. Only new or
  changed files are copied, so after the first run each backup is quick.
  Files iCloud has moved off the Mac to save space aren't copied again.
- **Safety:** nothing is ever deleted from the iCloud copy. It pauses during a
  restore. Restoring from the iCloud copy while some of its files are still
  only in iCloud stops and asks you to use Finder's "Download Now" first.
- **Settings → Backup & Restore → Automatic iCloud Backup:** on/off (on by
  default), the folder, the status ("Up to date — last backed up 2 minutes
  ago", or what went wrong), Back Up Now, Choose Folder… (for a different
  folder) and Show in Finder. These settings are kept per Mac.
- If the Proficiency folder isn't in iCloud Drive yet (iCloud Drive off, or the
  share not accepted), the status says so and it tries again later. It creates
  "William's Work" inside Proficiency if needed, but never creates a separate
  "Proficiency" folder, because that wouldn't be the shared one.

## Batch 31 — client addresses: Address Line 1, 2, 3; no more over-wide lines
- The client form has **Address Line 1**, **Address Line 2** and **Address Line
  3** instead of one Address box. On documents each is its own line, followed
  by City / Postal Code and Country.
- **Long address lines are kept narrow** on quotations, invoices, delivery
  notes and BOQs (PDF and Word): at most 260pt wide, and broken after a comma
  where possible. For example, an address typed on one line prints as
  "38th Floor, Dorset House, Taikoo Place," / "979 King's Road, Quarry Bay,
  Hong Kong". Existing clients print this way without re-typing. The client's
  name wraps at 300pt.

## Batch 32 — BOQ as the company's BQ sheet, landscape (with prices) or portrait (no prices)
- BOQ PDFs, prints and Word copies are laid out exactly like the company's
  Google Sheets BQ ("CRBC 1635 - 80m Concrete Wall", in `docs/reference`), with
  every position, size and colour measured from it:
  - an orange banner with **PROFICIENCY QUOTATION** (Arial Bold 20);
  - two cream rows: **Project Code** (the project number), **Client** (the
    client reference, or the name), **Job Site** (the site's reference and
    name) and **Structure** (the BOQ's structure);
  - a blue heading row, then items 18pt high (Calibri 12): No., Item Name,
    Weight, Quantity, Unit / Total Rental Rate (HKD) with "$" at the left,
    and Total Weight;
  - a **Total Amount :** row with the total price and total weight.
- Choose the page in the BOQ editor's toolbar:
  - **Landscape — with prices** (the default, as on the sheet);
  - **Portrait — no prices**: No., Item Name, Weight, Quantity, Total Weight,
    with **Total Weight :** at the bottom.
  It's saved with the BOQ and can be changed after the BOQ is issued. Sale
  BOQs show "Unit / Total Sale Price".
- A BOQ too long for one page continues on the next, under the banner, info
  and heading rows. An item name too long for its cell is set slightly
  smaller rather than wrapped, as a spreadsheet would.
- **Fonts:** Calibri is used if it's installed on the Mac. Otherwise the app
  uses its bundled **Carlito** (SIL Open Font Licence), which has exactly
  Calibri's letter widths, so the layout is identical. The title uses Arial,
  which every Mac has.
- **Word copy:** one table with exact row heights, fills and 0.75pt rules. The
  banner, info and heading rows repeat on each page, and text is kerned like
  the original. Built with LibreOffice, every piece of text lands within 0.2pt
  of the original sheet. The Word export now kerns the letterhead documents'
  text too, as their PDFs do.

## Batch 33 — portrait BOQ back on the letterhead
- **Portrait** BOQs print as before batch 32: on the company letterhead, with
  "BILL OF QUANTITIES", the client and reference block (BOQ No., Project No.,
  Site Ref., Date), "Re:" and Structure lines, and the table No / Item
  Description / Unit / Qty / Unit Wt (kg) / Total Wt (kg), ending in
  **Total Weight**. There are no prices. PDF, Print and Word copies are all
  this layout.
- **Landscape** BOQs are unchanged: the company's BQ sheet ("PROFICIENCY
  QUOTATION") with prices.
- The BOQ editor's Page menu reads "Landscape — with prices" and "Portrait —
  letterhead, no prices".

## Batch 34 — standard manpower rates in one click
- **+ Standard Manpower Rates** (under a quotation's line items) adds the
  "Erection & Dismantle Manpower Rates" section, already filled in as on
  Qt26179:
  - R1 Scaffolder CP HK$ 2,300.00 / md
  - R2 Scaffolder HK$ 2,100.00 / md
  - R3 Rigger HK$ 2,000.00 / md
  - R4 General Helper HK$ 1,800.00 / md

  All four are "(Rate Only)", with the usual note about overtime and Sunday /
  public holiday rates.
- **Fill Standard Rates** in any rates section adds the standard rates to it,
  skipping workers already listed.
- The four workers, rates and units ("md") can be changed in **Settings →
  Standard Quotation → Standard manpower rates**. Leave a name blank to drop
  that worker. Each row can still be edited on the quotation afterwards.

## Batch 35 — BQ rates section, rate discounts, fuller project code; backup straight into William's Work
- **iCloud backup** goes straight into **Proficiency › William's Work**
  (Database, Projects, Administration, Configuration, Database History), with
  no "ScaffoldPro Backup" folder. An existing "ScaffoldPro Backup" folder's
  contents are moved up once, the next time it backs up. To restore, choose
  William's Work in **Restore from Folder…**.
- **Project Code** on the BQ sheet reads "project number - project name -
  Sale/Rental - client", e.g. "26210 - Working Platform for Perimeter Wall -
  Rental - CRBC".
- **Rates after the total** (landscape BQ): in the BOQ editor, **+ Standard
  Manpower Rates** or **+ Rates Section** adds a section below the items. It
  has a title, rows (worker/item, rate, per), a note, **Add Row**, **Fill
  Standard Rates** and **Remove Section**. On the sheet, "Total Amount :"
  becomes "Subtotal :", followed by a blue title row, R1, R2… rows with
  "$ 2,300.00 / md" and "(Rate Only)", and the note. The portrait
  (letterhead) BOQ has no prices, so it doesn't list them.
- **Discount on an item's rate:** each BOQ item now shows its unit rate with
  a **Discount** button (a percentage off the rate, or an amount off each
  unit). The BQ sheet prints only the discounted rate and total. The discount
  isn't mentioned anywhere on the document. Quotations made from the BOQ, or
  importing its items, use the discounted rates.

## Batch 36 — Stock list, Accounts, icon discount button

- **Discount button** — the "Discount" text button on quotation, BOQ and
  invoice lines is now a small percent-tag icon. It turns blue when a discount
  is set; hover it to see the discount.
- **Stock** (sidebar, ⌘6) — every material-list item we hold, showing what's
  **in the yard**, **on hire** (by project) and **owned** in total.
  - Issuing a delivery note books its items out automatically. Delivery notes
    from a Sale quotation or invoice count as sold rather than on hire.
    Changing an issued note back books the items in again.
  - **Receive Stock**, **Record Return** (from a project), **Stock Count**
    (sets the yard quantity and records the difference) and **Write Off**.
  - A Movements tab lists every movement. Manual entries can be deleted.
  - Both lists export to CSV.
- **Accounts** (sidebar, ⌘7) — choose a period (this month, last month, this
  year, last year, all time or custom) to see what was invoiced and received,
  expenses, net cash, and what's outstanding or overdue today.
  - Tabs: Receivables, Payments Received, Expenses (add, edit or delete),
    By Project and By Month.
  - Each tab exports to CSV in `Administration/Accounts`.
- **Invoice payments** now record a date, a method (bank transfer, cheque,
  cash and so on) and a reference, which feed the Accounts page.
- The Go menu and sidebar shortcuts are now ⌘1–⌘9: Admin is ⌘8 and
  Settings ⌘9.

## Batch 37 — "+ Section" on the BQ: amounts added to the total

- In the BOQ editor, **+ Section** (it replaces "+ Rates Section") adds items
  that aren't priced by unit, such as Delivery or Design Fees. Each row has a
  No. (D1, D2… when left blank), a description and an amount.
- On the landscape BQ sheet these rows follow **"Subtotal Amount :"**, with
  "N/a" in the Total Weight column, then **"Total Amount"** with the amounts
  added. The layout is measured from the company's sheet for Mr. Law's
  container access platform; the signature block isn't included.
- The editor and the project's BOQ list show the total with these amounts
  added.
- **+ Standard Manpower Rates** still adds the rates section, which now comes
  after "Total Amount".
- The BOQ's **Notes** now also appear on the landscape BQ, in a box under the
  table. "Notes:" is added at the top if it isn't already there, and web
  addresses (e.g. pfitnet.com/TC) are blue and underlined.
- **Fit to page:** if a BQ sheet is slightly too long for one page, it is
  shrunk onto one page, as Google Sheets' "Fit to page" does. It shrinks to no
  less than 70%; longer sheets still run over several pages at full size.
  The Word copy matches.
- The amounts aren't copied when a quotation is made from the BOQ. Add them
  to the quotation's own priced section.

## Batch 38 — Delivery notes laid out like the company's own (DN26038a)

- **Header**: Our Ref. No., Site Ref. and Date on the right, **BY HAND ONLY**
  under them, then the title **Delivery Note**.
- **Details under the title**: Delivery Address, Site Reference (the site's
  reference and name), Project (Sale/Rental and the project name) and
  **Contact Person** (in bold), each as a bold label followed by ": value".
  Rows with nothing to show are left out.
- **Table**: No | Item Description | Unit Weight | Qty | Total Weight, with
  "kg" set at the right of each weight and a **Total Weight:** row. Unit
  weights come from the material list. Rows are shorter, as on the company's
  note, so 21 items fit on page 1.
- **Receipt lines**: "Received By : ____ Date : ____" and "Full Name : ____
  Contact No. : ____" replace the two signature boxes. They follow the table.
  If they don't fit on the page, they start a new page headed "Ref.: <DN no.>".
- **Contact Person** is a new field in the delivery-note editor. It starts
  with the site's contact person.
- **Letterheads (all documents)**: "BY EMAIL ONLY" / "BY HAND ONLY" now sit
  under the reference block even when the client's address runs to more
  lines, as on the company's Qt26179 and DN26038a. The title follows below
  both.
- **Addresses**: an address line typed with a comma at the end keeps it
  ("38th Floor, Dorset House,").
- The Word copy has the same layout.

## Batch 39 — Drag and drop to reorder

- **BOQ lines** and the **quotation's extra sections** (priced rows, rates,
  notes) are reordered by dragging instead of ↑ / ↓ buttons. Grab a line or
  section by its handle (⋮⋮) at the left and drag it up or down. The others
  slide out of the way; let go to save the new order.
- The page scrolls when you drag near its top or bottom edge.
- From the keyboard, focus a handle (Tab) and press ↑ / ↓ to move it one
  place.
- Handles appear only on drafts with at least two lines or sections; issued
  documents can't be reordered.

## Batch 40 — Locate File, BOQ mark-up on the rates, rounding, project code, delete

- **Locate File** shows a file in Finder. It appears on every uploaded file,
  drawing, company or worker document and backup, replacing "Reveal".
  - It's also on every BOQ, quotation, invoice and delivery note: in each
    editor's toolbar and on each row of the project's lists.
  - For these it shows the PDF last exported, else the newest PDF or Word
    copy with the document's number, else the folder it will be saved in.
  - A missing file's "Locate File…" is now **Find Moved File…**.
- **BOQ mark-up** no longer changes the stored unit prices. Lines keep their
  list prices, and the mark-up is applied to the rates shown and printed,
  each rounded to 0.1, as on a quotation.
  - A quotation made from the BOQ, or with its items imported, takes the
    mark-up as its own **markup %**. Its lines keep the list prices, and a
    BOQ line's discount becomes the same discount on the quotation line.
  - A mark-down is priced into the lines instead.
  - Draft BOQs made before this change are converted when the app starts.
    Issued ones are left as printed until they're set back to Draft.
- **Rounding**: Settings › Standard Quotation › "Marked-up unit prices"
  chooses between rounding off to the nearest 0.1 (4.83 → 4.80) and rounding
  up to the next 0.1 (4.83 → 4.90). It applies to quotations and BOQs.
- **Project Code** can be changed in Edit Project Details.
  - The project's folder (Documents › ScaffoldPro › Projects) is renamed
    and every file kept in it is re-pointed.
  - Draft documents numbered with the old code get the new one. Issued
    documents keep the numbers they were sent with.
- **Delete…** for BOQs, quotations, invoices and delivery notes, in the
  editor and on the project's lists.
  - A draft asks once. An issued document asks again and you type its
    number to confirm.
  - Deleting an invoice removes its payments from Accounts. Deleting a
    delivery note puts its items back in stock. Linked drawings stay with
    the project, and exported PDF and Word files stay in the folder.

## Batch 41 — One-click install from the Desktop

- **Install ScaffoldPro.command** (in the Scaffold-Pro folder, beside
  ScaffoldPro-native) builds and installs the app when you double-click it.
  Copy it to your Desktop.
  - The first time, it finds the ScaffoldPro-native folder, or asks you to
    drag it into the window, and remembers it in `~/.scaffoldpro-install-path`.
  - If the folder is a git copy, it fetches the latest version first. If it
    can't update, it installs the version you have.
  - It checks that Apple's Command Line Tools (the Swift compiler) are
    installed, runs `./install.sh`, and keeps the window open so you can
    read the result.
  - If macOS says it can't be opened, right-click it › Open › Open. You only
    need to do that once.

## Batch 42 — Drawings follow the quotation and print after it

- A quotation made from a BOQ, or with a BOQ's items imported, has that
  BOQ's drawings as well as its own.
  - The quotation's Drawings panel shows them tagged "From <BOQ no.>".
  - They're looked up live, so a drawing added to the BOQ later appears on
    the quotation too.
- When a quotation or BOQ is exported as a PDF or printed, its image and PDF
  drawings are added after its own pages: page 1 the quotation, page 2
  drawing 1, page 3 drawing 2, and so on.
  - The order is the one numbered in the Drawings panel: the BOQ's drawings
    first, then the quotation's own, each oldest first.
  - Every page of a PDF drawing is added as it is. Each image goes on a
    page of its own, fitted inside a small margin and turned landscape if
    it's wide.
  - When printing, drawing pages larger than the paper (e.g. A1) are scaled
    down to fit. The document's own pages print at full size.
  - DWG / DXF drawings, and files that are missing or password-protected,
    are left out.
- The Word copy is unchanged: it holds only the document itself.

## Batch 43 — Terms follow on when they fit; the BOQ goes with its quotation

- **Terms and Conditions** now follow straight after the quotation's total
  when the whole section fits in the space left on that page. If it doesn't
  fit, it starts a new page.
  - The signatures are placed separately. If the Terms fit but the
    signatures don't, the Terms stay and the signatures start the next page.
  - "-[Remainder of this page is intentionally left blank]-" is left out
    when there's no room for it, instead of taking a page of its own.
  - Settings › Standard Quotation › "Terms & Conditions page": "Follow on
    the same page when they fit" is the default. "Always on a new page"
    still works as before.
  - The Word copy breaks pages in the same places.
- **The BOQ a quotation follows** is added to the quotation's PDF (export and
  print) as its first drawing: the quotation's pages, then the BOQ, then
  the other drawings.
  - The BOQ is made fresh each time, as it's set up: the landscape BQ sheet
    with prices, or the portrait letterhead.
  - It's listed first in the quotation's Drawings panel, with **Open BOQ**
    and **Locate File** buttons.

## Batch 44 — Signed quotations; sharing with other Macs

- **Signed quotations to upload** (Dashboard): issued quotations with no
  signed copy from the client yet. Quotations already invoiced (going ahead
  without a signed copy on file) come first.
  - Each row has **Upload Signed Copy…** (a PDF, or a JPEG, PNG, HEIC or TIFF
    photo or scan). You can also drop the file onto the row.
  - **Not Needed** takes a quotation off the list.
  - The copy is saved as "<number> - Signed.pdf" in the project's Quotations
    folder. It shows as a "Signed" pill in the project's quotation list.
  - The quotation editor shows a bar once the quotation is issued, with
    Open, Locate File, Replace… and Remove (the file stays in the folder).
    The bar also takes a dropped file.
- **Share with Other Macs** (Settings): several people work on the same data,
  each on their own Mac, through a folder shared in iCloud Drive. No server
  is needed.
  - **Share My Data…** makes a "ScaffoldPro Team" folder in the chosen iCloud
    Drive folder and copies in the projects, documents and database.
  - Share that folder in Finder, then the others press **Join a Shared
    Folder…**. Joining leaves a Mac's own data untouched; it comes back after
    **Stop Sharing on This Mac…**.
  - Each Mac writes only its own change log in the folder
    (Database/<Mac>/<store>.json), so iCloud never has two versions of one
    file to choose between. The newest change to each record wins, and
    deletions carry across.
  - Paths to files in the folder are kept relative, as the folder is at a
    different place on each Mac.
  - The other Macs' logs are checked every 2 seconds. Their changes appear by
    themselves, usually within seconds, as soon as iCloud has carried them
    across.
  - The page refreshes when you're not typing in a field or using a dialog,
    and shows "Updated with changes from …".
  - The sidebar shows who the data is shared with. Each project's history
    shows who did what.
  - Settings lists the Macs using the folder and warns when one runs an older
    version of ScaffoldPro. install.sh now records the version in
    version.txt.
  - Files iCloud has moved off a Mac to save space are downloaded when opened.
  - Restore is turned off while sharing, since it would replace everyone's
    data.

## Batch 45 — Install ScaffoldPro pulls through GitHub Desktop

- **Install ScaffoldPro** first tries to pull the latest version from
  Terminal. If Terminal can't sign in to GitHub (e.g. a GitHub account that
  uses Google sign-in), it opens GitHub Desktop on the Scaffold-Pro folder
  and asks you to press **Fetch origin**, then **Pull origin**.
  - After you press Return, it checks that nothing is still waiting to be
    pulled. Type S to install the version you have.
- A copy of the Install file kept elsewhere (e.g. on the Desktop) now
  updates itself from the one in Scaffold-Pro.

## Batch 46 — The BOQ's structure in the quotation's subject line

- A quotation that follows a BOQ has the BOQ's **Structure** in its "Re:"
  subject line, e.g. "GL-28 Works - Rental - Access platform for louvres".
  - This applies when it's created from the BOQ, or when the BOQ's items are
    imported into it later.
  - Changing the structure in the BOQ, or switching the quotation between
    Rental and Sale, keeps the subject line in step.
  - A subject line typed by hand is never changed.
  - Draft quotations made before this get the structure when ScaffoldPro
    opens. Issued ones are left as they are.

## Batch 47 — Tidier Settings, client default markup, update check

- **Settings is grouped into collapsible sections**, each with a
  one-line description. Click a heading to open or close it:
  - General
  - Documents & Numbering
  - Quotations
  - Invoices
  - Share with Other Macs
  - Backup & Restore
  - Data Location

  The open sections are remembered, and links such as settings.html#team open
  that section.
- **Default Markup (%) for each client** (Clients › edit).
  - New BOQs for the client's projects start with it, and a BOQ's mark-up
    carries on to its quotation as before.
  - A quotation made without a BOQ starts with the client's markup.
  - The BOQ and quotation editors show the client's default. When the
    document uses a different markup, they offer "Use 15%".
  - The client list has a Default Markup column.
- **Update check when ScaffoldPro opens**, and from ScaffoldPro › Check for
  Updates….
  - install.sh records the commit it built (commit.txt) and its source folder
    (source.txt).
  - The app fetches from GitHub in that folder without asking for a
    password. It compares GitHub's latest (as fetched by it or by GitHub
    Desktop) and the folder's own latest with what's installed. If git can't
    sign in, it asks GitHub's web API, which works for public repositories.
  - If there's a newer version, **Update Now** runs Install ScaffoldPro and
    closes the app. The new build opens when it's done.
  - install.sh now closes an open ScaffoldPro before replacing it.

## Batch 48 — Tab to the next quantity; Delete stays on the page

- In the BOQ, quotation, invoice and delivery note editors, **Tab** (or
  Enter) in an item's quantity saves it and goes to the next item's
  quantity. **Shift-Tab** goes to the previous one.
  - The number is selected, ready to type over.
  - The place is kept when the table redraws after saving, including
    anything already typed (js/qty-tab.js).
- The **Delete** key no longer goes back to the previous page when the
  cursor isn't in a text box (a web view's built-in behaviour). ⌘[ still
  goes back.

## Batch 49 — Quotations into one PDF; structures and project totals

- **Combine into PDF…** (project › Quotations): tick the quotations you want
  (or all of them with the tick box in the header), then press the button.
  - Choose whether to include each quotation's drawings. The BOQ it follows
    is added first, then the other drawings, right after that quotation.
  - The quotations are built fresh, one after another, into a single PDF.
    It's saved in the project's Quotations folder (e.g.
    "26017_Quotations_Qt26195+Qt26194_with drawings.pdf") and opened.
- The **BOQ list** shows each BOQ's structure under its number.
- The **quotation list** shows the structure of the BOQ each quotation
  follows, or else its subject line, and a BOQ column.
- **Project totals**:
  - the BOQ tab gives the project total weight;
  - the Quotations tab gives the project total of the quotations;
  - cancelled ones aren't counted.

## Batch 50 — Updating behind a loading screen (no Terminal)

- **Update Now** no longer opens Terminal. ScaffoldPro shows a loading
  screen over its window while it updates itself in the background:
  1. **Getting the latest version**: a git pull in the source folder that
     never asks for a password. If git can't sign in to GitHub, GitHub
     Desktop opens on Scaffold-Pro and the screen says "press Fetch
     origin, then Pull origin". It carries on by itself once the new
     version has arrived, or Cancel stops it.
  2. **Building the new version** (about a minute), **Putting it
     together**, **Finishing**, **Installing**. The progress bar follows
     install.sh, whose messages go to ~/Library/Logs/ScaffoldPro
     Update.log instead of a Terminal window.
  3. install.sh closes this copy, installs the new one and opens it.
- If the build fails, the screen says why (the compiler's error line),
  with **Show Log** and **Close**. The version you had keeps running,
  unchanged.
- install.sh now closes a running ScaffoldPro with a signal (pkill)
  instead of AppleScript. This avoids macOS asking for permission to
  control ScaffoldPro.
- Install ScaffoldPro (the Desktop file) still uses Terminal. It's for
  installing the first time.

## Batch 51 — Material List: drag to reorder, aligned columns

- Items in the Material List can be dragged into order within their
  category using the ⋮⋮ handle. With the handle focused, ↑ / ↓ also move an
  item.
  - The order is saved (PriceListItem.sortOrder) and used wherever
    materials are listed, e.g. the BOQ and quotation item pickers. Items
    never moved follow, by item code.
  - A duplicate goes right after its original.
  - Dragging is paused while a search is typed in, since only some of the
    items are showing then.
- Every category's table now has the same fixed column widths, so the
  Weight, Rental and Sale columns line up down the whole list.

## Batch 52 — Automatic local backups at 12:00 a.m. and 12:00 p.m.

- ScaffoldPro makes a full local backup by itself every day at 12:00 a.m. and
  12:00 p.m. It's the same as Create Backup: the database, every project
  folder and the Administration documents, in Application Support ›
  ScaffoldPro › Backups, named "…_Auto".
  - Checked every minute and soon after opening. If the Mac was asleep or
    ScaffoldPro was closed at 12:00, the missed backup is made then.
  - After each one, automatic backups more than 7 days old are deleted.
    Manual and before-restore backups are never deleted.
  - Settings › Backup & Restore lists them as "Automatic (12:00)". The
    Dashboard's backup reminder now counts them too.
  - On APFS the copies are clones, so unchanged files take no extra disk
    space.

## Batch 53 — Fix: the update could hang on "Installing…"

- The in-app update relied on install.sh closing the running app from
  outside, and it could hang there. Now:
  1. install.sh only builds (SCAFFOLDPRO_BUILD_ONLY=1, which stops after
     signing with "✅ Built.").
  2. The app starts a small helper that runs on after the app has closed,
     then closes itself (a forced exit after 3 seconds if quitting is held
     up).
  3. The helper waits for it to close (force-quitting it after 15
     seconds), copies the new build next to the old one, moves the old
     one aside, moves the new one in, deletes the old one, and opens
     ScaffoldPro.
- If macOS doesn't allow the swap (e.g. System Settings › Privacy &
  Security › App Management), the old copy is kept and reopened. The next
  launch says why the update couldn't be installed.
- If building takes more than 8 minutes, the loading screen offers Show Log
  and Stop, so it can never sit there with no way out.

## Batch 54 — Icon buttons; Select on every document list

- **Icon buttons** (js/icons.js, on every page). Buttons for common actions
  show an icon instead of the word; hovering shows the word as a tooltip:
  - Locate File (a folder with a magnifier)
  - Delete / Remove (a red bin)
  - Print
  - Open
  - Edit
  - Duplicate
  - Show in Finder (a folder)
  - Archive
  - Rename

  Buttons where the words matter (Export PDF, Save, Upload…, Replace…)
  keep them.
- **Select** on the project's BOQ, Quotations, Invoices and Delivery Notes
  tabs (js/doc-select.js). The tick boxes only appear after pressing
  Select; then clicking a row ticks it instead of opening it. The toolbar
  offers:
  - **Select All**
  - **Export PDF**: all the ticked documents in one PDF. BOQs and
    quotations can include their drawings, and a quotation also the BOQ it
    follows. It's saved in the project's folder for that kind of document
    and opened.
  - **Locate Files**: one Finder window with all their files selected. It
    says which ones haven't been exported yet.
  - **Done**. Esc also leaves Select.
- The quotation, invoice and delivery note letters are each built by one
  function (quotationLetter / invoiceLetter / deliveryNoteLetter), shared by
  single export and the one-PDF export.

## Batch 55 — Install ScaffoldPro sets up Homebrew, gh and the GitHub sign-in

- **Install ScaffoldPro** now, before getting the latest version:
  1. installs **Homebrew** if it's missing, with Homebrew's official
     installer (it asks for the Mac password), and adds it to ~/.zprofile;
  2. installs **gh**, GitHub's command-line tool (`brew install gh`), if
     it's missing;
  3. if gh isn't signed in, runs `gh auth login --web`. That shows a
     one-time code and opens github.com in the browser, where signing in
     with Google works;
  4. runs `gh auth setup-git`, so git uses that sign-in.
- After that, `git pull` works from Terminal and from ScaffoldPro's own
  **Update Now** without GitHub Desktop. GitHub Desktop stays as the
  fallback.
- Each step is skipped when it's already done. If one fails, the installer
  carries on as before.

## Batch 56 — Install ScaffoldPro with a window instead of Terminal

- **Install ScaffoldPro.app** (in the Scaffold-Pro folder; the Terminal
  installer also puts a copy next to itself, e.g. on the Desktop) installs
  and updates ScaffoldPro in a window:
  - steps with ticks: Homebrew → GitHub tool (gh) → Sign in to GitHub → Get
    the latest version → Build ScaffoldPro → Install and open
  - a progress bar, and **Show Details** with everything the steps print
  - while signing in: GitHub's one-time code, with **Copy Code** and **Open
    GitHub** (the browser opens by itself)
  - Homebrew's Mac password is asked for in a normal password window
    (sudo askpass), not in Terminal
  - on failure: the reason, the details, and **Try Again**
- How it's put together:
  - `Contents/MacOS/install-launcher` (bash) finds the folder (remembered /
    next to the app / the usual places / Spotlight / "choose folder"). It
    checks Apple's Command Line Tools (a dialog offers to install them),
    then builds the window from ScaffoldPro-native/installer/InstallerUI.swift
    (once, and again whenever that file changes) and opens it.
  - The window runs installer/install-steps.sh, which reports its progress
    in "@@" lines. That script can also run on its own.
  - If the window can't be built or opened, the Terminal installer runs
    instead.
- The Terminal installer (Install ScaffoldPro.command) keeps working and
  does the same steps.

## Batch 57 — Dashboard, grouped item picker, BOQ defaults, drag-and-drop, one-click editing, no tax

- **Dashboard:**
  - "Signed Quotations to Upload" is merged into **Quotations Awaiting
    Reply**, which keeps its look. It lists issued quotations with no
    signed copy yet: "Valid to …", or "Invoiced, not signed" for ones
    already invoiced.
  - Each row has an upload icon (file the signed copy) and a cross (not
    needed: accepted by email, or not going ahead). A signed PDF or photo
    can also be dropped onto the row. Filing it, or marking it not needed,
    takes the row off the list.
  - Active & Recent Projects and Unpaid Invoices have swapped places.
- **Add Materials** (BOQ, quotation, invoice, delivery note): items come
  in a box per category (Base Items, Standards (with Spigots), Ledgers…),
  in item-code order, with the same column widths in every box
  (js/item-picker.js).
- **Settings → BOQ Defaults:** materials and quantities every new BOQ
  starts with, priced for its Sale / Rental mode (`defaultBOQItems` in
  the company settings). Items since deleted from the material list are
  flagged in Settings and skipped.
- **Drag and drop:** drag drawings from Finder onto the Drawings panel of
  a BOQ or quotation, or onto the project's Drawings or Documents
  section. Documents go under the category chosen there, and drawings are
  linked to the BOQ / quotation chosen (js/file-drop.js →
  `files:dropIntoProject`). Files over 60 MB still need the Upload button.
- **One click to edit another box:** saving box A redraws the table, which
  used to throw away box B as it was clicked. The same box is now focused
  again in the new table, keeping anything typed and where the cursor was
  (js/keep-focus.js; the editors and the project page).
- **No tax** (none on sales in Hong Kong): the tax / VAT rate, "prices
  include tax" and VAT number fields are gone from Settings, clients,
  quotations and invoices. New quotations carry no tax. An older quotation
  or invoice that still has a tax rate shows the box, so it can be set
  to 0.

## Batch 58 — Launch screen with the update check; Save Settings bar

- **Launch screen** (launch.html, `LaunchScreen` in main.swift). As
  ScaffoldPro opens, a rounded navy card shows the scaffold logo building
  itself: base plates, standards, ledgers, rosettes, then the yellow brace
  with a glow. "ScaffoldPro" follows letter by letter, then "Checking for
  updates…". The update check happens here, before the main window opens,
  so no question pops up a few seconds after opening:
  - up to date → "Up to date", and the main window opens as the card fades
  - newer version → "A new version is available" with **Update Now** /
    **Later** (Return / Escape). Update Now shows the update's progress on
    the same card, then ScaffoldPro reopens by itself.
  - GitHub slow to answer → the app opens after 10 seconds anyway, and a
    late answer is offered as before
- The updater now shows its progress through an `UpdateScreen`: the launch
  card, or the sheet used by ScaffoldPro › Check for Updates….
- **Save Settings** is pinned to the bottom of the window as a proper
  footer, so rows no longer show beneath it. It says "Unsaved changes"
  while there are some.

## Batch 59 — Bigger drop boxes, scrolling while dragging, reliable "+ Add", pinned items

- **Drop boxes:** the Drawings panel of a BOQ or quotation, and the
  project's Drawings and Documents sections, each have a large dashed "Drop
  drawings / documents here" box. While files are dragged over the window,
  every box grows and lights up.
- **Scrolling while dragging:** holding files near the bottom (or top) of
  the page scrolls it, faster the closer to the edge (js/file-drop.js).
- **"+ Add" right after typing a search** now always works. On the Mac each
  search answer takes a moment, and one arriving mid-click used to replace
  the button being clicked. The list now waits while the mouse button is
  down, and answers to older searches are dropped (`pickerSearch`).
- **Pinned items:** the star on each item in "Add Materials" pins it to a
  ★ Pinned box at the top of the list, in every editor. Pins are kept with
  the material list (`PriceListItem.isPinned`, `priceListItems:setPinned`),
  so every Mac sees them.

## Batch 60 — Combine counts, monthly vs one-time charges, minimum monthly rental, Back button

- **Combine into one BOQ / delivery note:** in Select mode on a project's
  BOQ or Delivery Notes tab, tick two or more and press **Combine into One
  BOQ** (or Delivery Note). A new Draft opens, with each item once and its
  quantities added together (`boq:combine`, `deliveryNotes:combine`). The
  originals are unchanged, and the new one's notes say where it came from.
- **Monthly charge vs one-time charge** (`ChargeSplit`):
  - Monthly: the monthly rental, plus any priced section charged per month.
  - One-time: delivery, plus priced sections charged once.
  - Sections charged per day or week show separately ("+ 500.00 per week").
  - A Sale quotation has no monthly charge: it's all one-time.
  - Shown on the Dashboard's Quotations Awaiting Reply, on the project's
    Quotations tab (two columns and the project total bar), and under a
    quotation's totals.
- **Charged once / per day / per week / per month** on each priced section
  of a quotation. The PDF's section title says "(per week)" etc.
- **Minimum monthly rental charge:** Settings › Quotations sets the amount
  (HK$1,000 by default), and "Minimum Monthly Rental Charge › Apply" on a
  rental quotation lifts a smaller monthly rental to it. The PDF shows the
  subtotal, then the minimum. An invoice made from the quotation gets an
  adjustment line, so it charges the same.
- **Back** (top left) on the project page and in the BOQ, quotation,
  invoice and delivery note editors: back to the page it was opened from.

## Batch 61 — Unit Rates for a client, from the Material List

- **Material List › Unit Rates…** switches the list into picking mode:
  tick items (or click their rows). Switching between SP and SCAFOM keeps
  the ticks, so one sheet can have items from both lists. **Make Unit
  Rates PDF…** then asks:
  - who it's for (any client, or none); choosing a client fills in their
    default markup
  - the markup / markdown %
  - an optional "Re:" line and remarks
- The PDF is laid out like a quotation, on the letterhead, titled **UNIT
  RATES**. Its columns are No., Item Description, Unit Weight (kg), Unit
  Monthly Rental (HK$, SCAFOM converted from EUR, with the markup and
  Settings' 0.1 rounding) and Unit. List and category names aren't shown.
  It's saved in the company folder's "Unit Rates" folder, then opened
  (`priceLists:unitRatesPDF`).

## Batch 62 — Stock by site, and delivery notes from a quotation

- **Stock › By Site** is a new subtab listing what's out on hire at each
  site. Each site gets a card showing which companies manage the materials
  there (each project's client), the piece count and the tonnage. Each
  row shows the item, the quantity on site, its weight, the project (a
  link) and the company managing it. You can filter by site, and search
  by item, project or company. **Export CSV** saves the list shown.
  Projects without a site are listed on their own. (`ProjectRef` now
  includes the project's site and client.)
- **Delivery note › Import from Quotation** lets you pick one of the
  project's quotations (not cancelled ones; newest first; the one the
  note was made from is chosen to start with). It copies that
  quotation's materials into a Draft note. Delivery and other charges
  aren't copied. If the note already has items, you choose either to
  replace them or to add the quotation's quantities to the matching
  items (`deliveryNotes:importQuotation`).

## Batch 63 — Liabilities, and employees on the payroll

- **Accounts › Liabilities** records what the company owes: loans,
  supplier bills, hire purchase, credit cards, tax, MPF and more. Each
  one keeps the amount, who it's owed to, the start and due dates, an
  optional monthly repayment and interest rate, a reference and notes.
  - Clicking a liability shows the payments made against it. You can
    record a new payment (it starts at the monthly repayment or the
    balance) or remove one.
  - The list shows the paid amount, the balance and a status (Owing,
    Overdue or Paid off). Items still owing come first, ordered by due
    date. "Show paid off" also lists the settled ones.
  - A summary line shows the total owing, the overdue total and the
    monthly repayments. Export CSV works on this tab too.
  - Data: `liabilities.json` and `liability_payments.json` (synced like
    every other store); `accounts:saveLiability`, `deleteLiability`,
    `addLiabilityPayment`, `deleteLiabilityPayment`.
- **Admin** now has two tabs: **Workers & Documents** (as before) and
  **Employees**.
  - Each employee has a Chinese name, position, phone, an optional link
    to the matching worker record, **Full-time / Part-time**, and how
    they're paid: monthly salary, by the day or by the hour, with their
    usual days or hours a month.
  - Each employee also has allowances, employer MPF (5% of pay, capped
    at HK$1,500 a month), annual leave days, bank account, start and
    leaving dates, and notes. Former employees stay on record, off the
    payroll.
  - Cards show the headcount (full-time / part-time), a usual month's
    pay, the employer MPF and the total payroll cost. The list can be
    searched and exported to CSV.
  - **Record Pay…** takes a month and the date paid. It lists current
    employees, with days or hours editable for daily and hourly staff,
    and pay and MPF worked out but editable. It then adds one expense
    per employee under the new "Salaries & MPF" expense category. An
    employee's month already recorded is skipped (reference
    `PAY yyyy-mm E00n`).
  - Data: `employees.json` (synced); `employees:list`, `save`, `delete`,
    `recordPayroll`.

## Batch 64 — Chinese material names, the material list always in step, and signature/terms on the landscape BOQ

- **Chinese names for every material.** Items have a Chinese name (中文名稱)
  for workers who don't read English. It is worked out from the English name
  using the wording of the official SP Material List (速拼國際 報價): for
  example 橫杆, 加固橫杆, 企柱(帶駁芯) / 企柱(無駁芯), 斜杆, 踏板, 窄踏板
  (160/190), 踢腳板, 揭蓋板, 鋁樓梯, 輔助梯, 斜梯, 掛梯, 外扶手 / 內扶手,
  短底座, 頂積, 腳套, 雙尖扣/雙接手扣, 駁芯手扣, 三角架, 三角板, 轉角板,
  轉彎板, 扣牆通 and 桁條.
  - All 217 SP and SCAFOM items get one (`chineseMaterialName`). Items added
    later get one when they're created, and existing items are filled in
    once at launch.
  - The name can be typed or changed in the Material List (Edit, or Add
    Item). Clearing it leaves the item without one.
  - It shows in the Material List, the item pickers (search finds Chinese
    too), the BOQ and delivery note editors, and on **delivery note and BOQ
    PDFs and Word copies**, after the English name (e.g. "2.07m Ledger  橫杆";
    the size isn't repeated).
  - Settings › BOQ Defaults can turn it off on documents.
- **The material list is always kept the same on every Mac.** In a shared
  folder it already was. A Mac working on its own data now keeps its
  material list (both price lists and every item, including pins, order and
  Chinese names) in step through iCloud Drive: in "Proficiency › ScaffoldPro
  Material List", or at the top of iCloud Drive if the Proficiency folder
  isn't there.
  - This uses the same per-record change logs as team sharing
    (`TeamSync(…, only: materialStores)`, `TeamSync.material`).
  - The first time, list and item ids are made the same on every Mac (from
    the list's source and each item's code and name), and every reference
    to them is updated. The same list made on two Macs then lines up
    instead of appearing twice.
  - A Mac's list goes in as of when it was last changed there, so newer
    changes made elsewhere win. A list the app has only just created never
    replaces anyone's.
  - The Material List page says how it's kept in step (`priceLists:syncStatus`).
- **Landscape BOQ: Terms and Signature.**
  - A **Terms & Conditions** box goes after the Notes box, in the same
    style. "Use Standard Terms" fills it from Settings › BOQ Defaults.
  - A **Signature section** can be ticked. It goes under the table as on
    the company's own sheet (Mr. Law's): "For and On Behalf of" the company,
    with the signatory and title from Settings › Quotations, and "Accepted
    By" the client, with "Date :". Each has a line to sign on and no box.
  - Both are in the PDF and the Word copy, and can be changed on an issued
    BOQ too, like the notes (`boq:updateSheetExtras`).
  - `tools/pdf-preview/sheet.py law --sign` checks the result against the
    original.

## Batch 65 — The rest of the official SP Material List

- The **57 items on the official SP list (速拼國際 報價, GH codes) that
  weren't in the SP Material List** are added. Each has the list's weight,
  rental price (出租單價 per month) and sale price (售價), its Chinese name
  as written there, and "SP Product No.: GH…" in its notes:
  - Base items: 600mm swivel U jack and swivel base jack (搖擺頂積 / 底座),
    special base plate for balconies, special base jack with round plate,
    timber sole board (木墊板)
  - Spigot (駁芯) and round spigot (圓形駁心)
  - 3.07m ledger, and 3.07m bridging ledger (拱橋橫杆)
  - **Lattice Girders**: 4.14m, 5.14m and 6.14m lattice girders (桁條) and
    the 7.71m lattice truss (桁架)
  - Face braces: 1.09 / 1.57 / 1.80 / 2.07 / 2.57m × 1.0m, 2.57 × 1.5m and
    3.07 × 2.0m
  - Steel decks: 1.80m and 3.07m (0.32m wide); 0.60 / 0.90 / 1.09 / 1.80m
    narrow decks (160)
  - Toe boards: 1.80m and 3.07m; 0.73m triangular steel deck guard (三角板圍)
  - **Catch Fans**: catch fan brace (斜棚斜桿) and catch fan / plank clip
  - **Couplers & Clamps**: L bolt, long L bolt Ø16 × 250mm, right angle
    coupler (死扣), swivel coupler (生扣), beam clamps (工字扣), EN74 swivel
    coupler, guard rail clamp (老鼠仔)
  - **Wall Tie Tubes** (扣牆通) 0.85–2.0m, **Tubes** (喉通) 0.8–6.0m
  - **Racking** (貨架): uprights, beams and base
  - **Bolts & Nuts**: M12 × 65 bolt and M12 nut, sale only
- New installs get them in the bundled list (`resources/sp_pricelist.json`).
  Existing SP lists get them once at launch (`addMissingSPProducts`), at the
  end of their categories. Items already there by name (even archived ones)
  are left alone.
  - These items have the same id on every Mac (`item_sp_<GH code>`), so Macs
    adding them at the same time — sharing a folder, or keeping the material
    list in step through iCloud Drive — end up with one copy.

## Batch 66 — Item names in English or Chinese, not both

- Delivery notes, quotations and BOQs print their item names in **one
  language**: English, or Chinese (中文, the materials' Chinese names from
  the Material List). They no longer print both side by side.
  - Each editor's toolbar has **Items in: Default / English / 中文 Chinese**
    (`deliveryNotes:setLanguage`, `quotations:setLanguage`,
    `boq:setLanguage`). It can be changed on issued documents too, since it
    only changes how the document is printed.
  - "Default" follows Settings › BOQ Defaults › "Item names on delivery
    notes, quotations and BOQs" (`documentLanguage`), which is English
    unless changed.
- In Chinese, an item with no Chinese name keeps its English one.
  - On delivery notes and BOQs (letterhead and landscape BQ sheet), the item
    table's headings are in Chinese too: 編號, 物料名稱, 單位重量, 數量,
    總重量, 單位租價 / 總租價 or 售價.
  - A quotation stays an English letter; only its item names change.
  - The PDF and the Word copy both follow the choice.

## Batch 67 — Delivery schedule for quotations

- **Quotation › Delivery Schedule** (under the quotation) plans and records
  how the quoted materials go to site.
  - The quotation's materials are listed down the side (not delivery
    charges or extra sections), with **Day 1, Day 2…** across ("+ Add Day").
    Type in how many of each material go that day.
  - Each day can have a **date**, be ticked **Delivered**, and have a note
    (e.g. "Truck 1").
  - "Fill the rest" puts everything not yet scheduled on that day.
  - The totals show each day's pieces and weight (from the material list's
    unit weights) and, per item, what's **scheduled** and what's **left**
    (or how many over).
  - Removing a day moves the later days up (Day 3 becomes Day 2).
  - **Export CSV** saves the schedule in the project's Quotations folder
    and opens it.
  - It can be changed on issued quotations too. It's deleted with its
    quotation.
- It is **not connected to the stock list** (or to delivery notes) yet.
- Data: `quotation_deliveries.json`, one record per day, synced like every
  other store; `quotations:deliverySchedule`, `addDeliveryDay`,
  `updateDeliveryDay`, `deleteDeliveryDay`.
- `accounts.saveCSV` can now save into a project's subfolder or an
  Administration folder; the employee list goes to Administration ›
  Employees.

## Batch 68 — Letters

- **Letters** (new in the sidebar, ⌘6) lists every letter, newest first,
  with a search and a project filter. **+ New Letter** asks for a project
  and a client, both optional, and opens the editor. The address and
  "Attn." are filled in from the client, or from the project's client.
- **Letter numbers** come from Settings › Document Numbers › Letter, like
  the other documents. The default is `L{YY}{SEQ}` (L26001, L26002…);
  `{PROJECT}`, `{YYYY}` and "next number at least" work too. A letter
  without a project uses "GEN" for `{PROJECT}`.
- **The editor** shows the letter on a page with the company **letterhead
  and footer**, which are always printed.
  - Above the page are the letter's details: Our Ref. (the letter number),
    date, Your Ref., project, To, address, Attn. and Re: (subject). "Fill
    in from a client" copies a client's name, address and contact.
  - The app prints the **opening** from those details: the recipient on the
    left; Our Ref., Your Ref. and the date on the right; then the "Re:"
    line, bold and underlined.
  - The body is written below the opening. It starts as a letter ("Dear
    Sirs," … "Yours faithfully," "For and on behalf of" the company, and the
    signatory and title from Settings) and **saves itself** while typing.
- **Google Docs–style toolbar** (`js/rich-editor.js`):
  - Undo / redo, and text style (Normal text, Heading 1–3).
  - Font: EB Garamond (the letter font), Georgia, Times New Roman, Arial,
    Helvetica, Verdana, Courier New, PingFang (中文), Songti (中文).
  - Size in points, with − / +.
  - Bold, italic, underline, strikethrough, text colour and highlight.
  - Link.
  - **Insert table**: pick the size on an 8 × 8 grid. Inside a table you
    can add or delete rows and columns, or delete the table.
  - Alignment (left, centre, right, justify) and line spacing.
  - Numbered and bulleted lists, indent and outdent, and clear formatting.
- **Export PDF / Print** lay the letter out over as many pages as it needs,
  each page on the letterhead with the footer and page number
  (`PDFGenerator.generateRichText`).
  - The PDF is saved in the project's Letters folder, or in Administration
    › Letters for a general letter, and then opened.
  - Draft / Issued / Cancelled work as on other documents. An issued letter
    is locked until it's set back to Draft.
  - ⌘K search finds letters.
- Data: `letters.json` (synced like every other store). Actions:
  `letters:list`, `create`, `get`, `update`, `updateStatus`, `delete`,
  `exportPDF`, `print`, `letterhead`.

## Batch 69 — Letters follow their project; the letter PDF matches the editor; the installer picks a working SDK

- **Every letter belongs to a project**, and its number follows the
  project code: `L{PROJECT}-{SEQ}`, so project 26001's letters are
  L26001-001, L26001-002…
  - Each project has a **Letters** tab (with "+ New Letter"), next to its
    Delivery Notes. The Letters page still lists every project's letters.
  - The project is chosen when the letter is made, and shown in the
    editor with a link back.
  - Changing a project's code renumbers its draft letters, as it does its
    other draft documents.
- **The letter's opening is laid out like the quotations'.**
  - The recipient (bold name, address) is on the left, then **Attn:**,
    bold and underlined.
  - Our Ref. No., Your Ref. No. and Date are on the right: label, colon,
    and the value up to the right margin.
  - Then the **Re:** line, bold and underlined.
  - The PDF draws the opening itself, like the quotations do, and the
    editor's page shows it the same way.
- **Fonts and sizes in the PDF match the editor.** EB Garamond came out as
  Georgia or Times, because the HTML reader runs where the app's own fonts
  aren't installed. It is now given a stand-in that's swapped back for EB
  Garamond afterwards. The reader's size scale is also measured and
  corrected, so 11pt in the editor is 11pt on paper.
- **Installer:** `install.sh` now checks which macOS SDK the Swift compiler
  can actually build with. It tries SDKROOT, then the default SDK, then
  every installed SDK, and builds with the first that works. A Mac whose
  Command Line Tools have an SDK newer than their compiler no longer fails
  with "this SDK is not supported by the compiler", so there's no need to
  set SDKROOT by hand. If none works, it says to update the Command Line
  Tools. The in-app updater runs `install.sh`, so it gets this too.

## Batch 70 — Who made it, who last worked on it, and a personal Dashboard

- **Every project and document now records who made it and who last
  worked on it:** BOQs, quotations, invoices, delivery notes and letters.
  - The names are added as records are saved (`Authorship.stamp` in
    `JSONStore.writeAll`): the user's name (Settings › Sharing) and their
    Mac.
  - They're kept in the records themselves, so they travel with the shared
    data and every Mac sees the same names. Records saved before this take
    their names from the History.
- Each editor and project page shows it under the title, e.g. "Created by
  William · Last worked on by Harry, 2 hours ago"
  (`js/doc-authors.js`, `documents:authors`).
- History entries now always record who did it (and on which Mac), not
  only while sharing a folder. Your own entries now show your name too.
- **The Dashboard is personal:**
  - **My Active & Recent Projects** lists the projects you made, changed,
    or worked on documents in, most recent first.
  - **My Quotations Awaiting Reply**, **My Recently Changed Documents** and
    **My Recent Delivery Notes** list the ones you last worked on. If
    William last worked on DN26001, it isn't here; it's in his activity.
  - **My Recent Activity** shows your own History entries. The new
    **Recent Team Activity** shows everyone else's, with their names.
  - Unpaid invoices and the totals are still company-wide.

## Batch 71 — Linked BOQs and quotations, BOQ delivery schedules, name colours, a User tab, and the app's own dialogs

- **A BOQ and a quotation can be linked:** a change to either is made to the
  other, until the link is removed.
  - A quotation made from a BOQ is linked automatically. Importing a BOQ's
    items by replacing the quotation's also links them.
  - "Link" (under the import button) links an existing quotation. Its
    items become the BOQ's.
  - What's kept the same: items, names, units, quantities, prices, line
    discounts, Sale / Rental and the mark-up.
    - Each quotation line records the BOQ line it is (`boqLineId`).
    - With a BOQ mark-down, the quotation gets the marked-down rates.
  - Each quotation's delivery charges, extra sections and overall discount
    stay its own.
  - Only Drafts are changed. A document that goes back to Draft catches up.
  - While linked, a quotation's BOQ picker and "Import Items" are hidden, and
    importing from another BOQ is refused. "Remove Link" brings them back.
  - The BOQ editor lists its linked quotations (each with "Remove Link").
    The project's quotation list marks them "Linked".
  - `mirrorBOQ` / `pushQuotationToBOQ` / `linkQuotationToBOQ` in main.swift.
- **Import button:** when not linked, the BOQ import controls are folded
  into an import icon button next to "Reference BOQ".
- **Delivery schedules on BOQs:** Day 1, Day 2… as on quotations.
  - A quotation made from the BOQ starts with the BOQ's schedule.
  - Any quotation from the BOQ can copy it ("Copy from BOQ" in its
    Delivery Schedule).
- **Names in colour:** each person's name appears as a coloured tag in:
  - "Created by / Last worked on by" lines
  - Recent Team Activity and project History
  - Settings › Sharing, and the Dashboard.
  Colours are chosen on the User page, or worked out from the name
  otherwise. They're kept in the shared data (`user_profiles.json`), so
  every Mac shows the same colours.
- **User tab**, pinned at the bottom left of the sidebar (⌘0), shows:
  - your name (with initials in your colour)
  - your name and colour settings
  - your projects, the documents you last worked on, and your activity
  - the team.
- **Accounts is now "Accounting".**
- **Letters:** the recipient block now lines up with the "Re:" line and the
  body, in the editor and on the PDF.
- **The app's own dialogs** replace the Mac's alert / confirm / prompt boxes
  (`js/dialogs.js`: `appAlert`, `appConfirm`, `appChoose`, `appPrompt`).
  - Delete-type questions have a red button named after the action.
  - Two-way questions now have named buttons instead of "OK = … / Cancel
    = …": Rental / Sale, From BOQ / Start Blank, Replace & Link / Add Below.
  - The update check uses the same dialog.

## Batch 72 — Who made each project and document, in every list

- **A "Created By" column in every list**, showing the maker's name tag in
  their colour. When someone else was the last to work on it, "last:" and
  their name are shown under it. The lists are:
  - Projects
  - each project's BOQ, Quotations, Invoices, Delivery Notes and Letters tabs
  - the Letters page
  - the documents on client and site pages.
- **Dashboard:** every row in My Active & Recent Projects, My Quotations
  Awaiting Reply, Unpaid Invoices, My Recently Changed Documents and My
  Recent Delivery Notes says "Created by …". So does the User page's list of
  documents.
- The list data now carries `createdBy` / `lastEditedBy`
  (`authorsByRecord` in main.swift); `window.createdByCell` in sidebar.js
  draws the cell.

## Batch 73 — Combined counts apart, subtler name colours, drawings in brackets, Marketing

- **Combined counts are listed apart.** A BOQ made by combining others
  (`combinedFrom`, or "Combined from …" in the notes of an older one) is
  listed in its own bracket below the "Project total weight" row. It says
  which BOQs it was made from, and its weight isn't added to the total.
  Quotations made from a combined BOQ are listed the same way, below the
  "Project total" row, and aren't added to it either.
- **Subtler name colours:** a softer, muted palette. Name tags are now a
  faint, see-through tint, with the text mostly in the normal text colour.
- **Drawings and documents in brackets.** On a project's Drawings &
  Documents tab, both lists are grouped:
  - each BOQ with the quotations made from it (e.g. "BOQ BQ26212-001 ·
    Quotation Qt26212-001")
  - a quotation or a BOQ on its own
  - then "Not linked to a BOQ or quotation".
  Documents can now be filed with a BOQ or quotation too (a "For" column,
  like drawings: `documents:setLink`).
- **Marketing** (new sidebar tab) has four tabs:
  - **Overview:** quotations sent, the win rate and the average quotation
    over 12 months; a month-by-month chart of the value quoted and won; top
    clients by value invoiced; and where leads come from.
  - **Follow-ups:** quotations sent a week or more ago with no reply,
    clients with no new work for three months, and leads whose follow-up
    day has come. Each shows who's looking after it.
  - **Leads:** a board (New / Contacted / Quoted / Won / Lost) of companies
    being won over. Each lead has its contact, where it came from, an
    estimated value, a follow-up date and who's looking after it. "Convert
    to Client" adds it to Clients. Leads are kept in `leads.json` (shared
    like the rest of the data).
  - **Project References:** every project with its client, site,
    scaffolding and values, searchable. The ticked or shown projects can be
    exported as a spreadsheet for tenders and the company profile (saved in
    Administration › Marketing).

## Batch 74 — Scaffold inspections, Tasks and a Calendar

- **Scaffold Inspections** (a new tab on each project): the Form 5
  register.
  - Each scaffold is inspected by a competent person before first use and
    at least every 14 days.
  - Each record has the scaffold, location, date, competent person,
    result (Safe / Safe with remarks / Unsafe), remarks and action taken.
  - The next inspection is due 14 days on unless another date is given.
    "Dismantled" ends a scaffold's inspections.
  - Cards at the top show each scaffold's next inspection (amber when due
    within 3 days, red when overdue). "Record Inspection" on a card fills
    in the scaffold, location and competent person.
  - "Export Register" saves the register as a spreadsheet in the project's
    Documents folder.
  - Due and overdue inspections on active projects show on the Dashboard
    ("Scaffold Inspections Due") and the Calendar.
  - Stored in `scaffold_inspections.json`.
- **Tasks** (new page, plus a Tasks tab on each project): the team's
  to-dos.
  - Each task can be for a project and for a person (shown in their colour),
    with a due date and a High priority.
  - Tick a task to finish it (who finished it and when is recorded); click
    it to change it.
  - Views: My Tasks, Everyone's and Done, with search and person/project
    filters.
  - The Dashboard's new "My Tasks" panel lists your open tasks, and they
    can be ticked there too.
  - Stored in `tasks.json`.
- **Calendar** (new page): a month view of everything with a date:
  - delivery schedule days (quotations' and BOQs') and delivery notes
  - inspections done and due (overdue ones on today)
  - tasks
  - quotations' "valid until" dates
  - unpaid invoices' due dates
  - lead follow-ups
  - worker and company documents expiring
  - projects' start and finish dates.

  Each kind can be switched off (remembered on this Mac). Beside the month
  are the chosen day's items and the next 14 days. Every item opens what
  it's about.
- Calendar and Tasks are in the sidebar (under Dashboard) and the Go menu.

## Batch 75 — Quotation › Delivery Note › Invoice, line sorting, a weekly Calendar, Dashboard widgets, automatic updates

- **Quotation › Delivery Note › Invoice are linked.**
  - **New Delivery Note** is made from a quotation (chosen in a sheet). It
    starts with the quotation's materials.
  - **New Invoice** is made from delivery notes: what they delivered (added
    up), at the prices of the quotation they were made from (its markup and
    discounts). Items not quoted take their material-list price.
    - Notes are ticked in groups by quotation, with ones not yet invoiced
      ticked first; notes from different quotations can't be mixed.
    - A whole quotation can still be invoiced (e.g. a deposit).
    - `Invoice.sourceDeliveryNoteIds`; `createInvoice(deliveryNoteIds:)`.
  - Every BOQ, quotation, delivery note and invoice shows its chain under
    its title: BOQ › Quotation › Delivery Notes › Invoices
    (`documents:chain`).
  - Delivery notes say which quotation they're for and which invoices bill
    them; invoices say which notes they bill.
  - **New Invoice sheet fixed:** the radio buttons and tick boxes were
    stretched across the sheet, so their labels sat on the far right.
- **Sorting items (BOQs and quotations).**
  - The default is by item code; "By description" and "As arranged
    (drag)" are the other choices.
  - Dragging a line (quotations can now be dragged too) switches to "As
    arranged" and keeps that order.
  - A BOQ's sort and order are its linked quotations' too. Dragging a
    linked quotation's lines re-orders its BOQ the same way.
- **Calendar: week view** (the new default), with days across and hours
  down.
  - Things without a time are in the all-day row; a red line shows the
    time now.
  - Click an empty hour to add a task then.
  - Tasks and delivery-schedule days can now have a time.
  - "Month" switches to the month view; the choice is remembered.
- **Dashboard widgets.** "Customise" lets you drag the panels into your own
  order, make one full width or half, and hide or show them. "Reset
  Layout" goes back to the default. The layout is remembered for each
  person on each Mac.
- **Drawings and documents in folding brackets.** Each group (a BOQ with
  its quotations, one on its own, or not linked) is a card with its own
  table that folds open and shut. Folded ones are remembered.
- **Quotation signatures.**
  - The company's name is now directly under "For and on Behalf of", with
    the signatory and title under the signing line.
  - The client's side reads "Accepted By" with the client's name under it.
  - The PDF and Word copy both changed.
- **Automatic updates** (Settings › Updates, on by default).
  - ScaffoldPro checks for a new version when it opens and every 30 minutes
    while it's open.
  - When one is found it warns for 15 seconds ("Later" puts it off an
    hour), then:
    1. saves what's open: the field being typed in, unsaved settings, the
       letter being written;
    2. makes a backup ("Before Update");
    3. updates, and opens again by itself.
  - At launch it just updates.
  - Turned off, it asks first, as before.

## Batch 76 — Updates that work with a private repository, and ask first

- **Why the update at launch didn't happen:** ScaffoldPro checks GitHub with
  git, which can't sign in by itself. It then fell back to GitHub's public
  web API, which can't see a private repository. So it said "Up to date"
  when it couldn't actually tell.
- **GitHub access token** (Settings › Updates): a fine-grained token
  (Contents: Read-only, the Scaffold-Pro repository only) lets ScaffoldPro
  check for and download new versions itself.
  - git's fetch and pull send it as a header, and the web API check uses it
    too (`GitHubToken`, `UpdateChecker.authArgs`).
  - It's kept in `~/Library/Application Support/ScaffoldPro/github-token`,
    readable only by this Mac's user. The Keychain would ask for
    permission again after every update, because the app is rebuilt.
- **When GitHub can't be reached,** the launch screen now says "Couldn't
  check for updates" (not "Up to date"). "Check Now" says what to do.
- **Updates ask first.** At launch, and every 30 minutes while it's open, a
  new version brings up "Update Now / Later" (no countdown). Update Now:
  1. saves what's open;
  2. makes a backup;
  3. updates, and opens again by itself.

  Later asks again in an hour.


## Batch 77 — Tidier inputs, Quick Actions, resizable widgets, Excel lists, matching numbers

- **Calendar:** the week's day headings, all-day row and hours are now one
  scrolling grid, so the columns line up whether or not a scroll bar shows.
  The headings stay at the top while the hours scroll.
- **Dashboard Quick Actions** (¼ width): a tile with an icon for each New
  Project, Quotation, BOQ, Delivery Note, Invoice, Task, Inspection, Letter,
  Client, Site and Lead. Document kinds ask for the project, then start the
  new one straight away (`project-detail.html?…&new=1`).
- **Widgets resize by dragging:** in Customise, drag a panel's right edge.
  It snaps to ¼, ½, ¾ or full width, with the column guides shown. Panels
  pack upwards into the space beside a taller one, so there are no gaps.
- **Input boxes redesigned:** every text box, pop-up and date field is now
  the same height (30px) and the same quiet style, with its own pop-up
  arrow. Labels are one style.
  - The quotation's top is grouped into cards: Letter, Dates & Pricing,
    Key Terms.
  - Minimum hire is an option tile with "[2 | months]" in one box.
  - The invoice and delivery note editors' fields sit in a card.
- **New Invoice dialog:** a "From delivery notes / A whole quotation"
  switch replaces the link. Rent to charge is two option cards.
- **Material picker:** the bracket-by-bracket scrolling tried here was taken
  out again (it was unreliable); the list scrolls as before.
- **BOQ "Use Standard Terms"** was greyed out until terms were saved in
  Settings. It now always works, with built-in standard terms
  (`defaultBOQTerms`) until your own are set in Settings › BOQ Defaults.
- **Clients and Sites to and from Excel:** "Export to Excel" saves a real
  .xlsx file. "Import from Excel…" reads .xlsx or .csv and finds the column
  titles (Company Name / Site Name, Phone, Email…).
  - Each row is matched by reference, or else by name. You see how many
    will be added and updated before anything changes.
  - Blank cells leave what's already there.
- **Linked documents share a number:**
  - The delivery notes and invoices made from Qt26001-004 are DN26001-004
    and H26001-004; a second one is H26001-004-2.
  - The quotation made from BQ26001-004 is Qt26001-004.
  - This only applies when both number formats run per project, or both
    don't. Switch it off in Settings › Documents & Numbering.
- **Follow-ups:**
  - While customising, a panel's own buttons and rows don't respond; only
    its bar and its edge do.
  - Quick Actions is one column ("New Quotation" and so on).
  - A narrow panel (¼ width) stacks each row: the name across the top, then
    status and amount, then its buttons. The table columns no longer get
    squeezed (CSS container query).
  - Panels stretch down to meet the panel below them (or the bottom of the
    Dashboard), so no empty patch is left under a short panel beside a
    tall one.
  - Each Dashboard list shows its first 5. "and 7 more" under it shows the
    rest in place, and "Show fewer" folds it back. Quick Actions always
    shows all its tiles.
  - The Dashboard now receives up to 30 of each list, so the count is right.
  - "My Recently Changed Documents" groups its documents into a bracket per
    kind: Quotations, BOQs, Delivery Notes and Invoices. Only the kinds in
    the list are shown. It shows the 5 most recent; "and N more" brings in
    the rest, bracketed the same way.
  - "and N more" is a proper button (full width, with a chevron) rather than
    a blue link. An empty My Tasks panel has a "+ New Task" button.

## Batch 78 — Announcements, widget editor, Clients & Sites, calendar week

- **Announcements:**
  - "Announce" on the Dashboard posts a message to everyone, or to your
    team. Your team is set on the User page.
  - It shows in a bar at the top of the Dashboard of everyone it's for; the
    bar is hidden when there's none. Important ones are shown first,
    highlighted.
  - Each person can close one, and it stays closed on every Mac they use.
    Whoever posted it can take it down for everyone.
  - It can run until a date.
  - Stored in `announcements.json` and `user_teams.json`, shared like
    tasks.
- **Widget editor:** Customise opens a Widgets tray.
  - Drag a widget from the tray onto the Dashboard to add it. Drag a panel
    by its bar into the tray, or press its ×, to take it off.
  - A card follows the pointer, and the other panels make room.
- **No empty patches:** panels widen into empty columns beside them and
  grow up and down to meet their neighbours. They don't widen while you
  customise, so a panel shows the width you gave it.
- **Calendar:** today is the 2nd column of the week by default. "Week
  starts" can be Yesterday, Today, Monday or Sunday, and is remembered.
- **Letters** are only in each project's Letters tab; they're gone from the
  sidebar. ⌘ shortcuts are renumbered.
- **Clients & Sites** are one page:
  - Clients on the left, sites on the right, and a curved line from a
    client to each site it has had a project at (thicker for more
    projects).
  - Hover or click either side to light up its lines.
  - Click a line for its project(s).
  - Drag a client's dot onto a site to start a new project for the two;
    the project form opens with both already chosen.
  - ✎ or double-click opens the details.
  - `sites.html` links still work: they land on the site.
- **Marketing › Top Clients** is for reading only (not clickable).

## Batch 79 — Team tab, and directors signing and chopping quotations

- **Team** (sidebar) has People, Signatures and Announcements tabs.
- **People:** everyone using ScaffoldPro, with their team and title.
  - Their Admin › Employees details (position, number, phone), when the
    names match.
  - The devices they use it on: each Mac, when it was last seen, and
    whether it needs updating.
  - ✎ sets a person's team, title, and "Signs and chops quotations" (a
    director).
  - On your own card you add your signature and the company chop, as
    pictures. They're kept in the shared folder's `signatures/` folder.
- **Asking a director to sign:**
  - In a draft or issued quotation, the new bar under the toolbar has "Send
    to Sign…". Choose the director and add a note.
  - The director sees "… is waiting for you to sign and chop" at the top of
    their Dashboard, and in Team › Signatures. There they can Review it,
    Decline it with a reason, or Sign & Chop it.
- **Sign & Chop:**
  - The quotation's PDF is made with their signature over the company's
    "For and on Behalf of" line and the chop beside it.
  - It's saved as "… - Signed & Chopped.pdf" in the project's Quotations
    folder.
  - Whoever asked gets an announcement just for them: "… has been signed
    and chopped by …". A decline tells them the reason.
  - The quotation's bar then shows "Signed & chopped by … on …" with Open
    Signed PDF.
  - Only the person asked can sign, from their own Mac with their own
    signature.
- Announcements can now go to one person (used for these replies).

## Batch 80 — Chat

- **Chat** (sidebar, with an unread count) has three kinds of
  conversation:
  - Everyone;
  - your team (set on the User or Team page);
  - a direct message with each person. 💬 on a Team card opens one.
- **Messages:**
  - They travel through the shared folder like the rest of the data
    (`chat_messages.json`), checked every 1.5 seconds.
  - "… is typing" shows with bouncing dots. Each Mac writes a small
    `Typing/<device>.json` in the shared folder, not the log.
- **Emoji and reactions:**
  - The emoji picker has Recent, Smileys, Gestures, Site and Hearts tabs.
  - Hover a message to react (👍 ❤️ 😂 or any emoji), reply, edit or
    delete your own. ↑ edits your last message.
  - A message of 1–3 emoji only is shown large, with a pop.
- **GIFs and pictures:**
  - GIF search uses GIPHY: paste a free API key once (developers.giphy.com).
  - GIFs and pictures can also be sent from the Mac. They're kept in the
    shared folder's `Chat Files/`.
- **@Name** mentions are highlighted, yours in yellow.
- **Animations:**
  - messages slide in;
  - the send arrow whooshes;
  - reactions pop;
  - a "New messages ↓" pill appears when you've scrolled up.

## Batch 81 — ScaffoldPro Web (for the people who don't use a Mac)

- **How it works:** one Mac in the office keeps ScaffoldPro open with Web
  Access on, and serves the very same pages to web browsers on Windows
  PCs, iPads and phones.
  - The server is built in, on Apple's Network framework (`WebServer`).
  - A browser's request goes through the same handler as the Mac's own
    window (`NativeBridge.handle`), as the person who signed in
    (`TeamSync.actingAs`). So "Created by", tasks, chat and history show
    them, and everything lands in the shared iCloud folder like any Mac's
    work.
  - It's always the newest version: it's that Mac's own copy, so it
    updates when that Mac updates.
- **Setting it up** (Settings › Web Access, on the office Mac):
  1. Set an office password, then tick "Turn on Web Access".
  2. Allow incoming connections if macOS asks.
  3. On the PCs, open one of the addresses shown, e.g.
     `http://office-imac.local:8642`. Each person signs in with their name
     and the password.
  4. Keep ScaffoldPro open on that Mac. It won't let the Mac fall asleep
     while Web Access is on.
- **From outside the office:** install the free Tailscale app on the
  office Mac and on each PC or phone, all signed in to the same Tailscale
  account. Then use the Mac's Tailscale address with the same port.
- **What works in a browser:** everything you work on day to day.
  - PDFs, Word copies and drawings are made on the office Mac and open as
    downloads. "Print" makes the PDF for the browser to print.
  - Things that need the Mac's own windows still need a Mac: choosing
    files to upload, imports, backups, shared-folder setup and updates.
    The browser says so.
- **Sessions:** browser sign-ins last 30 days; they're listed in Settings,
  with Sign Out. A new password signs everyone out.
- **Team › People** shows the browsers people use, e.g. "Edge on Windows
  (web)".

## Batch 82 — Team as folders; New Task on My Tasks

- **Team › People is a folder tree:**
  - Each team is a folder (teams with a director come first); in it, each
    person as "name — title"; under them, their devices.
  - Folders open and close, and are remembered. Open All and Close All
    are on the bar.
  - Drag a person onto another team's folder to move them there.
  - "+ New Team" makes an empty folder to drag people into.
- **My Tasks** has a "+ New Task" button in its heading. Quick Actions
  leaves out its own New Task while My Tasks is on the Dashboard. Hide My
  Tasks and New Task comes back to Quick Actions.

## Batch 83 — Dragging widgets fixed

- **No more jump to the top.** Picking up a widget (from its bar or from the
  Widgets tray) used to scroll the Dashboard back to the top. The layout
  pass briefly collapsed the grid, and WebKit doesn't keep the scroll
  position. The grid now keeps its height while it's measured, and the
  scroll position is put back.
- **Easier to place:**
  - Panels no longer reshuffle under the pointer while you drag.
  - A blue bar marks where the widget will go: before or after the panel
    under the pointer (left or right half; top or bottom half for a
    full-width panel), or at the end below everything.
  - It moves there when you let go.
- **Scrolls while dragging:** the Dashboard scrolls when the pointer is
  near the top or bottom of the window, so a widget can go anywhere.
- A plain click on a widget's bar does nothing. A click on a tray card
  still adds that widget at the end.

## Batch 84 — Multiply quantities (sets)

- **"× Multiply…"** next to Line Items on a Draft BOQ, quotation, invoice or
  delivery note. It scales the quantities in one go:
  - ×2 when the client wants 2 sets of the same scaffold;
  - +10% for a spare allowance;
  - ½ for half;
  - or any number you type.
- **Which items:** all items, or "Choose items" to tick lines or whole
  sections. On quotations and invoices only the materials are scaled, not
  delivery or one-off charges.
- **Rounding:** quantities stay whole numbers. For a factor that isn't a
  whole number you choose Round up (the default, so you're never short),
  Nearest or Round down.
- **Preview:** shows each item's quantity now and after, before anything
  changes.
- **Undo:** "Undo" in the note at the bottom right puts the old quantities
  back.
- Linked documents follow as usual: a multiplied BOQ updates its linked
  quotations, and a linked quotation updates its BOQ.
- **For other uses:** behind it is one bridge call,
  `window.api.lines.setQuantities(kind, documentId, { lineId: qty })`
  (native `lines:setQuantities`). It sets many quantities on any of the
  four document types at once, Drafts only, and also works from ScaffoldPro
  Web. The sheet is `js/multiply.js`
  (`window.multiplyLines.attach({ button, kind, detail, include, reload })`),
  so another page with line items can add the same button in a few lines.

## Batch 85 — New Task as the first item in My Tasks

- The "+ New Task" button left the My Tasks heading. "New Task" is now the
  first item in the list, a tile that looks like those in Quick Actions
  (same icon, colour and hover). "All tasks" stays in the heading.
- It shows when there are no tasks too, above "Nothing to do."
- Quick Actions still leaves out its own New Task while My Tasks is on the
  Dashboard.

## Batch 86 — New Task lined up; no gap beside a long column

- **New Task lines up with the tasks.** It's now the first row of the My
  Tasks table, so its icon sits in the tick-box column and "New Task"
  starts where the task titles start. This holds at every width, including
  the stacked ¼-width layout. It keeps the Quick Actions look and hover,
  and works from the keyboard (Return or Space).
- **No empty patch beside a long panel** (e.g. a long "Quotations Awaiting
  Reply"):
  - The Dashboard now places each panel, in order, where it sits highest.
  - It skips a spot that would leave a hole under the panel that nothing
    can fill.
  - A panel left short above a hole is stretched down into it.
  - Panels with empty columns beside them widen into them, and the rest
    stretch to meet.
  - Example: Delivery Notes now widens beside a long Quotations column
    instead of leaving a blank square there.

## Batch 87 — Marketing Overview, rebuilt to explore

- **Filters across the top** change everything below them:
  - 3, 6 or 12 months;
  - Value or Count;
  - chips for the month and client you've picked (× clears each).
  - The period and measure are remembered.
- **The headline:**
  - A big number for what was quoted (it counts up).
  - Against the period before, with ▲/▼ (3 and 6 months).
  - A win-rate meter.
  - Beside it: average quotation, best month, and busy months.
- **The month chart:**
  - Each month's column shows Won (strong blue) under Not won yet (light
    blue), with a 2px gap between them.
  - The best month's figure sits on its column.
  - Hover, or Tab to a column, for a card with quoted, won, not won,
    count and win rate.
  - Click a month (or press Return) to look at it on its own; the others
    fade. Arrow keys move between months.
  - Columns grow in when the period or measure changes.
  - "Show as table" shows every figure without hovering.
  - The colours were checked for colour-blind readers and contrast in light
    and dark mode.
- **Top Clients:** a ranked leaderboard with won / not-won bars, the number
  of quotations and amount invoiced. Click a client to see only their
  quotations everywhere on the page. It's for looking only; client details
  are still changed on Clients & Sites.
- **Quotations:** the quotations behind whatever is picked, newest first,
  each marked ✓ Won or Waiting. Click one to open it.
- **Where Leads Come From:** each source with how many leads were won, the
  win %, and the open estimated value. When there are no leads it offers
  "+ New Lead".
- The month figures now come from the quotations themselves
  (`MarketingSummary.quotes`), so the won value is exact rather than an
  average.

## Batch 88 — Delivery charges by weight

- **New standard delivery charges** (per truck per trip, by the weight on
  the truck):

  | Weight | Charge |
  |---|---|
  | Under 500 kg | $1,200 |
  | 500 kg – 1 ton | $1,800 |
  | 1 – 2 tons | $2,200 |
  | 2 – 6 tons | $3,300 |
  | 6 – 8 tons | $3,800 |

- **Settings › Quotations › Delivery charges by weight** is a table you can
  change:
  - "Up to (kg)" and the charge for each band.
  - Bands are named for you (e.g. "2 – 6 tons").
  - There's a spare row for a heavier band.
  - "Use the standard rates" puts the bands above back.
  - The single "Standard delivery charge" field is gone.
- **"+ Delivery Charge" on a quotation** opens a sheet:
  - It shows the materials' weight. Each item's weight comes from the
    material list: by the item it was picked from, else the same code, else
    the same name. Items with no weight are counted.
  - It picks the matching band, marked Suggested. Any other band can be
    chosen.
  - Over 8 tons, it suggests a split: full trucks at 6 – 8 tons and the rest
    at its own band (e.g. 10,240 kg → 1 × 6 – 8 tons + 1 × 2 – 6 tons).
  - Trucks and trips per truck can be set (2 = delivery and collection). A
    preview shows each D-line and the total before anything is added.
  - Lines read "Delivery of materials (2 – 6 tons) (from yard to site and
    from site to yard)", in truck/trip.
  - If no material has a weight, you pick the band yourself.

## Batch 89 — BOQ terms match quotations; picker with no cut; New Task hover

- **Landscape BOQ terms:** the standard terms are now the same as
  quotations' standard key terms (Settings › Quotations, else the built-in
  "(i) Payment … (ii) Delivery … (iii) Modification …").
  - BOQs that still hold the old built-in four lines ("1. Quantities are
    estimated …") show and print the quotation terms instead.
  - "Use Standard Terms" puts these in.
  - Settings › BOQ Defaults can still hold different terms for BOQs; leave
    it blank to share the quotation terms.
- **"Add Materials" list, no hard cut:**
  - Each bracket's heading stays at the top of the list while its items
    scroll under it.
  - The bottom edge fades out softly while there are more items below, and
    is crisp again at the end of the list.
  - The list uses more of the window's height.
  - This applies in BOQs, quotations, invoices and delivery notes.
- **New Task hover:** New Task is now the same button as the Quick Actions
  ones, so it highlights as one rounded tile, not as separate boxes. Its
  icon still lines up with the tick boxes and its name with the task
  titles, at full and ¼ width.

## Batch 90 — Material list: clean top edge

- While a bracket's heading is held at the top of "Add Materials", the rows
  sliding up under it fade away just below the heading, so you never see a
  half-cut line of text or a sliver of an "+ Add" button. Only the heading
  that's actually held at the top gets the fade. A bracket that's fully in
  view shows its column headings as usual.

## Batch 91 — Landscape quotations; no signature block on BOQs

- **Quotation › Page:** "Portrait — letterhead" (as before) or "Landscape — BQ
  sheet". The landscape quotation looks like the landscape BOQ:
  - The orange "PROFICIENCY QUOTATION" banner, plus a row with the
    quotation number and date over Project Code / Client / Job Site /
    Structure.
  - Each material with its weight, quantity, unit rate (markup and any
    discount included) and total, then the Subtotal Amount and total weight.
  - What's added after it, each on its own line:
    - minimum monthly charge and minimum hire months (M);
    - delivery D1, D2… (with trucks × rate);
    - priced sections (A1…);
    - discount and tax.
    Then the Total Amount, the same as the portrait quotation's.
  - Rates sections after the total, then the notes.
  - Terms & Conditions: the same as the portrait quotation's (the web
    address sentence, the key terms, and the acceptance and validity
    paragraph).
  - The signature block: "For and On Behalf of" Proficiency (HK) Limited,
    with the signatory and title, and "Accepted By" the client with
    "Date :".
  - Export PDF, Print, Export Word, combining several quotations into one
    PDF, and a director's "Signed & Chopped" copy all follow the chosen
    page. On the landscape sheet, the signature sits on the company's
    signing line with the chop at its end.
- **BOQs:** the "Signature section" option is gone; BOQs no longer have a
  signature block. The Terms box stays.

## Batch 92 — Icons for Page and Items in; drawings after linking a BOQ; rounded picker top

- **Toolbar icons:** "Page" and "Items in" next to the document's selects
  are now icons (a portrait and landscape page; a 文A translate mark) in the
  quotation, BOQ and delivery note editors. Hovering shows what they are.
- **Drawings after linking a BOQ:** linking a quotation to a BOQ (or
  removing the link) now refreshes the quotation's Drawings box straight
  away. The BOQ and its drawings, marked "From BQ…", show without reopening
  the quotation. They were already in the exported PDF; only the box
  wasn't redrawn.
- **Material list, rounded top while scrolling:** when a bracket is
  scrolled part-way, it starts at the top of the list as a rounded box with
  a border all round its heading, never a square-cornered cut. The extra
  rounded box inside each bracket (around the column headings and rows) is
  gone, so each bracket is one clean box.

## Batch 93 — Quotation Page setting (and director signing) remembered

- **Fixed:** a quotation's Page setting snapped back to "Portrait —
  letterhead". Quotations are loaded by a hand-written reader that keeps
  older files loading, and it didn't know about the new Page field, so
  "Landscape" was saved and then forgotten on the next load. It reads it
  now.
- The same reader also dropped a director's "Signed & Chopped" record (the
  signed PDF, when and by whom). That's now kept too.
- No other record type uses a hand-written reader, so nothing else was
  affected.

## Batch 94 — Landscape quotation on one page; terms indented; picker border

- **Landscape quotation, one page:** like the BOQ sheet, it shrinks to fit
  when there are too many items for the terms and signatures, but it
  always fits everything on one page (the BOQ still stops shrinking at 70%
  and runs on instead).
- **No BOQ after it:** a landscape quotation is already the BQ sheet, so
  the BOQ it follows is no longer added after it when it's exported,
  combined or signed. A portrait quotation still has the BOQ after it.
  Drawings are still added.
- **Terms & Conditions indented** on the sheet as on the portrait
  quotation: "Payment", "Delivery", "(i) …" and "•" items with the label
  at the edge, a colon, and the text and every line under it in one
  column; a little space between the web-address sentence, the key terms
  and the acceptance paragraph. The BOQ's terms box does the same. The
  Word copy matches (hanging indents and tab stops).
- **Material picker:** the Pinned box's top border, drawn while its
  heading is stuck at the top of the list, was grey while its sides were
  gold. Both are now the same solid colour.
- `tools/pdf-preview`: `sheet.py quote` uses the new terms layout, and
  `sheet.py quote long` renders a long quotation shrunk onto one page. The
  terms-parsing rules moved to `terms.py`, which `docs.py` uses too.

## Batch 95 — Editor header, icon pickers, Make Quotation, Start from Others, linked numbers

- **Page / Items-in pickers** (BOQ, quotation, delivery note): only the
  icon shows. Resting the pointer on it opens a list drawn by the app
  (`js/hover-menu.js`), with a tick by the current choice, in place of
  the system's pop-up menu. Click, Return, Space or ↓ open it too; ↑ ↓
  move, Return picks and Escape closes it.
- **Who made it:** "Created by … · Last worked on by …" now sits at the
  right of the document number's row in every document editor. The
  linked documents (BOQ › Quotation › …) stay under the title.
- **Make Quotation** on the BOQ's status row makes a quotation from the
  BOQ, linked to it. If the BOQ already has a linked quotation, you can
  open it or make another.
- **Drawings** in the BOQ and quotation editors now sit under Add
  Materials (the left column).
- **New Quotation → Start from Others:** when the project has more than
  one BOQ, this button lists the others, each with its structure, number
  of items and status, on hover or click. The quotation is made from the
  one picked and linked to it. Dialogs show these lists with
  `{ label, menu: [...] }` buttons.
- **Fixed:** linking a draft quotation to a BOQ (Link, or Replace & Link
  when importing) now renumbers it to match, e.g. BQ26212-007 →
  Qt26212-007, as a quotation made from the BOQ already was. If another
  quotation already has that number, it gets "-2" and so on. Issued
  quotations keep their number. The project history records the old
  number.

## Batch 96 — Linked BOQ / quotation: View and Remove Link; toolbar fix

- **Linked row → buttons.** On a quotation linked to a BOQ, the row "Linked
  to BQ… — a change to either is made to the other" is now just a link
  mark, **View BQ…** (opens the BOQ) and **Remove Link**. The BOQ shows
  the same for each quotation linked to it: **View Qt…** and **Remove
  Link**. What the link does is in the link mark's tooltip.
- **Fixed (from Batch 95):** in the BOQ and quotation editors, the
  Items-in icon's wrapper ran on past its own list. That hid the BOQ's
  **Pricing** list and the quotation's **From BOQ** list, and pulled the
  toolbar buttons into the wrapper. Each icon now holds only its own
  list.

## Batch 97 — Undo and Redo

- **⌘Z or Ctrl+Z undoes the last action; ⇧⌘Z, ⌘Y or Ctrl+Y redoes it.**
  So do Edit › Undo and Redo. Examples of actions: adding or removing a
  line, changing a quantity or price, Multiply, linking a quotation,
  changing a status, deleting a BOQ, saving a client. The page reloads
  where it was, with "Undone: Add line item (BOQ) [Redo]" at the bottom
  right. Each further ⌘Z goes one step further back, up to 60 steps. The
  steps last while the app is open.
- **Typing first:** text typed in a field and not yet saved is undone in
  the field, as usual. Once it's saved (you leave the field, or press
  Return), ⌘Z undoes the change as an action.
- **How it works (`UndoJournal` in main.swift):** while an action runs,
  every record it changes is noted as it was before and after (every
  save goes through `StoreFile.write`). Undo puts just those records back,
  re-adding any it deleted and taking off any it added. A teammate's work
  on other records isn't touched. The project history records
  "Undone: …" / "Redone: …".
- **Not undone:** reading, exporting and printing, backups, chat,
  announcements, signing requests, team settings, the history log, and
  files on disk (an uploaded drawing's copy stays in the folder). Changes
  made from a browser through ScaffoldPro Web aren't recorded, and Undo
  isn't offered there.

## Batch 98 — Build fix; sidebar group headings

- **Build fix:** `takeLinkedNumber` (from Batch 95) named the BOQ type
  `BOQ`, but it's `BillOfQuantities`, so the app didn't compile
  ("cannot find type 'BOQ' in scope").
- **Sidebar headings:** the sidebar's tabs are now grouped under small
  capital headings: **Overview** (Dashboard, Calendar, Tasks), **Team**
  (Chat, Team), **Operations** (Material List, Clients & Sites, Projects,
  Stock) and **Company** (Accounting, Marketing, Admin, Settings). The
  order and the ⌘ shortcuts are unchanged.

## Batch 99 — Quotation editor layout; lists fit their text; delivery wording

- **Quotation editor, top section:** **Letter** is on the left. On the
  right are **Dates & Pricing**, then the BOQ link row, then the signing
  rows ("Not signed by a director yet", the client's signed copy). The
  Letter box is as tall as those three together. Below 1000px wide they
  stack.
- **Key Terms** now sits under the line items, after Notes.
- **Drop-down lists** (Page, Items in, Start from Others) are as wide as
  their longest choice, so nothing scrolls sideways.
- **Delivery on the landscape quotation** reads "Delivery of materials",
  with "@$3,300.00 / Truck / Trip" on the line below. The weight band
  ("2 – 6 tons") is no longer printed. Sheet cells can now hold two
  lines, in the PDF and the Word copy.

## Batch 100 — Asked to save when leaving Settings

- **Leaving Settings with unsaved changes** asks "Save your changes to
  Settings?". **Save** saves and goes on, **Don't Save** goes on without
  saving, and **Cancel** stays. This covers every way out: sidebar links,
  ⌘K search, the Back button, ⌘[ / ⌘], and the Go menu.
- If a number format is missing {SEQ}, Save stops there and the changes
  stay unsaved, instead of being reported as saved.
- Any page can use this: set `window.leaveNeedsAsk()` and
  `window.askBeforeLeave()`; leaving goes through `window.appNavigate()`
  (js/sidebar.js).

## Batch 101 — The app's own controls (lists, numbers, dates, tick boxes)

Every form control is now drawn by the app instead of macOS, on every page
(`js/controls.js`, `js/hover-menu.js`, css/styles.css):

- **Lists:** every drop-down opens the app's list instead of the system's
  pop-up menu: a tick by the current choice, group headings, and it opens
  scrolled to the current choice. Click, Space, Return, ↑ or ↓ open it;
  ↑ ↓ move, typing jumps to a choice, Return picks, Escape closes, and a
  click outside closes it.
- **Numbers:** the system's ▲▼ arrows are gone. Resting the pointer on a
  number field (or clicking into it) shows a small − / + stepper; hold it
  to keep going. Typing and the arrow keys work as before.
- **Dates and months:** the app's calendar (Monday first, as the Calendar
  page) with Today and Clear. Click the field, or press Space or ⌥↓; the
  arrow keys move around it and the arrows at the top change month. You
  can still type the date.
- **Tick boxes and round choices:** drawn by the app, with a small
  animation when ticked.
- **Colour wells:** rounded swatches. The colour panel itself is still
  the Mac's.
- **Nothing changes underneath:** the real field stays in the page and
  keeps its value. Picking sets it and fires `input` and `change`, as the
  system's controls do, so every page saves as before. Fields added later
  (tables, dialogs) get the same treatment as they appear.
- **Opting out:** add `data-native` to a field (or a box around it) to
  keep the system's control there.

## Batch 102 — A livelier Dashboard

- **Greeting:** "Good morning / afternoon / evening, William" over the date.
  Under it, a **Today** line of chips: open tasks, quotations awaiting
  reply, overdue invoices, inspections due. Clicking one scrolls to its
  panel, which glows for a moment.
- **Number tiles:** each has an icon, and its figure counts up when the
  page opens. Each tile goes where its figure comes from: Active
  projects → Projects, Unpaid → the Unpaid Invoices panel, Overdue →
  Accounting, Quotations → their panel. Tiles lift on hover, with an
  arrow. When something is overdue, Unpaid shows a meter of how much of
  it is overdue. "Nothing overdue" shows in green.
- **Counts** beside the panel titles (My Tasks, Quotations Awaiting Reply,
  Unpaid Invoices, Inspections).
- **Small animations:** the tiles and panels rise in one after another as
  the page opens; a row under the pointer gets an accent edge; Quick
  Action icons lift on hover. Nothing moves when the Mac is set to
  Reduce Motion.
- Still information first: no decorative charts.

## Batch 103 — Tidier editor toolbar and Add Materials header

- **Export:** Export PDF and Export Word are one **Export** button in the
  BOQ, quotation, delivery note and invoice editors (and letters). A
  click saves the PDF; resting the pointer on it lists **PDF** and
  **Word** to choose from (js/hover-menu.js, `button.export-menu`; the
  old buttons stay on the page, hidden, with their own code).
- **No "← Back to project":** the Back button at the top of the page
  does that. In the BOQ editor **Make Quotation** sits at the right end
  of the toolbar.
- **Icon buttons without a box:** Print, Locate File, Delete, Duplicate
  and the other icon buttons are drawn like the Page / Items-in icons —
  just the icon, with a soft tint on hover.
- **Add Materials:** the price list and category are in one ☰ list at the
  right of the "Add Materials" heading, under the headings *Price list*
  and *Category* (`button.group-menu`, `data-selects`). The search box
  sits just left of it. A dot on ☰ shows a category is picked.
- **Dashboard rows:** in a narrow panel (rows stacked) the accent edge
  runs down the whole row instead of only beside its first line, and the
  row's words step aside from it.
- **"Show 3 more":** under a Dashboard list (e.g. My Recently Changed
  Documents) each press shows the next 3, with how many are left; "Show
  fewer" folds it back to 5. The new rows slide in.

## Batch 104 — Excel instead of CSV

- **Every export is an Excel workbook (.xlsx):** the Material List,
  Stock (stock list, by site, movements), Accounting, Employees, a BOQ's
  or quotation's delivery schedule, the inspection register and the
  project reference list. The buttons read **Export to Excel**.
- In those workbooks the column titles are bold and stay at the top;
  amounts, quantities and weights are real numbers (Excel can add them
  up, with their 1 or 2 decimals). Codes and numbers that are names stay
  as typed: item codes (3.10), project and employee numbers (00001),
  phones, bank accounts and references.
- **Imports take Excel workbooks:** the Material List's **Import from
  Excel…** and Clients & Sites' import open .xlsx files. (A .csv or old
  .xls file: open it in Excel or Numbers and save it as .xlsx first.)
- Under the hood the pages still hand the table over as CSV text
  (`accounts:saveCSV`); main.swift reads it (`SpreadsheetReader.parseCSV`,
  which now also ends rows at Windows line breaks) and writes the .xlsx
  (`SpreadsheetWriter.writeXLSX(…, numbers: true)`).

## Batch 105 — A long landscape quotation on a portrait page

- A landscape quotation always fits on one page. When a long one would
  have to shrink below **60%** on a landscape page, it now goes on a
  **portrait** page instead. It keeps the same landscape design (orange
  banner, the item table with prices, the totals, terms and signatures),
  and it is shrunk much less: about 78% instead of 40–60%. The PDF,
  printing and the Word copy all use the same page.
- Shorter quotations stay on a landscape page as before. Portrait
  quotations (the letterhead design) are unchanged.
- `BQSheet.fitToPage(…, portraitBelow:)` and `BQSheet.scaled`; the
  preview (`tools/pdf-preview/sheet.py quote long`) does the same.

## Batch 106 — Projects and the project page, redesigned

**Projects**
- **A card per project:** its number and status, its name, the client
  and site, how many BOQs, quotations, delivery notes and invoices it
  has, who made it and when it was last worked on. Each card is in its
  status colour: Planning violet, Quotation amber, Active green (its dot
  pulses gently), On Hold orange, Completed blue. On hover a line grows
  along the card's top, a soft light follows the pointer and an arrow
  shows. Clicking a document count opens the project on that tab.
- **Status filters** with counts (All 6 · Planning 2 · Active 2 …).
  **Order:** newest number, recently worked on, name or client.
  **Cards or List** (the list is the table, with the same counts).
  The page remembers these choices.
- **Search** matches the number, name, client or site. Press **/** to
  jump to it, and Escape clears it. Cards rise in one after another.
- The app now sends each project's document counts and when one last
  changed (`ProjectListEntry.boqCount` …, `lastActivityAt`).

**A project's page**
- **The header** is one panel, tinted in the status colour over a faint
  scaffold grid, with a light that follows the pointer. It shows:
  - the project number (click it to copy) and its status;
  - the name, then the client and site (links), and who made it and who
    last worked on it;
  - its **stage**: Planning › Quotation › Active › Completed. Stages
    already done are ticked, and clicking a stage moves the project
    there. On Hold and Archived show beside the stages; the status list
    is still at the right;
  - **tiles** for BOQs, Quotations, Delivery Notes, Invoices, Drawings &
    Docs and Open Tasks. Each opens its tab.
- **Overview:**
  - Project Details as labelled fields with icons, in two columns.
  - **Quick Actions** look like the Dashboard's panel: coloured icons for
    New BOQ, Quotation, Delivery Note, Invoice and Letter, Record
    Inspection, New Task, Upload Drawing and Upload Document.
  - Recent Activity is a timeline, with "All history" next to its title.
  - Description and Internal Notes sit beside the timeline.
- **Drawings & Documents:**
  - The two are side by side, and each file shows as a small card.
  - The "Drop … here" boxes are gone until files are dragged from
    Finder over the window. Each column then shows where to drop.

## Batch 107 — Arrange a project's Overview like the Dashboard

- **Customise** above a project's Overview arranges its panels the way
  the Dashboard's are arranged:
  - drag a panel by its bar to move it;
  - drag its right edge to make it ¼, ½, ¾ or full width;
  - drag it into the **Widgets** tray (or press ×) to take it off, and
    drag it back to put it on again.
  The panels are Project Details, Quick Actions, Recent Activity, and
  Description & Notes.
- While you're arranging, nothing is kept until you choose:
  - **Cancel** (or Escape) puts every panel back as it was before.
  - **Change**: rest the pointer on it, or click it, to choose:
    - **For this project:** only this project looks like this.
    - **For all projects:** every project looks like this, including
      ones arranged on their own.
- The arrangement is kept on this Mac (`project.layout` for all projects,
  `project.layout:<number>` for one). The Dashboard's Customise works as
  before.
- js/widgets.js: `setupWidgets(grid, button, null, { place, about, load,
  choices, store })` turns on Cancel / Change ▾ for a page.

## Batch 108 — Customise under the Overview

- A project Overview's **Customise** button now sits under its panels, at
  the right. While you arrange them, **Cancel** and **Change** take its
  place there. Change's list opens above it when there's no room below.

## Batch 109 — Pinned items in your own order

- In Add Materials (BOQ, quotation, delivery note and invoice editors), the
  **★ Pinned** box's items each have a ⋮⋮ handle. Drag one up or down to
  put the pinned items in the order you want. With the handle focused, ↑ / ↓
  move it one place.
- The order is kept with the material list, so it's the same in every
  editor and on every Mac. A newly pinned item goes at the end; unpinning
  forgets its place.
- When a search shows only some pinned items, dragging them reorders just
  those; the others keep their places.
- main.swift: `PriceListItem.pinOrder`, `reorderPinnedItems(ids:)`, action
  `priceListItems:reorderPinned`.

## Batch 110 — Sums in quantity and price boxes

- A line item's **quantity** (BOQ, quotation, delivery note, invoice) and
  **unit price** (quotation, invoice) box works out a sum: type `14+28`,
  `2 x 7`, `(3+2)*4` or `120/4`.
  - The answer is saved and shown. The sum is kept with the line.
  - A small accent corner marks a box that holds a sum.
  - Click into the box to see or change the sum. A plain number clears it.
  - While you type a sum, **= 42** shows above the box.
  - Escape puts back what was there. Something that isn't a number or a
    sum isn't saved: the box flashes red and goes back.
  - + − × ÷ and x, *, / all work, and 1,250 is read as 1250.
  - Quantities are still whole numbers, so 10/4 saves as 3.
  - (Batch 113: ↑ / ↓ now move to the box above / below instead.)
- A BOQ and its linked quotations share the sum. Multiply… changes the
  quantities, so it clears their sums.
- js/calc-input.js (`calcRead`, `calcChange`, `calcAttr`); main.swift:
  `quantityFormula` on every kind of line, `priceFormula` on quotation and
  invoice lines, and `lineFormula()`.

## Batch 111 — Linked BOQs and quotations share their drawings

- A drawing uploaded (or dropped) on a **quotation that's linked to a
  BOQ** now shows in the BOQ's Drawings panel too, marked "From Qt…". It
  also shows in the BOQ's other linked quotations, and is added after the
  BOQ's pages when the BOQ is exported or printed.
- As before, a quotation shows its BOQ's drawings, marked "From BQ…".
  A quotation that was only made from a BOQ (not linked) still has just
  the BOQ's drawings and its own.
- `documentDrawings(kind:id:)` in main.swift.

## Batch 112 — Dates typed as dd/mm/yyyy, shown as 24 Sep 2026

- Every date box is now **typed day first, dd/mm/yyyy**, whatever the
  Mac's region is set to (the system's date box followed it, so a US
  region gave 09/24/2026). Away from the box, the date is **shown as
  24 Sep 2026**; clicking it switches back to 24/09/2026, all selected,
  ready to type over, with the calendar open as before.
- Typing also takes 24/9/26, 24-9-2026, 24.09.2026, 24092026, 24 Sep
  2026, 24sep, 2026-09-24 or "today"; with no year it's this year. The
  calendar turns to the date as it's typed. Return or leaving the box
  takes it; a date that doesn't exist (31/02) flashes red and the box
  goes back. Escape puts back what was there; ↓ opens the calendar.
- Month boxes (Payroll) work the same: typed 09/2026, shown Sep 2026.
- Dates in lists and tables that showed as 2026-09-24 (payments,
  liabilities, document expiry, employees, marketing, a project's
  invoices / delivery notes / files, stock movements) are now
  24 Sep 2026. September is "Sep" everywhere (British English
  formatting wrote "Sept").
- The pages still read and save dates as 2026-09-24, so nothing saved
  changes. `upgradeDate` / `parseDate` and `window.appDay(iso)` in
  js/controls.js.

## Batch 113 — Arrow keys move from box to box

- In a table (line items, rates, the delivery schedule…), **↑ / ↓ go to
  the box above / below** in the same column, carrying on into the next
  section's table, and **← / → go to the box beside it** once the cursor
  is at that end of the text (or the whole number is selected, as when
  you arrive in a box). It works like a spreadsheet; the box you leave is
  saved, as with Tab.
- **The arrows no longer change a quantity or price.** Before, ↑ / ↓
  added or took one, which was easy to do by accident. The − / + stepper
  that shows on resting over a number box is still there for that.
- In a number box outside a table (e.g. Mark up %), ↑ / ↓ go to the box
  before / after it in the same form or dialog.
- Dates keep ↓ for the calendar; time boxes and lists are as before.
- In js/controls.js (`boxBelow`, `boxBeside`); js/calc-input.js no
  longer steps.

## Batch 114 — The delivery schedule is printed with its quotation and BOQ

- Once any day of a delivery schedule has items on it, the schedule is
  **added automatically after the document's own pages** whenever a
  quotation or BOQ is exported to PDF, printed or combined with others,
  and in a quotation's director-signed copy. It goes before the BOQ that a quotation follows and
  before the drawings.
- It's a **landscape sheet in the BQ sheet's style**:
  - an orange "DELIVERY SCHEDULE" banner;
  - the project code, client, job site and document;
  - a blue heading row: No. | Item Name | Unit | Qty | Day 1 (with its
    date under it) | Day 2 … | Left;
  - a row for each item with how many go to site each day;
  - Total Pieces and Total Weight for each day;
  - the days' notes in a box under the table.
- Seven days fit on a sheet. With more days, the schedule carries on onto
  the next sheet, headed "(DAY 8 – 14)", and "Left" is on the last sheet.
  A long item list runs on over pages, with the heading repeated on each.
  Item names and headings are in Chinese when the document is.
- A quotation with no schedule of its own prints its BOQ's schedule.
  Days with nothing on them are left out.
- **No time for delivery days:** the time box is gone from the schedule,
  and the Calendar shows each delivery day as a whole day.
- `BQSheet.deliverySchedule` and `deliveryScheduleFile(kind:id:)` in
  main.swift; previewed with `tools/pdf-preview/sheet.py schedule [many]`.

## Batch 115 — Newest bracket first; each kind of document has its colour

- In the Dashboard's **My Recently Changed Documents**, the bracket with
  the most recently changed document is at the top, so the brackets swap
  places as you work. For example, a BOQ changed 5 minutes ago puts
  BOQs above Quotations changed hours ago.
- **Each kind of document has a muted colour**, so it can be found at a
  glance. The colour shows only as a thin stripe or a small dot, never
  as a fill, and is slightly lighter in dark mode. The colours:
  - BOQs: sage teal;
  - quotations: dusty blue;
  - delivery notes: ochre;
  - invoices: sage green;
  - letters: lavender;
  - drawings and documents: grey.
- **Where the colours show:**
  - Dashboard: the recent-documents brackets, and the rows of Unpaid
    Invoices, Quotations Awaiting Reply and Delivery Notes;
  - the Projects page: the BQ / Qt / DN / Inv chips;
  - a project's page: the count tiles and the tabs.
- `--doc-*` tokens and `.dk-*` classes in css/styles.css.

## Batch 116 — Material-list order by default; a third click undoes a column sort

- **Clicking a column title** in a list table now cycles: 1st click
  ascending, 2nd descending, **3rd back to the table's original order**
  (the arrow goes away).
- **Line items are listed as in the material list by default** (BOQs,
  quotations, invoices and delivery notes; the new "As in the material
  list" in the Sort menu). The item code was only a rough way of
  ordering the old Excel BQ sheet.
  - **Types follow the material list's order:** Base Items, Standards,
    Ledgers, Face Braces, Steel Decks, Toe Boards, Staircases, Guard
    Rails… (the group number at the front of the item codes, which is
    the same in both lists).
  - **Items of a type from one list** stay in that list's order,
    including any order dragged in the Material List.
  - **Items of one type from both lists** (SP and SCAFOM) are put in
    order by length, shortest first. For example, a 0.73m ledger (SP),
    a 1.4m ledger (SCAFOM) and a 2.57m ledger (SP) go 0.73m, 1.4m,
    2.57m. Each list's names for the same type are matched: SP's "Toe
    Boards" and SCAFOM's "Steel Toe Boards", and "Lattice Girders" and
    "Lattice Gridders & …".
  - **Items not on a material list** (delivery, custom items) come last,
    in the order they were added.
  - "By item code", "By description" and "As arranged (drag)" are still
    in the Sort menu.
  - The delivery schedule lists items in the document's order too.
- `byMaterialList`, `materialLengths`, `materialCategory` in main.swift;
  the column cycle in js/sidebar.js.

## Batch 117 — Material List ☰ menu; a new delivery day is dated the day after

- **Material List:** Unit Rates…, Import from Excel…, Export to Excel
  and the category list are now in one ☰ list, with **+ Add Item** to
  its right. Resting on ☰ shows:
  - **Rates:**
    - **Import rates…**: update prices from an Excel workbook;
    - **Export rates**: resting on it opens a list to its left with:
      - **PDF**: the Unit Rates sheet on the letterhead (tick the items,
        from either list, then Make Unit Rates PDF);
      - **Excel**: this material list as a .xlsx.
  - **Category:** All Categories and each category.
  - A dot on ☰ shows when a category is chosen.
- js/hover-menu.js can now show submenus: an item with its own `items`
  opens them beside the menu, to the left (or the right where there's no
  room). It opens when the pointer rests on the item, on a click, or with
  ← / →; Escape goes back.
- **Delivery schedule:** **+ Add Day** dates the new day the day after
  the latest date already put in. Only Day 1 (or a schedule with no
  dates yet) starts without one.

## Batch 118 — Undo without the flash; schedule Export menu and pinned items; Line Items ☰

- **⌘Z / ⌘Y no longer reload the page.** The page is redrawn in place
  (no white flash, same scroll position). What the undo or redo changed
  is softly lit for about two seconds, and scrolled into view if it was
  out of sight: a row that's new or now says something else, or a box
  or total whose value changed. A redraw that changes too much (a new
  order) lights nothing. The "Undone: … [Redo]" note shows as before.
  Each page redraws with its own `window.appRefresh()`: the editors, a
  project's page, Projects, Material List, Clients / Sites, Stock,
  Accounts, Tasks, Letters, Calendar, Marketing, Team and your page. A
  page without one (the Dashboard) still reloads.
- **Delivery schedule:**
  - **Export** is a hover menu like the documents' Export: **PDF** (the
    default on a click) saves the landscape schedule sheet on its own
    (e.g. `26212_Delivery Schedule_Qt26212-007.pdf` in the document's
    folder); **Excel** saves the .xlsx as before. The Export helper in
    js/hover-menu.js can offer Excel in place of Word (`data-excel`).
  - **The item column stays pinned at the left** while the days are
    scrolled across, with a soft edge over the days. The table also keeps
    its sideways scroll when it's redrawn after typing a quantity.
- **Line Items:** **Multiply** and **Sort** are now in one ☰ list at the
  right of the heading (BOQ, quotation, invoice, delivery note):
  - **Multiply quantities…**, greyed out on an issued document or one
    with no items;
  - then the Sort choices, with the current one ticked (BOQ and
    quotation only).

## Batch 119 — Delivery schedule internal notes; Export › Internal / External › PDF / Excel

- Each delivery day has **Internal notes** (a row under Notes, its boxes
  dashed) for the team only, e.g. the driver, the gate or loading order.
  The **Notes** row above is for the client. A quotation copying its BOQ's
  schedule copies the internal notes too.
- **Export** in the delivery schedule:
  - resting the pointer on it lists **Internal** (with the internal
    notes, for the team) and **External** (the notes only, for the
    client);
  - resting on either opens **PDF** or **Excel** to its left;
  - an Internal PDF says "DELIVERY SCHEDULE (INTERNAL)" on its banner and
    lists "Internal notes:" after the notes. It's saved as
    `…_Delivery Schedule (Internal)_Qt26212-007.pdf`, and the Excel copy
    as `… Delivery Schedule (Internal).xlsx` with an Internal notes row.
  - A click on Export itself saves the External PDF.
- The schedule printed with the quotation or BOQ never shows the
  internal notes.
- `QuotationDeliveryDay.internalNote`; `BQSheet.deliverySchedule(…,
  internal:)` in main.swift (and its copy in tools/pdf-preview/sheet.py).

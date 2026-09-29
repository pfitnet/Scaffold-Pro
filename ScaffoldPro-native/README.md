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

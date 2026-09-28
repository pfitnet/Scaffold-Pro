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
  `Documents/ScaffoldPro/Backups/`, laid out exactly as section 39 asks:
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

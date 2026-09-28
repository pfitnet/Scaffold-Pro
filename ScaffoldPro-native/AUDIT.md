# ScaffoldPro — audit against the master prompt

Date: 28 Sep 2026. Scope: every file in `ScaffoldPro-native/` (main.swift,
13 JS files, 12 pages, CSS, install script, seed price lists), read in full
and compared with the 67 sections of the master development prompt.

## How this was checked, and its limits

- **Nothing has been compiled or run on a Mac.** This environment has no
  macOS SDK (no AppKit/WebKit/PDFKit), so `swiftc` can't be used. What was
  checked instead:
  - `main.swift` parsed with a Swift grammar (tree-sitter): no syntax errors
  - every JS file passes `node --check`
  - all 135 `window.api` actions in `bridge.js` have exactly one matching
    `case` in the Swift dispatcher, and vice versa
  - every `getElementById(...)` in the edited pages resolves to a real element
  - the logic of every handler was read line by line
- "Works" below means **the code does what the prompt asks, as far as
  reading it can tell**. Type errors, AppKit API mistakes and layout issues
  can only be found by running `./install.sh` on a Mac.
- **The attached sample documents and the Excel workbook were not in the
  zip.** Only the already-converted price lists
  (`resources/*.json`: 105 SP items, 112 SCAFOM items) were there. So the
  PDF templates couldn't be compared with the samples (section 26), and the
  Excel import couldn't be re-run against the real workbook.

## Bugs found and fixed in this pass

| # | Problem | Fix |
|---|---------|-----|
| 1 | New clients and sites saved empty form fields as `""`, so PDFs printed a blank **"Attn:"** line, empty address lines, and "Contact: , " for sites | Blank fields are stored as empty; PDF address blocks also skip blanks in records saved by earlier versions |
| 2 | Project-number override accepted `27001` in 2026 and `26000` (section 12: first two digits = the year, last three = the sequence) | A future year and sequence `000` are rejected; past years are still allowed for older projects. The proposed number also skips numbers already taken by an override |
| 3 | An **issued invoice could be put back to Draft** and edited, and any cancelled document could be reopened (section 25) | Issued invoices can't return to Draft (cancel it and issue a new one instead). Cancelled is final for quotations, invoices and delivery notes. Returning an issued quotation, delivery note or BOQ to Draft now asks first. Invalid options are greyed out in the status menu |
| 4 | Empty documents could be issued; invoices could be issued with no due date (section 62) | Quotations, invoices, delivery notes and BOQs need at least one line to be issued; invoices also need a due date |
| 5 | A payment larger than the balance due was accepted | Rejected, with the balance shown. The amount paid is added up with exact decimal maths |
| 6 | After a line was removed, the next line added could get the same position as an existing one, so line order became unpredictable (all four document types, and "Import Items" from a BOQ) | New lines always go after the current last line |
| 7 | Dashboard and ⌘K search re-read every line-item file once per document, on every keystroke. This gets slow as documents build up (section 55) | Each file is read once per search and grouped |
| 8 | Overdue invoices showed as "Overdue" on the Dashboard but "Issued" on the project's Invoices tab | Overdue is worked out the same way everywhere |
| 9 | **Rename** turned `Plan.pdf` into `Plan.pdf.pdf`, and the list kept showing the old name, so it looked like nothing happened. A `/` in the new name could move the file into another folder | The extension is added once. `/` and `:` are replaced. An existing file is never overwritten. The list shows the file's actual Finder name, with "Uploaded as …" underneath |
| 10 | Opening a worker from ⌘K search (`admin.html?worker=…`) opened Admin without selecting that worker | The worker is selected, even if archived |
| 11 | Quotation editor always showed **"HK$"**, whatever currency was set in Settings (section 50) | Uses the Settings currency. The invoice totals now show it too |
| 12 | Quotation, invoice and delivery dates couldn't be changed. They were fixed to the moment of creation (sections 21–23) | Editable date field on each, while Draft |
| 13 | The invoice PDF printed the due date as `2026-10-28` next to a formatted invoice date | Both formatted the same way |
| 14 | Drawing upload | ◐ | Native picker, copies the file (never moves it). PDF, DWG, DXF, PNG, JPEG or TIFF. Each drawing can be linked to one of the project's BOQs or quotations and is listed inside that document. Rename, replace, archive, description. **One file per upload**, no multi-select |
| 15 | Exported PDFs weren't linked to their document in the database (section 32). Re-exporting made `… (2).pdf`, `… (3).pdf` copies | Each document stores its PDF's path, and Restore updates it for another Mac. Re-exporting replaces that document's PDF |
| 16 | New delivery notes started with no delivery address | Filled in from the site's address. The PDF only prints a separate "Deliver to:" line when it differs from the site |
| 17 | Upload errors for drawings and documents were silently swallowed. File names were inserted as raw HTML | An error message is shown. Names are escaped |
| 18 | The "Add a custom item" form stayed usable on issued documents and only failed when submitted | Hidden unless the document is a Draft |

## Coverage of the prompt, section by section

**Legend:** ✅ built (reads correct) · ◐ partly built · ✗ not built

| § | Area | Status | Notes |
|---|------|:-:|---|
| 1 | Inspect samples & Excel | ◐ | Price data imported, and the quotation is modelled on Qt26193. Invoice, BOQ and delivery-note samples weren't used (see below) |
| 3–4 | Native Mac look | ◐ | WKWebView app inside a native window with a native menu bar, sheets and file pickers. It isn't SwiftUI, so tables, fields and sidebar are HTML styled to look like a Mac app |
| 5 | Light/Dark/System | ✅ | Follows System by default and switches live. A leftover hard-coded light colour in `boq-editor.html` (`.section-header`) is unused |
| 6 | Sidebar navigation | ✅ | ⌘1–⌘7 |
| 7 | Dashboard | ✅ | Every listed panel and quick action is there. "New Quotation/Invoice/Delivery Note" opens the chosen project's tab, but you still press "+ New" there |
| 8 | Price lists | ◐ | Search, filter, category, add, edit, duplicate, archive, Excel/CSV import with preview, CSV export all work. The **Notes** field isn't shown or editable |
| 9–10 | Sites, Clients | ✅ | Create, edit, archive/restore, search, related projects and documents |
| 11–12 | YYNNN numbering | ✅ | Auto-proposed. The year rolls over (27001 in 2027). Validation is fixed (see #2). Anyone can override; there are no user roles |
| 13 | Project creation | ◐ | Required and optional fields plus drawing upload all work. You **can't create a client or site from inside the New Project form**, and there's no hint when none exist yet |
| 14 | Drawing upload | ◐ | Native picker, copies the file (never moves it), rename, replace, archive, description. **One file per upload**, no multi-select |
| 15–17 | Project page, statuses, overview | ◐ | Every tab and status is there. The Overview has no **"Recent documents"** list (section 17), only recent activity |
| 18 | BOQ item picker | ✅ | Both lists, search, category |
| 19 | BOQ table | ◐ | Reorder, duplicate, delete, per-line notes. Per the owner's later request it shows **weights, not prices**, so BOQ discount, tax and money totals are gone. Lines are **not grouped into sections with subtotals** |
| 20 | Price override shown vs list price | ◐ | Quotation lines remember their material-list price: a hand-typed price shows "List 25.00" under it and is kept when switching Sale ↔ Rental. BOQ lines track it too but show weights. Invoice lines don't track it yet |
| 21 | Quotations | ✅ | From a BOQ, blank, or custom lines. Letter fields, discount (whole quotation or per item), tax, delivery charges, optional minimum hire. Switching Sale ↔ Rental re-prices existing items. Items listed in item-code order. Date is editable |
| 22 | Invoices | ✅ | Always based on one of the project's quotations (items, prices, line discounts, terms, Sale/Rental). A rental invoice charges one month's rent or the full hire period; the months and rental period can be changed while Draft. Every status, payments, cancel-not-delete |
| 23 | Delivery notes | ✅ | No prices, delivered-by / received-by, signatures, PDF |
| 24 | Numbering | ✅ | Separate sequences, configurable formats, company defaults Qt26XXX / H26XXX, "continue from" numbers, never duplicates |
| 25 | Lifecycle | ✅ | Fixed in this pass (see #3, #4). A BOQ has no "Cancelled" status |
| 26 | Separate templates | ◐ | All four documents now use the Qt26193 letterhead, footer, colours, fonts and table style (see "Letterhead layout" below). Each has its own title, reference block, columns and signature block. The quotation matches the sample; invoice, BOQ and delivery note follow the same style because there are no samples for them yet |
| 27 | PDF generation | ✅ | Drawn directly, not screenshots. Repeating headers, page numbers, and totals and signatures kept together. A4/Letter |
| 28 | Company info | ✅ | Bank details, terms, signatory. It lives in Settings rather than Admin. The logo chooser was removed: every PDF uses the fixed company letterhead |
| 29–35 | Folders in ~/Documents | ✅ | `~/Documents/ScaffoldPro/Projects/<number>/{Drawings,BOQ,Quotations,Invoices,Delivery Notes,Documents,Other}` plus `Administration/…` and `Backups/`. Meaningful file names |
| 36 | Show in Finder | ✅ | Project, drawing, document, worker, backup folders |
| 37 | Database + files | ◐ | Uses **JSON files, not SQLite** (section 46 prefers SQLite). Writes are atomic and unreadable files are preserved, but there are no foreign keys or constraints, and every operation re-reads the whole file |
| 38 | Missing-file handling | ✅ | "File unavailable" with Locate File / Remove Reference, for drawings, documents, worker and company documents. Not yet for exported PDFs |
| 39 | Backup/Restore | ✅ | Self-contained folder with Database, Projects, Administration, Configuration. A safety backup is taken before every restore. File paths are re-pointed when restoring on another Mac |
| 40–43 | Admin, workers, documents | ◐ | Workers, worker documents with expiry, company documents with categories, search and expiry reminders. **No "Replace" for worker or company documents** (section 42). Company info, numbering and backup are in Settings, not Admin |
| 44 | ⌘K search | ✅ | Every listed type. Worker results fixed (#10) |
| 45 | History | ✅ | Logged per project and shown on the History tab and Overview |
| 47 | Technology | ◐ | Swift + AppKit window + WKWebView UI (HTML/JS) rather than SwiftUI. It works, but it's the "web app in a Mac window" the prompt warns against |
| 48 | Data safety | ✅ | Autosaves on every change, atomic writes, confirmations, archive instead of delete |
| 49 | Import/export | ✅ | Excel/CSV import, CSV export, PDF, full backup |
| 50 | Currency/tax | ✅ | Configurable. Exact decimal totals. Prices can be set as tax-inclusive. EUR→HKD rate for SCAFOM |
| 51 | Tables | ◐ | Sorting, search, selection, context menus on projects and files. **No column resizing.** Right-click "Copy" only on projects |
| 52–53 | Empty states, plain errors | ✅ | Some native error text (`localizedDescription`) still appears inside messages |
| 54 | Printing | ✅ | Native print dialog, A4/Letter |
| 56 | Privacy | ✅ | No network calls, analytics or accounts |
| 57 | Settings | ✅ | All the listed groups. About is the standard ScaffoldPro → About menu item |
| 60 | Accessibility | ◐ | Keyboard shortcuts and focus rings. No text-size setting, and ARIA labels are sparse |
| 62 | Validation | ◐ | Rules are enforced. Messages mostly appear as alert dialogs, not next to the field (section 62). No email or phone format checks |
| 63 | End-to-end test | ✗ | Never run: needs a Mac |

## Letterhead layout (from the sample quotation Qt26193)

Every PDF (quotation, invoice, delivery note, BOQ) is now drawn in the
layout of the company's quotation:

- **Header and footer:** positions, sizes and colours were measured from
  the sample (orange `#F19E38`, grey `#999999`, dark grey `#666666`).
  Each piece of the "PROFICIENCY / 建機 (香港) 有限公司 (HK) LIMITED"
  letterhead is scaled to fill exactly the box it fills on the sample, so
  it comes out the same whichever font version the Mac has. The footer is
  Times New Roman 9pt (Chinese line in Songti), placed word by word, with
  "Page N" at the right.
- **Body:** EB Garamond (the Google Docs font of the original, bundled in
  `resources/fonts` under its free SIL Open Font Licence). Client 12pt,
  reference block and text 11pt, title 15pt bold and underlined,
  "BY EMAIL ONLY" 13pt.
- **Tables:** black 0.75pt rules, bold centred headings, "HK$" at the left
  of money cells, bold "Total Amount:" rows, "Delivery Charges" section.
  Column titles repeat on every page.
- **Terms and signatures:** laid out as on page 2 of the sample. Signature
  blocks are Times New Roman Bold Italic and always kept together on one
  page.
- A Python copy of the layout code was rendered and compared with both
  sample pages. Every header, footer, table and text element was within
  1 pixel (0.75pt).
- **Not reproduced:** the hand signature and company chop on the sample.
  Those are added when signing.

## Not built yet (suggested order)

1. **Build and run it on a Mac** (`./install.sh`) and fix whatever the
   compiler reports. Then do the section 63 walkthrough, especially PDF
   output, backup/restore and the new-year numbering case.
2. **Invoice, BOQ and delivery-note details from real samples**
   (section 26). They already use the Qt26193 letterhead and style, but
   their reference block, columns and signature wording are my best guess.
3. **Section 20 price-override marker** on invoice lines (quotations have
   it).
4. **Replace** for worker and company documents (section 42), and
   **multi-file upload** for drawings (section 14).
5. **Recent documents** on the project Overview (section 17), plus
   **Open PDF / Show PDF in Finder** on each document now that the path is
   stored.
6. **New client / new site** buttons inside the New Project form
   (section 58's workflow).
7. BOQ **section grouping with subtotals** (section 19), and reorder or
   duplicate for quotation, invoice and delivery-note lines.
8. Price-list item **notes**. Table **column resizing**. Validation
   messages **next to the field**.
9. Bigger decisions: move storage to **SQLite** (section 46), and/or move
    the UI to **SwiftUI** (sections 3–4, 47). Both are large rewrites, and
    the current JSON + WebView build works for a single-user app of this
    size.

## Questions for the owner

1. Please re-attach the **sample invoice, BOQ and delivery note** (and the
   Excel workbook, if the import should be re-checked). They weren't in
   the uploaded zip.

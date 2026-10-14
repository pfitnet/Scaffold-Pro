# ScaffoldPro: one design, every page (redesign plan)

> **Status (14 Oct 2026):** R0–R12 carried out in Batches 241–256. Not done,
> on purpose or still open:
> - R9b: the shared `openPartySheet`. Projects' quick New Client / New Site
>   keep their own form.
> - R10a: a shared `periodPicker`. Accounting keeps its dropdown. Admin's
>   Upload asks for the category first: choosing files first needs the
>   Swift side.
> - R11: Backup & Restore's buttons are not yet folded into Back Up Now plus
>   `···`. Settings › You still shows "Your work".
> - R12: the break-ui worst-case pass and the animation review were not run.
>   `data:image/svg` select carets remain in styles.css. Some JS-made
>   strings still use dashes (Swift-made ones keep theirs by design).
> - Not checked anywhere: WebKit on a Mac and the Swift build. Ask the user
>   to look after updating.

## Context

ScaffoldPro's interface (26 HTML pages in a WKWebView, `ScaffoldPro-native/`) grew one batch at a time. It now reads as generic and dull, and as separate parts forced together:

- **Generic look.** It uses the stock "AI SaaS" blue-violet gradient (`--grad-accent`), a fading-accent title gradient, a radial accent wash and glows.
- **The same thing is built many separate ways.** Each page grew its own version of the shared parts:

| Part | Separate versions |
|---|---|
| Page headers | 9 |
| Tab-switching scripts | about 10 |
| Modal systems | 5 |
| Toast styles | 6 |
| Hand-drawn icon sets | at least 9 |
| Number-tile styles | 8 |
| Search boxes with a "/" shortcut | several |

  - Some tabs mark the chosen one with `.active`, others with `.on`.
  - `js/icons.js` turns any button labelled "Delete", "Open" or similar into a bare icon, so toolbars end up half words and half icons.
  - Primary-button labels don't match from page to page, e.g. "New Worker" against "Add Worker".
- **The four document editors share about 80% of their markup,** copied and pasted along with their own `<style>` blocks. `quotation-editor.html` alone has 144 lines of inline style and shows about 10 toolbar controls.
- **Page-specific styling everywhere:**
  - 11 pages carry inline `<style>` blocks;
  - page stylesheets define their own token sets (`--tk-*` in `tasks.css`, `--viz-*` in `marketing.css`);
  - about 114 hard-coded hex values sit in `styles.css`, plus more in JS.
- **Navigation is long.** The sidebar lists 15 items, and some of them are thin pages that belong together:
  - Tasks and Calendar;
  - Chat and Team;
  - the Assistant, which already floats on every page;
  - the User Manual.

**The goal** is to rebuild every page into one coherent system with one theme. It must keep or improve the things that already work:

- interactivity;
- motion that has a reason;
- clarity of information;
- above all, usability and speed of use.

This plan is written for the next model (Opus 5.5, high effort) to carry out in staged batches, following the repo's standing workflow (HANDOFF.md §2).

### Before you start (read this first)
- **Line numbers in this plan are from commit `902d5bf`.** Batches 233–240 landed after it was written, so re-check each `file:line` before editing. Treat the line numbers as places to start looking, not exact positions.
- **Batches 233–240 added UI that this plan must also cover:**
  - Batch 233: issued, chopped and signed borders on Projects › Overview;
  - Batch 237: Settings › What's New;
  - Batch 238: the quotation's Columns… sheet (`js/quotation-columns.js`) and the custom-column cells in the line table;
  - Batch 240: the folding sidebar.
  Each one belongs in the batch for its page (R4, R11, R5a/R5b and R2b).

### Decisions already made with the user
- **Palette: "Steel & Signal".** Cool galvanised-steel neutrals with one muted safety-orange accent. It ties in with the letterhead's orange (`PDFGenerator.orange` #F19E38) and the logo's steel.
- **Typeface: Geist, with Geist Mono** for document numbers, codes and money columns. Both are bundled locally under the OFL licence.
- **Merging pages, splitting or joining menus, and new controls are all allowed**, in the user's words: "feel free to do anything necessary".
- **Small screens: Mac, iPad and phone.** The pages also reach iPads and phones through ScaffoldPro Web, so every page gets a proper layout down to phone width (§3.4).

### Design read (design-taste-frontend §0.B)
*Reading this as: an overhaul of a dense native-Mac business workspace for a five-person Hong Kong scaffolding firm. The language should be calm, roomy and tactile, like a "site office". It leans toward a custom token system in plain CSS and vanilla JS, with no framework and no build step.*

**Dials:**

| Dial | Value | Why |
|---|---|---|
| `DESIGN_VARIANCE` | 4 | This is product UI, so it should be predictable. Variance belongs only in hero and header composition. |
| `MOTION_INTENSITY` | 4 | Motion is for feedback and state only. The user rejected slow fades (Batches 224 and 225). |
| `VISUAL_DENSITY` | 5 | Roomy, but the data has to stay scannable. |

**How the skills apply.** design-taste-frontend §13 rules out dashboards and admin UI, and the high-end-visual-design skill targets marketing pages. Only the parts that suit a work tool are taken from them:

- one accent;
- a shape lock;
- no gradients or glows;
- a double bezel only on "hero" surfaces;
- a nested trailing icon on the one primary call to action on a page;
- tinted soft shadows;
- the animate skill's frequency gate, tokens and durations, but **not** its reduced-motion rule (§1.3).

The apple-design skill is **not** used, and nothing from Batch 223's Apple pass binds this plan (§1.3).

Explicitly **not** taken:

- page entrance animations or scroll reveals (the user rejected them, and Batch 226's snapshot already hides page building);
- sections padded to `py-24` or more;
- the pointer-tracking light on cards;
- eyebrow pills above every heading.

---

## 1. Hard constraints (carry into every batch)

1. **No flashing, ever** (HANDOFF §3):
   - never call `location.reload()`;
   - redraw with `window.appRefresh`, or else `window.softReload()`;
   - do not touch the page-change snapshot in Batch 226 (`decidePolicyFor` in `Sources/Assistant.swift`, `ui:releaseFrame` in `js/bridge.js`);
   - no fade-out or rise-in between pages in the Mac app.
2. **Fades the user rejected stay out:**
   - sheets fade in quickly and close at once;
   - dialogs close at once;
   - toasts rise from below.
3. **No Apple-design constraints (the user's instruction for this redesign).** Nothing that Batch 223's apple-design pass imposed on motion or interaction binds this redesign, and the apple-design skill is not used:
   - **The macOS Reduce Motion setting is not followed.** Animations play whatever the system setting. Remove:
     - the catch-all `prefers-reduced-motion` block (styles.css L847–863) and every other `prefers-reduced-motion` block in `css/*.css`;
     - the `reduce` checks in `js/motion.js`, `js/drag-reorder.js`, `js/assistant.js` and any other JS (`grep -n "reduced-motion\|reduce)" js/*.js`).
   - **Reduce Transparency and Increase Contrast handling** (styles.css L2692–2715) is removed. Contrast is still met by the tokens themselves (§6.2 step 5).
   - **Overshoot is allowed again.** Batch 223 made every curve critically damped; things that should feel alive may spring past and settle (§2.6).
   - **Looping and attention motion are allowed** wherever they help, e.g. the "now" dot, an Active project's status dot, a sign request. They no longer have to "play a few times then rest".
   - The Undo toast, press-down feedback and the rubber-band drags from Batch 223 are ordinary features now, not rules. Keep them where they work and change them freely.
   - In R0, update HANDOFF.md §3: the "micro-animations that respect Reduce Motion" line now reads "micro-animations everywhere; the app does not follow Reduce Motion".
4. **Element ids, `data-*` hooks and JS-facing class names stay**, unless the JS that uses them is changed in the same batch. Before renaming a class, grep for it across `js/*.js` and the Swift files. Specifically:
   - **Page skeleton.** `<nav id="sidebar">`, `<main id="content">` and `body[data-page]` stay. The editors and `letters.html` use `data-page="project-detail"`. Home keeps `data-page="dashboard"`, which `notify.js:13` and other code read.
   - **Editors.** The **hidden real controls** stay: `multiply-btn`, `line-sort`, `export-pdf-btn`, `export-word-btn`, `data-selects`, `data-multiply`, `data-sort`. Menus drive them. So do `#back-link`, `#not-found`, `#status-select`, `#orientation-select` and `#language-select`.
   - **Action ids that Swift or other JS clicks** stay as real `<button>`s, hidden or inside a menu. Their `disabled` state is kept up to date, and menu items click them and copy that state:
     - `#print-btn` (`main.swift:1527`, ⌘P, which checks `.disabled`);
     - `#locate-file-btn`, `#duplicate-doc-btn`, `#delete-doc-btn` (`document-actions.js:63–74`);
     - `#split-btn`, `#revert-split-btn` (`quotation-editor.js:121, 1267–1268`);
     - the letter editor's `#delete-btn`;
     - on project-detail: `new-boq-btn`, `new-quotation-btn`, `new-invoice-btn`, `new-delivery-note-btn`, `new-letter-btn`, `record-inspection-btn`, `new-task-btn`, `upload-drawing-btn`, `upload-document-btn` (`runQuickAction`, project-detail.js:893–901; the `?new=1` map, L1169–1171).
   - **Inputs in editor tables.** `keep-focus.js` and `qty-tab.js` need `input.qty-input` and `input.row-qty` and stable input ids and order across redraws. Keep them.
   - **`doc-authors.js`** wraps the h1 parent in `.doc-hero` and polls `#status-select`. Rework it into the new `.doc-bar`, keeping the linked-document chain (`flowHTML`), the author line (`metaHTML`) and click-to-copy on the number. Don't just break it.
   - **Open-sheet guards.** Every sheet keeps `modal-backdrop` on its backdrop, and `dialogs.js` keeps `app-dialog-backdrop`; the new `.sheet` classes are added alongside these. Several places read them to hold sync redraws, ⌘Z and shortcuts while a sheet is open: `bridge.js:747` (busy), `undo.js:38`, `tasks.js:553`, `calendar.js:592`, `doc-select.js:94`, `doc-preview.js:143` and `widgets.js:458`.
   - **Page functions Swift calls** keep their names and signatures:
     - `appDialog({message, buttons})` (main.swift:1000);
     - `appUpdatePrompt(latest)`, which returns 'now' or 'later'. Swift installs the update if it fails or returns anything else (main.swift:902–910);
     - `saveOpenWork`, `beforeAppUpdate`, `appNavigate`, `appUndo`, `openGlobalSearch`;
     - `__assistantStep`, `__sharedDataChanged`, `__nativeCallback`.
     The batch that touches `dialogs.js` tests each one in Playwright.
   - **Saved layouts.** The `data-widget` names on Home and the project Overview are saved in user layouts; keep them.
   - **Deep links that must still land:**
     - `sites.html?id=` and `?new=1`;
     - `settings.html#you` and `#backup`;
     - `projects.html?view=overview` and `?new=1`;
     - `workers.html?worker=`;
     - `marketing.html?tab=leads&lead=`;
     - `tasks.html?task=`;
     - `project-detail.html?tab=` and `?new=1`;
     - `?tab=` on accounts, admin, costs, marketing, stock and team;
     - `stock.html?dn=`;
     - `calendar.html?day=&event=` (Database+Records.swift:560);
     - `team.html?tab=signatures&review=` (:1126);
     - `chat.html?with=` (team.js:94, read by chat.js:412);
     - `project-detail.html?…#drawings` and `#documents` (:1479, :1484), `&tab=inspections|tasks|letters|history`, and `?new=1&tab=<old tab>`;
     - the saved `sessionStorage['project-tab-<number>']`, which holds the old tab names (project-detail.js:746, 755);
     - `price-lists.html?source=&q=` (:1496);
     - `marketing.html?tab=leads&new=1`;
     - `projects.html?new=1&client=&site=` (connections.js:185);
     - `clients.html?id=`, `?new=1` and `?newSite=1`;
     - `letters.html?project=`;
     - `settings.html#team` and `#ai-import`.
     Merged pages keep these working through redirect stubs or `?tab=` mapping.
   - **`window.appRefresh`** is set on 17 pages. Each rebuilt page must still set it and redraw in place.
   - **Launch screen.** `launch.html`'s ids are driven by Swift through `window.launch.*`: `status-words`, `panel-*`, `bar`, `bar-fill`, `buttons`. Recolour it only.
5. **Keep the meaning of these fixed colours** (HANDOFF §3). They are used in the Google Sheet, the PDFs and in `personColor` ↔ Swift `sheetsPeopleColours`:
   - the five document colours;
   - the six project-status colours;
   - the 12 person colours.
   Light and dark variants may be retuned for contrast, but the hues stay.
6. **Wording:** plain British English with short labels. No em dashes in visible UI copy; use a full stop, a comma or a colon. Dates follow `window.appDay` (`7 Oct 2026`).
7. **Settings-style editing stays:**
   - values show as text with a pencil;
   - switches, dropdowns and segmented controls act at once;
   - changes autosave with a small "Saved".
8. **Keyboard everywhere:**
   - arrow keys, Return and Esc work naturally;
   - ⌘Z and ⌘Y work without a flash;
   - ⌘K, ⌘J and ⌘1–7 keep working, **on the same pages as today**: Home 1, Costs 2, Clients 3, Projects 4, Stock 5, Accounting 6, Admin 7. These are `NAV_ITEMS.key` in sidebar.js:64–80 and the Go list at main.swift:1441–1448;
   - ⌘N stays New Project (main.swift:1394).
   The Go menu's other pages are at main.swift:1450; update it when pages merge.
9. **ScaffoldPro Web** serves the same pages to browsers. The design must also work in Chrome and Safari, where `html.web` is set and SF Pro is not available (another reason to bundle Geist).
10. **Swift is never compiled here.** Swift changes stay minimal and are checked with the tree-sitter method (HANDOFF §4.1). Expected Swift changes:
   - `PageBackdropView.color` in `Sources/Assistant.swift` L18–32;
   - the Go menu titles and entries (main.swift:1441–1454);
   - the `WebServer.loginPage()` HTML string (R11);
   - nothing else. Fonts need no Swift change: `WebServer.contentType` already maps woff2 to `font/woff2` (WebServer.swift:530), and the Mac app loads from file://.
   - Visible strings that Swift builds (search results, calendar events, notices) keep their "—" separators. That is accepted, because no other Swift edits are allowed.
11. **The Mac title-bar strip.** The top 38px of the Mac window is a native drag strip that takes every click (`TitlebarDragView`, main.swift:19–33; height at L1276–1281).
    - Add a `--titlebar-safe: 38px` token, set to 0 under `html.web`.
    - Sticky bars (`.doc-bar`, table heads, `.rt-toolbar`) use `top: var(--titlebar-safe)`.
    - `full` sheets, menus and popovers stay below it.
    - Top padding on pages and the sidebar stays at 44px or more in the Mac app (styles.css:160, :236).

---

## 2. The design system ("Steel & Signal")

Everything lives in `css/styles.css`, which stays the single shared stylesheet. Its token block is rewritten rather than having a second system added next to it (animate skill, rule 3).

### 2.1 Colour tokens
Keep the existing token **names** so the roughly 2,700 lines of CSS that use them follow along. Change their **values**, and add the missing ones.

| Token | Light | Dark | Notes |
|---|---|---|---|
| `--bg` / `--content` (canvas) | #EDEFF1 / #EEF0F2 | #111316 / #121417 | Remove the `body::before` accent wash. |
| `--panel` (surface) | #FAFBFC | #191C20 | |
| `--panel-2` (sunken) | #F3F4F6 | #1E2125 | |
| `--header-bg` | #F3F4F6 | #1E2125 | |
| `--border` / `--hairline` | #DADDE2 / rgba(21,24,28,.08) | #2A2E34 / rgba(255,255,255,.07) | |
| `--border-strong` | #C6CBD2 | #3A3F46 | |
| `--text` | #15181C | #ECEEF0 | |
| `--text-secondary` | #5A626C | #9AA2AC | |
| `--text-tertiary` | #8A919A | #6E7680 | |
| `--accent` (selection, focus, ink) | #C9561F | #E7773E | |
| `--accent-fill` (new; primary button fill) | #B94E19 (5.0:1 on white) | #E7773E | #C9561F with white text is only 4.35:1, which fails AA. |
| `--on-accent` (new) | #FFFFFF | #15181C (6:1) | |
| `--accent-text` (new; links and accent text on a surface) | #A9461A (5.6:1) | #E7773E (5.8:1) | |
| `--accent-soft` | rgba(201,86,31,.10) | rgba(231,119,62,.16) | |
| `--focus-ring` | rgba(201,86,31,.28) | rgba(231,119,62,.36) | |
| `--danger` / `--warning` / `--success` | #C23B32 / #A8620C / #23824A | #FF6B61 / #F2AA45 / #4FCB7E | The warning colour must stay visibly different from the accent: keep it amber-yellow, not orange. |
| `--danger-soft` / `--warning-soft` | color-mix(in srgb, var(--danger) 10%, transparent) / the same with `--warning` at 13% | the same at 14% | |
| `--accent-hover` | #A9461A | #F08A55 | Today blue (#2e57d8 / #88a2ff). |
| `--row-hover` | rgba(21,24,28,.035) | rgba(255,255,255,.04) | Today blue-tinted. |
| `--seg-active` | #FAFBFC | #2A2E34 | |
| `--sidebar` / `--sidebar-hover` / `--sidebar-selected` | rgba(237,239,241,.82) / rgba(21,24,28,.05) / #FAFBFC | rgba(17,19,22,.78) / rgba(255,255,255,.05) / rgba(255,255,255,.085) | |
| `--field-bg` / `--field-border` / `--field-hover` | #FFFFFF / #D3D7DD / #BCC2CA | #15171B / #2E3238 / #40454D | |
| `--titlebar-safe` (new) | 38px | 38px | 0 under `html.web` (§1.11). |

- **Every token** in the `:root` and dark blocks (styles.css L13–66 and L74–115) gets a new value.
  - R1a checks that `grep -nE "58, *102, *240|109, *141, *255|#3a66f0|#6d8dff" css/*.css *.html js/*.js` comes back empty. The one exception is the Completed status colour (below).
- **Status colours are fixed hex, never theme tokens.**
  - Today `.st-completed` uses `var(--accent)`, `.st-quotation` uses `var(--warning)` and `.st-active` uses `var(--success)` (styles.css:1858–1864), so retuning those tokens would turn Completed orange. Change them to the HANDOFF hexes: Completed `#3a66f0`, Quotation `#c98a14`, Active `#2a8a4a`. These match `ScaffoldPro-core.js:32`.
  - The default `--st` on `.pj-filters`, `.pj-grid` and `.pj-table` becomes `--text-tertiary`.
- **The accent is never a selection colour.** The accent sits within about 4° of hue of On Hold `#e0793a`, so selection never uses an accent fill or bar. A selected table row, list row, filter chip or segmented thumb uses ink: a `--text` bar, or a `--panel` fill with a hairline. The accent is kept for:
  - the focus ring;
  - the one primary fill;
  - links and accent text;
  - the selected sidebar icon.
- **Sweep how the accent is used.** Today's 127 text uses, `color: var(--accent)`, become `var(--accent-text)`. Every `background: var(--accent)` with white text (about 35, e.g. styles.css:1684 `.hm-item:hover`, :830 `.context-menu button:hover`, :1747 `.cal-cell.sel`, chat.css:54, settings.css:27, stock.css:85, calendar.css:105) becomes one of:
  - `background: var(--accent-fill); color: var(--on-accent)` where it is a real primary;
  - the ink selection style;
  - `--row-hover` for menu hovers.
  Menu rows are never filled with the accent.
- **Delete** `--accent-2`, `--grad-accent` and `--accent-glow`, and every use of them:
  - the gradient primary button;
  - the h1 text gradient (styles.css L255–259);
  - the gradient search result;
  - the gradient `.nav-ink` bar;
  - the gradient empty-state tile;
  - the gradient `.as-launcher`.
- **Hard-coded hex values become tokens.** This covers styles.css (about 114), `dialogs.js`, `tasks.css` (`--tk-*`), `marketing.css` (`--viz-*`, which is fine to keep as chart tokens), `workers.css`, inline `<style>` blocks, and hex values in JS (`grep -oE "#[0-9a-fA-F]{6}" js/*.js`). Keep the doc, status and person palettes, chart colours and the brand mark.
- **Dead selectors.** Remove `:root[data-theme="dark"]` (styles.css L2366, tasks.css L23/L29): nothing sets it.
- **Reduce Transparency and Increase Contrast blocks** (L2692–2715) are deleted (§1.3).
- **Swift.** `PageBackdropView.color` takes the new `--content` values exactly.

### 2.2 Type
- **Fonts to bundle:** Geist (variable woff2, 100–900) and Geist Mono (variable woff2).
  - Source: npm `geist@1.7.2` (`npm pack geist@1.7.2`, which works through the proxy). The package holds `package/dist/fonts/geist-sans/Geist-Variable.woff2` and `package/dist/fonts/geist-mono/GeistMono-Variable.woff2`; copy `package/LICENSE.txt` (the OFL) as `Geist-OFL.txt`.
  - Icons come from `npm pack @phosphor-icons/core@2.1.1` (MIT); keep its licence as `js/vendor/PHOSPHOR-LICENSE`.
  - Put them in `resources/fonts/ui/`, next to the existing document fonts. `install.sh` already copies `resources/`.
  - `@font-face` goes at the top of styles.css with `url('../resources/fonts/ui/…')`, the same path pattern `css/marketing.css` L251 uses.
  - `font-display: block`, because the files are local and there should be no swap flash.
  - The first page is never under the Batch 226 snapshot, and file:// loads are local, so no preload is needed. If a page change in the Mac app ever shows a frame of blank text, add `&& (!document.fonts || document.fonts.status === 'loaded')` to `built` in bridge.js's `releaseWhenBuilt` check. It is still capped by `READY_MAX_MS`, and this is the one allowed touch of §1.1.
  - The web login can reach `/resources/fonts/` before sign-in (WebServer.swift:430), so it can use Geist too.
- **Stacks:**
  - UI: `"Geist", -apple-system, "PingFang HK", "PingFang TC", sans-serif`. Chinese falls back to PingFang.
  - Mono: `"Geist Mono", ui-monospace, Menlo, monospace`.
- **Scale** (Geist runs slightly wide, so the body is 13.5px):

| Role | Size / line height | Weight | Tracking |
|---|---|---|---|
| caption | 11.5 / 16 | 500 | |
| small | 12.5 / 18 | | |
| body | 13.5 / 20 | | |
| body-strong | 13.5 / 20 | 560 | |
| h3 | 15 / 20 | 600 | |
| h2 | 18 / 24 | 620 | -0.01em |
| page title (h1) | 26 / 32 | 650 | -0.02em, solid ink, no gradient |
| hero figure | 32 / 36 | 600 | -0.02em, tabular |

- **Section labels:** sentence-case 12.5px / 560 in `--text-secondary`. This replaces today's uppercase tracked micro-labels on every panel; uppercase is kept only for table headers, at 11px / 0.04em.
- **Numbers:**
  - every money and quantity column uses `font-variant-numeric: tabular-nums`;
  - document numbers (Qt26219-002), item codes, project numbers and HKID use Geist Mono through a shared `.mono` class.

### 2.3 Shape, depth, spacing
- **Radius lock:**

| Token | Value | Used for |
|---|---|---|
| `--radius-sm` | 6px | chips, tags |
| `--radius` | 8px | buttons, inputs, menu items |
| `--radius-lg` | 12px | cards, panels, tables, menus |
| `--radius-xl` | 16px | sheets, dialogs, popovers, hero panels |
| full | | status pills, avatars and the segmented track |

  Nested elements use concentric radii: inner = outer − padding.
- **Depth.** Mostly hairlines, with shadows tinted to the steel (rgba(21,24,28,…)), never black:
  - `--shadow-control`: 0 1px 0 rgba(21,24,28,.04);
  - `--shadow-card`: 0 1px 2px rgba(21,24,28,.05);
  - `--shadow-lift`, used only on hover of clickable cards: 0 6px 18px -6px rgba(21,24,28,.14);
  - `--shadow-menu` and `--shadow-sheet`: soft and diffuse, plus a 0.5px ring.
- **Double bezel** (high-end-visual-design §4A), used only on these four:
  - the project header;
  - the document "paper" preview, as a page sitting in a tray;
  - sheets and dialogs;
  - the Home greeting panel.
  It is an outer shell (`--panel-2`, a 1px hairline, 5px padding, radius 16) around an inner core (`--panel`, radius 11, `inset 0 1px 0 rgba(255,255,255,.6)` in light). Nowhere else.
- **Spacing:**
  - 4px base: 4, 8, 12, 16, 20, 24, 32, 40, 56;
  - page gutter 32px, rising to 40px at ≥1440px;
  - 24px between page sections;
  - 16px inside cards;
  - control height 32px (`--control-h`), and 36px for the primary call to action in a page header.
- **Layers.** Document the z-index scale once, in tokens:

| Layer | z-index |
|---|---|
| sidebar | 10 |
| sticky bars | 20 |
| floating assistant | 40 |
| menus and popovers | 60 |
| sheets | 80 |
| dialogs | 90 |
| toasts | 95 |
| tooltips | 99 |

  Today's ad-hoc values (10000, 10050, 10060, 9000, 950) all map onto this scale.

### 2.4 Icons: one family
- **Replace all three hand-drawn sets with Phosphor (MIT), "regular" weight**, taken from npm `@phosphor-icons/core` (`assets/regular/*.svg`).
  - Only the glyphs in use are copied in (about 60).
  - **Registry** in `js/icons.js`. `window.ICON_PATHS[name]` holds the Phosphor path data: filled paths on a 256 viewBox. `window.icon(name, {size, cls})` returns `<svg class="${cls||'btn-icon'}" viewBox="0 0 256 256" width height fill="currentColor" aria-hidden="true">…</svg>` with **no stroke attributes**.
  - **`window.ICONS[name]` stays a whole 16px `<svg>` string** built from the registry, because icons.js:64, dashboard.js:244/246 and doc-select.js:45/49 insert it directly.
  - **In the same batch, delete sidebar.js's global `const ICONS` (L9–31) and `function icon` (L33).** Being top-level in classic scripts, they would clash with `window.icon` and with any new top-level `ICONS`. Sidebar calls become `window.icon(name, {size:18, cls:'nav-icon'})`. Load `icons.js` before `sidebar.js` on every page; today some pages load it after.
  - Phosphor "regular" weight everywhere, coloured by `currentColor`: 16px in controls, 18px in the sidebar.
- **Where the icons come from:**
  - `js/sidebar.js` `ICONS` (L9–31) and `BRAND_MARK` (the logo stays as it is);
  - `widgets.js`, `notify.js`, `settings-ui.js`, `manual.js` (its local `icon()`, L85), `workers.js` `I`, `stock.js` `ICON`, `calendar.js` `KINDS`, the Dashboard's `QA_SVG`, `team.js` constants;
  - the 57 inline SVGs in the HTML pages;
  - the CSS data-URI icons (styles.css L296, 307, 340, 532, 2265; settings.css L134).
  All of them use the registry.
- **The automatic label→icon swap** in `icons.js` (its `LABELS` MutationObserver) stays. It now draws Phosphor glyphs, and every icon-only button gets a tooltip (`title` stays).

### 2.5 Components: rebuilt once in styles.css, used everywhere
Each component gets one canonical class family. Old aliases are kept only where JS creates the old class; the JS is migrated in the batch that touches that page.

| Component | Spec |
|---|---|
| **Button** | Kinds: `primary` (`--accent-fill`, `--on-accent` text, no gradient, no glow), secondary (surface fill, hairline), `ghost`, `danger`, `icon-btn` (32×32, tooltip). Press: `scale(.97)` over 100ms (`--dur-press`). A page's single primary call to action may carry a trailing icon in a 22px circle (`.btn-cta > .btn-cta-ico`, the nested-island style), which moves 1px up and to the right on hover, under `(hover:hover)` only. |
| **Field** | Label above, helper and error text below; 32px tall, 8px radius, `--field-bg`; focus is a 3px `--focus-ring` with no glow animation. The read-only "value + pencil" row from Settings is formalised as `.value-row` and reused on the Details tabs (project, client, worker). |
| **Select** (`controls.js` menus) | Same look as the menus. |
| **Segmented** | The track is `--panel-2`; the thumb is `--panel` with a hairline and `--shadow-control`, and slides (`.seg-ink`). |
| **Switch** | New: 30×18 track, accent when on, 160ms thumb. It replaces tick boxes for any setting that acts at once. |
| **Tabs** | One style: text tabs with a 2px ink (`--text`) underline that slides (`.tab-ink`); the accent is not a selection colour (§2.1), plus counts in `.tab-count`. Used on Project, Stock, Marketing, Admin, Workers, Accounting, Settings sub-pages and Schedule. |
| **Toolbar** | `.toolbar`: search (with the `/` hint) · filter chips or segmented · spacer · sort menu · view toggle. Always in this order. R1c gives `.toolbar` no fixed height, because the five editors use `.toolbar` for their action bar (`quotation-editor.html:162` and siblings, with an inline `justify-content`). That bar keeps its layout until R5 and R6 rename it to `.doc-bar`. |
| **Page header** | `.page-header`: title (h1) and a one-line context. On nested pages, breadcrumbs replace the `.page-back` link (Projects › 26219 Kai Tak › Qt26219-002). On the right sit at most **one** primary call to action and **one** "…" overflow menu (hover-menu). Secondary actions move into the overflow. |
| **Card** | Only where elevation means something. Lists and tables sit on `--panel` with hairline dividers, not cards inside cards. Clickable cards lift on hover (`--shadow-lift`, `translateY(-1px)`). The pointer light is removed (§2.6). |
| **Table** | One style: sticky 11px uppercase header on `--header-bg`; 40px rows (36px for `table.compact`); row hover `--row-hover`; the selected row gets a 2px `--text` (ink) bar on its left, never the accent (§2.1). Numbers are right-aligned and tabular; row actions show on hover; one empty-row style. Lines between rows only, never boxes. |
| **List row** | `.list-row`: leading icon or avatar · title / subtitle · meta · trailing chevron or actions. Used for the dashboard lists, the search results, the notification centre and the chat list. |
| **Status pill** | Full radius, a tinted background (`color-mix(--st 12%)`) and coloured text. The dot is kept only on project status, where it carries meaning. |
| **Document chip** | `.doc-chip[data-kind]`: a 3px stripe in the kind's colour plus the number in Geist Mono. Used everywhere a document is referenced. |
| **Stat tile** | Figure (hero size, tabular), label, an optional delta or meter. No gradient edge. The markup stays `.stat-card` with the figure in `.value`, so motion.js's count-up (L154/157) keeps finding it. The count-up runs only the first time per session (see 2.6). |
| **Empty state** | A muted Phosphor icon (no gradient tile), one line of text and one button. Short variants for the inside of panels. |
| **Menu and hover-menu** | `--panel`, radius 12, `--shadow-menu`, 4px padding, 30px items, keyboard hints on the right. The hovered item is `--row-hover`, never accent-filled. It grows from its trigger (`transform-origin` at the trigger). |
| **Popovers** | All follow the Menu and Tooltip spec:<br>• the date picker `.app-calendar` (controls.js:152; keep its `.cal-*` classes in styles.css);<br>• the context menu `.context-menu` (`showContextMenu`, sidebar.js:558); drop its `--accent !important` hover at styles.css:830;<br>• the calc bubble `.calc-bubble` (calc-input.js:102), a tooltip look at the tooltip z;<br>• the ⌘K `.search-overlay` / `.search-panel` (sidebar.js:365–450), an `md` sheet with `.list-row` results, opened instantly. |
| **Drop box** | `.drop-box` (file-drop.js): the Empty state with a dashed hairline, outlined in ink while a file is dragged over. |
| **Tooltip** | One shared tooltip in `hover-menu.js`, replacing the system `title` delay where we draw our own: 125ms in, instant between neighbours. |
| **Sheet** (`.modal`, merged with `dialogs.js`) | One look. `dialogs.js` drops its injected `<style>` and adds the same `.sheet` classes, keeping `app-dialog-backdrop` (§1.4 open-sheet guards). Sizes are `sm` 420, `md` 560, `lg` 760 and `full`; header, body and footer are fixed; the footer has Cancel on the left and the primary action on the right. Backdrop: `rgba(17,19,22,.32)`. |
| **Toast** | One stack at the bottom centre: sync, undo, saved and errors. `notify.js` cards (announcements and sign requests) are the same style, kept bottom-right. The web shim's `.web-file-ready` link (built by a Swift string, styles.css:1574) is restyled in CSS only to match: bottom centre, `--accent-fill` / `--on-accent`, above `env(safe-area-inset-bottom)`. |
| **Inspector** (new, for editors) | `.inspector`: a right-hand column of `.form-card` sections with collapsible headers. The doc-bar always shows an Inspector toggle button; ⌥⌘I also toggles it in the Mac app only, because browsers keep ⌥⌘I for DevTools. The choice is remembered. |

### 2.6 Motion system (animate skill)
- **Tokens.** These are added, and `--ease`, `--spring` and `--spring-momentum` are kept by name with new values:
  - `--spring`: a gentle overshoot for things that should feel alive (switch thumbs, ticks, badges, toasts arriving, a sheet opening, menus popping). Take the curve from easings.co (an "out-back" with a small overshoot) rather than inventing one; the animate skill keeps bounce around 0.1–0.3;
  - `--spring-momentum`: a stronger overshoot, kept for drags that carry a flick;
  - `--ease`: an alias of `--ease-out`;
  - `--ease-out: cubic-bezier(0.23, 1, 0.32, 1)`;
  - `--ease-in-out: cubic-bezier(0.77, 0, 0.175, 1)`;
  - `--ease-drawer: cubic-bezier(0.32, 0.72, 0, 1)`;
  - `--dur-press: 100ms`, `--dur-fast: 150ms`, `--dur-menu: 180ms`, `--dur-move: 220ms`, `--dur-sheet: 220ms`.
- **Rules for each kind of motion:**

| What | Frequency | Purpose | Spec |
|---|---|---|---|
| Sidebar selection marker | tens a day | spatial | Slides at `--dur-move` with `--ease-in-out`. Keep it. |
| ⌘K, ⌘J, keyboard shortcuts | 100+ a day | n/a | **No animation.** Instant open and close. |
| Button and row press | many | feedback | `scale(.97)` or a tint, 100ms. |
| Hover on clickable cards | many | feedback | `translateY(-1px)` and a shadow, 150ms, under `(hover:hover) and (pointer:fine)`. |
| Menus, selects, date popover | tens | spatial | `opacity 0→1` and `scale(.97→1)` from the trigger, 180ms ease-out. Closing is instant. |
| Tooltips | tens | feedback | 125ms fade. Instant when moving to a neighbour. |
| Sheets and dialogs | occasional | prevent jarring | Backdrop fade plus `translateY(8px)→0`, `scale(.98→1)`, 220ms ease-out. **Close instantly** (Batch 225). |
| Tab underline and segmented thumb | tens | state | Transform slide, 220ms ease-in-out. |
| Inspector and sidebar collapse | occasional | spatial | `transform: translateX`, 240ms `--ease-drawer`. Content reflows without animation, which avoids animating width. |
| Toasts | occasional | state | Rise 8px and fade in, 200ms ease-out. Leave by the same path. Transitions, not keyframes. |
| Count-up on stat tiles | once a session | delight | 500ms ease-out, the first time per session only. Built in motion.js `countNew`, using its existing `store` (`sessionStorage motion.count.<page>`); today it counts on every load. dashboard.js's own `countUp` (L34) is removed. bridge.js needs no change, because countUp sets `data-count-final` itself. |
| Rows added or removed (undo, stock lines) | occasional | state | Height is acceptable here: an accordion-style 180ms. The existing `.undo-changed` glow becomes a 600ms `--accent-soft` background that fades out. |
| Drag and reorder | gesture | physical | `drag-reorder.js` settles with `--spring-momentum` at 260ms. |
| Living details | ambient | state / delight | Allowed: the calendar "now" dot pulses, an Active project's status dot breathes, a pending sign request glows softly, and spinners and typing dots keep moving. Use opacity and transform only, and keep it calm (HANDOFF §3: nothing busy, nothing that flashes). |

- **Remove:**
  - **the pointer light:** styles.css L474–477 and motion.js L163–185 (`SPOT`, `placeSpot`, `--mx`/`--my`). **Keep `manual.css .mx-frame.spot`**, which is the manual's spotlight, a different feature with the same class name;
  - **every keyframe entrance that plays on page load.** It shows after Batch 226's snapshot lifts, because CSS animations cause no DOM changes and so don't hold the snapshot. Find them with `grep -nE "animation:[^;]*(rise|Rise|-in\b|In\b|fade|up\b|pop|Pop)" css/*.css`. Known:
    - calendar.css 15/88/149/215;
    - workers.css 10/39/58/66/256;
    - marketing.css 138/163/174/187/231;
    - manual.css 40;
    - assistant.css 19/33/281;
    - stock.css 29/89/142/164/194;
    - tasks.css 48/87/166/234/250, with the `animate` class at tasks.js:195;
    - styles.css 1758 (`.dash-enter`, dashboard.js:327/420), 2023/2043 (`pjIn`), 2129 (`dhIn`), 2174/2195/2197 (`df-group`), 2333 (`.ov-bracket`);
    - settings.css 33.
    Keep only the ones a user action starts after load: the Projects filter-change stagger, rows added or removed, toasts and sheets;
  - every remaining `transition: all`. Grep for it and name the properties instead.
- **motion.js segmented thumb.** `placeInk` stops copying the active button's colours inline (delete motion.js L96–105). The thumb's `--panel` fill, hairline and `--shadow-control` live on `.seg-ink` in CSS, so it follows a Light/Dark switch. motion.js stays the one place that moves `.tab-ink`, `.seg-ink` and `.nav-ink`.
- **No reduced-motion variants** (§1.3). The animate and design-taste skills ask for them, but the user has overruled that for this app. Don't write `prefers-reduced-motion` rules or `matchMedia('(prefers-reduced-motion…')` checks. `js/motion.js` remains the one place that wires motion up in JS.

### 2.7 One shared UI kit: `js/ui-kit.js` (new; the only new JS file)
It replaces the many separate versions of the same parts.

- **Loading.** It must be a `<script>` tag on every page, straight after `dialogs.js`. The scripts that `sidebar.js` injects (motion, notify, assistant) load async, too late for page code that runs at load.
- **What it provides:**

| Function | What it does | What it replaces |
|---|---|---|
| `appTabs(el, {param:'tab', onChange, map})` | One tab controller. Sets `.active` and `aria-selected` only (motion.js moves the ink), handles ←/→, reads `?tab=`, and writes it **with `history.replaceState` only**. pushState or a `location` change would add Back steps and set off the Batch 226 snapshot. The optional `map` turns old tab names into new ones. | The ~10 copies in accounts.js:492, employees.js:348, manpower-costs.js:139, marketing.js:34, project-detail.js:744, team.js:32, stock.js:191 (`.on`), workers.js:702 (`.on`) and the tasks `.tk-seg` |
| `appToast(text, {action, kind})` | The one toast stack. | `.sync-toast` (bridge.js:751, project-detail.js:941), `.undo-toast` (undo.js:142, multiply.js:205), `.st-toast` (settings-ui.js:86), `.sk-toast`, `.wk-toast`, and the inline confirmations `#ai-saved` (settings-ai.js:50–54) and `#gs-copied` (google-sheets.js:74–77) |
| `appSheet({title, size, body, actions, onClose})` | The sheet used by JS-built modals. Its backdrop **always carries `modal-backdrop`** and is hidden with `.hidden` or removed on close (§1.4 guards). Static `.modal-backdrop` markup keeps working, restyled through the same CSS. | `#wk-sheet` and the JS-built modals (announcements, custom-item, delivery-rates, doc-select, line-discount, multiply, project-delete, `quickAdd`, promotions, quotation-import, quotation-split, sign-request, task-editor). Each moves over in its page's batch. |
| `statTile({label, value, sub, href, tone, meter})` | The stat-tile builder. It emits `.stat-card` with `.value` and `.label`. | Dashboard `statCard()` and the hand-written copies in accounts.js:92, employees.js:81, marketing.js:44, plus `.pd-stats`, `.wk-stats`, `.sk-stats`, `.tk-stats`, `.mo-kpis`, `.cr-stats`, `.you-stats` |
| `searchField(input, {slash:true})` | The search field: icon, Esc clears it, `/` focuses it. | `.pj-search`, `.tk-search`, `.wk-search`, `.sk-search` ×4, `.st-search`, `.mx-search` ×2 and the plain `#search-box` inputs |
| `periodPicker(el, {presets})` | The period choice. | accounts `#period-select`, marketing `#mo-range`, `#cr-period` |
| `pageActions(header, {primary, overflow:[…]})` | Builds the `[···] [Primary]` pair from §3.3 with hover-menu. | `.header-actions` |

- **The automatic label-to-icon swap** in `icons.js` is limited to `.row-actions` and table cells. Elsewhere, buttons keep their words, with an optional leading icon. This ends the "half words, half icons" toolbars.
- **Labels:** one wording per action across the app.
  - "New X" for creating, never "Add X" or "Create X". The sheet's confirm button repeats it: "New Worker" → "Add Worker" becomes "Create" → "Create Worker".
  - "Export to Excel…".
  - "Start from Standard Terms".
  - Filters are chips: "Archived", "Former", "Paid off".
  - Modals say "Cancel", not "Close", unless nothing can be cancelled.
  - The destructive button in a sheet footer always uses `class="left"`.

---

## 3. Information architecture and navigation

### 3.1 Merges
**How a page is merged.** The old file becomes a redirect stub that maps its query and hash, the same way `sites.html` and `user.html` already do. That way every link keeps working:

- Swift (`Database+Records.swift` search results, `Assistant.swift` "open" proposals, the `main.swift` Go menu);
- notifications;
- the Google Sheet;
- the manual.

| New page | Replaces | Why |
|---|---|---|
| **Schedule** (`calendar.html`, title "Schedule") | `calendar.html` and `tasks.html` | They show the same `TeamTask` data. Each has its own hero, its own search, its own segmented pill (`.tk-seg` against `.segmented`) and its own keyboard hints. One page has views **List · Week · Month**: List is today's Tasks, with My / Everyone's / Done as filter chips. It also has one quick-add bar (from Tasks: "Send revised BOQ to Mr. Law tomorrow 3pm @Tom") and one right rail (mini month, chosen day, this week). `tasks.html` becomes a redirect to `calendar.html?view=list`, forwarding `?task=`. The two scripts can't share a page as they are; see §4.5 "Script scope". |
| **Team** (`team.html`) | `team.html` and `chat.html` | Both are about the same people. Tabs: **Chat · People · Signatures · Announcements**. Chat is the default and shows an unread badge. `chat.html` becomes a redirect to **`team.html?tab=chat`, forwarding `?with=`**, because team.js:351 reads only `?tab=` and never the hash. Point team.js:94's chat link straight at `team.html?tab=chat&with=`. Load `chat.js` (already wrapped in its own scope) and `team.js` together, and check for id clashes first. |
| **Assistant** (no sidebar item) | the `assistant.html` sidebar entry | It is already on every page as the floating chat (⌘J). The floating launcher button is replaced by an "Ask" button beside Search at the top of the sidebar, which also shows ⌘J. The floating panel's expand button opens `assistant.html`, the full page with chat history, which stays. |
| **User Manual** (no sidebar item) | the sidebar entry | It moves into the user menu (below). The Mac Help menu already opens it with ⇧⌘? (main.swift:1482). `manual.html` stays. |

Not merged, on purpose: Accounting and Marketing are different jobs. Admin keeps Company Documents and Employees (payroll feeds Accounting), and Workers stays its own page (Batch 216 moved it out of Admin on purpose).

### 3.2 Sidebar (rebuilt in `js/sidebar.js`)
- **Items:** 15 → 11, in three groups.
  - **Work:** Home (`index.html`, renamed from Dashboard), Schedule, Projects, Team.
  - **Operations:** Stock, Costs, Clients & Sites, Workers.
  - **Company:** Accounting, Marketing, Admin.
  - Group headings are sentence case at 12px in tertiary ink (not uppercase), with 20px between groups.
- **Top of the sidebar:**
  - brand row (logo and wordmark);
  - a single row holding `[Search ⌘K]` and `[Ask ⌘J]`, both 32px and sharing one rounded track.
- **Items:**
  - 32px rows, 18px Phosphor icon, label;
  - the right side carries a count badge where it means something (Team unread, Schedule due today, Stock returns due);
  - the selected item gets the `--panel` fill, a hairline and an accent icon; the sliding `.nav-ink` stays, without the gradient bar.
- **Foot: one user button.** It opens a menu (hover-menu) with:
  - You;
  - Settings ⌘,;
  - Appearance, as an inline segmented control: System · Light · Dark. It calls `api.settings.update({appearance})` like `js/settings.js` L625 (`api.settings.update({ appearance: b.dataset.value })`).
    - **It is hidden under `html.web`**, both here and in Settings › You. The browser follows the device (`prefers-color-scheme`), and `settings:update` deliberately leaves the Mac's look alone for web users (NativeBridge+Routes.swift:1106–1109);
  - User Manual;
  - Edit Sidebar Order (moved here from the pencil on the first heading);
  - Sign Out (web only).

  The share-status line `.sidebar-team` sits above it as a quiet line of small text.
- **Collapse: already built in Batch 240.** Keep its behaviour and restyle it:
  - an icon rail that opens out over the page after resting the pointer about half a second, and folds back when the pointer leaves;
  - keyboard focus opens it;
  - the chat unread dot shows while folded;
  - the Settings › You switch "Fold the sidebar to icons", on by default.
  Changes:
  - restyle the rail at 60px with Phosphor icons and tooltips;
  - below 1100px the rail is used whatever the setting;
  - phones use the drawer (§3.4);
  - update `js/manual.js`'s default crop, which assumes 224px.
- **Order editing** keeps working, under a **new key, `localStorage['sidebar.order.v2']`**. The old `sidebar.order` is ignored once, so everyone sees the new Work / Operations / Company groups. Two things in `orderedNavItems()` (sidebar.js:105–117) would otherwise go wrong:
  - a new item with no known predecessor, such as `section:Work`, is put at the end;
  - a saved order would keep Projects under Operations.
  Unknown keys in a saved order are still dropped.
- **Go menu** (main.swift:1441–1454):
  - rename "Dashboard" to "Home" (R2b);
  - replace Calendar/Tasks with "Schedule" (R7) and Chat/Team with "Team" (R8);
  - keep the Assistant, Workers and Marketing entries;
  - **⌘1–7 stay on the same pages** (§1.8). `NAV_ITEMS.key` and the tooltips are unchanged, even though the sidebar order differs from the numbers;
- **Print.** One shared `@media print` in styles.css hides the phone top bar, drawer scrim, rail toggle, toast stack, tooltip and `.as-float` (R2d). Drop `.as-launcher` from assistant.css:210. The manual's print rule (manual.css:251–261) still hides `#sidebar`.

### 3.3 Page anatomy (every page)
```
┌ sidebar ┐┌───────────────────────────────────────────────┐
│         ││ Breadcrumb › Trail (nested pages only)        │
│         ││ Title                    [··· ] [ Primary ◉ ] │  ← .page-header
│         ││ one-line context (counts, status, date)       │
│         ││ ───────────────────────────────────────────── │
│         ││ Tabs (if any)                                  │  ← .tabs
│         ││ [Search /] [chips…]          [Sort ▾] [▦ ☰]   │  ← .toolbar
│         ││ content: table / list / grid / split view     │
└─────────┘└───────────────────────────────────────────────┘
```
- **One primary action per view**, and it is the only accent-filled button on screen.
  - When a page has tabs, the primary action follows the tab. For example, on Project › Quotations it reads "New Quotation".
  - Everything secondary goes into the `···` overflow: Import, Export, Show in Finder, Customise, Print and so on.
- **Long subtitles become short.** For example, Team's 25-word subtitle becomes "5 people · 2 to sign". Context lines are facts, not explanations; explanations go in tooltips or the manual.
- **Back buttons.** `addBackButton()` (sidebar.js L607) becomes breadcrumbs inside `.page-header` on nested pages: the project page and the editors.

### 3.4 Small screens (Mac window, iPad, phone)
Today no page has `<meta name="viewport">`; only `WebServer.loginPage()` does. Phones get a zoomed-out desktop page, so none of the existing `max-width` rules ever apply there. Use the mobile-native skill for this section.

- **Setup.** In R2d, add `<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">` to every page. Scope the shell and phone rules to `body[data-page]`, so the web login (which has no sidebar) isn't affected.
- **Breakpoints**, as tokens in a comment block and used everywhere. These replace today's scattered 1320/1280/1180/1100/1000/900/760/700 rules:

| Name | Width | Sidebar | Layout |
|---|---|---|---|
| wide | ≥ 1440px | full | full |
| desktop | 1100–1439px | full | full |
| compact | 768–1099px (iPad, narrow Mac window) | 60px icon rail | inspectors and right rails become toggled overlays, not columns |
| phone | < 768px | see below | single column |

- **Phone shell:**
  - The sidebar becomes a drawer. A 52px top bar shows ☰, the page title, and the page's primary action as an icon button with a label in its tooltip.
  - The drawer slides in from the left (`transform`, 240ms `--ease-drawer`, over a scrim). It closes on scrim tap, Esc, or an edge swipe.
  - The floating Assistant opens full screen.
  - Toasts sit above the safe area (`env(safe-area-inset-bottom)`).
- **Phone layout rules** (each page batch writes its own `< 768px` rules in the same CSS block as the desktop layout, never "it'll probably reflow"):
  - grids and splits collapse to one column at 16px gutters;
  - the toolbar wraps to search on its own line, with chips in a horizontal scroll-snap row;
  - sort and view go into `···`;
  - **tables** become stacked "card rows": the first column becomes the title, two or three key columns become a meta line, and the rest go on the detail page. Use a `data-label` attribute on each cell plus CSS, not a second renderer. Wide working grids (BOQ and quotation line tables, the delivery schedule, stock bulk entry) instead scroll sideways inside their card with a sticky first column, because editing them cell by cell needs the grid;
  - **sheets** open full screen as a bottom-anchored panel (100dvh, sticky header and footer); menus open as action sheets from the bottom;
  - **split views** (Team chat, Workers roster/profile, Settings list/pane, Clients & Sites) become list → detail with a back control in the top bar;
  - **editors:** the canvas comes first. The inspector becomes a "Details" button in the doc-bar that opens it as a full-screen sheet; Export stays the visible primary.
- **Touch** (`@media (pointer: coarse)`):
  - hit targets at least 44px, so rows grow to 48px;
  - row hover actions are always visible as a `···` button, because there is no hover;
  - `:hover` effects are gated behind `(hover: hover)`;
  - `-webkit-tap-highlight-color: transparent` plus a pressed tint;
  - inputs at least 16px font size, so iOS doesn't zoom;
  - `100dvh`, never `100vh`.
- **Mac app:** the window's minimum width is 1000px (`window.minSize`, main.swift:1229). The compact rail (below 1100px) therefore shows only when the window is made narrow, and the phone rules never fire in the Mac app. No Swift change is needed.

---

## 4. Page-by-page specs

These rules hold on every page:

- The page uses §3.3 anatomy and §2.5 components. Per-page look-alikes are deleted and the JS moved onto the shared classes. Examples: `.sk-head`, `.sk-tabs`, `.sk-search`, `.sk-menu`, `.tk-seg`, `.tk-search`, `.cal-round` and `.chat-tool` SVGs.
- Inline `<style>` blocks move into `styles.css`, or into the page's CSS file where one exists.
- Hand-drawn SVGs in the HTML become `icon()` calls.
- Explanatory subtitles shrink to a fact line; the explanation moves into a tooltip (ⓘ) or the manual.

### 4.1 Home (`index.html`, formerly Dashboard)
- **Header.** "Good morning, William" plus the date (`7 Oct 2026` style).
  - The overflow menu holds Customise and Announce.
  - The primary action is a **"New…" split button**. It replaces the 10-tile Quick Actions panel, joining those tiles into one menu: Project, Quotation, BOQ, Delivery Note, Invoice, Inspection, Letter, Client, Site, Lead.
  - Each menu item shows its document colour as a stripe.
  - ⌘N stays New Project everywhere (File menu, main.swift:1394; manual-content.js:489). The New… menu has no shortcut of its own: Tab to it, then press Return or ↓.
  - The Quick Actions widget stays available in the widget tray for anyone who wants it, but is off by default. Add `data-default-off` to the `quick` panel, and have `widgets.js` `apply()` hide it when the saved `dashboard.layout` has never mentioned it. Existing saved layouts keep their order.
- **Today strip.** Up to 4 stat tiles in one row:
  - due today;
  - quotations awaiting reply;
  - unpaid invoices (amount in mono);
  - returns due.
  Each tile is clickable and opens the filtered list. These replace `.stat-grid`.
- **Main grid** (still `widgets.js`, so moving and resizing stay). The grid has 4 quarter columns and flows row by row (`COLS = 4`, widgets.js:49), so there are no true columns. The default spans are:
  - **¾:** My tasks, and My active and recent projects (list rows with a status pill and doc chips);
  - **¼ beside them:** Needs attention (expiring documents, sign requests), Unpaid invoices, and Recent activity (team), with My recent documents merged into it;
  - deliveries move into Recent activity.
  - Panel titles are sentence case with an "All ›" link on the right.
  - Empty panels collapse to one muted line, not a big box.
- **The announcement bar** becomes a thin banner under the header (`--accent-soft` background, dismiss ×).
- **The backup reminder** becomes the same banner style.
- **Row actions.** The three bare 16px icon buttons on each "awaiting reply" row become the shared row hover actions: the most likely action as a labelled button, the rest under `···`.
- **The `#pick-project-modal`** is restyled as an `sm` sheet. A "New Quotation" made from Home still asks which project.

### 4.2 Projects (`projects.html`)
- **Header:** "Projects" with "12 active · 4 quoting", primary **New Project**, overflow (Projects Overview, Export).
- **Toolbar:**
  - search `/`;
  - status filter chips with counts (All, Planning, Quotation, Active, On Hold, Completed, Archived), each with its status dot;
  - a Scaffolding / Crane chip pair (the job type, already in the data);
  - Sort menu;
  - view toggle Cards · List · Overview (the third icon today, `ov-*`).
- **Cards:**
  - a 3-column grid at ≥1440px, 2 below;
  - each card: project number (mono) and status pill in the top row; name (15/600); client · site; a row of doc chips with counts (BOQ 2, Qt 3, DN 5, Inv 1) that open the project on that tab; and a footer with the creator's avatar and "worked on 2d ago";
  - hover lifts the card;
  - the status shows as a 3px top edge in the status colour (no tinted card fill).
- **List:** the shared table, with the same columns. Rows are 40px; the number column is mono.
- **Keep:** the search `/`, Esc, ↑/↓ and Return; the saved choices; the "rise in one after another" stagger only when filters change, with no animation on page load.
- **The view buttons** (30×26px today) become a segmented control with icon and label.
- **The New Project sheet** (`md`) loses its inline styles. Its quick New Client and New Site (`quickAdd()`, projects.js:594–631):
  - **R4** restyles them as a stacked second-level `.sheet`, with the backdrop dimmed once rather than twice, and keeps `QUICK_FIELDS` for now.
  - **R9b** moves the client/site sheet out of `party-page.js` into `openPartySheet(kind) → Promise<newId|null>`. It builds its own markup and does not set `window.appRefresh`, read `#show-archived` or touch `location.search`; all three would break projects.html (party-page.js:56, :60, :80). It must also return the new record (today save() discards it, L121). Then projects.js drops `QUICK_FIELDS` and `quickAdd()`, removing the Batch 188 duplication.

### 4.3 Project page (`project-detail.html`)
- **Header**, as a double-bezel hero panel:
  - breadcrumbs "Projects › 26219";
  - project number (mono, click to copy) and a status pill that is also a dropdown to change status;
  - the name (h1);
  - client and site as links;
  - job type chip; created by and last activity.
  - The faint scaffold-grid texture stays, but the status-tinted wash and the pointer light go.
- **Actions:** one primary **New ▾**, which follows the open tab ("New Quotation" on Quotations) and whose menu lists every kind. The overflow holds Edit Details, Show in Finder, Customise Overview and Delete Project.
  - This replaces the 8 separate per-tab primary buttons and the header's Edit Details and Show in Finder.
  - Per-tab extras go into the tab's toolbar overflow: Import… (quotations), Export Register (inspections), Show Done (tasks).
- **Tabs.** Ten tabs are too many for one row. Group them as **Overview · Documents · Files · Site · History**.
  - **Documents** has a secondary segmented control, BOQ · Quotations · Delivery Notes · Invoices · Letters, with counts and doc dots, remembered per project.
  - **Files** = Drawings & Documents.
  - **Site** = Inspections · Tasks.
  - **One old-to-new map.** It serves `?tab=`, the `#drawings`/`#documents` hash (project-detail.js:753) and the saved `sessionStorage['project-tab-<number>']` (L746, 755):
    - boq, quotations, delivery, invoices and letters go to Documents plus that segment;
    - files goes to Files;
    - inspections and tasks go to Site plus that segment;
    - history stays History;
    - an unknown name falls back to Overview.
  - `?new=1&tab=<old>` opens the matching item of New ▾.
- **Document lists:**
  - one table style with a doc-chip number column, status pill, client-facing date, amount (mono, right) and created by;
  - row hover shows actions (Open, Export, ···);
  - series brackets (`.doc-bracket`) become an indented group with a hairline rail on its left.
- **Overview:** stat strip (contract value, invoiced, paid, outstanding) and recent activity. `widgets.js` customise is kept. (`doc-flow` is not here; it is the editors' document chain, §4.4.)
  - The hero's 6 count tiles and the Overview's own Quick Actions are removed. Today there are three ways into every tab; the counts now live on the tabs and segments, and **New ▾** covers creating.
  - There are 13 primary buttons on the page today. After this there is one at a time.
  - New ▾ items click the kept hidden `new-*-btn`, `record-inspection-btn` and `upload-*-btn` ids, so `?new=1` and `runQuickAction` still work (§1.4).
  - Row actions on document lists come from `documentRowActions` (document-actions.js:79–94, called at project-detail.js:102, 179, 221, 260). Restyle them there.
- **File rows** (`renderFileList`, around project-detail.js:299) carry 6 buttons today. They become the shared file row:
  - type icon, name, linked-to chips, description (click to edit), date;
  - on hover: **Open**, plus `···` holding Locate File, Rename, Replace…, Archive and Delete.
  - The same row and CSS are used by Admin › Company Documents and Workers › Documents. Admin's `renderDocTable` already says it copies this one, so share the renderer.

### 4.4 Document workspace (Quotation, BOQ, Delivery Note, Invoice, Letter)
These are five editors with one shared shell, `.doc-shell`. The main structural unification of this plan.
```
┌ breadcrumbs: Projects › 26219 › Qt26219-002 ───────────────────────────┐
│ ▍Qt26219-002  Draft ▾  Kai Tak Sports Park · HK$ 1,284,500   [···][Export ▾] │ ← sticky .doc-bar (stripe in the kind's colour)
├──────────────────────────────────────────────┬─────────────────────────┤
│ Items · Delivery Schedule                    │ Inspector (⌥⌘I / button)│
│                                              │ ▾ Letter (To, Attn, Ref)│
│  section cards → line table → + Add ▾        │ ▾ Dates & pricing       │
│                                              │ ▾ Linked BOQ / split    │
│                                              │ ▾ Key terms (summary)   │
│                                              │ ▾ Drawings              │
│                                              │ ▾ Printing (page, lang.)│
└──────────────────────────────────────────────┴─────────────────────────┘
```
- **`.doc-bar`** (sticky):
  - a stripe in the kind's colour, the number (mono, click to copy), and a status pill with a dropdown.
    - The dropdown is the editor's existing `#status-select`, with its options unchanged: Draft / Issued / Cancelled; invoices add Partially Paid / Paid / Overdue; BOQ has only Draft / Issued.
    - The `lockStatusOptions` rules stay: Cancelled is final, and an issued invoice can't go back to Draft;
  - client and subject;
  - the live total (mono);
  - actions: **Export ▾** is the primary, a split button whose main part is PDF (with preview, as today) and whose menu holds Word, Excel where it exists, and Print…;
  - **···** holds Locate File, Duplicate…, Split…, Import…, Revert Split and Delete…, with Delete last and in red, below a separator;
  - **each menu item clicks the existing hidden button by id** and copies its `disabled` state (§1.4), so ⌘P (`#print-btn`) and document-actions.js keep working;
  - today the quotation toolbar shows 6 buttons inline: Export, Print, Locate, Duplicate, Split, Delete;
  - **a quiet second row** holds the linked-document chain (`.doc-flow`, from `flowHTML()` in doc-authors.js, using `api.authors.chain`: BOQ › Quotation › Split off › Delivery Notes › Invoices, with the current document not a link; BOQ, Qt, DN and Inv only), plus "Created by · Last worked on" (`metaHTML`);
  - it sits at `top: var(--titlebar-safe)` in the Mac app (§1.11).
- **Canvas tabs:**
  - **Items:** add materials, line items and sections;
  - **Delivery Schedule:** quotation, BOQ and DN where they exist.
  - **Preview stays the modal** opened by Export ▾ › PDF (`docPreview.pdf`, doc-preview.js:190), restyled as an `lg` sheet with the double-bezel paper tray. doc-preview.js has no inline mode. An inline Preview tab is skipped; add one only if the user asks.
- **Items canvas:**
  - each section is a card with its header row (title, subtotal in mono, `···` menu);
  - the line table inside uses the shared table at 36px rows, with in-cell editing kept and arrow-key spreadsheet movement (`controls.js`);
  - the "Add Materials" picker becomes a sticky command row at the top of the canvas: search box, Price list ▾ and Category ▾ (today an icon with a dot), with `item-picker.js` results in a popover;
  - at the bottom sits one **+ Add ▾** button: Section, Priced Section, Delivery Charge, Standard Manpower Rates, Note, Buy-back Offer, Custom Item. This replaces the wide `+ Add Section` plus the row of 5 buttons;
  - the Line Items "☰" menu stays as the section's `···` menu, holding Sort and Multiply.
- **Inspector:**
  - collapsible `.form-card` sections, holding today's Letter, Dates & Pricing, BOQ link, Key Terms and Drawings cards;
  - field labels sit above the fields, and pencil "value rows" are used where a value is rarely edited;
  - Key Terms shows a 3-line summary with "Edit terms…", which opens `terms-table.js` in an `lg` sheet;
  - crane quotations hide what doesn't apply, as today: no BOQ link, the letter layout;
  - the hire period and buy-back fields live in "Dates & pricing";
  - **▾ Printing:**
    - Page (`#orientation-select`; quotation and BOQ; still hidden on crane jobs, quotation-editor.js:101);
    - Items in (`#language-select` via doc-language.js; quotation, BOQ and DN);
    - the ids are unchanged;
  - **Signed copy** (`#signed-bar`, signed-copy.js; quotation-editor.js:419–432) is an inspector section on the quotation, like `dn-signed` on the DN;
  - `#director-bar` and `#imported-bar` become quiet notes at the top of the inspector.
- **Per editor:**
  - **BOQ:**
    - "Make Quotation" stays as a secondary button next to Export;
    - the Pricing, Mark up and Structure `.details-bar` moves into the inspector, along with the charges and rates sections;
    - Drawings sit in the same place as on the quotation (inspector).
  - **DN:**
    - it gets the shared primary, Export (it has none today);
    - "Import from Quotation" moves into `···`. The bar is gone because the choice was already made in New Delivery Note;
    - the signed copy drop zone (`dn-signed.js`) goes in the inspector.
  - **Invoice:**
    - it gets Export as primary;
    - payment terms (the 7-row Terms box) and the "SAY … ONLY" line go in the inspector;
    - the payment row under the totals becomes an inspector section, "Payments", listing the payments with a **Record Payment** button. It writes the same `payment-*` fields.
  - **Letter:**
    - the canvas is the A4 "paper" (`#paper`, EB Garamond kept, because it is a document);
    - the formatting toolbar (`#rt-toolbar`, `.rt-btn`) uses the shared `icon-btn` and a segmented control for alignment;
    - fields and attachments go in the inspector. Annexures (`.annex-*`, letter-attachments.js) keep their drag handle and ↑/↓;
    - add Locate File to `···` so it matches the other editors. Keep `#delete-btn` as the id; only its position changes.
  - **Shared CSS:** the four copies of `.boq-grid`, `.qty-input` (60px against 70px), `.totals-box` and `.header-fields` (3 against 4 columns) become one shared set of rules in styles.css.
  - **`letters.html`** (all letters, reached from Promotions and the letter editor) becomes the shared list layout: breadcrumbs "Projects › All letters", toolbar search and a project filter, primary New Letter.
- **Sheets** used by editors move to the unified `.sheet`: Split (keep Batch 201's layout), Import, Duplicate, Multiply, line discount, delivery rates, custom-item edit and the sub-project pick (quotation-editor.js:253). Their sizes are set by `sm`, `md` or `lg` only.
  - `multiply.js`, `line-discount.js` and `delivery-rates.js` are shared with the BOQ, DN, Invoice and Settings pages. Converting them in R5a changes those pages too, so check them in R5a's screenshots.
- **The editors' `.toolbar` becomes `.doc-bar`** in R5a (quotation) and R6a/R6b (the rest). Until then their old bar keeps its layout (§2.5 Toolbar).

### 4.5 Schedule (`calendar.html`, replacing Tasks and Calendar)
- **Header:** "Schedule", today's date plus "3 due today · 1 overdue". Primary **New ▾** (Task, Event). Overflow: Week starts on… (today a select in the toolbar), Show done.
- **Script scope.** `tasks.js` and `calendar.js` can't both load as they are:
  - both declare top-level `let view` and `const ICON/esc/pad/addDays/dayOf/ymd`. The second script then throws a SyntaxError and never runs;
  - both declare `function load/render/setView`, so the second silently overwrites the first.
  The fix:
  - **wrap `tasks.js` in an IIFE**, as `chat.js` already is, and export only `window.scheduleList = { load, render }`;
  - **`calendar.js` owns the single `window.appRefresh`** (it reloads both views) **and the single keydown handler**;
  - remove tasks.js's own keydown handler (L550–556) and its `appRefresh` (L488);
  - calendar.js's URL setup (L630) also reads `?view=list` and `?task=`, next to `day` and `event`;
  - fold assistant.js's `PAGE_SUGGESTIONS.tasks` into `calendar`.
- **Keys:**
  - N focuses the quick-add bar; ⇧N opens the full task sheet;
  - E makes a new event; T jumps to today;
  - L, W and M switch views; / searches;
  - ←/→ and PageUp/PageDown move the period;
  - in List view ↑/↓ move between rows, not days. Calendar's ±1/±7 arrow handler (calendar.js:588–598) runs only in Week and Month.
- **Class names.** Leave the date picker's `.cal-*` rules in styles.css alone, because `controls.js` uses them on every page. Rename the Schedule page's colliding classes (`.cal-week`, `.cal-day`, `.cal-peek`) to `.sch-*`.
- **Quick-add bar** under the header, from Tasks: the natural-language input with chips preview. It is kept in full, because it is fast.
- **Toolbar:** ‹ Today › · segmented **List · Week · Month** (L, W, M) · filter chips (Mine, Everyone, a team, a project ▾) · search.
- **List view:** today's `tasks.js` list grouped by Overdue / Today / This week / Later / No date. Rows have a check circle, title, project doc-chip, person avatar and due time. Done items collapse under "Done (12)".
- **Week and month:** today's `calendar.js` grid with drag to schedule kept. The colours are event and person colours on steel; the "now" line uses the accent.
- **Right rail** (collapsible): mini month, the chosen day's agenda, and the Tasks progress ring (kept as the only chart; flat accent stroke, no gradient).
- **Keyboard hints** (`.cal-keys`) move into a `?` popover; they are no longer a permanent strip.
- **One task row.** Tasks are drawn three ways today: `.tk-card`, `taskRowHTML` (task-editor.js:225) and calendar items. There is now one row:
  - `window.taskRowHTML` in `task-editor.js`, **restyled in place in R3** (the first batch that shows it);
  - it keeps its name, its `<tr class="task-row">` output and `wireTaskRows()`, so Home (dashboard.js:404, R3) and Project › Site › Tasks (project-work.js:155, R4) pick it up with no change;
  - R7 makes the Schedule list use it too, dropping `.tk-card`.
- **Calendar kind colours.** The 9 hard-coded colours (`KINDS` in `calendar.js`) become tokens. Document events use the `--doc-*` colours, and person events use the person colour.
- **Deep link:** `tasks.html?task=` redirects to `calendar.html?view=list&task=`, which opens the task sheet.

### 4.6 Team (`team.html`, replacing Chat and Team) and the Assistant
- **Tabs:** Chat (badge) · People · Signatures (count) · Announcements. Primary: on Chat none; on Announcements **Announce**.
- **Chat:**
  - a split view with conversations on the left (avatar in person colour, last line, time, unread dot) and the thread on the right;
  - the composer is one rounded field holding emoji, GIF and attach `icon-btn`s, and the send button is the accent circle;
  - message bubbles: mine in `--accent-soft` with ink text, theirs on `--panel` with a hairline.
- **People:**
  - the person list (avatar, role, devices, permissions such as `canSign`) as list rows, with details in a right pane;
  - the team tree with drag-to-team is kept, with Open All / Close All moved into `···`;
  - the 💬 emoji becomes a chat icon;
  - the empty text "Enter your name on the User page" becomes "Add your name in Settings › You".
- **Header:** the chat's h1, which sits inside its side column today, moves to the normal page header.
- **Chat badge** (R8). sidebar.js puts `#chat-badge` on the `team` item (today L231 on `chat`). The "conversation open" check at L639 becomes `data-page === 'team'` with the Chat tab active, so an open thread isn't counted as unread.
- **Signatures:** incoming, outgoing and recent as list rows with doc chips and Sign / Chop buttons.
- **Assistant:**
  - restyle `css/assistant.css` to the system; proposal cards use the card plus doc-chip style;
  - the floating panel uses `--panel`, radius 16 and `--shadow-sheet`;
  - remove the gradient launcher (§3.2); the stop button becomes an accent circle with a ring, as today but with no gradient.

### 4.7 Operations
- **Stock:**
  - the header becomes a fact line: "4,812 pieces in the yard · 1,920 on hire";
  - primary **Record Stock ▾** (its menu as today); Export in the overflow;
  - stat tiles (yard, on hire, rented, owned) with the existing yard/hire bar restyled flat;
  - shared `.tabs`: Stock · Returns (due badge) · On Hire · Rented · History;
  - the Returns due banner uses the banner style;
  - the bulk entry sheet keeps typing, paste from Excel and quick fill, restyled as an `lg` sheet with the shared table;
  - **Record Stock no longer asks for the kind twice.** Today it asks once in the `#sk-record-menu` and again in the sheet's 6-way segmented control. The primary now opens the sheet directly, with the kind as the sheet's segmented control. On the Rented tab the primary becomes "Rent In…", which opens the same sheet preset to that kind. `.sk-menu` is deleted;
  - one search per tab through `searchField`. The `.sk-row` grid rows look like the shared table.
- **Costs** (`price-lists.html`):
  - tabs Materials · Manpower Rates;
  - the materials table uses the shared style with a category group header row;
  - the price list picker becomes segmented chips;
  - primary **New Item**; the ☰ menu (category, import, export) becomes the toolbar's `···`;
  - **Unit Rates PDF** is a main task buried today under ☰ › Export rates › PDF. It becomes the primary on the Manpower Rates tab; the `#rates-bar` selection mode stays.
- **Clients & Sites:**
  - primary **New Client ▾** (menu: New Site);
  - the overflow holds Import from Excel… and Export to Excel…;
  - "Show archived" becomes a filter chip;
  - view toggle List · Connections (the `conn-board` line view);
  - the long how-to subtitle becomes a fact line, with the how-to in a ⓘ tooltip;
  - client and site detail (`party-page.js`) uses the shared value rows;
  - **make the hidden gestures visible:**
    - a client's dot shows a grab cursor and a "Drag onto a site to start a project" tooltip;
    - the line menu leads with "New Project Here";
    - each site row's `···` has "New Project for…".
  - Import and Export stop asking "which list?". The `···` lists Import Clients…, Import Sites…, Export Clients…, Export Sites… directly.
- **Workers:**
  - keep Batch 216's structure (summary, tiles filtering the roster, roster cards, profile tabs Agreement · Details · Documents, the live "paper" preview);
  - restyle it to the system and drop its own token block (`workers.css` L41);
  - roster cards become list rows when the window is narrow;
  - **one header, not two heroes:** the page header carries New Worker, and the profile's head carries the worker's one "Next step" primary;
  - Sign & Chop and Preview PDF become secondary buttons;
  - `#wk-sheet` moves onto `appSheet` (`lg`, with the paper preview on the side), and its button reads "Create Worker";
  - `.wk-toast` moves onto `appToast`; `.wk-tabs` and `.wk-seg` move onto the shared tabs and segmented control.

### 4.8 Company
- **Accounting** (`accounts.html`):
  - stat strip (receivable, received this month, expenses this month, net);
  - tabs: Receivables · Payments · Expenses · Liabilities · Reports, where Reports holds a segmented control By Project / By Month. This takes the 6 tabs down to 5;
  - primary follows the tab (Record Payment, New Expense);
  - the inline `<style>` moves out, and `table.money` (copied into admin.html) becomes a shared table variant;
  - each tab gets its own toolbar instead of one whose controls appear and disappear;
  - the period choice uses `periodPicker`;
  - `?tab=liabilities` keeps working;
  - the Liability sheet (with its payments) ends with "Done".
- **Marketing:**
  - tabs Overview · Follow-ups · Leads · References · Report · Promotions;
  - primary follows the tab (New Lead, New Promotion);
  - charts in `marketing-overview.js` use the `--viz-*` tokens, retuned to the steel palette, with the accent for the main series;
  - the Promotions letter preview keeps EB Garamond, because it is a document.
- **Admin:**
  - tabs Company Documents · Employees;
  - Company Documents: a Needs Attention list at the top, then the documents table, primary **Upload…**;
  - Employees: stat strip, table, primary **New Employee**, overflow Record Pay… and Export to Excel;
  - "Show former employees" becomes a chip;
  - **Upload, files first.** Upload… opens the file chooser first, then a small sheet asks the category and expiry for the chosen files. Today a category and expiry must be picked in the heading bar before choosing files;
  - keep the legacy `data-tab="workers"` and `#admin-tab-workers` ids;
  - move the tabs onto `appTabs`;
  - the 29-line `<style>`, including its redefinition of `.small-note`, goes.

### 4.9 Settings, Manual, launch and web screens
- **Settings** (`settings.html`, already a list plus value rows from Batch 165):
  - restyle it: the section list with Phosphor icons, the value rows formalised as `.value-row`;
  - real switches for on/off settings;
  - the autosave "Saved" toast (`#st-toast`, settings-ui.js:86–102) moves onto `appToast`, and so do `#ai-saved` (settings-ai.js:50–54) and `#gs-copied`/`#gs-copied2` (google-sheets.js:74–77, which also has an em dash);
  - delete the never-shown `#save-row` / `#saved-note` (settings.html:580) with its handlers (settings.js:245–247, 467, 604);
  - AI Import (settings-ai.js) and Google Sheets (google-sheets.js, `.gs-*`) move onto `.st-card` value rows. The Google green in `.gs-mark` (#1e8e3e) is an allowed brand hex;
  - the Appearance segmented control is shared with the user menu;
  - move the inline `<style>` out, and delete its stray duplicate `</style>` (settings.html L42–43);
  - **Share with Other Macs, Backup & Restore and Web Access** still use the old `.cloud-row` and `.backup-actions`. They move onto the `.st-card` value rows. Backup's 9 buttons become a primary **Back Up Now** plus `···` (Restore…, Show Backups, Choose Folder…, and the rest);
  - **You › "Your work"** repeats Home's panels. Replace it with one line, "Your projects, documents and activity are on Home ›";
  - keep "William's Work": it is the real default iCloud folder (Sources/Assistant.swift:1219–1220 `defaultFolder`), not the user's name. settings.html:451 and :462 stay as they are.
- **Manual:**
  - keep Batch 169's presentation layout;
  - **one search box**: the cover's search, which then sticks to the top of the rail. Remove the second one;
  - add `manual` to the sidebar's `ROOT_PAGES` so it stops getting a Back button;
  - chapter colours become the doc colours or the accent; no gradients;
  - cards use the system;
  - screenshots are retaken in R12.
- **Launch screen** (`launch.html`) and **web loading** (`js/web-loading.js`):
  - a steel canvas, the logo, "ScaffoldPro" in Geist, and a thin accent progress bar;
  - the logo still "builds itself" (Batch 58), once, and only the first time.
- **Web login** (`WebServer.loginPage()`):
  - the same look in its HTML string; it already has a viewport meta tag;
  - before sign-in only `/css/styles.css`, `/resources/fonts/` and `/icon/` can be fetched (WebServer.swift:430–431), so it can't load ui-kit.js or icons.js;
  - override the app shell (`body{height:auto; min-height:100dvh; overflow:auto}`) so the form scrolls with the phone keyboard up;
  - inputs at 16px, so iOS doesn't zoom;
  - the mark and colours inline in steel, not navy and yellow;
  - title "Sign in · ScaffoldPro";
  - centred, single column, and works at phone width.

---

## 5. Rollout: batches, in order

**Strategy: theme first, then structure.** The app updates itself from `main`, so every merged batch reaches the user.

- **R1a** retones **all pages at once**: tokens, type, the accent sweep and fixed status colours. From its merge onwards the whole app wears one theme, and there is never a week where half the pages are blue-violet. R1b and R1c finish the foundation; try to land R1a–R1c in the same session.
- **Later batches** rebuild layouts page by page on top of that. Each page batch also writes that page's phone rules (§3.4).
- **Batch size.** Batches are sized for one session each: the bigger ones are split with a letter suffix. Each split must make sense on its own, because `main` auto-updates the user's app.

**For every batch**, follow HANDOFF §2:

1. branch from the latest `main`;
2. make the change and verify it (§6);
3. add a `## Batch N` entry in `ScaffoldPro-native/README.md`, in plain words; the first is 241 (check HANDOFF.md §2 for the current number);
4. run `graphify update .`;
5. commit;
6. open a PR, then merge it at once.

Several batches can go in one session if each one is verified and merged on its own.

| # | Batch | Scope | Main files |
|---|---|---|---|
| R0 | Plan and screenshot harness | **Done** (Batch 241/242): this plan, HANDOFF pointer, and the harness. Build `tools/ui-shots/` (§6.1), with mock data rich enough to fill every page. Take "before" shots of all 26 pages in every viewport, light and dark, and keep them in the scratchpad, not git. No UI change. | `docs/redesign/PLAN.md`, `tools/ui-shots/shoot.js`, `tools/ui-shots/mock.js`, `HANDOFF.md` |
| R1a | Retone: tokens and type | §2.1 in full: every token light and dark, plus `--titlebar-safe`; status colours as fixed hex; the accent-use sweep (`--accent-text`, `--accent-fill`/`--on-accent`, ink selection, no accent menu hovers); delete the gradients, glows, h1 text gradient and the `body::before` wash. §2.2: bundle Geist and Geist Mono, add the stacks and type scale. §2.3: radii, shadows, z-scale tokens. Swift: `PageBackdropView` colours. The old-blue grep comes back empty. | `css/styles.css`, all `css/*.css` (token uses only), `resources/fonts/ui/*`, `Sources/Assistant.swift` |
| R1b | One icon family | §2.4: the Phosphor registry in `icons.js` (`ICON_PATHS`, `window.icon`, `ICONS` kept as whole svgs). Delete sidebar.js's `const ICONS` and `function icon`, and load `icons.js` before `sidebar.js` everywhere. Move `widgets.js`, `notify.js`, `settings-ui.js`, `manual.js`, `workers.js`, `stock.js`, `calendar.js`, `dashboard.js` and `team.js` icon sets, the 57 inline HTML svgs and the CSS data-URI icons onto it. | `js/icons.js`, `js/sidebar.js`, those JS files, every `*.html`, `css/styles.css`, `css/settings.css`, `js/vendor/PHOSPHOR-LICENSE` |
| R1c | Components, colour sweep, motion | §2.5 component CSS (button, field, segmented, switch, tabs, toolbar with no fixed height, table, list row, pill, doc chip, stat tile, empty state, menu, popovers, drop box, tooltip, toast). Hard-coded hex in CSS, inline `<style>` and JS becomes tokens. Inline `<style>` blocks move into the stylesheets, except in the editors, which move theirs in R5 and R6. §2.6 motion tokens; remove the pointer light (keeping the manual's `.spot`) and every load-time entrance keyframe; the motion.js `placeInk` fix; count-up once per session. Delete every `prefers-reduced-motion` block and JS `reduce` check, and the Reduce Transparency / Increase Contrast blocks (§1.3); restore overshoot via `--spring`. Recolour `launch.html` and `js/web-loading.js` to steel, with the logo kept. | `css/*.css`, `index`/`settings`/`admin`/`accounts`/`marketing`/`project-detail` `.html` `<style>` blocks, `js/motion.js`, `js/dashboard.js` (its countUp), `js/dialogs.js` (fallback hex only), `launch.html`, `js/web-loading.js` |
| R2a | UI kit, sheets, toasts | §2.7: new `js/ui-kit.js` and its `<script>` tag after `dialogs.js` on every page. `appSheet` and the one `.sheet` look: `dialogs.js` drops its injected `<style>` and keeps `app-dialog-backdrop`. `appToast`, with bridge sync, undo, notify and `.web-file-ready` CSS moved onto it. Optionally add `.app-dialog-backdrop:not(.leaving)` to bridge.js `busy()`. Test the Swift-called page functions and the open-sheet guards (§6.2). | `js/ui-kit.js`, every `*.html` (one tag), `js/dialogs.js`, `js/bridge.js`, `js/undo.js`, `js/notify.js`, `css/styles.css` |
| R2b | Sidebar | §3.2: groups, Search/Ask row, user menu (You, Settings, Appearance hidden on web, Manual, Edit Order, Sign Out), restyled Batch 240 fold rail, badges, `sidebar.order.v2`. The Assistant's floating launcher is removed. `icons.js` auto-swap is limited to rows. Go menu: Dashboard becomes Home. **Tasks and Chat keep their sidebar entries until R7 and R8**, so nothing becomes unreachable in between. | `js/sidebar.js`, `js/assistant.js` (launcher), `css/assistant.css`, `js/icons.js`, `js/manual.js` (L119 crop), `main.swift` (Go menu title) |
| R2c | Page headers | §3.3: `pageActions`, plus breadcrumbs replacing `addBackButton()` on nested pages, on every page that uses `.page-header` or a plain h1. Fact-line subtitles. Page `<title>`s become "Projects · ScaffoldPro", with assistant.js:1143's regex changed to `/\s*[—·]\s*ScaffoldPro$/` in the same batch. | every `*.html`, `js/sidebar.js`, the 7 JS files that set `document.title`, `js/assistant.js` |
| R2d | Small screens shell | §3.4: viewport meta on every page; breakpoint tokens; compact rail; phone top bar and drawer; full-screen sheets and bottom action-sheet menus; touch rules; table → card-row CSS (`data-label`); the shared `@media print`. | every `*.html`, `css/styles.css`, `js/sidebar.js`, `js/ui-kit.js`, `js/hover-menu.js` |
| R3 | Home | §4.1. Also restyles `taskRowHTML` in place. | `index.html`, `js/dashboard.js`, `js/widgets.js`, `js/announcements.js`, `js/task-editor.js` |
| R4 | Projects and the project page | §4.2–4.3: tab map, New ▾ over the kept ids, shared file row, `documentRowActions`, `quickAdd` restyled as a stacked sheet. | `projects.html`, `project-detail.html`, `js/projects.js`, `js/project-detail.js`, `js/project-work.js`, `js/project-delete.js`, `js/document-actions.js`, `js/doc-select.js`, `js/doc-authors.js` (project line only) |
| R5a | Document shell on Quotation | §4.4: `.doc-shell`, sticky `.doc-bar` (status, chain row, Export ▾, `···` over the hidden ids), canvas tabs. `doc-authors.js` builds `.doc-bar` only on pages with `.doc-shell`; the other four editors keep `.doc-hero` until R6. Move the 144-line `<style>` out. The shared sheets (multiply, line discount, delivery rates) move onto `.sheet`; check BOQ, DN, Invoice and Settings too. | `quotation-editor.html`, `js/quotation-editor.js`, `js/doc-authors.js`, `js/document-actions.js`, `js/multiply.js`, `js/line-discount.js`, `js/delivery-rates.js`, `js/quotation-split.js`, `js/quotation-import.js`, `js/doc-preview.js` (sheet look) |
| R5b | Inspector and Add on Quotation | §4.4: the inspector with Letter, Dates & pricing, Linked BOQ / split, Key terms (terms sheet), Drawings, Printing and Signed copy; ⌥⌘I plus the toggle button; the `+ Add ▾` menu; the picker command row. | `quotation-editor.html`, `js/quotation-editor.js`, `js/custom-item.js`, `js/item-picker.js`, `js/terms-table.js`, `js/delivery-schedule.js`, `js/linked-drawings.js`, `js/signed-copy.js`, `js/doc-language.js` |
| R6a | BOQ and Delivery Note | §4.4 per editor | `boq-editor.html`, `delivery-note-editor.html`, `js/boq-editor.js`, `js/delivery-note-editor.js`, `js/dn-signed.js` |
| R6b | Invoice, Letter and Letters | §4.4 per editor. Then remove the `.doc-hero` path from `doc-authors.js` and its CSS (styles.css ~L2119–2207). | `invoice-editor.html`, `letter-editor.html`, `letters.html`, `js/invoice-editor.js`, `js/letter-editor.js`, `js/rich-editor.js`, `js/letter-attachments.js`, `js/letters.js`, `js/doc-authors.js`, `css/styles.css` |
| R7 | Schedule (Tasks merged into Calendar) | §4.5: script scope, keys, `.sch-*` names, `taskRowHTML` in the list. `tasks.html` becomes a redirect stub forwarding `?task=`. Sidebar and Go menu: Calendar and Tasks become Schedule (ROOT_PAGES too). Fold `PAGE_SUGGESTIONS.tasks` into `calendar`. | `calendar.html`, `tasks.html`, `css/calendar.css`, `css/tasks.css` (merged in), `js/calendar.js`, `js/tasks.js`, `js/task-editor.js`, `js/sidebar.js`, `js/assistant.js`, `main.swift` (Go menu L1450) |
| R8 | Team (Chat merged into Team) and the Assistant | §4.6. `chat.html` becomes a redirect to `team.html?tab=chat`, forwarding `?with=`. The chat badge and its open-thread check move to Team. Sidebar and Go menu: Chat and Team become Team. | `team.html`, `chat.html`, `css/chat.css`, `js/team.js`, `js/chat.js`, `js/sign-request.js`, `js/sidebar.js`, `assistant.html`, `css/assistant.css`, `js/assistant.js`, `main.swift` (Go menu L1450) |
| R9a | Stock and Costs | §4.7 | `stock.html`, `css/stock.css`, `js/stock.js`, `price-lists.html`, `js/price-lists.js`, `js/manpower-costs.js` |
| R9b | Clients & Sites and Workers | §4.7, plus the `openPartySheet` extraction, with projects.js moved onto it | `clients.html`, `js/connections.js`, `js/party-page.js`, `projects.html`, `js/projects.js`, `workers.html`, `css/workers.css`, `js/workers.js` |
| R10a | Accounting and Admin | §4.8. Admin documents use R4's shared file row. | `accounts.html`, `js/accounts.js`, `admin.html`, `js/admin.js`, `js/employees.js` |
| R10b | Marketing | §4.8 | `marketing.html`, `css/marketing.css`, `js/marketing*.js`, `js/promotions.js` |
| R11 | Settings, Manual and web login | §4.9. Delete the dead `js/user.js`. | `settings.html`, `css/settings.css`, `js/settings*.js`, `js/settings-ai.js`, `js/google-sheets.js`, `manual.html`, `css/manual.css`, `js/manual.js`, `Sources/WebServer.swift` (`loginPage()` HTML string only) |
| R12 | Consistency pass and manual shots | Grep audit (§6.3). Worst-case data pass with the break-ui skill on every list and table. Animation review (`review-animations` skill) across the app. Retake all 32 manual shots and update their `points` and `view` crops in `js/manual-content.js`, including the stale `admin` "+ New Worker" mark and the `user` shot. Add shots for Workers, Schedule and the Assistant. Update HANDOFF.md §1 "Key places" and §3 "Look" to describe the new system. | `resources/manual/*.jpg`, `js/manual-shots.js`, `js/manual-content.js`, `HANDOFF.md` |

**If a session runs out mid-batch,** push the branch without merging. Write in HANDOFF.md which batch is half done and what is left.

---

## 6. Verification

### 6.1 The screenshot harness (built in R0, kept in the repo)
`tools/ui-shots/shoot.js` is a Node script using the globally installed Playwright and `/opt/pw-browsers/chromium-1194/chrome-linux/chrome`.

- **Mock data.** It loads each `ScaffoldPro-native/<page>.html` over `file://` with a mock of the native bridge (the HANDOFF §4.2 pattern). The replies come from `tools/ui-shots/mock.js`, which holds realistic data for every route a page calls:
  - about 12 projects in every status;
  - quotations with sections, custom items and terms;
  - BOQs, DNs, invoices, letters;
  - tasks and events this week;
  - chat messages;
  - stock with movements;
  - workers at each stage;
  - accounts;
  - leads;
  - people with person colours.
  Find the routes by grepping `callNative('` and `api.` in each page's JS. Have the mock record unknown routes, so gaps show up.
- **Each run, for each page:**
  - light and dark;
  - four viewports:
    - 1440×900;
    - 1000×760, which shows the compact rail;
    - iPad 820×1180, touch;
    - phone 390×844, `isMobile`, `hasTouch`, deviceScaleFactor 3.
    The iPad and phone runs set `window.__scaffoldProWeb = true` and `html.web`, as `WebServer.serveStatic` does. The two Mac viewports don't, so `--titlebar-safe` is 38px there; overlay a 38px translucent band on those shots to show the drag strip;
  - one pass with Reduce Motion emulated, to prove the app ignores it: animations still play;
  - `pageerror` and console errors fail the run;
  - output PNGs go to a folder given on the command line: the scratchpad, never git.
- **Options:** `--page` and `--tab` (clicks a tab after load) for a single shot.
- **R12** adds a `--manual` mode. It recreates the manual-shot capture: 1440 wide, records marked elements' boxes into `js/manual-shots.js`, and writes `resources/manual/<id>.jpg`.

### 6.2 For every batch
1. Run the harness for the pages the batch touched, light and dark. **Read the screenshots**, and compare them against the "before" set and against §2 and §4. Fix anything off before committing.
2. Drive the changed interactions in Playwright and assert on `window.__calls` (what would go to Swift):
   - open and close every sheet and menu with mouse and keyboard;
   - Esc and Return;
   - ↑/↓ in lists;
   - ⌘Z with no reload: check that `location.reload` is never called by stubbing it to throw;
   - for merged pages, check that the old URL's redirect lands on the right view, and check every deep link in §1.4 that the batch touches;
   - **open-sheet guards:** with an `appSheet` or dialog open, the `busy()` test (bridge.js:743) returns true and ⌘Z does nothing;
   - **Swift-called functions** (R2a, and any batch touching `dialogs.js` or `sidebar.js`):
     - `appUpdatePrompt('9.9')` shows a sheet and resolves 'now' or 'later';
     - `appDialog({message, buttons})` resolves the chosen value;
     - `appNavigate`, `appUndo` and `openGlobalSearch` exist and run.
3. Run with `page.emulateMedia({ reducedMotion: 'reduce' })` and check that the animations still play exactly as without it (§1.3). R12 also greps `prefers-reduced-motion\|prefers-reduced-transparency\|prefers-contrast` across `css/*.css js/*.js *.html`, which must come back empty.
4. **Swift:** a tree-sitter parse of every changed `.swift` file reports 0 errors (HANDOFF §4.1). Also watch the listed compile traps.
5. **Contrast:** a small `node` check of each text/background token pair in light and dark: AA 4.5:1 for body text, 3:1 for large text and UI strokes.
   - `--on-accent` on `--accent-fill`, and `--accent-text` on `--panel` and `--content`, must pass.
   - Every status colour must differ from `--accent` by at least 15° of hue or 15 L* (§2.1).
6. **The README entry says plainly** what was checked in Chromium and what wasn't (WebKit on a Mac, the PDFs). Ask the user to look at the pages on their Mac after updating.

### 6.3 Final consistency audit (R12): all must come back empty, or be explained in the README
- `grep -nE "#[0-9a-fA-F]{3,6}\b" css/*.css *.html js/*.js`. Allowed only in the token blocks, the doc/status/person palettes, chart tokens, the brand mark, and the PDF/Word export code (`docx-export.js`, `paragraph-format.js` for documents).
- `grep -n "transition: all\|ease-in[^-]\|scale(0)\|location.reload\|linear-gradient(135deg"`.
- `grep -nE "58, *102, *240|109, *141, *255|#6d8dff|--grad-accent|--accent-glow|--accent-2"`: the old blue-violet. Only the Completed status `#3a66f0` may remain.
- `grep -nE "animation:[^;]*(rise|Rise|-in\b|In\b|fade|up\b|pop|Pop)" css/*.css`: only the state-driven entrances allowed in §2.6.
- `grep -n "data:image/svg" css/*.css`: none, because the icons come from the registry.
- `grep -n "<style" *.html` — only `launch.html` and the redirect stubs may keep inline styles.
- `grep -n "<svg" *.html js/*.js` outside `icons.js`, the brand mark, charts (`marketing-overview.js`, the Schedule ring) and document previews.
- `grep -n "—" *.html js/*.js` in visible UI strings: replace with a full stop, a comma or a colon. Code comments and the PDF/Word text are exempt. Page `<title>`s are "Projects · ScaffoldPro" (R2c). Swift-made strings keep "—" (§1.10).
- Every page: one primary (accent-filled) button visible at a time; header actions ≤ 2 (primary + `···`); one tabs style; one toolbar order.
- **Phone pass,** at 390×844 on every page and tab:
  - no sideways scroll on the page, except inside the wide working grids;
  - nothing hidden under the top bar or the safe areas;
  - every action reachable without hover;
  - sheets full screen.
  Report on how the pages look on the user's iPhone and iPad once they have tried it.

### 6.4 What can't be checked here
- WebKit rendering on macOS: Geist rendering, backdrop blur and font smoothing.
- The Swift build.
- Real data volumes.

State this in each reply to the user, and ask them to update and look. The PDFs are untouched by this plan; it changes no document layout code.

---

## 7. Out of scope (say so if asked)
- **PDF and Word output.** The letterhead, BQ sheet, documents and `docx-export.js` keep their own document styling. This plan is the app's interface only.
- **The app icon and logo** (`icon/`, `BRAND_MARK`). They stay as they are.
- **The Google Sheet's layout and colours** (`resources/google-sheets/`). They keep the same status, doc and person colours, so nothing there changes.
- **A user-chosen accent colour, density or font-size setting.** Add one later only if the user asks.

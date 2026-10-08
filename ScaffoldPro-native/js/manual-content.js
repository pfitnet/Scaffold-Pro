'use strict';

// The User Manual's content (drawn by js/manual.js). One idea per block,
// as few words as will do: the pictures carry the rest.
//
// A chapter: { id, part, title, tag (one line), color, icon, keys, blocks }.
// Blocks:
//   shot   a screenshot with numbered points: { shot, view: [x, y, w, h] in %
//          of the picture (default: without the app's sidebar), points:
//          [[mark number in js/manual-shots.js, 'Label', 'short hint'], …] }
//   flow   steps joined by arrows: 'kind|Title|detail > kind|Title || kind|Alt'
//   steps  numbered steps: [['icon', 'Title', 'short text'], …]
//   cards  tiles: [['icon', 'Title', 'short text'], …]
//   keys   shortcut tiles: [['{⌘K}', 'What it does'], …]
//   tip    one sentence worth remembering (tone: tip, warn)
//   states the life of a document
//   code   a number taken apart
//   example a sentence with its parts picked out
//   swatches colours and what they mean
//   qa     questions and answers
// Text: **bold**, {⌘K} keys, [Button] buttons, [*Button] main buttons.

window.MANUAL_CONTENT = [
  // ------------------------------------------------------------ Getting started
  {
    id: 'welcome', part: 'Getting started', title: 'How it fits together', color: '#6d5cff', icon: 'grid',
    tag: 'Every job, from the first enquiry to the paid invoice, in one place.',
    blocks: [
      { type: 'cards', title: 'The sidebar, in four groups', cards: [
        ['home', 'Overview', 'Dashboard · Calendar · Tasks'],
        ['people', 'Team', 'Chat · Team'],
        ['layers', 'Operations', 'Costs · Clients & Sites · Projects · Stock'],
        ['building', 'Company', 'Accounting · Marketing · Admin · Settings'],
      ] },
      { type: 'flow', title: 'Documents grow from one another', chain: 'boq|BOQ|Materials and rates|BQ26212-001 > qt|Quotation|The priced offer|Qt26212-001 > dn|Delivery Note|What goes to site|DN26212-001 > inv|Invoice|What’s billed|H26212-001',
        note: 'Linked documents share a number. Each kind keeps its own colour everywhere.' },
      { type: 'states', title: 'Every document has a status' },
    ],
  },
  {
    id: 'basics', title: 'Everyday controls', color: '#6d5cff', icon: 'bolt',
    tag: 'The same on every page. Learn them once.',
    blocks: [
      { type: 'keys', keys: [
        ['{⌘K}', 'Search everything'], ['{⌘Z}  {⇧⌘Z}', 'Undo · Redo'], ['{⌘[}  {⌘]}', 'Back · Forward'],
        ['{↑} {↓} {←} {→}', 'Move between boxes'], ['{Return}', 'Save, next'], ['{Esc}', 'Cancel, put back'],
      ] },
      { type: 'cards', title: 'Small things that save time', cards: [
        ['calendar', 'Dates', 'Type **24/9/26**, **24 Sep** or **today**. Shown as 24 Sep 2026.'],
        ['hash', 'Sums in boxes', 'Type **14+28** or **2 x 7**. The answer is saved.'],
        ['pointer', 'Hover menus', 'Lists and icons open on hover. A tick marks the choice.'],
        ['drag', 'Drag and drop', 'Files from Finder. ⋮⋮ to reorder lines.'],
        ['sort', 'Sorting', 'Click a column: up, down, then back to normal.'],
        ['eye', 'Preview first', 'Every export opens a preview. {⌘S} saves it.'],
      ] },
      { type: 'tip', icon: 'check', text: 'Everything saves by itself — even what you were typing when you quit.' },
      { type: 'tip', icon: 'drag', text: 'Put the sidebar in your own order: press the pencil by **Overview**, drag the tabs, then **Done**.' },
    ],
  },
  {
    id: 'workflow', title: 'Start to finish', color: '#6d5cff', icon: 'route',
    tag: 'From enquiry to money in the bank, in four moves.',
    blocks: [
      { type: 'flow', step: '1', title: 'Set up', chain: 'client|Client & Site|Who and where > project|New Project|Number, name, site > grey|Drawings|Drop them in' },
      { type: 'flow', step: '2', title: 'Price it', chain: 'boq|BOQ|Materials, markup > qt|Quotation|Linked to the BOQ > team|Send to Sign|A director signs > qt|Export & Issue|Preview, save, send' },
      { type: 'flow', step: '3', title: 'Win it', chain: 'client|Client signs|Upload their copy > project|Project → Active|One click > qt|Delivery Schedule|What goes when' },
      { type: 'flow', step: '4', title: 'Deliver and bill', chain: 'dn|Delivery Note|Signed copy books stock out > inv|Invoice|From the notes > money|Payment|Recorded > money|Accounting|Received, owed' },
      { type: 'lanes', title: 'Who usually does what', lanes: [
        ['Sales', 'client|Lead > project|Project > boq|BOQ > qt|Quotation'],
        ['Director', 'team|Review > team|Sign & Chop'],
        ['Site', 'qt|Schedule > dn|Delivery Notes > grey|Inspections'],
        ['Accounts', 'inv|Invoices > money|Payments > money|Accounting'],
      ] },
    ],
  },

  // ------------------------------------------------------------ Overview
  {
    id: 'dashboard', part: 'Overview', title: 'Dashboard', color: '#3a66f0', icon: 'home', keys: '{⌘1}',
    tag: 'Your day at a glance: what’s waiting, what’s owed, what’s next.',
    blocks: [
      { type: 'shot', shot: 'dashboard', points: [
        [2, 'Today', 'What needs you now'], [5, 'Number tiles', 'Each opens its source'],
        [6, 'Quick Actions', 'Start anything in one click'], [3, 'Announce', 'A message to everyone'], [4, 'Customise', 'Arrange the panels'],
      ] },
      { type: 'cards', title: 'The panels', cards: [
        ['check', 'My Tasks', 'Tick to finish.'],
        ['doc', 'Awaiting reply', 'Upload the client’s signed copy, or × if not needed.'],
        ['receipt', 'Unpaid invoices', 'What’s owed, and what’s late.'],
        ['bell', 'Needs attention', 'Expiring documents. Backup reminders.'],
      ] },
      { type: 'steps', title: 'Make it yours', steps: [
        ['grid', 'Customise', 'Opens the widget tray.'],
        ['drag', 'Drag a panel', 'By its bar, to move it.'],
        ['resize', 'Drag its edge', '¼, ½, ¾ or full width.'],
        ['trash', 'Drop in the tray', 'To remove it. [Reset Layout] undoes all.'],
      ] },
    ],
  },
  {
    id: 'calendar', title: 'Calendar', color: '#3a66f0', icon: 'calendar',
    tag: 'Everything with a date — and your schedule: meetings, site visits, deliveries, payments due.',
    blocks: [
      { type: 'shot', shot: 'calendar', points: [
        [1, '‹ Today ›', 'A week or month at a time'], [2, 'Week · Month', 'And which day weeks start'],
        [3, 'Filters', '⌥-click shows only that kind'], [4, 'The week', 'Drag down an hour column for an event'],
        [5, 'Mini month', 'Dots mark busy days'], [6, 'The chosen day', 'Then the next 14 days'],
      ] },
      { type: 'flow', title: 'Scheduling an event', chain: 'grey|Press at 10:00|On the day > grey|Drag to 12:30|Snaps to quarter hours > team|Name it|For a person, a team or anyone' },
      { type: 'keys', keys: [['{←} {→}', 'A day'], ['{↑} {↓}', 'A week'], ['{T}', 'Today'], ['{W}  {M}', 'Week · Month'], ['{N}', 'New task'], ['{E}', 'New event']] },
      { type: 'tip', icon: 'pointer', text: 'Rest on anything for its details. Click to open it — or, for an event, to change it.' },
    ],
  },
  {
    id: 'tasks', title: 'Tasks', color: '#3a66f0', icon: 'check',
    tag: 'The team’s to-dos, for a person, a project and a day.',
    blocks: [
      { type: 'example', title: 'Type it the way you’d say it', parts: [
        ['Send revised BOQ to Mr. Law', ''], ['tomorrow 3pm', 'When'], ['@Tom', 'Who'], ['#26212', 'Project'], ['!high', 'Priority'],
      ], note: '{Return} adds it. [More…] opens the full form.' },
      { type: 'shot', shot: 'tasks', points: [
        [1, 'Quick add', 'As above'], [2, 'Mine · Everyone’s · Done', 'With counts'],
        [4, 'The list', 'Tick to finish · ⟳ tomorrow'], [5, 'This week', 'Click a day to filter'], [6, 'Team load', 'Who has how much'],
      ] },
      { type: 'tip', icon: 'people', text: 'A task can be **for a whole team** (e.g. Site) instead of one person: choose the team under **For**. Everyone in it sees it as theirs.' },
      { type: 'keys', keys: [['{N}', 'New task'], ['{/}', 'Search']] },
    ],
  },

  // ------------------------------------------------------------ Team
  {
    id: 'chat', part: 'Team', title: 'Chat', color: '#d07a2c', icon: 'chat',
    tag: 'Everyone, your team, or one person. Arrives in about a second.',
    blocks: [
      { type: 'shot', shot: 'chat', view: [15.6, 0, 84.4, 100], points: [
        [2, 'Messages', 'Hover to react, reply or edit'], [3, 'Write', '{Return} sends · {↑} edits · @name'],
        [4, 'Emoji', ''], [5, 'GIFs', ''], [6, 'Attach', 'A picture from the Mac'],
      ] },
    ],
  },
  {
    id: 'team', title: 'Team & signatures', color: '#d07a2c', icon: 'people',
    tag: 'Who’s who, and directors signing quotations.',
    blocks: [
      { type: 'shot', shot: 'team', view: [15.6, 0, 84.4, 62], points: [
        [1, 'Three tabs', 'People · Signatures · Announcements'], [2, 'People', 'Teams, devices, who signs'], [3, 'Announce', 'To all, a team or one'],
      ] },
      { type: 'flow', title: 'Signing a quotation', chain: 'qt|Send to Sign…|From the quotation > team|Notice|The director sees it at once > team|Review|The PDF as printed > money|Sign & Chop|Saved as a signed PDF || client|Decline|With a reason' },
      { type: 'shot', shot: 'team-signatures', view: [15.6, 0, 84.4, 48], points: [[1, 'Waiting for you', 'Who asked, and their note'], [2, 'Review', 'Then [*Sign & Chop] or [Decline]']] },
      { type: 'tip', icon: 'pen', text: 'Directors add their **signature** and the company **chop** once, on their own card.' },
    ],
  },

  // ------------------------------------------------------------ Operations
  {
    id: 'costs', part: 'Operations', title: 'Costs', color: '#3f938b', icon: 'tag', keys: '{⌘2}',
    tag: 'What materials and manpower cost, and what we charge.',
    blocks: [
      { type: 'shot', shot: 'costs', points: [
        [2, 'Price list', 'SP or SCAFOM (EUR → HK$)'], [3, 'Search', 'English or 中文'],
        [4, '☰ Rates', 'Import and export'], [5, '+ Add Item', ''], [6, 'The list', 'Drag ⋮⋮ · ★ to pin'],
      ] },
      { type: 'steps', title: 'A Unit Rates sheet for a client', steps: [
        ['menu', '☰ › Export › PDF', 'The list turns into ticks.'],
        ['check', 'Tick items', 'From either list.'],
        ['percent', 'Make Unit Rates PDF…', 'Client and markup.'],
        ['eye', 'Preview, save', 'Into Unit Rates.'],
      ] },
      { type: 'shot', shot: 'costs-manpower', points: [
        [1, 'Our rate · their rate', 'For each kind of worker'], [2, 'What’s left', 'Red when we lose money'], [3, '+ Add Provider', ''],
      ] },
    ],
  },
  {
    id: 'clients', title: 'Clients & Sites', color: '#3f938b', icon: 'building', keys: '{⌘3}',
    tag: 'Who we work for, and where. Lines show who’s been where.',
    blocks: [
      { type: 'shot', shot: 'clients', points: [
        [2, 'Clients', 'Hover to light up their sites'], [3, 'Sites', 'Click a line for its projects'],
        [1, 'Search', ''], [4, 'Excel', 'Import · export'], [6, '+ New Client', '{⇧⌘N}'], [5, '+ New Site', '{⌥⌘N}'],
      ] },
      { type: 'tip', icon: 'drag', text: '**Drag a client onto a site** to start a project for both.' },
      { type: 'tip', icon: 'percent', text: 'A client’s **Default Markup %** starts every new BOQ and quotation for them.' },
    ],
  },
  {
    id: 'projects', title: 'Projects', color: '#3f938b', icon: 'folder', keys: '{⌘4}',
    tag: 'Every job, grouped by who made it, then by client.',
    blocks: [
      { type: 'shot', shot: 'projects', points: [
        [1, 'New Project', '{⌘N}'], [2, 'Search', '{/}'], [3, 'Status', 'Filters with counts'],
        [5, 'Cards · List · Overview', ''], [7, 'A project', 'Right-click for more'],
      ] },
      { type: 'shot', title: 'Overview: every document, linked', shot: 'projects-overview', points: [
        [1, 'The project', ''], [2, 'BOQ', ''], [3, 'Quotation', 'Its subsidiary indented'], [4, 'Invoice', 'Joined to its note'],
      ] },
      { type: 'swatches', items: [['#22a35a', 'Linked', 'Kept the same'], ['#9196a3', 'Unlinked', 'Dashed'], ['#8b6cf0', 'Subsidiary', 'Violet branch']] },
      { type: 'steps', title: 'A new project', steps: [
        ['plus', 'New Project', 'The number is proposed.'],
        ['building', 'Client & site', 'Or add one on the spot.'],
        ['calendar', 'Dates', 'Optional.'],
        ['folder', 'Create', 'It gets its own folder.'],
      ] },
      { type: 'tip', tone: 'warn', icon: 'trash', text: 'Deleting a project asks you to type its name. Its folder goes to the **Trash**.' },
    ],
  },
  {
    id: 'project-page', title: 'A project’s page', color: '#3f938b', icon: 'folder-open',
    tag: 'Home for everything about one job.',
    blocks: [
      { type: 'shot', shot: 'project-page', points: [
        [1, 'Stage', 'Click one to move there'], [3, 'Edit Details', 'And delete'], [4, 'Tiles', 'Each opens its tab'],
        [5, 'Tabs', ''], [6, 'Quick Actions', ''], [7, 'Customise', 'This project, or all'],
      ] },
      { type: 'shot', title: 'Every tab works the same way', shot: 'project-quotations', points: [
        [1, '+ New', 'From the BOQ, or blank'], [2, 'A document', 'Monthly and one-time charges'], [3, 'Select', 'Export PDF · Combine'],
      ] },
      { type: 'cards', title: 'The tabs', cards: [
        ['layers', 'BOQ', 'With the total weight.', '#3f938b'], ['doc', 'Quotations', 'Monthly and one-time totals.', '#5374b8'],
        ['truck', 'Delivery Notes', 'From a quotation.', '#b0843f'], ['receipt', 'Invoices', 'From notes or a quotation.', '#5d9150'],
        ['mail', 'Letters', 'On the letterhead.', '#8a6cb0'], ['image', 'Drawings & Docs', 'Drop files in.', '#8a8d94'],
        ['shield', 'Inspections', 'Form 5. Next due in 14 days.'], ['clock', 'Tasks & History', 'Who did what, when.'],
      ] },
    ],
  },
  {
    id: 'boq', title: 'BOQ', color: '#3f938b', icon: 'layers',
    tag: 'The materials for a scaffold, with weights and rates.',
    blocks: [
      { type: 'shot', shot: 'boq-editor', view: [15.6, 16, 84.4, 52], points: [
        [2, 'Page', 'Landscape priced · portrait not'], [4, 'Make Quotation', 'Linked to this BOQ'],
        [5, 'Rental · Sale', ''], [6, 'Mark-up %', 'The client’s, offered'],
        [7, 'Add Materials', '★ pins favourites'], [9, 'Line items', 'Sums · % discount · drag'],
      ] },
      { type: 'shot', title: 'Sections, notes and terms', shot: 'boq-sections', points: [
        [1, '+ Add Section', 'Delivery, fees, manpower, notes'], [2, 'Notes', 'Printed under the sheet'],
        [3, 'Use Standard Terms', 'From Settings'], [4, 'Delivery Schedule', ''],
      ] },
      { type: 'example', title: 'Multiply quantities, for sets', parts: [['×2', 'Two sets'], ['+10%', 'Spare'], ['½', 'Half'], ['×n', 'Any']],
        note: 'Line Items ☰ › Multiply. A preview shows before and after.' },
      { type: 'tip', icon: 'resize', text: 'Too long for a page? It shrinks to fit, down to 70%.' },
    ],
  },
  {
    id: 'quotation', title: 'Quotation', color: '#5374b8', icon: 'doc',
    tag: 'The priced offer. The page used most.',
    blocks: [
      { type: 'shot', shot: 'quotation-editor', view: [15.6, 17, 84.4, 66], points: [
        [1, 'Status', 'Subsidiaries follow'], [3, 'Split…', 'Lines into a subsidiary'], [4, 'Letter', 'Re:, refs, minimum hire'],
        [5, 'Date · Pricing', ''], [6, 'Markup / Discount', 'See below'], [8, 'Send to Sign…', ''], [10, 'Line items', ''],
      ] },
      { type: 'example', title: 'One box for markup and discount', parts: [['+30%', 'Every price up'], ['-15%', 'Off the total'], ['-1000', 'Off the total']],
        note: 'Blank means neither. Delivery is never marked up.' },
      { type: 'shot', title: 'Sections, totals and key terms', shot: 'quotation-sections', points: [
        [1, '+ Add Section', ''], [2, 'Totals', 'Monthly vs one-time'], [4, 'Key Terms', 'Blank = the standard ones'],
      ] },
      { type: 'cards', title: 'Sections you can add', cards: [
        ['truck', 'Delivery Charges', 'Weighs the load, suggests the band.'],
        ['receipt', 'Priced Sections', 'Design fees… once, daily, weekly, monthly.'],
        ['people', 'Manpower Rates', 'From Costs.'],
        ['note', 'Notes', 'Small print after the total.'],
      ] },
      { type: 'flow', title: 'Linked to its BOQ', chain: 'boq|BOQ > qt|Quotation|Kept the same both ways',
        note: 'Click an item’s green link mark to unlink just that item.' },
      { type: 'flow', title: 'Split into subsidiaries', chain: 'qt|Qt26212-007 > qt|Split…|Tick lines > qt|Qt26212-007-s1|A new draft > grey|Revert|Puts it all back' },
      { type: 'flow', title: 'Import an old quotation', chain: 'grey|Import…|PDF, scan, photo, Word > qt|Read on this Mac || team|Or the free AI|When it can’t make it out > qt|Check every row|A new draft, the original kept with it',
        note: 'On the project’s **Quotations** tab. Set up the AI once in **Settings › AI Import**.' },
      { type: 'example', title: 'Crane jobs: a buy-back offer', parts: [['60%', 'Of the price'], ['6 months', 'Returned after'], ['−2% a month', 'Beyond that'], ['none after 24', 'Months']],
        note: 'On a crane quotation: **+ Add Section › Buy-back Offer** — row BO1 under “Buy Back Offer”, after the total. The standard figures are in **Settings › Quotations**.' },
      { type: 'tip', icon: 'stack', text: '**Duplicate…** copies a quotation — items, sections and delivery schedule — as a new draft, in this project or another.' },
    ],
  },
  {
    id: 'schedule', title: 'Delivery schedule', color: '#5374b8', icon: 'calendar-days',
    tag: 'What goes to site, on which day.',
    blocks: [
      { type: 'shot', shot: 'delivery-schedule', view: [15.6, 55, 84.4, 45], points: [
        [1, '+ Add Day', ''], [2, 'Export', 'For the client, or internal'], [3, 'Copy from BOQ', ''],
        [4, 'The grid', 'Days across · what’s left'],
      ] },
      { type: 'tip', icon: 'print', text: 'Printed after the quotation by itself. Internal notes never are.' },
    ],
  },
  {
    id: 'delivery-note', title: 'Delivery notes', color: '#b0843f', icon: 'truck',
    tag: 'What goes to site, by hand, with weights and no prices.',
    blocks: [
      { type: 'shot', shot: 'delivery-note', points: [
        [1, 'Import from Quotation', ''], [2, 'Date · Address', 'From the site'], [3, 'Contact', 'Printed in bold'],
        [5, 'Items', 'Quantities and weights'], [6, 'Export', 'PDF · 文A for Chinese'],
      ] },
      { type: 'flow', title: 'The signed copy', chain: 'dn|Issue it > client|Signed on site > dn|Upload Signed Copy|Books the stock out > inv|Invoice|Signed copies follow its pages' },
      { type: 'tip', tone: 'warn', icon: 'box', text: 'Stock leaves the yard when the **signed copy** is uploaded, not when the note is issued.' },
    ],
  },
  {
    id: 'invoice', title: 'Invoices & payments', color: '#5d9150', icon: 'receipt',
    tag: 'What’s billed, and what’s been paid.',
    blocks: [
      { type: 'shot', shot: 'invoice', view: [15.6, 15, 84.4, 85], points: [
        [1, 'Made from', 'Notes or a quotation'], [2, 'Date · Due', ''], [3, 'Terms', 'Follow Settings'],
        [4, 'Line items', ''], [5, 'Totals', 'Balance Due'],
      ] },
      { type: 'steps', title: 'Recording a payment', steps: [
        ['send', 'Issue it', 'Drafts can’t be paid.'],
        ['money', 'Amount, date', 'Method and reference.'],
        ['check', 'Record Payment', ''],
        ['flag', 'Status follows', 'Partly paid → Paid.'],
      ] },
      { type: 'flow', title: 'Several quotations on one invoice', chain: 'dn|Two delivery notes|From Qt…-001 and Qt…-002 > inv|One invoice|A section for each quotation' },
      { type: 'tip', icon: 'receipt', text: 'The last line spells the total out: **SAY HONG KONG DOLLARS … ONLY**.' },
      { type: 'states', invoice: true },
    ],
  },
  {
    id: 'letters', title: 'Letters', color: '#8a6cb0', icon: 'mail',
    tag: 'On the letterhead, written like a Google Doc.',
    blocks: [
      { type: 'shot', shot: 'letter', points: [
        [3, 'Details', 'The letter’s opening'], [4, 'From a client', 'Fills in the address'],
        [5, 'Toolbar', 'Styles, tables, lists'], [6, 'The page', 'Saves as you type'], [2, 'Export', ''],
      ] },
      { type: 'steps', title: 'Attachments, as annexures', steps: [
        ['clip', '+ Add Attachment…', 'PDFs or pictures.'],
        ['hash', 'Numbered', 'ANNEXURE P.01, P.02…'],
        ['sort', 'Reorder', '↑ ↓'],
        ['doc', 'In the PDF', 'A cover page for each.'],
      ] },
    ],
  },
  {
    id: 'export', title: 'Export & print', color: '#8a6cb0', icon: 'share',
    tag: 'Every document becomes a PDF or Word file the same way.',
    blocks: [
      { type: 'flow', chain: 'qt|Export|{⌘E} > grey|Preview|Zoom, check > money|Save|{⌘S} · into the project || client|Cancel|{Esc} · nothing saved' },
      { type: 'cards', cards: [
        ['layers', 'A quotation PDF', 'Its pages, subsidiaries, schedule, BOQ, drawings.'],
        ['stamp', 'Watermark', 'DRAFT or CANCELLED across every page.'],
        ['rotate', 'Page', 'Portrait letterhead or landscape sheet.'],
        ['globe', 'Language', 'English or 中文 item names.'],
        ['doc', 'Word', 'Same layout, editable.'],
        ['stack', 'Several at once', 'Select › Export PDF.'],
      ] },
      { type: 'path', title: 'Where files go', path: ['Projects', '26212', 'Quotations', '26212_Quotation_Qt26212-001.pdf'] },
    ],
  },
  {
    id: 'stock', title: 'Stock', color: '#3f938b', icon: 'box', keys: '{⌘5}',
    tag: 'In the yard, on site, rented in, and owned.',
    blocks: [
      { type: 'shot', shot: 'stock', points: [
        [1, 'Totals', ''], [2, 'Record Stock', 'Many items at once · {N}'], [3, 'Tabs', 'Returns · On Hire · Rented'],
        [5, 'Stocktake', 'Count straight into the list'], [6, 'By category', 'Click an item for more'],
      ] },
      { type: 'flow', title: 'How stock moves', chain: 'grey|Yard|Receive adds > dn|Signed note|Out to site > project|On hire > grey|Returns|All or part back' },
      { type: 'cards', cards: [
        ['rotate', 'Returns', '[*All Returned], [Part Returned…] or [Not Yet].'],
        ['building', 'Rented in', 'From other companies. Not counted as owned.'],
        ['table', 'Paste from Excel', 'Codes and quantities, many rows at once.'],
        ['check', 'Stocktake', 'Type counts. Only differences are saved.'],
      ] },
    ],
  },

  // ------------------------------------------------------------ Company
  {
    id: 'accounting', part: 'Company', title: 'Accounting', color: '#c0627a', icon: 'chart', keys: '{⌘6}',
    tag: 'Money in and out, for any period.',
    blocks: [
      { type: 'shot', shot: 'accounting', points: [
        [1, 'Period', ''], [2, 'Totals', ''], [3, 'Tabs', 'Receivables to By Month'], [5, 'Export to Excel', ''],
      ] },
      { type: 'cards', cards: [
        ['receipt', 'Expenses', 'Payroll adds Salaries & MPF itself.'],
        ['bank', 'Liabilities', 'Loans, bills, tax. Owing · Overdue · Paid off.'],
      ] },
    ],
  },
  {
    id: 'marketing', title: 'Marketing', color: '#c0627a', icon: 'megaphone',
    tag: 'Quotations turning into work, and who to chase next.',
    blocks: [
      { type: 'shot', shot: 'marketing', points: [
        [1, 'Headline figures', 'Win rate and more'], [2, 'Tabs', ''], [5, 'Month chart', 'Click a month'], [6, '+ New Lead', ''],
      ] },
      { type: 'shot', title: 'Leads', shot: 'marketing-leads', view: [15.6, 28, 84.4, 32], points: [[1, 'The board', 'New → Won'], [2, 'A lead', '[Convert to Client]']] },
      { type: 'tip', icon: 'check', text: 'An issued quotation counts as **won** only once the client has signed it (upload the signed copy) or you press **Client Agreed**.' },
      { type: 'shot', title: 'Client report', shot: 'marketing-report', points: [
        [1, 'Client', ''], [2, 'Period', ''], [3, 'Totals', 'Quoted vs accepted'], [5, 'Export Report…', 'A PDF on the letterhead'],
      ] },
      { type: 'flow', title: 'A promotion campaign', chain: 'client|Targets > letter|One letter|{Company}, {Contact} > letter|Write Letters|One each > team|Mark Sent > money|Won' },
    ],
  },
  {
    id: 'admin', title: 'Admin', color: '#c0627a', icon: 'id', keys: '{⌘7}',
    tag: 'Company papers and payroll. Site workers have their own page (Workers): details, employment agreements and certificates.',
    blocks: [
      { type: 'shot', shot: 'admin', points: [[2, 'Needs Attention', 'Expiring within 30 days'], [3, '+ New Worker', ''], [4, 'Company documents', 'With expiry dates']] },
      { type: 'shot', title: 'Employees and payroll', shot: 'admin-employees', points: [
        [1, 'Totals', 'Pay, MPF, cost'], [2, 'Record Pay…', 'One expense each'], [3, '+ New Employee', ''],
      ] },
      { type: 'tip', icon: 'shield', text: 'Files are copied in, never moved. Workers are archived, never deleted.' },
    ],
  },
  {
    id: 'settings', title: 'Settings', color: '#c0627a', icon: 'gear', keys: '{⌘,}',
    tag: 'The gear beside your name, bottom left ({⌘,}). You, the company and this Mac — each in its own section.',
    blocks: [
      { type: 'shot', shot: 'settings', points: [
        [1, 'Search', '{⌘F}'], [2, 'Sections', '{↑} {↓}'], [3, 'The value', ''], [4, 'The pencil', 'Changes just that one'], [5, 'Switches', 'Work at once'],
      ] },
      { type: 'cards', title: 'Three groups', cards: [
        ['user', 'You', 'Your name, team, colour and work.'],
        ['building', 'Company', 'Letterhead, numbering, pricing, terms for rental and for sale.'],
        ['monitor', 'This Mac & data', 'Sharing, backups, updates, AI Import.'],
      ] },
      { type: 'tip', icon: 'check', text: 'Every change saves itself. Look for **Saved** in the corner.' },
    ],
  },
  {
    id: 'user', title: 'You', color: '#c0627a', icon: 'user', keys: '{⌘0}',
    tag: 'Who you are to the rest of the team. The first section of Settings.',
    blocks: [
      { type: 'shot', shot: 'user', points: [[1, 'Your name', 'On everything you do'], [2, 'Your team', ''], [3, 'Your colour', 'On every Mac'], [4, 'Your work', '']] },
    ],
  },

  // ------------------------------------------------------------ Working together
  {
    id: 'sharing', part: 'Working together', title: 'Sharing & the web', color: '#2a8a8a', icon: 'sync',
    tag: 'Same data on every Mac, and in any browser.',
    blocks: [
      { type: 'flow', title: 'How a change travels', chain: 'team|Mac A|Saves > grey|Office network|About a second || grey|iCloud Drive|Catches up the rest > team|Mac B|“Updated with changes from …”' },
      { type: 'steps', title: 'Share with other Macs', steps: [
        ['cloud', 'Share My Data…', 'On the first Mac.'],
        ['share', 'Share the folder', 'In Finder.'],
        ['link', 'Join…', 'On each other Mac.'],
        ['check', 'Allow', 'If macOS asks.'],
      ] },
      { type: 'steps', title: 'ScaffoldPro Web, for PCs and phones', steps: [
        ['lock', 'Set a password', 'Settings › Web Access.'],
        ['globe', 'Open the address', 'e.g. office-mac.local:8642'],
        ['monitor', 'Keep the Mac on', 'ScaffoldPro open.'],
      ] },
      { type: 'tip', icon: 'globe', text: 'Away from the office? Install the free **Tailscale** app on the Mac and the device.' },
    ],
  },
  {
    id: 'google-sheets', title: 'Google Sheets', color: '#2a8a8a', icon: 'sheet',
    tag: 'A live overview of every project, kept in step both ways.',
    blocks: [
      { type: 'cards', cards: [
        ['table', 'Projects', 'Coloured cells fill in as each document goes out. Next Step in plain words.'],
        ['clock', 'Activity', 'Who did what. Type a row to add it.'],
        ['chart', 'Overview', 'The last 7 days at a glance.'],
        ['sync', 'Updates itself', 'New layouts arrive from GitHub.'],
      ] },
      { type: 'flow', title: 'Connecting it, once', chain: 'grey|Copy Script|In Settings > grey|Apps Script|Paste, save > grey|Run setup > grey|Deploy|Web app > money|Connect|URL + secret' },
      { type: 'tip', icon: 'sync', text: 'Syncs every minute, and 20 seconds after a save. If both change, the sheet wins.' },
    ],
  },
  {
    id: 'backups', title: 'Backups & updates', color: '#2a8a8a', icon: 'shield',
    tag: 'Nothing lost, always up to date.',
    blocks: [
      { type: 'cards', cards: [
        ['clock', 'Automatic', 'Twice a day. Kept 3 days.'],
        ['shield', 'Create Backup', '{⇧⌘B} · kept until you delete it.'],
        ['rotate', 'Restore', 'A safety backup is made first.'],
        ['cloud', 'iCloud copy', 'Every 15 minutes. 30 days kept.'],
        ['download', 'Updates', '[*Update Now] backs up, builds, reopens.'],
        ['bolt', 'Install', 'Double-click **Install ScaffoldPro**.'],
      ] },
      { type: 'tip', icon: 'shield', text: 'Backups you make are kept until you delete them. Automatic ones go after 3 days.' },
    ],
  },

  // ------------------------------------------------------------ Reference
  {
    id: 'shortcuts', part: 'Reference', title: 'Shortcuts', color: '#5b6b9a', icon: 'keyboard',
    tag: 'Faster than the mouse.',
    blocks: [
      { type: 'keys', title: 'Pages', keys: [
        ['{⌘1}', 'Dashboard'], ['{⌘2}', 'Costs'], ['{⌘3}', 'Clients & Sites'], ['{⌘4}', 'Projects'],
        ['{⌘5}', 'Stock'], ['{⌘6}', 'Accounting'], ['{⌘7}', 'Admin'], ['{⌘,}', 'Settings'], ['{⌘0}', 'You'],
      ] },
      { type: 'keys', title: 'Anywhere', keys: [
        ['{⌘K}', 'Search'], ['{⌘N}', 'New project'], ['{⇧⌘N}', 'New client'], ['{⌥⌘N}', 'New site'],
        ['{⌘E}', 'Export PDF'], ['{⌘P}', 'Print'], ['{⌘S}', 'Save preview'], ['{⇧⌘B}', 'Back up'],
        ['{⌘Z}', 'Undo'], ['{⇧⌘Z}', 'Redo'], ['{/}', 'Search the page'], ['{N}', 'New task'],
      ] },
    ],
  },
  {
    id: 'numbers', title: 'Numbers & colours', color: '#5b6b9a', icon: 'hash',
    tag: 'Read any document number at a glance.',
    blocks: [
      { type: 'code', parts: [['Qt', 'Kind'], ['26', 'Year'], ['212', 'Project'], ['-001', 'Document'], ['-s1', 'Subsidiary']] },
      { type: 'cards', title: 'The kinds', cards: [
        ['layers', 'BQ', 'BOQ', '#3f938b'], ['doc', 'Qt', 'Quotation', '#5374b8'], ['truck', 'DN', 'Delivery note', '#b0843f'],
        ['receipt', 'H', 'Invoice (a second: -2)', '#5d9150'], ['mail', 'L', 'Letter', '#8a6cb0'], ['megaphone', 'PL', 'Promotion letter', '#c0627a'],
      ] },
      { type: 'swatches', title: 'Documents', items: [['#3f938b', 'BOQ'], ['#5374b8', 'Quotation'], ['#b0843f', 'Delivery Note'], ['#5d9150', 'Invoice'], ['#8a6cb0', 'Letter'], ['#8a8d94', 'Files']] },
      { type: 'swatches', title: 'Projects', items: [['#8b6cf0', 'Planning'], ['#c98a14', 'Quotation'], ['#2a8a4a', 'Active'], ['#e0793a', 'On Hold'], ['#3a66f0', 'Completed']] },
    ],
  },
  {
    id: 'faq', title: 'Quick fixes', color: '#5b6b9a', icon: 'help',
    tag: 'When something isn’t right.',
    blocks: [
      { type: 'qa', items: [
        ['“File unavailable”', 'It was moved outside the app. [Find Moved File…] or [Remove Reference].'],
        ['I can’t change a document', 'It’s Issued. Set it back to Draft. Invoices: cancel, make a new one.'],
        ['Another Mac’s changes aren’t here', 'Check iCloud Drive is on and the folder downloaded.'],
        ['The update couldn’t check', 'GitHub is out of reach, or the token in Settings › Updates expired.'],
        ['The subject line changed itself', 'It follows its BOQ until you type your own.'],
        ['Wrong name as a project’s maker', 'Edit Details › Created by.'],
        ['Signed by mistake', 'Open Signed PDF › Withdraw Sign & Chop.'],
        ['Anything else just went wrong', '{⌘Z}, step by step.'],
      ] },
    ],
  },
];

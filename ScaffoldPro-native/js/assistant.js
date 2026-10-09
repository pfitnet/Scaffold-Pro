'use strict';

// The assistant: a conversation with the team's AI (Settings › AI Import).
// It looks things up itself (projects, clients, the material list, stock,
// quotations, invoices, tasks) and proposes work as cards — a quotation,
// lines for one, changes to a draft, a project, a client, a task or event —
// carried out only when the card's button is pressed (assistant:run).
// Files can be attached (button, drop or paste); the Mac reads them and the
// AI sees them too.
//
// Chats are kept on this Mac (localStorage), listed by day — a column on the
// Assistant page, a list over the floating chat — to search, rename, delete
// and go back to. A ring in the bar shows roughly how much of the AI's
// context window the chat takes; past 70%, older messages are summarised
// (assistant:summarise) and the AI is sent the summary plus the newest ones.
//
// Two places, the same chat open in both:
//   • assistant.html — the whole page;
//   • a small floating chat on every other page (the sparkle button at the
//     bottom right, or ⌘J). It sees what's on screen — the page, the
//     document open on it, the text selected and what the page shows — so
//     "check this quotation" or "what does this mean?" just works, and
//     after it changes something the page redraws in place.
//
//   window.AssistantChat.mount(element, { compact, context, onClose })

(function () {
  if (window.AssistantChat) return;
  const KEY = 'assistant.chat'; // the one conversation, before there was a history
  const CHATS_KEY = 'assistant.chats';
  const CUR_KEY = 'assistant.current';
  const SIDE_KEY = 'assistant.sideHidden';
  const MAX_CHATS = 60, MAX_MESSAGES = 400;
  const OVERHEAD = 3000, SCREEN = 2500; // tokens: the instructions; what's on screen
  const COMPACT_AT = 0.7; // of the window: older messages are summarised
  const KEEP_RAW = 4; // the newest messages are always sent word for word
  const OPEN_KEY = 'assistant.floatOpen';
  const RECT_KEY = 'assistant.floatRect';
  const listeners = new Map(); // run id → the chat showing its steps
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const money = (n) => Number(n || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const num = (n) => Number(n || 0).toLocaleString('en-US', { maximumFractionDigits: 2 });
  const MARK = '<svg viewBox="0 0 20 20" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 2.5 11.6 7.4 16.5 9 11.6 10.6 10 15.5 8.4 10.6 3.5 9 8.4 7.4z"/><path d="M15.5 13.5l.6 1.7 1.7.6-1.7.6-.6 1.7-.6-1.7-1.7-.6 1.7-.6z"/></svg>';
  const SVG = {
    plus: '<svg viewBox="0 0 20 20" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" aria-hidden="true"><path d="M10 4.5v11M4.5 10h11"/></svg>',
    clip: '<svg viewBox="0 0 20 20" width="19" height="19" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m15.5 9.5-5.6 5.6a3.5 3.5 0 0 1-5-5l6-6a2.3 2.3 0 0 1 3.3 3.3l-5.9 5.9a1.2 1.2 0 0 1-1.7-1.7l5.3-5.3"/></svg>',
    send: '<svg viewBox="0 0 20 20" width="17" height="17" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 15.5v-11M5 9l5-4.5L15 9"/></svg>',
    expand: '<svg viewBox="0 0 20 20" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M11.5 3.5h5v5M16.5 3.5 11 9M8.5 16.5h-5v-5M3.5 16.5 9 11"/></svg>',
    close: '<svg viewBox="0 0 20 20" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M5.5 5.5l9 9M14.5 5.5l-9 9"/></svg>',
    stop: '<svg viewBox="0 0 20 20" width="15" height="15" aria-hidden="true"><rect x="5.5" y="5.5" width="9" height="9" rx="2.2" fill="currentColor"/></svg>',
    history: '<svg viewBox="0 0 20 20" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3.6 10a6.4 6.4 0 1 0 1.9-4.5"/><path d="M3.3 3.6v2.6h2.6"/><path d="M10 6.6V10l2.4 1.6"/></svg>',
    sidebar: '<svg viewBox="0 0 20 20" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4" width="14" height="12" rx="2.5"/><path d="M8 4v12"/></svg>',
    pencil: '<svg viewBox="0 0 20 20" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12.8 4.2l3 3L7.5 15.5H4.5v-3z"/></svg>',
    trash: '<svg viewBox="0 0 20 20" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4.5 6h11M8 6V4.5h4V6M6 6l.7 9.5h6.6L14 6"/></svg>',
    search: '<svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" aria-hidden="true"><circle cx="9" cy="9" r="5"/><path d="m13 13 3.5 3.5"/></svg>',
  };
  const SUGGESTIONS = [
    { title: 'Quotation from a file', text: 'Make a quotation for project ', hint: 'Attach a quotation, BOQ or list, then say which project.', attach: true },
    { title: 'Quotation from a list', text: 'Make a rental quotation for project 26219 with:\n- 200 2.0m standards\n- 400 1.8m ledgers\n- delivery 2 trips', hint: 'Type the items; it finds them in the material list and prices them.' },
    { title: 'Find prices', text: 'What are the rental and sale prices of the 2.0m standard and the 1.8m ledger?' },
    { title: 'Add a task', text: 'Remind me on Friday to chase the signed quotation for 26219.' },
    { title: 'Project overview', text: 'Give me an overview of project 26219: its quotations, invoices and what’s still open.' },
    { title: 'Money owed', text: 'Which invoices are still unpaid, and how much is owed in total?' },
    { title: 'Stock', text: 'How many 2.0m standards are in the yard, and which sites have them on hire?' },
    { title: 'Change a quotation', text: 'In Qt26219-001, make the 2.0m standards 250 and remove the delivery line.' },
  ];
  // In the floating chat: about what's on screen.
  const PAGE_SUGGESTIONS = {
    'quotation-editor': ['Check this quotation for mistakes', 'Sum up this quotation', 'Add 2 trips of delivery to this quotation'],
    'boq-editor': ['Check this BOQ for missing items', 'Make a quotation from this BOQ', 'Sum up this BOQ'],
    'project-detail': ['What’s still open on this project?', 'Which invoices here are unpaid?', 'Add a task for this project'],
    'invoice-editor': ['Is this invoice paid?', 'Sum up this invoice'],
    stock: ['What’s on hire the longest?', 'Which items are running low in the yard?'],
    tasks: ['What’s overdue?', 'What’s due this week?'],
    calendar: ['What’s on this week?', 'Add an event tomorrow at 10:00'],
    default: ['What can you do?', 'Explain what’s on this page', 'Which invoices are unpaid?'],
  };

  // ---- when sent, and copying ----
  function sentAt(iso) {
    const d = iso ? new Date(iso) : null;
    if (!d || isNaN(d)) return '';
    const time = d.toLocaleTimeString('en-GB', { hour: 'numeric', minute: '2-digit', hour12: true }).replace(' ', '\u202f');
    const today = new Date();
    if (d.toDateString() === today.toDateString()) return time;
    return `${d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }).replace('Sept', 'Sep')}, ${time}`;
  }
  async function copyText(text) {
    try { await navigator.clipboard.writeText(text); return true; } catch (e) { /* the old way below */ }
    const t = document.createElement('textarea');
    t.value = text;
    t.style.cssText = 'position:fixed;opacity:0;pointer-events:none';
    document.body.appendChild(t);
    t.select();
    let ok = false;
    try { ok = document.execCommand('copy'); } catch (e) { ok = false; }
    t.remove();
    return ok;
  }
  // A message as plain text, for copying (its cards summed up).
  function plainOf(m) {
    const lines = [m.text || ''];
    for (const p of m.proposals || []) {
      lines.push(`\n${KIND_TITLE[p.type] || p.type}${p.projectNumber ? ` · ${p.projectNumber}` : ''}${p.quotationNumber ? ` · ${p.quotationNumber}` : ''}`);
      for (const it of p.items || []) lines.push(`- ${String(it.description).split('\n')[0]} — ${it.quantity} ${it.unit || ''} × ${money(it.unitPrice)}`);
    }
    for (const q of m.questions || []) lines.push(`\n${q.text}${m.answers && m.answers[q.id] ? ` — ${m.answers[q.id]}` : ''}`);
    return lines.join('\n').trim();
  }
  const COPY_ICON = '<svg viewBox="0 0 20 20" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round" aria-hidden="true"><rect x="7" y="7" width="9.5" height="9.5" rx="2"/><path d="M13 7V5.2A1.7 1.7 0 0 0 11.3 3.5H5.2A1.7 1.7 0 0 0 3.5 5.2v6.1A1.7 1.7 0 0 0 5.2 13H7"/></svg>';
  const metaHTML = (m, mi) => `<div class="as-meta">${m.at ? `<span class="as-time" title="${esc(new Date(m.at).toLocaleString('en-GB'))}">${esc(sentAt(m.at))}</span>` : ''}<button type="button" class="as-copy" data-copy="${mi}" data-no-icon title="Copy">${COPY_ICON}<span>Copy</span></button></div>`;

  // ---- the conversations, kept on this Mac and shared by both places ----
  // assistant.chats: [{ id, title, createdAt, updatedAt, messages, summary,
  // summarisedUpTo }], newest first; assistant.current: the one open.
  // An empty chat isn't listed until something is said in it.
  const newId = () => `c-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 6)}`;
  const fresh = (id) => ({ id: id || newId(), title: '', createdAt: new Date().toISOString(), messages: [] });
  function autoTitle(c) {
    const first = c.messages.find((m) => m.role === 'user' && (m.text || (m.files || []).length));
    if (!first) return 'New chat';
    const t = String(first.text || '').replace(/\s+/g, ' ').trim() || (first.files || []).map((f) => f.name).join(', ');
    return t.length > 60 ? `${t.slice(0, 57).replace(/\s+\S*$/, '')}…` : t;
  }
  function readChats() {
    try {
      const list = JSON.parse(localStorage.getItem(CHATS_KEY) || 'null');
      if (Array.isArray(list)) return list.filter((c) => c && c.id && Array.isArray(c.messages));
    } catch (e) { /* none yet */ }
    // Before there was a history: the one conversation becomes the first.
    try {
      const old = JSON.parse(localStorage.getItem(KEY) || 'null');
      if (old && Array.isArray(old.messages) && old.messages.length) {
        const c = { ...fresh(), messages: old.messages, createdAt: old.messages[0].at || new Date().toISOString() };
        c.title = autoTitle(c);
        c.updatedAt = old.messages[old.messages.length - 1].at || c.createdAt;
        localStorage.setItem(CHATS_KEY, JSON.stringify([c]));
        localStorage.setItem(CUR_KEY, c.id);
        localStorage.removeItem(KEY);
        return [c];
      }
    } catch (e) { /* not moved */ }
    return [];
  }
  function writeChats(list) {
    list.sort((a, b) => String(b.updatedAt || '').localeCompare(String(a.updatedAt || '')));
    list = list.slice(0, MAX_CHATS);
    const attempt = () => { localStorage.setItem(CHATS_KEY, JSON.stringify(list)); return true; };
    try { return attempt(); } catch (e) { /* full: make room below */ }
    // Out of room: the text of files in older chats goes first (the chats
    // stay, with the files' names), then the oldest chats.
    for (const c of list.slice(1)) for (const m of c.messages) for (const f of m.files || []) delete f.text;
    try { return attempt(); } catch (e) { /* still full */ }
    while (list.length > 1) { list.pop(); try { return attempt(); } catch (e) { /* keep going */ } }
    return false;
  }
  const currentId = () => { try { return localStorage.getItem(CUR_KEY) || ''; } catch (e) { return ''; } };
  const setCurrentId = (id) => { try { localStorage.setItem(CUR_KEY, id); } catch (e) { /* not kept */ } };
  // The chat open now.
  function load() {
    const list = readChats();
    const id = currentId();
    return list.find((c) => c.id === id) || fresh(id || undefined);
  }
  function save(chat) {
    // Very long chats: the oldest messages go (the summary keeps their gist).
    if (chat.messages.length > MAX_MESSAGES) {
      const cut = chat.messages.length - MAX_MESSAGES;
      chat.messages.splice(0, cut);
      chat.summarisedUpTo = Math.max(0, (chat.summarisedUpTo || 0) - cut);
    }
    const list = readChats().filter((c) => c.id !== chat.id);
    if (chat.messages.length) {
      if (!chat.title) chat.title = autoTitle(chat);
      const last = chat.messages[chat.messages.length - 1];
      chat.updatedAt = (last && last.at) || chat.updatedAt || chat.createdAt;
      list.push(chat);
    }
    writeChats(list);
    setCurrentId(chat.id);
  }
  // Grouped for the list: Today, Yesterday, Previous 7 Days, then by month.
  function groupOf(iso) {
    const d = new Date(iso || 0);
    const day = (x) => new Date(x.getFullYear(), x.getMonth(), x.getDate()).getTime();
    const diff = Math.round((day(new Date()) - day(d)) / 86400000);
    if (diff <= 0) return 'Today';
    if (diff === 1) return 'Yesterday';
    if (diff < 7) return 'Previous 7 Days';
    return d.toLocaleDateString('en-GB', { month: 'long', year: d.getFullYear() === new Date().getFullYear() ? undefined : 'numeric' });
  }

  // ---- the context window: roughly how much of it the conversation takes ----
  // About 3.5 characters a token; the instructions and tools take ~3k more
  // (and what's on screen, in the floating chat, up to ~2.5k).
  const tokensOf = (chars) => Math.ceil(chars / 3.5);
  const shortTokens = (n) => (n < 1000 ? String(n) : `${(n / 1000).toFixed(n < 9950 ? 1 : 0).replace(/\.0$/, '')}k`);
  function windowOf(status) {
    const model = String((status && (status.model || status.defaultModel)) || '').toLowerCase();
    if (status && status.provider === 'gemini') return 128000;
    if (/claude/.test(model)) return 128000;
    if (/gemini|gpt-4o|gpt-4\.1|gpt-5|o3|o4/.test(model)) return 128000;
    if (/llama-3\.[13]|qwen|deepseek|mistral-large/.test(model)) return 64000;
    return 32000;
  }

  // ---- text: **bold**, lists, line breaks ----
  function rich(text) {
    const lines = esc(text).replace(/\*\*(.+?)\*\*/g, '<b>$1</b>').split('\n');
    let html = '';
    let list = false;
    for (const line of lines) {
      const item = line.match(/^\s*(?:[-•*]|\d+[.)])\s+(.*)$/);
      if (item) { if (!list) { html += '<ul>'; list = true; } html += `<li>${item[1]}</li>`; continue; }
      if (list) { html += '</ul>'; list = false; }
      html += line.trim() ? `<p>${line}</p>` : '';
    }
    return html + (list ? '</ul>' : '');
  }

  function fileIcon(name) {
    const ext = String(name).split('.').pop().toLowerCase();
    const label = ext === 'pdf' ? 'PDF' : ['xlsx', 'xlsm', 'csv', 'tsv'].includes(ext) ? 'XLS' : ['doc', 'docx', 'rtf'].includes(ext) ? 'DOC' : ['png', 'jpg', 'jpeg', 'heic', 'webp', 'gif', 'tif', 'tiff'].includes(ext) ? 'IMG' : 'TXT';
    return `<span class="as-file-kind k-${label.toLowerCase()}">${label}</span>`;
  }

  // ---- the proposals ----
  const KIND_TITLE = { createQuotation: 'New quotation', addQuotationItems: 'Add to quotation', createTask: 'New task', open: 'Open',
    editQuotationItems: 'Change quotation lines', updateQuotationDetails: 'Change quotation details', duplicateQuotation: 'Copy quotation',
    createProject: 'New project', createClient: 'New client', completeTask: 'Mark task done', createBOQ: 'New BOQ' };
  const ICON = { createTask: '✓', completeTask: '✓', open: '↗', createProject: '▣', createClient: '◉', duplicateQuotation: '⧉',
    editQuotationItems: '✎', updateQuotationDetails: '✎' };
  const BLOCKING = /no project|no quotation|only a draft|no items|no title|isn't a date|can't do|couldn't be found|nothing to change|no name|already a client|say which|needs a|no open task|no line matches|matches \d+ lines/i;
  const rowsHTML = (rows) => `<div class="as-facts">${rows.filter((r) => r[1] !== undefined && r[1] !== null && r[1] !== '')
    .map(([k, v]) => `<div><span>${esc(k)}</span><b>${v}</b></div>`).join('')}</div>`;
  const itemsTotal = (items) => (items || []).reduce((a, i) => a + (Number(i.quantity) || 0) * (Number(i.unitPrice) || 0), 0);

  function card(p, mi, pi) {
    const state = p._state || '';
    const problems = (p.problems || []).map((x) => `<li>${esc(x)}</li>`).join('');
    const blocking = (p.problems || []).some((x) => BLOCKING.test(x));
    let body = '';
    let title = KIND_TITLE[p.type] || p.type;
    let button = '';
    if (p.type === 'createQuotation' || p.type === 'addQuotationItems' || p.type === 'createBOQ') {
      title = p.type === 'createQuotation'
        ? `New ${String(p.pricingMode || 'Rental').toLowerCase()} quotation · ${esc(p.projectNumber || '?')}${p.projectName ? ` ${esc(p.projectName)}` : ''}`
        : p.type === 'createBOQ'
          ? `New ${String(p.pricingMode || 'Rental').toLowerCase()} BOQ · ${esc(p.projectNumber || '?')}${p.projectName ? ` ${esc(p.projectName)}` : ''}`
          : `Add to ${esc(p.quotationNumber || '?')}`;
      const editable = !state;
      const rows = (p.items || []).map((it, ii) => `
        <tr data-ii="${ii}">
          <td class="as-it-no">${ii + 1}</td>
          <td class="as-it-desc">${esc(String(it.description).split('\n')[0])}${it.itemCode ? `<span class="as-code">${esc(it.itemCode)}</span>` : ''}${it.priceFromList ? '<span class="as-tag" title="Price from the material list">list price</span>' : ''}${it.kind !== 'Material' ? `<span class="as-tag soft">${esc(it.kind === 'Other' ? (it.section || 'Other') : it.kind)}</span>` : ''}</td>
          <td class="as-it-qty">${editable ? `<input type="number" min="1" step="1" value="${Number(it.quantity) || 1}" data-f="quantity" aria-label="Quantity" />` : esc(it.quantity)} <span class="as-unit">${esc(it.unit || '')}</span></td>
          <td class="as-it-price">${editable ? `<input type="number" min="0" step="0.1" value="${Number(it.unitPrice) || 0}" data-f="unitPrice" aria-label="Unit price" />` : money(it.unitPrice)}</td>
          <td class="as-it-total">${money((Number(it.quantity) || 0) * (Number(it.unitPrice) || 0))}</td>
          ${editable ? `<td class="as-it-x"><button type="button" class="as-x" data-remove="${ii}" title="Leave this line out" aria-label="Leave this line out" data-no-icon>×</button></td>` : '<td></td>'}
        </tr>`).join('');
      body = `${p.subject ? `<div class="as-card-sub">Re: ${esc(p.subject)}</div>` : ''}${p.structure ? `<div class="as-card-sub">Structure: ${esc(p.structure)}</div>` : ''}
        <div class="as-table-wrap"><table class="as-items">
          <thead><tr><th class="as-th-no">#</th><th>Item</th><th>Qty</th><th>Unit price</th><th>Total</th><th></th></tr></thead>
          <tbody>${rows}</tbody>
          <tfoot><tr><td></td><td>${(p.items || []).length} line${(p.items || []).length === 1 ? '' : 's'}</td><td></td><td></td><td class="as-it-total"><b>${money(itemsTotal(p.items))}</b></td><td></td></tr></tfoot>
        </table></div>`;
      button = p.type === 'createQuotation' ? 'Create Quotation' : p.type === 'createBOQ' ? 'Create BOQ' : `Add ${(p.items || []).length} Line${(p.items || []).length === 1 ? '' : 's'}`;
    } else if (p.type === 'createTask') {
      title = `New ${p.endTime ? 'event' : 'task'}${p.projectNumber ? ` · ${esc(p.projectNumber)}` : ''}`;
      const when = [p.dueDate ? (window.appDay ? window.appDay(p.dueDate) : p.dueDate) : '', p.dueTime ? `${p.dueTime}${p.endTime ? `–${p.endTime}` : ''}` : ''].filter(Boolean).join(' ');
      body = `<div class="as-task"><b>${esc(p.title)}</b>${when ? `<span>${p.endTime ? '' : 'Due '}${esc(when)}</span>` : ''}${p.assignee ? `<span>For ${esc(p.assignee)}</span>` : ''}${p.notes ? `<span>${esc(p.notes)}</span>` : ''}</div>`;
      button = p.endTime ? 'Add Event' : 'Add Task';
    } else if (p.type === 'open') {
      title = `Open ${esc(p.number || '')}`;
      button = 'Open';
    } else if (p.type === 'editQuotationItems') {
      title = `Change ${esc(p.quotationNumber || '?')}`;
      const rows = (p.changes || []).map((c) => {
        const what = [];
        if (c.remove) what.push('<span class="as-del">Remove</span>');
        else {
          if (c.quantity !== undefined && c.quantity !== c.oldQuantity) what.push(`Qty <s>${num(c.oldQuantity)}</s> → <b>${num(c.quantity)}</b>`);
          if (c.unitPrice !== undefined && c.unitPrice !== c.oldUnitPrice) what.push(`Price <s>${money(c.oldUnitPrice)}</s> → <b>${money(c.unitPrice)}</b>`);
          if (c.newDescription) what.push(`Reads “${esc(c.newDescription)}”`);
        }
        return `<tr><td class="as-it-desc">${esc(String(c.description).split('\n')[0])}</td><td class="as-change">${what.join('<br>') || 'No change'}</td></tr>`;
      }).join('');
      body = `<div class="as-table-wrap"><table class="as-items"><thead><tr><th>Line</th><th>Change</th></tr></thead><tbody>${rows}</tbody></table></div>`;
      button = `Change ${(p.changes || []).length} Line${(p.changes || []).length === 1 ? '' : 's'}`;
    } else if (p.type === 'updateQuotationDetails') {
      title = `Change ${esc(p.quotationNumber || '?')}`;
      body = `<div class="as-table-wrap"><table class="as-items"><thead><tr><th>Field</th><th>Now</th><th>Becomes</th></tr></thead><tbody>${(p.fields || [])
        .map((f) => `<tr><td>${esc(f.label)}</td><td class="as-old">${esc(f.old) || '—'}</td><td><b>${esc(f.new) || '—'}</b></td></tr>`).join('')}</tbody></table></div>`;
      button = 'Save Changes';
    } else if (p.type === 'duplicateQuotation') {
      title = `Copy ${esc(p.quotationNumber || '?')}`;
      body = rowsHTML([['Into', p.toProjectNumber ? `${esc(p.toProjectNumber)} ${esc(p.toProjectName || '')}` : 'The same project'], ['As', 'A new draft with the next number']]);
      button = 'Make Copy';
    } else if (p.type === 'createProject') {
      title = `New project · ${esc(p.name || '')}`;
      body = rowsHTML([['Number', esc(p.projectNumber)], ['Client', `${esc(p.clientName)}${p.clientNew ? ' <span class="as-tag">new client</span>' : ''}`],
        ['Site', `${esc(p.siteName)}${p.siteNew ? ' <span class="as-tag">new site</span>' : ''}`], ['Job', esc(p.jobType)]]);
      button = 'Create Project';
    } else if (p.type === 'createClient') {
      title = `New client · ${esc(p.companyName || '')}`;
      body = rowsHTML([['Contact', esc(p.contactPerson)], ['Phone', esc(p.phone)], ['Email', esc(p.email)],
        ['Address', [p.address, p.addressLine2, p.addressLine3].filter(Boolean).map(esc).join('<br>')]]);
      button = 'Add Client';
    } else if (p.type === 'completeTask') {
      title = 'Mark task done';
      body = rowsHTML([['Task', esc(p.title || '')]]);
      button = 'Mark Done';
    }
    const done = state === 'done'
      ? `<div class="as-done"><span class="as-check">✓</span><span>${esc((p._result && p._result.message) || 'Done.')}</span>${p._result && p._result.href ? `<button type="button" class="as-open" data-href="${esc(p._result.href)}" data-no-icon>Open</button>` : ''}</div>`
      : state === 'dismissed' ? '<div class="as-done muted">Dismissed.</div>' : '';
    return `<div class="as-card${state ? ` ${state}` : ''}" data-mi="${mi}" data-pi="${pi}">
      <div class="as-card-head"><span class="as-card-icon">${ICON[p.type] || '¶'}</span><span class="as-card-title">${title}</span></div>
      ${body}
      ${problems ? `<ul class="as-problems">${problems}</ul>` : ''}
      ${done || `<div class="as-card-actions">
        <button type="button" class="as-dismiss" data-act="dismiss" data-no-icon>Dismiss</button>
        <button type="button" class="primary" data-act="run" ${blocking ? 'disabled' : ''} data-no-icon>${button}</button>
      </div>`}
    </div>`;
  }

  // ---- one chat, in a given element ----
  function mount(root, opts = {}) {
    const compact = !!opts.compact;
    root.classList.add('as-chat');
    root.classList.toggle('compact', compact);
    root.classList.toggle('with-side', !compact);
    // The chats: a column on the Assistant page, a list over the floating chat.
    const side = `<aside class="as-side${compact ? ' hidden' : ''}" data-r="side" aria-label="Chats">
        <div class="as-side-head"><b>Chats</b><span class="as-side-count" data-r="count"></span></div>
        <label class="as-side-search">${SVG.search}<input type="search" data-r="search" placeholder="Search chats" autocomplete="off" /></label>
        <div class="as-side-list" data-r="list"></div>
      </aside>`;
    root.innerHTML = `
      ${compact ? '' : side}
      <div class="as-main">
      <header class="as-head">
        <div class="as-head-text">
          ${compact ? `<span class="as-head-mark">${MARK}</span><b class="as-head-title">Assistant</b>` : `<button type="button" class="as-icon-btn as-side-toggle" data-r="hist" data-no-icon title="Show or hide the chats">${SVG.sidebar}</button><h1>Assistant</h1>`}
          <span class="as-status" data-r="status"></span>
        </div>
        <div class="as-head-actions">
          <button type="button" class="as-ctx" data-r="ctx" data-no-icon aria-haspopup="dialog"></button>
          ${compact ? `<button type="button" class="as-icon-btn" data-r="hist" data-no-icon title="Chats — earlier conversations">${SVG.history}</button>` : ''}
          <button type="button" class="as-new" data-r="new" data-no-icon title="Start a new chat${compact ? '' : ' (⌘N)'} — this one stays in the list">${SVG.plus}${compact ? '' : 'New Chat'}</button>
          ${compact ? `<button type="button" class="as-icon-btn" data-r="expand" data-no-icon title="Open the Assistant page">${SVG.expand}</button>
          <button type="button" class="as-icon-btn" data-r="close" data-no-icon title="Close (Esc)">${SVG.close}</button>` : ''}
        </div>
        <div class="as-ctx-pop hidden" data-r="ctxpop" role="dialog" aria-label="Context window"></div>
      </header>
      ${compact ? side : ''}
      <div class="as-scroll" data-r="scroll"><div class="as-messages" data-r="messages"></div></div>
      <div class="as-composer-wrap">
        ${compact ? '<div class="as-context" data-r="context"></div>' : ''}
        <div class="as-composer">
          <div class="as-files hidden" data-r="files"></div>
          <div class="as-input-row">
            <button type="button" class="as-attach" data-r="attach" data-no-icon title="Attach a file — a quotation, BOQ, list, drawing or photo" aria-label="Attach a file">${SVG.clip}</button>
            <textarea data-r="input" rows="1" placeholder="${compact ? 'Ask about this page, or say what to do…' : 'Ask, or tell it what to do — e.g. “Make a rental quotation for 26219 with 200 2.0m standards”'}" autocomplete="off"></textarea>
            <button type="button" class="as-send" data-r="send" data-no-icon title="Send (Return)" aria-label="Send" disabled>${SVG.send}</button>
          </div>
        </div>
        ${compact ? '' : '<p class="as-foot">It proposes; nothing is made or changed until you confirm. Check its work before sending anything to a client.</p>'}
        <input type="file" data-r="file" multiple hidden accept=".pdf,.png,.jpg,.jpeg,.heic,.webp,.gif,.tif,.tiff,.xlsx,.xlsm,.csv,.tsv,.txt,.docx,.doc,.rtf" />
      </div>
      </div>
      <div class="as-drop hidden" data-r="drop"><div><b>Drop to attach</b><span>PDF, pictures, Excel, Word or text</span></div></div>`;
    const $ = (r) => root.querySelector(`[data-r="${r}"]`);
    let chat = load();
    let ai = null; // the AI connection (Settings › AI Import), for the size of its window
    let summaryOpen = false;
    let pending = [];
    let busy = false;
    let aiReady = true;
    // The run being waited for: its id, its steps as they come in
    // (window.__assistantStep), when it began, and whether its steps are shown.
    let run = null;
    let stepsOpen = false;
    let tick = null;
    const elapsed = (ms) => { const s = Math.max(0, Math.round(ms / 1000)); return s < 60 ? `${s}s` : `${Math.floor(s / 60)}m ${s % 60}s`; };

    // Steps: "Working… 12s ›" (or, once done, "Took 4 steps · 12s ›"), opening into the list.
    function stepsHTML(steps, ms, live, open) {
      const n = steps.length;
      const head = live
        ? `<span class="as-dots"><i></i><i></i><i></i></span><span class="as-steps-now">${esc(n ? steps[n - 1] : 'Thinking')}…</span><span class="as-steps-time" data-r="elapsed">${elapsed(ms)}</span>`
        : `<span class="as-steps-sum">Took ${n} step${n === 1 ? '' : 's'}${ms ? ` · ${elapsed(ms)}` : ''}</span>`;
      const list = steps.map((t, i) => `<li class="${live && i === n - 1 ? 'now' : 'done'}"><span class="as-step-mark" aria-hidden="true"></span>${esc(t)}</li>`).join('');
      return `<div class="as-steps${open ? ' open' : ''}${live ? ' live' : ''}">
        <div class="as-steps-row"><button type="button" class="as-steps-head" data-act="steps" aria-expanded="${open}" data-no-icon>${head}<span class="as-steps-chev" aria-hidden="true">›</span></button>${live ? '<button type="button" class="as-stop" data-act="stop" data-no-icon title="Stop (Esc) — or just type something else to interrupt">Stop</button>' : ''}</div>
        ${n ? `<ol class="as-steps-list">${list}</ol>` : ''}
      </div>`;
    }

    // Its questions as buttons. One question: a click answers it. Several:
    // pick each, then Send. "Other…" for an answer of your own.
    const picks = {}; // message index → { question id: answer } (not yet sent)
    function questionsHTML(m, mi) {
      const qs = m.questions || [];
      if (!qs.length) return '';
      const answered = m.answers || null;
      const mine = picks[mi] || {};
      const live = !answered && mi === chat.messages.length - 1 && !busy;
      const blocks = qs.map((q, qi) => {
        const chosen = answered ? answered[q.id] : mine[q.id];
        const opts = (q.options || []).map((o) => `<button type="button" class="as-opt${chosen === o ? ' on' : ''}" data-q="${esc(q.id)}" data-opt="${esc(o)}" ${live ? '' : 'disabled'} data-no-icon>${esc(o)}</button>`).join('');
        const other = live ? `<button type="button" class="as-opt other${chosen && !(q.options || []).includes(chosen) ? ' on' : ''}" data-q="${esc(q.id)}" data-other data-no-icon>${chosen && !(q.options || []).includes(chosen) ? esc(chosen) : 'Other…'}</button>`
          : (chosen && !(q.options || []).includes(chosen) ? `<button type="button" class="as-opt on" disabled data-no-icon>${esc(chosen)}</button>` : '');
        return `<div class="as-q${chosen ? ' done' : ''}" style="--i:${qi}">
          <div class="as-q-text"><span class="as-q-no">${qs.length > 1 ? qi + 1 : '?'}</span>${esc(q.text)}</div>
          <div class="as-opts">${opts}${other}</div>
          <div class="as-other-row hidden" data-other-row="${esc(q.id)}"><input type="text" placeholder="Your answer…" data-other-input="${esc(q.id)}" /><button type="button" class="primary" data-other-ok="${esc(q.id)}" data-no-icon>OK</button></div>
        </div>`;
      }).join('');
      const count = qs.filter((q) => mine[q.id]).length;
      const footer = live && qs.length > 1
        ? `<div class="as-q-foot"><span>${count} of ${qs.length} answered</span><button type="button" class="primary" data-answers ${count === qs.length ? '' : 'disabled'} data-no-icon>Send Answers</button></div>`
        : '';
      return `<div class="as-questions${answered ? ' answered' : ''}" data-qmi="${mi}">${blocks}${footer}</div>`;
    }
    // The answers, sent as the person's next message.
    function sendAnswers(mi) {
      const m = chat.messages[mi];
      const mine = picks[mi] || {};
      m.answers = { ...mine };
      delete picks[mi];
      save(chat);
      const qs = m.questions || [];
      const text = qs.length === 1 ? mine[qs[0].id] : qs.map((q) => `${q.text} — ${mine[q.id]}`).join('\n');
      send(text);
    }
    function pick(mi, qid, answer) {
      const m = chat.messages[mi];
      picks[mi] = { ...(picks[mi] || {}), [qid]: answer };
      if ((m.questions || []).length === 1) { sendAnswers(mi); return; }
      const box = $('messages').querySelector(`[data-qmi="${mi}"]`);
      if (box) box.outerHTML = questionsHTML(m, mi);
    }

    function messageHTML(m, mi) {
      if (m.role === 'user') {
        const files = (m.files || []).map((f) => `<span class="as-file-chip sent">${fileIcon(f.name)}${esc(f.name)}</span>`).join('');
        const where = m.where ? `<div class="as-where">${esc(m.where)}</div>` : '';
        return `<div class="as-msg user" data-mi="${mi}">${files ? `<div class="as-msg-files">${files}</div>` : ''}${m.text ? `<div class="as-bubble">${rich(m.text)}</div>` : ''}${where}${metaHTML(m, mi)}</div>`;
      }
      if (m.error) {
        return `<div class="as-msg bot error" data-mi="${mi}"><span class="as-avatar">${MARK}</span><div class="as-body">
          ${(m.steps || []).length ? stepsHTML(m.steps, m.ms, false, !!m.stepsOpen) : ''}<div class="as-error">${esc(m.error)}</div>
          ${mi === chat.messages.length - 1 ? '<button type="button" class="as-retry" data-act="retry" data-no-icon>Try Again</button>' : ''}</div></div>`;
      }
      const cards = (m.proposals || []).map((p, pi) => card(p, mi, pi)).join('');
      const steps = (m.steps || []).length ? stepsHTML(m.steps, m.ms, false, !!m.stepsOpen) : '';
      if (m.interrupted) {
        return `<div class="as-msg bot interrupted" data-mi="${mi}"><span class="as-avatar">${MARK}</span><div class="as-body">${steps}<div class="as-interrupted">Interrupted</div></div></div>`;
      }
      return `<div class="as-msg bot" data-mi="${mi}"><span class="as-avatar">${MARK}</span><div class="as-body">
        ${steps}${m.text ? `<div class="as-text">${rich(m.text)}</div>` : ''}${questionsHTML(m, mi)}${cards}${metaHTML(m, mi)}</div></div>`;
    }

    function emptyHTML() {
      if (compact) {
        const page = document.body.dataset.page || '';
        const list = PAGE_SUGGESTIONS[page] || PAGE_SUGGESTIONS.default;
        return `<div class="as-empty small">
          <div class="as-empty-mark">${MARK}</div>
          <h2>How can I help?</h2>
          <p>I can see this page. Ask about it, or have me do the work — I’ll show you before anything changes.</p>
          <div class="as-chips">${list.map((t) => `<button type="button" class="as-chip" data-chip="${esc(t)}" data-no-icon>${esc(t)}</button>`).join('')}</div>
        </div>`;
      }
      return `<div class="as-empty">
        <div class="as-empty-mark">${MARK}</div>
        <h2>What shall we do?</h2>
        <p>Ask about projects, prices, stock, tasks and invoices, or have it do the work: quotations from a file or a list, changes to a draft, new projects and clients, tasks and events. It looks things up in ScaffoldPro itself, and shows you what it would do before anything is made or changed. On any other page, the sparkle at the bottom right (⌘J) opens it beside your work.</p>
        <div class="as-suggest">${SUGGESTIONS.map((s, i) => `<button type="button" class="as-sug" data-sug="${i}" data-no-icon><b>${esc(s.title)}</b><span>${esc(s.hint || s.text.split('\n')[0])}</span></button>`).join('')}</div>
      </div>`;
    }

    function draw(scroll = true) {
      const box = $('messages');
      const upTo = chat.summary ? chat.summarisedUpTo || 0 : 0;
      box.innerHTML = chat.messages.length
        ? chat.messages.map((m, mi) => (mi === upTo && upTo > 0 ? summaryHTML(upTo) : '') + messageHTML(m, mi)).join('') + (upTo >= chat.messages.length && upTo > 0 ? summaryHTML(upTo) : '')
        : emptyHTML();
      if (busy && run) box.insertAdjacentHTML('beforeend', `<div class="as-msg bot thinking"><span class="as-avatar">${MARK}</span><div class="as-body" data-r="live">${stepsHTML(run.steps, Date.now() - run.started, true, stepsOpen)}</div></div>`);
      $('new').disabled = !chat.messages.length || busy;
      if (scroll) requestAnimationFrame(() => { const s = $('scroll'); s.scrollTop = s.scrollHeight; });
      drawContext();
      drawMeter();
      if (sideOpen()) drawSide();
    }
    // Where the summarised part ends: "Earlier messages summarised", opening
    // into the summary the AI is sent instead of them.
    function summaryHTML(n) {
      return `<div class="as-summ${summaryOpen ? ' open' : ''}">
        <button type="button" class="as-summ-head" data-act="summary" aria-expanded="${summaryOpen}" data-no-icon>
          <span class="as-summ-rule"></span><span class="as-summ-label">${n} earlier message${n === 1 ? '' : 's'} summarised for the AI<span class="as-steps-chev" aria-hidden="true">›</span></span><span class="as-summ-rule"></span>
        </button>
        <div class="as-summ-body"><div class="as-summ-kicker">What the AI remembers of them</div>${rich(chat.summary || '')}</div>
      </div>`;
    }

    // The floating chat: what it can see.
    function drawContext() {
      const box = $('context');
      if (!box) return;
      const ctx = opts.context ? opts.context() : null;
      box.innerHTML = ctx ? `<span class="as-eye" aria-hidden="true">◉</span>Sees: ${esc(ctx.label)}${ctx.selection ? ' · <b>your selection</b>' : ''}` : '';
    }

    function drawFiles() {
      const box = $('files');
      box.classList.toggle('hidden', !pending.length);
      box.innerHTML = pending.map((f, i) => `<span class="as-file-chip">${fileIcon(f.name)}<span class="as-file-name">${esc(f.name)}</span><button type="button" data-unfile="${i}" title="Remove" aria-label="Remove ${esc(f.name)}" data-no-icon>×</button></span>`).join('');
      updateSend();
    }
    function addFiles(list) {
      for (const file of list) {
        if (pending.length >= 5) { window.appAlert('Up to 5 files at a time.'); break; }
        if (file.size > 20 * 1024 * 1024) { window.appAlert(`${file.name} is too big (20 MB at most).`); continue; }
        const reader = new FileReader();
        reader.onload = () => {
          pending.push({ name: file.name || 'Pasted picture.png', mime: file.type, base64: String(reader.result).split(',')[1] || '', size: file.size });
          drawFiles();
        };
        reader.readAsDataURL(file);
      }
    }

    onStep.redraw = () => {
      const live = $('live');
      if (live && run) live.innerHTML = stepsHTML(run.steps, Date.now() - run.started, true, stepsOpen);
    };
    // A step of the run being waited for (main.swift, assistantStep).
    function onStep(text) {
      if (!run) return;
      run.steps.push(text);
      const live = $('live');
      if (live) {
        live.innerHTML = stepsHTML(run.steps, Date.now() - run.started, true, stepsOpen);
        const s = $('scroll');
        if (s.scrollHeight - s.scrollTop - s.clientHeight < 140) s.scrollTop = s.scrollHeight;
      }
    }

    // What the AI is sent: the summary of earlier messages (if they've been
    // summarised), then each message since — its text (its proposals summed
    // up) and the text of files sent before.
    function history() {
      const turns = turnsOf(chat.messages.slice(chat.summarisedUpTo || 0));
      if (chat.summary) {
        const intro = `[Earlier in this conversation — summarised to save room:]\n${chat.summary}\n\n[The conversation continues:]\n`;
        if (turns.length && turns[0].role === 'user') turns[0] = { ...turns[0], text: intro + turns[0].text };
        else turns.unshift({ role: 'user', text: intro.trim(), files: [] });
      }
      return turns;
    }
    function turnsOf(messages) {
      return messages.filter((m) => !m.error && !m.interrupted).map((m) => {
        let text = m.text || '';
        if (m.role === 'assistant' && (m.questions || []).length) {
          text += '\n\n(Asked: ' + m.questions.map((q) => `${q.text} [${(q.options || []).join(' / ')}]`).join('; ') + ')';
        }
        if (m.role === 'assistant' && (m.proposals || []).length) {
          text += '\n\n(Proposed: ' + m.proposals.map((p) => `${p.type}${p.projectNumber ? ` for ${p.projectNumber}` : ''}${p.quotationNumber ? ` to ${p.quotationNumber}` : ''}${p.items ? ` with ${p.items.length} items` : ''}${p._state === 'done' ? ` — done: ${(p._result && p._result.message) || ''}` : p._state === 'dismissed' ? ' — dismissed' : ''}`).join('; ') + ')';
        }
        return { role: m.role === 'assistant' ? 'assistant' : 'user', text, files: (m.files || []).filter((f) => f.text).map((f) => ({ name: f.name, text: f.text })) };
      });
    }

    // ---- the context window ----
    // How much of it the next message would take (roughly), and its parts.
    function usage() {
      let words = 0, files = 0;
      for (const t of history()) {
        words += t.text.length;
        for (const f of t.files) files += f.text.length + 60;
      }
      const words_ = tokensOf(words), files_ = tokensOf(files), setup = OVERHEAD + (compact ? SCREEN : 0);
      const total = words_ + files_ + setup;
      const max = windowOf(ai);
      return { words: words_, files: files_, setup, total, max, share: Math.min(1, total / max) };
    }
    // Messages that could be summarised: those before the newest few (cut
    // at a message of the person's, so what's kept starts with them).
    function summarisable() {
      const from = chat.summarisedUpTo || 0;
      let cut = chat.messages.length - KEEP_RAW;
      while (cut > from && chat.messages[cut] && chat.messages[cut].role !== 'user') cut--;
      return { from, cut, count: Math.max(0, cut - from) };
    }
    function needsSummary() {
      const { count } = summarisable();
      if (count < 2) return false;
      const unsent = chat.messages.length - (chat.summarisedUpTo || 0);
      // Too full, or so long the Mac would leave the oldest out (it keeps 80).
      return (usage().share >= COMPACT_AT && count >= 4) || unsent > 60;
    }
    // Summarise the older messages (main.swift, assistant:summarise): the AI
    // is sent the summary from then on, and the newest messages in full.
    async function summarise() {
      const { from, cut, count } = summarisable();
      if (count < 2) return { ok: false, error: 'There’s nothing old enough to summarise yet.' };
      const id = chat.id;
      let r;
      try { r = await window.api.assistant.summarise(turnsOf(chat.messages.slice(from, cut)), chat.summary || null); } catch (e) { r = { ok: false, error: e.message }; }
      if (!r || !r.ok || !String(r.summary || '').trim()) return { ok: false, error: (r && r.error) || 'The AI couldn’t summarise the conversation.' };
      const apply = (c) => { c.summary = String(r.summary).trim(); c.summarisedUpTo = cut; c.summarisedAt = new Date().toISOString(); };
      if (chat.id === id) { apply(chat); save(chat); } else {
        // Switched to another chat meanwhile: the summary still goes on its own.
        const list = readChats();
        const c = list.find((x) => x.id === id);
        if (c) { apply(c); writeChats(list); }
      }
      return { ok: true, count };
    }
    function ringHTML(share) {
      const r = 7, len = 2 * Math.PI * r;
      return `<svg viewBox="0 0 18 18" width="18" height="18" aria-hidden="true"><circle cx="9" cy="9" r="${r}" fill="none" stroke="currentColor" stroke-opacity=".18" stroke-width="2.4"/><circle cx="9" cy="9" r="${r}" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round" stroke-dasharray="${(len * Math.max(0.02, share)).toFixed(2)} ${len.toFixed(2)}" transform="rotate(-90 9 9)"/></svg>`;
    }
    const level = (share) => (share >= 0.85 ? 'full' : share >= 0.6 ? 'high' : 'ok');
    function drawMeter() {
      const b = $('ctx');
      const u = usage();
      b.className = `as-ctx ${level(u.share)}`;
      b.innerHTML = `${ringHTML(u.share)}<span>${shortTokens(u.total)}${compact ? '' : ` / ${shortTokens(u.max)}`}</span>`;
      b.title = `Context window: about ${shortTokens(u.total)} of ${shortTokens(u.max)} tokens (${Math.round(u.share * 100)}%)`;
      if (!$('ctxpop').classList.contains('hidden')) drawCtxPop();
    }
    function drawCtxPop() {
      const u = usage();
      const { count } = summarisable();
      const pct = Math.round(u.share * 100);
      const done = chat.summary ? chat.summarisedUpTo || 0 : 0;
      $('ctxpop').innerHTML = `
        <div class="as-pop-title">Context window</div>
        <div class="as-bar ${level(u.share)}"><i style="width:${Math.max(1.5, pct)}%"></i></div>
        <div class="as-pop-big"><b>${shortTokens(u.total)}</b> of ${shortTokens(u.max)} tokens <span>${pct}%</span></div>
        <div class="as-pop-rows">
          <div><span>Messages</span><b>${shortTokens(u.words)}</b></div>
          <div><span>Files read</span><b>${shortTokens(u.files)}</b></div>
          <div><span>Instructions${compact ? ' and this page' : ''}</span><b>${shortTokens(u.setup)}</b></div>
        </div>
        <p class="as-pop-note">${done ? `The first ${done} message${done === 1 ? ' is' : 's are'} summarised. ` : ''}When it passes ${Math.round(COMPACT_AT * 100)}%, older messages are summarised so the AI keeps the gist and stays quick. The newest ${KEEP_RAW} always go in full.</p>
        <button type="button" class="as-pop-btn" data-act="compact" ${count >= 2 && !busy ? '' : 'disabled'} data-no-icon>Summarise Earlier Messages Now</button>
        <p class="as-pop-note small">Rough count — about 3½ characters a token. ${esc((ai && (ai.model || ai.defaultModel)) || '')}</p>`;
    }
    function toggleCtxPop(force) {
      const pop = $('ctxpop');
      const show = force ?? pop.classList.contains('hidden');
      if (show) { drawCtxPop(); closeSide(); }
      pop.classList.toggle('hidden', !show);
      $('ctx').classList.toggle('on', show);
    }
    async function compactNow(button) {
      button.disabled = true;
      button.textContent = 'Summarising…';
      const r = await summarise();
      if (!r.ok) { await window.appAlert(r.error); }
      draw(false);
      drawCtxPop();
    }

    // ---- the chats ----
    let query = '';
    const sideOpen = () => !$('side').classList.contains('hidden');
    function drawSide() {
      const list = readChats();
      $('count').textContent = list.length ? String(list.length) : '';
      const q = query.trim().toLowerCase();
      const shown = q ? list.filter((c) => (c.title || '').toLowerCase().includes(q)
        || c.messages.some((m) => String(m.text || '').toLowerCase().includes(q))) : list;
      let html = '';
      let group = '';
      for (const c of shown) {
        const g = groupOf(c.updatedAt || c.createdAt);
        if (g !== group) { html += `<div class="as-side-group">${esc(g)}</div>`; group = g; }
        const n = c.messages.filter((m) => !m.error && !m.interrupted).length;
        html += `<div class="as-hist${c.id === chat.id ? ' on' : ''}" data-chat="${esc(c.id)}">
          <button type="button" class="as-hist-open" data-open-chat="${esc(c.id)}" data-no-icon title="${esc(c.title || autoTitle(c))}">
            <span class="as-hist-title">${esc(c.title || autoTitle(c))}</span>
            <span class="as-hist-sub">${esc(sentAt(c.updatedAt || c.createdAt))} · ${n} message${n === 1 ? '' : 's'}${c.summary ? ' · summarised' : ''}</span>
          </button>
          <span class="as-hist-acts">
            <button type="button" class="as-hist-act" data-rename-chat="${esc(c.id)}" data-no-icon title="Rename" aria-label="Rename">${SVG.pencil}</button>
            <button type="button" class="as-hist-act del" data-delete-chat="${esc(c.id)}" data-no-icon title="Delete" aria-label="Delete">${SVG.trash}</button>
          </span>
        </div>`;
      }
      if (!list.length) html = '<div class="as-side-empty">Your chats appear here. Each is kept on this Mac until you delete it.</div>';
      else if (!shown.length) html = `<div class="as-side-empty">No chat mentions “${esc(query.trim())}”.</div>`;
      $('list').innerHTML = html;
    }
    function openSide() {
      if (compact) {
        const pop = $('side');
        pop.style.top = `${root.querySelector('.as-head').offsetHeight}px`;
        toggleCtxPop(false);
      }
      $('side').classList.remove('hidden');
      $('hist').classList.add('on');
      drawSide();
      if (compact) setTimeout(() => $('search').focus(), 0);
    }
    function closeSide() {
      if (!compact) return;
      $('side').classList.add('hidden');
      $('hist').classList.remove('on');
    }
    function toggleSide() {
      if (compact) { if (sideOpen()) closeSide(); else openSide(); return; }
      const hide = !root.classList.contains('side-hidden');
      root.classList.toggle('side-hidden', hide);
      try { localStorage.setItem(SIDE_KEY, hide ? '1' : ''); } catch (e) { /* not kept */ }
    }
    async function switchTo(id) {
      if (busy) await interrupt();
      chat = id ? (readChats().find((c) => c.id === id) || fresh()) : fresh();
      setCurrentId(chat.id);
      for (const k of Object.keys(picks)) delete picks[k];
      draw();
      drawSide();
      closeSide();
      input.focus();
    }
    async function renameChat(id) {
      const row = $('list').querySelector(`[data-chat="${CSS.escape(id)}"]`);
      const list = readChats();
      const c = list.find((x) => x.id === id);
      if (!row || !c) return;
      const box = document.createElement('input');
      box.type = 'text';
      box.className = 'as-hist-input';
      box.value = c.title || autoTitle(c);
      box.setAttribute('aria-label', 'Chat name');
      row.classList.add('renaming');
      row.querySelector('.as-hist-open').replaceWith(box);
      box.focus();
      box.select();
      let done = false;
      const finish = (keep) => {
        if (done) return;
        done = true;
        const v = box.value.replace(/\s+/g, ' ').trim();
        if (keep && v) {
          c.title = v.slice(0, 120);
          writeChats(list);
          if (chat.id === id) chat.title = c.title;
        }
        drawSide();
      };
      box.addEventListener('keydown', (e) => {
        if (e.key === 'Enter') { e.preventDefault(); finish(true); }
        if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); finish(false); }
      });
      box.addEventListener('blur', () => finish(true));
      box.addEventListener('click', (e) => e.stopPropagation());
    }
    async function deleteChat(id) {
      const list = readChats();
      const c = list.find((x) => x.id === id);
      if (!c) return;
      if (!await window.appConfirm(`Delete “${c.title || autoTitle(c)}”?\n\nThe chat is removed from this Mac. Anything it made stays.`, { ok: 'Delete', danger: true })) return;
      if (busy && chat.id === id) await interrupt();
      writeChats(list.filter((x) => x.id !== id));
      if (chat.id === id) { chat = fresh(); setCurrentId(chat.id); draw(); }
      drawSide();
    }

    async function send(textArg) {
      const text = (textArg ?? $('input').value).trim();
      // While it works, the button stops it; a new message interrupts it.
      if (busy && !text && !pending.length) { interrupt(); return; }
      if (!text && !pending.length) return;
      if (!aiReady) { notReady(); return; }
      if (busy) await interrupt();
      const files = pending;
      pending = [];
      drawFiles();
      $('input').value = '';
      autosize();
      chat = load(); // the other place may have added to it
      const ctx = opts.context ? opts.context() : null;
      chat.messages.push({ role: 'user', text, files: files.map((f) => ({ name: f.name })), where: ctx ? `On ${ctx.label}` : undefined, at: new Date().toISOString() });
      save(chat);
      await ask(files, ctx);
    }

    // Interrupted (or given up on): its answer, if it ever comes, is left out.
    let asking = 0;
    let stopWaiting = null;
    let current = null;
    async function interrupt() {
      if (!busy || !stopWaiting) { await current; return; }
      const stop = stopWaiting;
      stopWaiting = null;
      if (run) window.api.assistant.cancel(run.id).catch(() => {});
      stop({ interrupted: true });
      await current;
    }
    function ask(files, ctx) {
      current = askNow(files, ctx);
      return current;
    }
    async function askNow(files, ctx) {
      busy = true;
      const mine = ++asking;
      run = { id: `run-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`, steps: [], started: Date.now() };
      listeners.set(run.id, onStep);
      clearInterval(tick);
      tick = setInterval(() => { const t = $('elapsed'); if (t && run) t.textContent = elapsed(Date.now() - run.started); }, 1000);
      draw();
      updateSend();
      let r;
      const stopped = new Promise((resolve) => {
        stopWaiting = resolve;
        // Never left waiting: the Mac gives up on the AI before this.
        setTimeout(() => resolve({ ok: false, error: 'The AI didn’t answer in time. Try again, perhaps one thing at a time — or choose a quicker model in Settings › AI Import.' }), 240000);
      });
      try {
        // Too much for its context window: the older messages are summarised first.
        if (needsSummary()) {
          onStep('Summarising earlier messages to make room');
          const s = await Promise.race([summarise(), stopped]);
          if (s && s.interrupted) r = s;
          else if (s && s.ok) onStep(`Summarised ${s.count} earlier message${s.count === 1 ? '' : 's'}`);
          else onStep('Couldn’t summarise — sending the conversation as it is');
        }
        if (!r) {
          r = await Promise.race([
            window.api.assistant.send(history(), files.map((f) => ({ name: f.name, mime: f.mime, base64: f.base64 })), ctx && ctx.payload, run.id),
            stopped,
          ]);
        }
      } catch (e) {
        r = { ok: false, error: e.message || 'The assistant couldn’t be reached.' };
      }
      if (mine !== asking) return;
      stopWaiting = null;
      clearInterval(tick);
      const finished = run;
      listeners.delete(finished.id);
      run = null;
      busy = false;
      const steps = finished.steps.slice(), ms = Date.now() - finished.started;
      const last = [...chat.messages].reverse().find((m) => m.role === 'user');
      if (last && r && Array.isArray(r.files) && r.files.length) last.files = r.files.map((f) => ({ name: f.name, text: f.text }));
      const at = new Date().toISOString();
      if (r && r.interrupted) chat.messages.push({ role: 'assistant', interrupted: true, steps, ms, at });
      else if (!r || r.ok === false) chat.messages.push({ role: 'assistant', error: (r && r.error) || 'Something went wrong.', steps, ms, at });
      else {
        const questions = Array.isArray(r.questions) ? r.questions.filter((q) => q && q.text) : [];
        const proposals = r.proposals || [];
        // Nothing came back: said so, never a made-up "Done".
        if (!String(r.reply || '').trim() && !proposals.length && !questions.length) {
          chat.messages.push({ role: 'assistant', error: 'The AI came back with nothing. Say exactly what you’d like, or press Try Again.', steps, ms, at });
        } else {
          chat.messages.push({ role: 'assistant', text: r.reply || '', proposals, questions, steps, ms, at });
        }
      }
      save(chat);
      draw();
      updateSend();
      $('input').focus();
    }

    async function runProposal(mi, pi, button) {
      if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
      const p = chat.messages[mi].proposals[pi];
      if (p.type === 'open') { if (p.href) (window.appNavigate || ((h) => { location.href = h; }))(p.href); return; }
      button.disabled = true;
      button.textContent = 'Working…';
      let r;
      try { r = await window.api.assistant.run(p); } catch (e) { r = { ok: false, error: e.message }; }
      if (!r || !r.ok) {
        button.disabled = false;
        await window.appAlert((r && r.error) || 'It couldn’t be done.');
        draw(false);
        return;
      }
      p._state = 'done';
      p._result = { message: r.message, href: r.href };
      save(chat);
      draw(false);
      // The page underneath shows the change, redrawn in place.
      if (compact && typeof window.appRefresh === 'function') { try { await window.appRefresh(); } catch (e) { /* the page stays as it was */ } }
    }

    async function checkStatus() {
      let s = null;
      try { s = await window.api.ai.status(); } catch (e) { s = null; }
      aiReady = !!(s && s.hasKey);
      ai = s;
      drawMeter();
      const names = { gemini: 'Google Gemini', openrouter: 'OpenRouter' };
      $('status').innerHTML = aiReady
        ? `<span class="as-dot on"></span>${compact ? '' : `${esc(names[s.provider] || s.provider)} · `}${esc(s.model || s.defaultModel || '')}`
        : '<span class="as-dot"></span>No AI connected — <a href="settings.html#ai-import">set one up</a>';
      updateSend();
    }
    function notReady() { window.appAlert('No AI is connected yet.\n\nAdd a free key in Settings › AI Import, then come back.'); }

    function autosize() {
      const t = $('input');
      t.style.height = 'auto';
      t.style.height = `${Math.min(compact ? 140 : 220, t.scrollHeight)}px`;
    }
    function updateSend() {
      const has = !!$('input').value.trim() || pending.length > 0;
      const stop = busy && !has;
      const b = $('send');
      b.disabled = !busy && !has;
      b.classList.toggle('stop', stop);
      b.innerHTML = stop ? SVG.stop : SVG.send;
      b.title = stop ? 'Stop (Esc)' : busy ? 'Interrupt and send this instead (Return)' : 'Send (Return)';
      b.setAttribute('aria-label', stop ? 'Stop' : 'Send');
      $('input').placeholder = busy ? 'Working… type to interrupt with something else'
        : compact ? 'Ask about this page, or say what to do…' : 'Ask, or tell it what to do — e.g. “Make a rental quotation for 26219 with 200 2.0m standards”';
    }

    // ---- wiring ----
    const input = $('input');
    input.addEventListener('input', () => { autosize(); updateSend(); });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); send(); }
      if (e.key === 'Escape' && busy) { e.preventDefault(); e.stopPropagation(); interrupt(); return; }
      if (e.key === 'Escape' && !$('ctxpop').classList.contains('hidden')) { e.preventDefault(); e.stopPropagation(); toggleCtxPop(false); return; }
      if (e.key === 'Escape' && compact && sideOpen()) { e.preventDefault(); e.stopPropagation(); closeSide(); return; }
      if (e.key === 'Escape' && compact && opts.onClose) { e.preventDefault(); e.stopPropagation(); opts.onClose(); }
    });
    input.addEventListener('paste', (e) => {
      const files = [...(e.clipboardData ? e.clipboardData.files : [])];
      if (files.length) { e.preventDefault(); addFiles(files); }
    });
    input.addEventListener('focus', drawContext);
    $('messages').addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && e.target.matches('[data-other-input]')) {
        e.preventDefault();
        const ok = e.target.parentElement.querySelector('[data-other-ok]');
        if (ok) ok.click();
      }
    });
    $('send').addEventListener('click', () => send());
    $('attach').addEventListener('click', () => $('file').click());
    $('file').addEventListener('change', (e) => { addFiles([...e.target.files]); e.target.value = ''; });
    $('files').addEventListener('click', (e) => {
      const b = e.target.closest('[data-unfile]');
      if (b) { pending.splice(Number(b.dataset.unfile), 1); drawFiles(); }
    });
    // A new chat: the one before stays in the list.
    $('new').addEventListener('click', () => { if (chat.messages.length) switchTo(null); });
    $('hist').addEventListener('click', toggleSide);
    $('ctx').addEventListener('click', (e) => { e.stopPropagation(); toggleCtxPop(); });
    $('ctxpop').addEventListener('click', (e) => {
      e.stopPropagation();
      const b = e.target.closest('[data-act="compact"]');
      if (b) compactNow(b);
    });
    // Clicking elsewhere closes the context window's card and the chats list.
    document.addEventListener('mousedown', (e) => {
      if (!$('ctxpop').classList.contains('hidden') && !e.target.closest('.as-ctx-pop, .as-ctx')) toggleCtxPop(false);
      if (compact && sideOpen() && !root.contains(e.target)) closeSide();
    });
    $('search').addEventListener('input', (e) => { query = e.target.value; drawSide(); });
    $('search').addEventListener('keydown', (e) => {
      if (e.key === 'Escape') {
        e.preventDefault();
        e.stopPropagation();
        if (query) { query = ''; e.target.value = ''; drawSide(); } else if (compact) { closeSide(); input.focus(); }
      }
      if (e.key === 'Enter') { const first = $('list').querySelector('[data-open-chat]'); if (first) first.click(); }
    });
    $('list').addEventListener('click', (e) => {
      const ren = e.target.closest('[data-rename-chat]');
      if (ren) { e.stopPropagation(); renameChat(ren.dataset.renameChat); return; }
      const del = e.target.closest('[data-delete-chat]');
      if (del) { e.stopPropagation(); deleteChat(del.dataset.deleteChat); return; }
      const openChat = e.target.closest('[data-open-chat]');
      if (openChat) switchTo(openChat.dataset.openChat);
    });
    $('list').addEventListener('dblclick', (e) => {
      const row = e.target.closest('[data-chat]');
      if (row && !e.target.closest('input')) renameChat(row.dataset.chat);
    });
    if (!compact) { try { if (localStorage.getItem(SIDE_KEY) === '1') root.classList.add('side-hidden'); } catch (e) { /* shown */ } }
    if (compact) {
      $('expand').addEventListener('click', () => (window.appNavigate || ((h) => { location.href = h; }))('assistant.html'));
      $('close').addEventListener('click', () => opts.onClose && opts.onClose());
    } else {
      document.addEventListener('keydown', (e) => {
        if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'n' && !e.shiftKey) { e.preventDefault(); $('new').click(); }
      });
    }

    // Dropping files: anywhere on the Assistant page; on the floating chat itself.
    const dropTarget = compact ? root : window;
    let depth = 0;
    const hasFiles = (e) => e.dataTransfer && [...e.dataTransfer.types].includes('Files');
    dropTarget.addEventListener('dragenter', (e) => { if (!hasFiles(e)) return; depth++; $('drop').classList.remove('hidden'); });
    dropTarget.addEventListener('dragleave', (e) => { if (!hasFiles(e)) return; depth = Math.max(0, depth - 1); if (!depth) $('drop').classList.add('hidden'); });
    dropTarget.addEventListener('dragover', (e) => { if (hasFiles(e)) e.preventDefault(); });
    dropTarget.addEventListener('drop', (e) => {
      if (!hasFiles(e)) return;
      e.preventDefault();
      e.stopPropagation();
      depth = 0;
      $('drop').classList.add('hidden');
      addFiles([...e.dataTransfer.files]);
      input.focus();
    });

    $('messages').addEventListener('click', (e) => {
      const sug = e.target.closest('[data-sug]');
      if (sug) {
        const s = SUGGESTIONS[Number(sug.dataset.sug)];
        input.value = s.text;
        autosize();
        updateSend();
        input.focus();
        input.setSelectionRange(input.value.length, input.value.length);
        if (s.attach) $('file').click();
        return;
      }
      const chip = e.target.closest('[data-chip]');
      if (chip) { send(chip.dataset.chip); return; }
      const open = e.target.closest('.as-open');
      if (open) { (window.appNavigate || ((h) => { location.href = h; }))(open.dataset.href); return; }
      if (e.target.closest('[data-act="stop"]')) { interrupt(); return; }
      const summ = e.target.closest('[data-act="summary"]');
      if (summ) {
        summaryOpen = !summaryOpen;
        summ.closest('.as-summ').classList.toggle('open', summaryOpen);
        summ.setAttribute('aria-expanded', String(summaryOpen));
        return;
      }
      const copy = e.target.closest('[data-copy]');
      if (copy) {
        const m = chat.messages[Number(copy.dataset.copy)];
        copyText(m.role === 'user' ? (m.text || '') : plainOf(m)).then((ok) => {
          copy.classList.add('copied');
          copy.querySelector('span').textContent = ok ? 'Copied' : 'Couldn’t copy';
          setTimeout(() => { copy.classList.remove('copied'); copy.querySelector('span').textContent = 'Copy'; }, 1400);
        });
        return;
      }
      const qbox = e.target.closest('[data-qmi]');
      if (qbox) {
        const mi = Number(qbox.dataset.qmi);
        const opt = e.target.closest('[data-opt]');
        if (opt) { pick(mi, opt.dataset.q, opt.dataset.opt); return; }
        const other = e.target.closest('[data-other]');
        if (other) {
          const row = qbox.querySelector(`[data-other-row="${CSS.escape(other.dataset.q)}"]`);
          row.classList.remove('hidden');
          row.querySelector('input').focus();
          return;
        }
        const ok = e.target.closest('[data-other-ok]');
        if (ok) {
          const v = qbox.querySelector(`[data-other-input="${CSS.escape(ok.dataset.otherOk)}"]`).value.trim();
          if (v) pick(mi, ok.dataset.otherOk, v);
          return;
        }
        if (e.target.closest('[data-answers]')) { sendAnswers(mi); return; }
      }
      const stepsBtn = e.target.closest('[data-act="steps"]');
      if (stepsBtn) {
        const msg = stepsBtn.closest('.as-msg');
        if (msg.classList.contains('thinking')) {
          stepsOpen = !stepsOpen;
          onStep.redraw();
        } else {
          const m = chat.messages[Number(msg.dataset.mi)];
          m.stepsOpen = !m.stepsOpen;
          save(chat);
          const box = stepsBtn.closest('.as-steps');
          box.classList.toggle('open', m.stepsOpen);
          stepsBtn.setAttribute('aria-expanded', String(!!m.stepsOpen));
        }
        return;
      }
      if (e.target.closest('[data-act="retry"]')) {
        chat.messages.pop();
        save(chat);
        ask([], opts.context ? opts.context() : null);
        return;
      }
      const cardEl = e.target.closest('.as-card');
      if (!cardEl) return;
      const mi = Number(cardEl.dataset.mi), pi = Number(cardEl.dataset.pi);
      const p = chat.messages[mi].proposals[pi];
      const remove = e.target.closest('[data-remove]');
      if (remove) { p.items.splice(Number(remove.dataset.remove), 1); save(chat); draw(false); return; }
      const act = e.target.closest('[data-act]');
      if (!act) return;
      if (act.dataset.act === 'dismiss') { p._state = 'dismissed'; save(chat); draw(false); }
      if (act.dataset.act === 'run') runProposal(mi, pi, act);
    });
    // Editing a card's quantities and prices before it's made.
    $('messages').addEventListener('change', (e) => {
      const f = e.target.dataset && e.target.dataset.f;
      if (!f) return;
      const cardEl = e.target.closest('.as-card');
      const p = chat.messages[Number(cardEl.dataset.mi)].proposals[Number(cardEl.dataset.pi)];
      const it = p.items[Number(e.target.closest('tr').dataset.ii)];
      const v = Number(e.target.value);
      it[f] = f === 'quantity' ? Math.max(1, Math.round(v || 1)) : Math.max(0, Math.round((v || 0) * 100) / 100);
      if (f === 'unitPrice') delete it.priceFromList;
      save(chat);
      e.target.blur();
      draw(false);
    });

    draw();
    checkStatus();
    return {
      // The conversation again (it may have changed on another page).
      refresh() { if (!busy) { chat = load(); draw(); } if (sideOpen()) drawSide(); checkStatus(); },
      focus() { input.focus(); },
      busy: () => busy,
    };
  }

  // ---- what's on screen, for the floating chat ----
  function pageContext() {
    const page = document.body.dataset.page || (location.pathname.split('/').pop() || '').replace('.html', '');
    const params = new URLSearchParams(location.search);
    const heading = (document.querySelector('#content h1') || {}).textContent || '';
    const title = (document.title || '').replace(/\s*—\s*ScaffoldPro$/, '');
    const docNumber = (document.querySelector('[data-doc-number], .doc-number, #doc-number') || {}).textContent || '';
    const sel = (window.getSelection && String(window.getSelection())) || '';
    const panel = document.getElementById('as-float');
    const selection = panel && window.getSelection && window.getSelection().anchorNode && panel.contains(window.getSelection().anchorNode) ? '' : sel.trim().slice(0, 2000);
    // What the page shows (the floating chat itself left out).
    const content = document.getElementById('content');
    let screen = '';
    if (content) screen = (content.innerText || '').replace(/\n{3,}/g, '\n\n').trim().slice(0, 8000);
    const label = [title || heading.trim() || page, docNumber.trim()].filter(Boolean).join(' · ');
    return {
      label: label || 'this page',
      selection,
      payload: { page, title, heading: heading.trim(), id: params.get('id') || '', number: params.get('number') || '', selection, screen },
    };
  }

  // ---- the floating chat, on every page but the Assistant's own ----
  function initFloat() {
    const page = document.body && document.body.dataset.page;
    if (!page || page === 'assistant' || page === 'launch' || document.getElementById('as-float')) return;
    if (!window.api || !window.api.assistant) return;
    const launcher = document.createElement('button');
    launcher.type = 'button';
    launcher.className = 'as-launcher';
    launcher.dataset.noIcon = '';
    launcher.title = 'Assistant (⌘J) — ask about this page, or have it do something';
    launcher.setAttribute('aria-label', 'Open the Assistant');
    launcher.innerHTML = MARK;
    const panel = document.createElement('div');
    panel.id = 'as-float';
    panel.className = 'as-float hidden';
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', 'Assistant');
    document.body.append(launcher, panel);
    let chat = null;
    const isOpen = () => !panel.classList.contains('hidden');
    const remember = (v) => { try { sessionStorage.setItem(OPEN_KEY, v ? '1' : ''); } catch (e) { /* not kept */ } };
    // ---- where it is and how big: dragged by its top bar, resized from
    // any edge or corner; kept on this Mac (double-click the bar to put it
    // back by the button) ----
    const MIN_W = 320, MIN_H = 360, EDGE = 8;
    // Its place, leaving out the opening animation's scale.
    const rectOf = () => ({ left: panel.offsetLeft, top: panel.offsetTop, width: panel.offsetWidth, height: panel.offsetHeight,
      right: panel.offsetLeft + panel.offsetWidth });
    const readRect = () => { try { return JSON.parse(localStorage.getItem(RECT_KEY) || 'null'); } catch (e) { return null; } };
    const saveRect = () => {
      if (panel.classList.contains('hidden')) return;
      const r = rectOf();
      try { localStorage.setItem(RECT_KEY, JSON.stringify({ left: r.left, top: r.top, width: r.width, height: r.height })); } catch (e) { /* not kept */ }
    };
    // Kept on screen, however the window was resized meanwhile.
    function place(rect) {
      const vw = window.innerWidth, vh = window.innerHeight;
      const width = Math.max(MIN_W, Math.min(rect.width, vw - EDGE * 2));
      const height = Math.max(MIN_H, Math.min(rect.height, vh - EDGE - (window.__scaffoldProWeb ? EDGE : 44)));
      const left = Math.max(EDGE, Math.min(rect.left, vw - width - EDGE));
      // In the Mac app the top 40px is the window's title bar (drag strip):
      // the chat's own bar is kept below it, where its buttons can be clicked.
      const topEdge = window.__scaffoldProWeb ? EDGE : 44;
      const top = Math.max(topEdge, Math.min(rect.top, vh - height - EDGE));
      Object.assign(panel.style, { left: `${left}px`, top: `${top}px`, width: `${width}px`, height: `${height}px`, right: 'auto', bottom: 'auto' });
    }
    function placeSaved() {
      const saved = readRect();
      if (saved) { place(saved); return; }
      // First time: by the button, bottom right — then left/top from there on.
      Object.assign(panel.style, { left: '', top: '', width: '', height: '', right: '', bottom: '' });
      const r = rectOf();
      place({ left: r.left, top: r.top, width: r.width, height: r.height });
    }
    // Past an edge it still follows, with more and more resistance; let go
    // and it springs back on screen (critically damped). Grabbing it while
    // it settles carries on from where it is.
    const rubberband = (over, dim) => (over * dim * 0.55) / (dim + 0.55 * Math.abs(over));
    const soft = (v, lo, hi, dim) => (v < lo ? lo + rubberband(v - lo, dim) : v > hi ? hi + rubberband(v - hi, dim) : v);
    let settleTimer = 0;
    function grab(e, el) {
      clearTimeout(settleTimer);
      panel.style.transition = 'none';
      if (el.setPointerCapture) { try { el.setPointerCapture(e.pointerId); } catch (err) { /* fine */ } }
    }
    function settle() {
      const before = rectOf();
      panel.style.transition = 'left .32s var(--spring), top .32s var(--spring), width .32s var(--spring), height .32s var(--spring)';
      place(before);
      settleTimer = setTimeout(() => { panel.style.transition = ''; saveRect(); }, 340);
    }
    function track(e, el, onMove, onEnd) {
      const move = (ev) => { if (ev.pointerId === e.pointerId) onMove(ev); };
      const up = (ev) => {
        if (ev.pointerId !== undefined && ev.pointerId !== e.pointerId) return;
        el.removeEventListener('pointermove', move);
        el.removeEventListener('pointerup', up);
        el.removeEventListener('pointercancel', up);
        window.removeEventListener('blur', up);
        onEnd();
      };
      el.addEventListener('pointermove', move);
      el.addEventListener('pointerup', up);
      el.addEventListener('pointercancel', up);
      window.addEventListener('blur', up);
    }
    function startDrag(e) {
      if (e.button !== 0 || e.target.closest('button, a, input, textarea, select')) return;
      e.preventDefault();
      const head = e.currentTarget;
      grab(e, head);
      const r = rectOf();
      const dx = e.clientX - r.left, dy = e.clientY - r.top;
      const topEdge = window.__scaffoldProWeb ? EDGE : 44;
      panel.classList.add('dragging');
      document.body.classList.add('as-dragging');
      track(e, head, (ev) => {
        const left = soft(ev.clientX - dx, EDGE, window.innerWidth - r.width - EDGE, r.width);
        const top = soft(ev.clientY - dy, topEdge, window.innerHeight - r.height - EDGE, r.height);
        Object.assign(panel.style, { left: `${left}px`, top: `${top}px`, width: `${r.width}px`, height: `${r.height}px`, right: 'auto', bottom: 'auto' });
      }, () => {
        panel.classList.remove('dragging');
        document.body.classList.remove('as-dragging');
        settle();
      });
    }
    // Resizing from any edge or corner: `dir` is the sides being moved
    // (n, s, e, w, ne, nw, se, sw).
    function startResize(e, dir) {
      if (e.button !== 0) return;
      e.preventDefault();
      e.stopPropagation();
      const grip = e.currentTarget;
      grab(e, grip);
      const r = rectOf();
      const x0 = e.clientX, y0 = e.clientY;
      panel.classList.add('dragging');
      document.body.classList.add('as-dragging', `as-resizing-${dir}`);
      track(e, grip, (ev) => {
        const dx = ev.clientX - x0, dy = ev.clientY - y0;
        let { left, top, width, height } = r;
        if (dir.includes('e')) width = Math.max(MIN_W, r.width + dx);
        if (dir.includes('s')) height = Math.max(MIN_H, r.height + dy);
        if (dir.includes('w')) { width = Math.max(MIN_W, r.width - dx); left = r.left + r.width - width; }
        if (dir.includes('n')) { height = Math.max(MIN_H, r.height - dy); top = r.top + r.height - height; }
        place({ left, top, width, height });
      }, () => {
        panel.classList.remove('dragging');
        document.body.classList.remove('as-dragging', `as-resizing-${dir}`);
        panel.style.transition = '';
        saveRect();
      });
    }
    function wireMoving() {
      const head = panel.querySelector('.as-head');
      head.classList.add('as-drag-handle');
      head.title = 'Drag to move · double-click to put it back';
      head.addEventListener('pointerdown', startDrag);
      head.addEventListener('dblclick', (e) => {
        if (e.target.closest('button')) return;
        try { localStorage.removeItem(RECT_KEY); } catch (err) { /* fine */ }
        placeSaved();
      });
      // A handle on each edge and corner.
      for (const dir of ['n', 's', 'e', 'w', 'ne', 'nw', 'se', 'sw']) {
        const grip = document.createElement('div');
        grip.className = `as-resize as-resize-${dir}`;
        grip.setAttribute('aria-hidden', 'true');
        grip.addEventListener('pointerdown', (e) => startResize(e, dir));
        panel.appendChild(grip);
      }
      window.addEventListener('resize', () => { if (isOpen()) place(rectOf()); });
    }

    function open(animate = true) {
      if (!chat) { chat = mount(panel, { compact: true, context: pageContext, onClose: close }); wireMoving(); }
      else chat.refresh();
      panel.classList.remove('hidden');
      placeSaved();
      panel.classList.toggle('no-anim', !animate);
      launcher.classList.add('open');
      remember(true);
      setTimeout(() => chat.focus(), animate ? 120 : 0);
    }
    function close() {
      panel.classList.add('hidden');
      launcher.classList.remove('open');
      remember(false);
      launcher.focus();
    }
    launcher.addEventListener('click', () => (isOpen() ? close() : open()));
    document.addEventListener('keydown', (e) => {
      if ((e.metaKey || e.ctrlKey) && !e.shiftKey && !e.altKey && e.key.toLowerCase() === 'j') {
        e.preventDefault();
        if (isOpen() && panel.contains(document.activeElement)) close(); else open();
      }
    });
    // Still open from the page before: open straight away, without the animation.
    let wasOpen = false;
    try { wasOpen = sessionStorage.getItem(OPEN_KEY) === '1'; } catch (e) { wasOpen = false; }
    if (wasOpen) open(false);
  }

  // Steps of a run, from main.swift, to the chat waiting for it.
  window.__assistantStep = (step) => { const fn = step && listeners.get(step.runId); if (fn) fn(step.text); };
  window.AssistantChat = { mount, pageContext, _listeners: listeners };
  const start = () => {
    const page = document.body.dataset.page;
    if (page === 'assistant') {
      const root = document.getElementById('as-root');
      const chat = mount(root, {});
      chat.focus();
      // Another Mac's changes (the AI connection may have been set up there).
      window.appRefresh = () => chat.refresh();
    } else {
      initFloat();
    }
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();

'use strict';

// The assistant: a conversation with the team's AI (Settings › AI Import).
// It looks things up itself (projects, clients, the material list, stock,
// quotations, invoices, tasks) and proposes work as cards — a quotation,
// lines for one, changes to a draft, a project, a client, a task or event —
// carried out only when the card's button is pressed (assistant:run).
// Files can be attached (button, drop or paste); the Mac reads them and the
// AI sees them too.
//
// Two places, one conversation (kept on this Mac, in localStorage):
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
  const KEY = 'assistant.chat';
  const OPEN_KEY = 'assistant.floatOpen';
  const RECT_KEY = 'assistant.floatRect';
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

  // ---- the conversation, shared by both places ----
  function load() {
    try { const c = JSON.parse(localStorage.getItem(KEY) || 'null'); if (c && Array.isArray(c.messages)) return c; } catch (e) { /* new */ }
    return { messages: [] };
  }
  function save(chat) {
    try { localStorage.setItem(KEY, JSON.stringify({ messages: chat.messages.slice(-80) })); } catch (e) { /* not kept */ }
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
    createProject: 'New project', createClient: 'New client', completeTask: 'Mark task done' };
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
    if (p.type === 'createQuotation' || p.type === 'addQuotationItems') {
      title = p.type === 'createQuotation'
        ? `New ${String(p.pricingMode || 'Rental').toLowerCase()} quotation · ${esc(p.projectNumber || '?')}${p.projectName ? ` ${esc(p.projectName)}` : ''}`
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
      body = `${p.subject ? `<div class="as-card-sub">Re: ${esc(p.subject)}</div>` : ''}
        <div class="as-table-wrap"><table class="as-items">
          <thead><tr><th class="as-th-no">#</th><th>Item</th><th>Qty</th><th>Unit price</th><th>Total</th><th></th></tr></thead>
          <tbody>${rows}</tbody>
          <tfoot><tr><td></td><td>${(p.items || []).length} line${(p.items || []).length === 1 ? '' : 's'}</td><td></td><td></td><td class="as-it-total"><b>${money(itemsTotal(p.items))}</b></td><td></td></tr></tfoot>
        </table></div>`;
      button = p.type === 'createQuotation' ? 'Create Quotation' : `Add ${(p.items || []).length} Line${(p.items || []).length === 1 ? '' : 's'}`;
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
    root.innerHTML = `
      <header class="as-head">
        <div class="as-head-text">
          ${compact ? `<span class="as-head-mark">${MARK}</span><b class="as-head-title">Assistant</b>` : '<h1>Assistant</h1>'}
          <span class="as-status" data-r="status"></span>
        </div>
        <div class="as-head-actions">
          <button type="button" class="as-new" data-r="new" data-no-icon title="Start a new conversation${compact ? '' : ' (⌘N)'}">${SVG.plus}${compact ? '' : 'New Chat'}</button>
          ${compact ? `<button type="button" class="as-icon-btn" data-r="expand" data-no-icon title="Open the Assistant page">${SVG.expand}</button>
          <button type="button" class="as-icon-btn" data-r="close" data-no-icon title="Close (Esc)">${SVG.close}</button>` : ''}
        </div>
      </header>
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
      <div class="as-drop hidden" data-r="drop"><div><b>Drop to attach</b><span>PDF, pictures, Excel, Word or text</span></div></div>`;
    const $ = (r) => root.querySelector(`[data-r="${r}"]`);
    let chat = load();
    let pending = [];
    let busy = false;
    let aiReady = true;
    let thinkingText = 'Thinking…';
    let thinkingTimer = null;

    function messageHTML(m, mi) {
      if (m.role === 'user') {
        const files = (m.files || []).map((f) => `<span class="as-file-chip sent">${fileIcon(f.name)}${esc(f.name)}</span>`).join('');
        const where = m.where ? `<div class="as-where">${esc(m.where)}</div>` : '';
        return `<div class="as-msg user" data-mi="${mi}">${files ? `<div class="as-msg-files">${files}</div>` : ''}${m.text ? `<div class="as-bubble">${rich(m.text)}</div>` : ''}${where}</div>`;
      }
      if (m.error) {
        return `<div class="as-msg bot error" data-mi="${mi}"><span class="as-avatar">${MARK}</span><div class="as-body">
          <div class="as-error">${esc(m.error)}</div>
          ${mi === chat.messages.length - 1 ? '<button type="button" class="as-retry" data-act="retry" data-no-icon>Try Again</button>' : ''}</div></div>`;
      }
      const cards = (m.proposals || []).map((p, pi) => card(p, mi, pi)).join('');
      return `<div class="as-msg bot" data-mi="${mi}"><span class="as-avatar">${MARK}</span><div class="as-body">
        ${m.text ? `<div class="as-text">${rich(m.text)}</div>` : ''}${cards}</div></div>`;
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
      box.innerHTML = chat.messages.length ? chat.messages.map(messageHTML).join('') : emptyHTML();
      if (busy) box.insertAdjacentHTML('beforeend', `<div class="as-msg bot thinking"><span class="as-avatar">${MARK}</span><div class="as-body"><span class="as-dots"><i></i><i></i><i></i></span><span class="as-thinking-text" data-r="thinking">${esc(thinkingText)}</span></div></div>`);
      $('new').disabled = !chat.messages.length || busy;
      if (scroll) requestAnimationFrame(() => { const s = $('scroll'); s.scrollTop = s.scrollHeight; });
      drawContext();
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

    function setThinking(withFiles) {
      const steps = withFiles
        ? ['Reading the file…', 'Reading the file…', 'Looking things up…', 'Preparing it…', 'Still working — big files take a while…']
        : ['Thinking…', 'Looking things up…', 'Preparing it…', 'Still working…'];
      let i = 0;
      thinkingText = steps[0];
      clearInterval(thinkingTimer);
      thinkingTimer = setInterval(() => {
        i = Math.min(i + 1, steps.length - 1);
        thinkingText = steps[i];
        const t = $('thinking');
        if (t) t.textContent = thinkingText;
      }, 4500);
    }

    // What the AI is sent: each message's text (its proposals summed up) and
    // the text of files sent before.
    function history() {
      return chat.messages.filter((m) => !m.error).map((m) => {
        let text = m.text || '';
        if (m.role === 'assistant' && (m.proposals || []).length) {
          text += '\n\n(Proposed: ' + m.proposals.map((p) => `${p.type}${p.projectNumber ? ` for ${p.projectNumber}` : ''}${p.quotationNumber ? ` to ${p.quotationNumber}` : ''}${p.items ? ` with ${p.items.length} items` : ''}${p._state === 'done' ? ` — done: ${(p._result && p._result.message) || ''}` : p._state === 'dismissed' ? ' — dismissed' : ''}`).join('; ') + ')';
        }
        return { role: m.role === 'assistant' ? 'assistant' : 'user', text, files: (m.files || []).filter((f) => f.text).map((f) => ({ name: f.name, text: f.text })) };
      });
    }

    async function send(textArg) {
      const text = (textArg ?? $('input').value).trim();
      if (busy || (!text && !pending.length)) return;
      if (!aiReady) { notReady(); return; }
      const files = pending;
      pending = [];
      drawFiles();
      $('input').value = '';
      autosize();
      chat = load(); // the other place may have added to it
      const ctx = opts.context ? opts.context() : null;
      chat.messages.push({ role: 'user', text, files: files.map((f) => ({ name: f.name })), where: ctx ? `On ${ctx.label}` : undefined });
      save(chat);
      await ask(files, ctx);
    }

    async function ask(files, ctx) {
      busy = true;
      setThinking(files.length > 0);
      draw();
      updateSend();
      let r;
      try {
        r = await window.api.assistant.send(history(), files.map((f) => ({ name: f.name, mime: f.mime, base64: f.base64 })), ctx && ctx.payload);
      } catch (e) {
        r = { ok: false, error: e.message || 'The assistant couldn’t be reached.' };
      }
      clearInterval(thinkingTimer);
      busy = false;
      const last = [...chat.messages].reverse().find((m) => m.role === 'user');
      if (last && r && Array.isArray(r.files) && r.files.length) last.files = r.files.map((f) => ({ name: f.name, text: f.text }));
      if (!r || r.ok === false) chat.messages.push({ role: 'assistant', error: (r && r.error) || 'Something went wrong.' });
      else chat.messages.push({ role: 'assistant', text: r.reply || (r.proposals && r.proposals.length ? '' : 'Done.'), proposals: r.proposals || [] });
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
    function updateSend() { $('send').disabled = busy || (!$('input').value.trim() && !pending.length); }

    // ---- wiring ----
    const input = $('input');
    input.addEventListener('input', () => { autosize(); updateSend(); });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); send(); }
      if (e.key === 'Escape' && compact && opts.onClose) { e.preventDefault(); e.stopPropagation(); opts.onClose(); }
    });
    input.addEventListener('paste', (e) => {
      const files = [...(e.clipboardData ? e.clipboardData.files : [])];
      if (files.length) { e.preventDefault(); addFiles(files); }
    });
    input.addEventListener('focus', drawContext);
    $('send').addEventListener('click', () => send());
    $('attach').addEventListener('click', () => $('file').click());
    $('file').addEventListener('change', (e) => { addFiles([...e.target.files]); e.target.value = ''; });
    $('files').addEventListener('click', (e) => {
      const b = e.target.closest('[data-unfile]');
      if (b) { pending.splice(Number(b.dataset.unfile), 1); drawFiles(); }
    });
    $('new').addEventListener('click', async () => {
      if (!chat.messages.length) return;
      if (!await window.appConfirm('Start a new conversation?\n\nThis one is cleared from this Mac. Anything already made stays.', { ok: 'New Chat' })) return;
      chat = { messages: [] };
      save(chat);
      draw();
      input.focus();
    });
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
      refresh() { if (!busy) { chat = load(); draw(); } checkStatus(); },
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
      const height = Math.max(MIN_H, Math.min(rect.height, vh - EDGE * 2));
      const left = Math.max(EDGE, Math.min(rect.left, vw - width - EDGE));
      const top = Math.max(EDGE, Math.min(rect.top, vh - height - EDGE));
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
    function startDrag(e) {
      if (e.button !== 0 || e.target.closest('button, a, input, textarea, select')) return;
      e.preventDefault();
      const r = rectOf();
      const dx = e.clientX - r.left, dy = e.clientY - r.top;
      panel.classList.add('dragging');
      document.body.classList.add('as-dragging');
      const move = (ev) => place({ left: ev.clientX - dx, top: ev.clientY - dy, width: r.width, height: r.height });
      const up = () => {
        panel.classList.remove('dragging');
        document.body.classList.remove('as-dragging');
        window.removeEventListener('mousemove', move);
        window.removeEventListener('mouseup', up);
        saveRect();
      };
      window.addEventListener('mousemove', move);
      window.addEventListener('mouseup', up);
    }
    // Resizing from any edge or corner: `dir` is the sides being moved
    // (n, s, e, w, ne, nw, se, sw).
    function startResize(e, dir) {
      if (e.button !== 0) return;
      e.preventDefault();
      e.stopPropagation();
      const r = rectOf();
      const x0 = e.clientX, y0 = e.clientY;
      panel.classList.add('dragging');
      document.body.classList.add('as-dragging', `as-resizing-${dir}`);
      const move = (ev) => {
        const dx = ev.clientX - x0, dy = ev.clientY - y0;
        let { left, top, width, height } = r;
        if (dir.includes('e')) width = Math.max(MIN_W, r.width + dx);
        if (dir.includes('s')) height = Math.max(MIN_H, r.height + dy);
        if (dir.includes('w')) { width = Math.max(MIN_W, r.width - dx); left = r.left + r.width - width; }
        if (dir.includes('n')) { height = Math.max(MIN_H, r.height - dy); top = r.top + r.height - height; }
        place({ left, top, width, height });
      };
      const up = () => {
        panel.classList.remove('dragging');
        document.body.classList.remove('as-dragging', `as-resizing-${dir}`);
        window.removeEventListener('mousemove', move);
        window.removeEventListener('mouseup', up);
        saveRect();
      };
      window.addEventListener('mousemove', move);
      window.addEventListener('mouseup', up);
    }
    function wireMoving() {
      const head = panel.querySelector('.as-head');
      head.classList.add('as-drag-handle');
      head.title = 'Drag to move · double-click to put it back';
      head.addEventListener('mousedown', startDrag);
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
        grip.addEventListener('mousedown', (e) => startResize(e, dir));
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

  window.AssistantChat = { mount, pageContext };
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

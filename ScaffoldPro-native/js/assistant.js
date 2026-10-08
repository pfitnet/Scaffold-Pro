'use strict';

// The assistant (assistant.html): a conversation with the team's AI
// (Settings › AI). It can look things up itself (projects, the material
// list, quotations) and proposes work as cards: a new quotation, items for
// a quotation, a task, a page to open. Nothing is made until the card's
// button is pressed (assistant:run). Files can be attached (button, drop
// or paste); the Mac reads them and the AI sees them too.
//
// The conversation is kept on this Mac (localStorage), files as the text
// read from them.

(function () {
  const KEY = 'assistant.chat';
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const money = (n) => Number(n || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const $ = (id) => document.getElementById(id);
  const MARK = '<svg viewBox="0 0 20 20" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 2.5 11.6 7.4 16.5 9 11.6 10.6 10 15.5 8.4 10.6 3.5 9 8.4 7.4z"/><path d="M15.5 13.5l.6 1.7 1.7.6-1.7.6-.6 1.7-.6-1.7-1.7-.6 1.7-.6z"/></svg>';
  const SUGGESTIONS = [
    { title: 'Quotation from a file', text: 'Make a quotation for project ', hint: 'Attach a quotation, BOQ or list, then say which project.', attach: true },
    { title: 'Quotation from a list', text: 'Make a rental quotation for project 26219 with:\n- 200 2.0m standards\n- 400 1.8m ledgers\n- delivery 2 trips', hint: 'Type the items; it finds them in the material list and prices them.' },
    { title: 'Find prices', text: 'What are the rental and sale prices of the 2.0m standard and the 1.8m ledger?' },
    { title: 'Add a task', text: 'Remind me on Friday to chase the signed quotation for 26219.' },
  ];

  let chat = load();
  let pending = []; // files for the next message: { name, mime, base64, size }
  let busy = false;
  let aiReady = true;

  function load() {
    try { const c = JSON.parse(localStorage.getItem(KEY) || 'null'); if (c && Array.isArray(c.messages)) return c; } catch (e) { /* new */ }
    return { messages: [] };
  }
  function save() {
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

  // ---- the proposals ----
  const KIND_TITLE = { createQuotation: 'New quotation', addQuotationItems: 'Add to quotation', createTask: 'New task', open: 'Open' };
  function itemsTotal(items) { return (items || []).reduce((a, i) => a + (Number(i.quantity) || 0) * (Number(i.unitPrice) || 0), 0); }

  function card(p, mi, pi) {
    const state = p._state || '';
    const problems = (p.problems || []).map((x) => `<li>${esc(x)}</li>`).join('');
    const blocking = (p.problems || []).some((x) => /no project|no quotation|only a draft|no items|no title|isn't a date|can't do|couldn't be found/i.test(x));
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
          <thead><tr><th>#</th><th>Item</th><th>Qty</th><th>Unit price</th><th>Total</th><th></th></tr></thead>
          <tbody>${rows}</tbody>
          <tfoot><tr><td></td><td>${(p.items || []).length} line${(p.items || []).length === 1 ? '' : 's'}</td><td></td><td></td><td class="as-it-total"><b>${money(itemsTotal(p.items))}</b></td><td></td></tr></tfoot>
        </table></div>`;
      button = p.type === 'createQuotation' ? 'Create Quotation' : `Add ${(p.items || []).length} Line${(p.items || []).length === 1 ? '' : 's'}`;
    } else if (p.type === 'createTask') {
      title = `New task${p.projectNumber ? ` · ${esc(p.projectNumber)}` : ''}`;
      const when = [p.dueDate ? (window.appDay ? window.appDay(p.dueDate) : p.dueDate) : '', p.dueTime || ''].filter(Boolean).join(' ');
      body = `<div class="as-task"><b>${esc(p.title)}</b>${when ? `<span>Due ${esc(when)}</span>` : ''}${p.assignee ? `<span>For ${esc(p.assignee)}</span>` : ''}${p.notes ? `<span>${esc(p.notes)}</span>` : ''}</div>`;
      button = 'Add Task';
    } else if (p.type === 'open') {
      title = `Open ${esc(p.number || '')}`;
      button = 'Open';
    }
    const done = state === 'done'
      ? `<div class="as-done"><span class="as-check">✓</span><span>${esc((p._result && p._result.message) || 'Done.')}</span>${p._result && p._result.href ? `<button type="button" class="as-open" data-href="${esc(p._result.href)}" data-no-icon>Open</button>` : ''}</div>`
      : state === 'dismissed' ? '<div class="as-done muted">Dismissed.</div>' : '';
    return `<div class="as-card${state ? ` ${state}` : ''}" data-mi="${mi}" data-pi="${pi}">
      <div class="as-card-head"><span class="as-card-icon">${p.type === 'createTask' ? '✓' : p.type === 'open' ? '↗' : '¶'}</span><span class="as-card-title">${title}</span></div>
      ${body}
      ${problems ? `<ul class="as-problems">${problems}</ul>` : ''}
      ${done || `<div class="as-card-actions">
        <button type="button" class="as-dismiss" data-act="dismiss" data-no-icon>Dismiss</button>
        <button type="button" class="primary" data-act="run" ${blocking ? 'disabled' : ''} data-no-icon>${button}</button>
      </div>`}
    </div>`;
  }

  // ---- drawing ----
  function messageHTML(m, mi) {
    if (m.role === 'user') {
      const files = (m.files || []).map((f) => `<span class="as-file-chip sent">${fileIcon(f.name)}${esc(f.name)}</span>`).join('');
      return `<div class="as-msg user" data-mi="${mi}">${files ? `<div class="as-msg-files">${files}</div>` : ''}${m.text ? `<div class="as-bubble">${rich(m.text)}</div>` : ''}</div>`;
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
    return `<div class="as-empty">
      <div class="as-empty-mark">${MARK}</div>
      <h2>What shall we do?</h2>
      <p>Ask about prices and projects, or have it prepare a quotation from a file or a list. It looks things up in ScaffoldPro itself, and shows you what it would do before anything is made.</p>
      <div class="as-suggest">${SUGGESTIONS.map((s, i) => `<button type="button" class="as-sug" data-sug="${i}" data-no-icon><b>${esc(s.title)}</b><span>${esc(s.hint || s.text.split('\n')[0])}</span></button>`).join('')}</div>
    </div>`;
  }

  function draw(scroll = true) {
    const box = $('as-messages');
    box.innerHTML = chat.messages.length ? chat.messages.map(messageHTML).join('') : emptyHTML();
    if (busy) box.insertAdjacentHTML('beforeend', `<div class="as-msg bot thinking"><span class="as-avatar">${MARK}</span><div class="as-body"><span class="as-dots"><i></i><i></i><i></i></span><span class="as-thinking-text" id="as-thinking-text">${esc(thinkingText)}</span></div></div>`);
    $('as-new').disabled = !chat.messages.length || busy;
    if (scroll) requestAnimationFrame(() => { const s = $('as-scroll'); s.scrollTop = s.scrollHeight; });
  }

  // ---- files ----
  function fileIcon(name) {
    const ext = String(name).split('.').pop().toLowerCase();
    const label = ext === 'pdf' ? 'PDF' : ['xlsx', 'xlsm', 'csv', 'tsv'].includes(ext) ? 'XLS' : ['doc', 'docx', 'rtf'].includes(ext) ? 'DOC' : ['png', 'jpg', 'jpeg', 'heic', 'webp', 'gif', 'tif', 'tiff'].includes(ext) ? 'IMG' : 'TXT';
    return `<span class="as-file-kind k-${label.toLowerCase()}">${label}</span>`;
  }
  function drawFiles() {
    const box = $('as-files');
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
        const base64 = String(reader.result).split(',')[1] || '';
        pending.push({ name: file.name || 'Pasted picture.png', mime: file.type, base64, size: file.size });
        drawFiles();
      };
      reader.readAsDataURL(file);
    }
  }

  // ---- sending ----
  let thinkingText = 'Thinking…';
  let thinkingTimer = null;
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
      const t = $('as-thinking-text');
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
    const text = (textArg ?? $('as-input').value).trim();
    if (busy || (!text && !pending.length)) return;
    if (!aiReady) { notReady(); return; }
    const files = pending;
    pending = [];
    drawFiles();
    $('as-input').value = '';
    autosize();
    chat.messages.push({ role: 'user', text, files: files.map((f) => ({ name: f.name })) });
    save();
    await ask(files);
  }

  async function ask(files) {
    busy = true;
    setThinking(files.length > 0);
    draw();
    updateSend();
    let r;
    try {
      r = await window.api.assistant.send(history(), files.map((f) => ({ name: f.name, mime: f.mime, base64: f.base64 })));
    } catch (e) {
      r = { ok: false, error: e.message || 'The assistant couldn’t be reached.' };
    }
    clearInterval(thinkingTimer);
    busy = false;
    // The files' text, kept with the message for the rest of the conversation.
    const last = [...chat.messages].reverse().find((m) => m.role === 'user');
    if (last && r && Array.isArray(r.files) && r.files.length) last.files = r.files.map((f) => ({ name: f.name, text: f.text }));
    if (!r || r.ok === false) chat.messages.push({ role: 'assistant', error: (r && r.error) || 'Something went wrong.' });
    else chat.messages.push({ role: 'assistant', text: r.reply || (r.proposals && r.proposals.length ? '' : 'Done.'), proposals: r.proposals || [] });
    save();
    draw();
    updateSend();
    $('as-input').focus();
  }

  async function runProposal(mi, pi, button) {
    if (document.activeElement && document.activeElement.blur) document.activeElement.blur();
    const p = chat.messages[mi].proposals[pi];
    if (p.type === 'open') { if (p.href) window.appNavigate ? window.appNavigate(p.href) : (location.href = p.href); return; }
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
    save();
    draw(false);
  }

  // ---- the AI's status ----
  async function checkStatus() {
    let s = null;
    try { s = await window.api.ai.status(); } catch (e) { s = null; }
    aiReady = !!(s && s.hasKey);
    const names = { gemini: 'Google Gemini', openrouter: 'OpenRouter' };
    $('as-status').innerHTML = aiReady
      ? `<span class="as-dot on"></span>${esc(names[s.provider] || s.provider)} · ${esc(s.model || s.defaultModel || '')}`
      : '<span class="as-dot"></span>No AI connected — <a href="settings.html#ai-import">set one up in Settings</a>';
    updateSend();
  }
  function notReady() {
    window.appAlert('No AI is connected yet.\n\nAdd a free key in Settings › AI Import, then come back.');
  }

  // ---- composer ----
  function autosize() {
    const t = $('as-input');
    t.style.height = 'auto';
    t.style.height = `${Math.min(220, t.scrollHeight)}px`;
  }
  function updateSend() {
    $('as-send').disabled = busy || (!$('as-input').value.trim() && !pending.length);
  }

  function wire() {
    const input = $('as-input');
    input.addEventListener('input', () => { autosize(); updateSend(); });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Enter' && !e.shiftKey && !e.isComposing) { e.preventDefault(); send(); }
    });
    input.addEventListener('paste', (e) => {
      const files = [...(e.clipboardData ? e.clipboardData.files : [])];
      if (files.length) { e.preventDefault(); addFiles(files); }
    });
    $('as-send').addEventListener('click', () => send());
    $('as-attach').addEventListener('click', () => $('as-file').click());
    $('as-file').addEventListener('change', (e) => { addFiles([...e.target.files]); e.target.value = ''; });
    $('as-files').addEventListener('click', (e) => {
      const b = e.target.closest('[data-unfile]');
      if (b) { pending.splice(Number(b.dataset.unfile), 1); drawFiles(); }
    });
    $('as-new').addEventListener('click', async () => {
      if (!chat.messages.length) return;
      if (!await window.appConfirm('Start a new conversation?\n\nThis one is cleared from this Mac. Anything already made stays.', { ok: 'New Chat' })) return;
      chat = { messages: [] };
      save();
      draw();
      input.focus();
    });
    document.addEventListener('keydown', (e) => {
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'n' && !e.shiftKey) { e.preventDefault(); $('as-new').click(); }
    });

    // Dropping files anywhere on the page.
    let depth = 0;
    const hasFiles = (e) => e.dataTransfer && [...e.dataTransfer.types].includes('Files');
    window.addEventListener('dragenter', (e) => { if (!hasFiles(e)) return; depth++; $('as-drop').classList.remove('hidden'); });
    window.addEventListener('dragleave', (e) => { if (!hasFiles(e)) return; depth = Math.max(0, depth - 1); if (!depth) $('as-drop').classList.add('hidden'); });
    window.addEventListener('dragover', (e) => { if (hasFiles(e)) e.preventDefault(); });
    window.addEventListener('drop', (e) => {
      if (!hasFiles(e)) return;
      e.preventDefault();
      depth = 0;
      $('as-drop').classList.add('hidden');
      addFiles([...e.dataTransfer.files]);
      input.focus();
    });

    // Messages: suggestions, cards, retry.
    $('as-messages').addEventListener('click', (e) => {
      const sug = e.target.closest('[data-sug]');
      if (sug) {
        const s = SUGGESTIONS[Number(sug.dataset.sug)];
        input.value = s.text;
        autosize();
        updateSend();
        input.focus();
        input.setSelectionRange(input.value.length, input.value.length);
        if (s.attach) $('as-file').click();
        return;
      }
      const open = e.target.closest('.as-open');
      if (open) { (window.appNavigate || ((h) => { location.href = h; }))(open.dataset.href); return; }
      const retry = e.target.closest('[data-act="retry"]');
      if (retry) {
        chat.messages.pop();
        save();
        ask([]);
        return;
      }
      const cardEl = e.target.closest('.as-card');
      if (!cardEl) return;
      const mi = Number(cardEl.dataset.mi), pi = Number(cardEl.dataset.pi);
      const p = chat.messages[mi].proposals[pi];
      const remove = e.target.closest('[data-remove]');
      if (remove) { p.items.splice(Number(remove.dataset.remove), 1); save(); draw(false); return; }
      const act = e.target.closest('[data-act]');
      if (!act) return;
      if (act.dataset.act === 'dismiss') { p._state = 'dismissed'; save(); draw(false); }
      if (act.dataset.act === 'run') runProposal(mi, pi, act);
    });
    // Editing a card's quantities and prices before it's made.
    $('as-messages').addEventListener('change', (e) => {
      const f = e.target.dataset && e.target.dataset.f;
      if (!f) return;
      const cardEl = e.target.closest('.as-card');
      const p = chat.messages[Number(cardEl.dataset.mi)].proposals[Number(cardEl.dataset.pi)];
      const it = p.items[Number(e.target.closest('tr').dataset.ii)];
      const v = Number(e.target.value);
      it[f] = f === 'quantity' ? Math.max(1, Math.round(v || 1)) : Math.max(0, Math.round((v || 0) * 100) / 100);
      if (f === 'unitPrice') delete it.priceFromList;
      save();
      e.target.blur();
      draw(false);
    });
  }

  document.addEventListener('DOMContentLoaded', () => {
    wire();
    draw();
    checkStatus();
    $('as-input').focus();
  });
  // Another Mac's changes (the AI connection may have been set up there).
  window.appRefresh = () => checkStatus();
})();

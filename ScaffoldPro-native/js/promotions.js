'use strict';

// Marketing › Promotions: campaigns to win new work. Each has who it's aimed
// at (leads, clients or anyone else), the promotional letter written for
// them ({Company} and {Contact} filled in for each), and how each answered —
// To Contact → Sent → Replied → Meeting → Won (or Not Interested).
// "Write Letters" makes a draft letter (PL26-001…) for each one ticked,
// opened and printed from Letters like any other.

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const nice = (iso) => { const d = new Date(iso || ''); return isNaN(d) ? '' : d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace('Sept', 'Sep'); };
  const CHANNELS = ['Letter', 'Email', 'Visit', 'Call', 'Event'];
  const STATES = ['Planning', 'Running', 'Done'];
  const STEPS = ['To Contact', 'Sent', 'Replied', 'Meeting', 'Won', 'Not Interested'];
  const STEP_CLASS = { 'To Contact': 'todo', Sent: 'sent', Replied: 'replied', Meeting: 'meeting', Won: 'won', 'Not Interested': 'no' };
  const DEFAULT_SUBJECT = 'Scaffolding Services — Introduction';
  const DEFAULT_BODY = '<p>Dear {Contact},</p>'
    + '<p>We are writing to introduce our scaffolding services to {Company}.</p>'
    + '<p>We design, supply and erect metal and bamboo scaffolding for construction, maintenance and fit-out works, with our own '
    + 'experienced crews, engineers and a large stock of materials ready for quick delivery. Every job comes with a clear quotation, '
    + 'delivery schedule and site support from start to dismantling.</p>'
    + '<p>We would welcome the chance to quote for your coming projects, or to visit your site to discuss your needs.</p>'
    + '<p>Please feel free to contact us at any time.</p>'
    + '<p>Yours faithfully,</p>';

  let started = false;
  let list = [];
  let current = null;     // the campaign shown (a copy, saved as it changes)
  let leads = [];
  let clients = [];
  let filter = '';        // a status picked in the funnel
  let saveTimer = null;
  let saving = Promise.resolve();

  const now = () => new Date().toISOString();
  const uid = () => `pt-${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;

  // ---- saving ----

  function queueSave() {
    clearTimeout(saveTimer);
    saveTimer = setTimeout(save, 600);
  }

  function save() {
    clearTimeout(saveTimer);
    saveTimer = null;
    if (!current) return saving;
    const copy = JSON.parse(JSON.stringify(current));
    saving = saving.then(async () => {
      const r = await window.api.promotions.save(copy);
      if (!r || r.ok === false) { window.appAlert((r && r.error) || 'The campaign couldn’t be saved.'); return; }
      const i = list.findIndex((p) => p.id === r.promotion.id);
      if (i >= 0) list[i] = r.promotion; else list.unshift(r.promotion);
      if (current && (current.id === r.promotion.id || !current.id)) { current.id = r.promotion.id; current.createdAt = r.promotion.createdAt; current.updatedAt = r.promotion.updatedAt; }
      drawCards();
    });
    return saving;
  }

  async function flush() { if (saveTimer) save(); await saving; }

  // ---- the list ----

  function progress(p) {
    const n = p.targets.length;
    const reached = p.targets.filter((t) => t.status !== 'To Contact').length;
    const won = p.targets.filter((t) => t.status === 'Won').length;
    return { n, reached, won };
  }

  function drawCards() {
    const box = document.getElementById('pr-cards');
    if (!list.length) {
      box.innerHTML = '<div class="pr-none">No campaigns yet.<br>Start one to write to the companies you’d like to work for.</div>';
      return;
    }
    box.innerHTML = list.map((p, i) => {
      const g = progress(p);
      const pct = g.n ? Math.round((g.reached / g.n) * 100) : 0;
      return `<button type="button" class="pr-card${current && current.id === p.id ? ' on' : ''}" data-id="${esc(p.id)}" style="--i:${Math.min(i, 10)}" data-no-icon>
        <span class="pr-card-top"><b>${esc(p.name)}</b><span class="pr-state s-${esc(p.status.toLowerCase())}">${esc(p.status)}</span></span>
        <span class="pr-card-meta">${esc(p.channel)} · ${g.n} target${g.n === 1 ? '' : 's'}${g.won ? ` · <em>${g.won} won</em>` : ''}</span>
        <span class="pr-track" title="${g.reached} of ${g.n} contacted"><i style="width:${pct}%"></i></span>
      </button>`;
    }).join('');
    box.querySelectorAll('.pr-card').forEach((b) => b.addEventListener('click', () => open(b.dataset.id)));
  }

  async function open(id) {
    await flush();
    const p = list.find((x) => x.id === id);
    current = p ? JSON.parse(JSON.stringify(p)) : null;
    filter = '';
    drawCards();
    drawDetail();
  }

  async function create() {
    await flush();
    current = { id: '', name: `New Campaign ${list.length + 1}`, channel: 'Letter', status: 'Planning', goal: '',
      subject: DEFAULT_SUBJECT, bodyHTML: DEFAULT_BODY, targets: [], createdAt: now(), updatedAt: now() };
    filter = '';
    drawDetail();
    await save();
    const name = document.getElementById('pr-name');
    if (name) { name.focus(); name.select(); }
  }

  // ---- one campaign ----

  function drawDetail() {
    const box = document.getElementById('pr-detail');
    if (!current) {
      box.innerHTML = `<div class="pr-blank"><div class="pr-blank-art" aria-hidden="true"><svg viewBox="0 0 48 48" width="44" height="44" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M8 20v8l22 10V10L8 20z"/><path d="M30 18c4 0 6 2.5 6 6s-2 6-6 6"/><path d="M12 28l3 10h5l-2-8"/></svg></div>
        <h2>Promotions</h2><p>Plan who to approach, write one promotional letter for all of them, and keep track of who replied.</p>
        <button type="button" class="primary" id="pr-new-2" data-no-icon>+ New Campaign</button></div>`;
      document.getElementById('pr-new-2').addEventListener('click', create);
      return;
    }
    const p = current;
    box.innerHTML = `
      <div class="pr-head">
        <input type="text" id="pr-name" class="pr-name" value="${esc(p.name)}" aria-label="Campaign name" />
        <button type="button" class="pr-del" id="pr-delete" title="Delete this campaign" data-no-icon>Delete…</button>
      </div>
      <div class="pr-fields">
        <label>How<select id="pr-channel">${CHANNELS.map((c) => `<option${c === p.channel ? ' selected' : ''}>${c}</option>`).join('')}</select></label>
        <label>Status<select id="pr-status">${STATES.map((c) => `<option${c === p.status ? ' selected' : ''}>${c}</option>`).join('')}</select></label>
        <label class="pr-goal">Goal<input type="text" id="pr-goal" value="${esc(p.goal || '')}" placeholder="e.g. 3 new main contractors by December" /></label>
      </div>
      <div class="pr-funnel" id="pr-funnel"></div>

      <section class="pr-block">
        <div class="pr-block-head"><h3>Who it’s for</h3>
          <span class="toolbar-spacer"></span>
          <button type="button" id="pr-add" data-no-icon>+ Add Targets…</button>
          <button type="button" class="primary" id="pr-write" data-no-icon>Write Letters</button>
        </div>
        <div id="pr-targets"></div>
      </section>

      <section class="pr-block">
        <div class="pr-block-head"><h3>The letter</h3><span class="small-note">Written for each target — <button type="button" class="pr-token" data-token="{Company}" data-no-icon>{Company}</button> and <button type="button" class="pr-token" data-token="{Contact}" data-no-icon>{Contact}</button> become their name and contact.</span></div>
        <label class="pr-subject">Re:<input type="text" id="pr-subject" value="${esc(p.subject || '')}" /></label>
        <div class="pr-paper"><div id="pr-body" class="pr-body" contenteditable="true" spellcheck="true">${p.bodyHTML || ''}</div></div>
      </section>`;

    const bind = (id, key, ev = 'input') => document.getElementById(id).addEventListener(ev, (e) => { current[key] = e.target.value; queueSave(); if (key === 'name' || key === 'status' || key === 'channel') liveCard(); });
    bind('pr-name', 'name');
    bind('pr-channel', 'channel', 'change');
    bind('pr-status', 'status', 'change');
    bind('pr-goal', 'goal');
    bind('pr-subject', 'subject');
    const body = document.getElementById('pr-body');
    body.addEventListener('input', () => { current.bodyHTML = body.innerHTML; queueSave(); });
    let caret = null;
    body.addEventListener('blur', () => { const s = getSelection(); if (s.rangeCount && body.contains(s.anchorNode)) caret = s.getRangeAt(0).cloneRange(); });
    box.querySelectorAll('.pr-token').forEach((b) => {
      b.addEventListener('mousedown', (e) => e.preventDefault());
      b.addEventListener('click', () => {
        body.focus();
        if (caret) { const s = getSelection(); s.removeAllRanges(); s.addRange(caret); }
        document.execCommand('insertText', false, b.dataset.token);
      });
    });
    document.getElementById('pr-delete').addEventListener('click', remove);
    document.getElementById('pr-add').addEventListener('click', pickTargets);
    document.getElementById('pr-write').addEventListener('click', writeLetters);
    drawFunnel();
    drawTargets();
  }

  // The card on the left follows the name and status as they're typed.
  function liveCard() {
    const i = list.findIndex((x) => x.id === current.id);
    if (i >= 0) { list[i] = JSON.parse(JSON.stringify(current)); drawCards(); }
  }

  function drawFunnel() {
    const t = current.targets;
    const box = document.getElementById('pr-funnel');
    if (!t.length) { box.innerHTML = ''; return; }
    box.innerHTML = STEPS.map((s) => {
      const n = t.filter((x) => x.status === s).length;
      return `<button type="button" class="pr-step ${STEP_CLASS[s]}${filter === s ? ' on' : ''}" data-s="${esc(s)}" data-no-icon><b>${n}</b><span>${esc(s)}</span></button>`;
    }).join('<i class="pr-arrow" aria-hidden="true"></i>');
    box.querySelectorAll('.pr-step').forEach((b) => b.addEventListener('click', () => { filter = filter === b.dataset.s ? '' : b.dataset.s; drawFunnel(); drawTargets(); }));
  }

  function drawTargets() {
    const box = document.getElementById('pr-targets');
    const rows = current.targets.filter((t) => !filter || t.status === filter);
    if (!current.targets.length) {
      box.innerHTML = '<div class="pr-empty">No one yet — add leads, clients or any other company with <b>+ Add Targets…</b></div>';
      updateWrite();
      return;
    }
    box.innerHTML = `<table class="pr-table"><thead><tr><th class="pr-tick"><input type="checkbox" id="pr-all" title="Tick all shown" /></th><th>Company</th><th>Contact</th><th>Status</th><th>Letter</th><th>Last</th><th></th></tr></thead><tbody>
      ${rows.map((t, i) => `<tr data-id="${esc(t.id)}" style="--i:${Math.min(i, 14)}">
        <td class="pr-tick"><input type="checkbox" class="pr-check" /></td>
        <td><b>${esc(t.name)}</b> <span class="pr-kind k-${esc(t.kind.toLowerCase())}">${esc(t.kind)}</span>${t.note ? `<div class="pr-note">${esc(t.note)}</div>` : ''}</td>
        <td class="muted">${esc(t.contact || '')}</td>
        <td><select class="pr-status-sel ${STEP_CLASS[t.status] || ''}" aria-label="Status">${STEPS.map((s) => `<option${s === t.status ? ' selected' : ''}>${s}</option>`).join('')}</select></td>
        <td>${t.letterId ? `<a href="letter-editor.html?id=${encodeURIComponent(t.letterId)}" class="pr-letter">Open</a>` : '<span class="muted">—</span>'}</td>
        <td class="muted">${esc(nice(t.lastAt))}</td>
        <td class="pr-row-tools"><button type="button" class="pr-note-btn" title="Add a note" data-no-icon>✎</button><button type="button" class="pr-x" title="Take off this campaign" data-no-icon>×</button></td>
      </tr>`).join('')}
      </tbody></table>${filter ? `<div class="pr-filtered">Showing ${rows.length} “${esc(filter)}” · <button type="button" class="link-btn" id="pr-unfilter" data-no-icon>Show everyone</button></div>` : ''}`;
    const byId = (tr) => current.targets.find((t) => t.id === tr.dataset.id);
    box.querySelectorAll('tbody tr').forEach((tr) => {
      const t = byId(tr);
      tr.querySelector('.pr-status-sel').addEventListener('change', (e) => {
        t.status = e.target.value;
        t.lastAt = now();
        save(); drawFunnel(); drawTargets(); liveCard();
      });
      tr.querySelector('.pr-x').addEventListener('click', async () => {
        if (t.letterId && !await window.appConfirm(`Take ${t.name} off this campaign?\n\nIts letter stays in Letters.`, { ok: 'Take Off' })) return;
        current.targets = current.targets.filter((x) => x !== t);
        save(); drawFunnel(); drawTargets(); liveCard();
      });
      tr.querySelector('.pr-note-btn').addEventListener('click', async () => {
        const v = await window.appPrompt(`A note about ${t.name}`, t.note || '', { ok: 'Save', placeholder: 'e.g. Spoke to Mr. Chan — call back in March' });
        if (v === null) return;
        t.note = v.trim() || null;
        save(); drawTargets();
      });
      tr.querySelector('.pr-check').addEventListener('change', updateWrite);
    });
    document.getElementById('pr-all').addEventListener('change', (e) => { box.querySelectorAll('.pr-check').forEach((c) => { c.checked = e.target.checked; }); updateWrite(); });
    const un = document.getElementById('pr-unfilter');
    if (un) un.addEventListener('click', () => { filter = ''; drawFunnel(); drawTargets(); });
    updateWrite();
  }

  function ticked() {
    return [...document.querySelectorAll('#pr-targets .pr-check:checked')].map((c) => c.closest('tr').dataset.id);
  }

  // Ticked ones, or everyone without a letter yet.
  function updateWrite() {
    const b = document.getElementById('pr-write');
    if (!b) return;
    const t = ticked();
    const need = (t.length ? current.targets.filter((x) => t.includes(x.id)) : current.targets).filter((x) => !x.letterId);
    b.textContent = need.length ? `Write ${need.length} Letter${need.length === 1 ? '' : 's'}` : 'Write Letters';
    b.disabled = !need.length;
    b.title = need.length ? 'A draft letter for each, from the letter below' : 'Everyone here already has a letter';
  }

  async function writeLetters() {
    await flush();
    const t = ticked();
    const ids = (t.length ? current.targets.filter((x) => t.includes(x.id)) : current.targets).filter((x) => !x.letterId).map((x) => x.id);
    if (!ids.length) return;
    if (!/\{Company\}|\{Contact\}/.test(current.bodyHTML || '') && ids.length > 1
      && !await window.appConfirm(`Write ${ids.length} identical letters?\n\nThe letter doesn’t use {Company} or {Contact}, so every copy will read the same.`, { ok: 'Write Them' })) return;
    const r = await window.api.promotions.writeLetters(current.id, ids);
    if (!r || r.ok === false) { window.appAlert((r && r.error) || 'The letters couldn’t be written.'); return; }
    const i = list.findIndex((p) => p.id === r.promotion.id);
    if (i >= 0) list[i] = r.promotion;
    current = JSON.parse(JSON.stringify(r.promotion));
    drawCards(); drawDetail();
    const choice = await window.appChoose(`${ids.length} draft letter${ids.length === 1 ? '' : 's'} written.\n\nOpen each from the Letter column to check and print it, then mark it Sent.`,
      [{ label: 'Open Letters', value: 'letters' }, { label: 'OK', value: 'ok', primary: true }], { noCancel: true });
    if (choice === 'letters') location.href = 'letters.html';
  }

  async function remove() {
    const p = current;
    if (!await window.appConfirm(`Delete “${p.name}”?\n\nThe letters it wrote stay in Letters.`)) return;
    clearTimeout(saveTimer); saveTimer = null;
    await saving;
    if (p.id) await window.api.promotions.remove(p.id);
    list = list.filter((x) => x.id !== p.id);
    current = null;
    drawCards(); drawDetail();
  }

  // ---- adding targets: leads, clients, or anyone else ----

  function pickTargets() {
    const taken = new Set(current.targets.filter((t) => t.refId).map((t) => `${t.kind}:${t.refId}`));
    const addr = (c) => (c.billingInfo && c.billingInfo.trim() ? c.billingInfo.split('\n')
      : [c.address, c.addressLine2, c.addressLine3, [c.city, c.postalCode].filter(Boolean).join(' ')]).map((x) => (x || '').trim()).filter(Boolean).join('\n');
    const items = [
      ...leads.filter((l) => !l.clientId).map((l) => ({ kind: 'Lead', refId: l.id, name: l.company, contact: l.contactPerson || '', address: '', sub: `Lead · ${l.status}` })),
      ...clients.filter((c) => !c.isArchived).map((c) => ({ kind: 'Client', refId: c.id, name: c.companyName, contact: c.contactPerson || '', address: addr(c), sub: 'Client' })),
    ].filter((x) => !taken.has(`${x.kind}:${x.refId}`));
    const back = document.createElement('div');
    back.className = 'modal-backdrop pr-pick';
    back.innerHTML = `<div class="modal wide" role="dialog" aria-label="Add targets">
      <h2>Add Targets</h2>
      <div class="pr-pick-bar">
        <input type="text" class="pr-pick-search" placeholder="Search leads and clients" />
        <div class="segmented pr-pick-kind" role="group"><button type="button" data-k="" class="active" data-no-icon>All</button><button type="button" data-k="Lead" data-no-icon>Leads</button><button type="button" data-k="Client" data-no-icon>Clients</button></div>
      </div>
      <div class="pr-pick-list"></div>
      <details class="pr-other"><summary>Someone else — not a lead or client yet</summary>
        <div class="form-grid">
          <div class="field"><label>Company</label><input type="text" class="o-name" /></div>
          <div class="field"><label>Contact person</label><input type="text" class="o-contact" /></div>
          <div class="field span-2"><label>Address (one line each)</label><textarea class="o-address" rows="2"></textarea></div>
        </div>
      </details>
      <div class="actions"><span class="pr-pick-count small-note"></span><button type="button" class="o-cancel">Cancel</button><button type="button" class="primary o-add">Add</button></div>
    </div>`;
    document.body.appendChild(back);
    let kind = '';
    const chosen = new Set();
    const listBox = back.querySelector('.pr-pick-list');
    const search = back.querySelector('.pr-pick-search');
    const count = () => {
      const other = back.querySelector('.o-name').value.trim() ? 1 : 0;
      const n = chosen.size + other;
      back.querySelector('.pr-pick-count').textContent = n ? `${n} to add` : '';
      back.querySelector('.o-add').disabled = !n;
    };
    const draw = () => {
      const q = search.value.trim().toLowerCase();
      const shown = items.filter((x) => (!kind || x.kind === kind) && (!q || `${x.name} ${x.contact}`.toLowerCase().includes(q)));
      listBox.innerHTML = shown.length ? shown.map((x) => {
        const key = `${x.kind}:${x.refId}`;
        return `<label class="pr-pick-row${chosen.has(key) ? ' on' : ''}"><input type="checkbox" data-key="${esc(key)}"${chosen.has(key) ? ' checked' : ''} />
          <span><b>${esc(x.name)}</b><small>${esc(x.sub)}${x.contact ? ` · ${esc(x.contact)}` : ''}</small></span></label>`;
      }).join('') : `<div class="pr-empty">${items.length ? 'Nothing matches.' : 'Every lead and client is already in this campaign.'}</div>`;
      listBox.querySelectorAll('input').forEach((c) => c.addEventListener('change', () => {
        if (c.checked) chosen.add(c.dataset.key); else chosen.delete(c.dataset.key);
        c.closest('.pr-pick-row').classList.toggle('on', c.checked);
        count();
      }));
    };
    const close = () => { back.remove(); document.removeEventListener('keydown', onKey, true); };
    const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(); } };
    document.addEventListener('keydown', onKey, true);
    search.addEventListener('input', draw);
    back.querySelector('.o-name').addEventListener('input', count);
    back.querySelectorAll('.pr-pick-kind button').forEach((b) => b.addEventListener('click', () => {
      kind = b.dataset.k;
      back.querySelectorAll('.pr-pick-kind button').forEach((x) => x.classList.toggle('active', x === b));
      draw();
    }));
    back.addEventListener('mousedown', (e) => { if (e.target === back) close(); });
    back.querySelector('.o-cancel').addEventListener('click', close);
    back.querySelector('.o-add').addEventListener('click', () => {
      for (const x of items) {
        if (!chosen.has(`${x.kind}:${x.refId}`)) continue;
        current.targets.push({ id: uid(), kind: x.kind, refId: x.refId, name: x.name, contact: x.contact || null, address: x.address || null, status: 'To Contact', letterId: null, lastAt: null, note: null });
      }
      const name = back.querySelector('.o-name').value.trim();
      if (name) {
        current.targets.push({ id: uid(), kind: 'Other', refId: null, name, contact: back.querySelector('.o-contact').value.trim() || null,
          address: back.querySelector('.o-address').value.trim() || null, status: 'To Contact', letterId: null, lastAt: null, note: null });
      }
      close();
      save(); drawFunnel(); drawTargets(); liveCard();
    });
    draw(); count();
    search.focus();
  }

  // ---- start ----

  async function start() {
    if (started) return;
    started = true;
    document.getElementById('pr-new').addEventListener('click', create);
    const [l, ld, cl] = await Promise.all([window.api.promotions.list(), window.api.marketing.leads().catch(() => []), window.api.clients.list().catch(() => [])]);
    list = Array.isArray(l) ? l : [];
    leads = Array.isArray(ld) ? ld : [];
    clients = Array.isArray(cl) ? cl : [];
    current = list.length ? JSON.parse(JSON.stringify(list[0])) : null;
    drawCards();
    drawDetail();
    window.addEventListener('beforeunload', () => { if (saveTimer) save(); });
  }
  document.addEventListener('marketing:tab', (e) => { if (e.detail === 'promotions') start(); });
  // Opened straight on this tab (marketing.html?tab=promotions).
  if (document.querySelector('.tab-panel[data-panel="promotions"].active')) start();
})();

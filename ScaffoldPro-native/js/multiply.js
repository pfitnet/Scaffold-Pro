'use strict';

// "Multiply…": scales a document's quantities in one go, e.g. the client
// wants 2 sets of the same scaffold (×2), a spare 10% (×1.1), or half of it
// (×½). Works on every document with material lines — BOQs, quotations,
// invoices and delivery notes — on all the items, or only the ones chosen.
// The new quantities are saved together (window.api.lines.setQuantities),
// and the change can be undone straight after.
//
//   const multiply = window.multiplyLines.attach({
//     button,                       // the "Multiply…" button
//     kind: 'boq',                  // 'boq' | 'quotation' | 'invoice' | 'deliveryNote'
//     detail: () => currentDetail,  // { id, status, lineItems }
//     include: (line) => true,      // which lines are materials to multiply
//     reload: loadDetail,           // redraws the document afterwards
//   });
//   multiply.update();              // in render(): shown on a Draft with items

(function () {
  const SETS = [[2, '×2'], [3, '×3'], [4, '×4'], [1.1, '+10%'], [0.5, '½']];
  let sheet = null;
  let ctx = null; // the attach() options of the document being multiplied
  let lines = [];
  let chosen = new Set();

  const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const qty = (n) => Math.round(Number(n) || 0).toLocaleString('en-US');

  // A new quantity: whole numbers (as everywhere in the app), never below 1.
  function scaled(q, factor, round) {
    const exact = Math.round((Number(q) || 0) * factor * 1e6) / 1e6;
    const whole = round === 'up' ? Math.ceil(exact) : round === 'down' ? Math.floor(exact) : Math.round(exact);
    return Math.max(1, whole);
  }

  function build() {
    sheet = document.createElement('div');
    sheet.className = 'modal-backdrop hidden';
    sheet.innerHTML = `
      <div class="modal wide multiply-sheet" role="dialog" aria-labelledby="mx-title">
        <h2 id="mx-title">Multiply Quantities</h2>
        <p class="small-note">For more sets of the same scaffold (×2 for 2 sets), a spare allowance (+10%), or part of it (½).</p>
        <div class="mx-row">
          <div class="field mx-factor-field">
            <label for="mx-factor">Multiply by</label>
            <div class="mx-factor-wrap"><span class="mx-times">×</span><input type="number" id="mx-factor" min="0.01" step="any" value="2" /></div>
          </div>
          <div class="mx-chips" id="mx-chips">${SETS.map(([f, label]) => `<button type="button" class="mx-chip" data-f="${f}" data-no-icon>${label}</button>`).join('')}</div>
        </div>
        <div class="mx-row">
          <div class="field">
            <label>Items</label>
            <div class="segmented" id="mx-scope">
              <button type="button" data-scope="all" class="active" data-no-icon>All items</button>
              <button type="button" data-scope="some" data-no-icon>Choose items</button>
            </div>
          </div>
          <div class="field hidden" id="mx-round-field">
            <label>Not a whole number</label>
            <div class="segmented" id="mx-round">
              <button type="button" data-round="up" class="active" data-no-icon title="Never short of an item">Round up</button>
              <button type="button" data-round="nearest" data-no-icon>Nearest</button>
              <button type="button" data-round="down" data-no-icon>Round down</button>
            </div>
          </div>
        </div>
        <div class="mx-table-wrap"><table class="mx-table"><thead><tr>
          <th class="mx-pick-col"><input type="checkbox" id="mx-all" title="All / none" /></th>
          <th>Item</th><th>Unit</th><th class="num">Now</th><th class="num">New</th></tr></thead>
          <tbody id="mx-rows"></tbody></table></div>
        <p class="small-note" id="mx-summary"></p>
        <div class="error-text hidden" id="mx-error"></div>
        <div class="actions">
          <button id="mx-cancel">Cancel</button>
          <button class="primary" id="mx-apply">Multiply</button>
        </div>
      </div>`;
    document.body.appendChild(sheet);
    const $ = (id) => sheet.querySelector(`#${id}`);
    $('mx-factor').addEventListener('input', preview);
    $('mx-chips').addEventListener('click', (e) => {
      const b = e.target.closest('.mx-chip');
      if (!b) return;
      $('mx-factor').value = b.dataset.f;
      preview();
    });
    for (const seg of [$('mx-scope'), $('mx-round')]) {
      seg.addEventListener('click', (e) => {
        const b = e.target.closest('button');
        if (!b) return;
        for (const x of seg.children) x.classList.toggle('active', x === b);
        preview();
      });
    }
    $('mx-all').addEventListener('change', () => {
      chosen = $('mx-all').checked ? new Set(lines.map((l) => l.id)) : new Set();
      preview();
    });
    $('mx-rows').addEventListener('change', (e) => {
      const box = e.target.closest('input[type="checkbox"]');
      if (!box) return;
      const ids = box.dataset.section != null
        ? lines.filter((l) => (l.section || '') === box.dataset.section).map((l) => l.id)
        : [box.dataset.id];
      for (const id of ids) { if (box.checked) chosen.add(id); else chosen.delete(id); }
      preview();
    });
    $('mx-cancel').addEventListener('click', close);
    $('mx-apply').addEventListener('click', apply);
    sheet.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') close();
      if (e.key === 'Enter' && e.target.tagName === 'INPUT' && e.target.type === 'number') apply();
    });
  }

  const pickedOf = (seg, attr) => sheet.querySelector(`#${seg} .active`).dataset[attr];
  const factorOf = () => Number(sheet.querySelector('#mx-factor').value);
  const someOnly = () => pickedOf('mx-scope', 'scope') === 'some';
  const inScope = (l) => !someOnly() || chosen.has(l.id);

  function preview() {
    const $ = (id) => sheet.querySelector(`#${id}`);
    const factor = factorOf();
    const valid = factor > 0 && isFinite(factor);
    const fractional = valid && Math.abs(factor - Math.round(factor)) > 1e-9;
    $('mx-round-field').classList.toggle('hidden', !fractional);
    const round = pickedOf('mx-round', 'round');
    for (const c of sheet.querySelectorAll('.mx-chip')) c.classList.toggle('on', valid && Math.abs(Number(c.dataset.f) - factor) < 1e-9);
    sheet.querySelector('.multiply-sheet').classList.toggle('choosing', someOnly());
    $('mx-all').checked = lines.length > 0 && chosen.size === lines.length;
    $('mx-all').indeterminate = chosen.size > 0 && chosen.size < lines.length;

    // Grouped by section when the lines have more than one.
    const sections = [...new Set(lines.map((l) => l.section || ''))];
    const grouped = sections.length > 1;
    let html = '';
    let changed = 0;
    for (const section of sections) {
      const group = lines.filter((l) => (l.section || '') === section);
      if (grouped) {
        const n = group.filter((l) => chosen.has(l.id)).length;
        html += `<tr class="mx-section"><td class="mx-pick-col"><input type="checkbox" data-section="${esc(section)}" ${n === group.length ? 'checked' : ''} ${n > 0 && n < group.length ? 'data-mixed="1"' : ''} /></td>
          <td colspan="4">${esc(section || 'Other items')}</td></tr>`;
      }
      for (const l of group) {
        const on = inScope(l);
        const after = valid && on ? scaled(l.quantity, factor, round) : Math.round(l.quantity);
        if (after !== Math.round(l.quantity)) changed += 1;
        html += `<tr class="${on ? '' : 'mx-off'}">
          <td class="mx-pick-col"><input type="checkbox" data-id="${esc(l.id)}" ${chosen.has(l.id) ? 'checked' : ''} /></td>
          <td>${esc(l.itemCode ? `${l.itemCode} — ` : '')}${esc(l.itemDescription)}</td><td>${esc(l.unit)}</td>
          <td class="num">${qty(l.quantity)}</td>
          <td class="num ${after !== Math.round(l.quantity) ? 'mx-new' : ''}">${qty(after)}</td></tr>`;
      }
    }
    $('mx-rows').innerHTML = html;
    for (const box of $('mx-rows').querySelectorAll('[data-mixed]')) box.indeterminate = true;
    const count = lines.filter(inScope).length;
    $('mx-summary').textContent = !valid ? 'Enter a number above 0.'
      : count === 0 ? 'Tick the items to multiply.'
      : `${count} item${count === 1 ? '' : 's'} × ${factor.toLocaleString('en-US', { maximumFractionDigits: 4 })} — ${changed} quantit${changed === 1 ? 'y changes' : 'ies change'}.`;
    $('mx-apply').disabled = !valid || changed === 0;
    $('mx-error').classList.add('hidden');
  }

  async function apply() {
    const factor = factorOf();
    if (!(factor > 0) || !isFinite(factor)) return;
    const round = pickedOf('mx-round', 'round');
    const quantities = {};
    const before = {};
    for (const l of lines.filter(inScope)) {
      const n = scaled(l.quantity, factor, round);
      if (n === Math.round(l.quantity)) continue;
      quantities[l.id] = n;
      before[l.id] = Math.round(l.quantity);
    }
    if (!Object.keys(quantities).length) return;
    const btn = sheet.querySelector('#mx-apply');
    btn.disabled = true;
    const doc = ctx.detail();
    const result = await window.api.lines.setQuantities(ctx.kind, doc.id, quantities);
    btn.disabled = false;
    if (!result || !result.ok) {
      const err = sheet.querySelector('#mx-error');
      err.textContent = (result && result.error) || 'Couldn’t change the quantities.';
      err.classList.remove('hidden');
      return;
    }
    const target = ctx;
    close();
    await target.reload();
    const label = SETS.find(([f]) => Math.abs(f - factor) < 1e-9);
    undoToast(`${Object.keys(quantities).length} quantit${Object.keys(quantities).length === 1 ? 'y' : 'ies'} multiplied ${label ? label[1] : `× ${factor}`}`, async () => {
      const r = await window.api.lines.setQuantities(target.kind, doc.id, before);
      if (!r || !r.ok) { window.appAlert((r && r.error) || 'Couldn’t undo it.'); return; }
      await target.reload();
    });
  }

  // "… multiplied ×2  [Undo]" at the bottom right for a few seconds.
  function undoToast(text, undo) {
    document.querySelectorAll('.undo-toast').forEach((t) => t.remove());
    const el = document.createElement('div');
    el.className = 'sync-toast undo-toast';
    el.innerHTML = `<span>${esc(text)}</span><button type="button" data-no-icon>Undo</button>`;
    document.body.appendChild(el);
    requestAnimationFrame(() => el.classList.add('show'));
    const gone = () => { el.classList.remove('show'); setTimeout(() => el.remove(), 400); };
    const timer = setTimeout(gone, 8000);
    el.querySelector('button').addEventListener('click', async () => { clearTimeout(timer); gone(); await undo(); });
  }

  function open(options) {
    if (!sheet) build();
    ctx = options;
    const doc = ctx.detail();
    lines = (doc.lineItems || []).filter(ctx.include || (() => true));
    chosen = new Set(lines.map((l) => l.id));
    sheet.querySelector('#mx-factor').value = '2';
    for (const [seg, first] of [['mx-scope', 'all'], ['mx-round', 'up']]) {
      for (const b of sheet.querySelectorAll(`#${seg} button`)) b.classList.toggle('active', (b.dataset.scope || b.dataset.round) === first);
    }
    preview();
    sheet.classList.remove('hidden');
    const f = sheet.querySelector('#mx-factor');
    f.focus();
    f.select();
  }

  function close() {
    if (sheet) sheet.classList.add('hidden');
    ctx = null;
  }

  window.multiplyLines = {
    open,
    attach(options) {
      options.button.addEventListener('click', () => open(options));
      return {
        update() {
          const d = options.detail();
          const n = d ? (d.lineItems || []).filter(options.include || (() => true)).length : 0;
          options.button.classList.toggle('hidden', !d || d.status !== 'Draft' || n === 0);
        },
      };
    },
  };
})();

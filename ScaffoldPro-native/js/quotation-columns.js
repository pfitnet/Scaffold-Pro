'use strict';

// "Columns…" (Line Items' ☰): the printed table's columns between No. and
// Total Price — drag to reorder, remove, or add Unit, Unit Weight or a
// custom column (its value typed on each item). Description and Qty always
// stay; Unit Rate is there by default and can be taken off the PDF (its
// price is still kept and typed in the editor) or put back; up to 6 in all.
// Every column's title can be changed (the standard ones' too; blank = the
// usual title). Unit Rate and custom columns can be worked out from the others: a formula
// such as "{Rate/kg} × {Unit Weight}" (column titles in braces), answered
// for each item and put in its box (sync, run by the editor on each load).
//
//   window.quotationColumns.open(currentDetail, loadDetail);
//   await window.quotationColumns.sync(currentDetail) → true if any box changed

(function () {
  const KNOWN = { desc: 'Description', rate: 'Unit Rate', qty: 'Qty', unit: 'Unit', weight: 'Unit Weight' };
  const FIXED = ['desc', 'qty'];
  const DEFAULT = ['desc', 'rate', 'qty'];
  const MAX = 6;
  const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  let sheet = null;
  let detail = null;
  let reload = null;
  let layout = [];
  let custom = [];
  let formulas = {};
  let titles = {}; // the standard columns renamed, by key ("total" too)
  let totalOf = ''; // what Total is Qty × of: '' = Unit Rate, 'weight' or a custom column's id
  let lastFormula = null; // the formula box a column name is put in

  const titleOf = (key) => (KNOWN[key] ? (titles[key] || '').trim() || KNOWN[key] : (custom.find((c) => c.id === key) || {}).title || '');

  // The names a formula can use: the columns (as titled), and each item's weight.
  function drawNames() {
    const names = [...new Set([...layout, 'rate', 'qty', 'weight'].filter((k) => k !== 'desc' && k !== 'unit').map(titleOf).filter((t) => t.trim()))];
    sheet.querySelector('#qc-names').innerHTML = `<span>In a formula:</span>${names.map((n) => `<button type="button" class="qc-name-chip" data-no-icon title="Put {${esc(n)}} in the formula">${esc(n)}</button>`).join('')}`;
  }

  // The Total row: what it's Qty × of, and its title (blank: the usual one).
  const totalTitle = () => (totalOf === 'weight' ? 'Total Weight (kg)' : totalOf ? `Total ${titleOf(totalOf) || ''}`.trim() : 'Total Price');
  function drawTotal() {
    const choices = [['', titleOf('rate')], ['weight', titleOf('weight')], ...custom.filter((c) => c.title.trim()).map((c) => [c.id, c.title])];
    if (!choices.some(([v]) => v === totalOf)) totalOf = '';
    const select = sheet.querySelector('#qc-total-of');
    select.innerHTML = choices.map(([v, t]) => `<option value="${esc(v)}">${esc(t)}</option>`).join('');
    select.value = totalOf;
    const input = sheet.querySelector('#qc-total-title');
    input.value = titles.total || '';
    input.placeholder = totalTitle();
  }

  function draw() {
    const list = sheet.querySelector('#qc-list');
    list.innerHTML = layout.map((key) => `
      <div class="qc-row" data-id="${esc(key)}">
        ${window.dragHandleHTML('Drag to move this column (or focus and press ↑ / ↓)')}
        <input type="text" class="qc-title" maxlength="30" value="${esc(KNOWN[key] ? titles[key] || '' : titleOf(key))}"
          placeholder="${KNOWN[key] ? esc(KNOWN[key]) : 'Column title, e.g. Size'}" aria-label="Column title"${KNOWN[key] ? ` title="Type a new title for the ${esc(KNOWN[key])} column (blank: ${esc(KNOWN[key])})"` : ''} />
        ${FIXED.includes(key) ? '<span class="qc-fixed">Always shown</span>'
          : `${key === 'rate' ? '<span class="qc-fixed">Shown by default</span>' : ''}<button type="button" class="qc-remove" data-no-icon${key === 'rate' ? ' title="Take the unit rate off the PDF and Word copy (the price stays in the editor)"' : ''}>Remove</button>`}
        ${KNOWN[key] && key !== 'rate' ? '' : `<input type="text" class="qc-formula" maxlength="120" value="${esc(formulas[key] || '')}"
          placeholder="Formula (optional), e.g. {Rate/kg} × {Unit Weight}" aria-label="${esc(titleOf(key) || 'Column')} formula"
          title="Leave blank to type it on each item. A formula works it out for each item: column titles in braces, with + − × ÷ and brackets." />`}
      </div>`).join('');
    drawNames();
    drawTotal();
    const full = layout.length >= MAX;
    sheet.querySelector('#qc-add-rate').hidden = layout.includes('rate');
    sheet.querySelector('#qc-add-rate').disabled = full;
    sheet.querySelector('#qc-add-unit').disabled = full || layout.includes('unit');
    sheet.querySelector('#qc-add-weight').disabled = full || layout.includes('weight');
    sheet.querySelector('#qc-add-custom').disabled = full;
    sheet.querySelector('#qc-note').textContent = full ? 'Up to 6 columns in all — the description needs the room.'
      : totalOf ? `Each item is priced by its ${titleOf(totalOf)}: Total = Qty × ${titleOf(totalOf)}.${layout.includes('rate') ? ` ${titleOf('rate')} shows that price too.` : ''}`
      : layout.includes('rate') ? '' : 'Unit Rate is off the printed table; each item’s price is still kept, and typed in the editor.';
  }

  function build() {
    sheet = document.createElement('div');
    sheet.className = 'modal-backdrop hidden';
    sheet.innerHTML = `
      <div class="modal qc-sheet" role="dialog" aria-labelledby="qc-head">
        <h2 id="qc-head">Columns</h2>
        <p class="small-note">The printed table’s columns, between No. and Total Price. Drag to reorder.</p>
        <div class="qc-list" id="qc-list"></div>
        <div class="qc-names" id="qc-names"></div>
        <div class="qc-row qc-total">
          <input type="text" class="qc-title" id="qc-total-title" maxlength="30" aria-label="Total column title" />
          <span class="qc-fixed">= Qty ×</span>
          <select id="qc-total-of" aria-label="What the total is of"
            title="The column that prices each item: its Total (and the quotation's) is Qty × it"></select>
        </div>
        <div class="qc-add">
          <button type="button" id="qc-add-rate" data-no-icon title="Show each item’s unit rate on the PDF again">+ Unit Rate</button>
          <button type="button" id="qc-add-unit" data-no-icon>+ Unit</button>
          <button type="button" id="qc-add-weight" data-no-icon title="Each item’s weight from the material list, in kg">+ Unit Weight</button>
          <button type="button" id="qc-add-custom" data-no-icon title="A column of your own — type its value on each item">+ Custom…</button>
        </div>
        <p class="small-note" id="qc-note"></p>
        <div class="error-text hidden" id="qc-error"></div>
        <div class="actions">
          <button type="button" class="left" id="qc-reset" data-no-icon>Default Columns</button>
          <button type="button" id="qc-cancel">Cancel</button>
          <button type="button" class="primary" id="qc-save">Save</button>
        </div>
      </div>`;
    document.body.appendChild(sheet);
    const list = sheet.querySelector('#qc-list');
    window.makeReorderable(list, { item: '.qc-row', onReorder: (ids) => { layout = ids; } });
    list.addEventListener('click', (e) => {
      const b = e.target.closest('.qc-remove');
      if (!b) return;
      const key = b.closest('.qc-row').dataset.id;
      layout = layout.filter((k) => k !== key);
      custom = custom.filter((c) => c.id !== key);
      draw();
    });
    list.addEventListener('focusin', (e) => { if (e.target.classList.contains('qc-formula')) lastFormula = e.target; });
    list.addEventListener('input', (e) => {
      if (e.target.classList.contains('qc-formula')) { formulas[e.target.closest('.qc-row').dataset.id] = e.target.value; return; }
      const input = e.target.closest('.qc-title');
      if (!input) return;
      const key = input.closest('.qc-row').dataset.id;
      if (KNOWN[key]) titles[key] = input.value;
      const c = custom.find((x) => x.id === key);
      if (c) c.title = input.value;
      drawNames();
      drawTotal();
    });
    sheet.querySelector('#qc-names').addEventListener('mousedown', (e) => e.preventDefault()); // (the formula box keeps the focus)
    sheet.querySelector('#qc-names').addEventListener('click', (e) => {
      const chip = e.target.closest('.qc-name-chip');
      const box = lastFormula && lastFormula.isConnected ? lastFormula : list.querySelector('.qc-formula');
      if (!chip || !box) return;
      const at = box.selectionStart ?? box.value.length;
      const name = `{${chip.textContent}}`;
      box.setRangeText(name, at, box.selectionEnd ?? at, 'end');
      box.focus();
      box.dispatchEvent(new Event('input', { bubbles: true }));
    });
    const add = (key) => { layout.push(key); draw(); };
    sheet.querySelector('#qc-add-rate').addEventListener('click', () => { layout.splice(Math.min(layout.indexOf('desc') + 1, layout.length), 0, 'rate'); draw(); });
    sheet.querySelector('#qc-add-unit').addEventListener('click', () => add('unit'));
    sheet.querySelector('#qc-add-weight').addEventListener('click', () => add('weight'));
    sheet.querySelector('#qc-add-custom').addEventListener('click', () => {
      const id = `col_${Math.random().toString(36).slice(2, 10)}`;
      custom.push({ id, title: '' });
      add(id);
      const input = list.querySelector(`[data-id="${id}"] .qc-title`);
      if (input) input.focus();
    });
    sheet.querySelector('#qc-reset').addEventListener('click', () => { layout = DEFAULT.slice(); custom = []; formulas = {}; titles = {}; totalOf = ''; draw(); });
    sheet.querySelector('#qc-cancel').addEventListener('click', close);
    sheet.querySelector('#qc-save').addEventListener('click', save);
    sheet.querySelector('#qc-total-title').addEventListener('input', (e) => { titles.total = e.target.value; });
    // (The columns stay as they are: Unit Rate is kept or removed by hand.)
    sheet.querySelector('#qc-total-of').addEventListener('change', (e) => { totalOf = e.target.value; draw(); });
    sheet.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') close();
      if (e.key === 'Enter' && e.target.classList.contains('qc-title')) save();
    });
    sheet.addEventListener('mousedown', (e) => { if (e.target === sheet) close(); });
  }

  async function save() {
    const err = sheet.querySelector('#qc-error');
    // A custom column left without a title is dropped.
    const named = custom.filter((c) => c.title.trim());
    const keep = layout.filter((k) => KNOWN[k] || named.some((c) => c.id === k));
    const kept = {};
    for (const k of keep) if ((formulas[k] || '').trim()) kept[k] = formulas[k].trim().replace(/^=\s*/, '');
    const renamed = {};
    for (const k of [...keep, 'total']) if ((KNOWN[k] || k === 'total') && (titles[k] || '').trim() && titles[k].trim() !== KNOWN[k]) renamed[k] = titles[k].trim();
    const r = await window.api.quotations.setColumns(detail.id, keep, named.map((c) => ({ id: c.id, title: c.title.trim() })), kept, renamed, totalOf || null);
    if (r && r.ok === false) { err.textContent = r.error; err.classList.remove('hidden'); return; }
    close();
    await reload();
  }

  function close() { if (sheet) sheet.classList.add('hidden'); }

  function open(d, after) {
    if (!sheet) build();
    detail = d;
    reload = after;
    layout = (d.columnLayout && d.columnLayout.length ? d.columnLayout : DEFAULT).slice();
    custom = (d.customColumns || []).map((c) => ({ id: c.id, title: c.title }));
    formulas = Object.assign({}, d.columnFormulas);
    titles = Object.assign({}, d.columnTitles);
    totalOf = d.totalOf || '';
    sheet.querySelector('#qc-error').classList.add('hidden');
    draw();
    sheet.classList.remove('hidden');
  }

  // The columns typed in on each item, in their printed order (for the
  // editor's table): the custom ones, and Unit Weight (kg) when shown.
  function customInOrder(d) {
    const byId = new Map((d.customColumns || []).map((c) => [c.id, c]));
    byId.set('weight', { id: 'weight', title: (d.columnTitles || {}).weight || 'Unit Weight (kg)' });
    return (d.columnLayout || []).filter((k) => byId.has(k)).map((k) => byId.get(k));
  }

  // ---- Worked-out columns ----

  // The first number in a box ("12.5 kg" → 12.5), or null.
  const numberIn = (v) => {
    const m = /-?(\d[\d,]*\.?\d*|\.\d+)/.exec(String(v ?? ''));
    return m ? Number(m[0].replace(/,/g, '')) : null;
  };
  // An item's value under a column title: a custom column's first, then
  // Unit Rate, Qty and Unit Weight (from the material list).
  function valueOf(name, item, d, values) {
    let n = name.trim().toLowerCase();
    const c = (d.customColumns || []).find((x) => x.title.trim().toLowerCase() === n);
    if (c) return numberIn(values[c.id]);
    // A standard column under its new title.
    const renamed = Object.entries(d.columnTitles || {}).find(([, t]) => t.trim().toLowerCase() === n);
    if (renamed) n = { rate: 'rate', qty: 'qty', weight: 'weight' }[renamed[0]] || n;
    if (['unit rate', 'unit price', 'rate', 'price'].includes(n)) return item.appliedUnitPrice;
    if (['qty', 'quantity'].includes(n)) return item.quantity;
    if (['unit weight', 'weight', 'unit weight (kg)'].includes(n)) return numberIn(values.weight) ?? (d.lineWeights || {})[item.id] ?? null;
    return null;
  }
  // A formula's answer for an item; null while a value it needs is blank.
  function answer(formula, item, d, values) {
    let blank = false;
    const text = formula.replace(/\{([^}]*)\}/g, (m, name) => {
      const v = valueOf(name, item, d, values);
      if (v === null || v === undefined) blank = true;
      return `(${v})`;
    });
    return blank ? null : window.calcEvaluate(text);
  }

  // Each item's worked-out columns (in their order), then Unit Rate: an
  // answer that differs from the box is saved there.
  async function sync(d) {
    const f = d.columnFormulas || {};
    if (!Object.keys(f).length && !d.totalOf) return false;
    const order = customInOrder(d).map((c) => c.id).filter((id) => f[id]);
    let changed = false;
    for (const item of d.lineItems || []) {
      if (item.blockId || item.section === 'Delivery' || item.priceNote) continue;
      const values = Object.assign({}, item.customValues);
      for (const id of order) {
        const v = answer(f[id], item, d, values);
        if (v === null) continue;
        const text = String(Math.round(v * 100) / 100);
        if (values[id] === text) continue;
        values[id] = text;
        const r = await window.api.quotations.setLineValue(item.id, id, text);
        if (!r || r.ok !== false) changed = true;
      }
      // Total of another column: that column is the price; else Unit Rate's formula.
      const v = d.totalOf === 'weight' ? numberIn(values.weight) ?? (d.lineWeights || {})[item.id] ?? null
        : d.totalOf ? numberIn(values[d.totalOf]) : f.rate ? answer(f.rate, item, d, values) : null;
      if (v === null) continue;
      const price = Math.round(Math.max(0, v) * 100) / 100;
      if (Math.abs(price - item.appliedUnitPrice) < 0.005 && !item.priceFormula) continue;
      const r = await window.api.quotations.updateLineItem(item.id, { appliedUnitPrice: price, priceFormula: '' });
      if (!r || r.ok !== false) changed = true;
    }
    return changed;
  }

  window.quotationColumns = { open, customInOrder, sync };
})();

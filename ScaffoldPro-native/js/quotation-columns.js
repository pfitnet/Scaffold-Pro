'use strict';

// "Columns…" (Line Items' ☰): the printed table's columns between No. and
// Total Price — drag to reorder, remove, or add Unit, Unit Weight or a
// custom column (its value typed on each item). Description, Unit Rate and
// Qty always stay; up to 3 more.
//
//   window.quotationColumns.open(currentDetail, loadDetail);

(function () {
  const KNOWN = { desc: 'Description', rate: 'Unit Rate', qty: 'Qty', unit: 'Unit', weight: 'Unit Weight' };
  const FIXED = ['desc', 'rate', 'qty'];
  const MAX = 6;
  const esc = (s) => String(s == null ? '' : s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  let sheet = null;
  let detail = null;
  let reload = null;
  let layout = [];
  let custom = [];

  const titleOf = (key) => KNOWN[key] || (custom.find((c) => c.id === key) || {}).title || '';

  function draw() {
    const list = sheet.querySelector('#qc-list');
    list.innerHTML = layout.map((key) => `
      <div class="qc-row" data-id="${esc(key)}">
        ${window.dragHandleHTML('Drag to move this column (or focus and press ↑ / ↓)')}
        ${KNOWN[key] ? `<span class="qc-name">${esc(KNOWN[key])}</span>`
          : `<input type="text" class="qc-title" maxlength="30" value="${esc(titleOf(key))}" placeholder="Column title, e.g. Size" aria-label="Column title" />`}
        ${FIXED.includes(key) ? '<span class="qc-fixed">Always shown</span>' : '<button type="button" class="qc-remove" data-no-icon>Remove</button>'}
      </div>`).join('');
    const full = layout.length >= MAX;
    sheet.querySelector('#qc-add-unit').disabled = full || layout.includes('unit');
    sheet.querySelector('#qc-add-weight').disabled = full || layout.includes('weight');
    sheet.querySelector('#qc-add-custom').disabled = full;
    sheet.querySelector('#qc-note').textContent = full ? 'Up to 3 columns can be added — the description needs the room.' : '';
  }

  function build() {
    sheet = document.createElement('div');
    sheet.className = 'modal-backdrop hidden';
    sheet.innerHTML = `
      <div class="modal qc-sheet" role="dialog" aria-labelledby="qc-head">
        <h2 id="qc-head">Columns</h2>
        <p class="small-note">The printed table’s columns, between No. and Total Price. Drag to reorder.</p>
        <div class="qc-list" id="qc-list"></div>
        <div class="qc-add">
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
    list.addEventListener('input', (e) => {
      const input = e.target.closest('.qc-title');
      if (!input) return;
      const c = custom.find((x) => x.id === input.closest('.qc-row').dataset.id);
      if (c) c.title = input.value;
    });
    const add = (key) => { layout.push(key); draw(); };
    sheet.querySelector('#qc-add-unit').addEventListener('click', () => add('unit'));
    sheet.querySelector('#qc-add-weight').addEventListener('click', () => add('weight'));
    sheet.querySelector('#qc-add-custom').addEventListener('click', () => {
      const id = `col_${Math.random().toString(36).slice(2, 10)}`;
      custom.push({ id, title: '' });
      add(id);
      const input = list.querySelector(`[data-id="${id}"] .qc-title`);
      if (input) input.focus();
    });
    sheet.querySelector('#qc-reset').addEventListener('click', () => { layout = FIXED.slice(); custom = []; draw(); });
    sheet.querySelector('#qc-cancel').addEventListener('click', close);
    sheet.querySelector('#qc-save').addEventListener('click', save);
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
    const r = await window.api.quotations.setColumns(detail.id, keep, named.map((c) => ({ id: c.id, title: c.title.trim() })));
    if (r && r.ok === false) { err.textContent = r.error; err.classList.remove('hidden'); return; }
    close();
    await reload();
  }

  function close() { if (sheet) sheet.classList.add('hidden'); }

  function open(d, after) {
    if (!sheet) build();
    detail = d;
    reload = after;
    layout = (d.columnLayout && d.columnLayout.length ? d.columnLayout : FIXED).slice();
    custom = (d.customColumns || []).map((c) => ({ id: c.id, title: c.title }));
    sheet.querySelector('#qc-error').classList.add('hidden');
    draw();
    sheet.classList.remove('hidden');
  }

  // The custom columns as printed, in their order (for the editor's table).
  function customInOrder(d) {
    const byId = new Map((d.customColumns || []).map((c) => [c.id, c]));
    return (d.columnLayout || []).filter((k) => byId.has(k)).map((k) => byId.get(k));
  }

  window.quotationColumns = { open, customInOrder };
})();

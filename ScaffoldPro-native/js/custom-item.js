'use strict';

// The custom item box (BOQ, quotation, delivery note and invoice editors):
// the description can run over several lines, formatted like the terms. Return adds the item;
// Shift-Return starts a new line in the same item. The box grows with
// what's typed and shrinks back once the item is added.

// Editing one already added: window.customItemEditButton(item, locked) gives
// a pencil for a custom line (none for material-list items), and
// window.wireCustomItemEdit(kind, findItem, reload) opens it in the same box,
// with its formatting strip and preview, then saves the description and unit.

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const PEN = '<svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12.8 3.7l3.5 3.5-8.8 8.8-4 .5.5-4z"/><path d="M11.2 5.3l3.5 3.5"/></svg>';
  window.customItemEditButton = (item, locked) => (locked || item.priceListItemId
    ? '' : `<button type="button" class="ci-edit-btn" data-ci-edit="${esc(item.id)}" data-no-icon title="Edit this item" aria-label="Edit this item">${PEN}</button>`);

  window.wireCustomItemEdit = function wireCustomItemEdit(kind, findItem, reload) {
    document.addEventListener('click', (e) => {
      const b = e.target.closest('[data-ci-edit]');
      if (!b) return;
      e.preventDefault();
      e.stopPropagation();
      const item = findItem(b.dataset.ciEdit);
      if (item) open(kind, item, reload);
    });
  };

  function open(kind, item, reload) {
    const back = document.createElement('div');
    back.className = 'modal-backdrop ci-edit-back';
    back.innerHTML = `<div class="modal ci-edit-modal" role="dialog" aria-label="Edit item">
      <h2>Edit Item</h2>
      <div class="ci-card"><div class="ci-editor"><textarea id="ci-edit-text" rows="3"></textarea></div>
        <div class="ci-fields"><label class="ci-field ci-unit"><span>Unit</span><input type="text" id="ci-edit-unit" /></label><span class="ci-edit-hint">Shift-Return for a new line · Return saves · Esc cancels</span></div>
        <div class="ci-preview" id="ci-edit-preview"></div></div>
      <div class="error-text hidden" id="ci-edit-error"></div>
      <div class="actions"><button type="button" data-act="cancel" data-no-icon>Cancel</button><button type="button" class="primary" data-act="save" data-no-icon>Save</button></div>
    </div>`;
    document.body.appendChild(back);
    const ta = back.querySelector('#ci-edit-text');
    const unit = back.querySelector('#ci-edit-unit');
    ta.value = item.itemDescription || '';
    unit.value = item.unit || '';
    const fit = () => { ta.style.height = 'auto'; ta.style.height = `${ta.scrollHeight + 2}px`; };
    if (window.attachParagraphFormatting) {
      window.attachParagraphFormatting(ta, { fit: true, strip: true, previewIn: back.querySelector('#ci-edit-preview'), tip: '' });
    }
    ta.addEventListener('input', fit);
    const close = () => back.remove();
    const save = async () => {
      const r = await window.api.lines.editCustom(kind, item.id, ta.value, unit.value);
      if (r && r.ok === false) { const err = back.querySelector('#ci-edit-error'); err.textContent = r.error; err.classList.remove('hidden'); return; }
      close();
      await reload();
    };
    back.addEventListener('click', (e) => {
      const b = e.target.closest('button[data-act]');
      if (b) { if (b.dataset.act === 'save') save(); else close(); }
      else if (e.target === back) close();
    });
    back.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(); }
      else if (e.key === 'Enter' && !e.shiftKey && !e.isComposing && !e.altKey) { e.preventDefault(); save(); }
    });
    requestAnimationFrame(() => { fit(); ta.focus(); ta.setSelectionRange(ta.value.length, ta.value.length); });
  }
})();

(function () {
  const box = document.getElementById('ci-description');
  const add = document.getElementById('ci-add-btn');
  if (!box || !add) return;

  // Empty: one line again (the hint text, which may wrap, doesn't count).
  const fit = () => {
    box.style.height = '';
    if (box.value) { box.style.height = 'auto'; box.style.height = `${box.scrollHeight + 2}px`; }
  };
  box.addEventListener('input', fit);
  // The editors clear it by setting its value once the item is added.
  const own = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
  Object.defineProperty(box, 'value', {
    configurable: true,
    get() { return own.get.call(this); },
    set(v) { own.set.call(this, v); fit(); if (window.refreshParagraphPreview) window.refreshParagraphPreview(this); },
  });

  // The same formatting as the terms: Hanging Indent ("Model : ZT14JC"),
  // bullets, numbering, indent, with the description as it will print.
  // The box laid out as one card: the description (with its formatting
  // strip) across the top, then Unit, Qty and price or weight with their
  // labels and the Add button, and the preview once there's formatting.
  const row = box.closest('.custom-item-row');
  const card = document.createElement('div');
  card.className = 'ci-card';
  const editor = document.createElement('div');
  editor.className = 'ci-editor';
  const fields = document.createElement('div');
  fields.className = 'ci-fields';
  const previewIn = document.createElement('div');
  previewIn.className = 'ci-preview';
  const labelled = (el, text) => {
    if (!el) return;
    const f = document.createElement('label');
    f.className = `ci-field ci-${el.id.replace('ci-', '')}`;
    f.innerHTML = `<span>${text}</span>`;
    f.appendChild(el);
    fields.appendChild(f);
  };
  editor.appendChild(box);
  card.append(editor, fields, previewIn);
  if (row) {
    const extra = document.getElementById('ci-extra');
    labelled(document.getElementById('ci-unit'), 'Unit');
    labelled(document.getElementById('ci-qty'), 'Qty');
    labelled(extra, extra ? (extra.placeholder || 'Price').replace(/\s*\(.*\)/, '') : '');
    if (extra) extra.placeholder = '0.00';
    add.textContent = 'Add Item';
    add.classList.add('primary');
    fields.appendChild(add);
    row.replaceWith(card);
  }
  box.placeholder = 'Describe the item — e.g. Provision of Tracked Telescopic Boom Lift';
  if (window.attachParagraphFormatting) {
    window.attachParagraphFormatting(box, { fit: true, strip: true, previewIn, tip: 'Return adds · Shift-Return new line' });
  }

  const submit = (e) => {
    if (e.key !== 'Enter' || e.isComposing || e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.shiftKey && e.currentTarget === box) return;   // a new line in the description
    e.preventDefault();
    add.click();
  };
  for (const id of ['ci-description', 'ci-unit', 'ci-qty', 'ci-extra', 'ci-price']) {
    const el = document.getElementById(id);
    if (el) el.addEventListener('keydown', submit);
  }
})();

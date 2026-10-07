'use strict';

// The custom item box (BOQ, quotation, delivery note and invoice editors):
// the description can run over several lines, formatted like the terms. Return adds the item;
// Shift-Return starts a new line in the same item. The box grows with
// what's typed and shrinks back once the item is added.

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

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
  if (window.attachParagraphFormatting) {
    window.attachParagraphFormatting(box, { fit: true, help: 'Shift-Return for a new line, a blank line for a gap. Labels in a run line up their colons.' });
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

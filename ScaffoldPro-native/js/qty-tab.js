'use strict';

// Tab / Enter in an item's quantity goes straight to the next item's
// quantity (Shift-Tab / Shift-Enter: the previous one), with its number
// selected ready to type over — in the BOQ, quotation, invoice and
// delivery note editors.
//
// Saving a quantity redraws the table; js/keep-focus.js then puts the
// cursor back in the same box of the new table.

(function () {
  const QTY = 'input.qty-input, input.row-qty';
  const boxes = () => [...document.querySelectorAll(QTY)].filter((el) => !el.disabled && el.offsetParent !== null);

  function focusBox(el) {
    el.focus();
    try { el.select(); } catch (e) { /* number inputs in some engines */ }
  }

  document.addEventListener('keydown', (e) => {
    const target = e.target;
    if (!(target instanceof HTMLInputElement) || !target.matches(QTY)) return;
    if ((e.key !== 'Tab' && e.key !== 'Enter') || e.altKey || e.ctrlKey || e.metaKey) return;
    const list = boxes();
    const index = list.indexOf(target) + (e.shiftKey ? -1 : 1);
    if (index < 0 || index >= list.length) {
      // Enter on the last one: just save it. Tab: carry on as usual.
      if (e.key === 'Enter') { e.preventDefault(); target.blur(); }
      return;
    }
    e.preventDefault();
    focusBox(list[index]); // leaving the box saves it ("change")
  }, true);
})();

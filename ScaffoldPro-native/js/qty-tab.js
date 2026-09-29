'use strict';

// Tab / Enter in an item's quantity goes straight to the next item's
// quantity (Shift-Tab / Shift-Enter: the previous one), with its number
// selected ready to type over — in the BOQ, quotation, invoice and
// delivery note editors.
//
// Saving a quantity redraws the table, which would lose the place, so for
// a moment afterwards the same quantity box (by position) is focused again
// in the new table, keeping anything already typed into it.

(function () {
  const QTY = 'input.qty-input, input.row-qty';
  const boxes = () => [...document.querySelectorAll(QTY)].filter((el) => !el.disabled && el.offsetParent !== null);
  let pending = null; // { index, el, until }

  function focusBox(el, typed) {
    el.focus();
    if (typed !== null && typed !== undefined) {
      el.value = typed;
    } else {
      try { el.select(); } catch (e) { /* number inputs in some engines */ }
    }
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
    const next = list[index];
    pending = { index: index, el: next, until: Date.now() + 2500 };
    focusBox(next, null); // leaving the box saves it ("change")
  }, true);

  // The table was redrawn: put the cursor back in the same quantity box.
  new MutationObserver(() => {
    if (!pending) return;
    if (Date.now() > pending.until) { pending = null; return; }
    if (pending.el.isConnected) return;
    const replacement = boxes()[pending.index];
    if (!replacement) return;
    const old = pending.el;
    const typed = old.value !== old.defaultValue ? old.value : null;
    pending.el = replacement;
    focusBox(replacement, typed);
  }).observe(document.documentElement, { childList: true, subtree: true });
})();

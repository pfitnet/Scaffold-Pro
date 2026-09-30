'use strict';

// One click to move from one box to another. Leaving a box saves it, and
// saving redraws the table — which used to throw away the box just
// clicked, so it took a second click to edit it. For a moment after a box
// is clicked (or tabbed to), if the table is redrawn under it, the same
// box in the new table (by its id, else by its place among boxes like it)
// is focused instead, keeping anything already typed and where the cursor
// was.

(function () {
  const FIELD = 'input:not([type=checkbox]):not([type=radio]):not([type=button]):not([type=submit]):not([type=file]), textarea, select';
  const WINDOW_MS = 2500;
  let pending = null; // { el, sig, index, id, until }

  // Boxes "like" this one: same tag, type and classes.
  function signature(el) {
    return `${el.tagName}|${el.type || ''}|${[...el.classList].sort().join('.')}`;
  }
  function alike(sig) {
    return [...document.querySelectorAll(FIELD)].filter((x) => signature(x) === sig);
  }

  function remember(el) {
    pending = { el: el, sig: signature(el), index: alike(signature(el)).indexOf(el), id: el.id || null, until: Date.now() + WINDOW_MS };
  }

  document.addEventListener('focusin', (e) => {
    const el = e.target;
    if (el instanceof Element && el.matches(FIELD) && !el.disabled) remember(el);
    else pending = null;
  }, true);

  // Pressing on something that isn't a box (a button, the page): nothing to keep.
  document.addEventListener('mousedown', (e) => {
    if (!(e.target instanceof Element) || !e.target.closest(FIELD)) pending = null;
  }, true);

  // Typing in it: that text is kept if it's redrawn.
  document.addEventListener('input', (e) => {
    if (pending && e.target === pending.el) pending.typed = true;
  }, true);

  function restore() {
    if (!pending || pending.el.isConnected) return;
    if (Date.now() > pending.until) { pending = null; return; }
    // Something else has the cursor now: leave it there.
    const active = document.activeElement;
    if (active && active !== document.body && active.isConnected) { pending = null; return; }
    const replacement = (pending.id && document.getElementById(pending.id)) || alike(pending.sig)[pending.index];
    if (!replacement || replacement.disabled || replacement.readOnly || replacement.offsetParent === null) return;
    const old = pending.el;
    let start = null;
    let end = null;
    try { start = old.selectionStart; end = old.selectionEnd; } catch (err) { /* not a text box */ }
    const typed = pending.typed ? old.value : null;
    const wasTyped = pending.typed;
    replacement.focus(); // → focusin: remembered afresh
    if (typed !== null && replacement.value !== typed) replacement.value = typed;
    if (pending) pending.typed = wasTyped;
    if (replacement.tagName === 'SELECT') return;
    try {
      if (start !== null && end !== null && (start !== end || start > 0)) replacement.setSelectionRange(start, end);
      else if (replacement.type === 'number') replacement.select();
    } catch (err) {
      try { replacement.select(); } catch (err2) { /* nothing to select */ }
    }
  }

  new MutationObserver(restore).observe(document.documentElement, { childList: true, subtree: true });
})();

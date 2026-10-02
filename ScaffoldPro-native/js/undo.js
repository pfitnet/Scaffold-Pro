'use strict';

// Undo / Redo the last action: ⌘Z or Ctrl+Z undoes, ⇧⌘Z, ⌘Y or Ctrl+Y
// redoes (and Edit › Undo / Redo). The app notes what each action changed
// (UndoJournal in main.swift) and puts it back; the page then reloads,
// where it was, with "Undone: Add line item (BOQ)  [Redo]" at the bottom.
//
// Typing in a field that hasn't been saved yet is undone in the field, as
// usual; once it's saved (the field is left, or Return), ⌘Z undoes it as
// an action.

(function () {
  if (window.appUndo) return;
  const KEY = 'scaffoldpro-undo-toast';

  const isField = (el) => !!el && (el.isContentEditable || el.tagName === 'TEXTAREA' ||
    (el.tagName === 'INPUT' && /^(text|search|email|url|tel|password|number|)$/i.test(el.type || '')));
  const valueOf = (el) => (el.isContentEditable ? el.innerHTML : el.value);
  // A field's value when it was last saved (or got focus): typed since → unsaved.
  document.addEventListener('focusin', (e) => { if (isField(e.target)) e.target.__savedValue = valueOf(e.target); }, true);
  document.addEventListener('change', (e) => { if (isField(e.target)) e.target.__savedValue = valueOf(e.target); }, true);
  const typing = (el) => isField(el) && el.__savedValue !== undefined && valueOf(el) !== el.__savedValue;

  // The page's scrolling box (#content in the app's pages), else the window.
  const scroller = () => {
    const c = document.getElementById('content');
    return c && c.scrollHeight > c.clientHeight && getComputedStyle(c).overflowY !== 'visible' ? c : document.scrollingElement || document.documentElement;
  };

  let busy = false;
  async function appUndo(kind) {
    const el = document.activeElement;
    if (typing(el)) { document.execCommand(kind === 'redo' ? 'redo' : 'undo'); return; }
    // Not while a dialog or sheet is asking something.
    if (document.querySelector('.app-dialog-backdrop, .modal-backdrop:not(.hidden)')) return;
    if (busy || !window.api || !window.api.history) return;
    busy = true;
    try {
      const r = await window.api.history[kind === 'redo' ? 'redo' : 'undo']();
      if (!r || !r.ok) { toast((r && r.error) || (kind === 'redo' ? 'Nothing to redo.' : 'Nothing to undo.'), null); return; }
      // Reloaded where it was, then told what happened.
      try {
        sessionStorage.setItem(KEY, JSON.stringify({ text: `${kind === 'redo' ? 'Redone' : 'Undone'}: ${r.label}`, again: kind === 'redo' ? (r.canUndo ? 'undo' : null) : (r.canRedo ? 'redo' : null), y: scroller().scrollTop, page: location.href }));
      } catch (e) { /* ignore */ }
      location.reload();
    } finally {
      busy = false;
    }
  }
  window.appUndo = appUndo;

  document.addEventListener('keydown', (e) => {
    if (!(e.metaKey || e.ctrlKey) || e.altKey || e.isComposing) return;
    const k = (e.key || '').toLowerCase();
    let kind = null;
    if (k === 'z') kind = e.shiftKey ? 'redo' : 'undo';
    else if (k === 'y' && !e.shiftKey) kind = 'redo';
    if (!kind) return;
    e.preventDefault();
    e.stopPropagation();
    appUndo(kind);
  }, true);

  // "Undone: …  [Redo]" for a few seconds at the bottom right.
  function toast(text, again) {
    document.querySelectorAll('.app-undo-toast').forEach((t) => t.remove());
    const el = document.createElement('div');
    el.className = 'sync-toast undo-toast app-undo-toast';
    el.setAttribute('role', 'status');
    const span = document.createElement('span');
    span.textContent = text;
    el.appendChild(span);
    if (again) {
      const b = document.createElement('button');
      b.type = 'button';
      b.setAttribute('data-no-icon', '');
      b.textContent = again === 'redo' ? 'Redo' : 'Undo';
      b.addEventListener('click', () => appUndo(again));
      el.appendChild(b);
    }
    (document.body || document.documentElement).appendChild(el);
    requestAnimationFrame(() => el.classList.add('show'));
    setTimeout(() => { el.classList.remove('show'); setTimeout(() => el.remove(), 400); }, 6000);
  }

  function afterReload() {
    let note = null;
    try { note = JSON.parse(sessionStorage.getItem(KEY) || 'null'); sessionStorage.removeItem(KEY); } catch (e) { note = null; }
    if (!note || note.page !== location.href) return;
    toast(note.text, note.again);
    // The page fills in as its data arrives: back to where it was once it's tall enough.
    let tries = 0;
    const back = () => {
      const box = scroller();
      if (box.scrollHeight - box.clientHeight >= note.y - 2 || tries > 30) { box.scrollTop = note.y; return; }
      tries += 1;
      setTimeout(back, 50);
    };
    back();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', afterReload);
  else afterReload();
})();

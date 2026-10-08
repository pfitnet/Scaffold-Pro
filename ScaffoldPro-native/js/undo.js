'use strict';

// Undo / Redo the last action: ⌘Z or Ctrl+Z undoes, ⇧⌘Z, ⌘Y or Ctrl+Y
// redoes (and Edit › Undo / Redo). The app notes what each action changed
// (UndoJournal in main.swift) and puts it back; the page is then redrawn
// where it is — not reloaded, so nothing flashes — with what changed
// softly lit for a moment (scrolled to, if it's out of sight) and
// "Undone: Add line item (BOQ)  [Redo]" at the bottom. A page redraws
// with its window.appRefresh(); one without it is reloaded.
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
      const text = `${kind === 'redo' ? 'Redone' : 'Undone'}: ${r.label}`;
      const again = kind === 'redo' ? (r.canUndo ? 'undo' : null) : (r.canRedo ? 'redo' : null);
      // Redrawn in place, what changed lit up.
      if (typeof window.appRefresh === 'function') {
        const box = scroller();
        const y = box.scrollTop;
        const before = snapshot();
        try {
          await window.appRefresh();
          await new Promise((done) => setTimeout(done, 160)); // (parts drawn after it)
          box.scrollTop = y;
          showChanges(before, snapshot());
          toast(text, again);
          return;
        } catch (e) { /* fall back to reloading */ }
      }
      // Reloaded where it was, then told what happened.
      try {
        sessionStorage.setItem(KEY, JSON.stringify({ text, again, y: scroller().scrollTop, page: location.href }));
      } catch (e) { /* ignore */ }
      window.softReload();
    } finally {
      busy = false;
    }
  }
  window.appUndo = appUndo;

  // ---- What an undo changed ----
  // Rows (and project cards) by what they say — a row that wasn't there
  // before, or now says something else; other boxes and totals by where
  // they are (their id, or their place).
  const ROWS = 'tbody > tr, .pj-card, .file-row';
  const FIELDS = 'input:not([type=hidden]):not([type=checkbox]):not([type=radio]), textarea, select, input[type=checkbox], .grand-total, .pd-stat, .doc-total, .totals-box, h1';
  const visible = (el) => el.offsetParent !== null && !el.closest('.app-undo-toast, .hm-menu, .app-calendar');
  const said = (el) => (el.textContent || '').replace(/\s+/g, ' ').trim() +
    [...el.querySelectorAll('input, textarea, select')].map((x) => `|${x.type === 'checkbox' ? x.checked : x.value}`).join('');
  function placeOf(el, root) {
    const parts = [];
    for (let n = el; n && n !== root; n = n.parentElement) {
      if (n.id) { parts.unshift(`#${n.id}`); break; }
      let i = 0;
      for (let sib = n.previousElementSibling; sib; sib = sib.previousElementSibling) if (sib.tagName === n.tagName) i += 1;
      parts.unshift(`${n.tagName}:${i}`);
    }
    return parts.join('>');
  }
  function snapshot() {
    const root = document.getElementById('content') || document.body;
    const rows = new Map();
    for (const el of root.querySelectorAll(ROWS)) if (visible(el)) rows.set(said(el), (rows.get(said(el)) || 0) + 1);
    const fields = new Map();
    for (const el of root.querySelectorAll(FIELDS)) {
      if (!visible(el) || el.closest(ROWS)) continue;
      fields.set(placeOf(el, root), el.matches('input, textarea, select') ? (el.type === 'checkbox' ? String(el.checked) : el.value) : said(el));
    }
    return { root, rows, fields };
  }
  function showChanges(before, after) {
    const changed = [];
    const left = new Map(before.rows);
    for (const el of after.root.querySelectorAll(ROWS)) {
      if (!visible(el)) continue;
      const key = said(el);
      if (left.get(key)) left.set(key, left.get(key) - 1);
      else changed.push(el);
    }
    for (const el of after.root.querySelectorAll(FIELDS)) {
      if (!visible(el) || el.closest(ROWS)) continue;
      const place = placeOf(el, after.root);
      const now = after.fields.get(place);
      if (before.fields.has(place) && before.fields.get(place) !== now) changed.push(el);
    }
    // Everything redrawn differently (a new order, another tab): no lights.
    if (!changed.length || changed.length > 15) return;
    for (const el of changed) {
      el.classList.remove('undo-changed');
      void el.offsetWidth;
      el.classList.add('undo-changed');
      setTimeout(() => el.classList.remove('undo-changed'), 2600);
    }
    const first = changed[0];
    const r = first.getBoundingClientRect();
    if (r.bottom < 0 || r.top > window.innerHeight) first.scrollIntoView({ block: 'center', behavior: 'smooth' });
  }

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

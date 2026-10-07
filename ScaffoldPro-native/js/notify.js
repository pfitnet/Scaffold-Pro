'use strict';

// Notices on every page (loaded by js/sidebar.js): announcements meant for
// me personally — above all "… asked you to sign and chop Qt…" — float in
// the corner of whatever page is open, as soon as they arrive, and stay
// until they're closed (closed stays closed on every Mac) or answered.
// The Dashboard and Team pages show them in their own bar instead.

(function () {
  if (window.__notify) return;
  window.__notify = true;
  const page = document.body && document.body.dataset.page;
  if (page === 'dashboard' || page === 'team' || !window.api || !window.api.announcements) return;
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const PEN = '<svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 15.5c2-1 3.5-4 5-4s0 3 1.5 3 3-5 4.5-5 1 2.5 3 2.5"/><path d="M3 17.5h14"/></svg>';
  const MEGAPHONE = '<svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3.5 8.5v3a1 1 0 0 0 1 1H6l5 3.5v-12L6 7.5H4.5a1 1 0 0 0-1 1z"/><path d="M14 7.5a3.5 3.5 0 0 1 0 5M6.5 12.5l1 4"/></svg>';
  const CLOSE = '<svg viewBox="0 0 12 12" width="11" height="11" aria-hidden="true"><path d="M3 3l6 6M9 3l-6 6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>';

  let box = null;
  const shown = new Map();   // id → element

  function ensureBox() {
    if (box) return box;
    box = document.createElement('div');
    box.className = 'notify-stack';
    box.setAttribute('role', 'region');
    box.setAttribute('aria-label', 'Notices');
    document.body.appendChild(box);
    return box;
  }

  function card(a) {
    const el = document.createElement('div');
    const sign = !!a.signRequestId;
    el.className = `notify-card${sign ? ' sign' : ''}${a.important ? ' important' : ''}`;
    el.dataset.id = a.id;
    el.setAttribute('role', 'alert');
    el.innerHTML = `
      <span class="notify-icon">${sign ? PEN : MEGAPHONE}</span>
      <div class="notify-body">
        <div class="notify-title">${sign ? 'Waiting for your signature' : 'For you'}</div>
        <div class="notify-text">${esc(a.message)}</div>
        ${a.link ? `<div class="notify-actions"><a class="button-like primary" href="${esc(a.link)}">${sign ? 'Review' : 'Open'}</a></div>` : ''}
      </div>
      <button type="button" class="notify-close" data-no-icon title="Close — it won’t show again" aria-label="Close">${CLOSE}</button>`;
    el.querySelector('.notify-close').addEventListener('click', async () => {
      el.classList.add('leaving');
      setTimeout(() => el.remove(), 260);
      shown.delete(a.id);
      try { await window.api.announcements.dismiss(a.id); } catch (e) { /* the next look puts it back */ }
    });
    return el;
  }

  async function look() {
    let p;
    try { p = await window.api.announcements.page(); } catch (e) { return; }
    const me = String((p && p.me) || '').toLowerCase();
    const rows = ((p && p.visible) || []).map((r) => r.announcement)
      .filter((a) => a.audience && a.audience.toLowerCase() === `@${me}`);
    const want = new Set(rows.map((a) => a.id));
    for (const [id, el] of shown) {
      if (!want.has(id)) { el.classList.add('leaving'); setTimeout(() => el.remove(), 260); shown.delete(id); }
    }
    for (const a of rows) {
      if (shown.has(a.id)) continue;
      const el = card(a);
      ensureBox().prepend(el);
      shown.set(a.id, el);
    }
  }

  function start() {
    look();
    // Quick to turn up: a look every few seconds, and on coming back.
    setInterval(look, 6000);
    window.addEventListener('focus', look);
    document.addEventListener('visibilitychange', () => { if (!document.hidden) look(); });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();

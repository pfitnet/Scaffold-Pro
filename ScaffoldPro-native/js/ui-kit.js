'use strict';

// The shared parts every page builds the same way (docs/redesign/PLAN.md §2.7).
// Loaded on every page straight after js/dialogs.js and js/icons.js.
//
//   appTabs(el, { param: 'tab', onChange, map })   one tab row: .active, ←/→, ?tab= (replaceState only)
//   appToast(text, { action: { label, run }, kind, timeout })   the one toast stack
//   appSheet({ title, size, body, actions, onClose })            a sheet built from JS
//   statTile({ label, value, sub, href, onClick, tone, icon })   a figure tile (.stat-card)
//   searchField(input, { slash: true })                         icon, Esc clears, / focuses
//   pageActions(header, { primary, overflow })                  [···] [Primary] in a page header
//   crumbs([{ label, href }, …])                                breadcrumbs for nested pages

(function () {
  if (window.appTabs) return;
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const ico = (name, size) => (window.icon ? window.icon(name, { size: size || 16 }) : '');

  // ---------- Tabs ----------
  function appTabs(el, opts) {
    const o = opts || {};
    const param = o.param === undefined ? 'tab' : o.param;
    const buttons = () => [...el.querySelectorAll(':scope > button[data-tab], :scope > [role="tab"][data-tab]')];
    el.setAttribute('role', 'tablist');
    function select(name, how) {
      const all = buttons();
      const target = all.find((b) => b.dataset.tab === name) || all[0];
      if (!target) return;
      for (const b of all) {
        const on = b === target;
        b.classList.toggle('active', on);
        b.setAttribute('role', 'tab');
        b.setAttribute('aria-selected', on ? 'true' : 'false');
        b.tabIndex = on ? 0 : -1;
      }
      if (param && how !== 'init') {
        const url = new URL(location.href);
        url.searchParams.set(param, target.dataset.tab);
        history.replaceState(history.state, '', url);
      }
      if (o.onChange) o.onChange(target.dataset.tab, how);
    }
    el.addEventListener('click', (e) => {
      const b = e.target.closest('[data-tab]');
      if (b && el.contains(b) && !b.disabled) select(b.dataset.tab, 'click');
    });
    el.addEventListener('keydown', (e) => {
      if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
      const all = buttons().filter((b) => !b.disabled && b.offsetParent !== null);
      const at = all.findIndex((b) => b.classList.contains('active'));
      const next = all[(at + (e.key === 'ArrowRight' ? 1 : -1) + all.length) % all.length];
      if (!next) return;
      e.preventDefault();
      select(next.dataset.tab, 'key');
      next.focus();
    });
    let first = param ? new URLSearchParams(location.search).get(param) : null;
    if (first && o.map && o.map[first]) first = o.map[first];
    const initial = first || o.initial || (buttons().find((b) => b.classList.contains('active')) || buttons()[0] || {}).dataset?.tab;
    if (initial) select(initial, 'init');
    return { select, current: () => (buttons().find((b) => b.classList.contains('active')) || {}).dataset?.tab };
  }

  // ---------- Toasts ----------
  let stack = null;
  function appToast(text, opts) {
    const o = opts || {};
    if (!stack) {
      stack = document.createElement('div');
      stack.className = 'toast-stack';
      stack.setAttribute('aria-live', 'polite');
      document.body.appendChild(stack);
    }
    const t = document.createElement('div');
    t.className = `toast${o.kind ? ` toast-${o.kind}` : ''}`;
    t.innerHTML = `<span class="toast-text">${esc(text)}</span>`;
    if (o.action) {
      const b = document.createElement('button');
      b.type = 'button';
      b.dataset.noIcon = '';
      b.textContent = o.action.label;
      b.addEventListener('click', () => { dismiss(); o.action.run && o.action.run(); });
      t.appendChild(b);
    }
    stack.appendChild(t);
    requestAnimationFrame(() => t.classList.add('show'));
    let timer = setTimeout(dismiss, o.timeout || (o.action ? 6000 : 2400));
    t.addEventListener('pointerenter', () => clearTimeout(timer));
    t.addEventListener('pointerleave', () => { timer = setTimeout(dismiss, 1600); });
    function dismiss() {
      clearTimeout(timer);
      t.classList.remove('show');
      t.addEventListener('transitionend', () => t.remove(), { once: true });
      setTimeout(() => t.remove(), 400);
    }
    return { dismiss, el: t };
  }

  // ---------- Sheets ----------
  // The backdrop always carries .modal-backdrop: bridge.js (busy) and undo.js
  // hold sync redraws and ⌘Z while one is open.
  function appSheet(opts) {
    const o = opts || {};
    const back = document.createElement('div');
    back.className = 'modal-backdrop sheet-backdrop';
    const sheet = document.createElement('div');
    sheet.className = `modal sheet sheet-${o.size || 'md'}`;
    sheet.setAttribute('role', 'dialog');
    sheet.setAttribute('aria-modal', 'true');
    sheet.innerHTML = `${o.title ? `<div class="sheet-head"><h2>${esc(o.title)}</h2></div>` : ''}<div class="sheet-body"></div><div class="actions sheet-foot"></div>`;
    const body = sheet.querySelector('.sheet-body');
    if (typeof o.body === 'string') body.innerHTML = o.body;
    else if (o.body) body.appendChild(o.body);
    const foot = sheet.querySelector('.sheet-foot');
    for (const a of o.actions || [{ label: 'Done', primary: true }]) {
      const b = document.createElement('button');
      b.type = 'button';
      b.dataset.noIcon = '';
      b.textContent = a.label;
      if (a.primary) b.className = 'primary';
      if (a.danger) b.classList.add('danger-btn');
      if (a.left) b.classList.add('left');
      if (a.id) b.id = a.id;
      b.addEventListener('click', async () => {
        if (a.run) { const keep = await a.run(api); if (keep === false) return; }
        close(a.value);
      });
      foot.appendChild(b);
    }
    if (!foot.children.length) foot.remove();
    back.appendChild(sheet);
    document.body.appendChild(back);
    const prev = document.activeElement;
    const focusable = () => sheet.querySelectorAll('input:not([type=hidden]), select, textarea, button, [tabindex="0"]');
    setTimeout(() => { const f = focusable()[0]; if (f) f.focus(); }, 0);
    let done = false;
    const onKey = (e) => {
      if (back.nextElementSibling && back.nextElementSibling.matches('.modal-backdrop, .app-dialog-backdrop')) return; // a sheet above this one
      if (window.hoverMenu && window.hoverMenu.isOpen()) return;
      if (e.key === 'Escape' && !e.defaultPrevented) { e.preventDefault(); close(); }
      if (e.key === 'Enter' && !e.shiftKey && e.target.tagName !== 'TEXTAREA' && !e.target.closest('button')) {
        const primary = foot.querySelector('button.primary');
        if (primary && !primary.disabled) { e.preventDefault(); primary.click(); }
      }
    };
    document.addEventListener('keydown', onKey);
    back.addEventListener('mousedown', (e) => { if (e.target === back && o.dismissOnBackdrop !== false) close(); });
    function close(value) {
      if (done) return;
      done = true;
      document.removeEventListener('keydown', onKey);
      back.remove();   // sheets close at once (HANDOFF §3)
      if (prev && prev.focus) prev.focus();
      if (o.onClose) o.onClose(value);
    }
    const api = { el: sheet, body, close };
    return api;
  }

  // ---------- Figure tiles ----------
  function statTile(opts) {
    const o = opts || {};
    const link = o.href || o.onClick;
    const el = document.createElement(o.href ? 'a' : link ? 'button' : 'div');
    el.className = `stat-card${o.tone ? ` tone-${o.tone}` : ''}${link ? ' stat-link' : ''}`;
    if (o.href) el.href = o.href;
    if (o.onClick) { if (el.tagName === 'BUTTON') el.type = 'button'; el.dataset.noIcon = ''; el.addEventListener('click', o.onClick); }
    if (o.title) el.title = o.title;
    el.innerHTML = `${o.icon ? `<span class="stat-icon">${ico(o.icon, 16)}</span>` : ''}<div class="value">${esc(o.value)}</div><div class="label">${esc(o.label)}</div>${o.sub ? `<div class="stat-sub">${esc(o.sub)}</div>` : ''}`;
    return el;
  }

  // ---------- Search fields ----------
  function searchField(input, opts) {
    const o = opts || {};
    if (!input || input.dataset.searchField) return input;
    input.dataset.searchField = '1';
    const wrap = document.createElement('label');
    wrap.className = 'search-field';
    input.parentNode.insertBefore(wrap, input);
    wrap.innerHTML = ico('search', 15);
    wrap.appendChild(input);
    if (o.slash !== false) {
      const k = document.createElement('kbd');
      k.textContent = '/';
      wrap.appendChild(k);
      document.addEventListener('keydown', (e) => {
        if (e.key !== '/' || e.metaKey || e.ctrlKey || e.altKey) return;
        const t = e.target;
        if (t.closest && t.closest('input, textarea, select, [contenteditable="true"], .modal-backdrop')) return;
        if (input.offsetParent === null) return;
        e.preventDefault();
        input.focus();
        input.select();
      });
    }
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && input.value) { e.stopPropagation(); input.value = ''; input.dispatchEvent(new Event('input', { bubbles: true })); }
    });
    return input;
  }

  // ---------- Page header actions: [···] [Primary] ----------
  function pageActions(header, opts) {
    const o = opts || {};
    let box = header.querySelector('.page-actions');
    if (!box) { box = document.createElement('div'); box.className = 'page-actions'; header.appendChild(box); }
    box.innerHTML = '';
    const items = (o.overflow || []).filter(Boolean);
    if (items.length) {
      const more = document.createElement('button');
      more.type = 'button';
      more.className = 'icon-btn more-btn';
      more.dataset.noIcon = '';
      more.title = 'More';
      more.setAttribute('aria-label', 'More');
      more.innerHTML = ico('more', 18);
      box.appendChild(more);
      if (window.hoverMenu) {
        window.hoverMenu.attach(more, {
          openOn: 'press',
          items: () => (typeof o.overflow === 'function' ? o.overflow() : items).filter(Boolean).map((it, i) => (it.group ? { group: it.group } : { label: it.label, sub: it.sub, value: i, disabled: it.disabled && it.disabled() })),
          onPick: (i) => { const list = (typeof o.overflow === 'function' ? o.overflow() : items).filter(Boolean); const it = list[i]; if (it && it.run) it.run(); },
        });
      }
    }
    if (o.primary) {
      const p = o.primary instanceof HTMLElement ? o.primary : document.createElement('button');
      if (!(o.primary instanceof HTMLElement)) {
        p.type = 'button';
        p.className = 'primary';
        p.dataset.noIcon = '';
        p.innerHTML = `${o.primary.icon ? ico(o.primary.icon, 15) : ''}<span>${esc(o.primary.label)}</span>`;
        if (o.primary.id) p.id = o.primary.id;
        if (o.primary.title) p.title = o.primary.title;
        p.addEventListener('click', o.primary.run);
      }
      box.appendChild(p);
    }
    return box;
  }

  // ---------- Breadcrumbs ----------
  function crumbs(trail) {
    const nav = document.createElement('nav');
    nav.className = 'crumbs';
    nav.setAttribute('aria-label', 'Breadcrumb');
    nav.innerHTML = trail.filter(Boolean).map((c, i, all) => (i < all.length - 1 && c.href
      ? `<a href="${esc(c.href)}">${esc(c.label)}</a><span class="crumb-sep" aria-hidden="true">${ico('caret-right', 11)}</span>`
      : `<span class="crumb-here">${esc(c.label)}</span>`)).join('');
    return nav;
  }

  Object.assign(window, { appTabs, appToast, appSheet, statTile, searchField, pageActions, crumbs });
})();

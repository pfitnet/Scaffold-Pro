'use strict';

// The app's own form controls, in place of the system's (loaded on every page):
//   • lists — every <select> opens the app's list (js/hover-menu.js), not
//     the system's pop-up menu;
//   • numbers — the system's ▲▼ arrows are hidden (css/styles.css); resting
//     on a number field shows the app's − / + stepper (hold to repeat);
//   • dates — a date (or month) field opens the app's calendar.
// The real <select> / <input> stays in the page and keeps its value, so the
// pages' own code reads and saves it as before: picking sets the value and
// fires "input" and "change", as the system's controls do. Fields added
// later (tables, dialogs) get the same, as they appear.

(function () {
  if (window.appControls) return;
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const fire = (el) => {
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  };

  // ---------- Lists ----------

  function enhanceSelect(select) {
    if (select.__appList || select.multiple || select.size > 1 || select.closest('.tb-pick') || select.hasAttribute('data-native')) return;
    if (!window.hoverMenu) return;
    select.__appList = window.hoverMenu.attach(select, {
      openOn: 'press',
      minWidth: 0,
      items: () => window.hoverMenu.selectItems(select),
      onPick: (value) => window.hoverMenu.pickInSelect(select, value),
    });
  }

  // ---------- Number stepper ----------

  let stepper = null;
  let stepFor = null;
  let hideTimer = null;
  function buildStepper() {
    stepper = document.createElement('div');
    stepper.className = 'num-stepper';
    stepper.setAttribute('data-no-icon', '');
    stepper.innerHTML = '<button type="button" tabindex="-1" data-d="1" data-no-icon aria-label="Up"><svg viewBox="0 0 10 6" width="9" height="6" aria-hidden="true"><path d="M1 5l4-4 4 4" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg></button>' +
      '<button type="button" tabindex="-1" data-d="-1" data-no-icon aria-label="Down"><svg viewBox="0 0 10 6" width="9" height="6" aria-hidden="true"><path d="M1 1l4 4 4-4" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/></svg></button>';
    document.body.appendChild(stepper);
    let repeat = null;
    const stop = () => { clearTimeout(repeat); clearInterval(repeat); repeat = null; };
    stepper.addEventListener('pointerdown', (e) => {
      const b = e.target.closest('button');
      e.preventDefault(); // the field keeps its focus
      if (!b || !stepFor) return;
      const d = Number(b.dataset.d);
      step(stepFor, d);
      b.classList.add('pressed');
      // Held down: keeps going, faster.
      repeat = setTimeout(() => { repeat = setInterval(() => stepFor && step(stepFor, d), 70); }, 380);
      const up = () => { stop(); b.classList.remove('pressed'); window.removeEventListener('pointerup', up); };
      window.addEventListener('pointerup', up);
    });
    stepper.addEventListener('pointerenter', () => clearTimeout(hideTimer));
    stepper.addEventListener('pointerleave', () => scheduleHide());
  }
  function step(input, d) {
    if (input.disabled || input.readOnly) return;
    const before = input.value;
    try {
      if (d > 0) input.stepUp(); else input.stepDown();
    } catch (e) {
      // step="any": by one.
      const v = Number(input.value) || 0;
      let next = v + d;
      if (input.min !== '' && next < Number(input.min)) next = Number(input.min);
      if (input.max !== '' && next > Number(input.max)) next = Number(input.max);
      input.value = String(next);
    }
    if (input.value !== before) fire(input);
  }
  function placeStepper(input) {
    if (!stepper) buildStepper();
    const r = input.getBoundingClientRect();
    if (!r.width || !r.height) { hideStepper(); return; }
    const h = Math.min(r.height - 6, 26);
    stepper.style.height = `${h}px`;
    stepper.style.top = `${r.top + (r.height - h) / 2}px`;
    stepper.style.left = `${r.right - 20}px`;
    stepper.classList.add('show');
    stepFor = input;
  }
  function hideStepper() {
    clearTimeout(hideTimer);
    if (stepper) stepper.classList.remove('show');
    stepFor = null;
  }
  function scheduleHide() {
    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => {
      if (stepFor && (stepFor === document.activeElement || stepFor.matches(':hover'))) return;
      hideStepper();
    }, 160);
  }
  const usable = (input) => input && input.matches && input.matches('input[type="number"]') && !input.disabled && !input.readOnly && !input.closest('[data-native]');
  document.addEventListener('pointerover', (e) => {
    const input = e.target.closest && e.target.closest('input[type="number"]');
    if (usable(input)) { clearTimeout(hideTimer); placeStepper(input); }
  });
  document.addEventListener('pointerout', (e) => {
    const input = e.target.closest && e.target.closest('input[type="number"]');
    if (input && input === stepFor && !(stepper && stepper.contains(e.relatedTarget))) scheduleHide();
  });
  document.addEventListener('focusin', (e) => { if (usable(e.target)) placeStepper(e.target); });
  document.addEventListener('focusout', (e) => { if (e.target === stepFor) scheduleHide(); });
  document.addEventListener('scroll', () => { if (stepFor) { if (stepFor === document.activeElement) placeStepper(stepFor); else hideStepper(); } }, true);
  window.addEventListener('resize', () => stepFor && placeStepper(stepFor));
  // A wheel over a number field never changes it by accident.
  document.addEventListener('wheel', (e) => { if (e.target.matches && e.target.matches('input[type="number"]:focus')) e.target.blur(); }, { passive: true });

  // ---------- Calendar (date and month fields) ----------

  const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  const pad = (n) => String(n).padStart(2, '0');
  const iso = (y, m, d) => `${y}-${pad(m + 1)}-${pad(d)}`;
  let cal = null;
  function closeCalendar(refocus) {
    if (!cal) return;
    const { el, input } = cal;
    cal = null;
    el.classList.remove('open');
    setTimeout(() => el.remove(), 120);
    document.removeEventListener('pointerdown', outsideCalendar, true);
    if (refocus) input.focus({ preventScroll: true });
  }
  function outsideCalendar(e) {
    if (cal && !cal.el.contains(e.target) && e.target !== cal.input) closeCalendar(false);
  }
  function openCalendar(input) {
    if (cal && cal.input === input) return;
    closeCalendar(false);
    const monthMode = input.type === 'month';
    const today = new Date();
    const parts = (input.value || '').split('-').map(Number);
    let viewY = parts[0] || today.getFullYear();
    let viewM = parts[1] ? parts[1] - 1 : today.getMonth();
    const el = document.createElement('div');
    el.className = 'app-calendar';
    el.setAttribute('data-no-icon', '');
    el.setAttribute('role', 'dialog');
    el.setAttribute('aria-label', monthMode ? 'Choose a month' : 'Choose a date');
    document.body.appendChild(el);
    cal = { el, input };
    const inRange = (v) => (!input.min || v >= input.min) && (!input.max || v <= input.max);
    let redrawing = false;
    const draw = (focusValue) => {
      const value = input.value;
      redrawing = true;
      setTimeout(() => { redrawing = false; }, 0);
      let body = '';
      if (monthMode) {
        body = `<div class="cal-months">${MONTHS.map((name, m) => {
          const v = `${viewY}-${pad(m + 1)}`;
          return `<button type="button" class="cal-cell${v === value ? ' sel' : ''}${viewY === today.getFullYear() && m === today.getMonth() ? ' today' : ''}" data-v="${v}" data-no-icon ${inRange(v) ? '' : 'disabled'}>${name.slice(0, 3)}</button>`;
        }).join('')}</div>`;
      } else {
        const first = new Date(viewY, viewM, 1);
        const lead = (first.getDay() + 6) % 7; // Monday first, as the Calendar page
        const days = new Date(viewY, viewM + 1, 0).getDate();
        const prevDays = new Date(viewY, viewM, 0).getDate();
        let cells = '';
        const weeks = Math.ceil((lead + days) / 7);
        for (let i = 0; i < weeks * 7; i++) {
          let y = viewY, m = viewM, d = i - lead + 1, other = false;
          if (d < 1) { m -= 1; d += prevDays; other = true; }
          else if (d > days) { m += 1; d -= days; other = true; }
          if (m < 0) { m = 11; y -= 1; } else if (m > 11) { m = 0; y += 1; }
          const v = iso(y, m, d);
          const isToday = y === today.getFullYear() && m === today.getMonth() && d === today.getDate();
          cells += `<button type="button" class="cal-cell${other ? ' other' : ''}${v === value ? ' sel' : ''}${isToday ? ' today' : ''}" data-v="${v}" data-no-icon tabindex="-1" ${inRange(v) ? '' : 'disabled'}>${d}</button>`;
        }
        body = `<div class="cal-week">${['Mo', 'Tu', 'We', 'Th', 'Fr', 'Sa', 'Su'].map((w) => `<span>${w}</span>`).join('')}</div><div class="cal-days">${cells}</div>`;
      }
      el.innerHTML = `<div class="cal-top">
          <button type="button" class="cal-nav" data-nav="-1" data-no-icon aria-label="Previous"><svg viewBox="0 0 10 10" width="10" height="10" aria-hidden="true"><path d="M6.5 1.5 3 5l3.5 3.5" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg></button>
          <span class="cal-title">${monthMode ? viewY : `${MONTHS[viewM]} <b>${viewY}</b>`}</span>
          <button type="button" class="cal-nav" data-nav="1" data-no-icon aria-label="Next"><svg viewBox="0 0 10 10" width="10" height="10" aria-hidden="true"><path d="M3.5 1.5 7 5 3.5 8.5" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/></svg></button>
        </div>${body}
        <div class="cal-foot">
          ${input.required ? '<span></span>' : '<button type="button" class="cal-link" data-clear data-no-icon>Clear</button>'}
          <button type="button" class="cal-link cal-today" data-today data-no-icon>${monthMode ? 'This month' : 'Today'}</button>
        </div>`;
      const target = el.querySelector(`.cal-cell[data-v="${focusValue || value}"]`) || el.querySelector('.cal-cell.sel') || el.querySelector('.cal-cell.today') || el.querySelector('.cal-cell:not(.other):not([disabled])');
      if (target) target.setAttribute('tabindex', '0');
      return target;
    };
    const set = (v) => {
      const changed = input.value !== v;
      input.value = v;
      if (changed) fire(input);
      closeCalendar(true);
    };
    const place = () => {
      const r = input.getBoundingClientRect();
      const w = el.offsetWidth, h = el.offsetHeight;
      let left = Math.max(8, Math.min(r.left, window.innerWidth - w - 8));
      let top = r.bottom + 4;
      if (top + h > window.innerHeight - 8 && r.top - 4 - h > 8) top = r.top - 4 - h;
      el.style.left = `${left}px`;
      el.style.top = `${top}px`;
      el.classList.toggle('above', top < r.top);
    };
    draw();
    place();
    requestAnimationFrame(() => el.classList.add('open'));
    // A click in the calendar leaves the focus in the field (so typing still works there).
    el.addEventListener('pointerdown', (e) => e.preventDefault());
    el.addEventListener('mousedown', (e) => e.preventDefault());
    el.addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b || b.disabled) return;
      if (b.dataset.nav) {
        const d = Number(b.dataset.nav);
        if (monthMode) viewY += d;
        else { viewM += d; if (viewM < 0) { viewM = 11; viewY -= 1; } else if (viewM > 11) { viewM = 0; viewY += 1; } }
        el.classList.remove('slide-l', 'slide-r');
        void el.offsetWidth;
        el.classList.add(d > 0 ? 'slide-l' : 'slide-r');
        draw();
        place();
      } else if (b.hasAttribute('data-clear')) set('');
      else if (b.hasAttribute('data-today')) set(monthMode ? `${today.getFullYear()}-${pad(today.getMonth() + 1)}` : iso(today.getFullYear(), today.getMonth(), today.getDate()));
      else if (b.dataset.v) set(b.dataset.v);
    });
    el.addEventListener('keydown', (e) => {
      const cur = document.activeElement && document.activeElement.dataset ? document.activeElement.dataset.v : null;
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); closeCalendar(true); return; }
      if (!cur || monthMode) return;
      const moves = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 };
      if (moves[e.key] != null) {
        e.preventDefault();
        const [y, m, d] = cur.split('-').map(Number);
        const next = new Date(y, m - 1, d + moves[e.key]);
        const v = iso(next.getFullYear(), next.getMonth(), next.getDate());
        if (next.getMonth() !== viewM || next.getFullYear() !== viewY) { viewY = next.getFullYear(); viewM = next.getMonth(); }
        const t = draw(v);
        if (t) t.focus();
      }
    });
    el.addEventListener('focusout', (e) => {
      if (redrawing) return; // the focused day was redrawn
      if (cal && cal.el === el && !el.contains(e.relatedTarget) && e.relatedTarget !== input) closeCalendar(false);
    });
    document.addEventListener('pointerdown', outsideCalendar, true);
  }
  const dateLike = (el) => el && el.matches && el.matches('input[type="date"], input[type="month"]') && !el.disabled && !el.readOnly && !el.closest('[data-native]');
  // A click on a date field opens the calendar (not the system's); typing in it still works.
  document.addEventListener('mousedown', (e) => {
    const input = e.target;
    if (!dateLike(input) || e.button !== 0) return;
    e.preventDefault();
    input.focus({ preventScroll: true });
    if (cal && cal.input === input) closeCalendar(false); else openCalendar(input);
  }, true);
  document.addEventListener('keydown', (e) => {
    const input = e.target;
    if (!dateLike(input)) return;
    // ↓ with ⌥, or Space: the calendar, with the chosen day ready for the arrow keys.
    if ((e.key === 'ArrowDown' && e.altKey) || e.key === ' ') {
      e.preventDefault();
      openCalendar(input);
      const t = cal && cal.el.querySelector('.cal-cell[tabindex="0"]');
      if (t) t.focus();
    } else if (e.key === 'Escape' && cal) { e.preventDefault(); closeCalendar(true); }
  }, true);
  document.addEventListener('scroll', (e) => { if (cal && !cal.el.contains(e.target)) closeCalendar(false); }, true);
  window.addEventListener('resize', () => closeCalendar(false));

  // ---------- Fields added later ----------

  function scan(root) {
    if (!root || !root.querySelectorAll) return;
    if (root.tagName === 'SELECT') enhanceSelect(root);
    root.querySelectorAll('select').forEach(enhanceSelect);
  }
  function start() {
    scan(document.body);
    new MutationObserver((records) => {
      for (const r of records) for (const n of r.addedNodes) if (n.nodeType === 1) scan(n);
    }).observe(document.body, { childList: true, subtree: true });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();

  window.appControls = { enhanceSelect, openCalendar, closeCalendar };
})();

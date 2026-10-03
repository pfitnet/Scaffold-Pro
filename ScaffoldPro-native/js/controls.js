'use strict';

// The app's own form controls, in place of the system's (loaded on every page):
//   • lists — every <select> opens the app's list (js/hover-menu.js), not
//     the system's pop-up menu;
//   • numbers — the system's ▲▼ arrows are hidden (css/styles.css); resting
//     on a number field shows the app's − / + stepper (hold to repeat);
//   • dates — a date (or month) field opens the app's calendar, and is
//     typed as 24/09/2026 (09/2026 for a month) and shown as 24 Sep 2026
//     (Sep 2026), whatever the Mac's region is set to.
// The real <select> / <input> stays in the page and keeps its value, so the
// pages' own code reads and saves it as before: picking sets the value and
// fires "input" and "change", as the system's controls do. (A date field's
// value is still "2026-09-24", as the system's.) Fields added later
// (tables, dialogs) get the same, as they appear.
//
//   window.appDay('2026-09-24')  → "24 Sep 2026" (for dates shown in lists)

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
    const monthMode = (input.dataset.date || input.type) === 'month';
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
    // A date typed in the field: the calendar turns to it.
    cal.sync = () => {
      const [y, m] = (input.value || '').split('-').map(Number);
      if (!y) return;
      viewY = y;
      if (m) viewM = m - 1;
      draw();
      place();
    };
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
  const dateLike = (el) => el && el.matches && el.matches('input[type="date"], input[type="month"], input[data-date]') && !el.disabled && !el.readOnly && !el.closest('[data-native]');
  // A click on a date field opens the calendar (not the system's); typing in it still works.
  document.addEventListener('mousedown', (e) => {
    const input = e.target;
    if (!dateLike(input) || e.button !== 0) return;
    // Already typing in it: the click still places the cursor.
    if (!(input.dataset.date && document.activeElement === input)) {
      e.preventDefault();
      input.focus({ preventScroll: true });
    }
    if (cal && cal.input === input) closeCalendar(false); else openCalendar(input);
  }, true);
  document.addEventListener('keydown', (e) => {
    const input = e.target;
    if (!dateLike(input)) return;
    // ↓ (a typed date field), ⌥↓, or Space (the system's): the calendar,
    // with the chosen day ready for the arrow keys.
    if ((e.key === 'ArrowDown' && (e.altKey || input.dataset.date)) || (e.key === ' ' && !input.dataset.date)) {
      e.preventDefault();
      if (input.dataset.date) commitDate(input);
      openCalendar(input);
      const t = cal && cal.el.querySelector('.cal-cell[tabindex="0"]');
      if (t) t.focus();
    } else if (e.key === 'Escape' && cal) { e.preventDefault(); closeCalendar(true); }
  }, true);

  // ---------- Date fields: typed 24/09/2026, shown 24 Sep 2026 ----------
  // The system's date field follows the Mac's region (09/24/2026 in the US).
  // Each one becomes a text field that reads and writes "2026-09-24" as its
  // value, as before, but is typed day first and shown as 24 Sep 2026.
  // Typing takes 24/09/2026, 24/9/26, 24-9, 24.09.2026, 24092026, 24 Sep
  // 2026, 24sep or 2026-09-24 (no year: this year); "today" too.

  const MON = MONTHS.map((name) => name.slice(0, 3));
  const nativeValue = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value');
  const isDay = (y, m, d) => { const t = new Date(y, m - 1, d); return y > 999 && t.getFullYear() === y && t.getMonth() === m - 1 && t.getDate() === d; };
  const fullYear = (y) => (y === undefined || y === '' ? new Date().getFullYear() : String(y).length <= 2 ? 2000 + Number(y) : Number(y));
  const monthNamed = (word) => {
    const w = String(word || '').toLowerCase().replace(/\.$/, '');
    return w.length >= 3 ? MONTHS.findIndex((name) => name.toLowerCase().startsWith(w)) + 1 : 0;
  };
  // "2026-09-24" (or "2026-09"), "" for an empty box, null when it isn't a date.
  function parseDate(text, kind) {
    const s = String(text || '').trim().replace(/,/g, ' ').replace(/\s+/g, ' ');
    if (!s) return '';
    const out = (y, m, d) => (kind === 'month'
      ? (m >= 1 && m <= 12 && y > 999 ? `${y}-${pad(m)}` : null)
      : (isDay(y, m, d) ? `${y}-${pad(m)}-${pad(d)}` : null));
    let r;
    if (/^today$/i.test(s)) { const t = new Date(); return out(t.getFullYear(), t.getMonth() + 1, t.getDate()); }
    if ((r = /^(\d{4})-(\d{1,2})(?:-(\d{1,2}))?/.exec(s))) return out(Number(r[1]), Number(r[2]), Number(r[3] || 1));
    if (kind === 'month') {
      if ((r = /^(\d{1,2})\s?[/.\- ]\s?(\d{2}|\d{4})$/.exec(s))) return out(fullYear(r[2]), Number(r[1]));
      if ((r = /^([a-z]+\.?)\s?(\d{2}|\d{4})?$/i.exec(s))) return out(fullYear(r[2]), monthNamed(r[1]));
      return null;
    }
    if ((r = /^(\d{1,2})\s?[/.\- ]\s?(\d{1,2})(?:\s?[/.\- ]\s?(\d{2}|\d{4}))?$/.exec(s))) return out(fullYear(r[3]), Number(r[2]), Number(r[1]));
    if ((r = /^(\d{2})(\d{2})(\d{4}|\d{2})$/.exec(s))) return out(fullYear(r[3]), Number(r[2]), Number(r[1]));
    if ((r = /^(\d{1,2})\s?([a-z]+\.?)\s?(\d{2}|\d{4})?$/i.exec(s))) return out(fullYear(r[3]), monthNamed(r[2]), Number(r[1]));
    if ((r = /^([a-z]+\.?)\s?(\d{1,2})\s(\d{4})$/i.exec(s))) return out(Number(r[3]), monthNamed(r[1]), Number(r[2]));
    return null;
  }
  // Typed: 24/09/2026 · shown: 24 Sep 2026 (months: 09/2026 · Sep 2026).
  const typedDate = (iso, kind) => {
    const [y, m, d] = String(iso || '').split('-');
    if (!y) return '';
    return kind === 'month' ? `${m}/${y}` : `${d}/${m}/${y}`;
  };
  const shownDate = (iso, kind) => {
    const [y, m, d] = String(iso || '').split('-').map(Number);
    if (!y || !m) return '';
    return kind === 'month' ? `${MON[m - 1]} ${y}` : `${d} ${MON[m - 1]} ${y}`;
  };
  // For dates shown in lists and tables: "24 Sep 2026" (a timestamp: its day).
  window.appDay = (value, empty = '—') => {
    const v = String(value || '');
    const iso = /^\d{4}-\d{2}-\d{2}T/.test(v) && !isNaN(new Date(v))
      ? (() => { const t = new Date(v); return `${t.getFullYear()}-${pad(t.getMonth() + 1)}-${pad(t.getDate())}`; })()
      : v.slice(0, 10);
    return /^\d{4}-\d{2}-\d{2}$/.test(iso) ? shownDate(iso, 'date') : (v || empty);
  };

  function upgradeDate(input) {
    const kind = input.type;
    if (input.__dateKind || (kind !== 'date' && kind !== 'month') || input.closest('[data-native]')) return;
    const start = nativeValue.get.call(input);
    input.__dateKind = kind;
    input.__iso = '';
    input.type = 'text';
    input.dataset.date = kind;
    input.setAttribute('autocomplete', 'off');
    input.spellcheck = false;
    if (!input.placeholder) input.placeholder = kind === 'month' ? 'mm/yyyy' : 'dd/mm/yyyy';
    // .value is "2026-09-24", as the system's date field: while typing, the
    // typed date once it's a whole one.
    Object.defineProperty(input, 'value', {
      configurable: true,
      get() {
        if (input.__typing) { const p = parseDate(nativeValue.get.call(input), kind); if (p !== null) return p; }
        return input.__iso;
      },
      set(v) {
        const s = String(v ?? '');
        const p = /^\d{4}-\d{2}/.test(s) ? parseDate(s.slice(0, kind === 'month' ? 7 : 10), kind) : null;
        input.__iso = p || '';
        nativeValue.set.call(input, input.__typing ? typedDate(input.__iso, kind) : shownDate(input.__iso, kind));
      },
    });
    input.value = start;
  }
  // The typed date is taken (Return, or leaving the field); not a date: put back.
  function commitDate(input) {
    const kind = input.__dateKind;
    if (!kind) return;
    const p = parseDate(nativeValue.get.call(input), kind);
    const changed = p !== null && p !== input.__iso;
    if (p === null) {
      input.classList.add('calc-bad');
      setTimeout(() => input.classList.remove('calc-bad'), 900);
    } else input.__iso = p;
    nativeValue.set.call(input, input.__typing ? typedDate(input.__iso, kind) : shownDate(input.__iso, kind));
    if (changed) fire(input);
  }
  document.addEventListener('focusin', (e) => {
    const input = e.target;
    if (!input.__dateKind) return;
    input.__typing = true;
    nativeValue.set.call(input, typedDate(input.__iso, input.__dateKind));
    requestAnimationFrame(() => { if (document.activeElement === input) try { input.select(); } catch (err) { /* ignore */ } });
  }, true);
  document.addEventListener('focusout', (e) => {
    const input = e.target;
    if (!input.__dateKind) return;
    input.__typing = false;
    commitDate(input);
  }, true);
  // Typing isn't a change yet (the pages save on "change"): only the calendar follows it.
  document.addEventListener('input', (e) => {
    const input = e.target;
    if (!input.__dateKind || !e.isTrusted) return;
    e.stopPropagation();
    if (cal && cal.input === input && cal.sync && parseDate(nativeValue.get.call(input), input.__dateKind)) cal.sync();
  }, true);
  // (The text field's own "change" on leaving it: the date's is fired above, once taken.)
  document.addEventListener('change', (e) => { if (e.target.__dateKind && e.isTrusted) e.stopPropagation(); }, true);
  document.addEventListener('keydown', (e) => {
    const input = e.target;
    if (!input.__dateKind || e.isComposing || e.defaultPrevented) return;
    if (e.key === 'Enter') { commitDate(input); closeCalendar(false); }
    // Escape: what was typed goes back (a second Escape closes a dialog, as usual).
    else if (e.key === 'Escape' && !cal && nativeValue.get.call(input) !== typedDate(input.__iso, input.__dateKind)) {
      e.preventDefault();
      e.stopPropagation();
      nativeValue.set.call(input, typedDate(input.__iso, input.__dateKind));
      input.select();
    }
  }, true);
  document.addEventListener('scroll', (e) => { if (cal && !cal.el.contains(e.target)) closeCalendar(false); }, true);
  window.addEventListener('resize', () => closeCalendar(false));

  // ---------- Fields added later ----------

  function scan(root) {
    if (!root || !root.querySelectorAll) return;
    if (root.tagName === 'SELECT') enhanceSelect(root);
    else if (root.tagName === 'INPUT') upgradeDate(root);
    root.querySelectorAll('select').forEach(enhanceSelect);
    root.querySelectorAll('input[type="date"], input[type="month"]').forEach(upgradeDate);
  }
  function start() {
    scan(document.body);
    new MutationObserver((records) => {
      for (const r of records) for (const n of r.addedNodes) if (n.nodeType === 1) scan(n);
    }).observe(document.body, { childList: true, subtree: true });
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();

  window.appControls = { enhanceSelect, openCalendar, closeCalendar, upgradeDate, parseDate };
})();

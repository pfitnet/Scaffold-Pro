'use strict';

// Small, purposeful motion for every page (loaded by js/sidebar.js):
//   • the page rises in when it opens, and fades as you leave by a link;
//   • the sidebar's selection marker slides from the page you left to this one;
//   • a line slides under the chosen tab (.tabs), a pill under the chosen
//     choice of a segmented control (.segmented);
//   • numbers on stat cards count up to their value;
//   • cards catch a soft light where the pointer is (.panel, .stat-card, .form-card);
//   • buttons ripple where they're pressed.
// Everything is skipped with "Reduce motion" (System Settings › Accessibility).

(function () {
  if (window.__motion) return;
  window.__motion = true;
  const reduce = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
  const root = document.documentElement;
  const raf = (fn) => requestAnimationFrame(fn);
  const store = {
    get(k) { try { return sessionStorage.getItem(`motion.${k}`); } catch (e) { return null; } },
    set(k, v) { try { sessionStorage.setItem(`motion.${k}`, v); } catch (e) { /* private */ } },
  };

  // ---------- Page in / out ----------
  if (!reduce) {
    root.classList.add('page-enter');
    setTimeout(() => root.classList.remove('page-enter'), 1400);
  }
  document.addEventListener('click', (e) => {
    if (reduce || e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    const a = e.target.closest && e.target.closest('a[href]');
    if (!a || a.target === '_blank') return;
    const href = a.getAttribute('href') || '';
    if (!/\.html(\?|#|$)/.test(href) || /^[a-z]+:/i.test(href)) return;
    if (a.pathname === location.pathname && a.search === location.search) return;
    // Remember where the sidebar marker was, so it slides from there.
    const ink = document.querySelector('#sidebar .nav-ink');
    if (ink) store.set('inkTop', String(parseFloat(ink.style.top) || 0));
    e.preventDefault();
    root.classList.add('page-leave');
    setTimeout(() => { location.href = a.href; }, 120);
  });
  window.addEventListener('pageshow', () => root.classList.remove('page-leave'));

  // ---------- Sidebar marker ----------
  function placeNavInk(animate) {
    const bar = document.getElementById('sidebar');
    const active = bar && bar.querySelector('a.active:not(.sidebar-brand)');
    if (!bar || !active) return false;
    let ink = bar.querySelector('.nav-ink');
    if (!ink) {
      ink = document.createElement('div');
      ink.className = 'nav-ink';
      ink.setAttribute('aria-hidden', 'true');
      bar.insertBefore(ink, bar.firstChild);
      const from = Number(store.get('inkTop'));
      if (!reduce && Number.isFinite(from) && from > 0) {
        ink.style.transition = 'none';
        ink.style.top = `${from}px`;
        ink.style.height = `${active.offsetHeight}px`;
        void ink.offsetHeight;
        ink.style.transition = '';
      }
      bar.classList.add('has-ink');
    }
    if (!animate) ink.style.transition = 'none';
    ink.style.top = `${active.offsetTop}px`;
    ink.style.height = `${active.offsetHeight}px`;
    if (!animate) { void ink.offsetHeight; ink.style.transition = ''; }
    store.set('inkTop', String(active.offsetTop));
    return true;
  }

  // ---------- Tab line and segmented pill ----------
  function placeInk(container, cls, vertical) {
    const active = container.querySelector(':scope > button.active, :scope > .active');
    let ink = container.querySelector(`:scope > .${cls}`);
    if (!active || active.offsetParent === null) { if (ink) ink.style.opacity = '0'; return; }
    if (!ink) {
      ink = document.createElement('span');
      ink.className = cls;
      ink.setAttribute('aria-hidden', 'true');
      ink.style.transition = 'none';
      // A page that colours its chosen choice (e.g. blue): the pill wears that.
      if (cls === 'seg-ink') {
        // Read the settled colours, not a colour change still under way.
        const was = active.style.transition;
        active.style.transition = 'none';
        const cs = getComputedStyle(active);
        void cs.color;
        if (cs.backgroundImage !== 'none') ink.style.backgroundImage = cs.backgroundImage;
        else if (cs.backgroundColor && !/rgba\(0, 0, 0, 0\)|transparent/.test(cs.backgroundColor)) ink.style.backgroundColor = cs.backgroundColor;
        container.style.setProperty('--seg-text', cs.color);
        active.style.transition = was;
      }
      container.appendChild(ink);
      container.classList.add('has-ink');
      raf(() => { ink.style.transition = ''; });
    }
    ink.style.opacity = '1';
    ink.style.width = `${active.offsetWidth}px`;
    ink.style.transform = `translateX(${active.offsetLeft}px)`;
    void vertical;
  }
  function placeAll() {
    for (const t of document.querySelectorAll('.tabs')) placeInk(t, 'tab-ink');
    for (const s of document.querySelectorAll('.segmented')) placeInk(s, 'seg-ink');
  }

  // ---------- Counting numbers ----------
  const NUM = /^(\D*?)(-?[\d,]*\.?\d+)(\D*)$/;
  const running = new WeakSet();
  function countUp(el) {
    if (reduce || running.has(el)) return;
    const text = el.textContent.trim();
    const m = NUM.exec(text);
    if (!m) return;
    const target = Number(m[2].replace(/,/g, ''));
    if (!Number.isFinite(target) || target === 0) return;
    const decimals = (m[2].split('.')[1] || '').length;
    const commas = m[2].includes(',');
    const fmt = (v) => m[1] + (commas
      ? v.toLocaleString('en-US', { minimumFractionDigits: decimals, maximumFractionDigits: decimals })
      : v.toFixed(decimals)) + m[3];
    // The final text rides along on the element, so a copy made mid-count
    // (a widget being moved) can be put straight.
    el.dataset.countFinal = text;
    running.add(el);
    const start = performance.now();
    const dur = Math.min(1100, 500 + Math.log10(Math.abs(target) + 1) * 140);
    const step = (now) => {
      // The page changed it meanwhile: leave the page's text.
      if (!el.isConnected || el.dataset.countFinal !== text) { running.delete(el); return; }
      const k = Math.min(1, (now - start) / dur);
      const eased = 1 - Math.pow(1 - k, 4);
      el.textContent = k < 1 ? fmt(target * eased) : text;
      if (k < 1) raf(step); else { running.delete(el); delete el.dataset.countFinal; }
    };
    raf(step);
  }
  const counted = new WeakSet();
  function countNew() {
    for (const el of document.querySelectorAll('.stat-card .value, .pd-stat b, .pd-stat .value, [data-count-final]')) {
      // A copy of a number still counting: its final text.
      if (el.dataset.countFinal && !running.has(el)) { el.textContent = el.dataset.countFinal; delete el.dataset.countFinal; counted.add(el); continue; }
      if (counted.has(el) || !el.matches('.stat-card .value, .pd-stat b, .pd-stat .value')) continue;
      counted.add(el);
      countUp(el);
    }
  }

  // ---------- Light under the pointer ----------
  const SPOT = '.panel, .stat-card, .form-card';
  let spotEl = null;
  let spotXY = null;
  document.addEventListener('pointermove', (e) => {
    if (reduce || e.pointerType === 'touch') return;
    const el = e.target.closest && e.target.closest(SPOT);
    if (!el) return;
    if (!el.classList.contains('spot')) {
      if (getComputedStyle(el).position === 'static') el.style.position = 'relative';
      el.classList.add('spot');
    }
    spotEl = el;
    spotXY = [e.clientX, e.clientY];
    if (!placeSpot.queued) { placeSpot.queued = true; raf(placeSpot); }
  }, { passive: true });
  function placeSpot() {
    placeSpot.queued = false;
    if (!spotEl || !spotXY) return;
    const r = spotEl.getBoundingClientRect();
    spotEl.style.setProperty('--mx', `${spotXY[0] - r.left}px`);
    spotEl.style.setProperty('--my', `${spotXY[1] - r.top}px`);
  }

  // ---------- Ripple ----------
  document.addEventListener('pointerdown', (e) => {
    if (reduce || e.button !== 0) return;
    const b = e.target.closest && e.target.closest('button');
    if (!b || b.disabled || b.closest('.tabs, .segmented, .hm-menu, table, .tk-seg, .dp-zoom, [data-no-ripple]')) return;
    // Not where something inside is placed outside the button (a badge, a bubble).
    for (const c of b.children) if (getComputedStyle(c).position === 'absolute') return;
    const cs = getComputedStyle(b);
    if (cs.position === 'static') b.style.position = 'relative';
    const r = b.getBoundingClientRect();
    const size = Math.max(r.width, r.height) * 2.2;
    const dot = document.createElement('span');
    dot.className = 'ripple';
    dot.style.width = dot.style.height = `${size}px`;
    dot.style.left = `${e.clientX - r.left - size / 2}px`;
    dot.style.top = `${e.clientY - r.top - size / 2}px`;
    const overflow = b.style.overflow;
    b.style.overflow = 'hidden';
    b.appendChild(dot);
    setTimeout(() => { dot.remove(); if (!b.querySelector('.ripple')) b.style.overflow = overflow; }, 560);
  });

  // ---------- Keeping up with the page ----------
  let queued = false;
  function refresh() {
    queued = false;
    placeNavInk(true);
    placeAll();
    countNew();
  }
  const queue = () => { if (!queued) { queued = true; raf(refresh); } };
  function start() {
    placeNavInk(false);
    placeAll();
    countNew();
    new MutationObserver(queue).observe(document.body, { subtree: true, childList: true, attributes: true, attributeFilter: ['class', 'hidden'] });
    window.addEventListener('resize', queue);
    if (document.fonts && document.fonts.ready) document.fonts.ready.then(queue);
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start);
  else start();
})();

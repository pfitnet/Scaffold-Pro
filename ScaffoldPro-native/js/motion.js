'use strict';

// Small, purposeful motion for every page (loaded by js/sidebar.js):
//   • the page rises in when it opens, and fades as you leave by a link;
//   • the sidebar's selection marker slides from the page you left to this one;
//   • a line slides under the chosen tab (.tabs), a pill under the chosen
//     choice of a segmented control (.segmented);
//   • numbers on stat cards count up to their value, once a session per page;
// Buttons press in as the pointer goes down (css/styles.css), as on the Mac.
// The app doesn't follow the Mac's Reduce Motion (the user's choice; see HANDOFF §3).

(function () {
  if (window.__motion) return;
  window.__motion = true;
  const reduce = false;
  const root = document.documentElement;
  const raf = (fn) => requestAnimationFrame(fn);
  const store = {
    get(k) { try { return sessionStorage.getItem(`motion.${k}`); } catch (e) { return null; } },
    set(k, v) { try { sessionStorage.setItem(`motion.${k}`, v); } catch (e) { /* private */ } },
  };

  // ---------- Page in / out ----------
  // In the Mac app the window keeps a picture of the page being left until
  // this one is built, then shows it (Sources/Assistant.swift, NativeBridge's
  // WKNavigationDelegate; js/bridge.js says when, with 'app:shown'). The
  // rise in and the sidebar marker's slide wait for that, so they're seen.
  // ScaffoldPro Web in a browser has no picture: it rises in at once.
  const web = !!window.__scaffoldProWeb;
  const enter = () => {
    if (reduce) return;
    root.classList.add('page-enter');
    setTimeout(() => root.classList.remove('page-enter'), 900);
  };
  let held = !web;
  const shown = (e) => {
    if (!held) return;
    held = false;
    if (!(e && e.detail && e.detail.reload)) enter();
    placeNavInk(true);
  };
  if (web) enter();
  window.addEventListener('app:shown', shown);
  // Shown by the app without word from the page (a slow one): no rise, the marker just moves.
  setTimeout(() => shown({ detail: { reload: true } }), 1600);
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
    if (!web) return;
    e.preventDefault();
    root.classList.add('page-leave');
    setTimeout(() => { location.href = a.href; }, 120);
    // Still here (the page couldn't be opened): show this one again.
    setTimeout(() => root.classList.remove('page-leave'), 2500);
  });
  window.addEventListener('pageshow', () => root.classList.remove('page-leave'));

  // ---------- Sidebar marker ----------
  function placeNavInk(animate) {
    const bar = document.getElementById('sidebar');
    const active = bar && bar.querySelector('a.active:not(.sidebar-brand):not(.sidebar-user)');
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
        ink.dataset.from = '1';
      }
      bar.classList.add('has-ink');
    }
    // Still under the last page's picture: stay where that page had it.
    if (held && ink.dataset.from) return true;
    if (!animate) ink.style.transition = 'none';
    ink.style.top = `${active.offsetTop}px`;
    ink.style.height = `${active.offsetHeight}px`;
    if (!animate) { void ink.offsetHeight; ink.style.transition = ''; }
    store.set('inkTop', String(active.offsetTop));
    return true;
  }

  // The sidebar's tabs can be put in another order (js/sidebar.js): the marker follows.
  window.placeNavInk = () => placeNavInk(true);

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
  const seenKey = `count.${location.pathname.split('/').pop()}`;
  const seen = new Set((store.get(seenKey) || '').split('|').filter(Boolean));
  const saveSeen = () => store.set(seenKey, [...seen].slice(-40).join('|'));
  window.addEventListener('pagehide', saveSeen);
  setTimeout(saveSeen, 3000);
  function countUp(el) {
    if (reduce || running.has(el)) return;
    // Once a session per page: the first visit counts up, later ones show the figure.
    if (seen.has(el.textContent.trim())) return;
    seen.add(el.textContent.trim());
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

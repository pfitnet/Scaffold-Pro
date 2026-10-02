'use strict';

// The Dashboard's panels as widgets. "Customise" opens the widget editor:
//   • drag a panel by its bar to move it — a marker shows where it'll go
//     (the Dashboard scrolls near the window's top or bottom edge);
//   • drag its right edge to make it ¼, ½, ¾ or full width (it snaps to
//     the column guides);
//   • the Widgets tray on the right holds the ones not on the Dashboard:
//     drag one onto the Dashboard to add it, or drag a panel into the tray
//     (or press its ×) to take it off.
// Remembered for the person on this Mac.
//
//   window.setupWidgets(grid, button, userName);
//
// A panel's starting width is its data-span (1–4 quarters; 2 if not given).

(function () {
  const svg = (p) => `<svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${p}</svg>`;
  const GRIP = '<svg viewBox="0 0 10 16" width="10" height="16" aria-hidden="true" fill="currentColor"><circle cx="3" cy="3" r="1.3"/><circle cx="7" cy="3" r="1.3"/><circle cx="3" cy="8" r="1.3"/><circle cx="7" cy="8" r="1.3"/><circle cx="3" cy="13" r="1.3"/><circle cx="7" cy="13" r="1.3"/></svg>';
  const CROSS = '<svg viewBox="0 0 12 12" width="10" height="10" aria-hidden="true"><path d="M3 3l6 6M9 3l-6 6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>';
  // What each widget is, for the tray.
  const ABOUT = {
    quick: [svg('<path d="M11 2.5 4.5 11H10l-1 6.5L15.5 9H10z"/>'), 'Start a new project, quotation, task…'],
    tasks: [svg('<rect x="3.5" y="3.5" width="13" height="13" rx="2"/><path d="m6.8 10.2 2.2 2.2 4.3-4.6"/>'), 'Your open tasks'],
    inspections: [svg('<path d="M10 2.5 16 5v4.5c0 3.8-2.6 6.7-6 8-3.4-1.3-6-4.2-6-8V5z"/><path d="m7.3 10 2 2 3.6-4"/>'), 'Scaffolds due for inspection'],
    projects: [svg('<path d="M2.5 5.5a1 1 0 0 1 1-1h4l1.5 1.8h7.5a1 1 0 0 1 1 1V15a1 1 0 0 1-1 1h-13a1 1 0 0 1-1-1z"/>'), 'Projects you’ve worked on'],
    quotations: [svg('<path d="M11.5 2.5H5.5A1.5 1.5 0 0 0 4 4v12a1.5 1.5 0 0 0 1.5 1.5h9A1.5 1.5 0 0 0 16 16V7z"/><path d="M11.5 2.5V7H16"/>'), 'Issued, waiting for the signed copy'],
    unpaid: [svg('<path d="M5 2.5h10v15l-2-1.3-1.7 1.3-1.3-1.3-1.3 1.3L7 16.2l-2 1.3z"/><path d="M8 7h4M8 10h4"/>'), 'Invoices still to be paid'],
    documents: [svg('<rect x="4" y="3" width="12" height="14" rx="1.5"/><path d="M7 7h6M7 10h6M7 13h4"/>'), 'Documents you changed lately'],
    deliveries: [svg('<path d="M2.5 5.5h9v8h-9z"/><path d="M11.5 8.5h3l2.5 2.5v2.5h-5.5"/><circle cx="6" cy="14.5" r="1.5"/><circle cx="14" cy="14.5" r="1.5"/>'), 'Your latest delivery notes'],
    activity: [svg('<path d="M2.5 10h3l2-5 3 10 2-5h5"/>'), 'What you’ve done lately'],
    team: [svg('<circle cx="7.5" cy="7" r="2.6"/><path d="M2.8 16c.4-2.8 2.3-4.3 4.7-4.3s4.3 1.5 4.7 4.3"/><circle cx="14" cy="8" r="2"/><path d="M13 11.9c2.2-.2 3.8 1 4.2 3.6"/>'), 'What the rest of the team did'],
    attention: [svg('<path d="M10 3 2.5 16.5h15z"/><path d="M10 8v4M10 14.5v.01"/>'), 'Certificates expiring'],
  };
  const COLS = 4;
  const SIZE_NAME = { 1: '¼ width', 2: '½ width', 3: '¾ width', 4: 'Full width' };
  let grid = null;
  let tray = null;
  let key = 'dashboard.layout';
  let layout = { order: [], hidden: [], span: {} };

  const widgets = () => [...grid.querySelectorAll(':scope > [data-widget]')];
  const defaultSpan = (w) => Number(w.dataset.defaultSpan || w.dataset.span) || 2;
  const spanOf = (w) => layout.span[w.dataset.widget] || defaultSpan(w);
  const customising = () => grid.classList.contains('customising');

  function load() {
    try { layout = Object.assign({ order: [], hidden: [], span: {} }, JSON.parse(localStorage.getItem(key) || '{}')); } catch (e) { /* default */ }
    // Layouts saved before widths came in quarters: "wide" was full width.
    if (Array.isArray(layout.wide)) {
      for (const id of layout.wide) if (!layout.span[id]) layout.span[id] = COLS;
      delete layout.wide;
    }
  }
  function save() {
    layout.order = widgets().map((w) => w.dataset.widget);
    try { localStorage.setItem(key, JSON.stringify(layout)); } catch (e) { /* ignore */ }
  }

  function apply() {
    const byId = Object.fromEntries(widgets().map((w) => [w.dataset.widget, w]));
    // Saved order first; panels added since keep their place after them.
    for (const id of layout.order) if (byId[id]) grid.appendChild(byId[id]);
    for (const w of widgets()) {
      if (!w.dataset.defaultSpan) w.dataset.defaultSpan = String(defaultSpan(w));
      w.dataset.span = String(spanOf(w));
      w.classList.toggle('widget-off', layout.hidden.includes(w.dataset.widget));
    }
  }

  function setHidden(w, off) {
    const id = w.dataset.widget;
    layout.hidden = layout.hidden.filter((x) => x !== id);
    if (off) layout.hidden.push(id);
    w.classList.toggle('widget-off', off);
  }

  function setSpan(w, n) {
    n = Math.max(1, Math.min(COLS, n));
    if (n === defaultSpan(w)) delete layout.span[w.dataset.widget];
    else layout.span[w.dataset.widget] = n;
    w.dataset.span = String(n);
    const label = w.querySelector('.widget-size-label');
    if (label) label.textContent = SIZE_NAME[n];
  }

  function bar(w) {
    const el = document.createElement('div');
    el.className = 'widget-bar';
    el.innerHTML = `<span class="widget-grip" title="Drag to move — or into the Widgets tray to take it off">${GRIP}</span>
      <span class="widget-name">${w.dataset.title || w.dataset.widget}</span>
      <span class="widget-size-label" title="Drag the right edge to change the width">${SIZE_NAME[spanOf(w)]}</span>
      <button class="widget-remove" data-no-icon title="Take it off the Dashboard (it goes to the Widgets tray)" aria-label="Remove">${CROSS}</button>`;
    el.querySelector('.widget-remove').addEventListener('click', () => { setHidden(w, true); save(); refresh(); });
    // The whole bar is the handle.
    el.addEventListener('pointerdown', (e) => { if (!e.target.closest('button')) startDrag(e, w); });
    return el;
  }

  function handle(w) {
    const el = document.createElement('div');
    el.className = 'widget-resize';
    el.title = 'Drag to make it wider or narrower';
    el.addEventListener('pointerdown', (e) => startResize(e, w));
    return el;
  }

  // The column guides shown while customising (brighter while resizing).
  function guides() {
    let g = grid.querySelector(':scope > .widget-guides');
    if (!g) {
      g = document.createElement('div');
      g.className = 'widget-guides';
      g.innerHTML = '<div></div>'.repeat(COLS);
      grid.prepend(g);
    }
    return g;
  }

  // The tray of widgets not on the Dashboard.
  function drawTray() {
    if (!customising()) { if (tray) { tray.remove(); tray = null; } document.body.classList.remove('widget-editing'); return; }
    document.body.classList.add('widget-editing');
    if (!tray) {
      tray = document.createElement('aside');
      tray.className = 'widget-tray';
      document.body.appendChild(tray);
    }
    const off = widgets().filter((w) => w.classList.contains('widget-off'));
    tray.innerHTML = `<div class="tray-head"><div class="tray-title">Widgets</div>
      <div class="tray-sub">Drag one onto the Dashboard to add it. Drag a panel here to take it off.</div></div>
      <div class="tray-list">${off.length ? off.map((w) => {
        const [icon, about] = ABOUT[w.dataset.widget] || ['', ''];
        return `<div class="tray-card" data-for="${w.dataset.widget}" title="Drag onto the Dashboard — or click to add it at the end">
          <span class="tray-icon">${icon}</span><span class="tray-text"><b>${w.dataset.title || w.dataset.widget}</b><small>${about}</small></span>
          <span class="tray-grip">${GRIP}</span></div>`;
      }).join('') : '<div class="tray-empty">Every widget is on the Dashboard.</div>'}</div>
      <div class="tray-drop">Drop here to take it off</div>`;
    for (const card of tray.querySelectorAll('.tray-card')) {
      const w = widgets().find((x) => x.dataset.widget === card.dataset.for);
      card.addEventListener('pointerdown', (e) => startDrag(e, w, card));
    }
  }

  function refresh() {
    apply();
    for (const old of grid.querySelectorAll('.widget-bar, .widget-resize, .widget-guides')) old.remove();
    if (customising()) {
      guides();
      for (const w of widgets()) { w.prepend(bar(w)); w.appendChild(handle(w)); }
    }
    drawTray();
    if (grid.classList.contains('packed')) repack();
  }

  // How many columns the grid has right now (fewer in a narrow window).
  function columns() {
    return getComputedStyle(grid).gridTemplateColumns.split(' ').filter(Boolean).length || COLS;
  }

  // Drag the right edge: the width follows the pointer and snaps to the
  // nearest column line.
  function startResize(e, w) {
    e.preventDefault();
    e.stopPropagation();
    const cols = columns();
    const gap = parseFloat(getComputedStyle(grid).columnGap) || 0;
    const colW = (grid.getBoundingClientRect().width - gap * (cols - 1)) / cols;
    const left = w.getBoundingClientRect().left;
    const scale = COLS / cols; // a narrow window's 2 columns are 2 quarters each
    grid.classList.add('resizing');
    w.classList.add('widget-resizing');
    const move = (ev) => {
      const width = ev.clientX - left;
      const n = Math.round((width + gap) / (colW + gap));
      setSpan(w, Math.max(1, Math.min(cols, n)) * scale);
      repack();
    };
    const up = () => {
      document.removeEventListener('pointermove', move);
      document.removeEventListener('pointerup', up);
      grid.classList.remove('resizing');
      w.classList.remove('widget-resizing');
      save();
    };
    document.addEventListener('pointermove', move);
    document.addEventListener('pointerup', up);
  }

  // Drag a widget — from its bar, or from the tray: a card follows the
  // pointer and a bar marks where it will go (before or after the panel
  // under the pointer); nothing moves until it's dropped, so the panels
  // stay still under the pointer. Over the tray it comes off. Near the top
  // or bottom of the window the Dashboard scrolls.
  function startDrag(e, w, fromCard) {
    if (e.button !== 0) return;
    e.preventDefault();
    const scroller = grid.closest('#content') || document.scrollingElement;
    const ghost = document.createElement('div');
    ghost.className = 'widget-ghost';
    const [icon] = ABOUT[w.dataset.widget] || [''];
    ghost.innerHTML = `${icon}<span>${w.dataset.title || w.dataset.widget}</span>`;
    const marker = document.createElement('div');
    marker.className = 'widget-drop-marker';
    let started = false;
    let last = e;
    let drop = null; // { ref } (insert before ref; null = at the end) or { off: true }
    let target = null;
    // Kept inside the window (it flips to the pointer's left near the edge).
    const place = (ev) => {
      const x = ev.clientX + 12 + ghost.offsetWidth > innerWidth - 6 ? ev.clientX - ghost.offsetWidth - 12 : ev.clientX + 12;
      ghost.style.transform = `translate(${x}px, ${ev.clientY + 10}px)`;
    };
    const begin = () => {
      started = true;
      document.body.append(ghost, marker);
      document.body.classList.add('widget-dragging-any');
      if (fromCard) fromCard.classList.add('picked');
      w.classList.add('widget-dragging');
    };
    const mark = (t) => {
      if (target !== t) { if (target) target.classList.remove('widget-drop-target'); target = t; if (t) t.classList.add('widget-drop-target'); }
    };
    // Where a drop here would put it.
    const aim = () => {
      const ev = last;
      const over = document.elementFromPoint(ev.clientX, ev.clientY);
      const overTray = !!(over && over.closest('.widget-tray'));
      if (tray) tray.classList.toggle('drop-here', overTray && !w.classList.contains('widget-off'));
      marker.style.display = 'none';
      mark(null);
      drop = null;
      if (overTray) { drop = { off: true }; return; }
      const g = grid.getBoundingClientRect();
      if (ev.clientX < g.left - 40 || ev.clientX > g.right + 40 || ev.clientY < g.top - 40 || ev.clientY > g.bottom + 120) return;
      const shown = widgets().filter((x) => x !== w && !x.classList.contains('widget-off'));
      if (!shown.length) { drop = { ref: null }; return; }
      // The panel under the pointer — or the nearest one when it's in a gap.
      let best = null;
      let bestD = Infinity;
      for (const x of shown) {
        const r = x.getBoundingClientRect();
        const dx = Math.max(r.left - ev.clientX, 0, ev.clientX - r.right);
        const dy = Math.max(r.top - ev.clientY, 0, ev.clientY - r.bottom);
        const d = Math.hypot(dx, dy);
        if (d < bestD) { bestD = d; best = { x, r }; }
      }
      // Over the panel being moved: it stays where it is.
      const own = w.classList.contains('widget-off') ? null : w.getBoundingClientRect();
      if (own && ev.clientX >= own.left && ev.clientX <= own.right && ev.clientY >= own.top && ev.clientY <= own.bottom) return;
      const { x, r } = best;
      // Below everything: at the end.
      if (ev.clientY > g.bottom - 8 && bestD > 0) {
        drop = { ref: null };
        const tail = shown[shown.length - 1].getBoundingClientRect();
        Object.assign(marker.style, { display: 'block', left: `${g.left}px`, top: `${Math.max(tail.bottom, g.bottom) + 3}px`, width: `${g.width}px`, height: '4px' });
        return;
      }
      // A full-width panel splits top / bottom; others left / right.
      const full = r.width > g.width - 20;
      const after = full ? ev.clientY > r.top + r.height / 2 : ev.clientX > r.left + r.width / 2;
      drop = { ref: after ? x.nextElementSibling : x };
      mark(x);
      if (full) Object.assign(marker.style, { display: 'block', left: `${r.left}px`, top: `${(after ? r.bottom : r.top) - 2}px`, width: `${r.width}px`, height: '4px' });
      else Object.assign(marker.style, { display: 'block', left: `${(after ? r.right : r.left) - 2}px`, top: `${r.top}px`, width: '4px', height: `${r.height}px` });
    };
    // Scrolls while the pointer is near the top or bottom edge.
    let raf = 0;
    const edge = () => {
      raf = 0;
      if (!started) return;
      const s = scroller === document.scrollingElement ? { top: 0, bottom: innerHeight } : scroller.getBoundingClientRect();
      const zone = 70;
      const y = last.clientY;
      let v = 0;
      if (y < s.top + zone) v = -Math.ceil((s.top + zone - y) / 4);
      else if (y > s.bottom - zone) v = Math.ceil((y - (s.bottom - zone)) / 4);
      if (!v) return;
      const before = scroller.scrollTop;
      scroller.scrollTop += Math.max(-24, Math.min(24, v));
      if (scroller.scrollTop !== before) aim();
      raf = requestAnimationFrame(edge);
    };
    const onScroll = () => { if (started) aim(); };
    const move = (ev) => {
      last = ev;
      if (!started) {
        if (Math.hypot(ev.clientX - e.clientX, ev.clientY - e.clientY) < 4) return;
        begin();
      }
      place(ev);
      aim();
      if (!raf) raf = requestAnimationFrame(edge);
    };
    const end = (ev) => {
      document.removeEventListener('pointermove', move);
      document.removeEventListener('pointerup', end);
      document.removeEventListener('pointercancel', end);
      scroller.removeEventListener('scroll', onScroll);
      cancelAnimationFrame(raf);
      ghost.remove();
      marker.remove();
      mark(null);
      if (tray) tray.classList.remove('drop-here');
      document.body.classList.remove('widget-dragging-any');
      w.classList.remove('widget-dragging');
      if (fromCard) fromCard.classList.remove('picked');
      const cancelled = ev.type === 'pointercancel';
      if (!started) {
        // A click on a tray card (no drag) adds it at the end.
        if (fromCard && !cancelled) { setHidden(w, false); grid.appendChild(w); save(); refresh(); }
        return;
      }
      if (cancelled || !drop) return;
      if (drop.off) setHidden(w, true);
      else {
        setHidden(w, false);
        if (drop.ref !== w) grid.insertBefore(w, drop.ref);
      }
      save();
      refresh();
    };
    document.addEventListener('pointermove', move);
    document.addEventListener('pointerup', end);
    document.addEventListener('pointercancel', end);
    scroller.addEventListener('scroll', onScroll, { passive: true });
  }

  // Packing, so the Dashboard has no empty patches:
  //  1. each panel takes as many thin grid rows as it's tall, in order
  //     (the next one moves up beside a taller one);
  //  2. a panel with empty columns beside it all the way down its side
  //     widens into them;
  //  3. each grows up to the panel above it (or the top) and down to the
  //     one below it (or the bottom).
  const ROW = 2;
  function pack() {
    const gap = parseFloat(getComputedStyle(grid).getPropertyValue('--widget-gap')) || 14;
    const shown = widgets().filter((w) => getComputedStyle(w).display !== 'none');
    if (!shown.length) return;
    // Measuring puts the panels back in their natural places for a moment;
    // the grid keeps its height meanwhile, or the page would be cut short
    // and jump back to the top (WebKit doesn't hold the scroll position).
    const scroller = grid.closest('#content') || document.scrollingElement;
    const top = scroller.scrollTop;
    grid.style.minHeight = `${grid.offsetHeight}px`;
    for (const w of shown) { w.style.gridColumn = ''; w.style.gridRow = ''; w.style.alignSelf = 'start'; }
    for (const w of shown) {
      const h = w.getBoundingClientRect().height;
      w.style.gridRowEnd = `span ${Math.max(1, Math.ceil((h + gap) / ROW))}`;
    }
    const g = grid.getBoundingClientRect();
    const cols = columns();
    const colGap = parseFloat(getComputedStyle(grid).columnGap) || 0;
    const step = (g.width + colGap) / cols;
    const items = shown.map((w) => {
      const r = w.getBoundingClientRect();
      const c0 = Math.max(0, Math.round((r.left - g.left) / step));
      const r0 = Math.max(0, Math.round((r.top - g.top) / ROW));
      return { w, c0, c1: Math.min(cols, c0 + Math.max(1, Math.round((r.width + colGap) / step))), r0, r1: r0 + Math.max(1, Math.ceil((r.height + gap) / ROW)) };
    });
    const bottom = Math.max(...items.map((i) => i.r1));
    const clear = (c, ra, rb, self) => items.every((o) => o === self || o.c1 <= c || o.c0 > c || o.r1 <= ra || o.r0 >= rb);
    // 2. Widen into empty columns beside it — not while customising, so a
    //    panel shows the width it was given while it's being arranged.
    if (!customising()) for (const it of items) {
      while (it.c1 < cols && clear(it.c1, it.r0, it.r1, it)) it.c1 += 1;
      while (it.c0 > 0 && clear(it.c0 - 1, it.r0, it.r1, it)) it.c0 -= 1;
    }
    // 3. Grow up to the one above (or the top), then down to the next one below.
    for (const it of items) {
      const above = items.filter((o) => o !== it && o.r1 <= it.r0 && o.c0 < it.c1 && o.c1 > it.c0);
      it.r0 = above.length ? Math.max(...above.map((o) => o.r1)) : 0;
    }
    for (const it of items) {
      const below = items.filter((o) => o !== it && o.r0 >= it.r1 && o.c0 < it.c1 && o.c1 > it.c0);
      it.r1 = below.length ? Math.min(...below.map((o) => o.r0)) : bottom;
    }
    for (const it of items) {
      it.w.style.gridColumn = `${it.c0 + 1} / ${it.c1 + 1}`;
      it.w.style.gridRow = `${it.r0 + 1} / ${it.r1 + 1}`;
      it.w.style.alignSelf = 'stretch';
    }
    grid.style.minHeight = '';
    if (scroller.scrollTop !== top) scroller.scrollTop = top;
  }
  let packing = 0;
  const repack = () => { cancelAnimationFrame(packing); packing = requestAnimationFrame(pack); };

  window.setupWidgets = function setupWidgets(gridEl, button, userName) {
    grid = gridEl;
    key = `dashboard.layout:${(userName || '').toLowerCase()}`;
    load();
    apply();
    grid.classList.add('packed');
    // Repacked when what's in a panel changes size (not the panel itself,
    // which the packing stretches), and when the window does.
    const watch = new ResizeObserver(repack);
    for (const w of widgets()) for (const child of w.children) watch.observe(child);
    new MutationObserver(repack).observe(grid, { attributes: true, subtree: false, childList: true, attributeFilter: ['class'] });
    for (const w of widgets()) new MutationObserver(repack).observe(w, { attributes: true, attributeFilter: ['class'] });
    window.addEventListener('resize', repack);
    repack();
    button.addEventListener('click', () => {
      const on = !customising();
      grid.classList.toggle('customising', on);
      button.textContent = on ? 'Done' : 'Customise';
      button.classList.toggle('primary', on);
      let reset = document.getElementById('widgets-reset');
      if (on && !reset) {
        reset = document.createElement('button');
        reset.id = 'widgets-reset';
        reset.textContent = 'Reset Layout';
        reset.dataset.noIcon = '';
        reset.addEventListener('click', () => {
          layout = { order: [], hidden: [], span: {} };
          try { localStorage.removeItem(key); } catch (e) { /* ignore */ }
          location.reload();
        });
        button.insertAdjacentElement('afterend', reset);
      } else if (!on && reset) reset.remove();
      refresh();
    });
  };
})();

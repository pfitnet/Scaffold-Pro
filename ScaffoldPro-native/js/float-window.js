'use strict';

// A floating window over every page (the calculator, the time log): moved
// by its top bar (.calc-bar), resized by any edge or corner, and where it
// is, its size and whether it's open kept on this Mac (open: across pages,
// like the Assistant's chat). Styles: css/calculator.css (.calc-float…).
// Dragged past an edge it follows with more and more resistance and springs
// back when let go, as the Assistant's chat does (js/assistant.js).
// Two windows dropped or opened on top of each other: the smaller springs
// to the side of the bigger, the first time. Overlapped again within a
// couple of minutes, they're left as put (window.floatWindow.separate).
//
//   const win = window.floatWindow(panel, { key: 'calc', minW: 272, minH: 380,
//     gripTitle: '…', onOpen: (focus) => {} });
//   win.open(focus = true) · win.close() · win.toggle() · win.isOpen() · win.restore()

(function () {
  if (window.floatWindow) return;
  const EDGE = 8;
  const store = {
    get(k, s) { try { return (s ? sessionStorage : localStorage).getItem(k); } catch (e) { return null; } },
    set(k, v, s) { try { (s ? sessionStorage : localStorage).setItem(k, v); } catch (e) { /* not kept */ } },
    drop(k) { try { localStorage.removeItem(k); } catch (e) { /* fine */ } },
  };
  const read = (k) => { try { return JSON.parse(store.get(k) || 'null'); } catch (e) { return null; } };
  const topEdge = () => (window.__scaffoldProWeb ? EDGE : 44);
  // The Assistant's rubber band (js/assistant.js): past an edge, more and more resistance.
  const rubberband = (over, dim) => (over * dim * 0.55) / (dim + 0.55 * Math.abs(over));
  const soft = (v, lo, hi, dim) => (v < lo ? lo + rubberband(v - lo, dim) : v > hi ? hi + rubberband(v - hi, dim) : v);
  const SPRING = 'left .32s var(--spring), top .32s var(--spring)';

  // ---- Overlapping windows ----
  const PANELS = '.calc-float, .as-float';
  const GAP = 12;
  const QUIET = 2 * 60 * 1000; // overlapped again within this: left as put
  const SEEN = 'float.overlaps';
  const box = (p) => ({ l: p.offsetLeft, t: p.offsetTop, w: p.offsetWidth, h: p.offsetHeight });
  const overlaps = (a, b) => a.l < b.l + b.w && b.l < a.l + a.w && a.t < b.t + b.h && b.t < a.t + a.h;
  // Springs a window to a place, then tells its owner to keep it ('float:placed').
  function springTo(p, spot) {
    p.style.transition = SPRING;
    Object.assign(p.style, { left: `${Math.round(spot.l)}px`, top: `${Math.round(spot.t)}px`, right: 'auto', bottom: 'auto' });
    clearTimeout(p.__springT);
    p.__springT = setTimeout(() => { p.style.transition = ''; p.dispatchEvent(new Event('float:placed')); }, 340);
  }
  // Where the small window `s` goes: beside the big window `b` (or, if
  // that's taken, beside another open window), on whichever side is nearest,
  // fits on screen and is clear of the open windows (`others`, `b` among
  // them); if none is clear, the nearest that fits beside `b`.
  function beside(s, b, others) {
    const vw = window.innerWidth, vh = window.innerHeight;
    const cx = (l) => Math.max(EDGE, Math.min(l, vw - s.w - EDGE));
    const cy = (t) => Math.max(topEdge(), Math.min(t, vh - s.h - EDGE));
    const around = (o) => [
      { l: o.l + o.w + GAP, t: cy(s.t) }, { l: o.l - GAP - s.w, t: cy(s.t) },
      { l: cx(s.l), t: o.t + o.h + GAP }, { l: cx(s.l), t: o.t - GAP - s.h },
    ];
    const onScreen = (c) => c.l >= EDGE && c.l + s.w <= vw - EDGE && c.t >= topEdge() && c.t + s.h <= vh - EDGE;
    const near = (x, y) => Math.hypot(x.l - s.l, x.t - s.t) - Math.hypot(y.l - s.l, y.t - s.t);
    const clear = [b, ...others].flatMap(around).filter(onScreen)
      .filter((c) => !others.some((o) => overlaps({ l: c.l, t: c.t, w: s.w, h: s.h }, o)))
      .sort(near)[0];
    return clear || around(b).filter(onScreen).sort(near)[0] || null;
  }
  // `panel` was just dropped, opened or resized: for each open window it now
  // overlaps, the smaller of the two springs aside — unless that pair was
  // overlapped within QUIET (the person means it). Each overlap restarts it.
  function separate(panel) {
    if (!panel || panel.classList.contains('hidden')) return;
    const open = [...document.querySelectorAll(PANELS)].filter((p) => !p.classList.contains('hidden'));
    // Each window's box, where it's going if it's being moved now.
    const boxes = new Map(open.map((p) => [p, box(p)]));
    const a = boxes.get(panel);
    let seen = {};
    try { seen = JSON.parse(store.get(SEEN, true) || '{}') || {}; } catch (e) { seen = {}; }
    for (const other of open) {
      if (other === panel) continue;
      const b = boxes.get(other);
      if (!overlaps(a, b)) continue;
      const key = [panel.id, other.id].sort().join('|');
      const last = seen[key];
      seen[key] = Date.now();
      if (last && Date.now() - last < QUIET) continue;
      const small = a.w * a.h <= b.w * b.h ? panel : other;
      const s = boxes.get(small), big = small === panel ? b : a;
      const spot = beside(s, big, open.filter((p) => p !== small).map((p) => boxes.get(p)));
      if (!spot) continue;
      springTo(small, spot);
      s.l = spot.l; s.t = spot.t; // (where it's going, for the windows after)
    }
    store.set(SEEN, JSON.stringify(seen), true);
  }

  window.floatWindow = function floatWindow(panel, o) {
    const PLACE = `${o.key}.place`, SIZE = `${o.key}.size`, OPEN = `${o.key}.open`;
    panel.insertAdjacentHTML('beforeend', `${['n', 's', 'e', 'w', 'ne', 'nw', 'sw'].map((d) => `<div class="calc-edge e-${d}" data-dir="${d}" aria-hidden="true"></div>`).join('')}
      <div class="calc-edge calc-grip" data-dir="se" title="${o.gripTitle || 'Drag an edge or corner to resize. Double-click: back to its usual size'}" aria-hidden="true">
        <svg viewBox="0 0 12 12" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M11 5 5 11M11 9 9 11"/></svg></div>`);
    const bar = panel.querySelector('.calc-bar');
    const isOpen = () => !panel.classList.contains('hidden');

    function place(p) {
      const w = panel.offsetWidth, h = panel.offsetHeight;
      const left = Math.max(EDGE, Math.min(p.left, window.innerWidth - w - EDGE));
      const top = Math.max(topEdge(), Math.min(p.top, window.innerHeight - h - EDGE));
      Object.assign(panel.style, { left: `${left}px`, top: `${top}px`, right: 'auto', bottom: 'auto' });
    }
    // Its size: none = its usual one (css).
    function size(sz) {
      panel.classList.toggle('sized', !!sz);
      if (!sz) { panel.style.width = ''; panel.style.height = ''; return; }
      const maxW = window.innerWidth - 2 * EDGE, maxH = window.innerHeight - 2 * EDGE;
      panel.style.width = `${Math.round(Math.max(o.minW, Math.min(sz.w, maxW)))}px`;
      panel.style.height = `${Math.round(Math.max(o.minH, Math.min(sz.h, maxH)))}px`;
    }
    function placeSaved() {
      size(read(SIZE));
      const saved = read(PLACE);
      if (saved) place(saved);
      else { Object.assign(panel.style, { left: '', top: '', right: '', bottom: '' }); place({ left: panel.offsetLeft, top: panel.offsetTop }); }
    }
    function open(focus = true) {
      panel.classList.remove('hidden');
      if (focus) panel.classList.add('popping');
      placeSaved();
      store.set(OPEN, '1', true);
      if (o.onOpen) o.onOpen(focus);
      if (focus) separate(panel);
    }
    function close() {
      panel.classList.add('hidden');
      store.set(OPEN, '', true);
    }
    const toggle = () => (isOpen() ? close() : open());
    const saveAll = () => {
      store.set(PLACE, JSON.stringify({ left: panel.offsetLeft, top: panel.offsetTop }));
      if (panel.classList.contains('sized')) store.set(SIZE, JSON.stringify({ w: panel.offsetWidth, h: panel.offsetHeight }));
    };
    // One drag at a time: moving it, or resizing it; then it's kept, and
    // moved aside of (or moves aside) a window it landed on.
    function drag(e, cls, move, end) {
      e.preventDefault();
      clearTimeout(panel.__springT);
      panel.style.transition = 'none';
      panel.classList.add(cls);
      const up = () => {
        document.removeEventListener('pointermove', move);
        document.removeEventListener('pointerup', up);
        panel.classList.remove(cls);
        if (end) end(); else { panel.style.transition = ''; saveAll(); separate(panel); }
      };
      document.addEventListener('pointermove', move);
      document.addEventListener('pointerup', up);
    }

    bar.addEventListener('pointerdown', (e) => {
      if (e.button !== 0 || e.target.closest('button, input, select')) return;
      const s = { x: e.clientX, y: e.clientY, left: panel.offsetLeft, top: panel.offsetTop, w: panel.offsetWidth, h: panel.offsetHeight };
      // Past an edge: the rubber band; let go: back on screen with a spring.
      drag(e, 'dragging', (ev) => {
        const left = soft(s.left + ev.clientX - s.x, EDGE, window.innerWidth - s.w - EDGE, s.w);
        const top = soft(s.top + ev.clientY - s.y, topEdge(), window.innerHeight - s.h - EDGE, s.h);
        Object.assign(panel.style, { left: `${left}px`, top: `${top}px`, right: 'auto', bottom: 'auto' });
      }, () => {
        const was = box(panel);
        panel.style.transition = SPRING;
        place({ left: was.l, top: was.t });
        // (The target, not offsetLeft: that's still where the spring starts.)
        const moved = Math.round(parseFloat(panel.style.left)) !== Math.round(was.l) || Math.round(parseFloat(panel.style.top)) !== Math.round(was.t);
        panel.__springT = setTimeout(() => { panel.style.transition = ''; saveAll(); separate(panel); }, moved ? 340 : 0);
      });
    });
    panel.addEventListener('pointerdown', (e) => {
      const edge = e.target.closest('.calc-edge');
      if (!edge || e.button !== 0) return;
      const dir = edge.dataset.dir;
      const r = { x: e.clientX, y: e.clientY, l: panel.offsetLeft, t: panel.offsetTop, w: panel.offsetWidth, h: panel.offsetHeight };
      drag(e, 'resizing', (ev) => {
        const maxW = window.innerWidth - 2 * EDGE, maxH = window.innerHeight - 2 * EDGE;
        let w = r.w, h = r.h;
        if (dir.includes('e')) w = r.w + ev.clientX - r.x;
        if (dir.includes('w')) w = r.w - (ev.clientX - r.x);
        if (dir.includes('s')) h = r.h + ev.clientY - r.y;
        if (dir.includes('n')) h = r.h - (ev.clientY - r.y);
        w = Math.max(o.minW, Math.min(w, maxW));
        h = Math.max(o.minH, Math.min(h, maxH));
        size({ w, h });
        place({ left: dir.includes('w') ? r.l + r.w - w : r.l, top: dir.includes('n') ? r.t + r.h - h : r.t });
      });
    });
    // Double-click: the corner back to its usual size, the bar back to its usual place.
    panel.querySelector('.calc-grip').addEventListener('dblclick', () => { store.drop(SIZE); placeSaved(); });
    bar.addEventListener('dblclick', (e) => { if (!e.target.closest('button, input, select')) { store.drop(PLACE); placeSaved(); } });
    panel.addEventListener('animationend', (e) => { if (e.target === panel) panel.classList.remove('popping', 'nudge'); });
    panel.addEventListener('float:placed', saveAll);
    window.addEventListener('resize', () => { if (isOpen()) placeSaved(); });

    return {
      open, close, toggle, isOpen,
      // Open on the page before: open here too (without taking the focus).
      restore: () => { if (store.get(OPEN, true) === '1') open(false); },
    };
  };
  window.floatWindow.separate = separate;
})();

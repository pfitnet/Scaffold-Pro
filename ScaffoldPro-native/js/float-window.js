'use strict';

// A floating window over every page (the calculator, the time log): moved
// by its top bar (.calc-bar), resized by any edge or corner, and where it
// is, its size and whether it's open kept on this Mac (open: across pages,
// like the Assistant's chat). Styles: css/calculator.css (.calc-float…).
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

  window.floatWindow = function floatWindow(panel, o) {
    const PLACE = `${o.key}.place`, SIZE = `${o.key}.size`, OPEN = `${o.key}.open`;
    panel.insertAdjacentHTML('beforeend', `${['n', 's', 'e', 'w', 'ne', 'nw', 'sw'].map((d) => `<div class="calc-edge e-${d}" data-dir="${d}" aria-hidden="true"></div>`).join('')}
      <div class="calc-edge calc-grip" data-dir="se" title="${o.gripTitle || 'Drag an edge or corner to resize. Double-click: back to its usual size'}" aria-hidden="true">
        <svg viewBox="0 0 12 12" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"><path d="M11 5 5 11M11 9 9 11"/></svg></div>`);
    const bar = panel.querySelector('.calc-bar');
    const isOpen = () => !panel.classList.contains('hidden');

    function place(p) {
      const w = panel.offsetWidth, h = panel.offsetHeight;
      const topEdge = window.__scaffoldProWeb ? EDGE : 44;
      const left = Math.max(EDGE, Math.min(p.left, window.innerWidth - w - EDGE));
      const top = Math.max(topEdge, Math.min(p.top, window.innerHeight - h - EDGE));
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
    // One drag at a time: moving it, or resizing it.
    function drag(e, cls, move) {
      e.preventDefault();
      panel.classList.add(cls);
      const up = () => {
        document.removeEventListener('pointermove', move);
        document.removeEventListener('pointerup', up);
        panel.classList.remove(cls);
        saveAll();
      };
      document.addEventListener('pointermove', move);
      document.addEventListener('pointerup', up);
    }

    bar.addEventListener('pointerdown', (e) => {
      if (e.button !== 0 || e.target.closest('button, input, select')) return;
      const s = { x: e.clientX, y: e.clientY, left: panel.offsetLeft, top: panel.offsetTop };
      drag(e, 'dragging', (ev) => place({ left: s.left + ev.clientX - s.x, top: s.top + ev.clientY - s.y }));
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
    window.addEventListener('resize', () => { if (isOpen()) placeSaved(); });

    return {
      open, close, toggle, isOpen,
      // Open on the page before: open here too (without taking the focus).
      restore: () => { if (store.get(OPEN, true) === '1') open(false); },
    };
  };
})();

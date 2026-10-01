'use strict';

// The Dashboard's panels as widgets: "Customise" lets each person drag
// them into their own order, drag a panel's right edge to make it ¼, ½, ¾
// or full width (it snaps to the columns, shown while dragging), and hide
// the ones they don't want (and show them again). Remembered for the
// person on this Mac.
//
//   window.setupWidgets(grid, button, userName);
//
// A panel's starting width is its data-span (1–4 quarters; 2 if not given).

(function () {
  const GRIP = '<svg viewBox="0 0 10 16" width="10" height="16" aria-hidden="true" fill="currentColor"><circle cx="3" cy="3" r="1.3"/><circle cx="7" cy="3" r="1.3"/><circle cx="3" cy="8" r="1.3"/><circle cx="7" cy="8" r="1.3"/><circle cx="3" cy="13" r="1.3"/><circle cx="7" cy="13" r="1.3"/></svg>';
  const COLS = 4;
  const SIZE_NAME = { 1: '¼ width', 2: '½ width', 3: '¾ width', 4: 'Full width' };
  let grid = null;
  let key = 'dashboard.layout';
  let layout = { order: [], hidden: [], span: {} };

  const widgets = () => [...grid.querySelectorAll(':scope > [data-widget]')];
  const defaultSpan = (w) => Number(w.dataset.defaultSpan || w.dataset.span) || 2;
  const spanOf = (w) => layout.span[w.dataset.widget] || defaultSpan(w);

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

  function setSpan(w, n) {
    n = Math.max(1, Math.min(COLS, n));
    if (n === defaultSpan(w)) delete layout.span[w.dataset.widget];
    else layout.span[w.dataset.widget] = n;
    w.dataset.span = String(n);
    const label = w.querySelector('.widget-size-label');
    if (label) label.textContent = SIZE_NAME[n];
  }

  function bar(w) {
    const id = w.dataset.widget;
    const off = layout.hidden.includes(id);
    const el = document.createElement('div');
    el.className = 'widget-bar';
    el.innerHTML = `<span class="widget-grip" title="Drag to move">${GRIP}</span>
      <span class="widget-name">${w.dataset.title || id}</span>
      <span class="widget-size-label" title="Drag the right edge to change the width">${SIZE_NAME[spanOf(w)]}</span>
      <button class="widget-toggle" data-no-icon>${off ? 'Show' : 'Hide'}</button>`;
    el.querySelector('.widget-toggle').addEventListener('click', () => {
      layout.hidden = off ? layout.hidden.filter((x) => x !== id) : layout.hidden.concat(id);
      save(); refresh();
    });
    el.querySelector('.widget-grip').addEventListener('pointerdown', (e) => startDrag(e, w));
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

  function refresh() {
    apply();
    for (const old of grid.querySelectorAll('.widget-bar, .widget-resize, .widget-guides')) old.remove();
    if (!grid.classList.contains('customising')) return;
    guides();
    for (const w of widgets()) { w.prepend(bar(w)); w.appendChild(handle(w)); }
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

  // Drag a widget by its grip: it goes before (or after) the one under the pointer.
  function startDrag(e, w) {
    e.preventDefault();
    w.classList.add('widget-dragging');
    const move = (ev) => {
      const over = document.elementFromPoint(ev.clientX, ev.clientY);
      const target = over && over.closest('[data-widget]');
      if (!target || target === w || target.parentElement !== grid) return;
      const r = target.getBoundingClientRect();
      const after = ev.clientY > r.top + r.height / 2 || (Math.abs(ev.clientY - (r.top + r.height / 2)) < r.height / 4 && ev.clientX > r.left + r.width / 2);
      grid.insertBefore(w, after ? target.nextSibling : target);
    };
    const up = () => {
      document.removeEventListener('pointermove', move);
      document.removeEventListener('pointerup', up);
      w.classList.remove('widget-dragging');
      save();
    };
    document.addEventListener('pointermove', move);
    document.addEventListener('pointerup', up);
  }

  // Panels are packed like tiles: each takes as many thin grid rows as
  // it's tall, so a short panel doesn't leave a gap under it beside a tall
  // one — the next panel moves up into the space.
  const ROW = 2;
  function pack() {
    const gap = parseFloat(getComputedStyle(grid).getPropertyValue('--widget-gap')) || 14;
    for (const w of widgets()) {
      const h = w.getBoundingClientRect().height;
      w.style.gridRowEnd = `span ${Math.max(1, Math.ceil((h + gap) / ROW))}`;
    }
  }
  let packing = 0;
  const repack = () => { cancelAnimationFrame(packing); packing = requestAnimationFrame(pack); };

  window.setupWidgets = function setupWidgets(gridEl, button, userName) {
    grid = gridEl;
    key = `dashboard.layout:${(userName || '').toLowerCase()}`;
    load();
    apply();
    grid.classList.add('packed');
    const watch = new ResizeObserver(repack);
    for (const w of widgets()) watch.observe(w);
    repack();
    button.addEventListener('click', () => {
      const on = !grid.classList.contains('customising');
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

'use strict';

// The Dashboard's panels as widgets: "Customise" lets each person drag
// them into their own order, make one full width or half, and hide the
// ones they don't want (and show them again). Remembered for the person
// on this Mac.
//
//   window.setupWidgets(grid, button, userName);

(function () {
  const GRIP = '<svg viewBox="0 0 10 16" width="10" height="16" aria-hidden="true" fill="currentColor"><circle cx="3" cy="3" r="1.3"/><circle cx="7" cy="3" r="1.3"/><circle cx="3" cy="8" r="1.3"/><circle cx="7" cy="8" r="1.3"/><circle cx="3" cy="13" r="1.3"/><circle cx="7" cy="13" r="1.3"/></svg>';
  let grid = null;
  let key = 'dashboard.layout';
  let layout = { order: [], hidden: [], wide: [] };

  const widgets = () => [...grid.querySelectorAll(':scope > [data-widget]')];

  function load() {
    try { layout = Object.assign({ order: [], hidden: [], wide: [] }, JSON.parse(localStorage.getItem(key) || '{}')); } catch (e) { /* default */ }
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
      w.classList.toggle('widget-off', layout.hidden.includes(w.dataset.widget));
      w.classList.toggle('widget-wide', layout.wide.includes(w.dataset.widget));
    }
  }

  function bar(w) {
    const id = w.dataset.widget;
    const off = layout.hidden.includes(id);
    const wide = layout.wide.includes(id);
    const el = document.createElement('div');
    el.className = 'widget-bar';
    el.innerHTML = `<span class="widget-grip" title="Drag to move">${GRIP}</span>
      <span class="widget-name">${w.dataset.title || id}</span>
      <button class="widget-size" data-no-icon title="${wide ? 'Make it half width' : 'Make it full width'}">${wide ? 'Half width' : 'Full width'}</button>
      <button class="widget-toggle" data-no-icon>${off ? 'Show' : 'Hide'}</button>`;
    el.querySelector('.widget-size').addEventListener('click', () => {
      layout.wide = wide ? layout.wide.filter((x) => x !== id) : layout.wide.concat(id);
      save(); refresh();
    });
    el.querySelector('.widget-toggle').addEventListener('click', () => {
      layout.hidden = off ? layout.hidden.filter((x) => x !== id) : layout.hidden.concat(id);
      save(); refresh();
    });
    el.querySelector('.widget-grip').addEventListener('pointerdown', (e) => startDrag(e, w));
    return el;
  }

  function refresh() {
    apply();
    for (const old of grid.querySelectorAll('.widget-bar')) old.remove();
    if (grid.classList.contains('customising')) for (const w of widgets()) w.prepend(bar(w));
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

  window.setupWidgets = function setupWidgets(gridEl, button, userName) {
    grid = gridEl;
    key = `dashboard.layout:${(userName || '').toLowerCase()}`;
    load();
    apply();
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
          layout = { order: [], hidden: [], wide: [] };
          try { localStorage.removeItem(key); } catch (e) { /* ignore */ }
          location.reload();
        });
        button.insertAdjacentElement('afterend', reset);
      } else if (!on && reset) reset.remove();
      refresh();
    });
  };
})();

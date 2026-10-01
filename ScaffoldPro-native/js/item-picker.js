'use strict';

// The "Add Materials" list in the BOQ, quotation, invoice and delivery
// note editors: items in a box per category (Base Items, Standards (with
// Spigots), Ledgers…), in the Material List's order, with the pinned ones
// in a "Pinned" box first. Each row has a pin to pin / unpin it (kept with
// the material list, so it's the same on every Mac).
//
//   const items = await window.pickerSearch(params);   // null: a newer search has started
//   window.renderPickerGroups(container, items, headHTML, makeRow)
//
// headHTML is the column-heading row's cells; makeRow(item) returns the
// item's <tr> (its first cell gets the pin).
//
// Clicking "+ Add" always works: the list isn't redrawn while the mouse
// button is down in it (a search answer arriving mid-click used to replace
// the button being clicked), and answers to older searches are dropped.

(function () {
  function esc(value) {
    return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  const byCode = (a, b) => String(a).localeCompare(String(b), undefined, { numeric: true });

  const PIN = '<svg viewBox="0 0 20 20" width="14" height="14" aria-hidden="true"><path d="M10 2.6l2.2 4.6 5 .7-3.6 3.5.9 5-4.5-2.4-4.5 2.4.9-5L2.8 7.9l5-.7z" fill="currentColor"/></svg>';

  // Searches in order: an answer to an older search (typing on) is dropped.
  let searchSeq = 0;
  window.pickerSearch = async function pickerSearch(params) {
    const mine = ++searchSeq;
    const items = await window.api.priceLists.searchItems(params);
    return mine === searchSeq ? items : null;
  };

  // A redraw asked for while the mouse is down in the list waits until it's up.
  const pressed = new WeakSet();
  const waiting = new Map();
  document.addEventListener('pointerdown', (e) => {
    const list = e.target instanceof Element && e.target.closest('.picker-results');
    if (list) pressed.add(list);
  }, true);
  document.addEventListener('pointerup', () => {
    // After the click has been handled.
    setTimeout(() => {
      for (const [container, args] of waiting) {
        pressed.delete(container);
        waiting.delete(container);
        render(...args);
      }
      for (const c of document.querySelectorAll('.picker-results')) pressed.delete(c);
    }, 0);
  }, true);

  function groupBox(title, list, headHTML, makeRow, extraClass, container, args) {
    const box = document.createElement('section');
    box.className = `picker-group${extraClass ? ` ${extraClass}` : ''}`;
    box.innerHTML = `
      <div class="picker-group-head"><span>${title}</span><span class="picker-group-count">${list.length} item${list.length === 1 ? '' : 's'}</span></div>
      <div class="picker-group-scroll"><table class="picker-group-table"><thead><tr>${headHTML}</tr></thead><tbody></tbody></table></div>`;
    box.dataset.key = title;
    const tbody = box.querySelector('tbody');
    for (const item of list) {
      const tr = makeRow(item);
      const first = tr.cells[0];
      if (first && item.id) {
        const pin = document.createElement('button');
        pin.type = 'button';
        pin.className = `pin-btn${item.isPinned ? ' pinned' : ''}`;
        pin.dataset.noIcon = '';
        pin.title = item.isPinned ? 'Unpin' : 'Pin to the top (for items you use often)';
        pin.setAttribute('aria-label', pin.title);
        pin.innerHTML = PIN;
        pin.addEventListener('click', async (e) => {
          e.stopPropagation();
          const now = !item.isPinned;
          const r = await window.api.priceLists.setPinned(item.id, now);
          if (r && r.ok === false) { alert(r.error); return; }
          for (const i of args[1]) if (i.id === item.id) i.isPinned = now;
          render(...args);
        });
        first.classList.add('picker-name-cell');
        first.prepend(pin);
      }
      // The Chinese name, for workers who read Chinese.
      if (first && item.chineseName && !first.querySelector('.zh-name')) {
        first.insertAdjacentHTML('beforeend', ` <span class="zh-name">${esc(item.chineseName)}</span>`);
      }
      tbody.appendChild(tr);
    }
    return box;
  }

  function render(container, items, headHTML, makeRow) {
    const args = [container, items, headHTML, makeRow];
    if (pressed.has(container)) { waiting.set(container, args); return; }
    const fragment = document.createDocumentFragment();
    const pinned = items.filter((i) => i.isPinned).sort((a, b) => byCode(a.itemCode || '', b.itemCode || ''));
    if (pinned.length) fragment.appendChild(groupBox('★ Pinned', pinned, headHTML, makeRow, 'picker-pinned', container, args));
    const groups = new Map();
    for (const item of items) {
      const name = item.category || 'Other Items';
      if (!groups.has(name)) groups.set(name, []);
      groups.get(name).push(item);
    }
    // Categories in item-code order (1.x Base Items, 2.x Standards…): the
    // list itself comes in dragged order, which is kept inside each box.
    const firstCode = (list) => list.map((i) => String(i.itemCode || '')).sort(byCode)[0] || '';
    const ordered = [...groups].sort((a, b) => byCode(firstCode(a[1]), firstCode(b[1])));
    for (const [name, list] of ordered) fragment.appendChild(groupBox(esc(name), list, headHTML, makeRow, '', container, args));
    // Keep the place: the bracket shown, and how far down its list.
    const scroll = container.scrollTop;
    const inner = new Map([...container.querySelectorAll('.picker-group')].map((g) => [g.dataset.key, g.querySelector('.picker-group-scroll').scrollTop]));
    container.innerHTML = '';
    container.appendChild(fragment);
    const boxes = [...container.querySelectorAll('.picker-group')];
    boxes.forEach((g, i) => {
      g.querySelector('.picker-group-count').insertAdjacentHTML('beforeend', boxes.length > 1 ? ` · ${i + 1} of ${boxes.length}` : '');
      if (inner.has(g.dataset.key)) g.querySelector('.picker-group-scroll').scrollTop = inner.get(g.dataset.key);
    });
    container.scrollTop = scroll;
    pageByBracket(container);
  }

  // Each bracket fills the box (so none is shown cut in half), and each
  // scroll moves to the next (or previous) whole bracket. Inside a long
  // bracket the list scrolls first; once it's at its end, the next scroll
  // turns the page. A flick's after-scroll doesn't turn more than one.
  const paged = new WeakSet();
  function pageByBracket(container) {
    if (paged.has(container)) return;
    paged.add(container);
    let last = 0;
    container.addEventListener('wheel', (e) => {
      if (Math.abs(e.deltaY) <= Math.abs(e.deltaX) || e.ctrlKey) return;
      const now = performance.now();
      const fresh = now - last > 180;
      last = now;
      const dir = Math.sign(e.deltaY);
      const list = e.target instanceof Element && e.target.closest('.picker-group-scroll');
      if (list && (dir > 0 ? list.scrollTop + list.clientHeight < list.scrollHeight - 1 : list.scrollTop > 0)) return;
      const groups = [...container.querySelectorAll(':scope > .picker-group')];
      if (!groups.length) return;
      let at = 0;
      for (let i = 0; i < groups.length; i++) {
        if (Math.abs(groups[i].offsetTop - container.scrollTop) < Math.abs(groups[at].offsetTop - container.scrollTop)) at = i;
      }
      const to = at + dir;
      // Past the first or last bracket: the page itself scrolls.
      if (to < 0 || to >= groups.length) return;
      e.preventDefault();
      if (!fresh) return;
      container.scrollTo({ top: groups[to].offsetTop, behavior: 'smooth' });
    }, { passive: false });
  }

  window.renderPickerGroups = function renderPickerGroups(container, items, headHTML, makeRow) {
    render(container, items, headHTML, makeRow);
  };
})();

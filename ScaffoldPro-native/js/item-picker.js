'use strict';

// The "Add Materials" list in the BOQ, quotation, invoice and delivery
// note editors: items in a box per category (Base Items, Standards (with
// Spigots), Ledgers…), in the Material List's order.
//
//   window.renderPickerGroups(container, items, headHTML, makeRow)
//
// headHTML is the column-heading row's cells; makeRow(item) returns the
// item's <tr>.

(function () {
  function esc(value) {
    return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  const byCode = (a, b) => a.localeCompare(b, undefined, { numeric: true });

  window.renderPickerGroups = function renderPickerGroups(container, items, headHTML, makeRow) {
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
    const scroll = container.scrollTop;
    container.innerHTML = '';
    for (const [name, list] of ordered) {
      const box = document.createElement('section');
      box.className = 'picker-group';
      box.innerHTML = `
        <div class="picker-group-head"><span>${esc(name)}</span><span class="picker-group-count">${list.length}</span></div>
        <table class="picker-group-table"><thead><tr>${headHTML}</tr></thead><tbody></tbody></table>`;
      const tbody = box.querySelector('tbody');
      for (const item of list) tbody.appendChild(makeRow(item));
      container.appendChild(box);
    }
    container.scrollTop = scroll;
  };
})();

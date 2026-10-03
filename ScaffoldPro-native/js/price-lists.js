'use strict';

let currentSourceKey = null;
let currentCurrency = 'HKD';
let priceListsMeta = [];
let allItemsForCurrentList = [];

function esc(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function money(value) {
  return value === null || value === undefined ? '—'
    : Number(value).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function groupByCategory(items) {
  const groups = new Map();
  for (const item of items) {
    const key = item.category || 'Uncategorized';
    if (!groups.has(key)) groups.set(key, []);
    groups.get(key).push(item);
  }
  return [...groups.entries()].sort((a, b) => a[0].localeCompare(b[0]));
}

function weightText(value) {
  return value === null || value === undefined ? '—'
    : `${Number(value).toLocaleString('en-US', { minimumFractionDigits: 1, maximumFractionDigits: 2 })} kg`;
}

// Rows can be dragged into order within their category — except while a
// search is typed in (only some of the items are showing then).
let canReorder = true;

function handleCell(item) {
  if (ratesSelecting && item) {
    return `<td class="drag-col"><input type="checkbox" class="rate-pick" ${ratesPicked.has(item.id) ? 'checked' : ''} tabindex="-1" /></td>`;
  }
  return `<td class="drag-col">${canReorder ? window.dragHandleHTML('Drag to move this item (or focus and press ↑ / ↓)') : ''}</td>`;
}

// ---------- The ☰ list: category, Import rates, Export rates ----------
// Resting on ☰ lists Import rates, Export rates (resting on it opens PDF —
// the Unit Rates sheet on the letterhead — and Excel, to its left) and the
// categories to show. They press the page's own (hidden) controls. A dot on
// ☰ shows a category is chosen.

function setupListMenu() {
  const button = document.getElementById('ml-menu-btn');
  const category = document.getElementById('category-select');
  const refresh = () => {
    button.classList.toggle('filtered', !!category.value);
    button.title = `Import or export rates\nCategory: ${category.selectedOptions[0] ? category.selectedOptions[0].textContent : 'All Categories'}`;
  };
  category.addEventListener('change', refresh);
  new MutationObserver(refresh).observe(category, { childList: true });
  refresh();
  window.hoverMenu.attach(button, {
    minWidth: 240,
    align: 'right',
    items: () => [
      { group: 'Rates' },
      { label: 'Import rates…', sub: 'Update prices from an Excel workbook (.xlsx)', value: 'import' },
      { label: 'Export rates', sub: 'As a PDF or an Excel workbook', value: 'export', items: [
        { label: 'PDF', sub: 'Unit Rates on the letterhead — tick the items, from either list', value: 'pdf' },
        { label: 'Excel', sub: 'This material list (.xlsx) — edit it and import it back', value: 'excel' },
      ] },
      { group: 'Category' },
      ...window.hoverMenu.selectItems(category).filter((it) => it.group == null).map((it) => ({ ...it, value: `cat:${it.value}` })),
    ],
    onPick: (v) => {
      if (v === 'import') document.getElementById('import-btn').click();
      else if (v === 'pdf') document.getElementById('rates-select-btn').click();
      else if (v === 'excel') document.getElementById('export-btn').click();
      else if (v.startsWith('cat:')) { window.hoverMenu.pickInSelect(category, v.slice(4)); refresh(); }
    },
  });
}

// ---------- Unit Rates: items picked from either list, for a client ----------

let ratesSelecting = false;
const ratesPicked = new Map(); // id → { sourceKey, itemCode, itemName }

function updateRatesBar() {
  document.getElementById('rates-bar').classList.toggle('hidden', !ratesSelecting);
  document.getElementById('rates-select-btn').classList.toggle('hidden', ratesSelecting);
  document.getElementById('table-container').classList.toggle('selecting', ratesSelecting);
  const n = ratesPicked.size;
  const lists = new Set([...ratesPicked.values()].map((i) => i.sourceKey));
  document.getElementById('rates-count').textContent = n === 0
    ? 'Tick the items for the Unit Rates sheet — from either list (switch lists above; ticks are kept).'
    : `${n} item${n === 1 ? '' : 's'} chosen${lists.size > 1 ? ` (from ${[...lists].join(' and ')})` : ''}`;
  document.getElementById('rates-make-btn').disabled = n === 0;
  for (const tr of document.querySelectorAll('#table-container tr[data-id]')) {
    const box = tr.querySelector('input.rate-pick');
    if (box) box.checked = ratesPicked.has(tr.dataset.id);
    tr.classList.toggle('row-selected', ratesPicked.has(tr.dataset.id));
  }
}

function toggleRatePick(item) {
  if (ratesPicked.has(item.id)) ratesPicked.delete(item.id);
  else ratesPicked.set(item.id, { sourceKey: item.sourceKey, itemCode: item.itemCode, itemName: item.itemName });
  updateRatesBar();
}

let ratesClients = [];

async function openRatesModal() {
  ratesClients = (await window.api.clients.list(false)).slice().sort((a, b) => a.companyName.localeCompare(b.companyName));
  const select = document.getElementById('rates-client');
  select.innerHTML = '<option value="">— No particular client —</option>' +
    ratesClients.map((c) => `<option value="${c.id}">${c.companyName.replace(/</g, '&lt;')}</option>`).join('');
  const lists = new Set([...ratesPicked.values()].map((i) => i.sourceKey));
  document.getElementById('rates-summary').textContent = `${ratesPicked.size} item${ratesPicked.size === 1 ? '' : 's'}${lists.size > 1 ? `, from ${[...lists].join(' and ')}` : ''}.`;
  document.getElementById('rates-markup').value = 0;
  updateRatesMarkupNote();
  document.getElementById('rates-modal').classList.remove('hidden');
  select.focus();
}

// Choosing a client fills in their default markup.
function updateRatesMarkupNote() {
  const client = ratesClients.find((c) => c.id === document.getElementById('rates-client').value);
  const m = client && Number(client.defaultMarkupPercent);
  document.getElementById('rates-markup-note').textContent = m ? `${client.companyName}’s default markup is ${m}%.` : 'Unit rates are rounded to 0.1 as set in Settings.';
}

async function makeUnitRates() {
  // The lists in their usual order (SP, then SCAFOM); by item code within each.
  const listIndex = (key) => { const i = priceListsMeta.findIndex((pl) => pl.sourceKey === key); return i < 0 ? 99 : i; };
  const order = [...ratesPicked.entries()].sort((a, b) =>
    listIndex(a[1].sourceKey) - listIndex(b[1].sourceKey) || String(a[1].itemCode).localeCompare(String(b[1].itemCode), undefined, { numeric: true }));
  const go = document.getElementById('rates-go-btn');
  go.disabled = true;
  go.textContent = 'Making PDF…';
  const clientId = document.getElementById('rates-client').value || null;
  const r = await window.api.priceLists.unitRatesPDF({
    itemIds: order.map(([id]) => id), clientId: clientId,
    markupPercent: Number(document.getElementById('rates-markup').value) || 0,
    subject: document.getElementById('rates-subject').value.trim() || null,
    notes: document.getElementById('rates-notes').value.trim() || null,
  });
  go.disabled = false;
  go.textContent = 'Make PDF';
  if (!r || !r.ok) { alert((r && r.error) || 'The PDF couldn’t be made.'); return; }
  document.getElementById('rates-modal').classList.add('hidden');
}

function setupUnitRates() {
  document.getElementById('rates-select-btn').addEventListener('click', () => { ratesSelecting = true; applyFilters().then(updateRatesBar); });
  document.getElementById('rates-done-btn').addEventListener('click', () => { ratesSelecting = false; ratesPicked.clear(); applyFilters().then(updateRatesBar); });
  document.getElementById('rates-clear-btn').addEventListener('click', () => { ratesPicked.clear(); updateRatesBar(); });
  document.getElementById('rates-all-btn').addEventListener('click', () => {
    for (const item of lastShownItems) ratesPicked.set(item.id, { sourceKey: item.sourceKey, itemCode: item.itemCode, itemName: item.itemName });
    updateRatesBar();
  });
  document.getElementById('rates-make-btn').addEventListener('click', openRatesModal);
  document.getElementById('rates-cancel-btn').addEventListener('click', () => document.getElementById('rates-modal').classList.add('hidden'));
  document.getElementById('rates-go-btn').addEventListener('click', makeUnitRates);
  document.getElementById('rates-client').addEventListener('change', () => {
    const client = ratesClients.find((c) => c.id === document.getElementById('rates-client').value);
    if (client && Number(client.defaultMarkupPercent)) document.getElementById('rates-markup').value = Number(client.defaultMarkupPercent);
    updateRatesMarkupNote();
  });
}

let lastShownItems = [];

function renderDisplayRow(tr, item) {
  tr.dataset.id = item.id;
  tr.innerHTML = `${handleCell(item)}
    <td>${item.itemName}${item.chineseName ? ` <span class="zh-name">${esc(item.chineseName)}</span>` : ''}</td>
    <td class="num">${weightText(item.weightKg)}</td>
    <td class="num">${money(item.unitRentalPrice)}</td>
    <td class="num">${money(item.unitSalePrice)}</td>
    <td class="row-actions"><button class="edit-btn">Edit</button> <button class="dup-btn" title="Duplicate">Duplicate</button> <button class="del-btn" title="Delete">Delete</button></td>`;
  tr.querySelector('.edit-btn').addEventListener('click', () => renderEditRow(tr, item));
  // Picking items for Unit Rates: clicking the row ticks it.
  tr.addEventListener('click', (e) => {
    if (!ratesSelecting || e.target.closest('button, a, input:not(.rate-pick), select')) return;
    toggleRatePick(item);
  });
  tr.querySelector('.dup-btn').addEventListener('click', async () => {
    const r = await window.api.priceLists.duplicateItem(item.id);
    if (!r.ok) { alert(r.error); return; }
    await applyFilters();
  });
  tr.querySelector('.del-btn').addEventListener('click', async () => {
    if (!await appConfirm(`Delete "${item.itemName}" from the material list?\n\nExisting BOQs, quotations and invoices keep their copy of it.`)) return;
    const r = await window.api.priceLists.archiveItem(item.id);
    if (!r.ok) { alert(r.error); return; }
    await applyFilters();
  });
}

function renderEditRow(tr, item) {
  tr.innerHTML = `<td class="drag-col"></td>
    <td>
      <input type="text" class="edit-field edit-name" value="${(item.itemName || '').replace(/"/g, '&quot;')}" placeholder="Item name" />
      <input type="text" class="edit-field edit-chinese" value="${esc(item.chineseName || '')}" placeholder="Chinese name 中文名稱" />
      <input type="text" class="edit-field edit-category" value="${(item.category || '').replace(/"/g, '&quot;')}" placeholder="Category" />
      <input type="text" class="edit-field edit-unit" value="${(item.unit || '').replace(/"/g, '&quot;')}" placeholder="Unit" />
    </td>
    <td class="num"><input type="number" class="edit-field edit-weight" min="0" step="0.01" value="${item.weightKg ?? ''}" placeholder="kg" /></td>
    <td class="num"><input type="number" class="edit-field edit-rental" min="0" step="0.01" value="${item.unitRentalPrice ?? ''}" placeholder="Rental" /></td>
    <td class="num"><input type="number" class="edit-field edit-sale" min="0" step="0.01" value="${item.unitSalePrice ?? ''}" placeholder="Sale" /></td>
    <td>
      <button class="save-btn">Save</button>
      <button class="cancel-btn">Cancel</button>
    </td>`;

  tr.querySelector('.cancel-btn').addEventListener('click', () => renderDisplayRow(tr, item));
  tr.querySelector('.save-btn').addEventListener('click', async () => {
    const saleValue = tr.querySelector('.edit-sale').value;
    const rentalValue = tr.querySelector('.edit-rental').value;
    const weightValue = tr.querySelector('.edit-weight').value;
    const changes = {
      itemName: tr.querySelector('.edit-name').value,
      chineseName: tr.querySelector('.edit-chinese').value,
      category: tr.querySelector('.edit-category').value || null,
      unit: tr.querySelector('.edit-unit').value,
      unitSalePrice: saleValue === '' ? null : parseFloat(saleValue),
      unitRentalPrice: rentalValue === '' ? null : parseFloat(rentalValue),
      weightKg: weightValue === '' ? null : parseFloat(weightValue),
    };
    const result = await window.api.priceLists.updateItem(item.id, changes);
    if (!result.ok) { alert(result.error); return; }
    await applyFilters();
  });
}

function renderTable(items) {
  const container = document.getElementById('table-container');
  if (items.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>No items match</h2><p>Try a different search or category.</p></div>`;
    return;
  }

  const groups = groupByCategory(items);
  container.innerHTML = '';

  for (const [category, groupItems] of groups) {
    const section = document.createElement('div');
    section.className = 'price-list-bracket';

    const title = document.createElement('h3');
    title.className = 'bracket-title';
    title.textContent = category;
    section.appendChild(title);

    // The same column widths in every category's table, so they line up.
    const table = document.createElement('table');
    table.className = 'price-table';
    table.innerHTML = `
      <colgroup><col class="c-drag" /><col class="c-item" /><col class="c-weight" /><col class="c-rental" /><col class="c-sale" /><col class="c-actions" /></colgroup>
      <thead><tr><th></th><th>Item</th><th class="num">Weight</th><th class="num">Rental / Month (${currentCurrency})</th><th class="num">Sale (${currentCurrency})</th><th></th></tr></thead>
      <tbody></tbody>`;
    const tbody = table.querySelector('tbody');

    for (const item of groupItems) {
      const tr = document.createElement('tr');
      renderDisplayRow(tr, item);
      tbody.appendChild(tr);
    }

    section.appendChild(table);
    container.appendChild(section);
    if (canReorder && groupItems.length > 1) {
      window.makeReorderable(tbody, {
        item: 'tr',
        onReorder: async (ids) => {
          const r = await window.api.priceLists.reorderItems(ids);
          if (r && !r.ok) alert(r.error);
          await applyFilters();
        },
      });
    }
  }
}

async function applyFilters() {
  const query = document.getElementById('search-box').value;
  const category = document.getElementById('category-select').value;
  const items = await window.api.priceLists.searchItems({ sourceKey: currentSourceKey, query, category: category || null });
  canReorder = !query.trim() && !ratesSelecting;
  lastShownItems = items;
  renderTable(items);
  if (ratesSelecting) updateRatesBar();
}

async function selectList(sourceKey) {
  currentSourceKey = sourceKey;
  const meta = priceListsMeta.find((pl) => pl.sourceKey === sourceKey);
  currentCurrency = meta ? meta.currency : 'HKD';
  const note = document.getElementById('currency-note');
  if (note) {
    note.textContent = currentCurrency === 'HKD' ? ''
      : `Prices in this list are in ${currentCurrency}. They're converted to HKD automatically on BOQs, quotations and invoices (rate set in Settings).`;
  }
  allItemsForCurrentList = await window.api.priceLists.searchItems({ sourceKey });

  const categories = [...new Set(allItemsForCurrentList.map((i) => i.category).filter(Boolean))].sort();
  const categorySelect = document.getElementById('category-select');
  categorySelect.innerHTML = '<option value="">All Categories</option>' +
    categories.map((c) => `<option value="${c}">${c}</option>`).join('');

  // Switching lists keeps any items ticked for Unit Rates.
  lastShownItems = allItemsForCurrentList;
  canReorder = !ratesSelecting;
  renderTable(allItemsForCurrentList);
  if (ratesSelecting) updateRatesBar();
}

// ---------- Add item (section 8) ----------

function openAddItem() {
  for (const f of ['itemName', 'chineseName', 'category', 'unit', 'weightKg', 'unitSalePrice', 'unitRentalPrice']) {
    document.getElementById(`n-${f}`).value = '';
  }
  document.getElementById('n-category').value = document.getElementById('category-select').value || '';
  const cats = [...new Set(allItemsForCurrentList.map((i) => i.category).filter(Boolean))].sort();
  document.getElementById('category-options').innerHTML = cats.map((c) => `<option value="${c}"></option>`).join('');
  document.getElementById('n-error').classList.add('hidden');
  document.getElementById('item-modal').classList.remove('hidden');
  document.getElementById('n-itemName').focus();
}

async function saveNewItem() {
  const numberOrNull = (id) => {
    const v = document.getElementById(id).value;
    return v === '' ? null : Number(v);
  };
  const result = await window.api.priceLists.createItem(currentSourceKey, {
    itemName: document.getElementById('n-itemName').value,
    chineseName: document.getElementById('n-chineseName').value,
    category: document.getElementById('n-category').value,
    unit: document.getElementById('n-unit').value || 'pc',
    weightKg: numberOrNull('n-weightKg'),
    unitSalePrice: numberOrNull('n-unitSalePrice'),
    unitRentalPrice: numberOrNull('n-unitRentalPrice'),
  });
  if (!result.ok) {
    const e = document.getElementById('n-error');
    e.textContent = result.error;
    e.classList.remove('hidden');
    return;
  }
  document.getElementById('item-modal').classList.add('hidden');
  await selectList(currentSourceKey);
}

// ---------- Import / export (sections 8, 49) ----------

let pendingImportToken = null;

async function startImport() {
  const preview = await window.api.priceLists.importPreview(currentSourceKey);
  if (!preview) return; // picker cancelled
  if (!preview.ok) { alert(preview.error); return; }
  pendingImportToken = preview.token;
  const listName = document.getElementById('list-select').selectedOptions[0].textContent;
  document.getElementById('import-summary').innerHTML = `
    <p><strong>${preview.fileName}</strong>${preview.sheetName ? ` — sheet “${preview.sheetName}”` : ''}</p>
    <p>${preview.rowsFound.toLocaleString('en-US')} items found. Importing into <strong>${listName}</strong> will
       <strong>update ${preview.toUpdate.toLocaleString('en-US')}</strong> existing items and
       <strong>add ${preview.toAdd.toLocaleString('en-US')}</strong> new ones. Nothing is deleted.</p>
    <h3 class="related-title">How the columns were read</h3>
    <ul class="plain-list">${preview.mapping.map((m) => `<li>${m}</li>`).join('')}</ul>
    <h3 class="related-title">First few items</h3>
    <ul class="plain-list">${preview.samples.map((m) => `<li>${m}</li>`).join('')}</ul>
    <p class="small-note">Tip: make a backup in Settings first if you'd like to be able to undo this.</p>`;
  document.getElementById('import-modal').classList.remove('hidden');
}

async function applyImport() {
  const result = await window.api.priceLists.importApply(pendingImportToken);
  document.getElementById('import-modal').classList.add('hidden');
  pendingImportToken = null;
  if (!result.ok) { alert(result.error); return; }
  alert(`Import complete: ${result.updated.toLocaleString('en-US')} items updated, ${result.added.toLocaleString('en-US')} added.`);
  await selectList(currentSourceKey);
}

// Where the list is kept the same on every Mac.
async function showSyncStatus() {
  const note = document.getElementById('material-sync-note');
  let st = null;
  try { st = await window.api.priceLists.syncStatus(); } catch (e) { st = null; }
  if (!st || !note) return;
  const others = st.otherMacs ? ` with ${st.otherMacs} other Mac${st.otherMacs === 1 ? '' : 's'}` : '';
  if (st.mode === 'team') note.innerHTML = `<span class="sync-dot"></span>Kept the same on every Mac${others}, through the shared folder “${esc(st.folder)}”.`;
  else if (st.mode === 'icloud') note.innerHTML = `<span class="sync-dot"></span>Kept the same on every Mac${others}, through iCloud Drive (“${esc(st.folder)}”).`;
  else note.innerHTML = '<span class="sync-dot off"></span>Only on this Mac: turn on iCloud Drive to keep the material list the same on every Mac.';
  note.classList.remove('hidden');
}

async function init() {
  const priceLists = await window.api.priceLists.list();
  priceListsMeta = priceLists;
  const select = document.getElementById('list-select');
  select.innerHTML = priceLists.map((pl) => `<option value="${pl.sourceKey}">${pl.displayName}</option>`).join('');

  select.addEventListener('change', () => selectList(select.value));
  document.getElementById('search-box').addEventListener('input', applyFilters);
  document.getElementById('category-select').addEventListener('change', applyFilters);
  document.getElementById('add-item-btn').addEventListener('click', openAddItem);
  document.getElementById('n-cancel-btn').addEventListener('click', () => document.getElementById('item-modal').classList.add('hidden'));
  document.getElementById('n-save-btn').addEventListener('click', saveNewItem);
  document.getElementById('import-btn').addEventListener('click', startImport);
  document.getElementById('import-apply-btn').addEventListener('click', applyImport);
  document.getElementById('import-cancel-btn').addEventListener('click', () => {
    pendingImportToken = null;
    document.getElementById('import-modal').classList.add('hidden');
  });
  setupUnitRates();
  setupListMenu();
  showSyncStatus();
  document.getElementById('export-btn').addEventListener('click', async () => {
    const r = await window.api.priceLists.exportCSV(currentSourceKey);
    if (r && !r.ok) alert(r.error);
  });

  // Arriving from global search: ?source=SP&q=Base%20Jack
  const params = new URLSearchParams(location.search);
  const wantedSource = params.get('source');
  if (wantedSource && priceLists.some((pl) => pl.sourceKey === wantedSource)) {
    select.value = wantedSource;
    await selectList(wantedSource);
    if (params.get('q')) {
      document.getElementById('search-box').value = params.get('q');
      await applyFilters();
    }
  } else if (priceLists.length > 0) {
    await selectList(priceLists[0].sourceKey);
  } else {
    document.getElementById('table-container').innerHTML =
      '<div class="empty-state"><h2>No price lists imported yet</h2></div>';
  }
}

init();

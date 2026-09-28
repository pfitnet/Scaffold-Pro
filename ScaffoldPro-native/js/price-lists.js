'use strict';

let currentSourceKey = null;
let currentCurrency = 'HKD';
let priceListsMeta = [];
let allItemsForCurrentList = [];

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

function renderDisplayRow(tr, item) {
  tr.innerHTML = `
    <td>${item.itemName}</td>
    <td class="num">${weightText(item.weightKg)}</td>
    <td class="num">${money(item.unitRentalPrice)}</td>
    <td class="num">${money(item.unitSalePrice)}</td>
    <td class="row-actions"><button class="edit-btn">Edit</button> <button class="dup-btn" title="Duplicate">Duplicate</button> <button class="del-btn" title="Delete">Delete</button></td>`;
  tr.querySelector('.edit-btn').addEventListener('click', () => renderEditRow(tr, item));
  tr.querySelector('.dup-btn').addEventListener('click', async () => {
    const r = await window.api.priceLists.duplicateItem(item.id);
    if (!r.ok) { alert(r.error); return; }
    await applyFilters();
  });
  tr.querySelector('.del-btn').addEventListener('click', async () => {
    if (!confirm(`Delete "${item.itemName}" from the material list?\n\nExisting BOQs, quotations and invoices keep their copy of it.`)) return;
    const r = await window.api.priceLists.archiveItem(item.id);
    if (!r.ok) { alert(r.error); return; }
    await applyFilters();
  });
}

function renderEditRow(tr, item) {
  tr.innerHTML = `
    <td>
      <input type="text" class="edit-field edit-name" value="${(item.itemName || '').replace(/"/g, '&quot;')}" placeholder="Item name" />
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

    const table = document.createElement('table');
    table.innerHTML = `
      <thead><tr><th>Item</th><th class="num">Weight</th><th class="num">Rental / Month (${currentCurrency})</th><th class="num">Sale (${currentCurrency})</th><th></th></tr></thead>
      <tbody></tbody>`;
    const tbody = table.querySelector('tbody');

    for (const item of groupItems) {
      const tr = document.createElement('tr');
      renderDisplayRow(tr, item);
      tbody.appendChild(tr);
    }

    section.appendChild(table);
    container.appendChild(section);
  }
}

async function applyFilters() {
  const query = document.getElementById('search-box').value;
  const category = document.getElementById('category-select').value;
  const items = await window.api.priceLists.searchItems({ sourceKey: currentSourceKey, query, category: category || null });
  renderTable(items);
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

  renderTable(allItemsForCurrentList);
}

// ---------- Add item (section 8) ----------

function openAddItem() {
  for (const f of ['itemName', 'category', 'unit', 'weightKg', 'unitSalePrice', 'unitRentalPrice']) {
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

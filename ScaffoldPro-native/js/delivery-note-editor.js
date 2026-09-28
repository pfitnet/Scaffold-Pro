'use strict';

let deliveryNoteId = null;
let currentDetail = null;

function getIdFromURL() {
  const params = new URLSearchParams(location.search);
  return params.get('id');
}

async function loadDetail() {
  currentDetail = await window.api.deliveryNotes.get(deliveryNoteId);
  if (!currentDetail) {
    document.getElementById('not-found').classList.remove('hidden');
    document.getElementById('dn-body').classList.add('hidden');
    return;
  }
  document.getElementById('dn-body').classList.remove('hidden');
  render();
}

function render() {
  const d = currentDetail;
  document.title = `${d.deliveryNoteNumber} — ScaffoldPro`;
  document.getElementById('dn-header').innerHTML = `
    <h1>${d.deliveryNoteNumber}</h1>
    <div class="subtitle">${d.projectNumber} — ${d.projectName} · ${d.clientName || 'No client'} · ${d.siteName || 'No site'}</div>`;
  document.getElementById('back-link').href = `project-detail.html?number=${d.projectNumber}`;

  document.getElementById('status-select').value = d.status;
  const isLocked = d.status !== 'Draft';

  const addressInput = document.getElementById('delivery-address-input');
  if (document.activeElement !== addressInput) addressInput.value = d.deliveryAddress || '';
  addressInput.disabled = isLocked;

  const deliveredByInput = document.getElementById('delivered-by-input');
  if (document.activeElement !== deliveredByInput) deliveredByInput.value = d.deliveredBy || '';
  deliveredByInput.disabled = isLocked;

  const receivedByInput = document.getElementById('received-by-input');
  if (document.activeElement !== receivedByInput) receivedByInput.value = d.receivedBy || '';
  receivedByInput.disabled = isLocked;

  const notesBox = document.getElementById('notes-box');
  if (document.activeElement !== notesBox) notesBox.value = d.notes || '';
  notesBox.disabled = isLocked;

  renderLineItems();
}

function renderLineItems() {
  const container = document.getElementById('line-items');
  const items = currentDetail.lineItems;
  const isLocked = currentDetail.status !== 'Draft';

  if (items.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>No items yet</h2><p>Add materials from the list on the left.</p></div>`;
    return;
  }

  const table = document.createElement('table');
  table.innerHTML = `
    <thead><tr><th class="num row-no">No.</th><th>Description</th><th>Unit</th><th class="num">Qty</th><th></th></tr></thead>
    <tbody></tbody>`;
  const tbody = table.querySelector('tbody');

  for (const [index, item] of items.entries()) {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td class="num row-no">${index + 1}</td>
      <td>${item.itemDescription}</td>
      <td>${item.unit}</td>
      <td class="num"><input type="number" class="qty-input" min="1" step="1" value="${Math.round(item.quantity)}" ${isLocked ? 'disabled' : ''} /></td>
      <td>${isLocked ? '' : '<button class="remove-btn">Remove</button>'}</td>`;

    const qtyInput = tr.querySelector('.qty-input');
    qtyInput.addEventListener('change', () => updateLine(item.id, { quantity: Math.max(1, Math.round(Number(qtyInput.value) || 0)) }));
    const removeBtn = tr.querySelector('.remove-btn');
    if (removeBtn) removeBtn.addEventListener('click', () => removeLine(item.id));

    tbody.appendChild(tr);
  }

  container.innerHTML = '';
  container.appendChild(table);
}

async function updateLine(lineId, changes) {
  const result = await window.api.deliveryNotes.updateLineItem(lineId, changes);
  if (!result.ok) { alert(result.error); }
  await loadDetail();
}

async function removeLine(lineId) {
  const result = await window.api.deliveryNotes.removeLineItem(lineId);
  if (!result.ok) { alert(result.error); }
  await loadDetail();
}

async function saveHeader() {
  const header = {
    deliveryAddress: document.getElementById('delivery-address-input').value || null,
    deliveredBy: document.getElementById('delivered-by-input').value || null,
    receivedBy: document.getElementById('received-by-input').value || null,
    notes: document.getElementById('notes-box').value || null,
  };
  const result = await window.api.deliveryNotes.updateHeader(deliveryNoteId, header);
  if (!result.ok) { alert(result.error); }
  await loadDetail();
}

async function renderPickerResults() {
  const sourceKey = document.getElementById('source-select').value;
  const query = document.getElementById('search-box').value;
  const category = document.getElementById('category-select').value;
  const items = await window.api.priceLists.searchItems({ sourceKey, query, category: category || null });

  const container = document.getElementById('picker-results');
  if (items.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>No items match</h2></div>`;
    return;
  }

  const table = document.createElement('table');
  table.innerHTML = `<thead><tr><th>Item</th><th></th></tr></thead><tbody></tbody>`;
  const tbody = table.querySelector('tbody');

  for (const item of items) {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${item.itemName}</td>
      <td><button class="add-btn" ${currentDetail.status !== 'Draft' ? 'disabled' : ''}>+ Add</button></td>`;
    tr.querySelector('.add-btn').addEventListener('click', () => addFromPicker(item));
    tbody.appendChild(tr);
  }

  container.innerHTML = '';
  container.appendChild(table);
}

async function addFromPicker(item) {
  const result = await window.api.deliveryNotes.addLineItem({
    deliveryNoteId: deliveryNoteId,
    sourceKey: item.sourceKey,
    priceListItemId: item.id,
    itemCode: item.itemCode,
    description: item.itemName,
    unit: item.unit,
    quantity: 1,
    section: item.category,
  });
  if (!result.ok) { alert(result.error); return; }
  await loadDetail();
}

async function populateCategories() {
  const sourceKey = document.getElementById('source-select').value;
  const items = await window.api.priceLists.searchItems({ sourceKey });
  const categories = [...new Set(items.map((i) => i.category).filter(Boolean))].sort();
  document.getElementById('category-select').innerHTML =
    '<option value="">All Categories</option>' + categories.map((c) => `<option value="${c}">${c}</option>`).join('');
}

async function init() {
  deliveryNoteId = getIdFromURL();
  if (!deliveryNoteId) {
    document.getElementById('not-found').classList.remove('hidden');
    return;
  }

  await loadDetail();
  if (!currentDetail) return;

  document.getElementById('status-select').addEventListener('change', async (e) => {
    const result = await window.api.deliveryNotes.updateStatus(deliveryNoteId, e.target.value);
    if (!result.ok) { alert(result.error); }
    await loadDetail();
  });

  for (const fieldId of ['delivery-address-input', 'delivered-by-input', 'received-by-input', 'notes-box']) {
    document.getElementById(fieldId).addEventListener('change', saveHeader);
  }

  document.getElementById('export-pdf-btn').addEventListener('click', async () => {
    const result = await window.api.deliveryNotes.exportPDF(deliveryNoteId);
    if (!result.ok) { alert(result.error); }
  });


  // Custom item not on a price list (section 21).
  document.getElementById('ci-add-btn').addEventListener('click', async () => {
    const description = document.getElementById('ci-description').value.trim();
    if (!description) { document.getElementById('ci-description').focus(); return; }
    const result = await window.api.deliveryNotes.addLineItem({
      deliveryNoteId: deliveryNoteId,
      sourceKey: null,
      priceListItemId: null,
      itemCode: '',
      description: description,
      unit: document.getElementById('ci-unit').value.trim() || 'lot',
      quantity: Math.max(1, Math.round(Number(document.getElementById('ci-qty').value) || 1)),
      section: 'Other',
    });
    if (!result.ok) { alert(result.error); return; }
    document.getElementById('ci-description').value = '';
    document.getElementById('ci-qty').value = 1;
    
    await loadDetail();
  });

  document.getElementById('print-btn').addEventListener('click', async () => {
    const result = await window.api.deliveryNotes.print(deliveryNoteId);
    if (!result.ok) { alert(result.error); }
  });

  document.getElementById('source-select').addEventListener('change', async () => {
    await populateCategories();
    await renderPickerResults();
  });
  document.getElementById('search-box').addEventListener('input', renderPickerResults);
  document.getElementById('category-select').addEventListener('change', renderPickerResults);

  await populateCategories();
  await renderPickerResults();
}

init();

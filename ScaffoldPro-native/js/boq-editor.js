'use strict';

let boqId = null;
let currentDetail = null;

function getBOQIdFromURL() {
  const params = new URLSearchParams(location.search);
  return params.get('id');
}

// "1,234.56" format everywhere (not "1234.56").
function money(value) {
  return Number(value || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// Quantities are whole numbers: "1,250".
function qty(value) {
  return Math.round(Number(value || 0)).toLocaleString('en-US', { maximumFractionDigits: 0 });
}

function priceForMode(item, pricingMode) {
  const primary = pricingMode === 'Sale' ? item.unitSalePrice : item.unitRentalPrice;
  const fallback = pricingMode === 'Sale' ? item.unitRentalPrice : item.unitSalePrice;
  const value = primary !== null && primary !== undefined ? primary : fallback;
  return value === null || value === undefined ? 0 : value;
}

async function loadDetail() {
  currentDetail = await window.api.boq.get(boqId);
  if (!currentDetail) {
    document.getElementById('not-found').classList.remove('hidden');
    document.getElementById('boq-body').classList.add('hidden');
    return;
  }
  document.getElementById('boq-body').classList.remove('hidden');
  render();
}

function render() {
  const d = currentDetail;
  document.title = `${d.boqNumber} — ScaffoldPro`;
  document.getElementById('boq-header').innerHTML = `
    <h1>${d.boqNumber}</h1>
    <div class="subtitle">${d.projectNumber} — ${d.projectName} · ${d.pricingMode} pricing</div>`;
  document.getElementById('back-link').href = `project-detail.html?number=${d.projectNumber}`;

  // BOQ settings bar
  const locked = d.status !== 'Draft';
  const modeSel = document.getElementById('boq-mode-select');
  modeSel.value = d.pricingMode;
  modeSel.disabled = locked;
  const markup = document.getElementById('boq-markup-input');
  if (document.activeElement !== markup) markup.value = d.markupPercent || 0;
  markup.disabled = locked;
  const structure = document.getElementById('boq-structure-input');
  if (document.activeElement !== structure) structure.value = d.structure || '';
  structure.disabled = locked;

  const statusSelect = document.getElementById('status-select');
  statusSelect.value = d.status;
  document.getElementById('custom-item-box').classList.toggle('hidden', d.status !== 'Draft');

  const isIssued = d.status === 'Issued';
  renderLineItems();

  const notesBox = document.getElementById('notes-box');
  if (document.activeElement !== notesBox) {
    notesBox.value = d.notes || '';
  }
  notesBox.disabled = isIssued;
}

function weight(value) {
  return value === null || value === undefined ? '—'
    : Number(value).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// The BOQ is a materials-and-weight document: it shows each item's unit
// weight and line weight instead of prices. Prices are still recorded
// behind the scenes (from the BOQ's Sale/Rental mode) so a Quotation
// created from or referencing this BOQ is pre-priced.
function renderLineItems() {
  const container = document.getElementById('line-items');
  const items = currentDetail.lineItems;
  const isIssued = currentDetail.status === 'Issued';

  if (items.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>No line items yet</h2><p>Add materials from the list on the left.</p></div>`;
    document.getElementById('grand-total').textContent = '';
    return;
  }

  const table = document.createElement('table');
  table.innerHTML = `
    <thead>
      <tr><th class="num row-no">No.</th><th>Description</th><th>Unit</th><th class="num">Qty</th><th class="num">Unit Wt (kg)</th><th class="num">Total Wt (kg)</th><th></th></tr>
    </thead>
    <tbody></tbody>`;
  const tbody = table.querySelector('tbody');

  for (const [index, item] of items.entries()) {
    const hasWeight = item.weightKg !== null && item.weightKg !== undefined;
    const lineWeight = hasWeight ? item.weightKg * item.quantity : null;

    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td class="num row-no">${index + 1}</td>
      <td>${item.itemDescription}
        ${isIssued
          ? (item.notes ? `<div class="line-note">${item.notes}</div>` : '')
          : `<input type="text" class="line-note-input" placeholder="Add a note" value="${(item.notes || '').replace(/"/g, '&quot;')}" />`}</td>
      <td>${item.unit}</td>
      <td class="num"><input type="number" class="qty-input" min="1" step="1" value="${Math.round(item.quantity)}" ${isIssued ? 'disabled' : ''} /></td>
      <td class="num">${weight(item.weightKg)}</td>
      <td class="num">${weight(lineWeight)}</td>
      <td class="row-actions">${isIssued ? '' : `
        <button class="icon-btn up-btn" title="Move up" ${index === 0 ? 'disabled' : ''}>↑</button>
        <button class="icon-btn down-btn" title="Move down" ${index === items.length - 1 ? 'disabled' : ''}>↓</button>
        <button class="icon-btn dup-btn" title="Duplicate line">⧉</button>
        <button class="remove-btn">Remove</button>`}</td>`;

    const qtyInput = tr.querySelector('.qty-input');
    qtyInput.addEventListener('change', () => updateLine(item.id, { quantity: Math.max(1, Math.round(Number(qtyInput.value) || 0)) }));
    const removeBtn = tr.querySelector('.remove-btn');
    if (removeBtn) removeBtn.addEventListener('click', () => removeLine(item.id));
    const lineAction = async (call) => {
      const r = await call();
      if (!r.ok) alert(r.error);
      await loadDetail();
    };
    const up = tr.querySelector('.up-btn');
    if (up) up.addEventListener('click', () => lineAction(() => window.api.boq.moveLineItem(item.id, -1)));
    const down = tr.querySelector('.down-btn');
    if (down) down.addEventListener('click', () => lineAction(() => window.api.boq.moveLineItem(item.id, 1)));
    const dup = tr.querySelector('.dup-btn');
    if (dup) dup.addEventListener('click', () => lineAction(() => window.api.boq.duplicateLineItem(item.id)));
    const note = tr.querySelector('.line-note-input');
    if (note) note.addEventListener('change', async () => {
      const r = await window.api.boq.updateLineNotes(item.id, note.value);
      if (!r.ok) alert(r.error);
    });

    tbody.appendChild(tr);
  }

  container.innerHTML = '';
  container.appendChild(table);
  document.getElementById('grand-total').textContent = `Total Weight: ${weight(currentDetail.totalWeightKg)} kg`;
}

async function updateLine(lineId, changes) {
  const result = await window.api.boq.updateLineItem(lineId, changes);
  if (!result.ok) { alert(result.error); }
  await loadDetail();
}

async function removeLine(lineId) {
  const result = await window.api.boq.removeLineItem(lineId);
  if (!result.ok) { alert(result.error); }
  await loadDetail();
}

async function renderPickerResults() {
  const sourceKey = document.getElementById('source-select').value;
  const query = document.getElementById('search-box').value;
  const category = document.getElementById('category-select').value;
  const items = await window.api.priceLists.searchItems({ sourceKey, query, category: category || null, inBaseCurrency: true });

  const container = document.getElementById('picker-results');
  if (items.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>No items match</h2></div>`;
    return;
  }

  const table = document.createElement('table');
  table.innerHTML = `<thead><tr><th>Item</th><th class="num">Weight (kg)</th><th></th></tr></thead><tbody></tbody>`;
  const tbody = table.querySelector('tbody');

  for (const item of items) {
    const price = priceForMode(item, currentDetail.pricingMode);
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${item.itemName}</td>
      <td class="num">${weight(item.weightKg)}</td>
      <td><button class="add-btn" ${currentDetail.status === 'Issued' ? 'disabled' : ''}>+ Add</button></td>`;
    tr.querySelector('.add-btn').addEventListener('click', () => addFromPicker(item, price));
    tbody.appendChild(tr);
  }

  container.innerHTML = '';
  container.appendChild(table);
}

async function addFromPicker(item, price) {
  const result = await window.api.boq.addLineItem({
    boqId: boqId,
    sourceKey: item.sourceKey,
    priceListItemId: item.id,
    itemCode: item.itemCode,
    description: item.itemName,
    unit: item.unit,
    quantity: 1,
    priceListUnitPrice: price,
    appliedUnitPrice: price,
    weightKg: item.weightKg === undefined ? null : item.weightKg,
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
  boqId = getBOQIdFromURL();
  if (!boqId) {
    document.getElementById('not-found').classList.remove('hidden');
    return;
  }

  await loadDetail();
  if (!currentDetail) return;
  window.setupLinkedDrawings({ kind: 'BOQ', id: boqId, projectNumber: currentDetail.projectNumber });

  document.getElementById('status-select').addEventListener('change', async (e) => {
    if (currentDetail.status === 'Issued' && e.target.value === 'Draft' &&
        !confirm('Return this BOQ to Draft?\n\nIt has already been issued; its items become editable again.')) {
      e.target.value = currentDetail.status;
      return;
    }
    const result = await window.api.boq.updateStatus(boqId, e.target.value);
    if (!result.ok) { alert(result.error); }
    await loadDetail();
  });

  document.getElementById('notes-box').addEventListener('change', async (e) => {
    await window.api.boq.updateNotes(boqId, e.target.value);
  });

  // BOQ settings: switching Sale/Rental or the mark-up re-prices the lines.
  document.getElementById('boq-mode-select').addEventListener('change', async (e) => {
    const to = e.target.value;
    if (currentDetail.lineItems.length > 0 &&
        !confirm(`Change this BOQ to ${to} pricing?\n\nEvery item from the material list will be re-priced at its ${to.toLowerCase()} price (with this BOQ's mark-up). Prices you typed in by hand are kept. Weights don't change.`)) {
      e.target.value = currentDetail.pricingMode;
      return;
    }
    const r = await window.api.boq.updateDetails(boqId, { pricingMode: to });
    if (!r.ok) alert(r.error);
    await loadDetail();
    await renderPickerResults();
  });
  document.getElementById('boq-markup-input').addEventListener('change', async (e) => {
    const r = await window.api.boq.updateDetails(boqId, { markupPercent: Number(e.target.value) || 0 });
    if (!r.ok) alert(r.error);
    await loadDetail();
  });
  document.getElementById('boq-structure-input').addEventListener('change', async (e) => {
    const r = await window.api.boq.updateDetails(boqId, { structure: e.target.value });
    if (!r.ok) alert(r.error);
    await loadDetail();
  });

  document.getElementById('export-pdf-btn').addEventListener('click', async () => {
    const result = await window.api.boq.exportPDF(boqId);
    if (!result.ok) { alert(result.error); }
  });


  // Custom item not on a price list (section 21).
  document.getElementById('ci-add-btn').addEventListener('click', async () => {
    const description = document.getElementById('ci-description').value.trim();
    if (!description) { document.getElementById('ci-description').focus(); return; }
    const result = await window.api.boq.addLineItem({
      boqId: boqId,
      sourceKey: null,
      priceListItemId: null,
      itemCode: '',
      description: description,
      unit: document.getElementById('ci-unit').value.trim() || 'lot',
      quantity: Math.max(1, Math.round(Number(document.getElementById('ci-qty').value) || 1)),
      appliedUnitPrice: 0,
      priceListUnitPrice: null,
      weightKg: document.getElementById('ci-extra').value === '' ? null : Number(document.getElementById('ci-extra').value),
      section: 'Other',
    });
    if (!result.ok) { alert(result.error); return; }
    document.getElementById('ci-description').value = '';
    document.getElementById('ci-qty').value = 1;
    document.getElementById('ci-extra').value = '';
    await loadDetail();
  });

  document.getElementById('print-btn').addEventListener('click', async () => {
    const result = await window.api.boq.print(boqId);
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

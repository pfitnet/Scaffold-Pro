'use strict';

let invoiceId = null;
let currentDetail = null;

function getInvoiceIdFromURL() {
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

function defaultPrice(item) {
  const value = item.unitRentalPrice !== null && item.unitRentalPrice !== undefined ? item.unitRentalPrice : item.unitSalePrice;
  return value === null || value === undefined ? 0 : value;
}

async function loadDetail() {
  currentDetail = await window.api.invoices.get(invoiceId);
  if (!currentDetail) {
    document.getElementById('not-found').classList.remove('hidden');
    document.getElementById('invoice-body').classList.add('hidden');
    return;
  }
  document.getElementById('invoice-body').classList.remove('hidden');
  render();
}

function render() {
  const d = currentDetail;
  document.title = `${d.invoiceNumber} — ScaffoldPro`;
  document.getElementById('invoice-header').innerHTML = `
    <h1>${d.invoiceNumber}</h1>
    <div class="subtitle">${d.projectNumber} — ${d.projectName} · ${d.clientName || 'No client'} · ${d.siteName || 'No site'}</div>`;
  document.getElementById('back-link').href = `project-detail.html?number=${d.projectNumber}`;

  document.getElementById('status-select').value = d.status;

  const isLocked = d.status !== 'Draft';

  const dueDateInput = document.getElementById('due-date-input');
  if (document.activeElement !== dueDateInput) dueDateInput.value = d.dueDate || '';
  dueDateInput.disabled = isLocked;

  const paymentTermsInput = document.getElementById('payment-terms-input');
  if (document.activeElement !== paymentTermsInput) paymentTermsInput.value = d.paymentTerms || '';
  paymentTermsInput.disabled = isLocked;

  const discountTypeSelect = document.getElementById('discount-type-select');
  discountTypeSelect.value = d.discountType;
  discountTypeSelect.disabled = isLocked;

  const discountValueInput = document.getElementById('discount-value-input');
  if (document.activeElement !== discountValueInput) discountValueInput.value = d.discountValue;
  discountValueInput.disabled = isLocked;

  const taxRateInput = document.getElementById('tax-rate-input');
  if (document.activeElement !== taxRateInput) taxRateInput.value = d.taxRatePercent;
  taxRateInput.disabled = isLocked;

  const notesBox = document.getElementById('notes-box');
  if (document.activeElement !== notesBox) notesBox.value = d.notes || '';
  notesBox.disabled = isLocked;

  const paymentRow = document.getElementById('payment-row');
  const canRecordPayment = d.status !== 'Draft' && d.status !== 'Cancelled' && d.status !== 'Paid';
  paymentRow.classList.toggle('hidden', !canRecordPayment);

  renderLineItems();
  renderTotals();
}

function renderLineItems() {
  const container = document.getElementById('line-items');
  const items = currentDetail.lineItems;
  const isLocked = currentDetail.status !== 'Draft';

  if (items.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>No line items yet</h2><p>Add materials from the list on the left.</p></div>`;
    return;
  }

  const table = document.createElement('table');
  table.innerHTML = `
    <thead><tr><th class="num row-no">No.</th><th>Description</th><th>Unit</th><th class="num">Qty</th><th class="num">Unit Price</th><th class="num">Total</th><th></th></tr></thead>
    <tbody></tbody>`;
  const tbody = table.querySelector('tbody');

  for (const [index, item] of items.entries()) {
    const lineTotal = item.quantity * item.appliedUnitPrice;
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td class="num row-no">${index + 1}</td>
      <td>${item.itemDescription}</td>
      <td>${item.unit}</td>
      <td class="num"><input type="number" class="qty-input" min="1" step="1" value="${Math.round(item.quantity)}" ${isLocked ? 'disabled' : ''} /></td>
      <td class="num"><input type="number" class="price-input" min="0" step="0.01" value="${item.appliedUnitPrice}" ${isLocked ? 'disabled' : ''} /></td>
      <td class="num">${money(lineTotal)}</td>
      <td>${isLocked ? '' : '<button class="remove-btn">Remove</button>'}</td>`;

    const qtyInput = tr.querySelector('.qty-input');
    const priceInput = tr.querySelector('.price-input');
    qtyInput.addEventListener('change', () => updateLine(item.id, { quantity: Math.max(1, Math.round(Number(qtyInput.value) || 0)) }));
    priceInput.addEventListener('change', () => updateLine(item.id, { appliedUnitPrice: parseFloat(priceInput.value) || 0 }));
    const removeBtn = tr.querySelector('.remove-btn');
    if (removeBtn) removeBtn.addEventListener('click', () => removeLine(item.id));

    tbody.appendChild(tr);
  }

  container.innerHTML = '';
  container.appendChild(table);
}

function renderTotals() {
  const d = currentDetail;
  const box = document.getElementById('totals-box');
  box.innerHTML = `
    <div class="row"><span>Subtotal</span><span>${money(d.subtotal)}</span></div>
    <div class="row"><span>Discount</span><span>-${money(d.discountAmount)}</span></div>
    <div class="row"><span>Tax / VAT</span><span>${money(d.taxAmount)}</span></div>
    <div class="row grand"><span>Total</span><span>${money(d.total)}</span></div>
    <div class="row"><span>Paid</span><span>${money(d.amountPaid)}</span></div>
    <div class="row balance"><span>Balance Due</span><span>${money(d.balanceDue)}</span></div>`;
}

async function updateLine(lineId, changes) {
  const result = await window.api.invoices.updateLineItem(lineId, changes);
  if (!result.ok) { alert(result.error); }
  await loadDetail();
}

async function removeLine(lineId) {
  const result = await window.api.invoices.removeLineItem(lineId);
  if (!result.ok) { alert(result.error); }
  await loadDetail();
}

async function saveHeader() {
  const header = {
    dueDate: document.getElementById('due-date-input').value || null,
    paymentTerms: document.getElementById('payment-terms-input').value || null,
    notes: document.getElementById('notes-box').value || null,
    discountType: document.getElementById('discount-type-select').value,
    discountValue: parseFloat(document.getElementById('discount-value-input').value) || 0,
    taxRatePercent: parseFloat(document.getElementById('tax-rate-input').value) || 0,
  };
  const result = await window.api.invoices.updateHeader(invoiceId, header);
  if (!result.ok) { alert(result.error); }
  await loadDetail();
}

async function recordPayment() {
  const input = document.getElementById('payment-amount-input');
  const amount = parseFloat(input.value) || 0;
  const result = await window.api.invoices.recordPayment(invoiceId, amount);
  if (!result.ok) { alert(result.error); return; }
  input.value = '';
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
  table.innerHTML = `<thead><tr><th>Item</th><th class="num">Price</th><th></th></tr></thead><tbody></tbody>`;
  const tbody = table.querySelector('tbody');

  for (const item of items) {
    const price = defaultPrice(item);
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${item.itemName}</td>
      <td class="num">${money(price)}</td>
      <td><button class="add-btn" ${currentDetail.status !== 'Draft' ? 'disabled' : ''}>+ Add</button></td>`;
    tr.querySelector('.add-btn').addEventListener('click', () => addFromPicker(item, price));
    tbody.appendChild(tr);
  }

  container.innerHTML = '';
  container.appendChild(table);
}

async function addFromPicker(item, price) {
  const result = await window.api.invoices.addLineItem({
    invoiceId: invoiceId,
    sourceKey: item.sourceKey,
    priceListItemId: item.id,
    itemCode: item.itemCode,
    description: item.itemName,
    unit: item.unit,
    quantity: 1,
    appliedUnitPrice: price,
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
  invoiceId = getInvoiceIdFromURL();
  if (!invoiceId) {
    document.getElementById('not-found').classList.remove('hidden');
    return;
  }

  await loadDetail();
  if (!currentDetail) return;

  document.getElementById('status-select').addEventListener('change', async (e) => {
    const result = await window.api.invoices.updateStatus(invoiceId, e.target.value);
    if (!result.ok) { alert(result.error); }
    await loadDetail();
  });

  document.getElementById('export-pdf-btn').addEventListener('click', async () => {
    const result = await window.api.invoices.exportPDF(invoiceId);
    if (!result.ok) { alert(result.error); }
  });


  // Custom item not on a price list (section 21).
  document.getElementById('ci-add-btn').addEventListener('click', async () => {
    const description = document.getElementById('ci-description').value.trim();
    if (!description) { document.getElementById('ci-description').focus(); return; }
    const result = await window.api.invoices.addLineItem({
      invoiceId: invoiceId,
      sourceKey: null,
      priceListItemId: null,
      itemCode: '',
      description: description,
      unit: document.getElementById('ci-unit').value.trim() || 'lot',
      quantity: Math.max(1, Math.round(Number(document.getElementById('ci-qty').value) || 1)),
      appliedUnitPrice: Number(document.getElementById('ci-extra').value) || 0,
      section: 'Other',
    });
    if (!result.ok) { alert(result.error); return; }
    document.getElementById('ci-description').value = '';
    document.getElementById('ci-qty').value = 1;
    document.getElementById('ci-extra').value = '';
    await loadDetail();
  });

  document.getElementById('print-btn').addEventListener('click', async () => {
    const result = await window.api.invoices.print(invoiceId);
    if (!result.ok) { alert(result.error); }
  });

  for (const fieldId of ['due-date-input', 'payment-terms-input', 'discount-type-select', 'discount-value-input', 'tax-rate-input', 'notes-box']) {
    document.getElementById(fieldId).addEventListener('change', saveHeader);
  }

  document.getElementById('record-payment-btn').addEventListener('click', recordPayment);

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

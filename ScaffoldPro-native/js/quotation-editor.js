'use strict';

// Section 25: issued documents are protected. Cancelled is final, and
// reopening an issued document for editing asks first.
function allowStatusChange(from, to, label) {
  if (from === 'Cancelled' && to !== 'Cancelled') return false;
  if (from !== 'Draft' && to === 'Draft') {
    return confirm(`Return this ${label} to Draft?\n\nIt has already been issued. Editing it afterwards means the copy you sent no longer matches — consider cancelling it and creating a new one instead.`);
  }
  if (to === 'Cancelled' && from !== 'Cancelled') {
    return confirm(`Cancel this ${label}?\n\nIt will be kept for your records but can't be reopened.`);
  }
  return true;
}

function lockStatusOptions(select, status, finalFromIssued) {
  for (const opt of select.options) {
    opt.disabled = (status === 'Cancelled' && opt.value !== 'Cancelled') ||
      (finalFromIssued && status !== 'Draft' && opt.value === 'Draft');
  }
}

let quotationId = null;
let currentDetail = null;
// Currency label from Settings (section 50) — "HK$" for HKD, as on the PDF.
let currencyLabel = '';

function getQuotationIdFromURL() {
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

// An ISO timestamp → "yyyy-mm-dd" in local time, for a date field.
function localDay(iso) {
  const d = new Date(iso || '');
  if (isNaN(d)) return '';
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function priceForMode(item, pricingMode) {
  const primary = pricingMode === 'Sale' ? item.unitSalePrice : item.unitRentalPrice;
  const fallback = pricingMode === 'Sale' ? item.unitRentalPrice : item.unitSalePrice;
  const value = primary !== null && primary !== undefined ? primary : fallback;
  return value === null || value === undefined ? 0 : value;
}

async function loadDetail() {
  currentDetail = await window.api.quotations.get(quotationId);
  if (!currentDetail) {
    document.getElementById('not-found').classList.remove('hidden');
    document.getElementById('quotation-body').classList.add('hidden');
    return;
  }
  document.getElementById('quotation-body').classList.remove('hidden');
  render();
}

function render() {
  const d = currentDetail;
  document.title = `${d.quotationNumber} — ScaffoldPro`;
  document.getElementById('quotation-header').innerHTML = `
    <h1>${d.quotationNumber}</h1>
    <div class="subtitle">${d.projectNumber} — ${d.projectName} · ${d.clientName || 'No client'} · ${d.siteName || 'No site'} · ${d.pricingMode} pricing</div>`;
  document.getElementById('back-link').href = `project-detail.html?number=${d.projectNumber}`;

  document.getElementById('status-select').value = d.status;
  lockStatusOptions(document.getElementById('status-select'), d.status, false);
  document.getElementById('custom-item-box').classList.toggle('hidden', d.status !== 'Draft');

  const isLocked = d.status !== 'Draft';

  renderLetterFields();
  const pricingModeSelect = document.getElementById('pricing-mode-select');
  pricingModeSelect.value = d.pricingMode;
  pricingModeSelect.disabled = isLocked;

  document.getElementById('boq-reference-select').disabled = isLocked;
  document.getElementById('import-boq-btn').disabled = isLocked;
  document.getElementById('boq-reference-note').textContent = d.sourceBOQNumber
    ? `Currently referencing ${d.sourceBOQNumber}`
    : 'Not linked to a BOQ';

  const docDateInput = document.getElementById('doc-date-input');
  if (document.activeElement !== docDateInput) docDateInput.value = localDay(d.quotationDate);
  docDateInput.disabled = isLocked;

  const validUntilInput = document.getElementById('valid-until-input');
  if (document.activeElement !== validUntilInput) validUntilInput.value = d.validUntil || '';
  validUntilInput.disabled = isLocked;

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
    <thead><tr><th class="num row-no">No.</th><th>Description</th><th>Unit</th><th class="num">Qty</th><th class="num">Unit Price</th><th>Discount</th><th class="num">Total</th><th></th></tr></thead>
    <tbody></tbody>`;
  const tbody = table.querySelector('tbody');

  // Materials are numbered 1, 2, 3…; delivery charges D1, D2… (as on Qt26193).
  let materialNo = 0;
  let deliveryNo = 0;
  for (const [index, item] of items.entries()) {
    const lineTotal = window.lineNetTotal(item);
    const isDelivery = item.section === 'Delivery';
    // Section 20: a hand-typed price shows the material-list price under it.
    const listPrice = item.priceListUnitPrice;
    const overridden = listPrice !== null && listPrice !== undefined && Math.abs(listPrice - item.appliedUnitPrice) > 0.004;
    const discountLabel = window.lineDiscountLabel(item, currencyLabel);
    const rowNo = isDelivery ? `D${++deliveryNo}` : String(++materialNo);
    void index;
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td class="num row-no">${rowNo}</td>
      <td>${isDelivery ? '<span class="line-tag">Delivery</span>' : ''}${item.itemDescription}</td>
      <td>${item.unit}</td>
      <td class="num"><input type="number" class="qty-input" min="1" step="1" value="${Math.round(item.quantity)}" ${isLocked ? 'disabled' : ''} /></td>
      <td class="num"><input type="number" class="price-input${overridden ? ' override' : ''}" min="0" step="0.01" value="${item.appliedUnitPrice}" ${isLocked ? 'disabled' : ''} />${overridden ? `<span class="ref-price">List ${money(listPrice)}</span>` : ''}</td>
      <td>${isLocked ? (discountLabel ? `<span class="line-discount-note">${discountLabel}</span>` : '') : `<button class="discount-btn${discountLabel ? ' active' : ''}" title="Discount this item">${discountLabel || 'Discount'}</button>`}</td>
      <td class="num">${money(lineTotal)}</td>
      <td>${isLocked ? '' : '<button class="remove-btn">Remove</button>'}</td>`;

    const qtyInput = tr.querySelector('.qty-input');
    const priceInput = tr.querySelector('.price-input');
    qtyInput.addEventListener('change', () => updateLine(item.id, { quantity: Math.max(1, Math.round(Number(qtyInput.value) || 0)) }));
    priceInput.addEventListener('change', () => updateLine(item.id, { appliedUnitPrice: parseFloat(priceInput.value) || 0 }));
    const removeBtn = tr.querySelector('.remove-btn');
    if (removeBtn) removeBtn.addEventListener('click', () => removeLine(item.id));
    const discountBtn = tr.querySelector('.discount-btn');
    if (discountBtn) discountBtn.addEventListener('click', () => {
      window.openLineDiscount(item, currencyLabel, async (type, value) => {
        const r = await window.api.quotations.updateLineDiscount(item.id, type, value);
        if (r.ok) await loadDetail();
        return r;
      });
    });

    tbody.appendChild(tr);
  }

  container.innerHTML = '';
  container.appendChild(table);
}

function renderTotals() {
  const d = currentDetail;
  const box = document.getElementById('totals-box');
  const rows = [];
  if (d.pricingMode === 'Rental') {
    rows.push(['Subtotal of Monthly Rental Charge', money(d.materialsSubtotal)]);
    if (d.minimumHireEnabled) {
      rows.push([`Minimum Hire of ${d.hireMonths} Month${d.hireMonths === 1 ? '' : 's'}`, money(d.materialsCharge)]);
    }
  } else {
    rows.push(['Materials', money(d.materialsSubtotal)]);
  }
  if (d.deliveryTotal > 0) rows.push(['Delivery Charges', money(d.deliveryTotal)]);
  if (d.discountAmount > 0) rows.push(['Discount', `-${money(d.discountAmount)}`]);
  if (d.taxAmount > 0) rows.push(['Tax / VAT', money(d.taxAmount)]);
  box.innerHTML = rows.map(([k, v]) => `<div class="row"><span>${k}</span><span>${v}</span></div>`).join('') +
    `<div class="row grand"><span>Total Amount</span><span>${currencyLabel} ${money(d.total)}</span></div>`;
}

// ---------- Standard quotation letter fields ----------

const LETTER_FIELDS = ['subject', 'clientRef', 'siteRef', 'deliveryMethod'];

function renderLetterFields() {
  const d = currentDetail;
  const locked = d.status !== 'Draft';
  for (const f of LETTER_FIELDS) {
    const el = document.getElementById(`q-${f}`);
    if (document.activeElement !== el) el.value = d[f] || '';
    el.disabled = locked;
  }
  const hireOn = document.getElementById('q-minimumHireEnabled');
  hireOn.checked = !!d.minimumHireEnabled;
  hireOn.disabled = locked;
  const hire = document.getElementById('q-minimumHireMonths');
  if (document.activeElement !== hire) hire.value = d.minimumHireMonths;
  hire.disabled = locked || !d.minimumHireEnabled;
  document.getElementById('q-hire-field').classList.toggle('hidden', d.pricingMode !== 'Rental');
  document.getElementById('add-delivery-btn').disabled = locked;
}

async function saveLetterField(field, value) {
  const payload = {};
  payload[field] = value;
  const r = await window.api.quotations.updateLetterFields(quotationId, payload);
  if (!r.ok) alert(r.error);
  await loadDetail();
}

async function addDeliveryCharge() {
  const price = currentDetail.standardDeliveryCharge;
  const r = await window.api.quotations.addLineItem({
    quotationId: quotationId,
    sourceKey: null,
    priceListItemId: null,
    itemCode: '',
    description: 'Delivery of materials\n(from yard to site and from site to yard)',
    unit: 'truck/trip',
    quantity: 2,
    appliedUnitPrice: price == null ? 0 : price,
    section: 'Delivery',
  });
  if (!r.ok) { alert(r.error); return; }
  await loadDetail();
}

async function updateLine(lineId, changes) {
  const result = await window.api.quotations.updateLineItem(lineId, changes);
  if (!result.ok) { alert(result.error); }
  await loadDetail();
}

async function removeLine(lineId) {
  const result = await window.api.quotations.removeLineItem(lineId);
  if (!result.ok) { alert(result.error); }
  await loadDetail();
}

async function saveHeader() {
  const header = {
    quotationDate: document.getElementById('doc-date-input').value || null,
    validUntil: document.getElementById('valid-until-input').value || null,
    paymentTerms: document.getElementById('payment-terms-input').value || null,
    notes: document.getElementById('notes-box').value || null,
    discountType: document.getElementById('discount-type-select').value,
    discountValue: parseFloat(document.getElementById('discount-value-input').value) || 0,
    taxRatePercent: parseFloat(document.getElementById('tax-rate-input').value) || 0,
    pricingMode: document.getElementById('pricing-mode-select').value,
  };
  const result = await window.api.quotations.updateHeader(quotationId, header);
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
  table.innerHTML = `<thead><tr><th>Item</th><th class="num">Price</th><th></th></tr></thead><tbody></tbody>`;
  const tbody = table.querySelector('tbody');

  for (const item of items) {
    const price = priceForMode(item, currentDetail.pricingMode);
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
  const result = await window.api.quotations.addLineItem({
    quotationId: quotationId,
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

// "Reference a BOQ for quicker work": lists this project's BOQs and
// pulls a chosen one's items into this quotation, priced for this
// quotation's Sale/Rental setting.
async function populateBOQReference() {
  const boqs = await window.api.boq.listForProject(currentDetail.projectId);
  const select = document.getElementById('boq-reference-select');
  if (boqs.length === 0) {
    select.innerHTML = '<option value="">No BOQs in this project</option>';
    document.getElementById('import-boq-btn').disabled = true;
    return;
  }
  select.innerHTML = boqs.map((b) =>
    `<option value="${b.id}">${b.boqNumber} · ${b.itemCount} items · ${b.status}</option>`).join('');
  if (currentDetail.sourceBOQId && boqs.some((b) => b.id === currentDetail.sourceBOQId)) {
    select.value = currentDetail.sourceBOQId;
  }
}

async function importFromBOQ() {
  const boqId = document.getElementById('boq-reference-select').value;
  if (!boqId) return;
  let replaceExisting = false;
  if (currentDetail.lineItems.length > 0) {
    replaceExisting = confirm(
      'This quotation already has items.\n\nOK = replace them with the BOQ\'s items\nCancel = add the BOQ\'s items below the existing ones');
  }
  const result = await window.api.quotations.importFromBOQ(quotationId, boqId, replaceExisting);
  if (!result.ok) { alert(result.error); return; }
  await loadDetail();
}

async function init() {
  quotationId = getQuotationIdFromURL();
  if (!quotationId) {
    document.getElementById('not-found').classList.remove('hidden');
    return;
  }
  const settings = await window.api.settings.get();
  currencyLabel = settings.currency === 'HKD' ? 'HK$' : settings.currency;

  await loadDetail();
  if (!currentDetail) return;
  window.setupLinkedDrawings({ kind: 'Quotation', id: quotationId, projectNumber: currentDetail.projectNumber });

  document.getElementById('status-select').addEventListener('change', async (e) => {
    if (!allowStatusChange(currentDetail.status, e.target.value, 'quotation')) {
      e.target.value = currentDetail.status;
      return;
    }
    const result = await window.api.quotations.updateStatus(quotationId, e.target.value);
    if (!result.ok) { alert(result.error); }
    await loadDetail();
  });

  document.getElementById('export-pdf-btn').addEventListener('click', async () => {
    const result = await window.api.quotations.exportPDF(quotationId);
    if (!result.ok) { alert(result.error); }
  });


  // Custom item not on a price list (section 21).
  document.getElementById('ci-add-btn').addEventListener('click', async () => {
    const description = document.getElementById('ci-description').value.trim();
    if (!description) { document.getElementById('ci-description').focus(); return; }
    const result = await window.api.quotations.addLineItem({
      quotationId: quotationId,
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
    const result = await window.api.quotations.print(quotationId);
    if (!result.ok) { alert(result.error); }
  });

  for (const fieldId of ['doc-date-input', 'valid-until-input', 'payment-terms-input', 'discount-type-select', 'discount-value-input', 'tax-rate-input', 'notes-box']) {
    document.getElementById(fieldId).addEventListener('change', saveHeader);
  }

  for (const f of LETTER_FIELDS) {
    document.getElementById(`q-${f}`).addEventListener('change', (e) => saveLetterField(f, e.target.value));
  }
  document.getElementById('q-minimumHireEnabled').addEventListener('change', (e) =>
    saveLetterField('minimumHireEnabled', e.target.checked));
  document.getElementById('q-minimumHireMonths').addEventListener('change', (e) =>
    saveLetterField('minimumHireMonths', Math.max(1, Math.round(Number(e.target.value) || 1))));
  document.getElementById('add-delivery-btn').addEventListener('click', addDeliveryCharge);

  await populateBOQReference();
  document.getElementById('import-boq-btn').addEventListener('click', importFromBOQ);

  // Switching Sale ↔ Rental re-prices the items already on the quotation.
  document.getElementById('pricing-mode-select').addEventListener('change', async (e) => {
    const to = e.target.value;
    const fromList = currentDetail.lineItems.some((i) => i.priceListItemId);
    if (fromList && !confirm(`Change this quotation to ${to} pricing?\n\nEvery item from the material list will be re-priced at its ${to.toLowerCase()} price. Prices you typed in by hand are kept.`)) {
      e.target.value = currentDetail.pricingMode;
      return;
    }
    await saveHeader();
    await renderPickerResults();
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

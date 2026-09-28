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

function esc(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
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
  if (document.activeElement !== paymentTermsInput) {
    paymentTermsInput.value = d.paymentTerms || '';
    window.refreshParagraphPreview(paymentTermsInput);
  }
  paymentTermsInput.disabled = isLocked;

  const adjustmentInput = document.getElementById('adjustment-input');
  if (document.activeElement !== adjustmentInput) adjustmentInput.value = formatAdjustment(d);
  adjustmentInput.disabled = isLocked;

  const taxRateInput = document.getElementById('tax-rate-input');
  if (document.activeElement !== taxRateInput) taxRateInput.value = d.taxRatePercent;
  taxRateInput.disabled = isLocked;

  const notesBox = document.getElementById('notes-box');
  if (document.activeElement !== notesBox) notesBox.value = d.notes || '';
  notesBox.disabled = isLocked;

  renderLineItems();
  renderBlocks();
  renderTotals();
}

function renderLineItems() {
  const container = document.getElementById('line-items');
  // Rows of the extra sections are shown in their own sections below.
  const items = currentDetail.lineItems.filter((i) => !i.blockId);
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
    const lineTotal = currentDetail.lineTotals[item.id] ?? window.lineNetTotal(item);
    const effectivePrice = currentDetail.effectiveUnitPrices[item.id] ?? item.appliedUnitPrice;
    const markedUp = Math.abs(effectivePrice - item.appliedUnitPrice) > 0.004;
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
      <td class="num"><input type="number" class="price-input${overridden ? ' override' : ''}" min="0" step="0.01" value="${item.appliedUnitPrice}" ${isLocked ? 'disabled' : ''} />${markedUp ? `<span class="markup-price" title="Price after the quotation markup, as printed">Quoted ${money(effectivePrice)}</span>` : ''}${overridden ? `<span class="ref-price">List ${money(listPrice)}</span>` : ''}</td>
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
      window.openLineDiscount(Object.assign({}, item, { appliedUnitPrice: effectivePrice }), currencyLabel, async (type, value) => {
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
    // Only when it changes the amount: ticked, and more than one month.
    if (d.minimumHireEnabled && d.hireMonths > 1) {
      rows.push([`Minimum Hire of ${d.hireMonths} Month${d.hireMonths === 1 ? '' : 's'}`, money(d.materialsCharge)]);
    }
  } else {
    rows.push(['Materials', money(d.materialsSubtotal)]);
  }
  if (d.deliveryTotal > 0) rows.push(['Delivery Charges', money(d.deliveryTotal)]);
  for (const block of d.blocks.filter((b) => b.kind === 'Priced')) {
    const lines = d.lineItems.filter((i) => i.blockId === block.id);
    if (lines.length === 0) continue;
    rows.push([esc(block.title || 'Other Charges'), money(lines.reduce((sum, i) => sum + (d.lineTotals[i.id] || 0), 0))]);
  }
  if (d.discountAmount > 0) {
    rows.push([d.discountType === 'Percent' ? `Less ${d.discountValue}% Discount` : 'Less Discount', `-${money(d.discountAmount)}`]);
  }
  if (d.taxAmount > 0) rows.push(['Tax / VAT', money(d.taxAmount)]);
  const markupNote = d.markupPercent > 0
    ? `<p class="small-note">Item unit prices include a ${d.markupPercent}% markup, each rounded to the nearest 0.1. Delivery charges aren't marked up.</p>`
    : '';
  box.innerHTML = markupNote + rows.map(([k, v]) => `<div class="row"><span>${k}</span><span>${v}</span></div>`).join('') +
    `<div class="row grand"><span>Total Amount</span><span>${currencyLabel} ${money(d.total)}</span></div>`;
}

// ---------- Extra sections: priced rows, rates-only rows, notes ----------

const BLOCK_KINDS = {
  Priced: 'Priced · added to the total',
  Rates: 'Rates only · shown after the total',
  Note: 'Note · shown after the total',
};

async function blockCall(promise) {
  const r = await promise;
  if (r && !r.ok) alert(r.error);
  await loadDetail();
}

function renderBlocks() {
  const d = currentDetail;
  const container = document.getElementById('extra-sections');
  const locked = d.status !== 'Draft';
  container.innerHTML = '';
  for (const btn of ['add-priced-btn', 'add-rates-btn', 'add-note-btn']) document.getElementById(btn).disabled = locked;

  d.blocks.forEach((block, index) => {
    const lines = d.lineItems.filter((i) => i.blockId === block.id).sort((a, b) => a.sortOrder - b.sortOrder);
    const rates = block.kind === 'Rates';
    const card = document.createElement('div');
    card.className = 'extra-section';

    let body = '';
    if (block.kind !== 'Note') {
      const head = rates
        ? '<th class="num row-no">No.</th><th>Description</th><th class="num">Rate</th><th>Unit</th><th></th><th></th>'
        : '<th class="num row-no">No.</th><th>Description</th><th>Unit</th><th class="num">Qty</th><th class="num">Unit Price</th><th class="num">Total</th><th></th>';
      const rows = lines.map((line, n) => {
        const dis = locked ? 'disabled' : '';
        const common = `<td class="num row-no">${esc(block.prefix)}${n + 1}</td>
          <td><input type="text" class="row-desc" value="${esc(line.itemDescription)}" ${dis} /></td>`;
        const remove = `<td>${locked ? '' : '<button class="row-remove">Remove</button>'}</td>`;
        return rates
          ? `<tr data-id="${line.id}">${common}
              <td class="num"><input type="number" class="row-price" min="0" step="0.01" value="${line.appliedUnitPrice}" ${dis} /></td>
              <td><input type="text" class="row-unit narrow" value="${esc(line.unit)}" ${dis} /></td>
              <td class="rate-only">(Rate Only)</td>${remove}</tr>`
          : `<tr data-id="${line.id}">${common}
              <td><input type="text" class="row-unit narrow" value="${esc(line.unit)}" ${dis} /></td>
              <td class="num"><input type="number" class="row-qty narrow" min="1" step="1" value="${Math.round(line.quantity)}" ${dis} /></td>
              <td class="num"><input type="number" class="row-price" min="0" step="0.01" value="${line.appliedUnitPrice}" ${dis} /></td>
              <td class="num">${money(d.lineTotals[line.id])}</td>${remove}</tr>`;
      }).join('');
      body = `
        <div class="extra-title-row">
          <input type="text" class="block-title" placeholder="Title row (optional), e.g. Design Fees" value="${esc(block.title)}" ${locked ? 'disabled' : ''} />
          <label class="small-note">Rows <input type="text" class="block-prefix" maxlength="4" value="${esc(block.prefix)}" title="Row numbers, e.g. A → A1, A2" ${locked ? 'disabled' : ''} /></label>
        </div>
        ${lines.length ? `<table class="compact"><thead><tr>${head}</tr></thead><tbody>${rows}</tbody></table>` : '<p class="small-note">No rows yet.</p>'}
        ${locked ? '' : `<div class="extra-add-row">
          <input type="text" class="add-desc" placeholder="${rates ? 'e.g. Scaffolder CP' : 'e.g. Design and Drawing'}" />
          ${rates ? '' : '<input type="number" class="add-qty" min="1" step="1" value="1" title="Quantity" />'}
          <input type="number" class="add-price" min="0" step="0.01" placeholder="${rates ? 'Rate' : 'Unit price'}" />
          <input type="text" class="add-unit" value="${rates ? 'md' : ''}" placeholder="Unit" title="Unit${rates ? ', e.g. md (man-day)' : ' (optional), e.g. lot'}" />
          <button class="add-row">Add Row</button>
        </div>`}`;
    }

    card.innerHTML = `
      <div class="extra-head">
        <span class="line-tag">${BLOCK_KINDS[block.kind] || block.kind}</span>
        ${locked ? '' : `<span class="controls">
          <button data-move="up" ${index === 0 ? 'disabled' : ''} title="Move up">↑</button>
          <button data-move="down" ${index === d.blocks.length - 1 ? 'disabled' : ''} title="Move down">↓</button>
          <button class="block-remove">Remove</button>
        </span>`}
      </div>
      ${body}
      <textarea class="block-note" rows="2" placeholder="${block.kind === 'Note' ? 'Note, shown in small italics across the table' : 'Note row (optional), shown in small italics under these rows'}" ${locked ? 'disabled' : ''}>${esc(block.note || '')}</textarea>`;

    const q = (sel) => card.querySelector(sel);
    const title = q('.block-title');
    if (title) title.addEventListener('change', () => blockCall(window.api.quotations.updateBlock(block.id, { title: title.value })));
    const prefix = q('.block-prefix');
    if (prefix) prefix.addEventListener('change', () => blockCall(window.api.quotations.updateBlock(block.id, { prefix: prefix.value })));
    const note = q('.block-note');
    note.addEventListener('change', () => blockCall(window.api.quotations.updateBlock(block.id, { note: note.value })));
    for (const b of card.querySelectorAll('[data-move]')) {
      b.addEventListener('click', () => blockCall(window.api.quotations.moveBlock(block.id, b.dataset.move === 'up')));
    }
    const remove = q('.block-remove');
    if (remove) remove.addEventListener('click', () => {
      const what = block.kind === 'Note' ? 'this note' : `the section "${block.title || 'untitled'}"${lines.length ? ` and its ${lines.length} row(s)` : ''}`;
      if (confirm(`Remove ${what}?`)) blockCall(window.api.quotations.removeBlock(block.id));
    });
    for (const tr of card.querySelectorAll('tr[data-id]')) {
      const lineId = tr.dataset.id;
      const field = (sel, key, parse) => {
        const el = tr.querySelector(sel);
        if (el) el.addEventListener('change', () => updateLine(lineId, { [key]: parse(el.value) }));
      };
      field('.row-desc', 'itemDescription', (v) => v);
      field('.row-unit', 'unit', (v) => v);
      field('.row-qty', 'quantity', (v) => Math.max(1, Math.round(Number(v) || 1)));
      field('.row-price', 'appliedUnitPrice', (v) => parseFloat(v) || 0);
      const rm = tr.querySelector('.row-remove');
      if (rm) rm.addEventListener('click', () => removeLine(lineId));
    }
    const addBtn = q('.add-row');
    if (addBtn) {
      const add = () => {
        const desc = q('.add-desc');
        if (!desc.value.trim()) { desc.focus(); return; }
        const qtyInput = q('.add-qty');
        blockCall(window.api.quotations.addBlockLine(block.id, {
          description: desc.value,
          unit: q('.add-unit').value,
          quantity: qtyInput ? Math.max(1, Math.round(Number(qtyInput.value) || 1)) : 1,
          price: Number(q('.add-price').value) || 0,
        }));
      };
      addBtn.addEventListener('click', add);
      for (const input of card.querySelectorAll('.extra-add-row input')) {
        input.addEventListener('keydown', (e) => { if (e.key === 'Enter') add(); });
      }
    }
    container.appendChild(card);
  });
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

// The Markup / Discount box: "+30%" marks every item up 30%, "-15%" is a
// 15% discount, "-1000" is a 1,000 discount, blank means neither.
function formatAdjustment(d) {
  if (d.markupPercent > 0) return `+${d.markupPercent}%`;
  if (d.discountType === 'Percent' && d.discountValue > 0) return `-${d.discountValue}%`;
  if (d.discountType === 'Fixed' && d.discountValue > 0) return `-${d.discountValue}`;
  return '';
}

function parseAdjustment(text) {
  const none = { markupPercent: null, discountType: 'None', discountValue: 0 };
  const cleaned = String(text || '').replace(/[\s,]/g, '').replace(/[−–]/g, '-');
  if (cleaned === '') return none;
  const m = cleaned.match(/^([+-]?)(\d+(?:\.\d+)?|\.\d+)(%?)$/);
  if (!m) return { error: 'Type a markup or discount such as +30%, -15% or -1000.' };
  const [, sign, digits, percent] = m;
  const value = Number(digits);
  if (value === 0) return none;
  if (percent) {
    if (sign === '-') {
      if (value > 100) return { error: 'A discount can’t be more than 100%.' };
      return { markupPercent: null, discountType: 'Percent', discountValue: value };
    }
    if (value > 1000) return { error: 'A markup can’t be more than 1000%.' };
    return { markupPercent: value, discountType: 'None', discountValue: 0 };
  }
  if (sign !== '-') {
    return { error: `An amount can only be taken off. Type -${digits} for a ${currencyLabel} ${money(value)} discount, or add % for a markup (e.g. +30%).` };
  }
  return { markupPercent: null, discountType: 'Fixed', discountValue: value };
}

async function saveHeader() {
  const adjustmentInput = document.getElementById('adjustment-input');
  const adjustment = parseAdjustment(adjustmentInput.value);
  if (adjustment.error) {
    alert(adjustment.error);
    adjustmentInput.value = formatAdjustment(currentDetail);
    return;
  }
  const header = {
    quotationDate: document.getElementById('doc-date-input').value || null,
    validUntil: document.getElementById('valid-until-input').value || null,
    paymentTerms: document.getElementById('payment-terms-input').value || null,
    notes: document.getElementById('notes-box').value || null,
    discountType: adjustment.discountType,
    discountValue: adjustment.discountValue,
    markupPercent: adjustment.markupPercent,
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
  window.attachParagraphFormatting(document.getElementById('payment-terms-input'));
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

  for (const fieldId of ['doc-date-input', 'valid-until-input', 'payment-terms-input', 'adjustment-input', 'tax-rate-input', 'notes-box']) {
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
  for (const [btn, kind] of [['add-priced-btn', 'Priced'], ['add-rates-btn', 'Rates'], ['add-note-btn', 'Note']]) {
    document.getElementById(btn).addEventListener('click', () => blockCall(window.api.quotations.addBlock(quotationId, kind)));
  }

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

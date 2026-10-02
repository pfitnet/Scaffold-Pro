'use strict';

// A line's Chinese name (from the material list), shown after its description.
function zhName(item) {
  const zh = currentDetail && currentDetail.chineseNames && currentDetail.chineseNames[item.id];
  return zh ? ` <span class="zh-name">${String(zh).replace(/&/g, '&amp;').replace(/</g, '&lt;')}</span>` : '';
}

let boqId = null;
let currentDetail = null;
// "× Multiply…" (js/multiply.js): the items' quantities ×2 for 2 sets, etc.
const multiply = window.multiplyLines.attach({
  button: document.getElementById('multiply-btn'),
  kind: 'boq',
  detail: () => currentDetail,
  reload: () => loadDetail(),
});
// "HK$" for HKD (from Settings), as on the documents.
let currencyLabel = 'HK$';

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
  renderLinkedBar();
  window.docLanguage.show(currentDetail);
  window.deliverySchedule.refresh(currentDetail);
}

// The quotations kept the same as this BOQ: a change to either is made to
// the other (while both are Drafts), until the link is removed.
function renderLinkedBar() {
  const bar = document.getElementById('linked-bar');
  const list = currentDetail.linkedQuotations || [];
  bar.classList.toggle('hidden', !list.length);
  if (!list.length) return;
  const e = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
  bar.innerHTML = `<strong>Linked</strong> with ${list.map((q) => `<span class="linked-doc"><a href="quotation-editor.html?id=${encodeURIComponent(q.id)}">${e(q.number)}</a>${q.status !== 'Draft' ? ` <span class="muted">(${e(q.status.toLowerCase())} — not changed)</span>` : ''}
    <button data-unlink="${e(q.id)}" data-number="${e(q.number)}" title="Stop keeping ${e(q.number)} the same as this BOQ">Remove Link</button></span>`).join(', ')}
    — a change here is made there too, and the other way round.`;
  for (const b of bar.querySelectorAll('[data-unlink]')) {
    b.addEventListener('click', async () => {
      if (!await appConfirm(`Remove the link between this BOQ and ${b.dataset.number}?\n\nBoth stay as they are now; after this, changing one no longer changes the other.`)) return;
      const r = await window.api.quotations.unlinkBOQ(b.dataset.unlink);
      if (r && r.ok === false) { alert(r.error); return; }
      await loadDetail();
    });
  }
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
  // The mark-up is applied to the rates shown (list prices stay as they
  // are) and becomes the markup % of a quotation made from this BOQ.
  const markupNote = document.getElementById('boq-markup-note');
  const m = Number(d.markupPercent) || 0;
  markupNote.classList.toggle('hidden', !m || !d.markupOnRates);
  markupNote.textContent = !m ? '' : m > 0
    ? `Unit rates include the ${m}% mark-up, each rounded ${d.markupRoundUp ? 'up to the next' : 'off to the nearest'} 0.1. A quotation made from this BOQ takes ${m}% as its markup.`
    : `Unit rates include the ${-m}% mark-down, each rounded ${d.markupRoundUp ? 'up to the next' : 'off to the nearest'} 0.1.`;
  // The client's default markup: said when it's in use, offered when not.
  const clientMarkup = document.getElementById('boq-client-markup');
  const cm = Number(d.clientMarkupPercent) || 0;
  clientMarkup.classList.toggle('hidden', !cm);
  if (cm) {
    const who = d.clientName ? `${d.clientName}’s` : 'The client’s';
    clientMarkup.innerHTML = cm === m
      ? `${escAttr(who)} default markup (${cm}%) is in use.`
      : `${escAttr(who)} default markup is ${cm}%.${locked ? '' : ` <button type="button" class="link-btn" id="use-client-markup-btn">Use ${cm}%</button>`}`;
    const use = document.getElementById('use-client-markup-btn');
    if (use) use.addEventListener('click', () => {
      markup.value = cm;
      markup.dispatchEvent(new Event('change'));
    });
  }
  const structure = document.getElementById('boq-structure-input');
  if (document.activeElement !== structure) structure.value = d.structure || '';
  structure.disabled = locked;

  // Landscape (with prices) or portrait (no prices) — can be changed any time.
  document.getElementById('orientation-select').value = d.orientation || 'Landscape';

  const statusSelect = document.getElementById('status-select');
  statusSelect.value = d.status;
  document.getElementById('custom-item-box').classList.toggle('hidden', d.status !== 'Draft');

  const isIssued = d.status === 'Issued';
  renderLineItems();
  renderCharges();
  renderRates();

  const notesBox = document.getElementById('notes-box');
  if (document.activeElement !== notesBox) {
    notesBox.value = d.notes || '';
  }

  // Terms and signature boxes: only on the landscape sheet.
  document.getElementById('sheet-extras').classList.toggle('hidden', (d.orientation || 'Landscape') !== 'Landscape');
  const termsBox = document.getElementById('terms-box');
  if (document.activeElement !== termsBox) termsBox.value = d.terms || '';
  document.getElementById('signature-check').checked = !!d.signatureSection;
  const standardBtn = document.getElementById('standard-terms-btn');
  standardBtn.disabled = isIssued;
  standardBtn.title = 'Put in the standard terms (change them in Settings › BOQ Defaults)';
  termsBox.disabled = isIssued;
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
  multiply.update();
  const container = document.getElementById('line-items');
  const items = currentDetail.lineItems;
  const isIssued = currentDetail.status === 'Issued';
  const sort = document.getElementById('line-sort');
  sort.value = currentDetail.lineSort || 'code';
  sort.disabled = isIssued;

  if (items.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>No line items yet</h2><p>Add materials from the list on the left.</p></div>`;
    document.getElementById('grand-total').textContent = '';
    return;
  }

  const table = document.createElement('table');
  table.innerHTML = `
    <thead>
      <tr><th class="drag-col"></th><th class="num row-no">No.</th><th>Description</th><th>Unit</th><th class="num">Qty</th><th class="num">Unit Rate</th><th></th><th class="num">Unit Wt (kg)</th><th class="num">Total Wt (kg)</th><th></th></tr>
    </thead>
    <tbody></tbody>`;
  const tbody = table.querySelector('tbody');

  for (const [index, item] of items.entries()) {
    const hasWeight = item.weightKg !== null && item.weightKg !== undefined;
    // The rate after any discount; the discount itself isn't printed.
    const rate = currentDetail.effectiveRates[item.id] ?? item.appliedUnitPrice;
    const dv = Number(item.discountValue) || 0;
    const discountLabel = item.discountType === 'Percent' && dv > 0 ? `−${dv}%`
      : item.discountType === 'Amount' && dv > 0 ? `−${money(dv)}` : '';
    const lineWeight = hasWeight ? item.weightKg * item.quantity : null;

    const tr = document.createElement('tr');
    tr.dataset.id = item.id;
    tr.innerHTML = `
      <td class="drag-col">${isIssued || items.length < 2 ? '' : window.dragHandleHTML('Drag to move this line (or focus and press ↑ / ↓)')}</td>
      <td class="num row-no">${index + 1}</td>
      <td>${item.itemDescription}${zhName(item)}
        ${isIssued
          ? (item.notes ? `<div class="line-note">${item.notes}</div>` : '')
          : `<input type="text" class="line-note-input" placeholder="Add a note" value="${(item.notes || '').replace(/"/g, '&quot;')}" />`}</td>
      <td>${item.unit}</td>
      <td class="num"><input type="number" class="qty-input" min="1" step="1" value="${Math.round(item.quantity)}" ${isIssued ? 'disabled' : ''} /></td>
      <td class="num">${money(rate)}</td>
      <td>${isIssued ? '' : window.discountButtonHTML(discountLabel, "Discount this item's rate (only the new rate is printed)")}</td>
      <td class="num">${weight(item.weightKg)}</td>
      <td class="num">${weight(lineWeight)}</td>
      <td class="row-actions">${isIssued ? '' : `
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
    const dup = tr.querySelector('.dup-btn');
    if (dup) dup.addEventListener('click', () => lineAction(() => window.api.boq.duplicateLineItem(item.id)));
    const discountBtn = tr.querySelector('.discount-btn');
    if (discountBtn) discountBtn.addEventListener('click', () => {
      window.openLineDiscount(item, currencyLabel, async (type, value) => {
        const r = await window.api.boq.updateLineDiscount(item.id, type, value);
        if (r.ok) await loadDetail();
        return r;
      }, { perUnit: true });
    });
    const note = tr.querySelector('.line-note-input');
    if (note) note.addEventListener('change', async () => {
      const r = await window.api.boq.updateLineNotes(item.id, note.value);
      if (!r.ok) alert(r.error);
    });

    tbody.appendChild(tr);
  }

  // Drag a line by its handle to move it.
  if (!isIssued) {
    window.makeReorderable(tbody, {
      item: 'tr',
      onReorder: async (ids) => {
        const r = await window.api.boq.reorderLineItems(boqId, ids);
        if (!r.ok) alert(r.error);
        await loadDetail();
      },
    });
  }

  container.innerHTML = '';
  container.appendChild(table);
  const d = currentDetail;
  document.getElementById('grand-total').textContent = d.charges
    ? `Subtotal: ${currencyLabel} ${money(d.grandTotal)} · Total: ${currencyLabel} ${money(d.totalAmount)} · Total Weight: ${weight(d.totalWeightKg)} kg`
    : `${d.ratesSection ? 'Subtotal' : 'Total'}: ${currencyLabel} ${money(d.grandTotal)} · Total Weight: ${weight(d.totalWeightKg)} kg`;
}

// ---------- Amounts added after the subtotal (landscape BQ sheet) ----------
// Items not priced by unit (delivery, design fees…): D1, D2… under
// "Subtotal Amount", added to the "Total Amount".

async function saveCharges(charges) {
  const r = await window.api.boq.setCharges(boqId, charges);
  if (!r.ok) alert(r.error);
  await loadDetail();
}

function renderCharges() {
  const box = document.getElementById('boq-charges');
  const d = currentDetail;
  const locked = d.status !== 'Draft';
  const charges = d.charges;
  if (!charges) {
    box.innerHTML = `<h3>Added to the total</h3>
      <p class="small-note">For the landscape BQ: items not priced by unit, such as Delivery or Design Fees, listed after the “Subtotal Amount” and added to the “Total Amount”.</p>
      ${locked ? '' : '<div class="actions-row"><button id="charges-add-section-btn">+ Section</button></div>'}`;
    if (!locked) {
      box.querySelector('#charges-add-section-btn').addEventListener('click', () =>
        saveCharges([{ code: '', name: 'Delivery', amount: 0 }]));
    }
    return;
  }
  const dis = locked ? 'disabled' : '';
  box.innerHTML = `<h3>Added to the total</h3>
    <table class="compact">
      <thead><tr><th class="row-no">No.</th><th>Item</th><th class="num">Amount (${currencyLabel})</th><th></th></tr></thead>
      <tbody>${charges.map((c, i) => `
        <tr data-i="${i}">
          <td><input type="text" class="c-code narrow" value="${escAttr(c.code || '')}" placeholder="D${i + 1}" ${dis} /></td>
          <td><input type="text" class="c-name" value="${escAttr(c.name)}" placeholder="e.g. Delivery, Design Fees" ${dis} /></td>
          <td class="num"><input type="number" class="c-amount" step="0.01" value="${c.amount}" ${dis} style="width:120px" /></td>
          <td>${locked ? '' : '<button class="c-remove">Remove</button>'}</td>
        </tr>`).join('')}</tbody>
      <tfoot><tr><td></td><td style="text-align:right">Total Amount</td><td class="num">${money(d.totalAmount)}</td><td></td></tr></tfoot>
    </table>
    ${locked ? '' : `<div class="actions-row">
      <button id="charges-add-btn">Add Row</button>
      <button id="charges-remove-btn">Remove Section</button>
    </div>`}`;
  if (locked) return;
  const read = () => [...box.querySelectorAll('tr[data-i]')].map((tr) => ({
    code: tr.querySelector('.c-code').value.trim(),
    name: tr.querySelector('.c-name').value,
    amount: Number(tr.querySelector('.c-amount').value) || 0,
  }));
  for (const el of box.querySelectorAll('input')) el.addEventListener('change', () => saveCharges(read()));
  for (const b of box.querySelectorAll('.c-remove')) {
    b.addEventListener('click', () => {
      const list = read();
      list.splice(Number(b.closest('tr').dataset.i), 1);
      saveCharges(list);
    });
  }
  box.querySelector('#charges-add-btn').addEventListener('click', () => saveCharges([...read(), { code: '', name: '', amount: 0 }]));
  box.querySelector('#charges-remove-btn').addEventListener('click', async () => {
    if (await appConfirm('Remove this section? Its amounts will no longer be added to the total.')) saveCharges(null);
  });
}

// ---------- Rates after the total (landscape BQ sheet) ----------

function escAttr(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
}

async function saveRates(section) {
  const r = await window.api.boq.setRatesSection(boqId, section);
  if (!r.ok) alert(r.error);
  await loadDetail();
}

function renderRates() {
  const box = document.getElementById('boq-rates');
  const d = currentDetail;
  const locked = d.status !== 'Draft';
  const s = d.ratesSection;
  if (!s) {
    box.innerHTML = `<h3>Rates after the total</h3>
      <p class="small-note">For the landscape BQ: rates listed after the total, which then reads “Subtotal”.</p>
      ${locked ? '' : `<div class="actions-row">
        <button id="rates-standard-btn">+ Standard Manpower Rates</button>
      </div>`}`;
    if (!locked) {
      box.querySelector('#rates-standard-btn').addEventListener('click', async () => {
        const standard = await window.api.boq.standardRates();
        saveRates({ title: 'Erection & Dismantle Manpower Rates', rates: standard, note: STANDARD_RATES_NOTE });
      });
    }
    return;
  }
  const dis = locked ? 'disabled' : '';
  box.innerHTML = `<h3>Rates after the total</h3>
    <input type="text" id="rates-title" value="${escAttr(s.title)}" placeholder="Title, e.g. Erection & Dismantle Manpower Rates" ${dis} style="width:100%; box-sizing:border-box; font-weight:600" />
    <table class="compact" style="margin-top:8px">
      <thead><tr><th class="num row-no">No.</th><th>Worker / item</th><th class="num">Rate (${currencyLabel})</th><th>Per</th><th></th></tr></thead>
      <tbody>${s.rates.map((r, i) => `
        <tr data-i="${i}">
          <td class="num row-no">R${i + 1}</td>
          <td><input type="text" class="r-name" value="${escAttr(r.name)}" ${dis} /></td>
          <td class="num"><input type="number" class="r-rate narrow" min="0" step="0.01" value="${r.rate}" ${dis} /></td>
          <td><input type="text" class="r-unit narrow" value="${escAttr(r.unit)}" ${dis} /></td>
          <td>${locked ? '' : '<button class="r-remove">Remove</button>'}</td>
        </tr>`).join('')}</tbody>
    </table>
    <textarea id="rates-note" rows="2" placeholder="Note under the rates (optional)" ${dis}>${escAttr(s.note || '')}</textarea>
    ${locked ? '' : `<div class="actions-row">
      <button id="rates-add-btn">Add Row</button>
      <button id="rates-fill-btn" title="Add the standard rates (Settings › Standard Quotation); workers already listed are skipped">Fill Standard Rates</button>
      <button id="rates-remove-btn">Remove Section</button>
    </div>`}`;
  if (locked) return;
  const read = () => ({
    title: box.querySelector('#rates-title').value,
    note: box.querySelector('#rates-note').value,
    rates: [...box.querySelectorAll('tr[data-i]')].map((tr) => ({
      name: tr.querySelector('.r-name').value,
      rate: Number(tr.querySelector('.r-rate').value) || 0,
      unit: tr.querySelector('.r-unit').value || 'md',
    })),
  });
  for (const el of box.querySelectorAll('input, textarea')) el.addEventListener('change', () => saveRates(read()));
  for (const b of box.querySelectorAll('.r-remove')) {
    b.addEventListener('click', () => {
      const section = read();
      section.rates.splice(Number(b.closest('tr').dataset.i), 1);
      saveRates(section);
    });
  }
  box.querySelector('#rates-add-btn').addEventListener('click', () => {
    const section = read();
    section.rates.push({ name: '', rate: 0, unit: 'md' });
    saveRates(section);
  });
  box.querySelector('#rates-fill-btn').addEventListener('click', async () => {
    const section = read();
    const have = new Set(section.rates.map((r) => r.name.trim().toLowerCase()));
    for (const r of await window.api.boq.standardRates()) {
      if (!have.has(r.name.trim().toLowerCase())) section.rates.push(r);
    }
    saveRates(section);
  });
  box.querySelector('#rates-remove-btn').addEventListener('click', async () => {
    if (await appConfirm('Remove the rates section? The total will read “Total Amount” again.')) saveRates(null);
  });
}

const STANDARD_RATES_NOTE = '* Please note that labour rates are subject to a price increase for over-time works and works on sundays / public holidays';

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
  const items = await window.pickerSearch({ sourceKey, query, category: category || null, inBaseCurrency: true });
  if (!items) return; // a newer search is on its way

  const container = document.getElementById('picker-results');
  if (items.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>No items match</h2></div>`;
    return;
  }

  // A box per category (Base Items, Standards (with Spigots), …).
  window.renderPickerGroups(container, items, '<th>Item</th><th class="num">Weight (kg)</th><th></th>', (item) => {
    const price = priceForMode(item, currentDetail.pricingMode);
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${item.itemName}</td>
      <td class="num">${weight(item.weightKg)}</td>
      <td><button class="add-btn" ${currentDetail.status === 'Issued' ? 'disabled' : ''}>+ Add</button></td>`;
    tr.querySelector('.add-btn').addEventListener('click', () => addFromPicker(item, price));
    return tr;
  });
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
  // Item names on the PDF in English or Chinese.
  window.docLanguage.init((language) => window.api.boq.setLanguage(boqId, language));
  window.setupDocumentActions('BOQ', () => ({
    id: boqId, number: currentDetail ? currentDetail.boqNumber : '', status: currentDetail ? currentDetail.status : 'Draft',
    projectNumber: currentDetail ? currentDetail.projectNumber : '',
  }));
  boqId = getBOQIdFromURL();
  if (!boqId) {
    document.getElementById('not-found').classList.remove('hidden');
    return;
  }
  const settings = await window.api.settings.get();
  currencyLabel = settings.currency === 'HKD' ? 'HK$' : settings.currency;
  window.deliverySchedule.setup(boqId, 'boq');
  // Sorted by item code unless changed; dragging a line makes it "As arranged".
  document.getElementById('line-sort').addEventListener('change', async (e) => {
    const r = await window.api.boq.setLineSort(boqId, e.target.value);
    if (r && r.ok === false) alert(r.error);
    await loadDetail();
  });

  await loadDetail();
  if (!currentDetail) return;
  window.setupLinkedDrawings({ kind: 'BOQ', id: boqId, projectNumber: currentDetail.projectNumber });

  document.getElementById('status-select').addEventListener('change', async (e) => {
    if (currentDetail.status === 'Issued' && e.target.value === 'Draft' &&
        !await appConfirm('Return this BOQ to Draft?\n\nIt has already been issued; its items become editable again.')) {
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
  document.getElementById('terms-box').addEventListener('change', async (e) => {
    const r = await window.api.boq.updateSheetExtras(boqId, { terms: e.target.value });
    if (r && !r.ok) alert(r.error);
    currentDetail.terms = e.target.value;
  });
  document.getElementById('signature-check').addEventListener('change', async (e) => {
    const r = await window.api.boq.updateSheetExtras(boqId, { signatureSection: e.target.checked });
    if (r && !r.ok) alert(r.error);
    currentDetail.signatureSection = e.target.checked;
  });
  document.getElementById('standard-terms-btn').addEventListener('click', async () => {
    const box = document.getElementById('terms-box');
    const standard = currentDetail.standardTerms || '';
    if (!standard) return;
    if (box.value.trim() && box.value.trim() !== standard.trim() &&
        !await appConfirm('Replace this BOQ’s terms with the standard terms from Settings?')) return;
    box.value = standard;
    box.dispatchEvent(new Event('change'));
  });

  // BOQ settings: switching Sale/Rental or the mark-up re-prices the lines.
  document.getElementById('boq-mode-select').addEventListener('change', async (e) => {
    const to = e.target.value;
    if (currentDetail.lineItems.length > 0 &&
        !await appConfirm(`Change this BOQ to ${to} pricing?\n\nEvery item from the material list will be re-priced at its ${to.toLowerCase()} price (with this BOQ's mark-up). Prices you typed in by hand are kept. Weights don't change.`)) {
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

  document.getElementById('orientation-select').addEventListener('change', async (e) => {
    const result = await window.api.boq.setOrientation(boqId, e.target.value);
    if (!result.ok) alert(result.error);
    await loadDetail();
  });

  document.getElementById('export-pdf-btn').addEventListener('click', async () => {
    const result = await window.api.boq.exportPDF(boqId);
    if (!result.ok) { alert(result.error); }
  });

  document.getElementById('export-word-btn').addEventListener('click', async (e) => {
    e.target.disabled = true;
    try {
      const result = await window.exportWord(() => window.api.boq.exportWord(boqId));
      if (!result.ok) { alert(result.error); }
    } catch (err) {
      alert(`The Word document couldn't be made.\n\n${err.message}`);
    } finally {
      e.target.disabled = false;
    }
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

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

let deliveryNoteId = null;
let currentDetail = null;

function getIdFromURL() {
  const params = new URLSearchParams(location.search);
  return params.get('id');
}

// An ISO timestamp → "yyyy-mm-dd" in local time, for a date field.
function localDay(iso) {
  const d = new Date(iso || '');
  if (isNaN(d)) return '';
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
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
  lockStatusOptions(document.getElementById('status-select'), d.status, false);
  document.getElementById('custom-item-box').classList.toggle('hidden', d.status !== 'Draft');
  const isLocked = d.status !== 'Draft';

  const docDateInput = document.getElementById('doc-date-input');
  if (document.activeElement !== docDateInput) docDateInput.value = localDay(d.deliveryDate);
  docDateInput.disabled = isLocked;

  const addressInput = document.getElementById('delivery-address-input');
  if (document.activeElement !== addressInput) addressInput.value = d.deliveryAddress || '';
  addressInput.disabled = isLocked;

  const contactInput = document.getElementById('contact-person-input');
  if (document.activeElement !== contactInput) contactInput.value = d.contactPerson || '';
  contactInput.disabled = isLocked;

  const deliveredByInput = document.getElementById('delivered-by-input');
  if (document.activeElement !== deliveredByInput) deliveredByInput.value = d.deliveredBy || '';
  deliveredByInput.disabled = isLocked;

  const receivedByInput = document.getElementById('received-by-input');
  if (document.activeElement !== receivedByInput) receivedByInput.value = d.receivedBy || '';
  receivedByInput.disabled = isLocked;

  const notesBox = document.getElementById('notes-box');
  if (document.activeElement !== notesBox) notesBox.value = d.notes || '';
  notesBox.disabled = isLocked;

  document.getElementById('quotation-import').classList.toggle('hidden', isLocked);
  renderLineItems();
}

// "Import from Quotation": the project's quotations (not cancelled ones),
// newest first, with the one this note was made from chosen to start with.
let projectQuotations = [];

async function loadQuotationChoices() {
  const select = document.getElementById('quotation-import-select');
  const button = document.getElementById('import-quotation-btn');
  const note = document.getElementById('quotation-import-note');
  const all = currentDetail.projectId ? await window.api.quotations.listForProject(currentDetail.projectId) : [];
  projectQuotations = (all || []).filter((q) => q.status !== 'Cancelled')
    .sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
  const escapeHTML = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  select.innerHTML = projectQuotations.map((q) => {
    const subject = q.subject ? ` — ${q.subject.length > 60 ? `${q.subject.slice(0, 60)}…` : q.subject}` : '';
    return `<option value="${escapeHTML(q.id)}">${escapeHTML(q.quotationNumber)}${escapeHTML(subject)} (${escapeHTML(q.status)})</option>`;
  }).join('');
  if (projectQuotations.some((q) => q.id === currentDetail.sourceQuotationId)) select.value = currentDetail.sourceQuotationId;
  select.disabled = button.disabled = projectQuotations.length === 0;
  if (projectQuotations.length === 0) {
    select.innerHTML = '<option value="">No quotations in this project</option>';
    note.textContent = '';
  } else {
    note.textContent = 'Copies the quotation’s materials (not delivery or other charges). Items already here get the quantity added.';
  }
}

async function importFromQuotation() {
  const quotationId = document.getElementById('quotation-import-select').value;
  if (!quotationId) return;
  let replaceExisting = false;
  if (currentDetail.lineItems.length > 0) {
    replaceExisting = confirm(
      'This delivery note already has items.\n\nOK = replace them with the quotation\'s materials\nCancel = add the quotation\'s quantities to the existing items');
  }
  const result = await window.api.deliveryNotes.importQuotation(deliveryNoteId, quotationId, replaceExisting);
  if (!result || !result.ok) { alert((result && result.error) || 'The quotation couldn’t be imported.'); return; }
  await loadDetail();
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
    deliveryDate: document.getElementById('doc-date-input').value || null,
    deliveryAddress: document.getElementById('delivery-address-input').value || null,
    contactPerson: document.getElementById('contact-person-input').value || null,
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
  const items = await window.pickerSearch({ sourceKey, query, category: category || null });
  if (!items) return; // a newer search is on its way

  const container = document.getElementById('picker-results');
  if (items.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>No items match</h2></div>`;
    return;
  }

  // A box per category (Base Items, Standards (with Spigots), …).
  window.renderPickerGroups(container, items, '<th>Item</th><th></th>', (item) => {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${item.itemName}</td>
      <td><button class="add-btn" ${currentDetail.status !== 'Draft' ? 'disabled' : ''}>+ Add</button></td>`;
    tr.querySelector('.add-btn').addEventListener('click', () => addFromPicker(item));
    return tr;
  });
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
  window.setupDocumentActions('DeliveryNote', () => ({
    id: deliveryNoteId, number: currentDetail ? currentDetail.deliveryNoteNumber : '', status: currentDetail ? currentDetail.status : 'Draft',
    projectNumber: currentDetail ? currentDetail.projectNumber : '',
  }));
  deliveryNoteId = getIdFromURL();
  if (!deliveryNoteId) {
    document.getElementById('not-found').classList.remove('hidden');
    return;
  }

  await loadDetail();
  if (!currentDetail) return;
  await loadQuotationChoices();
  document.getElementById('import-quotation-btn').addEventListener('click', importFromQuotation);

  document.getElementById('status-select').addEventListener('change', async (e) => {
    if (!allowStatusChange(currentDetail.status, e.target.value, 'delivery note')) {
      e.target.value = currentDetail.status;
      return;
    }
    const result = await window.api.deliveryNotes.updateStatus(deliveryNoteId, e.target.value);
    if (!result.ok) { alert(result.error); }
    await loadDetail();
  });

  for (const fieldId of ['doc-date-input', 'delivery-address-input', 'contact-person-input', 'delivered-by-input', 'received-by-input', 'notes-box']) {
    document.getElementById(fieldId).addEventListener('change', saveHeader);
  }

  document.getElementById('export-pdf-btn').addEventListener('click', async () => {
    const result = await window.api.deliveryNotes.exportPDF(deliveryNoteId);
    if (!result.ok) { alert(result.error); }
  });

  document.getElementById('export-word-btn').addEventListener('click', async (e) => {
    e.target.disabled = true;
    try {
      const result = await window.exportWord(() => window.api.deliveryNotes.exportWord(deliveryNoteId));
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

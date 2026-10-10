'use strict';

const STATUSES = ['Planning', 'Quotation', 'Active', 'On Hold', 'Completed', 'Archived'];
const DOCUMENT_CATEGORIES = ['Contracts', 'Specifications', 'Correspondence', 'Certificates', 'Client Documents', 'Site Information', 'Miscellaneous'];
let currentProject = null;
let currentBOQs = [];
let currentQuotations = [];
let currentInvoices = [];
let currentDeliveryNotes = [];

// "Select" on each list: tick several, then Export PDF (one PDF) or Locate Files.
const selections = {
  boq: window.createDocumentSelection({
    kind: 'BOQ', noun: 'BOQ', plural: 'BOQs', drawings: true, drawingsLabel: 'Include each BOQ\u2019s drawings after it',
    combine: { label: 'Combine into One BOQ', title: 'A new BOQ with the chosen BOQs\u2019 quantities added together',
      run: (ids) => window.api.boq.combine(ids), open: (id) => { location.href = `boq-editor.html?id=${encodeURIComponent(id)}`; } },
    toolbar: document.getElementById('boq-actions'), container: document.getElementById('boq-list'),
    order: () => currentBOQs.map((b) => b.id), numberOf: (id) => (currentBOQs.find((b) => b.id === id) || {}).boqNumber,
  }),
  quotation: window.createDocumentSelection({
    kind: 'Quotation', noun: 'quotation', drawings: true, drawingsLabel: 'Include each quotation\u2019s drawings (and the BOQ it follows) after it',
    toolbar: document.getElementById('quotation-actions'), container: document.getElementById('quotation-list'),
    order: () => currentQuotations.map((q) => q.id), numberOf: (id) => (currentQuotations.find((q) => q.id === id) || {}).quotationNumber,
  }),
  invoice: window.createDocumentSelection({
    kind: 'Invoice', noun: 'invoice',
    toolbar: document.getElementById('invoice-actions'), container: document.getElementById('invoice-list'),
    order: () => currentInvoices.map((i) => i.id), numberOf: (id) => (currentInvoices.find((i) => i.id === id) || {}).invoiceNumber,
  }),
  delivery: window.createDocumentSelection({
    kind: 'DeliveryNote', noun: 'delivery note',
    combine: { label: 'Combine into One Delivery Note', title: 'A new delivery note with the chosen notes\u2019 quantities added together',
      run: (ids) => window.api.deliveryNotes.combine(ids), open: (id) => { location.href = `delivery-note-editor.html?id=${encodeURIComponent(id)}`; } },
    toolbar: document.getElementById('delivery-actions'), container: document.getElementById('delivery-note-list'),
    order: () => currentDeliveryNotes.map((d) => d.id), numberOf: (id) => (currentDeliveryNotes.find((d) => d.id === id) || {}).deliveryNoteNumber,
  }),
};

function getProjectNumberFromURL() {
  const params = new URLSearchParams(location.search);
  return params.get('number');
}

// "1,234.56" format everywhere (not "1234.56").
function money(value) {
  return Number(value || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

// Quantities are whole numbers: "1,250".
function qty(value) {
  return Math.round(Number(value || 0)).toLocaleString('en-US', { maximumFractionDigits: 0 });
}

function formatFileSize(bytes) {
  if (!bytes) return '0 KB';
  const kb = bytes / 1024;
  if (kb < 1024) return `${kb.toFixed(0)} KB`;
  return `${(kb / 1024).toFixed(1)} MB`;
}

async function refreshBOQList() {
  currentBOQs = await window.api.boq.listForProject(currentProject.id);
  setCount('boq', currentBOQs.length);
  const container = document.getElementById('boq-list');

  if (currentBOQs.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <h2>No BOQs yet</h2>
        <p>Create a Bill of Quantities for this project.</p>
      </div>`;
    return;
  }

  // Project total weight: every BOQ except cancelled ones and combined
  // counts (those add up other BOQs, so they're listed apart, below it).
  const own = currentBOQs.filter((b) => !b.combined);
  const combined = currentBOQs.filter((b) => b.combined);
  const counted = own.filter((b) => b.status !== 'Cancelled');
  const totalWeight = counted.reduce((sum, b) => sum + (Number(b.totalWeightKg) || 0), 0);
  const table = document.createElement('table');
  table.innerHTML = `
    <thead><tr>${selections.boq.headerCell()}<th>Number</th><th>Pricing</th><th>Status</th><th>Created By</th><th>Items</th><th class="num">Total Weight (kg)</th><th></th></tr></thead>
    <tbody></tbody>
    <tbody class="total-rows"><tr class="project-total">${selections.boq.footerCell()}<td colspan="5">Project total weight${counted.length < own.length ? ' <span class="muted">(cancelled BOQs not counted)</span>' : ''}</td>
      <td class="num">${money(totalWeight)}</td><td></td></tr></tbody>
    ${combined.length ? `<tbody class="combined-rows"><tr class="combined-head"><td colspan="8">Combined counts <span class="muted">— made by adding up BOQs above; not added to the project total</span></td></tr></tbody>` : ''}`;
  const tbody = table.querySelector('tbody');
  const combinedBody = table.querySelector('tbody.combined-rows');
  for (const b of own.concat(combined)) {
    const tr = document.createElement('tr');
    tr.style.cursor = 'pointer';
    tr.onclick = () => { location.href = `boq-editor.html?id=${b.id}`; };
    tr.dataset.id = b.id;
    tr.innerHTML = `${selections.boq.cell(b.id)}
      <td>${esc(b.boqNumber)}${b.structure ? `<div class="sub">${esc(b.structure)}</div>` : ''}${b.combined && b.combinedFrom ? `<div class="sub">Combined from ${esc(b.combinedFrom.join(', '))}</div>` : ''}</td>
      <td>${b.pricingMode}</td>
      <td><span class="status-pill">${b.status}</span></td>
      ${window.createdByCell(b)}
      <td>${b.itemCount}</td>
      <td class="num">${money(b.totalWeightKg)}</td>`;
    tr.appendChild(window.documentRowActions('BOQ', { id: b.id, number: b.boqNumber, status: b.status }, refreshBOQList));
    if (b.combined) tr.classList.add('combined-row');
    (b.combined ? combinedBody : tbody).appendChild(tr);
  }
  container.innerHTML = '';
  container.appendChild(table);
  selections.boq.afterRender();
}

// Sections charged per day / week, under the one-time charge: "+ 500.00 per week".
function recurringNote(recurring) {
  const parts = Object.entries(recurring || {}).filter(([, v]) => v).map(([k, v]) => `+ ${money(v)} per ${k.toLowerCase()}`);
  return parts.length ? `<div class="sub">${parts.join('<br>')}</div>` : '';
}

async function refreshQuotationList() {
  currentQuotations = await window.api.quotations.listForProject(currentProject.id);
  setCount('quotations', currentQuotations.length);
  const container = document.getElementById('quotation-list');

  if (currentQuotations.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <h2>No quotations yet</h2>
        <p>Create a quotation for this project.</p>
      </div>`;
    return;
  }

  // Project total: every quotation except cancelled ones, split into the
  // monthly charge (rental) and the one-time charge (delivery and one-off
  // charges; all of a Sale quotation).
  // Quotations for combined counts are listed apart, below the total.
  const own = currentQuotations.filter((q) => !q.fromCombined);
  const combined = currentQuotations.filter((q) => q.fromCombined);
  const counted = own.filter((q) => q.status !== 'Cancelled');
  const split = (q) => q.charges || { monthly: 0, oneTime: Number(q.total) || 0, recurring: {} };
  const monthlyTotal = counted.reduce((sum, q) => sum + (Number(split(q).monthly) || 0), 0);
  const oneTimeTotal = counted.reduce((sum, q) => sum + (Number(split(q).oneTime) || 0), 0);
  const recurringTotal = {};
  for (const q of counted) for (const [k, v] of Object.entries(split(q).recurring || {})) recurringTotal[k] = (recurringTotal[k] || 0) + v;
  const table = document.createElement('table');
  table.innerHTML = `
    <thead><tr>${selections.quotation.headerCell()}<th>Number</th><th>BOQ</th><th>Status</th><th>Created By</th><th>Items</th><th class="num" title="Monthly rental (and anything charged per month)">Monthly Charge</th><th class="num" title="Delivery and one-off charges — all of a Sale quotation">One-time Charge</th><th></th></tr></thead>
    <tbody></tbody>
    <tbody class="total-rows"><tr class="project-total">${selections.quotation.footerCell()}<td colspan="5">Project total${counted.length < own.length ? ' <span class="muted">(cancelled quotations not counted)</span>' : ''}</td>
      <td class="num">${monthlyTotal ? `${money(monthlyTotal)}<div class="sub">per month</div>` : '<span class="muted">—</span>'}</td>
      <td class="num">${money(oneTimeTotal)}${recurringNote(recurringTotal)}</td><td></td></tr></tbody>
    ${combined.length ? `<tbody class="combined-rows"><tr class="combined-head"><td colspan="9">For combined counts <span class="muted">— quotations of combined BOQs; not added to the project total</span></td></tr></tbody>` : ''}`;
  const tbody = table.querySelector('tbody');
  const combinedBody = table.querySelector('tbody.combined-rows');
  // A quotation split off another is listed under it, as its subsidiary.
  const ordered = [];
  const withChildren = (q, depth) => {
    ordered.push([q, depth]);
    for (const c of currentQuotations.filter((x) => x.parentId === q.id && x.id !== q.id).sort((a, b) => a.quotationNumber.localeCompare(b.quotationNumber))) {
      if (!ordered.some(([o]) => o.id === c.id)) withChildren(c, depth + 1);
    }
  };
  const listed = (q) => q.parentId && currentQuotations.some((x) => x.id === q.parentId && x.fromCombined === q.fromCombined);
  for (const q of own.concat(combined)) if (!listed(q)) withChildren(q, 0);
  for (const [q, depth] of ordered) {
    const tr = document.createElement('tr');
    tr.style.cursor = 'pointer';
    tr.onclick = () => { location.href = `quotation-editor.html?id=${q.id}`; };
    tr.dataset.id = q.id;
    // Under the number: the structure of the BOQ it follows, else its subject line.
    const sub = q.structure || q.subject;
    const splitFrom = depth ? `<div class="sub split-from">Split from ${esc(q.parentNumber)}</div>` : '';
    tr.innerHTML = `${selections.quotation.cell(q.id)}
      <td${depth ? ` class="subsidiary" style="--depth:${depth}"` : ''}>${esc(q.quotationNumber)}${sub ? `<div class="sub">${esc(sub)}</div>` : ''}${splitFrom}</td>
      <td>${q.boqNumber ? `${esc(q.boqNumber)}${q.boqLinked ? ' <span class="status-pill pill-success" title="Kept the same as the BOQ, both ways">Linked</span>' : ''}` : '<span class="muted">—</span>'}</td>
      <td><span class="status-pill">${q.status}</span>${q.signed ? ' <span class="status-pill pill-success" title="The client’s signed copy is with the quotation in the project’s folder">Signed</span>' : ''}</td>
      ${window.createdByCell(q)}
      <td>${q.itemCount}</td>
      <td class="num">${q.pricingMode === 'Sale' || !split(q).monthly ? '<span class="muted">—</span>' : money(split(q).monthly)}</td>
      <td class="num">${money(split(q).oneTime)}${recurringNote(split(q).recurring)}</td>`;
    tr.appendChild(window.documentRowActions('Quotation', { id: q.id, number: q.quotationNumber, status: q.status, projectId: currentProject.id }, refreshQuotationList));
    if (q.fromCombined) tr.classList.add('combined-row');
    (q.fromCombined ? combinedBody : tbody).appendChild(tr);
  }
  container.innerHTML = '';
  container.appendChild(table);
  selections.quotation.afterRender();
}

async function refreshInvoiceList() {
  currentInvoices = await window.api.invoices.listForProject(currentProject.id);
  setCount('invoices', currentInvoices.length);
  const container = document.getElementById('invoice-list');

  if (currentInvoices.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <h2>No invoices yet</h2>
        <p>Create an invoice for this project.</p>
      </div>`;
    return;
  }

  const table = document.createElement('table');
  table.innerHTML = `
    <thead><tr>${selections.invoice.headerCell()}<th>Number</th><th>Status</th><th>Created By</th><th>Due</th><th class="num">Total</th><th class="num">Paid</th><th></th></tr></thead>
    <tbody></tbody>`;
  const tbody = table.querySelector('tbody');
  for (const inv of currentInvoices) {
    const tr = document.createElement('tr');
    tr.style.cursor = 'pointer';
    tr.onclick = () => { location.href = `invoice-editor.html?id=${inv.id}`; };
    tr.dataset.id = inv.id;
    tr.innerHTML = `${selections.invoice.cell(inv.id)}
      <td>${esc(inv.invoiceNumber)}${inv.deliveryNoteNumbers && inv.deliveryNoteNumbers.length
        ? `<div class="sub">From ${esc(inv.deliveryNoteNumbers.join(', '))}${inv.quotationNumber ? ` (${esc(inv.quotationNumber)})` : ''}</div>`
        : inv.quotationNumber ? `<div class="sub">From ${esc(inv.quotationNumber)}</div>` : ''}</td>
      <td><span class="status-pill">${inv.status}</span></td>
      ${window.createdByCell(inv)}
      <td>${window.appDay(inv.dueDate)}</td>
      <td class="num">${money(inv.total)}</td>
      <td class="num">${money(inv.amountPaid)}</td>`;
    tr.appendChild(window.documentRowActions('Invoice', { id: inv.id, number: inv.invoiceNumber, status: inv.status }, refreshInvoiceList));
    tbody.appendChild(tr);
  }
  container.innerHTML = '';
  container.appendChild(table);
  selections.invoice.afterRender();
}

async function refreshDeliveryNoteList() {
  currentDeliveryNotes = await window.api.deliveryNotes.listForProject(currentProject.id);
  setCount('delivery', currentDeliveryNotes.length);
  const container = document.getElementById('delivery-note-list');

  if (currentDeliveryNotes.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <h2>No delivery notes yet</h2>
        <p>Create a delivery note when materials are delivered.</p>
      </div>`;
    return;
  }

  const table = document.createElement('table');
  table.innerHTML = `
    <thead><tr>${selections.delivery.headerCell()}<th>Number</th><th>Status</th><th>Created By</th><th>Date</th><th>Items</th><th></th></tr></thead>
    <tbody></tbody>`;
  const tbody = table.querySelector('tbody');
  for (const dn of currentDeliveryNotes) {
    const tr = document.createElement('tr');
    tr.style.cursor = 'pointer';
    tr.onclick = () => { location.href = `delivery-note-editor.html?id=${dn.id}`; };
    tr.dataset.id = dn.id;
    tr.innerHTML = `${selections.delivery.cell(dn.id)}
      <td>${esc(dn.deliveryNoteNumber)}${dn.quotationNumber ? `<div class="sub">For ${esc(dn.quotationNumber)}</div>` : ''}${dn.invoiceNumbers && dn.invoiceNumbers.length
        ? `<div class="sub">Invoiced in ${esc(dn.invoiceNumbers.join(', '))}</div>` : ''}</td>
      <td><span class="status-pill">${dn.status}</span>${dn.signed ? ' <span class="status-pill pill-success" title="The copy signed on site is in the project’s Delivery Notes folder, and goes with its invoice">Signed</span>' : ''}</td>
      ${window.createdByCell(dn)}
      <td>${window.appDay(dn.deliveryDate)}</td>
      <td>${dn.itemCount}</td>`;
    tr.appendChild(window.documentRowActions('DeliveryNote', { id: dn.id, number: dn.deliveryNoteNumber, status: dn.status }, refreshDeliveryNoteList));
    tbody.appendChild(tr);
  }
  container.innerHTML = '';
  container.appendChild(table);
  selections.delivery.afterRender();
}

// Letters on the letterhead, numbered from the project code (L26001-001…).
async function refreshLetterList() {
  const letters = (await window.api.letters.list(currentProject.id)) || [];
  setCount('letters', letters.length);
  const container = document.getElementById('letter-list');
  if (letters.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>No letters yet</h2><p>Use “+ New Letter” to write one on the letterhead.</p></div>`;
    return;
  }
  const pill = { Issued: 'pill-success', Cancelled: 'pill-danger' };
  container.innerHTML = `<table>
    <thead><tr><th>Number</th><th>Status</th><th>Created By</th><th>Date</th><th>Subject</th><th>To</th></tr></thead>
    <tbody>${letters.map((l) => `<tr style="cursor:pointer" data-id="${esc(l.id)}">
      <td>${esc(l.letterNumber)}</td><td><span class="status-pill ${pill[l.status] || ''}">${esc(l.status)}</span></td>
      ${window.createdByCell(l)}<td>${formatDay(l.letterDate)}</td><td>${esc(l.subject || '—')}</td><td>${esc(l.recipientName || '—')}</td></tr>`).join('')}</tbody></table>`;
  for (const tr of container.querySelectorAll('tr[data-id]')) {
    tr.addEventListener('click', () => { location.href = `letter-editor.html?id=${encodeURIComponent(tr.dataset.id)}`; });
  }
}

async function createNewLetter() {
  const r = await window.api.letters.create({ projectId: currentProject.id });
  if (!r || !r.ok) { alert((r && r.error) || 'The letter couldn’t be created.'); return; }
  location.href = `letter-editor.html?id=${encodeURIComponent(r.id)}`;
}

/// Shared renderer for both the Drawings list and the Documents list —
/// same shape (name/type/size/uploaded/description + actions), differing
/// only in whether a Category column shows and which API namespace the
/// row actions call. A missing file (section 38) swaps Open/Locate File/
/// Rename/Archive for Find Moved File…/Remove Reference.
function renderFileList(containerId, items, api, opts) {
  const container = document.getElementById(containerId);
  if (items.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>${opts.emptyTitle}</h2><p>${opts.emptyBody}</p></div>`;
    return;
  }

  const headerCells = ['Name', ...(opts.showCategory ? ['Category'] : []), ...(opts.linkChoices ? ['For'] : []), 'Type', 'Size', 'Uploaded', 'Description', ''];
  // In brackets, each one folding open and shut: each BOQ with its
  // quotations, a quotation or BOQ on its own, then the files not linked
  // to either. Which are folded is remembered on this Mac.
  const groups = fileGroups(items);
  const stateKey = `files-folded:${currentProject.projectNumber}:${containerId}`;
  let folded = {};
  try { folded = JSON.parse(localStorage.getItem(stateKey) || '{}'); } catch (e) { folded = {}; }
  const wrap = document.createElement('div');
  wrap.className = 'file-accordion';
  for (const group of groups) {
    const card = document.createElement('section');
    card.className = `file-group-card${folded[group.key] ? ' folded' : ''}`;
    card.innerHTML = `<button type="button" class="file-group-head" data-no-icon aria-expanded="${folded[group.key] ? 'false' : 'true'}">
        <span class="chev" aria-hidden="true">›</span>
        <span class="file-group-title">${esc(group.title)}</span>${group.sub ? `<span class="muted file-group-sub">— ${esc(group.sub)}</span>` : ''}
        <span class="file-group-count">${group.items.length} file${group.items.length === 1 ? '' : 's'}</span></button>
      <table class="no-sort"><thead><tr>${headerCells.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody></tbody></table>`;
    const body = card.querySelector('tbody');
    for (const item of group.items) body.appendChild(fileRow(item));
    card.querySelector('.file-group-head').addEventListener('click', () => {
      const shut = !card.classList.contains('folded');
      card.classList.toggle('folded', shut);
      card.querySelector('.file-group-head').setAttribute('aria-expanded', shut ? 'false' : 'true');
      if (shut) folded[group.key] = true; else delete folded[group.key];
      try { localStorage.setItem(stateKey, JSON.stringify(folded)); } catch (e) { /* ignore */ }
    });
    wrap.appendChild(card);
  }
  container.innerHTML = '';
  container.appendChild(wrap);

  function fileRow(item) {
    const tr = document.createElement('tr');
    const missingBadge = item.fileExists ? '' : ' <span class="status-pill" style="color:var(--danger);">File unavailable</span>';
    const categoryCell = opts.showCategory ? `<td class="c-cat">${esc(item.category)}</td>` : '';
    // The name shown is the file's name in Finder; the name it was
    // uploaded under is kept underneath when different (section 33).
    const shownName = item.storedFilename || item.originalName;
    const uploadedAs = item.originalName && item.originalName !== shownName
      ? `<div class="sub muted">Uploaded as ${esc(item.originalName)}</div>` : '';
    // Drawings: the BOQ or quotation this drawing belongs to.
    const current = item.linkedKind && item.linkedId ? `${item.linkedKind}|${item.linkedId}` : '';
    const linkCell = opts.linkChoices
      ? `<td class="c-for"><select class="link-select">${opts.linkChoices.map((c) => `<option value="${c.value}" ${c.value === current ? 'selected' : ''}>${esc(c.label)}</option>`).join('')}</select></td>`
      : '';
    tr.innerHTML = `
      <td class="c-name">${esc(shownName)}${missingBadge}${uploadedAs}</td>
      ${categoryCell}${linkCell}
      <td class="c-type">${esc(item.fileType)}</td>
      <td class="c-size">${formatFileSize(item.fileSizeBytes)}</td>
      <td class="c-date">${window.appDay(item.uploadedAt, '')}</td>
      <td class="c-desc"><input type="text" class="desc-input" value="${(item.description || '').replace(/"/g, '&quot;')}" placeholder="Add a description" /></td>
      <td class="file-actions"></td>`;

    tr.querySelector('.desc-input').addEventListener('change', async (e) => {
      await api.updateDescription(item.id, e.target.value || null);
    });
    const linkSelect = tr.querySelector('.link-select');
    if (linkSelect) linkSelect.addEventListener('change', async () => {
      const [kind, id] = linkSelect.value ? linkSelect.value.split('|') : [null, null];
      const r = await api.setLink(item.id, kind, id);
      if (!r.ok) alert(r.error);
      await opts.refresh();
    });

    const actionsCell = tr.querySelector('.file-actions');
    // Right-click offers the same actions as the row's buttons.
    tr.addEventListener('contextmenu', (e) => {
      const buttons = Array.from(actionsCell.querySelectorAll('button'));
      // (Icon buttons keep their word in data-icon-label.)
      const labelOf = (b) => (b.dataset.iconLabel || b.textContent).trim();
      window.showContextMenu(e, buttons.map((b) => ({ label: labelOf(b), action: () => b.click(), danger: /archive|remove/i.test(labelOf(b)) })));
    });
    if (item.fileExists) {
      actionsCell.innerHTML = `<button class="open-btn">Open</button> <button class="reveal-btn" title="Show this file in Finder">Locate File</button> <button class="rename-btn">Rename</button> <button class="replace-btn">Replace…</button> <button class="archive-btn">Archive</button>`;
      actionsCell.querySelector('.replace-btn').addEventListener('click', async () => {
        const result = await api.replace(item.id);
        if (result && !result.ok) alert(result.error);
        await opts.refresh();
      });
      actionsCell.querySelector('.open-btn').addEventListener('click', async () => {
        const result = await api.open(item.id);
        if (!result.ok) alert(result.error);
      });
      actionsCell.querySelector('.reveal-btn').addEventListener('click', async () => {
        const result = await api.reveal(item.id);
        if (!result.ok) alert(result.error);
      });
      actionsCell.querySelector('.rename-btn').addEventListener('click', async () => {
        const current = shownName.replace(/\.[^.]+$/, '');
        const newName = await window.appPrompt('Rename File\n\nNew name for this file:', current, { ok: 'Rename' });
        if (!newName) return;
        const result = await api.rename(item.id, newName);
        if (!result.ok) alert(result.error);
        await opts.refresh();
      });
      actionsCell.querySelector('.archive-btn').addEventListener('click', async () => {
        await api.archive(item.id);
        await opts.refresh();
        if (window.appUndoHint) window.appUndoHint(`Archived “${shownName}”`);
      });
    } else {
      actionsCell.innerHTML = `<button class="locate-btn" title="The file has moved: choose where it is now">Find Moved File…</button> <button class="remove-ref-btn">Remove Reference</button>`;
      actionsCell.querySelector('.locate-btn').addEventListener('click', async () => {
        const result = await api.relink(item.id);
        if (result && !result.ok) alert(result.error);
        await opts.refresh();
      });
      actionsCell.querySelector('.remove-ref-btn').addEventListener('click', async () => {
        await api.removeReference(item.id);
        await opts.refresh();
        if (window.appUndoHint) window.appUndoHint('Reference removed (no file was deleted)');
      });
    }

    return tr;
  }
}

// The brackets files are listed in: each BOQ together with the quotations
// made from it ("BQ26212-001 · Qt26212-001"), a quotation with no BOQ, a
// BOQ with no quotation — in the order the lists show them — then the
// files that aren't linked to any.
function fileGroups(items) {
  const groups = [];
  const byKey = {};
  const boqIds = new Set(currentBOQs.map((b) => b.id));
  for (const b of currentBOQs) {
    const qs = currentQuotations.filter((q) => q.boqId === b.id);
    byKey[`boq:${b.id}`] = { key: `boq:${b.id}`, title: [`BOQ ${b.boqNumber}`, ...qs.map((q) => `Quotation ${q.quotationNumber}`)].join(' · '), sub: b.structure, items: [] };
    groups.push(byKey[`boq:${b.id}`]);
  }
  for (const q of currentQuotations) {
    if (q.boqId && boqIds.has(q.boqId)) continue;
    byKey[`q:${q.id}`] = { key: `q:${q.id}`, title: `Quotation ${q.quotationNumber}`, sub: q.subject, items: [] };
    groups.push(byKey[`q:${q.id}`]);
  }
  const loose = { key: 'loose', title: 'Not linked to a BOQ or quotation', items: [] };
  for (const item of items) {
    let key = null;
    if (item.linkedKind === 'BOQ') key = `boq:${item.linkedId}`;
    else if (item.linkedKind === 'Quotation') {
      const q = currentQuotations.find((x) => x.id === item.linkedId);
      key = q && q.boqId && boqIds.has(q.boqId) ? `boq:${q.boqId}` : `q:${item.linkedId}`;
    }
    (byKey[key] || loose).items.push(item);
  }
  return groups.concat(loose).filter((g) => g.items.length);
}

/// "Not linked", then the project's BOQs and quotations.
function drawingLinkChoices() {
  return [{ value: '', label: 'Not linked' }]
    .concat(currentBOQs.map((b) => ({ value: `BOQ|${b.id}`, label: `BOQ ${b.boqNumber}` })))
    .concat(currentQuotations.filter((q) => q.status !== 'Cancelled').map((q) => ({ value: `Quotation|${q.id}`, label: `Quotation ${q.quotationNumber}` })));
}

async function refreshDrawingList() {
  const choices = drawingLinkChoices();
  const uploadFor = document.getElementById('drawing-link-select');
  const keep = uploadFor.value;
  uploadFor.innerHTML = choices.map((c) => `<option value="${c.value}">${c.value ? `For ${esc(c.label)}` : 'Not linked to a BOQ / quotation'}</option>`).join('');
  if (choices.some((c) => c.value === keep)) uploadFor.value = keep;
  const drawings = await window.api.drawings.listForProject(currentProject.id);
  fileCounts.drawings = drawings.length;
  setCount('files', fileCounts.drawings + fileCounts.documents);
  renderFileList('drawing-list', drawings, window.api.drawings, {
    emptyTitle: 'No drawings yet',
    emptyBody: 'Use "Upload Drawing" above to add one: PDF, DWG, DXF or an image.',
    showCategory: false,
    linkChoices: choices,
    refresh: refreshDrawingList,
  });
}

async function refreshDocumentList() {
  const documents = await window.api.documents.listForProject(currentProject.id);
  fileCounts.documents = documents.length;
  setCount('files', fileCounts.drawings + fileCounts.documents);
  renderFileList('document-list', documents, window.api.documents, {
    emptyTitle: 'No documents yet',
    emptyBody: 'Upload a contract, certificate, or other project document.',
    showCategory: true,
    // Filed with a BOQ / quotation (bracketed with it), like the drawings.
    linkChoices: drawingLinkChoices(),
    refresh: refreshDocumentList,
  });
}

// Rental or Sale prices for a new document (null if cancelled).
function choosePricing(what) {
  return window.appChoose(`New ${what}\n\nWhich prices should it use?`, [
    { label: 'Sale', value: 'Sale' }, { label: 'Rental', value: 'Rental', primary: true }]);
}

async function createNewBOQ() {
  const pricingMode = await choosePricing('BOQ');
  if (!pricingMode) return;
  const boq = await window.api.boq.create(currentProject.id, currentProject.projectNumber, pricingMode);
  location.href = `boq-editor.html?id=${boq.id}`;
}

async function createNewQuotation() {
  let sourceBOQId = null;
  let pricingMode = 'Rental';
  if (currentBOQs.length > 0) {
    const mostRecent = currentBOQs[0];
    // The project's other BOQs, in a list that opens from "Start from Others".
    const others = currentBOQs.slice(1).filter((b) => b.status !== 'Cancelled').map((b) => ({
      label: b.boqNumber, value: { boq: b.id },
      sub: [b.structure, `${b.itemCount} item${b.itemCount === 1 ? '' : 's'}`, b.status, b.combined ? 'combined count' : ''].filter(Boolean).join(' · '),
    }));
    const pick = await window.appChoose(`New Quotation\n\nMake it from BOQ ${mostRecent.boqNumber}? The two stay linked: a change to either is made to the other (until you remove the link).`, [
      { label: 'Start Blank', value: 'blank' },
      ...(others.length ? [{ label: 'Start from Others', menu: others }] : []),
      { label: `From ${mostRecent.boqNumber}`, value: 'boq', primary: true }]);
    if (!pick) return;
    if (pick === 'boq') sourceBOQId = mostRecent.id;
    else if (pick.boq) sourceBOQId = pick.boq;
  }
  if (!sourceBOQId) {
    pricingMode = await choosePricing('Quotation');
    if (!pricingMode) return;
  }
  const quotation = await window.api.quotations.create(currentProject.id, currentProject.projectNumber, sourceBOQId, pricingMode);
  location.href = `quotation-editor.html?id=${quotation.id}`;
}

// Every invoice is based on one of the project's quotations. For a rental
// quotation, choose one month's rent or the full hire period.
let invoiceSource = null;
// Invoicing delivery notes (the usual way) or a whole quotation.
let invoiceFromQuotation = false;

// Invoices are made from delivery notes: what was delivered, priced as on
// the quotation each was delivered for. (A whole quotation can still be
// invoiced, e.g. for a deposit before anything is delivered.)
async function createNewInvoice() {
  const usable = currentQuotations.filter((q) => q.status !== 'Cancelled');
  if (usable.length === 0) {
    alert('Create a quotation first.\n\nDelivery notes are made from a quotation, and invoices from the delivery notes.');
    showTab('quotations');
    return;
  }
  const notes = currentDeliveryNotes.filter((d) => d.status !== 'Cancelled');
  const box = document.getElementById('inv-dns');
  if (!notes.length) {
    box.innerHTML = '<div class="empty-inline">No delivery notes yet. Make one from a quotation (Delivery Notes › New Delivery Note) — or choose “A whole quotation” above.</div>';
  } else {
    // Grouped by the quotation they deliver; not yet invoiced first.
    const groups = {};
    for (const d of notes) (groups[d.quotationNumber || ''] = groups[d.quotationNumber || ''] || []).push(d);
    const keys = Object.keys(groups).sort((a, b) => (a === '') - (b === '') || b.localeCompare(a));
    box.innerHTML = keys.map((k) => `<div class="dn-group">${k ? `Quotation ${esc(k)}` : 'Not from a quotation (no prices)'}</div>` +
      groups[k].map((d) => `<label><input type="checkbox" class="inv-dn" value="${esc(d.id)}" data-quotation="${esc(d.sourceQuotationId || '')}" ${k ? '' : 'disabled'} />
        <span>${esc(d.deliveryNoteNumber)} <span class="muted">· ${formatDay(d.deliveryDate)} · ${Math.round(d.totalQuantity || 0).toLocaleString('en-US')} pcs</span></span>
        <span class="muted">${d.invoiceNumbers && d.invoiceNumbers.length ? `invoiced (${esc(d.invoiceNumbers.join(', '))})` : d.status}</span></label>`).join('')).join('');
    // Ticked: the newest quotation's notes not yet invoiced.
    const firstKey = keys.find((k) => k);
    if (firstKey) {
      for (const input of box.querySelectorAll('.inv-dn')) {
        const d = notes.find((n) => n.id === input.value);
        input.checked = d.quotationNumber === firstKey && !(d.invoiceNumbers && d.invoiceNumbers.length);
      }
    }
    for (const input of box.querySelectorAll('.inv-dn')) input.addEventListener('change', loadInvoiceSource);
  }
  const select = document.getElementById('inv-quotation');
  select.innerHTML = usable.map((q) =>
    `<option value="${q.id}">${esc(q.quotationNumber)} · ${esc(q.status)} · ${money(q.total)}</option>`).join('');
  setInvoiceMode(!notes.some((d) => d.sourceQuotationId));
  document.getElementById('inv-error').classList.add('hidden');
  document.getElementById('invoice-modal').classList.remove('hidden');
  await loadInvoiceSource();
}

function setInvoiceMode(fromQuotation) {
  invoiceFromQuotation = fromQuotation;
  document.getElementById('inv-quotation-field').classList.toggle('hidden', !fromQuotation);
  document.getElementById('inv-dn-field').classList.toggle('hidden', fromQuotation);
  for (const b of document.querySelectorAll('#inv-mode button')) b.classList.toggle('active', (b.dataset.mode === 'quotation') === fromQuotation);
}

function chosenNotes() {
  return [...document.querySelectorAll('#inv-dns .inv-dn:checked')].map((i) => ({ id: i.value, quotationId: i.dataset.quotation }));
}

async function loadInvoiceSource() {
  const err = document.getElementById('inv-error');
  err.classList.add('hidden');
  let quotationId = document.getElementById('inv-quotation').value;
  if (!invoiceFromQuotation) {
    const picked = chosenNotes();
    const sources = [...new Set(picked.map((p) => p.quotationId))];
    if (sources.length > 1) {
      err.textContent = 'Those delivery notes are for different quotations. Invoice each quotation’s deliveries separately.';
      err.classList.remove('hidden');
    }
    quotationId = sources[0] || null;
  }
  invoiceSource = quotationId ? await window.api.quotations.get(quotationId) : null;
  const q = invoiceSource;
  const rental = q && q.pricingMode === 'Rental';
  document.getElementById('inv-rental').classList.toggle('hidden', !rental);
  if (rental) {
    document.getElementById('inv-months').value = q.minimumHireMonths;
    document.querySelector(`input[name="inv-charge"][value="${q.minimumHireEnabled ? 'full' : 'one'}"]`).checked = true;
  }
  const hasDelivery = !!q && q.lineItems.some((i) => i.section === 'Delivery' && !i.blockId);
  document.getElementById('inv-delivery-row').classList.toggle('hidden', !hasDelivery);
  // Priced sections (design fees, erection prices…) with rows.
  const pricedBlocks = q ? q.blocks.filter((b) => b.kind === 'Priced' && q.lineItems.some((i) => i.blockId === b.id)) : [];
  document.getElementById('inv-other-row').classList.toggle('hidden', pricedBlocks.length === 0);
  document.getElementById('inv-other-names').textContent = pricedBlocks.map((b) => b.title || 'other charges').join(', ');
  updateInvoiceSummary();
}

function invoiceMonthsChosen() {
  if (!invoiceSource || invoiceSource.pricingMode !== 'Rental') return null;
  const full = document.querySelector('input[name="inv-charge"]:checked').value === 'full';
  return full ? Math.max(1, Math.round(Number(document.getElementById('inv-months').value) || 1)) : 1;
}

function updateInvoiceSummary() {
  const q = invoiceSource;
  const summary = document.getElementById('inv-summary');
  if (!q) { summary.textContent = invoiceFromQuotation ? '' : 'Tick the delivery notes to invoice.'; return; }
  const months = invoiceMonthsChosen();
  const delivery = !document.getElementById('inv-delivery-row').classList.contains('hidden') && document.getElementById('inv-delivery').checked;
  const other = !document.getElementById('inv-other-row').classList.contains('hidden') && document.getElementById('inv-other').checked;
  const picked = chosenNotes();
  const parts = invoiceFromQuotation
    ? [`${q.lineItems.filter((i) => i.section !== 'Delivery' && !i.blockId).length} item(s) from ${q.quotationNumber}`]
    : (() => {
      // Notes for several quotations: one invoice, a section for each quotation.
      const quotes = [...new Set(picked.map((p) => p.quotationId))];
      return [quotes.length > 1
        ? `What ${picked.length} delivery notes delivered, in ${quotes.length} sections — one per quotation, at each one’s prices`
        : `What ${picked.length} delivery note${picked.length === 1 ? '' : 's'} delivered, at ${q.quotationNumber}’s prices`];
    })();
  if (months) parts.push(`${months} month${months === 1 ? '' : 's'} of rent`);
  if (delivery) parts.push(`delivery charges ${money(q.deliveryTotal)}`);
  if (other) parts.push(`other charges ${money(q.otherChargesTotal)}`);
  summary.textContent = parts.join(' · ');
}

function setupInvoiceSheet() {
  const close = () => document.getElementById('invoice-modal').classList.add('hidden');
  document.getElementById('inv-quotation').addEventListener('change', loadInvoiceSource);
  for (const b of document.querySelectorAll('#inv-mode button')) {
    b.addEventListener('click', () => { setInvoiceMode(b.dataset.mode === 'quotation'); loadInvoiceSource(); });
  }
  for (const el of document.querySelectorAll('input[name="inv-charge"], #inv-months, #inv-delivery, #inv-other')) {
    el.addEventListener('input', updateInvoiceSummary);
    el.addEventListener('change', updateInvoiceSummary);
  }
  document.getElementById('inv-months').addEventListener('focus', () => {
    document.querySelector('input[name="inv-charge"][value="full"]').checked = true;
    updateInvoiceSummary();
  });
  document.getElementById('inv-cancel').addEventListener('click', close);
  document.getElementById('invoice-modal').addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });
  document.getElementById('inv-create').addEventListener('click', async () => {
    const err = document.getElementById('inv-error');
    const notes = chosenNotes();
    if (!invoiceFromQuotation && !notes.length) {
      err.textContent = 'Tick the delivery notes to invoice.';
      err.classList.remove('hidden');
      return;
    }
    const months = invoiceMonthsChosen();
    const includeDelivery = document.getElementById('inv-delivery-row').classList.contains('hidden') || document.getElementById('inv-delivery').checked;
    const includeOtherCharges = document.getElementById('inv-other-row').classList.contains('hidden') || document.getElementById('inv-other').checked;
    try {
      const invoice = await window.api.invoices.create(currentProject.id, currentProject.projectNumber,
        invoiceFromQuotation ? document.getElementById('inv-quotation').value : null,
        { rentalMonths: months, includeDelivery: includeDelivery, includeOtherCharges: includeOtherCharges,
          deliveryNoteIds: invoiceFromQuotation ? [] : notes.map((n) => n.id) });
      location.href = `invoice-editor.html?id=${invoice.id}`;
    } catch (e) {
      err.textContent = e.message;
      err.classList.remove('hidden');
    }
  });
}

// A delivery note is made from a quotation (its materials, to change to
// what goes out); invoices are then made from the delivery notes.
async function createNewDeliveryNote() {
  const usable = currentQuotations.filter((q) => q.status !== 'Cancelled');
  if (!usable.length) {
    alert('Create a quotation first.\n\nA delivery note is made from a quotation, so its invoice can be priced from it.');
    showTab('quotations');
    return;
  }
  const select = document.getElementById('dn-quotation');
  select.innerHTML = usable.map((q) => `<option value="${esc(q.id)}">${esc(q.quotationNumber)}${q.subject ? ` — ${esc(q.subject)}` : ''} · ${esc(q.status)}</option>`).join('');
  document.getElementById('dn-modal').classList.remove('hidden');
  select.focus();
}

function setupDeliveryNoteSheet() {
  const close = () => document.getElementById('dn-modal').classList.add('hidden');
  document.getElementById('dn-cancel').addEventListener('click', close);
  document.getElementById('dn-modal').addEventListener('keydown', (e) => { if (e.key === 'Escape') close(); });
  document.getElementById('dn-create').addEventListener('click', async () => {
    const note = await window.api.deliveryNotes.create(currentProject.id, currentProject.projectNumber, document.getElementById('dn-quotation').value, null);
    location.href = `delivery-note-editor.html?id=${note.id}`;
  });
}


// ---------- Tabs, overview, edit sheet, history (sections 15, 17, 45) ----------

const fileCounts = { drawings: 0, documents: 0 };

function esc(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

const tabCounts = {};
function setCount(tab, n) {
  const el = document.getElementById(`count-${tab}`);
  if (el) el.textContent = n > 0 ? String(n) : '';
  tabCounts[tab] = n;
  renderStats();
}

function showTab(name) {
  for (const b of document.querySelectorAll('#tabs button')) b.classList.toggle('active', b.dataset.tab === name);
  for (const p of document.querySelectorAll('.tab-panel')) p.classList.toggle('active', p.dataset.panel === name);
  try { sessionStorage.setItem(`project-tab-${currentProject.projectNumber}`, name); } catch (e) { /* ignore */ }
}

function setupTabs() {
  for (const b of document.querySelectorAll('#tabs button')) b.addEventListener('click', () => showTab(b.dataset.tab));
  const params = new URLSearchParams(location.search);
  let initial = params.get('tab');
  if (!initial && (location.hash === '#drawings' || location.hash === '#documents')) initial = 'files';
  if (!initial) {
    try { initial = sessionStorage.getItem(`project-tab-${currentProject.projectNumber}`); } catch (e) { initial = null; }
  }
  showTab(initial || 'overview');
}

function formatDay(value) {
  if (!value) return '—';
  const d = new Date(value.length <= 10 ? `${value}T00:00:00` : value);
  return isNaN(d) ? value : d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace('Sept', 'Sep');
}

function formatWhen(iso) {
  const d = new Date(iso);
  return isNaN(d) ? iso : d.toLocaleString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }).replace('Sept', 'Sep');
}

const SVG = (paths, size = 16) => `<svg viewBox="0 0 20 20" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
const PD_ICONS = {
  client: '<path d="M3.5 17V5.5a1 1 0 0 1 .7-1l6-2a.7.7 0 0 1 .9.7V17"/><path d="M11 7.5h4.5a1 1 0 0 1 1 1V17M2 17h16M6.5 7h1.5M6.5 10h1.5M6.5 13h1.5M13.5 11h1M13.5 13.8h1"/>',
  site: '<path d="M10 17.5s-5.5-5-5.5-9a5.5 5.5 0 0 1 11 0c0 4-5.5 9-5.5 9z"/><circle cx="10" cy="8.5" r="2"/>',
  person: '<circle cx="10" cy="7" r="3"/><path d="M4 17c.8-3 3.2-4.5 6-4.5s5.2 1.5 6 4.5"/>',
  calendar: '<rect x="3" y="4.5" width="14" height="12.5" rx="1.5"/><path d="M3 8.5h14M7 2.5v4M13 2.5v4"/>',
  flag: '<path d="M4.5 17.5V3.5"/><path d="M4.5 4h10l-2 3.5 2 3.5h-10"/>',
  clock: '<circle cx="10" cy="10" r="7"/><path d="M10 6v4.3l2.8 1.7"/>',
  hash: '<path d="M8 3 6.5 17M13.5 3 12 17M3.5 7.5h14M2.5 12.5h14"/>',
  status: '<circle cx="10" cy="10" r="7"/><path d="m7 10.2 2.2 2.2 4-4.4"/>',
};
// The same look and colours as the Dashboard's Quick Actions.
const PD_ACTIONS = [
  { action: 'new-boq', label: 'New BOQ', color: '#4F8A8F', icon: '<rect x="3" y="3.5" width="14" height="13" rx="1.5"/><path d="M3 7.5h14M3 11.5h14M8 7.5v9"/>' },
  { action: 'new-quotation', label: 'New Quotation', color: '#8E72A8', icon: '<path d="M11.5 2.5H5.5A1.5 1.5 0 0 0 4 4v12a1.5 1.5 0 0 0 1.5 1.5h9A1.5 1.5 0 0 0 16 16V7z"/><path d="M11.5 2.5V7H16"/><path d="M7 11h6M7 14h4"/>' },
  { action: 'new-delivery-note', label: 'New Delivery Note', color: '#5E8C6A', icon: '<path d="M2.5 5.5h9v8h-9z"/><path d="M11.5 8.5h3l2.5 2.5v2.5h-5.5"/><circle cx="6" cy="14.5" r="1.5"/><circle cx="14" cy="14.5" r="1.5"/>' },
  { action: 'new-invoice', label: 'New Invoice', color: '#A66A6A', icon: '<path d="M5 2.5h10v15l-2-1.3-1.7 1.3-1.3-1.3-1.3 1.3L7 16.2l-2 1.3z"/><path d="M8 7h4M8 10h4M8 13h2.5"/>' },
  { action: 'new-letter', label: 'New Letter', color: '#7A7F9A', icon: '<rect x="2.5" y="4.5" width="15" height="11" rx="1.3"/><path d="m3 5.5 7 5.2 7-5.2"/>' },
  { action: 'record-inspection', label: 'Record Inspection', color: '#B07A5E', icon: '<path d="M10 2.5 16 5v4.5c0 3.8-2.6 6.7-6 8-3.4-1.3-6-4.2-6-8V5z"/><path d="m7.3 10 2 2 3.6-4"/>' },
  { action: 'new-task', label: 'New Task', color: '#6E8F4E', icon: '<rect x="3.5" y="3.5" width="13" height="13" rx="2"/><path d="m6.8 10.2 2.2 2.2 4.3-4.6"/>' },
  { action: 'upload-drawing', label: 'Upload Drawing', color: '#5B7DB1', icon: '<rect x="2.5" y="3.5" width="15" height="13" rx="1.5"/><path d="m2.5 13.5 4-4 3 3 2.5-2.5 5.5 5.5"/><circle cx="13.5" cy="7.3" r="1.3"/>' },
  { action: 'upload-document', label: 'Upload Document', color: '#9A8458', icon: '<path d="M3.5 12.5v2A1.5 1.5 0 0 0 5 16h10a1.5 1.5 0 0 0 1.5-1.5v-2"/><path d="M10 12.5V3.5"/><path d="M6.5 7 10 3.5 13.5 7"/>' },
];
// The stages a project goes through, in order; On Hold and Archived sit outside them.
const STAGES = ['Planning', 'Quotation', 'Active', 'Completed'];
const statusClass = (s) => `st-${String(s || '').toLowerCase().replace(/[^a-z]+/g, '-')}`;

function renderProjectHeader() {
  const p = currentProject;
  document.title = `${p.projectNumber} — ScaffoldPro`;
  // A crane job has no BOQs: its BOQ tab, tile and "New BOQ" are hidden.
  document.body.classList.toggle('crane-job', p.jobType === 'Crane');
  if (p.jobType === 'Crane' && document.querySelector('#tabs [data-tab="boq"].active') && window.showTab) showTab('overview');
  const hero = document.getElementById('pd-hero');
  hero.className = `pd-hero ${statusClass(p.status)}`;
  document.getElementById('project-header').innerHTML = `
    <div class="pd-eyebrow"><span class="eyebrow pd-number" title="Copy the project number" role="button" tabindex="0">Project ${esc(p.projectNumber)}</span><span class="job-tag ${p.jobType === 'Crane' ? 'crane' : 'scaffolding'}" title="Type of job (Edit Details to change)">${p.jobType === 'Crane' ? 'Crane job' : 'Scaffolding job'}</span><span class="pd-status"><i></i>${esc(p.status)}</span></div>
    <h1>${esc(p.name)}</h1>
    <div class="subtitle pd-where">
      <span>${SVG(PD_ICONS.client, 14)}${p.client ? `<a href="clients.html?id=${p.client.id}">${esc(p.client.companyName)}</a>` : 'No client'}</span>
      <span>${SVG(PD_ICONS.site, 14)}${p.site ? `<a href="sites.html?id=${p.site.id}">${esc(p.site.name)}</a>` : 'No site'}</span>
    </div>`;
  const number = document.querySelector('.pd-number');
  const copy = () => { if (window.copyText) window.copyText(p.projectNumber); number.classList.add('copied'); setTimeout(() => number.classList.remove('copied'), 1200); };
  number.addEventListener('click', copy);
  number.addEventListener('keydown', (e) => { if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); copy(); } });
  renderStages();
  renderStats();
  renderOverview();
}

// Planning › Quotation › Active › Completed, the project's stage lit up; a click moves it there.
function renderStages() {
  const p = currentProject;
  const box = document.getElementById('pd-stages');
  const at = STAGES.indexOf(p.status);
  const aside = at < 0 ? `<li class="pd-stage-aside ${statusClass(p.status)}"><i></i>${esc(p.status)}</li>` : '';
  box.innerHTML = STAGES.map((s, i) => `<li class="${i < at ? 'done' : ''}${i === at ? 'now' : ''}"><button type="button" data-no-icon class="pd-stage${i < at ? ' done' : ''}${i === at ? ' now' : ''}" data-status="${s}" ${i === at ? 'aria-current="step"' : ''} title="${i === at ? `This project is at ${s}` : `Move to ${s}`}">
      <span class="pd-stage-dot">${i < at ? SVG('<path d="m5.5 10.5 3 3 6-7"/>', 11) : ''}</span><span>${s}</span></button></li>`).join('') + aside;
}

async function setProjectStatus(status) {
  if (!status || status === currentProject.status) return;
  await window.api.projects.updateStatus(currentProject.id, status);
  currentProject.status = status;
  document.getElementById('status-select').value = status;
  renderProjectHeader();
  await refreshHistory();
}

// What the project holds: a tile per kind, opening its tab.
function renderStats() {
  const box = document.getElementById('pd-stats');
  if (!box || !currentProject) return;
  const files = (fileCounts.drawings || 0) + (fileCounts.documents || 0);
  const tiles = [
    ['boq', 'BOQs', tabCounts.boq], ['quotations', 'Quotations', tabCounts.quotations], ['delivery', 'Delivery Notes', tabCounts.delivery],
    ['invoices', 'Invoices', tabCounts.invoices], ['files', 'Drawings & Docs', tabCounts.files != null ? tabCounts.files : files],
    ['tasks', 'Open Tasks', tabCounts.tasks],
  ];
  // Each kind's colour, as on the Dashboard (css/styles.css, .dk-…).
  const colour = { boq: 'dk-boq', quotations: 'dk-quotation', delivery: 'dk-delivery', invoices: 'dk-invoice', files: 'dk-file' };
  box.innerHTML = tiles.map(([tab, label, n]) => `<button type="button" class="pd-stat ${colour[tab] || ''}${n ? '' : ' zero'}" data-tab="${tab}" data-no-icon>
    <b>${n || 0}</b><span>${label}</span></button>`).join('');
  for (const b of box.querySelectorAll('.pd-stat')) b.addEventListener('click', () => {
    showTab(b.dataset.tab);
    document.getElementById('tabs').scrollIntoView({ behavior: 'smooth', block: 'start' });
  });
}

function renderOverview() {
  const p = currentProject;
  const rows = [
    [PD_ICONS.hash, 'Project Number', p.projectNumber],
    [PD_ICONS.status, 'Status', p.status],
    [PD_ICONS.client, 'Client', p.client ? p.client.companyName : '—'],
    [PD_ICONS.site, 'Site', p.site ? [p.site.name, p.site.address].filter(Boolean).join(', ') : '—'],
    [PD_ICONS.person, 'Project Manager', p.projectManager || '—'],
    [PD_ICONS.calendar, 'Start Date', formatDay(p.startDate)],
    [PD_ICONS.flag, 'Expected Completion', formatDay(p.expectedCompletionDate)],
    [PD_ICONS.clock, 'Created', formatDay(p.createdAt)],
  ];
  document.getElementById('overview-details').innerHTML =
    rows.map(([icon, k, v]) => `<div class="pd-field${v === '—' ? ' empty' : ''}"><span class="pd-field-icon">${SVG(icon, 15)}</span><dt>${k}</dt><dd>${esc(v)}</dd></div>`).join('');
  const desc = document.getElementById('overview-description');
  desc.textContent = p.projectDescription || 'No description yet.';
  desc.classList.toggle('muted', !p.projectDescription);
  const notes = document.getElementById('overview-notes');
  notes.textContent = p.internalNotes || 'No internal notes.';
  notes.classList.toggle('muted', !p.internalNotes);
}

function renderQuickActions() {
  const box = document.getElementById('pd-quick-actions');
  box.innerHTML = PD_ACTIONS.map((a) => `<button class="qa-tile" data-no-icon data-action="${a.action}" style="--qa:${a.color}" title="${esc(a.label)}">
    <span class="qa-icon">${SVG(a.icon)}</span><span class="qa-text">${esc(a.label)}</span></button>`).join('');
  for (const b of box.querySelectorAll('[data-action]')) b.addEventListener('click', () => runQuickAction(b.dataset.action));
}

function runQuickAction(action) {
  const click = (tab, id) => { if (tab) showTab(tab); document.getElementById(id).click(); };
  switch (action) {
    case 'new-boq': click(null, 'new-boq-btn'); break;
    case 'new-quotation': click(null, 'new-quotation-btn'); break;
    case 'new-invoice': click(null, 'new-invoice-btn'); break;
    case 'new-delivery-note': click(null, 'new-delivery-note-btn'); break;
    case 'new-letter': click(null, 'new-letter-btn'); break;
    case 'record-inspection': click('inspections', 'record-inspection-btn'); break;
    case 'new-task': click('tasks', 'new-task-btn'); break;
    case 'upload-drawing': click('files', 'upload-drawing-btn'); break;
    case 'upload-document': click('files', 'upload-document-btn'); break;
    default: break;
  }
}

// The Overview's panels, arranged as on the Dashboard (Customise). An
// arrangement is kept for this project, or for every project (which
// replaces any project's own); kept on this Mac.
const LAYOUT_ALL = 'project.layout';
const layoutKey = () => `${LAYOUT_ALL}:${currentProject.projectNumber}`;
function setupOverviewLayout() {
  const read = (k) => { try { return JSON.parse(localStorage.getItem(k) || 'null'); } catch (e) { return null; } };
  const svg = (paths) => SVG(paths, 18);
  window.setupWidgets(document.getElementById('pd-overview'), document.getElementById('pd-customise-btn'), null, {
    place: 'Overview',
    about: {
      details: [svg(PD_ICONS.hash), 'Number, status, client, site and dates'],
      actions: [svg('<path d="M11 2.5 4.5 11H10l-1 6.5L15.5 9H10z"/>'), 'Start a BOQ, quotation, task…'],
      activity: [svg('<path d="M2.5 10h3l2-5 3 10 2-5h5"/>'), 'What was done lately'],
      notes: [svg('<rect x="4" y="3" width="12" height="14" rx="1.5"/><path d="M7 7h6M7 10h6M7 13h4"/>'), 'Description and internal notes'],
    },
    load: () => read(layoutKey()) || read(LAYOUT_ALL),
    choices: [
      { label: 'For this project', sub: `Only ${currentProject.projectNumber} looks like this`, value: 'project' },
      { label: 'For all projects', sub: 'Every project looks like this, including ones arranged on their own', value: 'all' },
    ],
    store: (layout, scope) => {
      try {
        if (scope === 'all') {
          localStorage.setItem(LAYOUT_ALL, JSON.stringify(layout));
          // Projects arranged on their own follow it too.
          const own = [];
          for (let i = 0; i < localStorage.length; i += 1) { const k = localStorage.key(i); if (k && k.startsWith(`${LAYOUT_ALL}:`)) own.push(k); }
          own.forEach((k) => localStorage.removeItem(k));
        } else {
          localStorage.setItem(layoutKey(), JSON.stringify(layout));
        }
      } catch (e) { /* ignore */ }
      // Said for a few seconds at the bottom right.
      const note = document.createElement('div');
      note.className = 'sync-toast';
      note.setAttribute('role', 'status');
      note.textContent = scope === 'all' ? 'Every project’s Overview now looks like this.' : `Kept for project ${currentProject.projectNumber}.`;
      document.body.appendChild(note);
      requestAnimationFrame(() => note.classList.add('show'));
      setTimeout(() => { note.classList.remove('show'); setTimeout(() => note.remove(), 400); }, 3500);
    },
  });
}

// Recent activity as a timeline: a dot per entry down a line, newest first.
function activityTimeline(list) {
  if (!list.length) return '<div class="empty-inline">No activity recorded yet.</div>';
  return `<ol class="pd-timeline">${list.map((e, i) => `<li style="--i:${i}">
    <span class="pd-tl-dot" aria-hidden="true"></span>
    <div class="pd-tl-what">${esc(e.action)}${e.by ? ` ${window.personTag(e.by)}` : ''}</div>
    <div class="pd-tl-meta">${e.reference ? `<span class="pd-tl-ref">${esc(e.reference)}</span>` : ''}<span>${esc(formatWhen(e.createdAt))}</span></div></li>`).join('')}</ol>`;
}

async function refreshHistory() {
  const entries = await window.api.activity.listForProject(currentProject.id);
  const render = (list) => list.length === 0
    ? '<div class="empty-state compact"><p>No activity recorded yet.</p></div>'
    : `<table class="history"><thead><tr><th>When</th><th>What</th><th>Reference</th></tr></thead><tbody>${
        list.map((e) => `<tr><td class="nowrap muted">${formatWhen(e.createdAt)}</td><td>${esc(e.action)}${e.by ? ` ${window.personTag(e.by)}` : ''}</td><td>${esc(e.reference || '')}</td></tr>`).join('')
      }</tbody></table>`;
  document.getElementById('history-list').innerHTML = render(entries);
  document.getElementById('overview-activity').innerHTML = activityTimeline(entries.slice(0, 6));
}

function setupEditSheet() {
  const $ = (id) => document.getElementById(id);
  const fields = ['name', 'startDate', 'expectedCompletionDate', 'projectManager', 'projectDescription', 'internalNotes'];

  $('edit-project-btn').addEventListener('click', async () => {
    const p = currentProject;
    const [clients, sites] = await Promise.all([window.api.clients.list(true), window.api.sites.list(true)]);
    $('e-clientId').innerHTML = clients.map((c) =>
      `<option value="${c.id}" ${p.client && p.client.id === c.id ? 'selected' : ''}>${esc(c.companyName)}${c.isArchived ? ' (archived)' : ''}</option>`).join('');
    $('e-siteId').innerHTML = sites.map((s) =>
      `<option value="${s.id}" ${p.site && p.site.id === s.id ? 'selected' : ''}>${esc(s.name)}${s.isArchived ? ' (archived)' : ''}</option>`).join('');
    for (const f of fields) $(`e-${f}`).value = p[f] ? String(p[f]).slice(0, f.endsWith('Date') ? 10 : undefined) : '';
    $('e-projectNumber').value = p.projectNumber;
    $(p.jobType === 'Crane' ? 'e-job-crane' : 'e-job-scaffolding').checked = true;
    // Who made it: from the record, or worked out from the history; it can
    // be set by hand (e.g. for a project made before names were recorded).
    const [authors, people] = await Promise.all([window.api.authors.get('project', p.id).catch(() => null), window.api.tasks.people().catch(() => [])]);
    $('e-createdBy').value = (authors && authors.createdBy) || '';
    $('e-createdBy').dataset.was = $('e-createdBy').value;
    $('e-people').innerHTML = (people || []).map((n) => `<option value="${esc(n)}"></option>`).join('');
    $('e-error').classList.add('hidden');
    $('edit-modal').classList.remove('hidden');
    $('e-name').focus();
  });

  $('e-cancel-btn').addEventListener('click', () => $('edit-modal').classList.add('hidden'));
  $('e-delete-btn').addEventListener('click', async () => {
    const p = currentProject;
    if (!p) return;
    $('edit-modal').classList.add('hidden');
    if (await window.deleteProject(p)) location.href = 'projects.html';
  });
  $('e-save-btn').addEventListener('click', async () => {
    const showError = (message) => {
      $('e-error').textContent = message;
      $('e-error').classList.remove('hidden');
    };
    const payload = { clientId: $('e-clientId').value, siteId: $('e-siteId').value };
    for (const f of fields) payload[f] = $(`e-${f}`).value;
    payload.jobType = document.querySelector('input[name="e-jobType"]:checked').value;
    const maker = $('e-createdBy').value.trim();
    if (maker && maker !== $('e-createdBy').dataset.was) payload.createdBy = maker;
    const result = await window.api.projects.update(currentProject.id, payload);
    if (!result.ok) return showError(result.error);
    // A new project code: its folder is renamed, so the page reloads under it.
    const oldCode = currentProject.projectNumber;
    const newCode = $('e-projectNumber').value.trim();
    if (newCode && newCode !== oldCode) {
      if (!await appConfirm(`Change the project code from ${oldCode} to ${newCode}?\n\nIts folder is renamed to Projects/${newCode}, and draft documents numbered with ${oldCode} are renumbered. Issued documents keep their numbers.`)) return;
      const changed = await window.api.projects.changeNumber(currentProject.id, newCode);
      if (!changed.ok) return showError(changed.error);
      location.href = `project-detail.html?number=${encodeURIComponent(newCode)}`;
      return;
    }
    $('edit-modal').classList.add('hidden');
    currentProject = await window.api.projects.get(currentProject.projectNumber);
    renderProjectHeader();
    if (payload.createdBy && window.docHeader) window.docHeader.refresh();
    await refreshHistory();
  });
  $('edit-modal').addEventListener('keydown', (e) => { if (e.key === 'Escape') $('edit-modal').classList.add('hidden'); });
}

// ⌘Z / ⌘Y redraw the page with this, not a reload (js/undo.js): the
// project's details and every tab's list again.
window.appRefresh = async () => {
  if (!currentProject) return;
  const fresh = await window.api.projects.get(currentProject.projectNumber);
  if (fresh) currentProject = fresh;
  document.getElementById('status-select').value = currentProject.status;
  renderProjectHeader();
  await refreshBOQList();
  await refreshQuotationList();
  await refreshInvoiceList();
  await refreshDeliveryNoteList();
  await refreshLetterList();
  await refreshDrawingList();
  await refreshDocumentList();
  await window.projectWork.reload();
  await refreshHistory();
};

async function init() {
  const projectNumber = getProjectNumberFromURL();
  if (!projectNumber) {
    document.getElementById('not-found').classList.remove('hidden');
    return;
  }

  const project = await window.api.projects.get(projectNumber);
  if (!project) {
    document.getElementById('not-found').classList.remove('hidden');
    return;
  }
  currentProject = project;

  renderProjectHeader();
  document.getElementById('project-body').classList.remove('hidden');
  setupTabs();
  setupEditSheet();
  setupInvoiceSheet();
  setupDeliveryNoteSheet();
  renderQuickActions();
  document.querySelector('.pd-all-history').addEventListener('click', () => showTab('history'));
  setupOverviewLayout();

  const statusSelect = document.getElementById('status-select');
  statusSelect.innerHTML = STATUSES.map((s) => `<option value="${s}" ${s === project.status ? 'selected' : ''}>${s}</option>`).join('');
  statusSelect.addEventListener('change', () => setProjectStatus(statusSelect.value));
  document.getElementById('pd-stages').addEventListener('click', (e) => {
    const b = e.target.closest('.pd-stage');
    if (b) setProjectStatus(b.dataset.status);
  });
  // A soft light follows the pointer across the header.
  const hero = document.getElementById('pd-hero');
  hero.addEventListener('pointermove', (e) => {
    const r = hero.getBoundingClientRect();
    hero.style.setProperty('--mx', `${e.clientX - r.left}px`);
    hero.style.setProperty('--my', `${e.clientY - r.top}px`);
  });

  document.getElementById('reveal-folder-btn').addEventListener('click', () => {
    window.api.projects.revealFolder(project.projectNumber);
  });

  document.getElementById('upload-drawing-btn').addEventListener('click', async () => {
    try {
      const link = document.getElementById('drawing-link-select').value;
      const [linkedKind, linkedId] = link ? link.split('|') : [null, null];
      await window.api.projects.uploadDrawing(project.projectNumber, { linkedKind: linkedKind, linkedId: linkedId });
    } catch (e) {
      alert(`Not every drawing could be added.\n\n${e.message}`);
    }
    // Several files can be chosen at once; show whatever was added.
    await refreshDrawingList();
    await refreshHistory();
  });

  document.getElementById('document-category-select').innerHTML =
    DOCUMENT_CATEGORIES.map((c) => `<option value="${c}">${c}</option>`).join('');

  // Files dragged from Finder onto the Drawings or Documents section.
  window.fileDrop(document.getElementById('drawings-drop'), {
    projectNumber: project.projectNumber, target: 'drawing',
    options: () => {
      const link = document.getElementById('drawing-link-select').value;
      const [linkedKind, linkedId] = link ? link.split('|') : [null, null];
      return { linkedKind: linkedKind, linkedId: linkedId };
    },
    done: async () => { await refreshDrawingList(); await refreshHistory(); },
    hint: 'Drop drawings here',
    hintSub: 'PDF, DWG, DXF or images, dragged from Finder. They’re linked to the BOQ or quotation chosen above.',
  });
  window.fileDrop(document.getElementById('documents-drop'), {
    projectNumber: project.projectNumber, target: 'document',
    options: () => ({ category: document.getElementById('document-category-select').value }),
    done: async () => { await refreshDocumentList(); await refreshHistory(); },
    hint: 'Drop documents here',
    hintSub: 'Any files, dragged from Finder. They go under the category chosen above.',
  });

  document.getElementById('upload-document-btn').addEventListener('click', async () => {
    const category = document.getElementById('document-category-select').value;
    try {
      await window.api.documents.upload(project.projectNumber, category);
    } catch (e) {
      alert(`Not every document could be added.\n\n${e.message}`);
    }
    await refreshDocumentList();
    await refreshHistory();
  });

  document.getElementById('new-boq-btn').addEventListener('click', createNewBOQ);
  document.getElementById('new-quotation-btn').addEventListener('click', createNewQuotation);
  document.getElementById('import-quotation-btn').addEventListener('click', () => window.importQuotation(currentProject));
  document.getElementById('new-invoice-btn').addEventListener('click', createNewInvoice);
  document.getElementById('new-delivery-note-btn').addEventListener('click', createNewDeliveryNote);
  document.getElementById('new-letter-btn').addEventListener('click', createNewLetter);

  await refreshBOQList();
  await refreshQuotationList();
  await refreshInvoiceList();
  await refreshDeliveryNoteList();
  await refreshLetterList();
  await refreshDrawingList();
  await refreshDocumentList();
  // Scaffold inspections and the project's tasks (js/project-work.js).
  await window.projectWork.load(currentProject, {
    setCount,
    structures: () => currentBOQs.filter((b) => !b.combined).map((b) => b.structure).filter(Boolean),
    afterChange: refreshHistory,
  });
  await refreshHistory();
  // ?new=1 (the Dashboard's Quick Actions): start the new one straight away.
  const url = new URL(location.href);
  if (url.searchParams.get('new') === '1') {
    url.searchParams.delete('new');
    history.replaceState(null, '', url.toString());
    const start = { boq: 'new-boq-btn', quotations: 'new-quotation-btn', invoices: 'new-invoice-btn', delivery: 'new-delivery-note-btn',
      letters: 'new-letter-btn', inspections: 'record-inspection-btn', tasks: 'new-task-btn' }[url.searchParams.get('tab')];
    if (start) document.getElementById(start).click();
  }
}

init();

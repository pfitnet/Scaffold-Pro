'use strict';

const STATUSES = ['Planning', 'Quotation', 'Active', 'On Hold', 'Completed', 'Archived'];
const DOCUMENT_CATEGORIES = ['Contracts', 'Specifications', 'Correspondence', 'Certificates', 'Client Documents', 'Site Information', 'Miscellaneous'];
let currentProject = null;
let currentBOQs = [];
let currentQuotations = [];
let currentInvoices = [];
let currentDeliveryNotes = [];

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

  const table = document.createElement('table');
  table.innerHTML = `
    <thead><tr><th>Number</th><th>Pricing</th><th>Status</th><th>Items</th><th class="num">Total Weight (kg)</th></tr></thead>
    <tbody></tbody>`;
  const tbody = table.querySelector('tbody');
  for (const b of currentBOQs) {
    const tr = document.createElement('tr');
    tr.style.cursor = 'pointer';
    tr.onclick = () => { location.href = `boq-editor.html?id=${b.id}`; };
    tr.innerHTML = `
      <td>${b.boqNumber}</td>
      <td>${b.pricingMode}</td>
      <td><span class="status-pill">${b.status}</span></td>
      <td>${b.itemCount}</td>
      <td class="num">${money(b.totalWeightKg)}</td>`;
    tbody.appendChild(tr);
  }
  container.innerHTML = '';
  container.appendChild(table);
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

  const table = document.createElement('table');
  table.innerHTML = `
    <thead><tr><th>Number</th><th>Status</th><th>Items</th><th class="num">Total</th></tr></thead>
    <tbody></tbody>`;
  const tbody = table.querySelector('tbody');
  for (const q of currentQuotations) {
    const tr = document.createElement('tr');
    tr.style.cursor = 'pointer';
    tr.onclick = () => { location.href = `quotation-editor.html?id=${q.id}`; };
    tr.innerHTML = `
      <td>${q.quotationNumber}</td>
      <td><span class="status-pill">${q.status}</span></td>
      <td>${q.itemCount}</td>
      <td class="num">${money(q.total)}</td>`;
    tbody.appendChild(tr);
  }
  container.innerHTML = '';
  container.appendChild(table);
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
    <thead><tr><th>Number</th><th>Status</th><th>Due</th><th class="num">Total</th><th class="num">Paid</th></tr></thead>
    <tbody></tbody>`;
  const tbody = table.querySelector('tbody');
  for (const inv of currentInvoices) {
    const tr = document.createElement('tr');
    tr.style.cursor = 'pointer';
    tr.onclick = () => { location.href = `invoice-editor.html?id=${inv.id}`; };
    tr.innerHTML = `
      <td>${inv.invoiceNumber}</td>
      <td><span class="status-pill">${inv.status}</span></td>
      <td>${inv.dueDate || '—'}</td>
      <td class="num">${money(inv.total)}</td>
      <td class="num">${money(inv.amountPaid)}</td>`;
    tbody.appendChild(tr);
  }
  container.innerHTML = '';
  container.appendChild(table);
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
    <thead><tr><th>Number</th><th>Status</th><th>Date</th><th>Items</th></tr></thead>
    <tbody></tbody>`;
  const tbody = table.querySelector('tbody');
  for (const dn of currentDeliveryNotes) {
    const tr = document.createElement('tr');
    tr.style.cursor = 'pointer';
    tr.onclick = () => { location.href = `delivery-note-editor.html?id=${dn.id}`; };
    tr.innerHTML = `
      <td>${dn.deliveryNoteNumber}</td>
      <td><span class="status-pill">${dn.status}</span></td>
      <td>${(dn.deliveryDate || '').slice(0, 10)}</td>
      <td>${dn.itemCount}</td>`;
    tbody.appendChild(tr);
  }
  container.innerHTML = '';
  container.appendChild(table);
}

/// Shared renderer for both the Drawings list and the Documents list —
/// same shape (name/type/size/uploaded/description + actions), differing
/// only in whether a Category column shows and which API namespace the
/// row actions call. A missing file (section 38) swaps Open/Reveal/
/// Rename/Archive for Locate File…/Remove Reference.
function renderFileList(containerId, items, api, opts) {
  const container = document.getElementById(containerId);
  if (items.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>${opts.emptyTitle}</h2><p>${opts.emptyBody}</p></div>`;
    return;
  }

  const headerCells = ['Name', ...(opts.showCategory ? ['Category'] : []), 'Type', 'Size', 'Uploaded', 'Description', ''];
  const table = document.createElement('table');
  table.innerHTML = `<thead><tr>${headerCells.map((h) => `<th>${h}</th>`).join('')}</tr></thead><tbody></tbody>`;
  const tbody = table.querySelector('tbody');

  for (const item of items) {
    const tr = document.createElement('tr');
    const missingBadge = item.fileExists ? '' : ' <span class="status-pill" style="color:var(--danger);">File unavailable</span>';
    const categoryCell = opts.showCategory ? `<td>${esc(item.category)}</td>` : '';
    // The name shown is the file's name in Finder; the name it was
    // uploaded under is kept underneath when different (section 33).
    const shownName = item.storedFilename || item.originalName;
    const uploadedAs = item.originalName && item.originalName !== shownName
      ? `<div class="sub muted">Uploaded as ${esc(item.originalName)}</div>` : '';
    tr.innerHTML = `
      <td>${esc(shownName)}${missingBadge}${uploadedAs}</td>
      ${categoryCell}
      <td>${esc(item.fileType)}</td>
      <td>${formatFileSize(item.fileSizeBytes)}</td>
      <td>${(item.uploadedAt || '').slice(0, 10)}</td>
      <td><input type="text" class="desc-input" value="${(item.description || '').replace(/"/g, '&quot;')}" placeholder="Add a description" /></td>
      <td class="file-actions"></td>`;

    tr.querySelector('.desc-input').addEventListener('change', async (e) => {
      await api.updateDescription(item.id, e.target.value || null);
    });

    const actionsCell = tr.querySelector('.file-actions');
    // Right-click offers the same actions as the row's buttons.
    tr.addEventListener('contextmenu', (e) => {
      const buttons = Array.from(actionsCell.querySelectorAll('button'));
      window.showContextMenu(e, buttons.map((b) => ({ label: b.textContent.trim(), action: () => b.click(), danger: /archive|remove/i.test(b.textContent) })));
    });
    if (item.fileExists) {
      actionsCell.innerHTML = `<button class="open-btn">Open</button> <button class="reveal-btn">Reveal</button> <button class="rename-btn">Rename</button> <button class="replace-btn">Replace…</button> <button class="archive-btn">Archive</button>`;
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
        const newName = prompt('New name for this file:', current);
        if (!newName) return;
        const result = await api.rename(item.id, newName);
        if (!result.ok) alert(result.error);
        await opts.refresh();
      });
      actionsCell.querySelector('.archive-btn').addEventListener('click', async () => {
        if (!confirm(`Archive "${shownName}"? It will no longer show in this list.`)) return;
        await api.archive(item.id);
        await opts.refresh();
      });
    } else {
      actionsCell.innerHTML = `<button class="locate-btn">Locate File…</button> <button class="remove-ref-btn">Remove Reference</button>`;
      actionsCell.querySelector('.locate-btn').addEventListener('click', async () => {
        const result = await api.relink(item.id);
        if (result && !result.ok) alert(result.error);
        await opts.refresh();
      });
      actionsCell.querySelector('.remove-ref-btn').addEventListener('click', async () => {
        if (!confirm("Remove this reference? This only removes it from ScaffoldPro's records, not any file on disk.")) return;
        await api.removeReference(item.id);
        await opts.refresh();
      });
    }

    tbody.appendChild(tr);
  }

  container.innerHTML = '';
  container.appendChild(table);
}

async function refreshDrawingList() {
  const drawings = await window.api.drawings.listForProject(currentProject.id);
  fileCounts.drawings = drawings.length;
  setCount('files', fileCounts.drawings + fileCounts.documents);
  renderFileList('drawing-list', drawings, window.api.drawings, {
    emptyTitle: 'No drawings yet',
    emptyBody: 'Use "Upload Drawing" above to add one.',
    showCategory: false,
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
    refresh: refreshDocumentList,
  });
}

async function createNewBOQ() {
  const pricingMode = confirm('Use Rental pricing? (Cancel for Sale pricing)') ? 'Rental' : 'Sale';
  const boq = await window.api.boq.create(currentProject.id, currentProject.projectNumber, pricingMode);
  location.href = `boq-editor.html?id=${boq.id}`;
}

async function createNewQuotation() {
  let sourceBOQId = null;
  let pricingMode = 'Rental';
  if (currentBOQs.length > 0) {
    const mostRecent = currentBOQs[0];
    const useBoq = confirm(`Create this quotation from BOQ ${mostRecent.boqNumber}? Cancel to start blank instead.`);
    if (useBoq) sourceBOQId = mostRecent.id;
  }
  if (!sourceBOQId) {
    pricingMode = confirm('Use Rental pricing for this quotation? (Cancel for Sale pricing)') ? 'Rental' : 'Sale';
  }
  const quotation = await window.api.quotations.create(currentProject.id, currentProject.projectNumber, sourceBOQId, pricingMode);
  location.href = `quotation-editor.html?id=${quotation.id}`;
}

async function createNewInvoice() {
  let sourceQuotationId = null;
  if (currentQuotations.length > 0) {
    const mostRecent = currentQuotations[0];
    const useQuotation = confirm(`Create this invoice from Quotation ${mostRecent.quotationNumber}? Cancel to start blank instead.`);
    if (useQuotation) sourceQuotationId = mostRecent.id;
  }
  const invoice = await window.api.invoices.create(currentProject.id, currentProject.projectNumber, sourceQuotationId);
  location.href = `invoice-editor.html?id=${invoice.id}`;
}

async function createNewDeliveryNote() {
  let sourceQuotationId = null;
  let sourceInvoiceId = null;
  if (currentInvoices.length > 0) {
    const mostRecent = currentInvoices[0];
    const useInvoice = confirm(`Create this delivery note from Invoice ${mostRecent.invoiceNumber}? Cancel to choose another source.`);
    if (useInvoice) sourceInvoiceId = mostRecent.id;
  }
  if (!sourceInvoiceId && currentQuotations.length > 0) {
    const mostRecent = currentQuotations[0];
    const useQuotation = confirm(`Create this delivery note from Quotation ${mostRecent.quotationNumber}? Cancel to start blank instead.`);
    if (useQuotation) sourceQuotationId = mostRecent.id;
  }
  const note = await window.api.deliveryNotes.create(currentProject.id, currentProject.projectNumber, sourceQuotationId, sourceInvoiceId);
  location.href = `delivery-note-editor.html?id=${note.id}`;
}


// ---------- Tabs, overview, edit sheet, history (sections 15, 17, 45) ----------

const fileCounts = { drawings: 0, documents: 0 };

function esc(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function setCount(tab, n) {
  const el = document.getElementById(`count-${tab}`);
  if (el) el.textContent = n > 0 ? String(n) : '';
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
  return isNaN(d) ? value : d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
}

function formatWhen(iso) {
  const d = new Date(iso);
  return isNaN(d) ? iso : d.toLocaleString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

function renderProjectHeader() {
  const p = currentProject;
  document.title = `${p.projectNumber} — ScaffoldPro`;
  document.getElementById('project-header').innerHTML = `
    <div class="eyebrow">Project ${esc(p.projectNumber)}</div>
    <h1>${esc(p.name)}</h1>
    <div class="subtitle">
      ${p.client ? `<a href="clients.html?id=${p.client.id}">${esc(p.client.companyName)}</a>` : 'No client'} ·
      ${p.site ? `<a href="sites.html?id=${p.site.id}">${esc(p.site.name)}</a>` : 'No site'}
    </div>`;
  renderOverview();
}

function renderOverview() {
  const p = currentProject;
  const rows = [
    ['Project Number', p.projectNumber],
    ['Status', p.status],
    ['Client', p.client ? p.client.companyName : '—'],
    ['Site', p.site ? [p.site.name, p.site.address].filter(Boolean).join(', ') : '—'],
    ['Project Manager', p.projectManager || '—'],
    ['Start Date', formatDay(p.startDate)],
    ['Expected Completion', formatDay(p.expectedCompletionDate)],
    ['Created', formatDay(p.createdAt)],
  ];
  document.getElementById('overview-details').innerHTML =
    rows.map(([k, v]) => `<dt>${k}</dt><dd>${esc(v)}</dd>`).join('');
  const desc = document.getElementById('overview-description');
  desc.textContent = p.projectDescription || 'No description yet.';
  desc.classList.toggle('muted', !p.projectDescription);
  const notes = document.getElementById('overview-notes');
  notes.textContent = p.internalNotes || 'No internal notes.';
  notes.classList.toggle('muted', !p.internalNotes);
}

function runQuickAction(action) {
  switch (action) {
    case 'new-boq': document.getElementById('new-boq-btn').click(); break;
    case 'new-quotation': document.getElementById('new-quotation-btn').click(); break;
    case 'new-invoice': document.getElementById('new-invoice-btn').click(); break;
    case 'new-delivery-note': document.getElementById('new-delivery-note-btn').click(); break;
    case 'upload-drawing': showTab('files'); document.getElementById('upload-drawing-btn').click(); break;
    case 'upload-document': showTab('files'); document.getElementById('upload-document-btn').click(); break;
    default: break;
  }
}

async function refreshHistory() {
  const entries = await window.api.activity.listForProject(currentProject.id);
  const render = (list) => list.length === 0
    ? '<div class="empty-state compact"><p>No activity recorded yet.</p></div>'
    : `<table class="history"><thead><tr><th>When</th><th>What</th><th>Reference</th></tr></thead><tbody>${
        list.map((e) => `<tr><td class="nowrap muted">${formatWhen(e.createdAt)}</td><td>${esc(e.action)}</td><td>${esc(e.reference || '')}</td></tr>`).join('')
      }</tbody></table>`;
  document.getElementById('history-list').innerHTML = render(entries);
  document.getElementById('overview-activity').innerHTML = render(entries.slice(0, 5));
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
    $('e-error').classList.add('hidden');
    $('edit-modal').classList.remove('hidden');
    $('e-name').focus();
  });

  $('e-cancel-btn').addEventListener('click', () => $('edit-modal').classList.add('hidden'));
  $('e-save-btn').addEventListener('click', async () => {
    const payload = { clientId: $('e-clientId').value, siteId: $('e-siteId').value };
    for (const f of fields) payload[f] = $(`e-${f}`).value;
    const result = await window.api.projects.update(currentProject.id, payload);
    if (!result.ok) {
      $('e-error').textContent = result.error;
      $('e-error').classList.remove('hidden');
      return;
    }
    $('edit-modal').classList.add('hidden');
    currentProject = await window.api.projects.get(currentProject.projectNumber);
    renderProjectHeader();
    await refreshHistory();
  });
  $('edit-modal').addEventListener('keydown', (e) => { if (e.key === 'Escape') $('edit-modal').classList.add('hidden'); });
}

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
  for (const b of document.querySelectorAll('.quick-actions [data-action]')) {
    b.addEventListener('click', () => runQuickAction(b.dataset.action));
  }

  const statusSelect = document.getElementById('status-select');
  statusSelect.innerHTML = STATUSES.map((s) => `<option value="${s}" ${s === project.status ? 'selected' : ''}>${s}</option>`).join('');
  statusSelect.addEventListener('change', async () => {
    await window.api.projects.updateStatus(project.id, statusSelect.value);
    currentProject.status = statusSelect.value;
    renderOverview();
    await refreshHistory();
  });

  document.getElementById('reveal-folder-btn').addEventListener('click', () => {
    window.api.projects.revealFolder(project.projectNumber);
  });

  document.getElementById('upload-drawing-btn').addEventListener('click', async () => {
    try {
      const result = await window.api.projects.uploadDrawing(project.projectNumber);
      if (result) await refreshDrawingList();
    } catch (e) {
      alert(`The drawing couldn't be added.\n\n${e.message}`);
    }
    await refreshHistory();
  });

  document.getElementById('document-category-select').innerHTML =
    DOCUMENT_CATEGORIES.map((c) => `<option value="${c}">${c}</option>`).join('');

  document.getElementById('upload-document-btn').addEventListener('click', async () => {
    const category = document.getElementById('document-category-select').value;
    try {
      const result = await window.api.documents.upload(project.projectNumber, category);
      if (result) await refreshDocumentList();
    } catch (e) {
      alert(`The document couldn't be added.\n\n${e.message}`);
    }
    await refreshHistory();
  });

  document.getElementById('new-boq-btn').addEventListener('click', createNewBOQ);
  document.getElementById('new-quotation-btn').addEventListener('click', createNewQuotation);
  document.getElementById('new-invoice-btn').addEventListener('click', createNewInvoice);
  document.getElementById('new-delivery-note-btn').addEventListener('click', createNewDeliveryNote);

  await refreshBOQList();
  await refreshQuotationList();
  await refreshInvoiceList();
  await refreshDeliveryNoteList();
  await refreshDrawingList();
  await refreshDocumentList();
  await refreshHistory();
}

init();

'use strict';

const WORKER_DOC_CATEGORIES = ['Employment Contract', 'Certification', 'Training Certificate', 'Identification', 'Other'];
const ADMIN_DOC_CATEGORIES = ['Contracts', 'Insurance', 'Licenses', 'Certificates', 'Company Documents', 'Other'];

let workers = [];
let selectedWorkerId = null;
let adminDocs = [];

function escapeAttr(value) {
  return String(value || '').replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
}

function formatFileSize(bytes) {
  if (!bytes) return '0 KB';
  const kb = bytes / 1024;
  if (kb < 1024) return `${kb.toFixed(0)} KB`;
  return `${(kb / 1024).toFixed(1)} MB`;
}

function daysUntil(dateString) {
  if (!dateString) return null;
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  const target = new Date(`${dateString.slice(0, 10)}T00:00:00`);
  return Math.round((target - today) / 86400000);
}

function expiryLabel(dateString) {
  const days = daysUntil(dateString);
  if (days === null) return '';
  if (days < 0) return `<span class="expiry-expired">Expired ${-days} day${days === -1 ? '' : 's'} ago</span>`;
  if (days === 0) return '<span class="expiry-expired">Expires today</span>';
  if (days <= 30) return `<span class="expiry-soon">Expires in ${days} day${days === 1 ? '' : 's'}</span>`;
  return '';
}

// ---------- Needs Attention (expiry reminders) ----------

async function refreshExpiring() {
  const items = await window.api.adminDocuments.expiring(30);
  const container = document.getElementById('expiring-list');
  if (items.length === 0) {
    container.innerHTML = '<div class="empty-state"><h2>Nothing needs attention</h2><p>No documents are expired or expiring in the next 30 days.</p></div>';
    return;
  }
  const table = document.createElement('table');
  table.innerHTML = '<thead><tr><th>Belongs To</th><th>Document</th><th>Category</th><th>Expiry</th><th></th></tr></thead><tbody></tbody>';
  const tbody = table.querySelector('tbody');
  for (const item of items) {
    const tr = document.createElement('tr');
    tr.innerHTML = `
      <td>${item.ownerName}</td>
      <td>${item.originalName}</td>
      <td>${item.category}</td>
      <td>${window.appDay(item.expiryDate)}</td>
      <td>${expiryLabel(item.expiryDate)}</td>`;
    tbody.appendChild(tr);
  }
  container.innerHTML = '';
  container.appendChild(table);
}

// ---------- Shared document-row renderer ----------

// Used for both worker documents and company documents: name, category,
// type, size, an editable expiry date, an editable description, and the
// same Open / Locate File / Archive — or, for a missing file, Find Moved File… /
// Remove Reference — actions as project drawings and documents.
function renderDocTable(container, docs, api, emptyTitle, emptyBody, refresh) {
  if (docs.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>${emptyTitle}</h2><p>${emptyBody}</p></div>`;
    return;
  }
  const table = document.createElement('table');
  table.innerHTML = '<thead><tr><th>Name</th><th>Category</th><th>Type</th><th>Size</th><th>Expiry</th><th>Description</th><th></th></tr></thead><tbody></tbody>';
  const tbody = table.querySelector('tbody');

  for (const doc of docs) {
    const tr = document.createElement('tr');
    const missing = doc.fileExists ? '' : ' <span class="status-pill" style="color:var(--danger);">File unavailable</span>';
    tr.innerHTML = `
      <td>${doc.originalName}${missing}<br>${expiryLabel(doc.expiryDate)}</td>
      <td>${doc.category}</td>
      <td>${doc.fileType}</td>
      <td>${formatFileSize(doc.fileSizeBytes)}</td>
      <td><input type="date" class="date-input expiry-input" value="${escapeAttr((doc.expiryDate || '').slice(0, 10))}" /></td>
      <td><input type="text" class="desc-input" value="${escapeAttr(doc.description)}" placeholder="Add a description" /></td>
      <td class="file-actions"></td>`;

    const save = async () => {
      const result = await api.update(doc.id, {
        description: tr.querySelector('.desc-input').value || null,
        expiryDate: tr.querySelector('.expiry-input').value || null,
      });
      if (!result.ok) alert(result.error);
      await refresh();
      await refreshExpiring();
    };
    tr.querySelector('.desc-input').addEventListener('change', save);
    tr.querySelector('.expiry-input').addEventListener('change', save);

    const actions = tr.querySelector('.file-actions');
    if (doc.fileExists) {
      actions.innerHTML = '<button class="open-btn">Open</button> <button class="reveal-btn" title="Show this file in Finder">Locate File</button> <button class="archive-btn">Archive</button>';
      actions.querySelector('.open-btn').addEventListener('click', async () => {
        const r = await api.open(doc.id);
        if (!r.ok) alert(r.error);
      });
      actions.querySelector('.reveal-btn').addEventListener('click', async () => {
        const r = await api.reveal(doc.id);
        if (!r.ok) alert(r.error);
      });
      actions.querySelector('.archive-btn').addEventListener('click', async () => {
        if (!await appConfirm(`Archive "${doc.originalName}"? The file stays in Finder; it just won't show here.`)) return;
        await api.archive(doc.id);
        await refresh();
        await refreshExpiring();
      });
    } else {
      actions.innerHTML = '<button class="locate-btn" title="The file has moved: choose where it is now">Find Moved File…</button> <button class="remove-ref-btn">Remove Reference</button>';
      actions.querySelector('.locate-btn').addEventListener('click', async () => {
        const r = await api.relink(doc.id);
        if (r && !r.ok) alert(r.error);
        await refresh();
      });
      actions.querySelector('.remove-ref-btn').addEventListener('click', async () => {
        if (!await appConfirm("Remove this reference? This only removes it from ScaffoldPro's records, not any file on disk.")) return;
        await api.removeReference(doc.id);
        await refresh();
        await refreshExpiring();
      });
    }
    tbody.appendChild(tr);
  }
  container.innerHTML = '';
  container.appendChild(table);
}

// ---------- Workers ----------

async function refreshWorkers() {
  const includeArchived = document.getElementById('show-archived-workers').checked;
  workers = await window.api.workers.list(includeArchived);
  const container = document.getElementById('worker-list');

  if (workers.length === 0) {
    container.innerHTML = '<div class="empty-state"><h2>No workers yet</h2><p>Add a worker to store their contracts and certificates.</p></div>';
    selectedWorkerId = null;
    renderWorkerDetail();
    return;
  }

  const table = document.createElement('table');
  table.innerHTML = '<thead><tr><th>No.</th><th>Name</th><th>Position</th></tr></thead><tbody></tbody>';
  const tbody = table.querySelector('tbody');
  for (const w of workers) {
    const tr = document.createElement('tr');
    tr.style.cursor = 'pointer';
    if (w.id === selectedWorkerId) tr.classList.add('selected');
    tr.innerHTML = `
      <td>${w.workerNumber}</td>
      <td>${w.name}${w.isArchived ? ' <span class="status-pill">Archived</span>' : ''}</td>
      <td>${w.position || '—'}</td>`;
    tr.addEventListener('click', () => {
      selectedWorkerId = w.id;
      refreshWorkers();
    });
    tbody.appendChild(tr);
  }
  container.innerHTML = '';
  container.appendChild(table);

  if (selectedWorkerId && !workers.some((w) => w.id === selectedWorkerId)) selectedWorkerId = null;
  await renderWorkerDetail();
}

async function renderWorkerDetail() {
  const container = document.getElementById('worker-detail');
  const worker = workers.find((w) => w.id === selectedWorkerId);
  if (!worker) {
    container.innerHTML = '<div class="empty-state"><h2>No worker selected</h2><p>Select a worker to see their details and documents.</p></div>';
    return;
  }

  container.innerHTML = `
    <div class="section-toolbar">
      <h2>${worker.workerNumber} — ${worker.name}</h2>
      <div class="controls">
        <button id="worker-reveal-btn">Show Folder</button>
        <button id="worker-archive-btn">${worker.isArchived ? 'Restore' : 'Archive'}</button>
      </div>
    </div>
    <div class="worker-detail-fields">
      <div class="field"><label>Name</label><input type="text" data-field="name" value="${escapeAttr(worker.name)}" /></div>
      <div class="field"><label>Chinese name</label><span class="name-pair"><input type="text" data-field="chineseName" value="${escapeAttr(worker.chineseName)}" placeholder="e.g. 陳大文" />
        <select data-field="honorific" title="On the employment agreement">${['先生', '女士'].map((h) => `<option ${(worker.honorific || '先生') === h ? 'selected' : ''}>${h}</option>`).join('')}</select></span></div>
      <div class="field"><label>ID card no.</label><input type="text" data-field="idNumber" value="${escapeAttr(worker.idNumber)}" placeholder="e.g. A123456(7)" /></div>
      <div class="field"><label>Daily wage (HK$)</label><input type="number" min="0" step="10" data-field="dailyWage" value="${escapeAttr(worker.dailyWage)}" placeholder="e.g. 1300" /></div>
      <div class="field"><label>Position</label><input type="text" data-field="position" value="${escapeAttr(worker.position)}" /></div>
      <div class="field"><label>Phone</label><input type="text" data-field="phone" value="${escapeAttr(worker.phone)}" /></div>
      <div class="field"><label>Email</label><input type="text" data-field="email" value="${escapeAttr(worker.email)}" /></div>
      <div class="field"><label>Start Date</label><input type="date" data-field="startDate" value="${escapeAttr(worker.startDate)}" /></div>
      <div class="field"><label>End Date</label><input type="date" data-field="endDate" value="${escapeAttr(worker.endDate)}" /></div>
      <div class="field full"><label>Notes</label><textarea data-field="notes" rows="2">${escapeAttr(worker.notes)}</textarea></div>
    </div>
    <div id="worker-agreement"></div>
    <div class="section-toolbar">
      <h2 style="font-size:14px;">Documents</h2>
      <div class="controls">
        <select id="worker-doc-category">${WORKER_DOC_CATEGORIES.map((c) => `<option value="${c}">${c}</option>`).join('')}</select>
        <input type="date" id="worker-doc-expiry" class="date-input" title="Expiry date (optional)" />
        <button class="primary" id="upload-worker-doc-btn" title="You can choose several files at once">Upload…</button>
      </div>
    </div>
    <div id="worker-doc-list"></div>`;

  for (const input of container.querySelectorAll('[data-field]')) {
    input.addEventListener('change', async () => {
      const payload = {};
      for (const el of container.querySelectorAll('[data-field]')) payload[el.dataset.field] = el.value;
      const result = await window.api.workers.update(worker.id, payload);
      if (!result.ok) { alert(result.error); }
      await refreshWorkers();
    });
  }

  document.getElementById('worker-reveal-btn').addEventListener('click', () => window.api.workers.revealFolder(worker.id));
  document.getElementById('worker-archive-btn').addEventListener('click', async () => {
    const archiving = !worker.isArchived;
    if (archiving && !await appConfirm(`Archive ${worker.name}? Their record and files are kept; they just won't show in the list.`)) return;
    await window.api.workers.setArchived(worker.id, archiving);
    await refreshWorkers();
    await refreshExpiring();
  });
  document.getElementById('upload-worker-doc-btn').addEventListener('click', async () => {
    const category = document.getElementById('worker-doc-category').value;
    const expiry = document.getElementById('worker-doc-expiry').value;
    try {
      await window.api.workerDocuments.upload(worker.id, category, expiry);
    } catch (e) {
      alert(`Not every document could be added.\n\n${e.message}`);
    }
    await refreshWorkerDocs(worker.id);
    await refreshExpiring();
  });

  await refreshWorkerDocs(worker.id);
  if (window.workerAgreement) await window.workerAgreement.render(document.getElementById('worker-agreement'), worker);
}

async function refreshWorkerDocs(workerId) {
  const docs = await window.api.workerDocuments.list(workerId);
  const container = document.getElementById('worker-doc-list');
  if (!container) return;
  renderDocTable(container, docs, window.api.workerDocuments,
    'No documents yet', 'Upload a contract, certificate, or ID for this worker.',
    () => refreshWorkerDocs(workerId));
}

function openWorkerModal() {
  for (const id of ['w-name', 'w-chineseName', 'w-idNumber', 'w-dailyWage', 'w-position', 'w-phone', 'w-email', 'w-startDate']) {
    document.getElementById(id).value = '';
  }
  document.getElementById('w-error').classList.add('hidden');
  document.getElementById('worker-modal').classList.remove('hidden');
  document.getElementById('w-name').focus();
}

function closeWorkerModal() {
  document.getElementById('worker-modal').classList.add('hidden');
}

async function saveNewWorker() {
  const result = await window.api.workers.create({
    name: document.getElementById('w-name').value,
    chineseName: document.getElementById('w-chineseName').value,
    honorific: document.getElementById('w-honorific').value,
    idNumber: document.getElementById('w-idNumber').value,
    dailyWage: document.getElementById('w-dailyWage').value,
    position: document.getElementById('w-position').value,
    phone: document.getElementById('w-phone').value,
    email: document.getElementById('w-email').value,
    startDate: document.getElementById('w-startDate').value,
  });
  if (!result.ok) {
    const err = document.getElementById('w-error');
    err.textContent = result.error;
    err.classList.remove('hidden');
    return;
  }
  closeWorkerModal();
  selectedWorkerId = result.worker.id;
  await refreshWorkers();
}

// ---------- Company documents ----------

async function refreshAdminDocs() {
  adminDocs = await window.api.adminDocuments.list();
  applyAdminDocSearch();
}

function applyAdminDocSearch() {
  const q = document.getElementById('admin-doc-search').value.trim().toLowerCase();
  const filtered = q === '' ? adminDocs : adminDocs.filter((d) =>
    d.originalName.toLowerCase().includes(q) ||
    d.category.toLowerCase().includes(q) ||
    (d.description || '').toLowerCase().includes(q));
  renderDocTable(document.getElementById('admin-doc-list'), filtered, window.api.adminDocuments,
    adminDocs.length === 0 ? 'No company documents yet' : 'No documents match',
    adminDocs.length === 0 ? 'Upload insurance, licences, contracts and other company paperwork.' : 'Try a different search.',
    refreshAdminDocs);
}

// ---------- init ----------

async function init() {
  document.getElementById('admin-doc-category').innerHTML =
    ADMIN_DOC_CATEGORIES.map((c) => `<option value="${c}">${c}</option>`).join('');

  document.getElementById('new-worker-btn').addEventListener('click', openWorkerModal);
  document.getElementById('w-cancel-btn').addEventListener('click', closeWorkerModal);
  document.getElementById('w-save-btn').addEventListener('click', saveNewWorker);
  document.getElementById('show-archived-workers').addEventListener('change', refreshWorkers);

  document.getElementById('upload-admin-doc-btn').addEventListener('click', async () => {
    const category = document.getElementById('admin-doc-category').value;
    const expiry = document.getElementById('admin-doc-expiry').value;
    let result = null;
    try {
      result = await window.api.adminDocuments.upload(category, expiry);
    } catch (e) {
      alert(`Not every document could be added.\n\n${e.message}`);
    }
    if (result) document.getElementById('admin-doc-expiry').value = '';
    await refreshAdminDocs();
    await refreshExpiring();
  });
  document.getElementById('admin-doc-search').addEventListener('input', applyAdminDocSearch);

  // Arriving from global search (⌘K): admin.html?worker=<id> opens that worker.
  const wantedWorker = new URLSearchParams(location.search).get('worker');
  if (wantedWorker) selectedWorkerId = wantedWorker;

  await refreshExpiring();
  await refreshWorkers();
  if (wantedWorker && !workers.some((w) => w.id === wantedWorker)) {
    document.getElementById('show-archived-workers').checked = true;
    selectedWorkerId = wantedWorker;
    await refreshWorkers();
  }
  await refreshAdminDocs();
}

init();

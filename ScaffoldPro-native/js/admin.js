'use strict';

const ADMIN_DOC_CATEGORIES = ['Contracts', 'Insurance', 'Licenses', 'Certificates', 'Company Documents', 'Other'];

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
    if (item.kind === 'Worker') {
      tr.classList.add('clickable');
      tr.title = 'Open on the Workers page';
      tr.addEventListener('click', () => (window.appNavigate || ((h) => { location.href = h; }))('workers.html'));
    }
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
        await api.archive(doc.id);
        await refresh();
        await refreshExpiring();
        if (window.appUndoHint) window.appUndoHint(`Archived “${doc.originalName}” (the file stays in Finder)`);
      });
    } else {
      actions.innerHTML = '<button class="locate-btn" title="The file has moved: choose where it is now">Find Moved File…</button> <button class="remove-ref-btn">Remove Reference</button>';
      actions.querySelector('.locate-btn').addEventListener('click', async () => {
        const r = await api.relink(doc.id);
        if (r && !r.ok) alert(r.error);
        await refresh();
      });
      actions.querySelector('.remove-ref-btn').addEventListener('click', async () => {
        await api.removeReference(doc.id);
        await refresh();
        await refreshExpiring();
        if (window.appUndoHint) window.appUndoHint('Reference removed (no file was deleted)');
      });
    }
    tbody.appendChild(tr);
  }
  container.innerHTML = '';
  container.appendChild(table);
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

  // Workers have their own page now: an old link to one goes there.
  const wantedWorker = new URLSearchParams(location.search).get('worker');
  if (wantedWorker) { location.replace(`workers.html?worker=${encodeURIComponent(wantedWorker)}`); return; }

  await refreshExpiring();
  await refreshAdminDocs();
}

init();

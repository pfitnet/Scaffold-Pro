'use strict';

// Shared engine for the Clients and Sites pages (sections 9-10): list with
// search and "show archived", a create/edit sheet, archive/restore, and
// the record's projects and documents. Each page supplies a config.

function escapeHTML(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function moneyText(value) {
  return Number(value || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function initPartyPage(config) {
  let all = [];
  let editing = null; // null = creating

  const $ = (id) => document.getElementById(id);

  function render() {
    const q = $('search-box').value.trim().toLowerCase();
    const rows = q === '' ? all : all.filter((r) => config.searchText(r).toLowerCase().includes(q));
    const container = $('list-container');
    if (rows.length === 0) {
      container.innerHTML = all.length === 0
        ? `<div class="empty-state"><h2>${config.emptyTitle}</h2><p>${config.emptyBody}</p>
             <button class="primary" id="empty-new-btn">${config.newLabel}</button></div>`
        : `<div class="empty-state"><h2>No matches</h2><p>Try a different search.</p></div>`;
      const b = $('empty-new-btn');
      if (b) b.addEventListener('click', () => openSheet(null));
      return;
    }
    const table = document.createElement('table');
    table.innerHTML = `<thead><tr>${config.columns.map((c) => `<th>${c.title}</th>`).join('')}</tr></thead><tbody></tbody>`;
    const tbody = table.querySelector('tbody');
    for (const r of rows) {
      const tr = document.createElement('tr');
      tr.style.cursor = 'pointer';
      tr.innerHTML = config.columns.map((c) => `<td>${c.value(r)}</td>`).join('');
      tr.addEventListener('click', () => openSheet(r));
      tbody.appendChild(tr);
    }
    container.innerHTML = '';
    container.appendChild(table);
  }

  async function refresh() {
    all = await config.api.list($('show-archived').checked);
    render();
  }

  async function openSheet(record) {
    editing = record;
    $('sheet-title').textContent = record ? config.titleOf(record) : config.newTitle;
    for (const f of config.fields) {
      const el = $(`f-${f}`);
      el.value = record ? (record[f] ?? '') : '';
    }
    $('form-error').classList.add('hidden');
    $('archive-btn').classList.toggle('hidden', !record);
    if (record) $('archive-btn').textContent = record.isArchived ? 'Restore' : 'Archive';
    $('related').innerHTML = '';
    $('modal-backdrop').classList.remove('hidden');
    $(`f-${config.fields[0]}`).focus();
    if (record) await renderRelated(record);
  }

  function closeSheet() {
    $('modal-backdrop').classList.add('hidden');
    if (location.search) history.replaceState(null, '', location.pathname);
  }

  async function renderRelated(record) {
    const detail = await config.api.detail(record.id);
    const projects = detail.projects.length === 0
      ? '<p class="small-note">No projects yet.</p>'
      : `<table><thead><tr><th>Project</th><th>Name</th><th>Status</th></tr></thead><tbody>${
          detail.projects.map((p) => `<tr class="link-row" data-url="project-detail.html?number=${p.projectNumber}">
            <td>${p.projectNumber}</td><td>${escapeHTML(p.name)}</td><td><span class="status-pill">${p.status}</span></td></tr>`).join('')
        }</tbody></table>`;
    const docs = detail.documents.length === 0
      ? '<p class="small-note">No documents yet.</p>'
      : `<table><thead><tr><th>Document</th><th>Type</th><th>Project</th><th>Status</th><th class="num">Amount</th></tr></thead><tbody>${
          detail.documents.slice(0, 30).map((d) => `<tr class="link-row" data-url="${d.url}">
            <td>${escapeHTML(d.number)}</td><td>${d.kind}</td><td>${d.projectNumber}</td>
            <td><span class="status-pill ${d.isOverdue ? 'pill-danger' : ''}">${d.status}</span></td>
            <td class="num">${d.amount == null ? '—' : moneyText(d.amount)}</td></tr>`).join('')
        }</tbody></table>`;
    $('related').innerHTML = `<h3 class="related-title">Projects</h3>${projects}<h3 class="related-title">Documents</h3>${docs}`;
    for (const tr of $('related').querySelectorAll('.link-row')) {
      tr.addEventListener('click', () => { location.href = tr.dataset.url; });
    }
  }

  async function save() {
    const payload = {};
    for (const f of config.fields) payload[f] = $(`f-${f}`).value.trim();
    const err = $('form-error');
    if (!payload[config.fields[0]]) {
      err.textContent = config.requiredMessage;
      err.classList.remove('hidden');
      $(`f-${config.fields[0]}`).focus();
      return;
    }
    if (editing) {
      const result = await config.api.update(editing.id, payload);
      if (!result.ok) { err.textContent = result.error; err.classList.remove('hidden'); return; }
    } else {
      await config.api.create(payload);
    }
    closeSheet();
    await refresh();
  }

  async function toggleArchive() {
    if (!editing) return;
    const archiving = !editing.isArchived;
    if (archiving && !await appConfirm(`Archive "${config.titleOf(editing)}"? It stays linked to its projects and documents, but won't appear in lists or when creating new projects.`)) return;
    await config.api.setArchived(editing.id, archiving);
    closeSheet();
    await refresh();
  }

  $('new-btn').addEventListener('click', () => openSheet(null));
  $('cancel-btn').addEventListener('click', closeSheet);
  $('save-btn').addEventListener('click', save);
  $('archive-btn').addEventListener('click', toggleArchive);
  $('search-box').addEventListener('input', render);
  $('show-archived').addEventListener('change', refresh);
  $('modal-backdrop').addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeSheet();
    if (e.key === 'Enter' && e.target.tagName === 'INPUT') save();
  });

  (async () => {
    await refresh();
    if (new URLSearchParams(location.search).get('new') === '1') { openSheet(null); return; }
    const wanted = new URLSearchParams(location.search).get('id');
    if (wanted) {
      if (!all.some((r) => r.id === wanted)) { $('show-archived').checked = true; await refresh(); }
      const record = all.find((r) => r.id === wanted);
      if (record) openSheet(record);
    }
  })();
}

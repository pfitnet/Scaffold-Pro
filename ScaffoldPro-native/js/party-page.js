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

// On the Clients & Sites page there are two at once: each sheet's ids
// start with config.prefix ("c-", "s-"), and config.onChange(all) draws
// the page instead of the table. Returns { open, openNew, refresh, all }.
function initPartyPage(config) {
  let all = [];
  let editing = null; // null = creating

  const P = config.prefix || '';
  const $ = (id) => document.getElementById(P + id);
  // The page's own search box, "Show archived" and list (not per sheet).
  const page = (id) => document.getElementById(id);

  function render() {
    if (config.onChange) { config.onChange(all); return; }
    const q = page('search-box').value.trim().toLowerCase();
    const rows = q === '' ? all : all.filter((r) => config.searchText(r).toLowerCase().includes(q));
    const container = page('list-container');
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
    all = await config.api.list(page('show-archived').checked);
    render();
  }
  // ⌘Z / ⌘Y redraw the page with this, not a reload (js/undo.js).
  window.appRefresh = refresh;

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
    if (config.onClose) config.onClose();
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
      : `<table><thead><tr><th>Document</th><th>Type</th><th>Project</th><th>Status</th><th>Created By</th><th class="num">Amount</th></tr></thead><tbody>${
          detail.documents.slice(0, 30).map((d) => `<tr class="link-row" data-url="${d.url}">
            <td>${escapeHTML(d.number)}</td><td>${d.kind}</td><td>${d.projectNumber}</td>
            <td><span class="status-pill ${d.isOverdue ? 'pill-danger' : ''}">${d.status}</span></td>
            ${window.createdByCell(d)}
            <td class="num">${d.amount == null ? '—' : moneyText(d.amount)}</td></tr>`).join('')
        }</tbody></table>`;
    $('related').innerHTML = `<h3 class="related-title">Projects</h3>${projects}<h3 class="related-title">Documents</h3>${docs}`;
    for (const tr of $('related').querySelectorAll('.link-row')) {
      tr.addEventListener('click', () => { window.goTo(tr.dataset.url); });
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
    const title = config.titleOf(editing);
    await config.api.setArchived(editing.id, archiving);
    closeSheet();
    await refresh();
    if (archiving) if (window.appUndoHint) window.appUndoHint(`Archived “${title}” (still linked to its projects)`);
  }

  // Excel: export the list (archived ones too when they're shown), or
  // import a file — matched by reference, else by name; shown first.
  const what = config.kind === 'sites' ? 'site' : 'client';
  async function exportExcel() {
    const r = await window.api.parties.exportXLSX(config.kind, page('show-archived').checked);
    if (r && r.ok === false) await appAlert(r.error);
  }
  async function importExcel() {
    const p = await window.api.parties.importPreview(config.kind);
    if (!p) return;
    if (!p.ok) { await appAlert(`Nothing was imported.\n\n${p.error}`); return; }
    const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
    const lines = [
      `Import ${plural(p.rowsFound, what)} from “${p.fileName}”?`,
      '',
      `${plural(p.toAdd, `new ${what}`)} will be added and ${plural(p.toUpdate, `existing ${what}`)} updated (matched by reference, or else by name). Blank cells leave what’s already there.`,
      '',
      `Columns used: ${p.columns.join(', ')}.`,
    ];
    if (p.samples && p.samples.length) lines.push('', ...p.samples.map((x) => `• ${x}`));
    if (!await appConfirm(lines.join('\n'), { ok: 'Import' })) return;
    const r = await window.api.parties.importApply(p.token);
    if (!r || !r.ok) { await appAlert((r && r.error) || 'The import didn’t finish.'); return; }
    await refresh();
    const done = `${plural(r.added, what)} added, ${plural(r.updated, what)} updated.`;
    await appAlert(r.skipped && r.skipped.length ? `${done}\n\nNot imported:\n${r.skipped.join('\n')}` : done);
  }
  if ($('import-xlsx-btn')) $('import-xlsx-btn').addEventListener('click', importExcel);
  if ($('export-xlsx-btn')) $('export-xlsx-btn').addEventListener('click', exportExcel);

  if ($('new-btn')) $('new-btn').addEventListener('click', () => openSheet(null));
  $('cancel-btn').addEventListener('click', closeSheet);
  $('save-btn').addEventListener('click', save);
  $('archive-btn').addEventListener('click', toggleArchive);
  if (!config.onChange) {
    page('search-box').addEventListener('input', render);
    page('show-archived').addEventListener('change', refresh);
  }
  $('modal-backdrop').addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeSheet();
    if (e.key === 'Enter' && e.target.tagName === 'INPUT') save();
  });

  const params = config.params || { id: 'id', new: 'new' };
  const ready = (async () => {
    await refresh();
    const q = new URLSearchParams(location.search);
    if (q.get(params.new) === '1') { openSheet(null); return; }
    const wanted = q.get(params.id);
    if (wanted) {
      if (!all.some((r) => r.id === wanted)) { page('show-archived').checked = true; await refresh(); }
      const record = all.find((r) => r.id === wanted);
      if (record) openSheet(record);
    }
  })();

  return { open: openSheet, openNew: () => openSheet(null), refresh, all: () => all, ready, importExcel, exportExcel };
}

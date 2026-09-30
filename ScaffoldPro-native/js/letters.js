'use strict';

// Letters: every letter, newest first, with a search and a project filter.
// "+ New Letter" (optionally for a project and client) opens the editor.

let letters = [];
let projects = [];
let clients = [];

function esc(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function dayText(iso) {
  const d = new Date(iso || '');
  return isNaN(d) ? '' : d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
}

const PILL = { Issued: 'pill-success', Cancelled: 'pill-danger', Draft: '' };

function render() {
  const q = document.getElementById('search-box').value.trim().toLowerCase();
  const list = letters.filter((l) => !q || `${l.letterNumber} ${l.subject || ''} ${l.recipientName || ''} ${l.projectNumber || ''} ${l.projectName || ''}`.toLowerCase().includes(q));
  const box = document.getElementById('list-container');
  if (!list.length) {
    box.innerHTML = letters.length
      ? '<div class="empty-state"><h2>No letters match</h2></div>'
      : '<div class="empty-state"><h2>No letters yet</h2><p>Use “+ New Letter” to write one on the letterhead.</p></div>';
    return;
  }
  box.innerHTML = `<table>
    <thead><tr><th>Letter No.</th><th>Date</th><th>Subject</th><th>To</th><th>Project</th><th>Status</th></tr></thead>
    <tbody>${list.map((l) => `<tr class="clickable" data-id="${esc(l.id)}">
      <td><b>${esc(l.letterNumber)}</b></td><td>${dayText(l.letterDate)}</td><td>${esc(l.subject || '—')}</td>
      <td>${esc(l.recipientName || '—')}</td><td>${l.projectNumber ? `${esc(l.projectNumber)} ${esc(l.projectName || '')}` : '—'}</td>
      <td><span class="status-pill ${PILL[l.status] || ''}">${esc(l.status)}</span></td></tr>`).join('')}</tbody></table>`;
  for (const tr of box.querySelectorAll('tr[data-id]')) {
    tr.style.cursor = 'pointer';
    tr.addEventListener('click', () => { location.href = `letter-editor.html?id=${encodeURIComponent(tr.dataset.id)}`; });
  }
}

async function load() {
  letters = (await window.api.letters.list(document.getElementById('project-filter').value || null)) || [];
  render();
}

function openNew() {
  const filter = document.getElementById('project-filter').value;
  document.getElementById('nl-project').innerHTML = '<option value="">Choose the project…</option>' +
    projects.map((p) => `<option value="${esc(p.id)}">${esc(p.projectNumber)} — ${esc(p.name)}</option>`).join('');
  document.getElementById('nl-project').value = filter || '';
  document.getElementById('nl-client').innerHTML = '<option value="">— The project’s client, or none —</option>' +
    clients.map((c) => `<option value="${esc(c.id)}">${esc(c.companyName)}</option>`).join('');
  document.getElementById('nl-number-note').textContent = 'The letter is numbered from the project code, e.g. L26001-001 for project 26001 (Settings › Document Numbers).';
  document.getElementById('nl-error').classList.add('hidden');
  document.getElementById('new-letter-modal').classList.remove('hidden');
}

async function create() {
  if (!document.getElementById('nl-project').value) {
    const err = document.getElementById('nl-error');
    err.textContent = 'Choose the project the letter is for.';
    err.classList.remove('hidden');
    return;
  }
  const r = await window.api.letters.create({
    projectId: document.getElementById('nl-project').value || null,
    clientId: document.getElementById('nl-client').value || null,
  });
  if (!r || !r.ok) {
    const err = document.getElementById('nl-error');
    err.textContent = (r && r.error) || 'The letter couldn’t be created.';
    err.classList.remove('hidden');
    return;
  }
  location.href = `letter-editor.html?id=${encodeURIComponent(r.id)}`;
}

async function init() {
  [projects, clients] = await Promise.all([window.api.projects.list(), window.api.clients.list()]);
  projects = projects || [];
  clients = (clients || []).filter((c) => !c.isArchived);
  const filter = document.getElementById('project-filter');
  filter.innerHTML = '<option value="">All letters</option>' +
    projects.map((p) => `<option value="${esc(p.id)}">${esc(p.projectNumber)} — ${esc(p.name)}</option>`).join('');
  // letters.html?project=<id>: that project's letters.
  const wanted = new URLSearchParams(location.search).get('project');
  if (wanted && projects.some((p) => p.id === wanted)) filter.value = wanted;
  filter.addEventListener('change', load);
  document.getElementById('search-box').addEventListener('input', render);
  document.getElementById('new-letter-btn').addEventListener('click', openNew);
  document.getElementById('nl-cancel').addEventListener('click', () => document.getElementById('new-letter-modal').classList.add('hidden'));
  document.getElementById('nl-create').addEventListener('click', create);
  await load();
}

init();

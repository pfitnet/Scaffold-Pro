'use strict';

let allProjects = [];

function renderProjects(projects) {
  const container = document.getElementById('list-container');
  if (projects.length === 0) {
    container.innerHTML = `
      <div class="empty-state">
        <h2>No projects yet</h2>
        <p>Create your first project — a number is assigned automatically.</p>
        <button class="primary" onclick="document.getElementById('new-project-btn').click()">+ New Project</button>
      </div>`;
    return;
  }
  const table = document.createElement('table');
  table.innerHTML = `
    <thead><tr><th>Number</th><th>Name</th><th>Client</th><th>Site</th><th>Status</th><th>Created By</th></tr></thead>
    <tbody></tbody>`;
  const tbody = table.querySelector('tbody');
  for (const p of projects) {
    const tr = document.createElement('tr');
    tr.style.cursor = 'pointer';
    tr.onclick = () => { location.href = `project-detail.html?number=${p.projectNumber}`; };
    tr.addEventListener('contextmenu', (e) => window.showContextMenu(e, [
      { label: 'Open Project', action: () => { location.href = `project-detail.html?number=${p.projectNumber}`; } },
      { label: 'Show in Finder', action: () => window.api.projects.revealFolder(p.projectNumber) },
      'separator',
      { label: 'New Quotation…', action: () => { location.href = `project-detail.html?number=${p.projectNumber}&tab=quotations`; } },
      { label: 'Copy Project Number', action: () => window.copyText(p.projectNumber) },
    ]));
    tr.innerHTML = `
      <td>${p.projectNumber}</td>
      <td>${p.name}</td>
      <td>${p.clientName || '—'}</td>
      <td>${p.siteName || '—'}</td>
      <td><span class="status-pill">${p.status}</span></td>
      ${window.createdByCell(p)}`;
    tbody.appendChild(tr);
  }
  container.innerHTML = '';
  container.appendChild(table);
}

async function refresh() {
  allProjects = await window.api.projects.list();
  applySearch();
}

function applySearch() {
  const q = document.getElementById('search-box').value.trim().toLowerCase();
  const filtered = q === '' ? allProjects : allProjects.filter(
    (p) => p.name.toLowerCase().includes(q) || p.projectNumber.includes(q)
  );
  renderProjects(filtered);
}

async function openModal() {
  document.getElementById('modal-backdrop').classList.remove('hidden');
  document.getElementById('form-error').classList.add('hidden');
  document.getElementById('f-name').value = '';
  document.getElementById('f-override').checked = false;
  document.getElementById('f-manualNumber').value = '';
  document.getElementById('f-manualNumber').classList.add('hidden');
  for (const f of ['startDate', 'expectedCompletionDate', 'projectManager', 'projectDescription', 'internalNotes']) {
    document.getElementById(`f-${f}`).value = '';
  }
  document.getElementById('f-uploadDrawing').checked = false;

  const proposed = await window.api.projects.proposeNumber();
  document.getElementById('proposed-number').textContent = proposed;
  document.getElementById('proposed-number').dataset.value = proposed;

  const [clients, sites] = await Promise.all([window.api.clients.list(), window.api.sites.list()]);
  document.getElementById('f-client').innerHTML =
    '<option value="">Select a client</option>' + clients.map((c) => `<option value="${c.id}">${c.companyName}</option>`).join('');
  document.getElementById('f-site').innerHTML =
    '<option value="">Select a site</option>' + sites.map((s) => `<option value="${s.id}">${s.name}</option>`).join('');
  // From Clients & Sites (a client dragged onto a site): both chosen already.
  const ps = new URLSearchParams(location.search);
  if (ps.get('client')) document.getElementById('f-client').value = ps.get('client');
  if (ps.get('site')) document.getElementById('f-site').value = ps.get('site');
}
function closeModal() {
  document.getElementById('modal-backdrop').classList.add('hidden');
}

document.getElementById('f-override').addEventListener('change', (e) => {
  document.getElementById('f-manualNumber').classList.toggle('hidden', !e.target.checked);
});

async function saveProject() {
  const name = document.getElementById('f-name').value.trim();
  const clientId = document.getElementById('f-client').value;
  const siteId = document.getElementById('f-site').value;
  const errorEl = document.getElementById('form-error');

  if (!name || !clientId || !siteId) {
    errorEl.textContent = 'Project name, client, and site are all required.';
    errorEl.classList.remove('hidden');
    return;
  }

  const override = document.getElementById('f-override').checked;
  const manualNumber = document.getElementById('f-manualNumber').value.trim();

  const optional = {};
  for (const f of ['startDate', 'expectedCompletionDate', 'projectManager', 'projectDescription', 'internalNotes']) {
    optional[f] = document.getElementById(`f-${f}`).value.trim();
  }

  const result = await window.api.projects.create(Object.assign({
    name,
    clientId,
    siteId,
    overrideNumber: override,
    manualNumber,
  }, optional));

  if (!result.ok) {
    errorEl.textContent = result.error;
    errorEl.classList.remove('hidden');
    return;
  }

  // Section 14: optional drawing upload straight after creation — the
  // native file picker, copied (never moved) into the Drawings folder.
  if (document.getElementById('f-uploadDrawing').checked) {
    await window.api.projects.uploadDrawing(result.project.projectNumber);
  }
  closeModal();
  location.href = `project-detail.html?number=${result.project.projectNumber}${document.getElementById('f-uploadDrawing').checked ? '&tab=files' : ''}`;
}

// ⌘N from the menu bar lands here with ?new=1.
if (new URLSearchParams(location.search).get('new') === '1') {
  setTimeout(() => document.getElementById('new-project-btn').click(), 0);
}

document.getElementById('new-project-btn').addEventListener('click', openModal);
document.getElementById('cancel-btn').addEventListener('click', closeModal);
document.getElementById('save-btn').addEventListener('click', saveProject);
document.getElementById('search-box').addEventListener('input', applySearch);

refresh();

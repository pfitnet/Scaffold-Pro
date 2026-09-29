'use strict';

// Section 7: useful information first, no decorative charts.

function esc(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function money(value) {
  return Number(value || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function day(value) {
  if (!value) return '—';
  const d = new Date(value.length <= 10 ? `${value}T00:00:00` : value);
  return isNaN(d) ? value : d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

function when(iso) {
  const d = new Date(iso);
  if (isNaN(d)) return iso;
  const mins = Math.round((Date.now() - d.getTime()) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins} min ago`;
  if (mins < 60 * 24) return `${Math.round(mins / 60)} h ago`;
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

function statCard(value, label, tone) {
  const el = document.createElement('div');
  el.className = `stat-card${tone ? ` tone-${tone}` : ''}`;
  el.innerHTML = `<div class="value">${value}</div><div class="label">${label}</div>`;
  return el;
}

function table(container, rows, columns, emptyText) {
  const el = document.getElementById(container);
  if (rows.length === 0) {
    el.innerHTML = `<div class="empty-inline">${emptyText}</div>`;
    return;
  }
  el.innerHTML = `<table class="compact"><tbody>${rows.map((r) =>
    `<tr class="link-row" data-url="${r.url}">${columns.map((c) => `<td class="${c.cls || ''}">${c.value(r)}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
  for (const tr of el.querySelectorAll('tr[data-url]')) {
    tr.addEventListener('click', () => { location.href = tr.dataset.url; });
  }
}

let projectsCache = [];

// Issued quotations still waiting for the client's signed copy: upload it
// (or drop it onto the row), or mark it as not needed.
function renderSignedCopies(summary) {
  const block = document.getElementById('signed-block');
  const rows = summary.awaitingSignedCopy || [];
  block.classList.toggle('hidden', rows.length === 0);
  if (rows.length === 0) return;
  const total = summary.awaitingSignedCopyCount || rows.length;
  document.getElementById('signed-title').textContent =
    `Signed Quotations to Upload (${total})`;
  const list = document.getElementById('signed-list');
  list.innerHTML = `<table class="compact signed-table"><tbody>${rows.map((r) => `
    <tr class="link-row signed-row" data-id="${esc(r.id)}" data-url="${esc(r.url)}">
      <td><strong>${esc(r.number)}</strong><div class="sub">${esc([r.clientName, r.projectNumber].filter(Boolean).join(' · '))}</div></td>
      <td>${r.status === 'Invoiced'
        ? '<span class="status-pill pill-warning" title="Already invoiced — going ahead without a signed copy on file">Invoiced, not signed</span>'
        : `<span class="muted">Issued ${day(r.date)}</span>`}</td>
      <td class="num">${summary.currency} ${money(r.amount)}</td>
      <td class="row-actions">
        <button class="primary upload-signed-btn">Upload Signed Copy…</button>
        <button class="not-needed-btn" title="Take it off this list — e.g. the client accepted by email, or won't go ahead">Not Needed</button>
      </td>
    </tr>`).join('')}</tbody></table>
    ${total > rows.length ? `<div class="small-note" style="padding:6px 4px 0;">and ${total - rows.length} more — they appear here as these are done.</div>` : ''}`;
  const refresh = async () => renderSignedCopies(await window.api.dashboard.summary());
  for (const tr of list.querySelectorAll('tr.signed-row')) {
    const id = tr.dataset.id;
    tr.addEventListener('click', () => { location.href = tr.dataset.url; });
    tr.querySelector('.row-actions').addEventListener('click', (e) => e.stopPropagation());
    tr.querySelector('.upload-signed-btn').addEventListener('click', async () => {
      if (await window.signedCopy.upload(id)) await refresh();
    });
    tr.querySelector('.not-needed-btn').addEventListener('click', async () => {
      if (await window.signedCopy.setNotNeeded(id, true)) await refresh();
    });
    window.signedCopy.dropTarget(tr, id, refresh);
  }
}

// "New Quotation / Invoice / Delivery Note" from the Dashboard: pick the
// project, then land on that tab of the project page.
function pickProjectThen(title, tab) {
  const active = projectsCache.filter((p) => p.status !== 'Archived' && p.status !== 'Completed');
  if (active.length === 0) {
    alert('Create a project first.');
    return;
  }
  document.getElementById('pick-project-title').textContent = title;
  document.getElementById('pick-project-select').innerHTML =
    active.map((p) => `<option value="${esc(p.projectNumber)}">${esc(p.projectNumber)} — ${esc(p.name)}</option>`).join('');
  const modal = document.getElementById('pick-project-modal');
  modal.classList.remove('hidden');
  document.getElementById('pick-go-btn').onclick = () => {
    location.href = `project-detail.html?number=${document.getElementById('pick-project-select').value}&tab=${tab}`;
  };
}

async function loadDashboard() {
  document.getElementById('today-line').textContent =
    new Date().toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' });

  const [summary, projects] = await Promise.all([window.api.dashboard.summary(), window.api.projects.list()]);
  projectsCache = projects;
  const cur = summary.currency;

  const grid = document.getElementById('stat-grid');
  grid.appendChild(statCard(summary.activeProjects, 'Active Projects'));
  grid.appendChild(statCard(`${cur} ${money(summary.unpaidTotal)}`, `Unpaid (${summary.unpaidInvoices.length} invoice${summary.unpaidInvoices.length === 1 ? '' : 's'})`));
  grid.appendChild(statCard(summary.overdueCount > 0 ? `${cur} ${money(summary.overdueTotal)}` : '—',
    summary.overdueCount > 0 ? `Overdue (${summary.overdueCount})` : 'Nothing overdue', summary.overdueCount > 0 ? 'danger' : null));
  grid.appendChild(statCard(summary.outstandingQuotations.length, 'Quotations Awaiting Reply'));

  table('unpaid-list', summary.unpaidInvoices, [
    { value: (r) => `<strong>${esc(r.number)}</strong><div class="sub">${esc(r.clientName || r.projectName)}</div>` },
    { value: (r) => r.isOverdue ? `<span class="status-pill pill-danger">Overdue</span>` : `<span class="muted">Due ${day(r.dueDate)}</span>` },
    { cls: 'num', value: (r) => `${cur} ${money(r.balance)}` },
  ], 'No unpaid invoices.');

  table('quotation-list', summary.outstandingQuotations, [
    { value: (r) => `<strong>${esc(r.number)}</strong><div class="sub">${esc(r.clientName || r.projectName)}</div>` },
    { value: (r) => `<span class="muted">${r.dueDate ? `Valid to ${day(r.dueDate)}` : `Sent ${day(r.date)}`}</span>` },
    { cls: 'num', value: (r) => `${cur} ${money(r.amount)}` },
  ], 'No issued quotations waiting for a reply.');

  const recentProjects = projects
    .slice()
    .sort((a, b) => (a.status === 'Active' ? 0 : 1) - (b.status === 'Active' ? 0 : 1) || b.projectNumber.localeCompare(a.projectNumber))
    .slice(0, 6)
    .map((p) => Object.assign({ url: `project-detail.html?number=${p.projectNumber}` }, p));
  table('recent-projects', recentProjects, [
    { value: (p) => `<strong>${esc(p.projectNumber)}</strong><div class="sub">${esc(p.name)}</div>` },
    { value: (p) => `<span class="muted">${esc(p.clientName || '—')}</span>` },
    { value: (p) => `<span class="status-pill">${esc(p.status)}</span>` },
  ], 'No projects yet — press New Project to start.');

  table('recent-docs', summary.recentDocuments, [
    { value: (r) => `<strong>${esc(r.number)}</strong><div class="sub">${esc(r.kind)} · ${esc(r.projectNumber)}</div>` },
    { value: (r) => `<span class="status-pill ${r.isOverdue ? 'pill-danger' : ''}">${esc(r.status)}</span>` },
    { cls: 'muted num', value: (r) => when(r.updatedAt) },
  ], 'No documents yet.');

  table('delivery-list', summary.recentDeliveryNotes, [
    { value: (r) => `<strong>${esc(r.number)}</strong><div class="sub">${esc(r.projectName)}</div>` },
    { value: (r) => `<span class="status-pill">${esc(r.status)}</span>` },
    { cls: 'muted num', value: (r) => day(r.date) },
  ], 'No delivery notes yet.');

  const activity = summary.recentActivity.map((a) => Object.assign({ url: a.projectNumber ? `project-detail.html?number=${a.projectNumber}&tab=history` : 'index.html' }, a));
  table('activity-list', activity, [
    { value: (a) => `${esc(a.action)}<div class="sub">${esc([a.projectNumber, a.reference, a.by].filter(Boolean).join(' · '))}</div>` },
    { cls: 'muted num', value: (a) => when(a.createdAt) },
  ], 'Nothing recorded yet.');

  renderSignedCopies(summary);

  // Expired / expiring worker and company documents (sections 42-43).
  const expiring = await window.api.adminDocuments.expiring(30);
  if (expiring.length > 0) {
    document.getElementById('attention-block').classList.remove('hidden');
    table('attention-list', expiring.slice(0, 8).map((i) => Object.assign({ url: 'admin.html' }, i)), [
      { value: (i) => `<strong>${esc(i.originalName)}</strong><div class="sub">${esc(i.ownerName)} · ${esc(i.category)}</div>` },
      { cls: 'num', value: (i) => i.daysLeft < 0 ? `<span class="status-pill pill-danger">Expired ${-i.daysLeft} day(s) ago</span>`
        : i.daysLeft === 0 ? '<span class="status-pill pill-danger">Expires today</span>' : `<span class="muted">Expires in ${i.daysLeft} day(s)</span>` },
    ], '');
  }

  // Backup reminder: none yet, or the last manual one is a week old.
  const backups = await window.api.backup.list();
  const manual = backups.find((b) => b.kind === 'Manual') || backups[0];
  const daysSince = manual ? Math.floor((Date.now() - new Date(manual.createdAt).getTime()) / 86400000) : null;
  if (projects.length > 0 && (daysSince === null || daysSince >= 7)) {
    const box = document.getElementById('backup-reminder');
    box.innerHTML = `
      <span>${daysSince === null ? 'You haven\u2019t made a backup yet.' : `Your last backup was ${daysSince} days ago.`}
        A backup protects all projects, drawings and documents.</span>
      <button onclick="location.href='settings.html#backup'">Back Up Now…</button>`;
    box.classList.remove('hidden');
  }
}

document.getElementById('qa-quotation').addEventListener('click', () => pickProjectThen('New Quotation — Choose a Project', 'quotations'));
document.getElementById('qa-invoice').addEventListener('click', () => pickProjectThen('New Invoice — Choose a Project', 'invoices'));
document.getElementById('qa-delivery').addEventListener('click', () => pickProjectThen('New Delivery Note — Choose a Project', 'delivery'));
document.getElementById('pick-cancel-btn').addEventListener('click', () => document.getElementById('pick-project-modal').classList.add('hidden'));

loadDashboard();

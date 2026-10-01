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

// "Created by Harry" (in Harry's colour) under a row's number.
function madeBy(r) {
  return r && r.createdBy ? `<div class="sub made-by">Created by ${window.personTag(r.createdBy)}</div>` : '';
}

// A quotation's charges: the monthly charge (rental) over the one-time
// charge (delivery and one-off charges; all of a Sale quotation).
function chargeCell(r, cur) {
  const c = r.charges;
  if (!c) return `${cur} ${money(r.amount)}`;
  const recurring = Object.entries(c.recurring || {}).filter(([, v]) => v)
    .map(([k, v]) => `<div class="charge-line"><span class="charge-label">per ${esc(k.toLowerCase())}</span> ${money(v)}</div>`).join('');
  return `<div class="charge-line"><span class="charge-label">Monthly</span> ${c.monthly ? `${cur} ${money(c.monthly)}` : '<span class="muted">—</span>'}</div>
    <div class="charge-line"><span class="charge-label">One-time</span> ${cur} ${money(c.oneTime)}</div>${recurring}`;
}

// Quotations awaiting reply: issued ones with no signed copy from the
// client yet. Upload the signed copy with the arrow (or drop the PDF or
// photo onto the row), or take it off with the cross when it isn't
// needed (accepted by email, or not going ahead).
function renderAwaitingQuotations(summary) {
  const cur = summary.currency;
  const rows = summary.awaitingSignedCopy || [];
  const total = summary.awaitingSignedCopyCount || rows.length;
  const list = document.getElementById('quotation-list');
  if (rows.length === 0) {
    list.innerHTML = '<div class="empty-inline">No issued quotations waiting for a reply.</div>';
    return;
  }
  list.innerHTML = `<table class="compact"><tbody>${rows.map((r) => `
    <tr class="link-row quote-row" data-id="${esc(r.id)}" data-url="${esc(r.url)}" title="Drop the client’s signed copy (PDF or photo) here to file it">
      <td><strong>${esc(r.number)}</strong><div class="sub">${esc(r.clientName || r.projectName)}</div>${madeBy(r)}</td>
      <td>${r.status === 'Invoiced'
        ? '<span class="status-pill pill-warning" title="Already invoiced — going ahead without a signed copy on file">Invoiced, not signed</span>'
        : `<span class="muted">${r.dueDate ? `Valid to ${day(r.dueDate)}` : `Sent ${day(r.date)}`}</span>`}</td>
      <td class="num">${chargeCell(r, cur)}</td>
      <td class="quote-actions" data-no-icon>
        <button class="icon-btn upload-signed-btn" title="Upload the signed copy…" aria-label="Upload the signed copy">${window.ICONS.upload}</button>
        <button class="icon-btn not-needed-btn" title="Not needed — take it off this list (e.g. accepted by email, or not going ahead)" aria-label="Signed copy not needed">${window.ICONS.dismiss}</button>
      </td>
    </tr>`).join('')}</tbody></table>
    ${total > rows.length ? `<div class="small-note" style="padding:6px 4px 0;">and ${total - rows.length} more</div>` : ''}`;
  const refresh = async () => {
    const fresh = await window.api.dashboard.summary();
    renderAwaitingQuotations(fresh);
    updateAwaitingCount(fresh);
  };
  for (const tr of list.querySelectorAll('tr.quote-row')) {
    const id = tr.dataset.id;
    tr.addEventListener('click', () => { location.href = tr.dataset.url; });
    tr.querySelector('.quote-actions').addEventListener('click', (e) => e.stopPropagation());
    tr.querySelector('.upload-signed-btn').addEventListener('click', async () => {
      if (await window.signedCopy.upload(id)) await refresh();
    });
    tr.querySelector('.not-needed-btn').addEventListener('click', async () => {
      if (await window.signedCopy.setNotNeeded(id, true)) await refresh();
    });
    window.signedCopy.dropTarget(tr, id, refresh);
  }
}

let awaitingCard = null;
function updateAwaitingCount(summary) {
  if (awaitingCard) awaitingCard.querySelector('.value').textContent = summary.awaitingSignedCopyCount || 0;
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
  // Panels as widgets: each person's own order, sizes and hidden ones.
  window.setupWidgets(document.getElementById('dash-grid'), document.getElementById('customise-btn'), summary.userName);
  if (summary.userName) {
    document.getElementById('today-line').insertAdjacentHTML('beforeend', ` · <a href="user.html" class="plain-link">${window.personTag(summary.userName)}</a>`);
  }

  const grid = document.getElementById('stat-grid');
  grid.appendChild(statCard(summary.activeProjects, 'Active Projects'));
  grid.appendChild(statCard(`${cur} ${money(summary.unpaidTotal)}`, `Unpaid (${summary.unpaidInvoices.length} invoice${summary.unpaidInvoices.length === 1 ? '' : 's'})`));
  grid.appendChild(statCard(summary.overdueCount > 0 ? `${cur} ${money(summary.overdueTotal)}` : '—',
    summary.overdueCount > 0 ? `Overdue (${summary.overdueCount})` : 'Nothing overdue', summary.overdueCount > 0 ? 'danger' : null));
  awaitingCard = grid.appendChild(statCard(summary.awaitingSignedCopyCount || 0, 'Quotations Awaiting Reply'));

  table('unpaid-list', summary.unpaidInvoices, [
    { value: (r) => `<strong>${esc(r.number)}</strong><div class="sub">${esc(r.clientName || r.projectName)}</div>${madeBy(r)}` },
    { value: (r) => r.isOverdue ? `<span class="status-pill pill-danger">Overdue</span>` : `<span class="muted">Due ${day(r.dueDate)}</span>` },
    { cls: 'num', value: (r) => `${cur} ${money(r.balance)}` },
  ], 'No unpaid invoices.');

  renderAwaitingQuotations(summary);

  // The projects I've worked on (made, changed, or worked on their documents), most recent first.
  const recentProjects = (summary.myProjects || [])
    .map((p) => Object.assign({ url: `project-detail.html?number=${encodeURIComponent(p.projectNumber)}` }, p));
  table('recent-projects', recentProjects, [
    { value: (p) => `<strong>${esc(p.projectNumber)}</strong><div class="sub">${esc(p.name)}</div>${madeBy(p)}` },
    { value: (p) => `<span class="muted">${esc(p.clientName || '—')}</span><div class="sub">${when(p.lastWorkedAt)}</div>` },
    { value: (p) => `<span class="status-pill">${esc(p.status)}</span>` },
  ], projects.length ? 'None yet — projects you work on show here.' : 'No projects yet — press New Project to start.');

  table('recent-docs', summary.recentDocuments, [
    { value: (r) => `<strong>${esc(r.number)}</strong><div class="sub">${esc(r.kind)} · ${esc(r.projectNumber)}</div>${madeBy(r)}` },
    { value: (r) => `<span class="status-pill ${r.isOverdue ? 'pill-danger' : ''}">${esc(r.status)}</span>` },
    { cls: 'muted num', value: (r) => when(r.lastEditedAt || r.updatedAt) },
  ], 'None yet — documents you work on show here.');

  table('delivery-list', summary.recentDeliveryNotes, [
    { value: (r) => `<strong>${esc(r.number)}</strong><div class="sub">${esc(r.projectName)}</div>${madeBy(r)}` },
    { value: (r) => `<span class="status-pill">${esc(r.status)}</span>` },
    { cls: 'muted num', value: (r) => day(r.date) },
  ], 'None yet — delivery notes you work on show here.');

  const activityRows = (list) => list.map((a) => Object.assign({ url: a.projectNumber ? `project-detail.html?number=${a.projectNumber}&tab=history` : 'index.html' }, a));
  table('activity-list', activityRows(summary.recentActivity), [
    { value: (a) => `${esc(a.action)}<div class="sub">${esc([a.projectNumber, a.reference].filter(Boolean).join(' · '))}</div>` },
    { cls: 'muted num', value: (a) => when(a.createdAt) },
  ], 'Nothing yet.');
  // Everyone else's, with who did it.
  table('team-activity-list', activityRows(summary.teamActivity || []), [
    { value: (a) => `${a.by ? window.personTag(a.by) : '<strong>Someone</strong>'} ${esc(a.action)}<div class="sub">${esc([a.projectNumber, a.reference].filter(Boolean).join(' · '))}</div>` },
    { cls: 'muted num', value: (a) => when(a.createdAt) },
  ], 'Nothing from the rest of the team yet.');

  // Scaffold inspections due in the next 3 days, or overdue.
  const due = summary.inspectionsDue || [];
  document.getElementById('inspections-panel').classList.toggle('hidden', !due.length);
  table('inspections-due-list', due, [
    { value: (d) => `<strong>${esc(d.structure)}</strong><div class="sub">${esc(d.projectNumber)} ${esc(d.projectName)}</div>` },
    { value: (d) => `<span class="status-pill ${d.daysLeft < 0 ? 'pill-danger' : 'pill-warning'}">${d.daysLeft < 0 ? `Overdue ${-d.daysLeft} day${d.daysLeft === -1 ? '' : 's'}` : d.daysLeft === 0 ? 'Due today' : `Due in ${d.daysLeft} day${d.daysLeft === 1 ? '' : 's'}`}</span>` },
    { cls: 'muted num', value: (d) => `Last ${day(d.lastInspected)}` },
  ], '');

  // My open tasks: tick to finish, click to open.
  const taskBox = document.getElementById('my-tasks-list');
  const myTasks = summary.myTasks || [];
  const reloadTasks = async () => {
    const fresh = (await window.api.tasks.list()).filter((r) => r.mine && !r.task.done).slice(0, 8);
    renderMyTasks(fresh);
  };
  const renderMyTasks = (rows) => {
    if (!rows.length) { taskBox.innerHTML = '<div class="empty-inline">Nothing to do — <a href="tasks.html">add a task</a>.</div>'; return; }
    taskBox.innerHTML = `<table class="compact no-sort task-table"><tbody>${rows.map((r) => window.taskRowHTML(r)).join('')}</tbody></table>`;
    window.wireTaskRows(taskBox, rows, reloadTasks, { projects });
  };
  renderMyTasks(myTasks);

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

  // Backup reminder: none yet, or the newest one (of any kind — they're
  // also made by themselves at 12:00 a.m. and p.m.) is a week old.
  const backups = await window.api.backup.list();
  const manual = backups[0];
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

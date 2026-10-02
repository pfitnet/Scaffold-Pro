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

// Each list shows its first 5; "and 7 more" under it shows the rest (and
// "Show fewer" folds it back). `total` when there are more than were sent.
const SHOWN = 5;
const CHEVRON = '<svg viewBox="0 0 12 12" width="11" height="11" aria-hidden="true"><path d="M3 4.5 6 7.5l3-3" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';
// The "and 7 more" / "Show fewer" button's words, count and chevron.
function moreLabel(btn, open, hiddenCount, notSent) {
  btn.classList.toggle('open', open);
  btn.innerHTML = open
    ? `<span>Show fewer</span>${notSent > 0 ? `<span class="more-count">${notSent} older not shown</span>` : ''}${CHEVRON}`
    : `<span>and ${hiddenCount} more</span>${CHEVRON}`;
}

function limitList(box, total) {
  const rows = [...box.querySelectorAll('tbody > tr:not(.task-new-row)')];
  const old = box.querySelector(':scope > .more-btn');
  if (old) old.remove();
  const all = Math.max(rows.length, total || 0);
  if (all <= SHOWN) return;
  const open = box.dataset.expanded === '1';
  rows.forEach((tr, i) => tr.classList.toggle('hidden', !open && i >= SHOWN));
  const more = document.createElement('button');
  more.type = 'button';
  more.className = 'more-btn';
  more.dataset.noIcon = '';
  const notSent = all - rows.length;
  moreLabel(more, open, all - SHOWN, notSent);
  more.addEventListener('click', (e) => {
    e.stopPropagation();
    box.dataset.expanded = open ? '' : '1';
    limitList(box, total);
  });
  box.appendChild(more);
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
  limitList(el);
}

// My recently changed documents, in a bracket per kind (Quotations,
// BOQs, Delivery Notes, Invoices — only the kinds in the list). The 5 most
// recent are shown; "and N more" shows the rest, bracketed the same way.
const DOC_KINDS = [['Quotation', 'Quotations'], ['BOQ', 'BOQs'], ['Delivery Note', 'Delivery Notes'], ['Invoice', 'Invoices']];
function renderRecentDocs(all) {
  const box = document.getElementById('recent-docs');
  if (!all.length) { box.innerHTML = '<div class="empty-inline">None yet — documents you work on show here.</div>'; return; }
  const open = box.dataset.expanded === '1';
  const shown = open ? all : all.slice(0, SHOWN);
  const known = DOC_KINDS.map(([k]) => k);
  const kinds = DOC_KINDS.concat([...new Set(shown.map((r) => r.kind).filter((k) => !known.includes(k)))].map((k) => [k, k]));
  box.innerHTML = kinds.map(([kind, title]) => {
    const rows = shown.filter((r) => r.kind === kind);
    if (!rows.length) return '';
    return `<section class="doc-bracket"><div class="doc-bracket-head"><span>${esc(title)}</span><span class="doc-bracket-count">${rows.length}</span></div>
      <table class="compact"><tbody>${rows.map((r) => `<tr class="link-row" data-url="${esc(r.url)}">
        <td><strong>${esc(r.number)}</strong><div class="sub">${esc(r.projectNumber)}${r.projectName ? ` ${esc(r.projectName)}` : ''}</div>${madeBy(r)}</td>
        <td><span class="status-pill ${r.isOverdue ? 'pill-danger' : ''}">${esc(r.status)}</span></td>
        <td class="muted num">${when(r.lastEditedAt || r.updatedAt)}</td></tr>`).join('')}</tbody></table></section>`;
  }).join('');
  for (const tr of box.querySelectorAll('tr[data-url]')) tr.addEventListener('click', () => { location.href = tr.dataset.url; });
  if (all.length > SHOWN) {
    const more = document.createElement('button');
    more.type = 'button';
    more.className = 'more-btn';
    more.dataset.noIcon = '';
    moreLabel(more, open, all.length - SHOWN, 0);
    more.addEventListener('click', (e) => { e.stopPropagation(); box.dataset.expanded = open ? '' : '1'; renderRecentDocs(all); });
    box.appendChild(more);
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
`;
  limitList(list, total);
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
function pickProjectThen(title, tab, startNew) {
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
    location.href = `project-detail.html?number=${document.getElementById('pick-project-select').value}&tab=${tab}${startNew ? '&new=1' : ''}`;
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

  renderRecentDocs(summary.recentDocuments || []);

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
    const fresh = (await window.api.tasks.list()).filter((r) => r.mine && !r.task.done);
    renderMyTasks(fresh);
  };
  // "New Task" first, as a Quick Actions tile, then the tasks. It's the
  // table's first row (one Quick Actions button across it), with its icon
  // over the tick boxes and its name over the tasks' titles.
  const renderMyTasks = (rows) => {
    taskBox.innerHTML = `<table class="compact no-sort task-table"><tbody>${newTaskRowHTML()}${rows.map((r) => window.taskRowHTML(r)).join('')}</tbody></table>` +
      (rows.length ? '' : '<div class="empty-widget"><span>Nothing to do.</span></div>');
    const add = taskBox.querySelector('#tasks-new-btn');
    add.addEventListener('click', newTaskQuick);
    if (!rows.length) return;
    window.wireTaskRows(taskBox, rows, reloadTasks, { projects });
    limitList(taskBox);
  };
  renderMyTasks(myTasks);

  // Expired / expiring worker and company documents (sections 42-43).
  const expiring = await window.api.adminDocuments.expiring(30);
  if (expiring.length > 0) {
    document.getElementById('attention-block').classList.remove('hidden');
    table('attention-list', expiring.map((i) => Object.assign({ url: 'admin.html' }, i)), [
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


// Quick Actions: start anything new in one click. Document kinds ask for
// the project first, then open that project's tab and start the new one.
const QA_SVG = (paths) => `<svg viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${paths}</svg>`;
const QUICK_ACTIONS = [
  { label: 'Project', color: '#5B7DB1', icon: '<path d="M2.5 5.5a1 1 0 0 1 1-1h4l1.5 1.8h7.5a1 1 0 0 1 1 1V15a1 1 0 0 1-1 1h-13a1 1 0 0 1-1-1z"/><path d="M10 9v4.5M7.75 11.25h4.5"/>', go: () => { location.href = 'projects.html?new=1'; } },
  { label: 'Quotation', color: '#8E72A8', icon: '<path d="M11.5 2.5H5.5A1.5 1.5 0 0 0 4 4v12a1.5 1.5 0 0 0 1.5 1.5h9A1.5 1.5 0 0 0 16 16V7z"/><path d="M11.5 2.5V7H16"/><path d="M7 11h6M7 14h4"/>', go: () => pickProjectThen('New Quotation — Choose a Project', 'quotations', true) },
  { label: 'BOQ', color: '#4F8A8F', icon: '<rect x="3" y="3.5" width="14" height="13" rx="1.5"/><path d="M3 7.5h14M3 11.5h14M8 7.5v9"/>', go: () => pickProjectThen('New BOQ — Choose a Project', 'boq', true) },
  { label: 'Delivery Note', color: '#5E8C6A', icon: '<path d="M2.5 5.5h9v8h-9z"/><path d="M11.5 8.5h3l2.5 2.5v2.5h-5.5"/><circle cx="6" cy="14.5" r="1.5"/><circle cx="14" cy="14.5" r="1.5"/>', go: () => pickProjectThen('New Delivery Note — Choose a Project', 'delivery', true) },
  { label: 'Invoice', color: '#A66A6A', icon: '<path d="M5 2.5h10v15l-2-1.3-1.7 1.3-1.3-1.3-1.3 1.3L7 16.2l-2 1.3z"/><path d="M8 7h4M8 10h4M8 13h2.5"/>', go: () => pickProjectThen('New Invoice — Choose a Project', 'invoices', true) },
  { label: 'Task', color: '#6E8F4E', icon: '<rect x="3.5" y="3.5" width="13" height="13" rx="2"/><path d="m6.8 10.2 2.2 2.2 4.3-4.6"/>', go: newTaskQuick },
  { label: 'Inspection', color: '#B07A5E', icon: '<path d="M10 2.5 16 5v4.5c0 3.8-2.6 6.7-6 8-3.4-1.3-6-4.2-6-8V5z"/><path d="m7.3 10 2 2 3.6-4"/>', go: () => pickProjectThen('Record Inspection — Choose a Project', 'inspections', true) },
  { label: 'Letter', color: '#7A7F9A', icon: '<rect x="2.5" y="4.5" width="15" height="11" rx="1.3"/><path d="m3 5.5 7 5.2 7-5.2"/>', go: () => pickProjectThen('New Letter — Choose a Project', 'letters', true) },
  { label: 'Client', color: '#9A8458', icon: '<rect x="4" y="3" width="12" height="14" rx="1.2"/><path d="M7 6.5h2M11 6.5h2M7 9.5h2M11 9.5h2M8.5 17v-3h3v3"/>', go: () => { location.href = 'clients.html?new=1'; } },
  { label: 'Site', color: '#B0705E', icon: '<path d="M10 17.5s-5.5-5-5.5-9a5.5 5.5 0 0 1 11 0c0 4-5.5 9-5.5 9z"/><circle cx="10" cy="8.5" r="2"/>', go: () => { location.href = 'clients.html?newSite=1'; } },
  { label: 'Lead', color: '#4F7FA0', icon: '<path d="M3.5 8.5v3a1 1 0 0 0 1 1H6l5 3.5v-12L6 7.5H4.5a1 1 0 0 0-1 1z"/><path d="M14 7.5a3.5 3.5 0 0 1 0 5M6.5 12.5l1 4"/>', go: () => { location.href = 'marketing.html?tab=leads&new=1'; } },
];

// The New Task row at the top of My Tasks — the Quick Actions look.
function newTaskRowHTML() {
  const a = QUICK_ACTIONS.find((x) => x.go === newTaskQuick);
  return `<tr class="task-new-row"><td colspan="4"><button type="button" class="qa-tile" id="tasks-new-btn" data-no-icon style="--qa:${a.color}" title="New Task">
    <span class="qa-icon">${QA_SVG(a.icon)}</span><span class="qa-text">New Task</span></button></td></tr>`;
}

async function newTaskQuick() {
  const people = await window.api.tasks.people();
  const projects = projectsCache.filter((p) => p.status !== 'Archived');
  if (await window.editTask(null, { projects, people })) location.reload();
}

// "New Task" is left out of Quick Actions while My Tasks (which has its
// own New Task button) is on the Dashboard.
function tasksWidgetShown() {
  const w = document.querySelector('[data-widget="tasks"]');
  return !!w && !w.classList.contains('widget-off') && !w.classList.contains('hidden');
}

function renderQuickActions() {
  const box = document.getElementById('quick-actions');
  const skipTask = tasksWidgetShown();
  box.innerHTML = QUICK_ACTIONS.map((a, i) => (skipTask && a.go === newTaskQuick ? '' : `<button class="qa-tile" data-no-icon data-i="${i}" style="--qa:${a.color}" title="New ${esc(a.label)}">
    <span class="qa-icon">${QA_SVG(a.icon)}</span><span class="qa-text">New ${esc(a.label)}</span></button>`)).join('');
  for (const b of box.querySelectorAll('.qa-tile')) b.addEventListener('click', () => QUICK_ACTIONS[Number(b.dataset.i)].go());
}
renderQuickActions();
// Hiding or showing My Tasks (Customise) brings New Task back, or takes it away.
new MutationObserver(() => {
  const shown = tasksWidgetShown();
  if (shown !== renderQuickActions.lastShown) { renderQuickActions.lastShown = shown; renderQuickActions(); }
}).observe(document.querySelector('[data-widget="tasks"]'), { attributes: true, attributeFilter: ['class'] });
renderQuickActions.lastShown = tasksWidgetShown();

window.announcements.render(document.getElementById('announce-bar'));
document.getElementById('announce-btn').addEventListener('click', () => window.announcements.compose());

document.getElementById('pick-cancel-btn').addEventListener('click', () => document.getElementById('pick-project-modal').classList.add('hidden'));

loadDashboard();

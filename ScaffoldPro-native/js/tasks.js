'use strict';

// The Tasks page: my tasks, everyone's, and those done; tick to finish,
// click to change. Each can be for a project and for a person.

let rows = [];
let projects = [];
let people = [];
let view = 'mine';

function esc(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function filtered() {
  const q = document.getElementById('task-search').value.trim().toLowerCase();
  const person = document.getElementById('task-person').value;
  const project = document.getElementById('task-project').value;
  return rows.filter((r) => {
    const t = r.task;
    if (view === 'mine' && (!r.mine || t.done)) return false;
    if (view === 'team' && t.done) return false;
    if (view === 'done' && !t.done) return false;
    if (person && (t.assignee || '') !== person) return false;
    if (project && t.projectId !== project) return false;
    return !q || [t.title, t.notes, t.assignee, r.projectNumber, r.projectName].some((x) => String(x || '').toLowerCase().includes(q));
  });
}

function render() {
  const open = rows.filter((r) => !r.task.done);
  const card = (value, label, tone) => `<div class="stat-card${tone ? ` tone-${tone}` : ''}"><div class="value">${value}</div><div class="label">${label}</div></div>`;
  const overdue = open.filter((r) => r.overdue).length;
  const today = new Date(); const p = (n) => String(n).padStart(2, '0');
  const t = `${today.getFullYear()}-${p(today.getMonth() + 1)}-${p(today.getDate())}`;
  document.getElementById('task-stats').innerHTML =
    card(open.filter((r) => r.mine).length, 'My open tasks') +
    card(open.filter((r) => r.task.dueDate === t).length, 'Due today') +
    card(overdue, 'Overdue', overdue ? 'danger' : null) +
    card(open.length, 'Open across the team');
  const list = filtered();
  const box = document.getElementById('task-list');
  if (!list.length) {
    box.innerHTML = `<div class="empty-state"><h2>${view === 'done' ? 'Nothing done yet' : 'Nothing to do'}</h2><p>${view === 'done' ? 'Ticked-off tasks show here.' : 'Use “+ New Task” to add one.'}</p></div>`;
    return;
  }
  box.innerHTML = `<table class="no-sort task-table"><thead><tr><th></th><th>Task</th><th>For</th><th>Due</th></tr></thead><tbody>${list.map((r) => window.taskRowHTML(r)).join('')}</tbody></table>`;
  window.wireTaskRows(box, rows, load, { projects });
}

async function load() {
  const [r, pr, pe] = await Promise.all([window.api.tasks.list(), window.api.projects.list(), window.api.tasks.people()]);
  rows = r || [];
  projects = (pr || []).filter((x) => x.status !== 'Archived');
  people = pe || [];
  const person = document.getElementById('task-person');
  const keepPerson = person.value;
  person.innerHTML = '<option value="">Everyone</option>' + people.map((n) => `<option value="${esc(n)}">${esc(n)}</option>`).join('');
  person.value = people.includes(keepPerson) ? keepPerson : '';
  const project = document.getElementById('task-project');
  const keepProject = project.value;
  project.innerHTML = '<option value="">All projects</option>' + projects.map((x) => `<option value="${esc(x.id)}">${esc(x.projectNumber)} — ${esc(x.name)}</option>`).join('');
  project.value = projects.some((x) => x.id === keepProject) ? keepProject : '';
  await window.loadPersonColors();
  render();
}

function setView(v) {
  view = v;
  for (const b of document.querySelectorAll('#task-tabs button')) b.classList.toggle('active', b.dataset.view === v);
  render();
}

document.getElementById('new-task-btn').addEventListener('click', async () => {
  const project = document.getElementById('task-project').value;
  if (await window.editTask(null, { projects, people, projectId: project || null })) await load();
});
for (const b of document.querySelectorAll('#task-tabs button')) b.addEventListener('click', () => setView(b.dataset.view));
document.getElementById('task-search').addEventListener('input', render);
document.getElementById('task-person').addEventListener('change', render);
document.getElementById('task-project').addEventListener('change', render);

load().then(async () => {
  // Opened from the Calendar: that task.
  const id = new URLSearchParams(location.search).get('task');
  const row = id && rows.find((r) => r.task.id === id);
  if (row) {
    if (row.task.done) setView('done'); else if (!row.mine) setView('team');
    if (await window.editTask(row.task, { projects, people })) await load();
  }
});

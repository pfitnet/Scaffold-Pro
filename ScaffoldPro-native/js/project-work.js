'use strict';

// A project's Inspections tab (the scaffold inspection register — Form 5:
// each structure inspected by a competent person before use and at least
// every 14 days) and its Tasks tab.
//
//   window.projectWork.load(project, { structures, setCount });

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const day = (d) => (d ? new Date(`${d}T00:00:00`).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }) : '—');
  const todayYMD = () => { const d = new Date(); const p = (n) => String(n).padStart(2, '0'); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`; };
  const RESULT_PILL = { Safe: 'pill-success', 'Safe with remarks': 'pill-warning', Unsafe: 'pill-danger' };

  let project = null;
  let opts = {};
  let records = [];
  let editing = null;

  // ---- inspections ----

  async function loadInspections() {
    records = (await window.api.inspections.list(project.id)) || [];
    renderInspections();
  }

  // Each structure's latest record: when it's next due.
  function dueList() {
    const latest = {};
    for (const r of records) {
      const key = r.structure.toLowerCase();
      if (!latest[key] || (latest[key].inspectedOn + latest[key].createdAt) < (r.inspectedOn + r.createdAt)) latest[key] = r;
    }
    return Object.values(latest).filter((r) => !r.dismantled && r.nextDue).sort((a, b) => a.nextDue.localeCompare(b.nextDue));
  }

  function renderInspections() {
    if (opts.setCount) opts.setCount('inspections', records.length);
    const box = document.getElementById('inspection-list');
    const due = dueList();
    const t = todayYMD();
    const dueHTML = due.length ? `<div class="insp-due">${due.map((r) => {
      const overdue = r.nextDue < t;
      const soon = !overdue && r.nextDue <= addDays(t, 3);
      return `<div class="insp-due-card ${overdue ? 'overdue' : soon ? 'soon' : ''}">
        <div class="insp-structure">${esc(r.structure)}</div>
        <div class="sub">Next inspection ${overdue ? '<b>overdue</b> — was due' : 'due'} ${day(r.nextDue)}</div>
        <div class="sub">Last: ${day(r.inspectedOn)} · ${esc(r.result)}</div>
        <button class="insp-again" data-structure="${esc(r.structure)}">Record Inspection</button></div>`;
    }).join('')}</div>` : '';
    if (!records.length) {
      box.innerHTML = '<div class="empty-state"><h2>No inspections recorded</h2><p>Record each scaffold’s inspection by the competent person — before it’s first used, then at least every 14 days (Form 5). The next one is reminded on the Dashboard and the Calendar.</p></div>';
      return;
    }
    box.innerHTML = `${dueHTML}<table class="no-sort"><thead><tr><th>Date</th><th>Scaffold</th><th>Competent person</th><th>Result</th><th>Remarks / action</th><th>Next due</th></tr></thead><tbody>${records.map((r) => `
      <tr class="link-row" data-id="${esc(r.id)}">
        <td class="nowrap">${day(r.inspectedOn)}</td>
        <td><strong>${esc(r.structure)}</strong>${r.location ? `<div class="sub">${esc(r.location)}</div>` : ''}</td>
        <td>${esc(r.inspector)}</td>
        <td><span class="status-pill ${RESULT_PILL[r.result] || ''}">${esc(r.result)}</span></td>
        <td>${esc(r.remarks || '')}${r.actionTaken ? `<div class="sub">Action: ${esc(r.actionTaken)}</div>` : ''}</td>
        <td class="nowrap">${r.dismantled ? '<span class="muted">Dismantled</span>' : day(r.nextDue)}</td></tr>`).join('')}</tbody></table>`;
    for (const tr of box.querySelectorAll('tr[data-id]')) tr.addEventListener('click', () => openInspection(records.find((r) => r.id === tr.dataset.id)));
    for (const b of box.querySelectorAll('.insp-again')) b.addEventListener('click', () => openInspection(null, b.dataset.structure));
  }

  function addDays(d, n) {
    const x = new Date(`${d}T00:00:00`);
    x.setDate(x.getDate() + n);
    const p = (v) => String(v).padStart(2, '0');
    return `${x.getFullYear()}-${p(x.getMonth() + 1)}-${p(x.getDate())}`;
  }

  function openInspection(record, structure) {
    editing = record || null;
    const last = !record && structure ? records.find((r) => r.structure === structure) : null;
    const v = (id, value) => { document.getElementById(id).value = value ?? ''; };
    document.getElementById('in-title').textContent = record ? 'Inspection' : 'Record Inspection';
    const names = [...new Set([...(opts.structures ? opts.structures() : []), ...records.map((r) => r.structure)])];
    document.getElementById('in-structures').innerHTML = names.map((n) => `<option value="${esc(n)}"></option>`).join('');
    v('in-structure', record ? record.structure : structure || '');
    v('in-location', record ? record.location : last ? last.location : '');
    v('in-date', record ? record.inspectedOn : todayYMD());
    v('in-inspector', record ? record.inspector : last ? last.inspector : '');
    v('in-result', record ? record.result : 'Safe');
    v('in-remarks', record ? record.remarks : '');
    v('in-action', record ? record.actionTaken : '');
    v('in-next', record ? record.nextDue : '');
    document.getElementById('in-dismantled').checked = !!(record && record.dismantled);
    document.getElementById('in-delete').classList.toggle('hidden', !record);
    document.getElementById('in-error').classList.add('hidden');
    updateNextHint();
    document.getElementById('inspection-modal').classList.remove('hidden');
    document.getElementById(record || structure ? 'in-inspector' : 'in-structure').focus();
  }

  function updateNextHint() {
    const d = document.getElementById('in-date').value;
    const dismantled = document.getElementById('in-dismantled').checked;
    document.getElementById('in-next').disabled = dismantled;
    document.getElementById('in-next').placeholder = '';
    document.getElementById('in-next-hint').textContent = dismantled ? 'No more inspections once it’s taken down.'
      : d ? `Leave blank for 14 days on: ${day(addDays(d, 14))}.` : '';
  }

  async function saveInspection() {
    const g = (id) => document.getElementById(id).value.trim();
    const r = await window.api.inspections.save({
      id: editing ? editing.id : null, projectId: project.id, structure: g('in-structure'), location: g('in-location'),
      inspectedOn: g('in-date'), inspector: g('in-inspector'), result: g('in-result'), remarks: g('in-remarks'),
      actionTaken: g('in-action'), nextDue: g('in-next'), dismantled: document.getElementById('in-dismantled').checked,
    });
    if (!r || !r.ok) {
      const err = document.getElementById('in-error');
      err.textContent = (r && r.error) || 'The inspection couldn’t be saved.';
      err.classList.remove('hidden');
      return;
    }
    document.getElementById('inspection-modal').classList.add('hidden');
    await loadInspections();
    if (opts.afterChange) opts.afterChange();
  }

  async function exportRegister() {
    if (!records.length) { alert('No inspections recorded yet.'); return; }
    const cell = (c) => { const t = String(c ?? ''); return /[",\n]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t; };
    const out = [['Date', 'Scaffold', 'Location', 'Competent person', 'Result', 'Remarks', 'Action taken', 'Next inspection due']];
    for (const r of [...records].reverse()) out.push([r.inspectedOn, r.structure, r.location || '', r.inspector, r.result, r.remarks || '', r.actionTaken || '', r.dismantled ? 'Dismantled' : r.nextDue || '']);
    const res = await window.api.accounts.saveCSV(`${project.projectNumber} Scaffold Inspection Register.csv`, out.map((row) => row.map(cell).join(',')).join('\r\n'),
      { projectNumber: project.projectNumber, subfolder: 'Documents' });
    if (res && res.ok === false) alert(res.error);
  }

  // ---- tasks ----

  let tasks = [];
  let showDone = false;

  async function loadTasks() {
    tasks = (await window.api.tasks.list(project.id)) || [];
    renderTasks();
  }

  function renderTasks() {
    const open = tasks.filter((r) => !r.task.done);
    if (opts.setCount) opts.setCount('tasks', open.length);
    const box = document.getElementById('task-list');
    const shown = showDone ? tasks : open;
    const doneCount = tasks.length - open.length;
    document.getElementById('task-show-done').textContent = showDone ? 'Hide Done' : `Show Done${doneCount ? ` (${doneCount})` : ''}`;
    if (!shown.length) {
      box.innerHTML = `<div class="empty-state"><h2>${tasks.length ? 'Nothing left to do' : 'No tasks yet'}</h2><p>Add what needs doing for this project and who it’s for.</p></div>`;
      return;
    }
    box.innerHTML = `<table class="no-sort task-table"><tbody>${shown.map((r) => window.taskRowHTML(r, { hideProject: true })).join('')}</tbody></table>`;
    window.wireTaskRows(box, tasks, loadTasks, { projects: [project], lockProject: true });
  }

  async function newTask() {
    const people = await window.api.tasks.people();
    if (await window.editTask(null, { projectId: project.id, projects: [project], people, lockProject: true })) await loadTasks();
  }

  window.projectWork = {
    async load(p, options) {
      project = p;
      opts = options || {};
      document.getElementById('record-inspection-btn').addEventListener('click', () => openInspection(null));
      document.getElementById('inspection-csv-btn').addEventListener('click', exportRegister);
      document.getElementById('in-cancel').addEventListener('click', () => document.getElementById('inspection-modal').classList.add('hidden'));
      document.getElementById('in-save').addEventListener('click', saveInspection);
      document.getElementById('in-date').addEventListener('change', updateNextHint);
      document.getElementById('in-dismantled').addEventListener('change', updateNextHint);
      document.getElementById('in-delete').addEventListener('click', async () => {
        if (!editing || !await window.appConfirm(`Delete this inspection record (${editing.structure}, ${day(editing.inspectedOn)})?`)) return;
        const r = await window.api.inspections.remove(editing.id);
        if (r && r.ok === false) { alert(r.error); return; }
        document.getElementById('inspection-modal').classList.add('hidden');
        await loadInspections();
      });
      document.getElementById('new-task-btn').addEventListener('click', newTask);
      document.getElementById('task-show-done').addEventListener('click', () => { showDone = !showDone; renderTasks(); });
      await loadInspections();
      await loadTasks();
    },
  };
})();

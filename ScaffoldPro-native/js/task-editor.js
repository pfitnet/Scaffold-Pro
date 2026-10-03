'use strict';

// The New / Edit Task sheet, shared by the Tasks page and each project's
// Tasks tab. Builds its own modal.
//
//   const saved = await window.editTask(task|null, { projectId, projects, people });
//   → true once saved (or deleted), false if cancelled.

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  function build() {
    const el = document.createElement('div');
    el.className = 'modal-backdrop hidden';
    el.id = 'task-modal';
    el.innerHTML = `
      <div class="modal wide" role="dialog" aria-labelledby="tk-title">
        <h2 id="tk-title">New Task</h2>
        <div class="form-grid">
          <div class="field span-2"><label for="tk-text">What needs doing</label><input type="text" id="tk-text" placeholder="e.g. Send revised BOQ to Mr. Law" /></div>
          <div class="field"><label for="tk-assignee">For</label><input type="text" id="tk-assignee" list="tk-people" placeholder="Anyone" /><datalist id="tk-people"></datalist></div>
          <div class="field"><label for="tk-due">Due</label><div class="due-row"><input type="date" id="tk-due" /><input type="time" id="tk-time" title="At a time (optional)" /></div></div>
          <div class="field"><label for="tk-project">Project</label><select id="tk-project"></select></div>
          <div class="field"><label for="tk-priority">Priority</label><select id="tk-priority"><option value="">Normal</option><option value="High">High</option></select></div>
          <div class="field span-2"><label for="tk-notes">Notes</label><input type="text" id="tk-notes" /></div>
        </div>
        <div class="error-text hidden" id="tk-error"></div>
        <div class="actions">
          <button id="tk-delete" class="left hidden" data-no-icon>Delete</button>
          <button id="tk-cancel">Cancel</button>
          <button class="primary" id="tk-save">Save</button>
        </div>
      </div>`;
    document.body.appendChild(el);
    return el;
  }

  window.editTask = function editTask(task, opts = {}) {
    const modal = document.getElementById('task-modal') || build();
    const $ = (id) => modal.querySelector(`#${id}`);
    return new Promise((resolve) => {
      $('tk-title').textContent = task ? 'Edit Task' : 'New Task';
      $('tk-text').value = task ? task.title : '';
      $('tk-assignee').value = task ? (task.assignee || '') : (opts.assignee || '');
      $('tk-due').value = task ? (task.dueDate || '') : (opts.dueDate || '');
      $('tk-time').value = task ? (task.dueTime || '') : (opts.dueTime || '');
      $('tk-priority').value = task && task.priority === 'High' ? 'High' : '';
      $('tk-notes').value = task ? (task.notes || '') : '';
      $('tk-people').innerHTML = (opts.people || []).map((n) => `<option value="${esc(n)}"></option>`).join('');
      const projects = opts.projects || [];
      $('tk-project').innerHTML = '<option value="">No project</option>' +
        projects.map((p) => `<option value="${esc(p.id)}">${esc(p.projectNumber)} — ${esc(p.name)}</option>`).join('');
      $('tk-project').value = task ? (task.projectId || '') : (opts.projectId || '');
      $('tk-project').disabled = !!opts.lockProject;
      $('tk-delete').classList.toggle('hidden', !task);
      $('tk-error').classList.add('hidden');
      modal.classList.remove('hidden');
      $('tk-text').focus();

      const close = (value) => {
        modal.classList.add('hidden');
        for (const [id, fn] of handlers) $(id).removeEventListener('click', fn);
        modal.removeEventListener('keydown', onKey);
        resolve(value);
      };
      const save = async () => {
        const r = await window.api.tasks.save({
          id: task ? task.id : null, title: $('tk-text').value.trim(), assignee: $('tk-assignee').value.trim(),
          dueDate: $('tk-due').value, dueTime: $('tk-time').value, projectId: $('tk-project').value || null, priority: $('tk-priority').value, notes: $('tk-notes').value.trim(),
        });
        if (!r || !r.ok) {
          $('tk-error').textContent = (r && r.error) || 'The task couldn’t be saved.';
          $('tk-error').classList.remove('hidden');
          return;
        }
        close(true);
      };
      const del = async () => {
        if (!await window.appConfirm(`Delete the task “${task.title}”?`)) return;
        const r = await window.api.tasks.remove(task.id);
        if (r && r.ok === false) { alert(r.error); return; }
        close(true);
      };
      const onKey = (e) => {
        if (e.key === 'Escape') { e.preventDefault(); close(false); }
        if (e.key === 'Enter' && e.target.tagName === 'INPUT' && e.target.type !== 'date') { e.preventDefault(); save(); }
      };
      const handlers = [['tk-save', save], ['tk-cancel', () => close(false)], ['tk-delete', del]];
      for (const [id, fn] of handlers) $(id).addEventListener('click', fn);
      modal.addEventListener('keydown', onKey);
    });
  };

  // Rows drawn with taskRowHTML: ticking a box marks it done (or not);
  // clicking a row edits it. opts: { projects, lockProject }.
  window.wireTaskRows = function wireTaskRows(box, rows, reload, opts = {}) {
    for (const tr of box.querySelectorAll('tr.task-row')) {
      const row = rows.find((r) => r.task.id === tr.dataset.id);
      if (!row) continue;
      const tick = tr.querySelector('.task-done-box');
      tick.addEventListener('click', (e) => e.stopPropagation());
      tick.addEventListener('change', async () => {
        const r = await window.api.tasks.setDone(row.task.id, tick.checked);
        if (r && r.ok === false) alert(r.error);
        await reload();
      });
      tr.addEventListener('click', async (e) => {
        if (e.target.closest('a')) return;
        const people = await window.api.tasks.people();
        if (await window.editTask(row.task, { projects: opts.projects || [], people, lockProject: !!opts.lockProject })) await reload();
      });
    }
  };

  // A task as a row: tick box, title, project, who, due.
  window.taskRowHTML = function taskRowHTML(row, opts = {}) {
    const t = row.task;
    const due = t.dueDate ? new Date(`${t.dueDate}T00:00:00`).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }).replace('Sept', 'Sep') : '';
    return `<tr class="task-row${t.done ? ' task-done' : ''}" data-id="${esc(t.id)}">
      <td class="task-check"><input type="checkbox" class="task-done-box" ${t.done ? 'checked' : ''} title="${t.done ? 'Not done yet' : 'Done'}" /></td>
      <td><span class="task-title">${t.priority === 'High' ? '<span class="status-pill pill-danger task-high">High</span> ' : ''}${esc(t.title)}</span>
        ${t.notes ? `<div class="sub">${esc(t.notes)}</div>` : ''}
        ${!opts.hideProject && row.projectNumber ? `<div class="sub"><a href="project-detail.html?number=${encodeURIComponent(row.projectNumber)}&tab=tasks">${esc(row.projectNumber)} ${esc(row.projectName || '')}</a></div>` : ''}</td>
      <td>${t.assignee ? window.personTag(t.assignee) : '<span class="muted">Anyone</span>'}</td>
      <td class="nowrap ${row.overdue ? 'task-overdue' : 'muted'}">${t.done ? `Done${t.doneBy ? ` by ${esc(t.doneBy)}` : ''}` : due ? `${row.overdue ? 'Overdue · ' : ''}${due}${t.dueTime ? ` ${esc(t.dueTime)}` : ''}` : ''}</td>
    </tr>`;
  };
})();

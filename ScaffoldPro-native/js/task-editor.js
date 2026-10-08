'use strict';

// The New / Edit Task sheet, shared by the Tasks page, each project's
// Tasks tab and the Calendar. Builds its own modal. Kept short: what, when
// and for whom — the project, priority and notes sit under "More".
// A task is a to-do with a due day (and maybe a time); an event has a start
// and an end (a meeting, a site visit) and shows as a block on the Calendar.
//
//   const saved = await window.editTask(task|null, { projectId, projects, people,
//     title, assignee, dueDate, dueTime, endTime, event: true });
//   → true once saved (or deleted), false if cancelled.

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const pad = (n) => String(n).padStart(2, '0');
  const plusHour = (t) => {
    const [h, m] = String(t || '09:00').split(':').map(Number);
    return h >= 23 ? '23:59' : `${pad(h + 1)}:${pad(m || 0)}`;
  };
  let teamsCache = null;

  function build() {
    const el = document.createElement('div');
    el.className = 'modal-backdrop hidden';
    el.id = 'task-modal';
    el.innerHTML = `
      <div class="modal te-modal" role="dialog" aria-labelledby="te-heading">
        <div class="te-head">
          <h2 id="te-heading">New</h2>
          <div class="segmented te-kind" role="tablist" aria-label="Kind">
            <button type="button" data-kind="task" data-no-icon>Task</button>
            <button type="button" data-kind="event" data-no-icon>Event</button>
          </div>
        </div>
        <input type="text" id="tk-text" class="te-title" placeholder="What needs doing?" aria-label="Title" />
        <div class="te-row">
          <span class="te-label">When</span>
          <div class="te-when">
            <input type="date" id="tk-due" aria-label="Day" />
            <input type="time" id="tk-time" aria-label="Start" />
            <span class="te-dash">–</span>
            <input type="time" id="tk-end" aria-label="End" />
          </div>
        </div>
        <div class="te-row">
          <span class="te-label">For</span>
          <div class="te-for" id="te-for" role="radiogroup" aria-label="For"></div>
        </div>
        <details class="te-more" id="te-more">
          <summary data-no-icon>More — project, priority, notes</summary>
          <div class="te-more-body">
            <div class="te-row"><span class="te-label">Project</span><select id="tk-project" aria-label="Project"></select></div>
            <div class="te-row te-task-only"><span class="te-label">Priority</span><label class="te-check"><input type="checkbox" id="tk-high" /> High</label></div>
            <div class="te-row"><span class="te-label">Notes</span><input type="text" id="tk-notes" aria-label="Notes" /></div>
          </div>
        </details>
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

  window.editTask = async function editTask(task, opts = {}) {
    const modal = document.getElementById('task-modal') || build();
    const $ = (id) => modal.querySelector(`#${id}`);
    if (!teamsCache) {
      try { teamsCache = (await window.api.tasks.teams()) || null; } catch (e) { teamsCache = null; }
      teamsCache = teamsCache || { me: '', teams: [] };
    }
    return new Promise((resolve) => {
      let kind = (task ? task.endTime : (opts.event || opts.endTime)) ? 'event' : 'task';
      // Who it's for: { person } or { team } or {} for anyone.
      let forWho = task
        ? (task.assignee ? { person: task.assignee } : task.team ? { team: task.team } : {})
        : (opts.assignee ? { person: opts.assignee } : opts.team ? { team: opts.team } : {});
      const me = teamsCache.me || '';
      // A new event is yours unless someone (or a team) is chosen.
      let forChosen = !!(task || opts.assignee || opts.team);
      if (!forChosen && kind === 'event' && me) forWho = { person: me };
      const people = [...new Set([...(opts.people || []), forWho.person].filter(Boolean))];

      const drawKind = () => {
        for (const b of modal.querySelectorAll('.te-kind button')) b.classList.toggle('active', b.dataset.kind === kind);
        modal.querySelector('.te-modal').classList.toggle('is-event', kind === 'event');
        $('tk-text').placeholder = kind === 'event' ? 'What’s on? e.g. Site visit, Tsuen Wan' : 'What needs doing? e.g. Send revised BOQ to Mr. Law';
        $('te-heading').textContent = `${task ? 'Edit' : 'New'} ${kind === 'event' ? 'Event' : 'Task'}`;
        $('tk-time').title = kind === 'event' ? 'Starts' : 'At a time (optional)';
        if (kind === 'event') {
          if (!$('tk-due').value) { const n = new Date(); $('tk-due').value = `${n.getFullYear()}-${pad(n.getMonth() + 1)}-${pad(n.getDate())}`; }
          if (!$('tk-time').value) $('tk-time').value = '09:00';
          if (!$('tk-end').value || $('tk-end').value <= $('tk-time').value) $('tk-end').value = plusHour($('tk-time').value);
        }
      };
      const drawFor = () => {
        const chip = (label, sel, attrs, extra = '') => `<button type="button" class="te-chip${sel ? ' on' : ''}" ${attrs} role="radio" aria-checked="${sel}" data-no-icon>${extra}${esc(label)}</button>`;
        const teamIcon = '<svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><circle cx="6" cy="6" r="2.3" fill="none" stroke="currentColor" stroke-width="1.4"/><circle cx="11.2" cy="6.8" r="1.8" fill="none" stroke="currentColor" stroke-width="1.4"/><path d="M2 13c.6-2.2 2.1-3.3 4-3.3s3.4 1.1 4 3.3M10 10c1.9-.3 3.4.7 4 3" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linecap="round"/></svg>';
        const others = people.filter((n) => n !== me);
        const pickedOther = forWho.person && forWho.person !== me;
        $('te-for').innerHTML = chip('Anyone', !forWho.person && !forWho.team, 'data-for=""')
          + (me ? chip('Me', forWho.person === me, `data-for="p:${esc(me)}"`) : '')
          + (teamsCache.teams || []).map((t) => chip(t, forWho.team === t, `data-for="t:${esc(t)}"`, teamIcon)).join('')
          + (others.length ? `<select class="te-person${pickedOther ? ' on' : ''}" aria-label="Someone else"><option value="">${pickedOther ? 'Someone else' : 'Someone else…'}</option>${others.map((n) => `<option value="${esc(n)}"${forWho.person === n ? ' selected' : ''}>${esc(n)}</option>`).join('')}</select>` : '');
        for (const b of $('te-for').querySelectorAll('.te-chip')) {
          b.addEventListener('click', () => {
            const v = b.dataset.for;
            forWho = v.startsWith('p:') ? { person: v.slice(2) } : v.startsWith('t:') ? { team: v.slice(2) } : {};
            forChosen = true;
            drawFor();
          });
        }
        const sel = $('te-for').querySelector('.te-person');
        if (sel) sel.addEventListener('change', () => { forWho = sel.value ? { person: sel.value } : {}; forChosen = true; drawFor(); });
      };

      $('tk-text').value = task ? task.title : (opts.title || '');
      $('tk-due').value = task ? (task.dueDate || '') : (opts.dueDate || '');
      $('tk-time').value = task ? (task.dueTime || '') : (opts.dueTime || '');
      $('tk-end').value = task ? (task.endTime || '') : (opts.endTime || '');
      $('tk-high').checked = (task ? task.priority : opts.priority) === 'High';
      $('tk-notes').value = task ? (task.notes || '') : '';
      const projects = opts.projects || [];
      $('tk-project').innerHTML = '<option value="">No project</option>' +
        projects.map((p) => `<option value="${esc(p.id)}">${esc(p.projectNumber)} — ${esc(p.name)}</option>`).join('');
      $('tk-project').value = task ? (task.projectId || '') : (opts.projectId || '');
      $('tk-project').disabled = !!opts.lockProject;
      $('te-more').open = !!($('tk-notes').value || $('tk-high').checked || ($('tk-project').value && !opts.lockProject));
      $('tk-delete').classList.toggle('hidden', !task);
      $('tk-error').classList.add('hidden');
      drawKind();
      drawFor();
      modal.classList.remove('hidden');
      $('tk-text').focus();

      const kindButtons = [...modal.querySelectorAll('.te-kind button')];
      const onKind = (e) => {
        kind = e.currentTarget.dataset.kind;
        if (!forChosen && me) { forWho = kind === 'event' ? { person: me } : {}; drawFor(); }
        drawKind();
      };
      // Moving the start keeps the event's length.
      let lastStart = $('tk-time').value;
      const onStart = () => {
        const s = $('tk-time').value;
        if (kind === 'event' && s && lastStart && $('tk-end').value) {
          const mins = (t) => { const [h, m] = t.split(':').map(Number); return h * 60 + m; };
          const len = Math.max(15, mins($('tk-end').value) - mins(lastStart));
          const end = Math.min(23 * 60 + 59, mins(s) + len);
          $('tk-end').value = `${pad(Math.floor(end / 60))}:${pad(end % 60)}`;
        }
        lastStart = s;
      };
      const close = (value) => {
        modal.classList.add('hidden');
        for (const [id, fn] of handlers) $(id).removeEventListener('click', fn);
        for (const b of kindButtons) b.removeEventListener('click', onKind);
        $('tk-time').removeEventListener('change', onStart);
        modal.removeEventListener('keydown', onKey);
        resolve(value);
      };
      const save = async () => {
        const isEvent = kind === 'event';
        if (isEvent && (!$('tk-due').value || !$('tk-time').value || !$('tk-end').value || $('tk-end').value <= $('tk-time').value)) {
          $('tk-error').textContent = 'An event needs a day, and an end after its start.';
          $('tk-error').classList.remove('hidden');
          return;
        }
        const r = await window.api.tasks.save({
          id: task ? task.id : null, title: $('tk-text').value.trim(),
          assignee: forWho.person || '', team: forWho.team || '',
          dueDate: $('tk-due').value, dueTime: $('tk-time').value, endTime: isEvent ? $('tk-end').value : '',
          projectId: $('tk-project').value || null, priority: !isEvent && $('tk-high').checked ? 'High' : '', notes: $('tk-notes').value.trim(),
        });
        if (!r || !r.ok) {
          $('tk-error').textContent = (r && r.error) || 'It couldn’t be saved.';
          $('tk-error').classList.remove('hidden');
          return;
        }
        close(true);
      };
      const del = async () => {
        if (!await window.appConfirm(`Delete “${task.title}”?`)) return;
        const r = await window.api.tasks.remove(task.id);
        if (r && r.ok === false) { alert(r.error); return; }
        close(true);
      };
      const onKey = (e) => {
        if (e.key === 'Escape') { e.preventDefault(); close(false); }
        if (e.key === 'Enter' && e.target.tagName === 'INPUT' && e.target.type !== 'date' && e.target.type !== 'checkbox') { e.preventDefault(); save(); }
      };
      const handlers = [['tk-save', save], ['tk-cancel', () => close(false)], ['tk-delete', del]];
      for (const [id, fn] of handlers) $(id).addEventListener('click', fn);
      for (const b of kindButtons) b.addEventListener('click', onKind);
      $('tk-time').addEventListener('change', onStart);
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
      <td>${t.assignee ? window.personTag(t.assignee) : t.team ? `<span class="muted">${esc(t.team)} team</span>` : '<span class="muted">Anyone</span>'}</td>
      <td class="nowrap ${row.overdue ? 'task-overdue' : 'muted'}">${t.done ? `Done${t.doneBy ? ` by ${esc(t.doneBy)}` : ''}` : due ? `${row.overdue ? 'Overdue · ' : ''}${due}${t.dueTime ? ` ${esc(t.dueTime)}` : ''}` : ''}</td>
    </tr>`;
  };
})();

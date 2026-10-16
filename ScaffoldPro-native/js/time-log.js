'use strict';

// The time log, in a floating window on every page (as the Assistant's chat
// and the calculator): the clock in the sidebar, or ⌥⌘T. A chain, read like
// a chat (oldest at the top, the box underneath): nobody presses start or
// stop. Type what you just finished and press Return, and it takes the time
// since your previous entry that day. The day's first entry only marks the
// start. An entry can be for a task (the list under the box); the task's
// card then shows the time logged on it (js/tasks.js, via chain/taskTotals).
// Wide enough, it shows the day by task and the week beside the entries.
// Moved, resized and kept open across pages by js/float-window.js.
// Styles: css/time-log.css. Swift: Sources/TimeLog.swift.

(function () {
if (window.timeLog) return;

const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const pad = (n) => String(n).padStart(2, '0');
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const stamp = (d) => `${ymd(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
const dayOf = (s) => new Date(`${s}T00:00:00`);
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const hhmm = (at) => at.slice(11, 16);
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const ic = (name, size) => (window.icon ? window.icon(name, { size }) : '');

// "45 min", "1 h 20 min", "2 h".
function length(mins) {
  if (mins < 60) return `${mins} min`;
  const h = Math.floor(mins / 60), m = mins % 60;
  return m ? `${h} h ${m} min` : `${h} h`;
}

// The entries oldest first, each with `from` (the entry before it that day)
// and `mins`; the day's first has neither.
function chain(entries) {
  let prev = null;
  return [...entries].sort((a, b) => (a.at < b.at ? -1 : a.at > b.at ? 1 : 0)).map((e) => {
    const same = prev && prev.at.slice(0, 10) === e.at.slice(0, 10);
    const row = { ...e, from: same ? prev.at : null, mins: same ? Math.max(0, Math.round((new Date(e.at) - new Date(prev.at)) / 60000)) : 0 };
    prev = e;
    return row;
  });
}
// Minutes logged on each task: { taskId: mins }.
function taskTotals(entries) {
  const out = {};
  for (const e of chain(entries)) if (e.taskId && e.mins) out[e.taskId] = (out[e.taskId] || 0) + e.mins;
  return out;
}

window.timeLog = { chain, taskTotals, length };

function build() {
  const panel = document.createElement('div');
  panel.id = 'time-float';
  panel.className = 'calc-float time-float hidden';
  panel.setAttribute('role', 'dialog');
  panel.setAttribute('aria-label', 'Time log');
  panel.dataset.noIcon = '';
  panel.innerHTML = `
    <div class="calc-bar" title="Drag to move it">
      <span class="calc-title" title="Time log">${ic('clock', 15)}</span>
      <span class="tf-nav">
        <button type="button" class="tf-step" data-step="-1" data-no-icon title="Previous day" aria-label="Previous day">${ic('caret-left', 13)}</button>
        <button type="button" class="tf-day" id="tl-day" data-no-icon title="Back to today"></button>
        <button type="button" class="tf-step" data-step="1" data-no-icon title="Next day" aria-label="Next day">${ic('caret-right', 13)}</button>
      </span>
      <span class="tl-total" id="tl-total" title="Logged this day"></span>
      <button type="button" class="calc-close" data-no-icon title="Close (Escape)" aria-label="Close">
        <svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M4 4l8 8M12 4l-8 8"/></svg></button>
    </div>
    <div class="tf-body">
      <ol class="tl-list" id="tl-list"></ol>
      <aside class="tf-side">
        <section><h3>By task</h3><div id="tl-by-task"></div></section>
        <section><h3>This week <span class="tl-week-total" id="tl-week-total"></span></h3><div class="tl-week" id="tl-week"></div></section>
      </aside>
    </div>
    <div class="tf-foot">
      <input type="text" id="tl-input" autocomplete="off" placeholder="What did you just finish? Press Return" aria-label="What you just finished" />
      <div class="tf-foot-row">
        <select id="tl-task" aria-label="For a task" title="For a task"><option value="">No task</option></select>
        <span class="tl-since" id="tl-since" title="What Return will record"></span>
      </div>
    </div>`;
  document.body.appendChild(panel);
  return panel;
}

function init() {
  if (!document.body || document.getElementById('time-float') || !window.floatWindow) return;
  const page = document.body.dataset.page;
  if (!page || page === 'launch') return;
  const panel = build();
  const $ = (id) => panel.querySelector(`#${id}`);
  const list = $('tl-list');

  let day = ymd(new Date());
  let entries = [];   // the shown week's, chained
  let tasks = [];     // TaskRow, for the list and the names
  let editing = '';
  let fresh = '';     // the entry just added, eased in

  const weekStart = (key) => { const d = dayOf(key); return addDays(d, -((d.getDay() + 6) % 7)); };
  const taskRow = (id) => tasks.find((r) => r.task.id === id);
  const taskName = (id) => { const r = taskRow(id); return r ? r.task.title : 'A removed task'; };
  const toEnd = () => { list.scrollTop = list.scrollHeight; };

  function taskOptions(selected) {
    const open = tasks.filter((r) => !r.task.done || r.task.id === selected)
      .sort((a, b) => (a.mine === b.mine ? 0 : a.mine ? -1 : 1));
    return `<option value="">No task</option>${open.map((r) => `<option value="${esc(r.task.id)}"${r.task.id === selected ? ' selected' : ''}>${esc(r.task.title)}${r.projectNumber ? ` · ${esc(r.projectNumber)}` : ''}</option>`).join('')}`;
  }

  async function load() {
    const ws = weekStart(day);
    const [got, rows] = await Promise.all([window.api.time.list(ymd(ws), ymd(addDays(ws, 6))), window.api.tasks.list()]);
    entries = chain(got || []);
    tasks = rows || [];
    const sel = $('tl-task');
    const keep = sel.value;
    sel.innerHTML = taskOptions(keep);
    sel.value = taskRow(keep) ? keep : '';
    render();
  }
  // After a change: this, and the page (the task cards' logged time).
  function reload() {
    if (window.scheduleList) window.scheduleList.load();
    return load();
  }

  function render() {
    const today = ymd(new Date());
    const d = dayOf(day);
    const rows = entries.filter((e) => e.at.slice(0, 10) === day);
    const total = rows.reduce((s, e) => s + e.mins, 0);
    $('tl-day').innerHTML = `${day === today ? 'Today' : day === ymd(addDays(new Date(), -1)) ? 'Yesterday' : WEEKDAYS[d.getDay()]} <span>${d.getDate()} ${MONTHS[d.getMonth()]}</span>`;
    $('tl-total').textContent = total ? length(total) : '';
    panel.querySelector('.tf-step[data-step="1"]').disabled = day >= today;

    list.innerHTML = rows.length ? rows.map((e) => editing === e.id ? `
      <li class="tl-row editing" data-id="${esc(e.id)}">
        <input type="time" class="tl-edit-at" value="${esc(hhmm(e.at))}" aria-label="Finished at" />
        <span class="tl-acts">
          <button type="button" class="icon-btn" data-act="save" data-no-icon title="Save (Return)" aria-label="Save">${ic('check', 15)}</button>
          <button type="button" class="icon-btn" data-act="cancel" data-no-icon title="Cancel (Esc)" aria-label="Cancel">${ic('x', 15)}</button>
        </span>
        <input type="text" class="tl-edit-text" value="${esc(e.text)}" aria-label="What you finished" />
        <select class="tl-edit-task" aria-label="Task">${taskOptions(e.taskId)}</select>
      </li>` : `
      <li class="tl-row${e.from ? '' : ' start'}${e.id === fresh ? ' fresh' : ''}" data-id="${esc(e.id)}">
        <span class="tl-meta"><span class="tl-when">${e.from ? `${esc(hhmm(e.from))}–` : ''}${esc(hhmm(e.at))}</span>
          <span class="tl-len">${e.from ? esc(length(e.mins)) : 'Start'}</span></span>
        <span class="tl-acts">
          <button type="button" class="icon-btn" data-act="edit" data-no-icon title="Change" aria-label="Change">${ic('edit', 14)}</button>
          <button type="button" class="icon-btn icon-danger" data-act="delete" data-no-icon title="Remove" aria-label="Remove">${ic('trash', 14)}</button>
        </span>
        <span class="tl-text">${esc(e.text)}${e.taskId ? ` <button type="button" class="tl-task" data-task="${esc(e.taskId)}" data-no-icon title="Open the task">${ic('check', 11)}${esc(taskName(e.taskId))}</button>` : ''}</span>
      </li>`).join('')
      : `<li class="tl-empty">${day === today ? 'Nothing logged yet today. Your first entry starts the clock: type something like “Arrived”.' : 'Nothing logged on this day.'}</li>`;
    if (fresh) toEnd();
    fresh = '';
    const ed = list.querySelector('.tl-edit-text');
    if (ed) { ed.focus(); ed.setSelectionRange(ed.value.length, ed.value.length); }

    // By task, for the day.
    const by = {};
    for (const e of rows) if (e.mins) by[e.taskId || ''] = (by[e.taskId || ''] || 0) + e.mins;
    const keys = Object.keys(by).sort((a, b) => by[b] - by[a]);
    $('tl-by-task').innerHTML = keys.length ? keys.map((k) => `
      <div class="tl-sum"><span class="tl-sum-name">${esc(k ? taskName(k) : 'No task')}</span><b>${esc(length(by[k]))}</b>
        <i style="--w:${Math.round((by[k] / total) * 100)}%"></i></div>`).join('')
      : '<div class="tl-none">Nothing yet.</div>';

    // The week, a bar a day.
    const ws = weekStart(day);
    const perDay = [...Array(7)].map((_, i) => {
      const k = ymd(addDays(ws, i));
      return { k, mins: entries.filter((e) => e.at.slice(0, 10) === k).reduce((s, e) => s + e.mins, 0) };
    });
    const most = Math.max(60, ...perDay.map((p) => p.mins));
    $('tl-week').innerHTML = perDay.map((p) => `
      <button type="button" class="tl-wday${p.k === day ? ' on' : ''}${p.k > today ? ' later' : ''}" data-day="${p.k}" data-no-icon
        title="${esc(window.appDay ? window.appDay(p.k) : p.k)}${p.mins ? `: ${esc(length(p.mins))}` : ''}"${p.k > today ? ' disabled' : ''}>
        <span class="tl-wbar"><i style="height:${Math.round((p.mins / most) * 100)}%"></i></span>
        <span>${WEEKDAYS[dayOf(p.k).getDay()].slice(0, 2)}</span></button>`).join('');
    const week = perDay.reduce((s, p) => s + p.mins, 0);
    $('tl-week-total').textContent = week ? length(week) : '';
    tick();
  }

  // Under the box: what Return will record.
  function tick() {
    const today = ymd(new Date());
    const last = entries.filter((e) => e.at.slice(0, 10) === today).pop();
    $('tl-since').textContent = last
      ? `${length(Math.max(0, Math.round((Date.now() - new Date(last.at)) / 60000)))} since ${hhmm(last.at)}`
      : 'Starts the day';
  }

  function show(key) {
    const before = weekStart(day).getTime();
    editing = '';
    day = key > ymd(new Date()) ? ymd(new Date()) : key;
    if (weekStart(day).getTime() !== before) load(); else render();
  }

  async function add() {
    const input = $('tl-input');
    const text = input.value.trim();
    if (!text) return;
    const res = await window.api.time.add({ text, at: stamp(new Date()), taskId: $('tl-task').value || null });
    if (!res || !res.ok) { window.appToast((res && res.error) || 'Couldn’t log that.', { kind: 'danger' }); return; }
    input.value = '';
    $('tl-task').value = '';
    fresh = res.id;
    day = ymd(new Date());
    await reload();
  }

  async function saveEdit(li) {
    const e = entries.find((x) => x.id === li.dataset.id);
    const time = li.querySelector('.tl-edit-at').value;
    const text = li.querySelector('.tl-edit-text').value.trim();
    if (!e || !text || !/^\d{2}:\d{2}$/.test(time)) return;
    const at = `${e.at.slice(0, 10)}T${time}:${time === hhmm(e.at) ? e.at.slice(17, 19) : '00'}`;
    const res = await window.api.time.save({ id: e.id, text, at, taskId: li.querySelector('.tl-edit-task').value });
    if (!res || !res.ok) { window.appToast((res && res.error) || 'Couldn’t save that.', { kind: 'danger' }); return; }
    editing = '';
    await reload();
  }

  // A task: its sheet where the page has one, otherwise on the Tasks page.
  async function openTask(id) {
    const r = taskRow(id);
    if (!r) return;
    if (!window.editTask) { location.href = `tasks.html?task=${encodeURIComponent(id)}`; return; }
    const [projects, people] = await Promise.all([window.api.projects.list(), window.api.tasks.people()]);
    if (await window.editTask(r.task, { projects: (projects || []).filter((p) => p.status !== 'Archived'), people }) && window.appRefresh) await window.appRefresh();
  }

  const win = window.floatWindow(panel, {
    key: 'timelog', minW: 320, minH: 340,
    gripTitle: 'Drag an edge or corner to resize: wider shows the day by task and the week. Double-click: back to its usual size',
    onOpen: (focus) => {
      load().then(toEnd);
      if (focus) setTimeout(() => $('tl-input').focus(), 0);
    },
  });

  $('tl-input').addEventListener('keydown', (e) => {
    if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); add(); }
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); if (e.target.value) e.target.value = ''; else win.close(); }
  });
  panel.querySelector('.calc-close').addEventListener('click', win.close);
  panel.querySelector('.tf-nav').addEventListener('click', (e) => {
    const step = e.target.closest('.tf-step');
    if (step) show(ymd(addDays(dayOf(day), Number(step.dataset.step))));
    else if (e.target.closest('.tf-day')) show(ymd(new Date()));
  });
  $('tl-week').addEventListener('click', (e) => { const b = e.target.closest('[data-day]'); if (b) show(b.dataset.day); });
  list.addEventListener('click', async (e) => {
    const chip = e.target.closest('[data-task]');
    if (chip) { openTask(chip.dataset.task); return; }
    const b = e.target.closest('[data-act]');
    const li = e.target.closest('.tl-row');
    if (!b || !li) return;
    if (b.dataset.act === 'edit') { editing = li.dataset.id; render(); }
    if (b.dataset.act === 'cancel') { editing = ''; render(); }
    if (b.dataset.act === 'save') saveEdit(li);
    if (b.dataset.act === 'delete') {
      const res = await window.api.time.remove(li.dataset.id);
      if (res && res.ok) { await reload(); if (window.appUndoHint) window.appUndoHint('Removed the entry'); }
    }
  });
  list.addEventListener('keydown', (e) => {
    const li = e.target.closest('.tl-row.editing');
    if (!li || e.target.tagName === 'SELECT') return;
    if (e.key === 'Enter') { e.preventDefault(); saveEdit(li); }
    if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); editing = ''; render(); }
  });
  document.addEventListener('keydown', (e) => {
    if (e.altKey && e.metaKey && !e.ctrlKey && (e.code === 'KeyT' || e.key.toLowerCase() === 't')) { e.preventDefault(); win.toggle(); }
  });
  // Undone or redone (js/undo.js): what it shows may have changed.
  window.addEventListener('app:undone', () => { if (win.isOpen()) load(); });
  setInterval(() => { if (win.isOpen()) tick(); }, 30000);

  Object.assign(window.timeLog, { open: win.open, close: win.close, toggle: win.toggle, focus: () => { win.open(); } });
  win.restore();
}

if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
else init();
})();

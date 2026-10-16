'use strict';

// Schedule › Time (calendar.html): the time log as a chain. Nobody presses
// start or stop: type what you just finished and press Return, and it takes
// the time since your previous entry that day. The day's first entry only
// marks the start. An entry can be for a task (the list beside the box);
// the task's card then shows the time logged on it (js/tasks.js).
// calendar.js owns the keys and window.appRefresh (it reloads this too).
// Styles: css/tasks.css (Time). Swift: Sources/TimeLog.swift.

(function () {

const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const pad = (n) => String(n).padStart(2, '0');
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const stamp = (d) => `${ymd(d)}T${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
const dayOf = (s) => new Date(`${s}T00:00:00`);
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const hhmm = (at) => at.slice(11, 16);
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

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

let day = ymd(new Date());
let entries = [];   // the shown week's, chained
let tasks = [];     // TaskRow, for the list and the names
let editing = '';
let fresh = '';     // the entry just added, eased in
const $ = (id) => document.getElementById(id);

const weekStart = (key) => { const d = dayOf(key); return addDays(d, -((d.getDay() + 6) % 7)); };
const taskRow = (id) => tasks.find((r) => r.task.id === id);
const taskName = (id) => { const r = taskRow(id); return r ? r.task.title : 'A removed task'; };

function taskOptions(selected) {
  const open = tasks.filter((r) => !r.task.done || r.task.id === selected)
    .sort((a, b) => (a.mine === b.mine ? 0 : a.mine ? -1 : 1));
  return `<option value="">No task</option>${open.map((r) => `<option value="${esc(r.task.id)}"${r.task.id === selected ? ' selected' : ''}>${esc(r.task.title)}${r.projectNumber ? ` · ${esc(r.projectNumber)}` : ''}</option>`).join('')}`;
}

async function load() {
  const ws = weekStart(day);
  const [list, rows] = await Promise.all([window.api.time.list(ymd(ws), ymd(addDays(ws, 6))), window.api.tasks.list()]);
  entries = chain(list || []);
  tasks = rows || [];
  const sel = $('tl-task');
  const keep = sel.value;
  sel.innerHTML = taskOptions(keep);
  sel.value = taskRow(keep) ? keep : '';
  render();
}

// After a change: this, and the task cards' logged time.
function reload() {
  if (window.scheduleList) window.scheduleList.load();
  return load();
}

function render() {
  const today = ymd(new Date());
  const d = dayOf(day);
  $('tl-day').innerHTML = `${day === today ? 'Today' : day === ymd(addDays(new Date(), -1)) ? 'Yesterday' : WEEKDAYS[d.getDay()]} <span>${esc(window.appDay ? window.appDay(day) : day)}</span>`;
  $('tl-next').disabled = day >= today;
  const rows = entries.filter((e) => e.at.slice(0, 10) === day);
  const total = rows.reduce((s, e) => s + e.mins, 0);
  $('tl-total').textContent = total ? length(total) : '';

  $('tl-list').innerHTML = rows.length ? rows.slice().reverse().map((e) => editing === e.id ? `
    <li class="tl-row editing" data-id="${esc(e.id)}">
      <input type="time" class="tl-edit-at" value="${esc(hhmm(e.at))}" aria-label="Finished at" />
      <input type="text" class="tl-edit-text" value="${esc(e.text)}" aria-label="What you finished" />
      <select class="tl-edit-task" aria-label="Task">${taskOptions(e.taskId)}</select>
      <span class="tl-acts">
        <button type="button" class="icon-btn" data-act="save" data-no-icon title="Save (Return)" aria-label="Save">${window.icon('check', { size: 15 })}</button>
        <button type="button" class="icon-btn" data-act="cancel" data-no-icon title="Cancel (Esc)" aria-label="Cancel">${window.icon('x', { size: 15 })}</button>
      </span>
    </li>` : `
    <li class="tl-row${e.from ? '' : ' start'}${e.id === fresh ? ' fresh' : ''}" data-id="${esc(e.id)}">
      <span class="tl-when">${e.from ? `${esc(hhmm(e.from))}–` : ''}${esc(hhmm(e.at))}</span>
      <span class="tl-len">${e.from ? esc(length(e.mins)) : 'Start'}</span>
      <span class="tl-text">${esc(e.text)}${e.taskId ? ` <button type="button" class="tk-chip tl-task" data-task="${esc(e.taskId)}" data-no-icon title="Open the task">${window.icon('check', { size: 12 })}${esc(taskName(e.taskId))}</button>` : ''}</span>
      <span class="tl-acts">
        <button type="button" class="icon-btn" data-act="edit" data-no-icon title="Change" aria-label="Change">${window.icon('edit', { size: 15 })}</button>
        <button type="button" class="icon-btn icon-danger" data-act="delete" data-no-icon title="Remove" aria-label="Remove">${window.icon('trash', { size: 15 })}</button>
      </span>
    </li>`).join('')
    : `<li class="tl-empty">${day === today ? 'Nothing logged yet today. Your first entry starts the clock.' : 'Nothing logged on this day.'}</li>`;
  fresh = '';
  const ed = $('tl-list').querySelector('.tl-edit-text');
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
setInterval(tick, 30000);

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

async function openTask(id) {
  const r = taskRow(id);
  if (!r) return;
  const [projects, people] = await Promise.all([window.api.projects.list(), window.api.tasks.people()]);
  if (await window.editTask(r.task, { projects: (projects || []).filter((p) => p.status !== 'Archived'), people })) await window.appRefresh();
}

$('tl-input').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); add(); }
  if (e.key === 'Escape') e.target.blur();
});
$('tl-prev').addEventListener('click', () => show(ymd(addDays(dayOf(day), -1))));
$('tl-next').addEventListener('click', () => show(ymd(addDays(dayOf(day), 1))));
$('tl-week').addEventListener('click', (e) => { const b = e.target.closest('[data-day]'); if (b) show(b.dataset.day); });
$('tl-list').addEventListener('click', async (e) => {
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
$('tl-list').addEventListener('keydown', (e) => {
  const li = e.target.closest('.tl-row.editing');
  if (!li || e.target.tagName === 'SELECT') return;
  if (e.key === 'Enter') { e.preventDefault(); saveEdit(li); }
  if (e.key === 'Escape') { e.preventDefault(); editing = ''; render(); }
});

window.timeLog = {
  load,
  chain,
  taskTotals,
  length,
  shown: () => { if (!$('tl-input').matches(':focus')) $('tl-input').focus(); },
  go: (delta) => show(ymd(addDays(dayOf(day), delta))),
  today: () => show(ymd(new Date())),
  focus: () => $('tl-input').focus(),
};
load();
})();

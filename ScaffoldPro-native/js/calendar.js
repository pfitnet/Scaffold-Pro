'use strict';

// The Calendar: a month of everything dated in ScaffoldPro (from
// calendar:events), with the chosen day's list and the next 14 days beside
// it. Each kind can be switched off; the choice is remembered on this Mac.

const KINDS = [
  { key: 'Delivery', label: 'Deliveries', color: '#5B7DB1' },
  { key: 'Inspection', label: 'Inspections', color: '#B07A5E' },
  { key: 'Task', label: 'Tasks', color: '#5E8C6A' },
  { key: 'Quotation', label: 'Quotations', color: '#8E72A8' },
  { key: 'Invoice', label: 'Payments due', color: '#A66A6A' },
  { key: 'Lead', label: 'Leads', color: '#4F8A8F' },
  { key: 'Expiry', label: 'Expiring', color: '#9A8458' },
  { key: 'Project', label: 'Projects', color: '#6B7078' },
];
const COLOR = Object.fromEntries(KINDS.map((k) => [k.key, k.color]));

let view = 'week';      // 'week' (hours down) or 'month'
try { if (localStorage.getItem('calendar.view') === 'month') view = 'month'; } catch (e) { /* ignore */ }
let weekStart = null;   // the Monday of the week shown
let month = null;       // first of the month shown
let selected = null;    // yyyy-MM-dd
let events = [];
let agenda = [];
let hidden = new Set();
try { hidden = new Set(JSON.parse(localStorage.getItem('calendar.hidden') || '[]')); } catch (e) { /* ignore */ }

const pad = (n) => String(n).padStart(2, '0');
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const shown = (list) => list.filter((e) => !hidden.has(e.kind));

function gridStart() {
  // Weeks start on Monday.
  const d = new Date(month);
  d.setDate(1 - ((d.getDay() + 6) % 7));
  return d;
}

function mondayOf(d) {
  const x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  x.setDate(x.getDate() - ((x.getDay() + 6) % 7));
  return x;
}

// Where the week view starts: the day before (so today is the 2nd column
// — the standard), today, Monday or Sunday. Remembered on this Mac.
let weekMode = 'yesterday';
try { weekMode = localStorage.getItem('calendar.weekStart') || 'yesterday'; } catch (e) { /* ignore */ }
function weekStartFor(d) {
  const x = new Date(d.getFullYear(), d.getMonth(), d.getDate());
  if (weekMode === 'yesterday') x.setDate(x.getDate() - 1);
  else if (weekMode === 'monday') x.setDate(x.getDate() - ((x.getDay() + 6) % 7));
  else if (weekMode === 'sunday') x.setDate(x.getDate() - x.getDay());
  return x;
}

// ⌘Z / ⌘Y redraw the page with this, not a reload (js/undo.js).
window.appRefresh = () => load();

async function load() {
  const start = view === 'week' ? new Date(weekStart) : gridStart();
  const end = new Date(start);
  end.setDate(end.getDate() + (view === 'week' ? 6 : 41));
  const today = new Date();
  const soon = new Date();
  soon.setDate(soon.getDate() + 14);
  [events, agenda] = await Promise.all([
    window.api.calendar.events(ymd(start), ymd(end)),
    window.api.calendar.events(ymd(today), ymd(soon)),
  ]);
  events = events || [];
  agenda = agenda || [];
  render();
}

function chip(e) {
  return `<div class="cal-ev${e.done ? ' done' : ''}${e.overdue ? ' overdue' : ''}" style="--k:${COLOR[e.kind] || '#888'}" title="${esc(e.title)}${e.detail ? ` — ${esc(e.detail)}` : ''}">${esc(e.title)}</div>`;
}

function item(e) {
  return `<a class="ev-item${e.done ? ' done' : ''}${e.overdue ? ' overdue' : ''}" style="--k:${COLOR[e.kind] || '#888'}" href="${esc(e.url || '#')}">
    <div class="ev-kind">${esc((KINDS.find((k) => k.key === e.kind) || {}).label || e.kind)}${e.overdue ? ' · overdue' : ''}</div>
    <div class="ev-title">${e.time ? `<b>${esc(e.time)}</b> ` : ''}${esc(e.title)}</div>
    ${e.detail ? `<div class="sub">${esc(e.detail)}</div>` : ''}
    ${e.person ? `<div class="sub">${window.personTag(e.person)}</div>` : ''}</a>`;
}

function render() {
  for (const b of document.querySelectorAll('#cal-view button')) b.classList.toggle('active', b.dataset.view === view);
  document.getElementById('cal-grid').classList.toggle('hidden', view !== 'month');
  document.getElementById('cal-week').classList.toggle('hidden', view !== 'week');
  if (view === 'week') {
    const end = new Date(weekStart);
    end.setDate(end.getDate() + 6);
    const sameMonth = end.getMonth() === weekStart.getMonth();
    document.getElementById('cal-title').textContent = `${weekStart.toLocaleDateString('en-GB', { day: 'numeric', month: sameMonth ? undefined : 'short' }).replace('Sept', 'Sep')} – ${end.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace('Sept', 'Sep')}`;
  } else {
    document.getElementById('cal-title').textContent = month.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' });
  }
  document.getElementById('cal-filters').innerHTML = KINDS.map((k) => `<label class="cal-filter${hidden.has(k.key) ? ' off' : ''}" style="--k:${k.color}">
    <input type="checkbox" data-kind="${k.key}" ${hidden.has(k.key) ? '' : 'checked'} /><span class="cal-dot" style="width:8px;height:8px;border-radius:50%;background:${k.color};display:inline-block"></span>${k.label}</label>`).join('');
  for (const box of document.querySelectorAll('#cal-filters input')) {
    box.addEventListener('change', () => {
      if (box.checked) hidden.delete(box.dataset.kind); else hidden.add(box.dataset.kind);
      try { localStorage.setItem('calendar.hidden', JSON.stringify([...hidden])); } catch (e) { /* ignore */ }
      render();
    });
  }
  const byDay = {};
  for (const e of shown(events)) (byDay[e.date] = byDay[e.date] || []).push(e);
  const start = gridStart();
  const today = ymd(new Date());
  if (view === 'week') renderWeek(byDay, today);
  const heads = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'].map((d) => `<div class="cal-head">${d}</div>`).join('');
  let cells = '';
  for (let i = 0; i < 42; i++) {
    const d = new Date(start);
    d.setDate(start.getDate() + i);
    const key = ymd(d);
    const list = byDay[key] || [];
    cells += `<div class="cal-day${d.getMonth() !== month.getMonth() ? ' other' : ''}${key === today ? ' today' : ''}${key === selected ? ' selected' : ''}" data-day="${key}">
      <div class="cal-num">${d.getDate()}</div>${list.slice(0, 4).map(chip).join('')}${list.length > 4 ? `<div class="cal-more">+${list.length - 4} more</div>` : ''}</div>`;
  }
  if (view === 'month') document.getElementById('cal-grid').innerHTML = heads + cells;
  for (const cell of document.querySelectorAll('.cal-day')) {
    cell.addEventListener('click', () => { selected = cell.dataset.day; render(); });
  }
  // The chosen day.
  const sel = selected || today;
  const d = new Date(`${sel}T00:00:00`);
  document.getElementById('day-title').textContent = sel === today ? 'Today' : d.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long' });
  const dayList = byDay[sel] || [];
  document.getElementById('day-events').innerHTML = dayList.length ? dayList.map(item).join('') : '<div class="empty-inline">Nothing on this day.</div>';
  // The next 14 days, by day.
  const next = shown(agenda).filter((e) => !e.done);
  const groups = {};
  for (const e of next) (groups[e.date] = groups[e.date] || []).push(e);
  document.getElementById('agenda').innerHTML = Object.keys(groups).length
    ? Object.keys(groups).sort().map((k) => `<div class="ev-day">${k === today ? 'Today' : new Date(`${k}T00:00:00`).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' }).replace('Sept', 'Sep')}</div>${groups[k].map(item).join('')}`).join('')
    : '<div class="empty-inline">Nothing coming up.</div>';
}

// The week: an all-day row (things without a time), then the hours, with
// timed items at their time. Clicking an empty hour adds a task then.
const HOUR_PX = 48;
let scrolledOnce = false;
function renderWeek(byDay, today) {
  const days = [...Array(7)].map((_, i) => { const d = new Date(weekStart); d.setDate(d.getDate() + i); return d; });
  const box = document.getElementById('cal-week');
  const head = '<div></div>' + days.map((d) => `<div class="${ymd(d) === today ? 'today' : ''}" data-day="${ymd(d)}">${d.toLocaleDateString('en-GB', { weekday: 'short' })} <span class="wd-num">${d.getDate()}</span></div>`).join('');
  const allDay = '<div class="gutter">all day</div>' + days.map((d) => {
    const list = (byDay[ymd(d)] || []).filter((e) => !e.time);
    return `<div data-day="${ymd(d)}">${list.map(chip).join('')}</div>`;
  }).join('');
  const gutter = `<div class="week-gutter">${[...Array(24)].map((_, h) => `<div class="hour-label">${h ? `${String(h).padStart(2, '0')}:00` : ''}</div>`).join('')}</div>`;
  const cols = days.map((d) => {
    const key = ymd(d);
    const timed = (byDay[key] || []).filter((e) => e.time);
    const evs = timed.map((e) => {
      const [h, m] = e.time.split(':').map(Number);
      const top = (h + m / 60) * HOUR_PX;
      return `<a class="week-ev${e.done ? ' done' : ''}" style="--k:${COLOR[e.kind] || '#888'};top:${top}px;height:${HOUR_PX - 4}px" href="${esc(e.url || '#')}" title="${esc(e.title)}${e.detail ? ` — ${esc(e.detail)}` : ''}">
        <span class="t">${esc(e.time)}</span> ${esc(e.title)}${e.detail ? `<div class="sub">${esc(e.detail)}</div>` : ''}</a>`;
    }).join('');
    const now = new Date();
    const line = key === today ? `<div class="now-line" style="top:${(now.getHours() + now.getMinutes() / 60) * HOUR_PX}px"></div>` : '';
    return `<div class="week-col${key === today ? ' today' : ''}" data-day="${key}">${[...Array(24)].map((_, h) => `<div class="slot" data-hour="${h}"></div>`).join('')}${evs}${line}</div>`;
  }).join('');
  const body = box.querySelector('.week-body');
  const keepScroll = body ? body.scrollTop : null;
  // One scroller for the day heads, the all-day row and the hours, so the
  // columns stay lined up whether or not a scroll bar is showing; the heads
  // stay put at the top while the hours scroll under them.
  box.innerHTML = `<div class="week-body"><div class="week-top"><div class="week-head">${head}</div><div class="week-allday">${allDay}</div></div><div class="week-hours">${gutter}${cols}</div></div>`;
  const newBody = box.querySelector('.week-body');
  // Opens at 7 a.m. the first time; keeps its place after that.
  newBody.scrollTop = keepScroll !== null && scrolledOnce ? keepScroll : 7 * HOUR_PX;
  scrolledOnce = true;
  for (const slot of box.querySelectorAll('.slot')) {
    slot.addEventListener('click', async () => {
      const day = slot.closest('.week-col').dataset.day;
      const hour = String(slot.dataset.hour).padStart(2, '0');
      const [projects, people] = await Promise.all([window.api.projects.list(), window.api.tasks.people()]);
      if (await window.editTask(null, { projects: (projects || []).filter((p) => p.status !== 'Archived'), people, dueDate: day, dueTime: `${hour}:00` })) load();
    });
  }
  for (const cell of box.querySelectorAll('.week-allday [data-day], .week-head > div')) {
    cell.addEventListener('click', () => { if (cell.dataset.day) { selected = cell.dataset.day; render(); } });
  }
}

function go(delta) {
  if (view === 'week') {
    weekStart = new Date(weekStart.getFullYear(), weekStart.getMonth(), weekStart.getDate() + 7 * delta);
    selected = ymd(weekStart);
  } else {
    month = new Date(month.getFullYear(), month.getMonth() + delta, 1);
  }
  load();
}

function setView(v) {
  view = v;
  try { localStorage.setItem('calendar.view', v); } catch (e) { /* ignore */ }
  const anchor = selected ? new Date(`${selected}T00:00:00`) : new Date();
  weekStart = weekStartFor(anchor);
  month = new Date(anchor.getFullYear(), anchor.getMonth(), 1);
  load();
}

(async function init() {
  const now = new Date();
  month = new Date(now.getFullYear(), now.getMonth(), 1);
  weekStart = weekStartFor(now);
  selected = ymd(now);
  const startSel = document.getElementById('cal-week-start');
  startSel.value = weekMode;
  startSel.addEventListener('change', () => {
    weekMode = startSel.value;
    try { localStorage.setItem('calendar.weekStart', weekMode); } catch (e) { /* ignore */ }
    weekStart = weekStartFor(selected ? new Date(`${selected}T00:00:00`) : new Date());
    load();
  });
  for (const b of document.querySelectorAll('#cal-view button')) b.addEventListener('click', () => setView(b.dataset.view));
  document.getElementById('cal-prev').addEventListener('click', () => go(-1));
  document.getElementById('cal-next').addEventListener('click', () => go(1));
  document.getElementById('cal-today').addEventListener('click', () => { const n = new Date(); month = new Date(n.getFullYear(), n.getMonth(), 1); weekStart = weekStartFor(n); selected = ymd(n); load(); });
  await window.loadPersonColors();
  await load();
})();

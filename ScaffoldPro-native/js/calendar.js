'use strict';

// The Calendar: everything dated in ScaffoldPro (from calendar:events) by
// week (hours down, things without a time in an all-day row) or by month.
// Beside it: a mini month to jump around, the chosen day, and the next 14
// days. Each kind can be switched off (⌥-click: only that kind); the
// choices are remembered on this Mac. Hover an item for a preview; click it
// to open it. Events (a start and an end: a meeting, a site visit) are
// blocks on the week; drag down an empty column to make one. Keys: ←/→ day,
// ↑/↓ week, T today, W/M view, N new task, E new event.

const ICON = (d) => `<svg viewBox="0 0 20 20" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
const KINDS = [
  { key: 'Delivery', label: 'Deliveries', one: 'Delivery', color: '#5B7DB1', icon: ICON('<path d="M2.5 5.5h9v8h-9z"/><path d="M11.5 8.5h3.2l2.8 2.8v2.2h-6"/><circle cx="6" cy="14.5" r="1.6"/><circle cx="14" cy="14.5" r="1.6"/>') },
  { key: 'Inspection', label: 'Inspections', one: 'Inspection', color: '#B07A5E', icon: ICON('<path d="M10 2.5 16 5v4.5c0 4-2.6 6.6-6 8-3.4-1.4-6-4-6-8V5z"/><path d="m7.3 10 2 2 3.6-3.8"/>') },
  { key: 'Event', label: 'Events', one: 'Event', color: '#4F6F96', icon: ICON('<rect x="3" y="4" width="14" height="13" rx="3"/><path d="M3 8h14M7 2.5v3M13 2.5v3"/><path d="M7 11.5h3"/>') },
  { key: 'Task', label: 'Tasks', one: 'Task', color: '#5E8C6A', icon: ICON('<rect x="3" y="3" width="14" height="14" rx="3.5"/><path d="m6.8 10.2 2.2 2.2 4.3-4.6"/>') },
  { key: 'Quotation', label: 'Quotations', one: 'Quotation', color: '#8E72A8', icon: ICON('<path d="M11.5 2.5h-6A1.5 1.5 0 0 0 4 4v12a1.5 1.5 0 0 0 1.5 1.5h9A1.5 1.5 0 0 0 16 16V7z"/><path d="M11.5 2.5V7H16M7 11h6M7 14h4"/>') },
  { key: 'Invoice', label: 'Payments due', one: 'Payment due', color: '#A66A6A', icon: ICON('<rect x="2.5" y="5" width="15" height="10.5" rx="2"/><path d="M2.5 8.5h15M5.5 12.5h3"/>') },
  { key: 'Lead', label: 'Leads', one: 'Lead', color: '#4F8A8F', icon: ICON('<path d="M3.5 8v4l2 .5 1.5 4h2l-1-3.6 7.5 2.6V4.5L8 7.2z"/>') },
  { key: 'Expiry', label: 'Expiring', one: 'Expiring', color: '#9A8458', icon: ICON('<circle cx="10" cy="10.5" r="6.5"/><path d="M10 7v3.7l2.3 1.5M8 2.5h4"/>') },
  { key: 'Project', label: 'Projects', one: 'Project', color: '#6B7078', icon: ICON('<path d="M2.5 6V5a1.5 1.5 0 0 1 1.5-1.5h3.2l1.6 1.8H16A1.5 1.5 0 0 1 17.5 6.8V15a1.5 1.5 0 0 1-1.5 1.5H4A1.5 1.5 0 0 1 2.5 15z"/>') },
];
const KIND = Object.fromEntries(KINDS.map((k) => [k.key, k]));
const colorOf = (e) => (KIND[e.kind] || {}).color || '#888';

let view = 'week';      // 'week' (hours down) or 'month'
try { if (localStorage.getItem('calendar.view') === 'month') view = 'month'; } catch (e) { /* ignore */ }
let weekStart = null;   // the first day of the week shown
let month = null;       // first of the month shown
let miniMonth = null;   // first of the month in the mini calendar
let selected = null;    // yyyy-MM-dd
let events = [];
let agenda = [];
let miniEvents = [];
let hidden = new Set();
try { hidden = new Set(JSON.parse(localStorage.getItem('calendar.hidden') || '[]')); } catch (e) { /* ignore */ }

const pad = (n) => String(n).padStart(2, '0');
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const dayOf = (key) => new Date(`${key}T00:00:00`);
const addDays = (d, n) => new Date(d.getFullYear(), d.getMonth(), d.getDate() + n);
const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const fmt = (d, o) => d.toLocaleDateString('en-GB', o).replace('Sept', 'Sep');
const shown = (list) => list.filter((e) => !hidden.has(e.kind));
const todayKey = () => ymd(new Date());

// Every item drawn gets an index, so a hover can show its preview.
let drawn = [];
const ref = (e) => { drawn.push(e); return drawn.length - 1; };

function gridStart(m) {
  // Month grids start on Sunday.
  const d = new Date(m);
  d.setDate(1 - d.getDay());
  return d;
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

function range() {
  const start = view === 'week' ? new Date(weekStart) : gridStart(month);
  return [start, addDays(start, view === 'week' ? 6 : 41)];
}

async function load(slide) {
  const [start, end] = range();
  const now = new Date();
  const miniStart = gridStart(miniMonth);
  [events, agenda, miniEvents] = await Promise.all([
    window.api.calendar.events(ymd(start), ymd(end)),
    window.api.calendar.events(ymd(now), ymd(addDays(now, 14))),
    window.api.calendar.events(ymd(miniStart), ymd(addDays(miniStart, 41))),
  ]);
  events = events || [];
  agenda = agenda || [];
  miniEvents = miniEvents || [];
  render(slide);
}

async function loadMini() {
  const s = gridStart(miniMonth);
  miniEvents = (await window.api.calendar.events(ymd(s), ymd(addDays(s, 41)))) || [];
  renderMini();
}

const byDayOf = (list) => {
  const out = {};
  for (const e of shown(list)) (out[e.date] = out[e.date] || []).push(e);
  for (const k of Object.keys(out)) out[k].sort((a, b) => (a.time || '').localeCompare(b.time || ''));
  return out;
};

// ---------- Drawing ----------

function render(slide) {
  drawn = [];
  for (const b of document.querySelectorAll('#cal-view button')) b.classList.toggle('active', b.dataset.view === view);
  document.getElementById('cal-grid').classList.toggle('hidden', view !== 'month');
  document.getElementById('cal-week').classList.toggle('hidden', view !== 'week');
  renderTitle();
  renderFilters();
  const byDay = byDayOf(events);
  if (view === 'week') renderWeek(byDay); else renderMonth(byDay);
  renderSummary();
  renderMini();
  renderDay(byDay);
  renderAgenda();
  const [start, end] = range();
  const t = todayKey();
  document.getElementById('cal-today').classList.toggle('here', t >= ymd(start) && t <= ymd(end));
  if (slide) {
    const main = document.getElementById(view === 'week' ? 'cal-week' : 'cal-grid');
    main.classList.remove('slide-next', 'slide-prev');
    void main.offsetWidth;
    main.classList.add(slide > 0 ? 'slide-next' : 'slide-prev');
  }
}

function renderTitle() {
  const title = document.getElementById('cal-title');
  const eyebrow = document.getElementById('cal-eyebrow');
  if (view === 'week') {
    const end = addDays(weekStart, 6);
    const sameMonth = end.getMonth() === weekStart.getMonth();
    title.innerHTML = `${esc(fmt(weekStart, { day: 'numeric', month: sameMonth ? undefined : 'short' }))} – ${esc(fmt(end, { day: 'numeric', month: 'short' }))} <span class="cal-year">${end.getFullYear()}</span>`;
    // ISO week number of the week's Thursday-ish middle.
    const mid = addDays(weekStart, 3);
    const jan4 = new Date(mid.getFullYear(), 0, 4);
    const week = 1 + Math.round(((mid - jan4) / 864e5 - 3 + ((jan4.getDay() + 6) % 7)) / 7);
    eyebrow.textContent = `Calendar · Week ${week}`;
  } else {
    title.innerHTML = `${esc(fmt(month, { month: 'long' }))} <span class="cal-year">${month.getFullYear()}</span>`;
    eyebrow.textContent = 'Calendar · Month';
  }
}

function renderFilters() {
  const counts = {};
  for (const e of events) counts[e.kind] = (counts[e.kind] || 0) + 1;
  const box = document.getElementById('cal-filters');
  box.innerHTML = KINDS.map((k) => `<button type="button" class="cal-filter${hidden.has(k.key) ? ' off' : ''}" data-kind="${k.key}" style="--k:${k.color}" aria-pressed="${!hidden.has(k.key)}" data-no-icon
      title="${hidden.has(k.key) ? 'Show' : 'Hide'} ${esc(k.label.toLowerCase())} · ⌥-click to show only these">
      <span class="cf-dot"></span>${esc(k.label)}${counts[k.key] ? `<span class="cf-n">${counts[k.key]}</span>` : ''}</button>`).join('');
  for (const b of box.querySelectorAll('.cal-filter')) {
    b.addEventListener('click', (e) => {
      const k = b.dataset.kind;
      if (e.altKey) {
        // Only this kind — or everything again if it already is.
        const only = KINDS.every((x) => (x.key === k) !== hidden.has(x.key));
        hidden = only ? new Set() : new Set(KINDS.map((x) => x.key).filter((x) => x !== k));
      } else if (hidden.has(k)) hidden.delete(k); else hidden.add(k);
      try { localStorage.setItem('calendar.hidden', JSON.stringify([...hidden])); } catch (err) { /* ignore */ }
      render();
    });
  }
}

// What's on in the period: a chip per kind, and anything overdue.
function renderSummary() {
  const list = shown(events).filter((e) => !e.done);
  const counts = {};
  for (const e of list) counts[e.kind] = (counts[e.kind] || 0) + 1;
  const overdue = list.filter((e) => e.overdue).length;
  const parts = KINDS.filter((k) => counts[k.key]).map((k) => `<span class="cs-chip" style="--k:${k.color}">${k.icon}<b>${counts[k.key]}</b> ${esc(counts[k.key] === 1 ? k.one : k.label).toLowerCase()}</span>`);
  if (overdue) parts.unshift(`<span class="cs-chip overdue"><b>${overdue}</b> overdue</span>`);
  document.getElementById('cal-summary').innerHTML = parts.length
    ? `<span class="cs-lead">This ${view === 'week' ? 'week' : 'month'}</span>${parts.join('')}`
    : `<span class="cs-lead">Nothing on this ${view === 'week' ? 'week' : 'month'} — a clear run.</span>`;
}

function chip(e) {
  return `<a class="cal-ev${e.done ? ' done' : ''}${e.overdue ? ' overdue' : ''}" style="--k:${colorOf(e)}" href="${esc(e.url || '#')}" data-ev="${ref(e)}">${e.time ? `<span class="t">${esc(e.time)}</span>` : ''}<span class="tt">${esc(e.title)}</span></a>`;
}

// The week's all-day row: the whole title over up to three lines (the
// columns are narrow), document numbers like DN26210-004 kept in one piece.
function allDayChip(e) {
  const title = esc(e.title).replace(/(\w)-(?=\w)/g, '$1\u2011');
  return `<a class="cal-ev ad${e.done ? ' done' : ''}${e.overdue ? ' overdue' : ''}" style="--k:${colorOf(e)}" href="${esc(e.url || '#')}" data-ev="${ref(e)}"><span class="ad-t">${title}</span></a>`;
}

function renderMonth(byDay) {
  const start = gridStart(month);
  const today = todayKey();
  const heads = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'].map((d, i) => `<div class="cal-head${i === 0 || i === 6 ? ' wkend' : ''}">${d}</div>`).join('');
  let cells = '';
  for (let i = 0; i < 42; i++) {
    const d = addDays(start, i);
    const key = ymd(d);
    const list = byDay[key] || [];
    const wkend = d.getDay() === 0 || d.getDay() === 6;
    cells += `<div class="cal-day${d.getMonth() !== month.getMonth() ? ' other' : ''}${wkend ? ' wkend' : ''}${key === today ? ' today' : ''}${key < today ? ' past' : ''}${key === selected ? ' selected' : ''}" data-day="${key}" style="--i:${i}">
      <div class="cal-day-top"><span class="cal-num">${d.getDate()}</span><button class="cal-day-add" data-add="${key}" data-no-icon title="Add a task on ${esc(fmt(d, { day: 'numeric', month: 'short' }))}" aria-label="Add a task">+</button></div>
      ${list.slice(0, 3).map(chip).join('')}${list.length > 3 ? `<button class="cal-more" data-day-more="${key}" data-no-icon>+${list.length - 3} more</button>` : ''}</div>`;
  }
  const grid = document.getElementById('cal-grid');
  grid.innerHTML = `<div class="cal-month-head">${heads}</div><div class="cal-month-body">${cells}</div>`;
  for (const cell of grid.querySelectorAll('.cal-day')) {
    cell.addEventListener('click', (e) => {
      if (e.target.closest('a, .cal-day-add')) return;
      select(cell.dataset.day);
    });
    cell.addEventListener('dblclick', (e) => { if (!e.target.closest('a')) addTask(cell.dataset.day); });
  }
  for (const b of grid.querySelectorAll('.cal-day-add')) b.addEventListener('click', () => addTask(b.dataset.add));
}

// Items at the same time sit side by side. An event lasts until its end;
// anything else counts as an hour long.
const minutesOf = (t) => { const [h, m] = String(t).split(':').map(Number); return h * 60 + (m || 0); };
function lanes(timed) {
  const items = timed.map((e) => {
    const s = minutesOf(e.time);
    const end = e.endTime ? Math.max(s + 30, minutesOf(e.endTime)) : s + 60;
    return { e, s, end };
  }).sort((a, b) => a.s - b.s || b.end - a.end);
  const out = [];
  let cluster = [];
  let clusterEnd = -1;
  const flush = () => {
    const ends = [];
    for (const it of cluster) {
      let i = ends.findIndex((x) => x <= it.s);
      if (i < 0) { i = ends.length; ends.push(0); }
      ends[i] = it.end;
      it.lane = i;
    }
    for (const it of cluster) it.lanes = ends.length;
    out.push(...cluster);
    cluster = [];
  };
  for (const it of items) {
    if (cluster.length && it.s >= clusterEnd) flush();
    cluster.push(it);
    clusterEnd = Math.max(clusterEnd, it.end);
  }
  if (cluster.length) flush();
  return out;
}

const HOUR_PX = 52;
let scrolledOnce = false;
function renderWeek(byDay) {
  const today = todayKey();
  const days = [...Array(7)].map((_, i) => addDays(weekStart, i));
  const box = document.getElementById('cal-week');
  const head = '<div class="wk-corner"></div>' + days.map((d) => {
    const key = ymd(d);
    const list = byDay[key] || [];
    const kinds = [...new Set(list.map((e) => e.kind))].slice(0, 4);
    return `<div class="wk-day${key === today ? ' today' : ''}${key === selected ? ' selected' : ''}${key < today ? ' past' : ''}" data-day="${key}">
      <span class="wd-name">${esc(fmt(d, { weekday: 'short' }))}</span><span class="wd-num">${d.getDate()}</span>
      <span class="wd-dots">${kinds.map((k) => `<i style="--k:${KIND[k] ? KIND[k].color : '#888'}"></i>`).join('')}</span></div>`;
  }).join('');
  const allDay = '<div class="gutter">all day</div>' + days.map((d) => {
    const list = (byDay[ymd(d)] || []).filter((e) => !e.time);
    return `<div class="wk-allday-cell${ymd(d) === today ? ' today' : ''}" data-day="${ymd(d)}">${list.slice(0, 3).map(allDayChip).join('')}${list.length > 3 ? `<button class="cal-more" data-day-more="${ymd(d)}" data-no-icon>+${list.length - 3} more</button>` : ''}</div>`;
  }).join('');
  const gutter = `<div class="week-gutter">${[...Array(24)].map((_, h) => `<div class="hour-label">${h ? `${pad(h)}:00` : ''}</div>`).join('')}</div>`;
  const cols = days.map((d) => {
    const key = ymd(d);
    const evs = lanes((byDay[key] || []).filter((e) => e.time)).map((it) => {
      const e = it.e;
      const w = 100 / it.lanes;
      const k = KIND[e.kind];
      const h = e.endTime ? ((it.end - it.s) / 60) * HOUR_PX - 3 : HOUR_PX - 3;
      return `<a class="week-ev${e.endTime ? ' is-event' : ''}${h < 34 ? ' short' : ''}${e.done ? ' done' : ''}${e.overdue ? ' overdue' : ''}" data-ev="${ref(e)}" href="${esc(e.url || '#')}"
        style="--k:${colorOf(e)};top:${(it.s / 60) * HOUR_PX + 1}px;height:${h}px;left:calc(${it.lane * w}% + 3px);width:calc(${w}% - 6px)">
        <span class="we-top">${k ? k.icon : ''}<span class="t">${esc(e.time)}${e.endTime && h >= 34 ? `–${esc(e.endTime)}` : ''}</span></span>
        <span class="we-title">${esc(e.title)}</span>${e.detail ? `<span class="we-sub">${esc(e.detail)}</span>` : ''}</a>`;
    }).join('');
    const wkend = d.getDay() === 0 || d.getDay() === 6;
    return `<div class="week-col${key === today ? ' today' : ''}${wkend ? ' wkend' : ''}${key < today ? ' past' : ''}" data-day="${key}">${[...Array(24)].map((_, h) => `<div class="slot" data-hour="${h}" data-label="+ ${pad(h)}:00"></div>`).join('')}${evs}</div>`;
  }).join('');
  const body = box.querySelector('.week-body');
  const keepScroll = body ? body.scrollTop : null;
  // One scroller for the day heads, the all-day row and the hours, so the
  // columns stay lined up whether or not a scroll bar is showing; the heads
  // stay put at the top while the hours scroll under them.
  box.innerHTML = `<div class="week-body"><div class="week-top"><div class="week-head">${head}</div><div class="week-allday">${allDay}</div></div>
    <div class="week-hours">${gutter}${cols}<div class="now-rule" aria-hidden="true"><span class="now-badge"></span></div></div></div>`;
  placeNow();
  const newBody = box.querySelector('.week-body');
  // Opens an hour before now (or at 7 a.m.) the first time; keeps its place
  // after that. A little above the hour, so its label isn't cut in half
  // under the day heads.
  const firstHour = days.some((d) => ymd(d) === today) ? Math.max(0, Math.min(new Date().getHours() - 1, 7)) : 7;
  newBody.scrollTop = keepScroll !== null && scrolledOnce ? keepScroll : Math.max(0, firstHour * HOUR_PX - 14);
  scrolledOnce = true;
  wireDragToSchedule(box);
  for (const cell of box.querySelectorAll('.wk-day, .wk-allday-cell')) {
    cell.addEventListener('click', (e) => { if (!e.target.closest('a')) select(cell.dataset.day); });
  }
}

// The red line at the time now: faint across the week, strong on today.
function placeNow() {
  const rule = document.querySelector('#cal-week .now-rule');
  if (!rule) return;
  const today = todayKey();
  const col = document.querySelector(`#cal-week .week-col[data-day="${today}"]`);
  if (!col) { rule.hidden = true; return; }
  const now = new Date();
  rule.hidden = false;
  rule.style.top = `${(now.getHours() + now.getMinutes() / 60) * HOUR_PX}px`;
  rule.style.setProperty('--today-left', `${col.offsetLeft}px`);
  rule.style.setProperty('--today-width', `${col.offsetWidth}px`);
  rule.querySelector('.now-badge').textContent = `${pad(now.getHours())}:${pad(now.getMinutes())}`;
}
setInterval(placeNow, 30000);
window.addEventListener('resize', placeNow);

function renderMini() {
  const box = document.getElementById('cal-mini');
  const start = gridStart(miniMonth);
  const byDay = byDayOf(miniEvents);
  const today = todayKey();
  const [rs, re] = range().map(ymd);
  let cells = '';
  for (let i = 0; i < 42; i++) {
    const d = addDays(start, i);
    const key = ymd(d);
    const kinds = [...new Set((byDay[key] || []).map((e) => e.kind))].slice(0, 3);
    cells += `<button class="mini-day${d.getMonth() !== miniMonth.getMonth() ? ' other' : ''}${key === today ? ' today' : ''}${key === selected ? ' selected' : ''}${key >= rs && key <= re ? ' in-view' : ''}" data-day="${key}" data-no-icon>
      <span>${d.getDate()}</span><span class="mini-dots">${kinds.map((k) => `<i style="--k:${KIND[k] ? KIND[k].color : '#888'}"></i>`).join('')}</span></button>`;
  }
  box.innerHTML = `<div class="mini-head">
      <div class="mini-title">${esc(fmt(miniMonth, { month: 'long' }))} <span>${miniMonth.getFullYear()}</span></div>
      <button class="cal-round sm" data-mini="-1" data-no-icon aria-label="Previous month"><svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><path d="M10 3.5 5.5 8l4.5 4.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg></button>
      <button class="cal-round sm" data-mini="1" data-no-icon aria-label="Next month"><svg viewBox="0 0 16 16" width="12" height="12" aria-hidden="true"><path d="M6 3.5 10.5 8 6 12.5" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg></button>
    </div>
    <div class="mini-grid">${['S', 'M', 'T', 'W', 'T', 'F', 'S'].map((x) => `<span class="mini-wd">${x}</span>`).join('')}${cells}</div>`;
  for (const b of box.querySelectorAll('[data-mini]')) {
    b.addEventListener('click', () => { miniMonth = new Date(miniMonth.getFullYear(), miniMonth.getMonth() + Number(b.dataset.mini), 1); loadMini(); });
  }
  for (const b of box.querySelectorAll('.mini-day')) b.addEventListener('click', () => jumpTo(b.dataset.day));
}

function item(e, withTime) {
  const k = KIND[e.kind] || { label: e.kind, icon: '' };
  return `<a class="ev-item${e.done ? ' done' : ''}${e.overdue ? ' overdue' : ''}" style="--k:${colorOf(e)}" href="${esc(e.url || '#')}" data-ev="${ref(e)}">
    ${withTime ? `<span class="ev-when">${e.time ? esc(e.time) : 'All day'}${e.endTime ? `<small>${esc(e.endTime)}</small>` : ''}</span>` : ''}
    <span class="ev-icon">${k.icon}</span>
    <span class="ev-body"><span class="ev-title">${esc(e.title)}</span>
    <span class="ev-meta">${esc(k.one || k.label)}${e.overdue ? ' · <b>overdue</b>' : ''}${e.detail ? ` · ${esc(e.detail)}` : ''}</span>
    ${e.person && window.personTag ? `<span class="ev-person">${window.personTag(e.person)}</span>` : ''}</span></a>`;
}

function renderDay(byDay) {
  const today = todayKey();
  const sel = selected || today;
  const d = dayOf(sel);
  document.getElementById('day-num').textContent = d.getDate();
  document.getElementById('day-num').classList.toggle('today', sel === today);
  document.getElementById('day-title').textContent = sel === today ? 'Today' : fmt(d, { weekday: 'long' });
  const list = byDay[sel] || shown(events.concat(miniEvents)).filter((e) => e.date === sel);
  const seen = new Set();
  const uniq = list.filter((e) => { const k = `${e.kind}|${e.title}|${e.time}`; if (seen.has(k)) return false; seen.add(k); return true; });
  document.getElementById('day-sub').textContent = `${fmt(d, { day: 'numeric', month: 'long', year: 'numeric' })}${uniq.length ? ` · ${uniq.length} item${uniq.length === 1 ? '' : 's'}` : ''}`;
  document.getElementById('day-events').innerHTML = uniq.length
    ? `<div class="ev-list">${uniq.map((e) => item(e, true)).join('')}</div>`
    : `<div class="cal-free"><span>Free day</span><button class="link-btn" id="day-free-add" data-no-icon>Add a task</button></div>`;
  const freeAdd = document.getElementById('day-free-add');
  if (freeAdd) freeAdd.addEventListener('click', () => addTask(sel));
}

function renderAgenda() {
  const today = todayKey();
  const next = shown(agenda).filter((e) => !e.done);
  const groups = {};
  for (const e of next) (groups[e.date] = groups[e.date] || []).push(e);
  const tomorrow = ymd(addDays(new Date(), 1));
  document.getElementById('agenda-count').textContent = next.length || '';
  document.getElementById('agenda').innerHTML = Object.keys(groups).length
    ? Object.keys(groups).sort().map((k) => `<div class="ev-day"><span>${k === today ? 'Today' : k === tomorrow ? 'Tomorrow' : esc(fmt(dayOf(k), { weekday: 'long' }))}</span><span class="ev-day-date">${esc(fmt(dayOf(k), { day: 'numeric', month: 'short' }))}</span></div>
      <div class="ev-list">${groups[k].sort((a, b) => (a.time || '').localeCompare(b.time || '')).map((e) => item(e, false)).join('')}</div>`).join('')
    : '<div class="cal-free"><span>Nothing in the next 14 days</span></div>';
}

// ---------- Moving around ----------

function select(key) {
  selected = key;
  const d = dayOf(key);
  if (miniMonth.getMonth() !== d.getMonth() || miniMonth.getFullYear() !== d.getFullYear()) {
    miniMonth = new Date(d.getFullYear(), d.getMonth(), 1);
    loadMini().then(() => render());
    return;
  }
  render();
}

// Show the period holding this day, and choose it.
function jumpTo(key) {
  const d = dayOf(key);
  const [start, end] = range();
  selected = key;
  miniMonth = new Date(d.getFullYear(), d.getMonth(), 1);
  if (key >= ymd(start) && key <= ymd(end) && (view === 'week' || d.getMonth() === month.getMonth())) { loadMini().then(() => render()); return; }
  const slide = key > ymd(end) ? 1 : -1;
  if (view === 'week') weekStart = weekStartFor(d); else month = new Date(d.getFullYear(), d.getMonth(), 1);
  load(slide);
}

function go(delta) {
  if (view === 'week') {
    weekStart = addDays(weekStart, 7 * delta);
    selected = ymd(addDays(dayOf(selected || todayKey()), 7 * delta));
  } else {
    month = new Date(month.getFullYear(), month.getMonth() + delta, 1);
    const s = dayOf(selected || todayKey());
    selected = ymd(new Date(month.getFullYear(), month.getMonth(), Math.min(s.getDate(), new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate())));
  }
  const s = dayOf(selected);
  miniMonth = new Date(s.getFullYear(), s.getMonth(), 1);
  load(delta);
}

function setView(v) {
  if (v === view) return;
  view = v;
  try { localStorage.setItem('calendar.view', v); } catch (e) { /* ignore */ }
  const anchor = dayOf(selected || todayKey());
  weekStart = weekStartFor(anchor);
  month = new Date(anchor.getFullYear(), anchor.getMonth(), 1);
  load();
}

function goToday() {
  const n = new Date();
  const was = selected;
  month = new Date(n.getFullYear(), n.getMonth(), 1);
  miniMonth = new Date(month);
  weekStart = weekStartFor(n);
  selected = ymd(n);
  load(was && was !== selected ? (was < selected ? 1 : -1) : 0);
}

// A new task — or, with an end time (or `event`), a new event.
async function addTask(day, time, endTime, event) {
  hidePeek();
  const [projects, people] = await Promise.all([window.api.projects.list(), window.api.tasks.people()]);
  const opts = { projects: (projects || []).filter((p) => p.status !== 'Archived'), people, dueDate: day || selected || todayKey() };
  if (time) opts.dueTime = time;
  if (endTime) opts.endTime = endTime;
  if (event) opts.event = true;
  const saved = await window.editTask(null, opts);
  clearGhost();
  if (saved) load();
}

// An event opens in the same sheet, here — not on the Tasks page.
async function editEvent(id) {
  hidePeek();
  const [task, projects, people] = await Promise.all([window.api.tasks.get(id), window.api.projects.list(), window.api.tasks.people()]);
  if (!task) return;
  if (await window.editTask(task, { projects: (projects || []).filter((p) => p.status !== 'Archived' || p.id === task.projectId), people })) load();
}
document.addEventListener('click', (ev) => {
  const el = ev.target.closest && ev.target.closest('[data-ev]');
  if (!el || ev.metaKey) return;
  const e = drawn[Number(el.dataset.ev)];
  if (!e || e.kind !== 'Event' || !e.id) return;
  ev.preventDefault();
  editEvent(e.id);
});

// ---------- Drag to schedule ----------
// Press on an empty part of a day's column and drag down (or up): the
// block snaps to quarter hours and shows its times; let go to name it.
// A plain click makes an hour from that slot.

const SNAP = 15;
let ghost = null;
function clearGhost() { if (ghost) { ghost.remove(); ghost = null; } }
const hhmm = (mins) => `${pad(Math.floor(mins / 60))}:${pad(mins % 60)}`;

function wireDragToSchedule(box) {
  for (const col of box.querySelectorAll('.week-col')) {
    col.addEventListener('pointerdown', (down) => {
      if (down.button !== 0 || down.target.closest('a, button')) return;
      down.preventDefault();
      clearGhost();
      hidePeek();
      const rect = col.getBoundingClientRect();
      const at = (y) => Math.max(0, Math.min(24 * 60, Math.round(((y - rect.top) / HOUR_PX) * 60 / SNAP) * SNAP));
      const anchor = Math.floor(((down.clientY - rect.top) / HOUR_PX) * 60 / SNAP) * SNAP;
      let from = anchor;
      let to = anchor + 60;
      let moved = false;
      ghost = document.createElement('div');
      ghost.className = 'week-ghost';
      col.appendChild(ghost);
      const draw = () => {
        ghost.style.top = `${(from / 60) * HOUR_PX + 1}px`;
        ghost.style.height = `${Math.max(12, ((to - from) / 60) * HOUR_PX - 3)}px`;
        ghost.innerHTML = `<span>${hhmm(from)} – ${hhmm(Math.min(to, 23 * 60 + 59))}</span>`;
      };
      draw();
      const onMove = (mv) => {
        const y = at(mv.clientY);
        if (!moved && Math.abs(mv.clientY - down.clientY) < 5) return;
        moved = true;
        ghost.classList.add('dragging');
        if (y > anchor) { from = anchor; to = Math.max(anchor + SNAP, y); } else { from = Math.min(y, anchor); to = anchor + SNAP; }
        draw();
      };
      const onUp = () => {
        document.removeEventListener('pointermove', onMove);
        document.removeEventListener('pointerup', onUp);
        ghost.classList.remove('dragging');
        addTask(col.dataset.day, hhmm(from), hhmm(Math.min(to, 23 * 60 + 59)), true);
      };
      document.addEventListener('pointermove', onMove);
      document.addEventListener('pointerup', onUp);
    });
  }
}

// ---------- Preview on hover ----------

const peek = document.createElement('div');
peek.className = 'cal-peek';
peek.setAttribute('role', 'tooltip');
document.body.appendChild(peek);
let peekTimer = null;
let peekFor = null;
function hidePeek() { clearTimeout(peekTimer); peekFor = null; peek.classList.remove('open'); }
function showPeek(el) {
  const e = drawn[Number(el.dataset.ev)];
  if (!e) return;
  const k = KIND[e.kind] || { label: e.kind, one: e.kind, icon: '' };
  const d = dayOf(e.date);
  peek.style.setProperty('--k', colorOf(e));
  peek.innerHTML = `<div class="pk-kind"><span class="pk-icon">${k.icon}</span>${esc(k.one || k.label)}${e.overdue ? '<span class="pk-flag">Overdue</span>' : ''}${e.done ? '<span class="pk-flag done">Done</span>' : ''}</div>
    <div class="pk-title">${esc(e.title)}</div>
    ${e.detail ? `<div class="pk-detail">${esc(e.detail)}</div>` : ''}
    <div class="pk-when">${esc(fmt(d, { weekday: 'long', day: 'numeric', month: 'long' }))}${e.time ? ` · ${esc(e.time)}${e.endTime ? `–${esc(e.endTime)}` : ''}` : ''}</div>
    ${e.person && window.personTag ? `<div class="pk-person">${window.personTag(e.person)}</div>` : ''}
    ${e.url && e.url !== '#' ? `<div class="pk-hint">Click to ${e.kind === 'Event' ? 'edit' : 'open'}</div>` : ''}`;
  const r = el.getBoundingClientRect();
  peek.classList.add('measure');
  const pw = peek.offsetWidth;
  const ph = peek.offsetHeight;
  peek.classList.remove('measure');
  let x = r.right + 10;
  let side = 'right';
  if (x + pw > window.innerWidth - 12) { x = r.left - pw - 10; side = 'left'; }
  if (x < 12) { x = Math.min(Math.max(12, r.left), window.innerWidth - pw - 12); side = 'below'; }
  let y = side === 'below' ? r.bottom + 8 : r.top + r.height / 2 - ph / 2;
  y = Math.max(12, Math.min(y, window.innerHeight - ph - 12));
  peek.style.left = `${x}px`;
  peek.style.top = `${y}px`;
  peek.dataset.side = side;
  peek.classList.add('open');
}
document.addEventListener('pointerover', (ev) => {
  const el = ev.target.closest && ev.target.closest('#cal-main [data-ev], .cal-side .cal-dayp [data-ev]');
  if (el === peekFor) return;
  if (!el) { hidePeek(); return; }
  peekFor = el;
  clearTimeout(peekTimer);
  peekTimer = setTimeout(() => { if (peekFor === el) showPeek(el); }, peek.classList.contains('open') ? 60 : 320);
});
document.addEventListener('scroll', hidePeek, true);
document.addEventListener('pointerdown', hidePeek);

// ---------- Keys ----------

document.addEventListener('keydown', (e) => {
  if (e.metaKey || e.ctrlKey || e.altKey || e.defaultPrevented) return;
  const t = e.target;
  if (t && (t.closest('input, textarea, select, [contenteditable="true"], .modal, .modal-backdrop, dialog') || t.isContentEditable)) return;
  if (document.querySelector('.modal-backdrop:not(.hidden), .modal.open, dialog[open]')) return;
  const sel = dayOf(selected || todayKey());
  const move = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }[e.key];
  if (move) { e.preventDefault(); jumpTo(ymd(addDays(sel, move))); return; }
  const k = e.key.toLowerCase();
  if (k === 'e') { e.preventDefault(); addTask(selected, null, null, true); return; }
  if (k === 't') { e.preventDefault(); goToday(); } else if (k === 'w') { e.preventDefault(); setView('week'); } else if (k === 'm') { e.preventDefault(); setView('month'); } else if (k === 'n') { e.preventDefault(); addTask(selected); } else if (e.key === 'PageUp') { e.preventDefault(); go(-1); } else if (e.key === 'PageDown') { e.preventDefault(); go(1); }
});

(async function init() {
  const now = new Date();
  month = new Date(now.getFullYear(), now.getMonth(), 1);
  miniMonth = new Date(month);
  weekStart = weekStartFor(now);
  selected = ymd(now);
  const startSel = document.getElementById('cal-week-start');
  startSel.value = weekMode;
  startSel.addEventListener('change', () => {
    weekMode = startSel.value;
    try { localStorage.setItem('calendar.weekStart', weekMode); } catch (e) { /* ignore */ }
    weekStart = weekStartFor(dayOf(selected || todayKey()));
    load();
  });
  for (const b of document.querySelectorAll('#cal-view button')) b.addEventListener('click', () => setView(b.dataset.view));
  document.getElementById('cal-prev').addEventListener('click', () => go(-1));
  document.getElementById('cal-next').addEventListener('click', () => go(1));
  document.getElementById('cal-today').addEventListener('click', goToday);
  document.getElementById('cal-add').addEventListener('click', () => addTask(selected));
  document.getElementById('cal-add-event').addEventListener('click', () => addTask(selected, null, null, true));
  document.getElementById('day-add').addEventListener('click', () => addTask(selected));
  // "+3 more": show that day beside the calendar.
  document.getElementById('cal-main').addEventListener('click', (e) => {
    const more = e.target.closest('[data-day-more]');
    if (more) { e.stopPropagation(); select(more.dataset.dayMore); }
  }, true);
  if (window.loadPersonColors) await window.loadPersonColors();
  // calendar.html?day=2026-10-07&event=… (from a link elsewhere): show that
  // day, and open the event.
  const q = new URLSearchParams(location.search);
  const qDay = q.get('day');
  if (qDay && /^\d{4}-\d{2}-\d{2}$/.test(qDay)) {
    const d = dayOf(qDay);
    selected = qDay;
    month = new Date(d.getFullYear(), d.getMonth(), 1);
    miniMonth = new Date(month);
    weekStart = weekStartFor(d);
  }
  await load();
  if (q.get('event')) editEvent(q.get('event'));
})();

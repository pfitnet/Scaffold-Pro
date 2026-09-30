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

async function load() {
  const start = gridStart();
  const end = new Date(start);
  end.setDate(end.getDate() + 41);
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
    <div class="ev-title">${esc(e.title)}</div>
    ${e.detail ? `<div class="sub">${esc(e.detail)}</div>` : ''}
    ${e.person ? `<div class="sub">${window.personTag(e.person)}</div>` : ''}</a>`;
}

function render() {
  document.getElementById('cal-title').textContent = month.toLocaleDateString('en-GB', { month: 'long', year: 'numeric' });
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
  document.getElementById('cal-grid').innerHTML = heads + cells;
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
    ? Object.keys(groups).sort().map((k) => `<div class="ev-day">${k === today ? 'Today' : new Date(`${k}T00:00:00`).toLocaleDateString('en-GB', { weekday: 'short', day: 'numeric', month: 'short' })}</div>${groups[k].map(item).join('')}`).join('')
    : '<div class="empty-inline">Nothing coming up.</div>';
}

function go(delta) {
  month = new Date(month.getFullYear(), month.getMonth() + delta, 1);
  load();
}

(async function init() {
  const now = new Date();
  month = new Date(now.getFullYear(), now.getMonth(), 1);
  selected = ymd(now);
  document.getElementById('cal-prev').addEventListener('click', () => go(-1));
  document.getElementById('cal-next').addEventListener('click', () => go(1));
  document.getElementById('cal-today').addEventListener('click', () => { const n = new Date(); month = new Date(n.getFullYear(), n.getMonth(), 1); selected = ymd(n); load(); });
  await window.loadPersonColors();
  await load();
})();

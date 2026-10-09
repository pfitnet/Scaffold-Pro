'use strict';

// The Tasks page: a greeting with today's progress, a quick-add bar that
// understands "tomorrow 3pm @Tom #26212 !high", the tasks grouped by when
// they're due (Overdue, Today, Tomorrow, This week, Later, No date) as
// cards — tick to finish, click to change, ⟳ to move to tomorrow — and at
// the side this week's load by day and the team's by person.
// Styles: css/tasks.css. The New / Edit sheet: js/task-editor.js.

let rows = [];
let projects = [];
let people = [];
let me = '';
let view = 'mine';
let dayFilter = '';
let flashId = '';
let firstDraw = true;

const esc = (value) => String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const pad = (n) => String(n).padStart(2, '0');
const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
const addDays = (d, n) => { const x = new Date(d); x.setDate(x.getDate() + n); return x; };
const dayOf = (s) => new Date(`${s}T00:00:00`);
const reduceMotion = () => window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const store = {
  get(k, d) { try { const v = localStorage.getItem(`tasks.${k}`); return v === null ? d : JSON.parse(v); } catch (e) { return d; } },
  set(k, v) { try { localStorage.setItem(`tasks.${k}`, JSON.stringify(v)); } catch (e) { /* private window */ } },
};
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const WEEKDAYS = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const shortDay = (s) => { const d = dayOf(s); return `${WEEKDAYS[d.getDay()]} ${d.getDate()} ${MONTHS[d.getMonth()]}`; };

const ICON = {
  check: '<svg viewBox="0 0 24 24" aria-hidden="true"><circle class="ring" cx="12" cy="12" r="9.2"/><path class="tick" d="M7.6 12.4l3 3 5.8-6.6"/></svg>',
  cal: '<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" aria-hidden="true"><rect x="2.5" y="3.5" width="11" height="10" rx="2"/><path d="M2.5 7h11M5.5 2v3M10.5 2v3"/></svg>',
  folder: '<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" aria-hidden="true"><path d="M2 4.5A1.5 1.5 0 0 1 3.5 3h3l1.5 1.5h4.5A1.5 1.5 0 0 1 14 6v5.5A1.5 1.5 0 0 1 12.5 13h-9A1.5 1.5 0 0 1 2 11.5z"/></svg>',
  flag: '<svg viewBox="0 0 16 16" width="12" height="12" fill="currentColor" aria-hidden="true"><path d="M3.5 1.8a.7.7 0 0 1 .7.7v.3h7.6a.6.6 0 0 1 .5.9L11 6l1.3 2.3a.6.6 0 0 1-.5.9H4.2v5.3a.7.7 0 0 1-1.4 0v-12a.7.7 0 0 1 .7-.7z"/></svg>',
  snooze: '<svg viewBox="0 0 20 20" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 10a6 6 0 1 0 2-4.5"/><path d="M4 3.5V6h2.5"/><path d="M10 7v3.2l2 1.3"/></svg>',
  edit: '<svg viewBox="0 0 20 20" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12.5 4.5l3 3L8 15H5v-3z"/><path d="M11 6l3 3"/></svg>',
  chevron: '<svg viewBox="0 0 12 12" width="11" height="11" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 4.5 6 7.5 9 4.5"/></svg>',
};

// ---------- What's shown ----------

function inView(r) {
  const t = r.task;
  if (view === 'mine') return r.mine && !t.done;
  if (view === 'team') return !t.done;
  return t.done;
}

function filtered() {
  const q = document.getElementById('task-search').value.trim().toLowerCase();
  const person = document.getElementById('task-person').value;
  const project = document.getElementById('task-project').value;
  return rows.filter((r) => {
    const t = r.task;
    if (!inView(r)) return false;
    if (person && (person === '—' ? !!t.assignee : (t.assignee || '') !== person)) return false;
    if (project && t.projectId !== project) return false;
    if (dayFilter && t.dueDate !== dayFilter) return false;
    return !q || [t.title, t.notes, t.assignee, t.team, r.projectNumber, r.projectName].some((x) => String(x || '').toLowerCase().includes(q));
  });
}

// Open tasks by when they're due; done ones by when they were ticked.
function groups(list) {
  const today = ymd(new Date());
  const tomorrow = ymd(addDays(new Date(), 1));
  const week = ymd(addDays(new Date(), 7));
  const order = (a, b) => (a.task.dueDate || '9999').localeCompare(b.task.dueDate || '9999')
    || (a.task.dueTime || '99').localeCompare(b.task.dueTime || '99')
    || (a.task.priority === 'High' ? -1 : 0) - (b.task.priority === 'High' ? -1 : 0)
    || a.task.title.localeCompare(b.task.title);
  if (view === 'done') {
    const yesterday = ymd(addDays(new Date(), -1));
    const weekAgo = ymd(addDays(new Date(), -7));
    const done = (r) => (r.task.doneAt || r.task.updatedAt || '').slice(0, 10);
    const buckets = [
      { key: 'd-today', title: 'Today', tone: 'good', test: (r) => done(r) === today },
      { key: 'd-yesterday', title: 'Yesterday', tone: 'quiet', test: (r) => done(r) === yesterday },
      { key: 'd-week', title: 'Earlier this week', tone: 'quiet', test: (r) => done(r) >= weekAgo && done(r) < yesterday },
      { key: 'd-earlier', title: 'Earlier', tone: 'quiet', test: () => true },
    ];
    const used = new Set();
    return buckets.map((b) => {
      const items = list.filter((r) => !used.has(r) && b.test(r)).sort((x, y) => (y.task.doneAt || '').localeCompare(x.task.doneAt || ''));
      items.forEach((r) => used.add(r));
      return Object.assign(b, { items });
    }).filter((b) => b.items.length);
  }
  const buckets = [
    { key: 'overdue', title: 'Overdue', tone: 'danger', test: (r) => r.task.dueDate && r.task.dueDate < today },
    { key: 'today', title: 'Today', tone: 'accent', test: (r) => r.task.dueDate === today },
    { key: 'tomorrow', title: 'Tomorrow', tone: 'warm', test: (r) => r.task.dueDate === tomorrow },
    { key: 'week', title: 'This week', tone: 'calm', test: (r) => r.task.dueDate && r.task.dueDate <= week },
    { key: 'later', title: 'Later', tone: 'quiet', test: (r) => !!r.task.dueDate },
    { key: 'nodate', title: 'No date', tone: 'quiet', test: () => true },
  ];
  const used = new Set();
  return buckets.map((b) => {
    const items = list.filter((r) => !used.has(r) && b.test(r)).sort(order);
    items.forEach((r) => used.add(r));
    return Object.assign(b, { items });
  }).filter((b) => b.items.length);
}

// ---------- Drawing ----------

function initials(name) {
  const parts = String(name || '').trim().split(/\s+/).filter(Boolean);
  return ((parts[0] || '?')[0] + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
}

function avatar(name, size) {
  if (!name) return `<span class="tk-avatar anyone${size ? ` ${size}` : ''}" title="For anyone">∗</span>`;
  return `<span class="tk-avatar${size ? ` ${size}` : ''}" style="--pc:${window.personColor(name)}" title="For ${esc(name)}">${esc(initials(name))}</span>`;
}

function dueChip(r) {
  const t = r.task;
  if (t.done) {
    const when = (t.doneAt || '').slice(0, 10);
    return `<span class="tk-chip done">${ICON.check.replace('<svg', '<svg width="12" height="12"')}Done${t.doneBy ? ` by ${esc(t.doneBy)}` : ''}${when ? ` · ${esc(shortDay(when))}` : ''}</span>`;
  }
  if (!t.dueDate) return '';
  const today = ymd(new Date());
  const tomorrow = ymd(addDays(new Date(), 1));
  const tone = t.dueDate < today ? 'overdue' : t.dueDate === today ? 'today' : t.dueDate === tomorrow ? 'soon' : '';
  const label = t.dueDate === today ? 'Today' : t.dueDate === tomorrow ? 'Tomorrow' : shortDay(t.dueDate);
  const days = Math.round((dayOf(today) - dayOf(t.dueDate)) / 86400000);
  return `<span class="tk-chip due ${tone}">${ICON.cal}${tone === 'overdue' ? `${days} day${days === 1 ? '' : 's'} late · ` : ''}${esc(label)}${t.dueTime ? ` · ${esc(t.dueTime)}` : ''}</span>`;
}

function cardHTML(r, i) {
  const t = r.task;
  const project = r.projectNumber
    ? `<a class="tk-chip project" href="project-detail.html?number=${encodeURIComponent(r.projectNumber)}&tab=tasks" title="${esc(r.projectName || '')}">${ICON.folder}${esc(r.projectNumber)}<span class="tk-chip-more">${esc(r.projectName || '')}</span></a>` : '';
  return `<article class="tk-card${t.done ? ' done' : ''}${t.priority === 'High' ? ' high' : ''}${r.overdue && !t.done ? ' late' : ''}" data-id="${esc(t.id)}" style="--i:${Math.min(i, 14)}" tabindex="0">
      <button type="button" class="tk-check" data-no-icon aria-label="${t.done ? 'Mark as not done' : 'Mark as done'}" title="${t.done ? 'Not done yet' : 'Done'}">${ICON.check}</button>
      <div class="tk-body">
        <div class="tk-title">${t.priority === 'High' ? `<span class="tk-flag" title="High priority">${ICON.flag}</span>` : ''}<span class="tk-title-text">${esc(t.title)}</span></div>
        ${t.notes ? `<div class="tk-notes">${esc(t.notes)}</div>` : ''}
        ${dueChip(r) || project || t.team ? `<div class="tk-meta">${dueChip(r)}${project}${!t.assignee && t.team ? `<span class="tk-chip">${esc(t.team)} team</span>` : ''}</div>` : ''}
      </div>
      <div class="tk-side-right">
        ${t.done ? '' : `<div class="tk-actions">
          <button type="button" class="tk-act" data-act="snooze" data-no-icon title="Move to tomorrow">${ICON.snooze}</button>
          <button type="button" class="tk-act" data-act="edit" data-no-icon title="Edit">${ICON.edit}</button>
        </div>`}
        ${!t.assignee && t.team ? `<span class="tk-avatar team" style="--pc:${window.personColor(t.team)}" title="For the ${esc(t.team)} team">${esc(initials(t.team))}</span>` : avatar(t.assignee)}
      </div>
    </article>`;
}

function emptyHTML() {
  const done = view === 'done';
  const filteredOut = rows.some(inView);
  const title = filteredOut ? 'Nothing matches' : done ? 'Nothing ticked off yet' : 'All clear';
  const text = filteredOut ? 'Try another search, person, project or day.' : done ? 'Tasks you finish land here.' : 'Nothing to do — enjoy the calm, or add a task above.';
  return `<div class="tk-empty">
      <svg class="tk-empty-art" viewBox="0 0 160 120" aria-hidden="true">
        <circle class="halo" cx="80" cy="62" r="40"/>
        <circle class="disc" cx="80" cy="62" r="28"/>
        <path class="tick" d="M68 62l8.5 8.5L93 54"/>
        <path class="spark s1" d="M30 30v10M25 35h10"/><path class="spark s2" d="M130 24v8M126 28h8"/><path class="spark s3" d="M136 86v8M132 90h8"/><circle class="spark s4" cx="26" cy="88" r="2.5"/>
      </svg>
      <h2>${title}</h2><p>${text}</p></div>`;
}

function render() {
  renderHero();
  renderSide();
  renderCounts();
  const list = filtered();
  const box = document.getElementById('task-list');
  const filterBar = dayFilter
    ? `<div class="tk-filter-chip"><span>Due ${esc(dayFilter === ymd(new Date()) ? 'today' : shortDay(dayFilter))}</span><button type="button" data-no-icon id="tk-clear-day" aria-label="Show every day">✕</button></div>` : '';
  if (!list.length) {
    box.innerHTML = filterBar + emptyHTML();
  } else {
    const collapsed = store.get('collapsed', {});
    let i = 0;
    box.innerHTML = filterBar + groups(list).map((g) => `
      <section class="tk-group tone-${g.tone}${collapsed[g.key] ? ' collapsed' : ''}" data-key="${g.key}">
        <button type="button" class="tk-group-head" data-no-icon aria-expanded="${collapsed[g.key] ? 'false' : 'true'}">
          <span class="tk-group-chev">${ICON.chevron}</span>
          <span class="tk-group-title">${g.title}</span>
          <span class="tk-group-count">${g.items.length}</span>
          <span class="tk-group-line"></span>
        </button>
        <div class="tk-group-body"><div class="tk-group-inner">${g.items.map((r) => cardHTML(r, i++)).join('')}</div></div>
      </section>`).join('');
  }
  box.classList.toggle('animate', firstDraw && !reduceMotion());
  firstDraw = false;
  wire(box);
  if (flashId) {
    const card = box.querySelector(`.tk-card[data-id="${CSS.escape(flashId)}"]`);
    if (card) { card.classList.add('flash'); card.scrollIntoView({ block: 'nearest', behavior: reduceMotion() ? 'auto' : 'smooth' }); }
    flashId = '';
  }
}

function renderCounts() {
  const open = rows.filter((r) => !r.task.done);
  const n = { mine: open.filter((r) => r.mine).length, team: open.length, done: rows.filter((r) => r.task.done).length };
  for (const el of document.querySelectorAll('[data-count]')) el.textContent = n[el.dataset.count] || '';
  moveSegPill();
}

function moveSegPill() {
  const seg = document.getElementById('task-tabs');
  const active = seg.querySelector('button.active');
  if (!active) return;
  seg.style.setProperty('--x', `${active.offsetLeft}px`);
  seg.style.setProperty('--w', `${active.offsetWidth}px`);
}

// Counts up from where it was to the new number.
function countTo(el, value, fmt = (v) => v) {
  const from = Number(el.dataset.v || 0);
  el.dataset.v = value;
  if (reduceMotion() || from === value) { el.textContent = fmt(value); return; }
  const start = performance.now();
  const step = (now) => {
    const k = Math.min(1, (now - start) / 600);
    el.textContent = fmt(Math.round(from + (value - from) * (1 - Math.pow(1 - k, 3))));
    if (k < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

function renderHero() {
  const now = new Date();
  const today = ymd(now);
  const hour = now.getHours();
  const first = (me || '').trim().split(/\s+/)[0];
  document.getElementById('tk-date').textContent = now.toLocaleDateString('en-GB', { weekday: 'long', day: 'numeric', month: 'long', year: 'numeric' }).replace('Sept', 'Sep');
  document.getElementById('tk-greeting').textContent = `${hour < 12 ? 'Good morning' : hour < 18 ? 'Good afternoon' : 'Good evening'}${first ? `, ${first}` : ''}`;
  const mine = rows.filter((r) => r.mine);
  const open = mine.filter((r) => !r.task.done);
  const dueToday = open.filter((r) => r.task.dueDate === today).length;
  const late = open.filter((r) => r.task.dueDate && r.task.dueDate < today).length;
  const doneToday = mine.filter((r) => r.task.done && (r.task.doneAt || '').slice(0, 10) === today).length;
  const parts = [];
  if (dueToday) parts.push(`<b>${dueToday}</b> task${dueToday === 1 ? '' : 's'} due today`);
  if (late) parts.push(`<b class="late">${late}</b> overdue`);
  document.getElementById('tk-summary').innerHTML = parts.length
    ? `You have ${parts.join(' and ')}.${doneToday ? ` ${doneToday} already done — nice.` : ''}`
    : open.length ? `Nothing due today. ${open.length} open task${open.length === 1 ? '' : 's'} on your list.` : 'Nothing on your list — enjoy the calm.';
  const teamOpen = rows.filter((r) => !r.task.done).length;
  const stats = document.getElementById('tk-stats');
  if (!stats.children.length) {
    stats.innerHTML = [['open', 'Open for you'], ['today', 'Due today'], ['late', 'Overdue'], ['team', 'Across the team']]
      .map(([k, label]) => `<div class="tk-stat ${k}"><b data-stat="${k}">0</b><span>${label}</span></div>`).join('');
  }
  const set = (k, v) => countTo(stats.querySelector(`[data-stat="${k}"]`), v);
  set('open', open.length); set('today', dueToday); set('late', late); set('team', teamOpen);
  stats.querySelector('.tk-stat.late').classList.toggle('on', late > 0);
  // Today's ring: what's done today out of what was due by today.
  const total = doneToday + dueToday + late;
  const pct = total ? Math.round((doneToday / total) * 100) : 100;
  const fill = document.getElementById('tk-ring-fill');
  const c = 2 * Math.PI * 50;
  fill.style.strokeDasharray = `${c}`;
  fill.style.strokeDashoffset = `${c * (1 - pct / 100)}`;
  countTo(document.getElementById('tk-ring-pct'), pct, (v) => `${v}%`);
  document.getElementById('tk-ring-sub').textContent = total ? `${doneToday} of ${total} today` : 'all clear';
  document.getElementById('tk-ring').classList.toggle('full', pct === 100);
}

function renderSide() {
  // This week: open tasks (in the current view) due each of the next 7 days.
  const base = rows.filter((r) => !r.task.done && (view !== 'mine' || r.mine));
  const today = new Date();
  const days = [...Array(7)].map((_, i) => addDays(today, i));
  const counts = days.map((d) => base.filter((r) => r.task.dueDate === ymd(d)).length);
  const max = Math.max(1, ...counts);
  document.getElementById('tk-week').innerHTML = days.map((d, i) => {
    const key = ymd(d);
    return `<button type="button" class="tk-day${i === 0 ? ' today' : ''}${dayFilter === key ? ' on' : ''}${[0, 6].includes(d.getDay()) ? ' weekend' : ''}" data-day="${key}" data-no-icon title="${counts[i]} due ${i === 0 ? 'today' : shortDay(key)}">
        <span class="tk-day-name">${i === 0 ? 'Today' : WEEKDAYS[d.getDay()]}</span>
        <span class="tk-day-bar"><span style="--h:${counts[i] / max}"></span></span>
        <span class="tk-day-num">${d.getDate()}</span>
        <span class="tk-day-count">${counts[i] || ''}</span>
      </button>`;
  }).join('');
  // Team load: open tasks per person (overdue in red).
  const open = rows.filter((r) => !r.task.done);
  const by = new Map();
  for (const r of open) {
    const k = r.task.assignee || '';
    const e = by.get(k) || { name: k, n: 0, late: 0 };
    e.n += 1; if (r.overdue) e.late += 1;
    by.set(k, e);
  }
  const list = [...by.values()].sort((a, b) => b.n - a.n || a.name.localeCompare(b.name));
  const top = Math.max(1, ...list.map((e) => e.n));
  const person = document.getElementById('task-person').value;
  document.getElementById('tk-team').innerHTML = list.length ? list.map((e) => `
      <button type="button" class="tk-person${(person || null) === (e.name || '—') ? ' on' : ''}" data-person="${esc(e.name || '—')}" data-no-icon style="--pc:${e.name ? window.personColor(e.name) : 'var(--text-tertiary)'}">
        ${avatar(e.name, 'sm')}
        <span class="tk-person-name">${esc(e.name || 'Anyone')}</span>
        <span class="tk-person-bar"><span style="--w:${e.n / top}"></span>${e.late ? `<span class="late" style="--w:${e.late / top}"></span>` : ''}</span>
        <span class="tk-person-n">${e.n}</span>
      </button>`).join('') : '<p class="tk-side-empty">No open tasks.</p>';
}

// ---------- Doing things ----------

function burst(origin) {
  if (reduceMotion()) return;
  const r = origin.getBoundingClientRect();
  const layer = document.createElement('div');
  layer.className = 'tk-burst';
  layer.style.left = `${r.left + r.width / 2}px`;
  layer.style.top = `${r.top + r.height / 2}px`;
  const colors = ['var(--tk-a)', 'var(--tk-b)', '#f2c14e', '#7fc8a9', '#e58f8f', '#9fb4e6'];
  for (let i = 0; i < 16; i++) {
    const s = document.createElement('i');
    const a = (Math.PI * 2 * i) / 16 + Math.random() * 0.4;
    const d = 22 + Math.random() * 26;
    s.style.setProperty('--dx', `${Math.cos(a) * d}px`);
    s.style.setProperty('--dy', `${Math.sin(a) * d}px`);
    s.style.setProperty('--r', `${Math.random() * 360}deg`);
    s.style.background = colors[i % colors.length];
    if (i % 3 === 0) s.className = 'round';
    layer.appendChild(s);
  }
  document.body.appendChild(layer);
  setTimeout(() => layer.remove(), 900);
}

async function toggleDone(card, row) {
  const done = !row.task.done;
  card.classList.add(done ? 'completing' : 'reopening');
  if (done) burst(card.querySelector('.tk-check'));
  const r = await window.api.tasks.setDone(row.task.id, done);
  if (r && r.ok === false) { card.classList.remove('completing', 'reopening'); await window.appAlert(r.error); return; }
  // Let the tick and strike-through play, then fold the card away.
  await new Promise((res) => setTimeout(res, reduceMotion() ? 0 : 520));
  if (!reduceMotion()) {
    card.style.height = `${card.offsetHeight}px`;
    void card.offsetHeight;
    card.classList.add('leaving');
    await new Promise((res) => setTimeout(res, 280));
  }
  await load();
}

async function snooze(row) {
  const t = row.task;
  const r = await window.api.tasks.save({
    id: t.id, title: t.title, assignee: t.assignee || '', team: t.team || '', dueDate: ymd(addDays(new Date(), 1)), dueTime: t.dueTime || '',
    projectId: t.projectId || null, priority: t.priority || '', notes: t.notes || '',
  });
  if (r && r.ok === false) { await window.appAlert(r.error); return; }
  flashId = t.id;
  await load();
}

async function edit(row) {
  if (await window.editTask(row.task, { projects, people })) await load();
}

function wire(box) {
  for (const card of box.querySelectorAll('.tk-card')) {
    const row = rows.find((r) => r.task.id === card.dataset.id);
    if (!row) continue;
    card.querySelector('.tk-check').addEventListener('click', (e) => { e.stopPropagation(); toggleDone(card, row); });
    for (const b of card.querySelectorAll('.tk-act')) {
      b.addEventListener('click', (e) => { e.stopPropagation(); (b.dataset.act === 'snooze' ? snooze : edit)(row); });
    }
    card.addEventListener('click', (e) => { if (!e.target.closest('a, button')) edit(row); });
    card.addEventListener('keydown', (e) => {
      if (e.target !== card) return;
      if (e.key === 'Enter') { e.preventDefault(); edit(row); }
      if (e.key === ' ') { e.preventDefault(); toggleDone(card, row); }
    });
  }
  for (const head of box.querySelectorAll('.tk-group-head')) {
    head.addEventListener('click', () => {
      const g = head.closest('.tk-group');
      const collapsed = store.get('collapsed', {});
      collapsed[g.dataset.key] = !g.classList.contains('collapsed');
      store.set('collapsed', collapsed);
      g.classList.toggle('collapsed', collapsed[g.dataset.key]);
      head.setAttribute('aria-expanded', collapsed[g.dataset.key] ? 'false' : 'true');
    });
  }
  const clear = box.querySelector('#tk-clear-day');
  if (clear) clear.addEventListener('click', () => { dayFilter = ''; render(); });
}

// ---------- Quick add: "tomorrow 3pm @Tom #26212 !high" ----------

const DAY_NAMES = ['sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday'];

function parseQuick(text) {
  let s = ` ${text} `;
  const out = { title: '', dueDate: '', dueTime: '', assignee: '', projectId: '', projectLabel: '', priority: '' };
  const take = (re, fn) => { s = s.replace(re, (...m) => { const keep = fn(...m); return keep === undefined ? ' ' : keep; }); };
  const today = new Date();
  take(/\s!(high|urgent|!+)?(?=\s)/i, () => { out.priority = 'High'; });
  take(/\s@([^\s@#!]+)(?=\s)/, (_, who) => {
    const hit = people.find((p) => p.toLowerCase() === who.toLowerCase()) || people.find((p) => p.toLowerCase().startsWith(who.toLowerCase()));
    out.assignee = hit || who;
  });
  take(/\s#(\S+)(?=\s)/, (m, code) => {
    const hit = projects.find((p) => p.projectNumber === code) || projects.find((p) => p.projectNumber.startsWith(code));
    if (!hit) return m;
    out.projectId = hit.id; out.projectLabel = `${hit.projectNumber} ${hit.name}`;
  });
  // Times: 3pm, 3:30 pm, 15:00
  take(/\s(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)(?=\s)/i, (_, h, m, ap) => {
    let hh = Number(h) % 12; if (ap.toLowerCase() === 'pm') hh += 12;
    out.dueTime = `${pad(hh)}:${pad(Number(m || 0))}`;
  });
  take(/\s(?:at\s+)?([01]?\d|2[0-3]):([0-5]\d)(?=\s)/, (_, h, m) => { out.dueTime = `${pad(Number(h))}:${m}`; });
  // Days
  take(/\s(today|tonight|tdy)(?=\s)/i, () => { out.dueDate = ymd(today); });
  take(/\s(tomorrow|tmrw?|tmr)(?=\s)/i, () => { out.dueDate = ymd(addDays(today, 1)); });
  take(/\snext week(?=\s)/i, () => { const d = addDays(today, ((8 - today.getDay()) % 7) || 7); out.dueDate = ymd(d); });
  take(/\sin (\d{1,3}) days?(?=\s)/i, (_, n) => { out.dueDate = ymd(addDays(today, Number(n))); });
  take(/\s(?:on\s+)?(next\s+)?(sun|mon|tue|tues|wed|thu|thur|thurs|fri|sat)(?:day|nesday|rsday|urday)?(?=\s)/i, (_, next, name) => {
    const target = DAY_NAMES.findIndex((d) => d.startsWith(name.toLowerCase().slice(0, 3)));
    let diff = (target - today.getDay() + 7) % 7 || 7;
    if (next) diff += diff < 7 ? 7 : 0;
    out.dueDate = ymd(addDays(today, diff));
  });
  // dd/mm or dd/mm/yyyy (always day first)
  take(/\s(\d{1,2})\/(\d{1,2})(?:\/(\d{2,4}))?(?=\s)/, (m, d, mo, y) => {
    let year = y ? Number(y.length === 2 ? `20${y}` : y) : today.getFullYear();
    const date = new Date(year, Number(mo) - 1, Number(d));
    if (date.getMonth() !== Number(mo) - 1) return m;
    if (!y && ymd(date) < ymd(today)) date.setFullYear(++year);
    out.dueDate = ymd(date);
  });
  // 5 Oct / Oct 5
  take(/\s(\d{1,2})\s+(jan|feb|mar|apr|may|jun|jul|aug|sep|sept|oct|nov|dec)[a-z]*(?=\s)/i, (_, d, mo) => {
    const date = new Date(today.getFullYear(), MONTHS.findIndex((x) => x.toLowerCase() === mo.toLowerCase().slice(0, 3)), Number(d));
    if (ymd(date) < ymd(today)) date.setFullYear(date.getFullYear() + 1);
    out.dueDate = ymd(date);
  });
  out.title = s.replace(/\s+/g, ' ').trim();
  return out;
}

function renderQuickChips() {
  const input = document.getElementById('tk-quick-input');
  const p = parseQuick(input.value);
  const chips = [];
  if (p.dueDate) {
    const today = ymd(new Date());
    const label = p.dueDate === today ? 'Today' : p.dueDate === ymd(addDays(new Date(), 1)) ? 'Tomorrow' : shortDay(p.dueDate);
    chips.push(`<span class="tk-qchip date">${ICON.cal}${esc(label)}${p.dueTime ? ` · ${esc(p.dueTime)}` : ''}</span>`);
  } else if (p.dueTime) chips.push(`<span class="tk-qchip date">${ICON.cal}Today · ${esc(p.dueTime)}</span>`);
  if (p.assignee) chips.push(`<span class="tk-qchip who" style="--pc:${window.personColor(p.assignee)}">@${esc(p.assignee)}</span>`);
  if (p.projectId) chips.push(`<span class="tk-qchip project">${ICON.folder}${esc(p.projectLabel)}</span>`);
  if (p.priority) chips.push(`<span class="tk-qchip high">${ICON.flag}High</span>`);
  document.getElementById('tk-quick-chips').innerHTML = chips.join('');
  document.getElementById('tk-quick').classList.toggle('has-chips', chips.length > 0);
}

async function quickAdd() {
  const input = document.getElementById('tk-quick-input');
  const p = parseQuick(input.value);
  if (!p.title) { input.focus(); return; }
  const r = await window.api.tasks.save({
    id: null, title: p.title, assignee: p.assignee, dueDate: p.dueDate || (p.dueTime ? ymd(new Date()) : ''), dueTime: p.dueTime,
    projectId: p.projectId || document.getElementById('task-project').value || null, priority: p.priority, notes: '',
  });
  if (!r || !r.ok) { await window.appAlert((r && r.error) || 'The task couldn’t be saved.'); return; }
  input.value = '';
  renderQuickChips();
  const bar = document.getElementById('tk-quick');
  bar.classList.remove('added'); void bar.offsetWidth; bar.classList.add('added');
  flashId = r.id || '';
  // Make sure it shows: someone else's goes under Everyone's.
  if (view === 'done' || (view === 'mine' && p.assignee && me && p.assignee.toLowerCase() !== me.toLowerCase())) setView('team', true);
  await load();
}

// ---------- Loading ----------

// ⌘Z / ⌘Y redraw the page with this, not a reload (js/undo.js).
window.appRefresh = () => load();

async function load() {
  const [r, pr, pe] = await Promise.all([window.api.tasks.list(), window.api.projects.list(), window.api.tasks.people()]);
  rows = r || [];
  projects = (pr || []).filter((x) => x.status !== 'Archived');
  people = pe || [];
  const person = document.getElementById('task-person');
  const keepPerson = person.value;
  person.innerHTML = '<option value="">Everyone</option><option value="—">For anyone</option>' + people.map((n) => `<option value="${esc(n)}">${esc(n)}</option>`).join('');
  person.value = keepPerson === '—' || people.includes(keepPerson) ? keepPerson : '';
  const project = document.getElementById('task-project');
  const keepProject = project.value;
  project.innerHTML = '<option value="">All projects</option>' + projects.map((x) => `<option value="${esc(x.id)}">${esc(x.projectNumber)} — ${esc(x.name)}</option>`).join('');
  project.value = projects.some((x) => x.id === keepProject) ? keepProject : '';
  await window.loadPersonColors();
  render();
}

function setView(v, quiet) {
  view = v;
  store.set('view', v);
  for (const b of document.querySelectorAll('#task-tabs button')) b.classList.toggle('active', b.dataset.view === v);
  moveSegPill();
  if (!quiet) { firstDraw = true; render(); }
}

document.getElementById('new-task-btn').addEventListener('click', async () => {
  const project = document.getElementById('task-project').value;
  // What's typed in the quick-add bar starts the form off.
  const p = parseQuick(document.getElementById('tk-quick-input').value);
  if (await window.editTask(null, { projects, people, title: p.title, projectId: p.projectId || project || null, assignee: p.assignee, dueDate: p.dueDate, dueTime: p.dueTime, priority: p.priority })) {
    document.getElementById('tk-quick-input').value = '';
    renderQuickChips();
    await load();
  }
});
for (const b of document.querySelectorAll('#task-tabs button')) b.addEventListener('click', () => setView(b.dataset.view));
document.getElementById('task-search').addEventListener('input', render);
document.getElementById('task-person').addEventListener('change', render);
document.getElementById('task-project').addEventListener('change', render);
document.getElementById('tk-quick-input').addEventListener('input', renderQuickChips);
document.getElementById('tk-quick-input').addEventListener('keydown', (e) => {
  if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); quickAdd(); }
  if (e.key === 'Escape') { e.target.value = ''; renderQuickChips(); e.target.blur(); }
});
document.getElementById('tk-week').addEventListener('click', (e) => {
  const b = e.target.closest('.tk-day');
  if (!b) return;
  dayFilter = dayFilter === b.dataset.day ? '' : b.dataset.day;
  if (dayFilter && view === 'done') setView('mine', true);
  render();
});
document.getElementById('tk-team').addEventListener('click', (e) => {
  const b = e.target.closest('.tk-person');
  if (!b) return;
  const select = document.getElementById('task-person');
  select.value = select.value === b.dataset.person ? '' : b.dataset.person;
  if (select.value && view === 'mine') setView('team', true);
  select.dispatchEvent(new Event('change'));
});
// N: add a task. /: search.
document.addEventListener('keydown', (e) => {
  if (e.metaKey || e.ctrlKey || e.altKey) return;
  const typing = e.target.closest && e.target.closest('input, textarea, select, [contenteditable], .modal-backdrop:not(.hidden)');
  if (typing || document.querySelector('.modal-backdrop:not(.hidden), .app-dialog-backdrop:not(.leaving)')) return;
  if (e.key === 'n' || e.key === 'N') { e.preventDefault(); document.getElementById('tk-quick-input').focus(); }
  if (e.key === '/') { e.preventDefault(); document.getElementById('task-search').focus(); }
});
window.addEventListener('resize', moveSegPill);

view = ['mine', 'team', 'done'].includes(store.get('view', 'mine')) ? store.get('view', 'mine') : 'mine';
setView(view, true);

Promise.all([load(), window.api.users.page().then((p) => { me = (p && p.name) || ''; }).catch(() => {})]).then(async () => {
  renderHero();
  // Opened from the Calendar: that task.
  const id = new URLSearchParams(location.search).get('task');
  const row = id && rows.find((r) => r.task.id === id);
  if (row) {
    if (row.task.done) setView('done'); else if (!row.mine) setView('team');
    if (await window.editTask(row.task, { projects, people })) await load();
  }
});

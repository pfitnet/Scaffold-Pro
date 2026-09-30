'use strict';

// The User page (pinned at the foot of the sidebar): this Mac's user —
// their name and colour — and their own projects, documents and activity.

const COLOURS = ['#2F6FED', '#D9480F', '#2B8A3E', '#AE3EC9', '#C2255C', '#0C8599', '#B7791F', '#5F3DC4', '#087F5B', '#E03131', '#495057', '#1864AB'];

let page = null;

function esc(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function when(iso) {
  const d = new Date(iso);
  if (isNaN(d)) return iso || '';
  const mins = Math.round((Date.now() - d.getTime()) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins} min ago`;
  if (mins < 60 * 24) return `${Math.round(mins / 60)} h ago`;
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
}

function initials(name) {
  return String(name || '').trim().split(/\s+/).map((w) => w[0] || '').slice(0, 2).join('').toUpperCase() || '?';
}

function table(container, rows, columns, emptyText) {
  const el = document.getElementById(container);
  if (!rows.length) { el.innerHTML = `<div class="empty-inline">${emptyText}</div>`; return; }
  el.innerHTML = `<table class="compact"><tbody>${rows.map((r) =>
    `<tr class="link-row" data-url="${esc(r.url || '')}">${columns.map((c) => `<td class="${c.cls || ''}">${c.value(r)}</td>`).join('')}</tr>`).join('')}</tbody></table>`;
  for (const tr of el.querySelectorAll('tr[data-url]')) {
    if (tr.dataset.url) tr.addEventListener('click', () => { location.href = tr.dataset.url; });
  }
}

function renderHead() {
  const colour = window.personColor(page.name);
  const avatar = document.getElementById('big-avatar');
  avatar.textContent = initials(page.name);
  avatar.style.background = colour;
  document.getElementById('user-name').textContent = page.name;
  document.getElementById('user-sub').textContent = `On ${page.computer}${page.sharing ? ' · sharing the data with the team' : ''}`;
  document.getElementById('colour-preview').innerHTML = window.personTag(page.name);
  const input = document.getElementById('name-input');
  if (document.activeElement !== input) input.value = page.name;

  const current = (page.color || '').toUpperCase();
  const box = document.getElementById('swatches');
  box.innerHTML = COLOURS.map((c) => `<button class="swatch${current === c ? ' on' : ''}" data-colour="${c}" style="background:${c}" title="${c}" aria-label="Colour ${c}"></button>`).join('') +
    `<label class="custom-colour" title="Any colour"><input type="color" id="colour-custom" value="${esc(current || colour)}" /> Other…</label>`;
  for (const b of box.querySelectorAll('.swatch')) b.addEventListener('click', () => setColour(b.dataset.colour));
  document.getElementById('colour-custom').addEventListener('change', (e) => setColour(e.target.value));
  document.getElementById('colour-auto').classList.toggle('hidden', !page.color);
}

function renderStats() {
  const stats = document.getElementById('user-stats');
  const card = (value, label) => `<div class="stat-card"><div class="value">${value}</div><div class="label">${label}</div></div>`;
  stats.innerHTML = card(page.myProjects.length, 'Projects I worked on') + card(page.createdCount, 'Made by me') +
    card(page.lastWorkedCount, 'Last worked on by me') + card(page.myActivity.length, 'Recent actions');
}

function renderLists() {
  table('my-projects', page.myProjects.map((p) => Object.assign({ url: `project-detail.html?number=${encodeURIComponent(p.projectNumber)}` }, p)), [
    { value: (p) => `<strong>${esc(p.projectNumber)}</strong><div class="sub">${esc(p.name)}</div>` },
    { value: (p) => `<span class="muted">${esc(p.clientName || '—')}</span><div class="sub">${when(p.lastWorkedAt)}</div>` },
    { value: (p) => `<span class="status-pill">${esc(p.status)}</span>` },
  ], 'None yet — projects you work on show here.');
  table('my-documents', page.myDocuments, [
    { value: (r) => `<strong>${esc(r.number)}</strong><div class="sub">${esc(r.kind)} · ${esc(r.projectNumber)}</div>` },
    { value: (r) => `<span class="status-pill">${esc(r.status)}</span>` },
    { cls: 'muted num', value: (r) => when(r.lastEditedAt || r.updatedAt) },
  ], 'None yet — documents you work on show here.');
  table('my-activity', page.myActivity.map((a) => Object.assign({ url: a.projectNumber ? `project-detail.html?number=${encodeURIComponent(a.projectNumber)}&tab=history` : '' }, a)), [
    { value: (a) => `${esc(a.action)}<div class="sub">${esc([a.projectNumber, a.reference].filter(Boolean).join(' · '))}</div>` },
    { cls: 'muted num', value: (a) => when(a.createdAt) },
  ], 'Nothing yet.');

  const team = document.getElementById('team-list');
  if (!page.sharing || !page.members.length) {
    team.innerHTML = '<div class="empty-inline">This Mac isn’t sharing its data. Set it up in <a href="settings.html#team">Settings › Share with Other Macs</a>; everyone’s names then show here in their colours.</div>';
    return;
  }
  team.innerHTML = page.members.map((m) => `<div class="member">${window.personTag(m.name)}
    <span class="muted">${esc(m.computer)}${m.isThisMac ? ' · this Mac' : m.lastSeen ? ` · seen ${esc(when(m.lastSeen))}` : ''}</span></div>`).join('');
}

async function setColour(colour) {
  const r = await window.api.users.setColor(colour);
  if (r && r.ok === false) { alert(r.error); return; }
  await window.loadPersonColors(true);
  await load();
}

async function load() {
  page = await window.api.users.page();
  if (!page) return;
  await window.loadPersonColors();
  renderHead();
  renderStats();
  renderLists();
}

document.getElementById('name-save').addEventListener('click', async () => {
  const name = document.getElementById('name-input').value.trim();
  if (!name) { alert('Enter your name.'); return; }
  if (name === page.name) return;
  const r = await window.api.users.setName(name);
  if (r && r.ok === false) { alert(r.error); return; }
  // The sidebar shows the new name too.
  location.reload();
});
document.getElementById('name-input').addEventListener('keydown', (e) => { if (e.key === 'Enter') document.getElementById('name-save').click(); });
document.getElementById('colour-auto').addEventListener('click', () => setColour(''));

load();

'use strict';

// Loaded on every page. Provides:
//   • the sidebar (with simple line icons, like native Mac sidebars)
//   • ⌘K global search (section 44) — window.openGlobalSearch()
//   • click-to-sort table columns (section 51)
//   • a small right-click menu helper — window.showContextMenu(event, items)

const ICONS = {
  dashboard: '<rect x="3" y="3" width="6" height="6" rx="1.2"/><rect x="11" y="3" width="6" height="6" rx="1.2"/><rect x="3" y="11" width="6" height="6" rx="1.2"/><rect x="11" y="11" width="6" height="6" rx="1.2"/>',
  'price-lists': '<path d="M10.6 3H16a1 1 0 0 1 1 1v5.4a1 1 0 0 1-.3.7l-6.9 6.9a1 1 0 0 1-1.4 0L3 11.6a1 1 0 0 1 0-1.4l6.9-6.9a1 1 0 0 1 .7-.3z"/><circle cx="13.5" cy="6.5" r="1.2"/>',
  sites: '<path d="M10 17.5s-5.5-5-5.5-9a5.5 5.5 0 0 1 11 0c0 4-5.5 9-5.5 9z"/><circle cx="10" cy="8.5" r="2"/>',
  clients: '<rect x="4" y="3" width="12" height="14" rx="1.2"/><path d="M7 6.5h2M11 6.5h2M7 9.5h2M11 9.5h2M8.5 17v-3h3v3"/>',
  projects: '<path d="M2.5 5.5a1 1 0 0 1 1-1h4l1.5 1.8h7.5a1 1 0 0 1 1 1V15a1 1 0 0 1-1 1h-13a1 1 0 0 1-1-1z"/>',
  stock: '<path d="M3 7.5 10 4l7 3.5v5L10 16l-7-3.5z"/><path d="M3 7.5 10 11l7-3.5M10 11v5"/>',
  accounts: '<rect x="4" y="2.5" width="12" height="15" rx="1.5"/><rect x="6.5" y="5" width="7" height="3" rx=".5"/><path d="M7 11h.01M10 11h.01M13 11h.01M7 14h.01M10 14h.01M13 14h.01"/>',
  admin: '<circle cx="7.5" cy="7" r="2.6"/><path d="M2.8 16c.4-2.8 2.3-4.3 4.7-4.3s4.3 1.5 4.7 4.3"/><circle cx="14" cy="8" r="2"/><path d="M13 11.9c2.2-.2 3.8 1 4.2 3.6"/>',
  // A hard hat: the people on site.
  workers: '<path d="M3 14.5h14"/><path d="M4.5 14.5V12a5.5 5.5 0 0 1 11 0v2.5"/><path d="M8.5 7V5.2a1.5 1.5 0 0 1 3 0V7"/><path d="M3.5 14.5v1.5h13v-1.5"/>',
  calendar: '<rect x="3" y="4.5" width="14" height="12.5" rx="1.5"/><path d="M3 8.5h14M7 3v3M13 3v3"/>',
  tasks: '<rect x="3.5" y="3.5" width="13" height="13" rx="2"/><path d="m6.8 10.2 2.2 2.2 4.3-4.6"/>',
  marketing: '<path d="M3.5 8.5v3a1 1 0 0 0 1 1H6l5 3.5v-12L6 7.5H4.5a1 1 0 0 0-1 1z"/><path d="M14 7.5a3.5 3.5 0 0 1 0 5M6.5 12.5l1 4"/>',
  letters: '<rect x="2.5" y="4.5" width="15" height="11" rx="1.3"/><path d="m3 5.5 7 5.2 7-5.2"/>',
  manual: '<path d="M4 4.5A1.5 1.5 0 0 1 5.5 3H16v12.5H5.5A1.5 1.5 0 0 0 4 17z"/><path d="M4 17a1.5 1.5 0 0 1 1.5-1.5H16V17H5.5"/><path d="M8 7h5M8 10h3.5"/>',
  settings: '<circle cx="10" cy="10" r="2.6"/><path d="M10 2.8v2M10 15.2v2M2.8 10h2M15.2 10h2M4.9 4.9l1.4 1.4M13.7 13.7l1.4 1.4M4.9 15.1l1.4-1.4M13.7 6.3l1.4-1.4"/>',
  search: '<circle cx="8.8" cy="8.8" r="5"/><path d="M12.6 12.6 16.5 16.5"/>',
  chat: '<path d="M3.5 5.5a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v6a2 2 0 0 1-2 2H9l-3.5 3v-3h0a2 2 0 0 1-2-2z"/><path d="M7 8.5h6M7 11h3.5"/>',
  team: '<circle cx="7" cy="7.5" r="2.5"/><circle cx="13.5" cy="7.5" r="2.5"/><path d="M2.5 16c.4-2.6 2.2-4 4.5-4s4.1 1.4 4.5 4M10.5 12.7c.8-.5 1.8-.7 3-.7 2.3 0 4.1 1.4 4.5 4"/>',
  assistant: '<path d="M10 2.8 11.5 7.5 16.2 9 11.5 10.5 10 15.2 8.5 10.5 3.8 9 8.5 7.5z"/><path d="M15.4 13.6l.5 1.5 1.5.5-1.5.5-.5 1.5-.5-1.5-1.5-.5 1.5-.5z"/>',
  user: '<circle cx="10" cy="7" r="3"/><path d="M4 17c.5-3.3 2.9-5 6-5s5.5 1.7 6 5"/>',
};

function icon(name) {
  return `<svg class="nav-icon" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ''}</svg>`;
}

// Leaving a page that has unsaved work (Settings): the page sets
// window.leaveNeedsAsk() (true while there's something unsaved) and
// window.askBeforeLeave() (asks Save / Don't Save / Cancel, resolves true to
// go on). Every way of leaving goes through here: links, ⌘K search, Back,
// and the Go menu (main.swift).
window.appNavigate = async function appNavigate(target) {
  if (typeof window.leaveNeedsAsk === 'function' && window.leaveNeedsAsk() && typeof window.askBeforeLeave === 'function') {
    if (!(await window.askBeforeLeave())) return false;
  }
  if (typeof target === 'function') target(); else location.href = target;
  return true;
};
document.addEventListener('click', (e) => {
  if (e.defaultPrevented || e.button !== 0 || e.metaKey || e.ctrlKey || e.shiftKey) return;
  const a = e.target.closest && e.target.closest('a[href]');
  if (!a || a.target === '_blank') return;
  const href = a.getAttribute('href') || '';
  if (!href || href.startsWith('#') || href.startsWith('javascript:')) return;
  // Another place in the same page (settings.html#team) isn't leaving.
  if (a.pathname === location.pathname && a.hash) return;
  if (!(typeof window.leaveNeedsAsk === 'function' && window.leaveNeedsAsk())) return;
  e.preventDefault();
  window.appNavigate(a.href);
}, true);

const NAV_ITEMS = [
  { section: 'Overview' },
  { page: 'dashboard', label: 'Dashboard', href: 'index.html', key: '1' },
  { page: 'calendar', label: 'Calendar', href: 'calendar.html' },
  { page: 'tasks', label: 'Tasks', href: 'tasks.html' },
  { page: 'assistant', label: 'Assistant', href: 'assistant.html' },
  { section: 'Team' },
  { page: 'chat', label: 'Chat', href: 'chat.html' },
  { page: 'team', label: 'Team', href: 'team.html' },
  { section: 'Operations' },
  { page: 'price-lists', label: 'Costs', href: 'price-lists.html', key: '2' },
  { page: 'clients', label: 'Clients & Sites', href: 'clients.html', key: '3' },
  { page: 'projects', label: 'Projects', href: 'projects.html', key: '4' },
  { page: 'stock', label: 'Stock', href: 'stock.html', key: '5' },
  { page: 'workers', label: 'Workers', href: 'workers.html' },
  { section: 'Company' },
  { page: 'accounts', label: 'Accounting', href: 'accounts.html', key: '6' },
  { page: 'marketing', label: 'Marketing', href: 'marketing.html' },
  { page: 'admin', label: 'Admin', href: 'admin.html', key: '7' },
  { page: 'manual', label: 'User Manual', href: 'manual.html' },
];

// The app mark (see icon/ScaffoldPro-logo.svg), in its simplified small-size
// form: scaffold frame with the safety-yellow brace.
const BRAND_MARK = `<svg class="brand-mark" viewBox="0 0 64 64" aria-hidden="true">
  <rect x="0" y="0" width="64" height="64" rx="14" fill="#1B3556"/>
  <g fill="#E4E8EC">
    <rect x="15" y="11" width="5" height="42"/><rect x="29.5" y="11" width="5" height="42"/><rect x="44" y="11" width="5" height="42"/>
    <rect x="15" y="16" width="34" height="4"/><rect x="15" y="30" width="34" height="4"/><rect x="15" y="44" width="34" height="4"/>
  </g>
  <line x1="17.5" y1="46" x2="46.5" y2="18" stroke="#F4B400" stroke-width="6" stroke-linecap="round"/>
</svg>`;

// The order of the tabs can be changed: the pencil by the first heading
// (Edit), then drag the tabs (and headings) into place, or ⌥↑ / ⌥↓.
// Kept on this Mac; tabs added in an update join their usual group.
const NAV_ORDER_KEY = 'sidebar.order';
const navKey = (item) => (item.section ? `section:${item.section}` : item.page);
function orderedNavItems() {
  let saved = null;
  try { saved = JSON.parse(localStorage.getItem(NAV_ORDER_KEY) || 'null'); } catch (e) { saved = null; }
  if (!Array.isArray(saved) || !saved.length) return NAV_ITEMS;
  const byKey = new Map(NAV_ITEMS.map((i) => [navKey(i), i]));
  const out = [];
  for (const k of saved) { const item = byKey.get(k); if (item && !out.includes(item)) out.push(item); }
  NAV_ITEMS.forEach((item, i) => {
    if (out.includes(item)) return;
    const before = NAV_ITEMS.slice(0, i).reverse().find((x) => out.includes(x));
    out.splice(before ? out.indexOf(before) + 1 : out.length, 0, item);
  });
  return out;
}

function setupNavEditing(sidebar) {
  const head = sidebar.querySelector('.sidebar-section');
  if (!head) return;
  const btn = document.createElement('button');
  btn.type = 'button';
  btn.className = 'nav-edit-btn';
  btn.dataset.noIcon = '';
  btn.title = 'Change the order of the tabs';
  btn.setAttribute('aria-label', 'Change the order of the tabs');
  btn.innerHTML = '<svg viewBox="0 0 20 20" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12.8 3.7l3.5 3.5-8.8 8.8-4 .5.5-4z"/></svg>';
  head.appendChild(btn);
  const bar = document.createElement('div');
  bar.className = 'nav-edit-bar';
  bar.innerHTML = '<span>Drag the tabs into order</span><button type="button" data-no-icon data-act="reset">Reset</button><button type="button" class="primary" data-no-icon data-act="done">Done</button>';
  const items = () => [...sidebar.querySelectorAll('[data-nav]')];
  const save = () => { try { localStorage.setItem(NAV_ORDER_KEY, JSON.stringify(items().map((el) => el.dataset.nav))); } catch (e) { /* not kept */ } };
  let dragged = null;
  const start = () => {
    sidebar.classList.add('nav-editing');
    head.before(bar);
    for (const el of items()) { el.draggable = true; el.tabIndex = 0; }
    items()[0].focus();
  };
  const stop = () => {
    sidebar.classList.remove('nav-editing');
    bar.remove();
    for (const el of items()) { el.draggable = false; if (el.classList.contains('sidebar-section')) el.removeAttribute('tabindex'); }
    save();
    if (window.placeNavInk) window.placeNavInk();
  };
  btn.addEventListener('click', (e) => { e.stopPropagation(); if (sidebar.classList.contains('nav-editing')) stop(); else start(); });
  bar.addEventListener('click', (e) => {
    const b = e.target.closest('button[data-act]');
    if (!b) return;
    if (b.dataset.act === 'reset') { try { localStorage.removeItem(NAV_ORDER_KEY); } catch (err) { /* ignore */ } window.softReload(); }
    else stop();
  });
  // While editing, a click doesn't open the tab.
  sidebar.addEventListener('click', (e) => { if (sidebar.classList.contains('nav-editing') && e.target.closest('[data-nav]')) { e.preventDefault(); e.stopPropagation(); } }, true);
  sidebar.addEventListener('dragstart', (e) => {
    const el = e.target.closest && e.target.closest('[data-nav]');
    if (!el || !sidebar.classList.contains('nav-editing')) return;
    dragged = el;
    el.classList.add('nav-dragging');
    e.dataTransfer.effectAllowed = 'move';
    try { e.dataTransfer.setData('text/plain', el.dataset.nav); } catch (err) { /* ignore */ }
  });
  sidebar.addEventListener('dragover', (e) => {
    if (!dragged) return;
    const over = e.target.closest && e.target.closest('[data-nav]');
    e.preventDefault();
    if (!over || over === dragged) return;
    const r = over.getBoundingClientRect();
    if (e.clientY < r.top + r.height / 2) over.before(dragged); else over.after(dragged);
    if (window.placeNavInk) window.placeNavInk();
  });
  const end = () => { if (dragged) { dragged.classList.remove('nav-dragging'); dragged = null; save(); } };
  sidebar.addEventListener('drop', (e) => { if (dragged) { e.preventDefault(); end(); } });
  sidebar.addEventListener('dragend', end);
  sidebar.addEventListener('keydown', (e) => {
    if (!sidebar.classList.contains('nav-editing')) return;
    const el = e.target.closest && e.target.closest('[data-nav]');
    if (e.key === 'Escape' || (e.key === 'Enter' && !el)) { e.preventDefault(); stop(); return; }
    if (!el || (e.key !== 'ArrowUp' && e.key !== 'ArrowDown')) return;
    e.preventDefault();
    const list = items();
    const i = list.indexOf(el);
    if (e.altKey) {
      if (e.key === 'ArrowUp' && i > 0) list[i - 1].before(el);
      if (e.key === 'ArrowDown' && i < list.length - 1) list[i + 1].after(el);
      el.focus();
      save();
    } else {
      const next = list[i + (e.key === 'ArrowUp' ? -1 : 1)];
      if (next) next.focus();
    }
  });
}

function renderSidebar(activePage) {
  const sidebar = document.getElementById('sidebar');
  if (!sidebar) return;

  const brand = document.createElement('a');
  brand.className = 'sidebar-brand';
  brand.href = 'index.html';
  brand.innerHTML = `${BRAND_MARK}<span>ScaffoldPro</span>`;
  sidebar.appendChild(brand);

  const search = document.createElement('button');
  search.className = 'sidebar-search';
  search.type = 'button';
  search.innerHTML = `${icon('search')}<span>Search</span><kbd>⌘K</kbd>`;
  search.addEventListener('click', () => window.openGlobalSearch());
  sidebar.appendChild(search);


  for (const item of orderedNavItems()) {
    // A group's heading ("OVERVIEW", "OPERATIONS"…).
    if (item.section) {
      const head = document.createElement('div');
      head.className = 'sidebar-section';
      head.dataset.nav = navKey(item);
      head.innerHTML = `<span>${item.section}</span>`;
      sidebar.appendChild(head);
      continue;
    }
    const link = document.createElement('a');
    link.dataset.nav = navKey(item);
    link.href = item.href;
    link.title = item.key ? `${item.label} (⌘${item.key})` : item.label;
    link.innerHTML = `${icon(item.page)}<span>${item.label}</span>`;
    if (item.page === activePage || (activePage === 'project-detail' && item.page === 'projects')) {
      link.classList.add('active');
      link.setAttribute('aria-current', 'page');
    }
    if (item.page === 'chat') link.insertAdjacentHTML('beforeend', '<span class="nav-badge hidden" id="chat-badge"></span>');
    sidebar.appendChild(link);
  }
  if (window.refreshChatBadge) window.refreshChatBadge();
  setupNavEditing(sidebar);
  // Pinned to the bottom left: the sharing status, then you — one button
  // (your name, with the gear) that opens Settings at You.
  const foot = document.createElement('div');
  foot.className = 'sidebar-foot';
  sidebar.appendChild(foot);
  const userRow = document.createElement('div');
  userRow.className = 'sidebar-user-row';
  foot.appendChild(userRow);
  const user = document.createElement('a');
  user.href = 'settings.html#you';
  user.className = 'sidebar-user';
  user.title = 'Settings — starting with You: your name, colour, theme and work (⌘,)';
  user.innerHTML = `<span class="user-avatar">${icon('user')}</span><span class="user-label">User</span>` +
    '<span class="user-gear"><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/></svg></span>';
  if (activePage === 'user' || activePage === 'settings') { user.classList.add('active'); user.setAttribute('aria-current', 'page'); }
  userRow.appendChild(user);
  renderUserTab(user);
  // ScaffoldPro Web: sign out of this browser.
  if (window.__scaffoldProWeb && window.scaffoldProSignOut) {
    const out = document.createElement('button');
    out.type = 'button';
    out.className = 'sidebar-signout';
    out.textContent = 'Sign Out';
    out.dataset.noIcon = '';
    out.addEventListener('click', () => window.scaffoldProSignOut());
    foot.appendChild(out);
  }
  renderTeamIndicator(foot);
}

// The User tab shows who's using this Mac, with their initials in their colour.
async function renderUserTab(link) {
  if (!window.api || !window.api.users) return;
  let page;
  try { page = await window.api.users.page(); } catch (e) { return; }
  if (!page || !page.name) return;
  await window.loadPersonColors();
  const initials = page.name.trim().split(/\s+/).map((w) => w[0]).slice(0, 2).join('').toUpperCase();
  const avatar = link.querySelector('.user-avatar');
  avatar.textContent = initials;
  avatar.classList.add('has-initials');
  avatar.style.background = window.personColor(page.name);
  const label = link.querySelector('.user-label');
  label.textContent = page.name;
}

// ---------------------------------------------------------------------
// People's names in colour: each person has their own colour (chosen on
// the User page, else one worked out from their name), the same on every
// Mac. window.personTag(name) gives the name as a coloured tag.
// ---------------------------------------------------------------------

(function setupPersonColors() {
  // Soft, muted and distinct; readable on white and in Dark mode.
  const PALETTE = ['#5B7DB1', '#B07A5E', '#5E8C6A', '#8E72A8', '#A8677C', '#4F8A8F', '#9A8458', '#6D6BA6', '#4E8472', '#A66A6A', '#6B7078', '#4F6F96'];
  let chosen = {};
  let loading = null;
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  window.personColor = function personColor(name) {
    const key = String(name || '').trim().toLowerCase();
    if (!key) return '#8a8f98';
    if (chosen[key]) return chosen[key];
    let h = 0;
    for (const ch of key) h = (h * 31 + ch.codePointAt(0)) >>> 0;
    return PALETTE[h % PALETTE.length];
  };

  window.personTag = function personTag(name) {
    const n = String(name || '').trim();
    if (!n) return '';
    return `<span class="person" data-person="${esc(n)}" style="--person:${window.personColor(n)}">${esc(n)}</span>`;
  };

  // A list's "Created By" cell: who made it, and under it who last worked
  // on it when that was someone else.
  window.createdByCell = function createdByCell(row) {
    const made = row && row.createdBy;
    const last = row && row.lastEditedBy;
    if (!made && !last) return '<td class="created-by"><span class="muted">—</span></td>';
    const lastLine = last && last !== made ? `<div class="sub">last: ${window.personTag(last)}</div>` : '';
    return `<td class="created-by">${made ? window.personTag(made) : '<span class="muted">—</span>'}${lastLine}</td>`;
  };

  // Loads everyone's chosen colours, then re-colours any names already shown.
  window.loadPersonColors = function loadPersonColors(force) {
    if (loading && !force) return loading;
    loading = (async () => {
      if (!window.api || !window.api.users) return;
      try {
        const list = await window.api.users.profiles();
        chosen = {};
        for (const p of list || []) if (p && p.id && p.color) chosen[p.id] = p.color;
      } catch (e) { return; }
      for (const el of document.querySelectorAll('.person[data-person]')) el.style.setProperty('--person', window.personColor(el.dataset.person));
      for (const el of document.querySelectorAll('.user-avatar.has-initials')) {
        const label = el.parentElement && el.parentElement.querySelector('.user-label');
        if (label) el.style.background = window.personColor(label.textContent);
      }
    })();
    return loading;
  };
  document.addEventListener('DOMContentLoaded', () => window.loadPersonColors());
})();

// "Shared with Tom, Anna" at the foot of the sidebar while this Mac uses
// a shared folder (Settings › Share with Other Macs).
async function renderTeamIndicator(sidebar) {
  if (!window.api || !window.api.team) return;
  let s;
  try { s = await window.api.team.status(); } catch (e) { return; }
  if (!s || (!s.enabled && !s.folderMissing)) return;
  const el = document.createElement('div');
  el.className = `sidebar-team${s.enabled && !s.thisMacOutdated ? '' : ' missing'}`;
  const others = (s.members || []).filter((m) => !m.isThisMac).map((m) => m.name);
  const label = !s.enabled ? 'Shared folder not found' : s.thisMacOutdated ? 'Update ScaffoldPro'
    : others.length ? `Shared with ${others.slice(0, 2).join(', ')}${others.length > 2 ? ` +${others.length - 2}` : ''}` : 'Shared folder';
  el.innerHTML = '<span class="dot"></span><span></span>';
  el.lastChild.textContent = label;
  el.title = s.enabled ? `Working in the shared folder ${s.folderDisplay}. Changes from the other Macs appear by themselves.`
    : 'The shared folder couldn’t be found, so this Mac’s own data is open. See Settings.';
  el.addEventListener('click', () => { window.appNavigate('settings.html#team'); });
  sidebar.prepend(el);
}

// ---------------------------------------------------------------------
// Global search (⌘K)
// ---------------------------------------------------------------------

(function setupGlobalSearch() {
  let overlay = null;
  let results = [];
  let selected = 0;
  let timer = null;
  let requestNo = 0;

  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  function build() {
    overlay = document.createElement('div');
    overlay.className = 'search-overlay hidden';
    overlay.innerHTML = `
      <div class="search-panel" role="dialog" aria-label="Search">
        <div class="search-input-row">${icon('search')}
          <input type="text" id="global-search-input" placeholder="Search projects, clients, sites, documents, workers, materials…" autocomplete="off" spellcheck="false" />
          <kbd>esc</kbd>
        </div>
        <div class="search-results" id="global-search-results"></div>
      </div>`;
    document.body.appendChild(overlay);
    overlay.addEventListener('mousedown', (e) => { if (e.target === overlay) close(); });
    const input = overlay.querySelector('input');
    input.addEventListener('input', () => {
      clearTimeout(timer);
      timer = setTimeout(() => run(input.value), 90);
    });
    input.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') { e.preventDefault(); close(); }
      else if (e.key === 'ArrowDown') { e.preventDefault(); move(1); }
      else if (e.key === 'ArrowUp') { e.preventDefault(); move(-1); }
      else if (e.key === 'Enter') { e.preventDefault(); if (results[selected]) window.appNavigate(results[selected].url); }
    });
  }

  async function run(query) {
    const mine = ++requestNo;
    const box = overlay.querySelector('#global-search-results');
    if (!query.trim()) {
      results = [];
      box.innerHTML = '<div class="search-hint">Type a project number, client, document number, drawing name, worker or material.</div>';
      return;
    }
    const found = await window.api.search.query(query);
    if (mine !== requestNo) return; // a newer search has started
    results = found;
    selected = 0;
    if (results.length === 0) {
      box.innerHTML = `<div class="search-hint">No results for “${esc(query)}”.</div>`;
      return;
    }
    box.innerHTML = results.map((r, i) => `
      <a class="search-result${i === 0 ? ' selected' : ''}" href="${r.url}" data-index="${i}">
        <span class="search-title">${esc(r.title)}</span>
        <span class="search-subtitle">${esc(r.subtitle)}</span>
        <span class="search-kind">${esc(r.kind)}</span>
      </a>`).join('');
    for (const a of box.querySelectorAll('.search-result')) {
      a.addEventListener('mousemove', () => highlight(Number(a.dataset.index)));
    }
  }

  function highlight(i) {
    selected = i;
    const items = overlay.querySelectorAll('.search-result');
    items.forEach((el, n) => el.classList.toggle('selected', n === i));
    if (items[i]) items[i].scrollIntoView({ block: 'nearest' });
  }

  function move(delta) {
    if (results.length === 0) return;
    highlight((selected + delta + results.length) % results.length);
  }

  function close() {
    if (overlay) overlay.classList.add('hidden');
  }

  window.openGlobalSearch = function openGlobalSearch() {
    if (!overlay) build();
    overlay.classList.remove('hidden');
    const input = overlay.querySelector('input');
    input.focus();
    input.select();
    run(input.value);
  };

  // The menu bar's ⌘K normally handles this; this is a fallback.
  document.addEventListener('keydown', (e) => {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'k') {
      e.preventDefault();
      window.openGlobalSearch();
    }
  });
})();

// ---------------------------------------------------------------------
// Click-to-sort tables (section 51)
// ---------------------------------------------------------------------
//
// Any list table gets sortable column headers. Document line items are
// excluded — their order *is* the document's order.

(function setupSortableTables() {
  function cellValue(row, index) {
    const cell = row.cells[index];
    if (!cell) return '';
    const input = cell.querySelector('input, select');
    return (input ? input.value : cell.textContent).trim();
  }

  function asNumber(text) {
    const cleaned = text.replace(/[,\s]|HK\$|HKD|\$|kg/gi, '');
    if (cleaned === '' || cleaned === '—') return null;
    return /^-?\d+(\.\d+)?$/.test(cleaned) ? Number(cleaned) : null;
  }

  // Clicking a heading: ascending, then descending, then back to the
  // table's own order (as it was before any heading was clicked).
  function sortBy(table, index, th) {
    const tbody = table.tBodies[0];
    if (!tbody) return;
    const was = th.dataset.sortDir;
    const sortedNow = [...table.tHead.rows[0].cells].some((c) => c.dataset.sortDir);
    // Unsorted: this is the table's own order, to go back to.
    if (!sortedNow || !tbody.__ownOrder) tbody.__ownOrder = Array.from(tbody.rows);
    for (const other of table.tHead.rows[0].cells) {
      delete other.dataset.sortDir;
      other.classList.remove('sorted-asc', 'sorted-desc');
    }
    if (was === 'desc') {
      // Third click: the own order again (rows added since stay at the end).
      const own = tbody.__ownOrder.filter((r) => r.parentNode === tbody);
      const rest = Array.from(tbody.rows).filter((r) => !own.includes(r));
      for (const r of own.concat(rest)) tbody.appendChild(r);
      th.title = 'Click to sort';
      return;
    }
    const ascending = was !== 'asc';
    th.dataset.sortDir = ascending ? 'asc' : 'desc';
    th.classList.add(ascending ? 'sorted-asc' : 'sorted-desc');
    th.title = ascending ? 'Sorted A–Z / low to high — click for Z–A' : 'Sorted Z–A / high to low — click to go back to the original order';
    const rows = Array.from(tbody.rows);
    const numeric = rows.every((r) => { const v = cellValue(r, index); return v === '' || v === '—' || asNumber(v) !== null; });
    rows.sort((a, b) => {
      const va = cellValue(a, index);
      const vb = cellValue(b, index);
      let cmp;
      if (numeric) cmp = (asNumber(va) ?? -Infinity) - (asNumber(vb) ?? -Infinity);
      else cmp = va.localeCompare(vb, undefined, { numeric: true, sensitivity: 'base' });
      return ascending ? cmp : -cmp;
    });
    for (const r of rows) tbody.appendChild(r);
  }

  function enhance(table) {
    if (table.dataset.sortReady || !table.tHead || !table.tHead.rows.length) return;
    if (table.closest('#line-items, .no-sort, .search-panel')) return;
    table.dataset.sortReady = '1';
    Array.from(table.tHead.rows[0].cells).forEach((th, index) => {
      if (!th.textContent.trim()) return;
      th.classList.add('sortable');
      th.title = 'Click to sort';
      th.addEventListener('click', () => sortBy(table, index, th));
    });
  }

  const observer = new MutationObserver(() => {
    for (const t of document.querySelectorAll('table:not([data-sort-ready])')) enhance(t);
  });
  document.addEventListener('DOMContentLoaded', () => {
    for (const t of document.querySelectorAll('table')) enhance(t);
    observer.observe(document.body, { childList: true, subtree: true });
  });
})();

// ---------------------------------------------------------------------
// Right-click menus (section 51)
// ---------------------------------------------------------------------
//
// window.showContextMenu(event, [{ label, action }, 'separator', …])

(function setupContextMenu() {
  let menu = null;

  function hide() {
    if (menu) { menu.remove(); menu = null; }
  }

  window.showContextMenu = function showContextMenu(event, items) {
    event.preventDefault();
    hide();
    menu = document.createElement('div');
    menu.className = 'context-menu';
    for (const item of items) {
      if (item === 'separator') {
        const sep = document.createElement('div');
        sep.className = 'context-separator';
        menu.appendChild(sep);
        continue;
      }
      const b = document.createElement('button');
      b.type = 'button';
      b.textContent = item.label;
      if (item.danger) b.classList.add('danger');
      b.addEventListener('click', () => { hide(); item.action(); });
      menu.appendChild(b);
    }
    document.body.appendChild(menu);
    const { innerWidth, innerHeight } = window;
    const rect = menu.getBoundingClientRect();
    menu.style.left = `${Math.min(event.clientX, innerWidth - rect.width - 6)}px`;
    menu.style.top = `${Math.min(event.clientY, innerHeight - rect.height - 6)}px`;
  };

  window.copyText = function copyText(text) {
    const area = document.createElement('textarea');
    area.value = text;
    area.style.position = 'fixed';
    area.style.opacity = '0';
    document.body.appendChild(area);
    area.select();
    try { document.execCommand('copy'); } catch (e) { /* ignore */ }
    area.remove();
  };

  document.addEventListener('mousedown', (e) => { if (menu && !menu.contains(e.target)) hide(); });
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') hide(); });
  window.addEventListener('blur', hide);
  document.addEventListener('scroll', hide, true);
})();

document.addEventListener('DOMContentLoaded', () => {
  renderSidebar(document.body.dataset.page);
  addBackButton();
});

// ---------------------------------------------------------------------
// Back button, top left of pages opened from another page (a project, a
// BOQ / quotation / invoice / delivery note) — not the sidebar's own pages.
// ---------------------------------------------------------------------

function addBackButton() {
  const file = (location.pathname.split('/').pop() || 'index.html').toLowerCase();
  const ROOT_PAGES = ['index.html', 'calendar.html', 'tasks.html', 'assistant.html', 'chat.html', 'team.html', 'price-lists.html', 'clients.html', 'projects.html', 'stock.html', 'accounts.html', 'marketing.html', 'workers.html', 'admin.html', 'settings.html', 'user.html', 'launch.html'];
  const content = document.getElementById('content');
  if (ROOT_PAGES.includes(file) || !content || content.querySelector('.page-back')) return;
  const button = document.createElement('button');
  button.type = 'button';
  button.className = 'page-back';
  button.dataset.noIcon = '';
  button.innerHTML = '<svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M12.5 4.5 7 10l5.5 5.5"/></svg><span>Back</span>';
  button.title = 'Back to the previous page';
  button.addEventListener('click', () => {
    // The page it was opened from, if it was one of ours; else its parent.
    const cameFromApp = document.referrer && document.referrer.startsWith(location.origin === 'null' ? 'file:' : location.origin);
    if (cameFromApp && history.length > 1) { window.appNavigate(() => history.back()); return; }
    const parent = document.getElementById('back-link');
    window.appNavigate(parent && parent.getAttribute('href') && parent.getAttribute('href') !== '#' ? parent.getAttribute('href') : 'projects.html');
  });
  content.prepend(button);
}

// Unread chat messages: a count on the sidebar's Chat (read marks are kept
// on this Mac, by js/chat.js).
window.refreshChatBadge = async function refreshChatBadge() {
  const badge = document.getElementById('chat-badge');
  if (!badge || !window.api || !window.api.chat) return;
  let page;
  try { page = await window.api.chat.page(); } catch (e) { return; }
  if (!page || !page.me) return;
  let marks = {};
  try { marks = JSON.parse(localStorage.getItem(`chat.read:${page.me.toLowerCase()}`) || '{}'); } catch (e) { marks = {}; }
  let current = null;
  try { current = document.body.dataset.page === 'chat' ? localStorage.getItem('chat.current') : null; } catch (e) { /* ignore */ }
  const unread = page.conversations.filter((c) => c.lastAt && c.lastAuthor && c.lastAuthor.toLowerCase() !== page.me.toLowerCase()
    && (!marks[c.id] || marks[c.id] < c.lastAt) && c.id !== current).length;
  badge.textContent = unread > 9 ? '9+' : String(unread);
  badge.classList.toggle('hidden', !unread);
};
if (!window.__chatBadgeTimer) window.__chatBadgeTimer = setInterval(() => window.refreshChatBadge(), 20000);
window.refreshChatBadge();

// Motion on every page: page in/out, sliding markers, counting numbers,
// the light on cards, ripples (js/motion.js).
(function loadMotion() {
  for (const src of ['js/motion.js', 'js/notify.js']) {
    if (document.querySelector(`script[src$="${src}"]`)) continue;
    const s = document.createElement('script');
    s.src = src;
    (document.head || document.documentElement).appendChild(s);
  }
})();

// ---------------------------------------------------------------------
// The Assistant's floating chat (js/assistant.js), on every page: the
// sparkle at the bottom right, or ⌘J.
// ---------------------------------------------------------------------
(function loadAssistant() {
  if (document.querySelector('script[src$="js/assistant.js"]') || (document.body && document.body.dataset.page === 'assistant')) return;
  const css = document.createElement('link');
  css.rel = 'stylesheet';
  css.href = 'css/assistant.css';
  document.head.appendChild(css);
  const script = document.createElement('script');
  script.src = 'js/assistant.js';
  script.defer = true;
  document.head.appendChild(script);
})();

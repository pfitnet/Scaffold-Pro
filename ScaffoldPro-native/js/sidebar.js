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
  calendar: '<rect x="3" y="4.5" width="14" height="12.5" rx="1.5"/><path d="M3 8.5h14M7 3v3M13 3v3"/>',
  tasks: '<rect x="3.5" y="3.5" width="13" height="13" rx="2"/><path d="m6.8 10.2 2.2 2.2 4.3-4.6"/>',
  marketing: '<path d="M3.5 8.5v3a1 1 0 0 0 1 1H6l5 3.5v-12L6 7.5H4.5a1 1 0 0 0-1 1z"/><path d="M14 7.5a3.5 3.5 0 0 1 0 5M6.5 12.5l1 4"/>',
  letters: '<rect x="2.5" y="4.5" width="15" height="11" rx="1.3"/><path d="m3 5.5 7 5.2 7-5.2"/>',
  settings: '<circle cx="10" cy="10" r="2.6"/><path d="M10 2.8v2M10 15.2v2M2.8 10h2M15.2 10h2M4.9 4.9l1.4 1.4M13.7 13.7l1.4 1.4M4.9 15.1l1.4-1.4M13.7 6.3l1.4-1.4"/>',
  search: '<circle cx="8.8" cy="8.8" r="5"/><path d="M12.6 12.6 16.5 16.5"/>',
  team: '<circle cx="7" cy="7.5" r="2.5"/><circle cx="13.5" cy="7.5" r="2.5"/><path d="M2.5 16c.4-2.6 2.2-4 4.5-4s4.1 1.4 4.5 4M10.5 12.7c.8-.5 1.8-.7 3-.7 2.3 0 4.1 1.4 4.5 4"/>',
  user: '<circle cx="10" cy="7" r="3"/><path d="M4 17c.5-3.3 2.9-5 6-5s5.5 1.7 6 5"/>',
};

function icon(name) {
  return `<svg class="nav-icon" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ''}</svg>`;
}

const NAV_ITEMS = [
  { page: 'dashboard', label: 'Dashboard', href: 'index.html', key: '1' },
  { page: 'calendar', label: 'Calendar', href: 'calendar.html' },
  { page: 'tasks', label: 'Tasks', href: 'tasks.html' },
  { page: 'team', label: 'Team', href: 'team.html' },
  { page: 'price-lists', label: 'Material List', href: 'price-lists.html', key: '2' },
  { page: 'clients', label: 'Clients & Sites', href: 'clients.html', key: '3' },
  { page: 'projects', label: 'Projects', href: 'projects.html', key: '4' },
  { page: 'stock', label: 'Stock', href: 'stock.html', key: '5' },
  { page: 'accounts', label: 'Accounting', href: 'accounts.html', key: '6' },
  { page: 'marketing', label: 'Marketing', href: 'marketing.html' },
  { page: 'admin', label: 'Admin', href: 'admin.html', key: '7' },
  { page: 'settings', label: 'Settings', href: 'settings.html', key: ',' },
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


  for (const item of NAV_ITEMS) {
    const link = document.createElement('a');
    link.href = item.href;
    link.title = item.key ? `${item.label} (⌘${item.key})` : item.label;
    link.innerHTML = `${icon(item.page)}<span>${item.label}</span>`;
    if (item.page === activePage || (activePage === 'project-detail' && item.page === 'projects')) {
      link.classList.add('active');
      link.setAttribute('aria-current', 'page');
    }
    sidebar.appendChild(link);
  }
  // Pinned to the bottom left: the sharing status, then the User tab.
  const foot = document.createElement('div');
  foot.className = 'sidebar-foot';
  sidebar.appendChild(foot);
  const user = document.createElement('a');
  user.href = 'user.html';
  user.className = 'sidebar-user';
  user.title = 'User — your name, colour and work (⌘0)';
  user.innerHTML = `<span class="user-avatar">${icon('user')}</span><span class="user-label">User</span>`;
  if (activePage === 'user') { user.classList.add('active'); user.setAttribute('aria-current', 'page'); }
  foot.appendChild(user);
  renderUserTab(user);
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
  label.insertAdjacentHTML('afterend', '<span class="user-sub">User</span>');
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
  el.addEventListener('click', () => { location.href = 'settings.html#team'; });
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
      else if (e.key === 'Enter') { e.preventDefault(); if (results[selected]) location.href = results[selected].url; }
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

  function sortBy(table, index, th) {
    const tbody = table.tBodies[0];
    if (!tbody) return;
    const ascending = th.dataset.sortDir !== 'asc';
    for (const other of table.tHead.rows[0].cells) {
      delete other.dataset.sortDir;
      other.classList.remove('sorted-asc', 'sorted-desc');
    }
    th.dataset.sortDir = ascending ? 'asc' : 'desc';
    th.classList.add(ascending ? 'sorted-asc' : 'sorted-desc');
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
  const ROOT_PAGES = ['index.html', 'calendar.html', 'tasks.html', 'team.html', 'price-lists.html', 'clients.html', 'projects.html', 'stock.html', 'accounts.html', 'marketing.html', 'admin.html', 'settings.html', 'user.html', 'launch.html'];
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
    if (cameFromApp && history.length > 1) { history.back(); return; }
    const parent = document.getElementById('back-link');
    location.href = parent && parent.getAttribute('href') && parent.getAttribute('href') !== '#' ? parent.getAttribute('href') : 'projects.html';
  });
  content.prepend(button);
}

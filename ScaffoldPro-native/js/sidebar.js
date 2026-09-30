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
  letters: '<rect x="2.5" y="4.5" width="15" height="11" rx="1.3"/><path d="m3 5.5 7 5.2 7-5.2"/>',
  settings: '<circle cx="10" cy="10" r="2.6"/><path d="M10 2.8v2M10 15.2v2M2.8 10h2M15.2 10h2M4.9 4.9l1.4 1.4M13.7 13.7l1.4 1.4M4.9 15.1l1.4-1.4M13.7 6.3l1.4-1.4"/>',
  search: '<circle cx="8.8" cy="8.8" r="5"/><path d="M12.6 12.6 16.5 16.5"/>',
};

function icon(name) {
  return `<svg class="nav-icon" viewBox="0 0 20 20" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${ICONS[name] || ''}</svg>`;
}

const NAV_ITEMS = [
  { page: 'dashboard', label: 'Dashboard', href: 'index.html', key: '1' },
  { page: 'price-lists', label: 'Material List', href: 'price-lists.html', key: '2' },
  { page: 'sites', label: 'Sites', href: 'sites.html', key: '3' },
  { page: 'clients', label: 'Clients', href: 'clients.html', key: '4' },
  { page: 'projects', label: 'Projects', href: 'projects.html', key: '5' },
  { page: 'letters', label: 'Letters', href: 'letters.html', key: '6' },
  { page: 'stock', label: 'Stock', href: 'stock.html', key: '7' },
  { page: 'accounts', label: 'Accounts', href: 'accounts.html', key: '8' },
  { page: 'admin', label: 'Admin', href: 'admin.html', key: '9' },
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
    link.title = `${item.label} (⌘${item.key})`;
    link.innerHTML = `${icon(item.page)}<span>${item.label}</span>`;
    if (item.page === activePage || (activePage === 'project-detail' && item.page === 'projects')) {
      link.classList.add('active');
      link.setAttribute('aria-current', 'page');
    }
    sidebar.appendChild(link);
  }
  renderTeamIndicator(sidebar);
}

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
  sidebar.appendChild(el);
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
  const ROOT_PAGES = ['index.html', 'price-lists.html', 'sites.html', 'clients.html', 'projects.html', 'letters.html', 'stock.html', 'accounts.html', 'admin.html', 'settings.html', 'launch.html'];
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

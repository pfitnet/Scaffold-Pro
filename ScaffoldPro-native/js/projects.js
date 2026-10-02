'use strict';

let allProjects = [];

// The page's choices, kept on this Mac: status filter, order, cards or list.
const STATE_KEY = 'projects.view';
const state = (() => {
  try { return Object.assign({ status: 'All', sort: 'number', view: 'cards' }, JSON.parse(localStorage.getItem(STATE_KEY) || '{}')); } catch (e) { return { status: 'All', sort: 'number', view: 'cards' }; }
})();
const keep = () => { try { localStorage.setItem(STATE_KEY, JSON.stringify(state)); } catch (e) { /* ignore */ } };

const STATUS_ORDER = ['Planning', 'Quotation', 'Active', 'On Hold', 'Completed', 'Archived'];
const statusClass = (s) => `st-${String(s || '').toLowerCase().replace(/[^a-z]+/g, '-')}`;
const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const calm = window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

function ago(iso) {
  const d = new Date(iso);
  if (!iso || isNaN(d)) return '';
  const mins = Math.round((Date.now() - d.getTime()) / 60000);
  if (mins < 1) return 'just now';
  if (mins < 60) return `${mins} min ago`;
  if (mins < 60 * 24) return `${Math.round(mins / 60)} h ago`;
  const days = Math.round(mins / 1440);
  if (days < 7) return `${days} day${days === 1 ? '' : 's'} ago`;
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: d.getFullYear() === new Date().getFullYear() ? undefined : 'numeric' });
}
const lastTouched = (p) => p.lastActivityAt && p.lastActivityAt > (p.createdAt || '') ? p.lastActivityAt : p.createdAt;

const ICON = {
  client: '<svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.4" stroke-linejoin="round" aria-hidden="true"><path d="M2.5 13.5V4.2a1 1 0 0 1 .7-1l5-1.6a.6.6 0 0 1 .8.6v11.3"/><path d="M9 6.5h3.6a1 1 0 0 1 1 1v6"/><path d="M1.5 13.5h13M5 5.5h1.2M5 8h1.2M5 10.5h1.2M11 9h.8M11 11.2h.8"/></svg>',
  site: '<svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.4" aria-hidden="true"><path d="M8 14.3s4.5-4.1 4.5-7.6a4.5 4.5 0 0 0-9 0c0 3.5 4.5 7.6 4.5 7.6z"/><circle cx="8" cy="6.6" r="1.6"/></svg>',
  go: '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 8h10M9 4l4 4-4 4"/></svg>',
};
// The documents a project holds, in the order they're made.
const DOCS = [['boqCount', 'BOQ', 'BOQs', 'boq'], ['quotationCount', 'Quotation', 'Quotations', 'quotations'], ['deliveryNoteCount', 'Delivery Note', 'Delivery Notes', 'deliveryNotes'], ['invoiceCount', 'Invoice', 'Invoices', 'invoices']];
const SHORT = { boqCount: 'BQ', quotationCount: 'Qt', deliveryNoteCount: 'DN', invoiceCount: 'Inv' };

function docChips(p) {
  return DOCS.map(([key, one, many, tab]) => {
    const n = Number(p[key]) || 0;
    return `<span class="pj-doc${n ? '' : ' none'}" data-tab="${tab}" title="${n} ${n === 1 ? one : many}"><b>${n}</b>${SHORT[key]}</span>`;
  }).join('');
}

function openProject(p, tab) {
  const url = `project-detail.html?number=${encodeURIComponent(p.projectNumber)}${tab ? `&tab=${tab}` : ''}`;
  if (window.appNavigate) window.appNavigate(url); else location.href = url;
}

function contextMenu(e, p) {
  window.showContextMenu(e, [
    { label: 'Open Project', action: () => openProject(p) },
    { label: 'Show in Finder', action: () => window.api.projects.revealFolder(p.projectNumber) },
    'separator',
    { label: 'New Quotation…', action: () => openProject(p, 'quotations') },
    { label: 'Copy Project Number', action: () => window.copyText(p.projectNumber) },
  ]);
}

function card(p, i) {
  const when = ago(lastTouched(p));
  const total = DOCS.reduce((n, [key]) => n + (Number(p[key]) || 0), 0);
  return `<a class="pj-card ${statusClass(p.status)}" href="project-detail.html?number=${encodeURIComponent(p.projectNumber)}" data-number="${esc(p.projectNumber)}" style="--i:${Math.min(i, 14)}">
    <span class="pj-spot" aria-hidden="true"></span>
    <div class="pj-top"><span class="pj-num">${esc(p.projectNumber)}</span><span class="pj-status"><i></i>${esc(p.status)}</span></div>
    <h3 class="pj-name">${esc(p.name)}</h3>
    <div class="pj-meta">
      <span title="Client">${ICON.client}<span>${esc(p.clientName || 'No client')}</span></span>
      <span title="Site">${ICON.site}<span>${esc(p.siteName || 'No site')}</span></span>
    </div>
    <div class="pj-docs" aria-label="${total} documents">${docChips(p)}</div>
    <div class="pj-foot">
      ${p.createdBy ? window.personTag(p.createdBy) : '<span class="muted">—</span>'}
      <span class="pj-when" title="Last worked on">${when ? `${p.lastActivityAt ? 'Worked on' : 'Created'} ${esc(when)}` : ''}</span>
      <span class="pj-go">${ICON.go}</span>
    </div>
  </a>`;
}

function listView(projects) {
  return `<table class="pj-table"><thead><tr><th>Number</th><th>Project</th><th>Site</th><th>Documents</th><th>Status</th><th>Last worked on</th><th>Created By</th></tr></thead><tbody>${
    projects.map((p, i) => `<tr class="pj-row ${statusClass(p.status)}" data-number="${esc(p.projectNumber)}" tabindex="0" style="--i:${Math.min(i, 14)}">
      <td class="pj-num">${esc(p.projectNumber)}</td>
      <td><div class="pj-row-name">${esc(p.name)}</div><div class="sub">${esc(p.clientName || '—')}</div></td>
      <td>${esc(p.siteName || '—')}</td>
      <td><div class="pj-docs">${docChips(p)}</div></td>
      <td><span class="pj-status"><i></i>${esc(p.status)}</span></td>
      <td class="muted">${esc(ago(lastTouched(p)))}</td>
      ${window.createdByCell(p)}</tr>`).join('')}</tbody></table>`;
}

function renderFilters() {
  const counts = { All: allProjects.length };
  for (const p of allProjects) counts[p.status] = (counts[p.status] || 0) + 1;
  const statuses = ['All'].concat(STATUS_ORDER.filter((s) => counts[s]), Object.keys(counts).filter((s) => s !== 'All' && !STATUS_ORDER.includes(s)));
  if (!statuses.includes(state.status)) state.status = 'All';
  const box = document.getElementById('pj-filters');
  box.innerHTML = statuses.map((s) => `<button type="button" role="tab" data-no-icon class="pj-filter ${s === 'All' ? '' : statusClass(s)}${s === state.status ? ' on' : ''}" aria-selected="${s === state.status}" data-status="${esc(s)}">${s === 'All' ? '' : '<i></i>'}${esc(s)}<span class="pj-count">${counts[s]}</span></button>`).join('');
  document.getElementById('pj-total').textContent = allProjects.length || '';
}

function sorted(list) {
  const by = {
    number: (a, b) => b.projectNumber.localeCompare(a.projectNumber, undefined, { numeric: true }),
    activity: (a, b) => String(lastTouched(b) || '').localeCompare(String(lastTouched(a) || '')),
    name: (a, b) => a.name.localeCompare(b.name),
    client: (a, b) => String(a.clientName || '').localeCompare(String(b.clientName || '')) || b.projectNumber.localeCompare(a.projectNumber),
  }[state.sort] || (() => 0);
  return list.slice().sort(by);
}

function renderProjects() {
  const container = document.getElementById('list-container');
  document.querySelectorAll('.pj-view button').forEach((b) => b.classList.toggle('on', b.dataset.view === state.view));
  if (allProjects.length === 0) {
    container.innerHTML = `
      <div class="empty-state pj-empty">
        <h2>No projects yet</h2>
        <p>Create your first project — a number is assigned automatically.</p>
        <button class="primary" onclick="document.getElementById('new-project-btn').click()">+ New Project</button>
      </div>`;
    return;
  }
  const q = document.getElementById('search-box').value.trim().toLowerCase();
  const shown = sorted(allProjects.filter((p) => (state.status === 'All' || p.status === state.status) &&
    (!q || [p.projectNumber, p.name, p.clientName, p.siteName].some((v) => String(v || '').toLowerCase().includes(q)))));
  if (!shown.length) {
    container.innerHTML = `<div class="pj-none"><b>No projects match${q ? ` “${esc(q)}”` : ''}${state.status !== 'All' ? ` in ${esc(state.status)}` : ''}.</b>
      <button type="button" class="link-btn" id="pj-clear" data-no-icon>Show all projects</button></div>`;
    document.getElementById('pj-clear').addEventListener('click', () => {
      document.getElementById('search-box').value = '';
      state.status = 'All'; keep(); renderFilters(); renderProjects();
    });
    return;
  }
  container.innerHTML = state.view === 'list' ? listView(shown) : `<div class="pj-grid">${shown.map(card).join('')}</div>`;
  if (!calm) {
    container.classList.remove('pj-enter');
    void container.offsetWidth;
    container.classList.add('pj-enter');
  }
  const byNumber = new Map(shown.map((p) => [p.projectNumber, p]));
  container.querySelectorAll('[data-number]').forEach((el) => {
    const p = byNumber.get(el.dataset.number);
    el.addEventListener('contextmenu', (e) => contextMenu(e, p));
    if (el.tagName === 'TR') {
      el.addEventListener('click', () => openProject(p));
      el.addEventListener('keydown', (e) => { if (e.key === 'Enter') openProject(p); });
    }
    // A document count goes straight to that tab of the project.
    el.querySelectorAll('.pj-doc:not(.none)').forEach((chip) => chip.addEventListener('click', (e) => {
      e.preventDefault(); e.stopPropagation(); openProject(p, chip.dataset.tab);
    }));
  });
}

// A soft light follows the pointer across a card.
document.getElementById('list-container').addEventListener('pointermove', (e) => {
  const c = e.target.closest && e.target.closest('.pj-card');
  if (!c) return;
  const r = c.getBoundingClientRect();
  c.style.setProperty('--mx', `${e.clientX - r.left}px`);
  c.style.setProperty('--my', `${e.clientY - r.top}px`);
});

async function refresh() {
  allProjects = await window.api.projects.list();
  renderFilters();
  renderProjects();
}

function applySearch() { renderProjects(); }

document.getElementById('pj-filters').addEventListener('click', (e) => {
  const b = e.target.closest('.pj-filter');
  if (!b) return;
  state.status = b.dataset.status; keep();
  renderFilters(); renderProjects();
});
document.getElementById('pj-sort').value = state.sort;
document.getElementById('pj-sort').addEventListener('change', (e) => { state.sort = e.target.value; keep(); renderProjects(); });
document.querySelectorAll('.pj-view button').forEach((b) => b.addEventListener('click', () => { state.view = b.dataset.view; keep(); renderProjects(); }));
// "/" jumps to the search box; Escape clears it.
document.addEventListener('keydown', (e) => {
  const box = document.getElementById('search-box');
  if (e.key === '/' && !e.metaKey && !e.ctrlKey && !/^(INPUT|TEXTAREA|SELECT)$/.test(document.activeElement.tagName) && !document.activeElement.isContentEditable) {
    e.preventDefault(); box.focus(); box.select();
  } else if (e.key === 'Escape' && document.activeElement === box && box.value) {
    box.value = ''; renderProjects();
  }
});

async function openModal() {
  document.getElementById('modal-backdrop').classList.remove('hidden');
  document.getElementById('form-error').classList.add('hidden');
  document.getElementById('f-name').value = '';
  document.getElementById('f-override').checked = false;
  document.getElementById('f-manualNumber').value = '';
  document.getElementById('f-manualNumber').classList.add('hidden');
  for (const f of ['startDate', 'expectedCompletionDate', 'projectManager', 'projectDescription', 'internalNotes']) {
    document.getElementById(`f-${f}`).value = '';
  }
  document.getElementById('f-uploadDrawing').checked = false;

  const proposed = await window.api.projects.proposeNumber();
  document.getElementById('proposed-number').textContent = proposed;
  document.getElementById('proposed-number').dataset.value = proposed;

  const [clients, sites] = await Promise.all([window.api.clients.list(), window.api.sites.list()]);
  document.getElementById('f-client').innerHTML =
    '<option value="">Select a client</option>' + clients.map((c) => `<option value="${c.id}">${c.companyName}</option>`).join('');
  document.getElementById('f-site').innerHTML =
    '<option value="">Select a site</option>' + sites.map((s) => `<option value="${s.id}">${s.name}</option>`).join('');
  // From Clients & Sites (a client dragged onto a site): both chosen already.
  const ps = new URLSearchParams(location.search);
  if (ps.get('client')) document.getElementById('f-client').value = ps.get('client');
  if (ps.get('site')) document.getElementById('f-site').value = ps.get('site');
}
function closeModal() {
  document.getElementById('modal-backdrop').classList.add('hidden');
}

document.getElementById('f-override').addEventListener('change', (e) => {
  document.getElementById('f-manualNumber').classList.toggle('hidden', !e.target.checked);
});

async function saveProject() {
  const name = document.getElementById('f-name').value.trim();
  const clientId = document.getElementById('f-client').value;
  const siteId = document.getElementById('f-site').value;
  const errorEl = document.getElementById('form-error');

  if (!name || !clientId || !siteId) {
    errorEl.textContent = 'Project name, client, and site are all required.';
    errorEl.classList.remove('hidden');
    return;
  }

  const override = document.getElementById('f-override').checked;
  const manualNumber = document.getElementById('f-manualNumber').value.trim();

  const optional = {};
  for (const f of ['startDate', 'expectedCompletionDate', 'projectManager', 'projectDescription', 'internalNotes']) {
    optional[f] = document.getElementById(`f-${f}`).value.trim();
  }

  const result = await window.api.projects.create(Object.assign({
    name,
    clientId,
    siteId,
    overrideNumber: override,
    manualNumber,
  }, optional));

  if (!result.ok) {
    errorEl.textContent = result.error;
    errorEl.classList.remove('hidden');
    return;
  }

  // Section 14: optional drawing upload straight after creation — the
  // native file picker, copied (never moved) into the Drawings folder.
  if (document.getElementById('f-uploadDrawing').checked) {
    await window.api.projects.uploadDrawing(result.project.projectNumber);
  }
  closeModal();
  location.href = `project-detail.html?number=${result.project.projectNumber}${document.getElementById('f-uploadDrawing').checked ? '&tab=files' : ''}`;
}

// ⌘N from the menu bar lands here with ?new=1.
if (new URLSearchParams(location.search).get('new') === '1') {
  setTimeout(() => document.getElementById('new-project-btn').click(), 0);
}

document.getElementById('new-project-btn').addEventListener('click', openModal);
document.getElementById('cancel-btn').addEventListener('click', closeModal);
document.getElementById('save-btn').addEventListener('click', saveProject);
document.getElementById('search-box').addEventListener('input', applySearch);

refresh();

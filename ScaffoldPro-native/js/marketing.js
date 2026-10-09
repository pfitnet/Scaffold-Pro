'use strict';

// Marketing: how quotations turn into work (Overview), who to chase
// (Follow-ups), companies being won over (Leads), and a reference list of
// past projects for tenders and the company profile (Project References).

const STATUSES = ['New', 'Contacted', 'Quoted', 'Won', 'Lost'];
const SOURCES = ['Referral', 'Website', 'Tender', 'Cold Call', 'Repeat Client', 'Site Visit', 'Other'];

let summary = null;
let leads = [];
let editing = null;
const picked = new Set();

function esc(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}
function money(v) { return Number(v || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 }); }
function short(v) {
  const n = Number(v || 0);
  if (n >= 1e6) return `${(n / 1e6).toLocaleString('en-US', { maximumFractionDigits: 1 })}M`;
  if (n >= 1e3) return `${(n / 1e3).toLocaleString('en-US', { maximumFractionDigits: 0 })}k`;
  return n.toLocaleString('en-US', { maximumFractionDigits: 0 });
}
function today() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

// ---- tabs ----

function showTab(name) {
  for (const b of document.querySelectorAll('#mk-tabs button')) b.classList.toggle('active', b.dataset.tab === name);
  for (const p of document.querySelectorAll('.tab-panel')) p.classList.toggle('active', p.dataset.panel === name);
  // The Client Report and Promotions tabs load when first shown.
  document.dispatchEvent(new CustomEvent('marketing:tab', { detail: name }));
}

// ---- overview ----

function renderStats() {
  const cur = summary.currency === 'HKD' ? 'HK$' : summary.currency;
  const card = (value, label, tone) => `<div class="stat-card${tone ? ` tone-${tone}` : ''}"><div class="value">${value}</div><div class="label">${label}</div></div>`;
  document.getElementById('mk-stats').innerHTML =
    card(`${summary.quotedCount}`, `Quotations sent (12 months) · ${cur} ${short(summary.quotedValue)}`) +
    card(`${Math.round(summary.winRate * 100)}%`, `Won — ${summary.wonCount} of ${summary.quotedCount}`) +
    card(`${cur} ${short(summary.averageQuote)}`, 'Average quotation') +
    card(`${summary.openLeads}`, `Open leads · ${cur} ${short(summary.pipelineValue)} estimated`);
}

// ---- follow-ups ----

function renderFollowUps() {
  const box = document.getElementById('mk-followups');
  const list = summary.followUps || [];
  if (!list.length) { box.innerHTML = '<div class="empty-state"><h2>Nothing to chase</h2><p>Every quotation has a reply and every client has had work lately.</p></div>'; return; }
  const pill = { Quotation: '', Client: 'pill-warning', Lead: 'pill-success' };
  box.innerHTML = `<table><thead><tr><th>What</th><th>Type</th><th>Who</th><th class="num">Days</th></tr></thead><tbody>${list.map((f) => `
    <tr class="link-row" data-url="${esc(f.url)}">
      <td><strong>${esc(f.title)}</strong>${f.detail ? `<div class="sub">${esc(f.detail)}</div>` : ''}</td>
      <td><span class="status-pill kind-pill ${pill[f.kind] || ''}">${esc(f.kind)}</span></td>
      <td>${f.owner ? window.personTag(f.owner) : '<span class="muted">—</span>'}</td>
      <td class="num">${f.days}</td></tr>`).join('')}</tbody></table>`;
  wireLinks(box);
}

// ---- leads ----

function renderBoard() {
  const cur = summary ? (summary.currency === 'HKD' ? 'HK$' : summary.currency) : '';
  const t = today();
  document.getElementById('mk-board').innerHTML = STATUSES.map((status) => {
    const col = leads.filter((l) => l.status === status);
    const total = col.reduce((a, l) => a + (Number(l.estimatedValue) || 0), 0);
    return `<div class="board-col"><h3><span>${status} · ${col.length}</span>${total ? `<span>${cur} ${short(total)}</span>` : ''}</h3>
      ${col.map((l) => `<div class="lead-card" data-id="${esc(l.id)}">
        <div class="company">${esc(l.company)}</div>
        <div class="meta">${[l.contactPerson, l.source].filter(Boolean).map(esc).join(' · ')}</div>
        ${l.estimatedValue ? `<div class="meta">${cur} ${money(l.estimatedValue)}</div>` : ''}
        ${l.nextFollowUp && !['Won', 'Lost'].includes(l.status) ? `<div class="meta ${l.nextFollowUp <= t ? 'due' : ''}">Follow up ${esc(l.nextFollowUp)}</div>` : ''}
        ${l.owner ? `<div class="meta">${window.personTag(l.owner)}</div>` : ''}
      </div>`).join('') || '<div class="empty-inline">—</div>'}</div>`;
  }).join('');
  for (const card of document.querySelectorAll('.lead-card')) {
    card.addEventListener('click', () => openLead(leads.find((l) => l.id === card.dataset.id)));
  }
}

function openLead(lead) {
  editing = lead || null;
  const v = (id, value) => { document.getElementById(id).value = value ?? ''; };
  document.getElementById('ld-title').textContent = lead ? lead.company : 'New Lead';
  v('ld-company', lead && lead.company);
  v('ld-contact', lead && lead.contactPerson);
  v('ld-phone', lead && lead.phone);
  v('ld-email', lead && lead.email);
  v('ld-source', (lead && lead.source) || 'Referral');
  v('ld-status', (lead && lead.status) || 'New');
  v('ld-value', lead && lead.estimatedValue);
  v('ld-followup', lead && lead.nextFollowUp);
  v('ld-owner', (lead && lead.owner) || (summary && summary.userName) || '');
  v('ld-notes', lead && lead.notes);
  document.getElementById('ld-delete').classList.toggle('hidden', !lead);
  const convert = document.getElementById('ld-convert');
  convert.classList.toggle('hidden', !lead);
  convert.textContent = lead && lead.clientId ? 'Open Client' : 'Convert to Client';
  document.getElementById('ld-error').classList.add('hidden');
  document.getElementById('lead-modal').classList.remove('hidden');
  document.getElementById('ld-company').focus();
}

function closeLead() { document.getElementById('lead-modal').classList.add('hidden'); editing = null; }

async function saveLead() {
  const g = (id) => document.getElementById(id).value.trim();
  const value = g('ld-value');
  const payload = {
    id: editing ? editing.id : null, company: g('ld-company'), contactPerson: g('ld-contact'), phone: g('ld-phone'), email: g('ld-email'),
    source: g('ld-source'), status: g('ld-status'), estimatedValue: value === '' ? null : Number(value), nextFollowUp: g('ld-followup'),
    owner: g('ld-owner'), notes: g('ld-notes'),
  };
  const r = await window.api.marketing.saveLead(payload);
  if (!r || !r.ok) {
    const err = document.getElementById('ld-error');
    err.textContent = (r && r.error) || 'The lead couldn’t be saved.';
    err.classList.remove('hidden');
    return null;
  }
  closeLead();
  await load();
  return r.id;
}

// ---- references ----

function referenceRows() {
  const q = document.getElementById('ref-search').value.trim().toLowerCase();
  const status = document.getElementById('ref-status').value;
  return (summary.references || []).filter((r) => (!status || r.status === status) &&
    (!q || [r.projectNumber, r.name, r.clientName, r.siteName, ...(r.structures || [])].some((x) => String(x || '').toLowerCase().includes(q))));
}

function renderReferences() {
  const box = document.getElementById('mk-references');
  const rows = referenceRows();
  if (!rows.length) { box.innerHTML = '<div class="empty-state"><h2>No projects match</h2></div>'; return; }
  box.innerHTML = `<table><thead><tr><th class="ref-check"></th><th>Project</th><th>Client</th><th>Site</th><th>Scaffolding</th><th>Started</th><th>Status</th><th class="num">Quoted</th><th class="num">Invoiced</th></tr></thead><tbody>${rows.map((r) => `
    <tr data-number="${esc(r.projectNumber)}">
      <td class="ref-check"><input type="checkbox" class="ref-pick" ${picked.has(r.projectNumber) ? 'checked' : ''} /></td>
      <td><a href="project-detail.html?number=${encodeURIComponent(r.projectNumber)}"><strong>${esc(r.projectNumber)}</strong></a><div class="sub">${esc(r.name)}</div></td>
      <td>${esc(r.clientName || '—')}</td><td>${esc(r.siteName || '—')}</td>
      <td>${(r.structures || []).length ? r.structures.map(esc).join('<br>') : '<span class="muted">—</span>'}</td>
      <td class="nowrap">${esc(window.appDay(r.startDate))}</td>
      <td><span class="status-pill">${esc(r.status)}</span></td>
      <td class="num">${money(r.quotedValue)}</td><td class="num">${money(r.invoicedValue)}</td></tr>`).join('')}</tbody></table>`;
  for (const box2 of box.querySelectorAll('.ref-pick')) {
    box2.addEventListener('change', () => {
      const n = box2.closest('tr').dataset.number;
      if (box2.checked) picked.add(n); else picked.delete(n);
    });
  }
}

async function exportReferences() {
  const shown = referenceRows();
  const rows = picked.size ? shown.filter((r) => picked.has(r.projectNumber)) : shown;
  if (!rows.length) { alert('No projects to export.'); return; }
  const cell = (c) => { const t = String(c ?? ''); return /[",\n]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t; };
  const out = [['Project No.', 'Project', 'Client', 'Site', 'Scaffolding', 'Started', 'Status', 'Quoted', 'Invoiced']];
  for (const r of rows) out.push([r.projectNumber, r.name, r.clientName || '', r.siteName || '', (r.structures || []).join('; '), r.startDate || '', r.status, r.quotedValue.toFixed(2), r.invoicedValue.toFixed(2)]);
  const r = await window.api.accounts.saveCSV(`Project References ${today()}.xlsx`, out.map((row) => row.map(cell).join(',')).join('\r\n'), { adminFolder: 'Marketing' });
  if (r && r.ok === false) alert(r.error);
}

// ---- shared ----

function wireLinks(box) {
  for (const tr of box.querySelectorAll('tr[data-url]')) tr.addEventListener('click', () => { location.href = tr.dataset.url; });
}

// ⌘Z / ⌘Y redraw the page with this, not a reload (js/undo.js).
window.appRefresh = () => load();

async function load() {
  const [s, l, page] = await Promise.all([window.api.marketing.summary(), window.api.marketing.leads(), window.api.users.page().catch(() => null)]);
  summary = s;
  if (summary && page) summary.userName = page.name;
  leads = l || [];
  if (!summary) return;
  await window.loadPersonColors();
  renderStats();
  window.marketingOverview.render(summary, leads);
  renderFollowUps();
  renderBoard();
  renderReferences();
}

function init() {
  document.getElementById('ld-source').innerHTML = SOURCES.map((s) => `<option>${s}</option>`).join('');
  document.getElementById('ld-status').innerHTML = STATUSES.map((s) => `<option>${s}</option>`).join('');
  for (const b of document.querySelectorAll('#mk-tabs button')) b.addEventListener('click', () => showTab(b.dataset.tab));
  document.getElementById('new-lead-btn').addEventListener('click', () => { showTab('leads'); openLead(null); });
  document.getElementById('ld-cancel').addEventListener('click', closeLead);
  document.getElementById('ld-save').addEventListener('click', saveLead);
  document.getElementById('ld-delete').addEventListener('click', async () => {
    if (!editing) return;
    const company = editing.company;
    const r = await window.api.marketing.deleteLead(editing.id);
    if (r && r.ok === false) { alert(r.error); return; }
    closeLead();
    await load();
    if (window.appUndoHint) window.appUndoHint(`Lead “${company}” deleted`);
  });
  document.getElementById('ld-convert').addEventListener('click', async () => {
    if (!editing) return;
    if (editing.clientId) { location.href = `clients.html?id=${encodeURIComponent(editing.clientId)}`; return; }
    if (!await appConfirm(`Convert “${editing.company}” to a client?\n\nIt’s added to Clients with its contact details, and the lead is marked Won.`, { ok: 'Convert' })) return;
    const id = editing.id;
    if (await saveLead() === null) return;
    const r = await window.api.marketing.convertLead(id);
    if (!r || !r.ok) { alert((r && r.error) || 'The client couldn’t be made.'); return; }
    location.href = `clients.html?id=${encodeURIComponent(r.id)}`;
  });
  document.getElementById('ref-search').addEventListener('input', renderReferences);
  document.getElementById('ref-status').addEventListener('change', renderReferences);
  document.getElementById('ref-csv-btn').addEventListener('click', exportReferences);
  const params = new URLSearchParams(location.search);
  if (params.get('tab')) showTab(params.get('tab'));
  if (params.get('new') === '1') { showTab('leads'); openLead(null); }
  load().then(() => {
    const leadId = params.get('lead');
    const lead = leadId && leads.find((l) => l.id === leadId);
    if (lead) openLead(lead);
  });
}

init();

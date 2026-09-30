'use strict';

// Stock list: what's in the yard, out on hire (per project) and owned, for
// every material-list item, plus the movements behind the figures. Issued
// delivery notes book items out automatically (main.swift, stockData).

let data = null;
let expanded = null;
let modalKind = null;

const KIND_LABELS = {
  Opening: 'Opening stock', Purchase: 'Received', Delivery: 'Delivered (on hire)', Sale: 'Delivered (sold)',
  Return: 'Returned', Adjustment: 'Stock count', WriteOff: 'Written off',
};

function esc(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function qty(value) {
  return Math.round(Number(value || 0)).toLocaleString('en-US');
}

function signed(value) {
  const n = Math.round(Number(value || 0));
  return `${n > 0 ? '+' : n < 0 ? '−' : ''}${Math.abs(n).toLocaleString('en-US')}`;
}

function today() {
  const d = new Date();
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function listOf(item) {
  if (!item.sourceKey) return 'other';
  return item.sourceKey;
}

async function load() {
  data = await window.api.stock.data();
  renderStats();
  renderItems();
  renderMovements();
  if (!document.getElementById('tab-sites').classList.contains('hidden')) renderSites();
}

function renderStats() {
  const held = data.items.filter((i) => Math.abs(i.owned) > 0.0001 || Math.abs(i.inYard) > 0.0001);
  const inYard = data.items.reduce((a, i) => a + i.inYard, 0);
  const onHire = data.items.reduce((a, i) => a + i.onHire, 0);
  const tonnes = data.items.reduce((a, i) => a + (i.weightKg || 0) * i.owned, 0) / 1000;
  const cards = [
    [held.length.toLocaleString('en-US'), 'Items held'],
    [qty(inYard), 'Pieces in the yard'],
    [qty(onHire), 'Pieces out on hire'],
    [`${tonnes.toLocaleString('en-US', { maximumFractionDigits: 1 })} t`, 'Weight owned'],
  ];
  document.getElementById('stock-stats').innerHTML =
    cards.map(([v, l]) => `<div class="stat-card"><div class="value">${v}</div><div class="label">${l}</div></div>`).join('');
}

function filteredItems() {
  const q = document.getElementById('search-box').value.trim().toLowerCase();
  const list = document.getElementById('list-filter').value;
  const onlyHeld = document.getElementById('only-held').checked;
  return data.items.filter((i) => {
    if (onlyHeld && Math.abs(i.owned) < 0.0001 && Math.abs(i.inYard) < 0.0001) return false;
    if (list && listOf(i) !== list) return false;
    if (q && !`${i.itemCode} ${i.itemName} ${i.category || ''}`.toLowerCase().includes(q)) return false;
    return true;
  });
}

function renderItems() {
  const items = filteredItems();
  const container = document.getElementById('items-container');
  if (items.length === 0) {
    const onlyHeld = document.getElementById('only-held').checked;
    container.innerHTML = `<div class="empty-state"><h2>${onlyHeld ? 'No stock recorded yet' : 'No items match'}</h2>
      <p>${onlyHeld ? 'Use “Receive Stock…” or “Stock Count…” to record what’s in the yard. Issued delivery notes book items out automatically.' : ''}</p></div>`;
    return;
  }
  container.innerHTML = `<table class="stock-table">
    <thead><tr><th>Code</th><th>Item</th><th>Unit</th><th class="num">In Yard</th><th class="num">On Hire</th><th class="num">Owned</th><th class="num">Weight Owned (kg)</th></tr></thead>
    <tbody>${items.map((i) => {
      const detail = expanded === i.key ? detailRow(i) : '';
      return `<tr class="item-row" data-key="${esc(i.key)}">
        <td class="muted">${esc(i.itemCode)}</td>
        <td>${esc(i.itemName)}</td>
        <td>${esc(i.unit)}</td>
        <td class="num${i.inYard < 0 ? ' negative' : ''}" title="${i.inYard < 0 ? 'More has gone out than was recorded in — do a stock count' : ''}">${qty(i.inYard)}</td>
        <td class="num">${qty(i.onHire)}</td>
        <td class="num">${qty(i.owned)}</td>
        <td class="num muted">${i.weightKg ? (i.weightKg * i.owned).toLocaleString('en-US', { maximumFractionDigits: 1 }) : '—'}</td>
      </tr>${detail}`;
    }).join('')}</tbody></table>`;
  for (const tr of container.querySelectorAll('tr.item-row')) {
    tr.addEventListener('click', () => {
      expanded = expanded === tr.dataset.key ? null : tr.dataset.key;
      renderItems();
    });
  }
  for (const b of container.querySelectorAll('[data-action]')) {
    b.addEventListener('click', (e) => {
      e.stopPropagation();
      const item = data.items.find((i) => i.key === b.dataset.key);
      openModal(b.dataset.action, item);
    });
  }
}

function detailRow(item) {
  const hire = item.onHireByProject.length
    ? `<table class="compact"><tbody>${item.onHireByProject.map((p) =>
      `<tr><td><a href="project-detail.html?number=${encodeURIComponent(p.projectNumber)}">${esc(p.projectNumber)}</a> ${esc(p.projectName)}</td><td class="num">${qty(p.quantity)}</td></tr>`).join('')}</tbody></table>`
    : '<p class="small-note">Nothing out on hire.</p>';
  const moves = data.movements.filter((m) => m.movement.itemKey === item.key).slice(0, 12);
  const history = moves.length
    ? `<table class="compact"><tbody>${moves.map((m) => `<tr><td class="muted">${esc(m.movement.date)}</td><td>${KIND_LABELS[m.movement.kind] || m.movement.kind}</td>
        <td>${esc(m.projectNumber || '')}</td><td class="muted">${esc(m.movement.reference || '')}</td>
        <td class="num ${m.movement.quantity > 0 ? 'qty-in' : 'qty-out'}">${signed(m.movement.quantity)}</td></tr>`).join('')}</tbody></table>`
    : '<p class="small-note">No movements yet.</p>';
  const key = esc(item.key);
  return `<tr class="detail-row"><td colspan="7">
    <div class="detail-grid">
      <div><h4>On hire</h4>${hire}</div>
      <div><h4>Recent movements</h4>${history}</div>
    </div>
    <div class="toolbar" style="margin-top:10px">
      <button data-action="Purchase" data-key="${key}">Receive…</button>
      <button data-action="Return" data-key="${key}">Return…</button>
      <button data-action="Count" data-key="${key}">Count…</button>
      <button data-action="WriteOff" data-key="${key}">Write Off…</button>
    </div>
  </td></tr>`;
}

function filteredMovements() {
  const q = document.getElementById('movement-search').value.trim().toLowerCase();
  const kind = document.getElementById('movement-kind').value;
  return data.movements.filter((m) => {
    if (kind && m.movement.kind !== kind) return false;
    if (q && !`${m.movement.itemCode} ${m.movement.itemDescription} ${m.projectNumber || ''} ${m.movement.reference || ''} ${m.movement.notes || ''}`.toLowerCase().includes(q)) return false;
    return true;
  });
}

function renderMovements() {
  const list = filteredMovements();
  const container = document.getElementById('movements-container');
  if (list.length === 0) {
    container.innerHTML = '<div class="empty-state"><h2>No movements</h2></div>';
    return;
  }
  container.innerHTML = `<table class="sortable">
    <thead><tr><th>Date</th><th>Movement</th><th>Item</th><th class="num">Qty</th><th>Project</th><th>Reference</th><th>Notes</th><th></th></tr></thead>
    <tbody>${list.map((m) => `<tr>
      <td>${esc(m.movement.date)}</td>
      <td>${KIND_LABELS[m.movement.kind] || esc(m.movement.kind)}</td>
      <td>${esc(m.movement.itemDescription)}</td>
      <td class="num ${m.movement.quantity > 0 ? 'qty-in' : 'qty-out'}">${signed(m.movement.quantity)}</td>
      <td>${esc(m.projectNumber || '')}</td>
      <td>${esc(m.movement.reference || '')}</td>
      <td class="small-note">${esc(m.movement.notes || '')}</td>
      <td>${m.automatic ? '<span class="small-note" title="From a delivery note">auto</span>' : `<button class="remove-btn" data-id="${esc(m.movement.id)}">Delete</button>`}</td>
    </tr>`).join('')}</tbody></table>`;
  for (const b of container.querySelectorAll('.remove-btn')) {
    b.addEventListener('click', async () => {
      if (!await appConfirm('Delete this stock entry? The figures will be worked out again without it.')) return;
      const r = await window.api.stock.deleteMovement(b.dataset.id);
      if (!r.ok) alert(r.error);
      await load();
    });
  }
}

// ---------- Recording a movement ----------

const MODAL = {
  Purchase: { title: 'Receive Stock', qty: 'Quantity received', hint: 'Adds to what’s in the yard.' },
  Return: { title: 'Record Return', qty: 'Quantity returned', hint: 'Back in the yard, and off hire for the project.' },
  Count: { title: 'Stock Count', qty: 'Counted in the yard', hint: 'The difference from the recorded figure is saved as a stock-count adjustment.' },
  WriteOff: { title: 'Write Off', qty: 'Quantity written off', hint: 'Lost, scrapped or damaged: taken off the yard figure.' },
};

function itemLabel(i) {
  return `${i.itemCode ? `${i.itemCode} — ` : ''}${i.itemName} (${i.unit})`;
}

function findItem(text) {
  const t = text.trim().toLowerCase();
  return data.items.find((i) => itemLabel(i).toLowerCase() === t) ||
    data.items.find((i) => i.itemCode && i.itemCode.toLowerCase() === t) ||
    data.items.find((i) => i.itemName.toLowerCase() === t);
}

function updateHint() {
  const item = findItem(document.getElementById('mv-item').value);
  const parts = [MODAL[modalKind].hint];
  if (item) {
    parts.push(`Now: ${qty(item.inYard)} in the yard, ${qty(item.onHire)} on hire.`);
    if (modalKind === 'Return') {
      const p = item.onHireByProject.find((x) => x.projectId === document.getElementById('mv-project').value);
      if (p) parts.push(`${qty(p.quantity)} on hire to ${p.projectNumber}.`);
    }
  }
  document.getElementById('mv-hint').textContent = parts.join(' ');
}

function openModal(kind, item) {
  modalKind = kind;
  const m = MODAL[kind];
  document.getElementById('mv-title').textContent = m.title;
  document.getElementById('mv-qty-label').textContent = m.qty;
  document.getElementById('mv-item').value = item ? itemLabel(item) : '';
  document.getElementById('mv-qty').value = '';
  document.getElementById('mv-date').value = today();
  document.getElementById('mv-ref').value = '';
  document.getElementById('mv-notes').value = '';
  document.getElementById('mv-project-field').classList.toggle('hidden', kind !== 'Return');
  const projects = item && kind === 'Return' && item.onHireByProject.length
    ? data.projects.filter((p) => item.onHireByProject.some((h) => h.projectId === p.id)).concat(
      data.projects.filter((p) => !item.onHireByProject.some((h) => h.projectId === p.id)))
    : data.projects;
  document.getElementById('mv-project').innerHTML = projects.map((p) =>
    `<option value="${esc(p.id)}">${esc(p.projectNumber)} — ${esc(p.name)}</option>`).join('');
  document.getElementById('mv-error').classList.add('hidden');
  updateHint();
  document.getElementById('movement-modal').classList.remove('hidden');
  document.getElementById(item ? 'mv-qty' : 'mv-item').focus();
}

function closeModal() {
  document.getElementById('movement-modal').classList.add('hidden');
}

async function saveModal() {
  const text = document.getElementById('mv-item').value;
  const item = findItem(text);
  const payload = {
    kind: modalKind,
    priceListItemId: item ? item.priceListItemId : null,
    itemCode: item ? item.itemCode : '',
    itemDescription: item ? item.itemName : text.trim(),
    unit: item ? item.unit : 'pc',
    quantity: Number(document.getElementById('mv-qty').value),
    date: document.getElementById('mv-date').value,
    projectId: modalKind === 'Return' ? document.getElementById('mv-project').value : null,
    reference: document.getElementById('mv-ref').value,
    notes: document.getElementById('mv-notes').value,
  };
  if (document.getElementById('mv-qty').value === '') payload.quantity = modalKind === 'Count' ? -1 : 0;
  const r = await window.api.stock.addMovement(payload);
  if (!r.ok) {
    const err = document.getElementById('mv-error');
    err.textContent = r.error;
    err.classList.remove('hidden');
    return;
  }
  closeModal();
  await load();
}

// ---------- CSV ----------

function csvLine(cells) {
  return cells.map((c) => {
    const s = String(c ?? '');
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  }).join(',');
}

async function exportCSV(which) {
  let rows;
  let name;
  if (which === 'items') {
    rows = [['Code', 'Item', 'Unit', 'In Yard', 'On Hire', 'Owned', 'Weight Owned (kg)', 'On hire by project']]
      .concat(filteredItems().map((i) => [i.itemCode, i.itemName, i.unit, Math.round(i.inYard), Math.round(i.onHire), Math.round(i.owned),
        i.weightKg ? (i.weightKg * i.owned).toFixed(1) : '', i.onHireByProject.map((p) => `${p.projectNumber}: ${Math.round(p.quantity)}`).join('; ')]));
    name = `Stock List ${today()}.csv`;
  } else if (which === 'sites') {
    const select = document.getElementById('site-filter').value;
    rows = [['Site', 'Site Address', 'Code', 'Item', 'Unit', 'Qty on Site', 'Weight (kg)', 'Project', 'Managed by']];
    for (const site of siteHoldings().filter((s) => !select || s.key === select)) {
      for (const r of site.rows) {
        rows.push([site.name, site.address, r.item.itemCode, r.item.itemName, r.item.unit, Math.round(r.quantity),
          r.item.weightKg ? (r.item.weightKg * r.quantity).toFixed(1) : '', r.project.projectNumber, r.project.clientName || '']);
      }
    }
    name = `Stock by Site ${today()}.csv`;
  } else {
    rows = [['Date', 'Movement', 'Code', 'Item', 'Unit', 'Quantity', 'Project', 'Reference', 'Notes']]
      .concat(filteredMovements().map((m) => [m.movement.date, KIND_LABELS[m.movement.kind] || m.movement.kind, m.movement.itemCode,
        m.movement.itemDescription, m.movement.unit, Math.round(m.movement.quantity), m.projectNumber || '', m.movement.reference || '', m.movement.notes || '']));
    name = `Stock Movements ${today()}.csv`;
  }
  const r = await window.api.accounts.saveCSV(name, rows.map(csvLine).join('\r\n'));
  if (!r.ok) alert(r.error);
}

// ---------- Page ----------

// ---------- By Site: what's out on hire at each site, and with whom ----------

// Site → [{ item, quantity, project }], from each item's quantities on hire per project.
function siteHoldings() {
  const projects = new Map(data.projects.map((p) => [p.id, p]));
  const sites = new Map();
  for (const item of data.items) {
    for (const h of item.onHireByProject) {
      if (Math.abs(h.quantity) < 0.0001) continue;
      const project = projects.get(h.projectId) || { id: h.projectId, projectNumber: h.projectNumber, name: h.projectName };
      const key = project.siteId || `project:${project.id}`;
      if (!sites.has(key)) sites.set(key, { key, name: project.siteName || 'Site not set', address: project.siteAddress || '', rows: [] });
      sites.get(key).rows.push({ item, quantity: h.quantity, project });
    }
  }
  return [...sites.values()].sort((a, b) => a.name.localeCompare(b.name));
}

function renderSites() {
  const all = siteHoldings();
  const select = document.getElementById('site-filter');
  const keep = select.value;
  select.innerHTML = '<option value="">All sites</option>' + all.map((s) => `<option value="${esc(s.key)}">${esc(s.name)}</option>`).join('');
  if (all.some((s) => s.key === keep)) select.value = keep;
  const q = document.getElementById('site-search').value.trim().toLowerCase();
  const shown = all.filter((s) => !select.value || s.key === select.value).map((s) => Object.assign({}, s, {
    rows: s.rows.filter((r) => !q || `${r.item.itemCode} ${r.item.itemName} ${r.project.projectNumber} ${r.project.name} ${r.project.clientName || ''}`.toLowerCase().includes(q)),
  })).filter((s) => s.rows.length);
  const container = document.getElementById('sites-container');
  if (shown.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>${all.length ? 'Nothing matches' : 'Nothing is out on hire'}</h2><p>Materials appear here, by site, once delivery notes for them are issued.</p></div>`;
    return;
  }
  container.innerHTML = shown.map((site) => {
    const companies = [...new Set(site.rows.map((r) => r.project.clientName).filter(Boolean))];
    const weight = site.rows.reduce((a, r) => a + (r.item.weightKg || 0) * r.quantity, 0);
    const rows = site.rows.slice().sort((a, b) => String(a.project.projectNumber).localeCompare(String(b.project.projectNumber)) ||
      String(a.item.itemCode).localeCompare(String(b.item.itemCode), undefined, { numeric: true }));
    return `<section class="site-holding">
      <div class="site-holding-head">
        <div><strong>${esc(site.name)}</strong>${site.address ? `<div class="sub">${esc(site.address)}</div>` : ''}</div>
        <div class="site-holding-meta">${companies.length ? `Managed by <strong>${companies.map(esc).join('</strong>, <strong>')}</strong> · ` : ''}${qty(site.rows.reduce((a, r) => a + r.quantity, 0))} pcs${weight ? ` · ${(weight / 1000).toLocaleString('en-US', { maximumFractionDigits: 2 })} t` : ''}</div>
      </div>
      <table class="compact stock-table"><thead><tr><th>Item</th><th class="num">Qty on site</th><th class="num">Weight (kg)</th><th>Project</th><th>Managed by</th></tr></thead><tbody>
      ${rows.map((r) => `<tr>
        <td>${esc(r.item.itemName)}<div class="sub">${esc([r.item.itemCode, r.item.category].filter(Boolean).join(' · '))}</div></td>
        <td class="num">${qty(r.quantity)} ${esc(r.item.unit || '')}</td>
        <td class="num">${r.item.weightKg ? (r.item.weightKg * r.quantity).toLocaleString('en-US', { maximumFractionDigits: 1 }) : '—'}</td>
        <td><a href="project-detail.html?number=${encodeURIComponent(r.project.projectNumber)}">${esc(r.project.projectNumber)}</a><div class="sub">${esc(r.project.name || '')}</div></td>
        <td>${esc(r.project.clientName || '—')}</td></tr>`).join('')}
      </tbody></table></section>`;
  }).join('');
}

async function init() {
  await load();
  for (const b of document.querySelectorAll('#stock-tabs button')) {
    b.addEventListener('click', () => {
      for (const x of document.querySelectorAll('#stock-tabs button')) x.classList.toggle('active', x === b);
      document.getElementById('tab-items').classList.toggle('hidden', b.dataset.tab !== 'items');
      document.getElementById('tab-movements').classList.toggle('hidden', b.dataset.tab !== 'movements');
      document.getElementById('tab-sites').classList.toggle('hidden', b.dataset.tab !== 'sites');
      if (b.dataset.tab === 'sites') renderSites();
    });
  }
  for (const id of ['site-filter', 'site-search']) {
    document.getElementById(id).addEventListener('input', renderSites);
    document.getElementById(id).addEventListener('change', renderSites);
  }
  document.getElementById('export-sites-btn').addEventListener('click', () => exportCSV('sites'));
  for (const id of ['search-box', 'list-filter', 'only-held']) {
    document.getElementById(id).addEventListener('input', renderItems);
    document.getElementById(id).addEventListener('change', renderItems);
  }
  for (const id of ['movement-search', 'movement-kind']) {
    document.getElementById(id).addEventListener('input', renderMovements);
    document.getElementById(id).addEventListener('change', renderMovements);
  }
  document.getElementById('receive-btn').addEventListener('click', () => openModal('Purchase'));
  document.getElementById('return-btn').addEventListener('click', () => openModal('Return'));
  document.getElementById('count-btn').addEventListener('click', () => openModal('Count'));
  document.getElementById('writeoff-btn').addEventListener('click', () => openModal('WriteOff'));
  document.getElementById('export-items-btn').addEventListener('click', () => exportCSV('items'));
  document.getElementById('export-movements-btn').addEventListener('click', () => exportCSV('movements'));
  document.getElementById('mv-items').innerHTML = data.items.map((i) => `<option value="${esc(itemLabel(i))}"></option>`).join('');
  document.getElementById('mv-item').addEventListener('input', updateHint);
  document.getElementById('mv-project').addEventListener('change', updateHint);
  document.getElementById('mv-cancel').addEventListener('click', closeModal);
  document.getElementById('mv-save').addEventListener('click', saveModal);
  document.getElementById('movement-modal').addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeModal();
    if (e.key === 'Enter' && e.target.tagName !== 'TEXTAREA') saveModal();
  });
}

init();

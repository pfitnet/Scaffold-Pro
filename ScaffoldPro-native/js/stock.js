'use strict';

// Stock (stock.html, css/stock.css).
//
//   Stock     every item by category: in the yard, on hire, owned, and a bar
//             of the two. Click an item for where it's on hire, its recent
//             history and quick actions. "Stocktake" puts a Counted box on
//             every row: type the counts, save them all as one stock count.
//   Returns   signed delivery notes with items still on site. On the day set
//             we ask whether they're back: All Returned, Part Returned… (the
//             sheet filled in with what's out, to change), or Not Yet.
//   On Hire   by site, then project: what's there, with "Return…" to bring
//             it all back in one go.
//   Rented    what we've rented from other companies, by company, with
//             "Send Back…". Rented pieces are in the yard or on site but
//             aren't counted as owned.
//   History   every receipt, return, rental, count, write-off and delivery,
//             by day; things recorded together shown (and removed) together.
//
// Record Stock: one kind (Receive, Return, Rent In, Send Back, Count, Write
// Off), one date and reference, as many items as needed — typed with
// suggestions (Return adds the item and jumps to its quantity; Return there
// goes back for the next), pasted from Excel, or filled in one click
// (everything on hire to a project or still out on a delivery note;
// everything rented from a company; a whole category). Saved as one batch
// (main.swift, addStockMovements). A delivery note books its items out once
// it's issued and its signed copy is uploaded.

const S = {
  data: null,
  tab: 'stock',
  list: '',
  open: null,          // the item opened in the list
  closedCats: new Set(),
  taking: false,       // stocktake
  counts: new Map(),   // item key → counted (text)
  histKind: '',
  openBatches: new Set(),
  stats: {},
  flashDN: null,       // a delivery note to point at in Returns (?dn=…)
};
const RENT = '#9c6b98';

const KIND = {
  Opening: { label: 'Opening stock', verb: 'Opening stock', colour: '#3f938b' },
  Purchase: { label: 'Received', verb: 'Received', colour: '#3f938b' },
  Return: { label: 'Returned', verb: 'Returned', colour: '#5374b8' },
  Adjustment: { label: 'Stock count', verb: 'Counted', colour: '#8a6cb0' },
  WriteOff: { label: 'Written off', verb: 'Written off', colour: '#c5221f' },
  RentIn: { label: 'Rented in', verb: 'Rented in', colour: RENT },
  RentReturn: { label: 'Sent back to owner', verb: 'Sent back to owner', colour: RENT },
  Delivery: { label: 'Delivered (on hire)', verb: 'Delivered', colour: '#b0843f' },
  Sale: { label: 'Delivered (sold)', verb: 'Sold', colour: '#5d9150' },
};
const ICON = {
  Purchase: '<path d="M10 3v9M6.5 8.5 10 12l3.5-3.5"/><path d="M3.5 12.5v2A1.5 1.5 0 0 0 5 16h10a1.5 1.5 0 0 0 1.5-1.5v-2"/>',
  Opening: '<path d="M10 3v9M6.5 8.5 10 12l3.5-3.5"/><path d="M3.5 12.5v2A1.5 1.5 0 0 0 5 16h10a1.5 1.5 0 0 0 1.5-1.5v-2"/>',
  Return: '<path d="M8 5 4.5 8.5 8 12"/><path d="M4.5 8.5H12a4 4 0 0 1 0 8h-2"/>',
  Count: '<rect x="4.5" y="3.5" width="11" height="14" rx="1.8"/><path d="M7.5 3.5V2.5h5v1M7.5 9.5l1.5 1.5 3-3M7.5 14h5"/>',
  Adjustment: '<rect x="4.5" y="3.5" width="11" height="14" rx="1.8"/><path d="M7.5 3.5V2.5h5v1M7.5 9.5l1.5 1.5 3-3M7.5 14h5"/>',
  WriteOff: '<path d="M4.5 6h11M8 6V4.5h4V6M6 6l.8 10h6.4L14 6M8.5 9v4.5M11.5 9v4.5"/>',
  Delivery: '<path d="M2.5 5.5h9v8h-9zM11.5 8.5h3.5l2.5 2.5v2.5h-6"/><circle cx="5.5" cy="14.5" r="1.5"/><circle cx="14.5" cy="14.5" r="1.5"/>',
  Sale: '<path d="M10.5 3H16v5.5L9 15.5 3.5 10z"/><circle cx="13" cy="6" r="1"/>',
  RentIn: '<path d="M16 10H6M9.5 6.5 6 10l3.5 3.5M16 4.5v11"/>',
  RentReturn: '<path d="M4 10h10M10.5 6.5 14 10l-3.5 3.5M4 4.5v11"/>',
  company: '<rect x="4" y="3" width="12" height="14" rx="1.5"/><path d="M7.5 6.5h1.5M11 6.5h1.5M7.5 9.5h1.5M11 9.5h1.5M8.5 17v-3.5h3V17"/>',
  check: '<path d="m5 10.5 3.2 3.2L15 7"/>',
  site: '<path d="M10 17.5s-5.5-4.6-5.5-9a5.5 5.5 0 0 1 11 0c0 4.4-5.5 9-5.5 9z"/><circle cx="10" cy="8.5" r="2"/>',
  chev: '<path d="M7.5 5 12.5 10l-5 5"/>',
  x: '<path d="M5.5 5.5l9 9M14.5 5.5l-9 9"/>',
  box: '<path d="M3.5 6.5 10 3l6.5 3.5v7L10 17l-6.5-3.5z"/><path d="M3.5 6.5 10 10l6.5-3.5M10 10v7"/>',
};
const svg = (body, size = 16, stroke = 1.7) => `<svg viewBox="0 0 20 20" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="${stroke}" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
const $ = (id) => document.getElementById(id);
const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const n0 = (v) => Math.round(Number(v || 0));
const qty = (v) => n0(v).toLocaleString('en-US');
const signed = (v) => { const n = n0(v); return `${n > 0 ? '+' : n < 0 ? '−' : ''}${Math.abs(n).toLocaleString('en-US')}`; };
const tonnes = (kg) => `${(kg / 1000).toLocaleString('en-US', { maximumFractionDigits: 1 })} t`;
const today = () => { const d = new Date(); const p = (n) => String(n).padStart(2, '0'); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`; };
const day = (ymd) => (window.appDay ? window.appDay(ymd) : ymd);
const held = (i) => Math.abs(i.owned) > 0.0001 || Math.abs(i.inYard) > 0.0001;
const rentedOf = (i) => Math.max(0, i.rented || 0);
const listOf = (i) => i.sourceKey || 'other';
const catOf = (i) => i.category || (i.sourceKey ? 'Uncategorised' : 'Other items');
const store = {
  get(k, d) { try { const v = localStorage.getItem(`stock.${k}`); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
  set(k, v) { try { localStorage.setItem(`stock.${k}`, JSON.stringify(v)); } catch (e) { /* not kept */ } },
};

function toast(text) {
  const t = $('sk-toast');
  t.textContent = text;
  t.classList.add('show');
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => t.classList.remove('show'), 2200);
}

// ⌘Z / ⌘Y redraw the page with this, not a reload (js/undo.js).
window.appRefresh = () => load();

async function load() {
  S.data = await window.api.stock.data();
  S.data.returns = S.data.returns || [];
  S.byKey = new Map(S.data.items.map((i) => [i.key, i]));
  renderStats();
  renderDue();
  renderStock();
  renderReturns();
  renderHire();
  renderRented();
  renderHistory();
}

// ---------------------------------------------------------------- totals

// A number counting from what it showed to what it is now.
function countTo(el, to, format) {
  const from = Number(el.dataset.v || 0);
  el.dataset.v = to;
  if (matchMedia('(prefers-reduced-motion: reduce)').matches || from === to) { el.textContent = format(to); return; }
  const t0 = performance.now();
  const step = (t) => {
    const k = Math.min(1, (t - t0) / 650);
    const e = 1 - Math.pow(1 - k, 3);
    el.textContent = format(from + (to - from) * e);
    if (k < 1) requestAnimationFrame(step);
  };
  requestAnimationFrame(step);
}

function renderStats() {
  const items = S.data.items;
  const yard = items.reduce((a, i) => a + Math.max(0, i.inYard), 0);
  const hire = items.reduce((a, i) => a + Math.max(0, i.onHire), 0);
  const rent = items.reduce((a, i) => a + rentedOf(i), 0);
  const kg = items.reduce((a, i) => a + (i.weightKg || 0) * Math.max(0, i.owned), 0);
  const box = $('sk-stats');
  if (!box.children.length) {
    box.innerHTML = `
      <div class="sk-stat" style="--i:0"><b data-k="held">0</b><span>Items held</span></div>
      <div class="sk-stat" style="--i:1"><b data-k="yard">0</b><span><i class="dot" style="background:var(--sk-yard)"></i>Pieces in the yard</span></div>
      <div class="sk-stat" style="--i:2"><b data-k="hire">0</b><span><i class="dot" style="background:var(--sk-hire)"></i>Pieces on hire</span></div>
      <div class="sk-stat" style="--i:3" title="Rented from other companies: in the yard or on site, but not ours"><b data-k="rent">0</b><span><i class="dot" style="background:var(--sk-rent)"></i>Rented from others</span></div>
      <div class="sk-stat" style="--i:4"><b data-k="kg">0 t</b><span>Weight owned</span></div>
      <div class="sk-stat sk-split" style="--i:5"><div class="sk-split-bar"><i class="yard"></i><i class="hire"></i></div><div class="sk-split-legend"><span data-k="yardPct"></span><span data-k="hirePct"></span><span data-k="rentPct"></span></div></div>`;
  }
  const q = (k) => box.querySelector(`[data-k="${k}"]`);
  countTo(q('held'), items.filter(held).length, (v) => qty(v));
  countTo(q('yard'), yard, (v) => qty(v));
  countTo(q('hire'), hire, (v) => qty(v));
  countTo(q('rent'), rent, (v) => qty(v));
  countTo(q('kg'), kg, (v) => tonnes(v));
  const all = yard + hire;
  const pct = (v) => (all ? (v / all) * 100 : 0);
  box.querySelector('.sk-split-bar .yard').style.width = `${pct(yard)}%`;
  box.querySelector('.sk-split-bar .hire').style.width = `${pct(hire)}%`;
  // A dot in each one's colour and its share (the cards say which is which).
  const share = (v, c, what) => `<i class="dot" style="background:var(${c})"></i>${Math.round(pct(v))}%<span class="sr"> ${what}</span>`;
  q('yardPct').innerHTML = all ? share(yard, '--sk-yard', 'in the yard') : 'Nothing recorded yet';
  q('hirePct').innerHTML = all ? share(hire, '--sk-hire', 'on hire') : '';
  q('rentPct').innerHTML = all && rent ? share(rent, '--sk-rent', 'rented from others') : '';
  box.querySelector('.sk-split').title = all ? `${Math.round(pct(yard))}% in the yard, ${Math.round(pct(hire))}% on hire${rent ? ` (${Math.round(pct(rent))}% of it rented from others)` : ''}` : '';
  const sites = new Set();
  for (const i of items) for (const h of i.onHireByProject) if (h.quantity > 0) sites.add(h.projectId);
  $('sk-n-hire').textContent = sites.size ? String(sites.size) : '';
  $('sk-n-rented').textContent = companyHoldings().length || '';
  const due = S.data.returns.filter((r) => r.due).length;
  $('sk-n-returns').textContent = due || S.data.returns.length || '';
  $('sk-n-returns').classList.toggle('due', !!due);
}

// Signed delivery notes whose day has come: a calm note above the tabs.
function renderDue() {
  const due = S.data.returns.filter((r) => r.due);
  const box = $('sk-due');
  box.classList.toggle('hidden', !due.length || S.tab === 'returns');
  if (!due.length) return;
  const names = due.slice(0, 3).map((r) => `<b>${esc(r.deliveryNoteNumber)}</b>`).join(', ') + (due.length > 3 ? ` and ${due.length - 3} more` : '');
  box.innerHTML = `<span class="sk-due-ico">${svg(ICON.Delivery, 16)}</span>
    <span>Are the items back from site? ${names} ${due.length === 1 ? 'is' : 'are'} due to be checked.</span>
    <button type="button" data-no-icon id="sk-due-go">Check Now</button>`;
}

// ---------------------------------------------------------------- tabs

const TABS = ['stock', 'returns', 'hire', 'rented', 'history'];
function showTab(tab) {
  S.tab = tab;
  store.set('tab', tab);
  for (const b of document.querySelectorAll('#sk-tabs button')) b.classList.toggle('on', b.dataset.tab === tab);
  for (const p of TABS) $(`pane-${p}`).classList.toggle('hidden', p !== tab);
  moveInk();
  if (S.data) renderDue();
  if (tab !== 'stock' && S.taking) endStocktake();
}
function moveInk() {
  const on = document.querySelector('#sk-tabs button.on');
  const ink = document.querySelector('.sk-tab-ink');
  if (on && ink) { ink.style.left = `${on.offsetLeft}px`; ink.style.width = `${on.offsetWidth}px`; }
}

// ---------------------------------------------------------------- the stock list

function shownItems() {
  const q = $('sk-q').value.trim().toLowerCase();
  const onlyHeld = $('sk-held').checked;
  return S.data.items.filter((i) => (!onlyHeld || held(i) || (S.taking && S.counts.has(i.key)))
    && (!S.list || listOf(i) === S.list)
    && (!q || `${i.itemCode} ${i.itemName} ${i.category || ''}`.toLowerCase().includes(q)));
}

function bar(i) {
  const yard = Math.max(0, i.inYard), hire = Math.max(0, i.onHire), rent = rentedOf(i), all = yard + hire;
  if (!all) return '<div class="sk-mini-wrap"><div class="sk-mini"></div><small>—</small></div>';
  return `<div class="sk-mini-wrap" title="${qty(yard)} in the yard, ${qty(hire)} on hire${rent ? `; ${qty(rent)} of them rented from others` : ''}"><div class="sk-mini"><i class="yard" style="width:${(yard / all) * 100}%"></i><i class="hire" style="width:${(hire / all) * 100}%"></i></div>
    <small>${Math.round((hire / all) * 100)}% on hire${rent ? ` · <span class="rent">${qty(rent)} rented</span>` : ''}</small></div>`;
}

function renderStock() {
  const box = $('sk-list');
  document.querySelector('.sk').classList.toggle('taking', S.taking);
  const items = shownItems();
  if (!items.length) {
    const nothing = !S.data.items.some(held);
    box.innerHTML = `<div class="sk-empty">${svg(ICON.box, 34, 1.4)}<h3>${nothing ? 'No stock recorded yet' : 'Nothing matches'}</h3>
      <p>${nothing ? 'Use Record Stock › Receive (or a Stocktake) to put in what’s in the yard — many items at once, or pasted from Excel.' : 'Try another search, list, or show every item.'}</p></div>`;
    return;
  }
  const cats = new Map();
  for (const i of items) { const c = catOf(i); if (!cats.has(c)) cats.set(c, []); cats.get(c).push(i); }
  const head = S.taking
    ? '<div class="sk-row head"><span>Item</span><span class="num">In yard</span><span class="num">On hire</span><span class="num" title="Rented from other companies">Rented in</span><span class="num">Owned</span><span class="num">Counted</span><span class="num">Change</span></div>'
    : '<div class="sk-row head"><span>Item</span><span class="num">In yard</span><span class="num">On hire</span><span class="num" title="Rented from other companies: in the yard or on site, but not ours">Rented in</span><span class="num">Owned</span><span class="bar">Yard · Hire</span><span class="num">Weight owned</span></div>';
  let k = 0;
  box.innerHTML = [...cats].map(([cat, list], ci) => {
    const open = S.taking || !S.closedCats.has(cat) || !!$('sk-q').value.trim();
    const yard = list.reduce((a, i) => a + i.inYard, 0), hire = list.reduce((a, i) => a + i.onHire, 0), rent = list.reduce((a, i) => a + rentedOf(i), 0);
    return `<section class="sk-cat${open ? ' open' : ''}" data-cat="${esc(cat)}" style="--i:${Math.min(ci, 12)}">
      <button type="button" class="sk-cat-head" data-no-icon aria-expanded="${open}"><span class="chev">${svg(ICON.chev, 14, 2)}</span><b>${esc(cat)}</b>
        <span class="meta">${list.length} item${list.length === 1 ? '' : 's'} · ${qty(yard)} in the yard · ${qty(hire)} on hire${rent ? ` · ${qty(rent)} rented` : ''}</span></button>
      <div class="sk-cat-body"><div>${head}${list.map((i) => rowHTML(i, k++)).join('')}</div></div></section>`;
  }).join('');
  if (S.taking) updateDock();
}

function rowHTML(i) {
  const name = `<div class="name"><b>${esc(i.itemName)}</b><small>${esc([i.itemCode, i.unit].filter(Boolean).join(' · '))}</small></div>`;
  const cell = (v, extra = '') => `<span class="num${n0(v) < 0 ? ' neg' : n0(v) === 0 ? ' zero' : ''}"${extra}>${qty(v)}</span>`;
  if (S.taking) {
    const c = S.counts.has(i.key) ? S.counts.get(i.key) : '';
    const diff = c === '' ? '' : n0(c) - n0(i.inYard);
    return `<div class="sk-row" data-key="${esc(i.key)}">${name}${cell(i.inYard)}${cell(i.onHire)}${cell(rentedOf(i))}${cell(i.owned)}
      <input type="number" class="sk-count${c !== '' ? ' changed' : ''}" min="0" step="1" value="${esc(c)}" placeholder="${qty(i.inYard)}" aria-label="Counted ${esc(i.itemName)}" />
      <span class="num sk-diff${diff === '' ? '' : diff > 0 ? ' up' : diff < 0 ? ' down' : ''}">${diff === '' ? '' : diff === 0 ? '✓' : signed(diff)}</span></div>`;
  }
  const open = S.open === i.key;
  return `<div class="sk-row${open ? ' expanded' : ''}" data-key="${esc(i.key)}" tabindex="0">${name}
      ${cell(i.inYard, i.inYard < 0 ? ' title="More has gone out than was recorded in — a stocktake will put it right"' : '')}${cell(i.onHire)}${cell(rentedOf(i))}${cell(i.owned)}
      <span class="bar">${bar(i)}</span>
      <span class="num zero">${i.weightKg ? `${(i.weightKg * i.owned).toLocaleString('en-US', { maximumFractionDigits: 1 })} kg` : '—'}</span></div>
    <div class="sk-detail${open ? ' open' : ''}"><div>${open ? detailHTML(i) : ''}</div></div>`;
}

function detailHTML(i) {
  const hire = i.onHireByProject.filter((h) => Math.abs(h.quantity) > 0.0001);
  const rent = (i.rentedByCompany || []).filter((r) => r.quantity > 0.0001);
  const moves = S.data.movements.filter((m) => m.movement.itemKey === i.key).slice(0, 8);
  return `<div class="sk-detail-in">
    <div><h4>On hire</h4>${hire.length ? hire.map((h) => `<div class="line"><span><a href="project-detail.html?number=${encodeURIComponent(h.projectNumber)}">${esc(h.projectNumber)}</a> <span class="muted">${esc(h.projectName)}</span></span><b>${qty(h.quantity)}</b></div>`).join('') : '<p class="muted">Nothing out on hire.</p>'}
      ${rent.length ? `<h4>Rented from</h4>${rent.map((r) => `<div class="line"><span>${esc(r.company)}</span><b class="rent">${qty(r.quantity)}</b></div>`).join('')}` : ''}</div>
    <div><h4>Recent</h4>${moves.length ? moves.map((m) => `<div class="line"><span><span class="muted">${esc(day(m.movement.date))}</span> · ${esc(KIND[m.movement.kind] ? KIND[m.movement.kind].label : m.movement.kind)}${m.projectNumber ? ` · ${esc(m.projectNumber)}` : ''}${m.movement.reference ? ` <span class="muted">${esc(m.movement.reference)}</span>` : ''}</span><span class="${m.movement.quantity > 0 ? 'in' : 'out'}">${signed(m.movement.quantity)}</span></div>`).join('') : '<p class="muted">No movements yet.</p>'}</div>
    <div class="sk-quick">
      <button type="button" data-q="Purchase" data-no-icon>Receive…</button>
      <button type="button" data-q="Return" data-no-icon${hire.length ? '' : ' disabled title="Nothing on hire"'}>Return…</button>
      <button type="button" data-q="RentIn" data-no-icon>Rent In…</button>
      ${rent.length ? '<button type="button" data-q="RentReturn" data-no-icon>Send Back…</button>' : ''}
      <button type="button" data-q="Count" data-no-icon>Count…</button>
      <button type="button" data-q="WriteOff" data-no-icon>Write Off…</button>
    </div></div>`;
}

// ---- stocktake ----
function startStocktake() {
  S.taking = true;
  S.open = null;
  $('sk-stocktake').classList.add('on');
  $('sk-take-note').classList.remove('hidden');
  $('sk-dock').classList.remove('hidden');
  renderStock();
  const first = document.querySelector('.sk-count');
  if (first) first.focus();
}
function endStocktake() {
  S.taking = false;
  S.counts.clear();
  $('sk-stocktake').classList.remove('on');
  $('sk-take-note').classList.add('hidden');
  $('sk-dock').classList.add('hidden');
  renderStock();
}
function updateDock() {
  let up = 0, down = 0, same = 0;
  for (const [key, v] of S.counts) {
    const item = S.byKey.get(key);
    if (!item || v === '') continue;
    const d = n0(v) - n0(item.inYard);
    if (d > 0) up += 1; else if (d < 0) down += 1; else same += 1;
  }
  const n = [...S.counts.values()].filter((v) => v !== '').length;
  $('sk-dock-text').innerHTML = n ? `<b>${n}</b> counted · ${up ? `<span class="sk-diff up">${up} more</span> · ` : ''}${down ? `<span class="sk-diff down">${down} fewer</span> · ` : ''}${same} as recorded` : 'Type what you counted into the Counted boxes';
  $('sk-dock-save').disabled = !(up || down);
}
async function saveStocktake() {
  const lines = [];
  for (const [key, v] of S.counts) {
    const item = S.byKey.get(key);
    if (!item || v === '' || n0(v) === n0(item.inYard)) continue;
    lines.push(lineOf(item, n0(v)));
  }
  if (!lines.length) return;
  $('sk-dock-save').disabled = true;
  const r = await window.api.stock.addMovements({ kind: 'Count', date: today(), reference: 'Stocktake', lines });
  if (!r || !r.ok) { await window.appAlert((r && r.error) || 'The count couldn’t be saved.'); updateDock(); return; }
  toast(`Stocktake saved — ${r.saved} item${r.saved === 1 ? '' : 's'} put right`);
  endStocktake();
  await load();
}
const lineOf = (item, quantity) => ({ priceListItemId: item.priceListItemId, itemCode: item.itemCode, itemDescription: item.itemName, unit: item.unit, quantity });

// ---------------------------------------------------------------- on hire, by site

function siteHoldings() {
  const projects = new Map(S.data.projects.map((p) => [p.id, p]));
  const sites = new Map();
  for (const item of S.data.items) {
    for (const h of item.onHireByProject) {
      if (h.quantity <= 0.0001) continue;
      const p = projects.get(h.projectId) || { id: h.projectId, projectNumber: h.projectNumber, name: h.projectName };
      const key = p.siteId || `project:${p.id}`;
      if (!sites.has(key)) sites.set(key, { key, name: p.siteName || 'Site not set', address: p.siteAddress || '', projects: new Map() });
      const site = sites.get(key);
      if (!site.projects.has(p.id)) site.projects.set(p.id, { project: p, rows: [] });
      site.projects.get(p.id).rows.push({ item, quantity: h.quantity });
    }
  }
  return [...sites.values()].sort((a, b) => a.name.localeCompare(b.name));
}

function renderHire() {
  const q = $('sk-hire-q').value.trim().toLowerCase();
  const sites = siteHoldings().map((s) => {
    const projects = [...s.projects.values()].map((p) => Object.assign({}, p, {
      rows: p.rows.filter((r) => !q || `${s.name} ${s.address} ${r.item.itemCode} ${r.item.itemName} ${p.project.projectNumber} ${p.project.name} ${p.project.clientName || ''}`.toLowerCase().includes(q)),
    })).filter((p) => p.rows.length);
    return Object.assign({}, s, { list: projects });
  }).filter((s) => s.list.length);
  const box = $('sk-hire');
  if (!sites.length) {
    box.innerHTML = `<div class="sk-empty">${svg(ICON.site, 34, 1.4)}<h3>${q ? 'Nothing matches' : 'Nothing is out on hire'}</h3><p>Materials appear here, by site, once their delivery notes’ signed copies are uploaded.</p></div>`;
    return;
  }
  box.innerHTML = sites.map((s, si) => {
    const pcs = s.list.reduce((a, p) => a + p.rows.reduce((b, r) => b + r.quantity, 0), 0);
    const kg = s.list.reduce((a, p) => a + p.rows.reduce((b, r) => b + (r.item.weightKg || 0) * r.quantity, 0), 0);
    return `<section class="sk-site" style="--i:${Math.min(si, 12)}">
      <div class="sk-site-head"><span class="sk-site-ico">${svg(ICON.site, 18)}</span><div><b>${esc(s.name)}</b>${s.address ? `<small>${esc(s.address)}</small>` : ''}</div>
        <div class="meta"><b>${qty(pcs)} pcs</b>${kg ? tonnes(kg) : ''}</div></div>
      ${s.list.map((p) => `<div class="sk-site-proj">
        <h5><a href="project-detail.html?number=${encodeURIComponent(p.project.projectNumber)}">${esc(p.project.projectNumber)}</a><span>${esc(p.project.name || '')}${p.project.clientName ? ` · ${esc(p.project.clientName)}` : ''}</span>
          <button type="button" data-return="${esc(p.project.id)}" data-no-icon title="Record items back from this project — everything on hire filled in">Return…</button></h5>
        <div class="sk-chipset">${p.rows.sort((a, b) => String(a.item.itemCode).localeCompare(String(b.item.itemCode), undefined, { numeric: true }))
          .map((r) => `<span class="sk-chip" title="${esc(r.item.itemCode)}">${esc(r.item.itemName)} <b>${qty(r.quantity)}</b></span>`).join('')}</div></div>`).join('')}
    </section>`;
  }).join('');
}

// ---------------------------------------------------------------- returns

function renderReturns() {
  const box = $('sk-returns');
  const list = S.data.returns;
  if (!list.length) {
    box.innerHTML = `<div class="sk-empty">${svg(ICON.check, 34, 1.6)}<h3>Nothing to check</h3><p>Every signed delivery note’s items are back. When a signed copy is uploaded, its items show here until they’re returned.</p></div>`;
    return;
  }
  const now = today();
  box.innerHTML = list.map((r, i) => {
    const pct = r.delivered ? Math.round((r.returned / r.delivered) * 100) : 0;
    const state = r.returned > 0.0001 ? `<span class="sk-state part">Part returned</span>` : '<span class="sk-state out">On site</span>';
    const out = r.lines.filter((l) => l.outstanding > 0.0001);
    const where = [r.projectNumber && `${r.projectNumber} ${r.projectName}`, r.siteName, r.clientName].filter(Boolean).map(esc).join(' · ');
    const ask = r.due
      ? `<span class="sk-ask due">${r.checkDate < now ? `Asked since ${esc(day(r.checkDate))} — are they back?` : 'Today — are they back?'}</span>`
      : '<span class="sk-ask">We’ll ask on</span>';
    return `<article class="sk-ret${r.due ? ' due' : ''}${S.flashDN === r.deliveryNoteId ? ' flash' : ''}" data-dn="${esc(r.deliveryNoteId)}" style="--i:${Math.min(i, 12)}">
      <div class="sk-ret-head"><span class="sk-ret-ico">${svg(ICON.Delivery, 18)}</span>
        <div class="who"><div><a href="delivery-note-editor.html?id=${encodeURIComponent(r.deliveryNoteId)}">${esc(r.deliveryNoteNumber)}</a>${state}</div><small>${where}</small></div>
        <div class="meta"><b>${qty(r.outstanding)} pcs out</b><small>Delivered ${esc(day(r.deliveryDate))}</small></div></div>
      <div class="sk-ret-prog" title="${qty(r.returned)} of ${qty(r.delivered)} back"><div class="sk-mini"><i class="yard" style="width:${pct}%"></i></div><small>${qty(r.returned)} of ${qty(r.delivered)} back</small></div>
      <div class="sk-chipset">${out.map((l) => `<span class="sk-chip" title="${esc(l.itemCode)}${l.returned ? ` · ${qty(l.returned)} of ${qty(l.delivered)} back` : ''}">${esc(l.itemName)} <b>${qty(l.outstanding)}</b></span>`).join('')}</div>
      <div class="sk-ret-foot">${ask}${r.due ? '' : `<input type="date" class="sk-ret-date" value="${esc(r.checkDate)}" aria-label="Ask on" />`}
        <span class="sk-spacer"></span>
        <button type="button" data-ret="later" data-no-icon title="Ask again in two weeks">Not Yet</button>
        <button type="button" data-ret="part" data-no-icon title="Type what came back; the rest stays on site">Part Returned…</button>
        <button type="button" class="primary" data-ret="all" data-no-icon title="Everything still out on ${esc(r.deliveryNoteNumber)} is back in the yard">All Returned</button></div>
    </article>`;
  }).join('');
  if (S.flashDN) {
    const card = box.querySelector(`.sk-ret[data-dn="${CSS.escape(S.flashDN)}"]`);
    if (card) requestAnimationFrame(() => card.scrollIntoView({ block: 'center' }));
    S.flashDN = null;
  }
}

const plusDays = (ymd, n) => { const d = new Date(`${ymd}T00:00:00`); d.setDate(d.getDate() + n); const p = (x) => String(x).padStart(2, '0'); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}`; };

async function answerReturn(r, how) {
  if (how === 'later') {
    const next = plusDays(today(), 14);
    const res = await window.api.stock.returnCheck(r.deliveryNoteId, next);
    if (res && !res.ok) { await window.appAlert(res.error); return; }
    toast(`We’ll ask about ${r.deliveryNoteNumber} again on ${day(next)}`);
    await load();
  } else if (how === 'part') {
    openRec('Return', { returnFor: r });
  } else if (how === 'all') {
    if (!await window.appConfirm(`Record everything still out on ${r.deliveryNoteNumber} (${qty(r.outstanding)} pcs) as back in the yard today?`, { ok: 'All Returned' })) return;
    const lines = r.lines.filter((l) => l.outstanding > 0.0001).map((l) => ({ priceListItemId: l.priceListItemId, itemCode: l.itemCode, itemDescription: l.itemName, unit: l.unit, quantity: n0(l.outstanding) }));
    const res = await window.api.stock.addMovements({ kind: 'Return', date: today(), reference: r.deliveryNoteNumber, deliveryNoteId: r.deliveryNoteId, projectId: r.projectId, lines });
    if (!res || !res.ok) { await window.appAlert((res && res.error) || 'It couldn’t be saved.'); return; }
    toast(`${r.deliveryNoteNumber}: all ${qty(r.outstanding)} pcs back in the yard`);
    await load();
  }
}

// ---------------------------------------------------------------- rented, by company

function companyHoldings() {
  const by = new Map();
  for (const item of S.data.items) {
    for (const r of item.rentedByCompany || []) {
      if (r.quantity <= 0.0001) continue;
      const k = r.company.toLowerCase();
      if (!by.has(k)) by.set(k, { company: r.company, rows: [] });
      by.get(k).rows.push({ item, quantity: r.quantity });
    }
  }
  return [...by.values()].sort((a, b) => a.company.localeCompare(b.company));
}

function renderRented() {
  const q = $('sk-rent-q').value.trim().toLowerCase();
  const list = companyHoldings().map((c) => Object.assign({}, c, {
    rows: c.rows.filter((r) => !q || `${c.company} ${r.item.itemCode} ${r.item.itemName}`.toLowerCase().includes(q)),
  })).filter((c) => c.rows.length);
  const box = $('sk-rented');
  if (!list.length) {
    box.innerHTML = `<div class="sk-empty">${svg(ICON.company, 34, 1.4)}<h3>${q ? 'Nothing matches' : 'Nothing rented from other companies'}</h3><p>Materials we rent from other companies show here, by company. Use <b>Rent In…</b> to record them; they go into the yard but aren’t counted as owned.</p></div>`;
    return;
  }
  box.innerHTML = list.map((c, ci) => {
    const pcs = c.rows.reduce((a, r) => a + r.quantity, 0);
    const kg = c.rows.reduce((a, r) => a + (r.item.weightKg || 0) * r.quantity, 0);
    return `<section class="sk-site rent" style="--i:${Math.min(ci, 12)}">
      <div class="sk-site-head"><span class="sk-site-ico">${svg(ICON.company, 18)}</span><div><b>${esc(c.company)}</b><small>Rented from them · ${c.rows.length} item${c.rows.length === 1 ? '' : 's'}</small></div>
        <div class="meta"><b>${qty(pcs)} pcs</b>${kg ? tonnes(kg) : ''}</div>
        <button type="button" data-rentback="${esc(c.company)}" data-no-icon title="Record items sent back to ${esc(c.company)} — everything rented from them filled in">Send Back…</button></div>
      <div class="sk-site-proj"><div class="sk-chipset">${c.rows.sort((a, b) => String(a.item.itemCode).localeCompare(String(b.item.itemCode), undefined, { numeric: true }))
        .map((r) => `<span class="sk-chip" title="${esc(r.item.itemCode)}">${esc(r.item.itemName)} <b>${qty(r.quantity)}</b></span>`).join('')}</div></div>
    </section>`;
  }).join('');
}

// ---------------------------------------------------------------- history

function batches() {
  const groups = new Map();
  for (const m of S.data.movements) {
    const mv = m.movement;
    const key = mv.batchId || (mv.deliveryNoteId ? `dn:${mv.deliveryNoteId}:${mv.kind}` : `one:${mv.id}`);
    if (!groups.has(key)) groups.set(key, { key, kind: mv.kind, date: mv.date, reference: mv.reference, notes: mv.notes, projectNumber: m.projectNumber, company: mv.company, automatic: m.automatic, batchId: mv.batchId, lines: [] });
    groups.get(key).lines.push(m);
  }
  return [...groups.values()];
}

function renderHistory() {
  const kinds = [['', 'All'], ['Purchase', 'Received'], ['Return', 'Returned'], ['RentIn', 'Rented'], ['Adjustment', 'Counts'], ['WriteOff', 'Written off'], ['Delivery', 'Delivered']];
  $('sk-kinds').innerHTML = kinds.map(([k, l]) => `<button type="button" data-kind="${k}" class="${S.histKind === k ? 'on' : ''}" data-no-icon>${l}</button>`).join('');
  const q = $('sk-hist-q').value.trim().toLowerCase();
  const list = batches().filter((b) => (!S.histKind || b.kind === S.histKind || (S.histKind === 'Purchase' && b.kind === 'Opening') || (S.histKind === 'Delivery' && b.kind === 'Sale') || (S.histKind === 'RentIn' && b.kind === 'RentReturn'))
    && (!q || `${b.reference || ''} ${b.projectNumber || ''} ${b.notes || ''} ${b.lines.map((l) => `${l.movement.itemCode} ${l.movement.itemDescription}`).join(' ')}`.toLowerCase().includes(q)));
  const box = $('sk-history');
  if (!list.length) {
    box.innerHTML = `<div class="sk-empty">${svg(ICON.Count, 34, 1.4)}<h3>${q || S.histKind ? 'Nothing matches' : 'No history yet'}</h3><p>Receipts, returns, counts, write-offs and deliveries appear here.</p></div>`;
    return;
  }
  let lastDay = null;
  let i = 0;
  box.innerHTML = list.map((b) => {
    const k = KIND[b.kind] || { label: b.kind, colour: '#888' };
    const total = b.lines.reduce((a, l) => a + l.movement.quantity, 0);
    const open = S.openBatches.has(b.key);
    const head = b.date !== lastDay ? `<div class="sk-day">${esc(day(b.date))}</div>` : '';
    lastDay = b.date;
    const sub = [b.projectNumber, b.company, b.reference, b.notes].filter(Boolean).map(esc).join(' · ');
    return `${head}<article class="sk-batch${open ? ' open' : ''}" data-key="${esc(b.key)}" style="--i:${Math.min(i++, 14)}">
      <button type="button" class="sk-batch-head" data-no-icon aria-expanded="${open}"><span class="sk-k k-${esc(b.kind)}">${svg(ICON[b.kind] || ICON.box, 16)}</span>
        <span class="what"><b>${esc(k.verb || k.label)} · ${b.lines.length} item${b.lines.length === 1 ? '' : 's'}</b><small>${sub || (b.automatic ? 'From a delivery note' : '&nbsp;')}</small></span>
        <span class="tot ${total > 0 ? 'in' : total < 0 ? 'out' : ''}">${signed(total)}</span></button>
      <div class="sk-batch-body"><div><div class="sk-batch-lines">${b.lines.map((l) => `<div class="line"><span>${esc(l.movement.itemDescription)} <span class="muted">${esc(l.movement.itemCode)}</span></span><b class="${l.movement.quantity > 0 ? 'in' : 'out'}">${signed(l.movement.quantity)}</b></div>`).join('')}
        ${b.automatic ? '<p class="muted" style="margin:8px 0 0;font-size:12px">Booked by its signed delivery note — remove the signed copy, or cancel or reopen the delivery note, to change it.</p>' : `<div class="acts"><button type="button" class="danger-btn" data-remove="${esc(b.key)}" data-no-icon>Remove</button></div>`}
      </div></div></div></article>`;
  }).join('');
}

// ---------------------------------------------------------------- Record Stock

const REC = {
  Purchase: { title: 'Receive Stock', hint: 'Bought or delivered into the yard: adds to what’s in the yard.', qty: 'Received', now: 'In yard' },
  Return: { title: 'Return from a Project', hint: 'Back from site: into the yard, and off hire for the project.', qty: 'Returned', now: 'On hire' },
  RentIn: { title: 'Rent In', hint: 'Rented from another company: into the yard and usable on jobs, but not counted as owned. Under Rented until they go back.', qty: 'Rented in', now: 'In yard' },
  RentReturn: { title: 'Send Back to Owner', hint: 'Sent back to the company we rented them from: out of the yard, off the rental.', qty: 'Sent back', now: 'Rented' },
  Count: { title: 'Stock Count', hint: 'What you counted in the yard. Only the differences from the recorded figures are saved.', qty: 'Counted', now: 'In yard' },
  WriteOff: { title: 'Write Off', hint: 'Lost, scrapped or damaged: taken off what’s in the yard.', qty: 'Written off', now: 'In yard' },
};
const KCOL = { Purchase: '#3f938b', Return: '#5374b8', RentIn: RENT, RentReturn: RENT, Count: '#8a6cb0', WriteOff: '#c5221f' };
// `note`: the signed delivery note a return answers (Stock › Returns).
const R = { kind: 'Purchase', lines: [], sel: -1, matches: [], note: null };
const renting = () => R.kind === 'RentIn' || R.kind === 'RentReturn';

function openRec(kind, opts = {}) {
  R.lines = [];
  R.note = opts.returnFor || null;
  $('rec-date').value = today();
  $('rec-ref').value = R.note ? R.note.deliveryNoteNumber : '';
  $('rec-notes').value = '';
  $('rec-company').value = opts.company || '';
  $('rec-error').classList.add('hidden');
  $('rec').classList.remove('hidden');
  setKind(kind || 'Purchase', true);
  if (opts.select) $('rec-project').value = opts.select;
  if (opts.projectId) { $('rec-project').value = opts.projectId; fillFromProject(); }
  if (R.note) { $('rec-project').value = R.note.projectId; fillFromNote(); }
  if (opts.fillCompany) fillFromCompany();
  for (const it of opts.items || []) addLine(it.item, false, it.quantity === undefined ? '' : it.quantity);
  renderLines();
  requestAnimationFrame(() => {
    moveSeg();
    const first = document.querySelector('#rec-lines input');
    (opts.items && opts.items.length && first ? first : $('rec-find')).focus();
  });
}
function closeRec() { $('rec').classList.add('hidden'); hideSuggest(); R.note = null; }

function setKind(kind, quiet) {
  R.kind = kind;
  if (kind !== 'Return') R.note = null;
  const r = REC[kind];
  $('rec-title').textContent = R.note ? `Back from Site — ${R.note.deliveryNoteNumber}` : r.title;
  $('rec-hint').textContent = R.note
    ? 'Change the quantities to what came back. Whatever isn’t returned stays on site, and we ask about it again in two weeks.'
    : r.hint;
  $('rec-qty-head').textContent = r.qty;
  $('rec-ref').placeholder = renting() ? 'Rental agreement, delivery note…' : 'Supplier invoice, return note…';
  $('rec-now-head').textContent = R.note ? 'Still out' : r.now;
  $('rec-project').disabled = !!R.note;
  document.querySelector('.sk-rec').classList.toggle('count', kind === 'Count');
  document.querySelector('.sk-rec-fields').classList.toggle('return', kind === 'Return');
  document.querySelector('.sk-rec-fields').classList.toggle('rent', renting());
  if (renting()) $('rec-companies').innerHTML = [...new Set([...companyHoldings().map((c) => c.company), ...(S.data.companies || [])])].map((c) => `<option value="${esc(c)}"></option>`).join('');
  for (const b of document.querySelectorAll('#rec-kind button')) { b.classList.toggle('on', b.dataset.kind === kind); b.setAttribute('aria-checked', b.dataset.kind === kind); }
  if (kind === 'Return') fillProjects();
  renderFill();
  if (!quiet) { moveSeg(); renderLines(); }
}
function moveSeg() {
  const on = document.querySelector('#rec-kind button.on');
  const ink = document.querySelector('.sk-seg-ink');
  if (!on || !ink) return;
  ink.style.left = `${on.offsetLeft}px`;
  ink.style.width = `${on.offsetWidth}px`;
  ink.style.backgroundColor = KCOL[R.kind];
}

// Projects with something on hire first, with how much.
function onHireTo(projectId) {
  const out = [];
  for (const i of S.data.items) { const h = i.onHireByProject.find((x) => x.projectId === projectId && x.quantity > 0); if (h) out.push({ item: i, quantity: h.quantity }); }
  return out;
}
function fillProjects() {
  const sel = $('rec-project');
  const keep = sel.value;
  const withHire = new Map();
  for (const i of S.data.items) for (const h of i.onHireByProject) if (h.quantity > 0) withHire.set(h.projectId, (withHire.get(h.projectId) || 0) + h.quantity);
  const list = S.data.projects.slice().sort((a, b) => (withHire.has(b.id) - withHire.has(a.id)) || String(b.projectNumber).localeCompare(String(a.projectNumber)));
  sel.innerHTML = list.map((p) => `<option value="${esc(p.id)}">${esc(p.projectNumber)} — ${esc(p.name)}${withHire.has(p.id) ? ` (${qty(withHire.get(p.id))} pcs on hire)` : ''}</option>`).join('');
  if (keep && list.some((p) => p.id === keep)) sel.value = keep;
}
function renderFill() {
  const box = $('rec-fill');
  const cats = [...new Set(S.data.items.map(catOf))];
  if (R.kind === 'Return' && R.note) {
    box.innerHTML = `<span>Quick fill:</span><button type="button" id="fill-note" data-no-icon>Everything still out on ${esc(R.note.deliveryNoteNumber)}</button>`;
  } else if (R.kind === 'Return') {
    box.innerHTML = '<span>Quick fill:</span><button type="button" id="fill-hire" data-no-icon>Everything on hire to this project</button>';
  } else if (R.kind === 'RentReturn') {
    box.innerHTML = '<span>Quick fill:</span><button type="button" id="fill-company" data-no-icon>Everything rented from this company</button>';
  } else if (R.kind === 'Count' || R.kind === 'Purchase' || R.kind === 'RentIn') {
    box.innerHTML = `<span>Quick fill:</span><select id="fill-cat" aria-label="Category">${cats.map((c) => `<option>${esc(c)}</option>`).join('')}</select><button type="button" id="fill-cat-btn" data-no-icon>Add the whole category</button>
      ${R.kind === 'Count' ? '<button type="button" id="fill-held" data-no-icon>Every item we hold</button>' : ''}`;
  } else box.innerHTML = '';
}
function fillFromProject() {
  const rows = onHireTo($('rec-project').value);
  if (!rows.length) { toast('Nothing is on hire to that project'); return; }
  for (const r of rows) addLine(r.item, false, r.quantity);
  renderLines();
}

// A signed delivery note's items still out, at those quantities.
function fillFromNote() {
  for (const l of R.note.lines) {
    if (l.outstanding <= 0.0001) continue;
    const item = S.byKey.get(l.itemKey) || { key: l.itemKey, priceListItemId: l.priceListItemId, itemCode: l.itemCode, itemName: l.itemName, unit: l.unit, inYard: 0, onHireByProject: [], rentedByCompany: [] };
    addLine(item, false, l.outstanding);
  }
  renderLines();
}
const rentedBy = (item, company) => { const c = company.trim().toLowerCase(); const r = (item.rentedByCompany || []).find((x) => x.company.toLowerCase() === c); return r ? r.quantity : 0; };
function fillFromCompany() {
  const c = $('rec-company').value.trim();
  const rows = c ? S.data.items.filter((i) => rentedBy(i, c) > 0) : [];
  if (!rows.length) { toast(c ? 'Nothing is rented from that company' : 'Enter the company first'); return; }
  for (const i of rows) addLine(i, false, rentedBy(i, c));
  renderLines();
}

function nowFor(item) {
  if (R.kind === 'Return' && R.note) {
    const l = R.note.lines.find((x) => x.itemKey === item.key);
    return l ? l.outstanding : 0;
  }
  if (R.kind === 'RentReturn') return rentedBy(item, $('rec-company').value);
  if (R.kind === 'Return') {
    const h = item.onHireByProject.find((x) => x.projectId === $('rec-project').value);
    return h ? h.quantity : 0;
  }
  return item.inYard;
}
function addLine(item, focus = true, quantity = '') {
  const at = R.lines.findIndex((l) => l.item.key === item.key);
  if (at >= 0) {
    if (quantity !== '') R.lines[at].qty = String(n0(quantity));
    if (focus) {
      renderLines();
      const row = document.querySelector(`#rec-lines .sk-line[data-i="${at}"]`);
      if (row) { row.classList.remove('flash'); void row.offsetWidth; row.classList.add('flash'); row.querySelector('input').focus(); row.querySelector('input').select(); }
    }
    return;
  }
  R.lines.push({ item, qty: quantity === '' ? '' : String(n0(quantity)), fresh: true });
  if (focus) {
    renderLines();
    const inputs = document.querySelectorAll('#rec-lines input');
    const last = inputs[inputs.length - 1];
    if (last) { last.focus(); last.scrollIntoView({ block: 'nearest' }); }
  }
}
function renderLines() {
  const box = $('rec-lines');
  box.innerHTML = R.lines.map((l, i) => {
    const now = nowFor(l.item);
    const diff = R.kind === 'Count' && l.qty !== '' ? n0(l.qty) - n0(now) : null;
    const html = `<div class="sk-line${l.fresh ? '' : ' kept'}" data-i="${i}" style="${l.fresh ? '' : 'animation:none'}">
      <div class="name"><b>${esc(l.item.itemName)}</b><small>${esc([l.item.itemCode, catOf(l.item)].filter(Boolean).join(' · '))}</small></div>
      <span class="num">${qty(now)}</span>
      <input type="number" min="0" step="1" value="${esc(l.qty)}" placeholder="${R.kind === 'Count' ? qty(now) : '0'}" aria-label="${esc(REC[R.kind].qty)} ${esc(l.item.itemName)}" />
      <span class="num rec-diff sk-diff${diff == null ? '' : diff > 0 ? ' up' : diff < 0 ? ' down' : ''}">${diff == null ? '' : diff === 0 ? '✓' : signed(diff)}</span>
      <button type="button" class="rm" data-rm="${i}" data-no-icon title="Remove" aria-label="Remove ${esc(l.item.itemName)}">${svg(ICON.x, 14, 2)}</button></div>`;
    l.fresh = false;
    return html;
  }).join('');
  updateSum();
}
function updateSum() {
  const filled = R.lines.filter((l) => l.qty !== '' && (R.kind === 'Count' ? n0(l.qty) >= 0 : n0(l.qty) > 0));
  const pcs = filled.reduce((a, l) => a + n0(l.qty), 0);
  let text = R.lines.length ? `<b>${R.lines.length}</b> item${R.lines.length === 1 ? '' : 's'}` : 'No items yet — add one below';
  if (filled.length && R.kind !== 'Count') text += ` · <b>${qty(pcs)}</b> pcs`;
  if (R.kind === 'Count') {
    const changes = filled.filter((l) => n0(l.qty) !== n0(l.item.inYard)).length;
    if (filled.length) text += ` · <b>${changes}</b> to put right`;
  }
  $('rec-sum').innerHTML = text;
  $('rec-save').disabled = !filled.length;
  $('rec-save').textContent = filled.length ? `Save ${filled.length} Item${filled.length === 1 ? '' : 's'}` : 'Save';
}

// ---- finding items ----
function score(i, q) {
  const code = String(i.itemCode || '').toLowerCase(), name = i.itemName.toLowerCase(), cat = String(i.category || '').toLowerCase();
  if (code === q) return 100;
  if (code.startsWith(q)) return 80;
  if (name.startsWith(q)) return 60;
  const words = q.split(/\s+/);
  if (words.every((w) => `${code} ${name} ${cat}`.includes(w))) return 40 + (held(i) ? 5 : 0);
  return 0;
}
const mark = (text, q) => { const t = String(text); const at = t.toLowerCase().indexOf(q); return at < 0 ? esc(t) : `${esc(t.slice(0, at))}<mark>${esc(t.slice(at, at + q.length))}</mark>${esc(t.slice(at + q.length))}`; };
function suggest() {
  const q = $('rec-find').value.trim().toLowerCase();
  if (!q) { hideSuggest(); return; }
  R.matches = S.data.items.map((i) => [i, score(i, q)]).filter((x) => x[1] > 0).sort((a, b) => b[1] - a[1]).slice(0, 8).map((x) => x[0]);
  const box = $('rec-suggest');
  if (!R.matches.length) { box.innerHTML = '<button type="button" disabled data-no-icon><span></span><span>No item matches — try the code</span></button>'; box.hidden = false; R.sel = -1; return; }
  R.sel = 0;
  box.innerHTML = R.matches.map((i, k) => `<button type="button" role="option" data-k="${k}" class="${k === 0 ? 'on' : ''}" data-no-icon><code>${mark(i.itemCode || '—', q)}</code><span>${mark(i.itemName, q)}</span><small>${qty(i.inYard)} in yard</small></button>`).join('');
  box.hidden = false;
}
function hideSuggest() { $('rec-suggest').hidden = true; R.sel = -1; }
function pick(k) {
  const item = R.matches[k];
  if (!item) return;
  $('rec-find').value = '';
  hideSuggest();
  addLine(item, true);
}

// Rows pasted from Excel: an item (code or name) and a quantity on each.
function pasteRows(text) {
  const rows = text.replace(/\r/g, '').split('\n').map((r) => r.split(/\t|,(?=(?:[^"]*"[^"]*")*[^"]*$)/).map((c) => c.replace(/^"|"$/g, '').trim())).filter((r) => r.some(Boolean));
  if (rows.length < 1) return false;
  const byCode = new Map(S.data.items.filter((i) => i.itemCode).map((i) => [String(i.itemCode).toLowerCase(), i]));
  const byName = new Map(S.data.items.map((i) => [i.itemName.toLowerCase(), i]));
  let added = 0;
  const missing = [];
  for (const r of rows) {
    const numbers = r.filter((c) => /^-?\d[\d,]*(\.\d+)?$/.test(c));
    const quantity = numbers.length ? Number(numbers[numbers.length - 1].replace(/,/g, '')) : '';
    let item = null;
    for (const c of r) { const k = c.toLowerCase(); item = byCode.get(k) || byName.get(k); if (item) break; }
    if (!item) {
      const text = r.filter((c) => !/^-?\d[\d,]*(\.\d+)?$/.test(c)).join(' ').toLowerCase();
      const found = text ? S.data.items.filter((i) => i.itemName.toLowerCase().includes(text)) : [];
      if (found.length === 1) item = found[0];
    }
    if (item) { addLine(item, false, quantity); added += 1; } else if (r.some(Boolean)) missing.push(r.filter(Boolean).join(' '));
  }
  renderLines();
  if (added) toast(`${added} item${added === 1 ? '' : 's'} added from the paste`);
  const err = $('rec-error');
  if (missing.length) { err.textContent = `Not found on the material list: ${missing.slice(0, 4).join('; ')}${missing.length > 4 ? ` and ${missing.length - 4} more` : ''}.`; err.classList.remove('hidden'); }
  return added > 0 || missing.length > 0;
}

async function saveRec() {
  const lines = R.lines.filter((l) => l.qty !== '').map((l) => lineOf(l.item, n0(l.qty)));
  if (!lines.length) return;
  if (renting() && !$('rec-company').value.trim()) {
    const err = $('rec-error');
    err.textContent = 'Enter the company they’re rented from.';
    err.classList.remove('hidden');
    $('rec-company').focus();
    return;
  }
  $('rec-save').disabled = true;
  const r = await window.api.stock.addMovements({
    kind: R.kind, date: $('rec-date').value, reference: $('rec-ref').value, notes: $('rec-notes').value,
    projectId: R.kind === 'Return' ? $('rec-project').value : null, lines,
    deliveryNoteId: R.kind === 'Return' && R.note ? R.note.deliveryNoteId : null,
    company: renting() ? $('rec-company').value.trim() : null,
  });
  if (!r || !r.ok) {
    const err = $('rec-error');
    err.textContent = (r && r.error) || 'It couldn’t be saved.';
    err.classList.remove('hidden');
    updateSum();
    return;
  }
  closeRec();
  const verb = { Purchase: 'received', Return: 'returned', RentIn: 'rented in', RentReturn: 'sent back', Count: 'counted', WriteOff: 'written off' }[R.kind];
  toast(`${r.saved} item${r.saved === 1 ? '' : 's'} ${verb}${r.skipped && r.skipped.length ? ` · ${r.skipped.length} unchanged` : ''}`);
  await load();
}

// ---------------------------------------------------------------- Excel

function csvLine(cells) {
  return cells.map((c) => { const s = String(c ?? ''); return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s; }).join(',');
}
async function exportShown() {
  let rows; let name;
  if (S.tab === 'hire') {
    rows = [['Site', 'Site Address', 'Project', 'Company', 'Code', 'Item', 'Unit', 'Qty on Site', 'Weight (kg)']];
    for (const s of siteHoldings()) for (const p of s.projects.values()) for (const r of p.rows) {
      rows.push([s.name, s.address, p.project.projectNumber, p.project.clientName || '', r.item.itemCode, r.item.itemName, r.item.unit, n0(r.quantity), r.item.weightKg ? (r.item.weightKg * r.quantity).toFixed(1) : '']);
    }
    name = `Stock on Hire ${today()}.xlsx`;
  } else if (S.tab === 'rented') {
    rows = [['Rented From', 'Code', 'Item', 'Unit', 'Qty Rented', 'Weight (kg)']];
    for (const c of companyHoldings()) for (const r of c.rows) {
      rows.push([c.company, r.item.itemCode, r.item.itemName, r.item.unit, n0(r.quantity), r.item.weightKg ? (r.item.weightKg * r.quantity).toFixed(1) : '']);
    }
    name = `Stock Rented In ${today()}.xlsx`;
  } else if (S.tab === 'returns') {
    rows = [['Delivery Note', 'Project', 'Site', 'Delivered', 'Ask On', 'Code', 'Item', 'Unit', 'Delivered Qty', 'Back', 'Still Out']];
    for (const r of S.data.returns) for (const l of r.lines) {
      rows.push([r.deliveryNoteNumber, `${r.projectNumber} ${r.projectName}`.trim(), r.siteName || '', r.deliveryDate, r.checkDate, l.itemCode, l.itemName, l.unit, n0(l.delivered), n0(l.returned), n0(l.outstanding)]);
    }
    name = `Stock Returns ${today()}.xlsx`;
  } else if (S.tab === 'history') {
    rows = [['Date', 'Movement', 'Code', 'Item', 'Unit', 'Quantity', 'Project', 'Company', 'Reference', 'Notes']]
      .concat(S.data.movements.map((m) => [m.movement.date, KIND[m.movement.kind] ? KIND[m.movement.kind].label : m.movement.kind, m.movement.itemCode,
        m.movement.itemDescription, m.movement.unit, n0(m.movement.quantity), m.projectNumber || '', m.movement.company || '', m.movement.reference || '', m.movement.notes || '']));
    name = `Stock History ${today()}.xlsx`;
  } else {
    rows = [['Category', 'Code', 'Item', 'Unit', 'In Yard', 'On Hire', 'Rented In', 'Owned', 'Weight Owned (kg)', 'On hire by project', 'Rented from']]
      .concat(shownItems().map((i) => [catOf(i), i.itemCode, i.itemName, i.unit, n0(i.inYard), n0(i.onHire), n0(rentedOf(i)), n0(i.owned),
        i.weightKg ? (i.weightKg * i.owned).toFixed(1) : '', i.onHireByProject.map((p) => `${p.projectNumber}: ${n0(p.quantity)}`).join('; '),
        (i.rentedByCompany || []).map((r) => `${r.company}: ${n0(r.quantity)}`).join('; ')]));
    name = `Stock List ${today()}.xlsx`;
  }
  const r = await window.api.accounts.saveCSV(name, rows.map(csvLine).join('\r\n'));
  if (r && !r.ok) await window.appAlert(r.error);
}

// ---------------------------------------------------------------- wiring

function wire() {
  // Tabs
  for (const b of document.querySelectorAll('#sk-tabs button')) b.addEventListener('click', () => showTab(b.dataset.tab));
  window.addEventListener('resize', moveInk);
  // Record Stock menu
  const menu = $('sk-record-menu');
  menu.innerHTML = Object.entries(REC).map(([k, r]) => `<button type="button" role="menuitem" data-kind="${k}" data-no-icon>
    <span class="k-ico" style="background:${KCOL[k]}">${svg(ICON[k], 16)}</span>
    <span><b>${esc(r.title)}</b><small>${esc(r.hint.split(':')[0])}</small></span></button>`).join('');
  const hideMenu = () => { menu.hidden = true; $('sk-record').setAttribute('aria-expanded', 'false'); };
  $('sk-record').addEventListener('click', (e) => {
    e.stopPropagation();
    menu.hidden = !menu.hidden;
    $('sk-record').setAttribute('aria-expanded', String(!menu.hidden));
    if (!menu.hidden) menu.querySelector('button').focus();
  });
  menu.addEventListener('click', (e) => { const b = e.target.closest('button[data-kind]'); if (b) { hideMenu(); openRec(b.dataset.kind); } });
  menu.addEventListener('keydown', (e) => {
    const items = [...menu.querySelectorAll('button')];
    const at = items.indexOf(document.activeElement);
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') { e.preventDefault(); items[(at + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length].focus(); }
    if (e.key === 'Escape') { hideMenu(); $('sk-record').focus(); }
  });
  document.addEventListener('click', (e) => { if (!menu.hidden && !e.target.closest('.sk-record')) hideMenu(); });
  $('sk-export').addEventListener('click', exportShown);

  // Stock list
  $('sk-q').addEventListener('input', renderStock);
  $('sk-held').addEventListener('change', () => { store.set('held', $('sk-held').checked); renderStock(); });
  $('sk-lists').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-list]');
    if (!b) return;
    S.list = b.dataset.list;
    for (const x of $('sk-lists').children) x.classList.toggle('on', x === b);
    renderStock();
  });
  $('sk-stocktake').addEventListener('click', async () => {
    if (!S.taking) { startStocktake(); return; }
    if ([...S.counts.values()].some((v) => v !== '') && !await window.appConfirm('Leave the stocktake? What you’ve typed isn’t saved.', { ok: 'Leave', danger: true })) return;
    endStocktake();
  });
  $('sk-dock-cancel').addEventListener('click', () => $('sk-stocktake').click());
  $('sk-dock-save').addEventListener('click', saveStocktake);
  const list = $('sk-list');
  list.addEventListener('click', (e) => {
    const head = e.target.closest('.sk-cat-head');
    if (head) {
      const cat = head.parentElement;
      const open = !cat.classList.contains('open');
      cat.classList.toggle('open', open);
      head.setAttribute('aria-expanded', String(open));
      if (open) S.closedCats.delete(cat.dataset.cat); else S.closedCats.add(cat.dataset.cat);
      store.set('closed', [...S.closedCats]);
      return;
    }
    const quick = e.target.closest('button[data-q]');
    if (quick) {
      const item = S.byKey.get(S.open);
      const k = quick.dataset.q;
      const hire = item.onHireByProject.filter((h) => h.quantity > 0);
      const rent = (item.rentedByCompany || []).filter((r) => r.quantity > 0);
      // A return: from the (first) project it's on hire to, with that
      // quantity; sending back: to the (first) company it's rented from.
      const qtyNow = k === 'Return' && hire.length ? hire[0].quantity : k === 'RentReturn' && rent.length ? rent[0].quantity : '';
      openRec(k, { items: [{ item, quantity: qtyNow }], select: k === 'Return' && hire.length ? hire[0].projectId : null,
        company: k === 'RentReturn' && rent.length ? rent[0].company : null });
      return;
    }
    if (S.taking || e.target.closest('a, input')) return;
    const row = e.target.closest('.sk-row[data-key]');
    if (!row) return;
    const was = S.open;
    S.open = S.open === row.dataset.key ? null : row.dataset.key;
    // Open and close smoothly: the old one folds as the new one unfolds.
    if (was) { const old = list.querySelector(`.sk-row[data-key="${CSS.escape(was)}"]`); if (old) { old.classList.remove('expanded'); old.nextElementSibling.classList.remove('open'); } }
    if (S.open) {
      row.classList.add('expanded');
      const d = row.nextElementSibling;
      d.firstElementChild.innerHTML = detailHTML(S.byKey.get(S.open));
      requestAnimationFrame(() => d.classList.add('open'));
    }
  });
  list.addEventListener('keydown', (e) => {
    if (e.target.classList.contains('sk-count')) {
      if (e.key === 'ArrowDown' || e.key === 'ArrowUp' || e.key === 'Enter') {
        e.preventDefault();
        const all = [...list.querySelectorAll('.sk-count')];
        const next = all[all.indexOf(e.target) + (e.key === 'ArrowUp' ? -1 : 1)];
        if (next) { next.focus(); next.select(); }
      }
      return;
    }
    if ((e.key === 'Enter' || e.key === ' ') && e.target.classList.contains('sk-row')) { e.preventDefault(); e.target.click(); }
  });
  list.addEventListener('input', (e) => {
    if (!e.target.classList.contains('sk-count')) return;
    const row = e.target.closest('.sk-row');
    const item = S.byKey.get(row.dataset.key);
    const v = e.target.value.trim();
    if (v === '') S.counts.delete(item.key); else S.counts.set(item.key, v);
    e.target.classList.toggle('changed', v !== '');
    const diffEl = row.querySelector('.sk-diff');
    const d = v === '' ? null : n0(v) - n0(item.inYard);
    diffEl.className = `num sk-diff${d == null ? '' : d > 0 ? ' up' : d < 0 ? ' down' : ''}`;
    diffEl.textContent = d == null ? '' : d === 0 ? '✓' : signed(d);
    updateDock();
  });

  // On hire
  $('sk-hire-q').addEventListener('input', renderHire);
  $('sk-hire').addEventListener('click', (e) => { const b = e.target.closest('button[data-return]'); if (b) openRec('Return', { projectId: b.dataset.return }); });

  // Returns: are a signed delivery note's items back?
  $('sk-due').addEventListener('click', (e) => { if (e.target.closest('#sk-due-go')) showTab('returns'); });
  $('sk-returns').addEventListener('click', (e) => {
    const b = e.target.closest('button[data-ret]');
    if (!b) return;
    const r = S.data.returns.find((x) => x.deliveryNoteId === b.closest('.sk-ret').dataset.dn);
    if (r) answerReturn(r, b.dataset.ret);
  });
  $('sk-returns').addEventListener('change', async (e) => {
    if (!e.target.classList.contains('sk-ret-date') || !e.target.value) return;
    const dn = e.target.closest('.sk-ret').dataset.dn;
    const res = await window.api.stock.returnCheck(dn, e.target.value);
    if (res && !res.ok) { await window.appAlert(res.error); return; }
    toast(`We’ll ask on ${day(e.target.value)}`);
    await load();
  });

  // Rented
  $('sk-rent-q').addEventListener('input', renderRented);
  $('sk-rent-new').addEventListener('click', () => openRec('RentIn'));
  $('sk-rented').addEventListener('click', (e) => { const b = e.target.closest('button[data-rentback]'); if (b) openRec('RentReturn', { company: b.dataset.rentback, fillCompany: true }); });

  // History
  $('sk-hist-q').addEventListener('input', renderHistory);
  $('sk-kinds').addEventListener('click', (e) => { const b = e.target.closest('button[data-kind]'); if (b) { S.histKind = b.dataset.kind; renderHistory(); } });
  $('sk-history').addEventListener('click', async (e) => {
    const rm = e.target.closest('button[data-remove]');
    if (rm) {
      const b = batches().find((x) => x.key === rm.dataset.remove);
      if (!b) return;
      const r = b.batchId ? await window.api.stock.deleteBatch(b.batchId) : await window.api.stock.deleteMovement(b.lines[0].movement.id);
      if (r && !r.ok) { await window.appAlert(r.error); return; }
      const what = KIND[b.kind] ? KIND[b.kind].label.toLowerCase() : 'entry';
      if (window.appUndoHint) window.appUndoHint(`Removed the ${what} (${b.lines.length} item${b.lines.length === 1 ? '' : 's'})`); else toast('Removed — ⌘Z puts it back');
      await load();
      return;
    }
    const head = e.target.closest('.sk-batch-head');
    if (!head) return;
    const card = head.parentElement;
    const open = !card.classList.contains('open');
    card.classList.toggle('open', open);
    head.setAttribute('aria-expanded', String(open));
    if (open) S.openBatches.add(card.dataset.key); else S.openBatches.delete(card.dataset.key);
  });

  // Record Stock
  $('rec-kind').addEventListener('click', (e) => { const b = e.target.closest('button[data-kind]'); if (b && b.dataset.kind !== R.kind) setKind(b.dataset.kind); });
  $('rec-kind').addEventListener('keydown', (e) => {
    if (e.key !== 'ArrowRight' && e.key !== 'ArrowLeft') return;
    const kinds = Object.keys(REC);
    const next = kinds[(kinds.indexOf(R.kind) + (e.key === 'ArrowRight' ? 1 : -1) + kinds.length) % kinds.length];
    setKind(next);
    document.querySelector(`#rec-kind button[data-kind="${next}"]`).focus();
  });
  $('rec-project').addEventListener('change', renderLines);
  $('rec-company').addEventListener('input', renderLines);
  $('rec-fill').addEventListener('click', (e) => {
    if (e.target.id === 'fill-hire') fillFromProject();
    if (e.target.id === 'fill-note') fillFromNote();
    if (e.target.id === 'fill-company') fillFromCompany();
    if (e.target.id === 'fill-cat-btn') { const c = $('fill-cat').value; for (const i of S.data.items.filter((x) => catOf(x) === c)) addLine(i, false); renderLines(); }
    if (e.target.id === 'fill-held') { for (const i of S.data.items.filter(held)) addLine(i, false); renderLines(); }
  });
  const find = $('rec-find');
  find.addEventListener('input', suggest);
  find.addEventListener('keydown', (e) => {
    const box = $('rec-suggest');
    if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      if (box.hidden || !R.matches.length) return;
      e.preventDefault();
      R.sel = (R.sel + (e.key === 'ArrowDown' ? 1 : -1) + R.matches.length) % R.matches.length;
      box.querySelectorAll('button').forEach((b, k) => b.classList.toggle('on', k === R.sel));
      box.querySelectorAll('button')[R.sel].scrollIntoView({ block: 'nearest' });
    } else if (e.key === 'Enter') {
      e.preventDefault();
      if (!box.hidden && R.sel >= 0) pick(R.sel);
    } else if (e.key === 'Escape' && !box.hidden) {
      e.preventDefault(); e.stopPropagation(); hideSuggest();
    }
  });
  find.addEventListener('blur', () => setTimeout(hideSuggest, 150));
  $('rec-suggest').addEventListener('mousedown', (e) => { const b = e.target.closest('button[data-k]'); if (b) { e.preventDefault(); pick(Number(b.dataset.k)); } });
  find.addEventListener('paste', (e) => {
    const text = (e.clipboardData || window.clipboardData).getData('text');
    if (/\n|\t/.test(text.trim())) { e.preventDefault(); pasteRows(text); }
  });
  const lines = $('rec-lines');
  lines.addEventListener('input', (e) => {
    const row = e.target.closest('.sk-line');
    if (!row) return;
    const l = R.lines[Number(row.dataset.i)];
    l.qty = e.target.value.trim();
    if (R.kind === 'Count') {
      const d = l.qty === '' ? null : n0(l.qty) - n0(nowFor(l.item));
      const el = row.querySelector('.rec-diff');
      el.className = `num rec-diff sk-diff${d == null ? '' : d > 0 ? ' up' : d < 0 ? ' down' : ''}`;
      el.textContent = d == null ? '' : d === 0 ? '✓' : signed(d);
    }
    updateSum();
  });
  lines.addEventListener('keydown', (e) => {
    if (e.target.tagName !== 'INPUT') return;
    if (e.key === 'Enter') {
      e.preventDefault();
      if (e.metaKey || e.ctrlKey) { saveRec(); return; }
      find.focus();
    } else if (e.key === 'ArrowDown' || e.key === 'ArrowUp') {
      e.preventDefault();
      const all = [...lines.querySelectorAll('input')];
      const next = all[all.indexOf(e.target) + (e.key === 'ArrowUp' ? -1 : 1)];
      (next || (e.key === 'ArrowDown' ? find : null) || e.target).focus();
    }
  });
  lines.addEventListener('click', (e) => {
    const b = e.target.closest('button[data-rm]');
    if (!b) return;
    const row = b.closest('.sk-line');
    row.classList.add('leaving');
    setTimeout(() => { R.lines.splice(Number(b.dataset.rm), 1); renderLines(); }, 170);
  });
  $('rec-cancel').addEventListener('click', closeRec);
  $('rec-save').addEventListener('click', saveRec);
  $('rec').addEventListener('keydown', async (e) => {
    if (e.key === 'Escape') {
      e.preventDefault();
      if (R.lines.some((l) => l.qty !== '') && !await window.appConfirm('Close without saving these items?', { ok: 'Close', danger: true })) return;
      closeRec();
    } else if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); saveRec(); }
  });
  $('rec').addEventListener('mousedown', (e) => { if (e.target === $('rec')) closeRec(); });
  // ⌘V anywhere in the dialog (not in a box): rows from Excel.
  $('rec').addEventListener('paste', (e) => {
    if (e.target.closest('input, textarea, select')) return;
    const text = (e.clipboardData || window.clipboardData).getData('text');
    if (text.trim()) { e.preventDefault(); pasteRows(text); }
  });
  // N: Record Stock.
  document.addEventListener('keydown', (e) => {
    if (!$('rec').classList.contains('hidden') || /INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName) || e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === 'n' || e.key === 'N') { e.preventDefault(); openRec('Purchase'); }
    if (e.key === '/') { const q = { stock: 'sk-q', hire: 'sk-hire-q', rented: 'sk-rent-q', history: 'sk-hist-q' }[S.tab]; if (q) { e.preventDefault(); $(q).focus(); } }
  });
}

async function init() {
  S.closedCats = new Set(store.get('closed', []));
  $('sk-held').checked = store.get('held', true);
  wire();
  // ?tab=returns&dn=… (from the calendar or a delivery note): that card.
  const params = new URLSearchParams(location.search);
  S.flashDN = params.get('dn');
  const asked = params.get('tab') || store.get('tab', 'stock');
  showTab(TABS.includes(asked) ? asked : 'stock');
  await load();
  moveInk();
}

init();

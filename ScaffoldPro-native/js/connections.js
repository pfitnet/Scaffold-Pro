'use strict';

// Clients & Sites: clients down the left, sites down the right, and a
// curved line from a client to each site it has had a project at (thicker
// for more projects). The sites are ordered to keep the lines from
// crossing where they can.
//
//   • hover a client or site to light up its lines and the other side;
//     click to keep them lit (click again, or on the background, to clear)
//   • click a line: its project — or a menu of them, and "New Project"
//   • drag a client's dot onto a site (or a site's onto a client) to start
//     a new project for the two
//   • ✎ or double-click a card for its details (the client / site sheet)

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const PENCIL = '<svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13.5 3.5a1.8 1.8 0 0 1 2.5 2.5L7 15l-3.5 1 1-3.5z"/></svg>';
  const $ = (id) => document.getElementById(id);

  let clients = [];
  let sites = [];
  let projects = [];
  let pinned = null; // { kind, id }
  let links = [];    // { clientId, siteId, projects: [] }

  // A calm colour per client, so its lines can be told apart.
  function hue(text) {
    let h = 0;
    for (const ch of String(text)) h = (h * 31 + ch.charCodeAt(0)) % 360;
    return h;
  }
  const lineColor = (c) => `hsl(${hue(c.companyName)} 42% 56%)`;

  const clientSheet = initPartyPage({
    prefix: 'c-', kind: 'clients', api: window.api.clients,
    fields: ['companyName', 'clientReference', 'contactPerson', 'phone', 'email', 'address', 'addressLine2', 'addressLine3', 'city', 'postalCode', 'country', 'defaultMarkupPercent', 'billingInfo', 'notes'],
    newTitle: 'New Client', titleOf: (c) => c.companyName, requiredMessage: 'Company name is required.',
    params: { id: 'id', new: 'new' },
    onChange: (all) => { clients = all; draw(); },
  });
  const siteSheet = initPartyPage({
    prefix: 's-', kind: 'sites', api: window.api.sites,
    fields: ['name', 'siteReference', 'contactPerson', 'phone', 'email', 'address', 'city', 'postalCode', 'country', 'notes'],
    newTitle: 'New Site', titleOf: (s) => s.name, requiredMessage: 'Site name is required.',
    params: { id: 'site', new: 'newSite' },
    onChange: (all) => { sites = all; draw(); },
  });

  function buildLinks() {
    const map = new Map();
    for (const p of projects) {
      if (!p.clientId || !p.siteId) continue;
      const k = `${p.clientId}|${p.siteId}`;
      if (!map.has(k)) map.set(k, { clientId: p.clientId, siteId: p.siteId, projects: [] });
      map.get(k).projects.push(p);
    }
    links = [...map.values()];
  }

  const matches = (text) => {
    const q = $('search-box').value.trim().toLowerCase();
    return !q || text.toLowerCase().includes(q);
  };

  function draw() {
    buildLinks();
    const q = $('search-box').value.trim();
    const shownClients = clients.filter((c) => matches([c.companyName, c.clientReference, c.contactPerson, c.phone, c.email, c.city].join(' ')))
      .sort((a, b) => a.companyName.localeCompare(b.companyName));
    // A search also shows the other side of what it finds.
    let shownSites = sites.filter((s) => matches([s.name, s.siteReference, s.address, s.city, s.contactPerson].join(' ')));
    if (q) {
      // Only what the search itself found brings in its other side.
      const cIds = new Set(shownClients.map((c) => c.id));
      const sIds = new Set(shownSites.map((s) => s.id));
      const addSites = new Set(links.filter((l) => cIds.has(l.clientId) && !sIds.has(l.siteId)).map((l) => l.siteId));
      const addClients = new Set(links.filter((l) => sIds.has(l.siteId) && !cIds.has(l.clientId)).map((l) => l.clientId));
      shownSites = shownSites.concat(sites.filter((s) => addSites.has(s.id)));
      shownClients.push(...clients.filter((c) => addClients.has(c.id)));
    }
    // Sites under the clients they're joined to (the average place of
    // their clients), so the lines cross as little as possible.
    const place = new Map(shownClients.map((c, i) => [c.id, i]));
    const rank = (s) => {
      const ps = links.filter((l) => l.siteId === s.id && place.has(l.clientId)).map((l) => place.get(l.clientId));
      return ps.length ? ps.reduce((a, b) => a + b, 0) / ps.length : Infinity;
    };
    shownSites = shownSites.map((s) => [s, rank(s)]).sort((a, b) => (a[1] - b[1]) || a[0].name.localeCompare(b[0].name)).map((x) => x[0]);

    const empty = !clients.length && !sites.length;
    $('conn-board').classList.toggle('hidden', empty);
    $('list-container').innerHTML = empty ? `<div class="empty-state"><h2>No clients or sites yet</h2><p>Add the companies you work for and the sites you work at — then a project joins them.</p>
      <button class="primary" id="empty-new-client">+ New Client</button></div>` : '';
    if (empty) { $('empty-new-client').addEventListener('click', () => clientSheet.openNew()); return; }

    const count = (kind, id) => {
      const ls = links.filter((l) => (kind === 'client' ? l.clientId : l.siteId) === id);
      return { other: ls.length, projects: ls.reduce((n, l) => n + l.projects.length, 0) };
    };
    const card = (kind, r) => {
      const n = count(kind, r.id);
      const title = kind === 'client' ? r.companyName : r.name;
      const sub = kind === 'client'
        ? [r.contactPerson, r.phone].filter(Boolean).join(' · ')
        : [r.siteReference, r.address].filter(Boolean).join(' · ');
      const meta = n.projects ? `${n.other} ${kind === 'client' ? 'site' : 'client'}${n.other === 1 ? '' : 's'} · ${n.projects} project${n.projects === 1 ? '' : 's'}` : 'No projects yet';
      return `<div class="conn-card ${kind}${r.isArchived ? ' archived' : ''}" data-kind="${kind}" data-id="${esc(r.id)}" tabindex="0"${kind === 'client' ? ` style="--line:${lineColor(r)}"` : ''}>
        <span class="conn-port" title="Drag onto a ${kind === 'client' ? 'site' : 'client'} to start a project for the two"></span>
        <div class="conn-card-body">
          <div class="conn-title">${esc(title)}${r.isArchived ? ' <span class="status-pill">Archived</span>' : ''}</div>
          ${sub ? `<div class="conn-sub">${esc(sub)}</div>` : ''}
          <div class="conn-meta">${meta}</div>
        </div>
        <button type="button" class="conn-edit" data-no-icon title="Details" aria-label="Details">${PENCIL}</button>
      </div>`;
    };
    $('conn-clients').innerHTML = `<div class="conn-col-head"><span>Clients</span><span class="conn-count">${shownClients.length}</span></div>
      ${shownClients.map((c) => card('client', c)).join('') || '<div class="conn-none">No clients match.</div>'}`;
    $('conn-sites').innerHTML = `<div class="conn-col-head"><span>Sites</span><span class="conn-count">${shownSites.length}</span></div>
      ${shownSites.map((s) => card('site', s)).join('') || '<div class="conn-none">No sites match.</div>'}`;
    wireCards();
    drawLines();
    applyFocus(pinned);
  }

  // The lines, from each client's right edge to its sites' left edges.
  function drawLines() {
    const board = $('conn-board');
    const svg = $('conn-lines');
    const b = board.getBoundingClientRect();
    svg.setAttribute('width', b.width);
    svg.setAttribute('height', board.scrollHeight);
    svg.setAttribute('viewBox', `0 0 ${b.width} ${board.scrollHeight}`);
    const at = (kind, id) => board.querySelector(`.conn-card[data-kind="${kind}"][data-id="${CSS.escape(id)}"]`);
    let paths = '';
    for (const l of links) {
      const c = at('client', l.clientId);
      const s = at('site', l.siteId);
      if (!c || !s) continue;
      const cr = c.getBoundingClientRect();
      const sr = s.getBoundingClientRect();
      const x1 = cr.right - b.left, y1 = cr.top + cr.height / 2 - b.top;
      const x2 = sr.left - b.left, y2 = sr.top + sr.height / 2 - b.top;
      const dx = Math.max(40, (x2 - x1) * 0.5);
      const d = `M ${x1} ${y1} C ${x1 + dx} ${y1}, ${x2 - dx} ${y2}, ${x2} ${y2}`;
      const w = Math.min(5, 1.6 + (l.projects.length - 1) * 0.9);
      const client = clients.find((x) => x.id === l.clientId);
      const label = `${l.projects.length} project${l.projects.length === 1 ? '' : 's'}: ${l.projects.map((p) => `${p.projectNumber} ${p.name}`).join(', ')}`;
      paths += `<g class="conn-link" data-client="${esc(l.clientId)}" data-site="${esc(l.siteId)}" style="--line:${client ? lineColor(client) : 'var(--accent)'}">
        <path class="conn-hit" d="${d}"><title>${esc(label)}</title></path>
        <path class="conn-path" d="${d}" stroke-width="${w}"/>
        <circle class="conn-end" cx="${x1}" cy="${y1}" r="3.2"/><circle class="conn-end" cx="${x2}" cy="${y2}" r="3.2"/></g>`;
    }
    svg.innerHTML = `${paths}<path class="conn-drag hidden" id="conn-drag"/>`;
    for (const g of svg.querySelectorAll('.conn-link')) {
      g.addEventListener('mouseenter', () => { if (!pinned) applyFocus({ link: g }); });
      g.addEventListener('mouseleave', () => { if (!pinned) applyFocus(null); });
      g.addEventListener('click', (e) => openLink(e, g.dataset.client, g.dataset.site));
    }
  }

  // Lights up a card's lines and the cards on their other ends.
  function applyFocus(focus) {
    const board = $('conn-board');
    for (const el of board.querySelectorAll('.lit, .chosen')) el.classList.remove('lit', 'chosen');
    board.classList.toggle('focusing', !!focus);
    if (!focus) return;
    const lit = (kind, id) => { const el = board.querySelector(`.conn-card[data-kind="${kind}"][data-id="${CSS.escape(id)}"]`); if (el) el.classList.add('lit'); };
    if (focus.link) {
      focus.link.classList.add('lit');
      lit('client', focus.link.dataset.client);
      lit('site', focus.link.dataset.site);
      return;
    }
    const key = focus.kind === 'client' ? 'client' : 'site';
    const card = board.querySelector(`.conn-card[data-kind="${focus.kind}"][data-id="${CSS.escape(focus.id)}"]`);
    if (card) card.classList.add('lit', 'chosen');
    for (const g of board.querySelectorAll(`.conn-link[data-${key}="${CSS.escape(focus.id)}"]`)) {
      g.classList.add('lit');
      lit(focus.kind === 'client' ? 'site' : 'client', focus.kind === 'client' ? g.dataset.site : g.dataset.client);
    }
  }

  function startProject(clientId, siteId) {
    window.goTo(`projects.html?new=1&client=${encodeURIComponent(clientId)}&site=${encodeURIComponent(siteId)}`);
  }

  function openLink(e, clientId, siteId) {
    const l = links.find((x) => x.clientId === clientId && x.siteId === siteId);
    if (!l) return;
    const go = (p) => { window.goTo(`project-detail.html?number=${encodeURIComponent(p.projectNumber)}`); };
    if (l.projects.length === 1 && !e.altKey) { go(l.projects[0]); return; }
    window.showContextMenu(e, l.projects.map((p) => ({ label: `${p.projectNumber} — ${p.name}${p.status ? ` (${p.status})` : ''}`, action: () => go(p) }))
      .concat(['separator', { label: 'New Project for These Two…', action: () => startProject(clientId, siteId) }]));
  }

  function wireCards() {
    for (const card of document.querySelectorAll('.conn-card')) {
      const { kind, id } = card.dataset;
      const record = () => (kind === 'client' ? clients : sites).find((r) => r.id === id);
      const sheet = kind === 'client' ? clientSheet : siteSheet;
      card.addEventListener('mouseenter', () => { if (!pinned) applyFocus({ kind, id }); });
      card.addEventListener('mouseleave', () => { if (!pinned) applyFocus(null); });
      card.addEventListener('click', (e) => {
        if (e.target.closest('.conn-edit, .conn-port')) return;
        pinned = pinned && pinned.kind === kind && pinned.id === id ? null : { kind, id };
        applyFocus(pinned || { kind, id });
      });
      card.addEventListener('dblclick', (e) => { if (!e.target.closest('.conn-port')) sheet.open(record()); });
      card.addEventListener('keydown', (e) => { if (e.key === 'Enter') sheet.open(record()); });
      card.querySelector('.conn-edit').addEventListener('click', () => sheet.open(record()));
      card.querySelector('.conn-port').addEventListener('pointerdown', (e) => startConnect(e, card));
    }
  }

  // Drag from a dot: a line follows the pointer; let go on a card of the
  // other kind to start a project for the two.
  function startConnect(e, from) {
    e.preventDefault();
    e.stopPropagation();
    const board = $('conn-board');
    const path = $('conn-drag');
    const other = from.dataset.kind === 'client' ? 'site' : 'client';
    board.classList.add('connecting', `connecting-to-${other}`);
    const b0 = () => board.getBoundingClientRect();
    const fr = from.getBoundingClientRect();
    let target = null;
    const move = (ev) => {
      const b = b0();
      const x1 = (from.dataset.kind === 'client' ? fr.right : fr.left) - b.left;
      const y1 = fr.top + fr.height / 2 - b.top;
      const x2 = ev.clientX - b.left, y2 = ev.clientY - b.top;
      const dx = (x2 - x1) * 0.5;
      path.setAttribute('d', `M ${x1} ${y1} C ${x1 + dx} ${y1}, ${x2 - dx} ${y2}, ${x2} ${y2}`);
      path.classList.remove('hidden');
      const over = document.elementFromPoint(ev.clientX, ev.clientY);
      const card = over && over.closest(`.conn-card[data-kind="${other}"]`);
      if (target && target !== card) target.classList.remove('drop-target');
      target = card;
      if (target) target.classList.add('drop-target');
    };
    const up = async (ev) => {
      document.removeEventListener('pointermove', move);
      document.removeEventListener('pointerup', up);
      document.removeEventListener('pointercancel', up);
      board.classList.remove('connecting', `connecting-to-${other}`);
      path.classList.add('hidden');
      if (target && ev && ev.type === 'pointercancel') { target.classList.remove('drop-target'); return; }
      if (!target) return;
      target.classList.remove('drop-target');
      const clientId = from.dataset.kind === 'client' ? from.dataset.id : target.dataset.id;
      const siteId = from.dataset.kind === 'site' ? from.dataset.id : target.dataset.id;
      const c = clients.find((x) => x.id === clientId);
      const s = sites.find((x) => x.id === siteId);
      if (await window.appConfirm(`Start a new project for ${c ? c.companyName : 'this client'} at ${s ? s.name : 'this site'}?`, { ok: 'New Project' })) startProject(clientId, siteId);
    };
    document.addEventListener('pointermove', move);
    document.addEventListener('pointerup', up);
    document.addEventListener('pointercancel', up);
    move(e);
  }

  async function chooseKind(verb) {
    return window.appChoose(`${verb} which list?`, [{ label: 'Sites', value: 'sites' }, { label: 'Clients', value: 'clients', primary: true }]);
  }

  $('new-client-btn').addEventListener('click', () => clientSheet.openNew());
  $('new-site-btn').addEventListener('click', () => siteSheet.openNew());
  $('import-xlsx-btn').addEventListener('click', async () => {
    const k = await chooseKind('Import into');
    if (k) await (k === 'sites' ? siteSheet : clientSheet).importExcel();
  });
  $('export-xlsx-btn').addEventListener('click', async () => {
    const k = await chooseKind('Export');
    if (k) await (k === 'sites' ? siteSheet : clientSheet).exportExcel();
  });
  $('search-box').addEventListener('input', draw);
  $('show-archived').addEventListener('change', async () => { await Promise.all([clientSheet.refresh(), siteSheet.refresh()]); });
  $('conn-board').addEventListener('click', (e) => {
    if (!e.target.closest('.conn-card, .conn-link')) { pinned = null; applyFocus(null); }
  });
  new ResizeObserver(() => drawLines()).observe($('conn-board'));
  window.addEventListener('resize', () => drawLines());

  (async () => {
    projects = (await window.api.projects.list()) || [];
    await window.loadPersonColors?.();
    draw();
  })();
})();

'use strict';

// The Team page: People (everyone, their team and title, the devices they
// use ScaffoldPro on, and who signs), Signatures (quotations waiting for a
// director to sign and chop) and Announcements.

const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
const MAC = '<svg viewBox="0 0 20 20" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="3" y="4" width="14" height="9.5" rx="1.2"/><path d="M1.5 16h17"/></svg>';
const PEN = '<svg viewBox="0 0 20 20" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 15.5c2-1 3.5-4 5-4s0 3 1.5 3 3-5 4.5-5 1 2.5 3 2.5"/><path d="M3 17.5h14"/></svg>';

const EDIT = '<svg viewBox="0 0 20 20" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13.5 3.5a1.8 1.8 0 0 1 2.5 2.5L7 15l-3.5 1 1-3.5z"/></svg>';

let team = null;
let signing = null;
let editingPerson = null;

function when(iso) {
  const d = new Date(iso);
  if (isNaN(d)) return '';
  const mins = Math.round((Date.now() - d.getTime()) / 60000);
  if (mins < 2) return 'just now';
  if (mins < 60) return `${mins} min ago`;
  if (mins < 60 * 24) return `${Math.round(mins / 60)} h ago`;
  return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
}

function initials(name) {
  return String(name).trim().split(/\s+/).map((w) => w[0]).slice(0, 2).join('').toUpperCase();
}

function showTab(name) {
  for (const b of document.querySelectorAll('#team-tabs button')) b.classList.toggle('active', b.dataset.tab === name);
  for (const p of document.querySelectorAll('.tab-panel')) p.classList.toggle('active', p.dataset.panel === name);
  try { sessionStorage.setItem('team-tab', name); } catch (e) { /* ignore */ }
}

// ---- People ----

function renderPeople() {
  const grid = document.getElementById('people-grid');
  document.getElementById('count-people').textContent = team.people.length || '';
  if (!team.people.length) {
    grid.innerHTML = '<div class="empty-state"><h2>No one yet</h2><p>Enter your name on the User page; everyone sharing the data folder shows here with their Macs.</p></div>';
    return;
  }
  grid.innerHTML = team.people.map((p) => {
    const colour = window.personColor ? window.personColor(p.name) : '#8a8f98';
    const devices = p.devices.length
      ? p.devices.map((d) => `<div class="device${d.outdated ? ' outdated' : ''}">${MAC}<span class="device-name">${esc(d.computer)}</span>
          <span class="device-seen">${d.isThisMac ? 'this Mac' : `seen ${esc(when(d.lastSeen))}`}${d.outdated ? ' · needs updating' : ''}</span></div>`).join('')
      : '<div class="device none">No devices yet</div>';
    const facts = [p.position, p.employeeNumber, p.phone].filter(Boolean).map(esc).join(' · ');
    return `<article class="person-card${p.isMe ? ' me' : ''}" data-name="${esc(p.name)}">
      <div class="person-head">
        <span class="person-avatar" style="background:${colour}">${esc(initials(p.name))}</span>
        <div class="person-id">
          <div class="person-name">${esc(p.name)}${p.isMe ? ' <span class="you-pill">You</span>' : ''}</div>
          <div class="person-role">${esc([p.title, p.team && `${p.team} team`].filter(Boolean).join(' · ') || 'No team yet')}</div>
        </div>
        <button class="person-edit" data-no-icon title="Team, title, signing" aria-label="Edit">${EDIT}</button>
      </div>
      ${p.canSign ? `<div class="signer-pill">${PEN} Signs &amp; chops quotations${p.isMe ? (p.hasSignature ? '' : ' — <b>add your signature</b>') : ''}</div>` : ''}
      ${facts ? `<div class="person-facts">${facts}</div>` : ''}
      <div class="person-devices">${devices}</div>
    </article>`;
  }).join('');
  for (const card of grid.querySelectorAll('.person-card')) {
    card.querySelector('.person-edit').addEventListener('click', () => openPerson(team.people.find((p) => p.name === card.dataset.name)));
  }
}

async function preview(which) {
  const r = await window.api.signatures.image(which);
  const box = document.getElementById(which === 'chop' ? 'pm-chop-preview' : 'pm-sig-preview');
  box.innerHTML = r && r.dataURL ? `<img src="${r.dataURL}" alt="" />` : `<span>${which === 'chop' ? 'No chop yet' : 'No signature yet'}</span>`;
}

function openPerson(p) {
  editingPerson = p;
  document.getElementById('pm-title').textContent = p.name;
  document.getElementById('pm-team').value = p.team || '';
  document.getElementById('pm-title-input').value = p.title || '';
  document.getElementById('pm-cansign').checked = !!p.canSign;
  document.getElementById('pm-teams').innerHTML = (team.teams || []).map((t) => `<option value="${esc(t)}"></option>`).join('');
  document.getElementById('pm-images').classList.toggle('hidden', !p.isMe);
  document.getElementById('pm-error').classList.add('hidden');
  if (p.isMe) { preview('signature'); preview('chop'); }
  document.getElementById('person-modal').classList.remove('hidden');
}

async function savePerson() {
  const r = await window.api.team.setPerson({
    name: editingPerson.name,
    team: document.getElementById('pm-team').value.trim(),
    title: document.getElementById('pm-title-input').value.trim(),
    canSign: document.getElementById('pm-cansign').checked,
  });
  if (r && r.ok === false) {
    document.getElementById('pm-error').textContent = r.error;
    document.getElementById('pm-error').classList.remove('hidden');
    return;
  }
  document.getElementById('person-modal').classList.add('hidden');
  await load();
}

// ---- Signatures ----

const STATUS_PILL = { Pending: 'pill-warning', Signed: 'pill-success', Declined: 'pill-danger' };

function requestRow(r, opts = {}) {
  return `<div class="sign-row" data-id="${esc(r.id)}">
    <div class="sign-main">
      <div><a href="quotation-editor.html?id=${encodeURIComponent(r.documentId)}"><strong>${esc(r.number)}</strong></a>
        <span class="status-pill ${STATUS_PILL[r.status] || ''}">${esc(r.status === 'Signed' ? 'Signed & chopped' : r.status)}</span></div>
      <div class="sub">${esc(r.projectNumber)} ${esc(r.projectName || '')}</div>
      <div class="sub">${opts.incoming ? `From ${window.personTag(r.requestedBy)}` : `${window.personTag(r.requestedBy)} → ${window.personTag(r.signer)}`} · ${esc(when(r.createdAt))}${r.decidedAt ? ` · ${r.status.toLowerCase()} ${esc(when(r.decidedAt))}` : ''}</div>
      ${r.note ? `<div class="sign-note">“${esc(r.note)}”</div>` : ''}
      ${r.reply ? `<div class="sign-note reply">${esc(r.signer)}: “${esc(r.reply)}”</div>` : ''}
    </div>
    <div class="sign-actions">
      ${opts.incoming ? `<a class="button-like" href="quotation-editor.html?id=${encodeURIComponent(r.documentId)}">Review</a>
        <button class="sign-decline" data-no-icon>Decline…</button><button class="primary sign-go" data-no-icon>${PEN} Sign &amp; Chop</button>` : ''}
      ${!opts.incoming && r.status === 'Pending' && opts.mine ? '<button class="sign-withdraw" data-no-icon>Withdraw</button>' : ''}
      ${r.status === 'Signed' && r.filePath ? '<button class="sign-open" data-no-icon>Open Signed PDF</button>' : ''}
    </div>
  </div>`;
}

function section(title, rows, empty, opts) {
  return `<section class="panel sign-section"><h3 class="panel-title">${title}</h3>${rows.length ? rows.map((r) => requestRow(r, opts)).join('') : `<div class="empty-inline">${empty}</div>`}</section>`;
}

function renderSignatures() {
  const s = signing;
  document.getElementById('count-signatures').textContent = s.incoming.length || '';
  document.getElementById('sign-incoming').innerHTML = s.canSign || s.incoming.length
    ? section('Waiting for you to sign', s.incoming, 'Nothing waiting for your signature.', { incoming: true }) : '';
  document.getElementById('sign-outgoing').innerHTML = section('You asked', s.outgoing.slice(0, 20), s.signers.length
    ? 'Open a quotation and press “Send to Sign…” to ask a director to sign and chop it.'
    : 'No one signs quotations yet — mark the directors on the People tab (✎ › Signs and chops quotations).', { mine: true });
  const known = new Set(s.incoming.concat(s.outgoing).map((r) => r.id));
  const others = s.recent.filter((r) => !known.has(r.id));
  document.getElementById('sign-recent').innerHTML = others.length ? section('Everyone’s', others.slice(0, 30), '', {}) : '';
  for (const row of document.querySelectorAll('.sign-row')) {
    const r = s.recent.concat(s.incoming, s.outgoing).find((x) => x.id === row.dataset.id);
    const on = (sel, fn) => { const b = row.querySelector(sel); if (b) b.addEventListener('click', fn); };
    on('.sign-go', async () => {
      if (!await window.appConfirm(`Sign and chop ${r.number}?\n\nYour signature and the company chop go on its “For and on Behalf of” line. The signed PDF is saved in project ${r.projectNumber}’s Quotations folder, and ${r.requestedBy} is told.`, { ok: 'Sign & Chop' })) return;
      const res = await window.api.signatures.sign(r.id);
      if (!res || res.ok === false) { await window.appAlert((res && res.error) || 'It couldn’t be signed.'); return; }
      await load();
      if (await window.appConfirm(`${r.number} is signed and chopped.`, { ok: 'Open PDF', cancel: 'Done' })) window.api.signatures.openFile(res.path);
    });
    on('.sign-decline', async () => {
      const reply = await window.appPrompt(`Why not sign ${r.number}? (${r.requestedBy} is told)`, '', { ok: 'Decline', placeholder: 'e.g. Please check the delivery charge first' });
      if (reply === null) return;
      const res = await window.api.signatures.decline(r.id, reply);
      if (res && res.ok === false) { await window.appAlert(res.error); return; }
      await load();
    });
    on('.sign-withdraw', async () => {
      if (!await window.appConfirm(`Withdraw the request for ${r.signer} to sign ${r.number}?`, { ok: 'Withdraw' })) return;
      const res = await window.api.signatures.withdraw(r.id);
      if (res && res.ok === false) { await window.appAlert(res.error); return; }
      await load();
    });
    on('.sign-open', async () => {
      const res = await window.api.signatures.openFile(r.filePath);
      if (res && res.ok === false) await window.appAlert(res.error);
    });
  }
}

// ---- Announcements ----

async function renderAnnouncements() {
  const page = await window.api.announcements.page();
  const rows = (page && page.visible) || [];
  const mine = (page && page.mine) || [];
  document.getElementById('count-announcements').textContent = rows.length || '';
  const box = document.getElementById('team-announcements');
  box.innerHTML = `<div class="announce-bar" id="team-announce-bar"></div>
    ${rows.length ? '' : '<div class="empty-state"><h2>No announcements</h2><p>Press Announce to tell everyone, or your team, something. It shows at the top of their Dashboard.</p></div>'}
    ${mine.length ? `<p class="small-note">You have ${mine.length} announcement${mine.length === 1 ? '' : 's'} showing — take one down from its bar or from Announce.</p>` : ''}`;
  window.announcements.render(document.getElementById('team-announce-bar'));
}

async function load() {
  [team, signing] = await Promise.all([window.api.team.page(), window.api.signatures.page()]);
  await window.loadPersonColors();
  renderPeople();
  renderSignatures();
  renderAnnouncements();
}

(function init() {
  for (const b of document.querySelectorAll('#team-tabs button')) b.addEventListener('click', () => showTab(b.dataset.tab));
  const q = new URLSearchParams(location.search).get('tab');
  let saved = null;
  try { saved = sessionStorage.getItem('team-tab'); } catch (e) { /* ignore */ }
  showTab(q || saved || 'people');
  document.getElementById('pm-cancel').addEventListener('click', () => document.getElementById('person-modal').classList.add('hidden'));
  document.getElementById('pm-save').addEventListener('click', savePerson);
  document.getElementById('person-modal').addEventListener('keydown', (e) => { if (e.key === 'Escape') document.getElementById('person-modal').classList.add('hidden'); });
  for (const slot of document.querySelectorAll('.sig-slot')) {
    const which = slot.dataset.which;
    slot.querySelector('.sig-choose').addEventListener('click', async () => {
      const r = await window.api.signatures.chooseImage(which);
      if (r && r.ok === false) { await window.appAlert(r.error); return; }
      await preview(which);
    });
    slot.querySelector('.sig-remove').addEventListener('click', async () => {
      await window.api.signatures.removeImage(which);
      await preview(which);
    });
  }
  document.getElementById('team-announce-btn').addEventListener('click', async () => { await window.announcements.compose(); renderAnnouncements(); });
  load();
  // Requests come in from the others' Macs.
  setInterval(async () => { signing = await window.api.signatures.page(); renderSignatures(); }, 60000);
})();

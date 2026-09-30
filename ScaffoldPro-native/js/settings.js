'use strict';

const SETTINGS_FIELDS = [
  'companyName', 'website', 'addressLine1', 'addressLine2', 'phone', 'email',
  'registrationNumber', 'bankDetails', 'currency',
  'defaultPaymentTerms', 'defaultNotes',
];

const NUMBER_FIELDS = ['numberFormatBOQ', 'numberFormatQuotation', 'numberFormatInvoice', 'numberFormatDeliveryNote'];
const QUOTE_TEXT_FIELDS = ['signatoryName', 'signatoryTitle', 'termsURL', 'quotationTerms', 'quotationAcceptance'];
const START_KEYS = ['BOQ', 'QT', 'INV', 'DN'];
// As on the company's quotations; Settings can change them.
const DEFAULT_MANPOWER_RATES = [
  { name: 'Scaffolder CP', rate: 2300, unit: 'md' },
  { name: 'Scaffolder', rate: 2100, unit: 'md' },
  { name: 'Rigger', rate: 2000, unit: 'md' },
  { name: 'General Helper', rate: 1800, unit: 'md' },
];

function escAttr(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;');
}

// Four rows (a blank name leaves that worker out).
function renderManpowerRates(rates) {
  const list = (rates && rates.length ? rates : DEFAULT_MANPOWER_RATES).slice(0, 4);
  while (list.length < 4) list.push({ name: '', rate: '', unit: 'md' });
  document.getElementById('manpower-rates-body').innerHTML = list.map((r, i) => `
    <tr>
      <td><input type="text" id="mr-name-${i}" value="${escAttr(r.name)}" placeholder="Worker" /></td>
      <td class="num"><input type="number" id="mr-rate-${i}" min="0" step="0.01" value="${escAttr(r.rate)}" /></td>
      <td><input type="text" id="mr-unit-${i}" value="${escAttr(r.unit || 'md')}" style="width:60px" /></td>
    </tr>`).join('');
}

function readManpowerRates() {
  const out = [];
  for (let i = 0; i < 4; i++) {
    const name = document.getElementById(`mr-name-${i}`).value.trim();
    if (!name) continue;
    out.push({ name, rate: Number(document.getElementById(`mr-rate-${i}`).value) || 0, unit: document.getElementById(`mr-unit-${i}`).value.trim() || 'md' });
  }
  return out;
}
let currentAppearance = 'System';

// ---------- BOQ Defaults: materials every new BOQ starts with ----------

let defaultBOQItems = []; // [{ priceListItemId, quantity }]
const materialCache = {}; // sourceKey → items

async function materials(sourceKey) {
  if (!materialCache[sourceKey]) materialCache[sourceKey] = await window.api.priceLists.searchItems({ sourceKey: sourceKey });
  return materialCache[sourceKey];
}

async function allMaterials() {
  const [sp, scafom] = await Promise.all([materials('SP'), materials('SCAFOM')]);
  return new Map(sp.concat(scafom).map((i) => [i.id, i]));
}

// The item list of the chosen material list, a group per category.
async function populateDefaultItemSelect() {
  const items = await materials(document.getElementById('default-item-source').value);
  const groups = new Map();
  for (const i of items) {
    const c = i.category || 'Other Items';
    if (!groups.has(c)) groups.set(c, []);
    groups.get(c).push(i);
  }
  const byCode = (a, b) => String(a).localeCompare(String(b), undefined, { numeric: true });
  const ordered = [...groups].sort((a, b) => byCode(a[1][0].itemCode, b[1][0].itemCode));
  document.getElementById('default-item-select').innerHTML = ordered.map(([c, list]) =>
    `<optgroup label="${escAttr(c)}">${list.map((i) => `<option value="${escAttr(i.id)}">${escAttr(i.itemName)}</option>`).join('')}</optgroup>`).join('');
}

async function renderDefaultItems() {
  const box = document.getElementById('default-items-list');
  if (defaultBOQItems.length === 0) {
    box.innerHTML = '<p class="small-note">No default items: new BOQs start empty.</p>';
    return;
  }
  const byId = await allMaterials();
  box.innerHTML = `<table class="compact default-items-table">
    <thead><tr><th>Item</th><th>Category</th><th>List</th><th class="num">Qty</th><th></th></tr></thead>
    <tbody>${defaultBOQItems.map((d, i) => {
      const item = byId.get(d.priceListItemId);
      return `<tr>
        <td>${item ? escAttr(item.itemName) : '<span class="status-pill pill-danger">No longer on the material list — skipped</span>'}</td>
        <td class="muted">${item ? escAttr(item.category || '') : ''}</td>
        <td class="muted">${item ? escAttr(item.sourceKey) : ''}</td>
        <td class="num"><input type="number" class="default-item-qty" data-index="${i}" min="1" step="1" value="${escAttr(d.quantity)}" /></td>
        <td class="row-actions"><button class="default-item-remove" data-index="${i}">Remove</button></td>
      </tr>`;
    }).join('')}</tbody></table>`;
  for (const input of box.querySelectorAll('.default-item-qty')) {
    input.addEventListener('change', () => {
      defaultBOQItems[Number(input.dataset.index)].quantity = Math.max(1, Math.round(Number(input.value) || 1));
      input.value = defaultBOQItems[Number(input.dataset.index)].quantity;
    });
  }
  for (const b of box.querySelectorAll('.default-item-remove')) {
    b.addEventListener('click', async () => {
      defaultBOQItems.splice(Number(b.dataset.index), 1);
      settingsDirty = true;
      await renderDefaultItems();
    });
  }
}

function readDefaultItems() {
  return defaultBOQItems.map((d) => ({ priceListItemId: d.priceListItemId, quantity: Math.max(1, Math.round(Number(d.quantity) || 1)) }));
}

async function setupDefaultItems() {
  await populateDefaultItemSelect();
  document.getElementById('default-item-source').addEventListener('change', populateDefaultItemSelect);
  document.getElementById('default-item-add-btn').addEventListener('click', async () => {
    const id = document.getElementById('default-item-select').value;
    if (!id) return;
    const qtyBox = document.getElementById('default-item-qty');
    const quantity = Math.max(1, Math.round(Number(qtyBox.value) || 1));
    const existing = defaultBOQItems.find((d) => d.priceListItemId === id);
    if (existing) existing.quantity = quantity;
    else defaultBOQItems.push({ priceListItemId: id, quantity: quantity });
    qtyBox.value = 1;
    settingsDirty = true;
    await renderDefaultItems();
  });
}

async function loadSettings() {
  const settings = await window.api.settings.get();
  for (const field of SETTINGS_FIELDS.concat(NUMBER_FIELDS, ['paperSize', 'defaultInvoiceDueDays'])) {
    const el = document.getElementById(`${field}-input`);
    if (!el) continue;
    el.value = settings[field] === null || settings[field] === undefined ? '' : settings[field];
  }
  if (!settings.paperSize) document.getElementById('paperSize-input').value = 'A4';
  for (const f of QUOTE_TEXT_FIELDS) document.getElementById(`${f}-input`).value = settings[f] || '';
  document.getElementById('standardDeliveryCharge-input').value = settings.standardDeliveryCharge ?? '';
  document.getElementById('defaultMinimumHireMonths-input').value = settings.defaultMinimumHireMonths ?? 2;
  document.getElementById('termsNewPage-input').value = settings.termsNewPage === 'Always' ? 'Always' : 'WhenLong';
  document.getElementById('markupRounding-input').value = settings.markupRoundUp ? 'Up' : 'Nearest';
  renderManpowerRates(settings.manpowerRates);
  document.getElementById('eurRate-input').value = (settings.exchangeRates && settings.exchangeRates.EUR) || 8.93;
  for (const k of START_KEYS) {
    document.getElementById(`start-${k}`).value = (settings.numberStarts && settings.numberStarts[k]) || '';
  }
  if (settings.defaultInvoiceDueDays == null) document.getElementById('defaultInvoiceDueDays-input').value = 30;
  defaultBOQItems = (settings.defaultBOQItems || []).map((d) => ({ priceListItemId: d.priceListItemId, quantity: d.quantity }));
  await renderDefaultItems();
  setAppearanceButtons(settings.appearance || 'System');
  for (const f of NUMBER_FIELDS) updateNumberExample(f);
}

async function saveSettings() {
  const payload = {};
  for (const field of SETTINGS_FIELDS) {
    const el = document.getElementById(`${field}-input`);
    if (!el) continue;
    payload[field] = el.value || null;
  }
  for (const f of NUMBER_FIELDS) {
    const v = document.getElementById(`${f}-input`).value.trim();
    if (v && !v.includes('{SEQ}')) {
      alert('Each document number format needs {SEQ} somewhere, so every number is different.');
      document.getElementById(`${f}-input`).focus();
      return;
    }
    payload[f] = v;
  }
  for (const f of QUOTE_TEXT_FIELDS) payload[f] = document.getElementById(`${f}-input`).value;
  const delivery = document.getElementById('standardDeliveryCharge-input').value;
  payload.standardDeliveryCharge = delivery === '' ? null : Number(delivery);
  payload.termsNewPage = document.getElementById('termsNewPage-input').value;
  payload.markupRounding = document.getElementById('markupRounding-input').value;
  payload.manpowerRates = readManpowerRates();
  payload.defaultMinimumHireMonths = Math.max(1, Math.round(Number(document.getElementById('defaultMinimumHireMonths-input').value) || 2));
  const eur = Number(document.getElementById('eurRate-input').value);
  if (eur > 0) payload.exchangeRates = { EUR: eur };
  payload.numberStarts = {};
  for (const k of START_KEYS) {
    const v = Math.round(Number(document.getElementById(`start-${k}`).value) || 0);
    if (v > 0) payload.numberStarts[k] = v;
  }
  payload.paperSize = document.getElementById('paperSize-input').value;
  payload.defaultInvoiceDueDays = Math.max(0, Math.round(Number(document.getElementById('defaultInvoiceDueDays-input').value) || 0));
  payload.defaultBOQItems = readDefaultItems();
  payload.appearance = currentAppearance;
  await window.api.settings.update(payload);
  const note = document.getElementById('saved-note');
  note.classList.remove('hidden');
  setTimeout(() => note.classList.add('hidden'), 2000);
}

// ---------- Automatic iCloud backup ----------

function timeAgo(iso) {
  const d = new Date(iso);
  if (isNaN(d)) return '';
  const minutes = Math.round((Date.now() - d.getTime()) / 60000);
  if (minutes < 1) return 'just now';
  if (minutes < 60) return `${minutes} minute${minutes === 1 ? '' : 's'} ago`;
  return formatWhen(iso);
}

function renderCloud(s) {
  if (!s) return;
  document.getElementById('cloud-enabled').checked = s.enabled;
  document.getElementById('cloud-folder').textContent = s.folderDisplay;
  document.getElementById('cloud-default-btn').classList.toggle('hidden', s.usingDefault);
  document.getElementById('cloud-now-btn').disabled = !s.enabled || s.running;
  const status = document.getElementById('cloud-status');
  let text;
  if (!s.enabled) text = 'Off';
  else if (s.running) text = 'Backing up…';
  else if (s.lastError) text = s.lastError;
  else if (s.lastBackupAt) text = `Up to date — last backed up ${timeAgo(s.lastBackupAt)}${s.lastFilesCopied ? ` (${s.lastFilesCopied.toLocaleString('en-US')} file${s.lastFilesCopied === 1 ? '' : 's'} copied)` : ''}`;
  else text = 'Waiting for the first backup…';
  if (s.enabled && s.lastError && s.lastBackupAt) text += ` Last successful backup: ${timeAgo(s.lastBackupAt)}.`;
  status.textContent = text;
  status.classList.toggle('error', !!(s.enabled && s.lastError && !s.running));
}

async function refreshCloud() {
  renderCloud(await window.api.cloudBackup.status());
}

function setupCloudBackup() {
  document.getElementById('cloud-enabled').addEventListener('change', async (e) => {
    renderCloud(await window.api.cloudBackup.setEnabled(e.target.checked));
  });
  document.getElementById('cloud-now-btn').addEventListener('click', async () => {
    renderCloud(Object.assign(await window.api.cloudBackup.status(), { running: true }));
    renderCloud(await window.api.cloudBackup.backUpNow());
  });
  document.getElementById('cloud-choose-btn').addEventListener('click', async () => {
    renderCloud(await window.api.cloudBackup.chooseFolder());
  });
  document.getElementById('cloud-default-btn').addEventListener('click', async () => {
    renderCloud(await window.api.cloudBackup.useDefaultFolder());
  });
  document.getElementById('cloud-reveal-btn').addEventListener('click', async () => {
    const r = await window.api.cloudBackup.reveal();
    if (r && !r.ok) alert(r.error);
  });
  refreshCloud();
  // Keep the status current while Settings is open.
  setInterval(refreshCloud, 10000);
}

// ---------- Backup & Restore (Phase 14) ----------

function formatBytes(bytes) {
  const n = Number(bytes || 0);
  if (n < 1024 * 1024) return `${Math.max(1, Math.round(n / 1024)).toLocaleString('en-US')} KB`;
  if (n < 1024 * 1024 * 1024) return `${(n / (1024 * 1024)).toLocaleString('en-US', { maximumFractionDigits: 1 })} MB`;
  return `${(n / (1024 * 1024 * 1024)).toLocaleString('en-US', { maximumFractionDigits: 2 })} GB`;
}

function formatWhen(iso) {
  const d = new Date(iso);
  if (isNaN(d)) return iso;
  return d.toLocaleString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' });
}

function setBusy(busy, message) {
  for (const id of ['create-backup-btn', 'restore-other-btn']) {
    document.getElementById(id).disabled = busy;
  }
  for (const b of document.querySelectorAll('#backup-list button.restore-btn')) b.disabled = busy;
  document.getElementById('backup-status').textContent = message || '';
}

async function refreshBackups() {
  const backups = await window.api.backup.list();
  const container = document.getElementById('backup-list');
  if (backups.length === 0) {
    container.innerHTML = `<div class="empty-state"><h2>No backups yet</h2><p>Create your first backup to protect your projects and documents.</p></div>`;
    return;
  }
  const table = document.createElement('table');
  table.innerHTML = `<thead><tr><th>Date</th><th>Type</th><th class="num">Projects</th><th class="num">Files</th><th class="num">Size</th><th></th></tr></thead><tbody></tbody>`;
  const tbody = table.querySelector('tbody');
  for (const b of backups) {
    const tr = document.createElement('tr');
    const kind = b.kind === 'Before Restore' ? '<span class="kind-safety">Automatic (before restore)</span>'
      : b.kind === 'Scheduled' ? '<span class="kind-safety">Automatic (12:00)</span>' : 'Manual';
    tr.innerHTML = `
      <td>${formatWhen(b.createdAt)}</td>
      <td>${kind}</td>
      <td class="num">${Number(b.projectCount).toLocaleString('en-US')}</td>
      <td class="num">${Number(b.fileCount).toLocaleString('en-US')}</td>
      <td class="num">${formatBytes(b.totalBytes)}</td>
      <td><button class="reveal-btn" title="Show this backup in Finder">Locate File</button> <button class="restore-btn">Restore</button></td>`;
    tr.querySelector('.reveal-btn').addEventListener('click', () => window.api.backup.reveal(b.path));
    tr.querySelector('.restore-btn').addEventListener('click', () => restoreBackup(b));
    tbody.appendChild(tr);
  }
  container.innerHTML = '';
  container.appendChild(table);
}

async function createBackup() {
  setBusy(true, 'Creating backup… this can take a minute if you have many drawings.');
  const result = await window.api.backup.create();
  setBusy(false, '');
  if (!result.ok) { alert(result.error); return; }
  setBusy(false, `Backup created: ${result.backup.fileCount.toLocaleString('en-US')} files, ${formatBytes(result.backup.totalBytes)}.`);
  await refreshBackups();
}

const RESTORE_WARNING =
  'Restoring replaces ALL current data — projects, documents, price lists and settings — with the contents of the backup.\n\n' +
  'Your current data is saved first as an automatic "before restore" backup, so this can be undone.\n\nContinue?';

function afterRestore(result) {
  if (!result) { setBusy(false, ''); return; }   // folder picker cancelled
  setBusy(false, '');
  if (!result.ok) { alert(result.error); refreshBackups(); return; }
  alert(`Restore complete.\n\nYour previous data was saved as "${result.safetyBackup.name}" in case you need it back.`);
  location.href = 'index.html';
}

async function restoreBackup(backup) {
  if (!confirm(`Restore the backup from ${formatWhen(backup.createdAt)}?\n\n${RESTORE_WARNING}`)) return;
  setBusy(true, 'Restoring… please don\'t close ScaffoldPro.');
  afterRestore(await window.api.backup.restore(backup.path));
}

async function restoreFromOtherFolder() {
  if (!confirm(RESTORE_WARNING)) return;
  setBusy(true, 'Choose a backup folder…');
  afterRestore(await window.api.backup.chooseAndRestore());
}

async function loadLocations() {
  const loc = await window.api.backup.locations();
  document.getElementById('loc-documents').textContent = loc.documentsFolder;
  document.getElementById('loc-backups').textContent = loc.backupsFolder;
  document.getElementById('loc-database').textContent = loc.databaseFolder;
}

// ---------- Numbering preview, appearance ----------

async function updateNumberExample(field) {
  const input = document.getElementById(`${field}-input`);
  const example = document.getElementById(`${field}-example`);
  const r = await window.api.settings.numberPreview(input.dataset.type, input.value.trim());
  example.textContent = input.value.trim() && !input.value.includes('{SEQ}')
    ? 'Needs {SEQ}'
    : `e.g. ${r.example}`;
}

function setAppearanceButtons(value) {
  currentAppearance = value;
  for (const b of document.querySelectorAll('#appearance-control button')) {
    b.classList.toggle('active', b.dataset.value === value);
  }
}

// ---------- Sharing with other Macs (team) ----------

// Unsaved edits in the settings form (so a change from another Mac doesn't
// replace what's being typed).
let settingsDirty = false;

function whenSeen(iso) {
  const d = new Date(iso);
  if (isNaN(d)) return '';
  const minutes = Math.round((Date.now() - d.getTime()) / 60000);
  if (minutes < 10) return 'active now';
  return `last seen ${timeAgo(iso)}`;
}

function renderTeam(s) {
  if (!s) return;
  document.getElementById('team-off').classList.toggle('hidden', s.enabled);
  document.getElementById('team-on').classList.toggle('hidden', !s.enabled);
  const busy = document.getElementById('team-busy');
  if (!s.enabled) {
    busy.textContent = s.folderMissing
      ? `Sharing is set up with “${s.folderDisplay}”, but that folder can’t be found, so this Mac’s own data is open. Join it again, or check iCloud Drive.`
      : '';
    busy.classList.toggle('team-warning', !!s.folderMissing);
    return;
  }
  document.getElementById('team-folder').textContent = s.folderDisplay;
  document.getElementById('team-status').textContent = s.lastChangeAt
    ? `Up to date — last change from ${s.lastChangeBy || 'another Mac'} ${timeAgo(s.lastChangeAt)}`
    : 'Up to date — watching for changes from the other Macs';
  const nameInput = document.getElementById('team-name-input');
  if (document.activeElement !== nameInput) nameInput.value = s.memberName;
  const status = document.getElementById('team-status');
  status.classList.toggle('team-warning', !!s.thisMacOutdated);
  if (s.thisMacOutdated) status.textContent = 'Another Mac has a newer version of ScaffoldPro. Update this one (double-click Install ScaffoldPro) so nothing it saves leaves out details the newer version keeps.';
  const members = document.getElementById('team-members');
  members.innerHTML = '';
  for (const m of s.members) {
    const row = document.createElement('div');
    row.innerHTML = '<span class="status-pill"></span><span></span><span class="muted"></span>';
    row.children[0].textContent = m.isThisMac ? 'This Mac' : whenSeen(m.lastSeen);
    row.children[0].classList.toggle('pill-success', !!m.isThisMac || whenSeen(m.lastSeen) === 'active now');
    row.children[1].textContent = m.name;
    row.children[2].textContent = m.computer + (m.outdated ? ' — older version of ScaffoldPro: update it with Install ScaffoldPro' : '');
    if (m.outdated) row.children[2].classList.add('team-warning');
    members.appendChild(row);
  }
}

async function refreshTeam() {
  renderTeam(await window.api.team.status());
}

function restartForTeam(message) {
  alert(message);
  window.api.app.relaunch();
}

function setupTeam() {
  document.getElementById('team-start-btn').addEventListener('click', async () => {
    if (!confirm('Share this Mac’s data?\n\nYou’ll choose a folder in iCloud Drive. ScaffoldPro copies in your projects, drawings, documents and database, then restarts and works from there. Your files in Documents › ScaffoldPro stay where they are as they are now.')) return;
    const busy = document.getElementById('team-busy');
    busy.textContent = 'Copying your data into the shared folder…';
    const buttons = document.querySelectorAll('#team-off button');
    for (const b of buttons) b.disabled = true;
    const r = await window.api.team.start();
    for (const b of buttons) b.disabled = false;
    busy.textContent = '';
    if (r === null) return;
    if (!r.ok) { alert(r.error); return; }
    restartForTeam('Your data is in the shared folder.\n\nScaffoldPro restarts now and works from there. Next, share the folder with the others in Finder (Control-click it › Share › Share Folder…), and have them press “Join a Shared Folder…” on their Macs.');
  });
  document.getElementById('team-join-btn').addEventListener('click', async () => {
    const r = await window.api.team.join();
    if (r === null) return;
    if (!r.ok) { alert(r.error); return; }
    restartForTeam('ScaffoldPro restarts now and opens the shared data.\n\nThis Mac’s own data is kept as it is; it comes back if you stop sharing.');
  });
  document.getElementById('team-leave-btn').addEventListener('click', () => {
    if (!confirm('Stop sharing on this Mac?\n\nScaffoldPro restarts with this Mac’s own data as it was before sharing. The shared folder and everyone else’s work in it stay as they are, and you can join again later.')) return;
    window.api.team.leave().then(() => window.api.app.relaunch());
  });
  document.getElementById('team-reveal-btn').addEventListener('click', async () => {
    const r = await window.api.team.reveal();
    if (r && !r.ok) alert(r.error);
  });
  document.getElementById('team-name-input').addEventListener('change', async (e) => {
    renderTeam(await window.api.team.setName(e.target.value));
  });
  document.getElementById('settings-reload-btn').addEventListener('click', () => location.reload());
  refreshTeam();
  setInterval(refreshTeam, 10000);
}

// Another Mac changed something: refresh the parts shown here, and the
// form itself unless it has unsaved edits.
window.onSharedDataChanged = async (change) => {
  refreshTeam();
  if ((change.stores || []).includes('settings.json')) {
    if (settingsDirty) {
      document.getElementById('settings-changed-elsewhere').classList.remove('hidden');
    } else {
      await loadSettings();
      for (const id of ['defaultPaymentTerms-input', 'quotationTerms-input']) window.refreshParagraphPreview(document.getElementById(id));
    }
  }
};

// ---------- Collapsible sections ----------

// The open sections are remembered; a link to #team, #backup etc. opens
// (and scrolls to) that section.
function setupSections() {
  const KEY = 'scaffoldpro.settings.open';
  const sections = [...document.querySelectorAll('details.settings-section')];
  let saved = null;
  try { saved = JSON.parse(localStorage.getItem(KEY) || 'null'); } catch (e) { saved = null; }
  if (Array.isArray(saved)) for (const d of sections) d.open = saved.includes(d.id);
  const openFromHash = () => {
    const target = location.hash && document.getElementById(location.hash.slice(1));
    if (target && target.tagName === 'DETAILS') {
      target.open = true;
      setTimeout(() => target.scrollIntoView({ block: 'start' }), 0);
    }
  };
  openFromHash();
  window.addEventListener('hashchange', openFromHash);
  for (const d of sections) {
    d.addEventListener('toggle', () => {
      try { localStorage.setItem(KEY, JSON.stringify(sections.filter((x) => x.open).map((x) => x.id))); } catch (e) { /* not kept */ }
    });
  }
}

async function init() {
  const formatted = ['defaultPaymentTerms-input', 'quotationTerms-input'].map((id) => document.getElementById(id));
  for (const ta of formatted) window.attachParagraphFormatting(ta);
  await loadSettings();
  for (const ta of formatted) window.refreshParagraphPreview(ta);
  document.getElementById('save-btn').addEventListener('click', async () => {
    await saveSettings();
    settingsDirty = false;
    document.getElementById('settings-changed-elsewhere').classList.add('hidden');
  });
  // Typing in the form (not the sharing or backup controls further down).
  const markDirty = (e) => { if (!e.target.closest('#team-box, #cloud-backup, .backup-actions')) settingsDirty = true; };
  document.getElementById('content').addEventListener('input', markDirty);
  document.getElementById('content').addEventListener('change', markDirty);
  for (const f of NUMBER_FIELDS) {
    document.getElementById(`${f}-input`).addEventListener('input', () => updateNumberExample(f));
  }
  // Appearance applies immediately — no need to press Save.
  for (const b of document.querySelectorAll('#appearance-control button')) {
    b.addEventListener('click', async () => {
      setAppearanceButtons(b.dataset.value);
      await window.api.settings.update({ appearance: b.dataset.value });
    });
  }
  setupSections();
  await setupDefaultItems();

  document.getElementById('create-backup-btn').addEventListener('click', createBackup);
  document.getElementById('restore-other-btn').addEventListener('click', restoreFromOtherFolder);
  document.getElementById('show-backups-btn').addEventListener('click', () => window.api.backup.reveal());
  document.getElementById('show-data-folder-btn').addEventListener('click', () => window.api.backup.revealDataFolder());

  setupCloudBackup();
  setupTeam();
  await refreshBackups();
  await loadLocations();
}

init();

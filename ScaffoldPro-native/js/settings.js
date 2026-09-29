'use strict';

const SETTINGS_FIELDS = [
  'companyName', 'website', 'addressLine1', 'addressLine2', 'phone', 'email',
  'registrationNumber', 'vatNumber', 'bankDetails', 'currency',
  'defaultTaxRatePercent', 'defaultPaymentTerms', 'defaultNotes',
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
  renderManpowerRates(settings.manpowerRates);
  document.getElementById('eurRate-input').value = (settings.exchangeRates && settings.exchangeRates.EUR) || 8.93;
  for (const k of START_KEYS) {
    document.getElementById(`start-${k}`).value = (settings.numberStarts && settings.numberStarts[k]) || '';
  }
  if (settings.defaultInvoiceDueDays == null) document.getElementById('defaultInvoiceDueDays-input').value = 30;
  document.getElementById('pricesIncludeTax-input').checked = !!settings.pricesIncludeTax;
  setAppearanceButtons(settings.appearance || 'System');
  for (const f of NUMBER_FIELDS) updateNumberExample(f);
}

async function saveSettings() {
  const payload = {};
  for (const field of SETTINGS_FIELDS) {
    const el = document.getElementById(`${field}-input`);
    if (!el) continue;
    if (field === 'defaultTaxRatePercent') {
      payload[field] = parseFloat(el.value) || 0;
    } else {
      payload[field] = el.value || null;
    }
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
  payload.pricesIncludeTax = document.getElementById('pricesIncludeTax-input').checked;
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
    const kind = b.kind === 'Before Restore'
      ? '<span class="kind-safety">Automatic (before restore)</span>' : 'Manual';
    tr.innerHTML = `
      <td>${formatWhen(b.createdAt)}</td>
      <td>${kind}</td>
      <td class="num">${Number(b.projectCount).toLocaleString('en-US')}</td>
      <td class="num">${Number(b.fileCount).toLocaleString('en-US')}</td>
      <td class="num">${formatBytes(b.totalBytes)}</td>
      <td><button class="reveal-btn">Show</button> <button class="restore-btn">Restore</button></td>`;
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

async function init() {
  const formatted = ['defaultPaymentTerms-input', 'quotationTerms-input'].map((id) => document.getElementById(id));
  for (const ta of formatted) window.attachParagraphFormatting(ta);
  await loadSettings();
  for (const ta of formatted) window.refreshParagraphPreview(ta);
  document.getElementById('save-btn').addEventListener('click', saveSettings);
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
  if (location.hash === '#backup') {
    document.getElementById('backup').scrollIntoView();
  }

  document.getElementById('create-backup-btn').addEventListener('click', createBackup);
  document.getElementById('restore-other-btn').addEventListener('click', restoreFromOtherFolder);
  document.getElementById('show-backups-btn').addEventListener('click', () => window.api.backup.reveal());
  document.getElementById('show-data-folder-btn').addEventListener('click', () => window.api.backup.revealDataFolder());

  setupCloudBackup();
  await refreshBackups();
  await loadLocations();
}

init();

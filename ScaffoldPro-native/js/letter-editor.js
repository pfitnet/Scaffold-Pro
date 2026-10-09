'use strict';

// The letter editor: the letter's details (number, date, references,
// recipient, subject) and its body, written on a page that shows the
// letterhead and footer, with a Google Docs–style toolbar (js/rich-editor.js).
// The body saves itself as it's typed. Export PDF / Print lay it out on the
// letterhead over as many pages as it needs (main.swift, generateRichText).

let letterId = null;
let detail = null;
let editor = null;
let saveTimer = null;
let saving = Promise.resolve();

function esc(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function localDay(iso) {
  const d = new Date(iso || '');
  if (isNaN(d)) return '';
  const pad = (n) => String(n).padStart(2, '0');
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

function setSaveState(text) {
  document.getElementById('save-state').textContent = text;
}

// ⌘Z / ⌘Y redraw the page with this, not a reload (js/undo.js).
window.appRefresh = () => loadDetail();

async function loadDetail() {
  detail = await window.api.letters.get(letterId);
  if (!detail) {
    document.getElementById('not-found').classList.remove('hidden');
    document.getElementById('letter-page').classList.add('hidden');
    return;
  }
  document.getElementById('letter-page').classList.remove('hidden');
  render();
  if (window.letterAttachments) window.letterAttachments.render(detail.letter);
}

function render() {
  const l = detail.letter;
  const locked = l.status !== 'Draft';
  document.title = `${l.letterNumber} — ScaffoldPro`;
  document.getElementById('letter-header').innerHTML = `<h1>${esc(l.letterNumber)}</h1>
    <div class="subtitle">${esc(l.subject || 'Letter')}${detail.projectNumber ? ` · ${esc(detail.projectNumber)} — ${esc(detail.projectName || '')}` : ''}</div>`;
  document.getElementById('our-ref').textContent = l.letterNumber;
  const status = document.getElementById('status-select');
  status.value = l.status;
  for (const opt of status.options) opt.disabled = l.status === 'Cancelled' && opt.value !== 'Cancelled';

  const fields = { 'f-yourRef': l.yourRef, 'f-recipientName': l.recipientName, 'f-recipientAddress': l.recipientAddress, 'f-attention': l.attention, 'f-subject': l.subject };
  for (const [id, value] of Object.entries(fields)) {
    const el = document.getElementById(id);
    if (document.activeElement !== el) el.value = value || '';
    el.disabled = locked;
  }
  const date = document.getElementById('f-date');
  if (document.activeElement !== date) date.value = localDay(l.letterDate);
  date.disabled = locked;
  document.getElementById('f-project').innerHTML = detail.projectNumber
    ? `<a href="project-detail.html?number=${encodeURIComponent(detail.projectNumber)}&tab=letters">${esc(detail.projectNumber)} — ${esc(detail.projectName || '')}</a>` : '—';
  document.getElementById('f-client').disabled = locked;

  document.getElementById('opening').innerHTML = detail.openingHTML;
  const body = document.getElementById('letter-body');
  if (document.activeElement !== body && body.innerHTML !== l.bodyHTML) body.innerHTML = l.bodyHTML;
  editor.setEditable(!locked);
  // Back to the project's Letters.
  const back = document.getElementById('back-link');
  back.href = detail.projectNumber ? `project-detail.html?number=${encodeURIComponent(detail.projectNumber)}&tab=letters` : 'letters.html';
  back.innerHTML = detail.projectNumber ? '&larr; Back to project' : '&larr; All letters';
}

// ---- saving ----

function queueBodySave() {
  setSaveState('Editing…');
  clearTimeout(saveTimer);
  saveTimer = setTimeout(saveBody, 700);
}

function saveBody() {
  clearTimeout(saveTimer);
  saveTimer = null;
  const html = document.getElementById('letter-body').innerHTML.replace(/​/g, '');
  if (!detail || html === detail.letter.bodyHTML) { setSaveState('Saved'); return saving; }
  setSaveState('Saving…');
  saving = saving.then(async () => {
    const r = await window.api.letters.update(letterId, { bodyHTML: html });
    if (r && r.ok === false) { setSaveState(''); alert(r.error); return; }
    detail.letter.bodyHTML = html;
    setSaveState('Saved');
  });
  return saving;
}

async function flush() {
  if (saveTimer) await saveBody();
  await saving;
}

async function saveField(changes) {
  await flush();
  const r = await window.api.letters.update(letterId, changes);
  if (r && r.ok === false) { alert(r.error); }
  await loadDetail();
}

// ---- page ----

async function showLetterhead() {
  try {
    const lh = await window.api.letters.letterhead();
    if (!lh || !lh.png) return;
    const url = `url("data:image/png;base64,${lh.png}")`;
    document.getElementById('paper-head').style.backgroundImage = url;
    document.getElementById('paper-foot').style.backgroundImage = url;
    document.getElementById('paper').classList.toggle('letter-size', lh.paperSize === 'Letter');
  } catch (e) { /* the page shows without it */ }
}

async function init() {
  letterId = new URLSearchParams(location.search).get('id');
  if (!letterId) { document.getElementById('not-found').classList.remove('hidden'); return; }

  editor = window.createRichEditor(document.getElementById('letter-body'), document.getElementById('rt-toolbar'), { onChange: queueBodySave });

  const clients = await window.api.clients.list();
  const clientList = (clients || []).filter((c) => !c.isArchived);
  document.getElementById('f-client').innerHTML = '<option value="">Choose a client…</option>' +
    clientList.map((c) => `<option value="${esc(c.id)}">${esc(c.companyName)}</option>`).join('');

  await loadDetail();
  if (!detail) return;
  showLetterhead();

  for (const [id, key] of [['f-yourRef', 'yourRef'], ['f-recipientName', 'recipientName'], ['f-recipientAddress', 'recipientAddress'],
    ['f-attention', 'attention'], ['f-subject', 'subject']]) {
    document.getElementById(id).addEventListener('change', (e) => saveField({ [key]: e.target.value }));
  }
  document.getElementById('f-date').addEventListener('change', (e) => { if (e.target.value) saveField({ letterDate: e.target.value }); });
  document.getElementById('f-client').addEventListener('change', async (e) => {
    const c = clientList.find((x) => x.id === e.target.value);
    e.target.value = '';
    if (!c) return;
    const lines = (c.billingInfo && c.billingInfo.trim()
      ? c.billingInfo.split('\n')
      : [c.address, c.addressLine2, c.addressLine3, [c.city, c.postalCode].filter(Boolean).join(' ')]).map((x) => (x || '').trim()).filter(Boolean);
    await saveField({ clientId: c.id, recipientName: c.companyName, recipientAddress: lines.join('\n'), attention: c.contactPerson || '' });
  });

  document.getElementById('status-select').addEventListener('change', async (e) => {
    const to = e.target.value;
    const from = detail.letter.status;
    if (to === 'Cancelled' && !await appConfirm('Cancel this letter?\n\nIt will be kept for your records but can’t be reopened.')) { e.target.value = from; return; }
    if (from === 'Issued' && to === 'Draft' && !await appConfirm('Return this letter to Draft?\n\nIt has already been issued; editing it afterwards means the copy sent no longer matches.')) { e.target.value = from; return; }
    await flush();
    const r = await window.api.letters.updateStatus(letterId, to);
    if (r && r.ok === false) alert(r.error);
    await loadDetail();
  });
  document.getElementById('export-word-btn').addEventListener('click', async (e) => {
    await flush();
    e.target.disabled = true;
    try {
      const result = await window.exportWord(() => window.api.letters.exportWord(letterId));
      if (result && result.ok === false) alert(result.error);
    } catch (err) {
      alert(`The Word document couldn't be made.\n\n${err.message}`);
    } finally {
      e.target.disabled = false;
    }
  });
  document.getElementById('export-pdf-btn').addEventListener('click', async () => {
    await flush();
    // Shown first (js/doc-preview.js); saved from there.
    const r = await window.docPreview.pdf(() => window.api.letters.exportPDF(letterId, { preview: true }),
      { title: (detail && detail.letter && detail.letter.letterNumber) || 'Letter' });
    if (r && r.ok === false) alert(r.error);
  });
  document.getElementById('print-btn').addEventListener('click', async () => {
    await flush();
    const r = await window.api.letters.print(letterId);
    if (r && r.ok === false) alert(r.error);
  });
  document.getElementById('delete-btn').addEventListener('click', async () => {
    const l = detail.letter;
    let force = false;
    if (l.status !== 'Draft') {
      if (!await appConfirm(`${l.letterNumber} has been ${l.status.toLowerCase()}. Delete it anyway?`)) return;
      force = true;
    }
    if (!await appConfirm(`Delete ${l.letterNumber}? This can’t be undone. (A PDF already saved stays in its folder.)`)) return;
    clearTimeout(saveTimer); saveTimer = null;
    const r = await window.api.letters.remove(letterId, force);
    if (r && r.ok === false) { alert(r.error); return; }
    location.href = document.getElementById('back-link').href;
  });
  // Don't lose the last few keystrokes when leaving the page.
  window.addEventListener('beforeunload', () => { if (saveTimer) saveBody(); });
  setSaveState('Saved');
}

init();

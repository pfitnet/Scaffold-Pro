/**
 * ScaffoldPro ⇄ Google Sheets
 *
 * Keeps a Google Sheet as an overview of who did what, and when, in
 * ScaffoldPro — and brings changes made in the sheet back into ScaffoldPro.
 *
 *   Overview  — who has done how much this week, projects by status, the latest work
 *   Activity  — everything done in ScaffoldPro, newest first (When, Who, Project, What…).
 *               Type a new row with no ID (e.g. "Site visit") and it is added to
 *               ScaffoldPro's history on the next sync.
 *   Projects  — every project. Change Status, Project Manager or Notes here and
 *               ScaffoldPro is updated; change them in ScaffoldPro and this updates.
 *
 * Setting it up (once):
 *   1. In the Google Sheet: Extensions › Apps Script. Replace everything there
 *      with this file and save.
 *   2. Choose "setup" at the top and press Run (allow it to use the sheet).
 *      It makes the tabs and shows the connection secret.
 *   3. Deploy › New deployment › Select type: Web app.
 *      Execute as: Me.   Who has access: Anyone.   Deploy, and copy the Web app URL.
 *   4. In ScaffoldPro: Settings › Google Sheets — paste the Web app URL and the
 *      secret, then Connect. It syncs about every minute while ScaffoldPro is open.
 *
 * The secret can be shown again from the sheet: ScaffoldPro › Connection secret.
 * After changing this script, use Deploy › Manage deployments › Edit › New version.
 */

const TABS = { overview: 'Overview', activity: 'Activity', projects: 'Projects', sync: '_sync' };
const ACTIVITY_HEAD = ['When', 'Who', 'Project', 'Project Name', 'What', 'Reference', 'From', 'ID'];
const PROJECT_HEAD = ['Project No.', 'Name', 'Client', 'Site', 'Status', 'Project Manager', 'Notes', 'Last Activity', 'Last By', 'ID'];
// The columns that can be changed here and go back into ScaffoldPro.
const EDITABLE = { 'Status': 'status', 'Project Manager': 'projectManager', 'Notes': 'internalNotes' };
const STATUSES = ['Planning', 'Quotation', 'Active', 'On Hold', 'Completed', 'Archived'];
const KEEP_ACTIVITY_ROWS = 20000;
const DATE_FORMAT = 'd mmm yyyy h:mm';

// ---------------------------------------------------------------- setup

function onOpen() {
  SpreadsheetApp.getUi().createMenu('ScaffoldPro')
    .addItem('Connection secret', 'showSecret')
    .addItem('Rebuild Overview tab', 'buildOverview_')
    .addToUi();
}

function setup() {
  const secret = secret_();
  ensureTabs_();
  buildOverview_();
  const message = 'ScaffoldPro is set up in this sheet.\n\nConnection secret:\n' + secret +
    '\n\nNext: Deploy › New deployment › Web app (Execute as: Me, Who has access: Anyone), ' +
    'then paste the Web app URL and this secret into ScaffoldPro › Settings › Google Sheets.';
  Logger.log(message);
  try { SpreadsheetApp.getUi().alert(message); } catch (e) { /* run from the editor: see the log */ }
}

function showSecret() {
  SpreadsheetApp.getUi().alert('Connection secret for ScaffoldPro › Settings › Google Sheets:\n\n' + secret_());
}

function secret_() {
  const props = PropertiesService.getScriptProperties();
  let s = props.getProperty('SECRET');
  if (!s) { s = Utilities.getUuid().replace(/-/g, ''); props.setProperty('SECRET', s); }
  return s;
}

function ensureTabs_() {
  const ss = SpreadsheetApp.getActive();
  const make = (name, head, widths) => {
    let sh = ss.getSheetByName(name);
    if (!sh) sh = ss.insertSheet(name);
    if (head) {
      const first = sh.getRange(1, 1, 1, head.length).getValues()[0];
      if (first.join('') === '') {
        sh.getRange(1, 1, 1, head.length).setValues([head]).setFontWeight('bold').setBackground('#eef2fb').setFontColor('#1f2a44');
        sh.setFrozenRows(1);
        (widths || []).forEach((w, i) => sh.setColumnWidth(i + 1, w));
      }
    }
    return sh;
  };
  make(TABS.overview);
  const act = make(TABS.activity, ACTIVITY_HEAD, [140, 120, 80, 200, 320, 160, 110, 150]);
  act.getRange('A2:A').setNumberFormat(DATE_FORMAT);
  const prj = make(TABS.projects, PROJECT_HEAD, [90, 220, 200, 180, 100, 140, 260, 140, 120, 150]);
  prj.getRange('H2:H').setNumberFormat(DATE_FORMAT);
  const sync = make(TABS.sync);
  sync.hideSheet();
  // The ID columns are ScaffoldPro's — greyed so they're left alone.
  act.getRange('H:H').setFontColor('#9aa0ab');
  prj.getRange('J:J').setFontColor('#9aa0ab');
  statusRule_(prj);
}

function statusRule_(sh) {
  const col = PROJECT_HEAD.indexOf('Status') + 1;
  const rule = SpreadsheetApp.newDataValidation().requireValueInList(STATUSES, true).setAllowInvalid(true).build();
  sh.getRange(2, col, Math.max(sh.getMaxRows() - 1, 1), 1).setDataValidation(rule);
}

function buildOverview_() {
  const ss = SpreadsheetApp.getActive();
  const sh = ss.getSheetByName(TABS.overview) || ss.insertSheet(TABS.overview);
  sh.clear();
  sh.getRange('A1').setValue('ScaffoldPro — Overview').setFontSize(16).setFontWeight('bold');
  sh.getRange('A2').setValue('Last synced');
  sh.getRange('A4').setValue('Who did what — last 7 days').setFontWeight('bold');
  sh.getRange('A5').setFormula('=IFERROR(QUERY(Activity!A2:H, "select B, count(E) where A >= date \'"&TEXT(TODAY()-7,"yyyy-mm-dd")&"\' and B <> \'\' group by B order by count(E) desc label B \'Who\', count(E) \'Things done\'", 0), "Nothing yet")');
  sh.getRange('D4').setValue('Projects by status').setFontWeight('bold');
  sh.getRange('D5').setFormula('=IFERROR(QUERY(Projects!A2:J, "select E, count(A) where A <> \'\' group by E label E \'Status\', count(A) \'Projects\'", 0), "Nothing yet")');
  sh.getRange('G4').setValue('Latest work').setFontWeight('bold');
  sh.getRange('G5').setFormula('=IFERROR(QUERY(Activity!A2:F, "select A, B, C, E where E <> \'\' order by A desc limit 25 label A \'When\', B \'Who\', C \'Project\', E \'What\'", 0), "Nothing yet")');
  sh.getRange('G6:G').setNumberFormat(DATE_FORMAT);
  [150, 90, 30, 110, 80, 30, 140, 120, 80, 340].forEach((w, i) => sh.setColumnWidth(i + 1, w));
  ss.setActiveSheet(sh);
  ss.moveActiveSheet(1);
}

// ---------------------------------------------------------------- the link

function doGet() {
  return ContentService.createTextOutput('ScaffoldPro sync is running. Connect from ScaffoldPro › Settings › Google Sheets.');
}

function doPost(e) {
  let req;
  try { req = JSON.parse(e.postData.contents); } catch (x) { return out_({ ok: false, error: 'The request couldn’t be read.' }); }
  const secret = PropertiesService.getScriptProperties().getProperty('SECRET');
  if (!secret) return out_({ ok: false, error: 'The sheet isn’t set up yet — run "setup" in its Apps Script first.' });
  if (req.secret !== secret) return out_({ ok: false, error: 'The secret doesn’t match. In the sheet, choose ScaffoldPro › Connection secret and copy it again.' });
  const ss = SpreadsheetApp.getActive();
  if (req.action === 'ping') return out_({ ok: true, name: ss.getName(), url: ss.getUrl() });
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(25000)) return out_({ ok: false, error: 'The sheet is busy — trying again shortly.' });
  try {
    ensureTabs_();
    const changes = syncProjects_(req.projects || []);
    const activity = syncActivity_(req.activity || []);
    const ov = ss.getSheetByName(TABS.overview);
    if (ov) ov.getRange('B2').setValue(new Date()).setNumberFormat(DATE_FORMAT);
    return out_({ ok: true, name: ss.getName(), url: ss.getUrl(), changes: changes, activity: activity });
  } catch (err) {
    return out_({ ok: false, error: String(err && err.message || err) });
  } finally {
    lock.releaseLock();
  }
}

function out_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

const str_ = (v) => (v === null || v === undefined ? '' : String(v)).trim();
const date_ = (iso) => { const d = iso ? new Date(iso) : null; return d && !isNaN(d) ? d : ''; };

// Projects: what was changed in the sheet since the last sync goes back to
// ScaffoldPro (and is kept); everything else is written from ScaffoldPro.
function syncProjects_(projects) {
  const ss = SpreadsheetApp.getActive();
  const sh = ss.getSheetByName(TABS.projects);
  const sync = ss.getSheetByName(TABS.sync);
  const values = sh.getDataRange().getValues();
  const head = values[0].map(str_);
  const col = {};
  PROJECT_HEAD.forEach((h) => { col[h] = head.indexOf(h); });
  if (col['ID'] < 0) throw new Error('The Projects tab has lost its ID column — put the heading "ID" back.');
  const width = head.length;

  // What ScaffoldPro last wrote for the editable columns.
  const snap = {};
  const syncRows = sync.getLastRow() > 0 ? sync.getRange(1, 1, sync.getLastRow(), 2).getValues() : [];
  syncRows.forEach((r) => { if (r[0]) { try { snap[r[0]] = JSON.parse(r[1]); } catch (e) { /* ignore */ } } });

  const rows = values.slice(1);
  const changes = [];
  const sheetWins = {};
  const byId = {};
  rows.forEach((r, i) => {
    const id = str_(r[col['ID']]);
    if (!id) return;
    byId[id] = i;
    const before = snap[id];
    if (!before) return;
    Object.keys(EDITABLE).forEach((h) => {
      if (col[h] < 0) return;
      const field = EDITABLE[h];
      const now = str_(r[col[h]]);
      if (now !== str_(before[field])) {
        changes.push({ projectId: id, field: field, value: now });
        (sheetWins[id] = sheetWins[id] || {})[field] = now;
      }
    });
  });

  const wanted = new Set(projects.map((p) => p.id));
  const put = (row, h, v) => { if (col[h] >= 0) row[col[h]] = v; };
  const fill = (row, p) => {
    const wins = sheetWins[p.id] || {};
    put(row, 'Project No.', p.number);
    put(row, 'Name', p.name);
    put(row, 'Client', p.client || '');
    put(row, 'Site', p.site || '');
    put(row, 'Status', 'status' in wins ? wins.status : (p.status || ''));
    put(row, 'Project Manager', 'projectManager' in wins ? wins.projectManager : (p.projectManager || ''));
    put(row, 'Notes', 'internalNotes' in wins ? wins.internalNotes : (p.internalNotes || ''));
    put(row, 'Last Activity', date_(p.lastActivity));
    put(row, 'Last By', p.lastBy || '');
    put(row, 'ID', p.id);
    return row;
  };
  // Kept: rows typed in by hand (no ID) and ScaffoldPro's projects; a
  // project deleted in ScaffoldPro leaves the sheet.
  const out = rows.filter((r) => { const id = str_(r[col['ID']]); return !id || wanted.has(id); }).map((r) => r.slice());
  const outIndex = {};
  out.forEach((r, i) => { const id = str_(r[col['ID']]); if (id) outIndex[id] = i; });
  projects.forEach((p) => {
    if (p.id in outIndex) fill(out[outIndex[p.id]], p);
    else out.push(fill(new Array(width).fill(''), p));
  });
  const numCol = col['Project No.'];
  out.sort((a, b) => str_(b[numCol]).localeCompare(str_(a[numCol]), undefined, { numeric: true }));

  // Written only when something is different (no edit history every minute).
  const norm = (rs) => JSON.stringify(rs.map((r) => r.map((v) => (v instanceof Date ? v.getTime() : str_(v)))));
  if (norm(out) !== norm(rows)) {
    if (rows.length) sh.getRange(2, 1, rows.length, width).clearContent();
    if (out.length) sh.getRange(2, 1, out.length, width).setValues(out);
    statusRule_(sh);
  }

  // Remember what ScaffoldPro and the sheet now agree on.
  const snapRows = out.filter((r) => str_(r[col['ID']])).map((r) => {
    const o = {};
    Object.keys(EDITABLE).forEach((h) => { if (col[h] >= 0) o[EDITABLE[h]] = str_(r[col[h]]); });
    return [str_(r[col['ID']]), JSON.stringify(o)];
  });
  sync.clearContents();
  if (snapRows.length) sync.getRange(1, 1, snapRows.length, 2).setValues(snapRows);
  return changes;
}

// Activity: ScaffoldPro's entries not in the sheet yet go in at the top;
// rows typed in by hand get an ID and go back to ScaffoldPro.
function syncActivity_(entries) {
  const sh = SpreadsheetApp.getActive().getSheetByName(TABS.activity);
  const values = sh.getDataRange().getValues();
  const head = values[0].map(str_);
  const col = {};
  ACTIVITY_HEAD.forEach((h) => { col[h] = head.indexOf(h); });
  if (col['ID'] < 0 || col['What'] < 0) throw new Error('The Activity tab has lost its What or ID column — put the heading back.');
  const width = head.length;
  const seen = new Set();
  const typed = [];
  for (let i = 1; i < values.length; i++) {
    const r = values[i];
    const id = str_(r[col['ID']]);
    if (id) { seen.add(id); continue; }
    const what = str_(r[col['What']]);
    if (!what) continue;
    const newId = 'sheet-' + Utilities.getUuid().replace(/-/g, '').slice(0, 16);
    let when = col['When'] >= 0 ? r[col['When']] : '';
    if (!(when instanceof Date) || isNaN(when)) {
      const parsed = when ? new Date(when) : null;
      when = parsed && !isNaN(parsed) ? parsed : new Date();
      if (col['When'] >= 0) sh.getRange(i + 1, col['When'] + 1).setValue(when);
    }
    sh.getRange(i + 1, col['ID'] + 1).setValue(newId);
    if (col['From'] >= 0 && !str_(r[col['From']])) sh.getRange(i + 1, col['From'] + 1).setValue('Google Sheets');
    seen.add(newId);
    typed.push({
      id: newId, when: when.toISOString(), who: col['Who'] >= 0 ? str_(r[col['Who']]) : '',
      project: col['Project'] >= 0 ? str_(r[col['Project']]) : '', what: what,
      reference: col['Reference'] >= 0 ? str_(r[col['Reference']]) : '',
    });
  }

  const fresh = entries.filter((e) => e.id && !seen.has(e.id))
    .sort((a, b) => String(b.when).localeCompare(String(a.when)));
  if (fresh.length) {
    const rows = fresh.map((e) => {
      const row = new Array(width).fill('');
      const put = (h, v) => { if (col[h] >= 0) row[col[h]] = v; };
      put('When', date_(e.when));
      put('Who', e.who || '');
      put('Project', e.project || '');
      put('Project Name', e.projectName || '');
      put('What', e.what || '');
      put('Reference', e.reference || '');
      put('From', e.from || 'ScaffoldPro');
      put('ID', e.id);
      return row;
    });
    sh.insertRowsBefore(2, rows.length);
    sh.getRange(2, 1, rows.length, width).setValues(rows);
    if (col['When'] >= 0) {
      sh.getRange(2, col['When'] + 1, rows.length, 1).setNumberFormat(DATE_FORMAT);
      // Newest first, even when another Mac's work arrives late.
      sh.getRange(2, 1, sh.getLastRow() - 1, width).sort({ column: col['When'] + 1, ascending: false });
    }
  }
  const extra = sh.getLastRow() - 1 - KEEP_ACTIVITY_ROWS;
  if (extra > 0) sh.deleteRows(KEEP_ACTIVITY_ROWS + 2, extra);
  return typed;
}

/**
 * ScaffoldPro ⇄ Google Sheets
 *
 * Keeps a Google Sheet as an overview of who did what, and when, in
 * ScaffoldPro — and brings changes made in the sheet back into ScaffoldPro.
 *
 *   Overview  — who has done how much this week, projects by status, the latest work
 *   Projects  — each project (a shaded row), then one row per sub-project
 *               (-001, -002 …) with its BOQ, quotations, delivery notes and
 *               invoices and how far it has got. The sub-project rows fold
 *               away under their project (the − / + at the left).
 *               Change a project's Stage or Notes here and ScaffoldPro is
 *               updated; a sub-project's Notes are kept in the sheet only.
 *   Activity  — everything done in ScaffoldPro, newest first: When, Who,
 *               Project, What. Type a new row (When can be left blank) and
 *               it is added to ScaffoldPro's history on the next sync.
 *
 * Setting it up (once):
 *   1. In the Google Sheet: Extensions › Apps Script. Replace everything there
 *      with this file and save.
 *   2. In the list next to Run / Debug, choose "setup" (not onOpen), then press
 *      Run and allow it to use the sheet ("unverified app": Advanced › Go to …).
 *      It makes the tabs and shows the connection secret.
 *   3. Deploy › New deployment › Select type: Web app.
 *      Execute as: Me.   Who has access: Anyone.   Deploy, and copy the Web app URL.
 *   4. In ScaffoldPro: Settings › Google Sheets — paste the Web app URL and the
 *      secret, then Connect. It syncs about every minute while ScaffoldPro is open.
 *
 * Made at script.google.com instead (not from the sheet's Extensions menu)?
 * Paste the sheet's link into SHEET_URL just below, save, then carry on from
 * step 2. The script then opens that sheet itself.
 *
 * The secret can be shown again from the sheet: ScaffoldPro › Connection secret
 * (or run "showSecret" and look in the Execution log).
 * After changing this script, use Deploy › Manage deployments › Edit › New version
 * (and run "setup" once more if the tabs' layout changed).
 */

// Only for a script made at script.google.com: the sheet's link, e.g.
// 'https://docs.google.com/spreadsheets/d/1AbC…/edit'. Leave it '' when the
// script was opened from the sheet (Extensions › Apps Script).
const SHEET_URL = '';

// The tabs' layout. A sheet made with an older layout is rebuilt in this one.
const LAYOUT = '2';
const TABS = { overview: 'Overview', activity: 'Activity', projects: 'Projects', sync: '_sync' };
const ACTIVITY_HEAD = ['When', 'Who', 'Project', 'What', 'ID'];
const PROJECT_HEAD = ['Ref', 'Name', 'Client · Site', 'Stage', 'BOQ', 'Quotations', 'Delivery Notes', 'Invoices', 'Letters', 'Last Update', 'Notes', 'ID'];
// On a project's row these go back into ScaffoldPro.
const EDITABLE = { 'Stage': 'status', 'Notes': 'internalNotes' };
const STATUSES = ['Planning', 'Quotation', 'Active', 'On Hold', 'Completed', 'Archived'];
// How far a sub-project has got, and its colour.
const STAGE_COLOURS = {
  Draft: ['#f1f3f4', '#5f6368'], Quoted: ['#ede7f6', '#5e35b1'], Accepted: ['#e3f2fd', '#1565c0'],
  Delivered: ['#fff3e0', '#b26a00'], Invoiced: ['#e8eaf6', '#3949ab'], Paid: ['#e6f4ea', '#1e7e34'], Cancelled: ['#fce8e6', '#c5221f'],
};
// ScaffoldPro's own colours: each kind of document, and project statuses.
const DOC_COLOURS = { 'BOQ': '#3f938b', 'Quotations': '#5374b8', 'Delivery Notes': '#b0843f', 'Invoices': '#5d9150', 'Letters': '#8a6cb0' };
const STATUS_COLOURS = { Planning: '#8b6cf0', Quotation: '#c98a14', Active: '#2a8a4a', 'On Hold': '#e0793a', Completed: '#3a66f0', Archived: '#9196a3' };
// In Activity, a line about a document is tinted in that document's colour.
const ACTIVITY_KINDS = [['\\bQt\\d', '#5374b8'], ['\\bBQ\\d', '#3f938b'], ['\\bDN\\d', '#b0843f'], ['\\bH\\d{4}', '#5d9150'], ['\\bP?L\\d', '#8a6cb0']];
const KEEP_ACTIVITY_ROWS = 20000;
const DATE_FORMAT = 'd mmm yyyy h:mm';
const HEAD_BG = '#1f2a44', HEAD_FG = '#ffffff', PROJECT_BG = '#eef2fb', LINE = '#dfe3ea';

// ---------------------------------------------------------------- setup

// Runs by itself when the sheet is opened (adds the ScaffoldPro menu).
// Run from the editor it has no sheet window to add to, so it does nothing:
// choose "setup" in the list at the top instead.
function onOpen() {
  try {
    SpreadsheetApp.getUi().createMenu('ScaffoldPro')
      .addItem('Connection secret', 'showSecret')
      .addItem('Rebuild Overview tab', 'buildOverview_')
      .addToUi();
  } catch (e) {
    Logger.log('onOpen runs by itself when the sheet opens. To set things up, choose "setup" in the list at the top and press Run.');
  }
}

function setup() {
  ss_();
  const secret = secret_();
  ensureTabs_();
  colours_(JSON.parse(PropertiesService.getScriptProperties().getProperty('PEOPLE') || '{}'));
  buildOverview_();
  const message = 'ScaffoldPro is set up in this sheet.\n\nConnection secret:\n' + secret +
    '\n\nNext: Deploy › New deployment › Web app (Execute as: Me, Who has access: Anyone), ' +
    'then paste the Web app URL and this secret into ScaffoldPro › Settings › Google Sheets.';
  Logger.log(message);
  try { SpreadsheetApp.getUi().alert(message); } catch (e) { /* run from the editor: see the log */ }
}

function showSecret() {
  const message = 'Connection secret for ScaffoldPro › Settings › Google Sheets:\n\n' + secret_();
  Logger.log(message);
  try { SpreadsheetApp.getUi().alert(message); } catch (e) { /* run from the editor: see the log */ }
}

// The sheet: the one the script belongs to, or the one in SHEET_URL.
function ss_() {
  let ss = null;
  try { ss = SpreadsheetApp.getActive(); } catch (e) { /* not attached to a sheet */ }
  if (ss) return ss;
  const url = String(SHEET_URL || '').trim();
  if (!url) throw new Error('This script isn\'t attached to a Google Sheet. Paste the sheet\'s link into SHEET_URL at the top of the script (or open the script from the sheet: Extensions › Apps Script).');
  return /^https?:/.test(url) ? SpreadsheetApp.openByUrl(url) : SpreadsheetApp.openById(url);
}

function secret_() {
  const props = PropertiesService.getScriptProperties();
  let s = props.getProperty('SECRET');
  if (!s) { s = Utilities.getUuid().replace(/-/g, ''); props.setProperty('SECRET', s); }
  return s;
}

function ensureTabs_() {
  const ss = ss_();
  const props = PropertiesService.getScriptProperties();
  const fresh = props.getProperty('LAYOUT') !== LAYOUT;
  const tab = (name) => ss.getSheetByName(name) || ss.insertSheet(name);
  tab(TABS.overview);
  const act = tab(TABS.activity);
  const prj = tab(TABS.projects);
  const sync = tab(TABS.sync);
  sync.hideSheet();
  if (fresh) {
    migrateActivity_(act);
    // The Projects tab is written again in full by the next sync.
    prj.clear();
    try { prj.getRange(1, 1, prj.getMaxRows(), 1).shiftRowGroupDepth(-8); } catch (e) { /* no groups */ }
    sync.clearContents();
  }
  const head = (sh, cols, widths) => {
    if (sh.getRange(1, 1).getValue() !== cols[0] || fresh) {
      sh.getRange(1, 1, 1, sh.getMaxColumns()).clearContent();
      sh.getRange(1, 1, 1, cols.length).setValues([cols]).setFontWeight('bold').setBackground(HEAD_BG).setFontColor(HEAD_FG)
        .setVerticalAlignment('middle');
      sh.setRowHeight(1, 30);
      sh.setFrozenRows(1);
      widths.forEach((w, i) => sh.setColumnWidth(i + 1, w));
      // The ID column is ScaffoldPro's: hidden.
      sh.hideColumns(cols.length);
    }
  };
  head(act, ACTIVITY_HEAD, [150, 110, 240, 460, 60]);
  act.getRange('A2:A').setNumberFormat(DATE_FORMAT);
  act.getRange('A2:D').setVerticalAlignment('top').setWrap(true);
  head(prj, PROJECT_HEAD, [120, 240, 220, 100, 130, 160, 160, 150, 110, 170, 240, 60]);
  prj.setFrozenColumns(1);
  prj.getRange('A2:K').setVerticalAlignment('top').setWrap(true);
  try { prj.setRowGroupControlPosition(SpreadsheetApp.GroupControlTogglePosition.BEFORE); } catch (e) { /* older API */ }
  if (fresh) {
    props.setProperty('COLOURED', '');
    props.setProperty('LAYOUT', LAYOUT);
  }
  // The document columns' headings in their colours.
  Object.keys(DOC_COLOURS).forEach((h) => {
    prj.getRange(1, PROJECT_HEAD.indexOf(h) + 1).setBackground(DOC_COLOURS[h]).setFontColor('#ffffff');
  });
}

// The old Activity layout (When, Who, Project, Project Name, What,
// Reference, From, ID) put into the new one.
function migrateActivity_(sh) {
  const values = sh.getDataRange().getValues();
  const head = values[0].map(str_);
  if (head.indexOf('Project Name') < 0 && head.indexOf('Reference') < 0) return;
  const c = {}; head.forEach((h, i) => { c[h] = i; });
  const get = (r, h) => (c[h] >= 0 ? r[c[h]] : '');
  const rows = values.slice(1).map((r) => [
    get(r, 'When'), str_(get(r, 'Who')),
    [str_(get(r, 'Project')), str_(get(r, 'Project Name'))].filter(Boolean).join(' '),
    [str_(get(r, 'What')), str_(get(r, 'Reference'))].filter(Boolean).join(' — '),
    str_(get(r, 'ID')),
  ]);
  sh.clear();
  try { sh.showColumns(1, sh.getMaxColumns()); } catch (e) { /* none hidden */ }
  if (rows.length) sh.getRange(2, 1, rows.length, ACTIVITY_HEAD.length).setValues(rows);
}

// Each sub-project's stage in its colour.
function stageColours_(sh, people) {
  const range = sh.getRange('D2:D');
  const rule = (text, bg, fg) => SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo(text).setBackground(bg).setFontColor(fg).setRanges([range]).build();
  const rules = Object.keys(STAGE_COLOURS).map((stage) => rule(stage, STAGE_COLOURS[stage][0], STAGE_COLOURS[stage][1]))
    .concat(Object.keys(STATUS_COLOURS).map((st) => rule(st, tint_(STATUS_COLOURS[st], 0.8), STATUS_COLOURS[st])));
  // Who last worked on it, in their colour.
  const last = sh.getRange('J2:J');
  Object.keys(people || {}).forEach((name) => {
    rules.push(SpreadsheetApp.newConditionalFormatRule().whenTextContains('· ' + name).setFontColor(people[name]).setRanges([last]).build());
  });
  sh.setConditionalFormatRules(rules);
}

// Activity: each person's name in their colour; a line about a document
// tinted in that document's colour.
function activityColours_(sh, people) {
  const rules = [];
  const who = sh.getRange('B2:B');
  Object.keys(people || {}).forEach((name) => {
    rules.push(SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo(name).setFontColor(people[name]).setBackground(tint_(people[name], 0.86))
      .setBold(true).setRanges([who]).build());
  });
  const rows = sh.getRange('A2:D');
  ACTIVITY_KINDS.forEach(([pattern, colour]) => {
    rules.push(SpreadsheetApp.newConditionalFormatRule().whenFormulaSatisfied('=REGEXMATCH($D2, "' + pattern + '")')
      .setBackground(tint_(colour, 0.9)).setRanges([rows]).build());
  });
  sh.setConditionalFormatRules(rules);
}

// The colour rules, set again whenever someone's colour changes.
function colours_(people) {
  const ss = ss_();
  const props = PropertiesService.getScriptProperties();
  const key = JSON.stringify(people || {});
  if (props.getProperty('PEOPLE') === key && props.getProperty('COLOURED') === LAYOUT) return;
  stageColours_(ss.getSheetByName(TABS.projects), people);
  activityColours_(ss.getSheetByName(TABS.activity), people);
  props.setProperty('PEOPLE', key);
  props.setProperty('COLOURED', LAYOUT);
}

function buildOverview_() {
  const ss = ss_();
  const sh = ss.getSheetByName(TABS.overview) || ss.insertSheet(TABS.overview);
  sh.clear();
  sh.getRange('A1').setValue('ScaffoldPro — Overview').setFontSize(16).setFontWeight('bold');
  sh.getRange('A2').setValue('Last synced');
  sh.getRange('A4').setValue('Who did what — last 7 days').setFontWeight('bold');
  sh.getRange('A5').setFormula('=IFERROR(QUERY(Activity!A2:D, "select B, count(D) where A >= date \'"&TEXT(TODAY()-7,"yyyy-mm-dd")&"\' and B <> \'\' group by B order by count(D) desc label B \'Who\', count(D) \'Things done\'", 0), "Nothing yet")');
  sh.getRange('D4').setValue('Projects by stage').setFontWeight('bold');
  sh.getRange('D5').setFormula('=IFERROR(QUERY(Projects!A2:L, "select D, count(A) where L <> \'\' and not L contains \'#\' group by D label D \'Stage\', count(A) \'Projects\'", 0), "Nothing yet")');
  sh.getRange('G4').setValue('Latest work').setFontWeight('bold');
  sh.getRange('G5').setFormula('=IFERROR(QUERY(Activity!A2:D, "select A, B, C, D where D <> \'\' order by A desc limit 25 label A \'When\', B \'Who\', C \'Project\', D \'What\'", 0), "Nothing yet")');
  sh.getRange('G6:G').setNumberFormat(DATE_FORMAT);
  [150, 90, 30, 110, 80, 30, 140, 110, 200, 380].forEach((w, i) => sh.setColumnWidth(i + 1, w));
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
  const ss = ss_();
  if (req.action === 'ping') return out_({ ok: true, name: ss.getName(), url: ss.getUrl() });
  const lock = LockService.getScriptLock();
  if (!lock.tryLock(25000)) return out_({ ok: false, error: 'The sheet is busy — trying again shortly.' });
  try {
    ensureTabs_();
    colours_(req.people || {});
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
const when_ = (iso, who, tz) => {
  const d = date_(iso);
  if (!d) return who || '';
  return Utilities.formatDate(d, tz || 'Asia/Hong_Kong', 'd MMM yyyy HH:mm') + (who ? ' · ' + who : '');
};
const lines_ = (list) => (list || []).join('\n');
// A colour mixed with white: amount 0 (the colour) … 1 (white).
const tint_ = (hex, amount) => {
  const n = parseInt(String(hex).replace('#', ''), 16);
  const mix = (c) => Math.round(c + (255 - c) * amount).toString(16).padStart(2, '0');
  return '#' + mix((n >> 16) & 255) + mix((n >> 8) & 255) + mix(n & 255);
};

// Projects: a row per project and, under it, a row per sub-project. What
// was changed on a project's row since the last sync goes back to
// ScaffoldPro (and is kept); everything else is written from ScaffoldPro.
function syncProjects_(projects) {
  const ss = ss_();
  const sh = ss.getSheetByName(TABS.projects);
  const sync = ss.getSheetByName(TABS.sync);
  const width = PROJECT_HEAD.length;
  const tz = ss.getSpreadsheetTimeZone ? ss.getSpreadsheetTimeZone() : 'Asia/Hong_Kong';
  const col = {};
  PROJECT_HEAD.forEach((h, i) => { col[h] = i; });
  const last = sh.getLastRow();
  const rows = last > 1 ? sh.getRange(2, 1, last - 1, width).getValues() : [];

  // What ScaffoldPro last wrote for a project's editable cells.
  const snap = {};
  const syncRows = sync.getLastRow() > 0 ? sync.getRange(1, 1, sync.getLastRow(), 2).getValues() : [];
  syncRows.forEach((r) => { if (r[0]) { try { snap[r[0]] = JSON.parse(r[1]); } catch (e) { /* ignore */ } } });

  const changes = [];
  const sheetWins = {};
  const keptNotes = {};   // a sub-project's notes: the sheet's own
  rows.forEach((r) => {
    const id = str_(r[col['ID']]);
    if (!id) return;
    if (id.indexOf('#') >= 0) { keptNotes[id] = r[col['Notes']]; return; }
    const before = snap[id];
    if (!before) return;
    Object.keys(EDITABLE).forEach((h) => {
      const field = EDITABLE[h];
      const now = str_(r[col[h]]);
      if (now !== str_(before[field])) {
        changes.push({ projectId: id, field: field, value: now });
        (sheetWins[id] = sheetWins[id] || {})[field] = now;
      }
    });
  });

  const out = [];
  const kinds = [];     // 'p' or 's' for each row written
  const sorted = projects.slice().sort((a, b) => str_(b.number).localeCompare(str_(a.number), undefined, { numeric: true }));
  sorted.forEach((p) => {
    const wins = sheetWins[p.id] || {};
    const row = new Array(width).fill('');
    row[col['Ref']] = p.number;
    row[col['Name']] = p.name;
    row[col['Client · Site']] = [p.client, p.site].filter(Boolean).join(' · ');
    row[col['Stage']] = 'status' in wins ? wins.status : (p.status || '');
    row[col['Letters']] = lines_(p.letters);
    row[col['Last Update']] = when_(p.lastActivity, p.lastBy, tz);
    row[col['Notes']] = 'internalNotes' in wins ? wins.internalNotes : (p.internalNotes || '');
    row[col['ID']] = p.id;
    out.push(row); kinds.push('p');
    (p.subs || []).forEach((s) => {
      const sid = p.id + '#' + s.key;
      const sub = new Array(width).fill('');
      sub[col['Ref']] = '↳ ' + s.ref;
      sub[col['Name']] = s.title || '';
      sub[col['Stage']] = s.stage || '';
      sub[col['BOQ']] = lines_(s.boqs);
      sub[col['Quotations']] = lines_(s.quotations);
      sub[col['Delivery Notes']] = lines_(s.deliveryNotes);
      sub[col['Invoices']] = lines_(s.invoices);
      sub[col['Last Update']] = when_(s.updated, s.updatedBy, tz);
      sub[col['Notes']] = sid in keptNotes ? keptNotes[sid] : '';
      sub[col['ID']] = sid;
      out.push(sub); kinds.push('s');
    });
  });

  // Written only when something is different (no edit history every minute).
  const norm = (rs) => JSON.stringify(rs.map((r) => r.map((v) => (v instanceof Date ? v.getTime() : str_(v)))));
  if (norm(out) !== norm(rows)) {
    if (rows.length) sh.getRange(2, 1, rows.length, width).clearContent().setBackground(null).setFontWeight(null).setDataValidation(null);
    try { sh.getRange(2, 1, Math.max(sh.getMaxRows() - 1, 1), 1).shiftRowGroupDepth(-8); } catch (e) { /* no groups */ }
    if (out.length) {
      sh.getRange(2, 1, out.length, width).setValues(out);
      lookOf_(sh, kinds, width);
    }
  }

  // Remember what ScaffoldPro and the sheet now agree on (projects' rows).
  const snapRows = out.filter((r, i) => kinds[i] === 'p').map((r) => {
    const o = {};
    Object.keys(EDITABLE).forEach((h) => { o[EDITABLE[h]] = str_(r[col[h]]); });
    return [str_(r[col['ID']]), JSON.stringify(o)];
  });
  sync.clearContents();
  if (snapRows.length) sync.getRange(1, 1, snapRows.length, 2).setValues(snapRows);
  return changes;
}

// Projects shaded and bold, with the Stage list; their sub-projects
// grouped under them (to fold away).
function lookOf_(sh, kinds, width) {
  const n = kinds.length;
  const bg = kinds.map((k) => new Array(width).fill(k === 'p' ? PROJECT_BG : null));
  const weight = kinds.map((k) => new Array(width).fill(k === 'p' ? 'bold' : 'normal'));
  const colour = kinds.map((k) => new Array(width).fill(k === 'p' ? '#1f2a44' : '#3c4043'));
  // Each document in its kind's colour (a soft tint behind, the colour in the text).
  const body = sh.getRange(2, 1, n, width);
  const values = body.getValues();
  Object.keys(DOC_COLOURS).forEach((h) => {
    const c = PROJECT_HEAD.indexOf(h);
    for (let r = 0; r < n; r++) {
      if (!str_(values[r][c])) continue;
      if (kinds[r] === 's') bg[r][c] = tint_(DOC_COLOURS[h], 0.88);
      colour[r][c] = DOC_COLOURS[h];
    }
  });
  body.setBackgrounds(bg).setFontWeights(weight).setFontColors(colour);
  body.setBorder(null, null, null, null, null, true, LINE, SpreadsheetApp.BorderStyle.SOLID);
  const rule = SpreadsheetApp.newDataValidation().requireValueInList(STATUSES, true).setAllowInvalid(true).build();
  sh.getRange(2, PROJECT_HEAD.indexOf('Stage') + 1, n, 1).setDataValidations(kinds.map((k) => [k === 'p' ? rule : null]));
  let i = 0;
  while (i < n) {
    if (kinds[i] !== 'p') { i++; continue; }
    let j = i + 1;
    while (j < n && kinds[j] === 's') j++;
    if (j > i + 1) { try { sh.getRange(i + 3, 1, j - i - 1, 1).shiftRowGroupDepth(1); } catch (e) { /* no groups */ } }
    i = j;
  }
}

// Activity: ScaffoldPro's entries not in the sheet yet go in at the top;
// rows typed in by hand get an ID and go back to ScaffoldPro.
function syncActivity_(entries) {
  const sh = ss_().getSheetByName(TABS.activity);
  const width = ACTIVITY_HEAD.length;
  const col = {};
  ACTIVITY_HEAD.forEach((h, i) => { col[h] = i; });
  const last = sh.getLastRow();
  const values = last > 1 ? sh.getRange(2, 1, last - 1, width).getValues() : [];
  const seen = new Set();
  const typed = [];
  values.forEach((r, k) => {
    const id = str_(r[col['ID']]);
    if (id) { seen.add(id); return; }
    const what = str_(r[col['What']]);
    if (!what) return;
    const row = k + 2;
    const newId = 'sheet-' + Utilities.getUuid().replace(/-/g, '').slice(0, 16);
    let when = r[col['When']];
    if (!(when instanceof Date) || isNaN(when)) {
      const parsed = when ? new Date(when) : null;
      when = parsed && !isNaN(parsed) ? parsed : new Date();
      sh.getRange(row, col['When'] + 1).setValue(when);
    }
    sh.getRange(row, col['ID'] + 1).setValue(newId);
    seen.add(newId);
    // "26212 GL-28 Works" or "26212-001": the project code is the first number.
    const project = (str_(r[col['Project']]).match(/\d{4,}/) || [''])[0];
    typed.push({ id: newId, when: when.toISOString(), who: str_(r[col['Who']]), project: project, what: what, reference: '' });
  });

  const fresh = entries.filter((e) => e.id && !seen.has(e.id))
    .sort((a, b) => String(b.when).localeCompare(String(a.when)));
  if (fresh.length) {
    const rows = fresh.map((e) => [
      date_(e.when), e.who || '',
      [e.project, e.projectName].filter(Boolean).join(' '),
      [e.what, e.reference].filter(Boolean).join(' — ') + (e.from === 'Google Sheets' ? ' (in the sheet)' : ''),
      e.id,
    ]);
    sh.insertRowsBefore(2, rows.length);
    sh.getRange(2, 1, rows.length, width).setValues(rows).setBackground(null).setFontWeight('normal');
    sh.getRange(2, 1, rows.length, 1).setNumberFormat(DATE_FORMAT);
    // Newest first, even when another Mac's work arrives late.
    sh.getRange(2, 1, sh.getLastRow() - 1, width).sort({ column: col['When'] + 1, ascending: false });
  }
  const extra = sh.getLastRow() - 1 - KEEP_ACTIVITY_ROWS;
  if (extra > 0) sh.deleteRows(KEEP_ACTIVITY_ROWS + 2, extra);
  return typed;
}

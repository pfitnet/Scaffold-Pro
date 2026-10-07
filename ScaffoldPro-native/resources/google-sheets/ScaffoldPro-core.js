/**
 * ScaffoldPro ⇄ Google Sheets — the core
 *
 * Lays out and fills the sheet's tabs (Overview, Projects, Activity). It
 * isn't pasted anywhere: the loader in the sheet's Apps Script
 * (ScaffoldPro.gs) fetches this file from ScaffoldPro's repository on
 * GitHub — again every 10 minutes, and at once when Sync Now is pressed in
 * ScaffoldPro — so a change here reaches the sheet by itself.
 *
 * It uses the loader's ss_() (the sheet) and ends with ScaffoldProCore,
 * what the loader calls. Only SpreadsheetApp, PropertiesService and
 * Utilities are used: anything needing another Google permission would
 * have to go in the loader.
 */

// The tabs' layout. A sheet made with an older layout is rebuilt in this one.
// (Also shown in ScaffoldPro as the sheet's version.)
const LAYOUT = '3';
const TABS = { overview: 'Overview', activity: 'Activity', projects: 'Projects', sync: '_sync' };
const ACTIVITY_HEAD = ['When', 'Who', 'Project', 'What', 'ID'];
const PROJECT_HEAD = ['Ref', 'Project', 'Client · Site', 'Stage', 'BOQ', 'Quotation', 'Delivery Note', 'Invoice', 'Letters', 'Next Step', 'Last Update', 'Notes', 'ID'];
const PROJECT_WIDTHS = [80, 330, 250, 105, 82, 92, 108, 88, 74, 210, 130, 220, 60];
// Short cells are centred; text reads from the left.
const PROJECT_ALIGN = ['center', 'left', 'left', 'center', 'center', 'center', 'center', 'center', 'center', 'left', 'center', 'left', 'left'];
// On a project's row these go back into ScaffoldPro.
const EDITABLE = { 'Stage': 'status', 'Notes': 'internalNotes' };
const STATUSES = ['Planning', 'Quotation', 'Active', 'On Hold', 'Completed', 'Archived'];
// The progress cells, each in ScaffoldPro's colour for that kind of document
// (the payload's list for it in brackets).
const STEPS = [['BOQ', 'boqs', '#3f938b'], ['Quotation', 'quotations', '#5374b8'], ['Delivery Note', 'deliveryNotes', '#b0843f'],
  ['Invoice', 'invoices', '#5d9150'], ['Letters', 'letters', '#8a6cb0']];
const STATUS_COLOURS = { Planning: '#8b6cf0', Quotation: '#c98a14', Active: '#2a8a4a', 'On Hold': '#e0793a', Completed: '#3a66f0', Archived: '#9196a3' };
// In Activity, a line about a document is tinted in that document's colour.
const ACTIVITY_KINDS = [['\\bQt\\d', '#5374b8'], ['\\bBQ\\d', '#3f938b'], ['\\bDN\\d', '#b0843f'], ['\\bH\\d{4}', '#5d9150'], ['\\bP?L\\d', '#8a6cb0']];
// Backups and undo / redo aren't work: never shown.
const NOISE = /backup made|^undone:|^redone:|^restored from/i;
const KEEP_ACTIVITY_ROWS = 20000;
const DATE_FORMAT = 'd mmm yyyy h:mm';
const HEAD_BG = '#1f2a44', HEAD_FG = '#ffffff', PROJECT_BG = '#eef2fb', LINE = '#e3e6ec', PROJECT_LINE = '#b9c2d3';
const INK = '#202124', SOFT = '#80868b', FAINT = '#b0b5bb';

// ---------------------------------------------------------------- tabs

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
  // The empty first tab a new spreadsheet comes with.
  ['Sheet1', '工作表1'].forEach((name) => {
    const extra = ss.getSheetByName(name);
    if (extra && extra.getLastRow() === 0 && extra.getLastColumn() === 0 && ss.getSheets().length > 1) ss.deleteSheet(extra);
  });
  if (fresh) {
    migrateActivity_(act);
    // The Projects tab is written again in full by the next sync.
    try { prj.getDataRange().clearNote().setDataValidation(null); } catch (e) { /* empty */ }
    prj.clear();
    try { prj.getRange(1, 1, prj.getMaxRows(), 1).shiftRowGroupDepth(-8); } catch (e) { /* no groups */ }
    sync.clearContents();
  }
  const head = (sh, cols, widths, align) => {
    if (sh.getRange(1, 1).getValue() !== cols[0] || fresh) {
      if (sh.getMaxColumns() < cols.length) sh.insertColumnsAfter(sh.getMaxColumns(), cols.length - sh.getMaxColumns());
      try { sh.showColumns(1, sh.getMaxColumns()); } catch (e) { /* none hidden */ }
      sh.getRange(1, 1, 1, sh.getMaxColumns()).clear();
      sh.getRange(1, 1, 1, cols.length).setValues([cols]).setFontWeight('bold').setBackground(HEAD_BG).setFontColor(HEAD_FG)
        .setVerticalAlignment('middle').setHorizontalAlignments([align]);
      sh.setRowHeight(1, 32);
      sh.setFrozenRows(1);
      widths.forEach((w, i) => sh.setColumnWidth(i + 1, w));
      // The ID column is ScaffoldPro's: hidden.
      sh.hideColumns(cols.length);
      return true;
    }
    return false;
  };
  head(act, ACTIVITY_HEAD, [140, 100, 260, 520, 60], ['center', 'center', 'left', 'left', 'left']);
  // The progress headings in their documents' colours.
  if (head(prj, PROJECT_HEAD, PROJECT_WIDTHS, PROJECT_ALIGN)) {
    STEPS.forEach(([h, , colour]) => prj.getRange(1, PROJECT_HEAD.indexOf(h) + 1).setBackground(colour).setFontColor('#ffffff'));
  }
  prj.setFrozenColumns(2);
  try { prj.setRowGroupControlPosition(SpreadsheetApp.GroupControlTogglePosition.BEFORE); } catch (e) { /* older API */ }
  if (fresh) {
    // Activity: one line a row, the time and person centred.
    const rows = Math.max(act.getMaxRows() - 1, 1);
    act.getRange(2, 1, rows, 4).setVerticalAlignment('middle').setWrapStrategy(SpreadsheetApp.WrapStrategy.CLIP);
    act.getRange(2, 1, rows, 2).setHorizontalAlignment('center');
    act.getRange(2, 1, rows, 1).setNumberFormat(DATE_FORMAT).setFontColor(SOFT);
    try { act.setRowHeightsForced(2, rows, 24); } catch (e) { /* older API */ }
    props.setProperty('COLOURED', '');
    props.setProperty('LAYOUT', LAYOUT);
  }
}

// Activity from an older layout: the old columns (When, Who, Project,
// Project Name, What, Reference, From, ID) put into the new ones, and
// backups and undo / redo taken out.
function migrateActivity_(sh) {
  const values = sh.getDataRange().getValues();
  const head = values[0].map(str_);
  const c = {}; head.forEach((h, i) => { c[h] = i; });
  const get = (r, h) => (c[h] >= 0 ? r[c[h]] : '');
  if (head.indexOf('What') < 0) return;
  const old = head.indexOf('Project Name') >= 0 || head.indexOf('Reference') >= 0;
  const rows = values.slice(1).filter((r) => !NOISE.test(str_(get(r, 'What')))).map((r) => [
    get(r, 'When'), str_(get(r, 'Who')),
    old ? [str_(get(r, 'Project')), str_(get(r, 'Project Name'))].filter(Boolean).join(' ') : str_(get(r, 'Project')),
    old ? [str_(get(r, 'What')), str_(get(r, 'Reference'))].filter(Boolean).join(' — ') : str_(get(r, 'What')),
    str_(get(r, 'ID')),
  ]);
  sh.clear();
  try { sh.showColumns(1, sh.getMaxColumns()); } catch (e) { /* none hidden */ }
  if (rows.length) sh.getRange(2, 1, rows.length, ACTIVITY_HEAD.length).setValues(rows);
}

// A column's letter (1 → A).
const letter_ = (n) => { let s = ''; for (; n > 0; n = Math.floor((n - 1) / 26)) s = String.fromCharCode(65 + (n - 1) % 26) + s; return s; };
const colOf_ = (h) => letter_(PROJECT_HEAD.indexOf(h) + 1);

// Projects: each project's stage in its colour, and who last worked on
// it in theirs.
function stageColours_(sh, people) {
  const stage = sh.getRange(colOf_('Stage') + '2:' + colOf_('Stage'));
  const rules = Object.keys(STATUS_COLOURS).map((st) => SpreadsheetApp.newConditionalFormatRule().whenTextEqualTo(st)
    .setBackground(tint_(STATUS_COLOURS[st], 0.82)).setFontColor(STATUS_COLOURS[st]).setBold(true).setRanges([stage]).build());
  const last = sh.getRange(colOf_('Last Update') + '2:' + colOf_('Last Update'));
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
  const id = colOf_('ID'), stage = colOf_('Stage');
  sh.getRange('A1').setValue('ScaffoldPro — Overview').setFontSize(16).setFontWeight('bold');
  sh.getRange('A2').setValue('Last synced').setFontColor(SOFT);
  sh.getRange('B2').setHorizontalAlignment('left').setFontColor(SOFT);
  sh.getRange('A4').setValue('Who did what — last 7 days').setFontWeight('bold');
  sh.getRange('A5').setFormula('=IFERROR(QUERY(Activity!A2:D, "select B, count(D) where A >= date \'"&TEXT(TODAY()-7,"yyyy-mm-dd")&"\' and B <> \'\' group by B order by count(D) desc label B \'Who\', count(D) \'Things done\'", 0), "Nothing yet")');
  sh.getRange('D4').setValue('Projects by stage').setFontWeight('bold');
  sh.getRange('D5').setFormula('=IFERROR(QUERY(Projects!A2:' + id + ', "select ' + stage + ', count(A) where ' + id + ' <> \'\' and not ' + id + ' contains \'#\' group by ' + stage + ' label ' + stage + ' \'Stage\', count(A) \'Projects\'", 0), "Nothing yet")');
  sh.getRange('G4').setValue('Latest work').setFontWeight('bold');
  sh.getRange('G5').setFormula('=IFERROR(QUERY(Activity!A2:D, "select A, B, C, D where D <> \'\' order by A desc limit 25 label A \'When\', B \'Who\', C \'Project\', D \'What\'", 0), "Nothing yet")');
  sh.getRange('G6:G').setNumberFormat(DATE_FORMAT);
  ['A5:B5', 'D5:E5', 'G5:J5'].forEach((a) => sh.getRange(a).setFontWeight('bold').setFontColor(SOFT).setBorder(null, null, true, null, null, null, LINE, SpreadsheetApp.BorderStyle.SOLID));
  // Numbers, times and names centred; the rest from the left.
  ['B5:B', 'E5:E', 'G5:H'].forEach((a) => sh.getRange(a).setHorizontalAlignment('center'));
  sh.getRange('A1:J').setVerticalAlignment('middle');
  sh.getRange('I6:J').setWrapStrategy(SpreadsheetApp.WrapStrategy.CLIP);
  [180, 90, 30, 110, 80, 30, 140, 100, 260, 420].forEach((w, i) => sh.setColumnWidth(i + 1, w));
  ss.setActiveSheet(sh);
  ss.moveActiveSheet(1);
}

// ---------------------------------------------------------------- helpers

const str_ = (v) => (v === null || v === undefined ? '' : String(v)).trim();
const date_ = (iso) => { const d = iso ? new Date(iso) : null; return d && !isNaN(d) ? d : ''; };
// "7 Oct · William" (the year only when it isn't this year's).
const when_ = (iso, who, tz) => {
  const d = date_(iso);
  if (!d) return who || '';
  const zone = tz || 'Asia/Hong_Kong';
  const sameYear = Utilities.formatDate(d, zone, 'yyyy') === Utilities.formatDate(new Date(), zone, 'yyyy');
  return Utilities.formatDate(d, zone, sameYear ? 'd MMM' : 'd MMM yyyy') + (who ? ' · ' + who : '');
};
// A colour mixed with white: amount 0 (the colour) … 1 (white).
const tint_ = (hex, amount) => {
  const n = parseInt(String(hex).replace('#', ''), 16);
  const mix = (c) => Math.round(c + (255 - c) * amount).toString(16).padStart(2, '0');
  return '#' + mix((n >> 16) & 255) + mix((n >> 8) & 255) + mix(n & 255);
};

// ---------------------------------------------------------------- progress

// "Qt26212-001 · Issued · client signed" → its number, status and note.
const doc_ = (s) => { const p = str_(s).split(' · '); return { no: p[0], status: p[1] || '', flag: p[2] || '' }; };

// What a document's status reads as in its progress cell, and how far it
// has got: 0 cancelled, 1 draft, 2 out (issued, sent, delivered), 3 finished.
function look_(field, d) {
  const st = d.status;
  if (/^(Cancelled|Void|Superseded)$/i.test(st)) return { label: 'Cancelled', level: 0 };
  if (/^(Rejected|Declined|Lost)$/i.test(st)) return { label: st, level: 0, bad: true };
  if (/^draft$/i.test(st) || !st) return { label: 'Draft', level: 1 };
  if (field === 'quotations') {
    if (d.flag === 'client signed') return { label: 'Signed', level: 3 };
    if (/^accepted$/i.test(st)) return { label: 'Accepted', level: 3 };
    return { label: st === 'Issued' ? 'Sent' : st, level: 2 };
  }
  if (field === 'deliveryNotes') return { label: d.flag === 'signed' ? 'Signed' : st === 'Issued' ? 'Delivered' : st, level: d.flag === 'signed' ? 3 : 2 };
  if (field === 'invoices') {
    if (/^paid$/i.test(st)) return { label: 'Paid', level: 3 };
    if (/^overdue$/i.test(st)) return { label: 'Overdue', level: 2, bad: true };
    return { label: st, level: 2 };
  }
  return { label: st, level: 2 };
}

// One cell: the furthest of its documents ("Sent", "Draft (2)"), the
// numbers for its note, and how far → { label, level, bad, note }.
function step_(field, list) {
  const docs = (list || []).map(doc_).filter((d) => d.no);
  if (!docs.length) return { label: '', level: -1, note: '' };
  const looks = docs.map((d) => look_(field, d));
  const best = looks.reduce((a, b) => (b.level > a.level || (b.level === a.level && b.bad) ? b : a));
  const live = looks.filter((l) => l.level > 0).length;
  return {
    label: best.label + (live > 1 ? ' (' + live + ')' : ''), level: best.level, bad: !!best.bad,
    note: docs.map((d) => d.no + ' — ' + [d.status, d.flag].filter(Boolean).join(', ')).join('\n'),
  };
}

// What's next for a sub-project, in plain words, and whether it's waiting
// on someone else.
function next_(cells) {
  const at = (field) => cells[field] || { level: -1 };
  const inv = at('invoices'), dn = at('deliveryNotes'), q = at('quotations'), boq = at('boqs');
  const all = [inv, dn, q, boq].filter((c) => c.level >= 0);
  if (!all.length) return { text: '' };
  if (all.every((c) => c.level === 0)) return { text: 'Cancelled', quiet: true };
  if (inv.level === 3) return { text: 'Done', done: true };
  if (inv.level === 2) return { text: inv.bad ? 'Chase payment (overdue)' : 'Waiting for payment', waiting: true, bad: inv.bad };
  if (inv.level === 1) return { text: 'Issue the invoice' };
  if (dn.level >= 2) return { text: 'Invoice it' };
  if (dn.level === 1) return { text: 'Deliver' };
  if (q.level === 3) return { text: 'Deliver' };
  if (q.level === 2) return { text: 'Waiting for the client', waiting: true };
  if (q.level === 1) return { text: 'Send the quotation' };
  if (q.level === 0) return { text: 'Quotation ' + q.label.toLowerCase(), quiet: true, bad: q.bad };
  if (boq.level >= 2) return { text: 'Make the quotation' };
  return { text: 'Finish the BOQ' };
}

// A project's row: how many of its sub-projects have each kind of document
// out ("3 of 8"), and what most of them are waiting for.
function summary_(subCells) {
  const out = {};
  STEPS.forEach(([, field]) => {
    if (field === 'letters') return;
    const have = subCells.filter((c) => c.cells[field].level >= 1);
    const done = have.filter((c) => c.cells[field].level >= 2).length;
    out[field] = have.length ? { label: done + ' of ' + have.length, level: done === 0 ? 1 : done === have.length ? 2 : 1.5, note: '' } : { label: '', level: -1, note: '' };
  });
  const counts = {};
  subCells.forEach((c) => { if (c.next.text && !c.next.done && !c.next.quiet) counts[c.next.text] = (counts[c.next.text] || 0) + 1; });
  const top = Object.keys(counts).sort((a, b) => counts[b] - counts[a]);
  const done = subCells.filter((c) => c.next.done).length;
  let text = top.slice(0, 2).map((t) => t + (counts[t] > 1 ? ' ×' + counts[t] : '')).join(' · ') + (top.length > 2 ? ' …' : '');
  if (!text && done) text = 'Done';
  return { cells: out, next: { text: text, done: !top.length && done > 0, note: top.map((t) => counts[t] + ' × ' + t).join('\n') } };
}

// A sub-project's name without its project's name in front:
// "Batch 3 of Materials - Rental - GL-18 …" → "Rental - GL-18 …".
function shortTitle_(title, projectName) {
  const t = str_(title), p = str_(projectName);
  if (!p || t.toLowerCase().indexOf(p.toLowerCase()) !== 0) return t;
  return t.slice(p.length).replace(/^[\s\-–—:·,]+/, '') || t;
}

// ---------------------------------------------------------------- projects

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
  const range = last > 1 ? sh.getRange(2, 1, last - 1, width) : null;
  const rows = range ? range.getValues() : [];
  const oldNotes = range ? range.getNotes() : [];

  // What ScaffoldPro last wrote for a project's editable cells.
  const snap = {};
  const syncRows = sync.getLastRow() > 0 ? sync.getRange(1, 1, sync.getLastRow(), 2).getValues() : [];
  syncRows.forEach((r) => { if (r[0]) { try { snap[r[0]] = JSON.parse(r[1]); } catch (e) { /* ignore */ } } });

  const changes = [];
  const sheetWins = {};
  const keptNotes = {};   // a sub-project's notes: the sheet's own
  const folded = {};      // projects whose sub-projects are folded away
  rows.forEach((r, k) => {
    const id = str_(r[col['ID']]);
    if (!id) return;
    if (id.indexOf('#') >= 0) { keptNotes[id] = r[col['Notes']]; return; }
    const next = rows[k + 1];
    if (next && str_(next[col['ID']]).indexOf(id + '#') === 0) {
      try { if (sh.getRowGroup(k + 3, 1).isCollapsed()) folded[id] = true; } catch (e) { /* no group */ }
    }
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

  const out = [];     // the cells' values
  const looks = [];   // per row: { kind, cells, next }
  const sorted = projects.slice().sort((a, b) => str_(b.number).localeCompare(str_(a.number), undefined, { numeric: true }));
  sorted.forEach((p) => {
    const wins = sheetWins[p.id] || {};
    const subs = (p.subs || []).map((s) => {
      const cells = {};
      STEPS.forEach(([, field]) => { cells[field] = field === 'letters' ? { label: '', level: -1, note: '' } : step_(field, s[field]); });
      return { s: s, cells: cells, next: next_(cells) };
    });
    const sum = summary_(subs);
    sum.cells.letters = step_('letters', p.letters);
    const row = new Array(width).fill('');
    row[col['Ref']] = p.number;
    row[col['Project']] = p.name;
    row[col['Client · Site']] = [p.client, p.site].filter(Boolean).join(' · ');
    row[col['Stage']] = 'status' in wins ? wins.status : (p.status || '');
    STEPS.forEach(([h, field]) => { row[col[h]] = sum.cells[field].label; });
    row[col['Next Step']] = sum.next.text;
    row[col['Last Update']] = when_(p.lastActivity, p.lastBy, tz);
    row[col['Notes']] = 'internalNotes' in wins ? wins.internalNotes : (p.internalNotes || '');
    row[col['ID']] = p.id;
    out.push(row); looks.push({ kind: 'p', cells: sum.cells, next: sum.next, id: p.id });
    subs.forEach(({ s, cells, next }) => {
      const sid = p.id + '#' + s.key;
      const sub = new Array(width).fill('');
      sub[col['Ref']] = str_(s.ref).replace(str_(p.number), '').trim() || s.ref;
      sub[col['Project']] = shortTitle_(s.title, p.name);
      STEPS.forEach(([h, field]) => { sub[col[h]] = cells[field].label; });
      sub[col['Next Step']] = next.text;
      sub[col['Last Update']] = when_(s.updated, s.updatedBy, tz);
      sub[col['Notes']] = sid in keptNotes ? keptNotes[sid] : '';
      sub[col['ID']] = sid;
      out.push(sub); looks.push({ kind: 's', cells: cells, next: next });
    });
  });
  // On hover: the document numbers behind each progress cell, and names
  // cut short.
  const notes = looks.map((l, k) => PROJECT_HEAD.map((h) => {
    const step = STEPS.find((st) => st[0] === h);
    if (step) return l.cells[step[1]].note || '';
    if (h === 'Next Step' && l.kind === 'p') return l.next.note || '';
    // A name too long for its cell, in full.
    if (h === 'Project' || h === 'Client · Site') { const v = str_(out[k][col[h]]); return v.length > 44 ? v : ''; }
    return '';
  }));

  // Written only when something is different (no edit history every minute).
  const norm = (rs) => JSON.stringify(rs.map((r) => r.map((v) => (v instanceof Date ? v.getTime() : str_(v)))));
  if (norm(out) !== norm(rows) || norm(notes) !== norm(oldNotes)) {
    if (range) range.clearContent().clearNote().clearFormat().setDataValidation(null);
    try { sh.getRange(2, 1, Math.max(sh.getMaxRows() - 1, 1), 1).shiftRowGroupDepth(-8); } catch (e) { /* no groups */ }
    if (out.length) {
      sh.getRange(2, 1, out.length, width).setValues(out).setNotes(notes);
      lookOf_(sh, looks, folded);
    }
  }

  // Remember what ScaffoldPro and the sheet now agree on (projects' rows).
  const snapRows = out.filter((r, i) => looks[i].kind === 'p').map((r) => {
    const o = {};
    Object.keys(EDITABLE).forEach((h) => { o[EDITABLE[h]] = str_(r[col[h]]); });
    return [str_(r[col['ID']]), JSON.stringify(o)];
  });
  sync.clearContents();
  if (snapRows.length) sync.getRange(1, 1, snapRows.length, 2).setValues(snapRows);
  return changes;
}

// How the Projects tab looks: one line a row; each project shaded and bold
// with a line above it and the Stage list, its sub-projects under it
// (folding away); the progress cells filling in with their document's
// colour as the work goes out; Next Step in plain words.
function lookOf_(sh, looks, folded) {
  const n = looks.length;
  const width = PROJECT_HEAD.length;
  const col = {};
  PROJECT_HEAD.forEach((h, i) => { col[h] = i; });
  const body = sh.getRange(2, 1, n, width);
  const bg = [], ink = [], weight = [], style = [];
  looks.forEach((l) => {
    const p = l.kind === 'p';
    const b = new Array(width).fill(p ? PROJECT_BG : null);
    const c = new Array(width).fill(p ? INK : '#3c4043');
    const w = new Array(width).fill('normal');
    const s = new Array(width).fill('normal');
    if (p) { w[col['Ref']] = 'bold'; w[col['Project']] = 'bold'; c[col['Client · Site']] = '#5f6368'; } else { c[col['Ref']] = SOFT; }
    c[col['Last Update']] = SOFT;
    STEPS.forEach(([h, field, colour]) => {
      const cell = l.cells[field], i = col[h];
      if (!cell || cell.level < 0) return;
      if (cell.level === 0) { c[i] = cell.bad ? '#c5221f' : FAINT; s[i] = 'italic'; return; }
      if (cell.level === 1) { c[i] = FAINT; return; }          // draft: barely there
      if (cell.level === 1.5) { b[i] = tint_(colour, 0.88); c[i] = colour; w[i] = 'bold'; return; }
      b[i] = tint_(colour, cell.level >= 3 ? 0.55 : 0.75);       // out: filled in, deeper once finished
      c[i] = cell.bad ? '#c5221f' : colour;
      w[i] = 'bold';
    });
    const nx = l.next || {};
    const i = col['Next Step'];
    if (nx.done) { c[i] = '#1e7e34'; w[i] = 'bold'; } else if (nx.bad) { c[i] = '#c5221f'; } else if (nx.waiting || nx.quiet) { c[i] = SOFT; s[i] = 'italic'; } else { c[i] = INK; }
    bg.push(b); ink.push(c); weight.push(w); style.push(s);
  });
  body.setBackgrounds(bg).setFontColors(ink).setFontWeights(weight).setFontStyles(style)
    .setVerticalAlignment('middle').setHorizontalAlignments(looks.map(() => PROJECT_ALIGN))
    .setWrapStrategy(SpreadsheetApp.WrapStrategy.CLIP);
  try { sh.setRowHeightsForced(2, n, 26); } catch (e) { sh.setRowHeights(2, n, 26); }
  body.setBorder(null, null, null, null, null, true, LINE, SpreadsheetApp.BorderStyle.SOLID);
  const tops = [];
  looks.forEach((l, r) => { if (l.kind === 'p') tops.push('A' + (r + 2) + ':' + letter_(width) + (r + 2)); });
  if (tops.length) sh.getRangeList(tops).setBorder(true, null, null, null, null, null, PROJECT_LINE, SpreadsheetApp.BorderStyle.SOLID);
  const rule = SpreadsheetApp.newDataValidation().requireValueInList(STATUSES, true).setAllowInvalid(true).build();
  sh.getRange(2, col['Stage'] + 1, n, 1).setDataValidations(looks.map((l) => [l.kind === 'p' ? rule : null]));
  // Sub-projects grouped under their project; folded ones stay folded.
  let i = 0;
  while (i < n) {
    if (looks[i].kind !== 'p') { i++; continue; }
    let j = i + 1;
    while (j < n && looks[j].kind === 's') j++;
    if (j > i + 1) {
      try {
        sh.getRange(i + 3, 1, j - i - 1, 1).shiftRowGroupDepth(1);
        if (folded[looks[i].id]) sh.getRowGroup(i + 3, 1).collapse();
      } catch (e) { /* no groups */ }
    }
    i = j;
  }
}

// ---------------------------------------------------------------- activity

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

  // (An older ScaffoldPro still sends backups and undo: left out here too.)
  const fresh = entries.filter((e) => e.id && !seen.has(e.id) && !NOISE.test(str_(e.what)))
    .sort((a, b) => String(b.when).localeCompare(String(a.when)));
  if (fresh.length) {
    const rows = fresh.map((e) => [
      date_(e.when), e.who || '',
      [e.project, e.projectName].filter(Boolean).join(' '),
      [e.what, e.reference].filter(Boolean).join(' — ') + (e.from === 'Google Sheets' ? ' (in the sheet)' : ''),
      e.id,
    ]);
    sh.insertRowsBefore(2, rows.length);
    const added = sh.getRange(2, 1, rows.length, width);
    added.setValues(rows).setBackground(null).setFontWeight('normal').setFontColor('#3c4043').setFontStyle('normal')
      .setVerticalAlignment('middle').setHorizontalAlignments(rows.map(() => ['center', 'center', 'left', 'left', 'left']))
      .setWrapStrategy(SpreadsheetApp.WrapStrategy.CLIP).setBorder(false, false, false, false, false, false);
    sh.getRange(2, 1, rows.length, 1).setNumberFormat(DATE_FORMAT).setFontColor(SOFT);
    try { sh.setRowHeightsForced(2, rows.length, 24); } catch (e) { /* older API */ }
    // Newest first, even when another Mac's work arrives late.
    sh.getRange(2, 1, sh.getLastRow() - 1, width).sort({ column: col['When'] + 1, ascending: false });
  }
  const extra = sh.getLastRow() - 1 - KEEP_ACTIVITY_ROWS;
  if (extra > 0) sh.deleteRows(KEEP_ACTIVITY_ROWS + 2, extra);
  return typed;
}

// ---------------------------------------------------------------- what the loader calls

// The tabs made (or brought up to this layout), coloured, and the Overview.
function setupTabs_() {
  ensureTabs_();
  colours_(JSON.parse(PropertiesService.getScriptProperties().getProperty('PEOPLE') || '{}'));
  buildOverview_();
}

// A sync from ScaffoldPro: its projects and history in, the sheet's
// changes out → { changes, activity }.
function sync_(req) {
  ensureTabs_();
  colours_(req.people || {});
  const changes = syncProjects_(req.projects || []);
  const activity = syncActivity_(req.activity || []);
  const ov = ss_().getSheetByName(TABS.overview);
  if (ov) ov.getRange('B2').setValue(new Date()).setNumberFormat(DATE_FORMAT);
  return { changes: changes, activity: activity };
}

// Projects tab: just the projects (each folds its sub-projects away), or everything.
function foldAll_() { try { ss_().getSheetByName(TABS.projects).collapseAllRowGroups(); } catch (e) { /* no groups */ } }
function unfoldAll_() { try { ss_().getSheetByName(TABS.projects).expandAllRowGroups(); } catch (e) { /* no groups */ } }

var ScaffoldProCore = { layout: LAYOUT, setup: setupTabs_, sync: sync_, overview: buildOverview_, foldAll: foldAll_, unfoldAll: unfoldAll_ };

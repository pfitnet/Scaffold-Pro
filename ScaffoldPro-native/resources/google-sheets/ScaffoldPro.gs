/**
 * ScaffoldPro ⇄ Google Sheets — the loader
 *
 * Keeps a Google Sheet as an overview of who did what, and when, in
 * ScaffoldPro — and brings changes made in the sheet back into ScaffoldPro.
 *
 *   Overview  — who has done how much this week, projects by stage, the latest work
 *   Projects  — one line per project, then one per sub-project (-001, -002 …),
 *               with BOQ / Quotation / Delivery Note / Invoice cells that fill
 *               in as each goes out, and the Next Step. Change a project's
 *               Stage or Notes here and ScaffoldPro is updated.
 *   Activity  — everything done in ScaffoldPro, newest first. Type a new row
 *               and it is added to ScaffoldPro's history on the next sync.
 *
 * This loader is the only part pasted into Apps Script, once. What lays out
 * and fills the tabs (ScaffoldPro-core.js) is fetched from ScaffoldPro's
 * repository on GitHub: again every 10 minutes, and at once when Sync Now is
 * pressed in ScaffoldPro. So new layouts reach the sheet by themselves —
 * nothing to paste or deploy again.
 *
 * Setting it up (once):
 *   1. In the Google Sheet: Extensions › Apps Script (or a project at
 *      script.google.com: SHEET_URL below already points at the sheet).
 *      Replace everything there with this file and save.
 *   2. In the list next to Run / Debug, choose "setup", then press Run and
 *      allow it ("unverified app": Advanced › Go to …). It makes the tabs
 *      and shows the connection secret.
 *   3. Deploy › New deployment › Select type: Web app.
 *      Execute as: Me.   Who has access: Anyone.   Deploy, and copy the Web app URL.
 *      (Already deployed? Deploy › Manage deployments › ✏️ › New version › Deploy.)
 *   4. In ScaffoldPro: Settings › Google Sheets — paste the Web app URL and the
 *      secret, then Connect. It syncs about every minute while ScaffoldPro is open.
 *
 * The secret can be shown again from the sheet: ScaffoldPro › Connection secret
 * (or run "showSecret" and look in the Execution log).
 */

// The sheet, for a script made at script.google.com (a script opened from
// the sheet, Extensions › Apps Script, uses its own sheet and ignores this).
// ScaffoldPro › Settings › Google Sheets › Copy Script fills in the
// connected sheet's link; for another sheet, paste its link here.
const SHEET_URL = 'https://docs.google.com/spreadsheets/d/10_6_7WG4p3pV7J1DIuqfQoqcGxNII6ZUUC9E_WZaKZ8/edit';

// Where the rest of the code comes from, and how long a copy is kept
// before looking for a newer one.
const CORE_URL = 'https://raw.githubusercontent.com/pfitnet/Scaffold-Pro/main/ScaffoldPro-native/resources/google-sheets/ScaffoldPro-core.js';
const CORE_MAX_AGE = 10 * 60 * 1000;
const CORE_CHUNK = 2500;   // characters per stored piece (a property holds 9 KB; some characters take 3 bytes)

// ---------------------------------------------------------------- the menu and setup

// Runs by itself when the sheet is opened (adds the ScaffoldPro menu).
// Run from the editor it has no sheet window to add to, so it does nothing:
// choose "setup" in the list at the top instead.
function onOpen() {
  try {
    SpreadsheetApp.getUi().createMenu('ScaffoldPro')
      .addItem('Fold all projects', 'foldAll')
      .addItem('Unfold all projects', 'unfoldAll')
      .addSeparator()
      .addItem('Update the layout now', 'updateNow')
      .addItem('Rebuild Overview tab', 'rebuildOverview')
      .addItem('Connection secret', 'showSecret')
      .addToUi();
  } catch (e) {
    Logger.log('onOpen runs by itself when the sheet opens. To set things up, choose "setup" in the list at the top and press Run.');
  }
}

function setup() {
  ss_();
  const secret = secret_();
  core_(true).setup();
  const message = 'ScaffoldPro is set up in this sheet.\n\nConnection secret:\n' + secret +
    '\n\nNext: Deploy › New deployment › Web app (Execute as: Me, Who has access: Anyone), ' +
    'then paste the Web app URL and this secret into ScaffoldPro › Settings › Google Sheets.' +
    '\n(Already deployed? Deploy › Manage deployments › ✏️ › New version › Deploy.)';
  Logger.log(message);
  try { SpreadsheetApp.getUi().alert(message); } catch (e) { /* run from the editor: see the log */ }
}

function showSecret() {
  const message = 'Connection secret for ScaffoldPro › Settings › Google Sheets:\n\n' + secret_();
  Logger.log(message);
  try { SpreadsheetApp.getUi().alert(message); } catch (e) { /* run from the editor: see the log */ }
}

function foldAll() { core_().foldAll(); }
function unfoldAll() { core_().unfoldAll(); }
function rebuildOverview() { core_().overview(); }
// The newest layout from GitHub, applied to the tabs.
function updateNow() { core_(true).setup(); }

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

// ---------------------------------------------------------------- the core

let CORE = null;

// The core's functions (ScaffoldProCore). fresh: look for a newer copy on
// GitHub now, not only once the kept one is 10 minutes old.
function core_(fresh) {
  if (CORE && !fresh) return CORE;
  const props = PropertiesService.getScriptProperties();
  const kept = props.getProperties();
  const keptCode = () => {
    let code = '';
    for (let i = 0; i < Number(kept.CORE_N || 0); i++) code += kept['CORE_' + i] || '';
    return code;
  };
  const load = (code) => new Function(code + '\n;return ScaffoldProCore;')();
  if (!fresh && kept.CORE_N && Date.now() - Number(kept.CORE_AT || 0) < CORE_MAX_AGE) {
    try { return (CORE = load(keptCode())); } catch (e) { /* fetched again below */ }
  }
  let code = '';
  try {
    const res = UrlFetchApp.fetch(CORE_URL + '?t=' + Date.now(), { muteHttpExceptions: true, followRedirects: true });
    if (res.getResponseCode() === 200) code = res.getContentText();
  } catch (e) { /* offline: the kept copy below */ }
  if (code) {
    try {
      CORE = load(code);
      // Kept in pieces (a property holds 9 KB); old pieces beyond the new ones removed.
      const parts = { CORE_AT: String(Date.now()) };
      let n = 0;
      for (let i = 0; i < code.length; i += CORE_CHUNK) parts['CORE_' + n++] = code.slice(i, i + CORE_CHUNK);
      parts.CORE_N = String(n);
      props.setProperties(parts);
      for (let i = n; i < Number(kept.CORE_N || 0); i++) props.deleteProperty('CORE_' + i);
      return CORE;
    } catch (e) {
      Logger.log('The newest sheet code from GitHub didn’t load (' + e + '); keeping the one before.');
    }
  }
  if (kept.CORE_N) return (CORE = load(keptCode()));
  throw new Error('ScaffoldPro’s sheet code couldn’t be fetched from GitHub (' + CORE_URL + '). Check the internet connection and try again.');
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
    const core = core_(!!req.refresh);
    const result = core.sync(req);
    return out_({ ok: true, name: ss.getName(), url: ss.getUrl(), layout: core.layout, changes: result.changes, activity: result.activity });
  } catch (err) {
    return out_({ ok: false, error: String(err && err.message || err) });
  } finally {
    lock.releaseLock();
  }
}

function out_(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj)).setMimeType(ContentService.MimeType.JSON);
}

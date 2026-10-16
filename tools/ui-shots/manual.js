#!/usr/bin/env node
'use strict';
// Retakes the User Manual's screenshots (resources/manual/<id>.jpg) and
// records where each numbered mark is (js/manual-shots.js, as % of the
// picture). Mark numbers are 1-based in the order below; js/manual-content.js
// refers to them in each shot's `points`.
//   node tools/ui-shots/manual.js [--only dashboard,stock]
// A mark: a selector (the first match), { sel, text } (the first match whose
// text starts with `text`), or an array of those (one box around them all).
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { chromium } = require(path.join(execSync('npm root -g').toString().trim(), 'playwright'));
const ROOT = path.resolve(__dirname, '../../ScaffoldPro-native');
const { reply } = require('./mock.js');

const PD = 'project-detail.html?number=26219';
// The page scrolls inside #content (the app shell), not the window, and
// smoothly: jump there at once.
const scrollTo = (sel, gap = 24) => async (p) => {
  await p.evaluate(([s, g]) => {
    const el = document.querySelector(s);
    const box = document.getElementById('content');
    if (!el || !box) return;
    const top = el.getBoundingClientRect().top - box.getBoundingClientRect().top + box.scrollTop - g;
    box.scrollTo({ top, behavior: 'instant' });
  }, [sel, gap]);
};
const SHOTS = {
  dashboard: { url: 'index.html', marks: ['.page-actions .has-menu', '.page-actions .more-btn', '.dash-brief', '#stat-grid', '#dash-grid > section.panel', '#announce-bar', '.sidebar-tools'] },
  calendar: { url: 'calendar.html', marks: [['#cal-prev', '#cal-next'], '#cal-view', '#cal-filters', '#cal-week', '#cal-mini', '.cal-dayp', ['#cal-add', '#cal-add-event']] },
  tasks: { url: 'tasks.html?tab=tasks', h: 960, marks: ['#tk-quick', '#task-tabs', '#task-list', '#tk-hero', '#tk-week', '#tk-team', '#tt-tabs'] },
  chat: { url: 'team.html?tab=chat', marks: ['#team-tabs', '#chat-convs', '#chat-scroll', '#chat-input', '#chat-emoji-btn', '#chat-gif-btn', '#chat-attach-btn'] },
  team: { url: 'team.html?tab=people', h: 700, marks: ['#team-tabs', '#people-grid', '#tree-new-team'] },
  'team-signatures': { url: 'team.html?tab=signatures', h: 700, marks: ['#sign-incoming', '#sign-incoming button', '#sign-outgoing'] },
  costs: { url: 'price-lists.html', marks: ['#list-select', '#search-box', '#category-select', '#rates-select-btn', '#costs-head .more-btn', '#costs-head .primary', '#table-container', '#costs-tabs'] },
  'costs-manpower': { url: 'price-lists.html?tab=manpower', h: 720, marks: ['#costs-manpower table', '.mp-margin', '#mp-add-provider', '#costs-head .primary'] },
  clients: { url: 'clients.html', marks: ['#search-box', '#conn-clients', '#conn-sites', '#cs-head .more-btn', '#cs-head .split-btn', 'label.check-chip', '#cs-head .info-tip'] },
  projects: { url: 'projects.html', marks: ['#new-project-btn', '#search-box', '#pj-filters', '.pj-view', '.pj-card', '#pj-sort'] },
  'projects-overview': { url: 'projects.html?view=overview', marks: ['.ov-project', { sel: '.ov-doc', text: 'BOQ' }, { sel: '.ov-doc', text: 'Qt' }, { sel: '.ov-doc', text: 'Inv' }] },
  'project-page': { url: PD, marks: ['#pd-stages', '#status-select', '#pd-hero .split-btn', '#pd-hero .more-btn', '#tabs-main', '#pd-overview', 'nav.crumbs'] },
  'project-quotations': { url: `${PD}&tab=quotations`, h: 760, marks: ['#pd-hero .split-btn', '#quotation-list tbody tr', '#tabs', '#quotation-actions'] },
  'boq-editor': { url: 'boq-editor.html?id=doc1', h: 900, marks: ['#status-select', '#make-quotation-btn', '#export-btn', '.doc-bar .more-btn', '#boq-mode-select', '#boq-markup-input', '#search-box', '#line-items', '.doc-bar .inspector-toggle'] },
  'boq-sections': { url: 'boq-editor.html?id=doc1', setup: scrollTo('#notes-box', 120), marks: ['#notes-box', '#delivery-schedule'] },
  'quotation-editor': { url: 'quotation-editor.html?id=doc1', h: 1300, marks: ['#status-select', '#export-btn', '.doc-bar .more-btn', '.inspector .form-card', ['#doc-date-input', '#pricing-mode-select'], '#adjustment-input', '#line-items', '#search-box', '.doc-bar .inspector-toggle'] },
  'quotation-sections': { url: 'quotation-editor.html?id=doc1', h: 860, setup: scrollTo('#add-section-btn', 170), marks: ['#add-section-btn', '#totals-box', '#notes-box'] },
  'delivery-schedule': { url: 'quotation-editor.html?id=doc1', setup: scrollTo('#delivery-schedule', 60), h: 640, marks: ['#ds-add-day-btn', '#ds-export-btn', '#ds-table'] },
  'delivery-note': { url: 'delivery-note-editor.html?id=doc1', marks: ['#quotation-import', ['#doc-date-input', '#delivery-address-input'], '#contact-person-input', '#line-items', '#export-btn', '#status-select'] },
  invoice: { url: 'invoice-editor.html?id=doc1', marks: ['#source-note', ['#doc-date-input', '#due-date-input'], '#inv-signed-notes', '#line-items', '#export-btn', '#status-select'] },
  letter: { url: 'letter-editor.html?id=doc1', h: 1100, marks: ['#export-btn', '#rt-toolbar', '#paper', '#f-client', '#annex-panel', '#status-select'] },
  stock: { url: 'stock.html', marks: ['#sk-stats', '#sk-record', '#sk-tabs', '#sk-stocktake', '#sk-list', '#sk-due', '.page-actions .more-btn'] },
  accounting: { url: 'accounts.html', marks: ['#period-select', '#account-stats', '#account-tabs', '#acc-head .more-btn', '#tab-content', '#unpaid-only-label'] },
  marketing: { url: 'marketing.html', marks: ['#mk-stats', '#mk-tabs', '#mo-range', '#mo-chart', '#new-lead-btn'] },
  'marketing-leads': { url: 'marketing.html?tab=leads', h: 640, marks: ['#mk-board', '#mk-board .lead-card'] },
  'marketing-report': { url: 'marketing.html?tab=report', h: 700, marks: ['#cr-client', '#cr-period', '#cr-result', '#cr-pdf'] },
  admin: { url: 'admin.html', h: 700, marks: ['#expiring-list', '#admin-head .primary', '#admin-doc-list', '#admin-tabs'] },
  'admin-employees': { url: 'admin.html?tab=employees', h: 700, marks: ['#employee-stats', '#admin-head .more-btn', '#admin-head .primary', 'label.check-chip'] },
  settings: { url: 'settings.html#documents', marks: ['#st-search', '#st-nav-list', '#documents .st-row .st-value', '#documents .st-row .st-edit', '#documents .st-switch'] },
  user: { url: 'settings.html#you', marks: ['#you-name', '#you .st-card', '#you-swatches', '#appearance-control', '#sidebar-rail'] },
  workers: { url: 'workers.html', h: 900, marks: ['#wk-stats', '#wk-list', '.wk-next', '.wk-tabs', '#wk-paper', '#wk-new', '.wk-search'] },
  assistant: { url: 'projects.html', setup: async (p) => { await p.click('.sidebar-ask'); await p.waitForTimeout(500); await p.mouse.move(1000, 600); await p.waitForTimeout(400); }, marks: ['#as-float', '.sidebar-ask'] },
};

const arg = (k) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : null; };
const only = arg('only') ? arg('only').split(',') : Object.keys(SHOTS);

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  const shotsFile = path.join(ROOT, 'resources/manual/shots.json');
  const all = fs.existsSync(shotsFile) ? JSON.parse(fs.readFileSync(shotsFile, 'utf8')) : {};
  let problems = 0;
  for (const id of only) {
    const s = SHOTS[id];
    const W = 1440, H = s.h || 860;
    const ctx = await browser.newContext({ viewport: { width: W, height: H }, colorScheme: 'light' });
    await ctx.exposeFunction('__mockReply', (a, p) => JSON.stringify(reply(a, p)));
    await ctx.addInitScript(`window.__calls = []; window.webkit = { messageHandlers: { native: { postMessage(m) { window.__calls.push(m.action); window.__mockReply(m.action, m.payload).then((r) => setTimeout(() => window.__nativeCallback(m.id, true, r, null), 5)); } } } };
      try { sessionStorage.clear(); } catch (e) {}`);
    await ctx.addInitScript({ content: fs.readFileSync(path.join(ROOT, 'js/bridge.js'), 'utf8') });
    const p = await ctx.newPage();
    const errs = [];
    p.on('pageerror', (e) => errs.push(e.message));
    await p.goto('file://' + path.join(ROOT, s.url));
    await p.mouse.move(W - 2, H - 2);
    await p.waitForTimeout(1800); // past the count-up and the sliding marks
    if (s.setup) { await s.setup(p); await p.waitForTimeout(500); }
    const boxes = await p.evaluate((marks) => marks.map((m) => {
      const one = (spec) => {
        const sel = typeof spec === 'string' ? spec : spec.sel;
        const list = [...document.querySelectorAll(sel)].filter((e) => e.getClientRects().length);
        const el = typeof spec === 'string' ? list[0] : list.find((e) => e.textContent.trim().startsWith(spec.text));
        return el ? el.getBoundingClientRect() : null;
      };
      const rs = (Array.isArray(m) ? m : [m]).map(one).filter(Boolean);
      if (!rs.length) return null;
      const x = Math.min(...rs.map((r) => r.left)), y = Math.min(...rs.map((r) => r.top));
      return { x, y, r: Math.max(...rs.map((r) => r.right)), b: Math.max(...rs.map((r) => r.bottom)) };
    }), s.marks);
    const pct = (v, of) => Math.round((v / of) * 10000) / 100;
    const marks = boxes.map((b, i) => {
      if (!b) { problems++; console.log(`  ${id}: mark ${i + 1} not found (${JSON.stringify(s.marks[i])})`); return { x: 0, y: 0, w: 0, h: 0 }; }
      const pad = 4;
      const x = Math.max(0, b.x - pad), y = Math.max(0, b.y - pad);
      const r = Math.min(W, b.r + pad), bt = Math.min(H, b.b + pad);
      if (b.y > H || b.b < 0) { problems++; console.log(`  ${id}: mark ${i + 1} is off the picture`); }
      return { x: pct(x, W), y: pct(y, H), w: pct(r - x, W), h: pct(bt - y, H) };
    });
    await p.screenshot({ path: path.join(ROOT, `resources/manual/${id}.jpg`), type: 'jpeg', quality: 82 });
    all[id] = { w: W, h: H, marks };
    if (errs.length) { problems++; console.log(`  ${id}: page error: ${errs[0]}`); }
    console.log(`${id}: ${marks.length} marks`);
    await ctx.close();
  }
  await browser.close();
  fs.writeFileSync(shotsFile, JSON.stringify(all, null, 1) + '\n');
  fs.writeFileSync(path.join(ROOT, 'js/manual-shots.js'), `'use strict';\n\n// Where each marked control is on the manual's screenshots (resources/manual),\n// as % of the picture: made with the screenshots (tools/ui-shots/manual.js).\nwindow.MANUAL_SHOTS = ${JSON.stringify(all)};\n`);
  console.log(problems ? `${problems} problem(s)` : 'all shots taken');
})();

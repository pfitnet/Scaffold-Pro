#!/usr/bin/env node
'use strict';
// Screenshots every ScaffoldPro page with a mocked native bridge (HANDOFF §4.2).
//   node tools/ui-shots/shoot.js --out <dir> [--page projects] [--tab quotations]
//        [--vp mac|narrow|ipad|phone|all] [--scheme light|dark|both] [--routes]
// Fails (exit 1) on any page error. --routes prints the bridge routes each page called.
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');
const { chromium, devices } = require(path.join(execSync('npm root -g').toString().trim(), 'playwright'));
const ROOT = path.resolve(__dirname, '../../ScaffoldPro-native');
const { reply } = require('./mock.js');

const arg = (k, d) => { const i = process.argv.indexOf('--' + k); return i > 0 ? process.argv[i + 1] : d; };
const has = (k) => process.argv.includes('--' + k);
const OUT = arg('out', '/tmp/ui-shots');
const PAGES = arg('page') ? arg('page').split(',') : fs.readdirSync(ROOT).filter((f) => f.endsWith('.html') && !['sites.html', 'user.html'].includes(f)).map((f) => f.replace('.html', ''));
const VPS = {
  mac: { viewport: { width: 1440, height: 900 } },
  narrow: { viewport: { width: 1000, height: 760 } },
  ipad: { viewport: { width: 820, height: 1180 }, hasTouch: true, web: true },
  phone: { viewport: { width: 390, height: 844 }, isMobile: true, hasTouch: true, deviceScaleFactor: 3, web: true },
};
const vpNames = arg('vp', 'mac') === 'all' ? Object.keys(VPS) : arg('vp', 'mac').split(',');
const schemes = arg('scheme', 'both') === 'both' ? ['light', 'dark'] : [arg('scheme')];
fs.mkdirSync(OUT, { recursive: true });

(async () => {
  const browser = await chromium.launch({ executablePath: '/opt/pw-browsers/chromium-1194/chrome-linux/chrome' });
  let failed = 0;
  for (const vp of vpNames) for (const scheme of schemes) {
    const { web, ...opts } = VPS[vp];
    const ctx = await browser.newContext({ ...opts, colorScheme: scheme });
    await ctx.exposeFunction('__mockReply', (action, payload) => JSON.stringify(reply(action, payload)));
    await ctx.addInitScript(`
      ${web ? 'window.__scaffoldProWeb = true; document.documentElement.classList.add("web");' : ''}
      window.__calls = [];
      window.webkit = { messageHandlers: { native: { postMessage(m) {
        window.__calls.push(m.action);
        window.__mockReply(m.action, m.payload).then((r) => setTimeout(() => window.__nativeCallback(m.id, true, r, null), 5));
      } } } };`);
    await ctx.addInitScript({ content: fs.readFileSync(path.join(ROOT, 'js/bridge.js'), 'utf8') });
    for (const p of PAGES) {
      const page = await ctx.newPage();
      const errs = [];
      page.on('pageerror', (e) => errs.push(e.message));
      page.on('console', (m) => { if (m.type() === 'error' && !/favicon|ERR_FILE_NOT_FOUND/.test(m.text())) errs.push('console: ' + m.text()); });
      const q = arg('query', p === 'project-detail' ? '?number=26219' : /editor$/.test(p) ? '?id=doc1' : '');
      try {
        await page.goto('file://' + path.join(ROOT, p + '.html') + q);
        await page.waitForTimeout(900);
        if (arg('tab')) { await page.click(`[data-tab="${arg('tab')}"]`).catch(() => {}); await page.waitForTimeout(400); }
      } catch (e) { errs.push('nav: ' + e.message); }
      const file = path.join(OUT, `${p}${arg('tab') ? '-' + arg('tab') : ''}-${vp}-${scheme}.png`);
      await page.screenshot({ path: file, fullPage: has('full') });
      if (has('routes')) console.log(p, [...new Set(await page.evaluate(() => window.__calls))].join(' '));
      if (errs.length) { failed++; console.log(`FAIL ${p} ${vp} ${scheme}: ${errs.slice(0, 3).join(' | ')}`); }
      await page.close();
    }
    await ctx.close();
  }
  await browser.close();
  console.log(failed ? `${failed} page(s) with errors` : 'all pages loaded without errors');
  process.exit(failed ? 1 : 0);
})();

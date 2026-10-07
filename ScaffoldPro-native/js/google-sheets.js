'use strict';

// Settings › Google Sheets: connecting the overview sheet (the steps, the
// script to paste, the Web app URL and secret), and how its syncing is going.

(function () {
  const $ = (id) => document.getElementById(id);
  let poll = null;

  function ago(iso) {
    const d = new Date(iso || '');
    if (isNaN(d)) return '';
    const s = Math.round((Date.now() - d) / 1000);
    if (s < 45) return 'just now';
    if (s < 3600) return `${Math.round(s / 60)} min ago`;
    if (s < 86400) return `${Math.round(s / 3600)} h ago`;
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace('Sept', 'Sep');
  }

  function show(s) {
    if (!s) return;
    $('gs-linked').classList.toggle('hidden', !s.linked);
    $('gs-setup').classList.toggle('hidden', !!s.linked);
    if (!s.linked) return;
    $('gs-name').textContent = s.sheetName || 'Google Sheet';
    const state = $('gs-state');
    state.className = '';
    if (s.running) {
      state.classList.add('syncing');
      state.innerHTML = '<i class="gs-dot"></i>Syncing…';
    } else if (s.lastError) {
      state.classList.add('bad');
      state.textContent = `${s.lastError}${s.lastSyncAt ? ` Last synced ${ago(s.lastSyncAt)}.` : ''}`;
    } else if (s.lastSyncAt) {
      const taken = s.lastTakenIn && s.lastTakenInAt ? ` · ${s.lastTakenIn} change${s.lastTakenIn === 1 ? '' : 's'} from the sheet taken in ${ago(s.lastTakenInAt)}` : '';
      state.innerHTML = `<i class="gs-dot"></i>In step — synced ${ago(s.lastSyncAt)}${taken}`;
    } else {
      state.textContent = 'Connected — the first sync is on its way.';
    }
    $('gs-open').disabled = !s.sheetURL;
    // A sheet whose script was pasted before it fetched its own layout.
    $('gs-old').classList.toggle('hidden', !s.lastSyncAt || !!s.sheetLayout || !!s.lastError);
  }

  async function refresh() {
    try { show(await window.api.sheets.status()); } catch (e) { /* not on this Mac */ }
  }

  async function connect() {
    const err = $('gs-error');
    err.classList.add('hidden');
    const btn = $('gs-connect');
    btn.disabled = true;
    btn.textContent = 'Connecting…';
    const r = await window.api.sheets.link($('gs-url').value, $('gs-secret').value);
    btn.disabled = false;
    btn.textContent = 'Connect';
    if (!r || r.ok === false) {
      err.textContent = (r && r.error) || 'It couldn’t connect.';
      err.classList.remove('hidden');
      return;
    }
    $('gs-secret').value = '';
    await refresh();
  }

  function init() {
    if (!$('google-sheets') || !window.api.sheets) return;
    // In a browser: it's set up and runs on the office Mac.
    if (window.__scaffoldProWeb) {
      $('google-sheets').querySelector('.section-body').innerHTML = '<p class="small-note">The Google Sheet is connected and kept up to date from the office Mac — set it up there, in Settings › Google Sheets.</p>';
      return;
    }
    for (const [btn, note] of [['gs-copy', 'gs-copied'], ['gs-copy2', 'gs-copied2']]) {
      $(btn).addEventListener('click', async () => {
        const r = await window.api.sheets.copyScript();
        $(note).textContent = r && r.ok ? 'Copied — paste it into Apps Script.' : ((r && r.error) || 'It couldn’t be copied.');
      });
    }
    $('gs-connect').addEventListener('click', connect);
    for (const id of ['gs-url', 'gs-secret']) $(id).addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); connect(); } });
    $('gs-sync').addEventListener('click', async () => {
      $('gs-sync').disabled = true;
      show(Object.assign(await window.api.sheets.status(), { running: true }));
      show(await window.api.sheets.syncNow());
      $('gs-sync').disabled = false;
    });
    $('gs-open').addEventListener('click', () => window.api.sheets.openSheet());
    $('gs-unlink').addEventListener('click', async () => {
      if (!await window.appConfirm('Disconnect the Google Sheet?\n\nThe sheet keeps what it has; it just stops being updated. You can connect it again with the same URL and secret.', { ok: 'Disconnect', danger: true })) return;
      show(await window.api.sheets.unlink());
    });
    refresh();
    poll = setInterval(refresh, 15000);
    window.addEventListener('pagehide', () => clearInterval(poll));
  }

  init();
})();

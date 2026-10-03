'use strict';

// Announcements: a message for everyone, or for one's own team (set on the
// User page), shown in a bar at the top of the Dashboard of everyone it's
// for — hidden when there are none. Each person can close one (it stays
// closed on every Mac they use); whoever posted it can take it down.
//
//   window.announcements.render(bar)    — draw the bar (and keep it fresh)
//   window.announcements.compose()      — the "Announce" sheet

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const MEGAPHONE = '<svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3.5 8.5v3a1 1 0 0 0 1 1H6l5 3.5v-12L6 7.5H4.5a1 1 0 0 0-1 1z"/><path d="M14 7.5a3.5 3.5 0 0 1 0 5M6.5 12.5l1 4"/></svg>';
  const CLOSE = '<svg viewBox="0 0 12 12" width="11" height="11" aria-hidden="true"><path d="M3 3l6 6M9 3l-6 6" stroke="currentColor" stroke-width="1.6" stroke-linecap="round"/></svg>';
  let barEl = null;
  let page = null;

  function when(iso) {
    const d = new Date(iso);
    if (isNaN(d)) return '';
    const mins = Math.round((Date.now() - d.getTime()) / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return `${mins} min ago`;
    if (mins < 60 * 24) return `${Math.round(mins / 60)} h ago`;
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }).replace('Sept', 'Sep');
  }

  const audienceText = (a) => (a.audience === 'Everyone' ? 'to everyone' : a.audience.startsWith('@') ? 'to you' : `to the ${esc(a.audience)} team`);
  const PEN = '<svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 15.5c2-1 3.5-4 5-4s0 3 1.5 3 3-5 4.5-5 1 2.5 3 2.5"/><path d="M3 17.5h14"/></svg>';
  let waiting = [];
  let started = false;

  async function refresh() {
    if (!barEl) return;
    try { page = await window.api.announcements.page(); } catch (e) { return; }
    // Quotations waiting for me to sign come first.
    try { const s = window.api.signatures ? await window.api.signatures.page() : null; waiting = (s && s.incoming) || []; } catch (e) { waiting = []; }
    draw();
  }

  function draw() {
    const rows = (page && page.visible) || [];
    barEl.classList.toggle('hidden', rows.length === 0 && waiting.length === 0);
    const sign = waiting.map((r) => `<div class="announce sign">
        <span class="announce-icon">${PEN}</span>
        <div class="announce-body">
          <div class="announce-text"><b>${esc(r.number)}</b> is waiting for you to sign and chop${r.note ? ` — “${esc(r.note)}”` : ''}</div>
          <div class="announce-meta">${window.personTag ? window.personTag(r.requestedBy) : esc(r.requestedBy)} <span>asked ${when(r.createdAt)} · ${esc(r.projectNumber)} ${esc(r.projectName || '')}</span></div>
        </div>
        <div class="announce-actions"><a class="button-like primary" href="team.html?tab=signatures">Review &amp; Sign</a></div>
      </div>`).join('');
    barEl.innerHTML = sign + rows.map(({ announcement: a, mine }) => `
      <div class="announce${a.important ? ' important' : ''}" data-id="${esc(a.id)}">
        <span class="announce-icon">${MEGAPHONE}</span>
        <div class="announce-body">
          <div class="announce-text">${esc(a.message)}</div>
          <div class="announce-meta">${window.personTag ? window.personTag(a.author) : esc(a.author)} <span>${audienceText(a)} · ${when(a.createdAt)}${a.showUntil ? ` · until ${esc(new Date(`${a.showUntil}T00:00:00`).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' }).replace('Sept', 'Sep'))}` : ''}</span></div>
        </div>
        <div class="announce-actions">
          ${mine ? '<button type="button" class="announce-down" data-no-icon title="Take it down for everyone">Take Down</button>' : ''}
          <button type="button" class="announce-close" data-no-icon title="Close — it won’t show for you again" aria-label="Close">${CLOSE}</button>
        </div>
      </div>`).join('');
    for (const el of barEl.querySelectorAll('.announce[data-id]')) {
      const id = el.dataset.id;
      el.querySelector('.announce-close').addEventListener('click', async () => {
        el.classList.add('leaving');
        const r = await window.api.announcements.dismiss(id);
        if (r && r.ok === false) { await window.appAlert(r.error); }
        await refresh();
      });
      const down = el.querySelector('.announce-down');
      if (down) down.addEventListener('click', async () => {
        if (!await window.appConfirm('Take this announcement down?\n\nIt’s removed from everyone’s Dashboard.', { ok: 'Take Down', danger: true })) return;
        const r = await window.api.announcements.remove(id);
        if (r && r.ok === false) { await window.appAlert(r.error); return; }
        await refresh();
      });
    }
  }

  function sheet() {
    let el = document.getElementById('announce-modal');
    if (el) return el;
    el = document.createElement('div');
    el.className = 'modal-backdrop hidden';
    el.id = 'announce-modal';
    el.innerHTML = `
      <div class="modal wide" role="dialog" aria-labelledby="an-title">
        <h2 id="an-title">New Announcement</h2>
        <div class="segmented seg-full" id="an-audience" role="tablist" aria-label="Who it’s for">
          <button type="button" data-audience="Everyone" class="active" data-no-icon>Everyone</button>
          <button type="button" data-audience="Team" data-no-icon id="an-team-btn">My team</button>
        </div>
        <div class="field-hint hidden" id="an-team-hint" style="margin:-8px 0 12px;">Set your team on the <a href="user.html">User page</a> to announce to your team only.</div>
        <div class="field"><label for="an-message">Message</label>
          <textarea id="an-message" rows="4" placeholder="e.g. The yard is closed on Saturday for the stock take."></textarea></div>
        <div class="form-row cols-2">
          <div class="field"><label for="an-until">Show until <span class="field-hint" style="display:inline">(optional)</span></label><input type="date" id="an-until" /></div>
          <div class="field"><label>&nbsp;</label><label class="inline-check"><input type="checkbox" id="an-important" /> Important — shown first, highlighted</label></div>
        </div>
        <div id="an-mine"></div>
        <div class="error-text hidden" id="an-error"></div>
        <div class="actions">
          <button id="an-cancel">Cancel</button>
          <button class="primary" id="an-post">Post Announcement</button>
        </div>
      </div>`;
    document.body.appendChild(el);
    return el;
  }

  async function compose() {
    page = await window.api.announcements.page();
    const el = sheet();
    const $ = (id) => el.querySelector(`#${id}`);
    let audience = 'Everyone';
    const setAudience = (a) => {
      audience = a;
      for (const b of el.querySelectorAll('#an-audience button')) b.classList.toggle('active', b.dataset.audience === a);
    };
    setAudience('Everyone');
    const teamBtn = $('an-team-btn');
    teamBtn.textContent = page.myTeam ? `My team (${page.myTeam})` : 'My team';
    teamBtn.disabled = !page.myTeam;
    $('an-team-hint').classList.toggle('hidden', !!page.myTeam);
    $('an-message').value = '';
    $('an-until').value = '';
    $('an-important').checked = false;
    $('an-error').classList.add('hidden');
    // Ones I posted that are still showing, to take down.
    const mine = page.mine || [];
    $('an-mine').innerHTML = mine.length ? `<div class="related-title">Your announcements still showing</div>
      <div class="an-mine-list">${mine.map(({ announcement: a }) => `<div class="an-mine-row" data-id="${esc(a.id)}">
        <div><div class="an-mine-text">${esc(a.message)}</div><div class="sub">${audienceText(a)} · ${when(a.createdAt)}</div></div>
        <button type="button" class="an-mine-down" data-no-icon>Take Down</button></div>`).join('')}</div>` : '';
    for (const row of el.querySelectorAll('.an-mine-row')) {
      row.querySelector('.an-mine-down').addEventListener('click', async () => {
        const r = await window.api.announcements.remove(row.dataset.id);
        if (r && r.ok === false) { await window.appAlert(r.error); return; }
        row.remove();
        await refresh();
      });
    }
    el.classList.remove('hidden');
    $('an-message').focus();
    return new Promise((resolve) => {
      const close = (v) => {
        el.classList.add('hidden');
        for (const [b, fn] of handlers) b.removeEventListener('click', fn);
        el.removeEventListener('keydown', onKey);
        resolve(v);
      };
      const post = async () => {
        const r = await window.api.announcements.post({ message: $('an-message').value.trim(), audience, showUntil: $('an-until').value, important: $('an-important').checked });
        if (!r || r.ok === false) {
          $('an-error').textContent = (r && r.error) || 'The announcement couldn’t be posted.';
          $('an-error').classList.remove('hidden');
          return;
        }
        close(true);
        await refresh();
      };
      const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); close(false); } };
      const segs = [...el.querySelectorAll('#an-audience button')].map((b) => [b, () => { if (!b.disabled) setAudience(b.dataset.audience); }]);
      const handlers = [[$('an-post'), post], [$('an-cancel'), () => close(false)], ...segs];
      for (const [b, fn] of handlers) b.addEventListener('click', fn);
      el.addEventListener('keydown', onKey);
    });
  }

  window.announcements = {
    render(bar) {
      barEl = bar;
      refresh();
      if (started) return;
      started = true;
      // New ones from the team turn up by themselves.
      setInterval(refresh, 60000);
      window.addEventListener('focus', refresh);
    },
    refresh,
    compose,
  };
})();

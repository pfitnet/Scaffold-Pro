'use strict';

// Settings › You (was the User page): this person's name, team, colour and
// Theme (js/settings.js), and their own projects, documents and activity.

(function () {
  const $ = (id) => document.getElementById(id);
  if (!$('you')) return;
  const COLOURS = ['#5B7DB1', '#B07A5E', '#5E8C6A', '#8E72A8', '#A8677C', '#4F8A8F', '#9A8458', '#6D6BA6', '#4E8472', '#A66A6A', '#6B7078', '#4F6F96'];
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const initials = (name) => String(name || '').trim().split(/\s+/).map((w) => w[0] || '').slice(0, 2).join('').toUpperCase() || '?';
  const when = (iso) => {
    const d = new Date(iso);
    if (isNaN(d)) return '';
    const mins = Math.round((Date.now() - d.getTime()) / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return `${mins} min ago`;
    if (mins < 60 * 24) return `${Math.round(mins / 60)} h ago`;
    return d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace('Sept', 'Sep');
  };
  let page = null;

  function list(id, rows, line, empty) {
    const box = $(id);
    box.innerHTML = rows.length ? rows.slice(0, 8).map((r) => `<div class="you-line" data-url="${esc(r.url || '')}">${line(r)}</div>`).join('') : `<div class="empty">${empty}</div>`;
    for (const el of box.querySelectorAll('.you-line[data-url]')) if (el.dataset.url) el.addEventListener('click', () => { location.href = el.dataset.url; });
  }

  async function load() {
    try { page = await window.api.users.page(); } catch (e) { page = null; }
    if (!page) return;
    if (window.loadPersonColors) await window.loadPersonColors();
    const colour = window.personColor ? window.personColor(page.name) : '#8a8f98';
    $('you-avatar').textContent = initials(page.name);
    $('you-avatar').style.background = colour;
    $('you-name').textContent = page.name || 'You';
    $('you-sub').textContent = `On ${page.computer || 'this Mac'}${page.sharing ? ' · sharing the data with the team' : ''}`;
    if (document.activeElement !== $('you-name-input')) $('you-name-input').value = page.name || '';
    if (document.activeElement !== $('you-team-input')) $('you-team-input').value = page.team || '';
    $('you-team-names').innerHTML = (page.teams || []).map((t) => `<option value="${esc(t)}"></option>`).join('');
    const current = (page.color || '').toUpperCase();
    $('you-swatches').innerHTML = COLOURS.map((c) => `<button type="button" class="sw${current === c ? ' on' : ''}" data-colour="${c}" style="background:${c}" title="${c}" aria-label="Colour ${c}" data-no-icon></button>`).join('')
      + (page.color ? '<button type="button" class="sw-auto" data-colour="" data-no-icon title="The colour worked out from your name">Automatic</button>' : '');
    $('you-stats').innerHTML = [[page.myProjects.length, 'Projects I worked on'], [page.createdCount, 'Made by me'], [page.lastWorkedCount, 'Last worked on by me'], [page.myActivity.length, 'Recent actions']]
      .map(([v, l]) => `<div><b>${v}</b><span>${l}</span></div>`).join('');
    list('you-projects', page.myProjects.map((p) => Object.assign({ url: `project-detail.html?number=${encodeURIComponent(p.projectNumber)}` }, p)),
      (p) => `<span><b>${esc(p.projectNumber)}</b> ${esc(p.name)}<small>${esc(p.clientName || '')}</small></span><span class="when">${esc(when(p.lastWorkedAt))}</span>`, 'Projects you work on show here.');
    list('you-documents', page.myDocuments, (r) => `<span><b>${esc(r.number)}</b><small>${esc(r.kind)} · ${esc(r.projectNumber)}</small></span><span class="when">${esc(when(r.lastEditedAt || r.updatedAt))}</span>`, 'Documents you work on show here.');
    list('you-activity', page.myActivity.map((a) => Object.assign({ url: a.projectNumber ? `project-detail.html?number=${encodeURIComponent(a.projectNumber)}&tab=history` : '' }, a)),
      (a) => `<span>${esc(a.action)}<small>${esc([a.projectNumber, a.reference].filter(Boolean).join(' · '))}</small></span><span class="when">${esc(when(a.createdAt))}</span>`, 'Nothing yet.');
    $('you-team-list').innerHTML = page.sharing && page.members && page.members.length
      ? page.members.map((m) => `<div class="you-line"><span>${window.personTag ? window.personTag(m.name) : esc(m.name)}<small>${esc(m.computer || '')}${m.isThisMac ? ' · this Mac' : m.lastSeen ? ` · seen ${esc(when(m.lastSeen))}` : ''}</small></span></div>`).join('')
      : '<div class="empty">This Mac isn’t sharing its data — see Share with Other Macs.</div>';
    if (window.settingsUI) window.settingsUI.refresh();
  }

  $('you-swatches').addEventListener('click', async (e) => {
    const b = e.target.closest('button[data-colour]');
    if (!b) return;
    const r = await window.api.users.setColor(b.dataset.colour);
    if (r && r.ok === false) { await window.appAlert(r.error); return; }
    if (window.loadPersonColors) await window.loadPersonColors(true);
    await load();
  });
  $('you-name-save').addEventListener('click', async () => {
    const name = $('you-name-input').value.trim();
    if (!name || !page || name === page.name) return;
    const r = await window.api.users.setName(name);
    if (r && r.ok === false) { await window.appAlert(r.error); return; }
    window.softReload();   // the sidebar shows the new name too
  });
  $('you-team-save').addEventListener('click', async () => {
    const r = await window.api.users.setTeam($('you-team-input').value.trim());
    if (r && r.ok === false) { await window.appAlert(r.error); return; }
    await load();
  });
  load();
})();

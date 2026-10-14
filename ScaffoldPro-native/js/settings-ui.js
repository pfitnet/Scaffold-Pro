'use strict';

// Settings, laid out (settings.html, css/settings.css): the sections in a
// list on the left with a search box, one section shown at a time. Each
// setting is a row showing what it's set to, with a pencil at its end to
// change just that one (Save or Cancel; Return saves, Esc cancels).
// Switches, lists and button sets have no pencil: they work straight away.
// Every change is saved by itself (js/settings.js › saveSettings), with a
// small "Saved" to say so.

(function () {
  const $ = (s, root = document) => root.querySelector(s);
  const $$ = (s, root = document) => [...root.querySelectorAll(s)];
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const svg = (body, size = 15) => `<svg viewBox="0 0 20 20" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${body}</svg>`;
  const PEN = window.icon('edit', { size: 16 });
  // Section icons: names in the shared set (js/icons.js).
  const ICONS = { building: 'building', doc: 'file-text', grid: 'table', quote: 'receipt', invoice: 'file-text', people: 'team', shield: 'shield', refresh: 'sync', globe: 'globe', sheet: 'table', folder: 'folder', user: 'user', tag: 'price-lists', news: 'note', spark: 'assistant' };
  const sectionIcon = (key) => window.icon(ICONS[key] || 'file-text', { size: 15, cls: 'st-ico-svg' });

  const panes = $$('.st-pane');
  const navList = $('#st-nav-list');
  const KEY = 'scaffoldpro.settings.section';

  // ---- the section list ----
  // The sections, under their groups (You · Company · This Mac & data).
  let lastGroup = null;
  navList.innerHTML = panes.map((p) => {
    const group = p.dataset.group || '';
    const head = group && group !== lastGroup ? `<div class="st-nav-group">${group}</div>` : '';
    lastGroup = group;
    return `${head}<button type="button" class="st-nav-item" data-for="${p.id}" data-no-icon>
    <span class="st-ico">${sectionIcon(p.dataset.icon)}</span><span>${esc(p.dataset.title)}</span></button>`;
  }).join('');
  let current = null;
  function select(id, focus) {
    const pane = panes.find((p) => p.id === id) || panes[0];
    current = pane.id;
    for (const p of panes) p.hidden = p !== pane;
    for (const b of $$('.st-nav-item', navList)) b.classList.toggle('on', b.dataset.for === pane.id);
    try { localStorage.setItem(KEY, pane.id); } catch (e) { /* not kept */ }
    if (location.hash.slice(1) !== pane.id) history.replaceState(null, '', `#${pane.id}`);
    // Restart the little fade each time a section is opened.
    pane.style.animation = 'none'; void pane.offsetWidth; pane.style.animation = '';
    if (focus) { const first = $('.st-edit, .st-control select, .st-control input, button', pane); if (first) first.focus({ preventScroll: true }); }
    window.scrollTo({ top: 0, behavior: 'instant' in window ? 'instant' : 'auto' });
  }
  navList.addEventListener('click', (e) => {
    const b = e.target.closest('.st-nav-item');
    if (!b) return;
    $('#st-search').value = '';
    search();
    select(b.dataset.for);
  });
  // ↑ / ↓ move through the sections.
  navList.addEventListener('keydown', (e) => {
    if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
    const items = $$('.st-nav-item', navList);
    const at = items.indexOf(document.activeElement);
    if (at < 0) return;
    e.preventDefault();
    const next = items[(at + (e.key === 'ArrowDown' ? 1 : -1) + items.length) % items.length];
    next.focus();
    select(next.dataset.for);
  });
  let saved = null;
  try { saved = localStorage.getItem(KEY); } catch (e) { saved = null; }
  // The gear by the User tab opens Settings with no section named: the
  // last one used, unless that was You (the User tab's own).
  select(location.hash.slice(1) || (saved && saved !== 'you' ? saved : 'general'));
  window.addEventListener('hashchange', () => { if (location.hash.slice(1) !== current) select(location.hash.slice(1)); });

  // ---- saving ----
  const toastEl = $('#st-toast');
  let toastTimer = null;
  function toast(text, bad) {
    toastEl.textContent = text;
    toastEl.classList.toggle('bad', !!bad);
    toastEl.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toastEl.classList.remove('show'), 1600);
  }
  let saving = Promise.resolve(true);
  async function commit() {
    saving = saving.then(async () => {
      const ok = await window.saveSettings();
      if (ok) {
        window.setSettingsDirty(false);
        $('#settings-changed-elsewhere').classList.add('hidden');
        toast('Saved');
      }
      refresh();
      return ok;
    });
    return saving;
  }
  // A switch, a list or a material quantity changed (js/settings.js marks
  // the form changed): saved a moment later. A row being edited waits for
  // its Save.
  let timer = null;
  const markChanged = window.setSettingsDirty;
  window.setSettingsDirty = function setSettingsDirty(value) {
    markChanged(value);
    if (value && !open) { clearTimeout(timer); timer = setTimeout(commit, 350); }
  };
  // "Reload" when another Mac changed them: theirs, now.
  const reload = $('#settings-reload-btn');
  if (reload) reload.addEventListener('click', async () => { await window.loadSettings(); window.setSettingsDirty(false); $('#settings-changed-elsewhere').classList.add('hidden'); refresh(); });

  // ---- one row at a time ----
  let open = null;
  let snapshot = null;
  const fieldsOf = (row) => $$('.st-editor input, .st-editor textarea, .st-editor select', row).filter((el) => !el.closest('.tt'));
  for (const row of $$('.st-row.edit')) {
    // One box (a name, a number…): it opens in place of its value, on the
    // same line, so nothing below moves.
    const boxes = $$('.st-editor input:not([type=hidden]), .st-editor textarea, .st-editor select, .st-editor table', row);
    if (boxes.length === 1 && boxes[0].tagName === 'INPUT' && !$('.number-example, .token-row', row)) row.classList.add('inline');
    const title = $('.st-label b', row).textContent;
    const pen = document.createElement('button');
    pen.type = 'button';
    pen.className = 'st-edit';
    pen.dataset.noIcon = '';
    pen.title = `Change ${title}`;
    pen.setAttribute('aria-label', `Change ${title}`);
    pen.innerHTML = PEN;
    $('.st-value', row).after(pen);
    const editor = $('.st-editor', row);
    const actions = document.createElement('div');
    actions.className = 'st-actions';
    actions.innerHTML = row.hasAttribute('data-own-actions')
      ? '<button type="button" data-no-icon data-act="done">Done</button>'
      : '<button type="button" data-no-icon data-act="cancel">Cancel</button><button type="button" class="primary" data-no-icon data-act="save">Save</button>';
    editor.appendChild(actions);
    pen.addEventListener('click', () => openRow(row));
    $('.st-value', row).addEventListener('click', () => openRow(row));
    actions.addEventListener('click', (e) => {
      const b = e.target.closest('button[data-act]');
      if (!b) return;
      if (b.dataset.act === 'save') saveRow(row);
      else if (b.dataset.act === 'cancel') cancelRow(row);
      else closeRow(row);
    });
    editor.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); if (row.hasAttribute('data-own-actions')) closeRow(row); else cancelRow(row); }
      else if (e.key === 'Enter' && !e.shiftKey && e.target.tagName === 'INPUT' && !row.hasAttribute('data-own-actions') && !e.target.closest('.default-items-add')) { e.preventDefault(); saveRow(row); }
    });
  }

  async function openRow(row) {
    if (open === row) return;
    if (open && !(await saveRow(open))) return;
    open = row;
    snapshot = {
      fields: fieldsOf(row).map((el) => [el, el.type === 'checkbox' ? el.checked : el.value]),
      // (js/settings.js keeps the starting materials in its own `defaultBOQItems`.)
      items: row.dataset.show === 'items' && typeof defaultBOQItems !== 'undefined' ? JSON.parse(JSON.stringify(defaultBOQItems)) : null,
      terms: $$('.st-editor textarea', row).filter((t) => t.termsTable).map((t) => [t, t.value]),
    };
    row.classList.add('editing');
    const first = $$('.st-editor input:not([type=hidden]), .st-editor textarea, .st-editor select', row).find((el) => el.offsetParent !== null);
    if (first) { first.focus(); if (first.select && first.tagName === 'INPUT') first.select(); }
  }

  function closeRow(row) {
    row.classList.remove('editing');
    if (open === row) { open = null; snapshot = null; }
    refresh();
    const pen = $('.st-edit', row);
    if (pen) pen.focus({ preventScroll: true });
  }

  async function saveRow(row) {
    const how = row.dataset.save || '';
    let ok = true;
    if (how.startsWith('click:')) document.getElementById(how.slice(6)).click();
    else if (how.startsWith('change:')) document.getElementById(how.slice(7)).dispatchEvent(new Event('change', { bubbles: true }));
    else if (!row.hasAttribute('data-own-actions')) { clearTimeout(timer); ok = await commit(); }
    if (ok === false) return false;   // e.g. a number format without {SEQ}: stays open
    if (how) toast('Saved');
    closeRow(row);
    return true;
  }

  function cancelRow(row) {
    if (open === row && snapshot) {
      for (const [el, v] of snapshot.fields) { if (el.type === 'checkbox') el.checked = v; else el.value = v; }
      for (const [t, v] of snapshot.terms) t.value = v;
      if (snapshot.items && window.renderDefaultItems) { defaultBOQItems = snapshot.items; window.renderDefaultItems(); }
      const rates = $('#delivery-rates-body', row);
      if (rates) rates.dispatchEvent(new Event('input', { bubbles: true }));
      for (const f of ['numberFormatBOQ', 'numberFormatQuotation', 'numberFormatInvoice', 'numberFormatDeliveryNote', 'numberFormatLetter']) {
        if ($(`#${f}-input`, row) && window.updateNumberExample) window.updateNumberExample(f);
      }
    }
    window.setSettingsDirty(false);
    closeRow(row);
  }

  // ---- what each row shows ----
  const none = (t) => `<span class="none">${esc(t)}</span>`;
  const plural = (n, w) => `${n} ${w}${n === 1 ? '' : 's'}`;
  const SHOW = {
    text(row) {
      const el = $('.st-editor input, .st-editor textarea', row);
      if (el.value.trim()) return esc(el.value.trim());
      return none(el.placeholder ? `Not set — ${el.placeholder}` : 'Not set');
    },
    long(row) {
      const v = $('.st-editor textarea', row).value.trim();
      return v ? `<span class="long">${esc(v)}</span>` : none('Not set');
    },
    buyback(row) {
      const v = (id) => Number(($(`#${id}`, row) || {}).value) || 0;
      const p = v('buyBackPercent-input'); const after = v('buyBackAfterMonths-input');
      const less = v('buyBackReductionPercent-input'); const end = Math.max(after, v('buyBackEndMonths-input'));
      const last = Math.max(0, p - less * (end - after));
      return `${p}% after ${plural(after, 'month')}${less ? `, then ${less}% less a month (${last}% at ${end})` : ''} <span class="none">· none after ${plural(end, 'month')}</span>`;
    },
    months: (row) => { const v = Number($('.st-editor input', row).value); return v ? plural(v, 'month') : none('Not set'); },
    days: (row) => { const v = $('.st-editor input', row).value; return v === '' ? none('Not set') : plural(Number(v), 'day'); },
    money: (row) => { const v = $('.st-editor input', row).value; return v === '' ? none('Not set') : `HK$ ${Number(v).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`; },
    password: (row) => (/^Set/.test($('.st-editor input', row).placeholder) ? '•••••••• <span class="none">set</span>' : none('Not set')),
    token: () => (/saved/.test(($('#token-state') || {}).textContent || '') ? 'Saved on this Mac' : none('None — only needed for a private repository')),
    numfmt(row) {
      const input = $('.st-editor input[type=text]', row);
      const start = $('.start-input', row).value;
      const example = ($('.number-example', row).textContent || '').replace(/^e\.g\.\s*/, '');
      return `<code>${esc(input.value.trim() || row.dataset.default)}</code>${example ? `<span class="arrow">→</span>${esc(example)}` : ''}${start ? ` <span class="none">· from ${esc(start)}</span>` : ''}`;
    },
    terms(row) {
      const ta = $('.st-editor textarea', row);
      const rows = window.termsTableParse ? window.termsTableParse(ta.value) : [];
      if (!rows.length) return none(ta.id === 'boqTerms-input' ? 'Not set — the quotations’ key terms are used' : ta.id === 'quotationTermsSale-input' ? 'Not set — the rental terms are used' : 'Not set');
      const terms = rows.filter((r) => r.kind === 'term');
      const paras = rows.length - terms.length;
      // A short preview, as the terms print: the first few labels beside
      // their wording (one line each), then how many more there are.
      const first = (t) => String(t || '').split('\n')[0].trim();
      const shown = terms.length > 4 ? 3 : terms.length;
      const rest = [terms.length > shown ? plural(terms.length - shown, 'more term') : '', paras ? plural(paras, 'paragraph') : ''].filter(Boolean);
      const lead = !terms.length ? rows.filter((r) => r.kind === 'para').slice(0, 1).map((r) => `<span class="st-para">${esc(first(r.text))}</span>`).join('') : '';
      return `<span class="st-terms">${terms.slice(0, shown).map((r) => `<span class="st-term"><b>${esc(r.label)}</b><span>${esc(first(r.value)) || '—'}</span></span>`).join('')}${lead}${
        rest.length ? `<span class="st-more">${terms.length ? '+ ' : ''}${rest.join(' · ')}</span>` : ''}</span>`;
    },
    rates() {
      const r = window.readDeliveryRates && document.getElementById('dr-kg-0') ? window.readDeliveryRates() : [];
      if (!r.length) return none('Not set');
      // A small rate table: the weights along the top, the price under each
      // (a two-column list when the window is narrow; css/settings.css).
      const shown = r.length > 6 ? 5 : r.length;
      return `<span class="st-rates"><span class="st-rh">Up to</span><span class="st-rh">HK$</span>${r.slice(0, shown).map((x) => `<span class="st-rk">${Number(x.upToKg).toLocaleString('en-US')} kg</span><b>${Number(x.price).toLocaleString('en-US')}</b>`).join('')}${
        r.length > shown ? `<span class="st-rk">…</span><span class="st-rmore">+${r.length - shown} more</span>` : ''}</span>`;
    },
    items() {
      const names = $$('#default-items-list tbody tr').map((tr) => {
        const name = tr.cells[0].textContent.trim();
        const qty = (tr.querySelector('input') || {}).value;
        return `${name} ×${qty}`;
      });
      if (!names.length) return none('None — new BOQs start empty');
      return names.slice(0, 3).map(esc).join(', ') + (names.length > 3 ? ` <span class="none">+${names.length - 3} more</span>` : '');
    },
  };
  function refresh() {
    for (const row of $$('.st-row.edit')) {
      if (row === open) continue;
      // One row that can't be shown yet (still loading) doesn't stop the rest.
      let html;
      try { html = (SHOW[row.dataset.show] || SHOW.text)(row); } catch (e) { continue; }
      const box = $('.st-value', row);
      if (box.innerHTML !== html) box.innerHTML = html;
    }
  }
  refresh();
  // Values arrive as the page loads (and from the other parts of the page).
  setInterval(refresh, 1200);
  window.settingsUI = { refresh };

  // ---- search ----
  const searchBox = $('#st-search');
  function search() {
    const q = searchBox.value.trim().toLowerCase();
    document.body.classList.toggle('searching', !!q);
    if (!q) {
      for (const el of $$('.st-row, .st-group, .st-pane .gs-body, .st-pane > *')) el.hidden = false;
      for (const b of $$('.st-nav-item')) b.classList.remove('dim');
      $('#st-none').classList.add('hidden');
      select(current || 'general');
      return;
    }
    let any = false;
    for (const p of panes) {
      const titleHit = p.dataset.title.toLowerCase().includes(q);
      const rows = $$('.st-row', p);
      let shown = 0;
      for (const r of rows) { const hit = titleHit || r.textContent.toLowerCase().includes(q); r.hidden = !hit; if (hit) shown += 1; }
      for (const g of $$('.st-group', p)) g.hidden = !$$('.st-row', g).some((r) => !r.hidden);
      const textHit = !rows.length && p.textContent.toLowerCase().includes(q);
      const hit = titleHit || shown > 0 || textHit;
      p.hidden = !hit;
      $(`.st-nav-item[data-for="${p.id}"]`).classList.toggle('dim', !hit);
      if (hit) any = true;
    }
    $('#st-none').classList.toggle('hidden', any);
  }
  searchBox.addEventListener('input', search);
  searchBox.addEventListener('keydown', (e) => { if (e.key === 'Escape') { searchBox.value = ''; search(); } });
  // ⌘F / "/" to search the settings.
  document.addEventListener('keydown', (e) => {
    if (((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'f') || (e.key === '/' && !/INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName))) {
      e.preventDefault(); searchBox.focus(); searchBox.select();
    }
  });
})();

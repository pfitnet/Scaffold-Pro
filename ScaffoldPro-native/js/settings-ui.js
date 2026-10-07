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
  const PEN = svg('<path d="M12.8 3.7l3.5 3.5-8.8 8.8-4 .5.5-4z"/><path d="M11.2 5.3l3.5 3.5"/>', 16);
  const ICONS = {
    building: '<rect x="4" y="3" width="12" height="14" rx="1.5"/><path d="M7.5 6.5h1.5M11 6.5h1.5M7.5 9.5h1.5M11 9.5h1.5M8.5 17v-3.5h3V17"/>',
    doc: '<path d="M5.5 2.5h6l3.5 3.5v11.5h-9.5z"/><path d="M11.5 2.5V6H15M8 10h5M8 13h5"/>',
    grid: '<rect x="3" y="3.5" width="14" height="13" rx="1.5"/><path d="M3 7.5h14M3 11.5h14M8 7.5v9"/>',
    quote: '<path d="M5 2.5h10v15l-2-1.3-2 1.3-2-1.3-2 1.3-2-1.3z"/><path d="M7.5 7h5M7.5 10h5"/>',
    invoice: '<rect x="4" y="2.5" width="12" height="15" rx="1.5"/><path d="M7 6.5h6M7 9.5h6M7 12.5h3.5"/>',
    people: '<circle cx="7.5" cy="7" r="2.5"/><circle cx="13.5" cy="8" r="2"/><path d="M3 16c.6-2.7 2.3-4 4.5-4s3.9 1.3 4.5 4M12.5 12.3c2 0 3.6 1.2 4.2 3.4"/>',
    shield: '<path d="M10 2.5l6 2.3v4.7c0 3.8-2.6 6.6-6 8-3.4-1.4-6-4.2-6-8V4.8z"/><path d="M7.3 10l1.9 1.9 3.6-3.8"/>',
    refresh: '<path d="M15.5 7.5A6 6 0 0 0 4.6 6.2M4.5 12.5a6 6 0 0 0 10.9 1.3"/><path d="M15.8 3.5v4h-4M4.2 16.5v-4h4"/>',
    globe: '<circle cx="10" cy="10" r="7"/><path d="M3 10h14M10 3c2 2.2 2.8 4.5 2.8 7S12 14.8 10 17c-2-2.2-2.8-4.5-2.8-7S8 5.2 10 3z"/>',
    sheet: '<rect x="4" y="2.5" width="12" height="15" rx="1.8"/><path d="M7 7h6M7 10.5h6M7 14h6M10 7v7"/>',
    folder: '<path d="M2.5 5.5a1 1 0 0 1 1-1h4l1.5 1.8h7.5a1 1 0 0 1 1 1v8.2a1 1 0 0 1-1 1h-13a1 1 0 0 1-1-1z"/>',
    user: '<circle cx="10" cy="7" r="3.2"/><path d="M3.8 17c.8-3.2 3.2-5 6.2-5s5.4 1.8 6.2 5"/>',
    tag: '<path d="M3 10V3.5h6.5L17 11l-6.5 6.5z"/><circle cx="6.8" cy="7" r="1.2"/>',
    spark: '<path d="M10 2.5l1.6 4.4 4.4 1.6-4.4 1.6L10 14.5l-1.6-4.4L4 8.5l4.4-1.6zM15.5 13l.7 1.8 1.8.7-1.8.7-.7 1.8-.7-1.8-1.8-.7 1.8-.7z"/>',
  };
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
    <span class="st-ico">${svg(ICONS[p.dataset.icon] || ICONS.doc)}</span><span>${esc(p.dataset.title)}</span></button>`;
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
  select(location.hash.slice(1) || saved || 'you');
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

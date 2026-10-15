'use strict';

// A document editor's header card (type, status, number, project line, who
// made it and last worked on it, the linked documents), and on the project
// page "Created by Harry · Last worked on by William, 2 hours ago" under
// its title. It works out which record the page shows from its address.

(function () {
  const PAGES = {
    'boq-editor.html': 'boq', 'quotation-editor.html': 'quotation', 'invoice-editor.html': 'invoice',
    'delivery-note-editor.html': 'deliveryNote', 'letter-editor.html': 'letter', 'project-detail.html': 'project',
  };

  function esc(value) {
    return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function ago(iso) {
    const t = new Date(iso || '').getTime();
    if (!t) return '';
    const mins = Math.round((Date.now() - t) / 60000);
    if (mins < 1) return 'just now';
    if (mins < 60) return `${mins} minute${mins === 1 ? '' : 's'} ago`;
    const hours = Math.round(mins / 60);
    if (hours < 24) return `${hours} hour${hours === 1 ? '' : 's'} ago`;
    const days = Math.round(hours / 24);
    if (days < 7) return `${days} day${days === 1 ? '' : 's'} ago`;
    return new Date(t).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace('Sept', 'Sep');
  }

  window.authorsText = function authorsText(a) {
    if (!a) return '';
    const parts = [];
    // Names in each person's colour (sidebar.js).
    const who = (n) => (window.personTag ? window.personTag(n) : esc(n));
    if (a.createdBy) parts.push(`Created by ${who(a.createdBy)}`);
    if (a.lastEditedBy) parts.push(`Last worked on by ${who(a.lastEditedBy)}${a.lastEditedAt ? `, ${ago(a.lastEditedAt)}` : ''}`);
    return parts.join(' · ');
  };

  // ---- A document editor's header card ----
  // The document type (in its colour) and status over the number and the
  // project line; who made it and who last worked on it at the right; and
  // the linked documents as a flow: BOQ › Quotation › Split off ›
  // Delivery Notes › Invoices. Click the number to copy it.

  const KIND = { boq: 'BOQ', quotation: 'Quotation', invoice: 'Invoice', deliveryNote: 'Delivery Note', letter: 'Letter' };
  const STEP = { BOQ: 'BOQ', Quotation: 'Quotation', Subsidiary: 'Split off', DeliveryNote: 'Delivery Notes', Invoice: 'Invoices' };
  const STEP_KIND = { BOQ: 'boq', Quotation: 'quotation', Subsidiary: 'subsidiary', DeliveryNote: 'deliveryNote', Invoice: 'invoice' };
  const COPY_ICON = '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linejoin="round" aria-hidden="true"><rect x="5.5" y="5.5" width="8" height="8" rx="1.6"/><path d="M10.5 3.5v-.2A1.3 1.3 0 0 0 9.2 2H3.3A1.3 1.3 0 0 0 2 3.3v5.9a1.3 1.3 0 0 0 1.3 1.3h.2"/></svg>';

  function flowHTML(chain) {
    if (!chain.length) return '';
    const groups = [];
    for (const kind of ['BOQ', 'Quotation', 'Subsidiary', 'DeliveryNote', 'Invoice']) {
      const docs = chain.filter((c) => c.kind === kind);
      if (docs.length) groups.push({ kind, docs });
    }
    return groups.map((g, i) => `${i ? `<span class="df-link" style="--i:${i}" aria-hidden="true"></span>` : ''}
      <div class="df-group" data-kind="${STEP_KIND[g.kind]}" style="--i:${i}">
        <span class="df-kind">${STEP[g.kind]}</span>
        <span class="df-docs">${g.docs.map((d) => {
          const status = `<span class="df-status s-${esc(String(d.status || '').toLowerCase())}" title="${esc(d.status)}"></span>`;
          return d.current
            ? `<span class="df-doc current" aria-current="page" title="This ${esc(STEP[g.kind].replace(/s$/, '').toLowerCase())} · ${esc(d.status)}">${status}${esc(d.number)}</span>`
            : `<a class="df-doc" href="${esc(d.url)}" title="Open ${esc(d.number)} · ${esc(d.status)}">${status}${esc(d.number)}</a>`;
        }).join('')}</span>
      </div>`).join('');
  }

  function metaHTML(a) {
    if (!a) return '';
    const who = (n) => (window.personTag ? window.personTag(n) : esc(n));
    const exact = (iso) => { const t = new Date(iso || ''); return isNaN(t) ? '' : t.toLocaleString('en-GB', { day: 'numeric', month: 'short', year: 'numeric', hour: '2-digit', minute: '2-digit' }).replace('Sept', 'Sep'); };
    const items = [];
    if (a.createdBy) items.push(`<div class="dh-meta"><span class="dh-meta-label">Created by</span><span class="dh-meta-value">${who(a.createdBy)}</span></div>`);
    if (a.lastEditedBy) items.push(`<div class="dh-meta" title="${esc(exact(a.lastEditedAt))}"><span class="dh-meta-label">Last worked on</span><span class="dh-meta-value">${who(a.lastEditedBy)}${a.lastEditedAt ? `<span class="dh-ago">${esc(ago(a.lastEditedAt))}</span>` : ''}</span></div>`);
    return items.join('');
  }

  function copyText(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) return navigator.clipboard.writeText(text).catch(() => fallback());
    return Promise.resolve(fallback());
    function fallback() {
      const t = document.createElement('textarea');
      t.value = text; t.setAttribute('readonly', ''); t.style.cssText = 'position:fixed;opacity:0;left:-9999px';
      document.body.appendChild(t); t.select();
      try { document.execCommand('copy'); } catch (e) { /* ignore */ }
      t.remove();
    }
  }

  function setupHero(hero) {
    // Click the number (or its copy mark) to copy it.
    hero.addEventListener('click', (e) => {
      const h1 = e.target.closest('h1, .dh-copy');
      if (!h1) return;
      const title = hero.querySelector('h1');
      const number = title ? title.textContent.trim() : '';
      if (!number) return;
      copyText(number);
      hero.classList.remove('copied');
      void hero.offsetWidth; // restart the animation
      hero.classList.add('copied');
      clearTimeout(setupHero.t);
      setupHero.t = setTimeout(() => hero.classList.remove('copied'), 1400);
    });
    // The status pill follows the Status list.
    const select = document.getElementById('status-select');
    if (select) {
      const update = () => setStatus(hero, select.value);
      select.addEventListener('change', () => setTimeout(update, 400));
      new MutationObserver(update).observe(select, { attributes: true, childList: true, subtree: true });
      setInterval(() => { if (hero.dataset.status !== select.value) update(); }, 1000);
    }
  }

  function setStatus(hero, status) {
    const pill = hero.querySelector('.dh-status');
    if (!pill || !status || hero.dataset.status === status) return;
    hero.dataset.status = status;
    pill.textContent = status;
    pill.className = `dh-status s-${status.toLowerCase()}`;
    pill.classList.add('changed');
  }

  function buildHero(kind, block, a, chain) {
    let hero = block.closest('.doc-hero');
    if (!hero) {
      hero = document.createElement('section');
      hero.className = 'doc-hero';
      hero.dataset.kind = kind;
      hero.innerHTML = `
        <div class="dh-eyebrow"><span class="dh-dot" aria-hidden="true"></span><span class="dh-kind">${KIND[kind] || ''}</span><span class="dh-status"></span></div>
        <div class="dh-main"><button type="button" class="dh-copy" data-no-icon title="Copy the number" aria-label="Copy the number">${COPY_ICON}<span class="dh-copied">Copied</span></button></div>
        <div class="dh-side"></div>
        <div class="doc-flow" hidden></div>`;
      block.insertAdjacentElement('beforebegin', hero);
      hero.querySelector('.dh-main').insertBefore(block, hero.querySelector('.dh-copy'));
      setupHero(hero);
    }
    hero.querySelector('.dh-side').innerHTML = metaHTML(a);
    const flow = hero.querySelector('.doc-flow');
    flow.innerHTML = flowHTML(chain);
    flow.hidden = !chain.length;
    const select = document.getElementById('status-select');
    const current = chain.find((c) => c.current);
    setStatus(hero, (select && select.value) || (current && current.status) || '');
  }

  async function show() {
    const file = location.pathname.split('/').pop();
    const kind = PAGES[file];
    if (!kind || !window.api || !window.api.authors) return;
    const params = new URLSearchParams(location.search);
    const id = params.get('id') || '';
    const number = params.get('number') || '';
    if (!id && !number) return;
    let a = null;
    try { a = await window.api.authors.get(kind, id, number); } catch (e) { return; }
    // The linked documents: BOQ › Quotation › Split off › Delivery Notes › Invoices.
    let chain = [];
    if (id && ['boq', 'quotation', 'deliveryNote', 'invoice'].includes(kind) && window.api.authors.chain) {
      try { chain = (await window.api.authors.chain(kind, id)) || []; } catch (e) { chain = []; }
    }
    const authors = window.authorsText(a);
    // A document's editor: the header card. (The page re-draws its title
    // block's contents; the card sits around it, so it stays.)
    const editor = kind !== 'project';
    const wait = (tries) => {
      const h1 = document.querySelector('#content h1');
      if (!h1) { if (tries > 0) setTimeout(() => wait(tries - 1), 200); return; }
      const block = h1.parentElement && h1.parentElement.id !== 'content' ? h1.parentElement : h1;
      if (editor && block !== h1) { buildHero(kind, block, a, chain); return; }
      if (!authors) return;
      let line = document.getElementById('doc-authors');
      if (!line) {
        line = document.createElement('div');
        line.id = 'doc-authors';
        line.className = 'doc-authors';
        const after = block === h1 && h1.nextElementSibling && h1.nextElementSibling.classList.contains('subtitle') ? h1.nextElementSibling : block;
        after.insertAdjacentElement('afterend', line);
      }
      line.innerHTML = authors;
    };
    wait(25);
  }

  // ---- The document workspace (docs/redesign/PLAN.md §4.4) ----
  // One layout for every editor: a sticky document bar (status, page and
  // language, Export as the main button, everything else under ···), the
  // document itself in the main column, and its details in an inspector on
  // the right that can be hidden (the button in the bar, or ⌥⌘I in the app).
  // Nodes are moved, never rebuilt, so every id and listener stays.
  const SHELL = {
    // The terms are part of the document: they stay in the main column, under
    // the items; their drawings go to the inspector.
    quotation: { body: 'quotation-body', side: ['.q-top-grid', '.q-terms-row .linked-drawings-panel'] },
    boq: { body: 'boq-body', side: ['.details-bar', '#linked-bar', '.linked-drawings-panel', '#sheet-extras'] },
    deliveryNote: { body: 'dn-body', side: ['#dn-signed-bar', '#quotation-import', '.header-fields'] },
    invoice: { body: 'invoice-body', side: ['#inv-signed-notes', '.header-fields'] },
    letter: { body: 'letter-page', side: ['.letter-fields', '#annex-panel'] },
  };
  const MOVE_TO_MENU = ['print-btn', 'locate-file-btn', 'duplicate-doc-btn', 'split-btn', 'revert-split-btn', 'delete-doc-btn', 'delete-btn'];
  const SIDE_KEY = 'doc.inspector';

  function setupDocShell(kind) {
    const cfg = SHELL[kind];
    const body = cfg && document.getElementById(cfg.body);
    if (!body || body.classList.contains('doc-shell')) return;
    const bar = body.querySelector(':scope > .toolbar');
    body.classList.add('doc-shell');
    if (bar) {
      bar.classList.add('doc-bar');
      bar.removeAttribute('style');
      // Print, Locate, Duplicate, Split, Delete: under ···, clicking the real
      // buttons (Swift clicks #print-btn for ⌘P; document-actions.js wires the rest).
      const moved = MOVE_TO_MENU.map((id) => document.getElementById(id)).filter((b) => b && bar.contains(b));
      for (const b of moved) b.classList.add('doc-in-menu');
      const right = document.createElement('div');
      right.className = 'doc-bar-actions';
      const more = document.createElement('button');
      more.type = 'button';
      more.className = 'icon-btn doc-more';
      more.dataset.noIcon = '';
      more.title = 'More';
      more.setAttribute('aria-label', 'More');
      more.innerHTML = window.icon ? window.icon('more', 18) : '···';
      const toggle = document.createElement('button');
      toggle.type = 'button';
      toggle.className = 'icon-btn inspector-toggle';
      toggle.dataset.noIcon = '';
      toggle.title = 'Show or hide the details (⌥⌘I)';
      toggle.setAttribute('aria-label', 'Show or hide the details');
      toggle.innerHTML = window.icon ? window.icon('sidebar', 18) : 'Details';
      const exportBtn = bar.querySelector('.export-menu');
      if (exportBtn) exportBtn.classList.add('primary');
      right.append(toggle, more);
      if (exportBtn) right.appendChild(exportBtn);
      bar.appendChild(right);
      // Pinned at the top once the page scrolls: then it covers the title
      // strip above it and shows a line under it (css .doc-bar.stuck).
      const scroller = document.getElementById('content');
      const stuck = () => {
        const strip = parseFloat(getComputedStyle(document.documentElement).getPropertyValue('--titlebar-safe')) || 0;
        bar.classList.toggle('stuck', !!scroller && scroller.scrollTop > 0 &&
          bar.getBoundingClientRect().top - scroller.getBoundingClientRect().top <= strip + 0.5);
      };
      if (scroller) scroller.addEventListener('scroll', stuck, { passive: true });
      // Its real height (it can wrap), for what pins under it (the inspector, the letter's toolbar).
      if (window.ResizeObserver) new ResizeObserver(() => body.style.setProperty('--doc-bar-h', `${bar.offsetHeight}px`)).observe(bar);
      const label = (b) => (b.dataset.iconLabel || b.textContent || b.getAttribute('aria-label') || b.title || '').trim().replace(/\s+/g, ' ');
      if (window.hoverMenu) {
        // One line each with its icon; what it does shows on resting on it.
        // Delete stands apart, in red.
        const ICON = { 'print-btn': 'print', 'locate-file-btn': 'locate', 'duplicate-doc-btn': 'duplicate', 'split-btn': 'split',
          'revert-split-btn': 'undo', 'delete-doc-btn': 'trash', 'delete-btn': 'trash' };
        window.hoverMenu.attach(more, {
          align: 'right',
          minWidth: 200,
          items: () => moved.filter((b) => !b.hidden && !b.classList.contains('hidden') && b.style.display !== 'none')
            .map((b) => {
              const danger = ICON[b.id] === 'trash';
              return { label: label(b) || b.id, hint: b.title && b.title !== label(b) ? b.title : '', icon: ICON[b.id], danger, sep: danger, value: b.id, disabled: b.disabled };
            }),
          onPick: (id) => { const b = document.getElementById(id); if (b && !b.disabled) b.click(); },
        });
      }
      // The inspector, shown unless hidden on this Mac.
      const setSide = (on) => {
        body.classList.toggle('inspector-off', !on);
        toggle.classList.toggle('on', on);
        try { localStorage.setItem(SIDE_KEY, on ? 'on' : 'off'); } catch (e) { /* not kept */ }
      };
      let on = true;
      try { on = localStorage.getItem(SIDE_KEY) !== 'off'; } catch (e) { on = true; }
      toggle.addEventListener('click', () => setSide(body.classList.contains('inspector-off')));
      document.addEventListener('keydown', (e) => {
        if (e.altKey && e.metaKey && (e.key === 'i' || e.key === 'I' || e.code === 'KeyI') && !window.__scaffoldProWeb) { e.preventDefault(); setSide(body.classList.contains('inspector-off')); }
      });
      setTimeout(() => setSide(on), 0);
    }
    // Main column and inspector.
    const main = document.createElement('div');
    main.className = 'doc-main';
    const side = document.createElement('aside');
    side.className = 'inspector';
    side.setAttribute('aria-label', 'Details');
    side.innerHTML = '<div class="inspector-title">Details</div>';
    const sideNodes = cfg.side.map((sel) => body.querySelector(`:scope > ${sel}`) || body.querySelector(sel)).filter(Boolean);
    const rest = [...body.children].filter((el) => el !== bar && !sideNodes.includes(el));
    for (const el of rest) main.appendChild(el);
    for (const el of sideNodes) side.appendChild(el);
    // Details stays in view beside the document while it fits the window;
    // taller than that, it scrolls with the page (no scrollbar of its own).
    // (Measured against the window, not by switching back and forth.)
    const fit = () => {
      const css = (el, name) => parseFloat(getComputedStyle(el).getPropertyValue(name)) || 0;
      const room = window.innerHeight - css(document.documentElement, '--titlebar-safe') - css(body, '--doc-bar-h') - 32;
      const tall = side.scrollHeight > room + 1;
      if (side.classList.contains('tall') !== tall) side.classList.toggle('tall', tall);
    };
    if (window.ResizeObserver) { const ro = new ResizeObserver(fit); ro.observe(side); for (const el of sideNodes) ro.observe(el); }
    window.addEventListener('resize', fit);
    const wrap = document.createElement('div');
    wrap.className = 'doc-columns';
    wrap.append(main, side);
    body.appendChild(wrap);
    setupPickerFold(main);
  }

  // Add Materials: its list folds away (kept on this Mac) and opens by itself
  // as soon as you search; the line items stay in view.
  const FOLD_KEY = 'doc.pickerFolded';
  function setupPickerFold(main) {
    const results = main.querySelector('#picker-results');
    const col = results && results.parentElement;
    const head = col && col.querySelector('.am-head');
    const title = head && head.querySelector('h2');
    if (!col || !head || !title) return;
    const btn = document.createElement('button');
    btn.type = 'button';
    btn.className = 'picker-fold';
    btn.dataset.noIcon = '';
    btn.title = 'Show or hide the list of materials';
    btn.setAttribute('aria-label', 'Show or hide the list of materials');
    btn.innerHTML = window.icon ? window.icon('caret-down', 14) : '▾';
    title.prepend(btn);
    const set = (folded) => {
      col.classList.toggle('picker-folded', folded);
      btn.setAttribute('aria-expanded', folded ? 'false' : 'true');
      try { localStorage.setItem(FOLD_KEY, folded ? '1' : ''); } catch (e) { /* not kept */ }
    };
    let folded = false;
    try { folded = localStorage.getItem(FOLD_KEY) === '1'; } catch (e) { folded = false; }
    set(folded);
    btn.addEventListener('click', () => set(!col.classList.contains('picker-folded')));
    const search = head.querySelector('input');
    if (search) search.addEventListener('input', () => { if (search.value.trim()) set(false); });
  }

  // Breadcrumbs: Projects › the project › this document.
  function docCrumbs(kind) {
    const content = document.getElementById('content');
    if (!content || content.querySelector(':scope > .crumbs') || !window.crumbs) return;
    const back = document.getElementById('back-link');
    const href = back && back.getAttribute('href');
    const number = href && /number=([^&#]+)/.exec(href);
    const h1 = content.querySelector('h1');
    const here = h1 ? h1.textContent.trim() : (KIND[kind] || 'Document');
    const trail = [{ label: 'Projects', href: 'projects.html' }];
    if (number) trail.push({ label: decodeURIComponent(number[1]), href });
    else if (kind === 'letter') trail.push({ label: 'Letters', href: href || 'letters.html' });
    trail.push({ label: here });
    content.prepend(window.crumbs(trail));
  }

  window.docHeader = { refresh: show };
  function startShell() {
    const kind = PAGES[location.pathname.split('/').pop()];
    if (!kind || kind === 'project') return;
    setupDocShell(kind);
    // The title arrives with the document: crumbs once it's there.
    let tries = 30;
    const crumb = () => { const h1 = document.querySelector('#content h1'); if (h1 && h1.textContent.trim()) docCrumbs(kind); else if (tries-- > 0) setTimeout(crumb, 150); };
    crumb();
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', startShell);
  else startShell();

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', show);
  else show();
})();

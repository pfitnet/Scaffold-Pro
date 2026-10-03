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
  window.docHeader = { refresh: show };

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', show);
  else show();
})();

'use strict';

// "Created by Harry · Last worked on by William, 2 hours ago" beside a
// document's number (under a project's title). Loaded by the editors and the
// project page; it works out which record the page shows from its address.

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

  const STEP = { BOQ: 'BOQ', Quotation: 'Quotation', DeliveryNote: 'Delivery Notes', Invoice: 'Invoices' };
  function chainText(chain) {
    if (!chain.length) return '';
    const steps = [];
    for (const kind of ['BOQ', 'Quotation', 'DeliveryNote', 'Invoice']) {
      const docs = chain.filter((c) => c.kind === kind);
      if (!docs.length) continue;
      steps.push(`<span class="chain-step"><span class="chain-kind">${STEP[kind]}</span> ${docs.map((d) => d.current
        ? `<b class="chain-doc current">${esc(d.number)}</b>`
        : `<a class="chain-doc" href="${esc(d.url)}" title="${esc(d.status)}">${esc(d.number)}</a>`).join(' ')}</span>`);
    }
    return `<div class="doc-chain">${steps.join('<span class="chain-arrow">›</span>')}</div>`;
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
    // The linked documents: BOQ › Quotation › Delivery Notes › Invoices.
    let chain = [];
    if (id && ['boq', 'quotation', 'deliveryNote', 'invoice'].includes(kind) && window.api.authors.chain) {
      try { chain = (await window.api.authors.chain(kind, id)) || []; } catch (e) { chain = []; }
    }
    const chainHTML = chainText(chain);
    const authors = window.authorsText(a);
    if (!authors && !chainHTML) return;
    // A document's editor: who made it and who last worked on it at the
    // right of its number's row; the linked documents under the title.
    // Elsewhere both go under the title. (The page re-draws its title
    // block's contents; these sit outside it, so they stay.)
    const beside = kind !== 'project';
    const wait = (tries) => {
      const h1 = document.querySelector('#content h1');
      if (!h1) { if (tries > 0) setTimeout(() => wait(tries - 1), 200); return; }
      const block = h1.parentElement && h1.parentElement.id !== 'content' ? h1.parentElement : h1;
      if (beside && block !== h1 && authors) {
        let bar = block.parentElement.classList.contains('doc-titlebar') ? block.parentElement : null;
        if (!bar) {
          bar = document.createElement('div');
          bar.className = 'doc-titlebar';
          block.insertAdjacentElement('beforebegin', bar);
          bar.appendChild(block);
        }
        let side = bar.querySelector('.doc-authors-side');
        if (!side) {
          side = document.createElement('div');
          side.className = 'doc-authors-side';
          side.id = 'doc-authors-side';
          bar.appendChild(side);
        }
        side.innerHTML = authors;
        if (!chainHTML) return;
        let line = document.getElementById('doc-authors');
        if (!line) {
          line = document.createElement('div');
          line.id = 'doc-authors';
          line.className = 'doc-authors';
          bar.insertAdjacentElement('afterend', line);
        }
        line.innerHTML = chainHTML;
        return;
      }
      let line = document.getElementById('doc-authors');
      if (!line) {
        line = document.createElement('div');
        line.id = 'doc-authors';
        line.className = 'doc-authors';
        const after = block === h1 && h1.nextElementSibling && h1.nextElementSibling.classList.contains('subtitle') ? h1.nextElementSibling : block;
        after.insertAdjacentElement('afterend', line);
      }
      line.innerHTML = authors + chainHTML;
    };
    wait(25);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', show);
  else show();
})();

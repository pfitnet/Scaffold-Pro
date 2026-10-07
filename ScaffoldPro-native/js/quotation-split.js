'use strict';

// "Split…" on a quotation: tick the lines and sections to move to a new
// quotation (e.g. the manpower part to a quotation of its own). The new one
// isn't linked to this one; it's listed under it as its subsidiary.
//
//   const pick = await window.quotationSplit.open(detail, currencyLabel);
//   // → { lineIds, blockIds } or null when cancelled

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const money = (n) => Number(n || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const KIND = { Priced: 'Priced section', Rates: 'Rates', Note: 'Note' };

  function open(d, currency) {
    return new Promise((resolve) => {
      const materials = d.lineItems.filter((i) => !i.blockId && i.section !== 'Delivery');
      const delivery = d.lineItems.filter((i) => !i.blockId && i.section === 'Delivery');
      const total = (ids) => ids.reduce((sum, id) => sum + (d.lineTotals[id] || 0), 0);
      const lineRow = (l, no) => `<label class="qs-row"><input type="checkbox" data-line="${l.id}" />
          <span class="qs-no">${no}</span><span class="qs-desc">${esc(l.itemDescription.split('\n')[0])}</span>
          <span class="qs-qty">${Math.round(l.quantity)} ${esc(l.unit)}</span><span class="qs-amt">${money(d.lineTotals[l.id])}</span></label>`;
      const group = (title, rows) => rows ? `<div class="qs-group"><label class="qs-row qs-head"><input type="checkbox" class="qs-all" /><span>${title}</span></label>${rows}</div>` : '';
      const blocks = d.blocks.map((b) => {
        const rows = d.lineItems.filter((i) => i.blockId === b.id);
        const what = b.kind === 'Note' ? (b.note || '').split('\n')[0] : (b.title || 'Untitled');
        const count = b.kind === 'Note' ? '' : `${rows.length} ${b.kind === 'Rates' ? 'rate' : 'row'}${rows.length === 1 ? '' : 's'}`;
        return `<label class="qs-row"><input type="checkbox" data-block="${b.id}" />
          <span class="qs-no">${esc(KIND[b.kind] || b.kind)}</span><span class="qs-desc">${esc(what)}</span>
          <span class="qs-qty">${count}</span><span class="qs-amt">${b.kind === 'Priced' ? money(total(rows.map((r) => r.id))) : ''}</span></label>`;
      }).join('');

      const sheet = document.createElement('div');
      sheet.className = 'modal-backdrop';
      sheet.innerHTML = `
        <div class="modal wide qs-sheet" role="dialog" aria-labelledby="qs-title">
          <h2 id="qs-title">Split ${esc(d.quotationNumber)}</h2>
          <p class="small-note">What you tick moves to a new quotation of this project, with the next number and this one’s letter details (subject, refs, pricing, markup, terms). It isn’t linked to this one — each is changed on its own — and is listed under it. If this quotation is linked to a BOQ, the new one is too (the BOQ keeps both’s items). The items’ deliveries on the delivery schedule go with them; drawings stay here.</p>
          <div class="qs-list">
            ${group('Items', materials.map((l, n) => lineRow(l, n + 1)).join(''))}
            ${group('Delivery charges', delivery.map((l, n) => lineRow(l, `D${n + 1}`)).join(''))}
            ${group('Sections', blocks)}
          </div>
          <p class="small-note" id="qs-summary"></p>
          <div class="error-text hidden" id="qs-error"></div>
          <div class="actions">
            <button id="qs-cancel">Cancel</button>
            <button class="primary" id="qs-split" disabled>Split</button>
          </div>
        </div>`;
      document.body.appendChild(sheet);
      const $ = (sel) => sheet.querySelector(sel);
      const picked = () => ({
        lineIds: [...sheet.querySelectorAll('input[data-line]:checked')].map((c) => c.dataset.line),
        blockIds: [...sheet.querySelectorAll('input[data-block]:checked')].map((c) => c.dataset.block),
      });
      const update = () => {
        for (const g of sheet.querySelectorAll('.qs-group')) {
          const boxes = [...g.querySelectorAll('input[data-line], input[data-block]')];
          const on = boxes.filter((c) => c.checked).length;
          const all = g.querySelector('.qs-all');
          all.checked = on > 0 && on === boxes.length;
          all.indeterminate = on > 0 && on < boxes.length;
        }
        const p = picked();
        const amount = total(p.lineIds) + total(d.lineItems.filter((i) => p.blockIds.includes(i.blockId) && d.blocks.find((b) => b.id === i.blockId)?.kind === 'Priced').map((i) => i.id));
        const parts = [];
        if (p.lineIds.length) parts.push(`${p.lineIds.length} line${p.lineIds.length === 1 ? '' : 's'}`);
        if (p.blockIds.length) parts.push(`${p.blockIds.length} section${p.blockIds.length === 1 ? '' : 's'}`);
        $('#qs-summary').textContent = parts.length ? `Moving ${parts.join(' and ')}${amount ? ` — ${currency} ${money(amount)}` : ''}.` : 'Tick what to move.';
        $('#qs-split').disabled = !parts.length;
      };
      for (const all of sheet.querySelectorAll('.qs-all')) {
        all.addEventListener('change', () => {
          for (const c of all.closest('.qs-group').querySelectorAll('input[data-line], input[data-block]')) c.checked = all.checked;
          update();
        });
      }
      sheet.addEventListener('change', update);
      const close = (value) => { sheet.remove(); resolve(value); };
      $('#qs-cancel').addEventListener('click', () => close(null));
      $('#qs-split').addEventListener('click', () => close(picked()));
      sheet.addEventListener('keydown', (e) => { if (e.key === 'Escape') { e.preventDefault(); close(null); } });
      sheet.addEventListener('mousedown', (e) => { if (e.target === sheet) close(null); });
      update();
      const first = sheet.querySelector('input[type=checkbox]');
      if (first) first.focus();
    });
  }

  window.quotationSplit = { open };
})();

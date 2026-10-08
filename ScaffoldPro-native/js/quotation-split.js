'use strict';

// "Split…" on a quotation: tick the lines and sections to move to a new
// quotation (e.g. the manpower part to a quotation of its own). The new one
// isn't linked to this one; it's listed under it as its subsidiary.
//
//   const pick = await window.quotationSplit.open(detail, currencyLabel, schedule);
//   // → { lineIds, blockIds, partial } or null when cancelled
//
// An item can be split by quantity: "Move [3] of 10". Its deliveries on the
// schedule go with the part moved: from its only day by themselves, else
// the sheet asks which days they come off (they go on the same days of the
// new quotation's schedule). `partial` is { lineId: { quantity, days: {
// dayId: how many } } }.

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const money = (n) => Number(n || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const KIND = { Priced: 'Priced section', Rates: 'Rates', Note: 'Note' };

  function open(d, currency, schedule) {
    return new Promise((resolve) => {
      const days = (schedule && schedule.days) || [];
      const fmtDay = (iso) => { const x = new Date(`${iso}T00:00:00`); return isNaN(x) ? '' : x.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace('Sept', 'Sep'); };
      // Where a line's quantity is on the schedule: [{ id, label, qty }] and
      // how many aren't on it yet.
      const sources = (l) => {
        const on = days.filter((day) => (day.quantities || {})[l.id] > 0)
          .map((day) => ({ id: day.id, qty: day.quantities[l.id],
            label: `Day ${day.day}${day.date ? ` · ${fmtDay(day.date)}` : ''}${day.sent ? ' · delivered' : ''}` }));
        const scheduled = on.reduce((a, x) => a + x.qty, 0);
        return { on, free: Math.max(0, Math.round(l.quantity) - scheduled) };
      };
      const materials = d.lineItems.filter((i) => !i.blockId && i.section !== 'Delivery');
      const delivery = d.lineItems.filter((i) => !i.blockId && i.section === 'Delivery');
      const total = (ids) => ids.reduce((sum, id) => sum + (d.lineTotals[id] || 0), 0);
      const lineRow = (l, no) => {
        const whole = Math.round(l.quantity);
        const src = sources(l);
        // Asked only when the part moved could come off more than one place.
        const ask = src.on.length + (src.free > 0 ? 1 : 0) > 1 && src.on.length > 0;
        const dayRows = ask ? src.on.map((x) => `<label class="qs-day"><span>${esc(x.label)}</span><span class="qs-day-of">${x.qty} on it</span>
            <input type="number" min="0" max="${x.qty}" step="1" value="0" data-day="${x.id}" data-max="${x.qty}" /></label>`).join('')
          + (src.free > 0 ? `<label class="qs-day"><span>Not on the schedule yet</span><span class="qs-day-of">${src.free}</span>
            <input type="number" min="0" max="${src.free}" step="1" value="0" data-free data-max="${src.free}" /></label>` : '') : '';
        return `<div class="qs-line" data-for="${l.id}"><label class="qs-row"><input type="checkbox" data-line="${l.id}" />
          <span class="qs-no">${no}</span><span class="qs-desc">${esc(l.itemDescription.split('\n')[0])}</span>
          <span class="qs-qty">${whole > 1 ? `<span class="qs-move-wrap">Move <input type="number" class="qs-move" min="1" max="${whole}" step="1" value="${whole}" disabled /> of</span> ` : ''}${whole} ${esc(l.unit)}</span>
          <span class="qs-amt">${money(d.lineTotals[l.id])}</span></label>
          ${ask ? `<div class="qs-days hidden"><div class="qs-days-head">Which deliveries go with them? <span class="qs-days-sum"></span></div>${dayRows}</div>` : ''}</div>`;
      };
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
          <p class="small-note">What you tick moves to a new quotation of this project, with the next number and this one’s letter details (subject, refs, pricing, markup, terms). It isn’t linked to this one — each is changed on its own — and is listed under it. If this quotation is linked to a BOQ, the new one is too (the BOQ keeps both’s items). To move only some of an item, change how many. The items’ deliveries on the delivery schedule go with them (you’re asked which days, when there’s a choice); drawings stay here.</p>
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
      const lineOf = (id) => d.lineItems.find((l) => l.id === id);
      // Each ticked line: all of it, or part (with where its deliveries come from).
      const picked = () => {
        const lineIds = [];
        const partial = {};
        let unsure = '';
        for (const c of sheet.querySelectorAll('input[data-line]:checked')) {
          const l = lineOf(c.dataset.line);
          const whole = Math.round(l.quantity);
          const box = c.closest('.qs-line');
          const moveBox = box.querySelector('.qs-move');
          const n = moveBox ? Math.max(1, Math.min(whole, Math.round(Number(moveBox.value) || 0))) : whole;
          if (n >= whole) { lineIds.push(l.id); continue; }
          const src = sources(l);
          const dayAmounts = {};
          if (box.querySelector('.qs-days')) {
            let chosen = 0;
            for (const i of box.querySelectorAll('.qs-days input')) {
              const v = Math.max(0, Math.min(Number(i.dataset.max), Math.round(Number(i.value) || 0)));
              chosen += v;
              if (v && i.dataset.day) dayAmounts[i.dataset.day] = v;
            }
            if (chosen !== n && !unsure) unsure = `Say which deliveries the ${n} ${l.unit || ''} of “${l.itemDescription.split('\n')[0]}” come from (${chosen} of ${n} chosen).`.replace(/\s+of “/, ' of “');
          } else if (src.on.length === 1) {
            dayAmounts[src.on[0].id] = Math.min(n, src.on[0].qty);
          }
          partial[l.id] = { quantity: n, days: dayAmounts };
        }
        return {
          lineIds,
          blockIds: [...sheet.querySelectorAll('input[data-block]:checked')].map((c) => c.dataset.block),
          partial, unsure,
        };
      };
      const update = () => {
        for (const g of sheet.querySelectorAll('.qs-group')) {
          const boxes = [...g.querySelectorAll('input[data-line], input[data-block]')];
          const on = boxes.filter((c) => c.checked).length;
          const all = g.querySelector('.qs-all');
          all.checked = on > 0 && on === boxes.length;
          all.indeterminate = on > 0 && on < boxes.length;
        }
        // Part of a line: its quantity box, and the days to say.
        for (const box of sheet.querySelectorAll('.qs-line')) {
          const on = box.querySelector('input[data-line]').checked;
          const moveBox = box.querySelector('.qs-move');
          if (moveBox) moveBox.disabled = !on;
          const l = lineOf(box.dataset.for);
          const n = moveBox ? Math.round(Number(moveBox.value) || 0) : Math.round(l.quantity);
          const daysBox = box.querySelector('.qs-days');
          if (daysBox) {
            const part = on && n > 0 && n < Math.round(l.quantity);
            daysBox.classList.toggle('hidden', !part);
            const chosen = [...daysBox.querySelectorAll('input')].reduce((a, i) => a + (Math.round(Number(i.value) || 0)), 0);
            const sum = daysBox.querySelector('.qs-days-sum');
            sum.textContent = `${chosen} of ${n} chosen`;
            sum.classList.toggle('ok', chosen === n);
          }
        }
        const p = picked();
        const partAmount = Object.entries(p.partial).reduce((a, [id, x]) => a + (d.lineTotals[id] || 0) * x.quantity / (Math.round(lineOf(id).quantity) || 1), 0);
        const amount = partAmount + total(p.lineIds) + total(d.lineItems.filter((i) => p.blockIds.includes(i.blockId) && d.blocks.find((b) => b.id === i.blockId)?.kind === 'Priced').map((i) => i.id));
        const parts = [];
        if (p.lineIds.length) parts.push(`${p.lineIds.length} line${p.lineIds.length === 1 ? '' : 's'}`);
        const partCount = Object.keys(p.partial).length;
        if (partCount) parts.push(`part of ${partCount} line${partCount === 1 ? '' : 's'}`);
        if (p.blockIds.length) parts.push(`${p.blockIds.length} section${p.blockIds.length === 1 ? '' : 's'}`);
        $('#qs-summary').textContent = parts.length ? `Moving ${parts.join(' and ')}${amount ? ` — ${currency} ${money(amount)}` : ''}.` : 'Tick what to move.';
        $('#qs-split').disabled = !parts.length || !!p.unsure;
        if (p.unsure) $('#qs-summary').textContent = p.unsure;
      };
      for (const all of sheet.querySelectorAll('.qs-all')) {
        all.addEventListener('change', () => {
          for (const c of all.closest('.qs-group').querySelectorAll('input[data-line], input[data-block]')) c.checked = all.checked;
          update();
        });
      }
      sheet.addEventListener('change', update);
      sheet.addEventListener('input', (e) => { if (e.target.matches('.qs-move, .qs-days input')) update(); });
      // Typing in a quantity doesn't tick or untick the line.
      sheet.addEventListener('click', (e) => { if (e.target.matches('.qs-move, .qs-days input')) e.stopPropagation(); }, true);
      const close = (value) => { sheet.remove(); resolve(value); };
      $('#qs-cancel').addEventListener('click', () => close(null));
      $('#qs-split').addEventListener('click', () => {
        const p = picked();
        if (p.unsure) return;
        close({ lineIds: p.lineIds, blockIds: p.blockIds, partial: p.partial });
      });
      sheet.addEventListener('keydown', (e) => { if (e.key === 'Escape') { e.preventDefault(); close(null); } });
      sheet.addEventListener('mousedown', (e) => { if (e.target === sheet) close(null); });
      update();
      const first = sheet.querySelector('input[type=checkbox]');
      if (first) first.focus();
    });
  }

  window.quotationSplit = { open };
})();

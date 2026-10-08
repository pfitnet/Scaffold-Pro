'use strict';

// "Split…" on a quotation: part of it goes to a new quotation of the same
// project, listed under this one as its subsidiary (not linked to it).
//
//   const pick = await window.quotationSplit.open(detail, currencyLabel, schedule);
//   // → { lineIds, blockIds, partial } or null when cancelled
//
// Two ways to say what goes:
//   • Move to new — tick what goes; change "New" to move only part of an item.
//   • Keep here  — say how many of each item stay; the rest overflows to the
//     new quotation (e.g. keep 100 of each ticked item).
// Every item row shows both sides, "Stays here" and "Goes to new", linked:
// typing in either sets the other. A part of an item takes its deliveries
// with it: from its only day by themselves, else the row asks which days
// (they go on the same days of the new quotation's schedule). `partial` is
// { lineId: { quantity, days: { dayId: how many } } }.

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const money = (n) => Number(n || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const count = (n) => Number(n || 0).toLocaleString('en-US', { maximumFractionDigits: 2 });
  const KIND = { Priced: 'Priced section', Rates: 'Rates', Note: 'Note' };
  const MODE_KEY = 'scaffoldpro.splitMode';

  function open(d, currency, schedule) {
    return new Promise((resolve) => {
      const days = (schedule && schedule.days) || [];
      const fmtDay = (iso) => { const x = new Date(`${iso}T00:00:00`); return isNaN(x) ? '' : x.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace('Sept', 'Sep'); };
      const lines = d.lineItems.filter((i) => !i.blockId);
      const materials = lines.filter((i) => i.section !== 'Delivery');
      const delivery = lines.filter((i) => i.section === 'Delivery');
      const whole = (l) => Math.round(Number(l.quantity) || 0);
      const lineOf = (id) => d.lineItems.find((l) => l.id === id);
      // Where a line's quantity is on the schedule, and how many aren't on it.
      const sources = (l) => {
        const on = days.filter((day) => (day.quantities || {})[l.id] > 0)
          .map((day) => ({ id: day.id, qty: day.quantities[l.id],
            label: `Day ${day.day}${day.date ? ` · ${fmtDay(day.date)}` : ''}${day.sent ? ' · delivered' : ''}` }));
        const scheduled = on.reduce((a, x) => a + x.qty, 0);
        return { on, free: Math.max(0, whole(l) - scheduled) };
      };
      const blockRows = (b) => d.lineItems.filter((i) => i.blockId === b.id);
      const blockTotal = (b) => b.kind === 'Priced' ? blockRows(b).reduce((a, r) => a + (d.lineTotals[r.id] || 0), 0) : 0;

      // How many of each line go to the new quotation; which sections go.
      const moving = {};
      for (const l of lines) moving[l.id] = 0;
      const movingBlocks = new Set();
      const dayPicks = {}; // lineId → { dayId|'free': how many }
      let mode = 'move';
      try { if (localStorage.getItem(MODE_KEY) === 'keep') mode = 'keep'; } catch (e) { /* default */ }

      const itemRow = (l, no) => {
        const n = whole(l);
        return `<div class="qs-line" data-for="${l.id}">
          <div class="qs-row" data-line="${l.id}">
            <span class="qs-check"><input type="checkbox" data-tick="${l.id}" aria-label="Split ${esc(l.itemDescription.split('\n')[0])}" /></span>
            <span class="qs-no">${esc(no)}</span>
            <span class="qs-desc" title="${esc(l.itemDescription)}">${esc(l.itemDescription.split('\n')[0])}<span class="qs-of">${count(n)} ${esc(l.unit || '')}</span></span>
            <span class="qs-side here"><input type="number" class="qs-num" data-side="here" min="0" max="${n}" step="1" value="${n}" aria-label="Stays here" /></span>
            <span class="qs-arrow" aria-hidden="true">→</span>
            <span class="qs-side new"><input type="number" class="qs-num" data-side="new" min="0" max="${n}" step="1" value="0" aria-label="Goes to the new quotation" /></span>
            <span class="qs-amt" data-amt="${l.id}"></span>
          </div>
          <div class="qs-days hidden"></div>
        </div>`;
      };
      const blockRow = (b) => {
        const what = b.kind === 'Note' ? (b.note || '').split('\n')[0] : (b.title || 'Untitled');
        const rows = blockRows(b);
        const size = b.kind === 'Note' ? '' : `${rows.length} ${b.kind === 'Rates' ? 'rate' : 'row'}${rows.length === 1 ? '' : 's'}`;
        return `<div class="qs-line" data-block-for="${b.id}">
          <div class="qs-row qs-block" data-block="${b.id}">
            <span class="qs-check"><input type="checkbox" data-tick-block="${b.id}" aria-label="Split ${esc(what)}" /></span>
            <span class="qs-no">${esc(b.prefix || '')}</span>
            <span class="qs-desc">${esc(what)}<span class="qs-of">${esc(KIND[b.kind] || b.kind)}${size ? ` · ${size}` : ''}</span></span>
            <span class="qs-whole">Whole section</span>
            <span class="qs-amt" data-block-amt="${b.id}"></span>
          </div>
        </div>`;
      };
      const group = (key, title, rows) => rows ? `<section class="qs-group" data-group="${key}">
          <div class="qs-group-head"><label><input type="checkbox" class="qs-all" /> ${esc(title)}</label><span class="qs-group-note"></span></div>${rows}</section>` : '';

      const sheet = document.createElement('div');
      sheet.className = 'modal-backdrop';
      sheet.innerHTML = `
        <div class="modal wide qs-sheet" role="dialog" aria-labelledby="qs-title">
          <div class="qs-top">
            <div>
              <h2 id="qs-title">Split ${esc(d.quotationNumber)}</h2>
              <p class="qs-how" id="qs-how"></p>
            </div>
            <div class="segmented qs-mode" role="tablist" aria-label="How to split">
              <button type="button" data-mode="move" data-no-icon>Move to new</button>
              <button type="button" data-mode="keep" data-no-icon>Keep here</button>
            </div>
          </div>
          <div class="qs-tools">
            <input type="search" class="qs-filter" placeholder="Find an item…" aria-label="Find an item" />
            <span class="qs-bulk">
              <span class="qs-bulk-label" id="qs-bulk-label"></span>
              <input type="number" class="qs-bulk-n" min="0" step="1" placeholder="0" aria-label="How many" />
              <span class="qs-bulk-tail">of each ticked item</span>
              <button type="button" class="qs-bulk-apply" disabled>Apply</button>
            </span>
          </div>
          <div class="qs-list">
            <div class="qs-cols" aria-hidden="true">
              <span></span><span>No</span><span>Item</span>
              <span class="qs-col-here" title="Stays on ${esc(d.quotationNumber)}">Stays here</span><span></span><span class="qs-col-new" title="Goes to the new quotation">Goes to new</span>
              <span class="qs-col-amt">Moving (${esc(currency)})</span>
            </div>
            ${group('items', 'Items', materials.map((l, i) => itemRow(l, String(i + 1))).join(''))}
            ${group('delivery', 'Delivery charges', delivery.map((l, i) => itemRow(l, `D${i + 1}`)).join(''))}
            ${group('blocks', 'Sections', d.blocks.map(blockRow).join(''))}
            <div class="qs-empty hidden">No item matches.</div>
          </div>
          <div class="qs-summary">
            <div class="qs-card stays"><span class="qs-card-label">Stays on ${esc(d.quotationNumber)}</span><b id="qs-stays-amt"></b><span id="qs-stays-n"></span></div>
            <div class="qs-card goes"><span class="qs-card-label">Goes to the new quotation</span><b id="qs-goes-amt"></b><span id="qs-goes-n"></span></div>
          </div>
          <p class="qs-message" id="qs-message" role="status"></p>
          <div class="actions">
            <span class="qs-foot-note left">Deliveries on the schedule go with what moves; drawings stay here. Linked to a BOQ? The new one is too.</span>
            <button id="qs-cancel">Cancel</button>
            <button class="primary" id="qs-split" disabled>Split</button>
          </div>
        </div>`;
      document.body.appendChild(sheet);
      const $ = (sel) => sheet.querySelector(sel);
      const $$ = (sel) => [...sheet.querySelectorAll(sel)];

      // ---- the day question, for a part of an item ----
      function drawDays(l) {
        const box = sheet.querySelector(`.qs-line[data-for="${l.id}"] .qs-days`);
        const n = moving[l.id];
        const src = sources(l);
        const ask = n > 0 && n < whole(l) && src.on.length > 0 && src.on.length + (src.free > 0 ? 1 : 0) > 1;
        box.classList.toggle('hidden', !ask);
        if (!ask) { delete dayPicks[l.id]; box.innerHTML = ''; return; }
        const picks = dayPicks[l.id] || (dayPicks[l.id] = {});
        const rows = src.on.map((x) => ({ key: x.id, label: x.label, max: x.qty }))
          .concat(src.free > 0 ? [{ key: 'free', label: 'Not on the schedule yet', max: src.free }] : []);
        if (!box.innerHTML) {
          box.innerHTML = `<div class="qs-days-head"><span>Which of its deliveries go with the ${count(n)}?</span><span class="qs-days-sum"></span></div>` +
            rows.map((r) => `<label class="qs-day"><span>${esc(r.label)}</span><span class="qs-day-of">${count(r.max)} there</span>
              <input type="number" min="0" max="${r.max}" step="1" value="${picks[r.key] || 0}" data-day="${r.key}" data-max="${r.max}" />
              <button type="button" class="qs-day-all" data-day-all="${r.key}" data-no-icon>All</button></label>`).join('');
        }
        box.querySelector('.qs-days-head span').textContent = `Which of its deliveries go with the ${count(n)}?`;
        const chosen = rows.reduce((a, r) => a + (picks[r.key] || 0), 0);
        const sum = box.querySelector('.qs-days-sum');
        sum.textContent = chosen === n ? `${count(chosen)} of ${count(n)} ✓` : `${count(chosen)} of ${count(n)} chosen`;
        sum.classList.toggle('ok', chosen === n);
      }

      // ---- one row redrawn from `moving` ----
      function drawLine(l) {
        const n = whole(l);
        const m = moving[l.id];
        const row = sheet.querySelector(`.qs-row[data-line="${l.id}"]`);
        const tick = row.querySelector('[data-tick]');
        tick.checked = m > 0;
        tick.indeterminate = m > 0 && m < n;
        row.classList.toggle('on', m > 0);
        row.classList.toggle('part', m > 0 && m < n);
        const here = row.querySelector('[data-side="here"]');
        const neu = row.querySelector('[data-side="new"]');
        if (document.activeElement !== here) here.value = n - m;
        if (document.activeElement !== neu) neu.value = m;
        const amount = n ? (d.lineTotals[l.id] || 0) * m / n : 0;
        sheet.querySelector(`[data-amt="${l.id}"]`).textContent = m > 0 ? money(amount) : '';
        drawDays(l);
      }

      function setMoving(l, value) {
        const n = whole(l);
        moving[l.id] = Math.max(0, Math.min(n, Math.round(Number(value) || 0)));
        drawLine(l);
        update();
      }

      // ---- everything ticked, as the native side wants it ----
      function picked() {
        const lineIds = [];
        const partial = {};
        let unsure = '';
        for (const l of lines) {
          const m = moving[l.id];
          if (!m) continue;
          if (m >= whole(l)) { lineIds.push(l.id); continue; }
          const src = sources(l);
          const days = {};
          if (dayPicks[l.id]) {
            const picks = dayPicks[l.id];
            const chosen = Object.values(picks).reduce((a, v) => a + v, 0);
            for (const [k, v] of Object.entries(picks)) if (k !== 'free' && v > 0) days[k] = v;
            if (chosen !== m && !unsure) unsure = `Say which deliveries the ${count(m)} ${lineOf(l.id).unit || ''} of “${l.itemDescription.split('\n')[0]}” come from.`.replace(/\s+of “/, ' of “');
          } else if (src.on.length === 1) {
            days[src.on[0].id] = Math.min(m, src.on[0].qty);
          }
          partial[l.id] = { quantity: m, days };
        }
        return { lineIds, blockIds: [...movingBlocks], partial, unsure };
      }

      function update() {
        // Groups' tick-all boxes, for the rows shown.
        for (const g of $$('.qs-group')) {
          const boxes = [...g.querySelectorAll('.qs-line:not(.hidden) [data-tick], .qs-line:not(.hidden) [data-tick-block]')];
          const on = boxes.filter((c) => c.checked || c.indeterminate).length;
          const all = g.querySelector('.qs-all');
          all.checked = on > 0 && on === boxes.length;
          all.indeterminate = on > 0 && on < boxes.length;
          const note = g.querySelector('.qs-group-note');
          const total = g.querySelectorAll('.qs-line').length;
          const ticked = g.querySelectorAll('[data-tick]:checked, [data-tick-block]:checked').length;
          note.textContent = ticked ? `${ticked} of ${total} splitting` : '';
        }
        // Stays / goes.
        let goes = 0, stays = 0, goesN = 0, staysN = 0, goesB = 0, staysB = 0;
        for (const l of lines) {
          const n = whole(l), m = moving[l.id], t = d.lineTotals[l.id] || 0;
          const part = n ? t * m / n : 0;
          goes += part; stays += t - part;
          if (m > 0) goesN++;
          if (m < n || n === 0) staysN++;
        }
        for (const b of d.blocks) {
          if (movingBlocks.has(b.id)) { goes += blockTotal(b); goesB++; } else { stays += blockTotal(b); staysB++; }
        }
        const what = (n, b) => [n ? `${n} line${n === 1 ? '' : 's'}` : '', b ? `${b} section${b === 1 ? '' : 's'}` : ''].filter(Boolean).join(' · ');
        $('#qs-stays-amt').textContent = `${currency} ${money(stays)}`;
        $('#qs-goes-amt').textContent = `${currency} ${money(goes)}`;
        $('#qs-stays-n').textContent = what(staysN, staysB) || 'Nothing';
        $('#qs-goes-n').textContent = what(goesN, goesB) || 'Nothing yet';
        const p = picked();
        const anything = p.lineIds.length || p.blockIds.length || Object.keys(p.partial).length;
        const everything = !Object.keys(p.partial).length && p.lineIds.length === lines.length && p.blockIds.length === d.blocks.length;
        let message = '';
        if (!anything) message = mode === 'keep' ? 'Tick items and say how many stay here — the rest goes to the new quotation.' : 'Tick what goes to the new quotation.';
        else if (everything) message = 'That’s everything — leave at least one line or section here.';
        else if (p.unsure) message = p.unsure;
        $('#qs-message').textContent = message;
        $('#qs-message').classList.toggle('warn', !!(anything && (everything || p.unsure)));
        $('#qs-split').disabled = !anything || everything || !!p.unsure;
        $('.qs-bulk-apply').disabled = !$$('[data-tick]:checked').length || $('.qs-bulk-n').value === '';
      }

      function drawMode() {
        for (const b of $$('.qs-mode button')) b.classList.toggle('active', b.dataset.mode === mode);
        sheet.querySelector('.qs-sheet').dataset.mode = mode;
        $('#qs-how').textContent = mode === 'keep'
          ? 'Say how many of each item stay on this quotation. Whatever is over that goes to the new one.'
          : 'Tick what goes to a new quotation. Change “Goes to new” to move only part of an item.';
        $('#qs-bulk-label').textContent = mode === 'keep' ? 'Keep' : 'Move';
        try { localStorage.setItem(MODE_KEY, mode); } catch (e) { /* not kept */ }
      }

      // ---- interaction ----
      const focusField = (l) => {
        const input = sheet.querySelector(`.qs-row[data-line="${l.id}"] [data-side="${mode === 'keep' ? 'here' : 'new'}"]`);
        input.focus();
        input.select();
      };
      function toggle(l, on) {
        if (!on) { setMoving(l, 0); return; }
        // Move: all of it goes. Keep: all of it goes until you say how many stay.
        setMoving(l, whole(l));
        if (mode === 'keep') focusField(l);
      }
      sheet.addEventListener('click', (e) => {
        const tick = e.target.closest('[data-tick]');
        if (tick) { toggle(lineOf(tick.dataset.tick), tick.checked); return; }
        const tickBlock = e.target.closest('[data-tick-block]');
        if (tickBlock) {
          if (tickBlock.checked) movingBlocks.add(tickBlock.dataset.tickBlock); else movingBlocks.delete(tickBlock.dataset.tickBlock);
          tickBlock.closest('.qs-row').classList.toggle('on', tickBlock.checked);
          update();
          return;
        }
        const dayAll = e.target.closest('[data-day-all]');
        if (dayAll) {
          const input = dayAll.parentElement.querySelector('input');
          const id = dayAll.closest('.qs-line').dataset.for;
          const picks = dayPicks[id] || (dayPicks[id] = {});
          const others = Object.entries(picks).filter(([k]) => k !== input.dataset.day).reduce((a, [, v]) => a + v, 0);
          const v = Math.max(0, Math.min(Number(input.dataset.max), moving[id] - others));
          picks[input.dataset.day] = v;
          input.value = v;
          drawDays(lineOf(id));
          update();
          return;
        }
        // A click on the row itself (not on a box in it) ticks it.
        const row = e.target.closest('.qs-row');
        if (row && !e.target.closest('input, button, label')) {
          row.querySelector('[data-tick], [data-tick-block]').click();
        }
      });
      sheet.addEventListener('input', (e) => {
        const t = e.target;
        if (t.matches('.qs-num')) {
          const l = lineOf(t.closest('.qs-row').dataset.line);
          const v = Math.round(Number(t.value) || 0);
          setMoving(l, t.dataset.side === 'new' ? v : whole(l) - v);
        } else if (t.matches('.qs-days input')) {
          const id = t.closest('.qs-line').dataset.for;
          const picks = dayPicks[id] || (dayPicks[id] = {});
          picks[t.dataset.day] = Math.max(0, Math.min(Number(t.dataset.max), Math.round(Number(t.value) || 0)));
          drawDays(lineOf(id));
          update();
        } else if (t.matches('.qs-filter')) {
          const q = t.value.trim().toLowerCase();
          let shown = 0;
          for (const box of $$('.qs-line')) {
            const text = box.querySelector('.qs-desc').textContent.toLowerCase();
            const hide = !!q && !text.includes(q);
            box.classList.toggle('hidden', hide);
            if (!hide) shown++;
          }
          for (const g of $$('.qs-group')) g.classList.toggle('hidden', !g.querySelector('.qs-line:not(.hidden)'));
          $('.qs-empty').classList.toggle('hidden', shown > 0);
          update();
        } else if (t.matches('.qs-bulk-n')) update();
      });
      // A number box left out of range shows what was kept.
      sheet.addEventListener('change', (e) => {
        if (e.target.matches('.qs-num')) drawLine(lineOf(e.target.closest('.qs-row').dataset.line));
        if (e.target.matches('.qs-all')) {
          const g = e.target.closest('.qs-group');
          for (const box of g.querySelectorAll('.qs-line:not(.hidden)')) {
            if (box.dataset.for) {
              const l = lineOf(box.dataset.for);
              moving[l.id] = e.target.checked ? whole(l) : 0;
              drawLine(l);
            } else {
              const id = box.dataset.blockFor;
              if (e.target.checked) movingBlocks.add(id); else movingBlocks.delete(id);
              const c = box.querySelector('[data-tick-block]');
              c.checked = e.target.checked;
              c.closest('.qs-row').classList.toggle('on', c.checked);
            }
          }
          update();
        }
      });
      // Return / ↑ / ↓ in a number box: the same box on the next (or previous) row.
      sheet.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') { e.preventDefault(); close(null); return; }
        const t = e.target;
        if (!t.matches || !t.matches('.qs-num')) return;
        if (e.key !== 'Enter' && e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
        e.preventDefault();
        const same = $$(`.qs-line:not(.hidden) .qs-num[data-side="${t.dataset.side}"]`);
        const next = same[same.indexOf(t) + (e.key === 'ArrowUp' ? -1 : 1)];
        if (next) { next.focus(); next.select(); }
      });
      for (const b of $$('.qs-mode button')) {
        b.addEventListener('click', () => { mode = b.dataset.mode; drawMode(); update(); });
      }
      $('.qs-bulk-apply').addEventListener('click', () => {
        const n = Math.max(0, Math.round(Number($('.qs-bulk-n').value) || 0));
        for (const c of $$('[data-tick]:checked')) {
          const l = lineOf(c.dataset.tick);
          moving[l.id] = Math.max(0, Math.min(whole(l), mode === 'keep' ? whole(l) - n : n));
          drawLine(l);
        }
        update();
      });
      $('.qs-bulk-n').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); $('.qs-bulk-apply').click(); } });

      const close = (value) => { sheet.remove(); resolve(value); };
      $('#qs-cancel').addEventListener('click', () => close(null));
      $('#qs-split').addEventListener('click', () => {
        const p = picked();
        if (p.unsure) return;
        close({ lineIds: p.lineIds, blockIds: p.blockIds, partial: p.partial });
      });
      sheet.addEventListener('mousedown', (e) => { if (e.target === sheet) close(null); });

      drawMode();
      for (const l of lines) drawLine(l);
      update();
      $('.qs-filter').focus();
    });
  }

  window.quotationSplit = { open };
})();

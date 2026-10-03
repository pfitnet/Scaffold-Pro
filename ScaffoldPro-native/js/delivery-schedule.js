'use strict';

// A quotation's or a BOQ's delivery schedule: its materials down the side,
// Day 1, Day 2… across, and how many of each go to site that day. Each day
// can have a date, be ticked once delivered, and have a note. "Left" is
// what hasn't been put on any day yet. A plan / record only — not connected
// to the stock list. A quotation can copy its BOQ's schedule.
//
//   window.deliverySchedule.setup(id, 'quotation' | 'boq');
//   window.deliverySchedule.refresh(detail);   // after the document reloads

(function () {
  let quotationId = null;
  let kind = 'quotation';
  let detail = null;
  let data = { days: [], weights: {} };
  const api = () => (kind === 'boq' ? window.api.boq : window.api.quotations);
  const isBOQ = () => kind === 'boq';

  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const num = (v) => Number(v || 0).toLocaleString('en-US', { maximumFractionDigits: 0 });
  const kg = (v) => (v >= 1000 ? `${(v / 1000).toLocaleString('en-US', { maximumFractionDigits: 2 })} t` : `${v.toLocaleString('en-US', { maximumFractionDigits: 1 })} kg`);

  // The quoted materials: not delivery charges, not the extra sections' rows.
  function materials() {
    return ((detail && detail.lineItems) || [])
      .filter((l) => !l.blockId && l.section !== 'Delivery')
      .sort((a, b) => a.sortOrder - b.sortOrder);
  }

  function scheduled(lineId) {
    return data.days.reduce((a, d) => a + (Number(d.quantities[lineId]) || 0), 0);
  }

  function dayWeight(day) {
    return materials().reduce((a, l) => a + (Number(day.quantities[l.id]) || 0) * (data.weights[l.id] || 0), 0);
  }

  async function load() {
    if (!quotationId) return;
    const r = await api().deliverySchedule(quotationId);
    data = { days: (r && r.days) || [], weights: (r && r.weights) || {} };
    render();
  }

  function render() {
    const box = document.getElementById('ds-table');
    if (!box) return;
    const lines = materials();
    if (!lines.length) {
      box.innerHTML = `<div class="empty-state"><h2>No materials yet</h2><p>Add materials to the ${isBOQ() ? 'BOQ' : 'quotation'}, then plan their delivery here.</p></div>`;
      return;
    }
    if (!data.days.length) {
      box.innerHTML = '<div class="empty-state"><h2>No delivery days yet</h2><p>Use “+ Add Day” for Day 1, then put in how many of each material go that day.</p></div>';
      return;
    }
    const head = data.days.map((d) => `
      <th class="ds-day ${d.sent ? 'ds-sent' : ''}" data-day="${esc(d.id)}">
        <div class="ds-day-title"><span>Day ${d.day}</span>
          <button class="ds-remove" data-remove="${esc(d.id)}" title="Remove Day ${d.day}" aria-label="Remove Day ${d.day}">×</button></div>
        <input type="date" class="ds-date" value="${esc(d.date || '')}" title="Date (optional)" />
        <label class="ds-sent-label"><input type="checkbox" class="ds-sent-check" ${d.sent ? 'checked' : ''} /> Delivered</label>
        <button class="ds-fill" title="Put everything still left on this day">Fill the rest</button>
      </th>`).join('');
    const rows = lines.map((l) => {
      const quoted = Math.round(Number(l.quantity) || 0);
      const left = quoted - scheduled(l.id);
      const zh = detail.chineseNames && detail.chineseNames[l.id];
      return `<tr data-line="${esc(l.id)}">
        <td class="ds-item">${esc(l.itemDescription)}${zh ? ` <span class="zh-name">${esc(zh)}</span>` : ''}</td>
        <td class="num">${num(quoted)} ${esc(l.unit || '')}</td>
        ${data.days.map((d) => `<td class="num ds-cell ${d.sent ? 'ds-sent' : ''}"><input type="number" min="0" step="1" class="ds-qty" data-day="${esc(d.id)}"
          value="${d.quantities[l.id] ? Math.round(d.quantities[l.id]) : ''}" placeholder="—" /></td>`).join('')}
        <td class="num">${num(scheduled(l.id))}</td>
        <td class="num ${left < 0 ? 'ds-over' : left === 0 ? 'ds-done' : ''}">${left < 0 ? `${num(-left)} over` : num(left)}</td>
      </tr>`;
    }).join('');
    const foot = data.days.map((d) => {
      const pcs = lines.reduce((a, l) => a + (Number(d.quantities[l.id]) || 0), 0);
      const w = dayWeight(d);
      return `<td class="num ${d.sent ? 'ds-sent' : ''}">${num(pcs)} pcs${w ? `<div class="small-note">${kg(w)}</div>` : ''}</td>`;
    }).join('');
    const notes = data.days.map((d) => `<td class="${d.sent ? 'ds-sent' : ''}"><input type="text" class="ds-note" data-day="${esc(d.id)}" value="${esc(d.note || '')}" placeholder="Note" /></td>`).join('');
    const totalPcs = lines.reduce((a, l) => a + scheduled(l.id), 0);
    const totalLeft = lines.reduce((a, l) => a + Math.max(0, Math.round(Number(l.quantity) || 0) - scheduled(l.id)), 0);
    box.innerHTML = `<div class="ds-scroll"><table class="ds">
      <thead><tr><th>Item</th><th class="num">${isBOQ() ? 'Quantity' : 'Quoted'}</th>${head}<th class="num">Scheduled</th><th class="num">Left</th></tr></thead>
      <tbody>${rows}</tbody>
      <tfoot>
        <tr><td>Total</td><td></td>${foot}<td class="num">${num(totalPcs)}</td><td class="num">${num(totalLeft)}</td></tr>
        <tr class="ds-notes"><td>Notes</td><td></td>${notes}<td></td><td></td></tr>
      </tfoot></table></div>`;
    wire(box);
  }

  async function update(dayId, changes) {
    const r = await api().updateDeliveryDay(dayId, changes);
    if (r && r.ok === false) { alert(r.error); }
    await load();
  }

  function wire(box) {
    for (const input of box.querySelectorAll('.ds-qty')) {
      input.addEventListener('change', () => {
        const lineId = input.closest('tr').dataset.line;
        update(input.dataset.day, { quantities: { [lineId]: Math.max(0, Math.round(Number(input.value) || 0)) } });
      });
    }
    for (const th of box.querySelectorAll('th.ds-day')) {
      const dayId = th.dataset.day;
      th.querySelector('.ds-date').addEventListener('change', (e) => update(dayId, { date: e.target.value }));
      th.querySelector('.ds-sent-check').addEventListener('change', (e) => update(dayId, { sent: e.target.checked }));
      th.querySelector('.ds-fill').addEventListener('click', () => {
        const day = data.days.find((d) => d.id === dayId);
        const quantities = {};
        for (const l of materials()) {
          const left = Math.round(Number(l.quantity) || 0) - scheduled(l.id);
          if (left > 0) quantities[l.id] = (Number(day.quantities[l.id]) || 0) + left;
        }
        if (!Object.keys(quantities).length) { alert(`Everything ${isBOQ() ? 'on the BOQ' : 'quoted'} is already on a day.`); return; }
        update(dayId, { quantities });
      });
      th.querySelector('.ds-remove').addEventListener('click', async () => {
        const day = data.days.find((d) => d.id === dayId);
        if (!await appConfirm(`Remove Day ${day.day} from the delivery schedule?`)) return;
        const r = await api().deleteDeliveryDay(dayId);
        if (r && r.ok === false) alert(r.error);
        await load();
      });
    }
    for (const input of box.querySelectorAll('.ds-note')) {
      input.addEventListener('change', () => update(input.dataset.day, { note: input.value }));
    }
  }

  async function exportCSV() {
    const lines = materials();
    if (!lines.length || !data.days.length) { alert('Add a delivery day first.'); return; }
    const cell = (c) => { const t = String(c ?? ''); return /[",\n]/.test(t) ? `"${t.replace(/"/g, '""')}"` : t; };
    const dayName = (d) => `Day ${d.day}${d.date ? ` (${window.appDay ? window.appDay(d.date) : d.date})` : ''}${d.sent ? ' - delivered' : ''}`;
    const out = [['Item', 'Unit', isBOQ() ? 'Quantity' : 'Quoted', ...data.days.map(dayName), 'Scheduled', 'Left']];
    for (const l of lines) {
      const quoted = Math.round(Number(l.quantity) || 0);
      out.push([l.itemDescription, l.unit || '', quoted, ...data.days.map((d) => d.quantities[l.id] || ''), scheduled(l.id), quoted - scheduled(l.id)]);
    }
    out.push(['Notes', '', '', ...data.days.map((d) => d.note || ''), '', '']);
    const name = `${isBOQ() ? detail.boqNumber : detail.quotationNumber} Delivery Schedule.xlsx`;
    // Saved in the project's Quotations (or BOQ) folder, then opened.
    const r = await window.api.accounts.saveCSV(name, out.map((row) => row.map(cell).join(',')).join('\r\n'),
      { projectNumber: detail.projectNumber, subfolder: isBOQ() ? 'BOQ' : 'Quotations' });
    if (r && r.ok === false) alert(r.error);
  }

  // A quotation: the schedule of the BOQ it's from, copied onto it.
  async function copyFromBOQ() {
    if (!detail || !detail.sourceBOQId) return;
    const from = detail.sourceBOQNumber || 'the BOQ';
    if (data.days.length && !await appConfirm(`Replace this quotation's delivery schedule with ${from}'s?`)) return;
    const r = await window.api.quotations.copyScheduleFromBOQ(quotationId, detail.sourceBOQId);
    if (r && r.ok === false) { alert(r.error); return; }
    await load();
    if (r && r.skipped) alert(`${r.skipped} ${r.skipped === 1 ? 'item' : 'items'} on ${from}'s schedule ${r.skipped === 1 ? "isn't" : "aren't"} on this quotation, so ${r.skipped === 1 ? 'it was' : 'they were'} left out.`);
  }

  function showCopyButton() {
    const b = document.getElementById('ds-copy-boq-btn');
    if (!b) return;
    const show = !isBOQ() && detail && detail.sourceBOQId;
    b.classList.toggle('hidden', !show);
    if (show) b.textContent = `Copy from ${detail.sourceBOQNumber || 'BOQ'}`;
  }

  window.deliverySchedule = {
    setup(id, docKind) {
      quotationId = id;
      kind = docKind === 'boq' ? 'boq' : 'quotation';
      document.getElementById('ds-add-day-btn').addEventListener('click', async () => {
        const r = await api().addDeliveryDay(quotationId);
        if (r && r.ok === false) { alert(r.error); return; }
        await load();
      });
      document.getElementById('ds-csv-btn').addEventListener('click', exportCSV);
      const copy = document.getElementById('ds-copy-boq-btn');
      if (copy) copy.addEventListener('click', copyFromBOQ);
    },
    async refresh(d) {
      detail = d;
      showCopyButton();
      await load();
    },
  };
})();

'use strict';

// Marketing › Client Report: the quotations a client was sent in a period —
// this month, last month, a quarter, the year, a chosen month or any days —
// with their total and how many were accepted; exported as a PDF report.

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const pad = (n) => String(n).padStart(2, '0');
  const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
  const nice = (s) => new Date(`${s}T00:00:00`).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace('Sept', 'Sep');
  let started = false;
  let period = 'month';
  let last = null;

  function range() {
    const now = new Date();
    if (period === 'custom') return [document.getElementById('cr-from').value, document.getElementById('cr-to').value];
    if (period === 'month') {
      const m = document.getElementById('cr-month').value;
      const [y, mo] = (m || `${now.getFullYear()}-${pad(now.getMonth() + 1)}`).split('-').map(Number);
      return [ymd(new Date(y, mo - 1, 1)), ymd(new Date(y, mo, 0))];
    }
    if (period === 'last') return [ymd(new Date(now.getFullYear(), now.getMonth() - 1, 1)), ymd(new Date(now.getFullYear(), now.getMonth(), 0))];
    if (period === 'quarter') { const q = Math.floor(now.getMonth() / 3) * 3; return [ymd(new Date(now.getFullYear(), q, 1)), ymd(new Date(now.getFullYear(), q + 3, 0))]; }
    return [`${now.getFullYear()}-01-01`, `${now.getFullYear()}-12-31`];
  }

  async function load() {
    const [from, to] = range();
    if (!from || !to) return;
    const clientId = document.getElementById('cr-client').value || null;
    last = await window.api.marketing.clientReport(clientId, from, to);
    draw();
  }

  function draw() {
    const r = last;
    const cur = r.currency === 'HKD' ? 'HK$' : r.currency;
    const money = (v) => `${cur} ${(Number(v) || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
    const rate = r.rows.length ? Math.round((r.wonCount / r.rows.length) * 100) : 0;
    document.getElementById('cr-result').innerHTML = `
      <div class="cr-head">
        <div><div class="cr-eyebrow">Quotations issued to</div><h2>${esc(r.clientName)}</h2><div class="cr-when">${esc(nice(r.from))} – ${esc(nice(r.to))}</div></div>
        <div class="cr-stats">
          <div class="cr-stat"><b>${r.rows.length}</b><span>quotation${r.rows.length === 1 ? '' : 's'}</span></div>
          <div class="cr-stat"><b>${esc(money(r.total))}</b><span>quoted</span></div>
          <div class="cr-stat good"><b>${r.wonCount}</b><span>accepted · ${rate}%</span></div>
          <div class="cr-stat good"><b>${esc(money(r.wonValue))}</b><span>accepted value</span></div>
        </div>
      </div>
      ${r.rows.length ? `<table class="cr-table"><thead><tr><th>No.</th><th>Quotation</th><th>Date</th><th>Project</th><th>Subject</th><th>Type</th><th class="num">Amount</th></tr></thead><tbody>
        ${r.rows.map((x, i) => `<tr class="link-row" data-id="${esc(x.id)}" style="--i:${Math.min(i, 12)}">
          <td class="muted">${i + 1}</td><td><b>${esc(x.number)}</b>${x.won ? ' <span class="status-pill pill-success">Accepted</span>' : ''}</td>
          <td>${esc(nice(x.date))}</td><td>${esc(x.projectNumber || '')} ${esc(x.projectName || '')}</td><td class="muted">${esc(x.subject || '')}</td>
          <td>${esc(x.pricingMode || '')}</td><td class="num">${esc(money(x.value))}</td></tr>`).join('')}
        </tbody><tfoot><tr><td></td><td colspan="5"><b>Total</b></td><td class="num"><b>${esc(money(r.total))}</b></td></tr></tfoot></table>`
        : '<div class="empty-state compact"><h2>No quotations in this period</h2><p>Try another month or client.</p></div>'}`;
    document.querySelectorAll('#cr-result tr.link-row').forEach((tr) => tr.addEventListener('click', () => { window.goTo(`quotation-editor.html?id=${encodeURIComponent(tr.dataset.id)}`); }));
  }

  async function start() {
    if (started) return;
    started = true;
    const clients = await window.api.clients.list(true);
    const sel = document.getElementById('cr-client');
    sel.innerHTML = '<option value="">All clients</option>' + (clients || []).map((c) => `<option value="${esc(c.id)}">${esc(c.companyName)}</option>`).join('');
    const now = new Date();
    document.getElementById('cr-month').value = `${now.getFullYear()}-${pad(now.getMonth() + 1)}`;
    document.getElementById('cr-from').value = ymd(new Date(now.getFullYear(), now.getMonth(), 1));
    document.getElementById('cr-to').value = ymd(now);
    sel.addEventListener('change', load);
    for (const id of ['cr-month', 'cr-from', 'cr-to']) document.getElementById(id).addEventListener('change', load);
    for (const b of document.querySelectorAll('#cr-period button')) {
      b.addEventListener('click', () => {
        period = b.dataset.p;
        for (const x of document.querySelectorAll('#cr-period button')) x.classList.toggle('active', x === b);
        document.querySelector('.cr-month').classList.toggle('hidden', period !== 'month');
        document.getElementById('cr-custom').classList.toggle('hidden', period !== 'custom');
        load();
      });
    }
    document.getElementById('cr-pdf').addEventListener('click', async () => {
      const [from, to] = range();
      const clientId = document.getElementById('cr-client').value || null;
      const r = await window.docPreview.pdf(() => window.api.marketing.clientReportPDF(clientId, from, to),
        { title: `Quotations issued — ${last ? last.clientName : ''}` });
      if (r && r.ok === false) window.appAlert(r.error);
    });
    load();
  }
  document.addEventListener('marketing:tab', (e) => { if (e.detail === 'report') start(); });
  // Opened straight on this tab (marketing.html?tab=report).
  if (document.querySelector('.tab-panel[data-panel="report"].active')) start();
})();

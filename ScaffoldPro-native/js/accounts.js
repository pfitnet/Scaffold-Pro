'use strict';

// Accounts: receivables (issued invoices), payments received, expenses,
// and totals by project and by month for the chosen period. The figures
// come from main.swift (accountsData); everything is added up here.

let data = null;
let tab = 'receivables';
let editingExpense = null;
let currency = 'HK$';

function esc(value) {
  return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function money(value) {
  return Number(value || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
}

function signedMoney(value) {
  return value < 0 ? `<span class="neg">−${money(-value)}</span>` : money(value);
}

function cents(value) {
  return Math.round(value * 100) / 100;
}

function pad(n) { return String(n).padStart(2, '0'); }
function ymd(d) { return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`; }

// ---------- Period ----------

function period() {
  const choice = document.getElementById('period-select').value;
  const now = new Date();
  const y = now.getFullYear();
  const m = now.getMonth();
  switch (choice) {
    case 'this-month': return { from: ymd(new Date(y, m, 1)), to: ymd(new Date(y, m + 1, 0)) };
    case 'last-month': return { from: ymd(new Date(y, m - 1, 1)), to: ymd(new Date(y, m, 0)) };
    case 'this-year': return { from: `${y}-01-01`, to: `${y}-12-31` };
    case 'last-year': return { from: `${y - 1}-01-01`, to: `${y - 1}-12-31` };
    case 'custom': return {
      from: document.getElementById('period-from').value || '0000-01-01',
      to: document.getElementById('period-to').value || '9999-12-31',
    };
    default: return { from: '0000-01-01', to: '9999-12-31' };
  }
}

function inPeriod(day, p) {
  return !!day && day >= p.from && day <= p.to;
}

function periodLabel(p) {
  if (p.from === '0000-01-01' && p.to === '9999-12-31') return 'All dates';
  const f = (d) => new Date(`${d}T00:00:00`).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' });
  return `${p.from === '0000-01-01' ? 'Start' : f(p.from)} – ${p.to === '9999-12-31' ? 'today' : f(p.to)}`;
}

// ---------- Figures ----------

function figures() {
  const p = period();
  const invoices = data.invoices.filter((i) => inPeriod(i.invoiceDate, p));
  const payments = data.payments.filter((x) => inPeriod(x.date, p));
  const expenses = data.expenses.filter((e) => inPeriod(e.date, p));
  const sum = (list, f) => cents(list.reduce((a, x) => a + f(x), 0));
  return {
    p, invoices, payments, expenses,
    invoiced: sum(invoices, (i) => i.total),
    received: sum(payments, (x) => x.amount),
    spent: sum(expenses, (e) => e.amount),
    // Outstanding and overdue are as of today, whatever the period.
    outstanding: sum(data.invoices, (i) => i.balanceDue),
    overdue: data.invoices.filter((i) => i.status === 'Overdue'),
  };
}

function renderStats(f) {
  const overdueTotal = cents(f.overdue.reduce((a, i) => a + i.balanceDue, 0));
  const net = cents(f.received - f.spent);
  const cards = [
    [`${currency} ${money(f.invoiced)}`, `Invoiced (${f.invoices.length})`, ''],
    [`${currency} ${money(f.received)}`, 'Received', ''],
    [`${currency} ${money(f.spent)}`, `Expenses (${f.expenses.length})`, ''],
    [`${net < 0 ? '−' : ''}${currency} ${money(Math.abs(net))}`, 'Net cash (received − expenses)', net < 0 ? 'tone-danger' : 'tone-good'],
    [`${currency} ${money(f.outstanding)}`, 'Outstanding today', ''],
    [`${currency} ${money(overdueTotal)}`, `Overdue today (${f.overdue.length})`, f.overdue.length ? 'tone-danger' : ''],
  ];
  document.getElementById('account-stats').innerHTML = cards.map(([v, l, tone]) =>
    `<div class="stat-card ${tone}"><div class="value">${v}</div><div class="label">${l}</div></div>`).join('');
  document.getElementById('period-label').textContent = periodLabel(f.p);
}

function matches(text) {
  const q = document.getElementById('search-box').value.trim().toLowerCase();
  return !q || text.toLowerCase().includes(q);
}

const PILL = { Paid: 'pill-success', PartiallyPaid: 'pill-warning', Overdue: 'pill-danger', Issued: '' };
const STATUS_TEXT = { PartiallyPaid: 'Part paid' };

// Each tab: { head, rows: [[cells…]], foot, csv: [[…]] }
function tableFor(f) {
  if (tab === 'receivables') {
    const unpaidOnly = document.getElementById('unpaid-only').checked;
    const list = (unpaidOnly ? data.invoices.filter((i) => i.balanceDue > 0.004) : f.invoices)
      .filter((i) => matches(`${i.invoiceNumber} ${i.projectNumber} ${i.projectName} ${i.clientName || ''} ${i.status}`));
    return {
      note: unpaidOnly ? 'Every invoice with a balance due, whatever its date.' : `Invoices dated ${periodLabel(f.p)}.`,
      head: ['Invoice', 'Date', 'Due', 'Project', 'Client', 'Total', 'Paid', 'Balance', 'Status'],
      numeric: [5, 6, 7],
      rows: list.map((i) => ({
        href: `invoice-editor.html?id=${encodeURIComponent(i.id)}`,
        cells: [esc(i.invoiceNumber), i.invoiceDate, i.dueDate || '—', `${esc(i.projectNumber)} ${esc(i.projectName)}`, esc(i.clientName || '—'),
          money(i.total), money(i.amountPaid), money(i.balanceDue),
          `<span class="status-pill ${PILL[i.status] || ''}">${STATUS_TEXT[i.status] || i.status}</span>`],
        csv: [i.invoiceNumber, i.invoiceDate, i.dueDate || '', i.projectNumber, i.projectName, i.clientName || '', i.total, i.amountPaid, i.balanceDue, i.status],
      })),
      foot: ['Total', '', '', '', '', money(list.reduce((a, i) => a + i.total, 0)), money(list.reduce((a, i) => a + i.amountPaid, 0)),
        money(list.reduce((a, i) => a + i.balanceDue, 0)), ''],
    };
  }
  if (tab === 'payments') {
    const list = f.payments.filter((x) => matches(`${x.invoiceNumber} ${x.method || ''} ${x.reference || ''}`));
    const project = (id) => data.projects.find((p) => p.id === id);
    return {
      note: `Payments received ${periodLabel(f.p)}.`,
      head: ['Date', 'Invoice', 'Project', 'Method', 'Reference', 'Amount'],
      numeric: [5],
      rows: list.map((x) => ({
        href: `invoice-editor.html?id=${encodeURIComponent(x.invoiceId)}`,
        cells: [x.undated ? `<span title="Recorded before payments were dated">${x.date}*</span>` : x.date, esc(x.invoiceNumber),
          esc(project(x.projectId)?.projectNumber || ''), esc(x.method || '—'), esc(x.reference || ''), money(x.amount)],
        csv: [x.date, x.invoiceNumber, project(x.projectId)?.projectNumber || '', x.method || '', x.reference || '', x.amount],
      })),
      foot: ['Total', '', '', '', '', money(list.reduce((a, x) => a + x.amount, 0))],
    };
  }
  if (tab === 'expenses') {
    const list = f.expenses.filter((e) => matches(`${e.category} ${e.supplier || ''} ${e.description} ${e.reference || ''}`));
    const project = (id) => data.projects.find((p) => p.id === id);
    return {
      note: `Expenses ${periodLabel(f.p)}. Click one to change it.`,
      head: ['Date', 'Category', 'Supplier', 'Description', 'Project', 'Reference', 'Amount'],
      numeric: [6],
      rows: list.map((e) => ({
        expense: e.id,
        cells: [e.date, esc(e.category), esc(e.supplier || ''), esc(e.description), esc(project(e.projectId)?.projectNumber || '—'), esc(e.reference || ''), money(e.amount)],
        csv: [e.date, e.category, e.supplier || '', e.description, project(e.projectId)?.projectNumber || '', e.reference || '', e.amount],
      })),
      foot: ['Total', '', '', '', '', '', money(list.reduce((a, e) => a + e.amount, 0))],
    };
  }
  if (tab === 'projects') {
    const rows = data.projects.map((p) => {
      const invoiced = f.invoices.filter((i) => i.projectId === p.id).reduce((a, i) => a + i.total, 0);
      const received = f.payments.filter((x) => x.projectId === p.id).reduce((a, x) => a + x.amount, 0);
      const spent = f.expenses.filter((e) => e.projectId === p.id).reduce((a, e) => a + e.amount, 0);
      const outstanding = data.invoices.filter((i) => i.projectId === p.id).reduce((a, i) => a + i.balanceDue, 0);
      return { p, invoiced, received, spent, outstanding, net: cents(invoiced - spent) };
    }).filter((r) => (r.invoiced || r.received || r.spent || r.outstanding) && matches(`${r.p.projectNumber} ${r.p.name}`));
    const general = f.expenses.filter((e) => !e.projectId).reduce((a, e) => a + e.amount, 0);
    const out = rows.map((r) => ({
      href: `project-detail.html?number=${encodeURIComponent(r.p.projectNumber)}`,
      cells: [`${esc(r.p.projectNumber)} ${esc(r.p.name)}`, money(r.invoiced), money(r.received), money(r.spent), signedMoney(r.net), money(r.outstanding)],
      csv: [r.p.projectNumber, r.p.name, cents(r.invoiced), cents(r.received), cents(r.spent), r.net, cents(r.outstanding)],
    }));
    if (general) {
      out.push({ cells: ['<i>General (no project)</i>', '', '', money(general), signedMoney(-general), ''], csv: ['', 'General (no project)', 0, 0, cents(general), -cents(general), 0] });
    }
    const total = (k) => rows.reduce((a, r) => a + r[k], 0);
    return {
      note: `Invoiced, received and spent ${periodLabel(f.p)}; outstanding as of today. Net = invoiced − expenses.`,
      head: ['Project', 'Invoiced', 'Received', 'Expenses', 'Net', 'Outstanding'],
      csvHead: ['Project No.', 'Project', 'Invoiced', 'Received', 'Expenses', 'Net', 'Outstanding'],
      numeric: [1, 2, 3, 4, 5],
      rows: out,
      foot: ['Total', money(total('invoiced')), money(total('received')), money(total('spent') + general),
        signedMoney(cents(total('invoiced') - total('spent') - general)), money(total('outstanding'))],
    };
  }
  // By month
  const months = new Map();
  const add = (day, key, amount) => {
    const m = day.slice(0, 7);
    if (!months.has(m)) months.set(m, { invoiced: 0, received: 0, spent: 0 });
    months.get(m)[key] += amount;
  };
  for (const i of f.invoices) add(i.invoiceDate, 'invoiced', i.total);
  for (const x of f.payments) add(x.date, 'received', x.amount);
  for (const e of f.expenses) add(e.date, 'spent', e.amount);
  const keys = [...months.keys()].sort().reverse();
  const label = (m) => new Date(`${m}-01T00:00:00`).toLocaleDateString('en-GB', { month: 'long', year: 'numeric' });
  const sum = (k) => keys.reduce((a, m) => a + months.get(m)[k], 0);
  return {
    note: `By month, ${periodLabel(f.p)}. Net cash = received − expenses.`,
    head: ['Month', 'Invoiced', 'Received', 'Expenses', 'Net Cash'],
    numeric: [1, 2, 3, 4],
    rows: keys.map((m) => {
      const v = months.get(m);
      return { cells: [label(m), money(v.invoiced), money(v.received), money(v.spent), signedMoney(cents(v.received - v.spent))],
        csv: [m, cents(v.invoiced), cents(v.received), cents(v.spent), cents(v.received - v.spent)] };
    }),
    foot: ['Total', money(sum('invoiced')), money(sum('received')), money(sum('spent')), signedMoney(cents(sum('received') - sum('spent')))],
  };
}

function render() {
  const f = figures();
  renderStats(f);
  document.getElementById('unpaid-only-label').classList.toggle('hidden', tab !== 'receivables');
  document.getElementById('add-expense-btn').classList.toggle('hidden', tab !== 'expenses');
  const t = tableFor(f);
  const content = document.getElementById('tab-content');
  if (!t.rows.length) {
    content.innerHTML = `<p class="small-note">${t.note}</p><div class="empty-state"><h2>Nothing here for this period</h2>
      ${tab === 'expenses' ? '<p>Use “+ Add Expense” to record money spent.</p>' : ''}</div>`;
    return;
  }
  const cls = (i) => (t.numeric.includes(i) ? ' class="num"' : '');
  content.innerHTML = `<p class="small-note">${t.note}</p>
    <table class="money">
      <thead><tr>${t.head.map((h, i) => `<th${cls(i)}>${h}</th>`).join('')}</tr></thead>
      <tbody>${t.rows.map((r) => `<tr class="${r.href || r.expense ? 'clickable' : ''}" ${r.href ? `data-href="${esc(r.href)}"` : ''} ${r.expense ? `data-expense="${esc(r.expense)}"` : ''}>
        ${r.cells.map((c, i) => `<td${cls(i)}>${c}</td>`).join('')}</tr>`).join('')}</tbody>
      <tfoot><tr>${t.foot.map((c, i) => `<td${cls(i)}>${c}</td>`).join('')}</tr></tfoot>
    </table>`;
  for (const tr of content.querySelectorAll('tr[data-href]')) tr.addEventListener('click', () => { location.href = tr.dataset.href; });
  for (const tr of content.querySelectorAll('tr[data-expense]')) {
    tr.addEventListener('click', () => openExpense(data.expenses.find((e) => e.id === tr.dataset.expense)));
  }
}

// ---------- Expenses ----------

function openExpense(expense) {
  editingExpense = expense || null;
  const e = expense || {};
  document.getElementById('ex-title').textContent = expense ? 'Change Expense' : 'Add Expense';
  document.getElementById('ex-date').value = e.date || ymd(new Date());
  document.getElementById('ex-amount').value = e.amount ?? '';
  document.getElementById('ex-category').innerHTML = data.categories.map((c) => `<option>${esc(c)}</option>`).join('');
  document.getElementById('ex-category').value = e.category || data.categories[0];
  document.getElementById('ex-supplier').value = e.supplier || '';
  document.getElementById('ex-description').value = e.description || '';
  document.getElementById('ex-project').innerHTML = '<option value="">— None (general) —</option>' +
    data.projects.map((p) => `<option value="${esc(p.id)}">${esc(p.projectNumber)} — ${esc(p.name)}</option>`).join('');
  document.getElementById('ex-project').value = e.projectId || '';
  document.getElementById('ex-reference').value = e.reference || '';
  document.getElementById('ex-delete').classList.toggle('hidden', !expense);
  document.getElementById('ex-error').classList.add('hidden');
  document.getElementById('expense-modal').classList.remove('hidden');
  document.getElementById(expense ? 'ex-amount' : 'ex-date').focus();
}

function closeExpense() {
  document.getElementById('expense-modal').classList.add('hidden');
}

async function saveExpense() {
  const r = await window.api.accounts.saveExpense({
    id: editingExpense ? editingExpense.id : null,
    date: document.getElementById('ex-date').value,
    amount: Number(document.getElementById('ex-amount').value) || 0,
    category: document.getElementById('ex-category').value,
    supplier: document.getElementById('ex-supplier').value,
    description: document.getElementById('ex-description').value,
    projectId: document.getElementById('ex-project').value || null,
    reference: document.getElementById('ex-reference').value,
  });
  if (!r.ok) {
    const err = document.getElementById('ex-error');
    err.textContent = r.error;
    err.classList.remove('hidden');
    return;
  }
  closeExpense();
  await load();
}

async function deleteExpense() {
  if (!editingExpense || !confirm('Delete this expense?')) return;
  const r = await window.api.accounts.deleteExpense(editingExpense.id);
  if (!r.ok) { alert(r.error); return; }
  closeExpense();
  await load();
}

// ---------- CSV ----------

function csvLine(cells) {
  return cells.map((c) => {
    const s = String(c ?? '');
    return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
  }).join(',');
}

async function exportCSV() {
  const f = figures();
  const t = tableFor(f);
  const names = { receivables: 'Receivables', payments: 'Payments Received', expenses: 'Expenses', projects: 'By Project', monthly: 'By Month' };
  const head = t.csvHead || (tab === 'receivables'
    ? ['Invoice', 'Date', 'Due', 'Project No.', 'Project', 'Client', 'Total', 'Paid', 'Balance', 'Status'] : t.head);
  const lines = [csvLine(head)].concat(t.rows.map((r) => csvLine(r.csv)));
  const r = await window.api.accounts.saveCSV(`${names[tab]} ${f.p.from === '0000-01-01' ? 'all' : f.p.from} to ${f.p.to === '9999-12-31' ? ymd(new Date()) : f.p.to}.csv`, lines.join('\r\n'));
  if (!r.ok) alert(r.error);
}

// ---------- Page ----------

async function load() {
  data = await window.api.accounts.data();
  currency = data.currency === 'HKD' ? 'HK$' : data.currency;
  render();
}

async function init() {
  await load();
  document.getElementById('period-select').addEventListener('change', (e) => {
    const custom = e.target.value === 'custom';
    document.getElementById('period-from').classList.toggle('hidden', !custom);
    document.getElementById('period-to').classList.toggle('hidden', !custom);
    render();
  });
  for (const id of ['period-from', 'period-to', 'unpaid-only']) document.getElementById(id).addEventListener('change', render);
  document.getElementById('search-box').addEventListener('input', render);
  for (const b of document.querySelectorAll('#account-tabs button')) {
    b.addEventListener('click', () => {
      tab = b.dataset.tab;
      for (const x of document.querySelectorAll('#account-tabs button')) x.classList.toggle('active', x === b);
      render();
    });
  }
  document.getElementById('add-expense-btn').addEventListener('click', () => openExpense(null));
  document.getElementById('export-btn').addEventListener('click', exportCSV);
  document.getElementById('ex-cancel').addEventListener('click', closeExpense);
  document.getElementById('ex-save').addEventListener('click', saveExpense);
  document.getElementById('ex-delete').addEventListener('click', deleteExpense);
  document.getElementById('expense-modal').addEventListener('keydown', (e) => {
    if (e.key === 'Escape') closeExpense();
    if (e.key === 'Enter') saveExpense();
  });
}

init();

'use strict';

// Admin › Employees: the people on the payroll, full-time or part-time,
// paid monthly, daily or hourly, with allowances and the employer's MPF.
// "Record Pay…" puts a month's pay into Accounts › Expenses.
//
// Employer MPF is worked out as 5% of the month's pay (salary + allowances),
// up to HK$1,500 (relevant income capped at HK$30,000).

(function () {
  const MPF_RATE = 0.05;
  const MPF_CAP = 1500;

  let employees = [];
  let workerList = [];
  let editing = null;
  let currency = 'HK$';

  function esc(value) {
    return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function money(value) {
    return Number(value || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  const cents = (v) => Math.round((Number(v) || 0) * 100) / 100;
  const pad = (n) => String(n).padStart(2, '0');
  const ymd = (d) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;

  const UNIT = { Daily: 'day', Hourly: 'hour' };

  /** A month's pay for `units` days / hours (or the salary), without allowances. */
  function basePay(e, units) {
    if (e.payBasis === 'Monthly') return cents(e.payRate);
    return cents(e.payRate * (units ?? e.usualUnitsPerMonth ?? 0));
  }

  function mpfFor(e, pay) {
    return e.mpfEnabled ? cents(Math.min(pay * MPF_RATE, MPF_CAP)) : 0;
  }

  /** The usual month: pay (with allowances), employer MPF, and the two together. */
  function monthly(e) {
    const pay = cents(basePay(e) + (e.monthlyAllowance || 0));
    const mpf = mpfFor(e, pay);
    return { pay, mpf, cost: cents(pay + mpf) };
  }

  function payText(e) {
    if (e.payBasis === 'Monthly') return `${currency} ${money(e.payRate)} / month`;
    const unit = UNIT[e.payBasis];
    const usual = e.usualUnitsPerMonth ? ` × ${e.usualUnitsPerMonth} ${unit}s` : '';
    return `${currency} ${money(e.payRate)} / ${unit}${usual}`;
  }

  function isCurrent(e) {
    return !e.isArchived;
  }

  // ---------- List ----------

  function visible() {
    const showFormer = document.getElementById('show-former-employees').checked;
    const q = document.getElementById('employee-search').value.trim().toLowerCase();
    return employees.filter((e) => (showFormer || isCurrent(e)) &&
      (!q || `${e.employeeNumber} ${e.name} ${e.chineseName || ''} ${e.position || ''} ${e.employmentType} ${e.phone || ''}`.toLowerCase().includes(q)));
  }

  function renderStats() {
    const current = employees.filter(isCurrent);
    const full = current.filter((e) => e.employmentType === 'Full-time').length;
    const sum = (k) => cents(current.reduce((a, e) => a + monthly(e)[k], 0));
    const cards = [
      [String(current.length), `Employees (${full} full-time, ${current.length - full} part-time)`],
      [`${currency} ${money(sum('pay'))}`, 'Monthly pay (usual month)'],
      [`${currency} ${money(sum('mpf'))}`, 'Employer MPF a month'],
      [`${currency} ${money(sum('cost'))}`, 'Monthly payroll cost'],
    ];
    document.getElementById('employee-stats').innerHTML = cards.map(([v, l]) =>
      `<div class="stat-card"><div class="value">${v}</div><div class="label">${l}</div></div>`).join('');
  }

  function render() {
    renderStats();
    const list = visible();
    const container = document.getElementById('employee-list');
    if (list.length === 0) {
      container.innerHTML = employees.length === 0
        ? '<div class="empty-state"><h2>No employees yet</h2><p>Add the people on the payroll, with their pay and whether they’re full-time or part-time.</p></div>'
        : '<div class="empty-state"><h2>No employees match</h2></div>';
      return;
    }
    const totals = { pay: 0, mpf: 0, cost: 0 };
    const rows = list.map((e) => {
      const m = monthly(e);
      if (isCurrent(e)) { totals.pay += m.pay; totals.mpf += m.mpf; totals.cost += m.cost; }
      const pill = e.employmentType === 'Full-time' ? 'pill-success' : 'pill-warning';
      return `<tr class="clickable" data-employee="${esc(e.id)}">
        <td>${esc(e.employeeNumber)}</td>
        <td>${esc(e.name)}${e.chineseName ? ` <span class="small-note">${esc(e.chineseName)}</span>` : ''}${e.isArchived ? ' <span class="status-pill">Former</span>' : ''}</td>
        <td>${esc(e.position || '—')}</td>
        <td><span class="status-pill type-pill ${pill}">${esc(e.employmentType)}</span></td>
        <td>${payText(e)}</td>
        <td class="num">${e.monthlyAllowance ? money(e.monthlyAllowance) : '—'}</td>
        <td class="num">${money(m.pay)}</td>
        <td class="num">${e.mpfEnabled ? money(m.mpf) : '—'}</td>
        <td class="num">${money(m.cost)}</td>
        <td>${esc(e.startDate || '—')}</td>
      </tr>`;
    }).join('');
    container.innerHTML = `<table class="money">
      <thead><tr><th>No.</th><th>Name</th><th>Position</th><th>Employment</th><th>Pay</th><th class="num">Allowances</th>
        <th class="num">Monthly Pay</th><th class="num">Employer MPF</th><th class="num">Monthly Cost</th><th>Started</th></tr></thead>
      <tbody>${rows}</tbody>
      <tfoot><tr><td>Total</td><td colspan="5" class="small-note">Current employees, a usual month</td>
        <td class="num">${money(totals.pay)}</td><td class="num">${money(totals.mpf)}</td><td class="num">${money(totals.cost)}</td><td></td></tr></tfoot>
    </table>`;
    for (const tr of container.querySelectorAll('tr[data-employee]')) {
      tr.addEventListener('click', () => openEmployee(employees.find((e) => e.id === tr.dataset.employee)));
    }
  }

  async function load() {
    employees = (await window.api.employees.list()) || [];
    render();
  }

  // ---------- Add / change ----------

  function formValues() {
    const num = (id) => (document.getElementById(id).value === '' ? null : Number(document.getElementById(id).value));
    return {
      id: editing ? editing.id : null,
      name: document.getElementById('em-name').value,
      chineseName: document.getElementById('em-chineseName').value,
      position: document.getElementById('em-position').value,
      phone: document.getElementById('em-phone').value,
      workerId: document.getElementById('em-worker').value || null,
      employmentType: document.getElementById('em-type').value,
      payBasis: document.getElementById('em-basis').value,
      payRate: num('em-rate') || 0,
      usualUnitsPerMonth: num('em-units'),
      monthlyAllowance: num('em-allowance'),
      mpfEnabled: document.getElementById('em-mpf').checked,
      annualLeaveDays: num('em-leave'),
      bankAccount: document.getElementById('em-bank').value,
      startDate: document.getElementById('em-start').value,
      endDate: document.getElementById('em-end').value,
      notes: document.getElementById('em-notes').value,
      isArchived: document.getElementById('em-archived').checked,
    };
  }

  function updateForm() {
    const basis = document.getElementById('em-basis').value;
    document.getElementById('em-rate-label').textContent = basis === 'Monthly' ? 'Monthly salary' : basis === 'Daily' ? 'Daily rate' : 'Hourly rate';
    document.getElementById('em-units-field').classList.toggle('hidden', basis === 'Monthly');
    document.getElementById('em-units-label').textContent = basis === 'Daily' ? 'Usual days a month' : 'Usual hours a month';
    const v = formValues();
    const m = monthly(v);
    const units = basis !== 'Monthly' && !v.usualUnitsPerMonth ? ` (enter the usual ${UNIT[basis]}s a month to estimate it)` : '';
    document.getElementById('em-estimate').textContent =
      `A usual month: pay ${currency} ${money(m.pay)}${v.mpfEnabled ? ` + employer MPF ${currency} ${money(m.mpf)}` : ''} = ${currency} ${money(m.cost)}${units}`;
  }

  function openEmployee(e) {
    editing = e || null;
    const v = e || { employmentType: 'Full-time', payBasis: 'Monthly', mpfEnabled: true };
    document.getElementById('em-title').textContent = e ? `${e.employeeNumber} — ${e.name}` : 'New Employee';
    document.getElementById('em-name').value = v.name || '';
    document.getElementById('em-chineseName').value = v.chineseName || '';
    document.getElementById('em-position').value = v.position || '';
    document.getElementById('em-phone').value = v.phone || '';
    const workerSelect = document.getElementById('em-worker');
    workerSelect.innerHTML = '<option value="">— None —</option>' +
      workerList.map((w) => `<option value="${esc(w.id)}">${esc(w.workerNumber)} — ${esc(w.name)}${w.isArchived ? ' (archived)' : ''}</option>`).join('');
    workerSelect.value = v.workerId || '';
    document.getElementById('em-type').value = v.employmentType;
    document.getElementById('em-basis').value = v.payBasis;
    document.getElementById('em-rate').value = e ? v.payRate : '';
    document.getElementById('em-units').value = v.usualUnitsPerMonth ?? '';
    document.getElementById('em-allowance').value = v.monthlyAllowance ?? '';
    document.getElementById('em-leave').value = v.annualLeaveDays ?? '';
    document.getElementById('em-bank').value = v.bankAccount || '';
    document.getElementById('em-start').value = v.startDate || '';
    document.getElementById('em-end').value = v.endDate || '';
    document.getElementById('em-mpf').checked = v.mpfEnabled !== false;
    document.getElementById('em-notes').value = v.notes || '';
    document.getElementById('em-archived').checked = !!v.isArchived;
    document.getElementById('em-archived-field').classList.toggle('hidden', !e);
    document.getElementById('em-delete').classList.toggle('hidden', !e);
    document.getElementById('em-error').classList.add('hidden');
    updateForm();
    document.getElementById('employee-modal').classList.remove('hidden');
    document.getElementById('em-name').focus();
  }

  function closeEmployee() {
    document.getElementById('employee-modal').classList.add('hidden');
    editing = null;
  }

  // Choosing a worker fills in what's still empty from their record.
  function fillFromWorker() {
    const w = workerList.find((x) => x.id === document.getElementById('em-worker').value);
    if (!w) return;
    for (const [id, value] of [['em-name', w.name], ['em-position', w.position], ['em-phone', w.phone], ['em-start', w.startDate]]) {
      const input = document.getElementById(id);
      if (!input.value && value) input.value = String(value).slice(0, id === 'em-start' ? 10 : undefined);
    }
  }

  async function saveEmployee() {
    const values = formValues();
    // Leaving date filled in for a current employee: offer to move them off the payroll.
    if (editing && !editing.isArchived && !values.isArchived && values.endDate && values.endDate <= ymd(new Date()) &&
        confirm(`${values.name} left on ${values.endDate}. Take them off the payroll (keep them as a former employee)?`)) {
      values.isArchived = true;
    }
    const r = await window.api.employees.save(values);
    if (!r.ok) {
      const err = document.getElementById('em-error');
      err.textContent = r.error;
      err.classList.remove('hidden');
      return;
    }
    closeEmployee();
    await load();
  }

  async function deleteEmployee() {
    if (!editing) return;
    if (!confirm(`Delete ${editing.name} completely?\n\nTo keep their record, tick “Former employee” instead. Pay already recorded in Expenses stays there.`)) return;
    const r = await window.api.employees.remove(editing.id);
    if (!r.ok) { alert(r.error); return; }
    closeEmployee();
    await load();
  }

  // ---------- Record Pay ----------

  function payrollRow(e) {
    const hourlyOrDaily = e.payBasis !== 'Monthly';
    return `<tr data-employee="${esc(e.id)}">
      <td><input type="checkbox" class="include" checked /></td>
      <td>${esc(e.name)}<span class="small-note who">${esc(e.employeeNumber)} · ${esc(e.employmentType)}</span></td>
      <td>${payText(e)}</td>
      <td>${hourlyOrDaily ? `<input type="number" class="units" min="0" step="0.5" value="${e.usualUnitsPerMonth ?? ''}" title="${UNIT[e.payBasis]}s worked" /> ${UNIT[e.payBasis]}s` : '—'}</td>
      <td class="num"><input type="number" class="pay" min="0" step="0.01" /></td>
      <td class="num"><input type="number" class="mpf" min="0" step="0.01" /></td>
      <td class="num total"></td>
    </tr>`;
  }

  function recalcRow(tr, fromUnits) {
    const e = employees.find((x) => x.id === tr.dataset.employee);
    const units = tr.querySelector('.units');
    if (fromUnits) {
      const pay = cents(basePay(e, units ? Number(units.value) || 0 : undefined) + (e.monthlyAllowance || 0));
      tr.querySelector('.pay').value = pay.toFixed(2);
      tr.querySelector('.mpf').value = mpfFor(e, pay).toFixed(2);
    }
    const total = cents((Number(tr.querySelector('.pay').value) || 0) + (Number(tr.querySelector('.mpf').value) || 0));
    tr.querySelector('.total').textContent = money(total);
    tr.classList.toggle('muted', !tr.querySelector('.include').checked);
    recalcFooter();
  }

  function recalcFooter() {
    const table = document.getElementById('payroll-table');
    let pay = 0; let mpf = 0;
    for (const tr of table.querySelectorAll('tbody tr')) {
      if (!tr.querySelector('.include').checked) continue;
      pay += Number(tr.querySelector('.pay').value) || 0;
      mpf += Number(tr.querySelector('.mpf').value) || 0;
    }
    const foot = table.querySelector('tfoot');
    if (foot) foot.innerHTML = `<tr><td></td><td>Total</td><td></td><td></td><td class="num">${money(pay)}</td><td class="num">${money(mpf)}</td><td class="num">${money(pay + mpf)}</td></tr>`;
  }

  function openPayroll() {
    const current = employees.filter(isCurrent);
    if (current.length === 0) { alert('Add employees first.'); return; }
    const now = new Date();
    document.getElementById('pr-month').value = `${now.getFullYear()}-${pad(now.getMonth() + 1)}`;
    document.getElementById('pr-date').value = ymd(now);
    const table = document.getElementById('payroll-table');
    table.innerHTML = `<thead><tr><th></th><th>Employee</th><th>Rate</th><th>Worked</th><th class="num">Pay (incl. allowances)</th><th class="num">Employer MPF</th><th class="num">Total</th></tr></thead>
      <tbody>${current.map(payrollRow).join('')}</tbody><tfoot></tfoot>`;
    for (const tr of table.querySelectorAll('tbody tr')) {
      recalcRow(tr, true);
      const units = tr.querySelector('.units');
      if (units) units.addEventListener('input', () => recalcRow(tr, true));
      for (const sel of ['.pay', '.mpf', '.include']) tr.querySelector(sel).addEventListener('input', () => recalcRow(tr, false));
      tr.querySelector('.include').addEventListener('change', () => recalcRow(tr, false));
    }
    document.getElementById('pr-error').classList.add('hidden');
    document.getElementById('payroll-modal').classList.remove('hidden');
  }

  function closePayroll() {
    document.getElementById('payroll-modal').classList.add('hidden');
  }

  async function savePayroll() {
    const lines = [...document.querySelectorAll('#payroll-table tbody tr')]
      .filter((tr) => tr.querySelector('.include').checked)
      .map((tr) => ({ employeeId: tr.dataset.employee, pay: Number(tr.querySelector('.pay').value) || 0, mpf: Number(tr.querySelector('.mpf').value) || 0 }));
    const r = await window.api.employees.recordPayroll({
      month: document.getElementById('pr-month').value,
      date: document.getElementById('pr-date').value,
      lines,
    });
    if (!r.ok) {
      const err = document.getElementById('pr-error');
      err.textContent = r.error;
      err.classList.remove('hidden');
      return;
    }
    closePayroll();
    const skipped = r.skipped && r.skipped.length ? `\n\nAlready recorded for this month (skipped): ${r.skipped.join(', ')}.` : '';
    alert(`${r.recorded} ${r.recorded === 1 ? 'expense' : 'expenses'} added to Accounts › Expenses under “Salaries & MPF”.${skipped}`);
  }

  // ---------- CSV ----------

  async function exportCSV() {
    const line = (cells) => cells.map((c) => {
      const s = String(c ?? '');
      return /[",\n]/.test(s) ? `"${s.replace(/"/g, '""')}"` : s;
    }).join(',');
    const rows = [['No.', 'Name', 'Chinese Name', 'Position', 'Phone', 'Employment', 'Paid', 'Rate', 'Usual Days/Hours a Month',
      'Allowances', 'Monthly Pay', 'Employer MPF', 'Monthly Cost', 'Annual Leave Days', 'Bank Account', 'Started', 'Left', 'Former']]
      .concat(visible().map((e) => {
        const m = monthly(e);
        return [e.employeeNumber, e.name, e.chineseName || '', e.position || '', e.phone || '', e.employmentType, e.payBasis, e.payRate,
          e.usualUnitsPerMonth || '', e.monthlyAllowance || '', m.pay, m.mpf, m.cost, e.annualLeaveDays || '', e.bankAccount || '',
          e.startDate || '', e.endDate || '', e.isArchived ? 'Yes' : ''];
      }));
    const r = await window.api.accounts.saveCSV(`Employees ${ymd(new Date())}.csv`, rows.map(line).join('\r\n'));
    if (r && !r.ok) alert(r.error);
  }

  // ---------- Page ----------

  function showTab(name) {
    for (const b of document.querySelectorAll('#admin-tabs button')) b.classList.toggle('active', b.dataset.tab === name);
    document.getElementById('admin-tab-workers').classList.toggle('hidden', name !== 'workers');
    document.getElementById('admin-tab-employees').classList.toggle('hidden', name !== 'employees');
    try { sessionStorage.setItem('admin.tab', name); } catch (e) { /* not kept */ }
    if (name === 'employees') refreshWorkerChoices();
  }

  async function refreshWorkerChoices() {
    workerList = (await window.api.workers.list(true)) || [];
  }

  async function init() {
    try {
      const settings = await window.api.settings.get();
      if (settings && settings.currency) currency = settings.currency === 'HKD' ? 'HK$' : settings.currency;
    } catch (e) { /* keep HK$ */ }
    for (const b of document.querySelectorAll('#admin-tabs button')) b.addEventListener('click', () => showTab(b.dataset.tab));
    document.getElementById('employee-search').addEventListener('input', render);
    document.getElementById('show-former-employees').addEventListener('change', render);
    document.getElementById('new-employee-btn').addEventListener('click', () => openEmployee(null));
    document.getElementById('record-pay-btn').addEventListener('click', openPayroll);
    document.getElementById('export-employees-btn').addEventListener('click', exportCSV);
    document.getElementById('em-cancel').addEventListener('click', closeEmployee);
    document.getElementById('em-save').addEventListener('click', saveEmployee);
    document.getElementById('em-delete').addEventListener('click', deleteEmployee);
    document.getElementById('em-worker').addEventListener('change', fillFromWorker);
    for (const el of document.querySelectorAll('#employee-modal input, #employee-modal select')) {
      el.addEventListener('input', updateForm);
      el.addEventListener('change', updateForm);
    }
    document.getElementById('employee-modal').addEventListener('keydown', (e) => {
      if (e.key === 'Escape') closeEmployee();
      if (e.key === 'Enter' && e.target.tagName === 'INPUT' && e.target.type !== 'checkbox') saveEmployee();
    });
    document.getElementById('pr-cancel').addEventListener('click', closePayroll);
    document.getElementById('pr-save').addEventListener('click', savePayroll);
    document.getElementById('payroll-modal').addEventListener('keydown', (e) => { if (e.key === 'Escape') closePayroll(); });

    // admin.html?tab=employees opens the Employees tab; otherwise the last one used.
    let tab = new URLSearchParams(location.search).get('tab');
    if (!tab && !new URLSearchParams(location.search).get('worker')) {
      try { tab = sessionStorage.getItem('admin.tab'); } catch (e) { tab = null; }
    }
    showTab(tab === 'employees' ? 'employees' : 'workers');
    await refreshWorkerChoices();
    await load();
  }

  init();
})();

'use strict';

// Per-line discount for quotations and invoices: no discount (the
// default), a percentage, or an amount off the line total.
//
//   window.openLineDiscount(line, currencyLabel, save)
//     save(discountType, discountValue) → Promise<{ ok, error }>
//   window.lineDiscountLabel(line, currencyLabel) → "", "−10%", "−HK$ 20.00"
//   window.lineNetTotal(line) → the line total after its discount

(function () {
  let sheet = null;
  let saveHandler = null;

  function money(value) {
    return Number(value || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  }

  function cents(value) {
    return Math.round(value * 100) / 100;
  }

  window.lineNetTotal = function lineNetTotal(line) {
    const gross = cents(Math.round(line.quantity) * line.appliedUnitPrice);
    const value = Math.max(0, Number(line.discountValue) || 0);
    let discount = 0;
    if (line.discountType === 'Percent') discount = cents(gross * Math.min(value, 100) / 100);
    else if (line.discountType === 'Amount') discount = cents(value);
    return cents(gross - Math.min(discount, Math.max(gross, 0)));
  };

  window.lineDiscountLabel = function lineDiscountLabel(line, currencyLabel) {
    const value = Number(line.discountValue) || 0;
    if (line.discountType === 'Percent' && value > 0) return `−${value}%`;
    if (line.discountType === 'Amount' && value > 0) return `−${currencyLabel} ${money(value)}`;
    return '';
  };

  function build() {
    sheet = document.createElement('div');
    sheet.className = 'modal-backdrop hidden';
    sheet.innerHTML = `
      <div class="modal" role="dialog" aria-labelledby="ld-title">
        <h2 id="ld-title">Discount</h2>
        <p class="small-note" id="ld-item"></p>
        <div class="field">
          <label for="ld-type">Discount</label>
          <select id="ld-type">
            <option value="None">No discount</option>
            <option value="Percent">Percentage of the line total</option>
            <option value="Amount">Amount off the line total</option>
          </select>
        </div>
        <div class="field" id="ld-value-field">
          <label for="ld-value" id="ld-value-label">Percentage (%)</label>
          <input type="number" id="ld-value" min="0" step="0.01" />
        </div>
        <p class="small-note" id="ld-preview"></p>
        <div class="error-text hidden" id="ld-error"></div>
        <div class="actions">
          <button id="ld-cancel">Cancel</button>
          <button class="primary" id="ld-save">Save</button>
        </div>
      </div>`;
    document.body.appendChild(sheet);
    const $ = (id) => sheet.querySelector(`#${id}`);
    $('ld-type').addEventListener('change', updateFields);
    $('ld-value').addEventListener('input', updatePreview);
    $('ld-cancel').addEventListener('click', close);
    $('ld-save').addEventListener('click', save);
    sheet.addEventListener('keydown', (e) => {
      if (e.key === 'Escape') close();
      if (e.key === 'Enter') save();
    });
  }

  let current = null;
  let currency = '';

  function updateFields() {
    const type = sheet.querySelector('#ld-type').value;
    sheet.querySelector('#ld-value-field').classList.toggle('hidden', type === 'None');
    sheet.querySelector('#ld-value-label').textContent = type === 'Amount' ? `Amount (${currency})` : 'Percentage (%)';
    updatePreview();
  }

  function updatePreview() {
    const type = sheet.querySelector('#ld-type').value;
    const value = Number(sheet.querySelector('#ld-value').value) || 0;
    const preview = Object.assign({}, current, { discountType: type, discountValue: value });
    const gross = cents(Math.round(current.quantity) * current.appliedUnitPrice);
    sheet.querySelector('#ld-preview').textContent = type === 'None'
      ? `Line total ${currency} ${money(gross)}`
      : `Line total ${currency} ${money(gross)} → ${currency} ${money(window.lineNetTotal(preview))}`;
  }

  function close() {
    sheet.classList.add('hidden');
    saveHandler = null;
  }

  async function save() {
    if (!saveHandler) return;
    const type = sheet.querySelector('#ld-type').value;
    const value = type === 'None' ? null : Number(sheet.querySelector('#ld-value').value);
    const result = await saveHandler(type, value);
    if (result && !result.ok) {
      const error = sheet.querySelector('#ld-error');
      error.textContent = result.error;
      error.classList.remove('hidden');
      return;
    }
    close();
  }

  window.openLineDiscount = function openLineDiscount(line, currencyLabel, handler) {
    if (!sheet) build();
    current = line;
    currency = currencyLabel;
    saveHandler = handler;
    sheet.querySelector('#ld-item').textContent = line.itemDescription.replace(/\n/g, ' ');
    sheet.querySelector('#ld-type').value = line.discountType || 'None';
    sheet.querySelector('#ld-value').value = line.discountValue || '';
    sheet.querySelector('#ld-error').classList.add('hidden');
    updateFields();
    sheet.classList.remove('hidden');
    sheet.querySelector(line.discountType ? '#ld-value' : '#ld-type').focus();
  };
})();

'use strict';

// Import… on a project's Quotations tab: a quotation from a file — an old
// quotation, one from another template, a scan or a photo. The file is read
// on this Mac first (its text, or the words off a scan); when the items
// can't be made out, the free cloud AI set up in Settings › AI Import reads
// it instead. Either way the person checks every row before the quotation
// is made, and the file is kept with the project's documents, filed with
// the new quotation.
//
//   window.importQuotation({ id, projectNumber })

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const money = (v) => Number(v || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 });
  const ACCEPT = '.pdf,.png,.jpg,.jpeg,.heic,.tif,.tiff,.webp,.gif,.bmp,.docx,.doc,.rtf,.txt,.csv,.html,.htm';
  const CURRENCIES = ['HKD', 'USD', 'CNY', 'MOP', 'EUR', 'GBP', 'SGD', 'JPY', 'AUD'];
  const SOURCE = {
    text: 'Read from the file’s text on this Mac',
    ocr: 'Read off the scan on this Mac — check the figures',
    ai: 'Read by the AI — check every row',
  };

  function pickFile() {
    return new Promise((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = ACCEPT;
      input.addEventListener('change', () => resolve(input.files && input.files[0] ? input.files[0] : null));
      input.click();
    });
  }

  const toBase64 = (file) => new Promise((resolve, reject) => {
    const r = new FileReader();
    r.onload = () => resolve(String(r.result).split(',')[1] || '');
    r.onerror = reject;
    r.readAsDataURL(file);
  });

  function sheet() {
    let el = document.getElementById('qi-modal');
    if (el) return el;
    el = document.createElement('div');
    el.className = 'modal-backdrop hidden';
    el.id = 'qi-modal';
    el.innerHTML = '<div class="modal qi-modal" role="dialog" aria-labelledby="qi-title"></div>';
    document.body.appendChild(el);
    return el;
  }

  window.importQuotation = async function importQuotation(project, file) {
    file = file || await pickFile();
    if (!file) return;
    const modal = sheet();
    const box = modal.querySelector('.qi-modal');
    let draft = null;
    let busy = false;
    let closed = false;

    const close = () => { closed = true; modal.classList.add('hidden'); document.removeEventListener('keydown', onKey, true); };
    const onKey = (e) => { if (e.key === 'Escape' && !busy) { e.preventDefault(); e.stopPropagation(); close(); } };
    document.addEventListener('keydown', onKey, true);

    const working = (title, text) => {
      box.innerHTML = `<h2 id="qi-title">Import a Quotation</h2>
        <div class="qi-working"><span class="qi-spin" aria-hidden="true"></span><div><b>${esc(title)}</b><span>${esc(text)}</span></div></div>
        <div class="actions"><button id="qi-cancel">Cancel</button></div>`;
      box.querySelector('#qi-cancel').addEventListener('click', close);
    };

    modal.classList.remove('hidden');
    working(`Reading ${file.name}…`, 'On this Mac — a scan takes a little longer.');
    let read;
    try {
      read = await window.api.quotations.importRead(project.projectNumber, file.name, await toBase64(file));
    } catch (e) {
      read = { ok: false, error: 'The file couldn’t be read.' };
    }
    if (closed) return;
    if (!read || !read.ok) { close(); alert((read && read.error) || 'The file couldn’t be read.'); return; }
    draft = read;
    let aiNote = '';
    if (draft.unsure && draft.aiReady) {
      working('Asking the AI to read it…', 'The items couldn’t be made out on this Mac, so the file goes to the AI set up in Settings.');
      const r = await window.api.quotations.importAI(draft.token);
      if (closed) return;
      if (r && r.ok) draft = r; else aiNote = (r && r.error) || 'The AI couldn’t read it.';
    }
    review();

    async function askAI() {
      const local = draft;
      busy = true;
      working('Asking the AI to read it…', 'This takes up to a minute.');
      const r = await window.api.quotations.importAI(local.token);
      busy = false;
      if (closed) return;
      if (r && r.ok) { draft = r; aiNote = ''; } else { draft = local; aiNote = (r && r.error) || 'The AI couldn’t read it.'; }
      review();
    }

    function rowHTML(it, i) {
      const amount = Number(it.quantity || 0) * Number(it.unitPrice || 0);
      return `<tr data-i="${i}">
        <td class="qi-kind"><select data-f="kind" aria-label="Kind">
          <option value="Material"${it.kind === 'Material' || !it.kind ? ' selected' : ''}>Item</option>
          <option value="Delivery"${it.kind === 'Delivery' ? ' selected' : ''}>Delivery</option>
          <option value="Other"${it.kind === 'Other' ? ' selected' : ''}>Other charge</option></select>
          ${it.kind === 'Other' ? `<input type="text" data-f="section" value="${esc(it.section || '')}" placeholder="Section, e.g. Design Fees" aria-label="Section" />` : ''}</td>
        <td><input type="text" data-f="itemCode" value="${esc(it.itemCode || '')}" aria-label="Code" />${it.matched ? '<span class="qi-match" title="In the material list: linked to it, at the price on the file">✓ listed</span>' : ''}</td>
        <td><input type="text" data-f="description" value="${esc(it.description)}" aria-label="Description" /></td>
        <td><input type="text" data-f="unit" value="${esc(it.unit || '')}" aria-label="Unit" /></td>
        <td class="num"><input type="number" data-f="quantity" value="${esc(it.quantity)}" min="0" step="1" aria-label="Quantity" /></td>
        <td class="num"><input type="number" data-f="unitPrice" value="${esc(it.unitPrice)}" min="0" step="0.01" aria-label="Unit price" /></td>
        <td class="num qi-amount">${money(amount)}</td>
        <td><button type="button" class="qi-del" data-no-icon title="Leave this row out" aria-label="Leave this row out">×</button></td></tr>`;
    }

    function review() {
      if (!Array.isArray(draft.items)) draft.items = [];
      const items = draft.items;
      const total = () => items.reduce((s, it) => s + Number(it.quantity || 0) * Number(it.unitPrice || 0), 0);
      box.innerHTML = `<div class="qi-head"><h2 id="qi-title">Import a Quotation</h2>
          <span class="qi-source ${esc(draft.source)}">${esc(SOURCE[draft.source] || '')}</span></div>
        <div class="qi-file">${esc(draft.fileName)}${draft.oldNumber ? ` · was ${esc(draft.oldNumber)}` : ''} <span class="muted">— kept with the project’s documents, filed with the new quotation</span></div>
        ${aiNote ? `<div class="qi-note warn">${esc(aiNote)}</div>` : ''}
        ${!items.length ? `<div class="qi-note">No items could be made out${draft.source === 'ai' ? '' : ' on this Mac'}. ${draft.aiReady && draft.source !== 'ai' ? 'Ask the AI to read it, or add' : 'Add'} the rows by hand${draft.aiReady ? '' : ' — or set up the free AI in <a href="settings.html#ai-import">Settings › AI Import</a> to read files like this'}.</div>` : ''}
        <div class="qi-fields">
          <label class="qi-field wide"><span>Re:</span><input type="text" id="qi-subject" value="${esc(draft.subject || '')}" placeholder="The subject line" /></label>
          <label class="qi-field"><span>Your Ref.</span><input type="text" id="qi-ref" value="${esc(draft.clientRef || '')}" /></label>
          <div class="qi-field"><span>Priced for</span><div class="segmented" id="qi-mode"><button type="button" data-v="Rental" data-no-icon>Rental</button><button type="button" data-v="Sale" data-no-icon>Sale</button></div></div>
          <label class="qi-field"><span>Currency</span><select id="qi-currency">${CURRENCIES.map((c) => `<option${(draft.currency || 'HKD') === c ? ' selected' : ''}>${c}</option>`).join('')}</select></label>
        </div>
        <div class="qi-table-wrap"><table class="qi-table">
          <thead><tr><th>Kind</th><th>Code</th><th>Description</th><th>Unit</th><th class="num">Qty</th><th class="num">Unit price${draft.pricingMode === 'Rental' ? ' <span class="muted">/ month</span>' : ''}</th><th class="num">Amount</th><th></th></tr></thead>
          <tbody>${items.map(rowHTML).join('')}</tbody>
          <tfoot><tr><td colspan="6"><button type="button" class="link-btn" id="qi-add" data-no-icon>+ Add a row</button></td><td class="num qi-total">${money(total())}</td><td></td></tr></tfoot>
        </table></div>
        ${draft.textPreview ? `<details class="qi-text"><summary data-no-icon>What was read from the file</summary><pre>${esc(draft.textPreview)}</pre></details>` : ''}
        <div class="actions">
          ${draft.source !== 'ai' ? (draft.aiReady ? '<button class="left" id="qi-ai" data-no-icon>Ask the AI to Read It</button>' : '<a class="left qi-setup" href="settings.html#ai-import">Set up the AI…</a>') : ''}
          <button id="qi-cancel">Cancel</button>
          <button class="primary" id="qi-create">Make Quotation${items.length ? ` (${items.length} row${items.length === 1 ? '' : 's'})` : ''}</button>
        </div>`;
      let mode = draft.pricingMode === 'Sale' ? 'Sale' : 'Rental';
      const drawMode = () => { for (const b of box.querySelectorAll('#qi-mode button')) b.classList.toggle('active', b.dataset.v === mode); };
      drawMode();
      for (const b of box.querySelectorAll('#qi-mode button')) b.addEventListener('click', () => { mode = b.dataset.v; draft.pricingMode = mode; drawMode(); });
      const keepHeader = () => {
        draft.subject = box.querySelector('#qi-subject').value;
        draft.clientRef = box.querySelector('#qi-ref').value;
        draft.currency = box.querySelector('#qi-currency').value;
        draft.pricingMode = mode;
      };
      const tbody = box.querySelector('tbody');
      tbody.addEventListener('input', (e) => {
        const tr = e.target.closest('tr');
        const f = e.target.dataset.f;
        if (!tr || !f) return;
        const it = items[Number(tr.dataset.i)];
        it[f] = e.target.type === 'number' ? Number(e.target.value) : e.target.value;
        if (f === 'itemCode') it.matched = false;
        tr.querySelector('.qi-amount').textContent = money(Number(it.quantity || 0) * Number(it.unitPrice || 0));
        box.querySelector('.qi-total').textContent = money(total());
      });
      tbody.addEventListener('change', (e) => {
        if (e.target.dataset.f !== 'kind') return;
        keepHeader();
        review();
      });
      tbody.addEventListener('click', (e) => {
        const del = e.target.closest('.qi-del');
        if (!del) return;
        items.splice(Number(del.closest('tr').dataset.i), 1);
        keepHeader();
        review();
      });
      box.querySelector('#qi-add').addEventListener('click', () => {
        keepHeader();
        items.push({ kind: 'Material', description: '', unit: 'pc', quantity: 1, unitPrice: 0 });
        draft.items = items;
        review();
        const last = box.querySelector('tbody tr:last-child [data-f="description"]');
        if (last) last.focus();
      });
      const ai = box.querySelector('#qi-ai');
      if (ai) ai.addEventListener('click', () => { keepHeader(); askAI(); });
      box.querySelector('#qi-cancel').addEventListener('click', close);
      box.querySelector('#qi-create').addEventListener('click', async () => {
        keepHeader();
        const rows = items.filter((it) => String(it.description || '').trim());
        const btn = box.querySelector('#qi-create');
        btn.disabled = true;
        busy = true;
        const r = await window.api.quotations.importCreate({
          token: draft.token, projectNumber: project.projectNumber, subject: draft.subject, clientRef: draft.clientRef,
          pricingMode: draft.pricingMode, currency: draft.currency, oldNumber: draft.oldNumber || '',
          items: rows.map((it) => ({ kind: it.kind || 'Material', section: it.section || null, itemCode: it.itemCode || null, description: String(it.description).trim(),
            unit: it.unit || 'pc', quantity: Number(it.quantity) || 1, unitPrice: Number(it.unitPrice) || 0 })),
        });
        busy = false;
        if (!r || !r.ok) { btn.disabled = false; alert((r && r.error) || 'The quotation couldn’t be made.'); return; }
        if (r.error) await window.appAlert(r.error);
        location.href = `quotation-editor.html?id=${encodeURIComponent(r.id)}`;
      });
    }
  };
})();

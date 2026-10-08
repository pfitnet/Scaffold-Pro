'use strict';

// A worker's employment agreement (簡易僱傭合約), on Admin › Workers: made
// when the worker is added, from the company's template with their name,
// ID card number and the terms below. Preview it as a PDF or a Word
// document, print it, have it signed and chopped for the employer (by
// someone the Team page marks as signing worker agreements), then add the
// copy the worker signed — chosen, or dropped onto the card.
//
//   window.workerAgreement.render(container, worker)

(function () {
  if (window.workerAgreement) return;
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const api = () => window.api.workerAgreements;
  const day = (iso) => (iso ? (window.appDay ? window.appDay(String(iso).slice(0, 10)) : String(iso).slice(0, 10)) : '');
  const ICON = {
    doc: '<svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linejoin="round" aria-hidden="true"><path d="M5.5 2.8h6l3.5 3.5v10.9H5.5z"/><path d="M11.5 2.8v3.5H15M8 10h5M8 13h5"/></svg>',
    pen: '<svg viewBox="0 0 20 20" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M13.2 3.8l3 3-8.7 8.7-3.7.7.7-3.7z"/></svg>',
    upload: '<svg viewBox="0 0 20 20" width="15" height="15" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10 13V3.5M6 7.5l4-4 4 4M4 13.5v3h12v-3"/></svg>',
    check: '<svg viewBox="0 0 20 20" width="13" height="13" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4.5 10.5l3.5 3.5 7.5-8"/></svg>',
  };

  // The three steps: made → signed & chopped for the employer → signed by the worker.
  function stepsHTML(page) {
    const a = page.agreement;
    const steps = [
      { label: 'Made', done: true, sub: day(a.createdAt) },
      { label: 'Signed & chopped', done: !!a.employerSignedBy, sub: a.employerSignedBy ? `${a.employerSignedBy}, ${day(a.employerSignedAt)}` : 'for the employer' },
      { label: 'Signed by the worker', done: !!a.signedCopyPath, sub: a.signedCopyPath ? `copy added ${day(a.signedCopyAt)}` : 'upload the signed copy' },
    ];
    const current = steps.findIndex((s) => !s.done);
    return `<ol class="ea-steps">${steps.map((s, i) => `<li class="${s.done ? 'done' : i === current ? 'now' : ''}">
      <span class="ea-step-dot">${s.done ? ICON.check : i + 1}</span><span class="ea-step-text"><b>${esc(s.label)}</b><small>${esc(s.sub)}</small></span></li>`).join('')}</ol>`;
  }

  function fieldsHTML(page) {
    const a = page.agreement;
    const signers = page.signers || [];
    const chosen = a.employerSignedBy || a.signatory || '';
    const options = signers.length
      ? (chosen && !signers.includes(chosen) ? [chosen, ...signers] : signers).map((n) => `<option ${n === chosen ? 'selected' : ''}>${esc(n)}</option>`).join('')
      : '<option value="">No one yet — Team page</option>';
    return `<div class="ea-fields">
      <label class="ea-field"><span>Agreement date</span><input type="date" data-ea="agreementDate" value="${esc(a.agreementDate)}" /></label>
      <label class="ea-field"><span>Starts</span><input type="date" data-ea="startDate" value="${esc(a.startDate)}" /></label>
      <label class="ea-field"><span>Position</span><input type="text" data-ea="position" value="${esc(a.position)}" /></label>
      <label class="ea-field"><span>Daily wage (HK$)</span><input type="number" min="0" step="10" data-ea="dailyWage" value="${esc(a.dailyWage)}" /></label>
      <label class="ea-field wide"><span>Hours</span><span class="ea-pair"><input type="time" data-ea="hoursFrom" value="${esc(a.hoursFrom)}" /><i>to</i><input type="time" data-ea="hoursTo" value="${esc(a.hoursTo)}" /></span></label>
      <label class="ea-field"><span>Wages paid on day</span><input type="number" min="1" max="28" step="1" data-ea="payDay" value="${esc(a.payDay)}" /></label>
      <label class="ea-field"><span>Notice (days)</span><input type="number" min="0" max="365" step="1" data-ea="noticeDays" value="${esc(a.noticeDays)}" /></label>
      <label class="ea-field wide"><span>Signed for the employer by</span><select data-ea="signatory" ${a.employerSignedBy || !signers.length ? 'disabled' : ''}>${options}</select></label>
    </div>`;
  }

  function signHTML(page) {
    const a = page.agreement;
    if (a.employerSignedBy) {
      return `<div class="ea-row ok"><span class="ea-row-icon">${ICON.check}</span>
        <span class="ea-row-text">Signed &amp; chopped by <b>${esc(a.employerSignedBy)}</b> on ${esc(day(a.employerSignedAt))}${page.employerSignedExists ? '' : ' <span class="ea-warn">— the PDF isn’t in the folder any more</span>'}</span>
        <span class="ea-row-actions">${page.employerSignedExists ? '<button type="button" data-ea-act="viewSigned">View</button>' : ''}<button type="button" data-ea-act="unsign" class="danger-btn">Withdraw</button></span></div>`;
    }
    if (page.canSign) {
      return `<div class="ea-row"><span class="ea-row-icon pen">${ICON.pen}</span>
        <span class="ea-row-text">${page.hasSignature ? 'You can sign and chop it for the employer.' : 'Add your signature on the Team page (your name › Signature) to sign it here.'}</span>
        <span class="ea-row-actions"><button type="button" class="primary" data-ea-act="sign" ${page.hasSignature ? '' : 'disabled'}>Sign &amp; Chop</button></span></div>`;
    }
    const who = page.signers || [];
    return `<div class="ea-row muted"><span class="ea-row-icon pen">${ICON.pen}</span>
      <span class="ea-row-text">${who.length ? `To be signed and chopped by ${esc(who.join(' or '))}.` : 'No one signs worker agreements yet — tick “Signs and chops worker agreements” for them on the Team page.'}</span></div>`;
  }

  function copyHTML(page) {
    const a = page.agreement;
    if (a.signedCopyPath) {
      return `<div class="ea-row ok" data-ea-drop><span class="ea-row-icon">${ICON.check}</span>
        <span class="ea-row-text">The copy signed by the worker was added on ${esc(day(a.signedCopyAt))}${page.signedCopyExists ? '' : ' <span class="ea-warn">— it isn’t in the folder any more</span>'}</span>
        <span class="ea-row-actions">${page.signedCopyExists ? '<button type="button" data-ea-act="openCopy">Open</button><button type="button" data-ea-act="revealCopy">Locate File</button>' : ''}<button type="button" data-ea-act="replaceCopy">Replace…</button></span></div>`;
    }
    return `<div class="ea-drop" data-ea-drop>
      <span class="ea-row-icon">${ICON.upload}</span>
      <span class="ea-row-text"><b>The copy signed by the worker</b><small>Print it, have ${esc(page.workerName || 'the worker')} sign it, then drop the scan or photo here.</small></span>
      <span class="ea-row-actions"><button type="button" data-ea-act="upload">Upload Signed Copy…</button></span></div>`;
  }

  async function render(container, worker) {
    if (!container) return;
    let page = await api().get(worker.id);
    if (!page) { container.innerHTML = ''; return; }
    page.workerName = worker.name;
    if (!page.agreement) {
      container.innerHTML = `<section class="ea-card empty"><div class="ea-head"><span class="ea-icon">${ICON.doc}</span>
        <div class="ea-title"><b>Employment Agreement</b><small>簡易僱傭合約 — none for ${esc(worker.name)} yet</small></div>
        <button type="button" class="primary" data-ea-act="create">Make Agreement</button></div></section>`;
      container.querySelector('[data-ea-act="create"]').addEventListener('click', async () => {
        const r = await api().create(worker.id);
        if (r && r.ok === false) { await window.appAlert(r.error); return; }
        render(container, worker);
      });
      return;
    }
    const a = page.agreement;
    container.innerHTML = `<section class="ea-card">
      <div class="ea-head">
        <span class="ea-icon">${ICON.doc}</span>
        <div class="ea-title"><b>Employment Agreement</b><small>簡易僱傭合約 · ${esc(page.number)}</small></div>
        <div class="ea-exports">
          <button type="button" data-ea-act="pdf" title="See the PDF, then save it into the worker’s Contracts folder">Preview PDF</button>
          <button type="button" data-ea-act="word" title="A Word copy laid out like the PDF">Word</button>
          <button type="button" data-ea-act="print">Print</button>
        </div>
      </div>
      ${stepsHTML(page)}
      ${(page.missing || []).length ? `<div class="ea-missing">Still to fill in: ${page.missing.map(esc).join('; ')}. It’s printed on the agreement.</div>` : ''}
      ${fieldsHTML(page)}
      ${signHTML(page)}
      ${copyHTML(page)}
    </section>`;

    const reload = () => render(container, worker);
    // The terms: saved as they change. After the employer has signed, a
    // change means signing again — asked first.
    for (const el of container.querySelectorAll('[data-ea]')) {
      el.addEventListener('change', async () => {
        const key = el.dataset.ea;
        if (a.employerSignedBy && key !== 'signatory'
          && !await window.appConfirm(`Change the agreement’s terms?\n\n${a.employerSignedBy}’s signature and chop come off; it will need signing again. The signed PDF stays in the folder.`, { ok: 'Change' })) {
          reload();
          return;
        }
        const r = await api().update(a.id, { [key]: el.value });
        if (r && r.ok === false) await window.appAlert(r.error);
        reload();
      });
    }
    const on = (act, fn) => { const b = container.querySelector(`[data-ea-act="${act}"]`); if (b) b.addEventListener('click', () => fn(b)); };
    on('pdf', async () => {
      const r = await window.docPreview.pdf(() => api().exportPDF(a.id, { preview: true }), { title: `${page.number} Employment Agreement`, note: 'Saved into the worker’s Contracts folder when you click Save.' });
      if (r && r.ok === false) await window.appAlert(r.error);
    });
    on('word', async (b) => {
      b.disabled = true;
      try {
        const r = await window.exportWord(() => api().exportWord(a.id));
        if (r && r.ok === false) await window.appAlert(r.error);
      } catch (e) {
        await window.appAlert(`The Word document couldn't be made.\n\n${e.message}`);
      }
      b.disabled = false;
    });
    on('print', async () => { const r = await api().print(a.id); if (r && r.ok === false) await window.appAlert(r.error); });
    on('sign', async (b) => {
      if (page.missing && page.missing.length && !await window.appConfirm(`Sign it without ${page.missing.join(' and ')}?\n\nThat line is left blank on the agreement.`, { ok: 'Sign Anyway' })) return;
      b.disabled = true;
      b.textContent = 'Signing…';
      const r = await api().sign(a.id);
      if (!r || r.ok === false) { await window.appAlert((r && r.error) || 'It couldn’t be signed.'); reload(); return; }
      await reload();
      viewSigned(r.path);
    });
    const viewSigned = async (path) => {
      const r = await window.docPreview.pdf(() => window.api.signatures.previewSigned(path), {
        title: `${page.number} — Signed & Chopped`,
        note: 'Saved in the worker’s Contracts folder. Print it for the worker to sign.',
        actions: [{ key: 'open', label: 'Open in Preview' }, { key: 'done', label: 'Done', primary: true }],
      });
      if (r && r.action === 'open') api().file(a.id, 'employer', 'open');
    };
    on('viewSigned', () => viewSigned(a.employerSignedPath));
    on('unsign', async () => {
      if (!await window.appConfirm(`Withdraw ${a.employerSignedBy}’s signature and chop?\n\nThe signed PDF goes to the Trash.`, { ok: 'Withdraw', danger: true })) return;
      await api().unsign(a.id);
      reload();
    });
    const upload = async () => {
      const r = await api().uploadSigned(a.id);
      if (r && r.ok === false) await window.appAlert(r.error);
      reload();
    };
    on('upload', upload);
    on('replaceCopy', upload);
    on('openCopy', async () => { const r = await api().file(a.id, 'signed', 'open'); if (r && r.ok === false) window.appAlert(r.error); });
    on('revealCopy', async () => { const r = await api().file(a.id, 'signed', 'reveal'); if (r && r.ok === false) window.appAlert(r.error); });

    // Dropping the signed copy onto the card.
    const card = container.querySelector('.ea-card');
    const hasFiles = (e) => e.dataTransfer && [...e.dataTransfer.types].includes('Files');
    let depth = 0;
    card.addEventListener('dragenter', (e) => { if (!hasFiles(e)) return; depth++; card.classList.add('dropping'); });
    card.addEventListener('dragleave', (e) => { if (!hasFiles(e)) return; depth = Math.max(0, depth - 1); if (!depth) card.classList.remove('dropping'); });
    card.addEventListener('dragover', (e) => { if (hasFiles(e)) e.preventDefault(); });
    card.addEventListener('drop', (e) => {
      if (!hasFiles(e)) return;
      e.preventDefault();
      depth = 0;
      card.classList.remove('dropping');
      const file = e.dataTransfer.files[0];
      if (!file) return;
      const reader = new FileReader();
      reader.onload = async () => {
        const r = await api().saveSignedFile(a.id, file.name, String(reader.result).split(',')[1] || '');
        if (r && r.ok === false) await window.appAlert(r.error);
        reload();
      };
      reader.readAsDataURL(file);
    });
  }

  window.workerAgreement = { render };
})();

'use strict';

// Signed delivery notes. The note is signed on site and the copy (a PDF,
// or a photo or scan) is kept in the project's Delivery Notes folder as
// "<DN no.> - Signed.pdf". It's added after the pages of the invoice that
// bills that delivery note (Export PDF, Print, and Select › Export PDF).
//
//   window.dnSigned.bar(el, deliveryNoteDetail, reload)   — the delivery note editor
//   window.dnSigned.list(el, invoiceDetail, reload)       — the invoice editor

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const day = (iso) => { const d = new Date(iso || ''); return isNaN(d) ? '' : d.toLocaleDateString('en-GB', { day: 'numeric', month: 'short', year: 'numeric' }).replace('Sept', 'Sep'); };
  const copy = () => window.signedCopyFor('deliveryNote');

  // The bar under a delivery note's toolbar.
  function bar(el, d, reload) {
    const has = !!d.signedCopyName;
    el.classList.toggle('hidden', d.status === 'Draft' && !has);
    if (d.status === 'Draft' && !has) return;
    const goesWith = d.invoiceNumbers && d.invoiceNumbers.length
      ? `It's added after invoice ${esc(d.invoiceNumbers.join(', '))}.`
      : 'It will be added after the invoice that bills this note.';
    el.classList.toggle('signed-done', has && d.signedCopyExists);
    if (has && d.signedCopyExists) {
      el.innerHTML = `<span class="signed-text"><span class="status-pill pill-success">Signed</span>
          Signed copy added${d.signedCopyAt ? ` ${esc(day(d.signedCopyAt))}` : ''}: <strong>${esc(d.signedCopyName)}</strong>. ${goesWith}</span>
        <span class="signed-actions"><button data-act="open">Open</button><button data-act="reveal">Locate File</button>
          <button data-act="upload">Replace…</button><button data-act="remove">Remove</button></span>`;
    } else if (has) {
      el.innerHTML = `<span class="signed-text"><span class="status-pill pill-danger">Missing</span>
          The signed copy (${esc(d.signedCopyName)}) is no longer in the project folder.</span>
        <span class="signed-actions"><button class="primary" data-act="upload">Upload Signed Copy…</button><button data-act="remove">Remove</button></span>`;
    } else {
      el.innerHTML = `<span class="signed-text"><span class="status-pill pill-warning">Waiting</span>
          Waiting for the copy signed on site. Upload it, or drop the PDF or photo here. ${goesWith}</span>
        <span class="signed-actions"><button class="primary" data-act="upload">Upload Signed Copy…</button></span>`;
    }
    if (!el.dataset.wired) {
      el.dataset.wired = '1';
      copy().dropTarget(el, d.id, reload);
      el.addEventListener('click', async (e) => {
        const b = e.target.closest('button[data-act]');
        if (!b) return;
        const c = copy();
        let changed = false;
        if (b.dataset.act === 'open') await c.open(d.id);
        else if (b.dataset.act === 'reveal') await c.reveal(d.id);
        else if (b.dataset.act === 'upload') changed = await c.upload(d.id);
        else if (b.dataset.act === 'remove') changed = await c.remove(d.id, d.deliveryNoteNumber);
        if (changed) await reload();
      });
    }
  }

  // The invoice's delivery notes, each with its signed copy (or a way to add it).
  function list(el, inv, reload) {
    const notes = inv.deliveryNotes || [];
    el.classList.toggle('hidden', !notes.length);
    if (!notes.length) return;
    const signed = notes.filter((n) => n.signedCopyExists).length;
    el.innerHTML = `<div class="dns-head"><b>Signed delivery notes</b>
        <span class="small-note">${signed ? `${signed} of ${notes.length} attached after this invoice's pages when it's exported or printed.` : 'None signed yet. Once uploaded, each is added after this invoice’s pages.'}</span></div>
      ${notes.map((n) => `<div class="dns-row${n.signedCopyExists ? ' done' : ''}" data-id="${esc(n.id)}">
        <a href="delivery-note-editor.html?id=${encodeURIComponent(n.id)}"><b>${esc(n.number)}</b></a>
        ${n.signedCopyExists ? `<span class="status-pill pill-success">Signed</span><span class="dns-file">${esc(n.signedCopyName)}</span>`
          : n.signedCopyName ? '<span class="status-pill pill-danger">Missing</span><span class="dns-file">The signed copy is no longer in the folder.</span>'
          : '<span class="status-pill pill-warning">Not signed yet</span><span class="dns-file">Drop the signed PDF or photo here.</span>'}
        <span class="dns-actions">${n.signedCopyExists ? '<button data-act="open" data-no-icon>Open</button>' : '<button class="primary" data-act="upload" data-no-icon>Upload Signed Copy…</button>'}</span>
      </div>`).join('')}`;
    for (const row of el.querySelectorAll('.dns-row')) {
      copy().dropTarget(row, row.dataset.id, reload);
      row.addEventListener('click', async (e) => {
        const b = e.target.closest('button[data-act]');
        if (!b) return;
        const c = copy();
        if (b.dataset.act === 'open') await c.open(row.dataset.id);
        else if (b.dataset.act === 'upload' && await c.upload(row.dataset.id)) await reload();
      });
    }
  }

  window.dnSigned = { bar, list };
})();

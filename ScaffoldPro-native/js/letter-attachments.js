'use strict';

// A letter's attachments (annexures), under the letter in its editor:
// each numbered (ANNEXURE P.01, P.02…, the prefix can be changed), with
// what it is and its files. Exported, the letter lists them, and each gets
// a cover page followed by its files. Drag the handle (or ↑ / ↓) to
// reorder; the numbers follow.

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const id = new URLSearchParams(location.search).get('id');
  let letter = null;
  let list = [];
  let timer = null;
  const label = (i) => `${(letter && letter.annexurePrefix) || 'ANNEXURE P.'}${String(i + 1).padStart(2, '0')}`;
  const base = (p) => String(p).split('/').pop();
  const FILE = '<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.4" aria-hidden="true"><path d="M9.5 1.5H4A1.5 1.5 0 0 0 2.5 3v10A1.5 1.5 0 0 0 4 14.5h8a1.5 1.5 0 0 0 1.5-1.5V5.5z"/><path d="M9.5 1.5v4h4"/></svg>';

  function save(fields) {
    clearTimeout(timer);
    timer = setTimeout(async () => {
      const r = await window.api.letters.update(id, fields || { attachments: list });
      if (r && r.ok === false) window.appAlert(r.error);
    }, 350);
  }

  function draw() {
    const locked = letter.status !== 'Draft';
    const box = document.getElementById('annex-list');
    document.getElementById('annex-add').disabled = locked;
    document.getElementById('annex-prefix').disabled = locked;
    box.innerHTML = list.length ? list.map((a, i) => `
      <div class="annex-row" data-i="${i}">
        <div class="annex-order">
          <button type="button" class="annex-up" data-no-icon ${i === 0 || locked ? 'disabled' : ''} title="Move up" aria-label="Move up">↑</button>
          <button type="button" class="annex-down" data-no-icon ${i === list.length - 1 || locked ? 'disabled' : ''} title="Move down" aria-label="Move down">↓</button>
        </div>
        <div class="annex-label">${esc(label(i))}</div>
        <div class="annex-body">
          <input type="text" class="annex-desc" value="${esc(a.description)}" placeholder="What it is, e.g. a detailed list of items for 1 unit of Kroll K1400" ${locked ? 'disabled' : ''} />
          <div class="annex-files">${a.files.map((f, j) => `<span class="annex-file"><button type="button" class="annex-open" data-path="${esc(f)}" data-no-icon title="Open">${FILE}${esc(base(f))}</button>${locked ? '' : `<button type="button" class="annex-file-x" data-j="${j}" data-no-icon title="Take this file off" aria-label="Remove file">×</button>`}</span>`).join('')}
            ${locked ? '' : '<button type="button" class="annex-more" data-no-icon>+ Files…</button>'}
            ${a.files.length ? '' : '<span class="annex-nofiles">Only its cover page — no files yet.</span>'}</div>
        </div>
        ${locked ? '' : '<button type="button" class="icon-btn annex-remove" data-no-icon title="Remove this attachment" aria-label="Remove">×</button>'}
      </div>`).join('') : '<p class="annex-none">No attachments. Add PDFs or pictures to send as annexures with this letter.</p>';
    box.querySelectorAll('.annex-row').forEach((row) => {
      const i = Number(row.dataset.i);
      const on = (sel, ev, fn) => { const el = row.querySelector(sel); if (el) el.addEventListener(ev, fn); };
      on('.annex-desc', 'input', (e) => { list[i].description = e.target.value; save(); });
      on('.annex-up', 'click', () => { [list[i - 1], list[i]] = [list[i], list[i - 1]]; draw(); save(); });
      on('.annex-down', 'click', () => { [list[i + 1], list[i]] = [list[i], list[i + 1]]; draw(); save(); });
      on('.annex-remove', 'click', async () => {
        if (!await window.appConfirm(`Remove ${label(i)}?\n\nIts cover page and files come off the letter (the copied files stay in the folder).`, { ok: 'Remove' })) return;
        list.splice(i, 1); draw(); save();
      });
      on('.annex-more', 'click', () => addFiles(list[i].id));
      row.querySelectorAll('.annex-file-x').forEach((b) => b.addEventListener('click', () => { list[i].files.splice(Number(b.dataset.j), 1); draw(); save(); }));
      row.querySelectorAll('.annex-open').forEach((b) => b.addEventListener('click', async () => {
        const r = await window.api.letters.openAttachmentFile(b.dataset.path);
        if (r && r.ok === false) window.appAlert(r.error);
      }));
    });
  }

  async function addFiles(attachmentId) {
    const r = await window.api.letters.addAttachmentFiles(id, attachmentId);
    if (!r) return;
    if (r.ok === false) { await window.appAlert(r.error); return; }
    list = r.attachments || list;
    draw();
  }

  window.letterAttachments = {
    render(l) {
      letter = l;
      list = JSON.parse(JSON.stringify(l.attachments || []));
      const prefix = document.getElementById('annex-prefix');
      if (document.activeElement !== prefix) prefix.value = l.annexurePrefix || 'ANNEXURE P.';
      draw();
    },
  };
  document.getElementById('annex-add').addEventListener('click', () => addFiles(null));
  document.getElementById('annex-prefix').addEventListener('input', (e) => {
    if (!letter) return;
    // A space typed at the end is kept ("ANNEX " → ANNEX 01).
    const v = e.target.value.replace(/^\s+/, '');
    letter.annexurePrefix = v.trim() ? v : 'ANNEXURE P.';
    draw();
    save({ annexurePrefix: v.trim() ? v : '' });
  });
})();

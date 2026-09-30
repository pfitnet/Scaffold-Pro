'use strict';

// "Select" for a project's lists of BOQs, quotations, invoices and delivery
// notes. The tick boxes only appear after pressing Select; then clicking a
// row ticks it (instead of opening it), and the toolbar offers:
//   Select All · Export PDF (all of them in one PDF, optionally each with
//   its drawings) · Locate Files (one Finder window with their files) ·
//   Combine (opts.combine: one new document with their quantities added up) · Done
//
//   const sel = window.createDocumentSelection({ kind: 'Quotation', noun: 'quotation', drawings: true,
//     toolbar: el, container: el, order: () => ids });
//   … when rendering: sel.headerCell() / sel.cell(id) / sel.footerCell(); then sel.afterRender().

(function () {
  let modal = null;

  function exportModal() {
    if (modal) return modal;
    modal = document.createElement('div');
    modal.className = 'modal-backdrop hidden';
    modal.innerHTML = `
      <div class="modal">
        <h2 class="sel-modal-title"></h2>
        <p class="small-note sel-modal-summary"></p>
        <label class="inline-check sel-drawings-row"><input type="checkbox" class="sel-drawings" /> <span class="sel-drawings-label"></span></label>
        <p class="small-note">They go one after another into a single PDF, saved in the project's folder and opened.</p>
        <div class="actions">
          <button class="sel-cancel" data-no-icon>Cancel</button>
          <button class="primary sel-go" data-no-icon>Export PDF</button>
        </div>
      </div>`;
    document.body.appendChild(modal);
    modal.querySelector('.sel-cancel').addEventListener('click', () => modal.classList.add('hidden'));
    return modal;
  }

  window.createDocumentSelection = function (opts) {
    const plural = opts.plural || `${opts.noun}s`;
    let selecting = false;
    const selected = new Set();

    const controls = document.createElement('span');
    controls.className = 'select-controls';
    controls.innerHTML = `
      <button class="sel-start" data-no-icon title="Choose several ${plural} to export as one PDF or show in Finder">${window.ICONS ? window.ICONS.select : ''}<span>Select</span></button>
      <span class="sel-active hidden">
        <span class="sel-count small-note"></span>
        <button class="sel-all" data-no-icon>Select All</button>
        <button class="sel-export" data-no-icon disabled>${window.ICONS ? window.ICONS.pdf : ''}<span>Export PDF</span></button>
        <button class="sel-locate" disabled>Locate Files</button>
        ${opts.combine ? `<button class="sel-combine" data-no-icon disabled title="${opts.combine.title}">${opts.combine.label}</button>` : ''}
        <button class="primary sel-done" data-no-icon>Done</button>
      </span>`;
    opts.toolbar.prepend(controls);
    const $ = (c) => controls.querySelector(c);

    const ids = () => opts.order();
    const chosen = () => ids().filter((id) => selected.has(id));

    function update() {
      opts.container.classList.toggle('selecting', selecting);
      $('.sel-start').classList.toggle('hidden', selecting);
      $('.sel-active').classList.toggle('hidden', !selecting);
      for (const id of [...selected]) if (!ids().includes(id)) selected.delete(id);
      const n = selected.size;
      $('.sel-count').textContent = n === 0 ? `Tick the ${plural} you want` : `${n} selected`;
      $('.sel-export').disabled = n === 0;
      $('.sel-locate').disabled = n === 0;
      if (opts.combine) $('.sel-combine').disabled = n < 2;
      const all = ids().length > 0 && n === ids().length;
      $('.sel-all').textContent = all ? 'Select None' : 'Select All';
      for (const box of opts.container.querySelectorAll('input.doc-select')) {
        box.checked = selected.has(box.dataset.id);
        const tr = box.closest('tr');
        if (tr) tr.classList.toggle('row-selected', box.checked);
      }
    }

    function setSelecting(on) {
      selecting = on;
      if (!on) selected.clear();
      update();
    }

    $('.sel-start').addEventListener('click', () => setSelecting(true));
    $('.sel-done').addEventListener('click', () => setSelecting(false));
    $('.sel-all').addEventListener('click', () => {
      const all = ids().length > 0 && selected.size === ids().length;
      selected.clear();
      if (!all) for (const id of ids()) selected.add(id);
      update();
    });
    document.addEventListener('keydown', (e) => {
      if (e.key === 'Escape' && selecting && document.querySelector('.modal-backdrop:not(.hidden)') === null) setSelecting(false);
    });

    // While selecting, clicking a row ticks it rather than opening it.
    opts.container.addEventListener('click', (e) => {
      if (!selecting) return;
      const tr = e.target.closest('tr[data-id]');
      if (!tr || !opts.container.contains(tr)) return;
      if (e.target.closest('button, a, select, .row-actions')) return; // the row's own buttons still work
      e.stopPropagation();
      const id = tr.dataset.id;
      if (selected.has(id)) selected.delete(id); else selected.add(id);
      update();
    }, true);

    $('.sel-locate').addEventListener('click', async () => {
      const r = await window.api.files.locateDocuments(opts.kind, chosen());
      if (r && !r.ok) alert(r.error);
      else if (r && r.note) alert(r.note);
    });

    // Combine: one new document with the chosen ones' quantities added up.
    if (opts.combine) {
      $('.sel-combine').addEventListener('click', async () => {
        const list = chosen();
        if (list.length < 2) return;
        const names = opts.numberOf ? list.map(opts.numberOf).join(', ') : `${list.length} ${plural}`;
        if (!confirm(`${opts.combine.label}?\n\nA new draft is made from ${names}, with each item's quantities added together. They stay as they are.`)) return;
        const r = await opts.combine.run(list);
        if (!r || !r.ok) { alert((r && r.error) || 'They couldn’t be combined.'); return; }
        setSelecting(false);
        if (opts.combine.open) opts.combine.open(r.id);
      });
    }

    $('.sel-export').addEventListener('click', () => {
      const list = chosen();
      if (list.length === 0) return;
      const m = exportModal();
      m.querySelector('.sel-modal-title').textContent = `Export ${list.length} ${list.length === 1 ? opts.noun : plural} as one PDF`;
      m.querySelector('.sel-modal-summary').textContent = opts.numberOf ? list.map(opts.numberOf).join(', ') : '';
      m.querySelector('.sel-drawings-row').classList.toggle('hidden', !opts.drawings);
      m.querySelector('.sel-drawings-label').textContent = opts.drawingsLabel || 'Include each one’s drawings after it';
      m.querySelector('.sel-drawings').checked = false;
      const go = m.querySelector('.sel-go');
      go.onclick = async () => {
        go.disabled = true;
        go.textContent = 'Making PDF…';
        const r = await window.api.files.combinePDF(opts.kind, list, opts.drawings && m.querySelector('.sel-drawings').checked);
        go.disabled = false;
        go.textContent = 'Export PDF';
        m.classList.add('hidden');
        if (!r || !r.ok) alert((r && r.error) || 'The PDF couldn’t be made.');
      };
      m.classList.remove('hidden');
    });

    return {
      headerCell: () => '<th class="check-col"></th>',
      footerCell: () => '<td class="check-col"></td>',
      cell: (id) => `<td class="check-col"><input type="checkbox" class="doc-select" data-id="${String(id).replace(/"/g, '&quot;')}" tabindex="-1" /></td>`,
      afterRender: update,
    };
  };
})();

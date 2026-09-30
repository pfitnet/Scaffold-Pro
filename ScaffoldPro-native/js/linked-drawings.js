'use strict';

// The drawings a BOQ or quotation is based on, shown inside its editor:
// open them, or upload a new drawing (PDF, DWG, DXF or image) already
// linked to this document. A quotation that follows a BOQ has the BOQ's
// drawings too. Image and PDF drawings are added, in this order, after the
// document's own pages when it's exported as a PDF or printed.
//
//   window.setupLinkedDrawings({ kind: 'BOQ' | 'Quotation', id, projectNumber })
//
// Needs an element with id="linked-drawings" and a button with
// id="upload-linked-drawing-btn" on the page. Drawings can also be dragged
// onto the panel (js/file-drop.js).

(function () {
  function esc(value) {
    return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  window.setupLinkedDrawings = function setupLinkedDrawings(options) {
    const container = document.getElementById('linked-drawings');
    const button = document.getElementById('upload-linked-drawing-btn');
    if (!container || !button) return;

    async function refresh() {
      const drawings = await window.api.drawings.listForDocument(options.kind, options.id);
      if (drawings.length === 0) {
        container.innerHTML = `<p class="small-note">No drawings linked to this ${options.kind === 'BOQ' ? 'BOQ' : 'quotation'} yet. Upload one here or drag the files onto this box, or link an existing drawing from the project's Drawings &amp; Documents tab.</p>`;
        return;
      }
      const appended = drawings.filter((d) => d.appended).length;
      const note = appended
        ? `<p class="small-note">${appended === drawings.length ? 'These drawings are' : `The ${appended} marked “PDF page” are`} added after the ${options.kind === 'BOQ' ? 'BOQ' : 'quotation'}’s own pages, in this order, when it’s exported as a PDF or printed.</p>`
        : '';
      container.innerHTML = note + `<table class="compact"><tbody>${drawings.map((d, i) => `
        <tr>
          <td class="muted">${i + 1}</td>
          <td>${esc(d.storedFilename || d.originalName)}${d.fileExists ? '' : ' <span class="status-pill pill-danger">File unavailable</span>'}
            ${d.fromBOQNumber ? ` <span class="status-pill" title="A drawing of the BOQ this quotation follows">From ${esc(d.fromBOQNumber)}</span>` : ''}
            ${d.appended && appended !== drawings.length ? ' <span class="status-pill">PDF page</span>' : ''}
            ${d.description ? `<div class="sub">${esc(d.description)}</div>` : ''}</td>
          <td class="muted">${esc(d.fileType)}</td>
          <td class="row-actions">${d.boqId
            ? `<button data-open-boq="${d.boqId}">Open BOQ</button> <button data-locate-boq="${d.boqId}" title="Show the BOQ's exported PDF in Finder">Locate File</button>`
            : d.fileExists ? `<button data-open="${d.id}">Open</button> <button data-reveal="${d.id}" title="Show this file in Finder">Locate File</button>` : ''}</td>
        </tr>`).join('')}</tbody></table>`;
      for (const b of container.querySelectorAll('[data-open]')) {
        b.addEventListener('click', async () => {
          const r = await window.api.drawings.open(b.dataset.open);
          if (!r.ok) alert(r.error);
        });
      }
      for (const b of container.querySelectorAll('[data-open-boq]')) {
        b.addEventListener('click', () => { location.href = `boq-editor.html?id=${encodeURIComponent(b.dataset.openBoq)}`; });
      }
      for (const b of container.querySelectorAll('[data-locate-boq]')) {
        b.addEventListener('click', async () => {
          const r = await window.api.files.locateDocument('BOQ', b.dataset.locateBoq);
          if (!r || !r.ok) alert((r && r.error) || 'The file couldn’t be shown in Finder.');
          else if (r.note) alert(r.note);
        });
      }
      for (const b of container.querySelectorAll('[data-reveal]')) {
        b.addEventListener('click', async () => {
          const r = await window.api.drawings.reveal(b.dataset.reveal);
          if (!r.ok) alert(r.error);
        });
      }
    }

    // Drawings dragged from Finder onto the panel are added the same way.
    if (window.fileDrop) {
      window.fileDrop(container.closest('.linked-drawings-panel') || container, {
        projectNumber: options.projectNumber, target: 'drawing',
        options: () => ({ linkedKind: options.kind, linkedId: options.id }),
        done: refresh,
        hint: 'Drop drawings here',
        hintSub: 'PDF, DWG, DXF or images — dragged from Finder. They’re linked to this ' + (options.kind === 'BOQ' ? 'BOQ' : 'quotation') + '.',
      });
    }

    button.addEventListener('click', async () => {
      try {
        await window.api.projects.uploadDrawing(options.projectNumber, { linkedKind: options.kind, linkedId: options.id });
      } catch (e) {
        alert(`Not every drawing could be added.\n\n${e.message}`);
      }
      await refresh();
    });
    refresh();
  };
})();

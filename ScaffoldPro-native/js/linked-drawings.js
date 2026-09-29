'use strict';

// The drawings a BOQ or quotation is based on, shown inside its editor:
// open them, or upload a new drawing (PDF, DWG, DXF or image) already
// linked to this document.
//
//   window.setupLinkedDrawings({ kind: 'BOQ' | 'Quotation', id, projectNumber })
//
// Needs an element with id="linked-drawings" and a button with
// id="upload-linked-drawing-btn" on the page.

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
        container.innerHTML = `<p class="small-note">No drawings linked to this ${options.kind === 'BOQ' ? 'BOQ' : 'quotation'} yet. Upload one here, or link an existing drawing from the project's Drawings &amp; Documents tab.</p>`;
        return;
      }
      container.innerHTML = `<table class="compact"><tbody>${drawings.map((d) => `
        <tr>
          <td>${esc(d.storedFilename || d.originalName)}${d.fileExists ? '' : ' <span class="status-pill pill-danger">File unavailable</span>'}
            ${d.description ? `<div class="sub">${esc(d.description)}</div>` : ''}</td>
          <td class="muted">${esc(d.fileType)}</td>
          <td class="row-actions">${d.fileExists ? `<button data-open="${d.id}">Open</button> <button data-reveal="${d.id}" title="Show this file in Finder">Locate File</button>` : ''}</td>
        </tr>`).join('')}</tbody></table>`;
      for (const b of container.querySelectorAll('[data-open]')) {
        b.addEventListener('click', async () => {
          const r = await window.api.drawings.open(b.dataset.open);
          if (!r.ok) alert(r.error);
        });
      }
      for (const b of container.querySelectorAll('[data-reveal]')) {
        b.addEventListener('click', async () => {
          const r = await window.api.drawings.reveal(b.dataset.reveal);
          if (!r.ok) alert(r.error);
        });
      }
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

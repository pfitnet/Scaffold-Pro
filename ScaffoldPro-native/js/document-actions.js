'use strict';

// "Locate File" and "Delete…" for a BOQ, quotation, invoice or delivery note —
// in its editor's toolbar (#locate-file-btn, #delete-doc-btn) and in the
// project's document lists (window.documentRowActions).
//
// Deleting a draft asks once. Deleting an issued document asks twice: it
// has usually been sent to the client, so its number has to be typed in.
// Exported PDF and Word files stay in the project folder.

(function () {
  const LABELS = { BOQ: 'BOQ', Quotation: 'quotation', Invoice: 'invoice', DeliveryNote: 'delivery note' };
  const API = { BOQ: 'boq', Quotation: 'quotations', Invoice: 'invoices', DeliveryNote: 'deliveryNotes' };

  window.locateDocumentFile = async function (kind, id) {
    const r = await window.api.files.locateDocument(kind, id);
    if (!r || !r.ok) alert((r && r.error) || 'The file couldn’t be shown in Finder.');
    else if (r.note) alert(r.note);
  };

  /** Asks, deletes, and resolves to true once it's gone. */
  window.deleteDocument = async function (kind, id, number, status) {
    const label = LABELS[kind] || 'document';
    const issued = status && status !== 'Draft';
    if (!issued) {
      if (!confirm(`Delete ${label} ${number}? This can’t be undone.`)) return false;
    } else {
      if (!confirm(`${number} is ${status}. Deleting it removes the ${label} from ScaffoldPro for good` +
        `${kind === 'Invoice' ? ', with its payments in Accounts' : kind === 'DeliveryNote' ? ', and its items go back into the stock list' : ''}.` +
        ' Any PDF or Word file already saved stays in the project folder.\n\nContinue?')) return false;
      const typed = prompt(`To delete it, type its number: ${number}`);
      if (typed === null) return false;
      if (typed.trim() !== number) {
        alert('The number didn’t match, so nothing was deleted.');
        return false;
      }
    }
    const r = await window.api[API[kind]].remove(id, issued);
    if (!r || !r.ok) {
      alert((r && r.error) || 'It couldn’t be deleted.');
      return false;
    }
    return true;
  };

  /**
   * Wires the editor's toolbar buttons.
   * @param kind 'BOQ' | 'Quotation' | 'Invoice' | 'DeliveryNote'
   * @param get  () => ({ id, number, status, projectNumber })
   */
  window.setupDocumentActions = function (kind, get) {
    const locate = document.getElementById('locate-file-btn');
    if (locate) locate.addEventListener('click', () => window.locateDocumentFile(kind, get().id));
    const del = document.getElementById('delete-doc-btn');
    if (del) del.addEventListener('click', async () => {
      const d = get();
      if (await window.deleteDocument(kind, d.id, d.number, d.status)) {
        location.href = `project-detail.html?number=${encodeURIComponent(d.projectNumber)}`;
      }
    });
  };

  /** "Locate File" and "Delete…" buttons for a row of a document list. */
  window.documentRowActions = function (kind, doc, refresh) {
    const cell = document.createElement('td');
    cell.className = 'row-actions';
    cell.innerHTML = '<button class="locate-btn" title="Show this document’s file in Finder">Locate File</button> ' +
      '<button class="delete-btn">Delete…</button>';
    cell.addEventListener('click', (e) => e.stopPropagation());
    cell.querySelector('.locate-btn').addEventListener('click', () => window.locateDocumentFile(kind, doc.id));
    cell.querySelector('.delete-btn').addEventListener('click', async () => {
      if (await window.deleteDocument(kind, doc.id, doc.number, doc.status)) await refresh();
    });
    return cell;
  };
})();

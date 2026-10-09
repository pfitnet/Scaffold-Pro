'use strict';

// "Locate File" and "Delete…" for a BOQ, quotation, invoice or delivery note
// (and "Duplicate…" for a quotation) —
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
      if (!await appConfirm(`Delete ${label} ${number}? This can’t be undone.`)) return false;
    } else {
      if (!await appConfirm(`${number} is ${status}. Deleting it removes the ${label} from ScaffoldPro for good` +
        `${kind === 'Invoice' ? ', with its payments in Accounting' : kind === 'DeliveryNote' ? ', and its items go back into the stock list' : ''}.` +
        ' Any PDF or Word file already saved stays in the project folder.\n\nContinue?', { danger: true, ok: 'Continue' })) return false;
      const typed = await window.appPrompt(`Delete ${number}\n\nTo delete it, type its number: ${number}`, '', { ok: 'Delete', placeholder: number });
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

  /** A quotation copied as a new draft, here or in another project; opens it. */
  window.duplicateQuotation = async function (id, number, projectId) {
    const projects = ((await window.api.projects.list()) || []).filter((p) => p.status !== 'Archived' && p.id !== projectId);
    const pick = await appChoose(`Duplicate ${number}\n\nA copy as a new draft, with its items, sections and delivery schedule. Where should it go?`, [
      ...(projects.length ? [{ label: 'Another Project', menu: projects.map((p) => ({ label: `${p.projectNumber} — ${p.name}`, value: { project: p.id } })) }] : []),
      { label: 'This Project', value: 'here', primary: true }]);
    if (!pick) return false;
    const r = await window.api.quotations.duplicate(id, pick === 'here' ? null : pick.project);
    if (!r || !r.ok) { alert((r && r.error) || 'It couldn’t be duplicated.'); return false; }
    window.goTo(`quotation-editor.html?id=${encodeURIComponent(r.id)}`);
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
    const dup = document.getElementById('duplicate-doc-btn');
    if (dup && kind === 'Quotation') dup.addEventListener('click', () => { const d = get(); window.duplicateQuotation(d.id, d.number, d.projectId); });
    const del = document.getElementById('delete-doc-btn');
    if (del) del.addEventListener('click', async () => {
      const d = get();
      if (await window.deleteDocument(kind, d.id, d.number, d.status)) {
        window.goTo(`project-detail.html?number=${encodeURIComponent(d.projectNumber)}`);
      }
    });
  };

  /** "Locate File" and "Delete…" buttons for a row of a document list. */
  window.documentRowActions = function (kind, doc, refresh) {
    const cell = document.createElement('td');
    cell.className = 'row-actions';
    cell.innerHTML = '<button class="locate-btn" title="Show this document’s file in Finder">Locate File</button> ' +
      (kind === 'Quotation' ? '<button class="dup-btn" title="A copy as a new draft, here or in another project">Duplicate…</button> ' : '') +
      '<button class="delete-btn">Delete…</button>';
    cell.addEventListener('click', (e) => e.stopPropagation());
    cell.querySelector('.locate-btn').addEventListener('click', () => window.locateDocumentFile(kind, doc.id));
    const dup = cell.querySelector('.dup-btn');
    if (dup) dup.addEventListener('click', () => window.duplicateQuotation(doc.id, doc.number, doc.projectId));
    cell.querySelector('.delete-btn').addEventListener('click', async () => {
      if (await window.deleteDocument(kind, doc.id, doc.number, doc.status)) await refresh();
    });
    return cell;
  };
})();

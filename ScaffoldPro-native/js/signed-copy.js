'use strict';

// Signed copies of quotations. The client signs the quotation and sends it
// back; the copy (a PDF, or a photo or scan) is kept in the project's
// Quotations folder as "<number> - Signed.pdf". Used by the Dashboard's
// reminder list and the quotation editor. A file can be chosen with the
// button, or dropped onto the row or bar.

(function () {
  const EXTENSIONS = ['pdf', 'jpg', 'jpeg', 'png', 'heic', 'tif', 'tiff'];
  const MAX_BYTES = 60 * 1024 * 1024;

  function base64Of(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result).replace(/^data:[^,]*,/, ''));
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(file);
    });
  }

  function report(r) {
    if (r === null || r === undefined) return false; // the file panel was cancelled
    if (!r.ok) {
      alert(r.error || 'The signed copy couldn’t be saved.');
      return false;
    }
    return true;
  }

  // The same for a quotation (the client's signed copy) or a delivery note
  // (signed on site): window.signedCopy is the quotations' one.
  function make(kind) {
  const api = () => (kind === 'deliveryNote' ? window.api.deliveryNotes : window.api.quotations);
  const noun = kind === 'deliveryNote' ? 'delivery note' : 'quotation';
  const folder = kind === 'deliveryNote' ? 'Delivery Notes' : 'Quotations';
  return {
    /** Choose the file in a panel. Resolves to true once it's saved. */
    async upload(id) {
      return report(await api().uploadSigned(id));
    },

    /** A file dropped onto the page. */
    async fromFile(id, file) {
      const ext = (file.name.split('.').pop() || '').toLowerCase();
      if (!EXTENSIONS.includes(ext)) {
        alert(`Use a PDF, or a photo or scan (JPEG, PNG, HEIC or TIFF), of the signed ${noun}.`);
        return false;
      }
      if (file.size > MAX_BYTES) {
        alert('That file is very large. Use “Upload Signed Copy…” to choose it instead.');
        return false;
      }
      return report(await api().saveSignedFile(id, file.name, await base64Of(file)));
    },

    async open(id) {
      const r = await api().signedCopy(id, 'open');
      if (r && !r.ok) alert(r.error);
    },

    async reveal(id) {
      const r = await api().signedCopy(id, 'reveal');
      if (r && !r.ok) alert(r.error);
    },

    /** Forgets the signed copy; the file itself stays in the folder. */
    async remove(id, number) {
      const after = kind === 'deliveryNote' ? `it's no longer added after its invoice, and its items go back into the yard` : `${number} goes back on the Dashboard’s list of quotations waiting for a signed copy`;
      if (!await appConfirm(`Remove the signed copy from ${number}?\n\nThe file stays in the project’s ${folder} folder; ${after}.`)) return false;
      return report(await api().signedCopy(id, 'remove'));
    },

    /** Takes it off (or puts it back on) the Dashboard's reminder. */
    /** The client agreed without signing (by email, phone…): won in Marketing. */
    async setAgreed(id, agreed) {
      return report(await window.api.quotations.setClientAgreed(id, agreed));
    },

    async setNotNeeded(id, notNeeded) {
      return report(await window.api.quotations.setSignedNotNeeded(id, notNeeded));
    },

    /** Lets a file be dropped onto `el` for quotation `id`; then calls `done`. */
    dropTarget(el, id, done) {
      let depth = 0;
      el.addEventListener('dragenter', (e) => {
        if (!e.dataTransfer || ![...e.dataTransfer.types].includes('Files')) return;
        e.preventDefault();
        depth += 1;
        el.classList.add('drop-over');
      });
      el.addEventListener('dragover', (e) => {
        if (!e.dataTransfer || ![...e.dataTransfer.types].includes('Files')) return;
        e.preventDefault();
        e.dataTransfer.dropEffect = 'copy';
      });
      el.addEventListener('dragleave', () => {
        depth = Math.max(0, depth - 1);
        if (depth === 0) el.classList.remove('drop-over');
      });
      el.addEventListener('drop', async (e) => {
        e.preventDefault();
        e.stopPropagation();
        depth = 0;
        el.classList.remove('drop-over');
        const file = e.dataTransfer && e.dataTransfer.files && e.dataTransfer.files[0];
        if (!file) return;
        el.classList.add('drop-saving');
        const ok = await this.fromFile(id, file);
        el.classList.remove('drop-saving');
        if (ok && done) await done();
      });
    },
  };
  }
  window.signedCopy = make('quotation');
  window.signedCopyFor = make;

  // A file dropped anywhere else would open in place of the app's page.
  window.addEventListener('dragover', (e) => e.preventDefault());
  window.addEventListener('drop', (e) => e.preventDefault());
})();

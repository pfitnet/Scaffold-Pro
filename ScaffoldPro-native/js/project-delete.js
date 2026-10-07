'use strict';

// Deleting a project (js/projects.js, js/project-detail.js):
//   const deleted = await window.deleteProject({ id, projectNumber, name })
// An empty project is deleted after a plain "are you sure". One holding
// anything — documents, drawings, files — is behind a wall: what will go is
// listed, and the project's name must be typed before Delete works.

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const KINDS = [['quotations', 'quotation'], ['boqs', 'BOQ'], ['deliveryNotes', 'delivery note'], ['invoices', 'invoice'], ['letters', 'letter'],
    ['drawings', 'drawing'], ['documents', 'document'], ['inspections', 'inspection'], ['payments', 'payment record']];
  const plural = (n, one) => `${n} ${one}${n === 1 ? '' : (one.endsWith('s') ? 'es' : 's')}`;

  function wall(c) {
    return new Promise((resolve) => {
      const el = document.createElement('div');
      el.className = 'modal-backdrop pd-del-backdrop';
      const items = KINDS.filter(([k]) => c[k] > 0).map(([k, one]) => `<li><b>${c[k]}</b> ${esc(plural(c[k], one).replace(/^\d+ /, ''))}</li>`).join('');
      el.innerHTML = `
        <div class="modal pd-del" role="alertdialog" aria-labelledby="pd-del-title">
          <div class="pd-del-icon" aria-hidden="true"><svg viewBox="0 0 24 24" width="26" height="26" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"><path d="M12 9v4M12 17h.01"/><path d="M10.3 3.9 1.8 18a2 2 0 0 0 1.7 3h17a2 2 0 0 0 1.7-3L13.7 3.9a2 2 0 0 0-3.4 0z"/></svg></div>
          <h2 id="pd-del-title">Delete ${esc(c.projectNumber)} — ${esc(c.name)}?</h2>
          <p>This project isn’t empty. Everything in it is deleted with it:</p>
          <ul class="pd-del-list">${items}</ul>
          <p class="small-note">Its folder (with the PDFs, drawings and files) goes to the Trash, so it can still be put back from there. Tasks and expenses stay, without the project.</p>
          <label class="pd-del-label" for="pd-del-input">Type <b>${esc(c.name)}</b> to confirm</label>
          <input type="text" id="pd-del-input" autocomplete="off" spellcheck="false" placeholder="${esc(c.name)}" />
          <div class="error-text hidden" id="pd-del-error"></div>
          <div class="actions">
            <button type="button" id="pd-del-cancel">Cancel</button>
            <button type="button" class="danger" id="pd-del-go" disabled>Delete Project</button>
          </div>
        </div>`;
      document.body.appendChild(el);
      const input = el.querySelector('#pd-del-input');
      const go = el.querySelector('#pd-del-go');
      const norm = (v) => String(v || '').trim().toLowerCase();
      const matches = () => norm(input.value) === norm(c.name) || norm(input.value) === norm(c.projectNumber);
      const close = (v) => { el.remove(); document.removeEventListener('keydown', onKey, true); resolve(v); };
      const onKey = (e) => {
        if (e.key === 'Escape') { e.preventDefault(); close(null); }
        if (e.key === 'Enter' && document.activeElement === input) {
          e.preventDefault();
          if (matches()) close(input.value);
          else { const m = el.querySelector('.pd-del'); m.classList.remove('shake'); void m.offsetWidth; m.classList.add('shake'); }
        }
      };
      input.addEventListener('input', () => { go.disabled = !matches(); el.querySelector('.pd-del').classList.toggle('armed', matches()); });
      go.addEventListener('click', () => { if (matches()) close(input.value); });
      el.querySelector('#pd-del-cancel').addEventListener('click', () => close(null));
      document.addEventListener('keydown', onKey, true);
      setTimeout(() => input.focus(), 30);
    });
  }

  window.deleteProject = async function deleteProject(p) {
    const c = await window.api.projects.contents(p.id);
    if (!c || c.ok === false) { await window.appAlert((c && c.error) || 'The project couldn’t be found.'); return false; }
    let confirm = null;
    if (c.isEmpty) {
      if (!await window.appConfirm(`Delete ${c.projectNumber} — ${c.name}?\n\nIt has nothing in it yet. Its folder goes to the Trash.`, { ok: 'Delete Project', danger: true })) return false;
    } else {
      confirm = await wall(c);
      if (confirm === null) return false;
    }
    const r = await window.api.projects.remove(p.id, confirm);
    if (!r || r.ok === false) { await window.appAlert((r && r.error) || 'The project couldn’t be deleted.'); return false; }
    return true;
  };
})();

'use strict';

// "Send to Sign…": ask a director (someone marked on the Team page as
// signing quotations) to sign and chop a quotation, with a note.
//
//   const sent = await window.askToSign(quotationId, quotationNumber);

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  function sheet() {
    let el = document.getElementById('sign-modal');
    if (el) return el;
    el = document.createElement('div');
    el.className = 'modal-backdrop hidden';
    el.id = 'sign-modal';
    el.innerHTML = `
      <div class="modal" role="dialog" aria-labelledby="sr-title">
        <h2 id="sr-title">Send to Sign</h2>
        <p class="small-note" id="sr-about"></p>
        <div class="field"><label>Who signs</label><div class="choice-cards" id="sr-signers"></div></div>
        <div class="field"><label for="sr-note">Note <span class="field-hint" style="display:inline">(optional)</span></label>
          <textarea id="sr-note" rows="3" placeholder="e.g. Client needs it back today"></textarea></div>
        <div class="error-text hidden" id="sr-error"></div>
        <div class="actions"><button id="sr-cancel">Cancel</button><button class="primary" id="sr-send">Send</button></div>
      </div>`;
    document.body.appendChild(el);
    return el;
  }

  window.askToSign = async function askToSign(quotationId, number) {
    const page = await window.api.signatures.page();
    const signers = (page && page.signers) || [];
    if (!signers.length) {
      await window.appAlert('No one signs quotations yet.\n\nOn the Team page, press ✎ on a director and tick “Signs and chops quotations”.');
      return false;
    }
    const el = sheet();
    const $ = (id) => el.querySelector(`#${id}`);
    $('sr-title').textContent = `Send ${number} to Sign`;
    $('sr-about').textContent = 'They’re told on their Dashboard. Once they’ve signed and chopped it, the signed PDF is saved in the project’s Quotations folder and you’re told.';
    $('sr-signers').innerHTML = signers.map((n, i) => `<label class="choice-card"><input type="radio" name="sr-signer" value="${esc(n)}" ${i === 0 ? 'checked' : ''} /><span>${window.personTag ? window.personTag(n) : esc(n)}</span></label>`).join('');
    $('sr-note').value = '';
    $('sr-error').classList.add('hidden');
    el.classList.remove('hidden');
    return new Promise((resolve) => {
      const close = (v) => {
        el.classList.add('hidden');
        $('sr-send').removeEventListener('click', send);
        $('sr-cancel').removeEventListener('click', cancel);
        el.removeEventListener('keydown', onKey);
        resolve(v);
      };
      const send = async () => {
        const chosen = el.querySelector('input[name="sr-signer"]:checked');
        const r = await window.api.signatures.request(quotationId, chosen ? chosen.value : '', $('sr-note').value.trim());
        if (!r || r.ok === false) {
          $('sr-error').textContent = (r && r.error) || 'It couldn’t be sent.';
          $('sr-error').classList.remove('hidden');
          return;
        }
        close(true);
      };
      const cancel = () => close(false);
      const onKey = (e) => { if (e.key === 'Escape') close(false); };
      $('sr-send').addEventListener('click', send);
      $('sr-cancel').addEventListener('click', cancel);
      el.addEventListener('keydown', onKey);
    });
  };
})();

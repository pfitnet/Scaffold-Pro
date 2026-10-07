'use strict';

// Settings › AI Import: which free cloud AI reads quotations the app can't
// make out itself, and its key (kept in this Mac's Keychain).

(function () {
  const $ = (id) => document.getElementById(id);
  if (!$('ai-import')) return;
  const HELP = {
    gemini: 'Sign in at Google AI Studio and press <b>Create API key</b>. It’s free; no card is needed.',
    openrouter: 'Sign up at OpenRouter, then <b>Settings › Keys › Create Key</b>. Free models cost nothing.',
  };
  const NAMES = { gemini: 'Google Gemini', openrouter: 'OpenRouter' };
  let status = null;

  const chosen = () => (document.querySelector('input[name="ai-provider"]:checked') || {}).value || 'gemini';

  function draw() {
    const p = chosen();
    $('ai-key-help').innerHTML = `${HELP[p]} <button type="button" class="link-btn" id="ai-get-key" data-no-icon>Open the page</button>`;
    $('ai-get-key').addEventListener('click', () => window.api.ai.openKeyPage(chosen()));
    const same = status && status.provider === p;
    $('ai-model').placeholder = p === 'gemini' ? 'gemini-2.5-flash' : 'openrouter/free';
    $('ai-key').placeholder = same && status.hasKey ? 'Saved — paste a new key to replace it' : 'Paste the key';
    $('ai-remove').classList.toggle('hidden', !(same && status.hasKey));
    const on = status && status.hasKey;
    $('ai-state').className = `ai-state${on ? ' on' : ''}`;
    $('ai-state').innerHTML = `<span class="dot"></span><span>${on
      ? `Ready — <b>${NAMES[status.provider]}</b> reads what the app can’t (${status.model || status.defaultModel}).`
      : 'Not set up. Imports are read on this Mac only.'}</span>`;
  }

  async function load() {
    status = await window.api.ai.status();
    const radio = document.querySelector(`input[name="ai-provider"][value="${status.provider}"]`);
    if (radio) radio.checked = true;
    $('ai-model').value = status.model || '';
    draw();
  }

  async function save(removeKey) {
    status = await window.api.ai.configure({ provider: chosen(), model: $('ai-model').value.trim(), key: $('ai-key').value.trim(), removeKey: !!removeKey });
    $('ai-key').value = '';
    $('ai-saved').textContent = removeKey ? 'Key removed.' : status.hasKey ? 'Saved.' : 'Saved — add a key to use it.';
    setTimeout(() => { $('ai-saved').textContent = ''; }, 3000);
    draw();
  }

  for (const r of document.querySelectorAll('input[name="ai-provider"]')) r.addEventListener('change', draw);
  $('ai-save').addEventListener('click', () => save(false));
  $('ai-remove').addEventListener('click', async () => {
    if (await window.appConfirm('Remove the AI key from this Mac?')) save(true);
  });
  $('ai-key').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); save(false); } });
  load();
})();

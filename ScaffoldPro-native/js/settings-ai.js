'use strict';

// Settings › AI Import: which free cloud AI reads quotations the app can't
// make out itself, its model and key: the whole team's, kept with the
// company's settings (the key never comes back to the page).

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
    const on = !!(status && status.hasKey);
    // Once a key is saved, the setup is closed: only Remove Key, until it's gone.
    $('ai-steps').classList.toggle('hidden', on);
    $('ai-state').className = `ai-state${on ? ' on' : ''}`;
    $('ai-state').innerHTML = on
      ? `<span class="dot"></span><span>Ready — <b>${NAMES[status.provider]}</b> reads what the app can’t (${status.model || status.defaultModel}).
          <small>Used on every Mac. To use another key, provider or model, remove this key first.</small></span>
          <button type="button" class="danger-btn" id="ai-remove" data-no-icon>Remove Key</button>`
      : '<span class="dot"></span><span>Not set up. Imports are read on each Mac only.</span>';
    const remove = $('ai-remove');
    if (remove) remove.addEventListener('click', async () => {
      if (await window.appConfirm('Remove the AI key for the whole team? Imports are then read on each Mac only until a key is added again.')) save(true);
    });
    if (on) return;
    $('ai-key-help').innerHTML = `${HELP[p]} <button type="button" class="link-btn" id="ai-get-key" data-no-icon>Open the page</button>`;
    $('ai-get-key').addEventListener('click', () => window.api.ai.openKeyPage(chosen()));
    $('ai-model').placeholder = p === 'gemini' ? 'gemini-2.5-flash' : 'openrouter/free';
  }

  async function load() {
    status = await window.api.ai.status();
    const radio = document.querySelector(`input[name="ai-provider"][value="${status.provider}"]`);
    if (radio) radio.checked = true;
    $('ai-model').value = status.model || '';
    draw();
  }

  async function save(removeKey) {
    const key = $('ai-key').value.trim();
    if (!removeKey && !key) { $('ai-saved').textContent = 'Paste the key first.'; return; }
    status = await window.api.ai.configure({ provider: chosen(), model: $('ai-model').value.trim(), key: removeKey ? '' : key, removeKey: !!removeKey });
    $('ai-key').value = '';
    $('ai-saved').textContent = removeKey ? 'Key removed.' : '';
    setTimeout(() => { $('ai-saved').textContent = ''; }, 3000);
    draw();
  }

  for (const r of document.querySelectorAll('input[name="ai-provider"]')) r.addEventListener('change', draw);
  $('ai-save').addEventListener('click', () => save(false));
  $('ai-key').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); save(false); } });
  load();
})();

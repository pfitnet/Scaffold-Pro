'use strict';

// Settings › What's New: the change log, as written in the README (one
// entry per change, "## Batch N — Title" and its lines in plain words),
// newest first. The first few open; the rest show their titles until
// clicked. Bullets ("- ") and their run-on lines become a list;
// `code` and **bold** are kept.

(function () {
  const list = document.getElementById('changelog-list');
  if (!list || !window.api || !window.api.updates || !window.api.updates.changelog) return;
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const inline = (t) => esc(t).replace(/\*\*([^*]+)\*\*/g, '<b>$1</b>').replace(/`([^`]+)`/g, '<code>$1</code>');

  // "- a\n  b\n- c" → <ul><li>a b</li><li>c</li></ul>; other lines are paragraphs.
  function body(text) {
    const items = [];
    for (const raw of String(text || '').split('\n')) {
      const line = raw.trim();
      if (!line) continue;
      if (/^[-*] /.test(line)) items.push({ li: true, text: line.slice(2) });
      else if (items.length && items[items.length - 1].li && /^\s/.test(raw)) items[items.length - 1].text += ` ${line}`;
      else items.push({ li: false, text: line });
    }
    let html = '';
    let open = false;
    for (const it of items) {
      if (it.li && !open) { html += '<ul>'; open = true; }
      if (!it.li && open) { html += '</ul>'; open = false; }
      html += it.li ? `<li>${inline(it.text)}</li>` : `<p>${inline(it.text)}</p>`;
    }
    return open ? `${html}</ul>` : html;
  }

  async function show() {
    let entries = [];
    try { entries = (await window.api.updates.changelog()) || []; } catch (e) { entries = []; }
    if (!entries.length) {
      list.innerHTML = '<p class="small-note">The change log comes with the next update.</p>';
      return;
    }
    list.innerHTML = entries.map((e, i) => `<details class="cl-entry st-card"${i < 3 ? ' open' : ''}>
        <summary><span class="cl-batch">${esc(e.batch)}</span><span class="cl-title">${inline(e.title)}</span></summary>
        <div class="cl-body">${body(e.text)}</div></details>`).join('');
  }
  show();
})();

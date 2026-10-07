'use strict';

// Terms as a table (Settings' standard terms, a quotation's key terms, an
// invoice's terms, a BOQ's terms): one row per term, its label on the left
// ("Payment", "Delivery", "Insurance" — set, with a pencil to change it)
// and what it says on the right; and paragraph rows across the whole width
// for text that isn't a labelled term. "+ Add term" and "+ Add paragraph"
// below; on hovering a row, move it up or down or remove it.
//
// The table keeps the box's text as before ("Payment : text", lines under
// it set in; paragraphs between blank lines), which is what main.swift's
// formattedParagraphs prints, so the PDFs don't change. The box itself is
// hidden; setting its value (as the pages do) redraws the table, and edits
// in the table fire the box's input and change events (which save it).
//
//   window.attachTermsTable(textarea, { fallback })   — fallback(): the
//     standard terms shown (greyed) while this box is left blank

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

  // "Payment : text", "Deposit: text", "Label<Tab>text" → { label, text }
  function labelOf(line) {
    const t = line.trim();
    const tab = t.indexOf('\t');
    if (tab > 0 && t.slice(0, tab).trim().endsWith(':')) return { label: t.slice(0, tab).trim().slice(0, -1).trim(), text: t.slice(tab + 1).trim() };
    const colon = t.indexOf(':');
    if (colon < 0) return null;
    const label = t.slice(0, colon).trim();
    const after = t.slice(colon + 1);
    if (!label || label.length > 40 || label.split(/ +/).length > 5) return null;
    if (after && after[0] !== ' ' && after[0] !== '\t') return null;
    if (/http|www\./i.test(label)) return null;
    return { label, text: after.trim() };
  }

  // Text → rows: [{ kind: 'term', label, value } | { kind: 'para', text }]
  function parse(text) {
    const rows = [];
    let term = null;
    let para = null;
    const end = () => { term = null; if (para) { rows.push(para); para = null; } };
    for (const raw of String(text || '').replace(/\r\n/g, '\n').split('\n')) {
      if (!raw.trim()) { end(); continue; }
      const indented = /^[ \t]/.test(raw);
      const label = indented ? null : labelOf(raw);
      if (label) {
        end();
        term = { kind: 'term', label: label.label, value: label.text };
        rows.push(term);
      } else if (term) {
        term.value += (term.value ? '\n' : '') + raw.replace(/^ {1,4}|^\t/, '');
      } else {
        if (!para) para = { kind: 'para', text: '' };
        para.text += (para.text ? '\n' : '') + raw;
      }
    }
    end();
    return rows;
  }

  // Rows → text: terms one after another; a paragraph between blank lines.
  function serialize(rows) {
    const out = [];
    rows.forEach((r, i) => {
      if (r.kind === 'term') {
        const label = r.label.trim();
        if (!label && !r.value.trim()) return;
        const lines = r.value.replace(/\r\n/g, '\n').split('\n');
        if (out.length && rows[i - 1] && rows[i - 1].kind === 'para') out.push('');
        out.push(`${label || 'Term'} : ${lines[0].trim()}`.trimEnd());
        // Its further lines set in under it (a blank one would end the term).
        for (const l of lines.slice(1)) if (l.trim()) out.push(`    ${l}`);
      } else {
        if (!r.text.trim()) return;
        if (out.length) out.push('');
        out.push(r.text.replace(/\s+$/, ''));
      }
    });
    // No blank lines inside a term's own value (they'd end it).
    return out.join('\n').replace(/\n{3,}/g, '\n\n');
  }

  const ICON = {
    pen: '<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10.5 2.5l3 3L6 13H3v-3z"/></svg>',
    up: '<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 10l4-4 4 4"/></svg>',
    down: '<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 6l4 4 4-4"/></svg>',
    x: '<svg viewBox="0 0 16 16" width="12" height="12" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" aria-hidden="true"><path d="M4.5 4.5l7 7M11.5 4.5l-7 7"/></svg>',
  };

  let styled = false;
  function addStyles() {
    if (styled) return;
    styled = true;
    const st = document.createElement('style');
    st.textContent = `
      .tt { border: 1px solid var(--border); border-radius: 12px; overflow: hidden; background: var(--panel); }
      .tt-rows { display: flex; flex-direction: column; }
      .tt-row { position: relative; display: grid; grid-template-columns: minmax(120px, 26%) 1fr; border-bottom: 1px solid var(--hairline); }
      .tt-row:last-child { border-bottom: none; }
      .tt-row.para { grid-template-columns: 1fr; }
      .tt-label { display: flex; align-items: flex-start; gap: 6px; padding: 9px 12px; background: color-mix(in srgb, var(--text) 3.5%, transparent);
        border-right: 1px solid var(--hairline); font-weight: 600; font-size: 13px; color: var(--text); min-width: 0; }
      .tt-label .tt-name { flex: 1; min-width: 0; padding-top: 1px; overflow-wrap: anywhere; }
      .tt-label .tt-name::after { content: ' :'; color: var(--text-tertiary); font-weight: 500; }
      .tt-label input { flex: 1; min-width: 0; height: 26px; padding: 2px 8px; font-weight: 600; font-size: 13px; }
      .tt-pen { opacity: 0; border: none; background: none; box-shadow: none; padding: 3px; height: auto; color: var(--text-tertiary); cursor: pointer; }
      .tt-row:hover .tt-pen, .tt-pen:focus-visible { opacity: 1; }
      .tt-value textarea { display: block; width: 100%; border: none; border-radius: 0; background: transparent; box-shadow: none; resize: none; overflow: hidden;
        padding: 9px 74px 9px 12px; min-height: 38px; font: inherit; font-size: 13px; line-height: 1.45; color: var(--text); }
      .tt-row.para .tt-value textarea { font-style: normal; color: var(--text); }
      .tt-value textarea:focus { outline: none; background: color-mix(in srgb, var(--accent) 5%, transparent); box-shadow: inset 2px 0 0 var(--accent); }
      .tt-row.para .tt-kind { position: absolute; left: 12px; top: -1px; font-size: 9.5px; letter-spacing: .06em; text-transform: uppercase; color: var(--text-tertiary); display: none; }
      .tt-tools { position: absolute; right: 6px; top: 6px; display: flex; gap: 2px; opacity: 0; transition: opacity .12s; }
      .tt-row:hover .tt-tools, .tt-row:focus-within .tt-tools { opacity: 1; }
      .tt-tools button { border: none; background: var(--panel); box-shadow: none; padding: 4px; height: auto; border-radius: 6px; color: var(--text-tertiary); cursor: pointer; }
      .tt-tools button:hover { color: var(--text); background: color-mix(in srgb, var(--text) 8%, var(--panel)); }
      .tt-tools button.tt-del:hover { color: var(--danger); }
      .tt-add { display: flex; gap: 6px; padding: 8px 10px; border-top: 1px dashed var(--border); background: color-mix(in srgb, var(--text) 2%, transparent); }
      .tt-add button { height: 28px; padding: 0 12px; font-size: 12.5px; }
      .tt-empty { padding: 14px 12px; color: var(--text-tertiary); font-size: 13px; }
      .tt.locked .tt-tools, .tt.locked .tt-add, .tt.locked .tt-pen { display: none; }
      .tt.fallback .tt-rows { opacity: .55; }
      .tt-fallback-bar { display: flex; align-items: center; gap: 10px; padding: 8px 12px; font-size: 12px; color: var(--text-secondary);
        background: color-mix(in srgb, var(--accent) 6%, transparent); border-bottom: 1px solid var(--hairline); }
      .tt-fallback-bar button { margin-left: auto; height: 26px; padding: 0 10px; font-size: 12px; }`;
    document.head.appendChild(st);
  }

  function grow(t) { t.style.height = 'auto'; t.style.height = `${t.scrollHeight}px`; }

  window.attachTermsTable = function attachTermsTable(ta, options) {
    if (!ta || ta.termsTable) return;
    addStyles();
    const box = document.createElement('div');
    box.className = 'tt';
    ta.after(box);
    ta.style.display = 'none';
    const own = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, 'value');
    let rows = parse(own.get.call(ta));
    let pending = false;   // a redraw waiting until the table is left
    const fallback = options && options.fallback;

    // The table's rows back into the box (input now, change when a field is left).
    const write = (commit) => {
      own.set.call(ta, serialize(rows));
      ta.dispatchEvent(new Event('input', { bubbles: true }));
      if (commit) ta.dispatchEvent(new Event('change', { bubbles: true }));
    };

    function render() {
      const locked = ta.disabled;
      const usingFallback = !rows.length && fallback && String(fallback() || '').trim();
      const shown = usingFallback ? parse(fallback()) : rows;
      box.className = `tt${locked ? ' locked' : ''}${usingFallback ? ' fallback' : ''}`;
      box.innerHTML = `${usingFallback ? `<div class="tt-fallback-bar">The standard terms from Settings are used.${locked ? '' : '<button type="button" data-no-icon data-act="own">Change them here</button>'}</div>` : ''}
        <div class="tt-rows">${shown.length ? shown.map((r, i) => r.kind === 'term'
          ? `<div class="tt-row" data-i="${i}">
              <div class="tt-label">${r.editing ? `<input type="text" value="${esc(r.label)}" placeholder="e.g. Payment" aria-label="Term">`
                : `<span class="tt-name">${esc(r.label)}</span><button type="button" class="tt-pen" data-no-icon data-act="pen" title="Rename this term">${ICON.pen}</button>`}</div>
              <div class="tt-value"><textarea rows="1" aria-label="${esc(r.label)}" placeholder="What it says" ${locked || usingFallback ? 'disabled' : ''}>${esc(r.value)}</textarea></div>
              ${tools()}</div>`
          : `<div class="tt-row para" data-i="${i}"><div class="tt-value"><textarea rows="1" aria-label="Paragraph" placeholder="A paragraph of terms" ${locked || usingFallback ? 'disabled' : ''}>${esc(r.text)}</textarea></div>${tools()}</div>`).join('')
          : '<div class="tt-empty">No terms yet.</div>'}</div>
        <div class="tt-add"${usingFallback ? ' hidden' : ''}><button type="button" data-no-icon data-act="add-term">+ Add term</button><button type="button" data-no-icon data-act="add-para">+ Add paragraph</button></div>`;
      box.querySelectorAll('textarea').forEach(grow);
    }
    const tools = () => `<div class="tt-tools"><button type="button" data-no-icon data-act="up" title="Move up">${ICON.up}</button><button type="button" data-no-icon data-act="down" title="Move down">${ICON.down}</button><button type="button" class="tt-del" data-no-icon data-act="del" title="Remove">${ICON.x}</button></div>`;

    const rowOf = (el) => { const r = el.closest('.tt-row'); return r ? Number(r.dataset.i) : -1; };
    const focusRow = (i, sel) => { const el = box.querySelector(`.tt-row[data-i="${i}"] ${sel || 'textarea'}`); if (el) { el.focus(); if (el.select && sel) el.select(); } };

    box.addEventListener('click', (e) => {
      const b = e.target.closest('button[data-act]');
      if (!b || ta.disabled) return;
      const act = b.dataset.act;
      const i = rowOf(b);
      if (act === 'own') { rows = parse(fallback()); write(true); render(); focusRow(0); return; }
      if (act === 'add-term') { rows.push({ kind: 'term', label: '', value: '', editing: true }); render(); focusRow(rows.length - 1, 'input'); return; }
      if (act === 'add-para') { rows.push({ kind: 'para', text: '' }); render(); focusRow(rows.length - 1); return; }
      if (act === 'pen') { rows[i].editing = true; render(); focusRow(i, 'input'); return; }
      if (act === 'del') { rows.splice(i, 1); write(true); render(); return; }
      if (act === 'up' && i > 0) { [rows[i - 1], rows[i]] = [rows[i], rows[i - 1]]; write(true); render(); focusRow(i - 1); return; }
      if (act === 'down' && i < rows.length - 1) { [rows[i + 1], rows[i]] = [rows[i], rows[i + 1]]; write(true); render(); focusRow(i + 1); }
    });
    box.addEventListener('input', (e) => {
      const i = rowOf(e.target);
      if (i < 0) return;
      if (e.target.tagName === 'TEXTAREA') {
        grow(e.target);
        if (rows[i].kind === 'term') rows[i].value = e.target.value; else rows[i].text = e.target.value;
      } else {
        rows[i].label = e.target.value;
      }
      write(false);
    });
    // A label set: locked again. Leaving a field saves.
    const finishLabel = (input) => {
      const i = rowOf(input);
      if (i < 0 || !rows[i]) return;
      rows[i].label = input.value.trim();
      rows[i].editing = false;
      if (!rows[i].label && !rows[i].value.trim()) rows.splice(i, 1);
      write(true);
      render();
      return i;
    };
    box.addEventListener('keydown', (e) => {
      if (e.target.tagName === 'INPUT' && (e.key === 'Enter' || e.key === 'Tab') && !e.shiftKey) {
        e.preventDefault();
        const i = finishLabel(e.target);
        if (i !== undefined) focusRow(i);
      } else if (e.target.tagName === 'INPUT' && e.key === 'Escape') {
        e.target.blur();
      }
    });
    box.addEventListener('focusout', (e) => {
      if (e.target.tagName === 'INPUT' && box.contains(e.target) && !box.contains(e.relatedTarget)) { finishLabel(e.target); return; }
      if (e.target.tagName === 'TEXTAREA') ta.dispatchEvent(new Event('change', { bubbles: true }));
      // A redraw asked for while typing here happens once the table is left.
      setTimeout(() => { if (pending && !box.contains(document.activeElement)) { pending = false; rows = parse(own.get.call(ta)); render(); } }, 0);
    });

    // The page setting the box's value (loading, another Mac's change,
    // "Use standard"): the table follows, unless it's what's already shown.
    Object.defineProperty(ta, 'value', {
      configurable: true,
      get() { return own.get.call(this); },
      set(v) {
        // While someone is typing in the table, what they type wins (it's
        // saved when they leave the field).
        if (box.contains(document.activeElement)) return;
        const same = String(v ?? '') === own.get.call(this);
        own.set.call(this, v);
        if (same && rows.length) return;
        rows = parse(v);
        render();
      },
    });
    new MutationObserver(render).observe(ta, { attributes: true, attributeFilter: ['disabled'] });
    ta.termsTable = { render: () => { if (box.contains(document.activeElement)) pending = true; else render(); } };
    render();
  };

  // For tests.
  window.termsTableParse = parse;
  window.termsTableSerialize = serialize;
})();

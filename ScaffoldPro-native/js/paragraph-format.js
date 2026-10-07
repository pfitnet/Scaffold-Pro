'use strict';

// Paragraph formatting for payment terms and key terms: a small toolbar
// (hanging indent, bullets, numbering), Tab for a hanging indent, and a
// live preview laid out the way the PDF prints it.
//
//   window.attachParagraphFormatting(textarea, { fallback })  — once, when the page loads;
//     fallback() gives the text printed when the box is left blank
//   window.refreshParagraphPreview(textarea)    — after setting its value
//
// The rules match formattedParagraphs() in main.swift:
//   "(i) Payment : text" or "Deposit: text"   label, colon, text in a hanging indent
//   "- text" or "• text"                      bullet
//   "1. text", "(a) text", "b) text", "(iv) text"   numbered
//   "marker<Tab>text"                         any marker
// Lines after one of these (up to a blank line) continue its text, lined up
// under it; an indented bullet, number or label goes under it, lined up with
// its text. Anything else is an ordinary paragraph; a blank line starts a
// new one.

(function () {
  const NUMBER_RE = /^(\(?[0-9]{1,3}[.)]|\([0-9]{1,3}\)|\(?[a-zA-Z][.)]|\([a-zA-Z]\)|\(?[ivxIVX]{1,5}[.)]|\([ivxIVX]{1,5}\))\s+/;
  const BULLETS = ['- ', '• ', '* ', '· '];

  function esc(value) {
    return String(value ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  }

  function labelSplit(line) {
    const colon = line.indexOf(':');
    if (colon < 0) return null;
    const label = line.slice(0, colon).trim();
    const after = line.slice(colon + 1);
    const lower = label.toLowerCase();
    if (!label || label.length > 40 || label.split(/ +/).length > 5) return null;
    if (after && after[0] !== ' ' && after[0] !== '\t') return null;
    if (lower.includes('http') || lower.includes('www.')) return null;
    return { marker: label, text: after.trim(), style: 'label' };
  }

  function hangingItem(raw) {
    const line = raw.trim();
    const tab = line.indexOf('\t');
    if (tab > 0) {
      const marker = line.slice(0, tab).trim();
      const rest = line.slice(tab + 1).trim();
      if (marker) {
        if (marker.endsWith(':')) return { marker: marker.slice(0, -1).trim(), text: rest, style: 'label' };
        return { marker, text: rest, style: 'marker' };
      }
    }
    for (const b of BULLETS) {
      if (line.startsWith(b)) return { marker: '•', text: line.slice(b.length).trim(), style: 'bullet' };
    }
    const label = labelSplit(line);
    if (label) return label;
    const m = line.match(NUMBER_RE);
    if (m) return { marker: m[0].trim(), text: line.slice(m[0].length), style: 'marker' };
    return null;
  }

  // Where an item's text starts, in points from its marker (as in main.swift).
  const TEXT_OFFSET = { label: 89.25, bullet: 12, marker: 24 };

  // → [{ kind: 'text', lines } | { kind: 'hanging', marker, lines, style, left }]
  //   left: points in from the margin (indented items sit under their parent's text)
  function parse(text) {
    const result = [];
    let current = null;
    let plain = [];
    let parentText = null;
    const flush = () => {
      if (current) { result.push(current); current = null; }
      if (plain.length) { result.push({ kind: 'text', lines: plain }); plain = []; }
    };
    for (const raw of String(text || '').replace(/\r\n/g, '\n').split('\n')) {
      const trimmed = raw.trim();
      if (!trimmed) { flush(); continue; }
      const item = hangingItem(raw);
      if (item) {
        flush();
        const indented = raw[0] === ' ' || raw[0] === '\t';
        const left = indented && parentText !== null ? parentText : 0;
        if (!indented || parentText === null) parentText = TEXT_OFFSET[item.style];
        current = { kind: 'hanging', marker: item.marker, lines: item.text ? [item.text] : [], style: item.style, left };
      } else if (current) {
        current.lines.push(trimmed);
      } else {
        plain.push(trimmed);
        parentText = null;
      }
    }
    flush();
    return result;
  }

  // fit: labels in a run share one colon column just past the longest
  // (as in a line item's description); otherwise a fixed column, as the terms.
  function previewHTML(text, fit) {
    if (fit) return fittedHTML(text);
    return parse(text).map((p) => {
      const body = p.lines.map(esc).join('<br>');
      if (p.kind === 'text') return `<p class="pf-text">${body}</p>`;
      const cls = p.style === 'label' ? 'pf-label' : p.style === 'bullet' ? 'pf-bullet' : 'pf-marker';
      // 11pt text previewed at 14px: 1pt ≈ 1.27px.
      return `<div class="pf-hang ${cls}" style="margin-left:${Math.round(p.left * 1.27)}px"><span class="pf-m">${esc(p.marker)}${p.style === 'label' ? '<span class="pf-colon">:</span>' : ''}</span><span class="pf-t">${body}</span></div>`;
    }).join('');
  }

  // A description as a line item prints it: blank lines kept, labels lined up.
  function fittedHTML(text) {
    const blocks = String(text || '').replace(/\r\n/g, '\n').split(/\n[ \t]*\n/);
    return blocks.filter((b) => b.trim()).map((block) => {
      let html = '';
      let labels = '';
      const endLabels = () => { if (labels) { html += `<div class="pf-labels">${labels}</div>`; labels = ''; } };
      for (const p of parse(block)) {
        const body = p.lines.map(esc).join('<br>');
        if (p.kind === 'hanging' && p.style === 'label') {
          labels += `<span class="pf-m" style="margin-left:${Math.round(p.left * 1.27)}px">${esc(p.marker)}</span><span class="pf-colon">:</span><span class="pf-t">${body}</span>`;
          continue;
        }
        endLabels();
        if (p.kind === 'text') html += `<p class="pf-text">${body}</p>`;
        else html += `<div class="pf-hang ${p.style === 'bullet' ? 'pf-bullet' : 'pf-marker'}" style="margin-left:${Math.round(p.left * 1.27)}px"><span class="pf-m">${esc(p.marker)}</span><span class="pf-t">${body}</span></div>`;
      }
      endLabels();
      return `<div class="pf-block">${html}</div>`;
    }).join('');
  }

  // A line item's description in an editor's list: laid out as printed when
  // it's written with bullets, numbering or labels over several lines
  // (the rule in main.swift: isFormattedDescription); else as typed.
  window.descriptionHTML = function descriptionHTML(text) {
    const t = String(text ?? '');
    const formatted = /[\n\t]/.test(t) && t.split('\n').some((l) => hangingItem(l));
    if (!formatted) return `<span class="line-desc-text">${t}</span>`;
    addStyles();
    return `<div class="pf-desc">${fittedHTML(t)}</div>`;
  };

  let styled = false;
  function addStyles() {
    if (styled) return;
    styled = true;
    const style = document.createElement('style');
    style.textContent = `
      .pf-toolbar { display: flex; gap: 4px; align-items: center; margin-bottom: 4px; flex-wrap: wrap; }
      .pf-toolbar button { padding: 1px 8px; font-size: 12px; }
      .pf-toolbar .pf-help { font-size: 11px; color: var(--text-secondary); margin-left: 4px; }
      .pf-preview { margin-top: 6px; padding: 8px 10px; border: 1px dashed var(--border); border-radius: var(--radius);
        font-family: 'EB Garamond', Georgia, serif; font-size: 14px; line-height: 1.45; }
      .pf-preview:empty { display: none; }
      .pf-preview .pf-text { margin: 0 0 6px; }
      .pf-hang { display: grid; column-gap: 6px; margin: 0 0 2px; }
      .pf-hang.pf-label { grid-template-columns: 107px 1fr; }
      .pf-hang.pf-bullet { grid-template-columns: 9px 1fr; }
      .pf-hang.pf-marker { grid-template-columns: minmax(24px, max-content) 1fr; }
      .pf-hang .pf-m { display: flex; justify-content: space-between; white-space: nowrap; }
      .pf-hang .pf-colon { padding-left: 4px; }
      .pf-preview-label { font-size: 11px; color: var(--text-secondary); margin-top: 6px; }
      .pf-labels { display: grid; grid-template-columns: max-content max-content 1fr; column-gap: 4px; margin: 0 0 2px; }
      .pf-labels .pf-colon { padding: 0; }
      .pf-block + .pf-block { margin-top: 0.9em; }
      .pf-desc { line-height: 1.4; }
      .pf-desc .pf-text { margin: 0; }`;
    document.head.appendChild(style);
  }

  // Selected lines (whole lines) of a textarea.
  function selectedLines(ta) {
    const v = ta.value;
    const start = v.lastIndexOf('\n', ta.selectionStart - 1) + 1;
    let end = v.indexOf('\n', ta.selectionEnd - (ta.selectionEnd > ta.selectionStart && v[ta.selectionEnd - 1] === '\n' ? 1 : 0));
    if (end < 0) end = v.length;
    return { start, end, lines: v.slice(start, end).split('\n') };
  }

  function replaceLines(ta, sel, lines, selectFrom, selectTo) {
    const v = ta.value;
    ta.value = v.slice(0, sel.start) + lines.join('\n') + v.slice(sel.end);
    ta.focus();
    if (selectFrom !== undefined) ta.setSelectionRange(sel.start + selectFrom, sel.start + selectTo);
    changed(ta);
  }

  function changed(ta) {
    window.refreshParagraphPreview(ta);
    ta.dispatchEvent(new Event('change'));
  }

  function stripMarker(line) {
    const item = hangingItem(line);
    if (item && item.style !== 'label') return item.text;
    return line.trim();
  }

  // Hanging indent: "Label : text" — the label is selected, ready to type
  // over; a short line on its own ("Model") becomes the label.
  function hangingIndent(ta) {
    const sel = selectedLines(ta);
    const first = sel.lines[0];
    if (labelSplit(first.trim())) { ta.focus(); return; }
    // A short label already typed ("Model"): "Model : ", ready for its value.
    const words = first.trim().split(/ +/).filter(Boolean);
    if (words.length && words.length <= 4 && first.trim().length <= 40) {
      sel.lines[0] = `${first.trim()} : `;
      replaceLines(ta, sel, sel.lines, sel.lines[0].length, sel.lines[0].length);
      return;
    }
    sel.lines[0] = `Label : ${first.trim()}`;
    replaceLines(ta, sel, sel.lines, 0, 5);
  }

  function bullets(ta) {
    const sel = selectedLines(ta);
    const all = sel.lines.filter((l) => l.trim()).every((l) => (hangingItem(l) || {}).style === 'bullet');
    replaceLines(ta, sel, sel.lines.map((l) => (!l.trim() ? l : all ? stripMarker(l) : `- ${stripMarker(l)}`)));
  }

  // Indent: puts the lines under the item above (lined up with its text).
  function indent(ta, out) {
    const sel = selectedLines(ta);
    replaceLines(ta, sel, sel.lines.map((l) => {
      if (!l.trim()) return l;
      return out ? l.replace(/^[ \t]+/, '') : `    ${l.replace(/^[ \t]+/, '')}`;
    }));
  }

  function numbering(ta, roman) {
    const sel = selectedLines(ta);
    const numerals = ['i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii', 'viii', 'ix', 'x', 'xi', 'xii'];
    let n = 0;
    replaceLines(ta, sel, sel.lines.map((l) => {
      if (!l.trim()) return l;
      const label = labelSplit(l.trim());
      const body = label ? l.trim().replace(NUMBER_RE, '') : stripMarker(l);
      n += 1;
      return `${roman ? `(${numerals[n - 1] || n})` : `${n}.`} ${body}`;
    }));
  }

  window.refreshParagraphPreview = function refreshParagraphPreview(ta) {
    if (ta && ta.termsTable) { ta.termsTable.render(); return; }
    const preview = ta.pfPreview;
    if (!preview) return;
    const fallback = !ta.value.trim() && ta.pfFallback ? ta.pfFallback() : '';
    // A line item's box: the preview only once there's formatting to see.
    const plain = ta.pfFit && !(/[\n\t]/.test(ta.value) && ta.value.split('\n').some((l) => hangingItem(l)));
    preview.innerHTML = plain ? '' : previewHTML(ta.value.trim() ? ta.value : fallback, ta.pfFit);
    ta.pfPreviewLabel.hidden = plain;
    ta.pfPreviewLabel.textContent = fallback ? 'As printed (standard terms from Settings):' : 'As printed:';
  };

  window.attachParagraphFormatting = function attachParagraphFormatting(ta, options) {
    // Terms boxes are a table of labelled terms and paragraphs (js/terms-table.js).
    if (!(options && options.fit) && window.attachTermsTable) { window.attachTermsTable(ta, options); return; }
    if (!ta || ta.pfPreview) return;
    addStyles();
    const bar = document.createElement('div');
    bar.className = 'pf-toolbar';
    if (options && options.strip) {
      // A slim strip of buttons along the top of the box (custom items).
      bar.className = 'pf-toolbar pf-strip';
      bar.innerHTML = `
        <button type="button" data-pf="hang" data-no-icon data-tip="Label : value" aria-label="Label and value, colons lined up" title="Label and value, colons lined up — type “Model”, press this, then its value"><svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2.5 5h4.5M2.5 10h4.5M2.5 15h4.5M11.5 5h6M11.5 10h6M11.5 15h4"/><circle cx="9.25" cy="4" r=".55" fill="currentColor" stroke="none"/><circle cx="9.25" cy="6" r=".55" fill="currentColor" stroke="none"/><circle cx="9.25" cy="9" r=".55" fill="currentColor" stroke="none"/><circle cx="9.25" cy="11" r=".55" fill="currentColor" stroke="none"/><circle cx="9.25" cy="14" r=".55" fill="currentColor" stroke="none"/><circle cx="9.25" cy="16" r=".55" fill="currentColor" stroke="none"/></svg></button>
        <span class="pf-sep"></span>
        <button type="button" data-pf="bullet" data-no-icon data-tip="Bulleted list" aria-label="Bulleted list"><svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="4" cy="5" r="1.2" fill="currentColor" stroke="none"/><circle cx="4" cy="10" r="1.2" fill="currentColor" stroke="none"/><circle cx="4" cy="15" r="1.2" fill="currentColor" stroke="none"/><path d="M8 5h9M8 10h9M8 15h9"/></svg></button>
        <button type="button" data-pf="number" data-no-icon data-tip="Numbered list" aria-label="Numbered list 1. 2. 3."><svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 5h9M8 10h9M8 15h9"/><path d="M3 3.6l1.2-.6v4" stroke-width="1.2"/><path d="M2.8 9c.3-.6 1.9-.8 1.9.3 0 .9-1.9 1.6-1.9 2.4h2" stroke-width="1.2"/><path d="M2.9 13.5h1.8l-1 1.2c.9 0 1.2.4 1.2.9 0 .9-1.5 1-2.1.4" stroke-width="1.2"/></svg></button>
        <button type="button" data-pf="roman" data-no-icon data-tip="Numbered (i) (ii)" aria-label="Numbered list (i) (ii) (iii)"><svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 5h9M8 10h9M8 15h9"/><path d="M4 3.5v3" stroke-width="1.3"/><path d="M3 8.5v3M5 8.5v3" stroke-width="1.3"/><path d="M2.4 13.5v3M4 13.5v3M5.6 13.5v3" stroke-width="1.2"/></svg></button>
        <span class="pf-sep"></span>
        <button type="button" data-pf="outdent" data-no-icon data-tip="Decrease indent" aria-label="Decrease indent"><svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 4.5h8.5M9 8.5h8.5M9 12.5h8.5M2.5 16.5h15"/><path d="M6 6.5l-3.5 2 3.5 2z" fill="currentColor"/></svg></button>
        <button type="button" data-pf="indent" data-no-icon data-tip="Increase indent" aria-label="Increase indent"><svg viewBox="0 0 20 20" width="18" height="18" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M9 4.5h8.5M9 8.5h8.5M9 12.5h8.5M2.5 16.5h15"/><path d="M2.5 6.5l3.5 2-3.5 2z" fill="currentColor"/></svg></button>
        <span class="pf-tip">${options.tip ? esc(options.tip) : ''}</span>`;
    } else bar.innerHTML = `
      <button type="button" data-pf="hang" title="Label, colon, then the text in a hanging indent — e.g. “Deposit : 50% upon order confirmation”">Hanging Indent</button>
      <button type="button" data-pf="bullet" title="Bullet points with a hanging indent">• Bullets</button>
      <button type="button" data-pf="number" title="Numbered 1. 2. 3.">1. Numbering</button>
      <button type="button" data-pf="roman" title="Numbered (i) (ii) (iii)">(i) Numbering</button>
      <button type="button" data-pf="indent" title="Put the lines under the item above, lined up with its text">Indent →</button>
      <button type="button" data-pf="outdent" title="Back to the margin">← Outdent</button>
      <span class="pf-help">${options && options.help ? esc(options.help) : 'Tab after a label or number also makes a hanging indent. Lines below it line up under the text; a blank line ends it.'}</span>`;
    ta.parentNode.insertBefore(bar, ta);
    const label = document.createElement('div');
    label.className = 'pf-preview-label';
    label.textContent = 'As printed:';
    const preview = document.createElement('div');
    preview.className = 'pf-preview';
    if (options && options.previewIn) options.previewIn.append(label, preview); else ta.after(label, preview);
    ta.pfPreview = preview;
    ta.pfPreviewLabel = label;
    ta.pfFallback = options && options.fallback;
    ta.pfFit = !!(options && options.fit);

    bar.addEventListener('mousedown', (e) => e.preventDefault()); // keep the selection in the text box
    bar.addEventListener('click', (e) => {
      const b = e.target.closest('button[data-pf]');
      if (!b || ta.disabled) return;
      if (b.dataset.pf === 'hang') hangingIndent(ta);
      else if (b.dataset.pf === 'bullet') bullets(ta);
      else if (b.dataset.pf === 'indent' || b.dataset.pf === 'outdent') indent(ta, b.dataset.pf === 'outdent');
      else numbering(ta, b.dataset.pf === 'roman');
    });
    ta.addEventListener('input', () => window.refreshParagraphPreview(ta));
    ta.addEventListener('keydown', (e) => {
      if (e.key !== 'Tab' || e.shiftKey || e.metaKey || e.ctrlKey || e.altKey) return;
      e.preventDefault();
      const { selectionStart: s, selectionEnd: end, value } = ta;
      ta.value = value.slice(0, s) + '\t' + value.slice(end);
      ta.setSelectionRange(s + 1, s + 1);
      window.refreshParagraphPreview(ta);
    });
    const sync = () => { bar.classList.toggle('hidden', ta.disabled); };
    new MutationObserver(sync).observe(ta, { attributes: true, attributeFilter: ['disabled'] });
    sync();
    window.refreshParagraphPreview(ta);
  };

  // For tests: the same parsing the preview uses.
  window.parseFormattedParagraphs = parse;
})();

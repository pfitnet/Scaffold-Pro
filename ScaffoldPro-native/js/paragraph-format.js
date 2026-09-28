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

  function previewHTML(text) {
    return parse(text).map((p) => {
      const body = p.lines.map(esc).join('<br>');
      if (p.kind === 'text') return `<p class="pf-text">${body}</p>`;
      const cls = p.style === 'label' ? 'pf-label' : p.style === 'bullet' ? 'pf-bullet' : 'pf-marker';
      // 11pt text previewed at 14px: 1pt ≈ 1.27px.
      return `<div class="pf-hang ${cls}" style="margin-left:${Math.round(p.left * 1.27)}px"><span class="pf-m">${esc(p.marker)}${p.style === 'label' ? '<span class="pf-colon">:</span>' : ''}</span><span class="pf-t">${body}</span></div>`;
    }).join('');
  }

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
      .pf-preview-label { font-size: 11px; color: var(--text-secondary); margin-top: 6px; }`;
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

  // Hanging indent: "Label : text" — the label is selected, ready to type over.
  function hangingIndent(ta) {
    const sel = selectedLines(ta);
    const first = sel.lines[0];
    if (labelSplit(first.trim())) { ta.focus(); return; }
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
    const preview = ta.pfPreview;
    if (!preview) return;
    const fallback = !ta.value.trim() && ta.pfFallback ? ta.pfFallback() : '';
    preview.innerHTML = previewHTML(ta.value.trim() ? ta.value : fallback);
    ta.pfPreviewLabel.textContent = fallback ? 'As printed (standard terms from Settings):' : 'As printed:';
  };

  window.attachParagraphFormatting = function attachParagraphFormatting(ta, options) {
    if (!ta || ta.pfPreview) return;
    addStyles();
    const bar = document.createElement('div');
    bar.className = 'pf-toolbar';
    bar.innerHTML = `
      <button type="button" data-pf="hang" title="Label, colon, then the text in a hanging indent — e.g. “Deposit : 50% upon order confirmation”">Hanging Indent</button>
      <button type="button" data-pf="bullet" title="Bullet points with a hanging indent">• Bullets</button>
      <button type="button" data-pf="number" title="Numbered 1. 2. 3.">1. Numbering</button>
      <button type="button" data-pf="roman" title="Numbered (i) (ii) (iii)">(i) Numbering</button>
      <button type="button" data-pf="indent" title="Put the lines under the item above, lined up with its text">Indent →</button>
      <button type="button" data-pf="outdent" title="Back to the margin">← Outdent</button>
      <span class="pf-help">Tab after a label or number also makes a hanging indent. Lines below it line up under the text; a blank line ends it.</span>`;
    ta.parentNode.insertBefore(bar, ta);
    const label = document.createElement('div');
    label.className = 'pf-preview-label';
    label.textContent = 'As printed:';
    const preview = document.createElement('div');
    preview.className = 'pf-preview';
    ta.after(label, preview);
    ta.pfPreview = preview;
    ta.pfPreviewLabel = label;
    ta.pfFallback = options && options.fallback;

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

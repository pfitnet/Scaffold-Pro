'use strict';

// A Google Docs–style formatting toolbar for a contenteditable area (the
// letter editor):
//   undo / redo · text style · font · size (− / +) · bold, italic,
//   underline, strikethrough · text and highlight colour · link ·
//   alignment · line spacing · numbered / bulleted lists · indent ·
//   insert table (pick the size on a grid) and, inside a table, add or
//   delete rows and columns · clear formatting.
//
//   const editor = window.createRichEditor(area, toolbar, { onChange });
//   editor.setEditable(false);   // an issued letter
//
// Sizes are written in points (e.g. font-size: 12pt), as the PDF uses them.

(function () {
  const FONTS = [
    ['EB Garamond', 'EB Garamond (letter)'], ['Georgia', 'Georgia'], ['Times New Roman', 'Times New Roman'],
    ['Arial', 'Arial'], ['Helvetica', 'Helvetica'], ['Verdana', 'Verdana'], ['Courier New', 'Courier New'],
    ['PingFang HK', '蘋方 PingFang (中文)'], ['Songti TC', '宋體 Songti (中文)'],
  ];
  const SIZES = [8, 9, 10, 11, 12, 14, 16, 18, 20, 24, 28, 36, 48];
  const DEFAULT_SIZE = 11;
  const DEFAULT_FONT = 'EB Garamond';

  const SVG = (d) => `<svg viewBox="0 0 20 20" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${d}</svg>`;
  const ICON = {
    undo: SVG('<path d="M7 5 3.5 8.5 7 12"/><path d="M4 8.5h8a4 4 0 0 1 0 8h-2"/>'),
    redo: SVG('<path d="m13 5 3.5 3.5L13 12"/><path d="M16 8.5H8a4 4 0 0 0 0 8h2"/>'),
    left: SVG('<path d="M3 5h14M3 8.5h9M3 12h14M3 15.5h9"/>'),
    center: SVG('<path d="M3 5h14M5.5 8.5h9M3 12h14M5.5 15.5h9"/>'),
    right: SVG('<path d="M3 5h14M8 8.5h9M3 12h14M8 15.5h9"/>'),
    justify: SVG('<path d="M3 5h14M3 8.5h14M3 12h14M3 15.5h14"/>'),
    ol: SVG('<path d="M8 5.5h9M8 10h9M8 14.5h9"/><path d="M3.2 4.5h1v3M3 7.5h2.2M3 12.2c.3-.6 2-.8 2 .3 0 .9-2 1.3-2 2.3h2.2"/>'),
    ul: SVG('<path d="M8 5.5h9M8 10h9M8 14.5h9"/><circle cx="4" cy="5.5" r=".9" fill="currentColor"/><circle cx="4" cy="10" r=".9" fill="currentColor"/><circle cx="4" cy="14.5" r=".9" fill="currentColor"/>'),
    outdent: SVG('<path d="M9 5.5h8M9 10h8M9 14.5h8M3 5.5h2M6 7.5 3.5 10 6 12.5"/>'),
    indent: SVG('<path d="M9 5.5h8M9 10h8M9 14.5h8M3 5.5h2M3.5 7.5 6 10l-2.5 2.5"/>'),
    link: SVG('<path d="M8.5 11.5a3 3 0 0 0 4.2 0l2.6-2.6a3 3 0 0 0-4.2-4.2l-.9.9"/><path d="M11.5 8.5a3 3 0 0 0-4.2 0l-2.6 2.6a3 3 0 0 0 4.2 4.2l.9-.9"/>'),
    table: SVG('<rect x="3" y="4" width="14" height="12" rx="1"/><path d="M3 8h14M3 12h14M8 4v12M12.5 4v12"/>'),
    clear: SVG('<path d="M5 4.5h9M9.5 4.5 7 15.5M4 16l12-12"/>'),
    spacing: SVG('<path d="M9 5h8M9 10h8M9 15h8M4.5 4v12M2.8 5.8 4.5 4l1.7 1.8M2.8 14.2 4.5 16l1.7-1.8"/>'),
  };

  function button(cmd, title, content, cls = '') {
    return `<button type="button" class="rt-btn ${cls}" data-cmd="${cmd}" title="${title}" aria-label="${title}">${content}</button>`;
  }

  window.createRichEditor = function createRichEditor(area, toolbar, opts = {}) {
    const onChange = opts.onChange || (() => {});
    let editable = true;
    let savedRange = null;

    toolbar.classList.add('rt-toolbar');
    toolbar.innerHTML = `
      ${button('undo', 'Undo (⌘Z)', ICON.undo)}${button('redo', 'Redo (⇧⌘Z)', ICON.redo)}
      <span class="rt-sep"></span>
      <select class="rt-select rt-block" title="Text style">
        <option value="p">Normal text</option><option value="h1">Heading 1</option><option value="h2">Heading 2</option><option value="h3">Heading 3</option>
      </select>
      <span class="rt-sep"></span>
      <select class="rt-select rt-font" title="Font">${FONTS.map(([v, l]) => `<option value="${v}" style="font-family:'${v}'">${l}</option>`).join('')}</select>
      <span class="rt-sep"></span>
      ${button('smaller', 'Decrease font size', '−', 'rt-size-btn')}
      <input class="rt-size" type="text" inputmode="numeric" title="Font size" list="rt-sizes" value="${DEFAULT_SIZE}" />
      <datalist id="rt-sizes">${SIZES.map((s) => `<option value="${s}">`).join('')}</datalist>
      ${button('bigger', 'Increase font size', '+', 'rt-size-btn')}
      <span class="rt-sep"></span>
      ${button('bold', 'Bold (⌘B)', '<b>B</b>')}${button('italic', 'Italic (⌘I)', '<i>I</i>')}
      ${button('underline', 'Underline (⌘U)', '<u>U</u>')}${button('strikeThrough', 'Strikethrough', '<s>S</s>')}
      <label class="rt-btn rt-color" title="Text colour"><span class="rt-color-a">A</span><span class="rt-swatch rt-fore-swatch"></span><input type="color" class="rt-fore" value="#000000" /></label>
      <label class="rt-btn rt-color" title="Highlight colour"><span class="rt-color-a rt-hl">ab</span><span class="rt-swatch rt-back-swatch" style="background:#fff59d"></span><input type="color" class="rt-back" value="#fff59d" /></label>
      <span class="rt-sep"></span>
      ${button('link', 'Insert link', ICON.link)}
      <div class="rt-table-wrap">
        ${button('table', 'Insert table', ICON.table)}
        <div class="rt-grid hidden"><div class="rt-grid-cells"></div><div class="rt-grid-label">Insert table</div></div>
      </div>
      <span class="rt-sep"></span>
      ${button('justifyLeft', 'Align left', ICON.left)}${button('justifyCenter', 'Centre', ICON.center)}
      ${button('justifyRight', 'Align right', ICON.right)}${button('justifyFull', 'Justify', ICON.justify)}
      <select class="rt-select rt-spacing" title="Line spacing">
        <option value="">Line spacing</option><option value="1">Single</option><option value="1.15">1.15</option><option value="1.5">1.5</option><option value="2">Double</option>
      </select>
      <span class="rt-sep"></span>
      ${button('insertOrderedList', 'Numbered list', ICON.ol)}${button('insertUnorderedList', 'Bulleted list', ICON.ul)}
      ${button('outdent', 'Decrease indent', ICON.outdent)}${button('indent', 'Increase indent', ICON.indent)}
      <span class="rt-sep"></span>
      ${button('removeFormat', 'Clear formatting', ICON.clear)}
      <span class="rt-table-tools hidden">
        <span class="rt-sep"></span>
        <span class="rt-label">Table:</span>
        ${button('rowAbove', 'Insert row above', '+ Row ↑', 'rt-text')}${button('rowBelow', 'Insert row below', '+ Row ↓', 'rt-text')}
        ${button('colLeft', 'Insert column left', '+ Col ←', 'rt-text')}${button('colRight', 'Insert column right', '+ Col →', 'rt-text')}
        ${button('deleteRow', 'Delete row', '− Row', 'rt-text')}${button('deleteCol', 'Delete column', '− Col', 'rt-text')}
        ${button('deleteTable', 'Delete table', 'Delete table', 'rt-text rt-danger')}
      </span>`;

    const $ = (sel) => toolbar.querySelector(sel);

    // ---- selection ----

    function selectionInArea() {
      const sel = window.getSelection();
      return sel && sel.rangeCount && area.contains(sel.getRangeAt(0).commonAncestorContainer) ? sel.getRangeAt(0) : null;
    }
    function keepSelection() {
      const r = selectionInArea();
      if (r) savedRange = r.cloneRange();
    }
    function restoreSelection() {
      area.focus();
      if (savedRange) {
        const sel = window.getSelection();
        sel.removeAllRanges();
        sel.addRange(savedRange);
      }
    }
    document.addEventListener('selectionchange', () => {
      if (selectionInArea()) { keepSelection(); refreshState(); }
    });

    function exec(cmd, value = null) {
      if (!editable) return;
      restoreSelection();
      document.execCommand('styleWithCSS', false, true);
      document.execCommand(cmd, false, value);
      changed();
    }

    function changed() {
      keepSelection();
      refreshState();
      onChange();
    }

    // ---- font size in points ----

    function applySize(pt) {
      if (!editable) return;
      pt = Math.max(6, Math.min(96, Math.round(pt)));
      restoreSelection();
      const r = selectionInArea();
      if (!r) return;
      if (r.collapsed) {
        // Nothing selected: type in the new size from here.
        const span = document.createElement('span');
        span.style.fontSize = `${pt}pt`;
        span.textContent = '​';
        r.insertNode(span);
        const sel = window.getSelection();
        const after = document.createRange();
        after.setStart(span.firstChild, 1);
        after.collapse(true);
        sel.removeAllRanges();
        sel.addRange(after);
      } else {
        document.execCommand('styleWithCSS', false, false);
        document.execCommand('fontSize', false, '7');
        for (const font of area.querySelectorAll('font[size="7"]')) {
          const span = document.createElement('span');
          span.style.fontSize = `${pt}pt`;
          while (font.firstChild) span.appendChild(font.firstChild);
          // Sizes set inside it before give way to the new one.
          for (const inner of span.querySelectorAll('[style*="font-size"]')) inner.style.fontSize = '';
          font.replaceWith(span);
        }
      }
      $('.rt-size').value = pt;
      changed();
    }

    function currentSize() {
      const r = selectionInArea() || savedRange;
      let node = r ? r.startContainer : null;
      if (node && node.nodeType === 3) node = node.parentElement;
      if (!node || !area.contains(node)) return DEFAULT_SIZE;
      return Math.round(parseFloat(getComputedStyle(node).fontSize) * 0.75 * 2) / 2;
    }

    // ---- tables ----

    function cellStyle() { return 'border:0.75pt solid #000;padding:3pt 5pt;vertical-align:top'; }

    function insertTable(rows, cols) {
      const cell = `<td style="${cellStyle()}"><br></td>`;
      const html = `<table class="grid" style="border-collapse:collapse;width:100%"><tbody>${
        Array.from({ length: rows }, () => `<tr>${cell.repeat(cols)}</tr>`).join('')}</tbody></table><p><br></p>`;
      exec('insertHTML', html);
    }

    function currentCell() {
      const r = selectionInArea() || savedRange;
      let node = r ? r.startContainer : null;
      if (node && node.nodeType === 3) node = node.parentElement;
      return node && area.contains(node) ? node.closest('td, th') : null;
    }

    function newCell() {
      const td = document.createElement('td');
      td.setAttribute('style', cellStyle());
      td.innerHTML = '<br>';
      return td;
    }

    function tableAction(cmd) {
      const cell = currentCell();
      if (!cell || !editable) return;
      const row = cell.parentElement;
      const table = cell.closest('table');
      const index = cell.cellIndex;
      if (cmd === 'rowAbove' || cmd === 'rowBelow') {
        const tr = document.createElement('tr');
        for (let i = 0; i < row.cells.length; i++) tr.appendChild(newCell());
        row.parentElement.insertBefore(tr, cmd === 'rowAbove' ? row : row.nextSibling);
      } else if (cmd === 'colLeft' || cmd === 'colRight') {
        for (const tr of table.rows) {
          const ref = tr.cells[index];
          const td = newCell();
          if (!ref) tr.appendChild(td);
          else tr.insertBefore(td, cmd === 'colLeft' ? ref : ref.nextSibling);
        }
      } else if (cmd === 'deleteRow') {
        if (table.rows.length <= 1) table.remove(); else row.remove();
      } else if (cmd === 'deleteCol') {
        if (row.cells.length <= 1) table.remove();
        else for (const tr of [...table.rows]) if (tr.cells[index]) tr.cells[index].remove();
      } else if (cmd === 'deleteTable') {
        table.remove();
      }
      changed();
    }

    // The size grid under "Insert table": hover to choose, click to insert.
    const grid = $('.rt-grid');
    const cells = $('.rt-grid-cells');
    cells.innerHTML = Array.from({ length: 64 }, (_, i) => `<span data-r="${Math.floor(i / 8) + 1}" data-c="${(i % 8) + 1}"></span>`).join('');
    cells.addEventListener('mouseover', (e) => {
      const t = e.target.closest('span[data-r]');
      if (!t) return;
      const r = +t.dataset.r, c = +t.dataset.c;
      for (const s of cells.children) s.classList.toggle('on', +s.dataset.r <= r && +s.dataset.c <= c);
      $('.rt-grid-label').textContent = `${r} × ${c}`;
    });
    cells.addEventListener('mousedown', (e) => e.preventDefault());
    cells.addEventListener('click', (e) => {
      const t = e.target.closest('span[data-r]');
      if (!t) return;
      grid.classList.add('hidden');
      insertTable(+t.dataset.r, +t.dataset.c);
    });
    document.addEventListener('mousedown', (e) => {
      if (!e.target.closest('.rt-table-wrap')) grid.classList.add('hidden');
    });

    // ---- line spacing ----

    function applySpacing(value) {
      if (!editable || !value) return;
      restoreSelection();
      const r = selectionInArea();
      if (!r) return;
      let blocks = [...area.querySelectorAll('p, h1, h2, h3, li, div')].filter((b) => r.intersectsNode(b));
      if (!blocks.length) {
        let node = r.startContainer.nodeType === 3 ? r.startContainer.parentElement : r.startContainer;
        const b = node.closest('p, h1, h2, h3, li, div');
        if (b && area.contains(b) && b !== area) blocks = [b];
      }
      for (const b of blocks) b.style.lineHeight = value;
      changed();
    }

    // ---- toolbar state ----

    function refreshState() {
      for (const cmd of ['bold', 'italic', 'underline', 'strikeThrough', 'insertOrderedList', 'insertUnorderedList',
        'justifyLeft', 'justifyCenter', 'justifyRight', 'justifyFull']) {
        const b = toolbar.querySelector(`[data-cmd="${cmd}"]`);
        let on = false;
        try { on = document.queryCommandState(cmd); } catch (e) { on = false; }
        if (b) b.classList.toggle('active', on);
      }
      const r = selectionInArea() || savedRange;
      let node = r ? r.startContainer : null;
      if (node && node.nodeType === 3) node = node.parentElement;
      if (node && area.contains(node)) {
        const block = node.closest('h1, h2, h3');
        $('.rt-block').value = block && area.contains(block) ? block.tagName.toLowerCase() : 'p';
        const family = getComputedStyle(node).fontFamily.split(',')[0].replace(/["']/g, '').trim();
        const match = FONTS.find(([v]) => v.toLowerCase() === family.toLowerCase());
        $('.rt-font').value = match ? match[0] : DEFAULT_FONT;
        if (document.activeElement !== $('.rt-size')) $('.rt-size').value = currentSize();
      }
      $('.rt-table-tools').classList.toggle('hidden', !currentCell());
    }

    // ---- wiring ----

    toolbar.addEventListener('mousedown', (e) => {
      // Buttons don't take the focus (and the selection) from the text.
      if (e.target.closest('button') && !e.target.closest('input, select')) e.preventDefault();
    });
    toolbar.addEventListener('click', (e) => {
      const b = e.target.closest('button[data-cmd]');
      if (!b || !editable) return;
      const cmd = b.dataset.cmd;
      if (cmd === 'table') { grid.classList.toggle('hidden'); return; }
      if (cmd === 'smaller' || cmd === 'bigger') {
        const now = currentSize();
        const next = cmd === 'bigger' ? SIZES.find((s) => s > now) || now + 2 : [...SIZES].reverse().find((s) => s < now) || Math.max(6, now - 1);
        applySize(next);
        return;
      }
      if (cmd === 'link') {
        const url = prompt('Link address (e.g. www.pfitnet.com):');
        if (url) exec('createLink', /^[a-z]+:/i.test(url) ? url : `https://${url}`);
        return;
      }
      if (['rowAbove', 'rowBelow', 'colLeft', 'colRight', 'deleteRow', 'deleteCol', 'deleteTable'].includes(cmd)) { tableAction(cmd); return; }
      if (cmd === 'removeFormat') {
        exec('removeFormat');
        exec('formatBlock', 'p');
        return;
      }
      exec(cmd);
    });
    $('.rt-block').addEventListener('change', (e) => exec('formatBlock', e.target.value));
    $('.rt-font').addEventListener('change', (e) => exec('fontName', e.target.value));
    $('.rt-size').addEventListener('change', (e) => applySize(Number(e.target.value) || DEFAULT_SIZE));
    $('.rt-size').addEventListener('keydown', (e) => { if (e.key === 'Enter') { e.preventDefault(); applySize(Number(e.target.value) || DEFAULT_SIZE); } });
    $('.rt-fore').addEventListener('input', (e) => { $('.rt-fore-swatch').style.background = e.target.value; exec('foreColor', e.target.value); });
    $('.rt-back').addEventListener('input', (e) => { $('.rt-back-swatch').style.background = e.target.value; exec('hiliteColor', e.target.value); });
    $('.rt-spacing').addEventListener('change', (e) => { applySpacing(e.target.value); e.target.value = ''; });
    for (const sel of ['.rt-block', '.rt-font', '.rt-size', '.rt-fore', '.rt-back', '.rt-spacing']) {
      $(sel).addEventListener('mousedown', keepSelection);
    }

    area.addEventListener('input', changed);
    area.addEventListener('keyup', refreshState);
    area.addEventListener('mouseup', refreshState);
    // Pasted text keeps its words, not other programs' styling.
    area.addEventListener('paste', (e) => {
      const text = e.clipboardData && e.clipboardData.getData('text/plain');
      const html = e.clipboardData && e.clipboardData.getData('text/html');
      if (!html && text) {
        e.preventDefault();
        document.execCommand('insertText', false, text);
      }
    });
    document.execCommand('defaultParagraphSeparator', false, 'p');

    return {
      setEditable(on) {
        editable = !!on;
        area.contentEditable = on ? 'true' : 'false';
        toolbar.classList.toggle('disabled', !on);
        for (const el of toolbar.querySelectorAll('button, select, input')) el.disabled = !on;
      },
      focus() { area.focus(); },
      refresh: refreshState,
    };
  };
})();

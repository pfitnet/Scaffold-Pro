'use strict';

// The preview shown before an export is saved — for a PDF and for a Word
// copy alike. Nothing goes into the project folder until "Save" is clicked;
// then the file can be opened or shown in Finder.
//
//   await window.docPreview.pdf(() => window.api.quotations.exportPDF(id, { preview: true }), { title: 'Qt26210-004' })
//     (the native side sends the finished PDF's pages; "Save" → files:savePreview)
//   await window.docPreview.word({ bytes, fileName, title, save })
//     (js/docx-export.js: the .docx drawn here by docx-preview; "Save" → save(false))
//   → { ok: true, saved: true|false, path } — or { ok: false, error }.
//
// With `edit: { id }` (a quotation, invoice or delivery note) the header
// has Edit: a panel beside the pages lists the document's lines, and a
// paragraph can be added above or below any of them. Each is kept with the
// document (window.api.docEdits; Sources/DocInserts.swift), so every PDF
// and Word copy has it; the preview is drawn again as soon as it's saved.
//
// The Word copy is drawn with docx-preview (js/vendor, Apache-2.0) and
// JSZip (js/vendor, MIT), loaded the first time they're needed.

(function () {
  if (window.docPreview) return;
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const reduceMotion = () => false;
  const ICON = {
    close: '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M4 4l8 8M12 4l-8 8"/></svg>',
    pencil: '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M10.5 3 13 5.5 6 12.5l-3 .5.5-3z"/></svg>',
    minus: '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M3.5 8h9"/></svg>',
    plus: '<svg viewBox="0 0 16 16" width="14" height="14" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M8 3.5v9M3.5 8h9"/></svg>',
    check: '<svg viewBox="0 0 16 16" width="15" height="15" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3.5 8.5l3 3 6-7"/></svg>',
  };

  let vendor = null;
  function loadVendor() {
    if (window.docx && window.docx.renderAsync) return Promise.resolve();
    if (vendor) return vendor;
    const add = (src) => new Promise((resolve, reject) => {
      const s = document.createElement('script');
      s.src = src; s.onload = resolve; s.onerror = () => reject(new Error(`${src} couldn't be loaded`));
      document.head.appendChild(s);
    });
    vendor = (window.JSZip ? Promise.resolve() : add('js/vendor/jszip.min.js')).then(() => add('js/vendor/docx-preview.min.js'));
    return vendor;
  }

  function sheet({ kind, title, fileName, actions, note, editable }) {
    const el = document.createElement('div');
    el.className = 'dp-backdrop';
    el.innerHTML = `
      <div class="dp-sheet" role="dialog" aria-modal="true" aria-label="Preview of ${esc(fileName || title)}" data-no-icon>
        <header class="dp-head">
          <span class="dp-badge ${kind}">${kind === 'word' ? 'W' : 'PDF'}</span>
          <div class="dp-title"><b>${esc(title || fileName || 'Preview')}</b><span class="dp-sub">${esc(fileName || '')}</span></div>
          ${editable ? `<button type="button" class="dp-list-btn" hidden title="All your paragraphs, beside the pages">List</button><button type="button" class="dp-edit-btn" aria-pressed="false" title="Click between lines on the page to add your own paragraph there — kept with this document, in every PDF and Word copy">${ICON.pencil}<span>Edit</span></button>` : ''}
          <div class="dp-zoom" role="group" aria-label="Zoom">
            <button type="button" data-zoom="out" title="Smaller (⌘−)">${ICON.minus}</button>
            <button type="button" data-zoom="fit" class="dp-zoom-label" title="Fit the width (⌘0)">100%</button>
            <button type="button" data-zoom="in" title="Larger (⌘+)">${ICON.plus}</button>
          </div>
          <button type="button" class="dp-close" title="Close without saving (Esc)" aria-label="Close">${ICON.close}</button>
        </header>
        <div class="dp-main">
          <div class="dp-canvas">
            <div class="dp-loading"><span class="dp-spinner"></span><span>Preparing the ${kind === 'word' ? 'Word document' : 'PDF'}…</span></div>
            <div class="dp-pages"></div>
          </div>
          ${editable ? '<aside class="dp-edit" aria-label="Add paragraphs" hidden></aside>' : ''}
        </div>
        <footer class="dp-foot">
          <span class="dp-note">${esc(note || 'Nothing is saved until you click Save.')}</span>
          <span class="dp-actions">
            <button type="button" class="dp-cancel${actions && actions.some((a) => a.key === 'done') ? ' hidden' : ''}">${actions ? 'Close' : 'Cancel'}</button>
            ${actions ? actions.map((a) => `<button type="button" class="dp-act${a.primary ? ' primary' : ''}${a.danger ? ' danger' : ''}" data-act="${esc(a.key)}" disabled>${a.html || esc(a.label)}</button>`).join('')
              : '<button type="button" class="primary dp-save" disabled>Save to Project Folder</button>'}
          </span>
        </footer>
      </div>`;
    document.body.appendChild(el);
    requestAnimationFrame(() => el.classList.add('open'));
    return el;
  }

  // The common part: zoom, keys, saving, closing. `ready()` draws the pages
  // (returns a note, if any); `save()` → { ok, error, path }; `discard()`.
  // With `actions` ([{ key, label | html, primary, danger }]) the footer
  // offers those instead of Save: choosing one closes the preview with
  // { ok: true, saved: false, action: key }.
  function run({ kind, title, fileName, ready, save, discard, actions, note, edit }) {
    return new Promise((resolve) => {
      const el = sheet({ kind, title, fileName, actions, note, editable: !!edit });
      const $ = (s) => el.querySelector(s);
      const pages = $('.dp-pages');
      let zoom = 1;
      let fitted = true;
      let saved = null;
      let busy = false;
      const setZoom = (z) => {
        zoom = Math.min(3, Math.max(0.25, z));
        pages.style.zoom = zoom;
        $('.dp-zoom-label').textContent = `${Math.round(zoom * 100)}%`;
      };
      const fit = () => {
        fitted = true;
        pages.style.zoom = 1;
        const room = $('.dp-canvas').clientWidth - 64;
        const widest = Math.max(1, ...[...pages.querySelectorAll('.dp-page, .dp-docx-host')].map((p) => p.offsetWidth));
        setZoom(Math.min(1.25, room / widest));
      };
      const close = (result) => {
        if (busy) return;
        document.removeEventListener('keydown', onKey, true);
        window.removeEventListener('resize', onResize);
        el.classList.remove('open');
        el.classList.add('closing');
        setTimeout(() => el.remove(), reduceMotion() ? 0 : 220);
        if (!saved && discard) discard();
        resolve(result);
      };
      const showSaved = (path) => {
        const where = String(path || '').split('/').slice(-3, -1).join(' › ');
        $('.dp-foot').innerHTML = `
          <span class="dp-done">${ICON.check}<span>Saved${where ? ` to <b>${esc(where)}</b>` : ''}</span></span>
          <span class="dp-actions">
            <button type="button" class="dp-reveal">Show in Finder</button>
            <button type="button" class="dp-open">Open</button>
            <button type="button" class="primary dp-finish">Done</button>
          </span>`;
        $('.dp-reveal').addEventListener('click', () => window.api.files.openSaved(path, true));
        $('.dp-open').addEventListener('click', () => window.api.files.openSaved(path, false));
        $('.dp-finish').addEventListener('click', () => close({ ok: true, saved: true, path }));
        $('.dp-finish').focus();
      };
      const doSave = async () => {
        if (busy || saved) return;
        busy = true;
        const button = $('.dp-save');
        button.disabled = true;
        button.textContent = 'Saving…';
        let r;
        try { r = await save(); } catch (e) { r = { ok: false, error: e.message }; }
        busy = false;
        if (!r || !r.ok) {
          button.disabled = false;
          button.textContent = 'Save to Project Folder';
          await window.appAlert((r && r.error) || 'It couldn’t be saved.');
          return;
        }
        saved = r;
        el.classList.add('saved');
        showSaved(r.path);
      };
      const onKey = (e) => {
        if (document.querySelector('.app-dialog-backdrop:not(.leaving)')) return;
        // Typing a paragraph: Escape (or ⌘Return) finishes it, it doesn't close the preview.
        if (e.target.closest && e.target.closest('.dp-edit') && (e.key === 'Escape' || (e.key === 'Enter' && (e.metaKey || e.ctrlKey)))) {
          e.preventDefault(); e.stopPropagation(); e.target.blur(); return;
        }
        const mod = e.metaKey || e.ctrlKey;
        if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(saved ? { ok: true, saved: true, path: saved.path } : { ok: true, saved: false }); }
        else if (mod && e.key.toLowerCase() === 's' && !actions) { e.preventDefault(); e.stopPropagation(); doSave(); }
        else if (mod && (e.key === '=' || e.key === '+')) { e.preventDefault(); fitted = false; setZoom(zoom + 0.1); }
        else if (mod && e.key === '-') { e.preventDefault(); fitted = false; setZoom(zoom - 0.1); }
        else if (mod && e.key === '0') { e.preventDefault(); fit(); }
      };
      let editor = null;
      const onResize = () => { if (fitted) fit(); if (editor) editor.relayout(); };
      document.addEventListener('keydown', onKey, true);
      window.addEventListener('resize', onResize);
      $('.dp-close').addEventListener('click', () => close(saved ? { ok: true, saved: true, path: saved.path } : { ok: true, saved: false }));
      $('.dp-cancel').addEventListener('click', () => close({ ok: true, saved: false }));
      if (actions) {
        for (const b of el.querySelectorAll('.dp-act')) b.addEventListener('click', () => close({ ok: true, saved: false, action: b.dataset.act }));
      } else $('.dp-save').addEventListener('click', doSave);
      $('.dp-zoom').addEventListener('click', (e) => {
        const b = e.target.closest('button');
        if (!b) return;
        if (b.dataset.zoom === 'fit') fit();
        else { fitted = false; setZoom(zoom + (b.dataset.zoom === 'in' ? 0.1 : -0.1)); }
      });
      el.addEventListener('mousedown', (e) => { if (e.target === el) close(saved ? { ok: true, saved: true, path: saved.path } : { ok: true, saved: false }); });

      (async () => {
        let note;
        try {
          note = await ready(pages);
        } catch (e) {
          el.remove();
          document.removeEventListener('keydown', onKey, true);
          window.removeEventListener('resize', onResize);
          if (discard) discard();
          resolve({ ok: false, error: e.message || 'The preview couldn’t be shown.' });
          return;
        }
        $('.dp-loading').remove();
        if (note) $('.dp-sub').textContent = note;
        fit();
        el.classList.add('ready');
        for (const b of el.querySelectorAll('.dp-save, .dp-act')) b.disabled = false;
        const first = $('.dp-act.primary') || $('.dp-save');
        if (first) first.focus();
        if (edit) editor = setupEdit(el, edit, async () => {
          // Drawn again with the paragraphs, keeping the place on the page.
          const canvas = $('.dp-canvas');
          const at = canvas.scrollTop / Math.max(1, canvas.scrollHeight);
          canvas.classList.add('dp-updating');
          try {
            const n = await edit.rebuild(pages);
            if (n) $('.dp-sub').textContent = n;
          } catch (e) { window.appAlert(e.message || 'The preview couldn’t be drawn again.'); }
          canvas.classList.remove('dp-updating');
          if (fitted) fit(); else setZoom(zoom);
          canvas.scrollTop = at * canvas.scrollHeight;
        });
      })();
    });
  }

  // ---------- Editing on the page (Edit) ----------
  // Resting the pointer between two lines shows where a paragraph would go;
  // a click opens a box right there on the page, with a small toolbar (bold,
  // italic, underline, bulleted and numbered lists). A paragraph you added
  // is changed by clicking it. Each is kept with the document, at its line
  // (window.api.docEdits; Sources/DocInserts.swift): saved on leaving the
  // box (or ⌘Return; Escape leaves it as it was), then the preview is drawn
  // again with it in place. List shows them all beside the pages (and adds
  // after the table or at the end; any whose line has gone are there too).
  const EDIT_CSS = `
    .dpe-layer { position: absolute; inset: 0; z-index: 3; cursor: text; }
    .dpe-caret { position: absolute; left: 7%; right: 7%; height: 0; border-top: 2px solid #e8783a; pointer-events: none; }
    .dpe-caret::before { content: '+'; position: absolute; left: -22px; top: -11px; width: 18px; height: 18px; border-radius: 50%; background: #e8783a; color: #fff;
      font: 600 14px/18px -apple-system, system-ui, sans-serif; text-align: center; }
    .dpe-caret span { position: absolute; right: 0; top: -22px; padding: 1px 7px; border-radius: 6px; background: #e8783a; color: #fff; font: 500 11px/18px -apple-system, system-ui, sans-serif; white-space: nowrap; }
    .dpe-mine { position: absolute; left: 7%; right: 7%; border-radius: 4px; background: rgba(232, 120, 58, .08); box-shadow: inset 0 0 0 1px rgba(232, 120, 58, .45); pointer-events: none; }
    .dpe-box { position: absolute; left: 8%; right: 8%; z-index: 4; }
    .dpe-tools { position: absolute; bottom: 100%; left: 0; margin-bottom: 6px; display: flex; gap: 2px; padding: 3px; border-radius: 9px; background: #1f2126; box-shadow: 0 6px 20px rgba(0, 0, 0, .28); }
    .dpe-tools button { min-width: 28px; height: 26px; padding: 0 7px; border: 0; border-radius: 6px; background: none; color: #e9eaee; font: 600 13px -apple-system, system-ui, sans-serif; cursor: default; }
    .dpe-tools button:hover { background: rgba(255, 255, 255, .12); }
    .dpe-tools .sep { width: 1px; margin: 4px 3px; background: rgba(255, 255, 255, .18); }
    .dpe-tools .del { color: #ff8b80; }
    .dpe-ed { min-height: 1.6em; padding: 4px 6px; border-radius: 4px; outline: 2px solid #e8783a; background: #fff; color: #000;
      font-family: 'EB Garamond', Georgia, serif; font-size: 14.67px; line-height: 1.38; text-align: justify; }
    .dpe-ed:empty::before { content: 'Type your paragraph…'; color: #999; }
    .dpe-ed ul, .dpe-ed ol { margin: 0; padding-left: 1.4em; }`;
  function editStyles(root) {
    const where = root || document.head;
    if (where.querySelector(':scope > style.dpe-css')) return;
    const st = document.createElement('style');
    st.className = 'dpe-css';
    st.textContent = EDIT_CSS;
    where.appendChild(st);
  }

  // Stored text (**bold**, *italic*, __underline__, a line each) ⇄ the box.
  function fromMarkup(text) {
    return String(text || '').split('\n').map((line) => {
      const h = esc(line).replace(/\*\*(?=\S)(.+?)(?<=\S)\*\*/g, '<b>$1</b>').replace(/__(?=\S)(.+?)(?<=\S)__/g, '<u>$1</u>')
        .replace(/(^|[^*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![*\w])/g, '$1<i>$2</i>');
      return `<div>${h || '<br>'}</div>`;
    }).join('');
  }
  function toMarkup(root) {
    const lines = [];
    let line = '';
    const flush = () => { lines.push(line.replace(/\s+$/, '')); line = ''; };
    const walk = (node) => {
      for (const n of node.childNodes) {
        if (n.nodeType === 3) { line += n.nodeValue.replace(/\s+/g, ' '); continue; }
        if (n.nodeType !== 1) continue;
        const tag = n.tagName;
        if (tag === 'BR') { flush(); continue; }
        if (tag === 'UL' || tag === 'OL') {
          if (line.trim()) flush();
          [...n.children].forEach((li, i) => { line = tag === 'UL' ? '• ' : `${i + 1}. `; walk(li); flush(); });
          continue;
        }
        const weight = n.style && n.style.fontWeight;
        const mark = tag === 'B' || tag === 'STRONG' || /bold|[6-9]00/.test(weight || '') ? '**'
          : tag === 'I' || tag === 'EM' || (n.style && n.style.fontStyle === 'italic') ? '*'
            : tag === 'U' || (n.style && /underline/.test(n.style.textDecoration || '')) ? '__' : '';
        const block = /^(DIV|P|LI|H\d)$/.test(tag);
        if (block && line.trim()) flush();
        if (mark) {
          const before = line;
          line = '';
          walk(n);
          const inner = line;
          const body = inner.trim();
          line = before + (body ? `${inner.match(/^\s*/)[0]}${mark}${body}${mark}${inner.match(/\s*$/)[0]}` : inner);
        } else walk(n);
        if (block) flush();
      }
    };
    walk(root);
    if (line.trim()) flush();
    return lines.filter((l, i, all) => l || (i > 0 && all[i - 1])).join('\n').trim();
  }
  const plainText = (t) => String(t || '').replace(/\*\*|__|\*/g, '').replace(/^\s*(•|\d+\.)\s+/, '');

  // The lines and added paragraphs in the order they're drawn (as Sources/DocInserts.swift docBlocks).
  function blocksOf(state) {
    const out = [];
    const placed = new Set();
    const added = (key, after) => {
      for (const p of state.inserts) if (p.anchor === key && p.after === after && p.text.trim()) { placed.add(p.id); out.push({ insert: p.id, text: p.text }); }
    };
    for (const a of state.anchors) {
      added(a.key, false);
      if (a.text) out.push({ key: a.key, text: a.text });
      added(a.key, true);
    }
    for (const p of state.inserts) if (!placed.has(p.id) && p.text.trim()) out.push({ insert: p.id, text: p.text });
    return out;
  }

  // The Word preview: each block found in the drawn pages by its first words.
  function locateInDocx(holder, blocks) {
    let full = '';
    const map = [];
    const walker = document.createTreeWalker(holder, NodeFilter.SHOW_TEXT);
    for (let n = walker.nextNode(); n; n = walker.nextNode()) {
      for (const ch of n.nodeValue.toLowerCase()) {
        const c = /\s/.test(ch) ? ' ' : ch;
        if (c === ' ' && full.endsWith(' ')) continue;
        full += c;
        map.push(n);
      }
    }
    const out = [];
    let from = 0;
    for (const b of blocks) {
      const words = plainText(b.text).toLowerCase().split(/\s+/).filter(Boolean).slice(0, 4).join(' ');
      const at = words ? full.indexOf(words, from) : -1;
      if (at < 0) continue;
      from = at + words.length;
      const line = map[at].parentElement.closest('p, tr') || map[at].parentElement;
      const host = line.closest('section.docx');
      if (!host) continue;
      const hr = host.getBoundingClientRect();
      out.push({ key: b.key, insert: b.insert, host, top: (line.getBoundingClientRect().top - hr.top) * host.offsetHeight / Math.max(1, hr.height) });
    }
    return out;
  }

  function setupEdit(el, edit, redraw) {
    const button = el.querySelector('.dp-edit-btn');
    const listBtn = el.querySelector('.dp-list-btn');
    const panel = el.querySelector('.dp-edit');
    let state = null;
    let editing = false;
    let saving = Promise.resolve();
    const newId = () => `p${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
    editStyles();

    // ---- the List panel ----
    const card = (p) => `<div class="dpe-card" data-id="${esc(p.id)}"><textarea rows="3" placeholder="Your paragraph…">${esc(p.text)}</textarea>
      <button type="button" class="dpe-del" data-no-icon title="Remove this paragraph" aria-label="Remove">${ICON.close}</button></div>`;
    const drawList = () => {
      if (panel.hidden) return;
      if (!state.ok) { panel.innerHTML = `<div class="dpe-head"><b>Your paragraphs</b></div><p class="dpe-empty">${esc(state.error || 'Paragraphs can’t be added to this document.')}</p>`; return; }
      const keys = new Set(state.anchors.map((a) => a.key));
      const at = (key, after) => state.inserts.filter((p) => p.anchor === key && p.after === after).map(card).join('');
      const lost = state.inserts.filter((p) => !keys.has(p.anchor));
      panel.innerHTML = `<div class="dpe-head"><b>Your paragraphs</b><span>Click between lines on the page to add one there. Kept with this document, in every PDF and Word copy.</span></div>
        <div class="dpe-list">
        ${lost.length ? `<div class="dpe-lost"><div class="dpe-label">Their line has changed: printed at the end</div>${lost.map(card).join('')}</div>` : ''}
        ${state.anchors.map((a) => `${at(a.key, false)}
          <div class="dpe-line${a.text ? '' : ' place'}" data-key="${esc(a.key)}">
            <span class="dpe-label">${esc(a.label)}</span>${a.text ? `<span class="dpe-text">${esc(plainText(a.text))}</span>` : ''}
            <span class="dpe-adds">${a.text ? '<button type="button" data-after="0" data-no-icon>+ Above</button><button type="button" data-after="1" data-no-icon>+ Below</button>'
              : '<button type="button" data-after="1" data-no-icon>+ Add here</button>'}</span>
          </div>${at(a.key, true)}`).join('')}
        </div>`;
    };

    // ---- on the page ----
    const layers = () => [...el.querySelectorAll('.dp-page'), ...[...el.querySelectorAll('.dp-docx-host')].flatMap((h) => (h.shadowRoot ? [...h.shadowRoot.querySelectorAll('section.docx')] : []))];
    const clearLayers = () => { for (const host of layers()) for (const x of host.querySelectorAll(':scope > .dpe-layer, :scope > .dpe-box')) x.remove(); };
    const drawLayers = async () => {
      clearLayers();
      if (!editing || !state || !state.ok) return;
      let spots = [];
      try { spots = await edit.locate(blocksOf(state)); } catch (e) { spots = []; }
      const byHost = new Map();
      for (const s of spots) { if (!byHost.has(s.host)) byHost.set(s.host, []); byHost.get(s.host).push(s); }
      for (const [host, list] of byHost) {
        const root = host.getRootNode();
        if (root !== document) editStyles(root);
        list.sort((a, b) => a.top - b.top);
        const layer = document.createElement('div');
        layer.className = 'dpe-layer';
        layer.innerHTML = '<div class="dpe-caret" hidden><span></span></div><div class="dpe-mine" hidden></div>';
        host.appendChild(layer);
        const caret = layer.querySelector('.dpe-caret');
        const mine = layer.querySelector('.dpe-mine');
        let target = null;
        const yOf = (e) => { const r = host.getBoundingClientRect(); return (e.clientY - r.top) * host.offsetHeight / Math.max(1, r.height); };
        layer.addEventListener('mousemove', (e) => {
          const y = yOf(e);
          let i = -1;
          for (let k = 0; k < list.length; k++) if (list[k].top <= y + 6) i = k;
          caret.hidden = true; mine.hidden = true; target = null;
          if (i < 0) return;
          const cur = list[i];
          const bottom = list[i + 1] ? list[i + 1].top : cur.top + 36;
          if (cur.insert) {
            target = { edit: cur.insert, y: cur.top - 4 };
            mine.style.top = `${cur.top - 5}px`;
            mine.style.height = `${Math.max(20, bottom - cur.top)}px`;
            mine.hidden = false;
            return;
          }
          const after = y > (cur.top + bottom) / 2;
          target = { anchor: cur.key, after, y: (after ? bottom : cur.top) - 4 };
          caret.style.top = `${target.y}px`;
          caret.querySelector('span').textContent = after ? 'Add a paragraph below' : 'Add a paragraph above';
          caret.hidden = false;
        });
        layer.addEventListener('mouseleave', () => { caret.hidden = true; mine.hidden = true; });
        layer.addEventListener('click', () => { if (target) openBox(host, target); });
      }
    };

    const persist = () => {
      saving = saving.then(async () => {
        const kept = state.inserts.filter((p) => p.text.trim()).map(({ id, anchor, after, text }) => ({ id, anchor, after, text }));
        const r = await window.api.docEdits.save(edit.id, kept);
        if (!r || !r.ok) { window.appAlert((r && r.error) || 'The paragraph couldn’t be saved.'); return; }
        state.inserts = kept;
        drawList();
        await redraw();
        await drawLayers();
      });
      return saving;
    };

    // The box on the page, where the paragraph goes (or the one clicked).
    const openBox = (host, target) => {
      for (const x of el.querySelectorAll('.dpe-box')) x.remove();
      const existing = target.edit ? state.inserts.find((p) => p.id === target.edit) : null;
      const box = document.createElement('div');
      box.className = 'dpe-box';
      box.style.top = `${target.y}px`;
      box.innerHTML = `<div class="dpe-tools" role="toolbar" aria-label="Formatting">
          <button type="button" data-cmd="bold" title="Bold (⌘B)"><b>B</b></button><button type="button" data-cmd="italic" title="Italic (⌘I)"><i>I</i></button><button type="button" data-cmd="underline" title="Underline (⌘U)"><u>U</u></button>
          <span class="sep"></span><button type="button" data-cmd="insertUnorderedList" title="Bulleted list">•</button><button type="button" data-cmd="insertOrderedList" title="Numbered list">1.</button>
          ${existing ? '<span class="sep"></span><button type="button" class="del" data-cmd="remove" title="Remove this paragraph">Remove</button>' : ''}
        </div><div class="dpe-ed" contenteditable="true" spellcheck="true"></div>`;
      host.appendChild(box);
      const ed = box.querySelector('.dpe-ed');
      ed.innerHTML = existing ? fromMarkup(existing.text) : '';
      let done = false;
      const finish = (keep, remove) => {
        if (done) return;
        done = true;
        const md = remove ? '' : toMarkup(ed);
        box.remove();
        if (!keep) return;
        if (existing) {
          if (md === existing.text) return;
          if (!md) state.inserts = state.inserts.filter((p) => p !== existing); else existing.text = md;
        } else {
          if (!md) return;
          state.inserts.push({ id: newId(), anchor: target.anchor, after: target.after, text: md });
        }
        persist();
      };
      box.addEventListener('mousedown', (e) => { if (e.target.closest('.dpe-tools')) e.preventDefault(); });
      box.querySelector('.dpe-tools').addEventListener('click', (e) => {
        const b = e.target.closest('[data-cmd]');
        if (!b) return;
        if (b.dataset.cmd === 'remove') { finish(true, true); return; }
        ed.focus();
        document.execCommand(b.dataset.cmd, false, null);
      });
      ed.addEventListener('keydown', (e) => {
        const style = { b: 'bold', i: 'italic', u: 'underline' }[(e.metaKey || e.ctrlKey) && !e.altKey ? e.key.toLowerCase() : ''];
        if (style) { e.preventDefault(); e.stopPropagation(); document.execCommand(style, false, null); return; }
        if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); finish(false); }
        else if (e.key === 'Enter' && (e.metaKey || e.ctrlKey)) { e.preventDefault(); e.stopPropagation(); finish(true); }
      });
      ed.addEventListener('focusout', (e) => { if (!box.contains(e.relatedTarget)) setTimeout(() => { if (!box.contains(document.activeElement && document.activeElement.shadowRoot ? document.activeElement.shadowRoot.activeElement : document.activeElement)) finish(true); }, 0); });
      requestAnimationFrame(() => {
        ed.focus();
        const sel = (host.getRootNode().getSelection ? host.getRootNode() : window).getSelection();
        if (sel) { sel.selectAllChildren(ed); sel.collapseToEnd(); }
      });
    };

    const load = async () => {
      if (state) return;
      try { state = await window.api.docEdits.get(edit.id); } catch (e) { state = { ok: false, error: e.message }; }
      state = state || { ok: false };
      state.anchors = state.anchors || [];
      state.inserts = state.inserts || [];
    };
    const setEditing = async (on) => {
      editing = on;
      el.classList.toggle('dp-editing', on);
      button.classList.toggle('on', on);
      button.setAttribute('aria-pressed', String(on));
      listBtn.hidden = !on;
      if (!on) { panel.hidden = true; listBtn.classList.remove('on'); clearLayers(); return; }
      await load();
      if (!state.ok) { panel.hidden = false; listBtn.classList.add('on'); drawList(); return; }
      await drawLayers();
    };
    button.addEventListener('click', () => setEditing(!editing));
    listBtn.addEventListener('click', async () => {
      await load();
      panel.hidden = !panel.hidden;
      listBtn.classList.toggle('on', !panel.hidden);
      drawList();
    });
    // The list: + Above / + Below / + Add here, and changing one's text there.
    panel.addEventListener('click', (e) => {
      const add = e.target.closest('[data-after]');
      if (add) {
        const p = { id: newId(), anchor: add.closest('.dpe-line').dataset.key, after: add.dataset.after === '1', text: '' };
        state.inserts.push(p);
        drawList();
        const ta = panel.querySelector(`.dpe-card[data-id="${CSS.escape(p.id)}"] textarea`);
        if (ta) { ta.focus(); ta.scrollIntoView({ block: 'nearest' }); }
        return;
      }
      const del = e.target.closest('.dpe-del');
      if (del) {
        const id = del.closest('.dpe-card').dataset.id;
        const had = state.inserts.find((p) => p.id === id);
        state.inserts = state.inserts.filter((p) => p.id !== id);
        drawList();
        if (had && had.text.trim()) persist();
      }
    });
    panel.addEventListener('input', (e) => {
      const c = e.target.closest('.dpe-card');
      const p = c && state.inserts.find((x) => x.id === c.dataset.id);
      if (p) { p.text = e.target.value; p.dirty = true; }
    });
    panel.addEventListener('focusout', (e) => {
      const c = e.target.closest && e.target.closest('.dpe-card');
      const p = c && state.inserts.find((x) => x.id === c.dataset.id);
      if (!p || !p.dirty) return;
      delete p.dirty;
      persist();
    });
    // The zoom or the window changed: the places on the pages are worked out again.
    return { relayout: () => { if (editing) drawLayers(); } };
  }

  async function pdf(fetcher, opts = {}) {
    let token = null;
    const draw = async (box) => {
        const r = await fetcher();
        if (!r || !r.ok) throw new Error((r && r.error) || 'The PDF couldn’t be prepared.');
        token = r.token;
        box.innerHTML = (r.pages || []).map((p, i) => `
          <figure class="dp-page" style="--i:${Math.min(i, 10)}; width:${(p.width * 4 / 3).toFixed(1)}px">
            <img src="data:image/jpeg;base64,${p.image}" alt="Page ${i + 1}" draggable="false" />
            <figcaption>${i + 1}</figcaption>
          </figure>`).join('');
        const n = r.pageCount || (r.pages || []).length;
        const shown = (r.pages || []).length;
        return `${r.fileName || ''} · ${n} page${n === 1 ? '' : 's'}${shown < n ? ` (the first ${shown} shown)` : ''}`;
    };
    return run({
      kind: 'pdf',
      title: opts.title,
      fileName: opts.fileName || '',
      actions: opts.actions,
      note: opts.note,
      ready: draw,
      // Drawn again after an edit: the old file is let go first.
      edit: opts.edit && {
        id: opts.edit.id,
        rebuild: async (box) => { if (token) window.api.files.discardPreview(token); token = null; return draw(box); },
        // Where each line is on the pages (points from the top; the page is drawn 4/3 px a point).
        locate: async () => {
          const r = await window.api.docEdits.spots(opts.edit.id);
          const figs = [...document.querySelectorAll('.dp-backdrop:last-of-type .dp-page')];
          return r && r.ok ? r.spots.filter((s) => figs[s.page]).map((s) => ({ key: s.key, insert: s.insert, host: figs[s.page], top: s.top * 4 / 3 })) : [];
        },
      },
      save: () => window.api.files.savePreview(token),
      discard: () => { if (token) window.api.files.discardPreview(token); },
    });
  }

  // `edit: { id, bytes: async () => Uint8Array }`: the .docx made again after an edit.
  async function word({ bytes, fileName, title, save, edit }) {
    const draw = async (box) => {
        await loadVendor();
        box.innerHTML = '';
        // Drawn in its own shadow tree, so the app's styles (tables, colours,
        // dark mode) don't reach the document.
        const host = document.createElement('div');
        host.className = 'dp-docx-host';
        box.appendChild(host);
        const shadow = host.attachShadow({ mode: 'open' });
        shadow.innerHTML = `<style>${DOCX_CSS}</style><div class="dp-docx-styles"></div><div class="dp-docx"></div>`;
        const holder = shadow.querySelector('.dp-docx');
        await window.docx.renderAsync(new Blob([bytes]), holder, shadow.querySelector('.dp-docx-styles'), {
          className: 'docx', inWrapper: true, ignoreWidth: false, ignoreHeight: false, ignoreFonts: false,
          breakPages: true, renderHeaders: true, renderFooters: true, renderFootnotes: true, useBase64URL: true, experimental: true,
        });
        letterheadBands(holder);
        shareFonts(shadow);
        // docx-preview only breaks pages where the document itself does;
        // the rest are worked out here, as Word would (near enough).
        const count = paginate(holder);
        return `${fileName || ''} · ${count} page${count === 1 ? '' : 's'} (Word may break them slightly differently)`;
    };
    return run({
      kind: 'word',
      title,
      fileName,
      ready: draw,
      edit: edit && {
        id: edit.id,
        rebuild: async (box) => { bytes = await edit.bytes(); return draw(box); },
        locate: async (blocks) => {
          const host = document.querySelector('.dp-backdrop:last-of-type .dp-docx-host');
          const holder = host && host.shadowRoot && host.shadowRoot.querySelector('.dp-docx');
          return holder ? locateInDocx(holder, blocks) : [];
        },
      },
      save: () => save(false),
    });
  }

  const DOCX_CSS = `
    :host { display: block; }
    .dp-docx { color: #000; -webkit-font-smoothing: antialiased; }
    .docx-wrapper { background: transparent !important; padding: 0 !important; display: flex; flex-direction: column; align-items: center; }
    .docx-wrapper > section.docx { position: relative; margin: 0 0 22px !important; color: #000;
      box-shadow: 0 1px 3px rgba(0, 0, 0, .12), 0 8px 26px rgba(0, 0, 0, .14) !important; }
    table { table-layout: fixed !important; }
    section.dp-paged { overflow: hidden; }
    section.dp-lettered > header, section.dp-lettered > footer { display: none; }
    .dp-band { position: absolute; left: 0; overflow: hidden; pointer-events: none; }
    .dp-band.top { top: 0; }
    .dp-band.bottom { bottom: 0; }
    .dp-band img { display: block; max-width: none; }`;

  // Fonts declared inside a shadow tree aren't used by it in every browser
  // engine: the document's embedded fonts (EB Garamond) are declared on the
  // page itself too.
  function shareFonts(shadow) {
    const faces = [...shadow.querySelectorAll('style')].map((st) => (st.textContent.match(/@font-face\s*{[^}]*}/g) || []).join('\n')).join('\n');
    if (!faces.trim()) return;
    let style = document.getElementById('dp-docx-fonts');
    if (!style) { style = document.createElement('style'); style.id = 'dp-docx-fonts'; document.head.appendChild(style); }
    style.textContent = faces;
  }

  // The letterhead is a whole-page picture behind the text in Word. With
  // no page breaks here, it's shown as its top band (the logo) at the top
  // of each document and its bottom band (the address) at the end.
  function letterheadBands(holder) {
    for (const section of holder.querySelectorAll('section.docx')) {
      const pageH = parseFloat(section.style.minHeight) || 0;
      const img = [...section.querySelectorAll('header img')].find((i) => pageH && parseFloat(i.style.height) > pageH * 0.8);
      if (!img) continue;
      const H = parseFloat(img.style.height);
      const W = parseFloat(img.style.width);
      const top = H * 0.15;
      const bottom = H * 0.09;
      const band = (h, offset, where) => `<div class="dp-band ${where}" style="height:${h}pt;width:${W}pt" aria-hidden="true">` +
        `<img src="${img.src}" alt="" style="width:${W}pt;height:${H}pt;margin-top:${-offset}pt" /></div>`;
      section.insertAdjacentHTML('afterbegin', band(top, 0, 'top') + band(bottom, H - bottom, 'bottom'));
      section.classList.add('dp-lettered');
      section.style.paddingBottom = `${bottom + 14}pt`;
    }
  }

  // Splits each section that's longer than its page into pages: whole
  // paragraphs move to the next page, long tables are split between rows
  // (the heading row repeated), and a heading stays with what follows it.
  // Each page keeps the letterhead bands. Returns the number of pages.
  function paginate(holder) {
    const px = (pt) => parseFloat(pt) * 4 / 3;
    let count = 0;
    for (const first of [...holder.querySelectorAll('section.docx')]) {
      const pageH = px(first.style.minHeight);
      const css = getComputedStyle(first);
      const limit = pageH - parseFloat(css.paddingBottom);
      if (!pageH) { count++; continue; }
      let page = first;
      for (let guard = 0; guard < 200; guard++) {
        count++;
        page.style.height = `${pageH}px`;
        page.classList.add('dp-paged');
        const article = page.querySelector(':scope > article');
        if (!article) break;
        const blocks = [...article.children];
        const over = blocks.findIndex((b) => b.offsetTop + b.offsetHeight > limit + 0.5);
        if (over < 0) break;
        let moving = blocks.slice(over);
        const block = blocks[over];
        // A table: the rows that fit stay, the rest (under a copy of its
        // heading row) go on.
        let rest = null;
        if (block.tagName === 'TABLE' && block.rows.length > 3) {
          const rows = [...block.rows];
          const cut = rows.findIndex((r, i) => i > 0 && block.offsetTop + r.offsetTop + r.offsetHeight > limit + 0.5);
          if (cut > 1) {
            rest = block.cloneNode(false);
            for (const c of block.querySelectorAll(':scope > colgroup')) rest.appendChild(c.cloneNode(true));
            rest.appendChild(rows[0].cloneNode(true));
            for (const r of rows.slice(cut)) rest.appendChild(r);
            moving = [rest, ...blocks.slice(over + 1)];
          }
        }
        if (!rest) {
          // Nothing fits on this page any more; a block taller than a whole
          // page stays where it is.
          if (over === 0) break;
          // A short paragraph just before (a heading) goes with what follows.
          const prev = blocks[over - 1];
          if (over > 1 && prev.tagName === 'P' && prev.offsetHeight < 30 && /bold/.test(prev.innerHTML)) moving = [prev, ...moving];
        }
        const next = page.cloneNode(false);
        next.style.minHeight = first.style.minHeight;
        for (const part of page.children) {
          if (part === article) {
            const body = article.cloneNode(false);
            for (const m of moving) body.appendChild(m);
            next.appendChild(body);
          } else next.appendChild(part.cloneNode(true));
        }
        page.after(next);
        page = next;
      }
    }
    return count;
  }

  window.docPreview = { pdf, word };
})();

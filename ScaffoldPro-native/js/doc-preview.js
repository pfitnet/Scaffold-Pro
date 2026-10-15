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
// With `edit` (a quotation, invoice or delivery note: for a PDF
// `{ id, layout }`, layout() giving its Word layout; for Word, from
// js/docx-export.js) the header has Edit: the document's wording is changed
// right on the page, as in a word processor (setupEdit, below). Each change
// is kept with the document (window.api.docEdits; Sources/DocInserts.swift),
// so every PDF and Word copy has it.
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
    bullets: '<svg viewBox="0 0 20 20" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" aria-hidden="true"><circle cx="4" cy="5" r="1.2" fill="currentColor" stroke="none"/><circle cx="4" cy="10" r="1.2" fill="currentColor" stroke="none"/><circle cx="4" cy="15" r="1.2" fill="currentColor" stroke="none"/><path d="M8 5h9M8 10h9M8 15h9"/></svg>',
    numbers: '<svg viewBox="0 0 20 20" width="16" height="16" fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M8 5h9M8 10h9M8 15h9"/><path d="M3 3.6l1.2-.6v4" stroke-width="1.2"/><path d="M2.8 9c.3-.6 1.9-.8 1.9.3 0 .9-1.9 1.6-1.9 2.4h2" stroke-width="1.2"/><path d="M2.9 13.5h1.8l-1 1.2c.9 0 1.2.4 1.2.9 0 .9-1.5 1-2.1.4" stroke-width="1.2"/></svg>',
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
          ${editable ? `<span class="dp-saved" aria-live="polite"></span>
          <div class="dp-format" role="toolbar" aria-label="Formatting" hidden>
            <button type="button" data-cmd="bold" title="Bold (⌘B)" aria-label="Bold"><b>B</b></button>
            <button type="button" data-cmd="italic" title="Italic (⌘I)" aria-label="Italic"><i>I</i></button>
            <button type="button" data-cmd="underline" title="Underline (⌘U)" aria-label="Underline"><u>U</u></button>
            <span class="sep"></span>
            <button type="button" data-cmd="insertUnorderedList" title="Bulleted list" aria-label="Bulleted list">${ICON.bullets}</button>
            <button type="button" data-cmd="insertOrderedList" title="Numbered list" aria-label="Numbered list">${ICON.numbers}</button>
          </div>
          <button type="button" class="dp-edit-btn" aria-pressed="false" title="Change the wording on the page — kept with this document, in every PDF and Word copy">${ICON.pencil}<span>Edit</span></button>` : ''}
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
        // Changing the wording: finished (and kept) first.
        if (editor && editor.editing) { editor.finish().then(() => { if (!editor.editing) close(result); }); return; }
        if (editor) editor.dispose();
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
        // Typing on the page: its own keys (Escape puts the line back, it doesn't close the preview).
        if (editor && editor.key(e)) return;
        const mod = e.metaKey || e.ctrlKey;
        if (editor && editor.editing) {
          // Escape finishes changing; ⌘S waits until then (Save keeps the copy drawn with the changes).
          if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); editor.finish(); return; }
          if (mod && e.key.toLowerCase() === 's') { e.preventDefault(); e.stopPropagation(); return; }
        }
        if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); close(saved ? { ok: true, saved: true, path: saved.path } : { ok: true, saved: false }); }
        else if (mod && e.key.toLowerCase() === 's' && !actions) { e.preventDefault(); e.stopPropagation(); doSave(); }
        else if (mod && (e.key === '=' || e.key === '+')) { e.preventDefault(); fitted = false; setZoom(zoom + 0.1); }
        else if (mod && e.key === '-') { e.preventDefault(); fitted = false; setZoom(zoom - 0.1); }
        else if (mod && e.key === '0') { e.preventDefault(); fit(); }
      };
      let editor = null;
      const onResize = () => { if (fitted) fit(); };
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
        // While changing the wording, Save (and the other actions) wait for Done.
        const noteText = $('.dp-note') && $('.dp-note').textContent;
        if (edit) editor = setupEdit(el, edit, (editing) => {
          for (const b of el.querySelectorAll('.dp-save, .dp-act')) b.disabled = editing;
          if ($('.dp-note')) $('.dp-note').textContent = editing ? 'Click any wording to change it. Kept with this document, in every PDF and Word copy.' : noteText;
          if (fitted) fit(); else setZoom(zoom);
        });
      })();
    });
  }

  // ---------- Editing the document itself (Edit) ----------
  // Edit shows the document as pages you type on (laid out as the Word copy,
  // which matches the PDF): click any of its wording — the salutation, the
  // subject, the opening, an item's description, a heading, a note, a
  // paragraph of the terms — and change it there, with bold, italic,
  // underline and lists in the header (⌘B ⌘I ⌘U). Figures, totals and the
  // details at the top are worked out by the app and stay as they are.
  // Each change is kept with the document as that line's new wording
  // (window.api.docEdits, `replace`; Sources/DocInserts.swift), saved as you
  // leave it, so every PDF and Word copy has it. Done draws the preview again.
  const EDIT_CSS = `
    .dpe-unit { outline: none; border-radius: 2px; cursor: text; transition: box-shadow .15s ease, background-color .15s ease; }
    p.dpe-unit:hover { background-color: rgba(232, 120, 58, .06); box-shadow: 0 0 0 3px rgba(232, 120, 58, .06); }
    p.dpe-unit:focus { background-color: rgba(232, 120, 58, .07); box-shadow: 0 0 0 3px rgba(232, 120, 58, .07), 0 0 0 4px rgba(232, 120, 58, .45); }
    td.dpe-unit:hover { background-color: rgba(232, 120, 58, .06); }
    td.dpe-unit:focus { background-color: rgba(232, 120, 58, .07); box-shadow: inset 0 0 0 1.5px rgba(232, 120, 58, .6); }
    .dpe-on section.docx { cursor: default; }
    .dpe-unit ul, .dpe-unit ol { margin: 0; padding-left: 1.4em; }`;
  function editStyles(root) {
    if (root.querySelector(':scope > style.dpe-css')) return;
    const st = document.createElement('style');
    st.className = 'dpe-css';
    st.textContent = EDIT_CSS;
    root.appendChild(st);
  }

  // Stored text (**bold**, *italic*, __underline__, a line each) ⇄ the page.
  const inlineHTML = (line) => esc(line).replace(/\*\*(?=\S)(.+?)(?<=\S)\*\*/g, '<b>$1</b>').replace(/__(?=\S)(.+?)(?<=\S)__/g, '<u>$1</u>')
    .replace(/(^|[^*\w])\*(?=[^\s*])(.+?)(?<=[^\s*])\*(?![*\w])/g, '$1<i>$2</i>');
  const fromMarkup = (text) => String(text || '').split('\n').map(inlineHTML).join('<br>');
  // The page → stored text. Styles are read as drawn and marked where they
  // differ from the line's own (a subject that's bold and underlined all
  // through has no marks): the app's marks switch a style on or off.
  function toMarkup(root) {
    const flags = (el) => {
      const cs = getComputedStyle(el);
      let u = false;
      for (let e = el; e && e !== root.parentNode; e = e.parentElement) if (/underline/.test(getComputedStyle(e).textDecorationLine || '')) { u = true; break; }
      return { b: (parseInt(cs.fontWeight, 10) || 400) >= 600, i: cs.fontStyle === 'italic', u };
    };
    const lines = [[]];
    const last = () => lines[lines.length - 1];
    const hasText = () => last().some((r) => r.t.trim());
    const walk = (node) => {
      for (const n of node.childNodes) {
        // (Tabs are kept: "Model<Tab>: ZT14JC" lines its colon up.)
        if (n.nodeType === 3) { if (n.nodeValue) last().push({ t: n.nodeValue.replace(/[^\S\t]+/g, ' '), f: flags(n.parentElement) }); continue; }
        if (n.nodeType !== 1) continue;
        const tag = n.tagName;
        if (tag === 'BR') { lines.push([]); continue; }
        const block = /^(DIV|P|LI|H\d|UL|OL)$/.test(tag);
        if (block && hasText()) lines.push([]);
        if (tag === 'LI') last().push({ t: n.parentElement.tagName === 'OL' ? `${[...n.parentElement.children].indexOf(n) + 1}. ` : '• ', f: null });
        walk(n);
        if (block && hasText()) lines.push([]);
      }
    };
    walk(root);
    // The line's own style: what most of its letters have.
    const all = lines.flat().filter((r) => r.f);
    const total = all.reduce((n, r) => n + r.t.trim().length, 0);
    const most = (k) => all.reduce((n, r) => n + (r.f[k] ? r.t.trim().length : 0), 0) * 2 > total;
    const base = { b: most('b'), i: most('i'), u: most('u') };
    const marks = (f) => (f ? [f.b !== base.b && '**', f.u !== base.u && '__', f.i !== base.i && '*'].filter(Boolean) : []);
    const text = lines.map((runs) => {
      let out = '';
      let open = null;
      let buf = '';
      const emit = () => {
        const m = open || [];
        const body = buf.trim();
        if (!m.length || !body) out += buf;
        else out += `${buf.match(/^\s*/)[0]}${m.join('')}${body}${[...m].reverse().join('')}${buf.match(/\s*$/)[0]}`;
        buf = '';
      };
      for (const r of runs) {
        const m = marks(r.f);
        if (open && m.join() !== open.join()) emit();
        open = m;
        buf += r.t;
      }
      emit();
      return out.replace(/^ +| +$/g, '');
    });
    return text.filter((l, i, every) => l || (i > 0 && every[i - 1])).join('\n').trim();
  }
  // Style marks from the app ( bold,  italic,  underline) → markup.
  const unmark = (t) => String(t || '').replace(//g, '**').replace(//g, '*').replace(//g, '__');
  // Letters and figures only, to find a line among the pages whatever its spacing, wrapping or tabs.
  const bare = (t) => String(t || '').toLowerCase().replace(/[^\p{L}\p{N}]+/gu, '');

  // The document's wording in the order it's drawn (as Sources/DocInserts.swift
  // withInserts draws it): each line as it now reads, and paragraphs added beside one
  // (by an earlier version of Edit), which are changed the same way.
  function blocksOf(state) {
    const out = [];
    const placed = new Set();
    const added = (key, after) => {
      for (const p of state.inserts) if (!p.replace && p.anchor === key && p.after === after && p.text.trim()) { placed.add(p.id); out.push({ insert: p.id, row: key.startsWith('row:'), text: p.text }); }
    };
    for (const a of state.anchors) {
      added(a.key, false);
      const own = state.inserts.find((p) => p.replace && p.anchor === a.key);
      const text = own ? own.text : unmark(a.text);
      if (a.text && text.trim()) out.push({ key: a.key, row: a.key.startsWith('row:'), text });
      added(a.key, true);
    }
    for (const p of state.inserts) if (!p.replace && !placed.has(p.id) && p.text.trim()) out.push({ insert: p.id, text: p.text });
    return out;
  }

  function setupEdit(el, edit, after) {
    const button = el.querySelector('.dp-edit-btn');
    const bar = el.querySelector('.dp-format');
    const savedNote = el.querySelector('.dp-saved');
    const canvas = el.querySelector('.dp-canvas');
    const pages = el.querySelector('.dp-pages');
    let state = null;
    let units = [];
    let editing = false;
    let switching = false;
    let changed = false;
    let saving = Promise.resolve();
    let savedTimer = 0;
    const newId = () => `r${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
    const deep = () => { let a = document.activeElement; while (a && a.shadowRoot && a.shadowRoot.activeElement) a = a.shadowRoot.activeElement; return a; };
    const current = () => { const a = deep(); return a && units.find((u) => u.el === a); };

    // Each line found on the pages by its words; it's editable only if the
    // place found holds just that line.
    const makeUnits = (holder) => {
      let full = '';
      const map = [];
      const walker = document.createTreeWalker(holder, NodeFilter.SHOW_TEXT);
      for (let n = walker.nextNode(); n; n = walker.nextNode()) {
        if (n.parentElement.closest('header, footer, .dp-band')) continue;
        for (const ch of bare(n.nodeValue)) { full += ch; map.push(n); }
      }
      const out = [];
      let from = 0;
      for (const b of blocksOf(state)) {
        const want = bare(b.text);
        const at = want ? full.indexOf(want.slice(0, 40), from) : -1;
        if (at < 0) continue;
        from = at + Math.min(want.length, 40);
        const node = map[at].parentElement;
        let box = b.row ? node.closest('td') : node.closest('p');
        if (box && box.tagName === 'TD' && box.querySelector('table')) box = node.closest('p'); // a lump sum's heading, above its list
        if (!box || out.some((u) => u.el === box || u.el.contains(box) || box.contains(u.el))) continue;
        if (bare(box.textContent) !== want) continue;
        from = at + want.length;
        if (box.tagName === 'TD') {
          // A table cell is drawn as wrapped lines: it's given its own text
          // (wrapped by the page), in the cell's font.
          const p = box.querySelector('p');
          const run = box.querySelector('span');
          const fresh = p ? p.cloneNode(false) : document.createElement('p');
          if (run) {
            const cs = getComputedStyle(run);
            for (const k of ['fontFamily', 'fontSize', 'fontWeight', 'fontStyle', 'textDecoration', 'color']) fresh.style[k] = cs[k];
          }
          fresh.innerHTML = fromMarkup(b.text);
          box.replaceChildren(fresh);
        }
        box.classList.add('dpe-unit');
        box.contentEditable = 'true';
        box.spellcheck = true;
        out.push({ el: box, key: b.key, insert: b.insert, html: box.innerHTML, original: toMarkup(box) });
      }
      return out;
    };

    const showSaved = (text) => {
      savedNote.textContent = text;
      savedNote.classList.add('show');
      clearTimeout(savedTimer);
      savedTimer = setTimeout(() => savedNote.classList.remove('show'), 1600);
    };
    const persist = () => {
      saving = saving.then(async () => {
        const list = state.inserts.map(({ id, anchor, after: below, text, replace }) => (replace ? { id, anchor, after: false, text, replace: true } : { id, anchor, after: below, text }));
        let r;
        try { r = await window.api.docEdits.save(edit.id, list); } catch (e) { r = { ok: false, error: e.message }; }
        if (!r || !r.ok) { window.appAlert((r && r.error) || 'Your change couldn’t be saved.'); return; }
        showSaved('Saved');
      });
      return saving;
    };
    // A line left: its new wording kept (the line as it was: the change let go).
    const commit = (u) => {
      const md = toMarkup(u.el);
      if (md === u.original) return;
      u.original = md;
      changed = true;
      if (u.insert) {
        const p = state.inserts.find((x) => x.id === u.insert);
        if (p) p.text = md;
        if (!md) state.inserts = state.inserts.filter((x) => x.id !== u.insert);
      } else {
        const anchor = state.anchors.find((a) => a.key === u.key);
        const own = state.inserts.find((x) => x.replace && x.anchor === u.key);
        if (anchor && md === unmark(anchor.text).trim()) state.inserts = state.inserts.filter((x) => x !== own);
        else if (own) own.text = md;
        else state.inserts.push({ id: newId(), anchor: u.key, after: false, replace: true, text: md });
      }
      persist();
    };
    const revert = (u) => { u.el.innerHTML = u.html; u.el.blur(); };

    const onFocusOut = (e) => {
      const u = units.find((x) => x.el === e.target);
      if (u) commit(u);
    };
    const syncBar = () => {
      if (!editing) return;
      const inUnit = !!current();
      for (const b of bar.querySelectorAll('[data-cmd]')) {
        b.disabled = !inUnit;
        let on = false;
        try { on = inUnit && document.queryCommandState(b.dataset.cmd); } catch (err) { on = false; }
        b.classList.toggle('on', on);
      }
    };

    const setEditing = async (on) => {
      if (switching || on === editing) return;
      switching = true;
      canvas.classList.add('dp-updating');
      const at = canvas.scrollTop / Math.max(1, canvas.scrollHeight);
      try {
        if (on) {
          let s;
          try { s = await window.api.docEdits.get(edit.id); } catch (e) { s = { ok: false, error: e.message }; }
          if (!s || !s.ok) { window.appAlert((s && s.error) || 'This document can’t be changed here.'); return; }
          state = { anchors: s.anchors || [], inserts: (s.inserts || []).map((p) => Object.assign({}, p)) };
          const holder = await edit.enter(pages);
          const root = holder.getRootNode();
          editStyles(root === document ? document.head : root);
          holder.classList.add('dpe-on');
          holder.addEventListener('focusout', onFocusOut);
          holder.title = 'Figures, totals and the details at the top are worked out by the app: change them in the editor.';
          units = makeUnits(holder);
          for (const u of units) u.el.title = 'Click to change the wording';
          editing = true;
          changed = false;
        } else {
          const u = current();
          if (u) { commit(u); u.el.blur(); }
          await saving;
          editing = false;
          units = [];
          const note = await edit.leave(pages, changed);
          if (note) el.querySelector('.dp-sub').textContent = note;
        }
        el.classList.toggle('dp-editing', editing);
        button.classList.toggle('on', editing);
        button.setAttribute('aria-pressed', String(editing));
        button.innerHTML = editing ? `${ICON.check}<span>Done</span>` : `${ICON.pencil}<span>Edit</span>`;
        button.title = editing ? 'Finish changing the wording (the preview is drawn again with it)' : 'Change the wording on the page — kept with this document, in every PDF and Word copy';
        bar.hidden = !editing;
        syncBar();
        after(editing);
      } catch (e) {
        window.appAlert(e.message || 'The document couldn’t be shown for changing.');
      } finally {
        canvas.classList.remove('dp-updating');
        switching = false;
        canvas.scrollTop = at * canvas.scrollHeight;
      }
    };
    button.addEventListener('click', () => setEditing(!editing));
    bar.addEventListener('mousedown', (e) => e.preventDefault()); // the cursor stays in the text
    bar.addEventListener('click', (e) => {
      const b = e.target.closest('[data-cmd]');
      if (!b || !current()) return;
      document.execCommand(b.dataset.cmd, false, null);
      syncBar();
    });
    document.addEventListener('selectionchange', syncBar);

    return {
      get editing() { return editing; },
      finish: () => setEditing(false),
      dispose: () => document.removeEventListener('selectionchange', syncBar),
      // Keys while typing in a line: ⌘B ⌘I ⌘U style it, Escape puts it back
      // as it was, ⌘Return finishes it. True when the key was used here.
      key: (e) => {
        const u = editing && current();
        if (!u) return false;
        const mod = (e.metaKey || e.ctrlKey) && !e.altKey;
        const style = { b: 'bold', i: 'italic', u: 'underline' }[mod ? e.key.toLowerCase() : ''];
        if (style) { e.preventDefault(); e.stopPropagation(); document.execCommand(style, false, null); syncBar(); return true; }
        if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); revert(u); return true; }
        if (e.key === 'Enter' && mod) { e.preventDefault(); e.stopPropagation(); u.el.blur(); return true; }
        return false;
      },
    };
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
      // Changed on the Word copy's pages (laid out as the PDF), shown in
      // place of the PDF's; then the PDF is made again (the old file let go).
      edit: opts.edit && {
        id: opts.edit.id,
        enter: async (box) => {
          const layout = await opts.edit.layout();
          if (!layout || !layout.ok) throw new Error((layout && layout.error) || 'The document couldn’t be prepared for changing.');
          const wrap = document.createElement('div');
          wrap.className = 'dp-editdoc';
          box.appendChild(wrap);
          const { holder } = await renderDocx(wrap, window.buildDocx(layout));
          for (const f of box.querySelectorAll('.dp-page')) f.style.display = 'none';
          return holder;
        },
        leave: async (box, changed) => {
          for (const w of box.querySelectorAll('.dp-editdoc')) w.remove();
          if (!changed) { for (const f of box.querySelectorAll('.dp-page')) f.style.display = ''; return null; }
          if (token) window.api.files.discardPreview(token);
          token = null;
          return draw(box);
        },
      },
      save: () => window.api.files.savePreview(token),
      discard: () => { if (token) window.api.files.discardPreview(token); },
    });
  }

  // `edit: { id, bytes: async () => Uint8Array }`: the .docx made again after an edit.
  async function word({ bytes, fileName, title, save, edit }) {
    const draw = async (box) => {
        box.innerHTML = '';
        const { count } = await renderDocx(box, bytes);
        return `${fileName || ''} · ${count} page${count === 1 ? '' : 's'} (Word may break them slightly differently)`;
    };
    return run({
      kind: 'word',
      title,
      fileName,
      ready: draw,
      // Changed on the pages shown; then the document is made again.
      edit: edit && {
        id: edit.id,
        enter: async (box) => box.querySelector('.dp-docx-host').shadowRoot.querySelector('.dp-docx'),
        leave: async (box, changed) => {
          if (!changed) {
            const holder = box.querySelector('.dp-docx-host').shadowRoot.querySelector('.dp-docx');
            for (const u of holder.querySelectorAll('.dpe-unit')) { u.classList.remove('dpe-unit'); u.removeAttribute('contenteditable'); u.removeAttribute('title'); }
            holder.classList.remove('dpe-on');
            holder.removeAttribute('title');
            return null;
          }
          bytes = await edit.bytes();
          return draw(box);
        },
      },
      save: () => save(false),
    });
  }

  // A .docx drawn into `box` by docx-preview, in its own shadow tree so the
  // app's styles (tables, colours, dark mode) don't reach the document.
  async function renderDocx(box, bytes) {
    await loadVendor();
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
    return { holder, count: paginate(holder) };
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

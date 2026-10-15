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
          ${editable ? `<button type="button" class="dp-edit-btn" aria-pressed="false" title="Add your own paragraphs above or below any line — kept with this document, in every PDF and Word copy">${ICON.pencil}<span>Edit</span></button>` : ''}
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
        if (edit) setupEdit(el, edit, async () => {
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

  // The Edit panel: the document's lines, each with + Above / + Below, and
  // the paragraphs added at them (a box each, saved on leaving it).
  function setupEdit(el, edit, redraw) {
    const button = el.querySelector('.dp-edit-btn');
    const panel = el.querySelector('.dp-edit');
    let state = null;
    let saving = Promise.resolve();
    const newId = () => `p${Date.now().toString(36)}${Math.random().toString(36).slice(2, 6)}`;
    const card = (p) => `<div class="dpe-card" data-id="${esc(p.id)}"><textarea rows="3" placeholder="Your paragraph…">${esc(p.text)}</textarea>
      <button type="button" class="dpe-del" data-no-icon title="Remove this paragraph" aria-label="Remove">${ICON.close}</button></div>`;
    const draw = () => {
      if (!state.ok) {
        panel.innerHTML = `<div class="dpe-head"><b>Add paragraphs</b></div><p class="dpe-empty">${esc(state.error || 'Paragraphs can’t be added to this document.')}</p>`;
        return;
      }
      const keys = new Set(state.anchors.map((a) => a.key));
      const at = (key, after) => state.inserts.filter((p) => p.anchor === key && p.after === after).map(card).join('');
      const lost = state.inserts.filter((p) => !keys.has(p.anchor));
      panel.innerHTML = `<div class="dpe-head"><b>Add paragraphs</b><span>Above or below any line. Kept with this document, in every PDF and Word copy.</span></div>
        <div class="dpe-list">
        ${lost.length ? `<div class="dpe-lost"><div class="dpe-label">Their line has changed: printed at the end</div>${lost.map(card).join('')}</div>` : ''}
        ${state.anchors.map((a) => `${at(a.key, false)}
          <div class="dpe-line${a.text ? '' : ' place'}" data-key="${esc(a.key)}">
            <span class="dpe-label">${esc(a.label)}</span>${a.text ? `<span class="dpe-text">${esc(a.text)}</span>` : ''}
            <span class="dpe-adds">${a.text ? '<button type="button" data-after="0" data-no-icon>+ Above</button><button type="button" data-after="1" data-no-icon>+ Below</button>'
              : '<button type="button" data-after="1" data-no-icon>+ Add here</button>'}</span>
          </div>${at(a.key, true)}`).join('')}
        </div>`;
    };
    const persist = () => {
      saving = saving.then(async () => {
        const kept = state.inserts.filter((p) => p.text.trim());
        const r = await window.api.docEdits.save(edit.id, kept);
        if (!r || !r.ok) { window.appAlert((r && r.error) || 'The paragraphs couldn’t be saved.'); return; }
        await redraw();
      });
      return saving;
    };
    const open = async (on) => {
      panel.hidden = !on;
      button.classList.toggle('on', on);
      button.setAttribute('aria-pressed', String(on));
      if (on && !state) {
        panel.innerHTML = '<p class="dpe-empty">Reading the document’s lines…</p>';
        try { state = await window.api.docEdits.get(edit.id); } catch (e) { state = { ok: false, error: e.message }; }
        state.inserts = state.inserts || [];
        draw();
      }
    };
    button.addEventListener('click', () => open(panel.hidden));
    panel.addEventListener('click', (e) => {
      const add = e.target.closest('[data-after]');
      if (add) {
        const p = { id: newId(), anchor: add.closest('.dpe-line').dataset.key, after: add.dataset.after === '1', text: '' };
        state.inserts.push(p);
        draw();
        const box = panel.querySelector(`.dpe-card[data-id="${CSS.escape(p.id)}"] textarea`);
        if (box) { box.focus(); box.scrollIntoView({ block: 'nearest' }); }
        return;
      }
      const del = e.target.closest('.dpe-del');
      if (del) {
        const id = del.closest('.dpe-card').dataset.id;
        const had = state.inserts.find((p) => p.id === id);
        state.inserts = state.inserts.filter((p) => p.id !== id);
        draw();
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
      edit: opts.edit && { id: opts.edit.id, rebuild: async (box) => { if (token) window.api.files.discardPreview(token); token = null; return draw(box); } },
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
      edit: edit && { id: edit.id, rebuild: async (box) => { bytes = await edit.bytes(); return draw(box); } },
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

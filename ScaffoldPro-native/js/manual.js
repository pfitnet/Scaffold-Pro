'use strict';

// The User Manual (manual.html): builds the contents list from the
// chapters, puts the numbered markers on each screenshot (positions from
// js/manual-shots.js, made with the screenshots), links each marker to its
// line in the legend, draws the workflow charts written as
// data-chain="kind|Title|detail > kind|Title|detail", and filters the
// chapters as you search.

(function () {
  const $ = (s, root = document) => root.querySelector(s);
  const $$ = (s, root = document) => [...root.querySelectorAll(s)];
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
  const SHOTS = window.MANUAL_SHOTS || {};

  // ---- workflow charts ----
  function chains() {
    for (const box of $$('[data-chain]')) {
      const parts = box.dataset.chain.split(/\s*(>|~>)\s*/);
      let html = '';
      for (const part of parts) {
        if (part === '>') { html += '<span class="mn-arrow" aria-hidden="true"></span>'; continue; }
        if (part === '~>') { html += '<span class="mn-arrow dash" aria-hidden="true"></span>'; continue; }
        // "a | b" alternatives stacked: kind|Title|detail || kind|Title|detail
        const alts = part.split(/\s*\|\|\s*/).map((alt) => {
          const [kind, title, detail, tag] = alt.split('|').map((x) => x.trim());
          return `<div class="mn-step k-${esc(kind)}">${tag ? `<i>${esc(tag)}</i>` : ''}<b>${esc(title)}</b>${detail ? `<span>${esc(detail)}</span>` : ''}</div>`;
        });
        html += alts.length > 1 ? `<div class="mn-branch">${alts.join('')}</div>` : alts[0];
      }
      box.classList.add('mn-chain');
      box.innerHTML = html;
      box.setAttribute('role', 'img');
      box.setAttribute('aria-label', parts.filter((p) => p !== '>' && p !== '~>').map((p) => p.split('|')[1]).join(', then '));
    }
  }

  // ---- annotated screenshots ----
  function shots() {
    for (const fig of $$('.mn-shot[data-shot]')) {
      const id = fig.dataset.shot;
      const data = SHOTS[id] || { marks: [] };
      const legend = $('.mn-legend', fig);
      const frame = document.createElement('div');
      frame.className = 'mn-frame';
      frame.innerHTML = `<img src="resources/manual/${esc(id)}.jpg" alt="${esc(fig.dataset.alt || id)}" loading="lazy" width="${data.w || 1440}" height="${data.h || 860}">`;
      const items = legend ? $$('li', legend) : [];
      // Many markers: the picture full width, the legend under it in two columns.
      if (items.length > 6) fig.classList.add('wide');
      (data.marks || []).forEach((m, i) => {
        if (!m || i >= items.length) return;
        const box = document.createElement('span');
        box.className = 'mn-box';
        box.dataset.i = i;
        Object.assign(box.style, { left: `${m.x}%`, top: `${m.y}%`, width: `${m.w}%`, height: `${m.h}%` });
        const mark = document.createElement('span');
        mark.className = 'mn-mark';
        mark.dataset.i = i;
        mark.textContent = i + 1;
        Object.assign(mark.style, { left: `${Math.min(m.x + 0.3, 98)}%`, top: `${Math.min(m.y + 0.6, 97)}%` });
        frame.append(box, mark);
      });
      fig.insertBefore(frame, fig.firstChild);
      const light = (i) => {
        frame.classList.toggle('on', i !== null);
        $$('.mn-box, .mn-mark', frame).forEach((x) => x.classList.toggle('on', String(i) === x.dataset.i));
        items.forEach((li, k) => li.classList.toggle('on', k === i));
      };
      items.forEach((li, i) => { li.addEventListener('mouseenter', () => light(i)); li.addEventListener('mouseleave', () => light(null)); });
      $$('.mn-mark', frame).forEach((m) => { m.addEventListener('mouseenter', () => light(+m.dataset.i)); m.addEventListener('mouseleave', () => light(null)); });
      frame.addEventListener('click', () => zoom(frame));
    }
  }

  function zoom(frame) {
    const back = document.createElement('div');
    back.className = 'mn-zoom';
    back.appendChild(frame.cloneNode(true));
    const close = () => { back.remove(); document.removeEventListener('keydown', onKey, true); };
    const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); close(); } };
    back.addEventListener('click', close);
    document.addEventListener('keydown', onKey, true);
    document.body.appendChild(back);
  }

  // ---- contents ----
  function toc() {
    const list = $('#mn-toc-list');
    let n = 0;
    let html = '';
    for (const ch of $$('.mn-ch')) {
      if (ch.dataset.part) html += `<li class="mn-part" data-part-for="${esc(ch.id)}">${esc(ch.dataset.part)}</li>`;
      n += 1;
      const h = $('h2', ch);
      const title = h.textContent.trim();
      h.insertAdjacentHTML('afterbegin', `<span class="mn-n">${n}</span>`);
      html += `<li data-for="${esc(ch.id)}"><a href="#${esc(ch.id)}"><b>${n}</b><span>${esc(title)}</span></a></li>`;
    }
    list.innerHTML = html;
    list.addEventListener('click', (e) => {
      const a = e.target.closest('a');
      if (!a) return;
      e.preventDefault();
      const target = document.getElementById(a.getAttribute('href').slice(1));
      if (target) target.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start' });
      history.replaceState(null, '', a.getAttribute('href'));
    });
    const links = new Map($$('a', list).map((a) => [a.getAttribute('href').slice(1), a]));
    const seen = new Set();
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) { if (e.isIntersecting) seen.add(e.target.id); else seen.delete(e.target.id); }
      const first = $$('.mn-ch').find((c) => seen.has(c.id));
      links.forEach((a, id) => a.classList.toggle('on', !!first && id === first.id));
    }, { rootMargin: '-10% 0px -70% 0px' });
    $$('.mn-ch').forEach((c) => io.observe(c));
  }

  // ---- search ----
  function search() {
    const box = $('#mn-search');
    const texts = $$('.mn-ch').map((ch) => [ch, ch.textContent.toLowerCase()]);
    box.addEventListener('input', () => {
      const words = box.value.trim().toLowerCase().split(/\s+/).filter(Boolean);
      for (const [ch, text] of texts) {
        const hit = !words.length || words.every((w) => text.includes(w));
        ch.classList.toggle('hidden-by-search', !hit);
        const li = $(`li[data-for="${ch.id}"]`);
        if (li) li.classList.toggle('hidden-by-search', !hit);
      }
      $$('li.mn-part').forEach((p) => {
        let next = p.nextElementSibling;
        let any = false;
        while (next && !next.classList.contains('mn-part')) { if (!next.classList.contains('hidden-by-search')) any = true; next = next.nextElementSibling; }
        p.classList.toggle('hidden-by-search', !any);
      });
    });
    document.addEventListener('keydown', (e) => {
      if (e.key === '/' && document.activeElement !== box && !/INPUT|TEXTAREA/.test(document.activeElement.tagName)) { e.preventDefault(); box.focus(); }
    });
  }

  chains();
  shots();
  toc();
  search();
  if (location.hash) { const t = document.getElementById(location.hash.slice(1)); if (t) setTimeout(() => t.scrollIntoView({ block: 'start' }), 50); }
})();

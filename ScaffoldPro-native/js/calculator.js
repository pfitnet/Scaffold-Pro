'use strict';

// A calculator in a small floating window, on every page (as the
// Assistant's chat): the calculator in the sidebar, or ⌥⌘C.
//   • Type a sum straight in — 2.07*4+1.5*12, 1,250 x 3, (12+8)/4, 15% — or
//     use the keys; the answer shows as you type.
//   • Return: the sum goes onto the tape below and its answer stays, ready
//     for the next step. Click a line on the tape to use its answer again.
//   • Copy puts the answer on the clipboard; Escape clears, or closes it
//     when there's nothing to clear.
// Dragged by its top bar; where it is, the tape, and whether it's open are
// kept on this Mac (open: across pages, like the chat). Sums are read by
// js/calc-input.js (window.calcEvaluate — no eval).

(function () {
  if (window.appCalculator) return;
  const OPEN_KEY = 'calc.open';
  const PLACE_KEY = 'calc.place';
  const TAPE_KEY = 'calc.tape';
  const EDGE = 8;
  const store = {
    get(k, s) { try { return (s ? sessionStorage : localStorage).getItem(k); } catch (e) { return null; } },
    set(k, v, s) { try { (s ? sessionStorage : localStorage).setItem(k, v); } catch (e) { /* not kept */ } },
  };
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  // 15% → 0.15; 200+10% → 200+20 (a percentage of what it's added to or taken from).
  function percent(text) {
    let s = String(text || '');
    s = s.replace(/([\d.,]+(?:\s*[×xX*÷/]\s*[\d.,]+)*)\s*([+\-−–])\s*([\d.,]+)\s*%/g, (m, base, op, p) => `${base}${op}(${base})*${p}/100`);
    return s.replace(/([\d.,]+)\s*%/g, '($1/100)');
  }
  function evaluate(text) {
    if (!window.calcEvaluate) return null;
    const v = window.calcEvaluate(percent(text));
    return v === null || !Number.isFinite(v) ? null : Math.round(v * 1e10) / 1e10;
  }
  const show = (v) => v.toLocaleString('en-US', { maximumFractionDigits: 10 });

  function build() {
    const panel = document.createElement('div');
    panel.id = 'calc-float';
    panel.className = 'calc-float hidden';
    panel.setAttribute('role', 'dialog');
    panel.setAttribute('aria-label', 'Calculator');
    panel.dataset.noIcon = '';
    const keys = [
      ['C', 'clear', 'fn'], ['⌫', 'back', 'fn'], ['%', '%', 'fn'], ['÷', '÷', 'op'],
      ['7', '7'], ['8', '8'], ['9', '9'], ['×', '×', 'op'],
      ['4', '4'], ['5', '5'], ['6', '6'], ['−', '-', 'op'],
      ['1', '1'], ['2', '2'], ['3', '3'], ['+', '+', 'op'],
      ['( )', 'paren', 'fn'], ['0', '0'], ['.', '.'], ['=', 'equals', 'eq'],
    ];
    const copyIcon = window.icon ? window.icon('duplicate', { size: 14 }) : 'Copy';
    panel.innerHTML = `
      <div class="calc-bar" title="Drag to move it">
        <span class="calc-title">${window.icon ? window.icon('accounts', { size: 15 }) : ''}<span>Calculator</span></span>
        <button type="button" class="calc-close" data-no-icon title="Close (Escape)" aria-label="Close">
          <svg viewBox="0 0 16 16" width="13" height="13" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" aria-hidden="true"><path d="M4 4l8 8M12 4l-8 8"/></svg></button>
      </div>
      <div class="calc-screen">
        <input class="calc-expr" type="text" inputmode="decimal" spellcheck="false" autocomplete="off" placeholder="0" aria-label="Sum" />
        <div class="calc-result" aria-live="polite"><span class="calc-answer"></span>
          <button type="button" class="calc-copy" data-no-icon title="Copy the answer" aria-label="Copy the answer">${copyIcon}</button></div>
      </div>
      <div class="calc-keys">${keys.map(([label, key, kind]) => `<button type="button" class="calc-key${kind ? ` ${kind}` : ''}" data-key="${esc(key)}" data-no-icon>${label}</button>`).join('')}</div>
      <div class="calc-tape-head"><span>Tape</span><button type="button" class="calc-tape-clear" data-no-icon>Clear</button></div>
      <ol class="calc-tape"></ol>`;
    document.body.appendChild(panel);
    return panel;
  }

  function init() {
    if (!document.body || document.getElementById('calc-float')) return;
    const page = document.body.dataset.page;
    if (!page || page === 'launch') return;
    const panel = build();
    const $ = (s) => panel.querySelector(s);
    const input = $('.calc-expr');
    const answer = $('.calc-answer');
    const tapeBox = $('.calc-tape');
    let tape = [];
    try { tape = JSON.parse(store.get(TAPE_KEY) || '[]'); } catch (e) { tape = []; }
    let last = null;
    // Just worked out: an operator carries on from the answer, a number starts afresh.
    let fresh = false;
    const carryOn = (key) => {
      if (!fresh) return;
      fresh = false;
      if (/^[+\-×÷*/%xX]$/.test(key)) { input.selectionStart = input.selectionEnd = input.value.length; }
      else if (/^[\d.(]$/.test(key)) { input.value = ''; }
    };

    const update = () => {
      const text = input.value.trim();
      const v = text ? evaluate(text) : null;
      last = v;
      answer.textContent = v === null ? (text ? '…' : '') : `= ${show(v)}`;
      panel.classList.toggle('has-answer', v !== null);
    };
    const drawTape = () => {
      tapeBox.innerHTML = tape.length ? tape.map((t, i) => `<li data-i="${i}" title="Use ${esc(show(t.v))}"><span class="calc-t-sum">${esc(t.s)}</span><b>${esc(show(t.v))}</b></li>`).join('')
        : '<li class="calc-t-empty">Sums you work out appear here.</li>';
      $('.calc-tape-clear').hidden = !tape.length;
    };
    const insert = (text) => {
      const s = input.selectionStart ?? input.value.length, e = input.selectionEnd ?? input.value.length;
      input.value = input.value.slice(0, s) + text + input.value.slice(e);
      input.selectionStart = input.selectionEnd = s + text.length;
      update();
    };
    const equals = () => {
      const text = input.value.trim();
      const v = text ? evaluate(text) : null;
      if (v === null) { panel.classList.remove('nudge'); void panel.offsetWidth; panel.classList.add('nudge'); return; }
      if (text !== show(v)) {
        tape.unshift({ s: text, v });
        tape = tape.slice(0, 40);
        store.set(TAPE_KEY, JSON.stringify(tape));
        drawTape();
      }
      input.value = show(v).replace(/,/g, '');
      update();
      input.selectionStart = input.selectionEnd = input.value.length;
      fresh = true;
    };
    const press = (key) => {
      input.focus();
      carryOn(key === 'paren' ? '(' : key);
      if (key === 'clear') { input.value = ''; update(); }
      else if (key === 'back') {
        const s = input.selectionStart ?? input.value.length, e = input.selectionEnd ?? s;
        if (s !== e) insert('');
        else if (s > 0) { input.value = input.value.slice(0, s - 1) + input.value.slice(s); input.selectionStart = input.selectionEnd = s - 1; update(); }
      } else if (key === 'equals') equals();
      else if (key === 'paren') {
        const open = (input.value.match(/\(/g) || []).length - (input.value.match(/\)/g) || []).length;
        insert(open > 0 && /[\d)%]$/.test(input.value.slice(0, input.selectionStart ?? input.value.length)) ? ')' : '(');
      } else insert(key);
    };

    // ---- open, close, and its place ----
    const isOpen = () => !panel.classList.contains('hidden');
    function place(p) {
      const vw = window.innerWidth, vh = window.innerHeight;
      const w = panel.offsetWidth, h = panel.offsetHeight;
      const topEdge = window.__scaffoldProWeb ? EDGE : 44;
      const left = Math.max(EDGE, Math.min(p.left, vw - w - EDGE));
      const top = Math.max(topEdge, Math.min(p.top, vh - h - EDGE));
      Object.assign(panel.style, { left: `${left}px`, top: `${top}px`, right: 'auto', bottom: 'auto' });
    }
    function placeSaved() {
      let saved = null;
      try { saved = JSON.parse(store.get(PLACE_KEY) || 'null'); } catch (e) { saved = null; }
      if (saved) place(saved);
      else { Object.assign(panel.style, { left: '', top: '', right: '', bottom: '' }); place({ left: panel.offsetLeft, top: panel.offsetTop }); }
    }
    function open(focus = true) {
      panel.classList.remove('hidden');
      if (focus) panel.classList.add('popping');
      placeSaved();
      store.set(OPEN_KEY, '1', true);
      if (focus) setTimeout(() => { input.focus(); input.select(); }, 0);
    }
    function close() {
      panel.classList.add('hidden');
      store.set(OPEN_KEY, '', true);
    }
    const toggle = () => (isOpen() ? close() : open());

    // ---- moved by its top bar ----
    $('.calc-bar').addEventListener('pointerdown', (e) => {
      if (e.button !== 0 || e.target.closest('button')) return;
      e.preventDefault();
      const start = { x: e.clientX, y: e.clientY, left: panel.offsetLeft, top: panel.offsetTop };
      panel.classList.add('dragging');
      const move = (ev) => place({ left: start.left + ev.clientX - start.x, top: start.top + ev.clientY - start.y });
      const up = () => {
        document.removeEventListener('pointermove', move);
        document.removeEventListener('pointerup', up);
        panel.classList.remove('dragging');
        store.set(PLACE_KEY, JSON.stringify({ left: panel.offsetLeft, top: panel.offsetTop }));
      };
      document.addEventListener('pointermove', move);
      document.addEventListener('pointerup', up);
    });
    $('.calc-bar').addEventListener('dblclick', (e) => {
      if (e.target.closest('button')) return;
      try { localStorage.removeItem(PLACE_KEY); } catch (err) { /* fine */ }
      placeSaved();
    });

    // ---- keys and typing ----
    panel.querySelector('.calc-keys').addEventListener('mousedown', (e) => e.preventDefault()); // the sum keeps the cursor
    panel.querySelector('.calc-keys').addEventListener('click', (e) => { const b = e.target.closest('.calc-key'); if (b) press(b.dataset.key); });
    input.addEventListener('input', update);
    input.addEventListener('keydown', (e) => {
      if (e.key.length === 1 && !e.metaKey && !e.ctrlKey) carryOn(e.key);
      else if (e.key !== 'Enter' && e.key !== 'Shift') fresh = false;
      if (e.key === 'Enter' || (e.key === '=' && !e.shiftKey)) { e.preventDefault(); equals(); }
      else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); if (input.value) { input.value = ''; update(); } else close(); }
      else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'c' && input.selectionStart === input.selectionEnd && last !== null) { e.preventDefault(); copy(); }
    });
    const copy = () => {
      if (last === null) return;
      const text = show(last).replace(/,/g, '');
      if (window.copyText) window.copyText(text); else if (navigator.clipboard) navigator.clipboard.writeText(text).catch(() => {});
      const b = $('.calc-copy');
      if (!window.icon) return;
      b.innerHTML = window.icon('check', { size: 14 });
      clearTimeout(copy.t);
      copy.t = setTimeout(() => { b.innerHTML = window.icon('duplicate', { size: 14 }); }, 1100);
    };
    $('.calc-copy').addEventListener('click', copy);
    $('.calc-close').addEventListener('click', close);
    panel.addEventListener('animationend', (e) => { if (e.target === panel) panel.classList.remove('popping', 'nudge'); });
    tapeBox.addEventListener('click', (e) => {
      const li = e.target.closest('li[data-i]');
      if (!li) return;
      input.focus();
      insert(show(tape[Number(li.dataset.i)].v).replace(/,/g, ''));
    });
    $('.calc-tape-clear').addEventListener('click', () => { tape = []; store.set(TAPE_KEY, '[]'); drawTape(); input.focus(); });
    document.addEventListener('keydown', (e) => {
      if (e.altKey && e.metaKey && !e.ctrlKey && (e.code === 'KeyC' || e.key.toLowerCase() === 'c')) { e.preventDefault(); toggle(); }
    });
    window.addEventListener('resize', () => { if (isOpen()) placeSaved(); });

    drawTape();
    update();
    window.appCalculator = { open, close, toggle };
    // Open on the page before: open here too (without taking the focus).
    if (store.get(OPEN_KEY, true) === '1') open(false);
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();

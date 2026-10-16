'use strict';

// A calculator in a small floating window, on every page (as the
// Assistant's chat): the calculator in the sidebar, or ⌥⌘C.
//   • Type a sum straight in — 2.07*4+1.5*12, 1,250 x 3, (12+8)/4, 15% — or
//     use the keys; the answer shows as you type.
//   • Return: the sum goes onto the tape below and its answer stays, ready
//     for the next step. Click a line on the tape to use its answer again.
//   • Copy puts the answer on the clipboard; Escape clears, or closes it
//     when there's nothing to clear. On the tape, copy a line or the whole
//     tape with its sums ("2.07*4 = 8.28"), oldest first.
//   • Powers, roots, trig (in degrees), logs and π: 2.5^2, sqrt(9), sin(30).
//   • Drag its corner to resize it; wide enough, it shows engineering keys.
// Moved, resized and kept open across pages by js/float-window.js; the tape
// is kept on this Mac. Sums are read by js/calc-input.js (window.calcEvaluate
// — no eval).

(function () {
  if (window.appCalculator) return;
  const TAPE_KEY = 'calc.tape';
  const MIN_W = 272, MIN_H = 380;
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
    // Engineering keys, shown once it's wide enough (css/calculator.css).
    // A function wraps what's selected, or the answer just worked out.
    const sci = [
      ['sin', 'sin', 'Sine (degrees)'], ['cos', 'cos', 'Cosine (degrees)'], ['tan', 'tan', 'Tangent (degrees)'],
      ['sin⁻¹', 'asin', 'Inverse sine, in degrees'], ['cos⁻¹', 'acos', 'Inverse cosine, in degrees'], ['tan⁻¹', 'atan', 'Inverse tangent, in degrees'],
      ['x²', '^2', 'Square'], ['x³', '^3', 'Cube'], ['xʸ', '^', 'To the power of'],
      ['√', 'sqrt', 'Square root'], ['∛', 'cbrt', 'Cube root'], ['1/x', '^-1', 'One over'],
      ['π', 'π', 'Pi'], ['log', 'log', 'Log, base 10'], ['ln', 'ln', 'Natural log'],
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
      <div class="calc-pad">
        <div class="calc-sci" aria-label="Engineering">${sci.map(([label, key, title]) => `<button type="button" class="calc-key sci" data-key="${esc(key)}" data-no-icon title="${esc(title)}">${label}</button>`).join('')}</div>
        <div class="calc-keys">${keys.map(([label, key, kind]) => `<button type="button" class="calc-key${kind ? ` ${kind}` : ''}" data-key="${esc(key)}" data-no-icon>${label}</button>`).join('')}</div>
      </div>
      <div class="calc-tape-head"><span>Tape</span>
        <span class="calc-tape-acts">
          <button type="button" class="calc-tape-copy" data-no-icon title="Copy the tape, with the sums" aria-label="Copy the tape, with the sums">${copyIcon}</button>
          <button type="button" class="calc-tape-clear" data-no-icon title="Clear the tape" aria-label="Clear the tape">${window.icon ? window.icon('trash', { size: 13 }) : 'Clear'}</button>
        </span></div>
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
      if (/^([+\-×÷*/%xX^]|\^-?\d)$/.test(key)) { input.selectionStart = input.selectionEnd = input.value.length; }
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
      tapeBox.innerHTML = tape.length ? tape.map((t, i) => `<li data-i="${i}" title="Use ${esc(show(t.v))}"><span class="calc-t-sum">${esc(t.s)}</span><b>${esc(show(t.v))}</b>
        <button type="button" class="calc-t-copy" data-no-icon title="Copy with its sum" aria-label="Copy with its sum">${window.icon ? window.icon('duplicate', { size: 12 }) : 'Copy'}</button></li>`).join('')
        : '<li class="calc-t-empty">Sums you work out appear here.</li>';
      $('.calc-tape-acts').hidden = !tape.length;
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
    // sin, sqrt…: around what's selected, the answer just worked out, or
    // opened for typing.
    const wrap = (fn) => {
      const s = input.selectionStart ?? input.value.length, e = input.selectionEnd ?? s;
      if (fresh || (s === 0 && e === input.value.length && input.value)) { input.value = `${fn}(${input.value})`; input.selectionStart = input.selectionEnd = input.value.length; update(); }
      else if (s !== e) insert(`${fn}(${input.value.slice(s, e)})`);
      else insert(`${fn}(`);
      fresh = false;
    };
    const press = (key) => {
      input.focus();
      if (/^[a-z]+$/.test(key) && key !== 'clear' && key !== 'back' && key !== 'equals' && key !== 'paren') { wrap(key); return; }
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

    // ---- moved, resized, opened and closed (js/float-window.js) ----
    const win = window.floatWindow(panel, {
      key: 'calc', minW: MIN_W, minH: MIN_H,
      gripTitle: 'Drag an edge or corner to resize: wider shows engineering keys. Double-click: back to small',
      onOpen: (focus) => { if (focus) setTimeout(() => { input.focus(); input.select(); }, 0); },
    });
    const { open, close, toggle } = win;

    // ---- keys and typing ----
    panel.querySelector('.calc-pad').addEventListener('mousedown', (e) => e.preventDefault()); // the sum keeps the cursor
    panel.querySelector('.calc-pad').addEventListener('click', (e) => { const b = e.target.closest('.calc-key'); if (b) press(b.dataset.key); });
    input.addEventListener('input', update);
    input.addEventListener('keydown', (e) => {
      if (e.key.length === 1 && !e.metaKey && !e.ctrlKey) carryOn(e.key);
      else if (e.key !== 'Enter' && e.key !== 'Shift') fresh = false;
      if (e.key === 'Enter' || (e.key === '=' && !e.shiftKey)) { e.preventDefault(); equals(); }
      else if (e.key === 'Escape') { e.preventDefault(); e.stopPropagation(); if (input.value) { input.value = ''; update(); } else close(); }
      else if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'c' && input.selectionStart === input.selectionEnd && last !== null) { e.preventDefault(); copy(); }
    });
    const toClipboard = (text, b, size) => {
      if (window.copyText) window.copyText(text); else if (navigator.clipboard) navigator.clipboard.writeText(text).catch(() => {});
      if (!window.icon || !b) return;
      b.innerHTML = window.icon('check', { size });
      clearTimeout(b.__t);
      b.__t = setTimeout(() => { b.innerHTML = window.icon('duplicate', { size }); }, 1100);
    };
    // A tape line with its sum: "2.07*4+1.5*12 = 26.28".
    const line = (t) => `${t.s} = ${show(t.v).replace(/,/g, '')}`;
    const copy = () => { if (last !== null) toClipboard(show(last).replace(/,/g, ''), $('.calc-copy'), 14); };
    $('.calc-copy').addEventListener('click', copy);
    $('.calc-close').addEventListener('click', close);
    tapeBox.addEventListener('click', (e) => {
      const li = e.target.closest('li[data-i]');
      if (!li) return;
      const c = e.target.closest('.calc-t-copy');
      if (c) { toClipboard(line(tape[Number(li.dataset.i)]), c, 12); return; }
      input.focus();
      insert(show(tape[Number(li.dataset.i)].v).replace(/,/g, ''));
    });
    $('.calc-tape-copy').addEventListener('click', (e) => toClipboard(tape.slice().reverse().map(line).join('\n'), e.currentTarget, 14));
    $('.calc-tape-clear').addEventListener('click', () => { tape = []; store.set(TAPE_KEY, '[]'); drawTape(); input.focus(); });
    document.addEventListener('keydown', (e) => {
      if (e.altKey && e.metaKey && !e.ctrlKey && (e.code === 'KeyC' || e.key.toLowerCase() === 'c')) { e.preventDefault(); toggle(); }
    });

    drawTape();
    update();
    window.appCalculator = { open, close, toggle };
    win.restore();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init);
  else init();
})();

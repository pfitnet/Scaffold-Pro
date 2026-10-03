'use strict';

// Sums in a line item's quantity or price box: type 14+28, 2 x 7, (3+2)*4
// or 120/4 and it's worked out. The sum is kept with the line; the box
// shows the result (with a small mark), and the sum again while you're in
// it. While typing a sum, "= 42" shows beside the box.
//
//   <input type="text" class="qty-input calc-input" data-formula="14+28" value="42">
//   const c = window.calcRead(input);   // { value: 42, formula: '14+28' } — or null
//                                       //   (not a number or sum: the box goes back)
//
// + − × ÷ and x, *, / all work; 1,250 is read as 1250.

(function () {
  if (window.calcRead) return;

  // Reads a sum (no eval): numbers, + - * / x × ÷, brackets, a leading minus.
  function evaluate(text) {
    const s = String(text || '').replace(/,/g, '').replace(/[×xX]/g, '*').replace(/÷/g, '/').replace(/[−–]/g, '-').replace(/\s+/g, '');
    if (!s || /[^0-9.+\-*/()]/.test(s)) return null;
    let i = 0;
    const peek = () => s[i];
    function number() {
      const m = /^\d*\.?\d+|^\d+\.?/.exec(s.slice(i));
      if (!m) throw new Error('number');
      i += m[0].length;
      return parseFloat(m[0]);
    }
    function factor() {
      if (peek() === '-') { i += 1; return -factor(); }
      if (peek() === '+') { i += 1; return factor(); }
      if (peek() === '(') {
        i += 1;
        const v = sum();
        if (peek() !== ')') throw new Error('bracket');
        i += 1;
        return v;
      }
      return number();
    }
    function product() {
      let v = factor();
      while (peek() === '*' || peek() === '/') {
        const op = s[i]; i += 1;
        const r = factor();
        v = op === '*' ? v * r : v / r;
      }
      return v;
    }
    function sum() {
      let v = product();
      while (peek() === '+' || peek() === '-') {
        const op = s[i]; i += 1;
        const r = product();
        v = op === '+' ? v + r : v - r;
      }
      return v;
    }
    try {
      const v = sum();
      return i === s.length && Number.isFinite(v) ? v : null;
    } catch (e) {
      return null;
    }
  }
  // A sum, not just a number (a lone "-5" or "1,250" isn't one).
  const isSum = (text) => /[0-9.)]\s*[+\-*/×xX÷−–]\s*[-(0-9.]/.test(String(text || '').replace(/,/g, ''));

  // What the box holds: its value and the sum (if it is one); null when it
  // isn't a number or a sum — then the box shows what it had.
  window.calcRead = function calcRead(input) {
    const text = input.value.trim();
    const value = evaluate(text);
    if (value === null) {
      input.classList.add('calc-bad');
      setTimeout(() => input.classList.remove('calc-bad'), 900);
      input.value = input.dataset.shown ?? input.defaultValue;
      return null;
    }
    return { value, formula: isSum(text) ? text : '' };
  };
  window.calcEvaluate = evaluate;

  // For the editors: the box's data-formula attribute, and its change → save(value, formula).
  window.calcAttr = (formula) => (formula ? `data-formula="${String(formula).replace(/&/g, '&amp;').replace(/"/g, '&quot;').replace(/</g, '&lt;')}"` : '');
  window.calcChange = function calcChange(input, save) {
    if (!input) return;
    input.addEventListener('change', () => {
      const c = window.calcRead(input);
      if (c) save(c.value, c.formula);
    });
  };

  // ---- In the box: the sum while editing, the result otherwise ----
  let bubble = null;
  function showBubble(input) {
    const text = input.value.trim();
    const v = isSum(text) ? evaluate(text) : null;
    if (v === null) { if (bubble) bubble.classList.remove('show'); return; }
    if (!bubble) {
      bubble = document.createElement('div');
      bubble.className = 'calc-bubble';
      bubble.setAttribute('aria-live', 'polite');
      document.body.appendChild(bubble);
    }
    bubble.textContent = `= ${v.toLocaleString('en-US', { maximumFractionDigits: 2 })}`;
    const r = input.getBoundingClientRect();
    bubble.style.left = `${Math.round(r.left)}px`;
    bubble.style.top = `${Math.round(r.top - 26)}px`;
    bubble.classList.add('show');
  }
  const hideBubble = () => { if (bubble) bubble.classList.remove('show'); };

  // The result as shown, and a mark on boxes that hold a sum.
  function mark(input) {
    if (input.dataset.shown === undefined) input.dataset.shown = input.value;
    const f = input.dataset.formula || '';
    input.classList.toggle('has-formula', !!f);
    if (f) input.title = `= ${f}  (click to see or change the sum)`;
  }
  const isCalc = (el) => el instanceof HTMLInputElement && el.classList.contains('calc-input');

  document.addEventListener('focusin', (e) => {
    const input = e.target;
    if (!isCalc(input)) return;
    mark(input);
    if (input.dataset.formula && input.value === input.dataset.shown) {
      input.value = input.dataset.formula;
      input.__savedValue = input.value; // (not typing yet, for ⌘Z — js/undo.js)
      // (Selected, ready to type over — as Tab into a quantity does.)
      requestAnimationFrame(() => { try { input.select(); } catch (err) { /* ignore */ } });
    }
    showBubble(input);
  });
  document.addEventListener('input', (e) => { if (isCalc(e.target)) showBubble(e.target); });
  document.addEventListener('focusout', (e) => {
    const input = e.target;
    if (!isCalc(input)) return;
    hideBubble();
    // Left unchanged: the result again.
    if (input.dataset.formula && input.value.trim() === input.dataset.formula) input.value = input.dataset.shown;
  });
  // ↑ / ↓ on a plain number: one more / one less, as the number boxes did.
  document.addEventListener('keydown', (e) => {
    if ((e.key !== 'ArrowUp' && e.key !== 'ArrowDown') || !isCalc(e.target) || e.altKey || e.metaKey || e.ctrlKey) return;
    const input = e.target;
    const text = input.value.trim().replace(/,/g, '');
    if (!/^-?\d+(\.\d+)?$/.test(text)) return;
    e.preventDefault();
    const step = e.shiftKey ? 10 : 1;
    const n = Number(text) + (e.key === 'ArrowUp' ? step : -step);
    const decimals = (text.split('.')[1] || '').length;
    input.value = decimals ? n.toFixed(decimals) : String(n);
    input.dispatchEvent(new Event('input', { bubbles: true }));
  });
  // Escape puts back what was there.
  document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || !isCalc(e.target)) return;
    const input = e.target;
    input.value = input.dataset.formula || input.dataset.shown || input.defaultValue;
    showBubble(input);
  });
  window.addEventListener('scroll', hideBubble, true);

  // Boxes drawn later (tables redrawn after a save) get their mark too.
  const scan = (root) => root.querySelectorAll && root.querySelectorAll('input.calc-input').forEach(mark);
  const start = () => {
    scan(document);
    new MutationObserver((ms) => { for (const m of ms) for (const n of m.addedNodes) if (n.nodeType === 1) { if (isCalc(n)) mark(n); else scan(n); } })
      .observe(document.body, { childList: true, subtree: true });
  };
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', start); else start();
})();

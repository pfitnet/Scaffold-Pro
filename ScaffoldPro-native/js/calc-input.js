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
// + − × ÷ and x, *, / all work; 1,250 is read as 1250. Powers, roots and
// the rest (see evaluate) work too: 2.5^2, sqrt(3^2+4^2), 6*sin(30).

(function () {
  if (window.calcRead) return;

  // Reads a sum (no eval): numbers (1,250 · 0.5 · 2e3), + - * / and x × ÷,
  // brackets, a leading minus, powers (2^3, 4², 2³), roots (sqrt(9), √9,
  // cbrt(27)), sin cos tan and asin acos atan in degrees, log (base 10), ln,
  // exp, abs, round, and π / pi / e. 2π and 3(4+1) multiply.
  const RAD = Math.PI / 180;
  const FN = {
    sqrt: Math.sqrt, cbrt: Math.cbrt, abs: Math.abs, ln: Math.log, log: Math.log10, exp: Math.exp, round: Math.round,
    sin: (d) => Math.sin(d * RAD), cos: (d) => Math.cos(d * RAD), tan: (d) => Math.tan(d * RAD),
    asin: (v) => Math.asin(v) / RAD, acos: (v) => Math.acos(v) / RAD, atan: (v) => Math.atan(v) / RAD,
  };
  const CONST = { pi: Math.PI, e: Math.E };
  const SYMBOL = { '×': '*', '÷': '/', '−': '-', '–': '-' };
  function tokens(text) {
    const src = String(text || '').replace(/,/g, '');
    const re = /\s*(?:((?:\d+\.?\d*|\.\d+)(?:[eE][+-]?\d+)?)|([a-zA-Z]+)|([-+*/^()×÷−–²³√π]))/y;
    const out = [];
    while (re.lastIndex < src.length) {
      const at = re.lastIndex;
      const m = re.exec(src);
      if (!m) { if (/^\s*$/.test(src.slice(at))) break; return null; }
      if (m[1] !== undefined) out.push({ n: parseFloat(m[1]) });
      else if (m[2] !== undefined) { const w = m[2].toLowerCase(); out.push(w === 'x' ? { o: '*' } : { w }); }
      else out.push({ o: SYMBOL[m[3]] || m[3] });
    }
    return out;
  }
  function evaluate(text) {
    const t = tokens(text);
    if (!t || !t.length) return null;
    let p = 0;
    const is = (o) => t[p] && t[p].o === o;
    function primary() {
      const k = t[p];
      if (!k) throw new Error('end');
      p += 1;
      if (k.n !== undefined) return k.n;
      if (k.o === '(') {
        const v = sum();
        if (!is(')')) throw new Error('bracket');
        p += 1;
        return v;
      }
      if (k.o === 'π') return Math.PI;
      if (k.o === '√') return Math.sqrt(postfix());
      if (k.w !== undefined) {
        if (k.w in CONST) return CONST[k.w];
        if (FN[k.w]) return FN[k.w](primary());
      }
      throw new Error('token');
    }
    function postfix() {
      let v = primary();
      while (is('²') || is('³')) { v **= t[p].o === '²' ? 2 : 3; p += 1; }
      return v;
    }
    // 2^3^2 = 2^9; -2^2 = -4; 2^-1 = 0.5.
    function power() {
      const b = postfix();
      if (!is('^')) return b;
      p += 1;
      return b ** unary();
    }
    function unary() {
      if (is('-')) { p += 1; return -unary(); }
      if (is('+')) { p += 1; return unary(); }
      return power();
    }
    const startsTerm = (k) => k && (k.o === '(' || k.o === 'π' || k.o === '√' || k.w !== undefined);
    function product() {
      let v = unary();
      for (;;) {
        if (is('*') || is('/')) {
          const op = t[p].o; p += 1;
          const r = unary();
          v = op === '*' ? v * r : v / r;
        } else if (startsTerm(t[p])) v *= power(); // 2π, 3(4+1), 2sqrt(9)
        else return v;
      }
    }
    function sum() {
      let v = product();
      while (is('+') || is('-')) {
        const op = t[p].o; p += 1;
        const r = product();
        v = op === '+' ? v + r : v - r;
      }
      return v;
    }
    try {
      const v = sum();
      return p === t.length && Number.isFinite(v) ? v : null;
    } catch (e) {
      return null;
    }
  }
  // A sum, not just a number (a lone "-5" or "1,250" isn't one).
  const isSum = (text) => {
    const t = String(text || '').replace(/,/g, '');
    return /[0-9.)]\s*[+\-*/×xX÷−–^]\s*[-(0-9.]/.test(t) || /[²³√π]|[a-z]{2,}/i.test(t);
  };

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
  // (↑ / ↓ go to the box above / below — js/controls.js.)
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

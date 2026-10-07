'use strict';

// The User Manual (manual.html, css/manual.css). Draws the chapters from
// js/manual-content.js: a cover with the parts, a contents rail, and each
// chapter as a few short, visual blocks: screenshots with numbered points
// (positions from js/manual-shots.js; hover a point to spotlight it, click
// the picture to enlarge it), flows, steps, cards, keys and tips.
// Search (/) filters the chapters.

(function () {
  const $ = (s, root = document) => root.querySelector(s);
  const $$ = (s, root = document) => [...root.querySelectorAll(s)];
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const CHAPTERS = window.MANUAL_CONTENT || [];
  const SHOTS = window.MANUAL_SHOTS || {};
  const still = () => matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---- icons (24 × 24, drawn with a line) ----
  const P = {
    grid: '<rect x="3.5" y="3.5" width="7" height="7" rx="2"/><rect x="13.5" y="3.5" width="7" height="7" rx="2"/><rect x="3.5" y="13.5" width="7" height="7" rx="2"/><rect x="13.5" y="13.5" width="7" height="7" rx="2"/>',
    home: '<path d="M3.5 11 12 4l8.5 7"/><path d="M5.5 9.5V20h13V9.5"/><path d="M10 20v-5.5h4V20"/>',
    people: '<circle cx="9" cy="8.5" r="3.2"/><circle cx="17" cy="9.5" r="2.4"/><path d="M3 19.5c.7-3.3 3-5 6-5s5.3 1.7 6 5M15.5 14.6c2.6-.2 4.6 1.3 5.3 4"/>',
    layers: '<path d="m12 3.5 8.5 4.5L12 12.5 3.5 8z"/><path d="m3.5 12 8.5 4.5 8.5-4.5"/><path d="m3.5 16 8.5 4.5 8.5-4.5"/>',
    building: '<rect x="4.5" y="3.5" width="15" height="17" rx="2"/><path d="M8.5 7.5h2M13.5 7.5h2M8.5 11.5h2M13.5 11.5h2M10 20.5v-4h4v4"/>',
    bolt: '<path d="M13 2.5 5 13.5h6l-1 8 8-11h-6z"/>',
    calendar: '<rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/><path d="M3.5 9.5h17M8 3v4M16 3v4"/>',
    'calendar-days': '<rect x="3.5" y="5" width="17" height="15.5" rx="2.5"/><path d="M3.5 9.5h17M8 3v4M16 3v4M7.5 13h2M11 13h2M14.5 13h2M7.5 16.5h2M11 16.5h2"/>',
    hash: '<path d="M9.5 3.5 7.5 20.5M16.5 3.5l-2 17M4 9h16.5M3.5 15H20"/>',
    pointer: '<path d="m5 3.5 13 7-5.6 1.7L10 18z"/><path d="m12.5 12.3 4.5 6.2"/>',
    drag: '<circle cx="9" cy="6" r="1.2"/><circle cx="15" cy="6" r="1.2"/><circle cx="9" cy="12" r="1.2"/><circle cx="15" cy="12" r="1.2"/><circle cx="9" cy="18" r="1.2"/><circle cx="15" cy="18" r="1.2"/>',
    sort: '<path d="M7 4v16M3.5 7.5 7 4l3.5 3.5M17 20V4M13.5 16.5 17 20l3.5-3.5"/>',
    eye: '<path d="M2.5 12S6 5.5 12 5.5 21.5 12 21.5 12 18 18.5 12 18.5 2.5 12 2.5 12z"/><circle cx="12" cy="12" r="3"/>',
    check: '<circle cx="12" cy="12" r="8.5"/><path d="m8.3 12.2 2.5 2.5 5-5.2"/>',
    route: '<circle cx="6" cy="18" r="2.5"/><circle cx="18" cy="6" r="2.5"/><path d="M8.5 18H15a3.5 3.5 0 0 0 0-7H9a3.5 3.5 0 0 1 0-7h6.5"/>',
    doc: '<path d="M14 3.5H7a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8.5z"/><path d="M14 3.5v5h5M8.5 13h7M8.5 16.5h5"/>',
    receipt: '<path d="M6 3.5h12v17l-2-1.4-2 1.4-2-1.4-2 1.4-2-1.4-2 1.4z"/><path d="M9 8.5h6M9 12h6M9 15.5h3.5"/>',
    bell: '<path d="M6 16.5V11a6 6 0 0 1 12 0v5.5l1.5 2h-15z"/><path d="M10 20.5a2.2 2.2 0 0 0 4 0"/>',
    resize: '<path d="M14 4h6v6M10 20H4v-6M20 4l-7 7M4 20l7-7"/>',
    trash: '<path d="M4.5 7h15M9.5 7V4.5h5V7M6.5 7l1 13h9l1-13M10 11v5.5M14 11v5.5"/>',
    chat: '<path d="M4 5.5h16v10.5H9.5L5 20v-4H4z"/><path d="M8 9.5h8M8 12.5h5"/>',
    pen: '<path d="M15.5 4.5 19.5 8.5 9 19H5v-4z"/><path d="m13.5 6.5 4 4"/>',
    tag: '<path d="M3.5 12V4.5h7.5l9.5 9.5-7.5 7.5z"/><circle cx="8" cy="9" r="1.4"/>',
    menu: '<path d="M4 7h16M4 12h16M4 17h16"/>',
    percent: '<path d="M19 5 5 19"/><circle cx="7" cy="7" r="2.3"/><circle cx="17" cy="17" r="2.3"/>',
    folder: '<path d="M3.5 7.5a2 2 0 0 1 2-2h4l2 2.2h7a2 2 0 0 1 2 2V17.5a2 2 0 0 1-2 2h-13a2 2 0 0 1-2-2z"/>',
    'folder-open': '<path d="M3.5 18V7.5a2 2 0 0 1 2-2h4l2 2.2h6a2 2 0 0 1 2 2v1.3"/><path d="M3.5 18 6 11.5h15L18.5 18z"/>',
    plus: '<path d="M12 5v14M5 12h14"/>',
    truck: '<path d="M2.5 6.5h11v9.5h-11z"/><path d="M13.5 9.5h4l3.5 3.5v3h-7.5"/><circle cx="6.5" cy="17.5" r="2"/><circle cx="17" cy="17.5" r="2"/>',
    mail: '<rect x="3.5" y="5.5" width="17" height="13" rx="2.2"/><path d="m4 7 8 6 8-6"/>',
    image: '<rect x="3.5" y="4.5" width="17" height="15" rx="2.2"/><circle cx="9" cy="9.5" r="1.8"/><path d="m4 17.5 5-4.5 4 3.5 3-2.5 4 3.5"/>',
    shield: '<path d="M12 3 19.5 6v5.5c0 4.5-3.2 8-7.5 9.5-4.3-1.5-7.5-5-7.5-9.5V6z"/><path d="m8.8 12 2.3 2.3 4.2-4.4"/>',
    clock: '<circle cx="12" cy="12" r="8.5"/><path d="M12 7.5V12l3 2"/>',
    note: '<path d="M5 4.5h14v10l-5 5H5z"/><path d="M14 19.5v-5h5M8.5 9h7M8.5 12h4.5"/>',
    print: '<path d="M7 8.5V3.5h10v5"/><rect x="3.5" y="8.5" width="17" height="8" rx="2"/><path d="M7 14h10v6.5H7z"/>',
    box: '<path d="m12 3 8.5 4.5v9L12 21l-8.5-4.5v-9z"/><path d="m3.5 7.5 8.5 4.5 8.5-4.5M12 12v9"/>',
    send: '<path d="M20.5 3.5 10 14M20.5 3.5l-6.5 17-4-6.5-6.5-4z"/>',
    money: '<rect x="2.5" y="6" width="19" height="12" rx="2.2"/><circle cx="12" cy="12" r="2.8"/><path d="M6 9.5v5M18 9.5v5"/>',
    flag: '<path d="M5.5 21V4M5.5 4.5h11l-2 4 2 4h-11"/>',
    clip: '<path d="m20 11.5-7.8 7.8a5 5 0 0 1-7-7l8.3-8.3a3.3 3.3 0 0 1 4.7 4.7l-8.2 8.2a1.6 1.6 0 0 1-2.3-2.3l7.5-7.5"/>',
    share: '<path d="M12 15V3.5M7.5 8 12 3.5 16.5 8"/><path d="M5 11.5v7a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2v-7"/>',
    stamp: '<path d="M9.5 3.5h5l-1 7h-3z"/><path d="M4.5 13.5a2 2 0 0 1 2-2h11a2 2 0 0 1 2 2v3h-15z"/><path d="M5.5 20.5h13"/>',
    rotate: '<path d="M4.5 12a7.5 7.5 0 0 1 13-5.1L20 9.5"/><path d="M20 4.5v5h-5"/><path d="M19.5 12a7.5 7.5 0 0 1-13 5.1L4 14.5"/><path d="M4 19.5v-5h5"/>',
    globe: '<circle cx="12" cy="12" r="8.5"/><path d="M3.5 12h17M12 3.5c2.4 2.6 3.4 5.4 3.4 8.5s-1 5.9-3.4 8.5c-2.4-2.6-3.4-5.4-3.4-8.5s1-5.9 3.4-8.5z"/>',
    stack: '<rect x="7.5" y="3.5" width="12" height="14" rx="2"/><path d="M4.5 7v11.5a2 2 0 0 0 2 2H15"/>',
    table: '<rect x="3.5" y="4.5" width="17" height="15" rx="2.2"/><path d="M3.5 9.5h17M3.5 14.5h17M10 9.5v10"/>',
    chart: '<path d="M4 20.5V4M4 20.5h16.5"/><path d="M8 16v-4.5M12 16V8M16 16v-6"/>',
    bank: '<path d="m3.5 9 8.5-5 8.5 5zM5 20.5h14M6.5 11v7M10 11v7M14 11v7M17.5 11v7"/>',
    megaphone: '<path d="M4 10v4l2.5.5 2 5h2.5l-1.3-4.5 9.3 3V5.5L8 9.2z"/>',
    id: '<rect x="3" y="5" width="18" height="14" rx="2.2"/><circle cx="9" cy="11" r="2.3"/><path d="M5.5 16.5c.5-1.6 1.8-2.4 3.5-2.4s3 .8 3.5 2.4M14.5 10h4M14.5 13.5h3"/>',
    gear: '<circle cx="12" cy="12" r="3"/><path d="M12 2.8v2.4M12 18.8v2.4M2.8 12h2.4M18.8 12h2.4M5.5 5.5l1.7 1.7M16.8 16.8l1.7 1.7M5.5 18.5l1.7-1.7M16.8 7.2l1.7-1.7"/>',
    user: '<circle cx="12" cy="8.5" r="3.8"/><path d="M4.5 20.5c.9-3.8 3.8-6 7.5-6s6.6 2.2 7.5 6"/>',
    sync: '<path d="M19.5 9A8 8 0 0 0 5 7.5M4.5 15A8 8 0 0 0 19 16.5"/><path d="M19.8 3.5v5.5h-5.5M4.2 20.5V15h5.5"/>',
    cloud: '<path d="M7 18.5a4.5 4.5 0 0 1-.6-9 6 6 0 0 1 11.4 1.6 3.8 3.8 0 0 1-.3 7.4z"/>',
    link: '<path d="M10 14a4 4 0 0 0 5.7 0l3.3-3.3a4 4 0 0 0-5.7-5.7l-1.2 1.2"/><path d="M14 10a4 4 0 0 0-5.7 0L5 13.3A4 4 0 0 0 10.7 19l1.2-1.2"/>',
    lock: '<rect x="4.5" y="10.5" width="15" height="10" rx="2.2"/><path d="M8 10.5V8a4 4 0 0 1 8 0v2.5"/>',
    monitor: '<rect x="3" y="4.5" width="18" height="12" rx="2"/><path d="M9 20.5h6M12 16.5v4"/>',
    sheet: '<path d="M14 3.5H7a2 2 0 0 0-2 2v13a2 2 0 0 0 2 2h10a2 2 0 0 0 2-2V8.5z"/><path d="M14 3.5v5h5M8.5 12h7v5.5h-7zM8.5 14.7h7M12 12v5.5"/>',
    download: '<path d="M12 3.5V15M7.5 10.5 12 15l4.5-4.5"/><path d="M4.5 16.5v2a2 2 0 0 0 2 2h11a2 2 0 0 0 2-2v-2"/>',
    keyboard: '<rect x="2.5" y="6" width="19" height="12" rx="2.2"/><path d="M6 9.5h.01M9.5 9.5h.01M13 9.5h.01M16.5 9.5h.01M18 9.5h.01M6 13h.01M18 13h.01M8.5 14.5h7"/>',
    help: '<circle cx="12" cy="12" r="8.5"/><path d="M9.5 9.5a2.5 2.5 0 1 1 3.5 2.3c-.6.3-1 .9-1 1.6v.6"/><path d="M12 17h.01"/>',
    search: '<circle cx="10.5" cy="10.5" r="6"/><path d="m15 15 5 5"/>',
    arrow: '<path d="M4 12h15M13.5 6.5 19 12l-5.5 5.5"/>',
    book: '<path d="M4.5 5.5A2 2 0 0 1 6.5 3.5h13v14h-13a2 2 0 0 0-2 2z"/><path d="M4.5 19.5a2 2 0 0 0 2 2h13v-4"/>',
  };
  const icon = (name, size = 20) => `<svg viewBox="0 0 24 24" width="${size}" height="${size}" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${P[name] || P.doc}</svg>`;

  // ---- text: **bold**, {⌘K} keys, [Button], [*Main button] ----
  const keysOf = (spec) => spec.trim().split(/\s+/).map((t) => {
    const mods = [];
    while (t.length > 1 && /^[⌘⇧⌥⌃]/.test(t)) { mods.push(t[0]); t = t.slice(1); }
    return mods.concat(t ? [t] : []).map((k) => `<kbd>${k}</kbd>`).join('');
  }).join('<span class="mx-keygap"></span>');
  const fmt = (text) => esc(text).replace(/\{([^}]+)\}|\[(\*?)([^\]{}]+)\]|\*\*([^*]+)\*\*/g, (m, keys, main, btn, bold) => {
    if (keys !== undefined) return `<span class="mx-keys">${keysOf(keys)}</span>`;
    if (btn !== undefined) return `<span class="mx-btn${main ? ' main' : ''}">${btn}</span>`;
    return `<b>${bold}</b>`;
  });

  const KIND = { boq: '#3f938b', qt: '#5374b8', dn: '#b0843f', inv: '#5d9150', letter: '#8a6cb0', client: '#c0627a', project: '#6d5cff', money: '#2f8a57', team: '#d07a2c', grey: '#7a808c' };

  // ---- blocks ----
  const head = (b) => (b.title ? `<h3 class="mx-h3">${b.step ? `<span class="mx-step-n">${esc(b.step)}</span>` : ''}${fmt(b.title)}</h3>` : '');

  function chain(spec, small) {
    return `<div class="mx-chain${small ? ' small' : ''}">${spec.split(/\s*>\s*/).map((part, i) => {
      const alts = part.split(/\s*\|\|\s*/).map((alt) => {
        const [kind, title, detail] = alt.split('|').map((x) => (x || '').trim());
        return `<div class="mx-node" style="--k:${KIND[kind] || KIND.grey}"><b>${fmt(title)}</b>${detail ? `<span>${fmt(detail)}</span>` : ''}</div>`;
      });
      const node = alts.length > 1 ? `<div class="mx-alts">${alts.map((a, k) => (k ? `<span class="mx-or">or</span>${a}` : a)).join('')}</div>` : alts[0];
      return (i ? `<span class="mx-arrow" aria-hidden="true">${icon('arrow', 18)}</span>` : '') + node;
    }).join('')}</div>`;
  }

  // A screenshot cut to its interesting part, with numbered points.
  let figures = 0;
  function shot(b) {
    const data = SHOTS[b.shot] || { w: 1440, h: 900, marks: [] };
    const [vx, vy, vw, vh] = b.view || [15.6, 0, 84.4, 100];
    const ratio = (data.w * vw) / (data.h * vh);
    const fig = `fig${figures++}`;
    const pins = [];
    const items = [];
    (b.points || []).forEach(([n, label, hint]) => {
      const m = data.marks[n - 1];
      const i = items.length;
      items.push(`<li data-i="${i}"><span class="mx-n">${i + 1}</span><span><b>${fmt(label)}</b>${hint ? `<small>${fmt(hint)}</small>` : ''}</span></li>`);
      if (!m) return;
      // Where the mark is, as % of the part shown (kept inside it).
      const clamp = (v) => Math.max(0, Math.min(100, v));
      const x = clamp(((m.x - vx) / vw) * 100), y = clamp(((m.y - vy) / vh) * 100);
      const w = clamp(((m.x + m.w - vx) / vw) * 100) - x, h = clamp(((m.y + m.h - vy) / vh) * 100) - y;
      if (w <= 0 || h <= 0) return;
      pins.push(`<span class="mx-box" data-i="${i}" style="left:${x}%;top:${y}%;width:${w}%;height:${h}%"></span>
        <span class="mx-pin" data-i="${i}" style="left:${Math.min(x + 0.4, 97)}%;top:${Math.min(y + 0.6, 95)}%">${i + 1}</span>`);
    });
    const img = `<img src="resources/manual/${esc(b.shot)}.jpg" alt="" loading="lazy" style="width:${10000 / vw}%;left:${(-vx / vw) * 100}%;top:${(-vy / vh) * 100}%">`;
    return `${head(b)}<figure class="mx-shot" id="${fig}">
      <div class="mx-win"><div class="mx-win-bar"><i></i><i></i><i></i></div>
        <div class="mx-frame" style="aspect-ratio:${ratio.toFixed(4)}" title="Click to enlarge">${img}${pins.join('')}</div></div>
      ${items.length ? `<ol class="mx-points">${items.join('')}</ol>` : ''}</figure>`;
  }

  const BLOCKS = {
    shot,
    flow: (b) => `<div class="mx-flow${b.step ? ' stepped' : ''}">${head(b)}${chain(b.chain)}${b.note ? `<p class="mx-note">${fmt(b.note)}</p>` : ''}</div>`,
    lanes: (b) => `${head(b)}<div class="mx-lanes">${b.lanes.map(([who, spec]) => `<div class="mx-lane"><span class="mx-who">${esc(who)}</span>${chain(spec, true)}</div>`).join('')}</div>`,
    steps: (b) => `${head(b)}<ol class="mx-steps" style="--n:${b.steps.length}">${b.steps.map(([ic, t, x], i) => `<li><span class="mx-big-n">${i + 1}</span><span class="mx-ico">${icon(ic)}</span><b>${fmt(t)}</b>${x ? `<p>${fmt(x)}</p>` : ''}</li>`).join('')}</ol>`,
    cards: (b) => `${head(b)}<div class="mx-cards">${b.cards.map(([ic, t, x, c]) => `<div class="mx-card"${c ? ` style="--c:${c}"` : ''}><span class="mx-ico">${icon(ic)}</span><b>${fmt(t)}</b>${x ? `<p>${fmt(x)}</p>` : ''}</div>`).join('')}</div>`,
    keys: (b) => `${head(b)}<div class="mx-keygrid">${b.keys.map(([k, what]) => `<div class="mx-key"><div class="mx-keyrow">${fmt(k)}</div><span>${fmt(what)}</span></div>`).join('')}</div>`,
    tip: (b) => `<div class="mx-tip${b.tone === 'warn' ? ' warn' : ''}"><span class="mx-ico">${icon(b.icon || 'bolt')}</span><p>${fmt(b.text)}</p></div>`,
    states: (b) => {
      const doc = [['draft', 'Draft', 'Change anything'], ['issued', 'Issued', 'Sent, locked'], ['cancelled', 'Cancelled', 'Kept, never reopened']];
      const inv = [['issued', 'Issued', 'Sent'], ['part', 'Partly paid', 'Balance left'], ['paid', 'Paid', 'Nothing owed'], ['late', 'Overdue', 'Past its due date']];
      const list = b.invoice ? inv : doc;
      return `${head(b)}<div class="mx-states">${list.map(([k, t, x], i) => `${i && !(b.invoice && i === 3) ? `<span class="mx-arrow">${icon('arrow', 18)}</span>` : ''}${b.invoice && i === 3 ? '<span class="mx-or">or</span>' : ''}<div class="mx-state ${k}"><b>${t}</b><span>${x}</span></div>`).join('')}</div>`;
    },
    code: (b) => `${head(b)}<div class="mx-code">${b.parts.map(([t, what], i) => `<div style="--i:${i}"><b>${esc(t)}</b><span>${esc(what)}</span></div>`).join('')}</div>`,
    example: (b) => `${head(b)}<div class="mx-example">${b.parts.map(([t, what]) => (what ? `<span class="mx-part"><b>${esc(t)}</b><small>${esc(what)}</small></span>` : `<span class="mx-plain">${esc(t)}</span>`)).join('')}</div>${b.note ? `<p class="mx-note">${fmt(b.note)}</p>` : ''}`,
    swatches: (b) => `${head(b)}<div class="mx-swatches">${b.items.map(([c, t, x]) => `<div><i style="--k:${c}"></i><b>${esc(t)}</b>${x ? `<span>${esc(x)}</span>` : ''}</div>`).join('')}</div>`,
    path: (b) => `${head(b)}<div class="mx-path">${b.path.map((p, i) => `${i ? '<span class="mx-sep">/</span>' : ''}<span class="${i === b.path.length - 1 ? 'file' : ''}">${icon(i === b.path.length - 1 ? 'doc' : 'folder', 16)}${esc(p)}</span>`).join('')}</div>`,
    qa: (b) => `${head(b)}<div class="mx-qa">${b.items.map(([q, a]) => `<div><b>${fmt(q)}</b><p>${fmt(a)}</p></div>`).join('')}</div>`,
  };

  // ---- the page ----
  const parts = [];
  CHAPTERS.forEach((c, i) => {
    if (c.part) parts.push({ name: c.part, first: c, chapters: [] });
    if (parts.length) parts[parts.length - 1].chapters.push(c);
    c.n = i + 1;
  });
  const PART_ICON = { 'Getting started': 'book', Overview: 'home', Team: 'people', Operations: 'layers', Company: 'building', 'Working together': 'sync', Reference: 'keyboard' };

  function render() {
    $('#mx-parts').innerHTML = parts.map((p, i) => `<a class="mx-part-tile" href="#${esc(p.first.id)}" style="--c:${p.first.color};--i:${i}">
      <span class="mx-ico">${icon(PART_ICON[p.name] || 'doc', 22)}</span><b>${esc(p.name)}</b><small>${p.chapters.map((c) => esc(c.title)).join(' · ')}</small></a>`).join('');
    $('#mx-rail-list').innerHTML = parts.map((p) => `<li class="mx-rail-part">${esc(p.name)}</li>${p.chapters.map((c) => `<li data-for="${esc(c.id)}"><a href="#${esc(c.id)}" style="--c:${c.color}"><span class="mx-dot"></span>${esc(c.title)}</a></li>`).join('')}`).join('');
    $('#mx-body').innerHTML = CHAPTERS.map((c) => `<section class="mx-ch" id="${esc(c.id)}" style="--c:${c.color}">
      <header class="mx-ch-head">
        <span class="mx-ch-n">${String(c.n).padStart(2, '0')}</span>
        <span class="mx-ch-ico">${icon(c.icon, 30)}</span>
        <div><h2>${esc(c.title)}</h2><p>${fmt(c.tag)}</p></div>
        ${c.keys ? `<span class="mx-ch-keys" title="Open it with">${fmt(c.keys)}</span>` : ''}
      </header>
      ${c.blocks.map((b) => `<div class="mx-block mx-${b.type}-block">${(BLOCKS[b.type] || (() => ''))(b)}</div>`).join('')}
    </section>`).join('') + '<p class="mx-none hidden" id="mx-none">Nothing in the manual matches that. Try a shorter word.</p>';
  }

  // Points ⇄ pins: hovering either spotlights that part of the picture.
  // (One listener for the page, so it holds however the page is redrawn.)
  function wireShots() {
    let lit = null;
    const light = (fig, i) => {
      const frame = $('.mx-frame', fig);
      frame.classList.toggle('spot', i !== null && !!$(`.mx-box[data-i="${i}"]`, frame));
      $$('[data-i]', fig).forEach((el) => el.classList.toggle('on', i !== null && el.dataset.i === String(i)));
    };
    document.addEventListener('mouseover', (e) => {
      const el = e.target.closest && e.target.closest('.mx-points li, .mx-pin');
      const key = el ? `${el.closest('.mx-shot').id}:${el.dataset.i}` : null;
      if (key === lit) return;
      if (lit) { const fig = document.getElementById(lit.split(':')[0]); if (fig) light(fig, null); }
      lit = key;
      if (el) light(el.closest('.mx-shot'), el.dataset.i);
    });
    document.addEventListener('click', (e) => {
      const frame = e.target.closest && e.target.closest('.mx-shot .mx-frame');
      if (frame) zoom(frame);
    });
  }

  function zoom(frame) {
    const back = document.createElement('div');
    back.className = 'mx-zoom';
    const copy = frame.cloneNode(true);
    copy.classList.remove('spot');
    back.appendChild(copy);
    const close = () => { back.classList.add('out'); setTimeout(() => back.remove(), still() ? 0 : 160); document.removeEventListener('keydown', onKey, true); };
    const onKey = (e) => { if (e.key === 'Escape') { e.preventDefault(); close(); } };
    back.addEventListener('click', close);
    document.addEventListener('keydown', onKey, true);
    document.body.appendChild(back);
  }

  // Contents: the chapter in view is marked; a click scrolls to it.
  function wireRail() {
    const go = (id) => {
      const t = document.getElementById(id);
      if (!t) return;
      t.scrollIntoView({ behavior: still() ? 'auto' : 'smooth', block: 'start' });
      history.replaceState(null, '', `#${id}`);
    };
    document.addEventListener('click', (e) => {
      const a = e.target.closest('a[href^="#"]');
      if (!a || !a.closest('.mx')) return;
      e.preventDefault();
      go(a.getAttribute('href').slice(1));
    });
    const links = new Map($$('#mx-rail-list a').map((a) => [a.getAttribute('href').slice(1), a]));
    const seen = new Set();
    const io = new IntersectionObserver((entries) => {
      for (const e of entries) { if (e.isIntersecting) seen.add(e.target.id); else seen.delete(e.target.id); }
      const first = $$('.mx-ch').find((c) => seen.has(c.id));
      links.forEach((a, id) => a.classList.toggle('on', !!first && id === first.id));
      if (first) { const a = links.get(first.id); if (a && a.scrollIntoViewIfNeeded) a.scrollIntoViewIfNeeded(false); }
    }, { rootMargin: '-15% 0px -70% 0px' });
    $$('.mx-ch').forEach((c) => io.observe(c));
    // Blocks rise in as they come into view.
    if (!still()) {
      const rise = new IntersectionObserver((entries) => {
        for (const e of entries) if (e.isIntersecting) { e.target.classList.add('in'); rise.unobserve(e.target); }
      }, { rootMargin: '0px 0px -8% 0px' });
      $$('.mx-block, .mx-ch-head').forEach((b) => { b.classList.add('rise'); rise.observe(b); });
    }
  }

  function wireSearch() {
    const boxes = $$('.mx-search input');
    const texts = $$('.mx-ch').map((ch) => [ch, ch.textContent.toLowerCase()]);
    const run = (q) => {
      for (const b of boxes) if (b.value !== q) b.value = q;
      const words = q.trim().toLowerCase().split(/\s+/).filter(Boolean);
      let any = false;
      for (const [ch, text] of texts) {
        const hit = !words.length || words.every((w) => text.includes(w));
        ch.classList.toggle('hidden', !hit);
        const li = $(`#mx-rail-list li[data-for="${ch.id}"]`);
        if (li) li.classList.toggle('hidden', !hit);
        if (hit) any = true;
      }
      $$('#mx-rail-list .mx-rail-part').forEach((p) => {
        let n = p.nextElementSibling, shown = false;
        while (n && !n.classList.contains('mx-rail-part')) { if (!n.classList.contains('hidden')) shown = true; n = n.nextElementSibling; }
        p.classList.toggle('hidden', !shown);
      });
      $('#mx-none').classList.toggle('hidden', any);
      document.body.classList.toggle('mx-searching', !!words.length);
    };
    for (const b of boxes) {
      b.addEventListener('input', () => run(b.value));
      b.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') { run(''); b.blur(); }
        if (e.key === 'Enter') { const first = $$('.mx-ch').find((c) => !c.classList.contains('hidden')); if (first) first.scrollIntoView({ behavior: still() ? 'auto' : 'smooth' }); }
      });
    }
    document.addEventListener('keydown', (e) => {
      if (e.key === '/' && !/INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName)) { e.preventDefault(); $('#mx-rail .mx-search input').focus(); }
    });
  }

  render();
  wireShots();
  wireRail();
  wireSearch();
  $('#mx-print').addEventListener('click', () => window.print());
  if (location.hash) { const t = document.getElementById(location.hash.slice(1)); if (t) setTimeout(() => t.scrollIntoView({ block: 'start' }), 60); }
})();

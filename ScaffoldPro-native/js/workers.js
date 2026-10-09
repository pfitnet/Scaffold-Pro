'use strict';

// Workers: the people on site. At the top, the crew at a glance (tiles
// that also filter the list); on the left, everyone as cards with where
// their employment agreement is; on the right, the chosen worker —
// their details (saved as they're typed), their agreement (its terms, a
// live preview of the paper, exports, Sign & Chop, the copy they signed),
// and their documents (certificates, ID… with expiry reminders).
//
// workers.html?worker=<id> opens that worker (global search, calendar).

(function () {
  const api = () => window.api;
  const $ = (id) => document.getElementById(id);
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const day = (iso, empty = '') => (iso ? (window.appDay ? window.appDay(String(iso).slice(0, 10), empty) : String(iso).slice(0, 10)) : empty);
  const money = (n) => Number(n || 0).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
  const store = {
    get(k, d) { try { const v = sessionStorage.getItem(`workers.${k}`); return v == null ? d : JSON.parse(v); } catch (e) { return d; } },
    set(k, v) { try { sessionStorage.setItem(`workers.${k}`, JSON.stringify(v)); } catch (e) { /* not kept */ } },
  };
  const svg = (p, s = 16) => `<svg viewBox="0 0 20 20" width="${s}" height="${s}" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">${p}</svg>`;
  const I = {
    crew: svg('<circle cx="7" cy="7" r="2.6"/><circle cx="13.6" cy="7.6" r="2.1"/><path d="M2.6 16c.4-2.8 2.2-4.3 4.4-4.3s4 1.5 4.4 4.3M11.6 12.1c2.4-.4 4.6.8 5.2 3.6"/>', 18),
    pen: svg('<path d="M13.2 3.8l3 3-8.7 8.7-3.7.7.7-3.7z"/><path d="M11.5 5.5l3 3"/>', 18),
    inbox: svg('<path d="M3 11.5 5 4.5h10l2 7v4H3z"/><path d="M3 11.5h4l1 2h4l1-2h4"/>', 18),
    clock: svg('<circle cx="10" cy="10" r="6.6"/><path d="M10 6.5V10l2.4 1.6"/>', 18),
    folder: svg('<path d="M2.5 6V5a1.5 1.5 0 0 1 1.5-1.5h3.2l1.6 1.8H16A1.5 1.5 0 0 1 17.5 6.8V15a1.5 1.5 0 0 1-1.5 1.5H4A1.5 1.5 0 0 1 2.5 15z"/>'),
    archive: svg('<rect x="2.5" y="3.5" width="15" height="4" rx="1"/><path d="M4 7.5v8A1.5 1.5 0 0 0 5.5 17h9a1.5 1.5 0 0 0 1.5-1.5v-8M8 11h4"/>'),
    restore: svg('<path d="M4 10a6 6 0 1 0 1.8-4.3"/><path d="M3.5 3.5v3h3"/>'),
    check: svg('<path d="M4.5 10.5l3.5 3.5 7.5-8"/>', 14),
    doc: svg('<path d="M5.5 2.8h6l3.5 3.5v10.9H5.5z"/><path d="M11.5 2.8v3.5H15M8 10h5M8 13h5"/>', 18),
    upload: svg('<path d="M10 13V3.5M6 7.5l4-4 4 4M4 13.5v3h12v-3"/>', 18),
    phone: svg('<path d="M5 3.5h2.5l1.2 3.2-1.6 1a8 8 0 0 0 3.7 3.7l1-1.6 3.2 1.2V15a1.5 1.5 0 0 1-1.6 1.5A12 12 0 0 1 3.5 5.1 1.5 1.5 0 0 1 5 3.5z"/>', 13),
    cal: svg('<rect x="3" y="4.5" width="14" height="12.5" rx="1.5"/><path d="M3 8.5h14M7 3v3M13 3v3"/>', 13),
    cash: svg('<rect x="2.5" y="5" width="15" height="10" rx="1.5"/><circle cx="10" cy="10" r="2"/>', 13),
    id: svg('<rect x="2.5" y="4.5" width="15" height="11" rx="1.5"/><circle cx="7" cy="9.5" r="1.7"/><path d="M4.6 13.2c.4-1.2 1.3-1.8 2.4-1.8s2 .6 2.4 1.8M11.5 8.5h3.5M11.5 11h2.5"/>', 13),
    eye: svg('<path d="M2 10s3-5.5 8-5.5S18 10 18 10s-3 5.5-8 5.5S2 10 2 10z"/><circle cx="10" cy="10" r="2.3"/>', 15),
    word: svg('<path d="M5.5 2.8h6l3.5 3.5v10.9H5.5z"/><path d="M7.5 9.5l1 4 1.5-3 1.5 3 1-4"/>', 15),
    print: svg('<path d="M5.5 7.5V3.5h9v4"/><rect x="2.5" y="7.5" width="15" height="6.5" rx="1.5"/><path d="M5.5 12h9v5h-9z"/>', 15),
  };

  // ---- state ----
  let roster = [];
  let selectedId = null;
  let filter = store.get('filter', 'all');
  let query = '';
  let tab = store.get('tab', 'agreement');
  let page = null;   // the chosen worker's agreement (workerAgreements:get)
  // A signer's full name (Team page), else their ScaffoldPro name.
  const person = (n) => (page && page.fullNames && page.fullNames[n]) || n;
  let docs = [];

  // ---- small helpers ----
  const PALETTE = [['#4b78ff', '#7a5cf5'], ['#13a37f', '#3fc7a2'], ['#e0702f', '#f2a64a'], ['#c0427a', '#e57aa8'], ['#2a8fc4', '#5cc0e8'], ['#7d5cd6', '#a98af0'], ['#b8892a', '#e0b956'], ['#3b8c4c', '#7cc187']];
  function hue(name) {
    let h = 0;
    for (const ch of String(name)) h = (h * 31 + ch.codePointAt(0)) >>> 0;
    return PALETTE[h % PALETTE.length];
  }
  function initials(w) {
    const parts = String(w.name || '').replace(/[,]/g, ' ').split(/\s+/).filter(Boolean);
    if (!parts.length) return (w.chineseName || '?').slice(0, 1);
    return (parts[0][0] + (parts.length > 1 ? parts[parts.length - 1][0] : '')).toUpperCase();
  }
  const avatar = (w, cls = '') => {
    const [a, b] = hue(w.name || w.workerNumber);
    return `<span class="wk-avatar ${cls}" style="--a:${a};--b:${b}">${esc(initials(w))}</span>`;
  };
  function toast(text) {
    const t = $('wk-toast');
    t.innerHTML = `<span class="wk-toast-dot">${I.check}</span>${esc(text)}`;
    t.classList.add('show');
    clearTimeout(toast.timer);
    toast.timer = setTimeout(() => t.classList.remove('show'), 2400);
  }
  // HK ID card: letter(s), six digits, check digit (0–9 or A).
  function hkid(raw) {
    const s = String(raw || '').toUpperCase().replace(/[\s()]/g, '');
    const m = s.match(/^([A-Z]{1,2})([0-9]{6})([0-9A])$/);
    if (!m) return { ok: false, formatted: raw };
    const v = (c) => c.charCodeAt(0) - 55;
    const letters = m[1].length === 2 ? [v(m[1][0]), v(m[1][1])] : [36, v(m[1][0])];
    let sum = letters[0] * 9 + letters[1] * 8;
    [...m[2]].forEach((d, i) => { sum += Number(d) * (7 - i); });
    const check = (11 - (sum % 11)) % 11;
    return { ok: (check === 10 ? 'A' : String(check)) === m[3], formatted: `${m[1]}${m[2]}(${m[3]})` };
  }

  // ---- the agreement's words (as main.swift's agreementContent), for the live preview ----
  const CAP = ['零', '壹', '貳', '叁', '肆', '伍', '陸', '柒', '捌', '玖'];
  function capitalAmount(value) {
    const cents = Math.round(Math.max(0, Number(value) || 0) * 100);
    const whole = Math.floor(cents / 100), jiao = Math.floor((cents % 100) / 10), fen = cents % 10;
    const group = (n) => {
      const units = ['仟', '佰', '拾', ''];
      const ds = [Math.floor(n / 1000), Math.floor(n / 100) % 10, Math.floor(n / 10) % 10, n % 10];
      let s = '', gap = false;
      ds.forEach((d, i) => { if (!d) { if (s) gap = true; return; } if (gap) { s += '零'; gap = false; } s += CAP[d] + units[i]; });
      return s;
    };
    let out = '', gap = false;
    for (const [n, unit] of [[Math.floor(whole / 1e8), '億'], [Math.floor(whole / 1e4) % 1e4, '萬'], [whole % 1e4, '']]) {
      if (!n) { if (out) gap = true; continue; }
      if (out && (gap || n < 1000)) out += '零';
      out += group(n) + unit;
      gap = false;
    }
    out = (out || '零') + '元';
    if (!jiao && !fen) return `${out}正`;
    return out + (jiao ? `${CAP[jiao]}角` : '零') + (fen ? `${CAP[fen]}分` : '');
  }
  const small = (n) => { const d = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九']; if (n < 10) return d[n]; if (n < 20) return `十${n % 10 ? d[n % 10] : ''}`; return `${d[Math.floor(n / 10)]}十${n % 10 ? d[n % 10] : ''}`; };
  function clock(hhmm) {
    const [h0, m0] = String(hhmm || '08:00').split(':').map(Number);
    const h = Math.min(23, Math.max(0, h0 || 0)), m = Math.min(59, Math.max(0, m0 || 0));
    const period = h < 6 ? '凌晨' : h < 12 ? '早上' : h < 13 ? '中午' : h < 18 ? '下午' : '晚上';
    const t = h % 12 === 0 ? 12 : h % 12;
    return `${period}${small(t)}${m ? `時${m < 10 ? '零' : ''}${small(m)}分` : '時正'} (${t}:${String(m).padStart(2, '0')} ${h < 12 ? 'a.m.' : 'p.m.'})`;
  }
  const cDate = (ymd) => { const p = String(ymd || '').slice(0, 10).split('-').map(Number); return p.length === 3 && p[0] ? `${p[0]}年${p[1]}月${p[2]}日` : '【日期】'; };
  // The paper: the first lines and the terms, the worker's details marked.
  function paperHTML(w, a, opts = {}) {
    const mark = (v, empty) => `<mark class="${v ? '' : 'empty'}">${esc(v || empty)}</mark>`;
    const name = [w.chineseName, w.name].filter(Boolean).filter((v, i, all) => all.indexOf(v) === i).join(' ');
    const wage = Number(a.dailyWage) || 0;
    const terms = [
      ['A', '工作崗位內容'], ['1', '受僱日期', `由 ${mark(a.startDate ? cDate(a.startDate) : '', '開始日期')} 起生效（至其中一方終止合約）`],
      ['2', '試用期', '不設試用期'], ['3', '受僱職位', mark(a.position, 'Scaffolder')], ['4', '工作地點', '任何地方（由僱主指派）'],
      ['5', '工作時間', `每天 ${mark(clock(a.hoursFrom))} 至 ${mark(clock(a.hoursTo))}`],
      ['B', '薪酬內容'], ['6', '工資', `每天 港元 ${mark(wage ? `${capitalAmount(wage)} (HK$${wage.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })})` : '', '工資')}（下稱「基本薪金」）`],
      ['7', '超時工作工資', '以基本薪金1.5倍計算'], ['8', '工資支付日期', `每月壹次；工資於每月第${mark(String(a.payDay || 7))}日支付`],
      ['C', '其他內容'], ['10', '合約終止', `欲終止合約方須於終止前 ${mark(String(a.noticeDays ?? 7))} 天前通知對方，或支付對方相等於 ${mark(String(a.noticeDays ?? 7))} 天工資`],
    ];
    return `<div class="wk-paper-head"><span class="wk-lh"><b>P</b>ROFICIENCY</span><span class="wk-lh-sub">建機（香港）設備有限公司 <b>(HK)</b> LIMITED</span></div>
      <div class="wk-paper-title">簡易僱傭合約 <small>Site-work Employment Agreement</small></div>
      <p class="wk-paper-intro">本簡易僱傭合約由 建機（香港）設備有限公司（下稱「僱主」）與 ${mark(name, '僱員姓名')} ${esc(w.honorific || '先生')}（下簡稱「僱員」）於 ${mark(a.agreementDate ? cDate(a.agreementDate) : '', '合約日期')}（下稱「合約日期」）訂立：</p>
      <dl class="wk-paper-terms">${terms.map((t) => (t.length === 2
        ? `<dt class="sec">${esc(t[0])}.</dt><dd class="sec">${esc(t[1])}</dd>`
        : `<dt>${esc(t[0])}.</dt><dd><span>${esc(t[1])}</span><span>：</span><span>${t[2]}</span></dd>`)).join('')}</dl>
      ${opts.short ? '' : `<div class="wk-paper-sign"><div><span>僱主或其代表簽署</span><i></i><b>${esc(person((page && (page.agreement.employerSignedBy || page.agreement.signatory)) || ''))}</b></div><div><span>僱員簽署</span><i></i><b>${esc(name)}</b><small>身份證號碼：${esc(w.idNumber || '')}</small></div></div>`}`;
  }

  // ---- loading ----
  async function loadRoster() {
    const archived = $('wk-show-archived').checked;
    roster = await api().workers.roster(archived) || [];
  }
  async function load(keepProfile) {
    await loadRoster();
    drawStats();
    drawList();
    if (!roster.some((r) => r.worker.id === selectedId)) selectedId = visible()[0] ? visible()[0].worker.id : null;
    if (!keepProfile) await openWorker(selectedId, { quiet: true });
    else drawHero();
  }
  window.appRefresh = () => load(false);

  // ---- the crew at a glance ----
  function counts() {
    const active = roster.filter((r) => !r.worker.isArchived);
    return {
      all: active.length,
      sign: active.filter((r) => r.stage <= 1).length,
      copy: active.filter((r) => r.stage === 2).length,
      expiring: active.reduce((s, r) => s + (r.expiring || 0), 0),
      expiringPeople: active.filter((r) => r.expiring > 0).length,
      done: active.filter((r) => r.stage === 3).length,
    };
  }
  function drawStats() {
    const c = counts();
    const tiles = [
      { key: 'all', icon: I.crew, n: c.all, label: c.all === 1 ? 'Worker' : 'Workers', hint: `${c.done} with a signed agreement`, tone: 'blue' },
      { key: 'sign', icon: I.pen, n: c.sign, label: 'To sign & chop', hint: c.sign ? 'Agreements waiting for the company' : 'All signed for the company', tone: 'violet' },
      { key: 'copy', icon: I.inbox, n: c.copy, label: 'Waiting for the worker', hint: c.copy ? 'Signed copy not back yet' : 'Nothing outstanding', tone: 'amber' },
      { key: 'expiring', icon: I.clock, n: c.expiring, label: 'Expiring documents', hint: c.expiring ? `Within 30 days, for ${c.expiringPeople} ${c.expiringPeople === 1 ? 'worker' : 'workers'}` : 'Nothing expires soon', tone: 'rose' },
    ];
    $('wk-stats').innerHTML = tiles.map((t, i) => `<button type="button" class="wk-stat t-${t.tone}${filter === t.key ? ' on' : ''}${t.n ? '' : ' zero'}" data-filter="${t.key}" style="--i:${i}" aria-pressed="${filter === t.key}" data-no-icon>
        <span class="wk-stat-icon">${t.icon}</span>
        <span class="wk-stat-label">${esc(t.label)}</span>
        <span class="wk-stat-n" data-n="${t.n}">${t.n}</span>
        <span class="wk-stat-hint">${esc(t.hint)}</span>
      </button>`).join('');
    const parts = [];
    if (c.all) parts.push(`<b>${c.all}</b> on the books`);
    if (c.sign) parts.push(`<b>${c.sign}</b> to sign`);
    if (c.copy) parts.push(`<b>${c.copy}</b> waiting for the worker`);
    if (c.expiring) parts.push(`<b class="late">${c.expiring}</b> document${c.expiring === 1 ? '' : 's'} expiring`);
    $('wk-summary').innerHTML = c.all ? `${parts.join(' · ')}.` : 'Add the people who work on site: their employment agreement is made for you, ready to sign.';
    countUp();
  }
  function countUp() {
    if (window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
    if (countUp.done) return;
    countUp.done = true;
    for (const el of document.querySelectorAll('.wk-stat-n')) {
      const target = Number(el.dataset.n) || 0;
      if (!target) continue;
      const t0 = performance.now();
      const step = (t) => {
        const k = Math.min(1, (t - t0) / 700);
        el.textContent = String(Math.round(target * (1 - Math.pow(1 - k, 3))));
        if (k < 1) requestAnimationFrame(step);
      };
      el.textContent = '0';
      requestAnimationFrame(step);
    }
  }

  // ---- the list ----
  const STAGE = ['No agreement', 'To sign & chop', 'Waiting for the worker', 'Agreement complete'];
  function visible() {
    const q = query.trim().toLowerCase();
    return roster.filter((r) => {
      const w = r.worker;
      if (!$('wk-show-archived').checked && w.isArchived) return false;
      if (filter === 'sign' && r.stage > 1) return false;
      if (filter === 'copy' && r.stage !== 2) return false;
      if (filter === 'expiring' && !r.expiring) return false;
      if (!q) return true;
      return [w.name, w.chineseName, w.workerNumber, w.idNumber, w.position, w.phone].some((v) => String(v || '').toLowerCase().includes(q));
    });
  }
  function drawList() {
    const list = visible();
    const titles = { all: 'Everyone', sign: 'To sign & chop', copy: 'Waiting for the worker', expiring: 'Expiring documents' };
    $('wk-roster-title').innerHTML = `${esc(titles[filter] || 'Everyone')} <span>${list.length}</span>`;
    if (!roster.length) {
      $('wk-list').innerHTML = `<div class="wk-list-empty"><b>No workers yet</b><span>Add someone with New Worker.</span></div>`;
      return;
    }
    if (!list.length) {
      $('wk-list').innerHTML = `<div class="wk-list-empty"><b>No one here</b><span>${query ? `Nothing matches “${esc(query)}”.` : 'Nothing in this group right now.'}</span>${filter !== 'all' ? '<button type="button" data-filter="all" data-no-icon>Show everyone</button>' : ''}</div>`;
      return;
    }
    $('wk-list').innerHTML = list.map((r, i) => {
      const w = r.worker;
      return `<button type="button" class="wk-card${w.id === selectedId ? ' on' : ''}${w.isArchived ? ' archived' : ''}" data-id="${esc(w.id)}" role="option" aria-selected="${w.id === selectedId}" style="--i:${Math.min(i, 12)}" data-no-icon>
        ${avatar(w)}
        <span class="wk-card-text">
          <span class="wk-card-name">${esc(w.name)}${w.chineseName ? ` <span class="wk-zh">${esc(w.chineseName)}</span>` : ''}</span>
          <span class="wk-card-sub">${esc(w.workerNumber)} · ${esc(w.position || 'Scaffolder')}${w.dailyWage ? ` · HK$${money(w.dailyWage)}/day` : ''}</span>
        </span>
        <span class="wk-card-end">
          <span class="wk-pips s${r.stage}" title="${esc(STAGE[r.stage])}"><i></i><i></i><i></i></span>
          ${r.expiring ? `<span class="wk-card-alert" title="${r.expiring} document${r.expiring === 1 ? '' : 's'} expiring">${r.expiring}</span>` : ''}
          ${w.isArchived ? '<span class="wk-card-tag">Archived</span>' : ''}
        </span>
      </button>`;
    }).join('');
  }

  // ---- the chosen worker ----
  const current = () => (roster.find((r) => r.worker.id === selectedId) || {}).worker;
  const entry = () => roster.find((r) => r.worker.id === selectedId);
  async function openWorker(id, opts = {}) {
    selectedId = id;
    store.set('selected', id);
    for (const c of document.querySelectorAll('.wk-card')) {
      const on = c.dataset.id === id;
      c.classList.toggle('on', on);
      c.setAttribute('aria-selected', String(on));
    }
    const box = $('wk-profile');
    if (!id || !current()) {
      box.innerHTML = roster.length
        ? '<div class="wk-profile-empty"><b>Choose a worker</b><span>Their details, agreement and documents appear here.</span></div>'
        : `<div class="wk-welcome">
            <div class="wk-welcome-art" aria-hidden="true"><span></span><span></span><span></span></div>
            <h2>Your site crew, in one place</h2>
            <p>Add a worker and their <b>employment agreement</b> is written for you from the company’s template — ready to preview, sign &amp; chop, and print. Keep their certificates here too, with reminders before they expire.</p>
            <button type="button" class="primary" data-act="new" data-no-icon>Add the First Worker</button>
          </div>`;
      return;
    }
    [page, docs] = await Promise.all([api().workerAgreements.get(id), api().workerDocuments.list(id)]);
    if (selectedId !== id) return;
    drawProfile(!opts.quiet);
  }

  function nextStep() {
    const r = entry();
    if (!r) return null;
    const w = r.worker;
    if (!page || !page.agreement) return { text: 'This worker has no employment agreement yet.', act: 'create', label: 'Make Agreement' };
    if ((page.missing || []).some((m) => /worker/.test(m))) return { text: 'Add their ID card number — it’s printed on the agreement.', act: 'focus-id', label: 'Add ID Number' };
    if (r.stage === 1) {
      return page.canSign
        ? { text: 'The agreement is ready for the company’s signature and chop.', act: 'sign', label: 'Sign & Chop' }
        : { text: `The agreement is waiting for ${(page.signers || []).map(person).join(' or ') || 'someone who signs worker agreements'} to sign and chop it.`, act: 'tab-agreement', label: 'View Agreement' };
    }
    if (r.stage === 2) return { text: `Print it for ${w.name.split(/[ ,]/)[0]} to sign, then add the signed copy.`, act: 'upload', label: 'Add Signed Copy' };
    if (r.expiring) return { text: `${r.expiring} document${r.expiring === 1 ? '' : 's'} expire${r.expiring === 1 ? 's' : ''} within 30 days.`, act: 'tab-documents', label: 'See Documents', tone: 'warn' };
    return { text: 'All set — the agreement is signed by both sides.', done: true };
  }

  function heroHTML() {
    const w = current();
    const [a, b] = hue(w.name || w.workerNumber);
    const n = nextStep();
    const chips = [
      `<span class="wk-chip mono">${esc(w.workerNumber)}</span>`,
      `<span class="wk-chip">${esc(w.position || 'Scaffolder')}</span>`,
      w.dailyWage ? `<span class="wk-chip">${I.cash}HK$${money(w.dailyWage)} a day</span>` : '',
      w.startDate ? `<span class="wk-chip">${I.cal}Since ${esc(day(w.startDate))}</span>` : '',
      w.idNumber ? `<span class="wk-chip mono">${I.id}${esc(w.idNumber)}</span>` : '',
      w.phone ? `<button type="button" class="wk-chip link" data-copy="${esc(w.phone)}" title="Copy" data-no-icon>${I.phone}${esc(w.phone)}</button>` : '',
    ].join('');
    return `<header class="wk-hero-card" style="--a:${a};--b:${b}">
      <div class="wk-cover" aria-hidden="true"></div>
      <div class="wk-hero-row">
        ${avatar(w, 'xl')}
        <div class="wk-hero-who">
          <h2>${esc(w.name)}${w.chineseName ? ` <span class="wk-zh">${esc(w.chineseName)} ${esc(w.honorific || '先生')}</span>` : ''}${w.isArchived ? ' <span class="wk-card-tag">Archived</span>' : ''}</h2>
          <div class="wk-chips">${chips}</div>
        </div>
        <div class="wk-hero-tools">
          <button type="button" class="wk-icon" data-act="folder" title="Show their folder in Finder" aria-label="Show folder" data-no-icon>${I.folder}</button>
          <button type="button" class="wk-icon" data-act="archive" title="${w.isArchived ? 'Restore' : 'Archive'}" aria-label="${w.isArchived ? 'Restore' : 'Archive'}" data-no-icon>${w.isArchived ? I.restore : I.archive}</button>
        </div>
      </div>
      ${n ? `<div class="wk-next${n.done ? ' done' : ''}${n.tone ? ` ${n.tone}` : ''}">
        <span class="wk-next-dot">${n.done ? I.check : ''}</span>
        <span class="wk-next-text"><small>${n.done ? 'Up to date' : 'Next step'}</small>${esc(n.text)}</span>
        ${n.act ? `<button type="button" class="${n.tone ? '' : 'primary'}" data-act="${n.act}" data-no-icon>${esc(n.label)}</button>` : ''}
      </div>` : ''}
    </header>`;
  }
  function drawHero() {
    const hero = document.querySelector('.wk-hero-card');
    if (hero && current()) hero.outerHTML = heroHTML();
  }

  function drawProfile(animate) {
    const w = current();
    const box = $('wk-profile');
    const docCount = docs.length;
    box.innerHTML = `${heroHTML()}
      <nav class="wk-tabs" role="tablist">
        ${[['agreement', 'Agreement'], ['details', 'Details'], ['documents', `Documents${docCount ? ` <span>${docCount}</span>` : ''}`]]
          .map(([k, l]) => `<button type="button" role="tab" class="${tab === k ? 'on' : ''}" data-tab="${k}" aria-selected="${tab === k}" data-no-icon>${l}</button>`).join('')}
        <span class="wk-tab-ink" aria-hidden="true"></span>
      </nav>
      <div class="wk-panel" id="wk-panel"></div>`;
    box.classList.toggle('enter', !!animate);
    drawPanel();
    placeInk();
    if (w) document.title = `${w.name} — Workers — ScaffoldPro`;
  }
  function placeInk() {
    const on = document.querySelector('.wk-tabs button.on');
    const ink = document.querySelector('.wk-tab-ink');
    if (on && ink) { ink.style.width = `${on.offsetWidth}px`; ink.style.transform = `translateX(${on.offsetLeft}px)`; }
  }
  function drawPanel() {
    const panel = $('wk-panel');
    if (!panel) return;
    if (tab === 'details') panel.innerHTML = detailsHTML();
    else if (tab === 'documents') panel.innerHTML = documentsHTML();
    else panel.innerHTML = agreementHTML();
    panel.classList.remove('swap');
    void panel.offsetWidth;
    panel.classList.add('swap');
    if (tab === 'details') checkId();
  }

  // ---- Details: saved as they're changed ----
  function detailsHTML() {
    const w = current();
    const f = (key, label, value, extra = '') => `<label class="wk-f"><span>${label}</span><input data-w="${key}" value="${esc(value)}" ${extra} /></label>`;
    return `<div class="wk-cards">
      <section class="wk-box">
        <h3>${I.id} Identity</h3>
        <div class="wk-form">
          ${f('name', 'Name', w.name, 'type="text" autocomplete="off"')}
          ${f('chineseName', 'Chinese name', w.chineseName, 'type="text" placeholder="e.g. 陳大文" autocomplete="off"')}
          <div class="wk-f"><span>On the agreement</span><div class="wk-seg" data-w-seg="honorific">${['先生', '女士'].map((h) => `<button type="button" data-v="${h}" class="${(w.honorific || '先生') === h ? 'on' : ''}" data-no-icon>${h} ${h === '先生' ? 'Mr' : 'Ms'}</button>`).join('')}</div></div>
          <label class="wk-f"><span>ID card no.</span><input data-w="idNumber" value="${esc(w.idNumber)}" type="text" placeholder="A123456(7)" spellcheck="false" autocomplete="off" /><em class="wk-hint" id="wk-id-hint"></em></label>
        </div>
      </section>
      <section class="wk-box">
        <h3>${I.cash} Work</h3>
        <div class="wk-form">
          ${f('position', 'Position', w.position, 'type="text" list="wk-positions" placeholder="Scaffolder"')}
          <label class="wk-f"><span>Daily wage</span><span class="wk-money"><i>HK$</i><input data-w="dailyWage" type="number" min="0" step="10" value="${esc(w.dailyWage ?? '')}" placeholder="1300" /><i>/ day</i></span></label>
          ${f('startDate', 'Started', w.startDate, 'type="date"')}
          ${f('endDate', 'Left', w.endDate, 'type="date"')}
        </div>
      </section>
      <section class="wk-box">
        <h3>${I.phone} Contact</h3>
        <div class="wk-form">
          ${f('phone', 'Phone', w.phone, 'type="tel"')}
          ${f('email', 'Email', w.email, 'type="email"')}
          <label class="wk-f span-2"><span>Notes</span><textarea data-w="notes" rows="3" placeholder="Anything worth remembering — sizes, languages, who referred them…">${esc(w.notes)}</textarea></label>
        </div>
      </section>
    </div>
    <p class="wk-foot">Changes are saved as you go. The agreement uses these details when it’s exported or signed.</p>`;
  }
  function checkId() {
    const input = document.querySelector('[data-w="idNumber"]');
    const hint = $('wk-id-hint');
    if (!input || !hint) return;
    const v = input.value.trim();
    const r = hkid(v);
    hint.className = `wk-hint ${!v ? '' : r.ok ? 'ok' : 'bad'}`;
    hint.innerHTML = !v ? 'Printed on the agreement' : r.ok ? `${I.check} Valid Hong Kong ID` : 'Check it — the last digit doesn’t match';
  }
  async function saveWorker(changes, el) {
    const w = current();
    const next = { ...w, ...changes };
    const payload = {};
    for (const k of ['name', 'chineseName', 'honorific', 'idNumber', 'dailyWage', 'position', 'phone', 'email', 'startDate', 'endDate', 'notes']) payload[k] = next[k] == null ? '' : String(next[k]);
    if (!payload.name.trim()) { await window.appAlert('A worker needs a name.'); drawPanel(); return; }
    const r = await api().workers.update(w.id, payload);
    if (r && r.ok === false) { await window.appAlert(r.error); return; }
    Object.assign(w, changes, { dailyWage: changes.dailyWage !== undefined ? (Number(changes.dailyWage) || null) : w.dailyWage });
    if (el) { const f = el.closest('.wk-f'); if (f) { f.classList.remove('saved'); void f.offsetWidth; f.classList.add('saved'); } }
    await loadRoster();
    drawStats();
    drawList();
    page = await api().workerAgreements.get(w.id);
    drawHero();
  }

  // ---- Agreement: steps, terms, the paper, exports, signing, the signed copy ----
  function agreementHTML() {
    const w = current();
    if (!page || !page.agreement) {
      return `<div class="wk-empty-big">${I.doc}<b>No employment agreement yet</b><span>Make one from the company’s template with ${esc(w.name)}’s details.</span><button type="button" class="primary" data-act="create" data-no-icon>Make Agreement</button></div>`;
    }
    const a = page.agreement;
    const r = entry() || { stage: 1 };
    const steps = [
      { label: 'Written', sub: day(a.createdAt), done: true },
      { label: 'Signed & chopped', sub: a.employerSignedBy ? `${person(a.employerSignedBy)} · ${day(a.employerSignedAt)}` : 'for the company', done: r.stage >= 2 },
      { label: 'Signed by the worker', sub: a.signedCopyPath ? `copy added ${day(a.signedCopyAt)}` : 'their signed copy', done: r.stage >= 3 },
    ];
    const nowAt = steps.findIndex((s) => !s.done);
    const signers = page.signers || [];
    const chosen = a.employerSignedBy || a.signatory || '';
    const locked = !!a.employerSignedBy;
    const field = (key, label, html) => `<label class="wk-f"><span>${label}</span>${html}</label>`;
    return `<div class="wk-agree">
      <div class="wk-agree-main">
        <ol class="wk-steps">
          ${steps.map((s, i) => `<li class="${s.done ? 'done' : i === nowAt ? 'now' : ''}"><span class="wk-step-dot">${s.done ? I.check : i + 1}</span><b>${esc(s.label)}</b><small>${esc(s.sub)}</small></li>`).join('')}
        </ol>

        <section class="wk-box">
          <h3>${I.doc} Terms <span class="wk-box-note">${locked ? 'Signed — changing a term takes the signature off' : 'Saved as you change them'}</span></h3>
          <div class="wk-form four">
            ${field('agreementDate', 'Agreement date', `<input type="date" data-a="agreementDate" value="${esc(a.agreementDate)}" />`)}
            ${field('startDate', 'Starts', `<input type="date" data-a="startDate" value="${esc(a.startDate)}" />`)}
            ${field('position', 'Position', `<input type="text" data-a="position" list="wk-positions" value="${esc(a.position)}" />`)}
            ${field('dailyWage', 'Daily wage', `<span class="wk-money"><i>HK$</i><input type="number" min="0" step="10" data-a="dailyWage" value="${esc(a.dailyWage)}" /></span>`)}
            <label class="wk-f span-2"><span>Working hours</span><span class="wk-pair"><input type="time" data-a="hoursFrom" value="${esc(a.hoursFrom)}" /><i>to</i><input type="time" data-a="hoursTo" value="${esc(a.hoursTo)}" /></span></label>
            ${field('payDay', 'Paid on day', `<input type="number" min="1" max="28" data-a="payDay" value="${esc(a.payDay)}" />`)}
            ${field('noticeDays', 'Notice (days)', `<input type="number" min="0" max="365" data-a="noticeDays" value="${esc(a.noticeDays)}" />`)}
            <label class="wk-f span-4"><span>Signed for the company by</span><select data-a="signatory" ${locked || !signers.length ? 'disabled' : ''}>${signers.length
              ? (chosen && !signers.includes(chosen) ? [chosen, ...signers] : signers).map((n) => `<option value="${esc(n)}" ${n === chosen ? 'selected' : ''}>${esc(person(n))}</option>`).join('')
              : '<option>No one yet — tick “Worker agreements” for them on the Team page</option>'}</select></label>
          </div>
          ${(page.missing || []).length ? `<div class="wk-missing">Still to fill in: ${page.missing.map(esc).join('; ')}.</div>` : ''}
        </section>

        <section class="wk-box">
          <h3>${I.pen} Signing</h3>
          ${a.employerSignedBy
            ? `<div class="wk-row ok"><span class="wk-row-icon">${I.check}</span><span class="wk-row-text">Signed &amp; chopped by <b>${esc(person(a.employerSignedBy))}</b> on ${esc(day(a.employerSignedAt))}${page.employerSignedExists ? '' : ' — <span class="wk-warn">the PDF isn’t in the folder any more</span>'}</span>
                <span class="wk-row-actions">${page.employerSignedExists ? '<button type="button" data-act="view-signed" data-no-icon>View</button>' : ''}<button type="button" class="danger-btn" data-act="unsign" data-no-icon>Withdraw</button></span></div>`
            : page.canSign
              ? `<div class="wk-row"><span class="wk-row-icon pen">${I.pen}</span><span class="wk-row-text">${page.hasSignature ? 'Your signature and the company chop go on the employer’s side.' : 'Add your signature on the Team page (your name › Signature) first.'}</span>
                  <span class="wk-row-actions"><button type="button" class="primary" data-act="sign" ${page.hasSignature ? '' : 'disabled'} data-no-icon>Sign &amp; Chop</button></span></div>`
              : `<div class="wk-row muted"><span class="wk-row-icon pen">${I.pen}</span><span class="wk-row-text">${signers.length ? `To be signed and chopped by ${esc(signers.map(person).join(' or '))}.` : 'No one signs worker agreements yet — tick “Worker agreements” for them on the Team page.'}</span></div>`}
          ${a.signedCopyPath
            ? `<div class="wk-row ok"><span class="wk-row-icon">${I.check}</span><span class="wk-row-text">Signed by ${esc(w.name)} — copy added ${esc(day(a.signedCopyAt))}${page.signedCopyExists ? '' : ' — <span class="wk-warn">it isn’t in the folder any more</span>'}</span>
                <span class="wk-row-actions">${page.signedCopyExists ? '<button type="button" data-act="open-copy" data-no-icon>Open</button><button type="button" data-act="reveal-copy" data-no-icon>Show in Finder</button>' : ''}<button type="button" data-act="upload" data-no-icon>Replace…</button></span></div>`
            : `<div class="wk-drop" data-drop="signed"><span class="wk-row-icon">${I.upload}</span><span class="wk-row-text"><b>The copy signed by ${esc(w.name.split(/[ ,]/)[0])}</b><small>Drop the scan or photo here — or</small></span><span class="wk-row-actions"><button type="button" data-act="upload" data-no-icon>Choose File…</button></span></div>`}
        </section>
      </div>

      <aside class="wk-agree-side">
        <div class="wk-paper-wrap">
          <div class="wk-paper" id="wk-paper">${paperHTML(w, a)}</div>
          <div class="wk-paper-fade" aria-hidden="true"></div>
          <span class="wk-paper-badge">${esc(page.number)}</span>
        </div>
        <div class="wk-exports">
          <button type="button" class="primary" data-act="pdf" data-no-icon>${I.eye}Preview PDF</button>
          <button type="button" data-act="word" data-no-icon>${I.word}Word</button>
          <button type="button" data-act="print" data-no-icon>${I.print}Print</button>
        </div>
        <p class="wk-foot center">Saved into ${esc(w.workerNumber)}’s Contracts folder.</p>
      </aside>
    </div>`;
  }
  function livePaper() {
    const paper = $('wk-paper');
    if (!paper || !page || !page.agreement) return;
    const draft = { ...page.agreement };
    for (const el of document.querySelectorAll('[data-a]')) draft[el.dataset.a] = el.dataset.a === 'dailyWage' ? Number(el.value) : el.value;
    paper.innerHTML = paperHTML(current(), draft);
  }
  async function saveTerm(el) {
    const a = page.agreement;
    const key = el.dataset.a;
    if (a.employerSignedBy && key !== 'signatory'
      && !await window.appConfirm(`Change the agreement’s terms?\n\n${person(a.employerSignedBy)}’s signature and chop come off; it will need signing again. The signed PDF stays in the folder.`, { ok: 'Change' })) {
      drawPanel();
      return;
    }
    const r = await api().workerAgreements.update(a.id, { [key]: el.value });
    if (r && r.ok === false) { await window.appAlert(r.error); }
    else { const f = el.closest('.wk-f'); if (f) { f.classList.remove('saved'); void f.offsetWidth; f.classList.add('saved'); } }
    await refreshAgreement(!!a.employerSignedBy && key !== 'signatory');
  }
  async function refreshAgreement(redraw = true) {
    page = await api().workerAgreements.get(selectedId);
    await loadRoster();
    drawStats();
    drawList();
    drawHero();
    if (redraw && tab === 'agreement') drawPanel(); else livePaper();
  }
  async function viewSigned(path) {
    const r = await window.docPreview.pdf(() => api().signatures.previewSigned(path), {
      title: `${page.number} — Signed & Chopped`,
      note: 'Saved in the worker’s Contracts folder. Print it for the worker to sign.',
      actions: [{ key: 'open', label: 'Open in Preview' }, { key: 'done', label: 'Done', primary: true }],
    });
    if (r && r.action === 'open') api().workerAgreements.file(page.agreement.id, 'employer', 'open');
  }
  async function storeSignedFile(file) {
    const reader = new FileReader();
    reader.onload = async () => {
      const r = await api().workerAgreements.saveSignedFile(page.agreement.id, file.name, String(reader.result).split(',')[1] || '');
      if (r && r.ok === false) { await window.appAlert(r.error); return; }
      toast('Signed copy added — the agreement is complete');
      await refreshAgreement();
    };
    reader.readAsDataURL(file);
  }

  // ---- Documents ----
  const CATEGORIES = ['Certification', 'Training Certificate', 'Identification', 'Employment Contract', 'Other'];
  function daysLeft(d) {
    if (!d) return null;
    const t = new Date(); t.setHours(0, 0, 0, 0);
    return Math.round((new Date(`${String(d).slice(0, 10)}T00:00:00`) - t) / 86400000);
  }
  function kindOf(doc) {
    const ext = String(doc.fileType || doc.originalName.split('.').pop() || '').toLowerCase();
    return ext === 'pdf' ? 'pdf' : ['png', 'jpg', 'jpeg', 'heic', 'gif', 'tif', 'tiff', 'webp'].includes(ext) ? 'img' : ['doc', 'docx'].includes(ext) ? 'doc' : ['xls', 'xlsx', 'csv'].includes(ext) ? 'xls' : 'file';
  }
  function documentsHTML() {
    const tiles = docs.map((d) => {
      const left = daysLeft(d.expiryDate);
      const exp = left == null ? '' : left < 0 ? `<span class="wk-exp bad">Expired ${-left} day${left === -1 ? '' : 's'} ago</span>`
        : left <= 30 ? `<span class="wk-exp warn">Expires in ${left} day${left === 1 ? '' : 's'}</span>` : `<span class="wk-exp">Until ${esc(day(d.expiryDate))}</span>`;
      const k = kindOf(d);
      return `<article class="wk-doc${d.fileExists ? '' : ' missing'}" data-doc="${esc(d.id)}">
        <span class="wk-doc-kind k-${k}">${k === 'file' ? esc(String(d.fileType || 'FILE').slice(0, 4)) : k.toUpperCase()}</span>
        <div class="wk-doc-text">
          <b title="${esc(d.originalName)}">${esc(d.description || d.originalName)}</b>
          <small>${esc(d.category)}${d.description ? ` · ${esc(d.originalName)}` : ''}</small>
          ${d.fileExists ? exp : '<span class="wk-exp bad">File moved or missing</span>'}
        </div>
        <div class="wk-doc-tools">
          ${d.fileExists ? `<button type="button" data-doc-act="open" data-no-icon>Open</button><button type="button" data-doc-act="reveal" title="Show in Finder" data-no-icon>Finder</button>` : '<button type="button" data-doc-act="relink" data-no-icon>Find…</button>'}
          <label class="wk-doc-exp" title="Expiry date (optional) — you’re reminded 30 days before">${I.cal}<input type="date" data-doc-exp value="${esc((d.expiryDate || '').slice(0, 10))}" /></label>
          <button type="button" class="wk-icon small" data-doc-act="archive" title="Archive" aria-label="Archive" data-no-icon>${I.archive}</button>
        </div>
      </article>`;
    }).join('');
    return `<div class="wk-docs">
      <div class="wk-drop big" data-drop="docs">
        <span class="wk-row-icon">${I.upload}</span>
        <span class="wk-row-text"><b>Add certificates, ID or other documents</b><small>Choose the kind, then add or drop the files. Expiry dates are optional.</small></span>
        <span class="wk-row-actions">
          <select id="wk-doc-cat">${CATEGORIES.map((c) => `<option>${c}</option>`).join('')}</select>
          <button type="button" class="primary" data-act="add-docs" data-no-icon>Add Files…</button>
        </span>
      </div>
      ${docs.length ? `<div class="wk-doc-grid">${tiles}</div>` : '<div class="wk-list-empty soft"><b>No documents yet</b><span>Green cards, safety training, ID and more. Drop files here or use Add Files….</span></div>'}
    </div>`;
  }
  // Files dropped on the Documents tab: added as the chosen kind, no expiry needed.
  async function addDroppedDocuments(files) {
    const cat = $('wk-doc-cat') ? $('wk-doc-cat').value : 'Other';
    const read = (file) => new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(String(reader.result).split(',')[1] || '');
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(file);
    });
    const failed = [];
    let added = 0;
    for (const file of files) {
      try {
        const r = await api().workerDocuments.addFile(selectedId, cat, file.name, await read(file));
        if (r && r.ok === false) failed.push(r.error); else added++;
      } catch (e) { failed.push(`${file.name}: ${e.message}`); }
    }
    if (added) toast(`${added} document${added === 1 ? '' : 's'} added`);
    await refreshDocs();
    if (failed.length) await window.appAlert(`Not every document could be added.\n\n${failed.join('\n')}`);
  }
  async function refreshDocs() {
    docs = await api().workerDocuments.list(selectedId);
    await loadRoster();
    drawStats();
    drawList();
    drawHero();
    const tabBtn = document.querySelector('[data-tab="documents"]');
    if (tabBtn) tabBtn.innerHTML = `Documents${docs.length ? ` <span>${docs.length}</span>` : ''}`;
    if (tab === 'documents') drawPanel();
  }

  // ---- actions ----
  async function act(name, button) {
    const w = current();
    const a = page && page.agreement;
    switch (name) {
      case 'new': openSheet(); break;
      case 'folder': api().workers.revealFolder(w.id); break;
      case 'archive': {
        const archiving = !w.isArchived;
        if (archiving && !await window.appConfirm(`Archive ${w.name}?\n\nTheir record, agreement and files are kept; they just leave the list.`, { ok: 'Archive' })) return;
        await api().workers.setArchived(w.id, archiving);
        toast(archiving ? `${w.name} archived` : `${w.name} is back on the list`);
        await load(false);
        break;
      }
      case 'create': {
        const r = await api().workerAgreements.create(w.id);
        if (r && r.ok === false) { await window.appAlert(r.error); return; }
        tab = 'agreement'; store.set('tab', tab);
        await refreshAgreement();
        drawProfile(false);
        toast('Agreement written from the template');
        break;
      }
      case 'focus-id': setTab('details'); setTimeout(() => { const el = document.querySelector('[data-w="idNumber"]'); if (el) el.focus(); }, 60); break;
      case 'tab-agreement': setTab('agreement'); break;
      case 'tab-documents': setTab('documents'); break;
      case 'pdf': {
        const r = await window.docPreview.pdf(() => api().workerAgreements.exportPDF(a.id, { preview: true }), { title: `${page.number} Employment Agreement`, note: 'Saved into the worker’s Contracts folder when you click Save.' });
        if (r && r.ok === false) await window.appAlert(r.error);
        break;
      }
      case 'word': {
        button.disabled = true;
        try {
          const r = await window.exportWord(() => api().workerAgreements.exportWord(a.id));
          if (r && r.ok === false) await window.appAlert(r.error);
        } catch (e) { await window.appAlert(`The Word document couldn't be made.\n\n${e.message}`); }
        button.disabled = false;
        break;
      }
      case 'print': { const r = await api().workerAgreements.print(a.id); if (r && r.ok === false) await window.appAlert(r.error); break; }
      case 'sign': {
        if (tab !== 'agreement') setTab('agreement');
        if ((page.missing || []).length && !await window.appConfirm(`Sign it without ${page.missing.join(' and ')}?\n\nThat line is left blank on the agreement.`, { ok: 'Sign Anyway' })) return;
        if (button) { button.disabled = true; button.textContent = 'Signing…'; }
        const r = await api().workerAgreements.sign(a.id);
        if (!r || r.ok === false) { await window.appAlert((r && r.error) || 'It couldn’t be signed.'); await refreshAgreement(); return; }
        toast('Signed and chopped');
        await refreshAgreement();
        viewSigned(r.path);
        break;
      }
      case 'view-signed': viewSigned(a.employerSignedPath); break;
      case 'unsign':
        if (!await window.appConfirm(`Withdraw ${person(a.employerSignedBy)}’s signature and chop?\n\nThe signed PDF goes to the Trash.`, { ok: 'Withdraw', danger: true })) return;
        await api().workerAgreements.unsign(a.id);
        await refreshAgreement();
        break;
      case 'upload': {
        if (tab !== 'agreement') setTab('agreement');
        const r = await api().workerAgreements.uploadSigned(a.id);
        if (r && r.ok === false) { await window.appAlert(r.error); return; }
        if (r && r.ok) toast('Signed copy added — the agreement is complete');
        await refreshAgreement();
        break;
      }
      case 'open-copy': { const r = await api().workerAgreements.file(a.id, 'signed', 'open'); if (r && r.ok === false) window.appAlert(r.error); break; }
      case 'reveal-copy': { const r = await api().workerAgreements.file(a.id, 'signed', 'reveal'); if (r && r.ok === false) window.appAlert(r.error); break; }
      case 'add-docs': {
        try { await api().workerDocuments.upload(w.id, $('wk-doc-cat').value, null); } catch (e) { await window.appAlert(`Not every document could be added.\n\n${e.message}`); }
        await refreshDocs();
        break;
      }
      default: break;
    }
  }
  function setTab(k) {
    tab = k;
    store.set('tab', k);
    for (const b of document.querySelectorAll('.wk-tabs [data-tab]')) { b.classList.toggle('on', b.dataset.tab === k); b.setAttribute('aria-selected', String(b.dataset.tab === k)); }
    placeInk();
    drawPanel();
  }

  // ---- New worker ----
  let honorific = '先生';
  function openSheet() {
    for (const id of ['ns-name', 'ns-chineseName', 'ns-idNumber', 'ns-dailyWage', 'ns-position', 'ns-startDate', 'ns-phone', 'ns-email']) $(id).value = '';
    honorific = '先生';
    for (const b of document.querySelectorAll('#ns-honorific button')) b.classList.toggle('on', b.dataset.v === honorific);
    $('ns-error').classList.add('hidden');
    sheetPreview();
    $('wk-sheet').classList.remove('hidden');
    requestAnimationFrame(() => $('wk-sheet').classList.add('open'));
    setTimeout(() => $('ns-name').focus(), 60);
  }
  function closeSheet() {
    $('wk-sheet').classList.remove('open');
    setTimeout(() => $('wk-sheet').classList.add('hidden'), 180);
  }
  function sheetDraft() {
    const today = new Date(Date.now() - new Date().getTimezoneOffset() * 60000).toISOString().slice(0, 10);
    return {
      w: { name: $('ns-name').value.trim(), chineseName: $('ns-chineseName').value.trim(), honorific, idNumber: $('ns-idNumber').value.trim() },
      a: { agreementDate: today, startDate: $('ns-startDate').value || today, position: $('ns-position').value.trim() || 'Scaffolder',
        dailyWage: Number($('ns-dailyWage').value) || 1300, hoursFrom: '08:00', hoursTo: '18:00', payDay: 7, noticeDays: 7 },
    };
  }
  function sheetPreview() {
    const d = sheetDraft();
    const shown = { ...d.w, workerNumber: '' };
    const [a, b] = hue(d.w.name || 'new');
    const av = $('ns-avatar');
    av.textContent = d.w.name ? initials(shown) : '+';
    av.style.setProperty('--a', a);
    av.style.setProperty('--b', b);
    $('ns-paper').innerHTML = `<div class="wk-mini-label">The agreement it writes</div><div class="wk-paper small">${paperHTML(shown, d.a, { short: true })}</div>`;
    const v = d.w.idNumber;
    const r = hkid(v);
    const hint = $('ns-id-hint');
    hint.className = `wk-hint ${!v ? '' : r.ok ? 'ok' : 'bad'}`;
    hint.innerHTML = !v ? '' : r.ok ? `${I.check} Valid` : 'Check the last digit';
  }
  async function saveSheet() {
    const name = $('ns-name').value.trim();
    const err = $('ns-error');
    if (!name) { err.textContent = 'Enter their name.'; err.classList.remove('hidden'); $('ns-name').focus(); return; }
    const id = hkid($('ns-idNumber').value);
    const r = await api().workers.create({
      name, chineseName: $('ns-chineseName').value, honorific, idNumber: id.ok ? id.formatted : $('ns-idNumber').value,
      dailyWage: $('ns-dailyWage').value, position: $('ns-position').value, startDate: $('ns-startDate').value,
      phone: $('ns-phone').value, email: $('ns-email').value,
    });
    if (!r || !r.ok) { err.textContent = (r && r.error) || 'The worker couldn’t be added.'; err.classList.remove('hidden'); return; }
    closeSheet();
    selectedId = r.worker.id;
    tab = 'agreement'; store.set('tab', tab);
    filter = 'all'; store.set('filter', filter);
    await load(false);
    const card = document.querySelector(`.wk-card[data-id="${CSS.escape(r.worker.id)}"]`);
    if (card) { card.scrollIntoView({ block: 'nearest' }); card.classList.add('fresh'); }
    toast(`${r.worker.workerNumber} added — the agreement is written`);
  }

  // ---- wiring ----
  function wire() {
    $('wk-new').addEventListener('click', openSheet);
    $('wk-search').addEventListener('input', (e) => { query = e.target.value; drawList(); });
    $('wk-search').addEventListener('keydown', (e) => {
      if (e.key === 'Escape') { e.target.value = ''; query = ''; drawList(); e.target.blur(); }
      if (e.key === 'Enter') { const first = visible()[0]; if (first) openWorker(first.worker.id); }
    });
    $('wk-show-archived').addEventListener('change', () => load(false));
    $('wk-stats').addEventListener('click', (e) => {
      const t = e.target.closest('[data-filter]');
      if (!t) return;
      filter = filter === t.dataset.filter ? 'all' : t.dataset.filter;
      store.set('filter', filter);
      drawStats();
      drawList();
      const list = visible();
      if (list.length && !list.some((r) => r.worker.id === selectedId)) openWorker(list[0].worker.id);
    });
    $('wk-list').addEventListener('click', (e) => {
      const all = e.target.closest('[data-filter]');
      if (all) { filter = 'all'; store.set('filter', filter); drawStats(); drawList(); return; }
      const card = e.target.closest('.wk-card');
      if (card && card.dataset.id !== selectedId) openWorker(card.dataset.id);
    });
    $('wk-list').addEventListener('keydown', (e) => {
      if (e.key !== 'ArrowDown' && e.key !== 'ArrowUp') return;
      e.preventDefault();
      const list = visible();
      const i = list.findIndex((r) => r.worker.id === selectedId);
      const next = list[Math.max(0, Math.min(list.length - 1, i + (e.key === 'ArrowDown' ? 1 : -1)))];
      if (next) { openWorker(next.worker.id); const c = document.querySelector(`.wk-card[data-id="${CSS.escape(next.worker.id)}"]`); if (c) c.scrollIntoView({ block: 'nearest' }); }
    });

    const profile = $('wk-profile');
    profile.addEventListener('click', (e) => {
      const t = e.target.closest('[data-tab]');
      if (t) { setTab(t.dataset.tab); return; }
      const copy = e.target.closest('[data-copy]');
      if (copy) { navigator.clipboard.writeText(copy.dataset.copy).then(() => toast('Phone number copied'), () => {}); return; }
      const seg = e.target.closest('[data-w-seg] button');
      if (seg) {
        for (const b of seg.parentElement.children) b.classList.toggle('on', b === seg);
        saveWorker({ [seg.parentElement.dataset.wSeg]: seg.dataset.v }, seg);
        return;
      }
      const docBtn = e.target.closest('[data-doc-act]');
      if (docBtn) { docAction(docBtn.closest('[data-doc]').dataset.doc, docBtn.dataset.docAct); return; }
      const b = e.target.closest('[data-act]');
      if (b && !b.disabled) act(b.dataset.act, b);
    });
    profile.addEventListener('change', (e) => {
      const el = e.target;
      if (el.dataset.w) {
        let v = el.value;
        if (el.dataset.w === 'idNumber') { const r = hkid(v); if (r.ok) { v = r.formatted; el.value = v; } }
        saveWorker({ [el.dataset.w]: v }, el);
      } else if (el.dataset.a) {
        saveTerm(el);
      } else if (el.matches('[data-doc-exp]')) {
        const id = el.closest('[data-doc]').dataset.doc;
        const d = docs.find((x) => x.id === id);
        api().workerDocuments.update(id, { description: d ? d.description || null : null, expiryDate: el.value || null }).then(refreshDocs);
      }
    });
    profile.addEventListener('input', (e) => {
      if (e.target.dataset.a) livePaper();
      if (e.target.dataset.w === 'idNumber') checkId();
    });
    // Files dropped: the signed copy (agreement), or documents.
    let depth = 0;
    const hasFiles = (e) => e.dataTransfer && [...e.dataTransfer.types].includes('Files');
    profile.addEventListener('dragenter', (e) => { if (!hasFiles(e)) return; depth++; profile.classList.add('dropping'); });
    profile.addEventListener('dragleave', (e) => { if (!hasFiles(e)) return; depth = Math.max(0, depth - 1); if (!depth) profile.classList.remove('dropping'); });
    profile.addEventListener('dragover', (e) => { if (hasFiles(e)) e.preventDefault(); });
    profile.addEventListener('drop', async (e) => {
      if (!hasFiles(e)) return;
      e.preventDefault();
      depth = 0;
      profile.classList.remove('dropping');
      const files = [...e.dataTransfer.files];
      if (!files.length) return;
      if (tab === 'agreement' && page && page.agreement) { storeSignedFile(files[0]); return; }
      if (tab === 'documents') addDroppedDocuments(files);
    });

    // The new-worker sheet.
    for (const id of ['ns-name', 'ns-chineseName', 'ns-idNumber', 'ns-dailyWage', 'ns-position', 'ns-startDate']) $(id).addEventListener('input', sheetPreview);
    $('ns-honorific').addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b) return;
      honorific = b.dataset.v;
      for (const x of $('ns-honorific').children) x.classList.toggle('on', x === b);
      sheetPreview();
    });
    $('ns-idNumber').addEventListener('blur', () => { const r = hkid($('ns-idNumber').value); if (r.ok) $('ns-idNumber').value = r.formatted; });
    $('ns-cancel').addEventListener('click', closeSheet);
    $('ns-save').addEventListener('click', saveSheet);
    $('wk-sheet').addEventListener('keydown', (e) => {
      if (e.key === 'Escape') { e.preventDefault(); closeSheet(); }
      if (e.key === 'Enter' && !e.isComposing && e.target.tagName === 'INPUT') { e.preventDefault(); saveSheet(); }
    });
    $('wk-sheet').addEventListener('mousedown', (e) => { if (e.target === $('wk-sheet')) closeSheet(); });

    document.addEventListener('keydown', (e) => {
      const typing = /^(INPUT|TEXTAREA|SELECT)$/.test((document.activeElement || {}).tagName || '');
      if (e.key === '/' && !typing && !e.metaKey) { e.preventDefault(); $('wk-search').focus(); }
      if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === 'n' && !e.shiftKey && $('wk-sheet').classList.contains('hidden')) { e.preventDefault(); openSheet(); }
    });
    window.addEventListener('resize', placeInk);
  }

  async function docAction(id, action) {
    const d = docs.find((x) => x.id === id);
    const w = api().workerDocuments;
    let r;
    if (action === 'open') r = await w.open(id);
    else if (action === 'reveal') r = await w.reveal(id);
    else if (action === 'relink') r = await w.relink(id);
    else if (action === 'archive') {
      if (!await window.appConfirm(`Archive “${d ? d.originalName : 'this document'}”?\n\nThe file stays in the folder; it just leaves the list.`, { ok: 'Archive' })) return;
      r = await w.archive(id);
    }
    if (r && r.ok === false) await window.appAlert(r.error);
    if (action !== 'open' && action !== 'reveal') refreshDocs();
  }

  async function init() {
    wire();
    const wanted = new URLSearchParams(location.search).get('worker');
    selectedId = wanted || store.get('selected', null);
    await loadRoster();
    if (wanted && !roster.some((r) => r.worker.id === wanted)) {
      $('wk-show-archived').checked = true;
      await loadRoster();
    }
    if (filter !== 'all' && !visible().length) filter = 'all';
    drawStats();
    drawList();
    if (!roster.some((r) => r.worker.id === selectedId)) selectedId = visible()[0] ? visible()[0].worker.id : null;
    await openWorker(selectedId);
    document.body.classList.add('wk-ready');
  }
  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', init); else init();
})();

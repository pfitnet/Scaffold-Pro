'use strict';

// Marketing › Overview: how quotations are turning into work, to explore.
//   • Filters across the top — 3, 6 or 12 months; value or count — change
//     everything below them.
//   • The headline: what was quoted, against the period before, and how
//     much of it was won.
//   • Month columns: won (strong blue) under not-won-yet (light blue).
//     Hover or focus one for its figures; click one to look at that month
//     on its own (click again, or its chip, to go back).
//   • Top Clients: click one to see only their quotations.
//   • The quotations behind whatever is picked, newest first.
//   • Where leads come from, and how many of them were won.
//
//   window.marketingOverview.render(summary, leads);

(function () {
  const SHOWN = 6;
  const QUOTES_SHOWN = 8;
  let summary = null;
  let leads = [];
  const state = { range: 12, measure: 'value', month: null, client: null, clientsOpen: false, quotesOpen: false };
  try {
    const saved = JSON.parse(localStorage.getItem('marketing.overview') || '{}');
    if ([3, 6, 12].includes(saved.range)) state.range = saved.range;
    if (['value', 'count'].includes(saved.measure)) state.measure = saved.measure;
  } catch (e) { /* defaults */ }
  const remember = () => { try { localStorage.setItem('marketing.overview', JSON.stringify({ range: state.range, measure: state.measure })); } catch (e) { /* ignore */ } };
  const calm = () => window.matchMedia && window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  const $ = (id) => document.getElementById(id);
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const cur = () => (summary.currency === 'HKD' ? 'HK$' : summary.currency);
  const money = (v) => Number(v || 0).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 0 });
  const short = (v) => {
    const n = Math.abs(Number(v || 0));
    const sign = v < 0 ? '−' : '';
    if (n >= 1e6) return `${sign}${(n / 1e6).toLocaleString('en-US', { maximumFractionDigits: 1 })}M`;
    if (n >= 1e3) return `${sign}${(n / 1e3).toLocaleString('en-US', { maximumFractionDigits: n >= 1e4 ? 0 : 1 })}k`;
    return `${sign}${n.toLocaleString('en-US', { maximumFractionDigits: 0 })}`;
  };
  const plural = (n, one, many) => `${n} ${n === 1 ? one : (many || `${one}s`)}`;
  const monthDate = (key) => { const [y, m] = key.split('-').map(Number); return new Date(y, m - 1, 1); };
  const monthShort = (key) => monthDate(key).toLocaleDateString('en-GB', { month: 'short' });
  const monthLong = (key) => monthDate(key).toLocaleDateString('en-GB', { month: 'long', year: 'numeric' });
  const dayLabel = (d) => new Date(`${d}T00:00:00`).toLocaleDateString('en-GB', { day: 'numeric', month: 'short' });
  const amount = (v) => (state.measure === 'value' ? `${cur()} ${money(v)}` : String(v));

  // ---- the slices ----

  const rangeMonths = () => summary.months.slice(-state.range).map((m) => m.month);
  const prevMonths = () => summary.months.slice(-2 * state.range, -state.range).map((m) => m.month);
  const quotesIn = (months, { client = state.client, month = null } = {}) => {
    const set = new Set(months);
    return summary.quotes.filter((q) => set.has(q.month) && (!client || q.clientId === client) && (!month || q.month === month));
  };
  const totals = (qs) => {
    const t = { value: 0, count: qs.length, wonValue: 0, wonCount: 0 };
    for (const q of qs) { t.value += q.value; if (q.won) { t.wonValue += q.value; t.wonCount += 1; } }
    return t;
  };
  const measureOf = (t) => (state.measure === 'value' ? t.value : t.count);
  const wonOf = (t) => (state.measure === 'value' ? t.wonValue : t.wonCount);
  const clientName = (id) => {
    const q = summary.quotes.find((x) => x.clientId === id);
    return (q && q.clientName) || 'Client';
  };

  // ---- the hover card ----

  function tip(html, x, y) {
    const el = $('mo-tip');
    el.innerHTML = html;
    el.classList.remove('hidden');
    const w = el.offsetWidth;
    const h = el.offsetHeight;
    const left = x + 16 + w > innerWidth - 8 ? x - w - 16 : x + 16;
    const top = Math.max(8, Math.min(innerHeight - h - 8, y - h / 2));
    el.style.left = `${left}px`;
    el.style.top = `${top}px`;
  }
  const untip = () => $('mo-tip').classList.add('hidden');
  const tipRows = (t) => {
    const open = { value: t.value - t.wonValue, count: t.count - t.wonCount };
    const rate = t.count ? Math.round((t.wonCount / t.count) * 100) : 0;
    return `<div class="mo-tip-row"><span class="k won"></span><span class="n">Won</span><span class="v">${state.measure === 'value' ? `${cur()} ${money(t.wonValue)}` : t.wonCount}</span></div>
      <div class="mo-tip-row"><span class="k open"></span><span class="n">Not won yet</span><span class="v">${state.measure === 'value' ? `${cur()} ${money(open.value)}` : open.count}</span></div>
      <div class="mo-tip-foot">${plural(t.count, 'quotation')} · ${t.wonCount} won · ${rate}% win rate</div>`;
  };

  // ---- count-up for the big number ----

  let shownBig = 0;
  let bigFrame = 0;
  function countTo(target, format) {
    cancelAnimationFrame(bigFrame);
    const from = shownBig;
    if (calm() || from === target) { shownBig = target; $('mo-big').innerHTML = format(target); return; }
    const start = performance.now();
    const step = (now) => {
      const p = Math.min(1, (now - start) / 650);
      const e = 1 - Math.pow(1 - p, 3);
      shownBig = from + (target - from) * e;
      $('mo-big').innerHTML = format(p === 1 ? target : shownBig);
      if (p < 1) bigFrame = requestAnimationFrame(step);
      else shownBig = target;
    };
    bigFrame = requestAnimationFrame(step);
  }

  // ---- headline ----

  function renderHero() {
    const scope = quotesIn(rangeMonths(), { month: state.month });
    const t = totals(scope);
    const period = state.month ? monthLong(state.month) : `last ${state.range} months`;
    $('mo-kicker').textContent = `${state.measure === 'value' ? 'Quoted' : 'Quotations sent'} · ${period}${state.client ? ` · ${clientName(state.client)}` : ''}`;
    const value = measureOf(t);
    countTo(value, (v) => (state.measure === 'value' ? `<small>${esc(cur())}</small>${money(v)}` : `${Math.round(v)}`));
    // Against the period before (when there is one inside the year).
    let delta = '';
    if (!state.month && state.range < 12) {
      const before = measureOf(totals(quotesIn(prevMonths())));
      if (before > 0) {
        const pct = Math.round(((value - before) / before) * 100);
        const dir = pct > 0 ? 'up' : pct < 0 ? 'down' : 'flat';
        delta = `<span class="mo-delta ${dir}" title="Against the ${state.range} months before">${dir === 'up' ? '▲' : dir === 'down' ? '▼' : '■'} ${Math.abs(pct)}%</span><span>vs the ${state.range} months before</span>`;
      } else if (value > 0) delta = `<span class="mo-delta up">▲ new</span><span>none the ${state.range} months before</span>`;
    }
    $('mo-sub').innerHTML = `<span>${plural(t.count, 'quotation')}${state.measure === 'count' ? ` · ${esc(cur())} ${money(t.value)}` : ''}</span>${delta}`;
    const rate = t.count ? t.wonCount / t.count : 0;
    $('mo-meter').querySelector('.mo-meter-fill').style.width = `${Math.round(rate * 100)}%`;
    $('mo-meter').classList.toggle('none', !t.count);
    $('mo-meter').setAttribute('aria-valuenow', String(Math.round(rate * 100)));
    $('mo-meter').setAttribute('aria-label', 'Win rate');
    $('mo-meter-label').innerHTML = `<b>${Math.round(rate * 100)}% won</b> — ${t.wonCount} of ${t.count}${t.wonValue ? ` · ${esc(cur())} ${money(t.wonValue)}` : ''}`;

    // Figures beside it.
    const months = rangeMonths();
    const byMonth = months.map((m) => ({ m, t: totals(quotesIn(months, { month: m })) }));
    const best = byMonth.reduce((a, b) => (measureOf(b.t) > measureOf(a.t) ? b : a), byMonth[0]);
    const activeMonths = byMonth.filter((x) => x.t.count > 0).length;
    const kpi = (label, value, sub) => `<div class="mo-kpi"><div class="mo-kpi-label">${label}</div><div class="mo-kpi-value">${value}</div><div class="mo-kpi-sub">${sub}</div></div>`;
    $('mo-kpis').innerHTML =
      kpi('Average quotation', t.count ? `${esc(cur())} ${short(t.value / t.count)}` : '—', t.count ? `over ${plural(t.count, 'quotation')}` : 'none sent') +
      kpi('Best month', best && measureOf(best.t) > 0 ? esc(monthShort(best.m)) : '—', best && measureOf(best.t) > 0 ? esc(amount(measureOf(best.t))) : 'nothing yet') +
      kpi('Busy months', `${activeMonths} of ${months.length}`, 'with a quotation sent');
  }

  // ---- the month chart ----

  function niceStep(max, ticks) {
    const raw = max / ticks;
    const p = Math.pow(10, Math.floor(Math.log10(raw || 1)));
    const n = raw / p;
    return (n <= 1 ? 1 : n <= 2 ? 2 : n <= 2.5 ? 2.5 : n <= 5 ? 5 : 10) * p;
  }
  // A bar segment: square at the bottom, 4px rounded at the top when it's the top one.
  function seg(x, y, w, h, cls, round) {
    if (h <= 0) return '';
    const r = round ? Math.min(4, w / 2, h) : 0;
    if (!r) return `<rect class="${cls}" x="${x}" y="${y}" width="${w}" height="${h}"/>`;
    return `<path class="${cls}" d="M${x},${y + h}V${y + r}Q${x},${y} ${x + r},${y}H${x + w - r}Q${x + w},${y} ${x + w},${y + r}V${y + h}Z"/>`;
  }

  function renderChart(grow) {
    const box = $('mo-chart');
    const months = rangeMonths();
    const data = months.map((m) => ({ m, t: totals(quotesIn(months, { month: m })) }));
    const W = box.clientWidth || 800;
    const H = box.clientHeight || 250;
    const pad = { l: 48, r: 8, t: 22, b: 36 };
    const pw = W - pad.l - pad.r;
    const ph = H - pad.t - pad.b;
    const max = Math.max(0, ...data.map((d) => measureOf(d.t)));
    const step = state.measure === 'count' ? Math.max(1, Math.ceil(niceStep(max || 4, 4))) : niceStep(max || 1000, 4);
    const top = Math.max(step, Math.ceil(max / step) * step);
    const y = (v) => pad.t + ph - (v / top) * ph;
    const band = pw / data.length;
    const bw = Math.min(24, Math.max(8, band * 0.5));
    let svg = `<svg viewBox="0 0 ${W} ${H}" role="group" aria-label="Quotations by month">`;
    for (let v = 0; max > 0 && v <= top + 1e-9; v += step) {
      svg += `<g class="tick"><line x1="${pad.l}" x2="${W - pad.r}" y1="${y(v)}" y2="${y(v)}"/><text x="${pad.l - 8}" y="${y(v) + 4}" text-anchor="end">${state.measure === 'value' ? short(v) : v}</text></g>`;
    }
    const peak = data.reduce((a, b) => (measureOf(b.t) > measureOf(a.t) ? b : a), data[0]);
    data.forEach((d, i) => {
      const cx = pad.l + band * i + band / 2;
      const x = cx - bw / 2;
      const total = measureOf(d.t);
      const won = wonOf(d.t);
      const open = total - won;
      const hWon = (won / top) * ph;
      const hOpen = (open / top) * ph;
      const gap = hWon > 0 && hOpen > 0 ? 2 : 0;
      const yWon = pad.t + ph - hWon;
      const yOpen = yWon - gap - hOpen;
      const on = state.month === d.m;
      const label = `${monthLong(d.m)}: ${amount(total)} ${state.measure === 'value' ? 'quoted' : 'sent'}, ${d.t.wonCount} of ${d.t.count} won`;
      svg += `<g class="col${on ? ' on' : ''}" data-m="${d.m}" data-i="${i}" tabindex="0" role="button" aria-pressed="${on}" aria-label="${esc(label)}">
        <rect class="hit" x="${pad.l + band * i + 1}" y="${pad.t - 14}" width="${band - 2}" height="${ph + 14}" rx="6"/>
        <g class="bars" style="--d:${(i * 0.035).toFixed(3)}s">${seg(x, yOpen, bw, Math.max(0, hOpen), 'seg-open', true)}${seg(x, yWon, bw, Math.max(0, hWon), 'seg-won', hOpen <= 0)}</g>
        ${total > 0 && (d === peak || on) ? `<text class="cap${d === peak || on ? '' : ' soft'}" x="${cx}" y="${Math.min(yOpen, yWon) - 7}">${state.measure === 'value' ? short(total) : total}</text>` : ''}
        <text class="xlab" x="${cx}" y="${H - pad.b + 17}">${esc(monthShort(d.m))}</text>
        ${i === 0 || d.m.endsWith('-01') ? `<text class="xlab year" x="${cx}" y="${H - pad.b + 31}">${d.m.slice(0, 4)}</text>` : ''}
      </g>`;
    });
    svg += `<line class="baseline" x1="${pad.l}" x2="${W - pad.r}" y1="${pad.t + ph + 0.5}" y2="${pad.t + ph + 0.5}"/></svg>`;
    box.innerHTML = svg + (max === 0 ? `<div class="mo-chart-empty">No quotations sent in the last ${state.range} months${state.client ? ` to ${esc(clientName(state.client))}` : ''}.</div>` : '');
    box.classList.toggle('picking', !!state.month);
    box.classList.remove('grow');
    if (grow && !calm()) { void box.offsetWidth; box.classList.add('grow'); }
    for (const col of box.querySelectorAll('.col')) {
      const d = data[Number(col.dataset.i)];
      const show = (x, yy) => tip(`<div class="mo-tip-title">${esc(monthLong(d.m))}${state.client ? ` · ${esc(clientName(state.client))}` : ''}</div>
        <div class="mo-tip-value">${esc(amount(measureOf(d.t)))} <span class="n" style="font-size:12px;font-weight:500;color:var(--text-secondary)">${state.measure === 'value' ? 'quoted' : 'sent'}</span></div>${tipRows(d.t)}`, x, yy);
      col.addEventListener('pointermove', (e) => show(e.clientX, e.clientY));
      col.addEventListener('pointerleave', untip);
      col.addEventListener('focus', () => { const r = col.getBoundingClientRect(); show(r.right, r.top + r.height / 2); });
      col.addEventListener('blur', untip);
      col.addEventListener('click', () => pickMonth(d.m));
      col.addEventListener('keydown', (e) => {
        if (e.key === 'Enter' || e.key === ' ') { e.preventDefault(); pickMonth(d.m, true); }
        if (e.key === 'ArrowRight' || e.key === 'ArrowLeft') {
          e.preventDefault();
          const next = box.querySelector(`.col[data-i="${Number(col.dataset.i) + (e.key === 'ArrowRight' ? 1 : -1)}"]`);
          if (next) next.focus();
        }
      });
    }
    renderTable(data);
  }

  function renderTable(data) {
    $('mo-table').innerHTML = `<table class="compact"><thead><tr><th>Month</th><th class="num">Sent</th><th class="num">Quoted</th><th class="num">Won</th><th class="num">Won value</th><th class="num">Win rate</th></tr></thead><tbody>${
      data.map((d) => `<tr class="display-row"><td>${esc(monthLong(d.m))}</td><td class="num">${d.t.count}</td><td class="num">${esc(cur())} ${money(d.t.value)}</td>
        <td class="num">${d.t.wonCount}</td><td class="num">${esc(cur())} ${money(d.t.wonValue)}</td><td class="num">${d.t.count ? Math.round((d.t.wonCount / d.t.count) * 100) : 0}%</td></tr>`).join('')}</tbody></table>`;
  }

  // ---- Top Clients ----

  function renderClients() {
    const box = $('mo-clients');
    const scope = quotesIn(rangeMonths(), { client: null, month: state.month });
    const by = new Map();
    for (const q of scope) {
      if (!q.clientId) continue;
      const c = by.get(q.clientId) || { id: q.clientId, name: q.clientName || 'Client', qs: [] };
      c.qs.push(q);
      by.set(q.clientId, c);
    }
    const invoiced = Object.fromEntries((summary.topClients || []).map((c) => [c.id, c.invoiced]));
    const rows = [...by.values()].map((c) => Object.assign(c, { t: totals(c.qs) }))
      .sort((a, b) => measureOf(b.t) - measureOf(a.t) || b.t.count - a.t.count);
    $('mo-clients-note').textContent = state.month ? monthLong(state.month) : `last ${state.range} months`;
    if (!rows.length) {
      box.innerHTML = `<div class="mo-empty">No quotations sent ${state.month ? `in ${esc(monthLong(state.month))}` : `in the last ${state.range} months`}.</div>`;
      return;
    }
    const max = Math.max(...rows.map((r) => measureOf(r.t))) || 1;
    const list = state.clientsOpen || state.client ? rows : rows.slice(0, SHOWN);
    box.innerHTML = `<div class="mo-board${state.client ? ' picking' : ''}">${list.map((r, i) => {
      const total = measureOf(r.t);
      const won = wonOf(r.t);
      const inv = invoiced[r.id];
      return `<button type="button" class="mo-row${state.client === r.id ? ' on' : ''}" data-id="${esc(r.id)}" data-no-icon aria-pressed="${state.client === r.id}"
          title="${state.client === r.id ? 'Show every client again' : 'Show only this client’s quotations'}">
        <span class="mo-rank">${rows.indexOf(r) + 1}</span>
        <span class="mo-name">${esc(r.name)}</span>
        <span class="mo-val">${esc(state.measure === 'value' ? `${cur()} ${short(total)}` : plural(total, 'quotation'))}</span>
        <span class="mo-bar" style="width:${Math.max(4, (total / max) * 100)}%">${won > 0 ? `<i class="won" style="flex:${won};--d:${(i * 0.05).toFixed(2)}s"></i>` : ''}${total - won > 0 ? `<i class="open" style="flex:${total - won};--d:${(i * 0.05).toFixed(2)}s"></i>` : ''}</span>
        <span class="mo-sub-line">${plural(r.t.count, 'quotation')} · ${r.t.wonCount} won${inv ? ` · ${esc(cur())} ${short(inv)} invoiced` : ''}</span>
      </button>`;
    }).join('')}</div>${rows.length > SHOWN && !state.client ? `<button type="button" class="more-btn" id="mo-clients-more" data-no-icon>${state.clientsOpen ? 'Show fewer' : `and ${rows.length - SHOWN} more`}</button>` : ''}`;
    for (const b of box.querySelectorAll('.mo-row')) {
      b.addEventListener('click', () => { state.client = state.client === b.dataset.id ? null : b.dataset.id; state.quotesOpen = false; refresh(true); });
      const r = rows.find((x) => x.id === b.dataset.id);
      b.addEventListener('pointermove', (e) => tip(`<div class="mo-tip-title">${esc(r.name)}</div><div class="mo-tip-value">${esc(amount(measureOf(r.t)))}</div>${tipRows(r.t)}`, e.clientX, e.clientY));
      b.addEventListener('pointerleave', untip);
    }
    const more = $('mo-clients-more');
    if (more) more.addEventListener('click', () => { state.clientsOpen = !state.clientsOpen; renderClients(); });
  }

  // ---- lead sources ----

  function renderSources() {
    const box = $('mo-sources');
    const by = new Map();
    for (const l of leads) {
      const s = by.get(l.source) || { name: l.source, total: 0, won: 0, lost: 0, open: 0, pipeline: 0 };
      s.total += 1;
      if (l.status === 'Won') s.won += 1;
      else if (l.status === 'Lost') s.lost += 1;
      else { s.open += 1; s.pipeline += Number(l.estimatedValue) || 0; }
      by.set(l.source, s);
    }
    const rows = [...by.values()].sort((a, b) => b.total - a.total || b.won - a.won);
    if (!rows.length) {
      box.innerHTML = `<div class="mo-empty">Add the companies you’re winning over, and where they came from, to see which channels bring work.
        <button type="button" class="add-btn" id="mo-add-lead" data-no-icon>+ New Lead</button></div>`;
      $('mo-add-lead').addEventListener('click', () => $('new-lead-btn').click());
      return;
    }
    const max = Math.max(...rows.map((r) => r.total));
    box.innerHTML = `<div class="mo-board">${rows.map((r, i) => `<div class="mo-row" data-i="${i}">
        <span class="mo-rank">${i + 1}</span>
        <span class="mo-name">${esc(r.name)}</span>
        <span class="mo-val">${plural(r.total, 'lead')}</span>
        <span class="mo-bar" style="width:${Math.max(4, (r.total / max) * 100)}%">${r.won ? `<i class="won" style="flex:${r.won};--d:${(i * 0.05).toFixed(2)}s"></i>` : ''}${r.total - r.won ? `<i class="open" style="flex:${r.total - r.won};--d:${(i * 0.05).toFixed(2)}s"></i>` : ''}</span>
        <span class="mo-sub-line">${r.won} won · ${Math.round((r.won / r.total) * 100)}%${r.pipeline ? ` · ${esc(cur())} ${short(r.pipeline)} still open` : r.open ? ` · ${r.open} open` : ''}</span>
      </div>`).join('')}</div>`;
    for (const el of box.querySelectorAll('.mo-row')) {
      const r = rows[Number(el.dataset.i)];
      el.addEventListener('pointermove', (e) => tip(`<div class="mo-tip-title">${esc(r.name)}</div><div class="mo-tip-value">${plural(r.total, 'lead')}</div>
        <div class="mo-tip-row"><span class="k won"></span><span class="n">Won</span><span class="v">${r.won}</span></div>
        <div class="mo-tip-row"><span class="k open"></span><span class="n">Open or lost</span><span class="v">${r.total - r.won}</span></div>
        <div class="mo-tip-foot">${r.open} open · ${r.lost} lost${r.pipeline ? ` · ${esc(cur())} ${money(r.pipeline)} estimated` : ''}</div>`, e.clientX, e.clientY));
      el.addEventListener('pointerleave', untip);
    }
  }

  // ---- the quotations behind it ----

  function renderQuotes() {
    const qs = quotesIn(rangeMonths(), { month: state.month });
    const t = totals(qs);
    $('mo-list-title').textContent = `Quotations — ${state.month ? monthLong(state.month) : `last ${state.range} months`}`;
    $('mo-list-note').textContent = `${plural(t.count, 'quotation')} · ${cur()} ${short(t.value)}${state.client ? ` · ${clientName(state.client)}` : ''}`;
    const box = $('mo-list');
    if (!qs.length) { box.innerHTML = '<div class="mo-empty">Nothing here — try a longer period, or another month or client.</div>'; return; }
    const list = state.quotesOpen ? qs : qs.slice(0, QUOTES_SHOWN);
    box.innerHTML = `<div class="mo-quotes">${list.map((q, i) => `<a class="mo-quote" href="quotation-editor.html?id=${encodeURIComponent(q.id)}" style="--d:${Math.min(i, 12) * 0.025}s">
        <span class="num">${esc(q.number)}<span class="mo-pill ${q.won ? 'won' : 'wait'}">${q.won ? '✓ Won' : 'Waiting'}</span></span>
        <span class="amt">${esc(cur())} ${money(q.value)}</span>
        <span class="who">${esc([q.clientName, q.projectNumber && `${q.projectNumber} ${q.projectName || ''}`.trim(), q.subject].filter(Boolean).join(' · '))}</span>
        <span class="when">${esc(dayLabel(q.date))}</span>
      </a>`).join('')}</div>${qs.length > QUOTES_SHOWN ? `<button type="button" class="more-btn" id="mo-quotes-more" data-no-icon>${state.quotesOpen ? 'Show fewer' : `and ${qs.length - QUOTES_SHOWN} more`}</button>` : ''}`;
    const more = $('mo-quotes-more');
    if (more) more.addEventListener('click', () => { state.quotesOpen = !state.quotesOpen; renderQuotes(); });
  }

  // ---- filters ----

  function renderChips() {
    const chips = [];
    if (state.month) chips.push(['month', monthLong(state.month)]);
    if (state.client) chips.push(['client', clientName(state.client)]);
    $('mo-chips').innerHTML = chips.map(([k, label]) => `<span class="mo-chip">${esc(label)}<button type="button" data-k="${k}" data-no-icon title="Clear" aria-label="Clear ${esc(label)}">
      <svg viewBox="0 0 12 12" width="9" height="9" aria-hidden="true"><path d="M3 3l6 6M9 3l-6 6" stroke="currentColor" stroke-width="1.7" stroke-linecap="round"/></svg></button></span>`).join('');
    for (const b of $('mo-chips').querySelectorAll('button')) {
      b.addEventListener('click', () => { state[b.dataset.k] = null; state.quotesOpen = false; refresh(b.dataset.k === 'client'); });
    }
    for (const b of $('mo-range').children) b.classList.toggle('active', Number(b.dataset.range) === state.range);
    for (const b of $('mo-measure').children) b.classList.toggle('active', b.dataset.measure === state.measure);
    $('mo-hint').textContent = state.month ? 'Click the month again to see them all' : 'Click a month to look at it on its own';
  }

  function pickMonth(m, keepFocus) {
    state.month = state.month === m ? null : m;
    state.quotesOpen = false;
    refresh(false);
    if (keepFocus) { const col = $('mo-chart').querySelector(`.col[data-m="${m}"]`); if (col) col.focus(); }
  }

  function refresh(grow) {
    if (state.month && !rangeMonths().includes(state.month)) state.month = null;
    renderChips();
    renderHero();
    renderChart(grow);
    renderClients();
    renderSources();
    renderQuotes();
  }

  let wired = false;
  function wire() {
    if (wired) return;
    wired = true;
    $('mo-range').addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b || Number(b.dataset.range) === state.range) return;
      state.range = Number(b.dataset.range);
      remember();
      refresh(true);
    });
    $('mo-measure').addEventListener('click', (e) => {
      const b = e.target.closest('button');
      if (!b || b.dataset.measure === state.measure) return;
      state.measure = b.dataset.measure;
      shownBig = 0;
      remember();
      refresh(true);
    });
    $('mo-table-btn').addEventListener('click', () => {
      const open = $('mo-table').classList.toggle('hidden') === false;
      $('mo-table-btn').textContent = open ? 'Hide table' : 'Show as table';
      $('mo-table-btn').setAttribute('aria-expanded', String(open));
    });
    // Redrawn to the new width (the text stays its size).
    let last = 0;
    new ResizeObserver(() => {
      const w = $('mo-chart').clientWidth;
      if (summary && w && Math.abs(w - last) > 1) { last = w; renderChart(false); }
    }).observe($('mo-chart'));
    document.addEventListener('scroll', untip, true);
  }

  window.marketingOverview = {
    render(s, l) {
      summary = Object.assign({ quotes: [] }, s);
      leads = l || [];
      wire();
      refresh(true);
    },
  };
})();

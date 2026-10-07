'use strict';

// Costs › Manpower Rates: each kind of worker, what we charge for them
// (the rate filled into quotations by "Standard Manpower Rates"), and what
// each rate provider charges us — with the margin left on each. Providers
// can be added, renamed or removed; everything saves as it's typed.

(function () {
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const box = document.getElementById('costs-manpower');
  if (!box) return;
  let data = null;
  let saveTimer = null;
  const money = (v) => (Number(v) || 0).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 });

  function margin(rate, cost) {
    if (cost === undefined || cost === null || cost === '' || !Number(rate)) return '';
    const m = Number(rate) - Number(cost);
    const pct = Math.round((m / Number(rate)) * 100);
    return `<span class="mp-margin ${m < 0 ? 'neg' : m === 0 ? 'zero' : ''}" title="What's left after paying this provider">${m < 0 ? '−' : '+'}${money(Math.abs(m))} · ${pct}%</span>`;
  }

  function cheapest(r) {
    let best = null;
    for (const p of data.providers) {
      const c = r.costs && r.costs[p];
      if (c !== undefined && c !== null && (best === null || c < r.costs[best])) best = p;
    }
    return best;
  }

  function render() {
    const providers = data.providers;
    box.innerHTML = `
      <div class="mp-card">
        <div class="mp-head">
          <div><h2>Manpower Rates</h2><p class="small-note">Our rate is what a quotation charges (“Standard Manpower Rates” fills it in). Each provider’s column is what they charge us; the cheapest is marked, with what’s left on each.</p></div>
          <button type="button" id="mp-add-provider" data-no-icon>+ Add Provider</button>
        </div>
        <div class="mp-scroll"><table class="mp-table">
          <thead><tr>
            <th>Worker</th><th>Per</th><th class="num mp-ours">Our Rate (HK$)</th>
            ${providers.map((p, i) => `<th class="num mp-prov"><div class="mp-prov-head"><span class="mp-prov-name" data-i="${i}">${esc(p)}</span>
              <span class="mp-prov-tools"><button type="button" class="mp-prov-rename" data-i="${i}" data-no-icon title="Rename ${esc(p)}" aria-label="Rename">✎</button><button type="button" class="mp-prov-remove" data-i="${i}" data-no-icon title="Remove ${esc(p)}" aria-label="Remove ${esc(p)}">×</button></span></div></th>`).join('')}
            <th></th>
          </tr></thead>
          <tbody>${data.rates.map((r, ri) => {
            const best = cheapest(r);
            return `<tr data-ri="${ri}">
              <td><input type="text" class="mp-name" value="${esc(r.name)}" placeholder="Worker" /></td>
              <td><input type="text" class="mp-unit" value="${esc(r.unit || 'md')}" /></td>
              <td class="num mp-ours"><input type="number" class="mp-rate" min="0" step="0.01" value="${esc(r.rate)}" /></td>
              ${providers.map((p) => {
                const c = r.costs && r.costs[p];
                return `<td class="num mp-prov${best === p && providers.length > 1 ? ' best' : ''}"><input type="number" class="mp-cost" data-p="${esc(p)}" min="0" step="0.01" value="${c ?? ''}" placeholder="—" />${margin(r.rate, c)}</td>`;
              }).join('')}
              <td><button type="button" class="icon-btn mp-remove" data-no-icon title="Remove this worker" aria-label="Remove">×</button></td>
            </tr>`;
          }).join('')}</tbody>
        </table></div>
        <button type="button" class="link-btn" id="mp-add-row" data-no-icon>+ Add Worker</button>
        <span class="mp-saved" id="mp-saved" aria-live="polite"></span>
      </div>`;
    wire();
  }

  function readBack() {
    const providers = data.providers.slice();
    const old = data.providers;
    data.rates = [...box.querySelectorAll('tbody tr')].map((tr) => {
      const costs = {};
      tr.querySelectorAll('.mp-cost').forEach((inp, j) => {
        if (inp.value !== '') costs[providers[j] || old[j]] = Number(inp.value);
      });
      return { name: tr.querySelector('.mp-name').value.trim(), unit: tr.querySelector('.mp-unit').value.trim() || 'md',
        rate: Number(tr.querySelector('.mp-rate').value) || 0, costs };
    });
    data.providers = providers.map((p, i) => p || old[i]);
  }

  function save(redraw) {
    readBack();
    clearTimeout(saveTimer);
    saveTimer = setTimeout(async () => {
      const r = await window.api.costs.saveManpower({ rates: data.rates.filter((x) => x.name), providers: data.providers.filter(Boolean) });
      const note = document.getElementById('mp-saved');
      if (r && r.ok === false) { await window.appAlert(r.error); return; }
      if (note) { note.textContent = 'Saved'; note.classList.add('on'); setTimeout(() => note.classList.remove('on'), 1400); }
    }, 450);
    if (redraw) render();
  }

  function wire() {
    box.querySelectorAll('.mp-name, .mp-unit').forEach((i) => i.addEventListener('input', () => save(false)));
    box.querySelectorAll('.mp-rate, .mp-cost').forEach((i) => {
      i.addEventListener('input', () => save(false));
      i.addEventListener('change', () => save(true));
    });
    box.querySelectorAll('.mp-prov-rename').forEach((b) => b.addEventListener('click', async () => {
      readBack();
      const i = Number(b.dataset.i);
      const old = data.providers[i];
      const name = await window.appPrompt('Rename the provider', old, { ok: 'Rename' });
      if (!name || !name.trim() || name.trim() === old) return;
      data.providers[i] = name.trim();
      for (const r of data.rates) if (r.costs && old in r.costs) { r.costs[name.trim()] = r.costs[old]; delete r.costs[old]; }
      render(); save(false);
    }));
    box.querySelectorAll('.mp-remove').forEach((b) => b.addEventListener('click', () => {
      readBack();
      data.rates.splice(Number(b.closest('tr').dataset.ri), 1);
      render(); save(false);
    }));
    box.querySelectorAll('.mp-prov-remove').forEach((b) => b.addEventListener('click', async () => {
      readBack();
      const name = data.providers[Number(b.dataset.i)];
      if (!await window.appConfirm(`Remove ${name}?\n\nTheir rates go from this table.`, { ok: 'Remove', danger: true })) return;
      data.providers.splice(Number(b.dataset.i), 1);
      for (const r of data.rates) if (r.costs) delete r.costs[name];
      render(); save(false);
    }));
    document.getElementById('mp-add-row').addEventListener('click', () => {
      readBack();
      data.rates.push({ name: '', unit: 'md', rate: 0, costs: {} });
      render();
      const names = box.querySelectorAll('.mp-name');
      names[names.length - 1].focus();
    });
    document.getElementById('mp-add-provider').addEventListener('click', async () => {
      const name = await window.appPrompt('The provider’s name', '', { ok: 'Add Provider', placeholder: 'e.g. ABC Engineering Ltd.' });
      if (!name || !name.trim()) return;
      readBack();
      if (!data.providers.some((p) => p.toLowerCase() === name.trim().toLowerCase())) data.providers.push(name.trim());
      render(); save(false);
    });
  }

  async function show(tab) {
    for (const b of document.querySelectorAll('#costs-tabs button')) b.classList.toggle('active', b.dataset.tab === tab);
    document.getElementById('costs-materials').classList.toggle('hidden', tab !== 'materials');
    box.classList.toggle('hidden', tab !== 'manpower');
    try { sessionStorage.setItem('costs.tab', tab); } catch (e) { /* ignore */ }
    if (tab === 'manpower' && !data) {
      data = await window.api.costs.manpower();
      data.rates = (data.rates || []).map((r) => Object.assign({ costs: {} }, r, { costs: r.costs || {} }));
      render();
    }
  }
  for (const b of document.querySelectorAll('#costs-tabs button')) b.addEventListener('click', () => show(b.dataset.tab));
  let start = new URLSearchParams(location.search).get('tab');
  if (!start) { try { start = sessionStorage.getItem('costs.tab'); } catch (e) { /* ignore */ } }
  if (start === 'manpower') show('manpower');
})();

'use strict';

// Delivery charges by weight (per truck per trip): the bands from
// Settings › Quotations, lightest first, e.g.
//   Under 500 kg $1,200 · 500 kg – 1 ton $1,800 · 1 – 2 tons $2,200 ·
//   2 – 6 tons $3,300 · 6 – 8 tons $3,800.
// A load heavier than the top band goes on more than one truck: full
// trucks at the top band, the rest at its own band.
//
//   window.deliveryRates.DEFAULT                → the standard bands
//   window.deliveryRates.label(rates, i)        → "2 – 6 tons"
//   window.deliveryRates.plan(kg, rates)        → [{ band, trucks }]
//   window.deliveryRates.open({ rates, kg, missing, currency }) → Promise<[{ band, trucks, trips }] | null>
//     The "+ Delivery Charge" sheet: the materials' weight, the band it
//     suggests (or any other), trucks and trips; resolves with the lines
//     to add, or null when cancelled.

(function () {
  const DEFAULT = [
    { upToKg: 500, price: 1200 },
    { upToKg: 1000, price: 1800 },
    { upToKg: 2000, price: 2200 },
    { upToKg: 6000, price: 3300 },
    { upToKg: 8000, price: 3800 },
  ];
  const esc = (v) => String(v ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
  const money = (v) => Number(v || 0).toLocaleString('en-US', { minimumFractionDigits: 0, maximumFractionDigits: 2 });
  const kgText = (kg) => `${Math.round(kg).toLocaleString('en-US')} kg`;

  // 500 → "500 kg", 1000 → "1 ton", 2000 → "2 tons", 1500 → "1.5 tons".
  function weight(kg, unit = true) {
    if (kg < 1000) return `${money(kg)}${unit ? ' kg' : ''}`;
    const t = Math.round((kg / 1000) * 100) / 100;
    return `${t.toLocaleString('en-US')}${unit ? (t === 1 ? ' ton' : ' tons') : ''}`;
  }
  function label(rates, i) {
    const up = rates[i].upToKg;
    if (i === 0) return `Under ${weight(up)}`;
    const from = rates[i - 1].upToKg;
    return from >= 1000 ? `${weight(from, false)} – ${weight(up)}` : `${weight(from)} – ${weight(up)}`;
  }
  const bandFor = (kg, rates) => {
    const i = rates.findIndex((r) => kg <= r.upToKg);
    return i < 0 ? rates.length - 1 : i;
  };
  function plan(kg, rates) {
    if (!rates.length) return [];
    if (!(kg > 0)) return [];
    const top = rates[rates.length - 1].upToKg;
    if (kg <= top) return [{ band: bandFor(kg, rates), trucks: 1 }];
    const full = Math.floor(kg / top);
    const rest = kg - full * top;
    const out = [{ band: rates.length - 1, trucks: full }];
    if (rest > 0.0001) {
      const b = bandFor(rest, rates);
      if (b === rates.length - 1) out[0].trucks += 1;
      else out.push({ band: b, trucks: 1 });
    }
    return out;
  }

  let sheet = null;
  function build() {
    sheet = document.createElement('div');
    sheet.className = 'modal-backdrop hidden';
    sheet.innerHTML = `
      <div class="modal wide dr-sheet" role="dialog" aria-labelledby="dr-title">
        <h2 id="dr-title">Delivery Charge</h2>
        <div class="dr-weight" id="dr-weight"></div>
        <div class="field"><label>Charge per truck per trip, by the weight on the truck</label>
          <div class="dr-bands" id="dr-bands" role="radiogroup"></div></div>
        <div class="dr-counts" id="dr-counts">
          <div class="field"><label for="dr-trucks">Trucks</label><input type="number" id="dr-trucks" min="1" step="1" value="1" /></div>
          <div class="field"><label for="dr-trips">Trips per truck</label><input type="number" id="dr-trips" min="1" step="1" value="2" /><span class="small-note">2 = delivery and collection</span></div>
        </div>
        <div class="dr-preview" id="dr-preview"></div>
        <div class="actions">
          <button id="dr-cancel">Cancel</button>
          <button class="primary" id="dr-add">Add Delivery Charge</button>
        </div>
      </div>`;
    document.body.appendChild(sheet);
  }

  function open({ rates, kg, missing, currency }) {
    rates = (rates && rates.length ? rates : DEFAULT).slice().sort((a, b) => a.upToKg - b.upToKg);
    const cur = currency || 'HK$';
    if (!sheet) build();
    const $ = (id) => sheet.querySelector(`#${id}`);
    const suggested = plan(kg, rates);
    const split = suggested.length > 1 || (suggested[0] && suggested[0].trucks > 1);
    // Options: the suggested split (when it takes several trucks), then every band.
    let choice = split ? 'split' : String(suggested.length ? suggested[0].band : rates.length - 1);
    const weightNote = kg > 0
      ? `<b>${kgText(kg)}</b> of materials${split ? ` — more than one truck (${weight(rates[rates.length - 1].upToKg)} a truck)` : ` — <b>${esc(label(rates, suggested[0].band))}</b>`}`
      : 'The materials’ weight isn’t known — pick the band for the load.';
    $('dr-weight').innerHTML = `<span class="dr-scale" aria-hidden="true">⚖︎</span><span>${weightNote}${missing ? `<span class="small-note"> · ${missing} item${missing === 1 ? ' has' : 's have'} no weight on the material list</span>` : ''}</span>`;
    const splitText = () => suggested.map((p) => `${p.trucks} × ${label(rates, p.band)}`).join(' + ');
    $('dr-bands').innerHTML = (split ? `<label class="dr-band" data-v="split"><input type="radio" name="dr-band" value="split" />
        <span class="dr-band-name">Suggested split<small>${esc(splitText())}</small></span><span class="dr-pill">Suggested</span></label>` : '') +
      rates.map((r, i) => `<label class="dr-band" data-v="${i}"><input type="radio" name="dr-band" value="${i}" />
        <span class="dr-band-name">${esc(label(rates, i))}</span>
        ${!split && suggested[0] && suggested[0].band === i ? '<span class="dr-pill">Suggested</span>' : ''}
        <span class="dr-band-price">${esc(cur)} ${money(r.price)}</span></label>`).join('');
    const lines = () => {
      const trips = Math.max(1, Math.round(Number($('dr-trips').value) || 1));
      if (choice === 'split') return suggested.map((p) => ({ band: p.band, trucks: p.trucks, trips }));
      return [{ band: Number(choice), trucks: Math.max(1, Math.round(Number($('dr-trucks').value) || 1)), trips }];
    };
    const draw = () => {
      for (const el of sheet.querySelectorAll('.dr-band')) {
        el.classList.toggle('on', el.dataset.v === choice);
        el.querySelector('input').checked = el.dataset.v === choice;
      }
      $('dr-trucks').closest('.field').classList.toggle('hidden', choice === 'split');
      const ls = lines();
      let total = 0;
      $('dr-preview').innerHTML = ls.map((l, n) => {
        const r = rates[l.band];
        const qty = l.trucks * l.trips;
        total += qty * r.price;
        return `<div class="dr-line"><span class="dr-no">D${n + 1}</span><span>Delivery of materials (${esc(label(rates, l.band))})<small>${l.trucks} truck${l.trucks === 1 ? '' : 's'} × ${l.trips} trip${l.trips === 1 ? '' : 's'} = ${qty} truck/trip × ${esc(cur)} ${money(r.price)}</small></span><b>${esc(cur)} ${money(qty * r.price)}</b></div>`;
      }).join('') + (ls.length > 1 ? `<div class="dr-line total"><span></span><span>Delivery total</span><b>${esc(cur)} ${money(total)}</b></div>` : '');
    };
    $('dr-trucks').value = choice !== 'split' && kg > 0 ? String(Math.max(1, Math.ceil(kg / rates[Number(choice)].upToKg))) : '1';
    $('dr-trips').value = '2';
    draw();
    sheet.classList.remove('hidden');
    return new Promise((resolve) => {
      const done = (value) => {
        sheet.classList.add('hidden');
        sheet.querySelector('#dr-bands').onclick = null;
        sheet.onkeydown = null;
        $('dr-trucks').oninput = $('dr-trips').oninput = null;
        $('dr-cancel').onclick = $('dr-add').onclick = null;
        resolve(value);
      };
      $('dr-bands').onclick = (e) => {
        const b = e.target.closest('.dr-band');
        if (!b) return;
        choice = b.dataset.v;
        if (choice !== 'split' && kg > 0) $('dr-trucks').value = String(Math.max(1, Math.ceil(kg / rates[Number(choice)].upToKg)));
        draw();
      };
      $('dr-trucks').oninput = draw;
      $('dr-trips').oninput = draw;
      $('dr-cancel').onclick = () => done(null);
      $('dr-add').onclick = () => done(lines().map((l) => Object.assign({}, l, { label: label(rates, l.band), price: rates[l.band].price })));
      sheet.onkeydown = (e) => {
        if (e.key === 'Escape') done(null);
        if (e.key === 'Enter' && e.target.tagName === 'INPUT') done(lines().map((l) => Object.assign({}, l, { label: label(rates, l.band), price: rates[l.band].price })));
      };
      const first = sheet.querySelector('.dr-band.on input');
      if (first) first.focus();
    });
  }

  window.deliveryRates = { DEFAULT, label, plan, open, weight };
})();

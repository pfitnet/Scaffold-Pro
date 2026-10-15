'use strict';
// Realistic sample data for the screenshot harness: Proficiency (HK) Limited,
// scaffolding and crane / boom-lift hire, in the week of Wed 14 Oct 2026.
// Shapes follow the Swift Codable structs in ScaffoldPro-native/Sources
// (Models.swift, StockAndAccounts.swift, TeamSharing.swift …). Routes may be
// functions of the payload. Editors open with ?id=doc1, project-detail with
// ?number=26219, so those resolve to project 26219's main documents.
const SP = require('../../ScaffoldPro-native/resources/sp_pricelist.json');
const SCAFOM = require('../../ScaffoldPro-native/resources/scafom_pricelist.json');

// ---------------------------------------------------------------- basics
const TODAY = '2026-10-14';
const ME = 'William';
const at = (day, time = '10:00') => `${day}T${time}:00Z`;
const addDays = (day, n) => { const d = new Date(day + 'T00:00:00Z'); d.setUTCDate(d.getUTCDate() + n); return d.toISOString().slice(0, 10); };
const r2 = (n) => Math.round(n * 100) / 100;
const r1 = (n) => Math.round(n * 10) / 10;
const byId = (list) => Object.fromEntries(list.map((x) => [x.id, x]));

const PEOPLE = ['William', 'Jeremie', 'Irene', 'Harry', 'Tom'];
const TEAMS = ['Office', 'Site'];
const PERSON = {
  William: { team: 'Office', title: 'Director', fullName: 'William Chan Wai-man', canSign: true, canSignAgreements: true, idNumber: 'A123456(7)', color: '#2f6f9f', phone: '9123 4567', position: 'Managing Director' },
  Jeremie: { team: 'Office', title: 'Director', fullName: 'Jeremie Laurent', canSign: true, canSignAgreements: false, idNumber: 'R765432(1)', color: '#8a5a9e', phone: '9234 5678', position: 'Commercial Director' },
  Irene: { team: 'Office', title: 'Office Manager', fullName: 'Irene Wong Mei-ling', canSign: false, canSignAgreements: true, idNumber: 'K234567(8)', color: '#c0713a', phone: '9345 6789', position: 'Office Manager' },
  Harry: { team: 'Site', title: 'Site Supervisor', fullName: 'Harry Lam Ka-ho', canSign: false, canSignAgreements: false, idNumber: null, color: '#3f8a5c', phone: '9456 7890', position: 'Site Supervisor' },
  Tom: { team: 'Site', title: 'Crane Coordinator', fullName: 'Tom Cheung Tak-wing', canSign: false, canSignAgreements: false, idNumber: null, color: '#b0455a', phone: '9567 8901', position: 'Crane & Boom-lift Coordinator' },
};
const MACS = {
  William: { computer: "William's MacBook Pro", device: 'mac-william' },
  Jeremie: { computer: "Jeremie's iMac", device: 'mac-jeremie' },
  Irene: { computer: 'Office iMac', device: 'mac-irene' },
  Harry: { computer: "Harry's MacBook Air", device: 'mac-harry' },
  Tom: { computer: "Tom's MacBook Air", device: 'mac-tom' },
};
const teamMember = (name, i) => ({
  id: MACS[name].device, name, computer: MACS[name].computer, lastSeen: at(TODAY, ['09:58', '09:41', '09:55', '08:12', '07:46'][i]),
  isThisMac: name === ME, version: '2026-10-09', outdated: name === 'Tom', linkPort: 47820, linkAddresses: [`192.168.1.${20 + i}`],
});
const MEMBERS = PEOPLE.map(teamMember);

// ---------------------------------------------------------------- clients & sites
const CLIENTS = [
  { id: 'c1', companyName: 'Gammon Construction Limited', contactPerson: 'Mr. Kelvin Ho', address: '28/F, Devon House, Taikoo Place', addressLine2: '979 King’s Road, Quarry Bay', phone: '2516 8823', email: 'kelvin.ho@gammonconstruction.com', clientReference: 'GAM', city: 'Hong Kong', country: 'Hong Kong', defaultMarkupPercent: 10 },
  { id: 'c2', companyName: 'Hip Hing Engineering Company Limited', contactPerson: 'Ms. Cindy Leung', address: '9/F, Hip Hing Building', addressLine2: '2 Kai Hing Road, Kowloon Bay', phone: '2827 3888', email: 'cindy.leung@hiphing.com.hk', clientReference: 'HH', city: 'Kowloon', country: 'Hong Kong' },
  { id: 'c3', companyName: 'Chun Wo Construction & Engineering Co. Ltd.', contactPerson: 'Mr. Alan Tse', address: '5/F, Chun Wo Commercial Centre', addressLine2: '23-29 Wing Wo Street, Central', phone: '2745 2828', email: 'alan.tse@chunwo.com', clientReference: 'CW', city: 'Hong Kong', country: 'Hong Kong' },
  { id: 'c4', companyName: 'Leighton Contractors (Asia) Limited', contactPerson: 'Mr. Daniel Price', address: '39/F, Sun Hung Kai Centre', addressLine2: '30 Harbour Road, Wan Chai', phone: '2823 1111', email: 'daniel.price@leightonasia.com', clientReference: 'LCA', city: 'Hong Kong', country: 'Hong Kong', defaultMarkupPercent: 5 },
  { id: 'c5', companyName: 'Paul Y. Construction Company Limited', contactPerson: 'Mr. Raymond Chau', address: '11/F, Paul Y. Centre', addressLine2: '51 Hung To Road, Kwun Tong', phone: '2831 8338', email: 'raymond.chau@paul-y.com', clientReference: 'PY', city: 'Kowloon', country: 'Hong Kong' },
  { id: 'c6', companyName: 'Shui On Building Contractors Limited', contactPerson: 'Ms. Vivian Ng', address: '18/F, Shui On Centre', addressLine2: '6-8 Harbour Road, Wan Chai', phone: '2879 1888', email: 'vivian.ng@shuion.com.hk', clientReference: 'SO', city: 'Hong Kong', country: 'Hong Kong' },
  { id: 'c7', companyName: 'China State Construction Engineering (HK) Ltd.', contactPerson: 'Mr. Liu Jianguo', address: '28/F, China Overseas Building', addressLine2: '139 Hennessy Road, Wan Chai', phone: '2823 7888', email: 'liu.jg@cscechk.com', clientReference: 'CSCE', city: 'Hong Kong', country: 'Hong Kong' },
  { id: 'c8', companyName: 'Yau Lee Construction Company Limited', contactPerson: 'Mr. Patrick Yuen', address: '10/F, Tower 1, Enterprise Square', addressLine2: '9 Sheung Yuet Road, Kowloon Bay', phone: '2799 9888', email: 'patrick.yuen@yaulee.com', clientReference: 'YL', city: 'Kowloon', country: 'Hong Kong' },
].map((c, i) => Object.assign({ notes: null, isArchived: false, createdAt: at(addDays('2025-03-02', i * 37), '09:30'), postalCode: null, vatNumber: null, billingInfo: null }, c));

const SITES = [
  { id: 's1', name: 'Kai Tak Sports Park', address: '38 Shing Fung Road, Kai Tak, Kowloon', contactPerson: 'Mr. Sam Wong (Site Agent)', phone: '6123 4501', siteReference: 'KTSP' },
  { id: 's2', name: 'Tseung Kwan O Hospital Extension', address: '2 Po Ning Lane, Hang Hau, Tseung Kwan O', contactPerson: 'Ms. Joyce Lau', phone: '6234 5502', siteReference: 'TKOH' },
  { id: 's3', name: 'Tuen Mun Road Widening – Tsing Tin Interchange', address: 'Tuen Mun Road near Tsing Tin Road, Tuen Mun', contactPerson: 'Mr. Benny Fung', phone: '6345 6603', siteReference: 'TMR' },
  { id: 's4', name: 'Central Kowloon Route – Yau Ma Tei East Vent Building', address: 'Gascoigne Road, Yau Ma Tei, Kowloon', contactPerson: 'Mr. Chris Evans', phone: '6456 7704', siteReference: 'CKR' },
  { id: 's5', name: 'West Kowloon Cultural District – Lyric Theatre Complex', address: '8 Austin Road West, Tsim Sha Tsui', contactPerson: 'Mr. Leo Kwok', phone: '6567 8805', siteReference: 'WKCD' },
  { id: 's6', name: 'Sha Tin Water Treatment Works (South Works)', address: 'Tai Po Road, Sha Tin, New Territories', contactPerson: 'Ms. Grace Ho', phone: '6678 9906', siteReference: 'STWTW' },
  { id: 's7', name: 'Tung Chung New Town Extension – Area 99', address: 'Tung Chung East Reclamation, Lantau', contactPerson: 'Mr. Zhang Wei', phone: '6789 0107', siteReference: 'TCNTE' },
  { id: 's8', name: 'Anderson Road Quarry – Site R2-5', address: 'Anderson Road, Sau Mau Ping, Kowloon', contactPerson: 'Mr. Jason Tam', phone: '6890 1208', siteReference: 'ARQ' },
  { id: 's9', name: 'Kai Tak Cruise Terminal', address: '33 Shing Fung Road, Kai Tak, Kowloon', contactPerson: 'Mr. Sam Wong', phone: '6123 4501', siteReference: 'KTCT' },
  { id: 's10', name: 'Wong Chuk Hang Station Development', address: '4 Heung Yip Road, Wong Chuk Hang', contactPerson: 'Ms. Karen Siu', phone: '6901 2310', siteReference: 'WCH' },
].map((s, i) => Object.assign({ notes: null, isArchived: false, createdAt: at(addDays('2025-04-10', i * 29), '11:00'), city: 'Hong Kong', postalCode: null, country: 'Hong Kong', email: null }, s));

const CLIENT = byId(CLIENTS);
const SITE = byId(SITES);

// ---------------------------------------------------------------- projects
const PROJECTS = [
  { id: 'p26219', projectNumber: '26219', name: 'Kai Tak Sports Park – Main Stadium Roof Access', clientId: 'c1', siteId: 's1', status: 'Active', jobType: 'Scaffolding', startDate: '2026-09-07', expectedCompletionDate: '2027-02-26', projectManager: 'Harry', createdBy: 'William', lastEditedBy: 'Irene', projectDescription: 'System scaffold access towers and working platforms to the stadium roof perimeter, Zones A–C.', internalNotes: 'Night deliveries only via Gate 3. Site induction booked for all crew.' },
  { id: 'p26220', projectNumber: '26220', name: 'TKO Hospital Extension – Block B Façade', clientId: 'c2', siteId: 's2', status: 'Active', jobType: 'Scaffolding', startDate: '2026-08-17', expectedCompletionDate: '2027-01-15', projectManager: 'Harry', createdBy: 'Jeremie', lastEditedBy: 'Jeremie' },
  { id: 'p26221', projectNumber: '26221', name: 'Tuen Mun Road Widening – Bridge Pier Falsework', clientId: 'c3', siteId: 's3', status: 'Quotation', jobType: 'Scaffolding', startDate: '2026-11-09', projectManager: 'William', createdBy: 'William', lastEditedBy: 'William' },
  { id: 'p26222', projectNumber: '26222', name: 'CKR Vent Building – Boom-lift Hire', clientId: 'c4', siteId: 's4', status: 'Active', jobType: 'Crane', startDate: '2026-09-21', expectedCompletionDate: '2026-12-18', projectManager: 'Tom', createdBy: 'Tom', lastEditedBy: 'Tom' },
  { id: 'p26223', projectNumber: '26223', name: 'Lyric Theatre – Stage Tower Scaffold', clientId: 'c5', siteId: 's5', status: 'On Hold', jobType: 'Scaffolding', startDate: '2026-07-06', projectManager: 'Harry', createdBy: 'Jeremie', lastEditedBy: 'William', internalNotes: 'Client waiting on revised architectural drawings.' },
  { id: 'p26224', projectNumber: '26224', name: 'Sha Tin Water Treatment – Filter House Access', clientId: 'c6', siteId: 's6', status: 'Planning', jobType: 'Scaffolding', projectManager: 'Irene', createdBy: 'Irene', lastEditedBy: 'Irene' },
  { id: 'p26225', projectNumber: '26225', name: 'Tung Chung Area 99 – Crawler Crane Hire', clientId: 'c7', siteId: 's7', status: 'Quotation', jobType: 'Crane', startDate: '2026-11-02', projectManager: 'Tom', createdBy: 'Tom', lastEditedBy: 'Jeremie' },
  { id: 'p26226', projectNumber: '26226', name: 'Anderson Road R2-5 – Podium Scaffold', clientId: 'c8', siteId: 's8', status: 'Completed', jobType: 'Scaffolding', startDate: '2026-03-02', expectedCompletionDate: '2026-08-28', projectManager: 'Harry', createdBy: 'William', lastEditedBy: 'Irene' },
  { id: 'p26218', projectNumber: '26218', name: 'Kai Tak Cruise Terminal – Canopy Maintenance', clientId: 'c1', siteId: 's9', status: 'Completed', jobType: 'Scaffolding', startDate: '2026-02-09', expectedCompletionDate: '2026-06-30', projectManager: 'Harry', createdBy: 'William', lastEditedBy: 'William' },
  { id: 'p26227', projectNumber: '26227', name: 'Wong Chuk Hang Station – Spider Crane Lift', clientId: 'c2', siteId: 's10', status: 'Planning', jobType: 'Crane', projectManager: 'Tom', createdBy: 'Tom', lastEditedBy: 'Tom' },
  { id: 'p26205', projectNumber: '26205', name: 'Lam Tin Estate – Lift Shaft Scaffold', clientId: 'c3', siteId: 's8', status: 'Archived', jobType: 'Scaffolding', startDate: '2025-11-03', expectedCompletionDate: '2026-02-27', projectManager: 'Harry', createdBy: 'William', lastEditedBy: 'William' },
].map((p, i) => Object.assign({ projectDescription: null, startDate: null, expectedCompletionDate: null, internalNotes: null, createdAt: at(addDays(p.startDate && p.startDate < TODAY ? p.startDate : '2026-10-06', -24 + i), '09:15') }, p));
const PROJECT = byId(PROJECTS);
const PROJECT_BY_NUMBER = Object.fromEntries(PROJECTS.map((p) => [p.projectNumber, p]));
const projectRef = (p) => ({ id: p.id, projectNumber: p.projectNumber, name: p.name, siteId: p.siteId, siteName: SITE[p.siteId].name, siteAddress: SITE[p.siteId].address, clientName: CLIENT[p.clientId].companyName });
const LAST_ACTIVITY = { p26219: '2026-10-14T09:42:00Z', p26220: '2026-10-13T16:05:00Z', p26221: '2026-10-13T11:20:00Z', p26222: '2026-10-12T15:30:00Z', p26225: '2026-10-09T10:10:00Z' };

// ---------------------------------------------------------------- material list
const priceItem = (x, i, sourceKey) => ({
  id: `${sourceKey.toLowerCase()}_${i}`, sourceKey, itemCode: String(x.itemCode), category: x.category || null, itemName: x.name, unit: 'pc',
  weightKg: x.weightKg == null ? null : x.weightKg, unitSalePrice: x.unitSalePriceHKD == null ? null : x.unitSalePriceHKD,
  unitRentalPrice: x.unitRentalPriceHKD == null ? null : x.unitRentalPriceHKD, applicableTypes: x.applicableTypes || [], notes: null, isArchived: false,
  sortOrder: i, isPinned: ['600mm Base Jack', '2.07m Ledger', '2.07m x 0.32m Steel Deck', '2.0m standard with spigot'].includes(x.name) && sourceKey === 'SP', chineseName: x.chineseName || null,
});
const SP_ITEMS = SP.map((x, i) => priceItem(x, i, 'SP'));
const SCAFOM_ITEMS = SCAFOM.map((x, i) => priceItem(x, i, 'SCAFOM'));
const ALL_ITEMS = SP_ITEMS.concat(SCAFOM_ITEMS);
const item = (name) => { const it = SP_ITEMS.find((x) => x.itemName === name); if (!it) throw new Error('No SP item ' + name); return it; };
const PRICE_LISTS = [
  { id: 'pl_sp', sourceKey: 'SP', displayName: 'SP Material List', currency: 'HKD', createdAt: '2025-01-06T09:00:00Z' },
  { id: 'pl_scafom', sourceKey: 'SCAFOM', displayName: 'SCAFOM-RUX Price List', currency: 'HKD', createdAt: '2025-02-17T09:00:00Z' },
];

// ---------------------------------------------------------------- settings
const MANPOWER_RATES = [
  { name: 'Scaffolder CP', rate: 2300, unit: 'md', costs: { 'Summit Engineering & Resources Limited': 1850, 'Lingma Const. & Eng. Co. Ltd.': 1900 } },
  { name: 'Scaffolder', rate: 1950, unit: 'md', costs: { 'Summit Engineering & Resources Limited': 1550, 'Lingma Const. & Eng. Co. Ltd.': 1600 } },
  { name: 'General Worker', rate: 1300, unit: 'md', costs: { 'Summit Engineering & Resources Limited': 1000, 'Lingma Const. & Eng. Co. Ltd.': 1050 } },
  { name: 'Safety Supervisor', rate: 2600, unit: 'md', costs: { 'Summit Engineering & Resources Limited': 2100, 'Lingma Const. & Eng. Co. Ltd.': 2150 } },
];
const DELIVERY_RATES = [{ upToKg: 3000, price: 1800 }, { upToKg: 5500, price: 2400 }, { upToKg: 9000, price: 3200 }, { upToKg: 16000, price: 4500 }];
const KEY_TERMS = '1. Payment: 30 days from the date of invoice.\n2. Delivery: Materials delivered to site by 5.5-tonne or 9-tonne lorry; unloading by the client.\n3. Rental is charged monthly from the date of delivery until the materials are returned to our yard.\n4. Any loss or damage to the materials will be charged at the unit sale price.\n5. Modification of the scaffold after erection will be charged separately.';
const SETTINGS = {
  id: 'company', companyName: 'Proficiency (HK) Limited', addressLine1: 'Unit 1203, 12/F, Kwun Tong Industrial Centre Phase 2', addressLine2: '448-458 Kwun Tong Road, Kwun Tong, Kowloon',
  phone: '+852 2345 6789', email: 'info@pfitnet.com', website: 'www.pfitnet.com', registrationNumber: 'BR 61234567-000-03-26-8', vatNumber: null,
  bankDetails: 'HSBC Hong Kong\nAccount name: Proficiency (HK) Limited\nAccount no.: 004-123-456789-001\nFPS ID: 1234567',
  defaultPaymentTerms: '30 days from invoice date', defaultNotes: 'Thank you for your business.', currency: 'HKD', defaultTaxRatePercent: 0, pricesIncludeTax: false,
  paperSize: 'A4', appearance: 'System', logoPath: null,
  numberFormatBOQ: 'BOQ{PROJECT}-{SEQ}', numberFormatQuotation: 'Qt{PROJECT}-{SEQ}', numberFormatInvoice: 'Inv{PROJECT}-{SEQ}', numberFormatDeliveryNote: 'DN{PROJECT}-{SEQ}', numberFormatLetter: 'L{PROJECT}-{SEQ}',
  defaultInvoiceDueDays: 30, signatoryName: 'William Chan', signatoryTitle: 'Director', termsURL: 'www.pfitnet.com/TC',
  quotationTerms: KEY_TERMS, quotationTermsSale: '1. Payment: 50% deposit on order, balance before delivery.\n2. Delivery: Within 7 working days from receipt of deposit.\n3. Goods sold are not returnable.',
  quotationAcceptance: 'Order shall be confirmed by signing and returning this quotation. This quotation is valid for 7 business days from the date above.',
  standardDeliveryCharge: 1800, defaultMinimumHireMonths: 3, buyBackPercent: 60, buyBackAfterMonths: 6, buyBackReductionPercent: 5, buyBackEndMonths: 12,
  buyBackWording: 'We offer to buy back the equipment at {PERCENT} of its price (i.e. {UNIT_PRICE} per unit) after {MONTHS} months.\nFor each month beyond {MONTHS} months, the buy-back price is reduced by {LESS} of the price (i.e. {NEXT_UNIT_PRICE} at {NEXT_MONTHS} months and so on).\nNo buy-back is offered after {END_MONTHS} months.',
  aiProvider: 'gemini', aiModel: null, exchangeRates: { EUR: 8.93, USD: 7.8, CNY: 1.08 }, numberStarts: { QT: 1 }, termsNewPage: 'WhenLong',
  manpowerRates: MANPOWER_RATES, manpowerProviders: ['Summit Engineering & Resources Limited', 'Lingma Const. & Eng. Co. Ltd.'], markupRoundUp: false,
  defaultBOQItems: [{ priceListItemId: item('600mm Base Jack').id, quantity: 20 }, { priceListItemId: item('Timber Sole Board').id, quantity: 20 }],
  minimumMonthlyRental: 1000, documentLanguage: 'English', boqTerms: 'Quantities are estimated from the drawings provided and are subject to site measurement.', linkedNumbers: true, giphyKey: null, deliveryRates: DELIVERY_RATES,
};

// ---------------------------------------------------------------- document builders
const authors = (createdBy, lastEditedBy, lastEditedAt) => ({ createdBy, lastEditedBy, lastEditedAt, mine: lastEditedBy === ME });
const DOC_AUTHORS = {};

// A quotation line from the material list: [name, qty] (optional price override).
function matLine(qid, n, name, qty, opts = {}) {
  const it = item(name);
  const rental = opts.sale ? it.unitSalePrice : it.unitRentalPrice;
  return Object.assign({ id: `${qid}_l${n}`, quotationId: qid, sourceKey: 'SP', priceListItemId: it.id, itemCode: it.itemCode, itemDescription: it.itemName, unit: it.unit, quantity: qty,
    appliedUnitPrice: opts.price != null ? opts.price : rental, section: it.category, sortOrder: n, priceListUnitPrice: rental, _weight: it.weightKg, _zh: it.chineseName }, opts.extra || {});
}
function customLine(qid, n, description, unit, qty, price, extra) {
  return Object.assign({ id: `${qid}_l${n}`, quotationId: qid, sourceKey: null, priceListItemId: null, itemCode: '', itemDescription: description, unit, quantity: qty, appliedUnitPrice: price, section: 'Other', sortOrder: n }, extra || {});
}
function markedUp(price, markup) { return markup ? r1(price * (1 + markup / 100)) : price; }

function buildQuotation(q) {
  const p = PROJECT[q.projectId];
  const isRental = q.pricingMode === 'Rental';
  const months = isRental ? (q.hirePeriodEnabled ? q.hirePeriodMonths : q.minimumHireMonths || 1) : 1;
  const lines = q.lines.map((l) => { const c = Object.assign({}, l); delete c._weight; delete c._zh; return c; });
  const isMaterial = (l) => l.section !== 'Delivery' && !l.blockId;
  const eff = {}; const tot = {};
  lines.forEach((l) => {
    eff[l.id] = isMaterial(l) && !l.noMarkup ? markedUp(l.appliedUnitPrice, q.markupPercent) : l.appliedUnitPrice;
    tot[l.id] = r2(Math.round(l.quantity) * eff[l.id]);
  });
  const sum = (f) => r2(lines.filter(f).reduce((a, l) => a + tot[l.id], 0));
  const oneTime = isRental ? sum((l) => isMaterial(l) && l.chargeOnce) : 0;
  const materials = sum((l) => isMaterial(l) && !(isRental && l.chargeOnce));
  const delivery = sum((l) => l.section === 'Delivery' && !l.blockId);
  const blocks = q.blocks || [];
  const priced = blocks.filter((b) => b.kind === 'Priced');
  const other = r2(priced.reduce((a, b) => a + sum((l) => l.blockId === b.id), 0));
  const materialsCharge = r2(materials * months);
  const subtotal = r2(materialsCharge + delivery + other + oneTime);
  const discountAmount = q.discountType === 'Percent' ? r2(subtotal * q.discountValue / 100) : q.discountType === 'Fixed' ? q.discountValue : 0;
  const total = r2(subtotal - discountAmount);
  const weighed = q.lines.filter((l) => isMaterial(l) && l._weight != null);
  const weight = r1(weighed.reduce((a, l) => a + l._weight * l.quantity, 0));
  const charges = isRental ? { monthly: materials, oneTime: r2(delivery + other + oneTime), recurring: {} } : { monthly: 0, oneTime: total, recurring: {} };
  const boq = q.sourceBOQId ? BOQS_RAW.find((b) => b.id === q.sourceBOQId) : null;
  const detail = {
    id: q.id, projectId: p.id, sourceBOQId: q.sourceBOQId || null, sourceBOQNumber: boq ? boq.boqNumber : null, quotationNumber: q.number, status: q.status,
    quotationDate: at(q.date), pricingMode: q.pricingMode, validUntil: q.validUntil || addDays(q.date, 7), paymentTerms: '30 days from invoice date',
    discountType: q.discountType || 'None', discountValue: q.discountValue || 0, taxRatePercent: 0, notes: q.notes || null,
    createdAt: at(q.date, '09:00'), updatedAt: q.updatedAt || at(q.date, '16:30'), projectNumber: p.projectNumber, projectName: p.name,
    clientName: CLIENT[p.clientId].companyName, siteName: SITE[p.siteId].name, lineItems: lines, subtotal, discountAmount, taxAmount: 0, total,
    subject: q.subject, clientRef: q.clientRef || null, siteRef: SITE[p.siteId].siteReference, deliveryMethod: 'BY EMAIL ONLY', hireMonths: months,
    materialsSubtotal: materials, materialsCharge, deliveryTotal: delivery, standardDeliveryCharge: 1800, deliveryRates: DELIVERY_RATES,
    materialsWeightKg: weighed.length ? weight : null, linesWithoutWeight: q.lines.filter((l) => isMaterial(l) && l._weight == null).length,
    minimumHireEnabled: isRental && !q.hirePeriodEnabled, minimumHireMonths: q.minimumHireMonths || 3, hirePeriodEnabled: !!q.hirePeriodEnabled, hirePeriodMonths: q.hirePeriodMonths || 6,
    markupPercent: q.markupPercent == null ? null : q.markupPercent, markupRoundUp: false, effectiveUnitPrices: eff, lineTotals: tot, blocks, otherChargesTotal: other,
    minimumMonthlyChargeEnabled: false, minimumMonthlyCharge: 1000, minimumMonthlyApplied: false, monthlyRental: isRental ? materials : 0, buyBackAmount: 0, oneTimeItemsTotal: oneTime,
    columnLayout: q.columnLayout || ['desc', 'rate', 'qty'], customColumns: q.customColumns || [], charges, keyTerms: null, standardKeyTerms: KEY_TERMS,
    signedCopyName: q.signed ? `${q.number} - Signed.pdf` : null, signedCopyAt: q.signed ? at(addDays(q.date, 3), '15:10') : null, signedCopyExists: !!q.signed, signedCopyNotNeeded: false,
    currency: q.currency || null, clientAgreedAt: null, importedDocumentId: null, importedFileName: null,
    buyBack: p.jobType === 'Crane' ? { enabled: true, percent: 60, afterMonths: 6, reductionPercent: 5, endMonths: 12, unitPrice: null, wording: SETTINGS.buyBackWording } : null,
    directorSignedBy: q.directorSigned ? 'William' : null, directorSignedAt: q.directorSigned ? at(addDays(q.date, 1), '11:00') : null, directorSignedExists: !!q.directorSigned,
    directorSignedPath: q.directorSigned ? `/Users/william/Documents/ScaffoldPro/Projects/${p.projectNumber}/Quotations/${q.number} - Signed by Director.pdf` : null,
    signPendingWith: q.signPendingWith || null, signRequestId: q.signPendingWith ? 'sr1' : null, clientMarkupPercent: CLIENT[p.clientId].defaultMarkupPercent || null,
    language: null, defaultLanguage: 'English', orientation: q.orientation || 'Portrait', jobType: p.jobType, boqLinked: !!q.boqLinked, sourceBOQStatus: boq ? boq.status : null,
    lineSort: 'manual', parent: null, subsidiaries: [],
  };
  const summary = {
    id: q.id, quotationNumber: q.number, status: q.status, itemCount: lines.length, total, createdAt: detail.createdAt, signed: !!q.signed,
    boqId: detail.sourceBOQId, boqNumber: detail.sourceBOQNumber, boqLinked: !!q.boqLinked, structure: boq ? boq.structure : null, subject: q.subject,
    pricingMode: q.pricingMode, charges, fromCombined: false, createdBy: q.createdBy || 'William', lastEditedBy: q.lastEditedBy || 'William', parentId: null, parentNumber: null,
  };
  DOC_AUTHORS['quotation:' + q.id] = authors(summary.createdBy, summary.lastEditedBy, detail.updatedAt);
  return { detail, summary, project: p, q };
}

// ---------------------------------------------------------------- BOQs
function boqLine(bid, n, name, qty, notes) {
  const it = item(name);
  return { id: `${bid}_l${n}`, boqId: bid, sourceKey: 'SP', priceListItemId: it.id, itemCode: it.itemCode, itemDescription: it.itemName, unit: it.unit, quantity: qty,
    priceListUnitPrice: it.unitRentalPrice, appliedUnitPrice: it.unitRentalPrice, weightKg: it.weightKg, section: it.category, sortOrder: n, notes: notes || null };
}
const BOQ_ZONE_A = [
  ['600mm Base Jack', 288], ['Timber Sole Board', 288], ['2.0m standard with spigot', 432], ['1.0m standard with spigot', 144], ['2.07m Ledger', 864], ['0.73m Ledger', 576],
  ['2.07m x 2.0m Face Brace', 216], ['2.07m x 0.32m Steel Deck', 648], ['2.07m Toe Board', 288], ['0.73m Toe Board', 192], ['2.57m Aluminumn Staircase', 18], ['Right Angle Coupler (fixed)', 360],
  ['1.2m Wall Tie Tube', 120],
];
const BOQS_RAW = [
  { id: 'doc1', projectId: 'p26219', boqNumber: 'BOQ26219-001', status: 'Issued', pricingMode: 'Rental', structure: 'Zone A – roof access tower and perimeter platform', date: '2026-09-02', rows: BOQ_ZONE_A, createdBy: 'Irene', lastEditedBy: 'Irene' },
  { id: 'b2', projectId: 'p26219', boqNumber: 'BOQ26219-002', status: 'Draft', pricingMode: 'Rental', structure: 'Zone B – truss-out at level 5', date: '2026-10-12', rows: BOQ_ZONE_A.slice(0, 9).map(([n, q]) => [n, Math.round(q * 0.6)]), createdBy: 'Irene', lastEditedBy: 'William' },
  { id: 'b3', projectId: 'p26220', boqNumber: 'BOQ26220-001', status: 'Issued', pricingMode: 'Rental', structure: 'Block B north façade, G/F to 12/F', date: '2026-08-05', rows: BOQ_ZONE_A.map(([n, q]) => [n, q * 2]), createdBy: 'Jeremie', lastEditedBy: 'Jeremie' },
  { id: 'b4', projectId: 'p26221', boqNumber: 'BOQ26221-001', status: 'Draft', pricingMode: 'Rental', structure: 'Pier P7–P9 falsework', date: '2026-10-08', rows: BOQ_ZONE_A.slice(2, 11), createdBy: 'William', lastEditedBy: 'William' },
];
const BOQ = {};
const BOQ_SUMMARY = {};
for (const b of BOQS_RAW) {
  const p = PROJECT[b.projectId];
  const lines = b.rows.map(([name, qty], i) => boqLine(b.id, i + 1, name, qty, i === 0 ? 'On sole boards; check ground bearing at Gate 3 side.' : null));
  const grand = r2(lines.reduce((a, l) => a + l.quantity * l.appliedUnitPrice, 0));
  const weight = r1(lines.reduce((a, l) => a + l.quantity * (l.weightKg || 0), 0));
  const eff = Object.fromEntries(lines.map((l) => [l.id, l.appliedUnitPrice]));
  const zh = Object.fromEntries(lines.filter((l) => item(l.itemDescription).chineseName).map((l) => [l.id, item(l.itemDescription).chineseName]));
  const charges = b.id === 'doc1' ? [{ code: 'D1', name: 'Delivery (2 trips, 9-tonne lorry)', amount: 6400 }, { code: 'D2', name: 'Design and drawing', amount: 3500 }] : null;
  const chargesTotal = charges ? charges.reduce((a, c) => a + c.amount, 0) : 0;
  BOQ[b.id] = {
    deliveryRates: DELIVERY_RATES, clientMarkupPercent: CLIENT[p.clientId].defaultMarkupPercent || null, clientName: CLIENT[p.clientId].companyName,
    id: b.id, boqNumber: b.boqNumber, status: b.status, pricingMode: b.pricingMode, notes: 'Based on architectural drawings A-2201 rev C and A-2210 rev B.',
    createdAt: at(b.date, '09:20'), updatedAt: at(b.date, '17:05'), projectNumber: p.projectNumber, projectName: p.name, lineItems: lines,
    grandTotal: grand, totalWeightKg: weight, markupPercent: 0, structure: b.structure, orientation: 'Landscape', effectiveRates: eff,
    ratesSection: b.id === 'doc1' ? { title: 'Erection & Dismantle Manpower Rates', rates: MANPOWER_RATES.slice(0, 3).map(({ name, rate, unit }) => ({ name, rate, unit })), note: 'Rates only – charged on actual man-days.' } : null,
    charges, chargesTotal, totalAmount: r2(grand + chargesTotal), markupOnRates: true, markupRoundUp: false, chineseNames: zh,
    terms: null, signatureSection: true, standardTerms: SETTINGS.boqTerms, language: null, defaultLanguage: 'English',
    linkedQuotations: b.id === 'doc1' ? [{ id: 'doc1', number: 'Qt26219-002', status: 'Issued' }] : [], lineSort: 'code',
  };
  BOQ_SUMMARY[b.id] = { id: b.id, boqNumber: b.boqNumber, status: b.status, pricingMode: b.pricingMode, itemCount: lines.length, grandTotal: grand, totalWeightKg: weight,
    createdAt: at(b.date, '09:20'), structure: b.structure, combined: false, combinedFrom: null, createdBy: b.createdBy, lastEditedBy: b.lastEditedBy, _projectId: b.projectId };
  DOC_AUTHORS['boq:' + b.id] = authors(b.createdBy, b.lastEditedBy, at(b.date, '17:05'));
}

// ---------------------------------------------------------------- quotations
const Q_SPECS = [
  {
    id: 'doc1', projectId: 'p26219', number: 'Qt26219-002', status: 'Issued', date: '2026-09-04', pricingMode: 'Rental', sourceBOQId: 'doc1', boqLinked: true,
    subject: '26219 Scaffolding Materials – Rental – Kai Tak Sports Park Main Stadium Roof Access (Zone A)', clientRef: 'GAM/KTSP/SC-114', minimumHireMonths: 3, markupPercent: 10,
    signed: true, directorSigned: true, createdBy: 'Irene', lastEditedBy: 'William', updatedAt: '2026-10-14T09:42:00Z',
    lines: (qid) => BOQ_ZONE_A.map(([n, qty], i) => matLine(qid, i + 1, n, qty, { extra: { boqLineId: `doc1_l${i + 1}` } })).concat([
      customLine(qid, 20, '**Edge protection netting**, fire-retardant, 1.8m wide (per roll)', 'roll', 12, 85),
      customLine(qid, 21, 'Site safety induction & toolbox talk for crew (one-off)', 'lot', 1, 2800, { chargeOnce: true, noMarkup: true }),
      { id: `${qid}_l30`, quotationId: qid, sourceKey: null, priceListItemId: null, itemCode: '', itemDescription: 'Delivery – 9-tonne lorry, per trip (Kowloon)', unit: 'trip', quantity: 2, appliedUnitPrice: 3200, section: 'Delivery', sortOrder: 30 },
      { id: `${qid}_l31`, quotationId: qid, sourceKey: null, priceListItemId: null, itemCode: '', itemDescription: 'Collection – 9-tonne lorry, per trip', unit: 'trip', quantity: 2, appliedUnitPrice: 3200, section: 'Delivery', sortOrder: 31 },
      { id: `${qid}_l40`, quotationId: qid, sourceKey: null, priceListItemId: null, itemCode: '', itemDescription: 'Design and drawing by registered engineer', unit: 'lot', quantity: 1, appliedUnitPrice: 3500, section: null, sortOrder: 40, blockId: 'blk1' },
      { id: `${qid}_l41`, quotationId: qid, sourceKey: null, priceListItemId: null, itemCode: '', itemDescription: 'Form 5 inspection certificate (first)', unit: 'lot', quantity: 1, appliedUnitPrice: 0, section: null, sortOrder: 41, blockId: 'blk1', priceNote: '(Included)' },
      { id: `${qid}_l50`, quotationId: qid, sourceKey: null, priceListItemId: null, itemCode: '', itemDescription: 'Scaffolder CP', unit: 'md', quantity: 1, appliedUnitPrice: 2300, section: null, sortOrder: 50, blockId: 'blk2' },
      { id: `${qid}_l51`, quotationId: qid, sourceKey: null, priceListItemId: null, itemCode: '', itemDescription: 'Scaffolder', unit: 'md', quantity: 1, appliedUnitPrice: 1950, section: null, sortOrder: 51, blockId: 'blk2' },
      { id: `${qid}_l52`, quotationId: qid, sourceKey: null, priceListItemId: null, itemCode: '', itemDescription: 'General Worker', unit: 'md', quantity: 1, appliedUnitPrice: 1300, section: null, sortOrder: 52, blockId: 'blk2' },
    ]),
    blocks: (qid) => [
      { id: 'blk1', quotationId: qid, kind: 'Priced', title: 'Design Fees', prefix: 'A', note: null, sortOrder: 1 },
      { id: 'blk2', quotationId: qid, kind: 'Rates', title: 'Erection & Dismantle Manpower Rates', prefix: 'R', note: 'Rates only – charged on actual man-days worked.', sortOrder: 2 },
      { id: 'blk3', quotationId: qid, kind: 'Note', title: '', prefix: 'N', note: 'Night work (19:00–07:00) at 1.5× the rates above.', sortOrder: 3 },
    ],
  },
  { id: 'q2', projectId: 'p26219', number: 'Qt26219-003', status: 'Draft', date: '2026-10-13', pricingMode: 'Rental', sourceBOQId: 'b2', subject: '26219 Scaffolding Materials – Rental – Zone B truss-out at L5', minimumHireMonths: 3, markupPercent: 10, createdBy: 'William', lastEditedBy: 'William',
    lines: (qid) => BOQ_ZONE_A.slice(0, 9).map(([n, qty], i) => matLine(qid, i + 1, n, Math.round(qty * 0.6))) },
  { id: 'q3', projectId: 'p26219', number: 'Qt26219-001', status: 'Cancelled', date: '2026-08-28', pricingMode: 'Rental', subject: '26219 Scaffolding – Rental – preliminary budget', minimumHireMonths: 3, createdBy: 'Irene', lastEditedBy: 'Irene',
    lines: (qid) => BOQ_ZONE_A.slice(0, 6).map(([n, qty], i) => matLine(qid, i + 1, n, qty)) },
  { id: 'q4', projectId: 'p26220', number: 'Qt26220-001', status: 'Issued', date: '2026-08-07', pricingMode: 'Rental', sourceBOQId: 'b3', subject: '26220 Scaffolding Materials – Rental – TKO Hospital Block B façade', minimumHireMonths: 4, signed: true, createdBy: 'Jeremie', lastEditedBy: 'Jeremie',
    lines: (qid) => BOQ_ZONE_A.map(([n, qty], i) => matLine(qid, i + 1, n, qty * 2)) },
  { id: 'q5', projectId: 'p26221', number: 'Qt26221-001', status: 'Issued', date: '2026-10-09', pricingMode: 'Rental', sourceBOQId: 'b4', subject: '26221 Falsework – Rental – Tuen Mun Road Piers P7–P9', minimumHireMonths: 6, markupPercent: 8, signPendingWith: 'Jeremie', createdBy: 'William', lastEditedBy: 'William',
    lines: (qid) => BOQ_ZONE_A.slice(2, 11).map(([n, qty], i) => matLine(qid, i + 1, n, qty)) },
  { id: 'q6', projectId: 'p26222', number: 'Qt26222-001', status: 'Issued', date: '2026-09-15', pricingMode: 'Rental', subject: '26222 Boom-lift Hire – CKR Yau Ma Tei East Vent Building', hirePeriodEnabled: true, hirePeriodMonths: 3, signed: true, createdBy: 'Tom', lastEditedBy: 'Tom',
    columnLayout: ['desc', 'model', 'rate', 'qty'], customColumns: [{ id: 'model', title: 'Model' }],
    lines: (qid) => [
      customLine(qid, 1, 'Articulating boom lift, 26m working height, diesel 4WD', 'unit/month', 2, 38500, { customValues: { model: 'Genie Z-80/60' } }),
      customLine(qid, 2, 'Telescopic boom lift, 41m working height', 'unit/month', 1, 52000, { customValues: { model: 'JLG 1350SJP' } }),
      customLine(qid, 3, 'Operator familiarisation on site (half day)', 'lot', 1, 3800, { chargeOnce: true }),
      { id: `${qid}_l9`, quotationId: qid, sourceKey: null, priceListItemId: null, itemCode: '', itemDescription: 'Low-loader delivery and collection', unit: 'trip', quantity: 2, appliedUnitPrice: 6800, section: 'Delivery', sortOrder: 9 },
    ] },
  { id: 'q7', projectId: 'p26225', number: 'Qt26225-001', status: 'Draft', date: '2026-10-09', pricingMode: 'Sale', subject: '26225 Spider Crane – Sale – Tung Chung Area 99', currency: 'USD', createdBy: 'Tom', lastEditedBy: 'Jeremie',
    lines: (qid) => [customLine(qid, 1, 'Mini crawler crane, 3.0t SWL, 16.4m max. working radius', 'unit', 1, 68500), customLine(qid, 2, 'Fly jib extension, 1.2t SWL', 'set', 1, 9200), customLine(qid, 3, 'Remote control unit and spare battery pack', 'set', 1, 2400)] },
  { id: 'q8', projectId: 'p26223', number: 'Qt26223-001', status: 'Issued', date: '2026-06-22', pricingMode: 'Rental', subject: '26223 Scaffolding – Rental – Lyric Theatre stage tower', minimumHireMonths: 3, createdBy: 'Jeremie', lastEditedBy: 'William',
    lines: (qid) => BOQ_ZONE_A.slice(0, 8).map(([n, qty], i) => matLine(qid, i + 1, n, qty)) },
  { id: 'q9', projectId: 'p26226', number: 'Qt26226-001', status: 'Issued', date: '2026-02-20', pricingMode: 'Rental', subject: '26226 Scaffolding – Rental – Anderson Road podium', minimumHireMonths: 4, signed: true, createdBy: 'William', lastEditedBy: 'Irene',
    lines: (qid) => BOQ_ZONE_A.map(([n, qty], i) => matLine(qid, i + 1, n, Math.round(qty * 1.4))) },
  { id: 'q10', projectId: 'p26218', number: 'Qt26218-001', status: 'Issued', date: '2026-01-26', pricingMode: 'Sale', subject: '26218 Scaffolding Materials – Sale – Cruise Terminal canopy', signed: true, createdBy: 'William', lastEditedBy: 'William',
    lines: (qid) => BOQ_ZONE_A.slice(0, 7).map(([n, qty], i) => matLine(qid, i + 1, n, Math.round(qty / 2), { sale: true })) },
];
const QUOTES = Q_SPECS.map((s) => buildQuotation(Object.assign({}, s, { lines: s.lines(s.id), blocks: s.blocks ? s.blocks(s.id) : [] })));
const QUOTE = Object.fromEntries(QUOTES.map((x) => [x.q.id, x]));

// ---------------------------------------------------------------- delivery notes
const DN_SPECS = [
  { id: 'doc1', projectId: 'p26219', number: 'DN26219-003', status: 'Draft', date: '2026-10-15', quotationId: 'doc1', rows: BOQ_ZONE_A.slice(4, 10).map(([n, q]) => [n, Math.round(q / 3)]), deliveredBy: 'Harry', notes: 'Night delivery, Gate 3. Call Mr. Sam Wong 30 min before arrival.' },
  { id: 'dn2', projectId: 'p26219', number: 'DN26219-002', status: 'Issued', date: '2026-09-22', quotationId: 'doc1', rows: BOQ_ZONE_A.slice(0, 8).map(([n, q]) => [n, Math.round(q / 2)]), deliveredBy: 'Harry', receivedBy: 'Sam Wong', signed: true },
  { id: 'dn3', projectId: 'p26219', number: 'DN26219-001', status: 'Issued', date: '2026-09-10', quotationId: 'doc1', rows: BOQ_ZONE_A.slice(0, 6).map(([n, q]) => [n, Math.round(q / 2)]), deliveredBy: 'Harry', receivedBy: 'Sam Wong', signed: true },
  { id: 'dn4', projectId: 'p26220', number: 'DN26220-001', status: 'Issued', date: '2026-08-19', quotationId: 'q4', rows: BOQ_ZONE_A.map(([n, q]) => [n, q]), deliveredBy: 'Harry', receivedBy: 'Joyce Lau', signed: true },
  { id: 'dn5', projectId: 'p26222', number: 'DN26222-001', status: 'Issued', date: '2026-09-21', quotationId: 'q6', custom: [['Genie Z-80/60 articulating boom lift', 'unit', 2], ['JLG 1350SJP telescopic boom lift', 'unit', 1]], deliveredBy: 'Tom', receivedBy: 'Chris Evans', signed: true },
];
const DN = {};
const DN_SUMMARY = {};
for (const d of DN_SPECS) {
  const p = PROJECT[d.projectId];
  const lines = d.custom
    ? d.custom.map(([desc, unit, qty], i) => ({ id: `${d.id}_l${i + 1}`, deliveryNoteId: d.id, sourceKey: null, priceListItemId: null, itemCode: '', itemDescription: desc, unit, quantity: qty, section: 'Other', sortOrder: i + 1, notes: null }))
    : d.rows.map(([name, qty], i) => { const it = item(name); return { id: `${d.id}_l${i + 1}`, deliveryNoteId: d.id, sourceKey: 'SP', priceListItemId: it.id, itemCode: it.itemCode, itemDescription: it.itemName, unit: it.unit, quantity: qty, section: it.category, sortOrder: i + 1, notes: null }; });
  const invNums = { dn2: ['Inv26219-001'], dn3: ['Inv26219-001'], dn4: ['Inv26220-001'], dn5: ['Inv26222-001'] }[d.id] || [];
  DN[d.id] = {
    id: d.id, deliveryNoteNumber: d.number, status: d.status, deliveryDate: at(d.date, '08:00'), deliveryAddress: SITE[p.siteId].address, deliveredBy: d.deliveredBy, receivedBy: d.receivedBy || null,
    notes: d.notes || null, createdAt: at(addDays(d.date, -1), '15:00'), updatedAt: at(d.id === 'doc1' ? TODAY : d.date, '09:30'), projectNumber: p.projectNumber, projectName: p.name,
    clientName: CLIENT[p.clientId].companyName, siteName: SITE[p.siteId].name, lineItems: lines, contactPerson: SITE[p.siteId].contactPerson, projectId: p.id, sourceQuotationId: d.quotationId,
    chineseNames: Object.fromEntries(lines.filter((l) => l.priceListItemId && item(l.itemDescription).chineseName).map((l) => [l.id, item(l.itemDescription).chineseName])),
    language: null, defaultLanguage: 'English', signedCopyName: d.signed ? `${d.number} - Signed.pdf` : null, signedCopyAt: d.signed ? at(addDays(d.date, 1), '10:00') : null,
    signedCopyExists: !!d.signed, invoiceNumbers: invNums, stockBooked: !!d.signed, isSale: false, stockOutstanding: d.signed ? lines.reduce((a, l) => a + l.quantity, 0) : null,
    returnCheckDate: d.signed ? addDays(d.date, 30) : null,
  };
  DN_SUMMARY[d.id] = { id: d.id, deliveryNoteNumber: d.number, status: d.status, itemCount: lines.length, deliveryDate: DN[d.id].deliveryDate, createdAt: DN[d.id].createdAt,
    createdBy: d.deliveredBy === 'Tom' ? 'Tom' : 'Irene', lastEditedBy: d.id === 'doc1' ? 'Harry' : 'Irene', sourceQuotationId: d.quotationId, quotationNumber: QUOTE[d.quotationId].q.number,
    invoiceNumbers: invNums, signed: !!d.signed, totalQuantity: lines.reduce((a, l) => a + l.quantity, 0), _projectId: d.projectId };
  DOC_AUTHORS['deliveryNote:' + d.id] = authors(DN_SUMMARY[d.id].createdBy, DN_SUMMARY[d.id].lastEditedBy, DN[d.id].updatedAt);
}

// ---------------------------------------------------------------- invoices
const INV_SPECS = [
  { id: 'doc1', projectId: 'p26219', number: 'Inv26219-001', status: 'PartiallyPaid', date: '2026-10-02', quotationId: 'doc1', dns: ['dn3', 'dn2'], paidShare: 0.6, period: '10 Sep – 9 Oct 2026' },
  { id: 'i2', projectId: 'p26220', number: 'Inv26220-001', status: 'Paid', date: '2026-09-01', quotationId: 'q4', dns: ['dn4'], paidAll: true, period: '19 Aug – 18 Sep 2026' },
  { id: 'i3', projectId: 'p26220', number: 'Inv26220-002', status: 'Issued', date: '2026-10-01', quotationId: 'q4', dns: ['dn4'], period: '19 Sep – 18 Oct 2026' },
  { id: 'i4', projectId: 'p26222', number: 'Inv26222-001', status: 'Overdue', date: '2026-09-08', quotationId: 'q6', dns: ['dn5'], period: '21 Sep – 20 Oct 2026' },
  { id: 'i5', projectId: 'p26226', number: 'Inv26226-004', status: 'Paid', date: '2026-08-31', quotationId: 'q9', paidAll: true, period: '1 Aug – 28 Aug 2026' },
  { id: 'i6', projectId: 'p26218', number: 'Inv26218-001', status: 'Paid', date: '2026-02-10', quotationId: 'q10', paidAll: true },
  { id: 'i7', projectId: 'p26219', number: 'Inv26219-002', status: 'Draft', date: '2026-10-14', quotationId: 'doc1', dns: ['dn2'], period: '10 Oct – 9 Nov 2026' },
];
const INV = {};
const INV_SUMMARY = {};
for (const s of INV_SPECS) {
  const p = PROJECT[s.projectId];
  const qd = QUOTE[s.quotationId].detail;
  const src = qd.lineItems.filter((l) => !l.blockId && !(qd.pricingMode === 'Rental' && l.chargeOnce));
  const lines = src.map((l, i) => ({ id: `${s.id}_l${i + 1}`, invoiceId: s.id, sourceKey: l.sourceKey, priceListItemId: l.priceListItemId, itemCode: l.itemCode, itemDescription: l.itemDescription,
    unit: l.unit, quantity: l.quantity, appliedUnitPrice: qd.effectiveUnitPrices[l.id], section: l.section, sortOrder: i + 1 }));
  const materials = r2(lines.filter((l) => l.section !== 'Delivery').reduce((a, l) => a + l.quantity * l.appliedUnitPrice, 0));
  const delivery = s.id === 'doc1' || s.id === 'i2' || s.id === 'i4' ? r2(lines.filter((l) => l.section === 'Delivery').reduce((a, l) => a + l.quantity * l.appliedUnitPrice, 0)) : 0;
  const finalLines = delivery ? lines : lines.filter((l) => l.section !== 'Delivery');
  const total = r2(materials + delivery);
  const paid = s.paidAll ? total : r2(total * (s.paidShare || 0));
  const dueDate = addDays(s.date, 30);
  INV[s.id] = {
    id: s.id, invoiceNumber: s.number, status: s.status, invoiceDate: at(s.date), dueDate: at(dueDate), paymentTerms: '30 days from invoice date', discountType: 'None', discountValue: 0, taxRatePercent: 0,
    amountPaid: paid, notes: null, createdAt: at(s.date, '09:00'), updatedAt: at(s.date, '17:00'), projectNumber: p.projectNumber, projectName: p.name,
    clientName: CLIENT[p.clientId].companyName, siteName: SITE[p.siteId].name, lineItems: finalLines, subtotal: total, discountAmount: 0, taxAmount: 0, total, balanceDue: r2(total - paid),
    sourceQuotationId: s.quotationId, sourceQuotationNumber: QUOTE[s.quotationId].q.number, pricingMode: qd.pricingMode, rentalMonths: 1, rentalPeriod: s.period || null,
    materialsSubtotal: materials, materialsCharge: materials, deliveryTotal: delivery, otherChargesTotal: 0, paymentTermsFromSettings: s.status === 'Draft', defaultPaymentTerms: SETTINGS.defaultPaymentTerms,
    currency: qd.currency || null, deliveryNotes: (s.dns || []).map((id) => ({ id, number: DN[id].deliveryNoteNumber, status: DN[id].status, signedCopyName: DN[id].signedCopyName, signedCopyExists: DN[id].signedCopyExists })),
  };
  INV_SUMMARY[s.id] = { id: s.id, invoiceNumber: s.number, status: s.status, itemCount: finalLines.length, total, amountPaid: paid, dueDate: at(dueDate), createdAt: at(s.date, '09:00'),
    createdBy: 'Irene', lastEditedBy: 'Irene', quotationNumber: QUOTE[s.quotationId].q.number, deliveryNoteNumbers: (s.dns || []).map((id) => DN[id].deliveryNoteNumber), _projectId: s.projectId, _date: s.date, _dueDate: dueDate };
  DOC_AUTHORS['invoice:' + s.id] = authors('Irene', 'Irene', INV[s.id].updatedAt);
}

// ---------------------------------------------------------------- letters
const LETTER_SPECS = [
  { id: 'doc1', projectId: 'p26219', clientId: 'c1', number: 'L26219-001', status: 'Draft', date: '2026-10-14', subject: 'Kai Tak Sports Park – Extension of hire and Zone B truss-out', attention: 'Mr. Kelvin Ho', yourRef: 'GAM/KTSP/SC-114',
    body: '<p>Dear Mr. Ho,</p><p>Further to our site meeting on 12 October 2026, we are pleased to confirm that the scaffolding to Zone A will remain on hire until the roof cladding works are complete, expected by the end of February 2027.</p><p>For the new truss-out at Level 5 (Zone B), please find our quotation <b>Qt26219-003</b> attached. Materials can be delivered within five working days of your confirmation.</p><p>Should you have any questions, please do not hesitate to contact the undersigned.</p><p>Yours faithfully,</p>', createdBy: 'William' },
  { id: 'l2', projectId: 'p26223', clientId: 'c5', number: 'L26223-001', status: 'Issued', date: '2026-09-18', subject: 'Lyric Theatre – Standing time for materials on site', attention: 'Mr. Raymond Chau', body: '<p>Dear Mr. Chau,</p><p>We refer to the suspension of works …</p>', createdBy: 'Jeremie' },
  { id: 'l3', projectId: null, clientId: 'c6', number: 'L-2026-014', status: 'Issued', date: '2026-10-05', subject: 'Introduction – system scaffold and boom-lift hire', attention: 'Ms. Vivian Ng', body: '<p>Dear Ms. Ng,</p><p>Proficiency (HK) Limited supplies …</p>', createdBy: 'Irene' },
  { id: 'l4', projectId: 'p26222', clientId: 'c4', number: 'L26222-001', status: 'Issued', date: '2026-10-08', subject: 'CKR Vent Building – Overdue payment reminder, Inv26222-001', attention: 'Mr. Daniel Price', body: '<p>Dear Mr. Price,</p><p>Our records show …</p>', createdBy: 'Irene' },
];
const LETTERS = LETTER_SPECS.map((l) => {
  const c = CLIENT[l.clientId];
  const letter = { id: l.id, letterNumber: l.number, projectId: l.projectId, clientId: l.clientId, status: l.status, letterDate: at(l.date), recipientName: c.companyName,
    recipientAddress: [c.address, c.addressLine2, 'Hong Kong'].join('\n'), attention: l.attention, yourRef: l.yourRef || null, subject: l.subject, bodyHTML: l.body, pdfPath: null,
    createdAt: at(l.date, '09:10'), updatedAt: at(l.date, '11:40'), attachments: l.id === 'doc1' ? [{ id: 'att1', description: 'Quotation Qt26219-003 for the Zone B truss-out', files: ['/Users/william/Documents/ScaffoldPro/Projects/26219/Quotations/Qt26219-003.pdf'] }] : [], annexurePrefix: null };
  const p = l.projectId ? PROJECT[l.projectId] : null;
  DOC_AUTHORS['letter:' + l.id] = authors(l.createdBy, l.createdBy, letter.updatedAt);
  return { letter, p, createdBy: l.createdBy };
});
const LETTER = Object.fromEntries(LETTERS.map((x) => [x.letter.id, x]));
const letterSummary = ({ letter, p, createdBy }) => ({ id: letter.id, letterNumber: letter.letterNumber, status: letter.status, letterDate: letter.letterDate, subject: letter.subject,
  recipientName: letter.recipientName, projectId: letter.projectId, projectNumber: p ? p.projectNumber : null, projectName: p ? p.name : null, updatedAt: letter.updatedAt, createdBy, lastEditedBy: createdBy });
const openingHTML = (l) => `<div class="opening"><p><b>${l.recipientName}</b><br>${l.recipientAddress.replace(/\n/g, '<br>')}</p><p>Attn: ${l.attention || ''}</p><p>Our Ref.: ${l.letterNumber}${l.yourRef ? '<br>Your Ref.: ' + l.yourRef : ''}</p><p>14 October 2026</p><p><b>Re: ${l.subject}</b></p></div>`;

// ---------------------------------------------------------------- doc rows (Dashboard, clients)
const docRow = (kind, x) => {
  const map = {
    BOQ: () => ({ id: x.id, number: x.boqNumber, status: x.status, date: x.createdAt, amount: x.grandTotal, url: `boq-editor.html?id=${x.id}`, p: PROJECT[x._projectId], by: x }),
    Quotation: () => ({ id: x.detail.id, number: x.q.number, status: x.q.status, date: x.detail.quotationDate, amount: x.detail.total, url: `quotation-editor.html?id=${x.q.id}`, p: x.project, by: x.summary, charges: x.detail.charges }),
    Invoice: () => ({ id: x.id, number: x.invoiceNumber, status: x.status, date: at(x._date), amount: x.total, balance: r2(x.total - x.amountPaid), dueDate: x.dueDate, url: `invoice-editor.html?id=${x.id}`, p: PROJECT[x._projectId], by: x, isOverdue: x.status === 'Overdue' }),
    'Delivery Note': () => ({ id: x.id, number: x.deliveryNoteNumber, status: x.status, date: x.deliveryDate, url: `delivery-note-editor.html?id=${x.id}`, p: PROJECT[x._projectId], by: x }),
  }[kind]();
  return { id: map.id, kind, number: map.number, status: map.status, projectNumber: map.p.projectNumber, projectName: map.p.name, clientName: CLIENT[map.p.clientId].companyName,
    date: map.date, updatedAt: map.date, amount: map.amount == null ? null : map.amount, balance: map.balance == null ? null : map.balance, dueDate: map.dueDate || null, isOverdue: !!map.isOverdue,
    url: map.url, charges: map.charges || null, createdBy: map.by.createdBy, lastEditedBy: map.by.lastEditedBy, lastEditedAt: map.date, mine: map.by.lastEditedBy === ME };
};
const ALL_DOC_ROWS = [].concat(
  Object.values(BOQ_SUMMARY).map((x) => docRow('BOQ', x)),
  QUOTES.map((x) => docRow('Quotation', x)),
  Object.values(INV_SUMMARY).map((x) => docRow('Invoice', x)),
  Object.values(DN_SUMMARY).map((x) => docRow('Delivery Note', x)),
).sort((a, b) => b.date.localeCompare(a.date));

// ---------------------------------------------------------------- activity
const ACTIVITY = [
  ['a1', 'p26219', 'Edited quotation', 'Qt26219-002', '2026-10-14T09:42:00Z', 'William'],
  ['a2', 'p26219', 'Created delivery note', 'DN26219-003', '2026-10-14T09:05:00Z', 'Harry'],
  ['a3', 'p26219', 'Created invoice', 'Inv26219-002', '2026-10-14T08:50:00Z', 'Irene'],
  ['a4', 'p26220', 'Recorded payment HK$ 48,200.00', 'Inv26220-001', '2026-10-13T16:05:00Z', 'Irene'],
  ['a5', 'p26219', 'Created BOQ', 'BOQ26219-002', '2026-10-12T14:30:00Z', 'Irene'],
  ['a6', 'p26221', 'Issued quotation', 'Qt26221-001', '2026-10-13T11:20:00Z', 'William'],
  ['a7', 'p26222', 'Uploaded drawing', 'Boom-lift positions rev B.pdf', '2026-10-12T15:30:00Z', 'Tom'],
  ['a8', 'p26225', 'Created quotation', 'Qt26225-001', '2026-10-09T10:10:00Z', 'Tom'],
  ['a9', 'p26219', 'Added signed copy', 'DN26219-002', '2026-09-23T10:00:00Z', 'Harry'],
  ['a10', 'p26219', 'Issued quotation', 'Qt26219-002', '2026-09-04T16:30:00Z', 'Irene'],
  ['a11', null, 'Backup made (scheduled)', null, '2026-10-14T00:00:00Z', 'William'],
  ['a12', 'p26223', 'Status changed to On Hold', null, '2026-09-18T12:00:00Z', 'William'],
].map(([id, pid, action, reference, createdAt, by]) => ({ id, projectNumber: pid ? PROJECT[pid].projectNumber : null, projectName: pid ? PROJECT[pid].name : null, action, reference, createdAt, by, mine: by === ME, _pid: pid }));
const activityRow = (a) => { const r = Object.assign({}, a); delete r._pid; return r; };

// ---------------------------------------------------------------- tasks & calendar
const TASK_SPECS = [
  ['t1', 'Confirm night delivery slot with Gammon for DN26219-003', 'p26219', 'Harry', '2026-10-14', '18:00', null, 'High', false],
  ['t2', 'Chase payment for Inv26222-001 (Leighton)', 'p26222', 'Irene', '2026-10-13', null, null, 'High', false],
  ['t3', 'Site meeting – Zone B truss-out', 'p26219', 'William', '2026-10-15', '10:00', '11:30', null, false],
  ['t4', 'Get Jeremie to sign Qt26221-001', 'p26221', 'William', '2026-10-14', null, null, null, false],
  ['t5', 'Boom-lift monthly inspection (LALG)', 'p26222', 'Tom', '2026-10-16', '09:00', '12:00', null, false],
  ['t6', 'Stock count – ledgers & steel decks', null, null, '2026-10-17', '08:30', '12:30', null, false],
  ['t7', 'Send revised BOQ to Chun Wo', 'p26221', 'William', '2026-10-12', null, null, null, true],
  ['t8', 'Renew CAR insurance policy', null, 'Irene', '2026-10-20', null, null, null, false],
  ['t9', 'Toolbox talk – working at height', null, null, '2026-10-19', '07:30', '08:00', null, false, 'Site'],
  ['t10', 'Prepare spider crane spec sheet for CSCE', 'p26225', 'Tom', '2026-10-15', null, null, null, false],
];
const TASKS = TASK_SPECS.map(([id, title, projectId, assignee, dueDate, dueTime, endTime, priority, done, team]) => ({
  task: { id, title, notes: id === 't1' ? 'Gate 3 only after 19:00. Sam Wong to confirm crane-free window.' : null, projectId, assignee, dueDate, dueTime, endTime, team: team || null, priority,
    done, doneAt: done ? at(dueDate, '17:00') : null, doneBy: done ? assignee : null, createdBy: 'William', createdAt: at(addDays(dueDate, -4), '09:00'), updatedAt: at(addDays(dueDate, -1), '12:00') },
  projectNumber: projectId ? PROJECT[projectId].projectNumber : null, projectName: projectId ? PROJECT[projectId].name : null,
  mine: assignee === ME || (!assignee && true), overdue: !done && dueDate < TODAY,
}));
const CALENDAR = [
  ...TASKS.map(({ task, projectNumber }) => ({ date: task.dueDate, kind: 'Task', title: task.title, detail: projectNumber ? `Project ${projectNumber}` : null, url: projectNumber ? `project-detail.html?number=${projectNumber}` : 'tasks.html',
    done: task.done, person: task.assignee || task.team, overdue: !task.done && task.dueDate < TODAY, time: task.dueTime || null, endTime: task.endTime || null, id: task.id })),
  { date: '2026-10-15', kind: 'Delivery', title: 'DN26219-003 – Kai Tak Sports Park', detail: '6 items · night delivery Gate 3', url: 'delivery-note-editor.html?id=doc1', time: '20:00', person: 'Harry' },
  { date: '2026-10-12', kind: 'Inspection', title: 'Form 5 – Zone A roof access tower', detail: '26219 · Safe', url: 'project-detail.html?number=26219&tab=inspections', done: true },
  { date: '2026-10-16', kind: 'Inspection', title: 'Form 5 due – Block B north façade', detail: '26220', url: 'project-detail.html?number=26220&tab=inspections' },
  { date: '2026-10-16', kind: 'Quotation', title: 'Qt26221-001 valid until', detail: 'Chun Wo – Tuen Mun Road', url: 'quotation-editor.html?id=q5' },
  { date: '2026-10-08', kind: 'Invoice', title: 'Inv26222-001 due', detail: 'Leighton Contractors (Asia)', url: 'invoice-editor.html?id=i4', overdue: true },
  { date: '2026-10-31', kind: 'Invoice', title: 'Inv26220-002 due', detail: 'Hip Hing', url: 'invoice-editor.html?id=i3' },
  { date: '2026-10-14', kind: 'Lead', title: 'Follow up: Kerry Properties', detail: 'Tender for Tai Wai residential', url: 'marketing.html?tab=leads&lead=ld2', person: 'Jeremie' },
  { date: '2026-10-18', kind: 'Expiry', title: 'Green card expires – Chan Siu-keung', detail: 'Construction Workers Registration', url: 'workers.html?worker=w2' },
  { date: '2026-11-02', kind: 'Project', title: '26225 starts', detail: 'Tung Chung Area 99', url: 'project-detail.html?number=26225' },
  { date: '2026-10-13', kind: 'Delivery', title: 'Return check – DN26220-001', detail: 'Hip Hing · items on site', url: 'stock.html?tab=returns&dn=dn4' },
];

// ---------------------------------------------------------------- inspections, drawings, documents
const INSPECTIONS = [
  { id: 'ins1', projectId: 'p26219', structure: 'Zone A – roof access tower', location: 'Grid C/7–9', inspectedOn: '2026-10-12', inspector: 'Harry Lam (CP)', result: 'Safe', remarks: null, actionTaken: null, nextDue: '2026-10-26', dismantled: false, createdBy: 'Harry', createdAt: at('2026-10-12', '16:00'), updatedAt: at('2026-10-12', '16:00') },
  { id: 'ins2', projectId: 'p26219', structure: 'Zone A – perimeter platform', location: 'Level 6 roof edge', inspectedOn: '2026-10-05', inspector: 'Harry Lam (CP)', result: 'Safe with remarks', remarks: 'Two toe boards missing at bay 14.', actionTaken: 'Replaced on the day.', nextDue: '2026-10-19', dismantled: false, createdBy: 'Harry', createdAt: at('2026-10-05', '15:30'), updatedAt: at('2026-10-05', '17:00') },
  { id: 'ins3', projectId: 'p26219', structure: 'Loading bay tower', location: 'Gate 3', inspectedOn: '2026-09-14', inspector: 'Harry Lam (CP)', result: 'Safe', remarks: null, actionTaken: null, nextDue: null, dismantled: true, createdBy: 'Harry', createdAt: at('2026-09-14', '15:30'), updatedAt: at('2026-09-28', '10:00') },
];
const DRAWINGS = [
  { id: 'dr1', originalName: 'A-2201 Roof plan rev C.pdf', storedFilename: 'A-2201 Roof plan rev C.pdf', fileType: 'pdf', fileSizeBytes: 2841236, description: 'Roof plan – Zones A to C', uploadedAt: at('2026-09-01', '10:12'), fileExists: true, linkedKind: 'BOQ', linkedId: 'doc1', linkedNumber: 'BOQ26219-001', appended: true },
  { id: 'dr2', originalName: 'A-2210 Section B-B rev B.pdf', storedFilename: 'A-2210 Section B-B rev B.pdf', fileType: 'pdf', fileSizeBytes: 1620554, description: 'Stadium roof section', uploadedAt: at('2026-09-01', '10:13'), fileExists: true, linkedKind: 'BOQ', linkedId: 'doc1', linkedNumber: 'BOQ26219-001' },
  { id: 'dr3', originalName: 'SK-05 Zone B truss-out.dwg', storedFilename: 'SK-05 Zone B truss-out.dwg', fileType: 'dwg', fileSizeBytes: 512880, description: 'Truss-out sketch at L5', uploadedAt: at('2026-10-12', '14:10'), fileExists: true, linkedKind: null, linkedId: null, linkedNumber: null },
];
const PROJECT_DOCS = [
  { id: 'pd1', originalName: 'Gammon sub-contract order SC-114.pdf', storedFilename: 'Gammon sub-contract order SC-114.pdf', category: 'Contracts', fileType: 'pdf', fileSizeBytes: 932110, description: 'Signed sub-contract order', uploadedAt: at('2026-09-05', '09:40'), fileExists: true },
  { id: 'pd2', originalName: 'Site induction record.pdf', storedFilename: 'Site induction record.pdf', category: 'Site Information', fileType: 'pdf', fileSizeBytes: 211004, description: null, uploadedAt: at('2026-09-08', '17:20'), fileExists: true },
  { id: 'pd3', originalName: 'Insurance certificate 2026.pdf', storedFilename: 'Insurance certificate 2026.pdf', category: 'Certificates', fileType: 'pdf', fileSizeBytes: 145230, description: 'Employees’ compensation & third party', uploadedAt: at('2026-09-03', '11:00'), fileExists: true },
];

// ---------------------------------------------------------------- dashboard
const MY_PROJECTS = ['p26219', 'p26221', 'p26220', 'p26223'].map((id) => { const p = PROJECT[id]; return { id, projectNumber: p.projectNumber, name: p.name, clientName: CLIENT[p.clientId].companyName, status: p.status, lastWorkedAt: LAST_ACTIVITY[id] || at('2026-09-18', '12:00'), createdBy: p.createdBy }; });
const INSPECTIONS_DUE = [
  { projectId: 'p26219', projectNumber: '26219', projectName: PROJECT.p26219.name, structure: 'Zone A – perimeter platform', lastInspected: '2026-10-05', lastResult: 'Safe with remarks', nextDue: '2026-10-19', daysLeft: 5, url: 'project-detail.html?number=26219&tab=inspections' },
  { projectId: 'p26220', projectNumber: '26220', projectName: PROJECT.p26220.name, structure: 'Block B north façade', lastInspected: '2026-10-02', lastResult: 'Safe', nextDue: '2026-10-16', daysLeft: 2, url: 'project-detail.html?number=26220&tab=inspections' },
  { projectId: 'p26220', projectNumber: '26220', projectName: PROJECT.p26220.name, structure: 'Hoist enclosure', lastInspected: '2026-09-28', lastResult: 'Safe', nextDue: '2026-10-12', daysLeft: -2, url: 'project-detail.html?number=26220&tab=inspections' },
];
const unpaid = ALL_DOC_ROWS.filter((d) => d.kind === 'Invoice' && d.balance > 0 && d.status !== 'Draft');
const DASHBOARD = {
  activeProjects: PROJECTS.filter((p) => p.status === 'Active').length, totalProjects: PROJECTS.length, clientCount: CLIENTS.length, priceListItemCount: ALL_ITEMS.length, currency: 'HKD',
  outstandingQuotations: ALL_DOC_ROWS.filter((d) => d.kind === 'Quotation' && (d.status === 'Issued' || d.status === 'Draft')).slice(0, 6),
  unpaidInvoices: unpaid, unpaidTotal: r2(unpaid.reduce((a, d) => a + d.balance, 0)), overdueCount: unpaid.filter((d) => d.isOverdue).length, overdueTotal: r2(unpaid.filter((d) => d.isOverdue).reduce((a, d) => a + d.balance, 0)),
  recentDeliveryNotes: ALL_DOC_ROWS.filter((d) => d.kind === 'Delivery Note').slice(0, 5), recentDocuments: ALL_DOC_ROWS.slice(0, 8), recentActivity: ACTIVITY.map(activityRow),
  awaitingSignedCopy: ALL_DOC_ROWS.filter((d) => ['q5', 'q8'].includes(d.id)), awaitingSignedCopyCount: 2, myProjects: MY_PROJECTS,
  teamActivity: ACTIVITY.filter((a) => a.by !== ME).map(activityRow), userName: ME, inspectionsDue: INSPECTIONS_DUE, myTasks: TASKS.filter((t) => t.mine && !t.task.done),
};

// ---------------------------------------------------------------- people, chat, announcements, signatures
const USER_PROFILES = PEOPLE.map((n) => ({ id: n.toLowerCase(), name: n, color: PERSON[n].color, updatedAt: '2026-06-01T09:00:00Z', appearance: 'System' }));
const USER_PAGE = { name: ME, computer: MACS[ME].computer, color: PERSON[ME].color, sharing: true, members: MEMBERS, myProjects: MY_PROJECTS,
  myDocuments: ALL_DOC_ROWS.filter((d) => d.mine).slice(0, 8), myActivity: ACTIVITY.filter((a) => a.mine).map(activityRow), createdCount: 14, lastWorkedCount: 9, team: 'Office', teams: TEAMS };
const TEAM_STATUS = { enabled: true, folder: '/Users/william/Library/Mobile Documents/com~apple~CloudDocs/Proficiency/ScaffoldPro Team', folderDisplay: 'iCloud Drive › Proficiency › ScaffoldPro Team',
  folderMissing: false, memberName: ME, members: MEMBERS, lastChangeAt: '2026-10-14T09:41:00Z', lastChangeBy: 'Jeremie', iCloudDrive: '/Users/william/Library/Mobile Documents/com~apple~CloudDocs', thisMacOutdated: false };

const CHAT_MESSAGES = {
  everyone: [
    ['m1', 'Irene', 'Morning all – reminder that the stock count is this Saturday 08:30 at the yard.', '2026-10-14T01:05:00Z'],
    ['m2', 'Harry', 'Noted. I’ll bring the scanner and the count sheets.', '2026-10-14T01:12:00Z', { reactions: { '👍': ['irene', 'william'] } }],
    ['m3', 'Tom', 'Boom lifts at CKR passed their monthly check, certificates uploaded to 26222.', '2026-10-14T01:30:00Z'],
    ['m4', 'William', 'Great work. Gammon confirmed the Zone B truss-out – Qt26219-003 going out today.', '2026-10-14T01:41:00Z', { replyTo: 'm1' }],
    ['m5', 'Jeremie', 'I’ll sign Qt26221-001 after lunch.', '2026-10-14T01:44:00Z'],
  ],
  'team:office': [
    ['m10', 'Irene', 'Leighton still hasn’t paid Inv26222-001. Sent a reminder letter on the 8th.', '2026-10-13T08:20:00Z'],
    ['m11', 'William', 'Give Daniel a call tomorrow please.', '2026-10-13T08:35:00Z'],
  ],
  'dm:harry|william': [
    ['m20', 'Harry', 'Gate 3 is closed until 19:00 on Thursday, I’ve moved the delivery to 20:00.', '2026-10-14T00:50:00Z'],
    ['m21', 'William', 'Thanks Harry, I’ll let Kelvin know.', '2026-10-14T00:58:00Z'],
  ],
};
const chatMsgs = (conv) => (CHAT_MESSAGES[conv] || []).map(([id, author, text, createdAt, extra]) => Object.assign({ id, conversation: conv, author, text, createdAt }, extra || {}));
const lastOf = (conv) => { const m = CHAT_MESSAGES[conv]; const l = m[m.length - 1]; return { lastText: l[2], lastAuthor: l[1], lastAt: l[3], count: m.length }; };
const CHAT_PAGE = { me: ME, myTeam: 'Office', people: PEOPLE, gifKey: null, conversations: [
  Object.assign({ id: 'everyone', title: 'Everyone', kind: 'everyone', with: null }, lastOf('everyone')),
  Object.assign({ id: 'team:office', title: 'Office', kind: 'team', with: null }, lastOf('team:office')),
  Object.assign({ id: 'dm:harry|william', title: 'Harry', kind: 'dm', with: 'Harry' }, lastOf('dm:harry|william')),
  { id: 'dm:jeremie|william', title: 'Jeremie', kind: 'dm', with: 'Jeremie', lastText: null, lastAuthor: null, lastAt: null, count: 0 },
] };

const ANNOUNCE = [
  { announcement: { id: 'an1', message: 'Stock count at the Tsing Yi yard this Saturday 17 Oct, 08:30. Site team please attend.', audience: 'Everyone', author: 'Irene', createdAt: '2026-10-13T02:00:00Z', showUntil: '2026-10-17', important: true, dismissedBy: [] }, mine: false },
  { announcement: { id: 'an2', message: 'New SP material prices from 1 November – see the Material List.', audience: 'Office', author: 'William', createdAt: '2026-10-12T03:00:00Z', showUntil: '2026-10-31', important: false, dismissedBy: [] }, mine: true },
];
const ANNOUNCEMENTS_PAGE = { me: ME, myTeam: 'Office', teams: TEAMS, visible: ANNOUNCE, mine: ANNOUNCE.filter((a) => a.mine) };

const SIGN_REQUESTS = [
  { id: 'sr1', kind: 'Quotation', documentId: 'q5', number: 'Qt26221-001', projectNumber: '26221', projectName: PROJECT.p26221.name, requestedBy: 'William', signer: 'Jeremie', note: 'Chun Wo want it before Friday.', status: 'Pending', createdAt: '2026-10-13T03:20:00Z' },
  { id: 'sr2', kind: 'Quotation', documentId: 'q2', number: 'Qt26219-003', projectNumber: '26219', projectName: PROJECT.p26219.name, requestedBy: 'Irene', signer: 'William', note: null, status: 'Pending', createdAt: '2026-10-14T01:30:00Z' },
  { id: 'sr3', kind: 'Quotation', documentId: 'doc1', number: 'Qt26219-002', projectNumber: '26219', projectName: PROJECT.p26219.name, requestedBy: 'Irene', signer: 'William', note: null, status: 'Signed', createdAt: '2026-09-04T07:00:00Z', decidedAt: '2026-09-05T03:00:00Z' },
];
const SIGNATURES_PAGE = { me: ME, canSign: true, incoming: SIGN_REQUESTS.filter((r) => r.signer === ME && r.status === 'Pending'), outgoing: SIGN_REQUESTS.filter((r) => r.requestedBy === ME), recent: SIGN_REQUESTS, signers: ['William', 'Jeremie'] };

// ---------------------------------------------------------------- workers & employees
const WORKER_SPECS = [
  ['w1', 'W001', 'Chan Tai-man', '陳大文', '先生', 'Scaffolder CP', '9611 2233', '2024-03-04', 1250, 'C668812(3)', 3, 'William', 4, 0],
  ['w2', 'W002', 'Chan Siu-keung', '陳少強', '先生', 'Scaffolder', '9622 3344', '2024-06-17', 1100, 'D234511(5)', 3, 'Irene', 3, 1],
  ['w3', 'W003', 'Lee Wing-hong', '李永康', '先生', 'Scaffolder', '9633 4455', '2025-01-06', 1100, 'E778123(0)', 2, 'William', 2, 0],
  ['w4', 'W004', 'Ho Ka-lok', '何家樂', '先生', 'General Worker', '9644 5566', '2025-09-01', 850, 'G120345(A)', 1, null, 1, 0],
  ['w5', 'W005', 'Mak Chi-wai', '麥志偉', '先生', 'Boom-lift Operator', '9655 6677', '2026-10-05', 1300, null, 0, null, 0, 0],
  ['w6', 'W006', 'Fung Yuk-lan', '馮玉蘭', '女士', 'Safety Officer', '9666 7788', '2025-05-12', 1400, 'K556677(2)', 3, 'Irene', 5, 2],
];
const WORKERS = WORKER_SPECS.map(([id, workerNumber, name, chineseName, honorific, position, phone, startDate, dailyWage, idNumber]) => ({
  id, workerNumber, name, position, phone, email: null, startDate, endDate: null, notes: null, isArchived: false, createdAt: at(startDate, '09:00'), chineseName, honorific, idNumber, dailyWage }));
const ROSTER = WORKER_SPECS.map((w, i) => ({ worker: WORKERS[i], agreementNumber: `${w[1]}-EA`, stage: w[10], signedBy: w[11], documents: w[12], expiring: w[13] }));
const EMPLOYEES = [
  ['e1', 'E001', 'William Chan', '陳偉文', 'Managing Director', 'Full-time', 'Monthly', 65000],
  ['e2', 'E002', 'Irene Wong', '王美玲', 'Office Manager', 'Full-time', 'Monthly', 32000],
  ['e3', 'E003', 'Harry Lam', '林家豪', 'Site Supervisor', 'Full-time', 'Monthly', 38000],
  ['e4', 'E004', 'Tom Cheung', '張德榮', 'Crane & Boom-lift Coordinator', 'Full-time', 'Monthly', 36000],
  ['e5', 'E005', 'Chan Tai-man', '陳大文', 'Scaffolder CP', 'Part-time', 'Daily', 1250, 'w1', 20],
  ['e6', 'E006', 'Ho Ka-lok', '何家樂', 'General Worker', 'Part-time', 'Daily', 850, 'w4', 18],
].map(([id, employeeNumber, name, chineseName, position, employmentType, payBasis, payRate, workerId, units]) => ({
  id, employeeNumber, name, chineseName, position, phone: null, workerId: workerId || null, employmentType, payBasis, payRate, usualUnitsPerMonth: units || null,
  monthlyAllowance: payBasis === 'Monthly' ? 1500 : null, mpfEnabled: true, annualLeaveDays: payBasis === 'Monthly' ? 14 : null, bankAccount: null, startDate: '2024-01-02', endDate: null,
  notes: null, isArchived: false, createdAt: '2024-01-02T09:00:00Z', updatedAt: '2026-09-30T09:00:00Z' }));
const EXPIRING = [
  { id: 'wd1', kind: 'Worker', ownerName: 'Chan Siu-keung', originalName: 'Green card.jpg', category: 'Certification', expiryDate: '2026-10-18', daysLeft: 4 },
  { id: 'wd2', kind: 'Worker', ownerName: 'Fung Yuk-lan', originalName: 'Safety Officer registration.pdf', category: 'Certification', expiryDate: '2026-11-02', daysLeft: 19 },
  { id: 'ad1', kind: 'Company', ownerName: 'Proficiency (HK) Limited', originalName: 'Contractor’s All Risks policy 2025-26.pdf', category: 'Insurance', expiryDate: '2026-10-31', daysLeft: 17 },
  { id: 'ad2', kind: 'Company', ownerName: 'Proficiency (HK) Limited', originalName: 'Business Registration Certificate.pdf', category: 'Licenses', expiryDate: '2026-10-10', daysLeft: -4 },
];
const TEAM_PAGE = { me: ME, teams: TEAMS, sharing: true, people: PEOPLE.map((n) => ({
  name: n, team: PERSON[n].team, title: PERSON[n].title, canSign: PERSON[n].canSign, canSignAgreements: PERSON[n].canSignAgreements, idNumber: PERSON[n].idNumber, isMe: n === ME,
  devices: MEMBERS.filter((m) => m.name === n), employeeNumber: (EMPLOYEES.find((e) => e.name.startsWith(n)) || {}).employeeNumber || null, position: PERSON[n].position, phone: PERSON[n].phone,
  hasSignature: PERSON[n].canSign, hasChop: PERSON[n].canSign, fullName: PERSON[n].fullName })) };

// ---------------------------------------------------------------- stock
const STOCK_ROWS = BOQ_ZONE_A.map(([name], i) => {
  const it = item(name);
  const onHireByProject = [
    { projectId: 'p26219', projectNumber: '26219', projectName: PROJECT.p26219.name, quantity: Math.round((DN.dn2.lineItems.concat(DN.dn3.lineItems).filter((l) => l.itemDescription === name).reduce((a, l) => a + l.quantity, 0))) },
    { projectId: 'p26220', projectNumber: '26220', projectName: PROJECT.p26220.name, quantity: (DN.dn4.lineItems.find((l) => l.itemDescription === name) || { quantity: 0 }).quantity },
  ].filter((x) => x.quantity > 0);
  const onHire = onHireByProject.reduce((a, x) => a + x.quantity, 0);
  const inYard = [820, 640, 1150, 380, 2400, 1460, 520, 1680, 760, 430, 34, 2200, 310][i];
  const rented = i === 4 ? 300 : 0;
  return { key: it.id, priceListItemId: it.id, sourceKey: 'SP', category: it.category, itemCode: it.itemCode, itemName: it.itemName, unit: it.unit, weightKg: it.weightKg,
    inYard, onHire, owned: inYard + onHire - rented, onHireByProject, rented, rentedByCompany: rented ? [{ company: 'Kwong Fat Scaffolding Co.', quantity: rented }] : [] };
});
const mv = (id, date, kind, name, quantity, extra) => { const it = item(name); return Object.assign({ id, date, kind, itemKey: it.id, priceListItemId: it.id, itemCode: it.itemCode, itemDescription: it.itemName, unit: it.unit, quantity,
  projectId: null, deliveryNoteId: null, reference: null, notes: null, createdAt: at(date, '17:00') }, extra || {}); };
const MOVEMENTS = [
  { movement: mv('mv1', '2026-10-09', 'Purchase', '2.07m Ledger', 600, { reference: 'SP PO-2026-118', batchId: 'bt1', notes: 'From SP Scaffolding, Shenzhen' }), projectNumber: null, automatic: false },
  { movement: mv('mv2', '2026-10-09', 'Purchase', '2.07m x 0.32m Steel Deck', 400, { reference: 'SP PO-2026-118', batchId: 'bt1' }), projectNumber: null, automatic: false },
  { movement: mv('mv3', '2026-09-23', 'Delivery', '2.07m Ledger', -144, { projectId: 'p26219', deliveryNoteId: 'dn2', reference: 'DN26219-002' }), projectNumber: '26219', automatic: true },
  { movement: mv('mv4', '2026-09-23', 'Delivery', '2.0m standard with spigot', -72, { projectId: 'p26219', deliveryNoteId: 'dn2', reference: 'DN26219-002' }), projectNumber: '26219', automatic: true },
  { movement: mv('mv5', '2026-10-06', 'Return', '0.73m Ledger', 40, { projectId: 'p26226', reference: 'Anderson Rd final return', batchId: 'bt2' }), projectNumber: '26226', automatic: false },
  { movement: mv('mv6', '2026-10-02', 'RentIn', '2.07m Ledger', 300, { company: 'Kwong Fat Scaffolding Co.', reference: 'KF-8812' }), projectNumber: null, automatic: false },
  { movement: mv('mv7', '2026-09-30', 'WriteOff', '2.07m Toe Board', -6, { notes: 'Bent beyond repair' }), projectNumber: null, automatic: false },
  { movement: mv('mv8', '2026-09-28', 'Adjustment', 'Right Angle Coupler (fixed)', -15, { notes: 'September count', batchId: 'bt3' }), projectNumber: null, automatic: false },
];
const RETURNS = [
  { deliveryNoteId: 'dn4', deliveryNoteNumber: 'DN26220-001', projectId: 'p26220', projectNumber: '26220', projectName: PROJECT.p26220.name, siteName: SITE.s2.name, clientName: CLIENT.c2.companyName,
    deliveryDate: '2026-08-19', signedAt: at('2026-08-20'), checkDate: '2026-10-13', due: true, delivered: 1408, returned: 120, outstanding: 1288,
    lines: DN.dn4.lineItems.slice(0, 5).map((l, i) => ({ itemKey: l.priceListItemId, priceListItemId: l.priceListItemId, itemCode: l.itemCode, itemName: l.itemDescription, unit: l.unit, delivered: l.quantity, returned: i === 4 ? 120 : 0, outstanding: l.quantity - (i === 4 ? 120 : 0) })) },
  { deliveryNoteId: 'dn3', deliveryNoteNumber: 'DN26219-001', projectId: 'p26219', projectNumber: '26219', projectName: PROJECT.p26219.name, siteName: SITE.s1.name, clientName: CLIENT.c1.companyName,
    deliveryDate: '2026-09-10', signedAt: at('2026-09-11'), checkDate: '2027-02-26', due: false, delivered: 432, returned: 0, outstanding: 432,
    lines: DN.dn3.lineItems.map((l) => ({ itemKey: l.priceListItemId, priceListItemId: l.priceListItemId, itemCode: l.itemCode, itemName: l.itemDescription, unit: l.unit, delivered: l.quantity, returned: 0, outstanding: l.quantity })) },
];
const STOCK = { items: STOCK_ROWS, movements: MOVEMENTS, projects: PROJECTS.filter((p) => !['Archived'].includes(p.status)).map(projectRef), returns: RETURNS,
  companies: ['Kwong Fat Scaffolding Co.', 'SP Scaffolding (Shenzhen) Ltd.', 'Gammon Construction Limited'] };

// ---------------------------------------------------------------- accounts
const ACC_INVOICES = Object.values(INV_SUMMARY).filter((s) => s.status !== 'Draft').map((s) => { const p = PROJECT[s._projectId]; return {
  id: s.id, invoiceNumber: s.invoiceNumber, projectId: p.id, projectNumber: p.projectNumber, projectName: p.name, clientName: CLIENT[p.clientId].companyName, status: s.status,
  invoiceDate: s._date, dueDate: s._dueDate, total: s.total, amountPaid: s.amountPaid, balanceDue: r2(s.total - s.amountPaid) }; });
// Earlier invoices of finished work, so the year's figures are full.
const PAST_INV = [
  ['pi1', 'Inv26205-003', 'p26205', '2026-01-30', 96400], ['pi2', 'Inv26205-004', 'p26205', '2026-02-27', 88150], ['pi3', 'Inv26226-001', 'p26226', '2026-03-31', 124800],
  ['pi4', 'Inv26226-002', 'p26226', '2026-04-30', 131250], ['pi5', 'Inv26226-003', 'p26226', '2026-05-29', 128900], ['pi6', 'Inv26218-002', 'p26218', '2026-03-16', 54200],
  ['pi7', 'Inv26218-003', 'p26218', '2026-06-30', 61850], ['pi8', 'Inv26223-001', 'p26223', '2026-07-31', 83600], ['pi9', 'Inv26223-002', 'p26223', '2026-08-31', 83600],
].map(([id, invoiceNumber, pid, invoiceDate, total]) => { const p = PROJECT[pid]; return { id, invoiceNumber, projectId: pid, projectNumber: p.projectNumber, projectName: p.name,
  clientName: CLIENT[p.clientId].companyName, status: 'Paid', invoiceDate, dueDate: addDays(invoiceDate, 30), total, amountPaid: total, balanceDue: 0 }; });
ACC_INVOICES.push(...PAST_INV);
const ACC_PAYMENTS = ACC_INVOICES.filter((i) => i.amountPaid > 0).map((i, n) => ({ id: `pay${n + 1}`, invoiceId: i.id, invoiceNumber: i.invoiceNumber, projectId: i.projectId,
  date: addDays(i.invoiceDate, 24), amount: i.amountPaid, method: n % 2 ? 'FPS' : 'Cheque', reference: n % 2 ? 'FPS 20261013' : `HSBC chq ${408120 + n}`, undated: false }));
const EXPENSES = [
  ['ex1', '2026-10-09', 'Materials purchase', 'SP Scaffolding (Shenzhen) Ltd.', '600 ledgers + 400 steel decks (PO-2026-118)', 119400, null, 'PO-2026-118'],
  ['ex2', '2026-10-08', 'Transport', 'Wing Fat Logistics', 'Lorry hire – September (14 trips)', 33600, null, 'WF-0926'],
  ['ex3', '2026-10-05', 'Labour / subcontract', 'Summit Engineering & Resources Limited', 'Scaffolders – 26219 erection, 42 md', 77700, 'p26219', 'SER-1041'],
  ['ex4', '2026-09-30', 'Salaries & MPF', null, 'September salaries and MPF', 182400, null, null],
  ['ex5', '2026-10-01', 'Rent & storage', 'Tsing Yi Yard Ltd.', 'Yard rent – October', 48000, null, 'TY-10/26'],
  ['ex6', '2026-10-03', 'Equipment & repairs', 'Genie Asia Service', 'Z-80/60 service and tyres', 12850, 'p26222', 'GA-5512'],
  ['ex7', '2026-10-11', 'Office & admin', 'HKBN', 'Office broadband & phones', 1288, null, null],
  ['ex8', '2026-09-25', 'Insurance & licences', 'AXA General Insurance', 'Employees’ compensation – quarterly', 21600, null, 'EC-Q4'],
].map(([id, date, category, supplier, description, amount, projectId, reference]) => ({ id, date, category, supplier, description, amount, projectId, reference, createdAt: at(date, '18:00') }));
const LIAB = [
  { liability: { id: 'lb1', name: 'Hang Seng SME loan', kind: 'Loan', creditor: 'Hang Seng Bank', amount: 1500000, startDate: '2025-04-01', dueDate: '2028-03-31', monthlyPayment: 45500, interestRatePercent: 4.25, reference: 'SME-88123', notes: null, createdAt: '2025-04-01T09:00:00Z', updatedAt: '2026-10-01T09:00:00Z' } },
  { liability: { id: 'lb2', name: 'Genie Z-80/60 hire purchase', kind: 'Hire purchase / lease', creditor: 'Orix Asia', amount: 860000, startDate: '2026-03-01', dueDate: '2029-02-28', monthlyPayment: 26800, interestRatePercent: 5.1, reference: 'HP-33019', notes: null, createdAt: '2026-03-01T09:00:00Z', updatedAt: '2026-10-01T09:00:00Z' } },
  { liability: { id: 'lb3', name: 'Profits tax 2025/26 (provisional)', kind: 'Tax', creditor: 'Inland Revenue Department', amount: 214000, startDate: '2026-08-15', dueDate: '2026-10-10', monthlyPayment: null, interestRatePercent: null, reference: 'BIR51', notes: null, createdAt: '2026-08-15T09:00:00Z', updatedAt: '2026-08-15T09:00:00Z' } },
].map((x, n) => {
  const payments = n === 2 ? [] : [0, 1, 2].map((k) => ({ id: `${x.liability.id}_p${k}`, liabilityId: x.liability.id, date: addDays('2026-08-01', k * 30), amount: x.liability.monthlyPayment, note: null, createdAt: at(addDays('2026-08-01', k * 30)) }));
  const paid = payments.reduce((a, p) => a + p.amount, 0) + (n === 0 ? 682500 : n === 1 ? 107200 : 0);
  return Object.assign(x, { payments, paid, balance: x.liability.amount - paid, isOverdue: n === 2 });
});
const ACCOUNTS = { currency: 'HKD', invoices: ACC_INVOICES, payments: ACC_PAYMENTS, expenses: EXPENSES, projects: PROJECTS.map(projectRef),
  categories: ['Materials purchase', 'Transport', 'Labour / subcontract', 'Salaries & MPF', 'Equipment & repairs', 'Rent & storage', 'Office & admin', 'Insurance & licences', 'Other'],
  liabilities: LIAB, liabilityKinds: ['Loan', 'Supplier bill', 'Hire purchase / lease', 'Credit card', 'Tax', 'MPF / wages payable', 'Deposit held', 'Other'] };

// ---------------------------------------------------------------- marketing
const LEADS = [
  ['ld1', 'Sun Hung Kai Properties', 'Mr. Edwin Lau', 'Tender', 'Quoted', 1850000, '2026-10-20', 'William', 'Tai Kok Tsui redevelopment – full façade scaffold'],
  ['ld2', 'Kerry Properties', 'Ms. Fiona Chow', 'Referral', 'Contacted', 960000, '2026-10-14', 'Jeremie', 'Tai Wai residential – tender in November'],
  ['ld3', 'Build King Holdings', 'Mr. Gary Mok', 'Website', 'New', 420000, '2026-10-16', 'Irene', 'Boom-lift hire enquiry for Tseung Kwan O'],
  ['ld4', 'Hong Kong Airport Authority', 'Mr. Simon Yip', 'Tender', 'Contacted', 3200000, '2026-10-28', 'William', 'T2 expansion – temporary works'],
  ['ld5', 'Wan Chung Construction', 'Mr. Kenny Lo', 'Cold Call', 'Lost', 280000, null, 'Jeremie', 'Went with a cheaper tube-and-coupler quote'],
  ['ld6', 'Shui On Building Contractors', 'Ms. Vivian Ng', 'Repeat Client', 'Won', 540000, null, 'Irene', 'Now project 26224'],
  ['ld7', 'Henderson Land', 'Mr. Alex Tang', 'Site Visit', 'New', 750000, '2026-10-22', 'Tom', 'Spider crane for glass installation, Central'],
].map(([id, company, contactPerson, source, status, estimatedValue, nextFollowUp, owner, notes]) => ({ id, company, contactPerson, phone: '2' + id.slice(2).padStart(3, '0') + ' 8800', email: null,
  source, status, estimatedValue, nextFollowUp, notes, owner, clientId: status === 'Won' ? 'c6' : null, createdAt: '2026-09-01T09:00:00Z', updatedAt: '2026-10-12T09:00:00Z' }));
const MONTHS = ['2025-11', '2025-12', '2026-01', '2026-02', '2026-03', '2026-04', '2026-05', '2026-06', '2026-07', '2026-08', '2026-09', '2026-10'];
const M_QUOTED = [[3, 410000, 1], [2, 280000, 1], [4, 620000, 2], [3, 515000, 2], [5, 880000, 3], [4, 690000, 2], [3, 470000, 1], [5, 940000, 3], [4, 760000, 2], [6, 1120000, 3], [5, 980000, 3], [4, 840000, 1]];
const REAL_QUOTES = QUOTES.filter((x) => x.q.status !== 'Cancelled' && x.q.date >= '2025-11-01').map((x) => ({ id: x.q.id, number: x.q.number, date: x.q.date, month: x.q.date.slice(0, 7), clientId: x.project.clientId,
  clientName: CLIENT[x.project.clientId].companyName, projectNumber: x.project.projectNumber, projectName: x.project.name, subject: x.q.subject, value: x.detail.total, won: !!x.q.signed }));
// Older quotations (projects not in this sample) fill each month up to M_QUOTED's count.
const PAST_SUBJECTS = ['Scaffolding Materials \u2013 Rental \u2013 fa\u00e7ade access', 'Truss-out platform \u2013 Rental', 'Boom-lift Hire \u2013 3 months', 'Scaffolding Materials \u2013 Sale', 'Lift shaft scaffold \u2013 Rental', 'Spider crane hire'];
let pastNo = 150;
const MKT_QUOTES = REAL_QUOTES.concat(...MONTHS.map((month, i) => {
  const [count, value, won] = M_QUOTED[i];
  const real = REAL_QUOTES.filter((q) => q.month === month);
  const need = Math.max(0, count - real.length);
  const left = Math.max(60000, value - real.reduce((a, q) => a + q.value, 0));
  const wonLeft = Math.max(0, won - real.filter((q) => q.won).length);
  return Array.from({ length: need }, (_, k) => { const c = CLIENTS[(i + k) % CLIENTS.length]; const n = pastNo++;
    return { id: `mq${n}`, number: `Qt26${n}-001`, date: `${month}-${String(4 + k * 6).padStart(2, '0')}`, month, clientId: c.id, clientName: c.companyName, projectNumber: `26${n}`,
      projectName: `${c.clientReference} \u2013 ${['Kowloon Bay', 'Sai Kung', 'Yuen Long', 'Aberdeen', 'Mong Kok', 'Tsing Yi'][(i + k) % 6]}`, subject: `26${n} ${PAST_SUBJECTS[(i + k) % PAST_SUBJECTS.length]}`,
      value: Math.round(left / need * (0.7 + 0.6 * ((k * 7 + i) % 5) / 4) / 10) * 10, won: k < wonLeft }; });
})).sort((a, b) => b.date.localeCompare(a.date));
const MKT_WON = MKT_QUOTES.filter((q) => q.won);
const MKT_VALUE = r2(MKT_QUOTES.reduce((a, q) => a + q.value, 0));
const MARKETING = {
  currency: 'HKD', months: MONTHS.map((month) => { const qs = MKT_QUOTES.filter((q) => q.month === month); return { month, quotedCount: qs.length, quotedValue: r2(qs.reduce((a, q) => a + q.value, 0)), wonCount: qs.filter((q) => q.won).length }; }),
  quotedCount: MKT_QUOTES.length, quotedValue: MKT_VALUE, wonCount: MKT_WON.length, winRate: MKT_WON.length / MKT_QUOTES.length, averageQuote: r2(MKT_VALUE / MKT_QUOTES.length), newClients: 3, openLeads: 5, pipelineValue: 7180000,
  leadSources: { Tender: 2, Referral: 1, Website: 1, 'Cold Call': 1, 'Repeat Client': 1, 'Site Visit': 1 },
  topClients: [['c1', 1240000, 9, 6], ['c2', 860000, 7, 4], ['c4', 395200, 3, 2], ['c8', 612000, 5, 3], ['c3', 210000, 6, 2]].map(([id, invoiced, quotations, won]) => ({ id, name: CLIENT[id].companyName, invoiced, quotations, won, lastActivity: '2026-10-13' })),
  quotes: MKT_QUOTES,
  followUps: [
    { kind: 'Quotation', title: 'Qt26221-001 – no reply yet', detail: 'Chun Wo · Tuen Mun Road piers', days: 5, url: 'quotation-editor.html?id=q5', owner: 'William' },
    { kind: 'Lead', title: 'Kerry Properties', detail: 'Follow-up due today', days: 0, url: 'marketing.html?tab=leads&lead=ld2', owner: 'Jeremie' },
    { kind: 'Client', title: 'Paul Y. Construction', detail: 'No new work for 84 days', days: 84, url: 'clients.html?id=c5', owner: null },
  ],
  references: PROJECTS.filter((p) => ['Active', 'Completed'].includes(p.status)).map((p) => ({ projectNumber: p.projectNumber, name: p.name, clientName: CLIENT[p.clientId].companyName, siteName: SITE[p.siteId].name,
    status: p.status, startDate: p.startDate, structures: ['Access towers', 'Working platforms'], quotedValue: (QUOTES.find((x) => x.project.id === p.id) || { detail: { total: 0 } }).detail.total, invoicedValue: 0 })),
};

// ---------------------------------------------------------------- settings page extras
const BACKUPS = [0, 1, 2, 3].map((n) => ({ name: `ScaffoldPro Backup ${addDays(TODAY, -n)} 00-00`, path: `/Users/william/Documents/ScaffoldPro/Backups/ScaffoldPro Backup ${addDays(TODAY, -n)} 00-00`,
  createdAt: at(addDays(TODAY, -n), '00:00'), kind: n === 2 ? 'Manual' : 'Scheduled', projectCount: PROJECTS.length, fileCount: 1284 - n * 6, totalBytes: 812345678 - n * 1200000 }));

// ---------------------------------------------------------------- per-project helpers
const forProject = (map, pid) => Object.values(map).filter((x) => x._projectId === pid).map((x) => { const r = Object.assign({}, x); for (const k of Object.keys(r)) if (k[0] === '_') delete r[k]; return r; });
const pidOf = (payload) => payload.projectId || 'p26219';
function chain(kind, id) {
  // BOQ › Quotation › Delivery Notes › Invoices, for 26219's main documents (others: just themselves).
  const isMain = { boq: ['doc1'], quotation: ['doc1'], deliveryNote: ['doc1', 'dn2', 'dn3'], invoice: ['doc1', 'i7'] }[kind] || [];
  if (!isMain.includes(id)) {
    const n = { boq: () => BOQ[id], quotation: () => QUOTE[id] && QUOTE[id].detail, deliveryNote: () => DN[id], invoice: () => INV[id] }[kind];
    const d = n && n();
    if (!d) return [];
    return [{ kind: { boq: 'BOQ', quotation: 'Quotation', deliveryNote: 'DeliveryNote', invoice: 'Invoice' }[kind], id, number: d.boqNumber || d.quotationNumber || d.deliveryNoteNumber || d.invoiceNumber, status: d.status, url: '', current: true }];
  }
  return [
    { kind: 'BOQ', id: 'doc1', number: 'BOQ26219-001', status: 'Issued', url: 'boq-editor.html?id=doc1', current: kind === 'boq' },
    { kind: 'Quotation', id: 'doc1', number: 'Qt26219-002', status: 'Issued', url: 'quotation-editor.html?id=doc1', current: kind === 'quotation' },
    ...['dn3', 'dn2', 'doc1'].map((d) => ({ kind: 'DeliveryNote', id: d, number: DN[d].deliveryNoteNumber, status: DN[d].status, url: `delivery-note-editor.html?id=${d}`, current: kind === 'deliveryNote' && id === d })),
    ...['doc1', 'i7'].map((i) => ({ kind: 'Invoice', id: i, number: INV[i].invoiceNumber, status: INV[i].status, url: `invoice-editor.html?id=${i}`, current: kind === 'invoice' && id === i })),
  ];
}
const ok = { ok: true, error: null };
const projectEntry = (p) => {
  const counts = (map) => Object.values(map).filter((x) => x._projectId === p.id && x.status !== 'Cancelled').length;
  return { id: p.id, projectNumber: p.projectNumber, name: p.name, clientId: p.clientId, siteId: p.siteId, status: p.status, createdAt: p.createdAt, clientName: CLIENT[p.clientId].companyName,
    siteName: SITE[p.siteId].name, createdBy: p.createdBy, lastEditedBy: p.lastEditedBy, boqCount: counts(BOQ_SUMMARY), quotationCount: QUOTES.filter((x) => x.project.id === p.id && x.q.status !== 'Cancelled').length,
    invoiceCount: counts(INV_SUMMARY), deliveryNoteCount: counts(DN_SUMMARY), lastActivityAt: LAST_ACTIVITY[p.id] || null, jobType: p.jobType };
};

// ================================================================= routes
module.exports = { routes: {
  // ---- shared chrome (every page)
  'users:profiles': USER_PROFILES,
  'users:page': USER_PAGE,
  'team:status': TEAM_STATUS,
  'chat:page': CHAT_PAGE,
  'chat:messages': (p) => ({ messages: chatMsgs(p.conversation || 'everyone'), typing: p.conversation === 'everyone' ? ['Harry'] : [] }),
  'announcements:page': ANNOUNCEMENTS_PAGE,
  'signatures:page': SIGNATURES_PAGE,
  'documents:authors': (p) => DOC_AUTHORS[`${p.kind}:${p.id}`] || authors('William', 'Irene', '2026-10-13T15:00:00Z'),
  'documents:chain': (p) => chain(p.kind, p.id),
  'ui:releaseFrame': ok,
  'ui:holdFrame': ok,

  // ---- dashboard, clients, sites
  'dashboard:summary': DASHBOARD,
  'clients:list': CLIENTS,
  'sites:list': SITES,
  'clients:detail': (p) => ({ projects: PROJECTS.filter((x) => x.clientId === p.id).map(projectEntry), documents: ALL_DOC_ROWS.filter((d) => PROJECTS.some((x) => x.clientId === p.id && x.projectNumber === d.projectNumber)) }),
  'sites:detail': (p) => ({ projects: PROJECTS.filter((x) => x.siteId === p.id).map(projectEntry), documents: ALL_DOC_ROWS.filter((d) => PROJECTS.some((x) => x.siteId === p.id && x.projectNumber === d.projectNumber)) }),
  'search:query': () => [],

  // ---- projects
  'projects:list': () => PROJECTS.map(projectEntry),
  // Projects › Overview: each project's documents in columns, joined to what they came from.
  'projects:overview': () => [
    { projectId: 'p26219', notes: { a: 'Zones A–C, roof perimeter' },
      boqs: [{ id: 'b1', number: 'BOQ26219-001', status: 'Issued', subProject: 'a', mark: 'issued' }],
      quotations: [{ id: 'q1', number: 'Qt26219-002', status: 'Issued', subProject: 'a', mark: 'chopped', from: [{ id: 'b1', linked: true }] },
        { id: 'q2', number: 'Qt26219-002-s1', status: 'Draft', from: [{ id: 'q1', linked: true }] },
        { id: 'q3', number: 'Qt26219-003', status: 'Issued', mark: 'client', from: [{ id: 'b1', linked: false }] }],
      deliveryNotes: [{ id: 'd1', number: 'DN26219-001', status: 'Issued', from: [{ id: 'q1', linked: true }] }, { id: 'd2', number: 'DN26219-002', status: 'Issued', from: [{ id: 'q1', linked: true }] }],
      invoices: [{ id: 'i1', number: 'Inv26219-001', status: 'PartiallyPaid', from: [{ id: 'd1', linked: true }] }] },
    { projectId: 'p26221', boqs: [{ id: 'b2', number: 'BOQ26221-001', status: 'Issued' }],
      quotations: [{ id: 'q4', number: 'Qt26221-001', status: 'Issued', mark: 'issued', from: [{ id: 'b2', linked: true }] }], deliveryNotes: [], invoices: [] },
  ],
  'projects:proposeNumber': '26228',
  'projects:get': (p) => { const x = PROJECT_BY_NUMBER[p.projectNumber]; if (!x) return null;
    return { id: x.id, projectNumber: x.projectNumber, name: x.name, status: x.status, projectDescription: x.projectDescription, startDate: x.startDate, expectedCompletionDate: x.expectedCompletionDate,
      projectManager: x.projectManager, internalNotes: x.internalNotes, createdAt: x.createdAt, client: CLIENT[x.clientId], site: SITE[x.siteId], jobType: x.jobType }; },
  'boq:listForProject': (p) => forProject(BOQ_SUMMARY, pidOf(p)),
  'quotations:listForProject': (p) => QUOTES.filter((x) => x.project.id === pidOf(p)).map((x) => x.summary),
  'invoices:listForProject': (p) => forProject(INV_SUMMARY, pidOf(p)),
  'deliveryNotes:listForProject': (p) => forProject(DN_SUMMARY, pidOf(p)),
  'letters:list': (p) => LETTERS.filter((x) => !p.projectId || x.letter.projectId === p.projectId).map(letterSummary),
  'drawings:listForProject': (p) => (pidOf(p) === 'p26219' ? DRAWINGS : []),
  'drawings:listForDocument': (p) => DRAWINGS.filter((d) => d.linkedId === p.linkedId),
  'documents:listForProject': (p) => (pidOf(p) === 'p26219' ? PROJECT_DOCS : []),
  'inspections:list': (p) => INSPECTIONS.filter((x) => x.projectId === pidOf(p)),
  'inspections:due': INSPECTIONS_DUE,
  'activity:listForProject': (p) => ACTIVITY.filter((a) => a._pid === pidOf(p)).map(activityRow),

  // ---- editors
  'boq:get': (p) => BOQ[p.id] || null,
  'quotations:get': (p) => (QUOTE[p.id] ? QUOTE[p.id].detail : null),
  // Paragraphs added in a document's preview (js/doc-preview.js › Edit).
  'docEdits:get': () => ({ ok: true, anchors: [
    { key: 'intro', label: 'Opening', text: 'We thank you for your inquiry related to the item above, the following is our quotation on the job.' },
    { key: 'row:600mm base jack', label: 'Item 1', text: '600mm Base Jack' },
    { key: 'row:timber sole board', label: 'Item 2', text: 'Timber Sole Board' },
    { key: 'table-end', label: 'After the table', text: '' },
    { key: 'para:payment : first two month', label: 'Terms and Conditions', text: 'Payment : First two month\'s rental and delivery charges in advance, thereafter monthly.' },
    { key: 'end', label: 'End, before the signatures', text: '' },
  ], inserts: [{ id: 'p1', anchor: 'row:timber sole board', after: true, text: 'Sole boards are supplied in 3m lengths and cut on site.' }] }),
  'docEdits:save': { ok: true },
  'docEdits:spots': () => ({ ok: true, pageWidth: 595.28, spots: [
    { key: 'intro', page: 0, top: 268 }, { key: 'row:600mm base jack', page: 0, top: 330 }, { key: 'row:timber sole board', page: 0, top: 372 },
    { insert: 'p1', page: 0, top: 396 }, { key: 'para:payment : first two month', page: 0, top: 520 },
  ] }),
  'quotations:deliverySchedule': (p) => (p.id === 'doc1' ? { days: [
    { id: 'dd1', quotationId: 'doc1', day: 1, date: '2026-09-10', time: '20:00', sent: true, note: 'Base items and standards', internalNote: '9-tonne lorry x1', quantities: { doc1_l1: 48, doc1_l2: 48, doc1_l3: 72 }, createdAt: at('2026-09-05'), updatedAt: at('2026-09-10') },
    { id: 'dd2', quotationId: 'doc1', day: 2, date: '2026-09-22', time: '20:00', sent: true, note: 'Ledgers and braces', internalNote: null, quantities: { doc1_l5: 144, doc1_l6: 96, doc1_l7: 36 }, createdAt: at('2026-09-05'), updatedAt: at('2026-09-22') },
    { id: 'dd3', quotationId: 'doc1', day: 3, date: '2026-10-15', time: '20:00', sent: false, note: 'Steel decks and toe boards', internalNote: 'Call Sam 30 min before', quantities: { doc1_l8: 72, doc1_l9: 32 }, createdAt: at('2026-09-05'), updatedAt: at(TODAY) },
  ], weights: Object.fromEntries(QUOTE.doc1.q.lines.filter((l) => l._weight != null).map((l) => [l.id, l._weight])) } : { days: [], weights: {} }),
  'invoices:get': (p) => INV[p.id] || null,
  'deliveryNotes:get': (p) => DN[p.id] || null,
  'letters:get': (p) => { const x = LETTER[p.id]; return x ? { letter: x.letter, projectNumber: x.p ? x.p.projectNumber : null, projectName: x.p ? x.p.name : null, openingHTML: openingHTML(x.letter) } : null; },
  'letters:letterhead': { png: null, paperSize: 'A4' },
  'boq:standardRates': MANPOWER_RATES,

  // ---- material list
  'priceLists:list': PRICE_LISTS,
  'priceListItems:search': (p) => { const q = (p.query || '').toLowerCase();
    return ALL_ITEMS.filter((x) => (!p.sourceKey || x.sourceKey === p.sourceKey) && (!p.category || x.category === p.category) && (!q || x.itemName.toLowerCase().includes(q) || x.itemCode.includes(q))); },
  'priceLists:syncStatus': { mode: 'team', folder: TEAM_STATUS.folderDisplay, otherMacs: 4 },

  // ---- tasks & calendar
  'tasks:list': (p) => TASKS.filter((t) => !p.projectId || t.task.projectId === p.projectId),
  'tasks:people': PEOPLE,
  'tasks:teams': { me: ME, teams: TEAMS },
  'calendar:events': (p) => CALENDAR.filter((e) => (!p.from || e.date >= p.from) && (!p.to || e.date <= p.to)),

  // ---- stock, accounts, admin, workers
  'stock:data': STOCK,
  'accounts:data': ACCOUNTS,
  'employees:list': EMPLOYEES,
  'workers:list': WORKERS,
  'workers:roster': ROSTER,
  'workerAgreements:get': (p) => {
    const e = ROSTER.find((r) => r.worker.id === p.workerId) || ROSTER[0];
    const w = e.worker;
    const agreement = e.stage === 0 ? null : { id: `wa_${w.id}`, workerId: w.id, agreementDate: w.startDate, startDate: w.startDate, position: w.position, dailyWage: w.dailyWage,
      hoursFrom: '08:00', hoursTo: '18:00', payDay: 7, noticeDays: 7, signatory: e.signedBy || 'William',
      employerSignedBy: e.stage >= 2 ? e.signedBy : null, employerSignedAt: e.stage >= 2 ? at(addDays(w.startDate, 1)) : null,
      employerSignedPath: e.stage >= 2 ? `/Users/william/Documents/ScaffoldPro/Administration/Workers/${w.workerNumber}/Contracts/${e.agreementNumber} - Signed by Employer.pdf` : null,
      signedCopyPath: e.stage >= 3 ? `/Users/william/Documents/ScaffoldPro/Administration/Workers/${w.workerNumber}/Contracts/${e.agreementNumber} - Signed.pdf` : null,
      signedCopyAt: e.stage >= 3 ? at(addDays(w.startDate, 2)) : null, createdAt: at(w.startDate), updatedAt: at(addDays(w.startDate, 2)) };
    return { agreement, number: e.agreementNumber, signers: ['William', 'Irene'], me: ME, canSign: true, hasSignature: true, employerSignedExists: e.stage >= 2, signedCopyExists: e.stage >= 3,
      missing: w.idNumber ? [] : ['the worker’s ID card number'], fullNames: { William: PERSON.William.fullName, Irene: PERSON.Irene.fullName } };
  },
  'workerDocuments:list': (p) => {
    const e = ROSTER.find((r) => r.worker.id === p.workerId) || ROSTER[0];
    return [
      { id: `${e.worker.id}_d1`, originalName: 'HKID copy.jpg', storedFilename: 'HKID copy.jpg', category: 'Identification', fileType: 'jpg', fileSizeBytes: 412330, description: null, expiryDate: null, uploadedAt: at(e.worker.startDate), fileExists: true },
      { id: `${e.worker.id}_d2`, originalName: 'Construction Workers Registration card.jpg', storedFilename: 'CWR card.jpg', category: 'Certification', fileType: 'jpg', fileSizeBytes: 388120, description: 'Green card', expiryDate: e.expiring ? '2026-10-18' : '2028-05-31', uploadedAt: at(e.worker.startDate), fileExists: true },
      { id: `${e.worker.id}_d3`, originalName: 'Metal scaffolding training certificate.pdf', storedFilename: 'Scaffolding cert.pdf', category: 'Training Certificate', fileType: 'pdf', fileSizeBytes: 230554, description: 'CIC Advanced Metal Scaffolding', expiryDate: null, uploadedAt: at(e.worker.startDate), fileExists: true },
    ].slice(0, Math.max(1, e.documents));
  },
  'adminDocuments:expiring': EXPIRING,
  'adminDocuments:list': [
    { id: 'ad1', originalName: 'Contractor’s All Risks policy 2025-26.pdf', storedFilename: 'CAR 2025-26.pdf', category: 'Insurance', fileType: 'pdf', fileSizeBytes: 1203344, description: 'AXA policy CAR-118822', expiryDate: '2026-10-31', uploadedAt: at('2025-11-01'), fileExists: true },
    { id: 'ad2', originalName: 'Business Registration Certificate.pdf', storedFilename: 'BR 2025-26.pdf', category: 'Licenses', fileType: 'pdf', fileSizeBytes: 220344, description: null, expiryDate: '2026-10-10', uploadedAt: at('2025-10-12'), fileExists: true },
  ],
  'costs:manpower': { rates: MANPOWER_RATES, providers: SETTINGS.manpowerProviders },

  // ---- team
  'team:page': TEAM_PAGE,

  // ---- marketing
  'marketing:summary': MARKETING,
  'marketing:leads': LEADS,
  'marketing:clientReport': (p) => ({
    currency: 'HKD', clientName: 'Gammon Construction Limited', from: '2026-01-01', to: '2026-12-31', total: 412600, wonCount: 2, wonValue: 284300,
    rows: [
      { id: 'q1', number: 'Qt26219-001', date: '2026-03-02', projectNumber: '26219', projectName: 'Kai Tak Sports Park', subject: 'Main Stadium Roof Access', value: 196500, won: true, pricingMode: 'rental' },
      { id: 'q2', number: 'Qt26219-003', date: '2026-10-13', projectNumber: '26219', projectName: 'Kai Tak Sports Park', subject: 'Zone B truss-out', value: 69683, won: false, pricingMode: 'rental' },
      { id: 'q3', number: 'Qt26214-002', date: '2026-06-18', projectNumber: '26214', projectName: 'Kai Tak Cruise Terminal', subject: 'Façade access', value: 146417, won: true, pricingMode: 'sale' },
    ],
  }),
  'promotions:list': [{ id: 'pr1', name: 'Q4 boom-lift hire mailer', channel: 'Letter', status: 'Running', goal: 'Three new boom-lift hires before Christmas', subject: 'Boom-lift hire for your sites',
    bodyHTML: '<p>Dear {Contact},</p><p>…</p>', createdAt: '2026-09-20T09:00:00Z', updatedAt: '2026-10-10T09:00:00Z', targets: [
      { id: 'pt1', kind: 'Lead', refId: 'ld3', name: 'Build King Holdings', contact: 'Mr. Gary Mok', address: null, status: 'Sent', letterId: null, lastAt: '2026-10-02T09:00:00Z', note: null },
      { id: 'pt2', kind: 'Client', refId: 'c6', name: CLIENT.c6.companyName, contact: 'Ms. Vivian Ng', address: null, status: 'Replied', letterId: 'l3', lastAt: '2026-10-08T09:00:00Z', note: 'Interested for Q1' },
    ] }],

  // ---- settings
  'settings:get': SETTINGS,
  'settings:numberPreview': (p) => ({ example: { BOQ: 'BOQ26228-001', QT: 'Qt26228-001', INV: 'Inv26228-001', DN: 'DN26228-001', LETTER: 'L26228-001' }[p.type] || 'Qt26228-001' }),
  'settings:logoPreview': null,
  'app:updates': { automatic: true, hasToken: false },
  'app:changelog': [
    { batch: 312, title: 'Calmer calendar week', text: '- The week view keeps its place when you add an event.\n- Times line up across days.' },
    { batch: 311, title: 'Stock returns', text: '- Signed delivery notes ask whether their items are back.' },
    { batch: 310, title: 'Boom-lift quotations', text: '- A Model column for crane and boom-lift quotations.' },
  ],
  'web:status': { enabled: true, running: true, port: 8443, hasPassword: true, urls: ['https://192.168.1.20:8443', 'https://williams-macbook-pro.local:8443'],
    sessions: [{ token: 'tk1', name: 'Harry', agent: 'Safari on iPhone', createdAt: '2026-10-13T00:40:00Z', lastSeen: '2026-10-14T00:50:00Z' }], error: null },
  'sheets:status': { linked: true, url: 'https://script.google.com/macros/s/AKfycbx/exec', sheetName: 'ScaffoldPro Overview', sheetURL: 'https://docs.google.com/spreadsheets/d/1abc/edit',
    lastSyncAt: '2026-10-14T01:58:00Z', lastError: null, lastTakenIn: 1, lastTakenInAt: '2026-10-13T08:00:00Z', sheetLayout: '7', running: false },
  'ai:status': { provider: 'gemini', model: '', defaultModel: 'gemini-2.5-flash', hasKey: true },
  'cloudBackup:status': { enabled: true, folder: "/Users/william/Library/Mobile Documents/com~apple~CloudDocs/Proficiency/William's Work", folderDisplay: "iCloud Drive › Proficiency › William's Work",
    usingDefault: true, lastBackupAt: '2026-10-14T01:45:00Z', lastFilesCopied: 12, lastError: null, running: false },
  'backup:autoStatus': { lastAt: '2026-10-14T00:00:00Z', lastError: null, running: false, local: { active: true, folder: '/Users/william/Documents/ScaffoldPro', lastAt: '2026-10-14T01:50:00Z', lastCopied: 4, waiting: 0, lastError: null, running: false } },
  'backup:list': BACKUPS,
  'backup:locations': { documentsFolder: '/Users/william/Documents/ScaffoldPro', backupsFolder: '/Users/william/Documents/ScaffoldPro/Backups', databaseFolder: '/Users/william/Library/Application Support/ScaffoldPro/team-data' },
} };

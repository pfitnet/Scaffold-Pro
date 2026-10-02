# BQ sheet ("PROFICIENCY QUOTATION") check without a Mac.
#
# A Python copy of BQSheet.layout and BQSheetRenderer in main.swift. It
# rebuilds the company's sample BQ (CRBC 1635 - 80m Concrete Wall, in
# docs/reference) and compares it with the original, pixel by pixel. It also
# builds the Word copy with js/docx-export.js and renders it with
# LibreOffice.
#
# The app prints only the landscape sheet; a portrait BOQ goes on the
# letterhead (docs.py's "boq"). The portrait sheet here is kept for reference.
#
#   pip install pillow pymupdf
#   python3 sheet.py [path/to/original.pdf] [calibri.ttf] [arial-bold.ttf]
#
# With no fonts given it uses the app's Carlito (Calibri's metrics) and
# Liberation Sans Bold (Arial's metrics).
import json, os, re, subprocess, sys
from PIL import Image, ImageDraw, ImageFont, ImageChops
from terms import formatted, LABEL_INDENT

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out'); os.makedirs(OUT, exist_ok=True)
APP = os.path.join(HERE, '..', '..', 'ScaffoldPro-native')
DPI = 200; S = DPI / 72

# "python3 sheet.py law <Mr. Law sheet.pdf>" checks the sheet with amounts
# added after the subtotal and a Notes box instead.
LAW_MODE = len(sys.argv) > 1 and sys.argv[1] == 'law'
# "python3 sheet.py law --sign <pdf>" adds the signature block, as on the original.
SIGN = '--sign' in sys.argv
if SIGN: sys.argv.remove('--sign')
# "python3 sheet.py quote long": every sample item, so the sheet has to shrink onto one page.
QUOTE_LONG = 'long' in sys.argv
if QUOTE_LONG: sys.argv.remove('long')
ARGS = sys.argv[2:] if LAW_MODE else sys.argv[1:]
ORIGINAL = ARGS[0] if len(ARGS) > 0 else os.path.join(HERE, '..', '..', 'docs', 'reference', 'BQ-CRBC-1635.pdf')
BODY_TTF = ARGS[1] if len(ARGS) > 1 else os.path.join(APP, 'resources', 'fonts', 'Carlito-Regular.ttf')
TITLE_TTF = ARGS[2] if len(ARGS) > 2 else '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf'

def kg(v): return f'{v:.1f} kg'
def money(v): return f'{v:,.2f}'
def qty(v): return f'{round(v):,}'

def layout(landscape, pricing, currency, info, lines, rates=None, charges=None, notes=None, terms=None, signature=None, extra=(), one_page=False):
    pw, ph = (842.88, 595.92) if landscape else (595.92, 842.88)
    left, top = 85.875, 53.625
    widths = [68.25, 174.75, 43.5, 51.75, 130.5, 128.25, 72.0] if landscape else [68.25, 186.54, 43.5, 51.75, 72.0]
    edges = [left]
    for w in widths: edges.append(edges[-1] + w)
    right = edges[-1]
    ie = [left, 154.125, 424.125, 492.375, right] if landscape else [left, 154.125, 263.625, 331.875, right]
    cell = lambda x0, x1, t, size, align, up, font='body': dict(x0=x0, x1=x1, text=t, font=font, size=size, align=align, baselineUp=up)
    rows = [dict(kind='banner', height=27.75, fill='ED7D31', repeats=True, cells=[cell(left, right, 'PROFICIENCY QUOTATION', 19.99, 'center', 6.375, 'title')])]
    for a, b, c, d in list(extra) + [('Project Code  :', info[0], 'Job Site          :', info[2]), ('Client             :', info[1], 'Structure        :', info[3])]:
        rows.append(dict(kind='info', height=15.75, fill='FDF9DF', repeats=True, cells=[
            cell(ie[0], ie[1], a, 10, 'left', 4.125), cell(ie[1], ie[2], b, 10, 'left', 4.125),
            cell(ie[2], ie[3], c, 10, 'left', 4.125), cell(ie[3], ie[4], d, 10, 'left', 4.125)]))
    word = 'Sale Price' if pricing == 'Sale' else 'Rental Rate'
    titles = (['No.', 'Item Name', 'Weight', 'Quantity', f'Unit {word} ({currency})', f'Total {word} ({currency})', 'Total Weight'] if landscape
              else ['No.', 'Item Name', 'Weight', 'Quantity', 'Total Weight'])
    rows.append(dict(kind='header', height=19.5, fill='B4C6E7', repeats=True, cells=[cell(edges[i], edges[i + 1], t, 13, 'center', 4.875) for i, t in enumerate(titles)]))
    total_money = 0; total_kg = 0
    for i, (name, w, q, price) in enumerate(lines):
        amount = round(q * price + 1e-9, 2); total_money += amount; total_kg += round(w * q, 2)
        texts = [(str(i + 1), 'center'), (name, 'left'), (kg(w), 'right'), (qty(q), 'center')]
        if landscape: texts += [(money(price), 'money'), (money(amount), 'money')]
        texts.append((kg(w * q), 'right'))
        rows.append(dict(kind='item', height=18, fill=None, repeats=False, cells=[cell(edges[j], edges[j + 1], t, 12, a, 4.875) for j, (t, a) in enumerate(texts)]))
    n = len(widths)
    if landscape:
        label = 'Subtotal Amount :' if charges else 'Subtotal :' if rates else 'Total Amount :'
        totals = [cell(edges[0], edges[n - 2], label, 28.99, 'center', 8.625), cell(edges[n - 2], edges[n - 1], money(total_money), 12, 'money', 15.375)]
    else:
        totals = [cell(edges[0], edges[n - 1], 'Total Weight :', 28.99, 'center', 8.625)]
    totals.append(cell(edges[n - 1], edges[n], kg(total_kg), 12, 'right', 15.375))
    rows.append(dict(kind='total', height=38.25, fill=None, repeats=False, cells=totals))
    if landscape and charges:
        grand = total_money
        for i, (code, nm, amount) in enumerate(charges):
            grand += amount
            rows.append(dict(kind='charge', height=18.75, fill=None, repeats=False, cells=[
                cell(edges[0], edges[1], code or f'D{i + 1}', 12, 'left', 5.625), cell(edges[1], edges[n - 2], nm, 12, 'left', 5.625),
                cell(edges[n - 2], edges[n - 1], money(amount), 12, 'money', 5.625), cell(edges[n - 1], edges[n], 'N/a', 12, 'center', 5.625)]))
        rows.append(dict(kind='grandTotal', height=45.75, fill=None, repeats=False, cells=[
            cell(edges[0], edges[n - 2], 'Total Amount', 28.99, 'center', 12.375),
            cell(edges[n - 2], edges[n - 1], money(grand), 12, 'money', 19.125), cell(edges[n - 1], edges[n], '', 12, 'right', 19.125)]))
    if landscape and rates:
        title, items, note = rates
        rows.append(dict(kind='ratesTitle', height=19.5, fill='B4C6E7', repeats=False, cells=[cell(left, right, title, 13, 'center', 4.875)]))
        for i, (nm, rate, unit) in enumerate(items):
            texts = [(f'R{i + 1}', 'center'), (nm, 'left'), ('', 'right'), ('', 'center'), (f'{money(rate)} / {unit}', 'money'), ('(Rate Only)', 'center'), ('', 'right')]
            rows.append(dict(kind='rate', height=18, fill=None, repeats=False, cells=[cell(edges[j], edges[j + 1], t, 12, a, 4.875) for j, (t, a) in enumerate(texts)]))
        if note: rows.append(dict(kind='note', height=15.75, fill=None, repeats=False, cells=[cell(left, right, note, 10, 'left', 4.125)]))
    def text_box(text, heading, kind):
        body = dict(font='body', size=12)
        lines = wrap(text, right - left - 2 * 2.625, font(body))
        if not lines[0].lower().startswith(heading.lower()[:4]): lines.insert(0, f'{heading}:')
        for i, t in enumerate(lines):
            first, last = i == 0, i == len(lines) - 1
            c = cell(left, right, t, 12, 'left', 12.375 if last else 3.375)
            m = re.search(r'(?i)\b(?:https?://)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?:/[^\s]*)?', t)
            c['link'] = m.group(0) if m else None
            rows.append(dict(kind=kind, height=14.25 + (9 if first else 0) + (9 if last else 0), fill=None, repeats=False,
                             cells=[c], joinNext=not last))
    if landscape and notes: text_box(notes, 'Notes', 'notes')
    if landscape and terms: rows.extend(terms_box(terms, left, right))
    # The signature block under the table (company, name, title, client), as on Mr. Law's sheet.
    if landscape and signature:
        company, name, title, client = signature
        le, rs, re_ = edges[2], ie[2], edges[n - 1]
        texts = [('For and On Behalf of', 'Accepted By', 36, 4.125, False), ('', '', 48, 0, True),
                 (company, client, 20.25, 4.125, False), (name, 'Date :', 15.75, 4.125, False), (title, '', 15.75, 4.125, False)]
        for i, (a, b, h, up, line) in enumerate(texts):
            ca = cell(left, le, a, 10, 'left', up); cb = cell(rs, re_, b, 10, 'left', up)
            ca['lineBelow'] = cb['lineBelow'] = line
            rows.append(dict(kind='signature', height=h, fill=None, repeats=False, joinNext=i < len(texts) - 1, borderless=True,
                             cells=[ca, cell(le, rs, '', 10, 'left', 0), cb, cell(re_, right, '', 10, 'left', 0)]))
    return fit(dict(ok=True, kind='sheet', landscape=landscape, pageWidth=pw, pageHeight=ph, left=left, right=right, top=top,
                    bottomLimit=ph - 53.25, rows=rows, number='BQ', title='PROFICIENCY QUOTATION', scale=1), 0 if one_page else 0.7)

def terms_box(text, left, right):
    """BQSheet.termsBox: the terms with their markers and indents, as on the portrait quotation."""
    pad = 2.625; width = right - left - 2 * pad; f = font(dict(font='body', size=12))
    lines = []  # (marker, marker x, text, text x, colon, gap)
    def hanging(marker, texts, l, indent, colon, gap):
        mw = wid(marker, f) if marker else 0
        tx = indent if indent is not None else l + max(18, mw + 6)
        if marker: tx = max(tx, l + mw + (7.5 if colon else 5))
        tx = min(tx, width - 120)
        pieces = [p for t in texts for p in wrap(t, width - tx, f)] or ['']
        for i, piece in enumerate(pieces):
            lines.append((marker if i == 0 and marker else None, l, piece, tx, i == 0 and colon, gap if i == 0 else 0))
    body = text.replace('\r\n', '\n').strip().split('\n')
    heading = 'Terms & Conditions:'
    first = body[0].strip()
    if first.lower().startswith('term') and (first.endswith(':') or first.lower() in ('terms & conditions', 'terms and conditions')):
        heading = first; body = body[1:]
    lines.append((None, 0, heading, 0, False, 0))
    previous = None
    for p in formatted('\n'.join(body)):
        is_text = p[0] == 'text'
        gap = 0 if previous is None or (not is_text and previous is False) else 6
        if is_text:
            for i, t in enumerate(wrap(p[1], width, f)): lines.append((None, 0, t, 0, False, gap if i == 0 else 0))
        else:
            _, marker, texts, l, indent, colon = p
            hanging(marker, texts, l, indent, colon, gap)
        previous = is_text
    rows = []
    for i, (marker, mx, t, tx, colon, gap) in enumerate(lines):
        first, last = i == 0, i == len(lines) - 1
        c = dict(x0=left, x1=right, text=t, font='body', size=12, align='left', baselineUp=12.375 if last else 3.375)
        m = re.search(r'(?i)\b(?:https?://)?(?:[a-z0-9-]+\.)+[a-z]{2,}(?:/[^\s]*)?', t)
        c['link'] = m.group(0) if m else None
        if tx > 0 or marker:
            c.update(textX=left + pad + tx, marker=marker, markerX=left + pad + mx, colon=colon)
        rows.append(dict(kind='terms', height=14.25 + gap + (9 if first else 0) + (9 if last else 0), fill=None, repeats=False,
                         cells=[c], joinNext=not last))
    return rows

def fit(L, smallest=0.7):
    """BQSheet.fitToPage: shrink a sheet a little too long for one page onto it (to no less than `smallest`)."""
    h = sum(r['height'] for r in L['rows']); room = L['bottomLimit'] - L['top']
    if h <= room or room / h < smallest: return L
    k = (room - 3) / h; cx = (L['left'] + L['right']) / 2; x = lambda v: cx + (v - cx) * k
    L.update(scale=k, left=x(L['left']), right=x(L['right']))
    for r in L['rows']:
        r['height'] *= k
        for c in r['cells']:
            c.update(x0=x(c['x0']), x1=x(c['x1']), size=c['size'] * k, baselineUp=c['baselineUp'] * k)
            if c.get('textX') is not None: c.update(textX=x(c['textX']), markerX=x(c['markerX']))
    return L

_fonts = {}
def font(c, size=None):
    key = (c['font'], size or c['size'])
    if key not in _fonts: _fonts[key] = ImageFont.truetype(TITLE_TTF if c['font'] == 'title' else BODY_TTF, key[1] * S)
    return _fonts[key]
def wid(t, f): return f.getlength(t) / S

def wrap(text, width, f):
    out = []
    for para in text.split('\n'):
        cur = ''
        for w in para.split(' '):
            cand = w if not cur else f'{cur} {w}'
            if wid(cand, f) <= width or not cur: cur = cand
            else: out.append(cur); cur = w
        out.append(cur)
    return out

def render(L):
    img = Image.new('RGB', (round(L['pageWidth'] * S), round(L['pageHeight'] * S)), 'white'); d = ImageDraw.Draw(img)
    # (At least a pixel, for the thin rules of a sheet shrunk a long way.)
    def rect(x, y, w, h, col): d.rectangle([x * S, y * S, max(x * S, (x + w) * S - 1), max(y * S, (y + h) * S - 1)], fill=col)
    k = L.get('scale', 1); half = 0.375 * k; y = L['top']
    for r in L['rows']:
        if r['fill']: rect(L['left'] - half, y - half, L['right'] - L['left'] + 2 * half, r['height'] + 2 * half, '#' + r['fill'])
        y += r['height']
    y = L['top']; rect(L['left'] - half, y - half, L['right'] - L['left'] + 2 * half, 2 * half, 'black'); bottom = y
    for r in L['rows']:
        if r.get('borderless'):
            # The signature block: only its lines to sign on.
            for c in r['cells']:
                if c.get('lineBelow'): rect(c['x0'] - half, y + r['height'] - half, c['x1'] - c['x0'] + 2 * half, 2 * half, 'black')
            y += r['height']; continue
        for c in r['cells']:
            if c['x0'] > L['left'] + 0.01: rect(c['x0'] - half, y - half, 2 * half, r['height'] + 2 * half, 'black')
        y += r['height']; bottom = y
        if not r.get('joinNext'): rect(L['left'] - half, y - half, L['right'] - L['left'] + 2 * half, 2 * half, 'black')
    rect(L['left'] - half, L['top'] - half, 2 * half, bottom - L['top'] + 2 * half, 'black'); rect(L['right'] - half, L['top'] - half, 2 * half, bottom - L['top'] + 2 * half, 'black')
    y = L['top']
    for r in L['rows']:
        bottom = y + r['height']
        for c in r['cells']:
            pad = 2.625 * k; base = bottom - c['baselineUp']
            if c.get('marker'): d.text((c['markerX'] * S, base * S), c['marker'], font=font(c), fill='black', anchor='ls')
            if c.get('colon'): d.text(((c['textX'] - 3.75 * k) * S, base * S), ':', font=font(c), fill='black', anchor='ls')
            if not c['text']: continue
            f = font(c); space = wid(' ', f); start = c['textX'] if c.get('textX') is not None else c['x0'] + pad
            room = c['x1'] - pad - start - (space if c['align'] in ('right', 'money') else 0)
            if wid(c['text'], f) > room: f = font(c, max(c['size'] * room / wid(c['text'], f), c['size'] * 0.6))
            w = wid(c['text'], f)
            put = lambda t, x: d.text((x * S, base * S), t, font=f, fill='black', anchor='ls')
            if c['align'] == 'center': put(c['text'], (c['x0'] + c['x1']) / 2 - w / 2)
            elif c['align'] == 'right': put(c['text'], c['x1'] - pad - space - w)
            elif c['align'] == 'money': put('$', c['x0'] + pad); put(c['text'], c['x1'] - pad - space - w)
            elif c.get('link') and c['link'] in c['text']:
                x = start; pre, post = c['text'].split(c['link'], 1)
                put(pre, x); lx = x + wid(pre, f)
                d.text((lx * S, base * S), c['link'], font=f, fill='#1155CC', anchor='ls')
                rect(lx, base + 1.125 * k - half, wid(c['link'], f), 2 * half, '#1155CC')
                put(post, lx + wid(c['link'], f))
            else: put(c['text'], start)
        y = bottom
    return img

# The sample sheet's items: name, weight (kg), quantity, unit rate (HKD).
SAMPLE = [('600mm Base Jack', 3.8, 220, 4.20), ('235 Base Collar', 1.7, 220, 2.50), ('2.0m standard without spigot', 9.8, 616, 11.30),
          ('0.73m Ledger', 2.9, 501, 4.50), ('1.40m Ledger', 5.5, 80, 11.853625), ('2.07m Ledger', 6.9, 1358, 8.50), ('2.57m Ledger', 8.4, 120, 9.90),
          ('1.40m x 2.0m Face Brace', 7.9, 22, 16.6677), ('0.73m x 0.32m Steel Deck', 5.9, 48, 10.30), ('2.07m x 0.32m Steel Deck', 13.5, 438, 17.10),
          ('2.57m x 0.32m Steel Deck', 16.2, 36, 19.40), ('0.73m Toe Board', 2.7, 66, 4.20), ('1.40m Steel Toe Board', 4.1, 12, 7.675),
          ('2.07m Toe Board', 6.7, 438, 7.30), ('2.57m Toe Board', 8.1, 36, 8.40), ('2.57m Aluminumn Staircase', 27.8, 8, 140.00),
          ('2.57m Outer Guard Rail', 18.2, 8, 26.20), ('2.57m Inner Guard Rail', 10.5, 8, 17.20)]
INFO = ('', 'CRBC', '1635 Kwu Tung Station', '80m Working Platform for Concrete Wall')

# The company's sheet for Mr. Law (a sale, with delivery and design fees
# added after the subtotal, and notes).
LAW = [('600mm Base Jack', 3.8, 8, 42.00), ('235 Base Collar', 1.7, 8, 25.00), ('1.0m standard with spigot', 6.5, 8, 90.00),
       ('2.0m standard with spigot', 10.9, 8, 139.00), ('1.40m Ledger', 5.5, 20, 93.096), ('2.57m Ledger', 8.4, 16, 99.00),
       ('3.07m Ledger', 11.4, 6, 104.8667), ('2.57m x 0.32m Steel Deck', 16.2, 4, 194.00), ('3.07m x 0.32m Steel Deck', 21.8, 8, 141.4275),
       ('1.40m Steel Toe Board', 4.1, 4, 105.49), ('2.57m Toe Board', 8.1, 2, 84.00), ('3.07m Steel Toe Board', 8.4, 2, 97.645),
       ('2.57m Aluminumn Staircase', 31.0, 2, 2365.74)]
LAW_NOTES = ('The terms and conditions set out in pfitnet.com/TC are hereby expressivly incorporated into this Quotation\n'
             'Payment: 100% against order confirmation\nDelivery: minimum of 5 days against order confirmation')

def law_check(original):
    """Builds Mr. Law's sheet and compares it with the company's (printed at 76.75%)."""
    import pymupdf
    L = layout(True, 'Sale', 'HKD', ('', 'Mr. Law', '', 'Container Access Platform'), LAW,
               charges=[('', 'Delivery', 1800.0), ('', 'Design Fees', 1000.0)], notes=LAW_NOTES,
               signature=('Proficiency (HK) Limited', 'Richard Kwan', 'Director', 'Mr. Law') if SIGN else None)
    ours = render(L); ours.save(os.path.join(OUT, 'law.png'))
    jp = os.path.join(OUT, 'law.json'); json.dump(L, open(jp, 'w'))
    dp = os.path.join(OUT, 'word_law.docx')
    subprocess.run(['node', '-e', f"require('{APP}/js/docx-export.js'); const fs=require('fs'); fs.writeFileSync('{dp}', buildSheetDocx(JSON.parse(fs.readFileSync('{jp}','utf8'))))"], check=True)
    subprocess.run(['soffice', '--headless', '--convert-to', 'pdf', '--outdir', OUT, dp], check=True, capture_output=True)
    pymupdf.open(dp[:-5] + '.pdf')[0].get_pixmap(dpi=DPI).save(os.path.join(OUT, 'word_law.png'))
    print('scale', L['scale'], '(theirs 0.76753)', 'left', L['left'], '(theirs 163.77)')
    page = pymupdf.open(original)[0]
    page.get_pixmap(dpi=DPI).save(os.path.join(OUT, 'law_original.png'))
    theirs = Image.open(os.path.join(OUT, 'law_original.png')).convert('RGB')
    return ours, theirs

# "python3 sheet.py quote" renders a landscape quotation: its number and
# date, materials, delivery and fees after the subtotal, the terms and the
# signature block (quotationSheetLayout in main.swift).
QUOTE_MODE = len(sys.argv) > 1 and sys.argv[1] == 'quote'
# The three parts are joined with a blank line, as quotationSheetLayout does.
QUOTE_TERMS = ('The terms and conditions set out in www.pfitnet.com/TC are hereby expressively incorporated into this quotation with other relevant key terms set forth below.\n\n'
               "Payment : First month's rental is to be paid upon order confirmation,\n"
               'Extended hire shall be counted on a pro-rata (30-days) basis,\n'
               'starting from its delivery to site until all materials have been returned to the yard.\n'
               "Delivery charges are to be paid within 7 days against each trucks' delivery\n"
               'Delivery : 5-7 Days against order confirmation\n'
               'Insurance: C.A.R. & E.C. insurance is to be paid for by hirer for our workers on-site\n\n'
               'Order shall be confirmed and regarded as properly accepted upon signature by all parties AND such signed copy is returned to Proficiency (HK) Limited via instant electronic communication means. This quotation shall be valid for 7 business days against the issue date.')

if __name__ == '__main__':
    import pymupdf
    if QUOTE_MODE:
        L = layout(True, 'Rental', 'HKD', ('26212 - Batch 3 of Materials - Rental - Lingma', 'Lingma', '1635 Kwu Tung Station', 'Truss-out at 5/F'),
                   SAMPLE + LAW if QUOTE_LONG else LAW[:8], one_page=True,
                   charges=[('M', 'Minimum Hire of 2 Months — rental for the 2nd month', 4638.20),
                            ('D1', 'Delivery of materials (2 – 6 tons) — 2 truck/trip × 3,300.00', 6600.0), ('A1', 'Design Fees: Design and Drawing', 1000.0)],
                   terms=QUOTE_TERMS, signature=('Proficiency (HK) Limited', 'Richard Kwan', 'Director', 'Lingma Const. & Eng. Co. Ltd.'),
                   extra=[('Quotation No. :', 'Qt26212-007', 'Date               :', '02/10/2026')])
        name = 'quote_landscape_long' if QUOTE_LONG else 'quote_landscape'
        render(L).save(os.path.join(OUT, f'{name}.png'))
        jp = os.path.join(OUT, f'{name}.json'); json.dump(L, open(jp, 'w'))
        dp = os.path.join(OUT, f'word_{name}.docx')
        subprocess.run(['node', '-e', f"require('{APP}/js/docx-export.js'); const fs=require('fs'); fs.writeFileSync('{dp}', buildSheetDocx(JSON.parse(fs.readFileSync('{jp}','utf8'))))"], check=True)
        subprocess.run(['soffice', '--headless', '--convert-to', 'pdf', '--outdir', OUT, dp], check=True, capture_output=True)
        pages = pymupdf.open(dp[:-5] + '.pdf')
        pages[0].get_pixmap(dpi=DPI).save(os.path.join(OUT, f'word_{name}.png'))
        print('scale', L.get('scale'), 'word pages', len(pages))
        sys.exit()
    if LAW_MODE:
        ours, theirs = law_check(ORIGINAL)
        diff = ImageChops.difference(ours.convert('L'), theirs.convert('L'))
        print('bbox of strong differences', diff.point(lambda v: 255 if v > 96 else 0).getbbox())
        diff.point(lambda v: 255 - min(255, v * 3)).save(os.path.join(OUT, 'law_diff.png'))
        sys.exit()
    for landscape in (True, False):
        L = layout(landscape, 'Rental', 'HKD', INFO, SAMPLE)
        name = 'sheet_landscape' if landscape else 'sheet_portrait'
        render(L).save(os.path.join(OUT, f'{name}.png'))
        jp = os.path.join(OUT, f'{name}.json'); json.dump(L, open(jp, 'w'))
        dp = os.path.join(OUT, f'word_{name}.docx')
        subprocess.run(['node', '-e', f"require('{APP}/js/docx-export.js'); const fs=require('fs'); fs.writeFileSync('{dp}', buildSheetDocx(JSON.parse(fs.readFileSync('{jp}','utf8'))))"], check=True)
        subprocess.run(['soffice', '--headless', '--convert-to', 'pdf', '--outdir', OUT, dp], check=True, capture_output=True)
        for i, page in enumerate(pymupdf.open(dp[:-5] + '.pdf')):
            page.get_pixmap(dpi=DPI).save(os.path.join(OUT, f'word_{name}_{i + 1}.png'))
        print(name, 'ok')
    if os.path.exists(ORIGINAL):
        pymupdf.open(ORIGINAL)[0].get_pixmap(dpi=DPI).save(os.path.join(OUT, 'sheet_original.png'))
        a = Image.open(os.path.join(OUT, 'sheet_original.png')).convert('L'); b = Image.open(os.path.join(OUT, 'sheet_landscape.png')).convert('L')
        b = b.resize(a.size)
        diff = ImageChops.difference(a, b)
        box = diff.point(lambda v: 255 if v > 96 else 0).getbbox()
        strong = sum(1 for v in diff.getdata() if v > 96)
        print('pixels differing strongly:', strong, 'of', a.size[0] * a.size[1], 'bbox', box)
        diff.point(lambda v: 255 - min(255, v * 3)).save(os.path.join(OUT, 'sheet_diff.png'))

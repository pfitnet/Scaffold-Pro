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
import json, os, subprocess, sys
from PIL import Image, ImageDraw, ImageFont, ImageChops

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out'); os.makedirs(OUT, exist_ok=True)
APP = os.path.join(HERE, '..', '..', 'ScaffoldPro-native')
DPI = 200; S = DPI / 72

ORIGINAL = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, '..', '..', 'docs', 'reference', 'BQ-CRBC-1635.pdf')
BODY_TTF = sys.argv[2] if len(sys.argv) > 2 else os.path.join(APP, 'resources', 'fonts', 'Carlito-Regular.ttf')
TITLE_TTF = sys.argv[3] if len(sys.argv) > 3 else '/usr/share/fonts/truetype/liberation/LiberationSans-Bold.ttf'

def kg(v): return f'{v:.1f} kg'
def money(v): return f'{v:,.2f}'
def qty(v): return f'{round(v):,}'

def layout(landscape, pricing, currency, info, lines, rates=None):
    pw, ph = (842.88, 595.92) if landscape else (595.92, 842.88)
    left, top = 85.875, 53.625
    widths = [68.25, 174.75, 43.5, 51.75, 130.5, 128.25, 72.0] if landscape else [68.25, 186.54, 43.5, 51.75, 72.0]
    edges = [left]
    for w in widths: edges.append(edges[-1] + w)
    right = edges[-1]
    ie = [left, 154.125, 424.125, 492.375, right] if landscape else [left, 154.125, 263.625, 331.875, right]
    cell = lambda x0, x1, t, size, align, up, font='body': dict(x0=x0, x1=x1, text=t, font=font, size=size, align=align, baselineUp=up)
    rows = [dict(kind='banner', height=27.75, fill='ED7D31', repeats=True, cells=[cell(left, right, 'PROFICIENCY QUOTATION', 19.99, 'center', 6.375, 'title')])]
    for a, b, c, d in [('Project Code  :', info[0], 'Job Site          :', info[2]), ('Client             :', info[1], 'Structure        :', info[3])]:
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
        label = 'Subtotal :' if rates else 'Total Amount :'
        totals = [cell(edges[0], edges[n - 2], label, 28.99, 'center', 8.625), cell(edges[n - 2], edges[n - 1], money(total_money), 12, 'money', 15.375)]
    else:
        totals = [cell(edges[0], edges[n - 1], 'Total Weight :', 28.99, 'center', 8.625)]
    totals.append(cell(edges[n - 1], edges[n], kg(total_kg), 12, 'right', 15.375))
    rows.append(dict(kind='total', height=38.25, fill=None, repeats=False, cells=totals))
    if landscape and rates:
        title, items, note = rates
        rows.append(dict(kind='ratesTitle', height=19.5, fill='B4C6E7', repeats=False, cells=[cell(left, right, title, 13, 'center', 4.875)]))
        for i, (nm, rate, unit) in enumerate(items):
            texts = [(f'R{i + 1}', 'center'), (nm, 'left'), ('', 'right'), ('', 'center'), (f'{money(rate)} / {unit}', 'money'), ('(Rate Only)', 'center'), ('', 'right')]
            rows.append(dict(kind='rate', height=18, fill=None, repeats=False, cells=[cell(edges[j], edges[j + 1], t, 12, a, 4.875) for j, (t, a) in enumerate(texts)]))
        if note: rows.append(dict(kind='note', height=15.75, fill=None, repeats=False, cells=[cell(left, right, note, 10, 'left', 4.125)]))
    return dict(ok=True, kind='sheet', landscape=landscape, pageWidth=pw, pageHeight=ph, left=left, right=right, top=top,
                bottomLimit=ph - 53.25, rows=rows, number='BQ', title='PROFICIENCY QUOTATION')

_fonts = {}
def font(c, size=None):
    key = (c['font'], size or c['size'])
    if key not in _fonts: _fonts[key] = ImageFont.truetype(TITLE_TTF if c['font'] == 'title' else BODY_TTF, key[1] * S)
    return _fonts[key]
def wid(t, f): return f.getlength(t) / S

def render(L):
    img = Image.new('RGB', (round(L['pageWidth'] * S), round(L['pageHeight'] * S)), 'white'); d = ImageDraw.Draw(img)
    def rect(x, y, w, h, col): d.rectangle([x * S, y * S, (x + w) * S - 1, (y + h) * S - 1], fill=col)
    half = 0.375; y = L['top']
    for r in L['rows']:
        if r['fill']: rect(L['left'] - half, y - half, L['right'] - L['left'] + 0.75, r['height'] + 0.75, '#' + r['fill'])
        y += r['height']
    y = L['top']; rect(L['left'] - half, y - half, L['right'] - L['left'] + 0.75, 0.75, 'black')
    for r in L['rows']:
        for c in r['cells']:
            if c['x0'] > L['left'] + 0.01: rect(c['x0'] - half, y - half, 0.75, r['height'] + 0.75, 'black')
        y += r['height']; rect(L['left'] - half, y - half, L['right'] - L['left'] + 0.75, 0.75, 'black')
    rect(L['left'] - half, L['top'] - half, 0.75, y - L['top'] + 0.75, 'black'); rect(L['right'] - half, L['top'] - half, 0.75, y - L['top'] + 0.75, 'black')
    y = L['top']
    for r in L['rows']:
        bottom = y + r['height']
        for c in r['cells']:
            if not c['text']: continue
            f = font(c); pad = 2.625; space = wid(' ', f)
            room = c['x1'] - c['x0'] - 2 * pad - (space if c['align'] in ('right', 'money') else 0)
            if wid(c['text'], f) > room: f = font(c, max(c['size'] * room / wid(c['text'], f), c['size'] * 0.6))
            base = bottom - c['baselineUp']; w = wid(c['text'], f)
            put = lambda t, x: d.text((x * S, base * S), t, font=f, fill='black', anchor='ls')
            if c['align'] == 'center': put(c['text'], (c['x0'] + c['x1']) / 2 - w / 2)
            elif c['align'] == 'right': put(c['text'], c['x1'] - pad - space - w)
            elif c['align'] == 'money': put('$', c['x0'] + pad); put(c['text'], c['x1'] - pad - space - w)
            else: put(c['text'], c['x0'] + pad)
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

if __name__ == '__main__':
    import pymupdf
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

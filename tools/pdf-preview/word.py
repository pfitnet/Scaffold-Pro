# Word export check without a Mac: turns the preview documents (docs.py) into
# the layout the app sends to js/docx-export.js (as PDFGenerator.wordLayout
# does in main.swift), builds the .docx files with that script (node), and
# renders them with LibreOffice so they can be compared with the PDF preview.
#
#   python3 word.py        # → out/word_<name>.docx and out/word_<name>_<page>.png
import base64, json, os, subprocess, sys
from PIL import Image, ImageDraw
import render
from render import Gen, body, width, W, H, S
import docs

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, 'out')
APP = os.path.join(HERE, '..', '..', 'ScaffoldPro-native')

def letterhead_png():
    g = Gen()
    g.img = Image.new('RGBA', (round(W * S), round(H * S)), (255, 255, 255, 0)); g.d = ImageDraw.Draw(g.img)
    g.letterhead()
    real = g.inktext
    g.inktext = lambda st, *a, **k: None if st.startswith('Page ') else real(st, *a, **k)
    g.footer()
    path = os.path.join(OUT, 'letterhead.png'); g.img.save(path)
    return base64.b64encode(open(path, 'rb').read()).decode()

def text_x(marker, left, indent, colon):
    f = body(11); mw = width(marker, f) if marker else 0
    tx = indent if indent is not None else left + max(18, mw + 6)
    if marker: tx = max(tx, left + mw + (7.5 if colon else 5))
    return min(tx, Gen.textRight - 120 - Gen.textLeft)

def layout(doc):
    g = Gen(); g.configure(doc); f = body(11); cw = width(doc['cur'], f)
    receipt_new_page = False
    if doc.get('receiptRows'):
        t = Gen(); t.layOut(doc); receipt_new_page = t.receiptOnNewPage
    long = False
    if any(s.get('newPageUnlessSinglePage') for s in doc['sections']):
        t = Gen(); t.layOut(doc); long = t.pageNumber > 1
    rows = []
    for r in doc['rows']:
        h = g.rowHeight(r, doc)
        if r[0] == 'item':
            rows.append(dict(type='item', height=h, cells=[g.cellLines(c, doc['columns'][i], f, cw) for i, c in enumerate(r[1]) if i < len(doc['columns'])]))
        elif r[0] == 'section': rows.append(dict(type='section', height=h, text=r[1]))
        elif r[0] == 'summary': rows.append(dict(type='summary', height=h, label=r[1], value=r[2], emphasized=r[3]))
        elif r[0] == 'partial': rows.append(dict(type='partial', height=h, cells=[g.cellLines(c, doc['columns'][i], f, cw) for i, c in enumerate(r[1])], text=r[2]))
        elif r[0] == 'note': rows.append(dict(type='note', height=h, text=r[1]))
    sections = []
    for s in doc['sections']:
        paras = []
        for p in s['paragraphs']:
            if p[0] == 'text': paras.append(dict(type='text', text=p[1], link=p[2]))
            elif p[0] == 'term': paras.append(dict(type='hanging', marker=p[1] or '', lines=p[2], left=0, textX=text_x(p[1] or '', 0, 89.25, True), colon=True))
            else:
                _, marker, lines, left, indent, colon = p
                paras.append(dict(type='hanging', marker=marker, lines=lines, left=left, textX=text_x(marker, left, indent, colon), colon=colon))
        sections.append(dict(heading=s.get('heading'), paragraphs=paras, pageBreakBefore=bool(s.get('newPageUnlessSinglePage') and long)))
    fonts = [dict(style=st, data=base64.b64encode(open(os.path.join(APP, 'resources', 'fonts', fn), 'rb').read()).decode())
             for st, fn in [('regular', 'EBGaramond-Regular.ttf'), ('bold', 'EBGaramond-Bold.ttf'), ('italic', 'EBGaramond-Italic.ttf'), ('boldItalic', 'EBGaramond-BoldItalic.ttf')]]
    return dict(ok=True, paperSize='A4', pageWidth=W, pageHeight=H, textLeft=Gen.textLeft, textRight=Gen.textRight, contentBottom=Gen.contentBottom,
                number=doc['number'], status=doc['status'], title=doc['title'], clientName='\n'.join(l for l, fnt in g.clientBlock(doc) if fnt == body(12, True)), clientLines=[l for l, fnt in g.clientBlock(doc) if fnt != body(12, True)],
                refRows=[dict(label=a, value=b, wraps=len(g.wrap(b, f, 66)) > 1) for a, b in doc['refRows']],
                deliveryMethod=doc.get('deliveryMethod'), salutation=doc.get('salutation'), subject=doc.get('subject'), intro=doc.get('intro'),
                currencySymbol=doc['cur'], columns=[dict(title=c[0], width=c[1], kind=c[2]) for c in doc['columns']], rows=rows, sections=sections,
                signatures=[dict(heading=s['heading'], lines=[dict(text=t, colon=c, value=v) for t, c, v in s['lines']]) for s in doc['signatures']],
                closingLine=doc.get('closing'), fonts=fonts,
                infoRows=[dict(label=a, lines=g.infoLines(b, bold), bold=bold) for a, b, bold in doc.get('infoRows') or []],
                headerHeight=g.headH, receiptRows=[list(r) for r in doc.get('receiptRows') or []], receiptNewPage=receipt_new_page)

if __name__ == '__main__':
    png = letterhead_png()
    names = sys.argv[1:] or ['quotation', 'quotation_sections', 'quotation_keyterms', 'invoice', 'dn', 'dn_short', 'boq']
    for name in names:
        payload = layout(getattr(docs, name)()); payload['letterheadPNG'] = png
        jp = os.path.join(OUT, f'word_{name}.json'); json.dump(payload, open(jp, 'w'))
        dp = os.path.join(OUT, f'word_{name}.docx')
        subprocess.run(['node', '-e', f"require('{APP}/js/docx-export.js'); const fs=require('fs'); fs.writeFileSync('{dp}', buildLetterDocx(JSON.parse(fs.readFileSync('{jp}','utf8'))))"], check=True)
        subprocess.run(['soffice', '--headless', '--convert-to', 'pdf', '--outdir', OUT, dp], check=True, capture_output=True)
        pdf = dp[:-5] + '.pdf'
        import pymupdf  # pip install pymupdf
        pages = pymupdf.open(pdf)
        for i, page in enumerate(pages):
            page.get_pixmap(dpi=96).save(os.path.join(OUT, f'word_{name}_{i + 1}.png'))
        print(name, len(pages), 'pages')

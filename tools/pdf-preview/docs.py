# Renders sample quotation / invoice / delivery note / BOQ pages with the
# Python port of the PDF layout (render.py). Output goes to ./out/.
# Usage: python3 docs.py   (needs Pillow: pip install pillow)
import os, sys
HERE=os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0,HERE)
from render import Gen
OUT=os.path.join(HERE,'out'); os.makedirs(OUT,exist_ok=True)
def money(v): return f'{v:,.2f}'
PRICED=[('No',29.25,'center'),('Item Description',219.75,'left'),('Unit Rate',110.25,'money'),('Qty',39.0,'center'),('Total Price',108.75,'money')]
client=('Lingma Construction & Engineering Co. Ltd.',['Flat K, 12/F, Gold King Industrial Building,','35 Tai Lin Pai Rd, Kwai Chung,','New Territories, Hong Kong'])
items=[('600mm Base Jack',5.50,6),('235 Base Collar',3.30,6),('1.0m standard with spigot',11.70,12),('2.0m standard with spigot',18.10,6),('1.09m Ledger',7.50,18),('1.57m Ledger',9.30,36),('1.57m x 2.0m Face Brace',14.50,4),('1.09m x 0.32m Steel Deck',15.60,6),('1.57m x 0.32m Steel Deck',18.40,12),('1.09m Toe Board',6.40,4),('1.57m Toe Board',8.10,8),('1.57m Flip Board',45.00,2),('2.0m Cat Ladder',23.20,2)]
TERMS="""(i) Payment : First two month's rental is to be paid upon order confirmation,
Following rental charges are to be paid monthly on the first day of the month
Delivery charges are to be paid within 7 days against each trucks' delivery
(ii) Delivery : Minimum of 5 days upon order confirmation
(iv) Modification : Extra works & modifications of works will be subject to an extra charge."""
# Same rules as formattedParagraphs() in main.swift.
import re
NUMBER_RE=re.compile(r'^(\(?[0-9]{1,3}[.)]|\([0-9]{1,3}\)|\(?[a-zA-Z][.)]|\([a-zA-Z]\)|\(?[ivxIVX]{1,5}[.)]|\([ivxIVX]{1,5}\))\s+')
LABEL_INDENT=89.25
def labelSplit(l):
    if ':' not in l: return None
    label,after=l.split(':',1); label=label.strip()
    if not label or len(label)>40 or len(label.split())>5 or (after and after[0] not in ' \t') or 'http' in label.lower() or 'www.' in label.lower(): return None
    return (label,after.strip(),'label')
def hangingItem(raw):
    l=raw.strip()
    if '\t' in l:
        m,rest=l.split('\t',1); m=m.strip()
        if m: return (m[:-1].strip(),rest.strip(),'label') if m.endswith(':') else (m,rest.strip(),'marker')
    for b in ['- ','• ','* ','· ']:
        if l.startswith(b): return ('•',l[len(b):].strip(),'bullet')
    lab=labelSplit(l)
    if lab: return lab
    m=NUMBER_RE.match(l)
    if m: return (m.group(0).strip(),l[m.end():],'marker')
    return None
OFFSET={'label':LABEL_INDENT,'bullet':12,'marker':24}
def formatted(t,left=0):
    out=[]; cur=None; plain=[]; parent=None
    def flush():
        nonlocal cur,plain
        if cur:
            out.append(('hanging',cur[0],cur[1],cur[3],cur[3]+OFFSET[cur[2]],cur[2]=='label')); cur=None
        if plain:
            out.append(('text','\n'.join(plain),None) if left==0 else ('hanging','',plain,left,left,False)); plain=[]
    for raw in t.replace('\r\n','\n').split('\n'):
        tr=raw.strip()
        if not tr: flush(); continue
        it=hangingItem(raw)
        if it:
            flush(); ind=raw[:1] in (' ','\t'); il=parent if (ind and parent is not None) else left
            if not ind or parent is None: parent=left+OFFSET[it[2]]
            cur=(it[0],[it[1]] if it[1] else [],it[2],il)
        elif cur: cur[1].append(tr)
        else: plain.append(tr); parent=None
    flush(); return out
def paymentTerms(pt,label):
    nested=formatted(pt,LABEL_INDENT); opening=[]
    if nested and nested[0][0]=='hanging' and nested[0][1]=='' and not nested[0][5]: opening=nested[0][2]; nested=nested[1:]
    return [('hanging',label,opening,0,LABEL_INDENT,True)]+nested
def parseTerms(t,pt=None):
    out=formatted(t)
    if pt:
        for i,p in enumerate(out):
            if p[0]=='hanging' and p[3]==0 and 'payment' in p[1].lower(): return out[:i]+paymentTerms(pt,p[1])+out[i+1:]
        out+=paymentTerms(pt,'Payment')
    return out
ACCEPT="Order shall be confirmed and regarded as properly accepted upon signature by all parties AND such signed copy is returned to Proficiency (HK) Limited via instant electronic communication means. This quotation shall be valid for 7 business days against the issue date."
def companySig(): return {'heading':'For and on Behalf of','lines':[('Proficiency (HK) Limited',False,None),('Richard Kwan',False,None),('Director',False,None)]}
def quotation(status='Issued'):
    rows=[('item',[str(i+1),d,f'{money(p)} /Month',str(q),money(p*q)]) for i,(d,p,q) in enumerate(items)]
    sub=sum(p*q for _,p,q in items)
    rows+=[('summary','Subtotal of Monthly Rental Charge:',money(sub),False),('summary','Minimum Hire of 2 Months:',money(sub*2),False),('section','Delivery Charges'),
           ('item',['D1','Delivery of materials\n(from yard to site and from site to yard )',f'{money(1200)} /truck/trip','2',money(2400)]),('summary','Total Amount:',money(sub*2+2400),True)]
    terms=[('text','The terms and conditions set out in www.pfitnet.com/TC are hereby expressively incorporated into this quotation with other relevant key terms set forth below.','www.pfitnet.com/TC')]+parseTerms(TERMS)+[('text',ACCEPT,None)]
    return dict(number='Qt26193',status=status,title='QUOTATION',clientName=client[0],clientLines=client[1],refRows=[('Our Ref. No.','Qt26193'),('Your Ref. No.',''),('Site Ref.','MTR 1601'),('Date','22 Sep 2026')],
        deliveryMethod='BY EMAIL ONLY',salutation='Dear Sir / Madam,',subject='Re: 1601 Scaffolding Materials - Rental - GL-28 G/F South G-015 For BS Wone - Req. by Gomez',
        intro='We thank you for your inquiry related to the item above, the following is our quotation on the job.',cur='HK$',columns=PRICED,rows=rows,
        sections=[{'heading':'Terms and Conditions','paragraphs':terms,'newPageUnlessSinglePage':True}],
        signatures=[companySig(),{'heading':'For and on Behalf of','lines':[(client[0],False,None),('Position',True,None),('Date',True,None)]}],
        closing='-[Remainder of this page is intentionally left blank]-')
def invoice():
    rows=[('item',[str(i+1),d,money(p),str(q),money(p*q)]) for i,(d,p,q) in enumerate(items[:6])]
    sub=sum(p*q for _,p,q in items[:6])
    rows+=[('section','Delivery Charges'),('item',['D1','Delivery of materials\n(from yard to site and from site to yard)',f'{money(3800)} /truck/trip','2',money(7600)])]
    tot=sub+7600
    rows+=[('summary','Total Amount:',money(tot),True),('summary','Less Amount Paid:','-'+money(2000),False),('summary','Balance Due:',money(tot-2000),True)]
    return dict(number='H26012',status='Issued',title='INVOICE',clientName=client[0],clientLines=client[1],refRows=[('Invoice No.','H26012'),('Project No.','26017'),('Site Ref.','MTR 1601'),('Date','28 Sep 2026'),('Due Date','28 Oct 2026')],
        subject='Re: 26017 GL-28 G/F South G-015 Scaffolding',cur='HK$',columns=PRICED,rows=rows,
        sections=[{'heading':'Payment Information','paragraphs':paymentTerms('Within 30 days of the invoice date','Payment Terms')+[('text','Bank: HSBC\nAccount name: Proficiency (HK) Limited\nAccount no.: 123-456789-001',None)]}],
        signatures=[companySig()],closing=None)
def dn():
    rows=[('item',[str(i+1),d,'pc',str(q)]) for i,(d,p,q) in enumerate(items)]
    return dict(number='26017-DN-001',status='Draft',title='DELIVERY NOTE',clientName=client[0],clientLines=client[1],refRows=[('D/N No.','26017-DN-001'),('Project No.','26017'),('Site Ref.','MTR 1601'),('Date','28 Sep 2026')],
        subject='Re: 26017 GL-28 G/F South G-015 Scaffolding',intro='Delivery address: GL-28 G/F South, 1601 Site, Kwai Chung',cur='HK$',
        columns=[('No',29.25,'center'),('Item Description',327.75,'left'),('Unit',75.0,'center'),('Qty',75.0,'center')],rows=rows,sections=[],
        signatures=[{'heading':'Delivered by','lines':[('Proficiency (HK) Limited',False,None),('Name',True,'Chan Tai Man'),('Date',True,None)]},
                    {'heading':'Received in good condition by','lines':[(client[0],False,None),('Name',True,None),('Date',True,None)]}],closing=None)
def boq():
    w=[4.1,1.2,5.6,10.9,3.4,5.0,7.8,9.4,13.2,3.1,4.4,12.0,6.3]
    rows=[('item',[str(i+1),d,'pc',str(q),money(w[i]),money(w[i]*q)]) for i,(d,p,q) in enumerate(items)]
    rows.append(('summary','Total Weight:',money(sum(w[i]*q for i,(d,p,q) in enumerate(items)))+' kg',True))
    return dict(number='26017-BOQ-001',status='Issued',title='BILL OF QUANTITIES',clientName=client[0],clientLines=client[1],refRows=[('BOQ No.','26017-BOQ-001'),('Project No.','26017'),('Site Ref.','MTR 1601'),('Date','28 Sep 2026')],
        subject='Re: 26017 GL-28 G/F South G-015 Scaffolding - Rental',intro='Structure: Access platform for louvre installation',cur='HK$',
        columns=[('No',29.25,'center'),('Item Description',219.75,'left'),('Unit',50.0,'center'),('Qty',50.0,'center'),('Unit Wt (kg)',75.0,'right'),('Total Wt (kg)',83.0,'right')],rows=rows,sections=[],signatures=[],closing=None)
def quotation_short():
    # Fits on one page, so the Terms stay on page 1. Minimum hire off; a 10% line discount.
    lines=[('600mm Base Jack',5.50,6,None),('1.57m Ledger',9.30,36,('Percent',10)),('2.0m Cat Ladder',23.20,2,None)]
    rows=[]; sub=0
    for i,(d,p,q,disc) in enumerate(lines):
        gross=round(p*q,2); net=gross-(round(gross*disc[1]/100,2) if disc else 0); sub+=net
        desc=d+('\nLess 10% discount' if disc else '')
        rows.append(('item',[str(i+1),desc,f'{money(p)} /Month',str(q),money(net)]))
    rows+=[('summary','Subtotal of Monthly Rental Charge:',money(sub),False),('section','Delivery Charges'),
           ('item',['D1','Delivery of materials\n(from yard to site and from site to yard)',f'{money(3800)} /truck/trip','2',money(7600)]),('summary','Total Amount:',money(sub+7600),True)]
    doc=quotation(); doc.update(number='Qt26201',status='Draft',rows=rows,refRows=[('Our Ref. No.','Qt26201'),('Your Ref. No.',''),('Site Ref.','MTR 1601'),('Date','28 Sep 2026')])
    return doc
def quotation_sections():
    # Delivery, a priced "Design Fees" section, the total, then a rates-only
    # section with its note (as on the company's quotation). Minimum hire of
    # 1 month: no "Minimum Hire" row.
    lines=[('600mm Base Jack',5.50,6),('1.57m Ledger',9.30,36),('2.0m Cat Ladder',23.20,2)]
    rows=[('item',[str(i+1),d,f'{money(p)} /Month',str(q),money(round(p*q,2))]) for i,(d,p,q) in enumerate(lines)]
    sub=sum(round(p*q,2) for d,p,q in lines)
    rows+=[('summary','Subtotal of Monthly Rental Charge:',money(sub),False),('section','Delivery Charges'),
           ('item',['D1','Delivery of materials\n(from yard to site and from site to yard )',f'{money(3800)} /truck/trip','8',money(30400)]),
           ('section','Design Fees'),('item',['A1','Design and Drawing',money(3000),'1',money(3000)]),
           ('summary','Total Amount:',money(sub+30400+3000),True),('section','Erection & Dismantle Manpower Rates')]
    rows+=[('partial',[f'R{i+1}',d,f'{money(r)} / md'],'(Rate Only)') for i,(d,r) in enumerate([('Scaffolder CP',2300),('Scaffolder',2100),('Rigger',2000),('General Helper',1800)])]
    rows.append(('note','* Please note that labour rates are subject to a price increase for over-time works and works on sundays / public holidays'))
    doc=quotation(); doc.update(number='Qt26202',status='Draft',rows=rows,refRows=[('Our Ref. No.','Qt26202'),('Your Ref. No.',''),('Site Ref.','MTR 1601'),('Date','28 Sep 2026')])
    return doc
def keyTermsText(standard,pt):
    # Same as keyTermsText(_:withPaymentTerms:) in main.swift.
    lines=standard.replace('\r\n','\n').split('\n')
    def isPay(l):
        it=hangingItem(l); return bool(it) and it[2]=='label' and 'payment' in it[0].lower()
    start=next((i for i,l in enumerate(lines) if isPay(l)),None)
    label=hangingItem(lines[start])[0] if start is not None else 'Payment'
    block=[]; opening=True
    for raw in pt.split('\n'):
        l=raw.strip()
        if not l: continue
        if opening and hangingItem(l) is None: block.append(f'{label} : {l}' if not block else l)
        else:
            if not block: block.append(f'{label} :')
            opening=False; block.append('    '+l)
    if start is None: return '\n'.join(lines+block)
    end=start+1
    while end<len(lines):
        l=lines[end]
        if not l.strip(): break
        if hangingItem(l) is not None and l[:1] not in (' ','\t'): break
        end+=1
    return '\n'.join(lines[:start]+block+lines[end:])
def quotation_keyterms():
    # A quotation's own key terms (all editable), with indented bullets and a
    # labelled line under "(i) Payment" — here made the way the one-time
    # carry-over turns older payment terms into key terms.
    doc=quotation_short()
    pt="""First two month's rental is to be paid upon order confirmation.
- Following rental charges are to be paid monthly on the first day of the month, by cheque or bank transfer to the account shown on the invoice.
- Delivery charges are to be paid within 7 days against each truck's delivery.
Deposit: HK$ 10,000.00, refundable on return of all materials in good condition."""
    kt=keyTermsText(TERMS,pt).replace('Minimum of 5 days','Minimum of 3 working days')
    print(kt)
    doc['sections'][0]['paragraphs']=[doc['sections'][0]['paragraphs'][0]]+formatted(kt)+[('text',ACCEPT,None)]
    doc.update(number='Qt26204'); return doc
def quotation_payment():
    # This quotation's own payment terms, with bullets and a labelled line, in
    # place of the standard "(i) Payment" term.
    doc=quotation_short()
    pt="""First two month's rental is to be paid upon order confirmation.
- Following rental charges are to be paid monthly on the first day of the month, by cheque or bank transfer to the account shown on the invoice.
- Delivery charges are to be paid within 7 days against each truck's delivery.
Deposit: HK$ 10,000.00, refundable on return of all materials in good condition."""
    doc['sections'][0]['paragraphs']=[doc['sections'][0]['paragraphs'][0]]+parseTerms(TERMS,pt)+[('text',ACCEPT,None)]
    doc.update(number='Qt26203'); return doc
for name,fn in [('quotation_keyterms',quotation_keyterms),('quotation_payment',quotation_payment),('quotation',quotation),('quotation_short',quotation_short),('quotation_sections',quotation_sections),('invoice',invoice),('dn',dn),('boq',boq)]:
    pages=Gen().generate(fn())
    for i,p in enumerate(pages): p.save(os.path.join(OUT,f'{name}_{i+1}.png'))
    print(name,len(pages),'pages')

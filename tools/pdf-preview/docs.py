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
def parseTerms(t):
    out=[]
    for raw in t.split('\n'):
        l=raw.strip()
        if not l: continue
        if l.startswith('(') and ':' in l:
            a,b=l.split(':',1); out.append(['term',a.strip(),[b.strip()]])
        elif out: out[-1][2].append(l)
        else: out.append(['term',None,[l]])
    return [tuple(x) for x in out]
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
        sections=[{'heading':'Terms and Conditions','paragraphs':terms}],
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
        sections=[{'heading':'Payment Information','paragraphs':[('text','Payment terms: 30 days net',None),('text','Bank: HSBC\nAccount name: Proficiency (HK) Limited\nAccount no.: 123-456789-001',None)]}],
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
for name,fn in [('quotation',quotation),('invoice',invoice),('dn',dn),('boq',boq)]:
    pages=Gen().generate(fn())
    for i,p in enumerate(pages): p.save(os.path.join(OUT,f'{name}_{i+1}.png'))
    print(name,len(pages),'pages')

# Python port of PDFGenerator in ScaffoldPro-native/main.swift, used to preview
# the letterhead layout and compare it with the sample quotation (Qt26193)
# without a Mac. It uses the same constants as the Swift code; if you change
# the layout in main.swift, change it here too.
#
# Stand-in fonts (Linux): DejaVu Sans Bold for Verdana Bold, IPAGothic for the
# Chinese fonts, Liberation Serif (same letter widths as Times New Roman).
# EB Garamond comes from the app's own resources/fonts folder.
import os
from PIL import Image, ImageDraw, ImageFont
HERE=os.path.dirname(os.path.abspath(__file__))
EBG=os.path.join(HERE,'..','..','ScaffoldPro-native','resources','fonts')+'/'
LIB='/usr/share/fonts/truetype/liberation/'
S=4/3; W,H=595.28,841.89
ORANGE=(241,158,56); GREY=(153,153,153); DGREY=(102,102,102); BLACK=(0,0,0); LINK=(40,84,197)
VERD='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'; CJK='/usr/share/fonts/opentype/ipafont-gothic/ipag.ttf'
FONTS={('b',0,0):EBG+'EBGaramond-Regular.ttf',('b',1,0):EBG+'EBGaramond-Bold.ttf',('b',0,1):EBG+'EBGaramond-Italic.ttf',('b',1,1):EBG+'EBGaramond-BoldItalic.ttf',
       ('t',0,0):LIB+'LiberationSerif-Regular.ttf',('t',1,0):LIB+'LiberationSerif-Bold.ttf',('t',0,1):LIB+'LiberationSerif-Italic.ttf',('t',1,1):LIB+'LiberationSerif-BoldItalic.ttf'}
_cache={}
def font(kind,size,bold=False,italic=False):
    k=(kind,int(bold),int(italic),size)
    if k not in _cache: _cache[k]=ImageFont.truetype(FONTS[k[:3]],size*S)
    return _cache[k]
def body(size=11,bold=False,italic=False): return font('b',size,bold,italic)
def times(size,bold=False,italic=False): return font('t',size,bold,italic)
def width(s,f): return f.getlength(s)/S

class Gen:
    def __init__(s): s.pages=[]; s.cursor=0; s.pageNumber=0; s.documentIsLong=False
    textLeft=42.75; textRight=552.0; contentBottom=781.5; contBase=95.25; contTable=88.0; pitch=16.5; rule=0.75; rowH=24.1; cellPitch=14.25
    def fill(s,x,y,w,h,c):
        x0,y0=round(x*S),round(y*S); s.d.rectangle([x0,y0,max(x0,round((x+w)*S)-1),max(y0,round((y+h)*S)-1)],fill=c)
    def text(s,st,x,base,f,c=BLACK,align='left',underline=False,size=None):
        if not st: return 0
        w=width(st,f); sx=x-w if align=='right' else x-w/2 if align=='center' else x
        s.d.text((sx*S,base*S),st,font=f,fill=c,anchor='ls')
        if underline: s.fill(sx,base+f.size/S*0.1,w,max(0.6,f.size/S*0.05),c)
        return w
    def inktext(s,st,base,f,c,left=None,right=None):
        bb=f.getbbox(st,anchor='ls'); x=left*S-bb[0] if left is not None else right*S-bb[2]
        s.d.text((x,base*S),st,font=f,fill=c,anchor='ls')
    def fitted(s,st,path,c,x0,top,x1,bot):
        f=ImageFont.truetype(path,200); bb=f.getbbox(st)
        tmp=Image.new('L',(bb[2]-bb[0]+4,bb[3]-bb[1]+4),0); ImageDraw.Draw(tmp).text((2-bb[0],2-bb[1]),st,font=f,fill=255); tmp=tmp.crop(tmp.getbbox())
        bw,bh=round((x1-x0)*S),round((bot-top)*S); tmp=tmp.resize((bw,bh),Image.LANCZOS)
        s.img.paste(Image.new('RGB',(bw,bh),c),(round(x0*S),round(top*S)),tmp)
    def wrap(s,st,f,wd):
        out=[]
        for para in st.split('\n'):
            words=para.strip().split(' ')
            if not para.strip(): continue
            cur=''
            for w_ in words:
                t=(cur+' '+w_) if cur else w_
                if width(t,f)<=wd or not cur: cur=t
                else: out.append(cur); cur=w_
            out.append(cur)
        return out
    def letterhead(s):
        f=s.fitted; f('P',VERD,ORANGE,42.75,28.5,57.75,46.5); f('ROFICIENCY',VERD,GREY,60.0,31.5,200.25,47.25); s.fill(6.0,51.0,209.25,2.25,ORANGE)
        # Noto Sans TC 15pt, natural shape (bundled subset in resources/fonts)
        s.inktext('建機 (香港) 有限公司',72.25,ImageFont.truetype(EBG+'ScaffoldPro-LetterheadTC.ttf',15*S),DGREY,left=41.25)
        f('(HK)',VERD,ORANGE,190.5,58.5,240.75,77.25); f('LIMITED',VERD,GREY,251.25,61.5,331.5,74.25); s.fill(189.0,78.0,W-6.53-189.0,2.25,ORANGE)
    def footer(s):
        s.fill(42.75,792.75,510.0,2.25,ORANGE)
        for st,l,r in [('香港',210.75,228.75),('北角',231.75,248.25),('蜆殼街 9-23',252.0,297.0),('號',300.0,308.25),('秀明中心',311.25,346.5),('17樓 B室',349.5,384.0)]:
            s.fitted(st,CJK,GREY,l,798.75,r,807.75)
        f=times(9)
        for wd,l in zip("Unit B, 17/F, Seabright Plaza, 9-23 Shell Street, Causeway Bay, Hong Kong".split(' '),[160.5,178.5,189.75,209.25,246.0,270.0,288.75,309.75,335.25,374.25,393.0,414.75]):
            s.inktext(wd,816.75,f,GREY,left=l)
        for st,l in [('Tel: +852 2690 0133',153.0),('Email: rk123@pfitnet.com',249.75),('Fax: +852 2663 0371',368.25)]: s.inktext(st,827.25,f,GREY,left=l)
        s.inktext(f'Page {s.pageNumber}',827.25,times(9,italic=True),GREY,right=552.0)
    def begin(s):
        s.img=Image.new('RGB',(round(W*S),round(H*S)),'white'); s.d=ImageDraw.Draw(s.img); s.pageNumber+=1; s.letterhead()
    def end(s): s.footer(); s.pages.append(s.img)
    def newPage(s): s.end(); s.begin()
    def opening(s,doc):
        left=[(l,body(12,True)) for l in s.wrap(doc['clientName'],body(12,True),345)]
        for l in doc['clientLines']: left+=[(x,body(12)) for x in s.wrap(l,body(12),345)]
        for i,(l,f) in enumerate(left): s.text(l,47.75,104.25+i*15.75,f)
        n=0
        for lab,val in doc['refRows']:
            b=104.25+n*15.75; s.text(lab,401.25,b,body(11)); s.text(':',478.5,b,body(11))
            vl=s.wrap(val,body(11),66)
            if len(vl)<=1: s.text(val,550.5,b,body(11),align='right'); n+=1
            else:
                for j,l in enumerate(vl): s.text(l,484.5,104.25+(n+j)*15.75,body(11))
                n+=len(vl)
        base=104.25+(max(len(left),n,1)-1)*15.75
        if doc.get('deliveryMethod'):
            base+=19.5; s.text(doc['deliveryMethod'],550.5,base,body(13,True),align='right',underline=True); base+=21.0
        else: base+=40.5
        s.text(doc['title'],W/2,base,body(15,True),align='center',underline=True)
        if doc['status']!='Issued': s.text(doc['status'].upper(),s.textRight,base,body(11,True),GREY,align='right')
        last=base; nxt=base+18
        if doc.get('salutation'): s.text(doc['salutation'],s.textLeft,nxt,body(11)); last=nxt; nxt+=16.5
        if doc.get('subject'):
            for l in s.wrap(doc['subject'],body(11,True),s.textRight-s.textLeft): s.text(l,s.textLeft,nxt,body(11,True),underline=True); last=nxt; nxt+=16.5
        if doc.get('intro'):
            for l in s.wrap(doc['intro'],body(11),s.textRight-s.textLeft): s.text(l,s.textLeft,nxt,body(11)); last=nxt; nxt+=16.5
        s.cursor=last+15
    def cellBase(s,top,h,n,j): return top+h/2+5.2-(n-1)*s.cellPitch/2+j*s.cellPitch
    def cellLines(s,v,col,f,cw): return s.wrap(v,f,col[1]-10.5-(cw+4 if col[2]=='money' else 0))
    def rowHeight(s,row,doc):
        if row[0]=='item':
            f=body(11); cw=width(doc['cur'],f); n=1
            for i,c in enumerate(row[1]): n=max(n,len(s.cellLines(c,doc['columns'][i],f,cw)))
            return s.rowH+(n-1)*14.9
        if row[0]=='section': return 37.5
        if row[0]=='partial': return s.rowHeight(('item',row[1]),doc)
        if row[0]=='note': return 29.25+(max(1,len(s.wrap(row[1],body(9.5,italic=True),s.noteWidth(doc))))-1)*13.0
        return 37.5 if row[3] else 29.25
    def noteWidth(s,doc): return sum(c[1] for c in doc['columns'])-12.0
    def hr(s,e,y): s.fill(e[0],y,e[-1]-e[0]+s.rule,s.rule,BLACK)
    def vr(s,x,t,h): s.fill(x,t,s.rule,h+s.rule,BLACK)
    def drawCell(s,lines,col,l,r,top,h,f,cur):
        n=max(1,len(lines))
        for j,line in enumerate(lines):
            b=s.cellBase(top,h,n,j); k=col[2]
            if k=='center': s.text(line,(l+r+s.rule)/2,b,f,align='center')
            elif k=='left': s.text(line,l+5.0,b,f)
            else: s.text(line,r-3.4,b,f,align='right')
        if col[2]=='money' and lines and lines[0]: s.text(cur,l+5.25,s.cellBase(top,h,1,0),f)
    def header(s,cols,e):
        t=s.cursor; s.hr(e,t); s.hr(e,t+s.rowH)
        for x in e: s.vr(x,t,s.rowH)
        for i,c in enumerate(cols): s.text(c[0],(e[i]+e[i+1]+s.rule)/2,s.cellBase(t,s.rowH,1,0),body(11,True),align='center')
        s.cursor+=s.rowH
    def table(s,doc):
        cols=doc['columns']; e=[42.0]
        for c in cols: e.append(e[-1]+c[1])
        last=len(e)-1; s.header(cols,e)
        for row in doc['rows']:
            h=s.rowHeight(row,doc)
            if s.cursor+h>s.contentBottom: s.newPage(); s.cursor=s.contTable; s.header(cols,e)
            t=s.cursor; s.hr(e,t); s.hr(e,t+h)
            if row[0]=='item':
                for x in e: s.vr(x,t,h)
                f=body(11); cw=width(doc['cur'],f)
                for i,c in enumerate(row[1]): s.drawCell(s.cellLines(c,cols[i],f,cw),cols[i],e[i],e[i+1],t,h,f,doc['cur'])
            elif row[0]=='section':
                s.vr(e[0],t,h); s.vr(e[last],t,h); s.text(row[1],(e[0]+e[last]+s.rule)/2,s.cellBase(t,h,1,0),body(12,True),align='center')
            elif row[0]=='partial':
                n=min(len(row[1]),len(cols)-1)
                for x in e[:n+1]: s.vr(x,t,h)
                s.vr(e[last],t,h); f=body(11); cw=width(doc['cur'],f)
                for i,c in enumerate(row[1][:n]): s.drawCell(s.cellLines(c,cols[i],f,cw),cols[i],e[i],e[i+1],t,h,f,doc['cur'])
                s.text(row[2],(e[n]+e[last]+s.rule)/2,s.cellBase(t,h,1,0),f,align='center')
            elif row[0]=='note':
                s.vr(e[0],t,h); s.vr(e[last],t,h); f=body(9.5,italic=True); lines=s.wrap(row[1],f,s.noteWidth(doc))
                first=t+h/2+3.4-(max(1,len(lines))-1)*13.0/2
                for j,l in enumerate(lines): s.text(l,e[0]+6.0,first+j*13.0,f,c=DGREY)
            else:
                s.vr(e[0],t,h); s.vr(e[last-1],t,h); s.vr(e[last],t,h); f=body(12 if row[3] else 11,True)
                s.text(row[1],e[last-1]-4.25,s.cellBase(t,h,1,0),f,align='right'); s.drawCell([row[2]],cols[last-1],e[last-1],e[last],t,h,f,doc['cur'])
            s.cursor+=h
    def paragraph(s,st,link,base):
        f=body(11); tw=s.textRight-s.textLeft; lines=[]
        for pi,para in enumerate(st.split('\n')):
            ws=para.split(' '); cur=[]
            for w_ in ws:
                if cur and width(' '.join(cur+[w_]),f)>tw: lines.append((cur,True)); cur=[w_]
                else: cur.append(w_)
            lines.append((cur,False))
        first=True
        for words,justify in lines:
            if not first: base+=s.pitch
            if base>s.contentBottom: s.newPage(); base=s.contBase
            first=False
            total=sum(width(w_,f) for w_ in words); gap=width(' ',f)
            if justify and len(words)>1: gap=(tw-total)/(len(words)-1)
            x=s.textLeft
            for w_ in words:
                c=BLACK
                if link and link in w_:
                    c=LINK; s.fill(x,base+1.1,width(w_,f),0.6,LINK)
                s.d.text((x*S,base*S),w_,font=f,fill=c,anchor='ls'); x+=width(w_,f)+gap
        return base
    def term(s,label,lines,base):
        f=body(11); first=True
        for raw in lines:
            for piece in s.wrap(raw,f,s.textRight-132.0):
                if not first: base+=s.pitch
                if base>s.contentBottom: s.newPage(); base=s.contBase
                if first:
                    if label: s.text(label,s.textLeft,base,f)
                    s.text(':',128.25,base,f)
                s.text(piece,132.0,base,f); first=False
        return base
    def sections(s,secs):
        after=True
        for sec in secs:
            base=s.cursor+(27.0 if after else 33.0); after=False
            if sec.get('newPageUnlessSinglePage') and s.documentIsLong: s.newPage(); base=s.contBase
            if sec.get('heading'):
                if base+26.25>s.contentBottom: s.newPage(); base=s.contBase
                s.text(sec['heading'],s.textLeft,base,body(11,True),underline=True); s.cursor=base; base+=26.25
            prevTerm=False
            for i,p in enumerate(sec['paragraphs']):
                if p[0]=='text':
                    if i>0: base=s.cursor+(33.0 if prevTerm else 26.25)
                    if base>s.contentBottom: s.newPage(); base=s.contBase
                    s.cursor=s.paragraph(p[1],p[2],base); prevTerm=False
                else:
                    if i>0: base=s.cursor+(16.5 if prevTerm else 26.25)
                    if base>s.contentBottom: s.newPage(); base=s.contBase
                    s.cursor=s.term(p[1],p[2],base); prevTerm=True
    def signatures(s,sigs,afterTable):
        if not sigs: return
        base=s.cursor+(30.0 if afterTable else 32.25)
        mx=max(len(g['lines']) for g in sigs); bh=75.75+39.0+max(0,mx-3)*14+6
        if base+bh>s.contentBottom: s.newPage(); base=s.contBase
        f=times(10.5,True,True); cols=[(48.75,43.5,225.75,120.75),(331.5,326.25,225.0,403.5)]; offs=[11.25,24.75,39.0]; low=base
        for i,g in enumerate(sigs[:2]):
            tx,rx,rw,cx=cols[i]; s.text(g['heading'],tx,base,f); ry=base+75.75; s.fill(rx,ry,rw,0.75,BLACK)
            for j,(t,colon,val) in enumerate(g['lines']):
                lb=ry+(offs[j] if j<3 else 39.0+(j-2)*14); s.text(t,tx,lb,f)
                if colon:
                    s.text(':',cx,lb,f)
                    if val: s.text(val,cx+8,lb,f)
                low=max(low,lb)
        s.cursor=low
    def closing(s,line):
        base=s.cursor+69.0
        if base>s.contentBottom: s.newPage(); base=s.contBase
        s.text(line,W/2,base,times(10.5,italic=True),align='center'); s.cursor=base
    def generate(s,doc):
        if any(sec.get('newPageUnlessSinglePage') for sec in doc['sections']):
            trial=Gen(); trial.layOut(doc); s.documentIsLong=trial.pageNumber>1
        return s.layOut(doc)
    def layOut(s,doc):
        s.begin(); s.opening(doc); s.table(doc); s.sections(doc['sections']); s.signatures(doc['signatures'],not doc['sections'])
        if doc.get('closing'): s.closing(doc['closing'])
        s.end(); return s.pages

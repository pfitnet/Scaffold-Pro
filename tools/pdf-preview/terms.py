# Same rules as formattedParagraphs() in main.swift: the terms' items
# ("(i) Payment : …", "• …") and plain paragraphs. Used by docs.py and sheet.py.
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

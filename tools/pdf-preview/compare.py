# Puts the sample quotation (docs/reference) and the rendered preview side by
# side, and prints how far each header/footer/body element is from the sample,
# in pixels (1 px = 0.75 pt). Run docs.py first.
import os
import numpy as np
from PIL import Image
HERE=os.path.dirname(os.path.abspath(__file__)); REF=os.path.join(HERE,'..','..','docs','reference'); OUT=os.path.join(HERE,'out')
# The page-1 screenshot has a 3px preview border at the top; page 2 has none.
pages=[('Qt26193-page1.png','quotation_1.png',3),('Qt26193-page2.png','quotation_2.png',0)]
def box(im,x0,y0,x1,y1):
    m=im[y0:y1,x0:x1].sum(axis=2)<600; ys,xs=np.where(m)
    return (x0+xs.min(),y0+ys.min(),x0+xs.max(),y0+ys.max()) if len(xs) else None
regions={'header logo':(40,30,460,103),'header rule':(240,103,792,108),'footer rule':(40,1054,760,1062),'footer text':(150,1063,760,1108)}
for ref,rendered,top in pages:
    s=Image.open(os.path.join(REF,ref)).convert('RGB').crop((0,top,792,1119+top))
    p=Image.open(os.path.join(OUT,rendered)).convert('RGB').crop((0,0,792,1119))
    side=Image.new('RGB',(1584,1119),'white'); side.paste(s,(0,0)); side.paste(p,(792,0))
    side.save(os.path.join(OUT,'compare_'+rendered))
    S,P=np.array(s).astype(int),np.array(p).astype(int)
    print(ref)
    for name,r in regions.items():
        a,b=box(S,*r),box(P,*r)
        print(f'  {name:12s} sample {a} render {b} diff', None if not(a and b) else tuple(int(b[i]-a[i]) for i in range(4)))

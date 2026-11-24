"""Hand trace of the central register of the Friends of Notre-Dame reference.
Reference coordinates use a 640 x 426 working copy. No photo pixels are shipped.
The photograph crops the circumference; outer registers below are reconstructed.
"""
from pathlib import Path
from PIL import Image, ImageDraw
from math import cos, sin, pi
import random

SIZE=1536
im=Image.new('RGB',(SIZE,SIZE),'#1c2130'); draw=ImageDraw.Draw(im)
# Outline of the lobed light directly below the hub (photo pixels, clockwise).
trace=[(286,297),(289,289),(296,282),(306,280),(315,282),(323,289),(326,298),(337,298),(346,302),(354,311),(357,320),(355,329),(348,336),(339,340),(330,340),(327,349),(319,358),(310,362),(301,360),(292,354),(287,343),(276,342),(268,338),(262,331),(260,322),(263,313),(270,304),(278,298)]
# Halo, head and silhouette sampled from the same panel, not a bitmap decal.
robe=[(299,305),(305,302),(313,303),(317,311),(327,321),(333,321),(330,330),(318,325),(320,344),(324,350),(311,355),(297,350),(292,349),(298,335),(298,324),(290,333),(283,327),(287,322)]
palette=['#343583','#2853a0','#782a51','#c54749','#cc9146','#40726b','#959fc6']
def panel(cx,cy,rad,angle,variant,central=False):
    # Map photo landmarks to a local panel, then place it on the rose.
    def pts(coords):
        out=[]
        for x,y in coords:
            x=(x-308)/48*rad;y=(y-321)/41*rad
            out.append((cx+x*cos(angle)-y*sin(angle),cy+x*sin(angle)+y*cos(angle)))
        return out
    def poly(coords,color,width=1):
        q=pts(coords);draw.polygon(q,fill=color);draw.line(q+[q[0]],fill='#30283b',width=width)
    def oval(x,y,rx,ry,col):poly([(x+rx*cos(i*pi/20),y+ry*sin(i*pi/20)) for i in range(40)],col)
    poly(trace,'#d39b66',3);poly([(308+(x-308)*.92,321+(y-321)*.92) for x,y in trace],'#334c96',2)
    for k in range(11):
        a=2*pi*k/11;oval(308+29*cos(a),321+22*sin(a),2.3,3.4,palette[(k+variant)%7])
    oval(307,300,9,9,'#d5ac55');oval(307,301,5.1,6.6,'#e7c19b');poly(robe,['#b9424d','#c6b288','#618974','#916a97'][variant%4],2)
    poly([(298,308),(302,306),(318,322),(315,343),(310,349),(312,326)],'#e1cfa5');
    for path in [[(295,344),(301,330),(304,323)],[(317,347),(313,342)],[(302,311),(311,316),(320,316)]]:draw.line(pts(path),fill='#382531',width=max(1,int(rad/55)))
    if central:draw.line(pts([(326,334),(328,305),(331,299)]),fill='#efc768',width=4)
C=SIZE/2;R=C*.985
# Lead and small vitreous tesserae separate the pictures; no borrowed colors/pixels.
rng=random.Random(14)
for lo,hi,n in [(.17,.31,48),(.31,.47,64),(.53,.68,90),(.72,.87,96),(.88,.99,120)]:
 for k in range(n):
    a=2*pi*k/n;b=2*pi*(k+1)/n;m=(a+b)*.5
    def p(r,t):return C+r*R*cos(t),C+r*R*sin(t)
    for aa,bb in [(a,m),(m,b)]:draw.polygon([p(lo,aa),p(hi,aa),p(hi,bb),p(lo,bb)],fill=rng.choice(palette),outline='#30283b',width=2)
for r,n,sz,phase in [(.46,12,.117,0),(.68,24,.073,.5),(.885,24,.104,0)]:
 for k in range(n):
    a=pi/2+2*pi*(k+phase)/n;panel(C+R*r*cos(a),C+R*r*sin(a),R*sz,a-pi/2,k)
for k in range(12):
 a=k*pi/6;x=C+.153*R*cos(a);y=C+.153*R*sin(a);rad=.024*R;draw.ellipse((x-rad,y-rad,x+rad,y+rad),fill=palette[k%7],outline='#bf9973',width=3)
panel(C,C,R*.128,0,0,True)
im.resize((1024,1024),Image.Resampling.LANCZOS).save(Path(__file__).with_name('rose_register.png'))
# Two upright lights: a lozenge quarry, jewelled borders, a gabled canopy
# and stacked figurative registers, using the photo-guided silhouette above.
im=Image.new('RGB',(768,960),'#292e48');draw=ImageDraw.Draw(im)
for k in range(2):
    left=k*384; cx=left+192
    for row in range(-1,23):
        for col in range(9):
            x=left+col*48+(row%2)*24;y=row*48
            draw.polygon([(x,y-48),(x+24,y),(x,y+48),(x-24,y)],fill=rng.choice(['#345981','#405785','#685278','#455e76']),outline='#30344b',width=3)
    for side in (-1,1):
        x=cx+side*154
        draw.rectangle((x-12,0,x+12,960),fill='#b99969',outline='#533f48',width=4)
        for y in range(0,960,38):draw.polygon([(x,y-14),(x+8,y),(x,y+14),(x-8,y)],fill='#8e3448')
    for y in (145,460,775):
        draw.line([(cx-123,y+82),(cx-123,y),(cx,y-121),(cx+123,y),(cx+123,y+82)],fill='#d0b48b',width=9)
        panel(cx,y+89,103,0,k+y//100)
    for y in (388,704,923):draw.line((left+36,y,left+348,y),fill='#3b3143',width=5)
im.save(Path(__file__).with_name('lancet_register.png'))

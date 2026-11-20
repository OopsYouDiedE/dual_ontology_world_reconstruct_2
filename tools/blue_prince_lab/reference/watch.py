"""Rest pose traced against the GPHG Halter 01 oblique / 02 profile photographs.
The silver fork is pierced, the gold balance is edged with individual timing screws.
The chapter ring and two blued pointers stay on the case, outside the three cages.
"""
from math import cos,sin,pi,tau
import numpy as np
from mesh import Mesh

S='b5b5b2'; HI='e4e2d9'; DARK='4b4a49'; BLUE='224d76'; GOLD='d5ac58'; RUBY='9c3c69'

def wheel(m,c,r,teeth,col):
    x,y,z=c; pts=[]
    for i in range(teeth):
        for frac,k in [(0,.83),(.43,1),(.63,1)]:
            a=tau*(i+frac)/teeth;pts.append((x+r*k*cos(a),y+r*k*sin(a)))
    for i,(X,Y) in enumerate(pts):
        x2,y2=pts[(i+1)%len(pts)];a=np.arctan2(Y-y,X-x);b=np.arctan2(y2-y,x2-x);poly=[(x+.65*r*cos(a),y+.65*r*sin(a)),(X,Y),(x2,y2),(x+.65*r*cos(b),y+.65*r*sin(b))]; hi=[(*v,z+.017) for v in poly];lo=[(*v,z-.017) for v in poly]
        m.face(hi,col,'metal');m.face([lo[1],lo[2],hi[2],hi[1]],col,'metal')
    for i in range(5):
        a=tau*i/5;m.board((x,y,z),(x+.76*r*cos(a),y+.76*r*sin(a),z),r*.10,.029,col)

def screw(m,x,y,z,r):
    m.rod((x,y,z),(x,y,z+.015),r,HI,10,mat='metal');m.board((x-r*.63,y-r*.36,z+.017),(x+r*.63,y+r*.36,z+.017),r*.21,.006,DARK)

def watch():
    m=Mesh()
    # Raised polished case, recessed midnight well, sloping ivory chapter ring and stepped bezel.
    for r,R,z,d,c in [(1.17,1.31,-.23,.26,'858887'),(1.25,1.34,-.11,.095,'c6c9c7'),(1.26,1.32,-.052,.050,HI),(1.23,1.27,-.07,.07,'363b40'),(.87,1.23,-.105,.065,'d9d5c8'),(.823,.871,-.15,.10,'ada99d'),(.784,.829,-.22,.10,'6d6f6a'),(.73,.79,-.26,.12,'43516a')]:m.ring((0,0,z),r,R,d,c,36,mat='metal')
    m.rod((0,0,-.39),(0,0,-.37),1.225,'252b34',64)
    m.ring((0,0,-.067),1.110,1.117,.006,DARK,40);m.ring((0,0,-.068),1.163,1.17,.005,DARK,40)
    for i in range(60):
        a=tau*i/60; r=1.087 if i%5==0 else 1.111;m.board((r*cos(a),r*sin(a),-.062),(1.168*cos(a),1.168*sin(a),-.062),.013 if i%5==0 else .007,.004,DARK)
    for a in [.45,2.02,3.6,5.15]:
        x=.966*cos(a);y=.966*sin(a);m.rod((x,y,-.072),(x,y,-.039),.050,'bebbb0',8,mat='metal')
    # Peripheral forked minute / hour pointers span the dial without a central arbor.
    for a,W,name in [(3.53,.043,"MinuteHand"),(5.45,.124,"HourHand")]:
        hand=Mesh()
        def pos(rad,w):return (rad*cos(a)-w*sin(a),rad*sin(a)+w*cos(a))
        for s in [-1,1]:hand.slab([pos(.67,0),pos(.72,s*.023),pos(1.11,s*W),pos(1.228,s*W)],.040,.019,'263778','metal')
        hand.slab([pos(1.11,-W),pos(1.11,W),pos(1.228,W),pos(1.228,-W)],.04,.019,'293777','metal')
        hand.save(name)
    m.rod((1.27,-.03,-.22),(1.46,-.03,-.22),.145,'979997',24,mat='metal');
    for i in range(8):
        a=tau*i/8;m.rod((1.35,-.03+.145*cos(a),-.22+.145*sin(a)),(1.41,-.03+.145*cos(a),-.22+.145*sin(a)),.035,DARK,8)
    # Black strap roots, four rounded attachment lugs and slotted pins flank the bezel.
    for v in [-1,1]:
        m.box((0,v*1.24,-.33),(.92,.63,.15),'302e30')
        for h in [-1,1]:
            m.slab([(h*.43,v*1.1),(h*.75,v*.95),(h*.69,v*1.32),(h*.54,v*1.45),(h*.44,v*1.39)],-.255,.19,'acafaf','metal')
            m.rod((h*.58,v*1.30,-.18),(h*.58,v*1.30,-.145),.073,'686b70',8,mat='metal')
    m.save('Case')
    m=Mesh();# The thick blue swing is behind the moving steel cage; both ends carry bearings.
    for z in [-.19,.02]:m.ring((0,.02,z),.635,.773,.092,BLUE,19,pi*1.05,pi*1.97,'metal',.83)
    for s in [-1,1]:
        m.slab([(s*.63,-.23),(s*.77,-.13),(s*.778,.12),(s*.66,.19),(s*.62,.06)],-.09,.29,BLUE,'metal');m.rod((s*.58,.031,-.06),(s*.79,.031,-.06),.089,'94979b',12,mat='metal');
    m.save('BlueSwing')
    m=Mesh();# Silver lower U has two mounting screws and a large open triangular void.
    m.ring((0,.015,.096),.346,.429,.062,S,20,pi*.99,pi*2.01,'metal',.86)
    for s in [-1,1]:
        m.slab([(s*.35,-.11),(s*.432,-.15),(s*.52,.045),(s*.60,.09),(s*.60,.17),(s*.42,.15)],.035,.074,S,'metal');screw(m,s*.291,-.238,.136,.041)
    for x,rad,n,z in [(.361,.174,21,-.07),(-.244,.236,19,-.035),(.026,.203,17,-.134)]:wheel(m,(x,.087,z),rad,n,'adac9f')
    # Vertical bevel wheel has visible thickness and a toothed edge when seen obliquely.
    side=Mesh();wheel(side,(0,0,0),.202,25,'c9ad68');
    for mat,faces in side.faces.items():
        for tri,col in faces:m.face([(.61+z,.063+y,-.066-x) for x,y,z in tri],col,mat)
    m.save('SilverCarrier')
    m=Mesh();m.ring((0,0,.145),.306,.327,.045,GOLD,24,mat='metal')
    for i in range(4):
        a=tau*i/4+.22;m.board((.034*cos(a),.034*sin(a),.137),(.31*cos(a),.31*sin(a),.137),.025,.025,GOLD)
    for i in range(10):
        a=tau*i/10;m.rod((.32*cos(a),.32*sin(a),.145),(.342*cos(a),.342*sin(a),.145),.019,'e6ca84',6,mat='metal')
    # Hairspring: spiral ribbon with daylight between successive coils.
    points=[]
    for i in range(73):
        a=tau*i/18;r=.032+i*.00158;points.append((r*cos(a),r*sin(a),.168))
    for p,q in zip(points,points[1:]):
        m.face([p,q,(q[0],q[1],q[2]+.014),(p[0],p[1],p[2]+.014)],'858b90','metal')
    m.save('Balance')
    # Stationary bridge across the balance + splayed fork cut-outs at either end.
    m=Mesh()
    for s in [-1,1]:
        for k in [-1,1]:m.slab([(s*.071,k*.048),(s*.145,k*.061),(s*.410,k*.095),(s*.43,k*.114),(s*.17,k*.095),(s*.078,k*.088)],.235,.050,S,'metal')
        m.slab([(s*.4,-.105),(s*.465,-.116),(s*.48,.12),(s*.402,.105)],.236,.066,'a8abad','metal');screw(m,s*.45,.006,.271,.038)
    for r,R,z,c in [(.062,.114,.237,S),(.045,.077,.267,HI),(.031,.046,.272,'a79b76')]:m.ring((0,0,z),r,R,.026,c,20,mat='metal')
    m.rod((0,0,.25),(0,0,.29),.034,RUBY,12,mat='metal');m.save('ForkBridge')

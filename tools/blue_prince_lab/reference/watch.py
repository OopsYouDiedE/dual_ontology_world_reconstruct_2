"""Rest pose traced against the GPHG Halter 01 oblique / 02 profile photographs.
The silver fork is pierced, the gold balance is edged with individual timing screws.
The chapter ring and two blued pointers stay on the case, outside the three cages.
"""
from math import cos,sin,pi,tau
import numpy as np
from mesh import Mesh

S='b5b5b2'; HI='e4e2d9'; DARK='4b4a49'; BLUE='224d76'; GOLD='d5ac58'; RUBY='9c3c69'

def cog(m, r, n, z, c, *, phase=0, escape=False, cone=0):
    """One toothed rim with open spokes. r is the pitch radius, not the tip."""
    module=2*r/n; root=r-module*.52; tip=r+module*.48
    profile=[(-.24,root),(.05,tip),(.18,tip)] if escape else [(-.32,root),(-.14,tip),(.14,tip),(.32,root)]
    # Both pitch cones converge on the intersection of the two arbors.
    for j in range(n):
        arc=[(phase+tau*(j+f)/n,v) for f,v in profile+[(1+profile[0][0],root)]]
        pt=lambda a,R,h:(R*cos(a),R*sin(a),z+h)
        front=[pt(a,v,0) for a,v in arc]; back=[pt(a,v*(.86 if cone else 1),cone or -.012) for a,v in arc]
        A,B=arc[0][0],arc[-1][0]; rim=r*.72
        for k in range(len(arc)-1):m.face([front[k],back[k],back[k+1],front[k+1]],c,'metal')
        # Fan from the inside of each sector, retaining tooth valleys on both faces.
        for face,h,rev in [(front,0,False),(back,cone or -.012,True)]:
            inner=rim*(.86 if cone and rev else 1); pts=[pt(A,inner,h)]+face+[pt(B,inner,h)]
            m.face(pts[::-1] if rev else pts,c,'metal')
        m.face([pt(B,rim,0),pt(A,rim,0),pt(A,rim*(.86 if cone else 1),cone or -.012),pt(B,rim*(.86 if cone else 1),cone or -.012)],c,'metal')
    for j in range(3):
        a=tau*j/3; u=np.array([cos(a),sin(a)]); v=np.array([-u[1],u[0]])*r*.07
        m.slab([v,-v,u*r*.76-v,u*r*.76+v],z-.005,.009,c,'metal')

def shaft(m,x,y,a,b,r,c):m.rod((x,y,a),(x,y,b),r,c,6 if r<=.02 else 8,mat='metal')

def train():
    # Positions here are arbor-local. Node pivots and the locked-train ratios are in Meridian.gd.
    m=Mesh(); cog(m,.144,54,0,GOLD,cone=-.024*.14); shaft(m,0,0,-.005,.08,.024,S); m.save('FixedBevel')
    m=Mesh(); cog(m,.024,9,.144,S,phase=pi/9,cone=-.144*.14); cog(m,.30,24,-.245,GOLD,phase=pi/24); shaft(m,0,0,-.26,.15,.019,S);m.save('TransferArbor')
    m=Mesh(); cog(m,.20,16,-.245,S); shaft(m,0,0,-.26,-.055,.022,S)
    for sign in [-1,1]:
        m.rod((0,0,-.065),(sign*.45,0,-.065),.021,S,6,mat='metal');shaft(m,sign*.45,0,-.075,.237,.018,S)
    m.save('CageDrive')
    m=Mesh();cog(m,.24,32,-.118,S);m.save('FixedSun')
    m=Mesh();cog(m,.06,8,-.118,GOLD,phase=pi/8);cog(m,.12,16,-.019,GOLD);shaft(m,0,0,-.14,.056,.014,S);m.save('PlanetArbor')
    m=Mesh();cog(m,.06,8,-.019,S,phase=pi/8);cog(m,.126,15,.058,GOLD,escape=True,phase=-tau*.18/15);shaft(m,0,0,-.05,.077,.012,S);m.save('EscapeArbor')
    m=Mesh(); # local lever pivot: set the locking face of each pallet on its banked tooth tip.
    def turn(v,a):return np.array([v[0]*cos(a)-v[1]*sin(a),v[0]*sin(a)+v[1]*cos(a)])
    pivot=np.array([.15,.075]); direction=pivot/np.linalg.norm(pivot); normal=np.array([-direction[1],direction[0]])
    for deg,bank in [(240,.11),(156,-.11)]:
        u=turn(np.array([1,0]),deg*pi/180); end=turn(np.array([.30,.18])+(.126+.48*.252/15)*u-pivot,-bank)
        m.rod((0,0,.066),(*end,.066),.009,S,6,mat='metal');v=turn(u,-bank);w=np.array([-v[1],v[0]])
        m.slab([end+w*.007,end-w*.007,end+v*.014-w*.007,end+v*.014+w*.007],.055,.019,RUBY,'metal')
    throat=-pivot+direction*.074
    m.rod((0,0,.071),(*throat,.089),.012,GOLD,6,mat='metal')
    for sign in [-1,1]:m.rod((*(throat+sign*normal*.009),.089),(*(-pivot+direction*.042+sign*normal*.016),.089),.006,GOLD,6,mat='metal')
    shaft(m,0,0,.037,.089,.011,S);m.save('PalletLever')

def screw(m,x,y,z,r):
    m.rod((x,y,z),(x,y,z+.015),r,HI,10,mat='metal');m.board((x-r*.63,y-r*.36,z+.017),(x+r*.63,y+r*.36,z+.017),r*.21,.006,DARK)

def watch():
    train()
    m=Mesh()
    # Raised polished case, recessed midnight well, sloping ivory chapter ring and stepped bezel.
    # One continuous turned shell: retain each visible ledge, omit the buried
    # radial walls and caps of overlapping cylinders. Deep cup clears the cage.
    profile=[(1.17,-.36,'858887'),(1.31,-.36,'858887'),(1.31,-.16,'858887'),
             (1.34,-.157,'c6c9c7'),(1.34,-.063,'c6c9c7'),(1.32,-.063,HI),
             (1.32,-.027,HI),(1.26,-.027,HI),(1.26,-.036,'363b40'),
             (1.23,-.036,'363b40'),(1.23,-.073,'d9d5c8'),(.87,-.073,'d9d5c8'),
             (.87,-.10,'ada99d'),(.823,-.10,'ada99d'),(.823,-.20,'6d6f6a'),
             (.851,-.22,'43516a'),(.851,-.32,'43516a'),(.85,-.375,'252b34'),(.85,-.712,'252b34')]
    for (r,z,_),(R,Z,col) in zip(profile,profile[1:]):
        for i in range(48):
            a=tau*i/48;b=tau*(i+1)/48
            m.face([(r*cos(a),r*sin(a),z),(r*cos(b),r*sin(b),z),(R*cos(b),R*sin(b),Z),(R*cos(a),R*sin(a),Z)],col,'metal')
    m.face([(.85*cos(tau*i/48),.85*sin(tau*i/48),-.712) for i in range(48)],'252b34','metal')
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
    m.ring((0,.015,-.335),.346,.429,.062,S,20,pi*.99,pi*2.01,'metal',.86)
    for s in [-1,1]:
        m.slab([(s*.35,-.11),(s*.432,-.15),(s*.52,.045),(s*.60,.09),(s*.60,.17),(s*.42,.15)],-.33,.074,S,'metal');screw(m,s*.291,-.238,-.298,.041)
    # Lower bearing plate fixes the sun and carries the perpendicular transfer spindle.
    for sign in [-1,1]:
        m.rod((sign*.605,0,0),(sign*.60,.14,-.33),.026,S,6,mat='metal')
        m.rod((sign*.60,.14,-.33),(sign*.42,0,-.33),.028,S,6,mat='metal')
    m.rod((-.42,0,-.33),(.5,0,-.33),.032,S,8,mat='metal');shaft(m,.5,0,-.33,-.26,.026,S)
    shaft(m,0,0,-.33,-.257,.04,S);m.rod((-.34,0,-.33),(-.28,0,-.149),.015,S,6,mat='metal');m.rod((-.28,0,-.149),(0,0,-.149),.018,S,6,mat='metal');shaft(m,0,0,-.15,-.121,.033,S)
    m.save('SilverCarrier')
    m=Mesh();m.ring((0,0,.145),.306,.327,.045,GOLD,24,mat='metal')
    for i in range(4):
        a=tau*i/4+.22;m.board((.034*cos(a),.034*sin(a),.137),(.31*cos(a),.31*sin(a),.137),.025,.025,GOLD)
    for i in range(10):
        a=tau*i/10;m.rod((.32*cos(a),.32*sin(a),.145),(.342*cos(a),.342*sin(a),.145),.019,'e6ca84',6,mat='metal')
    shaft(m,0,0,.076,.247,.017,S);shaft(m,0,0,.244,.263,.009,S);shaft(m,0,0,.126,.151,.044,GOLD);shaft(m,0,0,.098,.105,.063,GOLD);shaft(m,.054,.027,.081,.101,.007,RUBY)
    shaft(m,0,0,.164,.188,.033,'969a9c') # moving collet grips inner spring end
    m.save('Balance')
    # Stationary bridge across the balance + splayed fork cut-outs at either end.
    m=Mesh()
    for s in [-1,1]:
        for k in [-1,1]:m.slab([(s*.071,k*.048),(s*.145,k*.061),(s*.410,k*.095),(s*.43,k*.114),(s*.17,k*.095),(s*.078,k*.088)],.235,.050,S,'metal')
        m.slab([(s*.4,-.105),(s*.465,-.116),(s*.48,.12),(s*.402,.105)],.236,.066,'a8abad','metal');screw(m,s*.45,.006,.271,.038)
    for r,R,z,c in [(.062,.114,.237,S),(.045,.077,.267,HI),(.031,.046,.272,'a79b76')]:m.ring((0,0,z),r,R,.026,c,20,mat='metal')
    shaft(m,.15,0,.178,.231,.009,S) # spring stud and its lug on the pierced bridge
    m.rod((.15,0,.231),(.15,.078,.231),.012,S,6,mat='metal')
    # Under-balance bearing bar, with bearings for both train arbors and the lever.
    for x,y,h in [(.30,0,.056),(.30,.18,.077),(.15,.075,.089)]:
        m.rod((.45,0,.110),(x,y,.110),.008,S,6,mat='metal');shaft(m,x,y,h,.110,.013,S)
    m.rod((0,0,.25),(0,0,.29),.034,RUBY,12,mat='metal');m.save('ForkBridge')

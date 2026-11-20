"""Interior carpentry and masonry. Openings are holes in the shell, with independent reveals."""
import random
from math import sin,cos,tau,pi,sqrt
from mesh import Mesh,Scene,shade

WOOD='524239'; IRON='343438'; STONE='62616d'

def glass_bay(variant=0):
    # Local opening: front +Z, 1.20 m wide, with a round head. Lead lines are the gaps
    # between coloured facets and the projecting lead came around the figure's panels.
    m=Mesh(); xlim=.61; spring=3.66; bottom=1.37; top=4.27; rng=random.Random(6)
    for s in [-1,1]:m.box((s*.973,2.5,0),(.726,5,.30),STONE)
    m.box((0,bottom/2,0),(1.22,bottom,.30),STONE);m.box((0,(5+top)/2,0),(1.22,5-top,.30),STONE)
    for i in range(20):
        a=pi*i/20;b=pi*(i+1)/20;x1=xlim*cos(a);x2=xlim*cos(b);y1=spring+xlim*sin(a);y2=spring+xlim*sin(b)
        m.slab([(x1,y1),(x2,y2),(x2,top),(x1,top)],0,.30,STONE)
    m.ring((0,spring,.155),.601,.67,.108,'393b47',22,0,pi)
    for s in [-1,1]:m.box((s*.634,(spring+bottom)/2,.155),(.065,spring-bottom,.11),'393b47')
    m.box((0,bottom,.16),(1.44,.11,.22),'514e55');m.box((0,bottom-.10,.13),(1.34,.11,.19),'77727b')
    # Glass fields stop at the semicircle. Use pairs of triangles split along alternating diagonals.
    def point(i,j):
        x=(i/8-.5)*1.2; upper=spring+sqrt(max(0,.60**2-x*x));y=bottom+(upper-bottom)*j/15
        if 0<i<8 and 0<j<15:
            r=random.Random(i*91+j*171);x+=r.uniform(-.045,.045);y+=r.uniform(-.069,.069)
        return x,y
    palette=['a598b8','9baabe','cad2d2','8484a3','a7a8bc','d3c9d6','97b0ba']
    for i in range(8):
        for j in range(15):
            a,b,c,d=[point(*p) for p in [(i,j),(i+1,j),(i+1,j+1),(i,j+1)]]
            for tri in [(a,b,c),(a,c,d)] if (i+j)%2 else [(a,b,d),(b,c,d)]:
                cx=sum(q[0] for q in tri)/3;cy=sum(q[1] for q in tri)/3;colour=rng.choice(palette)
                if ((cx+.04)/.51)**2+((cy-3.70)/.45)**2<1:colour=rng.choice(['ffce80','ffd893','e4ac64','f4c674'])
                if i in (0,7):colour=rng.choice(['e4c27d','c8aa74','f2dbab'])
                m.face([(cx+(x-cx)*.95,cy+(y-cy)*.95,-.037) for x,y in tri],colour,'glass')
    # Draw the lead behind each pane; contour comes from each pane's actual perimeter.
    m.slab([(-.602,bottom),(.602,bottom),(.602,spring),(-.602,spring)],-.053,.012,'2c2638');m.ring((0,spring,-.054),.001,.601,.012,'2c2638',22,0,pi)
    z=-.024
    def panel(poly,c):
        nonlocal z
        if variant and c in ("bf3834","d24a40"): c=(["675879","81678d"] if variant==1 else ["3e6473","527784"])[int(c=="d24a40")]
        if variant==1: poly=[(-x,y) for x,y in poly]
        z+=.0013;m.face([(x,y,z) for x,y in poly],c,'glass')
        for p,q in zip(poly,poly[1:]+poly[:1]):m.board((*p,z+.0004),(*q,z+.0004),.011,.001,'3e3441')
    if variant == 0:
        from portrait import portrait
        portrait(panel)
        m.save('LeadedBay')
        return
    for s in [-1,1]:
        for k in range(5):
            x=s*(.24+k*.045);panel([(s*.11,3.51),(x,3.49-k*.095),(s*(.56-k*.012),2.72-k*.14),(s*(.53-k*.046),2.29-k*.12),(s*.19,2.90)],['f8f1dd','e6e6de','c5c6d0','f4eee1','d5d7d7'][k])
    panel([(-.20,2.71),(.19,2.73),(.15,2.12),(.04,1.70),(-.05,1.68),(-.07,2.15),(-.17,1.89),(-.24,1.93)],'e5dcca')
    for x,y in [(-.155,1.92),(.016,1.70)]:panel([(x-.056,y+.14),(x+.055,y+.12),(x+.048,y-.03),(x-.09,y-.052)],'514a50')
    panel([(-.09,3.56),(-.24,3.43),(-.27,3.08),(-.22,2.63),(.21,2.62),(.19,3.31),(.09,3.51)],'bf3834')
    panel([(-.14,3.48),(-.07,3.54),(.09,3.52),(.14,3.42),(-.025,3.22)],'f0e7d5');panel([(-.04,3.48),(.01,3.48),(.04,3.30),(-.016,3.23),(-.05,3.71)],'3b3940')
    panel([(.12,3.40),(.24,3.31),(.26,3.03),(.16,2.97),(-.11,3.00),(-.10,3.09),(.11,3.12)],'d24a40');panel([(-.13,3.09),(-.06,3.10),(-.06,3.0),(-.15,3.01)],'e2b58a')
    panel([(-.10,3.78),(.07,3.81),(.12,3.66),(.055,3.53),(-.014,3.49),(-.12,3.60)],'d9af8c');panel([(-.155,3.72),(-.121,3.84),(-.001,3.90),(.091,3.86),(.15,3.76),(.064,3.78),(-.005,3.72),(-.05,3.61),(-.09,3.56)],'574655')
    # Tunic pleats, lapels, hair, eyes and wing barbs remain legible in the near bay.
    for x in [-.18,-.105,.07,.14]: panel([(x,3.03),(x+.016,2.70),(x-.017,2.64)],'a13a3a' if not variant else '57546b')
    for k in range(3):
        y=2.82+k*.085;panel([(-.07,y),(-.052,y+.01),(-.043,y-.009),(-.064,y-.016)],'d8b469')
    for x in [-.078,.021]:panel([(x,3.701),(x+.045,3.70),(x+.015,3.683)],'574651')
    panel([(-.013,3.695),(-.040,3.625),(-.002,3.617)],'b48771');panel([(-.047,3.581),(.029,3.589),(-.014,3.565)],'936c66')
    for i in range(5):
        x=-.12+i*.041;panel([(x,3.78),(x+.053,3.839),(x+.025,3.77),(x-.025,3.721)],'716064')
    for side in [-1,1]:
        for i in range(7):
            x=.27+.027*i;y=3.24-.069*i;panel([(side*x,y),(side*(x+.087),y-.26),(side*(x+.133),y-.57),(side*(x+.084),y-.49)],'dedde1')
    m.save(['LeadedBay','VioletBay','BlueBay'][variant])

def pew():
    m=Mesh();m.box((0,.49,0),(2.65,.10,.56),'503a38');m.box((0,.56,.01),(2.57,.096,.50),'a14244');m.box((0,.87,-.26),(2.66,.62,.102),'4e3b3c');m.box((0,1.19,-.26),(2.73,.08,.13),'705452');
    for s in [-1,1]:
        x=s*1.28;m.box((x,.32,-.14),(.11,.63,.19),'45383c');m.box((x,.24,.20),(.11,.48,.14),'49383c');m.box((x,.075,.01),(.18,.13,.76),'685050');m.box((x,.66,.03),(.12,.11,.59),'64484a');m.rod((x,1.12,-.26),(x,1.30,-.29),.086,'745858',8,.062)
    m.save('Pew')

def chapel():
    for variant in range(3): glass_bay(variant)
    pew();sc=Scene('Chapel');m=Mesh();rng=random.Random(47)
    for i in range(8):
        for j in range(11):m.box(((i-3.5)*1.32,-.09,(j-5)*1.12),(1.31,.18,1.11),shade('96929b',rng.uniform(.89,1.04)))
    m.box((0,.023,.26),(10.46,.044,1.63),'9a3a40');
    for side in [-1,1]:
        for x in [-3.75,-2.43,-1.11,.21,1.53]:sc.add('Pew',(x,0,side*2.44),pi/2)
    for j in range(5):sc.add(['VioletBay','BlueBay','LeadedBay'][j%3],(5.28,0,5.34-j*2.672),-pi/2,(1,1.10,1))
    # Opposite the hero window: a real recessed door below a high, wider painted light.
    for z in [-4.74,4.67]:sc.add('VioletBay',(-5.28,0,z),pi/2,(1.31,1.10,1))
    span=1.27;center=-.16
    for z0,z1 in [(-3.1,center-span),(center+span,3.06)]:m.box((-5.28,2.75,(z0+z1)/2),(.31,5.50,z1-z0),STONE)
    for side in [-1,1]:m.box((-5.28,1.53,center+side*.995),(.32,3.06,.56),STONE)
    m.box((-5.28,2.82,center),(.33,.48,1.44),STONE)
    m.box((-5.42,1.24,center),(.12,2.47,1.42),'493a42');m.box((-5.30,1.24,center),(.06,2.38,1.29),'5a4852')
    for j in range(6):m.box((-5.25,1.15,center+(j-2.5)*.209),(.032,2.18,.194),'50414c')
    sc.add('BlueBay',(-5.28,1.86,center),pi/2,(.97,.73,1))
    for y in [.19,2.87,3.07]:m.box((-5.06,y,-.09),(.19,.12,6.12),'4c4956')
    sc.add('LeadedBay',(4.08,0,1.40),-.90,(1,1.14,1))
    for j in range(3):m.box((3.04,1.84+j*.092,1.92),(.86+.11*j,.085,.46+.10*j),'535360',-.9)
    m.box((3.04,.91,1.92),(.68,1.82,.39),'4c4956',-.9)
    for x,z in [(2.96,1.84),(-4.96,1.08),(-1.94,-5.01),(1.86,-5.01)]:
        m.rod((x,.04,z),(x,2.14,z),.042,'675341',8);m.rod((x,.04,z),(x,.16,z),.14,'7d6652',8,.065);m.rod((x,2.04,z),(x,2.25,z),.09,'b89867',8,.064);m.rod((x,2.24,z),(x+.018,2.36,z),.04,'ffc16c',6,.004,'glass')
    for x in [-3.944,3.944]:sc.add('LeadedBay',(x,0,-6.20),0,(1,1.10,1))
    # Door recess, timber leaves, hood and two freestanding sculptural niches.
    for s in [-1,1]:m.box((s*1.74,2.75,-6.2),(1.74,5.5,.32),STONE)
    m.box((0,4.45,-6.20),(1.78,2.10,.32),STONE);m.ring((0,2.53,-5.99),.79,.91,.19,'524c53',20,0,pi)
    for s in [-1,1]:m.box((s*.85,1.27,-5.99),(.12,2.54,.19),'524c53')
    for i in range(10):m.box(((i-4.5)*.161,1.25,-6.20),(.15,2.49,.13),shade('654d46',rng.uniform(.89,1.06)))
    for i in range(10):
        a=pi*i/10;b=a+pi/10;m.slab([(0,2.53),(.78*cos(a),2.53+.78*sin(a)),(.78*cos(b),2.53+.78*sin(b))],-6.16,.08,['c05d53','cc8a70','973f49'][i%3],'glass')
    for x in [-1.79,1.79]:
        m.box((x,1.16,-5.82),(.75,2.32,.65),'514852');m.box((x,2.32,-5.77),(.91,.14,.79),'88838a');m.rod((x,2.4,-5.85),(x+.03,3.21,-5.85),.24,'b1a8ad',8,.14);m.rod((x+.03,3.18,-5.85),(x,3.63,-5.84),.17,'aca3a7',7,.205);m.rod((x,3.61,-5.84),(x+.02,3.91,-5.84),.13,'c0b6b7',8,.10)
        for s in [-1,1]:m.rod((x+s*.16,3.56,-5.84),(x+s*.24,3.20,-5.75),.076,'b3aaab',7,.051)
    for i in range(25):
        x=(i-12)*.428;y=5.5+(5.3-abs(x))*.44

        m.box((x,(5.5+y)/2,-6.2),(.423,max(.02,y-5.5),.27),shade('5a515c',rng.uniform(.89,1.05)));m.box((x,y+.1,0),(.422,.19,13.1),shade('624e49',rng.uniform(.86,1.05)))
    for z in [-5.94,-2.75,.44,3.63,6.37]:
        m.box((0,5.27,z),(10.65,.26,.24),'483b3e');
        for s in [-1,1]:m.board((s*5.24,5.45,z),(0,7.84,z),.22,.27,'463a3f');m.board((s*4.98,5.29,z),(s*3.73,6.15,z),.15,.19,'4c3e40')
    m.save('ChapelShell');sc.add('ChapelShell');sc.save()

def attic():
    sc=Scene('Attic');m=Mesh();rng=random.Random(89);back=-4.95;window=(-1.02,2.96);r=.72;edge=.94
    for i in range(31):
        x=(i-15)*.293
        for j in range(4):m.box((x,-.065,-3.48+j*3.0+.03*(i%3)),(.282,.13,2.98),shade('776453',rng.uniform(.80,1.14)))
    # Build a square socket bounded by planks, then close only the corners around the circle.
    cx,cy=window
    for i in range(-2,34):
        x=-4.0+(i+.5)*.25; ymax=5.52-.55*abs(x); low=cy-edge if cx-edge-.12<x<cx+edge+.12 else ymax
        m.box((x,low/2,back),(.251,low,.15),shade('897568',rng.uniform(.9,1.08)))
        if low<ymax:m.box((x,(ymax+cy+edge)/2,back),(.251,ymax-cy-edge,.15),shade('897568',rng.uniform(.91,1.08)))
    for i in range(40):
        a=tau*i/40;b=tau*(i+1)/40
        def pt(t,length):return (cx+length*cos(t),cy+length*sin(t))
        def outer(t):return (edge+.24)/max(abs(cos(t)),abs(sin(t)))
        m.slab([pt(a,r),pt(a,outer(a)),pt(b,outer(b)),pt(b,r)],back,.15,'877569')
    shell=m;m=Mesh();cx=cy=back=0
    m.ring((cx,cy,back+.10),r,r+.078,.14,'463e37',40);m.ring((cx,cy,back+.18),r+.055,r+.10,.053,'68584b',40)
    for i in range(8):
        a=tau*i/8;m.board((cx,cy,back+.085),(cx+r*cos(a),cy+r*sin(a),back+.085),.040,.090,'635348')
    m.rod((cx,cy,back+.025),(cx,cy,back+.15),.075,'554638',10)
    m.save("SpokeWindow");sc.add("SpokeWindow",(*window,-4.95));m=shell;back=-4.95
    # Roof sheathing is continuous above the open trusses. Sloping boards carry physical gaps.
    for s in [-1,1]:
        for i in range(22):
            x=s*(i+.5)*.201;y=5.58-abs(x)*.94
            m.board((x-.101,y+s*.095,0),(x+.101,y-s*.095,0),.12,10.4,shade('65584d',rng.uniform(.77,1.1)))
        for y in [.16,1.27]:m.box((s*4.31,y,0),(.16,.16,10.42),'5b493f')
        m.box((s*4.38,.80,0),(.17,1.6,10.42),'6b584c')
    for z in [-4.72,-2.48,.22,2.88,4.99]:
        for s in [-1,1]:
            m.board((s*4.36,1.33,z),(0,5.56,z),.185,.25,'4e443e');m.box((s*2.84,1.40,z),(.19,2.80,.22),'54473d');m.board((s*2.84,1.8,z),(s*2.06,3.43,z),.10,.16,'635246')
        m.box((0,4.22,z),(2.79,.15,.22),'594b40')
    for y in [.13,1.38,4.06]:m.box((0,y,back+.13),(8.0,.12,.17),'645347')
    for x in [-3.88,-2.18,.62,1.64,3.71]:m.box((x,2.23,back+.16),(.14,4.48,.16),'5a4a3f')
    for xlo,xhi,ylo,yhi in [(-3.8,-2.27,1.46,3.14),(.19,1.54,1.46,3.90),(1.74,3.60,1.46,3.30),(-3.86,.56,.23,1.29)]:
        for k in range(-9,15):
            base_y=ylo+k*.24;lo=max(xlo,xlo+ylo-base_y);hi=min(xhi,xlo+yhi-base_y)
            if hi-lo>.02:m.board((lo,base_y+lo-xlo,back+.09),(hi,base_y+hi-xlo,back+.09),.212,.049,shade('806d61',rng.uniform(.86,1.04)))
    # Wing chair with separate projecting cheeks, rolled arms and tapered legs.
    x=-2.09;z=-3.0;m.box((x,.48,z),(.97,.21,.90),'42494b');m.box((x,1.09,z-.42),(.91,1.22,.16),'354749')
    for s in [-1,1]:
        m.box((x+s*.43,1.42,z-.32),(.14,.56,.32),'3b4b4a');m.box((x+s*.47,.74,z),(.12,.15,.85),'454e4c')
        for dz in [-.34,.32]:m.rod((x+s*.42,.02,z+dz),(x+s*.37,.45,z+dz*.85),.045,'494137',5,.064)
    def crate(x,y,z,w,h,d):
        m.box((x,y+h/2,z),(w,h,d),'756957');
        for s in [-1,1]:m.box((x+s*w*.4,y+h/2,z+d*.5),(.062,h+.012,.036),'504c44')
        m.box((x,y+h,z),(w+.032,.066,d+.03),'8d7a60')
    for spec in [(-1.40,0,-3.75,.69,.76,.80),(-1.33,.79,-3.78,.56,.32,.64),(2.52,0,-1.80,.79,1.03,.78),(2.49,1.04,-1.8,.62,.23,.61),(-3.3,0,-1.75,.77,.71,.67),(1.65,0,3.84,.92,.45,.65)]:crate(*spec)
    # Child's red wagon, raised bed and axles; the long handle crosses the lit back wall.
    x=.58;z=-3.05;m.box((x,.28,z),(.88,.15,.53),'813d33');
    for s in [-1,1]:m.box((x,.39,z+s*.245),(.89,.13,.055),'93483c');m.box((x+s*.424,.39,z),(.055,.13,.50),'8f493e')
    for dx in [-.31,.31]:
        for dz in [-.28,.28]:m.rod((x+dx,.14,z+dz-.036),(x+dx,.14,z+dz+.036),.13,'373c3b',10);m.rod((x+dx,.14,z+dz+.035),(x+dx,.14,z+dz+.042),.058,'817f72',8)
    m.rod((x+.41,.28,z),(x+.23,1.08,z-.08),.023,'514a40',6);m.box((x+.23,1.08,z-.08),(.16,.041,.045),'4a433b')
    # Landing rail in the lower right corner; front-right coat tree.
    for z in [.05,1.25,2.45,3.65]:m.box((1.44,.50,z),(.085,1,.085),'514940')
    for y in [.38,.96]:m.box((1.44,y,1.85),(.10,.089,3.71),'65574a')
    x=3.27;z=.15;m.rod((x,.03,z),(x,2.37,z),.059,'514b40',8,.042)
    for i in range(5):
        a=i*tau/5;dx=.27*cos(a);dz=.27*sin(a);m.rod((x,1.77,z),(x+dx,2.19,z+dz),.032,'635c4d',6);m.rod((x,.37,z),(x+dx,.02,z+dz),.041,'60574a',6)
    m.save('AtticJoinery');sc.add('AtticJoinery');sc.save()

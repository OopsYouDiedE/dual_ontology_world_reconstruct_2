"""Build an independent costume and retargetable mannequin from the external Blender Human Base Meshes bundle.
Run via Blender: -b --disable-autoexec --python build_detective.py -- /path/to/bundle.blend output-directory.
"""
import bpy, bmesh, json, math, sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from math import cos,sin,pi

src,out=map(Path,sys.argv[sys.argv.index('--')+1:]); out.mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
base='GEO-body_male_realistic'
with bpy.data.libraries.load(str(src),link=False) as (source,target):
    target.objects=[base]
# The asset places the figures on a display shelf; retain source object transforms before unlinking.
source={o.name:o for o in target.objects}
body0=source[base]
coords=[body0.matrix_world @ v.co for v in body0.data.vertices]
polys=[tuple(p.vertices) for p in body0.data.polygons]
if len(coords)!=10582: raise ValueError('Unexpected realistic male topology')
sole=min(range(len(coords)),key=lambda i:coords[i].z); skull=max(range(len(coords)),key=lambda i:coords[i].z); chin=8064
assert skull==8063, (skull,sole)
cx=coords[skull].x
head=1.77/6.5

def mix(a,b,t): return a+(b-a)*t
def smooth(a,b,x):
    t=max(0.,min(1.,(x-a)/(b-a)));return t*t*(3.-2.*t)
def interp(x,pairs):
    for (a,b),(c,d) in zip(pairs,pairs[1:]):
        if x<=c: return mix(b,d,(x-a)/(c-a))
    return pairs[-1][1]

def stature(p):
    x,y,z=p; x-=cx
    first=[(coords[sole].z,0),(.085,.094),(.415,.494),(.70,.776),(.91,.978), (1.15,1.218),(1.34,1.374),(coords[chin].z,1.77-head),(coords[skull].z,1.77)]
    arm=(1-smooth(1.30,1.41,z))*smooth(.17,.26,abs(x))*smooth(.66,.74,z)
    az=arm*(1-smooth(.77,1.32,z))
    face=smooth(1.37,1.52,z)
    x=x*mix(1.,1.19,face)-math.copysign(.046*az,x)
    # Widen the gonial and chin planes slightly while preserving the orbital volumes.
    x*=1+.085*math.exp(-((z-1.492)/.026)**2)*smooth(-.04,-.11,y)
    y=(y+.035)*mix(1,1.10,face)-.035 + .019*az
    z=interp(z,first)-.155*az
    return Vector((x,y,z))

V=[stature(v) for v in coords]
scene=bpy.context.scene

def material(name,color,rough=.86):
    m=bpy.data.materials.new(name); m.use_nodes=True
    c=[int(color[i:i+2],16)/255 for i in (0,2,4)]; c=tuple(a/12.92 if a<=.04045 else ((a+.055)/1.055)**2.4 for a in c)+(1,)
    m.diffuse_color=c
    b=m.node_tree.nodes.get('Principled BSDF'); b.inputs['Base Color'].default_value=c; b.inputs['Roughness'].default_value=rough; b.inputs['Specular IOR Level'].default_value=.22
    return m

skin=material('Skin | warm neutral','a17b68'); lips=material('Lips | restrained color','976857'); brow=material('Eye line | umber','372921'); sclera=material('Sclera | warm ivory','b9a99b'); iris=material('Iris | hazel','61503a'); pupil=material('Pupil','1e1a16')
coat=material('Coat | matte tobacco twill','564132'); lapel=material('Coat | lapel facing','5d4636'); lining=material('Coat | seam and liner','382b23'); vest=material('Waistcoat | forest wool','414d38'); vest_edge=material('Waistcoat | edge','2c3428'); white=material('Shirt | ivory poplin','ded6c0'); trousers=material('Trousers | charcoal wool','323234'); tie=material('Tie | dark midnight','292a30'); leather=material('Boot | russet leather','57402f'); sole_mat=material('Boot | heel and sole','302722'); brass=material('Buttons | aged brass','94764c',.65)
hair=[material('Hair | sculpted lock %s'%i,c) for i,c in enumerate(('382821','4a3529','51392c','493328','564031','402e24'))]

objects=[]
def mesh(name,vs,fs,mat,group=None,smooth_=True,recalc=True):
    me=bpy.data.meshes.new(name); me.from_pydata(vs,[],fs); me.update()
    if recalc:
        bm=bmesh.new();bm.from_mesh(me);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(me);bm.free()
    ob=bpy.data.objects.new(name,me); scene.collection.objects.link(ob);me.materials.append(mat)
    for p in me.polygons:p.use_smooth=smooth_
    if group is not None: objects.append((ob,group))
    return ob

def shell(ob,thickness=.004):
    mod=ob.modifiers.new('Pattern cloth thickness','SOLIDIFY');mod.thickness=thickness;mod.use_even_offset=True
    return ob

def loft(name,rings,mat,group,cap=False):
    N=len(rings[0]);R=len(rings); f=[(i*N+j,i*N+(j+1)%N,(i+1)*N+(j+1)%N,(i+1)*N+j) for i in range(R-1) for j in range(N)]
    if cap:f += [tuple(range(N-1,-1,-1)),tuple(range((R-1)*N,R*N))]
    return mesh(name,[v for r in rings for v in r],f,mat,group)

def disk_rings(data,N=32):
    return [[(x+rx*cos(2*pi*i/N),y+ry*sin(2*pi*i/N),z) for i in range(N)] for x,y,z,rx,ry in data]

def oval(name,loc,scale,mat,group):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=18,ring_count=10,location=loc)
    o=bpy.context.object;o.name=name; o.data.materials.append(mat);o.scale=scale
    bpy.ops.object.transform_apply(location=True,rotation=False,scale=True)
    for p in o.data.polygons:p.use_smooth=True
    objects.append((o,group));return o

def tube(name,p,r,mat,group,N=8):
    path=[Vector(v) for v in p];rings=[]
    for i,v in enumerate(path):
        D=(path[min(len(path)-1,i+1)]-path[max(0,i-1)]).normalized();axis=Vector((0,1,0))
        if abs(D.dot(axis))>.95:axis=Vector((0,0,1))
        U=D.cross(axis).normalized();W=D.cross(U).normalized(); rr=r if isinstance(r,(int,float)) else r[i]
        rings.append([v+rr*(cos(j*2*pi/N)*U+sin(j*2*pi/N)*W) for j in range(N)])
    return loft(name,rings,mat,group,True)

def panel(name,V,F,m,g,th=.003):return shell(mesh(name,V,F,m,g),th)

def subset(name,selected,m,g):
    ids=sorted(set(v for p in selected for v in p));idx={old:new for new,old in enumerate(ids)}
    return mesh(name,[V[i] for i in ids],[[idx[v] for v in p] for p in selected],m,g,recalc=False)

reference=mesh('Fitting body | CC0 Blender Human Base Meshes',V,polys,skin,recalc=False);reference.hide_render=True;reference.hide_set(True)
def visible_hand(p,s):
    return all(.26<s*V[i].x and V[i].z<.823 and  .66<coords[i].z<.94 for i in p)
neck_polys=[p for p in polys if all(V[i].z>1.416 for i in p)]
ob=subset('Face and neck',neck_polys,skin,'neckface')
for v in ob.data.vertices:
    x,y,z=v.co; k=1-smooth(1.451,1.491,z)
    v.co.x=mix(x,max(-.061,min(.061,x)),k)
    v.co.y=mix(y,max(-.069,min(.059,y)),k)

for s,sign in [('L',1),('R',-1)]:
    hand=subset('Hand.'+s,[p for p in polys if visible_hand(p,sign)],skin,'hand.'+s)
    for v in hand.data.vertices:
        k=smooth(.819,.658,v.co.z)
        v.co.x-=sign*.038*k
        v.co.y+=.057*k

bvh=BVHTree.FromPolygons(V,polys)
for side,sign in [('L',1),('R',-1)]:
    o=stature(Vector((cx+sign*.0329,-.1219,1.5737)))
    # Concentric loops place the iris and pupil boundaries on clean round ring edges.
    angles=[.001,.13,.25,.31,.34,.40,.47,.54,.57,.62,.68,.78,.90,1.04,1.25,1.55,1.85,2.15,2.45,2.75,3.00,pi-.001]
    rings=[[o+Vector((.0141*sin(v)*cos(u),-.0145*cos(v),.0140*sin(v)*sin(u))) for u in [i*2*pi/56 for i in range(56)]] for v in angles]
    ob=loft('Eye.'+side,rings,sclera,'eye.'+side,True)
    ob.data.materials.append(iris);ob.data.materials.append(pupil)
    for poly in ob.data.polygons:
        row=poly.index//56
        if row<3:poly.material_index=2
        elif row<8:poly.material_index=1

def front(x,z,offset=.0012):
    at,n,i,d=bvh.ray_cast(Vector((x,-.5,z)),Vector((0,1,0)),.7)
    return -.13 if at is None else at.y-offset

def stripe(name,points,widths,mat):
    vs=[]
    for (x,z),w in zip(points,widths):
        for dz in [-.45*w,.55*w]:vs.append((x,front(x,z+dz,.0014),z+dz))
    return mesh(name,vs,[(2*i,2*i+1,2*i+3,2*i+2) for i in range(len(points)-1)],mat,'head')
for s in [-1,1]:
    stripe('Sculpted eyebrow',[(s*x,z) for x,z in [(.019,1.665),(.028,1.669),(.040,1.673),(.053,1.676),(.064,1.675),(.075,1.669),(.082,1.664)]],[.002,.010,.011,.010,.008,.004,.0008],brow)
stripe('Lip plane',[(x,z) for x,z in [(-.037,1.552),(-.022,1.551),(-.010,1.552),(0,1.549),(.010,1.552),(.022,1.551),(.037,1.552)]],[.001,.003,.004,.003,.004,.003,.001],lips)

# Hair cap and arranged solid locks. The seam pattern follows the sweep away from an offset crown part.
center=Vector((.0,-.034,1.655)); rad=Vector((.113,.139,.127))
def on_head(a,b,r=0):
    return center+Vector(((rad.x+r)*sin(b)*sin(a),-(rad.y+r-.032*max(0,-cos(a)))*sin(b)*cos(a),(rad.z+r)*cos(b)))
def limit(a):
    a=abs((a+pi)%(2*pi)-pi)
    return interp(a,[(0,1.24),(.47,1.24),(1.04,1.44),(1.36,1.54),(1.63,1.36),(1.81,1.60),(2.16,2.12),(pi,2.30)])
loft('Hair | connected undercut',[[on_head(a,.013+(limit(a)-.013)*k/16,-.001) for a in [j*pi/36 for j in range(72)]] for k in range(17)],hair[0],'head')

def lock(name,A,B,C,wa,wb,ridge,mat,tip=.0):
    # Curved tapering lenticular section rolled in the local scalp frame.
    rings=[]
    for i in range(17):
        t=i/16; u=1-t; a=u*u*A[0]+2*t*u*B[0]+t*t*C[0]; b=u*u*A[1]+2*t*u*B[1]+t*t*C[1]
        da=2*(u*(B[0]-A[0])+t*(C[0]-B[0]));db=2*(u*(B[1]-A[1])+t*(C[1]-B[1])); w=wa*(1-t)+wb*t
        w*=max(.041,sin(pi*(.13+.87*t))**.60); lateral=Vector((-db,da)).normalized()*w
        c=on_head(a,b,.001+.004*t+tip*t**3.4); axis=(c-center).normalized()
        U=on_head(a+lateral.x/max(.47,sin(b)),b+lateral.y)-c
        h=(.001+ridge*(sin(pi*t)**.65));
        rings.append([c+sin(j*2*pi/12)*U+axis*(cos(j*2*pi/12)*h+.18*h) for j in range(12)])
    return loft(name,rings,mat,'head',True)

locks=[((.42,.39),(-.04,.98),(-.48,1.46),.17,.28,.018),((.46,.35),(-.29,.78),(-.89,1.64),.29,.41,.028),((.59,.23),(-.49,.39),(-1.01,1.52),.27,.42,.027),((.71,.20),(-.95,.33),(-1.44,1.51),.30,.46,.029),((.72,.19),(-1.42,.37),(-1.78,1.58),.28,.43,.027),((.53,.34),(.82,.72),(1.33,1.48),.25,.45,.025),((.65,.19),(1.46,.43),(1.77,1.35),.27,.40,.026),((.78,.30),(1.01,.89),(1.17,1.82),.17,.24,.021),((-.66,.69),(-1.25,.99),(-1.52,1.78),.19,.27,.015)]
for i,(A,B,C,wa,wb,h) in enumerate(locks):lock('Hair | swept front %02d'%i,A,B,C,wa,wb,h,hair[1+i%5])
for i,a in enumerate([1.76,2.06,2.36,2.70,3.04,3.40,3.77,4.1,4.4]):
    lock('Hair | swept crown %02d'%i,(a-.38,.22+i%3*.05),(a-.46,1.05),(a,limit(a)+.05+i%2*.08),.29,.37,.016+i%3*.003,hair[1+i%5],.003+i%3*.006)

for i,a in enumerate([1.88,2.28,2.63,2.94,3.16,3.57,4.02,4.43]):
    lock('Hair | nape lock %02d'%i,(a-.42,1.20),(a-.17,1.86),(a-.04,limit(a)+.14+i%3*.05),.24,.26,.014,hair[1+(i+2)%5],.014+i%2*.003)

# Separate tailor layers with a notched roll and working split tails.
# Each body-row entry gives z, half width, forward depth, back depth, front opening angle, back split.
rows=[(1.472,.081,.107,.077,.66,0),(1.429,.116,.120,.088,.53,0),(1.385,.220,.138,.099,.38,0),(1.337,.252,.146,.121,.32,0),(1.274,.244,.158,.130,.29,0),(1.191,.227,.168,.142,.29,0),(1.118,.207,.160,.134,.31,0),(1.040,.203,.153,.129,.35,0),(.965,.216,.150,.141,.43,0),(.898,.237,.154,.151,.48,0),(.808,.256,.172,.154,.50,.01),(.725,.270,.175,.158,.52,.031),(.641,.274,.180,.164,.53,.040),(.574,.277,.181,.169,.55,.048),(.500,.282,.181,.173,.56,.070)]

def coat_row(row,s,i,j, n=28):
    z,rx,rf,rb,op,gap=row;t=j/n;a=mix(op,pi-gap,t); wave=(1-smooth(.50,1.02,z))
    rw=(.005+.010*wave)*(sin(a*6+s*.30)*.48+sin(a*11+s*.55)*.50)
    x=s*(rx+rw)*sin(a); y=.006-(rf if cos(a)>=0 else rb)*math.copysign(abs(cos(a))**(.48 if cos(a)>=0 else .83),cos(a))+rw*cos(a)
    z += (.010*cos(a+s*.22))*(1-smooth(.5,.9,z))
    z += (.022*max(0.,-cos(a))**2)*smooth(1.374,1.472,z)
    return (x,y,z)

for s,side in [(1,'L'),(-1,'R')]:
    rr=[[coat_row(r,s,i,j) for j in range(29)] for i,r in enumerate(rows)]
    v=[v for r in rr for v in r];f=[(i*29+j,i*29+j+1,(i+1)*29+j+1,(i+1)*29+j) for i in range(len(rr)-1) for j in range(28)]
    if s<0:f=[tuple(reversed(p)) for p in f]
    o=panel('Coat | split panel.'+side,v,f,coat,'coat.'+side,.006);o.data.materials.append(lining);o.modifiers[-1].material_offset=1
    tube('Coat | hem piping.'+side,rr[-1],.0016,lining,'coat.'+side)
    # Thin edge follows the geometry and highlights the opening without a uniform black outline.
    tube('Coat | open edge.'+side,[tuple(Vector(r[0])+Vector((0,-.002,0))) for r in rr[3:]],.0019,lining,'coat.'+side)
    vv=[(.062,-.109,1.465),(.116,-.122,1.423),(.170,-.137,1.370),(.132,-.155,1.355),(.167,-.162,1.328),(.127,-.178,1.245),(.078,-.166,1.110),(.066,-.166,1.185),(.071,-.158,1.290),(.051,-.134,1.389)]
    p=[(s*x,y,z) for x,y,z in vv]
    fa=[(0,1,2,3,9),(3,4,8,9),(4,5,8),(5,6,7,8)]
    if s<0:fa=[tuple(reversed(k)) for k in fa]
    panel('Coat | notched rolled lapel.'+side,p,fa,lapel,'spine',.006)
    tube('Coat | lapel seam.'+side,[tuple(Vector(p[i])+Vector((0,-.002,0))) for i in [1,2,3,4,5,6]],.0012,lining,'spine')
    def coat_front(x,z):
        rx=interp(-z,[(-r[0],r[1]) for r in rows]);rf=interp(-z,[(-r[0],r[2]) for r in rows])
        return .006-rf*(max(.055,1-(x/rx)**2)**.24)-.006
    pocket=[(s*x,coat_front(x,z),z) for x,z in [(.119,.978),(.185,.984),(.184,.951),(.118,.946)]]
    panel('Coat | pocket welt.'+side,pocket,[(0,1,2,3)],lapel,'spine',.006)
    if s==1:
        tube('Coat | center back seam',[tuple(Vector(r[-1])+Vector((0,.0018,0))) for r in rr[2:11]],.00125,lining,'coat.L')
    if s==-1:
        oval('Coat | service button',(-.108,coat_front(.108,.976)-.001,.976),(.009,.0038,.009),lining,'spine')

# Vest and shirt form overlapping fitted closed shells. Top of waistcoat is V-shaped on front only.
def fitted(name,zspec,mat,g,power=1.):
    r=[]
    for z,rx,ry,y,drop,tip in zspec:
        ring=[]
        for j in range(48):
            a=2*pi*j/48;c=cos(a)
            dz=-drop*max(0,c)**9-tip*max(0,c)**3*abs(sin(a))*2
            if name.startswith('Trousers') and z<.82: dz+=.064*abs(sin(a))
            ring.append((rx*sin(a),y-ry*math.copysign(abs(c)**power,c),z+dz))
        r.append(ring)
    return shell(loft(name,r,mat,g),.004)
fitted('Shirt | torso',( (1.463,.075,.095,-.013,0,0),(1.397,.122,.101,-.012,0,0),(1.297,.158,.118,-.008,0,0),(1.187,.156,.118,-.005,0,0),(1.040,.165,.106,.004,0,0)),white,'spine')
fitted('Waistcoat | fitted five-button body',((1.395,.107,.096,-.012,.137,0),(1.363,.131,.108,-.017,.129,0),(1.242,.174,.147,-.013,0,0),(1.132,.166,.143,-.011,0,0),(1.038,.173,.132,-.004,0,0),(.979,.174,.129,-.005,0,0),(.949,.169,.126,-.003,0,.065)),vest,'spine',.80)
for i in range(5):
    z=1.150-i*.041;y=interp(z,[(.986,-.132),(1.04,-.137),(1.15,-.154)])
    oval('Waistcoat | button %d'%(i+1),(0,y-.003,z),(.010,.0045,.010),brass,'spine')
tube('Waistcoat | placket',[(.009,-.158,1.169),(.009,-.146,1.08),(.009,-.134,.992),(.009,-.132,.944)],.0013,vest_edge,'spine')
for s in (-1,1):
    d=s
    panel('Shirt | pointed collar',[(d*.007,-.112,1.446),(d*.057,-.105,1.469),(d*.086,-.088,1.434),(d*.049,-.152,1.346),(d*.022,-.145,1.387)],[(0,1,2,4),(2,3,4)],white,'spine',.004)
panel('Tie | knot and blade',[(-.020,-.125,1.445),(.020,-.125,1.445),(.022,-.145,1.411),(.012,-.149,1.388),(-.012,-.149,1.388),(-.022,-.145,1.411),(.030,-.155,1.248),(0,-.144,1.188),(-.030,-.155,1.248)],[(0,1,2,3,4,5),(4,3,6,7,8)],tie,'spine',.006)

# Pants are one surface from both hems to the waistband. Outer arcs carry into
# the hip panels; the two inner arcs share the crotch bridge.
P=[(.160,.053,.174,.060,.070),(.157,.053,.199,.058,.066),(.152,.055,.285,.059,.070),(.146,.050,.390,.070,.076),(.135,.031,.470,.078,.080),(.130,.014,.514,.080,.087),(.128,.005,.552,.079,.091),(.124,-.009,.658,.086,.104),(.120,-.004,.741,.094,.109)]
N=40; vs=[]; fs=[]; joins=[]
for s in (1,-1):
    offset=len(vs)
    for x,y,z,rx,ry in P:
        vs.extend((s*(x+rx*sin(a)),y-ry*cos(a),z) for a in (j*2*pi/N for j in range(N)))
    for j in range(N):
        a=j*2*pi/N; sn=sin(a)
        if j<=N//2:
            vs.append((s*.209*sn,-.008-.123*cos(a),.825+.014*sn))
        else:
            vs.append((s*(-.050*sn),-.008-.123*cos(a),.825+.049*sn))
    joins.append(offset+len(P)*N)
    for i in range(len(P)):
        for j in range(N):
            x=offset+i*N+j; q=offset+i*N+(j+1)%N; fs.append((x,q,q+N,x+N))
outer=[joins[0]+j for j in range(N//2+1)]+[joins[1]+j for j in range(N//2-1,0,-1)]
for z,rx,ry,cy in [(.874,.201,.118,-.006),(.927,.174,.111,-.005),(.958,.157,.104,-.003)]:
    start=len(vs)
    for j in range(N):
        a=j*2*pi/N;vs.append((rx*sin(a),cy-ry*cos(a),z))
    for j in range(N):
        k=(j+1)%N;fs.append((outer[j],outer[k],start+k,start+j))
    outer=list(range(start,start+N))
for j in range(N//2,N):
    k=(j+1)%N;fs.append((joins[0]+j,joins[0]+k,joins[1]+k,joins[1]+j))
pants=mesh('Trousers | joined waistband and legs',vs,fs,trousers,'pants')
bm=bmesh.new();bm.from_mesh(pants.data);bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=.00001);bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces));bm.to_mesh(pants.data);bm.free();shell(pants,.0035)

for side,s in [('L',1),('R',-1)]:
    # Sleeves: shoulder cap, tapered biceps, gentle elbow creases, independent cuff.
    A=[(.175,.015,1.372,.056,.060),(.208,.014,1.355,.071,.080),(.240,.009,1.326,.071,.094),(.260,.009,1.272,.070,.086),(.281,.016,1.215,.063,.077),(.296,.026,1.151,.056,.070),(.308,.030,1.094,.049,.066),(.313,.019,1.063,.053,.059),(.321,.011,1.044,.050,.057),(.322,.015,1.019,.046,.051),(.332,.000,.946,.039,.049),(.347,-.018,.871,.038,.045),(.352,-.026,.832,.036,.043)]
    rs=disk_rings([(s*x,y,z,rx,ry) for x,y,z,rx,ry in A],32)
    # Avoid visible circular fold bands: mark wrinkles mainly toward the crook.
    for j in range(32):
        x,y,z=rs[7][j];rs[7][j]=(x+y*.018,y,z+.008*sin(j*pi/16))
    shell(loft('Coat | shaped sleeve.'+side,rs,coat,'arm.'+side),.004)
    shell(loft('Shirt | cuff.'+side,disk_rings([(s*.351,-.026,.856,.034,.039),(s*.355,-.036,.812,.033,.038)]),white,'arm.'+side),.003)
    for i in range(3): oval('Coat | cuff button.'+side,(s*(.371-.002*i),.004,.850+i*.014),(.0065,.004,.0065),lining,'arm.'+side)
    B=[(.177,-.037,-.017,.077,.153),(.177,-.038,-.009,.080,.154),(.177,-.038,.010,.079,.154),(.177,-.038,.016,.075,.150)]
    loft('Boot | stacked sole.'+side,disk_rings([(s*x,y,z,rx,ry) for x,y,z,rx,ry in B]),sole_mat,'foot.'+side,True)
    upper=[(.177,-.038,.012,.076,.149),(.177,-.038,.026,.075,.149),(.178,-.026,.048,.071,.138),(.175,-.001,.072,.060,.107),(.167,.023,.094,.054,.080),(.164,.049,.125,.053,.066),(.161,.051,.180,.052,.061),(.160,.051,.213,.054,.061)]
    loft('Boot | leather pattern.'+side,disk_rings([(s*x,y,z,rx,ry) for x,y,z,rx,ry in upper]),leather,'foot.'+side,True)
    def boot_y(x,z):
        xc,yc,rx,ry=[interp(z,[(r[2],r[k]) for r in upper]) for k in (0,1,3,4)]
        return yc-ry*math.sqrt(max(.05,1-((x-xc)/rx)**2))-.002
    for i in range(6):
        z=.062+i*.023
        for x0,x1 in [(.144,.190),(.191,.145)]:
            tube('Boot | lace.'+side,[(s*x,boot_y(x,h),h) for x,h in [(x0,z),(mix(x0,x1,.5),z+.006),(x1,z+.012)]],.0026,sole_mat,'foot.'+side)

# Hierarchy and linear blend weights in the authored neutral pose.
B={}
def bone(name,h,t,parent=None):B[name]=(h,t,parent)
bone('Root',(0,0,0),(0,0,.16));bone('Hips',(0,0,.84),(0,0,1.00),'Root');bone('Spine',(0,0,1.00),(0,0,1.18),'Hips');bone('Chest',(0,0,1.18),(0,0,1.37),'Spine');bone('Neck',(0,0,1.37),(0,-.026,1.51),'Chest');bone('Head',(0,-.026,1.51),(0,-.038,1.77),'Neck')
for side,s in [('L',1),('R',-1)]:
    bone('Clavicle.'+side,(s*.033,.012,1.341),(s*.232,.007,1.313),'Chest');bone('UpperArm.'+side,(s*.232,.007,1.313),(s*.311,.022,1.062),'Clavicle.'+side);bone('Forearm.'+side,(s*.311,.022,1.062),(s*.353,-.025,.832),'UpperArm.'+side);bone('Hand.'+side,(s*.353,-.025,.832),(s*.363,-.05,.727),'Forearm.'+side)
    bone('Thigh.'+side,(s*.113,.013,.842),(s*.133,.023,.503),'Hips');bone('Shin.'+side,(s*.133,.023,.503),(s*.163,.053,.105),'Thigh.'+side);bone('Foot.'+side,(s*.163,.053,.105),(s*.174,-.102,.032),'Shin.'+side);bone('Tail.'+side,(s*.11,.071,.862),(s*.13,.097,.525),'Hips');bone('Eye.'+side,(s*.039,-.128,1.642),(s*.039,-.176,1.642),'Head')
arm=bpy.data.armatures.new('DetectiveSkeleton'); rig=bpy.data.objects.new('DetectiveSkeleton',arm);scene.collection.objects.link(rig);rig.show_in_front=True
bpy.context.view_layer.objects.active=rig; bpy.ops.object.select_all(action='DESELECT'); rig.select_set(True); bpy.ops.object.mode_set(mode='EDIT')
for name,(h,t,parent) in B.items():
    b=arm.edit_bones.new(name);b.head=h;b.tail=t
    if parent:b.parent=arm.edit_bones[parent]
bpy.ops.object.mode_set(mode='OBJECT')

def sw(z):
    s=smooth(.966,1.089,z);c=smooth(1.107,1.255,z)
    return {'Hips':1-s,'Spine':s*(1-c),'Chest':c}

def weights(group,v):
    x,y,z=v; g,_,s=group.partition('.')
    if g=='spine':return sw(z)
    if g=='arm':
        a=smooth(1.261,1.353,z);e=smooth(1.000,1.142,z)
        return {'Clavicle.'+s:a,'UpperArm.'+s:(1-a)*e,'Forearm.'+s:1-e}
    if g=='pants':
        f=smooth(-.027,.027,x)
        return {n:w*(f if n.endswith('.L') else 1-f) for n,w in (weights('leg.L',v)|weights('leg.R',v)).items() if n!='Hips'}|{'Hips':smooth(.78,.90,z)}
    if g=='leg':
        h=smooth(.78,.90,z);k=smooth(.433,.563,z);f=1-smooth(.10,.22,z)
        return {'Hips':h,'Thigh.'+s:(1-h)*k,'Shin.'+s:(1-k)*(1-f),'Foot.'+s:f}
    if g=='coat':
        a=1-smooth(.66,.93,z)
        return {k:w*(1-a) for k,w in sw(z).items()}|{'Tail.'+s:a}
    if g=='neckface':
        h=smooth(1.425,1.50,z);return {'Neck':1-h,'Head':h}
    return {g.capitalize()+('.'+s if s else ''):1.}

for o,g in objects:
    groups={}
    for i,v in enumerate(o.data.vertices):
        for n,w in weights(g,v.co).items():
            if w<=.00005:continue
            if n not in groups:groups[n]=o.vertex_groups.new(name=n)
            groups[n].add([i],w,'REPLACE')
    m=o.modifiers.new('DetectiveSkeleton','ARMATURE');m.object=rig;m.use_deform_preserve_volume=True;o.parent=rig

measure={'source':'Blender Studio Human Base Meshes v1.3.0, Realistic Male Body (CC0); eyes constructed for this study', 'barefoot_vertex':sole,'menton_vertex':chin,'cranium_vertex':skull,'barefoot_m':V[skull].z-V[sole].z,'head_m':V[skull].z-V[chin].z,'head_units':(V[skull].z-V[sole].z)/(V[skull].z-V[chin].z),'visible_parts':len(objects),'bones':len(B)}
assert abs(measure['barefoot_m']-1.77)<1e-6 and abs(measure['head_units']-6.5)<1e-5,measure
(out/'measurement.json').write_text(json.dumps(measure,indent=2)+'\n');print(measure,flush=True)
bpy.ops.object.select_all(action='DESELECT');rig.select_set(True);bpy.context.view_layer.objects.active=rig
bpy.ops.wm.save_as_mainfile(filepath=str((out/'detective-6p5.blend').resolve()))
for o,_ in objects:o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str((out/'detective-6p5.glb').resolve()),export_format='GLB',use_selection=True,export_animations=False)

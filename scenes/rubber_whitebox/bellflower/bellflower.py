"""Bellflower 03 authoritative geometry, scan, AST and 60 Hz reducer (stdlib only)."""
from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache
import json
import math
from pathlib import Path
import random

HERE = Path(__file__).resolve().parent
EPS = 1e-7
UP = (0, 1, 0)
PALETTE = {
    'stone': (0.52, 0.531, 0.538), 'white': (0.68, 0.685, 0.679),
    'night': (0.276, 0.293, 0.320), 'floor': (0.32, 0.335, 0.354),
    'path': (0.411, 0.418, 0.418), 'black': (0.147, 0.151, 0.155),
    'steel': (0.203, 0.209, 0.213), 'tube': (0.51, 0.52, 0.50), 'red': (0.391, 0.118, 0.095),
    'brass': (0.414, 0.328, 0.238), 'bronze_edge': (0.502, 0.401, 0.278),
    'rim': (0.283, 0.223, 0.174), 'lead': (0.27, 0.33, 0.35), 'mate': (0.42, 0.37, 0.30),
}


def read_config():
    return json.loads((HERE / 'arena.json').read_text(encoding='utf-8-sig'))


def dot(a, b):
    return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]


def sub(a, b):
    return (a[0]-b[0], a[1]-b[1], a[2]-b[2])


def cross(a, b):
    return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])


def unit(a):
    n = math.sqrt(dot(a, a))
    return tuple(v/n for v in a)


def cmp(op, a, b):
    if a is None or b is None:
        return None
    return {'eq': lambda: a == b, 'ne': lambda: a != b, 'lt': lambda: a < b,
            'le': lambda: a <= b, 'gt': lambda: a > b, 'ge': lambda: a >= b}[op]()


def eval_ast(expr, get):
    def term(x):
        return get(*x[1:]) if isinstance(x, list) else x
    op, *values = expr
    if op == 'cmp':
        return cmp(values[0], term(values[1]), term(values[2]))
    if op == 'delta':
        s, f, first, last, op, n = values
        a, b = get(s, f, first), get(s, f, last)
        return cmp(op, None if a is None or b is None else b-a, n)
    if op == 'not':
        a = eval_ast(values[0], get)
        return None if a is None else not a
    items = [eval_ast(v, get) for v in values]
    if op == 'all':
        return False if False in items else (None if None in items else True)
    if op == 'any':
        return True if True in items else (None if None in items else False)
    raise ValueError(op)


def refs(expr):
    op, *xs = expr
    if op == 'cmp':
        return {tuple(x[1:]) for x in xs if isinstance(x, list)}
    if op == 'delta':
        return {(xs[0], xs[1], xs[2]), (xs[0], xs[1], xs[3])}
    return set().union(*(refs(x) for x in xs))


@dataclass
class Hull:
    key: str
    verts: list
    faces: list
    material: str
    group: str = 'room'
    kind: str = 'wall'

    def __post_init__(self):
        center = tuple(sum(v[i] for v in self.verts)/len(self.verts) for i in range(3))
        self.planes = []
        self.triangles = []
        for face in self.faces:
            a, b, c = (self.verts[i] for i in face[:3])
            n = unit(cross(sub(b, a), sub(c, a)))
            if dot(n, sub(center, a)) > 0:
                n = tuple(-x for x in n)
                face = face[::-1]
            self.planes.append((n, dot(n, a)))
            if max(dot(n, v)-dot(n, a) for v in self.verts) > 0.001:
                raise ValueError(f'non-convex hull: {self.key}')
            self.triangles.extend((face[0], face[i], face[i+1]) for i in range(1, len(face)-1))
        self.low = tuple(min(v[i] for v in self.verts) for i in range(3))
        self.high = tuple(max(v[i] for v in self.verts) for i in range(3))

    def packet(self):
        return {'id': self.key, 'v': self.verts, 'tri': self.triangles,
                'color': PALETTE[self.material], 'finish': self.material, 'group': self.group, **({'smooth':self.smooth} if hasattr(self,'smooth') else {})}


def prism(key, lo, hi, material, group='room', kind='wall'):
    n = len(lo)
    return Hull(key, lo+hi, [list(range(n)), list(range(n,2*n))] +
                [[i,(i+1)%n,(i+1)%n+n,i+n] for i in range(n)], material, group, kind)


def box(key, x, y, z, w, h, d, material='stone', group='room', kind='wall'):
    lo = [(x+a*w/2, y+b*h/2, z-d/2) for a,b in [(-1,-1),(1,-1),(1,1),(-1,1)]]
    return prism(key, lo, [(a,b,z+d/2) for a,b,_ in lo], material, group, kind)


def drum(key,x,z,y1,y2,r1,r2,material,group='flower', sides=10,kind='wall'):
    def ring(y,r):
        return [(x+r*math.cos(i*math.tau/sides),y,z+r*math.sin(i*math.tau/sides)) for i in range(sides)]
    return prism(key,ring(y1,r1),ring(y2,r2),material,group,kind)


def beam(key, a, b, r, material, group):
    d = unit(sub(b,a))
    e = unit(cross(d,UP if abs(d[1]) < .95 else (1,0,0)))
    f = cross(d,e)
    def ring(p):
        return [tuple(p[j]+r*(math.cos(i*math.tau/6)*e[j]+math.sin(i*math.tau/6)*f[j])
                      for j in range(3)) for i in range(6)]
    return prism(key,ring(a),ring(b),material,group)


@dataclass(frozen=True)
class Pose:
    p: tuple = (0,0,0)
    x: tuple = (1,0,0)
    y: tuple = UP
    z: tuple = (0,0,1)

    def inverse_dir(self, v):
        return (dot(v,self.x),dot(v,self.y),dot(v,self.z))

    def world(self, v):
        return tuple(self.p[i]+self.x[i]*v[0]+self.y[i]*v[1]+self.z[i]*v[2] for i in range(3))

    def packet(self):
        return [self.p,self.x,self.y,self.z]


IDENTITY = Pose()


def clip(h, o, d, limit):
    """Nearest intersection with the same convex faces used to make the visible triangles."""
    t0, t1, side = 0., limit, -1
    for idx,(n,w) in enumerate(h.planes):
        inside = w-dot(n,o)
        dv = dot(n,d)
        if abs(dv)<EPS:
            if inside < -EPS:
                return None
        elif dv < 0:
            s = inside/dv
            if s >= t0:
                t0,side = s,idx
        else:
            s = inside/dv
            if s<t1:
                t1=s
        if t0 > t1+EPS:
            return None
    return t0,side


def slabs(o,d):
    return tuple((i,o[i],1/v,v<0) if abs(v)>=EPS else (i,o[i],0,False) for i,v in enumerate(d))


def bounds_clip(lo,hi,ray,limit):
    near,far=0.,limit
    for i,o,inv,flip in ray:
        if inv:
            l,h=(hi[i],lo[i]) if flip else (lo[i],hi[i])
            a,b=(l-o)*inv,(h-o)*inv
            if a>near:
                near=a
            if b<far:
                far=b
            if near>far+EPS:
                return False
        elif o<lo[i]-EPS or o>hi[i]+EPS:
            return False
    return True


@dataclass
class GroupBounds:
    key: str
    low: tuple
    high: tuple


class BVH:
    """Local-frame bounding tree; triangle/ray results still come from Hull planes."""
    def __init__(self, hulls):
        self.lo=tuple(min(h.low[i] for h in hulls) for i in range(3))
        self.hi=tuple(max(h.high[i] for h in hulls) for i in range(3))
        if len(hulls)>4:
            axis=max(range(3),key=lambda i:self.hi[i]-self.lo[i])
            ordered=sorted(hulls,key=lambda h:(h.high[axis]+h.low[axis],h.key))
            k=len(ordered)//2
            self.children=(BVH(ordered[:k]),BVH(ordered[k:]))
            self.hulls=()
        else:
            self.children=()
            self.hulls=hulls

    def possible(self,ray,limit):
        queue=[self]
        while queue:
            node=queue.pop()
            if bounds_clip(node.lo,node.hi,ray,limit):
                if node.children:
                    queue.extend(node.children)
                else:
                    yield from node.hulls


class World:
    def __init__(self,c,seed,strong=False):
        self.c,self.seed,self.strong = c,seed,strong
        rng = random.Random(seed)
        self.half = rng.randint(*c['period_half_ticks'])
        self.phase = rng.randint(*c['offset_ticks']) % (2*self.half)
        band = 'strong' if strong else 'normal'
        self.hold_min = rng.randint(*c[band+'_hold_min_ticks'])
        self.hold_gain = rng.randint(*c[band+'_hold_gain_ticks'])
        self.groups = {}
        self.arm_axes = {}
        self.make_geometry()
        self.gate_min = [self.face_min(i) for i in range(2)]
        self.trees = {g:BVH(hulls) for g,hulls in self.groups.items()}
        # Stable per-seed opaque track numbers, deliberately unrelated to scene paths.
        keys = [h.key for hs in self.groups.values() for h in hs]
        perm = rng.sample(range(1,1+len(keys)),len(keys))
        self.track = dict(zip(keys,perm))
        for i in range(2):
            g=f'wing{i}'
            self.track[g]=self.track[g+'/shell0']
            for h in self.groups[g]:
                if h.kind=='device':
                    self.track[h.key]=self.track[g]
        self.light_dirs=[unit(sub(l['aim'],l['p'])) for l in c['day_lights']]

    def make_geometry(self):
        c=self.c; gate=c['gate_s_mm']; rx,_,rz=c['root_mm']
        def add(h):
            self.groups.setdefault(h.group,[]).append(h)

        def bell(group,x,z,base,profile,kind='wall',sides=22):
            for k,((h0,r0),(h1,r1)) in enumerate(zip(profile,profile[1:])):
                material='bronze_edge' if k==0 else 'brass'
                hull=drum(f'{group}/shell{k}',x,z,base+h0,base+h1,r0,r1,material,group,sides,kind)
                slope=[]
                for j in (k,k+1):
                    p0,p1=profile[max(0,j-1)],profile[min(len(profile)-1,j+1)]
                    slope.append((p0[1]-p1[1])/(p1[0]-p0[0]))
                hull.smooth=[unit((math.cos(a*math.tau/sides),tilt,math.sin(a*math.tau/sides)))
                             for tilt in slope for a in range(sides)]
                add(hull)
            top,rad=profile[-1]
            add(drum(group+'/finial',x,z,base+top,base+top+120,rad*.63,rad*.63,'rim',group,10))
            add(drum(group+'/clapper',x,z,base-140,base+45,86,75,'rim',group,10))

        def arch(key,x,z,y,inner,thick):
            for j in range(11):
                a,b=math.pi*j/11,math.pi*(j+1)/11
                outline=[(x+math.cos(q)*r,y+math.sin(q)*r) for q,r in
                         ((a,inner),(a,inner+thick),(b,inner+thick),(b,inner))]
                add(prism(f'{key}/arch{j}',[(xx,yy,z-310) for xx,yy in outline],
                          [(xx,yy,z+310) for xx,yy in outline],'white' if j%2 else 'stone'))

        w,h,d=c['room_mm']; center=-2300
        near=center+d/2; far=center-d/2
        add(box('floor',0,-160,center,w,320,d,'floor'))
        add(box('rear_wall',0,h/2,far,w,h,360,'night'))
        add(box('entry_wall',0,h/2,near,w,h,340,'stone','section_front'))
        add(box('side_east',w/2,h/2,center,380,h,d,'stone','section_east'))
        add(box('side_west',-w/2,h/2,center,380,h,d,'night'))
        for x in (-7500,7500):
            for j,z in enumerate((5730,2430,-1750,-5930,-9830)):
                name=f'pier{x}/{j}'
                add(box(name+'/base0',x,145,z,1560,290,1560,'stone'))
                add(box(name+'/base1',x,430,z,1280,280,1280,'white'))
                add(drum(name+'/shaft',x,z,570,11180,530,455,'white','room',16))
                # Fine vertical relief surrounds a continuous tapered plaster shaft.
                for k in range(8):
                    ang=math.tau*k/8
                    dx,dz=math.cos(ang),math.sin(ang)
                    add(beam(f'{name}/flute{k}',(x+510*dx,680,z+510*dz),(x+439*dx,11020,z+439*dz),38,'stone','room'))
                add(drum(name+'/neck',x,z,11170,11510,455,620,'white','room',16))
                add(box(name+'/cap',x,11670,z,1500,340,1430,'white'))
            add(box(f'carrier{x}',x,12210,-2300,1490,780,18000,'stone','section_upper'))
            for j,z in enumerate((470,3850,-2940,-7190,-10600)):
                add(box(f'alcove{x}/{j}',x+765*(1 if x>0 else -1),95,z,1330,190,1780,'night'))
        for j,z in enumerate((5310,2080,-2300,-6750,-10420)):
            add(box(f'ceiling_beam{j}',0,12940,z,16800,470,600,'stone','section_upper'))
        add(box('ceiling',0,13440,center,w,380,d,'night','section_roof'))
        # The entire marble floor is open. Flush inlay marks the two traversal alignments.
        for j in range(9):
            z=5550-j*1580
            add(box(f'route_marker{j}',0,-11,z,2490,24,1550,'path'))
        for s in (-1,1):
            add(box(f'route_border{s}',s*1280,-10,-610,23,24,12600,'rim'))
        for j,radius in enumerate((6660,6800)):
            n=36
            for k in range(n):
                a,b=k*math.tau/n,(k+1)*math.tau/n
                ring=[(math.cos(v)*r,rz+math.sin(v)*(r if math.sin(v)>0 else r*0.82)) for v,r in ((a,radius-18),(a,radius+18),(b,radius+18),(b,radius-18))]
                add(prism(f'ring_marker{j}/{k}',[(x,-9,z) for x,z in ring],[(x,3,z) for x,z in ring],'rim'))
        # Real rear exit arch; it frames a recessed door at the back of the chamber.
        portal=-10020
        for side in (-1,1):
            add(box(f'portal_post{side}',side*1555,1375,portal,540,2750,940,'white'))
            add(box(f'portal_wall{side}',side*4820,2510,portal-360,5700,5020,510,'stone'))
            add(box(f'portal_threshold{side}',side*690,-24,portal+490,1380,55,400,'bronze_edge'))
            add(box(f'open_door_{side}',side*1140,1380,portal-740,185,2730,1160,'black'))
        arch('portal',0,portal,2750,1280,500)
        add(box('rear_threshold',0,-10,portal,2700,25,1530,'path'))
        add(box('behind_portal',0,1640,portal-1390,2350,3280,320,'night'))

        # Split floor pedestal: stone feet carry a steel saddle above both lanes.
        crown=c['crown']; self.hangers={}
        base=crown['base']; leg,sill=base['leg_x_mm'],base['sill_y_mm']
        bottom,upper=crown['axis_y_mm']
        for side in (-1,1):
            x=rx+side*leg
            add(box(f'pedestal/{side}/foot',x,125,rz,1110,250,1340,'stone','flower'))
            add(box(f'pedestal/{side}/plinth',x,280,rz,880,100,1090,'white','flower'))
            add(drum(f'pedestal/{side}/post',x,rz,325,sill-200,381,339,'white','flower',16))
            for rib in range(12):
                phi=math.tau*rib/12
                u,v=math.cos(phi),math.sin(phi)
                add(beam(f'pedestal/{side}/flute{rib}',(x+373*u,375,rz+373*v),
                         (x+332*u,sill-240,rz+332*v),25,'stone','flower'))
            add(box(f'pedestal/{side}/capital',x,sill-150,rz,875,242,965,'black','flower'))
        add(box('pedestal/saddle',rx,sill,rz,4070,285,1220,'black','flower'))
        add(box('gearbox',rx,(bottom+sill)/2,rz,2260,bottom-sill,1680,'black','flower'))
        add(box('gearbox_cap',rx,bottom-260,rz,2380,130,1820,'steel','flower'))
        add(drum('center_spindle',rx,rz,bottom-125,upper+185,417,346,'black'))
        for n in range(7):
            add(box(f'gearbox_fin{n}',rx-870+290*n,bottom-510,rz+849,66,395,94,'steel','flower'))
        for tier,n in enumerate(crown['pairs']):
            y,r=crown['axis_y_mm'][tier],crown['hub_radius_mm'][tier]
            add(drum(f'hub{tier}',rx,rz,y-155,y+155,r+140,r+140,'black',sides=20))
            add(drum(f'band{tier}',rx,rz,y-182,y-124,r+152,r+152,'bronze_edge',sides=20))
            reach=crown['arm_reach_mm'][tier]
            tube=crown['tube']
            spans,sides=tube['sections'],tube['sides']
            start=tube['shaft_end_mm']
            handed=tube['handedness'][tier]
            pair=[]
            for member in range(2):
                path=[]
                for k in range(spans+1):
                    u=k/spans
                    # Two opposed roots lock into the same collar. Each centreline
                    # winds half a turn outwards around the collar's radial axis.
                    t=min(1,3*u)
                    orbit=tube['root_orbit_mm']+(tube['orbit_mm'][tier]-tube['root_orbit_mm'])*t*t*(3-2*t)
                    angle=math.radians(tube['start_deg']+member*tube['pair_phase_deg']+u*tube['turn_deg'])
                    radius=(1-u)*tube['root_radius_mm']+u*tube['tip_radius_mm']
                    path.append((start+(reach-start)*u,orbit*math.sin(angle)-tube['tip_droop_mm'][tier]*u**2,
                                 handed*orbit*math.cos(angle),radius))
                rings,normals=[],[]
                for k,(x,yy,zz,radius) in enumerate(path):
                    a,b=path[max(0,k-1)],path[min(spans,k+1)]
                    dx=b[0]-a[0]
                    ring,normal=[],[]
                    for side in range(sides):
                        co,si=math.cos(math.tau*side/sides),math.sin(math.tau*side/sides)
                        ring.append((x,yy+radius*co,zz+radius*si))
                        normal.append(unit((-((b[1]-a[1])*co+(b[2]-a[2])*si+b[3]-a[3])/dx,co,si)))
                    rings.append(ring); normals.append(normal)
                pair.append((path,rings,normals))
            for i in range(n):
                name=f'rotor:{tier}:{i}'
                az=math.tau*(i+.5+.5*tier)/n+math.radians(crown['az_offset_deg'][tier])
                ca,sa=math.cos(az),math.sin(az)
                self.arm_axes[name]=(az,y,r,tier,i)
                # Trim the radial reach of perimeter-facing pairs to the open hall.
                # The lateral allowance keeps the entire thick tube and hanging bell inboard.
                side_room=crown['reach_clip_mm']['side']-1750*abs(sa)
                rear_room=crown['reach_clip_mm']['rear']-1750*abs(ca)
                limit=min(reach,side_room/max(abs(ca),0.001)-r,
                          rear_room/max(-sa,0.001)-r)
                scale=(limit-start)/(reach-start)
                def compress(v):
                    return start+(v[0]-start)*scale,v[1],v[2]
                # One stationary bearing in the hub, one common rotating collar.
                add(beam(name+'/bearing',(rx+(r-65)*ca,y,rz+(r-65)*sa),
                         (rx+(r+141)*ca,y,rz+(r+141)*sa),439,'black','flower'))
                add(beam(name+'/shaft',(92,0,0),(233,0,0),242,'steel',name))
                add(beam(name+'/collar',(210,0,0),(start-20,0,0),699,'black',name))
                add(beam(name+'/rim',(start-71,0,0),(start-20,0,0),708,'rim',name))
                for member,(path,rings,normals) in enumerate(pair):
                    hanger=f'bell:{tier}:{i}:{member}'
                    _,sy,sz,_=path[0]
                    add(beam(f'{name}/ferrule{member}',(start-32,sy,sz),(start+26,sy,sz),271,'steel',name))
                    for k in range(spans):
                        # Identical shared-seam solids for mesh, collision, shadow and rays.
                        hull=prism(f'{name}/tube{member}/{k}',[compress(v) for v in rings[k]],[compress(v) for v in rings[k+1]],'tube',name)
                        hull.smooth=[unit((nx/scale,ny,nz)) for nx,ny,nz in normals[k]+normals[k+1]]
                        add(hull)
                    self.hangers[hanger]=(name,compress(path[-1][:3]))
                    rope=crown['rope_mm'][tier]
                    add(beam(hanger+'/rope',(0,25,0),(0,-rope-45,0),22,'red',hanger))
                    radius=crown['bell_radius_mm'][tier]
                    profile=[(int(a),round(b*radius)) for a,b in ((0,1),(48,1),(123,.875),(233,.69),(393,.50),(555,.45),(615,.31))]
                    bell(hanger,0,0,-rope-670,profile,sides=16)

        # Two low bells hang from a differential yoke directly below the flower.
        yoke=base['yoke_y_mm']
        add(box('bell_yoke',rx,yoke,(rz-gate)/2,680,320,abs(rz+gate)+410,'black','flower'))
        add(box('bell_crossbar',rx,yoke,-gate,1870,235,360,'black','flower'))
        add(beam('bell_return_shaft',(-2280,yoke,-gate),(rx,yoke,-gate),85,'steel','flower'))
        low=c['low_bells']
        for i,sign in enumerate((-1,1)):
            g=f'wing{i}'; x=sign*low['x_mm']; base=low['bottom_mm']; profile=low['profile_mm']
            bell(g,x,-gate,base,profile,'device')
            top=base+profile[-1][0]
            add(beam(g+'/rope',(x,top+100,-gate),(x,yoke-910,-gate),29,'red',g))
            add(beam(g+'/hanger',(x,yoke-980,-gate),(x,yoke+90,-gate),64,'black',g))
            add(drum(f'pulley{i}',x,-gate,yoke-175,yoke+145,152,152,'black','flower',12))
        # Press plate and accessible side-mounted return catch, visible from the entry.
        lo,hi=c['plate_s_mm']; x=c['lane_x_mm'][1]
        add(box('pedal_frame',x,6,-(lo+hi)/2,870,16,830,'black'))
        add(box('pedal',x,c['plate_travel_mm']-22,-(lo+hi)/2,660,44,hi-lo+2*c['half_actor_mm'][2],'bronze_edge','plate','control'))
        for j in range(7):
            add(box(f'pedal_rib{j}',x-252+j*84,c['plate_travel_mm']+4,-(lo+hi)/2,17,8,540,'rim','plate'))
        catch=c['catch_mm']; y, bh=catch['bolt_y'],catch['bolt_height']
        add(box('latch_stand',-2260,y/2,-2050,270,y,350,'black','flower'))
        add(box('latch_frame',-2260,y,-2050,460,365,270,'steel','flower'))
        add(box('latch',-2260,y,-2270,238,bh,430,'bronze_edge','latch','control'))
        add(beam('latch_link',(-2270,y,-2170),(-2270,yoke,-gate),49,'black','flower'))
        ctop=y+bh/2-c['lift_mm']
        add(box('catch_tooth',-2260,ctop+45,-2550,285,90,275,'rim','carriage'))
        add(beam('catch_guide',(-2260,ctop+50,-2550),(-2195,yoke-710,-gate),79,'steel','carriage'))
        for i,m in enumerate(('lead','mate')):
            x,y,z=c['half_actor_mm']
            add(box('actor'+str(i),0,y,0,2*x,2*y,2*z,m,'actor'+str(i),'teammate'))
        self.group_bounds={g:(tuple(min(h.low[i] for h in hs) for i in range(3)),
                              tuple(max(h.high[i] for h in hs) for i in range(3))) for g,hs in self.groups.items()}

    def face_min(self, i):
        return self.c['low_bells']['bottom_mm']

    def cam(self,t,i=0):
        p=(t+self.phase+i*self.c['right_offset_ticks']) % (2*self.half)
        return self.c['cam_amplitude_mm']*min(p,2*self.half-p)//self.half

    def grace(self,t):
        return self.hold_min+self.hold_gain*self.cam(t)//self.c['cam_amplitude_mm']

    @lru_cache(maxsize=512)
    def arm_poses(self,t):
        c=self.c
        rx,_,rz=c['root_mm']
        poses={}
        for g,(a,y,r,tier,i) in self.arm_axes.items():
            # Cam translates the spring follower; both tubes rotate as one radial rotor.
            wave=self.cam(t+i*18+tier*17)/c['cam_amplitude_mm']
            th=math.radians(c['crown']['twist_deg'][tier]*(2*wave-1))
            ca,sa,ct,st=math.cos(a),math.sin(a),math.cos(th),math.sin(th)
            poses[g]=Pose((rx+r*ca,y,rz+r*sa),(ca,0,sa),(sa*st,ct,-ca*st),(-sa*ct,st,ca*ct))
        for hanger,(arm,point) in self.hangers.items():
            poses[hanger]=Pose(poses[arm].world(point))
        return poses

    def poses(self,a, actors=True):
        poses = {} if a.hidden else dict(self.arm_poses(a.t%(2*self.half)))
        for i in range(2):
            if not a.hidden:
                poses[f'wing{i}']=Pose((0,a.wings()[i],0))
            if actors and i in a.active:
                poses[f'actor{i}']=Pose((self.c['lane_x_mm'][i],0,-a.pos[i]))
        if not a.hidden:
            poses['plate']=Pose((0,-a.travel,0))
            poses['latch']=Pose((0,0,-a.latch_q))
            poses['carriage']=Pose((0,a.lift,0))
            poses['flower']=IDENTITY
        for g in ('room','section_upper','section_front','section_east','section_roof'):
            poses[g]=IDENTITY
        return poses

    def scene_tree(self,poses):
        bounded=[]
        for group,p in poses.items():
            lo,hi=self.group_bounds[group]
            if p is not IDENTITY:
                center=p.world(tuple((a+b)/2 for a,b in zip(lo,hi)))
                ext=(tuple((b-a)/2 for a,b in zip(lo,hi)))
                radius=tuple(abs(p.x[i])*ext[0]+abs(p.y[i])*ext[1]+abs(p.z[i])*ext[2]+EPS for i in range(3))
                lo=tuple(center[i]-radius[i] for i in range(3))
                hi=tuple(center[i]+radius[i] for i in range(3))
            bounded.append(GroupBounds(group,lo,hi))
        return BVH(bounded)

    def nearest(self,poses,o,d,limit,skip=None,shadow=False,tree=None):
        best=None
        tree=self.scene_tree(poses) if tree is None else tree
        ray=slabs(o,d)
        for item in tree.possible(ray,limit):
            g=item.key
            p=poses[g]
            if not bounds_clip(item.low,item.high,ray,limit):
                continue
            if g==skip and not shadow:
                continue
            origin=p.inverse_dir(sub(o,p.p)) if p is not IDENTITY else o
            direction=p.inverse_dir(d) if p is not IDENTITY else d
            local_ray=ray if p is IDENTITY else slabs(origin,direction)
            for h in self.trees[g].possible(local_ray,limit):
                if not bounds_clip(h.low,h.high,local_ray,limit):
                    continue
                hit=clip(h,origin,direction,limit)
                if hit is None:
                    continue
                dist,side=hit
                if shadow:
                    if dist < limit-EPS:
                        return True
                elif best is None or dist < limit-EPS or (abs(dist-limit)<=EPS and h.key < best[0].key):
                    best=h,dist,side
                    limit=dist
        return best

    def light(self,poses,point,tree=None):
        tree=self.scene_tree(poses) if tree is None else tree
        value=0
        for light,axis in zip(self.c['day_lights'],self.light_dirs):
            delta=sub(point,light['p'])
            n2=dot(delta,delta)
            r2=light['r']**2
            if 0 < n2 < r2:
                length=math.sqrt(n2)
                direction=tuple(v/length for v in delta)
                k=dot(direction,axis); cutoff=math.cos(math.radians(light['angle']))
                if k>cutoff and not self.nearest(poses,light['p'],direction,length,shadow=True,tree=tree):
                    value+=int(light['i']*(r2-n2)/r2*min(1,(k-cutoff)/0.095))
        return min(65535,value)

    def scan(self,a, *, eye=None,yaw=None):
        c=self.c
        o=eye or (c['lane_x_mm'][0],c['eye_mm'],-a.pos[0])
        yaw=a.yaw if yaw is None else yaw
        ps=self.poses(a)
        tree=self.scene_tree(ps)
        result=[]
        beams=[]
        for pitch in c['pitch_deg']:
            pv=math.radians(pitch)
            for az in c['az_deg']:
                azv=math.radians(az+yaw)
                d=(math.sin(azv)*math.cos(pv),math.sin(pv),-math.cos(azv)*math.cos(pv))
                h=self.nearest(ps,o,d,c['range_mm'],'actor0',tree=tree)
                if h is None:
                    result.append(None)
                    beams.append([tuple(round(o[i]+d[i]*c['range_mm']) for i in range(3)),0])
                    continue
                hull,t,side=h
                p=tuple(o[i]+d[i]*t for i in range(3))
                light=self.light(ps,p,tree)
                p=tuple(round(v) for v in p)
                beams.append([p,2 if light>=c['light_min'] else 1,hull.kind])
                st={}
                if hull.kind=='device':
                    st={'q_um':1000*a.wings()[int(hull.group[-1])], 'drive':'driving', 'motion':'slide'}
                elif hull.key in ('latch','pedal'):
                    st={'engaged':a.bolt_engaged() if hull.key=='latch' else a.loaded,'travel_um':1000*(a.latch_q if hull.key=='latch' else a.travel)}
                elif hull.kind=='teammate':
                    st={'slot':'mate1','sanity':a.sanity,'distress':a.distress,'mood':a.mood,'contact':'grounded'}
                if light>=c['light_min']:
                    pose=ps[hull.group]
                    center=pose.world(tuple((x+y)/2 for x,y in zip(hull.low,hull.high)))
                    result.append({'track':self.track[hull.key],'kind':hull.kind,
                                   'point_um':tuple(round(1000*(o[i]+d[i]*t)) for i in range(3)),
                                   'distance_um':round(1000*t),'center_um':tuple(round(1000*v) for v in center),
                                   'yaw_udeg':round(1e6*math.degrees(math.atan2(pose.x[2],pose.x[0]))),
                                   'basis_ppb':[tuple(round(v*1e9) for v in axis) for axis in (pose.x,pose.y,pose.z)],
                                   'size_um':[round(1000*(y-x)) for x,y in zip(hull.low,hull.high)],
                                   'face':side,'light_u16':light,'state':st})
                else:
                    result.append(None)
        return {'tick':a.t,'eye_um':tuple(int(v*1000) for v in o),'yaw_udeg':yaw*1000000,'rays':result},beams

    def packet(self):
        c=self.c
        return {'meshes':[h.packet() for hs in self.groups.values() for h in hs],
                'views':c['views'],'lights':c['day_lights'],'eye_mm':c['eye_mm'], 'seed':self.seed}


class Run:
    def __init__(self,w, *, solo=None, tick_limit=None, scan_initial=True):
        self.w,self.c=w,w.c
        self.t=0
        self.pos=self.c['spawn_s_mm'][:]
        self.yaw=0
        self.active=(0,1) if solo is None else (solo,)
        self.solo=solo
        self.joined=solo is not None
        self.hidden=False
        self.tick_limit=tick_limit or self.c['run_ticks']
        self.lift=self.travel=self.latch_q=0
        self.hold_until=-1
        self.loaded=False
        self.held=False
        self.frames={}
        self.last_scan=None
        self.beams=[]
        self.lease=-1
        self.applied=False
        self.proposal_used=set()
        self.last_bad=0
        self.sanity,self.distress=100,0
        self.mood='calm'
        self.result='running'
        self.release_tick=self.clear_tick=self.forecast_margin=None
        self.reply=''
        if scan_initial:
            self.request_scan()

    def request_scan(self):
        if self.t % self.c['scan_every'] == 0 and self.t not in self.frames:
            self.last_scan,self.beams=self.w.scan(self)
            self.frames[self.t]=self.last_scan
            self.frames.pop(self.t-4*self.c['scan_every'],None)

    def wings(self):
        return tuple(self.lift+self.w.cam(self.t,i) for i in range(2))

    def ring(self):
        return not self.hidden and self.lift==self.c['lift_mm'] and self.w.cam(self.t)>=self.c['ring_cam_mm']

    def pinch(self):
        return not self.hidden and all(q+b <= self.c['half_actor_mm'][1]*2 for q,b in zip(self.wings(),self.w.gate_min))

    def far(self,i):
        return self.pos[i] >= self.c['gate_s_mm']+self.c['gate_half_depth_mm']+self.c['half_actor_mm'][2]

    def bolt_engaged(self):
        return self.held and self.latch_q==self.c['catch_mm']['bolt_stroke']

    def legal_tree_get(self,slot,field,off):
        if off:
            return None
        if slot=='latch' and field=='held':
            return self.bolt_engaged()
        if slot=='team':
            return self.far(0) if field=='leader_far' else all(self.far(i) for i in self.active)
        return None

    def judge(self, proposal):
        n=self.c['native']; v=n['waiver']
        if not isinstance(proposal,dict) or self.t%self.c['scan_every'] or self.t in self.proposal_used or self.mood=='panic':
            return 'REJECTED'
        if not self.joined or any(proposal.get(k) != val for k,val in [('actor',n['actor']),('rule_id',n['id']),('waiver_id',v['id'])]):
            return 'REJECTED'
        support=proposal.get('support'); bind=proposal.get('bind')
        if not isinstance(support,list) or not isinstance(bind,dict) or set(bind)!=set(v['slots']):
            return 'REJECTED'
        required=refs(v['claim'])
        if len(support)>len(required):
            return 'REJECTED'
        self.proposal_used.add(self.t)
        values={}
        # Slots resolve to the real two leaves of this rule, not any two lookalike props.
        expected={slot:self.w.track['wing'+str(i)] for i,slot in enumerate(('left','right'))}
        if bind==expected:
            for row in support:
                if not isinstance(row,list) or len(row)!=4:
                    continue
                s,f,t,k=row
                if type(s) is not str or type(f) is not str or type(t) is not int or type(k) is not int:
                    continue
                if (self.t-t)%self.c['scan_every'] or t not in self.frames or not 0<=k<27:
                    continue
                address=s,f,(t-self.t)//self.c['scan_every']
                h=self.frames[t]['rays'][k]
                if address in values:
                    return 'REJECTED'
                if h and address in required and h['kind']==v['slots'][s] and h['track']==bind[s] and h['distance_um']<=self.c['evidence_range_mm']*1000 and f in h['state']:
                    values[address]=h['state'][f]
        if set(values)==required and eval_ast(v['claim'],lambda s,f,o:values.get((s,f,o))) is True:
            self.lease=self.t+self.c['lease_ticks']
            return 'GRANTED'
        self.sanity=max(0,self.sanity-8); self.distress=min(100,self.distress+15); self.last_bad=self.t
        self.update_mood()
        return 'UNSUPPORTED'

    def update_mood(self):
        if self.distress>=60 or self.sanity<=30:
            self.mood='panic'; self.lease=-1
        elif self.mood!='panic' or (self.distress<=30 and self.sanity>=45):
            self.mood='uneasy' if self.distress>=25 or self.sanity<=65 else 'calm'

    def plate(self,s):
        lo,hi=self.c['plate_s_mm']
        return lo<=s<=hi

    def clear_for_entry(self):
        return self.held and self.lift==self.c['lift_mm']

    def contact(self,i,a,b,q0,q1):
        """Continuous contact along the bell-centred traversal alignments.

        The bronze rim reaches the maximum z radius at its minimum y; the
        narrower clapper extends further downward. Both are visible solids.
        """
        c=self.c; mid=c['gate_s_mm']; body_top=2*c['half_actor_mm'][1]
        for radius,y in ((c['gate_half_depth_mm'],self.w.gate_min[i]),
                         (86,self.w.gate_min[i]-140)):
            r=radius+c['half_actor_mm'][2]
            if max(a,b)<mid-r or min(a,b)>mid+r:
                continue
            if b!=a:
                d0,d1=(mid-r-a)/(b-a),(mid+r-a)/(b-a)
                u,v=max(0,min(d0,d1)),min(1,max(d0,d1))
            else:
                u,v=0,1
            if y+q0+min(u*(q1-q0),v*(q1-q0))<=body_top:
                return True
        return False

    def margin(self,release):
        # Exact tick clearance for continuous forward walk from the plate lip.
        c=self.c; p=c['plate_s_mm'][1]; until=release+self.w.grace(release)
        q=self.c['lift_mm']
        clear_at=None; strike_at=None
        for t in range(release,release+250):
            n=q if t<until else max(0,q-c['fall_rate_mm_tick'])
            p2=p+c['move_mm_tick']
            if self.contact(1,p,p2,q+self.w.cam(t,1),n+self.w.cam(t+1,1)) and strike_at is None:
                strike_at=t+1
            if p2 >= c['gate_s_mm']+c['gate_half_depth_mm']+c['half_actor_mm'][2] and clear_at is None:
                clear_at=t+1
            if strike_at is None and n+self.w.cam(t+1,1)+self.w.gate_min[1]-140<=c['half_actor_mm'][1]*2:
                return (t+1)-(clear_at if clear_at is not None else release+math.ceil((c['gate_s_mm']+c['gate_half_depth_mm']+c['half_actor_mm'][2]-c['plate_s_mm'][1])/c['move_mm_tick']))
            if strike_at is not None:
                return strike_at-(clear_at if clear_at is not None else release+math.ceil((c['gate_s_mm']+c['gate_half_depth_mm']+c['half_actor_mm'][2]-c['plate_s_mm'][1])/c['move_mm_tick']))
            q,p=n,p2
        raise AssertionError('drop must finish')

    def step(self, move=(0,0), turn=0, proposal=None, join=False):
        if self.result!='running':
            return
        c=self.c
        self.request_scan()
        assert len(move)==2 and all(type(x) is int and -1<=x<=1 for x in move)
        assert type(turn) is int and -1<=turn<=1
        self.reply=''
        if join and self.solo is None and self.pos[0]>=c['rendezvous_s_mm'] and math.hypot(self.pos[0]-self.pos[1],c['lane_x_mm'][0]-c['lane_x_mm'][1])<=c['recruit_range_mm']:
            self.joined=True
        if proposal is not None:
            self.reply=self.judge(proposal)
        if self.t-self.last_bad and (self.t-self.last_bad)%120==0:
            self.sanity=min(100,self.sanity+2); self.distress=max(0,self.distress-5); self.update_mood()
        q0=self.wings()
        targets=self.pos[:]
        for i in self.active:
            if i==1 and (not self.joined or self.mood=='panic'):
                continue
            dst=min(c['end_s_mm'],max(c['spawn_s_mm'][i],self.pos[i]+c['move_mm_tick']*move[i]))
            if not self.hidden:
                if ((self.pos[i]<=c['approach_s_mm']<dst or dst<c['gate_s_mm']+c['gate_half_depth_mm']+c['half_actor_mm'][2]<=self.pos[i])
                        and not self.clear_for_entry()):
                    dst=self.pos[i]
                if i==1 and self.plate(self.pos[i]) and not self.plate(dst) and eval_ast(c['native']['deny'],self.legal_tree_get) is True:
                    if (self.t<self.lease and dst>self.pos[i] and eval_ast(c['native']['waiver']['live'],self.legal_tree_get) is True):
                        self.applied=True
                    else:
                        dst=self.pos[i]
            targets[i]=dst
        on=1 in self.active and self.joined and self.plate(targets[1]) and not self.hidden
        if self.loaded and not on:
            self.hold_until=self.t+self.w.grace(self.t)
            self.release_tick=self.t
            self.forecast_margin=self.margin(self.t)
        rate=c['plate_rate_mm_tick']
        self.travel=max(0,min(c['plate_travel_mm'],self.travel+(rate if on else -rate)))
        self.loaded=on and self.travel==c['plate_travel_mm']
        self.held=self.loaded or self.t<self.hold_until
        self.lift=max(0,min(c['lift_mm'],self.lift+(c['lift_rate_mm_tick'] if self.held else -c['fall_rate_mm_tick'])))
        catch=c['catch_mm']; speed=catch['bolt_speed']
        retract=(catch['bolt_stroke']+speed-1)//speed
        extend=self.lift==c['lift_mm'] and (self.loaded or self.hold_until-self.t>retract)
        self.latch_q=max(0,min(catch['bolt_stroke'],self.latch_q+(speed if extend else -speed)))
        self.t+=1
        q1=self.wings()
        self.yaw=(self.yaw+turn*c['turn_deg_tick'])%360
        if not self.hidden and any(self.contact(i,self.pos[i],targets[i],q0[i],q1[i]) for i in self.active):
            self.result='collision'
        self.pos=targets
        if self.release_tick is not None and self.clear_tick is None and self.far(1) and self.result=='running':
            self.clear_tick=self.t
        if self.result=='running' and all(self.pos[i]>=c['end_s_mm'] for i in self.active):
            self.result='win'
        if self.result=='running' and self.t>=self.tick_limit:
            self.result='timeout'
    def obs(self):
        self.request_scan()
        return {'tick':self.t,'s_mm':self.pos[0],'yaw_deg':self.yaw,'scan':self.frames.get(self.t),
                'receipt':self.reply}

    def display(self):
        self.request_scan()
        return {'tick':self.t,'poses':{g:p.packet() for g,p in self.w.poses(self).items()},
                'eye':(self.c['lane_x_mm'][0],self.c['eye_mm'],-self.pos[0]),'yaw':self.yaw,
                'beams':self.beams,'scan_eye':tuple(v/1000 for v in self.last_scan['eye_um']),
                'result':self.result,'held':self.held,'joined':self.joined,'reply':self.reply,
                'ring':self.ring(),'hidden':self.hidden,'pinch':self.pinch()}

    def preview(self, view, hidden=False, phase='pinch'):
        """Camera inspection fixture, kept out of scored/session navigation."""
        a=Run(self.w)
        a.hidden=hidden
        a.active=()
        if phase=='ring':
            a.t=(self.w.half-self.w.phase)%(2*self.w.half)
            a.lift=self.c['lift_mm']; a.held=True; a.travel=self.c['plate_travel_mm']; a.latch_q=self.c['catch_mm']['bolt_stroke']
        view=self.c['views'][view]
        scan,a.beams=self.w.scan(a,eye=view.get('scan_p_mm',view['p_mm']),yaw=0)
        a.last_scan=scan
        a.frames[a.t]=scan
        return dict(a.display(), camera=view)

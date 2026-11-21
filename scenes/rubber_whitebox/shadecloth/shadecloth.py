"""Bellflower room variant: one cloth surface serves the display and the light test."""
from functools import lru_cache
from pathlib import Path
import json
import math
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / 'bellflower'))
from bellflower import (EPS, IDENTITY, Pose, Run, World, beam, box, cross, dot,
                        drum, prism, read_config, sub)


def config():
    c = read_config()
    c.update(json.loads(Path(__file__).with_name('arena.json').read_text(encoding='utf-8')))
    c['day_lights'] = [c['primary'], c['gate_light']]
    return c


class Cloth:
    """Bounded, tick-driven deformation; no frame-dependent cloth integration."""
    def __init__(self, c, phase):
        self.c, self.phase = c, phase
        m, n = c['segments']
        self.tri = []
        for j in range(n):
            for i in range(m):
                a = j*(m+1)+i
                b, d = a+1, a+m+1
                self.tri.extend(((a,d,b), (b,d,d+1)) if (i+j)%2 else ((a,d,d+1), (a,d+1,b)))

    def center(self, theta):
        x,y,z = self.c['center_mm']
        rx,rz = self.c['orbit_mm']
        return (x+rx*math.cos(theta)+240*math.sin(2*theta),
                y+260*math.sin(2*theta)+160*math.cos(3*theta),
                z+rz*math.sin(theta)+280*math.cos(3*theta))

    @lru_cache(maxsize=24)
    def vertices(self, tick):
        sin,cos = math.sin,math.cos
        theta = math.tau*((tick+self.phase)%self.c['period_ticks'])/self.c['period_ticks']
        x,y,z = self.center(theta)
        yaw = theta + 0.58 + 0.35*sin(2*theta)
        cs, sn = cos(yaw), sin(yaw)
        a,b = self.c['half_size_mm']
        m,n = self.c['segments']
        points = []
        for j in range(n+1):
            v = 2*j/n-1
            for i in range(m+1):
                u = 2*i/m-1
                # Asymmetric tips, a cupped pocket, and sharper travelling folds at both hems.
                reach = 1 + 0.10*sin(3*v+theta) - 0.17*v*v
                width = 0.96 - 0.44*abs(u)**3 + 0.10*sin(4*u-2*theta)
                across = v*width*(0.86+0.10*cos(4*theta+1.4*u)) + 0.22*sin(3.3*u+theta)
                length = a*u*reach + 180*sin(3.5*v+2*theta)
                height = (460*(1-v*v)*cos(2.2*u-theta) - 420*v*sin(2.8*u+2*theta)
                          + (400+175*abs(v))*sin(5.9*v+2.5*u-4*theta)
                          + 240*v*v*sin(7.1*u-7*theta+v) + 320*u**3*cos(3*theta))
                depth = b*across + 138*sin(5.9*v+2.5*u-4*theta)
                points.append(tuple(map(round, (x+length*cs-depth*sn, y+height, z+length*sn+depth*cs))))
        return points

    @lru_cache(maxsize=8)
    def facets(self, tick):
        points = self.vertices(tick)
        rows = []
        for i,j,k in self.tri:
            a,b,c = points[i],points[j],points[k]
            lo = tuple(min(x,y,z) for x,y,z in zip(a,b,c))
            hi = tuple(max(x,y,z) for x,y,z in zip(a,b,c))
            rows.append((a, sub(b,a), sub(c,a), lo, hi))
        return (tuple(map(min, zip(*points))), tuple(map(max, zip(*points))), rows)

    def occludes(self, tick, o, d, end):
        lo,hi,rows = self.facets(tick)
        if abs(d[1]) < EPS:
            return False  # both arena lamps are strictly above or below the cloth envelope
        t0,t1 = sorted(((lo[1]-o[1])/d[1], (hi[1]-o[1])/d[1]))
        t0,t1 = max(0,t0),min(end,t1)
        if t0 >= t1:
            return False
        x0,x1 = sorted((o[0]+t0*d[0], o[0]+t1*d[0]))
        z0,z1 = sorted((o[2]+t0*d[2], o[2]+t1*d[2]))
        if x1 < lo[0] or x0 > hi[0] or z1 < lo[2] or z0 > hi[2]:
            return False
        for a,e,f,l,h in rows:
            if x1 < l[0]-EPS or x0 > h[0]+EPS or z1 < l[2]-EPS or z0 > h[2]+EPS:
                continue
            p = cross(d,f)
            det = dot(e,p)
            if abs(det) < EPS:
                continue
            v = sub(o,a)
            u = dot(v,p)/det
            if -EPS <= u <= 1+EPS:
                q = cross(v,e)
                w = dot(d,q)/det
                if w >= -EPS and u+w <= 1+EPS and EPS < dot(f,q)/det < end-EPS:
                    return True
        return False


class ShadePoses(dict):
    __slots__ = ('cloth_tick',)


class ShadeWorld(World):
    def __init__(self, c, seed, strong=False):
        # Small seed variation leaves the protected bell readback light in the same place.
        self.cloth = Cloth(c['cloth'], seed % 31)
        self.fixed_fans = {}
        super().__init__(c,seed,strong)

    def make_geometry(self):
        super().make_geometry()
        self.arm_axes.clear()
        self.hangers.clear()
        for g in tuple(self.groups):
            if g.startswith(('rotor:', 'bell:')):
                del self.groups[g]
        remove = ('rotor:', 'gearbox', 'center_spindle', 'hub', 'band')
        for g in ('room','flower'):
            self.groups[g] = [h for h in self.groups[g] if not h.key.startswith(remove)]

        # In the editorial section, remove only the near colonnade with the east wall.
        east = [h for h in self.groups['room'] if h.key.startswith('pier7500/')]
        self.groups['room'] = [h for h in self.groups['room'] if not h.key.startswith('pier7500/')]
        for h in east:
            h.group = 'section_east'
        self.groups['section_east'].extend(east)

        def add(h):
            self.groups.setdefault(h.group, []).append(h)

        c = self.c
        rx,_,rz = c['root_mm']
        fan = c['fans']
        for i in range(fan['count']):
            az = math.radians(fan['first_angle_deg']+i*360/fan['count'])
            # Face outward. The rectangular outlets cant inward and along the orbit.
            x,z = math.sin(az), math.cos(az)
            pose = Pose((rx+fan['radius_mm']*x,0,rz+fan['radius_mm']*z), (z,0,-x),(0,1,0),(x,0,z))
            g = f'fan{i}'
            self.fixed_fans[g] = pose
            def rect(name, x, y, z, w, h, d, mat='black'):
                add(box(g+'/'+name,x,y,z,w,h,d,mat,g))
            def annulus(name, cy, r0,r1,z0,z1, mat, n=24):
                for k in range(n):
                    a,b = k*math.tau/n,(k+1)*math.tau/n
                    face = [(r*math.cos(t),cy+r*math.sin(t),z0) for r,t in ((r0,a),(r1,a),(r1,b),(r0,b))]
                    add(prism(f'{g}/{name}{k}',face,[(x,y,z1) for x,y,_ in face],mat,g))
            rect('stone',0,90,0,1590,180,1290,'stone')
            rect('skid',0,224,0,1390,90,1050,'black')
            for side in (-1,1):
                rect(f'foot{side}',side*472,349,-65,168,170,613)
            height = 1040
            # Cast scroll, bright intake collar, and a protected cavity behind the grille.
            disk = [(802*math.cos(k*math.tau/24),height+802*math.sin(k*math.tau/24),-285) for k in range(24)]
            add(prism(g+'/volute',disk,[(a,b,145) for a,b,_ in disk],'black',g))
            annulus('casting',height,600,802,145,410,'black')
            annulus('intake',height,612,656,408,467,'bronze_edge')
            for n in range(12):
                a = n*math.tau/12
                start = (158*math.cos(a),height+158*math.sin(a),442)
                end = (613*math.cos(a),height+613*math.sin(a),442)
                add(beam(f'{g}/guard{n}', start, end, 13, 'steel',g))
            add(beam(g+'/bearing',(0,height,425),(0,height,515),163,'bronze_edge',g))
            # Hollow taper. Top and bottom rings share a parallel plane to remain convex.
            for side in (-1,1):
                for axis in (0,1):
                    def wall(y,cx,cz,hw,hd):
                        if axis==0:
                            return [(cx+side*a,y,cz+b) for a,b in ((hw,-hd),(hw+65,-hd),(hw+65,hd),(hw,hd))]
                        return [(cx+a,y,cz+side*b) for a,b in ((-hw-65,hd),(hw+65,hd),(hw+65,hd+65),(-hw-65,hd+65))]
                    lo = wall(1460,480,-44,315,265)
                    hi = wall(2320,640,-423,315,265)
                    lip = wall(2410,657,-463,315,265)
                    add(prism(f'{g}/duct{axis}/{side}',lo,hi,'black',g))
                    add(prism(f'{g}/lip{axis}/{side}',hi,lip,'bronze_edge',g))
            # Exposed dual belt legs and small drive pulley on the rear side of the casting.
            for side in (-1,1):
                add(beam(f'{g}/belt{side}',(0,1040+side*190,-385),(-780,400+side*115,-385),33,'black',g))
                rect(f'rivet{side}',side*630,266,408,86,65,80,'bronze_edge')
            add(beam(g+'/drive',(-780,400,-449),(-780,400,-317),156,'bronze_edge',g))
            add(beam(g+'/pulley',(0,1040,-466),(0,1040,-326),235,'rim',g))

        lx,ly,lz = c['primary']['p']
        def lamp(k, y1,y2,r1,r2,mat):
            add(drum('lamp/'+k,lx,lz,ly+y1,ly+y2,r1,r2,mat,'luminaire',sides=24))
        lamp('collar',1260,1710,183,246,'black')
        lamp('stem',660,1260,61,61,'rim')
        lamp('canopy',174,660,1000,282,'black')
        lamp('mouth',116,190,1000,1026,'bronze_edge')
        lamp('glass',92,122,868,868,'white')
        lamp('glow_rim',178,201,999,990,'white')
        self.group_bounds = {g:(tuple(map(min,zip(*(h.low for h in hs)))),
                                tuple(map(max,zip(*(h.high for h in hs))))) for g,hs in self.groups.items()}

    def poses(self, a, actors=True):
        posed = ShadePoses(super().poses(a,actors))
        posed['luminaire'] = IDENTITY
        if not a.hidden:
            posed.update(self.fixed_fans)
        posed.cloth_tick = None if a.hidden or getattr(a,'uncovered',False) else a.t
        return posed

    def nearest(self, poses, o, d, limit, skip=None, shadow=False, tree=None):
        # With the standard eye and 3x9 sensor, all sight rays end below the cloth.
        # Lighting queries, however, cross its exact double-sided mesh.
        if shadow and poses.cloth_tick is not None and self.cloth.occludes(poses.cloth_tick,o,d,limit):
            return True
        return super().nearest(poses,o,d,limit,skip,shadow,tree)

    def packet(self):
        return dict(super().packet(), cloth_tri=self.cloth.tri, cloth_segments=self.c['cloth']['segments'],
                    cloth_period=self.c['cloth']['period_ticks'], fan_phase=self.cloth.phase, fans=self.c['fans'])


class ShadeRun(Run):
    def display(self):
        state = super().display()
        visible = not self.hidden and not getattr(self,'uncovered',False)
        return dict(state, cloth=self.w.cloth.vertices(self.t) if visible else [],
                    shade_view=getattr(self,'shade_view','live'))

    def preview(self, view, hidden=False, phase='pinch', uncovered=False, frame_tick=None):
        a = ShadeRun(self.w, scan_initial=False)
        a.hidden, a.uncovered, a.shade_view = hidden, uncovered, view
        a.t = a.c['views'][view]['phase_ticks'] if frame_tick is None else frame_tick
        a.active = ()
        if frame_tick is not None:
            # No contestant scan is published during an unscored camera animation.
            a.last_scan = {'eye_um':(a.c['lane_x_mm'][0]*1000,a.c['eye_mm']*1000,-a.pos[0]*1000)}
            a.frames[a.t] = a.last_scan
            return dict(a.display(), camera=a.c['views'][view], diagnostic=True)
        # An authentic floor-height scan, even while inspecting from a crane camera.
        a.last_scan,a.beams = self.w.scan(a)
        a.frames[a.t] = a.last_scan
        return dict(a.display(),camera=a.c['views'][view],diagnostic=True)


if __name__=='__main__':
    from bridge import main
    main(config, ShadeWorld, ShadeRun)

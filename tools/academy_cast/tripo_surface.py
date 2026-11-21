"""Source-local academy character mesh repairs (NumPy/SciPy, ordinary Python).

Inputs are the individual first-pass Tripo OBJ ZIPs and corresponding front camera/face
landmark arrays. No character template, UV textures or cross-character vertex transfer.
Coordinates: X lateral, -Y front, Z up; normalized by each source's barefoot height.
"""
from argparse import ArgumentParser
from collections import Counter, defaultdict, deque
from functools import lru_cache
from pathlib import Path
from zipfile import ZipFile
import json
import numpy as np
from scipy.spatial import cKDTree

CAST = ('01-detective', '02-lucian', '03-ward', '04-shen-ding', '05-halvard',
        '06-ruan-qingyue', '07-caretaker')
EYES = ((33, 246, 161, 160, 159, 158, 157, 173, 133, 155, 154, 153, 145, 144, 163, 7),
        (263, 466, 388, 387, 386, 385, 384, 398, 362, 382, 381, 380, 374, 373, 390, 249))


def edges(f):
    return zip(f, f[1:] + f[:1])


def adjacency(faces):
    ed = defaultdict(list)
    for i, f in enumerate(faces):
        for a, b in edges(f):
            ed[min(a, b), max(a, b)].append((i, a, b))
    return ed


def borders(ed):
    nxt = {ls[0][1]: ls[0][2] for ls in ed.values() if len(ls) == 1}
    if len(nxt) != sum(len(ls) == 1 for ls in ed.values()):
        return []
    out = []
    while nxt:
        a = end = min(nxt)
        r = []
        while end in nxt:
            r.append(end)
            end = nxt.pop(end)
        if end != a:
            return []
        out.append(r)
    return out


def packed(v, faces):
    used = np.unique(np.concatenate(faces))
    lookup = np.full(len(v), -1)
    lookup[used] = np.arange(len(used))
    return v[used], [lookup[f].tolist() for f in faces]


def read_source(path):
    v, f, lut, points = [], [], [], {}
    with ZipFile(path) as z:
        name = next(n for n in z.namelist() if n.lower().endswith('.obj'))
        for s in z.read(name).decode('utf-8-sig').splitlines():
            a = s.split()
            if a and a[0] == 'v':
                q = tuple(round(float(x), 7) for x in a[1:4])
                ix = points.setdefault(q, len(v))
                if ix == len(v):
                    v.append(q)
                lut.append(ix)
            if a and a[0] == 'f':
                f.append([lut[int(x.split('/')[0]) - 1] for x in a[1:]])
    v = np.array(v)[:, [0, 2, 1]] * [1, -1, 1]
    h = np.ptp(v[:, 2]); floor = v[:, 2].min()
    v[:, 2] -= floor
    return v / h, f, h, floor


def main_component(v, faces):
    adj = defaultdict(set)
    for f in faces:
        for a, b in edges(f):
            adj[a].add(b); adj[b].add(a)
    left = set(adj)
    components = []
    while left:
        start = left.pop()
        todo = [start]; seen = {start}
        for u in todo:
            for w in sorted(adj[u] & left):
                seen.add(w); left.remove(w); todo.append(w)
        components.append(seen)
    biggest = max(components, key=len)
    kept = [f for f in faces if f[0] in biggest]
    return (*packed(v, kept), len(faces) - len(kept))


def tris(faces):
    return np.array([[f[0], f[j], f[j + 1]] for f in faces for j in range(1, len(f) - 1)])


def masses(v, faces, closed):
    p, q, r = v[tris(faces)].transpose(1, 0, 2)
    a = np.linalg.norm(np.cross(q-p, r-p), axis=1) * .5
    area = (a[:, None] * (p+q+r)/3).sum(0) / a.sum()
    result = {'area': float(a.sum()), 'surface_centroid': area.tolist()}
    if closed:
        o = v.mean(0)
        weights = np.einsum('ij,ij->i', p-o, np.cross(q-o, r-o))/6
        c = (weights[:, None] * ((p+q+r+o)/4)).sum(0)/weights.sum()
        result.update(signed_volume=float(weights.sum()), volume_centroid=c.tolist())
    return result


def unit(v):
    return v / np.maximum(1e-15, np.linalg.norm(v, axis=-1, keepdims=True))


def quad_cost(v, f):
    q = v[f]
    e = np.roll(q, -1, axis=0) - q
    L = np.linalg.norm(e, axis=1)
    if L.min() < 1e-8:
        return 1000.
    ne = unit(e)
    normals = unit(np.cross(ne, np.roll(ne, -1, axis=0)))
    straight = np.abs(np.einsum('ij,ij->i', ne, np.roll(ne, -1, axis=0)))
    return float(np.log(L.max()/L.min()) + straight.mean() + 3*(1-np.linalg.norm(normals.mean(0))))


def fill_boundary(v, rim):
    """Dynamic partition uses quads and at most one tri for an odd boundary."""
    r = rim[::-1]
    @lru_cache(None)
    def best(a, b):
        n = b-a+1
        if n == 2:
            return 0., ()
        if n == 3 or n == 4:
            f = r[a:b+1]
            return quad_cost(v, f), (f,)
        choices = []
        if n % 2:
            for j in range(a+1, b, 2):
                s, u = best(a, j); t, w = best(j, b)
                f = [r[i] for i in (a, j, b)]
                choices.append((s+t+quad_cost(v, f), u+w+(f,)))
        for j in range(a+1, b-1):
            for k in range(j+1, b):
                if sum((x-y) % 2 == 0 for x,y in ((j,a),(k,j),(b,k))) != n % 2:
                    continue
                s, u = best(a, j); t, w = best(j, k); z, e = best(k, b)
                f = [r[i] for i in (a, j, k, b)]
                choices.append((s+t+z+quad_cost(v,f),u+w+e+(f,)))
        return min(choices, key=lambda item: item[0])
    return list(best(0, len(r)-1)[1])


def crossings(v, old, added):
    """Score true segment/triangle crossings excluding coincident topological edges."""
    if not old or not added:return 0
    ia=tris(added); ib=tris(old); a=v[ia];b=v[ib]
    i,j=np.nonzero((a.max(1)[:,None,:]>=b.min(1)[None,:,:]-1e-7).all(2) & (a.min(1)[:,None,:]<=b.max(1)[None,:,:]+1e-7).all(2))
    clean=~np.any(ia[i,:,None]==ib[j,None,:],axis=(1,2));a=a[i[clean]];b=b[j[clean]]
    def scan(t, q):
        e1=t[:,1]-t[:,0];e2=t[:,2]-t[:,0]; any_hit=np.zeros(len(e1),bool)
        for k in range(3):
            d=q[:,(k+1)%3]-q[:,k];o=q[:,k]-t[:,0];p=np.cross(d,e2);det=(e1*p).sum(1)
            den=np.where(np.abs(det)>1e-13,det,1.)
            u=(o*p).sum(1)/den; r=np.cross(o,e1);w=(r*d).sum(1)/den; along=(e2*r).sum(1)/den
            any_hit|=(np.abs(det)>1e-13)&(u>=-1e-7)&(w>=-1e-7)&(u+w<=1+1e-7)&(along>=-1e-7)&(along<=1+1e-7)
        return any_hit
    return int(np.count_nonzero(scan(a,b)|scan(b,a)))


def close(v, f):
    ed = adjacency(f)
    base = list(f)
    filled = []
    # Exclude existing chords from hole fills, try several boundary origins.
    for r in borders(ed):
        existing = {e for e in ed if e[0] in r and e[1] in r}
        rim = {tuple(sorted(e)) for e in edges(r)}
        best = None
        bb = v[r]
        regional=[g for g in base if np.all(v[g].max(0)>=bb.min(0)-.001) and np.all(v[g].min(0)<=bb.max(0)+.001)]
        for k in range(0,len(r),max(1,len(r)//6)):
            patch = fill_boundary(v, r[k:] + r[:k])
            if (set(adjacency(patch)) - rim) & existing:
                continue
            hits=crossings(v,regional,patch)+crossings(v,patch,patch)//2
            score=hits*200+sum(quad_cost(v,g) for g in patch)
            if best is None or score<best[0]:best=(score,patch,hits)
            if hits==0 and len(r)<6:break
        if best is not None:
            base.extend(best[1])
            filled.append({'boundary_edges': len(r), 'size_pct_h': float(100*np.linalg.norm(np.ptp(v[r],axis=0))),
                           'center': v[r].mean(0).tolist(),'initial_crossings':best[2]})
    return base, filled


def merge_tris(v, faces):
    """Slide an odd face along the dual graph and pair with another triangle.

    Local flips must not create duplicate edges or fold across the old face normals.
    """
    f = list(faces)
    count = 0
    for attempt in range(60):
        ed = adjacency(f)
        links = defaultdict(dict)
        for k, ls in ed.items():
            if len(ls) == 2:
                a, b = (x[0] for x in ls)
                links[a][b] = links[b][a] = k
        face_ids = {tuple(sorted(g)): i for i,g in enumerate(f)}
        tri_ids = [i for i,g in enumerate(f) if len(g)==3]
        if len(tri_ids)<2:
            break
        def change(i, j, next_j=None):
            a, b = f[i], f[j]
            k = links[i][j]
            p = borders(adjacency([a,b]))
            if len(p)!=1 or len(p[0]) != len(a)+len(b)-2:
                return None
            poly = p[0]; ls = []
            old = [v[g] for g in (a,b)]
            oldn = unit(sum(np.cross(q[1]-q[0],q[2]-q[0]) for q in old))
            if len(poly)==4:
                choices=[(poly,)]
            else:
                target = links[j].get(next_j)
                choices=[]
                for t in range(5):
                    q = poly[t:] + poly[:t]
                    d = tuple(sorted((q[0],q[2])))
                    if d in ed and d != k:
                        continue
                    face = q[:3]; quad = [q[0]] + q[2:]
                    if target is not None and target not in {tuple(sorted(e)) for e in edges(face)}:
                        continue
                    choices.append((quad,face))
            for g in choices:
                if any(face_ids.get(tuple(sorted(h)), i) not in (i,j) for h in g):
                    continue
                dot = [np.dot(unit(np.cross(v[z[1]]-v[z[0]],v[z[2]]-v[z[0]])),oldn) for z in g]
                if min(dot) <= .22:
                    continue
                cost = sum(quad_cost(v,z) for z in g)
                if cost > 7:
                    continue
                ls.append((cost,g))
            return min(ls,key=lambda x:x[0])[1] if ls else None
        updated = False
        for i in tri_ids:
            todo = deque([[i]])
            seen = {i}; path = None
            while todo:
                q = todo.popleft()
                if len(q)>6:
                    continue
                for j in sorted(links[q[-1]]):
                    if j in seen: continue
                    seen.add(j)
                    if j in tri_ids:
                        if len(q)==1 and change(i,j):path=q+[j];break
                        if len(q)>1 and change(i,q[1],q[2] if len(q)>2 else j):path=q+[j];break
                    todo.append(q+[j])
                if path:break
            if path:
                old = f.copy()
                for k,(a,b) in enumerate(zip(path,path[1:])):
                    # Only the moving triangle's current adjacency changes; recompute locally.
                    inter = set(tuple(sorted(e)) for e in edges(f[a])) & set(tuple(sorted(e)) for e in edges(f[b]))
                    if len(inter)!=1:break
                    links[a][b]=inter.pop()
                    g=change(a,b,path[k+2] if k+2<len(path) else None)
                    if g is None:break
                    f[a]=g[0]
                    if len(g)==2:f[b]=g[1]
                    else:
                        f.pop(b); count+=2;updated=True
                if updated:
                    valid=all(len(a)==2 and a[0][1]!=a[1][1] for a in adjacency(f).values())
                    unique=len({tuple(sorted(g)) for g in f})==len(f)
                    if valid and unique:break
                    updated=False; count-=2
                f=old
        if not updated:
            break
    return f,count


def fit_head_scale(v, lm, detective):
    if not detective:
        return v, 1.
    top = v[:,2].max(); chin = lm[152,1]
    multiplier = top/6.5 / (top-chin)
    t=np.clip((v[:,2]-.80)/max(.01, chin-.80),0,1); t=t*t*(3-2*t)
    u=v.copy(); u[:,2]+=(multiplier-1)*(v[:,2]-top)*t
    return u, multiplier


def silhouette(face, v, p):
    """Front surface query in XZ: use only actual Tripo triangles, no other character."""
    t = v[tris(face)]; q = t[:,:,[0,2]]; a=q[:,1]-q[:,0]; b=q[:,2]-q[:,0]
    det=a[:,0]*b[:,1]-a[:,1]*b[:,0]; valid = np.abs(det)>1e-12
    out=[]
    for x in p:
        d=x-q[:,0]; u=(d[:,0]*b[:,1]-d[:,1]*b[:,0])/np.where(valid,det,1)
        w=(a[:,0]*d[:,1]-a[:,1]*d[:,0])/np.where(valid,det,1)
        keep=valid & (u>=-1e-7) & (w>=-1e-7) & (u+w<=1+1e-7)
        y=(1-u-w)*t[:,0,1]+u*t[:,1,1]+w*t[:,2,1]
        out.append(y[keep].min() if np.any(keep) else np.nan)
    return np.array(out)


def feature_specs(lm):
    specs=[]
    for e in EYES:
        points=lm[list(e)]
        c=(points.max(0)+points.min(0))*.5
        scale=np.maximum(np.ptp(points,axis=0)*.5,[.006,.0025])
        specs.append((c,scale,scale+np.array([.010,.011]),points))
    points=lm[[61,291,0,17]]
    c=np.array([points[:2,0].mean(),lm[[13,14],1].mean()])
    scale=np.array([np.ptp(points[:,0])*.50,max(np.ptp(points[:,1])*.5,.0034)])
    specs.append((c,scale,scale+np.array([.019,.020]),points))
    return specs


def closed_disks(v, faces, spec, index, excluded):
    """Search compact original face neighborhoods for a monotone annulus boundary."""
    c, size, search, points = spec
    v2 = v[:,[0,2]]
    ctr = np.array([v[g].mean(0) for g in faces]); xy=ctr[:,[0,2]]
    delta = (xy-c)/search
    front = ctr[:,1] < -.016
    n = np.array([np.cross(v[g[1]]-v[g[0]],v[g[2]]-v[g[0]])[1] for g in faces]); front &= (n<0 if index<2 else n<5e-5)
    front[list(excluded)]=False
    links = [set() for _ in faces]
    for es in adjacency(faces).values():
        if len(es)==2:
            a,b=(e[0] for e in es); links[a].add(b); links[b].add(a)
    pivot = int(np.argmin(np.where(front,np.linalg.norm(delta,axis=1),1e3)))
    if not front[pivot]:return []
    options=[]; visited=set()
    scales=((1.,1.),(.84,1.14),(1.22,.88),(.84,1.42),(1.29,1.12),(1.38,.90),(1.26,1.36),(.91,1.65),(1.58,.87),(1.15,.68))
    shifts=[(0.,0.)] if index<2 else [(0.,0.),(0.,-.22),(0.,.22),(-.18,0.),(.18,0.),(-.12,.16),(.12,.16)]
    for ax,az,m,shift in [(x,z,m,k) for k in shifts for x,z in scales for m in np.arange(.67,1.79,.06)]:
        d=np.linalg.norm((delta-shift)/[ax,az],axis=1)
        local={pivot}; stack=[pivot]
        for i in stack:
            for j in sorted(links[i]-local):
                if front[j] and d[j]<=m:
                    local.add(j); stack.append(j)
        for remove in (False,True):
            sub=local.copy()
            if remove:
                for i in sorted(local):
                    if len(links[i]&local)==1 and i!=pivot: sub.remove(i)
            key=tuple(sorted(sub))
            if key in visited:continue
            visited.add(key)
            fs=[faces[j] for j in key]
            b=borders(adjacency(fs))
            if len(b)!=1:continue
            rim=b[0]; count=len(rim)
            if count < 8 or count > 26 or count%2:continue
            r = (v2[rim]-c)/search
            angle = np.arctan2(r[:,1],r[:,0]); gaps=np.mod(np.roll(angle,-1)-angle,2*np.pi)
            if not np.isclose(gaps.sum(),2*np.pi) or max(gaps)>1.78 or min(gaps)<.009:continue
            u = v2[rim]-c
            # With CCW projected boundary each ellipse point has to be inside the annulus.
            ev=np.roll(u,-1,axis=0)-u
            vv=(points-c)[None,:,:]-u[:,None,:]
            cross=ev[:,0,None]*vv[:,:,1]-ev[:,1,None]*vv[:,:,0]
            if cross.min() < -1.9e-4:continue
            nrm=np.linalg.norm(r,axis=1)
            score=abs(nrm.mean()-1.03)+np.std(nrm)+.43*np.std(gaps)+abs(count-(12 if index<2 else 16))*.013
            options.append((float(score),rim,sub))
    return sorted(options,key=lambda a:a[0])


def surface_face(v, faces, lm, measurements):
    """Three independent small patches; no global face mask and no loose bridge fan."""
    origv=v.copy(); origf=faces.copy()
    patches=[]; deleted=set(); extras=[]; loops={}; centers=[]
    for i,spec in enumerate(feature_specs(lm)):
        c,sz,search,points=spec
        for disk in closed_disks(origv,origf,spec,i,deleted):
            _,rim,gone=disk
            vec=(v[rim][:,[0,2]]-c)/search
            angles=np.unwrap(np.arctan2(vec[:,1],vec[:,0])); n=len(angles)
            evenly=np.arange(n)*2*np.pi/n; evenly+=np.mean(angles-evenly)
            theta=angles*.52+evenly*.48
            D=np.column_stack([np.cos(theta),np.sin(theta)])
            rings=[]; assign={}
            if i<2:
                norm=(points-c)/sz; query=np.arctan2(norm[:,1],norm[:,0]); order=np.argsort(query)
                edge=np.column_stack([np.interp(theta,query[order],points[order,j],period=2*np.pi) for j in range(2)])
                rimxy=c+(edge-c)*[.97,1.0]
                midxy=c+(rimxy-c)*[1.20,1.35]
                center_y=float(silhouette(origf,origv,[c])[0]); radius=float(sz[0]*1.14)
                if not np.isfinite(center_y): continue
                eye_center=np.r_[c[0],center_y+radius*.78,c[1]]
                ell=np.column_stack([rimxy[:,0]-c[0],(rimxy[:,1]-c[1])/.94]); ell=np.linalg.norm(ell,axis=1)
                sy=eye_center[1]-radius*.86*np.sqrt(np.maximum(0,1-(ell/radius)**2))
                ys=sy-.0015
                rim_y=ys
                inside=c+(rimxy-c)*.91
                pocket0=np.c_[inside[:,0],ys+.0048,inside[:,1]]
                outer_xy=midxy
            else:
                width=sz[0]; ht=sz[1]; skew=(lm[291,1]-lm[61,1])/max(width*2,.001)
                base_z=c[1]+skew*width*D[:,0]
                # Keep the corners narrow, with a thin opening in the neutral pose.
                rimxy=np.c_[c[0]+width*.89*D[:,0],base_z+ht*.36*D[:,1]]
                outer_xy=np.c_[c[0]+width*1.08*D[:,0],base_z+ht*1.04*D[:,1]]
                rim_y=silhouette(origf,origv,rimxy)-.00075
                inside=c+(rimxy-c)*.88
                pocket0=np.c_[inside[:,0],rim_y+.0075,inside[:,1]]
            band=outer_xy*.60+v[rim][:,[0,2]]*.40
            def add(q, y):
                k=len(v)+sum(len(r) for r in rings)
                rings.append(np.c_[q[:,0],y,q[:,1]])
                return list(range(k,k+n))
            def join(a,b):
                return [[a[j],a[(j+1)%n],b[(j+1)%n],b[j]] for j in range(n)]
            use_transition = i==2 and np.linalg.norm(v[rim][:,[0,2]]-outer_xy,axis=1).mean() > .019
            bb=add(band,silhouette(origf,origv,band)) if use_transition else []
            oo=add(outer_xy,silhouette(origf,origv,outer_xy)-(.0003 if i<2 else .0007))
            ii=add(rimxy,rim_y)
            pp=add(pocket0[:,[0,2]],pocket0[:,1]); bottom=len(v)+sum(len(r) for r in rings)
            if not np.isfinite(np.concatenate(rings)).all():
                continue
            new=np.vstack([v,*rings,pocket0.mean(0)+[0,.006 if i<2 else .012,0]])
            quad=(join(rim,bb)+join(bb,oo) if bb else join(rim,oo))+join(oo,ii)+join(ii,pp)
            cap=[[bottom,pp[j],pp[(j+1)%n],pp[(j+2)%n]] for j in range(0,n,2)]
            # Exterior annulus must retain front winding; swallow no folded bridge.
            bad=0
            for face in quad[:(3 if use_transition else 2)*n]:
                q=new[face][:,[0,2]]
                a,b=q[1:-1]-q[0],q[2:]-q[0]
                if np.min(a[:,0]*b[:,1]-a[:,1]*b[:,0]) <= 1e-9:bad+=1
            if bad:
                continue
            patch_faces=quad+cap
            simple=[face for j,face in enumerate(origf) if j not in gone and j not in deleted]
            if crossings(new,simple+patches,patch_faces) or crossings(new,patch_faces,patch_faces):
                continue
            v=new
            if i<2:centers.append((eye_center,radius))
            deleted|=gone
            patches.extend(quad+cap)
            assign={str(i): {'outer': rim, 'transition': bb, 'support': oo, 'rim': ii, 'inside': pp}}
            loops.update(assign)
            measurements.append({'feature':i,'status':'built','sides':n,'patch_faces':len(quad)+len(cap)})
            break
        else:
            measurements.append({'feature':i,'status':'needs manual patch'})
    return v,[f for j,f in enumerate(origf) if j not in deleted]+patches,loops,centers


def reduce_strips(v, faces, target, locked):
    """Remove only full quad ribbons, with local direction and shape guardrails."""
    n = len(v); v=v.copy(); f=list(faces); record=[]; track=np.arange(n)
    for attempt in range(110):
        total=sum(len(g)-2 for g in f)
        if total<=target:break
        ed=adjacency(f)
        keys=sorted(ed); index={k:i for i,k in enumerate(keys)}; parent=np.arange(len(keys))
        def root(i):
            while parent[i]!=i: i=parent[i]
            return i
        for q in f:
            if len(q)!=4:continue
            ix=[index[tuple(sorted(e))] for e in edges(q)]
            for a,b in zip(ix[:2],ix[2:]):parent[root(a)]=root(b)
        strip=defaultdict(list)
        for i,k in enumerate(keys):strip[root(i)].append(k)
        options=[]
        for row in strip.values():
            if len(row)<4:continue
            ids=np.ravel(row)
            if len(set(ids))!=len(ids) or set(ids)&locked:continue
            if any(len(ed[k])!=2 for k in row):continue
            if any(len(f[t[0]])!=4 for k in row for t in ed[k]):continue
            a,b=np.array(row).T
            mid=(v[a]+v[b])*.5
            x,y,z=mid.T
            x=np.abs(x)
            # Hinge support costs are regional (neutral A pose).
            g = 1.+2*np.exp(-((z-.278)/.033)**2)+1.1*np.exp(-((z-.48)/.055)**2)
            g += 1.6*np.exp(-((z-.695)/.044)**2)*(x>.16)+1.3*np.exp(-((z-.755)/.045)**2)*(x>.10)
            g += 3*(z>.85)+1.6*(x>.23)*(z<.60)+2.2*(z<.052)
            length=np.linalg.norm(v[a]-v[b],axis=1)
            cost=length*g
            options.append((.48*cost.mean()+.52*cost.max(),a,b))
        taken=False
        for _,a,b in sorted(options,key=lambda q:q[0]):
            m=np.arange(n);m[b]=a
            vv=v.copy(); vv[a]=(v[a]+v[b])*.5
            gone=0; bad=False; keep=[]; incident=set(a)|set(b)
            for q in f:
                if not incident.intersection(q):keep.append(q);continue
                new=m[q].tolist()
                k=len(set(new))
                if k<3:
                    gone+=1;continue
                if k!=len(q):bad=True;break
                A=vv[new]; old=v[q]
                old_e=np.linalg.norm(np.roll(old,-1,axis=0)-old,axis=1)
                new_e=np.linalg.norm(np.roll(A,-1,axis=0)-A,axis=1)
                if new_e.min()<.00018 or np.any(new_e>np.maximum(.050,old_e*1.42)):
                    bad=True;break
                # Signed corners on both real triangulations of a quad.
                on=np.cross(old[1:-1]-old[0],old[2:]-old[0]); nn=np.cross(A[1:-1]-A[0],A[2:]-A[0]);
                if np.min(np.einsum('ij,ij->i', unit(on),unit(nn)))<.55:
                    bad=True;break
                if len(q)==4 and quad_cost(vv,new)>max(3.80,quad_cost(v,q)+.62):bad=True;break
                keep.append(new)
            if bad or gone!=len(a):continue
            if len({tuple(sorted(g)) for g in keep})!=len(keep):continue
            check=adjacency(keep)
            if any(len(es)!=2 or es[0][1]==es[1][1] for es in check.values()):continue
            track=m[track]; f=keep;v=vv;record.append(int(gone)); taken=True;break
        if not taken:break
    return v,f,record,track


def route_triangles(v, f, locked):
    """Convert remaining pairs by inserting an edge along a short dual-face path.

    Splits preserve the current source-local shape; pairs can remain if every
    connecting path crosses one of the protected facial rings.
    """
    v = list(v.copy()); f = list(f)
    splits = []
    for _ in range(16):
        ed = adjacency(f)
        adj = defaultdict(dict)
        for e, rows in ed.items():
            if len(rows)!=2 or set(e) & locked:continue
            i, j = (r[0] for r in rows)
            if len(f[i]) in (3,4) and len(f[j]) in (3,4):
                adj[i][j]=adj[j][i]=e
        tr = {i for i,g in enumerate(f) if len(g)==3}
        if not tr:break
        paths=[]
        for i in sorted(tr):
            seen={i};pending=deque([[i]])
            while pending:
                path=pending.popleft()
                if len(path)>31:continue
                a=path[-1]
                for j in sorted(set(adj[a])-seen):
                    seen.add(j)
                    q=path+[j]
                    if j in tr:
                        paths.append(q);pending.clear();break
                    pending.append(q)
        if not paths:break
        path=min(paths,key=len); mark={}; assigned=defaultdict(set)
        for a,b in zip(path,path[1:]):
            e=adj[a][b];mark[e]=len(v);v.append((v[e[0]]+v[e[1]])*.5);assigned[a].add(e);assigned[b].add(e)
        parts=[]; v0=np.array(v)
        for i in path:
            perimeter=[]
            for e in edges(f[i]):
                perimeter.append(e[0]);k=tuple(sorted(e))
                if k in assigned[i]:perimeter.append(mark[k])
            if len(perimeter)==4:
                parts.append(perimeter);continue
            # Prefer the all-quad split with the two widest, correctly oriented faces.
            best=float('inf'); solution=None
            for k in range(3):
                p=perimeter[k:]+perimeter[:k]; pair=[p[:4],[p[0]]+p[3:]]
                if {p[0],p[3]}.issubset(f[i]):continue
                cost=sum(quad_cost(v0,g) for g in pair)
                if cost<best:best=cost;solution=pair
            if solution is None:raise RuntimeError('invalid dual path')
            parts.extend(solution)
        use=set(path);f=[g for i,g in enumerate(f) if i not in use]+parts;splits.append(len(path)-1)
    return np.asarray(v),f,splits


def relax(v, faces, locked):
    """Small tangent moves; guards honor source normal and even up length transitions."""
    ed=adjacency(faces)
    adj=defaultdict(set); ff=defaultdict(list)
    for a,b in ed:adj[a].add(b);adj[b].add(a)
    for i,f in enumerate(faces):
        for j in f:ff[j].append(i)
    v=v.copy(); u=v.copy(); moved=set()
    reference=v.copy()
    for f in faces:
        if len(f)==3:locked.update(f)
    for es in ed.values():
        if len(es)!=2:locked.update(es[0][1:])
    # Preserve scale landmarks and local surface detail. Trial moves are individually checked.
    for i in adj:
        x,_,z=v[i]
        if z<.045 or z>.84 or (abs(x)>.225 and z<.615):locked.add(i)
    for _ in range(3):
        for i in sorted(set(adj)-locked):
            nbr=sorted(adj[i]); q=u[nbr]-u[i]
            g=max(.0001,np.mean(np.linalg.norm(q,axis=1)))
            local=ff[i]
            curs=[u[faces[k]] for k in local]
            n=unit(sum(np.cross(c[1]-c[0],c[2]-c[0]) for c in curs))
            d=q.mean(0); d=(d-n*np.dot(d,n))*.26
            amount=np.linalg.norm(d)
            d*=min(1,.002/max(amount,1e-8),.16*g/max(amount,1e-8))
            orig=u[i].copy(); u[i]+=d
            if np.linalg.norm(u[i]-reference[i])>.004:
                u[i]=orig;continue
            old_bad=sum(quad_cost(v,faces[k]) for k in local)
            new_bad=sum(quad_cost(u,faces[k]) for k in local)
            if new_bad>old_bad+.025:
                u[i]=orig;continue
            okay=True
            for old,k in zip(curs,local):
                new=u[faces[k]]
                a=np.cross(old[1:-1]-old[0],old[2:]-old[0]); b=np.cross(new[1:-1]-new[0],new[2:]-new[0])
                if np.min(np.einsum('ij,ij->i',unit(a),unit(b)))<.73:
                    okay=False;break
            if not okay:u[i]=orig;continue
            v[i]=u[i]
            if amount>1e-6:moved.add(i)
    return u,len(moved)


def eye_mesh(c,r):
    # Uniform color per face, all-quads poles. Visual iris and pupil use mat IDs, not maps.
    n=12; v=[]; f=[]; mat=[]
    for pitch in np.radians([13,28,62,119]):
        for t in range(n):
            a=2*np.pi*t/n
            v.append(np.array(c)+r*np.array([np.cos(a)*np.sin(pitch),-.86*np.cos(pitch),np.sin(a)*np.sin(pitch)]))
    for ring in range(3):
        for i in range(n):
            a=ring*n+i;b=ring*n+(i+1)%n
            f.append([a,a+n,b+n,b]);mat.append(2 if ring==0 else 1)
    v.extend([np.array(c)+[0,-.86*r,0],np.array(c)+[0,.86*r,0]])
    for i in range(0,n,2):
        j=(i+1)%n;k=(i+2)%n
        f.append([4*n,i,j,k]);mat.append(3)
        f.append([4*n+1,3*n+k,3*n+j,3*n+i]);mat.append(1)
    v=np.array(v)
    if masses(v,f,True)['signed_volume']<0:f=[g[::-1] for g in f]
    return dict(v=v.tolist(),f=f,mat=mat)


def cloud(v,f):
    q=v[tris(f)]
    # Regular barycentric sampling. This is an estimate, not an exact Hausdorff distance.
    w=np.array([(i/12,j/12,1-(i+j)/12) for i in range(13) for j in range(13-i)])
    return np.einsum('ab,nbd->nad',w,q).reshape(-1,3)


def deviation(v,f,u,g):
    a=cloud(v,f);b=cloud(u,g)
    p=cKDTree(b).query(a,workers=2)[0];q=cKDTree(a).query(b,workers=2)[0]
    def summary(reg):
        A=reg(a);B=reg(b);s=np.r_[p[A],q[B]]
        return {'p95_pct_h':float(100*np.quantile(s,.95)), 'max_pct_h':float(100*s.max())}
    region={'all':lambda p:np.ones(len(p),bool), 'head_neck':lambda p:p[:,2]>.815,
         'body':lambda p:(p[:,2]>.43)&(p[:,2]<.82)&(np.abs(p[:,0])<.17),
         'arms_hands':lambda p:(p[:,2]>.43)&(p[:,2]<.80)&(np.abs(p[:,0])>=.17),
         'legs_feet':lambda p:p[:,2]<=.43}
    return {k:summary(r) for k,r in region.items()}


def topology(f):
    e=adjacency(f)
    return {'quads':sum(len(g)==4 for g in f), 'tris':sum(len(g)==3 for g in f),
            'triangle_equivalent':sum(len(g)-2 for g in f), 'boundary_edges':sum(len(es)==1 for es in e.values()),
            'nonmanifold_edges':sum(len(es)>2 for es in e.values()),
            'winding_errors':sum(len(es)==2 and es[0][1]==es[1][1] for es in e.values())}


def run(slug, zipdir, anchor_dir, output_dir):
    v0,f0,h,floor=read_source(zipdir/f'academy-body-{slug}-quad.zip')
    source_topology=topology(f0)
    v0,f0,drop=main_component(v0,f0)
    f, fills=close(v0,f0)
    capped=f.copy()
    cap_topology=topology(f)
    f,joined=merge_tris(v0,f)
    c=np.load(anchor_dir/f'{slug}-camera.npz')
    lm=np.load(anchor_dir/f'{slug}-landmarks.npy')[:,:2].copy()
    lm[:,0]=((lm[:,0]-.5)*.244+c['cx'])/h
    lm[:,1]=(c['top']-lm[:,1]*.244-floor)/h
    v, scale=fit_head_scale(v0,lm,slug==CAST[0]); lm[:,1]=1+(lm[:,1]-1)*scale
    measurements=[]
    v,f,loops,eyes=surface_face(v,f,lm,measurements)
    lock={i for l in loops.values() for r in l.values() for i in r}
    eyes=[eye_mesh(c,r) for c,r in eyes]
    eye_tris=sum(topology(e['f'])['triangle_equivalent'] for e in eyes)
    v,f,triangle_paths=route_triangles(v,f,lock)
    v,f,strip_record,_=reduce_strips(v,f,5000-eye_tris,lock)
    v,f_moved=relax(v,f,lock.copy())
    used=np.unique(np.concatenate(f)); lut=np.full(len(v),-1);lut[used]=np.arange(len(used))
    loops={x:{k:lut[np.asarray(r,int)].tolist() for k,r in y.items()} for x,y in loops.items()}
    v,f=packed(v,f)
    res=topology(f)
    if len({tuple(sorted(g)) for g in f})!=len(f):raise ValueError(f'{slug}: duplicate body faces')
    closed=lambda t: not (t['boundary_edges'] or t['nonmanifold_edges'] or t['winding_errors'])
    original=masses(v0,f0,False); baseline=masses(v0,capped,closed(cap_topology)); after=masses(v,f,closed(res))
    def diff(a,b):
        d=np.asarray(b)-a
        return {'xyz_pct_h':(100*d).tolist(),'distance_pct_h':float(100*np.linalg.norm(d))}
    volume=diff(baseline['volume_centroid'],after['volume_centroid']) if 'volume_centroid' in baseline and 'volume_centroid' in after else None
    result={'character':slug,'source':source_topology,'source_fragments_removed':drop,'source_caps':fills,
            'paired_triangles':joined,'quad_completion_ribbons':triangle_paths,'strips_removed':strip_record,'body_vertices_relaxed':f_moved,
            'face':measurements,'mesh':res,'eyes_triangle_equivalent':eye_tris,'total_triangle_equivalent':res['triangle_equivalent']+eye_tris,
            'surface_centroid_shift':diff(original['surface_centroid'],after['surface_centroid']),
            'closed_volume_centroid_shift':volume,'regional_deviation':deviation(v0,f0,v,f),
            'chin_height_pct_h':100*float(lm[152,1]),'head_ratio':1/(1-float(lm[152,1])),
            'deterministic_chin_correction':scale,'raw_source_height':float(h)}
    chin_depth=silhouette(f,v,[lm[152]])[0]
    chin=[float(lm[152,0]),float(chin_depth),float(lm[152,1])] if np.isfinite(chin_depth) else None
    data=dict(v=v.tolist(), f=f, origin_v=v0.tolist(), origin_f=f0, eyes=eyes, loops=loops, chin=chin, report=result)
    (output_dir/f'{slug}.json').write_text(json.dumps(data,ensure_ascii=False),encoding='utf-8')
    print(slug,'source holes',source_topology['boundary_edges'],'body',res,'features',measurements,'total',result['total_triangle_equivalent'],flush=True)
    return result


def main():
    parser=ArgumentParser(description=__doc__)
    parser.add_argument('zip_dir',type=Path)
    parser.add_argument('anchor_dir',type=Path)
    parser.add_argument('output_dir',type=Path)
    parser.add_argument('--cast',nargs='+',choices=CAST,default=CAST)
    args=parser.parse_args();args.output_dir.mkdir(exist_ok=True,parents=True)
    results=[run(slug,args.zip_dir,args.anchor_dir,args.output_dir) for slug in args.cast]
    (args.output_dir/'metrics.json').write_text(json.dumps(results,indent=2,ensure_ascii=False),encoding='utf-8')


if __name__=='__main__':
    main()

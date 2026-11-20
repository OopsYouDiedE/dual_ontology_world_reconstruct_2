"""Small flat-shaded mesh writer. Coordinates are metres, Y up, camera toward -Z."""
from collections import defaultdict
from functools import lru_cache
from math import cos, sin, tau, pi
from pathlib import Path
import json, struct
import numpy as np

ROOT = Path(__file__).resolve().parents[3]
OUT = ROOT / 'scenes/blue_prince_lab/reference'

@lru_cache(None)
def pigment(hexcode):
    rgb = np.array(list(bytes.fromhex(hexcode))) / 255
    return np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055)**2.4)

def shade(color, amount):
    return bytes(max(0,min(255,round(v*amount))) for v in bytes.fromhex(color)).hex()

class Mesh:
    def __init__(self):
        self.faces = defaultdict(list)

    def face(self, points, color, mat='paint'):
        for i in range(1,len(points)-1):
            self.faces[mat].append(([points[0],points[i],points[i+1]], color))

    def box(self, p, size, c, angle=0, mat='paint'):
        x,y,z = p; w,h,d = [v*.5 for v in size]
        pts = [(x+cos(angle)*a+sin(angle)*e,y+b,z-sin(angle)*a+cos(angle)*e) for a,b,e in
               [(-w,-h,-d),(w,-h,-d),(w,h,-d),(-w,h,-d),(-w,-h,d),(w,-h,d),(w,h,d),(-w,h,d)]]
        for ids in [(0,3,2,1),(4,5,6,7),(0,4,7,3),(1,2,6,5),(3,7,6,2),(0,1,5,4)]:
            self.face([pts[i] for i in ids],c,mat)

    def rod(self, a,b,r,c,n=8,r2=None,mat='paint',phase=0):
        a,b=np.array(a),np.array(b); axis=b-a; axis=axis/np.linalg.norm(axis)
        u=np.cross(axis, (0,0,1) if abs(axis[2])<.9 else (0,1,0)); u/=np.linalg.norm(u); v=np.cross(axis,u)
        sides=[u*cos(phase+tau*i/n)+v*sin(phase+tau*i/n) for i in range(n)]
        lo=[a+s*r for s in sides]; hi=[b+s*(r if r2 is None else r2) for s in sides]
        for i in range(n): self.face([lo[i-1],lo[i],hi[i],hi[i-1]],c,mat)
        self.face(lo[::-1],c,mat); self.face(hi,c,mat)

    def board(self,a,b,w,d,c):
        # Rectangular member lying in the XY plane (rafters, glazing bars, braces).
        x,y,z=a; X,Y,Z=b; length=np.hypot(X-x,Y-y); dx=(y-Y)*w/(2*length); dy=(X-x)*w/(2*length)
        self.slab([(x+dx,y+dy),(x-dx,y-dy),(X-dx,Y-dy),(X+dx,Y+dy)],z,d,c)

    def slab(self,poly,z,d,c,mat='paint'):
        # Convex planar extrusion. Wind front face towards +Z regardless of input order.
        if sum(p[0]*q[1]-p[1]*q[0] for p,q in zip(poly,poly[1:]+poly[:1]))<0: poly=poly[::-1]
        lo=[(x,y,z-d/2) for x,y in poly]; hi=[(x,y,z+d/2) for x,y in poly]
        self.face(lo[::-1],c,mat); self.face(hi,c,mat)
        for i in range(len(poly)): self.face([lo[i-1],lo[i],hi[i],hi[i-1]],c,mat)

    def ring(self,center,r,R,d,c,n=32,start=0,end=tau,mat='paint',ry=1):
        x,y,z=center
        for i in range(n):
            a=start+(end-start)*i/n; b=start+(end-start)*(i+1)/n
            points=[(x+rad*cos(t),y+rad*ry*sin(t)) for rad,t in [(r,a),(R,a),(R,b),(r,b)]]
            lo=[(*p,z-d/2) for p in points]; hi=[(*p,z+d/2) for p in points]
            self.face(lo[::-1],c,mat);self.face(hi,c,mat)
            for j in [2,0]+([1] if i==0 and end-start<tau-.001 else [])+([3] if i==n-1 and end-start<tau-.001 else []):self.face([lo[j-1],lo[j],hi[j],hi[j-1]],c,mat)

    def save(self,name):
        path=OUT/'meshes'/(name+'.glb'); raw=bytearray(); views=[]; access=[]; primitives=[]; materials=[]
        def attr(arr,kind,ctype=5126,normalized=False):
            while len(raw)%4: raw.append(0)
            data=arr.tobytes(); views.append(dict(buffer=0,byteOffset=len(raw),byteLength=len(data))); raw.extend(data)
            desc=dict(bufferView=len(views)-1,componentType=ctype,count=len(arr),type=kind)
            if kind=='VEC3' and ctype==5126: desc.update(min=arr.min(axis=0).tolist(),max=arr.max(axis=0).tolist())
            if normalized: desc['normalized']=True
            access.append(desc); return len(access)-1
        for kind, faces in self.faces.items():
            pts=np.array([f[0] for f in faces],np.float32); cs=np.array([pigment(f[1]) for f in faces]); norm=np.cross(pts[:,1]-pts[:,0],pts[:,2]-pts[:,0]); lens=np.linalg.norm(norm,axis=1); ok=lens>1e-9
            pts=pts[ok]; cs=cs[ok]; norm=norm[ok]/lens[ok,None]
            verts=np.column_stack([pts.reshape(-1,3),norm.repeat(3,axis=0),cs.repeat(3,axis=0)]).astype('<f4'); verts,idx=np.unique(verts,axis=0,return_inverse=True)
            attrs={k:attr(verts[:,i:i+3].copy(),'VEC3') for i,k in [(0,'POSITION'),(3,'NORMAL'),(6,'COLOR_0')]}
            prim=dict(attributes=attrs,indices=attr(idx.astype('<u4').reshape(-1),'SCALAR',5125),material=len(materials));primitives.append(prim)
            m=dict(name=kind,doubleSided=True,pbrMetallicRoughness=dict(metallicFactor=.44 if kind=='metal' else 0,roughnessFactor=.36 if kind=='metal' else .95))
            if kind=='glass': m['extensions']={'KHR_materials_unlit':{}}
            materials.append(m)
        while len(raw)%4: raw.append(0)
        doc=dict(asset={'version':'2.0'},extensionsUsed=['KHR_materials_unlit'],scene=0,scenes=[{'nodes':[0]}],nodes=[dict(name=name,mesh=0)],meshes=[dict(primitives=primitives)],materials=materials,accessors=access,bufferViews=views,buffers=[dict(byteLength=len(raw))]); j=json.dumps(doc,separators=(',',':')).encode();j+=b' '*(-len(j)%4)
        path.write_bytes(struct.pack('<4sII',b'glTF',2,28+len(j)+len(raw))+struct.pack('<I4s',len(j),b'JSON')+j+struct.pack('<I4s',len(raw),b'BIN\x00')+raw)

class Scene:
    def __init__(self,name): self.name=name; self.items=[]
    def add(self,mesh,p=(0,0,0),yaw=0,scale=(1,1,1)): self.items.append((mesh,p,yaw,scale))
    def save(self):
        assets=list(dict.fromkeys(m for m,*_ in self.items)); txt=['[gd_scene format=3]','']
        for i,m in enumerate(assets): txt.append(f'[ext_resource type="PackedScene" path="res://scenes/blue_prince_lab/reference/meshes/{m}.glb" id="{i+1}"]')
        txt+=['',f'[node name="{self.name}" type="Node3D"]']
        for i,(m,p,yaw,s) in enumerate(self.items):
            vec=lambda q:', '.join(f'{v:.6f}' for v in q)
            txt+=['',f'[node name="{m}_{i}" parent="." instance=ExtResource("{assets.index(m)+1}")]',f'position = Vector3({vec(p)})',f'rotation = Vector3(0, {yaw:.6f}, 0)',f'scale = Vector3({vec(s)})']
        (OUT/(self.name+'.tscn')).write_text('\n'.join(txt)+'\n',encoding='utf8')

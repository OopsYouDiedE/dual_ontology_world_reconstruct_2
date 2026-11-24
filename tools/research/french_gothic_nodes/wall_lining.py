"""Reusable local interior bay masters and GN placement, in Blender Z-up coordinates."""
import math
import bpy
from mathutils import Vector
from gn_graph import num
from math import pi, sin, cos, sqrt

COLORS = {'Ashlar':(.61,.54,.42),'Moulding':(.78,.70,.55),'Lead':(.075,.077,.09),
          'Cobalt':(.075,.21,.57),'Ruby':(.58,.075,.11),'Amber':(.85,.49,.12),'Pearl':(.40,.67,.74),'Lancet':(1,1,1),'Traced':(1,1,1)}
GLASS = ['Cobalt','Ruby','Amber','Pearl']

def master(rose):
    verts, faces, indices = [], [], []
    def face(points, mat):
        start=len(verts); verts.extend(points); faces.append(tuple(range(start,len(verts)))); indices.append(list(COLORS).index(mat))
    def slab(poly, front, back, mat):
        for y,seq in [(front,poly),(back,poly[::-1])]: face([(x,y,z) for x,z in seq],mat)
        for i,(x,z) in enumerate(poly):
            xx,zz=poly[(i+1)%len(poly)]; face([(x,front,z),(x,back,z),(xx,back,zz),(xx,front,zz)],mat)
    def rect(x,z,w,h,a,b,mat): slab([(x,z),(x+w,z),(x+w,z+h),(x,z+h)],a,b,mat)
    def tube(path,r,y,mat):
        rings=[]
        for i,(x,z) in enumerate(path):
            v=Vector(path[min(i+1,len(path)-1)])-Vector(path[max(i-1,0)]);v.normalize()
            rings.append([(x-v.y*r*cos(t*pi/4),y+r*sin(t*pi/4),z+v.x*r*cos(t*pi/4)) for t in range(8)])
        for a,b in zip(rings,rings[1:]):
            for k in range(8): face([a[k],a[(k+1)%8],b[(k+1)%8],b[k]],mat)
    def circle(cx,cz,r): return [(cx+r*cos(i*pi/32),cz+r*sin(i*pi/32)) for i in range(65)]
    w=1.5; sill=1.15; top=4.65
    rect(-w,0,2*w,sill,-.07,.16,'Ashlar');rect(-w,sill-.13,2*w,.13,-.18,.17,'Moulding')
    rect(-w,top,2*w,.16,-.16,.17,'Moulding')
    for side in (-1,1):
        x=side*(w-.11);rect(x-.11,0,.22,top,-.16,.14,'Ashlar');rect(x-.14,0,.28,.24,-.21,.14,'Moulding')
    # Blind arcade and engaged shafts project into the ambulatory.
    for cx in [-.84,0,.84]:
        path=[(cx-.34,.20),(cx-.34,.66)]+[(cx+t*.34,.66+.29*(1-abs(t))**.7) for t in [-1,-.8,-.55,-.3,0,.3,.55,.8,1]]+[(cx+.34,.20)]
        tube(path,.043,-.12,'Moulding')
    for cx in [-1.38,1.38]:
        for off in [-.06,.06]:tube([(cx+off,.24),(cx+off,top-.32)],.057,-.17,'Moulding')
        for dz,wid in [(0,.27),(.09,.32),(.18,.39)]:rect(cx-wid/2,top-.34+dz,wid,.09,-.24,.12,'Moulding')
    if rose:
        cz=2.9;r=1.24
        # Fill from circular opening to the rectangular wall boundary, keeping a real reveal.
        for i in range(64):
            poly=[]
            for j,outer in [(i,False),(i,True),(i+1,True),(i+1,False)]:
                a=2*pi*j/64;dx,dz=cos(a),sin(a); rr=min(w/max(abs(dx),1e-8),(top-cz if dz>=0 else cz-sill)/max(abs(dz),1e-8)) if outer else r
                poly.append((rr*dx,cz+rr*dz))
            slab(poly,-.05,.14,'Ashlar')
        # The hub branches into twelve main bars; the outer order is finer.
        for rr in [r,.19*r]: tube(circle(0,cz,rr),.018,-.072,'Moulding')
        for k in range(12):
            a=(k+.5)*pi/6
            def point(rr,t): return (r*rr*cos(t),cz+r*rr*sin(t))
            tube([point(.19,a),point(.58,a),point(1,a)],.012,-.065,'Moulding')
            tube([point(.58,a),point(.74,a+.045),point(.80,a+.105),point(.83,a+pi/12)],.008,-.061,'Moulding')
            tube([point(.58,a),point(.74,a-.045),point(.80,a-.105),point(.83,a-pi/12)],.008,-.061,'Moulding')
        for i in range(96):
            q=[(0,.032,cz)]+[(r*cos(j*pi/48),.032,cz+r*sin(j*pi/48)) for j in (i,i+1)]
            face(q,'Traced')
    else:
        for k,cx in enumerate([-.68,.68]):
            hw=.62; spring=2.94; peak=4.23
            def arch(x):return spring+(peak-spring)*sqrt(max(0,1-((abs(x)/hw+0.35)/1.35)**2))/sqrt(1-(.35/1.35)**2)
            xx=[-hw+2*hw*i/24 for i in range(25)];curve=[(cx+x,arch(x)) for x in xx]
            for i in range(24):
                a,b=curve[i:i+2];slab([a,b,(b[0],top),(a[0],top)],-.045,.14,'Ashlar')
                face([(a[0],.045,sill),(b[0],.045,sill),(b[0],.045,b[1]),(a[0],.045,a[1])],'Lancet')
            tube([(cx-hw,sill),*curve,(cx+hw,sill)],.045,-.09,'Moulding')
            for z in [1.95,2.75]:tube([(cx-hw,z),(cx+hw,z)],.009,-.012,'Lead')
        for x,ww in [(-w,.20),(-.06,.12),(1.3,.20)]:rect(x,sill,ww,top-sill,-.04,.14,'Ashlar')
    name='Radial rose' if rose else 'Paired lancets'; mesh=bpy.data.meshes.new(name);mesh.from_pydata(verts,[],faces);mesh.update()
    for label,color in COLORS.items():
        mat=bpy.data.materials.get('Lining '+label) or bpy.data.materials.new('Lining '+label);mat.diffuse_color=(*color,1);mat.use_backface_culling=False;mat.use_nodes=True; mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value=(*color,1);mesh.materials.append(mat)
    from pathlib import Path
    uv=mesh.uv_layers.new(name='Window projection')
    for loop in mesh.loops:
        x,_,z=mesh.vertices[loop.vertex_index].co
        if rose: coords=(.5+x/(2*r),.5+(z-cz)/(2*r))
        else:
            k=int(x>0); cx=(-.68,.68)[k]; coords=((k+(x-cx+hw)/(2*hw))/2,(z-sill)/(peak-sill))
        uv.data[loop.index].uv=coords
    mat=mesh.materials[list(COLORS).index('Traced' if rose else 'Lancet')]; tex=mat.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(Path(__file__).with_name('rose_register.png' if rose else 'lancet_register.png')));tex.image.pack()
    mat.node_tree.links.new(tex.outputs['Color'],mat.node_tree.nodes.get('Principled BSDF').inputs['Base Color'])
    mesh.polygons.foreach_set('material_index',indices)
    return bpy.data.objects.new(name,mesh) # referenced by GN, not placed in the scene separately

def build(Kit):
    height=num('Lining height scale',1,.85,1.18); g=Kit('FG2 | Interior wall and glazed openings',[height]); h=g.i[height[0]]
    def src(rose):
        n=g.node('GeometryNodeObjectInfo');g.put(n,'Object',master(rose));return n.outputs['Geometry']
    bay,rose=src(False),src(True); pieces=[]
    def wall(unit,x,y,angle,width):
        pieces.append(g.op('GeometryNodeTransform',[('Geometry',unit),('Translation',(x,y,0)),('Rotation',(0,0,angle)),('Scale',g.xyz(width/3,1,h))]))
    for side in [-1,1]:
        for lo,hi in [(-24,-16.4),(-9.6,-3.6)]:
            for i in range(3):wall(bay,side*6.85,lo+(hi-lo)*(i+.5)/3,-side*pi/2,(hi-lo)/3)
        wall(rose,side*10.48,-13,-side*pi/2,3.0)
        for yy in [-15.45,-10.55]:wall(bay,side*10.48,yy,-side*pi/2,1.9)
        for y,rot in [(-16.4,pi),(-9.6,0)]:wall(bay,side*8.665,y,rot,3.63)
    for i in range(8):
        a=-(i+.5)*pi/8;r=5.78;wall(bay,r*cos(a)*cos(pi/16),-24+r*sin(a)*cos(pi/16),a-pi/2,2*r*sin(pi/16))
    return g.end(g.join(*pieces)),height

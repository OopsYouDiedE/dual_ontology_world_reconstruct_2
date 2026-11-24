"""Build and verify an editable original-group reuse fixture; run with -- MAIN_DIR."""
import sys, json, math
from pathlib import Path
import bpy
import numpy as np
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from gn_graph import Graph,num,toggle,G,I

out=Path(sys.argv[-1]).resolve(); bpy.ops.wm.read_factory_settings(use_empty=True)
names=['ArcsFromEdges','Gothic SupportColumn From EDge','GenerateStairCase']
with bpy.data.libraries.load(str(out/'nodes.blend')) as (_,lib): lib.node_groups=list(names)
arc,pier,stair=lib.node_groups
spec=[('Geometry',G,None,None,None),num('Bays',2,1,8,I),num('Clear axis span',6,4,8),num('Pitch',4,3,6),num('Seat height',4.2,3,5),num('Arch height',1.8,1,3),toggle('Source arches'),toggle('Source supports'),toggle('Seat adapters'),('Stair sample','NodeSocketBool',False,None,None),num('Stair width',.85,.6,1.1)]
g=Graph('Reuse | Original groups on a bay grid',spec); span,pitch,h,rise=[g.i[k] for k in ['Clear axis span','Pitch','Seat height','Arch height']]; count=g.i['Bays']; mul=lambda a,b:g.math('MULTIPLY',a,b); add=lambda a,b:g.math('ADD',a,b)
def at(geo,x=0,y=0,z=0):return g.move(geo,g.xyz(x,y,z))
def line(n,dx=0,dy=0):return g.op('GeometryNodeMeshLine',[('Count',n),('Offset',g.xyz(dx,dy,0))])
def row(geo,n):return g.op('GeometryNodeInstanceOnPoints',[('Points',line(n,dy=pitch)),('Instance',geo)])
def pair(geo):return g.join(geo,at(geo,span))
def orig(tree,**kw):return g.op('GeometryNodeGroup',list(kw.items()),node_tree=tree)
def visible(k,geo):return g.op('GeometryNodeSwitch',[('Switch',g.i[k]),('True',geo)],input_type='GEOMETRY')
def realize(geo):return g.op('GeometryNodeRealizeInstances',[(0,geo)])
# Recenter the asymmetric edge support. Normalize its full evaluated height to meet the adapter.
support=realize(orig(pier,Geometry=line(2,dx=.05),Depth=.30,DepthLos=0,HeightWall=h,PeakHeight=.12)); box=g.node('GeometryNodeBoundBox'); g.put(box,'Geometry',support)
def vec(op,a,b):return g.op('ShaderNodeVectorMath',[(0,a),(1,b)],operation=op)
lo=box.outputs['Min']; hi=box.outputs['Max']; mid=vec('MULTIPLY',vec('ADD',lo,hi),(-.5,-.5,0)); sep=g.node('ShaderNodeSeparateXYZ');g.put(sep,0,lo); centered=g.move(support,vec('ADD',mid,g.xyz(0,0,mul(sep.outputs['Z'],-1)))); size=g.node('ShaderNodeSeparateXYZ');g.put(size,0,vec('SUBTRACT',hi,lo)); scalez=g.math('DIVIDE',g.math('SUBTRACT',h,.14),size.outputs['Z']); fitted=g.op('GeometryNodeTransform',[('Geometry',centered),('Scale',g.xyz(1,1,scalez))]); fitted=g.join(fitted,g.op('GeometryNodeTransform',[('Geometry',fitted),('Rotation',(0,0,math.pi/2))])); posts=row(pair(fitted),add(count,1)); cap=g.op('GeometryNodeMeshCube',[('Size',(.60,.60,.14))]); caps=row(pair(at(cap,z=add(h,-.07))),add(count,1))
# With DecorRes locked to 3 in this pinned asset, the first 17 vertices trace the
# full-width arch outline. The complete Arcs output also includes a wall panel.
# Sample the original contour live; form a local rectangular stone section around it.
def original_arch(length):
    src=realize(orig(arc,Geometry=line(2,dx=length),TotalHeight=rise,DecorRes=3,ArcProportion=.78,ArcPadToEdge=.15,ArcIndentIn=.15,ArcIndentDepth=.18))
    position=g.node('GeometryNodeInputPosition').outputs[0]
    def sample(index):return g.op('GeometryNodeSampleIndex',[('Geometry',src),('Value',position),('Index',index)],data_type='FLOAT_VECTOR',domain='POINT')
    first=g.node('ShaderNodeSeparateXYZ');g.put(first,0,sample(0)); ix=g.node('GeometryNodeInputIndex').outputs[0]; coords=sample(g.math('FLOOR',g.math('DIVIDE',ix,2),0)); t=g.math('MODULO',ix,2); zbase=mul(first.outputs['Z'],-1); faces=[]
    for y0,z0,y1,z1 in [(-.13,0,.13,0),(.13,0,.13,.22),(.13,.22,-.13,.22),(-.13,.22,-.13,0)]:
        grid=g.op('GeometryNodeMeshGrid',[('Vertices X',17),('Vertices Y',2)]); delta=g.xyz(0,add(y0,mul(y1-y0,t)),add(zbase,add(z0,mul(z1-z0,t)))); faces.append(g.op('GeometryNodeSetPosition',[('Geometry',grid),('Position',vec('ADD',coords,delta))]))
    return g.op('GeometryNodeMergeByDistance',[('Geometry',g.join(*faces)),('Distance',.00001)])
across=at(original_arch(span),z=h); along=g.op('GeometryNodeTransform',[('Geometry',original_arch(pitch)),('Rotation',(0,0,math.pi/2))]); arches=g.join(row(across,add(count,1)),row(pair(at(along,z=h)),count)); stairs=at(orig(stair,StairsWidth=g.i['Stair width']),-3,0,0)
root=g.end(realize(g.join(*(visible(k,geo) for k,geo in zip(['Source arches','Source supports','Seat adapters','Stair sample'],[arches,posts,caps,stairs])))))
obj=bpy.data.objects.new('Original group bay | edit modifier',bpy.data.meshes.new('Host'));bpy.context.collection.objects.link(obj);bpy.context.view_layer.objects.active=obj; obj.select_set(True); obj.modifiers.new('Bay controls','NODES').node_group=root
for area in bpy.context.screen.areas:
    if area.type=='PROPERTIES':area.spaces.active.context='MODIFIER'
    if area.type=='VIEW_3D':
        v=area.spaces.active.region_3d;v.view_distance=18;v.view_location=(3,4,3);v.view_rotation=Vector((-1,1,-.4)).to_track_quat('-Z','Y')
file=out/'original-group-bay.blend'; bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(file),compress=True);bpy.ops.wm.open_mainfile(filepath=str(file));obj=bpy.context.view_layer.objects.active;mod=obj.modifiers[0]; ui=mod.node_group.interface.items_tree
assert set(names)=={n.node_tree.name for n in mod.node_group.nodes if n.type=='GROUP'}
def setv(**kw):
    for k,v in kw.items():mod[ui[k].identifier]=v
    obj.update_tag();bpy.context.view_layer.update()
def geometry():
    ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get()); m=ev.to_mesh(); ids={i for p in m.polygons for i in p.vertices}; coords=np.array([tuple(m.vertices[i].co) for i in ids]); f=len(m.polygons);ev.to_mesh_clear(); return coords,f
def isolate(k):setv(**{name:name==k for name in ['Source arches','Source supports','Seat adapters','Stair sample']})
records=[]
for n,w,p,h in [(1,6,4,4.2),(2,6,4,4.2),(4,7.5,3.2,4.8)]:
    setv(**{'Bays':n,'Clear axis span':w,'Pitch':p,'Seat height':h}); r={}; stations=[(x,j*p) for x in [0,w] for j in range(n+1)]
    for k,z in [('Source supports',h-.14),('Seat adapters',h),('Source arches',h)]:
        isolate(k); a,f=geometry(); assert f>0; r[k]=f; errors=[]
        for x,y in stations:
            near=a[(abs(a[:,0]-x)<=.301)&(abs(a[:,1]-y)<=.301)]; assert len(near),(k,x,y); observed=near[:,2].min() if k=='Source arches' else near[:,2].max(); errors.append(abs(observed-z))
        assert max(errors)<1e-4,(k,errors);r[k+' max seat error']=max(errors)
    assert np.isclose(geometry()[0][:,1].max(),n*p,atol=.3),(a.min(0),a.max(0),n,p);records.append(dict(bays=n,stations=len(stations),counts=r))
for k,perbay,extra in [('Source arches',3,1),('Source supports',2,2),('Seat adapters',2,2)]:
    unit=records[0]['counts'][k]/(perbay+extra); assert all(rec['counts'][k]==unit*(perbay*rec['bays']+extra) for rec in records[:2])
isolate('Stair sample'); stair_checks=[]
for width in [.65,.95]:
    setv(**{'Stair width':width});a,f=geometry();extent=np.ptp(a,axis=0);assert min(extent)>.25 and f>0;stair_checks.append(dict(width=width,faces=f,extent=extent.tolist()))
assert stair_checks[1]['extent'][0]>stair_checks[0]['extent'][0]
(out/'original-group-checks.json').write_text(json.dumps({'bays':records,'independent stair':stair_checks},indent=2))
setv(**{'Source arches':True,'Source supports':True,'Seat adapters':True,'Stair sample':False,'Bays':2,'Clear axis span':6.,'Pitch':4.,'Seat height':4.2}); scene=bpy.context.scene;bpy.ops.object.camera_add(); cam=bpy.context.object;scene.camera=cam;cam.location=(16,-10,10);cam.rotation_euler=(Vector((3,4,3))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=14;scene.render.engine='BLENDER_WORKBENCH';scene.display.shading.show_cavity=True;scene.display.shading.color_type='SINGLE';scene.display.shading.single_color=(.76,.72,.60);scene.render.resolution_x=900;scene.render.resolution_y=700;scene.render.resolution_percentage=100;scene.render.filepath=str(out/'original-group-bay.png');bpy.ops.render.render(write_still=True)

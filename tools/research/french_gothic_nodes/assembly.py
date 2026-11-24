"""Blender -b -P assembly.py -- DIRECTORY containing the extracted nodes.blend."""
import math
import sys
from pathlib import Path
import bpy
from mathutils import Vector

out = Path(sys.argv[-1]).resolve()
bpy.ops.wm.read_factory_settings(use_empty=True)
with bpy.data.libraries.load(str(out/'nodes.blend')) as (_, lib):
    lib.node_groups = ['Generate Cathedral Combined']
shell = lib.node_groups[0]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from gn_graph import Graph, num, toggle, F, I, B, G

# Two halves meet at a pointed crown. DX and DY are horizontal half-span components.
a = Graph('FG | Pointed rib', [num('DX',3,-12,12),num('DY',0,-12,12),num('Rise',2,.1,8),num('Radius',.12,.03,.6)])
dx,dy,r,h = [a.i[k] for k in ('DX','DY','Radius','Rise')]
parts = []
for sign in (-1,1):
    x=a.math('MULTIPLY',dx,sign); y=a.math('MULTIPLY',dy,sign)
    curve=a.op('GeometryNodeCurveQuadraticBezier',[('Resolution',16),('Start',a.xyz(x,y,0)),('Middle',a.xyz(x,y,a.math('MULTIPLY',h,.64))),('End',a.xyz(0,0,h))])
    parts.append(curve)
profile=a.op('GeometryNodeCurvePrimitiveCircle',[('Resolution',8),('Radius',r)])
rib=a.end(a.op('GeometryNodeCurveToMesh',[('Curve',a.join(*parts)),('Profile Curve',profile),('Fill Caps',True)]))

inside_specs=[num('Bays',5,2,10,I),num('Nave width',6,4,8),num('Spring height',4.2,3,5),num('Crown rise',2.2,1,3),num('Column radius',.28,.18,.45),num('Rib radius',.13,.08,.2)]
g=Graph('FG | Interior arcade and ribs',inside_specs)
count,width,high,rise,radius,rr=[g.i[k[0]] for k in inside_specs]
step=g.math('DIVIDE',20,count); half=g.math('MULTIPLY',width,.5); hs=g.math('MULTIPLY',step,.5)

def pointed(x,y): return g.op('GeometryNodeGroup',[('DX',x),('DY',y),('Rise',rise),('Radius',rr)],node_tree=rib)
def cylinder(radius,depth,z):
    geo=g.op('GeometryNodeMeshCylinder',[('Vertices',16),('Radius',radius),('Depth',depth)])
    return g.move(geo,g.xyz(0,0,z))
def pair(geo):
    return g.join(*(g.move(geo,g.xyz(g.math('MULTIPLY',half,s),0,0)) for s in (-1,1)))
def repeat(geo,n,yoff):
    line=g.op('GeometryNodeMeshLine',[('Count',n),('Start Location',g.xyz(0,yoff,0)),('Offset',g.xyz(0,step,0))])
    return g.op('GeometryNodeInstanceOnPoints',[('Points',line),('Instance',geo)])
shaft=cylinder(radius,high,g.math('MULTIPLY',high,.5)); trim=g.math('MULTIPLY',radius,1.5)
column=g.join(shaft,cylinder(trim,.26,.13),cylinder(trim,.26,g.math('SUBTRACT',high,.13)))
frames=g.join(pair(column),g.move(pointed(half,0),g.xyz(0,0,high)))
bay=g.join(pair(pointed(0,hs)),pointed(half,hs),pointed(half,g.math('MULTIPLY',hs,-1)))
frame_row=repeat(frames,g.math('ADD',count,1),-24)
bay_row=repeat(g.move(bay,g.xyz(0,0,high)),count,g.math('ADD',-24,hs))
floor=g.move(g.op('GeometryNodeMeshCube',[('Size',g.xyz(g.math('ADD',width,4),21,.16))]),(0,-14,-.08))
inside=g.end(g.join(frame_row,bay_row,floor))

outer_keys=['FrontRoofHeight','BellTowerRoofHeight','DomeHeightMultiplyer','SpawnCross']
outer_specs=[]
for k in outer_keys:
    s=shell.interface.items_tree[k]; d=s.default_value
    outer_specs.append(toggle(k) if s.socket_type==B else num(k,d,max(.01,d*.6),max(.1,d*1.5)))
    if s.socket_type==B: outer_specs[-1]=(k,B,d,None,None)
root=Graph('FG | Cathedral assembly',[('Geometry',G,None,None,None),toggle('Exterior'),toggle('Interior'),num('Length scale',1,.75,1.25),num('Width scale',1,.75,1.25),*inside_specs,*outer_specs])
branches=[]
for switch,group,specs in [('Exterior',shell,outer_specs),('Interior',inside,inside_specs)]:
    geo=root.op('GeometryNodeGroup',[(s[0],root.i[s[0]]) for s in specs],node_tree=group)
    branches.append(root.op('GeometryNodeSwitch',[('Switch',root.i[switch]),('True',geo)],input_type='GEOMETRY'))
scaled=root.op('GeometryNodeTransform',[('Geometry',root.join(*branches)),('Scale',root.xyz(root.i['Width scale'],root.i['Length scale'],1))])
tree=root.end(root.op('GeometryNodeRealizeInstances',[('Geometry',scaled)]))
obj=bpy.data.objects.new('Cathedral | select to edit',bpy.data.meshes.new('Generator host'))
bpy.context.collection.objects.link(obj); obj.select_set(True); bpy.context.view_layer.objects.active=obj
obj.modifiers.new('Cathedral controls','NODES').node_group=tree
for area in bpy.context.screen.areas:
    if area.type=='PROPERTIES': area.spaces.active.context='MODIFIER'
    if area.type=='VIEW_3D':
        v=area.spaces.active.region_3d; v.view_distance=60; v.view_location=(0,-14,12)
        v.view_rotation=Vector((-1,-1,-.6)).to_track_quat('-Z','Y')
bpy.context.preferences.filepaths.save_version=0
bpy.ops.wm.save_as_mainfile(filepath=str(out/'cathedral-controls.blend'),compress=True)

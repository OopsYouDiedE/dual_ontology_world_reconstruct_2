"""Build a layered procedural reconstruction of the example church, from the v1 assembly."""
from pathlib import Path
import math
import sys
import bpy
from mathutils import Vector
sys.path.insert(0,str(Path(__file__).resolve().parent))
from gn_graph import Graph, num, toggle, F, I, G

out=Path(sys.argv[-1]).resolve()
bpy.ops.wm.read_factory_settings(use_empty=True)
with bpy.data.libraries.load(str(out/'cathedral-controls.blend')) as (_,lib):
    lib.node_groups=['Generate Cathedral Combined','FG | Pointed rib','FG | Interior arcade and ribs']
shell,rib,nave=lib.node_groups

class Kit(Graph):
    def mul(self,a,b): return self.math('MULTIPLY',a,b)
    def add(self,a,b): return self.math('ADD',a,b)
    def at(self,geo,x=0,y=0,z=0): return self.move(geo,self.xyz(x,y,z))
    def box(self,x,y,z): return self.op('GeometryNodeMeshCube',[('Size',self.xyz(x,y,z))])
    def line(self,geo,count,start,offset):
        mesh=self.op('GeometryNodeMeshLine',[('Count',count),('Start Location',self.xyz(*start)),('Offset',self.xyz(*offset))]); return self.op('GeometryNodeInstanceOnPoints',[('Points',mesh),('Instance',geo)])
    def sub(self,tree,**kw): return self.op('GeometryNodeGroup',list(kw.items()),node_tree=tree)
    def arch(self,x,y,h,r=.12): return self.sub(rib,DX=x,DY=y,Rise=h,Radius=r)
    def beam(self,a,b,r):
        c=self.op('GeometryNodeCurvePrimitiveLine',[('Start',self.xyz(*a)),('End',self.xyz(*b))]); return self.tube(c,r)
    def tube(self,c,r):
        p=self.op('GeometryNodeCurvePrimitiveCircle',[('Radius',r),('Resolution',8)]); return self.op('GeometryNodeCurveToMesh',[('Curve',c),('Profile Curve',p),('Fill Caps',True)])
    def pair(self,geo):
        flip=self.op('GeometryNodeTransform',[('Geometry',geo),('Scale',(-1,1,1))]); return self.join(geo,flip)
    def grid(self,n,m):
        grid=self.op('GeometryNodeMeshGrid',[('Size X',2),('Size Y',2),('Vertices X',n),('Vertices Y',m)])
        pos=self.node('GeometryNodeInputPosition'); sep=self.node('ShaderNodeSeparateXYZ'); self.put(sep,0,pos.outputs[0]); return grid,*sep.outputs[:2]
    def deform(self,grid,x,y,z): return self.op('GeometryNodeSetPosition',[('Geometry',grid),('Position',self.xyz(x,y,z))])
    def paint(self,geo,name,color):
        mat=bpy.data.materials.get(name) or bpy.data.materials.new(name); mat.diffuse_color=(*color,1)
        return self.op('GeometryNodeSetMaterial',[('Geometry',geo),('Material',mat)])

bay=num('Bays',5,2,10,I); width=num('Nave width',6,4,8); height=num('Spring height',4.2,3,5); rise=num('Crown rise',2.2,1,3); col=num('Column radius',.28,.18,.45); radius=num('Rib radius',.13,.08,.2)
# A groin vault: match both the perimeter arches and diagonal ribs of the v1 nave.
g=Kit('FG2 | Vault web patch',[num('Half X',3,.2,12),num('Half Y',2,.2,12),rise,num('Web resolution',17,9,33,I)])
res=g.i['Web resolution']; grid,x,y=g.grid(res,res)
u=g.math('MINIMUM',g.math('ABSOLUTE',x,0),g.math('ABSOLUTE',y,0)); t=g.math('SQRT',g.math('SUBTRACT',1,u),0)
z=g.mul(g.i['Crown rise'],g.mul(t,g.add(1.28,g.mul(-.28,t))))
web=g.end(g.deform(grid,g.mul(x,g.i['Half X']),g.mul(y,g.i['Half Y']),z))

def setup(g):
    n=g.i['Bays']; w=g.mul(g.i['Nave width'],.5); step=g.math('DIVIDE',20,n); hs=g.mul(step,.5); return n,w,step,hs

def runs(g,geo,n,step,hs): return g.line(geo,n,(0,g.add(-24,hs),0),(0,step,0))

webres=num('Web resolution',17,9,33,I)
g=Kit('FG2 | Nave vault masonry',[bay,width,height,rise,webres]); n,w,s,hs=setup(g)
patch=g.sub(web,**{'Half X':w,'Half Y':hs,'Crown rise':g.i['Crown rise'],'Web resolution':g.i['Web resolution']}); webs=g.end(g.paint(runs(g,g.at(patch,z=g.add(g.i['Spring height'],.06)),n,s,hs),'Vault | limestone',(.74,.62,.43)))

# Each aisle fills the space from the nave column line to the measured example wall line.
g=Kit('FG2 | Side aisles and galleries',[bay,width,height,webres]); n,w,s,hs=setup(g); aw=g.math('SUBTRACT',7.1,w); ax=g.add(w,g.mul(aw,.5)); gh=g.mul(g.i['Spring height'],.84)
side=g.sub(web,**{'Half X':g.mul(aw,.5),'Half Y':hs,'Crown rise':.72,'Web resolution':g.i['Web resolution']}); deck=g.at(g.box(aw,s,.15),z=g.add(gh,.84)); wall=g.at(g.box(.16,s,.46),x=g.mul(aw,-.5),z=g.add(gh,1.12)); side=g.join(g.at(side,z=gh),deck,wall,g.at(g.arch(0,hs,.72,.10),x=g.mul(aw,.5),z=gh)); slab=g.at(g.box(aw,24,.16),x=ax,y=-12,z=-.08)
# v1 slab already extends 2 units beyond the column line; use the full slab only in wings and entrance below.
aisle=g.join(runs(g,g.at(side,x=ax),n,s,hs),g.at(g.box(g.math('SUBTRACT',aw,2),21,.16),x=g.add(w,g.add(2,g.mul(g.math('SUBTRACT',aw,2),.5))),y=-14,z=-.08)); aisles=g.end(g.paint(g.pair(aisle),'Gallery | sandstone',(.70,.56,.38)))

g=Kit('FG2 | Crossing and transept',[height,rise,webres]); h=g.i['Spring height']; gridh=g.i['Crown rise']; arm=g.sub(web,**{'Half X':1.8,'Half Y':3.4,'Crown rise':gridh,'Web resolution':g.i['Web resolution']}); transverse=g.arch(0,3.4,gridh); arm=g.join(g.at(arm,z=g.add(h,.06)),g.at(transverse,x=1.8,z=h),g.at(g.arch(1.8,3.4,gridh),z=h),g.at(g.arch(-1.8,3.4,gridh),z=h),*(g.at(g.box(.36,.36,h),x=1.8,y=y,z=g.mul(h,.5)) for y in (-3.4,3.4))); wings=g.pair(g.join(g.at(arm,8.9,-13),g.at(g.box(3.6,6.8,.16),8.9,-13,-.08))); transept=g.end(g.paint(g.join(wings,g.at(g.box(14.2,3.5,.16),0,-1.75,-.08)),'Cross arms | stone',(.69,.61,.49)))

fan=num('Apse sectors',8,4,16,I); g=Kit('FG2 | Chevet fan and ambulatory',[fan,height,rise]); sectors=g.i['Apse sectors']; h=g.i['Spring height']; r=g.i['Crown rise']
# Parameterize three half-disks / annuli around the east end station. Keep a small crown oculus.
def polar(rad,angle): return g.mul(rad,g.math('COSINE',angle,0)),g.mul(rad,g.math('SINE',angle,0))
def fanpatch(lo,hi,z0,zh):
    grid,u,v=g.grid(g.add(g.mul(sectors,4),1),12); ang=g.mul(g.add(1,u),-math.pi/2); f=g.mul(g.add(1,v),.5); rad=g.add(lo,g.mul(hi-lo,f)); x,y=polar(rad,ang); z=g.add(z0,g.mul(zh,g.math('SQRT',g.math('SUBTRACT',1,f),0))); return g.deform(grid,x,y,z)
arc=fanpatch(.05,4,h,r); floor=fanpatch(.05,6.0,-.02,0); outer=fanpatch(4,6,g.mul(h,.82),.75)
# Rotate one radial rib and pier at each sector boundary, about the shared east-end center.
angle=g.mul(g.node('GeometryNodeInputIndex').outputs[0],g.math('DIVIDE',-math.pi,sectors)); pts=g.op('GeometryNodeMeshLine',[('Count',g.add(sectors,1)),('Offset',(0,0,0))]); c=g.op('GeometryNodeCurveQuadraticBezier',[('Start',g.xyz(4,0,h)),('Middle',g.xyz(4,0,g.add(h,g.mul(r,.5)))),('End',g.xyz(.05,0,g.add(h,r)))]); radial=g.join(g.tube(c,.105),g.at(g.box(.36,.36,h),4,0,g.mul(h,.5))); spokes=g.op('GeometryNodeInstanceOnPoints',[('Points',pts),('Instance',radial),('Rotation',g.xyz(0,0,angle))]); apse=g.end(g.paint(g.at(g.join(arc,floor,outer,spokes),y=-24),'Apse | pale stone',(.77,.66,.5)))

trusses=num('Trusses per wing',7,3,14,I); timber=num('Timber radius',.13,.07,.22); g=Kit('FG2 | Timber roof framing',[trusses,timber]); n=g.i[trusses[0]]; r=g.i[timber[0]]; beams=[((-6.8,0,0),(6.8,0,0)),((-6.8,0,0),(0,0,4.3)),((6.8,0,0),(0,0,4.3)),((0,0,0),(0,0,4.3)),((0,0,0),(-3.4,0,2.15)),((0,0,0),(3.4,0,2.15))]; frame=g.join(*(g.beam(a,b,r) for a,b in beams)); span=g.math('DIVIDE',6,g.math('SUBTRACT',n,1)); rows=[]
for start in (-24,-9):
    rows.append(g.line(frame,n,(0,start,8.4),(0,span,0))); rows.extend(g.beam((x,start,z),(x,start+6,z),r) for x,z in [(0,12.7),(-6.8,8.4),(6.8,8.4)])
roof=g.end(g.paint(g.join(*rows),'Roof | oak',(.32,.14,.055)))

proj=num('Buttress projection',2.4,1.4,3.2); g=Kit('FG2 | Flying buttresses',[proj]); span=g.i[proj[0]]; x=g.add(7.35,span); pier=g.at(g.box(.74,.8,4.5),x,0,2.25); cap=g.op('GeometryNodeMeshCone',[('Vertices',4),('Radius Bottom',.57),('Radius Top',0),('Depth',1.35)]); path=g.op('GeometryNodeCurveQuadraticBezier',[('Start',g.xyz(x,0,4.1)),('Middle',g.xyz(x,0,5.8)),('End',(7.35,0,7.25))]); unit=g.pair(g.join(pier,g.at(cap,x,0,4.5),g.tube(path,.26))); butt=g.end(g.paint(g.join(*(g.at(unit,y=y) for y in (-23,-20,-7,-4))),'Buttress | limestone',(.62,.55,.42)))

stairs=num('Tower steps',44,32,80,I); g=Kit('FG2 | Twin tower stairs and landings',[stairs]); n=g.i[stairs[0]]; ix=g.node('GeometryNodeInputIndex').outputs[0]; angle=g.mul(ix,g.math('DIVIDE',4*math.pi,n)); x,y=polar(.84,angle); zz=g.mul(ix,g.math('DIVIDE',8,n)); pts=g.op('GeometryNodeMeshLine',[('Count',n),('Offset',(0,0,0))]); pts=g.deform(pts,x,y,zz); treads=g.op('GeometryNodeInstanceOnPoints',[('Points',pts),('Instance',g.box(1.12,.48,.14)),('Rotation',g.xyz(0,0,angle))]); core=g.beam((0,0,0),(0,0,8.2),.30); land=g.at(g.box(1.3,1.3,.16),1,0,8); towers=g.end(g.paint(g.pair(g.at(g.join(core,treads,land),5.6,-1.7)), 'Stairs | stone',(.54,.49,.42)))

from wall_lining import build as build_lining
lining,lining_height=build_lining(Kit)
systems=[('Exterior',shell),('Nave',nave),('Vault webs',webs),('Aisles and galleries',aisles),('Transept',transept),('Chevet',apse),('Timber frames',roof),('Flying buttresses',butt),('Tower access',towers),('Wall lining',lining)]
controls=[bay,width,height,rise,col,radius,webres,fan,trusses,timber,proj,stairs,lining_height]; outer=['FrontRoofHeight','BellTowerRoofHeight','DomeHeightMultiplyer','SpawnCross']
for k in outer:
    q=shell.interface.items_tree[k]; d=q.default_value; controls.append((k,q.socket_type,d,None,None) if type(d)==bool else num(k,d,d*.6,d*1.5))
g=Kit('FG2 | Whole church',[('Geometry',G,None,None,None),*(toggle(k) for k,_ in systems),*controls,num('Length scale',1,.75,1.25),num('Width scale',1,.75,1.25)])
branches=[]
for k,tree in systems:
    args={s[0]:g.i[s[0]] for s in controls if tree.interface.items_tree.get(s[0])}; geo=g.sub(tree,**args); branches.append(g.op('GeometryNodeSwitch',[('Switch',g.i[k]),('True',geo)],input_type='GEOMETRY'))
geo=g.op('GeometryNodeTransform',[('Geometry',g.join(*branches)),('Scale',g.xyz(g.i['Width scale'],g.i['Length scale'],1))]); root=g.end(g.op('GeometryNodeRealizeInstances',[('Geometry',geo)])); obj=bpy.data.objects.new('Whole church | layer controls',bpy.data.meshes.new('Empty procedural host')); bpy.context.collection.objects.link(obj); obj.select_set(True); bpy.context.view_layer.objects.active=obj; obj.modifiers.new('Structure and dimensions','NODES').node_group=root
for area in bpy.context.screen.areas:
    if area.type=='PROPERTIES': area.spaces.active.context='MODIFIER'
    if area.type=='VIEW_3D':
        v=area.spaces.active.region_3d; v.view_distance=58; v.view_location=(0,-14,12); v.view_rotation=Vector((-1,-1,-.6)).to_track_quat('-Z','Y'); area.spaces.active.shading.color_type='MATERIAL'
bpy.context.preferences.filepaths.save_version=0; bpy.ops.wm.save_as_mainfile(filepath=str(out/'cathedral-structure.blend'),compress=True)

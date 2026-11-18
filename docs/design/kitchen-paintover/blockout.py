"""Blender 4.2: create grey geometry for the kitchen paint-over, not shipping art."""
import bpy, math, pathlib
from mathutils import Vector
b = bpy
out = pathlib.Path(__file__).resolve().parent
b.ops.wm.read_factory_settings(use_empty=True)
s = b.context.scene

def box(name, pos, dims, shade=.55):
    b.ops.mesh.primitive_cube_add(size=1, location=pos)
    o=b.context.object; o.name=name; o.dimensions=dims; o.color=(shade,shade,shade,1)
    return o

def frame(prefix,x0,x1,y,z0,z1):
    box(prefix+' L',(x0,y,(z0+z1)/2),(.10,.24,z1-z0))
    box(prefix+' R',(x1,y,(z0+z1)/2),(.10,.24,z1-z0))
    box(prefix+' head',((x0+x1)/2,y,z1),(x1-x0+.10,.24,.12))
box('Kitchen floor',(0,0,-.09),(8,7,.18),.40)
box('Passage floor',(0,4.5,-.09),(8,2,.18),.36)
box('Cold store floor',(1.8,7,-.09),(4.4,3,.18),.50)
box('West kitchen wall',(-4,0,1.55),(.2,7,3.1))
box('East kitchen wall',(4,0,1.55),(.2,7,3.1))
# Landing, open hatch, and walk-through passage door share the north wall.
for name,a,c in [('left',-4,-1.65),('jamb',.65,1.45),('right',2.9,4)]:
    box('North '+name,((a+c)/2,3.5,1.55),(c-a,.20,3.1))
box('Hatch sill',(-.5,3.5,.51),(2.3,.28,1.02));box('Hatch soffit',(-.5,3.5,2.72),(2.3,.22,.76));frame('Hatch',-1.65,.65,3.5,1.02,2.34)
box('Sliding shutter',(-.5,3.47,2.15),(2.18,.14,.34),.27);frame('Service passage',1.45,2.90,3.5,0,2.55)
box('Passage back west',(-1.45,5.5,1.55),(5.1,.2,3.1));box('Passage back east',(3.6,5.5,1.55),(.8,.2,3.1));frame('Cold store',1.1,3.2,5.5,0,2.65)
leaf=box('Hinged cold store door',(1.53,5.89,1.28),(1.40,.15,2.56),.34);leaf.rotation_euler.z=.72
box('Cold store back',(1.8,8.5,1.55),(4.4,.2,3.1));box('Cold store shelf',(2.5,7.8,1),(1.8,.6,.14))
box('Range',(-3.10,1.5,.49),(1.6,2.0,.98),.28);box('Hood',(-3.08,1.5,2.15),(1.78,2.18,.28),.40);box('Flue',(-3.08,1.5,2.7),(.65,.68,.9))
box('Prep table top',(-.72,.25,.93),(2.65,1.04,.15),.50)
for x in [-1.87,.43]:
    for y in [-.14,.64]:box('Table leg',(x,y,.44),(.12,.12,.88),.35)
box('Notebook',(-.38,.25,1.035),(.36,.27,.05),.80);box('Notice',(-2.53,3.36,1.74),(.53,.04,.66),.78)
b.ops.object.camera_add(location=(.15,-3.15,1.75));cam=b.context.object;cam.name='Entry sightline';cam.rotation_euler=(Vector((0.1,3.5,1.38))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=18;s.camera=cam
s.render.engine='BLENDER_WORKBENCH';s.display.shading.color_type='OBJECT';s.display.shading.show_shadows=True;s.display.shading.show_cavity=True;s.display.shading.cavity_type='BOTH';s.render.resolution_x=1280;s.render.resolution_y=720;s.render.resolution_percentage=100;s.render.filepath=str(out/'kitchen-blockout.png');b.ops.render.render(write_still=True)

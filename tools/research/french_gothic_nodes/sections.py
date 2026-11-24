"""Blender -b -P sections.py -- /absolute/path/to/main (contains the test GLB)."""
import sys
from pathlib import Path
import bpy
import bmesh
from mathutils import Matrix, Vector

folder = Path(sys.argv[-1]).resolve()
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(folder / 'Generate_Cathedral_Combined.glb'))
scene = bpy.context.scene
objects = [o for o in scene.objects if o.type == 'MESH']
for obj in objects:
    obj.data = obj.data.copy()
    obj.data.transform(obj.matrix_world)
    obj.parent = None


    obj.matrix_world = Matrix.Identity(4)

bpy.ops.object.camera_add()
cam = bpy.context.object
scene.camera = cam
scene.render.engine = 'BLENDER_WORKBENCH'
shade = scene.display.shading
shade.light = 'STUDIO'; shade.color_type = 'SINGLE'; shade.single_color = (.79,.76,.68)
shade.show_shadows = False; shade.show_cavity = True; shade.cavity_type = 'BOTH'
shade.show_specular_highlight = False
shade.background_type = 'VIEWPORT'; shade.background_color = (.055,.075,.095)
scene.render.resolution_x = 1100; scene.render.resolution_y = 760
scene.render.resolution_percentage = 100

def render(name, eye, target, scale=None):
    cam.location = Vector(eye)
    cam.rotation_euler = (Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler()
    cam.data.type = 'ORTHO' if scale else 'PERSP'
    if scale: cam.data.ortho_scale = scale
    else: cam.data.lens = 19
    cam.data.clip_start = .03; cam.data.clip_end = 250
    scene.render.filepath = str(folder / (name+'.png'))
    bpy.ops.render.render(write_still=True)

def cut(axis, offset):
    n = Vector(axis)
    for obj in objects:
        bm = bmesh.new(); bm.from_mesh(obj.data)
        bmesh.ops.bisect_plane(bm, geom=[*bm.verts,*bm.edges,*bm.faces], plane_co=n*offset,
                               plane_no=n, clear_outer=True, dist=.00001)
        bm.to_mesh(obj.data); bm.free(); obj.data.update()

render('inside-axis', (0,-5.3,1.65), (0,-16,2.6))
originals = [o.data for o in objects]
for obj in objects: obj.data = obj.data.copy()
cut((1,0,0), .12)
render('inside-longitudinal', (52,-8,22), (0,-14,16), 54)
for obj, data in zip(objects, originals): obj.data = data
cut((0,0,1), 4)
render('inside-plan', (.01,-14,55), (0,-14,0), 55)

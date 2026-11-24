"""Run on the saved cathedral-controls.blend; write checks and an interior preview alongside."""
import json
from pathlib import Path
import bpy
from mathutils import Vector

out=Path(bpy.data.filepath).parent
obj=bpy.data.objects['Cathedral | select to edit']; mod=obj.modifiers[0]
sockets=mod.node_group.interface.items_tree

def set_knobs(**kw):
    for k,v in kw.items(): mod[sockets[k].identifier]=v
    obj.update_tag(); bpy.context.view_layer.update()

def measure():
    ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get()); mesh=ev.to_mesh()
    result=dict(faces=len(mesh.polygons),size=list(ev.dimensions)); ev.to_mesh_clear(); return result

checks={'combined':measure()}
set_knobs(Interior=False); checks['shell']=measure()
key='DomeHeightMultiplyer'; d=sockets[key].default_value
set_knobs(**{key:d*1.4}); checks['taller tower']=measure()
assert checks['taller tower']['size'][2]>checks['shell']['size'][2]
set_knobs(Exterior=False); assert measure()['faces']==0
set_knobs(Interior=True); checks['inside']=measure()
assert checks['inside']['faces']+checks['shell']['faces']==checks['combined']['faces']
set_knobs(Bays=8); checks['eight bays']=measure()
assert checks['eight bays']['faces']>checks['inside']['faces']
set_knobs(Bays=5,**{'Spring height':5.0}); checks['higher columns']=measure()
assert checks['higher columns']['size'][2]>checks['inside']['size'][2]
set_knobs(**{'Spring height':4.2}); (out/'assembly-checks.json').write_text(json.dumps(checks,indent=2))
scene=bpy.context.scene; bpy.ops.object.camera_add(); cam=bpy.context.object; scene.camera=cam
cam.location=(17,2,13); cam.rotation_euler=(Vector((0,-14,2.7))-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.type='ORTHO'; cam.data.ortho_scale=25
scene.render.engine='BLENDER_WORKBENCH'; shade=scene.display.shading; shade.color_type='SINGLE'; shade.single_color=(.80,.75,.61); shade.show_cavity=True; shade.cavity_type='BOTH'; shade.show_shadows=True
scene.render.resolution_x=960; scene.render.resolution_y=720; scene.render.resolution_percentage=100; scene.render.filepath=str(out/'assembly-interior.png'); bpy.ops.render.render(write_still=True)

# Half-shell inspection: cut the evaluated exterior copy only; keep the live nave intact.
import bmesh
set_knobs(Interior=False, Exterior=True, **{key:d})
ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get()); shell=bpy.data.meshes.new_from_object(ev)
bm=bmesh.new(); bm.from_mesh(shell)
bmesh.ops.bisect_plane(bm,geom=[*bm.verts,*bm.edges,*bm.faces],plane_co=(0,0,0),plane_no=(1,0,0),clear_outer=True,dist=.00001)
bm.to_mesh(shell); bm.free(); shell.update()
cut=bpy.data.objects.new('Section preview only',shell); scene.collection.objects.link(cut); cut.color=(.55,.62,.67,1)
set_knobs(Interior=True, Exterior=False); obj.color=(.95,.48,.13,1); shade.color_type='OBJECT'; shade.show_shadows=False
cam.location=(48,-3,22); cam.rotation_euler=(Vector((0,-14,15))-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.ortho_scale=54
scene.render.filepath=str(out/'assembly-section.png'); bpy.ops.render.render(write_still=True)

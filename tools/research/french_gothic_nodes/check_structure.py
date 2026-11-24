"""Check the saved GN modifier, then render the default model and two layer inspections."""
from pathlib import Path
import json, math, hashlib, array
import bpy
from mathutils import Vector

out=Path(bpy.data.filepath).parent; obj=bpy.context.view_layer.objects.active; mod=obj.modifiers[0]; ui=mod.node_group.interface.items_tree
layers=['Exterior','Nave','Vault webs','Aisles and galleries','Transept','Chevet','Timber frames','Flying buttresses','Tower access','Wall lining']
def change(**kw):
    for k,v in kw.items(): mod[ui[k].identifier]=v
    obj.update_tag(); bpy.context.view_layer.update()
def show(keys): change(**{k:k in keys for k in layers})
def stats():
    ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get()); mesh=ev.to_mesh(); assert all(math.isfinite(v) for corner in ev.bound_box for v in corner); val={'faces':len(mesh.polygons),'size':[round(x,4) for x in ev.dimensions]}; ev.to_mesh_clear(); return val
record={'all':stats(),'layers':{},'edits':{}}
for k in layers:
    show([k]); record['layers'][k]=stats(); assert record['layers'][k]['faces']>0,k
# Compare the exterior to an independent evaluation of the extracted upstream library.
# Ordered buffers test all vertex coordinates and indexed face loops, not only bounds.
def mesh_signature(target):
    ev=target.evaluated_get(bpy.context.evaluated_depsgraph_get()); mesh=ev.to_mesh()
    result={}
    for label,collection,field,code,stride in [('positions',mesh.vertices,'co','f',3),('corners',mesh.loops,'vertex_index','i',1),('face_starts',mesh.polygons,'loop_start','i',1)]:
        a=array.array(code,[0])*(len(collection)*stride); collection.foreach_get(field,a); result[label]=hashlib.sha256(a.tobytes()).hexdigest()
    ev.to_mesh_clear(); return result
show(['Exterior']); exterior=mesh_signature(obj)
with bpy.data.libraries.load(str(out/'nodes.blend')) as (_,lib): lib.node_groups=['Generate Cathedral Combined']
ref=bpy.data.objects.new('Upstream reference',bpy.data.meshes.new('Reference host')); bpy.context.scene.collection.objects.link(ref)
tree=bpy.data.node_groups.new('Reference evaluation','GeometryNodeTree'); tree.interface.new_socket(name='Geometry',in_out='OUTPUT',socket_type='NodeSocketGeometry'); source=tree.nodes.new('GeometryNodeGroup'); source.node_tree=lib.node_groups[0]; realize=tree.nodes.new('GeometryNodeRealizeInstances'); output=tree.nodes.new('NodeGroupOutput'); tree.links.new(source.outputs[0],realize.inputs[0]); tree.links.new(realize.outputs[0],output.inputs[0]); ref.modifiers.new('Reference','NODES').node_group=tree; bpy.context.view_layer.update(); reference=mesh_signature(ref); bpy.data.objects.remove(ref,do_unlink=True)
record['default exterior comparison']={'reference':reference,'layer':exterior,'identical':reference==exterior}; assert exterior==reference,(exterior,reference)
assert sum(s['faces'] for s in record['layers'].values())==record['all']['faces']; show([]); assert stats()['faces']==0
for group,key,val,axis in [('Wall lining','Lining height scale',1.15,2),('Nave','Bays',8,None),('Vault webs','Web resolution',25,None),('Aisles and galleries','Bays',8,None),('Transept','Spring height',5,2),('Chevet','Apse sectors',12,None),('Timber frames','Trusses per wing',12,None),('Flying buttresses','Buttress projection',3,0),('Tower access','Tower steps',60,None),('Exterior','DomeHeightMultiplyer',1.4*ui['DomeHeightMultiplyer'].default_value,2)]:
    show([group]); change(**{key:val}); after=stats(); before=record['layers'][group]; assert (after['faces']>before['faces'] if axis is None else after['size'][axis]>before['size'][axis]),(group,key,before,after); record['edits'][key+' / '+group]=after; change(**{key:ui[key].default_value})
show(layers); change(**{'Length scale':1.1}); assert abs(stats()['size'][1]/record['all']['size'][1]-1.1)<.001; change(**{'Length scale':1.}); (out/'structure-checks.json').write_text(json.dumps(record,indent=2))
scene=bpy.context.scene; bpy.ops.object.camera_add(); cam=bpy.context.object; scene.camera=cam; scene.render.engine='BLENDER_WORKBENCH'; shade=scene.display.shading; shade.color_type='MATERIAL'; shade.show_cavity=True; shade.cavity_type='BOTH'; shade.show_shadows=False; shade.background_type='VIEWPORT'; shade.background_color=(.055,.068,.08); scene.render.film_transparent=False
scene.render.resolution_x=1100; scene.render.resolution_y=820; scene.render.resolution_percentage=100

def render(name,eye,target,scale):
    cam.location=eye; cam.rotation_euler=(Vector(target)-cam.location).to_track_quat('-Z','Y').to_euler(); cam.data.type='ORTHO'; cam.data.ortho_scale=scale; scene.render.filepath=str(out/(name+'.png')); bpy.ops.render.render(write_still=True)
render('structure-exterior',(43,18,30),(0,-14,14),53); show(layers[1:]); render('structure-unwrapped',(32,4,23),(0,-14,5),43)
show(['Nave','Vault webs','Aisles and galleries','Transept','Chevet','Tower access']); cam.data.type='PERSP'; cam.data.lens=20; cam.location=(0,-4.8,1.7); cam.rotation_euler=(Vector((0,-20,3.8))-cam.location).to_track_quat('-Z','Y').to_euler(); scene.render.filepath=str(out/'structure-nave.png'); bpy.ops.render.render(write_still=True)

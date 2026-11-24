"""Bake each enabled branch independently; verify the full default face budget."""
import bpy
from pathlib import Path

out = Path(bpy.data.filepath).parent
host = bpy.context.view_layer.objects.active
mod = host.modifiers[0]
layers = ['Exterior','Nave','Vault webs','Aisles and galleries','Transept','Chevet','Timber frames','Flying buttresses','Tower access','Wall lining']
keys = {name: mod.node_group.interface.items_tree[name].identifier for name in layers}
def bake():
    bpy.context.view_layer.update()
    return bpy.data.meshes.new_from_object(host.evaluated_get(bpy.context.evaluated_depsgraph_get()))
full = bake(); expected = len(full.polygons); bpy.data.meshes.remove(full)
parts = []
for name in layers:
    for label,key in keys.items(): mod[key] = label == name
    host.update_tag(); mesh = bake(); assert len(mesh.polygons), name
    if name != 'Wall lining': mesh.materials.clear()
    obj = bpy.data.objects.new(name.replace(' ','_'), mesh)
    bpy.context.collection.objects.link(obj); obj.matrix_world = host.matrix_world.copy(); parts.append(obj)
assert sum(len(obj.data.polygons) for obj in parts) == expected
bpy.ops.object.select_all(action='DESELECT')
for obj in parts: obj.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(out/'whole-church.glb'),use_selection=True,export_materials='EXPORT')

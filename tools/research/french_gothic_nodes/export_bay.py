"""Export the evaluated active bay, keeping the editable blend unchanged."""
import bpy
from pathlib import Path
obj=bpy.context.view_layer.objects.active
ev=obj.evaluated_get(bpy.context.evaluated_depsgraph_get())
mesh=bpy.data.meshes.new_from_object(ev)
assert len(mesh.polygons)>0
sample=bpy.data.objects.new('Original two-bay arcade',mesh)
bpy.context.collection.objects.link(sample)
bpy.ops.object.select_all(action='DESELECT'); sample.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(Path(bpy.data.filepath).with_suffix('.glb')),use_selection=True,export_materials='NONE',export_yup=True)

@tool
extends EditorScenePostImport
## glTF vertex colors are linear pigments. Apply the same finish in the gallery and ArchBuilder.
func _post_import(scene: Node) -> Object:
	for node in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = node.mesh
		for i in mesh.get_surface_count():
			var mat := mesh.surface_get_material(i) as StandardMaterial3D
			if mat:
				mat.vertex_color_use_as_albedo = true
				if mat.resource_name == "paint":
					mat.diffuse_mode = BaseMaterial3D.DIFFUSE_TOON
					mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return scene

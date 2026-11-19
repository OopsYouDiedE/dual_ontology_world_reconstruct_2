extends RefCounted
## Assembly-space mesh receipt for the Blender geometry-node authoring handoff.

static func save_meshes(groups: Dictionary, path: String) -> void:
	var output := {}
	for label in groups:
		var pieces := []
		for node in groups[label]:
			_collect(node, pieces)
		output[label] = pieces
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(output))

static func _collect(node: Node, output: Array) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(i)
			var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var vertices := []
			for point in positions:
				var p: Vector3 = node.to_global(point)
				vertices.append([p.x, p.y, p.z])
			var faces := []
			var count := indices.size() if not indices.is_empty() else vertices.size()
			for v in range(0, count - 2, 3):
				faces.append([v,v+1,v+2] if indices.is_empty() else [indices[v],indices[v+1],indices[v+2]])
			var material: Material = node.get_active_material(i)
			var tone := Color("405570")
			if material is StandardMaterial3D:
				tone = material.albedo_color
			elif material is ShaderMaterial:
				for field: String in ["base_color", "cloth_color", "pigment"]:
					var value: Variant = material.get_shader_parameter(field)
					if value is Color:
						tone = value
						break
			output.append({"name":str(node.name), "vertices":vertices, "faces":faces, "color":tone.to_html(false)})
	for child in node.get_children():
		_collect(child, output)

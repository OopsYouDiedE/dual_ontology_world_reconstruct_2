extends RefCounted
## Bake visual siblings into one surface per material, preserving their parent's moving pivot.
## Collision bodies and dynamic meshes deeper in the tree remain distinct.

static func collapse(parent: Node) -> void:
	var groups := {}
	for child in parent.get_children():
		if not child is MeshInstance3D:
			collapse(child)
			continue
		if child.mesh == null or child.get_child_count() > 0 or child.mesh.get_surface_count() != 1:
			continue
		var mesh: Mesh = child.mesh
		var material: Material = child.get_active_material(0)
		var arrays := mesh.surface_get_arrays(0)
		var indexed: bool = arrays[Mesh.ARRAY_INDEX] != null and not arrays[Mesh.ARRAY_INDEX].is_empty()
		var channels := 0
		for i in range(Mesh.ARRAY_MAX):
			if arrays[i] != null: channels |= 1 << i
		var key := [material, channels,
			child.cast_shadow, child.gi_mode, indexed]
		if not groups.has(key): groups[key] = []
		groups[key].append(child)
	for key in groups:
		var originals: Array = groups[key]
		if originals.size() < 2: continue
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		for part: MeshInstance3D in originals:
			surface.append_from(part.mesh, 0, part.transform)
		var combined := MeshInstance3D.new()
		combined.name = "JoinedFinish"
		combined.mesh = surface.commit()
		combined.material_override = key[0]
		combined.cast_shadow = key[2]
		combined.gi_mode = key[3]
		parent.add_child(combined)
		for part: MeshInstance3D in originals:
			parent.remove_child(part)
			part.queue_free()

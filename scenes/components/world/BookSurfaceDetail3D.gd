extends RefCounted
## Static rounded box, centered at the origin with the original outer size.
## Keeps Godot BoxMesh face UVs by reading its four source corners per face.
## Build once, then attach the MeshInstance3D beneath the existing book root.

static func beveled_box(dimensions: Vector3, radius: float = 0.012, bevel_segments: int = 3) -> ArrayMesh:
	assert(dimensions.x > 0.0 and dimensions.y > 0.0 and dimensions.z > 0.0)
	var half_size: Vector3 = dimensions * 0.5
	var limit: float = minf(half_size.x, minf(half_size.y, half_size.z))
	var bevel: float = clampf(radius, limit * 0.001, limit * 0.95)
	var segments: int = clampi(bevel_segments, 1, 6)
	var inner: Vector3 = half_size - Vector3.ONE * bevel
	var source := BoxMesh.new()
	source.size = dimensions
	var original: Array = source.get_mesh_arrays()
	var source_vertices: PackedVector3Array = original[Mesh.ARRAY_VERTEX]
	var source_normals: PackedVector3Array = original[Mesh.ARRAY_NORMAL]
	var source_uvs: PackedVector2Array = original[Mesh.ARRAY_TEX_UV]
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var face_normals: Array[Vector3] = [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	var face_u: Array[Vector3] = [Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.RIGHT, Vector3.LEFT, Vector3.RIGHT]
	var face_v: Array[Vector3] = [Vector3.UP, Vector3.UP, Vector3.BACK, Vector3.FORWARD, Vector3.UP, Vector3.UP]
	for face in range(6):
		var n: Vector3 = face_normals[face]
		var u: Vector3 = face_u[face]
		var v: Vector3 = face_v[face]
		var half_u: float = half_size.dot(u.abs())
		var half_v: float = half_size.dot(v.abs())
		var half_n: float = half_size.dot(n.abs())
		var corners: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
		for index in range(source_vertices.size()):
			if source_normals[index].dot(n) < 0.99:
				continue
			var corner: int = (1 if source_vertices[index].dot(u) > 0.0 else 0) + (2 if source_vertices[index].dot(v) > 0.0 else 0)
			corners[corner] = source_uvs[index]
		var us: PackedFloat32Array = _edge_knots(half_u, bevel, segments)
		var vs: PackedFloat32Array = _edge_knots(half_v, bevel, segments)
		var offset: int = vertices.size()
		var columns: int = us.size()
		for row in range(vs.size()):
			for column in range(columns):
				var cube: Vector3 = n * half_n + u * us[column] + v * vs[row]
				var core: Vector3 = cube.clamp(-inner, inner)
				var normal: Vector3 = (cube - core).normalized()
				vertices.append(core + normal * bevel)
				normals.append(normal)
				var s: float = (us[column] + half_u) / (half_u * 2.0)
				var t: float = (vs[row] + half_v) / (half_v * 2.0)
				uvs.append(corners[0].lerp(corners[1], s).lerp(corners[2].lerp(corners[3], s), t))
		for row in range(vs.size() - 1):
			for column in range(columns - 1):
				var a: int = offset + row * columns + column
				var b: int = a + 1
				var c: int = a + columns
				# u cross v points inward: these triangles are Godot-clockwise.
				indices.append_array(PackedInt32Array([a, b, c, b, c + 1, c]))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var result := ArrayMesh.new()
	result.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return result

static func _edge_knots(half_extent: float, radius: float, segments: int) -> PackedFloat32Array:
	var result := PackedFloat32Array()
	for index in range(segments + 1):
		result.append(-half_extent + radius * float(index) / float(segments))
	for index in range(segments, -1, -1):
		result.append(half_extent - radius * float(index) / float(segments))
	return result

extends RefCounted
## Expedition Hale only. Edits render meshes in R-05 bind space; retains skin,
## weights, bone indices and the ProductionCast animation libraries.
const FIELD_WOOL := preload("res://scenes/rogue_crossing/HaleFieldWool.gdshader")
const SIDE_PART := preload("res://scenes/rogue_crossing/HaleSidePart.gdshader")
static var _tailored := {}

static func fit(body: Node3D) -> void:
	# Collapse the stock quiff into a close, off-centre comb-over.
	body.find_child("Hair_SolidLocks", true, false).hide()
	for label in [&"Hair_Cap", &"Wardrobe_Outfit"]:
		var node := body.find_child(label, true, false) as MeshInstance3D
		if not _tailored.has(label):
			_tailored[label] = _cut(node.mesh, label)
		node.mesh = _tailored[label]

static func _cut(source: Mesh, label: StringName) -> ArrayMesh:
	var arrays := source.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var dress := label == &"Wardrobe_Outfit"
	var coat := _coat_component(vertices, arrays[Mesh.ARRAY_INDEX]) if dress else {}
	var bind_uv := PackedVector2Array()
	var bind_depth := PackedColorArray()
	for i in vertices.size():
		var v := vertices[i]
		if dress:
			bind_uv.append(Vector2(v.x, v.y))
			bind_depth.append(Color(clampf((v.z + 0.3) / 0.65, 0., 1.), 1.0 if coat.has(v.snapped(Vector3.ONE * .00001)) else 0.0, 0.))
			var on_coat := coat.has(v.snapped(Vector3.ONE * .00001))
			var torso := 1.0 - smoothstep(.165, .23, absf(v.x))
			if not on_coat: torso = 0.0
			var waist := exp(-pow((v.y - 1.055) / .042, 2.0)) * torso
			var skirt := smoothstep(.76, .86, v.y) * (1.0 - smoothstep(.88, 1.10, v.y)) * torso
			v.x *= 1.0 - .047 * waist + .065 * skirt
			v.z = .036 + (v.z - .036) * (1.0 - .07 * waist + .085 * skirt)
			var panel := 0.0
			for center in [Vector2(.112, .927), Vector2(.101, 1.218)]:
				var delta: Vector2 = (Vector2(absf(v.x), v.y) - center).abs()
				panel += (1.0 - smoothstep(.031, .055, delta.x)) * (1.0 - smoothstep(.046, .065, delta.y))
			v.z += .007 * panel * torso * smoothstep(.070, .111, v.z)
		else:
			var top := smoothstep(1.690, 1.778, v.y)
			var part := v.x + .031 - .23 * (v.z - .110)
			var front := smoothstep(.030, .135, v.z)
			var sweep := smoothstep(-.018, .023, part)
			v.y += .004 + top * front * (.007 * sweep - .004 * exp(-pow(part / .008, 2.0)))
			v.x *= 1.025

			bind_uv.append(Vector2(v.x, v.z))
			var nape := (1.0 - smoothstep(-.058, .023, v.z)) * (1.0 - smoothstep(1.65, 1.736, v.y))
			v.y += .028 * nape
			v.z += .004 * nape
		vertices[i] = v
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV2] = bind_uv
	if dress:
		arrays[Mesh.ARRAY_COLOR] = bind_depth
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, source.surface_get_format(0) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
	if dress:
		var wool := ShaderMaterial.new()
		wool.shader = FIELD_WOOL
		wool.set_shader_parameter("toon_on", true)
		wool.set_shader_parameter("toon_strength", .86)
		mesh.surface_set_material(0, wool)
	else:
		var hair := ShaderMaterial.new()
		hair.shader = SIDE_PART
		hair.set_shader_parameter("toon_on", true)
		hair.set_shader_parameter("toon_strength", .86)
		mesh.surface_set_material(0, hair)
	return mesh

# The imported coat and trousers share a material but are separate welded islands.
static func _coat_component(vertices: PackedVector3Array, indices: PackedInt32Array) -> Dictionary:
	var weld := PackedVector3Array()
	for v in vertices:
		weld.append(v.snapped(Vector3.ONE * .00001))
	var adjacency := {}
	for i in range(0, indices.size(), 3):
		for j in 3:
			var a := weld[indices[i + j]]
			var b := weld[indices[i + (j + 1) % 3]]
			if not adjacency.has(a): adjacency[a] = []
			if not adjacency.has(b): adjacency[b] = []
			adjacency[a].append(b)
			adjacency[b].append(a)
	var coat := {}
	var pending: Array = []
	for v: Vector3 in adjacency:
		if v.y > 1.10:
			coat[v] = true
			pending.append(v)
	while not pending.is_empty():
		var v: Vector3 = pending.pop_back()
		for next: Vector3 in adjacency[v]:
			if not coat.has(next):
				coat[next] = true
				pending.append(next)
	return coat

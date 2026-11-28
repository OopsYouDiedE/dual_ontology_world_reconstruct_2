extends RefCounted
## Lightweight catalog silhouettes for known GUIDs when the art pack is unavailable.
## The lot always supplies the anchor, direction and existence of the object.

const ACADEMY_SIDE_CHAIR := preload("res://assets/props/academy/academy_side_chair.glb")
const HALL_FINISH := preload("res://scenes/components/rendering/surfaces/HallFinish.gdshader")

static func populate(anchor: Node3D, guid: int) -> bool:
	var wood := Color("594231")
	var upholstery := Color("765b57")
	match guid:
		0x5dea43f0:
			var chair := ACADEMY_SIDE_CHAIR.instantiate() as Node3D
			_apply_hall_finish(chair)
			anchor.add_child(chair)
		0x68ea432a, 0x53ea43a5, 0x3cea43f8:
			var armchair := guid == 0x68ea432a
			var width := 0.76 if armchair else 0.50
			var depth := 0.69 if armchair else 0.48
			for x in [-width * 0.38, width * 0.38]:
				for z in [-depth * 0.36, depth * 0.36]:
					_box(anchor, Vector3(x, 0.19, z), Vector3(0.075, 0.38, 0.075), wood)
			_box(anchor, Vector3(0, 0.43, 0), Vector3(width, 0.15, depth), upholstery)
			_box(anchor, Vector3(0, 0.72, depth * 0.43), Vector3(width, 0.44, 0.12), upholstery)
			if armchair:
				for x in [-0.33, 0.33]: _box(anchor, Vector3(x, 0.60, 0), Vector3(0.13, 0.23, depth), upholstery.darkened(0.12))
		0x06ea4309, 0x89ea4394, 0x12ea4376:
			var side := 0.72 if guid == 0x12ea4376 else 0.98
			var height := 0.54 if guid == 0x12ea4376 else 0.74
			_box(anchor, Vector3(0, height, 0), Vector3(side, 0.09, side), wood.lightened(0.24))
			for x in [-side * 0.39, side * 0.39]:
				for z in [-side * 0.39, side * 0.39]:
					_box(anchor, Vector3(x, height * 0.5, z), Vector3(0.09, height, 0.09), wood)
		0x04ef513c:
			_cylinder(anchor, Vector3(0, 0.36, 0), 0.38, 0.33, 0.58, Color("363a40"))
			_cylinder(anchor, Vector3(0, 0.65, 0), 0.39, 0.39, 0.055, Color("151b20"))
			_cylinder(anchor, Vector3(0, 0.685, 0), 0.30, 0.30, 0.022, Color("7a884d"))
			for x in [-0.42, 0.42]: _box(anchor, Vector3(x, 0.56, 0), Vector3(0.16, 0.08, 0.13), Color("22292e"))
		0x19ea4376:
			_box(anchor, Vector3(0, 0.28, 0.30), Vector3(0.88, 0.26, 1.78), wood)
			_box(anchor, Vector3(0, 0.51, 0.28), Vector3(0.82, 0.24, 1.70), Color("ccc6ae"))
			_box(anchor, Vector3(0, 0.66, -0.31), Vector3(0.63, 0.11, 0.39), Color("e5debf"))
			_box(anchor, Vector3(0, 0.65, 0.55), Vector3(0.84, 0.09, 1.02), Color("607a74"))
			_box(anchor, Vector3(0, 0.60, -0.58), Vector3(0.91, 0.74, 0.09), wood)
		0xddea43f0, 0x02b9b1ac, 0xacea43aa:
			var tall := guid == 0xacea43aa
			var height := 1.52 if tall else 0.79
			_box(anchor, Vector3(0, height / 2, 0), Vector3(0.85, height, 0.60), wood)
			_box(anchor, Vector3(0, height, 0), Vector3(0.92, 0.08, 0.67), Color("938978"))
			for i in (4 if tall else 2):
				var y := height - 0.21 - i * 0.30
				_box(anchor, Vector3(0, y, -0.31), Vector3(0.74, 0.22, 0.04), wood.lightened(0.13))
				_box(anchor, Vector3(0, y, -0.35), Vector3(0.21, 0.038, 0.035), Color("b89762"))
		0xb9ea4328:
			_cylinder(anchor, Vector3(0, 0.21, 0), 0.23, 0.17, 0.42, Color("986448"))
			var crown := SphereMesh.new()
			crown.radius = 0.32
			crown.height = 0.66
			_piece(anchor, crown, Vector3(0.03, 0.64, 0), Color("4b6849"))
		0xb7ea4340:
			_cylinder(anchor, Vector3(0, 0.035, 0), 0.23, 0.23, 0.07, wood)
			_cylinder(anchor, Vector3(0, 0.62, 0), 0.027, 0.027, 1.19, Color("67563d"))
			_cylinder(anchor, Vector3(0, 1.28, 0), 0.18, 0.30, 0.34, Color("d4b77e"))
		_:
			return false
	return true

static func _box(anchor: Node3D, pos: Vector3, dimensions: Vector3, color: Color) -> void:
	var box := BoxMesh.new()
	box.size = dimensions
	_piece(anchor, box, pos, color)

static func _cylinder(anchor: Node3D, pos: Vector3, top: float, bottom: float, height: float, color: Color) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 12
	_piece(anchor, mesh, pos, color)

static func _piece(anchor: Node3D, mesh: PrimitiveMesh, pos: Vector3, color: Color) -> void:
	var material := ShaderMaterial.new()
	material.shader = HALL_FINISH
	material.set_shader_parameter("pigment", color)
	material.set_shader_parameter("surface_roughness", 0.85)
	material.set_shader_parameter("grain", 0.055)
	material.set_shader_parameter("toon_on", true)
	material.set_shader_parameter("toon_strength", 0.86)
	mesh.material = material
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = pos
	anchor.add_child(part)

static func _apply_hall_finish(node: Node3D) -> void:
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		for i in mesh.mesh.get_surface_count():
			var src := mesh.get_active_material(i) as StandardMaterial3D
			if src == null: continue
			var mat := ShaderMaterial.new()
			mat.shader = HALL_FINISH
			mat.set_shader_parameter("pigment", src.albedo_color)
			mat.set_shader_parameter("surface_roughness", src.roughness)
			mat.set_shader_parameter("grain", 0.055)
			mat.set_shader_parameter("wood", 1.0 if "wood" in src.resource_name.to_lower() else 0.0)
			mat.set_shader_parameter("toon_on", true)
			mat.set_shader_parameter("toon_strength", 0.86)
			mesh.set_surface_override_material(i, mat)

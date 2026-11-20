extends Node3D
## Camera-ready room studies. Only the active room enters the lab's world and GI volume.
const Meridian := preload("res://scenes/blue_prince_lab/studies/Meridian.gd")
const Finish := preload("res://scenes/blue_prince_lab/HallFinish.gdshader")
const Batch := preload("res://scenes/blue_prince_lab/MeshBatches.gd")
enum Shot { SERVICE, ANOMALY, ARCHIVE, LEDGER, MERIDIAN }
const VIEWS := ["Service Stairs", "Stair Anomaly", "Archive", "Ledger", "Meridian"]
const CAMERA := [Vector3(-0.54, 1.65, 2.37), Vector3(-0.54, 1.65, 2.37),
	Vector3(0.64, 1.68, 3.92), Vector3(-0.04, 2.20, -0.46), Vector3(2.03, 2.76, 5.1)]
const FOCUS := [Vector3(-0.03, 0.56, -3.12), Vector3(-0.03, 0.56, -3.12),
	Vector3(-0.23, 1.39, -2.4), Vector3(0.08, 1.03, -1.44), Vector3(0.03, 1.94, -0.95)]
const FOV := [53.0, 53.0, 54.0, 38.0, 39.0]
const ORIGIN := Vector3(80, 0, 0)
const LAYER := 2

var rooms: Array[Node3D] = []
var room: Node3D
var flight: Node3D
var up_flight: Node3D
var meridian: Meridian
var bindings := {}

func _ready() -> void:
	position = ORIGIN
	_make_palette()
	room = _new_room("ServiceStairs")
	_build_service()
	room = _new_room("Archive")
	_build_archive()
	room = _new_room("MeridianChamber")
	_build_exhibit()
	for study in rooms:
		Batch.collapse(study)
		_layer(study)
	clear()

func clear() -> void:
	for study in rooms:
		if study.get_parent() == self:
			remove_child(study)

func show_study(index: int) -> void:
	var study := rooms[0 if index <= Shot.ANOMALY else (1 if index <= Shot.LEDGER else 2)]
	for other in rooms:
		if other != study and other.get_parent() == self:
			remove_child(other)
	if study.get_parent() == null:
		add_child(study)
	flight.visible = index != Shot.ANOMALY
	up_flight.visible = index == Shot.ANOMALY

func _notification(what: int) -> void:
	# Detached rooms remain cached for A/B switches, then follow the lab's lifetime.
	if what == NOTIFICATION_PREDELETE:
		for study in rooms:
			if study.get_parent() == null:
				study.free()

func _new_room(title: String) -> Node3D:
	var root := Node3D.new()
	root.name = title
	rooms.append(root)
	add_child(root)
	return root

func _layer(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers = LAYER
	for child in node.get_children():
		_layer(child)

func finish_materials() -> Array[ShaderMaterial]:
	var materials: Array[ShaderMaterial] = []
	for mat: Material in bindings.values() + meridian.finishes.values():
		if mat is ShaderMaterial:
			materials.append(mat)
	return materials

func _make_palette() -> void:
	# Pigments are shared with the hall's finish/Toon shader and its independent Ink/Glow layers.
	bindings = {"plaster": _mat("657985", 0.09), "bone": _mat("b8b2a0", 0.22),
		"slate": _mat("344e5c", 0.12), "ink": _mat("273740", 0.10),
		"green": _mat("466762", 0.14), "wood": _mat("63483c", 0.11, 0.45),
		"amber": _mat("ad8050", 0.13), "brass": _mat("d3a25f", 0.24),
		"red": _mat("794445", 0.16), "runner": _mat("794445", 0.16),
		"rule": _mat("b7a27f", 0.28), "paper": _mat("d9c093", 0.23),
		"page": _mat("e4d0a8", 0.25), "light": _mat("ffcb86", 2.4),
		"glass": _mat("779eb4", 0.88), "night": _mat("202e46", 0.42)}
	var frost := StandardMaterial3D.new()
	frost.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	frost.albedo_color = Color("83a6bd")
	bindings.frost = frost
	bindings.runner.set_shader_parameter("runner", 1.0)

func _mat(pigment: String, fill: float, wood := 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Finish
	mat.set_shader_parameter("pigment", Color(pigment))
	mat.set_shader_parameter("emission_gain", fill)
	mat.set_shader_parameter("grain", 0.08)
	mat.set_shader_parameter("two_tone", true)
	mat.set_shader_parameter("wood", wood)
	return mat

func _mesh(mesh: Mesh, p: Vector3, color: String, parent: Node3D) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.position = p
	piece.mesh = mesh
	piece.material_override = bindings[color]
	parent.add_child(piece)
	return piece

func _box(p: Vector3, size: Vector3, color: String, parent: Node3D = null) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _mesh(mesh, p, color, room if parent == null else parent)

func _beam(a: Vector3, b: Vector3, w: float, color: String, parent: Node3D = null) -> void:
	var beam := _box((a + b) / 2, Vector3(w, w, a.distance_to(b)), color, parent)
	if absf((b - a).normalized().dot(Vector3.UP)) > 0.995:
		beam.rotation.x = PI / 2
	else:
		beam.look_at(room.to_global(b), Vector3.UP)

func _cylinder(p: Vector3, axis: Vector3, r: float, height: float, color: String) -> void:
	var mesh := CylinderMesh.new()
	mesh.rings = 0
	mesh.radial_segments = 12
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = height
	_mesh(mesh, p, color, room).quaternion = Quaternion(Vector3.UP, axis)

func _text(words: String, p: Vector3, size: int, pixel: float, color: String,
		rotation_degs := Vector3.ZERO, align := HORIZONTAL_ALIGNMENT_CENTER) -> void:
	var label := Label3D.new()
	label.text = words
	label.position = p
	label.rotation_degrees = rotation_degs
	label.pixel_size = pixel
	label.font_size = size
	label.modulate = Color(color)
	label.outline_size = 0
	label.horizontal_alignment = align
	label.layers = LAYER
	room.add_child(label)

func _light(p: Vector3, color: String, energy: float, radius: float, shadows := false) -> void:
	var light := OmniLight3D.new()
	light.position = p
	light.light_color = Color(color)
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = 0.84
	light.shadow_enabled = shadows
	light.light_cull_mask = LAYER
	room.add_child(light)

func _build_service() -> void:
	# The signed route changes elevation; the room, props, lighting and camera are held fixed.
	_box(Vector3(0, -0.14, 2.38), Vector3(8.2, 0.28, 5.23), "slate")
	_box(Vector3(0, -1.84, -3.5), Vector3(8.2, 0.28, 7.1), "ink")
	_box(Vector3(-2.57, -0.14, -2.86), Vector3(3.06, 0.28, 5.65), "slate")
	_box(Vector3(2.95, -0.14, -2.86), Vector3(2.3, 0.28, 5.65), "slate")
	_box(Vector3(0, 1.16, -5.79), Vector3(8.4, 6, 0.23), "plaster")
	for x: float in [-4.12, 4.12]:
		_box(Vector3(x, 0.98, -0.56), Vector3(0.22, 6.55, 10.8), "plaster")
	_box(Vector3(0, 4.32, -0.8), Vector3(8.4, 0.27, 10.4), "ink")
	for y: float in [0.38, 0.53, 3.72]:
		_box(Vector3(0, y, -5.66), Vector3(8.02, 0.08, 0.035), "slate")
		for x: float in [-3.99, 3.99]:
			_box(Vector3(x, y, -0.60), Vector3(0.045, 0.08, 9.94), "slate")
	for x: float in [-3.74, -3.30, 2.91, 3.34]:
		_cylinder(Vector3(x, 1.08, -5.48), Vector3.UP, 0.071, 5.45, "ink")
		for y: float in [-0.98, 0.78, 2.54]:
			_cylinder(Vector3(x, y, -5.48), Vector3.UP, 0.094, 0.075, "amber")
	# A fixed upper shelf makes 01 look like a real landing, reachable off-frame.
	_box(Vector3(0.36, 1.62, -5.24), Vector3(2.50, 0.13, 0.83), "slate")
	_box(Vector3(0.36, 1.59, -4.80), Vector3(2.58, 0.15, 0.07), "ink")
	for y: float in [-1.683, 1.683]:
		# Matching portals on stacked floors let the eye follow the wrong destination.
		_box(Vector3(0.36, y + 0.76, -5.57), Vector3(1.81, 1.82, 0.23), "ink")
		_box(Vector3(0.36, y + 0.76, -5.42), Vector3(1.48, 1.58, 0.12), "green")
		_box(Vector3(0.65, y + 0.91, -5.33), Vector3(0.41, 0.32, 0.066), "ink")
		_box(Vector3(0.65, y + 0.91, -5.28), Vector3(0.34, 0.25, 0.023), "glass")
		_box(Vector3(-0.13, y + 0.65, -5.32), Vector3(0.20, 0.048, 0.06), "brass")
		_text("B1" if y < 0.0 else "01", Vector3(1.47, y + 1.12, -5.62), 36, 0.007, "e8d4af")
	_box(Vector3(-2.31, 2.12, -3.89), Vector3(1.94, 0.92, 0.10), "ink")
	_box(Vector3(-2.31, 2.12, -3.82), Vector3(1.82, 0.80, 0.022), "bone")
	_text("SERVICE STAIRS", Vector3(-2.31, 2.23, -3.80), 40, 0.0055, "29383d")
	_text("B1  /  DOWN", Vector3(-2.31, 1.99, -3.80), 32, 0.005, "674645")
	for x: float in [-3.17, -1.47]:
		_beam(Vector3(x, 0, -3.89), Vector3(x, 2.55, -3.89), 0.07, "ink")
	_box(Vector3(-2.52, 0.59, -2.93), Vector3(1.20, 1.18, 0.62), "ink")
	for x: float in [-2.79, -2.24]:
		_box(Vector3(x, 0.62, -2.61), Vector3(0.52, 1.04, 0.045), "green")
		_box(Vector3(x + 0.12, 0.58, -2.57), Vector3(0.10, 0.028, 0.035), "brass")
		for j in range(4):
			_box(Vector3(x, 0.98 - 0.046 * j, -2.58), Vector3(0.30, 0.014, 0.012), "ink")
	_text("MAINT.", Vector3(-2.78, 0.74, -2.58), 34, 0.0029, "dac8a7")
	for x: float in [-1.17, 1.93]:
		_beam(Vector3(x, 0.03, -0.27), Vector3(x, 1.03, -0.27), 0.10, "ink")
		_beam(Vector3(x, 0.99, -0.27), Vector3(x, 0.99, -4.95), 0.055, "ink")
		for z: float in [-1.5, -3.0, -4.53]:
			_beam(Vector3(x, 0, z), Vector3(x, 0.99, z), 0.04, "ink")
	for j in range(11):
		_box(Vector3(-0.94 + 0.253 * j, 0.009, 0.16), Vector3(0.13, 0.012, 0.14), "amber")
	_box(Vector3(0.37, 4.08, -3.1), Vector3(1.72, 0.25, 0.35), "ink")
	_box(Vector3(0.37, 3.92, -3.1), Vector3(1.53, 0.067, 0.21), "light")
	_light(Vector3(0.37, 3.66, -3.02), "ffe1b8", 1.7, 8.0, true)
	_light(Vector3(0.2, 1.60, 2.61), "c6dce6", 0.88, 8.6)
	_light(Vector3(0.36, -0.88, -4.06), "89b1ac", 0.7, 5.8)
	flight = _stair_flight(-1.0)
	up_flight = _stair_flight(1.0)

func _stair_flight(direction: float) -> Node3D:
	var group := Node3D.new()
	group.name = "DownFlight" if direction < 0 else "UpFlight"
	room.add_child(group)
	for i in range(11):
		var y := direction * 0.153 * (i + 1)
		var z := -0.42 - 0.378 * i
		_box(Vector3(0.36, y - 0.091, z), Vector3(2.30, 0.18, 0.38), "plaster", group)
		_box(Vector3(0.36, y + 0.008, z + 0.162), Vector3(2.30, 0.021, 0.054), "bone", group)
	_box(Vector3(0.36, direction * 1.683 - 0.07, -4.90), Vector3(2.32, 0.13, 1.36), "slate", group)
	for x: float in [-0.74, 1.46]:
		for i in [0, 3, 6, 10]:
			var p := Vector3(x, direction * 0.153 * (i + 1), -0.42 - 0.378 * i)
			_beam(p, p + Vector3.UP * 0.84, 0.047, "ink", group)
		for y: float in [0.49, 0.83]:
			_beam(Vector3(x, y + direction * 0.153, -0.38), Vector3(x, y + direction * 1.683, -4.24), 0.057, "amber", group)
	return group

func _build_archive() -> void:
	_box(Vector3(0, -0.14, -0.55), Vector3(9, 0.28, 11), "wood")
	_box(Vector3(0, 1.85, -5.58), Vector3(9, 4, 0.29), "slate")
	_box(Vector3(4.42, 1.85, -0.67), Vector3(0.25, 4, 10), "slate")
	_box(Vector3(0, 3.88, -0.60), Vector3(9, 0.25, 10), "ink")
	# Real opening in the left shell, with deep reveals and a dusk backing outside the room.
	for span: Vector2 in [Vector2(-4.51, 2.30), Vector2(2.43, 4.26)]:
		_box(Vector3(-4.42, 1.89, span.x), Vector3(0.31, 4.0, span.y), "slate")
	_box(Vector3(-4.42, 0.53, -1.52), Vector3(0.31, 1.34, 3.65), "plaster")
	_box(Vector3(-4.42, 3.48, -1.52), Vector3(0.31, 0.70, 3.65), "plaster")
	_box(Vector3(-4.95, 2.14, -1.52), Vector3(0.05, 2.07, 3.78), "frost")
	for z: float in [-3.31, -2.40, -1.50, -0.60, 0.27]:
		_box(Vector3(-4.46, 2.16, z), Vector3(0.23, 2.01, 0.069), "ink")
	for y: float in [1.18, 2.04, 3.13]:
		_box(Vector3(-4.41, y, -1.53), Vector3(0.30, 0.085, 3.73), "ink")
	_box(Vector3(-4.25, 1.20, -1.53), Vector3(0.52, 0.12, 3.8), "bone")
	_light(Vector3(-4.55, 2.29, -1.53), "a2cdff", 1.7, 8.1, true)
	_box(Vector3(0.42, 0.016, -0.88), Vector3(5.36, 0.029, 6.30), "runner")
	for x: float in [-2.14, 2.98]:
		_box(Vector3(x, 0.035, -0.88), Vector3(0.07, 0.013, 6.30), "amber")
	for z: float in [-3.98, 2.20]:
		_box(Vector3(0.42, 0.035, z), Vector3(5.36, 0.013, 0.067), "amber")
	for i in range(4):
		_archive_case(-3.19 + 2.12 * i)
	_box(Vector3(0.02, 3.44, -5.14), Vector3(6.84, 0.36, 0.15), "ink")
	_text("A C A D E M Y   /   R E C O R D S", Vector3(0.02, 3.46, -5.04), 44, 0.006, "cbb18a")
	_box(Vector3(0.17, 0.92, -1.55), Vector3(2.82, 0.13, 1.34), "wood")
	_box(Vector3(0.17, 0.81, -1.55), Vector3(2.56, 0.14, 1.13), "ink")
	for x: float in [-1.02, 1.35]:
		for z: float in [-2.06, -1.04]:
			_box(Vector3(x, 0.452, z), Vector3(0.13, 0.90, 0.13), "wood")
	_box(Vector3(0.12, 0.48, -2.80), Vector3(0.68, 0.085, 0.64), "green")
	_box(Vector3(0.12, 0.80, -3.07), Vector3(0.68, 0.71, 0.09), "wood")
	for x: float in [-0.15, 0.39]:
		for z: float in [-3.06, -2.53]:
			_box(Vector3(x, 0.23, z), Vector3(0.059, 0.46, 0.059), "wood")
	for i in range(4):
		_box(Vector3(0.93, 1.012 + i * 0.026, -1.77), Vector3(0.42, 0.022, 0.34), "paper").rotation.y = 0.17 * sin(i * 2.1)
	_cylinder(Vector3(-0.88, 1.006, -1.88), Vector3.UP, 0.18, 0.046, "ink")
	_cylinder(Vector3(-0.88, 1.24, -1.88), Vector3.UP, 0.027, 0.47, "brass")
	_box(Vector3(-0.74, 1.50, -1.88), Vector3(0.50, 0.16, 0.32), "green")
	_box(Vector3(-0.74, 1.41, -1.88), Vector3(0.44, 0.029, 0.24), "light")
	_light(Vector3(-0.71, 1.36, -1.84), "ffd397", 1.15, 3.45, true)
	_light(Vector3(1.82, 2.36, -0.2), "d2bcaa", 0.70, 7.8)
	_archive_sideboard()
	_ledger()

func _archive_sideboard() -> void:
	# Low catalogue drawers and a pinned circulation notice give the empty wall a function.
	_box(Vector3(3.94, 0.49, -1.52), Vector3(0.77, 0.94, 2.22), "wood")
	_box(Vector3(3.92, 0.98, -1.52), Vector3(0.86, 0.10, 2.35), "green")
	for y: float in [0.27, 0.51, 0.75]:
		for z: float in [-2.24, -1.52, -0.80]:
			_box(Vector3(3.539, y, z), Vector3(0.047, 0.225, 0.69), "wood")
			_box(Vector3(3.508, y + 0.018, z), Vector3(0.027, 0.044, 0.15), "brass")
	_box(Vector3(4.265, 2.06, -2.58), Vector3(0.075, 1.03, 1.63), "wood")
	_box(Vector3(4.211, 2.12, -2.60), Vector3(0.024, 0.77, 1.37), "paper")
	_text("RECORDS IN TRANSIT", Vector3(4.192, 2.35, -2.60), 38, 0.004, "374952", Vector3(0, -90, 0))
	for i in range(3):
		_box(Vector3(4.192, 2.14 - 0.10 * i, -2.56), Vector3(0.008, 0.019, 0.97 - 0.09 * i), "rule")

func _archive_case(x: float) -> void:
	_box(Vector3(x, 1.55, -5.28), Vector3(2.06, 3.11, 0.19), "ink")
	for edge: float in [-0.98, 0.98]:
		_box(Vector3(x + edge, 1.55, -4.96), Vector3(0.13, 3.10, 0.58), "wood")
	for row in range(4):
		var y := 0.18 + row * 0.75
		_box(Vector3(x, y, -4.96), Vector3(1.94, 0.10, 0.57), "wood")
		for col in range(3):
			if posmod(row * 7 + col * 3 + int(x * 4), 13) == 0:
				continue
			var center := x + (col - 1) * 0.57
			var tone: String = ["paper", "green", "red", "plaster"][posmod(row + col + int(x * 4), 4)]
			_box(Vector3(center, y + 0.22, -4.98), Vector3(0.50, 0.33, 0.45), tone)
			_box(Vector3(center, y + 0.39, -4.98), Vector3(0.53, 0.054, 0.49), tone)
			_box(Vector3(center, y + 0.25, -4.74), Vector3(0.23, 0.09, 0.023), "paper")
	_box(Vector3(x, 3.08, -4.96), Vector3(2.08, 0.17, 0.62), "wood")

func _ledger() -> void:
	_box(Vector3(0.10, 1.003, -1.44), Vector3(1.21, 0.032, 0.80), "red")
	for x: float in [-0.19, 0.39]:
		_box(Vector3(x, 1.029, -1.44), Vector3(0.555, 0.026, 0.756), "paper")
		_box(Vector3(x, 1.043, -1.44), Vector3(0.545, 0.006, 0.746), "page")
		for depth: float in [-1.57, -1.49, -1.41, -1.33, -1.25, -1.17]:
			_box(Vector3(x, 1.046, depth), Vector3(0.475, 0.002, 0.0025), "rule")
	var flat := Vector3(-90, 0, 0)
	_text("NIGHT REGISTER", Vector3(-0.19, 1.052, -1.708), 48, 0.00097, "34464b", flat)
	_text("TIME       LEVEL       LANDING", Vector3(-0.19, 1.052, -1.627), 32, 0.00088, "576566", flat)
	for i in range(3):
		var row: String = ["03:41      B1       LOWER", "03:48      B1       LOWER", "04:02      01       SAME DOOR"][i]
		_text(row, Vector3(-0.19, 1.052, -1.53 + i * 0.08), 32, 0.00086, "39454b", flat)
	_text("Filed  /  Night porter", Vector3(0.39, 1.052, -1.706), 38, 0.00090, "39454b", flat)
	_text("B1 still points DOWN.", Vector3(0.39, 1.052, -1.45), 40, 0.00088, "984b45", flat)
	_text("The flight does not.", Vector3(0.39, 1.052, -1.37), 40, 0.00088, "984b45", flat)

func _build_exhibit() -> void:
	_box(Vector3(0, -0.14, -0.48), Vector3(10, 0.28, 12), "slate")
	_box(Vector3(0, 2.61, -3.26), Vector3(9.6, 5.5, 0.21), "night")
	for x: float in [-4.65, 4.65]:
		_box(Vector3(x, 2.61, -0.24), Vector3(0.22, 5.5, 6.5), "slate")
	for x: float in [-3.8, -2.65, -1.5, 1.5, 2.65, 3.8]:
		_box(Vector3(x, 2.68, -3.1), Vector3(0.11, 5.28, 0.21), "ink")
	_box(Vector3(0, 0.08, -0.92), Vector3(2.84, 0.16, 2.04), "ink")
	_box(Vector3(0, 0.38, -0.92), Vector3(2.33, 0.55, 1.70), "slate")
	_box(Vector3(0, 0.68, -0.92), Vector3(2.77, 0.15, 1.96), "plaster")
	_box(Vector3(0, 0.44, -0.053), Vector3(1.68, 0.29, 0.037), "ink")
	_text("M E R I D I A N   /   0 3", Vector3(0, 0.46, -0.028), 46, 0.0038, "e5b676")
	meridian = Meridian.new()
	meridian.position = Vector3(0, 2.075, -0.92)
	room.add_child(meridian)
	_light(Vector3(-2.38, 3.68, 1.2), "f8d1a5", 2.45, 7.5, true)
	_light(Vector3(2.0, 2.65, 1.57), "c5dfff", 1.1, 6.1)
	_light(Vector3(-1.38, 3.1, -1.85), "a4cbff", 0.65, 5.1)

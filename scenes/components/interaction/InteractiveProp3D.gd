extends Node3D
## Shared physical detail models for gameplay close-ups and the interaction laboratory.
@export var kind := "wardrobe"
@export var original_surface := false
var pivot: Node3D
var hand: Node3D
var sleeve: Node3D
var fibers: Node3D
var tool: Node3D
var progress := 0.0
var completed := false
signal sampled
var _sound: AudioStreamPlayer3D

func _ready() -> void:
	name = "Detail_" + kind
	match kind:
		"wardrobe": _wardrobe()
		"ratchet": _ratchet()
		"grille": _grille()
		"hand", "sleeve", "copper": _body_trace()
		"water", "cloth", "chalk": _sample_surface()
		"drag", "boots": _floor_trace()
		"seal": _sealed_grille()
		_: _wardrobe()
	_sound = AudioStreamPlayer3D.new()
	_sound.bus = &"Sfx" if AudioServer.get_bus_index("Sfx") >= 0 else &"Master"
	_sound.max_db = -25.0
	_sound.volume_db = -28.0
	add_child(_sound)

static func material(color: Color, metallic := 0.0) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.metallic = metallic
	result.roughness = 0.62 if metallic == 0.0 else 0.32
	return result

static func box(parent: Node3D, dimensions: Vector3, at: Vector3, color: Color, metallic := 0.0) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = dimensions
	mesh.mesh = shape
	mesh.material_override = material(color, metallic)
	parent.add_child(mesh)
	mesh.position = at
	return mesh

static func rod(parent: Node3D, from: Vector3, to: Vector3, radius: float, color: Color) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius * 0.8
	shape.bottom_radius = radius
	shape.height = from.distance_to(to)
	shape.radial_segments = 8
	mesh.mesh = shape
	mesh.material_override = material(color)
	parent.add_child(mesh)
	mesh.position = (from + to) * 0.5
	if absf((to - from).normalized().dot(Vector3.UP)) < 0.999:
		mesh.basis = Basis.looking_at((to - from).normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI / 2.0)
	return mesh

func _wardrobe() -> void:
	var wood := Color("#4b3428")
	var interior_wood := Color("#654735")
	var shelf_wood := Color("#76523a")
	box(self, Vector3(1.36, 1.94, 0.07), Vector3(0, 0.99, -0.36), interior_wood.darkened(0.12))
	for side in [-1.0, 1.0]: box(self, Vector3(0.09, 2.0, 0.8), Vector3(side * 0.7, 1.0, 0), wood)
	for height in [0.08, 1.96]: box(self, Vector3(1.46, 0.09, 0.8), Vector3(0, height, 0), wood)
	box(self, Vector3(1.33, 0.055, 0.72), Vector3(0, 0.46, 0), shelf_wood)
	box(self, Vector3(1.28, 0.07, 0.035), Vector3(0, 0.46, 0.375), shelf_wood.lightened(0.12))
	rod(self, Vector3(-0.61, 1.65, -0.03), Vector3(0.61, 1.65, -0.03), 0.018, Color("#c0a164"))
	var interior_fill := OmniLight3D.new()
	interior_fill.name = "InteriorFill"
	interior_fill.position = Vector3(0, 1.34, 0.18)
	interior_fill.light_color = Color("#f0bd72")
	interior_fill.light_energy = 1.15
	interior_fill.omni_range = 2.2
	interior_fill.shadow_enabled = false
	add_child(interior_fill)
	pivot = Node3D.new()
	add_child(pivot)
	# Keep the physical front hinge fixed; the wider outward swing clears the opening.
	pivot.position = Vector3(-0.68, 1.0, 0.42)
	box(pivot, Vector3(1.36, 1.87, 0.055), Vector3(0.68, 0, 0), wood.lightened(0.05))
	for height in [-0.63, 0.63]: box(pivot, Vector3(1.12, 0.035, 0.018), Vector3(0.68, height, 0.037), Color("#836444"))
	box(pivot, Vector3(0.045, 0.15, 0.065), Vector3(1.17, -0.03, 0.065), Color("#baa168"), 0.7)
	set_meta("door_open_degrees",-145.0)
	set_meta("focus", Vector3(0, 1.0, 0.0))
	set_meta("camera_offset", Vector3(2.1, 0.8, 3.2))

func _ratchet() -> void:
	box(self, Vector3(0.7, 0.74, 0.06), Vector3(0, 0.5, -0.06), Color("#44372d"), 0.5)
	pivot = Node3D.new()
	add_child(pivot)
	pivot.position.y = 0.52
	var gear := CylinderMesh.new()
	gear.top_radius = 0.23
	gear.bottom_radius = 0.23
	gear.height = 0.07
	gear.radial_segments = 24
	var face := MeshInstance3D.new()
	face.mesh = gear
	face.material_override = material(Color("#c29a55"), 0.8)
	face.rotation.x = PI / 2.0
	pivot.add_child(face)
	for index in 12:
		var angle := TAU * index / 12.0
		var tooth := box(pivot, Vector3(0.085, 0.10, 0.075), Vector3(sin(angle) * 0.25, cos(angle) * 0.25, 0), Color("#c29a55"), 0.8)
		tooth.rotation.z = -angle
	box(self, Vector3(0.09, 0.28, 0.10), Vector3(0.24, 0.78, 0.045), Color("#9a9b93"), 0.9).rotation.z = -0.52
	box(self, Vector3(0.09, 0.09, 0.14), Vector3(0, 0.52, 0.06), Color("#3b3631"), 0.8)
	set_meta("focus", Vector3(0, 0.54, 0.03))
	set_meta("camera_offset", Vector3(0.42, 0.28, 1.18))

func _grille() -> void:
	box(self, Vector3(1.18, 0.9, 0.06), Vector3(0, 0.5, -0.08), Color("#181e20"))
	pivot = Node3D.new()
	add_child(pivot)
	pivot.position = Vector3(-0.58, 0.5, 0)
	for index in 7:
		box(pivot, Vector3(1.14, 0.055, 0.08), Vector3(0.58, -0.37 + index * 0.12, 0), Color("#81877e"), 0.7).rotation.x = 0.3
	set_meta("focus", Vector3(0, 0.5, 0))
	set_meta("camera_offset", Vector3(0.8, 0.55, 1.8))

func _body_trace() -> void:
	hand = Node3D.new()
	add_child(hand)
	hand.position = Vector3(-0.12, 0.36, 0)
	box(hand, Vector3(0.15, 0.05, 0.2), Vector3.ZERO, Color("#c29a80"))
	box(hand, Vector3(0.12, 0.055, 0.21), Vector3(0, -0.004, 0.19), Color("#3a4749"))
	for index in 4:
		var x := -0.055 + index * 0.037
		rod(hand, Vector3(x, 0, -0.07), Vector3(x, -0.007, -0.205 + absf(index - 1.5) * 0.018), 0.016, Color("#c29a80"))
	rod(hand, Vector3(0.065, 0.0, 0.035), Vector3(0.115, -0.005, -0.06), 0.02, Color("#c29a80"))
	for index in 3:
		var x := -0.045 + index * 0.035
		rod(hand, Vector3(x, 0.027, -0.045), Vector3(x + 0.017, 0.027, 0.052), 0.0028, Color("#9e3f3e"))
	sleeve = Node3D.new()
	add_child(sleeve)
	# Object-only correction: keep the cuff below the unchanged comparison hand.
	sleeve.position = Vector3(0.23, 0.30, -0.01)
	box(sleeve, Vector3(0.16, 0.065, 0.24), Vector3.ZERO, Color("#59616b"))
	for index in 7:
		var x := -0.068 + index * 0.022
		rod(sleeve, Vector3(x, 0.034, 0.11), Vector3(x - 0.013, 0.037, 0.15 + (index % 3) * 0.011), 0.002, Color("#b4b2ab"))
	sleeve.visible = kind == "sleeve"
	if kind == "copper":
		for index in 8:
			box(hand, Vector3(0.008, 0.004, 0.014), Vector3(sin(index * 2.2) * 0.05, 0.03, cos(index * 3.7) * 0.055), Color("#c4894c"), 0.7)
	set_meta("focus", Vector3(0, 0.36, 0))
	set_meta("camera_offset", Vector3(0.28, 0.52, 0.43))

func _sample_surface() -> void:
	var cloth := kind == "cloth"
	if not original_surface:
		# The laboratory supplies a neutral support; gameplay uses its real floor/towel.
		box(self, Vector3(0.95, 0.04, 0.7), Vector3(0, -0.025, 0), Color("#4b4034"))
	if kind == "chalk":
		for index in 12:
			var at := Vector3(sin(index * 2.5) * 0.22, 0.002, cos(index * 1.7) * 0.085)
			rod(self, at, at + Vector3(0.045, 0, 0.012), 0.0018, Color("#e2dfc2"))
	else:
		var decal := preload("res://scenes/components/interaction/SurfaceDecal3D.gd").new()
		add_child(decal)
		decal.install(kind, Vector2(0.10, 0.32) if cloth and original_surface else Vector2(0.72, 0.32), true)
		decal.position.y = 0.002
	fibers = Node3D.new()
	add_child(fibers)
	fibers.position = Vector3(0.22, 0.37, 0.08)
	for index in 5: rod(fibers, Vector3(index * 0.005, 0, 0), Vector3(index * 0.005 + 0.012, 0.09, 0.015), 0.002, Color("#dbd4ad"))
	fibers.visible = false
	tool = Node3D.new()
	add_child(tool)
	tool.position = Vector3(0.1, 0.26, 0.08)
	rod(tool, Vector3(-0.009, 0, 0), Vector3(-0.025, 0.17, 0.04), 0.005, Color("#b4bdba"))
	rod(tool, Vector3(0.009, 0, 0), Vector3(0.025, 0.17, 0.04), 0.005, Color("#b4bdba"))
	if original_surface:
		tool.scale = Vector3.ONE * (0.35 if cloth else 0.6)
		tool.position = Vector3(0, 0.06, 0)
		fibers.scale = Vector3.ONE * (0.35 if cloth else 0.7)
		fibers.position = Vector3(0.025, 0.12, 0)
	set_meta("sample_extent", Vector2(0.10, 0.32) if cloth and original_surface else Vector2(0.72, 0.32))
	set_meta("focus", Vector3(0, 0.002, 0))
	set_meta("camera_offset", Vector3(0.35, 0.65, 0.65))

func _floor_trace() -> void:
	if not original_surface: box(self,Vector3(1.4,0.04,1.45),Vector3(0,-0.025,0),Color("#787363"))
	var decal := preload("res://scenes/components/interaction/SurfaceDecal3D.gd").new()
	add_child(decal)
	decal.install(kind, Vector2(0.65, 1.10) if kind == "boots" else Vector2(0.60, 1.3), kind == "boots")
	decal.position.y = 0.002
	tool = Node3D.new()
	add_child(tool)
	tool.position = Vector3(0,0.025,-0.40)
	box(tool,Vector3(0.10,0.06,0.20),Vector3.ZERO,Color("#594535"))
	fibers = Node3D.new()
	add_child(fibers)
	fibers.visible = false
	set_meta("focus",Vector3(0,0.002,0))
	set_meta("camera_offset",Vector3(0.35,1.30,1.25))

func _sealed_grille() -> void:
	_grille()
	for side in [-1.0,1.0]:
		box(self,Vector3(0.04,0.60,0.025),Vector3(side*0.38,0.5,0.06),Color("#846944"),0.2)
	rod(self,Vector3(-0.42,0.66,0.09),Vector3(0.42,0.34,0.09),0.006,Color("#8a8776"))
	box(self,Vector3(0.09,0.09,0.025),Vector3(0,0.50,0.11),Color("#9a9988"),0.4)

func activate() -> void:
	if completed: return
	match kind:
		"seal":
			play_sound("metal")
			var tween := create_tween()
			for angle in [0.008,-0.006,0.0]: tween.tween_property(pivot,"rotation:y",angle,0.09)
			await tween.finished
			completed = true
			sampled.emit()
		"wardrobe", "grille":
			var tween := create_tween().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tween.tween_property(pivot, "rotation:y", deg_to_rad(float(get_meta("door_open_degrees",-105.0)) if kind == "wardrobe" else -28.0), 0.2)
			play_sound("wood")
			await tween.finished
			completed = true
			if is_inside_tree(): sampled.emit()
		"ratchet":
			play_sound("metal")
			var tween := create_tween()
			for angle in [0.07, -0.035, 0.05, 0.0]: tween.tween_property(pivot, "rotation:z", angle, 0.055)
			await tween.finished
			completed = true
			if is_inside_tree(): sampled.emit()

func sweep(distance: float, local_position: Vector2) -> void:
	if completed or tool == null: return
	if kind in ["drag","boots"]:
		tool.position = Vector3(0.14,0.025,clampf(local_position.x*2.0,-0.4,0.5))
	else:
		var extent: Vector2 = get_meta("sample_extent", Vector2(0.72, 0.32))
		tool.position = Vector3(clampf(local_position.x / 0.4, -1, 1) * extent.x * 0.45,
			0.06 if original_surface else 0.1, clampf(local_position.y / 0.2, -1, 1) * extent.y * 0.45)
	progress = minf(1.0, progress + distance / 180.0)
	if progress < 1.0: return
	completed = true
	fibers.visible = true
	play_sound("cloth")
	if kind in ["drag","boots"]: sampled.emit(); return
	var tween := create_tween().set_parallel(true)
	tween.tween_property(tool, "position", Vector3(0.025, 0.14, 0) if original_surface else Vector3(0.22, 0.41, 0.08), 0.55)
	tween.tween_property(fibers, "position:y", 0.14 if original_surface else 0.40, 0.55)
	sampled.emit()

func align_hand(offset: Vector2) -> void:
	if hand == null: return
	if kind == "sleeve":
		hand.position.x = clampf(offset.x, -0.2, 0.25)
		if hand.position.x > 0.17 and not completed:
			completed = true
			play_sound("cloth")
			var tween := create_tween().set_parallel(true)
			tween.tween_property(hand, "position", Vector3(0.15, 0.36, 0.05), 0.3)
			tween.tween_property(sleeve, "rotation:x", 0.0, 0.3)
			sampled.emit()
	else:
		hand.rotation.y = offset.x * 2.0
		if absf(offset.x) > 0.12 and not completed:
			completed = true
			sampled.emit()

func play_sound(cue: String) -> void:
	preload("res://scenes/components/interaction/InteractionSound.gd").play(_sound, cue)

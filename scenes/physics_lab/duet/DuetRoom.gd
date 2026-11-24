extends Node3D

const Kit := preload("res://scenes/physics_lab/shutter_loom/ShutterRoom.gd")
const STEEL := Color("46545d")
const STONE := Color("a5a8a0")
const BRASS := Color("c79857")
const FELT := Color("4d887c")
const TEAL := Color("7ce3d6")
const AMBER := Color("f4b865")
const RED := Color("f5825a")
var book := Kit.new()
var deck: Node3D
var leaf: Node3D
var runner: Node3D
var watcher: Node3D
var watcher_eye: MeshInstance3D
var listener: Node3D
var lever: Node3D
var ear_telltale: MeshInstance3D
var ear_bar: MeshInstance3D
var winding: MeshInstance3D
var gaze: MeshInstance3D
var cue_bus: Node3D
var cue_displays := {}
var fade_pier: MeshInstance3D
var fade_box: AABB
var fade_material: StandardMaterial3D
var faded := false
var stance_rim: MeshInstance3D
var parapet: Node3D
var cut_children: Array[MeshInstance3D] = []
var plan: Dictionary
const Z_SCALE := 1.43


func point(xz: Array, y: float = 0) -> Vector3:
	return Vector3(float(xz[0]) / 100, y, (float(xz[1]) - 360.0) / 100 * Z_SCALE)


func build(layout: Dictionary) -> void:
	plan = layout
	deck = Node3D.new()
	add_child(deck)
	add_child(book)
	book.deck = deck
	fade_material = book.translucent(Color(0.66, 0.86, 0.85, 0.18))
	book.box(deck, Vector3(0, -0.75, 0), Vector3(5.7, 0.44, 12.9), STEEL.darkened(0.22))
	book.box(deck, Vector3(0, -0.90, 0), Vector3(5.79, 0.08, 12.98), BRASS.darkened(0.35))
	book.box(deck, Vector3(0, -0.43, 0), Vector3(5.58, 0.28, 12.75), STEEL.darkened(0.38))
	for x: float in [-2.43, 2.43]:
		for iz in 12:
			var z := (iz - 5.5) * 1.045
			book.box(deck, Vector3(x, -0.20, z), Vector3(0.73, 0.34, 1.016), STONE.darkened(0.27))
			book.box(deck, Vector3(x, 0.0005, z), Vector3(0.71, 0.055, 1.015), STONE)
	for i in plan.stations_cm.size():
		if i > plan.gap_banks[0] and i < plan.gap_banks[1]: continue
		var p := point(plan.stations_cm[i])
		book.box(deck, p - Vector3(0, 0.17, 0), Vector3(1.10, 0.40, 0.806), STONE.lightened(0.08))
		book.box(deck, p + Vector3(0, 0.048, 0), Vector3(0.80, 0.057, 0.72), STONE if i == 0 or i == plan.stations_cm.size() - 1 else STEEL.lightened(0.13))
		for x in [-0.34, 0.34]:
			book.drum(deck, p + Vector3(x, 0.078, 0.29), 0.038, 0.019, BRASS)
	for z: float in [-6.05, -4.9, 5.72, 6.08]:
		book.box(deck, Vector3(-0.72, 0.1, z), Vector3(3.1, 0.29, 0.28), STONE)
	for z in range(-5, 7, 2):
		var x := -2.73
		book.box(deck, Vector3(x, 0.94, z), Vector3(0.24, 1.9, 0.14), STONE)
		book.box(deck, Vector3(x, 1.90, z), Vector3(0.35, 0.12, 0.28), BRASS.darkened(0.22))
		book.box(deck, Vector3(x, 0.19, z - 0.86), Vector3(0.19, 0.4, 1.71), STONE.darkened(0.16))
	var rail_start := point([plan.watcher_x_cm, plan.watcher_rail_z_cm[0]])
	var rail_end := point([plan.watcher_x_cm, plan.watcher_rail_z_cm[1]])
	for x in [-0.14, 0.14]:
		book.box(deck, (rail_start + rail_end) * 0.5 + Vector3(x, 0.13, 0),
			Vector3(0.08, 0.07, rail_end.z - rail_start.z), BRASS.darkened(0.14))
	for i in 19:
		book.box(deck, rail_start.lerp(rail_end, float(i) / 18.0) + Vector3(0, 0.075, 0), Vector3(0.51, 0.14, 0.08), STEEL)
	var parapet_height := float(plan.parapet_top_cm) * 0.01
	parapet = Node3D.new()
	deck.add_child(parapet)
	parapet.position.x = float(plan.parapet_x_cm) * 0.01
	for i in 9:
		var z := (i - 4) * 1.03
		cut_children.append(book.box(parapet, Vector3(0, parapet_height * 0.5, z), Vector3(0.19, parapet_height, 0.993), STONE))
		cut_children.append(book.box(parapet, Vector3(0, parapet_height - 0.04, z), Vector3(0.255, 0.10, 1.0), BRASS.darkened(0.25)))
		cut_children.append(book.box(parapet, Vector3(0, 0.16, z), Vector3(0.235, 0.08, 1.0), STEEL))
	leaf = Node3D.new()
	deck.add_child(leaf)
	leaf.position = point(plan.leaf_hinge_cm, 0.072)
	var leaf_len := float(plan.gap_banks[1] - plan.gap_banks[0]) * 0.6 * Z_SCALE
	var width := float(plan.leaf_width_cm) * 0.01
	book.box(leaf, Vector3(0, -0.06, leaf_len * 0.5), Vector3(width, 0.14, leaf_len), BRASS.darkened(0.22))
	for i in 8:
		book.box(leaf, Vector3(0, 0.028, (float(i) + 0.5) * leaf_len / 8.0), Vector3(width - 0.10, 0.06, leaf_len / 8.0 - 0.022), FELT.darkened(0.04 if i % 2 else 0.11))
	for x in [-0.471, 0.471]:
		book.box(leaf, Vector3(x, 0.22, leaf_len * 0.5), Vector3(0.061, 0.065, leaf_len), BRASS)
		for z in [0.15, 1.64, leaf_len - 0.1]:
			book.box(leaf, Vector3(x, 0.107, z), Vector3(0.055, 0.20, 0.055), STEEL)
	var h := book.drum(deck, leaf.position, 0.14, 1.28, BRASS)
	h.rotation.z = PI * 0.5
	var porch := point(plan.stations_cm[0]); var end := point(plan.stations_cm[-1]);
	book.arch(end + Vector3(0, 1.34, 0.64), 0.67, 0.58, 0.08)
	for x in [-0.69, 0.69]:
		book.box(deck, end + Vector3(x, 0.69, 0.63), Vector3(0.17, 1.35, 0.34), STONE)
	book.box(deck, porch + Vector3(0.80, 0.30, 0), Vector3(0.42, 0.50, 0.42), STEEL)
	lever = Node3D.new()
	deck.add_child(lever)
	lever.position = porch + Vector3(0.80, 0.58, 0)
	book.box(lever, Vector3(0, 0.16, 0), Vector3(0.055, 0.33, 0.065), BRASS)
	book.drum(lever, Vector3(0, 0.34, 0), 0.080, 0.11, AMBER)
	stamp("LEVER", porch + Vector3(0.80, 0.10, 0.46))
	stamp("PORCH", porch + Vector3(0, 0.10, -0.45))
	stamp("EXIT", end + Vector3(0, 0.10, 0.04))
	stamp("SIGHT RAIL", Vector3(-2.46, 0.06, 1.85))
	build_watcher()
	build_listener()
	runner = build_actor()
	book.beam(deck, Vector3.ZERO, Vector3.ONE, book.translucent(Color(0.49, 0.88, 0.85, 0.44)), "gaze")
	gaze = book.beams.gaze
	cue_bus = Node3D.new()
	deck.add_child(cue_bus)
	for kind: String in ["leaf", "listener", "sight", "recovery"]:
		var n := Node3D.new()
		cue_bus.add_child(n)
		cue_displays[kind] = n
		for i in 4:
			var rid := TorusMesh.new()
			rid.inner_radius = 0.15 + 0.06 * i
			rid.outer_radius = rid.inner_radius + 0.05
			rid.ring_segments = 8
			book.mesh(n, rid, Vector3(0, i * 0.069, 0), book.mat(RED if kind != "leaf" else AMBER, true))
	fade_pier = book.box(deck, Vector3(0.92, 0.80, -3.82), Vector3(0.38, 1.58, 0.44), STONE)
	fade_box = AABB(fade_pier.position - fade_pier.scale * 0.5, fade_pier.scale)


func build_actor() -> Node3D:
	var n := Node3D.new()
	deck.add_child(n)
	book.drum(n, Vector3(0, 0.10, 0), 0.217, 0.17, STEEL)
	book.drum(n, Vector3(0, 0.49, 0), 0.13, 0.66, STEEL)
	book.drum(n, Vector3(0, 0.99, 0), 0.20, 0.39, BRASS)
	book.drum(n, Vector3(0, 1.27, 0), 0.23, 0.11, STEEL)
	stance_rim = book.drum(n, Vector3(0, 1.45, 0), 0.142, 0.24, AMBER, true)
	return n


func build_watcher() -> void:
	watcher = Node3D.new()
	deck.add_child(watcher)
	book.box(watcher, Vector3(0, 0.25, 0), Vector3(0.47, 0.25, 0.57), STEEL)
	for z in [-0.24, 0.24]:
		book.drum(watcher, Vector3(0, 0.30, z), 0.20, 0.29, BRASS)
	book.box(watcher, Vector3(0, 0.68, 0), Vector3(0.26, 0.73, 0.30), STONE)
	book.drum(watcher, Vector3(0, 1.05, 0), 0.18, 0.38, STEEL)
	watcher_eye = book.box(watcher, Vector3(0.21, 1.17, 0), Vector3(0.075, 0.16, 0.29), RED, true)
	book.box(watcher, Vector3(0, 1.33, 0), Vector3(0.33, 0.105, 0.44), BRASS)
	winding = book.drum(watcher, Vector3(-0.20, 0.75, 0), 0.178, 0.12, BRASS)
	winding.rotation.z = PI * 0.5


func build_listener() -> void:
	listener = Node3D.new()
	deck.add_child(listener)
	listener.position = point(plan.ear_cm)
	book.box(listener, Vector3(0, 0.14, 0), Vector3(0.89, 0.31, 0.99), STEEL)
	book.drum(listener, Vector3(0, 0.56, 0), 0.20, 0.65, STONE)
	var horn := CylinderMesh.new()
	horn.top_radius = 0.39
	horn.bottom_radius = 0.105
	horn.height = 0.62
	var mouth := book.mesh(listener, horn, Vector3(-0.25, 1.02, 0), book.mat(BRASS))
	mouth.rotation.z = PI * 0.5
	var black := book.drum(listener, Vector3(-0.576, 1.02, 0), 0.33, 0.025, STEEL.darkened(0.15))
	black.rotation.z = PI * 0.5
	ear_telltale = book.drum(listener, Vector3(-0.60, 1.02, 0), 0.11, 0.023, AMBER)
	ear_telltale.rotation.z = PI * 0.5
	ear_bar = book.box(listener, Vector3(0.43, 0.43, 0.48), Vector3(0.14, 0.05, 0.08), AMBER, true)
	stamp("LISTENER", listener.position + Vector3(0.16, 0.05, 0.73))


func stamp(words: String, position: Vector3) -> void:
	book.box(deck, position, Vector3(0.91, 0.026, 0.203), STEEL)
	var l := Label3D.new()
	l.text = words
	l.font_size = 50
	l.pixel_size = 0.0032
	l.modulate = Color("f5dfb9")
	l.outline_size = 0
	l.rotation.x = -PI * 0.5
	deck.add_child(l)
	l.position = position + Vector3.UP * 0.022


func draw(state: Dictionary, camera: Camera3D) -> void:
	leaf.rotation.x = -deg_to_rad(float(state.leaf.angle_deg))
	lever.rotation.x = -0.50 if state.leaf.phase == "up" else 0.50
	var rider_y := -0.43 if state.player.zone == "service" else 0.11
	runner.position = point(state.player.position_cm, rider_y)
	runner.scale.y = 0.58 if state.player.posture == "low" else 1.0
	stance_rim.material_override = book.mat(TEAL if state.sight.gaze else AMBER, true)
	watcher.position = point(state.sight.position_cm, 0.07)
	watcher_eye.material_override = book.mat(TEAL if state.sight.gaze else RED, true)
	winding.rotation.x = clampf(float(state.sight.separation_cm) / 65.0, -PI, PI)
	ear_bar.scale.y = 0.05 + minf(float(state.hearing.ring) / float(state.hearing.cap_ring), 1.0) * 0.73
	ear_bar.position.y = 0.43 + ear_bar.scale.y * 0.5
	ear_telltale.material_override = book.mat(RED if state.hearing.mode == "warning" else AMBER if state.hearing.ring > 0 else STEEL, state.hearing.ring > 0)
	gaze.visible = state.sight.gaze and state.player.zone == "lane"
	if gaze.visible:
		book.set_beam(gaze, watcher.position + Vector3(0.25, 1.17, 0), runner.position + Vector3.UP * float(state.player.eye_height_cm) * 0.01)
	for n: Node3D in cue_displays.values(): n.visible = false
	for cue: Dictionary in state.cues:
		var cue_kind: String = cue.kind
		var name_: String = "leaf" if cue_kind.begins_with("leaf") else "listener" if cue_kind.begins_with("hearing") else "sight" if cue_kind.begins_with("sight") else "recovery"
		var object: Node3D = cue_displays[name_]
		object.visible = true
		object.position = (leaf.position + Vector3(0.63, 0, 0)) if name_ == "leaf" else listener.position if name_ == "listener" else watcher.position if name_ == "sight" else runner.position
		var progress := clampf(float(state.tick - cue.start_tick) / maxf(1.0, float(cue.due_tick - cue.start_tick)), 0.0, 1.0)
		for i in object.get_child_count():
			var ring := object.get_child(i) as MeshInstance3D
			ring.visible = i == 0 or progress >= float(i) / 4.0
		object.scale = Vector3.ONE * (0.92 + progress * 0.36)
	var key_pos := runner.position + Vector3.UP * 0.68
	faded = fade_box.intersects_segment(key_pos + camera.global_basis.z * 35, key_pos) != null
	fade_pier.material_override = fade_material if faded else book.mat(STONE)
	fade_pier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if faded else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var parapet_alpha := camera.global_basis.z.x < -0.18
	for i in cut_children.size():
		var child := cut_children[i]
		child.material_override = fade_material if parapet_alpha else book.mat([STONE, BRASS.darkened(0.25), STEEL][i % 3])
		child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if parapet_alpha else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

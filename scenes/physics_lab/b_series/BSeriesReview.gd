extends Node3D
## B-series whitebox review: B01 Thirteenth Tread, B02 Double Negative, B03 Counter-Tide Cloister.
## Static key states for art and layout review only; no room rules run here.
## Args: --b-room=b01|b02|b03  --b-view=0..3.  Tab next view, N next room.

const Kit := preload("res://scenes/physics_lab/shutter_loom/ShutterRoom.gd")
const Env := preload("res://scenes/components/rendering/post/Hall04.tres")
const Ink := preload("res://scenes/components/rendering/post/InkPass.gd")
const Cast := preload("res://scenes/rogue_crossing/ProductionCast.gd")

const STONE := Color("a49f90")
const PALE := Color("c4bca9")
const SHADE := Color("5c6663")
const IRON := Color("3f4b52")
const BRASS := Color("bd8a4f")
const OAK := Color("6e5136")
const RED := Color("b8402f")
const CYAN := Color(0.55, 0.86, 0.92, 0.10)
const SEPIA := Color(1.0, 0.80, 0.52, 0.16)
const WATER := Color(0.20, 0.42, 0.44, 0.78)
const ROOMS := ["b01", "b02", "b03"]
const TITLES := {"b01": "B01 · The Thirteenth Tread", "b02": "B02 · The Double Negative", "b03": "B03 · The Counter-Tide Cloister"}

var kit := Kit.new()
var world: WorldEnvironment
var ink: MeshInstance3D
var camera: Camera3D
var root: Node3D
var room := "b01"
var view := 0
var views: Array[Dictionary] = []
var cutaway: Array[Node3D] = []
var heading: Label
var caption: Label


func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--b-room="): room = argument.trim_prefix("--b-room=")
		if argument.begins_with("--b-view="): view = int(argument.trim_prefix("--b-view="))
	for pair in [["b_next_view", KEY_TAB], ["b_next_room", KEY_N]]:
		if InputMap.has_action(pair[0]): continue
		InputMap.add_action(pair[0])
		var key := InputEventKey.new()
		key.physical_keycode = pair[1]
		InputMap.action_add_event(pair[0], key)
	get_viewport().msaa_3d = Viewport.MSAA_2X
	get_viewport().scaling_3d_scale = 1.0
	world = WorldEnvironment.new()
	world.environment = Env.duplicate() as Environment
	world.environment.sdfgi_min_cell_size = 0.45
	add_child(world)
	if RenderingServer.get_current_rendering_method() == &"forward_plus":
		ink = Ink.create()
		ink.material_override.set_shader_parameter("opacity", 0.4)
		add_child(ink)
	camera = Camera3D.new()
	camera.current = true
	camera.far = 400.0
	add_child(camera)
	add_child(kit)
	var layer := CanvasLayer.new()
	add_child(layer)
	var block := VBoxContainer.new()
	block.position = Vector2(26, 18)
	layer.add_child(block)
	_text(block, "THE SLEEPING ACADEMY  /  B-SERIES WHITEBOX", 13, Color("abdcd1"))
	heading = _text(block, "", 30, Color("f5ead3"))
	caption = _text(block, "", 15, Color("e3d6bb"))
	build()


func _text(parent: Node, value: String, size: int, hue: Color) -> Label:
	var l := Label.new()
	l.text = value
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", hue)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(l)
	return l


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("b_next_view"):
		view = (view + 1) % views.size()
		frame()
	elif event.is_action_pressed("b_next_room"):
		room = ROOMS[(ROOMS.find(room) + 1) % ROOMS.size()]
		view = 0
		build()
	else:
		return
	get_viewport().set_input_as_handled()


func build() -> void:
	if root != null:
		root.free()
	root = Node3D.new()
	add_child(root)
	kit.deck = root
	views.clear()
	cutaway.clear()
	match room:
		"b01": build_b01()
		"b02": build_b02()
		"b03": build_b03()
	view = clampi(view, 0, views.size() - 1)
	frame()


func frame() -> void:
	var v: Dictionary = views[view]
	for n in cutaway:
		n.visible = not v.get("cut", false)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL if v.get("ortho", false) else Camera3D.PROJECTION_PERSPECTIVE
	camera.size = v.get("size", 40.0)
	camera.fov = v.get("fov", 68.0)
	camera.position = v.eye
	camera.look_at(v.at, v.get("up", Vector3.UP))
	heading.text = "%s  —  %s" % [TITLES[room], v.name]
	caption.text = v.note


func mcp_observe() -> Dictionary:
	return {"room": room, "view": view, "view_name": views[view].name, "views": views.size(), "render": {
		"msaa_samples": 2, "scaling_3d_scale": get_viewport().scaling_3d_scale,
		"ink_opacity": ink.material_override.get_shader_parameter("opacity") if ink != null else 0.0,
		"sdfgi_enabled": world.environment.sdfgi_enabled, "atmosphere_baseline": Env.resource_path,
		"opaque_shader": Kit.Finish.resource_path}}


# ------------------------------------------------------------------ shared helpers
func box(at: Vector3, size: Vector3, c: Color, lit := false, parent: Node3D = null) -> MeshInstance3D:
	return kit.box(parent if parent else root, at, size, c, lit)


func rod(a: Vector3, b: Vector3, thick: float, c: Color, parent: Node3D = null) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = Vector3(thick, a.distance_to(b), thick)
	var n := kit.mesh(parent if parent else root, shape, (a + b) * 0.5, kit.mat(c))
	n.quaternion = Quaternion(Vector3.UP, (b - a).normalized())
	return n


func ball(at: Vector3, radius: float, c: Color, lit := false, parent: Node3D = null) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	return kit.mesh(parent if parent else root, s, at, kit.mat(c, lit))


func glass(at: Vector3, radius: float, c: Color, parent: Node3D = null) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = radius
	s.height = radius * 2.0
	var m := kit.translucent(c)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var n := kit.mesh(parent if parent else root, s, at, m)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func sheet(at: Vector3, size: Vector3, c: Color, parent: Node3D = null) -> MeshInstance3D:
	var n := kit.mesh(parent if parent else root, BoxMesh.new(), at, kit.translucent(c))
	n.scale = size
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func lamp(at: Vector3, energy: float, reach: float, hue := Color("ffd9a8"), shadows := false) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = hue
	l.light_energy = energy
	l.omni_range = reach
	l.shadow_enabled = shadows
	root.add_child(l)
	l.position = at
	return l


func plaque(text: String, at: Vector3, size: float, hue: Color, yaw := 0.0, facing := false) -> void:
	var l := Label3D.new()
	if facing:
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.text = text
	l.font_size = 64
	l.pixel_size = size / 64.0
	l.modulate = hue
	l.outline_size = 6
	l.outline_modulate = Color(0, 0, 0, 0.7)
	root.add_child(l)
	l.position = at
	l.rotation.y = yaw


func person(id: String, at: Vector3, yaw: float, clip := &"idle") -> Node3D:
	var holder := Node3D.new()
	root.add_child(holder)
	holder.position = at
	holder.rotation.y = yaw
	if Cast.attach_hero(holder, id):
		var player: AnimationPlayer = holder.get_meta("animation_player")
		if player.has_animation(clip):
			player.play(clip)
	else:
		ball(Vector3(0, 0.9, 0), 0.35, OAK, false, holder)
	return holder


func cut(n: Node3D) -> Node3D:
	cutaway.append(n)
	return n


func view_add(name: String, eye: Vector3, at: Vector3, note: String, extra := {}) -> void:
	var v := {"name": name, "eye": eye, "at": at, "note": note}
	v.merge(extra, true)
	views.append(v)


func disc(at: Vector3, radius: float, c: Color) -> MeshInstance3D:
	var d := CylinderMesh.new()
	d.top_radius = radius
	d.bottom_radius = radius
	d.height = 0.02
	d.radial_segments = 48
	var n := kit.mesh(root, d, at, kit.translucent(c))
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func hoop(at: Vector3, radius: float, c: Color, count := 56) -> void:
	for i in count:
		var a := TAU * i / count
		var n := box(at + Vector3(cos(a) * radius, 0, sin(a) * radius), Vector3(0.12, 0.05, TAU * radius / count * 0.7), c, true)
		n.rotation.y = -a


func wedge(r0: float, r1: float, y: float, centre: float, half: float, c: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 16
	for i in steps:
		var a := centre - half + 2.0 * half * i / steps
		var b := centre - half + 2.0 * half * (i + 1) / steps
		var p := [Vector3(cos(a) * r0, y, sin(a) * r0), Vector3(cos(a) * r1, y, sin(a) * r1),
			Vector3(cos(b) * r1, y, sin(b) * r1), Vector3(cos(b) * r0, y, sin(b) * r0)]
		for k in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.add_vertex(p[k])
	var m := kit.translucent(c)
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var n := kit.mesh(root, st.commit(), Vector3.ZERO, m)
	n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func tint(holder: Node3D, c: Color, unshaded := false, metal := 0.0) -> void:
	for mesh: MeshInstance3D in holder.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.metallic = metal
		m.roughness = 0.4
		if c.a < 1.0:
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		if unshaded:
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material_override = m


func spot(at: Vector3, target: Vector3, energy: float, reach: float, angle: float, hue: Color, shadows := true) -> SpotLight3D:
	var l := SpotLight3D.new()
	l.light_color = hue
	l.light_energy = energy
	l.spot_range = reach
	l.spot_angle = angle
	l.shadow_enabled = shadows
	root.add_child(l)
	l.position = at
	l.look_at(target)
	return l


# ------------------------------------------------------------------ B01 · The Thirteenth Tread
const WHEEL := Vector3(30.0, 14.0, 0.0)
const PIVOT := Vector3(0.0, 20.6, 0.0)
const NUMERALS := ["I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X", "XI", "XII"]


func tread_point(angle: float) -> Vector3:
	# The wheel faces the nave (plane x = WHEEL.x). angle 0 = top; positive runs up the north (rising) face.
	return WHEEL + Vector3(0.0, cos(angle) * 12.0, -sin(angle) * 12.0)


func build_b01() -> void:
	world.environment.background_color = Color("10161c")
	world.environment.ambient_light_energy = 0.62
	# nave (x -30..18, 18 m wide) and wheel chamber (x 18..40, 32 m wide)
	box(Vector3(-6, -0.25, 0), Vector3(48, 0.5, 18.4), SHADE)
	box(Vector3(29, -0.25, 0), Vector3(22, 0.5, 32.4), SHADE.darkened(0.1))
	cut(box(Vector3(-6, 31.3, 0), Vector3(48, 0.6, 18.4), SHADE.darkened(0.3)))
	cut(box(Vector3(29, 31.3, 0), Vector3(22, 0.6, 32.4), SHADE.darkened(0.3)))
	box(Vector3(-6, 15.5, -9.4), Vector3(48, 31, 0.6), STONE)
	cut(box(Vector3(-6, 15.5, 9.4), Vector3(48, 31, 0.6), STONE))
	box(Vector3(29, 15.5, -16.4), Vector3(22, 31, 0.6), STONE.darkened(0.05))
	cut(box(Vector3(29, 15.5, 16.4), Vector3(22, 31, 0.6), STONE.darkened(0.05)))
	box(Vector3(18.3, 15.5, -12.85), Vector3(0.6, 31, 7.1), STONE.darkened(0.1))
	cut(box(Vector3(18.3, 15.5, 12.85), Vector3(0.6, 31, 7.1), STONE.darkened(0.1)))
	box(Vector3(40.3, 15.5, 0), Vector3(0.6, 31, 32.4), STONE.darkened(0.15))
	box(Vector3(-30.3, 15.5, 0), Vector3(0.6, 31, 18.4), STONE)
	for x in range(-26, 18, 8):
		box(Vector3(x, 15.5, -8.8), Vector3(1.2, 31, 0.8), PALE)
		cut(box(Vector3(x, 15.5, 8.8), Vector3(1.2, 31, 0.8), PALE))
		cut(box(Vector3(x, 30.6, 0), Vector3(1.0, 0.8, 18.4), PALE.darkened(0.15)))
	box(Vector3(18.3, 29.5, 0), Vector3(1.4, 3.0, 18.4), PALE.darkened(0.1))
	# west door and the Ivory plaque
	box(Vector3(-29.9, 3.0, 0), Vector3(0.4, 6.0, 4.0), Color("1a2228"))
	kit.arch(Vector3(-29.6, 6.2, 0), 4.2, 2.4, 0.4)
	box(Vector3(-29.85, 2.4, -4.2), Vector3(0.12, 2.2, 2.6), BRASS)
	plaque("NEVER STOP THE WHEEL\nKEEP YOUR COMPANION IN SIGHT\nDO NOT STAND ON THE RED TREAD\nIF THE HALL STRIKES THIRTEEN,\nDO NOT ANSWER",
		Vector3(-29.75, 2.4, -4.2), 0.16, Color("2a1d10"), PI * 0.5)

	# sweep path with the amplitude arc, push step, lag niches
	box(Vector3(0, 0.02, 0), Vector3(32.0, 0.04, 0.14), BRASS)
	for x in range(-16, 17):
		box(Vector3(x, 0.03, 0), Vector3(0.1, 0.05, 3.2 if x % 4 == 0 else 1.4), BRASS.darkened(0.2))
	box(Vector3(-17.2, 0.25, -2.2), Vector3(1.6, 0.5, 1.6), STONE)
	kit.drum(root, Vector3(-17.2, 0.55, -2.2), 0.7, 0.1, BRASS, true)
	plaque("PUSH STEP", Vector3(-17.2, 1.6, -2.2), 0.28, Color("e7d4b0"), 0.0, true)
	for x in [-12.0, -8.0, 0.0, 8.0, 12.0]:
		var n := Vector3(x, 0, 4.2)
		box(n + Vector3(0, 0.3, 0.5), Vector3(2.6, 0.6, 2.4), STONE.darkened(0.12))
		box(n + Vector3(-1.4, 1.9, 0.5), Vector3(0.3, 3.8, 2.4), PALE)
		box(n + Vector3(1.4, 1.9, 0.5), Vector3(0.3, 3.8, 2.4), PALE)
		box(n + Vector3(0, 3.95, 0.5), Vector3(3.1, 0.4, 2.6), PALE)
		plaque(str(int(x)), n + Vector3(0, 4.5, -0.75), 0.6, Color("e7d4b0"))
		lamp(n + Vector3(0, 3.2, 0.9), 0.6, 4.5)

	# pendulum, chaotic secondary arm and the lag field read as a cold floor ring and slowed dust
	box(PIVOT + Vector3(0, 1.4, 0), Vector3(3.2, 2.8, 3.2), IRON)
	var swing := deg_to_rad(24.0)
	var bob := PIVOT + Vector3(sin(swing), -cos(swing), 0) * 18.0
	rod(PIVOT, bob, 0.34, BRASS.darkened(0.2))
	ball(bob, 1.0, BRASS)
	var core := bob + Vector3(0.6, -1.2, 0.5)
	rod(bob, core, 0.12, IRON)
	ball(core, 0.34, Color("8fe3ee"), true)
	glass(core, 1.1, Color(0.6, 0.92, 0.98, 0.22))
	var ring_at := Vector3(core.x, 0.07, core.z)
	disc(ring_at, 6.6, Color(0.55, 0.86, 0.94, 0.14))
	hoop(ring_at, 6.6, Color("9fe8f2"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	for i in 160:
		var d := Vector3(rng.randf_range(-1, 1), rng.randf_range(-0.35, 1), rng.randf_range(-1, 1)) * Vector3(6.4, 3.2, 6.4)
		var at := Vector3(core.x, 1.6, core.z) + d
		if at.y > 0.15 and Vector2(d.x, d.z).length() < 6.4:
			box(at, Vector3.ONE * 0.06, Color("e4fbfa"), true)
	lamp(core, 2.2, 10.0, Color("9fe8f2"))

	# escape wheel facing the nave: rims, spokes, teeth, 13 level treads, hub dial
	var arbor := WHEEL + Vector3(0, 14.6, 0)
	for x in [WHEEL.x - 2.6, WHEEL.x + 2.6]:
		var off := Vector3(x - WHEEL.x, 0, 0)
		for i in 13:
			var a := TAU * i / 13.0
			var b := TAU * (i + 1) / 13.0
			rod(tread_point(a) + off, tread_point(b) + off, 0.6, BRASS)
			rod(WHEEL + off, tread_point(a) + off, 0.36, BRASS.darkened(0.25))
			rod(tread_point(a) + off, WHEEL + off + (tread_point(a + 0.12) - WHEEL) * 1.13, 0.46, BRASS.lightened(0.08))
	box(WHEEL, Vector3(6.4, 2.6, 2.6), IRON)
	var hub := kit.drum(root, WHEEL + Vector3(-3.3, 0, 0), 3.4, 0.2, PALE)
	hub.rotation.z = PI * 0.5
	for i in 13:
		var a := TAU * i / 13.0
		box(WHEEL + Vector3(-3.45, cos(a) * 2.9, -sin(a) * 2.9), Vector3(0.08, 0.5, 0.2), RED if i == 0 else IRON)
	rod(WHEEL + Vector3(-3.5, 0, 0), WHEEL + Vector3(-3.5, 2.7, 0), 0.2, RED)
	plaque("XIII", WHEEL + Vector3(-3.5, -1.4, 0), 1.2, Color("ff6a50"), -PI * 0.5)
	for i in 13:
		var pin := tread_point(TAU * i / 13.0)
		rod(pin + Vector3(-2.2, 0, 0), pin + Vector3(-2.2, -1.7, -1.2), 0.12, IRON)
		rod(pin + Vector3(-2.2, 0, 0), pin + Vector3(-2.2, -1.7, 1.2), 0.12, IRON)
		rod(pin + Vector3(2.2, 0, 0), pin + Vector3(2.2, -1.7, 0), 0.12, IRON)
		box(pin + Vector3(0, -1.75, 0), Vector3(4.6, 0.24, 3.0), RED if i == 0 else OAK)
		if i > 0:
			plaque(NUMERALS[i - 1], pin + Vector3(-2.45, -1.15, 0), 0.75, Color("efe2c4"), -PI * 0.5)
	# anchor with two pallet arms and the crutch across the vault to the pendulum pivot
	box(arbor, Vector3(6.0, 2.0, 2.2), IRON)
	for side in [-1.0, 1.0]:
		var tip := tread_point(side * deg_to_rad(52.0)) + Vector3(-3.4, 0, 0)
		rod(arbor + Vector3(-3.0, 0, 0), tip, 0.6, IRON.lightened(0.1))
		box(tip, Vector3(0.9, 1.0, 2.0), RED.darkened(0.35))
	rod(arbor + Vector3(-3.0, 0, 0), PIVOT + Vector3(0, 2.8, 0), 1.0, IRON)
	box(Vector3(WHEEL.x, -0.2, 0), Vector3(7.0, 0.45, 4.0), Color("161d22"))
	plaque("BOARDING SLOT", Vector3(WHEEL.x - 3.8, 0.9, -2.4), 0.36, Color("e7d4b0"), -PI * 0.5)

	# brake gallery north of the top tread (1.1 m gap), catwalk and service stair
	var deck_y := WHEEL.y + 12.0 - 1.75
	box(Vector3(WHEEL.x, deck_y - 0.3, -5.35), Vector3(6.0, 0.6, 5.5), STONE)
	box(Vector3(WHEEL.x, deck_y + 0.55, -8.05), Vector3(6.0, 1.1, 0.2), IRON)
	box(Vector3(WHEEL.x + 1.2, deck_y + 0.4, -4.0), Vector3(0.5, 0.8, 0.5), IRON)
	rod(Vector3(WHEEL.x + 1.2, deck_y + 0.8, -4.0), Vector3(WHEEL.x + 1.0, deck_y + 2.1, -3.5), 0.18, BRASS)
	plaque("WHEEL BRAKE · WATCH KEY", Vector3(WHEEL.x + 1.2, deck_y + 2.5, -4.0), 0.26, Color("ffd99e"), 0.0, true)
	box(Vector3(22.5, deck_y - 0.2, -7.4), Vector3(9.0, 0.4, 2.2), STONE.darkened(0.05))
	for i in 36:
		var x := -18.0 + i * 1.0
		box(Vector3(x, deck_y * float(i + 1) / 36.0 - 0.15, -7.6), Vector3(1.0, 0.3, 2.4), STONE.darkened(0.05))
	# Lantern turret behind the top tread (east), door facing the nave
	var turret := Vector3(WHEEL.x + 5.3, deck_y, 0)
	box(turret + Vector3(0, 3.0, 0), Vector3(4.0, 6.0, 5.0), PALE)
	box(turret + Vector3(-2.05, 1.45, 0), Vector3(0.2, 2.9, 2.0), Color("ffcf7a"), true)
	plaque("XIII", turret + Vector3(-2.1, 4.3, 0), 0.8, Color("ff6a50"), -PI * 0.5)
	plaque("THE LANTERN ADMITS TWO WHO ANSWER\nTHE THIRTEENTH HAND IN HAND", turret + Vector3(-2.1, 5.5, 0), 0.2, Color("2a1d10"), -PI * 0.5)
	spot(turret + Vector3(-2.4, 2.4, 0), turret + Vector3(-9.0, -2.0, 0), 7.0, 16.0, 45.0, Color("ffcf7a"))

	# hall dial on the nave's south wall, five beat pips
	var dial := kit.drum(root, Vector3(-20, 16.0, 8.95), 4.0, 0.2, Color("ece3cc"))
	dial.rotation.x = PI * 0.5
	for i in 12:
		var a := TAU * i / 12.0
		box(Vector3(-20 + sin(a) * 3.4, 16.0 + cos(a) * 3.4, 8.8), Vector3(0.28, 0.65, 0.1), IRON)
	rod(Vector3(-20, 16.0, 8.75), Vector3(-20 - sin(0.2) * 3.0, 16.0 + cos(0.2) * 3.0, 8.75), 0.2, IRON)
	for i in 5:
		ball(Vector3(-21.6 + i * 0.8, 11.4, 8.85), 0.22, Color("ffcf7a") if i < 3 else SHADE, i < 3)

	# people: Hale counting in niche 8 (inside the field), a pale lagshade in niche 0, the captain on the red tread
	person("hale", Vector3(8.0, 0.6, 4.0), PI)
	var shade := person("hale", Vector3(0.0, 0.6, 4.0), PI)
	tint(shade, Color(0.82, 0.9, 0.95, 0.42), true)
	person("detective", tread_point(0.0) + Vector3(0.6, -1.63, 0.4), PI * 0.5)
	plaque("\"…nine…\"  (slow)", Vector3(8.0, 2.8, 3.0), 0.3, Color("bff4ff"), 0.0, true)
	plaque("\"…ten.\"  (on the beat)", Vector3(0.0, 2.8, 3.0), 0.3, Color("ffffff"), 0.0, true)
	for x in [-24.0, -14.0, -4.0, 6.0]:
		lamp(Vector3(x, 10.0, -8.2), 2.4, 18.0)
		lamp(Vector3(x + 5.0, 10.0, 8.2), 1.8, 16.0)
	spot(Vector3(4.0, 22.0, 6.0), WHEEL + Vector3(-2.0, 2.0, 0), 9.0, 50.0, 28.0, Color("ffe4bd"))
	lamp(Vector3(34.0, 8.0, 10.0), 3.0, 22.0)
	lamp(Vector3(34.0, 8.0, -10.0), 3.0, 22.0)

	view_add("Entrance", Vector3(-28.8, 1.7, 2.2), Vector3(18.0, 10.5, -0.5),
		"West door: the pendulum sweeps the nave toward the cold lag ring; lag niches right; the escape wheel faces you at the end.", {"fov": 70.0})
	view_add("Lag niche", Vector3(-3.5, 1.7, -4.2), Vector3(7.0, 2.4, 4.0),
		"Hale counts slowly in niche 8 inside the field; the pale lagshade in niche 0 keeps the hall's beat.", {"fov": 70.0})
	lamp(Vector3(WHEEL.x - 2.0, deck_y + 5.0, -4.0), 3.2, 14.0)
	lamp(Vector3(WHEEL.x - 4.0, deck_y + 3.0, 3.0), 2.4, 12.0, Color("ffcf7a"))
	view_add("Thirteenth stroke", Vector3(WHEEL.x - 5.2, deck_y + 3.4, -7.0), Vector3(WHEEL.x + 2.0, deck_y + 0.4, 0.6),
		"From the brake gallery: the red tread has stopped at the top, the Lantern door is lit, the captain is across the gap.", {"fov": 72.0})
	var mid := Vector3(6.0, 11.0, 0.0)
	view_add("Section", mid + Vector3(-58.0, 52.0, 74.0), mid,
		"South walls and vault cut away: nave, niches and stair; the crutch arm ties the wheel's anchor to the pendulum.",
		{"ortho": true, "size": 58.0, "cut": true})


# ------------------------------------------------------------------ B02 · The Double Negative
func build_b02() -> void:
	world.environment.background_color = Color("07090b")
	world.environment.ambient_light_energy = 0.48
	for i in 48:
		var a := TAU * (i + 0.5) / 48.0
		var n := box(Vector3(cos(a) * 10.3, -0.25, sin(a) * 10.3), Vector3(10.6, 0.5, TAU * 15.6 / 48.0 + 0.05), SHADE.darkened(0.15))
		n.rotation.y = -a
	box(Vector3(0, -5.2, 0), Vector3(10, 0.4, 10), Color("1c2a26"))
	kit.drum(root, Vector3(0, -3.6, 0), 4.9, 0.05, Color("2f4a3e"))
	for i in 32:
		var a := TAU * (i + 0.5) / 32.0
		var n := box(Vector3(cos(a) * 5.1, -2.6, sin(a) * 5.1), Vector3(0.3, 5.2, 1.05), STONE.darkened(0.3))
		n.rotation.y = -a
	for i in 8:
		box(Vector3(-3.9, -0.35 - i * 0.6, -2.2 + i * 0.55), Vector3(1.4, 0.3, 0.7), STONE)
	for i in 40:
		var a := TAU * (i + 0.5) / 40.0
		if absf(wrapf(a - PI * 0.5, -PI, PI)) < 0.12: continue
		var n := box(Vector3(cos(a) * 15.9, 7.0, sin(a) * 15.9), Vector3(0.6, 14.5, 2.6), STONE.darkened(0.2))
		n.rotation.y = -a
		if sin(a) > 0.35: cut(n)
	cut(kit.drum(root, Vector3(0, 14.5, 0), 16.4, 0.4, SHADE.darkened(0.45)))
	box(Vector3(0, 2.6, 15.7), Vector3(3.0, 5.2, 0.3), Color("12181c"))
	kit.arch(Vector3(0, 5.3, 15.4), 3.2, 1.6, 0.35)
	# camera drum over the tank with its lens slit turned north
	kit.drum(root, Vector3(0, 9.0, 0), 2.6, 7.0, IRON)
	kit.drum(root, Vector3(0, 12.8, 0), 3.0, 0.6, BRASS)
	kit.drum(root, Vector3(0, 5.3, 0), 2.9, 0.4, BRASS)
	rod(Vector3(0, 13.0, 0), Vector3(0, 14.4, 0), 0.4, IRON)
	box(Vector3(0, 8.6, -2.62), Vector3(0.6, 3.6, 0.1), Color("ffe2a6"), true)
	# the band: one wedge on the ring floor, one on the tank floor, one panel on the far wall
	var band := Color(1.0, 0.82, 0.52, 0.20)
	wedge(5.2, 15.5, 0.04, -PI * 0.5, deg_to_rad(20.0), band)
	wedge(0.0, 4.8, -3.55, -PI * 0.5, deg_to_rad(20.0), band)
	sheet(Vector3(0, 6.5, -15.45), Vector3(10.8, 13.0, 0.04), Color(1.0, 0.82, 0.55, 0.12))
	spot(Vector3(0, 8.6, -2.8), Vector3(0, 1.0, -15.0), 10.0, 30.0, 22.0, Color("ffd598"))
	# upright lid on the near side; its inverted picture lies across the tank as the bridge
	var lid_frame := Node3D.new()
	root.add_child(lid_frame)
	lid_frame.position = Vector3(8.2, 0, 6.2)
	lid_frame.rotation.y = deg_to_rad(-52.0)
	var lid := kit.drum(lid_frame, Vector3(0, 4.6, 0), 4.4, 0.5, STONE)
	lid.rotation.x = PI * 0.5
	box(Vector3(-4.8, 2.2, 0.4), Vector3(0.5, 4.4, 0.5), IRON, false, lid_frame)
	box(Vector3(4.8, 2.2, 0.4), Vector3(0.5, 4.4, 0.5), IRON, false, lid_frame)
	rod(Vector3(-4.8, 4.4, 0.4), Vector3(4.8, 4.4, 0.4), 0.25, IRON, lid_frame)
	plaque("TANK LID (upright)", Vector3(8.2, 9.6, 6.2), 0.28, Color("e7d4b0"), 0.0, true)
	var picture := StandardMaterial3D.new()
	picture.albedo_color = Color(1.0, 0.86, 0.6, 0.5)
	picture.emission_enabled = true
	picture.emission = Color("ffcf86")
	picture.emission_energy_multiplier = 0.7
	picture.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var bridge := kit.mesh(root, BoxMesh.new(), Vector3(0, -0.05, -0.4), picture)
	bridge.scale = Vector3(3.4, 0.1, 10.4)
	plaque("PICTURE BRIDGE", Vector3(1.9, 0.6, -3.0), 0.3, Color("ffe1a8"), 0.0, true)
	var door := kit.mesh(root, BoxMesh.new(), Vector3(-3.4, 2.7, -15.35), picture)
	door.scale = Vector3(3.2, 5.4, 0.05)
	plaque("PICTURE DOOR", Vector3(-3.4, 6.0, -15.0), 0.3, Color("ffe1a8"), 0.0, true)
	# the real Hale's inverted image on the far wall; the negative leaves none
	var ink_mat := StandardMaterial3D.new()
	ink_mat.albedo_color = Color("2e1c10")
	ink_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var top := Vector3(1.6, 12.6, -15.25)   # inverted: feet up, head down
	for part in [[Vector3(-0.35, -1.5, 0), Vector3(0.42, 3.0, 0.04)], [Vector3(0.35, -1.5, 0), Vector3(0.42, 3.0, 0.04)],
			[Vector3(0, -4.2, 0), Vector3(1.4, 2.6, 0.04)], [Vector3(-0.95, -4.0, 0), Vector3(0.32, 2.4, 0.04)],
			[Vector3(0.95, -4.0, 0), Vector3(0.32, 2.4, 0.04)], [Vector3(0, -6.1, 0), Vector3(0.9, 1.0, 0.04)]]:
		var piece := kit.mesh(root, BoxMesh.new(), top + part[0], ink_mat)
		piece.scale = part[1]
	plaque("HALE'S IMAGE (inverted)", top + Vector3(0, 0.6, 0.2), 0.26, Color("ffe1a8"), 0.0, true)
	# winch on the far side, aperture step on the near rim
	box(Vector3(3.6, 0.6, -7.6), Vector3(1.2, 1.2, 1.2), IRON)
	var spool := kit.drum(root, Vector3(3.6, 1.4, -7.6), 0.5, 1.6, BRASS)
	spool.rotation.z = PI * 0.5
	plaque("LID WINCH", Vector3(3.6, 2.4, -7.6), 0.26, Color("e7d4b0"), 0.0, true)
	box(Vector3(-2.6, 0.3, 5.6), Vector3(1.2, 0.6, 1.2), STONE)
	kit.drum(root, Vector3(-2.6, 1.6, 5.6), 0.18, 1.8, BRASS)
	ball(Vector3(-2.6, 2.55, 5.6), 0.22, Color("ffe2a6"), true)
	plaque("NEVER LOOK INTO THE APERTURE", Vector3(-2.6, 3.2, 5.6), 0.22, Color("e7d4b0"), 0.0, true)
	for i in 8:
		var a := TAU * (i + 0.5) / 8.0
		var at := Vector3(cos(a) * 14.4, 2.6, sin(a) * 14.4)
		box(at + Vector3(0, -1.3, 0), Vector3(0.2, 2.6, 0.2), IRON)
		ball(at, 0.25, Color("ffbf6a"), true)
		lamp(at, 1.8, 8.0, Color("ffb866"), true)
	# two Hales: real one in the band, the negative (silvered here for the review) in lamplight
	person("hale", Vector3(-0.8, 0.0, -9.2), 0.0)
	var negative := person("hale", Vector3(6.8, 0.0, -11.0), -0.6)
	tint(negative, Color("c9d1d1"), false, 0.55)
	person("detective", Vector3(-1.8, 0.0, 10.2), PI)
	plaque("HALE · casts an image", Vector3(-0.8, 2.4, -9.2), 0.22, Color("ffe1a8"), 0.0, true)
	plaque("HALE? · no image", Vector3(6.8, 2.4, -11.0), 0.22, Color("dfe6e6"), 0.0, true)

	view_add("Entrance", Vector3(-1.2, 2.4, 14.2), Vector3(0.5, 3.0, -12.0),
		"From the door: the drum hangs over the fixing tank; the band lays a picture bridge to the far side. Two Hales wait there.")
	view_add("Aperture", Vector3(-2.6, 2.5, 5.0), Vector3(0.6, 4.2, -15.0),
		"Past the aperture: the far wall carries one inverted image. The figure in the lamplight has none.", {"fov": 64.0})
	view_add("Picture door", Vector3(-3.0, 1.7, -13.2), Vector3(0.0, 1.6, 8.0),
		"Looking back from the picture door: the bridge exists only inside the band; the upright lid projects it.")
	view_add("Plan", Vector3(0.0, 60.0, 0.0), Vector3(0.0, 0.0, 0.0),
		"Dome removed. Band pointed north; aperture and lid on the near side, winch on the far side, stair into the tank west.",
		{"ortho": true, "size": 36.0, "cut": true, "up": Vector3.FORWARD})


# ------------------------------------------------------------------ B03 · The Counter-Tide Cloister
func build_b03() -> void:
	world.environment.background_color = Color("0d1418")
	world.environment.ambient_light_energy = 0.58
	var water := 9.0
	var sill := 10.0
	box(Vector3(0, -4.3, 0), Vector3(38, 0.6, 38), SHADE.darkened(0.3))
	# outer walls
	box(Vector3(-19.0, 10.0, 0), Vector3(0.6, 28.6, 38.6), STONE.darkened(0.2))
	box(Vector3(19.0, 10.0, 0), Vector3(0.6, 28.6, 38.6), STONE.darkened(0.2))
	box(Vector3(0, 10.0, -19.0), Vector3(38.6, 28.6, 0.6), STONE.darkened(0.2))
	cut(box(Vector3(0, 10.0, 19.0), Vector3(38.6, 28.6, 0.6), STONE.darkened(0.2)))
	cut(box(Vector3(0, 24.0, 0), Vector3(38.6, 0.6, 38.6), SHADE.darkened(0.4)))
	# ranges on four sides: lower walk +1.5 (drowned now), upper arcade +12
	for side in 4:
		var holder := Node3D.new()
		root.add_child(holder)
		holder.rotation.y = side * PI * 0.5
		var parts: Array[Node3D] = []
		parts.append(box(Vector3(0, 1.2, 15.8), Vector3(37.8, 0.6, 5.8), STONE, false, holder))
		parts.append(box(Vector3(0, 11.75, 15.8), Vector3(37.8, 0.5, 5.8), STONE.darkened(0.05), false, holder))
		for i in 7:
			var x := -15.0 + i * 5.0
			parts.append(box(Vector3(x, 3.6, 12.9), Vector3(0.8, 4.8, 0.8), PALE, false, holder))
			parts.append(box(Vector3(x, 14.4, 12.9), Vector3(0.7, 5.0, 0.7), PALE, false, holder))
		parts.append(box(Vector3(0, 6.3, 12.9), Vector3(31, 0.6, 0.9), PALE.darkened(0.1), false, holder))
		parts.append(box(Vector3(0, 12.3, 12.9), Vector3(31, 0.5, 0.9), IRON, false, holder))
		parts.append(box(Vector3(0, 17.1, 12.9), Vector3(31, 0.6, 0.9), PALE.darkened(0.1), false, holder))
		if side == 0:
			for p in parts: cut(p)
	# south dead-end balcony at +6
	cut(box(Vector3(4.0, 5.75, 14.0), Vector3(10.0, 0.5, 2.6), STONE))
	plaque("BALCONY +6 · DEAD END", Vector3(4.0, 6.6, 12.8), 0.3, Color("e7d4b0"), 0.0, true)
	# water across the whole court at counter-tide
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color(0.18, 0.40, 0.42, 0.74)
	surface.roughness = 0.08
	surface.metallic = 0.2
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var pool := kit.mesh(root, BoxMesh.new(), Vector3(0, water - 0.05, 0), surface)
	pool.scale = Vector3(37.8, 0.1, 37.8)
	# east clerestory, the only exterior window; its sun patch lands on the bow tray
	box(Vector3(18.7, 18.5, 3.0), Vector3(0.2, 4.0, 5.0), Color("fff2cf"), true)
	spot(Vector3(18.4, 18.5, 3.0), Vector3(9.8, water + 0.6, 0.3), 16.0, 40.0, 9.0, Color("fff0cc"))
	# west exit at sill +10 with a short rope ladder
	box(Vector3(-17.6, sill - 0.2, 0), Vector3(2.2, 0.4, 3.8), STONE)
	box(Vector3(-18.65, sill + 2.0, 0), Vector3(0.2, 4.0, 3.0), Color("ffd892"), true)
	kit.arch(Vector3(-18.4, sill + 4.0, 0), 3.4, 1.6, 0.35)
	rod(Vector3(-16.5, sill, -0.6), Vector3(-16.4, sill - 0.55, -0.6), 0.05, OAK)
	rod(Vector3(-16.5, sill, 0.6), Vector3(-16.4, sill - 0.55, 0.6), 0.05, OAK)
	plaque("EXIT · SILL +10.0", Vector3(-17.4, sill + 4.8, 2.2), 0.34, Color("ffe1a8"), 0.0, true)
	# the barge: stern trimmed up 0.4 m by Hale's weight at the bow tray
	var barge := Node3D.new()
	root.add_child(barge)
	barge.position = Vector3(-2.6, water, 0.0)
	barge.rotation = Vector3(0, deg_to_rad(-5.0), -asin(0.8 / 26.0))
	box(Vector3(0, -0.6, 0), Vector3(26.0, 2.4, 6.0), OAK.darkened(0.3), false, barge)
	box(Vector3(0, 0.63, 0), Vector3(26.0, 0.1, 6.0), OAK, false, barge)
	box(Vector3(-1.0, 1.7, 0), Vector3(4.0, 2.2, 3.6), PALE.darkened(0.1), false, barge)
	box(Vector3(10.8, 0.95, 0), Vector3(1.8, 0.5, 2.4), BRASS, false, barge)
	box(Vector3(10.8, 1.22, 0), Vector3(1.0, 0.04, 0.8), Color("e9dcc0"), true, barge)
	for i in 10:
		box(Vector3(-11.5 + i * 2.6, 1.1, -2.9), Vector3(0.1, 0.9, 0.1), IRON, false, barge)
		box(Vector3(-11.5 + i * 2.6, 1.1, 2.9), Vector3(0.1, 0.9, 0.1), IRON, false, barge)
	kit.drum(barge, Vector3(-12.6, 0.4, 0), 0.5, 1.8, IRON)
	rod(Vector3(-15.4, water + 0.4, 0), Vector3(-18.6, water - 2.0, 0), 0.25, IRON)
	var hale := Node3D.new()
	barge.add_child(hale)
	hale.position = Vector3(9.6, 0.68, 1.2)
	hale.rotation.y = PI * 0.5
	Cast.attach_hero(hale, "hale")
	var captain := Node3D.new()
	barge.add_child(captain)
	captain.position = Vector3(-6.0, 0.68, -1.2)
	captain.rotation.y = -PI * 0.5
	Cast.attach_hero(captain, "detective")
	plaque("TRAY · WET PROOF DRYING", Vector3(8.0, water + 2.6, 0.5), 0.28, Color("ffe1a8"), 0.0, true)
	# siphons: roof cistern to court (east), court to sump over the south range
	box(Vector3(14.0, 26.0, -10.0), Vector3(6.0, 3.0, 6.0), IRON)
	var paths := [[Vector3(14.0, 25.0, -7.0), Vector3(14.0, 22.5, -7.0), Vector3(12.0, 22.5, -7.0), Vector3(12.0, water + 0.6, -7.0)],
		[Vector3(-7.0, water - 1.0, 11.5), Vector3(-7.0, 19.0, 11.5), Vector3(-7.0, 19.0, 21.0), Vector3(-7.0, 0.0, 21.0)]]
	for p in paths:
		for k in p.size() - 1:
			rod(p[k], p[k + 1], 0.8, BRASS.darkened(0.1))
		glass(p[1].lerp(p[2], 0.5), 0.6, Color(0.7, 0.95, 1.0, 0.4))
	disc(Vector3(12.0, water + 0.02, -7.0), 1.6, Color(0.9, 0.98, 1.0, 0.45))
	# north: Dry Archive sluice (raised), gauge glass with last overturn line
	box(Vector3(0, 15.0, -18.2), Vector3(6.0, 4.0, 0.5), IRON.darkened(0.1))
	rod(Vector3(-2.5, 17.0, -18.2), Vector3(-2.5, 23.0, -18.2), 0.12, IRON)
	rod(Vector3(2.5, 17.0, -18.2), Vector3(2.5, 23.0, -18.2), 0.12, IRON)
	plaque("DRY ARCHIVE SLUICE · NEVER OPEN", Vector3(0, 17.8, -17.6), 0.3, Color("e7d4b0"))
	box(Vector3(5.2, 15.0, -18.55), Vector3(0.6, 6.0, 0.25), Color(0.6, 0.85, 0.9), true)
	box(Vector3(5.2, 16.6, -18.35), Vector3(0.9, 0.08, 0.1), RED, true)
	plaque("ARCHIVE GAUGE", Vector3(5.2, 18.6, -17.9), 0.26, Color("e7d4b0"), 0.0, true)
	for x in [-12.0, 0.0, 12.0]:
		lamp(Vector3(x, 16.0, 16.0), 2.0, 16.0)
		lamp(Vector3(x, 16.0, -16.0), 2.0, 16.0)
		lamp(Vector3(-16.0, 16.0, x), 1.6, 14.0)
		lamp(Vector3(16.0, 16.0, x), 1.6, 14.0)

	view_add("Upper arcade", Vector3(-7.5, 13.7, 15.4), Vector3(3.0, 9.4, -2.0),
		"South-west corner, +12: the counter-tide has drowned the lower walks; sun from the east clerestory lands on the bow tray.", {"fov": 70.0})
	view_add("Sluice", Vector3(7.5, 13.7, 13.6), Vector3(-1.0, 11.5, -14.0),
		"Looking north across the drowned court to the raised Dry Archive sluice and gauge; the roof-cistern siphon pours in on the right.", {"fov": 70.0})
	view_add("Exit look-back", Vector3(-17.4, sill + 1.7, 0.9), Vector3(10.0, water + 0.6, 0.2),
		"From the exit sill: the stern rides level with the sill only while Hale holds the bow tray.", {"fov": 66.0})
	var court := Vector3(0.0, 7.0, 0.0)
	view_add("Section", court + Vector3(-50.0, 46.0, 64.0), court,
		"South range and roof cut away. Lower walk +1.5 under water at +9.0; balcony +6; upper arcade +12; exit sill +10.",
		{"ortho": true, "size": 54.0, "cut": true})

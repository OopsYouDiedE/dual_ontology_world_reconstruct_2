extends Node3D
## Optional architectural reference room. The seeded expedition remains the default.
const Shell := preload("res://scenes/blue_prince_lab/HallShell.gd")
const Banner := preload("res://scenes/blue_prince_lab/banner/Banner.tscn")
const Gears := preload("res://scenes/blue_prince_lab/gears/Gears.tscn")
const Lamp := preload("res://scenes/blue_prince_lab/lamp/Lamp.tscn")
const Door := preload("res://scenes/blue_prince_lab/doors/Door.tscn")
const Cabinet := preload("res://scenes/blue_prince_lab/doors/Cabinet.tscn")
const Stairs := preload("res://scenes/blue_prince_lab/stairs/Stairs.tscn")
const Helm := preload("res://scenes/blue_prince_lab/Helm.gd")
const VIEWS := ["Entrance", "Mechanisms", "Landing", "Airflow"]
const FRAMES := [Vector3(0.0, 1.65, 7.88), Vector3(-0.95, 1.69, -0.15), Vector3(0.20, 3.30, -7.32), Vector3(-0.02, 2.58, -1.48)]
const LOOK := [Vector3(0.0, 2.85, -6.0), Vector3(-3.6, 1.48, -0.62), Vector3(0.03, 2.94, -9.3), Vector3(-3.76, 2.65, -2.26)]
const EYE := 1.63
var walker := CharacterBody3D.new()
var walk_camera := Camera3D.new()
var shot_camera := Camera3D.new()
var active_view := 0
var portrait := false
var notice := Label.new()
var controls := HBoxContainer.new()
var hud := CanvasLayer.new()
var wind_sources: Array[Node3D] = []
var use_targets: Array[Dictionary] = []
var winds := false
var stairs: Node3D
var elapsed := 0.0
var door: Node3D
var cabinet: Node3D
var gears: Node3D
var helm: Node3D
var lamp: Node3D
var env: Environment

func _ready() -> void:
	name = "ArchitectureLab"
	add_child(Shell.new())
	_light_room()
	stairs = _place(Stairs, Vector3(0, 0, -4.23))
	door = _place(Door, Vector3(0, 1.65, -9.13))
	cabinet = _place(Cabinet, Vector3(-4.30, 0, 0.64), PI / 2.0)
	gears = _place(Gears, Vector3(-4.30, 0.83, -1.73), PI / 2.0)
	helm = Helm.new()
	helm.position = Vector3(0, 0.006, -0.50)
	add_child(helm)
	_register("Open or close the stair door", door, Vector3(0, 1.1, 0.24))
	_register("Open or close the cabinet", cabinet, Vector3(0, 0.86, 0.38))
	_register("Start or stop the gear train", gears, Vector3(0, 0.73, 0.36))
	_register("Turn the helm", helm, Vector3(0, 1.20, 0.26))
	for z: float in [4.60, -3.02]:
		var b := _place(Banner, Vector3(-4.36, 3.31, z), PI / 2.0)
		b.set("wall_setback", 0.12)
		wind_sources.append(b)
	lamp = _place(Lamp, Vector3(-2.65, 4.59, -1.25))
	wind_sources.append(lamp)
	for z: float in [6.25, 2.95, -0.35, -3.65, -6.95]:
		for side: float in [-1.0, 1.0]:
			_sconce(Vector3(side * 3.43, 2.86, z + 0.16), side, z != -0.35)
	_setup_cameras()
	_setup_hud()
	show_view(0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lab-components="):
			var capture := preload("res://scenes/blue_prince_lab/Blueprint.gd")
			capture.save_meshes({"Banners":wind_sources.slice(0, 2), "Oil Lamp":[lamp],
				"Gears":[gears], "Room Door":[door], "Cabinet":[cabinet],
				"Stairs":[stairs], "Helm":[helm]}, arg.trim_prefix("--lab-components="))

	var batching := preload("res://scenes/blue_prince_lab/MeshBatches.gd")
	for piece: Node3D in [door, cabinet, gears, helm, lamp]:
		batching.collapse(piece)

func _place(scene: PackedScene, p: Vector3, yaw := 0.0) -> Node3D:
	var node := scene.instantiate() as Node3D
	node.position = p
	node.rotation.y = yaw
	add_child(node)
	return node

func _register(title: String, target: Node3D, aim: Vector3) -> void:
	use_targets.append({"title": title, "node": target, "anchor": aim})

func _light_room() -> void:
	var world_environment := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("91a9bd")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b5c4e1")
	env.ambient_light_energy = 0.56
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 0.85
	env.ssao_intensity = 1.15
	env.sdfgi_enabled = "--lab-gi" in OS.get_cmdline_user_args()
	env.sdfgi_min_cell_size = 0.16
	env.sdfgi_use_occlusion = true
	env.glow_enabled = true
	env.glow_intensity = 0.24
	world_environment.environment = env
	add_child(world_environment)
	# This exterior sun reaches the interior through the east wall apertures.
	var day := DirectionalLight3D.new()
	day.rotation_degrees = Vector3(-24, 71, 0)
	day.light_color = Color("d6e6fa")
	day.light_energy = 1.12
	day.shadow_enabled = true
	day.directional_shadow_max_distance = 33.0
	add_child(day)
	# A permanent warm threshold lamp sets the destination value behind the stair.
	_omni(Vector3(0, 4.05, -8.22), Color("ffd29b"), 1.2, 5.25, true)
	_omni(Vector3(-3.3, 2.83, -1.0), Color("f9c991"), 0.53, 3.25, false)

func _omni(p: Vector3, tone: Color, energy: float, radius: float, shadows: bool) -> void:
	var light := OmniLight3D.new()
	light.position = p
	light.light_color = tone
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = shadows
	add_child(light)

func _sconce(p: Vector3, side: float, fills: bool) -> void:
	var iron := StandardMaterial3D.new()
	iron.albedo_color = Color("78674d")
	iron.roughness = 0.45
	iron.metallic = 0.52
	var arm := BoxMesh.new()
	arm.size = Vector3(0.28, 0.044, 0.047)
	_mesh(arm, iron, p - Vector3(side * 0.04, 0.12, 0.0))
	var base := CylinderMesh.new()
	base.top_radius = 0.11
	base.bottom_radius = 0.056
	base.height = 0.10
	base.radial_segments = 8
	_mesh(base, iron, p - Vector3(side * 0.17, 0.08, 0.0))
	var glass := CylinderMesh.new()
	glass.top_radius = 0.073
	glass.bottom_radius = 0.084
	glass.height = 0.26
	glass.radial_segments = 8
	var milk := StandardMaterial3D.new()
	milk.albedo_color = Color("ffe2ab")
	milk.emission_enabled = true
	milk.emission = Color("ffe0a2")
	milk.emission_energy_multiplier = 1.25
	var center := p - Vector3(side * 0.17, -0.08, 0.0)
	_mesh(glass, milk, center, false)
	var top := CylinderMesh.new()
	top.top_radius = 0.038
	top.bottom_radius = 0.092
	top.height = 0.074
	top.radial_segments = 8
	_mesh(top, iron, center + Vector3.UP * 0.159)
	if fills: _omni(center - Vector3(side * 0.22, 0.0, 0.0), Color("ffd6a3"), 0.72, 4.0, false)

func _mesh(mesh: Mesh, material: Material, pos: Vector3, shadows := true) -> void:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = material
	piece.position = pos
	if not shadows: piece.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	piece.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	add_child(piece)

func _setup_cameras() -> void:
	walker.position = Vector3(-0.35, 0.05, 7.77)
	walker.floor_snap_length = 0.24
	walker.floor_max_angle = deg_to_rad(49.0)
	walker.safe_margin = 0.003
	var shape := CapsuleShape3D.new()
	shape.height = 1.72
	shape.radius = 0.24
	var body := CollisionShape3D.new()
	body.shape = shape
	body.position.y = shape.height * 0.5
	walker.add_child(body)
	walk_camera.position.y = EYE
	walk_camera.fov = 67.0
	walk_camera.near = 0.06
	walker.add_child(walk_camera)
	add_child(walker)
	shot_camera.fov = 64.0
	shot_camera.near = 0.06
	add_child(shot_camera)

func _setup_hud() -> void:
	add_child(hud)
	hud.add_child(controls)
	controls.position = Vector2(16, 14)
	controls.add_theme_constant_override("separation", 8)
	for i in range(VIEWS.size()):
		_button(VIEWS[i], show_view.bind(i))
	_button("Walk", _walk)
	_button("Gust", func(): winds = not winds)
	_button("SDFGI", func(): env.sdfgi_enabled = not env.sdfgi_enabled)
	_button("Hide UI", _toggle_hud)
	notice.position = Vector2(16, 52)
	notice.add_theme_color_override("font_shadow_color", Color("161c26"))
	notice.add_theme_constant_override("shadow_outline_size", 4)
	hud.add_child(notice)

func _button(title: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	controls.add_child(button)

func show_view(index: int) -> void:
	active_view = index
	shot_camera.position = FRAMES[index]
	shot_camera.look_at(LOOK[index])
	shot_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _walk() -> void:
	active_view = -1
	walk_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _toggle_hud() -> void:
	portrait = not portrait
	hud.visible = not portrait

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_1: show_view(0)
			KEY_2: show_view(1)
			KEY_3: show_view(2)
			KEY_4: show_view(3)
			KEY_F: _walk() if active_view >= 0 else show_view(0)
			KEY_ESCAPE: show_view(0)
			KEY_H: _toggle_hud()
			KEY_G: winds = not winds
			KEY_E: _use(_select(get_viewport().get_visible_rect().size * 0.5, 2.5))
	if event is InputEventMouseMotion and active_view == -1:
		walker.rotation.y -= event.relative.x * 0.0024
		walk_camera.rotation.x = clampf(walk_camera.rotation.x - event.relative.y * 0.0024, -1.23, 1.23)
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var point: Vector2 = event.position if active_view >= 0 else get_viewport().get_visible_rect().size * 0.5
		_use(_select(point, 18.0 if active_view >= 0 else 2.5))

func _select(point: Vector2, max_range: float) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	var best := {}
	var radius := 76.0
	for target: Dictionary in use_targets:
		var p: Vector3 = target.node.to_global(target.anchor)
		if camera.is_position_behind(p) or camera.global_position.distance_to(p) > max_range: continue
		var d := camera.unproject_position(p).distance_to(point)
		if d < radius:
			best = target
			radius = d
	return best

func _use(target: Dictionary) -> void:
	if not target.is_empty(): target.node.interact()

func _physics_process(delta: float) -> void:
	elapsed += delta
	var wind := Vector3(6.0, 0.45, 2.1) * (1.0 + 0.30 * sin(elapsed * 3.1)) if winds else Vector3.ZERO
	for component in wind_sources:
		component.set_wind(wind)
	if active_view >= 0:
		notice.text = "THE ACADEMY   /   GRAND STAIR HALL     ·     Click a prop in the frame, or walk the hall."
		return
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var drive := walker.transform.basis * Vector3(input.x, 0, input.y)
	walker.velocity.x = drive.x * 3.3
	walker.velocity.z = drive.z * 3.3
	walker.velocity.y -= 16.0 * delta
	walker.move_and_slide()
	var target := _select(get_viewport().get_visible_rect().size / 2.0, 2.5)
	notice.text = "E  /  " + str(target.title) if not target.is_empty() else "WASD · Walk    /    Mouse · Look    /    Esc · Entrance"

func snapshot() -> Dictionary:
	var targets := []
	var buttons := {}
	for button: Control in controls.get_children():
		var center := button.get_global_rect().get_center()
		buttons[button.text] = [center.x, center.y]
	var camera := get_viewport().get_camera_3d()
	for t: Dictionary in use_targets:
		var p: Vector3 = t.node.to_global(t.anchor)
		if camera.is_position_behind(p): continue
		var point := camera.unproject_position(p)
		if get_viewport().get_visible_rect().has_point(point):
			targets.append({"name":t.title, "x":point.x, "y":point.y})
	return {"mode":"architecture_lab", "view":VIEWS[active_view] if active_view >= 0 else "Walk",
		"wind":winds, "sdfgi":env.sdfgi_enabled, "targets":targets, "buttons":buttons,
		"banner_deflection":wind_sources[1].tip_deflection(), "pendulum_radians":lamp.get_node("Pendulum").basis.get_rotation_quaternion().get_angle(),
		"gear_running":gears.get("is_running"), "gear_angle":gears.get("driver_angle"),
		"helm_angle":helm.get("angle"), "door_open":door.get("is_open"), "cabinet_open":cabinet.get("is_open"),
		"fps":Engine.get_frames_per_second(), "draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"player":[walker.position.x,walker.position.y,walker.position.z]}

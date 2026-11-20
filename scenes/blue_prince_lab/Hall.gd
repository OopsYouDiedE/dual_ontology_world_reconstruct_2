extends Node3D
## Optional architectural reference room. The seeded expedition remains the default.
const Shell := preload("res://scenes/blue_prince_lab/HallShell.gd")
const Banner := preload("res://scenes/blue_prince_lab/banner/Banner.tscn")
const Gears := preload("res://scenes/blue_prince_lab/gears/Gears.tscn")
const Lamp := preload("res://scenes/blue_prince_lab/lamp/Lamp.tscn")
const Door := preload("res://scenes/blue_prince_lab/doors/Door.tscn")
const Cabinet := preload("res://scenes/blue_prince_lab/doors/Cabinet.tscn")
const Stairs := preload("res://scenes/blue_prince_lab/stairs/Stairs.tscn")
const A26Exhibit := preload("res://scenes/blue_prince_lab/A26Exhibit.gd")
const Studies := preload("res://scenes/blue_prince_lab/studies/Studies.gd")
const STUDY_START := 5
const VIEWS := ["Entrance", "Mechanisms", "Landing", "Airflow", "A26 Exhibit"]
const FRAMES := [Vector3(0,1.07,7.88), Vector3(-0.95,1.69,-0.15), Vector3(0.20,2.10,-16.00),
	Vector3(-0.02,2.58,-1.48), Vector3(-1.30,1.88,1.85)]
const LOOK := [Vector3(0,5.35,-9.25), Vector3(-3.60,1.48,-0.62), Vector3(0.03,2.30,-21.40),
	Vector3(-3.76,2.65,-2.26), Vector3(0,1.36,-1.55)]
const EYE := 1.63
var walker := CharacterBody3D.new()
var walk_camera := Camera3D.new()
var shot_camera := Camera3D.new()
var active_view := 0
var portrait := false
var notice := Label.new()
var controls := HBoxContainer.new()
var study_controls := HBoxContainer.new()
var studies := Studies.new()
var hud := CanvasLayer.new()
var wind_sources: Array[Node3D] = []
var use_targets: Array[Dictionary] = []
var winds := false
var stairs: Node3D
var elapsed := 0.0
var door: Node3D
var cabinet: Node3D
var gears: Node3D
var hall_exhibit: A26Exhibit
var lamp: Node3D
var env: Environment
var ink: MeshInstance3D
var toon := true
var styled: Array[ShaderMaterial] = []
var decor: Node3D

func _ready() -> void:
	name = "ArchitectureLab"
	add_child(Shell.new())
	_light_room()
	stairs = _place(Stairs, Vector3(0, 0, -17.05))
	door = Door.instantiate()
	door.position = Vector3(0,0.015,-9.13)
	door.set("hall_finish", true)
	add_child(door)
	cabinet = _place(Cabinet, Vector3(-4.27,0,1.45), PI / 2.0)
	gears = _place(Gears, Vector3(-4.31,0.86,-1.92), PI / 2.0)
	if "--hall-a26-preview" in OS.get_cmdline_user_args():
		var exhibit := A26Exhibit.new()
		if exhibit.load_local():
			hall_exhibit = exhibit
			hall_exhibit.position = Vector3(0, 0.031, -1.55)
			add_child(hall_exhibit)
			_register("Inspect A26 assembly", hall_exhibit, Vector3(0, 1.32, 0.25))
		else:
			exhibit.free()
			push_warning("A26 exhibit unavailable; leaving the main axis clear.")
	_register("Open or close the hall door", door, Vector3(0, 1.1, 0.24))
	_register("Open or close the cabinet", cabinet, Vector3(0, 0.86, 0.38))
	_register("Start or stop the gear train", gears, Vector3(0, 0.73, 0.36))
	for z: float in [-5.78, -2.78]:
		var b := _place(Banner, Vector3(-4.36, 3.31, z), PI / 2.0)
		b.set("wall_setback", 0.12)
		wind_sources.append(b)
	lamp = _place(Lamp, Vector3(-2.65,4.52,-2.21))
	wind_sources.append(lamp)
	decor = preload("res://scenes/blue_prince_lab/HallDecor.gd").new()
	add_child(decor)
	add_child(studies)
	_collect_styled(self)
	styled.append_array(studies.finish_materials())
	_setup_ink()
	_setup_cameras()
	_setup_hud()
	show_view(0)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--lab-components="):
			var capture := preload("res://scenes/blue_prince_lab/Blueprint.gd")
			capture.save_meshes({"Banners":wind_sources.slice(0, 2), "Oil Lamp":[lamp],
				"Gears":[gears], "Room Door":[door], "Cabinet":[cabinet],
				"Stairs":[stairs], "Hall decor":[decor]}, arg.trim_prefix("--lab-components="))

	var batching := preload("res://scenes/blue_prince_lab/MeshBatches.gd")
	for piece: Node3D in [door, cabinet, gears, lamp, decor]:
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
	env.background_color = Color("8f9ba6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c5d2de")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 0.39
	env.ssao_intensity = 1.63
	env.ssao_power = 1.37
	env.sdfgi_enabled = "--lab-gi" in OS.get_cmdline_user_args()
	env.sdfgi_min_cell_size = 0.16
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = 0.67
	env.sdfgi_bounce_feedback = 0.28
	env.glow_enabled = true
	env.glow_intensity = 0.53
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, 0.27)
	env.set_glow_level(2, 0.58)
	env.set_glow_level(3, 0.75)
	env.set_glow_level(4, 0.42)
	env.set_glow_level(5, 0.13)
	env.glow_strength = 1.05
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.05
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.10
	env.adjustment_saturation = 0.95
	world_environment.environment = env
	add_child(world_environment)
	# This exterior sun reaches the interior through the east wall apertures.
	var day := DirectionalLight3D.new()
	day.rotation_degrees = Vector3(-8, 71, 0)
	day.light_color = Color("d6e6fa")
	day.light_energy = 0.21
	day.light_cull_mask = 1
	day.shadow_enabled = true
	day.directional_shadow_max_distance = 33.0
	add_child(day)
	# Long cool fills illuminate the stone without making a projected circle on the portal.
	_omni(Vector3(0,3.45,-4.10), Color("e0edff"), 0.76, 11.3, false, 0.69)
	_omni(Vector3(-1.9,3.75,6.15), Color("d6edff"), 0.69, 11.4, true, 1.14)
	_omni(Vector3(0,2.30,1.12), Color("f5dfba"), 0.37, 6.60, false, 1.22)
	for side: float in [-1.0, 1.0]:
		_omni(Vector3(side*2.24,3.32,-5.22), Color("dcecf9"), 0.53, 8.6, false, 0.85)
		_omni(Vector3(side*4.18,1.91,4.18), Color("ffca8f"), 0.27, 4.60, false, 1.13)
		_omni(Vector3(side*4.25,1.77,0.84), Color("ebbf91"), 0.15, 4.40, false, 1.18)
		_omni(Vector3(side*2.5,2.8,-15.0), Color("efd3ab"), 0.62, 5.65, false)
	_omni(Vector3(-0.7,2.58,-13.12), Color("ffecd2"), 1.5, 4.8, true)
	_omni(Vector3(0,3.77,-20.9), Color("e0e4df"), 0.75, 5.8, true)

func _collect_styled(n: Node) -> void:
	if n is MeshInstance3D and n.material_override is ShaderMaterial:
		var mat: ShaderMaterial = n.material_override
		if mat.shader.resource_path.get_file() in ["HallFinish.gdshader", "HallDoor.gdshader"] and not styled.has(mat):
			styled.append(mat)
	for child in n.get_children():
		_collect_styled(child)

func _toggle_toon() -> void:
	toon = not toon
	for mat in styled:
		mat.set_shader_parameter("toon_on",toon)

func _setup_ink() -> void:
	ink = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
	ink.mesh = quad
	ink.extra_cull_margin = 200.0
	ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ink.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scenes/blue_prince_lab/HallInk.gdshader")
	mat.render_priority = 100
	ink.material_override = mat
	add_child(ink)

func _omni(p: Vector3, tone: Color, energy: float, radius: float, shadows: bool, attenuation := 1.0) -> void:
	var light := OmniLight3D.new()
	light.position = p
	light.light_color = tone
	light.light_energy = energy
	light.omni_range = radius
	light.omni_attenuation = attenuation
	light.shadow_enabled = shadows
	add_child(light)

func _setup_cameras() -> void:
	walker.position = Vector3(-1.20 if hall_exhibit != null else -0.35, 0.05, 7.77)
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
	shot_camera.near = 0.06
	add_child(shot_camera)

func _setup_hud() -> void:
	add_child(hud)
	hud.add_child(controls)
	controls.position = Vector2(16, 14)
	controls.add_theme_constant_override("separation", 8)
	for i in range(VIEWS.size() if hall_exhibit != null else VIEWS.size()-1):
		_button(VIEWS[i], show_view.bind(i))
	_button("Walk", _walk)
	_button("Gust", func(): winds = not winds)
	_toggle_button("Toon", toon, _toggle_toon)
	_toggle_button("Ink", ink.visible, func(): ink.visible = not ink.visible)
	_toggle_button("Glow", env.glow_enabled, func(): env.glow_enabled = not env.glow_enabled)
	_toggle_button("SDFGI", env.sdfgi_enabled, func(): env.sdfgi_enabled = not env.sdfgi_enabled)
	_button("Hide UI", _toggle_hud)
	hud.add_child(study_controls)
	study_controls.position = Vector2(16, 48)
	study_controls.add_theme_constant_override("separation", 8)
	for i in Studies.VIEWS.size():
		_button(Studies.VIEWS[i], show_view.bind(STUDY_START + i), study_controls)
	notice.position = Vector2(16, 84)
	notice.add_theme_color_override("font_shadow_color", Color("161c26"))
	notice.add_theme_constant_override("shadow_outline_size", 4)
	hud.add_child(notice)

func _button(title: String, callback: Callable, row: HBoxContainer = null) -> void:
	var button := Button.new()
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	(controls if row == null else row).add_child(button)

func _toggle_button(title: String, enabled: bool, callback: Callable) -> void:
	var button := Button.new()
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.button_pressed = enabled
	button.pressed.connect(callback)
	controls.add_child(button)

func show_view(index: int) -> void:
	active_view = index
	if index >= STUDY_START:
		var shot := index - STUDY_START
		studies.show_study(shot)
		shot_camera.fov = Studies.FOV[shot]
		shot_camera.position = Studies.ORIGIN + Studies.CAMERA[shot]
		shot_camera.look_at(Studies.ORIGIN + Studies.FOCUS[shot])
	else:
		studies.clear()
		shot_camera.fov = 68.0 if index == 0 else 64.0
		shot_camera.position = FRAMES[index]
		shot_camera.look_at(LOOK[index])
	shot_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _walk() -> void:
	studies.clear()
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
			KEY_6:
				if hall_exhibit != null: show_view(4)
			KEY_7: show_view(STUDY_START + Studies.Shot.SERVICE)
			KEY_8: show_view(STUDY_START + Studies.Shot.ANOMALY)
			KEY_9: show_view(STUDY_START + Studies.Shot.ARCHIVE)
			KEY_0: show_view(STUDY_START + Studies.Shot.LEDGER)
			KEY_5: show_view(STUDY_START + Studies.Shot.MERIDIAN)
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
		if active_view == STUDY_START + Studies.Shot.MERIDIAN:
			if point.distance_to(_study_target()) < 165.0:
				studies.meridian.interact()
		elif active_view == STUDY_START + Studies.Shot.ARCHIVE:
			if point.distance_to(_study_target()) < 40.0:
				show_view(STUDY_START + Studies.Shot.LEDGER)
		elif active_view < STUDY_START:
			_use(_select(point, 18.0 if active_view >= 0 else 2.5))

func _study_target() -> Vector2:
	if active_view == STUDY_START + Studies.Shot.MERIDIAN:
		return shot_camera.unproject_position(studies.meridian.global_position)
	return shot_camera.unproject_position(Studies.ORIGIN + Vector3(0.10, 1.05, -1.44))

func _select(point: Vector2, max_range: float) -> Dictionary:
	var camera := get_viewport().get_camera_3d()
	var best := {}
	var radius := 64.0
	for target: Dictionary in use_targets:
		if not _in_zone(target): continue
		var p: Vector3 = target.node.to_global(target.anchor)
		if camera.is_position_behind(p) or camera.global_position.distance_to(p) > max_range: continue
		var d := camera.unproject_position(p).distance_to(point)
		if d < radius:
			best = target
			radius = d
	return best

func _in_zone(target: Dictionary) -> bool:
	if active_view >= STUDY_START: return false
	if target.node == hall_exhibit:
		return active_view in [0, 4] or (active_view == -1 and walker.position.z >= -9.3)
	if target.node != door and (active_view == 2 or (active_view == -1 and walker.position.z < -9.3)):
		return false
	return true

func _use(target: Dictionary) -> void:
	if not target.is_empty(): target.node.interact()

func _physics_process(delta: float) -> void:
	elapsed += delta
	var wind := Vector3(6.0, 0.45, 2.1) * (1.0 + 0.30 * sin(elapsed * 3.1)) if winds else Vector3.ZERO
	for component in wind_sources:
		component.set_wind(wind)
	if active_view >= STUDY_START:
		notice.text = ["SERVICE STAIRS   /   BASELINE", "SERVICE STAIRS   /   ANOMALY",
			"ACADEMY RECORDS   /   Click the ledger to read it.", "EVIDENCE   /   NIGHT REGISTER",
			"MERIDIAN 03   /   Click the mechanism to start or stop all three axes."][active_view - STUDY_START]
		return
	if active_view == 4:
		notice.text = "A26 / TRIAXIAL TOURBILLON MODEL II   ·   Click to separate or gather the original printed parts.   ·   CC BY-NC"
		return
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
	for button: Control in controls.get_children() + study_controls.get_children():
		var center := button.get_global_rect().get_center()
		buttons[button.text] = [center.x, center.y]
	var camera := get_viewport().get_camera_3d()
	for t: Dictionary in use_targets:
		if not _in_zone(t): continue
		var p: Vector3 = t.node.to_global(t.anchor)
		if camera.is_position_behind(p): continue
		var point := camera.unproject_position(p)
		if get_viewport().get_visible_rect().has_point(point):
			targets.append({"name":t.title, "x":point.x, "y":point.y})
	var landmarks := {}
	if active_view == 0:
		var frame_points := {"threshold":Vector3(0,0,-9.13),
			"runner_far_left":Vector3(-1.17,0.03,-9.13), "first_pendant":Vector3(-2.56,4.64,3.21),
			"near_column_base":Vector3(-3.43,0.14,3.0), "first_bust_crown":Vector3(-3.90,2.55,4)}
		var viewport := get_viewport().get_visible_rect().size
		for key in frame_points:
			var pixel := camera.unproject_position(frame_points[key]) / viewport
			landmarks[key] = [pixel.x, pixel.y]
	var shot := {
		"position": _axes(camera.global_position), "rotation": _axes(camera.global_rotation), "fov": camera.fov}
	var mechanism := studies.meridian.mesh_stats()
	mechanism["triangle_budget"] = studies.meridian.TRIANGLE_BUDGET
	mechanism["surface_budget"] = studies.meridian.SURFACE_BUDGET
	mechanism["running"] = studies.meridian.running
	mechanism["angles"] = _axes(studies.meridian.angles)
	if active_view in [STUDY_START + Studies.Shot.ARCHIVE, STUDY_START + Studies.Shot.MERIDIAN]:
		var point := _study_target()
		var title := "Read Night Register" if active_view == STUDY_START + Studies.Shot.ARCHIVE else "Start or stop Meridian"
		targets.append({"name": title, "x": point.x, "y": point.y})
	return {"mode":"architecture_lab", "entrance_landmarks":landmarks, "view":_view_name(),
		"shot":shot, "hud_visible":hud.visible, "meridian":mechanism,
		"stair_flight":("up" if studies.up_flight.visible else "down") if active_view in [STUDY_START, STUDY_START + Studies.Shot.ANOMALY] else "",
		"wind":winds, "toon":toon, "ink":ink.visible, "glow":env.glow_enabled, "sdfgi":env.sdfgi_enabled, "targets":targets, "buttons":buttons,
		"banner_deflection":wind_sources[1].tip_deflection(), "pendulum_radians":lamp.get_node("Pendulum").basis.get_rotation_quaternion().get_angle(),
		"gear_running":gears.get("is_running"), "gear_angle":gears.get("driver_angle"),
		"exhibit_parts":hall_exhibit.parts.size() if hall_exhibit != null else 0,
		"exhibit_exploded":hall_exhibit.exploded if hall_exhibit != null else false,
		"exhibit_blend":hall_exhibit.blend if hall_exhibit != null else 0.0,
		"door_open":door.get("is_open"), "cabinet_open":cabinet.get("is_open"),
		"fps":Engine.get_frames_per_second(), "draw_calls":RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"player":[walker.position.x,walker.position.y,walker.position.z]}

func _view_name() -> String:
	if active_view >= STUDY_START: return Studies.VIEWS[active_view - STUDY_START]
	return VIEWS[active_view] if active_view >= 0 else "Walk"

func _axes(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

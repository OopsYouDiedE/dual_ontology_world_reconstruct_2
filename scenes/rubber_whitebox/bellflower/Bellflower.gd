extends Node3D
## Build a visible, collision-bearing room from the same hulls the referee scans.

const WORKER := "res://scenes/rubber_whitebox/bellflower/bridge.py"
const SCALE_MM := 0.001
var _pipe: FileAccess
var _groups := {}
var _materials := {}
var _camera: Camera3D
var _env: Environment
var _rays: MeshInstance3D
var _hud: Label
var _radar: Label
var _capture_layer: CanvasLayer
var _hit_marks: Node3D
var _strike: AudioStreamPlayer
var _state := {}
var _options := {}
var _show_rays := false
var _auto := false
var _capture := false
var _pending := ""
var _was_ring := false
var _look_pitch := 0.0


func _ready() -> void:
	Engine.physics_ticks_per_second = 60
	for action in [&"bellflower_rays", &"bellflower_remove", &"bellflower_reference", &"bellflower_reset"]:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		_options[kv[0]] = kv[1] if kv.size() == 2 else true
	var exe := str(_options.get("python", "python"))
	var args := PackedStringArray(["-u", ProjectSettings.globalize_path(WORKER), "--seed", str(_options.get("seed", _options.get("run-seed", 1)))])
	if _options.has("strong"):
		args.append("--strong")
	var handle := OS.execute_with_pipe(exe, args, true)
	if handle.is_empty():
		_fail("Cannot launch Python. Supply --python=C:/path/to/python.exe")
		return
	_pipe = handle.stdio
	var first := _receive()
	if not first.has("init"):
		_fail("No geometry received from the Bellflower worker.")
		return
	_build(first.init)
	_apply(first.state)
	if _options.has("capture"):
		_capture = true
		_take_views(str(_options.capture))
	elif _options.has("auto") or _options.has("smoke"):
		_auto = true


func _fail(message: String) -> void:
	push_error(message)
	get_tree().quit(1)


func _exit_tree() -> void:
	if _pipe != null and _pipe.is_open():
		_pipe.store_line('{"op":"quit"}')
		_pipe.flush()
		_pipe.close()


func _receive() -> Dictionary:
	var data: Variant = JSON.parse_string(_pipe.get_line())
	if data is Dictionary and not data.has("error"):
		return data
	_fail("Invalid worker reply: %s" % str(data))
	return {}


func _send(packet: Dictionary) -> Dictionary:
	_pipe.store_line(JSON.stringify(packet))
	_pipe.flush()
	return _receive()


func _vec(a: Array, scale_factor: float = SCALE_MM) -> Vector3:
	return Vector3(float(a[0]), float(a[1]), float(a[2])) * scale_factor


func _build(packet: Dictionary) -> void:
	var env := Environment.new()
	_env = env
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("19212f")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("93a5bc")
	env.ambient_light_energy = 0.39
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.fog_enabled = true
	env.fog_light_color = Color("394658")
	env.fog_light_energy = 0.40
	env.fog_density = 0.0071
	env.fog_sky_affect = 0.5
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)
	for source in packet.lights:
		var lamp := SpotLight3D.new()
		lamp.position = _vec(source.p)
		lamp.spot_range = float(source.r) * SCALE_MM
		lamp.spot_angle = float(source.angle)
		lamp.spot_angle_attenuation = 0.72
		lamp.spot_attenuation = 0.72
		lamp.light_energy = float(source.energy)
		lamp.light_specular = 0.19
		lamp.light_color = Color(str(source.color))
		lamp.shadow_enabled = true
		lamp.shadow_bias = 0.15
		lamp.shadow_normal_bias = 0.95
		lamp.shadow_blur = 0.80
		add_child(lamp)
		lamp.look_at(_vec(source.aim))
	for part in packet.meshes:
		_build_part(part)
	_camera = Camera3D.new()
	_camera.fov = 77.0
	_camera.far = 84.0
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.cull_mask = 1
	_camera.current = true
	add_child(_camera)
	_hit_marks = Node3D.new()
	add_child(_hit_marks)
	_rays = MeshInstance3D.new()
	_rays.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rays)
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(22, 16)
	_hud.add_theme_font_size_override("font_size", 16)
	_hud.add_theme_color_override("font_shadow_color", Color.BLACK)
	_hud.add_theme_constant_override("shadow_offset_x", 2)
	_hud.add_theme_constant_override("shadow_offset_y", 2)
	layer.add_child(_hud)
	_radar = Label.new()
	_radar.position = Vector2(24, 124)
	_radar.add_theme_font_size_override("font_size", 17)
	_radar.add_theme_color_override("font_color", Color("92e0c4"))
	_radar.add_theme_color_override("font_shadow_color", Color.BLACK)
	_radar.add_theme_constant_override("shadow_offset_x", 2)
	_radar.add_theme_constant_override("shadow_offset_y", 2)
	_radar.hide()
	layer.add_child(_radar)
	_capture_layer = CanvasLayer.new()
	add_child(_capture_layer)
	_build_strike()


func _build_part(part: Dictionary) -> void:
	var g := str(part.group)
	if not _groups.has(g):
		var body := StaticBody3D.new()
		body.name = g.replace(":", "_")
		add_child(body)
		_groups[g] = body
	var verts := PackedVector3Array()
	for v in part.v:
		verts.append(_vec(v))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Turned bronze and the tapered spiral tubes have smoothly lit facets.
	surface.set_smooth_group(-1)
	# Python hulls are CCW; Godot renders front faces clockwise.
	var rounded: bool = part.has("smooth")
	for triangle in part.tri:
		var a := int(triangle[0])
		var b := int(triangle[1])
		var c := int(triangle[2])
		var face_normal := (verts[b] - verts[a]).cross(verts[c] - verts[a]).normalized()
		var half_ring := verts.size() / 2.0
		var cap: bool = max(a,b,c) < half_ring or min(a,b,c) >= half_ring
		for index in [a,c,b]:
			surface.set_normal(_vec(part.smooth[index], 1.0) if rounded and not cap else face_normal)
			surface.add_vertex(verts[index])
	var mesh := surface.commit()
	var vis := MeshInstance3D.new()
	vis.mesh = mesh
	if g == "actor0":
		vis.layers = 2
	var finish := str(part.finish)
	if not _materials.has(finish):
		var paint := StandardMaterial3D.new()
		paint.albedo_color = Color(part.color[0], part.color[1], part.color[2])
		paint.metallic = 0.0
		paint.roughness = 0.91
		paint.metallic_specular = 0.28
		if finish in ["black", "steel"]:
			paint.metallic = 0.60
			paint.roughness = 0.65
		elif finish == "tube":
			paint.metallic = 0.26
			paint.roughness = 0.76
		elif finish in ["brass", "bronze_edge", "rim"]:
			paint.metallic = 0.75
			paint.roughness = 0.45
		elif finish == "red":
			paint.roughness = 0.80
		_materials[finish] = paint
	vis.material_override = _materials[finish]
	_groups[g].add_child(vis)
	# Convex shape uses the visible solid's actual vertices. No proxy mesh or invisible box.
	var shape := ConvexPolygonShape3D.new()
	shape.points = verts
	shape.margin = 0.0
	var collider := CollisionShape3D.new()
	collider.shape = shape
	_groups[g].add_child(collider)


func _build_strike() -> void:
	var sound := AudioStreamWAV.new()
	sound.format = AudioStreamWAV.FORMAT_16_BITS
	sound.mix_rate = 22050
	var samples := PackedByteArray()
	samples.resize(22050 * 2)
	for i in range(22050):
		var t := i / 22050.0
		var value := sin(TAU * 239.0 * t) * exp(-3.4 * t) + 0.44 * sin(TAU * 583.0 * t) * exp(-8.0 * t) + 0.23 * sin(TAU * 869.0 * t) * exp(-14.0 * t)
		samples.encode_s16(2 * i, int(value * 7200.0 * minf(1.0, t * 290.0)))
	sound.data = samples
	_strike = AudioStreamPlayer.new()
	_strike.stream = sound
	add_child(_strike)


func _apply(state: Dictionary) -> void:
	if state.is_empty():
		return
	_state = state
	for id in _groups:
		var part: StaticBody3D = _groups[id]
		var section: bool = state.get("camera", {}).get("cutaway", false) and id.begins_with("section_")
		var present: bool = state.poses.has(id)
		part.visible = present and not section
		part.collision_layer = int(present)
		if present:
			var p: Array = state.poses[id]
			part.transform = Transform3D(Basis(_vec(p[1], 1), _vec(p[2], 1), _vec(p[3], 1)), _vec(p[0]))
	if state.has("camera"):
		_camera.position = _vec(state.camera.p_mm)
		_camera.projection = Camera3D.PROJECTION_ORTHOGONAL if state.camera.has("ortho") else Camera3D.PROJECTION_PERSPECTIVE
		if state.camera.has("ortho"):
			_camera.size = float(state.camera.ortho)
		else:
			_camera.fov = float(state.camera.get("fov", 77.0))
		_camera.look_at(_vec(state.camera.target_mm))
	else:
		_camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		_camera.position = _vec(state.eye)
		_camera.rotation = Vector3(_look_pitch, -deg_to_rad(state.yaw), 0)
	if state.ring and not _was_ring and not _capture:
		_strike.play()
	_was_ring = state.ring
	if _show_rays and not _capture:
		_draw_rays()
	if not _capture:
		_hud.text = "03   /   THE BELLFLOWER\n%04d   ·   %s   ·   %s\nW/S Leader  ·  ↑/↓ Mate  ·  Q/E Turn  ·  PgUp/PgDn Look\nF Recruit  ·  P Persuade  ·  T Reference AI  ·  V Rays  ·  H Remove  ·  R Reset" % [int(state.tick), state.result.to_upper(), "DIAGNOSTIC" if state.get("diagnostic", state.hidden) else ("PARTNER JOINED" if state.joined else "PARTNER WAITING")]
		_hud.text += "\nManual: Keep the plate held until all are across."
		if state.reply != "":
			_hud.text += "\n" + state.reply


func _draw_rays() -> void:
	for mark in _hit_marks.get_children():
		mark.queue_free()
	var mesh := ImmediateMesh.new()
	var paint := StandardMaterial3D.new()
	paint.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	paint.vertex_color_use_as_albedo = true
	paint.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var bright := StandardMaterial3D.new()
	bright.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bright.albedo_color = Color("f5df88")
	var eye := _vec(_state.scan_eye)
	mesh.surface_begin(Mesh.PRIMITIVE_LINES, paint)
	for beam in _state.beams:
		var target := _vec(beam[0])
		var on_bell: bool = beam.size() > 2 and beam[2] == "device" and int(beam[1]) == 2
		var color: Color = [Color(0.68, 0.75, 0.87, 0.28), Color(0.70, 0.48, 0.43, 0.42), Color(0.48, 0.90, 0.85, 0.84)][int(beam[1])]
		if on_bell:
			color = Color("ffe797")
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(eye.lerp(target, 0.05))
		mesh.surface_set_color(color)
		mesh.surface_add_vertex(target)
		if on_bell:
			var marker := MeshInstance3D.new()
			var dot := SphereMesh.new()
			dot.radius = 0.065
			dot.height = 0.13
			marker.mesh = dot
			marker.position = target.lerp(eye, 0.006)
			marker.material_override = bright
			marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			_hit_marks.add_child(marker)
	mesh.surface_end()
	_rays.mesh = mesh
	var grid := "27 RAYS  /  3 Hz\n"
	for k in range(_state.beams.size()):
		if k > 0 and k % 9 == 0:
			grid += "\n"
		var beam: Array = _state.beams[k]
		var on_bell: bool = beam.size() > 2 and beam[2] == "device" and int(beam[1]) == 2
		grid += "◆  " if on_bell else ["·  ", "×  ", "●  "][int(beam[1])]
	_radar.text = grid + "\n◆ bell    ● lit    × dark    · miss"


func _toggle_rays() -> void:
	_show_rays = not _show_rays
	_rays.visible = _show_rays
	_radar.visible = _show_rays
	_hit_marks.visible = _show_rays
	if _show_rays and not _state.is_empty():
		_draw_rays()


func _toggle_reference() -> void:
	_auto = not _auto
	_pending = "reset"


func _input(event: InputEvent) -> void:
	if _capture or _pipe == null:
		return
	if event.is_action_pressed(&"bellflower_rays"):
		_toggle_rays()
	elif event.is_action_pressed(&"bellflower_remove"):
		_pending = "hide"
	elif event.is_action_pressed(&"bellflower_reference"):
		_toggle_reference()
	elif event.is_action_pressed(&"bellflower_reset"):
		_pending = "reset"


func _unhandled_key_input(event: InputEvent) -> void:
	if _capture or not event.pressed or event.echo:
		return
	match event.physical_keycode:
		KEY_V: _toggle_rays()
		KEY_H: _pending = "hide"
		KEY_R: _pending = "reset"
		KEY_T: _toggle_reference()
		KEY_ESCAPE: get_tree().quit()


func _physics_process(_delta: float) -> void:
	if _capture or _pipe == null or _state.is_empty():
		return
	if _pending != "":
		_apply(_send({"op":_pending}))
		_pending = ""
		return
	if _state.result != "running":
		if _options.has("smoke"):
			print("Bellflower replay: ",_state.result," tick=",_state.tick)
			get_tree().quit(0 if _state.result == "win" else 2)
		return
	var lead := int(Input.is_physical_key_pressed(KEY_W)) - int(Input.is_physical_key_pressed(KEY_S))
	var mate := int(Input.is_physical_key_pressed(KEY_UP)) - int(Input.is_physical_key_pressed(KEY_DOWN))
	var turn := int(Input.is_physical_key_pressed(KEY_E)) - int(Input.is_physical_key_pressed(KEY_Q))
	_look_pitch = clampf(_look_pitch + 0.022 * (int(Input.is_physical_key_pressed(KEY_PAGEUP)) - int(Input.is_physical_key_pressed(KEY_PAGEDOWN))), -0.7, 0.9)
	_apply(_send({"op":"step", "auto":_auto, "move":[lead,mate], "turn":turn, "join":Input.is_physical_key_pressed(KEY_F), "persuade":Input.is_physical_key_pressed(KEY_P)}))


func _caption(text: String, at: Vector2, font_size: int = 17) -> void:
	var label := Label.new()
	label.position = at
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("e7dfca"))
	label.add_theme_color_override("font_shadow_color", Color("101620"))
	label.add_theme_constant_override("shadow_offset_x", 2)
	label.add_theme_constant_override("shadow_offset_y", 2)
	_capture_layer.add_child(label)


func _callout(text: String, at: Vector3, offset: Vector2) -> void:
	var anchor := _camera.unproject_position(at)
	var elbow := anchor + offset
	var lead := Line2D.new()
	lead.add_point(anchor)
	lead.add_point(elbow)
	lead.width = 1.1
	lead.default_color = Color("d8bea0")
	lead.antialiased = true
	_capture_layer.add_child(lead)
	_caption(text, elbow + Vector2(4,-19))


func _take_views(dir: String) -> void:
	var target := ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(target)
	_hud.hide()
	for view in ["A-hall", "B-entry", "C-under-bells", "D-ray-scan"]:
		_apply(_send({"op":"preview", "view":view, "phase":"pinch"}))
		for node in _capture_layer.get_children():
			node.queue_free()
		var overlay: bool = _state.camera.get("rays", false)
		_rays.visible = overlay
		_radar.visible = overlay
		_hit_marks.visible = overlay
		if overlay:
			_radar.position = Vector2(32, 29)
			_draw_rays()
		_env.ambient_light_energy = 0.73 if view == "A-hall" else 0.39
		_env.background_color = Color("303943") if view == "A-hall" else Color("19212f")
		if view == "A-hall":
			_caption("03   /   THE BELLFLOWER
HALL SECTION  ·  18.4 × 21.8 m", Vector2(39, 25), 21)
			_callout("ENTRY", Vector3(0,0,6.3), Vector2(48,47))
			_callout("OBSERVATION BAY", Vector3(-8.1,0.22,0.47), Vector2(-124,-24))
			_callout("PRESSURE PLATE", Vector3(0.68,0.05,-0.76), Vector2(104,38))
			_callout("RETURN CATCH", Vector3(-2.26,1.99,-2.05), Vector2(-164,23))
			_callout("LOW BELL SWEEP", Vector3(0,1.45,-2.80), Vector2(125,18))
			_callout("EXIT", Vector3(0,1.65,-10.02), Vector2(74,-31))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var path := target.path_join(str(view) + ".png")
		var err := get_viewport().get_texture().get_image().save_png(path)
		if err != OK:
			_fail("Could not save " + path)
			return
		print(path)
	get_tree().quit()


func mcp_observe() -> Dictionary:
	if _state.is_empty():
		return {}
	return {"tick": _state.tick, "eye_mm": _state.eye, "result": _state.result,
		"joined": _state.joined, "ring": _state.ring, "pinch": _state.pinch,
		"hidden": _state.hidden, "diagnostic": _state.get("diagnostic", false), "ray_count": _state.beams.size(), "ray_overlay": _show_rays}

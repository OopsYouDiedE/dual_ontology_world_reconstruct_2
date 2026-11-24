extends SceneTree
const R = preload("res://scenes/physics_lab/evidence_register/RegisterRules.gd")
const SCENE = preload("res://scenes/physics_lab/evidence_register/EvidenceRegister.tscn")
const REPLAY := "res://tools/evidence_register/golden.json"
var failures := 0
var checks := 0
var capture := OS.get_cmdline_user_args().has("--register-images")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var replay: Variant = JSON.parse_string(FileAccess.get_file_as_string(REPLAY))
	if not replay is Dictionary or not replay.has("cases"):
		printerr("Missing replay cases: " + REPLAY)
		quit(1)
		return
	_check(R.rays(R.READER, R.READER_FACING, R.SOURCE, false, false) == 27, "Partition, not the cone, hides the survey source")
	_check(R.rays(R.READER, R.READER_FACING, R.HOOD, true, false) == 27, "Hood, not the cone, hides the received sample")
	for case: Dictionary in replay.cases:
		var snapshot: Dictionary = _replay(case, true)
		_check(snapshot == _replay(case, false), case.id + " deterministic replay")
		print("REPLAY ", case.id, " @ tick ", snapshot.tick)
	var scene := SCENE.instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	_check(root.msaa_3d == Viewport.MSAA_2X and is_equal_approx(root.scaling_3d_scale, 1.0), "2x MSAA at native scale")
	_check(ProjectSettings.get_setting("rendering/renderer/rendering_method") == "forward_plus", "Forward+ project config")
	var render: Dictionary = scene.mcp_observe().render
	_check(is_equal_approx(render.scaling_3d_scale, 1.0) and render.msaa_samples == 2 and is_equal_approx(render.ink_opacity, 0.4), "Reported render parity")
	_check(render.sdfgi_enabled == (DisplayServer.get_name() != "headless"), "Reported SDFGI matches display mode")
	var ink := scene.get_node_or_null("RegisterInk") as MeshInstance3D
	_check(ink != null and is_equal_approx(ink.material_override.get_shader_parameter("opacity"), 0.40), "Mainline ink opacity")
	_check(scene.room.camera.get_world_3d().environment.background_color == scene.room.HALL_ATMOSPHERE.background_color, "Hall04 atmosphere baseline")
	for piece: MeshInstance3D in scene.find_children("*", "MeshInstance3D", true, false):
		if piece in [ink, scene.room.warm_cone, scene.room.cool_cone, scene.room.signal_glass]: continue
		for i in piece.mesh.get_surface_count():
			var material: Material = piece.material_override if piece.material_override else piece.mesh.surface_get_material(i)
			_check(material is ShaderMaterial and material.shader == scene.room.FINISH, "HallFinish on " + str(piece.get_path()))
	if capture: await _save_image("arrival")
	for id: String in R.ACTIONS:
		_check(InputMap.has_action("register_" + id), "InputMap " + id)
	_check(scene.mcp_observe().schema == "evidence_register.v1", "MCP scene root contract")
	_check(JSON.parse_string(JSON.stringify(scene.mcp_observe())) is Dictionary, "MCP JSON round trip")
	var click_target: Button = scene.action_buttons["take_wax"]
	await _click(click_target.get_global_rect().get_center())
	_check(scene.mcp_observe().held == "wax", "Click visible action reaches model")
	await _input_action("reset")
	# Use the same InputEventAction dispatch path as GameMcp.
	await _input_action("take_prism")
	_check(scene.mcp_observe().held == "prism", "InputMap dispatch reaches the model")
	await _input_action("drawer", R.WALK + 3)
	_check(scene.mcp_observe().station == "drawer" and scene.mcp_observe().walk_ticks_left == 0, "Scene station travel")
	await _input_action("send", R.HANDOFF + 3)
	_check(scene.mcp_observe().received == "prism", "Scene timed drawer handoff")
	await _input_action("sun")
	await _input_action("proof", R.WALK + 3)
	await _input_action("show", R.PROOF + 3)
	_check(scene.mcp_observe().manual.edition == "IV", "Scene timed proof")
	if capture: await _save_image("proof")
	await _input_action("release")
	await _input_action("threshold", R.STAMP + 2)
	await _input_action("file")
	_check(scene.mcp_observe().outcome == "clean", "Scene entire clean path via InputMap")
	if capture: await _save_image("filed")
	await _input_action("plate")
	_check(scene.mcp_observe().survey_mark == "moon" and scene.mcp_observe().manual.edition == "III", "Scene swap plate resets outcome")
	await _input_action("reset")
	_check(scene.mcp_observe().station == "survey" and scene.mcp_observe().survey_mark == "moon", "Reset preserves selected plate")
	print("Evidence Register: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)


func _input_action(id: String, frames := 3) -> void:
	var event := InputEventAction.new()
	event.action = StringName("register_" + id)
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	for i in frames: await physics_frame
	var released := InputEventAction.new()
	released.action = event.action
	Input.parse_input_event(released)
	Input.flush_buffered_events()


func _click(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		root.push_input(event, true)
		await process_frame
	for i in 3: await physics_frame


func _replay(case: Dictionary, assert_values: bool) -> Dictionary:
	var rules := R.new(int(case.plate) - 1)
	if assert_values: _expect(rules.observe(), case.get("initial", {}), case.id + " initial")
	var row := 0
	for entry: Dictionary in case.steps:
		row += 1
		var action: String = entry.get("action", "").trim_prefix("register_")
		if assert_values and action != "": _check(R.ACTIONS.has(action), "%s row %d action name" % [case.id, row])
		for i in int(entry.get("ticks", 1)): rules.step(action if i == 0 else "")
		if assert_values: _expect(rules.observe(), entry.get("expect", {}), "%s row %d @%d" % [case.id, row, rules.tick])
	return rules.observe()


func _expect(snapshot: Dictionary, expect: Dictionary, location: String) -> void:
	for path: String in expect:
		var value: Variant = snapshot
		for field in path.split("."):
			value = value.get(field) if value is Dictionary else null
		_check(value == expect[path], "%s: %s expected %s, got %s" % [location, path, expect[path], value])


func _check(ok: bool, name: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + name)



func _save_image(label: String) -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		_check(false, "Viewport images require Forward+ and a display")
		return
	await process_frame
	await RenderingServer.frame_post_draw
	var directory := "res://.runtime/academy-mechanisms/evidence-register"
	var disk_dir := ProjectSettings.globalize_path(directory)
	_check(DirAccess.make_dir_recursive_absolute(disk_dir) == OK, "Capture output directory")
	var path := "%s/.capture-%s.png" % [directory, label]
	_check(root.get_texture().get_image().save_png(ProjectSettings.globalize_path(path)) == OK, "Viewport image " + path)

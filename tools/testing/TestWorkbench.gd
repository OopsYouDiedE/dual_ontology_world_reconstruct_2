extends Control
## Shared host for story fixtures, interaction sequences, lighting and component matrices.
const Scenario := preload("res://scenes/components/testing/ScenarioLoader.gd")
const Monitor := preload("res://scenes/components/testing/RuntimeMonitor.gd")
const StoryHost := preload("res://tools/testing/TestStoryHost.gd")
const Closeup := preload("res://scenes/components/interaction/EvidenceCloseup.gd")
const Matrix := preload("res://tools/testing/BuildingMatrix.gd")
const CaptureSource := preload("res://mcp/CaptureSource.gd")
const Receipt := preload("res://mcp/CaptureReceipt.gd")
const Prop := preload("res://scenes/components/interaction/InteractiveProp3D.gd")
const Mocap := preload("res://tools/mocap/MocapPreview.gd")
const ExpressionPreview := preload("res://tools/testing/ExpressionPreview.gd")
@export_file("*.yaml", "*.json") var default_config := "res://assets/data/test_scenarios/wake.yaml"
var loader := Scenario.new()
var content: Control
var monitor: Control
var subject: Node
var output_dir := ""
var config_path := ""
var error := ""
var suite := ""
var _elapsed := 0.0
var _duration := 0.0
var _quitting := false
var _monitor_visible := false
var _captures: Array = []
var _events: Array = []
var _matrix_index := 0
var _world: Node3D
var _viewport: SubViewport
var _suite_running := false
signal fixture_ready

func _argument(key: String, fallback := "") -> String:
	for argument in OS.get_cmdline_user_args():
		if str(argument).begins_with(key + "="): return str(argument).substr(key.length() + 1)
	return fallback

func _ready() -> void:
	get_tree().auto_accept_quit = false
	add_to_group("lifecycle_hosts")
	get_window().files_dropped.connect(_files_dropped)
	config_path = _argument("--scenario", default_config)
	suite = _argument("--test-suite")
	_duration = float(_argument("--test-duration", "0"))
	output_dir = CaptureSource.project_output(_argument("--test-output", ".runtime/test-runs/" + Time.get_datetime_string_from_system().replace(":", "-") + "-" + str(Time.get_ticks_usec())))
	if output_dir.is_empty(): _fail("Invalid output path"); return
	DirAccess.make_dir_recursive_absolute(output_dir)
	content = Control.new()
	content.name = "Content"
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(content)
	monitor = Monitor.new()
	monitor.name = "RuntimeMonitor"
	monitor.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	monitor.offset_top = -82.0
	add_child(monitor)
	# User decision: collect continuously, hide the overlay by default. The test
	# operator can opt in explicitly or toggle it with F2; collection continues.
	_monitor_visible = _argument("--monitor-visible", "false") == "true"
	monitor.visible = _monitor_visible
	content.offset_bottom = -82.0 if _monitor_visible else 0.0
	monitor.configure(output_dir, {"config_path": config_path, "config_sha256": FileAccess.get_sha256(config_path), "mock": true, "monitor_visible": _monitor_visible, "monitor_policy": "hidden_by_default_opt_in_diagnostic_view", "capture_policy": "development evidence; Terra full-process capture and blind review required for acceptance"}, content)
	_load_fixture(config_path)
	if error != "": return
	fixture_ready.emit()
	if _argument("--capture-entry") == "true": _capture.call_deferred("entry")
	if suite != "": _run_suite.call_deferred()

func _files_dropped(paths: PackedStringArray) -> void:
	if paths.size() == 1 and paths[0].get_extension().to_lower() in ["yaml", "yml", "json"]:
		config_path = paths[0]
		_load_fixture(config_path)

func _load_fixture(path: String) -> void:
	if _suite_running: return
	if not loader.read(path): _fail(loader.error); return
	for child in content.get_children():
		content.remove_child(child)
		child.queue_free()
	subject = null
	_world = null
	_viewport = null
	error = ""
	var configuration: Dictionary = loader.configuration
	var mode := str(configuration.get("mode", "story"))
	monitor.node_id = str(configuration.get("id", mode))
	_event({"phase": "load", "configuration": configuration, "source": path, "sha256": FileAccess.get_sha256(path)})
	match mode:
		"story", "lighting": _build_story()
		"interaction": _build_interaction(str(configuration.get("kind", "wardrobe")))
		"building": _build_matrix_case(0)
		"mocap":
			var preview := Mocap.new()
			preview.configure_test_context(configuration,output_dir)
			subject = preview
			content.add_child(preview)
		"expression":
			var preview := ExpressionPreview.new()
			preview.configure_test_context(configuration,output_dir)
			subject = preview
			content.add_child(preview)
		_: _fail("Presentation module is not installed: " + mode)

func _build_story() -> void:
	var path := str(loader.configuration.get("scene", "res://scenes/dual_world/DualWorldMain.tscn"))
	if path != "res://scenes/dual_world/DualWorldMain.tscn":
		# An arbitrary scene must declare an explicit mock-state contract before it runs.
		var packed := load(path) as PackedScene
		if packed == null: _fail("Scene cannot be instantiated"); return
		var custom := packed.instantiate()
		if not custom.has_method("configure_test_context"):
			custom.free()
			_fail("Scene requires configure_test_context(configuration, output_directory)")
			return
		custom.configure_test_context(loader.configuration.duplicate(true), output_dir)
		subject = custom
		content.add_child(custom)
		return
	var story := StoryHost.new()
	story.name = "ProductionStoryFixture"
	story.fixture = loader
	story.fixture_directory = output_dir
	story.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	subject = story
	content.add_child(story)
	if story.fixture_error != "": _fail(story.fixture_error); return
	var actors := {"detective": story.det.position}
	for id in story.figures:
		actors[id] = story.figures[id].position
	var actor_ids := actors.keys()
	var overlapping: Array = []
	for i in actor_ids.size():
		for j in range(i + 1, actor_ids.size()):
			var a: Vector3 = actors[actor_ids[i]]
			var b: Vector3 = actors[actor_ids[j]]
			var distance := Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))
			if distance + 0.001 < story.ACTOR_TOUCH_DISTANCE:
				overlapping.append({"a": actor_ids[i], "b": actor_ids[j], "distance": distance})
	_write_json("initial-state.json", {"mock": true, "configured_scene": path, "production_script": "res://scenes/dual_world/DualWorldMain.gd", "state": story.fixture_initial_state,
		"actor_positions":actors,"overlapping_actors":overlapping})
	story.eng.changed.connect(func(reason: String): _event({"phase": "engine", "reason": reason, "snapshot": story.test_snapshot()}))
	story.interactions.event_recorded.connect(_event)
	story.reconstruction_observed.connect(_event)

func _build_interaction(kind: String) -> void:
	var closeup := Closeup.new()
	closeup.kind = kind
	subject = closeup
	closeup.observed.connect(_event)
	closeup.finished.connect(func(success: bool): _event({"phase": "closed", "kind": kind, "success": success}))
	content.add_child(closeup)

func _stage() -> Node3D:
	var container := SubViewportContainer.new()
	container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	content.add_child(container)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(1440, 900)
	_viewport.own_world_3d = true
	_viewport.audio_listener_enable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(_viewport)
	_world = Node3D.new()
	_viewport.add_child(_world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#182125")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#a3adb4")
	environment.environment.ambient_light_energy = 0.6
	_world.add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, -30, 0)
	sun.shadow_enabled = true
	_world.add_child(sun)
	var camera := Camera3D.new()
	_world.add_child(camera)
	camera.position = Vector3(6.8, 5.8, 8.8)
	camera.look_at(Vector3(0, 0.9, 0))
	camera.current = true
	return _world

func _build_matrix_case(index: int) -> void:
	if _world == null: _stage()
	var previous := _world.get_node_or_null("Components")
	if previous != null: _world.remove_child(previous); previous.queue_free()
	var group := Node3D.new()
	group.name = "Components"
	_world.add_child(group)
	var cases := Matrix.cases()
	_matrix_index = posmod(index, cases.size())
	var state: Dictionary = cases[_matrix_index]
	Matrix.build(group, state)
	subject = group
	monitor.node_id = str(state.id)
	_event({"phase": "component_case", "state": state, "total_cases": cases.size()})

func _event(value: Dictionary) -> void:
	var event := value.duplicate(true)
	event["elapsed_s"] = _elapsed
	event["system_time"] = Time.get_datetime_string_from_system(false, true)
	_events.append(event)
	if monitor != null and monitor.report.file != null: monitor.report.append({"event": event})
	if bool(loader.configuration.get("capture_stages",false)) and event.has("stage") and str(event.stage) != "complete": _capture_stage(event)

func _capture_stage(event: Dictionary) -> void:
	await get_tree().create_timer(0.12 if event.has("shot") else 1.05).timeout
	if _quitting: return
	await _capture("reconstruction_"+str(event.stage)+"_"+str(event.get("shot","entry")))

func _write_json(filename: String, value: Variant) -> void:
	var file := FileAccess.open(output_dir + "/" + filename, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(value, "  ")); file.close()

func _capture(tag: String) -> bool:
	if DisplayServer.get_name() == "headless":
		_event({"phase": "capture_skipped", "reason": "headless development run", "tag": tag})
		return false
	await RenderingServer.frame_post_draw
	var texture := get_viewport().get_texture()
	if texture == null or DisplayServer.get_name() == "headless":
		_event({"phase": "capture_skipped", "reason": "no rendered viewport", "tag": tag})
		return false
	var path := output_dir + "/captures/" + tag.validate_filename() + ".png"
	var image := texture.get_image()
	if not Receipt.save(image, path, get_tree(), "workbench-development-fixture"): return false
	_captures.append({"tag": tag, "path": path, "sha256": FileAccess.get_sha256(path), "elapsed_s": _elapsed, "text": Monitor.visible_text(content), "monitor_visible": monitor.visible})
	_write_json("captures.json", _captures)
	return true

func _run_suite() -> void:
	_suite_running = true
	match suite:
		"interactions":
			for kind in ["wardrobe", "ratchet", "grille", "hand", "sleeve", "copper", "water", "cloth", "chalk"]:
				for child in content.get_children(): content.remove_child(child); child.queue_free()
				_build_interaction(kind)
				monitor.node_id = kind
				await get_tree().create_timer(0.25).timeout
				await _capture(kind + "_start")
				if kind in ["wardrobe", "ratchet", "grille"]:
					await get_tree().create_timer(0.70).timeout
				else:
					# Drive the same public model methods; input-driven runs are collected separately.
					if kind in ["hand", "sleeve", "copper"]: subject.prop.align_hand(Vector2(0.10, 0))
					else: subject.prop.sweep(90, Vector2(-0.10, 0.02))
				await _capture(kind + "_process")
				if kind in ["hand", "sleeve", "copper"]: subject.prop.align_hand(Vector2(0.23, 0))
				elif kind in ["water", "cloth", "chalk"]: subject.prop.sweep(110, Vector2(0.16, 0.03))
				await get_tree().create_timer(0.75).timeout
				await _capture(kind + "_end")
		"building":
			for index in Matrix.cases().size():
				_build_matrix_case(index)
				await get_tree().create_timer(0.20).timeout
				await _capture("building_%02d" % index)
		"lighting":
			for setting in [{"id": "08", "hour": 8, "weather": "clear"}, {"id": "14", "hour": 14, "weather": "clear"}, {"id": "22", "hour": 22, "weather": "clear"}, {"id": "fog", "hour": 14, "weather": "fog"}]:
				if not subject is StoryHost: _fail("Lighting suite requires a story scene"); break
				loader.configuration["weather"] = setting.weather
				subject.eng.s.t = (int(subject.eng.s.day) - 1) * 1440 + int(setting.hour) * 60
				subject.eng.s.playing = false
				subject._light_cd = 0.0
				monitor.node_id = "lighting_" + str(setting.id)
				_event({"phase": "lighting_preset", "setting": setting, "clock": subject.eng.clock()})
				await get_tree().create_timer(1.0).timeout
				await _capture("lighting_" + str(setting.id))
		_: _fail("Unknown suite: " + suite)
	_suite_running = false
	_event({"phase": "suite_complete", "suite": suite, "acceptance": "pending_terra_capture_and_blind_review"})
	_write_json("events.json", _events)
	if _argument("--test-auto-quit", "false") == "true": _finish()

func _process(delta: float) -> void:
	_elapsed += delta
	if subject != null and subject.has_method("test_snapshot"):
		var state: Dictionary = subject.test_snapshot()
		monitor.node_id = str(state.get("opening_phase", state.get("kitchen_phase", state.get("room", "story"))))
		if state.has("reconstruction"): monitor.node_id = "reconstruction_"+str(state.reconstruction.performance.get("stage","off"))
	if _duration > 0 and _elapsed >= _duration and not _suite_running: _finish()

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo: return
	match event.keycode:
		KEY_F2:
			_monitor_visible = not _monitor_visible
			monitor.visible = _monitor_visible
			content.offset_bottom = -82.0 if _monitor_visible else 0.0
			_event({"phase": "monitor_visibility", "visible": _monitor_visible, "policy": "manual_diagnostic_view"})
		KEY_F5: _load_fixture(config_path)
		KEY_F8: _capture("manual_" + str(Time.get_ticks_msec()))
		KEY_PAGEUP: if _world != null: _build_matrix_case(_matrix_index - 1)
		KEY_PAGEDOWN: if _world != null: _build_matrix_case(_matrix_index + 1)
		_: return
	get_viewport().set_input_as_handled()

func _fail(message: String) -> void:
	error = message
	push_error("TestWorkbench: " + message)
	if output_dir != "": _write_json("error.json", {"error": message, "config": config_path})
	# Validation failures are concrete launch failures, never silent fallback scenes.
	_finish(2)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST: _finish()

func _finish(code := 0) -> void:
	if _quitting: return
	_quitting = true
	begin_shutdown(code)
	await preload("res://scenes/components/shared/HostLifecycle.gd").quit(get_tree(), code)

func begin_shutdown(code := 0) -> void:
	if monitor == null or monitor._finished: return
	_event({"phase": "shutdown", "exit_code": code})
	_write_json("events.json", _events)
	monitor.finish()

func wait_for_shutdown() -> void:
	if monitor == null: return
	var deadline := Time.get_ticks_msec() + 12000
	while monitor._worker_pid > 0 and OS.is_process_running(monitor._worker_pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	if monitor._worker_pid > 0 and OS.is_process_running(monitor._worker_pid): push_error("Audio worker did not finalize before shutdown")

func mcp_observe() -> Dictionary:
	return {"test_fixture": true, "configuration": loader.configuration, "output_directory": output_dir, "error": error, "suite": suite, "suite_running": _suite_running, "elapsed_s": _elapsed, "monitor_visible": monitor.visible if monitor != null else false, "snapshot": subject.test_snapshot() if subject != null and subject.has_method("test_snapshot") else {}, "metrics": monitor.latest if monitor != null else {}, "acceptance": "pending_independent_review"}

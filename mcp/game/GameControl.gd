extends Node

var server := TCPServer.new()
var peer: StreamPeerTCP
var buffer := PackedByteArray()
var token := ""
var busy := false
var launch_scene := ""
var monitor: Control
var _monitor_stopped := false
var snapshot_path := ""
var assessment_plan_path := ""
var assessment_test_id := ""
var realtime_capture: Node
var scenario_path := ""
var assessment_output_directory := ""
var assessment_segment_id := ""
var assessment_cases: Array = []
var assessment_case_index := 0

func _ready() -> void:
	var port := 0
	var expected_root := ""
	var expected_hash := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dv-mcp-port="): port = int(argument.trim_prefix("--dv-mcp-port="))
		elif argument.begins_with("--dv-mcp-token="): token = argument.trim_prefix("--dv-mcp-token=")
		elif argument.begins_with("--dv-launch-scene="): launch_scene = argument.trim_prefix("--dv-launch-scene=")
		elif argument.begins_with("--dv-project-root="): expected_root = argument.trim_prefix("--dv-project-root=")
		elif argument.begins_with("--dv-project-sha256="): expected_hash = argument.trim_prefix("--dv-project-sha256=")
		elif argument.begins_with("--dv-snapshot="): snapshot_path = argument.trim_prefix("--dv-snapshot=")
		elif argument.begins_with("--dv-scenario="): scenario_path = argument.trim_prefix("--dv-scenario=")
		elif argument.begins_with("--dv-assessment-plan="): assessment_plan_path = argument.trim_prefix("--dv-assessment-plan=")
	if port == 0: set_process(false); return
	assessment_output_directory = "res://.runtime/segment-sessions/" + str(OS.get_process_id())
	var source := preload("res://mcp/CaptureSource.gd").identity(get_tree(), launch_scene)
	var root_path := str(source.project_root).replace("\\", "/").simplify_path().trim_suffix("/")
	var required_root := expected_root.replace("\\", "/").simplify_path().trim_suffix("/")
	if OS.get_name() == "Windows":
		root_path = root_path.to_lower()
		required_root = required_root.to_lower()
	if expected_root.is_empty() or root_path != required_root or expected_hash.is_empty() or source.project_sha256 != expected_hash or int(source.process_id) <= 0:
		push_error("Game MCP project identity or PID validation failed")
		set_process(false)
		return
	if token.length() < 32 or server.listen(port, "127.0.0.1") != OK:
		push_error("Game MCP transport could not start")
		set_process(false)
		return
	add_to_group("lifecycle_hosts")
	_start_monitor.call_deferred()

func _start_monitor() -> void:
	# Boot replaces itself at the first frame boundary. Wait until the title owns
	# the tree so a transient null current_scene cannot discard the recorder.
	var content: Control
	for attempt in 120:
		await get_tree().process_frame
		content = get_tree().current_scene as Control
		if is_instance_valid(content) and (content.has_method("open_dual_world") or ((not snapshot_path.is_empty() or not scenario_path.is_empty()) and content.has_method("start_kitchen_exploration"))): break
	if not is_instance_valid(content) or not (content.has_method("open_dual_world") or ((not snapshot_path.is_empty() or not scenario_path.is_empty()) and content.has_method("start_kitchen_exploration"))):
		push_error("Mainline metrics could not find the production title")
		return
	monitor = preload("res://scenes/components/testing/RuntimeMonitor.gd").new()
	monitor.name = "MainlineMetrics"
	add_child(monitor)
	monitor.visible = false
	var directory := ".runtime/mainline-runs/" + Time.get_datetime_string_from_system().replace(":", "-") + "-" + str(OS.get_process_id())
	var metadata := {"mock": not snapshot_path.is_empty(), "entry": "snapshot" if not snapshot_path.is_empty() else "production_title", "snapshot_path": snapshot_path, "acceptance_eligible": snapshot_path.is_empty(), "launch_scene": launch_scene, "process_id": OS.get_process_id(), "project_sha256": FileAccess.get_sha256("res://project.godot"), "monitor_visible": false, "capture_policy": "independent Terra review required", "max_fps": Engine.max_fps}
	if not scenario_path.is_empty(): metadata.merge({"mock": true, "entry": "scenario", "scenario_path": scenario_path, "acceptance_eligible": false}, true)
	if not assessment_plan_path.is_empty():
		var plan = JSON.parse_string(FileAccess.get_file_as_string(assessment_plan_path))
		if not plan is Dictionary:
			push_error("Simultaneous assessment plan could not be read")
			return
		assessment_test_id = str(plan.test_id)
		assessment_segment_id = str(plan.get("segment_id", ""))
		assessment_cases = plan.cases
		metadata.merge({"test_id": plan.test_id, "revision": plan.revision, "assessment_plan": assessment_plan_path, "assessment_plan_sha256": FileAccess.get_sha256(assessment_plan_path), "collection_mode": "simultaneous", "assessment_channels": plan.channels})
	monitor.configure(directory, metadata, content)
	if not assessment_plan_path.is_empty():
		realtime_capture = preload("res://scenes/components/testing/RealtimeCapture.gd").new()
		add_child(realtime_capture)
		realtime_capture.configure(monitor)

func _story(main: Node) -> Control:
	if not is_instance_valid(main): return null
	if main.has_method("start_kitchen_exploration"): return main as Control
	if main.has_method("open_dual_world"): return main.get("dual_world") as Control
	return null

func _checkpoint_status(main: Node) -> Dictionary:
	var story := _story(main)
	if not is_instance_valid(story): return {}
	var checkpoint: Node = story.get("checkpoints")
	if not is_instance_valid(checkpoint): return {}
	var controller := "room"
	var phase := ""
	if is_instance_valid(story.opening) and story.opening.active:
		controller = "opening"
		phase = str(story.opening.phase)
	elif is_instance_valid(story.gathering) and story.gathering.active:
		controller = "corridor"
		phase = str(story.gathering.phase)
	elif is_instance_valid(story.kitchen) and story.kitchen.active:
		controller = "kitchen"
		phase = str(story.kitchen.phase)
	return {"checkpoint_path": checkpoint.output_path, "checkpoint_restored": checkpoint.restored,
		"checkpoint_error": checkpoint.error, "controller": controller, "controller_phase": phase}

func _tag_monitor() -> void:
	if monitor == null or _monitor_stopped: return
	var main := get_tree().current_scene
	if main == null: return
	monitor._owner = main as Control
	var direct_story := main.has_method("start_kitchen_exploration")
	var story := _story(main)
	var segment := "title"
	var room := ""
	var clock := ""
	var exempt := false
	var title: Control = null if direct_story else main.get("title_ui")
	var book: Control = null if direct_story else main.get("book_ui")
	if is_instance_valid(title) and title.is_visible_in_tree(): exempt = true
	if is_instance_valid(book) and book.is_open: exempt = book.page_id() == "settings"
	if is_instance_valid(story):
		exempt = false
		room = str(story.eng.s.room)
		clock = str(story.eng.clock().text)
		match room:
			"R05": segment = "wake" if story.opening != null and story.opening.active else "chapter_end"
			"B-P":
				segment = "kitchen_evidence"
				if story.kitchen != null and is_instance_valid(story.kitchen._order_replay) and story.kitchen._order_replay.active: segment = "kitchen_reconstruction"
			"A-P", "service_stair_M", "F01": segment = "service_route"
			"C-P", "D-P", "2F-cross-M": segment = "cross_zone"
			"2F-North-Stair", "1F-Shaft-Monitor": segment = "shaft"
			"T01": segment = "poem"
			"Wind-Corridor", "W-102", "S-102", "B-102", "F-104": segment = "institutes"
			"F03", "F05": segment = "dinner"
			_: segment = "travel"
		if story.gathering != null and story.gathering.active: segment = "corridor"
		var scene_root: Node = story.lowpoly._root if story._lowpoly_ok else story.room_mesh
		if story.gathering != null and story.gathering.active and is_instance_valid(story.gathering._root): scene_root = story.gathering._root
		monitor.tag_scene(str(scene_root.get_instance_id()) + "/" + story._room_loaded)
	else: monitor.tag_scene("title")
	if not assessment_segment_id.is_empty(): segment = assessment_segment_id
	monitor.node_id = segment + "/" + room
	monitor.sample_context = {"gameplay_segment": segment, "room": room, "story_clock": clock, "text_exempt": exempt}

func begin_shutdown() -> void:
	if realtime_capture != null: realtime_capture.finish()
	_monitor_stopped = true
	if monitor != null: monitor.finish()

func wait_for_shutdown() -> void:
	if monitor == null: return
	var deadline := Time.get_ticks_msec() + 35000
	var workers: Array[int] = [monitor._worker_pid]
	for stream in monitor.background_streams: workers.append(int(stream.worker_pid))
	for pid in workers:
		while pid > 0 and OS.is_process_running(pid) and Time.get_ticks_msec() < deadline:
			await get_tree().create_timer(0.05).timeout
		if pid > 0 and OS.is_process_running(pid): push_error("Audio worker did not finalize before shutdown: " + str(pid))

func _process(_delta: float) -> void:
	_tag_monitor()
	if peer == null:
		if server.is_connection_available(): peer = server.take_connection()
		return
	peer.poll()
	if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		peer = null
		buffer.clear()
		return
	if busy: return
	var count := peer.get_available_bytes()
	if count > 0:
		var received := peer.get_data(count)
		if received[0] == OK: buffer.append_array(received[1])
	if buffer.size() > 262144: peer.disconnect_from_host(); buffer.clear(); return
	var newline := buffer.find(10)
	if newline < 0: return
	var request = JSON.parse_string(buffer.slice(0, newline).get_string_from_utf8())
	buffer = buffer.slice(newline + 1)
	if not request is Dictionary: return
	if request.get("token") != token: _reply(request.get("id"), {}, "Invalid token"); return
	busy = true
	_handle.call_deferred(request)

func _reply(identity, result: Dictionary, error := "") -> void:
	if peer != null and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data((JSON.stringify({"id": identity, "result": result} if error.is_empty() else {"id": identity, "error": error}) + "\n").to_utf8_buffer())
	busy = false

func _handle(request: Dictionary) -> void:
	var identity = request.get("id")
	var main := get_tree().current_scene
	match str(request.get("type", "observe")):
		"next_case":
			if scenario_path.is_empty() or assessment_case_index + 1 >= assessment_cases.size():
				_reply(identity, {}, "No next case in this segment")
				return
			var next: Dictionary = assessment_cases[assessment_case_index + 1]
			if FileAccess.get_sha256(str(next.scenario_path)) != str(next.scenario_sha256):
				_reply(identity, {}, "Scenario changed after assessment launch")
				return
			assessment_case_index += 1
			scenario_path = str(next.scenario_path)
			if monitor != null: monitor._owner = null
			var changed := get_tree().change_scene_to_file("res://mcp/game/SegmentEntry.tscn")
			if changed != OK:
				_reply(identity, {}, "Scenario transition failed: " + error_string(changed))
				return
			await get_tree().process_frame
		"close":
			_reply(identity, {"closed": true, "source_identity": preload("res://mcp/CaptureSource.gd").identity(get_tree(), launch_scene)})
			await preload("res://scenes/components/shared/HostLifecycle.gd").quit(get_tree())
			return
		"start":
			if not main.has_method("open_dual_world"): _reply(identity, {}, "当前场景不支持主线新局"); return
			main.open_dual_world()
		"click":
			var point := Vector2(float(request.get("x", -1)), float(request.get("y", -1)))
			if not get_viewport().get_visible_rect().has_point(point): _reply(identity, {}, "点击越界"); return
			var motion := InputEventMouseMotion.new()
			motion.position = point
			Input.parse_input_event(motion)
			await get_tree().process_frame
			var event := InputEventMouseButton.new()
			event.position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = true
			Input.parse_input_event(event)
			await get_tree().process_frame
			event.pressed = false
			Input.parse_input_event(event)
		"observe": pass
		"drag":
			var from := Vector2(float(request.get("x", -1)), float(request.get("y", -1)))
			var to := Vector2(float(request.get("to_x", -1)), float(request.get("to_y", -1)))
			var bounds := get_viewport().get_visible_rect()
			if not bounds.has_point(from) or not bounds.has_point(to): _reply(identity, {}, "拖动越界"); return
			var motion := InputEventMouseMotion.new()
			motion.position = from
			Input.parse_input_event(motion)
			await get_tree().process_frame
			var button := InputEventMouseButton.new()
			button.position = from
			button.button_index = MOUSE_BUTTON_LEFT
			button.pressed = true
			Input.parse_input_event(button)
			var count := clampi(int(request.get("frames", 30)), 2, 120)
			var previous := from
			for index in count:
				await get_tree().process_frame
				var point := from.lerp(to, float(index + 1) / count)
				motion = InputEventMouseMotion.new()
				motion.position = point
				motion.relative = point - previous
				motion.button_mask = MOUSE_BUTTON_MASK_LEFT
				Input.parse_input_event(motion)
				previous = point
			button.position = to
			button.pressed = false
			Input.parse_input_event(button)
		"input_action":
			var action := str(request.get("action", ""))
			if not InputMap.has_action(action): _reply(identity, {}, "未知输入动作"); return
			var event := InputEventAction.new()
			event.action = action
			event.pressed = true
			Input.parse_input_event(event)
			for frame in range(clampi(int(request.get("frames", 1)), 1, 120)): await get_tree().process_frame
			event.pressed = false
			Input.parse_input_event(event)
		_: _reply(identity, {}, "不支持的游戏命令"); return
	var wait_ms := clampi(int(request.get("wait_ms", 200)), 0, 10000)
	if wait_ms > 0: await get_tree().create_timer(wait_ms / 1000.0).timeout
	await get_tree().process_frame
	main = get_tree().current_scene
	if not is_instance_valid(main):
		_reply(identity, {}, "Scene transition has not produced a live scene")
		return
	var result: Dictionary = main.mcp_observe() if main.has_method("mcp_observe") else {"scene": main.scene_file_path}
	if not scenario_path.is_empty():
		result["scenario_ready"] = main.scene_file_path == "res://mcp/game/SegmentEntry.tscn" and str(main.get("fixture_error")).is_empty()
		result["scenario_error"] = str(main.get("fixture_error"))
	result.merge(_checkpoint_status(main), true)
	var controls: Array = []
	_collect(get_tree().root, controls)
	result["controls"] = controls
	result["scene"] = main.scene_file_path
	result["source_identity"] = preload("res://mcp/CaptureSource.gd").identity(get_tree(), launch_scene)
	if monitor != null:
		result["metrics_directory"] = monitor.output_dir
		result["metrics"] = monitor.latest
		result["assessment_test_id"] = assessment_test_id
		result["assessment_segment"] = monitor.node_id
		result["assessment_case_index"] = assessment_case_index
		result["assessment_case_count"] = assessment_cases.size()
	if bool(request.get("capture_image", true)):
		var captured := get_viewport().get_texture().get_image()
		var encoder := Thread.new()
		var encoding := encoder.start(func(): return Marshalls.raw_to_base64(captured.save_png_to_buffer()))
		if encoding != OK:
			_reply(identity, {}, "截图编码线程启动失败：" + error_string(encoding))
			return
		while encoder.is_alive(): await get_tree().process_frame
		result["image_base64"] = encoder.wait_to_finish()
	_reply(identity, result)

func _collect(node: Node, controls: Array) -> void:
	preload("res://scenes/components/testing/VisibleText.gd").collect(node, get_viewport(), controls, false)

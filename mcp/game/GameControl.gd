extends Node

var server := TCPServer.new()
var peer: StreamPeerTCP
var buffer := PackedByteArray()
var token := ""
var busy := false
var launch_scene := ""
var monitor: Control
var _monitor_stopped := false

func _ready() -> void:
	var port := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dv-mcp-port="): port = int(argument.trim_prefix("--dv-mcp-port="))
		elif argument.begins_with("--dv-mcp-token="): token = argument.trim_prefix("--dv-mcp-token=")
		elif argument.begins_with("--dv-launch-scene="): launch_scene = argument.trim_prefix("--dv-launch-scene=")
	if port == 0: set_process(false); return
	if token.length() < 32 or server.listen(port, "127.0.0.1") != OK:
		push_error("Game MCP transport could not start")
		set_process(false)
		return
	add_to_group("lifecycle_hosts")
	_start_monitor.call_deferred()

func _start_monitor() -> void:
	await get_tree().process_frame
	var content := get_tree().current_scene as Control
	if content == null: return
	monitor = preload("res://scenes/components/testing/RuntimeMonitor.gd").new()
	monitor.name = "MainlineMetrics"
	add_child(monitor)
	monitor.visible = false
	var directory := ".runtime/mainline-runs/" + Time.get_datetime_string_from_system().replace(":", "-") + "-" + str(OS.get_process_id())
	monitor.configure(directory, {"mock": false, "entry": "production_title", "monitor_visible": false, "capture_policy": "real mainline; independent Terra review required"}, content)

func _tag_monitor() -> void:
	if monitor == null or _monitor_stopped: return
	var main := get_tree().current_scene
	if main == null: return
	monitor._owner = main as Control
	var story: Control = main.get("dual_world")
	var segment := "title"
	var room := ""
	var clock := ""
	var exempt := false
	var title: Control = main.get("title_ui")
	var book: Control = main.get("book_ui")
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
	monitor.node_id = segment + "/" + room
	monitor.sample_context = {"gameplay_segment": segment, "room": room, "story_clock": clock, "text_exempt": exempt}

func begin_shutdown() -> void:
	_monitor_stopped = true
	if monitor != null: monitor.finish()

func wait_for_shutdown() -> void:
	if monitor == null: return
	var deadline := Time.get_ticks_msec() + 12000
	while monitor._worker_pid > 0 and OS.is_process_running(monitor._worker_pid) and Time.get_ticks_msec() < deadline:
		await get_tree().create_timer(0.05).timeout
	if monitor._worker_pid > 0 and OS.is_process_running(monitor._worker_pid): push_error("Mainline audio worker did not finalize before shutdown")

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
	var result: Dictionary = main.mcp_observe() if main.has_method("mcp_observe") else {"scene": main.scene_file_path}
	var controls: Array = []
	_collect(get_tree().root, controls)
	result["controls"] = controls
	result["scene"] = main.scene_file_path
	result["source_identity"] = preload("res://mcp/CaptureSource.gd").identity(get_tree(), launch_scene)
	if monitor != null:
		result["metrics_directory"] = monitor.output_dir
		result["metrics"] = monitor.latest
	if bool(request.get("capture_image", true)):
		result["image_base64"] = Marshalls.raw_to_base64(get_viewport().get_texture().get_image().save_png_to_buffer())
	_reply(identity, result)

func _collect(node: Node, controls: Array) -> void:
	if node is SubViewport and node.has_meta("physical_book_view"):
		var book: Node = node.get_meta("physical_book_view")
		if not is_instance_valid(book) or not book.is_active(): return
	if node is Control:
		if not node.is_visible_in_tree(): return
		var text := ""
		if node is Label or node is BaseButton: text = node.text
		if not text.is_empty():
			var rect: Rect2 = node.get_global_rect()
			var ancestor := node.get_parent()
			while ancestor != null and not ancestor is Viewport:
				if ancestor is Control and ancestor.clip_contents: rect = rect.intersection(ancestor.get_global_rect())
				ancestor = ancestor.get_parent()
			if not rect.has_area(): return
			var viewport := node.get_viewport()
			if viewport.has_meta("physical_book_view"): rect = viewport.get_meta("physical_book_view").screen_rect_for_control(node, rect)
			if not get_viewport().get_visible_rect().intersects(rect): return
			controls.append({"text": text, "x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y, "class": node.get_class(), "path": str(node.get_path()), "disabled": node.disabled if node is BaseButton else false})
	for child in node.get_children(): _collect(child, controls)

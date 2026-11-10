extends Node

var server := TCPServer.new()
var peer: StreamPeerTCP
var buffer := PackedByteArray()
var token := ""
var busy := false

func _ready() -> void:
	var port := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dv-mcp-port="): port = int(argument.trim_prefix("--dv-mcp-port="))
		elif argument.begins_with("--dv-mcp-token="): token = argument.trim_prefix("--dv-mcp-token=")
	if port == 0: set_process(false); return
	if token.length() < 32 or server.listen(port, "127.0.0.1") != OK:
		push_error("Game MCP transport could not start")
		set_process(false)

func _process(_delta: float) -> void:
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
			if main.has_method("close_life"): main.close_life()
			_reply(identity, {"closed": true})
			get_tree().quit()
			return
		"start":
			if not main.has_method("open_life"): _reply(identity, {}, "当前场景不支持生活新局"); return
			main.open_life()
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
		"input_action":
			var action := str(request.get("action", ""))
			if not InputMap.has_action(action): _reply(identity, {}, "未知输入动作"); return
			Input.action_press(action)
			for frame in range(clampi(int(request.get("frames", 1)), 1, 120)): await get_tree().process_frame
			Input.action_release(action)
		_: _reply(identity, {}, "不支持的游戏命令"); return
	var wait_ms := clampi(int(request.get("wait_ms", 200)), 0, 10000)
	if wait_ms > 0: await get_tree().create_timer(wait_ms / 1000.0).timeout
	await get_tree().process_frame
	var result: Dictionary = main.mcp_observe() if main.has_method("mcp_observe") else {"scene": main.scene_file_path}
	var controls: Array = []
	_collect(get_tree().root, controls)
	result["controls"] = controls
	result["scene"] = main.scene_file_path
	if bool(request.get("capture_image", true)):
		result["image_base64"] = Marshalls.raw_to_base64(get_viewport().get_texture().get_image().save_png_to_buffer())
	_reply(identity, result)

func _collect(node: Node, controls: Array) -> void:
	if node is Control and node.is_visible_in_tree():
		var text := ""
		if node is Label or node is BaseButton: text = node.text
		if not text.is_empty():
			var rect: Rect2 = node.get_global_rect()
			controls.append({"text": text, "x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y})
	for child in node.get_children(): _collect(child, controls)

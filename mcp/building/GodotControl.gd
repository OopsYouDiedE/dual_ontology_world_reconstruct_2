extends Node
## Opt-in MCP transport. Normal project runs do not open a socket.
var server := TCPServer.new()
var peer: StreamPeerTCP
var buffer := PackedByteArray()
var token := ""
var busy := false
var observation_id := 0
var receipt_directory := ""

func _ready() -> void:
	var port := 0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--building-mcp-port="): port = int(argument.trim_prefix("--building-mcp-port="))
		elif argument.begins_with("--building-mcp-token="): token = argument.trim_prefix("--building-mcp-token=")
		elif argument.begins_with("--building-mcp-receipts="): receipt_directory = argument.trim_prefix("--building-mcp-receipts=")
	if port == 0: set_process(false); return
	if token.length() < 32 or server.listen(port,"127.0.0.1") != OK:
		push_error("Building MCP transport could not start")
		set_process(false)
		return

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
	var request = JSON.parse_string(buffer.slice(0,newline).get_string_from_utf8())
	buffer = buffer.slice(newline+1)
	if not request is Dictionary: return
	if request.get("token") != token: _reply(request.get("id"),{},"Invalid token"); return
	busy = true
	_handle.call_deferred(request)

func _reply(id, result: Dictionary, error := "") -> void:
	if peer != null and peer.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		peer.put_data((JSON.stringify({"id":id,"result":result} if error.is_empty() else {"id":id,"error":error})+"\n").to_utf8_buffer())
	busy = false

func _send_input(event: InputEvent) -> void:
	if event is InputEventMouse:
		Input.parse_input_event(event)
		return
	# Route native input to the visible embedded dialog's viewport. Keyboard
	# events sent only to the root viewport cannot edit an embedded LineEdit.
	var windows = get_viewport().get_embedded_subwindows()
	for i in range(windows.size()-1,-1,-1):
		var window = windows[i]
		if not window.visible: continue
		var routed = event.duplicate()
		if routed is InputEventMouse:
			routed.position -= Vector2(window.position)
		window.push_input(routed,true)
		return
	Input.parse_input_event(event)

func _handle(request: Dictionary) -> void:
	var id = request.get("id")
	match str(request.get("type","observe")):
		"close":
			_reply(id,{"closed":true})
			get_tree().quit()
			return
		"click":
			var point := Vector2(float(request.get("x",-1)),float(request.get("y",-1)))
			var bounds := get_viewport().get_visible_rect()
			if not bounds.has_point(point): _reply(id,{},"Click lies outside current viewport"); return
			var motion = InputEventMouseMotion.new()
			motion.position = point
			motion.global_position = point
			_send_input(motion)
			await get_tree().process_frame
			var event := InputEventMouseButton.new()
			event.position = point
			event.global_position = point
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = true
			_send_input(event)
			await get_tree().process_frame
			var release := event.duplicate()
			release.pressed = false
			_send_input(release)
		"pointer":
			var event = InputEventMouseMotion.new()
			event.position = Vector2(request.get("x",0),request.get("y",0))
			event.global_position = event.position
			event.relative = Vector2(request.get("dx",0),request.get("dy",0))
			event.button_mask = int(request.get("mask",0))
			_send_input(event)
		"mouse_button":
			var event = InputEventMouseButton.new()
			event.position = Vector2(request.get("x",0),request.get("y",0))
			event.global_position = event.position
			event.button_index = int(request.get("button",1))
			event.pressed = bool(request.get("pressed",true))
			event.double_click = bool(request.get("double_click",false))
			_send_input(event)
		"key":
			var event = InputEventKey.new()
			event.keycode = OS.find_keycode_from_string(str(request.get("key","")))
			event.ctrl_pressed = bool(request.get("ctrl",false))
			event.shift_pressed = bool(request.get("shift",false))
			event.pressed = true
			_send_input(event)
			await get_tree().process_frame
			event.pressed = false
			_send_input(event)
		"text":
			for ch in str(request.get("text","")):
				var event = InputEventKey.new()
				event.unicode = ch.unicode_at(0)
				event.pressed = true
				_send_input(event)
				await get_tree().process_frame
				event.pressed = false
				_send_input(event)
		"input_action":
			var action := str(request.get("action",""))
			if not InputMap.has_action(action): _reply(id,{},"Unknown input action"); return
			Input.action_press(action)
			for _frame in range(clampi(int(request.get("frames",1)),1,120)): await get_tree().process_frame
			Input.action_release(action)
		"observe": pass
		_: _reply(id,{},"Supported operations: observe, click, input_action, close"); return
	var delay := clampi(int(request.get("wait_ms",200)),0,10000)
	if delay>0: await get_tree().create_timer(delay/1000.0).timeout
	# Offscreen Windows hosts may suspend frame_post_draw while a native popup is
	# active. Process frames keep input transport responsive in that case too.
	await get_tree().process_frame
	await get_tree().process_frame
	observation_id += 1
	var controls: Array = []
	_collect(get_tree().root,controls)
	var scene := get_tree().current_scene
	var result := {"observation_id":observation_id,"project":ProjectSettings.globalize_path("res://"),"scene":scene.scene_file_path,"viewport":get_viewport().get_visible_rect().size,"controls":controls}
	# Read-only authored scene evidence, alongside the viewport and UI tree.
	if scene.get("state") is RefCounted and scene.state.get("data") is Dictionary:
		result["authored_scene"] = scene.state.data.duplicate(true)
		result["selection"] = scene.state.selected.duplicate(true)
		result["drawing"] = scene.drawing.duplicate(true)
		result["blueprint"] = {"x":scene.blueprint.global_position.x,"y":scene.blueprint.global_position.y,"width":scene.blueprint.size.x,"height":scene.blueprint.size.y,"pan_x":scene.blueprint.pan.x,"pan_y":scene.blueprint.pan.y,"zoom":scene.blueprint.zoom}
	if scene.get("candidates") is Node:
		result["candidate_count"] = scene.candidates.get_child_count()
		result["components"] = []
		for child in scene.candidates.get_children():
			result.components.append({"name":str(child.name),"scene":child.scene_file_path,"meshes":child.find_children("*","MeshInstance3D",true,false).size()})
	var stem := receipt_directory.path_join("observation-%06d" % observation_id)
	if bool(request.get("capture_image",true)):
		var png := get_viewport().get_texture().get_image().save_png_to_buffer()
		var file := FileAccess.open(stem+".png",FileAccess.WRITE)
		if file != null: file.store_buffer(png); file.close()
		result["screenshot_path"] = stem+".png"
		result["image_base64"] = Marshalls.raw_to_base64(png)
	var receipt := FileAccess.open(stem+".json",FileAccess.WRITE)
	if receipt != null:
		var metadata := result.duplicate()
		metadata.erase("image_base64")
		receipt.store_string(JSON.stringify(metadata,"  "))
		receipt.close()
	_reply(id,result)

func _collect(node: Node, result: Array) -> void:
	var start = result.size()
	if node is Control and node.is_visible_in_tree():
		var text := ""
		if node is Label or node is BaseButton or node is LineEdit: text = node.text
		if not text.is_empty():
			var rect: Rect2 = node.get_global_rect()
			result.append({"type":node.get_class(),"text":text,"x":rect.position.x,"y":rect.position.y,"width":rect.size.x,"height":rect.size.y})
		if node is ItemList:
			for index in range(node.item_count):
				var rect: Rect2 = node.get_item_rect(index)
				result.append({"type":"ItemListItem","index":index,"text":node.get_item_text(index),"x":node.global_position.x+rect.position.x,"y":node.global_position.y+rect.position.y,"width":rect.size.x,"height":rect.size.y})
		if node is SpinBox:
			var rect = node.get_global_rect()
			result.append({"type":"SpinBox","value":node.value,"x":rect.position.x,"y":rect.position.y,"width":rect.size.x,"height":rect.size.y})
		if node is TabBar:
			for index in range(node.tab_count):
				var rect = node.get_tab_rect(index)
				result.append({"type":"Tab","text":node.get_tab_title(index),"x":node.global_position.x+rect.position.x,"y":node.global_position.y+rect.position.y,"width":rect.size.x,"height":rect.size.y})
	if node is Control:
		var window = node.get_window()
		if window != get_tree().root and window.is_embedded():
			for index in range(start,result.size()):
				result[index].x += window.position.x
				result[index].y += window.position.y
	for child in node.get_children(true): _collect(child,result)

extends Node
## Gameplay and test fixtures call the same presentation entry point.
const Closeup := preload("res://scenes/components/interaction/EvidenceCloseup.gd")
const InRoomCloseup := preload("res://scenes/components/interaction/InRoomEvidenceCloseup.gd")
const EVIDENCE_KINDS := {"e_b_sleeve": "sleeve", "e_b_drag": "drag", "e_b_water": "water", "e_b_ratchet": "ratchet", "e_b_cloth": "cloth", "e_b_boots": "boots", "e_b_seal": "seal", "e_c_copper": "copper", "e_a_grate":"grille"}
var active: Control
var _active_callback := Callable()
var _active_token := 0
var _next_token := 0
signal event_recorded(event: Dictionary)

func begin(parent: Control, kind: String, callback := Callable(), context: Dictionary = {}) -> bool:
	if is_instance_valid(active): return false
	var closeup := Closeup.new()
	closeup.kind = kind
	closeup.wrist_anchor = context.get("wrist_anchor")
	closeup.anchor_camera = context.get("camera")
	closeup.anchor_container = context.get("container")
	return _start(parent, closeup, callback)


func _start(parent: Control, closeup: Control, callback: Callable) -> bool:
	if not is_instance_valid(parent) or is_instance_valid(active): return false
	_next_token += 1
	var token := _next_token
	_active_token = token
	_active_callback = callback
	active = closeup
	closeup.observed.connect(func(event: Dictionary): event_recorded.emit(event))
	closeup.finished.connect(func(success: bool): _complete(closeup, token, success))
	# 节点被场景切换或读档移除时，也收束本次交互会话。
	closeup.tree_exiting.connect(func(): _complete(closeup, token, false))
	parent.add_child(closeup)
	return true


func _complete(closeup: Control, token: int, success: bool) -> void:
	var callback := _take_active(closeup, token)
	if callback.is_valid(): callback.call(success)


func _take_active(closeup: Control, token: int) -> Callable:
	if token == 0 or token != _active_token or closeup != active: return Callable()
	var callback := _active_callback
	active = null
	_active_callback = Callable()
	_active_token = 0
	return callback

func kind_for(evidence_id: String) -> String:
	return str(EVIDENCE_KINDS.get(evidence_id, ""))

func begin_gameplay(host: Control, kind: String, callback := Callable()) -> bool:
	if is_instance_valid(active): return false
	var presentations = host.get("evidence_presentations")
	if not presentations is Dictionary or not presentations.has(kind) or not is_instance_valid(presentations[kind]): return false
	var was_playing: bool = host.eng.s.playing
	var was_cinematic: bool = host._cine
	host.eng.s.playing = false
	host._cine = true
	var closeup := InRoomCloseup.new()
	closeup.host = host
	closeup.kind = kind
	closeup.checkpoint_return_playing = was_playing
	closeup.checkpoint_return_cinematic = was_cinematic
	var started := _start(host.center, closeup, func(success: bool):
		if is_instance_valid(host):
			host.eng.s.playing = was_playing
			host._cine = was_cinematic
		if callback.is_valid(): callback.call(success))
	if not started:
		host.eng.s.playing = was_playing
		host._cine = was_cinematic
	return started

func handle_return_input(event: InputEvent) -> bool:
	if not is_instance_valid(active) or event.is_echo(): return false
	var right_click: bool = event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed
	if not (right_click or event.is_action_pressed("cancel") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact")):
		return false
	# close() eases the camera back and preserves a completed sample.
	active.close()
	return true

func cancel() -> void:
	finish(false)


func finish(success: bool) -> void:
	var closeup := active
	var token := _active_token
	if token == 0 or closeup != active: return
	var callback := _take_active(closeup, token)
	if is_instance_valid(closeup):
		if closeup.has_method("_restore"): closeup.call("_restore")
		var parent := closeup.get_parent()
		if parent != null: parent.remove_child(closeup)
		closeup.queue_free()
	if callback.is_valid(): callback.call(success)

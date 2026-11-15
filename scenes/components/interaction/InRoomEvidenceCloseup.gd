extends Control
## 正式调查始终使用房间原相机、原世界和已经摆在现场的证物。
var host: Control
var kind := ""
var prop: Node3D
var camera: Camera3D
var _saved_transform := Transform3D.IDENTITY
var _saved_near := 0.05
var _saved_fov := 70.0
var _tween: Tween
var _closing := false
var _ready_for_input := false
var _dragging := false
var _last := Vector2.ZERO
var _has_result := false
var _restored := false
var _close_button: Button
var _saved_visibility: Array = []
signal finished(success: bool)
signal observed(event: Dictionary)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	prop = host.evidence_presentations.get(kind)
	if not is_instance_valid(prop):
		finished.emit(false)
		queue_free()
		return
	camera = host.cam
	_saved_transform = camera.global_transform
	_saved_near = camera.near
	_saved_fov = camera.fov
	_has_result = bool(prop.completed)
	for item in [host.top_bar, host.left_card, host.drawer, host.room_hint, host.det_ring]:
		_hide(item)
	for label in host.room_vp.find_children("*", "Label3D", true, false): _hide(label)
	if host.kitchen != null and host.kitchen.active:
		_hide(host.kitchen._hint)
		_hide(host.kitchen._prompt)
		for item in host.kitchen._items:
			_hide(item.marker)
	if host.opening != null and host.opening.active:
		_hide(host.opening._hint)
		_hide(host.opening._prompt)
		for item in host.opening._items: _hide(item.marker)
	for node in [prop.tool, prop.hand]:
		if is_instance_valid(node):
			_saved_visibility.append([node, node.visible])
			node.visible = true
	_close_button = Button.new()
	_close_button.name = "ReturnFromEvidence"
	_close_button.text = "✓" if _has_result else "×"
	_close_button.position = Vector2(18, 18)
	_close_button.custom_minimum_size = Vector2(44, 44)
	_close_button.pressed.connect(close)
	add_child(_close_button)
	gui_input.connect(_on_input)
	prop.sampled.connect(_on_sampled)
	camera.near = 0.015
	var focus: Vector3 = prop.to_global(prop.get_meta("focus", Vector3.ZERO))
	var offset: Vector3 = prop.global_basis * Vector3(prop.get_meta("camera_offset", Vector3(0.4, 0.5, 1.0)))
	var camera_position := focus + offset
	if host._lowpoly_ok:
		var bounds: Rect2 = host.lowpoly.walk_rect(0.12)
		camera_position.x = clampf(camera_position.x, bounds.position.x, bounds.end.x)
		camera_position.z = clampf(camera_position.z, bounds.position.y, bounds.end.y)
	var target := Transform3D(Basis.IDENTITY, camera_position).looking_at(focus, Vector3.UP)
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(camera, "global_transform", target, 0.85)
	_tween.parallel().tween_property(camera, "fov", 42.0, 0.85)
	observed.emit(_event("anchor"))
	await _tween.finished
	if _closing or not is_inside_tree(): return
	_ready_for_input = true
	observed.emit(_event("closeup"))
	if kind in ["wardrobe", "ratchet", "grille", "seal", "bed", "desk", "lamp", "wash", "window"]: prop.activate()

func _hide(node: Node) -> void:
	if not is_instance_valid(node): return
	_saved_visibility.append([node, node.visible])
	node.visible = false

func _event(phase: String) -> Dictionary:
	return {"kind": kind, "phase": phase, "presentation": "in_room", "camera_id": camera.get_instance_id(),
		"world_id": camera.get_world_3d().get_instance_id(), "prop_id": prop.get_instance_id(),
		"room": str(host.eng.s.room), "time_usec": Time.get_ticks_usec()}

func _on_sampled() -> void:
	_has_result = true
	if is_instance_valid(_close_button): _close_button.text = "✓"
	observed.emit(_event("result"))

func _surface_rect() -> Rect2:
	var focus: Vector3 = prop.to_global(prop.get_meta("focus", Vector3.ZERO))
	var center := camera.unproject_position(focus)
	var distance := maxf(0.1, camera.global_position.distance_to(focus))
	var height := float(camera.get_viewport().size.y)
	var radius := clampf(height * 0.35 / (distance * tan(deg_to_rad(camera.fov) * 0.5)), 55.0, height * 0.4)
	return Rect2(center - Vector2.ONE * radius, Vector2.ONE * radius * 2.0)

func _viewport_point(point: Vector2) -> Vector2:
	return point / size * Vector2(camera.get_viewport().size)

func _on_input(event: InputEvent) -> void:
	if not _ready_for_input or _closing: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed and _surface_rect().has_point(_viewport_point(event.position))
		_last = event.position
	elif event is InputEventMouseMotion and _dragging:
		var area := _surface_rect()
		var point := _viewport_point(event.position)
		var distance: float = event.position.distance_to(_last)
		_last = event.position
		if not area.has_point(point): return
		var normalized := (point - area.position) / area.size
		if kind in ["water", "cloth", "chalk", "drag", "boots"]:
			prop.sweep(distance, (normalized - Vector2.ONE * 0.5) * Vector2(0.8, 0.4))
		elif kind in ["hand", "sleeve", "copper"]:
			prop.align_hand(Vector2((normalized.x - 0.5) * 0.9, 0))
		accept_event()

func close() -> void:
	if _closing or not is_instance_valid(camera): return
	_closing = true
	_ready_for_input = false
	if _tween != null: _tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(camera, "global_transform", _saved_transform, 0.65)
	_tween.parallel().tween_property(camera, "fov", _saved_fov, 0.65)
	await _tween.finished
	_restore()
	observed.emit(_event("return"))
	finished.emit(_has_result)
	queue_free()

func _restore() -> void:
	if _restored: return
	_restored = true
	if _tween != null: _tween.kill()
	if is_instance_valid(camera):
		camera.global_transform = _saved_transform
		camera.near = _saved_near
		camera.fov = _saved_fov
	for item in _saved_visibility:
		if is_instance_valid(item[0]): item[0].visible = item[1]
	if is_instance_valid(prop) and prop.sampled.is_connected(_on_sampled): prop.sampled.disconnect(_on_sampled)

func _exit_tree() -> void:
	_restore()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		close()
		get_viewport().set_input_as_handled()

func test_snapshot() -> Dictionary:
	return {"kind": kind, "presentation": "in_room", "completed": _has_result, "ready": _ready_for_input,
		"prop_id": prop.get_instance_id() if is_instance_valid(prop) else 0,
		"camera_id": camera.get_instance_id() if is_instance_valid(camera) else 0,
		"progress": prop.progress if is_instance_valid(prop) else 0.0}

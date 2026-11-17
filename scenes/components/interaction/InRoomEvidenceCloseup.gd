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
var _gesture_hint: Label
var _drag_origin := Vector2.ZERO
var _hand_start_x := 0.0
var _saved_visibility: Array = []
var checkpoint_return_playing := false
var checkpoint_return_cinematic := false
signal finished(success: bool)
signal observed(event: Dictionary)

func checkpoint_state() -> Dictionary:
	var visibility := {}
	for entry in _saved_visibility:
		if is_instance_valid(entry[0]): visibility[_visibility_key(entry[0])] = entry[1]
	return {"kind": kind, "saved_transform": _saved_transform, "saved_fov": _saved_fov, "saved_near": _saved_near,
		"ready": _ready_for_input, "closing": _closing, "has_result": _has_result, "visibility": visibility,
		"camera": camera.global_transform, "fov": camera.fov,
		"return_playing": checkpoint_return_playing, "return_cinematic": checkpoint_return_cinematic,
		"elapsed": _tween.get_total_elapsed_time() if _tween != null and _tween.is_valid() else 0.85}

func restore_checkpoint(state: Dictionary) -> void:
	if _tween != null: _tween.kill()
	_saved_transform = state.saved_transform
	_saved_fov = float(state.saved_fov)
	_saved_near = float(state.saved_near)
	_has_result = bool(state.has_result)
	_saved_visibility.clear()
	for path in state.visibility:
		var node := _visibility_node(path)
		if node != null: _saved_visibility.append([node, state.visibility[path]])
	camera.global_transform = state.camera
	camera.fov = state.fov
	_dragging = false
	_closing = false
	_ready_for_input = bool(state.ready)
	if _has_result: _on_sampled()
	if bool(state.closing):
		close(maxf(0.01, 0.65 - float(state.elapsed)))
	elif not _ready_for_input:
		var focus: Vector3 = prop.to_global(prop.get_meta("focus", Vector3.ZERO))
		var target := Transform3D(Basis.IDENTITY, _inspection_position(focus)).looking_at(focus, Vector3.UP)
		_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		var remaining := maxf(0.01, 0.85 - float(state.elapsed))
		_tween.tween_property(camera, "global_transform", target, remaining)
		_tween.parallel().tween_property(camera, "fov", float(prop.get_meta("camera_fov", 48.0)), remaining)
		_tween.finished.connect(func():
			_ready_for_input = true
			if kind in ["wardrobe", "ratchet", "grille", "seal", "bed", "desk", "lamp", "wash", "window"] and not prop.completed: prop.activate())
	elif kind in ["wardrobe", "ratchet", "grille", "seal", "bed", "desk", "lamp", "wash", "window"] and not prop.completed:
		prop.activate()

func _visibility_key(node: Node) -> String:
	for key in ["top_bar", "left_card", "drawer", "room_hint", "det_ring"]:
		if host.get(key) == node: return "host:" + key
	for key in ["tool", "hand"]:
		if prop.get(key) == node: return "prop:" + key
	for controller in [host.opening, host.kitchen]:
		if not is_instance_valid(controller) or not controller.active: continue
		for key in ["_hint", "_prompt"]:
			if controller.get(key) == node: return "controller:" + key
		for item in controller._items:
			if item.marker == node: return "item:" + str(item.id)
	if node is Label3D:
		return "label3d:" + str(host.room_vp.find_children("*", "Label3D", true, false).find(node))
	return str(host.get_path_to(node))

func _visibility_node(key: String) -> Node:
	if key.begins_with("host:"): return host.get(key.trim_prefix("host:"))
	if key.begins_with("prop:"): return prop.get(key.trim_prefix("prop:"))
	if key.begins_with("label3d:"):
		var labels: Array = host.room_vp.find_children("*", "Label3D", true, false)
		var index := int(key.trim_prefix("label3d:"))
		return labels[index] if index >= 0 and index < labels.size() else null
	for controller in [host.opening, host.kitchen]:
		if not is_instance_valid(controller) or not controller.active: continue
		if key.begins_with("controller:"): return controller.get(key.trim_prefix("controller:"))
		if key.begins_with("item:"):
			for item in controller._items:
				if str(item.id) == key.trim_prefix("item:"): return item.marker
	return host.get_node_or_null(NodePath(key))

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
	_close_button.text = tr("返回场景")
	_close_button.set_meta("text_category", "prompt")
	_close_button.position = Vector2(18, 18)
	_close_button.custom_minimum_size = Vector2(44, 44)
	_close_button.pressed.connect(close)
	add_child(_close_button)
	_build_gesture_hint()
	gui_input.connect(_on_input)
	prop.sampled.connect(_on_sampled)
	camera.near = 0.015
	var focus: Vector3 = prop.to_global(prop.get_meta("focus", Vector3.ZERO))
	var camera_position := _inspection_position(focus)
	var target := Transform3D(Basis.IDENTITY, camera_position).looking_at(focus, Vector3.UP)
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(camera, "global_transform", target, 0.85)
	_tween.parallel().tween_property(camera, "fov", float(prop.get_meta("camera_fov", 48.0)), 0.85)
	observed.emit(_event("anchor"))
	await _tween.finished
	if _closing or not is_inside_tree(): return
	_ready_for_input = true
	observed.emit(_event("closeup"))
	if kind in ["wardrobe", "ratchet", "grille", "seal", "bed", "desk", "lamp", "wash", "window"]: prop.activate()

func _inspection_position(focus: Vector3) -> Vector3:
	var offset: Vector3 = prop.global_basis.orthonormalized() * Vector3(prop.get_meta("camera_offset", Vector3(0.4, 0.5, 1.0)))
	if host._lowpoly_ok:
		# Wall props face the room interior. Their prefab forward axis can face a wall.
		if kind in ["water", "drag", "boots", "ratchet", "seal", "cloth", "window"]:
			var center: Vector3 = host.lowpoly.to_global(host.lowpoly.center())
			var inward := Vector3(center.x - focus.x, 0, center.z - focus.z).normalized()
			var reach := maxf(Vector2(offset.x, offset.z).length(), 1.25)
			offset = inward * reach + Vector3.UP * maxf(absf(offset.y), 0.65)
			if kind in ["water", "drag", "boots"]:
				# Look down onto floor traces without crossing the doorway leaf or jamb.
				offset = inward * 0.45 + Vector3.UP * 1.8
		var bounds: Rect2 = host.lowpoly.walk_rect(0.38)
		var local: Vector3 = host.lowpoly.to_local(focus + offset)
		local.x = clampf(local.x, bounds.position.x, bounds.end.x)
		local.z = clampf(local.z, bounds.position.y, bounds.end.y)
		return host.lowpoly.to_global(local)
	return focus + offset

func _build_gesture_hint() -> void:
	var text := ""
	if kind in ["water", "cloth", "chalk", "drag", "boots"]: text = "Drag to sample"
	elif kind in ["hand", "sleeve", "copper"]: text = "Drag right to align" if kind == "sleeve" else "Hold to turn wrist"
	if text.is_empty(): return
	_gesture_hint = Label.new()
	_gesture_hint.name = "EvidenceGesture"
	_gesture_hint.text = text
	_gesture_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_gesture_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_gesture_hint.offset_top = -65
	_gesture_hint.offset_bottom = -25
	_gesture_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gesture_hint.add_theme_color_override("font_color", Color("#ffe3a3"))
	_gesture_hint.add_theme_color_override("font_outline_color", Color("#21180f"))
	_gesture_hint.add_theme_constant_override("outline_size", 6)
	add_child(_gesture_hint)

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
	if is_instance_valid(_gesture_hint): _gesture_hint.text = "Collected"
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
		_drag_origin = event.position
		_hand_start_x = prop.hand.position.x if is_instance_valid(prop.hand) else 0.0
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
			var travel: float = (event.position.x - _drag_origin.x) / maxf(size.x * 0.25, 1.0)
			prop.align_hand(Vector2(_hand_start_x + travel, 0))
		accept_event()

func close(duration := 0.65) -> void:
	if _closing or not is_instance_valid(camera): return
	_closing = true
	_ready_for_input = false
	if _tween != null: _tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(camera, "global_transform", _saved_transform, duration)
	_tween.parallel().tween_property(camera, "fov", _saved_fov, duration)
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
		"camera_position": camera.global_position if is_instance_valid(camera) else Vector3.ZERO,
		"camera_forward": -camera.global_basis.z if is_instance_valid(camera) else Vector3.ZERO,
		"camera_is_current": camera.is_current() if is_instance_valid(camera) else false,
		"room_transform": host.lowpoly._root.global_transform if host._lowpoly_ok else Transform3D.IDENTITY,
		"focus_position": prop.to_global(prop.get_meta("focus", Vector3.ZERO)) if is_instance_valid(prop) else Vector3.ZERO,
		"progress": prop.progress if is_instance_valid(prop) else 0.0}

extends Node
## 乙区厨房的动作复演：把“门、拖痕、湿布、棘轮”变成可见动作，再确认先后。
## 仅在首个推演取证足够、且正式厨房漫游中挂起 ded_drag 时接管模态；不改引擎的证物与存档格式。

const Figure := preload("res://scenes/dual_world/ProceduralFigure.gd")
const EXPECTED := ["su_open", "detective_pull", "shen_cloth", "huo_lock"]
const FRAGMENTS := ["huo_lock", "detective_pull", "su_open", "shen_cloth"]
const ACTION_LABELS := {
	"su_open": "苏泠 · 扳门向外",
	"detective_pull": "侦探 · 拉人向内",
	"shen_cloth": "沈鼎 · 湿布塞缝",
	"huo_lock": "霍铎 · 反扣棘轮",
}

var host: Control
var active := false
var _playing := false
var _order: Array[String] = []
var _echoes: Dictionary = {}
var _echo_root: Node3D
var _panel: PanelContainer
var _status: Label
var _order_labels: Array[Label] = []
var _up_buttons: Array[Button] = []
var _down_buttons: Array[Button] = []
var _replay_button: Button
var _confirm_button: Button
var _door_inner := Vector2.ZERO
var _door_outer := Vector2.ZERO


func begin(h: Control, did: String) -> bool:
	if active or did != "ded_drag" or h.kitchen == null or not h.kitchen.active:
		return false
	var progress: Dictionary = h.eng.deduction_progress(did)
	if not bool(progress.get("can_answer", false)):
		return false
	host = h
	active = true
	_order = ["shen_cloth", "su_open", "detective_pull", "huo_lock"]
	var doorway: Dictionary = host._door_for(host.room_mesh.design, host._room_dir("B-P", "R05"))
	if not doorway.is_empty():
		var center3: Vector3 = host.room_mesh.center()
		var center2 := Vector2(center3.x, center3.z)
		var outward: Vector2 = (doorway.outer - doorway.inner).normalized()
		_door_inner = doorway.inner.lerp(center2, 0.45)
		_door_outer = _door_inner + outward * 0.8
	else:
		_door_inner = _evidence_point("e_b_drag")
		_door_outer = _door_inner + Vector2(0.0, -1.0)
	_build_echoes()
	_build_panel()
	_play_fragments()
	return true


func _build_echoes() -> void:
	_echo_root = Node3D.new()
	_echo_root.name = "KitchenMemoryEchoes"
	host.det_root.get_parent().add_child(_echo_root)
	for actor_id in ["su", "detective", "shen", "huo"]:
		var figure: Node3D = Figure.new()
		figure.name = "Echo_" + actor_id
		figure.setup(host.data.actor_by_id[actor_id], host.data.rig_spec.get("poses", {}))
		_echo_root.add_child(figure)
		figure.visible = false
		figure.set_meta("memory_echo", true)
		for part in figure.find_children("*", "GeometryInstance3D", true, false):
			part.transparency = 0.32
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var name_tag := Label3D.new()
		name_tag.text = str(host.data.actor_name(actor_id))
		name_tag.font = host.SANS_FONT
		name_tag.font_size = 30
		name_tag.pixel_size = 0.004
		name_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name_tag.position = Vector3(0.0, 1.65, 0.0)
		name_tag.modulate = Color("#f2e6c8")
		name_tag.outline_size = 10
		name_tag.outline_modulate = Color(0.04, 0.03, 0.02, 0.95)
		name_tag.no_depth_test = true
		figure.add_child(name_tag)
		_echoes[actor_id] = figure


func _build_panel() -> void:
	host._clear_modal()
	var dim := ColorRect.new()
	dim.color = Color(0.015, 0.012, 0.01, 0.28)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	host.modal.add_child(dim)

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_panel.offset_left = -335
	_panel.offset_right = 335
	_panel.offset_top = -270
	_panel.offset_bottom = -18
	_panel.custom_minimum_size = Vector2(670, 252)
	_panel.add_theme_stylebox_override("panel", host._style(Color("#eee4cb"), Color("#b89758"), 10, 10))
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	host.modal.add_child(_panel)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 3)
	_panel.add_child(body)
	var title := Label.new()
	title.text = "脑内复演 · 动作先后"
	title.add_theme_font_override("font", host.SERIF_FONT)
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color("#7a3a24"))
	body.add_child(title)
	_status = Label.new()
	_status.text = "看动作与方向；用 ↑ ↓ 排出先后。"
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color("#5a4a38"))
	body.add_child(_status)

	for i in 4:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		body.add_child(row)
		var up := _arrow_button("↑")
		var line := Label.new()
		line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		line.custom_minimum_size = Vector2(0, 26)
		line.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		line.add_theme_font_size_override("font_size", 15)
		line.add_theme_color_override("font_color", Color("#30291f"))
		var down := _arrow_button("↓")
		row.add_child(up)
		row.add_child(line)
		row.add_child(down)
		_order_labels.append(line)
		_up_buttons.append(up)
		_down_buttons.append(down)
		var row_index := i
		up.pressed.connect(func(): _move_card(row_index, -1))
		down.pressed.connect(func(): _move_card(row_index, 1))

	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	body.add_child(footer)
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_replay_button = Button.new()
	_replay_button.text = "重看动作"
	_replay_button.focus_mode = Control.FOCUS_NONE
	_replay_button.custom_minimum_size = Vector2(104, 30)
	_replay_button.pressed.connect(_play_fragments)
	footer.add_child(_replay_button)
	_confirm_button = Button.new()
	_confirm_button.text = "确认先后"
	_confirm_button.focus_mode = Control.FOCUS_NONE
	_confirm_button.custom_minimum_size = Vector2(112, 30)
	_confirm_button.pressed.connect(_confirm_order)
	footer.add_child(_confirm_button)
	_render_order()
	host.modal.visible = true


func _arrow_button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(36, 25)
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", Color("#30291f"))
	button.add_theme_stylebox_override("normal", host._style(Color("#fbf5e2"), Color("#b89758"), 5, 2))
	button.add_theme_stylebox_override("hover", host._style(Color("#fffaf0"), Color("#7a3a24"), 5, 2))
	return button


func _render_order() -> void:
	for i in _order.size():
		_order_labels[i].text = "%d　%s" % [i + 1, str(ACTION_LABELS[_order[i]])]
		_up_buttons[i].disabled = _playing or i == 0
		_down_buttons[i].disabled = _playing or i == _order.size() - 1
	if _replay_button != null: _replay_button.disabled = _playing
	if _confirm_button != null: _confirm_button.disabled = _playing


func _move_card(index: int, delta: int) -> void:
	var target := index + delta
	if _playing or target < 0 or target >= _order.size():
		return
	var item := _order[index]
	_order.remove_at(index)
	_order.insert(target, item)
	_render_order()


func _play_fragments() -> void:
	if not active or _playing:
		return
	_playing = true
	_render_order()
	_status.text = "动作复演中……"
	for step in FRAGMENTS.size():
		if not active: return
		_status.text = "动作复演　%d / %d" % [step + 1, FRAGMENTS.size()]
		await _perform(FRAGMENTS[step])
		await get_tree().create_timer(0.35).timeout
		for actor in _echoes.values(): actor.visible = false
	_playing = false
	if active:
		_status.text = "看动作与方向；用 ↑ ↓ 排出先后。"
		_render_order()


func _perform(action_id: String) -> void:
	for actor in _echoes.values(): actor.visible = false
	match action_id:
		"su_open":
			var su: Node3D = _echoes.su
			su.visible = true
			su.global_position = _world(_door_inner)
			su.rotation.y = _face(_door_outer - _door_inner)
			su.set_pose("walk")
			await _move_echo(su, _door_outer, "argue")
		"detective_pull":
			var su: Node3D = _echoes.su
			var detective: Node3D = _echoes.detective
			su.visible = true
			detective.visible = true
			su.global_position = _world(_door_outer)
			detective.global_position = _world(_door_outer + (_door_inner - _door_outer) * 0.35)
			detective.set_pose("walk")
			await _move_echo(detective, _door_inner, "argue")
			await _move_echo(su, _door_inner + (_door_inner - _door_outer).normalized() * 0.45, "think")
		"shen_cloth":
			var shen: Node3D = _echoes.shen
			shen.visible = true
			await _move_echo(shen, _evidence_stand("e_b_water"), "work")
		"huo_lock":
			var huo: Node3D = _echoes.huo
			huo.visible = true
			await _move_echo(huo, _evidence_stand("e_b_ratchet"), "work")


func _move_echo(actor: Node3D, target: Vector2, final_pose: String) -> void:
	var destination := _world(target)
	var delta := destination - actor.global_position
	if Vector2(delta.x, delta.z).length() > 0.08:
		actor.rotation.y = atan2(delta.x, delta.z)
		actor.set_pose("walk")
		var tween := create_tween()
		tween.tween_property(actor, "global_position", destination, 0.55).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await tween.finished
	actor.set_pose(final_pose)


func _evidence_point(eid: String) -> Vector2:
	if host.room_mesh.evidence_nodes.has(eid):
		var marker: Node3D = host.room_mesh.evidence_nodes[eid]
		return Vector2(marker.global_position.x, marker.global_position.z)
	return _door_inner


func _evidence_stand(eid: String) -> Vector2:
	var point := _evidence_point(eid)
	var center3: Vector3 = host.room_mesh.center()
	var toward_center := Vector2(center3.x, center3.z) - point
	return point + toward_center.normalized() * 0.75 if toward_center.length() > 0.01 else point


func _world(point: Vector2) -> Vector3:
	return Vector3(point.x, 0.0, point.y)


func _face(direction: Vector2) -> float:
	return atan2(direction.x, direction.y) if direction.length() > 0.001 else 0.0


func _confirm_order() -> void:
	if not active or _playing:
		return
	if _order != EXPECTED:
		_status.text = "顺序还对不上；再看一遍脚印、水痕和锁扣。"
		return
	var picked: Array = []
	for evidence_id in ["e_b_sleeve", "e_b_drag", "e_b_water", "e_b_ratchet"]:
		if host.eng.s.evidence.has(evidence_id): picked.append(evidence_id)
	if picked.size() < 4:
		_status.text = "相关证物未齐；回到现场继续查看。"
		return
	var h := host
	active = false
	_finish_visuals()
	if h.kitchen != null and h.kitchen._order_replay == self: h.kitchen._order_replay = null
	h._dismiss_modal()
	h.eng.solve_deduction("ded_drag", "in", picked)
	queue_free()


func _finish_visuals() -> void:
	if _echo_root != null and is_instance_valid(_echo_root):
		_echo_root.queue_free()
	_echo_root = null


func stop() -> void:
	if not active:
		return
	active = false
	_finish_visuals()
	if host != null and is_instance_valid(host):
		if host.kitchen != null and host.kitchen._order_replay == self: host.kitchen._order_replay = null
		if host.modal.visible: host._dismiss_modal()
	queue_free()

extends Node
## Compact order controls backed by the shared three-stage production performance.
const Reenactment := preload("res://scenes/components/interaction/ReconstructionPerformance.gd")
const EXPECTED := ["su_open","detective_pull","shen_cloth","huo_lock"]
const LABELS := {"su_open":"扳门","detective_pull":"拉回","shen_cloth":"塞布","huo_lock":"反扣"}
var host: Control
var active := false
var _playing := false
var _order: Array[String] = []
var _performance: Node
var _status: Label
var _labels: Array[Label] = []
var _up: Array[Button] = []
var _down: Array[Button] = []
var _replay: Button
var _confirm: Button
signal observed(event: Dictionary)

func begin(h: Control,did: String) -> bool:
	if active or did != "ded_drag" or h.kitchen == null or not h.kitchen.active: return false
	if not bool(h.eng.deduction_progress(did).get("can_answer",false)): return false
	host = h
	active = true
	_order = ["shen_cloth","su_open","detective_pull","huo_lock"]
	_build_panel()
	_performance = Reenactment.new()
	add_child(_performance)
	_performance.observed.connect(func(event: Dictionary): observed.emit(event))
	_performance.finished.connect(_finished)
	_playing = true
	_render()
	_performance.begin(host)
	return true

func _build_panel() -> void:
	host._clear_modal()
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	panel.offset_left = -286
	panel.offset_right = -18
	panel.offset_top = -225
	panel.offset_bottom = -18
	panel.add_theme_stylebox_override("panel",host._style(Color("#eee4cb"),Color("#b89758"),8,10))
	host.modal.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation",4)
	panel.add_child(body)
	_status = Label.new()
	_status.text = ""
	_status.add_theme_color_override("font_color",Color("#5a4a38"))
	body.add_child(_status)
	for index in 4:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",8)
		body.add_child(row)
		var up := _button("↑")
		var down := _button("↓")
		var label := Label.new()
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_color_override("font_color",Color("#30291f"))
		row.add_child(up)
		row.add_child(label)
		row.add_child(down)
		_up.append(up)
		_down.append(down)
		_labels.append(label)
		var at := index
		up.pressed.connect(func(): _move_card(at,-1))
		down.pressed.connect(func(): _move_card(at,1))
	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_END
	footer.add_theme_constant_override("separation",8)
	body.add_child(footer)
	_replay = _button("重看")
	_replay.pressed.connect(_play)
	_confirm = _button("确认")
	_confirm.pressed.connect(_confirm_order)
	footer.add_child(_replay)
	footer.add_child(_confirm)
	host.modal.visible = true

func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(44,29)
	button.add_theme_color_override("font_color",Color("#30291f"))
	button.add_theme_color_override("font_disabled_color",Color("#7a705e"))
	button.add_theme_stylebox_override("normal",host._style(Color("#fbf5e2"),Color("#b89758"),4,3))
	button.add_theme_stylebox_override("disabled",host._style(Color("#e8dec5"),Color("#b89758"),4,3))
	return button

func _render() -> void:
	for index in _order.size():
		_labels[index].text = LABELS[_order[index]]
		_up[index].disabled = _playing or index == 0
		_down[index].disabled = _playing or index == _order.size()-1
	_replay.disabled = _playing
	_confirm.disabled = _playing

func _move_card(index: int,delta: int) -> void:
	var target := index+delta
	if _playing or target<0 or target>=_order.size(): return
	var item := _order[index]
	_order.remove_at(index)
	_order.insert(target,item)
	_status.text = ""
	_render()

func _play() -> void:
	if not active or _playing: return
	_playing = true
	_status.text = ""
	_render()
	_performance.play()

func _finished() -> void:
	if not active: return
	_playing = false
	_status.text = "核对"
	_render()

func _confirm_order() -> void:
	if not active or _playing: return
	if _order != EXPECTED:
		_status.text = "再看"
		return
	var picked: Array = []
	for evidence in ["e_b_sleeve","e_b_drag","e_b_water","e_b_ratchet"]:
		if host.eng.s.evidence.has(evidence): picked.append(evidence)
	if picked.size()<4:
		_status.text = "取证"
		return
	var h := host
	active = false
	_finish()
	if h.kitchen != null and h.kitchen._order_replay == self: h.kitchen._order_replay = null
	h._dismiss_modal()
	h.eng.solve_deduction("ded_drag","in",picked)
	queue_free()

func _finish() -> void:
	if is_instance_valid(_performance): _performance.stop()
	_performance = null

func stop() -> void:
	if not active: return
	active = false
	_finish()
	if is_instance_valid(host):
		if host.kitchen != null and host.kitchen._order_replay == self: host.kitchen._order_replay = null
		if host.modal.visible: host._dismiss_modal()
	queue_free()

func test_snapshot() -> Dictionary:
	return {"active":active,"playing":_playing,"order":_order,"performance":_performance.test_snapshot() if is_instance_valid(_performance) else {}}

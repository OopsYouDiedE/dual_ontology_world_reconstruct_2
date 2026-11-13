extends PanelContainer

signal closed

const Bridge := preload("res://scenes/main/CampaignBridge.cs")
const RoomLibrary := preload("res://scenes/components/world/RoomLibrary.gd")
var bridge: Variant
var paused := false
var speed := 1.0
var elapsed := 0.0
var refresh_elapsed := 0.0
var snapshot: Dictionary = {}
var state: Dictionary = {}
var action_id := ""
var evidence_ids: Array[String] = []
var action_select: OptionButton
var preview: VBoxContainer
var summary: Label
var message: Label
var pages: TabContainer
var knowledge: RichTextLabel
var evidence: RichTextLabel
var memory_map: RichTextLabel
var history: RichTextLabel
var mechanics: RichTextLabel
var notes: TextEdit
var automatic: CheckButton
var first_material: OptionButton
var second_material: OptionButton
var comparison: RichTextLabel
var materials: Array = []
var evidence_revision := -1
var room_select: OptionButton
var room_view: SubViewportContainer
var room_world: Node3D
var room_camera: Camera3D
var room_instance: Node3D
var room_id := ""

func _ready() -> void:
	var background := StyleBoxFlat.new()
	background.bg_color = Color("15191e")
	add_theme_stylebox_override("panel", background)
	bridge = Bridge.new()
	add_child(bridge)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	hide()

func open_campaign(path := "res://assets/data/scenarios/campaign.dv") -> void:
	show()
	var result: Dictionary = JSON.parse_string(bridge.Open(path))
	message.text = "" if result.get("ok", false) else str(result.get("error", "无法打开案件"))
	paused = not result.get("ok", false)
	evidence_revision = -1
	action_id = ""
	evidence_ids.clear()
	elapsed = 0.0
	_refresh(true)

func _button(parent: Node, title: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _build() -> void:
	var column := VBoxContainer.new()
	add_child(column)
	var toolbar := HFlowContainer.new()
	column.add_child(toolbar)
	_button(toolbar, "返回主菜单", _close)
	_button(toolbar, "暂停／继续", func(): paused = not paused)
	var speeds := OptionButton.new()
	for value in [1, 10, 60, 240]: speeds.add_item(str(value) + "×", value)
	speeds.item_selected.connect(func(index): speed = speeds.get_item_id(index))
	toolbar.add_child(speeds)
	automatic = CheckButton.new()
	automatic.text = "侦探自主行动"
	automatic.toggled.connect(func(value): bridge.SetAutomatic(value))
	toolbar.add_child(automatic)
	_button(toolbar, "取消当前行动", func(): message.text = bridge.Cancel())
	_button(toolbar, "保存案件", _save)
	_button(toolbar, "读取案件", _load)
	summary = Label.new()
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(summary)
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	var actions := VBoxContainer.new()
	actions.custom_minimum_size.x = 340
	body.add_child(actions)
	action_select = OptionButton.new()
	action_select.clip_text = true
	action_select.item_selected.connect(_action_changed)
	actions.add_child(action_select)
	_button(actions, "提交所选行动／推演", _submit)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	actions.add_child(scroll)
	preview = VBoxContainer.new()
	preview.custom_minimum_size.x = 325
	scroll.add_child(preview)
	var visual := VBoxContainer.new()
	visual.custom_minimum_size.x = 380
	body.add_child(visual)
	room_select = OptionButton.new()
	room_select.clip_text = true
	room_select.item_selected.connect(func(index): _show_room(room_select.get_item_text(index).split(" · ")[0]))
	visual.add_child(room_select)
	room_view = SubViewportContainer.new()
	room_view.custom_minimum_size = Vector2(380, 290)
	room_view.stretch = true
	visual.add_child(room_view)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	room_view.add_child(viewport)
	room_world = Node3D.new()
	viewport.add_child(room_world)
	room_camera = Camera3D.new()
	room_world.add_child(room_camera)
	room_camera.current = true
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55, -35, 0)
	light.light_energy = 1.2
	room_world.add_child(light)
	var environment := WorldEnvironment.new()
	var room_environment := Environment.new()
	room_environment.background_mode = Environment.BG_COLOR
	room_environment.background_color = Color("29384e")
	room_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	room_environment.ambient_light_color = Color("b8c5d5")
	room_environment.ambient_light_energy = 0.8
	environment.environment = room_environment
	room_world.add_child(environment)
	pages = TabContainer.new()
	pages.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(pages)
	knowledge = _text_page("背包与所知")
	evidence = _text_page("证据与文本")
	var compare_page := VBoxContainer.new()
	compare_page.name = "材料对读"
	pages.add_child(compare_page)
	first_material = OptionButton.new()
	second_material = OptionButton.new()
	first_material.clip_text = true
	second_material.clip_text = true
	compare_page.add_child(first_material)
	compare_page.add_child(second_material)
	_button(compare_page, "逐段比较", _compare)
	comparison = RichTextLabel.new()
	comparison.selection_enabled = true
	comparison.size_flags_vertical = Control.SIZE_EXPAND_FILL
	compare_page.add_child(comparison)
	memory_map = _text_page("记忆地图")
	history = _text_page("对话与回执")
	mechanics = _text_page("推演与结算")
	notes = TextEdit.new()
	notes.name = "个人笔记"
	notes.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	pages.add_child(notes)
	notes.text_changed.connect(func(): bridge.SetNotes(notes.text))
	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	for id in RoomLibrary.catalog():
		room_select.add_item(id + " · 原版房间模型")

func _text_page(title: String) -> RichTextLabel:
	var label := RichTextLabel.new()
	label.name = title
	label.selection_enabled = true
	label.bbcode_enabled = false
	pages.add_child(label)
	return label

func _process(delta: float) -> void:
	if not visible: return
	refresh_elapsed += delta
	if not paused and state.get("active", false):
		elapsed = minf(elapsed + delta * speed, 300.0)
		var slices := 0
		while elapsed >= 1.0 and slices < 50:
			var result: Dictionary = JSON.parse_string(bridge.Step(1.0))
			elapsed -= 1.0
			slices += 1
			if not result.get("ok", false):
				message.text = str(result.get("error", "案件运行失败"))
				paused = true
				break
	if refresh_elapsed >= 0.5:
		refresh_elapsed = 0.0
		_refresh()

func _refresh(reset_notes := false) -> void:
	var parsed: Dictionary = JSON.parse_string(bridge.Observe())
	snapshot = parsed.get("snapshot", {})
	state = parsed.get("status", {})
	automatic.set_pressed_no_signal(bool(snapshot.get("automatic", false)))
	var minute := int(snapshot.get("time", 0))
	var progress: Dictionary = state.get("progress", {})
	summary.text = "%s · %s · 第%d日 %02d:%02d · %s\n%s" % [snapshot.get("label", "案件"), snapshot.get("name", ""), minute / 1440 + 1, minute % 1440 / 60, minute % 60, snapshot.get("room", ""), progress.get("phase", {}).get("description", "")]
	var current_room := str(snapshot.get("room", ""))
	if current_room != room_id: _show_room(current_room)
	var available: Array = snapshot.get("actions", [])
	action_select.clear()
	for action: Dictionary in available:
		action_select.add_item(str(action.label))
		action_select.set_item_metadata(action_select.item_count - 1, action)
		if str(action.id) == action_id: action_select.select(action_select.item_count - 1)
	if available.is_empty():
		action_id = ""
	elif not available.any(func(action): return str(action.id) == action_id):
		_action_changed(0)
	var evidence_count: int = snapshot.get("evidence", []).size()
	if evidence_count != evidence_revision:
		evidence_revision = evidence_count
		if action_select.selected >= 0 and action_select.get_item_metadata(action_select.selected).get("deduction", false):
			var selected_evidence := evidence_ids.duplicate()
			_action_changed(action_select.selected)
			for checkbox in preview.get_children():
				if checkbox is CheckBox and selected_evidence.has(str(checkbox.get_meta("evidence_id", ""))): checkbox.button_pressed = true
	var known_lines: PackedStringArray = []
	for fact: Dictionary in snapshot.get("knowledge", []):
		known_lines.append("%s = %s  [置信 %.2f%s]" % [fact.key, _text(fact.value), fact.confidence, "；冲突" if fact.conflicted else ""])
	knowledge.text = "本人所知；数量、文本和物品交接通过正式行动更新。\n\n" + "\n".join(known_lines)
	var evidence_lines: PackedStringArray = []
	for entry: Dictionary in snapshot.get("evidence", []):
		evidence_lines.append("%s · %.2f · %s\n%s\n来源 %s\n" % [entry.Id, entry.Time, entry.Method, _text(entry.Value), JSON.stringify(entry.Source)])
	evidence.text = "\n".join(evidence_lines)
	materials = snapshot.get("evidence", [])
	var first_id := str(first_material.get_item_metadata(first_material.selected)) if first_material.selected >= 0 else ""
	var second_id := str(second_material.get_item_metadata(second_material.selected)) if second_material.selected >= 0 else ""
	first_material.clear()
	second_material.clear()
	for entry: Dictionary in materials:
		for pick: OptionButton in [first_material, second_material]:
			pick.add_item("%s · %s" % [entry.Id, _text(entry.Value).left(80)])
			pick.set_item_metadata(pick.item_count - 1, str(entry.Id))
		if str(entry.Id) == first_id: first_material.select(first_material.item_count - 1)
		if str(entry.Id) == second_id: second_material.select(second_material.item_count - 1)
	memory_map.text = "本人记忆地图\n%s\n\n当前同室可见人物\n%s\n\n当前可见物件\n%s" % [JSON.stringify(snapshot.get("map", {}), "  "), JSON.stringify(snapshot.get("actors", []), "  "), JSON.stringify(snapshot.get("fixtures", []), "  ")]
	var lines: PackedStringArray = []
	for entry: Dictionary in snapshot.get("narrative", []): lines.append("%s：%s" % [entry.SpeakerLabel, entry.Text])
	for receipt: Dictionary in snapshot.get("receipts", []): lines.append("%.2f · %s · %s" % [receipt.Time, receipt.Action, "完成" if receipt.Committed else receipt.Reason])
	history.text = "\n".join(lines)
	mechanics.text = "%s\n%s\n\n已发生的推演、说服、言灵与策略回执\n%s" % ["阶段已完成" if state.get("completed", false) else "阶段尚未完成", JSON.stringify(progress, "  "), JSON.stringify(snapshot.get("mechanics", []), "  ")]
	for pending: Dictionary in snapshot.get("pending", []):
		if pending.get("host_required", false): mechanics.text += "\n待真实物理宿主完成：" + str(pending.action)
	if reset_notes: notes.text = str(snapshot.get("notes", ""))

func _show_room(identity: String) -> void:
	if identity.is_empty() or not RoomLibrary.available(identity): return
	room_id = identity
	for index in room_select.item_count:
		if room_select.get_item_text(index).begins_with(identity + " ·"):
			room_select.select(index)
			break
	if is_instance_valid(room_instance):
		room_world.remove_child(room_instance)
		room_instance.queue_free()
	room_instance = RoomLibrary.instantiate(identity)
	if room_instance == null: return
	room_world.add_child(room_instance)
	var bounds := AABB()
	var found := false
	for mesh: MeshInstance3D in room_instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_bounds: AABB = mesh.global_transform * mesh.get_aabb()
		if not found: bounds = mesh_bounds; found = true
		else: bounds = bounds.merge(mesh_bounds)
	if not found: bounds = AABB(Vector3.ZERO, Vector3(4, 3, 4))
	var center := bounds.get_center()
	var radius := maxf(bounds.size.length() * 0.7, 3.0)
	room_camera.position = center + Vector3(radius * 0.8, radius * 0.65, radius * 0.8)
	room_camera.look_at(center)

func _text(value: Variant) -> String:
	return value if value is String else JSON.stringify(value)

func _compare() -> void:
	if first_material.selected < 0 or second_material.selected < 0: return
	var first: Dictionary = materials[first_material.selected]
	var second: Dictionary = materials[second_material.selected]
	var before := _text(first.Value).split("\n")
	var after := _text(second.Value).split("\n")
	var lines: PackedStringArray = ["A %s · %s\nB %s · %s" % [first.Id, JSON.stringify(first.Source), second.Id, JSON.stringify(second.Source)]]
	for index in maxi(before.size(), after.size()):
		var left := str(before[index]) if index < before.size() else "[缺段]"
		var right := str(after[index]) if index < after.size() else "[缺段]"
		lines.append("%s %d\nA %s\nB %s\n" % ["一致" if left == right else "差异", index + 1, left, right])
	comparison.text = "\n".join(lines)

func _action_changed(index: int) -> void:
	for child in preview.get_children():
		preview.remove_child(child)
		child.queue_free()
	evidence_ids.clear()
	if index < 0 or index >= action_select.item_count: return
	action_select.select(index)
	var action: Dictionary = action_select.get_item_metadata(index)
	action_id = str(action.id)
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text = str(action.label)
	preview.add_child(label)
	if not action.get("deduction", false): return
	var result: Dictionary = JSON.parse_string(bridge.Preview(action_id))
	if not result.get("ok", false):
		label.text += "\n" + str(result.get("error", "推演不可用"))
		return
	var data: Dictionary = result.preview
	label.text += "\n" + str(data.get("qualification", ""))
	for entry: Dictionary in data.get("evidence", []):
		var checkbox := CheckBox.new()
		checkbox.text = str(entry.label)
		checkbox.disabled = not entry.get("known", false)
		var identity := str(entry.id)
		checkbox.set_meta("evidence_id", identity)
		checkbox.toggled.connect(func(value):
			if value: evidence_ids.append(identity)
			else: evidence_ids.erase(identity))
		preview.add_child(checkbox)
	for rule: Dictionary in data.get("rules", []):
		var rule_label := Label.new()
		rule_label.text = str(rule.label)
		rule_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		preview.add_child(rule_label)

func _submit() -> void:
	if action_id.is_empty(): return
	var action: Dictionary = action_select.get_item_metadata(action_select.selected)
	message.text = bridge.Submit(action_id, JSON.stringify(evidence_ids) if action.get("deduction", false) else "")
	if message.text.is_empty(): message.text = "行动已提交；结果由 Core 在实际耗时后结算。"

func _path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--dv-save-slot="): return "user://sessions/%s/campaign-save.json" % argument.trim_prefix("--dv-save-slot=")
	return "user://campaign-save.json"

func _save() -> void:
	message.text = bridge.Save(_path())
	if message.text.is_empty(): message.text = "案件进度已保存。"

func _load() -> void:
	var result: String = bridge.Load(_path())
	message.text = result
	if result.is_empty():
		paused = true
		_refresh(true)
		message.text = "案件已恢复并暂停。"

func _close() -> void:
	if snapshot.get("started", false): _save()
	hide()
	closed.emit()

func observation() -> Dictionary:
	return {"campaign": true, "paused": paused, "case_snapshot": snapshot, "case_status": state, "status_text": message.text}

func begin_shutdown() -> void:
	paused = true
	if snapshot.get("started", false): _save()

func wait_for_shutdown() -> void:
	await get_tree().process_frame

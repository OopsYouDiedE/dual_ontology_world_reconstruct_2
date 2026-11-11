extends Control

var host: Node
var data: Dictionary = {}
var section := 0
var body: HBoxContainer
var left: VBoxContainer
var right: VBoxContainer
var chosen: Dictionary = {}
var pinned: Dictionary = {}
var note_id := ""
var note_title: LineEdit
var note_text: TextEdit
var note_related: LineEdit
var judgement: OptionButton
var feedback: Label

func bind(main_host: Node) -> void:
	host = main_host

func on_page_shown() -> void:
	data = host.journal() if host != null else {}
	chosen = {}
	pinned = {}
	_render()

func _label(parent: Node, text: String, heading := false) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 30 if heading else 22)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _column(parent: Node) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	parent.add_child(scroll)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 540
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 14)
	scroll.add_child(column)
	return column

func _render() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]: margin.add_theme_constant_override("margin_" + edge, 100)
	margin.add_theme_constant_override("margin_top", 86)
	margin.add_theme_constant_override("margin_bottom", 100)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 20)
	margin.add_child(column)
	_label(column, "人物手记 · " + str(data.get("viewer", "尚未开局")), true)
	var tabs := HBoxContainer.new()
	column.add_child(tabs)
	var titles := ["证据", "背包", "认知与规则", "记忆地图", "笔记", "行动记录"]
	for index in titles.size():
		var tab_index := index
		var button := _button(tabs, titles[index], func(): section = tab_index; chosen = {}; _render())
		button.toggle_mode = true
		button.button_pressed = section == index
	body = HBoxContainer.new()
	body.add_theme_constant_override("separation", 100)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(body)
	left = _column(body)
	right = _column(body)
	if not data.has("time"):
		_label(left, "开始生活后可查阅人物本人取得的证据。")
		return
	match section:
		0: _evidence()
		1: _inventory()
		2: _cognition()
		3: _map()
		4: _notes()
		5: _receipts()

func _key(value: Dictionary) -> String:
	return "%s.%s.%s" % [value.get("Object", ""), value.get("Facet", ""), value.get("Field", "")]

func _evidence() -> void:
	var evidence: Array = data.get("evidence", [])
	if evidence.is_empty(): _label(left, "尚未取得证据。")
	for value: Dictionary in evidence:
		var entry := value
		_button(left, _key(entry.Key) + " · " + str(entry.Time).pad_decimals(1), func(): chosen = entry; _render())
	if chosen.is_empty():
		_label(right, "选择一项证据检视；可固定材料后逐段对读。")
		return
	_label(right, "证据 " + str(chosen.Id), true)
	_label(right, "来源 %s · %s\n时间 %.2f · 置信度 %.2f" % [chosen.Method, JSON.stringify(chosen.Source), chosen.Time, chosen.Confidence])
	_label(right, str(chosen.Value))
	_button(right, "固定材料／对读", func(): pinned = chosen.duplicate(true); _render())
	if not pinned.is_empty():
		_label(right, "对读来源：" + str(pinned.Id), true)
		var first := str(pinned.Value).split("\n")
		var second := str(chosen.Value).split("\n")
		for index in maxi(first.size(), second.size()):
			var before := first[index] if index < first.size() else "[缺段]"
			var after := second[index] if index < second.size() else "[缺段]"
			_label(right, "%s %d\nA %s\nB %s" % ["一致" if before == after else "差异", index + 1, before, after])
	_button(right, "关联到新笔记", func(): section = 4; note_id = ""; _render())

func _inventory() -> void:
	for value: Dictionary in data.get("knowledge", []):
		if value.subject == data.viewer and value.field in ["food", "book"]:
			_label(left, "%s：%s" % ["口粮" if value.field == "food" else "书本", value.fact.Value], true)
	_label(right, "数量来自人物本人所知。交接需通过当前可用行动提交，完成后由 Core 更新。")
	for action: Dictionary in host.journal_actions():
		var selected_action := action
		_button(right, str(action.label), func(): host.journal_submit(str(selected_action.id)); on_page_shown())

func _cognition() -> void:
	for value: Dictionary in data.get("cognition", {}).get("queries", []):
		var entry := value
		_button(left, "%s · %s" % [entry.label, entry.status], func(): chosen = entry; _render())
	if not chosen.is_empty():
		_label(right, str(chosen.label), true)
		_label(right, "状态：" + str(chosen.status))
		_label(right, "证明来源：\n" + JSON.stringify(chosen.get("source"), "  "))
	_label(right, "本人认知声明", true)
	_label(right, JSON.stringify(data.get("rules"), "  "))

func _map() -> void:
	var remembered: Dictionary = data.get("map", {})
	for key in remembered: _label(left, str(key) + "\n" + JSON.stringify(remembered[key]))
	for value: Dictionary in data.get("knowledge", []):
		if value.subject == data.viewer and value.field in ["room", "zone"]: _label(right, value.field + "：" + str(value.fact.Value), true)
	if remembered.is_empty(): _label(left, "尚无记忆地图记录。")
	_label(right, "其余区域未知；此页只展示本人已经记住的地点。")

func _notes() -> void:
	_button(left, "+ 新笔记", func(): note_id = ""; chosen = {}; _render())
	var notes: Variant = data.get("notes", [])
	if notes is Array:
		for value: Dictionary in notes:
			var entry := value
			_button(left, str(entry.title), func(): note_id = str(entry.id); chosen = entry; _render())
	var existing := chosen if chosen.get("id", "") == note_id and not note_id.is_empty() else {}
	note_title = LineEdit.new()
	note_title.placeholder_text = "标题"
	note_title.text = str(existing.get("title", ""))
	right.add_child(note_title)
	note_text = TextEdit.new()
	note_text.custom_minimum_size.y = 300
	note_text.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	note_text.text = str(existing.get("text", ""))
	right.add_child(note_text)
	note_related = LineEdit.new()
	note_related.placeholder_text = "关联证据 ID"
	note_related.text = str(existing.get("related", chosen.get("Id", "")))
	right.add_child(note_related)
	judgement = OptionButton.new()
	for title in ["待证", "倾向为真", "倾向为假"]: judgement.add_item(title)
	judgement.select(int(existing.get("judgement", "0")))
	right.add_child(judgement)
	_button(right, "保存笔记", _save_note)
	feedback = _label(right, "笔记随会话存档保存。个人判断不会改写人物认知。")

func _save_note() -> void:
	if note_id.is_empty(): note_id = Crypto.new().generate_random_bytes(16).hex_encode()
	var result: String = host.journal_save_note(note_title.text, note_text.text, note_related.text, str(judgement.selected), note_id)
	feedback.text = "已记下；请保存会话。" if result.is_empty() else result
	data = host.journal()

func _receipts() -> void:
	for receipt: Dictionary in data.get("receipts", []):
		_label(left, "%s · %s\n%s" % [receipt.Action, "完成" if receipt.Committed else "未完成", receipt.Reason])
	_label(right, "只列出本人的实际行动回执。阶段结果由 Core 结束条件决定。")

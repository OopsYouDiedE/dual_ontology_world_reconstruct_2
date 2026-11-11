extends Control
## 书本检视器中的设置对开页：左页画面、语言与阅读，右页声音与辅助功能。
## 只读写 GameSettings 自动加载，修改立即生效。

const LEFT_ROWS := [
	{"group": "画面"},
	{"section": "graphics", "key": "window_mode", "label": "显示方式", "options": [["windowed", "窗口"], ["fullscreen", "全屏"], ["borderless", "无边框全屏"]]},
	{"section": "graphics", "key": "resolution", "label": "窗口尺寸", "options": [["default", "默认"], ["1280x640", "1280×640"], ["1600x800", "1600×800"], ["1920x960", "1920×960"], ["1280x720", "1280×720"], ["1920x1080", "1920×1080"], ["2560x1440", "2560×1440"]]},
	{"section": "graphics", "key": "ui_scale", "label": "界面缩放", "options": [[0.85, "85%"], [1.0, "100%"], [1.15, "115%"], [1.25, "125%"]]},
	{"section": "graphics", "key": "max_fps", "label": "帧率上限", "options": [[0, "不限"], [30, "30"], [60, "60"], [120, "120"], [144, "144"]]},
	{"section": "graphics", "key": "vsync", "label": "垂直同步", "kind": "bool"},
	{"group": "语言"},
	{"section": "language", "key": "locale", "label": "界面语言", "options": [["zh_CN", "简体中文"], ["ja", "日本語"], ["en", "English"]]},
	{"group": "阅读"},
	{"section": "accessibility", "key": "text_speed", "label": "文字速度", "options": [[0.5, "慢"], [1.0, "标准"], [2.0, "快"], [0.0, "立即"]]},
	{"section": "accessibility", "key": "text_scale", "label": "文字大小", "options": [[1.0, "100%"], [1.25, "125%"], [1.5, "150%"]]},
]
const RIGHT_ROWS := [
	{"group": "声音"},
	{"section": "audio", "key": "master", "label": "总音量", "kind": "range"},
	{"section": "audio", "key": "music", "label": "音乐", "kind": "range"},
	{"section": "audio", "key": "sfx", "label": "音效", "kind": "range"},
	{"section": "audio", "key": "voice", "label": "语音", "kind": "range"},
	{"section": "audio", "key": "page_turn", "label": "翻页声", "kind": "range"},
	{"section": "audio", "key": "mute_unfocused", "label": "切到后台时静音", "kind": "bool"},
	{"group": "辅助"},
	{"section": "accessibility", "key": "reduce_motion", "label": "减少动态效果", "kind": "bool"},
	{"section": "accessibility", "key": "screen_flash", "label": "画面闪光", "kind": "bool"},
	{"section": "accessibility", "key": "high_contrast", "label": "高对比度", "kind": "bool"},
	{"section": "accessibility", "key": "subtitles", "label": "字幕", "kind": "bool"},
]

@onready var left_column: VBoxContainer = $LeftColumn
@onready var right_column: VBoxContainer = $RightColumn
@onready var reset_button: Button = $ResetButton

## 每项：{spec, value_label, slider, toggle}
var _entries: Array[Dictionary] = []
var _settings: Node

func _ready() -> void:
	_settings = get_node_or_null("/root/GameSettings")
	_build(left_column, LEFT_ROWS)
	_build(right_column, RIGHT_ROWS)
	reset_button.pressed.connect(_reset)
	if _settings != null:
		_settings.setting_changed.connect(func(_section, _key, _value): refresh())
	refresh()

## BookUI 翻到本页时调用。
func on_page_shown() -> void:
	refresh()

func refresh() -> void:
	if _settings == null: return
	for entry in _entries:
		var spec: Dictionary = entry.spec
		var value: Variant = _settings.get_value(spec.section, spec.key)
		match str(spec.get("kind", "choice")):
			"range":
				entry.slider.set_value_no_signal(float(value))
				entry.value_label.text = "%d%%" % roundi(float(value) * 100.0)
			"bool":
				entry.toggle.set_pressed_no_signal(bool(value))
				entry.toggle.text = "● 开启" if bool(value) else "○ 关闭"
			_:
				entry.value_label.text = str(spec.options[_option_index(spec, value)][1])

func _build(column: VBoxContainer, rows: Array) -> void:
	for spec: Dictionary in rows:
		if spec.has("group"):
			var group := Label.new()
			group.text = spec.group
			group.theme_type_variation = &"GroupLabel"
			group.custom_minimum_size.y = 46
			group.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			column.add_child(group)
			continue
		var row := HBoxContainer.new()
		row.custom_minimum_size.y = 46
		row.add_theme_constant_override("separation", 8)
		column.add_child(row)
		var label := Label.new()
		label.text = spec.label
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		row.add_child(label)
		var entry := {"spec": spec}
		match str(spec.get("kind", "choice")):
			"range":
				var slider := HSlider.new()
				slider.min_value = 0.0
				slider.max_value = 1.0
				slider.step = 0.05
				slider.custom_minimum_size = Vector2(230, 36)
				slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
				slider.value_changed.connect(func(value: float): _commit(spec, value))
				row.add_child(slider)
				var percent := _value_label(76)
				row.add_child(percent)
				entry.slider = slider
				entry.value_label = percent
			"bool":
				var toggle := Button.new()
				toggle.toggle_mode = true
				toggle.custom_minimum_size = Vector2(150, 40)
				toggle.toggled.connect(func(on: bool): _commit(spec, on))
				row.add_child(toggle)
				entry.toggle = toggle
			_:
				var previous := _step_button("‹")
				var value := _value_label(180)
				var following := _step_button("›")
				previous.pressed.connect(func(): _step(spec, -1))
				following.pressed.connect(func(): _step(spec, 1))
				row.add_child(previous)
				row.add_child(value)
				row.add_child(following)
				entry.value_label = value
		_entries.append(entry)

func _step(spec: Dictionary, direction: int) -> void:
	if _settings == null: return
	var options: Array = spec.options
	var index := posmod(_option_index(spec, _settings.get_value(spec.section, spec.key)) + direction, options.size())
	_commit(spec, options[index][0])

func _commit(spec: Dictionary, value: Variant) -> void:
	if _settings == null: return
	_settings.set_value(spec.section, spec.key, value)
	refresh()

func _option_index(spec: Dictionary, value: Variant) -> int:
	var options: Array = spec.options
	for index in options.size():
		var option: Variant = options[index][0]
		if typeof(option) == TYPE_STRING:
			if str(value) == option: return index
		elif value != null and typeof(value) in [TYPE_INT, TYPE_FLOAT] and is_equal_approx(float(value), float(option)):
			return index
	return 0

func _reset() -> void:
	if _settings == null: return
	var defaults: Dictionary = _settings.defaults()
	for entry in _entries:
		var spec: Dictionary = entry.spec
		if spec.section == "language": continue
		_settings.set_value(spec.section, spec.key, defaults[spec.section][spec.key])
	refresh()

func _value_label(width: float) -> Label:
	var label := Label.new()
	label.custom_minimum_size.x = width
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return label

func _step_button(glyph: String) -> Button:
	var button := Button.new()
	button.text = glyph
	button.custom_minimum_size = Vector2(40, 40)
	return button

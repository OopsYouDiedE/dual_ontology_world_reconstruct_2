extends Node
## 全局游戏设置（自动加载为 GameSettings）：图像 / 语言 / 声音 / 按键 / 辅助功能。
## 持久化到 user://settings.cfg（只写入玩家改过的项，其余跟随默认），启动时读取并立即生效，
## 改动经 setting_changed 通知界面。图像、声音、按键由本脚本直接生效；
## pixel_titles / paper_texture / text_scale / high_contrast / plain_fonts / reduce_motion / screen_flash
## 只存储并发信号，由界面代码消费；text_speed 由 DialogueUI 读取。
## 语言读写转给 GameLocale。
## 无头检查脚本里自动加载缺席时，读取方应经 get_node_or_null("/root/GameSettings") 取用并回退到默认。

signal setting_changed(section: String, key: String, value)
## 按下 settings 动作（F1）。设置页接这个信号打开自己。
signal settings_requested

const SAVE_PATH := "user://settings.cfg"
const CONTROL_BINDINGS_VERSION := 1
const BASE_WINDOW := Vector2i(1440, 900)
const SECTIONS := ["graphics", "language", "audio", "controls", "accessibility", "gameplay"]

## 可改键的动作（显示顺序）。
const CONTROL_ACTIONS := [
	"move_up", "move_down", "move_left", "move_right", "interact",
	"notebook", "manuscript", "campus_map", "wait", "cancel",
	"dialogue_continue", "dialogue_history", "fast_forward",
	"settings", "book_prev", "book_next",
]
## 移动键按物理位置匹配（换键盘布局后 WASD 仍是左手那一排），其余按键帽字符匹配。
const PHYSICAL_ACTIONS := ["move_up", "move_down", "move_left", "move_right"]
const MODIFIER_KEYS := [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]
const BUS_NAMES := {"master": "Master", "music": "Music", "sfx": "Sfx", "voice": "Voice", "page_turn": "PageTurn"}
## 相同按键在不同模式可复用；全局动作不能覆盖这些模式中的按键。
const ACTION_CONTEXTS := {
	"move_up": "world", "move_down": "world", "move_left": "world", "move_right": "world",
	"interact": "world", "manuscript": "world", "campus_map": "world", "wait": "world",
	"notebook": "global", "cancel": "global", "settings": "global",
	"dialogue_continue": "dialogue", "dialogue_history": "dialogue", "fast_forward": "dialogue",
	"book_prev": "book", "book_next": "book",
}
const SAVE_DELAY := 0.4

## 非按键项的规格：type = bool / choice（数值取最近的允许值）/ range / enum（字符串）。
const SPEC := {
	"graphics": {
		"window_mode": {"default": "windowed", "type": "enum", "allowed": ["windowed", "fullscreen", "borderless"]},
		"window_scale": {"default": 1.0, "type": "choice", "allowed": [1.0, 1.5, 2.0]},
		"resolution": {"default": "default", "type": "enum", "allowed": ["default", "1280x640", "1600x800", "1920x960", "1280x720", "1920x1080", "2560x1440"]},
		"ui_scale": {"default": 1.0, "type": "choice", "allowed": [0.85, 1.0, 1.15, 1.25]},
		"vsync": {"default": true, "type": "bool"},
		"max_fps": {"default": 0, "type": "choice", "allowed": [0, 30, 60, 120, 144], "integer": true},
		"pixel_titles": {"default": true, "type": "bool"},
		"paper_texture": {"default": true, "type": "bool"},
		"wall_transparency": {"default": "dither", "type": "enum", "allowed": ["dither", "alpha"]},
	},
	"audio": {
		"master": {"default": 1.0, "type": "range", "min": 0.0, "max": 1.0},
		"music": {"default": 0.8, "type": "range", "min": 0.0, "max": 1.0},
		"sfx": {"default": 0.8, "type": "range", "min": 0.0, "max": 1.0},
		"voice": {"default": 1.0, "type": "range", "min": 0.0, "max": 1.0},
		"page_turn": {"default": 0.75, "type": "range", "min": 0.0, "max": 1.0},
		"mute_unfocused": {"default": false, "type": "bool"},
	},
	"accessibility": {
		"text_scale": {"default": 1.0, "type": "choice", "allowed": [1.0, 1.25, 1.5]},
		"text_speed": {"default": 1.0, "type": "choice", "allowed": [0.5, 1.0, 2.0, 0.0]},
		"reduce_motion": {"default": false, "type": "bool"},
		"high_contrast": {"default": false, "type": "bool"},
		"plain_fonts": {"default": false, "type": "bool"},
		"screen_flash": {"default": true, "type": "bool"},
		"subtitles": {"default": true, "type": "bool"},
	},
	"controls": {
		"mouse_sensitivity": {"default": 1.0, "type": "range", "min": 0.2, "max": 2.5},
		"camera_distance": {"default": 1.0, "type": "choice", "allowed": [0.8, 1.0, 1.3]},
		"wheel_mode": {"default": "zoom", "type": "enum", "allowed": ["zoom", "pages"]},
		"hold_threshold": {"default": 0.4, "type": "range", "min": 0.2, "max": 1.0},
	},
	## 由会话宿主、对白与推演界面消费。设置页仅在宿主声明支持后允许修改。
	"gameplay": {
		"skip_read_only": {"default": true, "type": "bool"},
		"autosave_policy": {"default": "scene", "type": "enum", "allowed": ["off", "chapter", "scene", "event"]},
		"deduction_hints": {"default": "subtle", "type": "enum", "allowed": ["off", "subtle", "standard"]},
	},
}

var _values := {}
## 玩家改过或文件里已有的项（"section/key"）；只有这些写进文件，启动时也只有这些去改窗口/垂直同步/帧率，
## 免得覆盖命令行给的 --resolution、--disable-vsync 之类。
var _explicit := {}
var _default_events := {}
var _unfocused := false
var _save_pending := false
var _loading := true

func _init() -> void:
	# InputMap 此时已载入 project.godot 的 [input]，取它当出厂默认。
	for action in CONTROL_ACTIONS:
		var list: Array = []
		if InputMap.has_action(action):
			for event in InputMap.action_get_events(action):
				list.append(_event_to_dict(event))
		_default_events[action] = list
	for section in SPEC:
		_values[section] = {}
		for key in SPEC[section]:
			_values[section][key] = SPEC[section][key].default

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_load()
	_loading = false
	_apply_startup()
	var locale := _locale_node()
	if locale != null and locale.has_signal("language_changed"):
		locale.language_changed.connect(func(code: String): setting_changed.emit("language", "locale", code))

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT:
			_unfocused = true
			_apply_audio("master")
		NOTIFICATION_APPLICATION_FOCUS_IN:
			_unfocused = false
			_apply_audio("master")
		NOTIFICATION_WM_CLOSE_REQUEST:
			flush()

func _exit_tree() -> void:
	flush()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("settings"):
		settings_requested.emit()

# ==================================================================== query ===

## 出厂默认：{section: {key: value}}。controls 为每个动作一组序列化事件；language 取系统语言。
func defaults() -> Dictionary:
	var result := {}
	for section in SPEC:
		result[section] = {}
		for key in SPEC[section]:
			result[section][key] = SPEC[section][key].default
	result["language"] = {"locale": _system_locale_code()}
	var controls: Dictionary = result.get("controls", {})
	for action in CONTROL_ACTIONS:
		controls[action] = _default_events[action].duplicate(true)
	result["controls"] = controls
	return result

func get_value(section: String, key: String) -> Variant:
	match section:
		"language":
			return current_language() if key == "locale" else null
		"controls":
			if _default_events.has(key):
				var list: Array = []
				for event in action_events(key):
					list.append(_event_to_dict(event))
				return list
			elif not SPEC.get("controls", {}).has(key):
				return null
	if _values.has(section) and _values[section].has(key):
		return _values[section][key]
	return null

## 读取并生效 + 存盘。非法值会被规整到最近的允许值；未知项返回 false。
func set_value(section: String, key: String, value: Variant) -> bool:
	match section:
		"language":
			if key != "locale" or not _locale_codes().has(str(value)): return false
			var locale := _locale_node()
			if locale != null: locale.set_language(str(value))
			else: TranslationServer.set_locale(str(value))
			return true
		"controls":
			if _default_events.has(key):
				if value is Array:
					var events: Array[InputEvent] = []
					for entry in value:
						var event := _dict_to_event(entry, key) if entry is Dictionary else null
						if event != null: events.append(event)
					if events.is_empty(): return false
					_set_action_events(key, events)
					return true
				return false
	if not SPEC.has(section) or not SPEC[section].has(key): return false
	var clean: Variant = _normalize(SPEC[section][key], value)
	_mark(section, key)
	if _values[section][key] == clean and typeof(_values[section][key]) == typeof(clean):
		_save_later()
		return true
	_values[section][key] = clean
	_apply(section, key)
	_save_later()
	setting_changed.emit(section, key, clean)
	return true

func current_language() -> String:
	var locale := _locale_node()
	if locale != null: return locale.current_language()
	var code := TranslationServer.get_locale()
	return "ja" if code.begins_with("ja") else "en" if code.begins_with("en") else "zh_CN"

# ================================================================== controls ===

func action_events(action: String) -> Array[InputEvent]:
	var result: Array[InputEvent] = []
	if InputMap.has_action(action):
		result.assign(InputMap.action_get_events(action))
	return result

## 动作当前所有绑定的短文本，如 "E / Space / Enter"。
func action_text(action: String) -> String:
	var parts: Array[String] = []
	for event in action_events(action):
		parts.append(event_label(event))
	return " / ".join(parts)

## 键鼠与手柄分开显示和修改，改一类时保留另一类的绑定。
func action_device_text(action: String, device_kind: String, compact := false) -> String:
	var parts: Array[String] = []
	for event in action_events(action):
		if _event_device(event) == device_kind:
			parts.append(event_label(event))
	if parts.is_empty(): return "—"
	if compact and parts.size() > 1: return parts[0] + " +%d" % (parts.size() - 1)
	return " / ".join(parts)

func binding_conflicts(action: String, event: InputEvent) -> Array[String]:
	var conflicts: Array[String] = []
	var context: String = str(ACTION_CONTEXTS.get(action, "global"))
	for other: String in CONTROL_ACTIONS:
		if other == action: continue
		var other_context: String = str(ACTION_CONTEXTS.get(other, "global"))
		if context != "global" and other_context != "global" and context != other_context: continue
		for existing: InputEvent in action_events(other):
			if _same_input(existing, event):
				conflicts.append(other)
				break
	return conflicts

## 返回冲突列表，不隐式抢占其它动作；Esc/右键在捕获界面始终用于取消。
func rebind_action(action: String, event: InputEvent, device_kind: String) -> Dictionary:
	if not CONTROL_ACTIONS.has(action) or event == null:
		return {"ok": false, "reason": "invalid"}
	if _event_device(event) != device_kind:
		return {"ok": false, "reason": "device"}
	if event is InputEventKey and _key_identity(event) in MODIFIER_KEYS:
		return {"ok": false, "reason": "modifier"}
	var serial := _event_to_dict(event)
	if serial.is_empty(): return {"ok": false, "reason": "invalid"}
	var clean := _dict_to_event(serial, action)
	if clean == null: return {"ok": false, "reason": "invalid"}
	var conflicts := binding_conflicts(action, clean)
	if not conflicts.is_empty(): return {"ok": false, "reason": "conflict", "conflicts": conflicts}
	var events: Array[InputEvent] = []
	for existing: InputEvent in action_events(action):
		if _event_device(existing) != device_kind: events.append(existing)
	events.append(clean)
	_set_action_events(action, events)
	return {"ok": true, "action": action, "label": event_label(clean)}

func reset_bindings(device_kind := "all") -> void:
	for action: String in CONTROL_ACTIONS:
		var events: Array[InputEvent] = []
		if device_kind != "all":
			for existing: InputEvent in action_events(action):
				if _event_device(existing) != device_kind: events.append(existing)
		for serial: Dictionary in _default_events[action]:
			var event := _dict_to_event(serial, action)
			if event != null and (device_kind == "all" or _event_device(event) == device_kind):
				events.append(event)
		_set_action_events(action, events)

func _event_device(event: InputEvent) -> String:
	return "gamepad" if event is InputEventJoypadButton or event is InputEventJoypadMotion else "keyboard"

## 人读的按键名："Tab"、"E"、"Ctrl+R"、"鼠标左键"。
func event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var code: int = event.keycode
		if code == KEY_NONE:
			code = _logical_keycode(event.physical_keycode)
			if code == KEY_NONE: code = event.physical_keycode
		var label := _key_name(code)
		if code in MODIFIER_KEYS: return label
		var prefix := ""
		if event.ctrl_pressed: prefix += "Ctrl+"
		if event.alt_pressed: prefix += "Alt+"
		if event.shift_pressed: prefix += "Shift+"
		if event.meta_pressed: prefix += "Meta+"
		return prefix + label
	if event is InputEventMouseButton:
		return _mouse_name(event.button_index)
	if event is InputEventJoypadButton:
		return _joy_button_name(event.button_index)
	if event is InputEventJoypadMotion:
		return _joy_axis_name(event.axis, event.axis_value)
	return "" if event == null else event.as_text()

func _joy_button_name(button: int) -> String:
	var names := {
		JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
		JOY_BUTTON_BACK: "View", JOY_BUTTON_START: "Start",
		JOY_BUTTON_LEFT_SHOULDER: "LB", JOY_BUTTON_RIGHT_SHOULDER: "RB",
		JOY_BUTTON_LEFT_STICK: "L3", JOY_BUTTON_RIGHT_STICK: "R3",
	}
	if names.has(button): return str(names[button])
	var arrows := {JOY_BUTTON_DPAD_UP: "↑", JOY_BUTTON_DPAD_DOWN: "↓", JOY_BUTTON_DPAD_LEFT: "←", JOY_BUTTON_DPAD_RIGHT: "→"}
	if arrows.has(button):
		var language := current_language()
		var prefix := "十字键" if language == "zh_CN" else "十字キー" if language == "ja" else "D-pad "
		return prefix + str(arrows[button])
	return "Button %d" % (button + 1)

func _joy_axis_name(axis: int, value: float) -> String:
	if axis == JOY_AXIS_TRIGGER_LEFT: return "LT"
	if axis == JOY_AXIS_TRIGGER_RIGHT: return "RT"
	var language := current_language()
	var left := axis == JOY_AXIS_LEFT_X or axis == JOY_AXIS_LEFT_Y
	var names := {"zh_CN": ["左摇杆", "右摇杆"], "en": ["Left stick ", "Right stick "], "ja": ["左スティック", "右スティック"]}
	var prefix := str(names[language][0 if left else 1])
	var horizontal := axis == JOY_AXIS_LEFT_X or axis == JOY_AXIS_RIGHT_X
	return prefix + (("←" if value < 0.0 else "→") if horizontal else ("↑" if value < 0.0 else "↓"))

func _key_name(code: int) -> String:
	match code:
		KEY_ESCAPE: return "Esc"
		KEY_KP_ENTER: return "KP Enter"
		KEY_SPACE: return "Space"
		KEY_UP: return "↑"
		KEY_DOWN: return "↓"
		KEY_LEFT: return "←"
		KEY_RIGHT: return "→"
	var text := OS.get_keycode_string(code)
	return text if text != "" else "?"

func _mouse_name(button: int) -> String:
	var language := current_language()
	var index: int = {MOUSE_BUTTON_LEFT: 0, MOUSE_BUTTON_RIGHT: 1, MOUSE_BUTTON_MIDDLE: 2, MOUSE_BUTTON_WHEEL_UP: 3,
		MOUSE_BUTTON_WHEEL_DOWN: 4, MOUSE_BUTTON_XBUTTON1: 5, MOUSE_BUTTON_XBUTTON2: 6}.get(button, -1)
	var names := {
		"zh_CN": ["鼠标左键", "鼠标右键", "鼠标中键", "滚轮向上", "滚轮向下", "鼠标侧键 1", "鼠标侧键 2"],
		"en": ["Left Mouse", "Right Mouse", "Middle Mouse", "Wheel Up", "Wheel Down", "Mouse Side 1", "Mouse Side 2"],
		"ja": ["マウス左", "マウス右", "マウス中", "ホイール上", "ホイール下", "マウス側面1", "マウス側面2"],
	}
	if index == -1: return "Mouse %d" % button
	return str(names[language][index])

func _set_action_events(action: String, events: Array) -> void:
	if not InputMap.has_action(action): InputMap.add_action(action, 0.5)
	InputMap.action_erase_events(action)
	var serial: Array = []
	for event in events:
		InputMap.action_add_event(action, event)
		serial.append(_event_to_dict(event))
	if serial == _default_events[action]:
		_explicit.erase("controls/" + action)
	else:
		_explicit["controls/" + action] = true
	_save_later()
	setting_changed.emit("controls", action, serial)

# ----------------------------------------------------------- event <-> data ---

func _event_to_dict(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		return {"type": "key", "keycode": int(event.keycode), "physical_keycode": int(event.physical_keycode),
			"ctrl": event.ctrl_pressed, "shift": event.shift_pressed, "alt": event.alt_pressed, "meta": event.meta_pressed}
	if event is InputEventMouseButton:
		return {"type": "mouse", "button": int(event.button_index),
			"ctrl": event.ctrl_pressed, "shift": event.shift_pressed, "alt": event.alt_pressed, "meta": event.meta_pressed}
	if event is InputEventJoypadButton:
		return {"type": "joy_button", "button": int(event.button_index)}
	if event is InputEventJoypadMotion and absf(event.axis_value) >= 0.25:
		return {"type": "joy_axis", "axis": int(event.axis), "value": -1.0 if event.axis_value < 0.0 else 1.0}
	return {}

## 序列化数据 → 事件。移动动作只存物理键，其它动作只存键帽字符，这样与 project.godot 默认一致、测试合成的按键也能匹配。
func _dict_to_event(data: Dictionary, action: String) -> InputEvent:
	match str(data.get("type", "")):
		"key":
			var event := InputEventKey.new()
			var code := int(data.get("keycode", 0))
			var physical := int(data.get("physical_keycode", 0))
			if code == KEY_NONE and physical == KEY_NONE: return null
			if PHYSICAL_ACTIONS.has(action):
				event.physical_keycode = (physical if physical != KEY_NONE else code) as Key
			else:
				if code == KEY_NONE:
					code = _logical_keycode(physical)
					if code == KEY_NONE: code = physical
				event.keycode = code as Key
			if not (code in MODIFIER_KEYS or physical in MODIFIER_KEYS):
				event.ctrl_pressed = bool(data.get("ctrl", false))
				event.shift_pressed = bool(data.get("shift", false))
				event.alt_pressed = bool(data.get("alt", false))
				event.meta_pressed = bool(data.get("meta", false))
			return event
		"mouse":
			var event := InputEventMouseButton.new()
			var button := int(data.get("button", 0))
			if button <= 0: return null
			event.button_index = button as MouseButton
			event.ctrl_pressed = bool(data.get("ctrl", false))
			event.shift_pressed = bool(data.get("shift", false))
			event.alt_pressed = bool(data.get("alt", false))
			event.meta_pressed = bool(data.get("meta", false))
			return event
		"joy_button":
			var button := int(data.get("button", -1))
			if button < 0 or button >= JOY_BUTTON_MAX: return null
			var event := InputEventJoypadButton.new()
			event.device = -1
			event.button_index = button as JoyButton
			return event
		"joy_axis":
			var axis := int(data.get("axis", -1))
			var value := float(data.get("value", 0.0))
			if axis < 0 or axis >= JOY_AXIS_MAX or is_zero_approx(value): return null
			var event := InputEventJoypadMotion.new()
			event.device = -1
			event.axis = axis as JoyAxis
			event.axis_value = -1.0 if value < 0.0 else 1.0
			return event
	return null

func _same_input(a: InputEvent, b: InputEvent) -> bool:
	if a is InputEventKey and b is InputEventKey:
		return _key_identity(a) == _key_identity(b) and a.get_modifiers_mask() == b.get_modifiers_mask()
	if a is InputEventMouseButton and b is InputEventMouseButton:
		return a.button_index == b.button_index and a.get_modifiers_mask() == b.get_modifiers_mask()
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return a.button_index == b.button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		return a.axis == b.axis and signf(a.axis_value) == signf(b.axis_value)
	return false

## 同一个键不论用键帽字符还是物理位置记录，都化成键帽字符比较。
func _key_identity(event: InputEventKey) -> int:
	if event.keycode != KEY_NONE: return event.keycode
	var code := _logical_keycode(event.physical_keycode)
	return code if code != KEY_NONE else event.physical_keycode

# ==================================================================== apply ===

func _normalize(spec: Dictionary, value: Variant) -> Variant:
	match str(spec.type):
		"bool":
			return bool(value)
		"enum":
			return value if spec.allowed.has(value) else spec.default
		"range":
			return clampf(float(value), float(spec.min), float(spec.max))
		"choice":
			var best: float = float(spec.allowed[0])
			for option in spec.allowed:
				if absf(float(option) - float(value)) < absf(best - float(value)):
					best = float(option)
			return int(best) if spec.get("integer", false) else best
	return value

func _apply_startup() -> void:
	for key in SPEC.audio:
		_apply_audio(key)
	if _is_explicit("graphics", "window_mode") or _is_explicit("graphics", "window_scale") or _is_explicit("graphics", "resolution"):
		_apply("graphics", "window_mode")
	if _is_explicit("graphics", "vsync"): _apply("graphics", "vsync")
	if _is_explicit("graphics", "max_fps"): _apply("graphics", "max_fps")

func _apply(section: String, key: String) -> void:
	match section:
		"graphics":
			match key:
				"window_mode", "window_scale", "resolution": _apply_window()
				"vsync":
					if not _headless():
						DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if _values.graphics.vsync else DisplayServer.VSYNC_DISABLED)
				"max_fps":
					Engine.max_fps = int(_values.graphics.max_fps)
		"audio":
			_apply_audio("master" if key == "mute_unfocused" else key)

func _apply_window() -> void:
	if "--authoring-minimized" in OS.get_cmdline_user_args() or "--dv-background-capture" in OS.get_cmdline_user_args(): return
	if not "--dv-visible-window" in OS.get_cmdline_user_args():
		for argument in OS.get_cmdline_user_args():
			if argument.begins_with("--dv-mcp-port="):
				get_window().mode = Window.MODE_MINIMIZED
				return
	if _headless(): return
	match str(_values.graphics.window_mode):
		"fullscreen":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			# 退出全屏后窗口尺寸要等一帧才恢复，下一帧再定尺寸与位置。
			call_deferred("_apply_windowed_size")

func _apply_windowed_size() -> void:
	if _headless() or DisplayServer.window_get_mode() != DisplayServer.WINDOW_MODE_WINDOWED: return
	var target := windowed_size()
	var screen := DisplayServer.window_get_current_screen()
	var usable := DisplayServer.screen_get_usable_rect(screen)
	if DisplayServer.window_get_size() == target: return
	DisplayServer.window_set_size(target)
	DisplayServer.window_set_position(usable.position + (usable.size - target) / 2)

## 窗口化时的客户区大小：基准 1600×800 乘倍数，装不进当前屏幕可用区域（含标题栏）时按比例缩小。
func windowed_size() -> Vector2i:
	var scale := float(_values.graphics.window_scale)
	var wanted := Vector2(BASE_WINDOW) * scale
	var resolution: String = str(_values.graphics.resolution)
	if resolution != "default":
		var parts := resolution.split("x")
		if parts.size() == 2: wanted = Vector2(float(parts[0]), float(parts[1]))
	if _headless(): return Vector2i(wanted)
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var frame := DisplayServer.window_get_size_with_decorations() - DisplayServer.window_get_size()
	var room := Vector2(usable.size - frame)
	var fit := minf(1.0, minf(room.x / wanted.x, room.y / wanted.y))
	return Vector2i((wanted * maxf(fit, 0.25)).floor())

func _apply_audio(key: String) -> void:
	if not BUS_NAMES.has(key): return
	var bus := AudioServer.get_bus_index(BUS_NAMES[key])
	if bus == -1: return
	var volume := float(_values.audio[key])
	AudioServer.set_bus_volume_db(bus, linear_to_db(volume) if volume > 0.0 else -80.0)
	var muted := volume <= 0.0
	if key == "master" and bool(_values.audio.mute_unfocused) and _unfocused: muted = true
	AudioServer.set_bus_mute(bus, muted)

## 缺总线时补上（正常由 default_bus_layout.tres 提供），都挂在 Master 下。
func _ensure_buses() -> void:
	for bus_name in ["Music", "Sfx", "Voice", "PageTurn"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var index := AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus_name)
			AudioServer.set_bus_send(index, "Sfx" if bus_name == "PageTurn" else "Master")

## 物理键位对应的当前布局下的键帽字符（无头显示服务器不支持，原样返回）。
func _logical_keycode(physical: int) -> int:
	if _headless() or physical == KEY_NONE: return physical
	return DisplayServer.keyboard_get_keycode_from_physical(physical as Key)

func _headless() -> bool:
	return DisplayServer.get_name() == "headless"

# ===================================================================== save ===

func _mark(section: String, key: String) -> void:
	_explicit[section + "/" + key] = true

func _is_explicit(section: String, key: String) -> bool:
	return _explicit.has(section + "/" + key)

func _save_later() -> void:
	if _loading or _save_pending or not is_inside_tree(): return
	_save_pending = true
	get_tree().create_timer(SAVE_DELAY, true, false, true).timeout.connect(flush)

## 立即写盘（连续拖动滑块时合并写入，退出时也会调用）。
func flush() -> void:
	_save_pending = false
	var file := ConfigFile.new()
	for section in SPEC:
		for key in SPEC[section]:
			if _is_explicit(section, key): file.set_value(section, key, _values[section][key])
	for action in CONTROL_ACTIONS:
		if _is_explicit("controls", action):
			file.set_value("controls", "bindings_version", CONTROL_BINDINGS_VERSION)
			var serial: Array = []
			for event in action_events(action): serial.append(_event_to_dict(event))
			file.set_value("controls", action, serial)
	if file.get_sections().is_empty():
		if FileAccess.file_exists(SAVE_PATH): DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
		return
	file.save(SAVE_PATH)

func _load() -> void:
	var file := ConfigFile.new()
	if file.load(SAVE_PATH) != OK: return
	for section in SPEC:
		for key in SPEC[section]:
			if file.has_section_key(section, key):
				_values[section][key] = _normalize(SPEC[section][key], file.get_value(section, key))
				_mark(section, key)
	for action in CONTROL_ACTIONS:
		if not file.has_section_key("controls", action): continue
		var stored: Variant = file.get_value("controls", action)
		if stored is not Array: continue
		var events: Array[InputEvent] = []
		for entry in stored:
			var event := _dict_to_event(entry, action) if entry is Dictionary else null
			if event != null: events.append(event)
		if events.is_empty(): continue
		# Earlier settings could store keyboard/mouse only. Preserve those edits
		# while adding the newly shipped controller bindings exactly once.
		if int(file.get_value("controls", "bindings_version", 0)) < CONTROL_BINDINGS_VERSION:
			for entry: Dictionary in _default_events[action]:
				if str(entry.get("type", "")) not in ["joy_button", "joy_axis"]: continue
				var candidate := _dict_to_event(entry, action)
				if candidate == null: continue
				var duplicate := false
				for existing: InputEvent in events:
					if _same_input(existing, candidate): duplicate = true
				if not duplicate: events.append(candidate)
		InputMap.action_erase_events(action)
		for event in events: InputMap.action_add_event(action, event)
		_mark("controls", action)

# ==================================================================== locale ===

func _locale_node() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	return tree.root.get_node_or_null("GameLocale") if tree else null

func _locale_codes() -> Array:
	var locale := _locale_node()
	return locale.LANGUAGES if locale != null else ["zh_CN", "en", "ja"]

func _system_locale_code() -> String:
	var system := OS.get_locale()
	return "ja" if system.begins_with("ja") else "en" if system.begins_with("en") else "zh_CN"

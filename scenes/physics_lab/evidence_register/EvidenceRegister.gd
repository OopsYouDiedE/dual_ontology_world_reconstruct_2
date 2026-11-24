extends Node3D
const Rules = preload("res://scenes/physics_lab/evidence_register/RegisterRules.gd")
const Room = preload("res://scenes/physics_lab/evidence_register/RegisterRoom.gd")
const PREFIX := "register_"
const KEYS := {"survey": KEY_1, "drawer": KEY_2, "proof": KEY_3, "threshold": KEY_4, "take_prism": KEY_Q,
	"take_wax": KEY_W, "send": KEY_E, "sun": KEY_Z, "moon": KEY_X, "show": KEY_F, "release": KEY_U,
	"override": KEY_O, "brace": KEY_B, "file": KEY_ENTER, "reset": KEY_R, "plate": KEY_TAB, "optics": KEY_V}
const GILT := Color("ecc791")
const PAPER := Color("e8e4d8")
const FAINT := Color("b0bec6")
const RED := Color("ff9482")
const GOOD := Color("a8deb4")
const STATION_NAMES := {"survey": "01  Survey", "drawer": "02  Drawer", "proof": "03  Proof", "threshold": "04  Threshold"}
const TASK := {"survey": "Both samples carry the same mark. Wax copies the stamp; only amber throws a gold return.",
	"drawer": "A blind slide takes 30 ticks. Match the Clerk's receipt on the dial. You can test the hood by raising the slide here.",
	"proof": "Pull the slide into the shared light. The Clerk needs 40 uninterrupted ticks of live evidence to revise the manual.",
	"threshold": "Stamp after the latch settles and any warning clears. During an override warning, fit the brace before the shutter falls."}
var rules: Rules
var room := Room.new()
var actions: Array[String] = []
var gui: Control
var plate_label: Label
var desk_label: Label
var premise: Label
var receipt_label: Label
var rule_label: Label
var latch_label: Label
var sight_label: Label
var report: Label
var pressure_label: Label
var meter: ProgressBar
var action_buttons: Dictionary = {}
var station_buttons: Dictionary = {}
var serif: SystemFont
var initial_plate := 0
var last_draw_key := ""


func _ready() -> void:
	for id: String in KEYS:
		var action := StringName(PREFIX + id)
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = KEYS[id]
		InputMap.action_add_event(action, key)
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--register-plate="):
			initial_plate = clampi(arg.get_slice("=", 1).to_int(), 1, 2) - 1
	Engine.physics_ticks_per_second = Rules.TICK_RATE
	rules = Rules.new(initial_plate)
	get_viewport().msaa_3d = Viewport.MSAA_2X
	get_viewport().scaling_3d_scale = 1.0
	room.make(self)
	_build_gui()
	get_viewport().size_changed.connect(_layout_markers)
	_layout_markers()
	_refresh()


func _input(event: InputEvent) -> void:
	for id: String in KEYS:
		if event.is_action_pressed(StringName(PREFIX + id)):
			_queue(id)
			get_viewport().set_input_as_handled()
			return


func _queue(id: String) -> void:
	if actions.size() < 12: actions.append(id)


func _physics_process(_delta: float) -> void:
	var id: String = actions.pop_front() if not actions.is_empty() else ""
	if id == "reset" or id == "plate":
		var plate := rules.trial + (1 if id == "plate" else 0)
		var optic := rules.optics
		rules = Rules.new(plate)
		rules.optics = optic
		actions.clear()
	else:
		rules.step(id)
	_refresh()


func mcp_observe() -> Dictionary:
	var data := rules.observe()
	data["visible_instruction"] = TASK[rules.station]
	data["available_buttons"] = _context_actions(rules.station).map(func(id): return PREFIX + id) if rules.outcome.is_empty() else []
	var viewport := get_viewport()
	var size := viewport.get_visible_rect().size
	data["render"] = {
		"renderer": RenderingServer.get_current_rendering_method(), "window_backend": DisplayServer.get_name(),
		"viewport_size": [int(size.x), int(size.y)], "scaling_3d_scale": viewport.scaling_3d_scale,
		"msaa_samples": [1, 2, 4, 8][viewport.msaa_3d],
		"ink_opacity": (room.ink.material_override as ShaderMaterial).get_shader_parameter("opacity"),
		"sdfgi_enabled": room.world_env.environment.sdfgi_enabled,
		"atmosphere_baseline": Room.HALL_ATMOSPHERE.resource_path, "opaque_shader": Room.FINISH.resource_path,
	}
	return data


func _style(color: Color, edge: Color, radius: int = 6) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = edge
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	return style


func _label(parent: Control, text: String, font_size: int, color: Color, wrap := false, use_serif := false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color",color)
	label.add_theme_font_size_override("font_size",font_size)
	if use_serif: label.add_theme_font_override("font",serif)
	if wrap: label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _rule(parent: Control) -> void:
	var band := ColorRect.new()
	band.color = Color("56626a")
	band.custom_minimum_size.y = 1
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(band)


func _button(parent: Control, title: String, id: String, size: int = 13) -> Button:
	var b := Button.new()
	b.text = title
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size.y = 28
	b.add_theme_font_size_override("font_size",size)
	b.add_theme_stylebox_override("normal",_style(Color("283946"),Color("53636d"),4))
	b.add_theme_stylebox_override("hover",_style(Color("425b69"),GILT,4))
	b.add_theme_stylebox_override("pressed",_style(Color("455a60"),GILT,4))
	b.add_theme_color_override("font_color",PAPER)
	b.pressed.connect(_queue.bind(id))
	parent.add_child(b)
	return b


func _build_gui() -> void:
	serif = SystemFont.new()
	serif.font_names = PackedStringArray(["Georgia", "Liberation Serif"])
	var canvas := CanvasLayer.new()
	add_child(canvas)
	gui = Control.new()
	gui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(gui)
	gui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var header := VBoxContainer.new()
	header.position = Vector2(29,19)
	header.add_theme_constant_override("separation",1)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	gui.add_child(header)
	_label(header,"THE SLEEPING ACADEMY     /     MECHANISM STUDIES",13,GILT)
	_label(header,"Evidence Register",47,PAPER,false,true)
	_label(header,"A blind handoff and a rule tested in plain sight",15,FAINT)
	var side := PanelContainer.new()
	gui.add_child(side)
	side.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	side.offset_left = -378
	side.offset_right = -23
	side.offset_top = 22
	var panel_style := _style(Color("1a2632"),Color("67727b"),8)
	panel_style.content_margin_left = 17
	panel_style.content_margin_right = 17
	panel_style.content_margin_top = 13
	panel_style.content_margin_bottom = 13
	panel_style.shadow_color = Color(0.025,0.04,0.065,0.45)
	panel_style.shadow_size = 7
	side.add_theme_stylebox_override("panel",panel_style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation",6)
	side.add_child(column)
	plate_label = _label(column,"",12,GILT)
	desk_label = _label(column,"",29,PAPER,false,true)
	premise = _label(column,"",15,PAPER,true)
	premise.custom_minimum_size.y = 67
	_rule(column)
	receipt_label = _label(column,"",14,FAINT,true)
	rule_label = _label(column,"",15,PAPER,true)
	rule_label.custom_minimum_size.y = 40
	latch_label = _label(column,"",14,PAPER,true)
	sight_label = _label(column,"",13,GILT,true)
	meter = ProgressBar.new()
	meter.custom_minimum_size.y = 5
	meter.show_percentage = false
	meter.max_value = 1.0
	meter.add_theme_stylebox_override("background",_style(Color("2a3542"),Color("2a3542"),3))
	meter.add_theme_stylebox_override("fill",_style(GILT,GILT,3))
	column.add_child(meter)
	pressure_label = _label(column,"",14,FAINT,true)
	_rule(column)
	var choices := GridContainer.new()
	choices.columns = 2
	choices.add_theme_constant_override("h_separation",6)
	choices.add_theme_constant_override("v_separation",5)
	column.add_child(choices)
	var names := {"take_prism": "Q   Take amber", "take_wax": "W   Take wax", "send": "E   Send sample", "sun": "Z   Set SUN",
		"moon": "X   Set MOON", "show": "F   Raise / lower", "release": "U   Request release", "override": "O   Force latch",
		"brace": "B   Fit brace", "file": "Enter   Stamp case"}
	for id: String in names:
		action_buttons[id] = _button(choices,names[id],id)
		action_buttons[id].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rule(column)
	_label(column,"LATEST RECEIPT",11,GILT)
	report = _label(column,"",15,PAPER,true)
	report.custom_minimum_size.y = 67
	var meta := HBoxContainer.new()
	meta.add_theme_constant_override("separation",6)
	column.add_child(meta)
	for item in [["V  Sight", "optics"], ["Tab  Swap plate", "plate"], ["R  Reset", "reset"]]:
		var b := _button(meta,item[0],item[1],12)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for id: String in STATION_NAMES:
		var b := _button(gui,STATION_NAMES[id],id,14)
		b.toggle_mode = true
		station_buttons[id] = b
	var footer := _label(gui,"01–04   MOVE STATIONS     /     BLUE RUNNER · AMBER CLERK",13,FAINT)
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	footer.offset_left = 29
	footer.offset_right = 590
	footer.offset_top = -37
	footer.offset_bottom = -15


func _layout_markers() -> void:
	var shifts := {"survey": Vector2(-57, 18), "drawer": Vector2(-55,-29), "proof": Vector2(-47,34), "threshold": Vector2(-58,35)}
	for id: String in station_buttons:
		var world: Vector3 = Rules.STATIONS[id]
		var b: Button = station_buttons[id]
		b.position = room.camera.unproject_position(world) + shifts[id]


func _context_actions(id: String) -> Array:
	match id:
		"survey": return ["take_prism", "take_wax"]
		"drawer": return ["send", "show", "sun", "moon", "release", "override"]
		"proof": return ["show", "sun", "moon", "release", "override"]
		"threshold": return ["brace", "file"]
	return []


func _refresh() -> void:
	room.render(rules)
	var handoff := maxi(0,rules.arrives - rules.tick)
	var warning := maxi(0,rules.panic_at - rules.tick)
	var walk := maxi(0,rules.walking_until - rules.tick)
	var draw_key := "%s:%s:%s:%s:%s:%s:%s:%s:%s" % [rules.trial,rules.station,rules.audit.back().tick,handoff,warning,walk,
		rules.proof_ticks,rules.stamp_ready(), rules.optics]
	if draw_key == last_draw_key: return
	last_draw_key = draw_key
	plate_label.text = "REGISTER  /  PLATE %02d                                    60 HZ" % (rules.trial + 1)
	desk_label.text = STATION_NAMES[rules.station] if rules.outcome.is_empty() else rules.outcome.capitalize() + " filing"
	premise.text = TASK[rules.station] if rules.outcome.is_empty() else "Case closed. Reset to repeat this plate, or swap the mark and run a counterfactual."
	var receipt := "—" if rules.received.is_empty() else rules.mark().to_upper()
	if handoff > 0: receipt = "IN TRANSIT · %02dt" % handoff
	receipt_label.text = "Receipt: %s    /    Dial: %s    /    Hand: %s" % [receipt,rules.dial.to_upper() if rules.dial != "" else "—",rules.held.capitalize() if rules.held != "" else "—"]
	rule_label.text = "III · Sealed registers stay shut." if rules.manual.edition == "III" else "IV · Admit the witnessed live sample with a matching receipt."
	var latch_text := "Open · stamp ready" if rules.stamp_ready() else ("Open · settling" if rules.latch_at >= 0 else ("Jammed" if rules.panic_fired else "Sealed"))
	if warning > 0 and rules.latch_at >= 0: latch_text = "Open · warning active"
	latch_label.text = "Latch: %s" % latch_text + (" · brace fitted" if rules.braced else "")
	sight_label.text = "Clerk's sight: %02d/27 rays    ·    Proof: %02d/40t" % [rules.sample_rays,rules.proof_ticks]
	meter.value = float(rules.proof_ticks) / Rules.PROOF
	pressure_label.text = "Pressure debt: %d" % rules.debt + ("   /   SHUTTER IN %03dt" % warning if warning > 0 else "")
	pressure_label.add_theme_color_override("font_color",RED if warning > 0 else FAINT)
	report.text = rules.message
	report.add_theme_color_override("font_color",GOOD if not rules.outcome.is_empty() else PAPER)
	for id: String in action_buttons:
		action_buttons[id].visible = rules.outcome.is_empty() and _context_actions(rules.station).has(id)
	for id: String in station_buttons:
		station_buttons[id].set_pressed_no_signal(rules.station == id)

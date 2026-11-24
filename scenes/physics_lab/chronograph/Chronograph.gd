extends "ChronographRoom.gd"

const Ink := preload("res://scenes/components/rendering/post/InkPass.gd")
const HallAtmosphere := preload("res://scenes/components/rendering/post/Hall04.tres")
const INPUTS := {"north": KEY_W, "south": KEY_S, "west": KEY_A, "east": KEY_D,
	"use": KEY_E, "wait": KEY_SPACE, "reset": KEY_R, "view": KEY_TAB, "look": KEY_L}
const VIEWS := [Vector3(10, 15, 14), Vector3(-9, 16, 15), Vector3(7, 26, 10)]
var camera: Camera3D
var model := Rules.new()
var view_index := 0
var subtitle: Label
var status: Label
var action_help: Label
var facts: Label
var instrument: Label
var controls: Label
var ink: MeshInstance3D


func _ready() -> void:
	for command: String in INPUTS:
		var action := "chrono_" + command
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		var key := InputEventKey.new()
		key.physical_keycode = INPUTS[command]
		InputMap.action_add_event(action, key)
	world = WorldEnvironment.new()
	world.environment = HallAtmosphere.duplicate() as Environment
	add_child(world)
	keylight = DirectionalLight3D.new()
	keylight.shadow_enabled = true
	keylight.light_angular_distance = 1.2
	add_child(keylight)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	add_child(camera)
	if RenderingServer.get_current_rendering_method() == &"forward_plus":
		ink = Ink.create()
		ink.material_override.set_shader_parameter("opacity", 0.40)
		add_child(ink)
	get_viewport().msaa_3d = Viewport.MSAA_2X
	get_viewport().scaling_3d_scale = 1.0
	make_hud()
	apply_look()
	apply_camera()
	refresh()


func apply_look() -> void:
	var colors: Array = LOOKS[look]
	assemble()
	world.environment.background_color = colors[4]
	world.environment.ambient_light_energy = [0.71, 0.75, 0.65][look]
	keylight.light_color = colors[3]
	keylight.light_energy = [1.01, 0.93, 1.09][look]
	keylight.rotation_degrees = [Vector3(-58, -38, 0), Vector3(-64, -48, 0), Vector3(-51, -26, 0)][look]


func apply_camera() -> void:
	var focus := Vector3(2.12, 0.18, -0.85)
	camera.position = focus + VIEWS[view_index]
	camera.look_at(focus)
	camera.size = [15.85, 15.85, 15.2][view_index]


func _input(event: InputEvent) -> void:
	for command: String in INPUTS:
		if not event.is_action_pressed("chrono_" + command): continue
		match command:
			"reset": model = Rules.new()
			"view":
				view_index = (view_index + 1) % VIEWS.size()
				apply_camera()
			"look":
				look = (look + 1) % LOOKS.size()
				apply_look()
			_: model.command(command)
		refresh()
		get_viewport().set_input_as_handled()
		return


func make_hud() -> void:
	var ui := CanvasLayer.new()
	add_child(ui)
	var top := VBoxContainer.new()
	top.position = Vector2(31, 20)
	top.add_theme_constant_override("separation", 2)
	ui.add_child(top)
	label(top, "THE SLEEPING ACADEMY  /  MECHANISM TRIAL A01", 13, Color("a4d6cb"))
	label(top, "The Chronograph Works", 35, Color("f8e9d1"))
	subtitle = label(top, "", 13, Color("c5c9bc"))
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -131.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color("17242df9")
	style.border_color = Color("997c59")
	style.border_width_top = 1
	style.content_margin_left = 31
	style.content_margin_right = 31
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)
	var copy := VBoxContainer.new()
	copy.add_theme_constant_override("separation", 3)
	panel.add_child(copy)
	var first := HBoxContainer.new()
	copy.add_child(first)
	status = label(first, "", 17, Color("ffdfb0"))
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	instrument = label(first, "", 14, Color("aadad0"))
	facts = label(copy, "", 14, Color("f0e2cc"))
	action_help = label(copy, "", 14, Color("c3cabd"))
	controls = label(copy, "", 13, Color("91b4b0"))


func label(parent: Node, caption: String, size_: int, color: Color) -> Label:
	var text := Label.new()
	text.text = caption
	text.add_theme_font_size_override("font_size", size_)
	text.add_theme_color_override("font_color", color)
	parent.add_child(text)
	return text


func refresh() -> void:
	draw_state(model)
	cutaway(camera, model)
	subtitle.text = "%s  /  SECTION %02d" % [LOOKS[look][0], view_index + 1]
	status.text = model.message
	controls.text = "W A S D  Walk (%s)     E  Use / finish tape     Space  Wait one beat     R  Reset     Tab  Section     L  Look" % [
		["north ↗", "north ↖", "north ↗"][view_index]]
	var counter := "TICK %03d" % model.tick
	if model.recording:
		counter = "RECORD %02d / %02d" % [model.tape.size() - 1, Rules.LIMIT]
	elif model.rewind > 0:
		counter = "REWIND  −%02d TICKS" % model.rewind
	elif model.span == Rules.SpanMode.WARNING or model.span == Rules.SpanMode.CLOSING:
		counter = "TURNTABLE  −%02d TICKS" % model.span_clock
	elif model.replay_tick >= 0:
		counter = "REPLAY  %02d / %02d" % [ceili(float(model.replay_tick) / Rules.STEP), model.tape.size() - 1]
	instrument.text = counter
	var hand: String = ["empty", "raw ore", "cooling key", "key seated"][model.item]
	facts.text = "%s  /  HAND: %s  /  FURNACE %s  /  BRIDGE %s" % [Rules.PLACES[model.player].to_upper(), hand,
		"DOWN" if model.on_plate(Rules.FIRE) else "UP", ["PARKED", "ALIGNING", "LOCKED", "PARKING"][model.span]]
	action_help.text = "Bench notes · Furnace plate feeds kiln. The screen rejects ore. Bridge plate and a key bearer at the landing align the deck."
	if model.recording:
		action_help.text = "Record your walk and waits. E finishes the tape; the anchor resets your position and all equipment."
	elif model.rewind > 0:
		action_help.text = "Advance with Space. After the rewind, your recorded footsteps can press plates while you move elsewhere."


func mcp_observe() -> Dictionary:
	return {"state": model.state(), "section": view_index + 1, "look": LOOKS[look][0], "faded_piers": front_faded,
		"render": {"native_scale": get_viewport().scaling_3d_scale, "msaa": get_viewport().msaa_3d,
		"ink_opacity": ink.material_override.get_shader_parameter("opacity") if ink != null else 0.0,
		"sdfgi": world.environment.sdfgi_enabled}}

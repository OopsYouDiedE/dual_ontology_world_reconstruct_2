extends Node3D

const Rules := preload("ShutterRules.gd")
const Room := preload("ShutterRoom.gd")
const Env := preload("res://scenes/components/rendering/post/Hall04.tres")
const Ink := preload("res://scenes/components/rendering/post/InkPass.gd")
const KEYS := {"throw_west": KEY_Q, "throw_east": KEY_E, "approach_west": KEY_A, "approach_east": KEY_D,
	"cross": KEY_W, "exit": KEY_F, "back": KEY_S, "wait": KEY_SPACE, "watch": KEY_X, "view": KEY_TAB, "reset": KEY_R}
const REASON := {"lever_out_of_reach": "Go to the porch or an approach to throw.", "counterweight_engaged": "Wait for the home detent.",
	"approach_out_of_reach": "You are past the forecourt.", "mouth_unavailable": "That mouth needs a clear lane and a berthed wall.",
	"choose_an_approach": "Choose an approach first.", "exit_out_of_reach": "Reach the gallery before opening the exit.",
	"no_approach": "You are already at the porch."}
var rules: Rules
var art := Room.new()
var test_seed := 0
var world: WorldEnvironment
var camera: Camera3D
var ink: MeshInstance3D
var section := 0
var ticks_left := 0
var verdicts: Array[Dictionary] = []
var events: Array[Dictionary] = []
var s := {}
var status: Label
var details: Label
var instruction: Label
var step_count: Label


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--run-seed="): test_seed = arg.get_slice("=", 1).to_int()
	for command: String in KEYS:
		var action := StringName("shutter_" + command)
		if InputMap.has_action(action): continue
		InputMap.add_action(action)
		var k := InputEventKey.new()
		k.physical_keycode = KEYS[command]
		InputMap.action_add_event(action, k)
	Engine.physics_ticks_per_second = Rules.TICK_HZ
	get_viewport().msaa_3d = Viewport.MSAA_2X
	get_viewport().scaling_3d_scale = 1.0
	world = WorldEnvironment.new()
	world.environment = Env.duplicate() as Environment
	world.environment.background_color = Color("252f38")
	add_child(world)
	if RenderingServer.get_current_rendering_method() == &"forward_plus":
		ink = Ink.create()
		ink.material_override.set_shader_parameter("opacity", 0.4)
		add_child(ink)
	var lamp := DirectionalLight3D.new()
	lamp.rotation_degrees = Vector3(-59, 145, 0)
	lamp.light_color = Color("ffe3c6")
	lamp.light_energy = 0.81
	lamp.shadow_enabled = true
	add_child(lamp)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	add_child(camera)
	rules = Rules.new(test_seed)
	add_child(art)
	art.build(rules.layout())
	ui()
	frame_camera()
	refresh()


func frame_camera() -> void:
	var focus := Vector3(0, -0.45, -0.10)
	var sight: Vector3 = [Vector3(6.5, 17.5, -10.6), Vector3(-6.2, 17, -11.2), Vector3(1.80, 24, -5.6)][section]
	camera.position = focus + sight
	camera.look_at(focus)
	camera.size = [11.15, 11.15, 10.5][section]


func _input(event: InputEvent) -> void:
	for command: String in KEYS:
		if not event.is_action_pressed("shutter_" + command): continue
		if command == "view":
			section = (section + 1) % 3
			frame_camera()
		elif command == "reset":
			rules.reset(test_seed)
			verdicts.clear()
			events.clear()
			ticks_left = 0
		elif ticks_left == 0 and s.outcome == "active":
			var action := "wait" if command == "watch" else command
			var before: int = s.events.size()
			var reply := rules.submit(action)
			verdicts.append({"action": action, "tick": s.tick, "accepted": reply.accepted, "reason": reply.reason})
			events.append_array(rules.snapshot().events.slice(before))
			ticks_left = Rules.DECISION_TICKS * (3 if command == "watch" else 1)
		refresh()
		get_viewport().set_input_as_handled()
		return


func _physics_process(_seconds: float) -> void:
	if ticks_left <= 0: return
	rules.tick_once()
	ticks_left -= 1
	# Watch holds three ordinary wait beats; submit at each decision boundary, same authority as a tap.
	var tick_state := rules.snapshot()
	events.append_array(tick_state.events)
	if ticks_left > 0 and ticks_left % Rules.DECISION_TICKS == 0:
		verdicts.append({"action": "wait", "tick": tick_state.tick, "accepted": rules.submit("wait").accepted, "reason": ""})
	refresh()


func ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var block := VBoxContainer.new()
	block.position = Vector2(27, 19)
	layer.add_child(block)
	label(block, "THE SLEEPING ACADEMY  /  COUNTERWEIGHT TRIAL A04", 13, Color("abdcd1"))
	label(block, "The Shutter Loom", 33, Color("f5ead3"))
	var footer := PanelContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -136
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color("15222cf8")
	panel.content_margin_left = 27
	panel.content_margin_top = 9
	panel.content_margin_right = 27
	panel.border_color = Color("aa7c58")
	panel.border_width_top = 1
	footer.add_theme_stylebox_override("panel", panel)
	layer.add_child(footer)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 4)
	footer.add_child(lines)
	var row := HBoxContainer.new()
	lines.add_child(row)
	status = label(row, "", 17, Color("ffcf9e"))
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	step_count = label(row, "", 14, Color("9adbd1"))
	details = label(lines, "", 14, Color("e1ddc9"))
	instruction = label(lines, "", 14, Color("a9cbbe"))
	label(lines, "Q/E  Throw west/east    A/D  Approach west/east    W  Cross    S  Retreat    F  Exit    Space  Wait 20t    X  Watch 60t    Tab  View    R  Reset", 13, Color("a8bdb3"))


func label(parent: Node, value: String, size: int, hue: Color) -> Label:
	var text := Label.new()
	text.text = value
	text.add_theme_color_override("font_color", hue)
	text.add_theme_font_size_override("font_size", size)
	parent.add_child(text)
	return text


func lane_line(lane: String) -> String:
	var p: Dictionary = s.lanes[lane]
	return "%s   %s  /  %s  /  %s" % [lane.to_upper(), "lit" if p.beam_reaches_receiver else "ray cut",
		"mark visible" if p.shadow_visible else "mark gone", "walk permitted" if p.crossing_available else "no crossing"]


func refresh() -> void:
	s = rules.snapshot()
	art.draw(s, camera)
	status.text = "One sliding wall cuts a beam and clears the opposite mouth."
	if not verdicts.is_empty() and not verdicts[-1].accepted:
		status.text = REASON.get(verdicts[-1].reason, "That action has no effect here.")
	if not s.cues.is_empty():
		var cue: Dictionary = s.cues[-1]
		var name_: String = {"rail_steam_out": "Steam: wall travel", "rail_steam_home": "Steam: wall return", "ink_ridge": "INK RIDGE — RETREAT",
			"threshold_scuff": "Reserved crossing", "exit_lintel": "Exit latch releasing"}.get(cue.kind, cue.kind)
		var remaining := maxi(0, cue.due_tick - s.tick)
		status.text = "%s   /   %s" % [name_, ("−%d ticks" % remaining) if remaining > 0 else "engaged"]
	if s.outcome == "won": status.text = "The real shadow guided you to the gallery. The outer gate is open."
	if s.outcome == "caught": status.text = "The false mark caught the survey token. Reset with R."
	step_count.text = "SECTION %d  /  %s  /  TICK %04d" % [section + 1, s.rail.phase.replace("_", " ").to_upper(), s.tick]
	details.text = lane_line("west") + "           |           " + lane_line("east")
	instruction.text = "Field note · Real shade vanishes when the lamp is cut. The ink mark remains; test from the porch before choosing a mouth."


func mcp_observe() -> Dictionary:
	return {"state": s.duplicate(true), "section": section + 1, "ticks_left": ticks_left, "faded": art.faded,
		"verdicts": verdicts.duplicate(true), "events": events.duplicate(true), "render": {
		"msaa_samples": 2, "scaling_3d_scale": get_viewport().scaling_3d_scale, "ink_opacity": ink.material_override.get_shader_parameter("opacity") if ink != null else 0.0,
		"sdfgi_enabled": world.environment.sdfgi_enabled, "atmosphere_baseline": Env.resource_path, "opaque_shader": Room.Finish.resource_path}}

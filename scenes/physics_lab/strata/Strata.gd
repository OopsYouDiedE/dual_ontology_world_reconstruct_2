extends Node3D

const Rules := preload("StrataRules.gd")
const Room := preload("StrataRoom.gd")
const Env := preload("res://scenes/components/rendering/post/Hall04.tres")
const Ink := preload("res://scenes/components/rendering/post/InkPass.gd")
const KEYS := {"climb": KEY_W, "boost": KEY_B, "unload": KEY_U,
	"transform": KEY_T, "open_hatch": KEY_H, "wait": KEY_SPACE, "view": KEY_TAB, "reset": KEY_R}
const CUE_NAMES := {"form_change": "Core press", "hatch_open": "Crown hatch", "strain_trip": "Harness trip", "return_ready": "Sump cradle"}
var authority := Rules.initial()
var art := Room.new()
var world: WorldEnvironment
var camera: Camera3D
var ink: MeshInstance3D
var section := 0
var pending: Array = []
var cursor := 0
var verdicts: Array[Dictionary] = []
var events: Array[Dictionary] = []
var s := Rules.snapshot(authority)
var terrain := Rules.terrain()
var last_refusal := ""
var status: Label
var details: Label
var instruction: Label
var step_count: Label
var options: Label


func _ready() -> void:
	for command: String in KEYS:
		var action := StringName("strata_" + command)
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
	world.environment.background_color = Color("26343a")
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
	add_child(art)
	art.build(terrain)
	ui()
	frame_camera()
	refresh()


func frame_camera() -> void:
	var focus := Vector3(0.0, 3.31, 0.12)
	if section == 2:
		focus = Vector3(0, art.height(s.height_cm) + 0.27, lerpf(1.95, -2.13, float(s.height_cm) / 1620.0))
	var sight: Vector3 = [Vector3(9.0, 8.0, 14.9), Vector3(-7.0, 9.2, 15.5), Vector3(2.1, 13.9, 14.1)][section]
	camera.position = focus + sight
	camera.look_at(focus)
	camera.size = [15.45, 16.05, 6.25][section]


func _input(event: InputEvent) -> void:
	if not is_node_ready(): return
	for command: String in KEYS:
		if not event.is_action_pressed("strata_" + command): continue
		if command == "view":
			section = (section + 1) % 3
			frame_camera()
		elif command == "reset":
			authority = Rules.initial()
			s = Rules.snapshot(authority)
			events.clear()
			verdicts.clear()
			pending.clear()
			cursor = 0
			last_refusal = ""
		elif pending.is_empty():
			var accepted: bool = command in s.actions
			verdicts.append({"action": command, "tick": s.tick, "accepted": accepted})
			last_refusal = "" if accepted else command
			if accepted:
				authority = Rules.advance(authority, command, pending)
				cursor = 0
		refresh()
		get_viewport().set_input_as_handled()
		return


func _physics_process(_seconds: float) -> void:
	if pending.is_empty(): return
	s = pending[cursor]
	events.append_array(s.events)
	cursor += 1
	if cursor == pending.size():
		pending.clear()
		cursor = 0
		s = Rules.snapshot(authority)
	refresh()


func ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var block := VBoxContainer.new()
	block.position = Vector2(27, 19)
	layer.add_child(block)
	label(block, "THE SLEEPING ACADEMY  /  TRACTION TRIAL A07", 13, Color("abdcd1"))
	label(block, "Strata · The Harness Tower", 33, Color("f5ead3"))
	var footer := PanelContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -149
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
	options = label(lines, "", 14, Color("a9cbbe"))
	label(lines, "W  Climb    B  Boost    U  Unload    T  Change core    H  Crown hatch    Space  Wait    Tab  View    R  Reset", 13, Color("a8bdb3"))


func label(parent: Node, value: String, size: int, hue: Color) -> Label:
	var text := Label.new()
	text.text = value
	text.add_theme_color_override("font_color", hue)
	text.add_theme_font_size_override("font_size", size)
	parent.add_child(text)
	return text


func refresh() -> void:
	if section == 2: frame_camera()
	art.draw(s)
	status.text = "Copper powers the rack. Ceramic takes the stairs. Bring a charged copper core to the Crown."
	if not last_refusal.is_empty(): status.text = refusal(last_refusal)
	if s.mode == "return": status.text = "Harness tripped. The safety cradle returns the core to the Sump."
	if s.mode == "won": status.text = "Crown hatch open. The core and its remaining charge have reached the Crown."
	step_count.text = "SECTION %d  /  TICK %04d" % [section + 1, s.tick]
	details.text = "%s  /  %s  /  %d cm    |    STRAIN %03d / %03d trip band    |    BANK %03d / %03d    |    CIRCUIT %s" % [
		s.form.to_upper(), s.route.to_upper(), s.height_cm, s.strain, s.strain_warn, s.charge, s.charge_max, s.circuit.to_upper()]
	var deadlines := PackedStringArray()
	for cue: Dictionary in s.warnings: deadlines.append("%s −%dt" % [CUE_NAMES[cue.id], cue.ticks_left])
	var field_note := "Anchor · Copper unloads %d strain/t and returns 1 bank per %d. Ceramic unloads 8/t without charge." % [Rules.COPPER_UNLOAD_PER_TICK, s.strain_per_charge]
	if s.route != "anchor" and s.landing < terrain.bands.size():
		var band: Dictionary = terrain.bands[s.landing]
		field_note = "Band rates per tick · Hand %d cm / %d strain per tick   |   Boost %d cm / %d strain / %d charge   |   Stairs %d cm / %d strain" % [
			band.rail_hand_cm_per_tick, band.rail_hand_strain_per_tick, band.rail_boost_cm_per_tick,
			band.rail_boost_strain_per_tick, band.rail_boost_draw_per_tick, band.stairs_cm_per_tick, band.stairs_strain_per_tick]
	instruction.text = "Cue ledger · " + "    /    ".join(deadlines) if not deadlines.is_empty() else field_note
	var available := PackedStringArray()
	for item: String in s.actions:
		available.append(item.replace("_", " "))
	options.text = "Available · %s     |     Press %d charge   /   Hatch %d charge%s" % ["  ·  ".join(available), s.press_cost, s.hatch_cost,
		"   /   Next boost %d charge" % s.boost_cost_next if s.boost_cost_next > 0 else ""]


func refusal(action: String) -> String:
	if s.mode == "won": return "The Crown hatch is already open."
	if s.mode != "ready": return "Wait for the announced operation."
	match action:
		"climb": return "You are at the Crown."
		"boost": return "Boost requires copper on a rack and enough charge for the next beat."
		"unload": return "Unload at an anchor while the harness holds strain."
		"transform": return "Use an anchor press with enough charge and strain below the trip band."
		"open_hatch": return "Use copper at the Crown, with enough charge and a relaxed harness."
	return "That action is unavailable."


func mcp_observe() -> Dictionary:
	return {"state": s.duplicate(true), "section": section + 1, "ticks_left": pending.size() - cursor,
		"verdicts": verdicts.duplicate(true), "events": events.duplicate(true), "render": {
		"msaa_samples": 2, "scaling_3d_scale": get_viewport().scaling_3d_scale,
		"ink_opacity": ink.material_override.get_shader_parameter("opacity") if ink != null else 0.0,
		"sdfgi_enabled": world.environment.sdfgi_enabled, "atmosphere_baseline": Env.resource_path, "opaque_shader": Room.Kit.Finish.resource_path}}

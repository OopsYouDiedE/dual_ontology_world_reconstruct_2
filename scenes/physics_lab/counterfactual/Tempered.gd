extends Node3D

const Rules := preload("Model.gd")
const Room := preload("TemperedRoom.gd")
const Env := preload("res://scenes/components/rendering/post/Hall04.tres")
const Ink := preload("res://scenes/components/rendering/post/InkPass.gd")
const Tape := preload("res://tools/counterfactual/Replay.gd")
const STATION_KEYS := {"start": KEY_1, "jack": KEY_2, "kiln": KEY_3, "yoke": KEY_4,
	"brake": KEY_5, "weight": KEY_6, "span": KEY_7, "exit": KEY_8}
const PRESS_KEYS := {"cut_pin": KEY_P, "mark": KEY_M, "rewind_home": KEY_H, "rewind_bench": KEY_B,
	"arm": KEY_A, "cancel": KEY_X, "queue_cross": KEY_E, "view": KEY_TAB, "reset": KEY_R,
	"run": KEY_SPACE, "tick": KEY_PERIOD, "continue": KEY_J}
const HOLD_KEYS := {"increase": KEY_W, "decrease": KEY_S}
const STATION_HOLDS := {"jack": ["haul", "pay_out"], "kiln": ["heat", ""], "weight": ["raise", "lower"], "brake": ["tighten", "loosen"]}
const STEP_LABEL := {"jack": "W haul / S pay out", "kiln": "P punch pin / W heat", "weight": "W raise / S lower", "brake": "W tighten / S loosen",
	"start": "M mark Bench / H rewind Home / B rewind Bench", "yoke": "A arm the draw", "span": "X return on the safety trolley", "exit": "R reset"}
var rule := Rules.new()
var art := Room.new()
var world: WorldEnvironment
var camera: Camera3D
var ink: MeshInstance3D
var section := 0
var held := {}
var command_queue: Array[Dictionary] = []
var budget := 0
var live := false
var tape := {}
var stops: Array = []
var next_stop := 0
var tape_mode := false
var inputs: Array[Dictionary] = []
var events: Array[Dictionary] = []
var s := rule.observe()
var status: Label
var details: Label
var instruction: Label
var step_count: Label
var options: Label
var witness: Label
var rail: ProofRuler


class ProofRuler extends Control:
	var track := {}
	var t := 0
	func _draw() -> void:
		if track.get("stage", "parked") == "parked": return
		var start: int = track.start_tick
		var duration := float(track.end_tick - start)
		for i in 2:
			var tag: String = ["brake", "weight"][i]
			var y := 8.0 + 12.0 * i
			draw_rect(Rect2(62,y,244,7),Color("624c45"))
			for interval: Dictionary in track.windows.get(tag, []):
				var at: float = 62.0 + 244 * (interval.first_tick - start) / duration
				var width: float = 244 * (interval.last_tick + 1 - interval.first_tick) / duration
				draw_rect(Rect2(at,y,maxf(2.0,width),7),Color("77cfbc"))
			draw_string(ThemeDB.fallback_font, Vector2(0,y+7), tag.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("bfcac3"))
		var marker := 62.0 + 244 * clampf((t - start)/duration,0,1)
		draw_line(Vector2(marker,2),Vector2(marker,32),Color("ffe0a4"),1.0)
		draw_string(ThemeDB.fallback_font,Vector2(62,46), "Entry windows / full rider load",HORIZONTAL_ALIGNMENT_LEFT,-1,11,Color("bdd8cc"))


func _ready() -> void:
	for group: Dictionary in [STATION_KEYS, PRESS_KEYS, HOLD_KEYS]:
		for key: String in group:
			var action := StringName("tempered_" + key)
			if InputMap.has_action(action): continue
			InputMap.add_action(action)
			var k := InputEventKey.new()
			k.physical_keycode = group[key]
			InputMap.action_add_event(action, k)
	Engine.physics_ticks_per_second = Rules.HZ
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
	art.build(s)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tempered-study="):
			load_study(arg.trim_prefix("--tempered-study="))
	ui()
	frame_camera()
	refresh()


func load_study(path: String) -> void:
	# The detached tape only supplies player input edges and fixture hold levels.
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not data is Dictionary or not data.get("inputs") is Array or not data.get("stops") is Array:
		push_error("Invalid Tempered Span study tape")
		return
	var compiled := Tape.compile(data.inputs)
	if compiled.has("error"):
		push_error(str(compiled.error))
		return
	stops = data.stops.duplicate()
	stops.sort()
	tape = compiled.ticks
	tape_mode = true


func frame_camera() -> void:
	var focus := Vector3(0, -0.49, 0.04)
	var offset: Vector3 = [Vector3(8.7,18.6,11.0),Vector3(-8.7,18.6,11.0),Vector3(0.7,25,5.3)][section]
	camera.position = focus + offset
	camera.look_at(focus)
	camera.size = [13.4,13.4,14.4][section]


func _input(event: InputEvent) -> void:
	if not is_node_ready(): return
	for id: String in HOLD_KEYS:
		if event.is_action_pressed("tempered_" + id):
			if not tape_mode: held[id] = true
			get_viewport().set_input_as_handled()
			return
		if event.is_action_released("tempered_" + id):
			held.erase(id)
			return
	for id: String in STATION_KEYS:
		if event.is_action_pressed("tempered_" + id):
			if not tape_mode: command_queue.append({"press": "move", "target": id})
			get_viewport().set_input_as_handled()
			return
	for id: String in PRESS_KEYS:
		if not event.is_action_pressed("tempered_" + id): continue
		if id == "view":
			section = (section + 1) % 3
			frame_camera()
		elif id == "reset":
			rule.reset()
			s = rule.observe()
			budget = 0
			next_stop = 0
			live = false
			inputs.clear()
			events.clear()
			command_queue.clear()
			held.clear()
		elif tape_mode:
			if id == "continue" and budget == 0 and next_stop < stops.size():
				budget = maxi(0,int(stops[next_stop]) - int(s.tick))
				next_stop += 1
		elif id == "run":
			live = not live
		elif id == "tick":
			budget += 1
		elif id != "continue":
			command_queue.append({"press": id})
		refresh()
		get_viewport().set_input_as_handled()
		return


func _physics_process(_seconds: float) -> void:
	if s.won:
		budget = 0
		return
	if tape_mode and budget <= 0: return
	if not tape_mode and not live and budget <= 0 and held.is_empty() and command_queue.is_empty() and s.travel.is_empty(): return
	if budget > 0: budget -= 1
	var input := {}
	if tape_mode:
		input = tape.get(s.tick + 1,{})
	else:
		if not command_queue.is_empty(): input = command_queue.pop_front()
		var holds: Array = STATION_HOLDS.get(s.place,[])
		if not holds.is_empty():
			var level: String = holds[0] if held.has("increase") else holds[1] if held.has("decrease") else ""
			if not level.is_empty(): input["hold"] = level
	var before: Dictionary = s.event
	rule.step(input)
	s = rule.observe()
	if not input.is_empty(): inputs.append({"tick": s.tick, "input": input.duplicate()})
	if s.event != before: events.append(s.event.duplicate(true))
	refresh()


func ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var block := VBoxContainer.new()
	block.position = Vector2(27, 19)
	layer.add_child(block)
	label(block, "THE SLEEPING ACADEMY  /  SPLICE TRIAL A08", 13, Color("abdcd1"))
	label(block, "The Tempered Span", 33, Color("f5ead3"))
	var instruments := VBoxContainer.new()
	instruments.position = Vector2(942,22)
	layer.add_child(instruments)
	witness = label(instruments,"",13,Color("d7ded0"))
	rail = ProofRuler.new()
	rail.custom_minimum_size = Vector2(310,50)
	instruments.add_child(rail)
	var footer := PanelContainer.new()
	footer.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	footer.offset_top = -157
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
	label(lines, "1 Bench  2 Jack  3 Kiln  4 Yoke  5 Brake  6 Weight  7 Span   |   E Queue rider   Space Run/pause   . Step 1t   X Cancel   Tab View   R Reset", 13, Color("a8bdb3"))


func label(parent: Node, value: String, size: int, hue: Color) -> Label:
	var text := Label.new()
	text.text = value
	text.add_theme_color_override("font_color", hue)
	text.add_theme_font_size_override("font_size", size)
	parent.add_child(text)
	return text


func refresh() -> void:
	art.draw(s)
	rail.track = s.proof
	rail.t = s.tick
	rail.queue_redraw()
	var bench: Dictionary = s.marks.get("bench", {})
	witness.text = "RETAINED   cable %02d  /  copper bend %02d\nLOCAL        pin %s   /  kiln %03d\nMARK         %s\nNEEDLES   tension %d ≥ %d   /   shoe %d (±%d)" % [
		s.retained.preload,s.retained.bend,"IN" if s.local.pin_intact else "OUT",s.local.heat,
		"Bench B%d  /  W%d" % [bench.brake,bench.ballast] if not bench.is_empty() else "Home only",s.readings.tension,s.readings.min_tension,s.readings.shoe,s.readings.shoe_limit]
	status.text = s.event.text
	var clock := "STUDY" if tape_mode else "LIVE" if live else "STEP"
	step_count.text = "%s  /  OUT %04d   LOCAL %04d" % [clock,s.tick,s.local_tick]
	details.text = "%s   |   DRUM %03d   |   BRAKE %02d   /   WEIGHT %02d   |   %s" % [
		s.objects[s.place],s.drum_phase,s.local.brake,s.local.ballast,"PROOF " + s.proof.stage.to_upper()]
	var cues := PackedStringArray()
	for cue: Dictionary in s.cues:
		cues.append("%s −%dt" % [cue.id.replace("_"," "),maxi(0,cue.due_tick - s.tick)])
	instruction.text = "Cues · " + "  /  ".join(cues) if not cues.is_empty() else "Field note · Pin, heat, weight and brake rewind. Cable teeth, copper bend and exterior drum stay."
	var proof_note := ""
	if s.proof.stage != "parked":
		proof_note = "   |   First rider entry: brake %s  /  weight %s" % [entry_text("brake"),entry_text("weight")]
	options.text = ("Study tape · J advances to the next evidence frame" if tape_mode else STEP_LABEL[s.place]) + proof_note


func entry_text(approach: String) -> String:
	var at: int = s.proof.next_entry.get(approach,-1)
	return str(at) if at >= 0 else "none"


func mcp_observe() -> Dictionary:
	return {"state": s.duplicate(true),"section": section+1,"ticks_left": budget,"next_stop": next_stop,
		"inputs": inputs.duplicate(true),"events": events.duplicate(true),"render": {
		"msaa_samples": 2,"scaling_3d_scale": get_viewport().scaling_3d_scale,
		"ink_opacity": ink.material_override.get_shader_parameter("opacity") if ink != null else 0.0,
		"sdfgi_enabled": world.environment.sdfgi_enabled,"atmosphere_baseline": Env.resource_path,"opaque_shader": Room.Kit.Finish.resource_path}}

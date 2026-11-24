extends Node3D

const Rules := preload("AfterimageRules.gd")
const Room := preload("AfterimageRoom.gd")
const Env := preload("res://scenes/components/rendering/post/Hall04.tres")
const Ink := preload("res://scenes/components/rendering/post/InkPass.gd")
const PADS := ["hub", "lamp", "bell", "carriage", "exit"]
const INPUTS := {"hub": KEY_1, "lamp": KEY_2, "bell": KEY_3, "carriage": KEY_4, "exit": KEY_5,
	"pulse": KEY_E, "prism": KEY_P, "rewind": KEY_T, "escape": KEY_G, "wait": KEY_SPACE, "view": KEY_TAB, "reset": KEY_R}
const NOTES := {"no_gangway": "That landing has no load-bearing route from here.", "no_emitter": "Pulse only at a wired fixture or the carriage bell.",
	"no_ladder": "The service ladder goes down from the carriage only.", "no_prism_control": "The prism is operable from the hub or carriage."}
var model := Rules.new()
var art := Room.new()
var camera: Camera3D
var world: WorldEnvironment
var ink: MeshInstance3D
var bell_tone: AudioStreamWAV
var lamp_tone: AudioStreamWAV
var warning_tone: AudioStreamWAV
var voiced := {}
var state: Dictionary
var wiring: Dictionary
var advance := 0
var view := 0
var line: Label
var tape_line: Label
var facts: Label
var time_line: Label
var markers: Label
var input_history: Array[Dictionary] = []


func _ready() -> void:
	Engine.physics_ticks_per_second = Rules.HZ
	for verb: String in INPUTS:
		var id := StringName("afterimage_" + verb)
		if not InputMap.has_action(id):
			InputMap.add_action(id)
			var k := InputEventKey.new()
			k.physical_keycode = INPUTS[verb]
			InputMap.action_add_event(id, k)
	get_viewport().msaa_3d = Viewport.MSAA_2X
	get_viewport().scaling_3d_scale = 1.0
	world = WorldEnvironment.new()
	world.environment = Env.duplicate() as Environment
	world.environment.background_color = Color("28333a")
	add_child(world)
	if RenderingServer.get_current_rendering_method() == &"forward_plus":
		ink = Ink.create()
		ink.material_override.set_shader_parameter("opacity", 0.40)
		add_child(ink)
	var lamp := DirectionalLight3D.new()
	lamp.rotation_degrees = Vector3(-58, -34, 0)
	lamp.light_color = Color("ffe2bd")
	lamp.light_energy = 1.08
	lamp.shadow_enabled = true
	add_child(lamp)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.current = true
	add_child(camera)
	wiring = model.layout()
	add_child(art)
	art.build(wiring)
	bell_tone = make_tone(387.0, 0.62, 0.61)
	lamp_tone = make_tone(880.0, 0.19, 0.13)
	warning_tone = make_tone(171.0, 0.62, 0.32)
	make_hud()
	frame_view()
	refresh()


func frame_view() -> void:
	var focal := Vector3(-0.88, -0.25, 0.40)
	var delta: Vector3 = [Vector3(7.0, 15.0, 13.0), Vector3(-7.6, 16.0, 14.0), Vector3(1.0, 24.0, 6.0)][view]
	camera.position = focal + delta
	camera.look_at(focal)
	camera.size = [13.3, 13.3, 12.9][view]


func _input(event: InputEvent) -> void:
	for input: String in INPUTS:
		if not event.is_action_pressed("afterimage_" + input): continue
		if input == "view":
			view = (view + 1) % 3
			frame_view()
		elif input == "reset":
			model.reset()
			advance = 0
			input_history.clear()
			voiced.clear()
		elif advance == 0 and not state.won:
			var verb := "move" if PADS.has(input) else input
			var target := input if verb == "move" else ""
			var queued := model.queue_action(verb, target)
			if queued or (input == "wait" and state.reel.rewinding):
				input_history.append({"input": input, "queued": queued, "tick": state.tick})
				advance = Rules.DECISION_TICKS
		refresh()
		get_viewport().set_input_as_handled()
		return


func _physics_process(_dt: float) -> void:
	if advance == 0: return
	model.step_tick()
	advance -= 1
	refresh()


func make_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var heading := VBoxContainer.new()
	heading.position = Vector2(28, 17)
	layer.add_child(heading)
	make_label(heading, "THE SLEEPING ACADEMY  /  PARALLAX TRIAL A05", 13, Color("a9dcd0"))
	make_label(heading, "The Afterimage Carriage", 33, Color("f5ead6"))
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.offset_top = -158
	var style := StyleBoxFlat.new()
	style.bg_color = Color("16252de9")
	style.content_margin_left = 28
	style.content_margin_top = 7
	style.content_margin_right = 28
	style.border_color = Color("ae865d")
	style.border_width_top = 1
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 2)
	panel.add_child(body)
	var row := HBoxContainer.new()
	body.add_child(row)
	line = make_label(row, "", 17, Color("ffd49d"))
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_line = make_label(row, "", 14, Color("a3dcd4"))
	facts = make_label(body, "", 14, Color("e1ddc7"))
	tape_line = make_label(body, "", 14, Color("b4e2d5"))
	markers = make_label(body, "", 13, Color("abc1b7"))
	make_label(body, "1–5  Hub / Lamp / Bell / Carriage / Exit    E  Pulse    P  Prism    T  Rewind    G  Ladder down    Space  Wait    Tab  View    R  Reset", 13, Color("9cb8ad"))


func make_label(parent: Node, caption: String, size: int, shade: Color) -> Label:
	var text := Label.new()
	text.text = caption
	text.add_theme_font_size_override("font_size", size)
	text.add_theme_color_override("font_color", shade)
	parent.add_child(text)
	return text


func refresh() -> void:
	state = model.observe()
	art.draw(state, camera)
	line.text = "A light pulse and a bell pulse arriving on the same beat drive the pickup."
	if not state.last_action.is_empty() and not state.last_action.ok:
		line.text = NOTES.get(state.last_action.reason, state.last_action.reason.replace("_", " ").capitalize())
	if not state.pair.is_empty():
		line.text = "%s pickup: %s" % [state.pair.receiver.capitalize(), "matched two pulses" if state.pair.accepted else state.pair.reason.replace("_", " ")]
	if not state.cues.is_empty():
		var phrases := {"prism": "Prism mount turning", "swing": "Carriage swing", "spring": "Spring returning", "rewind": "Reel winding back"}
		var details: Array[String] = []
		for c: Dictionary in state.cues:
			details.append("%s in %02dt" % [phrases.get(c.kind, c.kind), maxi(0, c.due_tick - state.tick)])
		line.text = ("%s pair verified  /  " % state.pair.receiver.capitalize() if state.pair.get("accepted", false) else "") + "   /   ".join(details)
	if state.won: line.text = "Crossed to the East landing with the silver gangway engaged."
	time_line.text = "SECTION %02d  /  TICK %03d" % [view + 1, state.tick]
	facts.text = "%s   /   PRISM  %s   /   PICKUP  %s   /   CARRIAGE  %s" % [wiring.sites[state.player].label.to_upper(),
		state.form.to_upper(), state.optics.receiver.to_upper(), state.alignment.to_upper()]
	var tape: Array[String] = []
	for i in wiring.reel_beats:
		var c: String = {"lamp": "LIGHT", "bell": "BELL", "": "·"}.get(state.reel.tape[i], "·") if i < state.reel.tape.size() else "—"
		tape.append("[ %s ]" % c if state.reel.replaying and i == state.reel.cursor - 1 else c)
	tape_line.text = "%s  /  %s   %s" % ["REPLAY" if state.reel.replaying else "REEL", "   ".join(tape),
		"/  T READY" if state.reel.can_rewind else ""]
	markers.text = "The reel restores position and prism. It echoes only wired pulses. The carriage stays on the outside clock."
	voices()


func voices() -> void:
	for signal_: Dictionary in state.signals:
		var tag := "%s:%d:%s" % [signal_.origin, signal_.start_tick, signal_.channel]
		if voiced.has(tag): continue
		voiced[tag] = true
		var fixture: String = signal_.source
		var pos: Vector3 = art.ferry.position if fixture == "carriage" else art.destinations[fixture]
		play_audio(bell_tone if signal_.channel == "sound" else lamp_tone, pos, -16 if signal_.origin == "echo" else -12)
	for cue: Dictionary in state.cues:
		var tag := "%s:%d" % [cue.kind, cue.start_tick]
		if voiced.has(tag): continue
		voiced[tag] = true
		play_audio(warning_tone, Vector3.ZERO, -16)


func make_tone(freq: float, seconds: float, harmonic: float) -> AudioStreamWAV:
	const RATE := 22050
	var p := PackedByteArray()
	p.resize(int(RATE * seconds) * 2)
	for i in int(RATE * seconds):
		var t := float(i) / RATE
		var envelope := minf(t * 390.0, 1.0) * exp(-t / seconds * 5)
		var sound := (sin(TAU * freq * t) + harmonic * sin(TAU * freq * t * 1.68)) * envelope
		p.encode_s16(i * 2, clampi(roundi(sound * 15000.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.data = p
	return wav


func play_audio(wav: AudioStreamWAV, at: Vector3, gain: float) -> void:
	if DisplayServer.get_name() == "headless": return
	var player := AudioStreamPlayer3D.new()
	add_child(player)
	player.position = at + Vector3.UP * 0.5
	player.stream = wav
	player.max_db = gain
	player.volume_db = gain
	player.finished.connect(player.queue_free)
	player.play()


func mcp_observe() -> Dictionary:
	return {"state": state.duplicate(true), "advance": advance, "inputs": input_history.duplicate(true), "section": view + 1,
		"faded": art.faded_pier, "render": {"msaa_samples": 2, "scaling_3d_scale": get_viewport().scaling_3d_scale,
		"ink_opacity": ink.material_override.get_shader_parameter("opacity") if ink != null else 0.0,
		"sdfgi_enabled": world.environment.sdfgi_enabled, "atmosphere_baseline": Env.resource_path,
		"opaque_shader": Room.Kit.Finish.resource_path}}

extends Node3D

const Rules := preload("DuetRules.gd")
const Room := preload("DuetRoom.gd")
const Env := preload("res://scenes/components/rendering/post/Hall04.tres")
const Ink := preload("res://scenes/components/rendering/post/InkPass.gd")
const KEYS := {"lower": KEY_E, "watch": KEY_W, "creep": KEY_C,
	"back_watch": KEY_S, "back_creep": KEY_V, "wait": KEY_SPACE, "view": KEY_TAB, "reset": KEY_R}
const REASON := {"lever_out_of_reach": "The drawleaf lever is on the porch.", "drive_engaged": "The drive is already engaged.",
	"end_of_lane": "You are at the end of the lane.", "gap_open": "The gap has no support. Wait for the lower detent.",
	"recovering": "Service return in progress. Wait to regain the porch."}
const CUE_NAMES := {"leaf_lower": "Leaf drive", "leaf_raise": "Counterweight", "hearing": "Ear spring", "sight": "Watcher", "recovery": "Service return"}
var rules: Rules
var art := Room.new()
var world: WorldEnvironment
var camera: Camera3D
var ink: MeshInstance3D
var section := 0
var ticks_left := 0
var verdicts: Array[Dictionary] = []
var events: Array[Dictionary] = []
var s := {}
var last_event_id := 0
var sounds := {}
var status: Label
var details: Label
var instruction: Label
var step_count: Label


func _ready() -> void:
	for command: String in KEYS:
		var action := StringName("duet_" + command)
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
	rules = Rules.new()
	add_child(art)
	art.build(rules.layout())
	if DisplayServer.get_name() != "headless":
		for kind: String in ["iron", "felt", "leaf", "hearing", "sight", "caught"]:
			var freq: float = {"iron": 525.0, "felt": 108.0, "leaf": 79.0, "hearing": 251.0, "sight": 171.0, "caught": 61.0}[kind]
			sounds[kind] = make_tone(freq, 0.12 if kind in ["iron", "felt"] else 0.36, 0.12 if kind == "felt" else 0.38)
	ui()
	frame_camera()
	refresh()


func frame_camera() -> void:
	var focus := Vector3(0, -0.40, 0.10)
	var sight: Vector3 = [Vector3(8.3, 15.6, -11.1), Vector3(-8.0, 16.5, -10.5), Vector3(1.7, 23, -4.2)][section]
	camera.position = focus + sight
	camera.look_at(focus)
	camera.size = [13.4, 13.4, 14.2][section]


func _input(event: InputEvent) -> void:
	if not is_node_ready(): return
	for command: String in KEYS:
		if not event.is_action_pressed("duet_" + command): continue
		if command == "view":
			section = (section + 1) % 3
			frame_camera()
		elif command == "reset":
			rules.reset()
			events.clear()
			verdicts.clear()
			ticks_left = 0
			last_event_id = 0
		elif ticks_left == 0 and s.outcome != "won":
			var reply := rules.submit(command)
			verdicts.append({"action": command, "tick": s.tick, "accepted": reply.accepted, "reason": reply.reason})
			read_events(rules.snapshot().events)
			ticks_left = Rules.DECISION_TICKS
		refresh()
		get_viewport().set_input_as_handled()
		return


func _physics_process(_seconds: float) -> void:
	if ticks_left <= 0: return
	rules.tick_once()
	ticks_left -= 1
	read_events(rules.snapshot().events)
	refresh()


func read_events(pulse: Array) -> void:
	for entry: Dictionary in pulse:
		if entry.id <= last_event_id: continue
		last_event_id = entry.id
		events.append(entry)
		var kind := ""
		if entry.kind == "stride": kind = entry.detail.surface
		if entry.kind == "cue_start":
			kind = "leaf" if entry.source.begins_with("leaf") else entry.source
		if entry.kind == "caught": kind = "caught"
		if not sounds.has(kind): continue
		var sound := AudioStreamPlayer.new()
		sound.stream = sounds[kind]
		sound.volume_db = -24.0 if kind == "felt" else -15.0
		add_child(sound)
		sound.finished.connect(sound.queue_free)
		sound.play()


func ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var block := VBoxContainer.new()
	block.position = Vector2(27, 19)
	layer.add_child(block)
	label(block, "THE SLEEPING ACADEMY  /  ACOUSTIC TRIAL A06", 13, Color("abdcd1"))
	label(block, "The Felt Drawleaf", 33, Color("f5ead3"))
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
	label(lines, "E  Lower leaf    W  Watch & step    C  Creep    S/V  Retreat tall/low    Space  Wait 20t    Tab  View    R  Reset", 13, Color("a8bdb3"))


func label(parent: Node, value: String, size: int, hue: Color) -> Label:
	var text := Label.new()
	text.text = value
	text.add_theme_color_override("font_color", hue)
	text.add_theme_font_size_override("font_size", size)
	parent.add_child(text)
	return text


func refresh() -> void:
	s = rules.snapshot()
	art.draw(s, camera)
	status.text = "Stand tall to hold the Watcher still. Creep to quiet the iron tread."
	if not verdicts.is_empty() and not verdicts[-1].accepted:
		status.text = REASON.get(verdicts[-1].reason, "This action is unavailable.")
	var deadlines := PackedStringArray()
	for cue: Dictionary in s.cues:
		var remains := maxi(0, cue.due_tick - s.tick)
		var ending := "−%dt" % remains if remains > 0 else "held"
		deadlines.append("%s %s" % [CUE_NAMES[cue.kind], ending])
	if s.outcome == "recovering": status.text = "Caught. The service track returns you to the porch."
	if s.outcome == "won": status.text = "Far landing reached. The acoustic trial is complete."
	step_count.text = "SECTION %d  /  ATTEMPT %d  /  TICK %04d" % [section + 1, s.attempt, s.tick]
	details.text = "EAR %03d/%03d  %s    |    SIGHT %d cm  %s    |    %s on %s    |    LEAF %s" % [s.hearing.ring, s.hearing.trip_ring, s.hearing.mode,
		s.sight.separation_cm, s.sight.mode, s.player.posture, s.player.footing, s.leaf.phase.replace("_", " ")]
	instruction.text = "Cue ledger · " + "    /    ".join(deadlines) if not deadlines.is_empty() else "Field note · A tall step on felt quiets the ear spring without breaking your gaze."


func mcp_observe() -> Dictionary:
	return {"state": s.duplicate(true), "section": section + 1, "ticks_left": ticks_left, "faded": art.faded,
		"verdicts": verdicts.duplicate(true), "events": events.duplicate(true), "render": {
		"msaa_samples": 2, "scaling_3d_scale": get_viewport().scaling_3d_scale,
		"ink_opacity": ink.material_override.get_shader_parameter("opacity") if ink != null else 0.0,
		"sdfgi_enabled": world.environment.sdfgi_enabled, "atmosphere_baseline": Env.resource_path, "opaque_shader": Room.Kit.Finish.resource_path}}


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

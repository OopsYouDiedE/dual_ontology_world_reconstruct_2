extends Node3D
## Only draws detached layout and observation records from the room authority.

const Kit := preload("res://scenes/physics_lab/shutter_loom/ShutterRoom.gd")
const COPPER := Color("d2a36b")
const STONE := Color("8f9e9f")
const TRIM := Color("c6c5b0")
const IRON := Color("344754")
const TEAL := Color("75e5dc")
const AMBER := Color("ffc068")
const RUST := Color("ee8e60")
const LIGHT := Color("e7dac1")
var tools := Kit.new()
var deck: Node3D
var form_glass: MeshInstance3D
var form_silver: MeshInstance3D
var props := {}
var destinations := {}
var spans := {}
var ghost_spans := {}
var lamps := {}
var pulses := {}
var pulse_wires := {}
var wind_clock: Node3D
var reel_wheel: Node3D
var reel_slots: Array[MeshInstance3D] = []
var player: Node3D
var echo: Node3D
var ferry: Node3D
var cutaway: MeshInstance3D
var cutaway_bounds: AABB
var transparent: StandardMaterial3D
var faded_pier := false
var path_a: MeshInstance3D
var path_b: MeshInstance3D
var phase_meter: MeshInstance3D


func build(layout: Dictionary) -> void:
	deck = Node3D.new()
	add_child(deck)
	add_child(tools)
	tools.deck = deck
	transparent = tools.translucent(Color(0.73, 0.91, 0.93, 0.22))
	for site: String in layout.sites:
		var raw: Array = layout.sites[site].xz
		destinations[site] = Vector3(float(raw[0]) * 1.85, 0.08, float(raw[1]) * 1.43)
	tools.box(deck, Vector3(-0.98, -0.54, 0), Vector3(13.10, 0.93, 8.20), IRON.darkened(0.27))
	tools.box(deck, Vector3(-0.98, -0.75, 0), Vector3(13.20, 0.09, 8.24), COPPER.darkened(0.35))
	tools.box(deck, Vector3(-0.98, -0.10, 0), Vector3(12.96, 0.08, 8.12), IRON.darkened(0.42))
	for i in 9:
		tools.box(deck, Vector3(-7.12 + i * 1.50, -0.34, 4.10), Vector3(0.025, 0.37, 0.09), IRON)
	for z in [-2.85, -1.42, 0.0, 1.42, 2.85]:
		tools.box(deck, Vector3(-5.95, -0.12, z), Vector3(2.59, 0.42, 1.39), STONE)
		tools.box(deck, Vector3(-5.95, 0.111, z), Vector3(2.50, 0.064, 1.34), STONE.lightened(0.16 if absf(z) > 2 else 0.10))
	for site: String in ["hub", "exit"]:
		var node: Vector3 = destinations[site]
		tools.box(deck, node - Vector3(0, 0.17, 0), Vector3(2.57, 0.46, 2.05), STONE)
		for turn in 2:
			tools.box(deck, node + Vector3(turn * 1.25 - 0.625, 0.077, 0), Vector3(1.22, 0.036, 1.99), STONE.lightened(0.15))
	for site: String in ["lamp", "bell", "hub", "exit"]:
		var position: Vector3 = destinations[site]
		tools.drum(deck, position + Vector3(0, 0.16, 0), 0.33, 0.113, IRON)
		tools.drum(deck, position + Vector3(0, 0.213, 0), 0.27, 0.048, COPPER.darkened(0.18))
		floor_label(layout.sites[site].label.to_upper(), position + Vector3(0, 0.23, 0.62), 0.19)
	for x in [-5.96, -3.52, 2.74, 4.84]:
		tools.box(deck, Vector3(x, 0.70, -3.84), Vector3(2.07, 1.49, 0.24), IRON.lightened(0.17))
		for y in [0.25, 0.60, 0.95]:
			tools.box(deck, Vector3(x, y, -3.70), Vector3(2.04, 0.026, 0.075), IRON)
		tools.arch(Vector3(x, 0.79, -3.63), 0.91, 0.66, 0.087)
		for j in [-1.0, 1.0]:
			tools.box(deck, Vector3(x + j * 0.9, 0.34, -3.55), Vector3(0.17, 0.8, 0.35), TRIM)
	var at := Vector3(0, 0.0, 0)
	tools.drum(deck, at - Vector3(0, 0.13, 0), 1.21, 0.26, IRON)
	tools.drum(deck, at - Vector3(0, 0.08, 0), 0.93, 0.31, COPPER.darkened(0.13))
	for i in 15:
		var a := TAU * float(i) / 15.0
		var tooth := tools.box(deck, at + Vector3(cos(a) * 0.88, -0.04, sin(a) * 0.88), Vector3(0.17, 0.20, 0.14), COPPER)
		tooth.rotation.y = -a
	ferry = Node3D.new()
	deck.add_child(ferry)
	tools.box(ferry, Vector3(0, 0.09, 0), Vector3(1.84, 0.22, 1.50), COPPER.darkened(0.24))
	for i in 7:
		tools.box(ferry, Vector3(i * 0.248 - 0.744, 0.229, 0), Vector3(0.223, 0.08, 1.43), COPPER.lightened(0.05))
	for z in [-0.70, 0.70]:
		tools.box(ferry, Vector3(0, 0.52, z), Vector3(1.82, 0.07, 0.06), IRON)
		for x in [-0.84, -0.30, 0.30, 0.84]:
			tools.box(ferry, Vector3(x, 0.35, z), Vector3(0.075, 0.34, 0.05), IRON)
	var ferry_stencil := Label3D.new()
	ferry_stencil.text = "CARRIAGE"
	ferry_stencil.font_size = 56
	ferry_stencil.pixel_size = 0.004
	ferry_stencil.modulate = IRON
	ferry_stencil.outline_size = 0
	ferry_stencil.rotation.x = -PI * 0.5
	ferry.add_child(ferry_stencil)
	ferry_stencil.position = Vector3(0, 0.28, 0.32)
	var base := Vector3(-2.70, 0.19, -1.81)
	tools.drum(deck, base + Vector3(0, 0.23, 0), 0.24, 0.49, IRON)
	form_glass = tools.box(deck, base + Vector3(0, 0.63, 0), Vector3(0.60, 0.60, 0.27), TEAL)
	form_glass.rotation.z = PI / 4.0
	form_glass.material_override = transparent
	form_glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	form_silver = tools.box(deck, base + Vector3(0, 0.63, 0), Vector3(0.73, 0.56, 0.11), TRIM)
	form_silver.rotation = Vector3(-0.22, -0.68, -0.15)
	floor_label("PRISM", base + Vector3(0, 0.06, 0.61), 0.18)
	for side: String in ["west", "east"]:
		var polarity := -1.0 if side == "west" else 1.0
		var pos := Vector3(polarity * 1.64, 0.10, -2.70)
		props[side] = pos
		tools.box(deck, pos + Vector3(0, 0.18, 0), Vector3(0.76, 0.42, 0.59), IRON)
		lamps[side] = tools.drum(deck, pos + Vector3(0, 0.47, 0), 0.25, 0.12, STONE)
		floor_label(side.to_upper() + " PICKUP", pos + Vector3(0, 0.02, -0.58), 0.17)
		spans[side] = Node3D.new()
		deck.add_child(spans[side])
		var cx := polarity * 2.07
		for i in 7:
			tools.box(spans[side], Vector3(cx + (i - 3) * 0.27, 0.11, 0), Vector3(0.25, 0.13, 1.22), COPPER)
		for z in [-0.59, 0.59]:
			tools.box(spans[side], Vector3(cx, 0.25, z), Vector3(1.88, 0.07, 0.08), IRON)
		ghost_spans[side] = tools.box(deck, Vector3(cx, 0.09, 0), Vector3(1.91, 0.045, 1.12), TEAL)
		ghost_spans[side].material_override = transparent
		ghost_spans[side].cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for site: String in ["lamp", "bell", "carriage"]:
		var rig: Node3D = ferry if site == "carriage" else deck
		var position := Vector3(0.52, 0.21, -0.37) if site == "carriage" else (destinations[site] as Vector3) + Vector3(-0.47, 0.24, -0.39)
		tools.drum(rig, position + Vector3(0, 0.21, 0), 0.072, 0.44, IRON)
		props[site] = tools.drum(rig, position + Vector3(0, 0.51, 0), 0.19, 0.19, COPPER)
		pulses[site] = tools.drum(rig, position + Vector3(0, 0.70, 0), 0.13, 0.11, AMBER, true)
		if site != "carriage":
			tools.box(deck, position + Vector3(0.59, -0.07, 0.0), Vector3(1.33, 0.048, 0.048), COPPER)
	var ladder := Vector3(-2.04, 0.16, 0.80)
	for x in 9:
		tools.box(deck, ladder + Vector3((x - 4) * 0.21, 0.02 * x, 0), Vector3(0.051, 0.048, 0.47), IRON.lightened(0.08))
	for z in [-0.25, 0.25]:
		tools.box(deck, ladder + Vector3(0, 0.10, z), Vector3(1.85, 0.06, 0.07), COPPER.darkened(0.12))
	floor_label("DOWN ONLY  ‹", ladder + Vector3(0, 0.04, 0.40), 0.16)
	player = token(COPPER, false)
	echo = token(TEAL, true)
	tools.beam(deck, Vector3(-5, 0.75, -3), base + Vector3(0, 0.63, 0), tools.translucent(Color(1, 0.74, 0.29, 0.43)), "bus_a")
	tools.beam(deck, base + Vector3(0, 0.63, 0), Vector3(-1.6, 0.55, -2.7), tools.translucent(Color(1, 0.74, 0.29, 0.43)), "bus_b")
	path_a = tools.beams.bus_a
	path_b = tools.beams.bus_b
	build_clock(layout.reel_beats)
	cutaway = tools.box(deck, Vector3(-4.57, 0.73, 2.06), Vector3(0.54, 1.42, 0.58), STONE.darkened(0.15))
	cutaway_bounds = AABB(cutaway.position - cutaway.scale * 0.5, cutaway.scale)


func build_clock(beats: int) -> void:
	var x := 1.82
	var z := 2.64
	tools.box(deck, Vector3(x, 0.22, z), Vector3(2.90, 0.56, 1.69), IRON)
	tools.box(deck, Vector3(x, 0.50, z), Vector3(2.86, 0.09, 1.65), COPPER)
	var center := Vector3(x, 0.60, z - 0.13)
	tools.drum(deck, center, 0.59, 0.129, IRON)
	wind_clock = Node3D.new()
	deck.add_child(wind_clock)
	wind_clock.position = center + Vector3(0, 0.10, 0)
	tools.box(wind_clock, Vector3(0.22, 0, 0), Vector3(0.48, 0.039, 0.06), COPPER)
	reel_wheel = Node3D.new()
	deck.add_child(reel_wheel)
	reel_wheel.position = center
	for i in beats:
		var px := x + (float(i) - 3.5) * 0.29
		reel_slots.append(tools.box(deck, Vector3(px, 0.57, z + 0.53), Vector3(0.24, 0.075, 0.31), IRON))
		var rad := i * TAU / float(beats)
		tools.drum(reel_wheel, Vector3(cos(rad) * 0.47, 0.086, sin(rad) * 0.47), 0.035, 0.035, LIGHT)
	phase_meter = tools.box(deck, Vector3(x, 0.59, z - 0.71), Vector3(2.39, 0.055, 0.068), COPPER)
	phase_meter.visible = false
	floor_label("ANCHOR REEL", Vector3(x, 0.62, z + 0.27), 0.19)


func token(hue: Color, is_echo: bool) -> Node3D:
	var n := Node3D.new()
	deck.add_child(n)
	tools.drum(n, Vector3(0, 0.16, 0), 0.25, 0.13, IRON)
	tools.drum(n, Vector3(0, 0.37, 0), 0.14, 0.34, hue, true)
	tools.drum(n, Vector3(0, 0.57, 0), 0.20, 0.12, hue)
	if is_echo:
		for part: MeshInstance3D in n.get_children():
			part.material_override = transparent
			part.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return n


func floor_label(title: String, at: Vector3, size: float) -> void:
	var l := Label3D.new()
	l.text = title
	l.font_size = 56
	l.pixel_size = size / 56.0
	l.modulate = LIGHT
	l.outline_size = 0
	l.rotation.x = -PI * 0.5
	tools.box(deck, at - Vector3(0, 0.016, 0), Vector3(maxf(0.42, size * title.length() * 0.57), 0.026, size * 1.20), IRON)
	deck.add_child(l)
	l.position = at + Vector3.UP * 0.002


func slide(at: String) -> float:
	return {"west": -0.30, "neutral": 0.0, "east": 0.30}.get(at, 0.0)


func draw(s: Dictionary, camera: Camera3D) -> void:
	var receiver: String = s.optics.receiver
	var silver: bool = s.form == "silver"
	form_glass.visible = not silver
	form_silver.visible = silver
	var ferry_x := slide(s.alignment)
	for cue: Dictionary in s.cues:
		if cue.kind in ["swing", "spring"]:
			var t := clampf(float(s.tick - cue.start_tick) / maxf(1.0, float(cue.due_tick - cue.start_tick)), 0.0, 1.0)
			ferry_x = lerpf(slide(cue.from), slide(cue.to), t * 0.60)
			break
	ferry.position.x = ferry_x
	for side: String in spans:
		var enabled: bool = (side == "west" and ["hub", "carriage"] in s.walkable) or (side == "east" and ["carriage", "exit"] in s.walkable)
		spans[side].visible = enabled
		ghost_spans[side].visible = not enabled and receiver == side
		lamps[side].material_override = tools.mat(TEAL if side == receiver else IRON, side == receiver)
	if not s.pair.is_empty() and s.pair.accepted:
		lamps[s.pair.receiver].material_override = tools.mat(AMBER, true)
	player.position = (destinations[s.player] as Vector3) if s.player != "carriage" else ferry.position + Vector3(0.0, 0.22, 0)
	echo.visible = false
	path_a.visible = false
	path_b.visible = false
	for part: MeshInstance3D in pulses.values(): part.visible = false
	for signal_: Dictionary in s.signals:
		var site: String = signal_.source
		pulses[site].visible = true
		pulses[site].material_override = tools.mat(TEAL if signal_.origin == "echo" else AMBER, true)
		if signal_.origin == "echo":
			echo.visible = true
			echo.position = destinations[site] + Vector3(0.35, 0, 0.15)
		if signal_.channel == "light":
			var p: Vector3 = (props.lamp as Node3D).global_position
			var junction: Vector3 = form_glass.position
			tools.set_beam(path_a, p, junction)
			tools.set_beam(path_b, junction, (props[receiver] as Vector3) + Vector3.UP * 0.47)
			path_a.visible = true
			path_b.visible = true
	for i in reel_slots.size():
		var filled: bool = i < s.reel.tape.size()
		var source: String = s.reel.tape[i] if filled else ""
		var hue := AMBER if source == "lamp" else TEAL if source == "bell" else STONE if filled else IRON
		if s.reel.replaying and i == s.reel.cursor - 1: hue = LIGHT
		(reel_slots[i] as MeshInstance3D).material_override = tools.mat(hue, source != "")
	wind_clock.rotation.y = (float(s.reel.cursor) if s.reel.replaying else float(s.reel.recorded)) * PI / 4.0
	phase_meter.visible = not s.cues.is_empty()
	if phase_meter.visible:
		var last: Dictionary = s.cues[-1]
		var t := clampf(float(s.tick - last.start_tick) / maxf(1, float(last.due_tick - last.start_tick)), 0.0, 1.0)
		phase_meter.scale.x = maxf(0.10, 2.39 * t)
		phase_meter.material_override = tools.mat(RUST if last.kind == "spring" else TEAL, true)
	var aim := player.position + Vector3.UP * 0.36
	faded_pier = cutaway_bounds.intersects_segment(aim + camera.global_basis.z * 40.0, aim) != null
	cutaway.material_override = transparent if faded_pier else tools.mat(STONE.darkened(0.15))
	cutaway.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if faded_pier else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

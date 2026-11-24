extends Node3D

const Kit := preload("res://scenes/physics_lab/shutter_loom/ShutterRoom.gd")
const STONE := Color("b6ad95")
const SLATE := Color("546967")
const DARK := Color("374953")
const BRASS := Color("c0975e")
const COPPER := Color("bf6f47")
const LIGHT := Color("f6cd7a")
const AQUA := Color("79d9cb")
const HEAT := Color("f28e62")
const STATIONS := {
	"start": Vector3(0,0,4.52), "jack": Vector3(-2.28,0,2.82), "kiln": Vector3(2.28,0,2.82),
	"yoke": Vector3(0,0,1.06), "brake": Vector3(-2.28,0,-0.68), "weight": Vector3(2.28,0,-0.68),
	"span": Vector3(0,0,-2.52), "exit": Vector3(0,0,-4.86),
}
const FIXTURES := {
	"start": Vector3(-0.92,0,0.46), "jack": Vector3(-0.78,0,0.08), "kiln": Vector3(0.78,0,0.05),
	"yoke": Vector3(-0.75,0,0.24), "brake": Vector3(-0.76,0,0), "weight": Vector3(0.76,0,0),
}
const APPROACH := ["brake", "weight"]
var book := Kit.new()
var deck := Node3D.new()
var drum: Node3D
var runner: Node3D
var pin: MeshInstance3D
var shutter: MeshInstance3D
var braid: MeshInstance3D
var heated_seat: MeshInstance3D
var ballast: MeshInstance3D
var brake: MeshInstance3D
var tension_needle: MeshInstance3D
var shoe_needle: MeshInstance3D
var span_gate: Dictionary
var preload_teeth: Array[MeshInstance3D] = []
var witness: Dictionary
var active_signs: Dictionary
var cue_lamps: Dictionary
var local_witness: MeshInstance3D


func build(model: Dictionary) -> void:
	add_child(deck)
	add_child(book)
	book.deck = deck
	book.box(deck, Vector3(0,-0.66,-0.17), Vector3(8.1,0.50,11.9), DARK.darkened(0.22))
	book.box(deck, Vector3(0,-0.87,-0.17), Vector3(8.16,0.09,11.97), BRASS.darkened(0.34))
	for side in [-1,1]:
		for i in 12:
			var p := Vector3(side * 3.75,-0.27,float(i) - 5.63)
			book.box(deck, p, Vector3(0.60,0.29,0.96), SLATE.darkened(0.10 + 0.015 * (i % 3)))
		for z in [-5.44, -3.68, 0.80, 4.40]:
			var p := Vector3(side * 3.78,0,z)
			book.box(deck, p + Vector3.UP * 0.38, Vector3(0.27,0.76,0.31), STONE.darkened(0.16))
			book.box(deck, p + Vector3.UP * 0.78, Vector3(0.39,0.14,0.39), BRASS)
	for from: String in model.links:
		for to: String in model.links[from]:
			if from > to and from in model.links[to]: continue
			walk(STATIONS[from], STATIONS[to], to == "span" or from == "span")
	for id: String in STATIONS:
		var p: Vector3 = STATIONS[id]
		book.box(deck, p - Vector3.UP * 0.11, Vector3(1.48,0.23,1.22), DARK)
		book.box(deck, p, Vector3(1.39,0.09,1.13), STONE)
		active_signs[id] = book.box(deck, p + Vector3(0,0.054,0.36), Vector3(0.77,0.03,0.06), DARK)
		placard(model.objects[id], p + Vector3(0, 0.07, 0.47), 19)
		if FIXTURES.has(id):
			var mount: Vector3 = p + FIXTURES[id]
			book.box(deck, mount + Vector3.UP * 0.024, Vector3(0.75,0.13,0.65), SLATE)
			cue_lamps[id] = book.drum(deck, mount + Vector3(0.31,0.23,0.15), 0.073, 0.27, HEAT, true)
	build_fixtures()
	var far: Vector3 = STATIONS.exit + Vector3(0,0,-0.39)
	book.arch(far + Vector3.UP * 0.80, 0.68, 0.48, 0.073)
	for side in [-1.0,1.0]:
		book.box(deck, far + Vector3(0.68 * side,0.42,0), Vector3(0.20,0.84,0.26), STONE)
		book.box(deck, far + Vector3(0.68 * side,0.81,0), Vector3(0.27,0.08,0.29), BRASS)
	for approach: String in APPROACH:
		var p: Vector3 = STATIONS[approach].lerp(STATIONS.span,0.43)
		span_gate[approach] = book.box(deck, p + Vector3.UP * 0.16, Vector3(0.46,0.18,0.07), DARK)
		span_gate[approach].rotation.y = 0.58 if approach == "brake" else -0.58
	runner = Node3D.new()
	deck.add_child(runner)
	book.drum(runner, Vector3(0,0.086,0), 0.22, 0.10, DARK)
	book.drum(runner, Vector3(0,0.160,0), 0.185, 0.05, AQUA, true)
	book.drum(runner, Vector3(0,0.312,0), 0.101, 0.27, BRASS)
	book.drum(runner, Vector3(0,0.465,0), 0.152, 0.065, STONE.lightened(0.19))


func walk(a: Vector3, b: Vector3, proof: bool) -> void:
	bar(a - Vector3.UP * 0.12, b - Vector3.UP * 0.12, Vector2(0.86,0.19), DARK if proof else SLATE)
	var direct := (b - a).normalized()
	var cross := direct.cross(Vector3.UP)
	for side in [-1.0,1.0]:
		var edge: Vector3 = cross * side * 0.42
		bar(a + edge,b + edge,Vector2(0.047,0.06),BRASS.darkened(0.25))
		if proof:
			bar(a + edge - Vector3.UP*0.22,b + edge - Vector3.UP*0.22,Vector2(0.055,0.09),COPPER)
	var breaks := maxi(2,roundi(a.distance_to(b) * 3.7))
	for i in range(1, breaks):
		var p := a.lerp(b,float(i)/breaks)
		bar(p-cross*0.36,p+cross*0.36,Vector2(0.034,0.045),BRASS.darkened(0.28) if proof else STONE.darkened(0.17))


func bar(a: Vector3, b: Vector3, width_height: Vector2, tint: Color) -> MeshInstance3D:
	var delta := b - a
	var shape := book.box(deck,a.lerp(b,0.5),Vector3(width_height.x,width_height.y,delta.length()),tint)
	shape.rotation.y = atan2(delta.x, delta.z)
	return shape


func placard(title: String, at: Vector3, size: int) -> void:
	var label := Label3D.new()
	label.text = title.to_upper()
	label.font_size = size * 2
	label.pixel_size = 0.0031
	label.outline_size = 3
	label.modulate = Color("f8e7bc")
	deck.add_child(label)
	label.position = at
	label.rotation.x = -PI * 0.50


func fixture(id: String) -> Vector3:
	return STATIONS[id] + FIXTURES[id]


func build_fixtures() -> void:
	var p := fixture("start")
	for i in 3:
		witness[str(i)] = book.drum(deck,p + Vector3(0.26*(i-1),0.25,0),0.094,0.37,AQUA if i == 0 else BRASS,true)
	local_witness = witness["0"]
	p = fixture("jack")
	book.drum(deck,p + Vector3(0,0.34,0),0.26,0.47,BRASS)
	braid = book.box(deck,p + Vector3(0,0.48,0),Vector3(0.1,0.12,0.40),COPPER)
	for i in 8:
		preload_teeth.append(book.box(deck,p + Vector3(-0.24+0.069*i,0.58,0),Vector3(0.049,0.10,0.34),LIGHT,true))
	p = fixture("kiln")
	book.box(deck,p + Vector3(0,0.31,0),Vector3(0.58,0.56,0.56),SLATE)
	book.box(deck,p + Vector3(0,0.62,0),Vector3(0.67,0.11,0.67),BRASS.darkened(0.17))
	shutter = book.box(deck,p + Vector3(0,0.36,0.294),Vector3(0.50,0.44,0.065),DARK)
	heated_seat = book.box(deck,p + Vector3(0,0.33,0.291),Vector3(0.43,0.20,0.05),COPPER)
	pin = book.drum(deck,p + Vector3(-0.32,0.58,0.20),0.046,0.38,BRASS,true)
	p = fixture("yoke")
	drum = Node3D.new()
	deck.add_child(drum)
	drum.position = p + Vector3(0,0.41,0)
	book.drum(drum,Vector3.ZERO,0.305,0.133,BRASS)
	for j in 12:
		var radians := TAU * j / 12
		var mark := book.box(drum,Vector3(sin(radians),0,cos(radians))*0.286,Vector3(0.034,0.16,0.070),LIGHT if j == 0 else DARK,j == 0)
		mark.rotation.y = radians
	tension_needle = book.box(deck,p + Vector3(-0.24,0.14,0.38),Vector3(0.067,0.10,0.067),AQUA,true)
	shoe_needle = book.box(deck,p + Vector3(0.24,0.14,0.38),Vector3(0.067,0.10,0.067),HEAT,true)
	p = fixture("brake")
	book.drum(deck,p + Vector3(0,0.21,0),0.27,0.31,SLATE)
	brake = book.box(deck,p + Vector3(0,0.42,0),Vector3(0.54,0.08,0.09),COPPER)
	p = fixture("weight")
	for x in [-0.26,0.26]:
		book.box(deck,p + Vector3(x,0.46,0),Vector3(0.065,0.83,0.10),DARK)
	book.box(deck,p + Vector3(0,0.86,0),Vector3(0.59,0.073,0.19),BRASS)
	ballast = book.box(deck,p + Vector3(0,0.16,0),Vector3(0.36,0.22,0.30),COPPER)


func travel_position(state: Dictionary) -> Vector3:
	if not state.travel.is_empty():
		var travel: Dictionary = state.travel
		var t := progress(state.tick, travel.start_tick, travel.due_tick)
		return STATIONS[travel.from].lerp(STATIONS[travel.to],t)
	if not state.crossing.is_empty():
		var cross: Dictionary = state.crossing
		var t := progress(state.tick, cross.start_tick, cross.due_tick)
		if t < 0.48: return STATIONS[cross.from].lerp(STATIONS.span,t / 0.48)
		return STATIONS.span.lerp(STATIONS.exit,(t - 0.48) / 0.52)
	return STATIONS[state.place]


func progress(tick: int, first: int, last: int) -> float:
	return clampf(float(tick-first)/maxf(1.0,last-first),0,1)


func draw(state: Dictionary) -> void:
	runner.position = travel_position(state) + Vector3.UP * 0.06
	for id: String in active_signs:
		active_signs[id].material_override = book.mat(AQUA if id == state.place else SLATE,id == state.place)
	for id: String in cue_lamps: cue_lamps[id].visible = false
	for cue: Dictionary in state.cues:
		var id: String = "kiln" if cue.id == "cut_pin" else "start" if cue.id.begins_with("rewind") else state.place if cue.id == "rider_release" else "yoke"
		if cue_lamps.has(id):
			cue_lamps[id].visible = true
			cue_lamps[id].scale.y = 0.50 + progress(state.tick,cue.start_tick,cue.due_tick)
	for i in preload_teeth.size(): preload_teeth[i].visible = state.retained.preload > i * 8
	braid.rotation.z = -state.retained.preload * 0.008
	pin.position.y = 0.59 if state.local.pin_intact else 0.13
	shutter.position.y = 0.36 if state.local.pin_intact else 0.65
	heated_seat.rotation.z = deg_to_rad(float(state.retained.bend))
	heated_seat.material_override = book.mat(HEAT if state.local.heat >= state.readings.forming_heat else COPPER,state.local.heat >= state.readings.forming_heat)
	ballast.position.y = 0.16 + state.local.ballast * 0.014
	brake.rotation.y = state.local.brake * 0.12
	drum.rotation.y = -TAU * float(state.drum_phase) / 120.0
	local_witness.rotation.y = -TAU * float(state.local_tick % 120) / 120.0
	witness["1"].scale.y = 0.6 if state.marks.has("bench") else 0.17
	witness["2"].scale.y = 0.40 + state.retained.bend * 0.022
	tension_needle.scale.y = clampf(float(state.readings.tension)*0.005,0.04,0.76)
	tension_needle.position.y = 0.10 + tension_needle.scale.y*0.5
	shoe_needle.position.y = 0.23 + clampf(state.readings.shoe * 0.009,-0.12,0.54)
	for approach: String in APPROACH:
		var forecast: Dictionary = state.proof.forecast.get(approach,{})
		var safe: bool = forecast.get("safe",false)
		span_gate[approach].material_override = book.mat(AQUA if safe else HEAT if state.proof.stage == "live" else DARK,safe)
		span_gate[approach].scale.y = 0.043 if safe else 0.18

extends Node3D

const Kit := preload("res://scenes/physics_lab/shutter_loom/ShutterRoom.gd")
const LIMESTONE := Color("c1b99d")
const MOSS := Color("788b79")
const IRON := Color("415b5c")
const BRONZE := Color("bc8c58")
const CERAMIC := Color("bdd9c7")
const AMBER := Color("f9d28b")
const TEAL := Color("72d7c8")
const ALERT := Color("f0a374")
const LANES := ["north","south"]
var book := Kit.new()
var deck := Node3D.new()
var layout: Dictionary
var player := Node3D.new()
var runner_rim: MeshInstance3D
var castings := {}
var warning_castings := {}
var water := {}
var seals := {}
var receivers := {}
var marks := {}
var shutters := {}
var rune_ports := {}
var shuttle := Node3D.new()
var vane := Node3D.new()
var direct: Array[MeshInstance3D] = []
var folded: Array[MeshInstance3D] = []
var wet: Array[MeshInstance3D] = []
var exit_slide: MeshInstance3D
var lamp_glass: Material
var current_glass: Material
var warning_glass: Material
var gate_at: Vector3


func to_world(point: Dictionary, y: float = 0.0) -> Vector3:
	return Vector3((float(point.x) - 514.0) * 0.0104,y,float(point.z) * 0.012)


func room(id: String, y: float = 0) -> Vector3:
	return to_world(layout.rooms[id], y)


func port(id: String, y: float) -> Vector3:
	return to_world(layout.ports[id], y)


func build(plan: Dictionary) -> void:
	layout = plan
	add_child(deck)
	add_child(book)
	book.deck = deck
	lamp_glass = book.translucent(Color(1.0,0.81,0.43,0.77))
	current_glass = book.translucent(Color(0.25,0.86,0.76,0.65))
	warning_glass = book.translucent(Color(0.96,0.51,0.21,0.37))
	book.box(deck,Vector3(0,-0.65,0),Vector3(12.6,0.49,7.48),IRON.darkened(0.19))
	book.box(deck,Vector3(0,-0.865,0),Vector3(12.67,0.08,7.54),BRONZE.darkened(0.38))
	for side in [-1.0,1.0]:
		for i in 13:
			var x := (i-6.0)*0.945
			book.box(deck,Vector3(x,-0.30,3.39*side),Vector3(0.92,0.24,0.50),MOSS.darkened(0.15))
		for x in [-5.52,-3.42,0.74,5.36]:
			var p := Vector3(x,-0.13,side*3.42)
			book.box(deck,p+Vector3.UP*0.25,Vector3(0.21,0.52,0.25),LIMESTONE)
			book.box(deck,p+Vector3.UP*0.52,Vector3(0.32,0.10,0.34),BRONZE)
	for edge: Array in layout.fixed_walk:
		floor_link(room(edge[0]),room(edge[1]))
	floor_link(room("gallery"),room("exit"))
	for id: String in layout.rooms:
		if id.ends_with("_span"): continue
		var at := room(id)
		book.box(deck,at-Vector3.UP*0.17,Vector3(1.37,0.32,1.53),LIMESTONE.darkened(0.30))
		book.box(deck,at,Vector3(1.30,0.075,1.46),LIMESTONE)
		placard(layout.rooms[id].label.replace(" Receiver Pier"," Pier"),at+Vector3(0,0.055,0.42))
	for lane: String in LANES:
		build_lane(lane)
	build_bubble()
	gate_at = room("gallery") + Vector3(0.86,0,0)
	book.arch(gate_at+Vector3.UP*0.79,0.67,0.43,0.082)
	(deck.get_child(deck.get_child_count()-1) as Node3D).rotation.y = PI*0.5
	for z in [-0.67,0.67]:
		book.box(deck,gate_at+Vector3(0,0.38,z),Vector3(0.22,0.76,0.20),LIMESTONE)
		book.box(deck,gate_at+Vector3(0,0.77,z),Vector3(0.29,0.09,0.26),BRONZE)
	exit_slide = book.box(deck,gate_at+Vector3(0,0.37,0),Vector3(0.10,0.72,1.17),IRON)
	for i in 5:
		for bank: Array in [direct,folded,wet]:
			var tag := "path_%d_%d" % [i,book.beams.size()]
			book.beam(deck,Vector3.ZERO,Vector3.UP,lamp_glass if bank != wet else current_glass,tag)
			bank.append(book.beams[tag])
	deck.add_child(player)
	book.drum(player,Vector3(0,0.054,0),0.191,0.075,IRON)
	runner_rim = book.drum(player,Vector3(0,0.115,0),0.176,0.045,TEAL,true)
	book.drum(player,Vector3(0,0.235,0),0.093,0.20,BRONZE)
	book.drum(player,Vector3(0,0.36,0),0.133,0.08,CERAMIC)


func floor_link(a: Vector3, b: Vector3) -> void:
	var d := b-a
	var walk := book.box(deck,a.lerp(b,0.5)-Vector3.UP*0.07,Vector3(0.85,0.19,d.length()),IRON.lightened(0.15))
	walk.rotation.y = atan2(d.x,d.z)
	for i in range(1,7):
		var p := a.lerp(b,float(i)/7)
		var seam := book.box(deck,p+Vector3.UP*0.031,Vector3(0.78,0.014,0.03),LIMESTONE.darkened(0.12))
		seam.rotation.y = walk.rotation.y


func build_lane(lane: String) -> void:
	var center := room(lane+"_span")
	var lane_sign := -1.0 if lane == "north" else 1.0
	var casting := Node3D.new()
	deck.add_child(casting)
	casting.position = center
	castings[lane] = casting
	book.box(casting,Vector3(0,-0.09,0),Vector3(3.55,0.22,0.96),MOSS.darkened(0.22))
	for i in 11:
		book.box(casting,Vector3((i-5.0)*0.307,0.029,0),Vector3(0.284,0.046,0.81),CERAMIC.darkened(0.10+0.017*(i%3)))
	for z in [-0.48,0.48]:
		book.box(casting,Vector3(0,0.04,z),Vector3(3.53,0.077,0.064),BRONZE)
	book.box(deck,center+Vector3(0,-0.29,0),Vector3(3.73,0.15,1.16),IRON.darkened(0.36))
	var ghost := book.box(deck,center+Vector3(0,0.14,0),Vector3(3.50,0.062,0.84),ALERT)
	ghost.material_override = warning_glass
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	warning_castings[lane] = ghost
	var cistern := port(lane+"_cistern",0.04)
	book.drum(deck,cistern,0.377,0.23,IRON)
	book.drum(deck,cistern+Vector3.UP*0.123,0.338,0.052,BRONZE)
	water[lane] = book.drum(deck,cistern+Vector3.UP*0.20,0.288,1.0,TEAL,true)
	var prism := port(lane+"_facet",0.20)+Vector3(0,0,0.53*lane_sign)
	var torus := TorusMesh.new()
	torus.inner_radius=0.14
	torus.outer_radius=0.21
	book.mesh(deck,torus,prism,book.mat(BRONZE))
	var pier := room(lane+"_pier")
	var front := pier+Vector3(0.19,0.21,lane_sign*0.20)
	var folded_at := pier+Vector3(0.41,0.21,lane_sign*0.49)
	for option: Vector3 in [front,folded_at]:
		book.drum(deck,option-Vector3.UP*0.09,0.158,0.18,IRON)
	receivers[lane] = book.drum(deck,front+Vector3.UP*0.026,0.118,0.046,AMBER,true)
	marks[lane] = book.drum(deck,folded_at+Vector3.UP*0.026,0.118,0.046,AMBER,true)
	rune_ports[lane+"_receiver"] = front + Vector3.UP*0.05
	rune_ports[lane+"_mark"] = folded_at + Vector3.UP*0.05
	var mirror := port(lane+"_mirror",0.23)
	var foil := book.box(deck,mirror,Vector3(0.14,0.34,0.26),CERAMIC)
	foil.rotation.y = lane_sign*0.54
	shutters[lane] = book.box(deck,port(lane+"_fold_shutter",0.19),Vector3(0.13,0.32,0.29),BRONZE)
	seals[lane] = book.drum(deck,pier+Vector3(-0.46,0.10,lane_sign*0.47),0.093,0.10,TEAL,true)


func build_bubble() -> void:
	var center := port("liquid_bed",0.56)
	book.drum(deck,center-Vector3.UP*0.73,1.0,0.20,IRON.darkened(0.05))
	var hoop := TorusMesh.new()
	hoop.inner_radius=0.80
	hoop.outer_radius=0.86
	book.mesh(deck,hoop,center-Vector3.UP*0.53,book.mat(BRONZE))
	var shell := SphereMesh.new()
	shell.radius=0.88
	shell.height=1.76
	shell.rings=14
	shell.radial_segments=36
	var glass := book.mesh(deck,shell,center,book.translucent(Color(0.39,0.81,0.77,0.09)))
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for i in 8:
		var theta := TAU*i/8
		book.drum(deck,center+Vector3(cos(theta)*0.78,-0.48,sin(theta)*0.78),0.036,0.05,AMBER if i==0 else MOSS,i==0)
	deck.add_child(shuttle)
	deck.add_child(vane)
	book.drum(shuttle,Vector3.ZERO,0.12,0.13,BRONZE,true)
	book.box(vane,Vector3.ZERO,Vector3(0.70,0.075,0.17),CERAMIC)
	book.box(vane,Vector3(0.34,0,0),Vector3(0.073,0.13,0.20),AMBER,true)
	vane.position = center
	book.drum(deck,port("lamp",0.27),0.14,0.48,BRONZE)
	book.drum(deck,port("lamp",0.51),0.112,0.047,AMBER,true)


func placard(text: String, at: Vector3) -> void:
	var label := Label3D.new()
	label.text = text.to_upper()
	label.font_size=38
	label.pixel_size=0.0031
	label.outline_size=2
	label.modulate=Color("f5e4c4")
	deck.add_child(label)
	label.position=at
	label.rotation.x=-PI*0.5


func set_polyline(bank: Array[MeshInstance3D], paths: Array, y: float, width: float) -> void:
	var index := 0
	for poly: Array in paths:
		for part in poly.size()-1:
			if index >= bank.size(): break
			var a: Vector3 = rune_ports.get(poly[part],port(poly[part],y)) if bank != wet else port(poly[part],y)
			var b: Vector3 = rune_ports.get(poly[part+1],port(poly[part+1],y)) if bank != wet else port(poly[part+1],y)
			var model := bank[index]
			model.visible = a.distance_squared_to(b)>0.00001
			if model.visible:
				book.set_beam(model,a,b)
				model.scale.x = width
				model.scale.z = width
			index += 1
	for i in range(index,bank.size()): bank[i].visible=false


func draw(s: Dictionary) -> void:
	var loc := room(s.player.room,0.06)
	if not s.player.travel.is_empty():
		var walk: Dictionary=s.player.travel
		var t:=1.0-clampf(float(walk.arrive_tick-s.tick)/layout.move_ticks,0,1)
		loc=room(walk.from,0.06).lerp(room(walk.to,0.06),t)
	player.position=loc
	for lane: String in LANES:
		castings[lane].visible = s.support.span == lane+"_span"
		warning_castings[lane].visible = not s.pending.is_empty() and (s.pending.adding_span == lane+"_span" or s.pending.retiring_span == lane+"_span")
		if warning_castings[lane].visible:
			warning_castings[lane].position.y = 0.11 + 0.10*clampf(1.0 - float(s.pending.due_tick-s.tick)/layout.warning_ticks,0,1)
		var vessel: MeshInstance3D = water[lane]
		vessel.scale.y = 0.02 + 0.49*float(s.flow.head[lane])/layout.hydraulics.capacity
		vessel.position.y=0.19+vessel.scale.y*0.50
		seals[lane].visible=s.seals[lane]
		receivers[lane].visible=s.optics.receiver==lane+"_receiver"
		marks[lane].visible=s.optics.mark==lane+"_mark"
		shutters[lane].position.y=0.29 if s.optics.screen_closed else -0.04
	var center := port("liquid_bed",0.56)
	var theta := TAU*float(s.bubble.shuttle.phase)/(layout.phase.notch_units*layout.phase.turn_notches)
	shuttle.position=center+Vector3(cos(theta)*0.55,-0.14,sin(theta)*0.55)
	vane.rotation.y=-TAU*float(s.bubble.vane.phase)/(layout.phase.notch_units*layout.phase.turn_notches)
	set_polyline(direct,s.optics.direct,0.28,0.053)
	set_polyline(folded,s.optics.folded,0.24,0.033)
	set_polyline(wet,s.flow.paths,-0.098,0.099)
	exit_slide.position=gate_at+Vector3(0,0.38,0.62 if s.gate_open else 0.0)

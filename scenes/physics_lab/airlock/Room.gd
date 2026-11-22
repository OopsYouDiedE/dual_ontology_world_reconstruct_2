extends RefCounted
## The moving surface and its optically addressable facets share room coordinates.
const Rules = preload("res://scenes/physics_lab/airlock/Rules.gd")
const Kit = preload("res://scenes/physics_lab/Geometry.gd")
const WORLD := 1
const ACTOR := 2
const FACET := 4
const DECK := 8
const LEAD_HOME := Vector3(-.18, 0, 3.31)
const HALE_HOME := Vector3(1.03, 0, 1.16)
const ISLAND_WATCH := Vector3(.93, 0, -2.79)
const FAR_WATCH := Vector3(6.30, 0, -2.61)
const FAR_MARK := Vector3(6.30, 1.67, -2.18)
const FAR_SECOND := Vector3(6.80,0,-2.49)
const FAR_HIDDEN := Vector3(6.42,0,-3.02)
const B_LANE := -3.87
const A_AIM := Vector3(0, .006, -1.55)
const B_AIM := Vector3(3.55, -.68, -3.218)
const B_RIB := Vector3(3.56,-.90,-3.27)
const B_RIB_SIZE := Vector3(4.72,1.74,.104)
const B_END := 5.84
const STONE := Color("898984")
const PALE := Color("c4c3b8")
const SEAM := Color("383c40")
const DARK := Color("33363a")
const COLD := Color("a9c8cc")
var kit := Kit.new()
var root: Node3D
var spans: Array[Dictionary] = []
var gate: StaticBody3D
var gate_home: float
var lintel: MeshInstance3D
var gate_lamp: StandardMaterial3D
var gateside: Node3D
var entry_notice: Label3D
var relay_marks: Array[StandardMaterial3D] = []


func make(parent: Node3D) -> void:
	root = parent
	kit.root = parent
	_solid(Vector3(2.2,-3.95,-.55), Vector3(16,.32,13), Color("141719"), "catch")
	_solid(Vector3(3.1,4.29,-.62),Vector3(10.06,.23,9.94),Color("25272d"),"ceiling")
	_solid(Vector3(0,-.135,2), Vector3(3.64,.27,4.08), STONE, "near")
	_solid(Vector3(.20,-.135,-3.75), Vector3(2.18,.27,2.31), STONE, "island")
	_solid(Vector3(6.90,-.135,-3.66), Vector3(2.18,.27,3.02), STONE, "far")
	# Tall black baffle across the near bank's view of the second span.
	_solid(Vector3(2.99,.63,-2.25), Vector3(5.34,4.60,.22), DARK, "blind_wall")
	for x in [.61,1.8,3.06,4.32,5.49]:
		kit.box(Vector3(x,1.41,-2.12), Vector3(.024,2.95,.04), SEAM)
	_solid(Vector3(.86,1.25,-2.25), Vector3(.57,3.30,.28), Color("45474b"), "blind_pier")
	# Pass beneath the lintel from the island into B; a standing capsule strikes it.
	_solid(Vector3(1.24,1.77,B_LANE), Vector3(.29,.99,1.55), Color("6a6b68"), "low_lintel")
	kit.box(Vector3(1.25,1.296,B_LANE), Vector3(.34,.042,1.56), PALE)
	for i in range(5):
		kit.box(Vector3(1.083,1.42,B_LANE-.52+i*.26), Vector3(.018,.12,.035), SEAM)
	_solid(Vector3(-1.88,1.65,1.8), Vector3(.2,4.9,4.75), DARK, "west_entry")
	_solid(Vector3(1.88,1.65,1.8), Vector3(.2,4.9,4.75), DARK, "east_entry")
	_solid(Vector3(0,1.75,4.12), Vector3(3.8,4.8,.23), DARK, "entry_wall")
	_solid(Vector3(-1.91,1.15,-3.96), Vector3(.23,6.5,6.82), Color("272a30"), "west_well")
	_solid(Vector3(3.2,1.15,-5.45), Vector3(10.45,6.5,.25), Color("303139"), "north_well")
	_solid(Vector3(8.18,1.12,-3.70), Vector3(.25,6.15,4.84), DARK, "end_wall")
	_solid(Vector3(6.90,.24,-2.13), Vector3(2.22,.48,.16), DARK, "far_rail")
	_solid(Vector3(6.30,1.2,-2.105),Vector3(.82,1.49,.12),DARK,"relay_screen")
	var bar := kit.box(FAR_MARK+Vector3.DOWN*.21,Vector3(.49,.026,.025),PALE)
	bar.material_override = luminous(Color("a7b5b9"),.65)
	var prayer := kit.label("SHOW HIM YOUR BACK.\nTURN AT THE KNOCK.",FAR_MARK,.078)
	prayer.rotation.y = PI
	prayer.modulate = Color("dddcd2")
	# A high shutter clips only the head-height sightline. The optical rib is still visible below it.
	_solid(Vector3(5.97,2.34,-3.10),Vector3(.17,1.78,.46),DARK,"head_shutter")
	# Reflected signal from the side rib, repeated along the back wall.
	kit.box(Vector3(6.59,1.48,-2.115),Vector3(1.63,.102,.12),SEAM)
	for x in [6.28,6.88]:
		for i in range(6):
			var trace := kit.box(Vector3(x+(i-2.5)*.076,1.48,-2.184),Vector3(.054,.044,.022),COLD)
			var mat := luminous(Color("8e9692"),.12)
			trace.material_override = mat
			relay_marks.append(mat)
	_solid(Vector3(-.86,.23,-3.79), Vector3(.13,.46,2.17), SEAM, "island_rail")
	_solid(Vector3(.21,.22,-4.81), Vector3(2.15,.44,.14), DARK, "island_back")
	for z in [3.60, 2.71, 1.82, .93, .06]:
		kit.box(Vector3(0,.003,z), Vector3(3.56,.007,.021), SEAM)
	for x in [-.69,.69]:
		kit.box(Vector3(x,.006,.526), Vector3(.043,.009,.93), PALE)
		kit.box(Vector3(x,.034,-2.68), Vector3(.065,.067,.19), PALE)
	for p in [ISLAND_WATCH, FAR_WATCH]:
		for k in [-1,1]:
			kit.box(p+Vector3(.11*k,.006,0), Vector3(.038,.012,.35), Color("d5d3be"))
	make_span(Vector3(0,-.115,-1.29), Vector3(1.43,.23,2.70), Vector3.ZERO, Vector3.ZERO)
	make_span(Vector3(3.56,-.115,B_LANE), Vector3(4.56,.23,1.19),
		B_RIB, B_RIB_SIZE)
	_gate()
	spans[0]["lamp"] = spot(Vector3(-.13,4.0,-.95), Vector3(0,0,-1.36), Color("c4d8e7"), 4.4, 30)
	spot(Vector3(1.54,2.1,-2.53),Vector3(.88,1.53,-2.94),Color("a6b8bf"),.87,31)
	spot(Vector3(1.1,3.58,-4.04), Vector3(.42,0,-3.67), Color("d8d9d1"), 2.45, 32)
	spans[1]["lamp"] = spot(Vector3(3.55,3.65,-2.59), B_AIM, Color("b1cbd2"), 4.2, 40)
	spot(Vector3(1.0,2.84,2.08), Vector3(.77,.6,1.30), Color("dbcdba"), 2.05, 37)
	spot(Vector3(6.47,3.8,-3.26), Vector3(7.33,.84,-3.91), Color("d4d3c4"), 3.70, 33)
	spot(Vector3(1.32,2.64,.16), Vector3(.99,.95,1.24), Color("b9c7d5"), .94, 37)
	spot(Vector3(-1.05,2.82,1.83), Vector3(-1.73,1.82,.74), Color("bbc6d0"), .96, 39)
	spot(Vector3(3.02,2.62,-4.22),Vector3(1.94,1.55,-3.87),Color("b8c7ca"),2.02,38)
	spot(Vector3(4.29,2.66,-4.55), Vector3(3.44,1.01,-5.26), Color("879aa7"), .77, 44)
	_architecture()
	kit.box(Vector3(-1.605,1.49,.62),Vector3(.052,.42,1.68),SEAM)
	entry_notice = kit.label(Rules.player_notice(),Vector3(-1.575,1.49,.62),.072)
	entry_notice.rotation.y = PI/2.0
	entry_notice.modulate = Color("e2ddd2")
	# A clerestory stripe above the blind wall gives the room depth from the doorway.
	var lamp := kit.box(Vector3(6.25,2.67,-5.27),Vector3(1.38,.062,.10), PALE)
	lamp.material_override = luminous(Color("a8b9bd"), .9)
	for z in [-1.9,-.93,0.05]:
		kit.box(Vector3(-1.77,.98,z),Vector3(.12,.045,.37), SEAM)


func _architecture() -> void:
	for p in [Vector3(-.13,4.08,-.95),Vector3(3.55,4.09,-2.65)]:
		kit.box(p+Vector3.UP*.035,Vector3(.43,.115,.50),DARK)
		var slot := kit.box(p,Vector3(.20,.023,.38),COLD)
		slot.material_override = luminous(Color("afbdc4"),1.4)
	for z in [2.66,1.05,-.44,-1.85]:
		kit.box(Vector3(-1.772,1.46,z),Vector3(.12,2.92,.082),Color("555961"))
		kit.box(Vector3(-1.699,1.37,z+.069),Vector3(.013,2.65,.019),SEAM)
	for side: float in [-1.0,1.0]:
		_solid(Vector3(side*1.22,.22,.025),Vector3(.99,.44,.21),DARK,"edge_rail")
		var marker := kit.box(Vector3(side*.83,.46,.025),Vector3(.078,.022,.20),PALE)
		marker.material_override = luminous(Color("a8aaa2"),.32)
	kit.box(Vector3(-1.64,2.97,-.53),Vector3(.17,.13,3.75),SEAM)
	for x in [.62,1.91,3.19,4.47,5.37]:
		kit.box(Vector3(x,2.88,-2.11),Vector3(.039,.18,.038),Color("777a7b"))
	kit.box(Vector3(3.03,2.96,-2.106),Vector3(5.02,.026,.028),Color("676e73"))
	var mark := kit.label("I",Vector3(.91,1.27,-2.096),.23)
	mark.modulate = Color("cfcdc3")
	var turn := kit.label("II",Vector3(1.079,1.50,B_LANE),.10)
	turn.rotation.y = -PI/2.0
	turn.modulate = Color("d4d2c7")
	for i in range(12):
		kit.box(Vector3(1.61+i*.37,1.18,-5.302),Vector3(.022,2.29,.022),Color("474b52"))


func _solid(at: Vector3, size: Vector3, color: Color, tag: String, layer: int = WORLD) -> StaticBody3D:
	var b := StaticBody3D.new()
	root.add_child(b)
	b.position = at
	b.collision_layer = layer
	b.collision_mask = 0
	b.set_meta("surface", tag)
	var s := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	s.shape = shape
	b.add_child(s)
	if layer != FACET: kit.box(Vector3.ZERO, size, color, b)
	return b


func make_span(at: Vector3, size: Vector3, rib_at: Vector3, rib_size: Vector3) -> void:
	var idx := spans.size()
	var solid := _solid(at, size, PALE, "floor_%s" % idx, DECK)
	var mesh := solid.get_child(1) as MeshInstance3D
	var optical := _solid(at if idx == 0 else rib_at, size if idx == 0 else rib_size, PALE, "span_%s" % idx, FACET)
	var rib := mesh if idx == 0 else kit.box(rib_at, rib_size, COLD)
	var frame := kit.node(Vector3.ZERO)
	var ghost := kit.node(Vector3.ZERO)
	var line_mat := luminous(Color("91acb6"), .26)
	for i in range(10 if idx == 0 else 18):
		var p := float(i) / float(9 if idx == 0 else 17) - .5
		var v := at + Vector3(0, .116, p * (size.z-.07)) if idx == 0 else at + Vector3(p * (size.x-.08),.116,0)
		kit.box(v, Vector3(size.x - .08,.009,.021) if idx == 0 else Vector3(.025,.009,size.z-.05), SEAM, frame)
		if i % 3 == 0:
			var trace := kit.box(v - Vector3.UP*.068, Vector3(size.x-.13,.022,.020) if idx == 0 else Vector3(.023,.020,size.z-.06), COLD, ghost)
			trace.material_override = line_mat
	if idx == 1:
		for i in range(10):
			kit.box(Vector3(1.47 + i*.47,-.158,-3.256), Vector3(.065,.18,.13), SEAM, frame)
		# The residual trace never resembles a walkable tread; it marks the optical face itself.
		for h in [-.77,-.02,.77]:
			var guide := kit.box(rib_at+Vector3(0,h,rib_size.z*.52), Vector3(rib_size.x,.021,.024),COLD,ghost)
			guide.material_override = line_mat
	var steel := kit.mat(Color("9eafb0"))
	var warm := luminous(Color("c1ac93"), 1.05)
	spans.append({"solid":solid,"optic":optical,"surface":mesh,"rib":rib,"frame":frame,"ghost":ghost,
		"clear":steel,"warn":warm,"aspect":"DARK","red":luminous(Color("72151a"),.44),"red_accent":luminous(Color("d71b21"),.84),"focus":A_AIM if idx==0 else B_AIM,"normal":Vector3.UP if idx==0 else Vector3.BACK})
	paint(idx, false, 0)


func paint(i: int, solid_now: bool, warning_age: int, red_age := 0, qualified := true) -> void:
	var s := spans[i]
	s.aspect = "RED" if red_age > 0 else ("FADE" if warning_age > 0 and solid_now else ("WHITE" if solid_now and qualified else "DARK"))
	s.solid.collision_layer = DECK if solid_now else 0
	s.surface.visible = solid_now
	s.frame.visible = solid_now
	s.rib.visible = solid_now
	s.ghost.visible = not solid_now
	var flash := warning_age > 0 and warning_age % 24 < 12
	if red_age > 0:
		# Thin seams buckle while the real foot-bearing envelope stays fixed during warning.
		for seam in s.frame.get_children():
			seam.rotation.y = .14*sin(float(red_age)*.39+seam.position.length_squared())
			seam.material_override = s.red_accent
		s.surface.material_override = s.red if i == 0 else kit.mat(PALE)
		if i == 1: s.rib.material_override = s.red
	else:
		for seam in s.frame.get_children():
			seam.rotation.y = 0.0
			seam.material_override = kit.mat(SEAM)
		s.surface.material_override = s.warn if flash else (s.clear if i == 0 else kit.mat(PALE))
		s.rib.material_override = s.warn if flash else (s.clear if qualified else kit.mat(DARK))


func paint_relay(dark: int, red: bool) -> void:
	for i in range(relay_marks.size()):
		var mark := relay_marks[i]
		var lit := dark < (i%6+1)*10
		mark.emission = Color("a04642") if red else (Color("b9a694") if dark > 0 else Color("9eafb0"))
		mark.emission_energy_multiplier = (1.12 if dark > 0 else .28) if lit else .025


func spot(from: Vector3, toward: Vector3, color: Color, energy: float, angle: float) -> SpotLight3D:
	var s := SpotLight3D.new()
	root.add_child(s)
	s.position = from
	s.look_at(toward)
	s.light_color = color
	s.light_energy = energy
	s.spot_angle = angle
	s.spot_range = 10.0
	s.shadow_enabled = true
	return s


func luminous(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = .92
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _gate() -> void:
	var x := 7.48
	var z := -3.95
	gate_home = 1.10
	gate = _solid(Vector3(x,gate_home,z),Vector3(.19,2.20,1.36),SEAM,"exit_leaf")
	for dz in [-.83,.83]:
		_solid(Vector3(x,1.30,z+dz),Vector3(.40,2.61,.30),STONE,"gate_jamb")
		kit.box(Vector3(x-.214,1.31,z+dz), Vector3(.022,2.42,.035),PALE)
	_solid(Vector3(x,2.51,z),Vector3(.42,.54,1.9),STONE,"gate_head")
	for i in range(6):
		kit.box(Vector3(-.101,0,-.53+i*.21),Vector3(.018,2.03,.021),DARK,gate)
	gate_lamp = luminous(Color("8f9a94"), .22)
	lintel = kit.box(Vector3(x-.219,2.43,z),Vector3(.029,.056,.77),COLD)
	lintel.material_override = gate_lamp
	var mark := kit.label("03 / NORTH SERVICE", Vector3(x-.229,2.63,z),.096)
	mark.rotation.y = -PI/2.0
	mark.modulate = Color("dedbd1")
	gateside = kit.node(Vector3(x-.20,1.2,z-.98))


func lift_gate(amount: float) -> void:
	gate.position.y = gate_home + 2.43 * amount
	gate_lamp.emission_energy_multiplier = lerpf(.22, 1.75, amount)

extends RefCounted
## Cutaway gallery. Reuses the Hall lighting/ink and ArchBuilder ribs.
const R = preload("res://scenes/physics_lab/evidence_register/RegisterRules.gd")
const Kit = preload("res://scenes/physics_lab/Geometry.gd")
const FINISH = preload("res://scenes/blue_prince_lab/HallFinish.gdshader")
const HALL_ATMOSPHERE = preload("res://scenes/components/rendering/post/Hall04.tres")
const INK_PASS = preload("res://scenes/components/rendering/post/InkPass.gd")
const Gothic = preload("res://tools/building_construction/production/rule/GothicRecipes.gd")
const Geo = preload("res://tools/building_construction/BuildingConstruction/Shared/RecipeGeometry.gd")
const Profile = preload("res://scenes/components/rendering/AcademyRenderProfile.gd")
const STONE := Color("89959c")
const IVORY := Color("c0bdab")
const BASE := Color("404d59")
const INK := Color("263644")
const BRASS := Color("ba9456")
const BLUE := Color("427897")
const GOLD := Color("efb05a")
const RED := Color("ef514a")
const RUG := Color("405e65")
const WOOD := Color("523f36")
var kit := Kit.new()
var camera: Camera3D
var ink: MeshInstance3D
var world_env: WorldEnvironment
var runner: Node3D
var reader: Node3D
var book: MeshInstance3D
var prism: Node3D
var wax: Node3D
var latch: Node3D
var slider: Node3D
var brace: Node3D
var beam: MeshInstance3D
var signal_glass: MeshInstance3D
var mark_label: Label3D
var dial_mark: MeshInstance3D
var dial_label: Label3D
var warm_cone: MeshInstance3D
var cool_cone: MeshInstance3D
var mounted: Dictionary = {}
var finishes: Dictionary = {}


func make(scene: Node3D) -> void:
	kit.root = scene
	world_env = WorldEnvironment.new()
	world_env.environment = HALL_ATMOSPHERE.duplicate()
	if DisplayServer.get_name() == "headless": world_env.environment.sdfgi_enabled = false
	scene.add_child(world_env)
	ink = INK_PASS.create()
	ink.name = "RegisterInk"
	ink.material_override.set_shader_parameter("opacity", 0.40)
	scene.add_child(ink)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 11.60
	camera.h_offset = 2.88
	camera.v_offset = 1.00
	scene.add_child(camera)
	camera.position = Vector3(6.8, 8.9, 12.6)
	camera.look_at(Vector3(0, 0.45, 0), Vector3.UP)
	camera.make_current()
	var key := DirectionalLight3D.new()
	scene.add_child(key)
	key.rotation_degrees = Vector3(-54, -29, 0)
	key.light_energy = 1.22
	key.light_color = Color("ffe8cc")
	key.shadow_enabled = true
	_point_light(Vector3(-4.1, 2.04, -2.7), Color("99ccff"), 1.3, 3.2)
	_point_light(Vector3(2.9, 1.7, -2.06), Color("ffc084"), 1.5, 3.9)
	_platform()
	_architecture()
	_fixtures()


func _box(at: Vector3, size: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	return _opaque(kit.box(at, size, color, parent), color)


func _finish(tint: Color, emission := 0.0) -> ShaderMaterial:
	var id := "%s:%.3f" % [tint.to_html(), emission]
	if not finishes.has(id):
		var m := ShaderMaterial.new()
		m.shader = FINISH
		m.set_shader_parameter("pigment", tint)
		m.set_shader_parameter("grain", 0.10)
		m.set_shader_parameter("surface_roughness", 0.50 if tint == BRASS else 0.79)
		m.set_shader_parameter("wood", 1.0 if tint == WOOD else 0.0)
		m.set_shader_parameter("emission_gain", emission)
		finishes[id] = m
	return finishes[id]


func _opaque(piece: MeshInstance3D, tone: Color) -> MeshInstance3D:
	piece.material_override = _finish(tone)
	return piece


func _cylinder(at: Vector3, radius: float, length: float, tone: Color, parent: Node3D = null) -> MeshInstance3D:
	return _opaque(kit.cylinder(at, radius, length, tone, parent), tone)


func _sphere(at: Vector3, radius: float, tone: Color, parent: Node3D = null) -> MeshInstance3D:
	return _opaque(kit.sphere(at, radius, tone, parent), tone)


func _ring(at: Vector3, radius: float, thickness: float, tone: Color, parent: Node3D = null) -> MeshInstance3D:
	return _opaque(kit.ring(at, radius, thickness, tone, parent), tone)


func _line(a: Vector3, b: Vector3, thickness: float, tone: Color, parent: Node3D = null) -> MeshInstance3D:
	return _opaque(kit.line(a, b, thickness, tone, parent), tone)


func _sized(bounds: AABB, tone: Color) -> void:
	_box(bounds.get_center(), bounds.size, tone)


func _light_material(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func _point_light(at: Vector3, color: Color, power: float, reach: float) -> void:
	var light := OmniLight3D.new()
	kit.root.add_child(light)
	light.position = at
	light.light_color = color
	light.light_energy = power
	light.omni_range = reach
	Profile.tune_omni_light(light, "lantern")


func _platform() -> void:
	_box(Vector3(0,-0.43,0), Vector3(11.1,0.46,7.7), INK)
	_box(Vector3(0,-0.19,0), Vector3(11.25,0.17,7.85), BASE)
	_box(Vector3(0,-0.093,0), Vector3(11.0,0.16,7.6), IVORY)
	for x in range(-5, 6):
		for z in range(-3, 4):
			var tone := STONE.lerp(IVORY, 0.14 + 0.17 * posmod(3 * x + 5 * z, 4))
			_box(Vector3(x,-0.016,z), Vector3(0.982,0.045,0.982), tone)
	_box(Vector3(1.65,0.014,2.21), Vector3(5.25,0.025,1.02), RUG)
	_box(Vector3(-2.1,0.015,1.07), Vector3(1.03,0.025,3.28), RUG).rotation.y = -0.58
	for z in [1.75,2.67]: _box(Vector3(1.64,0.031,z), Vector3(5.25,0.006,0.028), BRASS)
	for id: String in R.STATIONS:
		var p: Vector3 = R.STATIONS[id]
		_ring(p + Vector3.UP * 0.039, 0.36, 0.019, BRASS)
		mounted[id] = _cylinder(p + Vector3.UP * 0.02, 0.31, 0.031, BASE)


func _architecture() -> void:
	_box(Vector3(0,1.25,-3.70), Vector3(11.0,2.5,0.20), BASE)
	for y in [0.12,0.68,2.48,2.58]:
		_box(Vector3(0,y,-3.68), Vector3(11.04,0.085,0.31), IVORY if y > 2 else STONE)
	for i in range(4):
		var x := -4.17 + 2.78 * i
		_box(Vector3(x,0.48,-3.57), Vector3(2.55,0.35,0.040), INK)
		_lancet(x, -3.55, 0.94, 0.90, 1.22, Color("597a92") if i < 2 else Color("8d745b"))
	for x in [-5.48,-2.78,0.0,2.78,5.48]:
		_box(Vector3(x,1.25,-3.55), Vector3(0.23,2.50,0.35), STONE)
		for y in [0.18,0.73,1.68,2.46]:
			_box(Vector3(x,y,-3.53), Vector3(0.32,0.085,0.39), IVORY)
	_box(Vector3(-5.48,0.45,-0.67), Vector3(0.22,0.9,6.02), BASE)
	_box(Vector3(-5.48,0.9,-0.67), Vector3(0.33,0.085,6.02), STONE)
	_sized(R.WALL, BASE)
	for i in range(8):
		var y := 0.21 + i * 0.273
		for j in range(7):
			var z := -3.34 + j * 0.55 + 0.045 * (i % 2)
			var tone := STONE.lerp(BASE, 0.13 * posmod(i * 5 + j * 3, 5))
			for x in [-0.228, 0.228]: _box(Vector3(x,y,z), Vector3(0.016,0.252,0.523), tone)
	_box(Vector3(0,2.36,-1.63), Vector3(0.57,0.094,4.13), IVORY)
	_box(Vector3(0,1.16,0.38), Vector3(0.53,2.33,0.19), BASE)
	for y in [0.16,1.83,2.30]: _box(Vector3(0,y,0.40), Vector3(0.65,0.07,0.24), IVORY)
	_sized(R.BAFFLE, INK)
	_box(R.BAFFLE.get_center() + Vector3.UP * 0.52, Vector3(0.59,0.045,0.54), BRASS)


func _lancet(x: float, z: float, base: float, width: float, spring: float, glaze: Color) -> void:
	_box(Vector3(x,base + 0.45,z), Vector3(width * 1.92,0.9,0.045), INK)
	_box(Vector3(x,base + 0.47,z + 0.03), Vector3(width * 1.68,0.85,0.026), glaze)
	for xp in [x - width, x + width]:
		_box(Vector3(xp,base + 0.42,z), Vector3(0.125,0.88,0.14), IVORY)
	_box(Vector3(x,base - 0.035,z + 0.04), Vector3(width * 2.17,0.10,0.23), IVORY)
	for xp in [x - width * 0.44,x,x + width * 0.44]:
		_box(Vector3(xp,base + 0.46,z + 0.055), Vector3(0.038,0.87,0.027), BASE)
	_box(Vector3(x,base + 0.44,z + 0.055), Vector3(width * 1.68,0.028,0.025), BASE)
	var rib := Geo.finish(Gothic.gen_gothic_pointed_rib("RegisterLancet", {"cream": _finish(IVORY), "stone": _finish(STONE)},
		width, 0.0, spring - 0.58, 0.077, 10))
	kit.root.add_child(rib)
	rib.position = Vector3(x,base + 0.87,z + 0.039)
	_ring(Vector3(x,base + 0.98,z + 0.031), 0.175, 0.035, BRASS).rotation.x = PI / 2


func _desk(at: Vector3, width: float, depth: float) -> void:
	_box(at + Vector3.UP * 0.79, Vector3(width,0.11,depth), WOOD)
	_box(at + Vector3.UP * 0.73, Vector3(width + 0.024,0.029,depth+0.024), BRASS)
	for x in [-0.41,0.41]:
		for z in [-0.37,0.37]:
			_box(at + Vector3(x * width,0.34,z * depth), Vector3(0.13,0.69,0.13), BASE)


func _fixture_label(text: String, at: Vector3, scale_value: float) -> Label3D:
	var l := kit.label(text, at, scale_value)
	l.modulate = Color("fff1d2")
	l.outline_size = 7
	l.outline_modulate = INK
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	return l


func _fixtures() -> void:
	_desk(Vector3(-4.08,0,-2.72),1.92,0.81)
	_box(Vector3(-4.08,0.86,-2.72), Vector3(1.52,0.053,0.62), RUG)
	mark_label = _fixture_label("", Vector3(-4.06,1.60,-2.77), 0.24)
	prism = _token(true)
	wax = _token(false)
	_box(Vector3(-0.53,0.65,-0.61),Vector3(0.43,0.68,0.78), WOOD)
	_box(Vector3(0.48,0.66,-0.61),Vector3(0.64,0.49,0.79), WOOD)
	_box(Vector3(-0.02,0.91,-0.61),Vector3(1.62,0.25,0.61), INK)
	for x in [-0.80,0.80]:
		_box(Vector3(x,0.91,-0.61),Vector3(0.045,0.28,0.67), BRASS)
		_box(Vector3(x * 1.022,0.91,-0.61),Vector3(0.051,0.12,0.42), INK)
	for z in [-0.82,-0.40]: _box(Vector3(0,1.06,z),Vector3(1.72,0.045,0.026), BRASS)
	slider = kit.node(R.LOAD)
	_box(Vector3(0,-0.10,0),Vector3(0.56,0.12,0.43),BRASS,slider)
	_box(Vector3(0,-0.024,0),Vector3(0.35,0.03,0.30),BASE,slider)
	# Shared proof stand, split rail and mechanical pull lever.
	for z in [-0.50,-0.16,0.18,0.52,0.86,1.20]:
		_box(Vector3(0.79,0.038,z),Vector3(0.35,0.055,0.046),BASE)
	for x in [0.68,0.90]: _box(Vector3(x,0.079,0.53),Vector3(0.045,0.029,2.17),BRASS)
	# The verification dial sits beside the blind slide, operated remotely at Proof.
	var spindle := Vector3(-0.55,0.95,0.42)
	_box(spindle - Vector3.UP * 0.43,Vector3(0.24,0.87,0.26),BASE)
	_cylinder(spindle,0.25,0.10,BRASS)
	_cylinder(spindle + Vector3.UP * 0.063,0.19,0.035,INK)
	dial_mark = _box(spindle + Vector3.UP * 0.09,Vector3(0.256,0.029,0.042),IVORY)
	dial_label = _fixture_label("", spindle + Vector3.UP * 0.25, 0.16)
	var proof := R.PITCH - Vector3.UP * 0.19
	_cylinder(Vector3(proof.x,0.50,proof.z),0.095,0.88,BASE)
	_cylinder(Vector3(proof.x,0.095,proof.z),0.36,0.16,INK)
	_cylinder(proof,0.27,0.09,BRASS)
	_ring(proof + Vector3.UP * 0.105,0.28,0.024,GOLD)
	_box(Vector3(-0.23,0.52,1.54),Vector3(0.19,1.02,0.19),INK)
	_sphere(Vector3(-0.23,1.04,1.54),0.115,BRASS)
	_desk(Vector3(2.74,0,-0.99),1.62,0.65)
	_box(Vector3(2.74,0.855,-0.99),Vector3(1.24,0.027,0.47),RUG)
	reader = _figure(Vector3(R.READER.x,0,R.READER.z), Color("786652"), GOLD)
	reader.rotation.y = atan2(R.READER_FACING.x, R.READER_FACING.z)
	book = _box(Vector3(2.61,0.90,-0.93),Vector3(0.47,0.08,0.34),BLUE)
	_box(Vector3(2.61,0.919,-0.93),Vector3(0.34,0.011,0.23),IVORY)
	_fixture_label("CLERK", Vector3(2.74,2.04,-1.76), 0.23)
	runner = _figure(R.STATIONS.survey,Color("3e7590"),Color("a7d8ee"))
	runner.rotation.y = PI
	# Gate oriented across the threshold, read in silhouette from the cutaway.
	var portal := kit.node(Vector3(4.84,0,2.20))
	portal.rotation.y = PI / 2
	for x in [-0.70,0.70]:
		_box(Vector3(x,0.98,0),Vector3(0.21,1.96,0.31),STONE,portal)
		_box(Vector3(x,0.15,0),Vector3(0.35,0.25,0.40),IVORY,portal)
	var rib := Geo.finish(Gothic.gen_gothic_pointed_rib("RegisterGate", {"cream": _finish(IVORY), "stone": _finish(STONE)},
		0.70, 0.0, 0.71, 0.118, 12))
	portal.add_child(rib)
	rib.position.y = 1.84
	latch = kit.node(Vector3.ZERO,portal)
	for x in [-0.48,-0.24,0.0,0.24,0.48]: _box(Vector3(x,0.91,0),Vector3(0.057,1.78,0.09),INK,latch)
	for y in [0.4,0.94,1.46]: _box(Vector3(0,y,0),Vector3(1.18,0.058,0.12),BRASS,latch)
	brace = kit.node(Vector3(4.57,0,2.70))
	_line(Vector3(0,0.11,0),Vector3(0,0.86,-0.97),0.065,BRASS,brace)
	var console := Vector3(3.71,0,3.07)
	_box(console + Vector3.UP * 0.31,Vector3(0.43,0.62,0.39),BASE)
	_box(console + Vector3.UP * 0.66,Vector3(0.49,0.10,0.47),WOOD)
	signal_glass = _sphere(console + Vector3.UP * 0.79, 0.101, GOLD)
	signal_glass.material_override = _light_material(GOLD, 1.4)
	beam = _line(R.PITCH, R.READER, 0.018, GOLD)
	beam.material_override = _finish(Color("ffd08a"), 2.0)
	warm_cone = _cone(R.READER, R.READER_FACING, 3.7, Color("f1a658"))
	var source_eye: Vector3 = R.STATIONS.survey + Vector3.UP * 1.6
	cool_cone = _cone(source_eye, R.SOURCE - source_eye, 2.20, Color("69c7f2"))


func _token(live: bool) -> Node3D:
	var p := kit.node(Vector3.ZERO)
	var crystal := _cylinder(Vector3(0,0.02,0),0.136,0.22,GOLD if live else Color("ad7964"),p)
	(crystal.mesh as CylinderMesh).radial_segments = 6
	(crystal.mesh as CylinderMesh).top_radius = 0.057 if live else 0.123
	if live:
		crystal.material_override = _finish(Color("ffb854"), 1.15)
	_cylinder(Vector3(0,-0.097,0),0.13,0.021,BRASS if live else WOOD,p)
	return p


func _figure(at: Vector3, coat: Color, band: Color) -> Node3D:
	# Abstract, 1.72 m role markers on plinths rather than production character assets.
	var p := kit.node(at)
	_cylinder(Vector3(0,0.073,0),0.235,0.11,INK,p)
	for x in [-0.107,0.107]:
		_box(Vector3(x,0.29,0),Vector3(0.12,0.43,0.17),INK,p)
	var mantle := _cylinder(Vector3(0,0.85,0),0.245,0.79,coat,p)
	(mantle.mesh as CylinderMesh).radial_segments = 8
	(mantle.mesh as CylinderMesh).top_radius = 0.167
	_box(Vector3(0,1.14,0.10),Vector3(0.21,0.14,0.085),band,p)
	_sphere(Vector3(0,1.43,0),0.151,Color("d4aa87"),p)
	_cylinder(Vector3(0,1.565,0),0.192,0.072,INK,p)
	_cylinder(Vector3(0,1.633,0),0.115,0.095,coat,p)
	return p


func _cone(eye: Vector3, forward: Vector3, reach: float, tint: Color) -> MeshInstance3D:
	var heading := Vector2(forward.x, forward.z).angle()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base := Vector3(eye.x,0.047,eye.z)
	var angle := acos(0.68)
	for i in range(18):
		var a := heading + lerpf(-angle,angle,float(i) / 18.0)
		var b := heading + lerpf(-angle,angle,float(i + 1) / 18.0)
		surface.add_vertex(base)
		surface.add_vertex(base + reach * Vector3(cos(a),0,sin(a)))
		surface.add_vertex(base + reach * Vector3(cos(b),0,sin(b)))
	var m := _light_material(tint,0.28)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color.a = 0.24
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mesh := kit.piece(surface.commit(), Vector3.ZERO, tint)
	mesh.material_override = m
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


func render(rules: R) -> void:
	runner.position = rules.runner_position()
	match rules.station:
		"survey": runner.rotation.y = PI
		"drawer": runner.rotation.y = PI * 0.5
		"proof": runner.rotation.y = 2.45
		"threshold": runner.rotation.y = PI * 0.5
	var sample := rules.sample_position()
	var received := rules.received if rules.arrives < 0 else rules.transit
	_set_token(prism,"prism",received,sample,rules,R.SOURCE + Vector3.LEFT * 0.37)
	_set_token(wax,"wax",received,sample,rules,R.SOURCE + Vector3.RIGHT * 0.37)
	slider.position = Vector3(sample.x, R.LOAD.y, R.LOAD.z) if rules.arrives >= 0 else (R.HOOD if received != "" else R.LOAD)
	latch.position.y = 1.63 if rules.latch_at >= 0 else 0.0
	latch.visible = rules.latch_at < 0
	brace.visible = rules.braced
	beam.visible = rules.proof_active and rules.station == "proof" and rules.received == "prism" and rules.sample_rays >= 14
	warm_cone.visible = rules.optics or rules.proof_active
	cool_cone.visible = rules.optics
	var warning := rules.panic_at >= 0
	reader.rotation.z = sin(rules.tick * 0.61) * 0.07 if warning else 0.0
	book.material_override = _finish(IVORY if rules.manual.edition == "IV" else BLUE)
	var tint := RED if warning or (rules.panic_fired and rules.latch_at < 0) else (Color("82d7a1") if rules.latch_at >= 0 else GOLD)
	var lamp := signal_glass.material_override as StandardMaterial3D
	lamp.albedo_color = tint
	lamp.emission = tint
	mark_label.text = rules.mark().to_upper() + "  /  LIVE & WAX"
	dial_mark.rotation.y = -0.65 if rules.dial == "sun" else (0.65 if rules.dial == "moon" else 0.0)
	dial_label.text = "DIAL" if rules.dial == "" else rules.dial.to_upper()
	for id in mounted:
		mounted[id].material_override = _finish(BLUE if id == rules.station else BASE)


func _set_token(token: Node3D, id: String, received: String, sample: Vector3, rules: R, bench: Vector3) -> void:
	token.position = sample if received == id else (runner.position + Vector3(0.18,1.13,0.23) if rules.held == id else bench)
	token.visible = not (received == id and rules.arrives >= 0 and absf(sample.x) < 0.34)

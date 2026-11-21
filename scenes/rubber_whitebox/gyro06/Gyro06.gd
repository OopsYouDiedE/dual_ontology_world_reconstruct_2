extends Node3D
## No audition logic: this is a walkable kinetic sculpture and its four review cameras.

const G := preload("FoundryMesh.gd")
const STOCK := preload("Stock.gdshader")
const DIAMETER := 24.0
const CROWN_HEIGHT := 16.0
const RADIUS := 9.92
const PIVOT_Y := 0.24
const TILT := 24.0 * PI / 180.0
const DECK := 7.0
const HZ := 60
const PRECESS_STEPS := 1200
const SPIN_STEPS := 488
const APPROACH := 11.38
const PIVOT := Vector3(0.0, PIVOT_Y, 0.0)
const ACTIONS := {
	"gyro_a": KEY_1, "gyro_b": KEY_2, "gyro_c": KEY_3, "gyro_d": KEY_4,
	"gyro_hide": KEY_H, "gyro_pause": KEY_SPACE, "gyro_walk": KEY_ENTER,
	"gyro_forward": KEY_W, "gyro_back": KEY_S, "gyro_left": KEY_A, "gyro_right": KEY_D
}

@export_file("*.glb", "*.gltf") var gyro_model_path := ""
@export var gyro_model_source := "" # Upstream URL / accession / archival record.
@export var gyro_model_license := "" # SPDX identifier or full reuse terms.

var step := 0
var seed_value := 6
var hole_count := 3
var precess_sign := 1
var spin_sign := 1
var phase := 0.0
var spin_phase := 0.0
var stair_angle := 0.0
var stair_span := 1.08
var overview_angle := 0.0
var review_view := ""
var running := true
var concealed := false
var external_active := false
var cut_items: Array[GeometryInstance3D] = []
var bridges: Array[AnimatableBody3D] = []
var bridge_angles: Array[float] = []
var side_guards: Array[Array] = []
var wheel: AnimatableBody3D
var construction: Node3D
var rotor_shapes: Array[CollisionShape3D] = []
var camera: Camera3D
var eye: Camera3D
var player: CharacterBody3D
var title: Label
var detail: Label
var stone: Material
var pale: Material
var iron: Material
var bronze: Material
var lip: Material
var mark: Material
var chalk: Material
var lamp: Material
var shaft_light: DirectionalLight3D

func _ready() -> void:
	Engine.physics_ticks_per_second = HZ
	get_viewport().msaa_3d = Viewport.MSAA_4X
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--run-seed="):
			seed_value = int(argument.get_slice("=", 1))
		if argument.begins_with("--gyro-model="):
			gyro_model_path = argument.trim_prefix("--gyro-model=")
		if argument.begins_with("--gyro-source="):
			gyro_model_source = argument.trim_prefix("--gyro-source=")
		if argument.begins_with("--gyro-license="):
			gyro_model_license = argument.trim_prefix("--gyro-license=")
	for action in ACTIONS:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var key := InputEventKey.new()
			key.physical_keycode = ACTIONS[action]
			InputMap.action_add_event(action, key)
	build_06_art(seed_value)
	make_controls()
	if Array(OS.get_cmdline_user_args()).any(func(arg: String) -> bool: return arg.begins_with("--rogue-mcp-dir=")):
		get_window().content_scale_size = Vector2i(1600,1000)
		show_view("A")

func build_06_art(seed: int) -> void:
	seed_value = seed
	if is_instance_valid(construction):
		remove_child(construction)
		construction.queue_free()
	construction = Node3D.new()
	construction.name = "Well06"
	add_child(construction)
	cut_items.clear()
	bridges.clear()
	bridge_angles.clear()
	side_guards.clear()
	rotor_shapes.clear()
	concealed = false
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	phase = rng.randf_range(0.0, TAU)
	spin_phase = rng.randf_range(0.0, TAU)
	precess_sign = -1 if rng.randi_range(0, 1) == 0 else 1
	spin_sign = -1 if rng.randi_range(0, 1) == 0 else 1
	hole_count = rng.randi_range(2, 4)
	var high := phase + PI
	overview_angle = high - 0.52
	stair_angle = high + rng.randf_range(1.34, 1.58)
	bridge_angles.assign([high + rng.randf_range(-0.12, 0.12), phase + rng.randf_range(-0.10, 0.10)])
	make_materials()
	make_lighting(phase + rng.randf_range(0.4, 2.1), rng.randf_range(2.0, 5.0))
	make_hall(rng)
	make_bridges()
	make_gyro()
	set_step(0)
	if is_instance_valid(player):
		reset_player()
		if not review_view.is_empty():
			show_view(review_view)

func make_materials() -> void:
	stone = stock(Color("474f57"), Color("5c6469"), 0.0, 0.94, 0.0)
	pale = stock(Color("656c71"), Color("77807f"), 0.0, 0.90, 0.0)
	iron = stock(Color("20272d"), Color("41484a"), 0.60, 0.65, 1.0)
	bronze = stock(Color("604126"), Color("8c6743"), 0.75, 0.45, 2.0)
	lip = stock(Color("8c693f"), Color("a98250"), 0.75, 0.45, 2.0)
	mark = stock(Color("643b33"), Color("854b3c"), 0.0, 0.85, 0.0)
	chalk = standard(Color("b8b2a0"))
	var phosphor := standard(Color("ccaf7d"))
	phosphor.emission_enabled = true
	phosphor.emission = Color("e7c087")
	phosphor.emission_energy_multiplier = 1.8
	lamp = phosphor

func standard(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.89
	return m

func stock(base: Color, oxide: Color, metal: float, rough: float, mode: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = STOCK
	for pair in [["base_tone", base], ["oxide_tone", oxide], ["alloy", metal], ["grit", rough], ["mode", mode]]:
		m.set_shader_parameter(pair[0], pair[1])
	return m

func make_lighting(direction: float, tilt_degrees: float) -> void:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("171d24")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("b6cadf")
	e.ambient_light_energy = 0.30
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.tonemap_exposure = 1.05
	e.sdfgi_enabled = true
	e.sdfgi_min_cell_size = 0.30
	e.sdfgi_energy = 0.38
	e.volumetric_fog_enabled = true
	e.volumetric_fog_density = 0.0065
	e.volumetric_fog_albedo = Color("bdc9d6")
	e.volumetric_fog_ambient_inject = 0.045
	e.volumetric_fog_length = 36.0
	var world := WorldEnvironment.new()
	world.environment = e
	construction.add_child(world)
	shaft_light = DirectionalLight3D.new()
	shaft_light.name = "Collimated oculus • hard key"
	shaft_light.light_color = Color("fff1dc")
	shaft_light.light_energy = 1.65
	shaft_light.light_angular_distance = 0.0
	shaft_light.light_volumetric_fog_energy = 0.78
	shaft_light.shadow_enabled = true
	shaft_light.shadow_bias = 0.031
	shaft_light.shadow_normal_bias = 0.22
	shaft_light.directional_shadow_max_distance = 62.0
	shaft_light.directional_shadow_split_1 = 0.24
	shaft_light.directional_shadow_split_2 = 0.48
	shaft_light.directional_shadow_split_3 = 0.76
	construction.add_child(shaft_light)
	shaft_light.look_at(Vector3.DOWN + G.radial(direction) * tan(deg_to_rad(tilt_degrees)))
	for i in 4:
		var a := phase + float(i)*TAU/4.0 + 0.36
		wash(G.radial(a)*9.3 + Vector3.UP*2.35, Color("b6d0ff"), 0.30, 12.0)
		wash(G.radial(a)*11.3 + Vector3.UP*10.0, Color("b6cde6"), 0.39, 15.0)
	wash(Vector3(0.0, 2.1, 0.0), Color("f8c383"), 0.41, 10.0)

func wash(pos: Vector3, color: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = energy
	light.light_volumetric_fog_energy = 0.075
	light.omni_range = reach
	light.omni_attenuation = 1.26
	construction.add_child(light)
	light.position = pos

func solid(parent: Node3D, mesh: Mesh, m: Material, collide := true, cut := false) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = m
	parent.add_child(visual)
	if cut:
		cut_items.append(visual)
	if collide:
		var shape := CollisionShape3D.new()
		shape.shape = mesh.create_trimesh_shape()
		if parent is CollisionObject3D:
			parent.add_child(shape)
		else:
			var body := StaticBody3D.new()
			visual.add_child(body)
			body.add_child(shape)
		if parent == wheel:
			rotor_shapes.append(shape)
	return visual

func arc(parent: Node3D, m: Material, r0: float, r1: float, y0: float, y1: float, a := 0.0, span := TAU, bevel := 0.0, collide := true, cut := false) -> MeshInstance3D:
	return solid(parent, G.band(r0,r1,y0,y1,a,span,bevel),m,collide,cut)

func beam(parent: Node3D, m: Material, a: Vector3, b: Vector3, wide: float, deep: float, collide := true, cut := false) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(wide, deep, a.distance_to(b))
	var center := (a+b)*0.5
	var tangent := (b-a).normalized()
	var basis_ := Basis.looking_at(tangent, Vector3.FORWARD if absf(tangent.y)>0.995 else Vector3.UP)
	var member := solid(parent, mesh, m, collide and not parent is CollisionObject3D, cut)
	member.transform = Transform3D(basis_, center)
	if collide and parent is CollisionObject3D:
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = mesh.size
		shape.shape = box
		parent.add_child(shape)
		shape.transform = member.transform
	return member

func make_hall(rng: RandomNumberGenerator) -> void:
	arc(construction, pale, 0.001, 13.53, -0.57, 0.0, 0.0, TAU, 0.03)
	arc(construction, iron, 13.11, 13.54, -0.81, -0.46, 0.0, TAU, 0.04, false)
	for rad in [1.66, 4.66, 7.35, 10.92]:
		arc(construction, iron, rad, rad+0.019, 0.001, 0.004, 0.0, TAU, 0.0, false)
	for i in 48:
		var a := float(i)*TAU/48.0
		var v := G.radial(a)
		beam(construction, chalk if i%4==0 else iron, v*10.98+Vector3.UP*0.008,
			v*(11.42 if i%4==0 else 11.18)+Vector3.UP*0.008, 0.025, 0.009, false)
		if i%4==0:
			beam(construction, iron, v*1.86+Vector3.UP*0.003,v*10.82+Vector3.UP*0.003, 0.014, 0.004, false)
	var bays := rng.randi_range(11, 14)
	var bay := TAU/bays
	var offset := phase + rng.randf_range(-0.2, 0.2)
	for i in bays:
		var a := offset + i*bay
		var front := angular_distance(a, overview_angle) < 1.19
		arc(construction, stone, 13.22, 13.51, 0.0, CROWN_HEIGHT, a-bay*0.5, bay-0.004, 0.0, true, front)
		arc(construction, pale, 12.07, 13.34, 11.30, 15.99, a-0.07, 0.14, 0.07, true, front)
		arc(construction, stone, 11.96, 13.35, 12.50, 13.06, a-0.105, 0.21, 0.06, false, front)
		arc(construction, pale, 11.88, 13.34, 15.14, 15.99, a-0.10, 0.20, 0.07, false, front)
		# Narrow buttresses leave the full rear recess continuous behind the stair.
		arc(construction, pale, 12.04 if not in_stair(a,0.14) else 13.12, 13.44, 0.0, 11.6,
			a-0.037, 0.074, 0.055, true, front)
		arc(construction, stone, 12.04, 13.22, 13.93, 15.95, a+0.087, bay-0.174, 0.07, true, front)
		arc(construction, iron, 13.178, 13.23, 0.42, 5.86, a+0.095, bay-0.19, 0.0, false, front)
		arc(construction, stone, 13.055, 13.23, 0.0, 0.32, a+0.046, bay-0.094, 0.035, false, front)
		for y in [3.72, 11.43]:
			var v := G.radial(a+bay*0.50)
			var b: Vector3 = v*13.13 + Vector3.UP*y
			beam(construction, iron, b-Vector3.UP*0.63,b+Vector3.UP*0.63,0.21,0.16,false,front)
			beam(construction, lamp, b-v*0.103-Vector3.UP*0.52,b-v*0.103+Vector3.UP*0.52,0.035,0.023,false,front)
			wash(b-v*0.57, Color("ded3ac"), 0.16, 3.4)
	# Sectorized oculus and outer decks retain their real silhouette in cutaway.
	var section := TAU/96.0
	for i in 96:
		var a := section*i
		var middle := a+section/2.0
		var front := angular_distance(middle,overview_angle) < 1.22
		var slice := angular_distance(middle,overview_angle) < 0.83 and not is_bridge(middle,0.14)
		arc(construction, iron, 10.56, 13.49, 15.64, 16.0, a, section, 0.0, true, front)
		arc(construction, pale, 10.31, 10.65, 15.08, 15.98, a, section, 0.0, true, front)
		arc(construction, pale, 10.33, 11.72, DECK-0.30, DECK, a, section, 0.0, true, slice)
		arc(construction, iron, 10.29, 10.47, DECK-0.55, DECK-0.17, a, section, 0.0, true, slice)
		if not in_stair(middle, section*0.48):
			arc(construction, stone, 11.72, 13.21, DECK-0.32, DECK, a, section, 0.0, true, slice)
		if not is_bridge(middle, 0.11):
			for y in [DECK+0.11, DECK+0.56, DECK+1.11]:
				arc(construction, iron, 10.34, 10.40, y-0.043, y+0.043, a, section, 0.0, true, slice)
			if i%2==0:
				var p := G.radial(a)*10.38 + Vector3.UP*DECK
				beam(construction, iron, p, p+Vector3.UP*1.15,0.072,0.082,true,slice)
		# Guard the side bordering the stair void; leave the upper landing open.
		if in_stair(middle, -0.02) and fposmod(middle-stair_angle,TAU) < stair_span-0.22:
			arc(construction, iron, 11.64, 11.71, DECK+1.04, DECK+1.12, a, section)
			if i%2==0:
				var p := G.radial(a)*11.675 + Vector3.UP*DECK
				beam(construction, iron, p,p+Vector3.UP*1.11,0.07,0.07)
	for i in bays:
		var a := offset + (i+0.21)*bay
		if in_stair(a,0.14) or is_bridge(a,0.19):
			continue
		var p := G.radial(a)
		var slice := angular_distance(a,overview_angle) < 0.83
		beam(construction, iron, p*10.36+Vector3.UP*(DECK-0.36),p*13.31+Vector3.UP*(DECK-0.36),0.36,0.44,true,slice)
		beam(construction, iron, p*10.53+Vector3.UP*(DECK-0.54),p*13.26+Vector3.UP*(DECK-1.46),0.31,0.26,true,slice)
		beam(construction, pale, p*13.15+Vector3.UP*0.18,p*13.15+Vector3.UP*(DECK-0.55),0.41,0.48,true,slice)
	make_stair()
	for i in 3:
		var a := stair_angle + stair_span * (i+0.5)/3.0
		var h := DECK * (i+0.5)/3.0
		wash(G.radial(a)*11.7+Vector3.UP*(h+2.25), Color("d9bd93"), 0.55, 5.2)
	for a in bridge_angles:
		var p := G.radial(a+0.22)*13.119 + Vector3.UP*8.98
		lettering("06  /  GYROSCOPE WELL", p, Vector3(0.0,p.y,0.0),0.006, angular_distance(a+0.22,overview_angle)<1.19)

func in_stair(a: float, margin: float) -> bool:
	return absf(wrapf(a-stair_angle-stair_span/2.0,-PI,PI)) < stair_span/2.0+margin

func is_bridge(a: float, margin: float) -> bool:
	for b in bridge_angles:
		if angular_distance(a,b) < margin:
			return true
	return false

func angular_distance(a: float, b: float) -> float:
	return absf(wrapf(a-b,-PI,PI))

func lettering(text: String, pos: Vector3, aim: Vector3, scale_: float, cut: bool) -> void:
	var sign_ := Label3D.new()
	sign_.text = text
	sign_.pixel_size = scale_
	sign_.font_size = 46
	sign_.outline_size = 0
	sign_.modulate = Color("d2c7ac")
	sign_.double_sided = false
	sign_.shaded = true
	construction.add_child(sign_)
	sign_.position = pos
	sign_.look_at(aim,Vector3.UP,true)
	if cut:
		cut_items.append(sign_)

func make_stair() -> void:
	const N := 40
	const INNER := 11.74
	const OUTER := 13.095
	var run := stair_span/N
	var riser := DECK/N
	solid(construction, G.ramp(INNER,OUTER,stair_angle,stair_span,DECK,N),null).hide()
	for i in N:
		var a := stair_angle + i*run
		var h := (i+1)*riser
		arc(construction,pale,INNER,OUTER,h-0.29,h,a,run+0.0003,0.016,false)
		arc(construction,iron,INNER+0.035,OUTER-0.031,h+0.002,h+0.009,a+0.001,0.003,0.0,false)
		for r in [INNER,OUTER]:
			var u: Vector3 = G.radial(a)*r + Vector3.UP*h
			var v: Vector3 = G.radial(a+run)*r + Vector3.UP*(h+riser)
			beam(construction, iron, u-Vector3.UP*0.27,v-Vector3.UP*0.27,0.09,0.28)
			if i<36 or r==OUTER:
				beam(construction, iron, u+Vector3.UP*1.0,v+Vector3.UP*1.0,0.064,0.064)
				beam(construction, iron, u+Vector3.UP*0.52,v+Vector3.UP*0.52,0.045,0.048)
				if i%3==0:
					beam(construction, iron, u,u+Vector3.UP*1.0,0.066,0.06)
		if i%8==7:
			var p := G.radial(a+run/2.0)*12.91
			beam(construction,stone,p,p+Vector3.UP*(h-0.26),0.38,0.40)
	var last := stair_angle+stair_span
	arc(construction,pale,INNER,OUTER,DECK-0.35,DECK,last,0.24)

func make_bridges() -> void:
	for index in bridge_angles.size():
		var a := bridge_angles[index]
		var v := G.radial(a)
		var t := G.radial(a+PI/2.0)
		for side in [-1.0,1.0]:
			var s: Vector3 = t*side*0.93
			var pier := v*12.91+s
			beam(construction,pale,pier,pier+Vector3.UP*6.49,0.42,0.48)
			beam(construction,iron,pier+Vector3.UP*6.10,pier+Vector3.UP*6.64,0.59,0.56)
			for height in [6.66,6.35]:
				beam(construction,iron,v*10.36+s+Vector3.UP*height,v*13.19+s+Vector3.UP*height,0.14,0.15)
			for i in 4:
				var start := 10.37+i*0.69
				beam(construction,iron,v*start+s+Vector3.UP*6.37,v*(start+0.69)+s+Vector3.UP*6.68,0.13,0.095)
			beam(construction,iron,v*13.09+s+Vector3.UP*5.42,v*10.38+s+Vector3.UP*6.33,0.24,0.23)
		var tongue := AnimatableBody3D.new()
		tongue.name = "Phase bridge %s" % ["I", "II"][index]
		tongue.sync_to_physics = false
		construction.add_child(tongue)
		tongue.basis = Basis(Vector3.UP,-a)
		bridges.append(tongue)
		var guard: Array[MeshInstance3D] = []
		side_guards.append(guard)
		# Local +X points out of the well. The tongue nests over the fixed landing.
		beam(tongue,iron,Vector3(0,0,0),Vector3(3.36,0,0),1.77,0.23)
		beam(tongue,pale,Vector3(0.015,0.122,0),Vector3(3.36,0.122,0),1.69,0.027)
		for side in [-1.0,1.0]:
			var z: float = side*0.885
			beam(tongue,mark,Vector3(0.01,0.15,z*0.90),Vector3(1.28,0.15,z*0.90),0.038,0.014,false)
			for y in [0.64,1.15]:
				guard.append(guard_box(tongue,Vector3(0.21,y,z),Vector3(0.36,0.063,0.067)))
			for x in [0.055,0.16,0.37]:
				guard.append(guard_box(tongue,Vector3(x,0.64,z),Vector3(0.063,1.05,0.065)))
		beam(tongue,iron,Vector3(0.055,1.15,-0.89),Vector3(0.055,1.15,0.89),0.063,0.066)
		beam(tongue,iron,Vector3(0.055,0.63,-0.89),Vector3(0.055,0.63,0.89),0.052,0.055)
		for i in 8:
			var z := -0.75+i*0.21
			beam(tongue,mark,Vector3(0.10,0.144,z),Vector3(0.27,0.144,z+0.09),0.034,0.009,false)

func guard_box(tongue: AnimatableBody3D, point: Vector3, size: Vector3) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var visual := solid(tongue,mesh,iron,false)
	visual.position = point
	var node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	node.shape = box
	tongue.add_child(node)
	node.position = point
	visual.set_meta("collider",node)
	return visual

func make_gyro() -> void:
	# Fixed, stepped hardened seat: the spindle's apex stays at its cup center.
	arc(construction, iron,0.08,1.38,0.0,0.086,0.0,TAU,0.03)
	arc(construction, iron,0.025,1.09,0.085,0.205,0.0,TAU,0.046)
	arc(construction, lip,0.075,0.53,0.166,0.242,0.0,TAU,0.024)
	arc(construction, iron,0.001,0.127,0.17,PIVOT_Y,0.0,TAU,0.015)
	for i in 12:
		var p := G.radial(i*TAU/12.0)*1.21+Vector3.UP*0.099
		beam(construction,lip,p-Vector3.UP*0.017,p+Vector3.UP*0.017,0.071,0.071,false)
	wheel = AnimatableBody3D.new()
	wheel.name = "Gyroscope • point, spindle and pierced crown"
	wheel.sync_to_physics = false
	wheel.collision_layer = 2
	construction.add_child(wheel)
	external_active = load_external_model()
	if external_active:
		return
	var spindle := CylinderMesh.new()
	spindle.radial_segments = 64
	spindle.rings = 0
	spindle.height = 1.66
	spindle.top_radius = 0.47
	spindle.bottom_radius = 0.0
	var point_mesh := spindle.get_faces()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(0,point_mesh.size(),3):
		G.tri(st,point_mesh[i]+Vector3.UP*0.83,point_mesh[i+1]+Vector3.UP*0.83,point_mesh[i+2]+Vector3.UP*0.83)
	solid(wheel,st.commit(),lip)
	for dims in [[0.49,1.53,2.62],[0.62,2.55,4.39],[0.82,4.30,5.91],[0.54,5.86,7.53],[0.31,7.51,8.43]]:
		arc(wheel,bronze,0.001,dims[0],dims[1],dims[2],0.0,TAU,0.11)
	for dims in [[0.59,1.51,1.73],[0.67,2.38,2.64],[0.73,3.06,3.26],[0.90,4.28,4.52],[0.91,5.84,6.10],[0.66,6.37,6.54],[0.61,7.28,7.58],[0.40,8.28,8.51]]:
		arc(wheel,lip,0.001,dims[0],dims[1],dims[2],0.0,TAU,0.07)
	arc(wheel, bronze,0.55,2.72,4.70,5.65,0.0,TAU,0.15)
	arc(wheel, iron,1.82,2.40,4.57,4.87,0.0,TAU,0.09)
	arc(wheel, lip,2.35,2.79,5.58,5.80,0.0,TAU,0.065)
	arc(wheel, bronze,7.96,RADIUS,4.99,5.54,0.0,TAU,0.13)
	arc(wheel, iron,8.37,9.87,4.88,5.60,0.0,TAU,0.096)
	arc(wheel, bronze,8.85,RADIUS,4.922,5.641,0.0,TAU,0.12)
	arc(wheel, lip,9.14,9.83,5.58,5.735,0.0,TAU,0.053)
	arc(wheel, lip,8.51,9.64,4.834,4.98,0.0,TAU,0.051)
	arc(wheel, iron,7.91,8.13,5.48,5.63,0.0,TAU,0.056)
	arc(wheel, lip,7.97,8.22,4.88,5.01,0.0,TAU,0.041)
	var pitch := TAU/hole_count
	var arm := minf(0.69,pitch*0.285)
	for i in hole_count:
		var a := float(i)*pitch-arm/2.0
		arc(wheel,bronze,2.54,8.43,4.98,5.49,a,arm,0.10)
		arc(wheel,bronze,2.34,4.1,4.91,5.54,a-0.12,arm+0.24,0.08)
		arc(wheel,bronze,7.15,8.43,4.94,5.55,a-0.12,arm+0.24,0.08)
		for offset in [0.043,arm-0.10]:
			arc(wheel,lip,2.66,8.34,4.877,5.01,a+offset,0.058,0.039)
			arc(wheel,lip,2.66,8.32,5.46,5.66,a+offset,0.058,0.038)
		for j in 3:
			var r := 3.60+j*1.20
			arc(wheel,iron,r,r+0.22,4.90,5.00,a+0.093,arm-0.192,0.033)
			arc(wheel,iron,r,r+0.22,5.47,5.56,a+0.093,arm-0.192,0.031)
	for i in 48:
		var a := i*TAU/48.0
		arc(wheel,bronze,9.72,RADIUS,5.08,5.40,a,0.034,0.048)
		arc(wheel,iron,8.76,8.93,5.53,5.61,a,0.019,0.027)

func load_external_model() -> bool:
	if gyro_model_path.is_empty():
		return false
	if gyro_model_source.strip_edges().is_empty() or gyro_model_license.strip_edges().is_empty():
		push_warning("External gyroscope requires both source and license; using procedural stock.")
		return false
	if gyro_model_path.get_extension().to_lower() not in ["glb", "gltf"]:
		push_warning("External gyroscope must be a .glb or .gltf; using procedural stock.")
		return false
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path(gyro_model_path),state) != OK:
		push_warning("Could not read external glTF; using procedural stock.")
		return false
	var model := doc.generate_scene(state) as Node3D
	if not model:
		return false
	var mesh_nodes := model.find_children("*","MeshInstance3D",true,false)
	if model is MeshInstance3D:
		mesh_nodes.push_front(model)
	var parts: Array[Dictionary] = []
	var radius := 0.0
	var has_point := false
	var valid := true
	for node in mesh_nodes:
		var mesh_node := node as MeshInstance3D
		if not mesh_node.mesh or mesh_node.mesh.get_faces().is_empty():
			continue
		var pose := mesh_node.transform
		var ancestor := mesh_node.get_parent() as Node3D
		while ancestor:
			pose = ancestor.transform*pose
			ancestor = ancestor.get_parent() as Node3D
		if pose.basis.determinant() <= 0.0 or mesh_node.skin != null or mesh_node.mesh.get_blend_shape_count() > 0:
			valid = false
			break
		var faces := mesh_node.mesh.get_faces()
		for i in faces.size():
			var p := pose*faces[i]
			faces[i] = p
			var r := Vector2(p.x,p.z).length()
			radius = maxf(radius,r)
			has_point = has_point or p.length() < 0.015
			if not p.is_finite() or p.y < -0.001 or p.y > 8.55 or (r > 3.0 and (p.y < 4.83 or p.y > 5.735)):
				valid = false
				break
		if not valid:
			break
		parts.append({"mesh":mesh_node.mesh,"pose":pose,"faces":faces})
	model.free()
	if not valid or not has_point or radius < 9.0 or radius > RADIUS+0.001:
		push_warning("External glTF is outside the tip/rotor envelope documented for this well; using procedural stock.")
		return false
	for part in parts:
		# Use an opaque stock material and the same triangle positions for shadow and contact.
		var visual := solid(wheel,part.mesh,bronze,false)
		visual.transform = part.pose
		var shape := CollisionShape3D.new()
		var baked := ConcavePolygonShape3D.new()
		baked.set_faces(part.faces)
		shape.shape = baked
		wheel.add_child(shape)
		rotor_shapes.append(shape)
	wheel.set_meta("model_source", gyro_model_source)
	wheel.set_meta("model_license", gyro_model_license)
	return true

func rotor_basis(tick: int) -> Basis:
	return Basis(Vector3.UP,-low_azimuth(tick))*Basis(Vector3.BACK,-TILT)*Basis(Vector3.UP,
		spin_phase+spin_sign*TAU*float(posmod(tick,SPIN_STEPS))/SPIN_STEPS)

func low_azimuth(tick: int) -> float:
	return phase+precess_sign*TAU*float(posmod(tick,PRECESS_STEPS))/PRECESS_STEPS

func set_step(tick: int) -> void:
	step = maxi(0,tick)
	wheel.transform = Transform3D(rotor_basis(step),PIVOT)
	update_bridges()

func update_bridges() -> void:
	for i in bridges.size():
		var open := 1.0 if concealed else smoothstep(0.17,0.53,cos(bridge_angles[i]-low_azimuth(step)))
		var nose := lerpf(9.82,7.08,open)
		if bridges[i].position.y > 0.0 and absf(bridges[i].position.dot(G.radial(bridge_angles[i]))-nose) < 0.00001:
			continue
		bridges[i].position = G.radial(bridge_angles[i])*nose+Vector3.UP*(DECK-0.1245)
		# Only the exposed section is guarded; stowed rails leave the circular aisle clear.
		var reach := 10.30-nose
		for j in side_guards[i].size():
			var visual := side_guards[i][j] as MeshInstance3D
			var collider := visual.get_meta("collider") as CollisionShape3D
			match j%5:
				0,1:
					var dimensions := Vector3(reach-0.035,0.063,0.067)
					(visual.mesh as BoxMesh).size = dimensions
					(collider.shape as BoxShape3D).size = dimensions
					visual.position.x = reach*0.5+0.028
				3:
					visual.position.x = reach*0.50
				4:
					visual.position.x = reach-0.040
			collider.position = visual.position

func hide_gyro(on: bool) -> void:
	concealed = on
	wheel.visible = not on
	for shape in rotor_shapes:
		shape.disabled = on
	update_bridges()
	update_card()

func make_controls() -> void:
	camera = Camera3D.new()
	camera.near = 0.07
	add_child(camera)
	player = CharacterBody3D.new()
	player.collision_mask = 1 | 2
	player.floor_snap_length = 0.24
	player.floor_max_angle = deg_to_rad(45.0)
	player.floor_constant_speed = true
	add_child(player)
	var collision := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.75
	capsule.radius = 0.35
	collision.shape = capsule
	player.add_child(collision)
	collision.position.y = 0.875
	eye = Camera3D.new()
	eye.position.y = 1.65
	eye.near = 0.07
	eye.fov = 69.0
	player.add_child(eye)
	reset_player()
	eye.make_current()
	var ui := CanvasLayer.new()
	add_child(ui)
	var panel := VBoxContainer.new()
	panel.position = Vector2(33.0,25.0)
	ui.add_child(panel)
	var index := Label.new()
	index.text = "K I N E T I C   W O R K S     /     0 6"
	index.add_theme_font_size_override("font_size",16)
	index.modulate = Color("dbc298")
	panel.add_child(index)
	title = Label.new()
	title.add_theme_font_size_override("font_size",31)
	panel.add_child(title)
	detail = Label.new()
	detail.add_theme_font_size_override("font_size",15)
	detail.modulate = Color("c0c9d4")
	panel.add_child(detail)
	for label in [index,title,detail]:
		label.add_theme_color_override("font_shadow_color",Color("141921"))
		label.add_theme_constant_override("shadow_offset_y",2)
	update_card()

func reset_player() -> void:
	var high := G.radial(phase+PI)
	player.position = high*APPROACH + Vector3.UP*0.015
	player.rotation.y = atan2(high.x,high.z)
	player.velocity = Vector3.ZERO
	eye.rotation.x = deg_to_rad(7.0)

func show_view(view: String) -> void:
	review_view = view
	var cut := view in ["A","D"]
	for item in cut_items:
		item.visible = not cut
	running = view.is_empty()
	if view.is_empty():
		eye.make_current()
		update_card()
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	set_step(PRECESS_STEPS/2 if view=="D" else 0)
	camera.make_current()
	camera.fov = 54.0
	if cut:
		camera.position = G.radial(overview_angle)*28.6+Vector3.UP*35.4
		camera.look_at(Vector3(0,6.8,0))
		camera.fov = 47.0
	elif view=="B":
		var high := G.radial(phase+PI)
		camera.position = high*APPROACH+Vector3.UP*1.65
		camera.look_at(high*3.25+Vector3.UP*2.30+G.radial(phase+PI/2.0)*0.23)
		camera.fov = 63.0
	else:
		var a := bridge_angles[1]+0.36
		camera.position = G.radial(a)*10.78+Vector3.UP*(DECK+1.65)
		camera.look_at(-G.radial(a)*0.85+Vector3.UP*5.08)
		camera.fov = 62.0
	update_card()

func update_card() -> void:
	if not is_instance_valid(title):
		return
	match review_view:
		"A": title.text = "Gyroscope Well   /   Section"
		"B": title.text = "Ground level   /   Beneath the crown"
		"C": title.text = "Upper level   /   Ring gallery"
		"D": title.text = "Gyroscope Well   /   Half-cycle"
		_: title.text = "Gyroscope Well"
	if review_view.is_empty():
		detail.text = "WASD  Walk    ·    Click  Look    ·    1–4  Plates    ·    H  Gyroscope    ·    Space  Pause"
	else:
		detail.text = "PLATE %s    /    SEED %d    /    STEP %03d    /    %s" % [review_view,seed_value,step,
			"ROTOR REMOVED" if concealed else ("LOW / HIGH SIDES REVERSED" if review_view=="D" else "24° AXIAL LEAN")]

func _input(event: InputEvent) -> void:
	if event.is_echo():
		return
	for view in ["A","B","C","D"]:
		if event.is_action_pressed("gyro_"+view.to_lower()):
			show_view(view)
			return
	if event.is_action_pressed("gyro_hide"):
		hide_gyro(not concealed)
	elif event.is_action_pressed("gyro_pause"):
		running = not running
	elif event.is_action_pressed("gyro_walk"):
		set_step(0)
		reset_player()
		show_view("")
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif review_view.is_empty():
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			player.rotate_y(-event.screen_relative.x*0.0026)
			eye.rotation.x = clampf(eye.rotation.x-event.screen_relative.y*0.0026,-1.45,1.45)

func _physics_process(delta: float) -> void:
	if running:
		set_step(step+1)
	if not review_view.is_empty():
		return
	var input := Input.get_vector("gyro_left","gyro_right","gyro_forward","gyro_back")
	var walk := player.basis*Vector3(input.x,0.0,input.y)*3.6
	player.velocity.x = walk.x
	player.velocity.z = walk.z
	player.velocity.y -= 9.81*delta
	player.move_and_slide()

## Direct oculus visibility for non-render callers. The direction matches the hard key;
## collision-mask 3 includes architectural baffles and the same triangles as the bronze rotor.
## Call during a physics frame; ambient/decorative fill does not enter this result.
func top_light_reaches(surface_point: Vector3, surface_normal: Vector3 = Vector3.UP) -> bool:
	var toward_key := shaft_light.global_basis.z
	var start := surface_point + surface_normal * 0.012
	var query := PhysicsRayQueryParameters3D.create(start, start+toward_key*48.0, 3, [player.get_rid()])
	return surface_normal.dot(toward_key) > 0.0 and get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func mcp_observe() -> Dictionary:
	var local_up := rotor_basis(step).y
	return {"seed":seed_value,"view":review_view,"step":step,"visible":not concealed,"cutaway":review_view in ["A","D"],
		"fixed_hz":HZ,"spin_period_steps":SPIN_STEPS,"precess_period_steps":PRECESS_STEPS,"hole_count":null if external_active else hole_count,
		"axis":[local_up.x,local_up.y,local_up.z],"pivot":[0,PIVOT_Y,0],"bridge_nose_m":[Vector2(bridges[0].position.x,bridges[0].position.z).length(),Vector2(bridges[1].position.x,bridges[1].position.z).length()],
		"rotor_collision_meshes":rotor_shapes.size(),"external_model":external_active}

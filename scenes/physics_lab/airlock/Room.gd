extends RefCounted
## Every gameplay-facing surface is built as one mesh + shape pair. Small
## trim, decals and readout markings are decoration and never block a query.
const Kit = preload("res://scenes/physics_lab/Geometry.gd")
const STONE := Color("b6b8b5")
const PALE := Color("d5d5cf")
const WHITE := Color("e7e6df")
const GRAPHITE := Color("424a4a")
const STEEL := Color("697473")
const BRASS := Color("aea092")
const INK := Color("242d2e")
const RECESS := Color("566162")
const ENV := 1
const ACTORS := 2
const GUARD := 4
const SENSORS := 8
const PROBE := 16
const SPAN_SIZE := Vector3(1.64, 0.19, 2.66)
const DECK_LOW := -0.76
const TRACK_X := -2.10
const BENCH := Vector3(TRACK_X, 0, 3.46)
const GAP_EDGE := 1.30
const FAR_DOG := Vector3(1.92, 0, -2.80)
const EXIT_Z := -5.02

var kit := Kit.new()
var root: Node3D
var target: StaticBody3D
var bridge: AnimatableBody3D
var guard: AnimatableBody3D
var exit_leaf: AnimatableBody3D
var ratchet: Node3D
var receiver_lamp: OmniLight3D
var receiver_face: MeshInstance3D
var tile_on: StandardMaterial3D
var warning_near: StaticBody3D
var warning_far: StaticBody3D
var bars: Array[MeshInstance3D] = []
var relay := "HOLD"
var rehearsal_dials: Array[MeshInstance3D] = []


func box(at: Vector3, size: Vector3, color: Color, parent: Node3D = null) -> MeshInstance3D:
	return kit.box(at, size, color, parent)


func shape(at: Vector3, size: Vector3, color: Color, tag: String,
		layer: int = ENV, moving: bool = false) -> PhysicsBody3D:
	var body: PhysicsBody3D = AnimatableBody3D.new() if moving else StaticBody3D.new()
	if moving: (body as AnimatableBody3D).sync_to_physics = false
	root.add_child(body)
	body.position = at
	body.collision_layer = layer
	body.collision_mask = 0
	body.set_meta("surface", tag)
	var physics := CollisionShape3D.new()
	var dims := BoxShape3D.new()
	dims.size = size
	physics.shape = dims
	body.add_child(physics)
	box(Vector3.ZERO, size, color, body)
	return body


func sign_text(text: String, at: Vector3, height: float, parent: Node3D = null) -> Label3D:
	var sign_ := kit.label(text, at, height, parent)
	sign_.modulate = INK
	return sign_


func make(parent: Node3D) -> void:
	root = parent
	kit.root = root
	bank(3.85, 5.10)
	bank(-4.18, 5.76)
	shape(Vector3(0, -1.31, 0), Vector3(7.2, .20, 2.67), RECESS, "catch_pit")
	for edge: float in [-1.0, 1.0]:
		shape(Vector3(0, -.78, edge * 1.37), Vector3(7.2, 1.02, .14), STONE, "pit_sill")
		for side: float in [-1.0, 1.0]:
			shape(Vector3(side * 2.18, .17, edge * 1.40), Vector3(2.76, .34, .17), PALE, "curb")
			for i in range(5):
				box(Vector3(side * (.93 + i * .56), .362, edge * 1.40), Vector3(.29, .032, .15), GRAPHITE)
	for side: float in [-1.0, 1.0]:
		shape(Vector3(side * 3.65, 1.70, -.30), Vector3(.24, 3.45, 13.48), PALE, "side_wall")
		for z: float in [-5.4, -3.15, -.95, 1.25, 3.45, 5.70]:
			box(Vector3(side * 3.515, 1.55, z), Vector3(.03, 2.95, .019), STONE)
			box(Vector3(side * 3.478, .35, z), Vector3(.083, .11, .50), GRAPHITE)
	shape(Vector3(0, 1.70, 6.43), Vector3(7.2, 3.45, .22), PALE, "entry_wall")
	shape(Vector3(0, 1.70, -7.04), Vector3(7.2, 3.45, .22), PALE, "rear_wall")
	shape(Vector3(0, 3.60, -.3), Vector3(7.44, .33, 13.48), STONE, "ceiling")
	# Nested thresholds frame the trench; the left optical hood occludes the witness
	# from the crossing strip. A second side is open for over-the-rail viewing.
	for z: float in [2.17, -.99, -4.89]:
		box(Vector3(0, 3.12, z), Vector3(7.0, .40, .31), WHITE)
		box(Vector3(0, 2.91, z), Vector3(7.0, .045, .34), GRAPHITE)
	for side: float in [-1.0, 1.0]:
		var x := -1.19 if side < 0 else .96
		shape(Vector3(x, 1.20, 1.29), Vector3(.22, 2.40, .30), WHITE, "cross_jamb")
		box(Vector3(x - side * .115, 1.18, 1.455), Vector3(.045, 2.31, .038), GRAPHITE)
	box(Vector3(-.12, 2.40, 1.30), Vector3(2.38, .18, .33), WHITE)
	for x: float in [-2.66, -1.54]:
		shape(Vector3(x, 1.17, -.60), Vector3(.19, 2.34, 2.30), PALE, "optical_hood")
		box(Vector3(x, 2.37, -.60), Vector3(.23, .05, 2.36), GRAPHITE)
	shape(Vector3(TRACK_X, 2.29, -.62), Vector3(1.28, .17, 2.31), STONE, "hood_roof")
	shape(Vector3(TRACK_X, .72, -1.80), Vector3(1.04, 1.44, .23), RECESS, "receiver_plinth")
	target = shape(Vector3(TRACK_X, 1.51, -1.71), Vector3(.54, .64, .19), GRAPHITE, "witness") as StaticBody3D
	receiver_face = box(Vector3(0, 0, .101), Vector3(.405, .505, .018), PALE, target)
	tile_on = emission(WHITE, .92)
	for i in range(5):
		box(Vector3(.148 - i * .073, 0, .113), Vector3(.018, .39, .012), GRAPHITE, target)
	box(Vector3(TRACK_X, 2.075, -.64), Vector3(.31, .083, .40), GRAPHITE)
	receiver_lamp = light(Vector3(TRACK_X, 1.98, -.70), 2.60, 2.8)
	receiver_lamp.light_bake_mode = Light3D.BAKE_DISABLED
	# Gate does not affect the test carriage: the loading rail is under the actor guard.
	bridge = shape(Vector3(0, DECK_LOW - SPAN_SIZE.y * .5, 0), SPAN_SIZE, GRAPHITE, "span", ENV, true) as AnimatableBody3D
	for i in range(13):
		box(Vector3(0, SPAN_SIZE.y * .5 - .007, -1.224 + i * .204), Vector3(1.53, .014, .164), STONE, bridge)
	guard = shape(Vector3(0, .88, 1.423), Vector3(1.68, .16, .13), GRAPHITE, "stop_bar", GUARD, true) as AnimatableBody3D
	for x: float in [-.66, -.34, 0.0, .34, .66]:
		box(Vector3(x, 0.0, .071), Vector3(.11, .074, .018), WHITE, guard)
	for sx: float in [-1.0, 1.0]:
		shape(Vector3(sx * 2.27, 1.40, EXIT_Z), Vector3(2.64, 2.80, .27), PALE, "exit_jamb")
	shape(Vector3(0, 2.81, EXIT_Z), Vector3(2.15, .40, .30), WHITE, "exit_lintel")
	exit_leaf = shape(Vector3(0, 1.30, EXIT_Z), Vector3(1.90, 2.60, .22), STEEL, "exit_leaf", ENV, true) as AnimatableBody3D
	for x: float in [-.66, -.33, .0, .33, .66]:
		box(Vector3(x, 0.0, .114), Vector3(.014, 2.58, .014), GRAPHITE, exit_leaf)
	sign_text("SERVICE LOCK", Vector3(0, 2.78, EXIT_Z + .18), .178)
	var dog := shape(FAR_DOG + Vector3(0, .48, 0), Vector3(.56, .96, .51), STONE, "dock_plinth")
	ratchet = kit.node(Vector3(0, .53, .10), dog)
	box(Vector3(0, .06, 0), Vector3(.08, .44, .083), GRAPHITE, ratchet)
	kit.cylinder(Vector3(0, .30, 0), .069, .24, BRASS, ratchet).rotation.z = PI * .50
	sign_text("DOG", Vector3(0, .23, .266), .115, dog)
	# The inlet plate is mounted clear of the required body position.
	var bench := shape(BENCH + Vector3(-.81, .56, .08), Vector3(.88, 1.12, .89), STONE, "test_bench")
	box(Vector3(0, .574, 0), Vector3(.86, .037, .89), GRAPHITE, bench)
	for i in range(2):
		var p := box(Vector3(.21 - i * .40, .605, .12), Vector3(.25, .045, .38), WHITE, bench)
		rehearsal_dials.append(p)
	sign_text("CATCH", Vector3(-.22, .30, .452), .132, bench)
	sign_text("TRAY", Vector3(.21, .30, .452), .132, bench)
	sign_text("PROOF LOAD   /   01", Vector3(0, .02, .454), .103, bench)
	var floor_stencil := sign_text("WITNESS", BENCH + Vector3(.0, .009, .32), .145)
	floor_stencil.rotation.x = -PI / 2.0
	box(BENCH + Vector3(0, .006, 0), Vector3(.69, .01, .68), STONE)
	for x: float in [-.32, .32]:
		box(BENCH + Vector3(x, .019, 0), Vector3(.06, .012, .63), GRAPHITE)
	var plate := kit.node(Vector3(TRACK_X, 2.62, .68))
	box(Vector3.ZERO, Vector3(1.19, .235, .07), PALE, plate)
	sign_text("WITNESS BAY", Vector3(0, 0, .042), .133, plate)
	box(Vector3(TRACK_X, 2.475, .69), Vector3(1.27, .021, .052), GRAPHITE)
	warning_near = signal_panel(Vector3(-.30, 2.04, 1.49), "caution_near")
	warning_far = signal_panel(Vector3(-.30, 1.57, -3.29), "caution_far")
	for z: float in [4.7, 2.8, -.17, -3.48, -5.90]:
		light(Vector3(.25, 3.17, z), 1.08 if z == -.17 else 1.34, 5.20)
		box(Vector3(.22, 3.37, z), Vector3(3.16, .082, .34), GRAPHITE)
		var diffuser := box(Vector3(.22, 3.315, z), Vector3(2.91, .05, .19), WHITE)
		diffuser.material_override = emission(WHITE, .62)


func bank(z: float, depth: float) -> void:
	shape(Vector3(0, -.17, z), Vector3(7.08, .34, depth), PALE, "bank")
	for i in range(-3, 4):
		box(Vector3(i * 1.01, .003, z), Vector3(.013, .005, depth), STONE)
	for i in range(1, floori(depth) + 1):
		box(Vector3(0, .004, z - depth / 2 + i * .93), Vector3(7.08, .005, .013), STONE)
	for x: float in [-.48, .48, TRACK_X]:
		box(Vector3(x, .008, z), Vector3(.025, .008, depth - .05), STEEL)


func signal_panel(at: Vector3, id: String) -> StaticBody3D:
	var panel := shape(at, Vector3(.87, .25, .08), GRAPHITE, id, SENSORS) as StaticBody3D
	for i in range(6):
		bars.append(box(Vector3((i - 2.5) * .123, 0, .045), Vector3(.096,.135,.012), WHITE, panel))
	return panel


func light(at: Vector3, energy: float, reach: float) -> OmniLight3D:
	var lamp := OmniLight3D.new()
	lamp.light_color = Color("faf5e9")
	lamp.light_energy = energy
	lamp.omni_range = reach
	lamp.omni_attenuation = 1.1
	root.add_child(lamp)
	lamp.position = at
	return lamp


func emission(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m


func set_lamp(on: bool) -> void:
	receiver_lamp.visible = on
	receiver_face.material_override = tile_on if on else kit.mat(RECESS)


func set_signal(ready: bool, alarm: int) -> void:
	relay = "PROCEED" if ready and alarm == 0 else "HOLD"
	for i in range(bars.size()):
		var cell := i % 6
		var on := cell < ceili(alarm / 10.0) if alarm > 0 else ready and cell in [0, 5]
		bars[i].material_override = kit.mat(WHITE if on else STEEL)
		bars[i].scale.y = 1.0 if alarm > 0 else .52


func render_state(lift: float, open_guard: bool, dog_turn: float, door_slide: float,
		failed_trial: bool, held_trial: bool) -> void:
	bridge.position.y = lift - SPAN_SIZE.y * .50
	guard.position.y = 2.69 if open_guard else .88
	ratchet.rotation.z = lerpf(.31, -1.12, dog_turn)
	exit_leaf.position.x = door_slide * 2.03
	rehearsal_dials[0].material_override = kit.mat(GRAPHITE if failed_trial else STONE)
	rehearsal_dials[1].material_override = kit.mat(WHITE if held_trial else STONE)

extends Node3D
## Exhibit-scale spherical tourbillon: three concentric cages and orthogonal local axles.
## The speed is staged for observation; this is a kinetic exhibit, not a timekeeping model.
const PERIODS := Vector3(22.0, 13.0, 7.0)
const AXLE_HEIGHT := 1.34
const OUTER := 0.574
const MIDDLE := 0.432
const INNER := 0.303
const PHASE := Vector3(0.26, 0.62, -0.39)
const BALANCE_HZ := 2.5
var angles := PHASE
var running := false
var _elapsed := 0.0
var _outer := Node3D.new()
var _middle := Node3D.new()
var _inner := Node3D.new()
var _balance := Node3D.new()
var _escape := Node3D.new()
var illustrated := false
var _gold: Material
var _light_gold: Material
var _blue: Material
var _steel: Material
var _dark: Material
var _jewel: Material

func _setup_finishes() -> void:
	_gold = _finish(Color("ba9460"), 0.51, 0.36)
	_light_gold = _finish(Color("e1c79a"), 0.50, 0.35)
	_blue = _finish(Color("668294"), 0.62, 0.35)
	_steel = _finish(Color("adb9bc"), 0.54, 0.37)
	_dark = _finish(Color("39444a"), 0.37, 0.65)
	_jewel = _finish(Color("a44750"), 0.18, 0.38)

func _ready() -> void:
	_setup_finishes()
	_outer.name = "OuterCage"
	_middle.name = "MiddleCage"
	_inner.name = "InnerCage"
	_balance.name = "Balance"
	_escape.name = "EscapeWheel"
	_outer.position.y = AXLE_HEIGHT
	add_child(_outer)
	_outer.add_child(_middle)
	_middle.add_child(_inner)
	_inner.add_child(_balance)
	_inner.add_child(_escape)
	_escape.position = Vector3(0.137,-0.116,0.08)
	_build_mount()
	_cage(_outer, OUTER, Vector3.BACK, 0.053, _gold, _light_gold)
	_cage(_middle, MIDDLE, Vector3.RIGHT, 0.045, _blue, _steel)
	_cage(_inner, INNER, Vector3.UP, 0.042, _steel, _light_gold)
	_joint(_outer, _middle, Vector3.UP, OUTER, MIDDLE)
	_joint(_middle, _inner, Vector3.BACK, MIDDLE, INNER)
	_build_regulator()
	_apply_pose()

func interact() -> void:
	running = not running

func _physics_process(delta: float) -> void:
	if not running:
		return
	_elapsed += delta
	angles = PHASE + Vector3(TAU * _elapsed / PERIODS.x,
		TAU * _elapsed / PERIODS.y, -TAU * _elapsed / PERIODS.z)
	_apply_pose()

func _apply_pose() -> void:
	_outer.rotation.x = angles.x
	_middle.rotation.y = angles.y
	_inner.rotation.z = angles.z
	_balance.rotation.y = 0.82 * sin(TAU * BALANCE_HZ * _elapsed)
	_escape.rotation.y = floorf(_elapsed * BALANCE_HZ * 2.0) * TAU / 18.0

func _build_mount() -> void:
	_cylinder(self, Vector3.UP * 0.05, 0.57, 0.60, 0.10, _dark, 12)
	_cylinder(self, Vector3.UP * 0.17, 0.48, 0.53, 0.14, _blue, 12)
	_cylinder(self, Vector3.UP * 0.27, 0.50, 0.50, 0.065, _gold, 12)
	_cylinder(self, Vector3.UP * 0.40, 0.25, 0.42, 0.23, _dark, 12)
	_cylinder(self, Vector3.UP * 0.56, 0.30, 0.23, 0.11, _blue, 12)
	for side: float in [-1.0,1.0]:
		var a := Vector3(side * 0.21, 0.58, 0)
		var b := Vector3(side * 0.64, 0.81, 0)
		var c := Vector3(side * 0.675, AXLE_HEIGHT, 0)
		_rod(self, a, b, 0.072, _gold)
		_rod(self, b, c, 0.051, _gold)
		_rod(self, a + Vector3.FORWARD*0.08, Vector3(side*0.68,1.15,0), 0.024, _dark)
		_axis_cylinder(self, c, Vector3.RIGHT, 0.087, 0.11, _gold)
		_axis_cylinder(self, Vector3(side*0.635,AXLE_HEIGHT,0), Vector3.RIGHT, 0.038, 0.16, _steel)
		_axis_cylinder(self, Vector3(side*0.738,AXLE_HEIGHT,0), Vector3.RIGHT, 0.032, 0.014, _jewel)
	var mounting := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.61
	shape.height = 1.66
	col.position.y = 0.83
	col.shape = shape
	mounting.add_child(col)
	add_child(mounting)

func _cage(parent: Node3D, r: float, normal: Vector3, depth: float, body: Material, rim: Material) -> void:
	# Two riveted hoops leave the inner axes and escapement visible from either side.
	for side: float in [-1.0,1.0]:
		_ring(parent, normal * side * depth * 0.5, normal, r, 0.019, body)
		_ring(parent, normal * side * (depth * 0.5 + 0.010), normal, r + 0.003, 0.007, rim)
	var orient := Quaternion(Vector3.UP, normal)
	for i in range(12):
		var phase := TAU * i / 12.0
		var rad := orient * Vector3(cos(phase),0,sin(phase))
		_axis_cylinder(parent, rad*r, normal, 0.022, depth + 0.025, body)
		_axis_cylinder(parent, rad*r + normal*(depth*0.5 + 0.017), normal, 0.012, 0.012, rim)

func _joint(support: Node3D, passenger: Node3D, axis: Vector3, large: float, small: float) -> void:
	for side: float in [-1.0,1.0]:
		# Close the gap between rings only on the shared axis, where both pivots agree.
		_axis_cylinder(support, axis*side*(large - 0.025), axis, 0.048, 0.078, _dark)
		_axis_cylinder(passenger, axis*side*(large + small)*0.5, axis, 0.021, large-small + 0.038, _light_gold)
		_axis_cylinder(passenger, axis*side*(large-0.076), axis, 0.030, 0.024, _steel)

func _build_regulator() -> void:
	var axis := Vector3.UP
	# Balance, bridge and escapement wheel are intentionally distinct silhouettes.
	_axis_cylinder(_inner, Vector3(0,-0.105,0), axis, 0.045, 0.054, _jewel)
	_axis_cylinder(_balance, Vector3(0,0.03,0), axis, 0.034, 0.21, _gold)
	_ring(_balance, Vector3(0,-0.035,0), axis, 0.193, 0.020, _light_gold)
	for i in range(3):
		var phase := TAU*i/3.0
		var radial := Vector3(cos(phase),0,sin(phase))
		_rod(_balance, Vector3.DOWN*0.035, radial*0.187 + Vector3.DOWN*0.035, 0.013, _gold)
		_axis_cylinder(_balance, radial * 0.185 + Vector3.DOWN*0.035, axis, 0.027, 0.041, _gold)
	var previous := Vector3(0.033,0.053,0)
	for i in range(1,97):
		var t := float(i) / 96.0
		var phase := TAU*t*4.0
		var radius := lerpf(0.033,0.129,t)
		var next := Vector3(cos(phase)*radius,0.053 + 0.051*t,sin(phase)*radius)
		_rod(_balance, previous, next, 0.0052, _blue)
		previous = next
	_rod(_inner, Vector3(-0.236,-0.18,0), Vector3(0.235,-0.18,0), 0.022, _steel)
	_axis_cylinder(_escape, Vector3.ZERO, axis, 0.074, 0.016, _blue, 18)
	for i in range(18):
		var a := TAU * i / 18.0
		_rod(_escape, Vector3(cos(a)*0.061,0,sin(a)*0.061),
			Vector3(cos(a+0.057)*0.088,0,sin(a+0.057)*0.088), 0.007, _steel)

func _finish(tone: Color, metal: float, roughness: float) -> Material:
	if illustrated:
		var painted := ShaderMaterial.new()
		painted.shader = preload("res://scenes/blue_prince_lab/HallFinish.gdshader")
		painted.set_shader_parameter("pigment", tone)
		painted.set_shader_parameter("stone_sheen", metal * 0.21)
		painted.set_shader_parameter("surface_roughness", maxf(roughness, 0.50))
		return painted
	var m := StandardMaterial3D.new()
	m.albedo_color = tone
	m.metallic = metal
	m.roughness = roughness
	return m

func _mesh(parent: Node3D, mesh: Mesh, at: Vector3, axis: Vector3, mat: Material) -> void:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = mat
	piece.position = at
	piece.quaternion = Quaternion(Vector3.UP, axis)
	piece.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC if parent != self else GeometryInstance3D.GI_MODE_STATIC
	parent.add_child(piece)

func _ring(parent: Node3D, at: Vector3, axis: Vector3, radius: float, tube: float, mat: Material) -> void:
	var mesh := TorusMesh.new()
	mesh.inner_radius = radius - tube
	mesh.outer_radius = radius + tube
	mesh.rings = 56
	mesh.ring_segments = 8
	_mesh(parent, mesh, at, axis, mat)

func _axis_cylinder(parent: Node3D, at: Vector3, axis: Vector3, r: float, length: float, mat: Material, n := 12) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r
	mesh.bottom_radius = r
	mesh.height = length
	mesh.radial_segments = n
	_mesh(parent, mesh, at, axis, mat)

func _cylinder(parent: Node3D, at: Vector3, top: float, base: float, length: float, mat: Material, n: int) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = base
	mesh.height = length
	mesh.radial_segments = n
	_mesh(parent, mesh, at, Vector3.UP, mat)

func _rod(parent: Node3D, a: Vector3, b: Vector3, r: float, mat: Material) -> void:
	_axis_cylinder(parent, (a+b)*0.5, a.direction_to(b), r, a.distance_to(b), mat, 6)

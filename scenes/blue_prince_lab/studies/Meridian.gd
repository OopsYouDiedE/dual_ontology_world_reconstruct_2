extends Node3D
## Academy Meridian governor: an open cradle with three nested kinematic axes.
## All visible geometry is generated here; the A26 preview is a separate optional asset.
const Batch := preload("res://scenes/blue_prince_lab/MeshBatches.gd")
const Finish := preload("res://scenes/blue_prince_lab/HallFinish.gdshader")
const TRIANGLE_BUDGET := 3000
const SURFACE_BUDGET := 16
const SPEEDS := Vector3(TAU / 26.0, -TAU / 13.0, TAU / 7.0)

var running := false
var angles := Vector3(-0.20, -0.40, 0.14)
var yaw := Node3D.new()
var pitch := Node3D.new()
var roll := Node3D.new()
var finishes := {}
var _mesh_stats := {"triangles": 0, "surfaces": 0}

func _ready() -> void:
	finishes.blue = _finish("416982", 0.53, 0.10)
	finishes.steel = _finish("b4cad0", 0.50, 0.08)
	finishes.gold = _finish("d5a05b", 0.47, 0.09)
	finishes.iron = _finish("304358", 0.79, 0.09)
	finishes.ruby = _finish("b84f61", 0.40, 0.30)
	var stand := Node3D.new()
	stand.name = "FixedBearing"
	add_child(stand)
	yaw.name = "OuterCradleY"
	pitch.name = "CarrierX"
	roll.name = "BalanceZ"
	add_child(yaw)
	yaw.add_child(pitch)
	pitch.add_child(roll)
	_disc(stand, Vector3(0, -1.25, 0), Vector3.UP, 0.62, 0.14, finishes.iron, 16)
	_disc(stand, Vector3(0, -1.16, 0), Vector3.UP, 0.31, 0.065, finishes.gold, 16)
	_disc(yaw, Vector3(0, -1.10, 0), Vector3.UP, 0.19, 0.14, finishes.steel)
	# Two generously spaced open ribs retain the bowl silhouette in profile.
	for z: float in [-0.22, 0.22]:
		_band(yaw, 1.10, 0.145, 0.085, z, deg_to_rad(163), deg_to_rad(377), 28, finishes.blue)
		_band(yaw, 1.165, 0.027, 0.012, z + 0.045, deg_to_rad(183), deg_to_rad(357), 20, finishes.gold)
	for side: float in [-1, 1]:
		_box(yaw, Vector3(side * 1.035, 0, 0), Vector3(0.21, 0.26, 0.59), finishes.blue)
		_disc(yaw, Vector3(side * 1.153, 0, 0), Vector3.RIGHT, 0.141, 0.071, finishes.gold)
		_disc(yaw, Vector3(side * 1.194, 0, 0), Vector3.RIGHT, 0.082, 0.034, finishes.ruby)
		_disc(pitch, Vector3(side * 0.862, 0, 0), Vector3.RIGHT, 0.095, 0.29, finishes.steel)
	for z: float in [-0.22, 0.22]:
		_band(pitch, 0.748, 0.080, 0.066, z, 0.0, TAU, 28, finishes.steel)
	for i in range(4):
		var a := PI * 0.5 * i
		_box(pitch, Vector3(cos(a), sin(a), 0) * 0.737, Vector3(0.10, 0.12, 0.45), finishes.iron, a)
	_disc(pitch, Vector3(0, 0, -0.26), Vector3.BACK, 0.11, 0.12, finishes.iron)
	# Forked silver bearing bridge, legible against the brass balance behind it.
	for side: float in [-1, 1]:
		_box(pitch, Vector3(side * 0.39, 0.083, 0.30), Vector3(0.59, 0.069, 0.048), finishes.steel, side * 0.17)
		_box(pitch, Vector3(side * 0.28, -0.055, 0.30), Vector3(0.34, 0.046, 0.038), finishes.steel, -side * 0.25)
		_box(pitch, Vector3(side * 0.694, 0.122, 0.251), Vector3(0.15, 0.14, 0.14), finishes.steel)
	_disc(pitch, Vector3(0, 0.031, 0.318), Vector3.BACK, 0.128, 0.095, finishes.steel)
	_disc(pitch, Vector3(0, 0.031, 0.371), Vector3.BACK, 0.066, 0.026, finishes.ruby)
	_band(roll, 0.515, 0.089, 0.074, 0.0, 0.0, TAU, 28, finishes.gold)
	for i in range(3):
		var a := TAU * i / 3.0
		_box(roll, Vector3(cos(a), sin(a), 0) * 0.25, Vector3(0.49, 0.064, 0.04), finishes.gold, a)
	for i in range(8):
		var a := TAU * i / 8.0
		_box(roll, Vector3(cos(a), sin(a), 0) * 0.508, Vector3(0.072, 0.036, 0.093), finishes.steel, a)
	_disc(roll, Vector3.ZERO, Vector3.BACK, 0.133, 0.20, finishes.steel)
	_disc(roll, Vector3(0, 0, 0.12), Vector3.BACK, 0.067, 0.06, finishes.ruby)
	# Coarse escape wheel and bridge read in close-up. They travel with the inner carriage.
	var escape := Vector3(0.255, -0.088, -0.125)
	_disc(roll, escape, Vector3.BACK, 0.115, 0.05, finishes.steel, 12)
	for i in range(12):
		var a := TAU * i / 12.0
		_box(roll, escape + Vector3(cos(a), sin(a), 0) * 0.113,
			Vector3(0.055, 0.035, 0.045), finishes.steel, a + 0.29)
	_box(roll, Vector3(0.16, -0.12, -0.169), Vector3(0.29, 0.049, 0.04), finishes.gold, -0.24)
	Batch.collapse(self)
	_count_surfaces(self, _mesh_stats)
	_apply_pose()

func interact() -> void:
	running = not running

func _process(delta: float) -> void:
	if running:
		angles += SPEEDS * delta
		angles = Vector3(fposmod(angles.x, TAU), fposmod(angles.y, TAU), fposmod(angles.z, TAU))
		_apply_pose()

func _apply_pose() -> void:
	yaw.rotation.y = angles.x
	pitch.rotation.x = angles.y
	roll.rotation.z = angles.z

func _finish(pigment: String, roughness: float, fill: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = Finish
	mat.set_shader_parameter("pigment", Color(pigment))
	mat.set_shader_parameter("grain", 0.03)
	mat.set_shader_parameter("surface_roughness", roughness)
	mat.set_shader_parameter("stone_sheen", 0.22)
	mat.set_shader_parameter("emission_gain", fill)
	return mat

func _instance(owner_node: Node3D, mesh: Mesh, p: Vector3, mat: Material) -> MeshInstance3D:
	var piece := MeshInstance3D.new()
	piece.mesh = mesh
	piece.material_override = mat
	piece.position = p
	piece.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	owner_node.add_child(piece)
	return piece

func _disc(parent: Node3D, p: Vector3, axis: Vector3, radius: float, depth: float, mat: Material, sides := 12) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = depth
	mesh.radial_segments = sides
	mesh.rings = 0
	_instance(parent, mesh, p, mat).quaternion = Quaternion(Vector3.UP, axis)

func _box(parent: Node3D, p: Vector3, size: Vector3, mat: Material, a := 0.0) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	_instance(parent, mesh, p, mat).rotation.z = a

func _section(a: float, r: float, w: float, depth: float) -> PackedVector3Array:
	var radial := Vector3(cos(a), sin(a), 0)
	return PackedVector3Array([radial * (r + w / 2.0) + Vector3.BACK * depth / 2.0,
		radial * (r - w / 2.0) + Vector3.BACK * depth / 2.0,
		radial * (r - w / 2.0) - Vector3.BACK * depth / 2.0,
		radial * (r + w / 2.0) - Vector3.BACK * depth / 2.0])

func _quad(s: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, c, b, a, d, c]:
		s.add_vertex(v)

func _band(parent: Node3D, r: float, w: float, depth: float, z: float, start: float, end: float, steps: int, mat: Material) -> void:
	var s := SurfaceTool.new()
	s.begin(Mesh.PRIMITIVE_TRIANGLES)
	s.set_smooth_group(-1)
	var first := _section(start, r, w, depth)
	var section := first
	for i in range(1, steps + 1):
		var next := _section(lerpf(start, end, float(i) / steps), r, w, depth)
		for j in range(4):
			var k := (j + 1) % 4
			_quad(s, section[j], next[j], next[k], section[k])
		section = next
	if end - start < TAU - 0.001:
		_quad(s, first[0], first[1], first[2], first[3])
		_quad(s, section[3], section[2], section[1], section[0])
	s.generate_normals()
	s.index()
	_instance(parent, s.commit(), Vector3(0, 0, z), mat)

func mesh_stats() -> Dictionary:
	return _mesh_stats.duplicate()

func _count_surfaces(node: Node, figures: Dictionary) -> void:
	if node is MeshInstance3D:
		for i in range(node.mesh.get_surface_count()):
			var arrays: Array = node.mesh.surface_get_arrays(i)
			var indices: Variant = arrays[Mesh.ARRAY_INDEX]
			var count: int = arrays[Mesh.ARRAY_VERTEX].size() if indices == null or indices.is_empty() else indices.size()
			figures.triangles += count / 3
			figures.surfaces += 1
	for child in node.get_children():
		_count_surfaces(child, figures)

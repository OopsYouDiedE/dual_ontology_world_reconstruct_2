extends Node3D
## Place with +Z into the room and the origin at the center of the rod.
## Use a unit-scale transform; dimensions and wall setback are in meters.

const COLS := 11
const ROWS := 17
const SUBSTEPS := 2
const ITERATIONS := 7
const FABRIC := preload("res://scenes/blue_prince_lab/banner/banner_fabric.gdshader")

@export_range(0.3, 4.0) var width := 1.35
@export_range(0.3, 5.0) var height := 2.1
## Distance from the rod center to the backing wall. Set to 0 to disable.
@export_range(0.0, 1.0) var wall_setback := 0.13
@export var cloth_color := Color("354a69")
@export var trim_color := Color("c3a16a")

var _wind_world := Vector3.ZERO
var _rest := PackedVector3Array()
var _points := PackedVector3Array()
var _previous := PackedVector3Array()
var _inv_mass := PackedFloat32Array()
var _forces := PackedVector3Array()
var _normals := PackedVector3Array()
var _uv := PackedVector2Array()
var _indices := PackedInt32Array()
var _links := PackedInt32Array()
var _lengths := PackedFloat32Array()
var _cloth_mesh := ArrayMesh.new()


func set_wind(wind: Vector3) -> void:
	if wind.is_finite():
		_wind_world = wind


## Largest displacement normal to the backing wall along the hem, in metres.
func tip_deflection() -> float:
	var amplitude := 0.0
	for i in range(maxi(0, _points.size() - COLS), _points.size()):
		amplitude = maxf(amplitude, absf(_points[i].z - _rest[i].z))
	return amplitude


func _ready() -> void:
	_build_hardware()
	_build_grid()
	var cloth := MeshInstance3D.new()
	cloth.name = "Cloth"
	cloth.mesh = _cloth_mesh
	var material := ShaderMaterial.new()
	material.shader = FABRIC
	material.set_shader_parameter("cloth_color", cloth_color)
	material.set_shader_parameter("trim_color", trim_color)
	cloth.material_override = material
	add_child(cloth)
	_update_mesh()


func _build_hardware() -> void:
	var bronze := StandardMaterial3D.new()
	bronze.albedo_color = Color("766140")
	bronze.metallic = 0.55
	bronze.roughness = 0.6
	var rod := CylinderMesh.new()
	rod.top_radius = 0.024
	rod.bottom_radius = 0.024
	rod.height = width + 0.19
	rod.radial_segments = 10
	rod.rings = 0
	_hardware("Rod", rod, Vector3.ZERO, bronze).rotation.z = PI / 2.0
	for side in [-1, 1]:
		var x: float = side * (width * 0.5 + 0.08)
		var finial := SphereMesh.new()
		finial.radius = 0.045
		finial.height = 0.09
		finial.radial_segments = 8
		finial.rings = 3
		_hardware("Finial", finial, Vector3(x, 0, 0), bronze)
		if wall_setback > 0.0:
			var arm := BoxMesh.new()
			arm.size = Vector3(0.039, 0.042, wall_setback)
			_hardware("Bracket", arm, Vector3(x, 0, -wall_setback * 0.5), bronze)
			var plate := BoxMesh.new()
			plate.size = Vector3(0.075, 0.13, 0.015)
			_hardware("Backplate", plate, Vector3(x, 0, -wall_setback + 0.008), bronze)


func _hardware(label: String, mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label
	part.mesh = mesh
	part.material_override = material
	part.position = at
	add_child(part, true)
	return part


func _build_grid() -> void:
	for y in range(ROWS):
		var v := float(y) / (ROWS - 1)
		for x in range(COLS):
			var u := float(x) / (COLS - 1)
			# Shallow tailoring folds and a five-sided pennant hem.
			var drop := height * (0.90 + 0.10 * (1.0 - absf(2.0 * u - 1.0)))
			var fold := sin(u * TAU * 3.0) * 0.032 * sin(v * PI * 0.82)
			_rest.append(Vector3((u - 0.5) * width, -v * drop, 0.016 + fold))
			_uv.append(Vector2(u, v))
			if x < COLS - 1 and y < ROWS - 1:
				var a := y * COLS + x
				_indices.append_array(PackedInt32Array([a, a + 1, a + COLS, a + 1, a + COLS + 1, a + COLS]))
	_points = _rest.duplicate()
	_previous = _rest.duplicate()
	_inv_mass.resize(_rest.size())
	_forces.resize(_rest.size())
	_normals.resize(_rest.size())
	# Each triangle contributes one third of its fabric mass to each corner.
	for i in range(0, _indices.size(), 3):
		var a := _indices[i]
		var b := _indices[i + 1]
		var c := _indices[i + 2]
		var share := (_rest[b] - _rest[a]).cross(_rest[c] - _rest[a]).length() * 0.5 * 0.48 / 3.0
		_inv_mass[a] += share
		_inv_mass[b] += share
		_inv_mass[c] += share
	for i in range(_rest.size()):
		_inv_mass[i] = 0.0 if i < COLS else 1.0 / _inv_mass[i]
	for y in range(ROWS):
		for x in range(COLS):
			for offset: Vector2i in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(2, 0), Vector2i(0, 2)]:
				var next := Vector2i(x, y) + offset
				if next.x >= 0 and next.x < COLS and next.y < ROWS:
					var a := y * COLS + x
					var b := next.y * COLS + next.x
					if _inv_mass[a] + _inv_mass[b] > 0.0:
						_links.append(a)
						_links.append(b)
						_lengths.append(_rest[a].distance_to(_rest[b]))


func _physics_process(delta: float) -> void:
	if delta <= 0.0:
		return
	var step := delta / SUBSTEPS
	var world_to_local := global_basis.inverse()
	var wind := world_to_local * _wind_world
	var gravity := world_to_local * (Vector3.DOWN * 9.81)
	for substep in range(SUBSTEPS):
		_simulate(step, wind, gravity)
	_update_mesh()


func _simulate(step: float, wind: Vector3, gravity: Vector3) -> void:
	_forces.fill(Vector3.ZERO)
	for i in range(0, _indices.size(), 3):
		var a := _indices[i]
		var b := _indices[i + 1]
		var c := _indices[i + 2]
		var cross := (_points[c] - _points[a]).cross(_points[b] - _points[a])
		var normal := cross.normalized()
		var velocity := (_points[a] - _previous[a] + _points[b] - _previous[b] + _points[c] - _previous[c]) / (step * 3.0)
		var relative := wind - velocity
		var flow := clampf(relative.dot(normal), -22.0, 22.0)
		# Two-sided pressure proportional to dynamic pressure, plus weak skin drag.
		var share := (normal * flow * absf(flow) * 0.66 + (relative - normal * relative.dot(normal)).limit_length(22.0) * 0.18) * (cross.length() / 6.0)
		_forces[a] += share
		_forces[b] += share
		_forces[c] += share
	var retention := exp(-1.8 * step)
	for i in range(COLS, _points.size()):
		var current := _points[i]
		var acceleration := gravity + _forces[i] * _inv_mass[i]
		_points[i] += (current - _previous[i]) * retention + acceleration * step * step
		_previous[i] = current
	for iteration in range(ITERATIONS):
		for j in range(_lengths.size()):
			var a := _links[2 * j]
			var b := _links[2 * j + 1]
			var edge := _points[b] - _points[a]
			var distance := edge.length()
			if distance < 0.00001:
				continue
			var correction := edge * ((distance - _lengths[j]) / (distance * (_inv_mass[a] + _inv_mass[b])))
			_points[a] += correction * _inv_mass[a]
			_points[b] -= correction * _inv_mass[b]
		if wall_setback > 0.0:
			var limit := -wall_setback + 0.008
			for i in range(COLS, _points.size()):
				if _points[i].z < limit:
					_points[i].z = limit
					_previous[i].z = minf(_previous[i].z, limit)


func _update_mesh() -> void:
	_normals.fill(Vector3.ZERO)
	for i in range(0, _indices.size(), 3):
		var a := _indices[i]
		var b := _indices[i + 1]
		var c := _indices[i + 2]
		var n := (_points[c] - _points[a]).cross(_points[b] - _points[a])
		_normals[a] += n
		_normals[b] += n
		_normals[c] += n
	for i in range(_normals.size()):
		_normals[i] = _normals[i].normalized()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _points
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_INDEX] = _indices
	_cloth_mesh.clear_surfaces()
	_cloth_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

@tool
extends Node3D
## Local origin: lower floor at the first riser. Upper exit faces -Z.

const WIDTH := 2.5
const RUN := 3.8
const RISE := 1.65
const LANDING := 1.0
const STEPS := 10
const TREAD := RUN / STEPS
const RISER := RISE / STEPS
const RAIL_X := 1.16
const RAIL_HEIGHT := 0.90

@export_flags_3d_physics var collision_layer: int = 1

var _body: StaticBody3D
var _stone: StandardMaterial3D
var _edge: StandardMaterial3D
var _slate: StandardMaterial3D
var _joint: StandardMaterial3D
var _baluster: ArrayMesh


func _ready() -> void:
	_stone = _material(Color("8b9297"))
	_edge = _material(Color("b6b9b6"))
	_slate = _material(Color("596671"))
	_joint = _material(Color("737d85"))
	_baluster = _make_baluster()
	_body = StaticBody3D.new()
	_body.name = "GeneratedStairGeometry"
	_body.collision_layer = collision_layer
	_body.collision_mask = 0
	add_child(_body)

	for i in range(STEPS):
		var top := (i + 1) * RISER
		var z := -(i + 0.5) * TREAD
		_block(Vector3(WIDTH, top - 0.039, TREAD), Vector3(0, (top - 0.039) / 2, z), _stone)
		_block(Vector3(WIDTH, 0.039, TREAD - 0.002), Vector3(0, top - 0.0195, z), _edge)
		# A shaded band tucked under the ashlar tread edge.
		_block(Vector3(WIDTH, 0.018, 0.006), Vector3(0, top - 0.048, z + TREAD / 2), _joint)

	var deck_z := -RUN - LANDING / 2
	_block(Vector3(WIDTH, RISE - 0.07, LANDING), Vector3(0, (RISE - 0.07) / 2, deck_z), _stone)
	for row in range(2):
		for col in range(4):
			_block(Vector3(WIDTH / 4 - 0.004, 0.066, LANDING / 2 - 0.004),
				Vector3((col - 1.5) * WIDTH / 4, RISE - 0.033, -RUN - (row + 0.5) * LANDING / 2), _edge)
	_block(Vector3(WIDTH, 0.005, LANDING), Vector3(0, RISE - 0.068, deck_z), _joint)
	# Keep the uphill contact surface continuous for CharacterBody3D floor snap.
	var length := Vector2(RUN, RISE).length()
	var pitch := atan2(RISE, RUN)
	var ramp := Basis(Vector3.RIGHT, pitch)
	_collider(Vector3(WIDTH, 0.14, length), Vector3(0, RISE / 2, -RUN / 2) - ramp.y * 0.07, ramp)
	_collider(Vector3(WIDTH, RISE, LANDING), Vector3(0, RISE / 2, deck_z))

	for side in [-1.0, 1.0]:
		_build_railing(RAIL_X * side, pitch, length)


func _build_railing(x: float, pitch: float, length: float) -> void:
	var middle := Vector3(x, RISE / 2 + RAIL_HEIGHT, -RUN / 2)
	_block(Vector3(0.162, 0.065, length), middle, _edge, pitch)
	_block(Vector3(0.12, 0.042, length), middle - Vector3.UP * 0.044, _slate, pitch)
	var deck_rail := Vector3(x, RISE + RAIL_HEIGHT, -RUN - LANDING / 2)
	_block(Vector3(0.162, 0.065, LANDING), deck_rail, _edge)
	_block(Vector3(0.12, 0.042, LANDING), deck_rail - Vector3.UP * 0.044, _slate)

	for i in range(STEPS):
		var top := (i + 1) * RISER
		var z := -(i + 0.50) * TREAD
		_block(Vector3(0.174, 0.062, TREAD - 0.003), Vector3(x, top + 0.031, z), _slate)
		if i > 0:
			_spindle(x, top + 0.062, z, RAIL_HEIGHT - RISER * 0.5 - 0.10)
	_block(Vector3(0.174, 0.062, LANDING), Vector3(x, RISE + 0.031, -RUN - LANDING / 2), _slate)
	for depth in [0.25, 0.50, 0.75]:
		_spindle(x, RISE + 0.062, -RUN - depth, RAIL_HEIGHT - 0.096)
	_newel(x, RISER, -0.115, RAIL_HEIGHT + RISER * (0.115 / TREAD - 1.0))
	_newel(x, RISE, -RUN, RAIL_HEIGHT)
	_newel(x, RISE, -RUN - LANDING + 0.115, RAIL_HEIGHT)

	var tilt := Basis(Vector3.RIGHT, pitch)
	_collider(Vector3(0.18, 0.90 * cos(pitch), length), middle - Vector3.UP * 0.45, tilt)
	_collider(Vector3(0.18, 0.90, LANDING), deck_rail - Vector3.UP * 0.45)


func _newel(x: float, y: float, z: float, h: float) -> void:
	var base := Vector3(x, y, z)
	_block(Vector3(0.230, 0.074, 0.230), base + Vector3.UP * 0.037, _slate)
	_block(Vector3(0.184, h - 0.10, 0.184), base + Vector3.UP * ((h + 0.04) / 2), _stone)
	_block(Vector3(0.222, 0.053, 0.222), base + Vector3.UP * (h - 0.053), _slate)
	_block(Vector3(0.244, 0.067, 0.244), base + Vector3.UP * h, _edge)
	_block(Vector3(0.192, 0.036, 0.192), base + Vector3.UP * (h + 0.047), _stone)


func _spindle(x: float, y: float, z: float, height: float) -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _baluster
	instance.material_override = _stone
	instance.position = Vector3(x, y, z)
	instance.scale.y = height
	_body.add_child(instance)


func _make_baluster() -> ArrayMesh:
	# Eight flat facets, with a molded foot, swelling shaft and neck.
	var profile := [Vector2(0.055, 0), Vector2(0.055, 0.075), Vector2(0.040, 0.11),
		Vector2(0.036, 0.22), Vector2(0.051, 0.34), Vector2(0.053, 0.44),
		Vector2(0.034, 0.63), Vector2(0.026, 0.83), Vector2(0.043, 0.89),
		Vector2(0.049, 0.94), Vector2(0.049, 1.025)]
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for ring in range(profile.size() - 1):
		for facet in range(8):
			var a := _ring_point(profile[ring], facet)
			var b := _ring_point(profile[ring], facet + 1)
			var c := _ring_point(profile[ring + 1], facet + 1)
			var d := _ring_point(profile[ring + 1], facet)
			for vertex in [a, b, d, b, c, d]:
				surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()


func _ring_point(profile: Vector2, facet: int) -> Vector3:
	var angle := TAU * facet / 8.0 + PI / 8.0
	return Vector3(cos(angle) * profile.x, profile.y, sin(angle) * profile.x)


func _block(size: Vector3, center: Vector3, material: Material, pitch := 0.0) -> void:
	var box := BoxMesh.new()
	box.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = box
	instance.material_override = material
	instance.position = center
	instance.rotation.x = pitch
	_body.add_child(instance)


func _collider(size: Vector3, center: Vector3, basis := Basis.IDENTITY) -> void:
	var box := BoxShape3D.new()
	box.size = size
	var shape := CollisionShape3D.new()
	shape.shape = box
	shape.transform = Transform3D(basis, center)
	_body.add_child(shape)


func _material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.89
	return material

@tool
extends Node3D
## Place the root at the ceiling attachment; use a unit-scale transform.
## Feed set_wind() a world-space air velocity in metres per second.

@export_range(0.5, 3.0, 0.01) var hang_length := 1.0
@export var light_energy := 1.1
@export var shadow_enabled := true

const GRAVITY := 9.81
const DRAG_PER_MASS := 0.035 # Effective Cd * air density * frontal area / (2 * mass).
const DAMPING := 1.65 # Angular damping, per second.
const MAX_TILT := 0.52

var _wind := Vector3.ZERO
var _tilt := Vector3.ZERO
var _velocity := Vector3.ZERO
var _swing: Node3D


func set_wind(wind: Vector3) -> void:
	_wind = wind.limit_length(20.0) if wind.is_finite() else Vector3.ZERO


func _ready() -> void:
	var copper := _metal(Color("815039"), 0.45)
	var brass := _metal(Color("bd8e50"), 0.34)
	var iron := _metal(Color("372d29"), 0.61)
	_cylinder(self, "CeilingRose", 0.071, 0.056, 0.026, 0.055, brass)
	_ring(self, "FixedEye", 0.024, 0.006, 0.023, iron)
	_swing = Node3D.new()
	_swing.name = "Pendulum"
	add_child(_swing)
	var y := -hang_length
	_ring(_swing, "HangingEye", 0.025, 0.005, -0.024, brass, true)
	var rod_length := hang_length - 0.216
	_cylinder(_swing, "SuspensionRod", 0.007, 0.007, rod_length, -0.046 - rod_length / 2.0, iron)
	_cylinder(_swing, "Finial", 0.012, 0.031, 0.033, y + 0.155, brass)
	_cylinder(_swing, "VentCap", 0.03, 0.087, 0.053, y + 0.112, copper)
	_cylinder(_swing, "UpperRim", 0.089, 0.089, 0.014, y + 0.08, brass)
	_cylinder(_swing, "OilReservoir", 0.094, 0.064, 0.048, y - 0.097, copper)
	_cylinder(_swing, "LowerRim", 0.096, 0.096, 0.014, y - 0.069, brass)
	_cylinder(_swing, "WickCollar", 0.022, 0.025, 0.023, y - 0.051, iron)
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.97, 0.62, 0.29, 0.20)
	glass.roughness = 0.29
	_cylinder(_swing, "AmberGlobe", 0.078, 0.087, 0.135, y + 0.005, glass, false)
	for i in range(8):
		var angle := TAU * i / 8.0
		var radial := Vector3(cos(angle), 0.0, -sin(angle))
		var bar := BoxMesh.new()
		bar.size = Vector3(0.009, 0.149, 0.008)
		var strut := _mesh(_swing, "CageBar%d" % i, bar, brass)
		strut.position = 0.083 * radial + Vector3.UP * (y + 0.006)
		strut.rotation = Vector3(0.0, angle, 0.06)
	var ember := StandardMaterial3D.new()
	ember.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember.albedo_color = Color(1.0, 0.67, 0.27)
	_cylinder(_swing, "FlameFoot", 0.011, 0.004, 0.019, y - 0.032, ember, false)
	_cylinder(_swing, "FlameTip", 0.001, 0.011, 0.037, y - 0.004, ember, false)
	var light := OmniLight3D.new()
	light.name = "OilLight"
	light.position.y = y + 0.008
	light.light_color = Color("ffbe78")
	light.light_energy = light_energy
	light.omni_range = 3.4
	light.shadow_enabled = shadow_enabled
	light.omni_shadow_mode = OmniLight3D.SHADOW_DUAL_PARABOLOID
	# The thin housing does not occlude its own emitter; room geometry still casts shadows.
	_swing.add_child(light)


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_instance_valid(_swing):
		return
	var local_frame := global_basis.orthonormalized().inverse()
	var bob_velocity := global_basis.orthonormalized() * (_velocity * hang_length)
	var air := local_frame * (_wind - bob_velocity)
	var side := Vector3(air.x, 0.0, air.z)
	var drive := side * air.length() * (DRAG_PER_MASS / hang_length)
	_velocity += (drive - _tilt * (GRAVITY / hang_length) - _velocity * DAMPING) * delta
	_tilt += _velocity * delta
	if _tilt.length_squared() > MAX_TILT * MAX_TILT:
		var outward := _tilt.normalized()
		_tilt = outward * MAX_TILT
		_velocity -= outward * maxf(0.0, _velocity.dot(outward))
	var angle := _tilt.length()
	_swing.basis = Basis(Vector3.DOWN.cross(_tilt / angle), angle) if angle > 0.00001 else Basis.IDENTITY


func _metal(tint: Color, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.metallic = 0.58
	material.roughness = roughness
	return material


func _mesh(parent: Node3D, label: String, shape: Mesh, material: Material) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.name = label
	node.mesh = shape
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node


func _cylinder(parent: Node3D, label: String, top: float, bottom: float,
		height: float, y: float, material: Material, caps := true) -> void:
	var shape := CylinderMesh.new()
	shape.top_radius = top
	shape.bottom_radius = bottom
	shape.height = height
	shape.radial_segments = 8
	shape.rings = 0
	shape.cap_top = caps
	shape.cap_bottom = caps
	_mesh(parent, label, shape, material).position.y = y


func _ring(parent: Node3D, label: String, radius: float, wire: float, y: float,
		material: Material, crosswise := false) -> void:
	var shape := TorusMesh.new()
	shape.inner_radius = radius - wire
	shape.outer_radius = radius + wire
	shape.rings = 12
	shape.ring_segments = 6
	var ring := _mesh(parent, label, shape, material)
	ring.position.y = y
	ring.rotation.x = PI / 2.0
	if crosswise:
		ring.rotation.y = PI / 2.0

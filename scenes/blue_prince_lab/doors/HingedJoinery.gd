extends Node3D
## Shared geometry and physics-clock hinge drive. Dimensions are in metres.

signal open_changed(open: bool)

@export_range(0.05, 3.0) var swing_seconds := 0.62
@export_flags_3d_physics var collision_layer := 1
var is_open := false
var _travel := 0.0
var _leaves: Array[AnimatableBody3D] = []
var _angles: Array[float] = []

static func finish(color: String, metallic := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color.html(color)
	material.metallic = metallic
	material.roughness = 0.39 if metallic > 0.0 else 0.73
	return material

func interact() -> void:
	set_open(not is_open)

func set_open(open: bool, immediate := false) -> void:
	var changed := open != is_open
	is_open = open
	if immediate:
		_travel = float(open)
		_pose()
	if changed:
		open_changed.emit(open)

func _physics_process(delta: float) -> void:
	var next := move_toward(_travel, float(is_open), delta / maxf(swing_seconds, 0.05))
	if next != _travel:
		_travel = next
		_pose()

func _pose() -> void:
	var eased := smoothstep(0.0, 1.0, _travel)
	for i in _leaves.size():
		_leaves[i].rotation.y = _angles[i] * eased

func hinge(label: String, at: Vector3, degrees: float) -> AnimatableBody3D:
	var body := AnimatableBody3D.new()
	body.name = label
	body.position = at
	body.collision_layer = collision_layer
	body.collision_mask = 0
	# Drive the physics body itself; meshes and shape share this exact transform.
	body.sync_to_physics = false
	add_child(body)
	_leaves.append(body)
	_angles.append(deg_to_rad(degrees))
	_pose()
	return body

func fixed_body() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Carcass"
	body.collision_layer = collision_layer
	body.collision_mask = 0
	add_child(body)
	return body

func shape(body: PhysicsBody3D, size: Vector3, at: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	collider.position = at
	body.add_child(collider)

func block(parent: Node3D, size: Vector3, at: Vector3, mat: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	piece(parent, mesh, at, mat)

func piece(parent: Node3D, mesh: Mesh, at: Vector3, mat: Material) -> void:
	var visual := MeshInstance3D.new()
	visual.mesh = mesh
	visual.material_override = mat
	visual.position = at
	parent.add_child(visual)

func pin(parent: Node3D, at: Vector3, radius: float, height: float, mat: Material) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 10
	piece(parent, mesh, at, mat)

## Three stacked courses give a carved profile with crisp, low-poly shading.
func panel(parent: Node3D, center: Vector3, w: float, h: float, face: float, rim: Material, edge: Material, field: Material) -> void:
	block(parent, Vector3(w, h, 0.008), center + Vector3(0, 0, face * 0.004), rim)
	block(parent, Vector3(w - 0.018, h - 0.018, 0.009), center + Vector3(0, 0, face * 0.011), edge)
	block(parent, Vector3(w - 0.046, h - 0.046, 0.009), center + Vector3(0, 0, face * 0.018), field)

func knob(parent: Node3D, at: Vector3, face: float, brass: Material) -> void:
	block(parent, Vector3(0.051, 0.119, 0.008), at, brass)
	var mesh := SphereMesh.new()
	mesh.radius = 0.025
	mesh.height = 0.05
	mesh.radial_segments = 12
	mesh.rings = 6
	piece(parent, mesh, at + Vector3(0, 0.015, face * 0.025), brass)
	var key := finish("302a22")
	block(parent, Vector3(0.009, 0.016, 0.003), at + Vector3(0, -0.031, face * 0.005), key)

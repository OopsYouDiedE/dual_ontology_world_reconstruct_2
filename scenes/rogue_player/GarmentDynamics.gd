extends SkeletonModifier3D
## Two-ring positional cloth. Install after other pose modifiers that drive the body.
## `simulation_paused` freezes the drape relative to Hips; `reset_simulation()`
## discards inertia at the next pose update (call for scripted warps).
## Collision radii are fractions of mean rest leg length; collision_radius_scale
## tunes them for the outfit. Use a positive, uniformly scaled actor transform.
## Missing or mis-parented garment bones leave the animation untouched.

const RING := 8
const COUNT := 16
const STEP := 1.0 / 120.0
const MAX_STEPS := 8
const ITERATIONS := 8
const BODY_NAMES := ["Hips", "Spine", "LeftUpLeg", "LeftLeg", "LeftFoot", "RightUpLeg", "RightLeg", "RightFoot"]
const CAPSULES := [Vector2i(0, 1), Vector2i(2, 3), Vector2i(3, 4), Vector2i(4, 4), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 7)]
const RADIUS_FACTORS := [0.28, 0.16, 0.11, 0.13, 0.16, 0.11, 0.13]

@export var simulation_paused := false
@export_range(0.0, 2.0) var gravity_scale := 1.0
@export_range(0.1, 2.0) var collision_radius_scale := 1.0

var _hem := PackedInt32Array()
var _body := PackedInt32Array()
var _rest := PackedVector3Array()
var _links: Array[Vector2i] = []
var _strength := PackedFloat32Array()
var _leg_length := 0.0
var _points := PackedVector3Array()
var _previous := PackedVector3Array()
var _last_targets := PackedVector3Array()
var _last_body := PackedVector3Array()
var _last_hips := Transform3D.IDENTITY
var _last_skeleton := Transform3D.IDENTITY
var _reset_pending := true
var _previous_h := 0.0

static func install(skeleton: Skeleton3D) -> SkeletonModifier3D:
	if skeleton == null:
		return null
	for child in skeleton.get_children():
		if child.get_script() == load("res://scenes/rogue_player/GarmentDynamics.gd"):
			return child
	var modifier := new()
	modifier.name = "GarmentDynamics"
	skeleton.add_child(modifier)
	return modifier

func reset_simulation() -> void:
	_reset_pending = true

func _skeleton_changed(_old: Skeleton3D, _new: Skeleton3D) -> void:
	_hem.clear()
	reset_simulation()

func _bind(skeleton: Skeleton3D) -> bool:
	_body.clear()
	_hem.clear()
	for label: String in BODY_NAMES:
		var bone := skeleton.find_bone(label)
		if bone < 0:
			return false
		_body.append(bone)
	var indices := PackedInt32Array()
	for prefix: String in ["HemUpper", "HemLower"]:
		for i in RING:
			var bone := skeleton.find_bone(prefix + str(i))
			var parent := _body[0] if prefix == "HemUpper" else indices[i]
			if bone < 0 or skeleton.get_bone_parent(bone) != parent:
				return false
			indices.append(bone)
	var hips_inverse := skeleton.get_bone_global_rest(_body[0]).affine_inverse()
	_leg_length = 0.0
	for i in [2, 5]:
		for j in [i, i + 1]:
			_leg_length += skeleton.get_bone_global_rest(_body[j]).origin.distance_to(skeleton.get_bone_global_rest(_body[j + 1]).origin) * 0.5
	if _leg_length < 0.0001:
		return false
	_hem = indices
	_rest.clear()
	for bone in _hem:
		_rest.append(hips_inverse * skeleton.get_bone_global_rest(bone).origin)
	_links.clear()
	_strength.clear()
	for i in RING:
		var next := (i + 1) % RING
		var skip := (i + 2) % RING
		_add_link(i, next, 0.9) # hoop stretch
		_add_link(i + RING, next + RING, 0.9)
		_add_link(i, i + RING, 0.95) # radial stretch
		_add_link(i, next + RING, 0.55) # shear
		_add_link(next, i + RING, 0.55)
		_add_link(i, skip, 0.18) # longer chords resist sharp folds
		_add_link(i + RING, skip + RING, 0.18)
	return true

func _add_link(a: int, b: int, stiffness: float) -> void:
	_links.append(Vector2i(a, b))
	_strength.append(stiffness)

func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null or (_hem.is_empty() and not _bind(skeleton)):
		return
	var world := skeleton.global_transform
	var hips := world * skeleton.get_bone_global_pose(_body[0])
	var scale := (world.basis.x.length() + world.basis.y.length() + world.basis.z.length()) / 3.0
	if scale < 0.0001 or absf(hips.basis.determinant()) < 1e-12 or absf(world.basis.determinant()) < 1e-12:
		reset_simulation()
		return
	var unit := _leg_length * scale
	var targets := PackedVector3Array()
	var body := PackedVector3Array()
	for bone in _hem:
		targets.append(world * skeleton.get_bone_global_pose(bone).origin)
	for bone in _body:
		body.append(world * skeleton.get_bone_global_pose(bone).origin)
	var jumped := _last_skeleton.origin.distance_to(world.origin) > unit * 1.35 \
		or _last_hips.origin.distance_to(hips.origin) > unit * 1.35 \
		or _last_skeleton.basis.orthonormalized().get_rotation_quaternion().angle_to(world.basis.orthonormalized().get_rotation_quaternion()) > PI * 0.65
	if _reset_pending or jumped or _points.size() != COUNT:
		_points = targets.duplicate()
		_previous = targets.duplicate()
		_previous_h = 0.0
		_reset_pending = false
	elif simulation_paused or not can_process():
		var carry := hips * _last_hips.affine_inverse()
		for i in COUNT:
			_points[i] = carry * _points[i]
		_previous = _points.duplicate()
	elif delta > 0.0:
		var time := minf(delta, STEP * MAX_STEPS)
		var steps := ceili(time / STEP)
		var h := time / steps
		for step in steps:
			var t := float(step + 1) / steps
			_substep(h, t, hips.basis, unit, targets, body)
	_last_hips = hips
	_last_skeleton = world
	_last_targets = targets
	_last_body = body
	var to_skeleton := world.affine_inverse()
	# Parents are written first; the lower ring converts against the already
	# modified upper pose. Rotations, scales and all body bones stay untouched.
	for i in COUNT:
		var bone := _hem[i]
		var parent := skeleton.get_bone_global_pose(skeleton.get_bone_parent(bone))
		skeleton.set_bone_pose_position(bone, parent.affine_inverse() * (to_skeleton * _points[i]))

func _substep(h: float, t: float, basis: Basis, unit: float, targets: PackedVector3Array, body: PackedVector3Array) -> void:
	var soft_targets := PackedVector3Array()
	var colliders := PackedVector3Array()
	for i in _body.size():
		colliders.append(_last_body[i].lerp(body[i], t))
	var down := Vector3.DOWN * 9.81 * gravity_scale
	var damping := exp(-8.0 * h)
	for i in COUNT:
		var target := _last_targets[i].lerp(targets[i], t)
		soft_targets.append(target)
		var point := _points[i]
		# Derive velocity using the previous substep's duration (frame rates vary).
		var velocity := (point - _previous[i]) / _previous_h if _previous_h > 0.0 else Vector3.ZERO
		_previous[i] = point
		var spring := 180.0 if i < RING else 65.0
		_points[i] += velocity.limit_length(unit * 9.0) * (h * damping) + (down + (target - point) * spring) * h * h
	_previous_h = h
	var lengths := PackedFloat32Array()
	for link in _links:
		lengths.append((basis * (_rest[link.y] - _rest[link.x])).length())
	var rays := PackedVector3Array()
	for rest in _rest:
		rays.append(basis * Vector3(rest.x, 0.0, rest.z))
	for iteration in ITERATIONS:
		for j in _links.size():
			var link := _links[j]
			var separation := _points[link.y] - _points[link.x]
			var length := separation.length()
			if length > 0.000001:
				var correction := separation * (0.5 * _strength[j] * (length - lengths[j]) / length)
				_points[link.x] += correction
				_points[link.y] -= correction
		for i in COUNT:
			var reach := unit * (0.24 if i < RING else 0.40)
			var target := soft_targets[i]
			_points[i] = target + (_points[i] - target).limit_length(reach)
			_collide(i, colliders, unit, rays[i])
	# Finish the coupled solve without a length projection reintroducing contact.
	for pass_index in 4:
		for i in COUNT:
			_collide(i, colliders, unit, rays[i])

func _collide(i: int, colliders: PackedVector3Array, unit: float, outward: Vector3) -> void:
	for j in CAPSULES.size():
		var link: Vector2i = CAPSULES[j]
		_project_capsule(i, colliders[link.x], colliders[link.y], unit * RADIUS_FACTORS[j] * collision_radius_scale, outward)

func _project_capsule(i: int, a: Vector3, b: Vector3, radius: float, outward: Vector3) -> void:
	var axis := b - a
	var along := clampf((_points[i] - a).dot(axis) / axis.length_squared(), 0.0, 1.0) if axis.length_squared() > 1e-10 else 0.0
	var center := a + axis * along
	var separation := _points[i] - center
	var distance := separation.length()
	if distance >= radius:
		return
	var normal := separation / distance if distance > 1e-6 else outward.normalized()
	if normal.is_zero_approx():
		normal = Vector3.RIGHT
	var correction := normal * (radius - distance)
	_points[i] += correction
	# Remove penetration velocity without turning positional projection into a kick.
	_previous[i] += correction
	var travel := _points[i] - _previous[i]
	_previous[i] += normal * minf(0.0, travel.dot(normal))

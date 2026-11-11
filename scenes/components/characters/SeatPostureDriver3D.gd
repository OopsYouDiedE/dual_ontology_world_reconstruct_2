extends RefCounted
## Native seat execution; the caller retains the prepared-action identity.
const Modifier = preload("res://scenes/components/characters/SeatPoseModifier3D.gd")
const Layers = preload("res://scenes/components/world/PhysicsLayers.gd")
var body: CharacterBody3D
var modifier
var target: Node3D
var declaration: Dictionary
var active := false
var sitting := false
var animation_finished := false
var last_measurement: Dictionary = {}
var _original_shape: Shape3D
var _original_center := Vector3.ZERO
var _standing_root := Vector3.ZERO
var _feet: Array[CollisionShape3D] = []
var _head_top_offset := 0.0
var _previous_centers: Array[Vector3] = []
var _elapsed := 0.0
var _rollback_reason := ""
var _recovered := false
var _expected_animation := ""
var _was_sitting := false
var _failure_measurement: Dictionary = {}
var _target_exceptions: Array[PhysicsBody3D] = []
var last_start_failure := ""

func begin(owner_body: CharacterBody3D, object: Node3D, spec: Dictionary) -> bool:
	last_start_failure = "seat-driver-or-target-unavailable"
	if active or not is_instance_valid(object) or not object.has_method("resolve_interaction_slot"): return false
	body = owner_body
	target = object
	declaration = spec.duplicate(true)
	var to_pose := str(spec.get("to", ""))
	if to_pose not in ["sitting", "standing"]: return false
	_was_sitting = sitting
	_failure_measurement={}
	if to_pose == "standing":
		if not sitting or not is_instance_valid(modifier): return false
		modifier.reversing = true
		modifier.reverse_start = 1.0
		modifier.elapsed = 0.0
		modifier.settled = false
		modifier.failure = ""
		var stand_clip: Animation = body.animation_player.get_animation("stand_up")
		if stand_clip == null: return false
		modifier.duration = stand_clip.length
	else:
		if sitting or is_instance_valid(modifier): return false
		var skeleton = body.visual.get_meta("skeleton", null)
		if not skeleton is Skeleton3D or body.collider == null or not body.collider.shape is CapsuleShape3D: return false
		modifier = Modifier.new()
		skeleton.add_child(modifier)
		var clip: Animation = body.animation_player.get_animation("sit_down")
		if clip == null or not modifier.begin(body, target, declaration, clip.length):
			last_start_failure = "seat-animation-unavailable" if clip == null else str(modifier.failure)
			modifier.queue_free()
			modifier = null
			return false
		modifier.external_clock = true
		_standing_root = body.global_position
		_original_shape = body.collider.shape
		_original_center = body.collider.position
		_head_top_offset = body.global_position.y + body.nominal_height - modifier._position("head").y
		for side in ["left", "right"]:
			var foot := CollisionShape3D.new()
			foot.name = "SeatFoot_" + side
			var shape := SphereShape3D.new()
			shape.radius = 0.045
			foot.shape = shape
			foot.position = body.to_local(modifier._initial[side + "_sole"] + Vector3.UP * shape.radius)
			body.add_child(foot)
			_feet.append(foot)
		_previous_centers.clear()
	_elapsed = 0.0
	_rollback_reason = ""
	_recovered = false
	_expected_animation = "stand_up" if to_pose == "standing" else "sit_down"
	animation_finished = false
	active = true
	if bool(declaration.get("ignore_target_collision",false)) and _target_exceptions.is_empty():
		for candidate in target.find_children("*","PhysicsBody3D",true,false):
			body.add_collision_exception_with(candidate)
			_target_exceptions.append(candidate)
	last_measurement = {}
	last_start_failure = ""
	return true

func cancel(reason: String) -> Dictionary:
	animation_finished = true # Cancellation cannot certify a clip; it only permits physical recovery.
	return _reject(reason) if active else {}

func retry_recovery() -> bool:
	if active or not is_instance_valid(body) or not is_instance_valid(target) or not is_instance_valid(modifier): return false
	_rollback_reason = "seat-recovery-retry"
	_recovered = false
	_elapsed = 0.0
	modifier.reverse_start = float(modifier._blend)
	modifier.reversing = true
	modifier.elapsed = 0.0
	modifier.duration = 0.8
	modifier.settled = false
	modifier.failure = ""
	animation_finished = true
	active = true
	return true

func notify_animation_finished(clip: String) -> void:
	if active and clip == _expected_animation: animation_finished = true

func step(delta: float) -> Dictionary:
	if not active: return {}
	_elapsed += delta
	if not is_instance_valid(target) or not is_instance_valid(modifier): return _finish(false, "seat-participant-unavailable")
	modifier.elapsed += delta
	modifier._process_modification()
	if not str(modifier.failure).is_empty(): return _reject(str(modifier.failure))
	var reason := _move_physical_pose()
	if not reason.is_empty(): return _reject(reason)
	if not _rollback_reason.is_empty():
		if modifier.settled and animation_finished:
			_recovered = body.global_position.distance_to(_standing_root) <= float(declaration.get("position_tolerance_m",0.03))
			last_measurement = modifier.measurement()
			last_measurement["recovered_to_standing"] = _recovered
			return _finish(false,_rollback_reason if _recovered else "seat-recovery-position-not-reached")
		if _elapsed > float(declaration.get("timeout_s",5.0)) + 3.0: return _finish(false,"seat-recovery-timeout:" + _rollback_reason)
		return {}
	if _elapsed > float(declaration.get("timeout_s", 5.0)): return _reject("seat-posture-timeout")
	if not animation_finished or not modifier.settled or modifier.elapsed<modifier.duration+float(declaration.get("contact_settle_seconds",0.2)): return {}
	if modifier.reversing:
		var exit: Marker3D = target.resolve_interaction_slot(str(declaration.get("exit_slot", "exit")))
		if exit == null: return _finish(false, "seat-exit-unavailable")
		last_measurement = modifier.measurement()
		if not bool(last_measurement.get("settled",false)) or not _feet_on_floor(last_measurement): return _finish(false,"seat-standing-foot-floor-contact-missing")
		last_measurement["standing_contact_valid"]=true
		last_measurement["settled"] = true
		last_measurement["exit_error_m"] = body.global_position.distance_to(exit.global_position)
		if float(last_measurement.exit_error_m) > float(declaration.get("position_tolerance_m", 0.03)): return _finish(false, "seat-exit-not-reached")
		return _finish(true, "")
	last_measurement = modifier.measurement()
	if not bool(last_measurement.get("settled", false)): return _reject(str(last_measurement.get("reason", "seat-surface-unavailable")))
	if float(last_measurement.seat_error_m) > float(declaration.get("position_tolerance_m", 0.03)): return _reject("seat-surface-contact-not-reached")
	if maxf(float(last_measurement.left_foot_error_m),float(last_measurement.right_foot_error_m)) > float(declaration.get("foot_tolerance_m", 0.025)): return _reject("seat-feet-contact-not-reached")
	if not bool(declaration.get("ignore_target_collision",false)) and modifier.penetrates_seat_structure(): return _reject("seat-skinned-surface-penetrates-structure")
	if not _feet_on_floor(last_measurement): return _reject("seat-foot-floor-contact-missing")
	return _finish(true, "")

func _feet_on_floor(measurement: Dictionary) -> bool:
	for side in ["left", "right"]:
		var at: Array = measurement.get(side + "_sole_world",[])
		if at.size() != 3: return false
		var point := Vector3(at[0],at[1],at[2])
		var ray := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 0.04,point - Vector3.UP * 0.06,Layers.FLOOR)
		var hit := body.get_world_3d().direct_space_state.intersect_ray(ray)
		if hit.is_empty() or hit.normal.y < 0.7 or absf(float(hit.position.y)-point.y) > float(declaration.get("foot_tolerance_m",0.025)): return false
	return true

func _reject(reason: String) -> Dictionary:
	if _rollback_reason.is_empty(): _failure_measurement=modifier.measurement()
	# A failed down-transition reverses through native physics to the real
	# starting stand. A blocked recovery remains an explicit partial failure.
	if not _rollback_reason.is_empty() or modifier.reversing: return _finish(false,"seat-recovery-blocked:" + reason)
	_rollback_reason = reason
	modifier.reverse_start = float(modifier._blend)
	modifier.reversing = true
	modifier.elapsed = 0.0
	modifier.duration = 0.8
	modifier.settled = false
	modifier.failure = ""
	return {}

func _move_physical_pose() -> String:
	# Move the actual body root horizontally with the pelvis. Replace the tall
	# standing capsule with a torso capsule and two genuine foot colliders.
	var hips: Vector3 = modifier._position("hips")
	var bottom: float = hips.y - modifier.applied_seat_offset + 0.015
	var top: float = modifier._position("head").y + _head_top_offset
	var torso := CapsuleShape3D.new()
	torso.radius = body.collision_radius
	torso.height = maxf(torso.radius * 2.0, top - bottom)
	var centers: Array[Vector3] = [Vector3(hips.x,bottom + torso.height * 0.5,hips.z)]
	var shapes: Array[Shape3D] = [torso]
	for index in 2:
		var side := "left" if index == 0 else "right"
		var sole: Vector3 = modifier._position(side + "_foot") - modifier._sole_offsets[side]
		centers.append(sole + Vector3.UP * 0.045)
		shapes.append(_feet[index].shape)
	for index in centers.size():
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shapes[index]
		query.collision_mask = Layers.ACTOR_MOVEMENT_MASK
		query.exclude = [body.get_rid()]
		for candidate in _target_exceptions:
			var excluded_targets: Array[RID]=query.exclude
			excluded_targets.append(candidate.get_rid())
			query.exclude=excluded_targets
		# The supporting floor is a permitted foot contact, not a body obstruction.
		# This excludes only the actually ray-measured support RID from the probe;
		# the body's real collision mask continues to collide with that floor.
		var floor_ray := PhysicsRayQueryParameters3D.create(centers[index]+Vector3.UP,centers[index]-Vector3.UP*2.0,Layers.FLOOR)
		var support := body.get_world_3d().direct_space_state.intersect_ray(floor_ray)
		if not support.is_empty():
			if index>0 and support.normal.y>0.7:
				# Keep the real foot collider above its measured floor while the
				# rendered sole settles through the authored posture transition.
				centers[index].y=maxf(centers[index].y,float(support.position.y)+float(shapes[index].radius)+body.safe_margin)
			var excluded: Array[RID] = query.exclude
			excluded.append(support.rid)
			query.exclude = excluded
		query.transform.origin = centers[index]
		var overlaps := body.get_world_3d().direct_space_state.intersect_shape(query,1)
		if not overlaps.is_empty():
			body.set_meta("seat_body_overlap",{"part":index,"collider":str(overlaps[0].collider.get_path()),"center":[centers[index].x,centers[index].y,centers[index].z]})
			return "seat-body-solid-overlap"
		if _previous_centers.size() == centers.size():
			query.transform.origin = _previous_centers[index]
			query.motion = centers[index] - _previous_centers[index]
			var sweep := body.get_world_3d().direct_space_state.cast_motion(query)
			if sweep.size() != 2 or sweep[0] < 0.9999: return "seat-body-sweep-blocked"
	var destination := Vector3(hips.x+_standing_root.x-modifier._initial.hips.x,
		_standing_root.y,hips.z+_standing_root.z-modifier._initial.hips.z)
	var motion := destination - body.global_position
	body.collider.shape = torso
	body.collider.position = centers[0] - destination
	for index in 2: _feet[index].position = centers[index + 1] - destination
	if motion.length_squared() > 0.00000001:
		var collision := body.move_and_collide(motion)
		if body.global_position.distance_to(destination) > 0.005:
			last_measurement["body_error_m"]=body.global_position.distance_to(destination)
			if collision!=null:
				last_measurement["blocking_collider"]=str(collision.get_collider().get_path())
				last_measurement["blocking_normal"]=[collision.get_normal().x,collision.get_normal().y,collision.get_normal().z]
			return "seat-body-motion-blocked"
	# Reapply world-space constraints after actual native body movement.
	modifier._process_modification()
	_previous_centers = centers
	return ""

func _finish(ok: bool, reason: String) -> Dictionary:
	active = false
	var standing: bool = is_instance_valid(modifier) and bool(modifier.reversing)
	var recovered_standing: bool = standing and bool(last_measurement.get("standing_contact_valid",false))
	if ok and not standing: modifier.contact_locked=true
	sitting = false if recovered_standing else not standing if ok else _was_sitting
	if recovered_standing: last_measurement["recovered_to_standing"]=true
	last_measurement["protocol"] = "native-seat-posture-v1"
	last_measurement["from"] = declaration.get("from", "")
	last_measurement["to"] = declaration.get("to", "")
	last_measurement["seat_id"] = str(target.get_meta("world_object_id", "")) if is_instance_valid(target) else ""
	last_measurement["settled"] = ok
	last_measurement["reason"] = reason
	last_measurement["initial_failure"] = _rollback_reason
	last_measurement["initial_measurement"] = _failure_measurement
	# Recovery reaches the stand through physics. A blocked recovery retains its
	# measured partial location; it never teleports to a claimed stand/seat.
	if (ok and standing) or _recovered or recovered_standing:
		for candidate in _target_exceptions:
			if is_instance_valid(candidate): body.remove_collision_exception_with(candidate)
		_target_exceptions.clear()
		modifier.active = false
		modifier.queue_free()
		modifier = null
		body.collider.shape = _original_shape
		body.collider.position = _original_center
		for foot in _feet: foot.queue_free()
		_feet.clear()
	return {"ok":ok,"reason":reason,"measurement":last_measurement.duplicate(true)}

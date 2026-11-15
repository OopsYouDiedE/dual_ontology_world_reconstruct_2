extends RefCounted
## Retarget measured joint directions onto the same imported skeleton used by the game.
const PRIMARY := {
	"Hips":"Spine", "Spine":"Spine2", "Spine2":"Neck", "Neck":"Head",
	"LeftArm":"LeftForeArm", "LeftForeArm":"LeftHand", "RightArm":"RightForeArm", "RightForeArm":"RightHand",
	"LeftUpLeg":"LeftLeg", "LeftLeg":"LeftFoot", "LeftFoot":"LeftToeBase",
	"RightUpLeg":"RightLeg", "RightLeg":"RightFoot", "RightFoot":"RightToeBase"
}
const ROTATION_RESPONSE_HZ := 8.0
const MAX_ROTATION_SPEED_DEG_PER_S := 300.0
const MAX_ROOT_SPEED_M_PER_S := 2.5

static func point(value: Variant) -> Vector3:
	if value is Array and value.size() == 3: return Vector3(float(value[0]),float(value[1]),float(value[2]))
	return Vector3.ZERO

static func _find_humanoid_bone(skeleton: Skeleton3D, short_name: String) -> int:
	for candidate in ["mixamorig_" + short_name, "mixamorig:" + short_name, short_name]:
		var index := skeleton.find_bone(candidate)
		if index >= 0: return index
	return -1

static func _frame(side: Vector3, up: Vector3) -> Basis:
	var y := up.normalized()
	var z := side.cross(y).normalized()
	if z.length_squared() < 0.1: return Basis.IDENTITY
	return Basis(y.cross(z).normalized(),y,z).orthonormalized()

static func _sample_blend(sample: Dictionary, delta_time: float) -> float:
	if bool(sample.get("held", false)): return 0.0
	var visibility := clampf(float(sample.get("mean_visibility", 1.0)), 0.0, 1.0)
	var response := 1.0 - exp(-ROTATION_RESPONSE_HZ * maxf(delta_time, 0.0))
	return clampf(response * lerpf(0.25, 1.0, visibility), 0.0, 1.0)

static func _stabilize_rotation(previous: Quaternion, target: Quaternion, blend: float, delta_time: float) -> Quaternion:
	var desired := target.normalized()
	if previous.dot(desired) < 0.0: desired = -desired
	var rotation := previous.slerp(desired, blend).normalized()
	var maximum_step := deg_to_rad(MAX_ROTATION_SPEED_DEG_PER_S * maxf(delta_time, 0.0))
	var angle := previous.angle_to(rotation)
	if angle > maximum_step and angle > 0.000001:
		rotation = previous.slerp(rotation, maximum_step / angle).normalized()
	return rotation

static func _stabilize_root(previous: Vector3, observed: Vector3, blend: float, delta_time: float) -> Vector3:
	var filtered := previous.lerp(observed, blend)
	var maximum_step := MAX_ROOT_SPEED_M_PER_S * maxf(delta_time, 0.0)
	var step := filtered - previous
	if step.length() > maximum_step: filtered = previous + step.normalized() * maximum_step
	return filtered

static func build(skeleton: Skeleton3D, relative_path: String, data: Dictionary, actor: Node3D, target_height: float, options: Dictionary = {}) -> Dictionary:
	var samples: Array = data.get("frames", [])
	if samples.size() < 2: return {"error":"Motion requires at least two measured frames"}
	if str(data.get("coordinate_system", "")) != "right-handed Y-up, meters": return {"error":"Unsupported motion coordinates"}
	var root_policy := str(options.get("root_policy","measured"))
	if root_policy not in ["measured","grounded"]: return {"error":"Unknown root policy: "+root_policy}
	var rig_to_actor := actor.global_transform.affine_inverse() * skeleton.global_transform
	var rig_rotation := rig_to_actor.basis.orthonormalized()
	var scale_ratio := target_height / maxf(float(data.get("subject_height_m", 1.72)), 0.01)
	var mapped: Dictionary = {}
	var missing: Array[String] = []
	for source_name in data.get("bones", {}):
		var index := _find_humanoid_bone(skeleton, str(source_name))
		if index >= 0: mapped[str(source_name)] = index
		else: missing.append(str(source_name))
	if not mapped.has("Hips") or not mapped.has("LeftArm") or not mapped.has("RightUpLeg"):
		return {"error":"Target skeleton lacks required humanoid bones", "missing":missing}
	var reverse: Dictionary = {}
	for key in mapped: reverse[int(mapped[key])] = key
	var order: Array[int] = []
	for i in skeleton.get_bone_count(): order.append(i)
	order.sort_custom(func(a: int,b: int): return _depth(skeleton,a) < _depth(skeleton,b))
	var rest_points: Dictionary = {}
	for key in mapped: rest_points[key] = rig_to_actor * skeleton.get_bone_global_rest(int(mapped[key])).origin
	var animation := Animation.new()
	animation.length = float(samples[-1].time) + 1.0 / maxf(float(data.get("fps",30)),1.0)
	animation.loop_mode = Animation.LOOP_NONE
	var tracks: Dictionary = {}
	for source in mapped:
		var index: int = mapped[source]
		var track := animation.add_track(Animation.TYPE_ROTATION_3D)
		animation.track_set_path(track, NodePath(relative_path+":"+skeleton.get_bone_name(index)))
		animation.track_set_interpolation_type(track,Animation.INTERPOLATION_LINEAR)
		tracks[index] = track
	var hips: int = mapped.Hips
	var root_track := animation.add_track(Animation.TYPE_POSITION_3D)
	animation.track_set_path(root_track,NodePath(relative_path+":"+skeleton.get_bone_name(hips)))
	var initial_root := point(samples[0].root)
	var previous: Dictionary = {}
	var previous_root := Vector3.ZERO
	var previous_time := float(samples[0].time)
	var maximum_step := 0.0
	var maximum_root_step := 0.0
	var maximum_root_tracking_error := 0.0
	var raw_root_min := Vector3(INF,INF,INF)
	var raw_root_max := Vector3(-INF,-INF,-INF)
	var root_min := Vector3(INF,INF,INF)
	var root_max := Vector3(-INF,-INF,-INF)
	for sample_index in samples.size():
		var sample: Dictionary = samples[sample_index]
		var measured: Dictionary = sample.joints
		var global_pose: Dictionary = {}
		var time := float(sample.time)
		var delta_time := 1.0 / maxf(float(data.get("fps",30)), 1.0) if sample_index == 0 else maxf(time - previous_time, 0.000001)
		previous_time = time
		var blend := _sample_blend(sample, delta_time)
		for index in order:
			var parent := skeleton.get_bone_parent(index)
			var parent_basis: Basis = global_pose.get(parent,Basis.IDENTITY)
			var rest := skeleton.get_bone_rest(index)
			var desired_global := parent_basis * rest.basis
			if reverse.has(index):
				var source: String = reverse[index]
				var desired_actor := rig_rotation * skeleton.get_bone_global_rest(index).basis
				var child: String = PRIMARY.get(source, "")
				if child != "" and mapped.has(child) and measured.has(child):
					var rest_direction: Vector3 = (rest_points[child] as Vector3)-(rest_points[source] as Vector3)
					var direction := point(measured[child])-point(measured[source])
					if direction.length_squared() > 0.000001:
						desired_actor = Basis(Quaternion(rest_direction.normalized(),direction.normalized())) * desired_actor
				if source in ["Hips","Spine2"]:
					var left := "LeftUpLeg" if source == "Hips" else "LeftArm"
					var right := "RightUpLeg" if source == "Hips" else "RightArm"
					var upper := "Spine" if source == "Hips" else "Neck"
					if mapped.has(left) and mapped.has(right) and mapped.has(upper):
						var reference_frame := _frame(rest_points[left]-rest_points[right],rest_points[upper]-rest_points[source])
						var observed_frame := _frame(point(measured[left])-point(measured[right]),point(measured[upper])-point(measured[source]))
						desired_actor = observed_frame * reference_frame.inverse() * rig_rotation * skeleton.get_bone_global_rest(index).basis
				if child != "": desired_global = rig_rotation.inverse() * desired_actor
			if tracks.has(index):
				var rotation := (parent_basis.inverse()*desired_global).orthonormalized().get_rotation_quaternion()
				if previous.has(index):
					var last: Quaternion = previous[index]
					rotation = _stabilize_rotation(last, rotation, blend, delta_time)
					maximum_step = maxf(maximum_step,rad_to_deg(last.angle_to(rotation)))
				previous[index] = rotation
				animation.rotation_track_insert_key(int(tracks[index]),time,rotation)
				global_pose[index] = (parent_basis * Basis(rotation)).orthonormalized()
			else:
				global_pose[index] = desired_global.orthonormalized()
		var raw_displacement := (point(sample.root)-initial_root)*scale_ratio
		raw_root_min = raw_root_min.min(raw_displacement)
		raw_root_max = raw_root_max.max(raw_displacement)
		var displacement := Vector3(raw_displacement.x,0.0 if root_policy == "grounded" else raw_displacement.y,0.0)
		var root_before := previous_root
		if sample_index > 0: previous_root = _stabilize_root(previous_root, displacement, blend, delta_time)
		else: previous_root = displacement
		maximum_root_step = maxf(maximum_root_step, root_before.distance_to(previous_root))
		maximum_root_tracking_error = maxf(maximum_root_tracking_error, previous_root.distance_to(displacement))
		displacement = previous_root
		root_min = root_min.min(displacement)
		root_max = root_max.max(displacement)
		var hips_parent := skeleton.get_bone_parent(hips)
		var parent_rest := skeleton.get_bone_global_rest(hips_parent) if hips_parent >= 0 else Transform3D.IDENTITY
		var local_displacement := parent_rest.basis.inverse() * rig_to_actor.basis.inverse() * displacement
		animation.position_track_insert_key(root_track,time,skeleton.get_bone_rest(hips).origin+local_displacement)
	var library := AnimationLibrary.new()
	library.add_animation("video",animation)
	return {"library":library, "report":{"mapped_bones":mapped.size(), "missing_bones":missing,
		"frames":samples.size(), "duration_s":animation.length, "target_height_m":target_height,
		"root_scale_ratio":scale_ratio,"root_min_m":[root_min.x,root_min.y,root_min.z],
		"root_max_m":[root_max.x,root_max.y,root_max.z],"raw_root_min_m":[raw_root_min.x,raw_root_min.y,raw_root_min.z],
		"raw_root_max_m":[raw_root_max.x,raw_root_max.y,raw_root_max.z],"max_rotation_step_deg":maximum_step,
		"max_root_step_m":maximum_root_step,"max_root_tracking_error_m":maximum_root_tracking_error,"rotation_response_hz":ROTATION_RESPONSE_HZ,
		"max_rotation_speed_deg_per_s":MAX_ROTATION_SPEED_DEG_PER_S,"max_root_speed_m_per_s":MAX_ROOT_SPEED_M_PER_S,
		"source_quality":data.get("quality",{}), "depth_translation":"unobserved; zero",
		"root_policy":root_policy,
		"root_translation":"measured horizontal X; floor-relative Y excluded for grounded walking" if root_policy == "grounded" else "measured horizontal X and observed floor-relative Y; filtered with source values retained",
		"method":"measured directions and hip/shoulder frames; visibility-weighted rotation stabilization and selected root policy speed clamp; no foot locking",
		"acceptance_scored":false}}

static func _depth(skeleton: Skeleton3D,index: int) -> int:
	var depth := 0
	while skeleton.get_bone_parent(index) >= 0:
		index = skeleton.get_bone_parent(index)
		depth += 1
	return depth

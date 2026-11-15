extends SceneTree
## Headless numerical regression for measured-motion retargeting.
const Motion := preload("res://scenes/components/characters/VideoMotionLibrary.gd")

func _argument(key: String, fallback: String = "") -> String:
	for value in OS.get_cmdline_user_args():
		var argument: String = str(value)
		if argument.begins_with("--" + key + "="):
			return argument.substr(key.length() + 3)
	return fallback

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	Engine.max_fps = 0
	var motion_path := _argument("motion")
	var output := _argument("test-output",_argument("output"))
	if motion_path.is_empty() or output.is_empty():
		push_error("retarget_regression requires --motion=<motion.json> and --output=<directory>")
		quit(2)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(motion_path))
	if not parsed is Dictionary:
		push_error("Motion JSON is invalid")
		quit(2)
		return
	var data: Dictionary = parsed
	var actor := Node3D.new()
	actor.name = "RegressionActor"
	var skeleton := _make_skeleton(data)
	actor.add_child(skeleton)
	root.add_child(actor)
	skeleton.force_update_all_bone_transforms()
	var built: Dictionary = Motion.build(skeleton, "Skeleton", data, actor, 1.32,{"root_policy":"grounded"})
	var result: Dictionary = {
		"created_at": Time.get_datetime_string_from_system(true, true),
		"motion_path": motion_path,
		"motion_sha256": FileAccess.get_sha256(motion_path),
		"retarget_script_sha256": FileAccess.get_sha256("res://scenes/components/characters/VideoMotionLibrary.gd"),
		"headless": DisplayServer.get_name() == "headless",
		"engine_version": Engine.get_version_info(),
		"command_arguments": OS.get_cmdline_args(),
		"raw_input": _raw_metrics(data),
		"acceptance_scored": false
	}
	if built.has("error"):
		result["error"] = built.error
		_write(output, result)
		quit(1)
		return
	var report: Dictionary = built.report
	var library: AnimationLibrary = built.library
	var animation := library.get_animation("video")
	DirAccess.make_dir_recursive_absolute(output)
	var resource_path := output.path_join("retargeted-regression.res")
	var export_code: int = ResourceSaver.save(library, resource_path)
	var export_ok := export_code == OK and FileAccess.file_exists(resource_path)
	var expected_frames := int(report.get("frames", 0))
	var expected_tracks := int(report.get("mapped_bones", 0)) + 1
	var track_count := animation.get_track_count() if animation != null else 0
	var keys_per_track: Array = []
	if animation != null:
		for track in range(track_count):
			keys_per_track.append(animation.track_get_key_count(track))
	var root_min := Motion.point(report.get("root_min_m", []))
	var root_max := Motion.point(report.get("root_max_m", []))
	var source_quality: Dictionary = report.get("source_quality", {})
	var measured_built: Dictionary = Motion.build(skeleton,"Skeleton",data,actor,1.32,{"root_policy":"measured"})
	var measured_report: Dictionary = measured_built.get("report",{})
	var vertical_span := Motion.point(measured_report.get("root_max_m",[])).y-Motion.point(measured_report.get("root_min_m",[])).y
	var checks := {
		"library_created": library != null and animation != null,
		"library_serialized": export_ok,
		"track_count": track_count == expected_tracks,
		"keys_per_track": keys_per_track.all(func(count: int) -> bool: return count == expected_frames),
		"rotation_step_limited": float(report.get("max_rotation_step_deg", INF)) <= 30.0001,
		"root_step_limited": float(report.get("max_root_step_m", INF)) <= 0.2501,
		"retargeted_root_has_no_vertical_or_depth_motion": is_zero_approx(root_min.y) and is_zero_approx(root_max.y) and is_zero_approx(root_min.z) and is_zero_approx(root_max.z),
		"measured_mode_preserves_vertical_motion": vertical_span>0.001,
		"source_quality_preserved": int(source_quality.get("detected_frames", -1)) == 49 and int(source_quality.get("held_frames", -1)) == 1 and bool(source_quality.get("requires_manual_motion_review", false)),
		"manual_review_still_required": bool(source_quality.get("requires_manual_motion_review", false)) and not bool(report.get("acceptance_scored", true))
	}
	var passed := true
	for value in checks.values():
		if not bool(value):
			passed = false
	result["report"] = report
	result["measured_root_mode_report"] = measured_report
	result["checks"] = checks
	result["passed"] = passed
	result["expected_frames"] = expected_frames
	result["expected_tracks"] = expected_tracks
	result["track_count"] = track_count
	result["keys_per_track"] = keys_per_track
	result["retargeted_library_path"] = resource_path
	result["retargeted_library_sha256"] = FileAccess.get_sha256(resource_path) if export_ok else ""
	result["retargeted_library_export_error"] = export_code
	_write(output, result)
	actor.queue_free()
	quit(0 if passed else 1)

func _make_skeleton(data: Dictionary) -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton"
	var bones: Dictionary = data.get("bones", {})
	var samples: Array = data.get("frames", [])
	var first: Dictionary = samples[0]
	var joints: Dictionary = first.get("joints", {})
	for bone_name_value in bones.keys():
		skeleton.add_bone(str(bone_name_value))
	for bone_name_value in bones.keys():
		var bone_name: String = str(bone_name_value)
		var index := skeleton.find_bone(bone_name)
		var parent_name: String = str(bones[bone_name])
		var parent_index := skeleton.find_bone(parent_name) if not parent_name.is_empty() else -1
		skeleton.set_bone_parent(index, parent_index)
		var position := Motion.point(joints.get(bone_name, []))
		var parent_position := Motion.point(joints.get(parent_name, [])) if parent_index >= 0 else Vector3.ZERO
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, position - parent_position))
	return skeleton

func _raw_metrics(data: Dictionary) -> Dictionary:
	var samples: Array = data.get("frames", [])
	var fps := maxf(float(data.get("fps", 0.0)), 0.01)
	var root_steps: Array = []
	var maximum_root_step := 0.0
	var maximum_rotation_step := 0.0
	var maximum_rotation_source := ""
	for sample_index in range(1, samples.size()):
		var current: Dictionary = samples[sample_index]
		var previous: Dictionary = samples[sample_index - 1]
		var root_step := Motion.point(current.get("root", [])).distance_to(Motion.point(previous.get("root", [])))
		root_steps.append(root_step)
		maximum_root_step = maxf(maximum_root_step, root_step)
		var current_joints: Dictionary = current.get("joints", {})
		var previous_joints: Dictionary = previous.get("joints", {})
		for source_value in Motion.PRIMARY.keys():
			var source: String = str(source_value)
			var child: String = str(Motion.PRIMARY[source])
			var current_direction := Motion.point(current_joints.get(child, [])) - Motion.point(current_joints.get(source, []))
			var previous_direction := Motion.point(previous_joints.get(child, [])) - Motion.point(previous_joints.get(source, []))
			if current_direction.length_squared() > 0.000001 and previous_direction.length_squared() > 0.000001:
				var angle := rad_to_deg(previous_direction.angle_to(current_direction))
				if angle > maximum_rotation_step:
					maximum_rotation_step = angle
					maximum_rotation_source = source
	var roots: Array = []
	for sample_value in samples:
		var sample: Dictionary = sample_value
		roots.append(Motion.point(sample.get("root", [])))
	var root_min := Vector3(INF, INF, INF)
	var root_max := Vector3(-INF, -INF, -INF)
	for root_value in roots:
		var root_point: Vector3 = root_value
		root_min = root_min.min(root_point)
		root_max = root_max.max(root_point)
	return {
		"fps": fps,
		"frames": samples.size(),
		"maximum_root_step_m": maximum_root_step,
		"root_y_span_m": root_max.y - root_min.y,
		"maximum_direction_step_deg": maximum_rotation_step,
		"maximum_direction_source": maximum_rotation_source,
		"held_frame_indices": samples.filter(func(sample: Dictionary) -> bool: return bool(sample.get("held", false))).map(func(sample: Dictionary) -> int: return int(round(float(sample.get("time", 0.0)) * fps)))
	}

func _write(directory: String, value: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(directory)
	var file := FileAccess.open(directory.path_join("retarget-regression.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "\t"))
		file.close()

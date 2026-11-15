extends SceneTree
## CPU/headless probe for Mixamo retarget-cache builds and reuse.
## Use --animation-retarget-cache-dir to keep an acceptance run isolated from player data.

const ImportedCharacter := preload("res://scenes/components/characters/ImportedCharacter.gd")
const DEFAULT_MODEL := "res://assets/characters/UserModels/model_06.glb"

func _initialize() -> void:
	var args := _arguments()
	var model_path := String(args.get("model", DEFAULT_MODEL))
	var output_path := String(args.get("output", "user://retarget-cache-probe.json"))
	var yaw := float(args.get("yaw", "-90.0"))
	var save_library_path := String(args.get("save-library", ""))
	var reference_path := String(args.get("reference", ""))
	var start_usec := Time.get_ticks_usec()
	var host := Node3D.new()
	host.name = "RetargetCacheProbeHost"
	get_root().add_child(host)
	var attached := ImportedCharacter.attach(host, model_path, 1.70, yaw, "retarget-cache-probe")
	var player := host.get_meta("animation_player", null) as AnimationPlayer
	var library: AnimationLibrary = null
	if player != null and player.has_animation_library(""):
		library = player.get_animation_library("")
	var save_error := OK
	if library != null and not save_library_path.is_empty():
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(save_library_path.get_base_dir()))
		save_error = ImportedCharacter.write_retarget_library_snapshot(library, save_library_path)
	var equivalence := {}
	if library != null and not reference_path.is_empty():
		var reference := ImportedCharacter.read_retarget_library_snapshot(reference_path)
		equivalence = _compare_libraries(reference, library)
	var report := {
		"ok": attached and library != null and save_error == OK and bool(equivalence.get("ok", true)),
		"model": model_path,
		"yaw": yaw,
		"elapsed_usec": Time.get_ticks_usec() - start_usec,
		"library_fingerprint": _library_fingerprint(library),
		"clip_count": library.get_animation_list().size() if library != null else 0,
		"save_error": save_error,
		"equivalence": equivalence,
		"cache": ImportedCharacter.get_retarget_cache_stats(),
		"cache_dir": ProjectSettings.globalize_path(ImportedCharacter._retarget_cache_directory())
	}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path.get_base_dir()))
	var report_file := FileAccess.open(output_path, FileAccess.WRITE)
	if report_file != null:
		report_file.store_string(JSON.stringify(report, "\t"))
		report_file.close()
	print(JSON.stringify(report))
	quit(0 if report.ok else 1)

func _arguments() -> Dictionary:
	var values := {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var split := argument.substr(2).split("=", false, 1)
		if split.size() == 2:
			values[split[0]] = split[1]
	return values

func _library_fingerprint(library: AnimationLibrary) -> String:
	if library == null:
		return ""
	var clips: Array = []
	var names := library.get_animation_list()
	names.sort()
	for name in names:
		var animation := library.get_animation(name)
		var tracks: Array = []
		for track in range(animation.get_track_count()):
			var keys: Array = []
			for key in range(animation.track_get_key_count(track)):
				keys.append([animation.track_get_key_time(track, key), animation.track_get_key_value(track, key), animation.track_get_key_transition(track, key)])
			tracks.append([animation.track_get_type(track), animation.track_get_path(track), animation.track_get_interpolation_type(track), keys])
		clips.append([name, animation.length, animation.loop_mode, tracks])
	return var_to_bytes(clips).hex_encode().sha256_text()

func _compare_libraries(expected: AnimationLibrary, actual: AnimationLibrary) -> Dictionary:
	var result := {"ok": false, "reason": "missing_library", "max_time_error": 0.0, "max_value_error": 0.0, "tracks_checked": 0, "keys_checked": 0}
	if expected == null or actual == null:
		return result
	var expected_names := expected.get_animation_list()
	var actual_names := actual.get_animation_list()
	expected_names.sort()
	actual_names.sort()
	if expected_names != actual_names:
		result.reason = "clip_names"
		return result
	for name in expected_names:
		var left := expected.get_animation(name)
		var right := actual.get_animation(name)
		if left == null or right == null or left.loop_mode != right.loop_mode or absf(left.length - right.length) > 0.000001 or left.get_track_count() != right.get_track_count():
			result.reason = "clip_layout:" + name
			return result
		for track in range(left.get_track_count()):
			if left.track_get_type(track) != right.track_get_type(track) or left.track_get_path(track) != right.track_get_path(track) or left.track_get_interpolation_type(track) != right.track_get_interpolation_type(track) or left.track_get_key_count(track) != right.track_get_key_count(track):
				result.reason = "track_layout:%s:%d" % [name, track]
				return result
			result.tracks_checked += 1
			for key in range(left.track_get_key_count(track)):
				var time_error := absf(left.track_get_key_time(track, key) - right.track_get_key_time(track, key))
				var value_error := _value_error(left.track_get_key_value(track, key), right.track_get_key_value(track, key))
				result.max_time_error = maxf(float(result.max_time_error), time_error)
				result.max_value_error = maxf(float(result.max_value_error), value_error)
				result.keys_checked += 1
				if time_error > 0.000001 or value_error > 0.00001:
					result.reason = "key_values:%s:%d:%d" % [name, track, key]
					result.expected_value = _describe_value(left.track_get_key_value(track, key))
					result.actual_value = _describe_value(right.track_get_key_value(track, key))
					return result
	result.ok = true
	result.reason = "equivalent"
	return result

func _value_error(left: Variant, right: Variant) -> float:
	if left is Quaternion and right is Quaternion:
		var left_quaternion := left as Quaternion
		var right_quaternion := right as Quaternion
		return maxf(maxf(absf(left_quaternion.x - right_quaternion.x), absf(left_quaternion.y - right_quaternion.y)), maxf(absf(left_quaternion.z - right_quaternion.z), absf(left_quaternion.w - right_quaternion.w)))
	if left is Vector3 and right is Vector3:
		return (left as Vector3).distance_to(right as Vector3)
	if left is float or left is int:
		return absf(float(left) - float(right))
	return 0.0 if var_to_bytes(left) == var_to_bytes(right) else INF

func _describe_value(value: Variant) -> Variant:
	if value is Quaternion:
		var quaternion := value as Quaternion
		return [quaternion.x, quaternion.y, quaternion.z, quaternion.w]
	if value is Vector3:
		var vector := value as Vector3
		return [vector.x, vector.y, vector.z]
	return value

extends RefCounted

const RIG_FIX := preload("res://scenes/rogue_player/RigWeightFix.gd")
const ANIM_LIB_HELPER := preload("res://scenes/rogue_player/KayKitAnimationLibrary.gd")
const CHIBI_SHADER := preload("res://scenes/rogue_player/ChibiFigurineSurface.gdshader")
const CHIBI_DOUBLE_SIDED := preload("res://scenes/rogue_player/ChibiFigurineDoubleSided.gdshader")
const SOURCE_RIG_PATH := "res://assets/imported/kaykit/animations/Rig_Medium_General.glb"

const NOMINAL_ACTOR_HEIGHT := 1.32
const BASE_RIG_HEIGHT := 1.86
const COLLISION_RADIUS := 0.18
const EYE_HEIGHT := 1.15
const KAYKIT_THREE_HEAD_SCALE := 0.58
const RETARGET_SAMPLE_FPS := 24.0
const ARM_LATERAL_SWING_RATIO := 0.55
## Disk cache entries are immutable and keyed by every input that changes a retargeted clip.
## They live under user:// so exported games can reuse a completed build across launches.
const RETARGET_CACHE_SCHEMA := 2
const RETARGET_CACHE_DIR := "user://mixamo-retarget-cache-v2"
const ARM_CHAIN_ROOT := {
	"upperarm.l": "upperarm.l", "lowerarm.l": "upperarm.l", "hand.l": "upperarm.l",
	"upperarm.r": "upperarm.r", "lowerarm.r": "upperarm.r", "hand.r": "upperarm.r"
}

const MIXAMO_TO_KAYKIT := {
	"Hips": "hips",
	"Spine": "spine",
	"Spine2": "chest",
	"Head": "head",
	"LeftArm": "upperarm.l",
	"LeftForeArm": "lowerarm.l",
	"LeftHand": "hand.l",
	"RightArm": "upperarm.r",
	"RightForeArm": "lowerarm.r",
	"RightHand": "hand.r",
	"LeftUpLeg": "upperleg.l",
	"LeftLeg": "lowerleg.l",
	"LeftFoot": "foot.l",
	"LeftToeBase": "toes.l",
	"RightUpLeg": "upperleg.r",
	"RightLeg": "lowerleg.r",
	"RightFoot": "foot.r",
	"RightToeBase": "toes.r"
}

const ALIAS_CLIPS := {
	"read_gauge": "interact",
	"read_scroll": "interact",
	"turn_wheel": "operate",
	"open_latch": "lockpick"
}

static var _scaled_head_mesh_cache: Dictionary = {}
static var _source_rig_data: Dictionary = {}
static var _retargeted_lib_cache: Dictionary = {}
static var retarget_builds := 0
static var retarget_cache_hits := 0
static var retarget_build_usec := 0
static var retarget_disk_cache_hits := 0
static var retarget_disk_cache_hit_usec := 0
static var retarget_cache_writes := 0
static var retarget_cache_invalidations := 0
static var retarget_last_cache_key := ""
static var _figurine_material_cache: Dictionary = {}

static func get_retarget_cache_stats() -> Dictionary:
	return {
		"builds": retarget_builds,
		"memory_hits": retarget_cache_hits - retarget_disk_cache_hits,
		"disk_hits": retarget_disk_cache_hits,
		"build_usec": retarget_build_usec,
		"disk_hit_usec": retarget_disk_cache_hit_usec,
		"writes": retarget_cache_writes,
		"invalidations": retarget_cache_invalidations,
		"last_cache_key": retarget_last_cache_key
	}

static func clear_retarget_memory_cache() -> void:
	_retargeted_lib_cache.clear()

static func resolve_model_path(path: String, _character_id: String = "") -> String:
	return path

static func attach(parent: Node3D, path: String, height: float = NOMINAL_ACTOR_HEIGHT, yaw_degrees: float = 0.0, character_id: String = "") -> bool:
	if height <= 0.0:
		height = NOMINAL_ACTOR_HEIGHT
	var resolved_path := resolve_model_path(path, character_id)
	var packed := load(resolved_path) as PackedScene
	if packed == null:
		push_error("Failed to load character scene: " + resolved_path)
		return false
	var model := packed.instantiate() as Node3D
	if model == null:
		return false

	var skel: Skeleton3D = _find_skeleton(model)
	var kaykit_rig := resolved_path.begins_with("res://assets/imported/kaykit/characters/") and skel != null
	var mixamo_rig := (not kaykit_rig) and skel != null and _find_mixamo_bone(skel, "Hips") != -1 and _find_mixamo_bone(skel, "LeftArm") != -1
	if kaykit_rig:
		_apply_kaykit_three_head_proportion(model, skel, resolved_path)

	# 蒙皮权重修正：左右腿错边、衣摆单腿拖拽、颈下头骨权重（见 RigWeightFix.gd）
	if mixamo_rig and not OS.get_cmdline_user_args().has("nofix=1"):
		RIG_FIX.apply(model, skel, resolved_path)

	_apply_chibi_figurine_materials(model, resolved_path)

	var bounds: Variant = _visual_bounds(model, Transform3D.IDENTITY)
	var source_height: float = bounds.size.y if bounds != null else BASE_RIG_HEIGHT
	var scale_factor := height / maxf(0.001, source_height)
	model.scale *= Vector3.ONE * scale_factor
	if bounds != null:
		model.position.y -= bounds.position.y * scale_factor
	model.rotation.y += deg_to_rad(yaw_degrees)

	var slot_r: BoneAttachment3D = null
	var slot_l: BoneAttachment3D = null
	if kaykit_rig:
		var r_bone := "handslot.r" if skel.find_bone("handslot.r") != -1 else "hand.r"
		var l_bone := "handslot.l" if skel.find_bone("handslot.l") != -1 else "hand.l"
		slot_r = _create_hand_slot(skel, "RightHandSlot", r_bone)
		slot_l = _create_hand_slot(skel, "LeftHandSlot", l_bone)
	elif mixamo_rig:
		var r_idx := _find_mixamo_bone(skel, "RightHand")
		var l_idx := _find_mixamo_bone(skel, "LeftHand")
		if r_idx != -1:
			slot_r = _create_hand_slot(skel, "RightHandSlot", skel.get_bone_name(r_idx))
		if l_idx != -1:
			slot_l = _create_hand_slot(skel, "LeftHandSlot", skel.get_bone_name(l_idx))

	var player := model.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if player == null:
		player = AnimationPlayer.new()
		player.name = "AnimationPlayer"
		model.add_child(player)
	player.root_node = player.get_path_to(model)

	var lib: AnimationLibrary = null
	if kaykit_rig:
		lib = ANIM_LIB_HELPER.get_library()
	elif mixamo_rig:
		var skel_rel_path := String(model.get_path_to(skel))
		lib = _get_or_build_mixamo_library(skel, skel_rel_path, yaw_degrees, resolved_path)

	if lib != null:
		for existing_lib_name in player.get_animation_library_list():
			player.remove_animation_library(existing_lib_name)
		player.add_animation_library("", lib)
		player.playback_default_blend_time = 0.2
		if player.has_animation("idle"):
			player.play("idle")
			player.advance(0.0)

	parent.add_child(model)
	parent.set_meta("model_source", resolved_path)
	parent.set_meta("presentation", "kaykit-animated-character" if (kaykit_rig or mixamo_rig) else "dv-selected-character")
	parent.set_meta("nominal_actor_height", height)
	parent.set_meta("collision_radius", COLLISION_RADIUS)
	parent.set_meta("eye_height", EYE_HEIGHT)
	parent.set_meta("feet_y", 0.0)
	parent.set_meta("animation_player", player if player.has_animation("idle") else null)
	parent.set_meta("skeleton", skel)
	parent.set_meta("slot_right_hand", slot_r)
	parent.set_meta("slot_left_hand", slot_l)
	return true

static func _create_hand_slot(skel: Skeleton3D, slot_name: String, bone_name: String) -> BoneAttachment3D:
	var slot := BoneAttachment3D.new()
	slot.name = slot_name
	slot.bone_name = bone_name
	skel.add_child(slot)
	return slot

static func _find_mixamo_bone(skel: Skeleton3D, short_name: String) -> int:
	for candidate in ["mixamorig_" + short_name, "mixamorig:" + short_name, short_name]:
		var idx := skel.find_bone(candidate)
		if idx != -1:
			return idx
	return -1

static func _strip_mixamo_prefix(bone_name: String) -> String:
	if bone_name.begins_with("mixamorig_"):
		return bone_name.substr(10)
	if bone_name.begins_with("mixamorig:"):
		return bone_name.substr(10)
	return bone_name

static func _get_source_rig_data() -> Dictionary:
	if not _source_rig_data.is_empty():
		return _source_rig_data
	if not ResourceLoader.exists(SOURCE_RIG_PATH):
		push_warning("Source rig GLB not found: " + SOURCE_RIG_PATH)
		return {}
	var packed := load(SOURCE_RIG_PATH) as PackedScene
	if packed == null:
		return {}
	var inst := packed.instantiate()
	var skel_s := _find_skeleton(inst)
	if skel_s == null:
		inst.free()
		return {}

	var order: Array[String] = []
	var parent_map: Dictionary = {}
	var local_rest: Dictionary = {}
	var global_rest: Dictionary = {}
	var global_rest_inv: Dictionary = {}
	var bone_count := skel_s.get_bone_count()
	var visited: Dictionary = {}

	while order.size() < bone_count:
		var progressed := false
		for i in range(bone_count):
			if visited.has(i):
				continue
			var p_idx := skel_s.get_bone_parent(i)
			if p_idx == -1 or visited.has(p_idx):
				visited[i] = true
				progressed = true
				var b_name := skel_s.get_bone_name(i)
				order.append(b_name)
				parent_map[b_name] = skel_s.get_bone_name(p_idx) if p_idx != -1 else ""
				var l_rest := skel_s.get_bone_rest(i)
				var g_rest := skel_s.get_bone_global_rest(i)
				local_rest[b_name] = l_rest
				global_rest[b_name] = g_rest
				global_rest_inv[b_name] = g_rest.basis.orthonormalized().inverse()
		if not progressed:
			break

	inst.free()
	_source_rig_data = {
		"order": order,
		"parent": parent_map,
		"local_rest": local_rest,
		"global_rest": global_rest,
		"global_rest_inv": global_rest_inv
	}
	return _source_rig_data

static func _get_or_build_mixamo_library(skel_t: Skeleton3D, skel_rel_path: String, yaw_degrees: float, _resolved_path: String) -> AnimationLibrary:
	var target_signature: Array = [skel_rel_path, yaw_degrees]
	for index in skel_t.get_bone_count():
		target_signature.append([skel_t.get_bone_name(index), skel_t.get_bone_parent(index), skel_t.get_bone_rest(index)])
	var memory_key := var_to_bytes(target_signature).hex_encode().sha256_text()
	if _retargeted_lib_cache.has(memory_key):
		retarget_cache_hits += 1
		return _retargeted_lib_cache[memory_key]
	var build_started := Time.get_ticks_usec()

	var cache_key := _retarget_cache_key(target_signature, _resolved_path)
	retarget_last_cache_key = cache_key
	if _retarget_disk_cache_enabled():
		var disk_cached := _load_retarget_disk_cache(cache_key)
		if disk_cached != null:
			_cache_retargeted_library(memory_key, disk_cached)
			retarget_cache_hits += 1
			retarget_disk_cache_hits += 1
			retarget_disk_cache_hit_usec += Time.get_ticks_usec() - build_started
			return disk_cached
	var src_lib: AnimationLibrary = ANIM_LIB_HELPER.get_library()
	if src_lib == null:
		return null
	# Loading the source may create its generated library on the first run.
	cache_key = _retarget_cache_key(target_signature,_resolved_path)
	retarget_last_cache_key = cache_key
	var src_rig := _get_source_rig_data()
	if src_rig.is_empty():
		return null

	var s_order: Array = src_rig["order"]
	var s_parent: Dictionary = src_rig["parent"]
	var s_local_rest: Dictionary = src_rig["local_rest"]
	var s_global_rest_inv: Dictionary = src_rig["global_rest_inv"]

	var t_count := skel_t.get_bone_count()
	var t_order: Array[int] = []
	var t_visited: Dictionary = {}
	while t_order.size() < t_count:
		var progressed := false
		for i in range(t_count):
			if t_visited.has(i):
				continue
			var p_idx := skel_t.get_bone_parent(i)
			if p_idx == -1 or t_visited.has(p_idx):
				t_visited[i] = true
				progressed = true
				t_order.append(i)
		if not progressed:
			break

	var t_parent: Array[int] = []
	var t_bone_name: Array[String] = []
	var t_mapped_src: Array[String] = []
	var t_local_rest_basis: Array[Basis] = []
	var t_global_rest_basis: Array[Basis] = []
	t_parent.resize(t_count)
	t_bone_name.resize(t_count)
	t_mapped_src.resize(t_count)
	t_local_rest_basis.resize(t_count)
	t_global_rest_basis.resize(t_count)

	var hips_t_idx := -1
	var target_arm_directions: Dictionary = {}
	for i in range(t_count):
		var b_name := skel_t.get_bone_name(i)
		var short_name := _strip_mixamo_prefix(b_name)
		t_parent[i] = skel_t.get_bone_parent(i)
		t_bone_name[i] = b_name
		t_mapped_src[i] = MIXAMO_TO_KAYKIT.get(short_name, "")
		t_local_rest_basis[i] = skel_t.get_bone_rest(i).basis.orthonormalized()
		t_global_rest_basis[i] = skel_t.get_bone_global_rest(i).basis.orthonormalized()
		if short_name == "Hips":
			hips_t_idx = i
		if short_name == "LeftArm" or short_name == "RightArm":
			var forearm := _find_mixamo_bone(skel_t, "LeftForeArm" if short_name == "LeftArm" else "RightForeArm")
			if forearm != -1:
				var rest := skel_t.get_bone_global_rest(i)
				target_arm_directions[i] = rest.basis.inverse() * (skel_t.get_bone_global_rest(forearm).origin - rest.origin)

	var r_align := Basis(Vector3.UP, deg_to_rad(yaw_degrees))
	var r_align_inv := r_align.inverse()

	var hips_s_rest_pos: Vector3 = (s_local_rest.get("hips", Transform3D.IDENTITY) as Transform3D).origin
	var hips_t_rest_pos: Vector3 = skel_t.get_bone_rest(hips_t_idx).origin if hips_t_idx != -1 else Vector3(0.0, 0.466, 0.0)
	var hip_scale := hips_t_rest_pos.y / maxf(0.05, hips_s_rest_pos.y)

	var dst_lib := AnimationLibrary.new()
	var built_clips: Dictionary = {}

	for anim_name in src_lib.get_animation_list():
		if ALIAS_CLIPS.has(anim_name):
			continue
		var src_anim: Animation = src_lib.get_animation(anim_name)
		if src_anim == null:
			continue
		var dst_anim := _retarget_single_clip(
			src_anim,
			skel_rel_path,
			s_order,
			s_parent,
			s_local_rest,
			s_global_rest_inv,
			t_order,
			t_parent,
			t_bone_name,
			t_mapped_src,
			t_local_rest_basis,
			t_global_rest_basis,
			hips_t_idx,
			hips_s_rest_pos,
			hips_t_rest_pos,
			hip_scale,
			r_align,
			r_align_inv,
			target_arm_directions
		)
		built_clips[anim_name] = dst_anim
		dst_lib.add_animation(anim_name, dst_anim)

	if built_clips.has("walk") and built_clips.has("carry_walk"):
		var moving: Animation=built_clips.walk.duplicate(true)
		var holding: Animation=built_clips.carry_walk
		for track in moving.get_track_count():
			var path:=moving.track_get_path(track)
			if path.get_subname_count()==0: continue
			var bone:=str(path.get_subname(0)).trim_prefix("mixamorig:").trim_prefix("mixamorig_")
			if bone not in ["LeftArm","LeftForeArm","LeftHand","RightArm","RightForeArm","RightHand"]: continue
			var source:=holding.find_track(path,moving.track_get_type(track))
			if source<0 or holding.track_get_key_count(source)==0: continue
			var pose=holding.track_get_key_value(source,0)
			while moving.track_get_key_count(track)>0: moving.track_remove_key(track,0)
			moving.track_insert_key(track,0.0,pose)
			moving.track_insert_key(track,moving.length,pose)
		dst_lib.remove_animation("carry_walk")
		dst_lib.add_animation("carry_walk",moving)
		built_clips["carry_walk"]=moving

	for alias_name in ALIAS_CLIPS:
		var base_name: String = ALIAS_CLIPS[alias_name]
		if built_clips.has(base_name):
			var alias_anim: Animation = (built_clips[base_name] as Animation).duplicate(false)
			dst_lib.add_animation(alias_name, alias_anim)

	if _retarget_disk_cache_enabled():
		_store_retarget_disk_cache(cache_key, dst_lib)
	_cache_retargeted_library(memory_key, dst_lib)
	retarget_builds += 1
	retarget_build_usec += Time.get_ticks_usec() - build_started
	return dst_lib

static func _cache_retargeted_library(memory_key: String, library: AnimationLibrary) -> void:
	if _retargeted_lib_cache.size() >= 64:
		_retargeted_lib_cache.erase(_retargeted_lib_cache.keys()[0])
	_retargeted_lib_cache[memory_key] = library

static func _retarget_disk_cache_enabled() -> bool:
	return not OS.get_cmdline_user_args().has("--animation-retarget-cache-disable=1")

static func _retarget_cache_key(target_signature: Array, resolved_path: String) -> String:
	var inputs := {
		"schema": RETARGET_CACHE_SCHEMA,
		"target_skeleton": target_signature,
		"target_model_sha256": _resource_sha256(resolved_path),
		"source_rig_sha256": _resource_sha256(SOURCE_RIG_PATH),
		"source_clips_sha256": Array(ANIM_LIB_HELPER.CLIPS_CONFIG.keys()).map(_resource_sha256),
		"source_animation_inputs_sha256": _source_animation_inputs_sha256(),
		"retarget_script_sha256": _resource_sha256("res://scenes/rogue_player/ImportedCharacter.gd"),
		"source_library_script_sha256": _resource_sha256("res://scenes/rogue_player/KayKitAnimationLibrary.gd"),
		"parameters": {
			"sample_fps": RETARGET_SAMPLE_FPS,
			"arm_lateral_swing_ratio": ARM_LATERAL_SWING_RATIO,
			"bone_map": MIXAMO_TO_KAYKIT,
			"arm_chain_root": ARM_CHAIN_ROOT,
			"aliases": ALIAS_CLIPS
		}
	}
	return var_to_bytes(inputs).hex_encode().sha256_text()

static func _resource_sha256(path: String) -> String:
	return FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "missing"

static func _source_animation_inputs_sha256() -> String:
	var source_paths: Array[String] = []
	for source_path in ANIM_LIB_HELPER.CLIPS_CONFIG.keys():
		source_paths.append(String(source_path))
	source_paths.sort()
	var source_files: Array = []
	for source_path in source_paths:
		source_files.append([source_path, _resource_sha256(source_path)])
	return var_to_bytes([source_files, ANIM_LIB_HELPER.CLIPS_CONFIG]).hex_encode().sha256_text()

static func _retarget_cache_directory() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--animation-retarget-cache-dir="):
			return argument.trim_prefix("--animation-retarget-cache-dir=").rstrip("/")
	return RETARGET_CACHE_DIR

static func _retarget_cache_resource_path(cache_key: String) -> String:
	# Variant serialization preserves sampled Quaternion/Vector3 key values exactly.
	return _retarget_cache_directory().path_join(cache_key + ".animation-library.bin")

static func _retarget_cache_manifest_path(cache_key: String) -> String:
	return _retarget_cache_directory().path_join(cache_key + ".manifest.json")

static func _load_retarget_disk_cache(cache_key: String) -> AnimationLibrary:
	var manifest_path := _retarget_cache_manifest_path(cache_key)
	var resource_path := _retarget_cache_resource_path(cache_key)
	var manifest_file := FileAccess.open(manifest_path, FileAccess.READ)
	if manifest_file == null:
		return null
	var parsed: Variant = JSON.parse_string(manifest_file.get_as_text())
	manifest_file.close()
	if not (parsed is Dictionary):
		_invalidate_retarget_disk_cache(cache_key)
		return null
	var manifest: Dictionary = parsed
	if int(manifest.get("schema", -1)) != RETARGET_CACHE_SCHEMA or String(manifest.get("cache_key", "")) != cache_key or String(manifest.get("resource", "")) != resource_path.get_file():
		_invalidate_retarget_disk_cache(cache_key)
		return null
	if not FileAccess.file_exists(resource_path) or String(manifest.get("resource_sha256", "")) != FileAccess.get_sha256(resource_path):
		_invalidate_retarget_disk_cache(cache_key)
		return null
	var cached := read_retarget_library_snapshot(resource_path)
	if not _is_retargeted_library_complete(cached):
		_invalidate_retarget_disk_cache(cache_key)
		return null
	return cached

static func _is_retargeted_library_complete(candidate: AnimationLibrary) -> bool:
	if candidate == null:
		return false
	for source in ANIM_LIB_HELPER.CLIPS_CONFIG.values():
		for targets in source.values():
			for target in targets:
				var anim := candidate.get_animation(str(target.name))
				if anim == null or anim.get_track_count() == 0 or anim.loop_mode != int(target.loop):
					return false
	for alias_name in ALIAS_CLIPS:
		if candidate.get_animation(alias_name) == null:
			return false
	return true

static func _store_retarget_disk_cache(cache_key: String, library: AnimationLibrary) -> void:
	var cache_dir_abs := ProjectSettings.globalize_path(_retarget_cache_directory())
	if DirAccess.make_dir_recursive_absolute(cache_dir_abs) != OK:
		push_warning("Could not create Mixamo retarget cache directory: " + cache_dir_abs)
		return
	if not _acquire_retarget_cache_write_lock(cache_key):
		return
	var resource_path := _retarget_cache_resource_path(cache_key)
	var manifest_path := _retarget_cache_manifest_path(cache_key)
	if FileAccess.file_exists(resource_path) and _load_retarget_disk_cache(cache_key) != null:
		_release_retarget_cache_write_lock(cache_key)
		return
	_invalidate_retarget_disk_cache(cache_key)
	var nonce := "%d-%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	var temp_resource := resource_path + "." + nonce + ".tmp"
	if write_retarget_library_snapshot(library, temp_resource) != OK:
		push_warning("Could not save Mixamo retarget cache resource: " + temp_resource)
		_release_retarget_cache_write_lock(cache_key)
		return
	var resource_sha := FileAccess.get_sha256(temp_resource)
	var temp_manifest := manifest_path + "." + nonce + ".tmp"
	var manifest_file := FileAccess.open(temp_manifest, FileAccess.WRITE)
	if manifest_file == null:
		_remove_file(temp_resource)
		_release_retarget_cache_write_lock(cache_key)
		return
	manifest_file.store_string(JSON.stringify({
		"schema": RETARGET_CACHE_SCHEMA,
		"cache_key": cache_key,
		"resource": resource_path.get_file(),
		"resource_sha256": resource_sha
	}, "\t"))
	manifest_file.close()
	if not _promote_cache_file(temp_resource, resource_path):
		_remove_file(temp_manifest)
		_release_retarget_cache_write_lock(cache_key)
		return
	if not _promote_cache_file(temp_manifest, manifest_path):
		# Keep the published resource only when its matching manifest was promoted.
		_remove_file(temp_manifest)
		_release_retarget_cache_write_lock(cache_key)
		return
	retarget_cache_writes += 1
	_release_retarget_cache_write_lock(cache_key)

static func _retarget_cache_lock_path(cache_key: String) -> String:
	return _retarget_cache_directory().path_join(cache_key + ".lock")

static func _acquire_retarget_cache_write_lock(cache_key: String) -> bool:
	# Creating a directory is atomic on the supported filesystems. A competing process
	# keeps its completed in-memory result and will read the winner's manifest next launch.
	return DirAccess.make_dir_absolute(ProjectSettings.globalize_path(_retarget_cache_lock_path(cache_key))) == OK

static func _release_retarget_cache_write_lock(cache_key: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_retarget_cache_lock_path(cache_key)))

static func _promote_cache_file(temp_path: String, final_path: String) -> bool:
	if FileAccess.file_exists(final_path):
		return false
	var result := DirAccess.rename_absolute(ProjectSettings.globalize_path(temp_path), ProjectSettings.globalize_path(final_path))
	return result == OK

static func _invalidate_retarget_disk_cache(cache_key: String) -> void:
	var resource_path := _retarget_cache_resource_path(cache_key)
	var manifest_path := _retarget_cache_manifest_path(cache_key)
	var removed := false
	if FileAccess.file_exists(manifest_path):
		_remove_file(manifest_path)
		removed = true
	if FileAccess.file_exists(resource_path):
		_remove_file(resource_path)
		removed = true
	if removed:
		retarget_cache_invalidations += 1

static func _remove_file(path: String) -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

static func write_retarget_library_snapshot(library: AnimationLibrary, path: String) -> Error:
	if library == null:
		return ERR_INVALID_PARAMETER
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_buffer(var_to_bytes(_animation_library_snapshot_data(library)))
	file.close()
	return OK

static func read_retarget_library_snapshot(path: String) -> AnimationLibrary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var data: Variant = bytes_to_var(file.get_buffer(file.get_length()))
	file.close()
	return _animation_library_from_snapshot_data(data)

static func _animation_library_snapshot_data(library: AnimationLibrary) -> Dictionary:
	var clips: Array = []
	var names := library.get_animation_list()
	names.sort()
	for name in names:
		var animation := library.get_animation(name)
		if animation == null:
			continue
		var tracks: Array = []
		for track in range(animation.get_track_count()):
			var keys: Array = []
			for key in range(animation.track_get_key_count(track)):
				keys.append([animation.track_get_key_time(track, key), _snapshot_animation_value(animation.track_get_key_value(track, key)), animation.track_get_key_transition(track, key)])
			tracks.append([animation.track_get_type(track), animation.track_get_path(track), animation.track_get_interpolation_type(track), keys])
		clips.append([name, animation.length, animation.loop_mode, tracks])
	return {"schema": RETARGET_CACHE_SCHEMA, "clips": clips}

static func _animation_library_from_snapshot_data(data: Variant) -> AnimationLibrary:
	if not (data is Dictionary):
		return null
	var snapshot: Dictionary = data
	if int(snapshot.get("schema", -1)) != RETARGET_CACHE_SCHEMA or not (snapshot.get("clips", []) is Array):
		return null
	var library := AnimationLibrary.new()
	for clip_data in snapshot["clips"]:
		if not (clip_data is Array) or clip_data.size() != 4:
			return null
		var animation := Animation.new()
		animation.length = float(clip_data[1])
		animation.loop_mode = int(clip_data[2])
		for track_data in clip_data[3]:
			if not (track_data is Array) or track_data.size() != 4:
				return null
			var track := animation.add_track(int(track_data[0]))
			animation.track_set_path(track, track_data[1])
			animation.track_set_interpolation_type(track, int(track_data[2]))
			for key_data in track_data[3]:
				if not (key_data is Array) or key_data.size() != 3:
					return null
				animation.track_insert_key(track, float(key_data[0]), _restore_animation_value(key_data[1]), float(key_data[2]))
		library.add_animation(String(clip_data[0]), animation)
	return library

static func _snapshot_animation_value(value: Variant) -> Variant:
	# Variant's built-in Quaternion/Vector3 binary encoding is float32. Store components
	# as scalar floats so an offline cache reconstructs the exact runtime keys.
	if value is Quaternion:
		var quaternion := value as Quaternion
		return {"type": "Quaternion64", "value": [quaternion.x, quaternion.y, quaternion.z, quaternion.w]}
	if value is Vector3:
		var vector := value as Vector3
		return {"type": "Vector364", "value": [vector.x, vector.y, vector.z]}
	return value

static func _restore_animation_value(value: Variant) -> Variant:
	if value is Dictionary:
		var encoded: Dictionary = value
		var components: Variant = encoded.get("value", [])
		if components is Array:
			if encoded.get("type", "") == "Quaternion64" and components.size() == 4:
				return Quaternion(float(components[0]), float(components[1]), float(components[2]), float(components[3]))
			if encoded.get("type", "") == "Vector364" and components.size() == 3:
				return Vector3(float(components[0]), float(components[1]), float(components[2]))
	return value

static func _retarget_single_clip(
	src_anim: Animation,
	skel_rel_path: String,
	s_order: Array,
	s_parent: Dictionary,
	s_local_rest: Dictionary,
	s_global_rest_inv: Dictionary,
	t_order: Array[int],
	t_parent: Array[int],
	t_bone_name: Array[String],
	t_mapped_src: Array[String],
	t_local_rest_basis: Array[Basis],
	t_global_rest_basis: Array[Basis],
	hips_t_idx: int,
	hips_s_rest_pos: Vector3,
	hips_t_rest_pos: Vector3,
	hip_scale: float,
	r_align: Basis,
	r_align_inv: Basis,
	target_arm_directions: Dictionary
) -> Animation:
	var rot_tracks: Dictionary = {}
	var pos_tracks: Dictionary = {}
	for trk in range(src_anim.get_track_count()):
		var path := src_anim.track_get_path(trk)
		if path.get_subname_count() == 0:
			continue
		var b_s := String(path.get_subname(0))
		var t_type := src_anim.track_get_type(trk)
		if t_type == Animation.TYPE_ROTATION_3D:
			rot_tracks[b_s] = trk
		elif t_type == Animation.TYPE_POSITION_3D:
			pos_tracks[b_s] = trk

	var dst_anim := Animation.new()
	dst_anim.length = src_anim.length
	dst_anim.loop_mode = src_anim.loop_mode

	var mapped_t_indices: Array[int] = []
	var rot_track_for_t: Dictionary = {}
	for b_t in t_order:
		if t_mapped_src[b_t] != "":
			mapped_t_indices.append(b_t)
			var trk_idx := dst_anim.add_track(Animation.TYPE_ROTATION_3D)
			dst_anim.track_set_path(trk_idx, NodePath(skel_rel_path + ":" + t_bone_name[b_t]))
			dst_anim.track_set_interpolation_type(trk_idx, Animation.INTERPOLATION_LINEAR)
			rot_track_for_t[b_t] = trk_idx

	var hips_pos_trk := -1
	if hips_t_idx != -1 and pos_tracks.has("hips"):
		hips_pos_trk = dst_anim.add_track(Animation.TYPE_POSITION_3D)
		dst_anim.track_set_path(hips_pos_trk, NodePath(skel_rel_path + ":" + t_bone_name[hips_t_idx]))
		dst_anim.track_set_interpolation_type(hips_pos_trk, Animation.INTERPOLATION_LINEAR)

	var sample_times: Array[float] = []
	var step := 1.0 / RETARGET_SAMPLE_FPS
	var t_cur := 0.0
	while t_cur < src_anim.length - 0.0005:
		sample_times.append(t_cur)
		t_cur += step
	sample_times.append(src_anim.length)

	var g_s_anim: Dictionary = {}
	var dw_t_map: Dictionary = {}
	var arm_corrections: Dictionary = {}
	var g_t_anim: Array[Basis] = []
	g_t_anim.resize(t_bone_name.size())

	var hips_src_pos_trk: int = pos_tracks.get("hips", -1)

	for t_sec in sample_times:
		arm_corrections.clear()
		for b_s in s_order:
			var l_basis: Basis
			if rot_tracks.has(b_s):
				var q: Quaternion = src_anim.rotation_track_interpolate(rot_tracks[b_s], t_sec)
				l_basis = Basis(q)
			else:
				l_basis = (s_local_rest[b_s] as Transform3D).basis

			var p_s: String = s_parent[b_s]
			var g_basis: Basis = (g_s_anim[p_s] as Basis) * l_basis if (p_s != "" and g_s_anim.has(p_s)) else l_basis
			g_s_anim[b_s] = g_basis

			var dw_s: Basis = g_basis * (s_global_rest_inv[b_s] as Basis)
			dw_t_map[b_s] = r_align_inv * dw_s * r_align

		var chest_delta: Basis = (g_s_anim["chest"] as Basis) * (s_global_rest_inv["chest"] as Basis)
		for b_t in t_order:
			var p_t := t_parent[b_t]
			var p_global: Basis = g_t_anim[p_t] if p_t != -1 else Basis.IDENTITY
			var src_name := t_mapped_src[b_t]
			if src_name != "" and dw_t_map.has(src_name):
				var target_global: Basis = (dw_t_map[src_name] as Basis) * t_global_rest_basis[b_t]
				if target_arm_directions.has(b_t):
					var arm_direction: Vector3 = target_global * (target_arm_directions[b_t] as Vector3)
					arm_corrections[src_name] = _arm_silhouette_correction(arm_direction, chest_delta, r_align, src_name == "upperarm.l")
				var chain: String = ARM_CHAIN_ROOT.get(src_name, "")
				if arm_corrections.has(chain):
					target_global = (arm_corrections[chain] as Basis) * target_global
				g_t_anim[b_t] = target_global
				var local_anim: Basis = (p_global.inverse() * target_global).orthonormalized()
				dst_anim.rotation_track_insert_key(rot_track_for_t[b_t], t_sec, local_anim.get_rotation_quaternion())
			else:
				g_t_anim[b_t] = p_global * t_local_rest_basis[b_t]

		if hips_pos_trk != -1 and hips_src_pos_trk != -1:
			var p_s_anim: Vector3 = src_anim.position_track_interpolate(hips_src_pos_trk, t_sec)
			var delta_s := p_s_anim - hips_s_rest_pos
			var delta_t := (r_align_inv * delta_s) * hip_scale
			dst_anim.position_track_insert_key(hips_pos_trk, t_sec, hips_t_rest_pos + delta_t)

	return dst_anim

static func _arm_silhouette_correction(direction: Vector3, chest_delta: Basis, alignment: Basis, left: bool) -> Basis:
	var body_direction := (chest_delta.inverse() * alignment * direction).normalized()
	var side := 1.0 if left else -1.0
	var outward := side * body_direction.x
	var downward := -body_direction.y
	if outward <= 0.0 or downward <= 0.0:
		return Basis.IDENTITY
	var angle := atan2(outward, downward)
	var weight := smoothstep(0.0, 0.25, downward)
	var correction := Basis(Vector3.BACK, -side * angle * (1.0 - ARM_LATERAL_SWING_RATIO) * weight)
	return alignment.inverse() * chest_delta * correction * chest_delta.inverse() * alignment

static func _apply_chibi_figurine_materials(model: Node3D, resolved_path: String) -> void:
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		if mesh_node.mesh == null or mesh_node.material_override != null:
			continue
		for surface in range(mesh_node.mesh.get_surface_count()):
			var source := mesh_node.get_active_material(surface) as BaseMaterial3D
			if source == null or source.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				continue
			if source.shading_mode != BaseMaterial3D.SHADING_MODE_PER_PIXEL or source.emission_enabled:
				continue
			# Keep authored specialty surfaces on the source material.
			if source.cull_mode == BaseMaterial3D.CULL_FRONT or source.normal_enabled or source.next_pass != null:
				continue
			var key := "%s::%s::%d" % [resolved_path, str(model.get_path_to(mesh_node)), surface]
			var finish := _figurine_material_cache.get(key) as ShaderMaterial
			if finish == null:
				finish = ShaderMaterial.new()
				finish.shader = CHIBI_DOUBLE_SIDED if source.cull_mode == BaseMaterial3D.CULL_DISABLED else CHIBI_SHADER
				if source.albedo_texture != null:
					finish.set_shader_parameter("albedo_texture", source.albedo_texture)
				finish.set_shader_parameter("albedo_tint", source.albedo_color)
				finish.set_shader_parameter("use_vertex_color", source.vertex_color_use_as_albedo)
				finish.set_shader_parameter("uv_scale", Vector2(source.uv1_scale.x, source.uv1_scale.y))
				finish.set_shader_parameter("uv_offset", Vector2(source.uv1_offset.x, source.uv1_offset.y))
				finish.set_shader_parameter("surface_roughness", clampf(source.roughness, 0.77, 0.95))
				_figurine_material_cache[key] = finish
			mesh_node.set_surface_override_material(surface, finish)

static func _apply_kaykit_three_head_proportion(model: Node3D, skel: Skeleton3D, resolved_path: String) -> void:
	var head_idx := skel.find_bone("head")
	if head_idx == -1:
		return
	var neck_pivot: Vector3 = skel.get_bone_global_rest(head_idx).origin
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_node := child as MeshInstance3D
		if mesh_node == null or not (mesh_node.mesh is ArrayMesh):
			continue
		var n := String(mesh_node.name)
		if not (n.ends_with("_Head") or n.ends_with("_Hat") or n.ends_with("_BearHat") or n.ends_with("_Helmet") or n.ends_with("_HelmetVisor") or n.ends_with("_Mask")):
			continue
		var cache_key := resolved_path + "::" + n
		if _scaled_head_mesh_cache.has(cache_key):
			mesh_node.mesh = _scaled_head_mesh_cache[cache_key]
			continue
		var src_mesh := mesh_node.mesh as ArrayMesh
		var dst_mesh := ArrayMesh.new()
		for s in range(src_mesh.get_surface_count()):
			var arrays := src_mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			for i in range(verts.size()):
				verts[i] = neck_pivot + (verts[i] - neck_pivot) * KAYKIT_THREE_HEAD_SCALE
			arrays[Mesh.ARRAY_VERTEX] = verts
			dst_mesh.add_surface_from_arrays(src_mesh.surface_get_primitive_type(s), arrays)
			dst_mesh.surface_set_material(s, src_mesh.surface_get_material(s))
		_scaled_head_mesh_cache[cache_key] = dst_mesh
		mesh_node.mesh = dst_mesh

static func _visual_bounds(node: Node, parent_transform: Transform3D) -> Variant:
	var transform := parent_transform
	if node is Node3D:
		transform = parent_transform * node.transform
	var bounds: Variant = null
	if node is MeshInstance3D and node.mesh != null:
		bounds = transform * node.get_aabb()
	for child in node.get_children():
		var child_bounds: Variant = _visual_bounds(child, transform)
		if child_bounds != null:
			bounds = child_bounds if bounds == null else bounds.merge(child_bounds)
	return bounds

static func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null

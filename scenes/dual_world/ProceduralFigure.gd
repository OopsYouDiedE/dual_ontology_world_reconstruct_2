extends Node3D
## 程序化低多边形人物（自 web 版 buildCharacter 迁入）：关节层级 + 姿态库，原点在脚底、正面朝 +z。
## 姿态与限位来自 dual_world.json 的 RIG_SPEC；高度与体型取自人物 look 参数。
## 若传入 glb_path 且文件存在，则改用 GLB 真实小人外观（UserModels/model_XX.glb，Mixamo 骨骼）；
## GLB 模式下 set_pose 会驱动骨骼动画（idle/walk/talk/argue/point/think/sit），失败时回退到程序化色块。

var actor: Dictionary = {}
var pose := "stand"
var poses: Dictionary = {}
var _t := 0.0
var _joints := {}
var _body: Node3D
var _base_y := 0.0
var use_glb := true
const ImportedCharacter := preload("res://scenes/components/characters/ImportedCharacter.gd")
var _glb_player: AnimationPlayer = null
var _glb_pose := "stand"


## 人物 id → UserModels GLB（与 character_art.dv 的职业映射对齐）
const GLB_BY_ACTOR := {
	"detective": "model_06", "quer": "model_01", "lucian": "model_10", "ruan": "model_17",
	"shen": "model_07", "huo": "model_04", "gu": "model_08", "ward": "model_14",
	"su": "model_16", "selma": "model_05", "elena": "model_11", "moran": "model_12",
	"veronica": "model_02", "bertrand": "model_03", "margaret": "model_13", "mora": "model_15",
	"demon": "model_09",
}


static func glb_path_for(actor_id: String) -> String:
	if not GLB_BY_ACTOR.has(actor_id): return ""
	return "res://assets/characters/UserModels/%s.glb" % str(GLB_BY_ACTOR[actor_id])


func setup(a: Dictionary, rig_poses: Dictionary, glb_path := "") -> void:
	actor = a
	poses = rig_poses
	if glb_path == "":
		glb_path = glb_path_for(str(a.get("id", "")))
	var look: Dictionary = a.look
	var height: float = look.height
	var build: float = look.build
	_body = Node3D.new()
	add_child(_body)
	if use_glb and glb_path != "" and ResourceLoader.exists(glb_path):
		if _attach_glb(glb_path, height):
			return
		# GLB 加载失败：回退到程序化色块（下方继续构建）
	var s := height / 1.38  # 原始骨架约 1.38m
	_body.scale = Vector3(s, s, s)
	var skin := Color(look.skin)
	var coat := Color(look.coat)
	var accent := Color(look.accent)
	var hair := Color(look.hair)
	var hip := 0.075 * build
	var shoulder := 0.20 * build
	var pelvis := Node3D.new()
	pelvis.position = Vector3(0, 0.78, 0)
	_body.add_child(pelvis)
	_joints["pelvis"] = pelvis
	pelvis.add_child(_part(Vector3(0.30 * build, 0.16, 0.18), coat.darkened(0.25), Vector3(0, 0.02, 0)))
	var chest := Node3D.new()
	chest.position = Vector3(0, 0.28, 0)
	pelvis.add_child(chest)
	chest.add_child(_part(Vector3(0.38 * build, 0.52, 0.22), coat, Vector3(0, 0.0, 0)))
	chest.add_child(_part(Vector3(0.40 * build, 0.04, 0.24), accent, Vector3(0, -0.12, 0)))  # 腰带
	var neck := Node3D.new()
	neck.position = Vector3(0, 0.27, 0)
	chest.add_child(neck)
	var head := Node3D.new()
	head.position = Vector3(0, 0.12, 0)
	neck.add_child(head)
	_joints["head"] = head
	head.add_child(_ball(0.14, skin, Vector3(0, 0.06, 0)))
	_hair(head, str(look.hairStyle), hair)
	_hat(head, str(look.hat), accent)
	for sx in [-1, 1]:
		var side := "L" if sx > 0 else "R"
		var arm := Node3D.new()
		arm.position = Vector3(sx * shoulder, 0.22, 0)
		chest.add_child(arm)
		_joints["arm" + side] = arm
		arm.add_child(_part(Vector3(0.085, 0.30, 0.085), coat, Vector3(0, -0.14, 0)))
		var fore := Node3D.new()
		fore.position = Vector3(0, -0.28, 0)
		arm.add_child(fore)
		fore.add_child(_part(Vector3(0.07, 0.26, 0.07), coat.lightened(0.05), Vector3(0, -0.12, 0)))
		fore.add_child(_ball(0.045, skin, Vector3(0, -0.28, 0)))
		var leg := Node3D.new()
		leg.position = Vector3(sx * hip, -0.04, 0)
		pelvis.add_child(leg)
		_joints["leg" + side] = leg
		leg.add_child(_part(Vector3(0.11, 0.38, 0.11), coat.darkened(0.35), Vector3(0, -0.19, 0)))
		var shin := Node3D.new()
		shin.position = Vector3(0, -0.38, 0)
		leg.add_child(shin)
		shin.add_child(_part(Vector3(0.09, 0.34, 0.09), coat.darkened(0.45), Vector3(0, -0.17, 0)))
		shin.add_child(_part(Vector3(0.11, 0.06, 0.2), Color("#2a2018"), Vector3(0, -0.36, 0.04)))
	_base_y = 0.0


## 真实小人：复用项目内 ImportedCharacter 管线（Mixamo retarget / chibi材质 / 身高归一），
## 避免另写一套骨骼轨道造成姿态不一致。返回 true 表示 GLB 已接管外观。
func _attach_glb(glb_path: String, height: float) -> bool:
	if not ImportedCharacter.attach(_body, glb_path, height, -90.0, str(actor.get("id", ""))):
		return false
	_glb_player = _body.get_meta("animation_player", null) as AnimationPlayer
	_build_gestures()
	# 即使某个角色的骨骼动画缺失，也保留真实 GLB 外观，不叠加程序化色块。
	return true


func _build_gestures() -> void:
	if _glb_player == null or not _glb_player.has_animation("idle"): return
	var skeleton: Skeleton3D = _body.get_meta("skeleton", null)
	if skeleton == null: return
	var model_basis := Basis.IDENTITY
	var ancestor: Node3D = skeleton
	while ancestor != _body and ancestor != null:
		model_basis = ancestor.basis * model_basis
		ancestor = ancestor.get_parent() as Node3D
	model_basis = model_basis.orthonormalized()
	var bone_map := {"armL": "LeftArm", "armR": "RightArm", "head": "Head"}
	var library := AnimationLibrary.new()
	var standing: Dictionary = poses.get("stand", {})
	for gesture in ["talk", "argue", "point", "think"]:
		var spec: Dictionary = poses.get(gesture, {})
		if spec.is_empty(): continue
		var base_clip := "talk" if gesture != "think" and _glb_player.has_animation("talk") else "idle"
		var animation := _glb_player.get_animation(base_clip).duplicate(true) as Animation
		for joint in bone_map:
			var bone := ImportedCharacter._find_mixamo_bone(skeleton, str(bone_map[joint]))
			if bone < 0: continue
			var angles: Array = spec.get(joint, [0, 0, 0])
			var neutral: Array = standing.get(joint, [0, 0, 0])
			var delta := Vector3(deg_to_rad(angles[0] - neutral[0]), deg_to_rad(angles[1] - neutral[1]), deg_to_rad(angles[2] - neutral[2]))
			var parent := skeleton.get_bone_parent(bone)
			var parent_basis := skeleton.get_bone_global_rest(parent).basis if parent >= 0 else Basis.IDENTITY
			var frame := (model_basis * parent_basis).orthonormalized()
			var correction := frame.inverse() * Basis.from_euler(delta) * frame
			for track in animation.get_track_count():
				var path := animation.track_get_path(track)
				if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D or path.get_subname_count() == 0: continue
				if str(path.get_subname(0)) != skeleton.get_bone_name(bone): continue
				for key in animation.track_get_key_count(track):
					var rotation: Quaternion = animation.track_get_key_value(track, key)
					animation.track_set_key_value(track, key, (correction * Basis(rotation)).get_rotation_quaternion())
		library.add_animation(gesture, animation)
	_glb_player.add_animation_library("gestures", library)


func _aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		var b := mi.global_transform * mi.get_aabb() if mi.is_inside_tree() else mi.transform * mi.get_aabb()
		out = b if first else out.merge(b)
		first = false
	return out


func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.9
	return m


func _part(size: Vector3, c: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _mat(c)
	mi.position = pos
	return mi


func _ball(r: float, c: Color, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	mi.material_override = _mat(c)
	mi.position = pos
	return mi


func _hair(head: Node3D, style: String, c: Color) -> void:
	head.add_child(_ball(0.152, c, Vector3(0, 0.10, -0.02)))
	match style:
		"buns":
			head.add_child(_ball(0.06, c, Vector3(0.12, 0.2, 0)))
			head.add_child(_ball(0.06, c, Vector3(-0.12, 0.2, 0)))
		"bun": head.add_child(_ball(0.07, c, Vector3(0, 0.24, -0.03)))
		"curly":
			for i in 6:
				var a := TAU * i / 6.0
				head.add_child(_ball(0.06, c, Vector3(cos(a) * 0.13, 0.12, sin(a) * 0.13 - 0.02)))


func _hat(head: Node3D, hat: String, accent: Color) -> void:
	match hat:
		"fedora":
			var brim := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.22
			cm.bottom_radius = 0.22
			cm.height = 0.015
			brim.mesh = cm
			brim.material_override = _mat(Color("#3a3028"))
			brim.position = Vector3(0, 0.2, 0)
			head.add_child(brim)
			head.add_child(_part(Vector3(0.2, 0.12, 0.2), Color("#4a3c30"), Vector3(0, 0.27, 0)))
			head.add_child(_part(Vector3(0.205, 0.03, 0.205), accent, Vector3(0, 0.23, 0)))
		"chef": head.add_child(_part(Vector3(0.2, 0.2, 0.2), Color("#f2efe6"), Vector3(0, 0.3, 0)))


const POSE_CLIPS := {
	"stand": [["idle"], 1.0],
	"think": [["gestures/think", "idle"], 1.0],
	"walk": [["walk"], 1.0],
	"run": [["run"], 1.0],
	"sit": [["sit_idle"], 1.0],
	"lie": [["lie_idle"], 1.0],
	"lie_stand_up": [["lie_stand_up"], 1.0],
	"talk": [["gestures/talk", "talk", "interact"], 0.85],
	"argue": [["gestures/argue", "talk", "interact"], 1.35],
	"point": [["gestures/point", "talk", "interact"], 0.7],
	"tend": [["talk", "interact"], 0.6],
	"work": [["work_loop", "work", "operate"], 1.0],
	"wave": [["wave"], 1.0],
}


func clip_for_pose(p: String) -> String:
	if _glb_player == null: return ""
	var entry: Array = POSE_CLIPS.get(p, POSE_CLIPS["stand"])
	for candidate in entry[0]:
		if _glb_player.has_animation(candidate): return str(candidate)
	return "idle" if _glb_player.has_animation("idle") else ""


func pose_length(p: String) -> float:
	var clip := clip_for_pose(p)
	if clip == "": return 0.0
	var entry: Array = POSE_CLIPS.get(p, POSE_CLIPS["stand"])
	return _glb_player.get_animation(clip).length / maxf(float(entry[1]), 0.05)


func measure_pose(p: String, ratio := 1.0) -> Dictionary:
	if _glb_player == null or not is_inside_tree(): return {}
	var skeleton := _body.get_meta("skeleton", null) as Skeleton3D
	var clip := clip_for_pose(p)
	if skeleton == null or clip == "": return {}
	var previous_clip := _glb_player.assigned_animation
	var previous_time := _glb_player.current_animation_position
	var was_playing := _glb_player.is_playing()
	_glb_player.play(clip, 0.0)
	_glb_player.seek(_glb_player.get_animation(clip).length * clampf(ratio, 0.0, 1.0), true)
	skeleton.force_update_all_bone_transforms()
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var hips := Vector3.ZERO
	var head := Vector3.ZERO
	for bone_index in skeleton.get_bone_count():
		var origin := to_local(skeleton.global_transform * skeleton.get_bone_global_pose(bone_index).origin)
		minimum = minimum.min(origin)
		maximum = maximum.max(origin)
		var bone_name := skeleton.get_bone_name(bone_index)
		if bone_name.ends_with("Hips") or bone_name == "hips": hips = origin
		elif bone_name.ends_with("Head") or bone_name == "head": head = origin
	if previous_clip != "":
		_glb_player.play(previous_clip, 0.0)
		_glb_player.seek(previous_time, true)
		if not was_playing: _glb_player.pause()
	skeleton.force_update_all_bone_transforms()
	return {
		"hips_y": hips.y, "min_y": minimum.y, "max_y": maximum.y,
		"hips": Vector2(hips.x, hips.z), "head": Vector2(head.x, head.z),
		"center": Vector2((minimum.x + maximum.x) * 0.5, (minimum.z + maximum.z) * 0.5),
	}


func set_pose(p: String) -> void:
	var previous := pose
	pose = p if poses.has(p) or POSE_CLIPS.has(p) else "stand"
	if _glb_player == null: return
	_glb_pose = pose
	var clip := clip_for_pose(pose)
	if clip == "": return
	var one_shot := _glb_player.get_animation(clip).loop_mode == Animation.LOOP_NONE
	if _glb_player.current_animation != clip and not (one_shot and previous == pose):
		_glb_player.play(clip)
	_glb_player.speed_scale = float((POSE_CLIPS.get(pose, POSE_CLIPS["stand"]) as Array)[1])


func pose_duration(p: String) -> float:
	return pose_length(p)


const WakeModifier := preload("res://scenes/dual_world/WakeModifier3D.gd")
var _wake_mod: SkeletonModifier3D = null


func wake_rig() -> SkeletonModifier3D:
	if _wake_mod != null: return _wake_mod
	var skeleton := _body.get_meta("skeleton", null) as Skeleton3D if _body != null else null
	if skeleton == null: return null
	var modifier := WakeModifier.new()
	modifier.name = "WakeModifier3D"
	skeleton.add_child(modifier)
	if not modifier.setup(skeleton):
		modifier.queue_free()
		return null
	_wake_mod = modifier
	return _wake_mod


func _process(delta: float) -> void:
	_t += delta
	if _glb_player != null:
		return  # ImportedCharacter 的真实骨骼动画由 AnimationPlayer 驱动
	if _joints.is_empty(): return
	var spec: Dictionary = poses.get(pose, poses.get("stand", {}))
	var swing := sin(_t * 6.0) * 0.5 if pose == "walk" else 0.0
	var breathe := sin(_t * 1.6) * 0.012
	_apply("armL", spec.get("armL", [0, 0, 8]), swing * 0.7)
	_apply("armR", spec.get("armR", [0, 0, -8]), -swing * 0.7)
	_apply("legL", spec.get("legL", [0, 0, 0]), -swing * 0.8)
	_apply("legR", spec.get("legR", [0, 0, 0]), swing * 0.8)
	_apply("head", spec.get("head", [0, 0, 0]), 0.0)
	var pelvis: Node3D = _joints["pelvis"]
	pelvis.position.y = 0.78 + float(spec.get("body", 0.0)) + breathe


func _apply(joint: String, deg: Array, extra_rad: float) -> void:
	var j: Node3D = _joints.get(joint)
	if j == null: return
	var target := Vector3(deg_to_rad(deg[0]) + extra_rad, deg_to_rad(deg[1]), deg_to_rad(deg[2]))
	j.rotation = j.rotation.lerp(target, 0.18)

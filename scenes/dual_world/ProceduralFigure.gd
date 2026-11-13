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
	# 即使某个角色的骨骼动画缺失，也保留真实 GLB 外观，不叠加程序化色块。
	return true


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


func set_pose(p: String) -> void:
	pose = p if poses.has(p) or p in ["lie", "run", "lie_stand_up"] else "stand"
	if _glb_player != null:
		_glb_pose = pose
		var clips := {
			"stand": "idle", "walk": "walk", "run": "run", "sit": "sit_idle", "lie": "lie_idle",
			"lie_stand_up": "lie_stand_up", "talk": "interact", "argue": "interact", "point": "interact", "think": "idle",
			"work": "operate", "tend": "interact"
		}
		var clip: String = str(clips.get(pose, "idle"))
		if not _glb_player.has_animation(clip): clip = "idle"
		if _glb_player.current_animation != clip: _glb_player.play(clip)


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

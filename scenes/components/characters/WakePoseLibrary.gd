extends RefCounted
## 侦探起床专用动作库（Mixamo 骨架直接摆姿，不经 KayKit 重定向）。
##
## 为什么要单独做：KayKit 的 Lie_Idle 是「侧卧蜷缩」，重定向到 Q 版小人（头占 28% 身高、躯干仅 0.19m）后
## 身体缩成一团、脸朝下；Lie_StandUp 也以侧卧为起点，和「仰卧 → 撑起上身 → 下床」的表演接不上。
##
## 做法：从骨骼静止姿态求出「前 / 上 / 左」，在角色坐标系（X 前、Y 上、Z 右）里按关节给出绝对旋转，
## 再乘回静止姿态得到各骨骼全局朝向，逐骨求局部旋转，烘焙成 Animation。
##   wake/lie      仰卧呼吸（循环）
##   wake/getup    仰卧撑坐 → 转身腿垂床沿 → 前倾起身 → 站定回身（腿向角色左侧下床）
##   wake/getup_r  同上，向角色右侧下床
## 骨骼命名按 Mixamo（mixamorig_ / mixamorig: / 无前缀）。

const ImportedCharacter := preload("res://scenes/components/characters/ImportedCharacter.gd")

const FPS := 24.0
const LIE_HIPS_Y := 0.10  # 仰卧时髋骨离床面高度（骨架原始单位，模型缩放前）
const LIE_LENGTH := 4.0
const GETUP_TIMES := [0.0, 0.75, 1.4, 2.0, 2.55, 3.1]
const GETUP_LENGTH := 3.1
const GETUP_TURN_START := 0.3   # 开始转身 / 向床沿挪动
const GETUP_EDGE := 1.4         # 坐到床沿
const GETUP_STAND_END := 2.55   # 站直

## 角色坐标系中的关节参数（单位：度；hy 为髋骨高度，负数表示用静止高度）
const POSE_LIE := {"yaw": 0.0, "hips": 90.0, "torso": 90.0, "head": 76.0, "thigh": 90.0, "knee": 0.0, "foot": 0.0, "arm": 78.0, "hy": LIE_HIPS_Y}
const POSE_BREATH := {"yaw": 0.0, "hips": 90.0, "torso": 87.0, "head": 76.0, "thigh": 90.0, "knee": 0.0, "foot": 0.0, "arm": 76.0, "hy": LIE_HIPS_Y}
const GETUP_POSES := [
	{"yaw": 0.0, "hips": 90.0, "torso": 24.0, "head": 10.0, "thigh": 90.0, "knee": 0.0, "foot": 0.0, "arm": 80.0, "hy": LIE_HIPS_Y},
	{"yaw": 45.0, "hips": 72.0, "torso": 14.0, "head": 4.0, "thigh": 80.0, "knee": 10.0, "foot": 0.0, "arm": 80.0, "hy": LIE_HIPS_Y},
	{"yaw": 90.0, "hips": 0.0, "torso": -10.0, "head": -14.0, "thigh": 90.0, "knee": 90.0, "foot": 0.0, "arm": 78.0, "hy": LIE_HIPS_Y},
	{"yaw": 90.0, "hips": -12.0, "torso": -28.0, "head": -10.0, "thigh": 45.0, "knee": 55.0, "foot": 0.0, "arm": 70.0, "hy": 0.28},
	{"yaw": 90.0, "hips": 0.0, "torso": 0.0, "head": 0.0, "thigh": 0.0, "knee": 0.0, "foot": 0.0, "arm": 84.0, "hy": -1.0},
	{"yaw": 0.0, "hips": 0.0, "torso": 0.0, "head": 0.0, "thigh": 0.0, "knee": 0.0, "foot": 0.0, "arm": 84.0, "hy": -1.0},
]


static func _rx(d: float) -> Basis: return Basis(Vector3.RIGHT, deg_to_rad(d))
static func _ry(d: float) -> Basis: return Basis(Vector3.UP, deg_to_rad(d))
static func _rz(d: float) -> Basis: return Basis(Vector3.BACK, deg_to_rad(d))


## 一个姿态参数 → { 骨骼短名: 角色坐标系绝对旋转 }
static func _joint_rotations(p: Dictionary, side: float) -> Dictionary:
	var yaw := _ry(float(p.yaw) * side)
	var hips: float = p.hips
	var torso: float = p.torso
	var head: float = p.head
	var thigh: float = p.thigh
	var shin: float = thigh - float(p.knee)
	var out := {}
	out["Hips"] = yaw * _rz(hips)
	out["Spine"] = yaw * _rz(lerpf(hips, torso, 0.35))
	out["Spine1"] = yaw * _rz(lerpf(hips, torso, 0.7))
	out["Spine2"] = yaw * _rz(torso)
	out["Neck"] = yaw * _rz(lerpf(torso, head, 0.5))
	out["Head"] = yaw * _rz(head)
	out["LeftArm"] = yaw * _rz(torso) * _rx(-float(p.arm))
	out["RightArm"] = yaw * _rz(torso) * _rx(float(p.arm))
	for side_name in ["Left", "Right"]:
		out[side_name + "UpLeg"] = yaw * _rz(thigh)
		out[side_name + "Leg"] = yaw * _rz(shin)
		out[side_name + "Foot"] = yaw * _rz(shin + float(p.foot))
	return out


static func _short(skeleton: Skeleton3D, bone: int) -> String:
	return ImportedCharacter._strip_mixamo_prefix(skeleton.get_bone_name(bone))


## 每根骨骼取它自己或最近祖先在姿态表里的旋转；没有就是单位旋转。
static func _resolve(skeleton: Skeleton3D, rotations: Dictionary, frame: Basis) -> Array:
	var out: Array = []
	for bone in skeleton.get_bone_count():
		var cursor := bone
		var found := Basis.IDENTITY
		while cursor != -1:
			var key := _short(skeleton, cursor)
			if rotations.has(key):
				found = frame * (rotations[key] as Basis) * frame.inverse()
				break
			cursor = skeleton.get_bone_parent(cursor)
		out.append(found.get_rotation_quaternion())
	return out


## 从骨骼静止姿态求角色坐标系 → 骨架空间的基：X 前、Y 上、Z 右。
static func character_frame(skeleton: Skeleton3D) -> Basis:
	var head := ImportedCharacter._find_mixamo_bone(skeleton, "Head")
	var hips := ImportedCharacter._find_mixamo_bone(skeleton, "Hips")
	var left := ImportedCharacter._find_mixamo_bone(skeleton, "LeftArm")
	var right := ImportedCharacter._find_mixamo_bone(skeleton, "RightArm")
	if head < 0 or hips < 0 or left < 0 or right < 0: return Basis.IDENTITY
	var up := (skeleton.get_bone_global_rest(head).origin - skeleton.get_bone_global_rest(hips).origin).normalized()
	var lateral_left := (skeleton.get_bone_global_rest(left).origin - skeleton.get_bone_global_rest(right).origin)
	lateral_left = (lateral_left - up * lateral_left.dot(up)).normalized()
	var forward := lateral_left.cross(up).normalized()
	return Basis(forward, up, -lateral_left)


static func build(skeleton: Skeleton3D, rel_path: String) -> AnimationLibrary:
	var frame := character_frame(skeleton)
	if frame == Basis.IDENTITY: return null
	var lib := AnimationLibrary.new()
	lib.add_animation("lie", _bake(skeleton, rel_path, frame, [0.0, LIE_LENGTH * 0.5, LIE_LENGTH], [POSE_LIE, POSE_BREATH, POSE_LIE], 1.0, LIE_LENGTH, true))
	lib.add_animation("getup", _bake(skeleton, rel_path, frame, GETUP_TIMES, GETUP_POSES, 1.0, GETUP_LENGTH, false))
	lib.add_animation("getup_r", _bake(skeleton, rel_path, frame, GETUP_TIMES, GETUP_POSES, -1.0, GETUP_LENGTH, false))
	return lib


static func _bake(skeleton: Skeleton3D, rel_path: String, frame: Basis, times: Array, poses: Array, side: float, length: float, loop: bool) -> Animation:
	var count := skeleton.get_bone_count()
	var hips := ImportedCharacter._find_mixamo_bone(skeleton, "Hips")
	var up_dir := frame.y
	var hips_rest := skeleton.get_bone_rest(hips).origin
	var rest_height := hips_rest.dot(up_dir)

	# 每个关键姿态：逐骨绝对旋转（四元数）与髋高
	var key_q: Array = []
	var key_h: Array = []
	for pose in poses:
		key_q.append(_resolve(skeleton, _joint_rotations(pose, side), frame))
		var hy := float(pose.hy)
		key_h.append(rest_height if hy < 0.0 else hy)

	var order: Array[int] = []
	var seen := {}
	while order.size() < count:
		var progressed := false
		for i in count:
			if seen.has(i): continue
			var p := skeleton.get_bone_parent(i)
			if p == -1 or seen.has(p):
				seen[i] = true
				order.append(i)
				progressed = true
		if not progressed: break

	var anim := Animation.new()
	anim.length = length
	anim.loop_mode = Animation.LOOP_LINEAR if loop else Animation.LOOP_NONE
	var rot_track: Array[int] = []
	rot_track.resize(count)
	for i in count:
		var t := anim.add_track(Animation.TYPE_ROTATION_3D)
		anim.track_set_path(t, NodePath(rel_path + ":" + skeleton.get_bone_name(i)))
		anim.track_set_interpolation_type(t, Animation.INTERPOLATION_LINEAR)
		rot_track[i] = t
	var pos_track := anim.add_track(Animation.TYPE_POSITION_3D)
	anim.track_set_path(pos_track, NodePath(rel_path + ":" + skeleton.get_bone_name(hips)))
	anim.track_set_interpolation_type(pos_track, Animation.INTERPOLATION_LINEAR)

	var samples: Array[float] = []
	var cursor := 0.0
	while cursor < length - 0.0005:
		samples.append(cursor)
		cursor += 1.0 / FPS
	samples.append(length)

	var global_basis: Array[Basis] = []
	global_basis.resize(count)
	for time in samples:
		# 找所在的关键姿态区间
		var seg := 0
		while seg < times.size() - 2 and time > float(times[seg + 1]): seg += 1
		var span := maxf(0.0001, float(times[seg + 1]) - float(times[seg]))
		var u := smoothstep(0.0, 1.0, clampf((time - float(times[seg])) / span, 0.0, 1.0))
		for bone in order:
			var qa: Quaternion = (key_q[seg] as Array)[bone]
			var qb: Quaternion = (key_q[seg + 1] as Array)[bone]
			var delta := Basis(qa.slerp(qb, u))
			var rest_global := skeleton.get_bone_global_rest(bone).basis.orthonormalized()
			var target := delta * rest_global
			global_basis[bone] = target
			var parent := skeleton.get_bone_parent(bone)
			var parent_global := global_basis[parent] if parent != -1 else Basis.IDENTITY
			var local := (parent_global.inverse() * target).orthonormalized()
			anim.rotation_track_insert_key(rot_track[bone], time, local.get_rotation_quaternion())
		var height := lerpf(float(key_h[seg]), float(key_h[seg + 1]), u)
		anim.position_track_insert_key(pos_track, time, hips_rest + up_dir * (height - rest_height))
	return anim

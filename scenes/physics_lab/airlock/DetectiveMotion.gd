extends RefCounted
## R-05 keeps its MPFB armature and original pose check. The room adds a
## small in-place gait, driven by the collision body's actual travel.
const MODEL := preload("res://assets/characters/mpfb/r05_styled.glb")
const NATIVE := &"MPFB_Pose_Check"
const GAIT_BONES := [&"thigh_l", &"calf_l", &"foot_l", &"thigh_r", &"calf_r", &"foot_r",
	&"upperarm_l", &"upperarm_r", &"lowerarm_l", &"lowerarm_r", &"spine_02"]

var actor: Node3D
var rig: Skeleton3D
var player: AnimationPlayer
var joints: Dictionary[StringName, int] = {}
var neutral: Dictionary[StringName, Quaternion] = {}
var axes: Dictionary[StringName, Vector3] = {}
var shoulder_roll: Dictionary[StringName, Vector3] = {}
var clip := &"idle"
var phase := 0.0
var weight := 0.0


func attach(parent: Node3D) -> void:
	actor = MODEL.instantiate() as Node3D
	parent.add_child(actor)
	rig = actor.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	player = actor.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(NATIVE)
	player.seek(0.0, true)
	var to_rig := rig.global_basis.inverse() * actor.global_basis
	for bone: StringName in GAIT_BONES:
		var index := rig.find_bone(bone)
		assert(index >= 0, "R-05 missing gait joint %s" % bone)
		joints[bone] = index
		neutral[bone] = rig.get_bone_pose_rotation(index)
		var bone_pose := rig.get_bone_global_pose(index)
		var actor_to_bone := bone_pose.basis.inverse() * to_rig
		axes[bone] = (actor_to_bone * Vector3.RIGHT).normalized()
		if bone == &"upperarm_l" or bone == &"upperarm_r":
			var side := signf((to_rig.inverse() * bone_pose.origin).x)
			shoulder_roll[bone] = (actor_to_bone * Vector3.BACK).normalized() * -side
	advance(0.0, false, 0.0, 0.0)


func advance(travel: float, operating: bool, work: float, delta: float) -> void:
	if operating:
		clip = &"operate"
		weight = 0.0
		# Use the reach-and-return section, before the unrelated knee test.
		player.seek(1.50 * work, true)
		var release := 1.0 - smoothstep(0.0, .24, minf(work, 1.0 - work))
		for shoulder in shoulder_roll:
			var index := joints[shoulder]
			rig.set_bone_pose_rotation(index, _lower_shoulder(shoulder, rig.get_bone_pose_rotation(index), release))
		return
	if clip == &"operate": player.seek(0.0, true)
	clip = &"walk" if travel > .007 else &"idle"
	phase = fposmod(phase + travel * TAU / 1.53, TAU)
	weight = move_toward(weight, 1.0 if clip == &"walk" else 0.0, delta * 10.0)
	_leg(&"thigh_l", &"calf_l", &"foot_l", phase)
	_leg(&"thigh_r", &"calf_r", &"foot_r", phase + PI)
	var swing := sin(phase) * weight
	_turn(&"upperarm_l", .21 * swing)
	_turn(&"upperarm_r", -.21 * swing)
	_turn(&"lowerarm_l", .11 * maxf(0.0, swing))
	_turn(&"lowerarm_r", .11 * maxf(0.0, -swing))
	_turn(&"spine_02", .05 * weight)


func _leg(thigh: StringName, calf: StringName, foot: StringName, time: float) -> void:
	var swing := sin(time)
	var bend := maxf(0.0, cos(time))
	_turn(thigh, .38 * swing * weight)
	_turn(calf, .48 * bend * weight)
	_turn(foot, -.19 * bend * weight)


func _turn(bone: StringName, radians: float) -> void:
	var pose := neutral[bone] * Quaternion(axes[bone], radians)
	if shoulder_roll.has(bone): pose = _lower_shoulder(bone, pose)
	rig.set_bone_pose_rotation(joints[bone], pose)


func _lower_shoulder(bone: StringName, pose: Quaternion, amount: float = 1.0) -> Quaternion:
	return pose * Quaternion(shoulder_roll[bone], .26 * amount)

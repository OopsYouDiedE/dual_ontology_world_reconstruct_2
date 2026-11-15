extends SkeletonModifier3D
## Analytic two-bone reach, evaluated after the character's real AnimationPlayer.
const Character := preload("res://scenes/components/characters/ImportedCharacter.gd")
var right_target: Node3D
var left_target: Node3D
var reach_weight := 0.0
var head_pitch := 0.0
var head_roll := 0.0
var torso_pitch := 0.0
var contact_error_m := 0.0
var character_root: Node3D
var pelvis_offset_world := Vector3.ZERO
var foot_targets: Dictionary = {}
var foot_error_m := 0.0
var arm_measurements: Dictionary = {}

func plant_feet() -> void:
	var skeleton := get_skeleton()
	foot_targets.clear()
	if skeleton == null: return
	for side in ["Left","Right"]:
		var foot := Character._find_mixamo_bone(skeleton,side+"Foot")
		if foot >= 0: foot_targets[side] = skeleton.global_transform*skeleton.get_bone_global_pose(foot).origin

func _process_modification() -> void:
	var skeleton := get_skeleton()
	if skeleton == null: return
	var axes := character_root.global_basis if is_instance_valid(character_root) else Basis.IDENTITY
	var hips := Character._find_mixamo_bone(skeleton,"Hips")
	if hips >= 0 and pelvis_offset_world.length_squared()>0.000001:
		var parent := skeleton.get_bone_parent(hips)
		var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent>=0 else Basis.IDENTITY
		var offset := parent_basis.inverse()*skeleton.global_basis.inverse()*pelvis_offset_world
		skeleton.set_bone_pose_position(hips,skeleton.get_bone_pose_position(hips)+offset)
	_rotate_world(skeleton,"Spine2",axes.x,torso_pitch)
	_rotate_world(skeleton,"Head",axes.x,head_pitch)
	_rotate_world(skeleton,"Head",axes.z,head_roll)
	foot_error_m = 0.0
	for side in foot_targets:
		foot_error_m = maxf(foot_error_m,_solve_chain(skeleton,side+"UpLeg",side+"Leg",side+"Foot",foot_targets[side],1.0))
	contact_error_m = 0.0
	arm_measurements.clear()
	if reach_weight <= 0.0001: return
	for pair in [["Right",right_target],["Left",left_target]]:
		var target := pair[1] as Node3D
		if is_instance_valid(target):
			var side := str(pair[0])
			contact_error_m = maxf(contact_error_m,_solve_chain(skeleton,side+"Arm",side+"ForeArm",side+"Hand",target.global_position,reach_weight))
			arm_measurements[side] = _measure_arm(skeleton,side,target.global_position)

func _measure_arm(skeleton: Skeleton3D, side: String, target_world: Vector3) -> Dictionary:
	var joints: Array[Vector3] = []
	for part in ["Arm","ForeArm","Hand"]:
		var index := Character._find_mixamo_bone(skeleton,side+part)
		if index < 0: return {"missing_bone":side+part}
		joints.append(skeleton.global_transform*skeleton.get_bone_global_pose(index).origin)
	var reach := joints[0].distance_to(joints[1])+joints[1].distance_to(joints[2])
	var distance := joints[0].distance_to(target_world)
	return {"shoulder_world":_xyz(joints[0]),"elbow_world":_xyz(joints[1]),"wrist_world":_xyz(joints[2]),"target_world":_xyz(target_world),"chain_length_m":reach,"shoulder_target_m":distance,"reach_margin_m":reach-distance,"contact_error_m":joints[2].distance_to(target_world)}

static func _xyz(value: Vector3) -> Array:
	return [value.x,value.y,value.z]

func _rotate_world(skeleton: Skeleton3D,name: String,axis_world: Vector3,angle: float) -> void:
	var index := Character._find_mixamo_bone(skeleton,name)
	if index < 0 or absf(angle)<0.000001: return
	var parent := skeleton.get_bone_parent(index)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent>=0 else Basis.IDENTITY
	var axis := (skeleton.global_basis.inverse()*axis_world).normalized()
	var desired := Basis(axis,angle)*skeleton.get_bone_global_pose(index).basis
	skeleton.set_bone_pose_rotation(index,(parent_basis.inverse()*desired).orthonormalized().get_rotation_quaternion())

func _solve_chain(skeleton: Skeleton3D,upper_name: String,lower_name: String,end_name: String,target_world: Vector3,weight: float) -> float:
	var upper := Character._find_mixamo_bone(skeleton,upper_name)
	var lower := Character._find_mixamo_bone(skeleton,lower_name)
	var hand := Character._find_mixamo_bone(skeleton,end_name)
	if mini(upper,mini(lower,hand)) < 0: return INF
	var target := skeleton.global_transform.affine_inverse()*target_world
	var shoulder := skeleton.get_bone_global_pose(upper).origin
	var elbow := skeleton.get_bone_global_pose(lower).origin
	var wrist := skeleton.get_bone_global_pose(hand).origin
	var length_a := shoulder.distance_to(elbow)
	var length_b := elbow.distance_to(wrist)
	if minf(length_a,length_b)<0.0001: return INF
	var towards := target-shoulder
	if towards.length_squared()<0.000001: return INF
	var distance := clampf(towards.length(),absf(length_a-length_b)+0.001,(length_a+length_b)*0.995)
	var direction := towards.normalized()
	var bend := elbow-shoulder-direction*(elbow-shoulder).dot(direction)
	if bend.length_squared()<0.00001:
		bend = skeleton.global_basis.inverse()*Vector3(0,0,1)
		bend -= direction*bend.dot(direction)
	if bend.length_squared()<0.00001: bend = direction.cross(Vector3.UP)
	var cosine := clampf((length_a*length_a+distance*distance-length_b*length_b)/(2*length_a*distance),-1,1)
	var desired_elbow := shoulder+direction*length_a*cosine+bend.normalized()*length_a*sqrt(maxf(0,1-cosine*cosine))
	_aim(skeleton,upper,elbow-shoulder,desired_elbow-shoulder,weight)
	elbow = skeleton.get_bone_global_pose(lower).origin
	wrist = skeleton.get_bone_global_pose(hand).origin
	_aim(skeleton,lower,wrist-elbow,target-elbow,weight)
	var actual := skeleton.global_transform*skeleton.get_bone_global_pose(hand).origin
	return actual.distance_to(target_world)

func _aim(skeleton: Skeleton3D,index: int,from: Vector3,to: Vector3,weight: float) -> void:
	if from.length_squared()<0.00001 or to.length_squared()<0.00001: return
	var global_basis := Basis(Quaternion(from.normalized(),to.normalized()))*skeleton.get_bone_global_pose(index).basis
	var parent := skeleton.get_bone_parent(index)
	var parent_basis := skeleton.get_bone_global_pose(parent).basis if parent>=0 else Basis.IDENTITY
	var desired := (parent_basis.inverse()*global_basis).orthonormalized().get_rotation_quaternion()
	skeleton.set_bone_pose_rotation(index,skeleton.get_bone_pose_rotation(index).slerp(desired,weight))

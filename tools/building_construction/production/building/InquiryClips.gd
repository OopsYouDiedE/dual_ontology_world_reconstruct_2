extends RefCounted
## Copy KayKit Interact rotational deltas into the R05 neutral pose, never its body scale or root motion.
const SOURCE=preload("res://assets/imported/kaykit/animations/Rig_Medium_General.glb")
static var library:AnimationLibrary
static func install(person:Node3D)->void:
	var ap:AnimationPlayer=person.get_meta("animation_player");var sk:Skeleton3D=person.get_meta("skeleton")
	if library==null:
		var src=SOURCE.instantiate();var donor:Skeleton3D=src.find_children("*","Skeleton3D",true,false)[0];var raw:Animation=src.find_children("*","AnimationPlayer",true,false)[0].get_animation("Interact")
		var clip:=Animation.new();clip.length=raw.length;var path=ap.get_node(ap.root_node).get_path_to(sk)
		var mapping={"spine":"spine_01","chest":"spine_03","head":"head"}
		for side in ["l","r"]:
			for pair in [["upperarm","upperarm"],["lowerarm","lowerarm"],["upperleg","thigh"],["lowerleg","calf"],["foot","foot"]]:mapping[pair[0]+"."+side]=pair[1]+"_"+side
		for k in raw.get_track_count():
			var bn=String(raw.track_get_path(k).get_concatenated_subnames());if raw.track_get_type(k)!=Animation.TYPE_ROTATION_3D or not mapping.has(bn):continue
			var a=donor.find_bone(bn);var b=sk.find_bone(mapping[bn]);var frame=sk.get_bone_global_rest(b).basis.get_rotation_quaternion().inverse()*donor.get_bone_global_rest(a).basis.get_rotation_quaternion();var tr=clip.add_track(Animation.TYPE_ROTATION_3D);clip.track_set_path(tr,NodePath("%s:%s"%[path,mapping[bn]]))
			for i in raw.track_get_key_count(k):
				var delta=donor.get_bone_rest(a).basis.get_rotation_quaternion().inverse()*raw.track_get_key_value(k,i);clip.rotation_track_insert_key(tr,raw.track_get_key_time(k,i),(sk.get_bone_pose_rotation(b)*frame*delta*frame.inverse()).normalized())
		library=AnimationLibrary.new();library.add_animation("interact",clip);src.free()
	ap.add_animation_library("kaykit",library)

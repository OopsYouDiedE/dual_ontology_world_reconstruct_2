extends MeshInstance3D
var rig:Skeleton3D
var joint:int
func bind(s:Skeleton3D,bone:String)->void:
	rig=s;joint=s.find_bone(bone)
func _process(_delta:float)->void:
	var p=get_parent().to_local(rig.to_global(rig.get_bone_global_pose(joint).origin));position=Vector3(p.x,.007,p.z+.04);scale=Vector3.ONE*clampf(1.14-p.y,.55,1.)

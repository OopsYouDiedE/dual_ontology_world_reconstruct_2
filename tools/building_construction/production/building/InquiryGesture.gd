extends SkeletonModifier3D
## Two-bone overlay. Targets and elbow poles are expressed in the R05 rig axes (+Z forward).
var motion:StringName
var weight:=0.
func _process_modification()->void:
	if weight<.001 or motion not in [&"listen",&"examine",&"signal"]:return
	var s=get_skeleton();var side="l" if motion==&"listen" else "r"
	var a=s.find_bone("upperarm_"+side);var b=s.find_bone("lowerarm_"+side);var c=s.find_bone("hand_"+side);var h=s.find_bone("head")
	var p=s.get_bone_global_pose(a).origin;var q=s.get_bone_global_pose(b).origin;var r=s.get_bone_global_pose(c).origin;var sign_x=signf(p.x);var head=s.get_bone_global_pose(h).origin
	var dest=head+Vector3(sign_x*.143,.005,.018) if motion==&"listen" else p+Vector3(sign_x*.035,-.38,.33) if motion==&"examine" else p+Vector3(-sign_x*.04,-.12,.39)
	var target=r.lerp(dest,weight);var axis=(target-p).normalized();var l1=p.distance_to(q);var l2=q.distance_to(r);var length=clampf(p.distance_to(target),absf(l1-l2)+.001,l1+l2-.001);var along=(l1*l1-l2*l2+length*length)/(2.*length)
	var pole=Vector3(sign_x*.46,-.85,-.23);pole=(pole-axis*pole.dot(axis)).normalized();var elbow=p+axis*along+pole*sqrt(maxf(0.,l1*l1-along*along))
	turn(s,a,q-p,elbow-p);q=s.get_bone_global_pose(b).origin;r=s.get_bone_global_pose(c).origin;turn(s,b,r-q,p+axis*length-q)
func turn(s:Skeleton3D,b:int,from:Vector3,to:Vector3)->void:
	var g=s.get_bone_global_pose(b);g.basis=Basis(Quaternion(from.normalized(),to.normalized()))*g.basis;s.set_bone_global_pose(b,g)

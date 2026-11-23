extends SkeletonModifier3D
## Two-bone overlay. Targets and elbow poles are expressed in the R05 rig axes (+Z forward).
var motion:StringName
var weight:=0.
func _process_modification()->void:
	var s=get_skeleton();hands(s)
	if weight<.001 or motion not in [&"listen",&"examine",&"signal"]:return
	var side="l" if motion==&"listen" else "r";var shoulder=s.get_bone_global_pose(s.find_bone("upperarm_"+side)).origin
	var head_id=s.find_bone("head");var head_pose=s.get_bone_global_pose(head_id)*s.get_bone_global_rest(head_id).affine_inverse()
	var dest=head_pose*Vector3(signf(shoulder.x)*.118,1.565,.128) if motion==&"listen" else shoulder+Vector3(signf(shoulder.x)*.035,-.41,.29) if motion==&"examine" else shoulder+Vector3(-signf(shoulder.x)*.04,-.12,.39)
	reach(s,side,dest)
	if motion==&"examine":aim_index(s,side,Vector3(signf(shoulder.x)*.12,-.78,.62))
	if motion==&"examine":
		var knee=s.get_bone_global_pose(s.find_bone("calf_l")).origin;reach(s,"l",knee+Vector3(.012,.095,.073))

func aim_index(s:Skeleton3D,side:String,direction:Vector3)->void:
	var wrist=s.find_bone("hand_"+side)
	var knuckle=s.get_bone_global_pose(s.find_bone("index_01_"+side)).origin
	var tip=s.get_bone_global_pose(s.find_bone("index_03_"+side)).origin
	var axis=(tip-knuckle).normalized()
	var angle=axis.angle_to(direction.normalized())
	if angle>.001:turn(s,wrist,axis,axis.slerp(direction.normalized(),weight*minf(1.,deg_to_rad(65.)/angle)))

func hands(s:Skeleton3D)->void:
	for side in ["l","r"]:
		var toward=Vector3(-1 if side=="l" else 1,0,0);var mid=s.get_bone_global_rest(s.find_bone("middle_01_"+side)).origin
		for digit in ["index","middle","ring","pinky","thumb"]:
			for j in range(1,4):
				var id=s.find_bone("%s_0%d_%s"%[digit,j,side]);var rest=s.get_bone_global_rest(id);var next=s.get_bone_global_rest(s.find_bone("%s_0%d_%s"%[digit,mini(3,j+1),side])).origin;var prev=s.get_bone_global_rest(s.get_bone_parent(id)).origin
				var dir=(next-rest.origin if j<3 else rest.origin-prev).normalized();var axis=(rest.basis.inverse()*dir.cross(toward)).normalized();var curl=lerpf(28.,7.,weight) if digit=="index" and side=="r" and motion in [&"signal",&"examine"] else (14. if digit=="thumb" else 28.)
				var q=s.get_bone_pose_rotation(id);if j==1 and digit not in ["middle","thumb"]:q*=Quaternion((rest.basis.inverse()*dir.cross((mid-rest.origin).normalized())).normalized(),.07)
				s.set_bone_pose_rotation(id,q*Quaternion(axis,deg_to_rad(curl)))

func reach(s:Skeleton3D,side:String,dest:Vector3)->void:
	var a=s.find_bone("upperarm_"+side);var b=s.find_bone("lowerarm_"+side);var c=s.find_bone("hand_"+side)
	var p=s.get_bone_global_pose(a).origin;var q=s.get_bone_global_pose(b).origin;var r=s.get_bone_global_pose(c).origin;var sign_x=signf(p.x)
	var target=r.lerp(dest,weight);var axis=(target-p).normalized();var l1=p.distance_to(q);var l2=q.distance_to(r);var length=clampf(p.distance_to(target),absf(l1-l2)+.001,l1+l2-.001);var along=(l1*l1-l2*l2+length*length)/(2.*length)
	var pole=Vector3(sign_x*.46,-.85,-.23);pole=(pole-axis*pole.dot(axis)).normalized();var elbow=p+axis*along+pole*sqrt(maxf(0.,l1*l1-along*along))
	turn(s,a,q-p,elbow-p);q=s.get_bone_global_pose(b).origin;r=s.get_bone_global_pose(c).origin;turn(s,b,r-q,p+axis*length-q)
func turn(s:Skeleton3D,b:int,from:Vector3,to:Vector3)->void:
	var g=s.get_bone_global_pose(b);g.basis=Basis(Quaternion(from.normalized(),to.normalized()))*g.basis;s.set_bone_global_pose(b,g)

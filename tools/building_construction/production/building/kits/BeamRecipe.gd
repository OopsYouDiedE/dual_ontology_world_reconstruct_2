extends RefCounted
const D=preload("../BayDetails.gd")
func emit(s,q):
	if q.variant=="none":return
	var a:Vector3=q.a;var b:Vector3=q.b;var v=b-a
	if q.variant=="gothic_rib":
		var spring_y:float=maxf(q.height-1.15,2.2)
		var rise:float=minf(1.05,q.height-spring_y)
		s.box(q.id,(a+b)/2+Vector3.UP*(q.height-.12),Vector3(v.length(),.24,.22),"stone",3,q.yaw)
		D.pointed_rib(s,q.owner,a+Vector3.UP*spring_y,b+Vector3.UP*spring_y,rise,.095,"cream")
		return
	s.box(q.id,(a+b)/2+Vector3.UP*(q.height-.15),Vector3(v.length(),.3,.21),"wood_dark",3,q.yaw)
	if q.seated:D.beam_corbels(s,q.id,a+Vector3.UP*(q.height-3.3),b+Vector3.UP*(q.height-3.3))
	if q.variant=="arcade" and q.seated:
		var radius=v.length()*.5-.1;var normal=Vector3.UP.cross(v).normalized()
		D.arch(s,q.owner,(a+b)*.5+normal*.17+Vector3.UP*(q.height-.30-radius*.40),v.normalized(),normal,radius,.40)

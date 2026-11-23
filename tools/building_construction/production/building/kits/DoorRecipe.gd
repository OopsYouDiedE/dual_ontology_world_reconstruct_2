extends RefCounted
const D=preload("../BayDetails.gd")
func emit(s,q):
	if q.variant=="oak" and q.high+q.w*.5+.12<=q.height:D.arch(s,q.owner,q.p+Vector3.UP*q.high,q.along,q.n,q.w*.5)
	var style=s.layout.overrides.get(q.id,{}).get("style",q.variant)
	s.socket(q.id,"door",q.p,{"yaw":q.yaw,"width":q.w,"wall_depth":q.thick,"height":q.high,"style":style,"rooms":q.rooms,"interlock":q.interlock,"scene":q.get("scene","")})

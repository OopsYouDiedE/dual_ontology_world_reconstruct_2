extends RefCounted
const D=preload("../BayDetails.gd")
func emit(s,q):
	var k:String=q.owner;var bay:float=s.BAY;var center:Vector3=q.p+Vector3.UP*(q.height-3.3)
	if s.kit(k).dome and s.slots.has("dome/"+k):return
	if q.variant=="coffer" and q.height>=2.8:
		s.box(k+"/coffer-soffit",center+Vector3.UP*3.106,Vector3(bay-.18,.026,bay-.18),"cream",0)
		for tier in [[1.85,2.98,.22,.18,"wood_dark"],[1.69,3.025,.12,.12,"cream"],[1.59,3.067,.08,.08,"gold"]]:
			D.frame(s,k,center,tier)
		# Four ceiling fields around the pendant; the perimeter steps down toward the room.
		for axis in [Vector3.RIGHT,Vector3.BACK]:
			for sign_ in [-1,1]:
				var size=axis*1.56+Vector3.UP*.10+Vector3(axis.z,0,axis.x)*.10
				s.box(k+"/ceiling-rib",center+axis*sign_*.81+Vector3.UP*3.052,size,"cream",0)
	elif q.variant=="pipes":
		for x in [-.32,.32]:s.box(q.id,center+Vector3(x,3.02,0),Vector3(.085,.085,bay),"gold",0)
		s.host.anchor(q.id,"PipeJunction",k,center+Vector3(.32,3.02,0))
	else:s.box(k+"/coffer-soffit",center+Vector3.UP*3.23,Vector3(bay,.10,bay),"stone_dark",0)

extends RefCounted
const D=preload("../BayDetails.gd")
func emit(s,q):
	if q.variant=="gothic_arcade":
		D.gothic_blind_arcade(s,q.owner,q.id,q.p,q.along,q.n,q.w,q.thick,q.door,q.height)
	elif q.variant=="wood":
		var first=s.pieces.size();D.wall_trim(s,q.owner,q.id,q.p,q.along,q.n,q.w,q.thick,q.door)
		if q.height<2.8:
			for i in range(first,s.pieces.size()):
				var r=s.pieces[i];r.p.y=q.p.y+(r.p.y-q.p.y)*.78;r.size.y*=.78
	else:
		for side in [-1,1]:
			var inner=q.w*.5+.08 if q.door else 0.;var span=s.BAY*.5-inner
			var pos=q.p+side*q.along*(inner+span*.5)-q.n*(q.thick*.5+.025)+Vector3.UP*.47
			s.box(q.id,pos,Vector3(span,.88,.035),"stone_dark" if q.variant=="riveted" else "stone",0,q.yaw)
			if q.variant=="riveted":
				for i in 5:s.box(q.id,pos+q.along*span*(i-2)/5.-q.n*.025,Vector3(.035,.035,.02),"gold",0,q.yaw)

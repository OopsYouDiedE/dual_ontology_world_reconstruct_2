extends RefCounted
func emit(s,q):
	var cp:Vector3=q.p;var h:float=q.height;var ci:String=q.id.trim_prefix("column/")
	if q.variant=="none":return
	if q.variant=="iron":
		for dx in [-.09,.09]:s.box(q.id,cp+Vector3(dx,h*.5,0),Vector3(.045,h,.24),"stone_dark")
		s.box(q.id,cp+Vector3.UP*h*.5,Vector3(.16,h,.045),"stone_dark")
	else:
		s.box(q.id,cp+Vector3.UP*(h-.2)*.5,Vector3(.23,h-.2,.23),"stone")
		for tier in [[.42,.045,.09],[.36,.121,.062],[.29,.19,.076]]:
			s.box("plinth/"+ci,cp+Vector3.UP*tier[1],Vector3(tier[0],tier[2],tier[0]),"stone_dark" if tier[1]<.1 else "cream")
		s.box("capital/"+ci,cp+Vector3.UP*(h-.27),Vector3(.36,.14,.36),"cream")
	s.host.anchor(q.id,"ColumnFace",q.owner,cp+Vector3(.115,1.5,0),Vector3.RIGHT)

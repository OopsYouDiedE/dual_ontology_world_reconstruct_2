extends RefCounted
func emit(s,q):
	preload("../BayDetails.gd").dress(s,q.owner,q.p,q.type,q.hole,q.up)

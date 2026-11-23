extends RefCounted
const D=preload("../BayDetails.gd")
func emit(s,q):D.dome(s,q.owner,q.points)

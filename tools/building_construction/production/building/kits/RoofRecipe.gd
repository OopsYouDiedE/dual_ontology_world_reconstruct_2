extends RefCounted
func emit(s,q):
	for i in 8:s.roofs.append([q.owner,q.points[0],q.points[i+1],q.points[(i+1)%8+1]])

extends RefCounted
func supports(q)->bool:return q.variant!="pendant" or q.height>=2.8
func emit(s,q):s.socket(q.id,"light",q.p+Vector3.UP*(q.height-(.50 if q.variant=="pendant" else .13)),{"flush":q.variant!="pendant"})

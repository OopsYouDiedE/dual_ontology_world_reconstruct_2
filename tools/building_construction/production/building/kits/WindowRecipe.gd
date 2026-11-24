extends RefCounted
const D=preload("../BayDetails.gd")
func supports(q)->bool:return q.variant=="blind" or q.open
func emit(s,q):
	var p:Vector3=q.p+Vector3.UP*((q.low+q.high)*.5);var h:float=q.high-q.low
	if q.variant=="blind" and not q.get("required",false):
		p-=q.n*(q.thick*.5+.024);s.box(q.id,p,Vector3(q.w,h,.035),"wood_dark",0,q.yaw);s.box(q.id,p-q.n*.024,Vector3(q.w-.12,h-.12,.025),"stone_dark",0,q.yaw);return
	if q.variant=="gothic_lancet":
		D.gothic_lancet_window(s,q.owner,q.id,q.p,q.along,q.n,q.w,q.low,q.high,q.thick,q.yaw)
		return
	if q.variant=="gothic_rose":
		D.gothic_rose_window(s,q.owner,q.id,q.p,q.along,q.n,q.w,q.low,q.high,q.thick,q.yaw)
		return
	s.box(q.id+"/glass",p,Vector3(q.w,h,.035),"glass",1,q.yaw)
	var count=7 if q.variant=="iron" else 4
	for i in count:s.box(q.id+"/mullion",p+q.along*((float(i)/(count-1)-.5)*q.w),Vector3(.045,h,.07),"wood_dark",1,q.yaw)
	if count>4:s.box(q.id,p,Vector3(q.w,.045,.07),"wood_dark",1,q.yaw)
	s.box(q.id+"/sill",q.p+Vector3.UP*q.low,Vector3(q.w+.12,.07,q.thick+.11),"cream",3,q.yaw)

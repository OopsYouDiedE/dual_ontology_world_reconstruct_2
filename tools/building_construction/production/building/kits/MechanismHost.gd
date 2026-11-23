extends RefCounted
## Mechanisms submit JSON-safe building-space metres. Radius grows from zero at apex.
var volumes:Array=[]
var holes:Dictionary={}
var anchors:Dictionary={}
func reset(plan:Dictionary)->void:
	volumes.clear();holes.clear();anchors.clear()
	for r in plan.get("reservations",[]):
		if r.kind=="opening":holes[r.edge]=r
		else:volumes.append(r)
static func vec(a:Array)->Vector3:return Vector3(a[0],a[1],a[2])
func blocked(bounds:AABB)->bool:
	for r in volumes:
		if r.kind=="cone":
			var a=vec(r.apex);var v=vec(r.end)-a;var length=v.length();var axis=v/length;var d=bounds.get_center()-a;var z=d.dot(axis);var rad=bounds.size.length()*.5
			var envelope=AABB(a,Vector3.ZERO).expand(a+v).grow(r.radius)
			if not envelope.intersects(bounds):continue
			if z+rad>=0 and z-rad<=length and (d-z*axis).length()<=rad+r.radius*clampf((z+rad)/length,0,1):return true
		elif AABB(vec(r.min),vec(r.size)).intersects(bounds):return true
	return false
func anchor(id:String,kind:String,owner:String,p:Vector3,normal:=Vector3.UP)->void:
	if not blocked(AABB(p-Vector3.ONE*.01,Vector3.ONE*.02)):anchors[id]={"kind":kind,"owner":owner,"p":p,"normal":normal}
func nearest(kind:String,point:Vector3,owner:String="")->Dictionary:
	var best={};var distance=INF
	for id in anchors:
		var a=anchors[id];var d=point.distance_squared_to(a.p)
		if a.kind==kind and (owner=="" or owner==a.owner) and d<distance:best=a;distance=d
	return best

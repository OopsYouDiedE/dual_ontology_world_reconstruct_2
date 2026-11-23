extends SceneTree
## Spatial acceptance of the built Example. Rays sample opaque joints, not windows.
const S=preload("../production/building/BuildingSolver.gd")
const View=preload("../production/building/BuildingView.gd")
var failures:Array[String]=[]
func check(ok:bool,detail:String)->void:
	if not ok:failures.append(detail);printerr(detail)
func _initialize()->void:run.call_deferred()
func run()->void:
	var s=S.new();var plan=S.example();s.build(plan);check(s.notes.is_empty(),"unexpected diagnostics: "+str(s.notes))
	plan.mode="strict";s.build(plan);check(s.notes.is_empty(),"strict Example requires repair")
	var v=View.new();root.add_child(v);v.render(s,-1,false);await physics_frame;await physics_frame
	var space=v.get_world_3d().direct_space_state
	var joints=0
	for k in s.hull:
		var c=S.address(k);var level_top=(c.z+1)*S.RISE;var center=Vector3((c.x+.5)*S.BAY,level_top,(c.y+.5)*S.BAY)
		for d in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
			if plan.cells.has(S.key(c.x+d.x,c.y+d.y,c.z)):continue
			var n=Vector3(d.x,0,d.y);var t=Vector3(n.z,0,-n.x)
			for offset in [-S.BAY*.5+.015,0.,S.BAY*.5-.015]:
				var p=center+n*S.BAY*.5+t*offset
				# Diagonal paths pass through the wall/eave junction; vertical paths hit roof inside it.
				for delta in [Vector3(0,1,0),(n+Vector3.UP*.28).normalized()]:
					var mid=p-n*.025;var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(mid-delta*.45,mid+delta*2,S.SIGHT));check(not hit.is_empty(),"open opaque eave: "+k+" "+str(p));joints+=1
	var eye=Vector3(S.BAY,1.6,S.BAY*1.5);var ceiling=space.intersect_ray(PhysicsRayQueryParameters3D.create(eye,eye+Vector3.UP*4,S.MOVE));check(not ceiling.is_empty() and absf(ceiling.position.y-3.)<.01,"hall beam soffit")
	var door=s.sockets.filter(func(o):return o.kind=="door" and o.rooms[1] in plan.cells and o.style=="oak")[0];var n=Basis(Vector3.UP,door.yaw)*Vector3.BACK
	var capsule=CapsuleShape3D.new();capsule.radius=.29;capsule.height=1.77;var q=PhysicsShapeQueryParameters3D.new();q.shape=capsule;q.collision_mask=S.MOVE;q.transform.origin=door.p+Vector3.UP*.90-n*.85;q.motion=n*1.70
	check(space.cast_motion(q)[0]<.98,"closed oak door must stop capsule");v.switch_door(door.id);await physics_frame;await physics_frame;check(space.cast_motion(q)[0]>.99,"open oak door must pass capsule")
	for dx in [-.69,-.65,.65,.69]:
		var p=door.p+Basis(Vector3.UP,door.yaw)*Vector3(dx,1.60,0);var expected=absf(dx)>.675;check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(p-n*.35,p+n*.35,S.SIGHT)).is_empty()==expected,"jamb section x="+str(dx))
	for h in [2.365,2.395]:
		var p=door.p+Vector3.UP*h;check(not space.intersect_ray(PhysicsRayQueryParameters3D.create(p-n*.35,p+n*.35,S.SIGHT)).is_empty()==(h>2.38),"lintel section y="+str(h))
	# The ground entrance used to open into the 1.65 m half landing. Test the
	# approach as well as the threshold, using the same standing player capsule.
	for ext in s.sockets:
		if ext.kind!="door" or plan.cells.has(ext.rooms[1]):continue
		check(not s.active_cores.has(ext.rooms[0]),"Example entrance under stair")
		v.switch_door(ext.id);await physics_frame;await physics_frame
		var normal=Basis(Vector3.UP,ext.yaw)*Vector3.BACK
		q.transform.origin=ext.p+Vector3.UP*.90-normal*1.1;q.motion=normal*2.2
		check(space.cast_motion(q)[0]>.99,"blocked exterior entrance approach")
		for step in [-.8,0.,.8]:
			var head=ext.p+normal*step+Vector3.UP*.05
			check(space.intersect_ray(PhysicsRayQueryParameters3D.create(head,head+Vector3.UP*2.32,S.MOVE)).is_empty(),"tread or support in entrance headroom")
	plan.cells[S.key(9,9,2)]=0;s.build(plan);check(s.notes.any(func(m):return "unsupported floor" in m),"unsupported floors must remain reported")
	print("Example · %d eave ray samples · door 1.35 × 2.38 m · beam soffit 3.00 m · %d failures"%[joints,failures.size()]);v.free();quit(0 if failures.is_empty() else 1)

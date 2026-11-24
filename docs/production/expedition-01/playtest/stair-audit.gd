extends SceneTree
const Scene = preload("res://scenes/expedition_01/Sortie.tscn")
var lv
var walker: CharacterBody3D
var failed := false
const DY := 4.8 / 41.
func _initialize() -> void:
	run.call_deferred()
func point(x: float, i: float, r: float) -> Vector3:
	var a := PI*.5+TAU*i/41.
	return Vector3(x+r*cos(a),DY*i,8.1+r*sin(a))
func ray(p: Vector3) -> Dictionary:
	return walker.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*.22,p-Vector3.UP*.22,1,[walker.get_rid()]))
func walk_to(p: Vector3) -> bool:
	for j in 180:
		var d := Vector2(p.x-walker.position.x,p.z-walker.position.z)
		if d.length() < .09:
			return true
		if lv.retry > 0.: break
		walker.rotation.y = atan2(-d.x,-d.y)
		Input.action_press("move_up",clampf(d.length()*4.,.25,1.))
		await physics_frame
	print("walk timeout target=",p," at=",walker.position," retry=",lv.retry)
	return false
func run() -> void:
	lv = Scene.instantiate()
	root.add_child(lv)
	walker = lv.walker
	lv.set_physics_process(false)
	for j in 4: await physics_frame
	print("engine=",Engine.get_version_info().string," physics=",ProjectSettings.get_setting("physics/3d/physics_engine")," floor_max_deg=",rad_to_deg(walker.floor_max_angle)," snap=",walker.floor_snap_length," capsule=",walker.find_children("*", "CollisionShape3D",false,false)[0].shape)
	for x in [49.15,73.35]:
		var start := -85 if x < 60. else 0
		var shapes := 0
		var treads := 0
		var solid_treads := 0
		for b in get_nodes_in_group("expedition_iron_tread"):
			if b.global_position.distance_to(Vector3(x,0,8.1)) < .001 and b.get_child(0).shape is ConvexPolygonShape3D:
				shapes += 1
		for m in lv.find_children("*", "MeshInstance3D",true,false):
			if absf(m.global_position.x-x) < 2. and m.scale.is_equal_approx(Vector3(1.84,.18,.37)):
				treads += 1
				solid_treads += m.get_child_count()
		var misses := 0
		var wrong := 0
		var capsule_misses := 0
		var count := 0
		var max_error := 0.
		var min_grade := INF
		var max_grade := -INF
		var min_ny := 1.
		var center_grade := Vector2(INF,-INF)
		var center_seam := Vector2(INF,-INF)
		var other_parents := {}
		var kin := KinematicCollision3D.new()
		for i in range(start,41):
			for r in [.308,.486,.664,.842,1.02,1.198,1.376,1.554,1.732]:
				var prev := {}
				for d in [.02,.25,.5,.75,.98,1.02]:
					if i == 40 and d > 1.: continue
					if i == -1 and d > 1.: continue # public landing overlays this seam; measured separately
					var p := point(x,i+d,r)
					var h := ray(p)
					count += 1
					if h.is_empty(): misses += 1; prev = {}; continue
					if not h.collider.is_in_group("expedition_iron_tread") or h.collider.global_position.distance_to(Vector3(x,0,8.1)) > .001:
						wrong += 1; var key := str(h.collider.get_parent().name); other_parents[key] = int(other_parents.get(key,0))+1; prev = {}; continue
					min_ny = minf(min_ny,h.normal.y)
					max_error = maxf(max_error,absf(h.position.y-p.y-.015))
					if not prev.is_empty():
						var g: float = (h.position.y-prev.position.y)/Vector2(h.position.x-prev.position.x,h.position.z-prev.position.z).length()
						min_grade = minf(min_grade,g); max_grade = maxf(max_grade,g)
						if r == 1.02:
							center_grade = Vector2(minf(center_grade.x,g),maxf(center_grade.y,g))
							if d > 1.: center_seam = Vector2(minf(center_seam.x,g),maxf(center_seam.y,g))
					prev = h
			for d in [.02,.5,.98]:
				var tr := walker.global_transform
				tr.origin = point(x,i+d,1.02)+Vector3.UP*.42
				var good := false
				if walker.test_move(tr,Vector3.DOWN*.84,kin,walker.safe_margin,false,4):
					for k in kin.get_collision_count():
						if kin.get_normal(k).y >= cos(walker.floor_max_angle): good = true
				if not good: capsule_misses += 1
		print("x=",x," hulls=",shapes," treads=",treads," tread_children=",solid_treads," rays=",count," miss=",misses," other=",wrong," min_normal_y=",min_ny," max_y_error=",max_error," grade_range=",Vector2(min_grade,max_grade)," capsule_queries=",(41-start)*3," capsule_misses=",capsule_misses)
		failed = failed or shapes != (41-start)*5 or treads != 41-start or solid_treads != 0 or capsule_misses != 0
		print("center_grade=",center_grade," center_seam_grade=",center_seam," other_parents=",other_parents)
		var radial_misses := 0
		var radial_other := 0
		var radial_jump := 0.
		for i in range(start,41):
			for r in [.486,.842,1.198,1.554]:
				var a := ray(point(x,i,r-.004).lerp(point(x,i+1,r-.004),.5))
				var b := ray(point(x,i,r+.004).lerp(point(x,i+1,r+.004),.5))
				if a.is_empty() or b.is_empty(): radial_misses += 1; continue
				if a.collider.global_position.distance_to(Vector3(x,0,8.1)) > .001 or b.collider.global_position.distance_to(Vector3(x,0,8.1)) > .001: radial_other += 1; continue
				radial_jump = maxf(radial_jump,absf(a.position.y-b.position.y))
		print("radial seam pairs=",(41-start)*4," misses=",radial_misses," other=",radial_other," max_abs_delta_y=",radial_jump)
		for z in [9.12,9.45,9.47,11.8]:
			var h := ray(Vector3(x,4.8,z))
			print("top tangent x=",x," z=",z," hit=",h.get("position"))
		for i in [0.,41.]:
			for d in [-.25,-.02,.02,.25]:
				var p := point(x,i+d,1.02)
				var h := ray(p)
				print("landing x=",x," index=",i+d," sample=",p," hit=",h.get("position")," normal=",h.get("normal")," parent=",str(h.collider.get_parent().name) if not h.is_empty() else "-")
		walker.position = Vector3(x,.08,10.95)
		walker.velocity = Vector3.ZERO
		lv.retry = 0.
		lv.set_physics_process(true)
		Input.action_press("expedition_quiet")
		for j in 15: await physics_frame
		var ok := walker.is_on_floor()
		for i in range(42):
			if not ok: break
			ok = await walk_to(point(x,i,1.02))
		if ok: ok = await walk_to(Vector3(x,4.8,11.8))
		Input.action_release("move_up")
		Input.action_release("expedition_quiet")
		for j in 15: await physics_frame
		ok = ok and walker.is_on_floor() and absf(walker.position.y-4.8)<.06 and lv.retry == 0.
		print("walk x=",x," pass=",ok," feet=",walker.position," grounded=",walker.is_on_floor())
		failed = failed or not ok
		lv.set_physics_process(false)
	lv.free()
	for j in 26:
		OS.delay_msec(8)
		await process_frame
	quit(int(failed))

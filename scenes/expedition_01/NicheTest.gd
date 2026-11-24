extends SceneTree
## A2 Quiet Niche: door from the arcade, the earth-cut run into B2, and the
## still-hand lamp oil. Every move is a capsule walk, never a teleport.
var level
var failures:=0

func _initialize()->void:run.call_deferred()

func go(x:float,z:float,limit:=1600)->bool:
	var target:=Vector3(x,0,z);Input.action_press("move_up")
	for i in limit:
		if level.retry>0.:Input.action_release("move_up");push_error("Failure: "+level.notice);return false
		var p:Vector3=level.walker.position;var d:=target-p;d.y=0
		if d.length()<.12:Input.action_release("move_up");return true
		level.walker.rotation.y=atan2(-d.x,-d.z)
		await physics_frame
	Input.action_release("move_up")
	for k in level.walker.get_slide_collision_count():
		print("COLL ",level.walker.get_slide_collision(k).get_collider().get_path()," n=",level.walker.get_slide_collision(k).get_normal())
	var probe:=PhysicsRayQueryParameters3D.create(Vector3(x,1.0,z),Vector3(x,1.0,z)+Vector3.DOWN*.2,1)
	print("RAYDOWN ",level.get_world_3d().direct_space_state.intersect_ray(probe))
	push_error("Blocked at %s approaching %s"%[level.walker.position,target]);failures+=1;return false

func run()->void:
	level=preload("Expedition.tscn").instantiate();root.add_child(level)
	for i in 4:await physics_frame
	# 1. The west door exists: walk from the arcade centre into the niche.
	level.walker.position=Vector3(9.0,.05,0.);level.walker.rotation.y=0.
	await go(9.0,4.2)
	if level.walker.position.z<3.6:push_error("Niche door blocked");quit(1);return
	if level.current_region(level.walker.position)!="niche":push_error("Region read wrong at the door");quit(1);return
	# 2. The still-hand oil refuses a moving hand and accepts a stopped one.
	await go(13.9,4.7)
	level.eye.look_at(Vector3(13.9,.62,5.9))
	if level.focus()!="niche_oil":push_error("Niche oil not focusable: "+level.focus());quit(1);return
	Input.action_press("move_left")
	await physics_frame
	level.use()
	Input.action_release("move_left")
	if level.niche_taken:push_error("Oil lifted while moving");quit(1);return
	for i in 20:await physics_frame
	var before:float=level.oil
	level.eye.look_at(Vector3(13.9,.62,5.9));level.use()
	if not level.niche_taken or level.oil<=before:push_error("Oil refused a still hand");quit(1);return
	level.eye.rotation=Vector3.ZERO
	# 3. The run is a real second route into B2.
	if not await go(15.0,6.6) or not await go(18.6,6.6) or not await go(20.6,6.7):quit(1);return
	if level.current_region(level.walker.position)!="archive":push_error("Run did not land in B2");quit(1);return
	# 4. The old B1 vestibule route still works (no topology was lost).
	if not await go(20.9,3.4) or not await go(21.9,3.4):quit(1);return
	print("PASS: A2 niche opens from the arcade, still-hand oil lifts, run reaches B2, vestibule intact.")
	level.queue_free()
	for tick in 26:
		OS.delay_msec(8)
		await process_frame
	quit(0)

extends SceneTree
## Live player movement through an unmodified Expedition scene instance.
var level
var failures:=0
var distance:=0.
const Z:=-7.36

func _initialize()->void:run.call_deferred()

func expect(condition:bool,label:String)->void:
	if not condition:failures+=1;push_error(label)

func walk(x:float,z:float,max_ticks:=560)->bool:
	var goal:=Vector2(x,z)
	Input.action_press("move_up")
	for i in max_ticks:
		var p:Vector3=level.walker.position
		var delta:=goal-Vector2(p.x,p.z)
		if delta.length()<.085:
			Input.action_release("move_up");return true
		level.walker.rotation.y=atan2(-delta.x,-delta.y)
		await physics_frame
		distance+=p.distance_to(level.walker.position)
	Input.action_release("move_up");return false

func route(points:Array)->bool:
	for point in points:
		if not await walk(point.x,point.y):
			push_error("Blocked approaching %s from %s"%[point,level.walker.position]);return false
	return true

func check_clerestory()->void:
	var space:PhysicsDirectSpaceState3D=level.walker.get_world_3d().direct_space_state
	var samples:=0
	for bay in 6:
		for offset in [-1.75,-1.25,-.75,-.25,.25,.75,1.25,1.75]:
			for y in [3.65,4.2,4.8]:
				var x:float=3.+6.*bay+offset
				var ray:=PhysicsRayQueryParameters3D.create(Vector3(x,y,-1.65),Vector3(x,y,-10.),2)
				var clear:=space.intersect_ray(ray).is_empty()
				expect(clear,"Clerestory opening obstructed at x=%.2f y=%.2f"%[x,y])
				if clear:samples+=1
	print("Clerestory: %d clear sightline samples across six original openings"%samples)

func shot(label:String)->void:
	if not OS.get_cmdline_user_args().has("--review"):return
	for i in 8:await process_frame
	await RenderingServer.frame_post_draw
	var folder:=ProjectSettings.globalize_path("res://.runtime/maintenance-review")
	DirAccess.make_dir_recursive_absolute(folder)
	var image:=root.get_texture().get_image()
	expect(image.save_png(folder+"/"+label+".png")==OK,"Could not save review image")

func run()->void:
	for reverse in [false,true]:
		level=preload("Sortie.tscn").instantiate();root.add_child(level)
		await physics_frame
		await physics_frame
		if not reverse:check_clerestory()
		var loop=level.kit.maintenance
		var entry:float=loop.EAST if reverse else loop.WEST
		var exit:float=loop.WEST if reverse else loop.EAST
		var side:float=1. if reverse else -1.
		var gate_x:float=loop.GATE_X
		var near_x:=gate_x+side*.92
		var first:=Vector2(entry,0.)
		var corner:=Vector2(entry,Z)
		var near_gate:=Vector2(near_x,Z)
		expect(await route([first,Vector2(exit,0.),first]),"Untouched main hall should remain walkable")
		if OS.get_cmdline_user_args().has("--review"):
			level.eye.look_at(Vector3(entry,.0,-2.3)+Vector3.UP*2.48)
			await shot("east-portal" if reverse else "west-portal")
			level.eye.rotation=Vector3.ZERO
		distance=0.
		expect(await route([corner,near_gate]),"Approach blocked")
		expect(not await walk(gate_x-side*.8,Z,55),"Capsule crossed the closed lift")
		expect((level.walker.position.x-gate_x)*side>.26,"Closed leaf did not stop the capsule")
		expect(not await walk(level.walker.position.x,-5.3,48),"Capsule crossed the inner wall")
		expect(not await walk(level.walker.position.x,-9.2,48),"Capsule crossed the outer wall")
		expect(await route([near_gate,corner,first]),"Could not retreat while closed")
		expect(await route([corner,near_gate]),"Could not re-enter after retreat")
		var handle:Vector3=loop.HANDLES[1 if reverse else 0]
		level.eye.look_at(handle)
		expect(level.focus()=="maintenance_lift","Near-side handle should be focusable")
		level.eye.look_at(loop.HANDLES[0 if reverse else 1])
		expect(not loop.visible_target(level.eye,level.walker,loop.HANDLES[0 if reverse else 1]),"Opposite handle should be hidden by the leaf")
		level.eye.look_at(handle)
		await shot("east-closed" if reverse else "west-closed")
		level.use();level.eye.rotation=Vector3.ZERO
		expect(loop.moving,"Use did not start lift")
		for i in 22:await physics_frame
		expect(loop.leaf.position.y>1.17 and loop.weight.position.y<2.45,"Leaf and weight should move in opposite directions")
		expect(await walk(near_x+side*.6,Z),"Could not back away during lift")
		for i in 115:await physics_frame
		expect(loop.opened,"Lift did not latch open")
		if OS.get_cmdline_user_args().has("--review"):
			level.eye.look_at(Vector3(gate_x,1.5,Z))
			await shot("east-open" if reverse else "west-open")
			level.eye.rotation=Vector3.ZERO
		expect(await route([corner,first]),"Could not exit entry while lift was latched")
		distance=0.
		expect(await route([corner,Vector2(exit,Z),Vector2(exit,0.)]),"Could not traverse the open loop")
		expect(distance>23.,"Loop did not materially exceed the 12 m main route")
		print("Maintenance route %s: %.2f m actual capsule travel"%["E to W" if reverse else "W to E",distance])
		expect(await route([Vector2(exit,Z),Vector2(loop.OIL_POINT.x,Z)]),"Return route to oil blocked")
		level.eye.look_at(loop.OIL_POINT)
		expect(level.focus()=="maintenance_oil","Oil reserve should be focusable")
		level.oil=65.;level.use()
		expect(not loop.oil_taken,"Full lamp consumed reserve")
		level.oil=55.;level.use()
		expect(loop.oil_taken and is_equal_approx(level.oil,59.),"Reserve should grant four units once")
		level.use();level.eye.rotation=Vector3.ZERO
		expect(is_equal_approx(level.oil,59.),"Reserve dispensed twice")
		expect(await route([corner,first]),"Could not finish return across open loop")
		level.queue_free();await process_frame
	if failures==0:print("PASS: MaintenanceLoop: two-way capsule, solid walls and leaf, retreat, latched lift, finite oil, main hall")
	# Let the audio mixer release playbacks before terminating the test host.
	for frame in 26:
		OS.delay_msec(8)
		await process_frame
	quit(1 if failures else 0)

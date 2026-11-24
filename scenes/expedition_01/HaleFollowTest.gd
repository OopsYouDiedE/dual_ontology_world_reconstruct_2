extends SceneTree
## Deterministic Hale updates in A1 with the real floor and collision layers.
const DT:=1./60.
var level
var failures:=0

func _initialize()->void:run.call_deferred()

func check(ok:bool,label:String)->void:
	if not ok:
		failures+=1;push_error(label)

func tick()->void:
	var prior:Vector3=level.hale.position
	var yaw:float=level.hale.rotation.y
	level.advance_hale(DT);level.animate_hale(prior,DT)
	check(absf(angle_difference(yaw,level.hale.rotation.y))<=TAU*DT+.0001,"Hale exceeded the yaw rate cap")

func set_gap(gap:float)->void:
	level.walker.position=level.hale.position+Vector3(gap,0.,0.)
	level.last_pos=level.walker.position
	level.trail=PackedVector3Array([level.walker.position])

func run()->void:
	level=preload("Sortie.tscn").instantiate();root.add_child(level)
	level.set_physics_process(false)
	await physics_frame
	await physics_frame
	level.hale.position=Vector3(8,0,0)
	level.hale.rotation.y=PI
	set_gap(2.59);tick()
	check(not level.hale_chasing,"Idle Hale started inside the hysteresis band")
	set_gap(2.61);tick()
	check(level.hale_chasing,"Hale did not start beyond 2.6 m")
	check(absf(angle_difference(PI,level.hale.rotation.y))>.01,"Chase movement did not turn Hale toward the route")
	set_gap(1.61);tick()
	check(level.hale_chasing,"Hale stopped inside the hysteresis band")
	set_gap(1.59);tick()
	check(not level.hale_chasing,"Hale did not stop below 1.6 m")
	set_gap(2.0);tick()
	check(not level.hale_chasing,"Hale restarted inside the band")

	set_gap(.55)
	var start:Vector3=level.hale.position
	var yaw:float=level.hale.rotation.y
	for i in 75:tick()
	check(is_equal_approx(level.hale.position.distance_to(start),.65),"Hale did not complete exactly one sidestep")
	check(is_equal_approx(level.hale.rotation.y,yaw),"Hale turned into the sidestep")
	set_gap(1.61);tick()
	set_gap(.55);start=level.hale.position
	for i in 30:tick()
	check(is_equal_approx(level.hale.position.distance_to(start),.65),"A new encounter did not rearm the sidestep")

	level.hale_speed=4.7
	level.hale_face_motion=true
	level.hale_yaw_before_step=level.hale.rotation.y
	yaw=level.hale.rotation.y
	level.animate_hale(level.hale.position+Vector3(.004,0.,0.),DT)
	check(is_equal_approx(level.hale.rotation.y,yaw),"Low-speed displacement changed Hale's yaw")
	level.pick_order("hold")
	set_gap(3.0);start=level.hale.position
	for i in 30:tick()
	check(level.hale.position==start and not level.hale_chasing,"Hold did not override pursuit")
	level.pick_order("trail");tick()
	check(level.hale_chasing and level.hale.position!=start,"Follow order did not resume pursuit")
	level.free()
	for choice in ["follow","stay","leave_early","hold","trail"]:
		await check_archive_guide(choice)
	if failures==0:print("PASS: Hale following, gate guide, green-door traversal, decline, early departure and command priority")
	# Let the audio mixer release playbacks before terminating the test host.
	for frame in 26:
		OS.delay_msec(8)
		await process_frame
	quit(1 if failures else 0)

func guide_walk(target:Vector2)->bool:
	Input.action_press("move_up")
	for i in 280:
		var p:Vector3=level.walker.position
		var d:=target-Vector2(p.x,p.z)
		if d.length()<.12:
			Input.action_release("move_up");return true
		level.walker.rotation.y=atan2(-d.x,-d.y)
		await physics_frame
	Input.action_release("move_up");return false

func check_archive_guide(choice:String)->void:
	level=preload("Sortie.tscn").instantiate();root.add_child(level)
	level.walker.position=Vector3(34.25,0.,0.)
	level.hale.position=level.kit.gate_spots[0].global_position
	await physics_frame
	level.eye.look_at(Vector3(36.,1.57,0.))
	check(level.focus()=="gate",choice+": could not focus the gate")
	level.pick_order("try_gate")
	if choice=="leave_early":
		check(await guide_walk(Vector2(32.55,0.)),"Could not leave during the gate attempt")
		for i in 85:await physics_frame
		check(level.cues.has("gate") and level.hale_gate_guide==0 and level.subtitle_id!="hale_gate","Guide started after player had already left gate frontage")
	else:
		for i in 220:
			await physics_frame
			if level.hale_gate_guide==3:break
		check(level.hale_gate_guide==3,choice+": Hale did not reach the lookout")
		check(level.hale.position.distance_to(level.HALE_ARCHIVE_LOOKOUT)<.04,choice+": Hale did not stand clear to the side of the doorway")
		check(level.subtitle_id=="hale_gate",choice+": missing the green doorway line")
		for i in 35:await physics_frame
		var to_player:Vector3=level.walker.position-level.hale.position
		check(absf(angle_difference(level.hale.rotation.y,atan2(to_player.x,to_player.z)))<.15,choice+": Hale did not look back")
		if choice=="follow":
			level.eye.rotation=Vector3.ZERO
			check(await guide_walk(Vector2(31.,0.)),"Main hall blocked beside the lookout")
			check(await guide_walk(Vector2(31.,4.9)),"Player could not traverse the green door with real capsule")
			check(level.hale_gate_guide==0 and not level.hale_hold,"Guide kept control after entering archive")
		elif choice=="stay":
			for i in 155:await physics_frame
			check(level.hale_gate_guide==0 and absf(level.walker.position.x-34.25)<.04,"Waiting player was moved or guide never timed out")
		else:
			level.pick_order(choice)
			await physics_frame
			check(level.hale_gate_guide==0 and level.hale_hold==(choice=="hold"),"Guide overrode explicit "+choice+" order")
	level.free()
	await process_frame

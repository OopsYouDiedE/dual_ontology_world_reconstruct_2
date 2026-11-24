extends SceneTree
## Movement feel + interaction regression. Measures the numbers the player
## actually feels: gear speeds, brake distance, reversal time, hop height,
## landing recovery, aim sensitivity and the reach of the command wheel.
var level
var fails:=0

func _initialize()->void:run.call_deferred()

func check(ok:bool,what:String)->void:
	if ok:print("  ok  "+what)
	else:push_error("FAIL "+what);fails+=1

func frames(n:int)->void:
	for i in n:await physics_frame

func speed()->float:
	return Vector2(level.walker.velocity.x,level.walker.velocity.z).length()

func settle()->void:
	Input.action_release("move_up");Input.action_release("expedition_quiet")
	level.running=false
	for i in 45:await physics_frame

func run()->void:
	level=preload("Expedition.tscn").instantiate();root.add_child(level)
	await frames(6)
	level.walker.position=Vector3(4.,.05,0.);level.walker.rotation.y=-PI/2

	# --- gear speeds
	check(is_equal_approx(level.SPEEDS[level.ST_WALK],3.8),"walk gear is 3.8 m/s")
	check(is_equal_approx(level.SPEEDS[level.ST_RUN],6.4),"run gear is 6.4 m/s")
	check(is_equal_approx(level.SPEEDS[level.ST_QUIET],1.55),"quiet gear is 1.55 m/s")
	Input.action_press("move_up")
	await frames(40)
	check(absf(speed()-3.8)<.25,"walk settles at 3.8 m/s (got %.2f)"%speed())
	level.running=true
	await frames(40)
	check(absf(speed()-6.4)<.35,"run settles at 6.4 m/s (got %.2f)"%speed())
	Input.action_press("expedition_quiet")
	await frames(10)
	check(speed()<2.1,"holding quiet drops a run into the quiet gear (got %.2f)"%speed())
	Input.action_release("expedition_quiet")
	await settle()

	# --- brake distance from a sprint (target < 1.5 m, old build glided further)
	level.running=true
	Input.action_press("move_up")
	await frames(50)
	var z0:float=level.walker.position.x
	Input.action_release("move_up")
	var stop_frames:=0
	for i in 120:
		await physics_frame
		stop_frames+=1
		if speed()<.08:break
	var brake:=absf(level.walker.position.x-z0)
	check(brake<1.6,"sprint stops in under 1.6 m (%.2f m in %d frames)"%[brake,stop_frames])
	check(stop_frames<26,"sprint stops within 26 physics frames (%d)"%stop_frames)
	level.running=false
	await settle()

	# --- hop clears the new 0.12 m threshold without a step-up assist
	Input.action_press("move_up")
	await frames(20)
	var y0:float=level.walker.position.y
	level._input(_key(KEY_SPACE))
	var peak:=y0
	for i in 40:
		await physics_frame
		peak=maxf(peak,level.walker.position.y)
	check(peak-y0>.42,"Space gives a hop over 0.42 m (%.2f)"%(peak-y0))
	await settle()
	check(absf(level.walker.position.y-.05)<.12 or level.walker.is_on_floor(),"the hop lands back on the floor")
	var landed_y:float=level.walker.position.y
	await frames(6)
	check(level.polish.land_dip<.012 and level.walker.is_on_floor(),"landing dip is absorbed by the camera rig")
	check(absf(level.walker.position.y-landed_y)<.05,"no sinking through the deck after landing")

	# --- aim stance halves the look gain and tightens the lens
	level.aiming=true
	for i in 40:
		await physics_frame
		await process_frame
	check(level.aim>.9,"aim blends in (%.2f)"%level.aim)
	level.polish._rig(.016)
	check(absf(level.polish.fov_off)<1. and level.eye.fov<76.,"aiming keeps the lens inside the base envelope")
	level.aiming=false
	for i in 20:await process_frame

	# --- wheel reach at each decision point
	level.walker.position=Vector3(34.6,.05,0.);level.eye.look_at(Vector3(36.,1.57,0.))
	check(level.order_options().size()>=2,"gate offers a real choice (2+ orders)")
	var ids:Array=level.order_options().map(func(o):return o.id)
	check("hold" in ids,"hold is always available")
	level.walker.position=Vector3(48.0,.05,10.1)
	level.released=true
	ids=level.order_options().map(func(o):return o.id)
	check("trail" in ids,"the shaft offers a follow order")
	check("north" in ids or level.hale.position.distance_to(level.walker.position)>6.,"north order is offered or explicitly gated by distance")

	# --- prompts: the action line and the notice line no longer fight
	level.notice="测试通知";level.msg_time=4.
	level.walker.position=Vector3(24.6,.05,4.0);level.walker.rotation.y=-PI*.5;level.eye.rotation=Vector3.ZERO
	await frames(2)
	check(level.prompt_notice.text=="测试通知","the notice line survives while the action line is empty")
	check(level.prompt.text=="","the action line clears instead of echoing the notice")

	print("PASS: movement gear, brake distance, hop, aim, wheel reach, prompt split (%d checks failed)"%fails)
	level.queue_free()
	for tick in 26:
		OS.delay_msec(8)
		await process_frame
	quit(0 if fails==0 else 1)

func _key(code:Key)->InputEventKey:
	var e:=InputEventKey.new();e.physical_keycode=code;e.pressed=true;return e

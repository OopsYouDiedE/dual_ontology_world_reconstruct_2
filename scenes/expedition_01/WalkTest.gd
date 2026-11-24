extends SceneTree
## A continuous capsule traversal. Navigation targets are floor coordinates, never teleports.
var level
var failures:=0
var gaze:=false
var solo_span:=false
var window_skip:=false
var transit_only:=false
var no_clock:=false
var clock_only:=false
var oil_only:=false
var audit_log
var replay_path:=""
var strategy:={}
var approach_radius:=.12
var wait_settle:=116
var stair_radius:=1.02
var outcome:="interrupted"
var failure_reason:=""
var route_start:=0
var compact:=false
var death_reported:=false
func _finalize()->void:
	if audit_log!=null and audit_log.active:save_replay()

func save_replay()->void:
	var report:={"profile":"定路线", "seed":strategy.seed, "tick":audit_log.now(), "physics_hz":60, "outcome":outcome, "failure_reason":failure_reason, "policy_parameters":strategy}
	audit_log.finish(report)
	var file:=FileAccess.open(replay_path,FileAccess.WRITE)
	if file==null:push_error("Cannot write strategy replay: "+replay_path);return
	file.store_string(JSON.stringify(report));file.close()

func _initialize()->void:run.call_deferred()
func observe_death()->void:
	if not death_reported and is_instance_valid(level) and level.retry>0.:
		death_reported=true
		print("WALK_DEATH ",JSON.stringify({"fail_reason":level.fail_reason,"tick":Engine.get_physics_frames()-route_start}))
func go(x:float,z:float,limit:=2000)->bool:
	var target:=Vector3(x,0,z);Input.action_press("move_up")
	for i in limit:
		if level.retry>0.:
			outcome="failed";failure_reason=level.fail_reason
			if audit_log!=null and audit_log.active:save_replay()
			Input.action_release("move_up");push_error("Gameplay failure at %s: %s"%[level.walker.position,level.notice]);return false
		if level.finished:Input.action_release("move_up");return true
		var p:Vector3=level.walker.position;var d:Vector3=target-p;d.y=0
		if d.length()<approach_radius:Input.action_release("move_up");return true
		level.walker.rotation.y=atan2(-d.x,-d.z)
		if gaze:level.eye.look_at(Vector3(23.85,.11,13.0))
		if solo_span:level.eye.look_at(Vector3(minf(p.x+3.,69.8),0.,10.1))
		await physics_frame
	for k in level.walker.get_slide_collision_count():print(level.walker.get_slide_collision(k).get_collider().get_path(),level.walker.get_slide_collision(k).get_normal())
	Input.action_release("move_up");push_error("Blocked at %s approaching %s"%[level.walker.position,target]);failures+=1;return false
func wait_ticks(n:int)->void:
	for i in n:await physics_frame
func use_at(target:Vector3,id:String)->bool:
	level.eye.look_at(target)
	if level.focus()!=id:
		push_error("Expected %s, got %s at %s"%[id,level.focus(),level.walker.position]);return false
	level.use();level.eye.rotation=Vector3.ZERO;return true
func walk_loft(take_clock:bool,reverse:bool)->bool:
	var entry:=39.05 if reverse else 29.9
	var departure:=29.9 if reverse else 39.05
	var source:int=1 if reverse else 0
	var ports:Array=level.Relay.PORTS
	if not await go(entry,14.1) or not await go(entry,16.45) or not await go(34.3,16.45):return false
	level.eye.look_at(Vector3(34.14,.5,14.67))
	if level.walker.position.y<.55 or level.focus()=="loot" or not level.in_b4(level.walker.position):
		push_error("Deck elevation, glazing or dark zone failed");return false
	level.eye.rotation=Vector3.ZERO
	if take_clock:
		if not use_at(level.Relay.HATCH,"clock_locked") or level.equipped:return false
		if not await go(ports[source].x,16.73):return false
		await wait_ticks(15)
		if not use_at(ports[source],"relay"):return false
		if not reverse:
			# Leaving the felt during the reply must mask it and keep the locker locked.
			if not await go(34.3,16.45):return false
			await wait_ticks(50)
			if level.service_signal.heard or level.service_signal.open:
				push_error("Moving heard a clear reply");return false
			if not await go(ports[source].x,16.73):return false
			await wait_ticks(15)
			if not use_at(ports[source],"relay"):return false
		await wait_ticks(50)
		if not level.service_signal.heard or level.service_signal.target()!=1-source:
			push_error("Clear relay did not answer from the opposite bay");return false
		if not await go(ports[1-source].x,16.73) or not use_at(ports[1-source],"relay"):return false
		if not level.service_signal.open or level.equipped:return false
		if not await go(level.Relay.HATCH.x,16.60) or not use_at(level.Relay.HATCH,"clock"):return false
		if not level.equipped or not level.clock_taken or level.kit.clock_cache.visible:return false
		level.equipped=false # An expended shaft lure cannot be restocked at the empty locker.
		level.eye.look_at(level.Relay.HATCH)
		if level.focus()=="clock":push_error("The empty locker still offers the lure");return false
		level.equipped=true;level.eye.rotation=Vector3.ZERO
	return await go(departure,16.45) and await go(departure,14.1)
func audit()->bool:
	var kit=level.kit;var space=level.get_world_3d().direct_space_state
	for i in range(6,23):
		var a:=TAU*(i+.5)/56.
		for sign_z in [-1,1]:
			var top:Vector3=kit.polar(13.25,sign_z*a,1.)
			var hit=space.intersect_ray(PhysicsRayQueryParameters3D.create(top,top+Vector3.DOWN*2.,1))
			if hit.is_empty()!=(sign_z<0):push_error("Mid-level floor mismatch at %s"%top);return false
	for deg in kit.BLIND_ANGLES:
		if level.sees_span(kit.polar(12.55,deg_to_rad(deg),6.42)):push_error("Sight leak at %d degrees"%deg);return false
	if not level.sees_span(kit.polar(12.45,1.5*PI,6.42)):push_error("North window blocked");return false
	for x in [28.45,29.5,31.,32.55,33.65]:
		var start:=Vector3(x,1.25,5.95)
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(start,start+Vector3.BACK*1.85,1)).is_empty():push_error("Collapse gap");return false
	for joint in [Vector2(kit.RETURN_ELBOW-1.17,4.8),Vector2(kit.RETURN_WEST+1.17,0.)]:
		for dx in [-.23,-.08,0.,.08,.23]:
			for h in [.14,1.18,2.46,2.74]:
				var inside:=Vector3(joint.x+dx,joint.y+h,kit.RETURN_SOUTH+.71)
				if space.intersect_ray(PhysicsRayQueryParameters3D.create(inside,inside+Vector3.BACK*.87,2)).is_empty():
					push_error("Open wall joint at the return ramp: %s"%inside);return false
	return true
func run()->void:
	var args:=OS.get_cmdline_user_args()
	transit_only=args.has("--transit-only")
	window_skip=transit_only or args.has("--skip-window")
	oil_only=args.has("--oil-only")
	no_clock=args.has("--south") or oil_only
	clock_only=args.has("--clock-only")
	level=preload("Expedition.tscn").instantiate();root.add_child(level);await physics_frame
	await physics_frame
	var key:=InputEventKey.new();key.physical_keycode=KEY_1;key.pressed=true
	level._input(key);if not level.manual.visible:quit(1);return
	level._input(key);if level.manual.visible:quit(1);return
	key.physical_keycode=KEY_SHIFT;level._input(key);if not level.running:quit(1);return
	level._input(key);if level.running:quit(1);return
	for ramp_x in [21.5,26.2]:
		level.walker.position=Vector3(ramp_x,-.59,12.45);level.walker.rotation.y=0
		for f in 10:await physics_frame
		if not await go(ramp_x,9.96,60) or level.walker.position.y<-.04:push_error("Entry ramp failed");quit(1);return
	level.queue_free();await wait_ticks(2)
	route_start=Engine.get_physics_frames()
	level=preload("Expedition.tscn").instantiate();root.add_child(level)
	var crossing_arg:="south" if no_clock else "self" if window_skip else "north"
	var route_seed:=1
	var light:=args.has("--strategy-light")
	for arg in args:
		if arg.begins_with("--route-output="):replay_path=arg.trim_prefix("--route-output=")
		if arg.begins_with("--run-seed="):route_seed=int(arg.trim_prefix("--run-seed="))
		if arg.begins_with("--crossing="):crossing_arg=arg.trim_prefix("--crossing=")
		if arg.begins_with("--arrival-radius="):approach_radius=float(arg.trim_prefix("--arrival-radius="))
		if arg.begins_with("--settle-ticks="):wait_settle=int(arg.trim_prefix("--settle-ticks="))
		if arg.begins_with("--stair-radius="):stair_radius=float(arg.trim_prefix("--stair-radius="))
	if not (.04<=approach_radius and approach_radius<=.25 and wait_settle>=1 and wait_settle<=600 and .85<=stair_radius and stair_radius<=1.18):push_error("Invalid strategy parameters");quit(2);return
	strategy={"seed":route_seed,"approach":"transit" if transit_only else "skip" if window_skip else "witness", "loadout":"oil" if oil_only else "neither" if no_clock else "clock" if clock_only else "both", "crossing":crossing_arg,"arrival_radius_m":approach_radius,"extra_settle_ticks":null if transit_only else wait_settle,"stair_radius_m":stair_radius,"fixture":"light" if light else "full"}
	compact=args.has("--walk-compact")
	if compact:
		print("WALK_POLICY ",JSON.stringify(strategy))
		physics_frame.connect(observe_death)
	if light:preload("res://tools/expedition/collision_fixture.gd").apply_lightweight(level)
	if replay_path!="":
		audit_log=preload("res://tools/expedition/strategy_trace.gd").new();audit_log.start(level)
	await wait_ticks(2)
	if not audit():quit(1);return
	for point in [[31,0],[31,4.9],[26.7,4.9],[25.7,5.5],[25.7,7.75],[24.65,7.75],[20.95,7.75],[20.95,9.8],[23.85,9.8],[23.85,12],[23.85,14.12],[25.5,14.1],[28.3,14.1],[34,14.1],[38.9,14.1],[38.9,10],[36.6,8.5]]:
		if not await go(point[0],point[1]):quit(1);return
		if point==[24.65,7.75] and not window_skip:
			# Let Hale take the first watch. He yields after the overlap.
			level.eye.look_at(Vector3(24.65,1.57,4.))
			for tick in 240:
				await physics_frame
				if level.archive.gaze!=Vector3.ZERO and level.observers==1:break
			level.eye.look_at(Vector3(23.85,.10,12.02))
			var two:=false;var withdrew:=false
			for frame in 240:
				await physics_frame
				if level.observers==2 and level.overload_blend>.80:two=true
				if two and level.observers==1 and level.overload_blend<.22 and level.archive.paired:
					withdrew=true;break
			if withdrew:await wait_ticks(42) # Finish the second watcher’s custody interval.
			if not withdrew:push_error("Hale did not trigger and withdraw from the two-observer overload");quit(1);return
			if level.archive.note or level.learned:push_error("B2 alone wrote the proof");quit(1);return
			level.eye.rotation=Vector3.ZERO
		if point==[20.95,7.75]:
			for frame in 360:
				await physics_frame
				if level.cues.has("ward_unseen" if window_skip else "ward_paired"):break
			if not level.cues.has("ward_unseen" if window_skip else "ward_paired") or level.hale.position.z>=8.95:
				push_error("Hale did not give the appropriate warning from outside B3");quit(1);return
		if point==[23.85,9.8] and transit_only:gaze=true
		if point==[23.85,9.8] and not transit_only:
			level.eye.look_at(Vector3(23.85,.11,12.02))
			for f in 44:await physics_frame
			if level.demo_locked or not level.cues.has("settling") or level.overload_blend>.01:push_error("Missing single-gaze amber settling phase");quit(1);return
			for f in wait_settle:await physics_frame
			if not level.demo_locked or level.archive.note==window_skip or level.learned or level.hale.position.z>=8.95:
				push_error("The single-gaze proof or Hale doorstep constraint failed");quit(1);return
			gaze=true
		if point==[23.85,14.12]:gaze=false;level.eye.rotation=Vector3.ZERO
		if absf(point[0]-25.5)<.01:
			if level.learned==transit_only:push_error("Wrong B3 crossing proof state");quit(1);return
			for f in 5:await physics_frame
			if not window_skip and not level.captions.entries.has(""):push_error("Missing B3 inner thought");quit(1);return
		if absf(point[0]-28.3)<.01:
			if not oil_only and not clock_only:
				if not await walk_loft(not no_clock,false):quit(1);return
			if clock_only:
				if not await walk_loft(true,true):quit(1);return
			for bypass in [[29.35,14.1],[29.35,12.1],[36.2,12.1],[29.35,12.1],[29.35,14.1]]:
				if not await go(bypass[0],bypass[1]):quit(1);return
		if absf(point[0]-34)<.01 and (oil_only or not no_clock and not clock_only):
			var before:float=level.oil
			if not use_at(Vector3(34.14,.5,14.67),"loot") or level.oil<=before or level.kit.oil_tin.visible:quit(1);return
	level.eye.look_at(Vector3(36.3,1.35,7.72));level.use()
	if not (level.learned!=transit_only and level.released and level.equipped!=no_clock and level.taken==(oil_only or not no_clock and not clock_only)):
		push_error("Archive state incomplete");quit(1);return
	Input.action_press("expedition_quiet")
	for point in [[39,10.1],[48.8,10.1]]:
		if not await go(point[0],point[1]):quit(1);return
	# Keep legacy single-route invocations; the matrix varies supplies and crossing independently.
	var crossing:=crossing_arg
	if crossing not in ["south","self","north"]:push_error("Unknown crossing: "+crossing);quit(1);return
	var requested:=crossing
	if crossing=="north":
		for i in 240:
			if transit_only or level.hale.position.distance_to(level.walker.position)<=6.:break
			await physics_frame
		level.eye.look_at(level.kit.polar(12.45,1.5*PI,6.42));level.order()
		if transit_only:
			if level.posting or level.holding or level.notice!="Hale 还没到桥头。":push_error("Missing response to unavailable Hale");quit(1);return
			crossing="self" # The player can recover from the refused order without a restart.
		else:
			if not level.posting or level.north_pause<=0.:push_error("Hale agreement was skipped");quit(1);return
			for i in 950:await physics_frame
			if not level.holding:push_error("Hale did not reach north window");quit(1);return
	if crossing=="south":
		level.toggle_lamp() # Observe the one-lamp rule on the long service walk.
		var oil_before:float=level.oil
		for i in range(33):
			var pt:Vector3=level.kit.polar(13.3,PI*(1.-i/32.),0.)
			if not await go(pt.x,pt.z):quit(1);return
		if level.oil>oil_before-15.:push_error("Unpriced southern bypass");quit(1);return
	elif level.equipped:
		level.eye.rotation=Vector3.ZERO;level.walker.rotation.y=-PI/2;level.eye.look_at(level.hunter.BAIT);level.use();level.eye.rotation=Vector3.ZERO;if level.distraction<=0:push_error("Lure not thrown");quit(1);return
	solo_span=crossing=="self"
	if not await go(72.9 if crossing=="south" else 70.95,10.1):quit(1);return
	solo_span=false
	level.eye.look_at(level.kit.core.position);level.use();Input.action_release("expedition_quiet");level.running=true;if not level.collected:quit(1);return
	if not await go(72.9 if crossing=="south" else 70.95,11.45):quit(1);return
	if not await go(73.35,11.45):quit(1);return
	if not await go(73.35,9.12):quit(1);return
	for i in range(1,42):
		var a:=PI*.5+TAU*i/41.
		if not await go(73.35+stair_radius*cos(a),8.1+stair_radius*sin(a),250):quit(1);return
	if level.walker.position.y<4.5:push_error("Missed upper landing: %s"%level.walker.position);quit(1);return
	if not await go(73.35,12.1):quit(1);return
	for i in 15:await physics_frame
	level.eye.look_at(level.kit.leaf.global_position);level.use()
	if not level.shortcut_open:push_error("Return leaf out of reach");quit(1);return
	for i in 35:await physics_frame
	for point:Vector2 in level.kit.RETURN_PATH:
		if not await go(point.x,point.y,900):quit(1);return
	if level.gallery_bell.playing or level.gallery_impact.playing or not level.shortcut_used or level.walker.position.distance_to(Vector3(43.8,0,10.1))>.4:
		push_error("Physical return gallery did not reach B5");quit(1);return
	for point in [[38.7,10.1],[38.7,7.2],[38.7,0],[34,0],[1.5,0]]:
		if not await go(point[0],point[1]):quit(1);return
	if not level.reunited:push_error("Hale did not rejoin in the main hall");quit(1);return
	var completed:=[false];level.returned.connect(func():completed[0]=level.polish.fade_a>.999 and level.polish.end_card.modulate.a>.999)
	for i in 15:await physics_frame
	level.eye.look_at(Vector3(.37,1.5,0));level.use()
	for i in 35:await physics_frame
	if not await go(-2.95,0):quit(1);return
	for i in 950:
		if completed[0]:break
		await physics_frame
	if not completed[0]:push_error("Exit signal missing");quit(1);return
	var trace_path:=ProjectSettings.globalize_path("res://.runtime/archive-%s.json"%("transit-evac" if transit_only else "skip-window-evac" if window_skip else "normal"))
	var explicit_trace:=false
	for arg in args:
		if arg.begins_with("--walk-trace="):
			trace_path=arg.trim_prefix("--walk-trace=")
			explicit_trace=true
	var facts:Dictionary=level.archive.facts.snapshot()
	if compact:
		print("WALK_WITNESS ",JSON.stringify("dual_gaze_b2" in facts["facts"]))
	if not compact or explicit_trace:
		var trace:=FileAccess.open(trace_path,FileAccess.WRITE)
		if trace==null:push_error("Could not export archive trace");quit(1);return
		trace.store_string(JSON.stringify(facts,"  "));trace.close()
	outcome="completed"
	if audit_log!=null:save_replay()
	print("ROUTE_TICKS ",Engine.get_physics_frames()-route_start)
	print("PASS: A1 to evacuation; B4=%s, crossing=%s."%["oil only" if oil_only else "skip both" if no_clock else "metronome only" if clock_only else "both caches", requested+"->"+crossing])
	level.queue_free()
	# Fixed-FPS headless runs outrun the asynchronous Vorbis mixer on Windows.
	for i in 26:
		OS.delay_msec(8)
		await process_frame
	quit(0)

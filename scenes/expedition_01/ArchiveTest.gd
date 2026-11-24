extends SceneTree
## The normal route lives in WalkTest. Here we take the actual capsule through
## the doors without B2, then exercise an interrupted and repeated B3 trial.
const APPROACH := [[30.9,.35],[31,4.9],[26.7,4.9],[25.7,5.5],[25.7,7.75],[20.95,7.75],[20.95,9.8],[23.85,9.8]]
const TO_LEVER := [[25.5,14.1],[28.3,14.1],[34,14.1],[38.9,14.1],[38.9,10],[36.6,8.5]]
const PLATE := Vector3(23.85,.11,12.02)
const FAR_PLATE := Vector3(23.85,.11,13.45)
var level
var checked_witness_cone:=false

func _initialize()->void:run.call_deferred()

func wait_ticks(n:int)->void:
	for i in n:await physics_frame

func insist(ok:bool,why:String)->bool:
	if not ok:
		Input.action_release("move_up");push_error(why);quit(1)
	return ok

func walk(points:Array,sight:=Vector3.INF)->bool:
	Input.action_press("move_up")
	for point in points:
		for i in 1000:
			if not insist(level.retry<=0.,"Route failed: "+level.notice):return false
			if not checked_witness_cone and level.crossing_locked and level.archive.sees_crossing(level):
				var yaw:float=level.hale.rotation.y
				level.hale.rotation.y=yaw+PI
				var saw_behind:bool=level.archive.sees_crossing(level)
				level.hale.rotation.y=yaw
				level.archive.gaze=Vector3.FORWARD
				var saw_while_watching_plate:bool=level.archive.sees_crossing(level)
				level.archive.gaze=Vector3.ZERO
				var doorway:Vector3=level.hale.position
				level.hale.position=doorway+(doorway-level.walker.position).normalized()*6.
				var saw_too_far:bool=level.archive.sees_crossing(level)
				level.hale.position=doorway
				if not insist(not saw_behind and not saw_while_watching_plate and not saw_too_far and level.archive.sees_crossing(level),
					"Hale's facing, attention and range must constrain the doorway ray"):return false
				checked_witness_cone=true
			var p:Vector3=level.walker.position
			var delta:=Vector2(point[0]-p.x,point[1]-p.z)
			if delta.length()<.12:break
			if i==999:
				for k in level.walker.get_slide_collision_count():print(level.walker.get_slide_collision(k).get_collider().get_path())
			if not insist(i<999,"Capsule blocked from %s to %s"%[p,point]):return false
			level.walker.rotation.y=atan2(-delta.x,-delta.y)
			if sight.is_finite():level.eye.look_at(sight)
			else:level.eye.rotation=Vector3.ZERO
			await physics_frame
	Input.action_release("move_up")
	return true

func count_event(key:String,value:String)->int:
	var events:Array=level.archive.facts.snapshot().decisions
	return events.filter(func(event):return event.get(key)==value).size()

func export_trace(route:String)->bool:
	var dir:=ProjectSettings.globalize_path("res://.runtime")
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--archive-trace-dir="):dir=arg.trim_prefix("--archive-trace-dir=")
	DirAccess.make_dir_recursive_absolute(dir)
	var file:=FileAccess.open(dir.path_join("archive-%s.json"%route),FileAccess.WRITE)
	if not insist(file!=null,"Could not export archive trace"):return false
	file.store_string(JSON.stringify(level.archive.facts.snapshot(),"  "))
	return true

func contract_gaze(player:bool,hale:bool)->void:
	level.eye.look_at(PLATE if player else level.eye.global_position+Vector3.UP*.3+Vector3.FORWARD)
	level.archive.gaze=PLATE-level.hale.position-Vector3.UP*1.57 if hale else Vector3.ZERO

func contract_tick(frames:int=1)->void:
	for i in frames:
		await physics_frame
		level.rules(1./60.)

func hale_caption(id:String,text:String)->bool:
	var entry:Dictionary=level.captions.entries.get("Hale",{})
	return entry.get("id","")==id and entry.label.text=="Hale："+text

func trip_blackout()->void:
	contract_gaze(true,false);await contract_tick()
	contract_gaze(true,true);await contract_tick()
	contract_gaze(true,false);await contract_tick()

func test_contract_dialogue()->bool:
	level=preload("Expedition.tscn").instantiate();root.add_child(level)
	level.set_physics_process(false)
	await wait_ticks(2)
	level.walker.position=Vector3(26.89,.03,8.53)
	level.hale.position=level.archive.WINDOW
	for hale_first in [false,true]:
		contract_gaze(not hale_first,hale_first);await contract_tick()
		contract_gaze(true,true);await contract_tick()
		if not insist(level.contracts.a_state=="overlap","Dialogue fixture did not establish two live rays"):return false
		contract_gaze(hale_first,not hale_first);await contract_tick(42)
		var text:="我背过身了。你那边怎么样？" if hale_first else "看，波纹平了。"
		if not insist(level.contracts.a_state=="idle" and hale_caption("pass_a",text),"Handoff caption contradicted Hale's gaze: "+text):return false
		contract_gaze(false,false);await contract_tick()
	level.captions.clear()
	await trip_blackout()
	if not insist(level.contracts.a_state=="blackout" and hale_caption("breach_a","刚才那声碎响，你听见了吗？"),"First blackout on stone needs an audible reaction, not an evacuation command"):return false
	contract_gaze(false,false);await contract_tick(190)
	level.captions.clear()
	await trip_blackout()
	if not insist(level.contracts.a_state=="blackout" and not level.captions.entries.has("Hale"),"Repeated window blackout replayed Hale's reaction"):return false
	contract_gaze(false,false);await contract_tick(190)
	level.walker.position=Vector3(23.85,.12,11.75)
	level.hale.position=Vector3(23.85,0.,14.85)
	await trip_blackout()
	if not insist(level.contracts.a_state=="blackout" and hale_caption("breach_a","脚下！快退回石台！"),"A player losing support needs Hale's urgent warning even after the window cue"):return false
	contract_gaze(false,false);await contract_tick(190)
	level.captions.clear()
	level.walker.position=Vector3(23.85,.03,9.25)
	level.hale.position=Vector3(23.85,0.,15.02)
	await trip_blackout()
	if not insist(level.contracts.a_state=="blackout" and not level.captions.entries.has("Hale"),"A distant Hale narrated the blackout"):return false
	level.queue_free();await wait_ticks(3)
	print("PASS: release dialogue matches both gaze orders; first window blackout is audible, repeat is quiet, plate danger is urgent, distant Hale stays silent")
	return true

func run()->void:
	if not await test_contract_dialogue():return
	level=preload("Expedition.tscn").instantiate();root.add_child(level)
	await wait_ticks(2)
	if not await walk(APPROACH):return
	if not await walk([[23.85,14.12]],FAR_PLATE):return
	if not await walk(TO_LEVER):return
	if not insist(not level.learned and not level.archive.note and not level.archive.paired and level.hale.position.z<8.95,
		"Direct transit invented evidence or brought Hale through the door"):return
	level.eye.look_at(Vector3(36.3,1.35,7.72))
	if not insist(level.focus()=="lever","B5 still gates on B2/B3 proof"):return
	level.use()
	if not insist(level.released and count_event("decision","master_release")==1 and count_event("decision","trial_entry")==1,
		"Direct B5 release or decision audit missing"):return

	if not export_trace("direct"):return
	level.queue_free();await wait_ticks(3)
	level=preload("Expedition.tscn").instantiate();root.add_child(level)
	await wait_ticks(2)
	if not await walk(APPROACH):return
	level.eye.look_at(PLATE);await wait_ticks(105)
	level.eye.rotation=Vector3.ZERO;await wait_ticks(5)
	level.eye.look_at(PLATE);await wait_ticks(105)
	if not insist(not level.demo_locked and count_event("fact","solo_lock_b3")==0,"Interrupted gaze accumulated across attempts"):return
	await wait_ticks(50)
	if not insist(level.demo_locked and not level.archive.note and level.hale.position.z<8.95,"B3 solo lock claimed a paired trial"):return
	if not await walk([[23.85,11.3],[23.85,9.8]],FAR_PLATE):return
	if not await walk([[20.95,9.8],[20.95,7.75],[24.65,7.75]]):return
	if not insist(not level.learned and count_event("fact","solo_crossing_b3")==0 and not level.crossing_locked,
		"Folding back banked a partial crossing"):return
	level.eye.look_at(Vector3(24.65,1.57,4.));await wait_ticks(86)
	if not insist(level.observers==1 and not level.archive.paired,"Hale alone counted as overlap on revisit"):return
	level.eye.look_at(PLATE);await wait_ticks(103)
	if not insist(level.archive.paired and level.archive.note and count_event("fact","handoff_b2")==1,
		"Actual B2 overlap and handoff did not complete the previously witnessed B3 comparison"):return
	level.eye.rotation=Vector3.ZERO
	if not await walk([[20.95,7.75],[20.95,9.8],[23.85,9.8]]):return
	level.eye.look_at(PLATE);await wait_ticks(150)
	if not insist(level.demo_locked and not level.learned and level.hale.position.z<8.95,"Repeat lock moved Hale through the door or counted as a crossing"):return
	if not await walk([[23.85,14.12]],FAR_PLATE):return
	if not insist(level.learned and count_event("fact","solo_lock_b3")==1 and count_event("fact","solo_crossing_b3")==1
		and count_event("fact","hale_saw_crossing_b3")==1 and level.cues.has("hale_evidence"),"Repeated trial or local Hale witness was not recorded correctly"):return
	if not insist(checked_witness_cone,"No live crossing sample exercised the witness cone"):return
	if not export_trace("foldback-repeat"):return
	print("PASS: continuous B2 skip and B5 release; interrupted gaze; folded-back crossing; real window and repeat crossing; deduplicated evidence")
	level.queue_free()
	for i in 26:
		OS.delay_msec(8);await process_frame
	quit()

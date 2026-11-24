extends SceneTree
## Reproducible first-person capture. Run this script with --write-movie for a real Forward+ recording.
var level
var look_yaw:float
var pitch_goal:=0.
var precise_look:=false
var gaze_lock_point:=Vector3.INF

func _initialize()->void: run.call_deferred()

func check(ok:bool,message:String)->bool:
	if not ok:
		Input.action_release("move_up");Input.action_release("expedition_quiet")
		push_error(message);quit(1)
	return ok

func go(x:float,z:float,limit:=1400)->bool:
	var target:=Vector3(x,0,z)
	Input.action_press("move_up")
	var last:=Vector3.INF
	var stalled:=0
	for i in limit:
		if not check(level.retry<=0.,"Gameplay failure: "+level.notice):return false
		if level.finished:
			Input.action_release("move_up");return true
		var p:Vector3=level.walker.position
		var d:=target-p;d.y=0.
		if d.length()<.12:
			Input.action_release("move_up");return true
		if p.distance_to(last)<.004:stalled+=1
		else:stalled=0;last=p
		if stalled>90:break
		var yaw:=atan2(-d.x,-d.z)
		if gaze_lock_point.is_finite():
			var sight:Vector3=gaze_lock_point-level.eye.global_position
			look_yaw=atan2(-sight.x,-sight.z)
			level.walker.rotation.y=yaw;level.eye.rotation.y=angle_difference(yaw,look_yaw)
			level.eye.rotation.x=atan2(sight.y,Vector2(sight.x,sight.z).length())
			await physics_frame
			continue
		look_yaw=yaw if precise_look else lerp_angle(look_yaw,yaw,.16)
		level.walker.rotation.y=yaw
		level.eye.rotation.y=angle_difference(yaw,look_yaw)
		level.eye.rotation.x=pitch_goal if precise_look else lerpf(level.eye.rotation.x,pitch_goal,.10)
		await physics_frame
	return check(false,"Blocked at %s approaching %s"%[level.walker.position,target])

func wait_frames(n:int)->void:
	for i in n:await physics_frame

func press(code:Key)->void:
	var e:=InputEventKey.new();e.physical_keycode=code;e.pressed=true
	Input.parse_input_event(e)
	var up:=InputEventKey.new();up.physical_keycode=code
	Input.parse_input_event(up)

func open_order(id:String,frames:=72)->int:
	press(KEY_Q)
	await wait_frames(2)
	if not check(level.wheel_open,"Expected Hale order wheel for %s; focused %s at %s"%[id,level.focus(),level.walker.position]):return -1
	for i in level.wheel.options.size():
		if level.wheel.options[i].id==id:
			await wait_frames(frames)
			return KEY_1+i
	check(false,"Missing Hale order: "+id)
	return -1

func look_at_point(target:Vector3,frames:=22)->void:
	for i in frames:
		var d:Vector3=target-level.eye.global_position
		var yaw:=atan2(-d.x,-d.z)
		look_yaw=lerp_angle(look_yaw,yaw,.21)
		level.eye.rotation.y=angle_difference(level.walker.rotation.y,look_yaw)
		level.eye.rotation.x=lerpf(level.eye.rotation.x,atan2(d.y,Vector2(d.x,d.z).length()),.21)
		await physics_frame

func interact(target:Vector3,id:String,frames:=35)->bool:
	await look_at_point(target,frames)
	if not check(level.focus()==id,"Expected %s; focused %s at %s"%[id,level.focus(),level.walker.position]):return false
	press(KEY_E);await wait_frames(4)
	return true

func run()->void:
	level=preload("res://scenes/expedition_01/Expedition.tscn").instantiate();root.add_child(level)
	look_yaw=level.walker.rotation.y
	await wait_frames(642)
	press(KEY_1);await wait_frames(335);press(KEY_RIGHT);await wait_frames(175)
	if not check(level.manual.visible and "观察窗交班记录" in level.page.get_parsed_text(),"Final31 manual page 2 was not shown"):return
	press(KEY_1)
	await wait_frames(45)
	if not await go(35.55,0,650):return
	if not await interact(Vector3(36.,1.57,0),"gate",50):return
	await wait_frames(210)
	var gate_order:=await open_order("try_gate")
	if gate_order<0:return
	press(gate_order)
	await wait_frames(14)
	for f in 240:
		if level.hale_gate_guide>0:break
		await look_at_point(level.hale_gate_target+Vector3.UP*1.34,1)
	if not check(level.cues.has("gate") and level.subtitle_id=="hale_gate" and level.hale_gate_guide>0,"Hale did not start guiding to the green door"):return
	for f in 195:
		await look_at_point(level.hale.position+Vector3.UP*1.30,1)
		if level.hale_gate_guide==3:break
	if not check(level.hale_gate_guide==3 and level.hale.position.distance_to(level.HALE_ARCHIVE_LOOKOUT)<.10
			and level.eye.is_position_in_frustum(level.hale.position+Vector3.UP*1.30),"Hale did not reach the green door in frame"):return
	print("GATE GUIDE at green door, in frame (movie frame %d)"%Engine.get_process_frames())
	await look_at_point(level.hale.position+Vector3.UP*1.30,55)
	for point in [[31,0],[31,4.9],[26.7,4.9],[25.7,5.5],[25.7,7.75],[24.65,7.75],[20.95,7.75],[20.95,9.8],[23.85,9.8],[23.85,12],[23.85,14.12],[25.5,14.1],[28.3,14.1],[34,14.1],[38.9,14.1],[38.9,10],[36.6,8.5]]:
		if not await go(point[0],point[1]):return
		if point==[24.65,7.75]:
			# Let Hale see the plate first. We keep looking when he yields.
			await look_at_point(level.archive.WINDOW+Vector3.UP*1.48,26)
			for f in 235:
				if level.prior_seer==level.contracts.Seer.HALE:break
				await physics_frame
			if not check(level.prior_seer==level.contracts.Seer.HALE,"Hale did not open the B2 hand-off"):return
			await look_at_point(level.archive.PLATE,23)
			var dual:=false
			for f in 285:
				if level.observers==2 and level.overload_blend>.8:dual=true
				if not check(level.retry<=0.,"B2 gaze failed: "+level.notice):return
				if level.archive.paired and level.observers==1 and level.contracts.trust_notes.has("contract_a"):break
				await physics_frame
			if not check(dual and level.archive.paired and level.observers==1 and level.contracts.trust_notes.has("contract_a"),"Missing witnessed B2 overlap and legal hand-off"):return
			print("B2 CONTROL %.2fs"%level.phase)
			await look_at_point(level.hale.position+Vector3.UP*1.43,47)
		if point==[20.95,7.75]:
			await look_at_point(level.archive.DOOR+Vector3.UP*1.48,100)
			# Wait for the B2 line to clear instead of cutting it off with the ward cue.
			for frame in 300:
				if level.cues.has("ward_paired"):break
				await physics_frame
			if not check(level.cues.has("ward_paired") and not level.cues.has("ward_unseen") and level.hale.position.z<8.95,"Hale did not stage the doorway warning"):return
			await wait_frames(78)
		if point==[23.85,9.8]:
			await look_at_point(Vector3(23.85,.11,12.02),55)
			if not check(level.cues.has("settling") and level.observers==1 and level.overload_blend<.05 and not level.demo_locked,"Solo gaze should gather amber ripples without a red overload"):return
			await wait_frames(118)
			if not check(level.demo_locked and level.archive.note and not level.learned and level.hale.position.z<8.95,"B3 should lock after the sustained gaze, before crossing"):return
			print("B3 PROOF %.2fs"%level.phase)
			gaze_lock_point=Vector3(23.85,.11,13.0)
		if point==[23.85,14.12]:gaze_lock_point=Vector3.INF
		if point==[25.5,14.1]:
			pitch_goal=0.;precise_look=false
			if not check(level.learned,"Missing crossing proof"):return
			await wait_frames(7)
			if not check(level.archive.note and level.archive.facts.has_fact("solo_crossing_b3") and level.archive.facts.has_fact("hale_saw_crossing_b3") and level.cues.has("hale_evidence"),"Missing field evidence after the witnessed experiment"):return
			await look_at_point(Vector3(29.,1.55,14.1),55)
			press(KEY_1);await wait_frames(280)
			if not check(level.manual.visible and level.page.get_parsed_text().contains("手写批注") and not level.caption_toast.visible,"Missing handwritten annotation"):return
			if not check(level.captions.entries.is_empty(),"Old drama captions survived opening the book"):return
			press(KEY_1);await wait_frames(40)
		if point==[28.3,14.1]:
			var ports:Array=level.Relay.PORTS
			for loft in [[29.9,14.1],[29.9,16.45],[ports[0].x,16.45],[ports[0].x,16.73]]:
				if not await go(loft[0],loft[1]):return
			if not await interact(ports[0],"relay"):return
			await wait_frames(155)
			if not check(level.service_signal.heard,"Missing relay reply"):return
			if not await go(ports[1].x,16.73):return
			if not await interact(ports[1],"relay"):return
			await wait_frames(35)
			if not await go(level.Relay.HATCH.x,16.60):return
			if not await interact(level.Relay.HATCH,"clock"):return
			await wait_frames(75)
			for loft in [[39.05,16.45],[39.05,14.1]]:
				if not await go(loft[0],loft[1]):return
		if point==[34,14.1]:
			if not await interact(Vector3(34.14,.5,14.67),"loot",55):return
			await wait_frames(60)
	await look_at_point(Vector3(36.34,2.67,7.34),49)
	if not await interact(Vector3(36.3,1.35,7.72),"lever",39):return
	if not check(level.released and level.equipped,"Archive state incomplete"):return
	await wait_frames(65)
	for point in [[39,10.1],[48.8,10.1]]:
		if not await go(point[0],point[1]):return
	Input.action_press("expedition_quiet")
	var window:Vector3=level.kit.north_spot.global_position+Vector3.UP*1.62
	await look_at_point(Vector3(58.,.15,10.10),94)
	if not check(level.cues.has("shaft_doubt"),"Missing Hale's bridge objection"):return
	await look_at_point(window,40)
	for f in 225:
		if level.hale.position.distance_to(level.walker.position)<6. and level.archive.beat==level.archive.Beat.DONE:break
		await physics_frame
	var north_order:=await open_order("north")
	if north_order<0:return
	var ordered:float=level.phase;press(north_order);await wait_frames(2)
	if not check(level.posting and level.north_pause>0. and level.captions.entries.has("我") and not level.north_beacon.visible,"North-window order or stacked speakers missing"):return
	# Keep the window off camera at arrival to prove the remote message is sight-gated.
	await look_at_point(level.eye.global_position+Vector3.LEFT*10.,28)
	for i in 240:
		if not check(level.retry<=0.,"Gameplay failure while Hale was traveling"):return
		if level.holding:break
		await physics_frame
	if not check(level.holding and not level.posting and level.command_path.is_empty()
			and level.hale.global_position.distance_to(level.kit.north_spot.global_position)<.05,
			"Hale did not reach the north window"):return
	if not check(level.sees_span(level.hale.global_position+Vector3.UP*1.62),"Hale reached the north window without a sightline to the bridge"):return
	print("NORTH WINDOW %.2fs"%(level.phase-ordered))
	if not check(level.phase-ordered<=4.05,"Hale took more than four seconds to reach the north window"):return
	var nearby:bool=level.hale_in_earshot()
	if not nearby:
		if not check(level.north_beacon.is_visible_in_tree() and not level.eye.is_position_in_frustum(level.north_beacon.global_position)
				and not level.north_ready_signaled,"The remote north-window signal announced itself off camera"):return
	await look_at_point(window,80)
	var voice_ready:bool=level.captions.entries.get("Hale",{}).get("id","")=="north_ready"
	if nearby:
		if not check(voice_ready,"Missing nearby north-window confirmation"):return
	else:
		if not check(not voice_ready and level.north_beacon.is_visible_in_tree()
				and level.eye.is_position_in_frustum(level.north_beacon.global_position)
				and level.caption_toast.is_visible_in_tree() and level.caption_toast.text=="北窗的灯亮了。",
				"Missing visible north-window signal after looking at the beacon"):return
		print("NORTH SIGNAL beacon seen (Hale %.2f m away)"%level.hale.global_position.distance_to(level.walker.global_position))
	if not await interact(level.hunter.BAIT,"throw",30):return
	if not check(level.distraction>0.,"Lure not thrown"):return
	await wait_frames(92)
	if not check(level.hunter.bait_answered and level.polish.bait_time>0.,"Missing bait response"):return
	await look_at_point(Vector3(70.95,1.8,10.1),19)
	if not await go(70.95,10.1):return
	if not await interact(level.kit.core.position,"core",26):return
	Input.action_release("expedition_quiet");press(KEY_SHIFT);await wait_frames(3)
	if not check(level.collected,"Source core not recovered"):return
	for point in [[70.95,11.45],[73.35,11.45],[73.35,9.12]]:
		if not await go(point[0],point[1]):return
	pitch_goal=-.18
	for i in range(1,42):
		var a:=PI*.5+TAU*i/41.
		if not await go(73.35+1.02*cos(a),8.1+1.02*sin(a),250):return
	pitch_goal=0.
	if not check(level.walker.position.y>4.5,"Missed the upper landing"):return
	if not await go(73.35,12.15):return
	await wait_frames(15)
	if not await interact(level.kit.leaf.global_position,"return",44):return
	await wait_frames(30)
	print("GREEN DOOR %.2fs"%level.phase)
	var heard_tail:=false
	for point:Vector2 in level.kit.RETURN_PATH:
		if not await go(point.x,point.y,900):return
		if level.gallery_bell.playing and level.gallery_impact.playing:heard_tail=true
		if not check(level.polish.fade_a<.03,"Unexpected fade in the service gallery"):return
	if not check(heard_tail and not level.gallery_bell.playing and not level.gallery_impact.playing and level.shortcut_used and level.walker.position.distance_to(Vector3(43.8,0,10.1))<.4,"Return gallery did not reach B5"):return
	for point in [[38.7,10.1],[38.7,7.2],[38.7,0],[34,0],[7.6,0]]:
		if not await go(point[0],point[1]):return
	press(KEY_SHIFT);await wait_frames(14)
	for i in 430:
		if i%24==0 and level.hale.position.x<22.:
			await look_at_point(level.hale.position+Vector3.UP*1.44,18)
		if level.reunited:break
		await physics_frame
	await wait_frames(155)
	if not await go(1.6,0):return
	await wait_frames(15)
	if not await interact(Vector3(.37,1.5,0),"exit",40):return
	await wait_frames(35)
	if not await go(-.95,-.25):return
	for i in 8:
		await look_at_point(level.hale.position+Vector3.UP*1.15,8)
		if level.hale.position.x< -2.15:break
	if not check(level.hale.position.x< -1.85,"Hale did not walk into the airlock foyer"):return
	if not check(not level.finished,"Airlock finished before entering the warm hall"):return
	await look_at_point(Vector3(-3.89,1.75,0),28)
	if not await go(-2.95,0):return
	for i in 950:
		if level.finished:break
		if not level.reunited and i%30==0 and level.hale.position.x<11.:
			await look_at_point(level.hale.position+Vector3.UP*1.45,18)
		await physics_frame
	if not check(level.finished and level.reunited,"Evacuation or Hale reunion did not finish"):return
	print("ENDING %.2fs"%level.phase)
	for i in 310:
		if not check(level.polish.end_card.modulate.a<.01 or level.polish.fade_a>.999,"Evacuation text appeared ahead of full blackout"):return
		await physics_frame
	if not check(level.polish.fade_a>.999 and level.polish.end_card.modulate.a>.999,"Blackout and ending card did not complete"):return
	print("PASS: Expedition complete; archive proof, signal loft, shaft crossing, reunion and blackout verified.")
	level.queue_free();level=null
	await process_frame
	# Fixed-FPS headless runs may exit before the asynchronous audio decoder drains.
	if DisplayServer.get_name()=="headless":
		for i in 26:
			OS.delay_msec(8)
			await process_frame
	quit(0)

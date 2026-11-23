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
	await wait_frames(270)
	press(KEY_1);await wait_frames(320);press(KEY_RIGHT);await wait_frames(205);press(KEY_1)
	await wait_frames(45)
	if not await go(35.55,0,650):return
	await wait_frames(50);press(KEY_E);await wait_frames(210);press(KEY_Q)
	await wait_frames(14);await look_at_point(level.hale_gate_target+Vector3.UP*1.34,120);await wait_frames(130)
	if not check(level.cues.has("gate") and level.subtitle_id=="hale_gate","Missing Hale's gate response"):return
	for point in [[31,0],[31,4.9],[26.7,4.9],[25.7,5.5],[25.7,7.75],[24.65,7.75],[20.95,7.75],[20.95,9.8],[23.85,9.8],[23.85,12],[23.85,14.12],[25.5,14.1],[28.3,14.1],[34,14.1],[38.9,14.1],[38.9,10],[36.6,8.5]]:
		if not await go(point[0],point[1]):return
		if point==[24.65,7.75]:
			await look_at_point(Vector3(23.85,.10,12.02),100)
		if point==[23.85,9.8]:
			await look_at_point(Vector3(23.85,.11,12.02),55)
			if not check(level.cues.has("red") and not level.demo_locked,"B3 did not show the unstable phase before lock"):return
			await wait_frames(118)
			if not check(level.demo_locked and not level.learned,"B3 should lock after the sustained gaze, before crossing"):return
			gaze_lock_point=Vector3(23.85,.11,13.0)
		if point==[23.85,14.12]:gaze_lock_point=Vector3.INF
		if point==[25.5,14.1]:
			pitch_goal=0.;precise_look=false
			if not check(level.learned,"Missing crossing proof"):return
			await wait_frames(40)
			if not check(level.captions.entries.has("") and level.captions.entries.has("Hale"),"Expected stacked thought and Hale subtitle"):return
			await look_at_point(Vector3(29.,1.55,14.1),55)
			press(KEY_1);await wait_frames(280)
			if not check(level.manual.visible and level.page.get_parsed_text().contains("若两目交错恐生变故") and not level.caption_toast.visible,"Missing handwritten annotation"):return
			if not check(level.captions.entries.is_empty(),"Old drama captions survived opening the book"):return
			press(KEY_1);await wait_frames(40)
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
	await look_at_point(window,40);var ordered:float=level.phase;press(KEY_Q);await wait_frames(2)
	if not check(level.posting and level.captions.entries.has("我") and level.captions.entries.has("Hale"),"North-window order or stacked speakers missing"):return
	for i in 240:
		if not check(level.retry<=0.,"Gameplay failure while Hale was traveling"):return
		if level.holding:break
		# Follow his lamp during the climb; keep the window in frame as he approaches it.
		if i%15==0:
			var subject:Vector3=level.hale.position+Vector3.UP*1.48
			if subject.distance_to(level.eye.global_position)>.7:await look_at_point(subject,6)
		await physics_frame
	if not check(level.holding and level.subtitle_id=="north_ready","Hale did not reach the north window"):return
	print("NORTH WINDOW %.2fs"%(level.phase-ordered))
	if not check(level.phase-ordered<=4.05,"Hale took more than four seconds to reach the north window"):return
	await look_at_point(window,80)
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
	for point:Vector2 in level.kit.RETURN_PATH:
		if not await go(point.x,point.y,900):return
		if not check(level.polish.fade_a<.03,"Unexpected fade in the service gallery"):return
	if not check(level.shortcut_used and level.walker.position.distance_to(Vector3(43.8,0,10.1))<.4,"Return gallery did not reach B5"):return
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
	print("PASS: Expedition complete; split captions, annotated handbook, north-window arrival, physical door crossing, reunion and airlock verified.")
	for i in 310:
		if not check(level.polish.end_card.modulate.a<.01 or level.polish.fade_a>.999,"Evacuation text appeared ahead of full blackout"):return
		await physics_frame
	if not check(level.polish.fade_a>.999 and level.polish.end_card.modulate.a>.999,"Blackout and ending card did not complete"):return
	level.queue_free();level=null
	await process_frame
	quit(0)

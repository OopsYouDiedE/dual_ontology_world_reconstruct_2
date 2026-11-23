extends SceneTree
## A continuous capsule traversal. Navigation targets are floor coordinates, never teleports.
var level
var failures:=0
var gaze:=false
var south_only:=false
func _initialize()->void:run.call_deferred()
func go(x:float,z:float,limit:=2000,portal:=false)->bool:
	var target:=Vector3(x,0,z);Input.action_press("move_up")
	for i in limit:
		if level.finished or (portal and level.shortcut_used):Input.action_release("move_up");return true
		var p:Vector3=level.walker.position;var d:Vector3=target-p;d.y=0
		if d.length()<.12:Input.action_release("move_up");return true
		level.walker.rotation.y=atan2(-d.x,-d.z)
		if gaze:level.eye.look_at(Vector3(23.85,.11,13.0))
		await physics_frame
	for k in level.walker.get_slide_collision_count():print(level.walker.get_slide_collision(k).get_collider().get_path(),level.walker.get_slide_collision(k).get_normal())
	Input.action_release("move_up");push_error("Blocked at %s approaching %s"%[level.walker.position,target]);failures+=1;return false
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
	return true
func run()->void:
	south_only=OS.get_cmdline_user_args().has("--south")
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
	level.reset_at_checkpoint();level.walker.rotation.y=-PI/2;level.tutorial_room=false
	if not audit():quit(1);return
	for point in [[31,0],[31,4.9],[26.7,4.9],[25.7,5.5],[25.7,7.75],[24.65,7.75],[20.95,7.75],[20.95,9.8],[23.85,9.8],[23.85,12],[23.85,14.12],[25.5,14.1],[28.3,14.1],[34,14.1],[38.9,14.1],[38.9,10],[36.6,8.5]]:
		if not await go(point[0],point[1]):quit(1);return
		if absf(point[0]-24.65)<.01:
			level.holding=true;level.hale.rotation.y=PI
			level.eye.look_at(Vector3(24.65,1.57,4.0));for frame in 95:await physics_frame
			if level.observers!=0 or level.kit.test_board.get_child(0).collision_layer!=0 or level.kit.test_board.position.y>-.53:push_error("Unwatched demo stayed up");quit(1);return
			level.eye.look_at(Vector3(23.85,.10,12.02));for frame in 90:await physics_frame
			if level.observers!=1 or level.kit.test_board.get_child(0).collision_layer==0 or level.kit.test_board.position.y<.04:push_error("Watched demo stayed down");quit(1);return
			level.hale.position=Vector3(24.5,0,7.7);level.hale.rotation.y=0
			for frame in 3:await physics_frame
			if level.observers!=2:push_error("Missing double exposure");quit(1);return
			level.holding=false;level.trail.clear();level.eye.rotation=Vector3.ZERO
		if point==[23.85,9.8]:
			level.eye.look_at(Vector3(23.85,.11,12.02))
			for f in 44:await physics_frame
			if level.demo_locked or not level.cues.has("red"):push_error("Missing early red phase");quit(1);return
			for f in 116:await physics_frame
			if not level.demo_locked:push_error("Missing timed lock");quit(1);return
			gaze=true
		if point==[23.85,14.12]:gaze=false;level.eye.rotation=Vector3.ZERO
		if absf(point[0]-25.5)<.01:
			if not level.learned:push_error("Missing crossing proof");quit(1);return
			for f in 46:await physics_frame
			if not level.captions.entries.has(""):push_error("Missing B3 inner thought");quit(1);return
		if absf(point[0]-28.3)<.01:
			for bypass in [[29.35,14.1],[29.35,12.1],[36.2,12.1],[29.35,12.1],[29.35,14.1]]:
				if not await go(bypass[0],bypass[1]):quit(1);return
		if absf(point[0]-34)<.01 and not south_only:level.eye.look_at(Vector3(34.14,.5,14.67));level.use()
	level.eye.look_at(Vector3(36.3,1.35,7.72));level.use();if not (level.learned and level.released and level.equipped!=south_only):push_error("Archive state incomplete");quit(1);return
	for point in [[39,10.1],[48.8,10.1]]:
		if not await go(point[0],point[1]):quit(1);return
	Input.action_press("expedition_quiet");var oil_before:float=level.oil
	for i in range(33):
		var pt:Vector3=level.kit.polar(13.3,PI*(1.-i/32.),0.)
		if not await go(pt.x,pt.z):quit(1);return
	if level.oil>oil_before-15.:push_error("Unpriced southern bypass");quit(1);return
	if not south_only:
		for i in range(33):
			var pt:Vector3=level.kit.polar(13.3,PI*i/32.,0.)
			if not await go(pt.x,pt.z):quit(1);return
		level.eye.look_at(level.kit.polar(12.45,1.5*PI,6.42));level.order();for i in 950:await physics_frame
		if not level.holding:push_error("Hale did not reach north window");quit(1);return
		level.eye.rotation=Vector3.ZERO;level.walker.rotation.y=-PI/2;level.eye.look_at(level.hunter.BAIT);level.use();level.eye.rotation=Vector3.ZERO;if level.distraction<=0:push_error("Lure not thrown");quit(1);return
	if not await go(72.9 if south_only else 70.95,10.1):quit(1);return
	level.eye.look_at(level.kit.core.position);level.use();Input.action_release("expedition_quiet");level.running=true;if not level.collected:quit(1);return
	if not await go(72.9 if south_only else 70.95,11.45):quit(1);return
	if not await go(73.35,11.45):quit(1);return
	if not await go(73.35,9.12):quit(1);return
	for i in range(1,42):
		var a:=PI*.5+TAU*i/41.
		if not await go(73.35+1.02*cos(a),8.1+1.02*sin(a),250):quit(1);return
	if level.walker.position.y<4.5:push_error("Missed upper landing: %s"%level.walker.position);quit(1);return
	if not await go(73.35,12.1):quit(1);return
	for i in 15:await physics_frame
	level.eye.look_at(level.kit.leaf.global_position);level.use()
	if not level.shortcut_open:push_error("Return leaf out of reach");quit(1);return
	for i in 35:await physics_frame
	if not await go(77.08,12.45,200,true):quit(1);return
	for i in 30:await physics_frame
	if level.walker.position.x>40:push_error("Return threshold did not transfer player");quit(1);return
	for point in [[38.7,7.2],[38.7,0],[34,0],[1.5,0]]:
		if not await go(point[0],point[1]):quit(1);return
	var completed:=[false];level.returned.connect(func():completed[0]=true)
	for i in 15:await physics_frame
	level.eye.look_at(Vector3(.37,1.5,0));level.use()
	for i in 35:await physics_frame
	if not await go(-2.95,0):quit(1);return
	for i in 950:
		if completed[0]:break
		await physics_frame
	if not completed[0]:push_error("Exit signal missing");quit(1);return
	print("PASS: south walkway evacuation without supplies, lure or north assignment." if south_only else "PASS: A1 → B1 → B2 → B3 → B4 → B5 → C1 → C2 → C4 → upper return → B5 → A1 exit; Hale watches through glazing.")
	level.queue_free()
	for i in 12:await process_frame
	quit(0)

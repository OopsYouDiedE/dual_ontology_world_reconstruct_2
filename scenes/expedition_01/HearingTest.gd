extends SceneTree
# Exercise the warning and hearing timers independently of movement steering.
func _initialize()->void:run.call_deferred()
func demand(ok:bool,msg:String)->bool:
	if not ok:push_error(msg);quit(1)
	return ok
func run()->void:
	var level=preload("Expedition.tscn").instantiate();root.add_child(level);await physics_frame
	var h=level.hunter;h.wake();var pos:=Vector3(49,0,10.1);var died:=false;var hunt_frames:=0
	for i in 180:
		died=h.step(1./60,pos,true,false,0,false,level.sounds);if h.state=="hunt":hunt_frames+=1
		if died:break
	if not demand(died and hunt_frames>=40,"No warned lethal approach within three seconds"):return
	h.wake()
	for i in 90:h.step(1./60,pos,false,false,0,false,level.sounds)
	if not demand(h.state=="patrol","Quiet player triggered hunter"):return
	h.step(1./60,pos,false,true,0,false,level.sounds)
	if not demand(h.state=="investigate","Metal footsteps ignored"):return
	for i in 245:h.step(1./60,pos,false,false,0,false,level.sounds)
	if not demand(h.state=="patrol","Hunter did not calm down"):return
	h.throw_from(pos);for i in 720:
		if not demand(not h.step(1./60,pos,true,true,12.-i/60.,false,level.sounds),"Lure lost priority"):return
		if i==42 and not demand(not h.bait_answered,"Hunter moved before the two beats"):return
		if i==92 and not demand(h.bait_answered,"Hunter did not respond after the two beats"):return
	if not demand(h.position.distance_to(h.BAIT)<.1,"Hunter did not reach lure"):return
	level.released=true;level.checkpoint_oil=51;level.checkpoint_item=true;level.collected=true;level.fail("test");for i in 184:await physics_frame
	if not demand(not level.collected and level.equipped and level.walker.position.x<41 and level.kit.core.visible,"Checkpoint inventory/position invalid"):return
	print("PASS: quiet / metal / silence / warned hunt / 12s lure / B5 restore")
	level.queue_free()
	for i in 26:
		OS.delay_msec(8)
		await process_frame
	quit()

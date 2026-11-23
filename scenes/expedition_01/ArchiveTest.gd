extends SceneTree
## A player can bypass the observation window spatially but cannot file either
## claim in the manual without both trials. Verify recovery after a missed cue.
func _initialize()->void:run.call_deferred()
func wait_ticks(n:int)->void:
	for i in n:await physics_frame
func insist(ok:bool,why:String)->bool:
	if not ok:push_error(why);quit(1)
	return ok
func run()->void:
	var level=preload("Expedition.tscn").instantiate();root.add_child(level);await physics_frame
	level.walker.position=Vector3(23.85,0.,9.8)
	level.eye.look_at(level.archive.PLATE)
	await wait_ticks(159)
	if not insist(level.demo_locked and not level.archive.note and not level.learned,"B3 wrote a two-gaze conclusion without B2"):return
	level.walker.position=Vector3(24.65,0.,7.75);level.hale.position=Vector3(25.5,0.,7.80)
	level.eye.look_at(Vector3(24.65,1.57,4.))
	await wait_ticks(86)
	if not insist(level.observers==1 and not level.archive.paired,"Hale alone triggered the controlled overlap"):return
	level.eye.look_at(level.archive.PLATE)
	await wait_ticks(58)
	if not insist(level.archive.paired and level.observers==1 and not level.archive.note,"Missed the recoverable window trial"):return
	level.walker.position=Vector3(23.85,0.,9.8)
	level.eye.look_at(level.archive.PLATE)
	await wait_ticks(102)
	level.eye.look_at(Vector3(23.85,1.57,5.))
	await wait_ticks(5)
	level.eye.look_at(level.archive.PLATE)
	await wait_ticks(105)
	if not insist(not level.archive.note, "An interrupted gaze counted as sustained proof"):return
	await wait_ticks(50)
	if not insist(level.archive.note and not level.learned and level.hale.position.z<8.95,"The recovered comparison did not file the annotation from outside"):return
	print("PASS: skipped B2 cannot write proof; retry the real window overlap; interrupted B3 gaze must restart.")
	level.queue_free()
	for i in 26:
		OS.delay_msec(8)
		await process_frame
	quit()

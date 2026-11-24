extends SceneTree
## --headless --path . --script res://scenes/expedition_01/ShaftRecoveryTest.gd
var level
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:failures += 1

func feet() -> Vector3:
	return level.walker.position

func place(point: Vector3) -> void:
	level.walker.position = point
	level.walker.velocity = Vector3.ZERO
	level.retry = 0.

func stair(index: float) -> Vector3:
	var angle := PI * .5 + TAU * index / 41.
	return Vector3(level.kit.WEST_STAIR_X + cos(angle), 4.8 * index / 41., level.kit.CZ - 2. + sin(angle))

func walk_to(target: Vector3, radius: float, limit: int) -> bool:
	for frame in limit:
		var offset := target - feet()
		var flat := Vector2(offset.x, offset.z)
		if level.retry > 0. or offset.y > 1.:break
		if flat.length() < radius:
			Input.action_release("move_up")
			return true
		level.walker.rotation.y = atan2(-flat.x, -flat.y)
		Input.action_press("move_up", clampf(flat.length() * 4., .25, 1.))
		await physics_frame
	Input.action_release("move_up")
	print("Walk stopped at ", feet(), " toward ", target, " retry=", level.retry)
	return false

func run() -> void:
	level = preload("Expedition.tscn").instantiate()
	root.add_child(level)
	if level.captions.typeface == null:
		push_error("Expedition fixture failed to initialize")
		quit(1)
		return
	# Start beside the bridge after release, before taking the core.
	level.released = true
	level.hunter.wake()
	level.hale_hold = true
	place(Vector3(55., .5, 7.))
	var crossed_in_air := false
	for frame in 120:
		await physics_frame
		if feet().y < -1.8 and not level.walker.is_on_floor():crossed_in_air = true
		if level.retry > 0. or level.walker.is_on_floor():break
	check(crossed_in_air and level.retry == 0., "actual free fall passes -1.8 inside the caisson")
	check(level.walker.is_on_floor() and absf(feet().y - level.kit.SHAFT_FLOOR_Y) < .06 and level.retry == 0., "player lands on the recovery floor without retry")
	Input.action_press("expedition_quiet")
	var foot := stair(-85.)
	var approach := stair(-87.)
	var route_ok := await walk_to(Vector3(approach.x, foot.y, approach.z), .12, 550)
	if route_ok:
		for index in range(-85, 2):
			if not await walk_to(stair(float(index)), .12, 65):
				route_ok = false
				break
	check(route_ok and feet().y > -.2 and level.retry == 0., "normal movement climbs the full west spiral from the floor")
	if route_ok:
		route_ok = await walk_to(Vector3(48.5, 0., 10.75), .16, 180)
	for frame in 12:await physics_frame
	print("Landing: ", feet(), " grounded=", level.walker.is_on_floor())
	check(route_ok and level.walker.is_on_floor() and absf(feet().y) < .10 and level.retry == 0., "player steps back onto the west landing and stays grounded")
	Input.action_release("expedition_quiet")
	place(Vector3(20., .4, -20.))
	for frame in 90:
		await physics_frame
		if level.retry > 0.:break
	check(level.retry > 0. and feet().y < -1.8 and level.fail_reason == "坠入源井", "actual out-of-bounds fall still triggers retry")
	level.free()
	# Let the audio mixer release playbacks before terminating the test host.
	for frame in 26:
		OS.delay_msec(8)
		await process_frame
	quit(0 if failures == 0 else 1)

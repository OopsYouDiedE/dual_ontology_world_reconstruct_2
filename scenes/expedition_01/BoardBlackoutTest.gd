extends SceneTree
## Run headless at 60 Hz; exercise live gaze rays and CharacterBody3D collisions.
const DT := 1. / 60.
var level
var failures := 0
var blackout_held := true

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	print("PASS " if ok else "FAIL ", label)
	if not ok:failures += 1

func feet() -> Vector3:
	return level.walker.position

func active_board() -> bool:
	return level.kit.test_board.visible and level.kit.test_board.get_child(0).collision_layer == 3

func dead_board() -> bool:
	return not level.kit.test_board.visible and level.kit.test_board.get_child(0).collision_layer == 0

func gaze(player: bool, hale: bool) -> void:
	var target: Vector3 = level.archive.PLATE
	level.eye.look_at(target if player else level.eye.global_position + Vector3.BACK)
	level.archive.gaze = target - level.hale.position - Vector3.UP * 1.57 if hale else Vector3.ZERO

func tick(planar := Vector3.ZERO) -> void:
	await physics_frame
	var was_blackout: bool = level.contracts.a_state == "blackout"
	level.walker.velocity = Vector3(planar.x, level.walker.velocity.y - 19. * DT, planar.z)
	level.walker.move_and_slide()
	level.rules(DT)
	if was_blackout or level.contracts.a_state == "blackout":
		blackout_held = blackout_held and dead_board() and level.retry == 0. and level.polish.fail_time == 0.

func walk_to(x: float, z: float, budget: int) -> bool:
	for frame in budget:
		var offset := Vector3(x - feet().x, 0., z - feet().z)
		if offset.length() < .10:return true
		await tick(offset.normalized() * minf(3.8, offset.length() / DT))
	return false

func recover() -> void:
	for frame in 190:
		if level.contracts.a_state != "blackout":break
		await tick()
	await tick()

func run() -> void:
	level = preload("Expedition.tscn").instantiate()
	root.add_child(level)
	level.set_physics_process(false)
	if level.captions.typeface == null:
		push_error("Expedition fixture failed to initialize")
		quit(1)
		return
	await physics_frame
	level.walker.position = Vector3(26.89, .03, 8.53)
	level.hale.position = level.archive.WINDOW
	gaze(true, false)
	await tick()
	gaze(true, true)
	await tick()
	check(level.contracts.a_state == "overlap" and active_board() and level.overload_blend > 0., "window: real dual gaze enters warning overlap")
	gaze(true, false)
	await tick()
	check(level.contracts.a_state == "blackout" and dead_board(), "wrong seer withdrawal extinguishes the plate on the same tick")
	for frame in 12:await tick()
	check(level.retry == 0. and level.walker.is_on_floor() and absf(feet().y) < .05, "reported window position stays on solid ground without death")
	check(level.captions.entries.get("Hale", {}).get("id") == "breach_a", "nearby Hale can react to blackout")
	gaze(true, true)
	await recover()
	check(active_board() and level.contracts.a_state == "overlap", "timer expires and a fresh live handoff can start")
	# Clear the window overlap before staging the player directly on supported board.
	gaze(false, true)
	for frame in 45:await tick()
	check(level.contracts.a_state == "idle" and level.contracts.trust_notes.has("contract_a"), "normal custody handoff works after recovery")
	level.walker.position = Vector3(23.85, .12, 11.75)
	level.walker.velocity = Vector3.ZERO
	level.hale.position = Vector3(23.85, 0., 14.85)
	gaze(true, false)
	for frame in 6:await tick()
	check(level.walker.is_on_floor() and feet().y > .04, "lit plate physically supports the player")
	gaze(true, true)
	await tick()
	gaze(true, false)
	await tick()
	check(level.contracts.a_state == "blackout" and dead_board(), "standing on the plate trips the same live blackout")
	for frame in 24:await tick()
	check(level.walker.is_on_floor() and feet().y < -.45 and level.retry == 0., "lost support drops player onto the shallow recess floor")
	var ramp := await walk_to(26.2, 12.30, 65)
	if ramp:ramp = await walk_to(26.2, 9.70, 70)
	check(ramp and feet().y > -.10 and level.walker.is_on_floor() and level.retry == 0., "player walks out of shallow pit via entry ramp")
	check(level.contracts.a_state == "blackout" and dead_board(), "ramp exit does not revive the board early")
	await recover()
	check(blackout_held and active_board(), "board stays dead through all blackout ticks and recovers afterwards")
	level.hale.position.z = 15.02
	level.walker.position = Vector3(23.85, .03, 9.25)
	level.walker.velocity = Vector3.ZERO
	level.captions.clear()
	gaze(true, false)
	await tick()
	gaze(true, true)
	await tick()
	gaze(true, false)
	await tick()
	check(dead_board() and level.walker.is_on_floor() and absf(feet().y) < .05, "B3 entry bank remains solid during blackout")
	check(feet().distance_to(level.hale.position) >= 5.5 and level.captions.entries.get("Hale", {}).get("id") != "breach_a", "distant Hale does not speak on blackout")
	var entered := await walk_to(23.85, 11.45, 70)
	for frame in 15:await tick()
	check(entered and level.walker.is_on_floor() and feet().y < -.45 and level.retry == 0., "player can step from the bank into the extinguished gap")
	await teardown()
	quit(0 if failures == 0 else 1)

func teardown() -> void:
	level.process_mode = Node.PROCESS_MODE_DISABLED
	for node in level.find_children("*", "", true, false):
		if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
			node.stop()
			node.stream = null
	level.queue_free()
	level = null
	# Fixed-fps tests can finish faster than the audio mixer releases voices.
	for frame in 26:
		OS.delay_msec(8)
		await process_frame

extends SceneTree
## Real-physics adversarial exploit bot ("CheeseBot").
## Uses the EXACT same player CharacterBody3D capsule, ExpeditionKit colliders,
## and [E] interaction triggers as a real player from spawn (1, 0.03, 0) — ZERO
## teleports and ZERO direct state overrides (released/collected).

var level
var peak_exposure := 0.0
var ticks := 0

func _initialize() -> void:
	run.call_deferred()

func step_frames(n: int) -> void:
	for i in n:
		await physics_frame
		ticks += 1
		if level != null and is_instance_valid(level):
			peak_exposure = maxf(peak_exposure, level.hunter.exposure)

func go(x: float, z: float, quiet: bool, run_mode: bool, look_at_pt := Vector3.ZERO, limit := 1400) -> bool:
	level.running = run_mode
	if quiet:
		Input.action_press("expedition_quiet")
	else:
		Input.action_release("expedition_quiet")
	Input.action_press("move_up")
	var ok := false
	for i in limit:
		if level.retry > 0.0:
			break
		var p: Vector3 = level.walker.position
		var d := Vector2(x - p.x, z - p.z)
		if d.length() < 0.22:
			ok = true
			break
		level.walker.rotation.y = atan2(-d.x, -d.y)
		if look_at_pt != Vector3.ZERO:
			level.eye.look_at(look_at_pt)
		else:
			level.eye.rotation.x = 0.0
		await physics_frame
		ticks += 1
		peak_exposure = maxf(peak_exposure, level.hunter.exposure)
	Input.action_release("move_up")
	Input.action_release("expedition_quiet")
	level.running = false
	return ok and level.retry <= 0.0

func use_at(target: Vector3) -> bool:
	level.eye.look_at(target)
	await step_frames(2)
	level.use()
	level.eye.rotation = Vector3.ZERO
	return true

func run() -> void:
	level = preload("Sortie.tscn").instantiate()
	root.add_child(level)
	await step_frames(6)

	# 1. Sprint through A1 -> B1 -> B2 -> B3 -> B5 (no gate test, no B2 wait, no oil)
	var path_to_b5 := [
		[31.0, 0.0], [31.0, 4.9], [26.7, 4.9], [25.7, 5.5], [25.7, 7.75],
		[20.95, 7.75], [20.95, 9.8], [23.85, 9.8],
	]
	var ok := true
	for pt in path_to_b5:
		ok = await go(pt[0], pt[1], false, true)
		if not ok:
			break
	# Cross B3 plate staring at it
	if ok:
		ok = await go(23.85, 14.12, false, false, Vector3(23.85, 0.11, 13.0))
	if ok:
		for pt in [[25.5, 14.1], [38.9, 14.1], [38.9, 10.0], [36.6, 8.5]]:
			ok = await go(pt[0], pt[1], false, true)
			if not ok:
				break
	# Pull real B5 Master Release lever via [E]
	if ok:
		await use_at(Vector3(36.3, 1.35, 7.72))
		ok = level.released
	# 2. Ditch Hale, enter C1 solo, stealth-walk main bridge staring down
	if ok:
		ok = await go(48.8, 10.1, true, false)
	if ok:
		ok = await go(52.2, 10.1, true, false, Vector3(61.0, 0.0, 10.1))
	if ok:
		ok = await go(70.5, 10.1, true, false, Vector3(61.0, 0.0, 10.1), 1100)
	# 3. Real [E] pickup on Core, then sprint to east spiral
	if ok:
		await use_at(level.kit.core.position)
		ok = level.collected
	if ok:
		ok = await go(74.6, 10.1, false, true, Vector3.ZERO, 400)

	var cheesed: bool = ok and level.retry <= 0.0 and bool(level.collected)
	var res := {
		"cheesed": cheesed,
		"fail_reason": level.fail_reason,
		"oil_left": snappedf(level.oil, 0.1),
		"peak_exposure": snappedf(peak_exposure, 0.01),
		"ticks": ticks,
		"hunter_state": level.hunter.state,
		"real_physics": true,
	}
	print("CHEESE_RESULT " + JSON.stringify(res))
	level.queue_free()
	for i in 8:
		await process_frame
	quit(0)

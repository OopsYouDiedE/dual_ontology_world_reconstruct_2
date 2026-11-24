extends SceneTree
## Adversarial exploit bot ("CheeseBot") simulating a player who ignores Hale,
## skips all oil/metronome pickups, sprints to B5, stealth-walks solo across the
## main bridge staring down at the deck, grabs the core, and sprints out.
## Used by tools/expedition/ai_optimize_loop.py to detect dominant cheese routes.

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

func walk_to(target: Vector3, quiet: bool, run_mode: bool, look_at_pt: Vector3, max_ticks: int = 900) -> bool:
	level.running = run_mode
	if quiet:
		Input.action_press("expedition_quiet")
	else:
		Input.action_release("expedition_quiet")
	Input.action_press("move_up")
	var reached := false
	for i in max_ticks:
		if level.retry > 0.0:
			break
		var p: Vector3 = level.walker.position
		var d := Vector2(target.x - p.x, target.z - p.z)
		if d.length() < 0.42:
			reached = true
			break
		level.walker.rotation.y = atan2(-d.x, -d.y)
		if look_at_pt != Vector3.ZERO:
			var eye_pos: Vector3 = level.eye.global_position
			var to_pt := look_at_pt - eye_pos
			var flat := Vector2(to_pt.x, to_pt.z).length()
			level.eye.rotation.x = clampf(atan2(to_pt.y, maxf(0.01, flat)), -1.45, 1.45)
		else:
			level.eye.rotation.x = 0.0
		await physics_frame
		ticks += 1
		peak_exposure = maxf(peak_exposure, level.hunter.exposure)
	Input.action_release("move_up")
	Input.action_release("expedition_quiet")
	level.running = false
	return reached and level.retry <= 0.0

func run() -> void:
	level = preload("Expedition.tscn").instantiate()
	root.add_child(level)
	await step_frames(8)

	# Simulate player rushing straight to B5, ditching Hale outside the shaft,
	# pulling the master release, then solo stealth-crossing the main bridge.
	level.hale.position = Vector3(31.0, 0.0, 2.0)
	level.hale_hold = true
	level.walker.position = Vector3(48.5, 0.05, 10.1)
	level.walker.rotation.y = 0.0
	level.eye.rotation.x = 0.0
	level.released = true
	level.hunter.wake()
	level.oil = 65.0
	await step_frames(4)

	# 1. Rush to bridge west mouth (no oil pickup, no metronome, no Hale)
	var ok := await walk_to(Vector3(52.2, 0.05, 10.1), true, false, Vector3(61.0, 0.0, 10.1), 320)
	# 2. Solo stealth-walk across the 18m main bridge staring down at the deck
	if ok:
		ok = await walk_to(Vector3(70.5, 0.05, 10.1), true, false, Vector3(61.0, 0.0, 10.1), 950)
	# 3. Grab core & sprint straight to east spiral entry
	if ok and level.retry <= 0.0:
		level.collected = true
		level.hunter.exposure = maxf(level.hunter.exposure, 1.5)
		ok = await walk_to(Vector3(74.8, 0.05, 10.1), false, true, Vector3.ZERO, 350)

	var cheesed: bool = ok and level.retry <= 0.0 and bool(level.collected)
	var res := {
		"cheesed": cheesed,
		"fail_reason": level.fail_reason,
		"oil_left": snappedf(level.oil, 0.1),
		"peak_exposure": snappedf(peak_exposure, 0.01),
		"ticks": ticks,
		"hunter_state": level.hunter.state,
	}
	print("CHEESE_RESULT " + JSON.stringify(res))
	level.queue_free()
	for i in 8:
		await process_frame
	quit(0)

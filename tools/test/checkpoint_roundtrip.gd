extends SceneTree
## Development-only state roundtrip; never an independent gameplay acceptance.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Checkpoint := preload("res://scenes/components/testing/StoryCheckpoint.gd")
var failures: Array[String] = []
var game: Control

func check(value: bool, message: String) -> void:
	print(("PASS " if value else "FAIL ") + message)
	if not value: failures.append(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var started := Time.get_ticks_msec()
	game = Main.instantiate()
	root.add_child(game)
	current_scene = game
	# Advance production controllers explicitly so fixtures are deterministic.
	game.set_process(false)
	await process_frame
	game.eng.s.playing = false
	game.eng.process_beats()
	var path := "res://.runtime/checkpoints/roundtrip.json"
	var opening = game.opening
	check(opening != null and opening.active, "production opening active")
	opening.phase = "look"
	opening._pt = 2.1
	opening._clock = 8.0
	opening._rig.set("sit", 1.0)
	game.cam.fov = 54.0
	game._sub_queue = [{"who": "detective", "text": "快照对白", "kind": "think"}]
	game._sub_clock = 12.0
	game._sub_until = 15.0
	check(game.checkpoints.save_now(path), "atomic snapshot saved")
	game.checkpoints.save_now("res://.runtime/checkpoints/fixtures/opening-look.json")
	var state: Dictionary = game.checkpoints.read_snapshot(path)
	check(not state.is_empty(), "snapshot integrity and project identity verified")
	game.opening._pt = 0
	game.eng.s.flags["changed_after_checkpoint"] = true
	check(game.checkpoints.restore_file(path), "opening restored")
	check(game.opening.phase == "look" and is_equal_approx(game.opening._pt, 2.1), "opening phase and local time restored")
	check(not game.eng.s.flags.has("changed_after_checkpoint"), "engine state restored without later mutations")
	check(game._sub_queue.size() == 1 and game._sub_clock == 12.0 and game._sub_until == 15.0, "dialogue queue and remaining time restored")
	check(is_equal_approx(game.cam.fov, 54.0), "original camera optics restored")
	game._sub_queue.clear()
	game.subtitle.visible = false
	opening = game.opening
	opening._enter("getup")
	var getup_duration: float = game._wake_total
	game._step_wake_up(getup_duration + 0.01)
	opening.process(getup_duration + 0.01)
	check(opening.phase == "free" and game.det.pose == "stand" and game._det_can_occupy(game.det_pos), "bedroom free fixture uses completed production get-up and walkable landing")
	check(game.eng.s.playing and is_equal_approx(game.eng.s.speed, opening.AMBIENT_SPEED), "bedroom free fixture keeps natural exploration clock")
	game.checkpoints.save_now("res://.runtime/checkpoints/fixtures/opening-free.json")
	game._stop_exploration()
	check(game.eng.enter_room("B-P"), "kitchen entered through rule engine")
	game._build_room("B-P")
	game._det_to_home()
	game.start_kitchen_exploration()
	# Finish the real doorway route; its callback clears _door_passage before free.
	for step in 600:
		if game.kitchen.phase == "free": break
		game._walk_step(1.0/60.0)
	check(game.kitchen.phase == "free" and game.det_path.is_empty() and not game.det_done.is_valid() and game._door_passage.is_empty(), "kitchen fixture has completed doorway crossing with no stale callback")
	check(game.eng.s.playing and game._det_can_occupy(game.det_pos), "kitchen fixture enables player movement at actual entry landing")
	var clock_before: float = game.eng.s.t
	game.eng.tick(1.0)
	check(is_equal_approx(game.eng.s.t, clock_before + game.eng.s.speed), "kitchen natural clock advances without stale story or door locks")
	game.kitchen.process(0.0)
	var before: Vector3 = game.det.position
	check(game.checkpoints.save_now(path), "kitchen snapshot saved")
	game.checkpoints.save_now("res://.runtime/checkpoints/fixtures/kitchen-free.json")
	check(game.checkpoints.restore_file(path), "kitchen restored directly")
	check(game.eng.s.room == "B-P" and game.kitchen.active and game.kitchen.phase == "free", "production kitchen controller resumed")
	check(game.det.position.is_equal_approx(before) and game.det_pos.is_equal_approx(Vector2(before.x, before.z)), "actual kitchen entrance position retained")
	check(game._door_passage.is_empty() and game.eng.s.playing, "restored kitchen remains outside doorway crossing with natural clock enabled")
	var item := -1
	for i in game.kitchen._items.size():
		if str(game.kitchen._items[i].id) == "e_b_water": item = i
	game.kitchen._arrive(item)
	check(is_instance_valid(game.interactions.active), "original room closeup started")
	var detail = game.evidence_presentations.water
	detail.progress = 0.42
	check(game.checkpoints.save_now(path), "mid-interaction snapshot saved")
	game.checkpoints.save_now("res://.runtime/checkpoints/fixtures/kitchen-water-partial.json")
	check(game.checkpoints.restore_file(path), "mid-interaction restored")
	check(is_instance_valid(game.interactions.active) and game.interactions.active.kind == "water", "closeup controller and completion callback reconstructed")
	check(is_equal_approx(game.evidence_presentations.water.progress, 0.42), "sampling progress retained")
	game.interactions.finish(true)
	check(game.eng.s.evidence.has("e_b_water"), "restored closeup completion registers actual evidence")
	check(not game._cine, "restored interaction releases cinematic lock")
	game._stop_exploration()
	game.eng.s.room = "R05"
	game._build_room("R05")
	game._det_to_home()
	game.start_gathering("B-P")
	game._fade_tween.kill()
	game.gathering._setup_stage()
	game._fade_tween.kill()
	game.gathering._enter_free()
	game.gathering._line = 3
	game.det_pos = Vector2(8.3, 2.2)
	game.det.position = Vector3(8.3, 0, 2.2)
	check(game.checkpoints.save_now(path), "corridor snapshot saved")
	game.checkpoints.save_now("res://.runtime/checkpoints/fixtures/corridor-free.json")
	check(game.checkpoints.restore_file(path), "corridor restored")
	check(game.gathering.active and game.gathering.phase == "free" and game.gathering._line == 3, "corridor stage and dialogue cursor retained")
	check(game.det_pos.is_equal_approx(Vector2(8.3, 2.2)), "corridor position retained separately from engine room")
	var invalid := JSON.parse_string(FileAccess.get_file_as_string(path)) as Dictionary
	invalid["sha256"] = "bad"
	var file := FileAccess.open(path + ".corrupt", FileAccess.WRITE)
	file.store_string(JSON.stringify(invalid))
	file.close()
	var prior: String = game.gathering.phase
	check(not game.checkpoints.restore_file(path + ".corrupt") and game.gathering.phase == prior, "corrupt snapshot rejected before scene mutation")
	print("CHECKPOINT_RESULT " + JSON.stringify({"failures": failures, "elapsed_ms": Time.get_ticks_msec() - started, "acceptance_scored": false}))
	game._stop_exploration()
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

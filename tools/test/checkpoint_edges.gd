extends SceneTree
## Focused checkpoint continuations, selected independently to keep room checks short.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Checkpoint := preload("res://scenes/components/testing/StoryCheckpoint.gd")
var failed := 0
func check(ok: bool, message: String) -> void:
	print(("PASS " if ok else "FAIL ") + message)
	if not ok: failed += 1
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var started := Time.get_ticks_msec()
	var game = Main.instantiate()
	game.show_intro = false
	root.add_child(game)
	game.set_process(false)
	game.eng.s.playing = false
	game.score.set_enabled(false)
	await process_frame
	var probe := Checkpoint.argument("--probe", "transit")
	var path := "res://.runtime/checkpoints/edge-" + probe + ".json"
	if probe == "opening-free":
		game.det.set_pose("lie")
		game.show_intro = true
		game._start_opening()
		game.eng.process_beats()
		game._sub_queue.clear()
		game.subtitle.visible = false
		game.opening._enter("getup")
		var getup_duration: float = game._wake_total
		game._step_wake_up(getup_duration + 0.01)
		game.opening.process(getup_duration + 0.01)
		check(game.opening.phase == "free" and game.det.pose == "stand" and game._det_can_occupy(game.det_pos), "free bedroom starts at completed production get-up landing")
		game.opening._free_t = 5.0
		game.opening._hint.modulate.a = 0.4
		game.opening._snap_camera()
		check(game.checkpoints.save_now(path), "free bedroom snapshot saved")
		check(game.checkpoints.restore_file(path), "free bedroom restored")
		check(game.opening._hint.visible and is_equal_approx(game.opening._hint.modulate.a, 0.4), "free bedroom hint visibility and fade retained")
		check(game.opening._name_tag.visible and game.opening._free_t == 5.0, "free bedroom nameplate and elapsed time retained")
		game.checkpoints.save_now("res://.runtime/checkpoints/fixtures/opening-free.json")
	elif probe == "transit":
		game.eng.s.room = "B-P"
		game._begin_transit("B-P")
		var room_before: String = game._room_loaded
		game.checkpoints.save_now(path)
		check(game.checkpoints.restore_file(path), "mid-transit checkpoint restored")
		check(game._room_loaded == room_before and game._transit.to == "B-P", "rendered origin and destination preserved")
		game.det_path.clear()
		game.det_done.call()
		check(game._transit.phase == "fade" and game._door_passage.is_empty(), "restored exit callback releases doorway and advances fade")
		game._fade_tween.kill()
		game._transit_swap()
		game.checkpoints.save_now(path)
		check(game.checkpoints.restore_file(path), "entrance checkpoint restored")
		game.det_path.clear()
		game.det_done.call()
		check(not game._transit_active() and game._door_passage.is_empty(), "restored entrance finishes and releases doorway")
	elif probe == "reconstruction":
		game.eng.s.room = "B-P"
		game.eng.s.t = 470.0
		game._build_room("B-P")
		game._det_to_home()
		game.start_kitchen_exploration()
		game.kitchen._enter_free()
		game.det_path.clear()
		for eid in ["e_b_sleeve", "e_b_drag", "e_b_water", "e_b_ratchet"]: game.eng.inspect_evidence(eid, true)
		game.eng.open_deduction("ded_drag")
		game._sub_queue.clear()
		game.kitchen.begin_order_replay("ded_drag")
		var replay = game.kitchen._order_replay
		replay._performance.set_process(false)
		replay._performance._advance_timeline(3.2)
		var before: Dictionary = replay.checkpoint_state()
		check(game.checkpoints.save_now(path), "mid-reconstruction full host checkpoint saved")
		check(game.checkpoints.restore_file(path), "mid-reconstruction full host restored")
		replay = game.kitchen._order_replay
		replay._performance.set_process(false)
		var after: Dictionary = replay.checkpoint_state()
		check(before.performance.phase == after.performance.phase and is_equal_approx(before.performance.phase_time, after.performance.phase_time), "reconstruction phase and fractional frame time preserved")
		check(before.order == after.order, "player's ordering preserved")
		while replay._playing: replay._performance._advance_timeline(0.5)
		check(not replay._confirm.disabled and game._cine, "resumed performance reaches confirmation")
		replay._order.assign(["su_open", "detective_pull", "shen_cloth", "huo_lock"])
		replay._confirm_order()
		check(game.eng.s.deductions.get("ded_drag") == "solved" and not game._cine, "resumed confirmation reaches rule engine and releases cinematic control")
	elif probe == "backup":
		check(game.checkpoints.save_now(path) and game.checkpoints.save_now(path), "two complete snapshot generations saved")
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_string("interrupted write")
		file.close()
		check(game.checkpoints.restore_file(path) and game.checkpoints.recovery_path == path + ".previous", "corrupt latest recovers full previous generation")
	else: check(false, "known probe")
	print("CHECKPOINT_EDGE " + JSON.stringify({"probe": probe, "failures": failed, "elapsed_ms": Time.get_ticks_msec() - started, "acceptance_scored": false}))
	game._stop_exploration()
	game.queue_free()
	await process_frame
	quit(0 if failed == 0 else 1)

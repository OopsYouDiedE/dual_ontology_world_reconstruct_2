extends SceneTree
## Focused checkpoint continuations, selected independently to keep room checks short.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Checkpoint := preload("res://scenes/components/testing/StoryCheckpoint.gd")
const Source := preload("res://mcp/CaptureSource.gd")
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
		# Fixture: the rendered origin cast can legitimately lag the rule engine
		# while a room change is in progress. Add a known actor to exercise this
		# mismatch; these coordinates are test data, not a game placement change.
		var fixture_id := "huo"
		if not game.figures.has(fixture_id):
			var center: Vector3 = game.room_mesh.center()
			game.figures[fixture_id] = game._make_room_figure(game.data.actor_by_id[fixture_id], game.figures.size(), Vector2(2.0, 1.0), Vector2(center.x, center.z))
		game.eng.s.room = "B-P"
		game._begin_transit("B-P")
		var room_before: String = game._room_loaded
		var cast_before: Array = game.figures.keys()
		var transform_before: Transform3D = game.figures[fixture_id].transform
		var animation_shape: Dictionary = game.checkpoints.capture().presentation.actors[fixture_id].duplicate(true)
		animation_shape["animation"] = StringName("idle")
		animation_shape["position"] = 0.0
		check(Checkpoint._valid_saved_actor(animation_shape), "native Godot StringName animation accepted")
		animation_shape["animation"] = "idle"
		check(Checkpoint._valid_saved_actor(animation_shape), "legacy String animation accepted")
		animation_shape["animation"] = 3
		check(not Checkpoint._valid_saved_actor(animation_shape), "invalid animation type rejected")
		var saved_route: Array = game.det_path.duplicate()
		var saved_door: Dictionary = game._door_passage.duplicate(true)
		check(not game.eng.actors_in_room(room_before).has(fixture_id), "fixture visible cast differs from current engine cast")
		check(game.checkpoints.save_now(path), "mismatched transit cast snapshot saved")
		check(game.checkpoints.restore_file(path), "mid-transit checkpoint restored")
		check(game._room_loaded == room_before and game._transit.to == "B-P", "rendered origin and destination preserved")
		check(game.figures.keys() == cast_before and game.figures.has(fixture_id) and game.figures[fixture_id].transform.is_equal_approx(transform_before), "exact saved transit actor order and transform restored")
		check(game.det_path == saved_route and game._door_passage == saved_door and game.det_done.is_valid(), "saved route, doorway and semantic callback restored")
		# An internally checksummed but invalid actor must be rejected before any
		# scene mutation; a valid envelope alone is not sufficient.
		var bad: Dictionary = game.checkpoints.capture()
		bad.presentation.actors["not-a-real-actor"] = bad.presentation.detective.duplicate(true)
		var bad_path := Source.project_output(path + ".invalid-actor")
		check(Checkpoint.write_snapshot(bad_path, bad, 1) == OK, "invalid-cast fixture has valid envelope and checksum")
		var before_invalid: Dictionary = game.checkpoints.capture()
		check(not game.checkpoints.restore_file(bad_path) and game.checkpoints.error.begins_with("Checkpoint transit actor invalid"), "unknown transit actor rejected")
		check(game.eng.save_dict() == before_invalid.engine and game.figures.keys() == cast_before and game.det_path == saved_route, "invalid cast rejected before scene mutation")
		bad = before_invalid.duplicate(true)
		bad.presentation.actors[fixture_id].transform = Vector3.ZERO
		check(Checkpoint.write_snapshot(bad_path, bad, 2) == OK, "invalid-transform fixture has valid envelope and checksum")
		check(not game.checkpoints.restore_file(bad_path) and game.checkpoints.error.begins_with("Checkpoint transit actor invalid"), "malformed transit actor transform rejected")
		check(game.eng.save_dict() == before_invalid.engine and game.figures.keys() == cast_before and game.det_path == saved_route, "invalid transform rejected before scene mutation")
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

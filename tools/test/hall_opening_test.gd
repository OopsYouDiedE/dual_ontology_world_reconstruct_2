extends SceneTree

const RunScene = preload("res://scenes/rogue/Run.tscn")
const ExpeditionEntry = preload("res://scenes/expedition_01/Expedition.tscn")
var failed := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		failed += 1

func reachable_cells(view, start: Vector2i) -> Dictionary:
	var seen := {}
	var pending: Array[Vector2i] = [start]
	seen[start] = true
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		for direction: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var dest := cell + direction
			if not seen.has(dest) and view._is_clear_cell(dest) and not view._has_wall_between(cell, dest):
				seen[dest] = true
				pending.append(dest)
	return seen

func run() -> void:
	var entry := ExpeditionEntry.instantiate()
	root.add_child(entry)
	await process_frame
	check(entry.mcp_observe().stage == "hall" and entry.first_sortie == null, "Direct Expedition launch starts in the hall before the sortie")
	entry.queue_free()
	await process_frame
	var game := RunScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame

	var obs: Dictionary = game.mcp_observe()
	check(obs.phase == "camp" and obs.stage == "hall", "Run.tscn starts in Public Hall camp phase")
	check(int(obs.witness_count) == 0, "Before the first sortie the Hall seats no residents (%d)" % int(obs.witness_count))
	var hale := game.find_child("HallHale", true, false) as Node3D
	check(hale != null and hale.get_meta("hero", "") == "hale", "Hale waits in the Hall on the hero model")

	var gothic := game.find_child("PublicHallGothic", true, false)
	check(gothic != null, "PublicHallGothic architectural shell is mounted in Public Hall")
	if gothic != null:
		var well := game.find_child("TourbillonTray", true, false) as Node3D
		for arch_z: int in [15, 17]:
			for door_x: int in [11, 21]:
				var a := Vector2i(door_x-1, arch_z)
				var b := a+Vector2i.RIGHT
				check(game.room_view._is_clear_cell(a) and game.room_view._is_clear_cell(b) and not game.room_view._has_wall_between(a,b), "Open side arcade at %s" % str(b))
		var reachable := reachable_cells(game.room_view, Vector2i(16,24))
		for interior: Vector2i in [Vector2i(9,15),Vector2i(9,19),Vector2i(24,15),Vector2i(22,19)]:
			check(reachable.has(interior), "Hall spawn reaches furnished wing interior %s" % str(interior))
		var desk := gothic.find_child("EssenceCalibrationLectern", true, false) as Node3D
		check(well != null and well.global_position.distance_to(gothic.pendulum_world_pos) < 0.01, "Flush tourbillon and suspension share one axis")
		check(desk != null and is_equal_approx(desk.position.x, gothic.pendulum_world_pos.x), "North desk is centered beyond pendulum")
		check(gothic.find_child("FoucaultPendulum", true, false) != null, "Central brass FoucaultPendulum is mounted")
		check(gothic.find_child("WatchCotAlcove", true, false) != null, "WatchCotAlcove awakening zone is mounted")
		check(gothic.find_child("EssenceCalibrationLectern", true, false) != null, "EssenceCalibrationLectern zone is mounted")
		check(gothic.find_child("HallRose_North", true, false) != null and gothic.find_child("HallRose_South", true, false) != null, "North and South Gothic Rose Windows are mounted")
		check(gothic.drifting == true, "FoucaultPendulum starts in drifting (uncalibrated) state")

	var started: bool = game.play_hall_opening(true)
	check(started, "Opening awakening sequence starts cleanly")
	await process_frame

	var seq = game._opening
	var seen_beats: Array[String] = []
	var fovs: Array[float] = []
	for step_i in 6:
		var snap: Dictionary = seq.snapshot()
		if not snap.active:
			break
		seen_beats.append(snap.beat_id)
		seq._process(1.8)
		fovs.append(seq.snapshot().camera_fov)
		seq._advance_beat()

	check(seen_beats == ["wake_shake", "wake_focus", "pendulum_drift", "essence_reason", "north_gate_handoff"], "Opening sequence plays all 5 revised narrative beats: " + str(seen_beats))
	check(not seq.active, "Opening sequence finishes cleanly and restores control")
	check(fovs.size() == 5 and fovs[2] < fovs[0], "Camera FOV pushes in on Foucault Pendulum shot (%.1f -> %.1f)" % [fovs[0] if fovs.size() > 0 else 0.0, fovs[2] if fovs.size() > 2 else 0.0])
	check(game.room_view.is_walking_view(), "First-person walking controls are restored after cutscene")

	# Verify skip path and calibrated pendulum state
	check(game.play_hall_opening(true), "Opening sequence can replay cleanly")
	game.skip_hall_opening()
	check(not seq.active and game.room_view.is_walking_view(), "Skip immediately restores first-person control")

	if gothic != null:
		game.room_view.set_pendulum_drifting(false)
		check(gothic.drifting == false, "Pendulum transitions to calibrated steady state")

	game.queue_free()
	await process_frame
	print("Hall opening test: %d failures" % failed)
	quit(failed)

extends SceneTree
## Non-mutating, discrete/local connector diagnosis of a restored transit.
## Each counterfactual excludes at most one named actor from collision probes;
## it never moves a figure, changes the checkpoint or constitutes acceptance.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Source := preload("res://mcp/CaptureSource.gd")
const RoomCheck := preload("res://scenes/components/testing/RoomFastCheck.gd")
const STEP := 0.025
const START_RADIUS := 1.2
const TARGET_RADIUS := 0.6

func _initialize() -> void: _run.call_deferred()

func _arg(key: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(key + "="): return argument.trim_prefix(key + "=")
	return ""

func _xy(p: Vector2) -> Array: return [p.x, p.y]

# Mirrors the production clearance rule; only the named actor is omitted.
func _occupiable(game: Control, p: Vector2, excluded: String) -> bool:
	var cell: Vector2i = game._cell_of(p)
	var crossing := false
	if not game._door_passage.is_empty():
		var nearest := Geometry2D.get_closest_point_to_segment(p, game._door_passage.outer, game._door_passage.inner)
		crossing = p.distance_to(nearest) <= 0.24
	if not crossing and (not game._grid.is_in_boundsv(cell) or game._grid.is_point_solid(cell)): return false
	for id in game.figures:
		if str(id) == excluded: continue
		var actor: Node3D = game.figures[id]
		if not is_instance_valid(actor): continue
		if p.distance_to(Vector2(actor.global_position.x, actor.global_position.z)) < game.ACTOR_MIN_DISTANCE: return false
	return true

func _segment(game: Control, a: Vector2, b: Vector2, excluded: String) -> bool:
	var count := maxi(1, int(ceil(a.distance_to(b) / STEP)))
	for i in range(count + 1):
		if not _occupiable(game, a.lerp(b, float(i) / float(count)), excluded): return false
	return true

func _probe(game: Control, grid: AStarGrid2D, excluded: String) -> Dictionary:
	var start: Vector2 = game.det_pos
	var inner: Vector2 = game._door_passage.inner
	var outer: Vector2 = game._door_passage.outer
	var source := []
	var destination := []
	for x in range(grid.region.position.x, grid.region.end.x):
		for z in range(grid.region.position.y, grid.region.end.y):
			var cell := Vector2i(x,z)
			if grid.is_point_solid(cell): continue
			var p := Vector2((x + 0.5) * game.CELL, (z + 0.5) * game.CELL)
			if p.distance_to(start) <= START_RADIUS and _segment(game, start, p, excluded): source.append({"cell":cell,"point":p})
			if p.distance_to(inner) <= TARGET_RADIUS and _segment(game, p, inner, excluded): destination.append({"cell":cell,"point":p})
	source.sort_custom(func(a: Dictionary, b: Dictionary): return a.point.distance_squared_to(start) < b.point.distance_squared_to(start))
	destination.sort_custom(func(a: Dictionary, b: Dictionary): return a.point.distance_squared_to(inner) < b.point.distance_squared_to(inner))
	var astar_found := false
	var continuous := []
	var tested_pairs := 0
	for origin: Dictionary in source:
		for target: Dictionary in destination:
			tested_pairs += 1
			var path: Array[Vector2i] = grid.get_id_path(origin.cell, target.cell)
			if path.is_empty(): continue
			astar_found = true
			var path_points: Array[Vector2] = [start]
			for cell: Vector2i in path: path_points.append(Vector2((cell.x + 0.5) * game.CELL, (cell.y + 0.5) * game.CELL))
			path_points.append(inner)
			var clear := true
			for i in range(1, path_points.size()):
				if not _segment(game, path_points[i-1], path_points[i], excluded): clear = false; break
			if clear:
				for p: Vector2 in path_points: continuous.append(_xy(p))
				break
		if not continuous.is_empty(): break
	var door_open := _segment(game, inner, outer, excluded)
	return {"excluded_actor":excluded, "start_occupiable":_occupiable(game,start,excluded),
		"inner_occupiable":_occupiable(game,inner,excluded), "door_segment_clear":door_open,
		"start_connector_count":source.size(), "target_connector_count":destination.size(),
		"connector_pairs_tested":tested_pairs, "astar_candidate_found":astar_found,
		"sampled_continuous_path_to_inner":continuous,
		"exact_inner_and_door_reachable":not continuous.is_empty() and door_open}

func _run() -> void:
	var snapshot := Source.project_output(_arg("--dv-snapshot"))
	var output := Source.project_output(_arg("--dv-connectivity-output"))
	if snapshot.is_empty() or output.is_empty():
		printerr("Project-local snapshot and output required")
		quit(2); return
	var game = Main.instantiate()
	game.show_intro = false
	root.add_child(game)
	current_scene = game
	if not is_instance_valid(game.checkpoints) or not game.checkpoints.restored:
		printerr("Checkpoint restore failed")
		quit(2); return
	game.checkpoints.automatic = false
	game.checkpoints.output_path = ""
	game.checkpoints.set_process(false)
	game.set_process(false)
	var saved: Dictionary = game.checkpoints.read_snapshot(snapshot)
	if saved.is_empty() or not game._transit_active() or str(game._transit.phase) != "exit" or game._door_passage.is_empty() or game.figures.keys() != saved.presentation.actors.keys():
		printerr("Snapshot is not an exactly restored active exit")
		quit(2); return
	for id in saved.presentation.actors:
		if not game.figures[id].transform.is_equal_approx(saved.presentation.actors[id].transform):
			printerr("Saved actor transform mismatch: ", id)
			quit(2); return
	var before: Dictionary = game.checkpoints.capture()
	var helper := RoomCheck.new()
	helper.host = game
	var probes := {}
	var started := Time.get_ticks_usec()
	probes["none"] = _probe(game, game._route_grid_with_figures(), "")
	for id in game.figures:
		probes[str(id)] = _probe(game, helper._grid_without_figure(str(id)), str(id))
	var after: Dictionary = game.checkpoints.capture()
	var unchanged: bool = before.engine == after.engine and before.presentation == after.presentation
	var report := {"format":"transit-one-exclusion-connectivity-v1",
		"source_identity":Source.identity(self, "res://scenes/dual_world/DualWorldMain.tscn"),
		"source_snapshot":snapshot, "source_sha256":FileAccess.get_sha256(snapshot),
		"room_loaded":str(game._room_loaded), "engine_room":str(game.eng.s.room),
		"detective":_xy(game.det_pos), "door_inner":_xy(game._door_passage.inner), "door_outer":_xy(game._door_passage.outer),
		"actor_count":game.figures.size(), "clearance":game.ACTOR_MIN_DISTANCE,
		"sample_step_m":STEP, "start_connector_radius_m":START_RADIUS, "target_connector_radius_m":TARGET_RADIUS,
		"probes":probes, "state_unchanged":unchanged,
		"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0,
		"scope":"counterfactual one-actor exclusions; sampled collision segments and discrete A* are not exhaustive continuous geometry or an independent acceptance test",
		"acceptance_eligible":false, "acceptance_scored":false}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null: printerr("Cannot write report"); quit(2); return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	var passing := []
	for id in probes:
		if probes[id].exact_inner_and_door_reachable: passing.append(id)
	print("TRANSIT_CONNECTIVITY " + JSON.stringify({"passing_exclusions":passing,"state_unchanged":unchanged,"elapsed_ms":report.elapsed_ms,"output":output,"acceptance_eligible":false}))
	game.queue_free()
	await process_frame
	quit(0 if unchanged else 1)

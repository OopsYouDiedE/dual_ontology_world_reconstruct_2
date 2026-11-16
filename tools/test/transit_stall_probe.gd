extends SceneTree
## Read-only analysis of a real development transit checkpoint. Actor exclusion
## grids are diagnostic simulations; no figure or snapshot is altered.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Source := preload("res://mcp/CaptureSource.gd")
const RoomCheck := preload("res://scenes/components/testing/RoomFastCheck.gd")

func _initialize() -> void:
	_run.call_deferred()

func _arg(key: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(key + "="): return argument.trim_prefix(key + "=")
	return ""

func _xy(p: Vector2) -> Array: return [p.x, p.y]
func _cell(p: Vector2i) -> Array: return [p.x, p.y]

func _path(grid: AStarGrid2D, game: Control, start: Vector2, target: Vector2) -> Dictionary:
	var origin: Vector2i = game._nearest_free(game._cell_of(start), grid)
	var destination: Vector2i = game._nearest_free(game._cell_of(target), grid)
	var points: Array[Vector2i] = grid.get_id_path(origin, destination)
	var encoded := []
	for point: Vector2i in points: encoded.append(_cell(point))
	var resolved := Vector2((destination.x + 0.5) * game.CELL, (destination.y + 0.5) * game.CELL)
	return {"origin_cell":_cell(origin), "target_cell":_cell(destination),
		"target_center":_xy(resolved), "target_center_distance":resolved.distance_to(target),
		"found":not points.is_empty(), "cell_count":points.size(), "cells":encoded}

func _run() -> void:
	var snapshot := _arg("--dv-snapshot")
	var output := Source.project_output(_arg("--dv-transit-output"))
	if snapshot.is_empty() or Source.project_output(snapshot).is_empty() or output.is_empty():
		printerr("Project-local snapshot and report required")
		quit(2)
		return
	var game = Main.instantiate()
	game.show_intro = false
	root.add_child(game)
	current_scene = game
	if not is_instance_valid(game.checkpoints) or not game.checkpoints.restored:
		printerr("Snapshot restore failed")
		quit(2)
		return
	game.checkpoints.automatic = false
	game.checkpoints.output_path = ""
	game.checkpoints.set_process(false)
	game.set_process(false)
	for controller in [game.opening, game.kitchen, game.gathering]:
		if is_instance_valid(controller): controller.set_process(false)
	await process_frame
	if not game._transit_active() or str(game._transit.phase) != "exit" or game._door_passage.is_empty():
		printerr("Expected an active exit transit checkpoint")
		quit(2)
		return
	var saved_snapshot: Dictionary = game.checkpoints.read_snapshot(snapshot)
	if saved_snapshot.is_empty():
		printerr("Cannot reread the source checkpoint")
		quit(2)
		return
	var saved_actors: Dictionary = saved_snapshot.presentation.actors
	var saved_ids: Array = saved_actors.keys()
	var restored_ids: Array = game.figures.keys()
	var missing_saved := []
	var extra_restored := []
	var changed_common := []
	for id in saved_ids:
		if not restored_ids.has(id):
			missing_saved.append(id)
		else:
			var expected: Transform3D = saved_actors[id].transform
			if not (game.figures[id] as Node3D).transform.is_equal_approx(expected): changed_common.append(id)
	for id in restored_ids:
		if not saved_ids.has(id): extra_restored.append(id)
	var cast_restored_exactly := missing_saved.is_empty() and extra_restored.is_empty() and changed_common.is_empty() and saved_ids == restored_ids
	var saved_p: Dictionary = saved_snapshot.presentation
	var restoration := {
		"cast_and_order":cast_restored_exactly,
		"actor_visibility_and_pose":true,
		"detective_transform":game.det.transform.is_equal_approx(saved_p.detective.transform),
		"detective_position":game.det_pos.is_equal_approx(saved_p.host.det_pos),
		"route":game.det_path == saved_p.host.det_path,
		"door_passage":game._door_passage == saved_p.host._door_passage,
		"transit_intent":game._transit == saved_p.host._transit,
		"transit_callback":game.det_done.is_valid(),
		"camera_transform":game.cam.global_transform.is_equal_approx(saved_p.camera.transform),
		"camera_optics":is_equal_approx(game.cam.fov, saved_p.camera.fov) and is_equal_approx(game.cam.near, saved_p.camera.near),
		"rule_engine":game.eng.save_dict() == saved_snapshot.engine,
	}
	for id in saved_ids:
		if not game.figures.has(id):
			restoration.actor_visibility_and_pose = false
			continue
		var actor: Node3D = game.figures[id]
		if actor.visible != saved_actors[id].visible or str(actor.pose) != str(saved_actors[id].pose):
			restoration.actor_visibility_and_pose = false
	var restoration_pass := true
	for field in restoration:
		if not restoration[field]: restoration_pass = false
	var door: Dictionary = game._door_passage.duplicate(true)
	var start: Vector2 = game.det_pos
	var origin: Vector2 = door.inner
	var center: Vector2 = door.pos
	var outside: Vector2 = door.outer
	var actors := {}
	var pairwise := []
	var ids: Array = game.figures.keys()
	for id in ids:
		var figure: Node3D = game.figures[id]
		var point := Vector2(figure.global_position.x, figure.global_position.z)
		var nearest := Geometry2D.get_closest_point_to_segment(point, origin, outside)
		actors[str(id)] = {"position":_xy(point), "distance_to_detective":point.distance_to(start),
			"distance_to_door_inner":point.distance_to(origin), "distance_to_door_center":point.distance_to(center),
			"distance_to_door_segment":point.distance_to(nearest),
			"blocks_door_segment":point.distance_to(nearest) < game.ACTOR_MIN_DISTANCE}
	for i in ids.size():
		for j in range(i + 1, ids.size()):
			var a: Array = actors[str(ids[i])].position
			var b: Array = actors[str(ids[j])].position
			var distance := Vector2(a[0],a[1]).distance_to(Vector2(b[0],b[1]))
			pairwise.append({"a":str(ids[i]), "b":str(ids[j]), "distance":distance, "clear":distance >= game.ACTOR_MIN_DISTANCE})
	var helper := RoomCheck.new()
	helper.host = game
	var current_grid: AStarGrid2D = game._route_grid_with_figures()
	var base_path := _path(current_grid, game, start, origin)
	var static_path := _path(game._grid, game, start, origin)
	var excluded := {}
	for id in ids:
		var grid: AStarGrid2D = helper._grid_without_figure(str(id))
		var possible := _path(grid, game, start, origin)
		var remaining_blockers := []
		for other in actors:
			if other != str(id) and actors[other].blocks_door_segment: remaining_blockers.append(other)
		possible["remaining_door_blockers"] = remaining_blockers
		excluded[str(id)] = possible
	var passage_samples := []
	for step in 16:
		var p: Vector2 = origin.lerp(outside, float(step) / 15.0)
		var cell: Vector2i = game._cell_of(p)
		passage_samples.append({"position":_xy(p), "cell":_cell(cell),
			"static_solid":game._grid.is_point_solid(cell), "occupiable":game._det_can_occupy(p)})
	var planned: Array = game._route(start, origin)
	var production := []
	for p: Vector2 in planned: production.append(_xy(p))
	var current_route := []
	for p: Vector2 in game.det_path: current_route.append(_xy(p))
	var report := {"format":"transit-stall-probe-v1", "source_identity":Source.identity(self, "res://scenes/dual_world/DualWorldMain.tscn"),
		"snapshot":Source.project_output(snapshot), "snapshot_sha256":FileAccess.get_sha256(snapshot),
		"loaded_room":str(game._room_loaded), "engine_room":str(game.eng.s.room), "phase":str(game._transit.phase),
		"saved_actor_ids":saved_ids, "restored_actor_ids":restored_ids,
		"missing_saved_actors":missing_saved, "extra_restored_actors":extra_restored,
		"common_actors_with_changed_transform":changed_common, "cast_restored_exactly":cast_restored_exactly,
		"restoration_checks":restoration, "restoration_pass":restoration_pass,
		"lowpoly":bool(game._lowpoly_ok), "door":{"inner":_xy(origin), "center":_xy(center), "outer":_xy(outside)},
		"detective":_xy(start), "current_position_occupiable":game._det_can_occupy(start),
		"actors":actors, "pairwise":pairwise, "door_passage_samples":passage_samples,
		"actual_remaining_route":current_route, "recomputed_production_route_to_inner":production,
		"all_figures_grid_path":base_path, "static_only_grid_path":static_path,
		"figure_exclusion_grid_probes":excluded, "actor_minimum_distance":game.ACTOR_MIN_DISTANCE,
		"scope":"read-only restored development snapshot; consult cast_restored_exactly before interpreting routes. Exclusion grids are counterfactual, not moved actors or acceptance",
		"acceptance_eligible":false, "acceptance_scored":false}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write transit report")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("TRANSIT_PROBE " + JSON.stringify({"room":report.loaded_room,"actor_count":actors.size(),
		"restoration":restoration,"restoration_pass":restoration_pass,
		"all_figures_path":base_path.found,"static_only_path":static_path.found,
		"production_route_points":production.size(),"report":output,"acceptance_eligible":false}))
	game.queue_free()
	await process_frame
	quit(0 if restoration_pass else 1)

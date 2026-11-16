extends SceneTree
## Development-only one-variable search on a restored, paused kitchen snapshot.
## Only the named actor's position changes per trial; other actors, the camera,
## evidence, geometry and the source checkpoint remain untouched. This uses the
## production approach planner, but is neither a ray test nor acceptance.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Approach := preload("res://scenes/components/interaction/InteractionApproach.gd")
const Source := preload("res://mcp/CaptureSource.gd")

func _initialize() -> void:
	_run.call_deferred()

func _arg(name: String, fallback := "") -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(name + "="): return argument.trim_prefix(name + "=")
	return fallback

func _xz(p: Vector2) -> Array:
	return [p.x, p.y]

func _position(node: Node3D) -> Vector2:
	return Vector2(node.global_position.x, node.global_position.z)

func _plans(game: Control, start: Vector2) -> Dictionary:
	var grid: AStarGrid2D = game._route_grid_with_figures()
	var out := {}
	for item: Dictionary in game.kitchen._items:
		var target := Vector2(float(item.pos.x), float(item.pos.z))
		var kind: String = game.interactions.kind_for(str(item.id))
		var plan: Dictionary = Approach.plan(game, target, kind, start, grid)
		out[str(item.id)] = {"ok":bool(plan.ok), "reason":str(plan.get("reason", "")),
			"stand":_xz(plan.stand), "distance_to_target":plan.stand.distance_to(target),
			"already_near":bool(plan.already_near), "path_points":plan.path.size()}
	return out

func _all_plans_pass(plans: Dictionary) -> bool:
	if plans.is_empty(): return false
	for plan: Dictionary in plans.values():
		if not plan.ok: return false
	return true

func _candidate_allowed(game: Control, id: String, p: Vector2) -> bool:
	if not game._lowpoly_ok or game.lowpoly == null: return false
	var bounds: Rect2 = game.lowpoly.walk_rect(game.ACTOR_WALL_MARGIN)
	if not bounds.has_point(p) or game._grid.is_point_solid(game._cell_of(p)): return false
	for obstacle: Rect2 in game.lowpoly.obstacle_rects():
		if obstacle.grow(game.ACTOR_FURNITURE_MARGIN).has_point(p): return false
	if game._blocks_entry_lane(p): return false
	if p.distance_to(game.det_pos) < game.ACTOR_MIN_DISTANCE: return false
	for other in game.figures:
		if str(other) == id: continue
		var figure: Node3D = game.figures[other]
		if is_instance_valid(figure) and p.distance_to(_position(figure)) < game.ACTOR_MIN_DISTANCE: return false
	return true

func _run() -> void:
	var snapshot := _arg("--dv-snapshot")
	var output := _arg("--dv-candidate-output")
	var actor_id := _arg("--dv-actor-id", "huo")
	var step_text := _arg("--dv-sample-step", "0.3")
	if not step_text.is_valid_float() or float(step_text) < 0.05 or float(step_text) > 0.3:
		printerr("Sample step must be between 0.05 and 0.3 metres")
		quit(2)
		return
	var sample_step := float(step_text)
	if snapshot.is_empty() or output.is_empty() or Source.project_output(snapshot).is_empty() or Source.project_output(output).is_empty():
		printerr("Project-local --dv-snapshot and --dv-candidate-output required")
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
	game.eng.s.playing = false
	game.set_process(false)
	for controller in [game.opening, game.kitchen, game.gathering]:
		if is_instance_valid(controller): controller.set_process(false)
	await process_frame
	if not is_instance_valid(game.kitchen) or not game.kitchen.active or game.kitchen.phase != "free" or not game.figures.has(actor_id):
		printerr("Expected kitchen free snapshot and actor missing")
		quit(2)
		return
	var actor: Node3D = game.figures[actor_id]
	var original: Vector3 = actor.position
	var original_world: Vector2 = _position(actor)
	var others := {}
	for id in game.figures:
		if str(id) != actor_id: others[str(id)] = _xz(_position(game.figures[id]))
	var start: Vector2 = game.det_pos
	var before := _plans(game, start)
	var candidates: Array[Vector2] = []
	var sample_width := int(ceil(float(game._grid.region.size.x) * game.CELL / sample_step))
	var sample_depth := int(ceil(float(game._grid.region.size.y) * game.CELL / sample_step))
	for x in sample_width:
		for z in sample_depth:
			var p := Vector2((x + 0.5) * sample_step, (z + 0.5) * sample_step)
			if _candidate_allowed(game, actor_id, p): candidates.append(p)
	candidates.sort_custom(func(a: Vector2, b: Vector2) -> bool:
		return a.distance_squared_to(original_world) < b.distance_squared_to(original_world))
	var trials := []
	var valid := []
	var started := Time.get_ticks_usec()
	for p: Vector2 in candidates:
		# Figures are children of an identity-transform room root in this scene;
		# assign global position so the trial remains correct if that changes.
		actor.global_position = Vector3(p.x, actor.global_position.y, p.y)
		if not game._det_can_occupy(start): continue
		var plans := _plans(game, start)
		var pass_all := _all_plans_pass(plans)
		var failed := []
		for id in plans:
			if not plans[id].ok: failed.append(id)
		var trial := {"position":_xz(p), "move_distance":p.distance_to(original_world),
			"all_plans_pass":pass_all, "failed_ids":failed}
		trials.append(trial)
		if pass_all:
			trial["plans"] = plans
			valid.append(trial)
			if valid.size() >= 12: break
	actor.position = original
	var other_positions_unchanged := true
	for id in others:
		if _xz(_position(game.figures[id])) != others[id]: other_positions_unchanged = false
	var report := {"format":"kitchen-one-actor-candidates-v1", "source_identity":Source.identity(self, "res://scenes/dual_world/DualWorldMain.tscn"),
		"snapshot":Source.project_output(snapshot), "snapshot_sha256":FileAccess.get_sha256(snapshot),
		"room":str(game.eng.s.room), "controller":str(game.kitchen.phase), "actor":actor_id,
		"original_position":_xz(original_world), "detective":_xz(start), "other_actors":others,
		"other_actors_unchanged":other_positions_unchanged, "baseline_plans":before,
		"sample_step":sample_step,
		"candidate_rules":"sampled positions respecting production grid, wall/furniture margins, entry lane and 1.52m actor clearance",
		"candidate_count":candidates.size(), "trial_count":trials.size(), "trials":trials, "passing_candidates":valid,
		"planning_elapsed_ms":(Time.get_ticks_usec() - started) / 1000.0,
		"scope":"one actor at a time; diagnostic only, no ray, no real input, no acceptance",
		"acceptance_eligible":false, "acceptance_scored":false}
	var absolute := Source.project_output(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write candidate diagnostic")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify({"report":absolute, "baseline_all_pass":_all_plans_pass(before), "candidates":candidates.size(),
		"trials":trials.size(), "passing":valid.size(), "other_actors_unchanged":other_positions_unchanged,
		"acceptance_eligible":false}))
	game.queue_free()
	await process_frame
	quit(0 if other_positions_unchanged else 1)

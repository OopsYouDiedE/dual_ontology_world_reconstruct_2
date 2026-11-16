extends SceneTree
## Read-only counterfactual: compare original doors from an exactly restored
## development exit checkpoint. The selected passage is temporarily changed for
## occupancy queries only; no actor, prop, camera or story state is changed.
## A sampled route is not a physics-ray, screenshot, five-second room gate or
## independent acceptance result.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Source := preload("res://mcp/CaptureSource.gd")
const SAMPLE := 0.025

func _initialize() -> void: _run.call_deferred()

func _arg(key: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(key + "="): return argument.trim_prefix(key + "=")
	return ""

func _xy(value: Vector2) -> Array: return [value.x, value.y]

func _segment(game: Control, a: Vector2, b: Vector2) -> Dictionary:
	var steps := maxi(1, int(ceil(a.distance_to(b) / SAMPLE)))
	for i in range(steps + 1):
		var p := a.lerp(b, float(i) / float(steps))
		if not game._det_can_occupy(p):
			var neighbours := []
			for id in game.figures:
				var actor: Node3D = game.figures[id]
				if is_instance_valid(actor):
					var distance := p.distance_to(Vector2(actor.global_position.x, actor.global_position.z))
					if distance < game.ACTOR_MIN_DISTANCE: neighbours.append({"id":str(id), "distance":distance})
			return {"clear":false, "first_blocked":_xy(p), "nearby_actors":neighbours}
	return {"clear":true, "first_blocked":[], "nearby_actors":[]}

func _candidate(game: Control, name: String, direction: Vector2) -> Dictionary:
	var op: Dictionary = game._door_for(game.room_mesh.design, direction)
	if op.is_empty(): return {"name":name, "door_exists":false, "sampled_path_pass":false}
	game._door_passage = op.duplicate(true)
	var start: Vector2 = game.det_pos
	var inner: Vector2 = op.inner
	var center: Vector2 = op.pos
	var outer: Vector2 = op.outer
	var route: Array = game._route(start, inner)
	var exact_goal: bool = not route.is_empty() and (route.back() as Vector2).distance_to(inner) < 0.001
	var encoded := []
	for point: Vector2 in route: encoded.append(_xy(point))
	var segments := []
	var prior := start
	for point: Vector2 in route:
		segments.append(_segment(game, prior, point))
		prior = point
	var to_center := _segment(game, inner, center)
	var to_outer := _segment(game, center, outer)
	var clear := exact_goal and bool(to_center.clear) and bool(to_outer.clear)
	for part in segments:
		if not part.clear: clear = false
	return {"name":name, "door_exists":true, "direction":_xy(direction),
		"door":{"inner":_xy(inner), "center":_xy(center), "outer":_xy(outer)},
		"inner_occupiable":game._det_can_occupy(inner), "center_occupiable":game._det_can_occupy(center),
		"outer_occupiable":game._det_can_occupy(outer), "production_route":encoded,
		"route_ends_at_exact_inner":exact_goal, "route_segments":segments,
		"inner_to_center":to_center, "center_to_outer":to_outer,
		"sampled_path_pass":clear}

func _run() -> void:
	var snapshot := Source.project_output(_arg("--dv-snapshot"))
	var output := Source.project_output(_arg("--dv-door-candidates-output"))
	if snapshot.is_empty() or output.is_empty():
		printerr("Project-local snapshot and report required"); quit(2); return
	var game = Main.instantiate()
	game.show_intro = false
	root.add_child(game)
	current_scene = game
	if not is_instance_valid(game.checkpoints) or not game.checkpoints.restored:
		printerr("Checkpoint restore failed"); quit(2); return
	game.checkpoints.automatic = false
	game.checkpoints.output_path = ""
	game.checkpoints.set_process(false)
	game.set_process(false)
	# Restoring can rebuild multiple rooms in one frame. Let queue_free retire
	# the superseded meshes before describing the original room's visible nodes.
	await process_frame
	var saved: Dictionary = game.checkpoints.read_snapshot(snapshot)
	if saved.is_empty() or not game._transit_active() or str(game._transit.phase) != "exit" or game._door_passage.is_empty() or game.figures.keys() != saved.presentation.actors.keys():
		printerr("Snapshot is not an exactly restored active exit"); quit(2); return
	for id in saved.presentation.actors:
		if not game.figures[id].transform.is_equal_approx(saved.presentation.actors[id].transform):
			printerr("Saved actor transform mismatch: ", id); quit(2); return
	var before: Dictionary = game.checkpoints.capture()
	var original: Dictionary = game._door_passage.duplicate(true)
	var from := str(game._transit.from)
	var to := str(game._transit.to)
	var hops: Array = game.eng.path_to(to, from)
	var directions := {"ultimate_destination":game._room_dir(from, to),
		"east":Vector2.RIGHT, "west":Vector2.LEFT, "north":Vector2.UP, "south":Vector2.DOWN}
	if hops.size() >= 2: directions["logical_next_hop"] = game._room_dir(from, str(hops[1]))
	var results := {}
	var started := Time.get_ticks_usec()
	for name in directions: results[name] = _candidate(game, str(name), directions[name])
	game._door_passage = original
	var after: Dictionary = game.checkpoints.capture()
	var unchanged: bool = before.engine == after.engine and before.presentation == after.presentation
	var visible_meshes := []
	for mesh: MeshInstance3D in game.room_mesh.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		var center: Vector3 = mesh.to_global(mesh.get_aabb().get_center())
		visible_meshes.append({"path":str(mesh.get_path()), "visible":mesh.is_visible_in_tree(),
			"center":[center.x,center.y,center.z], "size":[mesh.get_aabb().size.x,mesh.get_aabb().size.y,mesh.get_aabb().size.z]})
	var report := {"format":"transit-door-candidates-v1", "source_identity":Source.identity(self, "res://scenes/dual_world/DualWorldMain.tscn"),
		"snapshot":snapshot, "snapshot_sha256":FileAccess.get_sha256(snapshot), "from":from, "to":to,
		"logical_hops":hops, "detective":_xy(game.det_pos), "candidates":results,
		"original_visible_meshes":visible_meshes, "state_unchanged":unchanged,
		"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0, "sample_step_m":SAMPLE,
		"scope":"counterfactual choice of an existing passage, no actor/object/camera movement; sampled navigation only, no original-camera physical ray or room-gate claim",
		"acceptance_eligible":false, "acceptance_scored":false}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null: printerr("Cannot write report"); quit(2); return
	file.store_string(JSON.stringify(report, "  ")); file.close()
	var passing := []
	for name in results:
		if results[name].sampled_path_pass: passing.append(name)
	print("DOOR_CANDIDATES " + JSON.stringify({"hops":hops,"passing":passing,"state_unchanged":unchanged,"elapsed_ms":report.elapsed_ms,"output":output,"acceptance_eligible":false}))
	game.queue_free()
	await process_frame
	quit(0 if unchanged else 1)

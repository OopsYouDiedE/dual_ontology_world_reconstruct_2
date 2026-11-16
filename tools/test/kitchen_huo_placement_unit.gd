extends SceneTree
## Development regression against the real restored room and production spawn.
## It does not simulate natural play, score performance or issue acceptance.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Approach := preload("res://scenes/components/interaction/InteractionApproach.gd")
const Source := preload("res://mcp/CaptureSource.gd")
var failures: Array[String] = []
var checks: Array[Dictionary] = []

func _initialize() -> void:
	_run.call_deferred()

func _arg(key: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(key + "="): return argument.trim_prefix(key + "=")
	return ""

func _check(condition: bool, message: String) -> void:
	checks.append({"pass":condition, "name":message})
	print(("PASS " if condition else "FAIL ") + message)
	if not condition: failures.append(message)

func _xz(node: Node3D) -> Vector2:
	return Vector2(node.global_position.x, node.global_position.z)

func _encode(point: Vector2) -> Array:
	return [point.x, point.y]

func _run() -> void:
	var snapshot := _arg("--dv-snapshot")
	var output := Source.project_output(_arg("--dv-placement-output"))
	if snapshot.is_empty() or Source.project_output(snapshot).is_empty() or output.is_empty():
		printerr("Project-local snapshot and output required")
		quit(2)
		return
	var game = Main.instantiate()
	game.show_intro = false
	root.add_child(game)
	current_scene = game
	if not is_instance_valid(game.checkpoints) or not game.checkpoints.restored:
		printerr("Checkpoint did not restore")
		quit(2)
		return
	game.checkpoints.automatic = false
	game.checkpoints.output_path = ""
	game.checkpoints.set_process(false)
	game.set_process(false)
	for controller in [game.opening, game.kitchen, game.gathering]:
		if is_instance_valid(controller): controller.set_process(false)
	await process_frame
	if not is_instance_valid(game.kitchen) or not game.kitchen.active or game.kitchen.phase != "free" or not game.figures.has("huo"):
		printerr("Expected kitchen free snapshot with Huo")
		quit(2)
		return
	var others := {}
	for id in game.figures:
		if str(id) != "huo": others[str(id)] = _xz(game.figures[id])
	var original_huo := _xz(game.figures["huo"])
	var camera: Transform3D = game.cam.global_transform
	var detective: Vector2 = game.det_pos
	var rule_state: Dictionary = game.eng.save_dict()
	var all_actors: Array = game.eng.actors_in_room(game._room_loaded).filter(func(id): return str(id) != "detective")
	var slots: Array = game._free_slots(all_actors.size() + 1)
	var index: int = all_actors.find("huo") + 1
	if index <= 0 or index >= slots.size():
		printerr("Expected Huo spawn slot")
		quit(2)
		return
	var fallback: Vector2 = slots[index]
	var candidate: Vector2 = game.KITCHEN_HUO_CLEAR_STAND
	_check(game._kitchen_huo_slot(fallback, slots, index, true).is_equal_approx(candidate), "verified room uses the authored clear position")
	var blocked_slots := slots.duplicate(true)
	blocked_slots[0] = candidate
	_check(game._kitchen_huo_slot(fallback, blocked_slots, index, true).is_equal_approx(fallback), "another spawn occupying candidate causes fallback")
	game.det_pos = candidate
	_check(game._kitchen_huo_slot(fallback, slots, index, false).is_equal_approx(fallback), "live detective occupying candidate causes fallback")
	game.det_pos = detective
	var room: String = game._room_loaded
	game._room_loaded = "R05"
	_check(game._kitchen_huo_slot(fallback, slots, index, true).is_equal_approx(fallback), "other rooms keep their normal slots")
	game._room_loaded = room
	var lowpoly: bool = game._lowpoly_ok
	game._lowpoly_ok = false
	_check(game._kitchen_huo_slot(fallback, slots, index, true).is_equal_approx(fallback), "missing matching lowpoly room keeps normal slot")
	game._lowpoly_ok = lowpoly
	# Force exactly the production spawn synchronization used when a room is built.
	game._occ_key = ""
	game._sync_figures(true)
	_check(game.figures.has("huo") and _xz(game.figures["huo"]).is_equal_approx(candidate), "actual production figure spawn applies the single-actor placement")
	var other_positions := {}
	for id in others:
		var present: bool = game.figures.has(id)
		var position: Vector2 = _xz(game.figures[id]) if present else Vector2.INF
		other_positions[id] = _encode(position)
		_check(present and position.is_equal_approx(others[id]), "other actor unchanged: " + id)
	_check(game.det_pos.is_equal_approx(detective) and game._det_can_occupy(detective), "detective position unchanged and occupiable")
	_check(game.cam.global_transform.is_equal_approx(camera), "original room camera unchanged")
	_check(game.eng.save_dict() == rule_state, "rule state and evidence unchanged")
	var grid: AStarGrid2D = game._route_grid_with_figures()
	var plans := {}
	for item: Dictionary in game.kitchen._items:
		var target := Vector2(float(item.pos.x), float(item.pos.z))
		var kind: String = game.interactions.kind_for(str(item.id))
		var plan: Dictionary = Approach.plan(game, target, kind, detective, grid)
		plans[str(item.id)] = {"ok":bool(plan.ok), "reason":str(plan.get("reason", "")),
			"stand":_encode(plan.stand), "path_points":plan.path.size()}
		_check(bool(plan.ok), "production plan to " + str(item.id))
	_check(plans.size() == 7, "all seven kitchen evidence items exercised")
	var report := {"format":"kitchen-huo-production-placement-regression-v1",
		"source_identity":Source.identity(self, "res://scenes/dual_world/DualWorldMain.tscn"),
		"source_checkpoint":Source.project_output(snapshot), "source_sha256":FileAccess.get_sha256(snapshot),
		"original_huo":_encode(original_huo), "actual_huo":_encode(_xz(game.figures["huo"])),
		"other_positions":other_positions, "detective":_encode(detective), "plans":plans,
		"checks":checks, "failures":failures, "pass":failures.is_empty(),
		"method":"restored fixture followed by production _sync_figures(true); no natural play",
		"acceptance_eligible":false, "acceptance_scored":false}
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var file := FileAccess.open(output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write placement regression")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print("PLACEMENT_RESULT " + JSON.stringify({"checks":checks.size(), "failures":failures, "report":output, "acceptance_eligible":false}))
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

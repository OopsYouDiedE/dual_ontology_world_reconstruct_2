extends SceneTree
## One paused, snapshot-based developer call into KitchenExploration.interact().
## It does not synthesize a mouse click, finish an interaction, or constitute
## a natural-play / independent acceptance result.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Approach := preload("res://scenes/components/interaction/InteractionApproach.gd")
const Source := preload("res://mcp/CaptureSource.gd")

func _initialize() -> void:
	_run.call_deferred()

func _arg(name: String, fallback := "") -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(name + "="): return argument.trim_prefix(name + "=")
	return fallback

func _xz(value: Vector2) -> Array:
	return [value.x, value.y]

func _path(values: Array) -> Array:
	var encoded := []
	for value: Vector2 in values: encoded.append(_xz(value))
	return encoded

func _run() -> void:
	var snapshot := _arg("--dv-snapshot")
	var output := _arg("--dv-kitchen-click-output")
	var item_id := _arg("--dv-interaction-id", "e_b_seal")
	if snapshot.is_empty() or output.is_empty() or Source.project_output(snapshot).is_empty() or Source.project_output(output).is_empty():
		printerr("Project-local snapshot and diagnostic output required")
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
	if not is_instance_valid(game.kitchen) or not game.kitchen.active or game.kitchen.phase != "free":
		printerr("Snapshot is not in kitchen free exploration")
		quit(2)
		return
	var index := -1
	for i in game.kitchen._items.size():
		if str(game.kitchen._items[i].id) == item_id: index = i
	if index < 0:
		printerr("Requested kitchen item does not exist: " + item_id)
		quit(2)
		return
	var item: Dictionary = game.kitchen._items[index]
	var target := Vector2(float(item.pos.x), float(item.pos.z))
	var start: Vector2 = game.det_pos
	var kind: String = game.interactions.kind_for(item_id)
	var plan: Dictionary = Approach.plan(game, target, kind, start)
	var before := {"position":_xz(start), "distance_to_item":start.distance_to(target),
		"phase":str(game.kitchen.phase), "cinematic":bool(game._cine), "modal_visible":bool(game.modal.visible),
		"subtitle_visible":bool(game.subtitle.visible), "subtitle_queue_size":game._sub_queue.size(),
		"busy_item":int(game.kitchen._busy_item), "path":_path(game.det_path),
		"interaction_active":is_instance_valid(game.interactions.active), "evidence_recorded":game.eng.s.evidence.has(item_id)}
	var guards_pass: bool = not before.cinematic and not before.modal_visible and not before.subtitle_visible \
		and before.subtitle_queue_size == 0 and before.busy_item < 0 and before.path.is_empty() and not before.interaction_active
	# This calls the same production target handler that a click would reach,
	# but deliberately does not claim that a real screen click was performed.
	game.kitchen.interact(index)
	var after := {"position":_xz(game.det_pos), "busy_item":int(game.kitchen._busy_item),
		"path":_path(game.det_path), "interaction_active":is_instance_valid(game.interactions.active),
		"evidence_recorded":game.eng.s.evidence.has(item_id)}
	var accepted: bool = guards_pass and (after.interaction_active or (after.busy_item == index and not after.path.is_empty()))
	var reason := ""
	if not guards_pass: reason = "snapshot_has_active_input_guard_or_existing_activity"
	elif not bool(plan.ok): reason = str(plan.get("reason", "approach_rejected"))
	elif not accepted: reason = "handler_did_not_start_interaction_or_route"
	var report := {"format":"kitchen-click-diagnostic-v1", "status":"diagnostic_complete",
		"source_identity":Source.identity(self, "res://scenes/dual_world/DualWorldMain.tscn"),
		"snapshot":Source.project_output(snapshot), "snapshot_sha256":FileAccess.get_sha256(snapshot),
		"room":str(game.eng.s.room), "interaction_id":item_id, "target_position":_xz(target), "kind":kind,
		"guards_pass":guards_pass, "approach":{"ok":bool(plan.ok), "reason":str(plan.get("reason", "")),
			"already_near":bool(plan.already_near), "stand":_xz(plan.stand), "path":_path(plan.path)},
		"before":before, "after_immediate":after, "handler_accepted":accepted, "reason":reason,
		"input_method":"direct_production_handler_call_not_mouse", "observation":"immediate_decision_only_not_completed_interaction",
		"acceptance_eligible":false, "acceptance_scored":false}
	var absolute := Source.project_output(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write kitchen diagnostic")
		quit(2)
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify({"report":absolute, "guards_pass":guards_pass, "approach_ok":plan.ok,
		"handler_accepted":accepted, "reason":reason, "acceptance_eligible":false}))
	if is_instance_valid(game.interactions.active): game.interactions.cancel()
	game.queue_free()
	await process_frame
	quit()

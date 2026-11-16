extends SceneTree
## Construct a *development-only* derived checkpoint for a single NPC trial.
## No game source or existing checkpoint is changed. All saved rule, camera,
## prop and other-actor state must compare equal before the output is written.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Source := preload("res://mcp/CaptureSource.gd")

func _initialize() -> void:
	_run.call_deferred()

func _arg(key: String, fallback := "") -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(key + "="): return argument.trim_prefix(key + "=")
	return fallback

func _xz(p: Vector3) -> Array:
	return [p.x, p.z]

func _fail(message: String) -> void:
	printerr(message)
	quit(2)

func _run() -> void:
	var snapshot := Source.project_output(_arg("--dv-snapshot"))
	var output := Source.project_output(_arg("--dv-derived-snapshot"))
	var report_path := Source.project_output(_arg("--dv-derived-report"))
	var actor_id := _arg("--dv-actor-id", "huo")
	var sx := _arg("--dv-x")
	var sz := _arg("--dv-z")
	if snapshot.is_empty() or output.is_empty() or report_path.is_empty() or output == snapshot or not sx.is_valid_float() or not sz.is_valid_float():
		_fail("Distinct project-local source/output/report and numeric coordinates required")
		return
	if FileAccess.file_exists(output) or FileAccess.file_exists(report_path):
		_fail("Refusing to overwrite an existing fixture or report")
		return
	var p := Vector2(float(sx), float(sz))
	if not is_finite(p.x) or not is_finite(p.y):
		_fail("Non-finite actor coordinate")
		return
	var game = Main.instantiate()
	game.show_intro = false
	root.add_child(game)
	current_scene = game
	if not is_instance_valid(game.checkpoints) or not game.checkpoints.restored:
		_fail("Source checkpoint failed to restore")
		return
	game.checkpoints.automatic = false
	game.checkpoints.output_path = ""
	game.checkpoints.set_process(false)
	game.set_process(false)
	for controller in [game.opening, game.kitchen, game.gathering]:
		if is_instance_valid(controller): controller.set_process(false)
	await process_frame
	if not is_instance_valid(game.kitchen) or not game.kitchen.active or game.kitchen.phase != "free" or not game.figures.has(actor_id):
		_fail("Source must be a kitchen-free checkpoint containing the selected actor")
		return
	var actor: Node3D = game.figures[actor_id]
	var old_pos: Vector3 = actor.global_position
	var before: Dictionary = game.checkpoints.capture()
	actor.global_position = Vector3(p.x, old_pos.y, p.y)
	var center: Vector3 = game.lowpoly.center() if game._lowpoly_ok else game.room_mesh.center()
	var facing := Vector2(center.x, center.z) - p
	actor.rotation.y = atan2(facing.x, facing.y)
	var after: Dictionary = game.checkpoints.capture()
	var before_presentation: Dictionary = before.presentation.duplicate(true)
	var after_presentation: Dictionary = after.presentation.duplicate(true)
	before_presentation.actors.erase(actor_id)
	after_presentation.actors.erase(actor_id)
	var same_presentation: bool = before_presentation == after_presentation
	var same_rules: bool = before.engine == after.engine
	if not same_presentation or not same_rules:
		_fail("Unexpected non-actor state changed; refusing to write fixture")
		return
	if not game.checkpoints.save_now(output):
		_fail("Cannot write derived fixture: " + game.checkpoints.error)
		return
	var report := {"format":"kitchen-single-actor-derived-fixture-v1",
		"source_identity":Source.identity(self, "res://scenes/dual_world/DualWorldMain.tscn"),
		"source_checkpoint":snapshot, "source_sha256":FileAccess.get_sha256(snapshot),
		"derived_checkpoint":output, "derived_sha256":FileAccess.get_sha256(output),
		"actor_id":actor_id, "original_position":_xz(old_pos), "trial_position":_xz(actor.global_position),
		"trial_yaw":actor.rotation.y, "other_presentation_identical":same_presentation,
		"rule_engine_identical":same_rules, "purpose":"one-actor-position-and-facing preflight fixture; not production spawn",
		"acceptance_eligible":false, "acceptance_scored":false}
	DirAccess.make_dir_recursive_absolute(report_path.get_base_dir())
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		_fail("Cannot write fixture report")
		return
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify(report))
	game.queue_free()
	await process_frame
	quit()

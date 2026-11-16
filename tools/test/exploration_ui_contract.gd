extends SceneTree
## Snapshot-only UI regression. This development capture never supplies acceptance scores.
const Shell := preload("res://scenes/main/Main.tscn")
const Source := preload("res://mcp/CaptureSource.gd")
const Checkpoint := preload("res://scenes/components/testing/StoryCheckpoint.gd")
var failures: Array[String] = []
var checks: Array = []
var shell: Control
var game: Control
var output := ""
var started := Time.get_ticks_usec()


func _initialize() -> void:
	_run.call_deferred()


func check(value: bool, label: String) -> void:
	checks.append({"check": label, "pass": value})
	if not value: failures.append(label)


func _wait_book() -> void:
	var deadline := Time.get_ticks_msec() + 3000
	while shell.book_ui.busy() and Time.get_ticks_msec() < deadline:
		await process_frame
	check(not shell.book_ui.busy(), "physical book animation completed")


func _capture(label: String) -> void:
	if Checkpoint.argument("--dv-ui-capture") != "true": return
	await process_frame
	# A minimized diagnostic host still needs an explicit rendered frame.
	if is_instance_valid(game): game.room_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	var image: Image = root.get_texture().get_image()
	var path := output.get_basename() + "-" + label + ".png"
	image.save_png(path)
	var metadata := {"source_identity": Source.identity(self, "res://tools/test/exploration_ui_contract.gd"),
		"capture_kind": "development-ui-contract", "acceptance_eligible": false,
		"snapshot_path": Checkpoint.argument("--dv-snapshot"), "image_sha256": FileAccess.get_sha256(path)}
	var file := FileAccess.open(path + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(metadata, "  "))
	file.close()


func _hidden_chrome(label: String) -> void:
	for key in ["top_bar", "left_card", "room_hint", "drawer"]:
		check(not game.get(key).visible, label + ": " + key + " hidden")
	check(not game.drawer_btn.button_pressed, label + ": drawer toggle reset")
	check(game.room_container.get_rect().size.is_equal_approx(game.center.size), label + ": room fills center")


func _run() -> void:
	output = Source.project_output(Checkpoint.argument("--dv-ui-output", ".runtime/ui-contract/result.json"))
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	shell = Shell.instantiate()
	root.add_child(shell)
	current_scene = shell
	shell.stage.reduce_motion = true
	await process_frame
	# Verify title settings directly; no title/new-game story traversal is involved.
	shell._settings_requested()
	await _wait_book()
	check(shell.book_ui.is_open and shell.book_ui.page_id() == "settings", "title settings opens physical book")
	await _capture("title-settings")
	shell.book_ui.close()
	await _wait_book()
	check(not shell.book_ui.is_open and shell.title_ui.interactive, "title settings closes back to title")
	shell.open_dual_world()
	game = shell.dual_world
	check(game.checkpoints.restored, "existing project snapshot restored")
	game.checkpoints.automatic = false
	game.checkpoints.output_path = ""
	game.set_process(false)
	await process_frame
	game._sync_exploration_ui()
	_hidden_chrome("restored exploration")
	var controller: Node = game.opening if is_instance_valid(game.opening) and game.opening.active else game.kitchen
	check(is_instance_valid(controller) and controller.phase == "free", "fixture has active free exploration controller")
	var fixture_fade_alpha: float = game.fade_rect.modulate.a
	if controller == game.opening and fixture_fade_alpha > 0.0:
		# The existing free-phase fixture retains its original opening black frame.
		# Finish the production fade before the UI screenshot; record this adjustment.
		game._fade(0.0, 0.01)
		await create_timer(0.02).timeout
	var prompt: Label = controller._prompt
	var positions_before: Dictionary = {}
	for actor_id in game.figures:
		positions_before[actor_id] = game.figures[actor_id].global_transform
	game._sub_queue.clear()
	game.subtitle.visible = false
	game._cine = false
	controller._step_free(0.0)
	check(is_instance_valid(prompt), "controller retains E interaction prompt")
	var prompt_before := {"visible": prompt.visible, "text": prompt.text}
	var tag_found := false
	for child in game.det.get_children():
		if child is Label3D and child.visible: tag_found = true
	check(tag_found, "detective nameplate remains visible")
	await _capture("before-end")
	# Exercise the exact failing production lifecycle endpoint.
	if controller == game.opening: controller._end()
	else: controller.end()
	_hidden_chrome("controller end immediate")
	game._sync_hud_for_modal()
	_hidden_chrome("controller end synchronized")
	await process_frame
	await _capture("after-end")
	var time_before: float = game.eng.s.t
	var playing_before: bool = game.eng.s.playing
	var event := InputEventAction.new()
	event.action = "notebook"
	event.pressed = true
	game._unhandled_input(event)
	await _wait_book()
	check(shell.book_ui.is_open and shell.book_ui.page_id() == "journal", "notebook input opens physical journal")
	check(not game.visible and game.process_mode == Node.PROCESS_MODE_DISABLED, "book owns screen and pauses exploration")
	check(is_equal_approx(game.eng.s.t, time_before), "book leaves story time unchanged")
	await _capture("field-journal")
	shell.book_ui.close()
	await _wait_book()
	check(game.visible and game.process_mode == Node.PROCESS_MODE_INHERIT, "book close restores exploration screen")
	check(not shell.title_ui.interactive and not shell.stage.visible, "book close keeps title stage hidden")
	check(game.eng.s.playing == playing_before, "book close restores prior play state")
	_hidden_chrome("book close")
	event.action = "settings"
	game._unhandled_input(event)
	await _wait_book()
	check(shell.book_ui.is_open and shell.book_ui.page_id() == "settings", "field settings input opens physical settings")
	await _capture("field-settings")
	shell.book_ui.close()
	await _wait_book()
	_hidden_chrome("settings close")
	for actor_id in positions_before:
		check(game.figures[actor_id].global_transform.is_equal_approx(positions_before[actor_id]), "UI leaves actor transform unchanged: " + str(actor_id))
	var report := {"pass": failures.is_empty(), "checks": checks, "failures": failures,
		"source_identity": Source.identity(self, "res://tools/test/exploration_ui_contract.gd"),
		"fixture": Checkpoint.argument("--dv-snapshot"), "acceptance_eligible": false,
		"prompt_before_end": prompt_before, "fixture_fade_alpha": fixture_fade_alpha,
		"free_phase_fade_completed": controller == game.opening and fixture_fade_alpha > 0.0,
		"elapsed_ms": (Time.get_ticks_usec() - started) / 1000.0}
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify({"pass": report.pass, "checks": checks.size(), "failures": failures, "report": output, "elapsed_ms": report.elapsed_ms}))
	shell.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

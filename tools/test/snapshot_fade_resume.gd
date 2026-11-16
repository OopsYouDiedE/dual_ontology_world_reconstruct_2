extends SceneTree
## Deterministic production fades plus fresh-process replay; development evidence only.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Checkpoint := preload("res://scenes/components/testing/StoryCheckpoint.gd")
const Source := preload("res://mcp/CaptureSource.gd")
var game: Control
var output := ""
var scenario := ""
var checks: Array = []
var failures: Array = []
var samples: Array = []
var screenshots: Array = []

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	checks.append({"check": label, "pass": ok})
	if not ok: failures.append(label)

func phase() -> String:
	if is_instance_valid(game.gathering) and game.gathering.active: return "corridor:" + game.gathering.phase
	if is_instance_valid(game.opening) and game.opening.active: return "opening:" + game.opening.phase
	if is_instance_valid(game.kitchen) and game.kitchen.active: return "kitchen:" + game.kitchen.phase
	return "transit:" + str(game._transit.get("phase", "done"))

func sample() -> void:
	samples.append({"ticks_ms": Time.get_ticks_msec(), "alpha": game.fade_rect.modulate.a, "phase": phase()})

func capture(label: String) -> void:
	if Checkpoint.argument("--dv-fade-capture") != "true": return
	game.room_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	var image: Image = root.get_texture().get_image()
	if game.fade_rect.modulate.a < 0.999:
		var thumbnail := image.duplicate() as Image
		thumbnail.resize(32, 20)
		var darkest := 1.0
		var brightest := 0.0
		for y in 20:
			for x in 32:
				var luminance := thumbnail.get_pixel(x, y).get_luminance()
				darkest = minf(darkest, luminance)
				brightest = maxf(brightest, luminance)
		check(brightest - darkest > 0.01 and brightest > 0.025, "GPU frame contains rendered scene detail: " + label)
	var path := output.get_basename() + "-" + label + ".png"
	check(image.save_png(path) == OK, "GPU screenshot saved: " + label)
	var sidecar := {"source_identity": Source.identity(self, "res://tools/test/snapshot_fade_resume.gd"),
		"capture_kind": "development-snapshot-fade", "acceptance_eligible": false,
		"checkpoint_script_sha256": FileAccess.get_sha256("res://scenes/components/testing/StoryCheckpoint.gd"),
		"scenario": scenario, "snapshot_path": Checkpoint.argument("--dv-snapshot"),
		"phase": phase(), "fade_alpha": game.fade_rect.modulate.a, "image_sha256": FileAccess.get_sha256(path)}
	var file := FileAccess.open(path + ".json", FileAccess.WRITE)
	file.store_string(JSON.stringify(sidecar, "  "))
	file.close()
	screenshots.append(path)

func advance_tween(seconds: float) -> void:
	game._fade_tween.pause()
	game._fade_tween.custom_step(seconds)

func prepare(snapshot_path: String) -> void:
	check(game.opening != null and game.opening.phase == "black", "production opening begins in intentional black")
	match scenario:
		"opening-black": game.opening.process(0.28)
		"opening-fade":
			game.opening.process(game.opening.T_BLACK + 0.01)
			advance_tween(0.6)
			game.opening.process(0.6)
		"corridor-cover", "corridor-reveal", "corridor-out", "transit-cover", "transit-reveal":
			check(game.checkpoints.restore_file("res://.runtime/checkpoints/fixtures/opening-free.json"), "existing bedroom free fixture loaded")
			advance_tween(2.0)
			if scenario.begins_with("corridor"):
				game.start_gathering("B-P")
				if scenario == "corridor-cover": advance_tween(0.12)
				else:
					advance_tween(0.31)
					check(game.gathering.phase == "exit", "production callback constructs corridor stage")
					if scenario == "corridor-reveal":
						advance_tween(0.18)
						game.gathering.process(0.18)
					else:
						advance_tween(0.6)
						game.gathering._enter_free()
						game.gathering._finish()
						advance_tween(0.14)
			else:
				game._stop_exploration()
				game.eng.s.room = "B-P"
				game._begin_transit("B-P")
				game._transit_exit_done()
				if scenario == "transit-cover": advance_tween(0.09)
				else:
					advance_tween(0.23)
					advance_tween(0.1)
		"chapter-cover", "chapter-reveal":
			game._stop_exploration()
			game.eng.s.chapter = 1
			game.eng.s.chapter_complete = true
			game._modal_chapter()
			var button_found := false
			for button in game.modal.find_children("*", "Button", true, false):
				if button.text == "第二章":
					button.pressed.emit()
					button_found = true
					break
			check(button_found, "production next-chapter button starts transition")
			if scenario == "chapter-cover": advance_tween(0.12)
			else:
				advance_tween(0.31)
				advance_tween(0.16)
		_: check(false, "known preparation case")
	check(game.checkpoints.save_now(snapshot_path), "interrupted production tween snapshot written")
	var snapshot: Dictionary = game.checkpoints.read_snapshot(snapshot_path)
	check(not snapshot.is_empty() and snapshot.presentation.has("fade_transition"), "new snapshot stores explicit fade state")
	sample()
	capture("saved")

func resume(snapshot_path: String) -> void:
	check(game.checkpoints.restored, "fresh process restores snapshot through production bind")
	var snapshot: Dictionary = game.checkpoints.read_snapshot(snapshot_path)
	if snapshot.is_empty():
		check(false, "snapshot integrity validated: " + game.checkpoints.error)
		return
	var p: Dictionary = snapshot.presentation
	var initial: float = p.ui.fade_rect.modulate.a
	check(is_equal_approx(game.fade_rect.modulate.a, initial), "restore preserves captured alpha without a flash")
	check(int(snapshot.source.process_id) > 0 and int(snapshot.source.process_id) != OS.get_process_id(), "snapshot source and fresh replay PID are positive and distinct")
	check(str(snapshot.source.project_root).replace("\\", "/").to_lower() == ProjectSettings.globalize_path("res://").trim_suffix("/").to_lower(), "snapshot source belongs to exact current project")
	sample()
	capture("initial")
	if scenario == "opening-black":
		await create_timer(0.08).timeout
		check(is_equal_approx(game.fade_rect.modulate.a, initial) and phase() == "opening:black", "intentional black remains until production phase timer completes")
		game.opening.process(game.opening.T_BLACK - game.opening._pt + 0.01)
		check(phase() == "opening:fade" and game._fade_tween.is_valid(), "remaining black phase starts real opening fade")
	else:
		var state: Dictionary = game.checkpoints._resumed_fade.duplicate(true)
		check(bool(state.active), "restored mask has a live continuation")
		var half := float(state.remaining_seconds) * 0.5
		advance_tween(half)
		var middle: float = game.fade_rect.modulate.a
		var target: float = state.target
		check(middle > minf(initial, target) and middle < maxf(initial, target), "halfway continuation interpolates toward intended endpoint")
		sample()
		capture("midpoint")
		var again := output.get_basename() + "-interrupted-again.json"
		check(game.checkpoints.save_now(again), "resumed tween can be interrupted again")
		var repeated: Dictionary = game.checkpoints.read_snapshot(again)
		check(absf(float(repeated.presentation.fade_transition.remaining_seconds) - half) < 0.002, "second checkpoint stores remaining time rather than full duration")
		check(game.checkpoints.restore_file(again), "second interruption restores successfully")
		check(is_equal_approx(game.fade_rect.modulate.a, middle), "second restore preserves intermediate alpha")
		var resumed: Dictionary = game.checkpoints._resumed_fade
		check(absf(float(resumed.remaining_seconds) - half) < 0.002, "second restore retains remaining duration")
	var deadline := Time.get_ticks_msec() + 2400
	while Time.get_ticks_msec() < deadline:
		await process_frame
		sample()
		if game.fade_rect.modulate.a <= 0.00001 and (game._fade_tween == null or not game._fade_tween.is_valid()): break
	check(game.fade_rect.modulate.a <= 0.00001, "continued fade reaches visible production endpoint")
	if scenario == "corridor-cover":
		check(phase() == "corridor:exit", "cover resumes corridor setup callback")
		check(game.det_root.get_parent().find_children("CorridorStage*", "Node3D", false, false).size() == 1, "corridor stage callback runs exactly once")
	elif scenario == "corridor-out":
		check(game.eng.s.room == "B-P" and is_instance_valid(game.kitchen), "corridor exit callback reaches production kitchen")
		check(not is_instance_valid(game.gathering), "corridor exit releases old stage")
	elif scenario == "transit-cover": check(game._room_loaded == "B-P" and game._transit.phase == "enter", "transit cover callback swaps to intended room")
	elif scenario == "opening-free": check(phase() == "opening:free", "legacy free snapshot stays in free exploration")
	elif scenario.begins_with("chapter"):
		check(int(game.eng.s.chapter) == 2 and not bool(game.eng.s.chapter_complete) and not game._cine, "chapter continuation reaches chapter two and releases cinematic state")
		check(not game.modal.visible, "chapter transition keeps dismissed completion modal closed")
	capture("final")

func identity_checks() -> void:
	var state: Dictionary = game.checkpoints.capture()
	var before: float = game.fade_rect.modulate.a
	var path := output.get_basename() + "-invalid-pid.json"
	state.source.process_id = 0
	Checkpoint.write_snapshot(path, state, 1)
	check(not game.checkpoints.restore_file(path) and game.checkpoints.error == "Checkpoint host PID mismatch", "nonpositive source PID rejected")
	state.source.process_id = OS.get_process_id()
	path = output.get_basename() + "-mismatched-pid.json"
	Checkpoint.write_snapshot(path, state, 1)
	var envelope: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	envelope.host_pid = OS.get_process_id() + 1
	var invalid_file := FileAccess.open(path, FileAccess.WRITE)
	invalid_file.store_string(JSON.stringify(envelope))
	invalid_file.close()
	check(not game.checkpoints.restore_file(path) and game.checkpoints.error == "Checkpoint host PID mismatch", "envelope and payload PID mismatch rejected")
	state.source.project_root = ProjectSettings.globalize_path("res://") + "foreign"
	path = output.get_basename() + "-invalid-project.json"
	Checkpoint.write_snapshot(path, state, 2)
	check(not game.checkpoints.restore_file(path) and game.checkpoints.error == "Checkpoint belongs to a different project directory", "foreign project source rejected")
	state.source = Source.identity(self)
	state.presentation.fade_transition.remaining_seconds = -1.0
	path = output.get_basename() + "-invalid-transition.json"
	Checkpoint.write_snapshot(path, state, 3)
	check(not game.checkpoints.restore_file(path) and game.checkpoints.error == "Checkpoint fade transition invalid", "invalid transition rejected before scene mutation")
	check(is_equal_approx(before, game.fade_rect.modulate.a), "rejected files leave live alpha unchanged")
	for case_name in ["opening-fade", "corridor-cover", "corridor-reveal", "corridor-out", "transit-cover", "transit-reveal", "chapter-cover", "chapter-reveal"]:
		var old: Dictionary = game.checkpoints.read_snapshot(output.get_base_dir() + "/" + case_name + "-fixture.json")
		check(not old.is_empty(), "compatibility source available: " + case_name)
		if old.is_empty(): continue
		old.presentation.erase("fade_transition")
		path = output.get_base_dir() + "/legacy-" + case_name + ".json"
		Checkpoint.write_snapshot(path, old, 1)
		check(game.checkpoints.restore_file(path), "v1 without fade metadata restores: " + case_name)
		var legacy_alpha: float = old.presentation.ui.fade_rect.modulate.a
		check(is_equal_approx(game.fade_rect.modulate.a, legacy_alpha), "v1 retains capture alpha: " + case_name)
		advance_tween(2.0)
		if game._fade_tween != null and game._fade_tween.is_valid(): advance_tween(2.0)
		check(game.fade_rect.modulate.a <= 0.00001, "v1 transition reaches visible endpoint: " + case_name)

func _run() -> void:
	var started := Time.get_ticks_msec()
	scenario = Checkpoint.argument("--dv-fade-case", "opening-free")
	output = Source.project_output(Checkpoint.argument("--dv-fade-output", "res://.runtime/fade-resume/result.json"))
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	game = Main.instantiate()
	root.add_child(game)
	current_scene = game
	game.set_process(false)
	game.checkpoints.automatic = false
	game.score.set_enabled(false)
	# Settle container layout while retaining the exact restored transition frame.
	var startup_tween: Tween = game._fade_tween
	if startup_tween != null and startup_tween.is_valid(): startup_tween.pause()
	await process_frame
	await process_frame
	if startup_tween != null and startup_tween.is_valid(): startup_tween.play()
	var prepare_mode := Checkpoint.argument("--dv-fade-prepare") == "true"
	var snapshot_path := Source.project_output(Checkpoint.argument("--dv-snapshot", output.get_base_dir() + "/" + scenario + "-fixture.json"))
	if prepare_mode: prepare(snapshot_path)
	elif scenario == "identity": identity_checks()
	else: await resume(snapshot_path)
	var state: Dictionary = game.checkpoints.capture()
	var report := {"pass": failures.is_empty(), "checks": checks, "failures": failures,
		"checkpoint_script_sha256": FileAccess.get_sha256("res://scenes/components/testing/StoryCheckpoint.gd"),
		"source_identity": Source.identity(self, "res://tools/test/snapshot_fade_resume.gd"),
		"scenario": scenario, "prepare": prepare_mode, "snapshot_path": snapshot_path,
		"fade_state": state.presentation.get("fade_transition", {}), "samples": samples, "screenshots": screenshots,
		"elapsed_ms": Time.get_ticks_msec() - started, "acceptance_eligible": false}
	var file := FileAccess.open(output, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  "))
	file.close()
	print(JSON.stringify({"pass": report.pass, "checks": checks.size(), "failures": failures, "report": output}))
	game.checkpoints.finalized = true
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

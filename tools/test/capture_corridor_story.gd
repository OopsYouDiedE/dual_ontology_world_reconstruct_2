extends SceneTree
## Capture the production gathering, preserving original frames and provenance.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Source := preload("res://mcp/CaptureSource.gd")
const Text := preload("res://scenes/components/testing/VisibleText.gd")
var game: Control
var output := ""
var tasks: Array[int] = []
var frames: Array = []

func arg(key: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(key + "="): return value.trim_prefix(key + "=")
	return ""

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "  "))
	file.close()

func _initialize() -> void:
	call_deferred("run")

func capture(key: String) -> void:
	await RenderingServer.frame_post_draw
	var path := output.path_join("%02d.png" % (frames.size() + 1))
	var image := root.get_texture().get_image()
	var texts: Array = []
	Text.collect(game, root, texts)
	var row := {"path":path,"phase":game.gathering.phase,"line":game.gathering._line,
		"key":key,"source_identity":Source.identity(self),"acceptance_eligible":false,
		"capture_kind":"production-corridor-story-development","visible_text":texts,
		"captured_local":Time.get_datetime_string_from_system(false,true),"engine_time_scale":Engine.time_scale}
	frames.append(row)
	tasks.append(WorkerThreadPool.add_task(func():
		row["write_error"] = image.save_png(path)
		row["image_sha256"] = FileAccess.get_sha256(path)
		write_json(path + ".json", row)))

func run() -> void:
	output = Source.project_output(arg("--output"))
	if output.is_empty() or ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/").get_file() != "dual_ontology_world_reconstruct_2" or OS.get_process_id() <= 0:
		quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1440,900)
	game = Main.instantiate()
	game.show_intro = false
	root.add_child(game)
	for i in 12: await process_frame
	game.checkpoints.automatic = false
	game.eng.s.t = 440.0
	game.det.set_pose("stand")
	game.start_gathering("B-P")
	var captured := {}
	var start := Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < 150000:
		await process_frame
		var g = game.gathering
		if g == null: break
		var key: String = g.phase + "-" + str(g._line)
		if g.phase == "approach": key += "-" + str(int(game.det_pos.x / 4))
		var want: bool = g.phase in ["exit","hear","approach","join","talk","card","free"]
		if want and g._pt > 0.35 and not captured.has(key):
			captured[key] = true
			await capture(key)
		if g.phase == "free" and captured.has(key): break
	game.checkpoints.save_now(output.path_join("end.snapshot.json"))
	for task in tasks: WorkerThreadPool.wait_for_task_completion(task)
	write_json(output.path_join("sequence.json"), {"source_identity":Source.identity(self),"acceptance_eligible":false,"frames":frames})
	print("CORRIDOR_CAPTURE frames=" + str(frames.size()) + " phase=" + str(game.gathering.phase))
	quit(0 if game.gathering.phase == "free" else 1)

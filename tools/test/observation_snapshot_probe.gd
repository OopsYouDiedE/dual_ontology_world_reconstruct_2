extends SceneTree
## Targeted development capture from a checkpoint, using the real arrival callback.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Source := preload("res://mcp/CaptureSource.gd")
const Fast := preload("res://scenes/components/testing/RoomFastCheck.gd")
const Text := preload("res://scenes/components/testing/VisibleText.gd")
var game: Control
var output := ""
var kind := ""
var frames: Array = []
var checks: Array = []
var tasks: Array[int] = []
var events: Array = []
var started := Time.get_ticks_usec()

func arg(key: String) -> String:
	for raw in OS.get_cmdline_user_args():
		if raw.begins_with(key + "="): return raw.trim_prefix(key + "=")
	return ""

func _initialize() -> void:
	_run.call_deferred()

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "  "))
	file.close()

func check(value: bool, label: String) -> void:
	checks.append({"check":label,"pass":value})

func wait_seconds(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until: await process_frame

func capture(phase: String) -> void:
	await RenderingServer.frame_post_draw
	var path := output.path_join(phase + ".png")
	var pixels := root.get_texture().get_image()
	var texts: Array = []
	Text.collect(game, root, texts)
	var row := {"path":path,"phase":phase,"kind":kind,"source_identity":Source.identity(self),
		"acceptance_eligible":false,"capture_kind":"checkpoint-observation-development",
		"captured_local":Time.get_datetime_string_from_system(false,true),"visible_text":texts,
		"time_s":(Time.get_ticks_usec()-started)/1000000.0,"camera":str(game.cam.global_transform)}
	frames.append(row)
	tasks.append(WorkerThreadPool.add_task(func():
		row["write_error"] = pixels.save_png(path)
		row["image_sha256"] = FileAccess.get_sha256(path)
		write_json(path + ".json", row)))

func _run() -> void:
	output = Source.project_output(arg("--probe-output"))
	kind = arg("--probe-kind")
	if output.is_empty() or Source.project_output(arg("--dv-snapshot")).is_empty():
		quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1440,900)
	game = Main.instantiate()
	game.show_intro = false
	root.add_child(game)
	current_scene = game
	if not game.checkpoints.restored or game.opening == null or game.opening.phase != "free":
		push_error("A restored bedroom free-exploration checkpoint is required")
		quit(2); return
	game.checkpoints.automatic = false
	game.checkpoints.output_path = ""
	game.eng.s.playing = false
	game.set_process(false)
	game._fade(0.0,0.01)
	await wait_seconds(0.02)
	var index := -1
	for i in game.opening._items.size():
		if str(game.opening._items[i].id) == kind: index = i
	if index < 0 or not game.evidence_presentations.has(kind):
		push_error("Unknown in-room observation")
		quit(2); return
	var prop: Node3D = game.evidence_presentations[kind]
	if kind == "wash":
		var basin := prop.get_node_or_null(NodePath(prop.get_meta("inspection_target", ""))) as MeshInstance3D
		check(is_instance_valid(basin) and basin.name == "Bowl_Dish","intended water basin is the explicit target")
		check(prop.to_global(prop.get_meta("focus",Vector3.ZERO)).y > 0.8,"water observation focuses above the cabinet")
	if kind == "window":
		var yard := prop.get_parent().get_node_or_null("WindowCourtyard")
		check(is_instance_valid(yard) and game.lowpoly._root.is_ancestor_of(yard),"courtyard remains under the original room window")
	var item: Dictionary = game.opening._items[index]
	# Mock placement uses the production route endpoint, checked separately by Fast.
	var planner := Fast.new()
	planner.host = game
	var plan := planner._stand(item,game.det_pos)
	var route: Array = [game.det_pos] if plan.already_near else game._route(game.det_pos,plan.stand)
	if route.is_empty():
		push_error("No production route to observation")
		quit(2); return
	game.det_pos = route.back()
	game.det.position = Vector3(game.det_pos.x,0,game.det_pos.y)
	game.det_path.clear()
	game.det_done = Callable()
	game._sub_queue.clear()
	game.subtitle.visible = false
	game._cine = false
	game.opening._busy_item = -1
	game.checkpoints.save_now(output.path_join("entry.snapshot.json"))
	var camera_id: int = game.cam.get_instance_id()
	var world_id: int = game.cam.get_world_3d().get_instance_id()
	var viewport_count := game.find_children("*","SubViewport",true,false).size()
	var saved_camera: Transform3D = game.cam.global_transform
	game.interactions.event_recorded.connect(func(e: Dictionary): events.append(e))
	await capture("01-entry")
	game.opening._arrive(index)
	var closeup: Control = game.interactions.active
	if not is_instance_valid(closeup): quit(2); return
	await wait_seconds(0.4)
	await capture("02-approach")
	var deadline := Time.get_ticks_msec() + 3000
	while not closeup._has_result and Time.get_ticks_msec() < deadline: await process_frame
	check(closeup._has_result,"production observation completed")
	check(game.cam.get_instance_id()==camera_id and game.cam.get_world_3d().get_instance_id()==world_id,"original camera and world retained")
	check(game.find_children("*","SubViewport",true,false).size()==viewport_count,"viewport count retained")
	await capture("03-result")
	closeup.close()
	while is_instance_valid(game.interactions.active) and Time.get_ticks_msec() < deadline + 1000: await process_frame
	check(game.cam.global_transform.is_equal_approx(saved_camera),"camera returned to checkpoint view")
	check(bool(item.seen),"production callback marked observation seen")
	await capture("04-return")
	for task in tasks: WorkerThreadPool.wait_for_task_completion(task)
	var passed := true
	for c in checks: if not c.pass: passed = false
	write_json(output.path_join("report.json"),{"pass":passed,"source_identity":Source.identity(self),"acceptance_eligible":false,
		"snapshot":arg("--dv-snapshot"),"mock_placement":"production route endpoint","frames":frames,"checks":checks,"events":events,
		"kind":kind,"elapsed_ms":(Time.get_ticks_usec()-started)/1000.0})
	print(JSON.stringify({"pass":passed,"kind":kind,"frames":frames.size(),"output":output}))
	game.queue_free()
	await process_frame
	quit(0 if passed else 1)

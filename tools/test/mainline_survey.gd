extends SceneTree
## Broad production-room survey. Mock entry is explicit and never acceptance.
const Host := preload("res://tools/testing/TestStoryHost.gd")
const Scenario := preload("res://scenes/components/testing/ScenarioLoader.gd")
const Source := preload("res://mcp/CaptureSource.gd")
const Monitor := preload("res://scenes/components/testing/RuntimeMonitor.gd")
const Text := preload("res://scenes/components/testing/VisibleText.gd")
var output := ""
var game: Control
var monitor: Control
var tasks: Array[int] = []
var records: Array = []
var current_case := ""

func progress(phase: String, action := "", status := "running", reason := "") -> void:
	var value := {"case_id":current_case, "phase":phase, "action":action, "status":status,
		"reason":reason, "updated_at":Time.get_datetime_string_from_system(false,true),
		"process_id":OS.get_process_id(), "max_fps":Engine.max_fps}
	if is_instance_valid(game) and game.eng != null and is_instance_valid(game.det): value["state"] = state()
	write_json(output + "/progress.json", value)
	if not current_case.is_empty(): write_json(output + "/" + current_case + "/progress.json", value)

func _initialize() -> void:
	call_deferred("run")

func arg(key: String, fallback := "") -> String:
	for raw in OS.get_cmdline_user_args():
		if raw.begins_with(key + "="): return raw.trim_prefix(key + "=")
	return fallback

func write_json(path: String, value: Variant) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(value, "  "))
	file.close()

func wait_seconds(seconds: float) -> void:
	var until := Time.get_ticks_msec() + int(seconds * 1000)
	while Time.get_ticks_msec() < until: await process_frame

func capture(case_id: String, phase: String) -> Dictionary:
	progress("capture", phase)
	await process_frame
	# Overlapping Windows test windows may stop drawing automatically. Request
	# a real rendered frame explicitly, as the production UI capture test does.
	game.room_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	RenderingServer.force_draw(false)
	RenderingServer.force_draw(false)
	var path := output + "/" + case_id + "/" + phase + ".png"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var image := root.get_texture().get_image()
	var entries: Array = []
	Text.collect(game, root, entries)
	var metadata := {"source_identity":Source.identity(self), "capture_kind":"mainline-development-survey", "acceptance_eligible":false,
		"captured_local":Time.get_datetime_string_from_system(false,true),"image_path":path,
		"case_id":case_id,"phase":phase,"visible_text":entries,"engine_time_scale":Engine.time_scale}
	# Pixels and metadata are detached on the main thread; PNG encoding runs here.
	tasks.append(WorkerThreadPool.add_task(func():
		var error := image.save_png(path)
		metadata["write_error"] = error
		metadata["image_sha256"] = FileAccess.get_sha256(path)
		write_json(path + ".json", metadata)))
	return {"path":path,"caption":case_id + " · " + phase,"room":str(game.eng.s.room),"phase":phase,"visible_text":entries}

func state() -> Dictionary:
	return {"room":game.eng.s.room,"beat":game.eng.s.current_beat,"cursor":game.eng.s.beat_cursor,
		"hold":game.eng.s.hold,"pending_deduction":game.eng.s.pending_deduction,"pending_choice":game.eng.s.pending_choice,
		"pending_conflict":game.eng.s.pending_conflict,"evidence":game.eng.s.evidence.keys(),"knowledge":game.eng.s.knowledge.keys(),
		"chapter_complete":game.eng.s.chapter_complete,"det_pos":str(game.det_pos),"pose":game.det.pose,
		"fade_alpha":game.fade_rect.modulate.a,"fade_visible":game.fade_rect.visible,"viewport_size":str(game.room_vp.size),
		"chrome_visible":game.top_bar.is_visible_in_tree() or game.left_card.is_visible_in_tree(),"modal_visible":game.modal.visible}

func waiting_reason() -> String:
	if is_instance_valid(game.interactions.active): return "Interaction is waiting for a sampling/alignment gesture or close"
	if game.subtitle.visible or not game._sub_queue.is_empty(): return "Dialogue is waiting for continuation"
	if not game.eng.s.pending_deduction.is_empty(): return "Deduction is waiting for an answer"
	if game.eng.s.pending_conflict != "": return "Confrontation is waiting for an answer"
	if not game.eng.s.pending_choice.is_empty(): return "Choice is waiting for a selection"
	if not game.det_path.is_empty(): return "Walking path did not finish before the action deadline"
	return "Interaction did not start or complete before the action deadline"

func exercise_closeup() -> void:
	var active = game.interactions.active
	if not is_instance_valid(active) or not active._ready_for_input: return
	# Exercise the existing production prop gesture handlers in this isolated fixture.
	if active.kind == "sleeve": active.prop.align_hand(Vector2(0.25, 0))
	elif active.kind in ["drag", "water", "cloth", "boots"]: active.prop.sweep(200.0, Vector2.ZERO)
	if active._has_result: active.close()

func run_case(config: Dictionary) -> void:
	var id: String = config.id
	current_case = id
	progress("fixture_validation")
	var loader := Scenario.new()
	if not loader.validate(config.fixture):
		progress("fixture_validation", "", "failed", loader.error)
		push_error(loader.error); return
	game = Host.new()
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game.fixture = loader
	game.fixture_directory = output + "/" + id
	progress("scene_loading")
	root.add_child(game)
	current_scene = game
	game.checkpoints.automatic = false
	game.checkpoints.output_path = output + "/" + id + "/interrupt.json"
	if config.get("snapshot", "") != "" and not game.checkpoints.restore_file(config.snapshot):
		progress("snapshot_restore", "", "failed", game.checkpoints.error)
		push_error(game.checkpoints.error)
		return
	monitor = Monitor.new()
	game.add_child(monitor)
	monitor.visible = false
	monitor.node_id = config.segment_id
	monitor.configure(output + "/" + id + "/metrics", {"mock":true,"case_id":id,"acceptance_eligible":false}, game)
	monitor.tag_scene(id)
	await wait_seconds(1.6)
	progress("entry_capture")
	var row := {"id":id,"segment_id":config.segment_id,"fixture":config.fixture,"acceptance_eligible":false,
		"source_identity":Source.identity(self),"initial":state(),"images":[],"actions":[],"issues":[],"stalls":[],"max_fps":Engine.max_fps}
	row.images.append(await capture(id,"01-entry"))
	var checkpoint := output + "/" + id + "/entry.snapshot.json"
	row["snapshot"] = checkpoint
	row["snapshot_saved"] = game.checkpoints.save_now(checkpoint)
	if config.get("controller", "") == "kitchen_reconstruction":
		progress("reconstruction", "ded_drag")
		var started: bool = game.kitchen.begin_order_replay("ded_drag")
		var until := Time.get_ticks_msec() + 16000
		while started and is_instance_valid(game.kitchen._order_replay) and game.kitchen._order_replay._playing and Time.get_ticks_msec() < until:
			await process_frame
		var replay = game.kitchen._order_replay
		var finished: bool = started and is_instance_valid(replay) and not replay._playing
		row.actions.append({"action":"production_reconstruction", "completed":finished,"state":state()})
		row.images.append(await capture(id,"02-reconstruction"))
		if not finished:
			row.issues.append("Reconstruction did not finish within 16 seconds")
			row.stalls.append({"phase":"reconstruction","reason":row.issues[-1],"state":state()})
	elif config.get("controller", "") == "corridor":
		for wanted in ["door_r06", "npc_shen"]:
			progress("corridor_interaction", wanted)
			for i in game.gathering._items.size():
				if str(game.gathering._items[i].id) == wanted:
					game.gathering.interact(i)
					await wait_seconds(2.5)
					row.actions.append({"action":"interact","id":wanted,"state":state()})
					row.images.append(await capture(id,"02-" + wanted))
					game._sub_queue.clear(); game._sub_until = 0.0
	elif config.has("beat"):
		progress("story_beat", str(config.beat))
		game.eng.process_beats()
		await wait_seconds(0.8)
		row.actions.append({"action":"process_production_beat","id":config.beat,"state":state()})
		if str(game.eng.s.current_beat) != str(config.beat):
			row.issues.append("Expected beat " + str(config.beat) + "; reached " + str(game.eng.s.current_beat))
			row.stalls.append({"phase":"story_beat","action":config.beat,"reason":waiting_reason(),"state":state()})
		row.images.append(await capture(id,"02-beat"))
	else:
		var evidence: Array = game.data.evidence_by_room.get(str(game.eng.s.room),[]).duplicate()
		for item in evidence:
			var eid := str(item.id)
			progress("inspect", eid)
			game._inspect_walk(eid)
			var until := Time.get_ticks_msec() + 8000
			while Time.get_ticks_msec() < until and not game.eng.s.evidence.has(eid):
				await exercise_closeup()
				await process_frame
			var collected: bool = game.eng.s.evidence.has(eid)
			row.actions.append({"action":"production_inspect_walk","id":eid,"collected":collected,"state":state()})
			if not collected:
				var reason := waiting_reason()
				row.issues.append("Inspection deadline: " + eid + ". " + reason)
				row.stalls.append({"phase":"inspect","action":eid,"reason":reason,"state":state()})
			if row.images.size() == 1: row.images.append(await capture(id,"02-inspection"))
			game._sub_queue.clear(); game._sub_until = 0.0
			if is_instance_valid(game.interactions.active): game.interactions.finish(false)
			game.det_path.clear(); game.det_done = Callable()
		if evidence.is_empty():
			progress("movement", "move_right")
			var before_move: Vector2 = game.det_pos
			var saved_playing: bool = game.eng.s.playing
			game.eng.s.playing = true
			Input.action_press("move_right")
			await wait_seconds(0.7)
			Input.action_release("move_right")
			game.eng.s.playing = saved_playing
			if before_move.distance_to(game.det_pos) < 0.01:
				row.issues.append("Movement probe produced no displacement")
				row.stalls.append({"phase":"movement","reason":waiting_reason(),"state":state()})
			row.actions.append({"action":"move_right","state":state()})
			row.images.append(await capture(id,"02-movement"))
		else:
			game.eng.process_beats()
	if config.get("finish_chapter",false):
		game._sub_queue.clear(); game._sub_until = 0.0
		game.eng.s.t = 1320.0
		game.eng._complete_chapter_one()
		row.actions.append({"action":"production_chapter_completion_after_mock_time","state":state()})
	await wait_seconds(0.6)
	progress("result_capture")
	row.images.append(await capture(id,"03-result"))
	row["final"] = state()
	row["snapshot_restored"] = game.checkpoints.restore_file(checkpoint)
	row["restored"] = state()
	row["status"] = "passed" if row.issues.is_empty() and row.snapshot_restored else "blocked"
	if not row.snapshot_restored: row.issues.append("Checkpoint roundtrip restore failed")
	row["metrics"] = output + "/" + id + "/metrics/timeline.yaml"
	monitor.finish()
	for task in tasks: WorkerThreadPool.wait_for_task_completion(task)
	tasks.clear()
	write_json(output + "/" + id + "/report.json",row)
	records.append(row)
	write_json(output + "/survey.json",{"acceptance_eligible":false,"cases":records,"source_identity":Source.identity(self)})
	progress("completed", "", row.status, "; ".join(row.issues))
	print("SURVEY_CASE " + JSON.stringify({"id":id,"segment":config.segment_id,"issues":row.issues,"actions":row.actions.size()}))
	game._stop_exploration()
	game.queue_free()
	await process_frame
	await process_frame
	game = null

func run() -> void:
	Engine.max_fps = 60
	output = Source.project_output(arg("--survey-output"))
	if output.is_empty() or ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/").get_file() != "dual_ontology_world_reconstruct_2" or OS.get_process_id() <= 0:
		quit(2); return
	var configs: Array = JSON.parse_string(FileAccess.get_file_as_string(arg("--survey-plan")))
	root.size = Vector2i(1440,900)
	for config in configs: await run_case(config)
	quit()

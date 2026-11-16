extends SceneTree
## Real-time production opening, six investigations and the natural corridor handoff.
const Host := preload("res://tools/testing/TestStoryHost.gd")
const Scenario := preload("res://scenes/components/testing/ScenarioLoader.gd")
const Source := preload("res://mcp/CaptureSource.gd")
const Monitor := preload("res://scenes/components/testing/RuntimeMonitor.gd")
const Text := preload("res://scenes/components/testing/VisibleText.gd")
var game: Control
var monitor: Control
var output := ""
var started := 0
var video: Array = []
var keys: Array = []
var events: Array = []
var subtitles: Array = []
var utterances: Array = []
var tasks: Array[int] = []
var phase := ""
var phase_since := 0.0
var active_sub := ""
var item_index := 0
var request_at := -100.0
var result_at := -1.0
var checkpoint_at := 0.0
var last_frame_at := -1.0
var end_at := -1.0
var key_pending := ""
var captured_states := {}
var failure := ""
const ITEMS := ["bed", "lamp", "desk", "window", "wardrobe", "wash", "door"]

func argument(key: String) -> String:
	for raw in OS.get_cmdline_user_args():
		if raw.begins_with(key + "="): return raw.trim_prefix(key + "=")
	return ""

func seconds() -> float:
	return float(Time.get_ticks_usec() - started) / 1000000.0

func write_json(path: String, value: Variant) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null: return
	file.store_string(JSON.stringify(value, "  "))
	file.close()

func state() -> Dictionary:
	var stage := "wake"
	var p := "boot"
	var line := 0
	if game.gathering != null and game.gathering.active:
		stage = "corridor"
		p = game.gathering.phase
		line = game.gathering._line
	elif game.opening != null:
		p = game.opening.phase
	return {"segment_id":stage, "phase":p, "line":line,
		"subtitle":game.subtitle.text if game.subtitle.is_visible_in_tree() else "",
		"speaker":game._speaker, "interaction":game.interactions.active.kind if is_instance_valid(game.interactions.active) else ""}

func _initialize() -> void:
	call_deferred("run")

func on_said(who: String, text: String, kind: String) -> void:
	utterances.append({"time_s":seconds(), "who":who, "text":text, "kind":kind, "segment_id":state().segment_id})

func on_interaction(event: Dictionary) -> void:
	var row := event.duplicate(true)
	row["time_s"] = seconds()
	events.append(row)
	key_pending = "interaction-" + str(item_index) + "-" + str(event.get("phase", event.get("event", "detail")))

func capture(s: Dictionary, key: String) -> void:
	await RenderingServer.frame_post_draw
	var now := seconds()
	var image := root.get_texture().get_image()
	var path := output.path_join("video/%06d.jpg" % video.size())
	var row := s.duplicate(true)
	row.merge({"path":path, "time_s":now, "index":video.size()})
	video.append(row)
	var png_path := ""
	var receipt := {}
	if key != "":
		png_path = output.path_join("keyframes/%03d.png" % (keys.size() + 1))
		var texts: Array = []
		Text.collect(game, root, texts)
		receipt = s.duplicate(true)
		receipt.merge({"path":png_path, "time_s":now, "key":key, "source_identity":Source.identity(self),
			"acceptance_eligible":false, "capture_kind":"production-opening-complete-development",
			"visible_text":texts, "captured_local":Time.get_datetime_string_from_system(false,true), "engine_time_scale":Engine.time_scale})
		keys.append(receipt)
	tasks.append(WorkerThreadPool.add_task(func():
		if png_path != "":
			receipt["write_error"] = image.save_png(png_path)
			receipt["image_sha256"] = FileAccess.get_sha256(png_path)
			write_json(png_path + ".json", receipt)
		image.resize(1152,720,Image.INTERPOLATE_BILINEAR)
		row["write_error"] = image.save_jpg(path,0.88)))
	last_frame_at = now
	for index in range(tasks.size()-1,-1,-1):
		if WorkerThreadPool.is_task_completed(tasks[index]):
			WorkerThreadPool.wait_for_task_completion(tasks[index])
			tasks.remove_at(index)

func drive(now: float) -> void:
	if game.gathering != null and game.gathering.active:
		if game.gathering.phase == "free" and end_at < 0: end_at = now + 4.0
		return
	if game.opening == null or game.opening.phase != "free": return
	if is_instance_valid(game.interactions.active):
		var closeup = game.interactions.active
		if closeup._has_result and not closeup._closing:
			if result_at < 0: result_at = now
			if now - result_at >= 2.0: closeup.close()
		return
	result_at = -1.0
	if game.subtitle.visible or not game._sub_queue.is_empty() or game.opening._busy_item >= 0 or not game.det_path.is_empty(): return
	if item_index >= ITEMS.size() or now-request_at < 1.0 or game.opening._free_t < 3.0: return
	var wanted: String = ITEMS[item_index]
	for index in game.opening._items.size():
		var item: Dictionary = game.opening._items[index]
		if str(item.id) != wanted: continue
		if item.seen:
			events.append({"event":"investigation_completed", "kind":wanted, "time_s":now})
			item_index += 1
			return
		request_at = now
		events.append({"event":"interaction_requested", "kind":wanted, "time_s":now})
		game.opening.interact(index)
		return

func run() -> void:
	output = Source.project_output(argument("--output"))
	if output.is_empty() or ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/").get_file() != "dual_ontology_world_reconstruct_2" or OS.get_process_id() <= 0:
		quit(2); return
	DirAccess.make_dir_recursive_absolute(output.path_join("video"))
	DirAccess.make_dir_recursive_absolute(output.path_join("keyframes"))
	root.size = Vector2i(1440,900)
	started = Time.get_ticks_usec()
	game = Host.new()
	game.fixture = Scenario.new()
	if not game.fixture.validate({"schema_version":1,"id":"complete-opening","mode":"story","entry":"wake","room":"R05","time":{"day":1,"hour":7,"minute":0}}):
		quit(2); return
	game.fixture_directory = output
	root.add_child(game)
	game.skip_subtitles = false
	game.checkpoints.output_path = output.path_join("latest.snapshot.json")
	game.checkpoints.automatic = true
	game.eng.said.connect(on_said)
	game.interactions.event_recorded.connect(on_interaction)
	monitor = Monitor.new()
	game.add_child(monitor)
	monitor.configure(output.path_join("monitor"), {"purpose":"complete opening coverage with original subtitles; capture overhead included", "acceptance_eligible":false}, game)
	monitor.visible = false
	while seconds() < 300.0:
		await process_frame
		var now := seconds()
		var s := state()
		var phase_key: String = s.segment_id + ":" + s.phase
		if phase_key != phase:
			phase = phase_key
			phase_since = now
			events.append({"event":"phase_enter", "state":phase,"time_s":now})
			key_pending = phase
		if s.subtitle != active_sub:
			if active_sub != "" and not subtitles.is_empty(): subtitles[-1]["end_s"] = now
			active_sub = s.subtitle
			if active_sub != "":
				subtitles.append({"text":active_sub,"speaker":s.speaker,"start_s":now,"segment_id":s.segment_id})
				key_pending = "dialogue-" + str(subtitles.size())
		var motion_key := phase + "-" + str(int((now-phase_since)/0.9))
		if s.phase in ["lie","sit","look","getup","approach","join"] and not captured_states.has(motion_key):
			captured_states[motion_key] = true
			key_pending = motion_key
		monitor.node_id = phase
		monitor.tag_scene("corridor" if s.segment_id == "corridor" else "R05")
		drive(now)
		if now-checkpoint_at >= 10.0:
			game.checkpoints.save_now(output.path_join("checkpoint-%03d.snapshot.json" % int(now)))
			checkpoint_at = now
		if now-last_frame_at >= 1.0/12.0 or key_pending != "":
			var key := key_pending
			key_pending = ""
			await capture(s,key)
		if end_at > 0 and now >= end_at: break
	if end_at < 0: failure = "Production flow did not reach corridor free exploration within 300 seconds"
	if not subtitles.is_empty() and not subtitles[-1].has("end_s"): subtitles[-1]["end_s"] = seconds()
	game.checkpoints.save_now(output.path_join("end.snapshot.json"))
	monitor.finish()
	for task in tasks: WorkerThreadPool.wait_for_task_completion(task)
	write_json(output.path_join("sequence.json"), {"source_identity":Source.identity(self),"acceptance_eligible":false,
		"duration_s":seconds(),"audio_sample_rate":AudioServer.get_mix_rate(),"capture_fps_target":12,
		"skip_subtitles":game.skip_subtitles,"engine_time_scale":Engine.time_scale,
		"failure":failure,"events":events,"subtitles":subtitles,"utterances":utterances,"frames":keys,"video_frames":video})
	print("COMPLETE_OPENING frames=%s keys=%s subtitles=%s failure=%s" % [video.size(),keys.size(),subtitles.size(),failure])
	quit(0 if failure == "" else 1)

extends SceneTree
## Rendered development probe: restore a recorded production fixture, then wait
## for external window-system input. This script never calls a click, route,
## interaction handler, sample method or evidence setter. X11 automation is
## reported separately by its runner and is not an independent blind test.
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Source := preload("res://mcp/CaptureSource.gd")
var game: Control
var target_index := -1
var events: Array = []
var gui_events: Array = []
var captures: Array = []
var capture_tasks: Array[int] = []
var output_dir := ""

func _initialize() -> void:
	_run.call_deferred()

func _arg(key: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(key + "="): return argument.trim_prefix(key + "=")
	return ""

func _point(p: Vector2) -> Array:
	return [p.x, p.y]

func _signal_event(event: Dictionary) -> void:
	events.append(event.duplicate(true))
	print("PROBE_EVENT " + JSON.stringify(event))

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button: InputEventMouseButton = event
		if button.pressed:
			var record := {"button":button.button_index, "local_position":_point(button.position),
				"device":button.device, "picked_index":game.kitchen._pick(button.position),
				"busy_item_after_handler":game.kitchen._busy_item, "time_usec":Time.get_ticks_usec()}
			gui_events.append(record)
			print("PROBE_GUI_INPUT " + JSON.stringify(record))

func _screen_point(control: Control, local: Vector2) -> Vector2:
	return control.get_global_transform_with_canvas() * local

func _view() -> Dictionary:
	var marker: Node3D = game.kitchen._items[target_index].marker
	var local: Vector2 = game.cam.unproject_position(marker.global_position)
	var viewport_size := Vector2(game.room_vp.size)
	var container_point: Vector2 = local * game.room_container.size / viewport_size if viewport_size.x > 0.0 and viewport_size.y > 0.0 else Vector2.INF
	var window_point := _screen_point(game.room_container, container_point)
	var window_size := Vector2(root.size)
	var visible: bool = not game.cam.is_position_behind(marker.global_position) and game.room_container.get_rect().size.x > 0.0 \
		and window_point.x >= 4.0 and window_point.y >= 4.0 and window_point.x < window_size.x - 4.0 and window_point.y < window_size.y - 4.0
	return {"marker_local":_point(local), "window_point":_point(window_point), "window_size":_point(window_size),
		"viewport_size":_point(viewport_size), "container_size":_point(game.room_container.size),
		"marker_behind_camera":game.cam.is_position_behind(marker.global_position), "in_window":visible,
		"pick_at_projection":game.kitchen._pick(local), "target_index":target_index,
		"distance_to_target":game.det_pos.distance_to(Vector2(game.kitchen._items[target_index].pos.x, game.kitchen._items[target_index].pos.z))}

# Only immutable image data and metadata cross this worker boundary. Pixel
# readback occurs on the render thread; PNG compression and disk I/O do not.
static func _encode_png(image: Image, path: String, meta: Dictionary) -> void:
	var error := image.save_png(path)
	meta["encoding_error"] = error
	if error == OK: meta["image_sha256"] = FileAccess.get_sha256(path)
	var file := FileAccess.open(path + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(meta, "  "))
		file.close()

func _capture(label: String) -> void:
	if DisplayServer.get_name() == "headless": return
	await RenderingServer.frame_post_draw
	var image: Image = root.get_texture().get_image()
	if image == null or image.is_empty(): return
	var path := output_dir.path_join(label + ".png")
	var metadata := {"source_identity":Source.identity(self, "res://scenes/dual_world/DualWorldMain.tscn"),
		"capture_kind":"development-x11-automated-input", "snapshot_path":_arg("--dv-snapshot"),
		"snapshot_sha256":FileAccess.get_sha256(_arg("--dv-snapshot")), "image_path":path,
		"engine_time_scale":Engine.time_scale, "png_encoding":"WorkerThreadPool",
		"acceptance_eligible":false, "acceptance_scored":false}
	captures.append({"stage":label, "path":path})
	capture_tasks.append(WorkerThreadPool.add_task(func(): _encode_png(image, path, metadata)))

func _finish(status: String, started: int, travel: float) -> void:
	for task: int in capture_tasks: WorkerThreadPool.wait_for_task_completion(task)
	var images_ok := true
	for image: Dictionary in captures:
		if not FileAccess.file_exists(image.path) or not FileAccess.file_exists(image.path + ".json"): images_ok = false
	var report := {"format":"kitchen-x11-input-probe-v1", "status":status,
		"source_identity":Source.identity(self, "res://scenes/dual_world/DualWorldMain.tscn"),
		"snapshot":Source.project_output(_arg("--dv-snapshot")), "snapshot_sha256":FileAccess.get_sha256(_arg("--dv-snapshot")),
		"input_method":"external_window_system_events; driver must provide its own receipt",
		"target":"e_b_seal", "gui_mouse_events":gui_events, "interaction_events":events,
		"evidence_recorded":game.eng.s.evidence.has("e_b_seal"), "detective_position":_point(game.det_pos),
		"walked_distance":travel, "remaining_path_points":game.det_path.size(), "busy_item":game.kitchen._busy_item,
		"interaction_active":is_instance_valid(game.interactions.active), "elapsed_ms":Time.get_ticks_msec() - started,
		"captures":captures, "images_written":images_ok, "png_encoding":"background worker threads",
		"development_fixture":true, "acceptance_eligible":false, "acceptance_scored":false}
	var path := output_dir.path_join("result.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
		file.close()
	print("PROBE_DONE " + JSON.stringify({"status":status, "report":path, "evidence":report.evidence_recorded, "images_written":images_ok}))
	if is_instance_valid(game.interactions.active): game.interactions.cancel()
	game.queue_free()
	await process_frame
	quit(0 if status == "evidence_recorded_after_window_input" and images_ok else 1)

func _run() -> void:
	var snapshot := _arg("--dv-snapshot")
	output_dir = Source.project_output(_arg("--dv-probe-output"))
	if snapshot.is_empty() or Source.project_output(snapshot).is_empty() or output_dir.is_empty() or DisplayServer.get_name() == "headless":
		printerr("Rendered host, project-local snapshot and output directory required")
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(output_dir)
	game = Main.instantiate()
	game.show_intro = false
	root.add_child(game)
	current_scene = game
	if not is_instance_valid(game.checkpoints) or not game.checkpoints.restored:
		printerr("Snapshot restoration failed")
		quit(2)
		return
	game.checkpoints.automatic = false
	game.checkpoints.output_path = ""
	game.checkpoints.set_process(false)
	game.auto_search = false
	for frame in 3: await process_frame
	if not is_instance_valid(game.kitchen) or not game.kitchen.active or game.kitchen.phase != "free":
		printerr("Expected active kitchen-free checkpoint")
		quit(2)
		return
	for i in game.kitchen._items.size():
		if str(game.kitchen._items[i].id) == "e_b_seal": target_index = i
	if target_index < 0:
		printerr("Seal marker missing")
		quit(2)
		return
	game.room_container.gui_input.connect(_gui_input)
	game.interactions.event_recorded.connect(_signal_event)
	# Let the production follow camera settle; no camera or actor is repositioned.
	await create_timer(2.6).timeout
	var guards: bool = not game._cine and not game.modal.visible and not game.subtitle.visible and game._sub_queue.is_empty() \
		and game.kitchen._busy_item < 0 and game.det_path.is_empty() and not is_instance_valid(game.interactions.active)
	var started := Time.get_ticks_msec()
	var previous: Vector2 = game.det_pos
	var travelled := 0.0
	var walking_reported := false
	var close_reported := false
	var last_view := 0
	await _capture("01-before-input")
	print("PROBE_READY " + JSON.stringify({"pid":OS.get_process_id(), "guards_pass":guards,
		"time_scale":Engine.time_scale, "playing":game.eng.s.playing, "speed":game.eng.s.speed,
		"view":_view(), "source_identity":Source.identity(self, "res://scenes/dual_world/DualWorldMain.tscn")}))
	if not guards:
		await _finish("snapshot_input_guard_active", started, travelled)
		return
	while Time.get_ticks_msec() - started < 110000:
		await process_frame
		travelled += previous.distance_to(game.det_pos)
		previous = game.det_pos
		if not walking_reported and game.kitchen._busy_item == target_index and not game.det_path.is_empty():
			walking_reported = true
			print("PROBE_WALKING " + JSON.stringify({"path_points":game.det_path.size(), "position":_point(game.det_pos)}))
		if not walking_reported and Time.get_ticks_msec() - last_view > 1000:
			last_view = Time.get_ticks_msec()
			print("PROBE_VIEW " + JSON.stringify(_view()))
		var closeup: Control = game.interactions.active
		if is_instance_valid(closeup) and str(closeup.kind) == "seal" and closeup._has_result and not close_reported:
			close_reported = true
			await _capture("02-seal-closeup")
			var button: Control = closeup._close_button
			var point := _screen_point(button, button.size * 0.5)
			print("PROBE_READY_CLOSE " + JSON.stringify({"window_point":_point(point), "camera_id":game.cam.get_instance_id(),
				"closeup_camera_id":closeup.camera.get_instance_id(), "prop_id":closeup.prop.get_instance_id(),
				"closeup_kind":closeup.kind, "sampled":closeup._has_result}))
		if game.eng.s.evidence.has("e_b_seal") and not is_instance_valid(game.interactions.active):
			await _capture("03-evidence-recorded")
			await _finish("evidence_recorded_after_window_input", started, travelled)
			return
	await _finish("timeout_or_input_not_completed", started, travelled)

extends SceneTree
## godot --headless --path . --script res://tools/test/room_fast_check.gd -- --dv-snapshot=.runtime/checkpoints/fixtures/kitchen-free.json --dv-fast-output=.runtime/fast-check/kitchen.json
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Check := preload("res://scenes/components/testing/RoomFastCheck.gd")
const CorridorCheck := preload("res://scenes/components/testing/CorridorFastCheck.gd")
const Source := preload("res://mcp/CaptureSource.gd")
var started := Time.get_ticks_usec()
func _initialize() -> void:
	_run.call_deferred()
func _arg(name: String) -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with(name+"="): return argument.trim_prefix(name+"=")
	return ""
func _run() -> void:
	var snapshot := _arg("--dv-snapshot")
	var output := _arg("--dv-fast-output")
	if snapshot.is_empty() or output.is_empty() or Source.project_output(snapshot).is_empty() or Source.project_output(output).is_empty():
		printerr("Project-local --dv-snapshot and --dv-fast-output required")
		quit(2)
		return
	var main = Main.instantiate()
	main.show_intro = false
	root.add_child(main)
	current_scene = main
	if not is_instance_valid(main.checkpoints) or not main.checkpoints.restored:
		printerr("Snapshot restore failed: "+str(main.checkpoints.error if is_instance_valid(main.checkpoints) else "checkpoint unavailable"))
		quit(2)
		return
	main.checkpoints.automatic = false
	main.checkpoints.output_path = ""
	main.checkpoints.set_process(false)
	var restored_state := {"playing":bool(main.eng.s.playing),"speed":float(main.eng.s.speed),"time":float(main.eng.s.t),"door_crossing":not main._door_passage.is_empty(),"door_path_points":main.det_path.size(),"cinematic":bool(main._cine),"detective_pose":str(main.det.pose),"beat_cursor":int(main.eng.s.beat_cursor)}
	main.eng.s.playing = false
	main.set_process(false)
	for controller in [main.opening,main.kitchen,main.gathering]:
		if is_instance_valid(controller): controller.set_process(false)
	for player: AnimationPlayer in main.room_vp.find_children("*","AnimationPlayer",true,false): player.pause()
	main.det.set_process(false)
	for figure in main.figures.values(): figure.set_process(false)
	await process_frame
	var report: Dictionary
	if main._transit_active():
		# The rule room can already be the destination while the origin remains
		# visible. Neither is a stationary exploration fixture or a covered check.
		report = {"status":"blocked", "pass":false, "project":Source.identity(self, "res://scenes/dual_world/DualWorldMain.tscn"),
			"room":str(main._room_loaded), "engine_room":str(main.eng.s.room), "restored_state":restored_state,
			"blocking_reasons":["快照正在过门，未覆盖稳定房间的入口、全部互动与原相机射线"], "interactions":[], "errors":[]}
	elif is_instance_valid(main.gathering) and main.gathering.active:
		# The corridor has its own stage and movement; the underlying R05 room
		# grid and evidence presentations are hidden and cannot validate it.
		if main.gathering.phase != "free":
			report = {"status":"blocked", "pass":false, "project":Source.identity(self),
				"blocking_reasons":["走廊快照不处于自由探索阶段"], "interactions":[], "errors":[]}
		else:
			var corridor_checker := CorridorCheck.new()
			report = await corridor_checker.run(main, restored_state)
	elif not ((is_instance_valid(main.opening) and main.opening.active) or (is_instance_valid(main.kitchen) and main.kitchen.active)):
		# Generic rooms have not yet been adapted to this checker's target and
		# physical-ray contract; an empty loop must never count as a pass.
		report = {"status":"blocked", "pass":false, "project":Source.identity(self, "res://scenes/dual_world/DualWorldMain.tscn"),
			"room":str(main._room_loaded), "engine_room":str(main.eng.s.room), "restored_state":restored_state,
			"blocking_reasons":["普通房间的互动清单、导航及物理射线尚未覆盖"], "interactions":[], "errors":[]}
	else:
		var checker := Check.new()
		checker.restored_state = restored_state
		checker.begin(main)
		# Fixed-FPS headless frames can outrun NavigationServer's background
		# build. Bound the real elapsed wait; it still counts toward the 5 s gate.
		var wait_started := Time.get_ticks_usec()
		while Time.get_ticks_usec() - wait_started < 1500000:
			await physics_frame
			checker.navigation_wait_frames += 1
			if checker.navigation_readiness().ready: break
			OS.delay_msec(2)
		report = await checker.run()
	report["total_elapsed_ms"] = (Time.get_ticks_usec()-started)/1000.0
	report["under_5_seconds"] = report.total_elapsed_ms < 5000.0
	report["pass"] = bool(report.get("pass",false)) and report.under_5_seconds
	var absolute := Source.project_output(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file := FileAccess.open(absolute,FileAccess.WRITE)
	if file == null:
		printerr("Cannot write room fast-check report")
		quit(2)
		return
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print(JSON.stringify({"report":absolute,"pass":report.pass,"total_elapsed_ms":report.total_elapsed_ms,"interactions":report.get("interactions",[]).size(),"errors":report.get("errors",[])}))
	main.queue_free()
	await process_frame
	quit(2 if str(report.get("status", "")) == "blocked" else (0 if report.pass else 1))

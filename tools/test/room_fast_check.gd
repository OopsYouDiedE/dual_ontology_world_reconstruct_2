extends SceneTree
## godot --headless --path . --script res://tools/test/room_fast_check.gd -- --dv-snapshot=.runtime/checkpoints/fixtures/kitchen-free.json --dv-fast-output=.runtime/fast-check/kitchen.json
const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")
const Check := preload("res://scenes/components/testing/RoomFastCheck.gd")
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
	var checker := Check.new()
	checker.restored_state = restored_state
	checker.begin(main)
	for frame in 30:
		await physics_frame
		if NavigationServer3D.map_get_iteration_id(checker.nav_map) >= 2: break
	var report: Dictionary = await checker.run()
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
	quit(0 if report.pass else 1)

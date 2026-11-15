extends SceneTree
## Fast numeric regression using the production models, animation and contact solver.
const Figure := preload("res://scenes/dual_world/ProceduralFigure.gd")
const Data := preload("res://scenes/dual_world/DualData.gd")
const Contact := preload("res://scenes/components/characters/ContactPoseModifier.gd")
const PerformanceScene := preload("res://scenes/components/interaction/ReconstructionPerformance.gd")
const Source := preload("res://mcp/CaptureSource.gd")
var performance: Node
var world: Node3D
var records: Array = []
var baseline := false

func _initialize() -> void:
	_run.call_deferred()

func _arg(key: String, fallback: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(key+"="): return value.substr(key.length()+1)
	return fallback

func _run() -> void:
	Engine.max_fps = 0
	baseline = _arg("--baseline","false") == "true"
	var directory := Source.project_output(_arg("--test-output",".runtime/contact-probe/"+str(Time.get_ticks_usec())))
	if directory.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(directory)
	world = Node3D.new()
	root.add_child(world)
	performance = PerformanceScene.new()
	root.add_child(performance)
	performance._inward = Vector3.BACK
	performance._threshold = Vector3.ZERO
	var data: RefCounted = Data.get_data()
	for id in ["su","detective","shen","huo"]:
		var actor: Node3D = Figure.new()
		world.add_child(actor)
		actor.setup(data.actor_by_id[id],data.rig_spec.get("poses",{}))
		actor.set_pose("stand")
		actor.rotation.y = PI
		var body: Node3D = actor.get("_body")
		var skeleton: Skeleton3D = body.get_meta("skeleton")
		var driver := Contact.new()
		driver.character_root = actor
		skeleton.add_child(driver)
		performance.actors[id] = actor
		performance.drivers[id] = driver
	performance._place_characters()
	if baseline:
		for pair in [["su",Vector2(0.35,0.30)],["detective",Vector2(0.35,0.62)],["shen",Vector2(0.18,0.25)],["huo",Vector2(0.35,0.32)]]:
			performance.actors[pair[0]].position = Vector3(pair[1].x,0,pair[1].y)
	for frame in 8: await process_frame
	for driver in performance.drivers.values(): driver.plant_feet()
	var handle := Node3D.new()
	world.add_child(handle)
	handle.position = Vector3(0.40,0.92,0.12)
	performance.drivers.su.right_target = handle
	performance.drivers.su.reach_weight = 1.0
	await _sample("handle_reach")
	var released := Node3D.new()
	world.add_child(released)
	released.position = performance.release_wrist_position()
	if baseline: released.position = performance.actors.su.position+Vector3(-0.13,0.82,0.08)
	released.position += Vector3(0,0,0.10)
	performance.drivers.su.right_target = released
	performance.drivers.su.pelvis_offset_world = Vector3(0,-0.05,0.12)
	performance.drivers.su.torso_pitch = -0.16 if baseline else 0.24
	performance.drivers.detective.right_target = performance._slot("su")
	performance.drivers.detective.reach_weight = 1.0
	await _sample("pull_contact")
	var cloth := Node3D.new()
	world.add_child(cloth)
	cloth.position = Vector3(0.08,0.17,0.15)
	performance.drivers.shen.right_target = cloth
	performance.drivers.shen.pelvis_offset_world = -Vector3.UP*(0.28 if baseline else PerformanceScene.SHEN_CROUCH_DROP)
	performance.drivers.shen.torso_pitch = 0.55 if baseline else PerformanceScene.SHEN_CROUCH_PITCH
	performance.drivers.shen.reach_weight = 1.0
	await _sample("cloth_contact")
	performance.drivers.huo.right_target = handle
	performance.drivers.huo.reach_weight = 1.0
	await _sample("ratchet_reach")
	var maximum_contact := 0.0
	var maximum_foot := 0.0
	var cloth_error := 0.0
	for record in records:
		for error in record.measurement.contact_error_m.values(): maximum_contact = maxf(maximum_contact,float(error))
		for error in record.measurement.foot_anchor_error_m.values(): maximum_foot = maxf(maximum_foot,float(error))
		if record.shot == "cloth_contact": cloth_error = maxf(cloth_error,float(record.measurement.contact_error_m.shen))
	var numeric_ok := cloth_error>0.05 if baseline else maximum_contact<0.005 and maximum_foot<0.001
	var result := {"baseline":baseline,"source_identity":Source.identity(self),"measurement_context":"headless_numeric_development","acceptance_scored":false,"fixed_fps":_arg("--fixed-step-label","60"),"records":records,"source_sha256":{},"maximum_contact_m":maximum_contact,"maximum_foot_anchor_error_m":maximum_foot,"cloth_contact_error_m":cloth_error,"numeric_regression_ok":numeric_ok,"expected_baseline_error_reproduced":baseline and cloth_error>0.05}
	for path in ["res://scenes/components/interaction/ReconstructionPerformance.gd","res://scenes/components/characters/ContactPoseModifier.gd","res://scenes/components/characters/ImportedCharacter.gd"]:
		result.source_sha256[path] = FileAccess.get_sha256(path)
	var file := FileAccess.open(directory+"/contact-probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("Contact probe completed: ",directory)
	performance.queue_free()
	world.queue_free()
	await process_frame
	quit(0 if numeric_ok else 1)

func _sample(shot: String) -> void:
	for frame in 40:
		await process_frame
		if frame in [9,19,39]: records.append({"shot":shot,"frame":frame,"measurement":performance.test_snapshot()})

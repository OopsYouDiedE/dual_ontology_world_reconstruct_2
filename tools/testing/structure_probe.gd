extends SceneTree
## CPU checks for every declared fixture and building combination.
const Scenario := preload("res://scenes/components/testing/ScenarioLoader.gd")
const EngineState := preload("res://scenes/dual_world/DualEngine.gd")
const Matrix := preload("res://tools/testing/BuildingMatrix.gd")
const Source := preload("res://mcp/CaptureSource.gd")
var records: Array = []
var failures: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _arg(key: String, fallback: String) -> String:
	for value in OS.get_cmdline_user_args():
		if value.begins_with(key+"="): return value.substr(key.length()+1)
	return fallback

func _run() -> void:
	Engine.max_fps = 0
	var directory := Source.project_output(_arg("--test-output",".runtime/structure-probe/"+str(Time.get_ticks_usec())))
	if directory.is_empty(): quit(2); return
	DirAccess.make_dir_recursive_absolute(directory)
	var probe := _arg("--probe","fixtures")
	if probe == "fixtures": _fixtures()
	elif probe == "building": await _building()
	else: failures.append("Unknown probe: "+probe)
	var result := {"probe":probe,"source_identity":Source.identity(self),"measurement_context":"headless_structural_development","acceptance_scored":false,"records":records,"failures":failures}
	var file := FileAccess.open(directory+"/structure-probe.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(result,"  "))
	file.close()
	print("Structure probe: ",probe," records=",records.size()," failures=",failures.size())
	quit(0 if failures.is_empty() else 1)

func _fixtures() -> void:
	var folder := "res://assets/data/test_scenarios/"
	var names := DirAccess.get_files_at(folder)
	names.sort()
	for filename in names:
		if filename.get_extension() != "yaml": continue
		var loader := Scenario.new()
		var valid := loader.read(folder+filename)
		var state: Dictionary = {}
		if valid: state = loader.state_for(EngineState.new())
		if not valid or state.is_empty(): failures.append(filename+": "+loader.error)
		records.append({"path":folder+filename,"sha256":FileAccess.get_sha256(folder+filename),"valid":valid and not state.is_empty(),"mode":loader.configuration.get("mode",""),"room":state.get("room",""),"error":loader.error})

func _building() -> void:
	for state in Matrix.cases():
		var group := Node3D.new()
		root.add_child(group)
		var components := Matrix.build(group,state)
		await process_frame
		var meshes := group.find_children("*","MeshInstance3D",true,false)
		var geometry_errors: Array = []
		for value in meshes:
			var mesh := value as MeshInstance3D
			if mesh.mesh == null: geometry_errors.append(str(mesh.get_path())+": missing mesh"); continue
			var bounds := mesh.get_aabb()
			if not bounds.position.is_finite() or not bounds.size.is_finite() or bounds.size.length_squared() <= 0:
				geometry_errors.append(str(mesh.get_path())+": invalid bounds")
		if components.size() != 6 or meshes.is_empty() or not geometry_errors.is_empty(): failures.append({"case":state.id,"geometry_errors":geometry_errors,"components":components.size(),"meshes":meshes.size()})
		records.append({"case":state,"components":components.size(),"meshes":meshes.size(),"geometry_errors":geometry_errors})
		group.queue_free()
		await process_frame

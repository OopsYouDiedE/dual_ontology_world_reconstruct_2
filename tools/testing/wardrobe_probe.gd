extends SceneTree

const PROP := preload("res://scenes/components/interaction/InteractiveProp3D.gd")
const Source := preload("res://mcp/CaptureSource.gd")

func _initialize() -> void:
	print("wardrobe_probe_initialized")
	_probe.call_deferred()

func _probe() -> void:
	Engine.max_fps = 0
	var wardrobe := PROP.new()
	wardrobe.kind = "wardrobe"
	root.add_child(wardrobe)
	var closed_center := wardrobe.pivot.to_global(Vector3(0.68, 0.0, 0))
	var hinge := wardrobe.pivot.global_position
	for angle in [0.0,-30.0,-60.0,-105.0,-145.0]:
		wardrobe.pivot.rotation.y = deg_to_rad(angle)
		assert(wardrobe.pivot.to_global(Vector3.ZERO).distance_to(hinge)<0.000001,"door hinge moved during opening")
	wardrobe.pivot.rotation.y = deg_to_rad(float(wardrobe.get_meta("door_open_degrees")))
	var open_center := wardrobe.pivot.to_global(Vector3(0.68, 0.0, 0))
	var fill := wardrobe.get_node_or_null("InteriorFill") as OmniLight3D
	assert(is_instance_valid(fill), "wardrobe interior fill light is missing")
	assert(is_equal_approx(closed_center.z, 0.42), "closed door is no longer flush with the cabinet front")
	assert(open_center.x < -1.15, "opened door does not clear the cabinet opening laterally")
	assert(fill.light_energy >= 1.0 and fill.omni_range >= 2.0, "interior fill is too weak for the cabinet depth")
	var result := {
		"closed_center": [closed_center.x, closed_center.y, closed_center.z],
		"open_center": [open_center.x, open_center.y, open_center.z],
		"fill_energy": fill.light_energy,
		"fill_range": fill.omni_range,
		"status": "ok","hinge_fixed":true,"source_identity":Source.identity(self),"acceptance_scored":false
	}
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--test-output="):
			var directory := Source.project_output(argument.trim_prefix("--test-output="))
			if directory.is_empty(): quit(2); return
			DirAccess.make_dir_recursive_absolute(directory)
			var file := FileAccess.open(directory+"/wardrobe-probe.json",FileAccess.WRITE)
			file.store_string(JSON.stringify(result,"  "))
			file.close()
	print(JSON.stringify(result))
	wardrobe.queue_free()
	quit(0)

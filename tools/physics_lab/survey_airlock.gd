extends SceneTree
## Raster counterfactuals: owned Forward+ process, frozen geometry, one change per pose.
const Scene := preload("res://scenes/physics_lab/airlock/Airlock.tscn")
const Room := preload("res://scenes/physics_lab/airlock/Room.gd")
var game: Node3D
var output := ".runtime/physics-lab/l03/local-percepts/acceptance/optics"
var rows: Array[Dictionary] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		printerr("This survey requires the real Forward+ viewport.")
		quit(2)
		return
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--survey-out="): output = arg.trim_prefix("--survey-out=")
	if not output.is_absolute_path(): output = ProjectSettings.globalize_path("res://"+output)
	if DirAccess.make_dir_recursive_absolute(output) != OK:
		quit(2)
		return
	game = Scene.instantiate()
	root.add_child(game)
	game.set_physics_process(false)
	var beam: SpotLight3D = game.room.spans[1].lamp
	game.room.paint(1,true,0)
	var old_eye := Vector3(6.297585,1.600834,-2.628127)
	var old_axis := (Vector3(3.55,-.245,-2.977)-old_eye).normalized()
	for delta in [-1,0,1]:
		await _shot("01-historical-yaw-%+d" % delta, old_eye, old_axis.rotated(Vector3.UP,deg_to_rad(delta)))
	var far_eye := Room.FAR_WATCH+Vector3.UP*1.60
	var facing := (Room.B_AIM-far_eye).normalized()
	await _shot("02-spotlight-on",far_eye,facing)
	beam.hide()
	game.room.paint(1,true,0,0,false)
	await _shot("03-spotlight-off",far_eye,facing)
	beam.show()
	game.room.paint(1,true,0)
	game.hale.position = Room.B_AIM.lerp(beam.position,.36)-Vector3.UP*.86
	await _shot("04-actor-shadow",far_eye,facing)
	game.hale.position = Room.HALE_HOME
	var entrance := Vector3(.72,1.60,.70)
	var through := (Room.B_AIM-entrance).normalized()
	await _shot("05-baffle-in-place",entrance,through)
	for part in game.room.root.get_children():
		if part is StaticBody3D and part.get_meta("surface", "") in ["blind_wall","blind_pier"]:
			part.hide()
			part.collision_layer = 0
	await _shot("06-baffle-lifted",entrance,through)
	var file := FileAccess.open(output.path_join("survey.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"  "))
	var passed: bool = rows[0].witness[1] and rows[1].witness[1] and rows[2].witness[1] and rows[3].focus_lit
	passed = passed and not rows[4].witness[1] and not rows[4].focus_lit and not rows[5].focus_lit
	passed = passed and not rows[6].witness[1] and rows[7].witness[1]
	game.queue_free()
	await process_frame
	print("Optical raster survey: %d real frames; passed=%s" % [rows.size(),passed])
	quit(0 if passed else 1)


func _shot(id: String, eye: Vector3, forward: Vector3) -> void:
	game.lead.position = eye-Vector3.UP*1.60
	game.yaw = atan2(-forward.x,-forward.z)
	game.pitch = asin(forward.y)
	game._camera_rotation()
	await physics_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var filename := id+".png"
	var image := root.get_texture().get_image()
	if image.save_png(output.path_join(filename)) != OK:
		printerr("Couldn't save "+filename)
		quit(2)
	var observed: Array = game._observe(eye,forward,game.lead)
	var beam: SpotLight3D = game.room.spans[1].lamp
	rows.append({"frame":filename,"eye":eye,"forward":forward,"witness":observed,
		"focus_lit":game._lit(beam,Room.B_AIM),"renderer":"forward_plus"})

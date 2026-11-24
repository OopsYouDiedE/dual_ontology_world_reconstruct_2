extends SceneTree
## Lighting-only arcade alternatives in the actual Expedition viewport.

func _initialize() -> void:
	review.call_deferred()

func review() -> void:
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		push_error("A real Forward+ viewport is required")
		quit(2)
		return
	seed(31)
	var level = load("res://scenes/expedition_01/Expedition.tscn").instantiate()
	root.add_child(level)
	level.set_physics_process(false)
	level.set_process_input(false)
	level.set_process_unhandled_input(false)
	for n in level.find_children("*", "CanvasLayer", true, false):
		n.hide()
	level.hale.hide()
	level.walker.global_position = Vector3(1.7, 0, 0)
	level.walker.rotation.y = -PI/2
	level.eye.rotation = Vector3.ZERO
	level.eye.fov = 66.
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	print("Arcade camera: ", level.eye.global_transform, "; Forward+ / ", RenderingServer.get_video_adapter_name())
	var lights := Node3D.new()
	level.add_child(lights)
	var out := OS.get_cmdline_user_args()[0]
	for x: float in [5.2, 11.2, 17.2, 23.2, 29.2]:
		omni(lights, Vector3(x, 1.78, 1.57), Color("ffd29b"), 2.25, 3.35)
	if not await capture(out.path_join("arcade-side.png")):
		quit(3)
		return
	for n in lights.get_children():
		lights.remove_child(n)
		n.queue_free()
	for z: float in [-1.26, 1.26]:
		omni(lights, Vector3(35.14, 2.18, z), Color("fff0cd"), 2.85, 3.1)
	omni(lights, Vector3(35.15, 3.93, 0), Color("fff0cd"), 3.8, 3.4)
	var spot := SpotLight3D.new()
	lights.add_child(spot)
	spot.position = Vector3(33.1, 2.6, 0)
	spot.look_at(Vector3(36, 2.65, 0))
	spot.spot_range = 4.9
	spot.spot_angle = 42.
	spot.light_color = Color("fff5df")
	spot.light_energy = 2.5
	if not await capture(out.path_join("arcade-gate.png")):
		quit(3)
		return
	quit()

func omni(parent: Node3D, pos: Vector3, color: Color, energy: float, reach: float) -> void:
	var light := OmniLight3D.new()
	parent.add_child(light)
	light.position = pos
	light.light_color = color
	light.light_energy = energy
	light.omni_range = reach
	light.omni_attenuation = 1.5
	light.shadow_enabled = true
	light.shadow_bias = .04

func capture(path: String) -> bool:
	for i in 84:
		await RenderingServer.frame_post_draw
	return root.get_texture().get_image().save_png(path) == OK

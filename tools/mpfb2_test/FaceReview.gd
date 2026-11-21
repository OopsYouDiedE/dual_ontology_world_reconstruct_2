extends SceneTree
## Check that Godot exposes the MPFB face pack as usable blend shapes.

const LABELS := ["NEUTRAL", "JAW OPEN", "VISEME AA"]
const EXPECTED_SHAPES := 67


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	var packed := load("res://character_face.glb") as PackedScene
	if packed == null:
		fail("GLB failed to import")
		return
	for i in LABELS.size():
		var actor := packed.instantiate() as Node3D
		root.add_child(actor)
		actor.position.x = (i - 1) * 0.43
		actor.rotation.y = 0.22
		var body: MeshInstance3D = null
		for candidate in actor.find_children("*", "MeshInstance3D", true, false):
			if candidate.find_blend_shape_by_name(&"jawOpen") >= 0:
				body = candidate
				break
		if body == null or body.get_blend_shape_count() != EXPECTED_SHAPES:
			fail("Body or 67 face shapes missing")
			return
		if i > 0:
			var name_ := &"jawOpen" if i == 1 else &"viseme_aa"
			var index := body.find_blend_shape_by_name(name_)
			if index < 0:
				fail("Missing face shape " + name_)
				return
			body.set_blend_shape_value(index, 0.85)
			if not is_equal_approx(body.get_blend_shape_value(index), 0.85):
				fail("Could not set face shape " + name_)
				return
	print("MPFB_FACE_GODOT_PASS: 67 shape keys; jawOpen and viseme_aa set")
	if "--check-only" in OS.get_cmdline_user_args():
		quit()
		return
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		fail("Expected Forward+")
		return
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("293741")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_energy = 0.56
	root.add_child(world)
	for p in [Vector3(2, 3, 4), Vector3(-3, 2, -2)]:
		var light := DirectionalLight3D.new()
		root.add_child(light)
		light.position = p
		light.look_at(Vector3.UP)
		light.light_energy = 0.95 if p.z > 0 else 0.55
	var camera := Camera3D.new()
	root.add_child(camera)
	var target := Vector3(0.0, 1.71, 0.0)
	camera.position = target + Vector3(0, 0, 4)
	camera.look_at(target)
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 0.70
	camera.make_current()
	for i in LABELS.size():
		var label := Label.new()
		label.text = LABELS[i]
		root.add_child(label)
		label.add_theme_font_size_override("font_size", 19)
		var x := camera.unproject_position(Vector3((i - 1) * 0.43, 1.71, 0)).x
		label.position = Vector2(x - label.get_minimum_size().x / 2, root.size.y - 52)
	await RenderingServer.frame_post_draw
	if root.get_texture().get_image().save_png("res://mpfb-face-preview.png") != OK:
		fail("Could not save screenshot")
		return
	quit()


func fail(message: String) -> void:
	push_error(message)
	quit(1)

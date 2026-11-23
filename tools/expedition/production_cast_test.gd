extends SceneTree
## Headless: verify the production loader. Forward+: also photograph the same surfaces.
const Cast := preload("res://scenes/rogue_crossing/Roster.gd")
const Body := preload("res://scenes/rogue_crossing/ProductionCast.gd")
func _initialize() -> void:
	run.call_deferred()

func _roster_works() -> bool:
	var uniforms := {}
	for id: String in Cast.NAMES:
		var holder := Node3D.new()
		root.add_child(holder)
		var ok: bool = Cast.attach(holder, id) and holder.get_meta("model_source", "") == Body.MODEL.resource_path
		if not ok:
			holder.queue_free()
			return false
		var player := holder.get_meta("animation_player") as AnimationPlayer
		var skeleton := holder.get_meta("skeleton") as Skeleton3D
		var model := holder.get_child(0) as Node3D
		var torso := skeleton.find_bone("thigh_l")
		ok = torso >= 0 and model.scale.is_equal_approx(Vector3.ONE * model.scale.x)
		ok = ok and player.has_animation(&"idle") and player.has_animation(&"walk") and player.has_animation(&"interact")
		if ok:
			player.play(&"walk")
			player.advance(0.0)
			var neutral := skeleton.get_bone_pose_rotation(torso)
			player.advance(0.225)
			ok = not neutral.is_equal_approx(skeleton.get_bone_pose_rotation(torso))
		var coat_found := false
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for i in mesh.mesh.get_surface_count():
				var imported := mesh.mesh.surface_get_material(i)
				if imported.resource_name != "Human.male_elegantsuit01": continue
				var mat := mesh.get_active_material(i) as ShaderMaterial
				if mat == null: continue
				uniforms[mat.get_shader_parameter("base_color")] = true
				coat_found = true
		await process_frame
		holder.queue_free()
		await process_frame
		if not ok or not coat_found: return false
	return uniforms.size() == Cast.NAMES.size()

func run() -> void:
	if not await _roster_works():
		printerr("Cast requires distinct uniform recipes and working bone animation for every resident"); quit(1); return
	var model := Node3D.new()
	root.add_child(model)
	if not Cast.attach(model, "detective") or model.get_meta("model_source", "") != "res://assets/characters/mpfb/r05_formal.glb":
		printerr("Production detective must load the approved MPFB2 R-05"); quit(1); return
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1 or (skeletons[0] as Skeleton3D).get_bone_count() != 53:
		printerr("Expected one 53-bone R-05 skeleton"); quit(1); return
	var count := 0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(i) as ShaderMaterial
			if not mat or mat.shader != Body.FINISH or not mat.get_shader_parameter("toon_on"):
				printerr("Missing shared Toon finish: ", mesh.name, " surface ", i); quit(1); return
			count += 1
	if count == 0:
		printerr("No detective mesh surfaces"); quit(1); return
	print("MPFB2 R-05: ", count, " Toon surfaces")
	if DisplayServer.get_name() != "headless":
		if RenderingServer.get_current_rendering_method() != "forward_plus":
			printerr("Character capture requires Forward+"); quit(1); return
		root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
		root.size = Vector2i(1080,720)
		var world := WorldEnvironment.new()
		world.environment = Environment.new()
		world.environment.background_mode = Environment.BG_COLOR
		world.environment.background_color = Color("8e9998")
		world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		world.environment.ambient_light_color = Color("dce6e9")
		world.environment.ambient_light_energy = 0.65
		root.add_child(world)
		var light := DirectionalLight3D.new()
		root.add_child(light)
		light.position = Vector3(-1.3,2.1,2.0)
		light.look_at(Vector3.ZERO)
		light.light_energy = 1.5
		var camera := Camera3D.new()
		camera.projection = Camera3D.PROJECTION_ORTHOGONAL
		camera.size = 2.03
		root.add_child(camera)
		var copies := [model]
		for i in 2:
			var copy := Node3D.new()
			root.add_child(copy)
			Cast.attach(copy, "detective")
			copies.append(copy)
		for i in 3:
			copies[i].position.x = (i - 1) * 0.93
			copies[i].rotation.y = [0.0, 0.67, 2.85][i]
		camera.position = Vector3(0,0.91,3.5)
		camera.look_at(Vector3(0,0.91,0)); camera.make_current()
		for i in 12: await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path := ProjectSettings.globalize_path("res://.runtime/toon-cast")
		DirAccess.make_dir_recursive_absolute(path)
		if image.get_size() != Vector2i(1080,720) or image.save_jpg(path+"/detective-toon.jpg",0.94) != OK:
			printerr("Expected a 1080x720 JPG capture"); quit(1); return
	print("PASS: one MPFB2 R-05 Toon roster (16 animated residents and captain)")
	quit(0)

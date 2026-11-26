extends SceneTree
## Headless: verify the production loader. Forward+: also photograph the same surfaces.
const Cast := preload("res://scenes/rogue_crossing/Roster.gd")
const Body := preload("res://scenes/rogue_crossing/ProductionCast.gd")
func _initialize() -> void:
	run.call_deferred()

func _find_thigh_bone(skeleton: Skeleton3D) -> int:
	for name in ["thigh_l", "mixamorig_LeftUpLeg", "mixamorig:LeftUpLeg", "LeftUpLeg"]:
		var idx := skeleton.find_bone(name)
		if idx >= 0:
			return idx
	return -1

func _roster_works() -> bool:
	var uniforms := {}
	var r05_count := 0
	for id: String in Cast.NAMES:
		var is_hero := id.to_lower() in Cast.HERO_IDS
		var expected_src: String = (Body.HERO_DIR % id.to_lower()) if is_hero else Body.MODEL.resource_path
		var holder := Node3D.new()
		root.add_child(holder)
		var ok: bool = Cast.attach(holder, id) and holder.get_meta("model_source", "") == expected_src
		if not ok:
			holder.queue_free()
			return false
		var player := holder.get_meta("animation_player") as AnimationPlayer
		var skeleton := holder.get_meta("skeleton") as Skeleton3D
		var model := holder.get_child(0) as Node3D
		var torso := _find_thigh_bone(skeleton)
		ok = torso >= 0 and model.scale.is_equal_approx(Vector3.ONE * model.scale.x)
		ok = ok and player.has_animation(&"idle") and player.has_animation(&"walk") and player.has_animation(&"interact")
		if ok:
			player.play(&"walk")
			player.advance(0.0)
			var neutral := skeleton.get_bone_pose_rotation(torso)
			player.advance(0.225)
			ok = not neutral.is_equal_approx(skeleton.get_bone_pose_rotation(torso))
		var coat_found := is_hero
		var toon_found := false
		for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
			for i in mesh.mesh.get_surface_count():
				var active := mesh.get_active_material(i) as ShaderMaterial
				if active != null and active.shader == Body.FINISH and active.get_shader_parameter("toon_on"):
					toon_found = true
				if is_hero: continue
				var imported := mesh.mesh.surface_get_material(i)
				if imported == null or imported.resource_name != "Human.male_elegantsuit01": continue
				if active == null: continue
				uniforms[active.get_shader_parameter("base_color")] = true
				coat_found = true
		if not is_hero:
			r05_count += 1
		await process_frame
		holder.queue_free()
		await process_frame
		if not ok or not coat_found or not toon_found: return false
	return uniforms.size() == r05_count

func run() -> void:
	if not await _roster_works():
		printerr("Cast requires distinct uniform recipes, Toon finish, and working bone animation for every resident and hero"); quit(1); return
	var model := Node3D.new()
	root.add_child(model)
	if not Cast.attach(model, "detective") or model.get_meta("model_source", "") != (Body.HERO_DIR % "detective"):
		printerr("Production detective must load the Tripo hero GLB"); quit(1); return
	var skeletons := model.find_children("*", "Skeleton3D", true, false)
	if skeletons.size() != 1 or (skeletons[0] as Skeleton3D).get_bone_count() != 52:
		printerr("Expected one 52-bone Mixamo skeleton on detective hero"); quit(1); return
	var count := 0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var mat := mesh.get_active_material(i) as ShaderMaterial
			if not mat or mat.shader != Body.FINISH or not mat.get_shader_parameter("toon_on"):
				printerr("Missing shared Toon finish: ", mesh.name, " surface ", i); quit(1); return
			count += 1
	if count == 0:
		printerr("No detective mesh surfaces"); quit(1); return
	print("Tripo detective: ", count, " Toon surfaces")
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
		# Also capture all 4 Tripo heroes side-by-side (detective, hale, quer, lucian)
		for c in copies: c.queue_free()
		await process_frame
		var heroes := ["detective", "hale", "quer", "lucian"]
		var xs := [-1.35, -0.45, 0.45, 1.35]
		var lineup := []
		for i in heroes.size():
			var h := Node3D.new()
			root.add_child(h)
			Cast.attach(h, heroes[i])
			h.position.x = xs[i]
			h.rotation.y = [0.15, -0.20, 0.25, -0.15][i]
			lineup.append(h)
		camera.size = 2.35
		camera.position = Vector3(0, 0.95, 3.8)
		camera.look_at(Vector3(0, 0.95, 0))
		for i in 12: await RenderingServer.frame_post_draw
		var lineup_img := root.get_texture().get_image()
		lineup_img.save_jpg(path + "/heroes-lineup.jpg", 0.94)
		for h in lineup: h.rotation.y = PI
		for i in 8: await RenderingServer.frame_post_draw
		var back_img := root.get_texture().get_image()
		back_img.save_jpg(path + "/heroes-back.jpg", 0.94)
	print("PASS: one 6.5-head MPFB2 R-05 + Tripo hero Toon roster (14 residents, 4 heroes)")
	quit(0)

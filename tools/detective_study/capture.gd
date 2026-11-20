extends SceneTree

const DIR := "res://.runtime/detective-target-study/"
const SHADERS := "res://tools/detective_study/"
const NAMES := ["detective-6p5"]
const MODES := ["a_pbr", "c_soft_selective"]
var camera: Camera3D
var stage: Node3D
var screen_ink: MeshInstance3D
var ink_material: ShaderMaterial
var white: GradientTexture2D
var key: DirectionalLight3D
var portrait: Shader

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("LOOK renderer=", RenderingServer.get_current_rendering_method(), " host=", DisplayServer.get_name())
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus":
		quit(2)
		return
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(560,768)
	root.msaa_3d = Viewport.MSAA_4X
	root.use_taa = true
	stage = Node3D.new()
	root.add_child(stage)
	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("b5aaa0")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c6c4c8")
	env.ambient_light_energy = .73
	world.environment = env
	stage.add_child(world)
	key = DirectionalLight3D.new()
	stage.add_child(key)
	key.position = Vector3(-1.18,1.60,2.20)
	key.look_at(Vector3.ZERO)
	key.light_color = Color("f6ebe6")
	key.light_energy = 1.42
	key.shadow_enabled = true
	key.light_angular_distance = 3.2
	key.directional_shadow_max_distance = 3.2
	key.shadow_bias = .032
	key.shadow_normal_bias = .12
	var fill := DirectionalLight3D.new()
	stage.add_child(fill)
	fill.position = Vector3(1,.3,-1)
	fill.look_at(Vector3.ZERO)
	fill.light_color = Color("c2cbe8")
	fill.light_energy = .34
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.near = .06
	camera.far = 12.0
	stage.add_child(camera)
	white = GradientTexture2D.new()
	white.gradient = Gradient.new()
	white.gradient.set_color(0,Color.WHITE)
	white.gradient.set_color(1,Color.WHITE)
	portrait = read_shader("portrait.gdshader")
	screen_ink = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
	screen_ink.mesh = quad
	screen_ink.custom_aabb = AABB(Vector3(-10,-10,-10),Vector3(20,20,20))
	screen_ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ink_material = ShaderMaterial.new()
	ink_material.shader = read_shader("ink.gdshader")
	screen_ink.material_override = ink_material
	stage.add_child(screen_ink)
	for id: String in NAMES:
		var doc := GLTFDocument.new()
		var state := GLTFState.new()
		var path := ProjectSettings.globalize_path(DIR+id+".glb")
		if doc.append_from_file(path,state) != OK:
			push_error("GLB load failed: " + path)
			quit(4)
			return
		var model := doc.generate_scene(state) as Node3D
		stage.add_child(model)
		# Tilt the same amount, framing the geometry against a plain background.
		model.rotate_x(0)
		var originals: Dictionary = {}
		var stylized: Dictionary = {}
		var triangles := 0
		for n in model.find_children("*", "MeshInstance3D", true, false):
			var mesh := n as MeshInstance3D
			var original: Array[BaseMaterial3D] = []
			var style: Array[ShaderMaterial] = []
			for i in range(mesh.mesh.get_surface_count()):
				var stock := mesh.get_active_material(i) as BaseMaterial3D
				original.append(stock)
				var arr := mesh.mesh.surface_get_arrays(i)
				triangles += (arr[Mesh.ARRAY_INDEX].size() if arr[Mesh.ARRAY_INDEX] else arr[Mesh.ARRAY_VERTEX].size()) / 3
				var mat := ShaderMaterial.new()
				mat.shader = portrait
				var tint := stock.albedo_color
				var role := stock.resource_name.get_slice(" |",0)
				mat.set_shader_parameter("tint",tint)
				mat.set_shader_parameter("base_map",white)
				mat.set_shader_parameter("flat_map",white)
				mat.set_shader_parameter("texture_weight",0.0)
				mat.set_shader_parameter("shadow_tint",Color(.99, .88, .86))
				mat.set_shader_parameter("face",role in ["Skin", "Sclera", "Iris", "Pupil", "Eye line", "Lips"])
				style.append(mat)
			originals[mesh] = original
			stylized[mesh] = style
		print("SUBJECT ",id," meshes=",originals.size()," triangles=",triangles)
		for view: String in ["front","profile","back","quarter","portrait"]:
			var target := Vector3(0,1.57 if view == "portrait" else .905,0)
			var theta := deg_to_rad(float({"front":0,"profile":90,"back":180,"quarter":36,"portrait":36}[view]))
			camera.size = .61 if view == "portrait" else 1.975
			camera.position = target + Vector3(sin(theta),0,cos(theta)) * 3.0
			camera.look_at(target)
			for mode: String in MODES:
				apply_mode(mode,originals,stylized)
				for i in range(12):
					await process_frame
					await RenderingServer.frame_post_draw
				var img := root.get_texture().get_image()
				var output: String = DIR + id + "_" + view + "_" + mode + ".png"
				if not img or img.get_size() != Vector2i(560,768) or img.save_png(ProjectSettings.globalize_path(output)) != OK:
					push_error("Capture failed: " + output + " got " + str(img.get_size() if img else "nil"))
					quit(3)
					return
				print("CAPTURE ", id, " ", view, " ",mode)
		var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
		assert(skeleton.get_bone_count() == 24)
		print("Skeleton bones: ",skeleton.get_bone_count())
		apply_mode("c_soft_selective", originals, stylized)
		for pose: String in ["turn", "reach", "step", "run"]:
			skeleton.reset_bone_poses()
			if pose == "turn" or pose == "reach":
				rotate_bone(skeleton,"Eye_L",Vector3.UP,8.0)
				rotate_bone(skeleton,"Eye_R",Vector3.UP,8.0)
				rotate_bone(skeleton,"Head",Vector3.RIGHT,14.0)
				rotate_bone(skeleton,"Neck",Vector3.UP,8.0)
			if pose == "reach":
				rotate_bone(skeleton,"UpperArm_R",Vector3.RIGHT,-48.0)
				rotate_bone(skeleton,"Forearm_R",Vector3.RIGHT,-44.0)
				rotate_bone(skeleton,"Chest",Vector3.UP,-8.0)
			if pose in ["step","run"]:
				var scale_angle := 1.0 if pose == "step" else 1.7
				rotate_bone(skeleton,"Thigh_L",Vector3.RIGHT,-24.0*scale_angle)
				rotate_bone(skeleton,"Thigh_R",Vector3.RIGHT,16.0*scale_angle)
				rotate_bone(skeleton,"Shin_R",Vector3.RIGHT,17.0*scale_angle)
				rotate_bone(skeleton,"UpperArm_R",Vector3.RIGHT,-15.0*scale_angle)
				rotate_bone(skeleton,"UpperArm_L",Vector3.RIGHT,12.0*scale_angle)
				rotate_bone(skeleton,"Tail_L",Vector3.RIGHT,-7.0*scale_angle)
				rotate_bone(skeleton,"Tail_R",Vector3.RIGHT,17.0*scale_angle)
			var target := Vector3(0,1.57 if pose == "turn" else .885,0)
			camera.size = .64 if pose == "turn" else 2.07
			camera.position = target + Vector3(-.82,0,.57).normalized()*3.0
			camera.look_at(target)
			for i in range(14):
				await process_frame
				await RenderingServer.frame_post_draw
			var image := root.get_texture().get_image()
			if not image or image.save_png(ProjectSettings.globalize_path(DIR+id+"_pose_"+pose+".png")) != OK:
				quit(5)
				return
			print("POSE STRESS ",pose)
		skeleton.reset_bone_poses()
		stage.remove_child(model)
		model.queue_free()
	quit()

func apply_mode(mode: String, original: Dictionary, stylized: Dictionary) -> void:
	for mesh: MeshInstance3D in original:
		for i in range(mesh.mesh.get_surface_count()):
			var mat: ShaderMaterial = stylized[mesh][i]
			mat.set_shader_parameter("hard", mode == "b_hard")
			mesh.set_surface_override_material(i, original[mesh][i] if mode == "a_pbr" else mat)
	screen_ink.visible = mode in ["b_hard", "c_soft_selective", "e_soft_fullink"]
	ink_material.set_shader_parameter("ink_mode", 2 if mode in ["b_hard", "e_soft_fullink"] else 1)

func read_shader(path: String) -> Shader:
	var shader := Shader.new()
	shader.code = FileAccess.get_file_as_string(SHADERS + path).strip_edges().trim_prefix("\ufeff")
	return shader





func rotate_bone(sk: Skeleton3D, name: String, global_axis: Vector3, angle: float) -> void:
	var i := sk.find_bone(name)
	if i == -1:
		i = sk.find_bone(name.replace("_","."))
	if i == -1:
		push_error("Missing bone: " + name)
		quit(6)
		return
	var local_axis := sk.get_bone_global_rest(i).basis.inverse()*global_axis
	sk.set_bone_pose_rotation(i, (sk.get_bone_pose_rotation(i)*Quaternion(local_axis.normalized(),deg_to_rad(angle))).normalized())

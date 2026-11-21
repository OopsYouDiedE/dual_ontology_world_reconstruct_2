extends SceneTree
## Run after importing the R-05 pilot GLBs; all captures are from the real viewport.
const TOON := preload("res://academy_toon.gdshader")
const HULL := preload("res://academy_hull.gdshader")
const SCENE_INK := preload("res://academy_scene_ink.gdshader")
const ANIM := &"MPFB_Pose_Check"
var camera: Camera3D
var backdrop: Node3D
var screen_ink: MeshInstance3D
var skin: MeshInstance3D
var rig: Skeleton3D
var player: AnimationPlayer
var actor: Node3D
var caption: Label
var active_models: Dictionary
var capture_failed := false


func _initialize() -> void:
	call_deferred("run")


func run() -> void:
	if RenderingServer.get_current_rendering_method() != "forward_plus":
		fail("This comparison requires Forward+")
		return
	build_stage()
	for name in ["r05-base", "r05-stock-normals", "r05-styled"]:
		var scene := load("res://%s.glb" % name) as PackedScene
		if scene == null:
			fail("No GLB " + name)
			return
		var obj := scene.instantiate() as Node3D
		root.add_child(obj)
		obj.hide()
		active_models[name] = obj
	if not select_model("r05-base"):
		return
	portrait(false, 0.0)
	await capture("01-base-front", "01 / BODY LOCAL FIT / STOCK FACE")
	if not select_model("r05-stock-normals"):
		return
	portrait(false, 0.0)
	set_look(false, false, false, true)
	await capture("02-styled-front", "02 / R-05 FACE TARGETS + FULL STYLE TARGET")
	portrait(true, 0.48)
	set_look(true, false, false)
	await capture("03-toon-flat", "03 / SOFT TOON / FLAT PIGMENT")
	set_look(true, true, false)
	await capture("04-toon-bake", "04 / + UV BAKED AO & CAVITY")
	if not select_model("r05-styled"):
		return
	if not verify_ink_mask():
		return
	portrait(true, 0.48)
	set_look(true, true, false)
	await capture("05-toon-normals", "05 / + SELECTIVE CHEEK NORMALS")
	set_look(true, true, true)
	await capture("06-character-ink", "06 / + CHARACTER HULL ONLY")
	screen_ink.show()
	await capture("07-scene-ink", "07 / + FULL VIEW DEPTH & NORMAL INK")
	screen_ink.hide()
	camera.size = 2.16
	aim(Vector3(0.0, 0.96, 0.0))
	actor.rotation.y = 0.18
	await capture("08-full-hull", "08 / CHARACTER INK / FULL BODY")
	screen_ink.show()
	await capture("09-full-scene", "09 / CHARACTER & ARCHITECTURE INK / FULL BODY")
	screen_ink.hide()
	var elbow := rig.find_bone(&"lowerarm_r")
	if elbow < 0:
		fail("Right elbow missing")
		return
	var neutral := rig.get_bone_pose_rotation(elbow)
	player.seek(0.75, true)
	if neutral.angle_to(rig.get_bone_pose_rotation(elbow)) < 0.4:
		fail("Animation did not rotate the right elbow")
		return
	await capture("10-full-reach", "10 / REACH TEST / GARMENT & HULL")
	player.seek(0.0, true)
	portrait(true, 0.18)
	if not apply_face(&"jawOpen", 0.65, [&"Teeth", &"Tongue"]):
		return
	await capture("11-jaw-open", "11 / JAW 0.65 / ANIMATED MOUTH ASSETS")
	if not apply_face(&"jawOpen", 0.0) or not apply_face(&"eyeBlinkLeft", 1.0) or not apply_face(&"eyeBlinkRight", 1.0):
		return
	await capture("12-blink", "12 / EYE BLINK L + R 1.00")
	if not apply_face(&"eyeBlinkLeft", 0.0) or not apply_face(&"eyeBlinkRight", 0.0):
		return
	if not apply_face(&"viseme_aa", 0.75, [&"Teeth", &"Tongue"]) or not apply_face(&"browInnerUp", 0.6, [&"Brows"]):
		return
	await capture("13-viseme-and-brow", "13 / VISEME AA 0.75 / INNER BROW 0.60")
	if capture_failed:
		quit(1)
		return
	print("ACADEMY_STYLE_GODOT_PASS 53 bones; 67 body face channels; vertex ink mask; 13 viewport captures")
	quit()


func build_stage() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("504849")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("d2c6d9")
	env.ambient_light_energy = 0.47
	var world := WorldEnvironment.new()
	world.environment = env
	root.add_child(world)
	for spec in [[Vector3(-2.2, 3.2, 3.6), 1.63, Color("fff0dc")],
			[Vector3(2.7, 2.7, -1.4), 0.60, Color("bacde1")]]:
		var light := DirectionalLight3D.new()
		root.add_child(light)
		light.position = spec[0]
		light.look_at(Vector3(0, 1.45, 0.0))
		light.light_energy = spec[1]
		light.light_color = spec[2]
	backdrop = Node3D.new()
	root.add_child(backdrop)
	box(Vector3(0,-0.12,-0.8), Vector3(10,0.24,8), Color("6c6259"))
	box(Vector3(0,1.36,-1.32), Vector3(6,2.8,0.24), Color("8b8177"))
	box(Vector3(0,0.28,-1.19), Vector3(6,0.56,0.1), Color("6b625b"))
	for x in [-1.02, -0.52, 0.52, 1.02]:
		box(Vector3(x,1.42,-1.12), Vector3(0.084,2.82,0.16), Color("9b8e7b"))
	box(Vector3(0,1.82,-1.11), Vector3(6,0.04,0.16), Color("9b8e7b"))
	box(Vector3(0,1.32,-1.11), Vector3(6,0.045,0.17), Color("766c62"))
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 30
	root.add_child(camera)
	camera.make_current()
	screen_ink = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
	screen_ink.mesh = quad
	screen_ink.extra_cull_margin = 100.0
	screen_ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var overlay := ShaderMaterial.new()
	overlay.shader = SCENE_INK
	overlay.render_priority = 100
	screen_ink.material_override = overlay
	root.add_child(screen_ink)
	screen_ink.hide()
	caption = Label.new()
	caption.position = Vector2(25,19)
	caption.add_theme_font_size_override("font_size",26)
	caption.add_theme_color_override("font_color",Color("fff3db"))
	caption.add_theme_color_override("font_shadow_color",Color("2d2630"))
	caption.add_theme_constant_override("shadow_offset_x",1)
	caption.add_theme_constant_override("shadow_offset_y",2)
	root.add_child(caption)


func box(center: Vector3, size_: Vector3, color: Color) -> void:
	var n := MeshInstance3D.new()
	var m := BoxMesh.new()
	m.size = size_
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	n.mesh = m
	n.material_override = mat
	n.position = center
	backdrop.add_child(n)


func aim(point: Vector3) -> void:
	camera.position = point + Vector3(0,0,4)
	camera.look_at(point)


func portrait(show_hair: bool, yaw: float) -> void:
	actor.rotation.y = yaw
	camera.size = 0.54
	aim(Vector3(0.0,1.568,0.0))
	for n in actor.find_children("Hair*", "MeshInstance3D", true, false):
		n.visible = show_hair


func select_model(key: String) -> bool:
	for n: Node3D in active_models.values():
		n.hide()
	actor = active_models[key] as Node3D
	actor.show()
	skin = actor.find_child("Academy_HeadBody", true, false) as MeshInstance3D
	if skin == null:
		return fail("Body node missing " + key)
	if key != "r05-base" and skin.get_blend_shape_count() != 67:
		return fail("Face shape count " + str(skin.get_blend_shape_count()))
	rig = actor.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	player = actor.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	if rig.get_bone_count() != 53 or not player.has_animation(ANIM):
		return fail("Wrong rig or animation")
	player.play(ANIM)
	player.pause()
	player.seek(0.0, true)
	return true


func verify_ink_mask() -> bool:
	var colors: PackedColorArray = skin.mesh.surface_get_arrays(0)[Mesh.ARRAY_COLOR]
	var lo := 1.0
	var hi := 0.0
	for c in colors:
		lo = minf(c.a,lo)
		hi = maxf(c.a,hi)
	if colors.is_empty() or lo >= 0.6 or hi < 0.99:
		return fail("Vertex alpha mask was lost on import")
	print("INK_ALPHA_RANGE ",lo,"..",hi)
	return true


func set_look(toon: bool, tex: bool, hull: bool, flat_pbr: bool = false) -> void:
	for n in actor.find_children("*", "MeshInstance3D", true, false):
		var node := n as MeshInstance3D
		var body := node == skin
		if not body and not (node.name.begins_with("Hair") or node.name in [&"Shirt", &"Shorts"]):
			continue
		var origin := node.mesh.surface_get_material(0) as StandardMaterial3D
		assert(origin != null)
		if not toon:
			if not flat_pbr or not body:
				node.material_override = null
			else:
				var flat := StandardMaterial3D.new()
				flat.albedo_color = Color("bc927d")
				flat.roughness = origin.roughness
				node.material_override = flat
			continue
		var mat := ShaderMaterial.new()
		mat.shader = TOON
		mat.set_shader_parameter("pigment", Color("bc927d") if body else origin.albedo_color)
		mat.set_shader_parameter("band_width", 0.10 if body else 0.08)
		mat.set_shader_parameter("use_pigment_tex", body and tex)
		if body and tex:
			assert(origin.albedo_texture != null)
			mat.set_shader_parameter("pigment_tex",origin.albedo_texture)
		if hull:
			var ink := ShaderMaterial.new()
			ink.shader = HULL
			ink.set_shader_parameter("use_vertex_alpha", body)
			ink.set_shader_parameter("width_m", 0.00135 if body else (0.00155 if node.name.begins_with("Hair") else 0.00215))
			mat.next_pass = ink
		node.material_override = mat


func apply_face(key: StringName, weight: float, required: Array[StringName] = []) -> bool:
	var changed := []
	for n in actor.find_children("*", "MeshInstance3D", true, false):
		var instance := n as MeshInstance3D
		var i := instance.find_blend_shape_by_name(key)
		if i >= 0:
			instance.set_blend_shape_value(i, weight)
			assert(is_equal_approx(instance.get_blend_shape_value(i),weight))
			changed.append(instance.name)
	if skin.name not in changed:
		return fail("Missing body face channel " + str(key))
	for name_ in required:
		if name_ not in changed:
			return fail("Missing attachment channel %s on %s (found %s)" % [key, name_, changed])
	print("FACIAL_CHANNEL ",key," ",weight," ",changed)
	return true


func capture(stem: String, label_: String) -> void:
	caption.text = label_
	await process_frame
	await RenderingServer.frame_post_draw
	var png := root.get_texture().get_image()
	if png.save_png("res://%s.png" % stem) != OK:
		push_error("Could not write " + stem)
		capture_failed = true


func fail(reason: String) -> bool:
	push_error(reason)
	quit(1)
	return false

extends SceneTree
## Hero faces in the game's own look: AcademyStage environment and ink, ProductionCast's toon finish,
## idle pose, orthographic front camera. Writes <hero>-face.png and <hero>-body.png for the landmark
## comparison against the paintings (tools/cast/fit/sheet.py --godot).
##   godot --path . --script res://tools/cast/fit/godot_faces.gd -- --heroes=detective,hale --out=res://.runtime/facefit/godot

const Stage := preload("res://scenes/components/rendering/AcademyStage.gd")
const FINISH := preload("res://scenes/components/rendering/actors/CastDielectric.gdshader")

var heroes := ["detective", "hale", "quer", "lucian"]
var out := "res://.runtime/facefit/godot"

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--heroes="): heroes = a.substr(9).split(",")
		if a.begins_with("--out="): out = a.substr(6)
	run.call_deferred()

## Same finish as ProductionCast._apply_finish (no recipe tint).
func finish(node: Node) -> void:
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null: continue
		for i in mesh.mesh.get_surface_count():
			var stock := mesh.get_active_material(i) as StandardMaterial3D
			if stock == null: continue
			var mat := ShaderMaterial.new()
			mat.shader = FINISH
			mat.set_shader_parameter("toon_on", true)
			mat.set_shader_parameter("toon_strength", 0.86)
			mat.set_shader_parameter("base_color", stock.albedo_color)
			mat.set_shader_parameter("surface_roughness", stock.roughness)
			mat.set_shader_parameter("double_sided", stock.cull_mode == BaseMaterial3D.CULL_DISABLED)
			if stock.albedo_texture: mat.set_shader_parameter("base_texture", stock.albedo_texture)
			mesh.set_surface_override_material(i, mat)

func shoot(vp: SubViewport, path: String) -> void:
	for i in 8: await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png(path)

func run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out))
	var vp := SubViewport.new()
	vp.size = Vector2i(768, 768)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	Stage.tune_viewport(vp)
	root.add_child(vp)
	var world := WorldEnvironment.new(); world.environment = Stage.environment(); vp.add_child(world)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-38, 25, 0); sun.light_energy = 1.3
	sun.shadow_enabled = true; vp.add_child(sun)
	var fill := OmniLight3D.new(); fill.position = Vector3(-1.2, 2.0, 2.2); fill.omni_range = 7
	fill.light_energy = 0.7; fill.light_color = Color("ffd7a8"); vp.add_child(fill)
	var floor := MeshInstance3D.new(); var pm := PlaneMesh.new(); pm.size = Vector2(8, 8); floor.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color("525e6a"); floor.material_override = fm
	vp.add_child(floor)
	var cam := Camera3D.new(); cam.projection = Camera3D.PROJECTION_ORTHOGONAL; vp.add_child(cam); cam.current = true
	vp.add_child(Stage.ink())
	for id in heroes:
		var body: Node3D = load("res://assets/characters/heroes/%s.glb" % id).instantiate()
		vp.add_child(body)
		finish(body)
		var anim: AnimationPlayer = body.find_children("*", "AnimationPlayer", true, false)[0]
		anim.play("idle"); anim.seek(0.0, true); anim.pause()
		await process_frame
		var skel: Skeleton3D = body.find_children("*", "Skeleton3D", true, false)[0]
		var head := -1
		for b in skel.get_bone_count():
			if skel.get_bone_name(b).ends_with("Head"): head = b
		var head_pos := (skel.global_transform * skel.get_bone_global_pose(head)).origin
		# Face: orthographic, square on the head; the hero faces +Z.
		var target := head_pos + Vector3(0, 0.075, 0)
		cam.size = 0.42
		cam.look_at_from_position(target + Vector3(0, 0, 3.0), target)
		await shoot(vp, ProjectSettings.globalize_path("%s/%s-face.png" % [out, id]))
		# Body: full height.
		vp.size = Vector2i(640, 1024)
		var h := head_pos.y + 0.35
		cam.size = h * 1.12
		cam.look_at_from_position(Vector3(0, h / 2, 4.0), Vector3(0, h / 2, 0))
		await shoot(vp, ProjectSettings.globalize_path("%s/%s-body.png" % [out, id]))
		vp.size = Vector2i(768, 768)
		body.queue_free()
		await process_frame
		print("GODOT_FACE ", id)
	quit()

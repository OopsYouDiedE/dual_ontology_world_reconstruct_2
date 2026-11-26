extends SceneTree
## Render pass for the Godot face-fit loop (tools/cast/fit/godot_loop.py drives it).
## Loads each hero's face rig (.runtime/facefit/facerig/<hero>.glb, blend shapes p<k>/n<k>) at runtime,
## puts all heroes in one world under the game's look (AcademyStage environment + ink, CastDielectric
## toon), one SubViewport and orthographic camera per hero, and for every frame of the job sets the
## blend-shape weights and head-pose orbit, then saves one PNG per hero.
##   godot --path . --script res://tools/cast/fit/godot_fitloop.gd -- --job=<abs path to job.json>
## job = {"heroes": [...], "size": 640, "out": "<abs dir>", "frames": [{"<hero>": {"w": {"p3": 0.2}, "yaw": 0, "pitch": 0}}]}

const Stage := preload("res://scenes/components/rendering/AcademyStage.gd")
const FINISH := preload("res://scenes/components/rendering/actors/CastDielectric.gdshader")
const SPACING := 3.0
const SETTLE := 4

var job: Dictionary

func _initialize() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--job="):
			job = JSON.parse_string(FileAccess.get_file_as_string(a.substr(6)))
	run.call_deferred()

func finish(node: Node) -> void:
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		for i in mesh.mesh.get_surface_count():
			var stock := mesh.get_active_material(i) as StandardMaterial3D
			if stock == null: continue
			var mat := ShaderMaterial.new()
			mat.shader = FINISH
			mat.set_shader_parameter("toon_on", true)
			mat.set_shader_parameter("toon_strength", 0.86)
			mat.set_shader_parameter("base_color", stock.albedo_color)
			mat.set_shader_parameter("surface_roughness", stock.roughness)
			mat.set_shader_parameter("double_sided", true)
			if stock.albedo_texture: mat.set_shader_parameter("base_texture", stock.albedo_texture)
			mesh.set_surface_override_material(i, mat)

func load_rig(path: String) -> Node3D:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_file(path, state)
	assert(err == OK, "cannot load %s" % path)
	return doc.generate_scene(state)

func eye_centre(rig: Node3D) -> Vector3:
	for mesh: MeshInstance3D in rig.find_children("*", "MeshInstance3D", true, false):
		if mesh.name.ends_with("eyes"):
			var box := mesh.global_transform * mesh.get_aabb()
			return box.get_center()
	return rig.global_position + Vector3(0, 1.55, 0)

func run() -> void:
	var heroes: Array = job["heroes"]
	var size := int(job.get("size", 640))
	var world := World3D.new()
	var vps := {}
	var cams := {}
	var rigs := {}
	var eyes := {}
	var first: SubViewport = null
	for id in heroes:
		var vp := SubViewport.new()
		vp.size = Vector2i(size, size)
		vp.world_3d = world
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		Stage.tune_viewport(vp)
		root.add_child(vp)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = 0.42
		vp.add_child(cam)
		cam.current = true
		vps[id] = vp
		cams[id] = cam
		if first == null: first = vp
	var env := WorldEnvironment.new(); env.environment = Stage.environment(); first.add_child(env)
	var sun := DirectionalLight3D.new(); sun.rotation_degrees = Vector3(-38, 25, 0); sun.light_energy = 1.3
	sun.shadow_enabled = true; first.add_child(sun)
	first.add_child(Stage.ink())
	for i in heroes.size():
		var id: String = heroes[i]
		var rig := load_rig(ProjectSettings.globalize_path("res://.runtime/facefit/facerig/%s.glb" % id))
		first.add_child(rig)
		rig.position = Vector3(i * SPACING, 0, 0)
		finish(rig)
		var fill := OmniLight3D.new(); fill.position = rig.position + Vector3(-1.2, 2.0, 2.2)
		fill.omni_range = 4; fill.light_energy = 0.7; fill.light_color = Color("ffd7a8"); first.add_child(fill)
		rigs[id] = rig
	await process_frame
	for id in heroes: eyes[id] = eye_centre(rigs[id])
	var out: String = job["out"]
	var frames: Array = job["frames"]
	for f in frames.size():
		var frame: Dictionary = frames[f]
		for id in heroes:
			var spec: Dictionary = frame.get(id, {})
			var w: Dictionary = spec.get("w", {})
			for mesh: MeshInstance3D in rigs[id].find_children("*", "MeshInstance3D", true, false):
				for b in mesh.get_blend_shape_count():
					var key := String(mesh.mesh.get_blend_shape_name(b))
					mesh.set_blend_shape_value(b, float(w.get(key, 0.0)))
			var pivot: Vector3 = eyes[id] + Vector3(0, -0.03, -0.08)
			var orbit := Basis(Vector3.UP, deg_to_rad(float(spec.get("yaw", 0.0)))) \
				* Basis(Vector3.RIGHT, deg_to_rad(-float(spec.get("pitch", 0.0))))
			# Orbit the camera around a pivot inside the head; the hero faces +Z.
			var target: Vector3 = eyes[id] + Vector3(0, -0.03, 0)
			var aim: Vector3 = pivot + orbit * (target - pivot)
			cams[id].look_at_from_position(aim + orbit * Vector3(0, 0, 3.0), aim)
		for s in SETTLE: await RenderingServer.frame_post_draw
		for id in heroes:
			vps[id].get_texture().get_image().save_png("%s/%s-%d.png" % [out, id, f])
	print("FITLOOP_DONE ", frames.size())
	quit()

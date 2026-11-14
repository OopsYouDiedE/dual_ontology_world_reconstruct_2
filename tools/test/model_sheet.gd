extends SceneTree
## 模型检查表：四个人物并排，指定姿态与视角，输出 PNG。
## 用法：godot --path . -s tools/test/model_sheet.gd -- pose=stand yaw=0 out=/tmp/shots/a.png
const Data := preload("res://scenes/dual_world/DualData.gd")
const Figure := preload("res://scenes/dual_world/ProceduralFigure.gd")
const ImportedFix := preload("res://scenes/components/characters/RigWeightFix.gd")

func _arg(k: String, d: String) -> String:
	for a in OS.get_cmdline_user_args():
		if str(a).begins_with(k + "="): return str(a).substr(k.length() + 1)
	return d

func _initialize() -> void:
	var pose := _arg("pose", "stand")
	var yaw := float(_arg("yaw", "0"))
	var out := _arg("out", "/tmp/shots/sheet.png")
	var ids := _arg("ids", "detective,huo,shen,su").split(",")
	var zoom := float(_arg("zoom", "1"))
	var data = Data.get_data()
	root.size = Vector2i(1280, 720)
	var world := Node3D.new()
	root.add_child(world)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("#3a342c")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("#d8cdb8")
	e.ambient_light_energy = 0.9
	env.environment = e
	world.add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, -30, 0)
	sun.light_energy = 1.1
	world.add_child(sun)
	var floor_mesh := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(12, 6)
	floor_mesh.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color("#6b5b48")
	floor_mesh.material_override = fm
	world.add_child(floor_mesh)
	var figs: Array = []
	for i in ids.size():
		var f: Node3D = Figure.new()
		f.setup(data.actor_by_id[ids[i]], data.rig_spec.get("poses", {}))
		f.position = Vector3((i - (ids.size() - 1) * 0.5) * 1.1, 0, 0)
		f.rotation.y = deg_to_rad(yaw)
		world.add_child(f)
		f.set_pose(pose)
		figs.append(f)
	var cam := Camera3D.new()
	cam.position = Vector3(0, 0.95, 4.2 / zoom)
	world.add_child(cam)
	cam.look_at(Vector3(0, 0.7, 0))
	cam.current = true
	for k in 40: await process_frame
	var t := float(_arg("t", "0.6"))
	var t0 := Time.get_ticks_msec()
	while (Time.get_ticks_msec() - t0) < t * 1000.0: await process_frame
	var img := root.get_texture().get_image()
	img.save_png(out)
	print("saved ", out, " ", img.get_size(), " fix=", ImportedFix.report.keys().size())
	for k in ImportedFix.report: print("  ", k.get_file(), ImportedFix.report[k])
	quit()

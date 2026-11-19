extends SceneTree

const BANNER := preload("res://scenes/blue_prince_lab/banner/Banner.tscn")
var failures := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var banner = BANNER.instantiate()
	banner.rotation.y = PI / 2.0
	root.add_child(banner)
	if DisplayServer.get_name() != "headless":
		_setup_preview(banner)
	var cloth: MeshInstance3D = banner.get_node("Cloth")
	var hem: int = banner.COLS * (banner.ROWS - 1) + banner.COLS / 2
	_check(cloth.mesh.surface_get_array_len(0) == banner.ROWS * banner.COLS, "procedural mesh")
	_check(banner._normals[0].dot(Vector3.BACK) > 0.9, "front normal points into room")
	await _ticks(60)
	var rest_z: float = banner._points[hem].z
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		_check(root.get_texture().get_image().save_png("res://.runtime/banner-preview.png") == OK, "save viewport preview")
	banner.set_wind(Vector3(4.0, 0.0, 0.0))
	await _ticks(100)
	var blown_z: float = banner._points[hem].z
	_check(blown_z > rest_z + 0.35, "world wind deflects rotated cloth: calm %.3f, gust %.3f" % [rest_z, blown_z])
	banner.set_wind(Vector3(-12.0, 0.0, 0.0))
	await _ticks(100)
	var min_z := INF
	for i in range(banner._points.size()):
		var point: Vector3 = banner._points[i]
		_check(point.is_finite(), "finite particle %d" % i)
		min_z = minf(min_z, point.z)
		if i < banner.COLS:
			_check(point == banner._rest[i], "pinned particle %d" % i)
	_check(min_z >= -banner.wall_setback + 0.0079 and min_z < -banner.wall_setback + 0.015,
		"reversed wind reaches backing wall without crossing: %.3f" % min_z)
	_check(banner._points[hem].z < rest_z - 0.05, "reversed wind changes the hem direction")
	banner.set_wind(Vector3.ZERO)
	await _ticks(240)
	_check(absf(banner._points[hem].z - rest_z) < 0.12, "cloth settles after wind stops")
	var max_stretch := 0.0
	for j in range(banner._lengths.size()):
		var a: Vector3 = banner._points[banner._links[2 * j]]
		var b: Vector3 = banner._points[banner._links[2 * j + 1]]
		max_stretch = maxf(max_stretch, a.distance_to(b) / banner._lengths[j] - 1.0)
	_check(max_stretch < 0.06, "settled fabric stretch: %.2f%%" % (100.0 * max_stretch))
	print("Banner: %d failures; hem z calm=%.3f gust=%.3f, minimum against wall=%.3f" % [failures, rest_z, blown_z, min_z])
	quit(0 if failures == 0 else 1)


func _ticks(count: int) -> void:
	for i in count:
		await physics_frame


func _check(condition: bool, label: String) -> void:
	if not condition:
		failures += 1
		push_error(label)


func _setup_preview(banner: Node3D) -> void:
	var camera := Camera3D.new()
	camera.position = Vector3(0.55, -1.0, 3.85)
	camera.fov = 41.0
	banner.add_child(camera)
	camera.look_at(banner.to_global(Vector3(0.0, -1.05, 0.0)))
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -28, 0)
	light.light_color = Color("ffe2b8")
	light.shadow_enabled = true
	banner.add_child(light)
	var world_env := WorldEnvironment.new()
	world_env.environment = Environment.new()
	world_env.environment.background_mode = Environment.BG_COLOR
	world_env.environment.background_color = Color("222935")
	world_env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_env.environment.ambient_light_color = Color("becbe2")
	world_env.environment.ambient_light_energy = 0.5
	banner.add_child(world_env)
	var wall := MeshInstance3D.new()
	var stone := BoxMesh.new()
	stone.size = Vector3(6.0, 5.5, 0.15)
	wall.mesh = stone
	wall.position = Vector3(0.0, -1.0, -0.205)
	var stone_material := StandardMaterial3D.new()
	stone_material.albedo_color = Color("596572")
	stone_material.roughness = 0.88
	wall.material_override = stone_material
	banner.add_child(wall)

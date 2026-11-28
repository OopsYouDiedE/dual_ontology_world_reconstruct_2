extends SceneTree
## Multi-angle architectural layout verification & screenshot capture for Public Hall.
## Verifies full walkability flood-fill from spawn to all wings and captures 4 angles.

const RunScene := preload("res://scenes/rogue/Run.tscn")

var failed := 0
var out_dir := "/tmp/hall_layout_shots"

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	run.call_deferred()

func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		failed += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func reachable_cells(view, start: Vector2i) -> Dictionary:
	var seen := {}
	var pending: Array[Vector2i] = [start]
	seen[start] = true
	while not pending.is_empty():
		var cell: Vector2i = pending.pop_back()
		for d: Vector2i in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var dest := cell + d
			if not seen.has(dest) and view._is_clear_cell(dest) and not view._has_wall_between(cell, dest):
				seen[dest] = true
				pending.append(dest)
	return seen

func snap(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [out_dir, name]
	var err := img.save_png(path)
	check(err == OK, "Saved %s (%dx%d)" % [path, img.get_width(), img.get_height()])

func aim_at(view, player, pos: Vector3, look_target: Vector3) -> void:
	var dir := look_target - pos
	view.place_player(pos, Vector3(dir.x, 0.0, dir.z))
	await frames(2)
	var cam: Camera3D = player.camera()
	if cam != null and player.has_method("orbit_by"):
		var horiz := Vector2(dir.x, dir.z).length()
		var target_pitch := atan2(look_target.y - cam.global_position.y, maxf(horiz, 0.01))
		var delta_y := (cam.rotation.x - target_pitch) / 0.0022
		player.orbit_by(Vector2(0.0, delta_y))
	await frames(2)

func run() -> void:
	var game := RunScene.instantiate()
	root.add_child(game)
	await frames(4)

	var view = game.room_view
	var player = view._player

	# 1. Strict walkability & wing reachability check
	for arch_z: int in [15, 17]:
		for door_x: int in [11, 21]:
			var a := Vector2i(door_x - 1, arch_z)
			var b := a + Vector2i.RIGHT
			check(view._is_clear_cell(a) and view._is_clear_cell(b) and not view._has_wall_between(a, b),
				"Clear side arcade %s <-> %s" % [str(a), str(b)])
	var reachable := reachable_cells(view, Vector2i(16, 24))
	for pt: Vector2i in [Vector2i(9, 15), Vector2i(9, 19), Vector2i(24, 15), Vector2i(22, 19), Vector2i(16, 7)]:
		check(reachable.has(pt), "Spawn reaches %s" % str(pt))

	# 2. Capture 4 architectural views
	await aim_at(view, player, Vector3(16.0, 0.0, 23.6), Vector3(16.0, 1.35, 11.0))
	await snap("01_nave_axial_view")

	await aim_at(view, player, Vector3(16.0, 0.0, 13.8), Vector3(16.0, 1.15, 6.2))
	await snap("02_north_study_and_salon")

	await aim_at(view, player, Vector3(10.6, 0.0, 16.8), Vector3(7.6, 0.9, 18.2))
	await snap("03_west_wing_dormitory")

	await aim_at(view, player, Vector3(21.4, 0.0, 16.5), Vector3(24.5, 1.0, 17.6))
	await snap("04_east_wing_refectory")

	print("HALL_LAYOUT_TEST failed=%d" % failed)
	quit(0 if failed == 0 else 1)

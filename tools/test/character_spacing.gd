extends SceneTree
## 无渲染回归：Godot --headless --path . --script res://tools/test/character_spacing.gd
## 覆盖角色出生点、NPC 占位寻路与 WASD 贴身避让。此脚本由正式运行时验收前执行。

const Main := preload("res://scenes/dual_world/DualWorldMain.tscn")

var failures := 0


func _check(ok: bool, label: String) -> void:
	print(("PASS  " if ok else "FAIL  ") + label)
	if not ok: failures += 1


func _center(cell: Vector2i, cell_size: float) -> Vector2:
	return Vector2((float(cell.x) + 0.5) * cell_size, (float(cell.y) + 0.5) * cell_size)


func _all_separate(points: Array, minimum: float) -> bool:
	for i in points.size():
		for j in range(i + 1, points.size()):
			if (points[i] as Vector2).distance_to(points[j] as Vector2) < minimum:
				return false
	return true


func _position_of(figure: Node3D) -> Vector2:
	return Vector2(figure.global_position.x, figure.global_position.z)


func _check_room_slots(game, room: String) -> void:
	game.eng.s.room = room
	game._build_room(room)
	game._sync_figures(true)
	game._det_to_home()
	var occupants := game.figures.size() + 1
	var slots: Array = game._free_slots(occupants)
	_check(not game._grid.is_point_solid(game._cell_of(game.det_pos)), "%s detective home is walkable" % room)
	_check(slots.size() >= occupants, "%s has a walkable slot for every occupant" % room)
	_check(_all_separate(slots, game.ACTOR_TOUCH_DISTANCE), "%s slots keep model capsules separate" % room)
	var actor_points: Array = [game.det_pos]
	for figure in game.figures.values(): actor_points.append(_position_of(figure))
	_check(_all_separate(actor_points, game.ACTOR_TOUCH_DISTANCE), "%s spawned actors do not overlap" % room)


func _narrow_space_regression(game) -> void:
	var saved_grid = game._grid
	var saved_design: Dictionary = game.room_mesh.design
	var saved_lowpoly: bool = game._lowpoly_ok
	var grid := AStarGrid2D.new()
	grid.region = Rect2i(0, 0, 8, 8)
	grid.cell_size = Vector2(game.CELL, game.CELL)
	grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	grid.update()
	for ix in grid.region.size.x:
		for iz in grid.region.size.y:
			grid.set_point_solid(Vector2i(ix, iz), true)
	grid.set_point_solid(Vector2i(4, 4), false)
	game._grid = grid
	game._lowpoly_ok = false
	game.room_mesh.design = {"w": 2.4, "d": 2.4, "props": []}
	var slots: Array = game._free_slots(4)
	_check(slots.size() == 1, "narrow space returns its one valid slot without duplicate fallback")
	game._grid = saved_grid
	game.room_mesh.design = saved_design
	game._lowpoly_ok = saved_lowpoly


func _opposite_cells(game, npc: Vector2) -> Array:
	var left := Vector2.INF
	var right := Vector2.INF
	for ix in game._grid.region.size.x:
		for iz in game._grid.region.size.y:
			var point := _center(Vector2i(ix, iz), game.CELL)
			if not game._det_can_occupy(point): continue
			if point.x < npc.x - 1.8 and left == Vector2.INF: left = point
			if point.x > npc.x + 1.8 and right == Vector2.INF: right = point
			if left != Vector2.INF and right != Vector2.INF: return [left, right]
	return []


func _check_path_and_wasd(game) -> void:
	game.eng.s.room = "B-P"
	game._build_room("B-P")
	game._sync_figures(true)
	game._wake_timer = 0.0
	game._cine = false
	game._manual_moving = false
	game.view = "room"
	game.eng.s.playing = true
	game.auto_search = false
	var selected: Node3D = null
	var pair: Array = []
	for figure in game.figures.values():
		var candidate: Array = _opposite_cells(game, _position_of(figure))
		if candidate.size() == 2:
			selected = figure
			pair = candidate
			break
	_check(selected != null, "B-P has two reachable sides around an NPC")
	if selected == null: return
	var npc := _position_of(selected)
	var start: Vector2 = pair[0]
	var goal: Vector2 = pair[1]
	game.det_pos = start
	game.det.position = Vector3(start.x, 0.0, start.y)
	game.det_path = game._route(start, goal)
	_check(not game.det_path.is_empty(), "A* returns a route around the NPC")
	for frame in 240:
		if game.det_path.is_empty(): break
		game._walk_step(1.0 / 30.0)
		for figure in game.figures.values():
			_check(game.det_pos.distance_to(_position_of(figure)) >= game.ACTOR_TOUCH_DISTANCE, "path step %d preserves capsule spacing" % frame)
	_check(game.det_pos.distance_to(goal) < 0.2, "route reaches the far side after avoiding the NPC")

	# az = 0 makes move_right advance along +x. Start left of the selected actor and hold D into it.
	game.az = 0.0
	game.det_pos = start
	game.det.position = Vector3(start.x, 0.0, start.y)
	var initial_distance := start.distance_to(npc)
	var nearest_distance := initial_distance
	var moved := false
	Input.action_press("move_right")
	for frame in 90:
		var before := game.det_pos
		game._manual_move_step(1.0 / 30.0)
		moved = moved or game.det_pos.distance_to(before) > 0.0001
		nearest_distance = minf(nearest_distance, game.det_pos.distance_to(npc))
		for figure in game.figures.values():
			_check(game.det_pos.distance_to(_position_of(figure)) >= game.ACTOR_TOUCH_DISTANCE, "WASD step %d preserves capsule spacing" % frame)
	Input.action_release("move_right")
	_check(moved and nearest_distance < initial_distance, "WASD advances toward the NPC and remains collision-safe")


func _initialize() -> void:
	var game = Main.instantiate()
	root.add_child(game)
	await process_frame
	# Keep the detective standing while validating home slots in the early rooms.
	game.eng.s.t = float(game.eng.T(1, 8, 0))
	game.eng.s.beat_cursor = 2
	for room in ["R05", "R06", "R07", "R08", "B-P"]:
		_check_room_slots(game, room)
	_narrow_space_regression(game)
	_check_path_and_wasd(game)
	game.queue_free()
	await process_frame
	print("RESULT failures=", failures)
	quit(1 if failures > 0 else 0)

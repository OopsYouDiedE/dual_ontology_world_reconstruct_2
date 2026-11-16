extends RefCounted
## Pick a reachable standing point before the actor walks into an inspection.
## Floor traces need enough space for the detective's body to clear the close-up.
static func plan(host: Control, target: Vector2, kind: String, start: Vector2, navigation: AStarGrid2D = null) -> Dictionary:
	var grid: AStarGrid2D = navigation if navigation != null else host._route_grid_with_figures()
	var minimum := 0.9 if kind in ["water", "drag", "boots", "cloth"] else 0.55
	var maximum := 1.48
	var valid := func(point: Vector2) -> bool:
		var distance := point.distance_to(target)
		return distance >= minimum and distance <= maximum and host._det_can_occupy(point)
	if valid.call(start): return {"ok": true, "stand": start, "path": [], "already_near": true}
	var candidates: Array[Vector2] = []
	for x in range(grid.region.position.x, grid.region.end.x):
		for z in range(grid.region.position.y, grid.region.end.y):
			var cell := Vector2i(x, z)
			if grid.is_point_solid(cell): continue
			var point := Vector2((x + 0.5) * host.CELL, (z + 0.5) * host.CELL)
			if valid.call(point): candidates.append(point)
	candidates.sort_custom(func(a: Vector2, b: Vector2): return start.distance_squared_to(a) < start.distance_squared_to(b))
	var origin: Vector2i = host._nearest_free(host._cell_of(start), grid)
	for stand in candidates:
		var cells: Array[Vector2i] = grid.get_id_path(origin, host._cell_of(stand))
		if cells.is_empty(): continue
		var route: Array = []
		for cell in cells: route.append(Vector2((cell.x + 0.5) * host.CELL, (cell.y + 0.5) * host.CELL))
		if route.size() > 1: route.pop_front()
		return {"ok": true, "stand": stand, "path": route, "already_near": false}
	return {"ok": false, "stand": start, "path": [], "already_near": false, "reason": "no_reachable_inspection_stand"}

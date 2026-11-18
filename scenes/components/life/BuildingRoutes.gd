extends RefCounted
## Building-wide physical routes. Each staircase joins two Grid route endpoints
## identified from the same centerline and elevations as the stair mesh.
const Grid := preload("BuildingSpace.gd")
const HEIGHT_EPS := 0.075
const STAIR_RESUME_EPS := 0.12

var floors: Array[Grid] = []
var ports: Array[Dictionary] = []
var flights: Array[Dictionary] = []
var rejected_stairs: Array[String] = []
var links: Dictionary = {}
var object_floors: Dictionary = {}
var primary: Grid
var data: Dictionary
var base_layer: int
var action_capacities: Dictionary
var door_states: Dictionary

func set_door_states(states: Dictionary) -> void:
	if door_states != states: setup(data, base_layer, action_capacities, states)

func setup(building: Dictionary, layer_index: int, capacities: Dictionary = {}, live_doors: Dictionary = {}) -> void:
	data = building
	base_layer = layer_index
	action_capacities = capacities
	door_states = live_doors.duplicate()
	primary = null
	floors.clear()
	ports.clear()
	flights.clear()
	rejected_stairs.clear()
	links.clear()
	object_floors.clear()
	for i in range(building.layers.size()):
		var grid := Grid.new()
		grid.setup(building, i, capacities, door_states)
		floors.append(grid)
		if i == layer_index: primary = grid
		for id in grid.object_by_id:
			if not object_floors.has(id) or absf(float(grid.object_by_id[id].prop.get("y", 0.0)) - grid.layer_y) < absf(float(grid.object_by_id[id].prop.get("y", 0.0)) - floors[object_floors[id]].layer_y):
				object_floors[id] = i
	for stair in building.get("stairs", []):
		if not _add_stair(stair): rejected_stairs.append(str(stair.get("id", "")))

func _add_stair(stair: Dictionary) -> bool:
	var run := float(stair.get("run", 0.0))
	var rise := float(stair.get("rise", 0.0))
	var yaw := deg_to_rad(float(stair.get("yaw", 0.0)))
	var foot := Vector3(stair.x, stair.get("y", 0.0), stair.z)
	if not foot.is_finite() or not is_finite(yaw) or not is_finite(run) or not is_finite(rise): return false
	if run <= 0.0 or rise <= HEIGHT_EPS * 2.0 or float(stair.get("width", 0.0)) < 0.5 or int(stair.get("risers", 0)) < 1: return false
	var direction := Vector3(cos(yaw), 0.0, -sin(yaw))
	var head := foot + direction * run + Vector3.UP * rise
	var low := _landing(foot, -direction)
	var high := _landing(head, direction)
	if low.is_empty() or high.is_empty() or low.floor == high.floor: return false
	if not _clear_flight(foot, head): return false
	var i := ports.size()
	ports.append(low)
	ports.append(high)
	flights.append({"id": str(stair.get("id", "")), "low": i, "high": i + 1, "foot": foot, "head": head})
	links[Vector2i(i, i + 1)] = _segment(low.point, [foot, head, high.point])
	links[Vector2i(i + 1, i)] = _segment(high.point, [head, foot, low.point])
	return true

func _clear_flight(foot: Vector3, head: Vector3) -> bool:
	const BODY_RADIUS := 0.18
	var length := foot.distance_to(head)
	if not is_finite(length) or length > 360.0: return false
	var samples := maxi(2, ceili(length / 0.12))
	for i in range(1, samples):
		var pos := foot.lerp(head, float(i) / samples)
		var at := _xz(pos)
		for grid in floors:
			var clearance := grid.layer_y - pos.y
			if clearance <= HEIGHT_EPS or clearance >= Grid.MIN_PASSAGE_HEIGHT: continue
			for surface in grid.surfaces:
				if Geometry2D.is_point_in_polygon(at, surface.polygon): return false
		for wall in data.walls:
			var points: Array = wall.get("points", [])
			if points.size() < 2: continue
			var y := float(wall.get("baseY", points[0][1]))
			if y + float(wall.height) <= pos.y + 0.02 or y >= pos.y + Grid.MIN_PASSAGE_HEIGHT: continue
			var count := points.size() if wall.get("closed", false) and points.front() != points.back() else points.size() - 1
			for segment in range(count):
				var a := Vector2(points[segment][0], points[segment][2])
				var b := Vector2(points[(segment + 1) % points.size()][0], points[(segment + 1) % points.size()][2])
				if a.is_equal_approx(b): continue
				var nearest := Geometry2D.get_closest_point_to_segment(at, a, b)
				if nearest.distance_to(at) >= float(wall.thickness) * 0.5 + BODY_RADIUS: continue
				var along := a.distance_to(nearest)
				var through_opening := false
				for opening in wall.get("openings", []):
					if int(opening.segment) != segment or str(opening.type) not in Grid.DOORS: continue
					if door_states.get(str(opening.get("id", "")), "open") != "open": continue
					var floor_y := y + float(opening.get("bottom", 0.0))
					if floor_y > pos.y + Grid.CLEARANCE or floor_y + float(opening.height) < pos.y + Grid.MIN_PASSAGE_HEIGHT: continue
					if absf(float(opening.center) - along) + BODY_RADIUS <= float(opening.width) * 0.5:
						through_opening = true
						break
				if not through_opening: return false
	return true

func _landing(edge: Vector3, outward: Vector3) -> Dictionary:
	for f in range(floors.size()):
		var grid := floors[f]
		if absf(edge.y - grid.layer_y) > HEIGHT_EPS: continue
		# Approach along the stair axis. Never project sideways onto adjacent or
		# distant floor, nor across a blocked landing.
		var offset := grid.cell * 0.5
		var first := edge + outward * offset
		if grid.is_solid_at(_xz(first)): continue
		var inside := edge + outward * (0.5 + offset)
		if grid.line_clear(_xz(first), _xz(inside)):
			return {"floor": f, "point": Vector3(inside.x, grid.layer_y, inside.z)}
	return {}

static func _xz(p: Vector3) -> Vector2: return Vector2(p.x, p.z)

func floor_at(point: Vector3) -> int:
	for i in range(floors.size()):
		if absf(point.y - floors[i].layer_y) <= HEIGHT_EPS and not floors[i].is_solid_at(_xz(point)): return i
	return -1

func nearby_floor_point(point: Vector3, radius := 4) -> Vector3:
	for grid in floors:
		if absf(point.y - grid.layer_y) > HEIGHT_EPS: continue
		var flat := grid.nearest_free(_xz(point), radius)
		if flat.is_finite(): return Vector3(flat.x, grid.layer_y, flat.y)
	return Vector3.INF

func spawn_near(point: Vector3, occupied: Array[Vector3], radius := 8, spacing := 0.9) -> Vector3:
	for grid in floors:
		if absf(point.y - grid.layer_y) > HEIGHT_EPS: continue
		for candidate in grid.free_starts(_xz(point), radius):
			var stand := Vector3(candidate.x, grid.layer_y, candidate.y)
			if not occupied.any(func(other: Vector3) -> bool: return stand.distance_squared_to(other) < spacing * spacing):
				return stand
	return Vector3.INF

func _flat(grid: Grid, from: Vector3, to: Vector3) -> Dictionary:
	var route := grid.route_between(_xz(from), _xz(to))
	if route.is_empty(): return {}
	var points: Array[Vector3] = []
	for p in route.path: points.append(Vector3(p.x, grid.layer_y, p.y))
	return {"path": points, "length": float(route.length)}

static func path_length(from: Vector3, path: Array) -> float:
	var total := 0.0
	for p in path:
		total += from.distance_to(p)
		from = p
	return total

func _segment(from: Vector3, points: Array) -> Dictionary:
	var path: Array[Vector3] = []
	var last := from
	for p in points:
		if not last.is_equal_approx(p): path.append(p)
		last = p
	return {"path": path, "length": path_length(from, path)}

func _port_link(from: int, to: int) -> Dictionary:
	var key := Vector2i(from, to)
	if links.has(key): return links[key]
	var a := ports[from]
	var b := ports[to]
	var route := _flat(floors[a.floor], a.point, b.point) if a.floor == b.floor else {}
	links[key] = route
	return route

func _enter(from: Vector3, source_floor: int) -> Dictionary:
	var entry := {}
	if source_floor >= 0:
		for i in range(ports.size()):
			if ports[i].floor != source_floor: continue
			var edge := _flat(floors[source_floor], from, ports[i].point)
			if not edge.is_empty(): entry[i] = edge
	else:
		# Resume from an interrupted or restored flight. A point off the flight
		# cannot enter a floor by projection across the height difference.
		for flight in flights:
			var projected := Geometry3D.get_closest_point_to_segment(from, flight.foot, flight.head)
			if from.distance_to(projected) > STAIR_RESUME_EPS: continue
			entry[flight.low] = _segment(from, [projected, flight.foot, ports[flight.low].point])
			entry[flight.high] = _segment(from, [projected, flight.head, ports[flight.high].point])
	return entry

func find_route(from: Vector3, to: Vector3) -> Dictionary:
	if not from.is_finite() or not to.is_finite(): return {}
	var a := floor_at(from)
	var b := floor_at(to)
	if b < 0: return {}
	var best := _flat(floors[a], from, to) if a == b else {}
	var queue := _enter(from, a)
	var seen := {}
	while not queue.is_empty():
		var next := -1
		var shortest := float(best.get("length", INF))
		for index in queue:
			if queue[index].length < shortest:
				next = index
				shortest = queue[index].length
		if next < 0: break
		var route: Dictionary = queue[next]
		var port := ports[next]
		queue.erase(next)
		seen[next] = true
		if port.floor == b:
			var finish := _flat(floors[b], port.point, to)
			if not finish.is_empty() and shortest + finish.length < float(best.get("length", INF)):
				best = {"path": route.path + finish.path, "length": shortest + finish.length}
		for i in range(ports.size()):
			if seen.has(i): continue
			var edge := _port_link(next, i)
			if edge.is_empty(): continue
			var length: float = shortest + edge.length
			if not queue.has(i) or length < queue[i].length:
				queue[i] = {"path": route.path + edge.path, "length": length}
	return best

func plan_use(from: Vector3, id: String, action: Dictionary, slot: int) -> Dictionary:
	if not object_floors.has(id): return {}
	var f: int = object_floors[id]
	var grid := floors[f]
	var obj: Dictionary = grid.object_by_id[id]
	var best := {}
	for point in grid.use_points(obj, action, slot):
		var at := Vector3(point.approach.x, grid.layer_y, point.approach.y)
		var route := find_route(from, at)
		if not route.is_empty() and route.length < float(best.get("length", INF)):
			best = route
			best["target"] = at
	return best

func physical_object_route_length(x: float, y: float, z: float, id: String, action: String, slot: int, actions: Dictionary) -> float:
	if not actions.has(action): return INF
	return float(plan_use(Vector3(x, y, z), id, actions[action], slot).get("length", INF))

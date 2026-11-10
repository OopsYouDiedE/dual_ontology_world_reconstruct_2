extends RefCounted
const Footprint = preload("res://tools/building_construction/BuildingConstruction/Props/PropFootprint.gd")

const DOORS := ["double_door", "closed_door", "arched_closed_door", "portal_arch"]
const SEAT_LIFT := {"chair": 0.45, "sofa": 0.42, "bench": 0.45, "bed": 0.55}
const SEATS := ["chair", "sofa", "bench"]
const TABLES := ["table", "round_table"]

var data: Dictionary = {}
var layer_index := 0
var layer_y := 0.0
var cell := 0.25
var origin := Vector2.ZERO
var nx := 0
var ny := 0
var astar: AStarGrid2D
var solid := PackedByteArray()
var rooms: Array = []
var objects: Array = []
var object_by_id: Dictionary = {}
var bounds := Rect2()
var capacities: Dictionary = {}

func setup(building: Dictionary, layer_idx := 0, declared_capacities: Dictionary = {}) -> void:
	data = building
	capacities = declared_capacities
	layer_index = clampi(layer_idx, 0, maxi(building.layers.size() - 1, 0))
	var layer: Dictionary = building.layers[layer_index]
	layer_y = float(layer.y)
	rooms.clear()
	for face in layer.get("roomFaces", []):
		var ring := PackedVector2Array()
		var lo := Vector2(INF, INF)
		var hi := Vector2(-INF, -INF)
		for point in face.polygon:
			var vertex := Vector2(point[0], point[1])
			ring.append(vertex)
			lo = Vector2(minf(lo.x, vertex.x), minf(lo.y, vertex.y))
			hi = Vector2(maxf(hi.x, vertex.x), maxf(hi.y, vertex.y))
		rooms.append({"index": rooms.size(), "polygon": ring, "box": Rect2(lo, hi - lo), "centroid": Vector2(face.centroid[0], face.centroid[1]), "area": float(face.get("area", 0.0)), "kind": "room"})
	_collect_objects()
	_infer_room_kinds()
	_build_grid()

func room_at(point: Vector2) -> int:
	for room in rooms:
		if room.box.grow(0.05).has_point(point) and Geometry2D.is_point_in_polygon(point, room.polygon): return room.index
	return -1

func _collect_objects() -> void:
	objects.clear()
	object_by_id.clear()
	for prop in data.props:
		if absf(float(prop.get("y", 0.0)) - layer_y) > 0.6: continue
		var kind := str(prop.kind)
		var id := str(prop.get("id", "prop_%d" % objects.size()))
		while object_by_id.has(id): id += "'"
		var yaw := deg_to_rad(float(prop.get("yaw", 0.0)))
		var center := Vector2(float(prop.x), float(prop.z))
		var info := Footprint.info(prop)
		var front := Vector2(sin(yaw), cos(yaw))
		var obj := {"id": id, "kind": kind, "prop": prop, "center": center, "yaw": yaw, "front": front, "info": info,
			"room": -1, "cap": int(capacities.get(kind, 1)), "near_tables": [], "room_kind": str(prop.get("room_kind", ""))}
		obj.room = room_at(center + front * 0.35 if info.mount == Footprint.WALL else center)
		objects.append(obj)
		object_by_id[id] = obj
	for obj in objects:
		if SEATS.has(obj.kind):
			var probe := Footprint.to_world(obj.prop, Vector2(0.0, obj.info.d * 0.5 + 0.4))
			for other in objects:
				if TABLES.has(other.kind) and Footprint.contains(other.prop, probe, 0.3): obj.near_tables.append(other.id)

func _infer_room_kinds() -> void:
	for room in rooms:
		var count := {}
		var tagged := {}
		for obj in objects:
			if obj.room != room.index: continue
			count[obj.kind] = int(count.get(obj.kind, 0)) + 1
			if obj.room_kind != "": tagged[obj.room_kind] = int(tagged.get(obj.room_kind, 0)) + 1
		var kind := "room"
		if not tagged.is_empty():
			var best := 0
			for entry_index in tagged:
				if tagged[entry_index] > best: best = tagged[entry_index]; kind = entry_index
		elif count.get("bed", 0) > 0: kind = "bedroom"
		elif count.get("chair", 0) >= 3 and count.get("table", 0) + count.get("round_table", 0) > 0: kind = "dining"
		elif count.get("bookshelf", 0) > 0: kind = "study"
		elif count.get("sofa", 0) > 0 or count.get("upright_piano", 0) > 0: kind = "living"
		room.kind = kind
		for obj in objects:
			if obj.room == room.index: obj.room_kind = kind

func objects_of(kinds: Array) -> Array:
	var out: Array = []
	for obj in objects:
		if kinds.has(obj.kind): out.append(obj)
	return out

func beds() -> Array:
	return objects_of(["bed"])

func _cell_center(column_index: int, row_index: int) -> Vector2:
	return origin + Vector2((column_index + 0.5) * cell, (row_index + 0.5) * cell)

func _cell_of(point: Vector2) -> Vector2i:
	return Vector2i(clampi(int(floor((point.x - origin.x) / cell)), 0, nx - 1), clampi(int(floor((point.y - origin.y) / cell)), 0, ny - 1))

func is_solid_at(point: Vector2) -> bool:
	var grid_cell := _cell_of(point)
	return solid[grid_cell.y * nx + grid_cell.x] == 1

func _build_grid() -> void:
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for room in rooms:
		lo = Vector2(minf(lo.x, room.box.position.x), minf(lo.y, room.box.position.y))
		hi = Vector2(maxf(hi.x, room.box.end.x), maxf(hi.y, room.box.end.y))
	if not is_finite(lo.x):
		lo = Vector2(-4, -4); hi = Vector2(4, 4)
	origin = lo - Vector2(1.5, 1.5)
	var size := hi - lo + Vector2(3.0, 3.0)
	nx = int(ceil(size.x / cell))
	ny = int(ceil(size.y / cell))
	bounds = Rect2(lo, hi - lo)
	solid.resize(nx * ny)
	solid.fill(1)
	for row_index in range(ny):
		for column_index in range(nx):
			if room_at(_cell_center(column_index, row_index)) >= 0: solid[row_index * nx + column_index] = 0
	var walls_here: Array = []
	for wall in data.walls:
		if absf(float(wall.get("baseY", wall.points[0][1])) - layer_y) < 0.3: walls_here.append(wall)
	for wall in walls_here:
		var pts: Array = []
		for point in wall.points: pts.append(Vector2(point[0], point[2]))
		if wall.get("closed", false) and pts.size() > 2 and pts[0].distance_to(pts[pts.size() - 1]) > 0.01: pts.append(pts[0])
		var half := float(wall.thickness) * 0.5 + 0.12
		for segment_index in range(pts.size() - 1):
			_stamp_segment(pts[segment_index], pts[segment_index + 1], half)
	for wall in walls_here:
		var pts: Array = []
		for point in wall.points: pts.append(Vector2(point[0], point[2]))
		for op in wall.get("openings", []):
			if not DOORS.has(str(op.type)): continue
			var segment_index := int(op.segment)
			if segment_index < 0 or segment_index >= pts.size() - 1: continue
			var along: Vector2 = (pts[segment_index + 1] - pts[segment_index]).normalized()
			_open_gap(pts[segment_index] + along * float(op.center), along, float(op.width) * 0.5 - 0.06, float(wall.thickness) * 0.5 + 0.35)
	for obj in objects:
		if not Footprint.blocks(obj.prop): continue
		var corners := Footprint.corners(obj.prop, 0.12)
		var box := Rect2(corners[0], Vector2.ZERO)
		for grid_cell in corners: box = box.expand(grid_cell)
		var low_cell := _cell_of(box.position)
		var high_cell := _cell_of(box.end)
		for row_index in range(low_cell.y, high_cell.y + 1):
			for column_index in range(low_cell.x, high_cell.x + 1):
				if Footprint.contains(obj.prop, _cell_center(column_index, row_index), 0.12): solid[row_index * nx + column_index] = 1
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, nx, ny)
	astar.cell_size = Vector2(cell, cell)
	astar.offset = origin
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for row_index in range(ny):
		for column_index in range(nx):
			if solid[row_index * nx + column_index] == 1: astar.set_point_solid(Vector2i(column_index, row_index), true)

func _stamp_segment(start_point: Vector2, end_point: Vector2, half: float) -> void:
	var box := Rect2(start_point, Vector2.ZERO).expand(end_point).grow(half)
	var c0 := _cell_of(box.position)
	var c1 := _cell_of(box.end)
	for row_index in range(c0.y, c1.y + 1):
		for column_index in range(c0.x, c1.x + 1):
			var point := _cell_center(column_index, row_index)
			var nearest_point := Geometry2D.get_closest_point_to_segment(point, start_point, end_point)
			if point.distance_to(nearest_point) < half: solid[row_index * nx + column_index] = 1

func _open_gap(center: Vector2, along: Vector2, half_width: float, half_depth: float) -> void:
	var across := Vector2(-along.y, along.x)
	var box := Rect2(center, Vector2.ZERO).grow(maxf(half_width, half_depth) + 0.3)
	var c0 := _cell_of(box.position)
	var c1 := _cell_of(box.end)
	for row_index in range(c0.y, c1.y + 1):
		for column_index in range(c0.x, c1.x + 1):
			var depth := _cell_center(column_index, row_index) - center
			if absf(depth.dot(along)) <= half_width and absf(depth.dot(across)) <= half_depth: solid[row_index * nx + column_index] = 0

func nearest_free(point: Vector2, radius := 8) -> Vector2:
	var grid_cell := _cell_of(point)
	if solid[grid_cell.y * nx + grid_cell.x] == 0: return _cell_center(grid_cell.x, grid_cell.y)
	for search_radius in range(1, radius + 1):
		var best := Vector2.INF
		var best_d := INF
		for row_index in range(maxi(grid_cell.y - search_radius, 0), mini(grid_cell.y + search_radius, ny - 1) + 1):
			for column_index in range(maxi(grid_cell.x - search_radius, 0), mini(grid_cell.x + search_radius, nx - 1) + 1):
				if solid[row_index * nx + column_index] == 1: continue
				var nearest_point := _cell_center(column_index, row_index)
				if nearest_point.distance_to(point) < best_d:
					best_d = nearest_point.distance_to(point)
					best = nearest_point
		if best != Vector2.INF: return best
	return Vector2.INF

func line_clear(start_point: Vector2, end_point: Vector2) -> bool:
	var sample_count := int(ceil(start_point.distance_to(end_point) / (cell * 0.5)))
	for entry_index in range(1, sample_count):
		if is_solid_at(start_point.lerp(end_point, float(entry_index) / float(sample_count))): return false
	return true

func find_path(from: Vector2, to: Vector2) -> Array:
	var start_point := nearest_free(from)
	var end_point := nearest_free(to, 2)
	if start_point == Vector2.INF or end_point == Vector2.INF: return []
	var ids: Array[Vector2i] = astar.get_id_path(_cell_of(start_point), _cell_of(end_point))
	if ids.is_empty(): return []
	var pts: Array = []
	for id in ids: pts.append(_cell_center(id.x, id.y))
	var out: Array = []
	var anchor: Vector2 = pts[0]
	var column_index := 1
	while column_index < pts.size():
		var row_index := pts.size() - 1
		while row_index > column_index and not line_clear(anchor, pts[row_index]): row_index -= 1
		out.append(pts[row_index])
		anchor = pts[row_index]
		column_index = row_index + 1
	return out

func path_length(from: Vector2, path: Array) -> float:
	var total := 0.0
	var at := from
	for point in path:
		total += at.distance_to(point)
		at = point
	return total

func random_free_point(rng: RandomNumberGenerator, room_index := -1) -> Vector2:
	for attempt in range(40):
		var room: Dictionary = rooms[room_index] if room_index >= 0 else rooms[rng.randi() % rooms.size()]
		var point := Vector2(rng.randf_range(room.box.position.x, room.box.end.x), rng.randf_range(room.box.position.y, room.box.end.y))
		if Geometry2D.is_point_in_polygon(point, room.polygon) and not is_solid_at(point) and not is_solid_at(point + Vector2(0.3, 0)) and not is_solid_at(point - Vector2(0.3, 0)): return point
	return nearest_free(rooms[0].centroid)

func use_points(obj: Dictionary, act: Dictionary, slot := 0) -> Array:
	var item: Dictionary = obj.prop
	var width: float = obj.info.w
	var depth: float = obj.info.d
	var pose := str(act.get("pose", "stand"))
	var kind: String = obj.kind
	var out: Array = []
	if SEATS.has(kind) and (pose == "sit" or pose == "lie"):
		var sx := 0.0
		if obj.cap > 1: sx = (-0.22 if slot % 2 == 0 else 0.22) * width
		var seat := Footprint.to_world(item, Vector2(sx, -0.03))
		var yaw: float = obj.yaw + (PI * 0.5 if pose == "lie" else 0.0)
		var lift: float = SEAT_LIFT.get(kind, 0.45)
		var offsets := [Vector2(width * 0.5 + 0.45, 0.0), Vector2(-(width * 0.5 + 0.45), 0.0), Vector2(sx, depth * 0.5 + 0.45), Vector2(sx, -(depth * 0.5 + 0.45))]
		for offset in offsets:
			out.append({"approach": Footprint.to_world(item, offset), "pos": seat, "yaw": yaw, "lift": lift})
	elif kind == "bed" and pose == "lie":
		var lying := Footprint.to_world(item, Vector2(0.0, 0.05))
		for side in [1.0, -1.0]:
			out.append({"approach": Footprint.to_world(item, Vector2(side * (width * 0.5 + 0.45), 0.3)), "pos": lying, "yaw": obj.yaw, "lift": SEAT_LIFT.bed})
	else:
		var wall: bool = obj.info.mount == Footprint.WALL
		var reach_d := depth + 0.6 if wall else depth * 0.5 + 0.55
		var local_c := Vector2(0.0, depth * 0.5) if wall else Vector2.ZERO
		var offsets: Array = [Vector2(0.0, reach_d), Vector2(width * 0.5 + 0.5, 0.0), Vector2(-(width * 0.5 + 0.5), 0.0), Vector2(0.0, -reach_d)]
		if wall: offsets = [Vector2(0.0, reach_d), Vector2(width * 0.3, reach_d), Vector2(-width * 0.3, reach_d)]
		for offset in offsets:
			var at := Footprint.to_world(item, offset)
			var look: Vector2 = Footprint.to_world(item, local_c) - at
			out.append({"approach": at, "pos": at, "yaw": atan2(look.x, look.y), "lift": 0.0})
	var free: Array = []
	for use_point in out:
		if not is_solid_at(use_point.approach): free.append(use_point)
	return free

func plan_use(from: Vector2, obj: Dictionary, act: Dictionary, slot := 0) -> Dictionary:
	var best := {}
	var best_len := INF
	for use_point in use_points(obj, act, slot):
		var path := find_path(from, use_point.approach)
		if path.is_empty() and from.distance_to(use_point.approach) > 0.4: continue
		var length := path_length(from, path)
		if length < best_len:
			best_len = length
			best = {"point": use_point, "path": path, "length": length}
	return best

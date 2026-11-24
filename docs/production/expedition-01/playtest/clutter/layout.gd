extends RefCounted
## Pure layout API: generate(seed, room_id) -> JSON-ready Dictionary; validate(layout) -> Array[String].
const ROOM := Vector3(10, 3.2, 8)
const DOOR := 1.4
const CLEAR_HALF := 0.58
const SUPPORT_MARGIN := 0.05
const EPS := 0.0001

static func xyz(v: Array) -> Vector3:
	return Vector3(v[0], v[1], v[2])

static func box(id: String, center: Vector3, size: Vector3, support: String, layer: int) -> Dictionary:
	return {"id": id, "center": [center.x, center.y, center.z],
		"size": [size.x, size.y, size.z], "support": support, "layer": layer}

static func bounds(item: Dictionary) -> AABB:
	var size := xyz(item.size)
	return AABB(xyz(item.center) - size * 0.5, size)

static func generate(seed: int, room_id: String = "", density: float = 1.0, max_layers: int = 3) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed ^ room_id.sha256_text().substr(0, 12).hex_to_int()
	var bend := rng.randf_range(-1.25, 1.25)
	var route := [[-6.2, 0, 0], [-2.5, 0, 0], [-2.5, 0, bend],
		[2.5, 0, bend], [2.5, 0, 0], [6.2, 0, 0]]
	var items: Array = []
	for row in range(5):
		for col in range(6):
			var x := -4.0 + col * 1.6 + rng.randf_range(-0.16, 0.16)
			var z := -3.2 + row * 1.6 + rng.randf_range(-0.15, 0.15)
			var size := Vector3(rng.randf_range(0.85, 1.15), rng.randf_range(0.35, 0.65), rng.randf_range(0.85, 1.15))
			var id := 'stack_%d_%d_' % [row, col]
			var base := box(id + '1', Vector3(x, size.y / 2, z), size, '', 1)
			if hits_route(bounds(base), route) or density <= 0.0:
				continue
			if density < 1.0 and rng.randf() >= density:
				continue
			items.append(base)
			var top := size.y
			var depth := max_layers if items.size() == 1 else rng.randi_range(1, max_layers)
			for layer in range(2, depth + 1):
				size = Vector3(size.x * rng.randf_range(0.68, 0.82), rng.randf_range(0.25, 0.56), size.z * rng.randf_range(0.68, 0.82))
				x += rng.randf_range(-0.045, 0.045)
				z += rng.randf_range(-0.045, 0.045)
				items.append(box(id + str(layer), Vector3(x, top + size.y / 2, z), size, id + str(layer - 1), layer))
				top += size.y
	return {"schema": "clutter-layout/v1", "seed": seed, "room_id": room_id, "room_size": [10, 3.2, 8],
		"density": density, "max_layers": max_layers, "door_width": DOOR, "route_clear_half_width": CLEAR_HALF, "route": route, "items": items}

static func hits_route(a: AABB, route: Array) -> bool:
	for i in range(1, route.size()):
		var p := xyz(route[i - 1])
		var q := xyz(route[i])
		var low := p.min(q) - Vector3(CLEAR_HALF, 0, CLEAR_HALF)
		var high := p.max(q) + Vector3(CLEAR_HALF, 2.0, CLEAR_HALF)
		if a.intersects(AABB(low, high - low)):
			return true
	return false

static func validate(layout: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	var by_id := {}
	var boxes := {}
	for item in layout.items:
		var id: String = item.id
		var a := bounds(item)
		if id.is_empty() or by_id.has(id):
			errors.append('duplicate_id:' + id)
			continue
		for other in boxes:
			var overlap := a.intersection(boxes[other]).size
			if overlap.x > EPS and overlap.y > EPS and overlap.z > EPS:
				errors.append('overlap:' + id + ':' + other)
		by_id[id] = item
		boxes[id] = a
		if not a.position.is_finite() or not a.size.is_finite() or minf(a.size.x, minf(a.size.y, a.size.z)) <= EPS:
			errors.append('invalid_box:' + id)
		if a.position.x < -ROOM.x/2-EPS or a.end.x > ROOM.x/2+EPS or a.position.z < -ROOM.z/2-EPS or a.end.z > ROOM.z/2+EPS or a.position.y < -EPS or a.end.y > ROOM.y+EPS:
			errors.append('out_of_room:' + id)
		if hits_route(a, layout.route):
			errors.append('route:' + id)
		for station in layout.get('stations', []):
			if hits_route(a, station.route):
				errors.append('approach:' + station.id + ':' + id)
	# Accumulate uniform-density load of each descendant into each ancestor.
	var loads := {}
	for id in by_id:
		var a: AABB = boxes[id]
		var mass := a.get_volume()
		var center := a.get_center()
		var cursor: String = id
		var seen := {}
		while by_id.has(cursor) and not seen.has(cursor):
			seen[cursor] = true
			loads[cursor] = loads.get(cursor, Vector4.ZERO) + Vector4(center.x * mass, center.y * mass, center.z * mass, mass)
			cursor = by_id[cursor].support
		if seen.has(cursor):
			errors.append('cycle:' + id)
	for id in by_id:
		var item: Dictionary = by_id[id]
		var a: AABB = boxes[id]
		var p := a
		if item.support == '':
			if absf(a.position.y) > EPS or item.layer != 1:
				errors.append('floor_contact:' + id)
		else:
			if not by_id.has(item.support):
				errors.append('missing_support:' + id)
				continue
			p = boxes[item.support]
			if absf(a.position.y - p.end.y) > EPS or item.layer != by_id[item.support].layer + 1:
				errors.append('stack_contact:' + id)
		var load: Vector4 = loads[id]
		if load.w <= EPS or load.x/load.w < maxf(a.position.x, p.position.x) + SUPPORT_MARGIN or load.x/load.w > minf(a.end.x, p.end.x) - SUPPORT_MARGIN or load.z/load.w < maxf(a.position.z, p.position.z) + SUPPORT_MARGIN or load.z/load.w > minf(a.end.z, p.end.z) - SUPPORT_MARGIN:
			errors.append('unstable:' + id)
	return errors

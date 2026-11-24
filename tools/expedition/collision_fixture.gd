extends RefCounted
## Opt-in after the production scene enters the tree. Visual-only GPU savings.
const EFFECTS := [&"sdfgi_enabled", &"ssao_enabled", &"ssil_enabled", &"ssr_enabled"]
const CURVE_SAMPLES := 32

static func apply_lightweight(level: Node) -> Dictionary:
	assert(level.is_node_ready(), "Apply the collision fixture after add_child().")
	var changed := {}
	for node in level.find_children("*", "WorldEnvironment", true, false):
		var world := node as WorldEnvironment
		if world.environment == null: continue
		var local := world.environment.duplicate() as Environment
		var disabled := []
		for effect in EFFECTS:
			if local.get(effect):
				disabled.append(effect)
				local.set(effect, false)
		if not disabled.is_empty():
			world.environment = local
			changed[_path(level, world)] = disabled
	return changed

## Capture after a physics update for moving bodies and initial CSG generation.
## Returns JSON-ready data; errors mean geometry is incomplete.
static func capture(level) -> Dictionary:
	assert(level.is_node_ready(), "Capture a live Expedition instance.")
	var kit = level.kit
	var roles: Dictionary = {
		level.walker: "player", kit.maintenance.leaf: "maintenance_lift",
		kit.test_board: "gaze_plate", kit.clock_shutter: "clock_shutter",
		kit.shaft_shutter: "shaft_shutter", kit.return_exit_gate: "return_gate",
		kit.airlock: "airlock", kit.leave_pivot: "egress_leaf", kit.solo_hatch: "solo_hatch",
		kit.gate: "archive_gate", kit.bridge: "shaft_bridge",
	}
	var result := {"schema": "expedition-collision-v1", "plane": ["x", "z"], "vertical": "y",
		"units": "meters", "shapes": [], "errors": []}
	for node in level.find_children("*", "CollisionObject3D", true, false):
		var body := node as CollisionObject3D
		var meta := _metadata(level, body, roles)
		for owner in body.get_shape_owners():
			var pose := body.global_transform * body.shape_owner_get_transform(owner)
			for index in body.shape_owner_get_shape_count(owner):
				_add(result, meta, "%s:%d:%d" % [meta.path, owner, index], body.shape_owner_get_shape(owner, index),
					pose, body.is_shape_owner_disabled(owner))
	for node in level.find_children("*", "CSGShape3D", true, false):
		var csg := node as CSGShape3D
		if csg.use_collision and csg.is_root_shape():
			var meta := _metadata(level, csg, roles)
			_add(result, meta, "%s:csg" % meta.path, csg.bake_collision_shape(), csg.global_transform, false)
	return result

static func fingerprint(geometry: Dictionary) -> String:
	return JSON.stringify(geometry, "", true, true).sha256_text()

static func write_json(path: String, geometry: Dictionary) -> Error:
	if not geometry.errors.is_empty(): return ERR_INVALID_DATA
	var output := FileAccess.open(path, FileAccess.WRITE)
	if output == null: return FileAccess.get_open_error()
	output.store_string(JSON.stringify(geometry, "\t", true, true) + "\n")
	return output.get_error()

static func _path(root: Node, node: Node) -> String:
	var parts := PackedStringArray()
	while node != root:
		# Runtime-generated @Names contain process-global instance counters.
		var label := String(node.name)
		if label.begins_with("@"): label = node.get_class()
		elif label.begins_with("_Node3D_") and label.get_slice("_", 2).is_valid_int():
			# ArchBuilder sanitizes an @Node3D@<counter> source into _Node3D_<counter>_Part.
			label = "Generated_" + label.substr(9 + label.get_slice("_", 2).length())
		parts.insert(0, "%s[%d]" % [label, node.get_index()])
		node = node.get_parent()
	return "/".join(parts)

static func _metadata(root: Node, body: Node3D, roles: Dictionary) -> Dictionary:
	var tagged := body
	while tagged != root and not roles.has(tagged): tagged = tagged.get_parent()
	var role: String = roles.get(tagged, "trigger" if body is Area3D else "structure")
	return {"path": _path(root, body), "body_type": body.get_class(), "role": role,
		"layer": body.get("collision_layer"), "mask": body.get("collision_mask")}

static func _xyz(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

static func _add(result: Dictionary, meta: Dictionary, id: String, shape: Shape3D, pose: Transform3D, disabled: bool) -> void:
	var row := meta.duplicate()
	row.merge({"id": id, "disabled": disabled, "transform": [_xyz(pose.basis.x), _xyz(pose.basis.y),
		_xyz(pose.basis.z), _xyz(pose.origin)]})
	var points := PackedVector3Array()
	if shape is BoxShape3D:
		row.parameters = {"size": _xyz(shape.size)}
		for x in [-0.5, 0.5]:
			for y in [-0.5, 0.5]:
				for z in [-0.5, 0.5]: points.append(shape.size * Vector3(x, y, z))
	elif shape is ConvexPolygonShape3D:
		points = shape.points
		row.parameters = {"points": Array(points).map(_xyz)}
	elif shape is ConcavePolygonShape3D:
		points = shape.get_faces()
		row.parameters = {"faces": Array(points).map(_xyz), "backface_collision": shape.backface_collision}
	elif shape is CapsuleShape3D or shape is SphereShape3D:
		var half_segment: float = maxf(0.0, shape.height * 0.5 - shape.radius) if shape is CapsuleShape3D else 0.0
		row.parameters = {"radius": shape.radius, "half_segment": half_segment}
		_curve(row, pose, shape.radius, half_segment)
	else:
		result.errors.append({"id": id, "shape": shape.get_class() if shape != null else "missing"})
		return
	row.shape = shape.get_class()
	row.margin = shape.margin
	if not points.is_empty(): _polyhedron(row, pose, points, shape is ConcavePolygonShape3D)
	elif not row.has("footprints_xz"):
		result.errors.append({"id": id, "shape": row.shape, "reason": "no collision vertices"})
		return
	result.shapes.append(row)

static func _polyhedron(row: Dictionary, pose: Transform3D, points: PackedVector3Array, triangles: bool) -> void:
	var projected := PackedVector2Array()
	var low := INF
	var high := -INF
	for point in points:
		var world := pose * point
		projected.append(Vector2(world.x, world.z))
		low = minf(low, world.y)
		high = maxf(high, world.y)
	row.y_range = [low, high]
	row.footprints_xz = []
	if triangles:
		# A hull here would fill openings in concave/CSG geometry.
		for index in range(0, projected.size(), 3):
			row.footprints_xz.append(_xz(projected.slice(index, index + 3)))
	else:
		var hull := Geometry2D.convex_hull(projected)
		if hull.size() > 1 and hull[0] == hull[-1]: hull.resize(hull.size() - 1)
		row.footprints_xz.append(_xz(hull))

static func _xz(points: PackedVector2Array) -> Array:
	var result := []
	for p in points: result.append([p.x, p.y])
	return result

static func _curve(row: Dictionary, pose: Transform3D, radius: float, half_segment: float) -> void:
	# The exact XZ projection is the Minkowski sum of a projected segment and
	# projected sphere. Sample its support points for polygon-only consumers.
	var extent := absf(pose.basis.y.y) * half_segment + radius * pose.basis.transposed().y.length()
	row.y_range = [pose.origin.y - extent, pose.origin.y + extent]
	var sampled := PackedVector2Array()
	for index in CURVE_SAMPLES:
		var angle := TAU * index / CURVE_SAMPLES
		var direction := Vector3(cos(angle), 0.0, sin(angle))
		var normal := pose.basis.transposed() * direction
		var world := pose * (normal.normalized() * radius + Vector3.UP * signf(normal.y) * half_segment)
		sampled.append(Vector2(world.x, world.z))
	row.footprints_xz = [_xz(sampled)]
	row.curve_samples = CURVE_SAMPLES

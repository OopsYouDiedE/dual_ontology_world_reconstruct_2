extends RefCounted
## Test-only independent NavigationAgent3D probe for the real corridor stage.
## Visible static meshes are conservative AABB proxies, not production colliders;
## NPCs are circular exclusions using the production separation threshold. A
## passing result does not prove a real collision shape or macro camera exists.
const CELL := 0.2

var host: Control
var corridor: Node
var bounds: Rect2
var actor_min := 0.0
var actor_radius := 0.0
var obstacle_margin := 0.0
var obstacles: Array = []
var test_root: Node3D
var region: NavigationRegion3D
var agent_body: Node3D
var agent: NavigationAgent3D
var nav_map: RID
var free_cells := 0
var total_cells := 0
var errors: Array[String] = []

static func xyz(point: Vector3) -> Array:
	return [point.x, point.y, point.z]

static func xz_path(points: PackedVector3Array) -> Array:
	var output := []
	for point in points: output.append([point.x, point.z])
	return output

static func xz_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x, a.z).distance_to(Vector2(b.x, b.z))

func _inside(point: Vector2) -> bool:
	return point.x >= bounds.position.x and point.x <= bounds.end.x and point.y >= bounds.position.y and point.y <= bounds.end.y

func _is_stage_marker_or_character(mesh: MeshInstance3D) -> bool:
	for item in corridor._items:
		var marker = item.get("marker")
		if is_instance_valid(marker) and (marker == mesh or marker.is_ancestor_of(mesh)): return true
	for figure in corridor._npc.values():
		if is_instance_valid(figure) and (figure == mesh or figure.is_ancestor_of(mesh)): return true
	return false

func _world_bounds(mesh: MeshInstance3D) -> Dictionary:
	var box := mesh.get_aabb()
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for i in 8:
		var corner := box.position + Vector3(box.size.x if i & 1 else 0.0,
			box.size.y if i & 2 else 0.0, box.size.z if i & 4 else 0.0)
		var point := mesh.to_global(corner)
		low = Vector3(minf(low.x, point.x), minf(low.y, point.y), minf(low.z, point.z))
		high = Vector3(maxf(high.x, point.x), maxf(high.y, point.y), maxf(high.z, point.z))
	return {"low": low, "high": high}

func _collect_obstacles() -> void:
	# This is deliberately conservative and may over-report rotated/concave
	# objects. It never fabricates original CollisionShape3D nodes.
	for mesh: MeshInstance3D in corridor._root.find_children("*", "MeshInstance3D", true, false):
		if mesh.mesh == null or not mesh.is_visible_in_tree() or _is_stage_marker_or_character(mesh): continue
		var box := _world_bounds(mesh)
		var low: Vector3 = box.low
		var high: Vector3 = box.high
		if high.y <= 0.08 or low.y >= 1.7: continue # floor and overhead lights
		var rect := Rect2(Vector2(low.x, low.z), Vector2(high.x - low.x, high.z - low.z)).grow(obstacle_margin)
		if rect.intersects(bounds, true):
			# Grow a second time for grid-cell centre sampling: the entire cell,
			# not merely its centre, must lie outside the clearance rectangle.
			obstacles.append({"path": str(mesh.get_path()), "rect": rect,
				"cell_rect": rect.grow(CELL * 0.707107), "low": xyz(low), "high": xyz(high)})

func static_hits(point: Vector2) -> Array:
	var hits := []
	for obstacle in obstacles:
		if (obstacle.rect as Rect2).has_point(point): hits.append(obstacle.path)
	return hits

func _actor_distance(point: Vector2) -> float:
	var nearest := INF
	for figure in corridor._npc.values():
		if is_instance_valid(figure):
			nearest = minf(nearest, point.distance_to(Vector2(figure.global_position.x, figure.global_position.z)))
	return nearest

func _polygon_clear(point: Vector2) -> bool:
	# Expand exclusions by half a cell diagonal so every retained polygon stays
	# outside both the NPC clearance disk and the static proxy rectangles.
	for obstacle in obstacles:
		if (obstacle.cell_rect as Rect2).has_point(point): return false
	return _actor_distance(point) >= actor_min + CELL * 0.707107

func begin(h: Control, stage: Node, area: Rect2) -> void:
	host = h
	corridor = stage
	bounds = area
	actor_min = float(host.ACTOR_MIN_DISTANCE)
	actor_radius = float(host.ACTOR_RADIUS)
	obstacle_margin = maxf(float(host.ACTOR_FURNITURE_MARGIN), float(host.ACTOR_WALL_MARGIN))
	if not corridor._root.global_transform.is_equal_approx(Transform3D.IDENTITY):
		errors.append("corridor_stage_transform_not_identity")
		return
	_collect_obstacles()
	var vertices := PackedVector3Array()
	var corners := {}
	var polygons := []
	var nx := ceili(bounds.size.x / CELL)
	var nz := ceili(bounds.size.y / CELL)
	total_cells = nx * nz
	for x in nx:
		for z in nz:
			var x0 := bounds.position.x + minf(x * CELL, bounds.size.x)
			var x1 := bounds.position.x + minf((x + 1) * CELL, bounds.size.x)
			var z0 := bounds.position.y + minf(z * CELL, bounds.size.y)
			var z1 := bounds.position.y + minf((z + 1) * CELL, bounds.size.y)
			if not _polygon_clear(Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)): continue
			free_cells += 1
			var poly := PackedInt32Array()
			for key in [Vector2i(x, z), Vector2i(x, z + 1), Vector2i(x + 1, z + 1), Vector2i(x + 1, z)]:
				if not corners.has(key):
					corners[key] = vertices.size()
					vertices.append(Vector3(bounds.position.x + minf(key.x * CELL, bounds.size.x), 0.0,
						bounds.position.y + minf(key.y * CELL, bounds.size.y)))
				poly.append(corners[key])
			polygons.append(poly)
	if free_cells == 0:
		errors.append("corridor_navigation_has_no_free_cells")
		return
	var mesh := NavigationMesh.new()
	mesh.vertices = vertices
	for polygon in polygons:
		mesh.add_polygon(PackedInt32Array([polygon[0], polygon[1], polygon[2]]))
		mesh.add_polygon(PackedInt32Array([polygon[0], polygon[2], polygon[3]]))
	test_root = Node3D.new()
	test_root.name = "CorridorNavigationCheckOnly"
	host.det_root.get_parent().add_child(test_root)
	nav_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(nav_map, true)
	NavigationServer3D.map_set_cell_size(nav_map, CELL)
	region = NavigationRegion3D.new()
	test_root.add_child(region)
	region.navigation_mesh = mesh
	region.set_navigation_map(nav_map)
	agent_body = Node3D.new()
	test_root.add_child(agent_body)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.02
	agent.target_desired_distance = 0.02
	agent_body.add_child(agent)
	agent.set_navigation_map(nav_map)
	NavigationServer3D.map_force_update(nav_map)

func _segment_intersects_rect(a: Vector2, b: Vector2, rect: Rect2) -> bool:
	if rect.has_point(a) or rect.has_point(b): return true
	var corners := [rect.position, Vector2(rect.end.x, rect.position.y), rect.end,
		Vector2(rect.position.x, rect.end.y)]
	for index in 4:
		if Geometry2D.segment_intersects_segment(a, b, corners[index], corners[(index + 1) % 4]) != null:
			return true
	return false

func _path_clearance(points: PackedVector3Array) -> Dictionary:
	var nearest := INF
	var static_paths := {}
	for index in range(maxi(0, points.size() - 1)):
		var a := Vector2(points[index].x, points[index].z)
		var b := Vector2(points[index + 1].x, points[index + 1].z)
		for figure in corridor._npc.values():
			if not is_instance_valid(figure): continue
			var center := Vector2(figure.global_position.x, figure.global_position.z)
			var nearest_point := Geometry2D.get_closest_point_to_segment(center, a, b)
			nearest = minf(nearest, center.distance_to(nearest_point))
		for obstacle in obstacles:
			if _segment_intersects_rect(a, b, obstacle.rect): static_paths[obstacle.path] = true
	return {"minimum_npc_distance": null if is_inf(nearest) else nearest,
		"npc_clearance_pass": is_inf(nearest) or nearest + 0.001 >= actor_min,
		"static_proxy_hits": static_paths.keys(), "static_proxy_clearance_pass": static_paths.is_empty()}

func probe(start: Vector2, destination: Vector2) -> Dictionary:
	if not errors.is_empty() or not is_instance_valid(agent):
		return {"pass": false, "status": "navigation_setup_failed", "errors": errors}
	# A fresh custom map can publish iteration 1 before its region geometry is
	# ready. Fixed-FPS headless frames can outrun the asynchronous map build, so
	# wait a bounded *wall-clock* interval and fail closed if it never catches up.
	var wait_started := Time.get_ticks_usec()
	while NavigationServer3D.map_get_iteration_id(nav_map) < 2 and Time.get_ticks_usec() - wait_started < 1500000:
		await host.get_tree().physics_frame
		if NavigationServer3D.map_get_iteration_id(nav_map) < 2: OS.delay_msec(2)
	var map_iteration := NavigationServer3D.map_get_iteration_id(nav_map)
	if map_iteration < 2:
		return {"pass": false, "status": "navigation_map_not_synchronized", "map_iteration": map_iteration}
	var from := Vector3(start.x, 0.0, start.y)
	var to := Vector3(destination.x, 0.0, destination.y)
	agent_body.global_position = from
	agent.target_position = to
	await host.get_tree().physics_frame
	agent.get_next_path_position()
	var agent_path: PackedVector3Array = agent.get_current_navigation_path()
	var server_path := NavigationServer3D.map_get_path(nav_map, from, to, true)
	var nearest_start := NavigationServer3D.map_get_closest_point(nav_map, from)
	var nearest_end := NavigationServer3D.map_get_closest_point(nav_map, to)
	const TOL := 0.035
	var start_on_mesh := _inside(start) and xz_distance(nearest_start, from) < TOL
	var end_on_mesh := _inside(destination) and xz_distance(nearest_end, to) < TOL
	var agent_reaches := not agent_path.is_empty() and xz_distance(agent_path[agent_path.size() - 1], to) < TOL
	var server_reaches := not server_path.is_empty() and xz_distance(server_path[server_path.size() - 1], to) < TOL
	var clearance := _path_clearance(server_path)
	var agent_clearance := _path_clearance(agent_path)
	var ok: bool = start_on_mesh and end_on_mesh and agent_reaches and server_reaches \
		and clearance.npc_clearance_pass and clearance.static_proxy_clearance_pass \
		and agent_clearance.npc_clearance_pass and agent_clearance.static_proxy_clearance_pass
	return {"status": "checked", "pass": ok, "map_iteration": map_iteration,
		"start_on_mesh": start_on_mesh, "destination_on_mesh": end_on_mesh,
		"start": [start.x, start.y], "destination": [destination.x, destination.y],
		"bounds": {"position": [bounds.position.x, bounds.position.y], "end": [bounds.end.x, bounds.end.y]},
		"destination_mesh_distance": xz_distance(nearest_end, to),
		"agent_reaches_target": agent_reaches, "server_reaches_target": server_reaches,
		"agent_path": xz_path(agent_path), "navigation_path": xz_path(server_path),
		"nearest_start": xyz(nearest_start), "nearest_destination": xyz(nearest_end),
		"server_path_clearance": clearance, "agent_path_clearance": agent_clearance,
		"static_proxy_hits_at_destination": static_hits(destination)}

func summary() -> Dictionary:
	var items := []
	for obstacle in obstacles:
		items.append({"path": obstacle.path, "aabb_min": obstacle.low, "aabb_max": obstacle.high})
	return {"kind": "test_only_navigation_mesh_with_conservative_visible_aabbs",
		"free_cells": free_cells, "total_cells": total_cells, "cell_size": CELL,
		"actor_radius": actor_radius, "static_proxy_clearance_margin": obstacle_margin,
		"minimum_actor_separation": actor_min, "static_visual_proxies": items, "errors": errors,
		"limitation": "Visual AABBs are conservative; they are not original physics collision shapes."}

func cleanup() -> void:
	if is_instance_valid(region): region.set_navigation_map(RID())
	if is_instance_valid(agent): agent.set_navigation_map(RID())
	if is_instance_valid(test_root): test_root.queue_free()
	if nav_map.is_valid(): NavigationServer3D.free_rid(nav_map)

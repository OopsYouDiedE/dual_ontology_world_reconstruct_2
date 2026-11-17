extends RefCounted
## Direct fixture diagnostics. Physical ray proxies are attached only to this test host.
const Source := preload("res://mcp/CaptureSource.gd")
const RAY_LAYER := 1 << 19
const REQUIRED_TARGETS := {
	"opening": ["bed", "lamp", "desk", "window", "wardrobe", "wash", "door"],
	"kitchen": ["e_b_sleeve", "e_b_drag", "e_b_water", "e_b_cloth", "e_b_ratchet", "e_b_boots", "e_b_seal"],
}
var host: Control
var proxies: Array = []
var colliders := {}
var shape_cache := {}
var physics_root: Node3D
var agent: NavigationAgent3D
var agent_body: Node3D
var region: NavigationRegion3D
var nav_map: RID
var grid: AStarGrid2D
var started_usec := 0
var errors: Array[String] = []
var skinned_proxy_count := 0
var restored_state := {}
var exclusion_grids := {}
var navigation_wait_frames := 0

static func xyz(p: Vector3) -> Array: return [p.x,p.y,p.z]
static func xz(p: Vector2) -> Array: return [p.x,p.y]

static func grid_path(points: Array, cell_size: float) -> Array:
	var out := []
	for point: Vector2i in points:
		out.append([(point.x + 0.5) * cell_size, (point.y + 0.5) * cell_size])
	return out

static func nav_path(points: PackedVector3Array) -> Array:
	var out := []
	for point in points: out.append([point.x,point.z])
	return out

func begin(h: Control) -> void:
	host = h
	started_usec = Time.get_ticks_usec()
	grid = host._route_grid_with_figures() if host._grid != null else null
	physics_root = Node3D.new()
	physics_root.name = "RoomFastCheckProxies"
	host.det_root.get_parent().add_child(physics_root)
	if grid == null: errors.append("production_navigation_grid_missing")
	else: _navigation()
	for id in host.figures: exclusion_grids[str(id)] = _grid_without_figure(str(id))
	_make_proxies()

func _grid_without_figure(excluded: String) -> AStarGrid2D:
	var source: AStarGrid2D = host._grid
	var candidate := AStarGrid2D.new()
	candidate.region = source.region
	candidate.cell_size = source.cell_size
	candidate.diagonal_mode = source.diagonal_mode
	candidate.default_compute_heuristic = source.default_compute_heuristic
	candidate.default_estimate_heuristic = source.default_estimate_heuristic
	candidate.update()
	for x in source.region.size.x:
		for z in source.region.size.y:
			var cell := Vector2i(x,z)
			var solid := source.is_point_solid(cell)
			var center := Vector2((x+0.5)*host.CELL,(z+0.5)*host.CELL)
			for id in host.figures:
				if str(id) == excluded: continue
				var figure: Node3D = host.figures[id]
				if not is_instance_valid(figure): continue
				if center.distance_to(Vector2(figure.global_position.x,figure.global_position.z)) < host.ACTOR_MIN_DISTANCE: solid = true
			candidate.set_point_solid(cell,solid)
	return candidate

func _route_probe(source: AStarGrid2D, start: Vector2, requested: Vector2) -> Dictionary:
	var a: Vector2i = host._nearest_free(host._cell_of(start),source)
	var b: Vector2i = host._nearest_free(host._cell_of(requested),source)
	var points := source.get_id_path(a,b)
	return {"reachable":not points.is_empty(),"cells":points.size(),"start_cell":[a.x,a.y],"end_cell":[b.x,b.y],"end_center":[(b.x+0.5)*host.CELL,(b.y+0.5)*host.CELL]}

func _nearby_stands(source: AStarGrid2D, start: Vector2, target: Vector2) -> Dictionary:
	var start_cell: Vector2i = host._nearest_free(host._cell_of(start),source)
	var available := []
	var reachable := []
	for x in source.region.size.x:
		for z in source.region.size.y:
			var cell := Vector2i(x,z)
			var point := Vector2((x+0.5)*host.CELL,(z+0.5)*host.CELL)
			if point.distance_to(target)>_interaction_radius() or source.is_point_solid(cell): continue
			available.append(xz(point))
			if not source.get_id_path(start_cell,cell).is_empty(): reachable.append(xz(point))
	return {"interaction_radius":_interaction_radius(),"free_center_count":available.size(),"reachable_center_count":reachable.size(),"free_center_sample":available.slice(0,4),"reachable_center_sample":reachable.slice(0,4)}

func _interaction_radius() -> float:
	# E uses NEAR. interact() uses 1.3m only to decide whether walking is needed;
	# arrival callbacks have no additional 1.3m rejection.
	return float(host.kitchen.NEAR) if is_instance_valid(host.kitchen) and host.kitchen.active else 1.5

func _path_explanation(start: Vector2, requested: Vector2, interaction: Vector2) -> Dictionary:
	var excluded := {}
	for id in exclusion_grids:
		excluded[id] = _route_probe(exclusion_grids[id],start,requested)
		excluded[id]["interaction_stands"] = _nearby_stands(exclusion_grids[id],start,interaction)
	return {"static_furniture_grid":_route_probe(host._grid,start,requested),"with_all_figures":_route_probe(grid,start,requested),"interaction_stands":_nearby_stands(grid,start,interaction),"figure_exclusion_probes":excluded,
		"probe_semantics":"diagnostic_grid_only_original_actors_unchanged; reachable refers to returned stand, which may be a rejected-plan fallback, not necessarily the interaction"}

func _navigation() -> void:
	var mesh := NavigationMesh.new()
	var points := PackedVector3Array()
	var corners := {}
	var polygons := []
	for x in range(grid.region.position.x,grid.region.end.x):
		for z in range(grid.region.position.y,grid.region.end.y):
			if grid.is_point_solid(Vector2i(x,z)): continue
			var poly := PackedInt32Array()
			for key in [Vector2i(x,z),Vector2i(x,z+1),Vector2i(x+1,z+1),Vector2i(x+1,z)]:
				if not corners.has(key):
					corners[key] = points.size()
					points.append(Vector3(key.x*host.CELL,0.0,key.y*host.CELL))
				poly.append(corners[key])
			polygons.append(poly)
	mesh.vertices = points
	for poly in polygons:
		mesh.add_polygon(PackedInt32Array([poly[0],poly[1],poly[2]]))
		mesh.add_polygon(PackedInt32Array([poly[0],poly[2],poly[3]]))
	region = NavigationRegion3D.new()
	physics_root.add_child(region)
	region.navigation_mesh = mesh
	agent_body = Node3D.new()
	physics_root.add_child(agent_body)
	agent = NavigationAgent3D.new()
	agent.path_desired_distance = 0.02
	agent.target_desired_distance = 0.02
	agent_body.add_child(agent)
	nav_map = host.cam.get_world_3d().navigation_map
	NavigationServer3D.map_force_update(nav_map)

## The map iteration counter can already be nonzero before this new region's
## polygons are published. Check ownership and an actual free-cell projection,
## not just the counter, before measuring paths.
func navigation_readiness() -> Dictionary:
	var result := {"ready":false, "reason":"navigation_objects_missing", "iteration":0,
		"probe":[], "nearest":[], "owner_matches_region":false}
	if grid == null or not is_instance_valid(region) or not nav_map.is_valid(): return result
	result.iteration = NavigationServer3D.map_get_iteration_id(nav_map)
	if not NavigationServer3D.map_is_active(nav_map) or NavigationServer3D.region_get_map(region.get_region_rid()) != nav_map:
		result.reason = "navigation_region_not_on_active_map"
		return result
	if region.navigation_mesh == null or region.navigation_mesh.get_polygon_count() == 0:
		result.reason = "navigation_mesh_empty"
		return result
	if int(result.iteration) < 2:
		result.reason = "navigation_map_not_synchronized"
		return result
	var point := Vector3.INF
	for x in range(grid.region.position.x, grid.region.end.x):
		for z in range(grid.region.position.y, grid.region.end.y):
			if not grid.is_point_solid(Vector2i(x,z)):
				point = Vector3((x+0.5)*host.CELL, 0.0, (z+0.5)*host.CELL)
				break
		if point != Vector3.INF: break
	if point == Vector3.INF:
		result.reason = "no_free_navigation_cells"
		return result
	var nearest := NavigationServer3D.map_get_closest_point(nav_map, point)
	var owner := NavigationServer3D.map_get_closest_point_owner(nav_map, point)
	result.probe = xyz(point)
	result.nearest = xyz(nearest)
	result.owner_matches_region = owner == region.get_region_rid()
	result.ready = bool(result.owner_matches_region) and nearest.distance_to(point) < 0.03
	result.reason = "ready" if result.ready else "navigation_mesh_not_published"
	return result

func _make_proxies() -> void:
	var meshes: Array = host.room_vp.find_children("*","MeshInstance3D",true,false)
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null: continue
		var path := str(mesh.get_path())
		if "Markers/" in path or "/Marker/" in path or "/EvidenceMarker" in path: continue
		var key := mesh.mesh.get_rid().get_id()
		if not shape_cache.has(key): shape_cache[key] = mesh.mesh.create_trimesh_shape()
		var shape: Shape3D = shape_cache[key]
		if shape == null: continue
		if shape is ConcavePolygonShape3D: shape.backface_collision = true
		var body := StaticBody3D.new()
		body.collision_layer = RAY_LAYER if mesh.is_visible_in_tree() else 0
		body.collision_mask = 0
		physics_root.add_child(body)
		body.global_transform = mesh.global_transform
		var collider := CollisionShape3D.new()
		collider.shape = shape
		body.add_child(collider)
		var skinned := mesh.get_node_or_null(mesh.skeleton) is Skeleton3D and mesh.skin != null
		if skinned: skinned_proxy_count += 1
		proxies.append({"mesh":mesh,"body":body,"shape":collider,"skinned":skinned})
		colliders[body.get_instance_id()] = mesh

func _sync_proxies() -> void:
	for proxy in proxies:
		proxy.body.global_transform = proxy.mesh.global_transform
		proxy.body.collision_layer = RAY_LAYER if proxy.mesh.is_visible_in_tree() else 0
		if proxy.skinned and proxy.mesh.is_visible_in_tree():
			proxy.shape.shape = _skin_shape(proxy.mesh)

# Headless rendering has no registered GPU skin. Apply the live skeleton's
# matrices to the original indexed triangles on the CPU, preserving ray geometry.
func _skin_shape(mesh: MeshInstance3D) -> ConcavePolygonShape3D:
	var skeleton: Skeleton3D = mesh.get_node(mesh.skeleton)
	var skin: Skin = mesh.skin
	var transforms: Array[Transform3D] = []
	var signature := []
	var mesh_from_skeleton := mesh.global_transform.affine_inverse()*skeleton.global_transform
	for bind in skin.get_bind_count():
		var bone := skin.get_bind_bone(bind)
		if bone < 0: bone = skeleton.find_bone(skin.get_bind_name(bind))
		var transform := mesh_from_skeleton*skeleton.get_bone_global_pose(bone)*skin.get_bind_pose(bind)
		transforms.append(transform)
		signature.append(transform)
	var key := str(mesh.get_instance_id())+":"+str(hash(signature))
	if shape_cache.has(key): return shape_cache[key]
	var faces := PackedVector3Array()
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var deformed := PackedVector3Array()
		deformed.resize(vertices.size())
		var influences := bones.size()/vertices.size()
		for index in vertices.size():
			var position := Vector3.ZERO
			for influence in influences:
				var at := index*influences+influence
				if weights[at] > 0.0: position += (transforms[bones[at]]*vertices[index])*weights[at]
			deformed[index] = position
		if indices.is_empty(): faces.append_array(deformed)
		else:
			for index in indices: faces.append(deformed[index])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	shape_cache[key] = shape
	return shape

func _entry() -> Dictionary:
	var from := "R05" if str(host.eng.s.room) == "B-P" else "B-P"
	var passage: Dictionary = host._door_for(host.room_mesh.design,host._room_dir(str(host.eng.s.room),from))
	if passage.has("inner"):
		return {"position":passage.inner,"source":"production_door_inner"}
	return {"position":host.det_pos,"source":"detective_fallback"}

func _actors(spawn: Vector2) -> Dictionary:
	var positions := {"detective":host.det_pos}
	for id in host.figures:
		var figure: Node3D = host.figures[id]
		if is_instance_valid(figure) and figure.is_visible_in_tree(): positions[str(id)] = Vector2(figure.global_position.x,figure.global_position.z)
	var pairs := []
	var ids := positions.keys()
	var clear := true
	for i in ids.size():
		for j in range(i+1,ids.size()):
			var distance: float = positions[ids[i]].distance_to(positions[ids[j]])
			var pass_pair: bool = distance >= host.ACTOR_MIN_DISTANCE
			if not pass_pair: clear = false
			pairs.append({"a":ids[i],"b":ids[j],"distance":distance,"minimum":host.ACTOR_MIN_DISTANCE,"pass":pass_pair})
	var spawn_pairs := []
	var spawn_clear := true
	for id in positions:
		if id == "detective": continue
		var distance: float = spawn.distance_to(positions[id])
		var pass_pair: bool = distance >= host.ACTOR_MIN_DISTANCE
		if not pass_pair: spawn_clear = false
		spawn_pairs.append({"a":"spawn","b":id,"distance":distance,"minimum":host.ACTOR_MIN_DISTANCE,"pass":pass_pair})
	var occupied: bool = host._det_can_occupy(host.det_pos)
	var spawn_occupied: bool = host._det_can_occupy(spawn)
	var phase := str(host.opening.phase) if is_instance_valid(host.opening) and host.opening.active else ""
	var bed: Dictionary = host._bed_info() if not phase.is_empty() else {}
	var bed_performance: bool = phase in ["black","fade","lie","sit","look","talk","getup"] and host._cine and not bed.is_empty() and host.det_pos.distance_to(bed.pos) < 0.1 and str(host.det.pose).begins_with("lie")
	var occupancy_pass: bool = occupied or bed_performance
	var encoded_positions := {}
	for id in positions: encoded_positions[id] = xz(positions[id])
	return {"positions":encoded_positions,"detective_position":xz(host.det_pos),"detective_occupiable":occupied,
		"detective_pose":str(host.det.pose),"opening_phase":phase,"occupancy_context":"opening_bed_performance" if bed_performance else "exploration_landing","walking_occupancy_required":not bed_performance,"occupancy_pass":occupancy_pass,
		"snapshot_pairwise_clear":clear,"snapshot_pairs":pairs,"spawn_position":xz(spawn),
		"spawn_occupiable":spawn_occupied,"spawn_pairwise_clear":spawn_clear,"spawn_pairs":spawn_pairs,
		"pass":occupancy_pass and clear and spawn_occupied and spawn_clear}

func _items() -> Array:
	if is_instance_valid(host.opening) and host.opening.active: return host.opening._items
	if is_instance_valid(host.kitchen) and host.kitchen.active: return host.kitchen._items
	if is_instance_valid(host.gathering) and host.gathering.active: return host.gathering._items
	return []

func _stand(item: Dictionary, start: Vector2) -> Dictionary:
	var raw = item.get("pos",Vector2.ZERO)
	var point := Vector2(raw.x,raw.z) if raw is Vector3 else Vector2(raw)
	if is_instance_valid(host.kitchen) and host.kitchen.active:
		var kind: String = host.interactions.kind_for(str(item.id))
		var approach := preload("res://scenes/components/interaction/InteractionApproach.gd").plan(host, point, kind, start)
		return {"point":point,"desired":approach.stand,"cell":host._cell_of(approach.stand),"stand":approach.stand,
			"already_near":approach.already_near,"approach_ok":approach.ok,
			"approach_reason":str(approach.get("reason", "")),"planned_path":approach.path}
	if start.distance_to(point) <= 1.3:
		return {"point":point,"desired":start,"cell":host._cell_of(start),"stand":start,"already_near":true}
	var stand: Vector2
	if item.has("stand"):
		stand = item.stand
	else:
		var away := (start-point).normalized()
		stand = point+away*(0.7 if str(host.eng.s.room) == "B-P" else 0.8)
	var desired: Vector2i = host._cell_of(stand)
	var resolved: Vector2i = host._nearest_free(desired)
	var grid_stand := Vector2((resolved.x+0.5)*host.CELL,(resolved.y+0.5)*host.CELL)
	return {"point":point,"desired":stand,"cell":resolved,"stand":grid_stand,"already_near":false}

static func production_plan_path(plan: Dictionary, start: Vector2, fallback_route: Callable) -> Array:
	if not bool(plan.get("approach_ok", true)): return []
	if bool(plan.get("already_near", false)): return [start]
	if plan.has("planned_path"): return plan.planned_path
	return fallback_route.call(start, plan.stand)

static func navigation_target_claim(reaches_returned_stand: bool, approach_ok: bool) -> bool:
	return reaches_returned_stand and approach_ok

## Do not let an empty, incomplete, duplicated or unsupported item list pass
## vacuously. Corridor and other rooms need their own explicitly scoped checker.
static func target_coverage(controller: String, items: Array) -> Dictionary:
	var expected: Array = REQUIRED_TARGETS.get(controller, [])
	var seen := []
	var duplicates := []
	var unexpected := []
	for value in items:
		if not value is Dictionary or not value.has("id"):
			unexpected.append("<invalid>")
			continue
		var id := str(value.id)
		if seen.has(id): duplicates.append(id)
		else: seen.append(id)
		if not expected.has(id): unexpected.append(id)
	var missing := []
	for id in expected:
		if not seen.has(id): missing.append(id)
	return {"controller":controller,"supported":REQUIRED_TARGETS.has(controller),
		"expected":expected,"observed":seen,"missing":missing,"duplicates":duplicates,"unexpected":unexpected,
		"complete":REQUIRED_TARGETS.has(controller) and not expected.is_empty() and missing.is_empty() and duplicates.is_empty() and unexpected.is_empty()}

static func ray_claim(ray: Dictionary, required: bool) -> bool:
	return bool(ray.get("pass", false)) and (not required or bool(ray.get("applicable", false)))

func _target_kind(id: String) -> String:
	if host.evidence_presentations.has(id): return id
	return host.interactions.kind_for(id)

func _target_mesh(prop: Node3D) -> Dictionary:
	var selection: Node = prop
	# Observation wrappers are children of the original furniture.
	if str(prop.name).begins_with("RoomObservation_"): selection = prop.get_parent()
	var focus: Vector3 = prop.to_global(prop.get_meta("focus",Vector3.ZERO))
	if prop.has_meta("inspection_target"):
		var explicit := prop.get_node_or_null(NodePath(prop.get_meta("inspection_target"))) as MeshInstance3D
		return {"mesh":explicit,"root":explicit,"focus":focus}
	var best: MeshInstance3D
	var distance := INF
	for proxy in proxies:
		var mesh: MeshInstance3D = proxy.mesh
		if not mesh.is_visible_in_tree() or not (selection == mesh or selection.is_ancestor_of(mesh)): continue
		var center := mesh.to_global(mesh.get_aabb().get_center())
		var d := center.distance_to(focus)
		if d < distance:
			distance = d
			best = mesh
	return {"mesh":best,"root":selection,"focus":focus}

func _hit_category(mesh: MeshInstance3D, target_root: Node) -> String:
	if not is_instance_valid(mesh): return "none"
	if mesh == target_root or target_root.is_ancestor_of(mesh): return "target"
	if mesh == host.det_root or host.det_root.is_ancestor_of(mesh): return "detective"
	if mesh == host.figures_root or host.figures_root.is_ancestor_of(mesh): return "character"
	var path := str(mesh.get_path()).to_lower()
	if "door" in path or "jamb" in path or "hinge" in path: return "door"
	if "wall" in path or "architecture" in path: return "wall"
	return "furniture"

func inspect_ray(id: String, stand: Vector2) -> Dictionary:
	var ray_started := Time.get_ticks_usec()
	var kind := _target_kind(id)
	if kind.is_empty() or not host.evidence_presentations.has(kind): return {"status":"not_applicable","kind":kind,"applicable":false,"pass":true}
	if is_instance_valid(host.interactions.active): host.interactions.finish(false)
	# Use the same standing pose and facing direction as the production arrival.
	host.det_pos = stand
	host.det.position = Vector3(stand.x,0.0,stand.y)
	var prop: Node3D = host.evidence_presentations[kind]
	var target_position := Vector2(prop.global_position.x,prop.global_position.z)
	var facing := target_position-stand
	if facing.length() > 0.05: host.det.rotation.y = atan2(facing.x,facing.y)
	host.det.set_pose("stand")
	for player: AnimationPlayer in host.det.find_children("*","AnimationPlayer",true,false):
		player.advance(0.0)
		player.pause()
	if not host.interactions.begin_gameplay(host,kind): return {"status":"closeup_start_failed","kind":kind,"applicable":true,"pass":false}
	var closeup: Control = host.interactions.active
	if closeup._tween != null: closeup._tween.kill()
	var selected := _target_mesh(prop)
	var target: MeshInstance3D = selected.mesh
	if not is_instance_valid(target):
		host.interactions.finish(false)
		return {"status":"visible_geometry_missing","kind":kind,"prop_path":str(prop.get_path()),"applicable":true,"pass":false}
	var focus: Vector3 = selected.focus
	var camera: Camera3D = host.cam
	camera.global_transform = Transform3D(Basis.IDENTITY,closeup._inspection_position(focus)).looking_at(focus,Vector3.UP)
	camera.fov = float(prop.get_meta("camera_fov",48.0))
	_sync_proxies()
	await host.get_tree().physics_frame
	var origin := camera.global_position
	var center := target.to_global(target.get_aabb().get_center())
	# Continue beyond the AABB center so thin/concave target meshes still expose their
	# front surface while preserving the exact camera-to-center sight line.
	var ray_end := center + (center-origin).normalized() * 0.5
	var query := PhysicsRayQueryParameters3D.create(origin,ray_end,RAY_LAYER)
	query.hit_back_faces = true
	query.hit_from_inside = true
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	var collider = hit.get("collider")
	var mesh: MeshInstance3D = colliders.get(collider.get_instance_id()) if is_instance_valid(collider) else null
	var target_root: Node = selected.root
	var hit_target := is_instance_valid(mesh) and (mesh == target_root or target_root.is_ancestor_of(mesh))
	var result := {"status":"hit" if is_instance_valid(mesh) else "no_hit","kind":kind,
		"applicable":true,
		"camera_path":str(camera.get_path()),"camera_position":xyz(origin),"target_path":str(target.get_path()),
		"target_aabb_center":xyz(center),"target_root":str(target_root.get_path()),
		"first_hit_path":str(mesh.get_path()) if is_instance_valid(mesh) else "",
		"first_hit_category":_hit_category(mesh,target_root),
		"first_hit_position":xyz(hit.position) if hit.has("position") else [],
		"standing_position":xz(stand),"elapsed_ms":(Time.get_ticks_usec()-ray_started)/1000.0,"pass":hit_target}
	host.interactions.finish(false)
	return result

func run() -> Dictionary:
	var controller := "opening" if is_instance_valid(host.opening) and host.opening.active else ("kitchen" if is_instance_valid(host.kitchen) and host.kitchen.active else "other")
	var items := _items()
	var coverage := target_coverage(controller, items)
	if not coverage.complete:
		return {"format":"room-fast-check-v1", "status":"blocked", "pass":false,
			"project":Source.identity(host.get_tree(), "res://scenes/dual_world/DualWorldMain.tscn"),
			"room":str(host._room_loaded), "engine_room":str(host.eng.s.room), "controller":controller,
			"target_coverage":coverage, "interactions":[], "errors":[],
			"blocking_reasons":["目标房间交互清单缺失、重复或不受此快检支持"]}
	var ready := navigation_readiness()
	if not ready.ready:
		return {"format":"room-fast-check-v1", "status":"blocked", "pass":false,
			"project":Source.identity(host.get_tree(), "res://scenes/dual_world/DualWorldMain.tscn"),
			"room":str(host._room_loaded), "engine_room":str(host.eng.s.room), "controller":controller,
			"target_coverage":coverage, "navigation_readiness":ready, "navigation_wait_frames":navigation_wait_frames,
			"interactions":[], "errors":[], "blocking_reasons":["导航网格尚未发布到当前房间地图"]}
	var entry := _entry()
	var start: Vector2 = entry.position
	var actors := _actors(start)
	var saved_detective_position: Vector2 = host.det_pos
	var saved_detective_transform: Transform3D = host.det.transform
	var saved_camera_transform: Transform3D = host.cam.global_transform
	var results := []
	var paths_ok := true
	var rays_ok := true
	if grid == null: return {"status":"error","errors":errors}
	var start_cell: Vector2i = host._cell_of(start)
	var start_valid := not grid.is_point_solid(start_cell)
	var from := Vector3(start.x,0,start.y)
	var nearest_start: Vector3 = NavigationServer3D.map_get_closest_point(nav_map,from)
	agent_body.global_position = from
	for item in items:
		var stand := _stand(item,start)
		var requested: Vector2 = stand.stand
		var approach_ok: bool = bool(stand.get("approach_ok", true))
		# Kitchen's real click handler executes the plan's returned path, not a
		# second _route() to the fallback stand. Preserve an empty rejected plan.
		var production := production_plan_path(stand, start, Callable(host, "_route"))
		var end: Vector2 = production.back() if not production.is_empty() else start
		var end_cell: Vector2i = host._cell_of(end)
		var pass_goal: bool = not grid.is_point_solid(end_cell) and host._det_can_occupy(end)
		var astar: Array = grid.get_id_path(start_cell,end_cell) if start_valid and pass_goal else []
		var dest := Vector3(end.x,0,end.y)
		agent.target_position = dest
		await host.get_tree().physics_frame
		agent.get_next_path_position()
		var agent_path: PackedVector3Array = agent.get_current_navigation_path()
		var server_path := NavigationServer3D.map_get_path(nav_map,from,dest,true)
		var nearest_end: Vector3 = NavigationServer3D.map_get_closest_point(nav_map,dest)
		var raw_nav_ok := not server_path.is_empty() and nearest_start.distance_to(from)<0.03 and nearest_end.distance_to(dest)<0.03 and server_path[server_path.size()-1].distance_to(dest)<0.03
		var raw_agent_ok := not agent_path.is_empty() and agent_path[agent_path.size()-1].distance_to(dest)<0.03
		var nav_ok := navigation_target_claim(raw_nav_ok, approach_ok)
		var agent_ok := navigation_target_claim(raw_agent_ok, approach_ok)
		var arrival_near: bool = end.distance_to(stand.point) <= _interaction_radius()
		var path_ok: bool = approach_ok and start_valid and pass_goal and not production.is_empty() and not astar.is_empty() and nav_ok and agent_ok and arrival_near
		if not path_ok: paths_ok = false
		var ray: Dictionary = await inspect_ray(str(item.id),end)
		ray["context"] = "forced_visual_probe_from_fallback_not_a_completed_interaction" if not approach_ok else "visual_probe_after_planned_approach"
		# The bedroom door is an exit rather than an evidence close-up. Every
		# other listed target requires a real original-scene ray, not an implicit
		# pass from a missing presentation or an unknown kind.
		var ray_required := not (controller == "opening" and str(item.id) == "door")
		if not ray_claim(ray, ray_required): rays_ok = false
		var snapshot_stand := _stand(item,saved_detective_position)
		var snapshot_approach_ok: bool = bool(snapshot_stand.get("approach_ok", true))
		var snapshot_route := production_plan_path(snapshot_stand, saved_detective_position, Callable(host, "_route"))
		var snapshot_end: Vector2 = snapshot_route.back() if not snapshot_route.is_empty() else saved_detective_position
		var snapshot_ray: Dictionary = await inspect_ray(str(item.id),snapshot_end)
		snapshot_ray["context"] = "forced_visual_probe_from_fallback_not_a_completed_interaction" if not snapshot_approach_ok else "visual_probe_after_planned_approach"
		if not ray_claim(snapshot_ray, ray_required): rays_ok = false
		results.append({"id":str(item.id),"ray_required":ray_required,"interaction_position":xz(stand.point),"requested_stand":xz(stand.desired),
			"resolved_stand":xz(requested),"actual_stand":xz(end),"stand_occupiable":pass_goal,"astar_cells":astar.size(),
			"approach_plan_ok":approach_ok,"approach_failure_reason":str(stand.get("approach_reason", "")),
			"returned_stand_is_rejection_fallback":not approach_ok,
			"arrival_distance":end.distance_to(stand.point),"arrival_within_interaction_range":arrival_near,
			"interaction_radius":_interaction_radius(),"skip_approach_radius":1.3,"arrival_within_skip_approach_radius":end.distance_to(stand.point)<=1.3,
			"navigation_agent_points":agent_path.size(),"navigation_server_points":server_path.size(),
			"production_path":production.map(func(point: Vector2): return xz(point)),"astar_path":grid_path(astar,host.CELL),"navigation_path":nav_path(server_path),
			"navigation_agent_reaches_returned_stand":raw_agent_ok,"navigation_server_reaches_returned_stand":raw_nav_ok,
			"navigation_agent_reaches_target":agent_ok,"navigation_reaches_target":nav_ok,"path_pass":path_ok,"ray":ray,
			"path_explanation":_path_explanation(start,requested,stand.point),
			"snapshot_interaction":{"already_near":snapshot_stand.already_near,"approach_plan_ok":snapshot_approach_ok,
				"approach_failure_reason":str(snapshot_stand.get("approach_reason", "")),"actual_stand":xz(snapshot_end),
				"arrival_distance":snapshot_end.distance_to(stand.point),"path":snapshot_route.map(func(point: Vector2): return xz(point)),"ray":snapshot_ray}})
	host.det_pos = saved_detective_position
	host.det.transform = saved_detective_transform
	host.cam.global_transform = saved_camera_transform
	var elapsed := (Time.get_ticks_usec()-started_usec)/1000.0
	return {"format":"room-fast-check-v1","purpose":"runtime_geometry_diagnostic","project":Source.identity(host.get_tree(),"res://scenes/dual_world/DualWorldMain.tscn"),"launch_arguments":OS.get_cmdline_args(),"snapshot":str(host.checkpoints.argument("--dv-snapshot")),
		"restored_state":restored_state,"room_checks_context":"prospective_exploration_geometry" if actors.occupancy_context == "opening_bed_performance" else "free_exploration_geometry",
		"source_sha256":{"checker":FileAccess.get_sha256("res://scenes/components/testing/RoomFastCheck.gd"),"main":FileAccess.get_sha256("res://scenes/dual_world/DualWorldMain.gd"),"closeup":FileAccess.get_sha256("res://scenes/components/interaction/InRoomEvidenceCloseup.gd"),"snapshot":FileAccess.get_sha256(str(host.checkpoints.argument("--dv-snapshot")))},
		"room":str(host.eng.s.room),"controller":controller,"target_coverage":coverage,
		"navigation_readiness":ready,"navigation_wait_frames":navigation_wait_frames,
		"entry":{"position":xz(start),"source":entry.source,"cell_open":start_valid},"actors":actors,
		"proxies":proxies.size(),"skinned_pose_proxies":skinned_proxy_count,"navigation_mesh_cells":grid.region.size.x*grid.region.size.y,"navigation_diagnostics":{"region_valid":region.get_region_rid().is_valid(),"region_map_valid":NavigationServer3D.region_get_map(region.get_region_rid()).is_valid(),"region_map_equal":NavigationServer3D.region_get_map(region.get_region_rid()) == nav_map,"map_active":NavigationServer3D.map_is_active(nav_map),"map_iteration":NavigationServer3D.map_get_iteration_id(nav_map),"region_enabled":region.enabled,"nav_map_valid":nav_map.is_valid(),"regions":NavigationServer3D.map_get_regions(nav_map).size(),"polygons":region.navigation_mesh.get_polygon_count(),"vertices":region.navigation_mesh.vertices.size(),"nearest_start":xyz(nearest_start)},"interactions":results,
		"path_pass":paths_ok,"ray_pass":rays_ok,"elapsed_ms":elapsed,"under_5_seconds":elapsed<5000.0,
		"pass":paths_ok and rays_ok and actors.pass and elapsed<5000.0,"errors":errors}

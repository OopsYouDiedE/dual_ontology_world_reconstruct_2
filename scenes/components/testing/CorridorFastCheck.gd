extends RefCounted
## Diagnostic for the corridor's dedicated production stage/controller.
## Its movement is NOT the R05 room grid. Missing navigation/occlusion coverage
## blocks the formal room gate; this file never changes the game's implementation.
const Source := preload("res://mcp/CaptureSource.gd")
const NavigationCheck := preload("res://scenes/components/testing/CorridorNavigationCheck.gd")
const RayCheck := preload("res://scenes/components/testing/CorridorRayCheck.gd")
const STEP := 1.0 / 30.0
const MAX_STEPS := 600

var host: Control
var corridor: Node
var bounds: Rect2
var actor_min := 0.0

static func xy(value: Vector2) -> Array:
	return [value.x, value.y]

func _inside(value: Vector2) -> bool:
	const EPS := 0.001
	return value.x >= bounds.position.x - EPS and value.x <= bounds.end.x + EPS and value.y >= bounds.position.y - EPS and value.y <= bounds.end.y + EPS

func _actor_distance(value: Vector2) -> float:
	var nearest := INF
	for id in corridor._npc:
		var npc: Node3D = corridor._npc[id]
		if is_instance_valid(npc):
			nearest = minf(nearest, value.distance_to(Vector2(npc.position.x, npc.position.z)))
	return nearest

func _simulate(start: Vector2, index: int) -> Dictionary:
	# Match CorridorGathering's own click-to-walk helper and NPC push-out at a
	# documented fixed timestep. This is a fast diagnostic, not player footage.
	var target: Vector2 = corridor._item_pos(index)
	var stand: Vector2 = corridor._item_stand(index)
	host.det_pos = start
	host.det.position = Vector3(start.x, 0.0, start.y)
	var path: Array = [xy(start)]
	var in_bounds := _inside(start)
	var min_distance := _actor_distance(start)
	var stuck := 0
	var steps := 0
	while host.det_pos.distance_to(stand) > 0.12 and steps < MAX_STEPS:
		var before: Vector2 = host.det_pos
		corridor._walk_to(stand, STEP)
		host.det_pos = corridor._push_out(host.det_pos, before)
		host.det.position = Vector3(host.det_pos.x, 0.0, host.det_pos.y)
		steps += 1
		if steps % 10 == 0: path.append(xy(host.det_pos))
		in_bounds = in_bounds and _inside(host.det_pos)
		min_distance = minf(min_distance, _actor_distance(host.det_pos))
		if before.distance_to(host.det_pos) < 0.0001: stuck += 1
		else: stuck = 0
		if stuck >= 10: break
	path.append(xy(host.det_pos))
	var reached: bool = host.det_pos.distance_to(stand) <= 0.12
	var actors_clear: bool = is_inf(min_distance) or min_distance + 0.001 >= actor_min
	return {"target": xy(target), "stand": xy(stand), "end": xy(host.det_pos),
		"distance_to_stand": host.det_pos.distance_to(stand), "distance_to_item": host.det_pos.distance_to(target),
		"within_manual_e_radius": host.det_pos.distance_to(target) <= 1.6,
		"steps": steps, "step_seconds": STEP, "sampled_path": path,
		"bounds_pass": in_bounds, "actor_clearance_pass": actors_clear,
		"min_actor_distance": null if is_inf(min_distance) else min_distance,
		"reached": reached, "pass": reached and in_bounds and actors_clear}

func _separation_probes(previous: Vector2) -> Dictionary:
	# Exercise boundary and overlapping-neighbour corrections in the production
	# movement helper, using a known-clear entry point as the fallback.
	var candidates := [bounds.position - Vector2.ONE, bounds.end + Vector2.ONE]
	var positions: Array[Vector2] = []
	for npc in corridor._npc.values():
		if is_instance_valid(npc):
			var point := Vector2(npc.position.x, npc.position.z)
			positions.append(point)
			candidates.append(point)
	for i in range(positions.size() - 1):
		candidates.append((positions[i] + positions[i + 1]) * 0.5)
	var results := []
	var passed := _inside(previous) and _actor_distance(previous) + 0.001 >= actor_min
	for candidate: Vector2 in candidates:
		var corrected: Vector2 = corridor._push_out(candidate, previous)
		var clear := _inside(corrected) and _actor_distance(corrected) + 0.001 >= actor_min
		results.append({"candidate": xy(candidate), "corrected": xy(corrected), "pass": clear})
		passed = passed and clear
	return {"pass": passed, "samples": results}

func run(h: Control, restored: Dictionary) -> Dictionary:
	host = h
	corridor = host.gathering
	bounds = corridor.FREE_BOUNDS
	actor_min = float(host.ACTOR_MIN_DISTANCE)
	var entry := Vector2(float(corridor.DOORS[0][2]), 1.95) # controller's post-exit waypoint
	var separation := _separation_probes(entry)
	var saved_position: Vector2 = host.det_pos
	var saved_transform: Transform3D = host.det.transform
	var saved_pose := str(host.det.pose)
	var results := []
	var all_paths: bool = not corridor._items.is_empty()
	var all_navigation: bool = not corridor._items.is_empty()
	var ray_checked := 0
	var ray_passed := 0
	var ray_failed := 0
	var ray_unresolved := 0
	var navigation := NavigationCheck.new()
	navigation.begin(host, corridor, bounds)
	var rays := RayCheck.new()
	rays.begin(host, corridor)
	for index in corridor._items.size():
		var item: Dictionary = corridor._items[index]
		var movement := _simulate(entry, index)
		var stand: Vector2 = corridor._item_stand(index)
		var independent: Dictionary = await navigation.probe(entry, stand)
		var end := Vector2(float(movement.end[0]), float(movement.end[1]))
		var ray: Dictionary = await rays.probe(index, end)
		# Restore the checkpoint actor before testing its original camera. These
		# long-range observations are diagnostic; occlusion from a distant spawn
		# is not the interaction-stand ray verdict.
		host.det_pos = saved_position
		host.det.transform = saved_transform
		host.det.set_pose(saved_pose)
		var snapshot_ray: Dictionary = await rays.probe(index, saved_position, true)
		if not bool(movement.pass): all_paths = false
		if not bool(independent.pass): all_navigation = false
		if bool(ray.get("applicable", false)):
			ray_checked += 1
			if bool(ray.get("pass", false)): ray_passed += 1
			else: ray_failed += 1
		else: ray_unresolved += 1
		results.append({"id": str(item.id), "path_pass": movement.pass, "movement": movement,
			"independent_navigation": independent, "ray": ray,
			"snapshot_interaction": {"ray": snapshot_ray}})
	var navigation_summary := navigation.summary()
	var ray_summary := rays.summary()
	var check_errors := []
	check_errors.append_array(navigation.errors)
	check_errors.append_array(rays.errors)
	navigation.cleanup()
	rays.cleanup()
	host.det_pos = saved_position
	host.det.transform = saved_transform
	host.det.set_pose(saved_pose)
	var actors := {}
	for id in corridor._npc:
		var npc: Node3D = corridor._npc[id]
		if is_instance_valid(npc): actors[str(id)] = xy(Vector2(npc.position.x, npc.position.z))
	return {"format": "room-fast-check-v1", "status": "blocked", "purpose": "corridor_stage_movement_diagnostic",
		"project": Source.identity(host.get_tree(), "res://scenes/dual_world/DualWorldMain.tscn"),
		"launch_arguments": OS.get_cmdline_args(), "snapshot": str(host.checkpoints.argument("--dv-snapshot")),
		"snapshot_sha256": FileAccess.get_sha256(str(host.checkpoints.argument("--dv-snapshot"))),
		"restored_state": restored, "room": str(host.eng.s.room), "controller": "gathering",
		"stage": "CorridorStage", "entry": {"position": xy(entry), "source": "production_post_exit_waypoint"},
		"bounds": {"position": xy(bounds.position), "size": xy(bounds.size)}, "actors": actors,
		"minimum_actor_distance": actor_min, "separation_probes": separation,
		"interactions": results, "path_pass": all_paths and separation.pass,
		"navigation_agent_pass": all_navigation, "independent_navigation": navigation_summary,
		"ray_pass": false if ray_failed > 0 else (true if ray_checked > 0 and ray_unresolved == 0 else null),
		"ray_diagnostics": {"checked": ray_checked, "passed": ray_passed, "failed": ray_failed,
			"unresolved": ray_unresolved, "details": ray_summary}, "pass": false,
		"blocking_reasons": ["走廊使用独立 CorridorStage 和直接步进，R05 网格不可用于该阶段。",
			"独立导航使用保守可见几何代理，仅供诊断，不等于实际碰撞体或生产角色路径。",
			"射线采样原跟随相机及快照相机；微距相机检查尚未覆盖。"],
		"errors": check_errors, "acceptance_eligible": false}

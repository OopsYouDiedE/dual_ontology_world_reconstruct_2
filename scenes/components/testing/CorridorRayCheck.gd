extends RefCounted
## Corridor-stage development ray probe. The stage has no production physics
## bodies: collision shapes below are invisible, test-only proxies made from
## actual visible meshes (including current skeletal poses). The camera and
## targets remain the original nodes, in their original SubViewport/world.
## The production corridor controller has no macro close-up; a follow-camera
## ray is not a close-up acceptance claim.
const RoomCheck := preload("res://scenes/components/testing/RoomFastCheck.gd")
const RAY_LAYER := 1 << 20

var host: Control
var corridor: Node
var physics_root: Node3D
var skin_helper := RoomCheck.new()
var shape_cache := {}
var proxies: Array = []
var colliders := {}
var errors: Array[String] = []
var skinned_count := 0
var saved_camera := Transform3D.IDENTITY
var saved_focus := Vector3.ZERO
var saved_az := 0.0
var saved_pitch := 0.0
var saved_dist := 0.0

static func xyz(point: Vector3) -> Array:
	return [point.x, point.y, point.z]

func _is_marker(mesh: MeshInstance3D) -> bool:
	for item in corridor._items:
		var marker = item.get("marker")
		if is_instance_valid(marker) and (mesh == marker or marker.is_ancestor_of(mesh)): return true
	return false

func _shape(mesh: MeshInstance3D, skinned: bool) -> Shape3D:
	if skinned: return skin_helper._skin_shape(mesh)
	var key := mesh.mesh.get_rid().get_id()
	if not shape_cache.has(key): shape_cache[key] = mesh.mesh.create_trimesh_shape()
	var shape: Shape3D = shape_cache[key]
	if shape is ConcavePolygonShape3D: shape.backface_collision = true
	return shape

func begin(h: Control, stage: Node) -> void:
	host = h
	corridor = stage
	saved_camera = host.cam.global_transform
	saved_focus = corridor._focus
	saved_az = corridor._az
	saved_pitch = corridor._pitch
	saved_dist = corridor._dist
	if not corridor._root.global_transform.is_equal_approx(Transform3D.IDENTITY):
		errors.append("corridor_stage_transform_not_identity")
		return
	physics_root = Node3D.new()
	physics_root.name = "CorridorRayCheckOnly"
	host.det_root.get_parent().add_child(physics_root)
	# Only actual stage meshes and the detective; no hidden R05 geometry and no
	# extra visual nodes. Interaction icons are not treated as target geometry.
	var meshes: Array = corridor._root.find_children("*", "MeshInstance3D", true, false)
	meshes.append_array(host.det.find_children("*", "MeshInstance3D", true, false))
	for mesh: MeshInstance3D in meshes:
		if mesh.mesh == null or not mesh.is_visible_in_tree() or _is_marker(mesh): continue
		var skinned := mesh.skin != null and mesh.get_node_or_null(mesh.skeleton) is Skeleton3D
		var shape := _shape(mesh, skinned)
		if shape == null:
			errors.append("cannot_create_mesh_proxy:" + str(mesh.get_path()))
			continue
		var body := StaticBody3D.new()
		body.collision_layer = RAY_LAYER
		body.collision_mask = 0
		physics_root.add_child(body)
		body.global_transform = mesh.global_transform
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)
		proxies.append({"mesh": mesh, "body": body, "collision": collision, "skinned": skinned})
		colliders[body.get_instance_id()] = mesh
		if skinned: skinned_count += 1

func _sync() -> void:
	for proxy in proxies:
		var mesh: MeshInstance3D = proxy.mesh
		proxy.body.global_transform = mesh.global_transform
		proxy.body.collision_layer = RAY_LAYER if mesh.is_visible_in_tree() else 0
		if proxy.skinned and mesh.is_visible_in_tree():
			proxy.collision.shape = _shape(mesh, true)

func _boxes(size: Vector3, expected: Vector3, tolerance := 0.03) -> Array:
	var found := []
	for child in corridor._root.get_children():
		if not child is MeshInstance3D or not child.mesh is BoxMesh: continue
		if child.mesh.size.is_equal_approx(size) and child.position.distance_to(expected) <= tolerance:
			found.append(child)
	return found

func _unique(candidates: Array, root: Node, group: Array, selection: String) -> Dictionary:
	if candidates.size() != 1:
		return {"status": "original_target_not_unique", "selection": selection, "candidate_count": candidates.size()}
	return {"status": "selected", "mesh": candidates[0], "root": root,
		"group": group if not group.is_empty() else candidates, "selection": selection}

func _target(index: int) -> Dictionary:
	var item: Dictionary = corridor._items[index]
	var id := str(item.id)
	var point: Vector2 = corridor._item_pos(index)
	if id.begins_with("door_"):
		var own := id == "door_r05"
		var size := Vector3(0.08, 2.05, 0.85) if own else Vector3(0.96, 2.05, 0.07)
		var leaf_pos := Vector3(point.x - 0.45, 1.05, 0.5) if own else Vector3(point.x, 1.05, 0.1)
		var candidates := _boxes(size, leaf_pos)
		var group := []
		var parts := [
			[Vector3(1.15, 2.2, 0.1), Vector3(point.x, 1.1, 0.03)],
			[Vector3(1.35, 0.14, 0.2), Vector3(point.x, 2.28, 0.0)],
			[Vector3(0.96, 2.05, 0.07), Vector3(point.x, 1.05, 0.1)],
			[Vector3(0.62, 1.5, 0.02), Vector3(point.x, 1.05, 0.145)],
			[Vector3(0.07, 0.07, 0.12), Vector3(point.x + 0.34, 1.0, 0.19)],
			[Vector3(0.13, 0.22, 0.04), Vector3(point.x + 0.34, 1.2, 0.16)]]
		for part in parts: group.append_array(_boxes(part[0], part[1]))
		group.append_array(candidates)
		return _unique(candidates, null, group, "original door leaf and same-door assembly shapes")
	if id == "window":
		var found := _boxes(Vector3(0.9, 0.9, 0.06), Vector3(point.x, 1.7, 0.03))
		return _unique(found, null, found, "original corridor window box")
	if id == "bench":
		var seat := _boxes(Vector3(1.5, 0.12, 0.42), Vector3(point.x, 0.28, 0.45))
		var group := seat.duplicate()
		group.append_array(_boxes(Vector3(0.1, 0.24, 0.36), Vector3(point.x - 0.6, 0.12, 0.45)))
		group.append_array(_boxes(Vector3(0.1, 0.24, 0.36), Vector3(point.x + 0.6, 0.12, 0.45)))
		return _unique(seat, null, group, "original bench seat and legs")
	if id == "plant":
		var pots := []
		for mesh: MeshInstance3D in corridor._root.find_children("*", "MeshInstance3D", true, false):
			if not mesh.mesh is CylinderMesh or _is_marker(mesh): continue
			if absf(mesh.mesh.height - 0.5) > 0.01 or absf(mesh.mesh.top_radius - 0.25) > 0.01: continue
			if Vector2(mesh.global_position.x, mesh.global_position.z).distance_to(point) <= 0.03: pots.append(mesh)
		if pots.size() != 1:
			return {"status": "original_target_not_unique", "selection": "original plant pot", "candidate_count": pots.size()}
		return _unique(pots, pots[0].get_parent(), [], "original plant pot; representative of plant only")
	if id.begins_with("npc_") and item.has("npc"):
		var character: Node3D = corridor._npc.get(str(item.npc))
		if not is_instance_valid(character): return {"status": "original_character_missing"}
		var meshes := character.find_children("*", "MeshInstance3D", true, false).filter(
			func(mesh): return mesh.mesh != null and mesh.is_visible_in_tree())
		return _unique(meshes, character, [], "original character mesh")
	# In the production stage the west end is a wall, not an identifiable gate
	# model, and the kitchen destination is an opening/light, not an object.
	# Do not invent a target, reinterpret a wall as a gate, or raycast a marker.
	return {"status": "original_interaction_object_not_identifiable", "id": id}

func probe(index: int, stand: Vector2) -> Dictionary:
	if not errors.is_empty() or not is_instance_valid(physics_root):
		return {"status": "ray_setup_failed", "applicable": false, "pass": null, "errors": errors}
	var target := _target(index)
	if target.status != "selected":
		return {"status": target.status, "applicable": false, "pass": null, "selection": target}
	var item: Dictionary = corridor._items[index]
	host.det_pos = stand
	host.det.position = Vector3(stand.x, 0.0, stand.y)
	var facing: Vector2 = corridor._item_pos(index) - stand
	if facing.length() > 0.05: host.det.rotation.y = atan2(facing.x, facing.y)
	host.det.set_pose("stand")
	for player: AnimationPlayer in host.det.find_children("*", "AnimationPlayer", true, false):
		player.advance(0.0)
		player.pause()
	# Ask the real controller to settle its follow camera, not a separate camera
	# or invented close-up. Report explicitly that this is an accelerated probe.
	corridor._camera_drive(60.0)
	_sync()
	await host.get_tree().physics_frame
	var camera: Camera3D = host.cam
	var mesh: MeshInstance3D = target.mesh
	var center := mesh.to_global(mesh.get_aabb().get_center())
	var origin := camera.global_position
	var direction := center - origin
	if direction.length_squared() < 0.000001:
		return {"status": "camera_at_target_center", "applicable": true, "pass": false}
	var ray_end := center + direction.normalized() * 0.5
	var query := PhysicsRayQueryParameters3D.create(origin, ray_end, RAY_LAYER)
	query.hit_back_faces = true
	query.hit_from_inside = true
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	var body = hit.get("collider")
	var original: MeshInstance3D = colliders.get(body.get_instance_id()) if is_instance_valid(body) else null
	var target_root: Node = target.root
	var in_group: bool = is_instance_valid(original) and (original in target.group or
		(is_instance_valid(target_root) and (original == target_root or target_root.is_ancestor_of(original))))
	var group_paths := []
	for member in target.group: group_paths.append(str(member.get_path()))
	return {"status": "test_proxy_ray_hit" if is_instance_valid(original) else "test_proxy_ray_no_hit",
		"applicable": true, "pass": in_group, "id": str(item.id), "selection": target.selection,
		"camera_mode": "original_corridor_follow_camera_settled_not_macro",
		"camera_path": str(camera.get_path()), "camera_position": xyz(origin),
		"target_path": str(mesh.get_path()), "target_root": str(target_root.get_path()) if is_instance_valid(target_root) else "",
		"target_group": group_paths, "target_aabb_center": xyz(center),
		"first_hit_original_mesh": str(original.get_path()) if is_instance_valid(original) else "",
		"first_hit_position": xyz(hit.position) if hit.has("position") else [],
		"stand": [stand.x, stand.y], "test_only_collision_proxies": true}

func summary() -> Dictionary:
	return {"camera": "original_corridor_follow_camera_settled_not_macro",
		"collision_proxy_count": proxies.size(), "skinned_pose_proxy_count": skinned_count,
		"original_stage_physics_body_count": corridor._root.find_children("*", "PhysicsBody3D", true, false).size(),
		"errors": errors, "interaction_markers_excluded": true,
		"limitation": "Only sampled follow-camera rays; invisible triangle collision proxies, not production physics or a macro interaction."}

func cleanup() -> void:
	corridor._focus = saved_focus
	corridor._az = saved_az
	corridor._pitch = saved_pitch
	corridor._dist = saved_dist
	host.cam.global_transform = saved_camera
	if is_instance_valid(physics_root): physics_root.queue_free()

extends RefCounted
## Campaign-specific presentation inside RogueRoomView: crossing fixtures, service gates,
## witness targets, field followers, and camp layout/route-grid queries.

const CrossingFixture := preload("res://scenes/rogue_crossing/Fixture.gd")
const ServiceDoor := preload("res://assets/architecture/night_crossing/service_door.glb")
const Followers := preload("res://scenes/rogue_view/FieldFollowers.gd")
const Builder := preload("res://scenes/rogue_view/LotGeometryBuilder.gd")

const STAGE_CLIMATE := {
	"returns": "cool_slate",
	"exchange": "cool_slate",
	"wash": "damp_mist",
	"airlock": "damp_mist",
	"shutter": "amber_alert",
	"hall": "warm_shelter",
	"darkroom": "amber_alert",
	"relay": "cool_slate",
}

var crossing: Node3D
var witness_targets: Array[Dictionary] = []
var routes_released := false
var gate_root: Node3D
var gate_positions := {}
var gate_labels: Array = []
var route_hardware: Array = []
var followers: Node3D

func clear_room() -> void:
	crossing = null
	gate_root = null
	gate_positions.clear()
	gate_labels.clear()
	route_hardware.clear()

func drop_crossing() -> void:
	if is_instance_valid(crossing):
		crossing.hide()
		crossing.queue_free()
	crossing = null
	witness_targets.clear()

func drop_followers(viewport: Viewport) -> void:
	if is_instance_valid(followers):
		viewport.remove_child(followers)
		followers.queue_free()
	followers = null

func sync_gates(geometry: Node3D, player: CharacterBody3D, campaign_view: bool, exits: Array, portals: Array[Dictionary], cells: Array[Vector2i], spawn: Vector3, label_fn: Callable, portal_fn: Callable) -> void:
	if is_instance_valid(gate_root) and gate_labels == exits:
		return
	if is_instance_valid(gate_root):
		geometry.remove_child(gate_root)
		gate_root.queue_free()
	gate_positions.clear()
	route_hardware.clear()
	gate_labels = exits.duplicate()
	gate_root = Node3D.new()
	geometry.add_child(gate_root)
	for i in exits.size():
		var at := Vector3.ZERO
		if i < portals.size():
			at = portal_fn.call(portals[i])
		if i >= portals.size() or gate_positions.values().any(func(p: Vector3): return at.distance_squared_to(p) < 0.64):
			for cell in cells:
				var candidate := Builder.world_pos(Vector2(cell) + Vector2(0.5, 0.5))
				if candidate.distance_squared_to(spawn) < 4.0:
					continue
				if is_instance_valid(crossing) and candidate.distance_squared_to(crossing.position) < 3.6:
					continue
				if gate_positions.values().any(func(p: Vector3): return candidate.distance_squared_to(p) < 2.0):
					continue
				at = candidate
				break
		if at == Vector3.ZERO:
			continue
		var tint := Color("e7bb77") if not str(exits[i]).begins_with("E") else Color("9bc7c5")
		gate_positions[i] = at
		_plaque(label_fn.call(i), at + Vector3.UP * 1.90, tint, gate_root)
		if campaign_view:
			_build_watch_door(at, player)
			continue
		var plinth := MeshInstance3D.new()
		var slab := BoxMesh.new()
		slab.size = Vector3(0.78, 0.024, 0.42)
		plinth.mesh = slab
		plinth.material_override = Builder.painted_material(tint.darkened(0.43), tint.darkened(0.52))
		gate_root.add_child(plinth)
		plinth.position = at + Vector3.UP * 0.029

func _plaque(text: String, point: Vector3, tint: Color, parent: Node3D) -> Label3D:
	var plaque := Label3D.new()
	plaque.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	plaque.text = text
	plaque.font_size = 42
	plaque.pixel_size = 0.0024
	plaque.modulate = tint
	plaque.outline_size = 13
	plaque.position = point
	parent.add_child(plaque)
	return plaque

func _build_watch_door(at: Vector3, player: CharacterBody3D) -> void:
	var door := ServiceDoor.instantiate() as Node3D
	gate_root.add_child(door)
	door.position = at
	var inward := player.position - at
	if absf(inward.x) > absf(inward.z):
		door.rotation.y = PI * .5 * signf(inward.x)
	elif inward.z < 0:
		door.rotation.y = PI
	var panel := door.find_child("Leaf", true, false) as Node3D
	var blocker := StaticBody3D.new()
	door.add_child(blocker)
	Builder.add_shape(blocker, Vector3(0, 1.05, .03), Vector3(1.04, 2.10, .085))
	var collision := blocker.get_child(0) as CollisionShape3D
	route_hardware.append({"leaf": panel, "blocker": collision})
	panel.rotation.y = -.96 if routes_released else 0.0
	collision.set_deferred("disabled", routes_released)

func release_routes(released: bool) -> void:
	if released and is_instance_valid(crossing):
		crossing.mark_released()
	if routes_released == released:
		return
	routes_released = released
	for hardware: Dictionary in route_hardware:
		if not is_instance_valid(hardware.leaf):
			continue
		hardware.blocker.set_deferred("disabled", released)
		var swing: Tween = hardware.leaf.create_tween()
		swing.tween_property(hardware.leaf, "rotation:y", -.96 if released else 0.0, .38)

func set_field_party(viewport: Viewport, player: CharacterBody3D, origin: Vector3, field_model: Callable, names: Array, cells: Array[Vector2i], wall_fn: Callable) -> void:
	if not is_instance_valid(player):
		return
	if is_instance_valid(followers):
		followers.sync(names)
		return
	if names.is_empty():
		return
	followers = Followers.new()
	viewport.add_child(followers)
	var points: Array[Vector3] = []
	var back: Vector3 = player.camera().global_basis.z
	var cursor := Vector2i(floori(origin.x), floori(origin.z))
	var seen := {cursor: true}
	var previous := back
	for i in 4:
		var best_score := -INF
		var chosen := cursor
		for dir: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next := cursor + dir
			if seen.has(next) or not cells.has(next) or wall_fn.call(cursor, next):
				continue
			var score := Vector3(dir.x, 0.0, dir.y).dot(previous)
			if score > best_score:
				best_score = score
				chosen = next
		if cursor == chosen:
			break
		previous = Vector3(chosen.x - cursor.x, 0.0, chosen.y - cursor.y)
		cursor = chosen
		seen[chosen] = true
		points.append(Builder.world_pos(Vector2(cursor) + Vector2(0.5, 0.5)))
	followers.setup(player, points, field_model)
	followers.sync(names)

func set_crossing(geometry: Node3D, player: CharacterBody3D, lot: Dictionary, instance_id: String, stage: String, survivor: String, variant: bool, resolved: bool, origin: Vector3, accessible: Array[Vector2i], wall_fn: Callable) -> bool:
	if is_instance_valid(crossing):
		return false
	var best := INF
	var placement := Transform3D.IDENTITY
	for cell in accessible:
		for front: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT]:
			var across := Vector2i(front.y, -front.x)
			var clear := true
			for row in 3:
				for col in range(-1, 2):
					var at: Vector2i = cell + front * row + across * col
					if not accessible.has(at) or (row > 0 and wall_fn.call(at, at - front)) or (col > -1 and wall_fn.call(at, at - across)):
						clear = false
			if not clear:
				continue
			var at := Builder.world_pos(Vector2(cell) + Vector2(.5, .5))
			var f := Vector3(front.x, 0, front.y)
			var score := origin.distance_squared_to(at + f * 2.05)
			for item: Dictionary in lot.objects:
				if item.role in ["entry", "exit"] and Vector2(at.x, at.z).distance_squared_to(item.position) < 2.25:
					score += 20.0
			if score >= best:
				continue
			best = score
			placement = Transform3D(Basis(Vector3.UP.cross(f), Vector3.UP, f), at)
	assert(best < INF, "No accessible installation aisle for " + stage + " in " + instance_id)
	if best == INF:
		return false
	crossing = CrossingFixture.new()
	geometry.add_child(crossing)
	crossing.install(stage, placement, survivor, variant)
	if resolved:
		crossing.mark_released()
	var front := placement.basis.z
	var spawn := placement.origin + front * 2.22
	if stage == "intake":
		spawn -= placement.basis.x * .58
	var face := spawn - placement.origin
	player.spawn_at(spawn, atan2(face.x, face.z))
	return true

func show_crossing_turn(actors: Dictionary, beat: int) -> void:
	if not is_instance_valid(crossing):
		return
	crossing.turn(beat)
	if not is_instance_valid(followers):
		return
	var docks: Dictionary = {}
	for id in actors:
		docks[id] = crossing.to_global(Vector3(-.66 if actors[id] == 0 else .68, 0, 1.24))
	followers.rehearse(docks)

func camp_layout(lot: Dictionary, walkable_cells: Dictionary, player: CharacterBody3D, campaign_view: bool, template: String, gothic_hall: Node3D, names: Array, clear_fn: Callable, wall_fn: Callable, nearest_fn: Callable) -> Dictionary:
	var graph := {}
	for cell: Vector2i in walkable_cells:
		if clear_fn.call(cell):
			graph[cell] = []
	for cell: Vector2i in graph:
		for dir: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
			if graph.has(cell + dir) and not wall_fn.call(cell, cell + dir):
				graph[cell].append(cell + dir)
	var objects := []
	var taken := {}
	for item: Dictionary in lot.get("objects", []):
		var need: String = {0x06ea4309: "hunger", 0x68ea432a: "fatigue", 0x5dea43f0: "social"}.get(item.guid, "")
		if need.is_empty():
			continue
		var cell := Vector2i(item.position)
		for dir: Vector2i in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP]:
			var stand := cell + dir
			if graph.has(stand) and not taken.has(stand) and not wall_fn.call(cell, stand):
				taken[stand] = true
				var title: String = {"hunger": "Meal table", "fatigue": "Armchair", "social": "Common table seat"}[need]
				objects.append({"id": "%s (%d,%d)" % [title, cell.x, cell.y], "stand": stand, "need": need, "duration": 12, "relief": 55})
				break
	var people := []
	if is_instance_valid(player):
		taken[Vector2i(player.position.x, player.position.z)] = true
	var seats: Array = graph.keys()
	if campaign_view and not names.is_empty():
		seats = _hall_floor_positions(graph, taken, names.size(), player, template, gothic_hall, nearest_fn)
	for cell: Vector2i in seats:
		if people.size() == names.size():
			break
		if taken.has(cell):
			continue
		var index := people.size()
		people.append({"id": names[index], "cell": cell, "needs": {"hunger": 75 if index % 3 == 0 else 20, "fatigue": 75 if index % 3 == 1 else 20, "social": 75 if index % 3 == 2 else 20}})
	return {"graph": graph, "objects": objects, "people": people}

func _hall_floor_positions(graph: Dictionary, reserved: Dictionary, count: int, player: CharacterBody3D, template: String, gothic_hall: Node3D, nearest_fn: Callable) -> Array[Vector2i]:
	var positions: Array[Vector2i] = []
	var room_cells: Array[Vector2i] = []
	var origin := player.position
	var first := Vector2i(floori(origin.x), floori(origin.z))
	if not graph.has(first):
		var adjusted: Vector3 = nearest_fn.call(Vector2(origin.x, origin.z))
		first = Vector2i(floori(adjusted.x), floori(adjusted.z))
	var queue: Array[Vector2i] = [first]
	var visited := {first: true}
	for idx in 512:
		if idx == queue.size():
			break
		var cell := queue[idx]
		for next: Vector2i in graph.get(cell, []):
			if visited.has(next):
				continue
			visited[next] = true
			queue.append(next)
		if reserved.has(cell) or not graph.has(cell):
			continue
		if template == "public_nave" and absf(cell.x + 0.5 - gothic_hall.pendulum_world_pos.x) < 3.0:
			continue
		if is_instance_valid(crossing):
			var local := crossing.to_local(Builder.world_pos(Vector2(cell) + Vector2(.5, .5)))
			if absf(local.x) < 1.7 and local.z > -.62 and local.z < 2.0:
				continue
		room_cells.append(cell)
	for i in mini(count, room_cells.size()):
		var chosen := 0
		var best := -INF
		for j in room_cells.size():
			var candidate := room_cells[j]
			var from_desk := Vector2(candidate).distance_to(Vector2(first))
			var score := -from_desk if i == 0 else minf(from_desk, 5.0)
			for other in positions:
				score = minf(score, Vector2(candidate).distance_to(Vector2(other)))
			if score > best:
				best = score
				chosen = j
		positions.append(room_cells[chosen])
		room_cells.remove_at(chosen)
	return positions

static func viewport_routes_grid(graph: Dictionary) -> Array:
	var grid: Array = []
	for c: Vector2i in graph:
		var edge := 0
		for j in 4:
			var neighbor: Vector2i = c + [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP][j]
			if graph.has(neighbor) and neighbor in graph[c]:
				edge |= 1 << j
		grid.append([c.x, c.y, edge])
	return grid

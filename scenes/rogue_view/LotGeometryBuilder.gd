extends RefCounted
## Pure 3D architectural builder and walkable cell spatial query helper for RogueRoomView.

const Blueprint = preload("res://scenes/rogue_view/NativeBlueprint.gd")
const Silhouette = preload("res://scenes/rogue_view/CatalogSilhouette.gd")
const Plan = preload("res://scenes/rogue_view/NativeLotPlan.gd")
const Kitchen = preload("res://scenes/rogue_view/render/HotKitchen.gd")
const Lighting = preload("res://scenes/rogue_view/render/RoomLighting.gd")
const PublicHallGothic = preload("res://scenes/rogue_view/render/PublicHallGothic.gd")
const MeridianWell = preload("res://scenes/rogue_view/render/MeridianWell.gd")
const HallFinish = preload("res://scenes/blue_prince_lab/HallFinish.gdshader")
const RenderProfile = preload("res://scenes/components/rendering/AcademyRenderProfile.gd")
const Roster = preload("res://scenes/rogue_crossing/Roster.gd")

static func world_pos(point: Vector2) -> Vector3:
	return Vector3(point.x, 0.0, point.y)

static func hall_finish(color: Color, roughness := 0.84, grain := 0.055, is_wood := false, pale_wash := 0.0, emission := Color.BLACK, runner := false, vault_fill := 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = HallFinish
	mat.set_shader_parameter("pigment", color)
	mat.set_shader_parameter("surface_roughness", roughness)
	mat.set_shader_parameter("grain", grain)
	mat.set_shader_parameter("wood", 1.0 if is_wood else 0.0)
	mat.set_shader_parameter("runner", 1.0 if runner else 0.0)
	mat.set_shader_parameter("pale_wash", pale_wash)
	mat.set_shader_parameter("vault_fill", vault_fill)
	if emission != Color.BLACK:
		mat.set_shader_parameter("emission_gain", 0.35)
	mat.set_shader_parameter("toon_on", true)
	mat.set_shader_parameter("toon_strength", 0.86)
	return mat

static func tile_surface(tint: Color, wall_surface: bool) -> ShaderMaterial:
	return hall_finish(tint, 0.88 if wall_surface else 0.74, 0.048 if wall_surface else 0.062, false, 0.09 if wall_surface else 0.04, Color.BLACK, false, 0.03 if wall_surface else 0.0)

static func painted_material(color: Color, emission := Color.BLACK, is_wood := false) -> ShaderMaterial:
	return hall_finish(color, 0.84, 0.055, is_wood, 0.04, emission)

static func is_hall_shell(template: String, room_label: String) -> bool:
	return template == "public_nave" or room_label == "Public Hall"

static func has_meridian_well(template: String, room_label: String) -> bool:
	return is_hall_shell(template, room_label) or room_label == "Observatory"

static func build_room(geometry: Node3D, camera: Camera3D, lot: Dictionary, template: String, room_label: String, expedition_view: bool, pendulum_drifting: bool, kitchen_plan: Dictionary) -> Dictionary:
	var walkable_cells := {}
	if template == "kitchen" and not kitchen_plan.is_empty():
		for cell in lot.floors:
			walkable_cells[cell] = true
		var kitchen := Kitchen.new()
		geometry.add_child(kitchen)
		kitchen.build(kitchen_plan, lot.floors)
		return {"walkable_cells": walkable_cells, "kitchen": kitchen, "lights": null, "gothic_hall": null, "avatar_root": null, "object_root": null}

	var static_body := StaticBody3D.new()
	geometry.add_child(static_body)
	var tile := BoxMesh.new()
	tile.size = Vector3(1, 0.15, 1)
	var batches := {}
	var floor_bounds := Rect2i()
	var well := Rect2i()
	if expedition_view and has_meridian_well(template, room_label):
		well = Rect2i(14, 15, 4, 4) if template == "public_nave" else MeridianWell.plan(lot)
		if well.has_area():
			MeridianWell.install(geometry, well, template == "public_nave")

	var hall_shell := is_hall_shell(template, room_label)
	for cell: Vector2i in lot.floors:
		var pattern: int = lot.patterns.get(cell, 0)
		var pos := Vector3(cell.x + 0.5, -0.075, cell.y + 0.5)
		if not well.has_point(cell):
			if not batches.has(pattern):
				var surface := SurfaceTool.new()
				surface.begin(Mesh.PRIMITIVE_TRIANGLES)
				batches[pattern] = surface
			batches[pattern].append_from(tile, 0, Transform3D(Basis.IDENTITY, pos))
		var area := Rect2i(cell, Vector2i.ONE)
		floor_bounds = area if not floor_bounds.has_area() else floor_bounds.merge(area)
		if pattern != 65535:
			walkable_cells[cell] = true
			add_shape(static_body, pos, tile.size)

	for pattern: int in batches:
		var floor_tint: Color = Color("525e6a") if (expedition_view and hall_shell) else Plan.floor_color(pattern).darkened(0.24)
		commit_static_mesh(geometry, batches[pattern], tile_surface(floor_tint, false))

	var wall := BoxMesh.new()
	wall.size = Vector3(1, 2.75, 0.13)
	var walls := SurfaceTool.new()
	walls.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gothic_shell := expedition_view and hall_shell
	for edge: Vector4i in lot.segments:
		var a := Vector2(edge.x, edge.y)
		var b := Vector2(edge.z, edge.w)
		var d := b - a
		var middle := (a + b) * 0.5
		var position := Vector3(middle.x, wall.size.y * 0.5, middle.y)
		var basis := Basis(Vector3.UP, -d.angle())
		if not gothic_shell:
			if lot.get("windows", {}).has(edge):
				_build_window(geometry, position, basis, d.length())
			else:
				walls.append_from(wall, 0, Transform3D(basis * Basis.from_scale(Vector3(d.length(), 1, 1)), position))
		add_shape(static_body, position, Vector3(d.length(), wall.size.y, wall.size.z), basis)
	if not gothic_shell:
		commit_static_mesh(geometry, walls, tile_surface(Color("b9b1a1"), true))

	var gothic_hall: Node3D = null
	if gothic_shell:
		gothic_hall = PublicHallGothic.install(geometry, lot, Rect2i(11, 5, 10, 20) if template == "public_nave" else floor_bounds, well, pendulum_drifting)
		var nave := Rect2(Vector2(11, 5), Vector2(10, 20)) if template == "public_nave" else Rect2(floor_bounds)
		for i in 3:
			var fill := OmniLight3D.new()
			fill.name = "NaveFill%d" % i
			geometry.add_child(fill)
			fill.position = Vector3(nave.get_center().x, 4.1, lerpf(nave.position.y + 2.5, nave.end.y - 2.5, i / 2.0))
			fill.omni_range = 12.0
			fill.light_energy = 0.52
			fill.light_color = Color("ffe9cb")
			fill.omni_attenuation = 1.25
	elif expedition_view:
		# First-person rooms share Blue Prince painterly plaster ceilings illuminated evenly.
		var ceiling := SurfaceTool.new()
		ceiling.begin(Mesh.PRIMITIVE_TRIANGLES)
		for cell: Vector2i in walkable_cells:
			ceiling.append_from(tile, 0, Transform3D(Basis.IDENTITY, Vector3(cell.x + 0.5, 2.79, cell.y + 0.5)))
		commit_static_mesh(geometry, ceiling, hall_finish(Color("929ba4"), 0.90, 0.04, false, 0.14))
		var ceiling_fill := OmniLight3D.new()
		ceiling_fill.name = "RoomSoftFill"
		ceiling_fill.position = Vector3(floor_bounds.get_center().x, 2.25, floor_bounds.get_center().y)
		ceiling_fill.omni_range = 18.0
		ceiling_fill.light_energy = 0.55
		ceiling_fill.light_color = Color("e6ded2")
		ceiling_fill.omni_attenuation = 1.25
		geometry.add_child(ceiling_fill)

	var avatar_root := Node3D.new()
	var object_root := Node3D.new()
	geometry.add_child(avatar_root)
	geometry.add_child(object_root)
	update_lot_avatars(avatar_root, lot)
	rebuild_objects(object_root, lot, template, expedition_view)

	var center := Vector3(floor_bounds.get_center().x, 0.0, floor_bounds.get_center().y)
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.position = center + Vector3(1, 10, 8)
	camera.look_at(center)
	var lights := Lighting.new()
	geometry.add_child(lights)
	lights.build(lot, center)
	return {"walkable_cells": walkable_cells, "kitchen": null, "lights": lights, "gothic_hall": gothic_hall, "avatar_root": avatar_root, "object_root": object_root}

static func _build_window(geometry: Node3D, wall_center: Vector3, basis: Basis, width: float) -> void:
	var anchor := Node3D.new()
	geometry.add_child(anchor)
	anchor.transform = Transform3D(basis, Vector3(wall_center.x, 0, wall_center.z))
	var plaster := hall_finish(Color("b5bebc"), 0.88, 0.05, false, 0.10)
	var frame := hall_finish(Color("43362f"), 0.72, 0.06, true)
	var glass := StandardMaterial3D.new()
	glass.albedo_color = Color(0.39, 0.74, 0.89, 0.30)
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.roughness = 0.18
	_window_part(anchor, Vector3(0, 0.40, 0), Vector3(width, 0.80, 0.13), plaster)
	_window_part(anchor, Vector3(0, 2.435, 0), Vector3(width, 0.63, 0.13), plaster)
	for x in [-width * 0.45, width * 0.45, 0.0]:
		_window_part(anchor, Vector3(x, 1.46, 0), Vector3(0.09, 1.32, 0.19), frame)
	for y in [0.83, 1.46, 2.09]:
		_window_part(anchor, Vector3(0, y, 0), Vector3(width, 0.07, 0.21), frame)
	_window_part(anchor, Vector3(0, 1.46, 0), Vector3(width - 0.12, 1.24, 0.018), glass)

static func _window_part(anchor: Node3D, point: Vector3, dimensions: Vector3, material: Material) -> void:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	mesh.material = material
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = point
	anchor.add_child(part)

static func rebuild_objects(object_root: Node3D, lot: Dictionary, template: String, expedition_view: bool) -> void:
	for child in object_root.get_children():
		object_root.remove_child(child)
		child.queue_free()
	for item: Dictionary in lot.objects:
		if item.role == "window" or item.get("layout_only", false):
			continue
		if template == "public_nave" and expedition_view:
			continue
		var anchor := Node3D.new()
		object_root.add_child(anchor)
		anchor.position = world_pos(item.position)
		anchor.rotation.y = item.yaw
		anchor.set_meta("native_guid", item.guid)
		var role: String = item.role
		var marker := MeshInstance3D.new()
		var body := BoxMesh.new()
		var word := String(item.label).to_lower()
		body.size = Vector3(0.74, 0.70, 0.66)
		if "table" in word or "desk" in word or "counter" in word:
			body.size = Vector3(0.94, 0.76, 0.64)
		if "shelf" in word or "cabinet" in word or "bookcase" in word:
			body.size = Vector3(0.82, 1.48, 0.40)
		if role in ["entry", "exit"] or item.get("annotation_only", false):
			body.size = Vector3(0.76, 0.035, 0.76)
		body.material = painted_material(Color("5ba47f") if role == "entry" else Color("ce9b58") if role == "exit" else Color("866d55"))
		if not Silhouette.populate(anchor, int(item.guid)):
			marker.mesh = body
			marker.position.y = body.size.y * 0.5
			anchor.add_child(marker)
		else:
			marker.free()

static func update_lot_avatars(avatar_root: Node3D, lot: Dictionary) -> void:
	var positions: PackedVector2Array = lot.avatars
	while avatar_root.get_child_count() > positions.size():
		var last := avatar_root.get_child(-1)
		avatar_root.remove_child(last)
		last.queue_free()
	for i in positions.size():
		if i == avatar_root.get_child_count():
			var actor := Node3D.new()
			avatar_root.add_child(actor)
			Roster.attach(actor, Roster.NAMES[i % Roster.NAMES.size()])
		var actor := avatar_root.get_child(i) as Node3D
		actor.position = Vector3(positions[i].x, 0, positions[i].y)

static func add_shape(body: StaticBody3D, point: Vector3, size: Vector3, basis := Basis.IDENTITY) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.transform = Transform3D(basis, point)
	body.add_child(collision)

static func commit_static_mesh(geometry: Node3D, surface: SurfaceTool, material: Material) -> void:
	var mesh := surface.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	geometry.add_child(instance)

static func has_wall_between(lot: Dictionary, from: Vector2i, to: Vector2i) -> bool:
	if from == to:
		return false
	var edge: Vector4i
	if from.x != to.x:
		var x := maxi(from.x, to.x)
		edge = Vector4i(x, from.y, x, from.y + 1)
	else:
		var y := maxi(from.y, to.y)
		edge = Vector4i(from.x, y, from.x + 1, y)
	return edge in lot.segments

static func is_clear_cell(lot: Dictionary, walkable_cells: Dictionary, template: String, gothic_hall: Node3D, crossing: Node3D, campaign_view: bool, cell: Vector2i) -> bool:
	if not walkable_cells.has(cell):
		return false
	var center := Vector2(cell) + Vector2(0.5, 0.5)
	if template == "public_nave" and is_instance_valid(gothic_hall):
		for bounds: Rect2 in gothic_hall.station_bounds:
			if bounds.has_point(center):
				return false
	if campaign_view and is_instance_valid(crossing):
		var local := crossing.to_local(world_pos(center))
		if absf(local.x) < 1.52 and absf(local.z) < .63:
			return false
	for item: Dictionary in lot.objects:
		if not item.get("annotation_only", false) and item.role not in ["window", "entry", "exit"] and center.distance_to(item.position) < 0.48:
			return false
	for edge: Vector4i in lot.segments:
		if edge.x != edge.z and edge.y != edge.w and Vector2(edge.x + edge.z, edge.y + edge.w) * 0.5 == center:
			return false
	return true

static func nearest_walkable(lot: Dictionary, walkable_cells: Dictionary, clear_fn: Callable, point: Vector2) -> Vector3:
	var best := INF
	var result := Vector3.ZERO
	for cell: Vector2i in walkable_cells:
		if not clear_fn.call(cell):
			continue
		var center := Vector2(cell) + Vector2(0.5, 0.5)
		var distance := center.distance_squared_to(point)
		if distance < best:
			best = distance
			result = world_pos(center)
	if best == INF and not walkable_cells.is_empty():
		var first: Vector2i = walkable_cells.keys()[0]
		return world_pos(Vector2(first) + Vector2(0.5, 0.5))
	return result

static func reachable_cells(start: Vector2i, clear_fn: Callable, wall_fn: Callable, limit := 120) -> Array[Vector2i]:
	var result: Array[Vector2i] = [start]
	var seen := {start: true}
	var cursor := 0
	while cursor < result.size() and result.size() < limit:
		var from := result[cursor]
		for dir: Vector2i in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
			var next := from + dir
			if not seen.has(next) and clear_fn.call(next) and not wall_fn.call(from, next):
				seen[next] = true
				result.append(next)
		cursor += 1
	return result

static func spawn_point(lot: Dictionary, template: String, kitchen: Node, clear_fn: Callable, wall_fn: Callable, nearest_fn: Callable) -> Vector3:
	if template == "public_nave":
		return Vector3(16, 0, 24.4)
	if is_instance_valid(kitchen):
		return Kitchen.SPAWN
	for object: Dictionary in lot.objects:
		if object.role == "entry":
			var interior: Vector2 = object.get("interior", object.position)
			var start: Vector3 = nearest_fn.call(interior)
			var step := Vector2i((interior - Vector2(object.position)).normalized().round())
			var cell := Vector2i(floori(start.x), floori(start.z))
			for i in 2:
				var next := cell + step
				if not clear_fn.call(next) or wall_fn.call(cell, next):
					break
				cell = next
			return world_pos(Vector2(cell) + Vector2(0.5, 0.5))
	var bounds := Rect2i(lot.floors[0], Vector2i.ONE)
	for cell: Vector2i in lot.floors:
		bounds = bounds.merge(Rect2i(cell, Vector2i.ONE))
	return nearest_fn.call(Vector2(bounds.get_center()))

static func spawn_yaw(lot: Dictionary) -> float:
	for item: Dictionary in lot.objects:
		if item.role == "entry" and item.has("interior"):
			var inward: Vector2 = item.interior - item.position
			if inward.length_squared() > 0.01:
				return atan2(-inward.x, -inward.y)
	return NAN

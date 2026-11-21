extends Node3D
## ArchBuilder owns the shell geometry and cuts. Everything in Equipment is a review proxy.

const WallPath = preload("res://tools/building_construction/BuildingConstruction/Walls/WallPathGeometry.gd")
const Geometry = preload("res://tools/building_construction/BuildingConstruction/Shared/ArchitectGeometry.gd")
const State = preload("res://tools/building_construction/ArchitectState.gd")
const FLOOR = preload("res://scenes/rubber_whitebox/BlueRubber.tres")
const WALL = preload("res://scenes/rubber_whitebox/RedRubber.tres")
const PORTAL_WIDTH := 2.55
const PORTAL_HEIGHT := 2.52
const APRON_FRONT := 2.15
const APRON_WIDTH := 4.6
const APRON_BACK := 2.0

var palette := {}
var parts: Node3D
var markings: Node3D

func build(plan: Dictionary) -> bool:
	for key: String in ["pale", "metal", "water", "dark", "amber", "cyan", "apron"]:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = {
			"pale": Color("e1d8c5"), "metal": Color("9faeb2"), "water": Color("458884"),
			"dark": Color("293d4c"), "amber": Color("e8b36d"), "cyan": Color("91cac9"), "apron": Color("3c5568"),
		}[key]
		mat.roughness = 0.82
		palette[key] = mat
	var outline := _archbuilder(plan)
	if outline.is_empty():
		return false
	var shell := _group("ArchBuilderShell")
	var polygons: Array = outline.layers[0].polygons
	var floor_mesh: MeshInstance3D = Geometry.prism(polygons[0], -0.22, 0.0, "grout")
	floor_mesh.name = "RubberFloor"
	floor_mesh.material_override = FLOOR
	shell.add_child(floor_mesh)
	_mesh_collision(floor_mesh)
	for spec: Dictionary in outline.walls:
		var wall_root: Node3D = WallPath.build(spec)
		shell.add_child(wall_root)
		# ArchBuilder cuts the portals while the whitebox leaves the framed openings traversable.
		for segment in wall_root.get_children():
			for entry in segment.get_children():
				if entry.has_meta("opening_id"):
					segment.remove_child(entry)
					entry.free()
		for mesh_node: MeshInstance3D in wall_root.find_children("*", "MeshInstance3D", true, false):
			mesh_node.material_override = WALL
			_mesh_collision(mesh_node)
	var half: Vector2 = plan.size * 0.5
	var apron := _group("ReviewAprons")
	_box(apron, "EntryApron", Vector3(0, -0.12, half.y + APRON_FRONT * 0.5), Vector3(APRON_WIDTH, 0.24, APRON_FRONT), palette.apron)
	if not plan.terminal:
		_box(apron, "ExitApron", Vector3(plan.exit_x, -0.12, -half.y - APRON_BACK * 0.5), Vector3(3.5, 0.24, APRON_BACK), palette.apron)
		_portal(shell, plan.exit_x, -half.y + 0.17)
	_entry_tag(shell, half.y - 0.17)
	parts = _group("EquipmentEnvelopes")
	markings = _group("ReviewMarkings")
	for fixture: Dictionary in plan.fixtures:
		_add_fixture(fixture)
	_draw_route(plan.route, palette.amber)
	if not plan.alternative.is_empty():
		_draw_route(plan.alternative, palette.cyan, plan.route)
	var finish: Vector2 = plan.finish
	_box(markings, "FinishMarker", Vector3(finish.x, 0.009, finish.y), Vector3(1.75, 0.014, 0.78), palette.amber, false)
	_label(markings, "BELL CHECK" if plan.terminal else "NEXT ROOM", Vector3(finish.x, 0.02, finish.y), Color("263643"), 0.0054, Vector3(-PI/2.0, 0, 0))
	return true

func _archbuilder(plan: Dictionary) -> Dictionary:
	var half: Vector2 = plan.size * 0.5
	var h: float = plan.height
	var rear := [] if plan.terminal else [[half.x + plan.exit_x, PORTAL_WIDTH, PORTAL_HEIGHT]]
	var walls := [
		_wall("FrontLeftCutaway", Vector2(-half.x, half.y), Vector2(-PORTAL_WIDTH * 0.5, half.y), 0.78, []),
		_wall("FrontRightCutaway", Vector2(PORTAL_WIDTH * 0.5, half.y), Vector2(half.x, half.y), 0.78, []),
		_wall("BackWall", Vector2(-half.x, -half.y), Vector2(half.x, -half.y), h, rear),
		_wall("LeftWall", Vector2(-half.x, half.y), Vector2(-half.x, -half.y), h, []),
		_wall("RightWall", Vector2(half.x, -half.y), Vector2(half.x, half.y), h, []),
	]
	for spec: Dictionary in plan.walls:
		walls.append(_wall("Partition%02d" % (walls.size() - 3), spec.a, spec.b, spec.height, spec.openings))
	var rect := [[-half.x, -half.y], [half.x, -half.y], [half.x, half.y], [-half.x, half.y]]
	var document := {"activeLayerId": "review", "layers": [{"id": "review", "name": "Review floor", "y": 0.0, "polygons": [rect]}], "walls": walls}
	var state := State.new()
	if not state.restore(JSON.stringify(document)):
		push_error("Invalid ArchBuilder whitebox document")
		return {}
	# Walls define the floor boundary in the editor; keep the explicit slab perimeter here.
	var restored: Dictionary = state.data
	restored.layers[0].polygons = [rect]
	return restored

func _wall(title: String, a: Vector2, b: Vector2, height: float, openings: Array) -> Dictionary:
	var cuts := []
	for cut: Array in openings:
		cuts.append({"id": "%s_%d" % [title, cuts.size()], "type": "rectangular_window", "segment": 0,
			"center": cut[0], "width": cut[1], "height": cut[2], "bottom": 0.0})
	return {"id": title, "name": title, "points": [[a.x, 0.0, a.y], [b.x, 0.0, b.y]], "height": height,
		"thickness": 0.24, "style": "stone", "hasPillars": false, "openings": cuts}

func _group(title: String) -> Node3D:
	var group := Node3D.new()
	group.name = title
	add_child(group)
	return group

func _mesh_collision(node: MeshInstance3D) -> void:
	var shape := node.mesh.create_trimesh_shape()
	shape.backface_collision = true
	_solid(node, shape)

func _solid(mesh_node: MeshInstance3D, shape: Shape3D) -> void:
	var body := StaticBody3D.new()
	mesh_node.add_child(body)
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

func _box(parent: Node3D, title: String, at: Vector3, size: Vector3, material: Material, solid := true) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var node := MeshInstance3D.new()
	node.name = title
	node.position = at
	node.mesh = mesh
	node.material_override = material
	parent.add_child(node)
	if solid:
		var shape := BoxShape3D.new()
		shape.size = size
		_solid(node, shape)
	return node

func _portal(parent: Node3D, x: float, z: float) -> void:
	var material: Material = palette.pale
	for side in [-1, 1]:
		_box(parent, "PortalTrim", Vector3(x + side * (PORTAL_WIDTH * 0.5 + 0.09), PORTAL_HEIGHT * 0.5, z), Vector3(0.18, PORTAL_HEIGHT, 0.13), material, false)
	_box(parent, "PortalHeader", Vector3(x, PORTAL_HEIGHT + 0.13, z), Vector3(PORTAL_WIDTH + 0.36, 0.26, 0.13), material, false)
	_label(parent, "EXIT   /   NEXT ROOM", Vector3(x, PORTAL_HEIGHT + 0.13, z + 0.068), Color("283946"), 0.0051)

func _entry_tag(parent: Node3D, z: float) -> void:
	for side in [-1, 1]:
		_box(parent, "EntryPost", Vector3(side * (PORTAL_WIDTH * 0.5 + 0.09), 0.47, z + 0.16), Vector3(0.19, 0.94, 0.31), palette.pale, false)
	_label(parent, "ENTRY", Vector3(0, 0.014, z + 1.18), Color("c0d2d4"), 0.0082, Vector3(-PI/2.0, 0, 0))

func _add_fixture(fixture: Dictionary) -> void:
	var at: Vector3 = fixture.at
	var size: Vector3 = fixture.size
	var title: String = fixture.label
	var mat: Material = palette[fixture.finish]
	if fixture.shape == "drum":
		var cylinder := CylinderMesh.new()
		cylinder.radial_segments = 12
		cylinder.height = size.y
		cylinder.top_radius = size.x * (0.32 if title == "DAWN BELL" else 0.5)
		cylinder.bottom_radius = size.x * 0.5
		var node := MeshInstance3D.new()
		node.name = title.to_pascal_case().validate_node_name()
		node.mesh = cylinder
		node.position = at
		node.material_override = mat
		parts.add_child(node)
		var shape := CylinderShape3D.new()
		shape.radius = cylinder.bottom_radius
		shape.height = size.y
		_solid(node, shape)
	else:
		_box(parts, title.to_pascal_case().validate_node_name(), at, size, mat, fixture.shape != "mat")
	if title in ["BELL PIER A", "BELL PIER B", "BELL BEAM", "BELL PLINTH", "ISSUE CABINET", "ESCAPE LINTEL", "QUEUE RAIL"]:
		return
	var ink := Color("f6ecd9") if fixture.finish in ["dark", "water"] else Color("253846")
	if fixture.shape == "mat":
		_label(parts, title, at + Vector3(0, size.y * 0.5 + 0.008, 0), ink, 0.0062, Vector3(-PI/2.0, 0, 0))
	else:
		var label_at := Vector3(at.x, minf(at.y + size.y * 0.22, at.y + 0.33), at.z + maxf(size.x if fixture.shape == "drum" else 0.0, size.z) * 0.5 + 0.013)
		_label(parts, title, label_at, ink, minf(0.0068, size.x * 0.052 / title.length()))

func _label(parent: Node3D, title: String, at: Vector3, ink: Color, size: float, rotation := Vector3.ZERO) -> void:
	var node := Label3D.new()
	node.position = at
	node.rotation = rotation
	node.font_size = 32
	node.outline_size = 0
	node.pixel_size = size
	node.modulate = ink
	node.text = title
	parent.add_child(node)

func _draw_route(route: Array, material: Material, shared := []) -> void:
	for i in range(1, route.size()):
		var a: Vector2 = route[i - 1]
		var b: Vector2 = route[i]
		if i < shared.size() and shared[i - 1] == a and shared[i] == b:
			continue
		var length := a.distance_to(b)
		var heading := a.direction_to(b)
		for step in range(ceilf(length / 1.55)):
			var distance := (step + 0.52) * length / ceilf(length / 1.55)
			var at := a + heading * distance
			var mark := _box(markings, "RouteDash", Vector3(at.x, 0.008, at.y), Vector3(0.063, 0.012, 0.56), material, false)
			mark.rotation.y = atan2(heading.x, heading.y)

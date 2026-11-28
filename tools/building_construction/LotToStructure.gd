extends RefCounted
## Converts a room lot (FreeSO XML via NativeBlueprint, or an ArchBuilder document via
## HotKitchen-style layout) into an editable LevelStructure3D scene made of ordinary
## Godot @tool nodes. The result round-trips: LevelStructure3D.derive_lot() returns the
## same floors, wall edges, windows and objects as the source lot.

const Structure := preload("res://scenes/components/structure/LevelStructure3D.gd")
const Anchor := preload("res://scenes/components/structure/LevelAnchor3D.gd")
const Wall := preload("res://tools/building_construction/BuildingConstruction/Walls/SmartWall3D.gd")
const FloorZone := preload("res://tools/building_construction/BuildingConstruction/Floors/SmartFloorZone3D.gd")

const WALL_HEIGHT := 2.75
const WALL_THICKNESS := 0.13
const FLOOR_THICKNESS := 0.15
const WINDOW_BOTTOM := 0.9
const WINDOW_TOP := 2.2

static func build(lot: Dictionary, template: String, label: String, upper_plan := {}) -> Node3D:
	var root: Node3D = Structure.new()
	root.name = template.to_pascal_case() + "Structure"
	root.template_id = template
	root.room_label = label
	root.lot_size = int(lot.get("width", 32))
	root.upper_plan = upper_plan.duplicate(true)
	var floors := _group(root, "Floors")
	var walls := _group(root, "Walls")
	var anchors := _group(root, "Anchors")
	_group(root, "Stations")
	_group(root, "Components")
	for rect: Dictionary in _floor_rects(lot):
		var zone: Node3D = FloorZone.new()
		var r: Rect2i = rect.rect
		zone.name = "Floor_%d_%d" % [r.position.x, r.position.y]
		zone.polygon = PackedVector2Array([Vector2(r.position), Vector2(r.end.x, r.position.y), Vector2(r.end), Vector2(r.position.x, r.end.y)])
		zone.pattern = rect.pattern
		zone.floor_thickness = FLOOR_THICKNESS
		zone.show_grid = false
		_own(floors, zone, root)
	for run: Dictionary in _wall_runs(lot):
		var wall: Node3D = Wall.new()
		wall.name = "Wall_%d_%d_%d_%d" % [run.a.x, run.a.y, run.b.x, run.b.y]
		wall.grid_snap = 0.0
		wall.start_point = Vector3(run.a.x, 0, run.a.y)
		wall.end_point = Vector3(run.b.x, 0, run.b.y)
		wall.wall_height = WALL_HEIGHT
		wall.wall_thickness = WALL_THICKNESS
		wall.skirting_enabled = false
		if run.window:
			var length: float = Vector2(run.a).distance_to(Vector2(run.b))
			var ops: Array[Dictionary] = [{"from": 0.12, "to": length - 0.12, "bottom": WINDOW_BOTTOM, "top": WINDOW_TOP}]
			wall.openings = ops
		_own(walls, wall, root)
	var count := {}
	for item: Dictionary in lot.get("objects", []):
		var node: Node3D = Anchor.new()
		var role := str(item.get("role", ""))
		var key := role if role != "" else "object"
		count[key] = int(count.get(key, 0)) + 1
		node.anchor_id = "%s_%d" % [key, count[key]]
		node.name = node.anchor_id.to_pascal_case()
		node.role = role if role != "" else "object"
		node.label = str(item.get("label", ""))
		node.guid = int(item.get("guid", 0))
		var extra := item.duplicate(true)
		for k in ["position", "role", "label", "guid"]:
			extra.erase(k)
		node.extra = extra
		var pos: Vector2 = item.get("position", Vector2.ZERO)
		node.position = Vector3(pos.x, 0, pos.y)
		_own(anchors, node, root)
	return root

static func save(root: Node3D, path: String) -> Error:
	var packed := PackedScene.new()
	var err := packed.pack(root)
	if err != OK:
		return err
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	return ResourceSaver.save(packed, path)

static func _group(root: Node3D, title: String) -> Node3D:
	var node := Node3D.new()
	node.name = title
	root.add_child(node)
	node.owner = root
	return node

static func _own(parent: Node, node: Node, root: Node) -> void:
	parent.add_child(node)
	node.owner = root

## Greedy rectangles of equal pattern so the editor shows a few big, editable zones.
static func _floor_rects(lot: Dictionary) -> Array:
	var patterns: Dictionary = lot.get("patterns", {})
	var cells: Array = lot.get("floors", []).duplicate()
	cells.sort_custom(func(a: Vector2i, b: Vector2i): return a.y < b.y or (a.y == b.y and a.x < b.x))
	var used := {}
	var out: Array = []
	for cell: Vector2i in cells:
		if used.has(cell):
			continue
		var pattern: int = patterns.get(cell, 11)
		var same := func(c: Vector2i) -> bool: return patterns.has(c) and not used.has(c) and int(patterns[c]) == pattern
		var w := 1
		while same.call(cell + Vector2i(w, 0)):
			w += 1
		var h := 1
		while true:
			var row_ok := true
			for dx in w:
				if not same.call(cell + Vector2i(dx, h)):
					row_ok = false
					break
			if not row_ok:
				break
			h += 1
		for dy in h:
			for dx in w:
				used[cell + Vector2i(dx, dy)] = true
		out.append({"rect": Rect2i(cell, Vector2i(w, h)), "pattern": pattern})
	return out

## Contiguous collinear unit edges merge into one wall; window edges stay single walls.
static func _wall_runs(lot: Dictionary) -> Array:
	var windows: Dictionary = lot.get("windows", {})
	var horizontal := {}
	var vertical := {}
	var out: Array = []
	for e: Vector4i in lot.get("segments", []):
		var a := Vector2i(e.x, e.y)
		var b := Vector2i(e.z, e.w)
		if windows.has(e) or (a - b).length_squared() != 1:
			out.append({"a": a, "b": b, "window": windows.has(e)})
		elif a.y == b.y:
			horizontal[Vector2i(mini(a.x, b.x), a.y)] = true
		else:
			vertical[Vector2i(a.x, mini(a.y, b.y))] = true
	for start: Vector2i in horizontal.keys():
		if horizontal.has(start - Vector2i(1, 0)):
			continue
		var end := start
		while horizontal.has(end):
			end += Vector2i(1, 0)
		out.append({"a": start, "b": end, "window": false})
	for start: Vector2i in vertical.keys():
		if vertical.has(start - Vector2i(0, 1)):
			continue
		var end := start
		while vertical.has(end):
			end += Vector2i(0, 1)
		out.append({"a": start, "b": end, "window": false})
	return out

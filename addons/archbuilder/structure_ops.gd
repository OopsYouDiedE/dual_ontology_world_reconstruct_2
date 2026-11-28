@tool
extends RefCounted
## Editor operations shared by the plan tab, the 3D gizmo and the dock: undoable add,
## delete, duplicate, move and rotate in plan space, and "edit then commit" undo steps
## built from before/after snapshots of a node's saved properties.

const Wall := preload("res://tools/building_construction/BuildingConstruction/Walls/SmartWall3D.gd")
const FloorZone := preload("res://tools/building_construction/BuildingConstruction/Floors/SmartFloorZone3D.gd")
const Stair := preload("res://tools/building_construction/BuildingConstruction/Stairs/SmartStair3D.gd")
const Anchor := preload("res://scenes/components/structure/LevelAnchor3D.gd")
const Station := preload("res://scenes/components/structure/LevelStation3D.gd")
const Column := preload("res://scenes/components/structure/StructureColumn3D.gd")
const Arch := preload("res://scenes/components/structure/StructureArch3D.gd")
const Colonnade := preload("res://scenes/components/structure/Colonnade3D.gd")
const Assembly := preload("res://scenes/components/structure/StructureAssembly3D.gd")
const Trigger := preload("res://scenes/components/structure/LevelTrigger3D.gd")
const Mover := preload("res://scenes/components/structure/LevelMover3D.gd")
const Piece := preload("res://scenes/components/structure/StructurePiece3D.gd")

## Group (child of the structure) each kind of new node is filed under.
const GROUPS := {"wall": "Walls", "floor": "Floors", "anchor": "Anchors", "station": "Stations",
	"column": "Structure", "arch": "Structure", "colonnade": "Structure", "stair": "Stairs",
	"trigger": "Triggers", "mover": "Movers", "assembly": "Structure", "component": "Components"}

var plugin: EditorPlugin

func _init(p: EditorPlugin) -> void:
	plugin = p

func scene_root() -> Node:
	return EditorInterface.get_edited_scene_root()

func undo() -> EditorUndoRedoManager:
	return plugin.get_undo_redo()

# ── snapshots ─────────────────────────────────────────────────────────────────

static func snapshot(node: Object) -> Dictionary:
	var out := {}
	for prop in node.get_property_list():
		if prop.usage & PROPERTY_USAGE_STORAGE and prop.name not in ["script", "owner", "scene_file_path"]:
			var v = node.get(prop.name)
			out[prop.name] = v.duplicate(true) if (v is Array or v is Dictionary) else v
	return out

static func restore(node: Object, snap: Dictionary) -> void:
	for k in snap:
		if node.get(k) != snap[k]:
			node.set(k, snap[k])

## One undo step for edits already applied to `nodes` since `before` was taken.
func commit(action: String, nodes: Array, before: Array) -> void:
	var ur := undo()
	ur.create_action(action, UndoRedo.MERGE_DISABLE, scene_root())
	var any := false
	for i in nodes.size():
		var node: Object = nodes[i]
		if not is_instance_valid(node):
			continue
		var after := snapshot(node)
		for k in after:
			if not before[i].has(k) or after[k] != before[i][k]:
				ur.add_do_property(node, k, after[k])
				ur.add_undo_property(node, k, before[i].get(k))
				any = true
	ur.commit_action(false)
	if not any:
		pass

# ── plan-space helpers ────────────────────────────────────────────────────────

static func relative(structure: Node3D, node: Node3D) -> Transform3D:
	var xf := node.transform
	var p := node.get_parent()
	while p != null and p != structure:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf

## Transform from the node's parent space to structure space.
static func parent_to_structure(structure: Node3D, node: Node3D) -> Transform3D:
	return relative(structure, node) * node.transform.affine_inverse()

static func move_plan(structure: Node3D, node: Node3D, delta: Vector2) -> void:
	var p := parent_to_structure(structure, node)
	node.position += p.basis.inverse() * Vector3(delta.x, 0, delta.y)

## Rotate about a plan point (structure space), around the vertical axis.
static func rotate_plan(structure: Node3D, node: Node3D, centre: Vector2, angle: float) -> void:
	var p := parent_to_structure(structure, node)
	var c := Vector3(centre.x, 0, centre.y)
	var spin := Transform3D(Basis(Vector3.UP, angle), Vector3.ZERO)
	var world := Transform3D(Basis(), c) * spin * Transform3D(Basis(), -c) * relative(structure, node)
	node.transform = p.affine_inverse() * world

# ── structure tree ────────────────────────────────────────────────────────────

func group(structure: Node3D, title: String) -> Node3D:
	var g := structure.get_node_or_null(title) as Node3D
	if g == null:
		g = Node3D.new()
		g.name = title
		structure.add_child(g)
		g.owner = scene_root()
	return g

## Add `node` under the structure's group for `kind` at plan transform `at` (structure space).
func add(structure: Node3D, kind: String, node: Node3D, title: String, at := Transform3D.IDENTITY) -> Node3D:
	var parent := group(structure, GROUPS.get(kind, "Components"))
	node.name = title
	node.transform = relative(structure, parent).affine_inverse() * at
	var ur := undo()
	ur.create_action("添加%s" % title, UndoRedo.MERGE_DISABLE, scene_root())
	ur.add_do_method(parent, "add_child", node, true)
	ur.add_do_method(node, "set_owner", scene_root())
	ur.add_do_reference(node)
	ur.add_undo_method(parent, "remove_child", node)
	ur.commit_action()
	return node

func delete(nodes: Array) -> void:
	var ur := undo()
	ur.create_action("删除 %d 个节点" % nodes.size(), UndoRedo.MERGE_DISABLE, scene_root())
	for node: Node in nodes:
		var parent := node.get_parent()
		if parent == null:
			continue
		var owned: Array = [node] + node.find_children("*", "", true, false).filter(func(n): return n.owner == scene_root())
		ur.add_do_method(parent, "remove_child", node)
		ur.add_undo_method(parent, "add_child", node, true)
		ur.add_undo_method(parent, "move_child", node, node.get_index())
		for n in owned:
			ur.add_undo_method(n, "set_owner", scene_root())
		ur.add_undo_reference(node)
	ur.commit_action()

func duplicate(structure: Node3D, nodes: Array, offset: Vector2) -> Array:
	var out: Array = []
	var ur := undo()
	ur.create_action("复制 %d 个节点" % nodes.size(), UndoRedo.MERGE_DISABLE, scene_root())
	for node: Node3D in nodes:
		var copy := node.duplicate(Node.DUPLICATE_SIGNALS | Node.DUPLICATE_GROUPS | Node.DUPLICATE_SCRIPTS) as Node3D
		for child in copy.find_children("*", "", true, false):
			if Piece.is_generated(child) or child.has_meta(&"_structure_generated"):
				child.get_parent().remove_child(child)
				child.free()
		move_plan(structure, copy, offset)
		var parent := node.get_parent()
		ur.add_do_method(parent, "add_child", copy, true)
		ur.add_do_method(self, "_own_tree", copy)
		ur.add_do_reference(copy)
		ur.add_undo_method(parent, "remove_child", copy)
		out.append(copy)
	ur.commit_action()
	return out

func _own_tree(node: Node) -> void:
	node.owner = scene_root()
	for child in node.find_children("*", "", true, false):
		if not child.has_meta(&"_structure_generated") and child.owner == null:
			child.owner = scene_root()

# ── factories (plan coordinates in structure space) ───────────────────────────

static func at_plan(p: Vector2, y := 0.0) -> Transform3D:
	return Transform3D(Basis(), Vector3(p.x, y, p.y))

func add_wall(structure: Node3D, a: Vector2, b: Vector2, height := 2.75, thickness := 0.15) -> Node3D:
	var w: Node3D = Wall.new()
	w.grid_snap = 0.0
	w.start_point = Vector3.ZERO
	w.end_point = Vector3(b.x - a.x, 0, b.y - a.y)
	w.wall_height = height
	w.wall_thickness = thickness
	w.skirting_enabled = false
	return add(structure, "wall", w, "Wall", at_plan(a))

func add_floor(structure: Node3D, rect: Rect2) -> Node3D:
	var f: Node3D = FloorZone.new()
	var h := rect.size * 0.5
	f.polygon = PackedVector2Array([Vector2(-h.x, -h.y), Vector2(h.x, -h.y), Vector2(h.x, h.y), Vector2(-h.x, h.y)])
	f.floor_thickness = 0.15
	return add(structure, "floor", f, "Floor", at_plan(rect.get_center()))

func add_column(structure: Node3D, p: Vector2) -> Node3D:
	return add(structure, "column", Column.new(), "Column", at_plan(p))

func add_arch(structure: Node3D, a: Vector2, b: Vector2) -> Node3D:
	var arch: Node3D = Arch.new()
	arch.end_point = Vector3(b.x - a.x, 0, b.y - a.y)
	arch.rise = clampf(a.distance_to(b) * 0.55, 0.2, 6.0)
	return add(structure, "arch", arch, "Arch", at_plan(a))

func add_colonnade(structure: Node3D, a: Vector2, b: Vector2) -> Node3D:
	var c: Node3D = Colonnade.new()
	c.end_point = Vector3(b.x - a.x, 0, b.y - a.y)
	c.bays = maxi(1, roundi(a.distance_to(b) / 2.5))
	return add(structure, "colonnade", c, "Colonnade", at_plan(a))

func add_stair(structure: Node3D, a: Vector2, b: Vector2, rise := 3.0) -> Node3D:
	var s: Node3D = Stair.new()
	s.start_point = Vector3.ZERO
	s.end_point = Vector3(b.x - a.x, rise, b.y - a.y)
	return add(structure, "stair", s, "Stair", at_plan(a))

func add_trigger(structure: Node3D, rect: Rect2) -> Node3D:
	var t: Node3D = Trigger.new()
	t.size = Vector3(maxf(0.5, rect.size.x), 2.2, maxf(0.5, rect.size.y))
	return add(structure, "trigger", t, "Trigger", at_plan(rect.get_center()))

func add_station(structure: Node3D, rect: Rect2) -> Node3D:
	var s: Node3D = Station.new()
	s.footprint = Vector2(maxf(0.2, rect.size.x), maxf(0.2, rect.size.y))
	return add(structure, "station", s, "Station", at_plan(rect.get_center()))

func add_mover(structure: Node3D, rect: Rect2) -> Node3D:
	var m: Node3D = Mover.new()
	m.plan_size = Vector2(maxf(0.3, rect.size.x), maxf(0.3, rect.size.y))
	return add(structure, "mover", m, "Mover", at_plan(rect.get_center()))

func add_anchor(structure: Node3D, p: Vector2) -> Node3D:
	var a: Node3D = Anchor.new()
	a.anchor_id = "anchor"
	return add(structure, "anchor", a, "Anchor", at_plan(p))

## Wrap authored nodes into a new StructureAssembly3D at their centre (one undo step).
func group_into_assembly(structure: Node3D, nodes: Array) -> Node3D:
	if nodes.is_empty():
		return null
	var centre := Vector3.ZERO
	for n: Node3D in nodes:
		centre += relative(structure, n).origin
	centre /= float(nodes.size())
	centre.y = 0.0
	var parent := group(structure, "Structure")
	var assembly: Node3D = Assembly.new()
	assembly.name = "Assembly"
	assembly.transform = relative(structure, parent).affine_inverse() * Transform3D(Basis(), centre)
	var ur := undo()
	ur.create_action("组合为结构组", UndoRedo.MERGE_DISABLE, scene_root())
	ur.add_do_method(parent, "add_child", assembly, true)
	ur.add_do_method(assembly, "set_owner", scene_root())
	ur.add_do_reference(assembly)
	for n: Node3D in nodes:
		var old_parent := n.get_parent()
		var keep := relative(structure, n)
		var inside := Transform3D(Basis(), centre).affine_inverse() * keep
		var owned: Array = [n] + n.find_children("*", "", true, false).filter(func(c): return c.owner == scene_root())
		ur.add_do_method(old_parent, "remove_child", n)
		ur.add_do_method(assembly, "add_child", n, true)
		ur.add_do_property(n, "transform", inside)
		for c in owned:
			ur.add_do_method(c, "set_owner", scene_root())
		ur.add_undo_method(assembly, "remove_child", n)
		ur.add_undo_method(old_parent, "add_child", n, true)
		ur.add_undo_method(old_parent, "move_child", n, n.get_index())
		ur.add_undo_property(n, "transform", n.transform)
		for c in owned:
			ur.add_undo_method(c, "set_owner", scene_root())
	ur.add_undo_method(parent, "remove_child", assembly)
	ur.commit_action()
	return assembly

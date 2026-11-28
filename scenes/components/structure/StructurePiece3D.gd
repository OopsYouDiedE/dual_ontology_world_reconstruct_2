@tool
class_name StructurePiece3D
extends Node3D
## Base of every editable building piece (walls, floors, later doors, windows, stairs,
## columns, arches, triggers). One interface serves the 3D viewport, the 2D plan view
## and gameplay; 2D is only another view of the same node data.
##
## Update rule: a piece rebuilds its mesh once when something around it changes.
## - "Shape" = what neighbours may read (endpoints, outline, thickness, transform).
##   Changing it reaches the neighbours whose plan bounds touch, once per frame.
## - "Mesh" = what a piece builds from its shape and its neighbours' shapes.
##   Rebuilding a mesh never changes a shape, so neighbour updates stop after one hop.
## StructureRebuildQueue coalesces requests, skips unchanged inputs and caps the rounds.
## Neighbour propagation runs in the editor only; at runtime each piece builds once.
##
## Editing: the 3D viewport (gizmo handles, magnet to neighbour snap points while moving),
## the 2D plan tab (drag, grid snap) and the Inspector all write the same exported values.

const Queue := preload("res://scenes/components/structure/StructureRebuildQueue.gd")
## Set on generated helper nodes the editor adopts for click selection (never saved).
const GENERATED_META := &"_structure_generated"

## Generated (rebuilt, never saved) rather than authored in the scene.
static func is_generated(node: Node) -> bool:
	return node.owner == null or node.has_meta(GENERATED_META)

## Seconds-free hash of the inputs of the last build (shape + neighbour shapes).
var _built_inputs: int = 0
var _magnet_busy := false
## Movers posing their children (editor preview) switch the magnet off meanwhile.
static var magnet_suspended := false

func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_local_transform(true)
	rebuild()
	_built_inputs = input_hash()
	Queue.remember(self)
	# Editor: a newly placed piece lets the pieces around it re-check (unchanged ones skip).
	if Queue.editor_rules() and not has_meta(GENERATED_META):
		for n in neighbors():
			Queue.request(n, false, false)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_ENTER_TREE:
			Queue.invalidate(scope())
		NOTIFICATION_LOCAL_TRANSFORM_CHANGED:
			if Engine.is_editor_hint():
				shape_changed()
		NOTIFICATION_EXIT_TREE:
			var scope_node := scope()
			# Editor: neighbours that leaned on this piece (corner joins…) rebuild without it.
			# Deferred to the flush: when a whole scene leaves the tree (tab switch, close)
			# its scope is gone by then and nothing is queried or rebuilt.
			if Queue.editor_rules() and scope_node and not has_meta(GENERATED_META):
				Queue.removed(scope_node, self)
			Queue.invalidate(scope_node)

# ── overridable interface ─────────────────────────────────────────────────────

## Build mesh and collision now. Subclasses override; read neighbours through neighbors().
func rebuild() -> void:
	pass

## Shape parameters only (what neighbours may read). Transform is added automatically.
func shape_key() -> Array:
	return []

## Outline in plan space (scope-local XZ). Drives neighbour lookup and the 2D plan view.
func plan_outline() -> PackedVector2Array:
	return PackedVector2Array()

## Draggable points in plan space: [{id: StringName, position: Vector2}].
func plan_handles() -> Array:
	return []

func set_plan_handle(_id: StringName, _position: Vector2) -> void:
	pass

## Points other pieces snap to (wall endpoints, column centres…), plan space.
func snap_targets() -> PackedVector2Array:
	return PackedVector2Array()

## Extra reach when looking for neighbours (e.g. half a wall thickness).
func neighbor_margin() -> float:
	return 0.05

## Plan view: add a handle near this point (e.g. a floor vertex on an edge). True if added.
func plan_insert_handle(_position: Vector2) -> bool:
	return false

## Plan view: remove a handle (e.g. a floor vertex). True if removed.
func plan_remove_handle(_id: StringName) -> bool:
	return false

## Plan view colour family: floor, wall, column, arch, stair, trigger, station, mover, assembly, piece.
func plan_kind() -> String:
	return "piece"

## Height of a handle in local space (3D gizmo); default the node origin height.
func handle_height(_id: StringName) -> float:
	return 0.0

# ── change notification ───────────────────────────────────────────────────────

## Call from setters of shape parameters.
func shape_changed() -> void:
	if is_inside_tree():
		Queue.request(self, true, true)

## Call from setters of mesh-only parameters (materials, trims…): only this piece rebuilds.
func mesh_changed() -> void:
	if is_inside_tree():
		Queue.request(self, false, true)

# ── queries ───────────────────────────────────────────────────────────────────

## Nearest LevelStructure3D ancestor, else the parent. Plan space is this node's local XZ.
func scope() -> Node3D:
	var n := get_parent()
	while n != null:
		if n is LevelStructure3D:
			return n
		n = n.get_parent()
	return get_parent() as Node3D

## Transform from this piece to its scope (works outside the tree too).
func to_scope() -> Transform3D:
	var xf := transform
	var target := scope()
	var n := get_parent()
	while n != null and n != target:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

func to_plan(local_point: Vector3) -> Vector2:
	var p := to_scope() * local_point
	return Vector2(p.x, p.z)

func from_plan(plan_point: Vector2, local_y := 0.0) -> Vector3:
	var xf := to_scope()
	var y := (xf * Vector3(0, local_y, 0)).y
	return xf.affine_inverse() * Vector3(plan_point.x, y, plan_point.y)

func plan_bounds() -> Rect2:
	var outline := plan_outline()
	if outline.is_empty():
		var p := to_plan(Vector3.ZERO)
		return Rect2(p, Vector2.ZERO).grow(neighbor_margin())
	var r := Rect2(outline[0], Vector2.ZERO)
	for p in outline:
		r = r.expand(p)
	return r.grow(neighbor_margin())

## Pieces in the same scope whose plan bounds touch this one.
func neighbors() -> Array:
	if not is_inside_tree():
		return []
	return Queue.query(scope(), plan_bounds(), self)

## Hash of everything a build reads: own shape + transform, neighbours' shapes + transforms.
func input_hash() -> int:
	var parts: Array = [_shape_signature()]
	var others: Array = []
	for n in neighbors():
		others.append(n._shape_signature())
	others.sort()
	parts.append(others)
	return hash(var_to_str(parts))

func _shape_signature() -> String:
	return var_to_str([get_class(), name, to_scope(), shape_key()])

# ── magnet (editor moves) ─────────────────────────────────────────────────────

## While a piece is moved in the 3D viewport, pull it onto a neighbour's snap point when one
## of its own snap points comes within LevelStructure3D.editor_magnet metres.
func _magnet() -> void:
	var s := scope()
	var radius: float = s.get(&"editor_magnet") if s != null and s.get(&"editor_magnet") != null else 0.0
	var own := snap_targets()
	if radius <= 0.0 or own.is_empty() or not is_inside_tree():
		return
	var best := Vector2.ZERO
	var best_d := radius
	for n in Queue.query(s, plan_bounds().grow(radius), self):
		for t: Vector2 in n.snap_targets():
			for o: Vector2 in own:
				var d := o.distance_to(t)
				if d < best_d and d > 0.0005:
					best_d = d
					best = t - o
	if best == Vector2.ZERO:
		return
	var parent_to_scope := to_scope() * transform.affine_inverse()
	_magnet_busy = true
	position += parent_to_scope.basis.inverse() * Vector3(best.x, 0, best.y)
	_magnet_busy = false

# ── snapping helper (plan space) ──────────────────────────────────────────────

## Snap to the nearest target within radius, else to the grid (grid <= 0 disables it).
static func snap_point(p: Vector2, grid: float, targets: PackedVector2Array, radius := 0.3) -> Vector2:
	var best := p
	var best_d := radius
	for t in targets:
		var d := t.distance_to(p)
		if d < best_d:
			best_d = d
			best = t
	if best != p:
		return best
	return p.snappedf(grid) if grid > 0.0 else p

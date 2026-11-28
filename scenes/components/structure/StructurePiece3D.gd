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

const Queue := preload("res://scenes/components/structure/StructureRebuildQueue.gd")

## Seconds-free hash of the inputs of the last build (shape + neighbour shapes).
var _built_inputs: int = 0

func _ready() -> void:
	if Engine.is_editor_hint():
		set_notify_local_transform(true)
	rebuild()
	_built_inputs = input_hash()
	Queue.remember(self)
	# Editor: a newly placed piece lets the pieces around it re-check (unchanged ones skip).
	if Queue.editor_rules():
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
			if Queue.editor_rules() and scope_node and not scope_node.is_queued_for_deletion():
				for n in neighbors():
					if n != self:
						Queue.request(n, false, true)
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

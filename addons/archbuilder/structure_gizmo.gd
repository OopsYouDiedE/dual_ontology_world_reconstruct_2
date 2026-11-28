@tool
extends EditorNode3DGizmoPlugin
## 3D viewport handles for structure pieces: the same plan handles as the 2D tab (wall and
## arch ends, floor vertices, opening positions, column radius, trigger / station corners),
## dragged on the horizontal plane through the handle, snapped to the structure grid and to
## neighbours' snap points. The selected piece also shows its plan outline (and a mover its
## open pose). Every drag is one undo step.

const Ops := preload("res://addons/archbuilder/structure_ops.gd")
const Piece := preload("res://scenes/components/structure/StructurePiece3D.gd")
const Queue := preload("res://scenes/components/structure/StructureRebuildQueue.gd")

var ops
var _before := {}  # node instance id -> snapshot taken when a handle drag starts

func _init(o = null) -> void:
	ops = o
	create_material("outline", Color(1.0, 0.7, 0.28), false, true)
	create_material("ghost", Color(0.78, 0.6, 1.0, 0.9), false, true)
	create_handle_material("handles")

func _get_gizmo_name() -> String:
	return "StructurePiece"

func _get_priority() -> int:
	return 1

func _has_gizmo(node: Node3D) -> bool:
	return node is Piece and node.has_method("plan_handles")

func _selected(node: Node3D) -> bool:
	return node in EditorInterface.get_selection().get_selected_nodes()

## Plan point (scope space) at a local height → this node's local space.
func _local(node: Node3D, plan: Vector2, local_y: float) -> Vector3:
	var xf: Transform3D = node.to_scope()
	var y := (xf * Vector3(0, local_y, 0)).y
	return xf.affine_inverse() * Vector3(plan.x, y, plan.y)

func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var node := gizmo.get_node_3d()
	if not _selected(node):
		return
	var outline: PackedVector2Array = node.plan_outline()
	if outline.size() >= 2:
		var lines := PackedVector3Array()
		for i in outline.size():
			lines.append(_local(node, outline[i], 0.03))
			lines.append(_local(node, outline[(i + 1) % outline.size()], 0.03))
		gizmo.add_lines(lines, get_material("outline", gizmo))
	if node.has_method("plan_open_outline"):
		var ghost: PackedVector2Array = node.plan_open_outline()
		var gl := PackedVector3Array()
		for i in ghost.size():
			gl.append(_local(node, ghost[i], 0.05))
			gl.append(_local(node, ghost[(i + 1) % ghost.size()], 0.05))
		gizmo.add_lines(gl, get_material("ghost", gizmo))
	var handles: Array = node.plan_handles()
	if handles.is_empty():
		return
	var points := PackedVector3Array()
	var ids := PackedInt32Array()
	for i in handles.size():
		points.append(_local(node, handles[i].position, node.handle_height(handles[i].id)))
		ids.append(i)
	gizmo.add_handles(points, get_material("handles", gizmo), ids)

func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
	var handles: Array = gizmo.get_node_3d().plan_handles()
	return str(handles[handle_id].id) if handle_id < handles.size() else ""

func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> Variant:
	var handles: Array = gizmo.get_node_3d().plan_handles()
	return handles[handle_id].position if handle_id < handles.size() else Vector2.ZERO

func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, camera: Camera3D, screen_pos: Vector2) -> void:
	var node := gizmo.get_node_3d()
	var handles: Array = node.plan_handles()
	if handle_id >= handles.size():
		return
	var id: StringName = handles[handle_id].id
	if not _before.has(node.get_instance_id()):
		_before[node.get_instance_id()] = Ops.snapshot(node)
	var scope: Node3D = node.scope()
	if scope == null:
		return
	var s := scope.global_transform
	var h: Vector2 = handles[handle_id].position
	var xf: Transform3D = node.to_scope()
	var hy := (xf * Vector3(0, node.handle_height(id), 0)).y
	var plane := Plane(s.basis.y.normalized(), s * Vector3(h.x, hy, h.y))
	var hit = plane.intersects_ray(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos))
	if hit == null:
		return
	var local: Vector3 = s.affine_inverse() * hit
	var p := Vector2(local.x, local.z)
	var grid: float = scope.get(&"editor_grid") if scope.get(&"editor_grid") != null else 0.25
	if not Input.is_key_pressed(KEY_ALT):
		var targets := PackedVector2Array()
		for n in Queue.query(scope, Rect2(p, Vector2.ZERO).grow(1.0), node):
			targets.append_array(n.snap_targets())
		p = Piece.snap_point(p, grid, targets, 0.25)
	node.set_plan_handle(id, p)
	node.update_gizmos()

func _commit_handle(gizmo: EditorNode3DGizmo, _handle_id: int, _secondary: bool, _restore: Variant, cancel: bool) -> void:
	var node := gizmo.get_node_3d()
	var before: Dictionary = _before.get(node.get_instance_id(), {})
	_before.erase(node.get_instance_id())
	if before.is_empty():
		return
	if cancel:
		Ops.restore(node, before)
	elif ops != null:
		ops.commit("拖动手柄 %s" % node.name, [node], [before])
	node.update_gizmos()

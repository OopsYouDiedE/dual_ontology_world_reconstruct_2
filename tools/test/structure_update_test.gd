extends SceneTree
## StructurePiece3D update rule: a piece rebuilds once when something around it changes,
## requests coalesce per frame, unchanged inputs skip, chains stop instead of hanging.
## Plus the shared plan-view interface (outline, handles, snapping) for walls and floors.
## (Load/stress numbers live in a separate stress test, later.)

const Structure := preload("res://scenes/components/structure/LevelStructure3D.gd")
const Queue := preload("res://scenes/components/structure/StructureRebuildQueue.gd")
const Wall := preload("res://tools/building_construction/BuildingConstruction/Walls/SmartWall3D.gd")
const FloorZone := preload("res://tools/building_construction/BuildingConstruction/Floors/SmartFloorZone3D.gd")

## Pathological piece: every build moves its own shape, so it would ping-pong forever.
class Wobbler extends "res://scenes/components/structure/StructurePiece3D.gd":
	var size := 1.0
	var builds := 0
	func shape_key() -> Array: return [size]
	func plan_outline() -> PackedVector2Array:
		var p := to_plan(Vector3.ZERO)
		return PackedVector2Array([p, p + Vector2(size, 0), p + Vector2(size, size), p + Vector2(0, size)])
	func rebuild() -> void:
		builds += 1
		size += 0.01

var failed := 0
var counts := {}

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok:
		failed += 1

func _initialize() -> void:
	run.call_deferred()

func wall(parent: Node, title: String, a: Vector3, b: Vector3) -> Node3D:
	var w: Node3D = Wall.new()
	w.name = title
	w.grid_snap = 0.0
	w.start_point = a
	w.end_point = b
	w.wall_thickness = 0.2
	w.wall_height = 2.5
	w.skirting_enabled = false
	parent.add_child(w)
	counts[title] = 0
	w.wall_rebuilt.connect(func(): counts[title] += 1)
	return w

func mesh_x_range(w: Node3D) -> Vector2:
	var mesh: Mesh = w.get_node("VisualRoot/WallMesh").mesh
	var box := mesh.get_aabb()
	return Vector2(box.position.x, box.end.x)

func settle() -> void:
	await process_frame
	await process_frame

func reset_counts() -> void:
	for k in counts:
		counts[k] = 0

func run() -> void:
	Queue.force_editor_rules = true
	var s: Node3D = Structure.new()
	s.name = "S"
	root.add_child(s)
	var walls := Node3D.new()
	walls.name = "Walls"
	s.add_child(walls)
	# A runs along x 0..4 at z=0; B turns the corner at x=4 going +z; C stands far away.
	var a := wall(walls, "A", Vector3(0, 0, 0), Vector3(4, 0, 0))
	var b := wall(walls, "B", Vector3(4, 0, 0), Vector3(4, 0, 3))
	var c := wall(walls, "C", Vector3(20, 0, 20), Vector3(24, 0, 20))
	await settle()

	# Corner join
	var ra := mesh_x_range(a)
	check(is_equal_approx(ra.y, 4.1), "corner join: A's end reaches into B by half B's thickness (%.3f)" % ra.y)
	check(is_equal_approx(ra.x, 0.0), "free end of A is not extended (%.3f)" % ra.x)
	check(is_equal_approx(mesh_x_range(c).x, 20.0) and is_equal_approx(mesh_x_range(c).y, 24.0), "isolated wall C has no extension")
	check(a.neighbors().has(b) and not a.neighbors().has(c), "neighbours: A sees B, not far-away C")

	# Coalescing: ten edits in one frame -> one rebuild each for A and its neighbour B.
	reset_counts()
	for i in 10:
		a.wall_height = 2.5 + 0.05 * (i + 1)
	await settle()
	check(counts.A == 1, "ten shape edits in one frame rebuild A once (%d)" % counts.A)
	check(counts.B == 1, "neighbour B rebuilds once (%d)" % counts.B)
	check(counts.C == 0, "far wall C does not rebuild (%d)" % counts.C)

	# Mesh-only edit: only the piece itself.
	reset_counts()
	a.skirting_enabled = true
	await settle()
	check(counts.A == 1 and counts.B == 0, "mesh-only edit rebuilds A alone (A=%d B=%d)" % [counts.A, counts.B])

	# Moving A away: B (its former neighbour) rebuilds and A loses the corner extension.
	reset_counts()
	a.end_point = Vector3(4, 0, -6)
	a.start_point = Vector3(0, 0, -6)
	await settle()
	check(counts.B == 1, "former neighbour B rebuilds when A moves away (%d)" % counts.B)
	check(is_equal_approx(mesh_x_range(a).y, 4.0), "A no longer extends once apart (%.3f)" % mesh_x_range(a).y)
	check(not a.neighbors().has(b), "neighbour index follows the move")

	# Unchanged inputs skip.
	reset_counts()
	Queue.request(b, false, false)
	await settle()
	check(counts.B == 0, "a non-forced request with unchanged inputs is skipped")

	# Removing a neighbour: the remaining wall rebuilds without it.
	a.start_point = Vector3(0, 0, 0)
	a.end_point = Vector3(4, 0, 0)
	await settle()
	check(is_equal_approx(mesh_x_range(a).y, 4.1), "A joins B again after moving back")
	reset_counts()
	walls.remove_child(b)
	b.free()
	await settle()
	check(counts.A == 1 and is_equal_approx(mesh_x_range(a).y, 4.0), "deleting B rebuilds A without the join (A=%d, end %.3f)" % [counts.A, mesh_x_range(a).y])

	# Runaway chain: self-adjusting neighbours stop within the round cap, no hang.
	var w1 := Wobbler.new()
	var w2 := Wobbler.new()
	w2.position = Vector3(1.0, 0, 0)
	walls.add_child(w1)
	walls.add_child(w2)
	await settle()
	w1.builds = 0
	w2.builds = 0
	var capped_before: int = Queue.stats.get("capped", 0)
	w1.shape_changed()
	await settle()
	await settle()
	check(w1.builds <= 1 and w2.builds <= 1, "self-adjusting pieces rebuild at most once per flush (%d, %d)" % [w1.builds, w2.builds])
	check(Queue.stats.get("last_rounds", 0) <= Queue.MAX_ROUNDS, "chain stops within %d rounds (%d)" % [Queue.MAX_ROUNDS, Queue.stats.get("last_rounds", 0)])
	check(Queue.stats.get("capped", 0) > capped_before, "runaway chain is reported, not looped")
	check(Queue.pending() == 0, "queue is empty afterwards")

	# Plan-view interface.
	var handles: Array = a.plan_handles()
	check(handles.size() == 2 and handles[1].position == Vector2(4, 0), "wall exposes start/end plan handles")
	a.set_plan_handle(&"end", Vector2(6, 0))
	check(a.end_point == Vector3(6, 0, 0), "dragging the end handle moves the endpoint")
	check(a.plan_outline().size() == 4, "wall plan outline is its footprint rectangle")
	walls.position = Vector3(10, 0, 0)
	check(a.plan_handles()[0].position == Vector2(10, 0), "plan space is the structure's space (groups may move)")
	walls.position = Vector3.ZERO
	var f: Node3D = FloorZone.new()
	f.polygon = PackedVector2Array([Vector2(0, 0), Vector2(2, 0), Vector2(2, 2), Vector2(0, 2)])
	s.add_child(f)
	f.set_plan_handle(&"v2", Vector2(3, 3))
	check(f.polygon[2] == Vector2(3, 3), "floor vertex handle edits the polygon")
	check(a.snap_point(Vector2(5.9, 0.1), 0.25, a.snap_targets()) == Vector2(6, 0), "snap prefers a nearby endpoint")
	check(a.snap_point(Vector2(1.13, 2.9), 0.25, PackedVector2Array()) == Vector2(1.25, 3.0), "snap falls back to the grid")

	print("STRUCTURE_UPDATE_SUMMARY failed=%d" % failed)
	quit(0 if failed == 0 else 1)

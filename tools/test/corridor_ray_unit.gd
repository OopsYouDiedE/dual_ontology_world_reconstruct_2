extends SceneTree
## Synthetic collision/selection regression only: not game geometry or evidence.
const Check := preload("res://scenes/components/testing/CorridorRayCheck.gd")

class FakeFigure extends Node3D:
	var pose := "stand"
	func set_pose(value: String) -> void:
		pose = value

class FakeHost extends Control:
	var det_root: Node3D
	var det: FakeFigure
	var det_pos := Vector2.ZERO
	var cam: Camera3D

class FakeCorridor extends Node:
	var host: FakeHost
	var _root: Node3D
	var _npc: Dictionary = {}
	var _items: Array = []
	var _focus := Vector3.ZERO
	var _az := 0.0
	var _pitch := 0.0
	var _dist := 0.0
	func _item_pos(index: int) -> Vector2:
		return _items[index].pos
	func _camera_drive(_delta: float) -> void:
		host.cam.position = Vector3(0.0, 1.7, 5.0)
		host.cam.look_at(Vector3(0.0, 1.7, 0.0), Vector3.UP)

var tests := 0
var failures := 0

func _initialize() -> void:
	_run.call_deferred()

func check(name: String, condition: bool) -> void:
	tests += 1
	print(("PASS " if condition else "FAIL ") + name)
	if not condition: failures += 1

func box(parent: Node3D, name: String, size: Vector3, position: Vector3) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = name
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.position = position
	parent.add_child(mesh)
	return mesh

func _run() -> void:
	print("SYNTHETIC TEST FIXTURE: NOT GAME GEOMETRY OR ACCEPTANCE")
	var host := FakeHost.new()
	root.add_child(host)
	var world := Node3D.new()
	host.add_child(world)
	host.det_root = Node3D.new()
	world.add_child(host.det_root)
	host.det = FakeFigure.new()
	host.det_root.add_child(host.det)
	host.cam = Camera3D.new()
	world.add_child(host.cam)
	host.cam.position = Vector3(1, 2, 5)
	var old_camera := host.cam.global_transform
	var corridor := FakeCorridor.new()
	host.add_child(corridor)
	corridor.host = host
	corridor._root = Node3D.new()
	world.add_child(corridor._root)
	var window := box(corridor._root, "SyntheticWindow", Vector3(0.9, 0.9, 0.06), Vector3(0, 1.7, 0.03))
	var blocker := box(corridor._root, "SyntheticBlocker", Vector3(0.6, 0.6, 0.1), Vector3(0, 1.7, 2.5))
	var marker := Node3D.new()
	corridor._root.add_child(marker)
	box(marker, "SyntheticMarker", Vector3(0.4, 0.4, 0.1), Vector3(0, 1.7, 4.0))
	corridor._items = [{"id":"window", "pos":Vector2.ZERO, "marker":marker},
		{"id":"gate", "pos":Vector2.ZERO}, {"id":"kitchen", "pos":Vector2.ZERO}]
	var probe := Check.new()
	probe.begin(host, corridor)
	check("setup created visible-mesh proxies only", probe.proxies.size() == 2 and probe.errors.is_empty())
	check("original fixture has no physics bodies", probe.summary().original_stage_physics_body_count == 0)
	blocker.visible = false
	var clear: Dictionary = await probe.probe(0, Vector2(1, 1))
	print("SYNTHETIC CLEAR ", JSON.stringify(clear))
	check("original camera hits selected target", bool(clear.get("pass", false)))
	check("hit refers to original target mesh", str(clear.get("first_hit_original_mesh", "")) == str(window.get_path()))
	check("original camera path retained", str(clear.get("camera_path", "")) == str(host.cam.get_path()))
	blocker.visible = true
	var occluded: Dictionary = await probe.probe(0, Vector2(1, 1))
	print("SYNTHETIC OCCLUDED ", JSON.stringify(occluded))
	check("intervening original mesh blocks target", not bool(occluded.get("pass", true)) and str(occluded.get("first_hit_original_mesh", "")) == str(blocker.get_path()))
	var gate: Dictionary = await probe.probe(1, Vector2(1, 1))
	var kitchen: Dictionary = await probe.probe(2, Vector2(1, 1))
	check("gate target is not invented", gate.get("status") == "original_interaction_object_not_identifiable" and gate.get("pass") == null)
	check("kitchen target is not invented", kitchen.get("status") == "original_interaction_object_not_identifiable" and kitchen.get("pass") == null)
	var duplicate := box(corridor._root, "DuplicateSyntheticWindow", Vector3(0.9, 0.9, 0.06), Vector3(0, 1.7, 0.03))
	var ambiguous := probe._target(0)
	check("ambiguous target fails closed", ambiguous.get("status") == "original_target_not_unique" and ambiguous.get("candidate_count") == 2)
	duplicate.queue_free()
	probe.cleanup()
	check("original camera restored", host.cam.global_transform.is_equal_approx(old_camera))
	host.queue_free()
	await process_frame
	print("SYNTHETIC RESULT tests=", tests, " failures=", failures, " acceptance_eligible=false")
	quit(0 if failures == 0 else 1)

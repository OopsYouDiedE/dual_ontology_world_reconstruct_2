extends SceneTree
## Synthetic test-only geometry for the corridor navigation adapter. Nothing
## here is a game screenshot, production fixture, or acceptance result.
const Check := preload("res://scenes/components/testing/CorridorNavigationCheck.gd")

class FakeHost extends Control:
	const ACTOR_RADIUS := 0.68
	const ACTOR_FURNITURE_MARGIN := 0.78
	const ACTOR_WALL_MARGIN := 0.84
	const ACTOR_MIN_DISTANCE := 1.52
	var det_root: Node3D

class FakeCorridor extends Node:
	var _root: Node3D
	var _npc: Dictionary = {}
	var _items: Array = []

var failures := 0
var tests := 0

func _initialize() -> void:
	_run.call_deferred()

func check(name: String, condition: bool) -> void:
	tests += 1
	print(("PASS " if condition else "FAIL ") + name)
	if not condition: failures += 1

func _make_stage(with_wall: bool) -> Dictionary:
	var host := FakeHost.new()
	root.add_child(host)
	host.det_root = Node3D.new()
	host.add_child(host.det_root)
	var corridor := FakeCorridor.new()
	host.add_child(corridor)
	corridor._root = Node3D.new()
	host.add_child(corridor._root)
	var npc := Node3D.new()
	corridor._root.add_child(npc)
	npc.position = Vector3(4, 0, 4)
	corridor._npc["synthetic"] = npc
	if with_wall:
		var obstacle := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.3, 1.0, 8.0)
		obstacle.mesh = box
		obstacle.position = Vector3(4.0, 0.5, 4.0)
		corridor._root.add_child(obstacle)
	return {"host": host, "corridor": corridor}

func _run() -> void:
	print("SYNTHETIC TEST FIXTURE: NOT GAME GEOMETRY OR ACCEPTANCE")
	var adapter := Check.new()
	var rect := Rect2(2, 2, 1, 1)
	check("segment intersects proxy", adapter._segment_intersects_rect(Vector2(1, 2.5), Vector2(4, 2.5), rect))
	check("segment avoids proxy", not adapter._segment_intersects_rect(Vector2(1, 1), Vector2(4, 1), rect))
	check("segment inside proxy", adapter._segment_intersects_rect(Vector2(2.5, 2.5), Vector2(4, 4), rect))
	var fixture := _make_stage(false)
	var host: FakeHost = fixture.host
	var corridor: FakeCorridor = fixture.corridor
	adapter.begin(host, corridor, Rect2(0, 0, 8, 8))
	check("no empty nav mesh", adapter.errors.is_empty() and adapter.free_cells > 0)
	check("NPC exclusion includes cell radius", not adapter._polygon_clear(Vector2(4, 5.6)))
	check("distant cell remains free", adapter._polygon_clear(Vector2(1, 1)))
	var straight := PackedVector3Array([Vector3(1, 0, 4), Vector3(7, 0, 4)])
	check("straight path crossing NPC fails", not adapter._path_clearance(straight).npc_clearance_pass)
	var detour: Dictionary = await adapter.probe(Vector2(1, 4), Vector2(7, 4))
	print("SYNTHETIC DETOUR ", JSON.stringify(detour))
	check("agent navigates around NPC", bool(detour.get("pass", false)))
	check("server route clears NPC", not detour.get("navigation_path", []).is_empty() and bool(detour.get("server_path_clearance", {}).get("npc_clearance_pass", false)))
	check("agent route clears NPC", not detour.get("agent_path", []).is_empty() and bool(detour.get("agent_path_clearance", {}).get("npc_clearance_pass", false)))
	adapter.cleanup()
	host.queue_free()
	await process_frame
	var blocked_fixture := _make_stage(true)
	var blocked_host: FakeHost = blocked_fixture.host
	var blocked_corridor: FakeCorridor = blocked_fixture.corridor
	var blocked := Check.new()
	blocked.begin(blocked_host, blocked_corridor, Rect2(0, 0, 8, 8))
	check("visible wall becomes one test-only proxy", blocked.obstacles.size() == 1)
	check("wall blocks straight segment", not blocked._path_clearance(straight).static_proxy_clearance_pass)
	var outcome: Dictionary = await blocked.probe(Vector2(1, 4), Vector2(7, 4))
	print("SYNTHETIC BLOCK ", JSON.stringify(outcome))
	check("spanning obstacle prevents navigation", not bool(outcome.get("pass", true)))
	check("blocked-map endpoints are valid", bool(outcome.get("start_on_mesh", false)) and bool(outcome.get("destination_on_mesh", false)))
	check("spanning obstacle does not claim target reached", not bool(outcome.get("server_reaches_target", true)))
	blocked.cleanup()
	blocked_host.queue_free()
	await process_frame
	print("SYNTHETIC RESULT tests=", tests, " failures=", failures, " acceptance_eligible=false")
	quit(0 if failures == 0 else 1)

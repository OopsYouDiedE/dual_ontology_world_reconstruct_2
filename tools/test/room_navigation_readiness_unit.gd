extends SceneTree
## Synthetic NavigationServer publication test. Not room evidence or acceptance.
const Check := preload("res://scenes/components/testing/RoomFastCheck.gd")
class DummyHost extends Control:
	const CELL := 0.3
var tests := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	tests += 1
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	print("SYNTHETIC NAVIGATION PUBLICATION FIXTURE: NOT GAME ACCEPTANCE")
	var checker := Check.new()
	check(not checker.navigation_readiness().ready, "missing navigation objects fail closed")
	var host := DummyHost.new()
	root.add_child(host)
	checker.host = host
	checker.grid = AStarGrid2D.new()
	checker.grid.region = Rect2i(0,0,2,2)
	checker.grid.cell_size = Vector2(0.3,0.3)
	checker.grid.update()
	var nav_root := Node3D.new()
	root.add_child(nav_root)
	checker.region = NavigationRegion3D.new()
	nav_root.add_child(checker.region)
	checker.nav_map = NavigationServer3D.map_create()
	NavigationServer3D.map_set_active(checker.nav_map, true)
	NavigationServer3D.map_set_cell_size(checker.nav_map, 0.3)
	checker.region.set_navigation_map(checker.nav_map)
	for i in 4: await physics_frame
	check(not checker.navigation_readiness().ready, "empty region is not a published polygon mesh")
	checker.region.queue_free()
	await process_frame
	checker.region = NavigationRegion3D.new()
	nav_root.add_child(checker.region)
	var mesh := NavigationMesh.new()
	mesh.cell_size = 0.3
	var vertices := PackedVector3Array()
	var polygons := []
	for x in 2:
		for z in 2:
			var index := vertices.size()
			vertices.append(Vector3(x*0.3,0,z*0.3))
			vertices.append(Vector3(x*0.3,0,(z+1)*0.3))
			vertices.append(Vector3((x+1)*0.3,0,(z+1)*0.3))
			vertices.append(Vector3((x+1)*0.3,0,z*0.3))
			polygons.append(PackedInt32Array([index,index+1,index+2]))
			polygons.append(PackedInt32Array([index,index+2,index+3]))
	mesh.vertices = vertices
	for polygon in polygons: mesh.add_polygon(polygon)
	checker.region.navigation_mesh = mesh
	checker.region.set_navigation_map(checker.nav_map)
	NavigationServer3D.map_force_update(checker.nav_map)
	var readiness: Dictionary = checker.navigation_readiness()
	var waited := 0
	var wait_started := Time.get_ticks_usec()
	while not readiness.ready and Time.get_ticks_usec() - wait_started < 1500000:
		await physics_frame
		waited += 1
		readiness = checker.navigation_readiness()
		if not readiness.ready: OS.delay_msec(2)
	check(bool(readiness.ready), "published mesh projects a free cell")
	check(bool(readiness.owner_matches_region), "projected polygon belongs to this test region")
	check(readiness.probe.size() == 3 and readiness.nearest.size() == 3, "readiness records the tested and projected positions")
	for x in 2:
		for z in 2: checker.grid.set_point_solid(Vector2i(x,z), true)
	var no_cells: Dictionary = checker.navigation_readiness()
	check(not no_cells.ready and no_cells.reason == "no_free_navigation_cells", "all-solid navigation grid cannot pass")
	var owned_map := checker.nav_map
	checker.nav_map = RID()
	check(not checker.navigation_readiness().ready, "invalid map cannot pass")
	print("SYNTHETIC NAVIGATION RESULT " + JSON.stringify({"tests":tests,"failures":failures,"waited_frames":waited,"waited_ms":(Time.get_ticks_usec()-wait_started)/1000.0,"readiness":readiness,"acceptance_eligible":false}))
	nav_root.queue_free()
	host.queue_free()
	await process_frame
	NavigationServer3D.free_rid(owned_map)
	quit(0 if failures == 0 else 1)

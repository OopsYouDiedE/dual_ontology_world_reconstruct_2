extends SceneTree
## Headless regression check for the building editor.
## Run: godot --headless --path <project> --script res://tools/building_construction/tests/check_rooms.gd
const State = preload("res://tools/building_construction/ArchitectState.gd")
const Wall = preload("res://tools/building_construction/BuildingConstruction/Walls/WallPathGeometry.gd")
const Floor = preload("res://tools/building_construction/BuildingConstruction/Floors/ArchitectFloor.gd")
const Stair = preload("res://tools/building_construction/BuildingConstruction/Stairs/ArchitectStair.gd")
const Railing = preload("res://tools/building_construction/BuildingConstruction/Railings/ArchitectRailing.gd")
const Props = preload("res://tools/building_construction/BuildingConstruction/Props/ArchitectProps.gd")

func count_nodes(node: Node) -> int:
	var total = 1
	for child in node.get_children(): total += count_nodes(child)
	return total

func count_meshes(node: Node) -> int:
	var total = 1 if node is MeshInstance3D else 0
	for child in node.get_children(): total += count_meshes(child)
	return total

func _init() -> void:
	var rooms = JSON.parse_string(FileAccess.get_file_as_string("res://tools/building_construction/architect_rooms.json"))
	var totals = {"rooms":0,"derived":0,"nodes":0,"meshes":0,"prop_nodes":0,"prop_meshes":0,"usec":0,"failures":0}
	for room in rooms:
		var state = State.new()
		if not state.restore(JSON.stringify(room)):
			print("FAIL restore ", room.id); totals.failures += 1; continue
		var t0 = Time.get_ticks_usec()
		state.sync_rooms()
		var nodes = 0
		var meshes = 0
		var prop_nodes = 0
		var prop_meshes = 0
		var derived = 0
		for layer in state.data.layers:
			derived += layer.get("roomFaces",[]).size()
			var built = Floor.build(layer); nodes += count_nodes(built); meshes += count_meshes(built); built.free()
		for wall in state.data.walls:
			var built = Wall.build(wall); nodes += count_nodes(built); meshes += count_meshes(built); built.free()
		for item in state.data.stairs:
			var built = Stair.build(item); nodes += count_nodes(built); meshes += count_meshes(built); built.free()
		for item in state.data.railings:
			var built = Railing.build(item); nodes += count_nodes(built); meshes += count_meshes(built); built.free()
		for item in state.data.props:
			var built = Props.build(item); prop_nodes += count_nodes(built); prop_meshes += count_meshes(built); built.free()
		var usec = Time.get_ticks_usec()-t0
		totals.rooms += 1; totals.derived += derived; totals.nodes += nodes; totals.meshes += meshes
		totals.prop_nodes += prop_nodes; totals.prop_meshes += prop_meshes; totals.usec += usec
		print("%-18s derived=%d nodes=%d meshes=%d prop_nodes=%d prop_meshes=%d %.0fms" % [room.id,derived,nodes,meshes,prop_nodes,prop_meshes,usec/1000.0])
	print("TOTAL ", totals)
	quit(1 if totals.failures>0 else 0)

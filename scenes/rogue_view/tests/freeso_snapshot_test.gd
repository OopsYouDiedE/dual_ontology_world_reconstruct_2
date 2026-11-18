extends SceneTree

const Importer := preload("res://scenes/rogue_view/FreeSoSnapshot.gd")
const Room := preload("res://scenes/rogue_view/RogueRoomView.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Synthetic format/geometry fixture; never packaged as a lot or loaded by gameplay.
	var fixture := {
		"schema": "freeso.lot-snapshot.v1", "source": {"kind": "fsov"},
		"lot": {"width": 8, "height": 6, "stories": 2, "floors": [],
			"walls": [{"x": 1, "y": 1, "level": 1, "mask": 63}, {"x": 2, "y": 1, "level": 1, "mask": 1}, {"x": 5, "y": 2, "level": 2, "mask": 2}]},
		"avatars": [{"object_id":1,"x16":29,"y16":43,"level":1,"placed":true}, {"object_id":2,"x16":47,"y16":61,"level":2,"placed":true}, {"object_id":3,"x16":-32768,"y16":-32768,"level":1,"placed":false}]
	}
	# Round trip JSON: Godot decodes integer-number fields as floats.
	var json: Variant = JSON.parse_string(JSON.stringify(fixture))
	var first := Importer.decode(json, 1)
	var second := Importer.decode(json, 2)
	var unsupported := fixture.duplicate(true)
	unsupported.schema = "unknown"
	var invalid := fixture.duplicate(true)
	invalid.lot.walls[0].mask = 64
	var view := Room.instantiate()
	var before_ready: Error = view.set_freeso_snapshot("Lot", ["Exit"], json, 2)
	root.add_child(view)
	var avatar_found := false
	for mesh in view.get_node("RoomViewport/Geometry").find_children("*", "MeshInstance3D", true, false):
		if mesh is MeshInstance3D and mesh.mesh is CapsuleMesh:
			avatar_found = mesh.position == Vector3(47.0 / 16.0, 0.44, 61.0 / 16.0)
	var results := {
		"valid floors": first.error == OK and second.error == OK,
		"all six distinct segments, shared edge deduplicated": first.lot.segments.size() == 6,
		"horizontal diagonal": Vector4i(1, 2, 2, 1) in first.lot.segments,
		"vertical diagonal": Vector4i(1, 1, 2, 2) in first.lot.segments,
		"other floor isolated": second.lot.segments == [Vector4i(5, 2, 6, 2)],
		"native sub-tile position and off-lot exclusion": first.lot.avatars == PackedVector2Array([Vector2(29, 43) / 16.0]),
		"unsupported version": Importer.decode(unsupported, 1).error == ERR_FILE_UNRECOGNIZED,
		"invalid wall": Importer.decode(invalid, 1).error == ERR_INVALID_DATA,
		"invalid floor": Importer.decode(json, 0).error == ERR_PARAMETER_RANGE_ERROR,
		"before-ready call": before_ready == OK and avatar_found,
		"snapshot title": view.get_node("RoomViewport/Title").text.begins_with("FreeSO VM snapshot"),
	}
	results["missing output"] = view.set_freeso_room("Fallback", [], "") == ERR_FILE_NOT_FOUND
	results["fallback title"] = view.get_node("RoomViewport/Title").text == "Topology navigation map\nFallback"
	var passed := true
	for label in results:
		if not results[label]:
			printerr("FAIL: " + label)
			passed = false
	if passed:
		print("FreeSO snapshot unit checks passed.")
	quit(0 if passed else 1)

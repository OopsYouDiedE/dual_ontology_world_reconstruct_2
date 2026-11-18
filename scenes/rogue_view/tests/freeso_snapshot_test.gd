extends SceneTree

const Importer := preload("res://scenes/rogue_view/FreeSoSnapshot.gd")
const Blueprint := preload("res://scenes/rogue_view/NativeBlueprint.gd")
const Room := preload("res://scenes/rogue_view/RogueRoomView.tscn")


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	# Synthetic format/geometry fixture; never packaged as a lot or loaded by gameplay.
	var fixture := {
		"schema": "freeso.lot-snapshot.v1", "source": {"kind": "fsov"},
		"lot": {"width": 8, "height": 6, "stories": 2, "floors": [],
			"walls": [{"x": 1, "y": 1, "level": 1, "mask": 63}, {"x": 2, "y": 1, "level": 1, "mask": 1}, {"x": 5, "y": 2, "level": 2, "mask": 2}]},
		"objects": [],
		"avatars": [{"object_id":1,"x16":29,"y16":43,"level":1,"placed":true}, {"object_id":2,"x16":47,"y16":61,"level":2,"placed":true}, {"object_id":3,"x16":-32768,"y16":-32768,"level":1,"placed":false}]
	}
	var base := {"object_id": 7, "persist_id": 0, "guid": 0x19ea4376, "master_guid": 0, "x16": 43, "y16": 55,
		"level": 2, "direction": 1, "container_object_id": 0, "placed": true, "hidden": false,
		"name": "Elgardian Single Bed", "heading_radians": 0.25, "group_id": 6, "group_base_object_id": 7}
	var part := base.duplicate()
	part.object_id = 6
	var hidden := base.duplicate()
	hidden.object_id = 8
	hidden.group_id = 8
	hidden.hidden = true
	fixture.objects = [part, base, hidden]
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
		"snapshot title": "FreeSO VM" in view._heading.text,
		"furnishing visibility and grouping": second.lot.objects.size() == 1 and second.lot.objects[0].position == Vector2(43,55) / 16.0 and second.lot.objects[0].yaw == -0.25,
	}
	results["missing output"] = view.set_freeso_room("Fallback", [], "") == ERR_FILE_NOT_FOUND
	results["fallback title"] = "no native lot available" in view._heading.text
	var xml := "res://content/academy_lots/foyer.xml"
	var authored := Blueprint.read(xml)
	var upper := Blueprint.read(xml, 2)
	results["authored foyer window"] = authored.error == OK and authored.lot.windows.has(Vector4i(7, 12, 7, 13)) and Vector4i(7, 12, 7, 13) in authored.lot.segments
	results["foyer gallery windows"] = upper.error == OK and upper.lot.windows.size() == 4
	view.set_instance_id("test_foyer")
	results["authored plan"] = view.set_blueprint_room("Foyer", ["Travel"], xml) == OK
	var player = view._player
	results["player starts inside entry"] = is_instance_valid(player) and player.position.is_equal_approx(Vector3(9.5, 0, 17.5))
	view.set_blueprint_room("Foyer", [], xml)
	for template in ["foyer", "kitchen", "living_hall", "lecture", "clinic", "dining", "valve_gallery", "service_stair"]:
		var imported := Blueprint.read("res://content/academy_lots/%s.xml" % template)
		results["authored %s has walls, floors, and objects" % template] = imported.error == OK and not imported.lot.floors.is_empty() and not imported.lot.segments.is_empty() and not imported.lot.objects.is_empty()
	results["same-room refresh preserves player"] = view._player == player and is_instance_valid(player)
	view.set_freeso_room("Foyer", [], "")
	results["missing VM keeps authored room"] = view._mode == "blueprint" and view._player == player
	var key := InputEventKey.new()
	key.physical_keycode = KEY_E
	var pad := InputEventJoypadButton.new()
	pad.button_index = JOY_BUTTON_A
	results["standard keyboard and controller binding"] = InputMap.event_is_action(key, "interact") and InputMap.event_is_action(pad, "interact")
	var passed := true
	for label in results:
		if not results[label]:
			printerr("FAIL: " + label)
			passed = false
	if passed:
		print("FreeSO snapshot unit checks passed.")
	quit(0 if passed else 1)

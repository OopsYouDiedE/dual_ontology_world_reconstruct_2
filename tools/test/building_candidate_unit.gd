extends SceneTree
const State := preload("res://tools/building_construction/ArchitectState.gd")
const Plan := preload("res://tools/building_construction/RoomPlan.gd")
const DisplayNames := preload("res://tools/building_construction/ArchitectDisplayNames.gd")
const Space := preload("res://scenes/components/life/BuildingSpace.gd")
var failures := 0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func _setup(data: Dictionary) -> RefCounted:
	var space := Space.new()
	space.setup(data)
	return space

func _run() -> void:
	var original := State.new()
	var rooms: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/building_construction/architect_rooms.json"))
	var han := RegEx.create_from_string("\\p{Han}")
	var english_names := true
	var names_intact := true
	for room in rooms:
		var authored := JSON.stringify(room)
		for item in [room] + room.layers + room.walls + room.stairs + room.railings + room.props:
			if han.search(DisplayNames.name_of(item)) != null: english_names = false
		if JSON.stringify(room) != authored: names_intact = false
		if room.id == "B-P": original.restore(authored)
	check(english_names and names_intact, "all shipped presets and components show English aliases without mutating the data")
	check(DisplayNames.english("Custom Studio") == "Custom Studio", "custom names stay intact")
	original.remember()
	var prior := JSON.stringify(original.data)
	var draft := original.fork_candidate()
	var layout := Plan.build(47,2)
	check(layout == Plan.build(47,2) and layout != Plan.build(48,2), "fixed seed reproduces the blueprint; new seed changes dimensions")
	check(draft.restore(JSON.stringify(layout)), "generated layout uses the existing wire format")
	check(JSON.stringify(original.data) == prior and original.history.size() == 1, "preview can be dropped without touching the existing B-P draft or history")
	var unrelated := State.new()
	check(not unrelated.accept_candidate(draft), "a candidate is bound to the state that opened it")
	check(original.accept_candidate(draft) and original.history.size() == 2, "whole generated plan commits in one undo step")
	var saved := JSON.stringify(original.data)
	check(not original.accept_candidate(draft), "an already-applied candidate cannot commit twice")
	check(original.undo(-1) and JSON.stringify(original.data) == prior, "undo restores the exact B-P draft")
	check(original.undo(1) and JSON.stringify(original.data) == saved, "redo restores the exact generated plan")
	var stale := original.fork_candidate()
	original.undo(-1)
	check(not original.accept_candidate(stale), "a candidate based on an older draft cannot replace current edits")

	var cases := 0
	for pairs in range(1,5):
		for seed_value in range(12):
			var sample := State.new()
			var decoded := sample.restore(JSON.stringify(Plan.build(seed_value,pairs)))
			var space := _setup(sample.data)
			var connected: Dictionary = space.room_access()
			if decoded and space.rooms.size() == 2*pairs+1 and connected == {"groups": 1, "unusable": 0, "grid_limit": false}: cases += 1
	check(cases == 48, "%d/48 seeded plans produce the expected connected rooms" % cases)

	var open_space := _setup(draft.data)
	check(open_space.is_solid_at(Vector2(0.0,-0.14)), "an exterior entry does not create unsupported walkable cells outside")
	var blocked: Dictionary = draft.data.duplicate(true)
	blocked.walls[1].openings[0].bottom = 0.5
	check(_setup(blocked).room_access().groups == 2, "raised door threshold does not connect two rooms")
	blocked.walls[1].openings[0].bottom = 0.0
	blocked.walls[1].openings[0].height = 1.0
	check(_setup(blocked).room_access().groups == 2, "a low opening does not connect two rooms")
	blocked.walls[1].openings[0].height = 2.25
	blocked.walls[1].openings[0].type = "rectangular_window"
	check(_setup(blocked).room_access().groups == 2, "a window does not connect two rooms")
	blocked.walls[1].openings[0].type = "portal_arch"
	blocked.walls.append(Plan.wall("test_cross_wall", [[-2,0,2.25],[0,0,2.25]], []))
	var overlap := _setup(blocked)
	check(overlap.is_solid_at(Vector2(-1.2,2.25)), "a portal does not clear the collision of a different wall")
	blocked.walls.pop_back()
	blocked.props.append({"id":"test_blocker","kind":"cabinet","x":-1.2,"z":2.25,"y":0.0,"yaw":0.0,"params":{}})
	check(_setup(blocked).is_solid_at(Vector2(-1.2,2.25)), "a portal does not clear furniture collision")
	await test_workbench(prior)
	quit(0 if failures == 0 else 1)

func test_workbench(kitchen: String) -> void:
	var editor: Control = load("res://tools/building_construction/BuildingSimulator.tscn").instantiate()
	root.add_child(editor)
	await process_frame
	await process_frame
	editor.state.restore(kitchen)
	editor.state.remember()
	editor.refresh()
	var wall_count: int = editor.state.data.walls.size()
	editor.set_tool("wall")
	editor.drawing = [[-3.4,-3.25,0.0],[3.4,-3.25,0.0]]
	editor.finish_path(false)
	check(editor.pending_build != null and editor.state.data.walls.size() == wall_count and editor.pending_build.layer().roomFaces.size() == 2,
		"workbench wall tool stages the kitchen partition and leaves the original untouched")
	if editor.pending_build != null: editor.close_build_preview(true,false)
	check(editor.state.data.walls.size() == wall_count + 1 and _setup(editor.state.data).room_access().groups == 2,
		"applying the kitchen partition creates two disconnected rooms")
	editor.opening_params = {"type":"portal_arch","width":1.35,"height":2.4,"bottom":0.0}
	editor.preview_opening(Vector2(1.65,-3.25))
	check(editor.pending_build != null and _setup(editor.pending_build.data).room_access().groups == 1,
		"workbench opening tool stages a real connection without merging the kitchen rooms")
	if editor.pending_build != null: editor.close_build_preview(false,false)
	check(_setup(editor.state.data).room_access().groups == 2 and editor.state.data.walls[-1].openings.is_empty(),
		"discard restores the sealed kitchen")
	var sealed := JSON.stringify(editor.state.data)
	var props: int = editor.state.data.props.size()
	editor.place_prop(Vector2(0.8, -2.0))
	check(editor.pending_build != null and editor.pending_build.data.props.size() == props + 1 and JSON.stringify(editor.state.data) == sealed,
		"manual furniture placement stages one item over the original kitchen")
	if editor.pending_build != null: editor.close_build_preview(false,false)
	check(JSON.stringify(editor.state.data) == sealed, "discard restores the exact kitchen after furniture placement")
	editor.furnish_clear.button_pressed = true
	editor.furnish_rooms([0])
	check(editor.pending_build != null and JSON.stringify(editor.state.data) == sealed,
		"auto-furnish stages both removal and placement without changing the kitchen")
	if editor.pending_build != null: editor.close_build_preview(true,false)
	check(JSON.stringify(editor.state.data) != sealed and editor.state.undo(-1) and JSON.stringify(editor.state.data) == sealed,
		"one undo rolls back the entire auto-furnish operation")
	editor.refresh()
	editor.spawn_stair()
	check(editor.pending_build != null and editor.pending_build.data.stairs.size() == editor.state.data.stairs.size() + 1,
		"stair geometry is staged in the editor before placement")
	if editor.pending_build != null: editor.close_build_preview(false,false)
	check(JSON.stringify(editor.state.data) == sealed, "discard leaves the original stair records intact")
	editor.queue_free()
	await process_frame

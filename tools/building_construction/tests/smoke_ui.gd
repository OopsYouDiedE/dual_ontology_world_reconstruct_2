extends SceneTree
## Drives the real editor scene: loads rooms, places/snaps furniture, auto-furnishes, edits, undoes.
## Run: godot --headless --path <project> --script res://tools/building_construction/tests/smoke_ui.gd
var failures = 0
var draws = 0
func check(name: String, ok: bool, detail := "") -> void:
	print(("PASS " if ok else "FAIL ")+name+("" if ok else "  "+detail))
	if not ok: failures += 1

func _init() -> void:
	var scene = load("res://tools/building_construction/BuildingSimulator.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await process_frame
	scene.blueprint.draw.connect(func(): draws += 1)
	# Load every shipped room through the UI path and redraw the 2D view.
	var started = Time.get_ticks_msec()
	for room in scene.rooms:
		check("load "+str(room.id),scene.state.restore(JSON.stringify(room)))
		scene.refresh()
	await process_frame
	await process_frame
	check("blueprint drew frames",draws>0,str(draws))
	print("load+rebuild all rooms: %d ms" % (Time.get_ticks_msec()-started))
	# Cached rebuild: nothing changed => nothing rebuilt.
	scene.state.restore(JSON.stringify(scene.rooms[1]))
	scene.refresh()
	var before = []
	for child in scene.candidates.get_children(): before.append(child.get_instance_id())
	scene.rebuild()
	var same = true
	for child in scene.candidates.get_children(): if not before.has(child.get_instance_id()): same = false
	check("unchanged rebuild reuses nodes",same and before.size()==scene.candidates.get_child_count())
	# Change one prop => only that part is rebuilt.
	var n_before = scene.candidates.get_child_count()
	scene.state.data.props[0].x += 0.5
	scene.rebuild()
	var replaced = 0
	for child in scene.candidates.get_children(): if not before.has(child.get_instance_id()): replaced += 1
	check("one edit rebuilds one part",replaced==1 and scene.candidates.get_child_count()==n_before,str(replaced))
	# Place a wall lantern near a wall via the placement path: should be on the wall face at lamp height.
	scene.state.restore(JSON.stringify(scene.rooms[1]))
	scene.refresh()
	var wall = scene.state.data.walls[0]
	var count_before = scene.state.data.props.size()
	scene.web_prop_kind = "wall_lantern"
	scene.refresh_prop_fields()
	scene.prop_entry = {}
	var p0 = Vector2(wall.points[0][0],wall.points[0][2])
	var p1 = Vector2(wall.points[1][0],wall.points[1][2])
	var mid = (p0+p1)*0.5
	var inward = (Vector2(0,0)-mid).normalized()
	scene.place_prop(mid+inward*0.3)
	var lantern = scene.state.data.props[-1]
	check("lantern added",scene.state.data.props.size()==count_before+1)
	check("lantern at mount height",absf(lantern.y-(scene.state.layer().y+2.2))<0.02,str(lantern.y))
	var d = Vector2(lantern.x,lantern.z)
	var dist = absf((d-p0).cross((p1-p0).normalized()))
	check("lantern flush to wall face",absf(dist-(wall.thickness*0.5+0.05))<0.05,"dist=%f"%dist)
	# Bookshelf snapping + footprint conflict flag.
	scene.web_prop_kind = "bookshelf"
	scene.refresh_prop_fields()
	scene.place_prop(mid+inward*0.5)
	var shelf = scene.state.data.props[-1]
	check("bookshelf faces into room",absf(Vector2(sin(deg_to_rad(shelf.yaw)),cos(deg_to_rad(shelf.yaw))).dot(inward))>0.5)
	scene.place_prop(Vector2(shelf.x,shelf.z))
	check("overlapping shelves flagged",scene.state.prop_conflicts().size()>=1)
	# Auto furnish through the UI function.
	scene.state.restore(JSON.stringify(scene.rooms[1]))
	scene.refresh()
	scene.furnish_template = "study"
	check("room list filled",scene.furnish_room.item_count>=1)
	var props_before = scene.state.data.props.size()
	scene.furnish_rooms([0])
	check("furnish ran",scene.furnish_report.text.begins_with("已布置"),scene.furnish_report.text)
	check("furnish produced no conflicts",scene.state.prop_conflicts().size()==0,str(scene.state.prop_conflicts()))
	check("undo after furnish",scene.state.undo(-1))
	scene.refresh()
	# Undo/redo of an edit.
	scene.nudge_selected(Vector2(0.1,0))
	scene.state.selected = {"kind":"prop","index":0}
	var x0 = scene.state.data.props[0].x
	scene.nudge_selected(Vector2(1,0))
	check("nudge moves prop",absf(scene.state.data.props[0].x-(x0+1.0))<0.001)
	scene.duplicate_selected()
	check("duplicate adds prop",scene.state.data.props.size()>=2)
	# Inspector builds for every selectable kind.
	for sel in [{"kind":"wall","wallIndex":0},{"kind":"wallNode","wallIndex":0,"ptIndex":1},{"kind":"prop","index":0},{"kind":"floorPoly","layerIndex":0,"polyIndex":0}]:
		scene.state.selected = sel
		scene.refresh_inspector()
	check("inspector has controls",scene.inspector.get_child_count()>3)
	# Native recipe prop inspector.
	scene.prop_entry = scene.catalog.items[0]
	for entry in scene.catalog.items:
		if str(entry.path).get_file().begins_with("Recipe"): scene.prop_entry = entry; break
	scene.prop_params = scene.prop_entry.get("defaults",{}).duplicate(true)
	scene.place_prop(Vector2(0,0))
	scene.refresh_inspector()
	await process_frame
	check("native recipe placed",scene.state.data.props[-1].kind=="native_recipe")
	# Wireframe + visibility paths.
	scene.wireframe = true
	scene.update_wireframe()
	scene.wireframe = false
	scene.update_wireframe()
	scene.show_visibility()
	await process_frame
	print("FAILURES ",failures)
	quit(1 if failures>0 else 0)

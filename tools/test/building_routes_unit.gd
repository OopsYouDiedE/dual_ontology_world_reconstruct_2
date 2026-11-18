extends SceneTree
const State := preload("res://tools/building_construction/ArchitectState.gd")
const Routes := preload("res://scenes/components/life/BuildingRoutes.gd")
const RULES := "res://assets/data/life_simulation/rules.dv"
const SCENARIO := "res://assets/data/scenarios/life_simulation.dv"
const SINK := "test_gallery_washstand"
const ACTOR := "detective"
var failures := 0

func _initialize() -> void: run.call_deferred()

func check(pass_check: bool, description: String) -> void:
	print(("PASS " if pass_check else "FAIL ") + description)
	if not pass_check: failures += 1

func run() -> void:
	var rooms: Array = JSON.parse_string(FileAccess.get_file_as_string("res://tools/building_construction/architect_rooms.json"))
	var authored: Dictionary = rooms.filter(func(room): return room.id == "F01")[0]
	var state := State.new()
	check(state.restore(JSON.stringify(authored)), "load the shipped F01 hall")
	var routes := Routes.new()
	var start := Vector3(0, 0, -4)
	var west := Vector3(-7.5, 4, -10)
	var east := Vector3(7.5, 4, -10)
	routes.setup(state.data, 0)
	check(routes.flights.size() == 3, "all three F01 stairs bind their authored floor landings: %s" % str(routes.rejected_stairs))
	var starts: Array[Vector3] = []
	for i in range(5):
		var stand := routes.spawn_near(start, starts)
		if stand.is_finite(): starts.append(stand)
	check(starts.size() == 5 and starts.all(func(point): return routes.floor_at(point) == routes.floor_at(starts[0])),
		"the five-member F01 roster has distinct, standable ground-floor starting positions")
	for target in [west, east]:
		var up := routes.find_route(start, target)
		var down := routes.find_route(target, start)
		check(not up.is_empty() and not down.is_empty(), "F01 reaches %s and returns" % str(target))
		if up.is_empty(): continue
		var heights: Array = up.path.map(func(p): return snappedf(p.y, 0.01))
		check(heights.has(0.0) and heights.has(2.0) and heights.has(4.0), "walk crosses the intermediate landing")
		check(is_equal_approx(up.length, Routes.path_length(start, up.path)), "reported length includes both 3D flights")
	check(routes.find_route(start, Vector3(0, 4, -8)).is_empty(), "no walking over the open upper void")
	check(not routes.find_route(Vector3(0, 1, -9.2), east).is_empty(), "a restored mid-flight position can continue")
	check(routes.find_route(Vector3(0.5, 1, -9.2), east).is_empty(), "a point in midair cannot snap to another floor")

	var copy := state.data.duplicate(true)
	copy.stairs.pop_front()
	routes.setup(copy, 0)
	check(routes.find_route(start, east).is_empty(), "removing the central stair disconnects the upper floors")
	copy = state.data.duplicate(true)
	copy.stairs[2].yaw = 90
	routes.setup(copy, 0)
	var alt := routes.find_route(start, east)
	check(routes.rejected_stairs.has("stair_F01_east_branch") and not alt.is_empty() and alt.path.any(func(p): return p.x < -6.0),
		"a misaligned east stair routes through the west stair and rear gallery")

	copy = state.data.duplicate(true)
	copy.railings.append({"points": [[-2.0, 2.0, -11.45], [2.0, 2.0, -11.45]], "height": 1.0})
	routes.setup(copy, 0)
	check(routes.rejected_stairs.has("stair_F01_central_flight") and routes.find_route(start, east).is_empty(), "blocked landing cannot be used")
	copy = state.data.duplicate(true)
	copy.walls.append({"baseY": 0.5, "height": 2.0, "thickness": 0.2,
		"points": [[-2.0, 0.5, -9.1], [2.0, 0.5, -9.1]], "openings": []})
	routes.setup(copy, 0)
	check(routes.rejected_stairs.has("stair_F01_central_flight"), "a wall crossing the middle of the flight blocks the link")
	test_bridge(state.data, start)
	quit(0 if failures == 0 else 1)

func test_bridge(building: Dictionary, start: Vector3) -> void:
	var fixture := building.duplicate(true)
	# Isolate the upstairs action; the geometry cases above retain all F01 furniture.
	fixture.props.clear()
	fixture.props.append({"id": SINK, "name": "Gallery Washstand", "kind": "wash_table", "x": 7.9, "y": 4.0, "z": -10.9, "yaw": 0.0, "params": {}})
	var scratch := "res://.runtime/flight-test-%d" % Time.get_ticks_usec()
	var rules_path := scratch + "-rules.dv"
	var scenario_path := scratch + "-scenario.dv"
	var save := scratch + "-save.json"
	var file := FileAccess.open(rules_path, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(RULES).replace('"thirst": 80', '"thirst": 0'))
	file.close()
	file = FileAccess.open(scenario_path, FileAccess.WRITE)
	file.store_string(FileAccess.get_file_as_string(SCENARIO).replace(RULES, rules_path))
	file.close()
	var bridge: Node = load("res://scenes/main/LifeBridge.cs").new()
	root.add_child(bridge)
	var opened: Dictionary = JSON.parse_string(bridge.Open(scenario_path, JSON.stringify(fixture), 47))
	check(opened.ok, "production life host opens a multilevel F01 candidate")
	if opened.ok:
		var rules: Dictionary = opened.definition
		var objects: Array = rules.objects.filter(func(obj): return obj.id == SINK)
		check(objects.size() == 1 and objects[0].y == 4.0 and objects[0].zone > 0, "upper washstand has its own elevation and zone in Core")
		var routes := Routes.new()
		routes.setup(rules.building, 0, rules.capacities)
		bridge.SetObjectRouteSpace3D(routes, rules.actions)
		bridge.Place(ACTOR, start.x, start.y, start.z, 0.0)
		var dispatch := {}
		for i in range(90):
			var frame: Dictionary = JSON.parse_string(bridge.Step(2.0))
			if frame.has("error"):
				check(false, frame.error)
				break
			for escape in frame.dispatch:
				if escape.actor == ACTOR and escape.meta.get("action", "") == "drink": dispatch = escape; break
			if not dispatch.is_empty(): break
		if dispatch.is_empty():
			print("ROUTE ", routes.plan_use(start, SINK, rules.actions.drink, 0))
			var seen: Dictionary = JSON.parse_string(bridge.Observe())
			var actor: Dictionary = seen.actors.filter(func(profile): return profile.id == ACTOR)[0]
			print("NO DRINK ", actor.needs, " choices ", actor.choices, " activity ", actor.activity)
		check(not dispatch.is_empty(), "thirst selects reachable upstairs drinking action through the 3D route probe")
		if not dispatch.is_empty():
			var route := routes.plan_use(start, SINK, rules.actions.drink, 0)
			var target: Vector3 = route.target
			var execution := int(dispatch.execution)
			check(bridge.SetTarget(execution, target.x, target.y, target.z, route.length, 2.4), "host accepts the upstairs target")
			var mid := Vector3(0, 1, -9.2)
			var resume_route := routes.find_route(mid, target)
			check(bridge.Progress(execution, mid.x, mid.y, mid.z, resume_route.length), "host accepts physical stair elevation")
			check(bridge.Save(save) == "" and bridge.Load(save) == "", "save made on the stairs reloads")
			var resume: Dictionary = JSON.parse_string(bridge.Observe())
			var profile: Dictionary = resume.actors.filter(func(actor): return actor.id == ACTOR)[0]
			check(is_equal_approx(profile.placement.Y, mid.y) and int(profile.activity.Execution) == execution, "reload preserves stair position and dispatch identity")
			check(bridge.Arrive(execution, target.x, 0.0, target.z) == false and bridge.Arrive(execution, target.x, target.y, target.z), "arrival uses physical height, and the correct arrival starts drinking")
		bridge.Close()
		var files := DirAccess.get_files_at(opened.audit_directory)
		for item in files: DirAccess.remove_absolute(str(opened.audit_directory).path_join(item))
		DirAccess.remove_absolute(opened.audit_directory)
	bridge.free()
	for path in [save, scenario_path, rules_path]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

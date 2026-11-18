extends SceneTree
## Production B-P geometry, with an experiment-only partition in copied layouts.
const State := preload("res://tools/building_construction/ArchitectState.gd")
const Space := preload("res://scenes/components/life/BuildingSpace.gd")
const PRESETS := "res://tools/building_construction/architect_rooms.json"
const SCENARIO := "res://assets/data/scenarios/life_simulation.dv"
const RULES := "res://assets/data/life_simulation/rules.dv"
const SINK := "prop_B_P_sink_01"
const START := Vector2(1.65, -0.8)
const SEED := 47
const ACTOR := "detective"
var failures := 0
var scratch: Array[String] = []

func _initialize() -> void: _run.call_deferred()

func check(ok: bool, label: String) -> void:
	print(("PASS " if ok else "FAIL ") + label)
	if not ok: failures += 1

func variant(source: Dictionary, door_x: Variant) -> Dictionary:
	var copy := source.duplicate(true)
	var openings := []
	if door_x != null:
		openings.append({"id": "test_internal_door", "segment": 0, "center": float(door_x) + 3.4,
			"width": 1.35, "height": 2.4, "bottom": 0.0, "type": "portal_arch"})
	copy.walls.append({"id": "test_kitchen_partition", "baseY": 0.0, "height": 3.7, "thickness": 0.28,
		"points": [[-3.4, 0.0, -3.25], [3.4, 0.0, -3.25]], "openings": openings})
	var candidate := State.new()
	if not candidate.restore(JSON.stringify(copy)):
		check(false, "candidate decodes")
		return {}
	return candidate.data

func alternate_scenario() -> String:
	var stamp := str(Time.get_ticks_usec())
	var rules_path := "res://.runtime/kitchen-utility-rules-" + stamp + ".dv"
	var scenario_path := "res://.runtime/kitchen-utility-scenario-" + stamp + ".dv"
	var baseline := FileAccess.get_file_as_string(RULES)
	var initial_thirst := '"thirst": 80'
	if baseline.count(initial_thirst) != 1:
		check(false, "exactly one initial thirst edit")
		return SCENARIO
	for entry in [[rules_path, baseline.replace(initial_thirst, '"thirst": 0')],
			[scenario_path, FileAccess.get_file_as_string(SCENARIO).replace(RULES, rules_path)]]:
		var file := FileAccess.open(entry[0], FileAccess.WRITE)
		if file == null:
			check(false, "write isolated fixture")
			return SCENARIO
		file.store_string(entry[1])
		file.close()
		scratch.append(entry[0])
	return scenario_path

func simulate(bridge_script: Script, building: Dictionary, scenario: String) -> Dictionary:
	var bridge: Node = bridge_script.new()
	root.add_child(bridge)
	var opened: Dictionary = JSON.parse_string(bridge.Open(scenario, JSON.stringify(building), SEED))
	if not opened.ok:
		check(false, "life bridge opens: " + str(opened.get("error", "")))
		bridge.free()
		return {}
	var rules: Dictionary = opened.definition
	var space := Space.new()
	space.setup(rules.building, 0, rules.capacities)
	bridge.SetObjectRouteSpace(space, rules.actions)
	bridge.Place(ACTOR, START.x, space.layer_y, START.y, 0.0)
	var route := space.plan_use(START, space.object_by_id[SINK], rules.actions.drink)
	var result := {"distance": route.get("length", INF), "action": "", "options": [],
		"arrived": false, "distance_cost": rules.reasoning.distance_per_m}
	# Sample the first choice, then exercise the physical adapter for a drink dispatch.
	for i in range(120):
		var frame: Dictionary = JSON.parse_string(bridge.Step(2.0))
		if frame.has("error"):
			check(false, "life step: " + str(frame.error))
			break
		for dispatch in frame.dispatch:
			if dispatch.actor != ACTOR: continue
			result.action = dispatch.meta.action
			result.options = dispatch.options
			if result.action == "drink" and not route.is_empty():
				result.arrived = follow_route(bridge, dispatch, space, route)
			break
		if result.action != "": break
	if result.action == "":
		var snapshot: Dictionary = JSON.parse_string(bridge.Observe())
		var actor: Dictionary = snapshot.actors.filter(func(profile): return profile.id == ACTOR)[0]
		print("NO DISPATCH: ", snapshot.time, " thirst ", actor.needs.thirst, " choices ", actor.choices, " activity ", actor.activity)
	bridge.free()
	var audit: String = opened.audit_directory
	for name in ["content.dv", "manifest.json", "final.json", "actions.jsonl", "outcomes.jsonl"]:
		var path := audit.path_join(name)
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(audit)
	return result

func follow_route(bridge: Node, dispatch: Dictionary, space: RefCounted, route: Dictionary) -> bool:
	var dest: Vector2 = route.point.approach
	var execution := int(dispatch.execution)
	if not bridge.SetTarget(execution, dest.x, space.layer_y, dest.y, route.length, 2.4): return false
	var previous := START
	for index in range(route.path.size()):
		var point: Vector2 = route.path[index]
		if space.is_solid_at(point) or not space.line_clear(previous, point): return false
		var remaining: float = space.path_length(point, route.path.slice(index + 1))
		if not bridge.Progress(execution, point.x, space.layer_y, point.y, remaining): return false
		previous = point
	return previous.is_equal_approx(dest) and bool(bridge.Arrive(execution, dest.x, space.layer_y, dest.y))

func drink_option(result: Dictionary) -> Dictionary:
	for option in result.get("options", []):
		if str(option.Action).ends_with(".drink." + SINK + ".0"): return option
	return {}

func drink_available(bridge: Node) -> bool:
	var observed: Dictionary = JSON.parse_string(bridge.Observe())
	for actor in observed.actors:
		if actor.id == ACTOR:
			return actor.choices.any(func(choice): return str(choice.id).ends_with(".drink." + SINK + ".0"))
	return false

func test_live_doors(bridge_script: Script, direct: Dictionary, scenario: String) -> void:
	const NEAR := "test_internal_door"
	const FAR := "test_detour_door"
	var fixture := direct.duplicate(true)
	fixture.walls[-1].openings[0].type = "closed_door"
	fixture.walls[-1].openings.append({"id": FAR, "segment": 0, "center": 1.75,
		"width": 1.35, "height": 2.4, "bottom": 0.0, "type": "double_door"})
	var bridge: Node = bridge_script.new()
	root.add_child(bridge)
	var opened: Dictionary = JSON.parse_string(bridge.Open(scenario, JSON.stringify(fixture), SEED))
	if not opened.ok:
		check(false, "bridge starts the B-P door fixture")
		bridge.free()
		return
	var rules: Dictionary = opened.definition
	var routes := preload("res://scenes/components/life/BuildingRoutes.gd").new()
	var from := Vector3(START.x, 0.0, START.y)
	routes.setup(rules.building, 0, rules.capacities)
	bridge.SetObjectRouteSpace3D(routes, rules.actions)
	bridge.Place(ACTOR, from.x, from.y, from.z, 0.0)
	var nearby := routes.plan_use(from, SINK, rules.actions.drink, 0)
	check(drink_available(bridge), "the sink action is available through the open route")
	var first := {}
	for step in range(120):
		var frame: Dictionary = JSON.parse_string(bridge.Step(2.0))
		for action in frame.get("dispatch", []):
			if action.actor == ACTOR and action.meta.action == "drink": first = action
		if not first.is_empty(): break
	check(not first.is_empty() and not nearby.is_empty(), "actor dispatches a drink across an open B-P door")
	bridge.Place(ACTOR, 1.65, 0.0, -3.25, 0.0)
	check(bridge.ChangeDoor(NEAR, "toggle") == "Someone is in the doorway." and routes.door_states.is_empty(),
		"door cannot close on someone in its threshold")
	bridge.Place(ACTOR, from.x, from.y, from.z, 0.0)
	check(bridge.ChangeDoor(NEAR, "toggle").is_empty(), "an unoccupied door closes")
	var around := routes.plan_use(from, SINK, rules.actions.drink, 0)
	check(not around.is_empty() and around.length > nearby.get("length", INF) + 3.0, "closing the near door immediately reroutes through the far door")
	if not first.is_empty() and not around.is_empty():
		var execution := int(first.execution)
		check(JSON.parse_string(bridge.Navigation()).any(func(action): return int(action.execution) == execution),
			"the in-progress execution remains available for replanning")
		check(bridge.SetTarget(execution, around.target.x, around.target.y, around.target.z, around.length, 2.4),
			"the in-progress execution accepts the replacement route")
	check(bridge.ChangeDoor(FAR, "lock").is_empty() and routes.plan_use(from, SINK, rules.actions.drink, 0).is_empty(),
		"locking the second door removes the last route and refreshes the probe")
	check(not drink_available(bridge), "closing the final route removes the sink action before arbitration")
	check(bridge.ChangeDoor(FAR, "toggle") == "Unlock the door before opening it.", "an open request cannot bypass a lock")
	var save := "res://.runtime/kitchen-doors-%d.json" % Time.get_ticks_usec()
	scratch.append(save)
	check(bridge.Save(save).is_empty() and bridge.ChangeDoor(NEAR, "toggle").is_empty() and bridge.Load(save).is_empty(),
		"the life bridge saves and reloads the door states without a declaration change")
	bridge.SetObjectRouteSpace3D(routes, rules.actions)
	check(routes.door_states == {NEAR: "closed", FAR: "locked"} and routes.plan_use(from, SINK, rules.actions.drink, 0).is_empty(),
		"loaded closed and locked doors still block the route")
	check(bridge.ChangeDoor(FAR, "lock").is_empty() and bridge.ChangeDoor(FAR, "toggle").is_empty() and not routes.plan_use(from, SINK, rules.actions.drink, 0).is_empty(),
		"unlocking then opening restores reachability")
	# Remove only the additive field; retain the old serializer's numeric types.
	var suffix := RegEx.new()
	suffix.compile(',"door_states":\\{[^}]*\\}\\}$')
	var saved := FileAccess.get_file_as_string(save)
	var legacy := suffix.sub(saved, "}")
	check(legacy != saved, "construct a legacy envelope without rewriting its runtime payload")
	var file := FileAccess.open(save, FileAccess.WRITE)
	file.store_string(legacy)
	file.close()
	check(bridge.Load(save).is_empty(), "a legacy envelope without door states loads")
	bridge.SetObjectRouteSpace3D(routes, rules.actions)
	check(routes.door_states.is_empty() and is_equal_approx(routes.plan_use(from, SINK, rules.actions.drink, 0).get("length", INF), nearby.get("length", -1.0)),
		"legacy envelopes retain the formerly open portals")
	bridge.free()
	var audit: String = opened.audit_directory
	for name in DirAccess.get_files_at(audit): DirAccess.remove_absolute(audit.path_join(name))
	DirAccess.remove_absolute(audit)

func _run() -> void:
	var presets: Array = JSON.parse_string(FileAccess.get_file_as_string(PRESETS))
	var original := State.new()
	for preset in presets:
		if preset.id == "B-P":
			check(original.restore(JSON.stringify(preset)), "load the shipped kitchen preset")
			break
	original.remember()
	var snapshot := JSON.stringify(original.data)
	check(original.layer().roomFaces.size() == 1, "production kitchen has one closed face")
	var direct := variant(original.data, 1.65)
	var detour := variant(original.data, -1.65)
	var sealed := variant(original.data, null)
	for entry in [["direct", direct], ["detour", detour], ["sealed", sealed]]:
		check(entry[1].layers[0].roomFaces.size() == 2, entry[0] + " produces the same two closed faces")
	check(direct.layers[0].roomFaces == detour.layers[0].roomFaces and detour.layers[0].roomFaces == sealed.layers[0].roomFaces,
		"door position and presence do not change geometry of the room faces")
	check(JSON.stringify(original.data) == snapshot and original.history.size() == 1,
		"discarding copied candidates leaves the source and undo history intact")
	var low := alternate_scenario()
	var bridge_script: Script = load("res://scenes/main/LifeBridge.cs")
	var a := simulate(bridge_script, direct, low)
	var b := simulate(bridge_script, detour, low)
	var c := simulate(bridge_script, sealed, low)
	var d := simulate(bridge_script, direct, SCENARIO)
	var a_drink := drink_option(a)
	var b_drink := drink_option(b)
	print("DIRECT   ", a.get("distance"), " | ", a.get("action"), " | drink score ", a_drink.get("Score"))
	print("DETOUR   ", b.get("distance"), " | ", b.get("action"), " | drink score ", b_drink.get("Score"))
	print("SEALED   ", c.get("distance"), " | ", c.get("action"))
	print("BASELINE ", d.get("distance"), " | ", d.get("action"))
	check(is_finite(a.distance) and b.distance > a.distance and is_finite(b.distance), "open detour adds real path length")
	var expected_delta: float = (b.distance - a.distance) * a.distance_cost
	var score_delta := float(a_drink.get("Score", 0.0)) - float(b_drink.get("Score", 0.0))
	check(not a_drink.is_empty() and not b_drink.is_empty() and absf(score_delta - expected_delta) < 0.01,
		"drink score difference matches extra routed metres times the configured cost")
	check(a.arrived and b.arrived, "the host accepts the validated direct and detour routes and starts the selected action")
	check(is_inf(c.distance) and c.action != "" and c.action != "drink" and drink_option(c).is_empty(),
		"sealed wall removes the drink option before scheduling")
	check(is_equal_approx(a.distance, d.distance) and a.action == "drink" and d.action != "" and d.action != "drink" and drink_option(d).is_empty(),
		"changing only initial thirst changes the first decision at the same layout")
	test_live_doors(bridge_script, direct, low)
	for path in scratch: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0 if failures == 0 else 1)

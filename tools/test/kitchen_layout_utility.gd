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
	for path in scratch: DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	quit(0 if failures == 0 else 1)

extends SceneTree
## Run with Godot --headless --path . --script res://tools/meniscus/verify.gd.
const Model = preload("res://scenes/physics_lab/meniscus/Model.gd")
const GOLDEN := "res://tools/meniscus/golden.json"

var _failures := 0
var _checks := 0


func _initialize() -> void:
	var started := Time.get_ticks_usec()
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	if not data is Dictionary or not data.get("scenarios") is Array or data.scenarios.size() != 2:
		printerr("Expected two golden scenarios in ", GOLDEN)
		quit(1)
		return
	for scenario: Dictionary in data.scenarios:
		_golden(scenario)
	_test_coupling_and_safe_trial()
	_test_retiring_span()
	_test_folded_mark(data.scenarios[0].steps)
	_test_early_stamp(data.scenarios[0].steps)
	_test_atomicity()
	print("A09: %d checks, %d failures, %.3f ms in headless runner" % [
		_checks, _failures, (Time.get_ticks_usec() - started) / 1000.0])
	quit(1 if _failures else 0)


func _check(condition: bool, message: String) -> void:
	_checks += 1
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)


func _subset(actual: Variant, expected: Variant, key: String) -> void:
	if expected is Dictionary and not expected.is_empty():
		if not actual is Dictionary:
			_check(false, key + " is not a dictionary")
			return
		for field: String in expected:
			_subset(actual.get(field), expected[field], key + "." + field)
	else:
		_check(actual == expected, "%s: expected %s, got %s" % [key, expected, actual])


func _ids(events: Array) -> Array:
	return events.map(func(event: Dictionary) -> String: return event.id)


func _golden(scenario: Dictionary) -> void:
	var started := Time.get_ticks_usec()
	var model := Model.new()
	var per_tick := Model.new()
	var seals := []
	var before := _failures
	for i in scenario.steps.size():
		var step: Array = scenario.steps[i]
		var label := "%s, input %d" % [scenario.name, i + 1]
		var command: Dictionary = step[0]
		var result := model.apply(command)
		_check(result.ok, "%s rejected: %s" % [label, result.reason])
		if step.size() > 1:
			_subset(result.state, step[1], label)
		if step.size() > 2:
			_check(_ids(result.events) == step[2], label + " event sequence")
		for event: Dictionary in result.events:
			if event.id == "seal_set": seals.append(event.tick)
		# A real 60 Hz consumer sees the same state and tick-stamped events as a batched wait.
		if command.action == "wait":
			var single_events := []
			for j in int(command.ticks):
				single_events.append_array(per_tick.apply({"action": "wait", "ticks": 1}).events)
			_check(single_events == result.events, label + " batched events differ from single ticks")
			_check(per_tick.snapshot() == result.state, label + " batched state differs from single ticks")
		else:
			_check(per_tick.apply(command) == result, label + " commands diverge")
	var terminal := model.snapshot()
	_check(terminal.tick == scenario.win_tick and terminal.outcome == "won" and seals.size() == 2, scenario.name + " terminal witness state")
	_check(model.apply({"action": "wait", "ticks": 600}).state == terminal, "terminal tick holds")
	print("GOLDEN %s: %s; seals=%s; exit=%d (%.2f s at 60 Hz); batched + single tick %.3f ms" % [
		scenario.name, "PASS" if before == _failures else "FAIL", seals, terminal.tick,
		terminal.tick / 60.0, (Time.get_ticks_usec() - started) / 1000.0])


func _do(model: RefCounted, action: String, arg: Variant = null) -> Dictionary:
	var command := {"action": action}
	if action == "wait": command.ticks = arg
	elif arg != null: command.target = arg
	var result: Dictionary = model.apply(command)
	_check(result.ok, "expected %s(%s) to succeed, got %s" % [action, arg, result.reason])
	return result


func _walk(model: RefCounted, room: String) -> Dictionary:
	_do(model, "move", room)
	return _do(model, "wait", Model.layout().move_ticks)


func _reject(model: RefCounted, command: Dictionary, reason: String) -> void:
	var before: Dictionary = model.snapshot()
	var result: Dictionary = model.apply(command)
	_check(not result.ok and result.reason == reason, "expected %s, got %s" % [reason, result.reason])
	_check(result.state == before and model.snapshot() == before and result.events.is_empty(), "rejected input mutated the run")


func _test_coupling_and_safe_trial() -> void:
	var map := Model.layout()
	var m := Model.new()
	var start := m.snapshot()
	_check(map.tick_hz == 60 and map.warning_ticks >= 40 and start.walk_edges == map.fixed_walk, "external reference and initial walk topology")
	_do(m, "cast", "south")
	var before: Dictionary = _do(m, "wait", 47).state
	_check(before.walk_edges == start.walk_edges and before.flow.paths == start.flow.paths and before.optics.direct == start.optics.direct, "preview leaves old form active")
	var commit := _do(m, "wait", 1)
	var cast: Dictionary = commit.state
	_check(commit.events.size() == 1 and commit.events[0].id == "cast_committed"
		and commit.events[0].tick == 48 and cast.tick == 48, "cast changes at announced tick")
	_check(cast.support.guide == cast.flow.guide and cast.flow.guide == cast.optics.guide
		and cast.optics.guide == cast.bubble.guide and cast.bubble.guide == map.guides.south.id, "four systems agree on guide identity")
	_check(cast.support.span == "south_span" and cast.walk_edges.has(["south_sill", "south_span"])
		and cast.walk_edges.has(["south_span", "south_pier"]) and not cast.walk_edges.has(["north_sill", "north_span"]), "south cast supplies both south support edges")
	_check(cast.flow.paths == [["feed", "south_diverter", "north_cistern"]] and cast.flow.head.north == 0
		and cast.optics.direct == ["lamp", "south_facet", "vane_axis", "south_receiver"], "flow and direct ray snap together; water arrives next tick")
	_check(cast.bubble.shuttle.phase == 0 and cast.bubble.shuttle.turns == 2 and cast.bubble.vane.phase == 48, "commit preserves old-form phase accumulation")
	var next: Dictionary = _do(m, "wait", 1).state
	_check(next.flow.head.north == 1 and next.bubble.shuttle.phase == 2 and next.bubble.vane.phase == 52, "first external tick under new flow and rate table")
	for path: Array in next.flow.paths + [next.optics.direct, next.optics.folded]:
		for port: String in path:
			_check(map.ports.has(port), "renderable named port " + port)
	# Same final detent and frame; one tick of different casting history changes real transmission.
	var later := Model.new()
	_do(later, "wait", 1)
	_do(later, "cast", "south")
	var early_state: Dictionary = _do(m, "wait", 8).state
	var late_state: Dictionary = _do(later, "wait", 56).state
	_check(early_state.tick == 57 and late_state.tick == 57 and early_state.walk_edges == late_state.walk_edges
		and early_state.flow.paths == late_state.flow.paths and early_state.optics.mark == late_state.optics.mark
		and early_state.optics.receiver == "" and late_state.optics.receiver == "south_receiver"
		and early_state.bubble.vane.phase == 84 and late_state.bubble.vane.phase == 83
		and early_state.bubble.shuttle.phase == 18 and late_state.bubble.shuttle.phase == 20, "same topology and glyph, different clock history and ray")
	print("PHASE COUNTEREXAMPLE tick 57: same South span and mark; vane 84 -> dump vs 83 -> receiver")


func _test_retiring_span() -> void:
	var m := Model.new()
	_do(m, "cast", "north")
	_do(m, "wait", 48)
	_walk(m, "north_sill")
	_walk(m, "north_span")
	_do(m, "cast", "liquid")
	var old := _do(m, "wait", 47)
	_check(old.state.form == "north" and old.state.tick == 119 and old.events.is_empty(), "48-tick support notice")
	var held := _do(m, "wait", 1)
	_check(held.state.pending.interlocked and held.state.support.span == "north_span" and _ids(held.events) == ["cast_held"], "occupied span holds thaw")
	_check(_do(m, "wait", 12).events.is_empty(), "hold event fires once")
	var cancelled := _do(m, "cancel")
	_check(cancelled.state.pending.is_empty() and cancelled.state.support.span == "north_span" and _ids(cancelled.events) == ["cast_cancelled"], "cancel after interlock")
	_do(m, "cast", "liquid")
	_do(m, "wait", 48)
	var cleared := _walk(m, "north_pier")
	_check(_ids(cleared.events) == ["walk_arrived", "cast_committed"] and cleared.state.tick == 192
		and cleared.state.pending.is_empty() and cleared.state.form == "liquid"
		and cleared.state.support.span == "" and cleared.state.optics.receiver == ""
		and cleared.state.flow.paths == [["feed", "liquid_bed", "return"]], "repeatable thaw applies only after full safe arrival")
	_reject(m, {"action": "move", "target": "north_span"}, "no_walk_edge")
	var inbound := Model.new()
	_do(inbound, "cast", "north")
	_do(inbound, "wait", 48)
	_do(inbound, "cast", "south")
	_walk(inbound, "north_sill")
	_do(inbound, "wait", 35)
	_do(inbound, "move", "north_span")
	var on_line := _do(inbound, "wait", 1)
	_check(on_line.state.tick == 96 and on_line.state.player.room == "north_sill"
		and on_line.state.player.travel.to == "north_span" and on_line.state.pending.interlocked, "inbound bridge travel also holds the cast")
	_do(inbound, "wait", 11)
	var recast := _walk(inbound, "north_pier")
	_check(recast.state.tick == 119 and recast.state.support.span == "south_span", "held recast releases on arrival")


func _prefix(steps: Array, count: int) -> RefCounted:
	var m := Model.new()
	for i in count:
		_check(m.apply(steps[i][0]).ok, "common replay input %d" % i)
	return m


func _test_folded_mark(steps: Array) -> void:
	var m := _prefix(steps, 12) # On North Pier at tick 180, true contact and undocked shuttle.
	_reject(m, {"action": "stamp"}, "shuttle_out_of_dock")
	var dark: Dictionary = _do(m, "wait", 12).state
	_check(dark.optics.mark == "north_mark" and dark.optics.receiver == "" and dark.stamp_checks.north.shuttle_docked, "projected glyph mimics a docked witness with dark contact")
	_reject(m, {"action": "stamp"}, "receiver_dark")
	var screened: Dictionary = _do(m, "screen").state
	_check(screened.tick == dark.tick and screened.bubble == dark.bubble and screened.flow == dark.flow
		and screened.optics.direct == dark.optics.direct and screened.optics.mark == ""
		and screened.optics.folded.back() == "north_fold_shutter", "shutter cuts only the comparison leg")
	_check(_do(m, "screen").state == dark, "comparison probe is repeatable without state cost")
	var backlit: Dictionary = _do(m, "wait", 36).state
	var proof: Dictionary = _do(m, "screen").state
	_check(proof.optics.receiver == backlit.optics.receiver and proof.optics.receiver == "north_receiver"
		and proof.optics.mark == "" and proof.stamp_checks.north.available, "screen removes copy while preserving true stamp")


func _test_early_stamp(steps: Array) -> void:
	var spent := _prefix(steps, 13) # Pre-stamp at tick 228, both runs on North Pier.
	var skipped := _prefix(steps, 13)
	_check(spent.snapshot() == skipped.snapshot(), "paired states start identical")
	_do(spent, "stamp")
	for run: RefCounted in [spent, skipped]:
		_do(run, "cast", "south")
		_walk(run, "gallery")
		_walk(run, "south_pier")
		_do(run, "wait", 126)
	var low: Dictionary = spent.snapshot()
	var full: Dictionary = skipped.snapshot()
	_check(low.tick == 378 and full.tick == low.tick and low.form == full.form and low.player == full.player
		and low.bubble == full.bubble and low.optics == full.optics and low.walk_edges == full.walk_edges, "equal future schedule and optics after one earlier decision")
	_check(low.flow.head == {"north": 96, "south": 26} and full.flow.head == {"north": 96, "south": 62}
		and low.stamp_checks.south.receiver_lit and low.stamp_checks.south.shuttle_docked
		and low.stamp_checks.south.coolant_ready and not low.stamp_checks.south.head_ready
		and full.stamp_checks.south.available, "earlier useful stamp spends head a later branch needs")
	_reject(spent, {"action": "stamp"}, "low_working_head")
	_do(skipped, "stamp")
	_do(spent, "cast", "north")
	_do(spent, "wait", 96)
	_do(spent, "cast", "south")
	_do(spent, "wait", 48)
	_reject(spent, {"action": "stamp"}, "low_coolant")
	_do(spent, "wait", 8)
	_do(spent, "stamp")
	_walk(spent, "gallery")
	var finish := _walk(spent, "exit")
	_check(finish.state.tick == 554 and finish.state.outcome == "won", "re-prime and recover in-place, keeping North seal")
	print("HYDRAULIC COUNTEREXAMPLE tick 378: same South contact and dock; prior North stamp -> 26 head, skipped -> 62; recovery exits at tick ", finish.state.tick)


func _test_atomicity() -> void:
	var m := Model.new()
	var layout := Model.layout()
	layout.guides.north.walk[0][0] = "changed"
	_check(Model.layout().guides.north.walk[0][0] == "north_sill", "layout copies nested arrays")
	for value: Variant in [null, false, 0, 601, 2.5, "12"]:
		_reject(m, {"action": "wait", "ticks": value}, "invalid_ticks")
	_reject(m, {"action": "cast", "target": "east"}, "unknown_form")
	_reject(m, {"action": "stamp"}, "wrong_pier")
	_reject(m, {"action": "move", "target": "exit"}, "no_walk_edge")
	_do(m, "move", "north_sill")
	_reject(m, {"action": "cast", "target": "north"}, "while_walking")
	_do(m, "wait", 12)
	var warning := _do(m, "cast", "north")
	warning.state.pending.target = "south"
	warning.events[0].due_tick = 0
	warning.state.walk_edges[0][0] = "changed"
	warning.state.flow.paths[0][0] = "changed"
	warning.state.flow.head.north = 96
	var valid := m.snapshot()
	_check(valid.pending.target == "north" and valid.pending.due_tick == 60
		and valid.walk_edges[0][0] == "dais" and valid.flow.paths[0][0] == "feed"
		and valid.flow.head.north == 0, "result snapshots and events are detached")
	_reject(m, {"action": "cast", "target": "south"}, "cast_pending")

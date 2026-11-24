extends SceneTree

const R = preload("res://scenes/physics_lab/palimpsest/PalimpsestRules.gd")
const FIXTURE := "res://tools/palimpsest/golden.json"
var failures := 0
var checks := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	if not fixture is Dictionary or fixture.get("schema") != "palimpsest.replay.v1":
		printerr("Invalid replay fixture: " + FIXTURE)
		quit(1)
		return
	var map := R.new().board()
	_check_board(map)
	_check_input(map)
	for test: Dictionary in fixture.cases:
		var first := _replay(test, true)
		var second := _replay(test, false)
		_check(first == second, test.id + ": preview and repeated replay have identical outcomes")
		print("REPLAY %s: %s / %s @ %d" % [test.id, first.phase, first.event.get("code", "-"), first.tick])
	var golden: Dictionary = fixture.cases[0]
	_check_ablations(golden, map)
	_check_incomplete_turn(map)
	_check_lift_cap_and_early_exit(map, golden)
	print("Palimpsest Switchyard: %d checks, %d failures." % [checks, failures])
	quit(0 if failures == 0 else 1)


func _check_board(map: Dictionary) -> void:
	_check(R.TICK_HZ == 60 and R.DECISION_TICKS == 20 and R.PREVIEW_TICKS >= 40, "clock contract")
	_check(map.bays.size() == map.width * map.height, "board dimensions")
	_check(map.start == 0 and map.lift_start == map.bays.size() - 1, "opposite corner docks")
	var turns := 0
	var exits := 0
	for bay: Dictionary in map.bays:
		_check(bay.id == bay.y * map.width + bay.x, "row-major bay %s" % bay.id)
		for deck in ["ink", "lift"]:
			var distinct := {}
			_check(bay[deck].size() == 3, "three physical sockets")
			for target: int in bay[deck]:
				_check(not distinct.has(target), "one rail per destination at bay %d on %s" % [bay.id, deck])
				distinct[target] = true
				if target == map.turn:
					turns += 1
					_check(deck == "ink" and bay.id == map.lift_start, "only the far ink dock owns the Turn")
				elif target == map.exit:
					exits += 1
					_check(deck == "lift" and bay.id == map.start, "only the near lift dock owns the Exit")
				elif target != map.hold:
					_check(target >= 0 and target < map.bays.size() and target != bay.id, "no void destinations or self loops")
					var neighbor: Dictionary = map.bays[target]
					_check(maxi(absi(bay.x - neighbor.x), absi(bay.y - neighbor.y)) == 1, "every rail is local")
	_check(turns == 1 and exits == 1, "no shortcut across decks or around the exit")


func _check_input(map: Dictionary) -> void:
	var m := R.new()
	var before := m.snapshot()
	_check(before.tick == 0 and before.phase == "record" and before.tape.is_empty(), "fresh attempt")
	_check(not m.step_tick() and m.snapshot() == before, "idle does not write time or tape")
	_check(not m.submit("wait") and m.preview("wait").reason == "unknown_action", "wait is not an engravable pulse")
	_check(not m.submit("rewind") and m.preview("rewind").reason == "need_turn", "early rewind rejected")
	_check(m.snapshot() == before, "invalid queries and commands are pure")
	var detached := m.board()
	detached.bays[0].ink[0] = map.exit
	before.pins[0] = 2
	before.actions.clear()
	_check(m.board() == map and m.snapshot().pins[0] == -1 and m.snapshot().actions.size() == 3,
		"board and state are defensive copies")
	var ghost := m.preview("port_0")
	var same := m.preview("port_0")
	ghost.frames[0].in_flight.to = map.exit
	ghost.frames[0].pins[0] = 2
	_check(m.preview("port_0") == same and ghost.frames[1] == same.frames[1], "preview frames are detached from model and each other")
	for i in same.frames.size():
		_check(same.frames[i].tick == same.base_tick + i + 1, "one forecast snapshot per integer tick")
	_check(m.submit("port_0"), "initial departure queueable")
	_check(m.snapshot().tick == 0 and m.snapshot().tape.is_empty(), "submission queues before ticking")
	_check(not m.submit("port_2") and m.snapshot().actions.is_empty(), "one scheduled action per boundary")
	for i in R.DECISION_TICKS:
		_check(m.step_tick(), "pending command advances clock")
		_check(m.snapshot() == same.frames[i], "record live/preview parity at tick %d" % (i + 1))
		if i < R.DECISION_TICKS - 1:
			_check(m.snapshot().pins[0] == -1 and not m.submit("port_2"), "no partial pin writes or interleaving")
	_check(same.frames[-1].tick == R.PREVIEW_TICKS and same.frames[-1].tape == [0]
		and same.frames[-1].in_flight.is_empty(), "idle forecast dwells without adding a tape stroke")
	var jam := m.preview("port_2")
	_check(jam.ok and jam.frames[19].failure == "ink_revisit" and jam.frames[39].phase == "failed",
		"preview identifies an armed-bay collision before confirmation")
	_check(m.submit("port_2"), "a red forecast is a real risky move")
	_step(m, R.DECISION_TICKS)
	_check(m.snapshot() == jam.frames[19] and not m.step_tick(), "crash is exact and terminal")
	_check(not m.submit("port_0") and not m.submit("rewind"), "terminal attempt has no gameplay escape")
	_check(R.new().snapshot().pins.count(-1) == map.bays.size(), "whole-attempt restart clears every pin")


func _replay(test: Dictionary, with_preview: bool) -> Dictionary:
	var m := R.new()
	var ink: Array[int] = []
	var lift: Array[int] = []
	var total_ink_steps: int = test.actions.size() - 1
	var map := m.board()
	for i in total_ink_steps:
		var before := m.snapshot()
		var action: String = test.actions[i]
		ink.append(before.ink_bay)
		var forecast := m.preview(action) if with_preview else {}
		_check(m.snapshot() == before, test.id + ": record preview leaves live state untouched")
		if not m.submit(action):
			_check(false, test.id + ": ink action rejected at step %d" % i)
			return m.snapshot()
		_step(m, R.DECISION_TICKS)
		var after := m.snapshot()
		if with_preview:
			_check(after == forecast.frames[R.DECISION_TICKS - 1], test.id + ": record forecast matches resolution")
		_check(after.tick == (i + 1) * R.DECISION_TICKS and after.tape.size() == i + 1,
			test.id + ": each departure adds exactly one sample")
		_check(after.pins[before.ink_bay] == after.tape[i] and after.cured.count(true) == 0,
			test.id + ": each outbound stroke writes the two coupled roles")
	_check(PackedInt32Array(ink) == PackedInt32Array(test.ink_route), test.id + ": exact ink route")
	var turn := m.snapshot()
	_check(turn.ink_bay == map.turn and turn.actions == ["rewind"] and turn.pins.count(-1) == 0,
		test.id + ": Turn alone cannot win; all pin writes precede rewind")
	_check(not m.submit("port_0"), test.id + ": cannot record from the Turn")
	var rewind := m.preview("rewind") if with_preview else {}
	_check(m.snapshot() == turn, test.id + ": rewind forecast is pure")
	if not m.submit(test.actions[-1]):
		_check(false, test.id + ": rewind rejected")
		return m.snapshot()
	if with_preview:
		_check(rewind.ok and rewind.horizon_ticks == R.PREVIEW_TICKS, test.id + ": raises a full two-stroke ghost")
		_check(rewind.frames[19].event.deck == "lift" and rewind.frames[39].event.deck == "lift"
			and rewind.frames[19].event.tape_index == map.bays.size() - 1
			and rewind.frames[39].event.tape_index == map.bays.size() - 2,
			test.id + ": rewind forecast simulates both real topology transitions")
	var elapsed := 0
	while elapsed < map.bays.size() * R.DECISION_TICKS and m.step_tick():
		elapsed += 1
		var state := m.snapshot()
		if with_preview and elapsed <= rewind.horizon_ticks:
			_check(state == rewind.frames[elapsed - 1], test.id + ": rewind forecast matches live tick %d" % elapsed)
		if elapsed % R.DECISION_TICKS == 0:
			var e: Dictionary = state.event
			lift.append(e.from)
			_check(state.pins == turn.pins and state.tape == turn.tape, test.id + ": replay never rewrites the tape or pins")
			_check(e.tape_index == total_ink_steps - lift.size()
				and e.pulse == turn.tape[e.tape_index] and e.pin == turn.pins[e.from],
				test.id + ": reverse cursor and bay-local pin both drive every stroke")
			_check(e.port == (2 - e.pulse + e.pin) % 3 and e.to == map.bays[e.from].lift[e.port],
				test.id + ": physical return rail agrees with independent rotary law")
			_check(not m.submit("port_0") and not m.submit("rewind"), test.id + ": no intervention in return deck")
	var result := m.snapshot()
	_check(PackedInt32Array(lift) == PackedInt32Array(test.lift_departures), test.id + ": exact lift route")
	_check(result.phase == test.expect.phase and result.tick == test.expect.tick
		and result.event.get("code") == test.expect.event_code and result.lift_bay == test.expect.lift_bay,
		test.id + ": exact terminal state")
	_check(not m.step_tick() and result.actions.is_empty() and result.cursor == -1,
		test.id + ": terminal clock stopped and cursor parked")
	if result.phase == "won":
		_check(result.cured.count(true) == map.bays.size(), "won means every pin is cured")
	else:
		_check(result.cured.count(true) < map.bays.size(), test.id + ": a divergent lift route cannot satisfy the cure invariant")
	return result


func _check_ablations(golden: Dictionary, map: Dictionary) -> void:
	var tape: Array[int] = []
	var pins := {}
	for i in map.bays.size():
		tape.append(R.PORT_ACTIONS.find(golden.actions[i]))
		pins[int(golden.ink_route[i])] = tape[i]
	for law in ["normal", "forward", "no_pin", "no_mirror"]:
		var bay: int = map.lift_start
		var seen := {}
		var steps := 0
		while steps < tape.size() and bay >= 0 and not seen.has(bay):
			seen[bay] = true
			var pulse := tape[steps if law == "forward" else -1 - steps]
			var pin: int = 0 if law == "no_pin" else pins[bay]
			var port := ((pulse if law == "no_mirror" else 2 - pulse) + pin) % 3
			bay = map.bays[bay].lift[port]
			steps += 1
		if law == "normal":
			_check(steps == tape.size() and bay == map.exit, "independent stateless routing calculation agrees")
		else:
			_check(steps == 2 and bay == map.lift_start, law + " breaks golden return by revisiting its start on stroke two")


func _check_incomplete_turn(map: Dictionary) -> void:
	# Find a legal shortcut to the far corner using only visible ink rails.
	var m := R.new()
	var route := _short_path(map, map.start, map.lift_start)
	for port: String in route:
		if not m.submit(port):
			_check(false, "visible short path to Turn must be queueable")
			return
		_step(m, R.DECISION_TICKS)
	var at_far := m.snapshot()
	_check(at_far.ink_bay == map.lift_start and at_far.tape.size() < map.bays.size() - 1,
		"physical Turn shortcut exists before all bays latch")
	var enter: String = R.PORT_ACTIONS[map.bays[map.lift_start].ink.find(map.turn)]
	var ghost := m.preview(enter)
	_check(ghost.ok and ghost.frames[19].failure == "turn_incomplete", "interlock forecasts incomplete Turn")
	_check(m.submit(enter), "partial departure clamps at arrival, not at input")
	_step(m, R.DECISION_TICKS)
	_check(m.snapshot() == ghost.frames[19] and not m.submit("rewind"), "shortcut cannot launch a shorter return")


func _short_path(map: Dictionary, source: int, target: int) -> Array[String]:
	var queue: Array[int] = [source]
	var path := {source: []}
	while not queue.is_empty():
		var bay: int = queue.pop_front()
		if bay == target:
			var result: Array[String] = []
			result.assign(path[bay])
			return result
		for port in R.PORT_ACTIONS.size():
			var next: int = map.bays[bay].ink[port]
			if next >= 0 and not path.has(next):
				queue.append(next)
				path[next] = path[bay] + [R.PORT_ACTIONS[port]]
	return []


func _check_lift_cap_and_early_exit(map: Dictionary, golden: Dictionary) -> void:
	# Reach the actual ink cap through public actions; it never consumes a turn.
	var cap_source := -1
	for bay: Dictionary in map.bays:
		if map.hold in bay.ink:
			cap_source = bay.id
	var m := R.new()
	for action: String in _short_path(map, map.start, cap_source):
		_check(m.submit(action), "ink cap approach via public rails")
		_step(m, R.DECISION_TICKS)
	var before := m.snapshot()
	var capped: String = R.PORT_ACTIONS[map.bays[cap_source].ink.find(map.hold)]
	_check(before.ink_bay == cap_source and capped not in before.actions and not m.submit(capped)
		and m.preview(capped).reason == "capped_socket" and m.snapshot() == before, "capped ink socket cannot write arbitrary pulses")
	# Boundary unit tests for the actual cap and exit. Public actions are tested
	# by the full fixtures; controlled one-stroke setup isolates the latch behavior.
	for terminal in [map.hold, map.exit]:
		m = R.new()
		var source := -1
		for bay: Dictionary in map.bays:
			if terminal in bay.lift:
				source = bay.id
		var port: int = map.bays[source].lift.find(terminal)
		m._phase = "rewind"
		m._lift_bay = source
		m._pins[source] = port
		m._tape.append(R.PORT_ACTIONS.find(golden.actions[0]))
		m._tape.append(2)
		m._cursor = 1
		m._queue_lift()
		_step(m, R.DECISION_TICKS)
		var after := m.snapshot()
		var reason := "lift_capped" if terminal == map.hold else "early_exit"
		_check(after.phase == "failed" and after.failure == reason, "return guard: " + reason)
		_check(after.cured[source] == (terminal == map.exit), "only an actual rail departure cures the source")


func _step(m, ticks: int) -> void:
	for i in ticks:
		if not m.step_tick():
			_check(false, "stalled before expected transition at offset %d" % i)
			return


func _check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)

extends SceneTree

const Model := preload("res://scenes/physics_lab/counterfactual/Model.gd")
const Replay := preload("res://tools/counterfactual/Replay.gd")
const FIXTURE := "res://tools/counterfactual/golden.json"
var _failures := 0
var _checks := 0

func _initialize() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	var routes: Array = fixture.routes
	for route in routes:
		_check_golden(route)
	_test_order(routes[0])
	_test_marks(routes[1])
	_test_warm_mark(routes[0])
	_test_missing_parts(routes[0])
	_test_recovery(routes[0])
	_test_replay_contract()
	print("A08: %d assertions, %d failures." % [_checks, _failures])
	quit(1 if _failures else 0)

func _check(ok: bool, context: String) -> void:
	_checks += 1
	if not ok:
		_failures += 1
		printerr("FAIL: ", context)

func _run(inputs: Array, until: int) -> Array[Dictionary]:
	var compiled := Replay.compile(inputs)
	if compiled.has("error"):
		_check(false, compiled.error)
		return []
	var m := Model.new()
	var frames: Array[Dictionary] = [m.observe()]
	for t in range(1, until + 1):
		m.step(compiled.ticks.get(t, {}))
		frames.append(m.observe())
	return frames

func _put(rows: Array, tick: int, press: String, target: String = "") -> void:
	rows.append({"tick": tick, "press": press, "target": target})

func _prefix(rows: Array, last: int) -> Array:
	return rows.filter(func(row: Dictionary) -> bool: return int(row.tick) <= last).duplicate(true)

func _cue_at(frame: Dictionary, id: String) -> Dictionary:
	for cue in frame.cues:
		if cue.id == id:
			return cue
	return {}

func _check_golden(route: Dictionary) -> void:
	var arm := int(route.arm_tick)
	var splice := int(route.splice_tick)
	var board := int(route.board_tick)
	var win := int(route.win_tick)
	var frames := _run(route.inputs, win + 4)
	_check(frames == _run(route.inputs, win + 4), route.id + ": identical fresh per-tick replay")
	_check(frames[splice - 1].retained == frames[splice].retained and frames[splice].retained == {"preload": int(route.retained_at_splice.preload), "bend": int(route.retained_at_splice.bend)},
		route.id + ": same two material memories through the splice")
	_check(not frames[splice - 1].local.pin_intact and frames[splice].local.pin_intact and frames[splice].local.heat == 0,
		route.id + ": pin and heat on old local layer")
	_check(frames[splice].tick == splice and frames[splice].local_tick == frames[splice].marks[route.mark].local_tick,
		route.id + ": exterior advances and local clock rewinds to chosen mark")
	var proof: Dictionary = frames[arm].proof
	var expected_windows: Array = proof.windows.get(route.approach, [])
	_check(not expected_windows.is_empty() and expected_windows[0] == {"first_tick": board, "last_tick": int(route.last_entry)},
		route.id + ": forecast and entry range")
	_check(frames[board].crossing.get("from", "") == route.approach and frames[board].event.id == "boarding", route.id + ": approach")
	for t in range(board, win):
		var rider: Dictionary = frames[t].readings
		_check(rider.tension_ok and rider.shoe_ok and rider.rider_load > 0 and not frames[t].won,
			"Both needles support rider at tick %d" % t)
	_check(frames[win].won and frames[win].place == "exit" and frames[win + 4] == frames[win], route.id + ": stable verdict")
	var review := {}
	for frame in frames:
		for cue in frame.cues:
			_check(cue.due_tick > frame.tick, "Cue visible only before change")
			if not review.has(cue.id):
				review[cue.id] = cue
	for id in ["cut_pin", "rewind_" + route.mark, "proof_start", "proof_end", "rider_release"]:
		var cue: Dictionary = review.get(id, {})
		_check(not cue.is_empty(), "Observed warning: " + id)
		if cue.is_empty():
			continue
		_check(cue.due_tick - cue.start_tick >= 40, "Forty readable ticks for " + id)
		for t in range(cue.start_tick, mini(cue.due_tick, win)):
			_check(_cue_at(frames[t], id) == cue, "Continuous warning: %s at %d" % [id, t])
	print("%s: splice %d, board %d, far landing %d." % [route.id, splice, board, win])

func _test_order(route: Dictionary) -> void:
	var base := [
		{"tick": 1, "press": "move", "target": "jack"}, {"tick": 56, "press": "move", "target": "yoke"},
		{"tick": 68, "press": "move", "target": "kiln"}, {"tick": 80, "press": "cut_pin"},
		{"tick": 128, "hold": "heat", "for": 45}, {"tick": 173, "press": "move", "target": "start"},
		{"tick": 185, "press": "move", "target": "jack"}, {"tick": 256, "press": "move", "target": "start"},
		{"tick": 268, "press": "rewind_home"},
	]
	for row in route.inputs:
		if int(row.tick) > int(route.splice_tick):
			var replay: Dictionary = row.duplicate()
			replay.tick += 120  # Same exterior phase, same actions after the splice.
			base.append(replay)
	var early := _run(base + [{"tick": 13, "hold": "haul", "for": 43}], 650)
	var late := _run(base + [{"tick": 213, "hold": "haul", "for": 43}], 650)
	_check(early[128].place == late[128].place and early[13].place == late[213].place,
		"Order counterexample uses the same pad for each action and the same itinerary")
	_check(early[316].local == late[316].local and early[316].drum_phase == late[316].drum_phase,
		"Same restored snapshot, same exterior phase")
	_check(early[316].retained == {"preload": 43, "bend": 25} and late[316].retained == {"preload": 43, "bend": 0},
		"Hot under load leaves the bend; cold haul after heating leaves a flat strip")
	_check(early[-1].won and not late[-1].won and late[459].proof.windows == {"brake": [], "weight": []},
		"Identical later inputs: historical order changes the old world's proof")

func _test_marks(route: Dictionary) -> void:
	var home_rows := _prefix(route.inputs, 363)
	home_rows[-1].press = "rewind_home"
	var home := _run(home_rows, 411)[-1]
	var bench := _run(_prefix(route.inputs, 363), 411)[-1]
	_check(bench.marks.bench.saved_drum_phase == bench.marks.home.saved_drum_phase,
		"Both saved marks have the same visible drum phase")
	_check(home.tick == bench.tick and home.drum_phase == bench.drum_phase and home.retained == bench.retained,
		"Choose two marks at the identical real tick with identical material memories")
	_check(home.local.ballast == 0 and bench.local.ballast == 34 and home.local.brake == 0 and bench.local.brake == 4,
		"Home and Bench display different local witness columns at the same beat")
	_check(home.readings.shoe != bench.readings.shoe and home.readings.tension != bench.readings.tension,
		"Restored witness columns change the physical needles immediately")

func _test_warm_mark(route: Dictionary) -> void:
	var rows := _prefix(route.inputs, 173)
	_put(rows, 185, "mark")
	_put(rows, 240, "rewind_bench")
	var frames := _run(rows, 289)
	_check(frames[185].marks.bench.heat == frames[185].local.heat and frames[185].local.heat > Model.FORM_HEAT,
		"A warm mark stamps the same heat as the live witness")
	_check(frames[287].local.heat == 0 and not frames[288].local.pin_intact and frames[288].retained.bend == 25 and frames[288].local_tick == 185,
		"Splice restores the chosen hot, open-pin frame exactly while retaining shape")
	_check(frames[288].local.heat == frames[185].local.heat and frames[289].local.heat == frames[288].local.heat - 1,
		"Cooling resumes on the tick after an exact warm restore")

func _test_missing_parts(route: Dictionary) -> void:
	var rows := _prefix(route.inputs, 172)
	_put(rows, 173, "move", "yoke")
	_put(rows, 185, "arm")
	var pin := _run(rows, 185)[-1]
	_check(pin.event.id == "blocked" and not pin.local.pin_intact and pin.proof.stage == "parked", "Cut pin prevents carrying proof before restoring it")
	rows = _prefix(route.inputs, 234)
	rows.append({"tick": 246, "hold": "pay_out", "for": 43})
	_put(rows, 289, "move", "yoke")
	_put(rows, 301, "move", "weight")
	rows.append({"tick": 313, "hold": "raise", "for": 36})
	_put(rows, 349, "move", "yoke")
	_put(rows, 361, "arm")
	var cable := _run(rows, 361)[-1]
	_check(cable.retained == {"preload": 0, "bend": 25} and cable.proof.windows == {"brake": [], "weight": []},
		"Retained bend alone does not bear the rider")

func _test_recovery(route: Dictionary) -> void:
	var rows := _prefix(route.inputs, 80)
	_put(rows, 127, "cancel")
	var frames := _run(rows, 128)
	_check(frames[126].cues.size() == 1 and frames[127].cues.is_empty() and frames[128].local.pin_intact,
		"Cancel the service punch one tick before the pin falls")
	rows = _prefix(route.inputs, 185)
	_put(rows, 232, "cancel")
	_put(rows, 234, "rewind_home")
	frames = _run(rows, 282)
	_check(not frames[233].local.pin_intact and frames[282].local.pin_intact and frames[282].retained.bend == 25,
		"Withdraw a splice, then try it again with the same surviving bend")
	rows = _prefix(route.inputs, 340)
	_put(rows, 400, "move", "span")
	frames = _run(rows, 627)
	_check(frames[400].event.id == "blocked" and frames[400].event.detail.failure.tick == 400 and frames[400].place == "weight",
		"Too-early entry shows a failed loaded sample and holds the latch closed")
	_check(_cue_at(frames[626], "proof_end").get("due_tick") == 627 and frames[627].proof.stage == "parked"
		and frames[627].event.id == "proof_ended", "Unused proof ends exactly at its posted deadline")
	rows = route.inputs.duplicate(true)
	_put(rows, 360, "cancel")
	_put(rows, 361, "queue_cross")
	_put(rows, 470, "cancel")
	_put(rows, 482, "move", "yoke")
	_put(rows, 579, "arm")  # Same exterior phase on the second trial.
	_put(rows, 580, "move", "weight")
	_put(rows, 593, "queue_cross")
	frames = _run(rows, 748)
	_check(frames[360].proof.stage == "arming" and frames[360].proof.queued.is_empty() and frames[361].proof.queued.due_tick == 460,
		"Withdraw and replace an entry request without restarting the draw")
	_check(frames[470].event.id == "retreat" and frames[470].travel.kind == "safety_return" and frames[481].place == "span",
		"A rider can retreat on the safety trolley")
	_check(frames[482].place == "weight" and frames[-1].won, "Retreat leaves a usable approach and another successful draw")
	var m := Model.new()
	var edge_ticks: Dictionary = Replay.compile(route.inputs).ticks
	for t in range(1, int(route.arm_tick) + 1):
		m.step(edge_ticks.get(t, {}))
	var view := m.observe()
	var entry := int(route.board_tick)
	var clash := false
	for off in range(Model.CROSS_TICKS):
		var left := m.sample_proof("brake", entry, off)
		var right := m.sample_proof("weight", entry, off)
		if left.tension_ok and not left.shoe_ok and right.tension_ok and right.shoe_ok:
			clash = true
	_check(clash and view.proof.windows.brake.is_empty(), "Same tick and cable, conflicting shoe constraint on the mirrored approach")
	var off_window_cable := false
	var off_window_shoe := false
	for t in range(int(view.proof.start_tick), int(view.proof.end_tick) - Model.CROSS_TICKS + 1):
		var sample := m.sample_proof("weight", t, 15)
		off_window_cable = off_window_cable or (sample.tension_ok and not sample.shoe_ok)
		off_window_shoe = off_window_shoe or (sample.shoe_ok and not sample.tension_ok)
	_check(off_window_cable and off_window_shoe, "A high cable reading and a good shoe seat are independently insufficient")
	view.proof.windows.weight.clear()
	view.proof.best_trial.weight.failure["fake"] = true
	view.links.start.clear()
	view.marks.home.ballast = 99
	var reread := m.observe()
	_check(not reread.proof.windows.weight.is_empty() and not reread.proof.best_trial.weight.failure.has("fake")
		and reread.links.start.size() == 2 and reread.marks.home.ballast == 0, "Detached views cannot mutate the referee")

func _test_replay_contract() -> void:
	var ok := Replay.compile([{"tick": 1, "press": "move", "target": "jack"}, {"tick": 1, "hold": "haul", "for": 3}])
	_check(ok.ticks[1] == {"press": "move", "target": "jack", "hold": "haul"} and ok.ticks[3] == {"hold": "haul"},
		"RLE hold levels merge with one edge; edge does not retrigger")
	_check(Replay.compile([{"tick": 1.1, "hold": "haul"}]).has("error"), "Reject fractional real tick")
	_check(Replay.compile([{"tick": 1, "hold": "haul", "for": 2}, {"tick": 2, "hold": "heat"}]).has("error"),
		"Reject two levels rather than silently alter the replay rhythm")

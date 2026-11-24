extends SceneTree
## Run headless from the project root. Drives only the public integration API.

const Rules = preload("res://scenes/physics_lab/afterimage/AfterimageRules.gd")
const FIXTURE := "res://tools/afterimage/golden.json"

var checks := 0
var failures: Array[String] = []
var fixture: Dictionary


func _initialize() -> void:
	fixture = JSON.parse_string(FileAccess.get_file_as_string(FIXTURE))
	_test_input()
	_test_golden("from_lamp")
	_test_golden("from_bell")
	_test_causal_cuts()
	_test_reel_and_recovery()
	_test_pending_pair()
	_test_spring_and_late_swing()
	_test_west_cannot_be_banked()
	print("Afterimage A05: %d checks, %d failures" % [checks, failures.size()])
	for failure in failures:
		printerr(failure)
	quit(int(not failures.is_empty()))


func _expect(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		failures.append(label)


func _step(model: Rules, count: int) -> Dictionary:
	for i in count:
		model.step_tick()
	return model.observe()


func _beat(model: Rules, command: String = "wait") -> Dictionary:
	var words := command.split(" ")
	_expect(model.queue_action(words[0], words[1] if words.size() > 1 else ""), "queue " + command)
	var s := model.observe()
	return _step(model, s.next_decision_tick - s.tick)


func _plays(model: Rules, commands: Array) -> void:
	for command in commands:
		_beat(model, command)


func _cue(s: Dictionary, kind: String) -> Dictionary:
	for cue in s.cues:
		if cue.kind == kind:
			return cue
	return {}


func _notice(s: Dictionary, kind: String, due: int, label: String) -> void:
	var cue := _cue(s, kind)
	_expect(cue.get("start_tick", -1) == s.tick and cue.get("due_tick", -1) == due
		and due - s.tick >= 40, label + "/" + kind)


func _start_replay(model: Rules, recording: Array) -> void:
	_plays(model, recording)
	_expect(model.observe().reel.can_rewind, "full grounded reel")
	var s := _beat(model, "rewind")
	_expect(s.last_action.ok and s.reel.rewinding, "rewind armed")
	_notice(s, "rewind", s.tick + 40, "rewind cue starts at arm")
	_expect(not model.queue_action("move", "hub"), "no buffered input during rewind")
	var origin: String = s.player
	s = _step(model, 39)
	_expect(s.player == origin and s.reel.rewinding and s.reel.cursor == 0, "origin retained through due - 1")
	s = _step(model, 1)
	_expect(s.reel.replaying and s.reel.cursor == 0 and s.signals.is_empty(), "commit before first echo beat")


func _check_pair(s: Dictionary, receiver: String, sources: Array, label: String) -> void:
	_expect(s.pair.get("receiver", "") == receiver and s.pair.get("accepted", false), label + ": paired")
	var seen := []
	for signal_state in s.signals:
		seen.append(signal_state.source)
		_expect(signal_state.start_tick == s.tick and signal_state.end_tick == s.tick + 20, label + ": window")
	_expect(seen == sources and s.signals[0].origin == "echo" and s.signals[1].origin == "live", label + ": sources")


func _test_input() -> void:
	var model := Rules.new()
	var geometry := model.layout()
	_expect(geometry.sites.size() == 5 and geometry.sites.lamp.grounded, "public room schema")
	geometry.sites.lamp["grounded"] = false
	_expect(model.layout().sites.lamp.grounded, "layout detached")
	_expect(not model.queue_action("bogus") and not model.queue_action("move", "void")
		and not model.queue_action("wait", "hub"), "invalid inputs rejected immediately")
	_expect(model.queue_action("move", "lamp") and not model.queue_action("wait"), "only one queued action")
	var s := _step(model, 19)
	_expect(s.player == "hub" and s.next_decision_tick == 20, "no move at tick 19")
	s = _step(model, 1)
	_expect(s.player == "lamp" and s.last_action.tick == 20, "move at tick 20")
	s.walkable[0][0] = "test"
	_expect(model.observe().walkable[0][0] == "hub", "observation detached")
	s = _beat(model, "rewind")
	_expect(s.last_action.reason == "reel_short", "short rewind denied")
	model.reset()
	_expect(model.observe().tick == 0 and model.observe().reel.recorded == 0, "reset is clean")


func _test_golden(name: String) -> void:
	var model := Rules.new()
	var row: Dictionary = fixture[name]
	var clock: Dictionary = fixture.clock
	_start_replay(model, row.record)
	var s := model.observe()
	_expect(s.tick == clock.splice and s.player == "hub" and s.form == "clear"
		and s.last_action.tick == clock.rewind, name + ": spliced baseline")
	_beat(model, row.play[0])
	s = _beat(model, row.play[1])
	_check_pair(s, "west", row.west_pair, name + ": west")
	_expect(s.tick == clock.west_pair and s.alignment == "neutral" and s.walkable.size() == 2, name + ": west still absent")
	_notice(s, "swing", clock.west_dock, name)
	_beat(model, row.play[2])
	_expect(model.observe().signals.is_empty(), name + ": pulse expires next boundary")
	_expect(model.queue_action("move", "carriage"), name + ": queue carriage")
	s = _step(model, 19)
	_expect(s.walkable.size() == 2 and s.player == "hub", name + ": no premature boarding")
	s = _step(model, 1)
	_expect(s.tick == clock.west_dock and s.alignment == "west" and s.player == "carriage"
		and s.walkable.has(["hub", "carriage"]), name + ": board at commit")
	s = _beat(model, row.play[4])
	_expect(s.tick == clock.prism_throw and s.optics.receiver == "west", name + ": old observation through warning")
	_notice(s, "prism", clock.east_pair, name)
	_beat(model, row.play[5])
	s = _beat(model, row.play[6])
	_check_pair(s, "east", row.east_pair, name + ": east")
	_expect(s.tick == clock.east_pair and s.optics.receiver == "east" and s.form == "silver"
		and s.optics.revealed_gangway == ["carriage", "exit"] and s.walkable.size() == 2, name + ": new observation, dark west gangway")
	_notice(s, "swing", clock.exit, name)
	_notice(s, "spring", clock.exit, name)
	_beat(model, row.play[7])
	s = _beat(model, row.play[8])
	_expect(s.won and s.player == "exit" and s.tick == clock.exit and s.alignment == "east"
		and s.spring_due_tick == -1, name + ": arrival and powered-swing/spring tie")
	_expect(not model.queue_action("wait") and _step(model, 1).tick == clock.exit, name + ": terminal")
	print("PASS golden %s: W pair/land %d/%d; E pair/exit %d/%d" % [name, clock.west_pair, clock.west_dock, clock.east_pair, s.tick])


func _test_causal_cuts() -> void:
	var row: Dictionary = fixture.from_lamp
	for cut in ["late_ring", "same_channel", "missing_past_flash", "clear_prism", "early_exit"]:
		var model := Rules.new()
		var record: Array = row.record.duplicate()
		var play: Array = row.play.duplicate()
		match cut:
			"late_ring":
				play[6] = "wait"
				play[7] = "pulse"
			"same_channel": play[0] = "move lamp"
			"missing_past_flash": record[6] = "wait"
			"clear_prism": play[4] = "wait"
			"early_exit": play[7] = "move exit"
		_start_replay(model, record)
		_plays(model, play.slice(0, 2))
		var s := model.observe()
		if cut == "same_channel":
			_expect(s.signals.size() == 2 and s.pair.is_empty() and s.cues.is_empty(), cut + ": two lights do not pair")
		_plays(model, play.slice(2, 7))
		s = model.observe()
		if cut == "clear_prism":
			_expect(s.pair.get("reason", "") == "already_aligned" and s.alignment == "west"
				and s.walkable.has(["hub", "carriage"]) and s.optics.receiver == "west"
				and s.spring_due_tick == 400, cut + ": wrong pickup, no spring refresh")
		elif cut in ["late_ring", "missing_past_flash"]:
			_expect(s.player == "carriage" and s.form == "silver" and s.pair.is_empty(), cut + ": same geometry cannot substitute for paired history")
		s = _beat(model, play[7])
		if cut == "early_exit":
			_expect(not s.last_action.ok and s.last_action.reason == "no_gangway", cut + ": preview is not traversal")
		elif cut == "late_ring":
			_expect(s.signals.size() == 1 and s.pair.is_empty(), cut + ": one-beat miss")
		s = _beat(model, play[8])
		_expect(s.won == (cut == "early_exit"), cut + ": result")
		if cut in ["late_ring", "missing_past_flash", "clear_prism"]:
			_expect(s.player == "carriage" and s.alignment == "neutral", cut + ": safe spring return with rider")
			s = _beat(model, "escape")
			_expect(s.player == "hub" and s.last_action.ok, cut + ": safe descent")
		print("PASS counterfactual %s: %s" % [cut, "only later crossing succeeds" if cut == "early_exit" else "no exit"])


func _test_reel_and_recovery() -> void:
	var model := Rules.new()
	_start_replay(model, ["move lamp", "pulse", "move hub", "prism", "wait", "wait", "move bell", "wait"])
	var s := model.observe()
	_expect(s.form == "clear" and s.player == "hub" and s.reel.tape == ["", "lamp", "", "", "", "", "", ""], "rewind restores optical snapshot and filters ordinary interactions")
	s = _beat(model, "rewind")
	_expect(s.last_action.reason == "head_busy" and s.reel.cursor == 1 and s.reel.recorded == 0, "no nested rewind or simultaneous recording")
	s = _beat(model)
	_expect(s.signals.size() == 1 and s.signals[0].source == "lamp" and s.player == "hub", "grounded contact can replay away from pawn")
	_plays(model, ["wait", "wait", "wait", "wait", "wait", "wait"])
	_expect(model.observe().player == "hub" and model.observe().form == "clear", "no echo movement or prism throw")
	model.reset()
	_start_replay(model, ["move lamp", "pulse", "wait", "wait", "wait", "wait", "wait", "wait", "wait", "wait"])
	_expect(model.observe().player == "lamp" and not model.observe().reel.tape.has("lamp"), "old pulse and origin outside rolling bound")
	model.reset()
	_start_replay(model, fixture.from_lamp.record)
	_plays(model, fixture.from_lamp.play.slice(0, 4))
	_plays(model, ["wait", "wait", "wait", "wait"])
	s = _beat(model, "pulse")
	_expect(s.alignment == "neutral" and s.reel.anchor == "carriage" and s.reel.tape == [""]
		and s.signals[0].source == "carriage", "mobile bell acts live but leaves no imprint")
	for i in 7:
		_beat(model)
	_expect(not model.observe().reel.can_rewind, "an ungrounded origin cannot restore the pawn")
	s = _beat(model, "rewind")
	_expect(s.last_action.reason == "anchor_ungrounded", "soft refusal at ungrounded anchor")
	_beat(model, "escape")
	for i in 8:
		_beat(model)
	_expect(model.observe().reel.can_rewind and model.observe().reel.anchor == "hub", "fresh tape after taking ladder")


func _test_pending_pair() -> void:
	var model := Rules.new()
	_start_replay(model, ["move lamp", "pulse", "pulse", "pulse", "wait", "wait", "wait", "wait"])
	_beat(model, "move bell")
	_beat(model, "pulse")
	var s := _beat(model, "pulse")
	_expect(s.pair.get("reason", "") == "swing_pending" and _cue(s, "swing").get("due_tick") == 300, "second pair cannot preempt warning")
	s = _beat(model, "pulse")
	_expect(s.pair.get("reason", "") == "already_aligned" and s.spring_due_tick == 400, "same receiver cannot renew lease")


func _test_spring_and_late_swing() -> void:
	var model := Rules.new()
	var record: Array = fixture.from_lamp.record.duplicate()
	record[6] = "wait"
	record[7] = "pulse"
	_start_replay(model, record)
	_plays(model, fixture.from_lamp.play.slice(0, 6))
	var s := _beat(model)
	_notice(s, "spring", 400, "spring countdown independent of light")
	s = _beat(model, "pulse")
	_check_pair(s, "east", ["lamp", "carriage"], "late pair")
	_notice(s, "swing", 420, "late East swing has a full warning")
	s = _step(model, 19)
	_expect(s.alignment == "west" and s.player == "carriage", "spring retains support through due - 1")
	s = _step(model, 1)
	_expect(s.tick == 400 and s.alignment == "neutral" and s.player == "carriage"
		and _cue(s, "swing").get("due_tick") == 420, "spring return does not cancel the armed swing")
	s = _beat(model, "move exit")
	_expect(s.won and s.tick == 420, "late but valid second rendezvous")


func _test_west_cannot_be_banked() -> void:
	var model := Rules.new()
	_start_replay(model, ["move lamp", "wait", "wait", "wait", "wait", "wait", "wait", "pulse"])
	_plays(model, ["move bell", "wait", "wait", "wait", "wait", "wait", "wait", "pulse"])
	var s := model.observe()
	_notice(s, "swing", 420, "latest possible West pair")
	_beat(model, "move hub")  # First new recording frame; no replay remains.
	s = _beat(model, "move carriage")
	_expect(s.alignment == "west" and s.player == "carriage", "late West boarding")
	_plays(model, ["escape", "move lamp", "pulse", "wait", "wait", "wait"])
	s = model.observe()
	_expect(s.alignment == "neutral" and s.reel.can_rewind, "spring returns before next tape can be wound")
	s = _beat(model, "rewind")
	_expect(_cue(s, "rewind").get("restore_alignment") == "neutral", "rewind keeps external escapement result")
	_step(model, 40)
	s = _beat(model, "move carriage")
	_expect(s.player == "bell" and s.last_action.reason == "no_gangway", "no banking a West pass across rewinds")

extends SceneTree

const Rules = preload("res://scenes/physics_lab/duet/DuetRules.gd")
const GOLDEN := "res://tools/duet/golden.json"
const SIGNPOSTS := ["leaf_passable", "leaf_hold", "leaf_blocked", "caught", "recovered", "won"]
var _failures: Array[String] = []


func _initialize() -> void:
	var golden: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	if not golden is Dictionary or not golden.has("cases"):
		printerr("A06: invalid golden")
		quit(1)
		return
	var report := OS.get_cmdline_user_args().has("--report")
	for entry: Dictionary in golden.cases:
		_replay(entry, report)
	_test_decisions()
	_test_coupling()
	_test_evidence_plan()
	for failure in _failures:
		printerr(failure)
	if _failures.is_empty():
		print("A06 verified: %d tapes, cue/footing invariants, conflict forks, and live evidence plan" % golden.cases.size())
	quit(0 if _failures.is_empty() else 1)


func _check(ok: bool, label: String) -> void:
	if not ok:
		_failures.append(label)


func _replay(entry: Dictionary, report: bool) -> void:
	var name: String = entry.name
	var live := Rules.new()
	var batch := Rules.new()
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	var marks: Array = []
	var cues: Dictionary = {}
	var last_id := 0
	var checkpoints: Dictionary = entry.get("at", {})
	var refusals: Dictionary = entry.get("refusals", {})
	var sampled := 0
	for row: Array in entry.input:
		for repetition in range(int(row[1])):
			var action: String = row[0]
			var before := live.snapshot()
			var offset: int = before.events.size()
			var receipt := live.submit(action)
			var expected_reason: String = refusals.get(str(before.tick), "")
			_check(receipt.reason == expected_reason and receipt.accepted == expected_reason.is_empty(),
				name + ": action receipt @%d: %s" % [before.tick, receipt.reason])
			var tape: Array = live.snapshot().events.slice(offset)
			_hash(digest, [action, receipt])
			for frame in range(20):
				var prev := live.snapshot()
				live.tick_once()
				var now := live.snapshot()
				_check_frame(prev, now, name)
				tape.append_array(now.events)
				_hash(digest, now)
				if checkpoints.has(str(now.tick)):
					_sample(checkpoints[str(now.tick)], now, name)
					sampled += 1
			var fast := batch.step(action)
			_check(fast.accepted == receipt.accepted and fast.reason == receipt.reason, name + ": decision parity")
			_check(fast.events == tape and fast.snapshot == live.snapshot(), name + ": batch parity @" + str(before.tick))
			for e: Dictionary in tape:
				_check(int(e.id) == last_id + 1, name + ": contiguous event IDs")
				last_id = e.id
				_audit_event(e, cues, name)
				if e.kind in SIGNPOSTS:
					marks.append([e.tick, e.kind, e.source, e.lead_ticks])
	var final := live.snapshot()
	var hex := digest.finish().hex_encode()
	_check(sampled == checkpoints.size(), name + ": all checkpoints reached")
	_check(final.outcome == entry.outcome, name + ": final outcome " + final.outcome)
	var expected_marks: Array = []
	for mark: Array in entry.marks:
		expected_marks.append([int(mark[0]), mark[1], mark[2], int(mark[3])])
	_check(marks == expected_marks, name + ": signposts " + JSON.stringify(marks))
	if report:
		print(name, " ", hex, " ", JSON.stringify(marks))
	else:
		_check(hex == entry.get("sha256", ""), name + ": full tick tape sha256 " + hex)


func _hash(digest: HashingContext, datum: Variant) -> void:
	digest.update((JSON.stringify(datum) + "\n").to_utf8_buffer())


func _sample(paths: Dictionary, state: Dictionary, label: String) -> void:
	for key: String in paths:
		var value: Variant = state
		for part in key.split("."):
			value = value[part]
		_check(value == paths[key], "%s @%s: %s was %s; expected %s" % [label, state.tick, key, value, paths[key]])


func _audit_event(e: Dictionary, cues: Dictionary, label: String) -> void:
	var note := "%s %s/%s @%d" % [label, e.kind, e.source, e.tick]
	if e.kind == "cue_start":
		_check(not cues.has(e.source) and e.id == e.cue_id, note + ": unique warning")
		_check(e.start_tick == e.tick and e.due_tick - e.tick >= 40, note + ": minimum announced lead")
		cues[e.source] = e
		return
	if e.kind == "leaf_hold" or (e.kind == "leaf_motion" and e.source == "leaf_lower"):
		_check(cues.has(e.source) and e.tick - int(cues[e.source].start_tick) >= 40, note + ": preceded by steam")
	if e.kind not in ["cue_cancel", "leaf_passable", "leaf_blocked", "caught", "recovered"]:
		return
	_check(cues.has(e.source), note + ": cue still live")
	if not cues.has(e.source):
		return
	var cue: Dictionary = cues[e.source]
	_check(e.cue_id == cue.id and e.start_tick == cue.tick and e.due_tick == cue.due_tick, note + ": cue linkage")
	_check(e.lead_ticks == e.tick - cue.tick, note + ": exact lead")
	if e.kind != "cue_cancel":
		_check(e.lead_ticks >= 40 and e.tick >= cue.due_tick, note + ": cue matured before commit")
	cues.erase(e.source)
	if e.kind == "caught":
		for secondary: String in e.detail.also:
			_check(cues.has(secondary) and e.tick >= int(cues[secondary].due_tick), note + ": secondary cue matured")
			cues.erase(secondary)


func _check_frame(prev: Dictionary, now: Dictionary, label: String) -> void:
	_check(now.tick == prev.tick + 1 and now.tick_hz == 60, label + ": fixed tick")
	var changed: Array[String] = []
	for e: Dictionary in now.events:
		changed.append(e.kind)
	var blocked_changed: bool = now.leaf.passable != prev.leaf.passable
	_check(blocked_changed == ("leaf_passable" in changed or "leaf_blocked" in changed), label + ": topology commit")
	_check(not now.leaf.passable or now.leaf.angle_deg == 0, label + ": physical detent")
	_check(not now.player.on_leaf or now.leaf.passable, label + ": actor supported")
	if now.player.zone != "lane":
		_check(now.hearing.ring == 0 and not now.sight.gaze, label + ": shelter isolation")
		return
	var low: bool = now.player.posture == "low"
	var felt: bool = prev.player.footing == "felt"
	var contribution := (-4 if low else -3) if felt else (-2 if low else 4)
	_check(now.hearing.signal_per_tick == contribution, label + ": iron/felt contribution")
	_check(now.hearing.ring == clampi(int(prev.hearing.ring) + contribution, 0, 240), label + ": ring integrator")
	var old_z: int = prev.sight.position_cm[1]
	var player_z: int = now.player.position_cm[1]
	var expected_z := old_z + (clampi(player_z - old_z, -9, 9) if low else 0)
	_check(now.sight.gaze == not low and now.sight.position_cm[1] == expected_z, label + ": freeze/advance")


func _to_lane(rule: RefCounted, strides: Array) -> void:
	rule.step("lower")
	for i in range(4):
		rule.step()
	for action: String in strides:
		rule.step(action)


func _test_decisions() -> void:
	var r := Rules.new()
	var layout := r.layout()
	var initial := r.snapshot()
	_check(layout.stations_cm.size() == 13 and initial.next_decision_tick == 0, "fresh layout and decision")
	layout.stations_cm[0][1] = 999
	initial.player.position_cm[1] = 999
	_check(r.layout().stations_cm[0][1] == 0 and r.snapshot().player.position_cm[1] == 0, "detached geometry and player snapshot")
	_check(not r.submit("debug_warp").accepted, "unknown action rejected")
	_check(r.step("lower").reason == "decision_closed" and r.snapshot().tick == 0, "rejection spends only that decision; closed step does not advance")
	r.tick_once()
	_check(r.submit("lower").reason == "decision_closed" and r.snapshot().next_decision_tick == 20, "offbeat rejected")
	for i in range(19):
		r.tick_once()
	_check(r.submit("lower").accepted, "open boundary accepted")
	var changed := r.snapshot()
	changed.events.back().detail.foo = 1
	changed.cues[0].due_tick = -1
	_check(r.snapshot().events.back().detail.is_empty() and r.snapshot().cues[0].due_tick == 120, "detached cues and nested events")
	r.reset()
	_check(r.snapshot() == Rules.new().snapshot(), "reset matches new instance")


func _test_coupling() -> void:
	# Both branches start at exactly the same iron mark and pressure.
	var high := Rules.new()
	var low := Rules.new()
	_to_lane(high, ["watch", "creep", "watch"])
	_to_lane(low, ["watch", "creep", "watch"])
	var start := high.snapshot()
	_check(start == low.snapshot(), "iron conflict fork is identical")
	high.submit("watch")
	low.submit("creep")
	high.tick_once()
	low.tick_once()
	var h := high.snapshot()
	var l := low.snapshot()
	_check(h.player.position_cm == l.player.position_cm, "same displacement on iron")
	_check(h.hearing.ring > start.hearing.ring and l.hearing.ring < start.hearing.ring, "opposed pressure on iron")
	_check(h.sight.gaze and h.sight.position_cm == start.sight.position_cm and l.sight.separation_cm < start.sight.separation_cm, "same stride freezes in tall stance, closes gap in low stance")

	# At the first felt edge the very same tall input reverses its acoustic sign.
	var felt := Rules.new()
	_to_lane(felt, ["watch", "creep", "watch", "creep"])
	var bank := felt.snapshot()
	felt.step("watch")
	var deck := felt.snapshot()
	_check(bank.hearing.mode == "warning" and bank.sight.mode == "winding", "both constructs telegraph at the bank")
	_check(deck.sight.gaze and deck.sight.position_cm == bank.sight.position_cm and deck.hearing.ring < bank.hearing.ring, "felt permits concurrent clearance with tall stride")
	_check(deck.sight.separation_cm > bank.sight.separation_cm and deck.cues.is_empty(), "felt stride clears both warnings")

	# Replace only the acoustic material on that published winning line; leave gaze and topology intact.
	var bare_ring: int = bank.hearing.ring
	var deadline := -1
	for cue: Dictionary in bank.cues:
		if cue.kind == "hearing":
			deadline = cue.due_tick
	for t in range(int(bank.tick) + 1, deadline + 1):
		bare_ring = mini(240, bare_ring + 4)
	_check(deadline == 210 and bare_ring >= 80 and felt.step("watch").snapshot.outcome == "active", "iron substitution catches the otherwise identical winning tall line")

	# A charged watcher is held in place by sight past its due tick. Ducking now is visibly unsafe.
	var primed := Rules.new()
	_to_lane(primed, ["watch", "creep", "watch", "creep", "watch", "creep", "watch", "creep", "watch"])
	_check(primed.snapshot().sight.mode == "primed", "expired close wind-up still visible under gaze")
	var collapse := primed.step("creep")
	_check(collapse.snapshot.outcome == "recovering", "ducking with primed watcher fails")


func _test_evidence_plan() -> void:
	# Public geometric marks and visible/hearable readings only; no fixed tape or absolute schedule.
	var r := Rules.new()
	var banks: Array = r.layout().gap_banks
	var throw_delay := 3
	for i in range(35):
		var s := r.snapshot()
		if s.outcome == "won":
			break
		var input := "wait"
		var mark: int = s.player.station
		if throw_delay > 0:
			throw_delay -= 1
		elif s.player.zone == "porch" and s.leaf.phase == "up":
			input = "lower"
		elif s.leaf.passable:
			var felt_ahead: bool = mark >= int(banks[0]) and mark < int(banks[1])
			var sight_primed: bool = s.sight.mode == "primed"
			for cue: Dictionary in s.cues:
				if cue.kind == "sight" and int(cue.due_tick) - int(s.tick) <= 20:
					sight_primed = true
			input = "watch" if felt_ahead or sight_primed or s.hearing.mode != "warning" else "creep"
		_check(r.step(input).accepted, "evidence policy issues only legal player actions")
	_check(r.snapshot().outcome == "won" and r.snapshot().attempt == 1, "visible-evidence plan wins at delayed start")

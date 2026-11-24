extends SceneTree

const Rules = preload("res://scenes/physics_lab/shutter_loom/ShutterRules.gd")
const GOLDEN := "res://tools/shutter_loom/golden.json"
var _failures := 0


func _initialize() -> void:
	_golden()
	_counterfactuals()
	if _failures == 0:
		print("A04 shutter loom: golden + counterfactual smoke PASS")
	quit(0 if _failures == 0 else 1)


func _golden() -> void:
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	if not _check(data is Dictionary, "golden is readable JSON"):
		return
	var live := Rules.new(int(data.seed))
	var batch := Rules.new(int(data.seed))
	var flat_events: Array = []
	var cue_map: Dictionary = {}
	var expected_events: Array = []
	for row: Array in data.events:
		expected_events.append([int(row[0]), row[1], row[2], int(row[3]), int(row[4])])
	var samples: Dictionary = {}
	for sample: Dictionary in data.samples:
		samples[int(sample.tick)] = sample
	_sample(live.snapshot(), samples)
	for pair: Array in data.actions:
		for i in range(int(pair[1])):
			var action: String = pair[0]
			var previous_at_boundary: Array = live.snapshot().events
			var reply := live.submit(action)
			_check(reply.accepted, "golden accepted %s at %s" % [action, live.snapshot().tick])
			var turn_events: Array = live.snapshot().events.slice(previous_at_boundary.size())
			for j in range(Rules.DECISION_TICKS):
				var prior := live.snapshot()
				live.tick_once()
				var s := live.snapshot()
				_check_frame(live.layout(), prior, s)
				_sample(s, samples)
				turn_events.append_array(s.events)
			var transaction := batch.step(action)
			_check(transaction.accepted and transaction.snapshot == live.snapshot(), "live and batch snapshots match")
			_check(transaction.events == turn_events, "live and batch event streams match")
			_audit_events(turn_events, cue_map)
			for event: Dictionary in turn_events:
				flat_events.append([event.tick, event.kind, event.lane, event.cue_id,
					event.get("due_tick", event.get("lead_ticks", 0))])
	_check(flat_events == expected_events, "exact golden event tape match: %s" % [flat_events])
	_check(live.snapshot().outcome == data.outcome, "golden wins by reaching the exit")
	_check(samples.is_empty(), "all golden samples covered")
	live.reset(int(data.seed))
	var fresh := Rules.new(int(data.seed))
	_check(live.snapshot() == fresh.snapshot(), "reset matches a new run")


func _counterfactuals() -> void:
	var m := Rules.new(0)
	var flipped := Rules.new(1)
	var altered := m.snapshot()
	altered.lanes.west.shadow_visible = false
	_check(m.snapshot().lanes.west.shadow_visible, "snapshot mutations do not alter the model")
	_check(m.snapshot() == flipped.snapshot(), "seed swap leaves the initial observation identical")
	_check(not m.submit("exit").accepted, "porch cannot trigger exit")
	_check(m.submit("throw_west").reason == "decision_closed", "one request per boundary, including a refused request")
	_check(m.snapshot().next_decision_tick == 20, "used boundary projects the next slot")
	m.tick_once()
	_check(m.step("throw_west").reason == "decision_closed" and m.snapshot().tick == 1, "off-grid step is refused without advancing")
	for i in range(19):
		m.tick_once()
	m.step("approach_west")
	_check(not m.step("cross").accepted, "closed home mouth prevents crossing")
	_wait_to(m, 740)
	_check(m.snapshot().outcome == "active" and m.snapshot().rail.phase == "home", "waiting without a throw neither moves the wall nor wins")
	_check(_lane_bits(m.snapshot(), "west") == "110" and _lane_bits(m.snapshot(), "east") == "110", "without the rail cut both shadows persist")

	m.reset(0)
	_throw_and_approach(m, "west", "east")
	_throw_and_approach(flipped, "west", "east")
	_check(_lane_bits(m.snapshot(), "west") == "000", "eclipsed genuine silhouette goes out")
	_check(_lane_bits(flipped.snapshot(), "west") == "010", "eclipsed decoy silhouette remains on the same patch")
	_check(m.snapshot().rail == flipped.snapshot().rail, "seed changes no rail geometry")
	var bad := m.step("cross")
	_check(bad.accepted and m.snapshot().player.zone == "approach", "wrong open mouth begins a reversible approach")
	_check(_event_at(bad.events, "ink_ridge", 160), "wrong mouth has a physical warning at +20")
	_check(not _event_at(flipped.step("cross").events, "ink_ridge", 160), "the same beam and mouth on the mirror seed stays safe")
	_wait_to(m, 180)
	_check(m.step("back").accepted and m.snapshot().player.zone == "porch", "back after the ink cue cancels the catch before movement")
	_wait_to(m, 240)
	_check(m.snapshot().outcome == "active" and m.snapshot().cues.is_empty(), "aborted approach sheds its cues")
	_check(not m.step("exit").accepted, "cancel cannot place the player beyond the trap")
	_wait_to(flipped, 240)
	_check(flipped.snapshot().player.zone == "gallery" and flipped.snapshot().outcome == "active", "correct crossing reaches gallery, with exit still ahead")
	flipped.step("exit")
	flipped.step()
	_check(flipped.snapshot().outcome == "won", "mirrored route succeeds through the open genuine mouth")

	# Use the last decision before return; the wall waits at its detent during the crossing.
	m.reset(0)
	_throw_and_approach(m, "west", "east")
	_wait_to(m, 620)
	var events: Array = m.step("cross").events
	_check(m.snapshot().rail.phase == "held" and m.snapshot().rail.wall_x_cm == -220, "crossing reservation holds the due return at the detent")
	_check(_event_at(events, "rail_interlock", 640), "interlock has a spatial event")
	_check(not m.step("throw_east").accepted, "a held rail cannot be redirected")
	while m.snapshot().tick < 720:
		var result := m.step()
		events.append_array(result.events)
		if m.snapshot().tick < 720:
			_check(m.snapshot().rail.wall_x_cm == -220, "wall remains out of the swept route")
	_check(_event_at(events, "ink_snap", 720) and _event_at(events, "rail_depart_home", 720), "wrong passage catches, then releases the interlock")
	var cues := {2: {"tick": 580, "kind": "rail_steam_home", "lane": "west"}}
	_audit_events(events, cues)
	_check(m.snapshot().outcome == "caught" and not m.step("exit").accepted, "the open decoy mouth is a terminal loss")
	while m.snapshot().tick < 800:
		_audit_events(m.step().events, cues)
	_check(m.snapshot().rail.phase == "home" and m.snapshot().outcome == "caught", "delayed return completes without changing terminal loss")

	# A changing aperture mid-stroke is visible, but the crossing detent is still disengaged.
	m.reset(0)
	m.step("throw_east")
	m.step("approach_west")
	_wait_to(m, 100)
	_check(m.snapshot().lanes.west.mouth_clear and not m.snapshot().lanes.west.crossing_available, "moving slab has no crossing permit")
	_check(not m.step("cross").accepted, "no slip past a moving slab")
	_check(not m.step("teleport").accepted, "unknown action cannot win")
	_check(m.snapshot().outcome == "active", "no route reaches the exit through those denials")


func _throw_and_approach(m: Rules, wall: String, lane: String) -> void:
	_check(m.step("throw_" + wall).accepted, "smoke throw accepted")
	_check(m.step("approach_" + lane).accepted, "smoke approach accepted")
	_wait_to(m, 140)


func _wait_to(m: Rules, tick: int) -> void:
	var now: int = m.snapshot().tick
	for i in range(now, tick, Rules.DECISION_TICKS):
		_check(m.step().accepted, "wait on decision boundary")
	_check(m.snapshot().tick == tick, "wait ends on expected tick")


func _check_frame(layout: Dictionary, prior: Dictionary, s: Dictionary) -> void:
	_check(s.tick == prior.tick + 1, "live simulation advanced exactly one tick")
	var x: int = s.rail.wall_x_cm
	var half_x: int = layout.wall_half_extents_cm[0]
	var p: Array = s.player.position_cm
	_check(absi(p[1]) > layout.wall_half_extents_cm[1] + layout.body_radius_cm
		or absi(p[0] - x) > half_x + layout.body_radius_cm, "no player overlap with swept slab")
	for lane: String in Rules.LANES:
		var l: Dictionary = layout.lanes[lane]
		var o: Dictionary = s.lanes[lane]
		# Independent centimetre scan for the first contact, including both wall faces.
		var z_hit: int = l.beam_end_cm[1]
		var direction: int = -1 if lane == "west" else 1
		for z: int in range(-layout.wall_half_extents_cm[1], layout.wall_half_extents_cm[1] + 1):
			if absi(2 * (l.rail_ray_cm[0] - x) - direction * z) <= 2 * half_x:
				z_hit = z
				break
		_check(o.beam_reaches_receiver == (z_hit == l.beam_end_cm[1]), "ray follows the slab footprint")
		_check(o.beam_tip_cm == [l.rail_ray_cm[0] - direction * int(z_hit / 2.0), z_hit], "beam tip is the first contact")
		_check(o.mouth_clear == (absi(l.mouth_cm[0] - x) > half_x + layout.body_radius_cm), "mouth follows the slab footprint")
		if o.mouth_clear != prior.lanes[lane].mouth_clear:
			_check(_event_at(s.events, "mouth_open" if o.mouth_clear else "mouth_close", s.tick), "aperture transition emitted an event")
		if o.beam_reaches_receiver != prior.lanes[lane].beam_reaches_receiver:
			_check(_event_at(s.events, "beam_restore" if o.beam_reaches_receiver else "beam_cut", s.tick), "beam transition emitted an event")


func _audit_events(events: Array, cues: Dictionary) -> void:
	for e: Dictionary in events:
		if e.type == "cue":
			_check(not cues.has(e.cue_id), "cue IDs are unique")
			cues[e.cue_id] = e
			_check(e.due_tick >= e.tick + Rules.MIN_CUE_LEAD, "cue projects ≥40 ticks of lead")
			_check(e.position_cm.size() == 2, "cue has a world anchor")
		elif e.type == "commit":
			if _check(cues.has(e.cue_id), "commit has a preceding physical cue: %s" % e.kind):
				var cue: Dictionary = cues[e.cue_id]
				_check(e.tick - cue.tick == e.lead_ticks and e.lead_ticks >= Rules.MIN_CUE_LEAD, "commit lead is audited: %s" % e.kind)
				if e.kind == "ink_snap":
					_check(cue.kind == "ink_ridge" and cue.lane == e.lane, "catch uses its own physical ink cue")


func _event_at(events: Array, kind: String, tick: int) -> bool:
	for event: Dictionary in events:
		if event.kind == kind and event.tick == tick:
			return true
	return false


func _sample(s: Dictionary, samples: Dictionary) -> void:
	if not samples.has(s.tick):
		return
	var expected: Dictionary = samples[s.tick]
	_check(s.rail.wall_x_cm == expected.x and s.rail.phase == expected.phase and s.player.zone == expected.zone
		and _lane_bits(s, "west") == expected.west and _lane_bits(s, "east") == expected.east,
		"golden sample at %s" % s.tick)
	samples.erase(s.tick)


func _lane_bits(s: Dictionary, lane: String) -> String:
	var l: Dictionary = s.lanes[lane]
	return "%d%d%d" % [int(l.beam_reaches_receiver), int(l.shadow_visible), int(l.mouth_clear)]


func _check(condition: bool, message: String) -> bool:
	if not condition:
		_failures += 1
		printerr("FAIL: ", message)
	return condition

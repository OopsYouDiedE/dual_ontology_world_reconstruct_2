extends SceneTree
## Headless rule-object sweep. See rule_sweep.md for the finite domains.
const Contracts = preload("res://scenes/expedition_01/ExpeditionContracts.gd")
const Facts = preload("res://scenes/expedition_01/ArchiveFacts.gd")
const ALPHABETS := {
	"a": ["both_p", "both_h", "both_125", "both_1000", "p_250", "p_375", "h_250", "h_375", "none", "abandon", "retry", "reset"],
	"b": ["loud", "quiet_500", "quiet_750", "pardon", "retry", "reset"],
	"archive": ["dual", "lock", "hale", "cross", "door_paired", "comparison", "hale_comparison", "hale_follow"],
}
const DEPTH := {"a": 5, "b": 22, "archive": 5}
const EVIDENCE := {"dual": "dual_gaze_b2", "lock": "solo_lock_b3", "hale": "hale_saw_crossing_b3", "cross": "solo_crossing_b3"}
const GATES := {
	"door_paired": ["dual_gaze_b2"],
	"comparison": ["dual_gaze_b2", "solo_lock_b3"],
	"hale_comparison": ["dual_gaze_b2", "hale_saw_crossing_b3", "solo_lock_b3"],
	"hale_follow": ["solo_crossing_b3"],
}
var error := {}
var edges := 0
var calls := 0
var coverage := {}

func _initialize() -> void:
	var suite := ""
	var replay := false
	var trace := PackedStringArray()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--suite="): suite = arg.trim_prefix("--suite=")
		elif arg.begins_with("--trace="):
			replay = true
			trace = arg.trim_prefix("--trace=").split(",", false)
		elif not arg.begins_with("--run-seed="):
			printerr("Unknown argument: ", arg)
			quit(2)
			return
	if (suite != "" or replay) and not ALPHABETS.has(suite):
		printerr("Use --suite=a|b|archive (required with --trace).")
		quit(2)
		return
	for name in ALPHABETS if suite.is_empty() else [suite]:
		var start := Time.get_ticks_usec()
		edges = 0
		calls = 0
		coverage.clear()
		var states := 0
		if replay:
			for action in trace:
				if action not in ALPHABETS[name]:
					printerr("Unknown action: ", action)
					quit(2)
					return
			edges = trace.size()
			play(name, trace)
		else:
			states = sweep(name)
		if not error.is_empty():
			printerr("COUNTEREXAMPLE ", JSON.stringify(error))
			quit(1)
			return
		print("PASS ", JSON.stringify({"suite": name, "depth": trace.size() if replay else DEPTH[name],
			"edges": edges, "replayed_action_calls": calls, "quotient_states": states,
			"outcomes_on_checked_edges": coverage, "elapsed_ms": (Time.get_ticks_usec() - start) / 1000.0}))
	quit()

func sweep(suite: String) -> int:
	var frontier: Array[PackedStringArray] = [PackedStringArray()]
	var seen := {}
	var root_key := play(suite, frontier[0])
	if suite == "b": seen[root_key] = true
	for depth in range(1, DEPTH[suite] + 1):
		var next: Array[PackedStringArray] = []
		for prefix in frontier:
			for action in ALPHABETS[suite]:
				var trace := prefix.duplicate()
				trace.append(action)
				edges += 1
				var key := play(suite, trace, true)
				if not error.is_empty(): return 0
				if suite == "b":
					if seen.has(key): continue
					seen[key] = true
				if depth < DEPTH[suite]: next.append(trace)
		frontier = next
	return seen.size()

func play(suite: String, trace: PackedStringArray, tail_only := false) -> String:
	var actual: RefCounted = Facts.new() if suite == "archive" else Contracts.new()
	var model := {}
	match suite:
		"a": model = {"first": 0, "time": 0, "opened": 0, "solo_since": -1, "dark_until": -1, "breaches": 0}
		"b": model = {"progress": 0, "quiet_ms": 0, "spent": false, "breaches": 0}
		"archive": model = {"facts": {}, "log": [], "last": {}}
	for i in trace.size():
		calls += 1
		var check := not tail_only or i == trace.size() - 1
		var pair: Array
		match suite:
			"a": pair = custody(actual, model, trace[i], check)
			"b": pair = iron(actual, model, trace[i], check)
			"archive": pair = archive(actual, model, trace[i], i, check)
		if check:
			if pair[0] != pair[1]:
				var prefix := trace.slice(0, i + 1)
				error = {"suite": suite, "trace": prefix, "expected": pair[0], "actual": pair[1],
					"replay_args": "-- --suite=%s --trace=%s --run-seed=%d" % [suite, ",".join(prefix), configured_seed()]}
				break
			var label: String = pair[2]
			coverage[label] = coverage.get(label, 0) + 1
	return JSON.stringify(model) if suite == "b" else ""

func custody(c, m: Dictionary, action: String, check: bool) -> Array:
	var event := ""
	var actual := ""
	var expired := false
	if action == "reset" or action == "retry" or action == "abandon":
		match action:
			"reset": c.reset(); m.breaches = 0
			"retry": c.soft_reset()
			"abandon": c.a_abandon()
		if action != "abandon" or m.dark_until < 0:
			m.first = 0
			m.solo_since = -1
			m.dark_until = -1
	else:
		var parts := action.split("_")
		var player := parts[0] == "both" or parts[0] == "p"
		var hale := parts[0] == "both" or parts[0] == "h"
		var dt := 125
		var first := 1
		if parts.size() == 2:
			if parts[1].is_valid_int(): dt = int(parts[1])
			elif parts[1] == "h": first = 2
		actual = c.a_step(dt / 1000.0, int(player) + int(hale), first, player, hale)
		m.time += dt
		if m.dark_until >= 0:
			if m.time >= m.dark_until:
				m.dark_until = -1
				expired = true
		elif m.first == 0:
			if player and hale:
				m.first = first
				m.opened = m.time
				event = "overlap"
		else:
			var second_only: bool = (hale and not player) if m.first == 1 else (player and not hale)
			if second_only:
				if m.solo_since < 0: m.solo_since = m.time - dt
				if m.time - m.solo_since >= 620:
					event = "release"
					m.first = 0
					m.solo_since = -1
				else: event = "overlap"
			elif player and hale and m.time - m.opened <= 1000:
				m.solo_since = -1
				event = "overlap"
			else:
				event = "breach"
				m.dark_until = m.time + 3000
				m.breaches += 1
				m.first = 0
				m.solo_since = -1
	if not check: return []
	var phase := "blackout" if m.dark_until >= 0 else ("overlap" if m.first else "idle")
	var remaining := maxi(0, m.dark_until - m.time)
	return [[event, phase, m.first, m.breaches, remaining],
		[actual, c.a_state, c.a_role if c.a_state == "overlap" else 0, c.a_breaches, roundi(c.a_blackout * 1000)],
		"blackout_expired" if expired else (event if not event.is_empty() else phase)]

func iron(c, m: Dictionary, action: String, check: bool) -> Array:
	var expected: Variant = null
	var actual: Variant = null
	match action:
		"loud":
			actual = c.b_loud_step()
			expected = ""
			if m.progress < 9:
				m.progress += 1
				if m.progress == 9:
					m.breaches += 1
					expected = "remembered"
				elif m.progress in [3, 6]: expected = "call"
		"quiet_500", "quiet_750":
			var dt := int(action.get_slice("_", 1))
			c.b_quiet(dt / 1000.0)
			# Quiet erases a pending bead, preserving completed groups of three.
			if m.progress % 3 != 0:
				m.quiet_ms += dt
				if m.quiet_ms > 1200:
					m.progress -= 1
					m.quiet_ms = 0
		"pardon":
			actual = c.b_pardon()
			expected = m.progress == 9 and not m.spent
			if expected:
				m.spent = true
				m.progress = 0
				m.quiet_ms = 0
		"retry":
			c.soft_reset()
			m.progress -= m.progress % 3
			m.quiet_ms = 0
		"reset":
			c.reset()
			m.merge({"progress": 0, "quiet_ms": 0, "spent": false, "breaches": 0}, true)
	if not check: return []
	var label := action
	if action == "loud": label = expected if expected != "" else "loud"
	if action == "pardon":
		label = "pardoned" if expected else ("pardon_exhausted" if m.progress == 9 else "pardon_premature")
	return [[expected, m.progress / 3, m.progress % 3, m.progress == 9, 0 if m.spent else 1, m.spent, m.breaches, float(m.quiet_ms)],
		[actual, c.b_calls, c.b_beads(), c.b_remembered, c.b_pardons, c.b_pardon_used, c.b_breaches, c.b_grace * 1000], label]

func configured_seed() -> int:
	var seed_value := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--run-seed="): seed_value = int(arg.trim_prefix("--run-seed="))
	return seed_value

func archive(f, m: Dictionary, action: String, index: int, check: bool) -> Array:
	var actual: Variant = null
	var expected: Variant = null
	var entry := {}
	var label := action
	if EVIDENCE.has(action):
		var fact: String = EVIDENCE[action]
		var source := "observation-%d" % (index + 1)
		f.record(fact, source)
		if not m.facts.has(fact):
			m.facts[fact] = source
			entry = {"fact": fact, "intent": "observe", "rule": source, "delta": {fact: true}}
		else: label = "duplicate_fact"
	else:
		actual = f.evaluate(action)
		var missing := PackedStringArray()
		for fact in GATES[action]:
			if not m.facts.has(fact): missing.append(fact)
		expected = missing.is_empty()
		var reason := "witnessed" if expected else ", ".join(missing)
		label += ":allow" if expected else ":deny"
		if m.last.get(action) != reason:
			m.last[action] = reason
			entry = {"decision": action, "intent": action, "rule": GATES[action], "allowed": expected, "reason": reason}
		else: label = "duplicate_decision"
	if not entry.is_empty():
		entry.merge({"tick": 0, "seed": configured_seed()})
		m.log.append(entry)
	if not check: return []
	var predicates := [[], []]
	for gate in GATES:
		predicates[0].append(GATES[gate].all(func(fact): return m.facts.has(fact)))
		predicates[1].append(f.allows(gate))
	for fact in EVIDENCE.values():
		predicates[0].append(m.facts.has(fact))
		predicates[1].append(f.has_fact(fact))
	var snapshot: Dictionary = f.snapshot()
	var observed := [actual, snapshot.seed, snapshot.facts, snapshot.decisions, predicates[1]]
	# Mutate a separate snapshot, then check the live values and nested log rows.
	var disposable: Dictionary = f.snapshot()
	disposable.facts.clear()
	if not disposable.decisions.is_empty():
		var row: Dictionary = disposable.decisions[0]
		if row.has("delta"): row.delta.clear()
		else: row.rule.clear()
		disposable.decisions.clear()
	return [[expected, configured_seed(), m.facts, m.log, predicates[0], snapshot],
		observed + [f.snapshot()], label]

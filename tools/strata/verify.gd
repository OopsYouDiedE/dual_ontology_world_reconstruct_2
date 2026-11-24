extends SceneTree

const Rules = preload("res://scenes/physics_lab/strata/StrataRules.gd")
const GOLDEN := "res://tools/strata/golden.json"
const CUE_COMMITS := {
	"strain_tripped": "strain_trip", "form_changed": "form_change",
	"hatch_opened": "hatch_open", "returned": "return_ready",
}

var failures: Array[String] = []
var checks := 0
var inputs: Dictionary


func _initialize() -> void:
	var golden: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(GOLDEN))
	inputs = golden.inputs
	for run in golden.runs:
		_check_golden(run)
	_counterfactuals()
	_search_without("transform")
	_search_without("boost")
	for failure in failures:
		printerr(failure)
	print("Strata: %d checks, %d failures" % [checks, failures.size()])
	quit(0 if failures.is_empty() else 1)


func _check(passes: bool, message: String) -> void:
	checks += 1
	if not passes:
		failures.append(message)


func _replay(decisions: String, state: Dictionary = {}, trace: Variant = null) -> Dictionary:
	if state.is_empty():
		state = Rules.initial()
	for letter in decisions.replace(" ", ""):
		var action: String = inputs[letter]
		_check(action in Rules.legal_actions(state), "%s legal at tick %d" % [action, state.tick])
		state = Rules.advance(state, action, trace)
	return state


func _check_golden(run: Dictionary) -> void:
	var state := Rules.initial()
	var tape: Array = []
	var boundaries: Dictionary = {}
	for letter in run.decisions.replace(" ", ""):
		var action: String = inputs[letter]
		var before := state.duplicate(true)
		var next := Rules.advance(state, action, tape)
		_check(action in Rules.legal_actions(state), "%s input legal at %s" % [run.id, state.tick])
		_check(state == before and Rules.step(state, action) == next, "step purity/parity")
		_check(next.tick == state.tick + Rules.DECISION_TICKS, "decision tick cadence")
		state = next
		boundaries[str(state.tick)] = Rules.snapshot(state)
	for tick in run.checkpoints:
		for field in run.checkpoints[tick]:
			_check(boundaries.get(tick, {}).get(field) == run.checkpoints[tick][field],
				"%s checkpoint %s.%s" % [run.id, tick, field])
	_check(JSON.stringify(tape).sha256_text() == run.tape_sha256, "%s tape digest" % run.id)
	_check(state.mode == "won" and state.landing == 3, "%s reaches powered crown" % run.id)
	_check(Rules.legal_actions(state).is_empty() and Rules.step(state, "wait") == state,
		"won is terminal")
	var events := _audit_tape(tape, run.id)
	for id in run.commits:
		_check(events.get(id) == run.commits[id].map(func(tick): return int(tick)), "%s exact %s ticks" % [run.id, id])
	print("%s: won at boundary %d, %d bank remaining, tape %s" % [run.id, state.tick,
		state.charge, JSON.stringify(tape).sha256_text()])


func _audit_tape(tape: Array, label: String) -> Dictionary:
	var seen_boundary: Dictionary = {}
	var commits: Dictionary = {}
	var min_visible := Rules.WARNING_TICKS
	var previous: Dictionary = {}
	for s in tape:
		if not previous.is_empty():
			_check(s.tick == previous.tick + 1, "%s integer cadence" % label)
			_check(s.height_cm >= previous.height_cm or previous.mode == "return", "only cradle descends")
		previous = s
		for field in ["tick", "height_cm", "strain", "charge", "landing"]:
			_check(s[field] is int, "integer tick metric %s" % field)
		_check(s.strain >= 0 and s.strain <= s.strain_hard and s.charge >= 0 and s.charge <= s.charge_max,
			"meters in physical range")
		_check(s.route in ["anchor", "rail", "stairs"], "known lane")
		if s.route == "rail":
			_check(s.form == "copper", "rail closes with Copper")
		if s.route == "stairs":
			_check(s.form == "ceramic", "stairs admit the compact Ceramic core")
		for warning in s.warnings:
			_check(warning.due_tick - warning.started_tick == Rules.WARNING_TICKS and
				warning.due_tick - s.tick == warning.ticks_left and warning.ticks_left > 0, "warning clock")
			var key := "%s:%s" % [warning.id, warning.started_tick]
			if s.tick % Rules.DECISION_TICKS == 0 and not seen_boundary.has(key):
				seen_boundary[key] = s.tick
				min_visible = mini(min_visible, warning.ticks_left)
				_check(warning.ticks_left >= 40, "%s first boundary offers at least 40 ticks" % key)
		for event in s.events:
			_check(event.tick == s.tick, "event timestamp")
			if not commits.has(event.id):
				commits[event.id] = []
			commits[event.id].append(event.tick)
			if CUE_COMMITS.has(event.id):
				var key := "%s:%s" % [CUE_COMMITS[event.id], event.tick - Rules.WARNING_TICKS]
				_check(seen_boundary.has(key) and event.tick - seen_boundary.get(key, event.tick) >= 40,
					"%s has a linked visible warning before commitment" % event.id)
	print("%s: minimum first-boundary warning lead %d ticks" % [label, min_visible])
	return commits


func _counterfactuals() -> void:
	var sump := Rules.initial()
	var snap := Rules.snapshot(sump)
	snap.events.append({"id": "forged", "tick": 0})
	snap.actions.clear()
	_check(Rules.snapshot(sump).events.is_empty() and not Rules.legal_actions(sump).is_empty(), "view copy")
	var geometry := Rules.terrain()
	geometry.bands[0].to_cm = 0
	_check(Rules.terrain().bands[0].to_cm == 420, "terrain copy")
	var invalid_trace: Array = []
	_check(Rules.advance(sump, "open_hatch", invalid_trace) == sump and invalid_trace.is_empty(),
		"invalid input does not advance or emit")
	var copper := Rules.step(sump, "climb")
	var ceramic := _replay("TWWW C")
	_check(copper.height_cm == 100 and copper.strain == 100 and Rules.snapshot(copper).circuit == "rail" and
		ceramic.height_cm == 80 and ceramic.strain == 60 and Rules.snapshot(ceramic).circuit == "open" and
		"boost" not in Rules.legal_actions(ceramic), "same climb command produces distinct material lanes/load/circuit")

	var switchback := _replay("CCCCC")
	var restored := Rules.step(switchback, "unload")
	_check(restored.strain == 340 and restored.charge == 273 and Rules.snapshot(restored).warnings.is_empty(),
		"Copper unload closes the recovery loop and clears the warning")
	var pressed := _replay("TWWW", restored)
	_check(pressed.form == "ceramic" and pressed.strain == restored.strain and
		pressed.charge == restored.charge - Rules.PRESS_COST,
		"the same loaded harness survives a paid core conversion")
	var same_anchor_bleed := Rules.step(pressed, "unload")
	_check(same_anchor_bleed.strain == 180 and same_anchor_bleed.charge == pressed.charge,
		"transforming this same core changes the anchor's unload circuit and rate")
	var return_tape: Array = [Rules.snapshot(switchback)]
	return_tape[0].events.clear()
	var reset := _replay("WWWWWW", switchback, return_tape)
	var reset_events := _audit_tape(return_tape, "delayed lower vent")
	_check(reset_events.get("strain_tripped") == [144] and reset_events.get("returned") == [204] and
		reset.landing == 0 and reset.charge == sump.charge and reset.strain == 0, "automatic return after idle")
	_check(_replay("CCCCC UUUUUU TWWW CCCCCCCC UUU TWWW BBCCC UUUUUU HWWW", reset).mode == "won",
		"ordinary retry after cradle return")

	var ceramic_gallery := _replay("CCCCC UUUUUU TWWW CCCCCCCC")
	var dissipated := Rules.step(ceramic_gallery, "unload")
	_check(dissipated.strain == 275 and dissipated.charge == ceramic_gallery.charge and
		Rules.snapshot(dissipated).circuit == "open", "ceramic dissipates 160 rather than charging")
	var ceramic_top_tape: Array = []
	var steep_stair := _replay("UUU CCCCCCCC U", ceramic_gallery, ceramic_top_tape)
	var stair_events := _audit_tape(ceramic_top_tape, "steep stair")
	_check(steep_stair.mode == "return" and stair_events.get("strain_tripped") == [685] and
		stair_events.get("landed") == [675], "top stair reaches crown but cannot bleed fast enough")

	var gallery := _replay("UUU TWWW", ceramic_gallery)
	var hand := Rules.step(gallery, "climb")
	var motor := Rules.step(gallery, "boost")
	_check(hand.height_cm == 1100 and hand.strain == 180 and hand.charge == 232 and
		motor.height_cm == 1200 and motor.strain == 60 and motor.charge == 132,
		"one boosted beat exchanges 100 bank for 100 cm and 120 less strain")
	var crown := _replay("BBCCC", gallery)
	_check("open_hatch" not in Rules.legal_actions(crown), "topping out does not open the hatch")
	var insufficient := _replay("UUUU", crown)
	var sufficient := Rules.step(insufficient, "unload")
	_check(insufficient.charge == 112 and "open_hatch" not in Rules.legal_actions(insufficient) and
		sufficient.charge == 132 and "open_hatch" in Rules.legal_actions(sufficient),
		"one more regeneration beat pays the hatch")

	var under_vented := _replay("UU TWWW BBCCC UU", ceramic_gallery)
	_check(under_vented.mode == "return", "one less ceramic bleed beat causes a relief trip on the same upper inputs")

	var middle := _replay("UUUUUU", switchback)
	var middle_last := _replay("BCC", middle)
	var early := Rules.step(middle_last, "boost")
	_check(Rules.snapshot(middle_last).boost_cost_next == 108 and early.charge == middle_last.charge - 108,
		"part of the decision idles after landing and spends no bank")
	var late := _replay("CCBB", middle)
	_check(early.height_cm == late.height_cm and early.charge == late.charge and early.strain == late.strain and
		Rules.snapshot(early).warnings[0].ticks_left == 36 and Rules.snapshot(late).warnings[0].ticks_left == 27,
		"same four middle beats, differently ordered, yield different safety clocks")
	_check(_replay("WU", early).mode == "return" and _replay("UU", late).mode == "ready",
		"one idle beat can be worse than the late boost order")


## Exhaust the restricted, first-attempt public-input graph. At ready, wait
## cannot improve meters or topology and can only make an armed clock older.
## A reset restores the initial state modulo absolute tick, so prune returns.
## Only the age of an active cue affects successors; absolute time and the
## previous receipt are not part of the search key.
func _search_without(forbidden: String) -> void:
	var queue: Array[Dictionary] = [Rules.initial()]
	var explored: Dictionary = {}
	var reached := 0
	var safe_crown_bank := -1
	var found := false
	while not queue.is_empty():
		var state: Dictionary = queue.pop_back()
		var key := [state.landing, state.height_cm, state.form, state.mode, state.target_form,
			state.strain, state.charge, state.regen_remainder,
			-1 if state.strain_start < 0 else state.tick - state.strain_start,
			-1 if state.operation_start < 0 else state.tick - state.operation_start]
		if explored.has(key):
			continue
		explored[key] = true
		reached = maxi(reached, state.height_cm)
		if state.landing == 3 and state.form == "copper" and state.mode == "ready" and \
				state.strain < Rules.STRAIN_WARN:
			safe_crown_bank = maxi(safe_crown_bank, state.charge)
		if state.mode == "won":
			found = true
			break
		for action in Rules.legal_actions(state):
			if action == forbidden or (action == "wait" and state.mode == "ready"):
				continue
			var next := Rules.step(state, action)
			if next.mode != "return":
				queue.append(next)
	_check(not found, "no first-attempt win without %s" % forbidden)
	print("without %s: %d distinct states, highest point %d cm, safe Copper crown bank %s, won=%s" %
		[forbidden, explored.size(), reached, str(safe_crown_bank) if safe_crown_bank >= 0 else "unreached", found])

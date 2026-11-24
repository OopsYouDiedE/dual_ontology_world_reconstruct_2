extends RefCounted
## A07 Strata. All time and physical state use integer ticks/units.

const TICK_HZ := 60
const DECISION_TICKS := 20
# A warning raised in a decision still has at least two full decisions left
# when it first reaches a boundary snapshot.
const WARNING_TICKS := 60
const STRAIN_WARN := 420
const STRAIN_HARD := 660
const CHARGE_MAX := 280
const INITIAL_CHARGE := 253
const PRESS_COST := 24
const HATCH_COST := 130
const COPPER_UNLOAD_PER_TICK := 4
const CERAMIC_UNLOAD_PER_TICK := 8
const STRAIN_PER_CHARGE := 4

const LANDINGS := [
	{"id": 0, "name": "Sump", "height_cm": 0},
	{"id": 1, "name": "Switchback", "height_cm": 420},
	{"id": 2, "name": "Gallery", "height_cm": 1000},
	{"id": 3, "name": "Crown", "height_cm": 1620},
]
# Each pair spans the same rise. Rack teeth set the rail speeds; the exposed
# rack pitches set the different hand loads. The stairs divide the rise into
# smaller lifts. No band gates change rules according to prior inputs.
const BANDS := [
	{"from_cm": 0, "to_cm": 420, "rail_hand_cm_per_tick": 5, "rail_boost_cm_per_tick": 10,
		"stairs_cm_per_tick": 4, "rail_hand_strain_per_tick": 5,
		"rail_boost_strain_per_tick": 2, "stairs_strain_per_tick": 3, "rail_boost_draw_per_tick": 2},
	{"from_cm": 420, "to_cm": 1000, "rail_hand_cm_per_tick": 5, "rail_boost_cm_per_tick": 10,
		"stairs_cm_per_tick": 4, "rail_hand_strain_per_tick": 10,
		"rail_boost_strain_per_tick": 3, "stairs_strain_per_tick": 3, "rail_boost_draw_per_tick": 6},
	{"from_cm": 1000, "to_cm": 1620, "rail_hand_cm_per_tick": 5, "rail_boost_cm_per_tick": 10,
		"stairs_cm_per_tick": 4, "rail_hand_strain_per_tick": 9,
		"rail_boost_strain_per_tick": 3, "stairs_strain_per_tick": 4, "rail_boost_draw_per_tick": 5},
]


static func terrain() -> Dictionary:
	return {"landings": LANDINGS.duplicate(true), "bands": BANDS.duplicate(true)}


static func initial() -> Dictionary:
	return {"tick": 0, "landing": 0, "height_cm": 0, "route": "anchor",
		"form": "copper", "mode": "ready", "target_form": "", "strain": 0,
		"charge": INITIAL_CHARGE, "regen_remainder": 0, "strain_start": -1,
		"operation_start": -1, "events": []}


static func legal_actions(state: Dictionary) -> Array[String]:
	var actions: Array[String] = []
	if state.mode == "won":
		return actions
	actions.append("wait")
	if state.mode != "ready":
		return actions
	if state.landing < BANDS.size():
		actions.append("climb")
		var cost := _boost_cost_next(state)
		if cost > 0 and state.charge >= cost:
			actions.append("boost")
	if state.route == "anchor":
		if state.strain > 0:
			actions.append("unload")
		if state.charge >= PRESS_COST and state.strain < STRAIN_WARN:
			actions.append("transform")
		if state.landing == BANDS.size() and state.form == "copper" and \
				state.charge >= HATCH_COST and state.strain < STRAIN_WARN:
			actions.append("open_hatch")
	return actions


static func snapshot(state: Dictionary) -> Dictionary:
	var result := state.duplicate(true)
	result.erase("operation_start")
	result.erase("strain_start")
	result.erase("regen_remainder")
	result.merge({"strain_warn": STRAIN_WARN, "strain_hard": STRAIN_HARD,
		"charge_max": CHARGE_MAX, "press_cost": PRESS_COST, "hatch_cost": HATCH_COST,
		"boost_cost_next": _boost_cost_next(state), "circuit": _circuit(state),
		"unload_rate": COPPER_UNLOAD_PER_TICK if state.form == "copper" else CERAMIC_UNLOAD_PER_TICK,
		"strain_per_charge": STRAIN_PER_CHARGE,
		"warnings": _warnings(state), "actions": legal_actions(state)})
	return result


static func step(state: Dictionary, action: String) -> Dictionary:
	return advance(state, action)


## Trace snapshots carry events for their individual tick; the returned state
## carries the whole decision's events. Validation is atomic at the boundary.
static func advance(state: Dictionary, action: String, trace: Variant = null) -> Dictionary:
	var next := state.duplicate(true)
	if action not in legal_actions(state):
		return next
	var events: Array = []
	for i in range(DECISION_TICKS):
		next.tick += 1
		next.events = []
		# A timed operation can only be initiated once during a decision.
		if i == 0:
			_begin(next, action)
		var landed_before: int = next.landing
		_integrate(next, action)
		if landed_before != next.landing:
			action = "wait"
		events.append_array(next.events)
		if trace != null:
			trace.append(snapshot(next))
	next.events = events
	return next


static func _boost_cost_next(state: Dictionary) -> int:
	if state.mode != "ready" or state.form != "copper" or state.landing >= BANDS.size():
		return 0
	var band: Dictionary = BANDS[state.landing]
	var rise: int = band.to_cm - state.height_cm
	var speed: int = band.rail_boost_cm_per_tick
	@warning_ignore("integer_division")
	var needed := (rise + speed - 1) / speed
	return mini(DECISION_TICKS, needed) * int(band.rail_boost_draw_per_tick)


static func _circuit(state: Dictionary) -> String:
	if state.mode == "hatch" or state.mode == "won":
		return "hatch"
	if state.form != "copper" or state.mode != "ready":
		return "open"
	return "rail" if state.route == "rail" else "regenerative"


static func _warning(state: Dictionary, id: String, started_tick: int) -> Dictionary:
	var due_tick := started_tick + WARNING_TICKS
	return {"id": id, "started_tick": started_tick, "due_tick": due_tick,
		"ticks_left": due_tick - state.tick}


static func _warnings(state: Dictionary) -> Array[Dictionary]:
	var warnings: Array[Dictionary] = []
	if state.strain_start >= 0:
		warnings.append(_warning(state, "strain_trip", state.strain_start))
	match state.mode:
		"thermal_press": warnings.append(_warning(state, "form_change", state.operation_start))
		"hatch": warnings.append(_warning(state, "hatch_open", state.operation_start))
		"return": warnings.append(_warning(state, "return_ready", state.operation_start))
	return warnings


static func _event(state: Dictionary, id: String) -> void:
	state.events.append({"id": id, "tick": state.tick})


static func _begin(state: Dictionary, action: String) -> void:
	match action:
		"transform":
			state.charge -= PRESS_COST
			state.mode = "thermal_press"
			state.operation_start = state.tick
			state.target_form = "ceramic" if state.form == "copper" else "copper"
			_event(state, "form_started")
		"open_hatch":
			state.charge -= HATCH_COST
			state.mode = "hatch"
			state.operation_start = state.tick
			_event(state, "hatch_started")


static func _integrate(state: Dictionary, action: String) -> void:
	if state.mode != "ready":
		if state.operation_start >= 0 and state.tick >= state.operation_start + WARNING_TICKS:
			_complete_operation(state)
		return
	match action:
		"climb", "boost": _climb(state, action == "boost")
		"unload": _unload(state)
		"wait": pass # The harness ratchet holds load and altitude with no drift.
	if state.strain < STRAIN_WARN:
		if state.strain_start >= 0:
			state.strain_start = -1
			_event(state, "strain_cleared")
	elif state.strain_start < 0:
		state.strain_start = state.tick
		_event(state, "strain_warning")
	elif state.tick >= state.strain_start + WARNING_TICKS:
		state.strain_start = -1
		state.mode = "return"
		state.operation_start = state.tick
		_event(state, "strain_tripped")


static func _climb(state: Dictionary, boosted: bool) -> void:
	var band: Dictionary = BANDS[state.landing]
	if state.route == "anchor":
		state.route = "rail" if state.form == "copper" else "stairs"
		_event(state, "rail_entered" if state.route == "rail" else "stairs_entered")
	var speed: int = band.stairs_cm_per_tick
	var load_per_tick: int = band.stairs_strain_per_tick
	if state.route == "rail":
		if boosted:
			state.charge -= band.rail_boost_draw_per_tick
			speed = band.rail_boost_cm_per_tick
			load_per_tick = band.rail_boost_strain_per_tick
		else:
			speed = band.rail_hand_cm_per_tick
			load_per_tick = band.rail_hand_strain_per_tick
	state.strain = mini(STRAIN_HARD, state.strain + load_per_tick)
	state.height_cm = mini(band.to_cm, state.height_cm + speed)
	if state.height_cm == band.to_cm:
		state.landing += 1
		state.route = "anchor"
		_event(state, "landed")


static func _unload(state: Dictionary) -> void:
	var copper: bool = state.form == "copper"
	var release := mini(state.strain, COPPER_UNLOAD_PER_TICK if copper else CERAMIC_UNLOAD_PER_TICK)
	state.strain -= release
	if copper:
		var total: int = state.regen_remainder + release
		@warning_ignore("integer_division")
		state.charge = mini(CHARGE_MAX, state.charge + total / STRAIN_PER_CHARGE)
		state.regen_remainder = total % STRAIN_PER_CHARGE if state.charge < CHARGE_MAX else 0


static func _complete_operation(state: Dictionary) -> void:
	state.operation_start = -1
	match state.mode:
		"thermal_press":
			state.form = state.target_form
			state.target_form = ""
			state.mode = "ready"
			_event(state, "form_changed")
		"hatch":
			state.mode = "won"
			_event(state, "hatch_opened")
		"return":
			# The automatic safety cradle takes the player back to the sump and
			# releases the spring; the sump charger restores the initial bank.
			var fresh := initial()
			fresh.erase("tick")
			fresh.erase("events")
			state.merge(fresh, true)
			_event(state, "returned")

extends RefCounted
## A09 authority. Only accepted commands change a run; all returned data is detached.

const TICK_HZ := 60
const WARNING_TICKS := 48
const MOVE_TICKS := 12
const MAX_WAIT := 600
const NOTCH_UNITS := 12
const TURN_NOTCHES := 8
const TURN_UNITS := NOTCH_UNITS * TURN_NOTCHES
const HEAD_CAP := 96
const DRAIN_TICKS := 3
const WORKING_MIN := 54
const WORKING_DRAW := 48
const COOLANT_DRAW := 72
const LANES := ["north", "south"]
const GUIDE_ID := "cold_cast_guide"

const ROOMS := {
	"dais": {"label": "Balance Dais", "x": 0, "z": 0},
	"north_sill": {"label": "North Sill", "x": 200, "z": -200},
	"south_sill": {"label": "South Sill", "x": 200, "z": 200},
	"north_span": {"label": "North Span", "x": 425, "z": -200},
	"south_span": {"label": "South Span", "x": 425, "z": 200},
	"north_pier": {"label": "North Receiver Pier", "x": 650, "z": -200},
	"south_pier": {"label": "South Receiver Pier", "x": 650, "z": 200},
	"gallery": {"label": "Far Gallery", "x": 850, "z": 0},
	"exit": {"label": "Witness Gate", "x": 1050, "z": 0},
}
const FIXED_WALK := [
	["dais", "north_sill"], ["dais", "south_sill"],
	["north_pier", "gallery"], ["south_pier", "gallery"],
]
const EXIT_EDGE := ["gallery", "exit"]
const GUIDES := {
	"liquid": {
		"id": GUIDE_ID, "label": "Liquid return", "span": "", "wet_lane": "",
		"flow": ["feed", "liquid_bed", "return"], "rates": {"shuttle": 4, "vane": 3},
	},
	"north": {
		"id": GUIDE_ID, "label": "North cast", "span": "north_span", "wet_lane": "south",
		"flow": ["feed", "north_diverter", "south_cistern"],
		"walk": [["north_sill", "north_span"], ["north_span", "north_pier"]],
		"rates": {"shuttle": 3, "vane": 2}, "vane_notches": [2, 3], "shuttle_notches": [4, 5, 6],
	},
	"south": {
		"id": GUIDE_ID, "label": "South cast", "span": "south_span", "wet_lane": "north",
		"flow": ["feed", "south_diverter", "north_cistern"],
		"walk": [["south_sill", "south_span"], ["south_span", "south_pier"]],
		"rates": {"shuttle": 2, "vane": 4}, "vane_notches": [4, 5, 6], "shuttle_notches": [1, 2, 3],
	},
}
# Separate logical ports for the front contact and its adjacent painted copy.
const PORTS := {
	"feed": {"x": 100, "z": 0}, "liquid_bed": {"x": 425, "z": 0}, "return": {"x": 640, "z": 0},
	"north_diverter": {"x": 425, "z": -165}, "south_diverter": {"x": 425, "z": 165},
	"north_cistern": {"x": 600, "z": -140}, "south_cistern": {"x": 600, "z": 140},
	"lamp": {"x": 250, "z": 0}, "liquid_surface": {"x": 425, "z": 0},
	"return_trap": {"x": 610, "z": 0}, "vane_axis": {"x": 510, "z": 0},
	"north_facet": {"x": 425, "z": -188}, "south_facet": {"x": 425, "z": 188},
	"north_receiver": {"x": 650, "z": -202}, "south_receiver": {"x": 650, "z": 202},
	"north_dump": {"x": 650, "z": -78}, "south_dump": {"x": 650, "z": 78},
	"north_fold_shutter": {"x": 506, "z": -226}, "south_fold_shutter": {"x": 506, "z": 226},
	"north_mirror": {"x": 567, "z": -254}, "south_mirror": {"x": 567, "z": 254},
	"north_mark": {"x": 650, "z": -218}, "south_mark": {"x": 650, "z": 218},
}

var _tick := 0
var _room := "dais"
var _travel := {}
var _form := "liquid"
var _pending := {}
var _head := {"north": 0, "south": 0}
var _phase_units := {"shuttle": 0, "vane": 0}
var _screen_closed := false
var _seals := {"north": false, "south": false}
var _outcome := "running"


static func layout() -> Dictionary:
	return {
		"title": "The Meniscus Court", "tick_hz": TICK_HZ,
		"warning_ticks": WARNING_TICKS, "move_ticks": MOVE_TICKS, "max_wait": MAX_WAIT,
		"rooms": ROOMS.duplicate(true), "fixed_walk": FIXED_WALK.duplicate(true),
		"exit_edge": EXIT_EDGE.duplicate(), "guides": GUIDES.duplicate(true), "ports": PORTS.duplicate(true),
		"phase": {"notch_units": NOTCH_UNITS, "turn_notches": TURN_NOTCHES,
			"entities": {"shuttle": "Bronze Shuttle", "vane": "Ceramic Vane"}},
		"hydraulics": {"capacity": HEAD_CAP, "wet_units_per_tick": 1, "dry_drain_ticks": DRAIN_TICKS,
			"working_min": WORKING_MIN, "working_draw": WORKING_DRAW, "coolant_draw": COOLANT_DRAW},
	}


func snapshot() -> Dictionary:
	var optics := _optics()
	var checks := {}
	for lane: String in LANES:
		checks[lane] = _stamp_checks(lane, optics.receiver)
	return {
		"tick": _tick, "player": {"room": _room, "travel": _travel.duplicate()},
		"form": _form, "pending": _pending.duplicate(), "walk_edges": _walk_edges(),
		"support": {"guide": GUIDE_ID, "span": GUIDES[_form].span},
		"flow": {"guide": GUIDE_ID, "paths": [GUIDES[_form].flow.duplicate()],
			"wet_lane": GUIDES[_form].wet_lane, "head": _head.duplicate()},
		"bubble": {"guide": GUIDE_ID, "shuttle": _phase("shuttle"), "vane": _phase("vane")},
		"optics": optics, "stamp_checks": checks, "seals": _seals.duplicate(),
		"gate_open": _gate_open(), "outcome": _outcome, "notice": _notice(),
	}


func apply(command: Dictionary) -> Dictionary:
	var action: Variant = command.get("action")
	var events: Array = []
	if not action is String:
		return _result("unknown_action", events)
	if action == "wait":
		var count: Variant = command.get("ticks")
		if not (count is int or count is float) or not (count >= 1 and count <= MAX_WAIT) or count != int(count):
			return _result("invalid_ticks", events)
		for i in int(count):
			if _outcome == "won":
				break
			_advance(events)
		return _result("", events)
	if _outcome == "won":
		return _result("run_complete", events)
	if not _travel.is_empty():
		return _result("while_walking", events)
	var target: Variant = command.get("target")
	var reason := ""
	match action:
		"move":
			if not target is String or not _can_walk(target):
				reason = "no_walk_edge"
			else:
				_travel = {"from": _room, "to": target, "arrive_tick": _tick + MOVE_TICKS}
				_event(events, "walk_started", _travel)
		"cast":
			if not target is String or not GUIDES.has(target):
				reason = "unknown_form"
			elif not _pending.is_empty():
				reason = "cast_pending"
			elif target == _form:
				reason = "already_in_form"
			else:
				_pending = {"from": _form, "target": target, "due_tick": _tick + WARNING_TICKS,
					"retiring_span": GUIDES[_form].span, "adding_span": GUIDES[target].span, "interlocked": false}
				_event(events, "cast_warning", _pending)
		"cancel":
			if _pending.is_empty():
				reason = "no_pending_cast"
			else:
				_event(events, "cast_cancelled", _pending)
				_pending = {}
		"screen":
			_screen_closed = not _screen_closed
			_event(events, "shutter_changed", {"closed": _screen_closed})
		"stamp":
			reason = _stamp(events)
		_:
			reason = "unknown_action"
	return _result(reason, events)


func _advance(events: Array) -> void:
	_tick += 1
	for entity: String in _phase_units:
		_phase_units[entity] += GUIDES[_form].rates[entity]
	for lane: String in LANES:
		if lane == GUIDES[_form].wet_lane:
			_head[lane] = mini(HEAD_CAP, _head[lane] + 1)
		elif _tick % DRAIN_TICKS == 0:
			_head[lane] = maxi(0, _head[lane] - 1)
	if not _travel.is_empty() and _tick == _travel.arrive_tick:
		_room = _travel.to
		_event(events, "walk_arrived", _travel)
		_travel = {}
		if _room == "exit":
			_outcome = "won"
			_event(events, "won", {"room": _room})
	if not _pending.is_empty() and _tick >= _pending.due_tick:
		var retiring: String = _pending.retiring_span
		if retiring != "" and (_room == retiring or _travel.get("to") == retiring):
			if not _pending.interlocked:
				_pending.interlocked = true
				_event(events, "cast_held", _pending)
		else:
			_form = _pending.target
			_event(events, "cast_committed", _pending)
			_pending = {}


func _walk_edges() -> Array:
	var edges := FIXED_WALK.duplicate(true)
	if _form != "liquid":
		edges.append_array(GUIDES[_form].walk.duplicate(true))
	if _gate_open():
		edges.append(EXIT_EDGE.duplicate())
	return edges


func _can_walk(target: String) -> bool:
	for edge: Array in _walk_edges():
		if target != _room and _room in edge and target in edge:
			return true
	return false


@warning_ignore("integer_division")
func _phase(entity: String) -> Dictionary:
	var units: int = _phase_units[entity]
	var phase := units % TURN_UNITS
	return {"phase": phase, "notch": phase / NOTCH_UNITS,
		"rate": GUIDES[_form].rates[entity], "turns": units / TURN_UNITS}


func _optics() -> Dictionary:
	var ray := {"guide": GUIDE_ID, "screen_closed": _screen_closed, "receiver": "", "mark": "",
		"direct": ["lamp", "liquid_surface", "return_trap"], "folded": []}
	if _form == "liquid":
		return ray
	var facet := _form + "_facet"
	var endpoint := _form + "_dump"
	if _phase("vane").notch in GUIDES[_form].vane_notches:
		endpoint = _form + "_receiver"
		ray.receiver = endpoint
	ray.direct = ["lamp", facet, "vane_axis", endpoint]
	ray.folded = ["lamp", facet, _form + "_fold_shutter"]
	if not _screen_closed:
		ray.mark = _form + "_mark"
		ray.folded.append_array([_form + "_mirror", ray.mark])
	return ray


func _stamp_checks(lane: String, receiver: String) -> Dictionary:
	var checks := {"receiver_lit": receiver == lane + "_receiver",
		"shuttle_docked": _phase("shuttle").notch in GUIDES[lane].shuttle_notches,
		"head_ready": _head[lane] >= WORKING_MIN, "coolant_ready": _head[GUIDES[lane].wet_lane] >= COOLANT_DRAW}
	checks.ready = (_form == lane and not _seals[lane] and checks.receiver_lit
		and checks.shuttle_docked and checks.head_ready and checks.coolant_ready)
	checks.available = checks.ready and _room == lane + "_pier" and _travel.is_empty()
	return checks


func _stamp(events: Array) -> String:
	if _form == "liquid" or _room != _form + "_pier":
		return "wrong_pier"
	if _seals[_form]:
		return "seal_already_set"
	var checks := _stamp_checks(_form, _optics().receiver)
	if not checks.receiver_lit:
		return "receiver_dark"
	if not checks.shuttle_docked:
		return "shuttle_out_of_dock"
	if not checks.head_ready:
		return "low_working_head"
	if not checks.coolant_ready:
		return "low_coolant"
	var coolant: String = GUIDES[_form].wet_lane
	_head[_form] -= WORKING_DRAW
	_head[coolant] -= COOLANT_DRAW
	_seals[_form] = true
	_event(events, "seal_set", {"lane": _form, "coolant_lane": coolant, "head": _head.duplicate()})
	if _gate_open():
		_event(events, "gate_opened", {"edge": EXIT_EDGE.duplicate()})
	return ""


func _gate_open() -> bool:
	return _seals.north and _seals.south


func _notice() -> Dictionary:
	if not _pending.is_empty():
		if _pending.interlocked:
			return {"text": "Cast held. Clear %s or pull Cancel." % ROOMS[_pending.retiring_span].label}
		return {"text": "%s in %d ticks. %s" % [GUIDES[_pending.target].label, _pending.due_tick - _tick,
			"Support stays live until clear." if _pending.retiring_span != "" else "Stand clear of the casting bed."]}
	if _outcome == "won":
		return {"text": "Both witnesses accepted."}
	if _gate_open():
		return {"text": "Both seals set. The Witness Gate is open."}
	return {"text": "Prime one cistern from the opposite cast. Compare the painted mark with the live receiver."}


func _event(events: Array, id: String, payload: Dictionary) -> void:
	var entry := payload.duplicate(true)
	entry["id"] = id
	entry["tick"] = _tick
	events.append(entry)


func _result(reason: String, events: Array) -> Dictionary:
	return {"ok": reason.is_empty(), "reason": reason, "events": events, "state": snapshot()}

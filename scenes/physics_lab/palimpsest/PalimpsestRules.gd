extends RefCounted
## A03 switchyard authority. Time and route decisions use integers only.

const TICK_HZ := 60
const DECISION_TICKS := 20
const PREVIEW_TICKS := 40
const WIDTH := 9
const HEIGHT := 8
const BAY_COUNT := WIDTH * HEIGHT
const START := 0
const LIFT_START := BAY_COUNT - 1
const TURN := -1
const EXIT := -2
const HOLD := -3

const PORT_ACTIONS := ["port_0", "port_1", "port_2"]
const REWIND := "rewind"

# Row-major fixtures. A socket is a directed local rail, a terminal, or a cap.
const INK := [
	[9, 1, 10], [0, 10, 9], [1, 11, 3], [13, 2, 11], [5, 13, 12], [4, 14, 13], [16, 14, 7], [17, 8, 16], [17, 16, 7],
	[18, 1, 0], [11, 0, 2], [3, 12, 10], [4, 20, 2], [3, 23, 22], [6, 15, 5], [5, 6, 24], [26, 15, 8], [8, 16, 25],
	[28, 19, 9], [27, 18, 9], [19, 21, 12], [22, 29, 30], [32, 13, 31], [31, 22, 14], [15, 33, 23], [26, 34, 17], [35, 25, 34],
	[18, 36, 28], [20, 29, 27], [21, 30, 19], [38, 20, 40], [41, 23, 30], [42, 31, 33], [25, 32, 42], [24, 35, 44], [44, 43, 26],
	[37, 45, 28], [29, 27, 46], [29, 37, 46], [40, 38, 48], [32, 49, 50], [-3, 51, 50], [34, 41, 33], [44, 33, 53], [43, 35, 53],
	[55, 36, 54], [45, 56, 47], [39, 46, 48], [38, 39, 40], [39, 58, 59], [59, 42, 60], [41, 52, 61], [43, 53, 62], [62, 61, 52],
	[45, 63, 46], [56, 65, 47], [64, 48, 65], [47, 58, 66], [57, 50, 68], [67, 49, 68], [52, 59, 69], [62, 71, 51], [52, 70, 71],
	[54, 55, 64], [55, 63, 65], [57, 64, 66], [56, 67, 58], [68, 57, 66], [67, 69, 60], [70, 61, 59], [60, 69, 71], [70, -1, 61],
]
const LIFT := [
	[1, 10, -2], [9, 2, 10], [1, 3, 11], [13, 2, 11], [5, 3, 12], [6, 4, 13], [14, 5, 16], [15, 8, 17], [17, 7, 16],
	[19, 18, 0], [0, 1, 19], [1, 20, 2], [2, 3, 21], [22, 4, 21], [6, 23, 4], [14, 6, 5], [7, 17, 25], [26, 8, 7],
	[9, 27, 28], [27, 9, 20], [30, 10, 19], [22, 11, 12], [30, 23, 12], [32, 33, 14], [33, 15, 16], [33, 35, 26], [16, 25, 34],
	[28, 18, 37], [20, 37, 27], [28, 20, 37], [39, 38, 31], [21, 32, 22], [23, 42, 24], [25, 34, 24], [24, 44, 43], [26, 25, 44],
	[-3, 45, 27], [36, 45, 29], [29, 47, 30], [38, 47, 29], [50, 31, 48], [49, 31, 32], [34, 51, 41], [35, 52, 51], [53, 43, 35],
	[36, 37, 54], [56, 36, 38], [46, 56, 39], [39, 49, 40], [58, 40, 50], [51, 42, 59], [41, 59, 60], [44, 43, 60], [61, 52, 62],
	[46, 64, 63], [45, 47, 46], [65, 48, 55], [49, 58, 56], [48, 49, 68], [67, 68, 58], [50, 69, 68], [71, 52, 53], [71, 53, 61],
	[54, 55, 64], [63, 55, 54], [64, 57, 66], [57, 67, 65], [57, 68, 66], [69, 60, 67], [70, 61, 59], [62, 71, 69], [61, 62, 70],
]

var _tick := 0
var _phase := "record"
var _ink_bay := START
var _lift_bay := LIFT_START
var _pins := PackedInt32Array()
var _cured: Array[bool] = []
var _tape := PackedInt32Array()
var _cursor := -1
var _pending := ""
var _flight := {}
var _failure := ""
var _event := {}


func _init() -> void:
	_pins.resize(BAY_COUNT)
	_pins.fill(-1)
	_cured.resize(BAY_COUNT)
	_cured.fill(false)


@warning_ignore("integer_division")
func board() -> Dictionary:
	var bays: Array[Dictionary] = []
	for i in BAY_COUNT:
		bays.append({"id": i, "x": i % WIDTH, "y": i / WIDTH,
			"ink": INK[i].duplicate(), "lift": LIFT[i].duplicate()})
	return {"width": WIDTH, "height": HEIGHT, "start": START, "lift_start": LIFT_START,
		"turn": TURN, "exit": EXIT, "hold": HOLD, "bays": bays}


func snapshot() -> Dictionary:
	return {"tick": _tick, "phase": _phase, "ink_bay": _ink_bay, "lift_bay": _lift_bay,
		"pins": Array(_pins), "cured": _cured.duplicate(), "tape": Array(_tape),
		"cursor": _cursor, "pending": _pending, "in_flight": _flight.duplicate(),
		"failure": _failure, "event": _event.duplicate(), "actions": _actions()}


func preview(action: String) -> Dictionary:
	var reason := _rejection(action)
	var frames: Array[Dictionary] = []
	if reason.is_empty():
		var ghost := get_script().new() as RefCounted
		ghost._copy_from(self)
		ghost.submit(action)
		for _i in PREVIEW_TICKS:
			ghost._advance_tick(true)
			frames.append(ghost.snapshot())
	return {"ok": reason.is_empty(), "reason": reason, "action": action, "base_tick": _tick,
		"horizon_ticks": frames.size(), "frames": frames}


func submit(action: String) -> bool:
	if not _rejection(action).is_empty():
		return false
	_pending = action
	if action == REWIND:
		_phase = "rewind"
		_cursor = _tape.size() - 1
		_queue_lift()
	else:
		var port := PORT_ACTIONS.find(action)
		_flight = _route("ink", _ink_bay, INK[_ink_bay][port], port, port, port, _tape.size())
	return true


func step_tick() -> bool:
	return _advance_tick(false)


func _actions() -> Array[String]:
	var actions: Array[String] = []
	for action: String in PORT_ACTIONS:
		if _rejection(action).is_empty():
			actions.append(action)
	if _rejection(REWIND).is_empty():
		actions.append(REWIND)
	return actions


func _rejection(action: String) -> String:
	if action != REWIND and action not in PORT_ACTIONS:
		return "unknown_action"
	if _phase == "won" or _phase == "failed":
		return "terminal"
	if _phase == "rewind":
		return "rewind_automatic"
	if not _flight.is_empty() or _tick % DECISION_TICKS != 0:
		return "busy"
	if _ink_bay == TURN:
		return "turn_only" if action != REWIND else ""
	if action == REWIND:
		return "need_turn"
	if INK[_ink_bay][PORT_ACTIONS.find(action)] == HOLD:
		return "capped_socket"
	return ""


func _route(deck: String, source: int, target: int, port: int, pulse: int, pin: int,
		tape_index: int) -> Dictionary:
	return {"deck": deck, "from": source, "to": target, "port": port, "pulse": pulse,
		"pin": pin, "tape_index": tape_index, "start_tick": _tick,
		"end_tick": _tick + DECISION_TICKS}


func _queue_lift() -> void:
	var pulse := _tape[_cursor]
	var pin := _pins[_lift_bay]
	var port := (2 - pulse + pin) % PORT_ACTIONS.size()
	_flight = _route("lift", _lift_bay, LIFT[_lift_bay][port], port, pulse, pin, _cursor)


func _advance_tick(include_dwell: bool) -> bool:
	if _flight.is_empty() and not include_dwell:
		return false
	_tick += 1
	if _flight.is_empty() or _tick < _flight.end_tick:
		return true
	_event = _flight
	_flight = {}
	_pending = ""
	if _event.deck == "ink":
		_finish_ink()
	else:
		_finish_lift()
	return true


func _finish_ink() -> void:
	var source: int = _event.from
	var target: int = _event.to
	_pins[source] = _event.port
	_tape.append(_event.port)
	_ink_bay = target
	if target == TURN:
		if _tape.size() != BAY_COUNT:
			_fail("turn_incomplete")
		else:
			_event.code = "turn_ready"
	elif _pins[target] >= 0:
		_fail("ink_revisit")
	else:
		_event.code = "ink_stamped"


func _finish_lift() -> void:
	var target: int = _event.to
	_cursor -= 1
	if target == HOLD:
		_fail("lift_capped")
		return
	_cured[_event.from] = true
	_lift_bay = target
	if target == EXIT:
		if _cursor >= 0 or _cured.has(false):
			_fail("early_exit")
		else:
			_phase = "won"
			_event.code = "exit_open"
	elif _cured[target]:
		_fail("lift_revisit")
	elif _cursor < 0:
		_fail("tape_spent")
	else:
		_event.code = "lift_cured"
		_queue_lift()


func _fail(code: String) -> void:
	_phase = "failed"
	_failure = code
	_cursor = -1
	_event.code = code


func _copy_from(model) -> void:
	_tick = model._tick
	_phase = model._phase
	_ink_bay = model._ink_bay
	_lift_bay = model._lift_bay
	_pins = model._pins.duplicate()
	_cured = model._cured.duplicate()
	_tape = model._tape.duplicate()
	_cursor = model._cursor
	_pending = model._pending
	_flight = model._flight.duplicate()
	_failure = model._failure
	_event = model._event.duplicate()

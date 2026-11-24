extends RefCounted
## A06. One lane, one hinged leaf, two sensors sampling the same stride.

const TICK_HZ := 60
const DECISION_TICKS := 20
const STRIDE_CM := 60
const EXIT := 12
const NEAR_BANK := 4
const FAR_BANK := 8
const PARAPET_TOP_CM := 125
const TALL_EYE_CM := 160
const LOW_EYE_CM := 95
const WATCHER_X_CM := -130
const WATCHER_START_CM := -180
const WATCHER_STEP_CM := 9
const REACH_CM := 100
const RING_TRIP := 80
const RING_CAP := 240
const DANGER_TICKS := 60
const DRIVE_WARNING_TICKS := 60
const LEAF_TRAVEL_TICKS := 40
const DWELL_TICKS := 300
const RECOVERY_TICKS := 60
const ACTIONS := ["wait", "lower", "watch", "creep", "back_watch", "back_creep"]

var _tick: int
var _decision: int
var _outcome: String
var _attempt: int
var _station: int
var _target: int
var _z: int
var _stride_tick: int
var _low: bool
var _leaf_phase: String
var _leaf_angle: int
var _passable: bool
var _leaf_motion_tick: int
var _raise_warning_tick: int
var _leaf_cue: Dictionary
var _ring: int
var _signal: int
var _sampled_surface: String
var _hearing_cue: Dictionary
var _watcher_z: int
var _gaze: bool
var _sight_cue: Dictionary
var _recovery_z: int
var _recovery_watcher_z: int
var _recovery_cue: Dictionary
var _event_serial: int
var _events: Array[Dictionary] = []


func _init() -> void:
	reset()


func reset() -> void:
	_tick = 0
	_decision = -1
	_outcome = "active"
	_attempt = 1
	_station = 0
	_target = 0
	_z = 0
	_stride_tick = -1
	_low = false
	_leaf_phase = "up"
	_leaf_angle = 90
	_passable = false
	_leaf_motion_tick = -1
	_raise_warning_tick = -1
	_leaf_cue = {}
	_ring = 0
	_signal = 0
	_sampled_surface = "cover"
	_hearing_cue = {}
	_watcher_z = WATCHER_START_CM
	_gaze = false
	_sight_cue = {}
	_recovery_z = 0
	_recovery_watcher_z = WATCHER_START_CM
	_recovery_cue = {}
	_event_serial = 0
	_events.clear()


func layout() -> Dictionary:
	var stations: Array = []
	for i in range(EXIT + 1):
		stations.append([0, i * STRIDE_CM])
	return {
		"stations_cm": stations, "gap_banks": [NEAR_BANK, FAR_BANK],
		"ear_cm": [160, 6 * STRIDE_CM], "watcher_x_cm": WATCHER_X_CM,
		"watcher_rail_z_cm": [WATCHER_START_CM, EXIT * STRIDE_CM],
		"watcher_eye_height_cm": 120, "parapet_x_cm": -60,
		"parapet_top_cm": PARAPET_TOP_CM, "leaf_hinge_cm": [0, NEAR_BANK * STRIDE_CM],
		"leaf_width_cm": 90, "decision_ticks": DECISION_TICKS, "actions": ACTIONS.duplicate(),
		"placards": {
			"lever": "FELT DRAWLEAF / Steam before movement. Cross at the flat detent.",
			"iron": "IRON TREAD / Even a tall brace makes the spring sing. Low feet let it settle.",
			"parapet": "WATCH RAIL / Meet its eye to stop it. Leave its reach to unwind the ratchet.",
			"leaf": "FELT TREAD / Holds a tall stride without ringing. Stay on it and the pawl holds.",
			"porch": "COVER / Return behind the stone lip to break the chase.",
		},
	}


func snapshot() -> Dictionary:
	var cues: Array[Dictionary] = []
	for cue: Dictionary in [_leaf_cue, _hearing_cue, _sight_cue, _recovery_cue]:
		if not cue.is_empty():
			cues.append(cue.duplicate())
	var zone := _zone()
	var hearing_mode := "idle" if _ring == 0 else "listening"
	if not _hearing_cue.is_empty():
		hearing_mode = "warning"
	var sight_mode := "idle"
	if zone == "lane":
		if _gaze:
			sight_mode = "primed" if _mature(_sight_cue) else "frozen"
		else:
			sight_mode = "tracking" if _sight_cue.is_empty() else "winding"
	return {
		"tick": _tick, "tick_hz": TICK_HZ, "attempt": _attempt, "outcome": _outcome,
		"next_decision_tick": _tick if _can_decide() else _tick + DECISION_TICKS - _tick % DECISION_TICKS,
		"player": {
			"position_cm": [0, _z], "station": _station, "target_station": _target,
			"zone": zone, "posture": "low" if _low else "tall",
			"eye_height_cm": LOW_EYE_CM if _low else TALL_EYE_CM,
			"moving": _stride_tick >= 0 or zone == "service", "footing": _surface(), "on_leaf": _on_leaf(),
		},
		"leaf": {"phase": _leaf_phase, "angle_deg": _leaf_angle, "passable": _passable,
			"hold": _leaf_phase == "held"},
		"hearing": {"ring": _ring, "trip_ring": RING_TRIP, "cap_ring": RING_CAP,
			"signal_per_tick": _signal, "surface": _sampled_surface, "mode": hearing_mode},
		"sight": {"position_cm": [WATCHER_X_CM, _watcher_z], "separation_cm": _z - _watcher_z,
			"reach_cm": REACH_CM, "gaze": _gaze, "mode": sight_mode},
		"cues": cues, "events": _events.duplicate(true),
	}


func submit(action: String) -> Dictionary:
	if not _can_decide():
		return _result(false, "decision_closed")
	_decision = _tick
	if action not in ACTIONS:
		return _result(false, "unknown_action")
	if action == "wait":
		return _result(true)
	if _outcome != "active":
		return _result(false, _outcome)
	if action == "lower":
		if _zone() != "porch":
			return _result(false, "lever_out_of_reach")
		if _leaf_phase != "up":
			return _result(false, "drive_engaged")
		_leaf_phase = "lower_warning"
		_leaf_motion_tick = _tick + DRIVE_WARNING_TICKS
		_leaf_cue = _cue("leaf_lower", _leaf_motion_tick + LEAF_TRAVEL_TICKS)
		return _result(true)
	var next := _station + (-1 if action.begins_with("back_") else 1)
	if next < 0 or next > EXIT:
		return _result(false, "end_of_lane")
	if _leaf_edge(_station, next) and not _passable:
		return _result(false, "gap_open")
	_target = next
	_low = action.ends_with("creep")
	_stride_tick = _tick
	var surface := "felt" if _leaf_edge(_station, next) else "iron"
	_emit("stride", "player", {}, {"from": _station, "to": next,
		"posture": "low" if _low else "tall", "surface": surface})
	return _result(true)


func tick_once() -> void:
	_tick += 1
	_events.clear()
	# Use the interval's tread for this sample, even if it ends on a bank mark.
	var contact := _surface()
	_advance_player()
	_advance_leaf()
	if _outcome == "active" and _zone() == "lane":
		_sample_sensors(contact)


func step(action: String = "wait") -> Dictionary:
	var offset := _events.size()
	var result := submit(action)
	var tape: Array = []
	if result.reason != "decision_closed":
		tape.append_array(_events.slice(offset).duplicate(true))
		for i in range(DECISION_TICKS):
			tick_once()
			tape.append_array(_events.duplicate(true))
	result["events"] = tape
	result["snapshot"] = snapshot()
	return result


func _can_decide() -> bool:
	return _tick % DECISION_TICKS == 0 and _decision != _tick


func _result(accepted: bool, reason: String = "") -> Dictionary:
	return {"accepted": accepted, "reason": reason}


func _zone() -> String:
	if _outcome == "recovering":
		return "service"
	if _outcome == "won":
		return "exit"
	if _station == 0 and _stride_tick < 0:
		return "porch"
	return "lane"


func _leaf_edge(a: int, b: int) -> bool:
	return mini(a, b) >= NEAR_BANK and maxi(a, b) <= FAR_BANK and a != b


func _on_leaf() -> bool:
	return _outcome == "active" and (
		(_station > NEAR_BANK and _station < FAR_BANK)
		or (_stride_tick >= 0 and _leaf_edge(_station, _target)))


func _surface() -> String:
	match _zone():
		"service": return "service"
		"porch", "exit": return "cover"
	return "felt" if _on_leaf() else "iron"


@warning_ignore("integer_division")
func _advance_player() -> void:
	if _outcome == "recovering":
		var left := int(_recovery_cue.due_tick) - _tick
		_z = _recovery_z * left / RECOVERY_TICKS
		_watcher_z = WATCHER_START_CM + (_recovery_watcher_z - WATCHER_START_CM) * left / RECOVERY_TICKS
		if left == 0:
			_station = 0
			_target = 0
			_low = false
			_outcome = "active"
			_attempt += 1
			_sampled_surface = "cover"
			_emit("recovered", "recovery", _recovery_cue)
			_recovery_cue = {}
		return
	if _stride_tick < 0:
		return
	var elapsed := _tick - _stride_tick
	_z = _station * STRIDE_CM + (_target - _station) * (STRIDE_CM / DECISION_TICKS) * elapsed
	if elapsed < DECISION_TICKS:
		return
	_station = _target
	_stride_tick = -1
	if _station == 0 or _station == EXIT:
		_clear_sensors()
		_watcher_z = WATCHER_START_CM
		if _station == EXIT:
			_outcome = "won"
			_emit("won", "player")


@warning_ignore("integer_division")
func _advance_leaf() -> void:
	match _leaf_phase:
		"lower_warning":
			if _tick == _leaf_motion_tick:
				_leaf_phase = "lowering"
				_emit("leaf_motion", "leaf_lower", {}, {"direction": "down"})
		"lowering":
			_leaf_angle = 90 * (int(_leaf_cue.due_tick) - _tick) / LEAF_TRAVEL_TICKS
			if _mature(_leaf_cue):
				_passable = true
				_leaf_phase = "down"
				_raise_warning_tick = _tick + DWELL_TICKS
				_emit("leaf_passable", "leaf_lower", _leaf_cue)
				_leaf_cue = {}
		"down":
			if _tick == _raise_warning_tick:
				_leaf_phase = "raise_warning"
				_leaf_cue = _cue("leaf_raise", _tick + DRIVE_WARNING_TICKS)
		"raise_warning", "held":
			if not _mature(_leaf_cue):
				return
			if _on_leaf():
				if _leaf_phase != "held":
					_leaf_phase = "held"
					_emit("leaf_hold", "leaf_raise")
				return
			_passable = false
			_leaf_motion_tick = _tick
			_leaf_phase = "raising"
			_emit("leaf_blocked", "leaf_raise", _leaf_cue)
			_emit("leaf_motion", "leaf_raise", {}, {"direction": "up"})
			_leaf_cue = {}
		"raising":
			_leaf_angle = 90 * (_tick - _leaf_motion_tick) / LEAF_TRAVEL_TICKS
			if _tick == _leaf_motion_tick + LEAF_TRAVEL_TICKS:
				_leaf_phase = "up"
				_emit("leaf_up", "leaf_raise")


func _sample_sensors(contact: String) -> void:
	_sampled_surface = contact
	# The rear rail's spring reads load, not key presses; a tall stationary brace still rings iron.
	if contact == "felt":
		_signal = -4 if _low else -3
	else:
		_signal = -2 if _low else 4
	_ring = clampi(_ring + _signal, 0, RING_CAP)
	if _ring >= RING_TRIP:
		if _hearing_cue.is_empty():
			_hearing_cue = _cue("hearing", _tick + DANGER_TICKS)
	elif not _hearing_cue.is_empty():
		_cancel(_hearing_cue)
		_hearing_cue = {}

	# The parapet covers the low eye. Watching halts actual position, not just the strike timer.
	if _gaze != not _low:
		_gaze = not _low
		_emit("gaze_lock" if _gaze else "gaze_lost", "sight")
	if not _gaze:
		_watcher_z += clampi(_z - _watcher_z, -WATCHER_STEP_CM, WATCHER_STEP_CM)
	if absi(_z - _watcher_z) > REACH_CM:
		if not _sight_cue.is_empty():
			_cancel(_sight_cue)
			_sight_cue = {}
	elif not _gaze and _sight_cue.is_empty():
		_sight_cue = _cue("sight", _tick + DANGER_TICKS)

	# Commit only after updating both sensors. Hearing is the stable primary tie-break.
	var hit_ear := _mature(_hearing_cue)
	var hit_eye := not _gaze and _mature(_sight_cue)
	if hit_ear or hit_eye:
		var primary := _hearing_cue if hit_ear else _sight_cue
		var also := ["sight"] if hit_ear and hit_eye else []
		_emit("caught", primary.kind, primary, {"also": also})
		if hit_ear:
			_hearing_cue = {}
		if hit_eye:
			_sight_cue = {}
		_start_recovery()


func _start_recovery() -> void:
	_outcome = "recovering"
	_stride_tick = -1
	_target = _station
	_recovery_z = _z
	_recovery_watcher_z = _watcher_z
	_clear_sensors("service")
	_recovery_cue = _cue("recovery", _tick + RECOVERY_TICKS)


func _clear_sensors(surface: String = "cover") -> void:
	_cancel(_hearing_cue)
	_cancel(_sight_cue)
	_hearing_cue = {}
	_sight_cue = {}
	_ring = 0
	_signal = 0
	_sampled_surface = surface
	if _gaze:
		_gaze = false
		_emit("gaze_lost", "sight")


func _mature(cue: Dictionary) -> bool:
	return not cue.is_empty() and _tick >= int(cue.due_tick)


func _cue(kind: String, due: int) -> Dictionary:
	var cue := {"id": _event_serial + 1, "kind": kind, "start_tick": _tick, "due_tick": due}
	_emit("cue_start", kind, cue)
	return cue


func _cancel(cue: Dictionary) -> void:
	if not cue.is_empty():
		_emit("cue_cancel", cue.kind, cue)


func _emit(kind: String, source: String, cue: Dictionary = {}, detail: Dictionary = {}) -> void:
	_event_serial += 1
	_events.append({"id": _event_serial, "tick": _tick, "kind": kind, "source": source,
		"cue_id": cue.get("id", -1), "start_tick": cue.get("start_tick", -1),
		"due_tick": cue.get("due_tick", -1),
		"lead_ticks": -1 if cue.is_empty() else _tick - int(cue.start_tick), "detail": detail})

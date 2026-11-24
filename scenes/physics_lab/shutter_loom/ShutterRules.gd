extends RefCounted
## A04: the same counterweight slab sets the walking aperture and cuts the window rays.

const TICK_HZ := 60
const DECISION_TICKS := 20
const MIN_CUE_LEAD := 40
const STROKE_TICKS := 80
const STEAM_TICKS := 60
const NOMINAL_CYCLE := 720
const RETURN_AT := NOMINAL_CYCLE - STROKE_TICKS
const LINEUP_TICKS := 60
const CROSS_TICKS := 100
const LANES := ["west", "east"]
const ACTIONS := ["wait", "throw_west", "throw_east", "approach_west", "approach_east", "back", "cross", "exit"]

const BERTH_X := 220
const WALL_HALF_X := 150
const WALL_HALF_Z := 24
const MOUTH_X := 105
const MOUTH_HALF_X := 35
const BODY_RADIUS := 22
const RAY_X := 205
const WINDOW_Z := -280
const APPROACH_Z := -120
const RECEIVER_Z := 200
const BEAM_END_Z := 280
const PORCH_Z := -240
const EXIT_Z := 345

var _tick := 0
var _decision_tick := -1
var _genuine := "west"
var _zone := "porch"
var _player_lane := ""
var _outcome := "active"
var _throw_tick := -1
var _rail_lane := ""
var _rail_phase := "home"
var _wall_x := 0
var _motion_tick := -1
var _next_cue := 0
var _rail_cue: Dictionary = {}
var _walk_cue: Dictionary = {}
var _ink_cue: Dictionary = {}
var _exit_cue: Dictionary = {}
var _events: Array[Dictionary] = []


func _init(seed: int = 0) -> void:
	reset(seed)


func reset(seed: int = 0) -> void:
	_tick = 0
	_decision_tick = -1
	_genuine = LANES[posmod(seed, 2)]
	_zone = "porch"
	_player_lane = ""
	_outcome = "active"
	_throw_tick = -1
	_rail_lane = ""
	_rail_phase = "home"
	_wall_x = 0
	_motion_tick = -1
	_next_cue = 0
	_rail_cue = {}
	_walk_cue = {}
	_ink_cue = {}
	_exit_cue = {}
	_events.clear()


func layout() -> Dictionary:
	var lanes: Dictionary = {}
	for lane: String in LANES:
		var side := _side(lane)
		lanes[lane] = {
			"approach_cm": [side * MOUTH_X, APPROACH_Z],
			"mouth_cm": [side * MOUTH_X, 0],
			"window_cm": [side * _ray_x_at(WINDOW_Z), WINDOW_Z],
			"rail_ray_cm": [side * RAY_X, 0],
			"beam_end_cm": [side * _ray_x_at(BEAM_END_Z), BEAM_END_Z],
			"caster_cm": [side * _ray_x_at(120), 120],
			"receiver_cm": [side * MOUTH_X, RECEIVER_Z],
			"shadow_polygon_cm": [
				[side * 138, 124], [side * 152, 124],
				[side * 104, 224], [side * 83, 224],
			],
		}
	return {
		"bounds_cm": [-390, -320, 390, 390],
		"porch_cm": [0, PORCH_Z], "exit_cm": [0, EXIT_Z],
		"rail_z_cm": 0, "rail_detents_x_cm": [-BERTH_X, 0, BERTH_X],
		"mouth_half_width_cm": MOUTH_HALF_X, "partition_z_cm": -65,
		"partition_x_spans_cm": [[-390, -MOUTH_X - MOUTH_HALF_X],
			[-MOUTH_X + MOUTH_HALF_X, MOUTH_X - MOUTH_HALF_X], [MOUTH_X + MOUTH_HALF_X, 390]],
		"wall_half_extents_cm": [WALL_HALF_X, WALL_HALF_Z],
		"body_radius_cm": BODY_RADIUS, "lanes": lanes,
	}


func snapshot() -> Dictionary:
	var lanes: Dictionary = {}
	for lane: String in LANES:
		var cut_z := _beam_cut_z(lane, _wall_x)
		var beam := cut_z == BEAM_END_Z
		lanes[lane] = {
			"beam_reaches_receiver": beam,
			"beam_tip_cm": [_side(lane) * _ray_x_at(cut_z), cut_z],
			"shadow_visible": beam or lane != _genuine,
			"mouth_clear": _mouth_clear(lane, _wall_x),
			"crossing_available": _crossing_available(lane),
		}
	var cues: Array[Dictionary] = []
	for cue: Dictionary in [_rail_cue, _walk_cue, _ink_cue, _exit_cue]:
		if not cue.is_empty():
			cues.append(cue.duplicate(true))
	return {
		"tick": _tick, "tick_hz": TICK_HZ, "outcome": _outcome,
		"next_decision_tick": _tick if _can_decide() else _tick + DECISION_TICKS - posmod(_tick, DECISION_TICKS),
		"player": {"zone": _zone, "lane": _player_lane, "position_cm": _player_position()},
		"rail": {"phase": _rail_phase, "wall_x_cm": _wall_x, "target_lane": _rail_lane},
		"lanes": lanes, "cues": cues, "events": _events.duplicate(true),
	}


## Submit occupies a decision slot, including a rejected attempt. A tick never reads wall time.
func submit(action: String) -> Dictionary:
	if not _can_decide():
		return _result(false, "decision_closed")
	_decision_tick = _tick
	if action not in ACTIONS:
		return _result(false, "unknown_action")
	if action == "wait":
		return _result(true)
	if _outcome != "active":
		return _result(false, "terminal")
	if not _exit_cue.is_empty() or _zone == "crossing":
		return _result(false, "in_motion")
	if not _walk_cue.is_empty() and action != "back":
		return _result(false, "lining_up")
	match action:
		"throw_west", "throw_east":
			if _zone not in ["porch", "approach"]:
				return _result(false, "lever_out_of_reach")
			if _rail_phase != "home":
				return _result(false, "counterweight_engaged")
			_rail_lane = action.trim_prefix("throw_")
			_throw_tick = _tick
			_rail_phase = "outbound_warning"
			_rail_cue = _cue("rail_steam_out", _rail_lane, _tick + STEAM_TICKS)
		"approach_west", "approach_east":
			if _zone not in ["porch", "approach"]:
				return _result(false, "approach_out_of_reach")
			_zone = "approach"
			_player_lane = action.trim_prefix("approach_")
		"back":
			if _zone != "approach":
				return _result(false, "no_approach")
			if not _walk_cue.is_empty():
				_note("walk_cancel", _player_lane, _walk_cue)
			_walk_cue = {}
			_ink_cue = {}
			_zone = "porch"
			_player_lane = ""
		"cross":
			if _zone != "approach":
				return _result(false, "choose_an_approach")
			if not _crossing_available(_player_lane):
				return _result(false, "mouth_unavailable")
			_walk_cue = _cue("threshold_scuff", _player_lane, _tick + LINEUP_TICKS)
		"exit":
			if _zone != "gallery":
				return _result(false, "exit_out_of_reach")
			_exit_cue = _cue("exit_lintel", _player_lane, _tick + MIN_CUE_LEAD)
	return _result(true)


func tick_once() -> void:
	_tick += 1
	_events.clear()
	_update_player()
	_update_rail()


## Headless/batch helper. A syntactically valid decision boundary always consumes 20 ticks.
func step(action: String = "wait") -> Dictionary:
	if not _can_decide():
		return {"accepted": false, "reason": "decision_closed", "events": [], "snapshot": snapshot()}
	var first_new_event := _events.size()
	var result := submit(action)
	var trace: Array = _events.slice(first_new_event).duplicate(true)
	for i in range(DECISION_TICKS):
		tick_once()
		trace.append_array(_events.duplicate(true))
	result["events"] = trace
	result["snapshot"] = snapshot()
	return result


func _update_player() -> void:
	if not _walk_cue.is_empty():
		var start: int = _walk_cue["start_tick"]
		if _tick == start + DECISION_TICKS and _player_lane != _genuine:
			_ink_cue = _cue("ink_ridge", _player_lane, start + CROSS_TICKS)
		if _tick == start + LINEUP_TICKS:
			_zone = "crossing"
			_commit("walk_begin", _player_lane, _walk_cue)
		if _tick == start + CROSS_TICKS:
			if _ink_cue.is_empty():
				_zone = "gallery"
				_commit("walk_arrive", _player_lane, _walk_cue)
			else:
				_zone = "caught"
				_outcome = "caught"
				_commit("ink_snap", _player_lane, _ink_cue)
			_walk_cue = {}
			_ink_cue = {}
	if not _exit_cue.is_empty() and _tick == _exit_cue["due_tick"]:
		_zone = "outside"
		_outcome = "won"
		_commit("exit_arrive", _player_lane, _exit_cue)
		_exit_cue = {}
		_player_lane = ""


func _update_rail() -> void:
	if _rail_phase == "home":
		return
	var elapsed := _tick - _throw_tick
	match _rail_phase:
		"outbound_warning":
			if elapsed == STEAM_TICKS:
				_rail_phase = "outbound"
				_motion_tick = _tick
				_commit("rail_depart_out", _rail_lane, _rail_cue)
		"outbound":
			var progress := _tick - _motion_tick
			_move_wall(_side(_rail_lane) * _lerp_i(0, BERTH_X, progress, STROKE_TICKS))
			if progress == STROKE_TICKS:
				_rail_phase = "berthed"
				_commit("rail_dock_berth", _rail_lane, _rail_cue)
				_rail_cue = {}
		"berthed":
			if elapsed == RETURN_AT - STEAM_TICKS:
				_rail_phase = "return_warning"
				_rail_cue = _cue("rail_steam_home", _rail_lane, _throw_tick + RETURN_AT)
		"return_warning", "held":
			if elapsed >= RETURN_AT:
				# A reservation begins in the safe approach and covers the whole swept crossing.
				if not _walk_cue.is_empty():
					if _rail_phase != "held":
						_rail_phase = "held"
						_note("rail_interlock", _rail_lane, _rail_cue)
				else:
					_rail_phase = "returning"
					_motion_tick = _tick
					_commit("rail_depart_home", _rail_lane, _rail_cue)
		"returning":
			var progress := _tick - _motion_tick
			var distance := BERTH_X - _lerp_i(0, BERTH_X, progress, STROKE_TICKS)
			_move_wall(_side(_rail_lane) * distance)
			if progress == STROKE_TICKS:
				_rail_phase = "home"
				_commit("rail_dock_home", _rail_lane, _rail_cue)
				_rail_cue = {}
				_rail_lane = ""


func _move_wall(x: int) -> void:
	for lane: String in LANES:
		var clear := _mouth_clear(lane, x)
		var beam := _beam_cut_z(lane, x) == BEAM_END_Z
		if clear != _mouth_clear(lane, _wall_x):
			_commit("mouth_open" if clear else "mouth_close", lane, _rail_cue)
		if beam != (_beam_cut_z(lane, _wall_x) == BEAM_END_Z):
			_commit("beam_restore" if beam else "beam_cut", lane, _rail_cue)
	_wall_x = x


func _player_position() -> Array:
	var side := _side(_player_lane)
	match _zone:
		"approach":
			return [side * MOUTH_X, APPROACH_Z]
		"crossing":
			var walked: int = _tick - _walk_cue["due_tick"]
			return [side * MOUTH_X, _lerp_i(APPROACH_Z, RECEIVER_Z, walked, CROSS_TICKS - LINEUP_TICKS)]
		"gallery", "caught":
			if not _exit_cue.is_empty():
				var walked: int = _tick - _exit_cue["start_tick"]
				return [_lerp_i(side * MOUTH_X, 0, walked, MIN_CUE_LEAD),
					_lerp_i(RECEIVER_Z, EXIT_Z, walked, MIN_CUE_LEAD)]
			return [side * MOUTH_X, RECEIVER_Z]
		"outside":
			return [0, EXIT_Z]
	return [0, PORCH_Z]


func _can_decide() -> bool:
	return posmod(_tick, DECISION_TICKS) == 0 and _decision_tick != _tick


func _crossing_available(lane: String) -> bool:
	return _rail_phase in ["berthed", "return_warning"] and _mouth_clear(lane, _wall_x)


func _mouth_clear(lane: String, x: int) -> bool:
	return absi(_side(lane) * MOUTH_X - x) > WALL_HALF_X + BODY_RADIUS


func _beam_cut_z(lane: String, x: int) -> int:
	# Mirror into positive X. The ray x = RAY_X - z/2 intersects the wall's X
	# extent over an integer Z interval, which is then clipped to its thickness.
	var local_x := _side(lane) * x
	var first_z := maxi(-WALL_HALF_Z, 2 * (RAY_X - local_x - WALL_HALF_X))
	var last_z := mini(WALL_HALF_Z, 2 * (RAY_X - local_x + WALL_HALF_X))
	return first_z if first_z <= last_z else BEAM_END_Z


func _side(lane: String) -> int:
	return -1 if lane == "west" else 1


@warning_ignore("integer_division")
func _ray_x_at(z: int) -> int:
	return RAY_X - z / 2


@warning_ignore("integer_division")
func _lerp_i(a: int, b: int, elapsed: int, duration: int) -> int:
	return a + (b - a) * elapsed / duration


func _cue(kind: String, lane: String, due: int) -> Dictionary:
	_next_cue += 1
	var cue := {"id": _next_cue, "kind": kind, "lane": lane, "start_tick": _tick,
		"due_tick": due, "position_cm": _cue_position(kind, lane)}
	_events.append({"type": "cue", "tick": _tick, "kind": kind, "lane": lane,
		"cue_id": _next_cue, "due_tick": due, "position_cm": cue.position_cm.duplicate()})
	return cue


func _cue_position(kind: String, lane: String) -> Array:
	var side := _side(lane)
	match kind:
		"rail_steam_out":
			return [side * (BERTH_X + WALL_HALF_X - 10), -40]
		"rail_steam_home":
			return [-side * (WALL_HALF_X - 10), -40]
		"threshold_scuff":
			return [side * MOUTH_X, APPROACH_Z]
		"ink_ridge":
			return [side * MOUTH_X, RECEIVER_Z]
	return [0, EXIT_Z]


func _note(kind: String, lane: String, cue: Dictionary) -> void:
	_events.append({"type": "note", "tick": _tick, "kind": kind, "lane": lane, "cue_id": cue["id"]})


func _commit(kind: String, lane: String, cue: Dictionary) -> void:
	var lead: int = _tick - cue["start_tick"]
	assert(lead >= MIN_CUE_LEAD)
	_events.append({"type": "commit", "tick": _tick, "kind": kind, "lane": lane, "cue_id": cue["id"], "lead_ticks": lead})


func _result(accepted: bool, reason: String = "") -> Dictionary:
	return {"accepted": accepted, "reason": reason}

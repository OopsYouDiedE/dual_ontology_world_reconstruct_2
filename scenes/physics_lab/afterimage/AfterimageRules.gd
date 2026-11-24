extends RefCounted
## Afterimage Carriage: deterministic model; no Node, input device, or render dependency.

const HZ := 60
const DECISION_TICKS := 20
const WARNING_TICKS := 40
const REEL_BEATS := 8
const WEST_HOLD_TICKS := 100

const HUB := "hub"
const LAMP := "lamp"
const BELL := "bell"
const CARRIAGE := "carriage"
const EXIT := "exit"
const CLEAR := "clear"
const SILVER := "silver"
const NEUTRAL := "neutral"
const WEST := "west"
const EAST := "east"
const ACTIONS := ["wait", "move", "pulse", "prism", "rewind", "escape"]
const SITES := {
	HUB: {"label": "Hub", "xz": [-2, 0], "prism": true, "grounded": true},
	LAMP: {"label": "Wired Lamp", "xz": [-3, -2], "channel": "light", "grounded": true},
	BELL: {"label": "Wired Bell", "xz": [-3, 2], "channel": "sound", "grounded": true},
	CARRIAGE: {"label": "Carriage", "xz": [0, 0], "channel": "sound", "prism": true},
	EXIT: {"label": "Exit Landing", "xz": [2, 0]},
}
const SHORE := [[HUB, LAMP], [HUB, BELL]]
const GANGWAYS := {WEST: [HUB, CARRIAGE], EAST: [CARRIAGE, EXIT]}
const RECEIVERS := {CLEAR: WEST, SILVER: EAST}

var _tick := 0
var _player := HUB
var _form := CLEAR
var _alignment := NEUTRAL
var _won := false
var _spring_due := -1
var _swing: Dictionary = {}
var _throw: Dictionary = {}
var _rewind: Dictionary = {}
var _queued: Dictionary = {}
var _last: Dictionary = {}
var _signals: Array[Dictionary] = []
var _pair: Dictionary = {}
# Reel frames contain a pre-action optical snapshot and at most one grounded emission.
var _frames: Array[Dictionary] = []
var _echo: Array[String] = []
var _cursor := 0


func reset() -> void:
	_tick = 0
	_player = HUB
	_form = CLEAR
	_alignment = NEUTRAL
	_won = false
	_spring_due = -1
	_swing.clear()
	_throw.clear()
	_rewind.clear()
	_queued.clear()
	_last.clear()
	_signals.clear()
	_pair.clear()
	_frames.clear()
	_echo.clear()
	_cursor = 0


func layout() -> Dictionary:
	return {
		"hz": HZ, "decision_ticks": DECISION_TICKS, "warning_ticks": WARNING_TICKS,
		"reel_beats": REEL_BEATS, "west_hold_ticks": WEST_HOLD_TICKS,
		"sites": SITES.duplicate(true), "shore": SHORE.duplicate(true),
		"gangways": GANGWAYS.duplicate(true), "receivers": RECEIVERS.duplicate(),
		"escape": {"from": CARRIAGE, "to": HUB, "label": "Service Ladder (down only)"},
	}


func queue_action(verb: String, target: String = "") -> bool:
	if _won or not _rewind.is_empty() or not _queued.is_empty() or not ACTIONS.has(verb):
		return false
	if (verb == "move" and not SITES.has(target)) or (verb != "move" and not target.is_empty()):
		return false
	_queued = {"verb": verb, "target": target}
	return true


func step_tick() -> void:
	if _won:
		return
	_tick += 1
	var winding := not _rewind.is_empty()
	# A committed powered swing takes precedence over a spring return due on the same tick.
	if _is_due(_swing):
		_alignment = _swing.to
		_spring_due = _tick + WEST_HOLD_TICKS if _alignment == WEST else -1
		_swing.clear()
	if _spring_due == _tick:
		_alignment = NEUTRAL
		_spring_due = -1
		if not _swing.is_empty():
			_swing["from"] = NEUTRAL
	if _is_due(_throw):
		_form = _throw.to
		_throw.clear()
	if _is_due(_rewind):
		_finish_rewind()
	if _tick % DECISION_TICKS != 0:
		return
	_signals.clear()
	_pair.clear()
	if winding:
		return # The splice boundary itself never plays or records a beat.
	_decide()


func observe() -> Dictionary:
	var tape: Array[String] = []
	var anchor := ""
	if _echo.is_empty():
		for frame in _frames:
			tape.append(frame.source)
		if not _frames.is_empty():
			anchor = _frames.front().player
	else:
		tape.assign(_echo)
	var receiver: String = RECEIVERS[_form]
	return {
		"tick": _tick, "next_decision_tick": _tick - _tick % DECISION_TICKS + DECISION_TICKS,
		"player": _player, "form": _form, "alignment": _alignment, "won": _won,
		"walkable": _walkable().duplicate(true), "queued": _queued.duplicate(),
		"last_action": _last.duplicate(), "optics": {
			"receiver": receiver, "revealed_gangway": GANGWAYS[receiver].duplicate(),
		},
		"signals": _signals.duplicate(true), "pair": _pair.duplicate(), "cues": _cues(),
		"spring_due_tick": _spring_due, "reel": {
			"capacity": REEL_BEATS, "recorded": _frames.size(), "tape": tape, "anchor": anchor,
			"cursor": _cursor, "rewinding": not _rewind.is_empty(), "replaying": not _echo.is_empty(),
			"can_rewind": _rewind_reason().is_empty(),
		},
	}


func _decide() -> void:
	if not _echo.is_empty() and _cursor == _echo.size():
		_echo.clear()
		_cursor = 0
	var playing := not _echo.is_empty()
	if playing:
		var source := _echo[_cursor]
		_cursor += 1
		if not source.is_empty():
			_emit(source, "echo")
	var frame := {"player": _player, "form": _form, "source": ""}
	var action := _queued if not _queued.is_empty() else {"verb": "wait", "target": ""}
	_queued = {}
	var reason := _apply(action)
	_last = {"tick": _tick, "verb": action.verb, "target": action.target, "ok": reason.is_empty(),
		"reason": reason, "from": frame.player, "to": _player}
	if not playing and _rewind.is_empty():
		if action.verb == "pulse" and reason.is_empty() and SITES[_player].get("grounded", false):
			frame.source = _player
		_frames.append(frame)
		if _frames.size() > REEL_BEATS:
			_frames.pop_front()
	_pair_signals()


func _apply(action: Dictionary) -> String:
	match action.verb:
		"move":
			for edge in _walkable():
				if edge.has(_player) and edge.has(action.target) and _player != action.target:
					_player = action.target
					_won = _player == EXIT
					return ""
			return "no_gangway"
		"escape":
			if _player != CARRIAGE:
				return "no_ladder"
			_player = HUB
		"pulse":
			if not SITES[_player].has("channel"):
				return "no_emitter"
			_emit(_player, "live")
		"prism":
			if not SITES[_player].get("prism", false):
				return "no_prism_control"
			if not _throw.is_empty():
				return "prism_pending"
			_throw = _cue("prism", _form, SILVER if _form == CLEAR else CLEAR)
		"rewind":
			var reason := _rewind_reason()
			if not reason.is_empty():
				return reason
			var frame: Dictionary = _frames.front()
			_rewind = _cue("rewind", _player, frame.player)
			_rewind["restore_form"] = frame.form
			_rewind["restore_alignment"] = NEUTRAL if _spring_due >= 0 and _spring_due <= _rewind.due_tick else _alignment
	return ""


func _emit(source: String, origin: String) -> void:
	var channel: String = SITES[source].channel
	_signals.append({"channel": channel, "source": source, "origin": origin,
		"start_tick": _tick, "end_tick": _tick + DECISION_TICKS})


func _pair_signals() -> void:
	var light := false
	var sound := false
	for signal_state in _signals:
		light = light or signal_state.channel == "light"
		sound = sound or signal_state.channel == "sound"
	if not (light and sound):
		return
	var receiver: String = RECEIVERS[_form]
	var reason := ""
	if not _swing.is_empty():
		reason = "swing_pending"
	elif receiver == _alignment:
		reason = "already_aligned" # A pair cannot refresh the West spring.
	else:
		_swing = _cue("swing", _alignment, receiver)
	_pair = {"tick": _tick, "receiver": receiver, "accepted": reason.is_empty(), "reason": reason}


func _rewind_reason() -> String:
	if _won:
		return "room_complete"
	if not _rewind.is_empty() or not _echo.is_empty():
		return "head_busy"
	if not _swing.is_empty() or not _throw.is_empty():
		return "actuator_pending"
	if _frames.size() < REEL_BEATS:
		return "reel_short"
	if not SITES[_frames.front().player].get("grounded", false):
		return "anchor_ungrounded"
	return ""


func _finish_rewind() -> void:
	_player = _rewind.to
	_form = _rewind.restore_form
	_rewind.clear()
	for frame in _frames:
		_echo.append(frame.source)
	_frames.clear()
	_cursor = 0


func _walkable() -> Array:
	var paths := SHORE.duplicate()
	if _alignment == RECEIVERS[_form]:
		paths.append(GANGWAYS[_alignment])
	return paths


func _cue(kind: String, from: String, to: String) -> Dictionary:
	return {"kind": kind, "from": from, "to": to, "start_tick": _tick, "due_tick": _tick + WARNING_TICKS}


func _is_due(cue: Dictionary) -> bool:
	return not cue.is_empty() and cue.due_tick == _tick


func _cues() -> Array[Dictionary]:
	var cues: Array[Dictionary] = []
	for cue in [_throw, _swing, _rewind]:
		if not cue.is_empty():
			cues.append(cue.duplicate())
	if _spring_due >= 0 and _spring_due - _tick <= WARNING_TICKS:
		cues.append({"kind": "spring", "from": WEST, "to": NEUTRAL,
			"start_tick": _spring_due - WARNING_TICKS, "due_tick": _spring_due})
	return cues

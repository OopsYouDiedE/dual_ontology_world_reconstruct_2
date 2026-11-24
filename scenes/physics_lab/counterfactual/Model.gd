extends RefCounted
## A08: integer mechanism and 60 Hz input referee; no scene or engine time dependency.

const HZ := 60
const WALK_TICKS := 12
const NOTICE_TICKS := 48
const PROOF_TICKS := 240
const CROSS_TICKS := 48
const DRUM_TICKS := 120
const MAX_PRELOAD := 64
const MAX_SET := 40
const MAX_BALLAST := 36
const MAX_BRAKE := 18
const MAX_HEAT := 100
const FORM_HEAT := 50
const MIN_TENSION := 73
const SHOE_LIMIT := 7

const OBJECTS := {
	"start": "Splice Bench", "jack": "Cable Jack", "kiln": "Forming Kiln",
	"yoke": "Proof Yoke", "brake": "Dashpot Brake", "weight": "Counterweight",
	"span": "Test Span", "exit": "Far Landing",
}
const LINKS := {
	"start": ["jack", "kiln"], "jack": ["start", "yoke"], "kiln": ["start", "yoke"],
	"yoke": ["jack", "kiln", "brake", "weight"], "brake": ["yoke", "span"],
	"weight": ["yoke", "span"], "span": ["exit"], "exit": [],
}
const APPROACHES := ["brake", "weight"]
const CUE_TEXT := {
	"cut_pin": "Service punch armed. The proof pin will fall and open the kiln shutter.",
	"rewind_home": "Splice armed: restore Home. Cable teeth and copper bend stay here.",
	"rewind_bench": "Splice armed: restore Bench. Cable teeth and copper bend stay here.",
	"proof_start": "Proof draw armed. Clear the shoe and wait for a green rider window.",
	"proof_end": "Proof draw will end. The entry latch closes for the final return.",
	"rider_release": "Rider latch set. The trolley will release into the marked green window.",
}

var _tick: int
var _local_tick: int
var _place: String
var _preload: int
var _bend: int
var _heat: int
var _ballast: int
var _brake: int
var _pin: bool
var _won: bool
var _travel: Dictionary
var _pending: Dictionary
var _marks: Dictionary
var _proof: Dictionary
var _cross: Dictionary
var _event: Dictionary
var _hold: String
var _stamp_requested: bool
var _draws: Array[int]
var _entries: Dictionary
var _windows: Dictionary
var _best: Dictionary
var _queued: Dictionary

func _init() -> void:
	reset()

func reset() -> void:
	_tick = 0
	_local_tick = 0
	_place = "start"
	_preload = 0
	_bend = 0
	_heat = 0
	_ballast = 0
	_brake = 0
	_pin = true
	_won = false
	_travel = {}
	_pending = {}
	_marks = {"home": _capture()}
	_cross = {}
	_clear_proof()
	_hold = ""
	_stamp_requested = false
	_report("ready", "Form a copper seat, then prove the span under a rider.")

func step(input: Dictionary = {}) -> void:
	if _won:
		return
	_tick += 1
	_local_tick += 1
	_hold = ""
	_stamp_requested = false
	var restored := _due()
	if _won:
		return
	var press := str(input.get("press", ""))
	if press != "":
		_press(press, str(input.get("target", "")))
	if _travel.is_empty() and _cross.is_empty() and _pending.is_empty() and _proof.is_empty():
		_hold = _apply_hold(str(input.get("hold", "")))
	if not restored:
		_heat = clampi(_heat + (2 if _hold == "heat" else -1), 0, MAX_HEAT)
		if _heat >= FORM_HEAT and not _pin:
			_bend += clampi(_form_target() - _bend, -1, 1)
	if _stamp_requested:
		_marks["bench"] = _capture()

func _capture() -> Dictionary:
	return {"local_tick": _local_tick, "saved_at_tick": _tick, "saved_drum_phase": _tick % DRUM_TICKS,
		"pin_intact": _pin,
		"heat": _heat, "ballast": _ballast, "brake": _brake}

func _restore(id: String) -> void:
	var mark: Dictionary = _marks[id]
	_local_tick = mark.local_tick
	_pin = mark.pin_intact
	_heat = mark.heat
	_ballast = mark.ballast
	_brake = mark.brake
	_place = "start"
	_report("spliced", "Local work restored. Cable teeth and copper bend are still in place.", {"mark": id})

func _cue(id: String, start: int, due: int) -> Dictionary:
	return {"id": id, "start_tick": start, "due_tick": due, "text": CUE_TEXT[id]}

func _report(id: String, text: String, detail: Dictionary = {}) -> void:
	_event = {"id": id, "text": text, "tick": _tick, "detail": detail}

func _deny(text: String, detail: Dictionary = {}) -> void:
	_report("blocked", text, detail)

func _due() -> bool:
	if not _travel.is_empty() and _tick == _travel.due_tick:
		_place = _travel.to
		_travel = {}
		_report("arrived", "Arrived: %s." % OBJECTS[_place])
	if not _pending.is_empty() and _tick == _pending.due_tick:
		var id: String = _pending.id
		_pending = {}
		match id:
			"cut_pin":
				_pin = false
				_report("pin_dropped", "The proof pin fell into the catchbox. The kiln is open.")
			"rewind_home", "rewind_bench":
				_restore(id.trim_prefix("rewind_"))
				return true
	if not _queued.is_empty() and _tick == _queued.due_tick:
		_board()
	if not _cross.is_empty() and _tick == _cross.due_tick:
		_place = "exit"
		_cross = {}
		_won = true
		_clear_proof()
		_report("crossed", "Far Landing reached. The proof shoe carried the rider.")
		return false
	if not _proof.is_empty():
		if _tick == _proof.start_tick:
			_report("proof_started", "Proof draw live. Watch both rider needles.")
		elif _tick == _proof.end_tick:
			_clear_proof()
			_report("proof_ended", "Proof draw parked. The settings are free again.")
	return false

func _press(id: String, target: String) -> void:
	if id == "cancel":
		_cancel()
		return
	if not _pending.is_empty() or not _travel.is_empty() or not _cross.is_empty() or not _queued.is_empty():
		_deny("Wait for the mechanism or pull Cancel.")
		return
	match id:
		"move":
			_move(target)
		"mark":
			if _place == "start" and _proof.is_empty():
				_stamp_requested = true
				_report("marked", "Bench mark saved. Compare its witness columns with Home.")
			else:
				_deny("Make a mark at the Splice Bench while the proof draw is parked.")
		"rewind_home", "rewind_bench":
			if _place == "start" and _proof.is_empty() and _marks.has(id.trim_prefix("rewind_")):
				_pending = _cue(id, _tick, _tick + NOTICE_TICKS)
				_report("warned", _pending.text)
			else:
				_deny("Choose an existing mark at the Splice Bench with the proof draw parked.")
		"cut_pin":
			if _place == "kiln" and _pin and _proof.is_empty():
				_pending = _cue(id, _tick, _tick + NOTICE_TICKS)
				_report("warned", _pending.text)
			else:
				_deny("Use the service punch at the Kiln with the pin seated and draw parked.")
		"queue_cross":
			_queue_entry()
		"arm":
			if _place != "yoke" or not _proof.is_empty():
				_deny("Arm a parked draw at the Proof Yoke.")
			elif not _pin:
				_deny("Proof needs the seated pin. The catchbox is below the deck.")
			else:
				_arm()
		_:
			_deny("Unrecognized control.")

func _cancel() -> void:
	if not _pending.is_empty():
		_pending = {}
		_report("cancelled", "Pending operation withdrawn.")
	elif not _cross.is_empty():
		_travel = {"from": "span", "to": _cross.from, "start_tick": _tick,
			"due_tick": _tick + WALK_TICKS, "kind": "safety_return"}
		_cross = {}
		_clear_proof()
		_report("retreat", "The safety trolley is returning to the approach rail.")
	elif not _queued.is_empty():
		_queued = {}
		_report("cancelled", "Rider request withdrawn; the proof draw is still running.")
	elif not _proof.is_empty():
		_clear_proof()
		_report("cancelled", "Proof draw withdrawn; settings released.")
	else:
		_report("idle", "No pending operation. Walk back along the service paths.")

func _move(target: String) -> void:
	if not target in LINKS[_place]:
		_deny("Walk along a connected service path.")
		return
	if target == "span":
		var preview := _forecast(_place, _tick)
		if not preview.safe:
			_deny(preview.text, preview)
			return
		_board()
		return
	_travel = {"from": _place, "to": target, "start_tick": _tick,
		"due_tick": _tick + WALK_TICKS, "kind": "walk"}
	_report("walking", "Walking to %s." % OBJECTS[target])

func _queue_entry() -> void:
	var due := _next_entry(_place, _tick + NOTICE_TICKS)
	if due < 0:
		_deny("No certified rider window on this approach with time to show the release flag.")
		return
	_queued = _cue("rider_release", _tick, due)
	_report("warned", _queued.text)

func _board() -> void:
	_cross = {"from": _place, "start_tick": _tick, "due_tick": _tick + CROSS_TICKS}
	_queued = {}
	_place = "span"
	_report("boarding", "Rider on the span; safety trolley available.")

func _apply_hold(id: String) -> String:
	match _place:
		"jack":
			if id in ["haul", "pay_out"]:
				_preload = clampi(_preload + (1 if id == "haul" else -1), 0, MAX_PRELOAD)
				return id
		"kiln":
			if id == "heat" and not _pin:
				return id
		"brake":
			if id in ["tighten", "loosen"]:
				_brake = clampi(_brake + (1 if id == "tighten" else -1), 0, MAX_BRAKE)
				return id
		"weight":
			if id in ["raise", "lower"]:
				_ballast = clampi(_ballast + (1 if id == "raise" else -1), 0, MAX_BALLAST)
				return id
	return ""

@warning_ignore("integer_division")
func _form_target() -> int:
	return clampi(_preload - _ballast / 2 - 18, 0, MAX_SET)

func _clear_proof() -> void:
	_proof = {}
	_draws = []
	_entries = {}
	_windows = {}
	_best = {}
	_queued = {}

@warning_ignore("integer_division")
func _arm() -> void:
	var start := _tick + NOTICE_TICKS
	_proof = {"armed_tick": _tick, "start_tick": start, "end_tick": start + PROOF_TICKS,
		"preload": _preload, "bend": _bend, "ballast": _ballast, "brake": _brake}
	# The intact pin closes the kiln; the brake cam locks all four settings during a draw.
	# Precompute one actual shaft trajectory and both interlock envelopes from those settings.
	var piston := 0
	for age in range(PROOF_TICKS):
		var offset := age - PROOF_TICKS / 2
		var lobe := maxi(0, 44 - (offset * offset) / 180)
		var phase := (start + age) % DRUM_TICKS
		var eccentric := (60 - absi(60 - phase)) / 15 - 2
		var drive := maxi(0, lobe + eccentric) if lobe > 0 else 0
		piston += (16 * drive - piston) / (4 + _brake)
		_draws.append(piston)
	for approach in APPROACHES:
		var entries: Array[Dictionary] = []
		var ranges: Array[Dictionary] = []
		var best_score := -1000
		for age in range(PROOF_TICKS - CROSS_TICKS + 1):
			var result := _run_rider(approach, start + age)
			entries.append(result)
			var score := mini(result.tension_margin, result.shoe_margin)
			if score > best_score:
				best_score = score
				_best[approach] = result
			if result.safe:
				if not ranges.is_empty() and ranges[-1].last_tick == result.entry_tick - 1:
					ranges[-1].last_tick = result.entry_tick
				else:
					ranges.append({"first_tick": result.entry_tick, "last_tick": result.entry_tick})
		_entries[approach] = entries
		_windows[approach] = ranges
	_report("warned", CUE_TEXT.proof_start)

@warning_ignore("integer_division")
func _sample(t: int, rider: int = -1, approach: String = "") -> Dictionary:
	var age: int = t - _proof.start_tick if not _proof.is_empty() else -1
	var piston := _draws[age] if age >= 0 and age < _draws.size() else 0
	var payload := 0
	var shift := 0
	if rider >= 0:
		# Both approaches meet on the tread, with mirrored side loading.
		payload = 8 + mini(rider, CROSS_TICKS - 1 - rider) / 5
		shift = (2 * rider - (CROSS_TICKS - 1)) * _seat_leverage() / (CROSS_TICKS - 1)
		if approach == "weight":
			shift = -shift
	var force := _preload + piston / 16 - _brake
	var tension := force - _ballast / 3 - payload
	var shoe := force - 2 * _ballast - _bend + shift
	return {"tick": t, "draw_q16": piston, "tension": tension, "shoe": shoe,
		"tension_ok": tension >= MIN_TENSION, "shoe_ok": absi(shoe) <= SHOE_LIMIT,
		"rider_load": payload, "rider_shift": shift}

@warning_ignore("integer_division")
func _seat_leverage() -> int:
	# A deeper curved seat has a longer moment arm at either end of the tread.
	return 4 + _bend * _bend / 120

func sample_proof(approach: String, entry_tick: int, rider_offset: int) -> Dictionary:
	if not _proof.is_empty() and approach in APPROACHES and rider_offset >= 0 and rider_offset < CROSS_TICKS:
		if entry_tick >= _proof.start_tick and entry_tick + CROSS_TICKS <= _proof.end_tick:
			return _sample(entry_tick + rider_offset, rider_offset, approach)
	return {}

func _run_rider(approach: String, enter: int) -> Dictionary:
	var worst_tension := 1000
	var worst_shoe := 1000
	var first_failure: Dictionary = {}
	for i in range(CROSS_TICKS):
		var sample := _sample(enter + i, i, approach)
		worst_tension = mini(worst_tension, sample.tension - MIN_TENSION)
		worst_shoe = mini(worst_shoe, SHOE_LIMIT - absi(sample.shoe))
		if first_failure.is_empty() and (not sample.tension_ok or not sample.shoe_ok):
			first_failure = sample
	var safe := first_failure.is_empty()
	var reason := "Both rider needles stay in range for the whole crossing."
	if not safe:
		if not first_failure.tension_ok and not first_failure.shoe_ok:
			reason = "Rider forecast: the cable goes slack and the shoe leaves its guide."
		elif not first_failure.tension_ok:
			reason = "Rider forecast: the cable goes slack."
		else:
			reason = "Rider forecast: the shoe leaves its guide."
	return {"safe": safe, "entry_tick": enter, "failure": first_failure, "text": reason,
		"tension_margin": worst_tension, "shoe_margin": worst_shoe}

func _forecast(approach: String, tick: int) -> Dictionary:
	if not _proof.is_empty() and _entries.has(approach):
		var age: int = tick - _proof.start_tick
		var entries: Array = _entries[approach]
		if age >= 0 and age < entries.size():
			return entries[age]
	return {"safe": false, "entry_tick": tick, "failure": {},
		"text": "The entry latch needs a full rider window on a live proof draw."}

func _next_entry(approach: String, earliest: int) -> int:
	for span in _windows.get(approach, []):
		if span.last_tick >= earliest:
			return maxi(earliest, span.first_tick)
	return -1

func _view_proof() -> Dictionary:
	if _proof.is_empty():
		return {"stage": "parked", "next_entry": {}, "forecast": {}, "windows": {}, "best_trial": {}}
	var view := _proof.duplicate()
	view["stage"] = "live" if _tick >= _proof.start_tick else "arming"
	view["next_entry"] = {}
	view["forecast"] = {}
	view["windows"] = _windows.duplicate(true)
	view["best_trial"] = _best.duplicate(true)
	view["queued"] = _queued.duplicate()
	for approach in APPROACHES:
		# At observation tick t, the next possible input is t+1.
		view.next_entry[approach] = _next_entry(approach, _tick + 1)
		view.forecast[approach] = _forecast(approach, _tick + 1).duplicate(true)
	return view

func observe() -> Dictionary:
	var cues: Array[Dictionary] = []
	if not _pending.is_empty():
		cues.append(_pending.duplicate())
	if not _queued.is_empty():
		cues.append(_queued.duplicate())
	if not _proof.is_empty():
		if _tick < _proof.start_tick:
			cues.append(_cue("proof_start", _proof.armed_tick, _proof.start_tick))
		cues.append(_cue("proof_end", _proof.armed_tick, _proof.end_tick))
	var local := _capture()
	local.erase("saved_at_tick")
	local.erase("saved_drum_phase")
	var readings := _sample(_tick) if _cross.is_empty() else _sample(_tick, _tick - int(_cross.start_tick), _cross.from)
	readings["min_tension"] = MIN_TENSION
	readings["shoe_limit"] = SHOE_LIMIT
	readings["forming_heat"] = FORM_HEAT
	readings["forming_target"] = _form_target()
	readings["seat_leverage"] = _seat_leverage()
	return {"tick": _tick, "local_tick": _local_tick, "drum_phase": _tick % DRUM_TICKS,
		"place": _place, "travel": _travel.duplicate(), "objects": OBJECTS.duplicate(),
		"links": LINKS.duplicate(true), "local": local, "retained": {"preload": _preload, "bend": _bend},
		"marks": _marks.duplicate(true), "cues": cues, "proof": _view_proof(), "readings": readings,
		"crossing": _cross.duplicate(), "active_hold": _hold, "won": _won, "event": _event.duplicate(true)}

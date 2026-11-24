extends RefCounted
## Fixed-tick rule model. Coordinates are shared with the room; no render/physics queries.
const TICK_RATE := 60
const HANDOFF := 30
const PROOF := 40
const WARNING := 120
const STAMP := 24
const WALK := 12
const STATIONS := {
	"survey": Vector3(-3.95, 0, -1.55), "drawer": Vector3(-1.18, 0, -0.56),
	"proof": Vector3(-0.62, 0, 2.14), "threshold": Vector3(3.86, 0, 2.20),
}
const SOURCE := Vector3(-4.08, 1.12, -2.72)
const LOAD := Vector3(-0.72, 0.92, -0.61)
const HOOD := Vector3(0.68, 0.92, -0.61)
const PITCH := Vector3(0.77, 1.38, 1.49)
const READER := Vector3(2.74, 1.60, -1.78)
const READER_FACING := Vector3(-0.82, 0, 0.57)
const WALL := AABB(Vector3(-0.22, 0, -3.63), Vector3(0.44, 2.35, 4.00))
const BAFFLE := AABB(Vector3(1.05, 0.7, -1.24), Vector3(0.52, 1.04, 0.48))
const PLATES := ["sun", "moon"]
const ACTIONS := ["survey", "drawer", "proof", "threshold", "take_prism", "take_wax", "send", "sun", "moon",
	"show", "release", "override", "brace", "file", "reset", "plate", "optics"]
const OLD_RULE := {"edition": "III", "op": "all", "args": [{"fact": "registered_sample"}, {"op": "not", "arg": {"fact": "sealed_register"}}]}
const NEW_RULE := {"edition": "IV", "op": "all", "args": [{"fact": "registered_sample"}, {"op": "any", "args": [
	{"op": "not", "arg": {"fact": "sealed_register"}}, {"fact": "live_counterexample_witnessed"}]}]}

var trial := 0
var tick := 0
var station := "survey"
var from_station := "survey"
var walking_until := 0
var held := ""
var transit := ""
var arrives := -1
var received := ""
var dial := ""
var proof_active := false
var proof_ticks := 0
var sample_rays := 0
var manual := OLD_RULE
var debt := 0
var panic_at := -1
var panic_fired := false
var braced := false
var emergency := false
var latch_at := -1
var outcome := ""
var optics := false
var last_event := ""
var message := ""
var audit: Array[Dictionary] = []


func _init(plate: int = 0) -> void:
	trial = posmod(plate, PLATES.size())
	_note("case_open", "Read the two samples at the survey desk, then send one through the blind drawer.")
	_refresh_optics()


func mark() -> String:
	return PLATES[trial]


func _note(event: String, text: String) -> void:
	last_event = event
	message = text
	audit.append({"tick": tick, "event": event})
	if audit.size() > 30:
		audit.pop_front()


static func _eval(rule: Dictionary, facts: Dictionary) -> bool:
	if rule.has("fact"):
		return facts.get(rule.fact, false)
	match rule.op:
		"not": return not _eval(rule.arg, facts)
		"all":
			for child: Dictionary in rule.args:
				if not _eval(child, facts): return false
			return true
		"any":
			for child: Dictionary in rule.args:
				if _eval(child, facts): return true
	return false


func _registered() -> bool:
	return received != "" and dial == mark() and arrives == -1


func permitted() -> bool:
	return _eval(manual, {"registered_sample": _registered(), "sealed_register": true,
		"live_counterexample_witnessed": manual.edition == "IV" and received == "prism"})


func _cut_proof() -> void:
	proof_active = false
	if manual.edition == "III": proof_ticks = 0


func _arrived() -> bool:
	return tick >= walking_until


func _move(destination: String) -> void:
	if station == destination: return
	if not _arrived():
		_note("walking", "Finish moving to the selected station first.")
		return
	var interrupted: bool = proof_active and proof_ticks > 0 and manual.edition == "III"
	_cut_proof()
	from_station = station
	station = destination
	walking_until = tick + WALK
	if interrupted:
		_note("proof_interrupted", "Sightline broken. The proof must run for 40 uninterrupted ticks.")


func runner_position() -> Vector3:
	if _arrived(): return STATIONS[station]
	var a: Vector3 = STATIONS[from_station]
	var b: Vector3 = STATIONS[station]
	var u := 1.0 - float(walking_until - tick) / float(WALK)
	# Wrap around the partition on the gallery side.
	if (a.x < 0.0) != (b.x < 0.0):
		var corner := Vector3(-0.60, 0, 2.23)
		var first := a.distance_to(corner)
		var length := first + b.distance_to(corner)
		if u * length < first: return a.lerp(corner, u * length / first)
		return corner.lerp(b, (u * length - first) / maxf(length - first, 0.001))
	return a.lerp(b, u)


func sample_position() -> Vector3:
	if arrives >= 0:
		return LOAD.lerp(HOOD, 1.0 - float(arrives - tick) / float(HANDOFF))
	return PITCH if proof_active and station == "proof" else HOOD


static func rays(eye: Vector3, direction: Vector3, target: Vector3, partition := true, hood := true) -> int:
	var hits := 0
	for x in [-0.095, 0.0, 0.095]:
		for y in [-0.115, 0.0, 0.115]:
			for z in [-0.075, 0.0, 0.075]:
				var point := target + Vector3(x, y, z)
				var delta := point - eye
				if delta.length_squared() > 64.0 or delta.normalized().dot(direction.normalized()) < 0.68:
					continue
				if (not partition or WALL.intersects_segment(eye, point) == null) and (not hood or BAFFLE.intersects_segment(eye, point) == null):
					hits += 1
	return hits


func _refresh_optics() -> void:
	var target := sample_position() if received != "" or arrives >= 0 else SOURCE
	# Samples inside their opaque transit sleeve have no optical target.
	sample_rays = 0 if arrives >= 0 else rays(READER, READER_FACING, target)


func step(action: String = "") -> void:
	tick += 1
	if arrives == tick:
		received = transit
		transit = ""
		arrives = -1
		_note("drawer_received", "Clerk's receipt: %s. Set that mark on the dial. The hood hides the sample from the Clerk." % mark().to_upper())
	if panic_at == tick:
		panic_at = -1
		panic_fired = true
		if braced and latch_at >= 0:
			emergency = true
			_note("panic_braced", "The Clerk pulled the shutter. Your brace held the latch; the emergency stamp is ready.")
		else:
			latch_at = -1
			_note("panic_closed", "The Clerk pulled the shutter. The latch has jammed. Live proof and a regular release can recover this case.")
	if action != "": _act(action)
	_refresh_optics()
	if proof_active and manual.edition == "III":
		if received == "prism" and sample_rays >= 14:
			proof_ticks += 1
			if proof_ticks == PROOF:
				manual = NEW_RULE
				_note("manual_revised", "The Clerk saw the gold return. Edition IV now admits a witnessed live exception.")
		else:
			proof_ticks = 0


func _act(action: String) -> void:
	if action == "optics":
		optics = not optics
		return
	if outcome != "": return
	if STATIONS.has(action):
		_move(action)
		return
	if not _arrived():
		_note("walking", "Finish moving to the selected station first.")
		return
	match action:
		"take_prism", "take_wax":
			if station != "survey":
				_note("wrong_station", "Pick up samples at the Survey desk.")
				return
			held = "prism" if action == "take_prism" else "wax"
			_note("sample_selected", "Carrying %s marked %s. The blind drawer is at station 02." % [held, mark().to_upper()])
		"send":
			if station != "drawer" or held == "" or arrives >= 0:
				_note("send_refused", "The drawer needs a held sample, an empty slide, and the Runner at station 02.")
				return
			_cut_proof()
			received = ""
			transit = held
			held = ""
			arrives = tick + HANDOFF
			dial = ""
			if latch_at != -1:
				latch_at = -1
				emergency = false
			_note("drawer_sent", "Blind slide in transit. The Clerk can read its registration slit when it arrives.")
		"sun", "moon":
			if station not in ["drawer", "proof"]:
				_note("wrong_station", "Set the dial at the Drawer or Proof station.")
				return
			dial = action
			if latch_at != -1 and not _registered():
				latch_at = -1
				emergency = false
			_note("dial_set", "Dial set to %s." % dial.to_upper())
		"show":
			if station not in ["drawer", "proof"] or received == "":
				_note("nothing_to_show", "A sample must arrive before you can raise a slide at Drawer or Proof.")
				return
			if proof_active:
				_cut_proof()
				_note("proof_lowered", "Slide lowered into the hood.")
				return
			proof_active = true
			if station == "drawer":
				_note("proof_occluded", "The registration slit can read the mark. The lead hood blocks the Clerk's view of the sample.")
			elif received == "wax":
				_note("proof_inert", "The Clerk can see the wax copy. It gives no gold return.")
			else:
				_note("proof_started", "Keep the prism raised in the Clerk's sight for 40 uninterrupted ticks.")
		"release", "override": _request_release(action == "override")
		"brace":
			if station != "threshold" or panic_at < 0 or latch_at < 0:
				_note("brace_refused", "Fit the brace at the Threshold while the override latch is open and the warning is active.")
				return
			braced = true
			_note("brace_set", "Brace fitted. Let the warning resolve before stamping.")
		"file":
			if station != "threshold" or not _registered() or not stamp_ready():
				_note("file_refused", "The Threshold stamp needs a matching receipt, a settled open latch, and a clear warning line.")
				return
			outcome = "emergency" if emergency else ("clean" if debt == 0 else "recovered")
			_note("filed_" + outcome, {"clean": "Clean filing complete. Edition IV is in effect; pressure debt is zero.",
				"emergency": "Emergency filing complete. The brace held; pressure debt remains on the docket.",
				"recovered": "Filing recovered after override. Edition IV is in effect; pressure debt remains."}[outcome])


func _request_release(force: bool) -> void:
	if station not in ["drawer", "proof"]:
		_note("wrong_station", "The Clerk takes release requests from the Drawer and Proof stations.")
		return
	if not _registered():
		_note("receipt_mismatch", "The Clerk needs a delivered sample and a dial matching the receipt.")
		return
	if force:
		if debt > 0 or latch_at >= 0:
			_note("override_spent", "One red-wax seal per case. Use a regular release once the manual is revised.")
			return
		debt += 1
		panic_at = tick + WARNING
		latch_at = tick
		_note("override_warning", "Latch forced. Fit the brace at station 04 before the Clerk pulls the shutter.")
	elif permitted():
		if latch_at < 0: latch_at = tick
		emergency = false
		_note("release_allowed", "Edition IV authorizes the latch. Proceed to the Threshold stamp.")
	else:
		_note("release_denied", "Edition III bars sealed registers. Show a live counterexample or break the override seal."
			if manual.edition == "III" else "Edition IV admits the witnessed live prism. This substitute gives no gold return.")


func stamp_ready() -> bool:
	return latch_at >= 0 and tick - latch_at >= STAMP and panic_at == -1


func observe() -> Dictionary:
	var target := sample_position() if received != "" or arrives >= 0 else SOURCE
	return {"schema": "evidence_register.v1", "phase": "filed" if outcome != "" else "investigation", "plate": trial + 1,
		"tick": tick, "tick_rate": TICK_RATE, "station": station, "walk_ticks_left": maxi(0, walking_until - tick),
		"survey_mark": mark(), "held": held, "drawer_ticks_left": maxi(0, arrives - tick),
		"received": received, "receipt_mark": mark() if received != "" else "", "dial": dial,
		"runner_source_rays": rays(STATIONS.survey + Vector3.UP * 1.60, SOURCE - STATIONS.survey - Vector3.UP * 1.60, SOURCE),
		"clerk_source_rays": rays(READER, READER_FACING, SOURCE), "clerk_sample_rays": sample_rays,
		"sample_socket": "sleeve" if arrives >= 0 else ("proof" if target == PITCH else ("hood" if received != "" else "survey")),
		"slide_raised": proof_active, "proof_ticks": proof_ticks, "proof_ticks_required": PROOF,
		"manual": manual.duplicate(true), "rule_permits_release": permitted(), "pressure_debt": debt,
		"warning_ticks_left": maxi(0, panic_at - tick), "panic_fired": panic_fired, "brace_fitted": braced,
		"latch_open": latch_at >= 0, "stamp_ready": stamp_ready(), "outcome": outcome, "optics_overlay": optics,
		"last_event": last_event, "message": message, "receipts": audit.duplicate(true)}

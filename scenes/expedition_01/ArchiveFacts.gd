extends RefCounted
## Expedition-local evidence. Facts are sticky; movement/gaze samples are transient.
const REQUIRES := {
	"door_paired": ["dual_gaze_b2"],
	"comparison": ["dual_gaze_b2", "solo_lock_b3"],
	"hale_comparison": ["dual_gaze_b2", "hale_saw_crossing_b3", "solo_lock_b3"],
	"hale_follow": ["solo_crossing_b3"],
}
var _facts := {}
var _decisions: Array[Dictionary] = []
var _last := {}
var _start_tick := Engine.get_physics_frames()
var run_seed := 1

func _init() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--run-seed="):run_seed=int(arg.get_slice("=",1))

func _append(entry: Dictionary) -> void:
	entry["tick"]=Engine.get_physics_frames()-_start_tick
	entry["seed"]=run_seed
	_decisions.append(entry)

func record(id: String, source: String) -> void:
	if not _facts.has(id):
		_facts[id] = source
		_append({"fact": id, "intent": "observe", "rule": source, "delta": {id: true}})

func has_fact(id: String) -> bool:
	return _facts.has(id)

func allows(id: String) -> bool:
	for fact in REQUIRES[id]:
		if not has_fact(fact):return false
	return true

func decide(id: String, allowed: bool, reason: String) -> bool:
	var entry := {"decision": id, "intent": id, "rule": REQUIRES.get(id, id), "allowed": allowed, "reason": reason}
	if _last.get(id) != entry:
		_last[id] = entry
		_append(entry.duplicate())
	return allowed

func evaluate(id: String) -> bool:
	var missing: Array = REQUIRES[id].filter(func(fact):return not has_fact(fact))
	return decide(id, missing.is_empty(), "witnessed" if missing.is_empty() else ", ".join(missing))

func snapshot() -> Dictionary:
	return {"seed": run_seed, "decision_deduplication": "consecutive identical outcomes per intent", "facts": _facts.duplicate(), "decisions": _decisions.duplicate(true)}

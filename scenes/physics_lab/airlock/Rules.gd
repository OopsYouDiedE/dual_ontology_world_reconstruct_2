extends RefCounted
## Small typed subset of the project's SELF / FORBID rule vocabulary. Only
## the native span order is patchable; the hard dock interlock stays separate.
const RULE_ID := "hale_unbraced_span"
const LEAD_RULE_ID := "lead_wait_for_dog"
const HALE_RULE := {
	"rule_id": RULE_ID, "scope": "SELF", "source": "NATIVE", "modality": "FORBID",
	"action": {"type": "Interact", "target_entity_id": "span", "op_type": "cross"},
	"condition": ["not", ["eq", "span", "dog_seated", 1]],
	"label": "Hale / Do not take an unbraced span."
}
const LEAD_RULE := {
	"rule_id": LEAD_RULE_ID, "scope": "SELF", "source": "NATIVE", "modality": "FORBID",
	"action": {"type": "Interact", "target_entity_id": "exit", "op_type": "traverse"},
	"condition": ["not", ["eq", "span", "dog_seated", 1]],
	"label": "Lead / Surveyor secures a span before you clear the room."
}
const NATIVE_ORDER := {"type": "Interact", "target_entity_id": "span", "op_type": "cross"}
const LEAD_ORDER := {"type": "Interact", "target_entity_id": "exit", "op_type": "traverse"}
const FRESH_TICKS := 3600
var records: Array[Dictionary] = []
var revision: Dictionary = {}
var rejection := ""


static func evaluate(expr: Array, fields: Dictionary) -> bool:
	match expr[0]:
		"not": return not evaluate(expr[1], fields)
		"eq": return fields.get(expr[1], {}).get(expr[2], -1) == expr[3]
	return false


static func forbidden(rule: Dictionary, action: Dictionary, fields: Dictionary) -> bool:
	for key: String in rule.action:
		if rule.action[key] != action.get(key): return false
	return rule.modality == "FORBID" and evaluate(rule.condition, fields)


func add_record(held: bool, tick: int, observer: int, specimen: StringName, start_tick: int) -> void:
	# Only the carriage referee can create these. The radio submits IDs, not observations.
	records.append({"id": records.size() + 1, "span": "span", "specimen": specimen,
		"kind": "SUPPORTED" if held else "CAUGHT", "observer": observer, "start": start_tick, "tick": tick})


func recent(kind: String, tick: int) -> Dictionary:
	for i in range(records.size() - 1, -1, -1):
		var r: Dictionary = records[i]
		if r.kind == kind and r.tick + FRESH_TICKS >= tick: return r
	return {}


func persuade(rule_id: String, refs: Array, tick: int, now_lit: bool) -> bool:
	rejection = "Hale: The test needs a caught load and a load through to the far tray."
	if rule_id != RULE_ID or refs.size() != 2 or refs[0] == refs[1]: return false
	var caught := recent("CAUGHT", tick)
	var carried := recent("SUPPORTED", tick)
	if caught.is_empty() or carried.is_empty(): return false
	if not refs.has(caught.id) or not refs.has(carried.id) or caught.specimen != carried.specimen: return false
	if caught.observer != 0 or carried.observer != 0 or caught.span != "span" or carried.span != "span": return false
	if not now_lit:
		rejection = "Hale: Take the witness position again. Then I'll accept the trial."
		return false
	revision = {"rule_id": RULE_ID, "mode": "EXEMPT_ACTION", "action": NATIVE_ORDER.duplicate(),
		"evidence": refs.duplicate(), "expires": mini(caught.tick, carried.tick) + FRESH_TICKS,
		"condition": ["eq", "witness", "live", 1]}
	rejection = ""
	return true


func allows_departure(tick: int, fields: Dictionary) -> bool:
	if not forbidden(HALE_RULE, NATIVE_ORDER, fields): return true
	return not revision.is_empty() and tick <= revision.expires and evaluate(revision.condition, fields)

extends RefCounted
## Hale's authored belief and its local exception. Only a continuous sequence
## of witnessed actor actions can produce an admissible counterexample.
const RULE := {"id":"hale_lit_span", "scope":"SELF", "modality":"FORBID", "action":"observe_lit_span",
	"condition":["eq","span_lit",true], "claim":"The light takes anyone who looks into a span."}
const MIN_OBSERVED := 13
var observed := 0
var saw_survival := false
var counterexample := false
var revised := false


func record(lead_grounded_on_span: bool, lead_witness: bool, hale_saw_lead: bool, lead_back_on_bank: bool) -> bool:
	if counterexample: return false
	if lead_grounded_on_span and lead_witness and hale_saw_lead:
		observed += 1
		if observed >= MIN_OBSERVED: saw_survival = true
	else:
		observed = 0
	if lead_back_on_bank and hale_saw_lead and saw_survival:
		counterexample = true
		return true
	return false


func invalidate_attempt() -> void:
	observed = 0
	saw_survival = false


func speak(face_to_face: bool) -> bool:
	if revised or not counterexample or not face_to_face: return false
	revised = true
	return true


func forbidden(action: String, facts: Dictionary) -> bool:
	return action == RULE.action and facts.get(RULE.condition[1], false) == RULE.condition[2] and not revised

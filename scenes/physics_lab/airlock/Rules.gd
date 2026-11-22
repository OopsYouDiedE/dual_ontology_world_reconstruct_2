extends RefCounted
## Hale's local rule projections. An exception narrows the taboo; it does not erase it.
const PLAYER := [
	{"when":"light_reddens","do":"look_away","notice":"If the light reddens, look away."},
	{"when":"gaze_broken","within_ticks":60,"do":"regain_stone","notice":"Off the span within a second of looking away."},
]
const TABOO := {"observe_lit_span":{"not":["lead_already_watching"]}}
const ORIGINAL := {"deny":["observe_lit_span","step_into_void"],"exception":{}}
const REVISED := {"deny":["observe_lit_span","step_into_void"],"exception":TABOO}
const DISTORTED := {"deny":["step_into_void"],"urge":["keep_both_eyes_on_red"]}
const MIN_SOLO := 27
const MIN_UNINTERRUPTED_SOLO := 84
const PANIC_LIMIT := 46
var ast := ORIGINAL
var counterexample := false
var revised := false
var panic := 0
var distorted := false
var red_witnessed := false
var solo := 0

static func player_notice() -> String:
	return PLAYER[0].notice + "\n" + PLAYER[1].notice

func sample_trial(hale_eye_on_span: bool, lead_eye_on_span: bool) -> String:
	if hale_eye_on_span and lead_eye_on_span:
		red_witnessed = true
		panic += 1
		if not distorted and panic >= PANIC_LIMIT:
			distorted = true
			ast = DISTORTED
			return "DISTORTED"
	solo = solo + 1 if hale_eye_on_span and not lead_eye_on_span and not distorted else 0
	if solo >= (MIN_SOLO if red_witnessed else MIN_UNINTERRUPTED_SOLO):
		counterexample = true
		return "EVIDENCE"
	return ""

func begin_trial() -> void:
	red_witnessed = false
	solo = 0

func ground() -> void:
	panic = 0
	distorted = false
	ast = REVISED if revised else ORIGINAL
	begin_trial()

func speak(face_to_face: bool) -> bool:
	if revised or distorted or not counterexample or not face_to_face: return false
	revised = true
	ast = REVISED
	return true

func forbidden(action: String, facts: Dictionary = {}) -> bool:
	if action not in ast.deny: return false
	var exception: Dictionary = ast.get("exception",{}).get(action,{})
	if exception.has("not"):
		return bool(facts.get(exception["not"][0],true))
	return true

func urges_overlap() -> bool:
	return "keep_both_eyes_on_red" in ast.get("urge",[])

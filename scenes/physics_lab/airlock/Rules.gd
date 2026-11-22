extends RefCounted
## Finite hypothesis test over Hale's local sensory frames. The bridge owns the law.
const PLAYER := [
	{"when":"light_reddens","do":"look_away","notice":"If the light reddens, look away."},
	{"when":"gaze_broken","within_ticks":60,"do":"regain_stone","notice":"Off the span within a second of looking away."},
]
const TREAD := {"id":"P-03", "when":"at_low_lintel", "do":"keep_tread_in_sight_or_retreat",
	"notice":"At a low lintel, keep the pale tread in sight. If it goes dark, retreat to stone."}
const TABOO := {"id":"H-03", "notice":"In company, do not look into a hanging span. At a low lintel, the lead goes first. Feel for the floor before stepping."}
const SINGLE_EXCEPTION := "Only with my companion visibly turned away."
const ORIGINAL := {"hold":"DO_NOT_LOOK","step":"DO_NOT_STEP_INTO_VOID","lintel":"LEAD_FIRST"}
const DISTORTED := {"hold":"JOIN_VISIBLE_GAZE","step":"DO_NOT_STEP_INTO_VOID","lintel":"LEAD_FIRST"}
const LOOK_IS_HAZARD := "any_gaze_is_dangerous"
const JOIN_IS_HAZARD := "joined_gaze_is_dangerous"
const NO_GAZE_HAZARD := "gaze_is_not_the_hazard"
const MIN_SOLO := 27
const MIN_UNINTERRUPTED_SOLO := 84
const PANIC_LIMIT := 46
const HAND_SIGNAL := 13
const NONE := "UNSEEN"
var ast: Dictionary = ORIGINAL.duplicate(true)
var hypotheses: Array[String] = [LOOK_IS_HAZARD, JOIN_IS_HAZARD, NO_GAZE_HAZARD]
var counterexample := false
var revised := false
var panic := 0
var distorted := false
var red_witnessed := false
var solo := 0
var together := 0
var apart := 0
var overlap_seen_on_stone := 0


static func player_notice() -> String:
	return PLAYER[0].notice + "\n" + PLAYER[1].notice


func _fits(hypothesis: String, head: String, color: String) -> bool:
	match hypothesis:
		LOOK_IS_HAZARD: return color == "RED"
		JOIN_IS_HAZARD: return (head == "TOWARD") == (color == "RED")
		NO_GAZE_HAZARD: return color == "WHITE"
	return false


func sample_trial(local: Dictionary) -> String:
	# Only compare an aspect actually seen during my own look and a visible head pose.
	var color: String = local.get("color", NONE)
	var head: String = local.get("head", NONE)
	if local.get("heard_red", false) or color == "RED":
		panic += 1
		if not distorted and panic >= PANIC_LIMIT:
			distorted = true
			ast = DISTORTED.duplicate(true)
			return "DISTORTED"
	if distorted: return ""
	var both_red := color == "RED" and head == "TOWARD"
	together = together + 1 if both_red else 0
	if together == 5:
		red_witnessed = true
		_prune(head,color)
	solo = solo + 1 if color == "WHITE" and head == "AWAY" else 0
	if not counterexample and solo >= (MIN_SOLO if red_witnessed else MIN_UNINTERRUPTED_SOLO):
		_prune(head,color)
		counterexample = LOOK_IS_HAZARD not in hypotheses
		if counterexample: return "EVIDENCE"
	return ""


func _prune(head: String, color: String) -> void:
	var surviving: Array[String] = []
	for h in hypotheses:
		if _fits(h,head,color): surviving.append(h)
	# Contradictory or misread signals do not fabricate certainty.
	if not surviving.is_empty(): hypotheses = surviving


func begin_trial() -> void:
	red_witnessed = false
	solo = 0
	together = 0
	apart = 0
	overlap_seen_on_stone = 0
	if not revised:
		counterexample = false
		hypotheses.assign([LOOK_IS_HAZARD,JOIN_IS_HAZARD,NO_GAZE_HAZARD])


func ground() -> void:
	panic = 0
	distorted = false
	ast = _inferred() if revised else ORIGINAL.duplicate(true)
	begin_trial()


func speak(face_to_face: bool, clause := "H-03", proposed_pose := "AWAY") -> bool:
	if revised or distorted or not counterexample or not face_to_face or clause != TABOO.id: return false
	if proposed_pose not in _inferred().allowed_heads: return false
	revised = true
	ast = _inferred()
	return true


func _inferred() -> Dictionary:
	# Compile a conservative rule: every surviving explanation must predict white.
	var safe: Array[String] = []
	for pose in ["AWAY","TOWARD"]:
		var unanimous := true
		for h in hypotheses:
			if not _fits(h,pose,"WHITE"): unanimous = false
		if unanimous: safe.append(pose)
	return {"hold":"MODEL_CHECK_GAZE","step":"DO_NOT_STEP_INTO_VOID","lintel":ORIGINAL.lintel,"allowed_heads":safe,
		"supported_hypotheses":hypotheses.duplicate()}


func decide(local: Dictionary, action: String) -> String:
	var head: String = local.get("head", NONE)
	var bank: String = local.get("bank", NONE)
	match ast.hold:
		"DO_NOT_LOOK": return "REFUSE"
		"JOIN_VISIBLE_GAZE":
			return "JOIN" if head == "TOWARD" else "SEARCH"
		"MODEL_CHECK_GAZE":
			if action == "TAKE": return "TAKE" if bank in ["island","far"] and head in ast.allowed_heads else "WAIT"
			if action == "GIVE":
				# Recoil from a known overlap if I can verify my partner is on stone.
				var safe_to_recoil: bool = bank == "far" and local.get("color",NONE) == "RED"
				overlap_seen_on_stone = overlap_seen_on_stone+1 if safe_to_recoil else 0
				if overlap_seen_on_stone >= 9: return "RECOIL"
				# Don't pull a footing away from someone whose safety I cannot see.
				var partner_safe: bool = bank == "far" or (ast.get("lintel", "") != "LEAD_FIRST" and bank == "island")
				apart = apart+1 if partner_safe and head == "AWAY" else 0
				if apart >= HAND_SIGNAL: return "GIVE"
				return "HOLD"
	return "WAIT"


func permits_step(footing: bool) -> bool:
	return footing or ast.step != "DO_NOT_STEP_INTO_VOID"

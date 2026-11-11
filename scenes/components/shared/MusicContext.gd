extends RefCounted
## Read-only presentation policy. Never infer dramatic music from available
## answers, a hidden NPC action, the demon's mere presence or an open notebook.

static func background(snapshot: Dictionary) -> String:
	if snapshot.has("time"):
		var minute := posmod(int(float(snapshot.time)), 1440)
		return "night" if minute < 420 or minute >= 1260 else "day"
	if not snapshot.has("chapter"):
		return ""
	if int(snapshot.chapter) == 1:
		return "door_side"
	var minute := posmod(int(float(snapshot.get("game_time", 0.0))), 1440)
	if minute < 7 * 60 or minute >= 21 * 60:
		return "night"
	if minute < 11 * 60 + 30:
		return "day"
	if minute < 13 * 60 + 30:
		return "day_noon"
	if minute < 17 * 60 + 30:
		return "day_afternoon"
	return "day_evening"

static func is_formal_confrontation(presentation: Dictionary) -> bool:
	# This is the already-delivered adjudication projected into the dialogue.
	# Candidate answers and arbitrary prose containing "对质" are not receipts.
	var judgment: Variant = presentation.get("judgment", null)
	if not judgment is Dictionary:
		return false
	return str(judgment.get("status", "")) in ["answer_accepted", "answer_rejected"]

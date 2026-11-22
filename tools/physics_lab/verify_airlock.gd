extends SceneTree
## Exercise evidence authority and expiry apart from the Forward+ physical replay.
const Rules = preload("res://scenes/physics_lab/airlock/Rules.gd")
var failures := 0

func check(ok: bool, label: String) -> void:
	if ok: return
	failures += 1
	printerr(label)

func _initialize() -> void:
	var rules := Rules.new()
	var live := {"span": {"dog_seated": 0}, "witness": {"live": 1}}
	var dark := {"span": {"dog_seated": 0}, "witness": {"live": 0}}
	var braced := {"span": {"dog_seated": 1}, "witness": {"live": 0}}
	check(not rules.allows_departure(10, live), "Light alone cannot overrule Hale.")
	check(Rules.forbidden(Rules.LEAD_RULE, Rules.LEAD_ORDER, live), "The lead still requires the far dog.")
	rules.add_record(false, 10, 0, &"proof_load", 1)
	check(not rules.persuade(Rules.RULE_ID, [1], 11, true), "One trial cannot revise the order.")
	rules.add_record(true, 20, 0, &"other_load", 12)
	check(not rules.persuade(Rules.RULE_ID, [1, 2], 21, true), "The pair must use one specimen.")
	rules.add_record(true, 30, 0, &"proof_load", 23)
	check(not rules.persuade(Rules.RULE_ID, [1, 9], 31, true), "Unknown evidence IDs fail.")
	check(not rules.persuade(Rules.RULE_ID, [1, 1], 31, true), "Duplicate evidence IDs fail.")
	check(not rules.persuade(Rules.LEAD_RULE_ID, [1, 3], 31, true), "Only Hale's rule is revisable.")
	check(not rules.persuade(Rules.RULE_ID, [1, 3], 31, false), "The witness must be live at filing.")
	check(rules.persuade(Rules.RULE_ID, [1, 3], 31, true), "A valid comparison under a live witness is accepted.")
	check(rules.allows_departure(32, live) and not rules.allows_departure(32, dark), "The exemption tracks current sight.")
	check(Rules.forbidden(Rules.LEAD_RULE, Rules.LEAD_ORDER, live), "The revision leaves the lead's rule intact.")
	check(rules.allows_departure(10 + Rules.FRESH_TICKS, live), "The oldest slip defines the inclusive expiry.")
	check(not rules.allows_departure(11 + Rules.FRESH_TICKS, live), "An expired exemption does not authorize departure.")
	check(not rules.persuade(Rules.RULE_ID, [1, 3], 11 + Rules.FRESH_TICKS, true), "Expired slips cannot renew an exemption.")
	check(rules.allows_departure(11 + Rules.FRESH_TICKS, braced), "The mechanical dog satisfies the native order.")
	check(not Rules.forbidden(Rules.LEAD_RULE, Rules.LEAD_ORDER, braced), "The lead can clear a braced span.")
	print("Airlock evidence checks: %d failures" % failures)
	quit(0 if failures == 0 else 1)

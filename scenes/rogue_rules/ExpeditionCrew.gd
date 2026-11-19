extends RefCounted
## Field agency is separate from the residents' navigation and needs simulation.
const FULL_TRUST := 4
const MAX_NERVE := 6
var people := {}
var upgrades := {"Infirmary": false, "Watch lamp": false}
var supplies := 0

func recruit(id: String) -> void:
	if not people.has(id):
		people[id] = {"trust": FULL_TRUST, "stress": 0, "wound": 0.0, "spent": false}

func deployable(id: String) -> bool:
	return people.has(id) and people[id].wound <= 0.0

func willing(id: String) -> bool:
	return deployable(id) and people[id].trust >= 2 and people[id].stress < MAX_NERVE and not people[id].spent

func pressure(party: Array, cost: int) -> void:
	for id in party:
		if people.has(id): people[id].stress = clampi(people[id].stress + cost, 0, MAX_NERVE)

func abandon(id: String, witnesses: Array) -> void:
	if not deployable(id): return
	people[id].wound = 36.0
	people[id].trust = 0
	for witness in witnesses:
		if witness != id: people[witness].trust = maxi(0, people[witness].trust - 1)
	pressure(witnesses, 3)

func wound(id: String, seconds: float) -> void:
	if people.has(id): people[id].wound = maxf(people[id].wound, seconds)

func return_to_camp() -> void:
	for row in people.values():
		row.spent = false
		row.stress = maxi(0, row.stress - 3)

func rest(delta: float) -> bool:
	var healed := false
	for row in people.values():
		if row.wound <= 0.0: continue
		row.wound = maxf(0.0, row.wound - delta * (2.0 if upgrades.Infirmary else 1.0))
		healed = healed or row.wound <= 0.0
	return healed

func build(name: String) -> bool:
	if not upgrades.has(name) or upgrades[name] or supplies < 3: return false
	supplies -= 3
	upgrades[name] = true
	return true

func status(id: String) -> String:
	var row: Dictionary = people[id]
	if not deployable(id): return "in the clinic · %ds" % ceili(row.wound)
	return "trust %d/%d · stress %d/%d" % [row.trust, FULL_TRUST, row.stress, MAX_NERVE]

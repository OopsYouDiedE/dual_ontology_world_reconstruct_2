extends SceneTree

const Camp = preload("res://scenes/rogue_camp/CampResidents.gd")
const A := Vector2i(0, 0)
const B := Vector2i(1, 0)
const C := Vector2i(2, 0)
const D := Vector2i(1, 1)
const X := Vector2i(0, 1)
var failures := 0


func _initialize() -> void:
	_test_walk_use_and_result()
	_test_contention()
	_test_departure()
	_test_need_priority_and_stall()
	_test_repeatability_and_social()
	print("Camp residents: %d failure(s)" % failures)
	quit(1 if failures else 0)


func _expect(ok: bool, description: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + description)


func _person(id: String, cell: Vector2i, hunger: int = 60) -> Dictionary:
	return {"id": id, "cell": cell, "needs": {"hunger": hunger}}


func _meal(id: String, stand: Vector2i, stock: int = 1) -> Dictionary:
	return {"id": id, "stand": stand, "need": "hunger", "duration": 2, "relief": 70, "stock": stock}


func _test_walk_use_and_result() -> void:
	var camp := Camp.new()
	var graph := {A: [B], B: [A, C], C: [B], X: []} # Adjacent tile X has a wall edge.
	_expect(camp.setup("lead", graph, [_person("lead", A)], [_meal("01_wall", X), _meal("02_meal", C)]), "valid setup")
	graph[A].clear() # Inputs are copied by setup.
	_expect(not camp.setup("missing", graph, [_person("lead", A)], []), "invalid setup rejected atomically")
	_expect(camp.enter_camp(), "enter camp")
	camp.step()
	var reading := camp.snapshot()
	_expect(reading.objects["01_wall"].reserved_by == "", "unreachable fixture skipped")
	_expect(reading.objects["02_meal"].reserved_by == "lead", "reachable fixture reserved")
	_expect(reading.residents.lead.cell == A, "reservation does not teleport")
	camp.step()
	_expect(camp.snapshot().residents.lead.cell == B, "walk one graph edge per tick")
	camp.step()
	reading = camp.snapshot()
	_expect(reading.residents.lead.status == &"using_object" and reading.events.back().tick == 3, "arrival starts operation")
	camp.step()
	reading = camp.snapshot()
	_expect(reading.objects["02_meal"].stock == 1 and reading.residents.lead.needs.hunger == 68, "no effect before duration elapses")
	camp.step()
	reading = camp.snapshot()
	_expect(reading.objects["02_meal"].stock == 0 and reading.objects["02_meal"].reserved_by == "", "stock and reservation updated")
	_expect(reading.residents.lead.needs.hunger == 0 and reading.events.back().relief == 70 and reading.events.back().tick == 5, "completion changes the actual need")
	reading.objects["02_meal"].stock = 99
	for i in 60:
		camp.step()
	reading = camp.snapshot()
	_expect(reading.events.size() == 3 and reading.residents.lead.needs.hunger == 100, "depleted stock stays unavailable; need clamps")


func _test_contention() -> void:
	var camp := Camp.new()
	_expect(camp.setup("lead", {A: [B], B: [A, C, D], C: [B], D: [B]},
		[_person("lead", A), _person("other", D)], [_meal("meal", C, 2)]), "contention setup")
	camp.enter_camp()
	camp.step()
	var reading := camp.snapshot()
	_expect(reading.objects.meal.reserved_by == "lead" and reading.residents.other.status == &"waiting_for_object", "one reservation for two contenders")
	for i in 11:
		camp.step()
		reading = camp.snapshot()
		_expect(reading.residents.lead.cell != reading.residents.other.cell, "actors never overlap")
	var completions := []
	for event in reading.events:
		if event.kind == &"completed":
			completions.append(event.resident_id)
	_expect(completions == ["lead", "other"], "first user yields stand and second user can finish")


func _test_departure() -> void:
	var camp := Camp.new()
	var changes := []
	camp.control_changed.connect(func(mode: StringName, id: String) -> void:
		changes.append([mode, id]))
	_expect(camp.setup("lead", {A: []}, [_person("lead", A)], [_meal("meal", A)]), "departure setup")
	camp.enter_camp()
	camp.step()
	camp.step()
	_expect(camp.leave_camp() and not camp.leave_camp(), "departure is idempotent")
	var reading := camp.snapshot()
	_expect(changes == [[&"camp_ai", "lead"], [&"captain", "lead"]] and reading.mode == &"captain", "captain control handoff")
	_expect(reading.events.back().reason == &"left_camp" and reading.objects.meal.reserved_by == "" and reading.objects.meal.stock == 1, "departure cancels in-flight use without payment or reward")
	camp.step()
	_expect(camp.snapshot() == reading, "outside camp freezes resident state")
	camp.enter_camp()
	camp.step()
	_expect(camp.snapshot().residents.lead.job.get("remaining") == 2, "re-entry starts fresh work at full duration")


func _test_need_priority_and_stall() -> void:
	var camp := Camp.new()
	var first := _person("lead", A, 60)
	first.needs.fatigue = 99
	var rest := {"id": "bed", "stand": C, "need": "fatigue", "relief": 80, "duration": 1}
	# On step one lead reserves the bed via B. Other subsequently reserves B,
	# making the original route inaccessible; a long use exposes the timeout.
	var blocker := _meal("meal", B)
	blocker.duration = 12
	_expect(camp.setup("lead", {A: [B, X], B: [A, C, D], C: [B], D: [B], X: [A]},
		[first, _person("other", D, 98)], [rest, blocker, _meal("snack", X)]), "stall setup")
	camp.enter_camp()
	camp.step()
	_expect(camp.snapshot().residents.lead.job.object_id == "bed", "most urgent reachable need wins")
	for i in Camp.MAX_STALL:
		camp.step()
	var reading := camp.snapshot()
	_expect(reading.events.back().reason == &"path_blocked" and reading.objects.bed.reserved_by == "", "blocked path cancels and releases reservation")


func _test_repeatability_and_social() -> void:
	var first := Camp.new()
	var second := Camp.new()
	var resident := _person("lead", A, 0)
	resident.needs.social = 85
	var seat := {"id": "seat", "stand": A, "need": "social", "duration": 2, "relief": 45}
	for camp in [first, second]:
		_expect(camp.setup("lead", {A: []}, [resident], [seat]), "social setup")
		camp.enter_camp()
		for i in 3:
			camp.step()
	var reading := first.snapshot()
	_expect(reading == second.snapshot(), "same inputs reproduce the entire trace")
	_expect(reading.residents.lead.needs.social == 43 and reading.objects.seat.stock == -1,
		"social action relieves the configured need and unlimited stock stays unlimited")

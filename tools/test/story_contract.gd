extends SceneTree
## Contract regressions for launch modes, named fixtures and the five-day timeline.
const Engine_ := preload("res://scenes/dual_world/DualEngine.gd")
const Scenario := preload("res://scenes/components/testing/ScenarioLoader.gd")
const Launch := preload("res://scenes/main/LaunchRoute.gd")
const SEGMENTS := "res://assets/data/test_scenarios/segments/"
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, detail: String) -> void:
	if not ok:
		failures += 1
		printerr("FAIL: " + detail)

func launch_contract() -> void:
	for cases in [
		[[], Launch.TITLE], [["--dv-campaign-lab"], Launch.TITLE],
		[["--dv-scenario=story.json"], Launch.SEGMENT],
		[["--dv-snapshot=state.json"], Launch.STORY], [["--dv-story-direct"], Launch.STORY],
		[["--dv-workbench", "--scenario=fixture.yaml"], Launch.WORKBENCH],
		[["--dv-focused-workbench", "--scenario=fixture.yaml"], Launch.WORKBENCH],
		[["--scenario=fixture.yaml"], Launch.WORKBENCH],
	]:
		check(Launch.resolve(PackedStringArray(cases[0])).get("scene", "") == cases[1], "launch " + str(cases))
	for bad in [
		["--dv-scenario="], ["--dv-snapshot"], ["--dv-workbench=true"],
		["--dv-snapshot=state.json", "--dv-scenario=story.json"],
		["--dv-scenario=story.json", "--scenario=fixture.yaml"],
		["--dv-snapshot=a.json", "--dv-snapshot=b.json"],
	]:
		check(Launch.resolve(PackedStringArray(bad)).has("error"), "reject ambiguous launch " + str(bad))

func fixture_contract() -> int:
	var engine := Engine_.new()
	var seen_days := {}
	var files := DirAccess.get_files_at(SEGMENTS)
	var count := 0
	for file in files:
		if not file.ends_with(".json"): continue
		count += 1
		var loader := Scenario.new()
		if not loader.read(SEGMENTS + file):
			check(false, file + ": " + loader.error)
			continue
		var candidate := loader.state_for(engine)
		if candidate.is_empty():
			check(false, file + ": " + loader.error)
			continue
		check(int(candidate.beat_cursor) == int(engine.d.beat_index_by_id[loader.configuration.before_beat]), "named cursor: " + file)
		var day := int(candidate.day)
		seen_days[day] = true
		check(int(candidate.chapter) == (1 if day == 1 else 2), "derived chapter: " + file)
		check(Engine_.new().load_dict(candidate), "fixture also satisfies the production state shape: " + file)
	check(seen_days.size() == 5, "named fixtures cover all five days")
	var invalid := Scenario.new()
	check(not invalid.validate({"schema_version": 1, "before_beat": "d1_wake", "mock": {"beat_cursor": 0}}), "reject duplicate anchor")
	check(invalid.validate({"schema_version": 1, "before_beat": "missing"}) and invalid.state_for(engine).is_empty(), "reject unknown beat ID")
	return count

func gate_dispatch() -> void:
	for boundary in ["story_gate", "hold"]:
		var engine := Engine_.new()
		var i := int(engine.d.beat_index_by_id.d1_deduce_drag)
		engine.s.beat_cursor = i
		engine.s.room = "B-P"
		engine.s.t = float(engine.T(1, 8, 10))
		engine.s.deductions.ded_drag = "solved"
		engine.s[boundary] = {"beat": "d1_deduce_drag", "room": "B-P", "deduction": "ded_drag"}
		engine.tick(10.0)
		check(engine.s.current_beat == "d1_deduce_drag" and int(engine.s.beat_cursor) == i + 1, boundary + " releases only the first overdue beat")
		check(is_equal_approx(float(engine.s.t), 490.0), boundary + " release preserves the clock")
		engine.tick(0.0)
		check(engine.s.current_beat == "d1_inspect" and int(engine.s.beat_cursor) == i + 2, boundary + " allows the next beat on the next tick")

func save_and_evidence() -> void:
	var engine := Engine_.new()
	var snapshot := engine.save_dict()
	snapshot.flags.test_flag = true
	check(engine.load_dict(snapshot), "saved snapshot loads")
	engine.s.flags.test_flag = false
	check(snapshot.flags.test_flag == true, "loading does not alias the stored state")
	var invalid := snapshot.duplicate(true)
	invalid.pending_choice = 1
	var before := engine.save_dict()
	check(not engine.load_dict(invalid) and engine.s == before, "corrupt save leaves the active state untouched")
	var deduction: Dictionary = engine.d.deduction_by_id.ded_drag
	for test_case in ["undiscovered", "duplicate", "collected"]:
		engine.new_game(false)
		var first := str(deduction.evidence[0])
		var picked: Array = deduction.evidence.duplicate()
		if test_case == "duplicate":
			engine.s.evidence[first] = {}
			picked = [first, first, first, first]
		elif test_case == "collected":
			for id in picked: engine.s.evidence[id] = {}
		engine.open_deduction("ded_drag")
		engine.solve_deduction("ded_drag", str(deduction.correct), picked)
		check(engine.s.deductions.ded_drag == ("solved" if test_case == "collected" else "wrong"), "deduction evidence: " + test_case)

func deferred_deduction() -> void:
	var engine := Engine_.new()
	var loader := Scenario.new()
	check(loader.read(SEGMENTS + "day3-case.json"), "load the ballot case fixture")
	check(engine.load_dict(loader.state_for(engine)), "start from the ballot case fixture")
	engine.s.playing = true
	engine.tick(0.0)
	check(engine.s.pending_choice.beat_id == "d3_case" and engine.s.pending_deduction.id == "ded_vote", "the ballot case queues a deduction and a choice")
	check(engine.postpone_deduction() and not engine.s.waiting, "postponing opens the field before the choice")
	var saved := engine.save_dict()
	check(engine.load_dict(saved) and not engine.s.waiting, "the postponed evidence search survives a save and reload")
	engine.choose("d3_case", "probe")
	check(not engine.s.pending_choice.is_empty(), "the case choice cannot bypass its pending deduction")
	var t := float(engine.s.t)
	engine.tick(30.0)
	check(is_equal_approx(float(engine.s.t), t), "time stays fixed while evidence is missing")
	var dd: Dictionary = engine.d.deduction_by_id.ded_vote
	for eid in dd.evidence: engine.s.evidence[eid] = {}
	engine.s.room = "W-102"
	engine.tick(0.0)
	check(engine.s.room == "2F-cross-M", "postponed deduction returns to its original staging room")
	check(engine.s.postponed.is_empty() and engine.s.pending_deduction.id == "ded_vote", "the deduction reopens when evidence is complete")
	engine.solve_deduction(str(dd.id), str(dd.correct))
	check(not engine.s.pending_choice.is_empty() and engine.s.waiting, "the original case choice follows the deduction or conflict")

func all_beats() -> int:
	var engine := Engine_.new()
	# This is a deterministic rules check. It provides the relevant evidence
	# directly; production walking, evidence gestures and dialogue are tested separately.
	for i in engine.d.beats.size():
		var beat: Dictionary = engine.d.beats[i]
		check(int(engine.s.beat_cursor) == i, "cursor before " + str(beat.id))
		if i == int(engine.d.beat_index_by_id.d2_wind):
			engine.tick(100000.0)
			check(engine.s.chapter_complete and engine.continue_chapter(), "chapter one closes before day two can dispatch")
		var effective := engine._resolve_beat(beat)
		if bool(effective.get("requires_room", false)): engine.s.room = effective.room
		if effective.has("deduction"):
			for id in engine.d.deduction_by_id[effective.deduction].evidence: engine.s.evidence[id] = {}
		engine.s.t = float(beat.at)
		engine.tick(0.0)
		check(engine.s.current_beat == beat.id and int(engine.s.beat_cursor) == i + 1, "dispatch " + str(beat.id))
		for _j in 10:
			if not engine.s.pending_deduction.is_empty():
				var d: Dictionary = engine.d.deduction_by_id[engine.s.pending_deduction.id]
				for id in d.evidence: engine.s.evidence[id] = {}
				engine.solve_deduction(str(d.id), str(d.correct))
			elif not engine.s.pending_choice.is_empty():
				var choice: Dictionary = engine.s.pending_choice
				engine.choose(str(choice.beat_id), str(choice.choice.options[0].id))
			elif engine.s.pending_conflict != "":
				var conflict: Dictionary = engine.d.conflict_by_id[engine.s.pending_conflict]
				engine.resolve_conflict(str(conflict.id), str(conflict.correct))
			else:
				break
		check(not engine.s.waiting, "clear player gates before next beat: " + str(beat.id))
	engine.tick(100000.0)
	engine.tick(0.0)
	check(not str(engine.s.ending).is_empty(), "day 5 resolves an ending")
	return engine.d.beats.size()

func opening_contract() -> void:
	var e := Engine_.new()
	e.s.room = "B-P"
	e.s.flags.service_map = true
	for row in [[999, false, false, false], [1000, true, false, false], [1030, true, true, false], [1060, true, true, true]]:
		e.s.t = row[0]
		for i in 3:
			var target: String = ["A-P", "C-P", "D-P"][i]
			check((not e.path_to(target).is_empty()) == row[i+1], "route to %s at %s" % [target, row[0]])
	e.s.t = 1000
	e.s.beat_cursor = e.d.beat_index_by_id.d1_deduce_cuffs
	e.process_beats()
	check(e.s.room == "B-P" and e.s.story_gate.get("room") == "A-P", "wait for the first physical meeting")
	for order in ["hold", "send"]:
		e.new_game(false)
		e.s.t = 650
		e.s.room = "R05"
		e.s.beat_cursor = e.d.beat_index_by_id.d1_relay_c
		e.process_beats()
		check(e.s.room == "R05" and not e.actors_in_room("B-P").has("ruan"), "remote witness stays in Wing C")
		e.choose("d1_relay_c", order)
		e.s.t = 770
		e.process_beats()
		check(e.load_dict(e.save_dict()) and e.s.choices.slingOrder == order, "retain dispatch order")
		var first: Array = e.effective_beat_lines(e.d.beat_by_id.d1_meeting)[0]
		check(first[0] == ("shen" if order == "send" else "mora"), "handoff reflects sling delivery")
	e.new_game(false)
	e.s.t = 1170
	check(not e.actors_in_room("F03").has("margaret"), "Wing D still in transit at first sitting")
	e.s.t = 1190
	check(e.actors_in_room("F03").has("margaret") and e.actors_in_room("F04").has("mora"), "last group reaches supper")
	for option in ["latch", "frame"]:
		e.new_game(false)
		e.s.t = 1295
		e.s.beat_cursor = e.d.beat_index_by_id.d1_plan
		e.process_beats()
		e.choose("d1_plan", option)
		e.next_beat()
		check(e.load_dict(e.save_dict()) and e.continue_chapter(), "night roster survives chapter transition")
		e.next_beat()
		check(e.s.current_beat == "d2_wind" and e.actors_in_room("Wind-Corridor").has("quer" if option == "latch" else "huo"), "assigned partner reports on site")
		var lead: Array = e.effective_beat_lines(e.d.beat_by_id.d2_wind)[0]
		check(lead[0] == ("quer" if option == "latch" else "huo"), "night roster assigns next morning's lead")
	var legacy := e.save_dict()
	legacy.erase("opening_revision")
	legacy.t = 600
	legacy.room = "A-P"
	legacy.beat_cursor = 8
	check(e.load_dict(legacy) and not e.path_to("B-P").is_empty(), "old visit keeps its return route")
	legacy.t = 1880
	legacy.erase("beat_cursor")
	check(e.load_dict(legacy) and e.d.beats[e.s.beat_cursor].id == "d2_wind" and e.s.flags.legacy_opening_done.has("d1_poem"), "clock-only save preserves resolved day-one scenes")

func run() -> void:
	opening_contract()
	launch_contract()
	var fixtures := fixture_contract()
	gate_dispatch()
	save_and_evidence()
	deferred_deduction()
	var beats := all_beats()
	print("RESULT story_contract fixtures=%d beats=%d failures=%d" % [fixtures, beats, failures])
	quit(0 if failures == 0 else 1)

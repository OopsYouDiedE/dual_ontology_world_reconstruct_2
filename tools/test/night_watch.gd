extends SceneTree

const Main := preload("res://scenes/rogue/Run.tscn")
const Rules := preload("res://scenes/rogue_crossing/Crossing.gd")
var errors: Array[String] = []
var completed_routes := 0

func _initialize() -> void: call_deferred("_test")

func expect(value: bool, why: String) -> bool:
	if not value: errors.append(why)
	return value

func play(room: RefCounted, plan: Array, protocols: Array, witnesses := 0) -> Dictionary:
	var result := {}
	for step: Array in plan:
		result = room.act(step[0], step[1], protocols, false, witnesses)
		expect(not result.is_empty() and result.damage == 0, "%s/%s safe step %s" % [room.stage, room.variant, step])
	return result

func plans(stage: String, mirror: bool) -> Array:
	match stage:
		"intake": return [[[0,"issue"]],[[2,"coupon"]]]
		"returns": return [[[1,"slot_ash" if mirror else "slot_reed"]],[[1,"tie"],[2,"key"]]]
		"exchange": return [[[2,"partition"],[2,"booths"]],[[1,"mute"],[2,"sequence"]]]
		"wash": return [[[1,"unload"],[1,"pump_cistern" if mirror else "pump_yard"]],[[0,"sleeve"],[2,"awning"]]]
		"lift": return [[[2,"dog"],[1,"trim_hall" if mirror else "trim_yard"]],[[2,"brake"],[2,"under"]]]
		"airlock": return [[[1,"dry"],[1,"benches"]],[[2,"pin"],[2,"one_locker"]]]
		"shutter": return [[[1,"mute"],[1,"on_bell"]],[[2,"bleed"],[2,"early" if mirror else "shoe"]]]
		"hall": return [[[2,"survey"]],[[1,"depositions"]]]
		"darkroom": return [[[2,"bath"],[2,"print_copper" if mirror else "print_black"]],[[1,"carrier"],[1,"contact"]]]
		"relay": return [[[2,"partition"],[2,"parallel"]],[[1,"mute"],[1,"common"]]]
		"meridian": return [[[1,"mute"],[1,"seal"]],[[0,"docket"],[2,"brake"],[2,"wind"]]]
	return []

func _logic() -> void:
	var protocols := ["Ivory","Cobalt","Ochre"]
	for mirror in [false,true]:
		for stage in Rules.Rooms.TITLES:
			var several := []
			for plan: Array in plans(stage, mirror):
				var r := Rules.new(stage, mirror)
				var party := ["Ivory","Ivory","Ivory"] if plan.back()[1] == "common" else protocols
				var done := play(r, plan, party, 2)
				expect(done.get("clear", false), "%s/%s can finish %s" % [stage, mirror, plan])
				several.append(r.route)
			expect(several.size() == 2 and several[0] != several[1], "%s has distinct exits" % stage)
		var wrong := Rules.new("exchange", mirror)
		expect(wrong.act(1,"all_call",protocols).damage > 0 and not wrong.completed, "local order causes a failed crossing")
		expect(not wrong.act(1,"ask_early",protocols).clear and wrong.act(1,"agree",protocols,true).is_empty(), "initial script refuses override even when caller passes true")
		expect(play(wrong, plans("exchange",mirror)[0],protocols).clear and wrong.report.size() == 3 and wrong.report[0] != wrong.report[1], "parallel routes preserve three editions")
		var adopt := Rules.new("exchange", mirror)
		expect(play(adopt, [[1,"mute"],[1,"adopt"]], ["Ivory","Cobalt"]).clear and adopt.report[0] == adopt.report[1], "captain can adapt without rewriting NPC copy")
		var dry := Rules.new("airlock", mirror)
		expect(not dry.act(2,"together",protocols).clear, "ward notice cannot override individual practice")
		var relay := Rules.new("relay", mirror)
		expect(relay.act(1,"agree",protocols).is_empty() and relay.act(1,"agree",protocols,true).agree, "evidence/standing gate for expedition-only agreement")
		var bar := Rules.new("shutter", mirror)
		expect(bar.act(2,"early",protocols).damage == 3 and not bar.completed, "red amendment requires pressure work even with the seal")
		expect(play(bar, [[2,"bleed"],[2,"shoe"]],protocols).clear, "failure at the shutter is recoverable")

func _activate(game: Node, predicate: Callable) -> bool:
	var rv: Control = game.room_view
	for t: Dictionary in rv._targets:
		if not predicate.call(t): continue
		if not expect(rv._player != null, "player exists for %s" % game._stage()): return false
		rv._player.spawn_at(t.position)
		await physics_frame
		await physics_frame
		return expect(rv._activate(t), "fixture or exit physically reachable at %s: %s" % [game.current,t.label])
	return expect(false, "matching target in " + game.current)

func _route(game: Node, seed: int, explore: bool) -> void:
	game.new_run(seed)
	expect(game.phase == "camp" and game.current == "camp" and game.moves == 0 and game.modal.is_empty() and game.handbook, "new run starts in Public Hall with its handbook and no mandatory intake")
	expect(game.camp_actors.actors.size() == 16, "camp residents available for recruitment")
	if explore:
		if await _activate(game, func(t): return t.kind == "witness" and t.id == "Ada"):
			game._hall_recruit("Ada")
			game._deploy("Ada")
			game._close()
			expect(game.party.has("Ada"), "camp companion deployed")
	for i in 9:
		if game.phase == "won": break
		var step_index := 0
		if game.current == "turntable" and explore and not game.recalled:
			step_index = game.destinations.find("camp")
		if not expect(step_index >= 0,"return or onward available"): return
		var bag: Dictionary = game.pack.duplicate()
		if not await _activate(game, func(t): return t.kind == "exit" and t.index == step_index): return
		if game.current == "camp":
			expect(game.recalled and game.pack==bag and Array(game.destinations)==["turntable"],"resume without reroll")
			continue
		if game.current == "turntable" and game.recalled:
			expect(not "camp" in game.destinations and game.pack==bag,"no repeat recall or loot")
			continue
		expect(game.destinations.is_empty() and not game.room_view.routes_released,"unresolved room is sealed")
		var r: RefCounted = game._room()
		var plan: Array = plans(r.stage,r.variant)[0]
		var tool: String = "felt" if game.pack.felt>0 else "ratchet"
		if r.stage=="meridian" and game.pack[tool]>0:
			plan = [[1,"felt"],[1,"seal"]] if tool=="felt" else [[0,"docket"],[2,"ratchet"],[2,"wind"]]
		for step: Array in plan:
			if not await _activate(game, func(t): return t.kind == "crossing" and t.index == step[0]): return
			game._act(game.current,step[0],step[1])
			while game._performing: await process_frame
		if not expect(game.cleared.has(game.current) and game.hp == 9, "safe solve: %d/%s" % [seed,r.stage]): return
	if expect(game.phase=="won" and game.moves==(7 if explore else 5),"onward or recall path to dawn"):
		completed_routes += 1

func _test() -> void:
	_logic()
	var game := Main.instantiate()
	root.add_child(game)
	for seed in [1, 2, 25]: await _route(game, seed, seed != 2)
	expect(completed_routes == 3, "all three campaigns must reach the bell")
	game.queue_free()
	await process_frame
	await process_frame
	for reason in errors: push_error(reason)
	if errors.is_empty(): print("Expedition integration passed: camp, recruitment, physical doors, three expeditions, optional single return, inventory and bell.")
	quit(0 if errors.is_empty() else 1)

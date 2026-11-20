extends SceneTree

const Main := preload("res://scenes/rogue/Run.tscn")
const Rules := preload("res://scenes/rogue_crossing/Crossing.gd")
const Cast := preload("res://scenes/rogue_crossing/Roster.gd")
var errors: Array[String] = []

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
	var all_models := {}
	for id in Cast.NAMES + ["detective"]:
		var n := Cast.model_number(id)
		all_models[n] = true
		expect(ResourceLoader.exists("res://assets/characters/UserModels/model_%02d.glb" % n), "restored model %d" % n)
	expect(all_models.size() == 17, "discrete original character meshes")

func _path(house: RefCounted, start: String, to: String) -> Array[String]:
	var q: Array[String] = [start]
	var parent := {start:""}
	for i in 80:
		if i >= q.size(): break
		for next in house.exits(q[i]):
			if parent.has(next): continue
			parent[next] = q[i]
			q.append(next)
	var result: Array[String] = []
	while to != start and parent.has(to):
		result.push_front(to)
		to = parent[to]
	return result

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
	var path := _path(game.house, game.current, game.house.goal_room())
	var schedule := [game.current] + path
	for cell: String in schedule:
		if cell != game.current:
			var index: int = game.destinations.find(cell)
			if not expect(index >= 0, "route step %s -> %s" % [game.current, cell]): return
			if not await _activate(game, func(t): return t.kind == "exit" and t.index == index): return
		var r: RefCounted = game._room()
		expect(not game.room_view._navigation.visible, "watch does not offer remote travel")
		expect(game.room_view._route_hardware.size() == game.house.exits(game.current).size(), "a modeled latch for every graph edge")
		if not game.room_view._route_hardware.is_empty():
			var apparatus: Dictionary = game.room_view._route_hardware[0]
			await physics_frame
			expect(not apparatus.blocker.disabled and not game.room_view.routes_released, "doors physically sealed until crossing succeeds")
		if r.stage == "hall":
			expect(game.party.size() == game.house.recruit_rooms().size() and game.party.size() in [1,2], "meet all seeded survivors before the Hall")
			expect(game.camp_actors != null and game.camp_actors.actors.size() == 16, "all 16 residents retain their own models in Hall")
			if explore:
				for name: String in ["Quer", "Ada"]:
					if await _activate(game, func(t): return t.kind == "witness" and t.id == name): game._close()
		if explore or r.stage == "intake":
			if not await _activate(game, func(t): return t.kind == "crossing" and t.index == 0): return
			game._close()
		var plan: Array = plans(r.stage, r.variant)[1 if not explore else 0]
		if r.stage == "relay" and not explore: plan = plans(r.stage, r.variant)[0]
		if r.stage == "hall": plan = plans(r.stage, r.variant)[1 if explore else 0]
		if r.stage == "relay" and explore:
			expect(game._can_agree(), "witnessed route unlocks genuine agreement after the Hall")
			plan = [[1, "agree"], [1,"mute"],[1,"common"]]
		for step: Array in plan:
			if not await _activate(game, func(t): return t.kind == "crossing" and t.index == step[0]): return
			game._act(game.current, step[0], step[1])
			while game._performing: await process_frame
		if not expect(game.cleared.has(cell) and game.hp == 9, "room cleared safely: %s/%s — %s" % [seed,r.stage,game.message]): return
	expect(game.phase == "won" and game.moves == 10, "all ten thresholds before dawn")

func _test() -> void:
	_logic()
	var game := Main.instantiate()
	root.add_child(game)
	for seed in [1, 2, 25]: await _route(game, seed, seed != 2)
	for reason in errors: push_error(reason)
	if errors.is_empty(): print("Night watch passed: 11 encounters, both variants, two routes per room, disagreements, original cast, Hall and dawn.")
	quit(0 if errors.is_empty() else 1)

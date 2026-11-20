extends SceneTree

const Run := preload("res://scenes/rogue/Run.gd")
const Wing := preload("res://scenes/rogue/SlidingWing.gd")
const Scenes := preload("res://scenes/rogue_rules/NightRules.gd")
var failure := ""

func _initialize() -> void:
	_main.call_deferred()

func check(result: bool, why: String) -> bool:
	if not result and failure.is_empty():
		failure = why
		push_error(why)
	return result

func path(exits: Callable, from: String, to: String) -> Array:
	var back := {from: ""}
	var queue := [from]
	while not queue.is_empty() and not back.has(to):
		var here: String = queue.pop_front()
		for next in exits.call(here):
			if not back.has(next):
				back[next] = here
				queue.append(next)
	var result := []
	if not back.has(to): return result
	var room := to
	while room != from:
		result.push_front(room)
		room = back[room]
	return result

func _board() -> bool:
	var solutions := [[4,7,6,3,4,7], [6,3,4,7,8,5,4,3,6], [8,7,4,3,6], [7,8,5,4,7]]
	for seed in solutions.size():
		var b := Wing.new()
		b.reset(seed)
		if not check(not b.connected() and not b.slide(0) and not b.slide(2), "wing starts unsolved; terminals fixed"): return false
		for tile in solutions[seed]:
			if not check(b.slide(tile), "legal slide rejected"): return false
		if not check(b.connected(), "matching door path required"): return false
		for room in Wing.ROOMS.values():
			for adjacent in b.exits(room):
				if not check(b.exits(adjacent).has(room), "sliding creates one-way exit"): return false
		b.restore()
		if not check(b.tiles == Wing.PATTERNS[seed], "board restore" ): return false
	return true

func _approach(game: Node, seed: int, fatal := false, shortcut := false) -> bool:
	game.new_run(seed)
	if not check(game.reading and game.party.is_empty() and game.mcp_observe().player_observation.perspective == "first_person", "start alone, with opening card and first-person camera"): return false
	game._close_sheet()
	var route := path(game.house.exits, game.house.start_room(), game.house.camp_room())
	if not check(route.size() >= 10 and route.size() <= 20, "approach budget"): return false
	var encountered := {}
	var survivors := {}
	for target in route:
		game.travel(game.destinations.find(target))
		await physics_frame
		if not check(game.current == target, "failed to travel to " + target): return false
		if target == game.house.camp_room(): break
		game._inspect()
		var e: Dictionary = game._event()
		var stage: String = game._stage()
		if not stage.is_empty(): encountered[stage] = true
		if stage == "rain":
			var room: Node = game.room_view
			if not check(room._lanes.size() == 2 and room._lanes[0].distance_to(room._lanes[1]) > 0.68, "two spatial rain routes"): return false
			game.resolve(0)
			if not check(not game.cleared.has(target), "rain cannot be solved remotely"): return false
			room._player.spawn_at(room._lanes[1])
			var before: int = game.stability
			game._process(1.1)
			if not check(game.stability < before, "red lane exposes the player to time rain"): return false
			room._player.spawn_at(room._lanes[0])
			game._process(1.5)
		if stage == "rewrite" and fatal and not game._variant():
			game.resolve(1)
			if not check(game.ended and game.phase == "lost", "false red amendment must be lethal"): return false
			game._legacy_sheet()
			game._legacy_input.text = "My warning: check both seals before crossing."
			game._edit_note("replace")
			game._edit_note("erase")
			if not check(game.notes.size() == 1 and game.notes[0] == "My warning: check both seals before crossing.", "only one legacy change per death"): return false
			game.new_run(seed)
			return check(game.notes[0] == "My warning: check both seals before crossing.", "legacy retained on restart")
		if stage == "rewrite" and shortcut and game._variant():
			var crates: int = game.crew.supplies
			game.resolve(1)
			if not check(game.crew.supplies == crates + 3 and game.hp == 9, "supported red amendment is the better outcome"): return false
		else: game.resolve(e.safe)
		if not check(game.cleared.has(target) and game.hp == 9, "printed rules must survive room " + target): return false
		var survivor: String = game._field_candidate()
		if not survivor.is_empty():
			survivors[survivor] = true
			if not check(not game.roster.has(survivor) and not game.party.has(survivor), "encounter does not auto-enlist"): return false
			if seed % 2 == 0: game._invite_field(survivor)
	if not check(encountered.size() == 3 and survivors.size() in [1, 2] and game.phase == "camp" and game.party.size() == game.roster.size() and game.camp_ready, "enter hall without forced recruitment"): return false
	if not check(game.party.size() in [1, 2] if seed % 2 == 0 else game.party.is_empty(), "1–2 optional pre-hall recruits"): return false
	game._team_info()
	var field_count: int = game.party.size()
	for id in ["Mara", "Elias", "June", "Rowan"]: game._invite_hall(id)
	game._invite_hall("Mara")
	game._close_sheet()
	return check(game.roster.size() == 4 and game.party.size() == field_count, "hall recruiting is idempotent and never auto-deploys")

func _main() -> void:
	if not _board():
		quit(1)
		return
	var game := Run.new()
	root.add_child(game)
	game.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var tested_fatal := false
	var tested_shortcut := false
	for seed in range(12):
		if not await _approach(game, seed, false, true):
			quit(1)
			return
		for id in path(game.house.exits, game.house.start_room(), game.house.camp_room()):
			if game.house.room_stage(id) != "rewrite": continue
			if Scenes.truth(seed, id, "rewrite"): tested_shortcut = true
			elif not tested_fatal:
				if not await _approach(game, seed, true):
					quit(1)
					return
				tested_fatal = true
	if not check(tested_shortcut and tested_fatal, "both outcomes executed") or not await _approach(game, 0):
		quit(1)
		return
	game._build("Infirmary")
	game._close_sheet()
	var original: String = game.wing.tiles
	for i in [4,7,6,3,4,7]: game._slide(i)
	game._close_sheet()
	if not check(game.wing.tiles != original and game.wing.connected(), "UI slide sequence changes physical links"):
		quit(1)
		return
	var folding_route := path(game.wing.exits, "camp", "observatory")
	var next_room: String = folding_route[0]
	game.travel(game.destinations.find(next_room))
	await physics_frame
	game._inspect()
	var member: String = game.party.back()
	game._betray(member)
	if not check(game.crew.people[member].trust == 0 and not game.crew.deployable(member) and not game.party.has(member), "betrayal injures and removes deployed companion"):
		quit(1)
		return
	game.travel(game.destinations.find("camp"))
	game._process(19.0)
	if not check(game.crew.deployable(member) and not game.crew.willing(member), "clinic heals but does not restore trust"):
		quit(1)
		return
	for id in folding_route:
		game.travel(game.destinations.find(id))
		await physics_frame
		if game.current != "observatory" and not game.cleared.has(game.current):
			game._inspect()
			game.resolve(game._event().safe)
	game._finish()
	if not check(game.phase == "won", "observable expedition win through physical sliding wing"):
		quit(1)
		return
	print("Night expedition passed: 12 seed approaches, rain lanes, both amendments, inherited rule, wing/crew and completion.")
	quit(0)

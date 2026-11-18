extends SceneTree

const FIELD_DESIGNS := ["kitchen", "lecture", "clinic", "dining", "valve_gallery", "service_stair"]
const HOUSE_MAP = preload("res://scenes/rogue/HouseMap.cs")

func _initialize() -> void:
	var error := _test_bridge()
	if not error.is_empty():
		push_error(error)
		quit(1)
		return
	quit(0)

func _test_bridge() -> String:
	var house = HOUSE_MAP.new()
	if not house is RefCounted or house.start_room() != "" or house.camp_room() != "" \
			or house.goal_room() != "" or not house.exits("foyer").is_empty() or not house.recruit_rooms().is_empty():
		return "Unexpected bridge state before generate"
	var graphs := {}
	var approach_graphs := {}
	var expedition_graphs := {}
	var arrivals := {}
	var recruit_counts := {}
	var goal_designs := {}
	var doubled_layer_edge_counts := {}
	var max_before_camp := 0
	var seeds: Array[int] = [-9223372036854775807 - 1, -1, 9223372036854775807]
	for seed in range(2048):
		seeds.append(seed)
		seeds.append(-((seed + 1) << 40) + seed)
	for seed in seeds:
		if not house.generate(seed):
			return "Cannot generate seed %d" % seed
		var start: String = house.start_room()
		var camp: String = house.camp_room()
		var goal: String = house.goal_room()
		if [start, camp, goal] != ["foyer", "camp", "observatory"]:
			return "Wrong endpoint IDs at seed %d" % seed
		if not house.exits("unknown").is_empty() or house.template_id("unknown") != "":
			return "Unexpected results for unknown room"
		if house.template_id(start) != "foyer" or house.template_id(camp) != "living_hall" \
				or house.template_id(goal) not in ["lecture", "valve_gallery"]:
			return "Unexpected endpoint design at seed %d" % seed
		goal_designs[house.template_id(goal)] = true
		var full := _distances(house, start)
		var before := _distances(house, start, camp)
		var after := _distances(house, goal, camp)
		var arrival: int = full.get(camp, -1) + 1 # Count both start and camp.
		if arrival < 10 or arrival > 20 or before.size() + 1 > 20:
			return "Camp depth/budget mismatch at seed %d" % seed
		if after.size() < 4 or before.has(goal) or before.size() + after.size() + 1 != full.size():
			return "Expedition must be reachable only through camp at seed %d" % seed
		if typeof(house.recruit_rooms()) != TYPE_PACKED_STRING_ARRAY:
			return "recruit_rooms() must return PackedStringArray"
		var recruits: PackedStringArray = house.recruit_rooms()
		if recruits.size() < 1 or recruits.size() > 2:
			return "Wrong recruitment count at seed %d" % seed
		var previous_depth := 0
		for room in recruits:
			if not before.has(room) or before[room] <= previous_depth:
				return "Recruit rooms must be distinct, after the start, and in encounter order at seed %d" % seed
			previous_depth = before[room]
			if _distances(house, start, room).has(camp):
				return "Camp can bypass recruit %s at seed %d" % [room, seed]
		var approach_designs := {}
		var expedition_designs := {}
		var branched := false
		var widths := {}
		var forward_edges := {}
		for room in full:
			if house.template_id(room).is_empty() or typeof(house.exits(room)) != TYPE_PACKED_STRING_ARRAY:
				return "Wrong template or exit type at %s" % room
			if room not in [start, camp, goal]:
				var design: String = house.template_id(room)
				if design not in FIELD_DESIGNS:
					return "Unexpected room design %s at seed %d" % [design, seed]
				if before.has(room):
					approach_designs[design] = true
				else:
					expedition_designs[design] = true
			var depth: int = full[room]
			widths[depth] = widths.get(depth, 0) + 1
			var listed := {}
			var forward_count := 0
			for other in house.exits(room):
				if other == room or listed.has(other) or not house.exits(other).has(room):
					return "Invalid exit %s -> %s" % [room, other]
				listed[other] = true
				if absi(full[other] - depth) != 1:
					return "Exit skipped a depth at seed %d: %s -> %s" % [seed, room, other]
				if full[other] > depth:
					forward_edges[depth] = forward_edges.get(depth, 0) + 1
					if before.has(other):
						forward_count += 1
			branched = branched or forward_count > 1
		if approach_designs.size() != FIELD_DESIGNS.size() \
				or expedition_designs.size() != mini(after.size() - 1, FIELD_DESIGNS.size()):
			return "Room design variety regressed at seed %d" % seed
		if not branched:
			return "Approach must have a forward branch at seed %d" % seed
		for depth in widths:
			if widths[depth] == 2 and widths.get(depth + 1, 0) == 2:
				doubled_layer_edge_counts[forward_edges.get(depth, 0)] = true
		var graph := _key(house, full)
		var replay = HOUSE_MAP.new()
		if not replay.generate(seed) or replay.recruit_rooms() != recruits \
				or _key(replay, _distances(replay, start)) != graph:
			return "Seed replay diverged at %d" % seed
		for room in full:
			if replay.template_id(room) != house.template_id(room):
				return "Template replay diverged at seed %d" % seed
		graphs[graph] = true
		approach_graphs[_key(house, before)] = true
		expedition_graphs[_key(house, after)] = true
		arrivals[arrival] = true
		recruit_counts[recruits.size()] = true
		max_before_camp = maxi(max_before_camp, before.size() + 1)
	if approach_graphs.size() < 16 or expedition_graphs.size() < 16 or arrivals.size() < 5 \
			or not recruit_counts.has(1) or not recruit_counts.has(2):
		return "Too little seeded variety in topology, arrival depth, or recruit count"
	if goal_designs.size() != 2:
		return "Expected both goal designs across stress seeds"
	# The same allowed 2×2 adjacency shape must collapse to sparse and dense door sets.
	if doubled_layer_edge_counts.size() != 3 or not doubled_layer_edge_counts.has(2) \
			or not doubled_layer_edge_counts.has(3) or not doubled_layer_edge_counts.has(4):
		return "Expected distinct 2×2 door collapses, got %s" % [doubled_layer_edge_counts.keys()]
	print("2×2 layers collapsed to 2, 3 and 4 open doors across the stress seeds.")
	var arrival_values := arrivals.keys()
	arrival_values.sort()
	print("HouseMap bridge passed: %d seeds, %d graphs (%d approach, %d expedition); camp arrival %d–%d, explored through camp max %d" % [
		seeds.size(), graphs.size(), approach_graphs.size(), expedition_graphs.size(), arrival_values.front(), arrival_values.back(), max_before_camp])
	return ""

func _distances(house: RefCounted, root: String, blocked: String = "") -> Dictionary:
	var distances := {root: 0}
	var queue: Array[String] = [root]
	var cursor := 0
	while cursor < queue.size():
		var room := queue[cursor]
		cursor += 1
		for other in house.exits(room):
			if other != blocked and not distances.has(other):
				distances[other] = distances[room] + 1
				queue.append(other)
	return distances

func _key(house: RefCounted, rooms: Dictionary) -> String:
	var ids := rooms.keys()
	ids.sort()
	var rows := PackedStringArray()
	for room in ids:
		rows.append(room + ":" + ",".join(house.exits(room)))
	return "|".join(rows)

extends RefCounted
## Seeded single-storey plan using the existing blueprint wire format.
const GRID_WIDTH := 2.4
const DOOR_WIDTH := 1.15

static func build(seed_value: int, pairs: int) -> Dictionary:
	if pairs < 1 or pairs > 4: return {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var left := -GRID_WIDTH * 0.5
	var right := GRID_WIDTH * 0.5
	var outer_left := left - float(rng.randi_range(64, 90)) * 0.05
	var outer_right := right + float(rng.randi_range(64, 90)) * 0.05
	var breaks: Array[float] = [0.0]
	for i in range(pairs): breaks.append(breaks[-1] + float(rng.randi_range(64, 96)) * 0.05)
	var total := breaks[-1]
	var doors: Array = []
	for i in range(pairs): doors.append(door("hall_door_%d" % i, (breaks[i] + breaks[i + 1]) * 0.5))
	var right_doors: Array = doors.duplicate(true)
	for op in right_doors: op.id += "_right"
	var walls := [
		wall("plan_shell", [[outer_left, 0.0, 0.0], [outer_right, 0.0, 0.0], [outer_right, 0.0, total],
			[outer_left, 0.0, total], [outer_left, 0.0, 0.0]], [door("plan_entry", -outer_left)], true),
		wall("plan_hall_left", [[left, 0.0, 0.0], [left, 0.0, total]], doors),
		wall("plan_hall_right", [[right, 0.0, 0.0], [right, 0.0, total]], right_doors)]
	for i in range(1, pairs):
		var z := breaks[i]
		walls.append(wall("plan_left_%d" % i, [[outer_left, 0.0, z], [left, 0.0, z]], []))
		walls.append(wall("plan_right_%d" % i, [[right, 0.0, z], [outer_right, 0.0, z]], []))
	return {"activeLayerId": "plan_ground", "layers": [{"id": "plan_ground", "name": "Ground floor", "y": 0.0,
		"style": "plain_grout", "polygons": []}], "walls": walls, "stairs": [], "railings": [], "props": []}

static func door(id: String, at: float) -> Dictionary:
	return {"id": id, "segment": 0, "center": at, "width": DOOR_WIDTH, "height": 2.25, "bottom": 0.0, "type": "portal_arch"}

static func wall(id: String, points: Array, openings: Array, closed := false) -> Dictionary:
	return {"id": id, "name": id.replace("_", " ").capitalize(), "height": 3.2, "thickness": 0.24,
		"baseY": 0.0, "style": "classical", "points": points, "openings": openings, "closed": closed}

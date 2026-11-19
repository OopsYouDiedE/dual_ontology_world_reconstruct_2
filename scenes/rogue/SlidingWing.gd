extends RefCounted
## Fixed terminals occupy the top corners. Only touching, opposing door ports connect.
const PATTERNS := ["C_Gdecbaf", "CdGabec_f", "CfGbe_adc", "CfGbcd_ea"]
const PORTS := {"C": 6, "G": 12, "a": 3, "b": 10, "c": 9, "d": 5, "e": 6, "f": 12, "_": 0}
const ROOMS := {"C": "camp", "G": "observatory", "a": "fold_archive", "b": "fold_pump", "c": "fold_stair", "d": "fold_clinic", "e": "fold_kitchen", "f": "fold_lecture"}
const TEMPLATES := {"fold_archive": "dining", "fold_pump": "valve_gallery", "fold_stair": "service_stair", "fold_clinic": "clinic", "fold_kitchen": "kitchen", "fold_lecture": "lecture"}
const LEGEND := {"C": "HALL · ES", "G": "GATE · SW", "a": "Archive · NE", "b": "Pump · EW", "c": "Stair · NW", "d": "Clinic · NS", "e": "Kitchen · ES", "f": "Lecture · SW", "_": "EMPTY"}
const STEPS := [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
var tiles := ""
var _initial := ""

func reset(seed_value: int) -> void:
	_initial = PATTERNS[posmod(seed_value, PATTERNS.size())]
	tiles = _initial

func restore() -> void:
	tiles = _initial

func can_slide(index: int) -> bool:
	if index < 0 or index >= tiles.length() or tiles[index] in ["C", "G", "_"]: return false
	return _cell(index).distance_squared_to(_cell(tiles.find("_"))) == 1

func slide(index: int) -> bool:
	if not can_slide(index): return false
	var empty := tiles.find("_")
	var next := tiles.split("")
	next[empty] = next[index]
	next[index] = "_"
	tiles = "".join(next)
	return true

func exits(room: String) -> Array[String]:
	var exits_found: Array[String] = []
	var id: Variant = ROOMS.find_key(room)
	if id == null or tiles.is_empty(): return exits_found
	var index := tiles.find(id)
	for dir in STEPS.size():
		var dest: Vector2i = _cell(index) + STEPS[dir]
		if dest.x < 0 or dest.y < 0 or dest.x >= 3 or dest.y >= 3: continue
		var next := tiles[dest.y * 3 + dest.x]
		if (PORTS[id] & (1 << dir)) != 0 and (PORTS[next] & (1 << ((dir + 2) % 4))) != 0:
			exits_found.append(ROOMS[next])
	return exits_found

func connected() -> bool:
	var seen := {"camp": true}
	var queue: Array[String] = ["camp"]
	while not queue.is_empty():
		var room: String = queue.pop_front()
		if room == "observatory": return true
		for next in exits(room):
			if not seen.has(next):
				seen[next] = true
				queue.append(next)
	return false

static func _cell(index: int) -> Vector2i:
	@warning_ignore("integer_division")
	return Vector2i(index % 3, index / 3)

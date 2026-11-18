extends RefCounted
## Translation from native wall bits and LotTilePos units to view coordinates.

const VMContract := preload("res://tools/freeso_bridge/LotSnapshot.gd")
const MAX_SIDE := 128
const MAX_BYTES := 8 * 1024 * 1024
# FreeSO WallSegments (XmlHouse.cs); facing from WallComponentRC.cs.
const EDGES := {
	1: Vector4i(0, 0, 0, 1), # TopLeft
	2: Vector4i(0, 0, 1, 0), # TopRight
	4: Vector4i(1, 0, 1, 1), # BottomRight
	8: Vector4i(0, 1, 1, 1), # BottomLeft
	16: Vector4i(0, 1, 1, 0), # HorizontalDiag
	32: Vector4i(0, 0, 1, 1), # VerticalDiag
}


static func read_file(path: String, level: int) -> Dictionary:
	if path.is_empty():
		return _failure(ERR_FILE_NOT_FOUND)
	var input := FileAccess.open(path, FileAccess.READ)
	if input == null:
		return _failure(FileAccess.get_open_error())
	if input.get_length() > MAX_BYTES:
		return _failure(ERR_FILE_CORRUPT)
	var json := JSON.new()
	if json.parse(input.get_as_text()) != OK or not json.data is Dictionary:
		return _failure(ERR_PARSE_ERROR)
	return decode(json.data, level)


static func decode(snapshot: Dictionary, level: int) -> Dictionary:
	if snapshot.get("schema") != VMContract.SCHEMA:
		return _failure(ERR_FILE_UNRECOGNIZED)
	var source: Variant = snapshot.get("source")
	if not source is Dictionary or source.get("kind") not in ["fsov", "live-vm"]:
		return _failure(ERR_INVALID_DATA)
	if VMContract.validate(snapshot).has("error"):
		return _failure(ERR_INVALID_DATA)
	var lot: Dictionary = snapshot.lot
	var width := int(lot.width)
	var height := int(lot.height)
	var stories := int(lot.stories)
	if width > MAX_SIDE or height > MAX_SIDE or stories > 127:
		return _failure(ERR_INVALID_DATA)
	if level < 1 or level > stories:
		return _failure(ERR_PARAMETER_RANGE_ERROR)
	var unique_edges := {}
	for wall: Dictionary in lot.walls:
		if int(wall.mask) > 63:
			return _failure(ERR_INVALID_DATA)
		if int(wall.level) != level:
			continue
		var x := int(wall.x)
		var y := int(wall.y)
		var mask := int(wall.mask)
		for bit: int in EDGES:
			if mask & bit:
				var edge: Vector4i = EDGES[bit] + Vector4i(x, y, x, y)
				unique_edges[edge] = true
	var floors: Array[Vector2i] = []
	for cell: Dictionary in lot.floors:
		if int(cell.level) == level and int(cell.pattern) != 0:
			floors.append(Vector2i(int(cell.x), int(cell.y)))
	var positions := PackedVector2Array()
	for avatar: Dictionary in snapshot.avatars:
		if not avatar.placed or int(avatar.level) != level:
			continue
		var position := VMContract.avatar_position(avatar)
		positions.append(Vector2(position.x, position.z))
	return {"error": OK, "lot": {"width": width, "height": height, "segments": unique_edges.keys(), "floors": floors, "avatars": positions}}


static func _failure(error: Error) -> Dictionary:
	return {"error": error}

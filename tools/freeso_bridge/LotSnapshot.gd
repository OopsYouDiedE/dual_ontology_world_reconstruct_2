extends RefCounted
## Read-only projection of the native FreeSO VM snapshot. No fallback geography.

const SCHEMA := "freeso.lot-snapshot.v1"
const STORY_HEIGHT := 2.95 # FreeSO LotTilePos.ToVector3()

static func read_file(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"error": "Cannot open FreeSO snapshot JSON: " + path}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return {"error": "Invalid FreeSO snapshot JSON: " + parser.get_error_message()}
	return validate(parser.data)

static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary or value.get("schema") != SCHEMA:
		return {"error": "Expected " + SCHEMA}
	var lot: Variant = value.get("lot")
	if not lot is Dictionary or not value.get("avatars") is Array:
		return {"error": "Snapshot is missing its lot or avatar list."}
	for key in ["width", "height", "stories"]:
		if not _integer(lot.get(key)) or lot[key] < 1:
			return {"error": "Invalid lot dimension: " + key}
	for key in ["walls", "floors"]:
		if not lot.get(key) is Array:
			return {"error": "Missing " + key}
		for tile in lot[key]:
			if not tile is Dictionary or not _cell(tile, lot):
				return {"error": "Invalid coordinate in " + key}
			var id: Variant = tile.get("mask" if key == "walls" else "pattern")
			if not _integer(id) or id <= 0 or id > (255 if key == "walls" else 65535):
				return {"error": "Invalid native tile value in " + key}
	for avatar in value.avatars:
		if not avatar is Dictionary or not avatar.get("placed") is bool:
			return {"error": "Invalid avatar entry."}
		for key in ["object_id", "x16", "y16", "level"]:
			if not _integer(avatar.get(key)):
				return {"error": "Invalid avatar field: " + key}
		if avatar.placed and not _cell({"x": floori(avatar.x16 / 16.0), "y": floori(avatar.y16 / 16.0), "level": avatar.level}, lot):
			return {"error": "Placed avatar is outside the lot."}
	return {"snapshot": value}

static func avatar_position(avatar: Dictionary) -> Vector3:
	assert(avatar.placed, "Skip avatars marked unplaced.")
	return Vector3(avatar.x16 / 16.0, (avatar.level - 1) * STORY_HEIGHT, avatar.y16 / 16.0)

static func _cell(cell: Dictionary, lot: Dictionary) -> bool:
	for key in ["x", "y", "level"]:
		if not _integer(cell.get(key)):
			return false
	return cell.x >= 0 and cell.x < lot.width and cell.y >= 0 and cell.y < lot.height and cell.level >= 1 and cell.level <= lot.stories

static func _integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))

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
	if value.has("objects"):
		if not value.objects is Array:
			return {"error": "Invalid native object list."}
		var seen := {}
		for obj in value.objects:
			if not obj is Dictionary or not obj.get("placed") is bool or not obj.get("hidden") is bool:
				return {"error": "Invalid native object entry."}
			for key in ["object_id", "persist_id", "guid", "master_guid", "x16", "y16", "level", "direction", "container_object_id"]:
				if not _integer(obj.get(key)):
					return {"error": "Invalid native object field: " + key}
			for key in ["persist_id", "guid", "master_guid"]:
				if obj[key] < 0 or obj[key] > 4294967295:
					return {"error": "Invalid native unsigned ID: " + key}
			if obj.direction < 0 or obj.direction > 255 or seen.has(obj.object_id):
				return {"error": "Invalid native object direction or duplicate ID."}
			seen[obj.object_id] = true
			if obj.get("name") != null and not obj.name is String:
				return {"error": "Invalid native object name."}
			for key in ["group_id", "group_base_object_id"]:
				if obj.get(key) != null and not _integer(obj[key]):
					return {"error": "Invalid native object group field: " + key}
			var heading: Variant = obj.get("heading_radians")
			if heading != null and (not (heading is int or heading is float) or not is_finite(heading)):
				return {"error": "Invalid native object heading."}
			if obj.placed and not _cell({"x": floori(obj.x16 / 16.0), "y": floori(obj.y16 / 16.0), "level": obj.level}, lot):
				return {"error": "Placed object is outside the lot."}
	return {"snapshot": value}

static func avatar_position(avatar: Dictionary) -> Vector3:
	assert(avatar.placed, "Skip avatars marked unplaced.")
	return Vector3(avatar.x16 / 16.0, (avatar.level - 1) * STORY_HEIGHT, avatar.y16 / 16.0)

static func object_position(obj: Dictionary) -> Vector3:
	assert(obj.placed, "Skip objects marked unplaced.")
	return Vector3(obj.x16 / 16.0, (obj.level - 1) * STORY_HEIGHT, obj.y16 / 16.0)

## Godot yaw for a mesh pointing along -Z at zero rotation. Null means unknown.
static func object_yaw(obj: Dictionary) -> Variant:
	var heading: Variant = obj.get("heading_radians")
	return null if heading == null else -float(heading)

static func _cell(cell: Dictionary, lot: Dictionary) -> bool:
	for key in ["x", "y", "level"]:
		if not _integer(cell.get(key)):
			return false
	return cell.x >= 0 and cell.x < lot.width and cell.y >= 0 and cell.y < lot.height and cell.level >= 1 and cell.level <= lot.stories

static func _integer(value: Variant) -> bool:
	return value is int or (value is float and is_finite(value) and value == floor(value))

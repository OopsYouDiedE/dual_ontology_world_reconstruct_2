extends RefCounted

const ARCHIVE := "res://assets/data/room_art.zip"
static var cache_path := ""
static var room_ids: Array[String] = []

static func prepare() -> bool:
	if not cache_path.is_empty(): return true
	var archive := ZIPReader.new()
	if archive.open(ARCHIVE) != OK:
		push_error("无法打开房间资源目录")
		return false
	var destination := "user://room-art/" + FileAccess.get_sha256(ARCHIVE) + "/"
	for path in archive.get_files():
		if not path.begins_with("scenes/") or ".." in path or not path.ends_with(".tscn"):
			archive.close()
			push_error("房间目录包含无效路径")
			return false
		var target := destination + path
		if not FileAccess.file_exists(target):
			var source := archive.read_file(path).get_string_from_utf8()
			source = source.replace("res://scenes/rooms/", destination + "scenes/rooms/")
			source = source.replace("res://scenes/prefabs/", destination + "scenes/prefabs/")
			DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(target.get_base_dir()))
			var file := FileAccess.open(target, FileAccess.WRITE)
			if file == null:
				archive.close()
				push_error("房间缓存写入失败：" + target)
				return false
			file.store_string(source)
		if path.begins_with("scenes/rooms/"): room_ids.append(path.get_file().get_basename())
	archive.close()
	room_ids.sort()
	cache_path = destination
	return true

static func rooms() -> Array[String]:
	if not prepare(): return []
	return room_ids.duplicate()

static func instantiate(identity: String) -> Node3D:
	if not prepare() or not identity in room_ids: return null
	var scene := load(cache_path + "scenes/rooms/" + identity + ".tscn") as PackedScene
	return scene.instantiate() as Node3D if scene != null else null

static func available(identity: String) -> bool:
	return prepare() and identity in room_ids

static func catalog() -> Array[String]:
	return rooms()

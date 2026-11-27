extends RefCounted
## Persistent Watch progress and inherited margin note storage.

const MARGINS := "user://night_watch_margins.txt"
const FIRST_SEAL := "user://expedition_01_returned"

var no_save := false

func _init(disable_save := false) -> void:
	no_save = disable_save

func load_margins() -> String:
	if no_save or not FileAccess.file_exists(MARGINS):
		return ""
	return FileAccess.get_file_as_string(MARGINS).left(180)

func save_margins(text: String) -> void:
	if no_save:
		return
	var file := FileAccess.open(MARGINS, FileAccess.WRITE)
	if file:
		file.store_string(text)

func has_first_seal() -> bool:
	return not no_save and FileAccess.file_exists(FIRST_SEAL)

func mark_first_seal() -> void:
	if no_save:
		return
	var file := FileAccess.open(FIRST_SEAL, FileAccess.WRITE)
	if file:
		file.store_line("Source recovered")

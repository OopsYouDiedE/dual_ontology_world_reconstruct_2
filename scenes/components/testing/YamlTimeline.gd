extends RefCounted
## Streaming YAML 1.2 reports; JSON quoting keeps timestamps, Unicode and null unambiguous.
var file: FileAccess
var path := ""
var error := ""

static func encode(value: Variant, indent := 0) -> String:
	var pad := " ".repeat(indent)
	if value is Dictionary:
		if value.is_empty(): return pad + "{}\n"
		var result := ""
		for key in value:
			var item: Variant = value[key]
			result += pad + JSON.stringify(str(key)) + ":"
			if (item is Dictionary or item is Array) and not item.is_empty():
				result += "\n" + encode(item, indent + 2)
			else:
				result += " " + JSON.stringify(item) + "\n"
		return result
	if value is Array:
		if value.is_empty(): return pad + "[]\n"
		var result := ""
		for item in value:
			result += pad + "- " + JSON.stringify(item) + "\n"
		return result
	return pad + JSON.stringify(value) + "\n"

func begin(destination: String, metadata: Dictionary) -> bool:
	path = preload("res://mcp/CaptureSource.gd").project_output(destination)
	if path.is_empty():
		error = "Invalid report output path"
		return false
	var directory := path.get_base_dir()
	if DirAccess.make_dir_recursive_absolute(directory) != OK:
		error = "Cannot create report directory: " + directory
		return false
	file = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		error = "Cannot open report: " + error_string(FileAccess.get_open_error())
		return false
	file.store_string(encode({"schema_version": 1, "metadata": metadata}) + "timeline:\n")
	file.flush()
	return true

func append(sample: Dictionary) -> void:
	if file == null: return
	file.store_string("  - " + JSON.stringify(sample) + "\n")
	file.flush()

func finish(summary: Dictionary) -> void:
	if file == null: return
	file.store_string(encode({"summary": summary}))
	file.flush()
	file.close()
	file = null

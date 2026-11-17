extends RefCounted
## Shared PNG persistence for project tools. Fixture captures retain their origin.
const Source := preload("res://mcp/CaptureSource.gd")

static func save(image: Image, output: String, tree: SceneTree, kind := "development-fixture") -> bool:
	if image == null or image.is_empty():
		push_error("Capture has no rendered image")
		return false
	# Absolute paths are permitted only inside this project; never escape the root.
	var path := Source.project_output(output)
	if path.is_empty(): return false
	var error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if error != OK:
		push_error("Cannot create capture directory: " + path.get_base_dir())
		return false
	error = image.save_png(path)
	if error != OK:
		push_error("Cannot save capture PNG: " + path + " (" + str(error) + ")")
		return false
	var scene_paths: Array[String] = []
	for child in tree.root.get_children():
		if not child.scene_file_path.is_empty(): scene_paths.append(child.scene_file_path)
	var metadata := {
		"source_identity": Source.identity(tree), "capture_kind": kind,
		"entry_script": tree.get_script().resource_path if tree.get_script() != null else "",
		"loaded_scenes": scene_paths, "engine_time_scale": Engine.time_scale,
		"captured_local": Time.get_datetime_string_from_system(false, true),
		"image_path": path, "image_sha256": FileAccess.get_sha256(path),
		"acceptance_eligible": false,
	}
	var receipt := FileAccess.open(path + ".json", FileAccess.WRITE)
	if receipt == null:
		push_error("Cannot write capture source receipt: " + path)
		return false
	receipt.store_string(JSON.stringify(metadata, "  "))
	receipt.close()
	print("CAPTURE ", path)
	return true

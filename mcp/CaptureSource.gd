extends RefCounted
## Read-only provenance of the host that rendered an image.

static func identity(tree: SceneTree, launch_scene := "") -> Dictionary:
	var scene := tree.current_scene
	return {
		"project_root": ProjectSettings.globalize_path("res://").trim_suffix("/"),
		"project_sha256": FileAccess.get_sha256("res://project.godot"),
		"configured_main_scene": str(ProjectSettings.get_setting("application/run/main_scene", "")),
		"current_scene": scene.scene_file_path if scene != null else "",
		"launch_scene": launch_scene,
		"process_id": OS.get_process_id(),
		"executable_path": OS.get_executable_path(),
	}

static func project_output(path: String) -> String:
	var normalized := path.replace("\\", "/")
	if normalized.begins_with("user://"):
		push_error("Capture output must use a project path or an explicit absolute path")
		return ""
	var project := ProjectSettings.globalize_path("res://").simplify_path().trim_suffix("/")
	if project.get_file() != "dual_ontology_world_reconstruct_2" or not FileAccess.file_exists(project.path_join("project.godot")):
		push_error("Capture host is not the authorized named project")
		return ""
	var absolute := ProjectSettings.globalize_path(normalized if normalized.begins_with("res://") or normalized.is_absolute_path() else "res://" + normalized).simplify_path()
	var compare_project := project.to_lower() if OS.get_name() == "Windows" else project
	var compare_path := absolute.to_lower() if OS.get_name() == "Windows" else absolute
	if compare_path != compare_project and not compare_path.begins_with(compare_project + "/"):
		push_error("Capture output escaped the project: " + absolute)
		return ""
	if OS.get_name() == "Windows" and absolute.begins_with("/"):
		push_error("Capture output needs an explicit Windows drive: " + absolute)
		return ""
	# Do not follow project-internal links at a capture/snapshot boundary: an
	# apparently local output could otherwise redirect into a different project.
	var relative := absolute.substr(project.length()).trim_prefix("/")
	var parent := project
	for part in relative.split("/", false):
		var directory := DirAccess.open(parent)
		if directory != null and directory.is_link(part):
			push_error("Capture output cannot traverse a symbolic link: " + parent.path_join(part))
			return ""
		parent = parent.path_join(part)
	return absolute

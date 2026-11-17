extends SceneTree
## File-output regression only. These synthetic pixels are never gameplay evidence.
const Receipt := preload("res://mcp/CaptureReceipt.gd")
const Source := preload("res://mcp/CaptureSource.gd")

func _initialize() -> void:
	var image := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.4, 0.6, 1.0))
	var expected := ProjectSettings.globalize_path("res://.runtime/capture-path-regression/nested/proof.png")
	for output in [".runtime/capture-path-regression/nested/proof.png", "res://.runtime/capture-path-regression/nested/proof.png", expected]:
		if not Receipt.save(image, output, self, "synthetic-file-output-regression"):
			quit(1)
			return
		if Source.project_output(output) != expected:
			push_error("Capture output resolved against the wrong working directory")
			quit(1)
			return
	var metadata = JSON.parse_string(FileAccess.get_file_as_string(expected + ".json"))
	if not metadata is Dictionary or metadata.get("image_sha256") != FileAccess.get_sha256(expected) or metadata.get("acceptance_eligible") != false:
		push_error("Capture source receipt is invalid")
		quit(1)
		return
	# The guard emits expected ERROR diagnostics for rejected paths; the runner
	# verifies those separately. No external file is opened or written.
	var forbidden := ProjectSettings.globalize_path("res://").trim_suffix("/").get_base_dir().path_join("__evaluation_forbidden_output__.png")
	if not Source.project_output(forbidden).is_empty() or Receipt.save(image, forbidden, self):
		push_error("External absolute capture path was incorrectly authorized")
		quit(1)
		return
	var directory := DirAccess.open("res://.runtime/capture-path-regression")
	if directory != null and directory.is_link("outside-link"):
		if not Source.project_output("res://.runtime/capture-path-regression/outside-link/sentinel.png").is_empty():
			push_error("Symlink capture escape was incorrectly authorized")
			quit(1)
			return
		print("PASS symbolic-link path rejected")
	print("PASS relative, res://, absolute project paths; external paths rejected; SHA256 sidecar; fixture exclusion")
	quit()

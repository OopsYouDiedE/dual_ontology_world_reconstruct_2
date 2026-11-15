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
	print("PASS relative, res://, absolute paths; nested output; SHA256 sidecar; fixture exclusion")
	quit()

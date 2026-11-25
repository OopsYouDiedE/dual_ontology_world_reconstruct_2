extends Node
## Opt-in testing bridge. Normal game launches leave it dormant.

const TEST_SCENES := [
	"res://tools/research/french_gothic_nodes/InteriorFlight.tscn",
	"res://tools/research/french_gothic_nodes/WholeReview.tscn",
	"res://tools/research/french_gothic_nodes/BayReview.tscn",
	"res://scenes/expedition_01/Expedition.tscn",
	"res://scenes/physics_lab/airlock/Airlock.tscn",
	"res://scenes/physics_lab/Lab.tscn",
	"res://scenes/physics_lab/chronograph/Chronograph.tscn",
	"res://scenes/physics_lab/evidence_register/EvidenceRegister.tscn",
	"res://scenes/physics_lab/palimpsest/Palimpsest.tscn",
	"res://scenes/physics_lab/shutter_loom/ShutterLoom.tscn",
	"res://scenes/physics_lab/afterimage/Afterimage.tscn",
	"res://scenes/physics_lab/duet/Duet.tscn",
	"res://scenes/physics_lab/strata/Strata.tscn",
	"res://scenes/physics_lab/counterfactual/Tempered.tscn",
	"res://scenes/rule_evaluation/Evaluation.tscn",
	"res://scenes/rubber_whitebox/gyro06/Gyro06.tscn",
	"res://scenes/rubber_whitebox/bellflower/Bellflower.tscn",
	"res://scenes/rubber_whitebox/shadecloth/Shadecloth.tscn",
	"res://scenes/rogue/Run.tscn",
	"res://scenes/rubber_whitebox/RubberYard.tscn",
	"res://scenes/rubber_whitebox/kinetic_pilot/Gallery.tscn",
	"res://scenes/rubber_whitebox/rule_arena/RuleArena.tscn",
	"res://scenes/rubber_whitebox/room_review/RoomReview.tscn",
]
var run_dir := ""
var busy := false

func _ready() -> void:
	var allowed := ProjectSettings.globalize_path("res://.runtime/rogue-mcp/").replace("\\", "/")
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--rogue-mcp-dir="):
			continue
		var path := argument.trim_prefix("--rogue-mcp-dir=").replace("\\", "/").simplify_path()
		var identifier := RegEx.new()
		identifier.compile("^[0-9a-f]{32}$")
		if path.get_base_dir() == allowed.trim_suffix("/") and identifier.search(path.get_file()) != null:
			run_dir = path
	set_process(not run_dir.is_empty())

func _process(_delta: float) -> void:
	if busy:
		return
	var path := run_dir.path_join("request.json")
	if not FileAccess.file_exists(path):
		return
	var source := FileAccess.get_file_as_string(path)
	# Windows can expose a just-renamed inbox before its handle is readable.
	if source.is_empty():
		return
	if DirAccess.remove_absolute(path) != OK:
		return
	var request: Variant = JSON.parse_string(source)
	if not request is Dictionary:
		return
	var identifier := RegEx.new()
	identifier.compile("^[0-9]{6,}$")
	if identifier.search(str(request.get("id", ""))) == null:
		return
	busy = true
	_handle.call_deferred(request)

func _handle(request: Dictionary) -> void:
	var id := str(request["id"])
	var frames := clampi(int(request.get("frames", 1)), 1, 120)
	var operation := str(request.get("operation", ""))
	var error := ""
	var scene := get_tree().current_scene
	if not is_instance_valid(scene) or scene.scene_file_path not in TEST_SCENES:
		error = "Expected an allowlisted test scene"
	elif operation == "action":
		var action := StringName(request.get("action", ""))
		if not InputMap.has_action(action):
			error = "Unknown InputMap action: " + str(action)
		else:
			_send_action(action, true)
			for frame in range(frames):
				await get_tree().process_frame
			_send_action(action, false)
	elif operation == "click":
		var position := Vector2(float(request.get("x", 0)), float(request.get("y", 0)))
		if not get_viewport().get_visible_rect().has_point(position):
			error = "Click outside the viewport"
		else:
			_send_click(position, true)
			await get_tree().process_frame
			_send_click(position, false)
	elif operation == "look":
		# Relative mouse motion split over the requested frames, as a captured mouse delivers it.
		var delta := Vector2(float(request.get("dx", 0)), float(request.get("dy", 0))) / frames
		for frame in range(frames):
			var motion := InputEventMouseMotion.new()
			motion.position = get_viewport().get_visible_rect().size * 0.5
			motion.global_position = motion.position
			motion.relative = delta
			motion.screen_relative = delta
			Input.parse_input_event(motion)
			await get_tree().process_frame
	elif operation == "key":
		# Physical key tap: InputMap actions bound to it fire through the normal event path.
		var key := InputEventKey.new()
		key.physical_keycode = int(request.get("keycode", 0)) as Key
		key.keycode = key.physical_keycode
		key.pressed = true
		Input.parse_input_event(key)
		for frame in range(frames):
			await get_tree().process_frame
		var up := key.duplicate() as InputEventKey
		up.pressed = false
		Input.parse_input_event(up)
	elif operation == "wait":
		for frame in range(frames):
			await get_tree().process_frame
	elif operation != "observe":
		error = "Unknown operation"
	await get_tree().process_frame
	scene = get_tree().current_scene
	var size := get_viewport().get_visible_rect().size
	var result := {"pid": OS.get_process_id(), "project_root": ProjectSettings.globalize_path("res://"),
		"project_sha256": FileAccess.get_sha256("res://project.godot"),
		"scene": scene.scene_file_path if is_instance_valid(scene) else "",
		"renderer": RenderingServer.get_current_rendering_method(),
		"window_backend": DisplayServer.get_name(), "viewport_size": [size.x, size.y]}
	if error.is_empty() and is_instance_valid(scene) and scene.has_method("mcp_observe"):
		var state: Variant = scene.call("mcp_observe")
		if state is Dictionary:
			result["state"] = state
		else:
			error = "mcp_observe() must return a Dictionary"
	if error.is_empty() and request.get("screenshot", false):
		if result.renderer != "forward_plus" or str(result.window_backend).to_lower() == "headless":
			error = "Screenshots require a real Forward+ window"
		else:
			await RenderingServer.frame_post_draw
			var image := get_viewport().get_texture().get_image()
			if image == null or image.is_empty() or image.save_png(run_dir.path_join(id + ".png")) != OK:
				error = "Failed to capture viewport PNG"
	if not error.is_empty():
		result["error"] = error
	var temporary := run_dir.path_join(id + ".tmp")
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(result))
		file.close()
		DirAccess.rename_absolute(temporary, run_dir.path_join(id + ".json"))
	busy = false

func _send_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	Input.parse_input_event(event)

func _send_click(position: Vector2, pressed: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = position
	event.global_position = position
	event.pressed = pressed
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	get_viewport().push_input(event, true)

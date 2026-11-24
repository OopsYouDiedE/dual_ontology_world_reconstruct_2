extends SceneTree
## Actual Forward+ scene, with an editorial camera on the sampled Sol path.
const Portal = preload("res://docs/production/expedition-01/playtest/structure/portal.gd")
const INTRO := 90
const FRAMES := 360
var level
var path: Array
var hale_path: Array
var caption: Label

func _initialize() -> void:
	film.call_deferred()

func sample(points: Array, t: float) -> Vector3:
	for i in range(1, points.size()):
		var b: Array = points[i]
		if b[0] < t: continue
		var a: Array = points[i-1]
		return Vector3(a[1], a[2], a[3]).lerp(Vector3(b[1], b[2], b[3]), clampf((t-a[0])/(b[0]-a[0]), 0., 1.))
	var end: Array = points[-1]
	return Vector3(end[1], end[2], end[3])

func film() -> void:
	var args := OS.get_cmdline_user_args()
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	if DisplayServer.get_name() == "headless" or RenderingServer.get_current_rendering_method() != "forward_plus" or report.profile != "cautious" or report.seed != 31:
		push_error("Need a Forward+ viewport and cautious/31 report")
		quit(2)
		return
	path = report.path_samples
	hale_path = report.hale_path_samples
	seed(31)
	level = load("res://scenes/expedition_01/Expedition.tscn").instantiate()
	root.add_child(level)
	Portal.install(level, report.layout)
	level.set_physics_process(false)
	level.set_process_input(false)
	level.set_process_unhandled_input(false)
	for child in level.get_children():
		if child is CanvasLayer: child.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	var overlay := CanvasLayer.new()
	overlay.layer = 100
	root.add_child(overlay)
	caption = Label.new()
	caption.position = Vector2(28, 60)
	caption.add_theme_font_size_override("font_size", 26)
	caption.add_theme_color_override("font_outline_color", Color.BLACK)
	caption.add_theme_constant_override("outline_size", 9)
	overlay.add_child(caption)
	print("FILM ", report.layout, " ", RenderingServer.get_current_rendering_method(), " ", RenderingServer.get_video_adapter_name())
	pose(0, report.layout)
	for i in 45:
		await RenderingServer.frame_post_draw
	for i in FRAMES:
		pose(i, report.layout)
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image.save_png(args[1].path_join("%04d.png" % i)) != OK:
			push_error("Could not write rendered frame")
			quit(3)
			return
	print("FILM DONE ", FRAMES)
	quit()

func pose(frame: int, layout: String) -> void:
	var t := 0. if frame < INTRO else 235. + (frame-INTRO)*2.
	var p := sample(path, t)
	# Hold the same +X heading on both arms; a common editorial view makes the
	# opening and the lateral shift readable. No inference of Sol's original gaze.
	level.walker.global_position = p
	level.walker.rotation.y = -PI/2
	level.eye.rotation = Vector3.ZERO
	level.hale.global_position = sample(hale_path, t)
	var shot := "MATCHED ENTRANCE VIEW" if frame < INTRO else "SOL PATH REPLAY  |  TICK %03d" % int(t)
	caption.text = "%s  /  %s\nCAUTIOUS  /  SEED 31  /  FORWARD+" % [layout, shot]

extends SceneTree
## Public Hall shares the expedition stage, HUD frame and first-person look.
## Needs a real window (mouse capture is a no-op headless):
##   Godot --path . --rendering-method forward_plus -s res://tools/test/hall_view_test.gd -- --no-rule-save --skip-intro

const RunScene := preload("res://scenes/rogue/Run.tscn")
const Stage := preload("res://scenes/components/rendering/AcademyStage.gd")
var failed := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, msg: String) -> void:
	print(("PASS " if ok else "FAIL ") + msg)
	if not ok:
		failed += 1

func frames(n: int) -> void:
	for i in n:
		await process_frame

func click(at: Vector2) -> void:
	for pressed in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.position = at
		event.global_position = at
		event.pressed = pressed
		root.push_input(event, true)
	await frames(2)

func look(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = root.get_visible_rect().size * 0.5
	event.relative = relative
	event.screen_relative = relative
	Input.parse_input_event(event)
	await frames(2)

func captured() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func run() -> void:
	var game := RunScene.instantiate()
	root.add_child(game)
	await frames(8)
	var view = game.room_view
	var player = view._player
	var screen := root.get_visible_rect()
	check(game.mouse_filter == Control.MOUSE_FILTER_IGNORE, "Run root lets clicks through to the level beneath it")
	check(view.get_global_rect().is_equal_approx(screen), "Hall view covers the whole window")
	var picture: Rect2 = view._pixels.get_global_rect()
	check(picture.size.x >= screen.size.x - 2 and picture.size.y >= screen.size.y - 2, "Hall picture has no letterbox frame (%s)" % str(picture))
	var hall_env: Environment = view.get_node("RoomViewport/WorldEnvironment").environment
	var stage := Stage.environment()
	check(hall_env.tonemap_mode == stage.tonemap_mode and is_equal_approx(hall_env.tonemap_exposure, stage.tonemap_exposure)
		and is_equal_approx(hall_env.adjustment_saturation, stage.adjustment_saturation) and hall_env.ssao_enabled and hall_env.glow_enabled and hall_env.fog_enabled,
		"Hall renders on the expedition stage environment")
	var ink := view.get_node("RoomViewport/ExpeditionInk") as MeshInstance3D
	# No override means the HallInk default, the strength the expedition draws with.
	check(ink != null and ink.material_override.get_shader_parameter("opacity") == null, "Hall ink matches the expedition strength")
	check(view._viewport.msaa_3d == Viewport.MSAA_4X, "Hall viewport uses the expedition MSAA")

	var eye: Camera3D = player.camera()
	await frames(2)
	check(is_equal_approx(eye.fov, Stage.BASE_FOV), "Hall eye uses the expedition FOV (%.1f)" % eye.fov)
	check(absf(eye.global_position.y - player.global_position.y - Stage.EYE_HEIGHT) < 0.03, "Hall eye height matches the expedition")

	var yaw: float = player.snapshot().yaw
	Input.action_press("rogue_orbit_left")
	await frames(16)
	Input.action_release("rogue_orbit_left")
	check(is_equal_approx(player.snapshot().yaw, yaw), "Q no longer spins the first-person view")

	root.focus_entered.emit()
	await click(Vector2(40, screen.size.y * 0.45))
	check(captured(), "A click on the former letterbox edge takes the view")
	await look(Vector2(100, 0))
	var turned: float = yaw - player.snapshot().yaw
	check(absf(turned - 100 * Stage.LOOK_SENSITIVITY) < 0.002, "Mouse right turns right at the expedition sensitivity (%.3f rad)" % turned)
	await look(Vector2(0, -2000))
	check(is_equal_approx(player.snapshot().pitch, Stage.PITCH_LIMIT), "Pitch stops at the expedition limit")
	root.focus_exited.emit()
	await frames(1)
	check(not captured(), "Losing window focus releases the cursor")

	# From the Hall into the first sortie: the level beneath the Run root must still take a world click.
	game._depart_first()
	await frames(10)
	var sortie = game.first_sortie
	root.focus_entered.emit()
	await frames(1)
	var before: float = sortie.walker.rotation.y
	await click(screen.size * 0.5)
	check(captured(), "First expedition captures the mouse when launched from the Hall")
	await look(Vector2(100, 0))
	check(sortie.walker.rotation.y < before - 0.1, "First expedition turns with the mouse")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	game.queue_free()
	await frames(2)
	print("Hall view test: %d failures" % failed)
	quit(failed)

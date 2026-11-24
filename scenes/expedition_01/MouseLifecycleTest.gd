extends SceneTree
## Run with --path . --script res://scenes/expedition_01/MouseLifecycleTest.gd

var level
var failures := 0
var gui_presses := 0
const WORLD := Vector2(240, 120)

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, label: String) -> void:
	if ok:
		print("ok: ", label)
	else:
		failures += 1
		push_error("FAIL: " + label)

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	root.push_input(event, true)

func motion(pos: Vector2, relative := Vector2.ZERO) -> void:
	var event := InputEventMouseMotion.new()
	event.position = pos
	event.relative = relative
	root.push_input(event, true)

func button(pos: Vector2, pressed: bool, index := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.position = pos
	event.button_index = index
	event.pressed = pressed
	root.push_input(event, true)

func click(pos: Vector2) -> void:
	motion(pos)
	button(pos, true)
	button(pos, false)

func visible_mouse() -> bool:
	return Input.mouse_mode == Input.MOUSE_MODE_VISIBLE

func run() -> void:
	level = preload("Expedition.tscn").instantiate()
	root.add_child(level)
	level.set_physics_process(false)
	var canvas := CanvasLayer.new()
	canvas.layer = 30
	level.add_child(canvas)
	var gui := Button.new()
	canvas.add_child(gui)
	gui.position = Vector2(12, 45)
	gui.size = Vector2(70, 40)
	gui.pressed.connect(func(): gui_presses += 1)
	await process_frame
	root.focus_entered.emit()
	check(visible_mouse(), "startup and focus entry leave cursor visible")
	click(gui.get_global_rect().get_center())
	check(gui_presses == 1 and visible_mouse(), "GUI button receives click without capture")
	gui.mouse_filter = Control.MOUSE_FILTER_PASS
	gui.disabled = true
	click(gui.get_global_rect().get_center())
	check(visible_mouse(), "pass-through GUI still blocks world capture")
	click(WORLD)
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "world left press captures")
	var yaw: float = level.walker.rotation.y
	motion(WORLD, Vector2(12, 0))
	check(not is_equal_approx(level.walker.rotation.y, yaw), "captured mouse still looks around")
	button(WORLD, true, MOUSE_BUTTON_RIGHT)
	check(level.aiming, "right mouse aims")
	root.focus_exited.emit()
	check(visible_mouse() and not level.aiming, "focus loss releases mouse and aim")
	click(WORLD)
	check(visible_mouse(), "unfocused click cannot capture")
	root.focus_entered.emit()
	button(WORLD, false)
	check(visible_mouse(), "focus return and mouse-up do not recapture")
	click(WORLD)
	key(KEY_ESCAPE)
	check(visible_mouse(), "Escape releases gameplay capture")
	click(WORLD)
	key(KEY_I)
	check(visible_mouse() and level.manual.visible, "I releases and opens handbook")
	key(KEY_RIGHT)
	check(level.book_page == 1, "handbook page keys still work")
	click(WORLD)
	check(visible_mouse(), "world click while handbook is open does not capture")
	key(KEY_I)
	check(visible_mouse() and not level.manual.visible, "I closes handbook without capture")
	key(KEY_1)
	key(KEY_ESCAPE)
	check(visible_mouse() and not level.manual.visible, "legacy handbook shortcut and Escape close")
	level.hale.hide()
	level.contracts.trust = 2
	click(WORLD)
	key(KEY_Q)
	check(visible_mouse() and level.wheel_open, "Q releases and opens command wheel")
	click(WORLD)
	check(visible_mouse(), "world click while wheel is open does not capture")
	var selected: int = level.wheel.index
	button(WORLD, true, MOUSE_BUTTON_WHEEL_DOWN)
	button(WORLD, false, MOUSE_BUTTON_WHEEL_DOWN)
	check(level.wheel.index == posmod(selected + 1, level.wheel.options.size()), "one scroll step moves selection once")
	key(KEY_Q)
	check(visible_mouse() and not level.wheel_open, "Q dismisses wheel without capture")
	key(KEY_Q)
	key(KEY_ESCAPE)
	check(visible_mouse() and not level.wheel_open, "Escape dismisses wheel without capture")
	level.contracts.trust = 0
	click(WORLD)
	key(KEY_Q)
	check(visible_mouse() and not level.wheel_open and level.hale_hold, "Q releases even when executing a single order directly")
	level.hale_hold = false
	level.contracts.trust = 2
	key(KEY_Q)
	key(KEY_1)
	check(visible_mouse() and not level.wheel_open and level.hale_hold, "number confirms order without capture")
	click(WORLD)
	key(KEY_F4)
	check(visible_mouse() and level.mode >= 0, "section view releases mouse")
	click(WORLD)
	check(visible_mouse(), "section view world click leaves cursor visible")
	for i in 3:
		key(KEY_F4)
	check(visible_mouse(), "returning to first person leaves cursor visible")
	click(WORLD)
	check(Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "fresh click restores capture")
	level.free()
	check(visible_mouse(), "scene exit releases mouse")
	print("Expedition mouse lifecycle: %d failure(s)" % failures)
	# Let the audio mixer release playbacks before terminating the test host.
	for frame in 26:
		OS.delay_msec(8)
		await process_frame
	quit(0 if failures == 0 else 1)

extends Node
class_name UnifiedTeammateWheel
## Unified radial teammate command wheel controller shared across Public Hall,
## Campaign Rooms, Expedition-01, and all future levels.
## Uses the exact same Q key, 34px center cancel deadzone, 235px outer ring,
## mouse hover / wheel / 1-5 / E confirm / Esc cancel semantics everywhere.

const CommandWheelScript := preload("res://scenes/expedition_01/CommandWheel.gd")
const UiStyle := preload("res://scenes/components/shared/UiTheme.gd")

signal order_selected(id: String)
signal wheel_opened
signal wheel_closed

var wheel: Node
var _prev_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_VISIBLE

func setup(ui_parent: Node) -> void:
	if is_instance_valid(wheel):
		return
	wheel = CommandWheelScript.new()
	add_child(wheel)
	wheel.setup(ui_parent, UiStyle.make_font())
	wheel.chosen.connect(func(id: String):
		Input.mouse_mode = _prev_mouse_mode
		order_selected.emit(id)
		wheel_closed.emit()
	)
	wheel.cancelled.connect(func():
		Input.mouse_mode = _prev_mouse_mode
		wheel_closed.emit()
	)

func is_open() -> bool:
	return is_instance_valid(wheel) and bool(wheel.open)

func open_with(items: Array) -> bool:
	if not is_instance_valid(wheel) or items.is_empty():
		return false
	wheel.bind(items)
	wheel.reveal()
	_prev_mouse_mode = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	wheel_opened.emit()
	return true

func close(confirm_current := false) -> void:
	if not is_open():
		return
	if confirm_current:
		wheel.confirm()
	else:
		wheel.dismiss()
		Input.mouse_mode = _prev_mouse_mode
		wheel_closed.emit()

func handle_input(event: InputEvent, options_provider: Callable) -> bool:
	if not is_instance_valid(wheel):
		return false
	if is_open():
		if event is InputEventMouseButton and event.pressed:
			var mb := (event as InputEventMouseButton).button_index
			if mb == MOUSE_BUTTON_WHEEL_UP:
				wheel.move(-1)
				return true
			elif mb == MOUSE_BUTTON_WHEEL_DOWN:
				wheel.move(1)
				return true
		if event is InputEventKey and event.pressed and not event.echo:
			var code := (event as InputEventKey).physical_keycode
			if code == KEY_ESCAPE or code == KEY_Q:
				close(false)
				return true
			if code == KEY_E or code == KEY_ENTER:
				close(true)
				return true
			if code in [KEY_1, KEY_2, KEY_3, KEY_4, KEY_5]:
				var idx := code - KEY_1
				if idx < wheel.options.size():
					wheel.index = idx
					close(true)
					return true
		return false

	# Closed state: pressing Q opens the unified teammate radial wheel
	if event is InputEventKey and event.pressed and not event.echo:
		if (event as InputEventKey).physical_keycode == KEY_Q:
			if options_provider.is_valid():
				var items: Array = options_provider.call()
				if not items.is_empty():
					return open_with(items)
	return false

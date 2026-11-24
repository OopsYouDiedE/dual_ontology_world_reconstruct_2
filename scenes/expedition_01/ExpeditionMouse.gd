extends RefCounted
## Mouse capture belongs to a fresh world click after GUI dispatch.

var focused := false

func set_focused(value: bool) -> void:
	focused = value
	if not focused:
		release()

func release() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func capture_world_click(event: InputEvent, viewport: Viewport) -> bool:
	if not focused or viewport.gui_get_hovered_control() != null:
		return false
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return true
	return false

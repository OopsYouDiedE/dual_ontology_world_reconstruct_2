extends "res://tools/research/french_gothic_nodes/WholeReview.gd"
## All bookmarks keep every structural layer visible. Flight has no collision.
const STOPS := [
	[Vector3(0,1.65,4.8),Vector3(0,3.3,21)],
	[Vector3(5,1.65,6),Vector3(4,2.3,19)],
	[Vector3(-6,2,14),Vector3(4,4,16)],
	[Vector3(1,1.65,21),Vector3(0,4,27)],
	[Vector3(6.3,2.25,13),Vector3(10.48,2.9,13)],
	[Vector3(4.45,1.95,6.7),Vector3(6.85,2.65,6.7)],
	[Vector3(0,9,4.5),Vector3(1,10,9)],
]
func _set_view() -> void:
	parts["Exterior"].visible = true
	cam.fov = 68; cam.near = 0.04; cam.current = true
	cam.position = STOPS[view][0]; cam.look_at(STOPS[view][1])

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_RIGHT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if e.pressed else Input.MOUSE_MODE_VISIBLE
	elif e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		cam.rotation.y -= e.relative.x * 0.002
		cam.rotation.x = clampf(cam.rotation.x - e.relative.y * 0.002, -1.55, 1.55)
	elif e is InputEventKey and e.pressed and e.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif e.is_action_pressed("ui_accept"):
		view = (view + 1) % STOPS.size(); _set_view()

func _process(delta: float) -> void:
	if not get_window().has_focus(): return
	var d := Vector3.ZERO
	for pair in [[KEY_W,-cam.basis.z],[KEY_S,cam.basis.z],[KEY_A,-cam.basis.x],[KEY_D,cam.basis.x],[KEY_E,Vector3.UP],[KEY_Q,Vector3.DOWN]]:
		if Input.is_physical_key_pressed(pair[0]): d += pair[1]
	cam.position += d.normalized() * delta * (9.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 3.0)

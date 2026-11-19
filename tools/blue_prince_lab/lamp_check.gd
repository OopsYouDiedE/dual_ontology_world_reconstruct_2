extends SceneTree

const LAMP := preload("res://scenes/blue_prince_lab/lamp/Lamp.tscn")
var _errors := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var mount := Node3D.new()
	mount.position = Vector3(3, 4, -2)
	mount.rotation.y = 0.83
	root.add_child(mount)
	var lamp := LAMP.instantiate()
	mount.add_child(lamp)
	var light := lamp.get_node("Pendulum/OilLight") as OmniLight3D
	var hook := lamp.get_node("FixedEye") as Node3D
	var fixed := hook.global_position
	var rest := light.global_position
	_check(absf((lamp.global_position - rest).y - 0.992) < 0.001, "one metre drop")
	_check(light.shadow_enabled and light.light_color.r > light.light_color.b, "warm shadowed light")
	lamp.set_wind(Vector3(7, 0, 0))
	await _ticks(45)
	var first := light.global_position - rest
	_check(first.x > 0.08 and absf(first.z) < 0.001, "world +X gust moves bob under rotated parent")
	_check(hook.global_position.is_equal_approx(fixed), "ceiling eye stays fixed")
	_check(absf(lamp.global_position.distance_to(light.global_position) - 0.992) < 0.001, "fixed pivot radius")
	lamp.set_wind(Vector3(0, 0, -7))
	await _ticks(280)
	var reversed := light.global_position - rest
	_check(reversed.z < -0.10 and absf(reversed.x) < 0.012, "wind change redirects bob")
	lamp.set_wind(Vector3.ZERO)
	await _ticks(12)
	_check(light.global_position.distance_to(rest) > 0.04, "inertia after wind stops")
	await _ticks(420)
	_check(light.global_position.distance_to(rest) < 0.004, "damping returns lamp to rest")
	lamp.set_wind(Vector3(200, 0, 0))
	await _ticks(150)
	var swing: Vector3 = light.global_position - lamp.global_position
	_check(swing.angle_to(Vector3.DOWN) < 0.522, "maximum tilt is bounded")
	print("Lamp check: %d failure(s); first=%s, redirected=%s" % [_errors, first, reversed])
	quit(1 if _errors else 0)


func _ticks(count: int) -> void:
	for i in range(count):
		await physics_frame


func _check(condition: bool, message: String) -> void:
	if not condition:
		_errors += 1
		push_error(message)

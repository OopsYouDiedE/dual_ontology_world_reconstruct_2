extends SceneTree
## Run with Godot --headless --path . --script res://tools/blue_prince_lab/stairs_check.gd

const STAIRS := preload("res://scenes/blue_prince_lab/stairs/Stairs.tscn")
var failures := 0


func _initialize() -> void:
	Engine.physics_ticks_per_second = 60
	call_deferred("_run")


func _run() -> void:
	var stairs := STAIRS.instantiate() as Node3D
	root.add_child(stairs)
	var body := stairs.get_node("GeneratedStairGeometry") as StaticBody3D
	var normal_checked := false
	for node in body.get_children():
		if node is MeshInstance3D and node.mesh is ArrayMesh:
			var data: Array = node.mesh.surface_get_arrays(0)
			var vertex: Vector3 = data[Mesh.ARRAY_VERTEX][0]
			var normal: Vector3 = data[Mesh.ARRAY_NORMAL][0]
			_check(normal.dot(Vector3(vertex.x, 0, vertex.z)) > 0, "baluster normals face outward")
			normal_checked = true
			break
	_check(normal_checked, "faceted baluster generated")
	_floor(Vector3(0, -0.1, 1.0))
	_floor(Vector3(0, 1.55, -5.8))
	var player := CharacterBody3D.new()
	player.position = Vector3(0, 0.01, 0.70)
	player.floor_snap_length = 0.26
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.25
	capsule.height = 1.70
	shape.shape = capsule
	shape.position.y = 0.85
	player.add_child(shape)
	root.add_child(player)
	await physics_frame
	await _walk(player, Vector3.FORWARD, 365)
	_check(player.position.z < -5.0 and absf(player.position.y - 1.65) < 0.03 and player.is_on_floor(), "ascending from floor through landing to upper exit: %s" % player.position)
	await _walk(player, Vector3.BACK, 45)
	_check(player.position.z < -3.9 and player.position.z > -4.7 and player.is_on_floor(), "return to landing: %s" % player.position)
	await _walk(player, Vector3.RIGHT, 75)
	_check(player.position.x > 0.65 and player.position.x < 0.86 and player.is_on_floor(), "side guard blocks lateral exit: %s" % player.position)
	await _walk(player, Vector3.LEFT, 44)
	await _walk(player, Vector3.BACK, 255)
	_check(player.position.z > 0.25 and absf(player.position.y) < 0.03 and player.is_on_floor(), "descending to lower floor: %s" % player.position)
	if failures == 0:
		print("PASS: stairs geometry, ascent, landing guard and descent")
	quit(failures)


func _walk(player: CharacterBody3D, direction: Vector3, count: int) -> void:
	for i in count:
		await physics_frame
		player.velocity = direction * 1.2 + Vector3.DOWN * 0.35
		player.move_and_slide()


func _floor(position: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = position
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(5, 0.2, 2)
	shape.shape = box
	body.add_child(shape)
	root.add_child(body)


func _check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

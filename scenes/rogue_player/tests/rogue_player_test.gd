extends SceneTree

const PLAYER := preload("res://scenes/rogue_player/RoguePlayer.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var error := await _exercise()
	if not error.is_empty():
		push_error(error)
		quit(1)
	else:
		print("RoguePlayer: MPFB2 R-05 rig + bone clips, walk, sprint, orbit, floor/wall, camera collision, action and respawn passed")
		quit(0)

func _exercise() -> String:
	var view := SubViewport.new()
	view.own_world_3d = true
	view.size = Vector2i(384, 216)
	root.add_child(view)
	_box(view, Vector3(0, -0.15, 0), Vector3(18, 0.3, 18))
	_box(view, Vector3(0, 1, -2.2), Vector3(8, 2, 0.2))
	var player = PLAYER.instantiate()
	view.add_child(player)
	player.spawn_at(Vector3.ZERO, 0.0)
	await _frames(12)
	if not player.is_on_floor() or view.get_camera_3d() != player.camera():
		return "Player failed to ground or own the SubViewport camera"
	var visual: Node3D = player.get_node("Visual")
	var animation := visual.get_meta("animation_player", null) as AnimationPlayer
	var skeleton := visual.get_meta("skeleton", null) as Skeleton3D
	if animation == null or skeleton == null or not str(player.snapshot().rig).ends_with("r05_formal.glb"):
		return "Production detective rig unavailable"
	for clip in [&"idle", &"walk", &"run", &"interact"]:
		if not animation.has_animation(clip) or animation.get_animation(clip).get_track_count() < 10:
			return "Missing production bone tracks for %s" % clip
	Input.action_press("move_up")
	await _frames(18)
	Input.action_release("move_up")
	var walked: float = -player.position.z
	if walked < 0.65 or absf(player.position.x) > 0.03 or animation.current_animation != &"walk":
		return "Walk failed: position %s clip %s" % [player.position, animation.current_animation]
	player.spawn_at(Vector3.ZERO, 0.0)
	Input.action_press("move_up")
	Input.action_press("rogue_sprint")
	await _frames(18)
	Input.action_release("rogue_sprint")
	if -player.position.z < walked * 1.4 or animation.current_animation != &"run":
		Input.action_release("move_up")
		return "Sprint failed"
	await _frames(45)
	Input.action_release("move_up")
	if player.position.z < -1.86 or player.position.z > -1.60:
		return "Wall collision failed: %s" % player.position
	player.spawn_at(Vector3.ZERO, 0.0)
	var ceiling := _box(view, Vector3(0, 3, 0), Vector3(10, 0.3, 10))
	await _frames(4)
	if player.snapshot().camera_distance > 2.0:
		return "Camera penetrated ceiling"
	ceiling.queue_free()
	await _frames(35)
	if player.snapshot().camera_distance < 8.0:
		return "Camera failed to recover after obstacle removal"
	Input.action_press("rogue_orbit_right")
	await _frames(16)
	Input.action_release("rogue_orbit_right")
	if player.snapshot().yaw < 0.3:
		return "Keyboard orbit failed"
	Input.action_press("move_up")
	await _frames(12)
	Input.action_release("move_up")
	if player.position.x > -0.15:
		return "Movement did not track the changed camera basis"
	player.spawn_at(Vector3.ZERO)
	player.set_controls_enabled(false)
	Input.action_press("move_up")
	await _frames(12)
	Input.action_release("move_up")
	if absf(player.position.z) > 0.01 or not player.play_action("interact"):
		return "Disabled controls or interaction failed"
	await _frames(3)
	if animation.current_animation != &"interact":
		return "Interaction clip did not play"
	await _frames(ceili(animation.get_animation(&"interact").length * Engine.physics_ticks_per_second) + 6)
	if animation.current_animation != &"idle":
		return "Action did not return to idle"
	view.queue_free()
	return ""

func _frames(count: int) -> void:
	for i in count:
		await physics_frame

func _box(parent: Node, at: Vector3, size: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = at
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	body.add_child(collider)
	parent.add_child(body)
	return body

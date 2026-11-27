extends Node3D
## Public Hall residents & teammates:
## - Smooth exponential turn toward the player when approached (social acknowledgment)
## - Proximity-faded nameplates so the Gothic Hall stays uncluttered at long range
## - First-person camera anti-clipping fade

const Cast := preload("Roster.gd")
const ACK_RANGE := 3.4

var actors := {}
var _tags := {}
var _moving := {}

func sync(rows: Dictionary, step_seconds: float) -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	for id: String in rows:
		var cell: Vector2i = rows[id].cell
		var at := Vector3(cell.x + .5, 0, cell.y + .5)
		if not actors.has(id):
			var actor := Node3D.new()
			add_child(actor)
			actor.position = at
			Cast.attach(actor, id)
			var tag := Label3D.new()
			tag.text = id
			tag.modulate = Color("ecdbb9")
			tag.pixel_size = .002
			tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			actor.add_child(tag)
			tag.position.y = 1.92
			actors[id] = actor
			_tags[id] = tag
		var actor: Node3D = actors[id]
		var moved := actor.position.distance_squared_to(at) > .04
		_moving[id] = moved
		if moved:
			var flat := Vector2(at.x - actor.position.x, at.z - actor.position.z)
			if flat.length_squared() > 0.001:
				var target_yaw := atan2(flat.x, flat.y)
				if step_seconds > 0.0:
					var tw_rot := actor.create_tween()
					tw_rot.tween_property(actor, "rotation:y", lerp_angle(actor.rotation.y, target_yaw, 1.0), minf(step_seconds * 0.35, 0.35))
				else:
					actor.rotation.y = target_yaw
			if step_seconds > 0.0:
				actor.create_tween().tween_property(actor, "position", at, step_seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			else:
				actor.position = at
		var anim := actor.get_meta("animation_player", null) as AnimationPlayer
		var clip := &"walk" if moved else (&"interact" if rows[id].status == &"using_object" else &"idle")
		if anim and anim.has_animation(clip) and anim.current_animation != clip:
			anim.play(clip, .18)
		targets.append({"kind": "witness", "id": id, "label": id, "position": actor.position})
	return targets

## Social acknowledgment turn when approached + proximity-faded nameplates + camera anti-clip.
func _process(delta: float) -> void:
	var camera := get_viewport().get_camera_3d()
	if not camera:
		return
	var cam_pos := camera.global_position
	for id: String in actors:
		var actor: Node3D = actors[id]
		var local_eye := actor.to_local(cam_pos)
		var flat_d2 := Vector2(local_eye.x, local_eye.z).length_squared()
		actor.visible = not (local_eye.y > 0.0 and local_eye.y < 2.1 and flat_d2 < 0.16)

		var dist := Vector2(cam_pos.x - actor.position.x, cam_pos.z - actor.position.z).length()
		if not bool(_moving.get(id, false)) and dist < ACK_RANGE and dist > 0.35:
			var yaw := atan2(cam_pos.x - actor.position.x, cam_pos.z - actor.position.z)
			actor.rotation.y = lerp_angle(actor.rotation.y, yaw, 1.0 - exp(-4.8 * delta))

		var tag := _tags.get(id) as Label3D
		if is_instance_valid(tag):
			tag.modulate.a = clampf(1.0 - smoothstep(3.8, 8.2, dist), 0.12, 0.95)

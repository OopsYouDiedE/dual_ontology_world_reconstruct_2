extends Node3D

const Cast := preload("Roster.gd")
var actors := {}

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
			tag.position.y = 1.88
			actors[id] = actor
		var actor: Node3D = actors[id]
		var moved := actor.position.distance_squared_to(at) > .04
		if moved:
			actor.look_at(at, Vector3.UP, true)
			if step_seconds > 0: actor.create_tween().tween_property(actor, "position", at, step_seconds)
			else: actor.position = at
		var anim := actor.get_meta("animation_player", null) as AnimationPlayer
		var clip := &"walk" if moved else (&"interact" if rows[id].status == &"using_object" else &"idle")
		if anim and anim.has_animation(clip) and anim.current_animation != clip: anim.play(clip, .15)
		targets.append({"kind":"witness", "id":id, "label":id, "position":actor.position})
	return targets

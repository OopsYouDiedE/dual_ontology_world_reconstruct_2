extends Node3D
## Presentation only. CampResidents owns choices, clock, occupancy and completion.
const Visual := preload("res://scenes/rogue_player/ImportedCharacter.gd")
const Model := preload("res://assets/characters/UserModels/model_06.glb")
var actors := {}

func sync(residents: Dictionary, seconds: float) -> void:
	for id: String in residents:
		var row: Dictionary = residents[id]
		var target := Vector3(row.cell.x + 0.5, 0.0, row.cell.y + 0.5)
		if not actors.has(id):
			var actor := Node3D.new()
			add_child(actor)
			actor.position = target
			Visual.attach(actor, Model.resource_path, 1.38, -90.0, id)
			actors[id] = actor
		var actor: Node3D = actors[id]
		var moving := not actor.position.is_equal_approx(target)
		if moving:
			actor.look_at(target, Vector3.UP, true)
			if seconds > 0.0: actor.create_tween().tween_property(actor, "position", target, seconds)
			else: actor.position = target
		var anim := actor.get_meta("animation_player", null) as AnimationPlayer
		var clip := &"walk" if moving else (&"interact" if row.status == &"using_object" else &"idle")
		if anim and anim.has_animation(clip) and anim.current_animation != clip: anim.play(clip, 0.15)

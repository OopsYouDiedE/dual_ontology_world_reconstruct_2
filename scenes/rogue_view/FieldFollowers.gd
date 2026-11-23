extends Node3D
## Presentation only. Crew decisions remain in ExpeditionCrew. Follow the captain's walked trail,
## rather than cutting straight through room walls between formation points.
const Visual := preload("res://scenes/rogue_crossing/Roster.gd")
const STEP := 0.15
var captain: CharacterBody3D
var _model: Callable
var _actors := {}
var _rehearsal := {}
var _rehearsal_time := 0.0
var _trail: Array[Vector3] = []

func setup(player: CharacterBody3D, starting_points: Array[Vector3], model := Callable()) -> void:
	captain = player
	_model = model
	_trail.assign([player.position])
	for point in starting_points:
		var old := _trail.back() as Vector3
		var count := maxi(1, ceili(old.distance_to(point) / STEP))
		for i in range(1, count + 1): _trail.append(old.lerp(point, float(i) / count))

func sync(names: Array) -> void:
	for id in _actors.keys():
		if not names.has(id):
			_actors[id].queue_free()
			_actors.erase(id)
	for i in names.size():
		var id: String = names[i]
		if _actors.has(id): continue
		var actor := Node3D.new()
		add_child(actor)
		actor.position = _slot(i)
		if _model.is_valid(): _model.call(actor, id)
		else: Visual.attach(actor, id)
		var label := Label3D.new()
		label.text = id
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = 2.00
		label.pixel_size = 0.0023
		label.modulate = Color("eed4a4")
		actor.add_child(label)
		_actors[id] = actor

func rehearse(docks: Dictionary) -> void:
	_rehearsal = docks
	_rehearsal_time = .78

func _slot(index: int) -> Vector3:
	return _trail[mini((index + 1) * 7, _trail.size() - 1)]

func _physics_process(delta: float) -> void:
	if not is_instance_valid(captain) or _trail.is_empty(): return
	if captain.position.distance_to(_trail[0]) > 4.0:
		_trail.assign([captain.position])
	if captain.position.distance_to(_trail[0]) >= STEP:
		_trail.push_front(captain.position)
		if _trail.size() > 30: _trail.pop_back()
	_rehearsal_time = maxf(0, _rehearsal_time - delta)
	var index := 0
	for id in _actors:
		var actor: Node3D = _actors[id]
		var target: Vector3 = _rehearsal[id] if _rehearsal_time > 0 and _rehearsal.has(id) else _slot(index)
		index += 1
		actor.visible = actor.position.distance_squared_to(captain.position) > 0.32
		var moving := actor.position.distance_to(target) > 0.045
		if moving:
			var facing := Vector3(target.x, actor.position.y, target.z)
			if not facing.is_equal_approx(actor.position): actor.look_at(facing, Vector3.UP, true)
			actor.position = actor.position.move_toward(target, 5.8 * delta)
		var anim := actor.get_meta("animation_player", null) as AnimationPlayer
		var clip := &"walk" if moving else (&"interact" if _rehearsal_time > 0 and _rehearsal.has(id) else &"idle")
		if anim and anim.has_animation(clip) and anim.current_animation != clip: anim.play(clip, 0.18)

extends Node3D
## Industry-standard companion follower presentation:
## - Breadcrumb trail following with smooth arrival damping (no robotic constant-speed snapping)
## - Smooth exponential yaw interpolation (lerp_angle)
## - Personal-space sidestepping when the captain approaches (avoids popping invisible)
## - Social gaze awareness: idle companions gently turn toward the captain when nearby
## - Proximity-faded nameplates to keep the world clean at distance

const Visual := preload("res://scenes/rogue_crossing/Roster.gd")
const STEP := 0.15
const PERSONAL_SPACE := 0.95
const GAZE_RANGE := 4.8

var captain: CharacterBody3D
var _model: Callable
var _actors := {}
var _tags := {}
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
		for i in range(1, count + 1):
			_trail.append(old.lerp(point, float(i) / count))

func sync(names: Array) -> void:
	for id in _actors.keys():
		if not names.has(id):
			_actors[id].queue_free()
			_actors.erase(id)
			_tags.erase(id)
	for i in names.size():
		var id: String = names[i]
		if _actors.has(id):
			continue
		var actor := Node3D.new()
		add_child(actor)
		actor.position = _slot(i)
		if _model.is_valid():
			_model.call(actor, id)
		else:
			Visual.attach(actor, id)
		var label := Label3D.new()
		label.text = id
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.position.y = 2.02
		label.pixel_size = 0.0022
		label.modulate = Color("eed4a4")
		actor.add_child(label)
		_actors[id] = actor
		_tags[id] = label

func rehearse(docks: Dictionary) -> void:
	_rehearsal = docks
	_rehearsal_time = .78

func _slot(index: int) -> Vector3:
	return _trail[mini((index + 1) * 7, _trail.size() - 1)]

func _smooth_turn_toward(actor: Node3D, look_pos: Vector3, delta: float, rate: float = 8.5) -> void:
	var flat := Vector2(look_pos.x - actor.position.x, look_pos.z - actor.position.z)
	if flat.length_squared() < 0.001:
		return
	# Godot forward with model facing +Z (use_model_front=true) maps to atan2(dx, dz)
	var target_yaw := atan2(flat.x, flat.y)
	actor.rotation.y = lerp_angle(actor.rotation.y, target_yaw, 1.0 - exp(-rate * delta))

func _physics_process(delta: float) -> void:
	if not is_instance_valid(captain) or _trail.is_empty():
		return
	if captain.position.distance_to(_trail[0]) > 4.0:
		_trail.assign([captain.position])
	if captain.position.distance_to(_trail[0]) >= STEP:
		_trail.push_front(captain.position)
		if _trail.size() > 30:
			_trail.pop_back()
	_rehearsal_time = maxf(0.0, _rehearsal_time - delta)
	var index := 0
	for id in _actors:
		var actor: Node3D = _actors[id]
		var target: Vector3 = _rehearsal[id] if _rehearsal_time > 0.0 and _rehearsal.has(id) else _slot(index)
		index += 1

		# Personal-space yielding: gently step aside if captain walks into our bubble
		var to_actor := Vector3(actor.position.x - captain.position.x, 0.0, actor.position.z - captain.position.z)
		var cap_dist := to_actor.length()
		if cap_dist < PERSONAL_SPACE and cap_dist > 0.01 and _rehearsal_time <= 0.0:
			var push := to_actor.normalized() * (PERSONAL_SPACE - cap_dist) * 1.15
			target += push

		actor.visible = cap_dist > 0.42
		var dist := actor.position.distance_to(target)
		var moving := dist > 0.055
		if moving:
			_smooth_turn_toward(actor, target, delta, 9.5)
			# Smooth arrival damping instead of abrupt constant-speed stop
			var speed := clampf(dist * 4.4, 0.85, 5.8)
			actor.position = actor.position.move_toward(target, speed * delta)
		elif cap_dist < GAZE_RANGE:
			# Social gaze awareness: politely face the captain when standing nearby
			_smooth_turn_toward(actor, captain.position, delta, 4.5)

		var tag := _tags.get(id) as Label3D
		if is_instance_valid(tag):
			var alpha := clampf(1.0 - smoothstep(4.5, 9.0, cap_dist), 0.18, 0.95)
			tag.modulate.a = alpha

		var anim := actor.get_meta("animation_player", null) as AnimationPlayer
		var clip := &"walk" if moving else (&"interact" if _rehearsal_time > 0.0 and _rehearsal.has(id) else &"idle")
		if anim and anim.has_animation(clip) and anim.current_animation != clip:
			anim.play(clip, 0.20)

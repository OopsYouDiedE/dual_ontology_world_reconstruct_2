extends CharacterBody3D

const Importer := preload("res://scenes/components/characters/ImportedCharacter.gd")
const SeatDriver := preload("res://scenes/components/characters/SeatPostureDriver3D.gd")
const Layers := preload("res://scenes/components/world/PhysicsLayers.gd")
var animation_player: AnimationPlayer
var visual: Node3D
var collider: CollisionShape3D
var nominal_height := 1.32
var collision_radius := 0.18
var posture_driver: RefCounted
var posture_failure := ""
var posture := "standing"
var animation_paused := false
var posture_animation_mode := AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_IDLE
var life_action_clip := ""

func configure(declaration: Dictionary) -> void:
	name = declaration.character_id
	visual = Node3D.new()
	visual.name = "Visual"
	add_child(visual)
	nominal_height = float(declaration.height)
	if not Importer.attach(visual, str(declaration.path), nominal_height, float(declaration.yaw_degrees), str(declaration.character_id)): return
	animation_player = visual.get_meta("animation_player", null) as AnimationPlayer
	collision_radius = float(visual.get_meta("collision_radius", 0.18))
	collider = CollisionShape3D.new()
	collider.name = "BodyCollider"
	var capsule := CapsuleShape3D.new()
	capsule.radius = collision_radius
	capsule.height = maxf(nominal_height, collision_radius * 2.0)
	collider.shape = capsule
	collider.position.y = capsule.height * 0.5
	add_child(collider)
	collision_layer = 0
	collision_mask = Layers.ACTOR_MOVEMENT_MASK
	safe_margin = 0.001
	if animation_player != null: animation_player.animation_finished.connect(_animation_finished)
	set_meta("character_id", declaration.character_id)
	set_meta("model_source", declaration.path)
	set_meta("nominal_height", declaration.height)
	set_meta("animation_player", animation_player)
	set_meta("skeleton", visual.get_meta("skeleton", null))

func set_motion(moving: bool, running := false) -> void:
	if posture_busy() or posture != "standing": return
	if life_action_clip != "": return
	play_pose("run" if moving and running else "walk" if moving else "idle")

func play_life_action(pose_name: String, action_name: String) -> void:
	if posture_busy() or animation_player == null: return
	var clip := ""
	if action_name in ["eat_meal", "eat_standing", "eat", "drink"]: clip = "eat"
	elif action_name in ["prepare_meal", "wash", "study", "play_piano", "paint", "tend_plant", "work", "write", "play"]: clip = "work"
	elif action_name in ["read", "return_book"]: clip = "pickup"
	elif action_name in ["talk", "request", "fulfil", "hangout", "inspect_pantry", "light_lamp", "douse_lamp"]: clip = "interact"
	elif action_name == "read_seated": clip = "read_scroll"
	elif pose_name == "lie": clip = "lie_idle"
	elif pose_name == "sit": clip = "sit_idle"
	else: clip = "idle"
	if not animation_player.has_animation(clip): clip = "idle"
	life_action_clip = clip
	play_pose(clip)

func clear_life_action() -> void:
	life_action_clip = ""

func play_pose(clip: String) -> void:
	if animation_player == null or not animation_player.has_animation(clip): return
	if animation_player.current_animation != clip or not animation_player.is_playing(): animation_player.play(clip)

func pause_animation(value: bool) -> void:
	animation_paused = value
	if animation_player != null: animation_player.speed_scale = 0.0 if value else 1.0

func posture_busy() -> bool:
	return posture_driver != null and bool(posture_driver.active)

func begin_posture(target: Node3D, declaration: Dictionary) -> bool:
	posture_failure = ""
	var destination := str(declaration.get("to", ""))
	if destination not in ["sitting", "standing"]:
		posture_failure = "physical-posture-not-supported:" + destination
		return false
	if animation_player == null or collider == null or visual == null:
		posture_failure = "physical-character-unavailable"
		return false
	var clip := "sit_down" if destination == "sitting" else "stand_up"
	if not animation_player.has_animation(clip):
		posture_failure = "posture-animation-unavailable:" + clip
		return false
	if posture_driver == null: posture_driver = SeatDriver.new()
	if not posture_driver.begin(self, target, declaration):
		posture_failure = str(posture_driver.last_start_failure)
		return false
	posture_animation_mode = animation_player.callback_mode_process
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	collision_layer = Layers.ACTOR
	play_pose(clip)
	return true

func step_posture(delta: float) -> Dictionary:
	if not posture_busy() or animation_paused: return {}
	animation_player.advance(maxf(delta, 0.0))
	var result: Dictionary = posture_driver.step(maxf(delta, 0.0))
	if result.is_empty(): return result
	animation_player.callback_mode_process = posture_animation_mode
	posture_failure = str(result.get("reason", ""))
	if bool(result.ok):
		posture = str(result.measurement.to)
		play_pose("sit_idle" if posture == "sitting" else "idle")
	elif bool(result.measurement.get("recovered_to_standing", false)):
		posture = "standing"
		play_pose("idle")
	else:
		posture = "partial"
	return result

func cancel_posture(reason: String) -> Dictionary:
	if posture_driver == null: return {}
	var result: Dictionary = posture_driver.cancel(reason)
	if not result.is_empty() and animation_player != null: animation_player.callback_mode_process = posture_animation_mode
	return result

func retry_posture_recovery() -> bool:
	return posture_driver != null and posture_driver.retry_recovery()

func move_physical(displacement: Vector3) -> Dictionary:
	if posture_busy() or posture != "standing": return {"ok":false,"reason":"posture-not-standing"}
	var before := global_position
	var hit := move_and_collide(displacement)
	var moved := global_position - before
	return {"ok":moved.distance_to(displacement) <= 0.005,"moved":moved,"collider":str(hit.get_collider().get_path()) if hit != null else ""}

func _animation_finished(clip: StringName) -> void:
	if posture_driver != null: posture_driver.notify_animation_finished(str(clip))
	if life_action_clip == str(clip): play_pose(life_action_clip)

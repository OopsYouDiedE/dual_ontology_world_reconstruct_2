extends CharacterBody3D
## Feet-origin actor. Add to the lot's SubViewport (not to rebuildable geometry).

const Visual := preload("res://scenes/rogue_crossing/Roster.gd")
const Feel := preload("res://scenes/components/shared/FeelProfile.gd")
const DEFAULT_YAW := 0.65
const DEFAULT_PITCH := 1.25
const DEFAULT_DISTANCE := 9.5
const CAMERA_HEIGHT := 1.05
const WALK_SPEED := 3.0
const SPRINT_SPEED := 5.0
const FP_BASE_FOV := 73.0

@export_flags_3d_physics var camera_collision_mask := 1
@onready var _visual: Node3D = $Visual
@onready var _camera: Camera3D = $Camera3D

var first_person := false
var first_person_fov := FP_BASE_FOV
var _animation: AnimationPlayer
var _controls := true
var _yaw := DEFAULT_YAW
var _pitch := DEFAULT_PITCH
var _distance := DEFAULT_DISTANCE
var _distance_smooth := DEFAULT_DISTANCE
var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _camera_shape := SphereShape3D.new()
var _camera_range := DEFAULT_DISTANCE
var _action: StringName = &""
var _pending_spawn := Vector3.ZERO
var _has_pending_spawn := false
var _stride := 0.0
var _bob_amp := 0.0
var _roll := 0.0
var _sprinting := false

func _ready() -> void:
	_camera_shape.radius = 0.20
	_visual.visible = not first_person
	if not first_person and Visual.attach(_visual, "detective"):
		_animation = _visual.get_meta("animation_player", null) as AnimationPlayer
		if _animation != null:
			_animation.animation_finished.connect(_on_animation_finished)
	if _animation == null and not first_person:
		push_error("RoguePlayer could not load the 6.5-head rig and animation library")
	if _has_pending_spawn:
		global_position = _pending_spawn
	_visual.rotation.y = _yaw + PI
	_camera.make_current()
	_distance_smooth = _distance
	_update_camera(0.0)

func spawn_at(world_feet: Vector3, yaw: float = NAN) -> void:
	if is_finite(yaw):
		_yaw = yaw
	if not is_node_ready():
		_pending_spawn = world_feet
		_has_pending_spawn = true
		return
	global_position = world_feet
	velocity = Vector3.ZERO
	_visual.rotation.y = _yaw + PI
	_action = &""
	_play_loop(&"idle")
	reset_physics_interpolation()
	_distance_smooth = _distance
	_camera_range = _distance
	_stride = 0.0
	_bob_amp = 0.0
	_roll = 0.0
	_update_camera(0.0)

func set_controls_enabled(enabled: bool) -> void:
	_controls = enabled
	if not enabled:
		velocity.x = 0.0
		velocity.z = 0.0

func set_first_person_framing(vertical_fov: float, pitch: float) -> void:
	first_person_fov = vertical_fov
	_pitch = pitch

func orbit_by(relative: Vector2) -> void:
	if not _controls:
		return
	_yaw = wrapf(_yaw - relative.x * (0.0032 if first_person else 0.008), -PI, PI)
	if first_person:
		_pitch = clampf(_pitch - relative.y * 0.0032, -1.40, 1.40)
	else:
		_pitch = clampf(_pitch + relative.y * 0.006, 0.18, 1.45)

func zoom_by(steps: float) -> void:
	if _controls and not first_person:
		_distance = clampf(_distance * pow(0.92, steps), 3.0, 14.0)

func camera() -> Camera3D:
	return _camera

## Run/View choose when an interaction succeeds; this only plays its visual clip.
func play_action(clip: StringName = &"interact") -> bool:
	if _animation == null or not _animation.has_animation(clip):
		return false
	if _animation.get_animation(clip).loop_mode != Animation.LOOP_NONE:
		return false
	_action = clip
	_animation.stop(true)
	_animation.play(clip, 0.10)
	return true

func snapshot() -> Dictionary:
	return {
		"position": global_position, "velocity": velocity, "grounded": is_on_floor(),
		"yaw": _yaw, "pitch": _pitch, "camera_distance": 0.0 if first_person else _camera_range,
		"animation": _animation.current_animation if _animation != null else "",
		"rig": _visual.get_meta("model_source", ""), "controls": _controls,
	}

func _physics_process(delta: float) -> void:
	var direction := Vector3.ZERO
	var sprint := false
	if _controls:
		_yaw = wrapf(_yaw + Input.get_axis("rogue_orbit_left", "rogue_orbit_right") * delta * 1.8, -PI, PI)
		if _action == &"":
			var axes := Input.get_vector("move_left", "move_right", "move_up", "move_down")
			direction = Vector3(axes.x, 0.0, axes.y).rotated(Vector3.UP, _yaw)
			sprint = Input.is_action_pressed("rogue_sprint")
	_sprinting = sprint and not direction.is_zero_approx()
	var speed := SPRINT_SPEED if sprint else WALK_SPEED
	var grounded := is_on_floor()
	var planar := Feel.step_planar_velocity(
		Vector2(velocity.x, velocity.z),
		Vector2(direction.x, direction.z) * speed,
		delta,
		grounded,
		32.0,
		58.0,
		38.0,
		Feel.AIR_CONTROL,
		false
	)
	velocity.x = planar.x
	velocity.z = planar.y
	if grounded:
		velocity.y = 0.0
	else:
		velocity.y -= _gravity * delta
	move_and_slide()
	var actual := get_real_velocity() * Vector3(1.0, 0.0, 1.0)
	if grounded and actual.length() > 0.2:
		var step_len := Feel.stride_for_stance(Feel.ST_RUN if sprint else Feel.ST_WALK)
		_stride = fmod(_stride + actual.length() * delta / step_len, 1.0)
	if not direction.is_zero_approx():
		_visual.rotation.y = lerp_angle(_visual.rotation.y, atan2(direction.x, direction.z), Feel.exp_damp(14.0, delta))
	if _action == &"":
		_play_loop((&"run" if sprint else &"walk") if actual.length_squared() > 0.02 else &"idle")
	_update_camera(delta)

func _play_loop(clip: StringName) -> void:
	if _animation != null and _animation.current_animation != clip:
		_animation.play(clip, 0.16)

func _on_animation_finished(clip: StringName) -> void:
	if clip == _action:
		_action = &""
		_play_loop(&"idle")

func _update_camera(delta: float) -> void:
	if first_person:
		var planar_speed := Vector2(velocity.x, velocity.z).length()
		var moving := is_on_floor() and planar_speed > 0.35
		_bob_amp = lerpf(_bob_amp, clampf(planar_speed / WALK_SPEED, 0.0, 1.45) if moving else 0.0, Feel.exp_damp(9.0, delta))
		var bob := -cos(TAU * _stride) * 0.014 * _bob_amp
		var local_v := Vector3(velocity.x, 0.0, velocity.z).rotated(Vector3.UP, -_yaw)
		_roll = lerpf(_roll, -clampf(local_v.x / SPRINT_SPEED, -1.0, 1.0) * 0.018, Feel.exp_damp(8.0, delta))
		_camera.global_position = global_position + Vector3.UP * (1.48 + bob)
		_camera.rotation = Vector3(_pitch, _yaw, _roll)
		var target_fov := first_person_fov + (4.5 if _sprinting else 0.0)
		_camera.fov = lerpf(_camera.fov, target_fov, Feel.exp_damp(7.0, delta)) if delta > 0.0 else target_fov
		return
	var target_dist := clampf(_distance + (0.35 if _sprinting else 0.0), 3.0, 14.0)
	_distance_smooth = target_dist if delta <= 0.0 else lerpf(_distance_smooth, target_dist, Feel.exp_damp(10.0, delta))
	var focus := global_position + Vector3.UP * CAMERA_HEIGHT
	var direction := Vector3(sin(_yaw) * cos(_pitch), sin(_pitch), cos(_yaw) * cos(_pitch))
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _camera_shape
	query.transform = Transform3D(Basis.IDENTITY, focus)
	query.motion = direction * _distance_smooth
	query.collision_mask = camera_collision_mask
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.cast_motion(query)
	var safe_range := _distance_smooth
	if not hit.is_empty() and hit[0] < 1.0:
		safe_range = maxf(0.02, _distance_smooth * hit[0] - 0.04)
	if delta <= 0.0 or safe_range < _camera_range:
		_camera_range = safe_range
	else:
		_camera_range = lerpf(_camera_range, safe_range, Feel.exp_damp(8.0, delta))
	_camera.look_at_from_position(focus + direction * _camera_range, focus, Vector3.UP)

## Initial framing preset; movement and subsequent camera input stay unchanged.
func set_room_camera(pitch: float, distance: float) -> void:
	_pitch = clampf(pitch,0.18,1.45)
	_distance = clampf(distance,3.0,14.0)
	_distance_smooth = _distance

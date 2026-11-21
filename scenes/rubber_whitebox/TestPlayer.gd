extends CharacterBody3D
## Disposable third-person controller for testing the yard's geometry.

const WALK_SPEED := 4.2
const RUN_SPEED := 6.6
const JUMP_SPEED := 5.2
const TURN_SPEED := 1.65
const ORBIT_SENSITIVITY := 0.003
const DEFAULT_DISTANCE := 6.9

@onready var rig: Node3D = $Orbit
@onready var boom: SpringArm3D = $Orbit/Boom
@onready var figure: Node3D = $Figure
@onready var left_leg: Node3D = $Figure/LeftLeg
@onready var right_leg: Node3D = $Figure/RightLeg
@onready var left_arm: Node3D = $Figure/LeftArm
@onready var right_arm: Node3D = $Figure/RightArm
var gait := 0.0
var peak_height := 0.0

func _ready() -> void:
	floor_snap_length = 0.32
	floor_constant_speed = true
	boom.add_excluded_object(get_rid())

func reset_to(spawn: Transform3D) -> void:
	global_transform = spawn
	velocity = Vector3.ZERO
	rig.rotation.y = 0.0
	boom.rotation.x = -0.35
	boom.spring_length = DEFAULT_DISTANCE
	figure.rotation.y = 0.0
	gait = 0.0
	for limb in [left_leg, right_leg, left_arm, right_arm]:
		limb.rotation.x = 0.0
	peak_height = spawn.origin.y
	reset_physics_interpolation()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		match event.button_index:
			MOUSE_BUTTON_LEFT: Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			MOUSE_BUTTON_WHEEL_UP: _zoom(-0.55)
			MOUSE_BUTTON_WHEEL_DOWN: _zoom(0.55)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rig.rotate_y(-event.screen_relative.x * ORBIT_SENSITIVITY)
		_tilt(-event.screen_relative.y * ORBIT_SENSITIVITY)

func _zoom(change: float) -> void:
	if change != 0.0:
		boom.spring_length = clampf(boom.spring_length + change, 2.25, 8.5)

func _tilt(change: float) -> void:
	if change != 0.0:
		boom.rotation.x = clampf(boom.rotation.x + change, -1.12, -0.12)

func _physics_process(delta: float) -> void:
	_zoom(Input.get_axis("whitebox_zoom_in", "whitebox_zoom_out") * 4.5 * delta)
	_tilt(Input.get_axis("whitebox_tilt_down", "whitebox_tilt_up") * TURN_SPEED * delta)
	rig.rotate_y(Input.get_axis("whitebox_orbit_right", "whitebox_orbit_left") * TURN_SPEED * delta)
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var direction := rig.basis * Vector3(input.x, 0.0, input.y)
	var speed := RUN_SPEED if Input.is_action_pressed("whitebox_sprint") else WALK_SPEED
	var horizontal := Vector2(velocity.x, velocity.z).move_toward(Vector2(direction.x, direction.z) * speed, 27.0 * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y
	if is_on_floor() and Input.is_action_just_pressed("whitebox_jump"):
		velocity.y = JUMP_SPEED
	else:
		velocity += get_gravity() * delta
	move_and_slide()
	peak_height = maxf(peak_height, position.y)
	_push_crates(direction, delta)
	if direction.length_squared() > 0.01:
		figure.rotation.y = lerp_angle(figure.rotation.y, atan2(-direction.x, -direction.z), minf(delta * 13.0, 1.0))
	_animate(delta)

func _push_crates(direction: Vector3, delta: float) -> void:
	for index in get_slide_collision_count():
		var contact := get_slide_collision(index)
		var body := contact.get_collider() as RigidBody3D
		if body and body.is_in_group("whitebox_pushable"):
			var push := -contact.get_normal().slide(Vector3.UP)
			var strength := maxf(direction.dot(push), 0.0)
			body.apply_central_impulse(push * strength * 93.0 * delta)

func _animate(delta: float) -> void:
	var actual := get_real_velocity()
	var speed := Vector2(actual.x, actual.z).length()
	gait = fmod(gait + speed * delta * 3.2, TAU)
	var swing := sin(gait) * minf(speed * 0.14, 0.72) if is_on_floor() else 0.25
	var blend := minf(delta * 15.0, 1.0)
	left_leg.rotation.x = lerpf(left_leg.rotation.x, swing, blend)
	right_leg.rotation.x = lerpf(right_leg.rotation.x, -swing, blend)
	left_arm.rotation.x = lerpf(left_arm.rotation.x, -swing * 0.65, blend)
	right_arm.rotation.x = lerpf(right_arm.rotation.x, swing * 0.65, blend)

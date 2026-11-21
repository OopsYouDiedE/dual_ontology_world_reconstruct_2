extends Node3D
## Standalone art/physics whitebox; its inputs and state stay within this scene.

const Inputs = preload("res://scenes/rubber_whitebox/WhiteboxInput.gd")
const TestPlayer = preload("res://scenes/rubber_whitebox/TestPlayer.gd")
const GATE_TRAVEL := 2.72
const RELEASE_DELAY := 2.2

@onready var player: TestPlayer = $TestPlayer
@onready var spawn: Marker3D = $Spawn
@onready var crate: RigidBody3D = $Equipment/PushBlock
@onready var gate: AnimatableBody3D = $Equipment/Gate
@onready var pad: Area3D = $Equipment/PressurePad
@onready var clearance: Area3D = $Equipment/GateClearance
@onready var pad_top: MeshInstance3D = $Equipment/PressurePad/Top
@onready var signal_lamp: MeshInstance3D = $Equipment/GateFrame/Signal
@onready var state_label: Label = $HUD/GateStatus/State
@onready var hud: CanvasLayer = $HUD
var crate_spawn: Transform3D
var gate_home: Vector3
var pad_home: Vector3
var plate_occupied := false
var gate_hold := 0.0
var lift := 0.0
var ignore_pad_frames := 0
var lamp: StandardMaterial3D
var previous_taa := false

func _ready() -> void:
	previous_taa = get_viewport().use_taa
	if RenderingServer.get_current_rendering_method() == "forward_plus":
		# Accumulate the soft shadows and subpixel floor relief at native resolution.
		get_viewport().use_taa = true
	crate_spawn = crate.global_transform
	gate_home = gate.position
	pad_home = pad_top.position
	lamp = signal_lamp.material_override.duplicate() as StandardMaterial3D
	signal_lamp.material_override = lamp
	Inputs.install()
	_reset()

func _exit_tree() -> void:
	get_viewport().use_taa = previous_taa

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("whitebox_reset") or player.position.y < -3.0:
		_reset()
	if Input.is_action_just_pressed("whitebox_hud"):
		hud.visible = not hud.visible
	if ignore_pad_frames > 0:
		ignore_pad_frames -= 1
	else:
		plate_occupied = pad.has_overlapping_bodies()
		gate_hold = RELEASE_DELAY if plate_occupied else maxf(gate_hold - delta, 0.0)
	var opening := _gate_requested()
	lift = move_toward(lift, 1.0 if opening else 0.0, delta * (1.85 if opening else 1.1))
	gate.position = gate_home + Vector3.UP * GATE_TRAVEL * lift
	var pad_target := pad_home.y - (0.040 if plate_occupied else 0.0)
	pad_top.position.y = move_toward(pad_top.position.y, pad_target, delta * 0.35)
	var tint := Color("b5ecab") if opening else Color("ffc47b")
	lamp.albedo_color = tint
	lamp.emission = tint
	state_label.modulate = tint
	state_label.text = _gate_state().to_upper()

func _reset() -> void:
	player.reset_to(spawn.global_transform)
	# Reset the rigid body's physics state as well as its scene transform.
	crate.global_transform = crate_spawn
	PhysicsServer3D.body_set_state(crate.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, crate_spawn)
	crate.linear_velocity = Vector3.ZERO
	crate.angular_velocity = Vector3.ZERO
	crate.sleeping = false
	crate.reset_physics_interpolation()
	plate_occupied = false
	gate_hold = 0.0
	lift = 0.0
	ignore_pad_frames = 2
	gate.position = gate_home
	pad_top.position = pad_home

func _gate_requested() -> bool:
	# Preserve the opening while a player or crate is in the moving gate’s path.
	return gate_hold > 0.0 or (lift > 0.0 and clearance.has_overlapping_bodies())

func _gate_state() -> String:
	if lift >= 1.0:
		return "Open"
	if _gate_requested():
		return "Lifting"
	if lift > 0.0:
		return "Closing"
	return "Standby"

func mcp_observe() -> Dictionary:
	return {
		"player": [player.position.x, player.position.y, player.position.z],
		"grounded": player.is_on_floor(), "peak_height": player.peak_height,
		"orbit": player.rig.rotation.y, "camera_distance": player.boom.spring_length,
		"camera_pitch": player.boom.rotation.x,
		"plate_occupied": plate_occupied, "gate": _gate_state(), "gate_lift": lift,
		"block": [crate.position.x, crate.position.y, crate.position.z],
	}

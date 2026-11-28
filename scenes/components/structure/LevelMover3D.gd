@tool
class_name LevelMover3D
extends "res://scenes/components/structure/StructurePiece3D.gd"
## Moves its authored children between a rest pose and an "open" pose: gates, lifts,
## drawbridges, sliding shelves, swinging doors. Put the moving pieces under it, set the
## open offset / rotation, and drive it from a trigger (MoverAction) or a script
## (open / close / toggle / play). `preview` scrubs the motion in the editor without
## changing anything that is saved.

signal motion_finished(is_open: bool)

enum Mode { ONE_SHOT, PING_PONG_LOOP }

## Offset of the open pose (local axes of this node).
@export var open_offset := Vector3(0, 2.5, 0):
	set(v): open_offset = v; _pose(preview)
## Rotation of the open pose, degrees, about this node's origin (e.g. a door hinge).
@export var open_rotation_degrees := Vector3.ZERO:
	set(v): open_rotation_degrees = v; _pose(preview)
@export_range(0.05, 60.0, 0.05) var duration := 1.5
@export var transition: Tween.TransitionType = Tween.TRANS_SINE
@export var easing: Tween.EaseType = Tween.EASE_IN_OUT
@export var mode: Mode = Mode.ONE_SHOT
@export var autoplay := false
@export var start_open := false
## Editor only: scrub between rest (0) and open (1).
@export_range(0.0, 1.0, 0.01) var preview := 0.0:
	set(v): preview = v; _pose(v)
## Footprint shown on the plan (x, z).
@export var plan_size := Vector2(2, 0.4):
	set(v): plan_size = v; shape_changed()

var is_open := false
var _t := 0.0
var _tween: Tween
var _rest := {}  # child instance id -> rest transform (never saved)

func plan_kind() -> String:
	return "mover"

func shape_key() -> Array:
	return [plan_size]

func plan_outline() -> PackedVector2Array:
	var h := plan_size * 0.5
	return PackedVector2Array([to_plan(Vector3(-h.x, 0, -h.y)), to_plan(Vector3(h.x, 0, -h.y)), to_plan(Vector3(h.x, 0, h.y)), to_plan(Vector3(-h.x, 0, h.y))])

## Outline of the open pose (dashed on the plan).
func plan_open_outline() -> PackedVector2Array:
	var h := plan_size * 0.5
	var xf := _open_transform()
	var out := PackedVector2Array()
	for p in [Vector3(-h.x, 0, -h.y), Vector3(h.x, 0, -h.y), Vector3(h.x, 0, h.y), Vector3(-h.x, 0, h.y)]:
		out.append(to_plan(xf * p))
	return out

func _open_transform() -> Transform3D:
	var r := open_rotation_degrees * (PI / 180.0)
	return Transform3D(Basis.from_euler(r), open_offset)

func rebuild() -> void:
	pass

func _ready() -> void:
	super._ready()
	if Engine.is_editor_hint():
		_pose(preview)
		return
	_pose(1.0 if start_open else 0.0)
	is_open = start_open
	if autoplay:
		play()

## Pose the authored children at t (0 = rest, 1 = open). Rest transforms are remembered
## in memory only; before the editor saves, the children go back to rest.
func _pose(t: float) -> void:
	_t = clampf(t, 0.0, 1.0)
	if not is_inside_tree():
		return
	var xf := Transform3D.IDENTITY.interpolate_with(_open_transform(), _t)
	magnet_suspended = true
	for child in get_children():
		if not (child is Node3D) or is_generated(child):
			continue
		var id := child.get_instance_id()
		if not _rest.has(id):
			_rest[id] = child.transform
		child.transform = xf * _rest[id]
		if _t == 0.0:
			_rest.erase(id)
	magnet_suspended = false

# (GDScript calls _notification on every script of the chain: no super call here.)
func _notification(what: int) -> void:
	if what == NOTIFICATION_EDITOR_PRE_SAVE and _t > 0.0:
		var keep := _t
		_pose(0.0)
		_t = keep
	elif what == NOTIFICATION_EDITOR_POST_SAVE and _t > 0.0:
		_pose(_t)

func open() -> void:
	_go(1.0)

func close() -> void:
	_go(0.0)

func toggle() -> void:
	_go(0.0 if is_open else 1.0)

## ONE_SHOT: toggle once. PING_PONG_LOOP: keep swinging until stop().
func play() -> void:
	if mode == Mode.PING_PONG_LOOP:
		_loop()
	else:
		toggle()

func stop() -> void:
	if _tween:
		_tween.kill()

func _go(target: float) -> void:
	is_open = target > 0.5
	if _tween:
		_tween.kill()
	if not is_inside_tree():
		_pose(target)
		return
	_tween = create_tween()
	_tween.tween_method(_pose, _t, target, duration * absf(target - _t)).set_trans(transition).set_ease(easing)
	_tween.finished.connect(func(): motion_finished.emit(is_open))

func _loop() -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween().set_loops()
	_tween.tween_method(_pose, 0.0, 1.0, duration).set_trans(transition).set_ease(easing)
	_tween.tween_method(_pose, 1.0, 0.0, duration).set_trans(transition).set_ease(easing)

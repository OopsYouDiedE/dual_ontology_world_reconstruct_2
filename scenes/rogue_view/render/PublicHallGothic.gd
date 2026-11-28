@tool
extends Node3D
## The Public Hall: the root of the hall's editable components inside the level structure
## (scenes/levels/structures/public_nave.tscn → PublicHallGothic). Everything visible —
## vault, piers, lancet bays, gables and roses, oculi, paving, lamps, pendulum, furniture —
## is a component node under here (scenes/components/hall/*): move, add, delete and tune
## them in the Godot editor. This node only gathers gameplay data from them and forwards
## time of day / pendulum state. Nothing here builds geometry.

const Pendulum := preload("res://scenes/components/hall/FoucaultPendulum3D.gd")

## Gameplay points (structure space), read from LevelAnchor3D nodes and the pendulum.
var watch_cot_pos := Vector3.ZERO
var pendulum_world_pos := Vector3.ZERO
var north_gate_pos := Vector3.ZERO
var lectern_pos := Vector3.ZERO
var spawn_pos := Vector3.ZERO
## Footprints that block walking (furniture, lamps, arch cheeks), structure space.
var station_bounds: Array[Rect2] = []

var drifting: bool:
	get: return _pendulum.drifting if _pendulum else true
	set(v): set_drift_state(v)
var pendulum_pivot: Node3D:
	get: return _pendulum.pendulum_pivot if _pendulum else null
var pendulum_bob: Node3D:
	get: return _pendulum.pendulum_bob if _pendulum else null
var drift_bezel: MeshInstance3D:
	get: return _pendulum.drift_bezel if _pendulum else null
var essence_light: OmniLight3D:
	get: return _pendulum.essence_light if _pendulum else null

var _pendulum: Node3D
var _structure: Node3D

func _ready() -> void:
	refresh()

## Re-read anchors, pendulum and stations (after editing the scene).
func refresh() -> void:
	_structure = get_parent()
	while _structure != null and not (_structure is LevelStructure3D):
		_structure = _structure.get_parent()
	_pendulum = null
	for n in find_children("*", "", true, false):
		if n.get_script() == Pendulum:
			_pendulum = n
			break
	if _structure == null:
		return
	pendulum_world_pos = _structure.relative(_pendulum).origin if _pendulum else Vector3.ZERO
	watch_cot_pos = _structure.anchor("cot", pendulum_world_pos)
	north_gate_pos = _structure.anchor("north_gate", pendulum_world_pos)
	lectern_pos = _structure.anchor("lectern", pendulum_world_pos)
	spawn_pos = _structure.anchor("spawn", pendulum_world_pos)
	station_bounds = _structure.station_bounds()

func pendulum() -> Node3D:
	return _pendulum

## Dial cells (no floor tiles there); empty without a pendulum.
func well_rect() -> Rect2i:
	return _pendulum.well_rect() if _pendulum else Rect2i()

func pieces() -> Array:
	return find_children("*", "", true, false).filter(func(n): return n.has_method("apply_hour"))

func set_hour(hour: float) -> void:
	for piece in pieces():
		piece.apply_hour(hour)

func set_drift_state(is_drifting: bool) -> void:
	if _pendulum:
		_pendulum.set_drift_state(is_drifting)

func get_pendulum_period_sec() -> float:
	return _pendulum.get_pendulum_period_sec() if _pendulum else 7.0

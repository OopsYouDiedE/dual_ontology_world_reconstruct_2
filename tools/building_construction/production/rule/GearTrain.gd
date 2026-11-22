@tool
extends "res://scenes/blue_prince_lab/gears/Gears.gd"
## Catalog gear train: reuse the hall's wheel profile and bearing geometry,
## with tooth counts driving the pitch centers, ratio and backlash together.

@export_range(18, 36, 1) var driver_teeth := DRIVER_TEETH:
	set(value):
		driver_teeth = clampi(value, 18, 36)
		_queue_regeneration()
@export_range(18, 36, 1) var follower_teeth := FOLLOWER_TEETH:
	set(value):
		follower_teeth = clampi(value, 18, 36)
		_queue_regeneration()

const CATALOG_BACKLASH_FRACTION := 0.03
var _catalog_flank_offset := 0.0
var _regeneration_pending := false

func _queue_regeneration() -> void:
	if not is_inside_tree() or _regeneration_pending: return
	_regeneration_pending = true
	_regenerate.call_deferred()

func _regenerate() -> void:
	_regeneration_pending = false
	if is_instance_valid(_generated): _generated.free()
	_ready()

func _phase() -> float:
	return MESH_ANGLE + PI - PI / follower_teeth

func _lash() -> float:
	return PI * CATALOG_BACKLASH_FRACTION / follower_teeth

func _ready() -> void:
	_generated = Node3D.new()
	_generated.name = "Mechanism"
	add_child(_generated)
	_brass = _metal(Color("a38959"), 0.62, 0.49)
	_edge = _metal(Color("c2a776"), 0.68, 0.42)
	_iron = _metal(Color("454e4b"), 0.56, 0.57)
	_slate = _metal(Color("333e47"), 0.18, 0.77)
	_box(_generated, "Backplate", Vector3(0.0, 0.75, 0.038), Vector3(1.94, 1.40, 0.076), _slate)
	for y in [0.064, 1.436]:
		_box(_generated, "Moulding", Vector3(0.0, y, 0.079), Vector3(1.98, 0.04, 0.042), _iron)
	for x in [-0.914, 0.914]:
		for y in [0.112, 1.388]:
			_cylinder(_generated, "Plate bolt", Vector3(x, y, 0.092), 0.022, 0.027, 6, _edge)
	var a := Vector3(-0.39, 0.73, 0.255)
	var pitch_distance := MODULE * (driver_teeth + follower_teeth) * 0.5
	var b := a + Vector3(cos(MESH_ANGLE), sin(MESH_ANGLE), 0.0) * pitch_distance
	_driver = _wheel("Driver", a, driver_teeth, 6)
	_follower = _wheel("Follower", b, follower_teeth, 5)
	driver_angle = MESH_ANGLE
	_catalog_flank_offset = _lash()
	follower_angle = _phase() + _catalog_flank_offset
	_apply_angles()

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_running: return
	var ratio := float(driver_teeth) / follower_teeth
	var cycles := follower_teeth / float(_gcd(driver_teeth, follower_teeth))
	var advance := delta * driver_rad_per_second
	_catalog_flank_offset = clampf(_catalog_flank_offset + advance * ratio, -_lash(), _lash())
	var travel := fposmod(driver_angle - MESH_ANGLE + advance, TAU * cycles)
	driver_angle = MESH_ANGLE + travel
	follower_angle = _phase() - travel * ratio + _catalog_flank_offset
	_apply_angles()

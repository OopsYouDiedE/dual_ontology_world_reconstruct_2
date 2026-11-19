@tool
extends Node3D
## Standalone wall-mounted gear train. +Z is the display side; Y=0 is mounting datum.
signal running_changed(active: bool)

const DRIVER_TEETH := 30
const FOLLOWER_TEETH := 22
const MODULE := 0.035
const PRESSURE := PI / 9.0
const MESH_ANGLE := 0.20
const CENTER_DISTANCE := MODULE * (DRIVER_TEETH + FOLLOWER_TEETH) / 2.0
const FOLLOWER_PHASE := MESH_ANGLE + PI - PI / FOLLOWER_TEETH

@export var driver_rad_per_second: float = 0.65
var is_running: bool = false
var driver_angle: float = MESH_ANGLE
var follower_angle: float = FOLLOWER_PHASE

var _driver: Node3D
var _follower: Node3D
var _generated: Node3D
var _brass: StandardMaterial3D
var _edge: StandardMaterial3D
var _iron: StandardMaterial3D
var _slate: StandardMaterial3D

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
	var b := a + Vector3(cos(MESH_ANGLE), sin(MESH_ANGLE), 0.0) * CENTER_DISTANCE
	_driver = _wheel("Driver", a, DRIVER_TEETH, 6)
	_follower = _wheel("Follower", b, FOLLOWER_TEETH, 5)
	_apply_angles()

## Toggle from your room's interaction system. Returns the resulting state.
func interact() -> bool:
	is_running = not is_running
	running_changed.emit(is_running)
	return is_running

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint() or not is_running:
		return
	# Eleven driver revolutions give exactly fifteen follower revolutions.
	var cycles := FOLLOWER_TEETH / float(_gcd(DRIVER_TEETH, FOLLOWER_TEETH))
	var travel := fposmod(driver_angle - MESH_ANGLE + delta * driver_rad_per_second, TAU * cycles)
	driver_angle = MESH_ANGLE + travel
	follower_angle = FOLLOWER_PHASE - travel * DRIVER_TEETH / FOLLOWER_TEETH
	_apply_angles()

func _apply_angles() -> void:
	_driver.rotation.z = driver_angle
	_follower.rotation.z = follower_angle

static func _gcd(a: int, b: int) -> int:
	while b != 0:
		var remainder := a % b
		a = b
		b = remainder
	return a

## Approximate a 20° involute with three segments per flank, a small backlash,
## and a radial transition into the dedendum where the involute is undefined.
static func tooth_outline(teeth: int) -> PackedVector2Array:
	var pitch := MODULE * teeth * 0.5
	var base := pitch * cos(PRESSURE)
	var root_radius := pitch - 1.25 * MODULE
	var tip := pitch + MODULE
	var half_width := PI * 0.47 / teeth
	var step := TAU / teeth
	var points := PackedVector2Array()
	for i in range(teeth):
		var center := i * step
		points.append(Vector2.from_angle(center - step * 0.5) * root_radius)
		for flank in [-1, 1]:
			for j in range(5):
				var k := j if flank < 0 else 4 - j
				var radius := root_radius if k == 0 else lerpf(maxf(base, root_radius + 0.001), tip, (k - 1) / 3.0)
				var phi := acos(clampf(base / radius, 0.0, 1.0))
				var width := half_width + tan(PRESSURE) - PRESSURE - (tan(phi) - phi)
				points.append(Vector2.from_angle(center + flank * width) * radius)
	return points

func _wheel(label_text: String, center: Vector3, teeth: int, spokes: int) -> Node3D:
	var radius := MODULE * teeth * 0.5
	_cylinder(_generated, label_text + " bearing flange", Vector3(center.x, center.y, 0.108), 0.104, 0.068, 12, _iron)
	_cylinder(_generated, label_text + " fixed axle", Vector3(center.x, center.y, 0.233), 0.039, 0.242, 12, _iron)
	var pivot := Node3D.new()
	pivot.name = label_text
	pivot.position = center
	_generated.add_child(pivot)
	var ring := MeshInstance3D.new()
	ring.name = "Beveled involute rim"
	ring.mesh = _rim_mesh(tooth_outline(teeth), radius - 0.103)
	pivot.add_child(ring)
	for i in range(spokes):
		var angle := TAU * i / spokes
		var inner := 0.067
		var outer := radius - 0.091
		var at := Vector2.from_angle(angle) * (inner + outer) * 0.5
		var spoke := _box(pivot, "Cast spoke", Vector3(at.x, at.y, 0.0), Vector3(outer - inner, 0.057, 0.052), _brass)
		spoke.rotation.z = angle
		var pin := Vector2.from_angle(angle) * (radius - 0.082)
		_cylinder(pivot, "Spoke rivet", Vector3(pin.x, pin.y, 0.047), 0.012, 0.012, 8, _iron)
	_cylinder(pivot, "Hub", Vector3.ZERO, 0.086, 0.121, 16, _brass)
	_cylinder(pivot, "Thrust washer", Vector3(0.0, 0.0, 0.067), 0.058, 0.022, 16, _edge)
	_cylinder(_generated, label_text + " retaining nut", center + Vector3(0.0, 0.0, 0.104), 0.046, 0.035, 6, _iron)
	_box(pivot, "Timing index", Vector3(radius - 0.063, 0.0, 0.047), Vector3(0.035, 0.012, 0.004), _edge)
	return pivot

func _rim_mesh(outline: PackedVector2Array, inner: float) -> ArrayMesh:
	var result := ArrayMesh.new()
	var main := SurfaceTool.new()
	var bevel := SurfaceTool.new()
	main.begin(Mesh.PRIMITIVE_TRIANGLES)
	bevel.begin(Mesh.PRIMITIVE_TRIANGLES)
	main.set_material(_brass)
	bevel.set_material(_edge)
	for i in range(outline.size()):
		var a := outline[i]
		var b := outline[(i + 1) % outline.size()]
		var ai := a.normalized() * inner
		var bi := b.normalized() * inner
		var af := a - a.normalized() * 0.005
		var bf := b - b.normalized() * 0.005
		# Godot front faces are clockwise when seen from outside.
		_quad(main, _v(ai, 0.044), _v(bi, 0.044), _v(bf, 0.044), _v(af, 0.044))
		_quad(main, _v(bi, -0.044), _v(ai, -0.044), _v(af, -0.044), _v(bf, -0.044))
		_quad(bevel, _v(af, 0.044), _v(bf, 0.044), _v(b, 0.039), _v(a, 0.039))
		_quad(bevel, _v(bf, -0.044), _v(af, -0.044), _v(a, -0.039), _v(b, -0.039))
		_quad(main, _v(a, 0.039), _v(b, 0.039), _v(b, -0.039), _v(a, -0.039))
		_quad(main, _v(bi, 0.044), _v(ai, 0.044), _v(ai, -0.044), _v(bi, -0.044))
	main.commit(result)
	bevel.commit(result)
	return result

static func _v(p: Vector2, z: float) -> Vector3:
	return Vector3(p.x, p.y, z)

static func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_triangle(surface, a, b, c)
	_triangle(surface, a, c, d)

static func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var cross := (c - a).cross(b - a)
	if cross.length_squared() < 1e-17:
		return
	var normal := cross.normalized()
	for p in [a, b, c]:
		surface.set_normal(normal)
		surface.add_vertex(p)

static func _metal(color: Color, metallic: float, roughness: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.metallic = metallic
	material.roughness = roughness
	return material

static func _box(parent: Node3D, label_text: String, at: Vector3, size: Vector3, material: Material) -> MeshInstance3D:
	var shape := BoxMesh.new()
	shape.size = size
	return _part(parent, label_text, at, shape, material)

static func _cylinder(parent: Node3D, label_text: String, at: Vector3, radius: float, height: float, segments: int, material: Material) -> MeshInstance3D:
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = height
	shape.radial_segments = segments
	shape.rings = 0
	var part := _part(parent, label_text, at, shape, material)
	part.rotation.x = PI / 2.0
	return part

static func _part(parent: Node3D, label_text: String, at: Vector3, shape: Mesh, material: Material) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.name = label_text
	part.mesh = shape
	part.material_override = material
	part.position = at
	parent.add_child(part)
	return part

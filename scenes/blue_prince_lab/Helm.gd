extends Node3D
## Full 3D, original eight-spoke helm. Rotation axis is Z; pedestal is at ground level.
const SPOKES := 8
const RIM_RADIUS := 0.48
const AXLE_HEIGHT := 1.15
const GRIP_TIP := 0.65
var angle := 0.0
var _goal := 0.0
var _rotor := Node3D.new()
var _wood := _finish(Color("6e4738"), 0.0, 0.52)
var _endgrain := _finish(Color("a37555"), 0.0, 0.48)
var _bronze := _finish(Color("c09c64"), 0.58, 0.39)
var _iron := _finish(Color("3d4749"), 0.4, 0.65)

func _ready() -> void:
	_lathe(self, Vector3.ZERO, [[0.35,0.00],[0.34,0.07],[0.26,0.13],[0.18,0.18],
		[0.16,0.25],[0.135,0.78],[0.19,0.96],[0.18,1.12],[0.12,1.29],[0.0,1.30]], _iron, 12)
	add_child(_rotor)
	_rotor.position = Vector3(0, AXLE_HEIGHT, 0.19)
	_lathe(_rotor, Vector3.ZERO, [[0.116,-0.11],[0.136,-0.08],[0.136,0.08],
		[0.118,0.112],[0.0,0.112]], _bronze, 20, Vector3.BACK)
	for z: float in [-0.036, 0.036]:
		_ring(RIM_RADIUS, 0.047, z, _wood)
		_ring(RIM_RADIUS + 0.023, 0.008, z * 2.5, _endgrain)
	for i in range(SPOKES):
		var phase := TAU * i / SPOKES
		var direction := Vector3(sin(phase), cos(phase), 0)
		_lathe(_rotor, Vector3.ZERO, [[0.035,0.12],[0.042,0.17],[0.030,0.19],
			[0.030,0.28],[0.041,0.32],[0.027,0.39],[0.026,0.54],
			[0.043,0.57],[0.043,0.61],[0.032,0.636],[0.0,GRIP_TIP]], _wood, 10, direction)
		_lathe(_rotor, direction * 0.54, [[0.034,0.0],[0.035,0.025]], _bronze, 10, direction)
		_lathe(_rotor, direction * 0.084 + Vector3.BACK * 0.108,
			[[0.013,0.0],[0.013,0.009],[0.0,0.012]], _iron, 6, Vector3.BACK)
	var body := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.height = 1.36
	shape.radius = 0.34
	collider.shape = shape
	collider.position.y = 0.68
	body.add_child(collider)
	add_child(body)

func interact() -> void:
	_goal += TAU / SPOKES

func _physics_process(delta: float) -> void:
	angle = move_toward(angle, _goal, delta * 1.35)
	_rotor.rotation.z = angle

func _finish(tone: Color, metal: float, roughness: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tone
	m.metallic = metal
	m.roughness = roughness
	return m

func _ring(radius: float, thickness: float, z: float, mat: Material) -> void:
	var tube := TorusMesh.new()
	tube.inner_radius = radius - thickness
	tube.outer_radius = radius + thickness
	tube.rings = 40
	tube.ring_segments = 8
	var instance := MeshInstance3D.new()
	instance.mesh = tube
	instance.material_override = mat
	instance.rotation.x = PI / 2.0
	instance.position.z = z
	instance.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC
	_rotor.add_child(instance)

func _lathe(parent: Node3D, p: Vector3, profile: Array, mat: Material, slices: int, axis := Vector3.UP) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(slices):
		var a := TAU * float(i) / slices
		var b := TAU * float(i + 1) / slices
		for j in range(profile.size() - 1):
			var low: Array = profile[j]
			var high: Array = profile[j + 1]
			var x := Vector3(cos(a) * low[0], low[1], sin(a) * low[0])
			var y := Vector3(cos(b) * low[0], low[1], sin(b) * low[0])
			var z := Vector3(cos(b) * high[0], high[1], sin(b) * high[0])
			var w := Vector3(cos(a) * high[0], high[1], sin(a) * high[0])
			for points: Array in [[x,y,z],[x,z,w]]:
				var normal: Vector3 = (points[2] - points[0]).cross(points[1] - points[0]).normalized()
				if normal.is_zero_approx(): continue
				for v: Vector3 in points:
					surface.set_normal(normal)
					surface.add_vertex(v)
	var instance := MeshInstance3D.new()
	instance.mesh = surface.commit()
	instance.material_override = mat
	instance.position = p
	instance.quaternion = Quaternion(Vector3.UP, axis)
	instance.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC if parent == _rotor else GeometryInstance3D.GI_MODE_STATIC
	parent.add_child(instance)

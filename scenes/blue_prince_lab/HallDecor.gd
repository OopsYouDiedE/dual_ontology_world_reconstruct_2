extends Node3D
## Original faceted academy busts and pendant lights. Assembled locally for Blender export.
const TRIM := Color("788187")
const FACE := Color("aab4ba")
const EDGE := Color("4e5d67")
const METAL := Color("827152")
const LOCATIONS := [4.0, 0.42, -3.13]

func _ready() -> void:
	for side: float in [-1.0, 1.0]:
		for i in range(LOCATIONS.size()):
			var figure := Node3D.new()
			figure.name = "Founder"
			figure.position = Vector3(side * (3.90 if i == 0 else 3.69), 0.0, LOCATIONS[i])
			figure.rotation.y = -side * (0.83 + 0.08 * i)
			figure.scale = Vector3(0.64, 0.99, 0.72) if i == 0 else Vector3(0.85, 0.97, 0.89)
			add_child(figure)
			_bust(figure, i + (0 if side < 0.0 else 3))
		_pointing_hand(side)
		for z: float in [3.21, -0.36, -3.91]:
			var fixture := Node3D.new()
			fixture.position = Vector3(side * (2.56 if z > 0.0 else 1.91), 4.64 if z > 0.0 else 4.50, z)
			add_child(fixture)
			_pendant(fixture)

func _pointing_hand(side: float) -> void:
	var hand := Node3D.new()
	hand.name = "StoneWayfinder"
	hand.position = Vector3(side * 1.42, 1.014, -8.58)
	hand.rotation.y = side * PI * 0.5
	add_child(hand)
	_block(hand, Vector3(0,0.038,0.025), Vector3(0.47,0.076,0.18), TRIM)
	# Hand along local -Z; the pointed index faces the doorway on both plinths.
	_finger(hand, Vector3(0,0.13,0.177), Vector3(0,0.15,0.044), 0.108,0.080)
	_finger(hand, Vector3(0,0.15,0.053), Vector3(0,0.18,-0.122), 0.079,0.089)
	_finger(hand, Vector3(side*0.048,0.207,-0.07), Vector3(side*0.046,0.219,-0.295),0.036,0.028)
	_finger(hand, Vector3(side*0.046,0.219,-0.285), Vector3(side*0.039,0.204,-0.393),0.028,0.010)
	for i in range(3):
		var x: float = side * (0.009 - 0.041 * i)
		var knuckle := Vector3(x, 0.166 - i * 0.015, -0.192 + i * 0.013)
		_finger(hand, Vector3(x,0.175 + i * 0.006,-0.07), knuckle,0.031,0.029)
		_finger(hand, knuckle, Vector3(x,0.113,-0.122 + i * 0.013),0.028,0.017)
	_finger(hand, Vector3(side*0.057,0.133,0.011), Vector3(side*0.112,0.117,-0.092),0.038,0.025)

func _finger(n: Node3D, a: Vector3, b: Vector3, base: float, tip: float) -> void:
	var piece := _cylinder(n, (a+b)*0.5, tip, base, a.distance_to(b) + 0.012, FACE, 8)
	piece.quaternion = Quaternion(Vector3.UP, a.direction_to(b))

func _bust(n: Node3D, variant: int) -> void:
	_lathe(n, [[0.48,0.0],[0.48,0.09],[0.45,0.13],[0.45,0.16],[0.40,0.20]], TRIM, 12)
	_lathe(n, [[0.391,0.19],[0.368,1.14],[0.42,1.18],[0.42,1.22]], FACE, 12)
	_lathe(n, [[0.44,1.2],[0.48,1.24],[0.48,1.36],[0.44,1.40],[0.27,1.48],[0.24,1.52]], TRIM, 12)
	for i in range(12):
		var a := (i + 0.5) * TAU / 12.0
		var rod := _cylinder(n, Vector3(cos(a),0,sin(a))*0.367+Vector3.UP*0.67, 0.022, 0.031, 0.93, EDGE, 4)
		rod.rotation.z = cos(a) * 0.019
	# Profile sections add a neck, shoulder line, jaw, cheek planes, temples and cropped crown.
	_form(n, [[1.48,0.24,0.20,0.0],[1.56,0.30,0.23,0.0],[1.73,0.47,0.25,0.0],
		[1.97,0.55,0.26,0.0],[2.03,0.48,0.23,-0.01],[2.13,0.22,0.16,0.01],
		[2.28,0.141,0.137,0.005]], FACE)
	var head := Node3D.new()
	head.rotation.y = -0.15 + 0.13 * (variant % 3)
	head.scale.x = 0.92 + 0.06 * (variant % 4)
	n.add_child(head)
	_form(head, [[2.13,0.132,0.139,0.018],[2.205,0.143,0.158,0.051],
		[2.29,0.180,0.17,0.034],[2.39,0.202,0.172,0.018],[2.52,0.200,0.180,0.002],
		[2.62,0.165,0.153,-0.025],[2.675,0.10,0.096,-0.032],[2.682,0.0,0.0,-0.032]], FACE)
	_form(head, [[2.33,0.049,0.025,0.183],[2.365,0.062,0.059,0.182],
		[2.40,0.041,0.059,0.175],[2.477,0.030,0.023,0.172]], TRIM)
	for side: float in [-1.0, 1.0]:
		var brow := _block(head, Vector3(side*0.081,2.458,0.171), Vector3(0.086,0.025,0.046), TRIM)
		brow.rotation.z = side * 0.14
		var eye := _block(head, Vector3(side*0.084,2.432,0.169), Vector3(0.058,0.011,0.026), EDGE)
		eye.rotation.y = side * 0.23
		_cylinder(head, Vector3(side*0.192,2.391,0.008), 0.032, 0.036, 0.097, TRIM, 6)
		var lapel := _block(n, Vector3(side*0.17,1.999,0.202), Vector3(0.105,0.29,0.05), TRIM)
		lapel.rotation.z = -side * (0.48 + (variant % 3) * 0.13)
	_block(head, Vector3(0,2.292,0.198), Vector3(0.085,0.009,0.020), EDGE)
	_block(n, Vector3(0,1.32,0.450), Vector3(0.33,0.086,0.049), FACE)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.46
	shape.height = 1.44
	col.shape = shape
	col.position.y = 0.72
	body.add_child(col)
	n.add_child(body)

func _pendant(n: Node3D) -> void:
	_cylinder(n, Vector3(0,1.91,0), 0.012,0.012,2.76, METAL, 5)
	_lathe(n, [[0.045,-0.52],[0.125,-0.49],[0.13,-0.44],[0.07,-0.39]], METAL, 8)
	_lathe(n, [[0.10,0.48],[0.27,0.37],[0.28,0.31]] , METAL, 8, true)
	_form(n, [[-0.47,0.05,0.05,0.0],[-0.31,0.18,0.18,0.0],[-0.05,0.28,0.28,0.0],
		[0.24,0.31,0.31,0.0],[0.36,0.26,0.26,0.0],[0.43,0.12,0.12,0.0]], Color("ffefc9"), true)
	for i in range(8):
		var bearing := TAU * (float(i) + 0.5) / 8.0
		var radial := Vector3(cos(bearing),0,sin(bearing))
		var low := Vector3.DOWN*0.43 + radial*0.084
		var tip := Vector3.DOWN*0.29 + radial*0.196
		var middle := Vector3.DOWN*0.029 + radial*0.302
		var shoulder := Vector3.UP*0.239 + radial*0.328
		var top := Vector3.UP*0.37 + radial*0.265
		_rod(n, low, tip, METAL)
		_rod(n, tip, middle, METAL)
		_rod(n, middle, shoulder, METAL)
		_rod(n, shoulder, top, METAL)
	var light := OmniLight3D.new()
	light.light_color = Color("ffdda7")
	light.light_energy = 0.17
	light.omni_range = 3.0
	light.omni_attenuation = 2.25
	n.add_child(light)

func _rod(n: Node3D, from: Vector3, to: Vector3, color: Color) -> void:
	var piece := _cylinder(n, (from+to)*0.5, 0.014, 0.014, from.distance_to(to), color, 5)
	piece.quaternion = Quaternion(Vector3.UP, from.direction_to(to))

func _block(n: Node3D, p: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _piece(n, p, mesh, color)

func _cylinder(n: Node3D, p: Vector3, top: float, base: float, h: float, color: Color, sides: int) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = base
	mesh.height = h
	mesh.radial_segments = sides
	return _piece(n, p, mesh, color)

func _lathe(n: Node3D, rings: Array, color: Color, sides: int, flip := false) -> void:
	var profile := []
	if flip: rings.reverse()
	for ring: Array in rings: profile.append([ring[1],ring[0],ring[0],0.0])
	_form(n, profile, color, false, sides)

func _form(n: Node3D, profile: Array, color: Color, light := false, sides := 8) -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(sides):
		var a := TAU*(i+0.5)/sides
		var b := TAU*(i+1.5)/sides
		for j in range(profile.size()-1):
			var lo: Array = profile[j]
			var hi: Array = profile[j+1]
			var v0 := Vector3(cos(a)*lo[1],lo[0],sin(a)*lo[2]+lo[3])
			var v1 := Vector3(cos(b)*lo[1],lo[0],sin(b)*lo[2]+lo[3])
			var v2 := Vector3(cos(b)*hi[1],hi[0],sin(b)*hi[2]+hi[3])
			var v3 := Vector3(cos(a)*hi[1],hi[0],sin(a)*hi[2]+hi[3])
			for face: Array in [[v0,v1,v2],[v0,v2,v3]]:
				var normal: Vector3 = (face[2]-face[0]).cross(face[1]-face[0]).normalized()
				if normal.is_zero_approx(): continue
				for vertex: Vector3 in face:
					surface.set_normal(normal)
					surface.add_vertex(vertex)
	_piece(n, Vector3.ZERO, surface.commit(), color, light)

var _materials := {}
func _piece(n: Node3D, p: Vector3, mesh: Mesh, color: Color, light := false) -> MeshInstance3D:
	if not _materials.has(color):
		var mat := ShaderMaterial.new()
		mat.shader = preload("res://scenes/blue_prince_lab/HallFinish.gdshader")
		mat.set_shader_parameter("pigment", color)
		mat.set_shader_parameter("grain", 0.065 if not light else 0.0)
		mat.set_shader_parameter("two_tone", color == FACE or color == TRIM)
		mat.set_shader_parameter("emission_gain", 2.2 if light else 0.0)
		_materials[color] = mat
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = _materials[color]
	instance.position = p
	instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
	if light: instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	n.add_child(instance)
	return instance

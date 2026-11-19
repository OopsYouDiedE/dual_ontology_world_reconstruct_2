extends Node3D
## Repeated bays keep the reference perspective legible at 720p. World units are metres.
const FINISH := preload("res://scenes/blue_prince_lab/HallFinish.gdshader")
const BAY_Z := [3.0, -0.55, -4.10, -7.65]
const BACK := -9.25
const SPRING := 4.48
const ARCH_RADIUS := 3.35
const KEY_COLORS := {
	"plaster": Color("778289"), "panel": Color("56626a"), "vault": Color("7a8995"),
	"stone": Color("989fa4"), "ivory": Color("b3babd"), "edge": Color("75818c"),
	"skirt": Color("535d64"), "floor_a": Color("81919d"), "floor_b": Color("8697a0"),
	"floor_c": Color("8899a4"), "grout": Color("333e42"), "carpet": Color("b28d5d"),
	"reveal": Color("3e484f"), "blue": Color("435159"), "oak": Color("6b5f4d"),
	"ink": Color("333b40"), "linen": Color("585044"),
	"fan_a": Color("a2b4be"), "fan_b": Color("b5c4ca"), "fan_seam": Color("586970")
}
var _batches: Dictionary = {}
var _boxes: Array[Dictionary] = []
var _arches: Array[Dictionary] = []
var _courses: Array[Dictionary] = []
var _unit_box := BoxMesh.new()

func _ready() -> void:
	_build_wall_shell()
	_build_vault()
	_build_floor()
	_build_masonry()
	for key in _batches:
		var material_key: String = key.get_slice("__", 0)
		var instance := MeshInstance3D.new()
		instance.name = str(key).capitalize().replace(" ", "")
		instance.mesh = (_batches[key] as SurfaceTool).commit()
		instance.gi_mode = GeometryInstance3D.GI_MODE_STATIC
		var material := ShaderMaterial.new()
		material.shader = FINISH
		material.set_shader_parameter("pigment", KEY_COLORS[material_key])
		material.set_shader_parameter("grain", 0.11 if material_key in ["vault", "plaster", "carpet", "oak", "linen", "fan_a", "fan_b"] else 0.076)
		material.set_shader_parameter("runner", 1.0 if material_key == "carpet" else 0.0)
		material.set_shader_parameter("wood", 1.0 if material_key in ["oak", "linen"] else 0.0)
		material.set_shader_parameter("surface_roughness", 0.65 if material_key.begins_with("floor_") else 0.83)
		instance.material_override = material
		add_child(instance)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hall-recipe="):
			var file := FileAccess.open(arg.trim_prefix("--hall-recipe="), FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify({"boxes": _boxes, "arches": _arches, "courses": _courses,
					"materials": KEY_COLORS.keys().map(func(key: String): return [key, KEY_COLORS[key].to_html(false)])}))

func _build_wall_shell() -> void:
	_solid(Vector3(0, -0.15, -0.39), Vector3(9.78, 0.30, 18.54), "grout")
	_solid(Vector3(0, 2.32, 8.72), Vector3(9.78, 4.64, 0.30), "plaster")
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(side * 2.82, 2.32, BACK), Vector3(4.16, 4.64, 0.36), "plaster")
	_solid(Vector3(0, 3.62, BACK), Vector3(1.49, 2.10, 0.36), "plaster")
	_solid(Vector3(-4.76, 2.32, -0.36), Vector3(0.32, 4.64, 18.4), "plaster")
	_solid(Vector3(4.76, 1.77, -0.36), Vector3(0.32, 3.54, 18.4), "plaster")
	_solid(Vector3(4.76, 4.49, -0.36), Vector3(0.32, 0.31, 18.4), "plaster")
	# High exterior apertures sit above the wood bays, out of the hero composition.
	var end := -9.60
	for z: float in [-5.85, -2.32, 1.23, 4.77]:
		var next := z - 0.46
		_solid(Vector3(4.76, 3.95, (end + next) * 0.5), Vector3(0.32, 0.84, next - end), "plaster")
		end = z + 0.46
		_box(Vector3(4.69, 3.95, z), Vector3(0.30, 0.84, 0.055), "edge")
	_solid(Vector3(4.76, 3.95, (end + 8.87) * 0.5), Vector3(0.32, 0.84, 8.87 - end), "plaster")
	_build_workroom()

func _build_workroom() -> void:
	_solid(Vector3(0, -0.14, -16.17), Vector3(6.1, 0.28, 14.03), "floor_a")
	_solid(Vector3(0, 4.45, -16.20), Vector3(6.18, 0.30, 14.0), "vault")
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(side * 3.02, 2.2, -16.2), Vector3(0.24, 4.4, 14.0), "panel")
		_box(Vector3(side * 2.88, 0.15, -16.2), Vector3(0.09, 0.30, 14.0), "edge")
		for z: float in [-10.0, -13.3, -16.6, -19.9, -22.5]:
			_box(Vector3(side * 2.86, 2.15, z), Vector3(0.19, 4.3, 0.26), "stone")
	_solid(Vector3(0, 2.2, -23.20), Vector3(6.18, 4.4, 0.24), "plaster")
	_solid(Vector3(0, 1.5, -22.42), Vector3(2.5, 0.30, 1.46), "stone")

func _build_floor() -> void:
	# Large fields of stone define metre scale; thin dark joints are part of the silhouette.
	for z in range(7):
		for x in range(4):
			var key: String = ["floor_a", "floor_b", "floor_c"][posmod(x * 11 + z * 17 + x * z, 7) % 3]
			_box(Vector3((x - 1.5) * 2.39, -0.012, -7.98 + z * 2.65), Vector3(2.367, 0.036, 2.627), key)
	_box(Vector3(0, 0.019, -0.28), Vector3(2.34, 0.022, 17.71), "carpet")

func _build_vault() -> void:
	_arch(Vector3(0, SPRING, -0.38), 0, ARCH_RADIUS, ARCH_RADIUS + 0.24, 18.20, 30, "vault", false)
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(side * 4.00, 4.57, -0.4), Vector3(1.38, 0.20, 18.16), "plaster")
	for z: float in BAY_Z:
		_rib(z, SPRING, ARCH_RADIUS)
		# Individual ceiling panels link the ribs along the length of each bay.
		for i in range(1, 8):
			var theta := PI * i / 8.0
			var p := Vector3(cos(theta) * 3.33, SPRING + sin(theta) * 3.33, z + 1.775)
			_box(p, Vector3(0.060, 0.052, 3.23), "reveal")
		if z < 2.0:
			_arch(Vector3(0, SPRING, z + 1.775), 0, ARCH_RADIUS - 0.16, ARCH_RADIUS + 0.01, 0.15, 32, "edge", false)
			_arch(Vector3(0, SPRING, z + 1.775), 0, ARCH_RADIUS - 0.19, ARCH_RADIUS - 0.16, 0.21, 32, "stone", false)
			for band in range(8):
				var tone := "reveal" if band in [0, 2, 5, 7] else "edge"
				_ceiling_field(z + 1.775, band, tone)
	for z: float in [8.66, BACK + 0.015]:
		var p := Vector3(0, SPRING, z)
		for i in range(30):
			var a := PI * float(i) / 30.0
			var b := PI * float(i + 1) / 30.0
			_prism([Vector2.ZERO, Vector2(cos(a), sin(a)) * ARCH_RADIUS,
				Vector2(cos(b), sin(b)) * ARCH_RADIUS], p, 0, 0.24, "plaster")

func _ceiling_field(z: float, band: int, tone: String) -> void:
	var a := PI * band / 8.0 + 0.028
	var b := PI * (band + 1.0) / 8.0 - 0.028
	for i in range(4):
		var u := Vector2.from_angle(lerpf(a,b,i/4.0))
		var v := Vector2.from_angle(lerpf(a,b,(i+1)/4.0))
		_prism([u*3.245,u*3.32,v*3.32,v*3.245], Vector3(0,SPRING,z), 0.0, 2.62, tone)

func _rib(z: float, spring: float, radius: float) -> void:
	# Ring courses meet radially. Each course owns a different axial projection;
	# the ledges and returns are faces that receive light, not lines on the face.
	var courses := [
		[-0.43, -0.34, 0.57, "stone"],
		[-0.34, -0.30, 0.62, "ivory"],
		[-0.30, -0.23, 0.44, "edge"],
		[-0.23, -0.10, 0.51, "stone"],
		[-0.10, -0.045, 0.65, "ivory"],
		[-0.045, 0.04, 0.46, "edge"],
	]
	for course: Array in courses:
		_arch(Vector3(0, spring, z), 0, radius + course[0], radius + course[1],
			course[2] * 2.0, 32, course[3], false)
	# The crown boss projects below the soffit, with three rectangular stone steps.
	for step: Array in [[0.91, 0.090, 1.25, 0.43, "edge"], [0.78, 0.080, 1.40, 0.49, "stone"],
			[0.65, 0.065, 1.51, 0.55, "ivory"]]:
		_box(Vector3(0, spring + radius - step[3], z), Vector3(step[0], step[1], step[2]), step[4])

func _portal(radius: float, spring: float, scale_factor: float) -> void:
	# All courses share a rear bed in the wall and continue down the jambs.
	const BED := -9.15
	var courses := [
		[0.00, 0.070, 0.260, "stone"],
		[0.07, 0.109, 0.295, "ivory"],
		[0.109, 0.18, 0.165, "edge"],
		[0.18, 0.30, 0.225, "stone"],
		[0.30, 0.35, 0.260, "ivory"],
		[0.35, 0.42, 0.150, "edge"],
	]
	for course: Array in courses:
		var inner: float = radius + course[0] * scale_factor
		var outer: float = radius + course[1] * scale_factor
		var front: float = BED + 0.13 + course[2] * scale_factor
		var z: float = (front + BED) * 0.5
		var depth: float = front - BED
		_arch(Vector3(0, spring, z), 0, inner, outer, depth, 32, course[3], false)
		for side: float in [-1.0, 1.0]:
			_box(Vector3(side * (inner + outer) * 0.5, spring * 0.5, z),
				Vector3(outer - inner, spring, depth), course[3])

func _build_masonry() -> void:
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side * 4.52, 0.11, -0.38), Vector3(0.25, 0.22, 17.8), "skirt")
		_box(Vector3(side * 4.55, 0.93, -0.38), Vector3(0.19, 0.09, 17.8), "edge")
		for i in range(17):
			var z := 8.1 - 1.045 * i
			_box(Vector3(side * 4.58, 0.52, z), Vector3(0.13, 0.69, 1.012), "panel")
			_box(Vector3(side * 4.50, 0.52, z), Vector3(0.042, 0.58, 0.88), "stone")
			_box(Vector3(side * 4.473, 0.52, z), Vector3(0.025, 0.47, 0.78), "panel")
		for z: float in BAY_Z:
			_pier(side, z)
		for z: float in [4.64, 1.21, -2.33, -5.89]:
			_box(Vector3(side * 4.55, 2.70, z), Vector3(0.22, 3.48, 1.17), "reveal")
			for i in range(7):
				var thick := 0.12 + 0.075 * sin(float(i) * 1.47 + 0.4)
				_box(Vector3(side * (4.49 - thick * 0.5), 2.70, z + (i - 3) * 0.149), Vector3(thick, 3.46, 0.142), "oak")
		_curtain(side, 3.84)
		if side > 0.0:
			for z: float in [1.29, -2.28]:
				_curtain(side, z)
	# Nested frames retain three different silhouettes and physical jamb depths.
	_portal(2.85, 4.39, 1.12)
	_portal(1.63, 3.78, 0.94)
	_portal(0.93, 2.62, 0.60)
	# Segmented stone fields give the cold focus a readable boundary beyond the light pool.
	var fan_center := Vector3(0, 3.78, -9.054)
	for i in range(20):
		var a := PI * float(i) / 20.0
		var b := PI * float(i + 1) / 20.0
		var tone := "fan_b" if i >= 7 and i < 13 else "fan_a"
		_prism([Vector2.ZERO, Vector2.from_angle(a) * 1.63,
			Vector2.from_angle(b) * 1.63], fan_center, 0, 0.046, tone)
	for i in range(3):
		var a := PI * (i + 1) / 4.0
		var v := Vector2.from_angle(a)
		var d := Vector2(-v.y, v.x) * 0.013
		_prism([v * 0.21 - d, v * 1.60 - d, v * 1.60 + d, v * 0.21 + d],
			fan_center + Vector3.BACK * 0.028, 0, 0.02, "fan_seam")
	_prism([Vector2(-1.63,-0.96), Vector2(1.63,-0.96), Vector2(1.63,0), Vector2(-1.63,0)],
		fan_center, 0, 0.046, "fan_a")
	_prism([Vector2(-0.70,0),Vector2(0.70,0),Vector2(0.46,0.34),Vector2(-0.46,0.34)],
		Vector3(0,2.72,-8.93), 0.0, 0.078, "ivory")
	for side: float in [-1.0, 1.0]:
		var p := Vector3(side * 1.42, 0, -8.58)
		_box(p + Vector3.UP * 0.10, Vector3(0.57,0.20,0.60), "edge")
		_box(p + Vector3.UP * 0.53, Vector3(0.38,0.82,0.44), "stone")
		_box(p + Vector3.UP * 0.96, Vector3(0.55,0.10,0.59), "ivory")
		_prism([Vector2(-0.255,0),Vector2(0.255,0),Vector2(0.24,0.235),Vector2(0,0.354),Vector2(-0.24,0.235)],
			p + Vector3.UP * 1.014, 0.0, 0.18, "stone")
	for i in range(-5, 6):
		if abs(i) < 2: continue
		_box(Vector3(i * 0.70, 0.47, -9.00), Vector3(0.61, 0.68, 0.13), "panel")
		_box(Vector3(i * 0.70, 0.47, -8.925), Vector3(0.48, 0.56, 0.05), "edge")
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side * 2.55, 0.88, -8.989), Vector3(3.32, 0.108, 0.13), "stone")

func _curtain(side: float, z: float) -> void:
	# Closed extruded pleats, angled toward the aisle and exported with the masonry recipe.
	const WIDTH := 1.69
	for i in range(18):
		var u := float(i) / 18.0 * WIDTH
		var v := float(i + 1) / 18.0 * WIDTH
		var depth := cos(float(i) * TAU / 3.0) * 0.06
		var next_depth := cos(float(i + 1) * TAU / 3.0) * 0.06
		var run := 0.19 * (v - u) - (next_depth - depth)
		var slope := atan2(run, v - u)
		var half := Vector2(v - u, run).length() * 0.505
		var hem := 0.13 + 0.035 * sin(float(i) * 0.81)
		var p := Vector3(side * (4.37 + 0.19 * (u + v) * 0.5), 0, z + side * (u + v - WIDTH) * 0.5)
		p.x -= side * (depth + next_depth) * 0.5
		_prism([Vector2(-half, hem), Vector2(half, hem), Vector2(half, 4.60), Vector2(-half, 4.60)],
			p, -side * PI * 0.5 + slope, 0.030, "linen")

func _pier(side: float, z: float) -> void:
	var p := Vector3(side * 3.43, 0, z)
	_solid(p + Vector3.UP * 0.14, Vector3(1.62, 0.28, 1.55), "stone")
	for h: float in [0.038, 0.25]:
		_box(p + Vector3.UP * h, Vector3(1.68, 0.052, 1.61), "edge")
	for face: float in [-1.0, 1.0]:
		for shift: float in [-0.47, 0.0, 0.47]:
			_box(p + Vector3(shift, 0.142, face * 0.781), Vector3(0.40, 0.117, 0.036), "reveal")
			_box(p + Vector3(face * 0.818, 0.142, shift), Vector3(0.036, 0.117, 0.40), "reveal")
	_round(p, [[0.75, 0.27], [0.75, 0.33], [0.68, 0.38], [0.63, 0.48], [0.62, 4.23]], "stone")
	for h: float in [0.55, 0.76, 0.98, 1.22, 1.47, 1.73, 3.51, 4.16]:
		_round(p, [[0.622,h-0.027],[0.654,h-0.021],[0.654,h+0.017],[0.622,h+0.036]], "edge")
	_round(p, [[0.622,4.12],[0.68,4.27],[0.80,4.36],[0.80,4.50]], "ivory")
	_round(p, [[0.70,4.33],[0.82,4.36],[0.82,4.39]], "ink")
	_box(p + Vector3.UP * 4.48, Vector3(1.67, 0.12, 1.34), "stone")

func _round(p: Vector3, profile: Array, key: String) -> void:
	var batch := _batch(key + "__prism")
	var n := 8
	for i in range(n):
		var a := (i + 0.5) * TAU / n
		var b := (i + 1.5) * TAU / n
		for j in range(profile.size() - 1):
			var lo: Array = profile[j]
			var hi: Array = profile[j+1]
			var v0 := p + Vector3(cos(a)*lo[0],lo[1],sin(a)*lo[0])
			var v1 := p + Vector3(cos(b)*lo[0],lo[1],sin(b)*lo[0])
			var v2 := p + Vector3(cos(b)*hi[0],hi[1],sin(b)*hi[0])
			var v3 := p + Vector3(cos(a)*hi[0],hi[1],sin(a)*hi[0])
			_triangle(batch, v0, v1, v2)
			_triangle(batch, v0, v2, v3)
	_courses.append({"p": _xyz(p), "profile": profile, "sides": n, "material": key})

func _solid(p: Vector3, size: Vector3, key: String) -> void:
	_box(p, size, key)
	var body := StaticBody3D.new()
	body.position = p
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	add_child(body)

func _batch(key: String) -> SurfaceTool:
	if not _batches.has(key):
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		_batches[key] = surface
	return _batches[key]

func _box(p: Vector3, size: Vector3, key: String) -> void:
	_batch(key).append_from(_unit_box, 0, Transform3D(Basis.from_scale(size), p))
	_boxes.append({"p": [p.x, p.y, p.z], "size": [size.x, size.y, size.z], "material": key})

func _arch(p: Vector3, yaw: float, inner: float, outer: float, depth: float, count: int,
		key: String, joints := true) -> void:
	for i in range(count):
		var seam := 0.004 if joints else 0.0
		var a := PI * float(i) / count + seam
		var b := PI * float(i + 1) / count - seam
		var u := Vector2(cos(a), sin(a))
		var v := Vector2(cos(b), sin(b))
		_prism([u * inner, u * outer, v * outer, v * inner], p, yaw, depth, key)

func _prism(profile: Array[Vector2], p: Vector3, yaw: float, depth: float, key: String) -> void:
	var front: Array[Vector3] = []
	var rear: Array[Vector3] = []
	for point: Vector2 in profile:
		front.append(p + Vector3(point.x, point.y, depth / 2.0).rotated(Vector3.UP, yaw))
		rear.append(p + Vector3(point.x, point.y, -depth / 2.0).rotated(Vector3.UP, yaw))
	var batch := _batch(key + "__prism")
	for i in range(1, profile.size() - 1):
		_triangle(batch, front[0], front[i + 1], front[i])
		_triangle(batch, rear[0], rear[i], rear[i + 1])
	for i in range(profile.size()):
		var j := (i + 1) % profile.size()
		_triangle(batch, front[i], front[j], rear[j])
		_triangle(batch, front[i], rear[j], rear[i])
	_arches.append({"front": front.map(_xyz), "rear": rear.map(_xyz), "material": key})

func _xyz(p: Vector3) -> Array[float]:
	return [p.x, p.y, p.z]

func _triangle(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	var normal := (c - a).cross(b - a).normalized()
	for point: Vector3 in [a,b,c]:
		surface.set_normal(normal)
		surface.add_vertex(point)

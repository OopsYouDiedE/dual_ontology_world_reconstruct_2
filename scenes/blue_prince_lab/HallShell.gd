extends Node3D
## Repeated bays keep the reference perspective legible at 720p. World units are metres.
const FINISH := preload("res://scenes/blue_prince_lab/HallFinish.gdshader")
const BAY_Z := [1.82, -1.88, -5.62]
const STRUCTURAL_ARCH_Z := [1.82, -1.88]
const END_HALL_START := -3.05
const REAR_RISE := 5.52
const END_WIDTH := 4.52
const BACK := -9.25
const SPRING := 5.10
const UPPER_HALL := SPRING + 0.16
const ARCH_RADIUS := 3.35
const KEY_COLORS := {
	"plaster": Color("778289"), "panel": Color("56626a"), "vault": Color("7a8995"),
	"stone": Color("989fa4"), "shaft": Color("a6b2bc"), "ivory": Color("b3babd"), "edge": Color("75818c"),
	"skirt": Color("535d64"), "floor_a": Color("81919d"), "floor_b": Color("8697a0"),
	"floor_c": Color("8899a4"), "grout": Color("333e42"), "carpet": Color("b28d5d"),
	"reveal": Color("3e484f"), "blue": Color("435159"), "oak": Color("6b5f4d"),
	"ink": Color("333b40"), "linen": Color("585044"),
	"coffer": Color("647485"), "vault_rib": Color("85939f"), "vault_crown": Color("a0abb2"), "fan_a": Color("9eafba"), "fan_b": Color("aabac2"), "fan_seam": Color("586970")
}
var _batches: Dictionary = {}
var _boxes: Array[Dictionary] = []
var _arches: Array[Dictionary] = []
var _courses: Array[Dictionary] = []
var _drapes: Array[Dictionary] = []
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
		material.set_shader_parameter("grain", 0.25 if material_key in ["stone", "shaft", "vault", "plaster", "carpet", "fan_a", "fan_b"] else 0.095)
		material.set_shader_parameter("runner", 1.0 if material_key == "carpet" else 0.0)
		material.set_shader_parameter("wood", 1.0 if material_key in ["oak", "linen"] else 0.0)
		material.set_shader_parameter("surface_roughness", 0.50 if material_key.begins_with("floor_") else 0.83)
		if material_key == "shaft":
			material.set_shader_parameter("shaft_flat", true)
		if material_key == "plaster":
			material.set_shader_parameter("two_tone", true)
		if material_key.begins_with("floor_"):
			material.set_shader_parameter("stone_sheen", 0.064)
		if material_key in ["coffer", "vault"]:
			material.set_shader_parameter("vault_fill", 0.10)
		if material_key in ["fan_a", "fan_b"]:
			material.set_shader_parameter("pale_wash", 0.17)
		if material_key in ["linen", "stone", "ivory"]:
			material.set_shader_parameter("toon_strength", 0.71)
		instance.material_override = material
		add_child(instance)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hall-recipe="):
			var file := FileAccess.open(arg.trim_prefix("--hall-recipe="), FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify({"boxes": _boxes, "arches": _arches, "courses": _courses, "drapes": _drapes,
					"materials": KEY_COLORS.keys().map(func(key: String): return [key, KEY_COLORS[key].to_html(false)])}))

func _build_subfloor() -> void:
	_solid(Vector3(0, -0.15, -0.39), Vector3(9.78, 0.30, 18.54), "grout")

func _build_wall_shell() -> void:
	_build_subfloor()
	_solid(Vector3(0, UPPER_HALL * 0.5, 8.72), Vector3(9.78, UPPER_HALL, 0.30), "plaster")
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(side * 2.99, UPPER_HALL * 0.5, BACK), Vector3(3.80, UPPER_HALL, 0.36), "plaster")
	_solid(Vector3(0, (UPPER_HALL + 3.86) * 0.5, BACK), Vector3(2.20, UPPER_HALL - 3.86, 0.36), "plaster")
	_solid(Vector3(-4.76, UPPER_HALL * 0.5, -0.36), Vector3(0.32, UPPER_HALL, 18.4), "plaster")
	_solid(Vector3(4.76, 1.77, -0.36), Vector3(0.32, 3.54, 18.4), "plaster")
	_solid(Vector3(4.76, (4.37 + UPPER_HALL) * 0.5, -0.36), Vector3(0.32, UPPER_HALL - 4.37, 18.4), "plaster")
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
	_solid(Vector3(0, 2.2, -23.86), Vector3(6.18, 4.4, 0.24), "plaster")
	_solid(Vector3(0, 1.5, -22.42), Vector3(2.5, 0.30, 1.46), "stone")

func _build_floor() -> void:
	# Large fields of stone define metre scale; thin dark joints are part of the silhouette.
	for z in range(7):
		for x in range(4):
			var key: String = ["floor_a", "floor_b", "floor_c"][posmod(x * 11 + z * 17 + x * z, 7) % 3]
			_box(Vector3((x - 1.5) * 2.39, -0.012, -7.98 + z * 2.65), Vector3(2.367, 0.036, 2.627), key)
	_box(Vector3(0, 0.019, -0.28), Vector3(2.34, 0.022, 17.71), "carpet")

func _build_vault() -> void:
	var front_length := 8.72 - END_HALL_START
	_arch(Vector3(0, SPRING, 8.72 - front_length * 0.5), 0.0, ARCH_RADIUS, ARCH_RADIUS + 0.22,
		front_length, 44, "coffer", false)
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(side * 4.0, SPRING + 0.09, 8.72 - front_length * 0.5),
			Vector3(1.38, 0.20, front_length), "plaster")
	for i in range(STRUCTURAL_ARCH_Z.size()):
		_build_entry_arch(STRUCTURAL_ARCH_Z[i], 1.06 if i == 0 else 0.91)
	# A single broad rear shell without ribs, keystones or panel breaks down its length.
	var back_depth := END_HALL_START - BACK
	_elliptic_ring(Vector3(0, SPRING, BACK + back_depth * 0.5), END_WIDTH, REAR_RISE,
		0.0, 0.18, back_depth, "vault")
	_seal_vault_transition()
	for z: float in [8.66, BACK + 0.015]:
		var width := END_WIDTH if z < 0.0 else ARCH_RADIUS
		var height := REAR_RISE if z < 0.0 else ARCH_RADIUS
		var p := Vector3(0, SPRING, z)
		for i in range(48):
			var a := PI * float(i) / 48.0
			var b := PI * float(i + 1) / 48.0
			_prism([Vector2.ZERO, Vector2(cos(a)*width, sin(a)*height),
				Vector2(cos(b)*width, sin(b)*height)], p, 0, 0.24, "plaster")

func _seal_vault_transition() -> void:
	# Close the spandrel where the narrow coffered vault opens into the broad shell.
	for i in range(48):
		var a := Vector2.from_angle(PI * float(i) / 48.0)
		var b := Vector2.from_angle(PI * float(i + 1) / 48.0)
		var outer := Vector2(END_WIDTH + 0.03, REAR_RISE)
		_prism([a*ARCH_RADIUS, a*outer, b*outer, b*ARCH_RADIUS],
			Vector3(0,SPRING,END_HALL_START), 0.0, 0.22, "vault")

func _build_entry_arch(z: float, span: float) -> void:
	# Three successive setbacks cut toward the recessed bay. Broad soffits carry
	# the load visually; the narrower courses are real lip/return geometry.
	var rings := [
		[-0.43, -0.33, 1.90, "vault_rib"],
		[-0.33, -0.27, 2.21, "edge"],
		[-0.27, -0.14, 1.70, "vault_rib"],
		[-0.14, -0.08, 2.48, "vault_crown"],
		[-0.08, 0.03, 2.65, "edge"],
	]
	for ring: Array in rings:
		_arch(Vector3(0, SPRING, z), 0.0, ARCH_RADIUS + ring[0], ARCH_RADIUS + ring[1],
			span * ring[2], 40, ring[3], false)
	# Axial ribs run through the opening. The wall of each recess is the radial
	# height difference between these ribs and the curved backing behind them.
	for i in range(1, 12):
		var center := PI * i / 12.0
		var a := center - 0.019
		var b := center + 0.019
		var u := Vector2.from_angle(a)
		var v := Vector2.from_angle(b)
		_prism([u*2.79,u*2.98,v*2.98,v*2.79], Vector3(0,SPRING,z), 0.0, span * 1.88, "vault_rib")
		_prism([u*2.77,u*2.80,v*2.80,v*2.77], Vector3(0,SPRING,z), 0.0, span * 1.67, "vault_crown")

func _elliptic_ring(p: Vector3, width: float, height: float, inner: float, outer: float,
		depth: float, key: String) -> void:
	for i in range(48):
		var a := PI * float(i) / 48.0
		var b := PI * float(i + 1) / 48.0
		var u := Vector2.from_angle(a)
		var v := Vector2.from_angle(b)
		_prism([u*Vector2(width+inner,height+inner),u*Vector2(width+outer,height+outer),
			v*Vector2(width+outer,height+outer),v*Vector2(width+inner,height+inner)], p, 0.0, depth, key)

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
	# The broad outlines at the back sit in one wall plane, rather than
	# projecting into the hall as extra transverse vaults.
	_elliptic_ring(Vector3(0, SPRING, -9.004), 3.78, 5.34, -0.045, 0.020, 0.036, "edge")
	_elliptic_ring(Vector3(0, SPRING, -8.995), 3.78, 5.34, 0.020, 0.074, 0.035, "vault_rib")
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side*3.78, SPRING * 0.5, -9.003), Vector3(0.074,SPRING,0.045), "edge")
	_portal(2.26, 5.24, 0.74)
	_portal(1.20, 3.97, 0.72)
	# Segmented stone fields give the cold focus a readable boundary beyond the light pool.
	var fan_center := Vector3(0, 5.24, -9.054)
	for i in range(20):
		var a := PI * float(i) / 20.0
		var b := PI * float(i + 1) / 20.0
		var tone := "fan_a"
		_prism([Vector2.ZERO, Vector2.from_angle(a) * 2.26,
			Vector2.from_angle(b) * 2.26], fan_center, 0, 0.046, tone)
	for side: float in [-1.0, 1.0]:
		var foot := Vector2(side * 0.84, -1.46)
		var head := Vector2(side * 1.08, 1.84)
		var lip := Vector2(0.020, 0)
		_prism([foot-lip,head-lip,head+lip,foot+lip],fan_center + Vector3.BACK * 0.03,0,0.024,"fan_seam")
	_prism([Vector2(-2.26,-1.29), Vector2(2.26,-1.29), Vector2(2.26,0), Vector2(-2.26,0)],
		fan_center, 0, 0.046, "fan_a")
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side * 1.73, 1.985, -9.054), Vector3(1.06, 3.97, 0.046), "fan_a")
	_prism([Vector2(-0.70,0),Vector2(0.70,0),Vector2(0.46,0.34),Vector2(-0.46,0.34)],
		Vector3(0,3.97,-8.93), 0.0, 0.078, "ivory")
	for side: float in [-1.0, 1.0]:
		var p := Vector3(side * 1.77, 0, -8.58)
		_box(p + Vector3.UP * 0.10, Vector3(0.57,0.20,0.60), "edge")
		_box(p + Vector3.UP * 0.99, Vector3(0.49,1.60,0.48), "stone")
		_box(p + Vector3.UP * 1.84, Vector3(0.73,0.14,0.62), "ivory")
	for i in range(-5, 6):
		if abs(i) < 2: continue
		_box(Vector3(i * 0.70, 0.47, -9.00), Vector3(0.61, 0.68, 0.13), "panel")
		_box(Vector3(i * 0.70, 0.47, -8.925), Vector3(0.48, 0.56, 0.05), "edge")
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side * 2.55, 0.88, -8.989), Vector3(3.32, 0.108, 0.13), "stone")

func _drape_point(side: float, z: float, u: float, v: float) -> Vector3:
	var phase := TAU * (5.3 * u + 0.37 * (1.0 - v) + 0.07 * sin(TAU * u))
	var depth := (0.045 + 0.043 * (1.0 - v)) * cos(phase) + 0.021 * sin(phase * 2.0 + 0.9)
	var hem := 0.14 + 0.034 * sin(phase)
	return Vector3(side * (4.29 + 0.18 * u - depth - 0.15 * sin(v * PI)),
		lerpf(hem, UPPER_HALL - 0.02, v), z + side * ((u - 0.5) * 1.95 + 0.14 * (1.0 - v)))

func _curtain(side: float, z: float) -> void:
	const ACROSS := 54
	const DOWN := 12
	var batch := _batch("linen__drape")
	var points: Array[Vector3] = []
	var normals: Array[Vector3] = []
	var faces: Array = []
	for y in range(DOWN + 1):
		for x in range(ACROSS + 1):
			var u := float(x) / ACROSS
			var v := float(y) / DOWN
			points.append(_drape_point(side, z, u, v))
			var du := _drape_point(side, z, u + 0.001, v) - _drape_point(side, z, u - 0.001, v)
			var dv := _drape_point(side, z, u, v + 0.001) - _drape_point(side, z, u, v - 0.001)
			normals.append(du.cross(dv).normalized())
	for y in range(DOWN):
		for x in range(ACROSS):
			var lo := y * (ACROSS + 1) + x
			var hi := lo + ACROSS + 1
			var face := [lo, hi, hi + 1, lo + 1]
			faces.append(face)
			for idx in [lo, hi, hi + 1, lo, hi + 1, lo + 1]:
				batch.set_normal(normals[idx])
				batch.add_vertex(points[idx])
	_drapes.append({"vertices": points.map(_xyz), "faces": faces})

func _pier(side: float, z: float) -> void:
	var p := Vector3(side * 3.43, 0, z)
	_solid(p + Vector3.UP * 0.145, Vector3(1.48, 0.29, 1.47), "stone")
	for h: float in [0.038, 0.265]:
		_box(p + Vector3.UP * h, Vector3(1.54, 0.052, 1.53), "edge")
	for face: float in [-1.0, 1.0]:
		for shift: float in [-0.44, 0.0, 0.44]:
			_box(p + Vector3(shift, 0.145, face * 0.739), Vector3(0.36, 0.117, 0.029), "edge")
			_box(p + Vector3(face * 0.744, 0.145, shift), Vector3(0.029, 0.117, 0.36), "edge")
	_round(p, [[0.70,0.29], [0.70,0.34], [0.60,0.40], [0.54,0.50], [0.48,SPRING-0.34]], "shaft")
	for h: float in [0.57, 0.75, 0.94, 1.16, 1.39]:
		var r := lerpf(0.54, 0.48, (h-0.50)/(SPRING-0.84))
		_round(p, [[r-0.004,h-0.024], [r+0.014,h-0.019], [r+0.014,h+0.015], [r-0.004,h+0.030]], "shaft")
	_round(p, [[0.479,SPRING-0.37], [0.55,SPRING-0.23], [0.68,SPRING-0.13], [0.70,SPRING+0.02]], "ivory")
	_box(p + Vector3.UP * SPRING, Vector3(1.47, 0.11, 1.36), "stone")

func _round(p: Vector3, profile: Array, key: String) -> void:
	var batch := _batch(key + "__prism")
	var n := 32
	for i in range(n):
		var a := (i + 0.5) * TAU / n
		var b := (i + 1.5) * TAU / n
		var u := Vector3(cos(a),0,sin(a))
		var v := Vector3(cos(b),0,sin(b))
		for j in range(profile.size() - 1):
			var lo: Array = profile[j]
			var hi: Array = profile[j+1]
			var slope := Vector2(hi[1] - lo[1], lo[0] - hi[0]).normalized()
			var nu := u*slope.x + Vector3.UP*slope.y
			var nv := v*slope.x + Vector3.UP*slope.y
			var v0: Vector3 = p + u*lo[0] + Vector3.UP*lo[1]
			var v1: Vector3 = p + v*lo[0] + Vector3.UP*lo[1]
			var v2: Vector3 = p + v*hi[0] + Vector3.UP*hi[1]
			var v3: Vector3 = p + u*hi[0] + Vector3.UP*hi[1]
			for vertex in [[v0,nu],[v1,nv],[v2,nv],[v0,nu],[v2,nv],[v3,nu]]:
				batch.set_normal(vertex[1])
				batch.add_vertex(vertex[0])
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

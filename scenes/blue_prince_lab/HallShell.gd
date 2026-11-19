extends Node3D
## Repeated bays keep the reference perspective legible at 720p. World units are metres.
const FINISH := preload("res://scenes/blue_prince_lab/HallFinish.gdshader")
const BAY_Z := [6.25, 2.95, -0.35, -3.65, -6.95]
const HALF_WIDTH := 4.65
const BACK := -9.25
const ENTRY := 8.05
const SPRING := 3.40
const VAULT := 6.52
const ARCH_RADIUS := 3.10
const KEY_COLORS := {
	"plaster": Color("72859b"), "panel": Color("4d6078"), "vault": Color("465775"),
	"stone": Color("a2b1b8"), "ivory": Color("ccd2cc"), "edge": Color("82929f"),
	"skirt": Color("536576"), "floor_a": Color("7d8e95"), "floor_b": Color("86959a"),
	"floor_c": Color("899b9e"), "grout": Color("536168"), "carpet": Color("a58a4c"),
	"brass": Color("987343"), "reveal": Color("334455"), "blue": Color("263c55")
}
var _batches: Dictionary = {}
var _boxes: Array[Dictionary] = []
var _arches: Array[Dictionary] = []
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
		material.set_shader_parameter("grain", 0.15 if material_key in ["vault", "plaster", "carpet"] else 0.062)
		material.set_shader_parameter("runner", 1.0 if material_key == "carpet" else 0.0)
		material.set_shader_parameter("surface_roughness", 0.65 if material_key.begins_with("floor_") else 0.83)
		instance.material_override = material
		add_child(instance)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--hall-recipe="):
			var file := FileAccess.open(arg.trim_prefix("--hall-recipe="), FileAccess.WRITE)
			if file != null:
				file.store_string(JSON.stringify({"boxes": _boxes, "arches": _arches,
					"materials": KEY_COLORS.keys().map(func(key: String): return [key, KEY_COLORS[key].to_html(false)])}))

func _build_wall_shell() -> void:
	_solid(Vector3(0, -0.14, -0.6), Vector3(9.7, 0.28, 18.5), "grout")
	_solid(Vector3(0, 2.8, 8.7), Vector3(9.7, 5.6, 0.4), "plaster")
	# Rear door has a walkable recess beyond the moving leaf.
	for sign_x: float in [-1.0, 1.0]:
		_solid(Vector3(sign_x * 2.72, 2.8, BACK), Vector3(3.96, 5.6, 0.36), "plaster")
	_solid(Vector3(0, 0.65, BACK), Vector3(1.48, 1.3, 0.36), "plaster")
	_solid(Vector3(0, 5.15, BACK), Vector3(1.48, 1.8, 0.36), "plaster")
	_solid(Vector3(0, 1.51, -10.1), Vector3(2.0, 0.28, 2.0), "stone")
	_solid(Vector3(0, 3.1, -11.0), Vector3(2.0, 3.1, 0.24), "blue")
	for sign_x: float in [-1.0, 1.0]:
		_solid(Vector3(sign_x * 0.9, 3.1, -10.13), Vector3(0.22, 3.1, 1.8), "panel")
	# East window apertures are genuine holes through the exterior wall.
	_solid(Vector3(-4.78, 2.9, -0.48), Vector3(0.30, 5.8, 18.05), "plaster")
	_solid(Vector3(4.78, 0.84, -0.48), Vector3(0.30, 1.68, 18.05), "plaster")
	_solid(Vector3(4.78, 4.85, -0.48), Vector3(0.30, 2.1, 18.05), "plaster")
	var end := -9.50
	for z: float in [-5.30, -2.00, 1.30, 4.60]:
		var start := z - 0.61
		_solid(Vector3(4.78, 2.74, (start + end) / 2), Vector3(0.30, 2.12, start - end), "plaster")
		end = z + 0.61
		# Upper/lower jambs, inset mullions and sill in one repeatable assembly.
		_solid(Vector3(4.64, 1.65, z), Vector3(0.54, 0.12, 1.47), "ivory")
		_box(Vector3(4.72, 3.78, z), Vector3(0.36, 0.13, 1.46), "stone")
		for s: float in [-1.0, 1.0]:
			_box(Vector3(4.72, 2.71, z + s * 0.64), Vector3(0.35, 2.11, 0.12), "ivory")
		_box(Vector3(4.76, 2.73, z), Vector3(0.12, 2.11, 0.061), "edge")
		_box(Vector3(4.76, 2.38, z), Vector3(0.12, 0.057, 1.22), "edge")
	_solid(Vector3(4.78, 2.74, (8.55 + end) / 2), Vector3(0.30, 2.12, 8.55 - end), "plaster")

func _build_floor() -> void:
	for z in range(20):
		for x in range(10):
			var key: String = ["floor_a", "floor_b", "floor_c"][posmod(x * 11 + z * 17 + x * z, 7) % 3]
			_box(Vector3((x - 4.5) * 0.93, -0.008, -9.03 + z * 0.92), Vector3(0.92, 0.028, 0.91), key)
	_box(Vector3(0, 0.018, 2.40), Vector3(2.45, 0.024, 11.70), "carpet")

func _build_vault() -> void:
	# The roof surface is connected across bays; the ivory ribs have separate joints.
	_arch(Vector3(0, SPRING, -0.41), 0, ARCH_RADIUS, ARCH_RADIUS + 0.22, 18.2, 26, "vault", false)
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(side * 3.87, 3.60, -0.42), Vector3(1.62, 0.18, 18.15), "edge")
		_box(Vector3(side * 3.87, 3.47, -0.42), Vector3(1.64, 0.085, 18.15), "stone")
	for z: float in BAY_Z + [BACK + 0.15]:
		_arch(Vector3(0, SPRING, z), 0, ARCH_RADIUS - 0.15, ARCH_RADIUS + 0.04, 0.34, 20, "stone")
		_arch(Vector3(0, SPRING, z), 0, ARCH_RADIUS - 0.23, ARCH_RADIUS - 0.15, 0.15, 20, "ivory")
		_box(Vector3(0, VAULT - 0.16, z + 0.19), Vector3(0.29, 0.35, 0.13), "ivory")
	for z: float in [8.60, BACK - 0.05]:
		var p := Vector3(0, SPRING, z)
		for i in range(20):
			var a := PI * float(i) / 20.0
			var b := PI * float(i + 1) / 20.0
			_prism([Vector2.ZERO, Vector2(cos(a), sin(a)) * ARCH_RADIUS,
				Vector2(cos(b), sin(b)) * ARCH_RADIUS], p, 0, 0.24, "vault")

func _build_masonry() -> void:
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side * 4.52, 0.11, -0.38), Vector3(0.25, 0.22, 17.8), "skirt")
		_box(Vector3(side * 4.55, 1.18, -0.38), Vector3(0.18, 0.08, 17.8), "ivory")
		_box(Vector3(side * 4.63, 0.67, -0.38), Vector3(0.15, 1.0, 17.8), "panel")
		for z: float in BAY_Z:
			_pier(side, z)
		for z: float in [4.60, 1.30, -2.00, -5.30]:
			var p := Vector3(side * 4.57, 3.57, z)
			_arch(p, -side * PI / 2.0, 0.64, 0.79, 0.11, 10, "ivory")
			if side < 0:
				_box(Vector3(-4.58, 2.64, z), Vector3(0.16, 1.84, 1.28), "reveal")
				_box(Vector3(-4.48, 2.64, z), Vector3(0.052, 1.62, 1.12), "panel")
				_box(Vector3(-4.43, 1.70, z), Vector3(0.29, 0.10, 1.46), "stone")
			for offset: float in [-0.70, 0.70]:
				_box(Vector3(side * 4.54, 2.63, z + offset), Vector3(0.19, 1.89, 0.09), "stone")
	for side: float in [-1.0, 1.0]:
		_box(Vector3(side * 0.83, 2.91, -9.01), Vector3(0.19, 2.64, 0.23), "ivory")
	_box(Vector3(0, 4.29, -9.00), Vector3(1.85, 0.19, 0.26), "ivory")
	_arch(Vector3(0, 4.42, -9.04), 0, 0.77, 0.95, 0.17, 12, "stone")

func _pier(side: float, z: float) -> void:
	_solid(Vector3(side * 4.03, 0.17, z), Vector3(1.12, 0.34, 1.05), "stone")
	_box(Vector3(side * 4.03, 0.37, z), Vector3(1.02, 0.10, 0.97), "ivory")
	_box(Vector3(side * 4.02, 1.81, z), Vector3(0.91, 2.80, 0.77), "stone")
	_box(Vector3(side * 3.55, 1.85, z), Vector3(0.075, 2.74, 0.62), "ivory")
	for offset: float in [-0.31, 0.31]:
		_box(Vector3(side * 3.50, 1.82, z + offset), Vector3(0.13, 2.81, 0.075), "edge")
	for y: float in [0.59, 1.49, 2.39, 3.15]:
		_box(Vector3(side * 3.53, y, z), Vector3(0.04, 0.022, 0.65), "edge")
	_box(Vector3(side * 4.01, 3.26, z), Vector3(1.08, 0.12, 0.92), "edge")
	_box(Vector3(side * 4.01, 3.38, z), Vector3(1.20, 0.12, 1.04), "ivory")
	_box(Vector3(side * 3.37, 3.44, z), Vector3(0.59, 0.23, 0.66), "stone")
	_box(Vector3(side * 3.19, 3.61, z), Vector3(0.57, 0.14, 0.47), "ivory")

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

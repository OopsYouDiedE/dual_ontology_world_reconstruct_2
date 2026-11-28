@tool
class_name StructureArch3D
extends "res://scenes/components/structure/StructurePiece3D.gd"
## An arch between two points (like a wall): round/elliptical, pointed, segmental or flat
## (lintel) profile, optional jambs down to the floor and an optional spandrel fill up to
## `fill_to`. Its ends snap onto columns and wall ends. Drag the end handles in 3D or in
## the plan tab; the crown handle (3D) sets the rise.

const Hall := preload("res://scenes/components/hall/GothicHallPiece3D.gd")

enum Profile { ROUND, POINTED, SEGMENTAL, FLAT }

@export var start_point := Vector3.ZERO:
	set(v): start_point = v; shape_changed()
@export var end_point := Vector3(3, 0, 0):
	set(v): end_point = v; shape_changed()
@export var profile: Profile = Profile.POINTED:
	set(v): profile = v; mesh_changed()
## Height of the springing line above the end points.
@export_range(0.0, 40.0, 0.01) var spring_height := 2.4:
	set(v): spring_height = v; mesh_changed()
## Crown height above the springing line (ROUND with rise = half span is a semicircle).
@export_range(0.0, 20.0, 0.01) var rise := 1.5:
	set(v): rise = v; mesh_changed()
## Radial depth of the arch ring (voussoir band).
@export_range(0.02, 3.0, 0.01) var band := 0.3:
	set(v): band = v; mesh_changed()
## Thickness across the opening (wall depth).
@export_range(0.02, 5.0, 0.01) var depth := 0.4:
	set(v): depth = maxf(0.02, v); shape_changed()
## Solid jambs from the floor up to the springing line at both ends.
@export var jambs := true:
	set(v): jambs = v; mesh_changed()
## Fill the spandrels up to this height above the end points (0 = open).
@export_range(0.0, 40.0, 0.01) var fill_to := 0.0:
	set(v): fill_to = v; mesh_changed()
@export_range(4, 64) var segments := 20:
	set(v): segments = v; mesh_changed()
@export var material_key := "rib":
	set(v): material_key = v; mesh_changed()
@export var material: Material:
	set(v): material = v; mesh_changed()
@export var collision := true:
	set(v): collision = v; mesh_changed()

func plan_kind() -> String:
	return "arch"

func shape_key() -> Array:
	return [start_point, end_point, depth]

func neighbor_margin() -> float:
	return depth * 0.5 + 0.05

func plan_outline() -> PackedVector2Array:
	var a := to_plan(start_point)
	var b := to_plan(end_point)
	var side := (b - a).orthogonal().normalized() * depth * 0.5
	return PackedVector2Array([a + side, b + side, b - side, a - side])

func plan_handles() -> Array:
	return [{"id": &"start", "position": to_plan(start_point)}, {"id": &"end", "position": to_plan(end_point)}]

func set_plan_handle(id: StringName, plan_position: Vector2) -> void:
	match id:
		&"start": start_point = from_plan(plan_position, start_point.y)
		&"end": end_point = from_plan(plan_position, end_point.y)

func handle_height(id: StringName) -> float:
	return (start_point if id == &"start" else end_point).y

func snap_targets() -> PackedVector2Array:
	return PackedVector2Array([to_plan(start_point), to_plan(end_point), to_plan((start_point + end_point) * 0.5)])

## Height of the intrados above the springing line at u in [-1, 1] across the span.
func curve_y(u: float, half_span: float) -> float:
	var x := clampf(absf(u), 0.0, 1.0)
	match profile:
		Profile.ROUND:
			return rise * sqrt(maxf(0.0, 1.0 - x * x))
		Profile.POINTED:
			return rise * sqrt(maxf(0.0, 4.0 - pow(x + 1.0, 2)) / 3.0)
		Profile.SEGMENTAL:
			if rise <= 0.001:
				return 0.0
			var r := (half_span * half_span + rise * rise) / (2.0 * rise)
			return sqrt(maxf(0.0, r * r - pow(x * half_span, 2))) - (r - rise)
	return 0.0

func rebuild() -> void:
	for child in get_children():
		if is_generated(child):
			remove_child(child)
			child.queue_free()
	var span := Vector3(end_point.x - start_point.x, 0, end_point.z - start_point.z)
	var length := span.length()
	if length < 0.05:
		return
	var along := span / length
	var across := Vector3(-along.z, 0, along.x)
	var base_y := minf(start_point.y, end_point.y)
	var origin := Vector3(start_point.x, base_y, start_point.z)
	var half := length * 0.5
	var spring := base_y + spring_height
	var crown := spring + (0.0 if profile == Profile.FLAT else rise)
	var top := maxf(base_y + fill_to, crown + band) if fill_to > 0.0 else 0.0
	# Intrados (inner) and extrados (outer) curves in the arch plane (x along, y up).
	var inner := PackedVector2Array()
	var outer := PackedVector2Array()
	for i in segments + 1:
		var u := -1.0 + 2.0 * float(i) / float(segments)
		var x := half + u * half
		var y := curve_y(u, half)
		inner.append(Vector2(x, y))
	for i in inner.size():
		var prev := inner[maxi(0, i - 1)]
		var next := inner[mini(inner.size() - 1, i + 1)]
		var t := (next - prev).normalized()
		var n := Vector2(-t.y, t.x)
		if n.y < 0.0:
			n = -n
		if profile == Profile.FLAT:
			n = Vector2.UP
		outer.append(inner[i] + n * band)
	# The outer ring reaches the springing line at both ends (no gap above the jambs).
	var end_y := band if profile == Profile.FLAT else 0.0
	outer[0] = Vector2(-band, end_y)
	outer[outer.size() - 1] = Vector2(length + band, end_y)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var to3 := func(p: Vector2, side: float) -> Vector3:
		return origin + along * p.x + Vector3.UP * (spring + p.y - base_y) + across * (side * depth * 0.5)
	for i in segments:
		var a0: Vector3 = to3.call(inner[i], -1.0); var a1: Vector3 = to3.call(inner[i + 1], -1.0)
		var b0: Vector3 = to3.call(inner[i], 1.0); var b1: Vector3 = to3.call(inner[i + 1], 1.0)
		var c0: Vector3 = to3.call(outer[i], -1.0); var c1: Vector3 = to3.call(outer[i + 1], -1.0)
		var d0: Vector3 = to3.call(outer[i], 1.0); var d1: Vector3 = to3.call(outer[i + 1], 1.0)
		_quad(st, a0, b0, b1, a1)  # intrados (soffit), faces down
		_quad(st, c1, d1, d0, c0)  # extrados, faces up
		_quad(st, a1, c1, c0, a0)  # front face
		_quad(st, b0, d0, d1, b1)  # back face
	if jambs and spring_height > 0.01:
		var w := band if profile != Profile.FLAT else maxf(band, 0.1)
		for end in [[-w, 0.0], [length, length + w]]:
			_box(st, origin + along * ((end[0] + end[1]) * 0.5) + Vector3.UP * spring_height * 0.5,
				along * absf(end[1] - end[0]), Vector3.UP * spring_height, across * depth)
	if top > 0.0:
		# Spandrel walls: from the extrados up to `top`, front and back faces plus the top.
		for side in [-1.0, 1.0]:
			var poly := outer.duplicate()
			poly.append(Vector2(outer[outer.size() - 1].x, top - spring))
			poly.append(Vector2(outer[0].x, top - spring))
			var tris := Geometry2D.triangulate_polygon(poly)
			for k in range(0, tris.size(), 3):
				var p0: Vector3 = to3.call(poly[tris[k]], side)
				var p1: Vector3 = to3.call(poly[tris[k + 1]], side)
				var p2: Vector3 = to3.call(poly[tris[k + 2]], side)
				if side < 0.0:
					st.add_vertex(p0); st.add_vertex(p1); st.add_vertex(p2)
				else:
					st.add_vertex(p0); st.add_vertex(p2); st.add_vertex(p1)
		var tl: Vector3 = to3.call(Vector2(outer[0].x, top - spring), -1.0)
		var tr: Vector3 = to3.call(Vector2(outer[outer.size() - 1].x, top - spring), -1.0)
		_quad(st, tl, tr, tr + across * depth, tl + across * depth)
	st.generate_normals()
	var mesh := st.commit()
	var mi := MeshInstance3D.new()
	mi.name = "Arch"
	mi.mesh = mesh
	mi.material_override = material if material != null else Hall.mat(material_key)
	add_child(mi)
	if collision and mesh.get_surface_count() > 0:
		var body := StaticBody3D.new()
		body.name = "Collision"
		var col := CollisionShape3D.new()
		col.shape = mesh.create_trimesh_shape()
		body.add_child(col)
		add_child(body)

func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)

func _box(st: SurfaceTool, c: Vector3, x: Vector3, y: Vector3, z: Vector3) -> void:
	var h := [x * 0.5, y * 0.5, z * 0.5]
	var p := func(sx: float, sy: float, sz: float) -> Vector3: return c + h[0] * sx + h[1] * sy + h[2] * sz
	_quad(st, p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1))
	_quad(st, p.call(1, -1, -1), p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1))
	_quad(st, p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1))
	_quad(st, p.call(1, -1, 1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1))
	_quad(st, p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1), p.call(-1, 1, -1))

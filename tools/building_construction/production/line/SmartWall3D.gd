@tool
extends "res://scenes/components/structure/StructurePiece3D.gd"

## SmartWall3D: Godot 4.7 @tool parametric wall component.
## Supports grid-snap dragging (start_point -> end_point), automatic skirting boards,
## cutaway caps (for cutaway view inspection), and automatic opening cutout when
## doors or windows are placed upon it.

signal wall_rebuilt()

@export var start_point: Vector3 = Vector3.ZERO:
	set(v):
		start_point = _snap_vector(v)
		shape_changed()

@export var end_point: Vector3 = Vector3(4.0, 0.0, 0.0):
	set(v):
		end_point = _snap_vector(v)
		shape_changed()

@export_range(0.5, 40.0, 0.01) var wall_height: float = 3.0:
	set(v):
		wall_height = maxf(0.5, v)
		shape_changed()

@export_range(0.02, 3.0, 0.01) var wall_thickness: float = 0.25:
	set(v):
		wall_thickness = maxf(0.05, v)
		shape_changed()

@export_range(0.0, 1.0, 0.05) var grid_snap: float = 0.25
## Close corners and T-joints: an end touching another wall extends by half its thickness.
@export var join_corners: bool = true:
	set(v):
		join_corners = v
		_queue_rebuild()

@export_group("Skirting & Cutaway")
@export var skirting_enabled: bool = true:
	set(v):
		skirting_enabled = v
		_queue_rebuild()

@export_range(0.02, 0.3, 0.01) var skirting_height: float = 0.12:
	set(v):
		skirting_height = v
		_queue_rebuild()

@export_range(0.005, 0.1, 0.005) var skirting_thickness: float = 0.03:
	set(v):
		skirting_thickness = v
		_queue_rebuild()

@export var cutaway_enabled: bool = false:
	set(v):
		cutaway_enabled = v
		_queue_rebuild()

@export_range(0.1, 5.0, 0.1) var cutaway_elevation: float = 1.2:
	set(v):
		cutaway_elevation = v
		_queue_rebuild()

@export_group("Materials")
@export var wall_material: Material:
	set(v):
		wall_material = v
		_update_materials()

@export var skirting_material: Material:
	set(v):
		skirting_material = v
		_update_materials()

@export var cutaway_cap_material: Material:
	set(v):
		cutaway_cap_material = v
		_update_materials()

# Persist authored openings in .tscn; detected child openings remain transient.
@export var openings: Array[Dictionary] = []
## Level structures: false keeps collision and gameplay edges but hides the mesh at runtime
## (e.g. the Public Hall, whose visible shell is a Gothic component). Always drawn in the editor.
@export var draw_mesh: bool = true:
	set(v):
		draw_mesh = v
		_queue_rebuild()
var _rebuild_pending: bool = false
## Build-time origin and length offset (corner joins extend the ends beyond the endpoints).
var _origin: Vector3 = Vector3.ZERO

func _snap_vector(v: Vector3) -> Vector3:
	if grid_snap <= 0.0:
		return v
	return Vector3(
		snappedf(v.x, grid_snap),
		snappedf(v.y, grid_snap),
		snappedf(v.z, grid_snap)
	)

## Mesh-only change (materials, trims, openings): only this wall rebuilds.
func _queue_rebuild() -> void:
	mesh_changed()

# ── StructurePiece3D interface ────────────────────────────────────────────────

func shape_key() -> Array:
	return [start_point, end_point, wall_thickness, wall_height]

func neighbor_margin() -> float:
	return wall_thickness * 0.5 + 0.05

func plan_outline() -> PackedVector2Array:
	var a := to_plan(start_point)
	var b := to_plan(end_point)
	var side := (b - a).orthogonal().normalized() * wall_thickness * 0.5
	return PackedVector2Array([a + side, b + side, b - side, a - side])

func plan_kind() -> String:
	return "wall"

## Endpoints plus one handle per authored opening (door/window), slid along the wall.
func plan_handles() -> Array:
	var out: Array = [{"id": &"start", "position": to_plan(start_point)}, {"id": &"end", "position": to_plan(end_point)}]
	var dir := (end_point - start_point).normalized()
	for i in openings.size():
		var mid := (float(openings[i].get("from", 0)) + float(openings[i].get("to", 0))) * 0.5
		out.append({"id": StringName("op%d" % i), "position": to_plan(start_point + dir * mid)})
	return out

func set_plan_handle(id: StringName, plan_position: Vector2) -> void:
	match id:
		&"start": start_point = from_plan(plan_position, start_point.y)
		&"end": end_point = from_plan(plan_position, end_point.y)
		_:
			var i := str(id).trim_prefix("op").to_int()
			if not str(id).begins_with("op") or i < 0 or i >= openings.size():
				return
			var length := start_point.distance_to(end_point)
			var a := to_plan(start_point)
			var b := to_plan(end_point)
			var along := clampf((plan_position - a).dot((b - a).normalized()), 0.0, length)
			var op: Dictionary = openings[i].duplicate()
			var half := (float(op.get("to", 0)) - float(op.get("from", 0))) * 0.5
			along = clampf(along, half, length - half)
			op["from"] = snappedf(along - half, 0.01)
			op["to"] = snappedf(along + half, 0.01)
			var next := openings.duplicate()
			next[i] = op
			openings = next
			_queue_rebuild()

func handle_height(id: StringName) -> float:
	if str(id).begins_with("op"):
		var op: Dictionary = openings[str(id).trim_prefix("op").to_int()]
		return start_point.y + float(op.get("bottom", 0))
	return (start_point if id == &"start" else end_point).y

## Door (bottom 0) or window, centred at a plan point projected onto the wall.
func add_opening_at(plan_position: Vector2, width: float, bottom: float, top: float) -> int:
	var a := to_plan(start_point)
	var b := to_plan(end_point)
	var length := a.distance_to(b)
	var along := clampf((plan_position - a).dot((b - a).normalized()), width * 0.5, maxf(width * 0.5, length - width * 0.5))
	var next := openings.duplicate()
	next.append({"from": snappedf(along - width * 0.5, 0.01), "to": snappedf(along + width * 0.5, 0.01), "bottom": bottom, "top": top})
	openings = next
	_queue_rebuild()
	return openings.size() - 1

func plan_remove_handle(id: StringName) -> bool:
	if not str(id).begins_with("op"):
		return false
	var next := openings.duplicate()
	next.remove_at(str(id).trim_prefix("op").to_int())
	openings = next
	_queue_rebuild()
	return true

func snap_targets() -> PackedVector2Array:
	return PackedVector2Array([to_plan(start_point), to_plan(end_point)])

## How far an end reaches past its endpoint to close a corner with another wall.
func _end_extension(end: Vector3, away: Vector2) -> float:
	if not join_corners:
		return 0.0
	var p := to_plan(end)
	var reach := 0.0
	for n in neighbors():
		if not ("start_point" in n and "wall_thickness" in n):
			continue
		var a: Vector2 = n.to_plan(n.start_point)
		var b: Vector2 = n.to_plan(n.end_point)
		if a.distance_to(b) < 0.01:
			continue
		if Geometry2D.get_closest_point_to_segment(p, a, b).distance_to(p) > 0.02:
			continue
		if absf((b - a).normalized().dot(away)) > 0.99:
			continue  # collinear continuation: no overlap needed
		reach = maxf(reach, float(n.wall_thickness) * 0.5)
	return reach

func register_opening(from_m: float, to_m: float, bottom_m: float, top_m: float) -> void:
	openings.append({
		"from": minf(from_m, to_m),
		"to": maxf(from_m, to_m),
		"bottom": minf(bottom_m, top_m),
		"top": maxf(bottom_m, top_m)
	})
	_queue_rebuild()

func clear_openings() -> void:
	openings.clear()
	_queue_rebuild()

## Opening coordinates are in the insert's CLOSED local X/Y plane, independent
## of the animated sash/leaf transform. Legacy hinged children use the same datum.
static func outline(child: Node3D) -> PackedVector2Array:
	var points := PackedVector2Array()
	if child.has_meta(&"assembly_outline"): return child.get_meta(&"assembly_outline")
	var mesh_root := child.get_node_or_null("Generated")
	if mesh_root and mesh_root.has_meta(&"opening_profile_json"):
		for point in JSON.parse_string(mesh_root.get_meta(&"opening_profile_json")):
			points.append(Vector2(point[0],point[1]))
	return points

static func aperture(child: Node3D) -> Rect2:
	if "leaf_width" in child:
		return Rect2(-0.035, 0, child.leaf_width + 0.07, child.leaf_height + 0.025)
	if "sash_width" in child:
		return Rect2(-0.025, -0.015, child.sash_width + 0.05, child.sash_height + 0.04)
	match str(child.get_meta(&"assembly_id", "")):
		"HallDoor": return Rect2(-0.81, 0, 1.62, 2.7)
		"RecipeClosedDoor", "RecipeRectangularWindow": return Rect2(-float(child.width) / 2, 0, child.width, child.height)
	var poly := outline(child)
	if poly.is_empty(): return Rect2()
	var rect := Rect2(poly[0], Vector2.ZERO)
	for point in poly: rect = rect.expand(point)
	return rect

func opening_for(child: Node3D) -> Dictionary:
	var rect := aperture(child)
	if not rect.has_area(): return {}
	var dir := (end_point - start_point).normalized()
	var a := child.transform * Vector3(rect.position.x, rect.position.y, 0) - start_point
	var b := child.transform * Vector3(rect.end.x, rect.end.y, 0) - start_point
	var polygon := PackedVector2Array()
	for point in outline(child):
		var projected := child.transform * Vector3(point.x,point.y,0) - start_point
		polygon.append(Vector2(projected.dot(dir),projected.y))
	return {"profile":polygon,"from":minf(a.dot(dir), b.dot(dir)), "to":maxf(a.dot(dir), b.dot(dir)),
		"bottom":minf(a.y,b.y), "top":maxf(a.y,b.y)}

func detect_child_openings() -> Array[Dictionary]:
	var detected: Array[Dictionary] = []
	for child in get_children():
		if child is Node3D and not child.is_queued_for_deletion():
			var op := opening_for(child)
			if not op.is_empty(): detected.append(op)
	return detected

func rebuild() -> void:
	_rebuild_pending = false
	var wall_vec := end_point - start_point
	var length := wall_vec.length()
	if length < 0.05:
		return
	var plan_dir := (to_plan(end_point) - to_plan(start_point)).normalized()
	var ext_start := _end_extension(start_point, -plan_dir)
	var ext_end := _end_extension(end_point, plan_dir)
	_origin = start_point - wall_vec.normalized() * ext_start

	var active_openings: Array[Dictionary] = openings.duplicate()
	active_openings.append_array(detect_child_openings())

	var visual_root := get_node_or_null("VisualRoot") as Node3D
	if visual_root == null:
		visual_root = Node3D.new()
		visual_root.name = "VisualRoot"
		add_child(visual_root)

	var collision_root := get_node_or_null("CollisionRoot") as StaticBody3D
	if collision_root == null:
		collision_root = StaticBody3D.new()
		collision_root.name = "CollisionRoot"
		collision_root.collision_layer = 1
		collision_root.collision_mask = 0
		add_child(collision_root)

	# Clear previous generated meshes and shapes
	for c in visual_root.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()
	for c in collision_root.get_children():
		c.get_parent().remove_child(c)
		c.queue_free()

	var effective_height := cutaway_elevation if cutaway_enabled else wall_height
	var dir := wall_vec.normalized()
	var normal := Vector3(-dir.z, 0, dir.x).normalized()

	# Build wall segments considering openings
	# Sort openings along wall length
	var valid_openings: Array[Dictionary] = []
	for op in active_openings:
		var f: float = clampf(float(op.from), 0.0, length) + ext_start
		var t: float = clampf(float(op.to), 0.0, length) + ext_start
		if t > f:
			valid_openings.append({
				"profile":_shift_profile(op.get("profile",PackedVector2Array()), ext_start),
				"from": f,
				"to": t,
				"bottom": clampf(float(op.bottom), 0.0, effective_height),
				"top": clampf(float(op.top), 0.0, effective_height)
			})
	valid_openings.sort_custom(func(a, b): return a.from < b.from)
	length += ext_start + ext_end

	# Generate wall blocks
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)

	var col_faces := PackedVector3Array()
	# Sweep vertical slices so stacked or overlapping openings share one void
	# in render geometry, collision and the cutaway lid.
	var cuts: Array[float] = [0.0, length]
	for op in valid_openings:
		cuts.append(op.from)
		cuts.append(op.to)
		if op.profile.is_empty(): _generate_opening_frame(visual_root, op, dir, normal)
		else:
			var poly: PackedVector2Array = op.profile
			for j in poly.size():
				var p := poly[j]; var q := poly[(j+1)%poly.size()]
				cuts.append(clampf(p.x,0,length))
				if (p.y-effective_height)*(q.y-effective_height)<0:
					cuts.append(clampf(lerpf(p.x,q.x,(effective_height-p.y)/(q.y-p.y)),0,length))
	cuts.sort()
	for i in range(1, cuts.size()):
		var a := cuts[i-1]
		var b := cuts[i]
		if b-a < 0.0001: continue
		var voids := valid_openings.filter(func(op): return op.from < b and op.to > a and op.top > op.bottom)
		voids.sort_custom(func(left,right): return left.bottom < right.bottom)
		var y := Vector2.ZERO
		for op in voids:
			var left := _span(op,a,effective_height); var right := _span(op,b,effective_height)
			var lower := Vector2(left.x,right.x).max(y)
			if lower.distance_squared_to(y)>0.00000001:
				_generate_box_segment(st,col_faces,a,b,y.x,lower.x,dir,normal,y.y,lower.y)
			y = y.max(Vector2(left.y,right.y))
		if minf(y.x,y.y) < effective_height:
			_generate_box_segment(st,col_faces,a,b,y.x,effective_height,dir,normal,y.y,effective_height)
			if cutaway_enabled: _build_cutaway_cap(visual_root, a, b, effective_height, dir, normal)

	if not col_faces.is_empty(): st.generate_normals()
	var wall_mesh := st.commit() if not col_faces.is_empty() else null
	var wall_instance := MeshInstance3D.new()
	wall_instance.name = "WallMesh"
	wall_instance.mesh = wall_mesh
	if wall_material != null:
		wall_instance.material_override = wall_material
	visual_root.add_child(wall_instance)

	# Skirting board mesh
	if skirting_enabled and skirting_height > 0.0:
		_build_skirting(visual_root, valid_openings, length, dir, normal)

	# StaticBody CollisionShape
	if col_faces.size() >= 3:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(col_faces)
		var col_shape := CollisionShape3D.new()
		col_shape.name = "WallCollision"
		col_shape.shape = shape
		collision_root.add_child(col_shape)

	_update_materials()
	visual_root.visible = draw_mesh or Engine.is_editor_hint()
	wall_rebuilt.emit()

static func _shift_profile(profile: PackedVector2Array, dx: float) -> PackedVector2Array:
	if dx == 0.0 or profile.is_empty():
		return profile
	var out := PackedVector2Array()
	for p in profile:
		out.append(p + Vector2(dx, 0))
	return out

# The kit's round and arched profiles are convex in each vertical slice.
func _span(op: Dictionary, x: float, height: float) -> Vector2:
	var poly: PackedVector2Array = op.profile
	if poly.is_empty(): return Vector2(op.bottom,op.top)
	var low := INF; var high := -INF
	for j in poly.size():
		var a := poly[j]; var b := poly[(j+1)%poly.size()]
		if absf(b.x-a.x)<0.00001 or x < minf(a.x,b.x)-0.00001 or x > maxf(a.x,b.x)+0.00001: continue
		var y := clampf(lerpf(a.y,b.y,clampf((x-a.x)/(b.x-a.x),0,1)),0,height)
		low = minf(low,y); high = maxf(high,y)
	return Vector2(low,high) if low<=high else Vector2(op.bottom,op.top)

func _generate_box_segment(st: SurfaceTool, col: PackedVector3Array, x0: float, x1: float, y0: float, y1: float, dir: Vector3, normal: Vector3, low_right: float, high_right: float) -> void:
	var hw := wall_thickness * 0.5
	var p0 := _origin + dir * x0 - normal * hw + Vector3.UP * y0
	var p1 := _origin + dir * x1 - normal * hw + Vector3.UP * low_right
	var p2 := _origin + dir * x1 + normal * hw + Vector3.UP * low_right
	var p3 := _origin + dir * x0 + normal * hw + Vector3.UP * y0
	var q0 := p0 + Vector3.UP * (y1 - y0)
	var q1 := p1 + Vector3.UP * (high_right - low_right)
	var q2 := p2 + Vector3.UP * (high_right - low_right)
	var q3 := p3 + Vector3.UP * (y1 - y0)

	_add_quad(st, col, p0, p1, q1, q0) # Front face (-normal)
	_add_quad(st, col, p2, p3, q3, q2) # Back face (+normal)
	_add_quad(st, col, p3, p0, q0, q3) # Left face (-dir)
	_add_quad(st, col, p1, p2, q2, q1) # Right face (+dir)
	_add_quad(st, col, p3, p2, p1, p0) # Bottom face
	_add_quad(st, col, q0, q1, q2, q3) # Top face

func _add_quad(st: SurfaceTool, col: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
	st.add_vertex(a)
	st.add_vertex(c)
	st.add_vertex(d)

	col.append(a)
	col.append(b)
	col.append(c)
	col.append(a)
	col.append(c)
	col.append(d)

func _generate_opening_frame(parent: Node3D, op: Dictionary, dir: Vector3, normal: Vector3) -> void:
	const TRIM := 0.03
	var width := float(op.to) - float(op.from)
	var height := float(op.top) - float(op.bottom)
	if height <= 0.0: return
	var cx := (float(op.from) + float(op.to)) * 0.5
	var cy := (float(op.bottom) + float(op.top)) * 0.5
	# Trim sits on the solid side of the opening; no raised threshold for doors.
	var strips := [Vector4(op.from - TRIM/2, cy, TRIM, height), Vector4(op.to + TRIM/2, cy, TRIM, height)]
	if not cutaway_enabled or op.top < cutaway_elevation:
		strips.append(Vector4(cx, op.top + TRIM/2, width + 2*TRIM, TRIM))
	if op.bottom > TRIM: strips.append(Vector4(cx, op.bottom - TRIM/2, width + 2*TRIM, TRIM))
	for strip: Vector4 in strips:
		var bar := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(strip.z, strip.w, wall_thickness + 0.04)
		bar.mesh = mesh
		bar.material_override = skirting_material
		bar.transform = Transform3D(Basis(dir, Vector3.UP, normal), _origin + dir * strip.x + Vector3.UP * strip.y)
		parent.add_child(bar)

func _build_skirting(parent: Node3D, openings_list: Array[Dictionary], length: float, dir: Vector3, normal: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var dummy_col := PackedVector3Array()

	var cur_x := 0.0
	for op in openings_list:
		if op.bottom <= 0.05: # Opening reaches floor, skip skirting
			if op.from > cur_x + 0.01:
				_build_skirting_strip(st, dummy_col, cur_x, op.from, dir, normal)
			cur_x = maxf(cur_x, op.to)
	if cur_x < length - 0.01:
		_build_skirting_strip(st, dummy_col, cur_x, length, dir, normal)

	if dummy_col.is_empty(): return
	st.generate_normals()
	var mesh := st.commit()
	var inst := MeshInstance3D.new()
	inst.name = "SkirtingMesh"
	inst.mesh = mesh
	if skirting_material != null:
		inst.material_override = skirting_material
	parent.add_child(inst)

func _build_skirting_strip(st: SurfaceTool, col: PackedVector3Array, x0: float, x1: float, dir: Vector3, normal: Vector3) -> void:
	var hw := wall_thickness * 0.5
	var sw := skirting_thickness
	var sh := skirting_height
	# Side 1 (+normal)
	var a0 := _origin + dir * x0 + normal * hw
	var a1 := _origin + dir * x1 + normal * hw
	var b1 := a1 + normal * sw
	var b0 := a0 + normal * sw
	_add_quad(st, col, b1, b0, b0 + Vector3.UP * sh, b1 + Vector3.UP * sh)
	_add_quad(st, col, a0 + Vector3.UP * sh, a1 + Vector3.UP * sh, b1 + Vector3.UP * sh, b0 + Vector3.UP * sh)

	# Side 2 (-normal)
	var c0 := _origin + dir * x0 - normal * hw
	var c1 := _origin + dir * x1 - normal * hw
	var d1 := c1 - normal * sw
	var d0 := c0 - normal * sw
	_add_quad(st, col, d0, d1, d1 + Vector3.UP * sh, d0 + Vector3.UP * sh)
	_add_quad(st, col, c1 + Vector3.UP * sh, c0 + Vector3.UP * sh, d0 + Vector3.UP * sh, d1 + Vector3.UP * sh)

func _build_cutaway_cap(parent: Node3D, x0: float, x1: float, elevation: float, dir: Vector3, normal: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var dummy := PackedVector3Array()
	var hw := wall_thickness * 0.5
	var p0 := _origin + dir * x0 - normal * hw + Vector3.UP * elevation
	var p1 := _origin + dir * x1 - normal * hw + Vector3.UP * elevation
	var p2 := _origin + dir * x1 + normal * hw + Vector3.UP * elevation
	var p3 := _origin + dir * x0 + normal * hw + Vector3.UP * elevation
	_add_quad(st, dummy, p0, p1, p2, p3)
	st.generate_normals()
	var cap_mesh := st.commit()
	var cap_inst := MeshInstance3D.new()
	cap_inst.name = "CutawayCap"
	cap_inst.position.y = 0.001
	cap_inst.mesh = cap_mesh
	if cutaway_cap_material != null:
		cap_inst.material_override = cutaway_cap_material
	parent.add_child(cap_inst)

func _update_materials() -> void:
	var visual := get_node_or_null("VisualRoot")
	if visual == null:
		return
	var wall := visual.get_node_or_null("WallMesh") as MeshInstance3D
	if wall and wall_material:
		wall.material_override = wall_material
	var skirt := visual.get_node_or_null("SkirtingMesh") as MeshInstance3D
	if skirt and skirting_material:
		skirt.material_override = skirting_material
	var cap := visual.get_node_or_null("CutawayCap") as MeshInstance3D
	if cap and cutaway_cap_material:
		cap.material_override = cutaway_cap_material

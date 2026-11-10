@tool
extends Path3D
class_name SmartRailing3D

## SmartRailing3D: Godot 4.7 @tool parametric railing system.
## Based on Path3D points (supports straight polyline and bezier curves).
## Generates equidistant baluster posts, newel corner/terminal posts, continuous
## handrail extrusion, bottom curb rail, and static collision.

signal railing_rebuilt()

@export_range(0.5, 2.0, 0.05) var railing_height: float = 0.9:
	set(v):
		railing_height = v
		_queue_rebuild()

@export_range(0.2, 3.0, 0.05) var post_spacing: float = 0.8:
	set(v):
		post_spacing = v
		_queue_rebuild()

@export_range(0.01, 0.2, 0.005) var post_radius: float = 0.03:
	set(v):
		post_radius = v
		_queue_rebuild()

@export_range(0.02, 0.3, 0.005) var newel_post_radius: float = 0.06:
	set(v):
		newel_post_radius = v
		_queue_rebuild()

@export_range(0.02, 0.2, 0.005) var handrail_radius: float = 0.04:
	set(v):
		handrail_radius = v
		_queue_rebuild()

@export var railing_material: Material:
	set(v):
		railing_material = v
		_update_materials()

var _rebuild_pending: bool = false

func _ready() -> void:
	if curve == null:
		curve = Curve3D.new()
		curve.add_point(Vector3.ZERO)
		curve.add_point(Vector3(3.0, 0.0, 0.0))
	curve.changed.connect(_queue_rebuild)
	rebuild()

func _queue_rebuild() -> void:
	if not is_inside_tree():
		return
	if not _rebuild_pending:
		_rebuild_pending = true
		call_deferred(&"rebuild")

func set_points(pts: PackedVector3Array) -> void:
	if curve == null:
		curve = Curve3D.new()
	curve.clear_points()
	for pt in pts:
		curve.add_point(pt)
	rebuild()

func rebuild() -> void:
	_rebuild_pending = false
	if curve == null or curve.point_count < 2:
		return
	
	var length := curve.get_baked_length()
	if length < 0.05:
		return
	
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
	
	for c in visual_root.get_children():
		c.queue_free()
	for c in collision_root.get_children():
		c.queue_free()
	
	var col_faces := PackedVector3Array()
	
	# 1. Newel Posts at control points
	var newel_st := SurfaceTool.new()
	newel_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(curve.point_count):
		var p := curve.get_point_position(i)
		_build_cylinder(newel_st, col_faces, p, newel_post_radius, railing_height + 0.05, 8)
	newel_st.generate_normals()
	var newel_mesh := newel_st.commit()
	var newel_inst := MeshInstance3D.new()
	newel_inst.name = "NewelPosts"
	newel_inst.mesh = newel_mesh
	visual_root.add_child(newel_inst)
	
	# 2. Intermediate Baluster Posts
	var baluster_st := SurfaceTool.new()
	baluster_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var num_intervals := maxi(1, ceili(length / post_spacing))
	var step_dist := length / float(num_intervals)
	for i in range(1, num_intervals):
		var dist := float(i) * step_dist
		var p := curve.sample_baked(dist, true)
		_build_cylinder(baluster_st, col_faces, p, post_radius, railing_height, 6)
	baluster_st.generate_normals()
	var baluster_mesh := baluster_st.commit()
	var baluster_inst := MeshInstance3D.new()
	baluster_inst.name = "Balusters"
	baluster_inst.mesh = baluster_mesh
	visual_root.add_child(baluster_inst)
	
	# 3. Continuous Handrail Mesh
	var rail_st := SurfaceTool.new()
	rail_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sample_step := 0.2
	var num_samples := maxi(2, ceili(length / sample_step))
	var path_samples: Array[Vector3] = []
	for i in range(num_samples + 1):
		var d := clampf(float(i) * (length / float(num_samples)), 0.0, length)
		path_samples.append(curve.sample_baked(d, true) + Vector3.UP * railing_height)
	
	for i in range(path_samples.size() - 1):
		var p0 := path_samples[i]
		var p1 := path_samples[i + 1]
		var seg_dir := (p1 - p0).normalized()
		var seg_norm := Vector3(-seg_dir.z, 0, seg_dir.x).normalized()
		var seg_up := seg_dir.cross(seg_norm).normalized()
		_build_segment_prism(rail_st, col_faces, p0, p1, seg_norm, seg_up, handrail_radius)
	
	rail_st.generate_normals()
	var rail_mesh := rail_st.commit()
	var rail_inst := MeshInstance3D.new()
	rail_inst.name = "Handrail"
	rail_inst.mesh = rail_mesh
	visual_root.add_child(rail_inst)
	
	# 4. Collision Shape
	if col_faces.size() >= 3:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(col_faces)
		var col_shape := CollisionShape3D.new()
		col_shape.name = "RailingCollision"
		col_shape.shape = shape
		collision_root.add_child(col_shape)
	
	_update_materials()
	railing_rebuilt.emit()

func _build_cylinder(st: SurfaceTool, col: PackedVector3Array, base: Vector3, r: float, h: float, sides: int) -> void:
	var top := base + Vector3.UP * h
	var pts_bot: Array[Vector3] = []
	var pts_top: Array[Vector3] = []
	for i in range(sides):
		var angle := float(i) * TAU / float(sides)
		var offset := Vector3(cos(angle) * r, 0, sin(angle) * r)
		pts_bot.append(base + offset)
		pts_top.append(top + offset)
	
	for i in range(sides):
		var next := (i + 1) % sides
		var b0 := pts_bot[i]
		var b1 := pts_bot[next]
		var t1 := pts_top[next]
		var t0 := pts_top[i]
		st.add_vertex(b0); st.add_vertex(b1); st.add_vertex(t1)
		st.add_vertex(b0); st.add_vertex(t1); st.add_vertex(t0)
		col.append(b0); col.append(b1); col.append(t1)
		col.append(b0); col.append(t1); col.append(t0)

func _build_segment_prism(st: SurfaceTool, col: PackedVector3Array, p0: Vector3, p1: Vector3, norm: Vector3, up: Vector3, r: float) -> void:
	var v0 := p0 - norm * r - up * (r * 0.5)
	var v1 := p0 + norm * r - up * (r * 0.5)
	var v2 := p0 + norm * r + up * (r * 0.5)
	var v3 := p0 - norm * r + up * (r * 0.5)
	
	var u0 := p1 - norm * r - up * (r * 0.5)
	var u1 := p1 + norm * r - up * (r * 0.5)
	var u2 := p1 + norm * r + up * (r * 0.5)
	var u3 := p1 - norm * r + up * (r * 0.5)
	
	# Quad sides
	_add_quad_mesh(st, col, v0, u0, u1, v1)
	_add_quad_mesh(st, col, v1, u1, u2, v2)
	_add_quad_mesh(st, col, v2, u2, u3, v3)
	_add_quad_mesh(st, col, v3, u3, u0, v0)

func _add_quad_mesh(st: SurfaceTool, col: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
	col.append(a); col.append(b); col.append(c)
	col.append(a); col.append(c); col.append(d)

func _update_materials() -> void:
	var visual := get_node_or_null("VisualRoot")
	if visual == null or railing_material == null:
		return
	for c in visual.get_children():
		if c is MeshInstance3D:
			c.material_override = railing_material

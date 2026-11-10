@tool
extends Node3D
class_name SmartStair3D

## SmartStair3D: Godot 4.7 @tool parametric stair generator.
## Dual handle stretch (start_point -> end_point), auto step calculation based on
## standard 0.18m rise, chamfered treads, smooth ramp collision, and optional
## synchronized SmartRailing3D on left and/or right sides.

signal stair_rebuilt()

@export var start_point: Vector3 = Vector3.ZERO:
	set(v):
		start_point = v
		_queue_rebuild()

@export var end_point: Vector3 = Vector3(3.0, 2.0, 0.0):
	set(v):
		end_point = v
		_queue_rebuild()

@export_range(0.6, 5.0, 0.1) var stair_width: float = 1.2:
	set(v):
		stair_width = maxf(0.5, v)
		_queue_rebuild()

@export_range(0.12, 0.25, 0.01) var standard_step_height: float = 0.18:
	set(v):
		standard_step_height = maxf(0.05, v)
		_queue_rebuild()

@export_range(0.02, 0.1, 0.01) var tread_thickness: float = 0.04:
	set(v):
		tread_thickness = v
		_queue_rebuild()

@export_range(0.01, 0.05, 0.005) var tread_nosing: float = 0.03:
	set(v):
		tread_nosing = v
		_queue_rebuild()

@export_group("Railings")
@export var has_left_railing: bool = false:
	set(v):
		has_left_railing = v
		_queue_rebuild()

@export var has_right_railing: bool = false:
	set(v):
		has_right_railing = v
		_queue_rebuild()

@export_group("Materials")
@export var stair_material: Material:
	set(v):
		stair_material = v
		_update_materials()

@export var railing_material: Material:
	set(v):
		railing_material = v
		_update_materials()

var _rebuild_pending: bool = false

func _ready() -> void:
	rebuild()

func _queue_rebuild() -> void:
	if not is_inside_tree():
		return
	if not _rebuild_pending:
		_rebuild_pending = true
		call_deferred(&"rebuild")

func rebuild() -> void:
	_rebuild_pending = false
	var total_rise := end_point.y - start_point.y
	var horizontal_vec := Vector3(end_point.x - start_point.x, 0, end_point.z - start_point.z)
	var run_length := horizontal_vec.length()
	if run_length < 0.2 or absf(total_rise) < 0.1:
		return
	
	var step_count := maxi(1, int(round(absf(total_rise) / standard_step_height)))
	var actual_step_height := total_rise / float(step_count)
	var step_depth := run_length / float(step_count)
	
	var dir := horizontal_vec.normalized()
	var normal := Vector3(-dir.z, 0, dir.x).normalized()
	var half_width := stair_width * 0.5
	
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
	
	# 1. Build Treads & Risers Mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dummy_col := PackedVector3Array()
	
	for i in range(step_count):
		# start_point already contains world elevation; add only the relative rise.
		var step_start_h := float(i) * actual_step_height
		var step_top_h := step_start_h + actual_step_height
		var x0 := float(i) * step_depth
		var x1 := float(i + 1) * step_depth
		
		# Riser (vertical face)
		var r_b0 := start_point + dir * x0 - normal * half_width + Vector3.UP * step_start_h
		var r_b1 := start_point + dir * x0 + normal * half_width + Vector3.UP * step_start_h
		var r_t1 := start_point + dir * x0 + normal * half_width + Vector3.UP * step_top_h
		var r_t0 := start_point + dir * x0 - normal * half_width + Vector3.UP * step_top_h
		_add_quad(st, dummy_col, r_b0, r_b1, r_t1, r_t0)
		
		# Tread (horizontal surface with nosing overhang)
		var t_f0 := start_point + dir * (x0 - tread_nosing) - normal * half_width + Vector3.UP * step_top_h
		var t_f1 := start_point + dir * (x0 - tread_nosing) + normal * half_width + Vector3.UP * step_top_h
		var t_b1 := start_point + dir * x1 + normal * half_width + Vector3.UP * step_top_h
		var t_b0 := start_point + dir * x1 - normal * half_width + Vector3.UP * step_top_h
		_add_quad(st, dummy_col, t_f0, t_b0, t_b1, t_f1)
		
		# Tread front lip
		var lip_b0 := t_f0 - Vector3.UP * tread_thickness
		var lip_b1 := t_f1 - Vector3.UP * tread_thickness
		_add_quad(st, dummy_col, lip_b0, lip_b1, t_f1, t_f0)
	
	st.generate_normals()
	var stair_mesh := st.commit()
	var stair_inst := MeshInstance3D.new()
	stair_inst.name = "StairMesh"
	stair_inst.mesh = stair_mesh
	if stair_material != null:
		stair_inst.material_override = stair_material
	visual_root.add_child(stair_inst)
	
	# 2. Ramp Collision Body (smooth wedge)
	var p_bot_l := start_point - normal * half_width
	var p_bot_r := start_point + normal * half_width
	var p_top_l := start_point + dir * run_length - normal * half_width + Vector3.UP * total_rise
	var p_top_r := start_point + dir * run_length + normal * half_width + Vector3.UP * total_rise
	var p_base_top_l := start_point + dir * run_length - normal * half_width
	var p_base_top_r := start_point + dir * run_length + normal * half_width
	
	var ramp_faces := PackedVector3Array([
		# Top slope
		p_bot_l, p_top_l, p_top_r,
		p_bot_l, p_top_r, p_bot_r,
		# Bottom base
		p_bot_l, p_bot_r, p_base_top_r,
		p_bot_l, p_base_top_r, p_base_top_l,
		# Back vertical face
		p_base_top_l, p_base_top_r, p_top_r,
		p_base_top_l, p_top_r, p_top_l,
		# Left side triangle
		p_bot_l, p_base_top_l, p_top_l,
		# Right side triangle
		p_bot_r, p_top_r, p_base_top_r
	])
	var ramp_shape := ConcavePolygonShape3D.new()
	ramp_shape.set_faces(ramp_faces)
	var col_shape := CollisionShape3D.new()
	col_shape.name = "RampCollision"
	col_shape.shape = ramp_shape
	collision_root.add_child(col_shape)
	
	# 3. Synchronized Railings
	_sync_railings(half_width, normal)
	
	_update_materials()
	stair_rebuilt.emit()

func _sync_railings(half_width: float, normal: Vector3) -> void:
	var left_railing := get_node_or_null("LeftRailing") as SmartRailing3D
	if has_left_railing:
		if left_railing == null:
			left_railing = SmartRailing3D.new()
			left_railing.name = "LeftRailing"
			add_child(left_railing)
		var pts := PackedVector3Array([
			start_point - normal * half_width,
			end_point - normal * half_width
		])
		left_railing.set_points(pts)
		if railing_material != null:
			left_railing.railing_material = railing_material
	elif left_railing != null:
		left_railing.queue_free()
	
	var right_railing := get_node_or_null("RightRailing") as SmartRailing3D
	if has_right_railing:
		if right_railing == null:
			right_railing = SmartRailing3D.new()
			right_railing.name = "RightRailing"
			add_child(right_railing)
		var pts := PackedVector3Array([
			start_point + normal * half_width,
			end_point + normal * half_width
		])
		right_railing.set_points(pts)
		if railing_material != null:
			right_railing.railing_material = railing_material
	elif right_railing != null:
		right_railing.queue_free()

func _add_quad(st: SurfaceTool, col: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	st.add_vertex(a); st.add_vertex(b); st.add_vertex(c)
	st.add_vertex(a); st.add_vertex(c); st.add_vertex(d)
	col.append(a); col.append(b); col.append(c)
	col.append(a); col.append(c); col.append(d)

func _update_materials() -> void:
	var visual := get_node_or_null("VisualRoot")
	if visual != null and stair_material != null:
		var stair_mesh := visual.get_node_or_null("StairMesh") as MeshInstance3D
		if stair_mesh != null:
			stair_mesh.material_override = stair_material
	var left_railing := get_node_or_null("LeftRailing") as SmartRailing3D
	if left_railing != null and railing_material != null:
		left_railing.railing_material = railing_material
	var right_railing := get_node_or_null("RightRailing") as SmartRailing3D
	if right_railing != null and railing_material != null:
		right_railing.railing_material = railing_material

@tool
extends Node3D
class_name SmartWall3D

## SmartWall3D: Godot 4.7 @tool parametric wall component.
## Supports grid-snap dragging (start_point -> end_point), automatic skirting boards,
## cutaway caps (for cutaway view inspection), and automatic opening cutout when
## doors or windows are placed upon it.

signal wall_rebuilt()

@export var start_point: Vector3 = Vector3.ZERO:
	set(v):
		start_point = _snap_vector(v)
		_queue_rebuild()

@export var end_point: Vector3 = Vector3(4.0, 0.0, 0.0):
	set(v):
		end_point = _snap_vector(v)
		_queue_rebuild()

@export_range(0.5, 10.0, 0.1) var wall_height: float = 3.0:
	set(v):
		wall_height = maxf(0.5, v)
		_queue_rebuild()

@export_range(0.05, 1.0, 0.05) var wall_thickness: float = 0.25:
	set(v):
		wall_thickness = maxf(0.05, v)
		_queue_rebuild()

@export_range(0.05, 1.0, 0.05) var grid_snap: float = 0.25

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
var _rebuild_pending: bool = false

func _ready() -> void:
	rebuild()

func _snap_vector(v: Vector3) -> Vector3:
	if grid_snap <= 0.0:
		return v
	return Vector3(
		snappedf(v.x, grid_snap),
		snappedf(v.y, grid_snap),
		snappedf(v.z, grid_snap)
	)

func _queue_rebuild() -> void:
	if not is_inside_tree():
		return
	if not _rebuild_pending:
		_rebuild_pending = true
		call_deferred(&"rebuild")

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

func detect_child_openings() -> Array[Dictionary]:
	var detected: Array[Dictionary] = []
	var wall_dir := end_point - start_point
	var wall_length := wall_dir.length()
	if wall_length < 0.001: return detected
	var wall_norm := wall_dir.normalized()
	for child in get_children():
		if child is Node3D and (child.has_method("get_leaf_width") or child.name.contains("Door") or child.name.contains("Window")):
			var child_pos: Vector3 = child.position
			var proj_dist: float = (child_pos - start_point).dot(wall_norm)
			if proj_dist >= -0.2 and proj_dist <= wall_length + 0.2:
				var w: float = child.get("leaf_width") if "leaf_width" in child else 0.9
				var h: float = child.get("leaf_height") if "leaf_height" in child else 2.1
				var bottom_h: float = child_pos.y
				detected.append({"from":proj_dist - w * 0.5,"to":proj_dist + w * 0.5,"bottom":bottom_h,"top":bottom_h + h})
	return detected

func rebuild() -> void:
	_rebuild_pending = false
	var wall_vec := end_point - start_point
	var length := wall_vec.length()
	if length < 0.05:
		return
	
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
		c.queue_free()
	for c in collision_root.get_children():
		c.queue_free()
	
	var effective_height := cutaway_elevation if cutaway_enabled else wall_height
	var dir := wall_vec.normalized()
	var normal := Vector3(-dir.z, 0, dir.x).normalized()
	
	# Build wall segments considering openings
	# Sort openings along wall length
	var valid_openings: Array[Dictionary] = []
	for op in active_openings:
		var f: float = clampf(float(op.from), 0.0, length)
		var t: float = clampf(float(op.to), 0.0, length)
		if t > f:
			valid_openings.append({
				"from": f,
				"to": t,
				"bottom": clampf(float(op.bottom), 0.0, effective_height),
				"top": clampf(float(op.top), 0.0, effective_height)
			})
	valid_openings.sort_custom(func(a, b): return a.from < b.from)
	
	# Generate wall blocks
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	var col_faces := PackedVector3Array()
	var current_x: float = 0.0
	
	for op in valid_openings:
		# Segment to the left of opening
		if op.from > current_x + 0.01:
			_generate_box_segment(st, col_faces, current_x, op.from, 0.0, effective_height, dir, normal)
		
		# Below opening (e.g. window sill)
		if op.bottom > 0.01:
			_generate_box_segment(st, col_faces, op.from, op.to, 0.0, op.bottom, dir, normal)
		
		# Above opening (lintel / over-door)
		if op.top < effective_height - 0.01:
			_generate_box_segment(st, col_faces, op.from, op.to, op.top, effective_height, dir, normal)
		
		# Opening frame trim
		_generate_opening_frame(visual_root, op, dir, normal)
		
		current_x = op.to
	
	# Final segment to the right of last opening
	if current_x < length - 0.01:
		_generate_box_segment(st, col_faces, current_x, length, 0.0, effective_height, dir, normal)
	
	st.generate_normals()
	var wall_mesh := st.commit()
	var wall_instance := MeshInstance3D.new()
	wall_instance.name = "WallMesh"
	wall_instance.mesh = wall_mesh
	if wall_material != null:
		wall_instance.material_override = wall_material
	visual_root.add_child(wall_instance)
	
	# Skirting board mesh
	if skirting_enabled and skirting_height > 0.0:
		_build_skirting(visual_root, valid_openings, length, dir, normal)
	
	# Cutaway Cap (if enabled)
	if cutaway_enabled:
		_build_cutaway_cap(visual_root, length, effective_height, dir, normal)
	
	# StaticBody CollisionShape
	if col_faces.size() >= 3:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(col_faces)
		var col_shape := CollisionShape3D.new()
		col_shape.name = "WallCollision"
		col_shape.shape = shape
		collision_root.add_child(col_shape)
	
	_update_materials()
	wall_rebuilt.emit()

func _generate_box_segment(st: SurfaceTool, col: PackedVector3Array, x0: float, x1: float, y0: float, y1: float, dir: Vector3, normal: Vector3) -> void:
	var hw := wall_thickness * 0.5
	var p0 := start_point + dir * x0 - normal * hw + Vector3.UP * y0
	var p1 := start_point + dir * x1 - normal * hw + Vector3.UP * y0
	var p2 := start_point + dir * x1 + normal * hw + Vector3.UP * y0
	var p3 := start_point + dir * x0 + normal * hw + Vector3.UP * y0
	var q0 := p0 + Vector3.UP * (y1 - y0)
	var q1 := p1 + Vector3.UP * (y1 - y0)
	var q2 := p2 + Vector3.UP * (y1 - y0)
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
	var frame_node := Node3D.new()
	frame_node.name = "Frame_%.1f_%.1f" % [op.from, op.to]
	var center_x: float = (op.from + op.to) * 0.5
	var center_y: float = (op.bottom + op.top) * 0.5
	var pos := start_point + dir * center_x + Vector3.UP * center_y
	frame_node.position = pos
	
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "FrameMesh"
	var box := BoxMesh.new()
	var w: float = op.to - op.from + 0.06
	var h: float = op.top - op.bottom + 0.06
	box.size = Vector3(w, h, wall_thickness + 0.04)
	mesh_inst.mesh = box
	if skirting_material != null:
		mesh_inst.material_override = skirting_material
	frame_node.add_child(mesh_inst)
	parent.add_child(frame_node)

func _build_skirting(parent: Node3D, openings_list: Array[Dictionary], length: float, dir: Vector3, normal: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dummy_col := PackedVector3Array()
	
	var cur_x := 0.0
	for op in openings_list:
		if op.bottom <= 0.05: # Opening reaches floor, skip skirting
			if op.from > cur_x + 0.01:
				_build_skirting_strip(st, dummy_col, cur_x, op.from, dir, normal)
			cur_x = op.to
	if cur_x < length - 0.01:
		_build_skirting_strip(st, dummy_col, cur_x, length, dir, normal)
	
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
	var a0 := start_point + dir * x0 + normal * hw
	var a1 := start_point + dir * x1 + normal * hw
	var b1 := a1 + normal * sw
	var b0 := a0 + normal * sw
	_add_quad(st, col, a0, a1, a1 + Vector3.UP * sh, a0 + Vector3.UP * sh)
	_add_quad(st, col, b0, b1, b1 + Vector3.UP * sh, b0 + Vector3.UP * sh)
	_add_quad(st, col, a0 + Vector3.UP * sh, a1 + Vector3.UP * sh, b1 + Vector3.UP * sh, b0 + Vector3.UP * sh)
	
	# Side 2 (-normal)
	var c0 := start_point + dir * x0 - normal * hw
	var c1 := start_point + dir * x1 - normal * hw
	var d1 := c1 - normal * sw
	var d0 := c0 - normal * sw
	_add_quad(st, col, c1, c0, c0 + Vector3.UP * sh, c1 + Vector3.UP * sh)
	_add_quad(st, col, d1, d0, d0 + Vector3.UP * sh, d1 + Vector3.UP * sh)
	_add_quad(st, col, c0 + Vector3.UP * sh, c1 + Vector3.UP * sh, d1 + Vector3.UP * sh, d0 + Vector3.UP * sh)

func _build_cutaway_cap(parent: Node3D, length: float, elevation: float, dir: Vector3, normal: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var dummy := PackedVector3Array()
	var hw := wall_thickness * 0.5
	var p0 := start_point - normal * hw + Vector3.UP * elevation
	var p1 := start_point + dir * length - normal * hw + Vector3.UP * elevation
	var p2 := start_point + dir * length + normal * hw + Vector3.UP * elevation
	var p3 := start_point + normal * hw + Vector3.UP * elevation
	_add_quad(st, dummy, p0, p1, p2, p3)
	st.generate_normals()
	var cap_mesh := st.commit()
	var cap_inst := MeshInstance3D.new()
	cap_inst.name = "CutawayCap"
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

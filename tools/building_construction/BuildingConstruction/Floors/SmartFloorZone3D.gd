@tool
extends Node3D
class_name SmartFloorZone3D

## SmartFloorZone3D: Godot 4.7 @tool parametric floor zone and room boundary.
## Generates polygon floor parquet/stone slab, ceiling (optional), editor reference grid,
## and registers room culling AABB bounds with RoomStreamingController.

signal floor_zone_rebuilt()

@export var room_id: String = "":
	set(v):
		room_id = v
		_queue_rebuild()

@export var polygon: PackedVector2Array = PackedVector2Array([
	Vector2(-3.0, -3.0),
	Vector2(3.0, -3.0),
	Vector2(3.0, 3.0),
	Vector2(-3.0, 3.0)
]):
	set(v):
		polygon = v
		_queue_rebuild()

@export_range(0.05, 1.0, 0.05) var floor_thickness: float = 0.2:
	set(v):
		floor_thickness = v
		_queue_rebuild()

@export var ceiling_enabled: bool = false:
	set(v):
		ceiling_enabled = v
		_queue_rebuild()

@export_range(2.0, 6.0, 0.1) var ceiling_height: float = 3.0:
	set(v):
		ceiling_height = v
		_queue_rebuild()

@export var show_grid: bool = true:
	set(v):
		show_grid = v
		_queue_rebuild()

@export_range(0.1, 1.0, 0.05) var grid_step: float = 0.25:
	set(v):
		grid_step = v
		_queue_rebuild()

@export_group("Materials")
@export var floor_material: Material:
	set(v):
		floor_material = v
		_update_materials()

@export var ceiling_material: Material:
	set(v):
		ceiling_material = v
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

func get_zone_aabb() -> AABB:
	if polygon.size() < 3:
		return AABB(global_position, Vector3(1, 1, 1))
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for pt in polygon:
		min_x = minf(min_x, pt.x)
		max_x = maxf(max_x, pt.x)
		min_z = minf(min_z, pt.y)
		max_z = maxf(max_z, pt.y)
	var size := Vector3(max_x - min_x, ceiling_height, max_z - min_z)
	return AABB(Vector3(min_x, -floor_thickness, min_z), size)

func rebuild() -> void:
	_rebuild_pending = false
	if polygon.size() < 3:
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
	
	# Triangulate polygon (2D in X-Z plane)
	var indices := Geometry2D.triangulate_polygon(polygon)
	if indices.size() < 3:
		return
	
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var col_faces := PackedVector3Array()
	
	# 1. Top floor surface (Y = 0, normal UP)
	for i in range(0, indices.size(), 3):
		var p0_2d := polygon[indices[i]]
		var p1_2d := polygon[indices[i + 1]]
		var p2_2d := polygon[indices[i + 2]]
		var v0 := Vector3(p0_2d.x, 0.0, p0_2d.y)
		var v1 := Vector3(p1_2d.x, 0.0, p1_2d.y)
		var v2 := Vector3(p2_2d.x, 0.0, p2_2d.y)
		
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(v0.x, v0.z))
		st.add_vertex(v0)
		st.set_uv(Vector2(v1.x, v1.z))
		st.add_vertex(v1)
		st.set_uv(Vector2(v2.x, v2.z))
		st.add_vertex(v2)
		
		col_faces.append(v0)
		col_faces.append(v1)
		col_faces.append(v2)
	
	# 2. Bottom floor surface (Y = -floor_thickness, normal DOWN)
	for i in range(0, indices.size(), 3):
		var p0_2d := polygon[indices[i]]
		var p1_2d := polygon[indices[i + 1]]
		var p2_2d := polygon[indices[i + 2]]
		var v0 := Vector3(p0_2d.x, -floor_thickness, p0_2d.y)
		var v1 := Vector3(p1_2d.x, -floor_thickness, p1_2d.y)
		var v2 := Vector3(p2_2d.x, -floor_thickness, p2_2d.y)
		st.set_normal(Vector3.DOWN)
		st.add_vertex(v0); st.add_vertex(v2); st.add_vertex(v1)
		col_faces.append(v0); col_faces.append(v2); col_faces.append(v1)
	
	# 3. Perimeter side faces
	for i in range(polygon.size()):
		var next := (i + 1) % polygon.size()
		var a_2d := polygon[i]
		var b_2d := polygon[next]
		var t0 := Vector3(a_2d.x, 0.0, a_2d.y)
		var t1 := Vector3(b_2d.x, 0.0, b_2d.y)
		var b1 := Vector3(b_2d.x, -floor_thickness, b_2d.y)
		var b0 := Vector3(a_2d.x, -floor_thickness, a_2d.y)
		
		var side_dir := (t1 - t0).normalized()
		var side_norm := Vector3(side_dir.z, 0, -side_dir.x)
		st.set_normal(side_norm)
		st.add_vertex(t0); st.add_vertex(t1); st.add_vertex(b1)
		st.add_vertex(t0); st.add_vertex(b1); st.add_vertex(b0)
		col_faces.append(t0); col_faces.append(t1); col_faces.append(b1)
		col_faces.append(t0); col_faces.append(b1); col_faces.append(b0)
	
	var floor_mesh := st.commit()
	var floor_inst := MeshInstance3D.new()
	floor_inst.name = "FloorMesh"
	floor_inst.mesh = floor_mesh
	if floor_material != null:
		floor_inst.material_override = floor_material
	visual_root.add_child(floor_inst)
	
	# 4. Optional Ceiling
	if ceiling_enabled and ceiling_height > 0.0:
		var c_st := SurfaceTool.new()
		c_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in range(0, indices.size(), 3):
			var p0_2d := polygon[indices[i]]
			var p1_2d := polygon[indices[i + 1]]
			var p2_2d := polygon[indices[i + 2]]
			var v0 := Vector3(p0_2d.x, ceiling_height, p0_2d.y)
			var v1 := Vector3(p1_2d.x, ceiling_height, p1_2d.y)
			var v2 := Vector3(p2_2d.x, ceiling_height, p2_2d.y)
			c_st.set_normal(Vector3.DOWN)
			c_st.add_vertex(v0); c_st.add_vertex(v2); c_st.add_vertex(v1)
		var ceiling_mesh := c_st.commit()
		var ceil_inst := MeshInstance3D.new()
		ceil_inst.name = "CeilingMesh"
		ceil_inst.mesh = ceiling_mesh
		if ceiling_material != null:
			ceil_inst.material_override = ceiling_material
		visual_root.add_child(ceil_inst)
	
	# 5. Collision Shape
	if col_faces.size() >= 3:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(col_faces)
		var col_shape := CollisionShape3D.new()
		col_shape.name = "FloorCollision"
		col_shape.shape = shape
		collision_root.add_child(col_shape)
	
	# 6. Reference Grid (Editor Hint)
	if Engine.is_editor_hint() and show_grid:
		_build_reference_grid(visual_root)
	
	_update_materials()
	floor_zone_rebuilt.emit()

func _build_reference_grid(parent: Node3D) -> void:
	var im := ImmediateMesh.new()
	var inst := MeshInstance3D.new()
	inst.name = "ReferenceGrid"
	inst.mesh = im
	
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	inst.material_override = mat
	
	var aabb := get_zone_aabb()
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var x := aabb.position.x
	while x <= aabb.end.x:
		im.surface_add_vertex(Vector3(x, 0.005, aabb.position.z))
		im.surface_add_vertex(Vector3(x, 0.005, aabb.end.z))
		x += grid_step
	var z := aabb.position.z
	while z <= aabb.end.z:
		im.surface_add_vertex(Vector3(aabb.position.x, 0.005, z))
		im.surface_add_vertex(Vector3(aabb.end.x, 0.005, z))
		z += grid_step
	im.surface_end()
	parent.add_child(inst)

func _update_materials() -> void:
	var visual := get_node_or_null("VisualRoot")
	if visual == null:
		return
	var floor_inst := visual.get_node_or_null("FloorMesh") as MeshInstance3D
	if floor_inst != null and floor_material != null:
		floor_inst.material_override = floor_material
	var ceil_inst := visual.get_node_or_null("CeilingMesh") as MeshInstance3D
	if ceil_inst != null and ceiling_material != null:
		ceil_inst.material_override = ceiling_material

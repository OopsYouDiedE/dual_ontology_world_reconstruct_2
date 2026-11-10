@tool
extends Node3D
## Openable window sash generator with dedicated frame, glass, hinge and handle (Task 2.17, 2.18).
## Origin is at hinge pivot. Glass is a separate translucent material with solid collision
## when closed to block walking through or camera penetration.
## Window opening angle is strictly clamped with zero drift across multiple cycles.
const PhysicsLayers = preload("res://tools/building_construction/BuildingConstruction/Shared/PhysicsLayers.gd")

@export_range(0.2, 5.0, 0.05) var sash_width: float = 0.8:
	set(v):
		sash_width = v
		if Engine.is_editor_hint() and is_inside_tree():
			apply_dimensions(sash_width, sash_height, sash_thickness, frame_material, glass_material)

@export_range(0.2, 5.0, 0.05) var sash_height: float = 1.0:
	set(v):
		sash_height = v
		if Engine.is_editor_hint() and is_inside_tree():
			apply_dimensions(sash_width, sash_height, sash_thickness, frame_material, glass_material)

@export_range(0.01, 0.5, 0.005) var sash_thickness: float = 0.04:
	set(v):
		sash_thickness = v
		if Engine.is_editor_hint() and is_inside_tree():
			apply_dimensions(sash_width, sash_height, sash_thickness, frame_material, glass_material)

@export var frame_material: Material:
	set(v):
		frame_material = v
		if Engine.is_editor_hint() and is_inside_tree():
			apply_dimensions(sash_width, sash_height, sash_thickness, frame_material, glass_material)

@export var glass_material: Material:
	set(v):
		glass_material = v
		if Engine.is_editor_hint() and is_inside_tree():
			apply_dimensions(sash_width, sash_height, sash_thickness, frame_material, glass_material)

@export_range(-180.0, 180.0, 1.0) var current_angle: float = 0.0:
	set(v):
		current_angle = v
		if is_instance_valid(hinge_node):
			hinge_node.rotation_degrees.y = current_angle
		elif is_inside_tree():
			var h := get_node_or_null("HingeRoot") as Node3D
			if h != null:
				h.rotation_degrees.y = current_angle

@export var max_angle: float = 75.0
@export var min_angle: float = 0.0

var hinge_node: Node3D
var glass_body: StaticBody3D

func _init() -> void:
	var frame := StandardMaterial3D.new()
	frame.albedo_color = Color(0.31, 0.23, 0.17, 1)
	frame_material = frame
	var glass := StandardMaterial3D.new()
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.albedo_color = Color(0.72, 0.85, 0.94, 0.38)
	glass.roughness = 0.12
	glass.metallic = 0.05
	glass_material = glass
	hinge_node = Node3D.new()
	hinge_node.name = "HingeRoot"
	add_child(hinge_node)
	var visuals := Node3D.new()
	visuals.name = "VisualRoot"
	hinge_node.add_child(visuals)
	_part(visuals, "SashGlass", Vector3.ZERO, Vector3.ONE, glass_material)
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.83, 0.69, 0.22, 1)
	brass.metallic = 0.85
	brass.roughness = 0.25
	_part(visuals, "WindowHandle", Vector3.ZERO, Vector3(0.025, 0.12, 0.03), brass)
	glass_body = StaticBody3D.new()
	glass_body.name = "CollisionRoot"
	glass_body.collision_layer = 1
	glass_body.collision_mask = 0
	hinge_node.add_child(glass_body)
	var collision := CollisionShape3D.new()
	collision.name = "WindowSashCollision"
	collision.shape = BoxShape3D.new()
	glass_body.add_child(collision)
	apply_dimensions(sash_width, sash_height, sash_thickness, frame_material, glass_material)

func _ready() -> void:
	apply_dimensions(sash_width, sash_height, sash_thickness, frame_material, glass_material)
	hinge_node.rotation_degrees.y = current_angle
	hinge_node = get_node_or_null("HingeRoot")
	glass_body = get_node_or_null("HingeRoot/CollisionRoot")
	if Engine.is_editor_hint():
		apply_dimensions(sash_width, sash_height, sash_thickness, frame_material, glass_material)
		if hinge_node != null:
			hinge_node.rotation_degrees.y = current_angle

static func create(id: String, width: float, height: float, thickness: float, max_open_angle: float, min_open_angle: float, p_frame_material: Material, p_glass_material: Material = null) -> Node3D:
	if id.is_empty() or not is_finite(width) or not is_finite(height) or not is_finite(thickness) or not is_finite(max_open_angle) or not is_finite(min_open_angle) or width <= 0.0 or height <= 0.0 or thickness <= 0.0:
		push_error("HingedWindow3D " + id + ": invalid-parameters")
		return null
	
	var root: Node3D = load("res://tools/building_construction/BuildingConstruction/Windows/HingedWindow3D.gd").new()
	root.name = "WorldObject3D"
	root.set_meta("world_object_id", id)
	root.set_meta("kind", "openable_window")
	
	root.sash_width = width
	root.sash_height = height
	root.sash_thickness = thickness
	root.max_angle = max_open_angle
	root.min_angle = min_open_angle
	root.frame_material = p_frame_material
	root.glass_material = p_glass_material
	
	root.hinge_node = root.get_node_or_null("HingeRoot")
	root.glass_body = root.get_node_or_null("HingeRoot/CollisionRoot")
	root.apply_dimensions(width, height, thickness, p_frame_material, p_glass_material)
	return root

func apply_dimensions(width: float, height: float, thickness: float, frame_mat: Material, glass_mat: Material) -> void:
	var border := 0.05
	var visuals: Node3D = get_node_or_null("HingeRoot/VisualRoot")
	if visuals:
		_update_part(visuals, "Frame_Bottom", Vector3(width * 0.5, border * 0.5, 0.0), Vector3(width, border, thickness), frame_mat)
		_update_part(visuals, "Frame_Top", Vector3(width * 0.5, height - border * 0.5, 0.0), Vector3(width, border, thickness), frame_mat)
		_update_part(visuals, "Frame_HingeSide", Vector3(border * 0.5, height * 0.5, 0.0), Vector3(border, height - 2.0 * border, thickness), frame_mat)
		_update_part(visuals, "Frame_LockSide", Vector3(width - border * 0.5, height * 0.5, 0.0), Vector3(border, height - 2.0 * border, thickness), frame_mat)
		
		var glass: MeshInstance3D = visuals.get_node_or_null("SashGlass")
		if glass:
			var g_mesh := BoxMesh.new()
			g_mesh.size = Vector3(width - 2.0 * border, height - 2.0 * border, thickness * 0.35)
			glass.mesh = g_mesh
			glass.position = Vector3(width * 0.5, height * 0.5, 0.0)
			if glass_mat != null:
				glass.material_override = glass_mat
				
		var handle: MeshInstance3D = visuals.get_node_or_null("WindowHandle")
		if handle:
			handle.position = Vector3(width - border * 0.6, height * 0.5, thickness * 0.5 + 0.015)
			
	var col: CollisionShape3D = get_node_or_null("HingeRoot/CollisionRoot/WindowSashCollision")
	if col and col.shape is BoxShape3D:
		col.shape.size = Vector3(width, height, thickness)
		col.position = Vector3(width * 0.5, height * 0.5, 0.0)

func _update_part(parent: Node3D, part_name: String, pos: Vector3, sz: Vector3, mat: Material) -> void:
	var m: MeshInstance3D = parent.get_node_or_null(part_name)
	if m == null:
		m = MeshInstance3D.new()
		m.name = part_name
		parent.add_child(m)
	var mesh: BoxMesh = m.mesh as BoxMesh
	if mesh == null:
		mesh = BoxMesh.new()
		m.mesh = mesh
	mesh.size = sz
	m.position = pos
	if mat != null:
		m.material_override = mat

static func _part(parent: Node3D, part_name: String, pos: Vector3, sz: Vector3, mat: Material) -> void:
	var m := MeshInstance3D.new()
	m.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = sz
	m.mesh = mesh
	m.position = pos
	m.material_override = mat
	parent.add_child(m)

func set_angle_checked(angle_deg: float) -> bool:
	var target := clampf(angle_deg, minf(min_angle, max_angle), maxf(min_angle, max_angle))
	current_angle = target
	if hinge_node != null:
		hinge_node.rotation_degrees.y = target
	return true

func is_open() -> bool:
	return absf(current_angle) > 5.0

func open_ratio() -> float:
	var span := absf(max_angle - min_angle)
	if span < 0.001: return 0.0
	return clampf(absf(current_angle - min_angle) / span, 0.0, 1.0)

func can_operate_from_position(world_pos: Vector3, reach_m: float = 1.25) -> bool:
	var local_pos := to_local(world_pos) if is_inside_tree() else (transform.affine_inverse() * world_pos)
	var target := Vector3(sash_width * 0.5, sash_height * 0.5, 0.0)
	return local_pos.distance_to(target) <= reach_m

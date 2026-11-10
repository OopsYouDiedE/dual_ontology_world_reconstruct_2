@tool
extends Node3D
## A hinged leaf with lock, latch and inner/outer interaction slots.
## Only a fully closed, stationary leaf participates in physical collision.
## Local +X spans the leaf; its pivot is the hinge at floor height (Tasks 2.14, 2.15, 2.16).
## Motion is visual/physical only. Core decides whether an action is permitted.
const PhysicsLayers = preload("res://tools/building_construction/BuildingConstruction/Shared/PhysicsLayers.gd")

@export var instance_id: String = ""
@export var portal_id: String = ""
@export var component_kind: String = "door"

@export_range(0.1, 10.0, 0.05) var leaf_width: float = 0.9:
	set(v):
		leaf_width = v
		if Engine.is_editor_hint() and is_inside_tree():
			apply_dimensions(leaf_width, leaf_height, leaf_thickness, door_material)

@export_range(0.1, 10.0, 0.05) var leaf_height: float = 2.1:
	set(v):
		leaf_height = v
		if Engine.is_editor_hint() and is_inside_tree():
			apply_dimensions(leaf_width, leaf_height, leaf_thickness, door_material)

@export_range(0.01, 1.0, 0.005) var leaf_thickness: float = 0.05:
	set(v):
		leaf_thickness = v
		if Engine.is_editor_hint() and is_inside_tree():
			apply_dimensions(leaf_width, leaf_height, leaf_thickness, door_material)

@export var door_material: Material:
	set(v):
		door_material = v
		if Engine.is_editor_hint() and is_inside_tree():
			apply_dimensions(leaf_width, leaf_height, leaf_thickness, door_material)

@export var minimum_angle: float = -90.0
@export var maximum_angle: float = 0.0
@export_range(-180.0, 180.0, 1.0) var current_angle: float = 0.0:
	set(v):
		current_angle = v
		if is_instance_valid(hinge):
			hinge.rotation_degrees.y = current_angle

var last_blocker: Dictionary = {}
var moving := false
var motion_blocked := false
var motion_target := 0.0
var motion_speed_degrees_per_second := 0.0
var blocked_retry_elapsed := 0.0
var hinge: Node3D
var body: StaticBody3D
var box: Shape3D
var safety_box: BoxShape3D

# Lock and latch state from Core (Task 2.15)
var is_locked := false
var locked_side := "both" # "both", "outer" (latched from inside)
var key_id := ""

func _init() -> void:
	var visual_root := Node3D.new()
	visual_root.name = "VisualRoot"
	add_child(visual_root)
	hinge = Node3D.new()
	hinge.name = "Hinge"
	visual_root.add_child(hinge)
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.219608, 0.227451, 0.215686, 1)
	metal.metallic = 0.8
	metal.roughness = 0.3
	_add_mesh("DoorLeafMesh", Vector3(0.9, 2.1, 0.05), null)
	_add_mesh("Handle_Outer", Vector3(0.12, 0.03, 0.05), metal)
	_add_mesh("Handle_Inner", Vector3(0.12, 0.03, 0.05), metal)
	_add_mesh("Latch_Inner", Vector3(0.06, 0.04, 0.03), metal)
	var collision_root := Node3D.new()
	collision_root.name = "CollisionRoot"
	hinge.add_child(collision_root)
	body = StaticBody3D.new()
	body.name = "StaticBody3D"
	body.collision_layer = 1
	body.collision_mask = 0
	collision_root.add_child(body)
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = BoxShape3D.new()
	body.add_child(collision)
	var area := Area3D.new()
	area.name = "InteractionArea"
	area.collision_layer = 16
	area.collision_mask = 2
	add_child(area)
	var area_collision := CollisionShape3D.new()
	area_collision.name = "CollisionShape3D"
	area_collision.shape = BoxShape3D.new()
	area.add_child(area_collision)
	var slots := Node3D.new()
	slots.name = "InteractionSlots"
	add_child(slots)
	for slot_name in ["InnerSlot", "OuterSlot"]:
		var slot := Marker3D.new()
		slot.name = slot_name
		slots.add_child(slot)
	apply_dimensions(leaf_width, leaf_height, leaf_thickness, door_material)

func _add_mesh(part_name: String, size: Vector3, material: Material) -> void:
	var part := MeshInstance3D.new()
	part.name = part_name
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = material
	hinge.add_child(part)

func _ready() -> void:
	apply_dimensions(leaf_width, leaf_height, leaf_thickness, door_material)
	hinge.rotation_degrees.y = current_angle
	hinge = get_node_or_null("VisualRoot/Hinge")
	var body_node = get_node_or_null("VisualRoot/Hinge/CollisionRoot/StaticBody3D")
	if body_node is StaticBody3D:
		body = body_node
		if body.get_child_count() > 0:
			box = (body.get_child(0) as CollisionShape3D).shape
			if box is BoxShape3D:
				safety_box = BoxShape3D.new()
				safety_box.size = (box as BoxShape3D).size + Vector3(0.30, 0.0, 0.30)
	if Engine.is_editor_hint():
		if leaf_width <= 0.0:
			leaf_width = 0.9
			leaf_height = 2.1
			leaf_thickness = 0.05
			maximum_angle = 95.0
		apply_dimensions(leaf_width, leaf_height, leaf_thickness, door_material)
		if hinge != null:
			hinge.rotation_degrees.y = current_angle
		return
	_sync_leaf_collision()

static func create(id: String, width: float, height: float, thickness: float, minimum_degrees: float, maximum_degrees: float, material: Material) -> Node3D:
	if id.is_empty() or not is_finite(width) or not is_finite(height) or not is_finite(thickness) or not is_finite(minimum_degrees) or not is_finite(maximum_degrees) or width <= 0.0 or height <= 0.0 or thickness <= 0.0 or minimum_degrees > 0.0 or maximum_degrees < 0.0 or minimum_degrees >= maximum_degrees:
		push_error("HingedDoor3D " + id + ": invalid-parameters")
		return null
	var root: Node3D = load("res://tools/building_construction/BuildingConstruction/Doors/HingedDoor3D.gd").new()
	root.name = "WorldObject3D"
	root.set_meta("world_object_id", id)
	root.set_meta("kind", "door_panel")
	root.leaf_width = width
	root.leaf_height = height
	root.leaf_thickness = thickness
	root.door_material = material
	root.minimum_angle = minimum_degrees
	root.maximum_angle = maximum_degrees

	root.apply_dimensions(width, height, thickness, material)
	return root

func apply_dimensions(width: float, height: float, thickness: float, material: Material) -> void:
	var visual: MeshInstance3D = get_node_or_null("VisualRoot/Hinge/DoorLeafMesh")
	if visual and visual.mesh is BoxMesh:
		visual.mesh.size = Vector3(width, height, thickness)
		visual.position = Vector3(width / 2.0, height / 2.0, 0.0)
		if material != null:
			visual.material_override = material

	var handle_outer: MeshInstance3D = get_node_or_null("VisualRoot/Hinge/Handle_Outer")
	if handle_outer:
		handle_outer.position = Vector3(width * 0.85, 0.98, thickness / 2.0 + 0.025)

	var handle_inner: MeshInstance3D = get_node_or_null("VisualRoot/Hinge/Handle_Inner")
	if handle_inner:
		handle_inner.position = Vector3(width * 0.85, 0.98, -thickness / 2.0 - 0.025)

	var latch_inner: MeshInstance3D = get_node_or_null("VisualRoot/Hinge/Latch_Inner")
	if latch_inner:
		latch_inner.position = Vector3(width * 0.85, 1.10, -thickness / 2.0 - 0.015)

	var col: CollisionShape3D = get_node_or_null("VisualRoot/Hinge/CollisionRoot/StaticBody3D/CollisionShape3D")
	if col and col.shape is BoxShape3D:
		col.shape.size = Vector3(width, height, thickness)
		col.position = Vector3(width / 2.0, height / 2.0, 0.0)

	var area_col: CollisionShape3D = get_node_or_null("InteractionArea/CollisionShape3D")
	if area_col and area_col.shape is BoxShape3D:
		area_col.shape.size = Vector3(width + 0.6, height, 1.8)
		area_col.position = Vector3(width / 2.0, height / 2.0, 0.0)

	var slots: Node3D = get_node_or_null("InteractionSlots")
	if slots == null:
		slots = Node3D.new()
		slots.name = "InteractionSlots"
		add_child(slots)
	var slot_defs := [
		["Approach", Vector3(width * 0.8, 0, 0.6)],
		["Approach_Inner", Vector3(width * 0.8, 0, -0.6)],
		["Approach_Outer", Vector3(width * 0.8, 0, 0.6)],
		["Stand", Vector3(width * 0.8, 0, 0.6)],
		["FaceTarget", Vector3(width * 0.85, 0.98, 0)],
		["Contact", Vector3(width * 0.85, 0.98, 0)],
		["Contact_Inner", Vector3(width * 0.85, 0.98, -thickness / 2.0 - 0.03)],
		["Contact_Outer", Vector3(width * 0.85, 0.98, thickness / 2.0 + 0.03)]
	]
	for pair in slot_defs:
		var marker: Marker3D = slots.get_node_or_null(pair[0])
		if marker == null:
			marker = Marker3D.new()
			marker.name = pair[0]
			slots.add_child(marker)
		marker.position = pair[1]

	var states: Node3D = get_node_or_null("StateVisuals")
	if states == null:
		states = Node3D.new()
		states.name = "StateVisuals"
		add_child(states)

	var label: Label3D = get_node_or_null("StateVisuals/LabelAnchor")
	if label == null:
		label = Label3D.new()
		label.name = "LabelAnchor"
		states.add_child(label)
	label.position = Vector3(width * 0.85, 1.25, 0)

func is_closed() -> bool:
	return is_equal_approx(current_angle, 0.0)

func resolve_interaction_slot(slot_id: String) -> Marker3D:
	if slot_id.is_empty() or "/" in slot_id or ":" in slot_id: return null
	return get_node_or_null("InteractionSlots/" + slot_id) as Marker3D

## Sets lock state authorized by Core (Task 2.15).
func set_lock_state(locked: bool, side: String = "both", required_key: String = "") -> void:
	is_locked = locked
	locked_side = side
	key_id = required_key

## Evaluates whether operation from world position is allowed under Core lock rules (Task 2.15).
func can_operate_from_position(world_pos: Vector3, has_key: bool = false, held_key_id: String = "") -> Dictionary:
	var local_pos := to_local(world_pos) if is_inside_tree() else (transform.affine_inverse() * world_pos)
	var is_outer_side := local_pos.z >= 0.0
	if is_locked:
		if locked_side == "both" or (locked_side == "outer" and is_outer_side):
			if has_key and (held_key_id == key_id or key_id.is_empty()):
				return {"allowed": true, "operation": "unlock_and_open"}
			return {"allowed": false, "reason": "door_locked_needs_key"}
	if locked_side == "outer" and is_outer_side and is_closed():
		return {"allowed": false, "reason": "latched_from_inside"}
	var op := "close" if not is_closed() else "open"
	return {"allowed": true, "operation": op}

## Angle motion is presentation. Core remains responsible for permission and timing.
func set_angle_checked(degrees: float) -> bool:
	if not is_finite(degrees) or degrees < minimum_angle or degrees > maximum_angle: return false
	if is_inside_tree() and is_instance_valid(body) and is_instance_valid(hinge) and box!=null and not is_equal_approx(degrees,current_angle):
		var shape_node:=body.get_child(0) as CollisionShape3D
		var proposed: Transform3D=(hinge.get_parent() as Node3D).global_transform * Transform3D(Basis(Vector3.UP,deg_to_rad(degrees)),hinge.position) * (body.get_parent() as Node3D).transform * body.transform * shape_node.transform
		var query:=PhysicsShapeQueryParameters3D.new()
		query.shape=safety_box if safety_box!=null else box
		query.transform=proposed
		query.collision_mask=PhysicsLayers.ACTOR
		query.exclude=[body.get_rid()]
		query.margin=0.01
		var hits:=get_world_3d().direct_space_state.intersect_shape(query,16)
		if not hits.is_empty():
			var collider: Object=hits[0].collider
			last_blocker={"name":str(collider.name),"instance_id":collider.get_instance_id(),"angle":degrees,"position":collider.global_position if collider is Node3D else Vector3.ZERO}
			return false
	current_angle = clampf(degrees, minimum_angle, maximum_angle)
	if hinge != null: hinge.rotation.y = deg_to_rad(current_angle)
	last_blocker = {}
	_sync_leaf_collision()
	return true

func _sync_leaf_collision() -> void:
	if not is_instance_valid(body): return
	var blocks := not moving and (absf(current_angle) <= .01 or motion_blocked)
	body.set_meta("door_leaf_collision_enabled", blocks)
	if not body.has_meta("residency_layer"):
		body.set_meta("residency_layer", PhysicsLayers.SOLID)
		body.set_meta("residency_mask", 0)
	var resident := not is_inside_tree() or body.can_process()
	body.collision_layer = int(body.get_meta("residency_layer")) if blocks and resident else 0
	body.collision_mask = 0

## Start motion with the leaf collider disabled; the frame remains solid.
func begin_motion(target_degrees: float, speed_degrees_per_second: float) -> bool:
	if not is_inside_tree() or moving or not is_finite(target_degrees) or not is_finite(speed_degrees_per_second) or speed_degrees_per_second <= 0.0 or target_degrees < minimum_angle or target_degrees > maximum_angle: return false
	motion_target = target_degrees
	motion_speed_degrees_per_second = speed_degrees_per_second
	motion_blocked = false
	blocked_retry_elapsed = 0.0
	moving = not is_equal_approx(current_angle, target_degrees)
	_sync_leaf_collision()
	return true

func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	if not moving and motion_blocked:
		blocked_retry_elapsed+=delta
		if blocked_retry_elapsed<0.25: return
		blocked_retry_elapsed=0.0
		var retry_angle:=move_toward(current_angle,motion_target,motion_speed_degrees_per_second*delta)
		if set_angle_checked(retry_angle):
			motion_blocked=false
			moving=not is_equal_approx(current_angle,motion_target)
			_sync_leaf_collision()
		return
	if not moving: return
	var next_angle := move_toward(current_angle, motion_target, motion_speed_degrees_per_second * delta)
	if not set_angle_checked(next_angle):
		motion_blocked = true
		moving = false
		blocked_retry_elapsed = 0.0
	elif is_equal_approx(current_angle, motion_target):
		moving = false
	_sync_leaf_collision()

## Cancel leaves the leaf at its last checked angle; no completion is emitted.
func cancel_motion() -> void:
	moving = false
	motion_blocked = false
	_sync_leaf_collision()

func get_interaction_slot(slot_id: String) -> Marker3D:
	var slots = get_node_or_null("InteractionSlots")
	if slots != null and slots.has_node(slot_id):
		return slots.get_node(slot_id) as Marker3D
	var dynamic_name = "DynamicSlot_" + slot_id
	var dynamic_slot = get_node_or_null(dynamic_name) as Marker3D
	if dynamic_slot != null:
		return dynamic_slot
	dynamic_slot = Marker3D.new()
	dynamic_slot.name = dynamic_name
	dynamic_slot.position = Vector3(0, 0, 0.6 if slot_id == "Front" else -0.6)
	add_child(dynamic_slot)
	return dynamic_slot



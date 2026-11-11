@tool
extends Node3D
class_name PropEntity3D

## PropEntity3D: Universal root script for all smart prefabs in scenes/prefabs/.
## Manages native AnimationPlayer actions ("open_drawer", "inspect_highlight", etc.),
## ReachTarget3D chibi character standing anchors, SeatPoseModifier3D seating IK offsets,
## dv_slot_id logical slot bindings, and 4-quadrant painterly shader parameters.

signal interaction_requested(entity_id: String, action_id: String, slot_id: String)
signal action_finished(action_name: String)

@export_group("DV & Identification")
@export var instance_id: String = "":
	set(v):
		instance_id = v
		set_meta("instance_id", v)

@export var portal_id: String = "":
	set(v):
		portal_id = v
		set_meta("portal_id", v)

var _component_kind: String = "furniture"
@export var component_kind: String:
	get:
		if _component_kind == "furniture":
			if has_meta("component_kind"):
				return str(get_meta("component_kind"))
			if has_meta("clean_name"):
				return str(get_meta("clean_name"))
			if has_meta("prop_category"):
				return str(get_meta("prop_category"))
			if "architecture" in name.to_lower():
				return "architecture"
			if "shell" in name.to_lower():
				return "complete_shell"
			if "floor" in name.to_lower():
				return "floor"
		return _component_kind
	set(v):
		_component_kind = v
		set_meta("component_kind", v)

@export var dv_slot_id: String = "":
	set(v):
		dv_slot_id = v
		set_meta("dv_slot_id", v)

@export var entity_id: String = "":
	set(v):
		entity_id = v
		set_meta("entity_id", v)

@export_enum("furniture", "doors_windows", "interactive_props", "lighting_decor") var prop_category: String = "furniture":
	set(v):
		prop_category = v
		set_meta("world_category", v)

@export var is_interactive: bool = true
@export_enum("inspect", "sit", "operate", "open", "use", "talk") var default_interaction: String = "inspect"

@export_group("Painterly Shader Parameters")
@export_enum("0: Wood", "1: Cloth/Pigment", "2: Paper", "3: Brass", "4: Polished Wood") var material_kind: int = 0:
	set(v):
		material_kind = v
		_apply_shader_params()

@export var base_color: Color = Color(0.8, 0.75, 0.7, 1.0):
	set(v):
		base_color = v
		_apply_shader_params()

@export_range(0.0, 1.0, 0.01) var surface_roughness: float = 0.62:
	set(v):
		surface_roughness = v
		_apply_shader_params()

@export_range(0.0, 1.0, 0.01) var surface_metallic: float = 0.0:
	set(v):
		surface_metallic = v
		_apply_shader_params()

var _anim_player: AnimationPlayer
var _is_playing: bool = false
var _active_action: String = ""

func _ready() -> void:
	if instance_id.is_empty():
		instance_id = name
	if _component_kind == "furniture":
		if has_meta("prop_category"):
			_component_kind = str(get_meta("prop_category"))
		elif has_meta("component_kind"):
			_component_kind = str(get_meta("component_kind"))
		elif "architecture" in name.to_lower():
			_component_kind = "architecture"
		elif "shell" in name.to_lower():
			_component_kind = "complete_shell"
		elif "floor" in name.to_lower():
			_component_kind = "floor"
		set_meta("component_kind", _component_kind)
	_ensure_static_collision()
	_init_components()
	_apply_shader_params()

func _ensure_static_collision() -> void:
	if find_child("*CollisionObject3D*", true, false) != null: return
	var faces := PackedVector3Array()
	for child in find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := child as MeshInstance3D
		if mesh_inst.mesh != null:
			var rel := _local_transform_to_root(mesh_inst)
			faces.append_array(rel * mesh_inst.mesh.get_faces())
	if faces.is_empty(): return
	var sb := StaticBody3D.new()
	sb.name = "Solid"
	sb.collision_layer = 1
	sb.collision_mask = 0
	add_child(sb)
	var cs := CollisionShape3D.new()
	cs.name = "PropShape"
	var concave := ConcavePolygonShape3D.new()
	concave.set_faces(faces)
	cs.shape = concave
	sb.add_child(cs)

func _local_transform_to_root(descendant: Node3D) -> Transform3D:
	var relative := Transform3D.IDENTITY
	var cursor: Node = descendant
	while cursor != null and cursor != self:
		if cursor is Node3D:
			relative = (cursor as Node3D).transform * relative
		cursor = cursor.get_parent()
	return relative

func get_interaction_slot(slot_id: String) -> Marker3D:
	var slots := get_node_or_null("InteractionSlots")
	if slots != null:
		var target := slots.get_node_or_null(slot_id) as Marker3D
		if target != null: return target
		var reach_target := slots.get_node_or_null("ReachTarget_" + slot_id) as Marker3D
		if reach_target != null: return reach_target
	var existing := get_node_or_null("DynamicSlot_" + slot_id) as Marker3D
	if existing != null: return existing
	var dynamic_slot := Marker3D.new()
	dynamic_slot.name = "DynamicSlot_" + slot_id
	dynamic_slot.position = Vector3(0, 0, 0.6 if slot_id == "Front" else -0.6)
	add_child(dynamic_slot)
	return dynamic_slot

func _init_components() -> void:
	_anim_player = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _anim_player != null and not _anim_player.animation_finished.is_connected(_on_animation_finished):
		_anim_player.animation_finished.connect(_on_animation_finished)

# --- Animation Actions ---
func play_action(action_name: String) -> bool:
	if _anim_player == null:
		_anim_player = get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _anim_player == null or not _anim_player.has_animation(action_name):
		# Default procedural fallback if animation not present in mesh
		if action_name == "inspect_highlight":
			_procedural_highlight()
			return true
		return false
	_is_playing = true
	_active_action = action_name
	_anim_player.play(action_name)
	return true

func stop_action() -> void:
	if _anim_player != null and _anim_player.is_playing():
		_anim_player.stop()
	_is_playing = false
	_active_action = ""

func _on_animation_finished(anim_name: StringName) -> void:
	if _is_playing and str(anim_name) == _active_action:
		_is_playing = false
		action_finished.emit(_active_action)
		_active_action = ""

func _procedural_highlight() -> void:
	var tw := create_tween()
	tw.tween_property(self, "scale", Vector3(1.05, 1.05, 1.05), 0.15)
	tw.tween_property(self, "scale", Vector3.ONE, 0.15)
	tw.finished.connect(func(): action_finished.emit("inspect_highlight"))

# --- Reach & Seating Anchors ---
func get_reach_target(slot_name: String = "ReachTarget_Front") -> Node3D:
	var slots := get_node_or_null("InteractionSlots") as Node3D
	if slots != null:
		var target := slots.get_node_or_null(slot_name) as Node3D
		if target != null:
			return target
		if slots.get_child_count() > 0:
			return slots.get_child(0) as Node3D
	return self

func get_seat_anchor(seat_name: String = "SeatAnchor_Chair") -> Node3D:
	var slots := get_node_or_null("InteractionSlots") as Node3D
	if slots != null:
		var anchor := slots.get_node_or_null(seat_name) as Node3D
		if anchor != null:
			return anchor
	return null

func get_clue_spot(clue_name: String = "ClueSpot_Drawer") -> Marker3D:
	var markers := get_node_or_null("EvidenceMarkers") as Node3D
	if markers != null:
		var spot := markers.get_node_or_null(clue_name) as Marker3D
		if spot != null:
			return spot
		if markers.get_child_count() > 0:
			return markers.get_child(0) as Marker3D
	return null

# --- Interaction API ---
func request_interaction(actor: Node3D, action_id: String = "") -> void:
	if not is_interactive:
		return
	var chosen_action := action_id if not action_id.is_empty() else default_interaction
	interaction_requested.emit(entity_id, chosen_action, dv_slot_id)
	play_action(chosen_action)

# --- Painterly Shader Application ---
func _apply_shader_params() -> void:
	var visual := get_node_or_null("VisualRoot")
	if visual == null:
		return
	_apply_shader_recursive(visual)

func _apply_shader_recursive(node: Node) -> void:
	if node is MeshInstance3D and node.material_override != null:
		var mat: Material = node.material_override
		if mat is ShaderMaterial:
			mat.set_shader_parameter("material_kind", float(material_kind))
			mat.set_shader_parameter("base_color", base_color)
			mat.set_shader_parameter("surface_roughness", surface_roughness)
			mat.set_shader_parameter("surface_metallic", surface_metallic)
	for child in node.get_children():
		_apply_shader_recursive(child)

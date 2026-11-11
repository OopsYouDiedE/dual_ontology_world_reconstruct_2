@tool
extends Node3D
class_name RoomContainer3D

@export var room_id := ""
@export var room_title := ""
@export var floor_name := "2F"
@export var spawn_position := Vector3(1, 0, -1)
@export var auto_sync_on_save := false

func _ready() -> void:
	if room_id.is_empty(): room_id = name
	set_meta("room_id", room_id)
	set_meta("room_title", room_title)
	set_meta("floor_name", floor_name)
	if get_node_or_null("SpawnPoint") == null:
		var spawn := Marker3D.new()
		spawn.name = "SpawnPoint"
		spawn.position = spawn_position
		add_child(spawn)

func get_props() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in find_children("*", "Node3D", true, false):
		if node.has_method("get_interaction_slot"): result.append(node)
	return result

func get_prop_by_slot(identity: String) -> Node3D:
	for prop in get_props():
		if prop.dv_slot_id == identity or prop.name == identity: return prop
	return null

func get_spawn_transform() -> Transform3D:
	var spawn := get_node_or_null("SpawnPoint") as Marker3D
	return spawn.global_transform if spawn != null else global_transform.translated_local(spawn_position)

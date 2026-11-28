@tool
class_name LevelAnchor3D
extends Marker3D
## A named gameplay point inside a LevelStructure3D (spawn, pendulum, cot, gate, entry, exit,
## need object…). Drag it in the Godot editor; the level reads it through LevelStructure3D.
## Anchors with a `role` also become lot objects for room gameplay (entries, exits, windows,
## inspectables, need objects). `extra` keeps any additional lot fields (cell, dir, interior…).

@export var anchor_id: String = "":
	set(v):
		anchor_id = v
		_refresh_label()
## Empty = plain named anchor. Lot roles: entry, exit, focal, inspect, landmark, window, object.
@export var role: String = ""
@export var label: String = ""
@export var guid: int = 0
@export var extra: Dictionary = {}

func _ready() -> void:
	add_to_group(&"level_anchor")
	gizmo_extents = 0.45
	_refresh_label()

func _refresh_label() -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	var tag := get_node_or_null("EditorTag") as Label3D
	if tag == null:
		tag = Label3D.new()
		tag.name = "EditorTag"  # editor-only helper, never owned / saved
		tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tag.no_depth_test = true
		tag.pixel_size = 0.004
		tag.position = Vector3(0, 0.55, 0)
		add_child(tag)
	tag.text = anchor_id if anchor_id != "" else (label if label != "" else role)

## Lot object dictionary in the same shape NativeBlueprint produces.
func lot_object(local_position: Vector3) -> Dictionary:
	var item: Dictionary = extra.duplicate(true)
	item["position"] = Vector2(local_position.x, local_position.z)
	item["role"] = role if role not in ["need", "object"] else ""
	item["label"] = label
	item["guid"] = guid
	if not item.has("yaw"):
		item["yaw"] = rotation.y
	return item

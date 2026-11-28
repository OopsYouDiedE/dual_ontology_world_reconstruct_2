@tool
class_name LevelStation3D
extends Node3D
## A reserved floor footprint (furniture, lamps, jambs): adds a box collider and marks the
## covered cells as not clear for room gameplay. Resize it in the Inspector; the editor shows
## a translucent box so it can be placed by eye.

@export var footprint: Vector2 = Vector2(1, 1):
	set(v):
		footprint = v
		_rebuild()
@export var height: float = 1.0:
	set(v):
		height = v
		_rebuild()
@export var collision: bool = true:
	set(v):
		collision = v
		_rebuild()

func _ready() -> void:
	add_to_group(&"level_station")
	_rebuild()

func bounds_in(local_position: Vector3) -> Rect2:
	return Rect2(Vector2(local_position.x, local_position.z) - footprint * 0.5, footprint)

func _rebuild() -> void:
	if not is_inside_tree():
		return
	for child in get_children():
		if child.name in [&"StationBody", &"EditorBox"]:
			remove_child(child)
			child.queue_free()
	if collision:
		var body := StaticBody3D.new()
		body.name = "StationBody"
		body.position = Vector3.UP * height * 0.5
		var shape := BoxShape3D.new()
		shape.size = Vector3(footprint.x, height, footprint.y)
		var col := CollisionShape3D.new()
		col.shape = shape
		body.add_child(col)
		add_child(body)
	if Engine.is_editor_hint():
		var mesh := BoxMesh.new()
		mesh.size = Vector3(footprint.x, height, footprint.y)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.55, 0.2, 0.22)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = mat
		var box := MeshInstance3D.new()
		box.name = "EditorBox"
		box.mesh = mesh
		box.position = Vector3.UP * height * 0.5
		add_child(box)

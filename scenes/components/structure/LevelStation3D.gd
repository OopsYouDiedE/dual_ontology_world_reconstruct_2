@tool
class_name LevelStation3D
extends "res://scenes/components/structure/StructurePiece3D.gd"
## A reserved floor footprint (furniture, lamps, jambs): adds a box collider and marks the
## covered cells as not clear for room gameplay. Resize it in the Inspector, by its corner
## handles in 3D, or in the plan tab; the editor shows a translucent box.

@export var footprint: Vector2 = Vector2(1, 1):
	set(v):
		footprint = Vector2(maxf(0.05, v.x), maxf(0.05, v.y))
		shape_changed()
@export var height: float = 1.0:
	set(v):
		height = v
		mesh_changed()
@export var collision: bool = true:
	set(v):
		collision = v
		mesh_changed()

func _enter_tree() -> void:
	add_to_group(&"level_station")

func bounds_in(local_position: Vector3) -> Rect2:
	return Rect2(Vector2(local_position.x, local_position.z) - footprint * 0.5, footprint)

func plan_kind() -> String:
	return "station"

func shape_key() -> Array:
	return [footprint]

func plan_outline() -> PackedVector2Array:
	var h := footprint * 0.5
	return PackedVector2Array([to_plan(Vector3(-h.x, 0, -h.y)), to_plan(Vector3(h.x, 0, -h.y)), to_plan(Vector3(h.x, 0, h.y)), to_plan(Vector3(-h.x, 0, h.y))])

## Corner handle: the opposite corner stays put.
func plan_handles() -> Array:
	var h := footprint * 0.5
	return [{"id": &"corner", "position": to_plan(Vector3(h.x, 0, h.y))}]

func set_plan_handle(_id: StringName, plan_position: Vector2) -> void:
	var local := from_plan(plan_position)
	var anchor := Vector2(-footprint.x * 0.5, -footprint.y * 0.5)
	var size := (Vector2(local.x, local.z) - anchor).abs()
	var centre := anchor + size * 0.5
	position += transform.basis * Vector3(centre.x, 0, centre.y)
	footprint = size

func rebuild() -> void:
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

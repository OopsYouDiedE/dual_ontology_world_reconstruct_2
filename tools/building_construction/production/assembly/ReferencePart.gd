@tool
extends Node3D
## ArchBuilder and the reference rooms instantiate the same imported solids.
var model: PackedScene

func _ready() -> void:
	var part := model.instantiate() as Node3D
	add_child(part)
	var meshes := part.find_children("*", "MeshInstance3D", true, false)
	if part is MeshInstance3D: meshes.append(part)
	for mesh: MeshInstance3D in meshes:
		mesh.create_trimesh_collision()

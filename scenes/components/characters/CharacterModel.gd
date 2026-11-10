extends Node3D

func configure(declaration: Dictionary) -> void:
	name = declaration.character_id
	var resource := load(str(declaration.path)) as PackedScene
	if resource == null:
		push_error("无法载入角色模型：" + str(declaration.path))
		return
	var model := resource.instantiate() as Node3D
	if model == null:
		push_error("角色资源必须包含 Node3D：" + str(declaration.path))
		return
	add_child(model)
	model.rotation_degrees.y = float(declaration.yaw_degrees)
	var bounds: Variant = _bounds(model, Transform3D.IDENTITY)
	if bounds == null or bounds.size.y <= 0.0:
		push_error("角色模型缺少有效网格：" + str(declaration.path))
		return
	var factor := float(declaration.height) / float(bounds.size.y)
	model.scale *= factor
	model.position -= Vector3(bounds.get_center().x, bounds.position.y, bounds.get_center().z) * factor
	set_meta("character_id", declaration.character_id)
	set_meta("model_source", declaration.path)
	set_meta("nominal_height", declaration.height)

func _bounds(node: Node, parent_transform: Transform3D) -> Variant:
	var transform := parent_transform
	if node is Node3D:
		transform *= node.transform
	var result: Variant = null
	if node is MeshInstance3D and node.mesh != null:
		result = transform * node.get_aabb()
	for child in node.get_children():
		var child_bounds: Variant = _bounds(child, transform)
		if child_bounds != null:
			result = child_bounds if result == null else result.merge(child_bounds)
	return result

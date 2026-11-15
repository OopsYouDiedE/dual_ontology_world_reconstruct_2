extends RefCounted
## A shadow-only roof blocks exterior sunlight while retaining the cutaway camera view.
static func install(parent: Node3D, center: Vector3, size: Vector2, height := 3.05) -> MeshInstance3D:
	var previous := parent.get_node_or_null("ShadowOnlyCeiling") as MeshInstance3D
	if previous != null: return previous
	var ceiling := MeshInstance3D.new()
	ceiling.name = "ShadowOnlyCeiling"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(size.x + 0.25, 0.15, size.y + 0.25)
	ceiling.mesh = mesh
	ceiling.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	parent.add_child(ceiling)
	ceiling.position = Vector3(center.x, height, center.z)
	return ceiling

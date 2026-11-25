extends RefCounted
## Full-screen quad inside the room viewport: essence warp and red/blue shift.
## Drawn before the ink pass so outlines stay crisp on top; the HUD is never touched.
static func create() -> MeshInstance3D:
	var pass_mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	pass_mesh.mesh = quad
	pass_mesh.extra_cull_margin = 200.0
	pass_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pass_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scenes/components/rendering/post/EssenceShift.gdshader")
	mat.render_priority = 90
	pass_mesh.material_override = mat
	pass_mesh.visible = false
	return pass_mesh

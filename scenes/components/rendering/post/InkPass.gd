extends RefCounted
## Shared native-resolution edge overlay.
static func create() -> MeshInstance3D:
	var ink := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
	ink.mesh = quad
	ink.extra_cull_margin = 200.0
	ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ink.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scenes/components/rendering/post/HallInk.gdshader")
	mat.render_priority = 100
	ink.material_override = mat
	return ink

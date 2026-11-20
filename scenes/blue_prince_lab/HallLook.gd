extends RefCounted
## Shared reference-room exposure, ambient occlusion and native-resolution edge pass.
static func environment(gi: bool) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("8f9ba6")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("c5d2de")
	env.ambient_light_energy = 0.42
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.ssao_enabled = true
	env.ssao_radius = 0.39
	env.ssao_intensity = 1.63
	env.ssao_power = 1.37
	env.sdfgi_enabled = gi
	env.sdfgi_min_cell_size = 0.16
	env.sdfgi_use_occlusion = true
	env.sdfgi_energy = 0.67
	env.sdfgi_bounce_feedback = 0.28
	env.glow_enabled = true
	env.glow_intensity = 0.53
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	env.set_glow_level(1, 0.27)
	env.set_glow_level(2, 0.58)
	env.set_glow_level(3, 0.75)
	env.set_glow_level(4, 0.42)
	env.set_glow_level(5, 0.13)
	env.glow_strength = 1.05
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.05
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.10
	env.adjustment_saturation = 0.95
	return env

static func ink_pass() -> MeshInstance3D:
	var ink := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2,2)
	ink.mesh = quad
	ink.extra_cull_margin = 200.0
	ink.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ink.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://scenes/blue_prince_lab/HallInk.gdshader")
	mat.render_priority = 100
	ink.material_override = mat
	return ink

extends RefCounted
## One Forward+ stage for every first-person space: the Public Hall, the night-watch rooms and
## Expedition-01 share the same grading, contact shading, GI, bloom, aerial fog, ink and eye.

const BASE_FOV := 73.0
const EYE_HEIGHT := 1.57
## Radians per viewport pixel of mouse travel; pitch stops just short of straight up/down.
const LOOK_SENSITIVITY := 0.0022
const PITCH_LIMIT := 1.48

## A fresh Environment per call: rooms may grade fog and GI at runtime without touching each other.
static func environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color("e3e2d9")
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color("c9d0d8")
	e.ambient_light_energy = 0.55
	# Filmic keeps contrast; exposure .78 lets vaults read without washing the walls out.
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 0.78
	e.tonemap_white = 3.5
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.08
	e.adjustment_saturation = 0.80
	# Contact shading + one-bounce GI.
	e.ssao_enabled = true
	e.ssao_radius = 1.3
	e.ssao_intensity = 2.2
	e.ssao_power = 1.6
	e.ssao_detail = 0.6
	e.ssao_light_affect = 0.25
	e.sdfgi_enabled = true
	e.sdfgi_cascades = 3
	e.sdfgi_min_cell_size = 0.3
	e.sdfgi_use_occlusion = true
	e.sdfgi_bounce_feedback = 0.45
	e.sdfgi_energy = 0.9
	e.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	# Soft bloom for lamps and emissive boards; thin aerial fog for depth.
	e.glow_enabled = true
	e.glow_intensity = 0.3
	e.glow_strength = 0.85
	e.glow_bloom = 0.02
	e.glow_hdr_threshold = 1.3
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.fog_enabled = true
	e.fog_light_color = Color("e7e0d0")
	e.fog_density = 0.0028
	e.fog_aerial_perspective = 0.2
	e.fog_sky_affect = 0.0
	return e

## Render parameters that belong to the viewport rather than the Environment.
static func tune_viewport(vp: Viewport) -> void:
	vp.msaa_3d = Viewport.MSAA_4X
	vp.use_debanding = true
	vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	vp.positional_shadow_atlas_size = 4096
	vp.positional_shadow_atlas_quad_0 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16
	vp.positional_shadow_atlas_quad_1 = Viewport.SHADOW_ATLAS_QUADRANT_SUBDIV_16

## Native-resolution HallInk outline at the shared strength.
static func ink() -> MeshInstance3D:
	return preload("res://scenes/components/rendering/post/InkPass.gd").create()

static func is_compatibility() -> bool:
	return RenderingServer.get_current_rendering_method() == &"gl_compatibility"

static func create_compatibility_fill_light() -> DirectionalLight3D:
	var fill := DirectionalLight3D.new()
	fill.name = "CompatibilityFillLight"
	fill.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	fill.light_color = Color("dde6f2")
	fill.light_energy = 0.45
	fill.shadow_enabled = false
	return fill

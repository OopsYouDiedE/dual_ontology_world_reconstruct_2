extends RefCounted
## Render-only A/B cases for the lighting workbench. The story fixture owns its world and camera.
const EDGE := preload("res://tools/testing/RenderRouteEdges.gdshader")
const PALETTE := preload("res://tools/testing/RenderRoutePalette.gdshader")
const CASES := ["reference", "pixel_grid", "sdfgi", "sdfgi_pixel_grid", "sdfgi_stylized", "stylized"]

var index := 0
var _story: Control
var _edges: MeshInstance3D
var _palette: ShaderMaterial
var _original_msaa: int
var _original_scale: float
var _original_mode: int
var _original_taa: bool
var _original_material: Material
var _initial_azimuth: float
var _orbit: Tween

func setup(story: Control) -> void:
	_story = story
	_initial_azimuth = story.az
	var viewport: SubViewport = story.room_vp
	_original_msaa = viewport.msaa_3d
	_original_scale = viewport.scaling_3d_scale
	_original_mode = viewport.scaling_3d_mode
	_original_taa = viewport.use_taa
	_original_material = story.room_container.material
	var quad := QuadMesh.new()
	quad.size = Vector2(2.0, 2.0)
	_edges = MeshInstance3D.new()
	_edges.name = "RenderRouteOutline"
	_edges.mesh = quad
	_edges.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_edges.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	_edges.extra_cull_margin = 200.0
	var material := ShaderMaterial.new()
	material.shader = EDGE
	material.render_priority = -127 # Let transparent nameplates draw over the contours.
	_edges.material_override = material
	story.cam.add_child(_edges)
	_palette = ShaderMaterial.new()
	_palette.shader = PALETTE
	apply_case(0)

func apply_case(value: int) -> void:
	index = posmod(value, CASES.size())
	var pixels := index in [1, 3, 4, 5]
	var stylized := index >= 4
	var environment: Environment = _story.env
	var viewport: SubViewport = _story.room_vp
	environment.sdfgi_enabled = index in [2, 3, 4]
	environment.sdfgi_cascades = 4
	environment.sdfgi_min_cell_size = 0.25
	environment.sdfgi_use_occlusion = true
	environment.sdfgi_read_sky_light = false
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_NEAREST if pixels else _original_mode
	viewport.scaling_3d_scale = 0.5 if pixels else _original_scale
	viewport.msaa_3d = Viewport.MSAA_DISABLED if pixels else _original_msaa
	viewport.use_taa = false if pixels else _original_taa
	_edges.visible = stylized
	_story.room_container.material = _palette if stylized else _original_material

func sweep_camera() -> void:
	if _orbit != null and _orbit.is_running(): _orbit.kill()
	var from: float = _story.az
	_orbit = _story.create_tween()
	_orbit.tween_method(_set_azimuth, from, _initial_azimuth + 0.16, 0.6)
	_orbit.tween_method(_set_azimuth, _initial_azimuth + 0.16, _initial_azimuth, 0.6)

func _set_azimuth(value: float) -> void:
	_story.az = value
	_story._update_camera()

func snapshot() -> Dictionary:
	var viewport: SubViewport = _story.room_vp
	var rd := RenderingServer.get_rendering_device()
	return {"case": CASES[index], "sdfgi": _story.env.sdfgi_enabled, "viewport": [viewport.size.x, viewport.size.y],
		"scale": viewport.scaling_3d_scale, "scaling_mode": viewport.scaling_3d_mode,
		"msaa": viewport.msaa_3d, "taa": viewport.use_taa, "outline": _edges.visible,
		"palette": _story.room_container.material == _palette,
		"driver": RenderingServer.get_current_rendering_driver_name(),
		"adapter": RenderingServer.get_video_adapter_name(),
		"rt_pipeline_feature": rd != null and rd.has_feature(RenderingDevice.SUPPORTS_RAYTRACING_PIPELINE)}

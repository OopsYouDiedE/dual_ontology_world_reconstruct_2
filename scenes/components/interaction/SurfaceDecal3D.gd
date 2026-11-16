extends MeshInstance3D
## A lit, surface-aligned decal supported by the project's Compatibility renderer.
## Parent this layer to its real surface; it never creates a viewport or backdrop.
const TEXTURES := {
	"water": "res://assets/textures/evidence/water_burlap_decal_v1.png",
	"drag": "res://assets/textures/evidence/drag_scuff_decal_v1.png",
	"boots": "res://assets/textures/evidence/wet_bootprint_decal_v1.png",
	"cloth": "res://assets/textures/evidence/purple_gold_residue_decal_v1.png",
}

func install(kind: String, extent: Vector2, wet := false) -> void:
	name = "SurfaceDecal_" + kind
	var plane := PlaneMesh.new()
	plane.size = extent
	mesh = plane
	var surface := StandardMaterial3D.new()
	surface.albedo_texture = load(TEXTURES[kind])
	surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	surface.cull_mode = BaseMaterial3D.CULL_DISABLED
	surface.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	surface.roughness = 0.24 if wet else 0.84
	surface.metallic = 0.1 if kind == "cloth" else 0.0
	material_override = surface
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	set_meta("surface_decal", true)

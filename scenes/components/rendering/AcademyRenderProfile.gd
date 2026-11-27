extends RefCounted
## Unified PBR material presets, regional atmosphere grading, and soft light
## attenuation shared by Expedition-01 Masonry/Lighting and Rogue RoomLighting.

const HALL_FINISH := preload("res://scenes/blue_prince_lab/HallFinish.gdshader")

const MATERIAL_PRESETS := {
	"brass": {"metallic": 0.82, "roughness": 0.30, "specular": 0.65},
	"iron": {"metallic": 0.72, "roughness": 0.44, "specular": 0.55},
	"glass": {"metallic": 0.12, "roughness": 0.08, "specular": 0.78, "alpha": 0.22, "rim": 0.35},
	"door_green": {"metallic": 0.06, "roughness": 0.42, "specular": 0.50, "clearcoat": 0.35, "clearcoat_roughness": 0.30},
	"floor": {"metallic": 0.04, "roughness": 0.64, "specular": 0.46},
	"brick": {"metallic": 0.0, "roughness": 0.88, "specular": 0.28},
	"chalk": {"metallic": 0.0, "roughness": 0.92, "specular": 0.22},
	"trim": {"metallic": 0.02, "roughness": 0.78, "specular": 0.34},
	"joint": {"metallic": 0.0, "roughness": 0.94, "specular": 0.18},
	"felt_dark": {"metallic": 0.0, "roughness": 0.98, "specular": 0.08},
	"book": {"metallic": 0.0, "roughness": 0.86, "specular": 0.24},
	"dark": {"metallic": 0.08, "roughness": 0.84, "specular": 0.22},
	"pit": {"metallic": 0.05, "roughness": 0.90, "specular": 0.20},
	"abyss": {"metallic": 0.0, "roughness": 1.0, "specular": 0.05},
	"test_amber": {"metallic": 0.15, "roughness": 0.36, "specular": 0.60},
	"amber": {"metallic": 0.10, "roughness": 0.35, "emission_energy": 0.82},
	"green": {"metallic": 0.08, "roughness": 0.38, "emission_energy": 0.78},
}

const REGION_ATMOSPHERE := {
	"arcade": {"fog_color": Color("e6ded0"), "fog_density": 0.0028, "ambient": 0.54},
	"niche": {"fog_color": Color("d9d2c4"), "fog_density": 0.0038, "ambient": 0.44},
	"archive": {"fog_color": Color("ddd6c9"), "fog_density": 0.0034, "ambient": 0.48},
	"trial": {"fog_color": Color("dfd4c0"), "fog_density": 0.0038, "ambient": 0.45},
	"release": {"fog_color": Color("cdd3da"), "fog_density": 0.0046, "ambient": 0.40},
	"shaft": {"fog_color": Color("bac9d4"), "fog_density": 0.0048, "ambient": 0.42},
	"underdeck": {"fog_color": Color("9cb0be"), "fog_density": 0.0064, "ambient": 0.30},
	"return": {"fog_color": Color("dfd5c3"), "fog_density": 0.0035, "ambient": 0.48},
}

static func apply_material_preset(m: StandardMaterial3D, key: String) -> void:
	var p: Dictionary = MATERIAL_PRESETS.get(key, {})
	m.metallic = float(p.get("metallic", 0.0))
	m.roughness = float(p.get("roughness", 0.85))
	m.metallic_specular = float(p.get("specular", 0.4))
	if p.has("clearcoat"):
		m.clearcoat_enabled = true
		m.clearcoat = float(p.clearcoat)
		m.clearcoat_roughness = float(p.get("clearcoat_roughness", 0.3))
	if p.has("rim"):
		m.rim_enabled = true
		m.rim = float(p.rim)
		m.rim_tint = 0.35
	if p.has("emission_energy"):
		m.emission_enabled = true
		m.emission = m.albedo_color
		m.emission_energy_multiplier = float(p.emission_energy)
	if key == "glass":
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color.a = float(p.get("alpha", 0.22))
		m.cull_mode = BaseMaterial3D.CULL_DISABLED

static func tune_omni_light(light: OmniLight3D, role: String = "lamp") -> void:
	match role:
		"lamp":
			light.omni_attenuation = 1.45
			light.shadow_bias = 0.04
			light.shadow_normal_bias = 0.45
		"hearth":
			light.omni_attenuation = 1.65
			light.shadow_bias = 0.045
			light.shadow_normal_bias = 0.42
		"window":
			light.omni_attenuation = 1.35
			light.shadow_bias = 0.035
			light.shadow_normal_bias = 0.45
		"lantern":
			light.omni_attenuation = 1.85
			light.shadow_bias = 0.045
			light.shadow_normal_bias = 0.40

static func atmosphere_for(region_id: String, darkroom_mix: float) -> Dictionary:
	var base: Dictionary = REGION_ATMOSPHERE.get(region_id, REGION_ATMOSPHERE.arcade)
	var fog_col: Color = base.fog_color
	var fog_dens: float = float(base.fog_density)
	var amb: float = float(base.ambient)
	if darkroom_mix > 0.001:
		fog_col = fog_col.lerp(Color("1c222d"), darkroom_mix)
		fog_dens = lerpf(fog_dens, 0.0085, darkroom_mix)
		amb = lerpf(amb, 0.09, darkroom_mix)
	return {"fog_color": fog_col, "fog_density": fog_dens, "ambient": amb}

## Shared Blue Prince painterly toon shader builder for Hall and Expedition opaque surfaces.
static func make_hall_finish(
	pigment: Color,
	roughness: float = 0.84,
	grain: float = 0.075,
	is_wood: bool = false,
	is_runner: bool = false,
	vault_fill: float = 0.0,
	pale_wash: float = 0.0,
	emission_gain: float = 0.0
) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = HALL_FINISH
	m.set_shader_parameter("toon_on", true)
	m.set_shader_parameter("toon_strength", 0.86)
	m.set_shader_parameter("pigment", pigment)
	m.set_shader_parameter("surface_roughness", roughness)
	m.set_shader_parameter("grain", grain)
	m.set_shader_parameter("wood", 1.0 if is_wood else 0.0)
	m.set_shader_parameter("runner", 1.0 if is_runner else 0.0)
	m.set_shader_parameter("vault_fill", vault_fill)
	m.set_shader_parameter("pale_wash", pale_wash)
	m.set_shader_parameter("emission_gain", emission_gain)
	return m

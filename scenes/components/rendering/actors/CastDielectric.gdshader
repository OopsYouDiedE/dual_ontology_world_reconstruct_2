shader_type spatial;
render_mode cull_disabled;
#include "res://scenes/components/rendering/surfaces/SoftToonLight.gdshaderinc"

uniform vec4 base_color : source_color = vec4(1.0);
uniform sampler2D base_texture : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.85;
uniform bool double_sided = false;

void fragment() {
	if (!FRONT_FACING && !double_sided) {
		discard;
	}
	ALBEDO = base_color.rgb * texture(base_texture, UV).rgb;
	ROUGHNESS = surface_roughness;
}

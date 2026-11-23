shader_type spatial;
render_mode cull_disabled;
#include "SoftToonLight.gdshaderinc"

uniform vec4 pigment : source_color = vec4(1.0);
uniform float roughness = 0.89;
uniform vec4 emission : source_color = vec4(0.0);

void fragment() {
	ALBEDO = pigment.rgb;
	ROUGHNESS = roughness;
	EMISSION = emission.rgb;
}

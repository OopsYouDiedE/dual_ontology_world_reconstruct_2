shader_type spatial;
render_mode cull_disabled;
#include "SoftToonLight.gdshaderinc"

uniform vec4 pigment : source_color = vec4(1.0);
uniform float roughness = 0.89;
uniform vec4 emission : source_color = vec4(0.0);

uniform float wall_lift = 0.0;
uniform float specular_amount = 0.5;
varying float world_y;
void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
	ALBEDO = pigment.rgb * (1.0 + wall_lift * (clamp(mod(world_y, 3.3) / 3.3, 0.0, 1.0) - 0.5));
	SPECULAR = specular_amount;
	ROUGHNESS = roughness;
	EMISSION = emission.rgb;
}

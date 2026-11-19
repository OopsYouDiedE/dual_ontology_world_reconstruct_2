shader_type spatial;
render_mode specular_disabled;

#include "res://scenes/blue_prince_lab/HallToon.gdshaderinc"

uniform vec4 pigment : source_color = vec4(0.68, 0.72, 0.73, 1.0);

void fragment() {
	vec2 p = vec2(abs(UV.x - 0.5), 1.0 - UV.y);
	float cusp = 0.115 + 2.55 * pow(max(0.0, p.y - 0.46), 2.0);
	float foot = 0.025 + 0.215 * pow(p.x, 0.57);
	float split = min(abs(p.x - 0.016), min(abs(p.x - cusp), abs(p.y - foot)));
	float inset = smoothstep(0.001,0.008,split);
	float brush = 0.019 * sin(UV.x * 177.0 + sin(UV.y * 11.0)) + 0.014 * sin(UV.x * 469.0);
	float field = p.x > cusp ? 0.90 : 1.0;
	ALBEDO = mix(vec3(0.16,0.19,0.20),pigment.rgb * field + brush,inset);
	ROUGHNESS = 0.86;
}

shader_type spatial;
render_mode specular_disabled, cull_disabled;
uniform sampler2D base_map : source_color, filter_linear_mipmap;
uniform sampler2D flat_map : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec3 shadow_tint : source_color = vec3(0.79,0.65,0.62);
uniform bool hard;
uniform bool cutout;
uniform bool face;
uniform float texture_weight = 1.0;
varying vec3 base;
void fragment() {
	vec4 texel = texture(base_map, UV);
	if (cutout && texel.a < 0.5) discard;
	base = tint.rgb * mix(vec3(1.0), texture(flat_map, UV).rgb, texture_weight);
	ALBEDO = base * (hard ? vec3(0.77) : shadow_tint);
	ROUGHNESS = face ? 0.25 : 0.86;
}
void light() {
	float t = dot(normalize(NORMAL),normalize(LIGHT));
	float lit = hard ? (0.87 * step(0.38, t)) : (
		0.16 * max(t, 0.0) + 0.35 * smoothstep(-0.01, 0.33, t)
		+ 0.43 * smoothstep(0.46, 0.83, t));
	DIFFUSE_LIGHT += (hard ? vec3(1.28) : mix(vec3(0.99), vec3(1.32),lit)) * lit * LIGHT_COLOR * ATTENUATION / PI;
}

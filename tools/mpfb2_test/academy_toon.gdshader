shader_type spatial;
render_mode diffuse_lambert, specular_disabled, cull_back;
uniform vec4 pigment : source_color = vec4(0.735, 0.574, 0.49, 1.0);
uniform vec4 shadow_tint : source_color = vec4(0.78, 0.72, 0.78, 1.0);
uniform sampler2D pigment_tex : source_color, filter_linear_mipmap;
uniform bool use_pigment_tex = false;
uniform float band_width : hint_range(0.02, 0.18) = 0.08;
varying vec3 base;
void fragment() {
	base = use_pigment_tex ? texture(pigment_tex, UV).rgb : pigment.rgb;
	ALBEDO = base * mix(shadow_tint.rgb, vec3(1.0), 0.48);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
}
void light() {
	float n = dot(normalize(NORMAL), LIGHT);
	float step_a = smoothstep(0.2 - band_width, 0.2 + band_width, n);
	float step_b = smoothstep(0.67 - band_width, 0.67 + band_width, n);
	float bands = max(n, 0.0) * 0.19 + 0.31 * step_a + 0.37 * step_b;
	vec3 hue = mix(shadow_tint.rgb, vec3(1.16), step_b);
	DIFFUSE_LIGHT += hue * bands * LIGHT_COLOR * ATTENUATION / PI;
}

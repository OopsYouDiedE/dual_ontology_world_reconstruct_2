shader_type spatial;
render_mode unshaded, cull_disabled;

uniform sampler2D glass_tex : source_color, filter_linear_mipmap;
uniform bool has_tex = false;
uniform vec4 fallback_color : source_color = vec4(0.42, 0.58, 0.77, 1.0);
uniform vec4 exterior_tint : source_color = vec4(0.66, 0.80, 0.96, 1.0);
uniform float daylight : hint_range(0.0, 1.0) = 0.25;
uniform float emit_gain = 0.70;

void fragment() {
	vec3 sample_rgb = has_tex ? texture(glass_tex, UV).rgb : fallback_color.rgb;
	float luma = dot(sample_rgb, vec3(0.299, 0.587, 0.114));
	float glass_mask = smoothstep(0.06, 0.42, luma);
	// Opaque self-illuminated stained glass: unaffected by interior lamps, glowing purely from exterior light.
	vec3 boosted = mix(sample_rgb * 0.25, pow(max(sample_rgb, vec3(0.001)), vec3(0.84)) * 1.25, glass_mask);
	float transmit = (0.58 + 1.15 * daylight) * emit_gain;
	ALBEDO = boosted * exterior_tint.rgb * mix(0.24, transmit, glass_mask);
}

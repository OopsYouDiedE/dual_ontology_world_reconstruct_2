shader_type spatial;
render_mode cull_disabled;

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
	// Preserve dark leadwork while saturating translucent jewel-toned glass panels.
	vec3 boosted = mix(sample_rgb, pow(max(sample_rgb, vec3(0.001)), vec3(0.84)) * 1.18, glass_mask);
	float view_facing = mix(0.76, 1.15, abs(dot(normalize(NORMAL), normalize(VIEW))));
	float transmit = (0.46 + 0.92 * daylight) * emit_gain * view_facing;
	ALBEDO = boosted * 0.24;
	ROUGHNESS = 0.35;
	SPECULAR = 0.0;
	EMISSION = boosted * exterior_tint.rgb * transmit * (0.20 + 0.80 * glass_mask);
}

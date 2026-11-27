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
	// Sharp threshold so lead cames stay pitch-dark silhouettes against blazing backlit glass.
	float glass_mask = smoothstep(0.09, 0.32, luma);

	// Preserve deep jewel-like chroma (cobalt, crimson, amber, emerald) while pushing HDR luminance.
	vec3 jewel = pow(max(sample_rgb, vec3(0.002)), vec3(1.08)) * 1.45;
	float jewel_luma = dot(jewel, vec3(0.299, 0.587, 0.114));
	float sat_boost = mix(0.85, 1.65, daylight);
	jewel = max(vec3(0.0), mix(vec3(jewel_luma), jewel, sat_boost));

	// Natural backlit sun-sky gradient: hotter luminous core near upper/center glass, deeper jewel tones at edges.
	float sun_grad = 0.78 + 0.48 * smoothstep(0.0, 1.0, 1.0 - UV.y);
	float core_hot = 1.0 + 0.35 * smoothstep(0.35, 0.95, luma);

	float day_curve = pow(clamp(daylight, 0.0, 1.0), 0.78);
	// Strong HDR transmit in daytime (triggers colored cathedral bloom), near-black at night.
	float transmit = mix(0.035, 3.85, day_curve) * emit_gain * sun_grad * core_hot;
	float lead_level = mix(0.012, 0.022, day_curve);

	vec3 final_color = mix(sample_rgb * lead_level, jewel * transmit, glass_mask);
	ALBEDO = final_color * exterior_tint.rgb;
}

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D glass_tex : source_color, filter_linear_mipmap;
uniform bool has_tex = false;
uniform vec4 fallback_color : source_color = vec4(0.45, 0.68, 0.96, 1.0);
uniform vec4 glow_tint : source_color = vec4(1.0, 0.95, 0.84, 1.0);
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float glow_strength = 0.0;
uniform float is_circular = 0.0;

void fragment() {
	if (glow_strength <= 0.001) {
		discard;
	}
	vec2 centered = UV * 2.0 - 1.0;
	float radial_fade = 1.0 - smoothstep(0.28, 1.0, length(centered));
	float rect_fade = smoothstep(0.0, 0.22, UV.x) * smoothstep(0.0, 0.22, 1.0 - UV.x)
		* smoothstep(0.0, 0.20, UV.y) * smoothstep(0.0, 0.20, 1.0 - UV.y);
	float shape_fade = mix(rect_fade, radial_fade, is_circular);

	vec2 sample_uv = mix(uv_rect.xy, uv_rect.zw, clamp(UV, vec2(0.0), vec2(1.0)));
	vec3 tex_rgb = has_tex ? texture(glass_tex, sample_uv).rgb : fallback_color.rgb;
	// Boost jewel color saturation for authentic colored cathedral halation / floor caustics.
	float luma = dot(tex_rgb, vec3(0.299, 0.587, 0.114));
	vec3 jewel = max(vec3(0.0), mix(vec3(luma), pow(max(tex_rgb, vec3(0.02)), vec3(0.85)), 1.55));
	vec3 col = mix(fallback_color.rgb, jewel, has_tex ? 0.88 : 0.0) * glow_tint.rgb;

	float alpha = shape_fade * glow_strength * (0.55 + 0.45 * smoothstep(0.05, 0.65, luma));
	ALBEDO = col;
	ALPHA = clamp(alpha, 0.0, 0.55);
}

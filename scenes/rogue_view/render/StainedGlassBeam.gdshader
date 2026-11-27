shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform sampler2D stained_tex : source_color, filter_linear_mipmap;
uniform sampler2D depth_tex : hint_depth_texture, repeat_disable, filter_linear;
uniform bool has_tex = false;
uniform vec4 fallback_color : source_color = vec4(0.48, 0.68, 0.90, 1.0);
uniform vec4 beam_tint : source_color = vec4(0.66, 0.82, 0.98, 1.0);
uniform vec4 uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform float beam_intensity = 0.55;
uniform float radial_wrap = 1.0;

float scene_view_depth(vec2 uv, mat4 inv_proj) {
	float raw_z = texture(depth_tex, uv).r;
#if CURRENT_RENDERER == RENDERER_FORWARD_PLUS
	float ndc_z = raw_z;
#else
	float ndc_z = raw_z * 2.0 - 1.0;
#endif
	vec4 view_pos = inv_proj * vec4(uv * 2.0 - 1.0, ndc_z, 1.0);
	return -view_pos.z / view_pos.w;
}

void fragment() {
	// UV.y runs 0.0 (window glass) -> 1.0 (far tip into nave).
	float along = UV.y;
	float entry_fade = smoothstep(0.0, 0.14, along);
	float tail_fade = pow(clamp(1.0 - along, 0.0, 1.0), 1.35);

	// UV.x wraps 0..1: cone uses smooth cylindrical Fresnel only (no seam); ribbons fade edges with sin(pi*x).
	float ribbon_fade = pow(sin(clamp(UV.x, 0.0, 1.0) * 3.14159265), 1.65);
	float edge_profile = mix(ribbon_fade, 1.0, radial_wrap);
	float fresnel_soft = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.50);

	// Sample stained glass pattern across the beam cross-section for colored Tyndall streaks.
	float slice_u = mix(uv_rect.x, uv_rect.z, fract(UV.x));
	float slice_v = mix(uv_rect.y, uv_rect.w, clamp(0.18 + 0.64 * sin(UV.x * 3.14159265), 0.0, 1.0));
	vec3 glass_rgb = has_tex ? texture(stained_tex, vec2(slice_u, slice_v)).rgb : fallback_color.rgb;
	vec3 boosted_glass = pow(max(glass_rgb, vec3(0.03)), vec3(0.75)) * 1.25;
	vec3 ray_color = mix(fallback_color.rgb, boosted_glass, has_tex ? 0.85 : 0.0) * beam_tint.rgb;

	// Distinct Tyndall shaft striations + gentle floating dust motes.
	float streak = 0.72 + 0.28 * sin(UV.x * 31.415926 + along * 2.5 - TIME * 0.25);
	float mote = 0.90 + 0.10 * sin(UV.x * 53.0 - along * 12.0 + TIME * 0.55);

	// Soft-fade before solid floor/walls so shafts never leave sharp intersections.
	float env_depth = scene_view_depth(SCREEN_UV, INV_PROJECTION_MATRIX);
	float frag_depth = -VERTEX.z;
	float depth_soft = smoothstep(0.0, 0.75, max(0.0, env_depth - frag_depth));

	float alpha = entry_fade * tail_fade * edge_profile * fresnel_soft * depth_soft * streak * mote * beam_intensity;
	ALBEDO = ray_color;
	ALPHA = clamp(alpha, 0.0, 0.36);
}

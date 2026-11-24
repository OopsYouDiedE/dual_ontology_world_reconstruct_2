shader_type spatial;
render_mode cull_disabled, blend_mix, depth_prepass_alpha;
uniform float sight : hint_range(0.0, 1.0) = 0.0;
uniform float overload : hint_range(0.0, 1.0) = 0.0;
uniform float settling : hint_range(0.0, 1.0) = 0.0;
uniform float presence : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec2 disturbed = UV + vec2(sin(UV.y*34.0 + TIME*22.0), cos(UV.x*23.0 - TIME*13.0)) * overload * 0.018;
	vec2 grid = abs(fract(disturbed * vec2(8.0, 12.0)) - 0.5);
	float inlay = smoothstep(0.455, 0.492, max(grid.x, grid.y));
	float radial = length((UV - vec2(0.5)) * vec2(1.0, 1.52));
	float rough_wave = sin(UV.y * 57.0 + TIME * 18.0 + sin(UV.x * 29.0)) * 0.5 + 0.5;
	float inward = pow(0.5 + 0.5 * sin(radial * 41.0 + settling * 20.0 + TIME * 9.0), 2.0);
	float tremor = mix(inward, rough_wave, smoothstep(0.69, 1.0, overload));
	float fresnel = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.4);
	float core_glow = smoothstep(0.75, 0.05, radial) * (0.25 + 0.75 * sight);
	vec3 amber = mix(vec3(0.20, 0.095, 0.025), vec3(0.64, 0.36, 0.11), sight);
	vec3 brass_edge = vec3(0.78, 0.58, 0.28) * inlay * (0.35 + 0.45 * sight);
	vec3 ink = mix(amber, vec3(0.58, 0.045, 0.025), overload * (0.65 + tremor * 0.35));
	ALBEDO = ink * (1.0 - 0.42 * inlay) + brass_edge * (1.0 - overload * 0.7);
	EMISSION = ink * (0.15 + sight * 0.42 + core_glow * 0.22 + overload * tremor * 0.28) + mix(vec3(0.85, 0.55, 0.22), vec3(0.95, 0.15, 0.08), overload) * fresnel * (0.18 + 0.32 * max(sight, overload));
	METALLIC = mix(0.14, 0.58, inlay);
	ROUGHNESS = mix(0.42 - sight * 0.12, 0.26, inlay);
	ALPHA = presence;
}

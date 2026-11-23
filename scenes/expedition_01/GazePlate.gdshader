shader_type spatial;
render_mode cull_disabled, blend_mix, depth_prepass_alpha;
uniform float sight : hint_range(0.0, 1.0) = 0.0;
uniform float overload : hint_range(0.0, 1.0) = 0.0;
uniform float presence : hint_range(0.0, 1.0) = 1.0;
void fragment() {
	vec2 grid = abs(fract(UV * vec2(8.0, 12.0)) - 0.5);
	float inlay = smoothstep(0.45, 0.49, max(grid.x, grid.y));
	float tremor = sin(UV.y * 57.0 + TIME * 18.0 + sin(UV.x * 29.0)) * 0.5 + 0.5;
	vec3 amber = mix(vec3(0.21, 0.10, 0.028), vec3(0.57, 0.32, 0.10), sight);
	vec3 ink = mix(amber, vec3(0.53, 0.04, 0.025), overload * (0.65 + tremor * 0.35));
	ALBEDO = ink * (1.0 - 0.46 * inlay);
	EMISSION = ink * (0.14 + sight * 0.38 + overload * tremor * 0.23);
	ROUGHNESS = 0.75;
	ALPHA = presence;
}

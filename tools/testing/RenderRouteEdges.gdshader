shader_type spatial;
render_mode unshaded, fog_disabled, cull_disabled, depth_test_disabled, depth_draw_never, shadows_disabled;

uniform sampler2D scene_depth : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D scene_normal : hint_normal_roughness_texture, repeat_disable, filter_nearest;

uniform float silhouette_strength = 0.44;
uniform float crease_strength = 0.21;

void vertex() {
	// Godot Forward+ uses reverse Z. The quad writes no depth.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float linear_depth(vec2 uv, float depth, mat4 inverse_projection) {
	vec4 view = inverse_projection * vec4(uv * 2.0 - 1.0, depth, 1.0);
	return -view.z / view.w;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 size = vec2(textureSize(scene_depth, 0));
	vec2 texel = 1.0 / size;
	float raw_depth = texture(scene_depth, uv).r;
	if (raw_depth <= 0.0) { discard; }
	float depth = linear_depth(uv, raw_depth, INV_PROJECTION_MATRIX);
	vec3 normal = texture(scene_normal, uv).rgb * 2.0 - 1.0;
	float silhouette = 0.0;
	float crease = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 axis = (i < 2) ? vec2(texel.x, 0.0) : vec2(0.0, texel.y);
		vec2 sample_uv = uv + ((i % 2 == 0) ? axis : -axis);
		float raw_other = texture(scene_depth, sample_uv).r;
		float relative_gap = (linear_depth(sample_uv, raw_other, INV_PROJECTION_MATRIX) - depth) / max(depth, 0.1);
		silhouette = max(silhouette, smoothstep(0.015, 0.035, relative_gap));
		if (raw_other > 0.0 && abs(relative_gap) < 0.015) {
			vec3 other = texture(scene_normal, sample_uv).rgb * 2.0 - 1.0;
			crease = max(crease, smoothstep(0.2, 0.55, 1.0 - dot(normal, other)));
		}
	}
	float edge = max(silhouette_strength * silhouette, crease_strength * crease);
	if (edge < 0.01) { discard; }
	ALBEDO = vec3(0.0);
	ALPHA = edge;
}

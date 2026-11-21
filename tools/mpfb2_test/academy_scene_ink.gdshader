shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, blend_mul;
uniform sampler2D depth_b : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normals_b : hint_normal_roughness_texture, repeat_disable, filter_nearest;
void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
float view_depth(vec2 p, mat4 proj) {
	vec4 v = proj * vec4(p * 2.0 - 1.0, texture(depth_b, p).r, 1.0);
	return -v.z / v.w;
}
void fragment() {
	vec2 p = SCREEN_UV;
	vec2 x = vec2(1.4, 0.0) / VIEWPORT_SIZE;
	vec2 y = vec2(0.0, 1.4) / VIEWPORT_SIZE;
	float d = view_depth(p, INV_PROJECTION_MATRIX);
	float dh = abs(view_depth(p+x, INV_PROJECTION_MATRIX) + view_depth(p-x, INV_PROJECTION_MATRIX) - 2.0*d);
	float dv = abs(view_depth(p+y, INV_PROJECTION_MATRIX) + view_depth(p-y, INV_PROJECTION_MATRIX) - 2.0*d);
	vec3 n = texture(normals_b, p).rgb;
	float turn = max(max(length(n-texture(normals_b,p+x).rgb),length(n-texture(normals_b,p-x).rgb)),
		max(length(n-texture(normals_b,p+y).rgb),length(n-texture(normals_b,p-y).rgb)));
	float edge = max(smoothstep(0.009, 0.036, max(dh,dv)), 0.82*smoothstep(0.17, 0.45, turn));
	ALBEDO = mix(vec3(1.0), vec3(0.17,0.14,0.14), 0.79*edge);
	ALPHA = 1.0;
}

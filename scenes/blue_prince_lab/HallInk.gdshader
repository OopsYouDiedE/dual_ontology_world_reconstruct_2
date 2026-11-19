shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, blend_mul;

uniform sampler2D z_buffer : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normals : hint_normal_roughness_texture, repeat_disable, filter_nearest;
uniform float opacity = 0.89;

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

float view_depth(vec2 uv, mat4 inverse_projection) {
	float z = texture(z_buffer, uv).r;
	vec4 view = inverse_projection * vec4(uv * 2.0 - 1.0, z, 1.0);
	return -view.z / view.w;
}

vec3 face_normal(vec2 uv) {
	return texture(normals, uv).xyz * 2.0 - 1.0;
}

void fragment() {
	vec2 px = 1.15 / VIEWPORT_SIZE;
	vec2 uv = SCREEN_UV;
	vec2 x = vec2(px.x,0.0);
	vec2 y = vec2(0.0,px.y);
	float mid = view_depth(uv, INV_PROJECTION_MATRIX);
	float left = view_depth(uv - x, INV_PROJECTION_MATRIX);
	float right = view_depth(uv + x, INV_PROJECTION_MATRIX);
	float bottom = view_depth(uv - y, INV_PROJECTION_MATRIX);
	float top = view_depth(uv + y, INV_PROJECTION_MATRIX);
	float step_size = max(max(left - mid, right - mid), max(bottom - mid, top - mid));
	float curvature = max(abs(left + right - 2.0 * mid), abs(bottom + top - 2.0 * mid));
	float silhouette = smoothstep(0.003,0.014, max(step_size,0.0)/max(mid,0.1))
		* smoothstep(0.003,0.012,curvature/max(mid,0.1));
	vec3 n = face_normal(uv);
	float jump = max(max(length(n-face_normal(uv-x)),length(n-face_normal(uv+x))),
		max(length(n-face_normal(uv-y)),length(n-face_normal(uv+y))));
	float crease = smoothstep(0.34,0.78,jump) * 0.52;
	float cover = max(silhouette,crease) * opacity * (1.0-smoothstep(21.0,34.0,mid));
	// Multiplication leaves unmarked pixels exactly unchanged and keeps ink dark through tonemapping.
	ALBEDO = mix(vec3(1.0), vec3(0.035,0.047,0.064), cover);
	ALPHA = 1.0;
}

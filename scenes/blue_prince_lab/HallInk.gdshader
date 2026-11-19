shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, blend_mul;

uniform sampler2D z_buffer : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normals : hint_normal_roughness_texture, repeat_disable, filter_linear;
uniform sampler2D opaque_scene : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float opacity = 0.84;

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
	vec2 uv = SCREEN_UV;
	float mid = view_depth(uv, INV_PROJECTION_MATRIX);
	float distance_fade = smoothstep(4.5, 19.0, mid);
	vec2 px = mix(1.12, 0.74, distance_fade) / VIEWPORT_SIZE;
	vec2 x = vec2(px.x,0.0);
	vec2 y = vec2(0.0,px.y);
	float left = view_depth(uv - x, INV_PROJECTION_MATRIX);
	float right = view_depth(uv + x, INV_PROJECTION_MATRIX);
	float bottom = view_depth(uv - y, INV_PROJECTION_MATRIX);
	float top = view_depth(uv + y, INV_PROJECTION_MATRIX);
	float step_size = max(max(left - mid, right - mid), max(bottom - mid, top - mid));
	float curvature = max(abs(left + right - 2.0 * mid), abs(bottom + top - 2.0 * mid));
	float depth_scale = max(mid,0.1);
	float silhouette = smoothstep(mix(0.0036,0.010,distance_fade),
		mix(0.014,0.028,distance_fade), max(step_size,0.0)/depth_scale)
		* smoothstep(mix(0.003,0.008,distance_fade), mix(0.011,0.024,distance_fade),curvature/depth_scale);
	vec3 n = face_normal(uv);
	float jump = max(max(length(n-face_normal(uv-x)),length(n-face_normal(uv+x))),
		max(length(n-face_normal(uv-y)),length(n-face_normal(uv+y))));
	float crease = smoothstep(mix(0.38, 0.67, distance_fade), mix(0.83, 1.03, distance_fade), jump)
		* mix(0.53, 0.24, distance_fade);
	// Test a softly filtered HDR neighborhood so a highlight can wrap a thin metal rib.
	vec3 luminous = textureLod(opaque_scene, uv, 1.75).rgb;
	float luma = dot(luminous, vec3(0.2126, 0.7152, 0.0722));
	float highlight_relief = 1.0 - 0.67 * smoothstep(0.73, 1.55, luma);
	float cover = max(silhouette * mix(1.0, 0.49, distance_fade), crease)
		* opacity * highlight_relief * (1.0-smoothstep(22.0,37.0,mid));
	// Multiplication leaves unmarked pixels exactly unchanged and keeps ink dark through tonemapping.
	ALBEDO = mix(vec3(1.0), vec3(0.035,0.047,0.064), cover);
	ALPHA = 1.0;
}

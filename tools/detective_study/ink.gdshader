shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled, blend_mul;
uniform sampler2D z_buffer : hint_depth_texture, repeat_disable, filter_nearest;
uniform sampler2D normal_buffer : hint_normal_roughness_texture, repeat_disable, filter_nearest;
uniform int ink_mode = 0;
void vertex() { POSITION = vec4(VERTEX.xy, 1.0, 1.0); }
float view_depth(vec2 uv, mat4 inverse_projection) {
	float z = texture(z_buffer, uv).r;
	vec4 view = inverse_projection * vec4(uv * 2.0 - 1.0, z, 1.0);
	return -view.z / view.w;
}
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = (ink_mode == 2 ? 1.7 : 1.05) / VIEWPORT_SIZE;
	vec2 x = vec2(px.x,0.0), y = vec2(0.0,px.y);
	vec4 n = texture(normal_buffer, uv);
	vec4 nl = texture(normal_buffer, uv-x), nr = texture(normal_buffer, uv+x);
	vec4 nu = texture(normal_buffer, uv-y), nd = texture(normal_buffer, uv+y);
	float face = 1.0 - step(0.55,min(min(n.a,nl.a),min(min(nr.a,nu.a),nd.a)));
	float mid = view_depth(uv, INV_PROJECTION_MATRIX);
	float l = view_depth(uv-x, INV_PROJECTION_MATRIX), r = view_depth(uv+x, INV_PROJECTION_MATRIX);
	float u = view_depth(uv-y, INV_PROJECTION_MATRIX), d = view_depth(uv+y, INV_PROJECTION_MATRIX);
	float edge = max(max(l,r),max(u,d))-mid;
	float crease = max(abs(l+r-2.0*mid),abs(u+d-2.0*mid));
	float cut = smoothstep(0.009,0.036,edge)*smoothstep(0.007,0.023,crease);
	float jump = 2.0*max(max(length(n.rgb-nl.rgb),length(n.rgb-nr.rgb)),max(length(n.rgb-nu.rgb),length(n.rgb-nd.rgb)));
	float normal = smoothstep(ink_mode == 2 ? 0.20 : 0.31, ink_mode == 2 ? 0.50 : 0.83,jump);
	float coverage = max(cut * (ink_mode == 2 ? 0.99 : 0.75), normal * (ink_mode == 2 ? 0.90 : 0.68 - 0.53*face));
	ALBEDO = mix(vec3(1.0), vec3(0.075,0.055,0.052), coverage);
	ALPHA = 1.0;
}

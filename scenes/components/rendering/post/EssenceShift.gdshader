shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled, depth_draw_never, fog_disabled;
// Essence instability: a slow refractive warp plus a red/blue shift that swings between
// approach (blue) and recession (red), as if the room were moving relative to the eye.
uniform sampler2D opaque_scene : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform float instability : hint_range(0, 1) = 0.0;
uniform vec2 focus = vec2(0.5, 0.5);

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - focus;
	float r = length(d);
	float k = instability;
	float band = sin(uv.y * 18.0 + TIME * 1.7) * sin(uv.y * 7.0 - TIME * 0.9);
	vec2 warp = vec2(band * 0.0035, sin(uv.x * 11.0 + TIME * 1.3) * 0.002) * k;
	warp += d / max(r, 0.0001) * sin(r * 26.0 - TIME * 2.4) * 0.0025 * k * smoothstep(0.05, 0.45, r);
	float swing = sin(TIME * 0.8 + sin(TIME * 0.23) * 1.7);
	vec2 split = d * (0.006 + 0.008 * abs(swing)) * k;
	vec3 col = vec3(
		texture(opaque_scene, uv + warp + split * swing).r,
		texture(opaque_scene, uv + warp).g,
		texture(opaque_scene, uv + warp - split * swing).b);
	float side = clamp(d.x * 2.2, -1.0, 1.0) * swing;
	col *= mix(vec3(1.0), vec3(1.12, 0.90, 0.86), max(side, 0.0) * 0.38 * k);
	col *= mix(vec3(1.0), vec3(0.84, 0.95, 1.16), max(-side, 0.0) * 0.38 * k);
	ALBEDO = col;
}

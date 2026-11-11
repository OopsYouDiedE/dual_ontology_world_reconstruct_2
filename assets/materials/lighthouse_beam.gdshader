shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

// Additive light shaft. UV.y runs along the cone, 0 at the lamp end.
uniform vec4 beam_color : source_color = vec4(1.0, 0.88, 0.66, 1.0);
uniform float strength = 0.22;

void fragment() {
	float along = UV.y;
	float fade = smoothstep(0.0, 0.06, along) * (1.0 - smoothstep(0.35, 1.0, along));
	float core = pow(clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 1.4);
	ALBEDO = beam_color.rgb * strength * fade * core;
}

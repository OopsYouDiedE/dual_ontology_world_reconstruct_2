shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;
uniform vec4 ink : source_color = vec4(0.14, 0.096, 0.101, 1.0);
uniform float width_m = 0.0017;
uniform bool use_vertex_alpha = false;
void vertex() {
	float mask = use_vertex_alpha ? COLOR.a : 1.0;
	VERTEX += normalize(NORMAL) * width_m * mask;
}
void fragment() {
	ALBEDO = ink.rgb;
}

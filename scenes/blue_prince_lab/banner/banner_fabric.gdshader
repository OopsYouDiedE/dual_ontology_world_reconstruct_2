shader_type spatial;
render_mode cull_disabled;

uniform vec4 cloth_color : source_color = vec4(0.21, 0.29, 0.41, 1.0);
uniform vec4 trim_color : source_color = vec4(0.76, 0.63, 0.42, 1.0);

float ink(float d) {
	float aa = max(fwidth(d), 0.001);
	return 1.0 - smoothstep(-aa, aa, d);
}

void fragment() {
	vec2 p = UV;
	vec2 q = vec2((p.x - 0.5) * 1.25, p.y - 0.45);
	float edge = min(min(p.x, 1.0 - p.x), min(p.y, 1.0 - p.y));
	float braid = ink(abs(edge - 0.033) - 0.008) + 0.55 * ink(abs(edge - 0.056) - 0.002);
	float lozenge = ink(abs(abs(q.x) + abs(q.y) * 0.79 - 0.137) - 0.004);
	// Original estate badge: a stepped gate with a tapered arch and three merlons.
	float gate = ink(max(abs(q.x) - 0.058, max(q.y - 0.055, -q.y - 0.042)));
	float merlons = ink(max(min(abs(q.x), abs(abs(q.x) - 0.046)) - 0.012,
		max(-q.y - 0.063, q.y + 0.042))) * ink(abs(q.x) - 0.058);
	float arch = ink(max(q.y - 0.056, max(abs(q.x) - 0.020, length(vec2(q.x, min(q.y - 0.020, 0.0))) - 0.020)));
	float badge = clamp(lozenge + max(gate, merlons) * (1.0 - arch), 0.0, 1.0);
	float weave = sin(p.x * 1050.0) * sin(p.y * 1540.0);
	float weave_gate = 1.0 - smoothstep(0.18, 0.52, max(fwidth(p.x) * 167.0, fwidth(p.y) * 245.0));
	float dye = 0.92 + 0.08 * sin(p.x * 8.0 + p.y * 3.0) + weave * weave_gate * 0.035;
	vec3 ground = cloth_color.rgb * dye * mix(0.70, 1.0, smoothstep(0.0, 0.015, edge));
	ALBEDO = mix(ground, trim_color.rgb * dye, clamp(braid + badge, 0.0, 1.0));
	ROUGHNESS = 0.91;
	SPECULAR = 0.26;
}

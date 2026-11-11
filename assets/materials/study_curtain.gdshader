shader_type spatial;
render_mode cull_disabled, diffuse_burley;

// Velvet curtain on a FACE_Z plane: vertical folds plus a slow draught from the window.
uniform vec4 velvet : source_color = vec4(0.32, 0.05, 0.06, 1.0);
uniform float sway = 1.0;
uniform float fold_frequency = 46.0;
uniform float fold_depth = 0.022;
varying float fold;

void vertex() {
	float hang = UV.y;
	fold = sin(VERTEX.x * fold_frequency);
	VERTEX.z += fold * fold_depth + sin(TIME * 0.55 + VERTEX.x * 3.0 + hang * 2.2) * 0.014 * hang * sway;
	VERTEX.x += sin(TIME * 0.41 + hang * 3.1) * 0.010 * hang * sway;
	NORMAL = normalize(vec3(-cos(VERTEX.x * fold_frequency) * fold_frequency * fold_depth, 0.0, 1.0));
}

void fragment() {
	float shade = 0.72 + 0.28 * (fold * 0.5 + 0.5);
	ALBEDO = velvet.rgb * shade;
	ROUGHNESS = 0.92;
	float rim = pow(1.0 - clamp(abs(dot(NORMAL, VIEW)), 0.0, 1.0), 2.0);
	EMISSION = velvet.rgb * rim * 0.18;
}

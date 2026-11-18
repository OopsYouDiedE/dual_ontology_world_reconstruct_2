shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 pigment : source_color = vec4(0.45, 0.28, 0.15, 1.0);
uniform float roughness_value = 0.76;
uniform float sheen = 0.0;
uniform float paint_weight : hint_range(0.0, 1.0) = 0.3;
uniform int finish_kind = 0; // 0 waxed wood, 1 stone, 2 woven fabric
uniform bool fixed_surface = false;

varying vec3 brush_point;
varying vec3 brush_normal;

float hash_cell(vec2 cell) {
	vec3 q = fract(vec3(cell.xyx) * 0.1031);
	q += dot(q, q.yzx + 33.33);
	return fract((q.x + q.y) * q.z);
}

float wash(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), f.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + 1.0), f.x), f.y);
}

void vertex() {
	brush_point = fixed_surface ? (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz : VERTEX;
	brush_normal = fixed_surface ? MODEL_NORMAL_MATRIX * NORMAL : NORMAL;
}

void fragment() {
	// Architecture brushwork is continuous across mesh seams. Furniture keeps its
	// grain attached to the model when a door or drawer rotates.
	vec3 axis = abs(normalize(brush_normal));
	vec2 p = axis.y > max(axis.x, axis.z) ? brush_point.xz
		: axis.x > axis.z ? brush_point.zy : brush_point.xy;
	float broad = wash(p * 2.0);
	float line = 0.0;
	float dab = 0.0;
	if (finish_kind == 0) {
		vec2 grain_uv = vec2(p.x * 2.4, p.y * 44.0 + 2.8 * broad);
		float band = wash(grain_uv);
		float distance_fade = 1.0 - smoothstep(0.4, 1.3, length(fwidth(grain_uv)));
		line = (band - 0.5) * distance_fade;
		dab = wash(p * vec2(5.0, 8.0)) - 0.5;
	} else if (finish_kind == 1) {
		// Layered wet-on-dry stone wash, deliberately low-contrast near traces.
		float cloud = wash((p + vec2(broad, -broad) * 0.09) * 7.0);
		dab = smoothstep(0.20, 0.80, cloud) - 0.5;
		line = 0.36 * (wash(p * 35.0) - 0.5) * (1.0 - smoothstep(0.35, 1.0, length(fwidth(p * 35.0))));
	} else {
		vec2 threads = p * vec2(75.0, 66.0);
		float weave = sin(threads.x * TAU) * sin(threads.y * TAU);
		line = 0.37 * weave * (1.0 - smoothstep(0.18, 0.64, length(fwidth(threads))));
		dab = wash(p * vec2(8.0, 13.0)) - 0.5;
	}
	float stroke = (broad - 0.5) * 0.75 + line * 0.95 + dab * 0.55;
	vec3 undertone = finish_kind == 1 ? vec3(1.055, 0.98, 0.915) : vec3(1.11, 1.015, 0.88);
	vec3 overpaint = mix(pigment.rgb, pigment.rgb * undertone, clamp(broad + dab * 0.35, 0.0, 1.0));
	ALBEDO = overpaint * (1.0 + stroke * paint_weight);
	ROUGHNESS = clamp(roughness_value - paint_weight * (dab * 0.15 + line * 0.08), 0.28, 0.98);
	METALLIC = sheen;
}

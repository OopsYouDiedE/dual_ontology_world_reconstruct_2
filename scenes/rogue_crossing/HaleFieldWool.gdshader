shader_type spatial;
#include "res://scenes/components/rendering/surfaces/SoftToonLight.gdshaderinc"

// Pattern placement follows the existing skin in every pose, independent of light and camera.
varying vec3 pattern;
varying float jacket;
void vertex() {
	pattern = vec3(UV2, COLOR.r * .65 - .3);
	jacket = COLOR.g;
}

float box_sdf(vec2 p, vec2 half_size, float radius) {
	vec2 d = abs(p) - half_size + radius;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - radius;
}
float edge(float d) {
	return 1.0 - smoothstep(-.0015, .0015, d);
}

void fragment() {
	float x = abs(pattern.x);
	float y = pattern.y;
	float z = pattern.z;
	float front = smoothstep(.069, .105, z);

	vec3 wool = vec3(.40, .30, .17);
	vec3 color = wool;
	float relief = 0.0;
	float metal_mask = 0.0;
	// Four applied pockets: squared flaps over rounded patch bodies.
	for (int i = 0; i < 2; i++) {
		float upper = float(i);
		vec2 p = vec2(x - mix(.112, .101, upper), y - mix(.927, 1.218, upper));
		float d = box_sdf(p, vec2(mix(.051, .041, upper), .062), .014);
		float patch = edge(d) * front;
		float seam = (edge(d + .001) - edge(d + .004)) * front;
		float flap = edge(box_sdf(p - vec2(0., .042), vec2(mix(.053, .043, upper), .019), .006)) * front;
		color += wool * (.09 * patch + .16 * flap - .44 * seam);
		relief += .003 * patch + .004 * flap;
		float stud = edge(length(p - vec2(0., .035)) - .0055) * front;
		color = mix(color, vec3(.62, .45, .20), stud);
		metal_mask = max(metal_mask, stud);
	}
	// Norfolk-style waist strap, lapel notch, and box-pleat stitching.
	float belt = edge(abs(y - 1.06) - .022) * (1.0 - smoothstep(.176, .198, x));
	color = mix(color, wool * .64, belt);
	float pleat = edge(abs(x - .076) - .010) * smoothstep(.85, .90, y) * (1.0 - smoothstep(1.38, 1.43, y)) * (1.0 - smoothstep(-.084, -.064, z));
	float fore_fold = edge(abs(x - .132) - .009) * front * smoothstep(1.085, 1.13, y) * (1.0 - smoothstep(1.385, 1.435, y));
	pleat = max(pleat, fore_fold);
	color += wool * .19 * pleat * (1.0 - belt);
	relief += .004 * belt + .003 * pleat;
	// Crisp 1900s lapel edge & cream shirt collar
	float lapel = edge(abs(x - .052 - (1.40 - y) * .18) - .005) * smoothstep(1.24, 1.40, y) * front;
	color *= 1.0 - .20 * lapel;
	relief += .0035 * lapel;
	float throat = (1.0 - smoothstep(.027, .047, x)) * smoothstep(1.325, 1.425, y) * front;
	color = mix(color, vec3(.66, .62, .52), throat);
	float placket = edge(x - .009) * front * smoothstep(.86, .91, y) * (1.0 - smoothstep(1.27, 1.33, y));
	color *= 1.0 - .22 * placket * (1.0 - belt);
	float button_y = mod(y - .898 + .042, .084) - .042;
	float buttons = edge(length(vec2(pattern.x - .003, button_y)) - .008) * placket * (1.0 - belt);
	color = mix(color, vec3(.52, .36, .16), buttons);
	metal_mask = max(metal_mask, buttons * .7);
	float buckle = edge(box_sdf(vec2(pattern.x, y - 1.06), vec2(.027, .023), .005));
	float opening = edge(box_sdf(vec2(pattern.x, y - 1.06), vec2(.022, .016), .003));
	float brass_buckle = clamp((buckle - opening) * front, 0.0, 1.0);
	color = mix(color, vec3(.72, .54, .24), brass_buckle);
	metal_mask = max(metal_mask, brass_buckle);
	relief += .005 * brass_buckle;
	// Dual-frequency herringbone twill weave
	float chevron = sign(sin(pattern.x * 160.0));
	float twill = sin((y * .65 + (pattern.x * chevron + z) * .76) * 2180.0);
	color *= 1.0 + .042 * twill * (1.0 - smoothstep(.001, .004, fwidth(y)));
	// Derivative bump for the sewn layers, in view space.
	vec3 dx = dFdx(VERTEX);
	vec3 dy = dFdy(VERTEX);
	vec3 tx = cross(dy, NORMAL);
	vec3 ty = cross(NORMAL, dx);
	float det = dot(dx, tx);
	NORMAL = normalize(abs(det) * NORMAL - sign(det) * (dFdx(relief) * tx + dFdy(relief) * ty));
	// Soft wool Fresnel rim & mid-tone charcoal-taupe trousers (avoiding pure black outline loss).
	float rim = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), 3.0);
	vec3 trousers = vec3(.195, .188, .168);
	vec3 base_albedo = mix(trousers, color, jacket);
	ALBEDO = base_albedo + vec3(.06, .05, .04) * rim * (1.0 - metal_mask);
	METALLIC = metal_mask * .82 * jacket;
	ROUGHNESS = mix(.88, .28, metal_mask * jacket);
}

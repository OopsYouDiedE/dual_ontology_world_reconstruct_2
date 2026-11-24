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

	vec3 wool = vec3(.37, .275, .15);
	vec3 color = wool;
	float relief = 0.0;
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
		float stud = edge(length(p - vec2(0., .035)) - .005) * front;
		color = mix(color, vec3(.135, .088, .033), stud);
	}
	// Norfolk-style waist strap and box-pleat stitching on the back.

	float belt = edge(abs(y - 1.06) - .022) * (1.0 - smoothstep(.176, .198, x));
	color = mix(color, wool * .64, belt);
	float pleat = edge(abs(x - .076) - .010) * smoothstep(.85, .90, y) * (1.0 - smoothstep(1.38, 1.43, y)) * (1.0 - smoothstep(-.084, -.064, z));
	float fore_fold = edge(abs(x - .132) - .009) * front * smoothstep(1.085, 1.13, y) * (1.0 - smoothstep(1.385, 1.435, y));
	pleat = max(pleat, fore_fold);
	color += wool * .19 * pleat * (1.0 - belt);
	relief += .004 * belt + .003 * pleat;
	float throat = (1.0 - smoothstep(.027, .047, x)) * smoothstep(1.325, 1.425, y) * front;
	color = mix(color, vec3(.58, .54, .44), throat);
	float placket = edge(x - .009) * front * smoothstep(.86, .91, y) * (1.0 - smoothstep(1.27, 1.33, y));
	color *= 1.0 - .22 * placket * (1.0 - belt);
	float button_y = mod(y - .898 + .042, .084) - .042;
	float buttons = edge(length(vec2(pattern.x - .003, button_y)) - .008) * placket * (1.0 - belt);
	color = mix(color, vec3(.30, .19, .075), buttons);
	float buckle = edge(box_sdf(vec2(pattern.x, y - 1.06), vec2(.027, .023), .005));
	float opening = edge(box_sdf(vec2(pattern.x, y - 1.06), vec2(.022, .016), .003));
	color = mix(color, vec3(.40, .25, .095), (buckle - opening) * front);
	relief += .005 * buckle * front;
	float twill = sin((y * .65 + (pattern.x + z) * .76) * 2180.0);
	color *= 1.0 + .035 * twill * (1.0 - smoothstep(.001, .004, fwidth(y)));
	// Derivative bump for the sewn layers, in view space.
	vec3 dx = dFdx(VERTEX);
	vec3 dy = dFdy(VERTEX);
	vec3 tx = cross(dy, NORMAL);
	vec3 ty = cross(NORMAL, dx);
	float det = dot(dx, tx);
	NORMAL = normalize(abs(det) * NORMAL - sign(det) * (dFdx(relief) * tx + dFdy(relief) * ty));
	ALBEDO = mix(vec3(.085, .093, .075), color, jacket);
	ROUGHNESS = .90;
}

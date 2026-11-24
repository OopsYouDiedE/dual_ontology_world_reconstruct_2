shader_type spatial;
#include "res://scenes/components/rendering/surfaces/SoftToonLight.gdshaderinc"

void fragment() {
	vec2 p = UV2;
	float depth = clamp((.144 - p.y) / .145, 0.0, 1.0);
	float part = p.x + .031 + .23 * (.110 - p.y) + .029 * depth * depth;
	float crown = smoothstep(-.014, .055, p.y);
	float seam = exp(-pow(part / .0038, 2.0)) * crown;
	float sweep = part / (.014 + depth * .009);
	float grain = sin(6.283 * (sweep + sign(part) * depth * .9));
	float comb = (1.0 - smoothstep(.23, .65, fwidth(sweep))) * crown;
	vec3 brown = vec3(.067, .043, .028);
	brown *= 1.0 + .25 * grain * comb + .16 * smoothstep(-.009, .010, part) * crown;
	ALBEDO = mix(brown, vec3(.25, .154, .091), seam * .81);
	ROUGHNESS = .62;
}

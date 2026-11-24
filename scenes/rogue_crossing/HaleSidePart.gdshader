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
	float fine_strand = sin(18.85 * (sweep + sign(part) * depth * 1.1));
	float comb = (1.0 - smoothstep(.23, .65, fwidth(sweep))) * crown;
	// Mid-dark chestnut base so HallInk outlines remain crisp (never pure black).
	vec3 brown = vec3(.175, .112, .068);
	brown *= 1.0 + .22 * grain * comb + .08 * fine_strand * comb + .16 * smoothstep(-.009, .010, part) * crown;
	// Stylized anisotropic hair sheen band across the crown sweep.
	float ndv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
	float sheen_band = exp(-pow((depth - 0.38 - 0.08 * grain) / 0.14, 2.0)) * crown * (0.45 + 0.55 * ndv);
	brown += vec3(.22, .15, .09) * sheen_band * 0.42;
	ALBEDO = mix(brown, vec3(.34, .22, .135), seam * .78);
	ROUGHNESS = mix(.54, .34, sheen_band);
	SPECULAR = .55;
}

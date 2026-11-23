#ifndef EXPEDITION_SOFT_TOON_LIGHT
#define EXPEDITION_SOFT_TOON_LIGHT

uniform bool toon_on = true;
uniform float toon_strength = 0.86;
uniform bool clearline = false;
uniform bool two_tone = false;
uniform float stone_sheen = 0.0;

float soft_toon_response(float lambert) {
	if (toon_on && clearline) {
		return 0.46 * smoothstep(0.27, 0.30, lambert) + 0.54 * smoothstep(0.68, 0.71, lambert);
	}
	// Quantize surface response, not distance or shadow. Lantern falloff stays continuous.
	float bands = 0.27 * smoothstep(0.17, 0.25, lambert)
		+ 0.31 * smoothstep(0.42, 0.53, lambert)
		+ 0.40 * smoothstep(0.71, 0.81, lambert);
	if (two_tone) {
		bands = 0.14 * lambert + 0.72 * smoothstep(0.45, 0.51, lambert);
	}
	return toon_on ? mix(lambert, bands, toon_strength) : lambert;
}

#ifndef EXPEDITION_CUSTOM_LIGHT
void light() {
	float lambert = max(dot(NORMAL, LIGHT), 0.0);
	float response = soft_toon_response(lambert);
	DIFFUSE_LIGHT += response * ATTENUATION * LIGHT_COLOR / PI;
	if (stone_sheen > 0.0) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float lobe = pow(max(dot(NORMAL, half_vec), 0.0), 13.0);
		SPECULAR_LIGHT += stone_sheen * lobe * ATTENUATION * LIGHT_COLOR * lambert;
	}
}

#endif
#endif

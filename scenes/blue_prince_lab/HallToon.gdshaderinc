uniform bool toon_on = true;
uniform float toon_strength = 0.86;
uniform bool two_tone = false;
uniform float stone_sheen = 0.0;

void light() {
	float lambert = max(dot(NORMAL, LIGHT), 0.0);
	// Quantize surface response, not distance or shadow. Lantern falloff stays continuous.
	float bands = 0.27 * smoothstep(0.17, 0.25, lambert)
		+ 0.31 * smoothstep(0.42, 0.53, lambert)
		+ 0.40 * smoothstep(0.71, 0.81, lambert);
	if (two_tone) {
		bands = 0.14 * lambert + 0.72 * smoothstep(0.45, 0.51, lambert);
	}
	float response = toon_on ? mix(lambert, bands, toon_strength) : lambert;
	DIFFUSE_LIGHT += response * ATTENUATION * LIGHT_COLOR / PI;
	if (stone_sheen > 0.0) {
		vec3 half_vec = normalize(LIGHT + VIEW);
		float lobe = pow(max(dot(NORMAL, half_vec), 0.0), 13.0);
		SPECULAR_LIGHT += stone_sheen * lobe * ATTENUATION * LIGHT_COLOR * lambert;
	}
}

uniform bool toon_on = true;

void light() {
	float lambert = max(dot(NORMAL, LIGHT), 0.0);
	// Quantize surface response, not distance or shadow. Lantern falloff stays continuous.
	float bands = 0.27 * smoothstep(0.17, 0.25, lambert)
		+ 0.31 * smoothstep(0.42, 0.53, lambert)
		+ 0.40 * smoothstep(0.71, 0.81, lambert);
	float response = toon_on ? bands : lambert;
	DIFFUSE_LIGHT += response * ATTENUATION * LIGHT_COLOR / PI;
}

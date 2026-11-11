shader_type spatial;
render_mode unshaded, cull_disabled, fog_disabled;

// UV.y = 0 is the upper edge of the distant sky quad.
uniform vec2 volcano_uv = vec2(0.42, 0.585);
uniform float horizon_v = 0.66;
uniform float flash = 0.0;
uniform vec4 zenith : source_color = vec4(0.008, 0.012, 0.035, 1.0);
uniform vec4 middle : source_color = vec4(0.016, 0.027, 0.055, 1.0);
uniform vec4 horizon : source_color = vec4(0.035, 0.049, 0.072, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amplitude = 0.5;
	for (int octave = 0; octave < 5; octave++) {
		value += noise(p) * amplitude;
		p = p * 2.03 + vec2(17.0, 9.0);
		amplitude *= 0.5;
	}
	return value;
}

void fragment() {
	vec2 uv = UV;
	float height = clamp((horizon_v - uv.y) / horizon_v, 0.0, 1.0);
	vec3 color = mix(horizon.rgb, middle.rgb, smoothstep(0.0, 0.12, height));
	color = mix(color, zenith.rgb, smoothstep(0.12, 0.58, height));

	// Separate the narrow bright crater from a dim, nearby ash halo.
	vec2 delta = uv - volcano_uv;
	float crater = exp(-dot(delta * vec2(9.0, 5.0), delta * vec2(9.0, 5.0)) * 4.0);
	float haze = exp(-dot(delta * vec2(4.5, 5.5), delta * vec2(4.5, 5.5)) * 2.2);
	float pulse = 0.86 + 0.10 * sin(TIME * 0.83) + 0.04 * sin(TIME * 3.7);
	color += vec3(0.85, 0.22, 0.055) * crater * 0.85 * pulse;
	color += vec3(0.27, 0.075, 0.025) * haze * 0.36;

	float cloud_noise = fbm(uv * vec2(3.2, 7.0) + vec2(TIME * 0.0045, TIME * 0.0012));
	float cloud = smoothstep(0.46, 0.80, cloud_noise) * smoothstep(0.02, 0.22, height) * (1.0 - smoothstep(0.75, 1.0, height));
	vec3 ash = mix(vec3(0.026, 0.032, 0.052), vec3(0.38, 0.13, 0.065), clamp(haze * 1.4, 0.0, 1.0));
	color = mix(color, ash, cloud * 0.7);

	vec2 star_uv = uv * vec2(460.0, 190.0);
	float star_seed = hash(floor(star_uv));
	float star = step(0.986, star_seed) * smoothstep(0.38, 0.0, length(fract(star_uv) - 0.5));
	star *= smoothstep(0.38, 0.82, height) * (1.0 - cloud) * (0.55 + 0.45 * sin(TIME * 1.7 + star_seed * 70.0));
	color += vec3(0.92, 0.88, 1.0) * star * 0.85;
	// Eruptions light the crater and adjacent ash, never the entire sky.
	color += vec3(1.0, 0.60, 0.34) * flash * (crater * 1.6 + haze * cloud * 0.25);
	ALBEDO = color;
}

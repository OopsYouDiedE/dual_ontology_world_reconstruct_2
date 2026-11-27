shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform float surge_level : hint_range(0.0, 1.5) = 0.0;
uniform float seed = 0.0;
uniform vec4 blue_shift : source_color = vec4(0.32, 0.72, 1.0, 1.0);
uniform vec4 red_shift : source_color = vec4(1.0, 0.30, 0.22, 1.0);

float hash2(vec2 p) {
	p = fract(p * vec2(127.1, 311.7) + seed * 19.1);
	p += dot(p, p + 34.5);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(hash2(i), hash2(i + vec2(1.0, 0.0)), f.x),
		mix(hash2(i + vec2(0.0, 1.0)), hash2(i + vec2(1.0, 1.0)), f.x),
		f.y
	);
}

void fragment() {
	if (surge_level <= 0.01) {
		discard;
	}
	float h = clamp(1.0 - UV.y, 0.0, 1.0);
	float x = (UV.x - 0.5) * 2.0;
	float t = TIME * 1.85 + seed * 4.7;

	// Rising twisted Essence filaments with opposing red/blue chromatic phase separation
	float twist = sin(h * 7.5 - t * 2.2) * 0.22 * (0.3 + h);
	float n_blue = noise2(vec2((x + twist) * 3.2, h * 3.8 - t));
	float n_red = noise2(vec2((x - twist) * 3.2 + 1.4, h * 3.5 - t * 1.15));

	float width_mask = 1.0 - smoothstep(0.12, 0.92, abs(x + twist * 0.6) / mix(0.88, 0.34, h));
	float vert_mask = smoothstep(0.0, 0.14, h) * smoothstep(0.0, 0.55, (1.0 - h) + (n_blue - 0.45) * 0.65);

	float blue_strand = smoothstep(0.32, 0.85, n_blue) * width_mask * vert_mask;
	float red_strand = smoothstep(0.36, 0.88, n_red) * width_mask * vert_mask;

	vec3 col = blue_shift.rgb * blue_strand * 1.35 + red_shift.rgb * red_strand * 1.25;
	float alpha = clamp((blue_strand + red_strand) * 0.65 * surge_level, 0.0, 0.78);
	ALBEDO = col * surge_level;
	ALPHA = alpha;
}

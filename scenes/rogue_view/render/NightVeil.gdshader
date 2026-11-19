shader_type canvas_item;
render_mode unshaded;
uniform float fracture : hint_range(0, 1) = 0.0;
uniform float rainfall : hint_range(0, 1) = 0.0;
uniform float unrest : hint_range(0, 1) = 0.0;

float hash(float x) { return fract(sin(x * 127.1) * 43758.5453); }

void fragment() {
	vec2 p = UV - 0.5;
	float edge = smoothstep(0.28, 0.74, length(p * vec2(1.12, 0.88)));
	float column = floor(UV.x * 144.0 + UV.y * 5.0);
	float phase = fract(UV.y * 3.2 + TIME * (0.85 + hash(column + 67.0) * 0.85) + hash(column));
	float thread = smoothstep(0.32, 0.48, abs(fract(UV.x * 144.0 + UV.y * 5.0) - .5));
	float rain = thread * smoothstep(.76, .96, phase) * step(.82, hash(column - 93.0)) * rainfall;
	float pulse = 0.78 + 0.22 * sin(TIME * 3.2);
	float noise = (hash(floor(UV.y * 270.0) + floor(UV.x * 160.0) * 0.37 + floor(TIME * 11.0) * 2.0)) * 0.035;
	vec3 tint = mix(vec3(.073, .126, .17), vec3(.28, .048, .071), fracture);
	COLOR = vec4(mix(tint, vec3(.61, .83, .79), clamp(rain * 1.35, 0.0, 1.0)),
		clamp(edge * (.18 + fracture * .52 * pulse + unrest * .12) + rain * .44 + noise * (unrest + fracture), 0.0, .8));
}

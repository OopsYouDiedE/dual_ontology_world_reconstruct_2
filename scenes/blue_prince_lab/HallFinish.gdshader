shader_type spatial;

uniform vec4 pigment : source_color = vec4(0.5, 0.54, 0.6, 1.0);
uniform float grain = 0.07;
uniform float surface_roughness = 0.8;
uniform float runner = 0.0;
varying vec3 point_world;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + vec3(0.13, 0.31, 0.63));
	return fract((p.x + p.y + p.z) * p.x * p.y * p.z * 97.0);
}

float field(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = mix(hash(i), hash(i + vec3(1,0,0)), f.x);
	float b = mix(hash(i + vec3(0,1,0)), hash(i + vec3(1,1,0)), f.x);
	float c = mix(hash(i + vec3(0,0,1)), hash(i + vec3(1,0,1)), f.x);
	float d = mix(hash(i + vec3(0,1,1)), hash(i + vec3(1,1,1)), f.x);
	return mix(mix(a,b,f.y), mix(c,d,f.y), f.z);
}

void vertex() {
	point_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float mottling = 0.7 * field(point_world * 2.8) + 0.3 * field(point_world * 27.0);
	vec3 tone = pigment.rgb * (1.0 + grain * (mottling - 0.5) * 2.0);
	if (runner > 0.5) {
		float edge = abs(point_world.x);
		float rule = step(1.04, edge) * (1.0 - step(1.07, edge));
		float band = step(1.13, edge) * (1.0 - step(1.19, edge));
		vec2 repeat_cell = abs(fract(point_world.xz * vec2(8.0, 3.0)) - 0.5);
		float motif = (1.0 - step(0.3, repeat_cell.x + repeat_cell.y)) * band;
		tone *= 1.0 + 0.30 * rule - 0.24 * band + 0.38 * motif;
	}
	ALBEDO = tone;
	ROUGHNESS = surface_roughness;
}

shader_type spatial;
render_mode specular_disabled;

#include "res://scenes/blue_prince_lab/HallToon.gdshaderinc"

uniform vec4 pigment : source_color = vec4(0.5, 0.54, 0.6, 1.0);
uniform float grain = 0.07;
uniform float surface_roughness = 0.8;
uniform float runner = 0.0;
uniform float wood = 0.0;
uniform float emission_gain = 0.0;
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
	float broad = field(point_world * vec3(1.7, 1.2, 1.7));
	vec3 offset = vec3(broad * 0.51, broad * 0.29, -broad * 0.45);
	float mottling = 0.68 * field(point_world * 2.65 + offset) + 0.24 * broad
		+ 0.08 * field(point_world * vec3(15.0, 6.0, 15.0));
	vec3 tone = pigment.rgb * (1.0 + grain * (mottling - 0.5) * 2.0);
	if (runner > 0.5) {
		float stroke = field(point_world * vec3(16.0,5.0,1.3));
		float worn = smoothstep(0.79,1.17,abs(point_world.x) + 0.043 * (broad - 0.5));
		tone *= (0.89 + 0.16 * stroke) * (1.0 - 0.18 * worn);
	}
	if (wood > 0.5) {
		float stroke = field(point_world * vec3(8.0,0.65,47.0));
		tone *= 0.74 + 0.44 * stroke;
	}
	ALBEDO = tone;
	EMISSION = pigment.rgb * emission_gain;
	ROUGHNESS = surface_roughness;
}

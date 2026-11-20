shader_type spatial;

#include "res://scenes/blue_prince_lab/HallToon.gdshaderinc"

uniform vec4 pigment : source_color = vec4(0.5, 0.54, 0.6, 1.0);
uniform float grain = 0.07;
uniform float surface_roughness = 0.8;
uniform float runner = 0.0;
uniform float wood = 0.0;
uniform float emission_gain = 0.0;
uniform float pale_wash = 0.0;
uniform float vault_fill = 0.0;
uniform bool shaft_flat = false;
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
	float wash = field(point_world * vec3(1.40, 1.63, 1.09) + offset * 1.2);
	float mottling = 0.40 * field(point_world * 2.65 + offset) + 0.49 * wash
		+ 0.11 * field(point_world * vec3(15.0, 6.0, 15.0));
	vec3 tone = pigment.rgb * (1.0 + grain * (mottling - 0.5) * 2.0);
	float dry = field(vec3(point_world.x+point_world.y*.45,point_world.y,point_world.z-point_world.x*.24)*vec3(9.,1.6,4.)+offset);
	tone *= mix(vec3(.90,.92,1.), vec3(1.12,1.09,1.02),smoothstep(.2,.78,dry));
	if (runner > 0.5) {
		float stroke = field(point_world * vec3(16.0,5.0,1.3));
		float worn = smoothstep(0.79,1.17,abs(point_world.x) + 0.043 * (broad - 0.5));
		float approach = smoothstep(2.3, 8.0, point_world.z);
		float seam = smoothstep(1.141, 1.168, abs(point_world.x));
		tone *= (0.87 + 0.11 * stroke + 0.15 * wash) * (1.0 - 0.20 * worn)
			* (1.0 - 0.31 * approach) * (1.0 - 0.58 * seam);
	}
	if (wood > 0.5) {
		float stroke = field(point_world * vec3(8.0,0.65,47.0));
		tone *= 0.74 + 0.44 * stroke;
	}
	ALBEDO = tone;
	float falloff = 1.0 - smoothstep(2.6, 6.6, point_world.y);
	EMISSION = pigment.rgb * emission_gain + tone * vault_fill * smoothstep(4.95,6.2,point_world.y)
		+ pale_wash * (0.34 + 0.66 * falloff) * mix(0.93, 1.07, wash) * vec3(0.60, 0.79, 0.94);
	if (shaft_flat && toon_on) {
		vec3 world_normal = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
		vec3 key = normalize(vec3(-sign(point_world.x) * 0.99, 0.0, -0.20));
		float band = smoothstep(0.245, 0.295, dot(world_normal, key));
		vec3 cel = mix(vec3(0.41, 0.49, 0.58), vec3(0.88, 0.95, 1.02), band);
		ALBEDO = vec3(0.0);
		EMISSION = mix(pigment.rgb, tone, 0.34) * cel * 0.70;
	}
	ROUGHNESS = surface_roughness;
}

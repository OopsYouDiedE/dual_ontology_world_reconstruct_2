shader_type spatial;

#include "res://scenes/components/rendering/surfaces/HallToon.gdshaderinc"

#include "res://scenes/components/rendering/surfaces/Exposure.gdshaderinc"
uniform bool two_editions = false;

uniform vec4 pigment : source_color = vec4(0.5, 0.54, 0.6, 1.0);
uniform float grain = 0.07;
uniform float surface_roughness = 0.8;
uniform float runner = 0.0;
uniform float wood = 0.0;
uniform float emission_gain = 0.0;
uniform float pale_wash = 0.0;
uniform float vault_fill = 0.0;
uniform bool shaft_flat = false;

// Industry-standard World-Space Triplanar stylized texture pipeline (toggleable)
uniform bool use_triplanar = false;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_tex : source_color, filter_linear_mipmap, repeat_enable;
uniform float triplanar_scale = 0.42;
uniform float macro_scale = 0.09;
uniform float triplanar_detail = 0.85;
uniform float normal_strength = 0.34;

varying vec3 point_world;
varying vec3 normal_world;

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

vec3 triplanar_blend(vec3 wn) {
	vec3 w = pow(abs(wn), vec3(6.0));
	return w / max(w.x + w.y + w.z, 0.0001);
}

vec3 sample_triplanar(sampler2D tex, vec3 wp, vec3 w, float scale) {
	vec3 cx = texture(tex, wp.zy * scale).rgb;
	vec3 cy = texture(tex, wp.xz * scale).rgb;
	vec3 cz = texture(tex, wp.xy * scale).rgb;
	return cx * w.x + cy * w.y + cz * w.z;
}

vec3 sample_triplanar_normal_world(sampler2D ntex, vec3 wp, vec3 wn, vec3 w, float scale, float strength) {
	vec3 tx = texture(ntex, wp.zy * scale).xyz * 2.0 - 1.0;
	vec3 ty = texture(ntex, wp.xz * scale).xyz * 2.0 - 1.0;
	vec3 tz = texture(ntex, wp.xy * scale).xyz * 2.0 - 1.0;
	tx.xy *= strength;
	ty.xy *= strength;
	tz.xy *= strength;
	// Whiteout-style world-space normal perturbation per projection axis
	vec3 nx = vec3(wn.x, wn.y + tx.y, wn.z + tx.x * sign(wn.x));
	vec3 ny = vec3(wn.x + ty.x, wn.y, wn.z + ty.y * sign(wn.y));
	vec3 nz = vec3(wn.x + tz.x * sign(wn.z), wn.y + tz.y, wn.z);
	return normalize(nx * w.x + ny * w.y + nz * w.z);
}

void vertex() {
	point_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	normal_world = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 tone;
	float wash = 0.5;
	float broad = 0.5;
	float rough_out = surface_roughness;

	if (use_triplanar) {
		vec3 wn = normalize(normal_world);
		vec3 w = triplanar_blend(wn);
		vec3 base_tex = sample_triplanar(albedo_tex, point_world, w, triplanar_scale);
		vec3 macro = sample_triplanar(macro_tex, point_world, w, macro_scale);
		wash = dot(macro, vec3(0.299, 0.587, 0.114));
		broad = wash;
		// Blend neutral 1.0 toward sampled seamless texture according to triplanar_detail
		vec3 detail_mod = mix(vec3(1.0), base_tex, triplanar_detail);
		vec3 macro_mod = mix(vec3(1.0), macro, 0.65);
		tone = pigment.rgb * detail_mod * macro_mod;

		// Subtle world-space triplanar normal relief (keeps toon faces crisp while adding stone/wood tactility)
		if (normal_strength > 0.001) {
			vec3 perturbed_w = sample_triplanar_normal_world(normal_tex, point_world, wn, w, triplanar_scale, normal_strength);
			NORMAL = normalize((VIEW_MATRIX * vec4(perturbed_w, 0.0)).xyz);
		}
		// Subtle roughness variation derived from luminance of the painterly surface
		float tex_luma = dot(base_tex, vec3(0.299, 0.587, 0.114));
		rough_out = clamp(surface_roughness + (0.95 - tex_luma) * 0.22, 0.18, 0.98);
	} else {
		broad = field(point_world * vec3(1.7, 1.2, 1.7));
		vec3 offset = vec3(broad * 0.51, broad * 0.29, -broad * 0.45);
		wash = field(point_world * vec3(1.40, 1.63, 1.09) + offset * 1.2);
		float mottling = 0.40 * field(point_world * 2.65 + offset) + 0.49 * wash
			+ 0.11 * field(point_world * vec3(15.0, 6.0, 15.0));
		tone = pigment.rgb * (1.0 + grain * (mottling - 0.5) * 2.0);
		float dry = field(vec3(point_world.x+point_world.y*.45,point_world.y,point_world.z-point_world.x*.24)*vec3(9.,1.6,4.)+offset);
		tone *= mix(vec3(.90,.92,1.), vec3(1.12,1.09,1.02),smoothstep(.2,.78,dry));
	}

	if (runner > 0.5) {
		float stroke = field(point_world * vec3(16.0,5.0,1.3));
		float worn = smoothstep(0.79,1.17,abs(point_world.x) + 0.043 * (broad - 0.5));
		float approach = smoothstep(2.3, 8.0, point_world.z);
		float seam = smoothstep(1.141, 1.168, abs(point_world.x));
		tone *= (0.87 + 0.11 * stroke + 0.15 * wash) * (1.0 - 0.20 * worn)
			* (1.0 - 0.31 * approach) * (1.0 - 0.58 * seam);
	}
	if (wood > 0.5 && !use_triplanar) {
		float stroke = field(point_world * vec3(8.0,0.65,47.0));
		tone *= 0.74 + 0.44 * stroke;
	}
	ALBEDO = tone;
	float falloff = 1.0 - smoothstep(2.6, 6.6, point_world.y);
	EMISSION = pigment.rgb * emission_gain + tone * vault_fill * smoothstep(4.95,6.2,point_world.y)
		+ pale_wash * (0.34 + 0.66 * falloff) * mix(0.93, 1.07, wash) * vec3(0.60, 0.79, 0.94);
	if (shaft_flat && toon_on) {
		vec3 wn_flat = normalize(mat3(INV_VIEW_MATRIX) * NORMAL);
		vec3 key = normalize(vec3(-sign(point_world.x) * 0.99, 0.0, -0.20));
		float band = smoothstep(0.245, 0.295, dot(wn_flat, key));
		vec3 cel = mix(vec3(0.41, 0.49, 0.58), vec3(0.88, 0.95, 1.02), band);
		ALBEDO = vec3(0.0);
		EMISSION = mix(pigment.rgb, tone, 0.34) * cel * 0.70;
	}
	if (two_editions) {
		float margin = exposure_margin(point_world);
		if (fire_year(margin)) {
			ALBEDO *= vec3(.60,.27,.34);
			EMISSION = EMISSION * vec3(.72,.34,.40) + .065 * tone * vec3(.94,.31,.21);
		}
		EMISSION += exposure_line(margin)*vec3(.92,.48,.14);
	}
	ROUGHNESS = rough_out;
}

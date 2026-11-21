shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 sheet_color : source_color = vec4(0.22, 0.39, 0.54, 1.0);
uniform vec4 registration_ink : source_color = vec4(0.71, 0.86, 0.88, 1.0);
uniform float tile_size : hint_range(0.1, 4.0) = 1.0;
uniform bool molded_tread = false;
varying vec3 world_position;
varying vec3 world_normal;

float hash_cell(vec2 cell) {
	vec3 seed = fract(vec3(cell.xyx) * 0.1031);
	seed += dot(seed, seed.yzx + 33.33);
	return fract((seed.x + seed.y) * seed.z);
}

float value_noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash_cell(cell), hash_cell(cell + vec2(1.0, 0.0)), f.x),
		mix(hash_cell(cell + vec2(0.0, 1.0)), hash_cell(cell + vec2(1.0, 1.0)), f.x), f.y);
}

vec2 pebble(vec2 p, float footprint) {
	vec2 cell = floor(p);
	vec2 random = vec2(hash_cell(cell), hash_cell(cell + vec2(17.0, 5.0)));
	vec2 center = mix(vec2(0.35), vec2(0.65), random);
	vec2 offset = (fract(p) - center) * vec2(1.0, 1.12 + random.y * 0.24);
	float rounded = 1.0 - smoothstep(0.09, 0.29 + footprint * 0.22, length(offset));
	float coverage = 1.0 - smoothstep(0.34, 1.25, footprint);
	return vec2(rounded * coverage, random.x);
}

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 axis = abs(world_normal);
	vec2 plane = world_position.xz;
	if (axis.z > axis.y && axis.z >= axis.x) {
		plane = world_position.xy;
	} else if (axis.x > axis.y) {
		plane = world_position.zy;
	}
	vec2 tiled = plane / tile_size + vec2(0.5, 0.0);
	vec2 edge = 0.5 - abs(fract(tiled) - 0.5);
	float distance_to_joint = min(edge.x, edge.y);
	vec2 pixel = fwidth(tiled);
	float aa = max(max(pixel.x, pixel.y) * 0.62, 0.0005);
	float joint = 1.0 - smoothstep(0.010 - aa, 0.010 + aa, distance_to_joint);
	float crown = smoothstep(0.007, 0.029 + aa, distance_to_joint);
	float lip = smoothstep(0.010, 0.023 + aa, distance_to_joint) *
		(1.0 - smoothstep(0.024, 0.049 + aa, distance_to_joint));
	float cross_mark = (1.0 - smoothstep(0.011 - aa, 0.011 + aa, distance_to_joint)) *
		(1.0 - smoothstep(0.041 - aa, 0.041 + aa, max(edge.x, edge.y)));
	float footprint = max(length(fwidth(plane)), 0.0001);
	vec2 grain = pebble(plane * 68.0, footprint * 68.0);
	float tile_tone = mix(0.87, 1.12, hash_cell(floor(tiled)));
	float tone = 0.97 + grain.x * mix(0.08, 0.18, grain.y) + 0.12 * lip;
	float relief = crown * 0.0018 + grain.x * 0.00035;
	float roughness = 0.76 - lip * 0.10 + grain.x * 0.08 + joint * 0.08;
	if (molded_tread && axis.y >= max(axis.x, axis.z)) {
		// Layers at three scales: molded grip, colored rubber crumbs and burnished traffic.
		const mat2 DIAGONAL = mat2(vec2(0.94, 0.342), vec2(-0.342, 0.94));
		vec2 tread = pebble(DIAGONAL * plane * 27.0, footprint * 27.0);
		float mottling = value_noise(plane * 15.0) - 0.5;
		float flecks = value_noise(DIAGONAL * plane * 34.0 + 11.0) - 0.5;
		float wear = smoothstep(0.36, 0.70, value_noise(plane * vec2(2.1, 0.59)));
		float fleck_visibility = 1.0 - smoothstep(0.32, 1.2, footprint * 34.0);
		float tread_height = tread.x * mix(0.85, 1.07, tread.y) * (1.0 - 0.30 * wear) * crown;
		tone += mottling * 0.13 + flecks * fleck_visibility * 0.20 - 0.033 * wear + tread_height * 0.105;
		relief += tread_height * 0.00125 + mottling * 0.00048;
		roughness += 0.052 * grain.x + 0.11 * mottling - wear * 0.15;
	}
	vec3 rubber = sheet_color.rgb * tile_tone * tone;
	ALBEDO = mix(mix(rubber, sheet_color.rgb * 0.43, joint * 0.78), registration_ink.rgb, cross_mark * 0.47);
	ROUGHNESS = clamp(roughness, 0.0, 1.0);
	SPECULAR = 0.33;

	// Perturb the view-space normal from the world-projected relief, independent of the box UVs.
	vec3 u = dFdx(VERTEX);
	vec3 v = dFdy(VERTEX);
	vec3 du = cross(v, NORMAL);
	vec3 dv = cross(NORMAL, u);
	float determinant = dot(u, du);
	if (abs(determinant) > 0.00000001) {
		NORMAL = normalize(NORMAL - (du * dFdx(relief) + dv * dFdy(relief)) / determinant);
	}
}

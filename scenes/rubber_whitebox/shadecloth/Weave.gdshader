shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

void fragment() {
	float yarn = sin(UV.x * 908.0) * sin(UV.y * 510.0);
	float seams = 1.0 - smoothstep(0.0, 0.020, min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y)));
	ALBEDO = vec3(0.017, 0.016, 0.017) * (1.0 + 0.17 * yarn + seams * 0.48);
	ROUGHNESS = 0.89;
	SPECULAR = 0.30;
}

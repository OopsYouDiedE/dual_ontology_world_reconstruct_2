uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic, repeat_enable, hint_default_white;
uniform vec4 albedo_tint : source_color = vec4(1.0);
uniform bool use_vertex_color = false;
uniform vec2 uv_scale = vec2(1.0);
uniform vec2 uv_offset = vec2(0.0);
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.87;

void fragment() {
	vec3 paint = texture(albedo_texture, UV * uv_scale + uv_offset).rgb * albedo_tint.rgb;
	if (use_vertex_color) {
		paint *= COLOR.rgb;
	}
	ALBEDO = paint;
	ROUGHNESS = surface_roughness;
	SPECULAR = 0.24;
	METALLIC = 0.0;
}

void light() {
	float facing = dot(NORMAL, LIGHT);
	float diffuse = smoothstep(-0.30, 0.91, facing);
	DIFFUSE_LIGHT += LIGHT_COLOR * ATTENUATION * (diffuse * 0.46);

	vec3 half_dir = normalize(VIEW + LIGHT);
	float lobe = pow(max(dot(NORMAL, half_dir), 0.0), mix(28.0, 10.0, surface_roughness));
	// Broad, faint sheen on lit surfaces; never add an emissive outline.
	float grazing = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * lobe * diffuse * mix(0.009, 0.017, grazing);
}

shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0, 0.99, 0.97, 1.0);
uniform float surface_roughness : hint_range(0.0, 1.0) = 0.76;
uniform float surface_specular : hint_range(0.0, 1.0) = 0.22;
uniform vec3 shadow_warm_tint : source_color = vec3(0.64, 0.54, 0.52);
uniform vec3 rim_warm_color : source_color = vec3(1.0, 0.91, 0.76);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.24;
uniform float ambient_lift : hint_range(0.0, 0.5) = 0.16;

void fragment() {
	vec4 tex = texture(albedo_texture, UV) * albedo_tint;
	ALBEDO = tex.rgb;
	ROUGHNESS = surface_roughness;
	SPECULAR = surface_specular;
	METALLIC = 0.0;
	float fresnel = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	vec3 world_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float top_mask = clamp(world_normal.y * 0.45 + 0.55, 0.0, 1.0);
	EMISSION = tex.rgb * ambient_lift + rim_warm_color * (fresnel * top_mask * rim_strength * 0.35);
}

void light() {
	float ndl = dot(NORMAL, LIGHT) * 0.5 + 0.5;
	float toon_ramp = smoothstep(0.22, 0.76, ndl);
	float atten = clamp(ATTENUATION, 0.0, 1.0);
	vec3 ramp_color = mix(shadow_warm_tint, vec3(1.03, 1.0, 0.96), toon_ramp);
	DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * ramp_color * atten * 0.52;

	vec3 half_dir = normalize(VIEW + LIGHT);
	float specular_power = clamp(20.0 * pow(0.76 / max(surface_roughness, 0.04), 4.0), 2.0, 512.0);
	float spec = pow(max(dot(NORMAL, half_dir), 0.0), specular_power) * smoothstep(0.45, 0.85, ndl);
	SPECULAR_LIGHT += LIGHT_COLOR * spec * surface_specular * atten * 0.18;
}

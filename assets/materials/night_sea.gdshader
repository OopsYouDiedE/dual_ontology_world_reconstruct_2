shader_type spatial;
render_mode diffuse_lambert, specular_schlick_ggx;

// Faceted low-poly swell. Faces reflect the eruption glow toward the viewer.
uniform vec4 deep_color : source_color = vec4(0.006, 0.014, 0.022, 1.0);
uniform vec4 glow_color : source_color = vec4(1.0, 0.36, 0.12, 1.0);
uniform vec3 volcano_world = vec3(-80.0, 40.0, -300.0);
uniform float flash = 0.0;
uniform float swell = 1.0;

void vertex() {
	vec3 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float t = TIME;
	float wave = sin(world.x * 0.055 + t * 0.75) * 0.65
		+ sin(world.z * 0.085 - t * 1.05) * 0.45
		+ sin((world.x + world.z) * 0.16 + t * 1.6) * 0.18;
	VERTEX.y += wave * swell;
}

void fragment() {
	vec3 facet = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));
	if (dot(facet, VIEW) < 0.0) facet = -facet;
	NORMAL = facet;
	vec3 volcano_view = (VIEW_MATRIX * vec4(volcano_world, 1.0)).xyz;
	vec3 toward_volcano = normalize(volcano_view - VERTEX);
	vec3 mirrored = reflect(-VIEW, facet);
	float sparkle = pow(max(dot(mirrored, toward_volcano), 0.0), 20.0);
	float fresnel = pow(1.0 - clamp(dot(facet, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = deep_color.rgb;
	ROUGHNESS = 0.38;
	SPECULAR = 0.35;
	EMISSION = glow_color.rgb * (sparkle * 1.8 + fresnel * 0.05) * (1.0 + flash * 2.5);
}

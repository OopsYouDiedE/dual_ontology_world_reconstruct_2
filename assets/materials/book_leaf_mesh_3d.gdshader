shader_type spatial;
render_mode cull_back, depth_draw_opaque, diffuse_burley;

uniform sampler2D front_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D back_texture : source_color, filter_linear, repeat_disable;
// Normal / roughness are linear material data, never colors or UI glyphs.
uniform sampler2D front_normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D back_normal_texture : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D front_roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D back_roughness_texture : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool has_front_normal = false;
uniform bool has_back_normal = false;
uniform bool has_front_roughness = false;
uniform bool has_back_roughness = false;
uniform float front_normal_strength : hint_range(0.0, 1.0) = 0.25;
uniform float back_normal_strength : hint_range(0.0, 1.0) = 0.12;
uniform bool front_paper_mount = false;
// x/y = minimum UV, z/w = maximum UV; updated from the native Slip Control.
uniform vec4 front_paper_rect = vec4(0.141379, 0.131707, 0.858621, 0.858537);
uniform vec2 page_size = vec2(4.8, 6.8);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform bool reverse = false;
uniform float flexibility : hint_range(0.0, 0.9) = 0.68;
uniform float paper_roughness : hint_range(0.0, 1.0) = 0.94;
uniform vec4 edge_color : source_color = vec4(0.78, 0.76, 0.72, 1.0);
uniform vec4 surface_tint : source_color = vec4(1.0);
uniform vec4 blank_paper : source_color = vec4(0.91, 0.90, 0.86, 1.0);
// x/y = UV origin, z/w = UV extent inside each side's texture. A spread
// texture can thus feed the left and right halves of one physical leaf.
uniform vec4 front_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);
uniform vec4 back_uv_rect = vec4(0.0, 0.0, 1.0, 1.0);

varying vec2 surface_tag;

vec3 unpack_detail_normal(vec3 encoded, float strength) {
	vec2 xy = (encoded.xy * 2.0 - 1.0) * strength;
	// Reconstruct Z so imported two-channel normal textures remain valid.
	return normalize(vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.001))));
}

void vertex() {
	surface_tag = COLOR.rg;
	float t = reverse ? 1.0 - progress : progress;
	float angle = t * PI;
	// Geometry is measured from the binding, independently of the back's
	// mirrored material UV. Both skins therefore follow the exact same curve.
	float u = VERTEX.x / page_size.x;
	// The outer part of a paper leaf lags the binding. Integrating its
	// tangent gives a circular strip with constant physical arc length.
	float bend = -flexibility * sin(angle);
	float tangent_angle = angle + bend * u;
	vec3 point;
	if (t <= 0.00001) {
		point = vec3(u * page_size.x, 0.0, VERTEX.z);
		tangent_angle = 0.0;
	} else if (t >= 0.99999) {
		point = vec3(-u * page_size.x, 0.0, VERTEX.z);
		tangent_angle = PI;
	} else if (abs(bend) < 0.0001) {
		point = vec3(u * page_size.x * cos(angle), u * page_size.x * sin(angle), VERTEX.z);
	} else {
		point = vec3(
			page_size.x * (sin(tangent_angle) - sin(angle)) / bend,
			page_size.x * (cos(angle) - cos(tangent_angle)) / bend,
			VERTEX.z);
	}
	vec3 surface_normal = vec3(-sin(tangent_angle), cos(tangent_angle), 0.0);
	// Preserve each skin's thickness along the deformed normal.
	VERTEX = point + surface_normal * VERTEX.y;
	NORMAL = vec3(
		NORMAL.x * cos(tangent_angle) - NORMAL.y * sin(tangent_angle),
		NORMAL.x * sin(tangent_angle) + NORMAL.y * cos(tangent_angle),
		NORMAL.z);
	TANGENT = vec3(
		TANGENT.x * cos(tangent_angle) - TANGENT.y * sin(tangent_angle),
		TANGENT.x * sin(tangent_angle) + TANGENT.y * cos(tangent_angle),
		TANGENT.z);
	BINORMAL = vec3(
		BINORMAL.x * cos(tangent_angle) - BINORMAL.y * sin(tangent_angle),
		BINORMAL.x * sin(tangent_angle) + BINORMAL.y * cos(tangent_angle),
		BINORMAL.z);
}

void fragment() {
	bool is_edge = surface_tag.y > 0.5;
	// Surface identity is part of the mesh, not the current camera/light view.
	// Both skins already have outward normals, matching UVs and tangent frames.
	bool is_back = surface_tag.x > 0.5;
	vec2 page_uv = UV;
	vec4 paper = is_back
		? texture(back_texture, back_uv_rect.xy + page_uv * back_uv_rect.zw)
		: texture(front_texture, front_uv_rect.xy + page_uv * front_uv_rect.zw);
	vec3 detail_normal = vec3(0.0, 0.0, 1.0);
	float roughness = paper_roughness;
	if (!is_edge) {
		if (!is_back) {
			if (has_front_normal) detail_normal = unpack_detail_normal(texture(front_normal_texture, page_uv).rgb, front_normal_strength);
			if (has_front_roughness) roughness = texture(front_roughness_texture, page_uv).r;
			if (front_paper_mount) {
				vec2 near_edge = page_uv - front_paper_rect.xy;
				vec2 far_edge = front_paper_rect.zw - page_uv;
				float boundary = min(min(near_edge.x, near_edge.y), min(far_edge.x, far_edge.y));
				float aa = max(fwidth(boundary), 0.0005);
				float mount = smoothstep(-aa, aa, boundary);
				vec2 paper_uv = clamp(near_edge / max(front_paper_rect.zw - front_paper_rect.xy, vec2(0.001)), vec2(0.0), vec2(1.0));
				vec3 mount_normal = vec3(0.0, 0.0, 1.0);
				float mount_roughness = paper_roughness;
				if (has_back_normal) mount_normal = unpack_detail_normal(texture(back_normal_texture, paper_uv).rgb, back_normal_strength);
				if (has_back_roughness) mount_roughness = texture(back_roughness_texture, paper_uv).r;
				detail_normal = normalize(mix(detail_normal, mount_normal, mount));
				roughness = mix(roughness, mount_roughness, mount);
			}
		} else {
			if (has_back_normal) detail_normal = unpack_detail_normal(texture(back_normal_texture, page_uv).rgb, back_normal_strength);
			if (has_back_roughness) roughness = texture(back_roughness_texture, page_uv).r;
		}
	}
	// An unpainted UI texel remains paper, rather than a hole in the book.
	ALBEDO = is_edge ? edge_color.rgb : mix(blank_paper.rgb, paper.rgb, paper.a) * surface_tint.rgb;
	// Keep NORMAL geometric for the renderer's shadow normal bias. Godot
	// applies the material detail through the rotated mesh tangent frame.
	NORMAL_MAP = detail_normal * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	ROUGHNESS = clamp(roughness, 0.04, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.12;
}

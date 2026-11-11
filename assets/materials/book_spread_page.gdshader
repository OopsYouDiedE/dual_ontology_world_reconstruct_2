shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Open casebook spread. The UI SubViewport is drawn as ink on procedural paper.
// During a page turn either half can show a frozen snapshot of the previous page.
uniform sampler2D live_texture : source_color, filter_linear, repeat_disable;
uniform sampler2D snapshot_texture : source_color, filter_linear, repeat_disable;
uniform bool left_snapshot = false;
uniform bool right_snapshot = false;
uniform float page_fade : hint_range(0.0, 1.0) = 1.0;
uniform vec4 paper_color : source_color = vec4(0.87, 0.81, 0.69, 1.0);
uniform vec4 paper_edge : source_color = vec4(0.62, 0.50, 0.35, 1.0);
// Keeps the ink legible under the warm night lamp without flattening the paper.
uniform float reading_glow : hint_range(0.0, 1.0) = 0.22;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 uv = UV;
	bool left = uv.x < 0.5;
	bool frozen = left ? left_snapshot : right_snapshot;
	vec4 ink = frozen ? texture(snapshot_texture, uv) : texture(live_texture, uv);
	float fibre = noise(uv * vec2(320.0, 220.0)) * 0.45 + noise(uv * vec2(36.0, 25.0)) * 0.55;
	vec3 paper = paper_color.rgb * (0.93 + 0.09 * fibre);
	// Outer edges age; the gutter only darkens through the binding shadow below.
	float outer = left ? uv.x * 2.0 : (1.0 - uv.x) * 2.0;
	float edge = min(outer, min(uv.y, 1.0 - uv.y) * 1.44);
	paper = mix(paper_edge.rgb, paper, smoothstep(0.0, 0.07, edge + (fibre - 0.5) * 0.03));
	float gutter = abs(uv.x - 0.5) * 2.0;
	float binding = mix(0.52, 1.0, smoothstep(0.0, 0.10, gutter));
	vec3 color = mix(paper, ink.rgb, ink.a * page_fade) * binding;
	ALBEDO = color;
	ROUGHNESS = 0.93;
	SPECULAR = 0.12;
	EMISSION = color * reading_glow;
}

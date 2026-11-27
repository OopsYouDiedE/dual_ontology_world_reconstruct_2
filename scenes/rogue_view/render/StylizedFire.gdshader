shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform float speed = 2.6;
uniform float seed = 0.0;
uniform vec4 core_color : source_color = vec4(1.0, 0.96, 0.78, 1.0);
uniform vec4 mid_color : source_color = vec4(1.0, 0.56, 0.14, 1.0);
uniform vec4 tip_color : source_color = vec4(0.76, 0.14, 0.04, 1.0);

float hash2(vec2 p) {
	p = fract(p * vec2(127.1, 311.7) + seed * 17.3);
	p += dot(p, p + 34.5);
	return fract(p.x * p.y);
}

float noise2(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i);
	float b = hash2(i + vec2(1.0, 0.0));
	float c = hash2(i + vec2(0.0, 1.0));
	float d = hash2(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.52;
	for (int i = 0; i < 4; i++) {
		v += a * noise2(p);
		p = p * 2.05 + vec2(13.7, 7.3);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	if (intensity <= 0.01) {
		discard;
	}
	// UV.y: 0 = top tip, 1 = bottom base in Godot QuadMesh
	float h = clamp(1.0 - UV.y, 0.0, 1.0);
	float x = (UV.x - 0.5) * 2.0;

	// Upward-scrolling turbulent FBM flow for realistic flickering tongues
	float t = TIME * speed + seed * 3.1;
	float sway = sin(t * 1.4 + h * 4.5) * 0.14 * h;
	vec2 flow_uv = vec2((x + sway) * 2.1, h * 2.6 - t);
	float n1 = fbm(flow_uv);
	float n2 = fbm(flow_uv * 2.15 + vec2(2.4, -t * 0.7));
	float turb = n1 * 0.65 + n2 * 0.35;

	// Tapered teardrop flame silhouette eroded by upward turbulence
	float width_profile = mix(0.82, 0.14, pow(h, 0.82));
	float radial = abs(x + sway + (turb - 0.5) * 0.42 * h) / max(width_profile, 0.05);
	float base_fade = smoothstep(0.0, 0.14, h);
	float top_erode = smoothstep(0.0, 0.45, (1.0 - h) + (turb - 0.46) * 0.75);
	float body = (1.0 - smoothstep(0.32, 1.05, radial)) * base_fade * top_erode;

	// Blackbody temperature ramp: white-gold core -> bright amber -> crimson wisps
	float heat = clamp(body * (1.25 - h * 0.68) + (turb - 0.35) * 0.35, 0.0, 1.0);
	vec3 col = mix(tip_color.rgb, mid_color.rgb, smoothstep(0.12, 0.56, heat));
	col = mix(col, core_color.rgb, smoothstep(0.58, 0.92, heat));

	float alpha = smoothstep(0.08, 0.65, body) * intensity;
	ALBEDO = col * (1.15 + 0.85 * heat) * intensity;
	ALPHA = clamp(alpha, 0.0, 0.92);
}

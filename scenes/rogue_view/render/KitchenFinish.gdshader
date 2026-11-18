shader_type spatial;

uniform sampler2D wear_masks : repeat_enable, filter_linear_mipmap_anisotropic;
uniform vec4 base : source_color;
uniform bool timber;
varying vec3 point;
varying vec3 face;

void vertex() {
	point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	face = MODEL_NORMAL_MATRIX * NORMAL;
}

void fragment() {
	vec3 n = abs(normalize(face));
	vec2 uv = n.y > max(n.x,n.z) ? point.xz : (n.x > n.z ? point.zy : point.xy);
	vec4 mask = texture(wear_masks,uv * (timber ? vec2(0.32,2.4) : vec2(0.48,0.53)));
	float streak = timber ? mask.r * 0.48 + mask.b * 0.22 : mask.r * 0.52 + mask.g * 0.28;
	vec3 worn = timber ? base.rgb * vec3(1.18,1.09,0.96) : mix(base.rgb,vec3(0.20,0.081,0.041),mask.g * 0.40);
	ALBEDO = mix(worn,base.rgb*0.38,streak);
	ROUGHNESS = timber ? 0.61 + mask.r * 0.24 : 0.43 + mask.r * 0.36;
	METALLIC = timber ? 0.0 : 0.42 - mask.r * 0.21;
}

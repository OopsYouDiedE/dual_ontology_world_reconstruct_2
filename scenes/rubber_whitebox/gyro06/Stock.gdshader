shader_type spatial;

uniform vec4 base_tone : source_color;
uniform vec4 oxide_tone : source_color;
uniform float alloy;
uniform float grit;
uniform float mode; // 0 concrete, 1 iron, 2 bronze
varying vec3 stock;

float hash(vec3 p) {
	p = fract(p * .3183099 + vec3(.13, .27, .53));
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}
float grain(vec3 p) {
	vec3 i = floor(p), f = fract(p);
	f = f*f*(3.0-2.0*f);
	return mix(mix(mix(hash(i), hash(i+vec3(1,0,0)),f.x),mix(hash(i+vec3(0,1,0)),hash(i+vec3(1,1,0)),f.x),f.y),
		mix(mix(hash(i+vec3(0,0,1)),hash(i+vec3(1,0,1)),f.x),mix(hash(i+vec3(0,1,1)),hash(i+vec3(1,1,1)),f.x),f.y),f.z);
}
void vertex() { stock = VERTEX; }
void fragment() {
	float broad = .55*grain(stock*1.7) + .30*grain(stock*5.3) + .15*grain(stock*17.0);
	float fine = grain(stock*57.0);
	float striation = grain(stock*vec3(2,105,3));
	float oxide = smoothstep(.32, .71, broad + (fine-.5)*.16);
	vec3 color = mix(base_tone.rgb, oxide_tone.rgb, oxide);
	float pores = smoothstep(.62,.85,fine)*.16;
	if (mode < .5) {
		float formwork = smoothstep(.95,.995,fract(stock.y/.82+.25));
		color *= .94 + striation*.12 - pores - formwork*.19;
	} else {
		color *= .78 + fine*.27 + striation*.17;
	}
	ALBEDO = color;
	METALLIC = alloy;
	ROUGHNESS = grit;
}

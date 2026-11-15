shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_tint : source_color = vec4(1.0,0.99,0.97,1.0);
uniform float surface_roughness = 0.76;
uniform float surface_specular = 0.22;
uniform vec3 shadow_warm_tint : source_color = vec3(0.64,0.54,0.52);
uniform vec3 rim_warm_color : source_color = vec3(1.0,0.91,0.76);
uniform float rim_strength = 0.24;
uniform float ambient_lift = 0.16;
uniform vec3 face_origin = vec3(0.085,0.755,0.0);
uniform vec3 skin_tint : source_color = vec3(0.72,0.56,0.43);
uniform float frown = 0.0;
uniform float brow_lift = 0.0;
uniform float mouth_open = 0.0;
uniform float mouth_curve = 0.0;
uniform float eye_squeeze = 0.0;
uniform float blink = 0.0;
varying vec3 rest_position;
varying vec3 rest_normal;

void vertex() {
	rest_position = VERTEX;
	rest_normal = NORMAL;
	// Move the model's existing eyebrow vertices, retaining their native shape.
	vec3 source = textureLod(albedo_texture,UV,0.0).rgb;
	float brow = (1.0-smoothstep(0.14,0.28,max(source.r,max(source.g,source.b))));
	brow *= step(0.075,VERTEX.x)*(1.0-step(0.132,VERTEX.x));
	brow *= step(0.795,VERTEX.y)*(1.0-step(0.822,VERTEX.y));
	brow *= step(0.014,abs(VERTEX.z))*(1.0-step(0.102,abs(VERTEX.z)));
	float outer = clamp((abs(VERTEX.z)-0.025)/0.065,0.0,1.0);
	VERTEX.y += brow*(frown*mix(-0.012,0.005,outer)+brow_lift*mix(0.012,0.002,outer));
}

float segment_distance(vec2 p,vec2 a,vec2 b) {
	vec2 ab = b-a;
	return length(p-a-ab*clamp(dot(p-a,ab)/dot(ab,ab),0.0,1.0));
}

void fragment() {
	vec4 tex = texture(albedo_texture,UV)*albedo_tint;
	vec2 p = vec2(rest_position.z-face_origin.z,rest_position.y-face_origin.y);
	float face = smoothstep(face_origin.x-0.025,face_origin.x,rest_position.x);
	face *= smoothstep(0.13,0.10,abs(p.x))*smoothstep(-0.090,-0.075,p.y)*smoothstep(0.043,0.035,p.y);
	face *= smoothstep(0.15,0.55,rest_normal.x);
	vec3 face_color = skin_tint;
	float ink = 0.0;
	float whites = 0.0;
	for(int i=0;i<2;i++) {
		float side = i==0 ? -1.0 : 1.0;
		vec2 eye = p-vec2(side*0.058,0.016+brow_lift*0.003);
		float height = mix(0.014,0.004,eye_squeeze)*(1.0-blink*0.93);
		float eye_shape = max(abs(eye.x)/0.019,abs(eye.y)/height);
		ink = max(ink,1.0-smoothstep(0.88,1.06,eye_shape));
	}
	vec2 mouth = p-vec2(0.0,-0.053);
	mouth.y -= mouth_curve*0.009*pow(clamp(mouth.x/0.030,-1.0,1.0),2.0);
	float mouth_shape = length(mouth/vec2(0.023,0.0015+mouth_open*0.013));
	ink = max(ink,1.0-smoothstep(0.85,1.10,mouth_shape));
	face_color = mix(face_color,vec3(0.94,0.92,0.86),whites);
	face_color = mix(face_color,vec3(0.14,0.11,0.10),ink);
	ALBEDO = mix(tex.rgb,face_color,face);
	ROUGHNESS = surface_roughness;
	SPECULAR = surface_specular;
	float fresnel = pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),3.0);
	vec3 world_normal = normalize((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).xyz);
	float top_mask = clamp(world_normal.y*0.45+0.55,0.0,1.0);
	EMISSION = ALBEDO*ambient_lift+rim_warm_color*(fresnel*top_mask*rim_strength*0.35);
}

void light() {
	float ndl = dot(NORMAL,LIGHT)*0.5+0.5;
	float ramp = smoothstep(0.22,0.76,ndl);
	vec3 ramp_color = mix(shadow_warm_tint,vec3(1.03,1.0,0.96),ramp);
	DIFFUSE_LIGHT += ALBEDO*LIGHT_COLOR*ramp_color*clamp(ATTENUATION,0.0,1.0)*0.52;
	vec3 halfway = normalize(VIEW+LIGHT);
	float spec = pow(max(dot(NORMAL,halfway),0.0),20.0)*smoothstep(0.45,0.85,ndl);
	SPECULAR_LIGHT += LIGHT_COLOR*spec*surface_specular*ATTENUATION*0.18;
}

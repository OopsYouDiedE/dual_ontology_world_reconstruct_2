shader_type spatial;
render_mode cull_disabled, specular_disabled;
#include "res://scenes/blue_prince_lab/HallToon.gdshaderinc"

// Pigment only: silhouettes, rebates, openings, creases and window tracery are meshes.
varying vec3 place;
float hash3(vec3 u) {
	u = fract(u * .1031);
	u += dot(u, u.yzx + 33.33);
	return fract((u.x + u.y) * u.z);
}
float wash(vec3 p) {
	vec3 cell = floor(p), f = fract(p);
	f = f*f*(3.-2.*f);
	return mix(mix(mix(hash3(cell), hash3(cell+vec3(1,0,0)), f.x),
		mix(hash3(cell+vec3(0,1,0)),hash3(cell+vec3(1,1,0)),f.x), f.y),
		mix(mix(hash3(cell+vec3(0,0,1)),hash3(cell+vec3(1,0,1)),f.x),
		mix(hash3(cell+vec3(0,1,1)),hash3(cell+vec3(1)),f.x),f.y), f.z);
}
void vertex() { place = (MODEL_MATRIX * vec4(VERTEX,1.)).xyz; }
void fragment() {
	float broad = wash(place*1.4);
	float tooth = wash(place*vec3(13.,21.,7.)+broad);
	vec3 slant = vec3(place.x + place.y*.48 + place.z*.21, place.y - place.z*.34, place.z - place.x*.41);
	float daub = smoothstep(.25,.72,wash(slant*vec3(6.,1.3,3.)+broad*.7));
	float bristle = wash(slant*vec3(32.,3.1,17.) + broad*1.25);
	ALBEDO = COLOR.rgb * (.63+.31*broad+.09*tooth+.29*daub+.17*bristle) * mix(vec3(.90,.99,1.08),vec3(1.12,1.035,.89),daub);
	ROUGHNESS = .93;
}

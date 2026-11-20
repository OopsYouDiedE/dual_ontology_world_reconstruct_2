shader_type spatial;
#include "res://scenes/blue_prince_lab/HallToon.gdshaderinc"
#include "res://scenes/blue_prince_lab/vesper/Exposure.gdshaderinc"
// -1: masonry common to both years; 0: published year; 1: fire year.
uniform int edition = -1;
uniform vec4 pigment : source_color = vec4(.5,.5,.5,1.);
uniform float glow = 0.;
varying vec3 world;
void vertex(){ world=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz; }
void fragment(){
	float margin=exposure_margin(world);
	bool exposed=fire_year(margin);
	if(edition>=0 && exposed!=(edition==1)) discard;
	vec3 base=pigment.rgb;
	float tooth=fract(sin(dot(floor(world*36.),vec3(13.17,25.43,9.63)))*4736.13);
	if(edition==-1 && exposed) base=base*vec3(.60,.30,.38)+vec3(.018,.005,.007);
	ALBEDO=base*(.93+.10*tooth);
	ROUGHNESS=.82;
	float edge=exposure_line(margin);
	EMISSION=glow*base+edge*vec3(.92,.48,.14);
}

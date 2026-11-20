shader_type spatial;
render_mode cull_disabled, specular_disabled;
varying float lightness;
void vertex(){
 vec3 w=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;
 float gust=sin(w.x*.81+w.z*.46+TIME*1.8)+.42*sin(w.z*2.3+TIME*2.7);
 VERTEX.x+=UV.y*UV.y*.063*gust; VERTEX.z+=UV.y*.026*gust;
 lightness=INSTANCE_CUSTOM.r*.31+.13*sin(w.x*.62+sin(w.z*.53));
}
void fragment(){
 vec3 moss=mix(vec3(.035,.078,.048),vec3(.16,.238,.122),UV.y*.78+lightness*.48);
 ALBEDO=moss*(.70+lightness+.22*UV.y); EMISSION=moss*(.12+.21*UV.y); ROUGHNESS=1.;
}

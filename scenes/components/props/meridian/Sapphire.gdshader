shader_type spatial;
render_mode unshaded, cull_back, depth_draw_never;
void fragment(){
 float edge = pow(1.0-max(0.,dot(normalize(NORMAL),normalize(VIEW))),3.0);
 ALBEDO=vec3(.65,.78,.87); ALPHA=.012+.26*edge;
}

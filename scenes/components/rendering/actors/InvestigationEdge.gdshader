shader_type spatial;
render_mode unshaded,cull_front,shadows_disabled;
void vertex(){vec4 p=PROJECTION_MATRIX*MODELVIEW_MATRIX*vec4(VERTEX,1.);vec3 n=MODELVIEW_NORMAL_MATRIX*NORMAL;vec2 dir=(PROJECTION_MATRIX*vec4(n,0.)).xy;POSITION=p;POSITION.xy+=dir/max(length(dir),.001)*1.9*p.w/VIEWPORT_SIZE;POSITION.z-=.000025*p.w;}
void fragment(){ALBEDO=vec3(.046,.039,.040);}

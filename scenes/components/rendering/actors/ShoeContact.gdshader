shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled, depth_draw_never;
void fragment(){vec2 p=(UV-.5)*2.;float d=dot(p,p);ALBEDO=vec3(.040,.043,.054);ALPHA=.40*(1.-smoothstep(.03,1.,d));}

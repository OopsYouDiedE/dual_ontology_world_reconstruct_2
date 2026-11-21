shader_type spatial;
render_mode cull_disabled;
varying vec3 wp;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.)).xyz;}
void fragment(){vec2 p=wp.xz;float grid=min(abs(fract(p.x+.5)-.5),abs(fract(p.y+.5)-.5));float seam=1.-smoothstep(.009,.021,grid);float ring=1.-smoothstep(.018,.038,abs(length(p)-8.84));float stripe=1.-smoothstep(.015,.035,abs(length(p)-3.28));float dots=step(.38,fract(atan(p.x,p.y)*64.0/6.283));vec3 base=mix(vec3(.155,.18,.18),vec3(.097,.118,.118),seam);ALBEDO=mix(base,vec3(.59,.42,.21),max(ring,stripe*dots)*.86);ROUGHNESS=.83;}

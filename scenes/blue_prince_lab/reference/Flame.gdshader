shader_type spatial;
render_mode unshaded,cull_disabled;
uniform float phase;
uniform vec4 ember : source_color;
uniform vec4 tip : source_color;
void vertex(){float h=1.-UV.y;float p=phase+TIME*6.8;VERTEX.x+=h*h*(sin(p+h*3.)*.105+sin(p*1.8)*.04);VERTEX.z+=h*h*cos(p*1.27+h)*.087;VERTEX.y*=.94+.17*sin(p)+.09*cos(p*1.87);}
void fragment(){ALBEDO=mix(ember.rgb,tip.rgb,smoothstep(.17,.90,1.-UV.y))*1.65;}

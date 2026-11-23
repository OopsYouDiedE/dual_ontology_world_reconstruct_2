shader_type spatial;
render_mode cull_disabled, specular_disabled;
uniform vec4 pigment : source_color = vec4(1.);
uniform vec4 secondary : source_color = vec4(1.);
uniform sampler2D textile : source_color, hint_default_white, filter_linear_mipmap;
// 0 accessory, 1 detective coat, 2 Vale waistcoat, 4 eyes, 5 hair
uniform int part = 0;
varying float elevation;
void vertex(){ elevation=VERTEX.y; }
void fragment(){
 vec3 tex=texture(textile,UV).rgb;
 vec3 col=pigment.rgb;
 if(part==1 || part==2){col=mix(secondary.rgb,pigment.rgb,COLOR.r);col*=.80+.40*sqrt(dot(tex,vec3(.30,.59,.11)));}
 if(part==2){col=mix(vec3(.112,.123,.132),col,COLOR.g);}
 if(part==6){float seam=abs(fract(UV.x*2.+.5)-.5);col*=mix(.77,1.,smoothstep(.002,.012,seam));}
 if(part==3){col=tex*pigment.rgb;}
 if(part==4){col=tex*pigment.rgb;}
 if(part==5){col*=mix(.82,1.18,smoothstep(.42,.50,UV.y)*(1.-smoothstep(.53,.60,UV.y)));}
 ALBEDO=col*(part==3?1.:mix(.85,1.,smoothstep(.08,1.45,elevation)));ROUGHNESS=.95;SPECULAR=0.;
}
void light(){
 float d=dot(NORMAL,LIGHT);float band=smoothstep(.16,.20,d);float high=smoothstep(.65,.69,d);
 vec3 tone=mix(vec3(.31,.36,.47),vec3(.77,.76,.72),band);
 tone=mix(tone,vec3(1.),high);if(part==3){tone=mix(vec3(.49,.45,.48),vec3(.94,.73,.65),step(.12,d));tone=mix(tone,vec3(1.),step(.20,d));}float rim=smoothstep(.82,.91,1.-max(dot(NORMAL,VIEW),0.))*smoothstep(.08,.5,d);
 DIFFUSE_LIGHT+=(tone+vec3(.09,.10,.12)*rim)*(floor(ATTENUATION*3.99)/3.)*LIGHT_COLOR/PI;
}

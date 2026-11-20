shader_type sky;
float hash(vec2 p) {return fract(sin(dot(p,vec2(72.31,111.37)))*43758.5453);}
float value(vec2 p) {vec2 i=floor(p),f=fract(p); f=f*f*(3.-2.*f);return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1)),f.x),f.y);}
void sky() {
 vec2 p=EYEDIR.xz/max(.09,EYEDIR.y+.19)*2.4;
 float clouds=.58*value(p)+.28*value(p*2.1)+.14*value(p*5.3);
 COLOR=mix(vec3(.055,.16,.29),vec3(.16,.29,.42),clouds)*mix(1.,.73,clamp(EYEDIR.y,0.,1.));
}

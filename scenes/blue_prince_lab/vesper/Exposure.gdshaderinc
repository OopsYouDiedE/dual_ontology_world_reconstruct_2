uniform vec3 source;
uniform vec3 axis;
uniform float cone_cos;
uniform float reach;
uniform bool shutter_open;
uniform bool cinder;
float exposure_margin(vec3 world){
	vec3 ray=world-source;
	return min(dot(ray,axis)-length(ray)*cone_cos,reach-length(ray));
}
bool fire_year(float margin){return cinder != (shutter_open && margin>=0.);}
float exposure_line(float margin){return shutter_open ? 1.-smoothstep(.004,.024,abs(margin)) : 0.;}

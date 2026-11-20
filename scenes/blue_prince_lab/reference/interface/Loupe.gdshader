shader_type canvas_item;
uniform sampler2D image : hint_screen_texture, repeat_disable, filter_linear;
uniform float zoom = 2.0;
void fragment(){vec2 q=UV-.5;float d=length(q);if(d>.5)discard;vec2 center=SCREEN_UV-q*vec2(dFdx(SCREEN_UV.x)/dFdx(UV.x),dFdy(SCREEN_UV.y)/dFdy(UV.y));vec3 c=texture(image,center+(SCREEN_UV-center)/zoom).rgb*vec3(1.04,1.05,1.00);if(d>.465)c=mix(vec3(.16,.15,.13),vec3(.62,.56,.39),smoothstep(.03,.97,.5+.47*cos((d-.465)*225.)+.20*dot(q,vec2(-1.,-1.))));if(d>.492||abs(d-.466)<.003)c=vec3(.10,.095,.09);COLOR=vec4(c,1.);}

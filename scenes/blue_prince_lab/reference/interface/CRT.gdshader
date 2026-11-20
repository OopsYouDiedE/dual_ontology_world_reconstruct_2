shader_type spatial;
render_mode unshaded,cull_disabled;
uniform sampler2D feed : source_color,filter_linear_mipmap;
uniform vec2 tile;
uniform float channel;
void fragment(){vec2 p=UV;float vignette=1.-.32*dot(p-.5,p-.5)*2.;vec2 uv=(tile+clamp(p,.005,.995))/vec2(4.,2.);float v=dot(texture(feed,uv).rgb,vec3(.29,.57,.14));v=pow(v,.62);float glow=.88+.06*sin(UV.y*291.)+.09*exp(-abs(fract(TIME*.14+channel)-UV.y)*26.);ALBEDO=mix(vec3(.009,.037,.024),vec3(.39,1.24,.52),v)*glow*vignette;}

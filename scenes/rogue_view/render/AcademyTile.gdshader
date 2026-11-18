shader_type spatial;
uniform vec4 glaze : source_color = vec4(0.37, 0.32, 0.25, 1.0);
uniform bool wall = false;
varying vec3 p;
varying vec3 face;
void vertex(){ p = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; face = MODEL_NORMAL_MATRIX * NORMAL; }
void fragment(){
    vec2 uv = !wall ? p.xz : vec2(abs(face.z)>abs(face.x) ? p.x : p.z, p.y);
    vec2 grid = uv * 2.0;
    vec2 cell = floor(grid);
    vec2 local = abs(fract(grid)-0.5);
    float edge = 0.5-max(local.x,local.y);
    float aa = clamp(max(fwidth(grid.x),fwidth(grid.y)),0.001,0.18);
    float tile = smoothstep(0.012-aa*0.5,0.044+aa*0.5,edge);
    float variation = fract(sin(dot(cell,vec2(12.9898,78.233)))*4375.54);
    float diamond = 1.0-smoothstep(0.17-aa,0.20+aa,local.x+local.y);
    float motif = wall && cell.y == 3.0 ? diamond : 0.0;
    vec3 pigment = glaze.rgb * (0.87+0.15*variation) * (1.0-0.56*motif);
    ALBEDO = mix(glaze.rgb*0.42,pigment,tile);
    ROUGHNESS = mix(0.94,0.40+0.14*variation+0.09*motif,tile);
    float height = 0.0028*tile+0.0006*motif;
    vec3 dx = dFdx(VERTEX), dy = dFdy(VERTEX);
    vec3 r1 = cross(dy,NORMAL), r2 = cross(NORMAL,dx);
    float det = dot(dx,r1);
    NORMAL = normalize(NORMAL - sign(det)*(r1*dFdx(height)+r2*dFdy(height))/max(abs(det),0.0000001));
}

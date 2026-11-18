shader_type spatial;
uniform vec4 glaze : source_color = vec4(0.37, 0.32, 0.25, 1.0);
uniform bool wall = false;
uniform bool kitchen_weathering = false;
uniform sampler2D wear_masks : repeat_enable, filter_linear_mipmap_anisotropic;
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
    float relief = 0.0028*tile+0.0006*motif;
    float rough = 0.40+0.14*variation+0.09*motif;
    vec3 joint = glaze.rgb*0.42;
    if (kitchen_weathering) {
        // One architectural coordinate frame keeps wear continuous across mesh cuts.
        vec4 masks = texture(wear_masks,uv*vec2(0.36,0.31)+vec2(0.13,0.58));
        float range_distance = distance(p.xz,vec2(0.9,2.2));
        float hearth = 1.0-smoothstep(0.15,2.45,range_distance);
        float door_distance = abs(p.x-6.4);
        float cold_track = (1.0-smoothstep(0.30,1.15,door_distance))*
            (1.0-smoothstep(1.0,4.6,abs(p.z+2.0)));
        float drip = masks.g*(0.23+0.34*(1.0-smoothstep(0.15,1.9,p.y)));
        float dirt = wall ? clamp(0.22*masks.r+0.52*hearth*masks.r+drip,0.0,0.83) :
            clamp(0.32*masks.r+0.44*hearth*masks.r,0.0,0.76);
        float wear = masks.b*(1.0-smoothstep(0.03,0.16,edge));
        float damp = wall ? 0.0 : cold_track*smoothstep(0.2,0.84,masks.a);
        pigment = mix(pigment,pigment*vec3(0.33,0.28,0.23),dirt);
        pigment = mix(pigment,pigment*vec3(0.69,0.79,0.81),damp*0.37);
        pigment *= 1.0-wear*0.37;
        joint *= 1.0-dirt*0.41;
        rough = mix(clamp(rough+dirt*0.32+wear*0.18,0.0,1.0),0.21,damp*0.94);
        relief -= wear*0.0006;
    }
    ALBEDO = mix(joint,pigment,tile);
    ROUGHNESS = mix(0.94,rough,tile);
    float height = relief;
    vec3 dx = dFdx(VERTEX), dy = dFdy(VERTEX);
    vec3 r1 = cross(dy,NORMAL), r2 = cross(NORMAL,dx);
    float det = dot(dx,r1);
    NORMAL = normalize(NORMAL - sign(det)*(r1*dFdx(height)+r2*dFdy(height))/max(abs(det),0.0000001));
}

shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;

uniform float wind = 0.0;
uniform float intensity = 1.0;
uniform float flame_height = 1.15;
uniform float flame_radius = 0.17;
varying float flame_t;

void vertex() {
    float t = clamp(VERTEX.y / flame_height + .5, 0.0, 1.0);
    flame_t = t;
    float radial_length = length(VERTEX.xz);
    vec2 radial = radial_length > .00001 ? VERTEX.xz / radial_length : vec2(1.0, 0.0);
    // Broad below the middle and tapering to a narrow, bent wick-flame tip.
    float profile = flame_radius * pow(max(sin(t * PI), 0.0), .72) * pow(max(1.0 - t, 0.0), .48);
    VERTEX.xz = radial * profile;
    VERTEX.x += wind * flame_height * .16 * t * t;
    VERTEX.z += wind * flame_height * .055 * t * t * t;
    // The facing/opacity response must follow the deformed flame surface.
    // Differentiate the radial profile and centreline, with bounded pole terms.
    float nt = clamp(t, .001, .999);
    float nr = flame_radius * pow(sin(nt * PI), .72) * pow(1.0 - nt, .48);
    float dr = nr * (.72 * PI * cos(nt * PI) / sin(nt * PI) - .48 / (1.0 - nt));
    vec3 along = vec3(radial.x * dr + wind * flame_height * .32 * nt,
                      flame_height,
                      radial.y * dr + wind * flame_height * .165 * nt * nt);
    vec3 around = vec3(-radial.y, 0.0, radial.x);
    NORMAL = normalize(cross(along, around));
}

void fragment() {
    float facing = clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0);
    float center = pow(facing, 2.5) * (1.0 - smoothstep(.52, .95, flame_t));
    vec3 amber = mix(vec3(1.0, .18, .012), vec3(1.0, .57, .12), smoothstep(.04, .36, flame_t));
    vec3 fire = mix(amber, vec3(1.0, .91, .60), center);
    ALBEDO = vec3(0.0);
    EMISSION = fire * (2.8 + center * 1.2) * intensity;
    ALPHA = smoothstep(.0, .28, facing) * smoothstep(.005, .065, flame_t) * (1.0 - smoothstep(.975, 1.0, flame_t));
}

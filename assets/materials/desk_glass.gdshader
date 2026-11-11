shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_back, diffuse_burley, specular_schlick_ggx;

// Real transparent geometry with live light and captured environment response.
// The center stays transparent; no painted window or opaque screen-space copy.
uniform vec4 glass_tint : source_color = vec4(.91, .86, .72, 1.0);
uniform float base_opacity : hint_range(0.0, 1.0) = .025;
uniform float edge_opacity : hint_range(0.0, 1.0) = .32;
uniform float glass_roughness : hint_range(0.0, 1.0) = .10;
uniform float waviness = .003;
varying vec3 local_point;

void vertex() { local_point = VERTEX; }

void fragment() {
    float wavex = sin(local_point.y * 21.0 + local_point.z * 13.0) * waviness;
    float wavey = sin(local_point.x * 27.0 - local_point.y * 11.0) * waviness;
    vec3 n = normalize(NORMAL + vec3(wavex, wavey, 0.0));
    float grazing = pow(1.0 - clamp(dot(n, VIEW), 0.0, 1.0), 4.0);
    NORMAL = n;
    ALBEDO = glass_tint.rgb;
    ALPHA = clamp(base_opacity + edge_opacity * grazing, 0.0, .68);
    ROUGHNESS = glass_roughness + .015 * sin(local_point.y * 31.0 + local_point.x * 17.0);
    METALLIC = 0.0;
    SPECULAR = .70;
    CLEARCOAT = .25;
    CLEARCOAT_ROUGHNESS = .08;
}

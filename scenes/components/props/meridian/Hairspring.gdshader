shader_type spatial;
render_mode cull_disabled;
// UV.x measures distance along the four turns, from collet to fixed stud.
uniform float balance_angle = 0.0;
void vertex() {
    float u = UV.x;
    float a = (1.0-u)*balance_angle;
    mat2 twist = mat2(vec2(cos(a),sin(a)), vec2(-sin(a),cos(a)));
    float breathe = 1.0 + (balance_angle/(8.0*PI))*sin(PI*u);
    VERTEX.xy = twist * VERTEX.xy * breathe;
    NORMAL.xy = twist * NORMAL.xy;
}
void fragment() {
    ALBEDO = vec3(.48,.58,.65);
    METALLIC = .66;
    ROUGHNESS = .32;
}

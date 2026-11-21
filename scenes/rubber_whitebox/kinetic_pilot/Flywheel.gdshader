shader_type spatial;
render_mode cull_disabled;
varying vec3 p;
void vertex(){p=VERTEX;}
void fragment(){
    float h=p.y,r=length(p.xz);
    vec3 brass=vec3(.54,.32,.10),oxide=vec3(.38,.047,.022),petrol=vec3(.032,.145,.155),ivory=vec3(.63,.50,.29);
    vec3 col=brass;
    if(h<-.18)col=mix(brass,petrol,smoothstep(-1.02,-1.,h));
    if(h>-.135&&h<.102)col=oxide;
    if(h>=.102&&h<.153)col=petrol;
    if(h>.162&&h<.23)col=ivory;
    if(h>3.78)col=oxide;
    // Narrow index marks read self-spin against the wider precession of the shadow.
    float i=mod(atan(p.z,p.x)+6.283185,6.283185/44.);
    if(h>.11&&h<.16&&i<.005)col=brass;
    ALBEDO=col*(.986+.014*cos(r*151.)); METALLIC=.36;ROUGHNESS=.36;
}
